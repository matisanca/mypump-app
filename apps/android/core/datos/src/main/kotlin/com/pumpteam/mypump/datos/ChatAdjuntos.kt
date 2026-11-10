package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.AdjuntoChat
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasChatAdjuntos
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext

// Fotos y audios en el chat con Mati (2.3.0, `nativa_chat_adjuntos`). Gemelo de ChatAdjuntos.swift. Cada adjunto tiene un
// id que pone el teléfono: es el nombre del archivo, la clave de la cola y lo que mini-vision usa para no guardarlo dos
// veces. La burbuja aparece al instante («enviando…») y sale por su propio carril de la cola: sin señal espera sin gastar
// intentos y nada se pierde. Lo que el servidor guarda es una fila del chat con «Foto» o «Audio de 0:42».

/** Una URL firmada de `/chat/urls` (dura 1 h; se usa 50 minutos) con el formato real del archivo. */
data class FirmaAdjunto(val url: String, val mime: String, val venceMs: Long)

const val KIND_ADJUNTO_CHAT = "chat_adjunto"
const val CARPETA_ADJUNTOS_CHAT = "chat-adjuntos"

internal fun claveAdjunto(id: String) = "${KIND_ADJUNTO_CHAT}_$id"

internal fun burbujaPendiente(id: String, tipo: AdjuntoChat.Tipo, segundos: Double?, creado: String, fallo: Boolean = false, motivo: String? = null) =
    BurbujaChat(
        id = "adj_$id", autor = "cliente",
        contenido = if (tipo == AdjuntoChat.Tipo.FOTO) ReglasChatAdjuntos.TEXTO_FOTO else ReglasChatAdjuntos.textoAudio(segundos),
        leidoPorCliente = null, createdAt = creado, pendiente = true, fallo = fallo,
        adjunto = AdjuntoChat(id, tipo, segundos), motivoFallo = motivo,
    )

/** El motivo de [Outbox.Fallido] es el código solo cuando fue directo; si no, «abandonada tras 8 intentos». */
internal fun motivoCorto(m: String?): String? = m?.let { mm -> ReglasChatAdjuntos.CODIGOS_DIRECTOS.firstOrNull { mm.startsWith(it) } }

internal fun extensionDe(mime: String) = when (mime) {
    "image/jpeg" -> "jpg"
    "audio/webm" -> "webm"
    "audio/ogg" -> "ogg"
    else -> "m4a"
}

internal fun mimeDeExtension(e: String) = when (e.lowercase()) {
    "jpg", "jpeg" -> "image/jpeg"
    "webm" -> "audio/webm"
    "ogg" -> "audio/ogg"
    else -> "audio/mp4"
}

private fun idDeArchivo(nombre: String): String? {
    val base = nombre.substringBeforeLast('.')
    return runCatching { UUID.fromString(base) }.getOrNull()?.let { base.lowercase() }
}

private fun parsearJson(b: ByteArray): ValorJson? = try {
    ValorJson.parsear(b.toString(Charsets.UTF_8))
} catch (_: Exception) {
    null
}

// ── Si se muestra ──

/**
 * [palanca] null = no se pudo leer en esta apertura (queda lo último que se supo). Con la palanca prendida pregunta al servidor si este cliente los tiene (`mypump_chat_adjuntos_estado`). Sin red queda lo
 * último que se supo: con la palanca prendida, sin señal en el gimnasio igual se puede mandar (sale después).
 */
suspend fun ModeloChat.consultarAdjuntos(palanca: Boolean?) {
    val carpeta = carpetaAdjuntos
    if (palanca == false || carpeta == null || demo) {
        _adjuntosActivos.value = false
        carpeta?.let { if (palanca == false) recordarEstado(it) }
        return
    }
    if (palanca == null) {
        // La palanca no se pudo leer (sin red al abrir): lo último que se supo.
        leerEstado(carpeta)?.let { ponerEstado(it.first, it.second) }
        return
    }
    when (val r = cliente.llamar("mypump_chat_adjuntos_estado", mapOf("p_token" to texto(token ?: "")))) {
        is Resultado.Ok -> {
            ponerEstado(r.valor["habilitado"] == ValorJson.Booleano(true), r.valor["audio_max_s"]?.comoNumero)
            recordarEstado(carpeta)
        }
        is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) {
            ponerEstado(false, null)   // la función todavía no está en la base
            recordarEstado(carpeta)
        } else {
            leerEstado(carpeta)?.let { ponerEstado(it.first, it.second) }
        }
    }
}

