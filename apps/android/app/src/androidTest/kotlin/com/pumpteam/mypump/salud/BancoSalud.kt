package com.pumpteam.mypump.salud

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import com.pumpteam.mypump.datos.FuenteSalud
import com.pumpteam.mypump.datos.HistorialSalud
import com.pumpteam.mypump.datos.PermisosSalud
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.reglas.RelojLocal
import java.util.Collections
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/**
 * El plugin de la Capacitor como lo llama el bridge: un método (`readSamples`…) con sus opciones, y lo que resuelve. Lo
 * implementa `banco/PluginCapgo` (src/bancoSalud), que se compila solo si está el plugin de node_modules.
 */
interface PluginDeLaCapacitor {
    suspend fun llamar(metodo: String, opciones: JSONObject): JSONObject
}

/** Un `call.reject(mensaje)` del plugin. */
class RechazoDelPlugin(mensaje: String?) : Exception(mensaje)

/** Una consulta al plugin, como la ve el bridge: el método, el tipo y las puntas en ms (`toISOString` de cada lado). */
data class Consulta(val metodo: String, val dataType: String?, val desde: Double?, val hasta: Double?, val extra: String = "") {
    override fun toString() = "$metodo ${dataType ?: ""} ${desde?.let(RelojLocal::iso) ?: ""} → ${hasta?.let(RelojLocal::iso) ?: ""} $extra".trim()
}

/**
 * El banco de Android (gemelo de scripts/nativa/salud-banco.sh): el healthkit-bridge.js de origin/main corriendo en un
 * WebView como en la Capacitor (plataforma `android`, el reloj fijo en [ahora]), con el plugin de VERDAD contestando
 * contra el Health Connect del emulador. Devuelve las consultas que hizo, los lotes que mandó a `ingest_salud` e
 * `ingest_entrenos` y cómo dejó su localStorage. Otro origen que el de la Capacitor (`https://localhost`): no toca lo que
 * lee la migración.
 */
class BridgeEnWebView(private val app: Context, private val plugin: PluginDeLaCapacitor, private val ahora: Long) {
    class Resultado(val consultas: List<Consulta>, val crudo: ValorJson)

    private val principal = Handler(Looper.getMainLooper())
    private val consultas: MutableList<Consulta> = Collections.synchronizedList(ArrayList())
    private val fin = CompletableDeferred<String>()
    private val alcance = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var vista: WebView? = null

    /** Lo que llama el JavaScript (en el hilo del puente de Java; contesta por `__resolver` en el principal). */
    inner class Puente {
        @JavascriptInterface
        fun llamar(id: Int, metodo: String, opciones: String) {
            val o = JSONObject(opciones)
            consultas += Consulta(
                metodo, o.optString("dataType").ifEmpty { null },
                o.optString("startDate").ifEmpty { null }?.let { RelojLocal.desdeIso(it) },
                o.optString("endDate").ifEmpty { null }?.let { RelojLocal.desdeIso(it) },
                extra(metodo, o),
            )
            alcance.launch {
                val r = try {
                    Result.success(plugin.llamar(metodo, o).toString())
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Result.failure(e)
                }
                val js = "__resolver($id, ${r.isSuccess}, ${JSONObject.quote(r.getOrNull() ?: (r.exceptionOrNull()?.message ?: "error"))})"
                principal.post { vista?.evaluateJavascript(js, null) }
            }
        }

        @JavascriptInterface
        fun fin(json: String) {
            fin.complete(json)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    suspend fun conectar(puente: String, esperaMs: Long = 600_000): Resultado {
        val cargada = CompletableDeferred<Unit>()
        withContext(Dispatchers.Main) {
            val w = WebView(app)
            vista = w
            w.settings.javaScriptEnabled = true
            w.settings.domStorageEnabled = true
            w.addJavascriptInterface(Puente(), "Banco")
            w.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(m: ConsoleMessage): Boolean = true
            }
            w.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    cargada.complete(Unit)
                }
            }
            w.loadDataWithBaseURL("$ORIGEN/", "<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>", "text/html", "utf-8", null)
        }
        try {
            withTimeout(30_000) { cargada.await() }
            withContext(Dispatchers.Main) {
                val w = vista!!
                w.evaluateJavascript(preparacion(ahora), null)
                w.evaluateJavascript(puente, null)
                w.evaluateJavascript(CONECTAR, null)
            }
            val json = withTimeout(esperaMs) { fin.await() }
            return Resultado(consultas.toList(), ValorJson.parsear(json))
        } finally {
            withContext(Dispatchers.Main) {
                vista?.destroy()
                vista = null
                WebStorage.getInstance().deleteOrigin(ORIGEN)
            }
            alcance.cancel()
        }
    }

    companion object {
        const val ORIGEN = "https://banco-salud.invalid"

        /** Lo que no son las puntas y distingue una consulta (las tandas de permisos, la agregación, el límite). */
        fun extra(metodo: String, o: JSONObject): String = when (metodo) {
            "requestAuthorization", "checkAuthorization" ->
                (o.optJSONArray("read")?.let { a -> (0 until a.length()).joinToString(",") { a.getString(it) } } ?: "") +
                    if (o.optBoolean("requestHistoryAccess")) " +historial" else ""
            "queryAggregated" -> "${o.optString("bucket")}/${o.optString("aggregation")}"
            "readSamples" -> "limit=${o.optInt("limit")} asc=${o.optBoolean("ascending")}"
            else -> ""
        }

        /**
         * El reloj fijo (como `DateFalsa` de vectores-salud.mjs), el plugin por el puente con promesas, la base que anota
         * los lotes, y el localStorage vacío con el token (el bridge lo lee de ahí).
         */
        fun preparacion(ahora: Long) = """
            (function () {
              const R = Date, A = $ahora;
              class F extends R { constructor(...a) { if (a.length === 0) super(A); else super(...a); } static now() { return A; } }
              window.Date = F;
              localStorage.clear();
              localStorage.setItem('mypump_token', 'tok-banco-salud');
              window.__n = 0; window.__pendientes = {};
              const llamar = (metodo, o) => new Promise((res, rej) => {
                const id = ++window.__n; window.__pendientes[id] = { res, rej };
                Banco.llamar(id, metodo, JSON.stringify(o || {}));
              });
              window.__resolver = (id, ok, json) => {
                const p = window.__pendientes[id]; delete window.__pendientes[id];
                if (ok) p.res(JSON.parse(json)); else p.rej(new Error(json));
              };
              const metodos = ['isAvailable', 'requestAuthorization', 'checkAuthorization', 'readSamples', 'queryAggregated', 'queryWorkouts'];
              const Health = {}; metodos.forEach(m => { Health[m] = (o) => llamar(m, o); });
              window.Capacitor = { isNativePlatform: () => true, getPlatform: () => 'android', Plugins: { Health } };
              window.__lotes = []; window.__entrenos = [];
              window.mypumpDB = {
                ingestSalud: async (t, regs) => { window.__lotes.push(regs); return { success: true, data: regs.length }; },
                ingestEntrenos: async (t, ws) => { window.__entrenos.push(ws); return { success: true, data: ws.length }; },
              };
            })(); 'ok'
        """.trimIndent()

        const val CONECTAR = """
            (async function () {
              try {
                const r = await window.MyPumpHealth.connect({ esperarBackfill: true });
                const estado = {};
                for (let i = 0; i < localStorage.length; i++) {
                  const k = localStorage.key(i);
                  if (k.indexOf('mypump_health_') === 0) estado[k] = localStorage.getItem(k);
                }
                Banco.fin(JSON.stringify({ ok: true, resultado: { ok: r.ok, preguntados: r.preguntados, total: r.total, sinDatos: r.sinDatos },
                  lotes: window.__lotes, entrenos: window.__entrenos, estado: estado, historial: window.MyPumpHealth.historialAndroid() }));
              } catch (e) { Banco.fin(JSON.stringify({ ok: false, error: String((e && e.stack) || e) })); }
            })(); 'ok'
        """
    }
}

