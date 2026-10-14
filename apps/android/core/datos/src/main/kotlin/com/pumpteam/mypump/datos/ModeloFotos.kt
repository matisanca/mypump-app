package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.FotoProgreso
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import java.util.Base64
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * Una foto que espera subir. Mismo formato que la cola de la web (`mypump_fotoq_<TOKEN>`: pose, fecha, dataUrl,
 * intentos): así la migración del almacenamiento viejo la deja tal cual en `fotos-pendientes.json`.
 */
data class FotoPendiente(
    val pose: String,
    val fecha: String,
    /** `data:image/jpeg;base64,…` (900 px, calidad 0,7, sin EXIF). */
    val dataUrl: String,
    /** Solo cuentan los errores del servidor; con 8 se descarta. */
    val intentos: Int = 0,
) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "pose" to texto(pose), "fecha" to texto(fecha), "dataUrl" to texto(dataUrl), "intentos" to numero(intentos),
    )

    companion object {
        const val ARCHIVO = "fotos-pendientes.json"

        fun desde(v: ValorJson): FotoPendiente? {
            val pose = v["pose"]?.comoTexto ?: return null
            val fecha = v["fecha"]?.comoTexto ?: return null
            val dataUrl = v["dataUrl"]?.comoTexto ?: return null
            return FotoPendiente(pose, fecha, dataUrl, v["intentos"]?.comoNumero?.toInt() ?: 0)
        }
    }
}

/**
 * Fotos de progreso: subida por pose al servicio de la Mini (bucket privado), con una cola propia en disco que sobrevive a
 * cerrar la app y a quedarse sin señal, URLs firmadas que se cachean 50 minutos, y la lista de lo subido.
 */
class ModeloFotos(private val cliente: ClienteRpc, private val token: String, private val disco: Disco?) {
    sealed interface Resultado {
        /** "Listo, guardada ✓" */
        data object Guardada : Resultado

        /** "Sin conexión: queda guardada y se sube sola." */
        data object SinConexion : Resultado

        /** "No se pudo guardar: <motivo>" (no va a entrar nunca). */
        data class Rechazada(val motivo: String) : Resultado

        /** "Hay fotos esperando subir. Probá cuando tengas señal." */
        data object ColaLlena : Resultado

        /** "Esa foto es demasiado pesada. Probá sacarla con la cámara." */
        data object MuyPesada : Resultado

        /** No se pudo ni guardar en el teléfono. */
        data object NoSeGuardo : Resultado

        val texto: String
            get() = when (this) {
                Guardada -> "Listo, guardada ✓"
                SinConexion -> "Sin conexión: queda guardada y se sube sola."
                is Rechazada -> "No se pudo guardar: $motivo"
                ColaLlena -> "Hay fotos esperando subir. Probá cuando tengas señal."
                MuyPesada -> "Esa foto es demasiado pesada. Probá sacarla con la cámara."
                NoSeGuardo -> "No se pudo guardar. Probá de nuevo con señal."
            }
    }

    private val _fotos = MutableStateFlow<List<FotoProgreso>>(emptyList())
    val fotos: StateFlow<List<FotoProgreso>> = _fotos.asStateFlow()

    /** "<lunes>|<pose>" → la foto que espera subir. */
    private val _pendientes = MutableStateFlow<Map<String, FotoPendiente>>(leerCola())
    val pendientes: StateFlow<Map<String, FotoPendiente>> = _pendientes.asStateFlow()

    /** "<lunes>|<pose>" → URL firmada (1 h). */
    private val _urls = MutableStateFlow<Map<String, String>>(emptyMap())
    val urls: StateFlow<Map<String, String>> = _urls.asStateFlow()

    private val _subiendo = MutableStateFlow<Set<String>>(emptySet())
    val subiendo: StateFlow<Set<String>> = _subiendo.asStateFlow()

    private val drenando = Mutex()
    @Volatile private var urlsVencen: Long? = null

    val semanaActual: String get() = FotosProgreso.lunes(FechaLocal.hoy())

    val posesDeLaSemana: Set<String>
        get() = FotosProgreso.posesDeLaSemana(_fotos.value, _pendientes.value.values.map { it.pose to it.fecha }, semanaActual)

    /** `loadFotos`: lo que ya está subido. Sin red queda lo de antes. */
    suspend fun cargar() {
        cliente.filas("mypump_get_fotos_progreso", mapOf("p_token" to texto(token), "p_desde" to ValorJson.Nulo), FotoProgreso::desde)
            .valorONull()?.let { _fotos.value = it }
    }

    /** `_tomarFoto`: el JPEG ya reducido (900 px, 0,7, sin metadatos) se encola y se sube enseguida. */
    suspend fun subir(pose: String, jpeg: ByteArray): Resultado {
        val dataUrl = "data:image/jpeg;base64," + Base64.getEncoder().encodeToString(jpeg)
        val fecha = FechaLocal.hoy()
        val clave = "${FotosProgreso.lunes(fecha)}|$pose"
        if (_pendientes.value.size >= FotosProgreso.MAX_PENDIENTES && clave !in _pendientes.value) return Resultado.ColaLlena
        if (dataUrl.length > FotosProgreso.MAX_CARACTERES) return Resultado.MuyPesada
        val item = FotoPendiente(pose, fecha, dataUrl)
        _pendientes.update { it + (clave to item) }
        val guardo = guardarCola()
        _subiendo.update { it + clave }
        try {
            return when (val r = enviar(item)) {
                Envio.Ok -> {
                    _pendientes.update { it - clave }
                    guardarCola()
                    cargar()
                    urlsVencen = null          // que se refirme y aparezca la miniatura
                    Resultado.Guardada
                }
                is Envio.Fatal -> {
                    _pendientes.update { it - clave }
                    guardarCola()
                    Resultado.Rechazada(r.motivo)
                }
                Envio.Reintentar, Envio.Red -> if (guardo) Resultado.SinConexion else Resultado.NoSeGuardo
            }
        } finally {
            _subiendo.update { it - clave }
        }
    }