private fun ModeloChat.ponerEstado(habilitado: Boolean, audioMax: Double?) {
    _adjuntosActivos.value = habilitado
    audioMaximo = if (audioMax != null && audioMax.isFinite() && audioMax >= 10) minOf(audioMax, ReglasChatAdjuntos.AUDIO_MAXIMO) else ReglasChatAdjuntos.AUDIO_MAXIMO
}

private suspend fun ModeloChat.recordarEstado(carpeta: File) = withContext(Dispatchers.IO) {
    runCatching {
        carpeta.mkdirs()
        File(carpeta, "estado.json").writeText(
            ValorJson.objeto("habilitado" to ValorJson.Booleano(_adjuntosActivos.value), "audio_max_s" to ValorJson.Numero(audioMaximo)).serializar(),
        )
    }
}

private suspend fun leerEstado(carpeta: File): Pair<Boolean, Double?>? = withContext(Dispatchers.IO) {
    val j = runCatching { ValorJson.parsear(File(carpeta, "estado.json").readText()) }.getOrNull() ?: return@withContext null
    (j["habilitado"] == ValorJson.Booleano(true)) to j["audio_max_s"]?.comoNumero
}

// ── Mandar ──

/**
 * Una foto ya reducida en la app (`ReduccionFoto`: lado mayor 1600 px, JPEG sin EXIF ni GPS). Sale por la cola. false si
 * no se pudo guardar o es demasiado grande.
 */
suspend fun ModeloChat.enviarFoto(jpeg: ByteArray): Boolean {
    val carpeta = carpetaAdjuntos ?: return false
    if (!_adjuntosActivos.value || outbox == null) return false
    if (jpeg.isEmpty() || jpeg.size > ReglasChatAdjuntos.BYTES_MAXIMOS || jpeg.size < 3 || jpeg[0] != 0xFF.toByte() || jpeg[1] != 0xD8.toByte()) {
        avisar(ReglasChatAdjuntos.TEXTO_FOTO_ILEGIBLE)
        return false
    }
    val id = UUID.randomUUID().toString().lowercase()
    val destino = File(carpeta, "$id.jpg")
    val ok = withContext(Dispatchers.IO) { runCatching { carpeta.mkdirs(); destino.writeBytes(jpeg) }.isSuccess }
    if (!ok) {
        avisar(ReglasChatAdjuntos.TEXTO_FOTO_ILEGIBLE)
        return false
    }
    encolarAdjunto(id, AdjuntoChat.Tipo.FOTO, null, destino)
    return true
}

/** Un audio grabado (AAC en m4a). Se mueve a la carpeta de la cuenta con el nombre del id. Menos de 1 segundo no sale. */
suspend fun ModeloChat.enviarAudio(archivo: File, segundos: Double): Boolean {
    val carpeta = carpetaAdjuntos
    if (carpeta == null || !_adjuntosActivos.value || outbox == null) {
        archivo.delete()
        return false
    }
    if (!segundos.isFinite() || segundos < ReglasChatAdjuntos.AUDIO_MINIMO) {
        archivo.delete()
        avisar(ReglasChatAdjuntos.TEXTO_MUY_CORTO)
        return false
    }
    val largo = archivo.length()
    if (largo <= 0 || largo > ReglasChatAdjuntos.BYTES_MAXIMOS) {
        archivo.delete()
        return false
    }
    val id = UUID.randomUUID().toString().lowercase()
    val destino = File(carpeta, "$id.m4a")
    val movido = withContext(Dispatchers.IO) {
        carpeta.mkdirs()
        archivo.renameTo(destino) || runCatching { archivo.copyTo(destino, overwrite = true); archivo.delete() }.isSuccess
    }
    if (!movido) return false
    encolarAdjunto(id, AdjuntoChat.Tipo.AUDIO, Math.rint(minOf(segundos, audioMaximo)), destino)
    return true
}

