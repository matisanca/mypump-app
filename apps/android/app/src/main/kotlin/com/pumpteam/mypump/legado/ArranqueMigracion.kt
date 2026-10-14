package com.pumpteam.mypump.legado

import android.content.Context
import android.os.Build
import android.util.Log
import com.pumpteam.mypump.datos.AlmacenToken
import com.pumpteam.mypump.datos.ConteosRpc
import com.pumpteam.mypump.datos.EjecutorLegado
import com.pumpteam.mypump.datos.EntornoLegado
import com.pumpteam.mypump.datos.FaseRemotaLegado
import com.pumpteam.mypump.datos.LevelDbLegado
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.PalancaRemota
import com.pumpteam.mypump.datos.Preferencias
import com.pumpteam.mypump.datos.ReciboEnServidor
import java.io.File
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Todo el arranque de la migración del almacenamiento viejo (gemelo de ArranqueMigracion.swift): la 2.0.0 sale como
 * update de la app Capacitor y tiene que levantar lo que ella dejó en el `localStorage` del WebView sin perder nada.
 *
 * 1. **Fase L**, local y sin red, ANTES de crear el modelo: el modelo lee el token y su cola del disco al iniciar. Si
 *    corriera después, arrancaría sin cuenta y mostraría "pegá tu link" a alguien que ya tenía todo. En Android la lectura
 *    es un WebView (hilo principal, asíncrono): el modelo se crea cuando termina, y mientras tanto se ve la marca. Si
 *    falla, el modelo se crea igual y la Fase L se reintenta con la cuenta viva.
 * 2. Con la primera carga con red del modelo (modelo listo, no desde la copia offline, no demo): la palanca remota y la
 *    **Fase R** (validar las ops sin sesión contra la rutina activa, reasignar tokens rotados, recibo).
 * 3. La **escritura de vuelta**, una vez: saca del `localStorage` lo que ya tomó la nativa y deja la marca; el arranque
 *    siguiente la confirma leyéndola.
 * 4. Los recibos que quedaron solo en el disco, otra vez al servidor.
 *
 * Si alguien vuelve a la Capacitor (plan B, reinstalación) y después a la nativa, la huella del leveldb cambia y se
 * repite. El libro mayor evita duplicados.
 */
internal object ArranqueMigracion {
    /** Una Fase L por vez: la del arranque y la de un reintento no se pisan. */
    private val candado = Mutex()

    fun entorno(app: Context): EntornoLegado =
        EntornoLegado(app.filesDir, LectorWebView(app.applicationContext, anotar = { RegistroLegado.anotar(app, it) }))

    /** "2.0.0 (100)", como `CFBundleShortVersionString (CFBundleVersion)` en iOS: va en el recibo y en la marca. */
    fun version(app: Context): String = try {
        val i = app.packageManager.getPackageInfo(app.packageName, 0)
        @Suppress("DEPRECATION")
        val codigo = if (Build.VERSION.SDK_INT >= 28) i.longVersionCode else i.versionCode.toLong()
        "${i.versionName ?: "?"} ($codigo)"
    } catch (_: Exception) {
        "? (?)"
    }

    /**
     * Corre la Fase L (si corresponde), crea el modelo con [crear] y deja andando el resto en [alcance]. El almacén del
     * token y los ajustes son LOS MISMOS que usa el modelo.
     */
    suspend fun arrancar(app: Context, almacen: AlmacenToken, ajustes: Preferencias, alcance: CoroutineScope, crear: () -> ModeloApp): ModeloApp {
        val entorno = entorno(app)
        val hecha = candado.withLock { faseLocal(app, entorno, almacen, ajustes, cuentaViva = null) } != null
        val modelo = crear()
        alcance.launch { seguir(app, entorno, almacen, ajustes, modelo, hecha) }
        return modelo
    }