/**
 * Deja [texto] en `/data/local/tmp/[nombre]` (el informe del banco: la app y su carpeta se van cuando Gradle la desinstala).
 * Por la entrada de `tee`, sin pasar por una línea de comandos.
 */
fun guardarEnTmp(nombre: String, texto: String) {
    val (salida, entrada) = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommandRw("tee /data/local/tmp/$nombre")
    android.os.ParcelFileDescriptor.AutoCloseOutputStream(entrada).use { it.write(texto.toByteArray()) }
    android.os.ParcelFileDescriptor.AutoCloseInputStream(salida).use { it.readBytes() }
}

/** La fuente de verdad, anotando cada consulta con el nombre y las opciones que tendría en el plugin. */
class FuenteQueAnota(private val f: FuenteSalud) : FuenteSalud by f {
    val consultas: MutableList<Consulta> = Collections.synchronizedList(ArrayList())
    private fun lista(t: List<String>) = t.joinToString(",")

    override suspend fun disponible(): Boolean = f.disponible().also { consultas += Consulta("isAvailable", null, null, null) }

    override suspend fun pedirLectura(tipos: List<String>) {
        consultas += Consulta("requestAuthorization", null, null, null, lista(tipos))
        f.pedirLectura(tipos)
    }

    override suspend fun pedirLecturaConHistorial(tipos: List<String>): HistorialSalud? {
        consultas += Consulta("requestAuthorization", null, null, null, lista(tipos) + " +historial")
        return f.pedirLecturaConHistorial(tipos)
    }

    override suspend fun permisos(tipos: List<String>): PermisosSalud {
        consultas += Consulta("checkAuthorization", null, null, null, lista(tipos))
        return f.permisos(tipos)
    }

    override suspend fun historial(): HistorialSalud? {
        consultas += Consulta("checkAuthorization", null, null, null, lista(PuenteSalud.nucleo) + " +historial")
        return f.historial()
    }

    override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> {
        consultas += Consulta("queryAggregated", dataType, desde, hasta, "day/$agregacion")
        return f.agregado(dataType, agregacion, desde, hasta)
    }

    override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> {
        consultas += Consulta("readSamples", dataType, desde, hasta, "limit=$limite asc=true")
        return f.muestras(dataType, desde, hasta, limite)
    }

    override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> {
        consultas += Consulta("queryWorkouts", null, desde, hasta)
        return f.entrenos(desde, hasta)
    }

    override val plataforma: PlataformaSalud get() = f.plataforma
}