private suspend fun ModeloChat.encolarAdjunto(id: String, tipo: AdjuntoChat.Tipo, segundos: Double?, archivo: File) {
    val creado = FechaIso.texto(Instant.now())
    _hilo.update { it.agregarPendiente(burbujaPendiente(id, tipo, segundos, creado)) }
    _archivos.update { it + (id to archivo) }
    val payload = linkedMapOf<String, ValorJson>(
        "id" to texto(id), "tipo" to texto(tipo.valor), "archivo" to texto(archivo.absolutePath), "creado" to texto(creado),
    )
    if (segundos != null) payload["segundos"] = ValorJson.Numero(segundos)
    outbox?.encolar(KIND_ADJUNTO_CHAT, ValorJson.Objeto(payload), claveAdjunto(id))
}

internal fun ModeloChat.avisar(t: String) {
    _anuncio.update { (it?.first ?: 0) + 1 to t }
}

// ── Lo que dice la cola ──

/**
 * Lo que quedó en la cola de antes (la app cerrada sin señal): las burbujas «enviando…» y «no salió» vuelven al hilo. Los
 * archivos de más de 14 días que nadie nombra se borran (si se vuelven a ver, se bajan de nuevo).
 */
suspend fun ModeloChat.cargarAdjuntosDeLaCola() {
    val cola = outbox ?: return
    val carpeta = carpetaAdjuntos ?: return
    // La carpeta se lista ANTES de leer la cola: lo que entra en el medio ya está nombrado.
    val presentes = withContext(Dispatchers.IO) { carpeta.listFiles()?.toList() ?: emptyList() }
    val ops = cola.operaciones().filter { it.kind == KIND_ADJUNTO_CHAT }
    val fallidos = cola.fallidos().filter { it.op.kind == KIND_ADJUNTO_CHAT }
    for (op in ops) restaurar(op, false, null)
    for (f in fallidos) if (ops.none { it.dedupeKey == f.op.dedupeKey }) restaurar(f.op, true, f.motivo)
    val nombrados = (ops + fallidos.map { it.op }).mapNotNull { it.payload["archivo"]?.comoTexto?.let { a -> File(a).name } }.toSet()
    val limite = System.currentTimeMillis() - ReglasChatAdjuntos.DIAS_EN_EL_TELEFONO * 86_400_000L
    for (f in presentes) {
        if (f.name == "estado.json" || f.name in nombrados) continue
        if (f.lastModified() < limite) {
            withContext(Dispatchers.IO) { f.delete() }
            _archivos.update { m -> m.filterValues { it != f } }
        } else {
            idDeArchivo(f.name)?.let { id -> _archivos.update { it + (id to f) } }
        }
    }
}

private fun ModeloChat.restaurar(op: Operacion, fallo: Boolean, motivo: String?) {
    val id = op.payload["id"]?.comoTexto ?: return
    val tipo = AdjuntoChat.Tipo.de(op.payload["tipo"]?.comoTexto) ?: return
    op.payload["archivo"]?.comoTexto?.let { a -> _archivos.update { it + (id to File(a)) } }
    if (_hilo.value.tieneAdjunto(id)) {
        if (fallo) _hilo.update { it.marcarAdjuntoFallido(id, motivoCorto(motivo)) }
        return
    }
    val creado = op.payload["creado"]?.comoTexto ?: FechaIso.texto(Instant.ofEpochMilli(op.ts.toLong()))
    _hilo.update { it.agregarPendiente(burbujaPendiente(id, tipo, op.payload["segundos"]?.comoNumero, creado, fallo, motivoCorto(motivo))) }
}