    /**
     * `flushFotos`: una pasada a la vez. Un rechazo (4xx salvo 429) se descarta para no trabar la cola; la red no gasta
     * intentos; 8 errores del servidor y se deja.
     */
    suspend fun drenar() {
        if (_pendientes.value.isEmpty() || !drenando.tryLock()) return
        try {
            var subioAlgo = false
            for (clave in _pendientes.value.keys.sorted()) {
                val item = _pendientes.value[clave] ?: continue
                _subiendo.update { it + clave }
                val r = enviar(item)
                _subiendo.update { it - clave }
                when (r) {
                    Envio.Ok -> {
                        _pendientes.update { it - clave }
                        guardarCola()
                        subioAlgo = true
                        continue
                    }
                    is Envio.Fatal -> _pendientes.update { it - clave }
                    Envio.Red -> {}
                    Envio.Reintentar -> {
                        val otra = item.copy(intentos = item.intentos + 1)
                        _pendientes.update { if (otra.intentos >= FotosProgreso.MAX_INTENTOS) it - clave else it + (clave to otra) }
                    }
                }
                guardarCola()
                if (r == Envio.Red) break
                if (clave in _pendientes.value) break   // el servidor está mal: se reintenta después
            }
            if (subioAlgo) {
                cargar()
                urlsVencen = null
            }
        } finally {
            drenando.unlock()
        }
    }

    /** `cargarFotosFirmadas`: las URLs (duran 1 h) se piden una vez y se guardan 50 minutos. */
    suspend fun firmar(forzar: Boolean = false): Boolean {
        val vencen = urlsVencen
        if (!forzar && vencen != null && vencen > System.currentTimeMillis()) return true
        val pedido = Pedido(
            url = "${cliente.config.vision}/progreso/urls", metodo = "POST", cabeceras = mapOf("Content-Type" to "application/json"),
            cuerpo = ValorJson.objeto("token" to texto(token)).serializar().toByteArray(), esperaMs = 30_000,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return _urls.value.isNotEmpty()
        }
        val j = parsear(r.cuerpo)
        val filas = (j?.get("fotos") as? ValorJson.Lista)?.elementos
        if (r.status >= 300 || j?.get("ok") != ValorJson.Booleano(true) || filas == null) return _urls.value.isNotEmpty()
        val mapa = LinkedHashMap<String, String>()
        for (f in filas) {
            val s = f["semana_lunes"]?.comoTexto
            val p = f["pose"]?.comoTexto
            val u = f["url"]?.comoTexto
            if (s != null && p != null && u != null) mapa["$s|$p"] = u
        }
        if (mapa.isEmpty()) return _urls.value.isNotEmpty()
        _urls.value = mapa
        urlsVencen = System.currentTimeMillis() + 50 * 60 * 1000
        return true
    }

    // ── Envío ──

    internal sealed interface Envio {
        data object Ok : Envio

        data class Fatal(val motivo: String) : Envio

        data object Reintentar : Envio

        data object Red : Envio
    }

    /** `_subirFoto`: 4xx salvo 429 = no va a entrar nunca; 5xx/429 = el servidor, se reintenta; sin respuesta = red. */
    internal suspend fun enviar(f: FotoPendiente): Envio {
        val pedido = Pedido(
            url = "${cliente.config.vision}/progreso/upload", metodo = "POST", cabeceras = mapOf("Content-Type" to "application/json"),
            cuerpo = ValorJson.objeto(
                "token" to texto(token), "pose" to texto(f.pose), "fecha" to texto(f.fecha), "imagen_base64" to texto(f.dataUrl),
            ).serializar().toByteArray(),
            esperaMs = 90_000,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return Envio.Red
        }
        val j = parsear(r.cuerpo)
        if (r.status in 200..299 && j?.get("ok") == ValorJson.Booleano(true)) return Envio.Ok
        if (r.status in 400..499 && r.status != 429) return Envio.Fatal(j?.get("error")?.comoTexto ?: "HTTP ${r.status}")
        return Envio.Reintentar
    }

    private fun leerCola(): Map<String, FotoPendiente> {
        val o = disco?.leer(ARCHIVO) as? JsonObject ?: return emptyMap()
        val m = LinkedHashMap<String, FotoPendiente>()
        for ((k, v) in o) FotoPendiente.desde(ValorJson.desde(v))?.let { m[k] = it }
        return m
    }

    /** Devuelve si la cola quedó en disco (si no, el resultado de subir es "no se guardó"). */
    private fun guardarCola(): Boolean {
        val d = disco ?: return false
        val p = _pendientes.value
        if (p.isEmpty()) {
            d.borrar(ARCHIVO)
            return true
        }
        d.guardar(ARCHIVO, ValorJson.Objeto(p.mapValues { it.value.aValor() }))
        return d.leer(ARCHIVO) != null
    }

    private fun parsear(cuerpo: ByteArray): ValorJson? = try {
        ValorJson.desde(Json.parseToJsonElement(cuerpo.toString(Charsets.UTF_8)))
    } catch (_: Exception) {
        null
    }

    companion object {
        const val ARCHIVO = FotoPendiente.ARCHIVO
    }
}