    /** null = falló la lectura (se reintenta; no es lo mismo que "no había nada"). */
    private suspend fun faseLocal(app: Context, entorno: EntornoLegado, almacen: AlmacenToken, ajustes: Preferencias, cuentaViva: String?): EjecutorLegado.Resultado? =
        try {
            val r = withContext(Dispatchers.IO) { EjecutorLegado.faseLocal(entorno, almacen, ajustes, cuentaViva = cuentaViva) }
            if (r.corrio) {
                val donde = LevelDbLegado.ubicar(app.dataDir).joinToString(" + ") { LevelDbLegado.relativa(it, app.dataDir) }
                RegistroLegado.anotar(
                    app,
                    "Fase L corrida ${r.corrida}${if (r.repeticion) " (repetición)" else ""}: token ${if (r.adoptoToken) "adoptado" else "sin cambios"}, " +
                        "cola ${r.aLaCola}, por validar ${r.porValidar}, estacionadas ${r.estacionadas}, anon ${r.anon}, ya en el libro ${r.yaEnElLibro}, " +
                        "reemplazadas ${r.reemplazadas}, escritura confirmada ${r.escrituraConfirmada ?: "no"} [$donde]",
                )
            }
            r
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RegistroLegado.anotar(app, "Fase L falló: ${describir(e)}")
            null
        }

    private suspend fun seguir(app: Context, entorno: EntornoLegado, almacen: AlmacenToken, ajustes: Preferencias, modelo: ModeloApp, faseLocalHecha: Boolean) {
        // La copia cruda se borra 90 días después de que el servidor confirme el recibo (con el recibo solo en disco, nunca).
        withContext(Dispatchers.IO) { FaseRemotaLegado.podarCopias(entorno) }
        if (!faseLocalHecha) {
            for (n in 1..3) {
                delay(n * 5_000L)
                // El modelo ya existe: si tiene cuenta, su cola está viva y la Fase L no le escribe el archivo.
                val r = candado.withLock { faseLocal(app, entorno, almacen, ajustes, cuentaViva = modelo.token) } ?: continue
                val t = r.tokenVigente
                if (r.adoptoToken && t != null && modelo.token != t) modelo.entrar(t)
                break
            }
        }
        val recibos = File(entorno.carpeta, "recibos")
        while (withContext(Dispatchers.IO) { FaseRemotaLegado.hayPendiente(entorno) }) {
            esperarCargaConRed(modelo)
            val token = modelo.token
            val info = modelo.info.value
            val cola = modelo.outbox
            if (token == null || info == null || cola == null) {
                esperarOtraCarga(modelo)
                continue
            }
            // La palanca remota (nativa_001). Sin poder leerla se espera, como sin red; sin la tabla vale la de fábrica.
            val palanca = PalancaRemota.leer(modelo.cliente)
            if (palanca == null) {
                esperarOtraCarga(modelo)
                continue
            }
            if (!palanca.opsLegadas && withContext(Dispatchers.IO) { FaseRemotaLegado.faseRPendiente(entorno) }) {
                RegistroLegado.anotar(app, "Fase R en pausa por la palanca remota: se reintenta con la próxima carga")
                esperarOtraCarga(modelo)
                continue
            }
            // Sin cortarla a la mitad: importa a la cola viva y recién después anota el libro mayor.
            val r = withContext(Dispatchers.IO + NonCancellable) {
                FaseRemotaLegado.correr(
                    entorno, token, info.clienteId, modelo.cliente, cola, ReciboEnServidor(modelo.cliente, recibos), ConteosRpc(modelo.cliente),
                    app = version(app),
                )
            }
            if (r.corrio) {
                RegistroLegado.anotar(
                    app,
                    "Fase R: cola ${r.aLaCola}, para revisar ${r.paraRevisar}, reasignadas ${r.reasignadas}, reemplazadas ${r.reemplazadas}, " +
                        "no resuelven ${r.noResuelven}, otro cliente ${r.otroCliente}, swaps sin migrar ${r.swapsSinMigrar}, " +
                        "recibo ${r.recibo?.name?.lowercase() ?: "-"}" + if (r.sinRed) ", sin red: queda pendiente" else "",
                )
            }
            if (r.sinRed) {
                // Se reintenta con la próxima carga con red del modelo, no antes.
                esperarOtraCarga(modelo)
                continue
            }
            if (palanca.escrituraVuelta) {
                escribirDeVuelta(app, entorno, modelo)
            } else {
                RegistroLegado.anotar(app, "escritura de vuelta en pausa por la palanca remota: se reintenta en el arranque siguiente")
            }
            break
        }
        // Los recibos que quedaron solo en el disco (antes de la nativa_001, o sin red), otra vez al servidor.
        if (withContext(Dispatchers.IO) { ReciboEnServidor.hayPendientes(recibos) }) {
            esperarCargaConRed(modelo)
            val token = modelo.token
            val info = modelo.info.value
            if (token != null && info != null) {
                val n = withContext(Dispatchers.IO) { FaseRemotaLegado.reenviarRecibos(entorno, token, info.clienteId, modelo.cliente) }
                if (n > 0) RegistroLegado.anotar(app, "recibos reenviados y confirmados: $n")
            }
        }
    }

