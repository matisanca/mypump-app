package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasAudioDuda
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Las dudas en audio para la videollamada (`entregas_019`, por token). Lo del teléfono:
 *
 * - **El archivo.** El audio grabado se mueve a `audios-guia/<id>.m4a` en la carpeta de la cuenta (fuera del backup, como
 *   el resto de `MyPump/`), nunca a las preferencias. Se borra cuando el servidor confirma `subido`.
 * - **La cola.** Cada audio es UNA op de kind [KIND] con su `p_id` (uuid) fijo y su propia `dedupeKey`: dos audios nunca se
 *   deduplican entre sí, y reintentar el mismo reemplaza su op. La ejecuta [EnvioAudioDuda]: `iniciar`, `subir` y `subido`.
 * - **La lista.** `entregas_app_audios` al abrir la sección y después de mandar; mientras alguno está en `subido`, cada 15 s
 *   y hasta 3 minutos, solo con la sección a la vista ([seguir], que la pantalla corre mientras está en primer plano).
 * - **Disponible.** El botón solo aparece cuando la lista contestó alguna vez (la función existe en el servidor): antes de
 *   que se aplique la 019, o si se saca, la app no muestra nada nuevo. Queda guardado con la última lista.
 *
 * Se usa desde el hilo principal, como [ModeloGuia]; lo que avisa la cola llega desde su hilo y se pasa a [alcance].
 */