/** La cola guardó adjuntos: la burbuja pasa a ser la fila del servidor. El archivo queda en el teléfono. */
fun ModeloChat.alGuardarAdjuntos(ops: List<OpGuardada>) {
    for (g in ops) {
        if (g.op.kind != KIND_ADJUNTO_CHAT) continue
        val id = g.op.payload["id"]?.comoTexto ?: continue
        _hilo.update { it.confirmarAdjunto(id, g.respuesta["comentario_id"]?.comoTexto ?: "", g.respuesta["created_at"]?.comoTexto) }
    }
}

/** La cola los dejó en fallidos: «no salió» (con el motivo que guardó la cola). */
suspend fun ModeloChat.alAbandonarAdjuntos(ops: List<Operacion>) {
    val mias = ops.filter { it.kind == KIND_ADJUNTO_CHAT }
    val cola = outbox
    if (mias.isEmpty() || cola == null) return
    val fallidos = cola.fallidos()
    for (op in mias) {
        val id = op.payload["id"]?.comoTexto ?: continue
        val motivo = motivoCorto(fallidos.lastOrNull { it.op.dedupeKey == op.dedupeKey }?.motivo)
        // El id resultó ser de otro mensaje (dos UUID iguales): sale solo con uno nuevo, sin pasar por «no salió».
        if (motivo == ReglasChatAdjuntos.CODIGO_ID) {
            reintentarAdjunto(id)
            continue
        }
        _hilo.update { it.marcarAdjuntoFallido(id, motivo) }
        if (motivo == ReglasChatAdjuntos.CODIGO_TOPE) avisar(ReglasChatAdjuntos.TEXTO_TOPE)
    }
}

/**
 * «Reintentar»: si sigue en la cola, sale ya; si la cola lo dejó, vuelve a la cola con el mismo archivo (y con otro id si
 * el anterior resultó ser de otro mensaje). Primero se encola y después se olvida el fallido.
 */
suspend fun ModeloChat.reintentarAdjunto(id: String) {
    val cola = outbox ?: return
    val clave = claveAdjunto(id)
    if (cola.operaciones().any { it.dedupeKey == clave }) {
        _hilo.update { it.desmarcarAdjunto(id) }
        cola.drenar(esperarAudios = false)
        return
    }
    val f = cola.fallidos().lastOrNull { it.op.dedupeKey == clave } ?: return
    val o = (f.op.payload as? ValorJson.Objeto)?.campos ?: return
    val viejo = o["archivo"]?.comoTexto
    if (motivoCorto(f.motivo) != ReglasChatAdjuntos.CODIGO_ID || viejo == null) {
        _hilo.update { it.desmarcarAdjunto(id) }
        cola.encolar(KIND_ADJUNTO_CHAT, f.op.payload, clave)
        cola.olvidarFallidos(clave)
        return
    }
    val nuevo = UUID.randomUUID().toString().lowercase()
    val v = File(viejo)
    val destino = File(v.parentFile, "$nuevo.${v.extension}")
    if (!withContext(Dispatchers.IO) { v.renameTo(destino) }) return
    val p = LinkedHashMap(o).apply { put("id", texto(nuevo)); put("archivo", texto(destino.absolutePath)) }
    _archivos.update { it - id + (nuevo to destino) }
    _hilo.update { it.desmarcarAdjunto(id, nuevo) }
    cola.encolar(KIND_ADJUNTO_CHAT, ValorJson.Objeto(p), claveAdjunto(nuevo))
    cola.olvidarFallidos(clave)
}

/** «Borrar» en uno que no salió: se saca de la cola, del hilo y del teléfono. Nunca llegó a Mati. */
suspend fun ModeloChat.descartarAdjunto(id: String) {
    val cola = outbox ?: return
    val clave = claveAdjunto(id)
    if (cola.operaciones().any { it.dedupeKey == clave }) return   // sigue saliendo: no se toca
    cola.olvidarFallidos(clave)
    _archivos.value[id]?.let { withContext(Dispatchers.IO) { it.delete() } }
    _archivos.update { it - id }
    _hilo.update { it.quitarAdjuntoPendiente(id) }
}