    /**
     * La Fase R necesita el primer `get_cliente_info` que contestó: el modelo listo, sin copia offline y fuera de la demo.
     * No dispara cargas: `get_cliente_info` anota una apertura y eso lo decide la app, no la migración.
     */
    private suspend fun esperarCargaConRed(m: ModeloApp) {
        combine(m.fase, m.desdeCache, m.esDemo, m.info) { f, cache, demo, info -> f == ModeloApp.Fase.LISTO && !cache && !demo && info != null }
            .first { it }
    }

    /** Que termine OTRA carga con red (la cuenta las lleva: `cargar` no pasa por "cargando" si ya estaba lista). */
    private suspend fun esperarOtraCarga(m: ModeloApp) {
        val n = m.cargasConRed.value
        m.cargasConRed.first { it > n }
        esperarCargaConRed(m)
    }

    private suspend fun escribirDeVuelta(app: Context, entorno: EntornoLegado, modelo: ModeloApp) {
        val cambios = withContext(Dispatchers.IO) { FaseRemotaLegado.escrituraPendiente(entorno, version(app)) } ?: return
        // Con la app a la vista: en segundo plano el sistema puede congelar el proceso en medio de la escritura.
        while (!modelo.enPrimerPlano) delay(2_000)
        try {
            val resultado = EscritorLegado(app) { RegistroLegado.anotar(app, it) }.escribir(cambios)
            withContext(Dispatchers.IO) { FaseRemotaLegado.registrarEscritura(entorno, cambios, resultado) }
            val porEstado = resultado.values.groupingBy { it }.eachCount().toSortedMap()
            RegistroLegado.anotar(app, "escritura de vuelta, corrida ${cambios.corrida}: " + porEstado.entries.joinToString(", ") { "${it.key} ${it.value}" })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RegistroLegado.anotar(app, "escritura de vuelta falló: ${describir(e)} (se reintenta en el arranque siguiente)")
        }
    }
}

/**
 * `files/legado/registro.log`: qué hizo la migración, sin tokens ni contenido (para el diagnóstico y la prueba en el
 * emulador, que lo lee con `run-as`). Tope de 200 KB. Lo mismo va a Logcat con la etiqueta `MyPumpLegado`.
 */
internal object RegistroLegado {
    private const val TOPE = 200_000L

    fun archivo(contexto: Context): File = File(contexto.filesDir, "legado/registro.log")

    @Synchronized
    fun anotar(contexto: Context, texto: String) {
        Log.i("MyPumpLegado", texto)
        try {
            val f = archivo(contexto)
            f.parentFile?.mkdirs()
            if (f.length() > TOPE) f.writeText("")
            f.appendText("${DateTimeFormatter.ISO_INSTANT.format(Instant.now().truncatedTo(ChronoUnit.SECONDS))} $texto\n")
        } catch (_: Exception) {
        }
    }
}