class ModeloAudioDudas(
    private val cliente: ClienteRpc,
    private val token: String,
    private val outbox: Outbox?,
    private val disco: Disco?,
    private val alcance: CoroutineScope,
    /** «Ver demo»: se graba y se escucha, pero no sale nada (la pantalla muestra «Vista previa…»). */
    val esDemo: Boolean = false,
    private val reloj: () -> Long = System::currentTimeMillis,
    private val esperar: suspend (Long) -> Unit = { delay(it) },
) {
    /** Una fila de `entregas_app_audios`. */
    data class AudioServidor(val id: String, val estado: String, val en: String?, val texto: String?, val segundos: Int? = null) {
        fun aValor(): ValorJson = ValorJson.objeto(
            "id" to ValorJson.Texto(id),
            "estado" to ValorJson.Texto(estado),
            "en" to (en?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "texto" to (texto?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "segundos" to (segundos?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
        )

        companion object {
            fun desde(v: ValorJson): AudioServidor? {
                val id = v["id"]?.comoTexto ?: return null
                return AudioServidor(id, v["estado"]?.comoTexto ?: SUBIDO, v["en"]?.comoTexto, v["texto"]?.comoTexto?.takeIf { it.isNotBlank() }, v["segundos"]?.comoNumero?.toInt())
            }
        }
    }

    enum class Estado { MANDANDO, NO_SE_MANDO, SUBIDO, TRANSCRIPTO, ERROR }

    /** Lo que se ve de un audio. [aviso] es el texto del rechazo; [reintentable] suma «Reintentar». */
    data class Item(val id: String, val estado: Estado, val texto: String? = null, val aviso: String? = null, val reintentable: Boolean = false)

    private val _items = MutableStateFlow<List<Item>>(emptyList())
    val items: StateFlow<List<Item>> = _items.asStateFlow()

    private val _disponible = MutableStateFlow(esDemo)
    val disponible: StateFlow<Boolean> = _disponible.asStateFlow()

    private var servidor: List<AudioServidor> = emptyList()

    /** Las ops de audio en la cola (id del audio → op), y lo que la cola abandonó. */
    private var enCola: Map<String, Operacion> = emptyMap()
    private var abandonados: Map<String, Operacion> = emptyMap()

    /** Los audios en fallidos por `id` (ese p_id es de otro cliente): «Reintentar» va con un id nuevo. */
    private var conIdAjeno: Set<String> = emptySet()

    /** Lo que `iniciar` rechazó (id → motivo, null si no vino) con su op, para reintentar. */
    private val rechazados = LinkedHashMap<String, Pair<String?, Operacion>>()

    /** Lo que el servidor confirmó y la lista todavía no trae. */
    private val confirmados = LinkedHashSet<String>()

    /** Desde cuándo se sigue la lista (abrir la sección o mandar un audio), para el tope de 3 minutos. */
    private var siguiendoDesde = 0L
    private val reinicios = MutableStateFlow(0)

    private val carpeta: File? get() = disco?.archivo(CARPETA)

    /** La caché y la cola se leen al armar el modelo; [mandar] lo espera (si no, la limpieza podía borrar el audio nuevo). */
    private val inicial = alcance.launch {
            val cache = withContext(Dispatchers.IO) { disco?.leer(ARCHIVO)?.let { ValorJson.desde(it) } }
            if (cache != null) {
                if (cache["disponible"] == ValorJson.Booleano(true)) _disponible.value = true
                if (servidor.isEmpty()) servidor = listaDe(cache["audios"]).orEmpty()
            }
            leerCola()
            limpiarHuerfanos()
            pintar()
    }

    /**
     * El aviso de «sin red» es de todo el proceso ([VuelosAudio]) y el alcance es el de la app: sin [cerrar], cada cuenta
     * que pasaba por el teléfono dejaba un collector vivo.
     */
    private val vigia = alcance.launch { VuelosAudio.sinRed.collect { pintar() } }

    /** El modelo se suelta (otra cuenta, salir, la demo): deja de escuchar los avisos. Lo pendiente sigue en la cola. */
    fun cerrar() {
        vigia.cancel()
    }

    /** Para las pruebas: ya se leyó la caché y la cola. */
    suspend fun alDia() = inicial.join()

    /** Los textos transcriptos, para saltearlos en las dudas de la videollamada (la deduplicación de la web). */
    val transcriptos: List<String> get() = servidor.filter { it.estado == TRANSCRIPTO }.mapNotNull { it.texto }

    /** Hay uno saliendo: «Grabar un audio» espera (los botones desactivados de la web mientras sube). */
    val hayMandando: Boolean get() = _items.value.any { it.estado == Estado.MANDANDO }

    // ── La lista ──

    /** `entregas_app_audios`. Sin red queda lo de antes. Devuelve si contestó. */
    suspend fun refrescar(): Boolean {
        if (esDemo) return true
        val r = cliente.llamar("entregas_app_audios", mapOf("p_token" to ValorJson.Texto(token)))
        if (r is Resultado.Falla) {
            // La función no existe (antes de la 019): no hay audios en la app.
            if (r.error.funcionInexistente || r.error.status == 404) {
                _disponible.value = false
                guardarCache()
            }
            return false
        }
        val v = (r as Resultado.Ok).valor
        val lista = listaDe(v) ?: listaDe(v["audios"])
        servidor = lista.orEmpty()
        confirmados.removeAll(servidor.map { it.id }.toSet())
        if (lista != null || v == ValorJson.Nulo) _disponible.value = true
        leerCola()
        pintar()
        guardarCache()
        return true
    }

    /**
     * Lo que corre la pantalla mientras «Tu guía» está a la vista (y se cancela al salir o ir a segundo plano): la lista al
     * abrir y, mientras haya alguno en `subido`, cada 15 s hasta 3 minutos. Pasado el tope queda «Lo estoy pasando a
     * texto» sin seguir preguntando, hasta que se mande otro audio o se vuelva a abrir.
     */
    suspend fun seguir() {
        if (esDemo) return
        siguiendoDesde = reloj()
        refrescar()
        while (true) {
            val vuelta = reinicios.value
            if (!ReglasAudioDuda.seguirConsultando(haySubido(), siguiendoDesde, reloj())) {
                reinicios.first { it != vuelta }
                continue
            }
            esperar(ReglasAudioDuda.CONSULTA_CADA_MS)
            refrescar()
        }
    }

    private fun haySubido(): Boolean = confirmados.isNotEmpty() || servidor.any { it.estado == SUBIDO }

    // ── Mandar ──

    /**
     * El audio que se revisó y se tocó «Mandar»: el archivo pasa a la carpeta de la cuenta y sale por la cola. Devuelve
     * false si no se pudo (sin carpeta o sin cola, o la demo).
     */
    suspend fun mandar(grabado: File, segundos: Int): Boolean {
        if (esDemo) return false
        inicial.join()
        val cola = outbox ?: return false
        val dir = carpeta ?: return false
        val id = java.util.UUID.randomUUID().toString()
        val destino = File(dir, "$id.m4a")
        val movido = withContext(Dispatchers.IO) {
            try {
                dir.mkdirs()
                Files.move(grabado.toPath(), destino.toPath(), StandardCopyOption.REPLACE_EXISTING)
                true
            } catch (_: Exception) {
                false
            }
        }
        if (!movido) return false
        val payload = ValorJson.objeto(
            "id" to ValorJson.Texto(id),
            "archivo" to ValorJson.Texto(destino.absolutePath),
            "mime" to ValorJson.Texto(ReglasAudioDuda.MIME),
            "bytes" to ValorJson.Numero(destino.length().toDouble()),
            "segundos" to ValorJson.Numero(segundos.toDouble()),
        )
        cola.encolar(KIND, payload, clave(id))
        leerCola()
        pintar()
        return true
    }

    /**
     * «Reintentar»: lo que está en la cola sale ya; lo rechazado o abandonado vuelve a la cola con el mismo `p_id` (marcado
     * como reintento: un 403 o 409 de Storage es «quizás ya subió»). Con el motivo `id` (ese p_id es de otro cliente) el
     * mismo archivo sale con un `p_id` nuevo (hallazgo 17).
     */
    suspend fun reintentar(id: String) {
        val cola = outbox ?: return
        VuelosAudio.olvidar(id)
        val rechazo = rechazados.remove(id)
        val op = rechazo?.second ?: abandonados[id]
        if (op != null && enCola[id] == null) {
            val campos = (op.payload as? ValorJson.Objeto)?.campos.orEmpty()
            if (ReglasAudioDuda.pideIdNuevo(rechazo?.first) || id in conIdAjeno) {
                val nuevo = java.util.UUID.randomUUID().toString()
                cola.encolar(KIND, ValorJson.Objeto(campos - "reintento" + ("id" to ValorJson.Texto(nuevo))), clave(nuevo))
            } else {
                cola.encolar(KIND, ValorJson.Objeto(campos + ("reintento" to ValorJson.Booleano(true))), clave(id))
            }
            cola.olvidarFallidos(clave(id))
        }
        leerCola()
        pintar()
        alcance.launch { cola.drenar() }
    }

    /** Lo que el servidor guardó (lo pasa [ModeloGuia] desde la cola). */
    fun alGuardar(ops: List<OpGuardada>) {
        val nuestras = ops.filter { it.op.kind == KIND }
        if (nuestras.isEmpty()) return
        alcance.launch {
            for (g in nuestras) {
                val id = idDe(g.op) ?: continue
                VuelosAudio.olvidar(id)
                val r = g.respuesta
                if (r["ok"] == ValorJson.Booleano(true)) {
                    confirmados += id
                    borrarArchivo(g.op)
                } else {
                    val motivo = r["motivo"]?.comoTexto
                    rechazados[id] = motivo to g.op
                    // Queda en fallidos (no se pierde al cerrar la app) lo que se puede reintentar (sin motivo, `pendientes`, o
                    // `id`, que vuelve con un p_id nuevo), con su archivo para «Reintentar».
                    if (ReglasAudioDuda.motivoReintentable(motivo)) {
                        outbox?.archivarEnFallidos(listOf(g.op), "audio rechazado: ${motivo ?: "sin motivo"}")
                    }
                    if (!ReglasAudioDuda.motivoReintentable(motivo)) borrarArchivo(g.op)
                }
            }
            leerCola()
            pintar()
            if (nuestras.any { it.respuesta["ok"] == ValorJson.Booleano(true) }) {
                siguiendoDesde = reloj()
                reinicios.update { it + 1 }
                refrescar()
            }
        }
    }

    /**
     * Lo que la cola abandonó tras 8 intentos, o tras 2 h en `pendientes` (queda en fallidos con su archivo): «No se pudo
     * mandar» con «Reintentar».
     */
    fun alAbandonar(ops: List<Operacion>) {
        val nuestras = ops.filter { it.kind == KIND }
        if (nuestras.isEmpty()) return
        nuestras.forEach { op -> idDe(op)?.let(VuelosAudio::olvidar) }
        alcance.launch {
            leerCola()
            pintar()
        }
    }

    // ── Lo de adentro ──

    private suspend fun leerCola() {
        val cola = outbox ?: return
        enCola = cola.operaciones().filter { it.kind == KIND }.mapNotNull { op -> idDe(op)?.let { it to op } }.toMap()
        val fallidos = cola.fallidos().filter { it.op.kind == KIND }
        abandonados = fallidos.mapNotNull { f -> idDe(f.op)?.let { it to f.op } }.toMap()
        conIdAjeno = fallidos.filter { it.motivo == MOTIVO_ID_AJENO }.mapNotNullTo(HashSet()) { idDe(it.op) }
    }

    private fun pintar() {
        val vistos = HashSet<String>()
        val lista = mutableListOf<Item>()
        for (s in servidor.sortedBy { it.en ?: "" }) {
            // Otro estado (un ticket pedido que todavía no subió): manda lo del teléfono, si lo tiene.
            if (s.estado != SUBIDO && s.estado != TRANSCRIPTO && s.estado != ERROR) continue
            if (!vistos.add(s.id)) continue
            lista += when (s.estado) {
                TRANSCRIPTO -> Item(s.id, Estado.TRANSCRIPTO, texto = s.texto)
                ERROR -> Item(s.id, Estado.ERROR)
                else -> Item(s.id, Estado.SUBIDO)
            }
        }
        val sinRed = VuelosAudio.sinRed.value
        val locales = (abandonados.values + rechazados.values.map { it.second } + enCola.values).sortedBy { it.ts }
        for (op in locales) {
            val id = idDe(op) ?: continue
            if (id in vistos) continue
            vistos += id
            lista += when {
                id in confirmados -> Item(id, Estado.SUBIDO)
                id in enCola -> sinRed[id]?.let { Item(id, Estado.NO_SE_MANDO, aviso = it, reintentable = true) } ?: Item(id, Estado.MANDANDO)
                id in rechazados -> {
                    val motivo = rechazados[id]?.first
                    Item(id, Estado.NO_SE_MANDO, aviso = ReglasAudioDuda.textoMotivo(motivo) ?: ReglasAudioDuda.NO_SE_PUDO, reintentable = ReglasAudioDuda.motivoReintentable(motivo))
                }
                else -> Item(id, Estado.NO_SE_MANDO, aviso = ReglasAudioDuda.NO_SE_PUDO, reintentable = true)
            }
        }
        for (id in confirmados) if (vistos.add(id)) lista += Item(id, Estado.SUBIDO)
        _items.value = lista
    }

    private fun guardarCache() {
        val d = disco ?: return
        val v = ValorJson.objeto(
            "disponible" to ValorJson.Booleano(_disponible.value),
            "audios" to ValorJson.Lista(servidor.map { it.aValor() }),
        )
        alcance.launch(Dispatchers.IO) { d.guardar(ARCHIVO, v) }
    }

    private suspend fun borrarArchivo(op: Operacion) {
        val ruta = op.payload["archivo"]?.comoTexto ?: return
        withContext(Dispatchers.IO) { File(ruta).delete() }
    }

    /** Los archivos que ya no tiene ninguna op (se confirmó y la app se cerró antes de borrarlo): se borran. */
    private suspend fun limpiarHuerfanos() {
        val dir = carpeta ?: return
        val usados = (enCola.values + abandonados.values).mapNotNull { it.payload["archivo"]?.comoTexto }.toSet()
        withContext(Dispatchers.IO) {
            dir.listFiles()?.forEach { f -> if (f.absolutePath !in usados) f.delete() }
        }
    }

    companion object {
        const val KIND = "guia_audio"
        const val SUBIDO = "subido"
        const val TRANSCRIPTO = "transcripto"
        const val ERROR = "error"
        internal const val CARPETA = "audios-guia"
        internal const val ARCHIVO = "guia-audios.json"

        fun clave(id: String): String = "guia_audio_$id"

        /** El motivo con el que queda en fallidos un audio rechazado por `id`. */
        internal const val MOTIVO_ID_AJENO = "audio rechazado: id"

        internal fun idDe(op: Operacion): String? = op.payload["id"]?.comoTexto

        private fun listaDe(v: ValorJson?): List<AudioServidor>? = (v as? ValorJson.Lista)?.elementos?.mapNotNull(AudioServidor::desde)
    }
}

/**
 * Los audios cuyo último intento se cortó por la red (o el servidor ocupado): la pantalla los muestra con «No se pudo
 * mandar» y «Reintentar» mientras la cola los vuelve a probar sola. Por id (uuid), así sirve para cualquier cuenta.
 */
object VuelosAudio {
    /** id → lo que se muestra («No se pudo mandar.», o «Esperá un toque…» con `pendientes`). */
    private val _sinRed = MutableStateFlow<Map<String, String>>(emptyMap())
    val sinRed: StateFlow<Map<String, String>> = _sinRed.asStateFlow()

    fun cortado(id: String, aviso: String = ReglasAudioDuda.NO_SE_PUDO) = _sinRed.update { it + (id to aviso) }

    fun olvidar(id: String) = _sinRed.update { it - id }
}

/**
 * Cómo sale un audio de la cola: el contrato FINAL de `entregas_019` (aplicado el 4-nov), siempre con el mismo `p_id`.
 *
 * 1. `entregas_app_audio_iniciar(p_token, p_mime, p_bytes, p_segundos, p_id)` → `{ok, id, bucket, ruta, mime, max_bytes}`
 *    o `{ok: false, motivo}`. Es idempotente por `p_id` (un ticket vencido sin archivo se reactiva con el mismo id): cada
 *    intento lo pide de nuevo, así uno vencido (30 min) nunca se usa.
 * 2. `POST /storage/v1/object/{bucket}/{ruta}` con la anon key, `Content-Type` = el `mime` del ticket y `x-upsert: false`.
 *    La re-subida de la misma ruta contesta 403 (o 409): «quizás ya subió», y lo decide `subido`.
 * 3. `entregas_app_audio_subido(p_token, p_id)` → `{ok, estado}` o el motivo: `sin_archivo` = subir otra vez; `vencido` o
 *    `no_existe` = `iniciar` de nuevo con el mismo id; `tamano` = rechazo; `token` = la cola lo verifica.
 *
 * Hasta [RONDAS] vueltas por intento. Lo que devuelve a la cola: `{ok: true, id}` = hecho; `{ok: false, motivo}` =
 * rechazado (no se reintenta solo; lo avisa [ModeloAudioDudas]); `false` = el token (la cola lo verifica y estaciona); un
 * [Resultado.Falla] de red o transitorio = reintento sin gastar intento; uno permanente gasta intento.
 */
class EnvioAudioDuda(private val cliente: ClienteRpc, private val token: String) {
    /**
     * [reintento]: la op ya salió antes (o es «Reintentar» del mismo id). Solo entonces un 403 o 409 de la subida cuenta
     * como «quizás ya subió» (revisión del 4-nov, hallazgo 15): en el primer intento es un error de verdad.
     */
    suspend fun ejecutar(p: ValorJson, reintento: Boolean = false): Resultado<ValorJson> {
        val id = p["id"]?.comoTexto ?: return rechazo("archivo")
        val r = pasos(id, p, reintento)
        val e = r.errorONull()
        if (e != null && e.clase != ErrorRpc.Clase.PERMANENTE) {
            VuelosAudio.cortado(id, if (e.codigo == MOTIVO_PENDIENTES) ReglasAudioDuda.textoMotivo("pendientes")!! else ReglasAudioDuda.NO_SE_PUDO)
        } else {
            VuelosAudio.olvidar(id)
        }
        return r
    }

    private class Ticket(val bucket: String, val ruta: String, val mime: String)

    private suspend fun pasos(id: String, p: ValorJson, reintento: Boolean): Resultado<ValorJson> {
        VuelosAudio.olvidar(id)
        val archivo = p["archivo"]?.comoTexto?.let(::File)
        // Un archivo que no se puede leer no es falta de red (una IOException acá la cola la tomaría como tal).
        val bytes = withContext(Dispatchers.IO) { runCatching { archivo?.takeIf { it.isFile }?.readBytes() }.getOrNull() }
            ?: return rechazo("archivo")
        val t = ValorJson.Texto(token)
        val mime = p["mime"]?.comoTexto ?: ReglasAudioDuda.MIME
        val segundos = (p["segundos"]?.comoNumero ?: 0.0).coerceIn(0.0, ReglasAudioDuda.TOPE_S.toDouble()).toInt()

        var ticket: Ticket? = null
        // Ya se subió una vez en este intento (`sin_archivo` pidió otra): la re-subida también es un reintento.
        var subioAntes = false
        repeat(RONDAS) {
            // 1. El ticket (de nuevo si `subido` dijo vencido o no_existe).
            val tk = ticket ?: run {
                val r = cliente.llamar(
                    "entregas_app_audio_iniciar",
                    mapOf(
                        "p_token" to t, "p_mime" to ValorJson.Texto(mime), "p_bytes" to ValorJson.Numero(bytes.size.toDouble()),
                        "p_segundos" to ValorJson.Numero(segundos.toDouble()), "p_id" to ValorJson.Texto(id),
                    ),
                )
                val v = when (r) {
                    is Resultado.Falla -> return if (r.error.funcionInexistente) rechazo("sin_funcion") else r
                    is Resultado.Ok -> r.valor
                }
                if (v["ok"] != ValorJson.Booleano(true)) {
                    val motivo = v["motivo"]?.comoTexto
                    // El token (o una respuesta vacía, como contestan las demás con el token caído): que la cola lo verifique.
                    if (motivo == null || motivo == "token") return Resultado.Ok(ValorJson.Booleano(false))
                    // `pendientes` (3 a la vez): se arregla esperando. Transitorio: la cola reintenta sin gastar intento.
                    if (motivo == "pendientes") return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.TRANSITORIO, 200, MOTIVO_PENDIENTES, "entregas_app_audio_iniciar: pendientes"))
                    return rechazo(motivo)
                }
                val bucket = v["bucket"]?.comoTexto
                val ruta = v["ruta"]?.comoTexto
                if (bucket.isNullOrEmpty() || ruta.isNullOrEmpty()) {
                    return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_TICKET", "entregas_app_audio_iniciar sin bucket o ruta"))
                }
                v["max_bytes"]?.comoNumero?.let { if (bytes.size > it) return rechazo("tamano") }
                Ticket(bucket, ruta, (v["mime"]?.comoTexto ?: mime).substringBefore(';').trim()).also { ticket = it }
            }

            // 2. La subida. En un reintento, un 403 o 409 es «quizás ya estaba»: lo decide `subido`.
            subir(tk, bytes, reintento || subioAntes)?.let { return Resultado.Falla(it) }
            subioAntes = true

            // 3. Avisar que subió.
            val v = when (val s = cliente.llamar("entregas_app_audio_subido", mapOf("p_token" to t, "p_id" to ValorJson.Texto(id)))) {
                is Resultado.Falla -> return s
                is Resultado.Ok -> s.valor
            }
            if (v["ok"] == ValorJson.Booleano(true) || v == ValorJson.Booleano(true)) {
                return Resultado.Ok(ValorJson.objeto("ok" to ValorJson.Booleano(true), "id" to ValorJson.Texto(id)))
            }
            when (val motivo = v["motivo"]?.comoTexto) {
                "sin_archivo" -> Unit                        // otra vuelta: subir de nuevo con el mismo ticket
                "vencido", "no_existe" -> ticket = null      // otra vuelta: iniciar de nuevo con el mismo id
                null, "token" -> return Resultado.Ok(ValorJson.Booleano(false))
                else -> return rechazo(motivo)
            }
        }
        return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_CONFIRMAR", "entregas_app_audio_subido no confirmó en $RONDAS vueltas"))
    }

    /** Devuelve el error, o null si quedó subido (o, en un [reintento], quizás ya estaba: 403 o 409 de la re-subida). */
    private suspend fun subir(tk: Ticket, bytes: ByteArray, reintento: Boolean): ErrorRpc? {
        val c = cliente.config
        val camino = tk.ruta.split('/').joinToString("/") { java.net.URLEncoder.encode(it, "UTF-8").replace("+", "%20") }
        val pedido = Pedido(
            url = "${c.supabase}/storage/v1/object/${java.net.URLEncoder.encode(tk.bucket, "UTF-8")}/$camino",
            metodo = "POST",
            cabeceras = mapOf(
                "apikey" to c.anonKey,
                "Authorization" to "Bearer ${c.anonKey}",
                "Content-Type" to tk.mime,
                "x-upsert" to "false",
            ),
            cuerpo = bytes,
            esperaMs = 90_000,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            return ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "subida: $e")
        }
        if (r.status in 200..299 || (reintento && quizasYaEstaba(r))) return null
        val texto = r.cuerpo.copyOf(minOf(300, r.cuerpo.size)).toString(Charsets.UTF_8)
        return ErrorRpc(ErrorRpc.claseDe(r.status), r.status, "STORAGE", "subida: $texto")
    }

    companion object {
        /** Vueltas de iniciar, subir y subido en un mismo intento (sin_archivo o vencido piden otra). */
        const val RONDAS = 3

        internal const val MOTIVO_PENDIENTES = "PENDIENTES"

        fun rechazo(motivo: String): Resultado<ValorJson> =
            Resultado.Ok(ValorJson.objeto("ok" to ValorJson.Booleano(false), "motivo" to ValorJson.Texto(motivo)))

        /**
         * La re-subida de la misma ruta: Storage contesta 403 (lo dice el contrato final), 409, o 400 con `statusCode: "409"`
         * o `Duplicate` en el cuerpo. No se sabe si subió: `subido` lo confirma o pide subir de nuevo (`sin_archivo`).
         */
        internal fun quizasYaEstaba(r: Respuesta): Boolean {
            if (r.status == 403 || r.status == 409) return true
            if (r.status != 400) return false
            // Storage suele contestar HTTP 400 con el código de verdad adentro (`"statusCode":"403"` de la política, `"409"`).
            val t = r.cuerpo.toString(Charsets.UTF_8).replace(" ", "")
            return "\"statusCode\":\"403\"" in t || "\"statusCode\":\"409\"" in t || "Duplicate" in t || "alreadyexists" in t
        }
    }
}