// ── Ver y escuchar ──

/**
 * El archivo en el teléfono, o se baja con una URL firmada (se piden de a muchas y duran 50 minutos). null = no se pudo
 * (sin red, o ya no está): la burbuja lo dice y ofrece probar de nuevo.
 */
suspend fun ModeloChat.archivo(a: AdjuntoChat): File? {
    _archivos.value[a.id]?.let { if (it.isFile) return it }
    val carpeta = carpetaAdjuntos ?: return null
    if (a.borrado) return null
    val tarea = bajando.getOrPut(a.id) {
        alcance.async(start = CoroutineStart.LAZY) { bajar(a, carpeta) }
    }
    val f = try {
        tarea.await()
    } finally {
        bajando.remove(a.id, tarea)
    }
    if (f != null) {
        _archivos.update { it + (a.id to f) }
        _sinBajar.update { it - a.id }
    } else {
        _sinBajar.update { it + a.id }
    }
    return f
}

private suspend fun ModeloChat.bajar(a: AdjuntoChat, carpeta: File): File? {
    val firma = firma(a.id) ?: return null
    val r = try {
        cliente.transporte.enviar(Pedido(firma.url, "GET", emptyMap(), null, 60_000))
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        return null
    }
    if (r.status !in 200..299 || r.cuerpo.isEmpty()) return null
    val destino = File(carpeta, "${a.id}.${extensionDe(firma.mime)}")
    return withContext(Dispatchers.IO) { runCatching { carpeta.mkdirs(); destino.writeBytes(r.cuerpo); destino }.getOrNull() }
}

/** El formato real (un audio grabado desde la web en Firefox es webm u ogg, que el teléfono puede no reproducir). */
fun ModeloChat.formato(a: AdjuntoChat): String? = _archivos.value[a.id]?.let { mimeDeExtension(it.extension) } ?: firmas[a.id]?.mime

internal suspend fun ModeloChat.firma(id: String): FirmaAdjunto? {
    firmas[id]?.let { if (it.venceMs > System.currentTimeMillis()) return it }
    firmar(id)
    return firmas[id]?.takeIf { it.venceMs > System.currentTimeMillis() }
}

/** `/chat/urls`: las del hilo que no están en el teléfono ni tienen firma vigente, las más nuevas primero, con [id] adentro. */
internal suspend fun ModeloChat.firmar(id: String) {
    val ahora = System.currentTimeMillis()
    val ids = mutableListOf(id)
    for (a in _hilo.value.adjuntosReales.asReversed()) {
        if (ids.size >= ReglasChatAdjuntos.FIRMAS_POR_PEDIDO) break
        if (a.id != id && _archivos.value[a.id] == null && (firmas[a.id]?.venceMs ?: 0) <= ahora) ids += a.id
    }
    val cuerpo = ValorJson.objeto("token" to texto(token ?: ""), "ids" to ValorJson.Lista(ids.map { texto(it) }))
    val r = try {
        cliente.transporte.enviar(
            Pedido("${cliente.config.vision}/chat/urls", "POST", mapOf("Content-Type" to "application/json"), cuerpo.serializar().toByteArray(), 30_000),
        )
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        return
    }
    if (r.status >= 300) return
    val j = parsearJson(r.cuerpo) ?: return
    if (j["ok"] != ValorJson.Booleano(true)) return
    val filas = (j["adjuntos"] as? ValorJson.Lista)?.elementos ?: return
    val vence = ahora + ReglasChatAdjuntos.FIRMA_VIGENTE_MS
    for (f in filas) {
        val i = f["id"]?.comoTexto?.lowercase() ?: continue
        val u = f["url"]?.comoTexto ?: continue
        firmas[i] = FirmaAdjunto(u, f["mime"]?.comoTexto ?: "", vence)
    }
}

// ── La ejecución en la cola ──

/**
 * `chat_adjunto`: el archivo crudo a mini-vision (`POST /chat/adjunto`), con el id en un encabezado. Es idempotente: un
 * reintento de algo que ya entró contesta el mismo mensaje. Sin el archivo, o con un rechazo que no va a cambiar, va directo
 * a «no salió» sin gastar los 8 intentos.
 */
