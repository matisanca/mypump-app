package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.EstadoEstudios
import com.pumpteam.mypump.reglas.Estudios
import java.io.File
import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.serialization.json.Json

/** Un archivo de un envío. El contenido va en su propio archivo (`estudios-archivos/<id>.pdf|.jpg`); acá, solo el índice. */
data class ArchivoEstudios(val id: String, val mime: String, val subido: Boolean = false) {
    val nombre: String get() = id + if (mime == Estudios.MIME_PDF) ".pdf" else ".jpg"

    fun aValor(): ValorJson = ValorJson.objeto("id" to ValorJson.Texto(id), "mime" to ValorJson.Texto(mime), "subido" to ValorJson.Booleano(subido))

    companion object {
        fun desde(v: ValorJson): ArchivoEstudios? {
            val mime = v["mime"]?.comoTexto?.takeIf { it == Estudios.MIME_PDF || it == Estudios.MIME_JPEG } ?: return null
            return ArchivoEstudios(v["id"]?.comoTexto ?: return null, mime, v["subido"] == ValorJson.Booleano(true))
        }
    }
}

/** Lo que el alumno ya mandó y sale solo, aunque cierre la app: `envio_nuevo` → `upload` de cada archivo → `enviar`. */
data class EnvioEstudios(
    /** Lo genera el teléfono: un reintento cae en el mismo envío. */
    val id: String,
    val pedidoId: String? = null,
    val archivos: List<ArchivoEstudios> = emptyList(),
    /** `envio_nuevo` ya contestó que sí. */
    val creado: Boolean = false,
    /** Archivos que el servidor no quiso (4xx): ya no están en la lista. */
    val rechazados: Int = 0,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("id", ValorJson.Texto(id))
            pedidoId?.let { put("pedidoId", ValorJson.Texto(it)) }
            put("archivos", ValorJson.Lista(archivos.map { it.aValor() }))
            put("creado", ValorJson.Booleano(creado))
            put("rechazados", ValorJson.Numero(rechazados.toDouble()))
        },
    )

    companion object {
        fun desde(v: ValorJson): EnvioEstudios? = EnvioEstudios(
            v["id"]?.comoTexto ?: return null, v["pedidoId"]?.comoTexto,
            (v["archivos"] as? ValorJson.Lista)?.elementos?.mapNotNull(ArchivoEstudios::desde) ?: emptyList(),
            v["creado"] == ValorJson.Booleano(true), v["rechazados"]?.comoNumero?.toInt() ?: 0,
        )
    }
}

object ColaEstudios {
    const val ARCHIVO = "estudios-cola.json"
    const val CARPETA = "estudios-archivos"

    fun leer(disco: Disco): List<EnvioEstudios> {
        val j = disco.leer(ARCHIVO) ?: return emptyList()
        return (ValorJson.desde(j) as? ValorJson.Lista)?.elementos?.mapNotNull(EnvioEstudios::desde) ?: emptyList()
    }

    /** Donde esperan los archivos de la cuenta de [disco]: bajo [raiz] (en la app, `noBackupFilesDir`), nunca en almacenamiento compartido. */
    fun carpeta(raiz: File, disco: Disco): File = File(raiz, "MyPump/${disco.carpeta.name}/$CARPETA")
}

/**
 * «Estudios y órdenes». Mismo criterio de cola que [ModeloGimnasio]: en disco, sobrevive a cerrar la app y a quedarse sin
 * señal, un error del servidor (5xx o 429) no gasta el archivo y todo 4xx es definitivo para ese archivo. Con la palanca
 * `estudios_app` apagada [ModeloApp] no llama a nada de esto: [estado] queda en null y no se ve ni se pide nada.
 *
 * Son datos de salud: los archivos esperan en [carpetaArchivos] (fuera de toda copia de seguridad y de la galería), se
 * borran al quedar enviados, y de acá no sale nada a registros ni a analítica.
 */