class EnvioAdjuntoChat(private val cliente: ClienteRpc, private val token: String) {
    suspend fun ejecutar(p: ValorJson): Resultado<ValorJson> {
        val id = p["id"]?.comoTexto?.takeIf { s -> runCatching { UUID.fromString(s) }.isSuccess }
            ?: return falla(ReglasChatAdjuntos.CODIGO_RECHAZO, "pedido inválido")
        val tipo = AdjuntoChat.Tipo.de(p["tipo"]?.comoTexto) ?: return falla(ReglasChatAdjuntos.CODIGO_RECHAZO, "pedido inválido")
        val archivo = p["archivo"]?.comoTexto?.let(::File) ?: return falla(ReglasChatAdjuntos.CODIGO_RECHAZO, "pedido inválido")
        // Un archivo que no se puede leer no es falta de red (una IOException acá la cola la tomaría como tal).
        val datos = withContext(Dispatchers.IO) { runCatching { archivo.takeIf { it.isFile }?.readBytes() }.getOrNull() }
        if (datos == null || datos.isEmpty()) return falla(ReglasChatAdjuntos.CODIGO_SIN_ARCHIVO, "sin archivo")
        if (datos.size > ReglasChatAdjuntos.BYTES_MAXIMOS) return falla(ReglasChatAdjuntos.CODIGO_RECHAZO, "muy grande")
        val cab = linkedMapOf(
            "Content-Type" to if (tipo == AdjuntoChat.Tipo.FOTO) ReglasChatAdjuntos.MIME_FOTO else ReglasChatAdjuntos.MIME_AUDIO,
            "x-chat-token" to token, "x-chat-id" to id.lowercase(), "x-chat-tipo" to tipo.valor,
        )
        if (tipo == AdjuntoChat.Tipo.AUDIO) {
            val s = Math.rint(p["segundos"]?.comoNumero ?: 1.0).coerceIn(1.0, ReglasChatAdjuntos.AUDIO_MAXIMO)
            cab["x-chat-duracion"] = s.toInt().toString()
        }
        val r = try {
            cliente.transporte.enviar(Pedido("${cliente.config.vision}/chat/adjunto", "POST", cab, datos, 120_000))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin respuesta"))
        }
        val j = parsearJson(r.cuerpo)
        val error = j?.get("error")?.comoTexto
        return when (ReglasChatAdjuntos.subida(r.status, j?.get("ok") == ValorJson.Booleano(true), error)) {
            ReglasChatAdjuntos.Subida.OK -> Resultado.Ok(
                ValorJson.objeto(
                    "ok" to ValorJson.Booleano(true), "id" to texto(id),
                    "comentario_id" to (j?.get("comentario_id") ?: ValorJson.Nulo), "created_at" to (j?.get("created_at") ?: ValorJson.Nulo),
                ),
            )
            ReglasChatAdjuntos.Subida.TOKEN -> Resultado.Ok(ValorJson.Nulo)   // `Escrituras.ejecutar` mira si cayó el token
            ReglasChatAdjuntos.Subida.REINTENTAR -> Resultado.Falla(ErrorRpc(ErrorRpc.Clase.TRANSITORIO, r.status, mensaje = error ?: "HTTP ${r.status}"))
            ReglasChatAdjuntos.Subida.TOPE -> falla(ReglasChatAdjuntos.CODIGO_TOPE, "tope", r.status)
            ReglasChatAdjuntos.Subida.ID_REPETIDO -> falla(ReglasChatAdjuntos.CODIGO_ID, "id", r.status)
            ReglasChatAdjuntos.Subida.RECHAZO -> falla(ReglasChatAdjuntos.CODIGO_RECHAZO, error ?: "HTTP ${r.status}", r.status)
        }
    }

    private fun falla(codigo: String, mensaje: String, status: Int = 0): Resultado<ValorJson> =
        Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, status, codigo, mensaje))
}