class ModeloEstudios(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    /** La carpeta de los archivos en cola. Sin ella no se puede encolar. */
    val carpetaArchivos: File?,
    /** Espera entre reintentos, en milisegundos (en las pruebas, nada). */
    private val esperar: suspend (Long) -> Unit = { delay(it) },
    private val lanzar: (suspend () -> Unit) -> Unit = {},
) {
    enum class Aviso { RECIBIDO, RECIBIDO_CON_RECHAZO, TOPE_DIA, RECHAZADO }
    enum class Salida { OK, FECHA, SIN_SENAL, ERROR }
    data class Progreso(val va: Int, val total: Int)
    data class Nuevo(val archivo: File, val mime: String)
    data class Remoto(val url: String, val mime: String)

    sealed interface Apertura {
        data class Ok(val archivos: List<Remoto>) : Apertura
        data object TodaviaNo : Apertura
        data object Error : Apertura
    }

    private val _estado = MutableStateFlow<EstadoEstudios?>(null)
    /** null: apagado, sin el servidor nuevo, sin habilitar para esta cuenta, o sin red sin nada guardado. No se muestra nada. */
    val estado: StateFlow<EstadoEstudios?> = _estado.asStateFlow()
    private val _cola = MutableStateFlow(disco?.let(ColaEstudios::leer) ?: emptyList())
    val cola: StateFlow<List<EnvioEstudios>> = _cola.asStateFlow()
    private val _progreso = MutableStateFlow<Progreso?>(null)
    /** «Subiendo 2 de 5». */
    val progreso: StateFlow<Progreso?> = _progreso.asStateFlow()
    private val _sinSenal = MutableStateFlow(false)
    /** La última pasada se cortó por la red y queda algo por salir. */
    val sinSenal: StateFlow<Boolean> = _sinSenal.asStateFlow()
    private val _aviso = MutableStateFlow<Aviso?>(null)
    val aviso: StateFlow<Aviso?> = _aviso.asStateFlow()
    private val _errorCarga = MutableStateFlow(false)
    /** El último `get` no llegó: lo que se ve es lo último que se supo. */
    val errorCarga: StateFlow<Boolean> = _errorCarga.asStateFlow()

    private val drenando = Mutex()
    private val reintentoProgramado = AtomicBoolean(false)
    private val vueltas = ConcurrentHashMap<String, Int>()
    private val regenerados = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var reintentosDeFondo = 0

    init {
        barrerHuerfanos()
    }

    /** Un cierre entre copiar el archivo y guardar el índice deja un archivo que nadie sube ni borra. */
    private fun barrerHuerfanos() {
        val vivos = _cola.value.flatMap { e -> e.archivos.map { it.nombre } }.toSet()
        carpetaArchivos?.listFiles()?.filter { it.name !in vivos }?.forEach { it.delete() }
    }

    /** La palanca `estudios_app` que se leyó por última vez. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
    }

    /** Hay algo esperando salir. */
    val hayCola: Boolean get() = _cola.value.isNotEmpty()

    // ── Servidor ──

    /** `get`. Sin el servidor nuevo o apagado para esta cuenta: nada. Sin red, lo último que se supo. */
    suspend fun refrescar() {
        when (val r = cliente.llamar("mypump_estudios_get", mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                _errorCarga.value = false
                if (r.valor == ValorJson.Nulo) {   // token caído: lo guardado queda para el link nuevo
                    _estado.value = null
                    return
                }
                val e = EstadoEstudios.desde(r.valor)
                if (e == null) {
                    apagar()
                    return
                }
                _estado.value = e
                disco?.guardar(ARCHIVO_ESTADO, r.valor)
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                } else {
                    if (_estado.value == null) _estado.value = disco?.leer(ARCHIVO_ESTADO)?.let { EstadoEstudios.desde(ValorJson.desde(it)) }
                    _errorCarga.value = _estado.value != null
                }
            }
        }
    }

    /** La sección deja de existir. La cola no se toca: si se vuelve a prender, sale. */
    fun apagar() {
        _estado.value = null
        _errorCarga.value = false
        _progreso.value = null
        _sinSenal.value = false
        disco?.borrar(ARCHIVO_ESTADO)
    }

    /** «Ya me lo hice» con su fecha; null lo deshace. */
    suspend fun marcarHecho(pedidoId: String, fecha: LocalDate?): Salida {
        val p = mapOf("p_token" to ValorJson.Texto(token), "p_pedido_id" to ValorJson.Texto(pedidoId), "p_fecha" to (fecha?.let { ValorJson.Texto(it.toString()) } ?: ValorJson.Nulo))
        return when (val r = cliente.llamar("mypump_estudios_hecho", p)) {
            is Resultado.Ok -> when {
                r.valor["ok"] == ValorJson.Booleano(true) -> {
                    refrescar()
                    Salida.OK
                }
                r.valor["error"]?.comoTexto == "fecha" -> Salida.FECHA
                r.valor["error"]?.comoTexto == "no_habilitado" -> {
                    apagar()
                    Salida.ERROR
                }
                else -> {
                    if (r.valor != ValorJson.Nulo) refrescar()
                    Salida.ERROR
                }
            }
            is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) Salida.ERROR else Salida.SIN_SENAL
        }
    }

    // ── Encolar ──

    /**
     * «Enviar»: los archivos de la hoja (fotos ya en JPEG, PDF tal cual) pasan a la carpeta propia, cada uno con su id, y
     * el envío queda en la cola. Los originales de [nuevos] se borran. Después hay que drenar. Devuelve si quedó guardado.
     */
    fun encolar(nuevos: List<Nuevo>, pedidoId: String?): Boolean {
        val d = disco ?: return false
        val carpeta = carpetaArchivos ?: return false
        if (nuevos.isEmpty() || _estado.value == null) return false
        val archivos = ArrayList<ArchivoEstudios>()
        var bien = true
        for (n in nuevos) {
            val a = ArchivoEstudios(UUID.randomUUID().toString().lowercase(), n.mime)
            if (!mover(n.archivo, File(carpeta, a.nombre))) {
                bien = false
                break
            }
            archivos += a
        }
        val envio = EnvioEstudios(UUID.randomUUID().toString().lowercase(), pedidoId, archivos)
        if (bien) {
            _cola.update { it + envio }
            bien = guardarCola(d)
            if (!bien) _cola.update { l -> l.filter { it.id != envio.id } }
        }
        if (!bien) {
            archivos.forEach { File(carpeta, it.nombre).delete() }
            return false
        }
        nuevos.forEach { it.archivo.delete() }
        _aviso.value = null
        _sinSenal.value = false
        _progreso.value = Progreso(1, archivos.size)
        return true
    }

    private fun mover(desde: File, hasta: File): Boolean = try {
        hasta.parentFile?.mkdirs()
        if (!desde.renameTo(hasta)) {
            desde.inputStream().use { e -> hasta.outputStream().use { s -> e.copyTo(s); s.fd.sync() } }
        }
        hasta.length() > 0
    } catch (_: Exception) {
        hasta.delete()
        false
    }

    fun limpiarAviso() {
        _aviso.value = null
    }

    // ── Cola ──

    private enum class Fin { LISTO, SEGUIR, RED, MAS_TARDE, PARAR }
    private enum class Subida { OK, PERDIDO, DESCARTAR, REINTENTAR, RED }

    /** Una pasada a la vez, un envío detrás de otro. Red: corta y espera a que vuelva. 5xx o 429: espera y reintenta. */
    suspend fun drenar() {
        if (_estado.value == null || _cola.value.isEmpty() || !drenando.tryLock()) return
        var huboEnviado = false
        try {
            _sinSenal.value = false
            pasada@ while (_estado.value != null) {
                val e = _cola.value.firstOrNull() ?: break
                when (procesar(e)) {
                    Fin.LISTO -> huboEnviado = true
                    Fin.SEGUIR -> Unit
                    Fin.RED -> {
                        _sinSenal.value = true
                        break@pasada
                    }
                    Fin.MAS_TARDE -> {
                        programarReintento()
                        break@pasada
                    }
                    Fin.PARAR -> break@pasada
                }
            }
        } finally {
            _progreso.value = null
            drenando.unlock()
        }
        if (huboEnviado) refrescar()
    }

    /** Una pasada sin esperarla, atada a la vida de la app: cambiar de pantalla no corta la subida. */
    fun drenarEnFondo() {
        lanzar { drenar() }
    }

    private fun programarReintento() {
        if (reintentosDeFondo >= MAX_REINTENTOS_DE_FONDO || !reintentoProgramado.compareAndSet(false, true)) return
        reintentosDeFondo++
        lanzar {
            esperar(60_000)
            reintentoProgramado.set(false)
            drenar()
        }
    }

    private fun texto(s: String) = ValorJson.Texto(s)

    private suspend fun procesar(inicial: EnvioEstudios): Fin {
        var env = inicial
        if (!env.creado) {
            val p = mapOf("p_token" to texto(token), "p_id" to texto(env.id), "p_pedido_id" to (env.pedidoId?.let(::texto) ?: ValorJson.Nulo))
            when (val r = cliente.llamar("mypump_estudios_envio_nuevo", p)) {
                is Resultado.Ok -> {
                    val j = r.valor
                    if (j == ValorJson.Nulo) return Fin.PARAR   // token caído: queda guardado para el link nuevo
                    if (j["ok"] == ValorJson.Booleano(true)) {
                        if (j["estado"]?.comoTexto == "enviado") return terminar(env)   // ya había salido: un reintento
                        env = actualizar(env, env.copy(creado = true))
                    } else {
                        return when (j["error"]?.comoTexto) {
                            "tope_dia" -> {
                                descartar(env, Aviso.TOPE_DIA)
                                Fin.SEGUIR
                            }
                            "no_habilitado" -> {
                                apagar()
                                Fin.PARAR
                            }
                            "id_repetido" -> {
                                // El id ya es de otro: se prueba una vez con uno nuevo.
                                if (regenerados.add(env.id)) {
                                    val nuevo = UUID.randomUUID().toString().lowercase()
                                    regenerados.add(nuevo)
                                    actualizar(env, env.copy(id = nuevo))
                                } else {
                                    descartar(env, Aviso.RECHAZADO)
                                }
                                Fin.SEGUIR
                            }
                            else -> Fin.MAS_TARDE
                        }
                    }
                }
                is Resultado.Falla -> return alFallar(r.error)
            }
        }

        var seguidas = 0
        while (true) {
            val a = env.archivos.firstOrNull { !it.subido } ?: break
            _progreso.value = Progreso(env.archivos.count { it.subido } + 1, env.archivos.size)
            when (subir(env, a)) {
                Subida.OK -> {
                    env = actualizar(env, env.copy(archivos = env.archivos.map { if (it.id == a.id) it.copy(subido = true) else it }))
                    seguidas = 0
                    reintentosDeFondo = 0
                }
                Subida.PERDIDO, Subida.DESCARTAR -> {
                    archivo(a).delete()
                    env = actualizar(env, env.copy(archivos = env.archivos.filter { it.id != a.id }, rechazados = env.rechazados + 1))
                }
                Subida.REINTENTAR -> {
                    seguidas++
                    if (seguidas >= MAX_INTENTOS_SEGUIDOS) return Fin.MAS_TARDE
                    esperar(1000L shl seguidas)
                }
                Subida.RED -> return Fin.RED
            }
        }
        if (env.archivos.isEmpty()) {
            // No quedó ninguno: el envío se descarta en silencio y se le dice que pruebe con otro archivo.
            descartar(env, Aviso.RECHAZADO)
            return Fin.SEGUIR
        }

        val p = mapOf("p_token" to texto(token), "p_id" to texto(env.id), "p_archivos" to ValorJson.Numero(env.archivos.size.toDouble()))
        return when (val r = cliente.llamar("mypump_estudios_enviar", p)) {
            is Resultado.Ok -> {
                val j = r.valor
                when {
                    j == ValorJson.Nulo -> Fin.PARAR
                    j["ok"] == ValorJson.Booleano(true) -> terminar(env)
                    else -> when (j["error"]?.comoTexto) {
                        // En el servidor hay menos que acá: se suben de nuevo (los que ya están contestan `ya`).
                        "faltan_archivos", "sin_archivos" -> {
                            actualizar(env, env.copy(archivos = env.archivos.map { it.copy(subido = false) }))
                            if (otraVuelta(env.id)) Fin.SEGUIR else Fin.MAS_TARDE
                        }
                        "no_encontrado" -> {
                            if (otraVuelta(env.id)) {
                                actualizar(env, env.copy(creado = false, archivos = env.archivos.map { it.copy(subido = false) }))
                            } else {
                                descartar(env, Aviso.RECHAZADO)
                            }
                            Fin.SEGUIR
                        }
                        "no_habilitado" -> {
                            apagar()
                            Fin.PARAR
                        }
                        else -> Fin.MAS_TARDE
                    }
                }
            }
            is Resultado.Falla -> alFallar(r.error)
        }
    }

    private fun otraVuelta(id: String): Boolean = vueltas.merge(id, 1, Int::plus)!! <= MAX_VUELTAS

    private fun alFallar(e: ErrorRpc): Fin = when (e.clase) {
        ErrorRpc.Clase.RED -> Fin.RED
        ErrorRpc.Clase.TRANSITORIO -> Fin.MAS_TARDE
        // La función ya no está o el servidor dijo que no: la sección se apaga y la cola queda guardada.
        ErrorRpc.Clase.PERMANENTE -> {
            apagar()
            Fin.PARAR
        }
    }

    private suspend fun subir(env: EnvioEstudios, a: ArchivoEstudios): Subida {
        val f = archivo(a)
        if (!f.isFile || f.length() == 0L) return Subida.PERDIDO
        val pedido = Pedido(
            url = "${cliente.config.vision}/estudios/upload", metodo = "POST",
            cabeceras = mapOf("Content-Type" to a.mime, "x-estudios-token" to token, "x-estudios-envio" to env.id, "x-estudios-archivo" to a.id),
            cuerpo = null, esperaMs = 180_000, archivo = f,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return Subida.RED
        }
        return when (Estudios.clasificarSubida(r.status, parsear(r.cuerpo)?.get("ok") == ValorJson.Booleano(true))) {
            Estudios.Accion.OK -> Subida.OK
            Estudios.Accion.DESCARTAR -> Subida.DESCARTAR
            Estudios.Accion.REINTENTAR -> Subida.REINTENTAR
        }
    }

    /** Cambia el envío en la cola (y en disco). Devuelve el nuevo. */
    private fun actualizar(viejo: EnvioEstudios, nuevo: EnvioEstudios): EnvioEstudios {
        _cola.update { l -> l.map { if (it.id == viejo.id) nuevo else it } }
        disco?.let(::guardarCola)
        return nuevo
    }

    private fun sacar(env: EnvioEstudios) {
        env.archivos.forEach { archivo(it).delete() }
        _cola.update { l -> l.filter { it.id != env.id } }
        disco?.let(::guardarCola)
        vueltas.remove(env.id)
    }

    private fun descartar(env: EnvioEstudios, aviso: Aviso) {
        sacar(env)
        _aviso.value = aviso
    }

    /** Quedó `enviado`: los archivos locales se borran. */
    private fun terminar(env: EnvioEstudios): Fin {
        sacar(env)
        _aviso.value = if (env.rechazados > 0) Aviso.RECIBIDO_CON_RECHAZO else Aviso.RECIBIDO
        return Fin.LISTO
    }

    // ── Abrir una orden o un estudio propio ──

    /** Las URL duran 10 minutos: se piden al tocar «Ver» y nunca se guardan. */
    suspend fun urls(clase: String, id: String): Apertura {
        val cuerpo = ValorJson.objeto("token" to texto(token), "clase" to texto(clase), "id" to texto(id))
        val pedido = Pedido(
            url = "${cliente.config.vision}/estudios/urls", metodo = "POST", cabeceras = mapOf("Content-Type" to "application/json"),
            cuerpo = cuerpo.serializar().toByteArray(), esperaMs = 30_000,
        )
        val r = try {
            cliente.transporte.enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return Apertura.Error
        }
        val j = parsear(r.cuerpo)
        if (r.status == 409 && j?.get("error")?.comoTexto == "todavia_no") return Apertura.TodaviaNo
        if (r.status !in 200..299 || j?.get("ok") != ValorJson.Booleano(true)) return Apertura.Error
        val archivos = (j["archivos"] as? ValorJson.Lista)?.elementos?.mapNotNull { a ->
            Remoto(a["url"]?.comoTexto?.takeIf { it.startsWith("https://") } ?: return@mapNotNull null, a["mime"]?.comoTexto ?: "")
        } ?: emptyList()
        return if (archivos.isEmpty()) Apertura.Error else Apertura.Ok(archivos)
    }

    /** Baja un archivo para verlo a [destino] (un temporal que borra quien lo pidió al cerrar). Devuelve si quedó entero. */
    suspend fun bajar(remoto: Remoto, destino: File): Boolean {
        val r = try {
            cliente.transporte.enviar(Pedido(url = remoto.url, metodo = "GET", cabeceras = emptyMap(), cuerpo = null, esperaMs = 120_000))
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return false
        }
        if (r.status !in 200..299 || r.cuerpo.isEmpty()) return false
        return try {
            destino.parentFile?.mkdirs()
            destino.writeBytes(r.cuerpo)
            true
        } catch (_: Exception) {
            destino.delete()
            false
        }
    }

    private fun parsear(cuerpo: ByteArray): ValorJson? = try {
        ValorJson.desde(Json.parseToJsonElement(cuerpo.toString(Charsets.UTF_8)))
    } catch (_: Exception) {
        null
    }

    // ── Disco ──

    fun archivo(a: ArchivoEstudios): File = File(carpetaArchivos ?: File("/nonexistent"), a.nombre)

    private fun guardarCola(d: Disco): Boolean {
        val c = _cola.value
        if (c.isEmpty()) {
            d.borrar(ColaEstudios.ARCHIVO)
            return true
        }
        return d.guardar(ColaEstudios.ARCHIVO, ValorJson.Lista(c.map { it.aValor() }))
    }

    /** Los envíos que quedaron en la carpeta de otro link de la misma persona ([CuentasDelTelefono.adoptarEstudios]). */
    internal fun adoptar(otros: List<EnvioEstudios>, carpetaVieja: File): Boolean {
        val d = disco ?: return false
        val carpeta = carpetaArchivos ?: return false
        var todos = true
        for (e in otros) {
            if (_cola.value.any { it.id == e.id }) continue
            val llegaron = e.archivos.filter { a -> mover(File(carpetaVieja, a.nombre), File(carpeta, a.nombre)) }
            if (llegaron.size != e.archivos.size) todos = false
            if (llegaron.isNotEmpty()) _cola.update { it + e.copy(archivos = llegaron) }
        }
        return guardarCola(d) && todos
    }

    companion object {
        const val ARCHIVO_ESTADO = "estudios-estado.json"
        const val ARCHIVO_PALANCA = "estudios-palanca.json"
        const val MAX_INTENTOS_SEGUIDOS = 3
        const val MAX_REINTENTOS_DE_FONDO = 5
        const val MAX_VUELTAS = 2
    }
}
