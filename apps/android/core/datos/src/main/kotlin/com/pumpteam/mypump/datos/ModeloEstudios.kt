package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.EstadoEstudios
import com.pumpteam.mypump.reglas.Estudios
import java.io.File
import java.security.MessageDigest
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
    /** Cuándo se mandó (ms): un envío que no pudo salir en [ColaEstudios.DIAS_DE_VIDA] días se borra del teléfono. */
    val creadoEn: Long? = null,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("id", ValorJson.Texto(id))
            pedidoId?.let { put("pedidoId", ValorJson.Texto(it)) }
            put("archivos", ValorJson.Lista(archivos.map { it.aValor() }))
            put("creado", ValorJson.Booleano(creado))
            put("rechazados", ValorJson.Numero(rechazados.toDouble()))
            creadoEn?.let { put("creadoEn", ValorJson.Numero(it.toDouble())) }
        },
    )

    companion object {
        fun desde(v: ValorJson): EnvioEstudios? = EnvioEstudios(
            v["id"]?.comoTexto ?: return null, v["pedidoId"]?.comoTexto,
            (v["archivos"] as? ValorJson.Lista)?.elementos?.mapNotNull(ArchivoEstudios::desde) ?: emptyList(),
            v["creado"] == ValorJson.Booleano(true), v["rechazados"]?.comoNumero?.toInt() ?: 0, v["creadoEn"]?.comoNumero?.toLong(),
        )
    }
}

object ColaEstudios {
    const val ARCHIVO = "estudios-cola.json"
    const val CARPETA = "estudios-archivos"

    /** En la caché de la app: lo elegido en la hoja y todavía no enviado. */
    const val CARPETA_BORRADOR = "estudios-borrador"

    /** En la caché de la app: lo que se bajó para ver. */
    const val CARPETA_VER = "estudios-ver"

    /** En la caché de la app: donde la cámara deja la foto cruda (con sus metadatos) hasta que se convierte. */
    const val CARPETA_CAMARA = "camara"
    const val FOTO_CAMARA = "foto-estudios.jpg"
    const val PREFIJO_CAMARA = "estudios-"

    /** Un envío que no pudo salir en dos semanas no se queda en el teléfono para siempre. */
    const val DIAS_DE_VIDA = 14L

    /**
     * Al arrancar, lo elegido y no enviado se borra pasada una hora: antes puede ser la hoja que Android va a restaurar
     * (cerró la app con la cámara abierta).
     */
    const val MS_DE_GRACIA_AL_ARRANCAR = 3_600_000L

    /** De versiones anteriores: el estado del servidor y la palanca ya no se guardan en el teléfono. */
    private val RESTOS = listOf("estudios-estado.json", "estudios-palanca.json")

    fun leer(disco: Disco): List<EnvioEstudios> {
        val j = disco.leer(ARCHIVO) ?: return emptyList()
        return (ValorJson.desde(j) as? ValorJson.Lista)?.elementos?.mapNotNull(EnvioEstudios::desde) ?: emptyList()
    }

    fun guardar(disco: Disco, cola: List<EnvioEstudios>): Boolean {
        if (cola.isEmpty()) {
            disco.borrar(ARCHIVO)
            return true
        }
        return disco.guardar(ARCHIVO, ValorJson.Lista(cola.map { it.aValor() }))
    }

    /** Donde esperan los archivos de la cuenta de [disco]: bajo [raiz] (en la app, `noBackupFilesDir`), nunca en almacenamiento compartido. */
    fun carpeta(raiz: File, disco: Disco): File = File(raiz, "MyPump/${disco.carpeta.name}/$CARPETA")

    /**
     * Deja la cola de una cuenta como tiene que estar y la devuelve: sin los envíos vencidos, sin archivos que ningún
     * envío nombre (un cierre entre copiar el archivo y guardar el índice) y sin lo que guardaban versiones anteriores.
     * Un envío sin fecha (de antes de que se anotara) empieza a contar ahora.
     */
    fun sanear(disco: Disco, carpeta: File?, ahora: Long): List<EnvioEstudios> {
        RESTOS.forEach(disco::borrar)
        val leidos = leer(disco)
        val limite = ahora - DIAS_DE_VIDA * 86_400_000L
        val cola = leidos.filter { (it.creadoEn ?: ahora) >= limite }.map { if (it.creadoEn == null) it.copy(creadoEn = ahora) else it }
        if (cola != leidos) guardar(disco, cola)
        val vivos = cola.flatMap { e -> e.archivos.map { it.nombre } }.toSet()
        carpeta?.listFiles()?.filter { it.name !in vivos }?.forEach { it.delete() }
        return cola
    }

    /**
     * Al arrancar la app, con o sin la sección prendida y con o sin sesión: lo de «Estudios» de TODAS las cuentas de este
     * teléfono (otro link, sesión cerrada, cuenta dada de baja) pasa por [sanear], y de la caché se va lo que se bajó para
     * ver, la foto cruda de la cámara y lo elegido que ya nadie va a enviar.
     */
    fun barrerTelefono(raizDisco: File, raizArchivos: File, raizCache: File?, ahora: Long = System.currentTimeMillis()) {
        val cuentas = File(raizDisco, "MyPump").listFiles { f -> f.isDirectory && f.name.startsWith("cuenta-") }.orEmpty()
        for (c in cuentas) {
            val d = Disco(c)
            sanear(d, carpeta(raizArchivos, d), ahora)
        }
        // Archivos de una cuenta cuya carpeta ya no está: nadie los va a subir.
        val nombres = cuentas.map { it.name }.toSet()
        File(raizArchivos, "MyPump").listFiles { f -> f.isDirectory && f.name !in nombres }?.forEach { File(it, CARPETA).deleteRecursively() }
        raizCache?.let { limpiarCache(it, ahora - MS_DE_GRACIA_AL_ARRANCAR) }
    }

    /**
     * Lo de «Estudios» en la caché de la app. Lo que se bajó para ver y las fotos crudas que se estaban convirtiendo se
     * borran siempre; lo elegido en la hoja y la foto que la cámara acaba de dejar, solo si son anteriores a [antesDe]
     * (sin límite: todo).
     */
    fun limpiarCache(raizCache: File, antesDe: Long = Long.MAX_VALUE) {
        fun viejo(f: File) = f.lastModified() < antesDe
        File(raizCache, CARPETA_VER).deleteRecursively()
        File(raizCache, CARPETA_BORRADOR).listFiles()?.filter(::viejo)?.forEach { it.delete() }
        File(raizCache, CARPETA_CAMARA).listFiles()
            ?.filter { (it.name == FOTO_CAMARA && viejo(it)) || (it.name.startsWith(PREFIJO_CAMARA) && it.name.endsWith(".jpg")) }
            ?.forEach { it.delete() }
    }
}

/**
 * «Estudios y órdenes». Mismo criterio de cola que [ModeloGimnasio]: en disco, sobrevive a cerrar la app y a quedarse sin
 * señal y un error del servidor (5xx o 429) no gasta el archivo. Tampoco lo gasta lo que no habla del archivo sino del link
 * o del envío (401, 403, 404 y 409 de la subida); el resto de los 4xx es definitivo para ese archivo. Con la palanca
 * `estudios_app` apagada, o sin haberla leído en esta sesión, no se llama a nada: [estado] queda en null y no se ve ni se
 * pide nada.
 *
 * Son datos de salud: los archivos esperan en [carpetaArchivos] (fuera de toda copia de seguridad y de la galería), se
 * borran al quedar enviados o a los [ColaEstudios.DIAS_DE_VIDA] días, el estado del servidor no se guarda en el teléfono,
 * y de acá no sale nada a registros ni a analítica.
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
    private val ahora: () -> Long = System::currentTimeMillis,
) {
    enum class Aviso { RECIBIDO, RECIBIDO_CON_RECHAZO, TOPE_DIA, RECHAZADO, ERROR }
    enum class Salida { OK, FECHA, SIN_SENAL, ERROR }
    data class Progreso(val va: Int, val total: Int)
    data class Nuevo(val archivo: File, val mime: String)
    data class Remoto(val url: String, val mime: String)

    /** Un archivo elegido en la hoja de subida, antes de «Enviar». */
    data class Elegido(
        val archivo: File,
        val mime: String,
        /** Para no sumar dos veces los mismos bytes. */
        val huella: String,
    ) {
        val esPdf: Boolean get() = mime == Estudios.MIME_PDF
    }

    /** Lugar apartado en la hoja para archivos que se están convirtiendo. */
    data class Reserva(val entran: Int, val hoja: Int)

    sealed interface Apertura {
        data class Ok(val archivos: List<Remoto>) : Apertura
        data object TodaviaNo : Apertura
        data object Error : Apertura
    }

    private val _estado = MutableStateFlow<EstadoEstudios?>(null)
    /** null: apagado, sin el servidor nuevo, sin habilitar para esta cuenta, o todavía no se supo nada. No se muestra nada. */
    val estado: StateFlow<EstadoEstudios?> = _estado.asStateFlow()
    private val _palanca = MutableStateFlow<Boolean?>(null)
    /**
     * La palanca `estudios_app` leída en esta sesión; null hasta que se lee. No se recuerda de una vez para la otra: sin
     * una lectura fresca la sección no llama a nada (lo que quedó en la cola espera en el disco hasta que se lea).
     */
    val palanca: StateFlow<Boolean?> = _palanca.asStateFlow()
    private val _cola = MutableStateFlow(disco?.let { ColaEstudios.sanear(it, carpetaArchivos, ahora()) } ?: emptyList())
    val cola: StateFlow<List<EnvioEstudios>> = _cola.asStateFlow()
    private val _progreso = MutableStateFlow<Progreso?>(null)
    /** «Subiendo 2 de 5». */
    val progreso: StateFlow<Progreso?> = _progreso.asStateFlow()
    private val _sinSenal = MutableStateFlow(false)
    /** La última pasada se cortó por la red y queda algo por salir. */
    val sinSenal: StateFlow<Boolean> = _sinSenal.asStateFlow()
    private val _detenida = MutableStateFlow(false)
    /** La última pasada se cortó por otra cosa (el link, el servidor) y nada la va a retomar sola: hay que ofrecer «Probar de nuevo». */
    val detenida: StateFlow<Boolean> = _detenida.asStateFlow()
    private val _aviso = MutableStateFlow<Aviso?>(null)
    val aviso: StateFlow<Aviso?> = _aviso.asStateFlow()
    private val _errorCarga = MutableStateFlow(false)
    /** El último `get` no llegó: lo que se ve es lo que ya se veía en esta sesión y puede estar viejo. */
    val errorCarga: StateFlow<Boolean> = _errorCarga.asStateFlow()
    private val _borrador = MutableStateFlow<List<Elegido>>(emptyList())
    /** Lo elegido en la hoja de subida. Vive acá para que rotar el teléfono no lo pierda. */
    val borrador: StateFlow<List<Elegido>> = _borrador.asStateFlow()
    private val _preparando = MutableStateFlow(0)
    /** Archivos que se están convirtiendo para la hoja. */
    val preparando: StateFlow<Int> = _preparando.asStateFlow()

    private val drenando = Mutex()
    private val reintentoProgramado = AtomicBoolean(false)
    private val vueltas = ConcurrentHashMap<String, Int>()
    private val regenerados = ConcurrentHashMap.newKeySet<String>()
    @Volatile private var reintentosDeFondo = 0
    private val candadoHoja = Any()
    /** Cambia cada vez que se descarta o se envía lo elegido: una foto que se estaba convirtiendo para la hoja anterior no entra en la próxima. */
    private var hoja = 0

    init {
        if (disco == null) carpetaArchivos?.listFiles()?.forEach { it.delete() }
    }

    /** Lo que dijo `get_app_config` recién. Apagada, la sección deja de existir en el momento. */
    fun usarPalanca(prendida: Boolean) {
        _palanca.value = prendida
        if (!prendida) apagar()
    }

    /** Hay algo esperando salir. */
    val hayCola: Boolean get() = _cola.value.isNotEmpty()

    val topeArchivos: Int get() = _estado.value?.topeArchivos ?: Estudios.TOPE_ARCHIVOS

    // ── Servidor ──

    /** Lo que hace la pantalla al abrirse y al deslizar: con la palanca prendida, `get` y que salga lo pendiente. Si no, nada. */
    suspend fun sincronizar() {
        if (_palanca.value != true) {
            apagar()
            return
        }
        refrescar()
        drenarEnFondo()   // un PDF grande no frena a quien espera
    }

    /** «Probar de nuevo» con la cola detenida. */
    suspend fun reintentar() {
        reintentosDeFondo = 0
        _detenida.value = false
        sincronizar()
    }

    /**
     * `get`. Token caído, función inexistente o `habilitado: false`: la sección no existe. Sin red se queda con lo que ya
     * se veía en esta sesión (nada se guarda en el teléfono) y avisa que no se pudo cargar.
     */
    suspend fun refrescar() {
        when (val r = cliente.llamar("mypump_estudios_get", mapOf("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                val e = if (r.valor == ValorJson.Nulo) null else EstadoEstudios.desde(r.valor)
                if (e == null) {
                    apagar()
                    return
                }
                _estado.value = e
                _errorCarga.value = false
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                } else {
                    _errorCarga.value = _estado.value != null
                }
            }
        }
    }

    /** La sección deja de existir. La cola no se toca: si se vuelve a prender dentro del plazo, sale. */
    fun apagar() {
        _estado.value = null
        _errorCarga.value = false
        _progreso.value = null
        _sinSenal.value = false
        _detenida.value = false
    }

    /** «Ya me lo hice» con su fecha; null lo deshace. */
    suspend fun marcarHecho(pedidoId: String, fecha: LocalDate?): Salida {
        val p = mapOf("p_token" to ValorJson.Texto(token), "p_pedido_id" to ValorJson.Texto(pedidoId), "p_fecha" to (fecha?.let { ValorJson.Texto(it.toString()) } ?: ValorJson.Nulo))
        return when (val r = cliente.llamar("mypump_estudios_hecho", p)) {
            is Resultado.Ok -> when {
                r.valor == ValorJson.Nulo -> Salida.ERROR
                r.valor["ok"] == ValorJson.Booleano(true) -> {
                    refrescar()
                    Salida.OK
                }
                else -> when (r.valor["error"]?.comoTexto) {
                    "fecha" -> Salida.FECHA
                    // Ya llegó el resultado o lo cerraron: lo que valga es lo del servidor.
                    "no_encontrado" -> {
                        refrescar()
                        Salida.OK
                    }
                    "no_habilitado" -> {
                        apagar()
                        Salida.ERROR
                    }
                    else -> Salida.ERROR
                }
            }
            is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) Salida.ERROR else Salida.SIN_SENAL
        }
    }

    // ── La hoja de subida ──

    /**
     * Aparta lugar en la hoja para hasta [quieren] archivos que se van a convertir. Cada lugar apartado se devuelve con
     * [sumarAlBorrador], se haya podido convertir o no.
     */
    fun reservar(quieren: Int): Reserva = synchronized(candadoHoja) {
        val entran = minOf(quieren, Estudios.restan(_borrador.value.size + _preparando.value, topeArchivos)).coerceAtLeast(0)
        _preparando.value += entran
        Reserva(entran, hoja)
    }

    /**
     * Termina una conversión apartada con [reservar]: [listo] (la foto ya en JPEG o el PDF copiado, en la caché propia) entra
     * en la hoja, o null si no se pudo. Los mismos bytes dos veces quedan una sola. Si la hoja ya se cerró, el archivo se
     * borra. Lee el archivo entero: fuera del hilo principal. Devuelve si quedó en la hoja.
     */
    fun sumarAlBorrador(deHoja: Int, listo: Nuevo?): Boolean {
        val huella = listo?.let { huellaDe(it.archivo) }
        synchronized(candadoHoja) {
            if (deHoja != hoja) {
                listo?.archivo?.delete()
                return false
            }
            _preparando.value = (_preparando.value - 1).coerceAtLeast(0)
            if (listo == null || huella == null) {
                listo?.archivo?.delete()
                return false
            }
            if (_borrador.value.any { it.huella == huella }) {
                listo.archivo.delete()
                return true   // el mismo archivo dos veces: ya está
            }
            _borrador.value += Elegido(listo.archivo, listo.mime, huella)
            return true
        }
    }

    /**
     * Android cerró la app con la hoja abierta (la cámara en un teléfono con poca memoria): lo que la pantalla recordaba
     * vuelve a la hoja, si sigue en el disco. Lee los archivos: fuera del hilo principal.
     */
    fun restaurarBorrador(guardados: List<Nuevo>) {
        val vivos = guardados.filter { it.archivo.isFile }.mapNotNull { n -> huellaDe(n.archivo)?.let { Elegido(n.archivo, n.mime, it) } }.distinctBy { it.huella }
        // Lo recordado va primero; si mientras tanto ya entró algo (la foto que la cámara acaba de devolver), se conserva.
        synchronized(candadoHoja) {
            if (vivos.isNotEmpty()) _borrador.value = (vivos + _borrador.value).distinctBy { it.huella }.take(topeArchivos)
        }
    }

    fun quitarDelBorrador(e: Elegido) {
        synchronized(candadoHoja) { _borrador.value -= e }
        e.archivo.delete()
    }

    /** Se cerró la hoja sin enviar: no queda nada. */
    fun descartarBorrador() {
        val viejos = synchronized(candadoHoja) {
            hoja++
            _preparando.value = 0
            _borrador.value.also { _borrador.value = emptyList() }
        }
        viejos.forEach { it.archivo.delete() }
    }

    /** «Enviar» lo de la hoja. Si no se pudo guardar en el teléfono, lo elegido queda en la hoja. */
    fun enviarBorrador(pedidoId: String?): Boolean = synchronized(candadoHoja) {
        if (_preparando.value > 0 || !encolar(_borrador.value.map { Nuevo(it.archivo, it.mime) }, pedidoId)) return false
        hoja++
        _borrador.value = emptyList()
        true
    }

    private fun huellaDe(f: File): String? = try {
        val md = MessageDigest.getInstance("SHA-256")
        f.inputStream().use { e ->
            val bloque = ByteArray(64 * 1024)
            while (true) {
                val n = e.read(bloque)
                if (n < 0) break
                md.update(bloque, 0, n)
            }
        }
        md.digest().joinToString("") { "%02x".format(it) }
    } catch (_: Exception) {
        null
    }

    // ── Encolar ──

    /**
     * Los archivos (fotos ya en JPEG, PDF tal cual) pasan a la carpeta propia, cada uno con su id, y el envío queda en la
     * cola. O sale todo o no sale nada: si no se pudo guardar, cada archivo de [nuevos] vuelve a donde estaba. Después hay
     * que drenar. Devuelve si quedó guardado.
     */
    fun encolar(nuevos: List<Nuevo>, pedidoId: String?): Boolean {
        val d = disco ?: return false
        val carpeta = carpetaArchivos ?: return false
        if (nuevos.isEmpty() || _estado.value == null) return false
        val movidos = ArrayList<Pair<ArchivoEstudios, File>>()
        var bien = true
        for (n in nuevos) {
            val a = ArchivoEstudios(UUID.randomUUID().toString().lowercase(), n.mime)
            if (!mover(n.archivo, File(carpeta, a.nombre))) {
                bien = false
                break
            }
            movidos += a to n.archivo
        }
        val envio = EnvioEstudios(UUID.randomUUID().toString().lowercase(), pedidoId, movidos.map { it.first }, creadoEn = ahora())
        if (bien) {
            _cola.update { it + envio }
            bien = guardarCola(d)
            if (!bien) _cola.update { l -> l.filter { it.id != envio.id } }
        }
        if (!bien) {
            for ((a, original) in movidos) mover(File(carpeta, a.nombre), original)
            return false
        }
        _aviso.value = null
        _sinSenal.value = false
        _detenida.value = false
        _progreso.value = Progreso(1, envio.archivos.size)
        return true
    }

    /** Pasa un archivo de una carpeta a otra (de la hoja a la cola, o de la carpeta de otro link a esta). Devuelve si llegó entero. */
    private fun mover(desde: File, hasta: File): Boolean = try {
        hasta.parentFile?.mkdirs()
        if (!desde.renameTo(hasta)) {
            desde.inputStream().use { e -> hasta.outputStream().use { s -> e.copyTo(s); s.fd.sync() } }
            desde.delete()
        }
        if (hasta.length() > 0) {
            true
        } else {
            hasta.delete()
            false
        }
    } catch (_: Exception) {
        hasta.delete()
        false
    }

    fun limpiarAviso() {
        _aviso.value = null
    }

    /**
     * Cerrar sesión: de esta cuenta no queda nada médico en el teléfono, ni lo que esperaba salir ni lo elegido. Una
     * pasada en curso se corta en el próximo paso.
     */
    fun borrarTodo() {
        apagar()
        _palanca.value = false
        descartarBorrador()
        _cola.value = emptyList()
        vueltas.clear()
        disco?.let(::guardarCola)
        carpetaArchivos?.deleteRecursively()
        _aviso.value = null
    }

    // ── Cola ──

    private enum class Fin { LISTO, SEGUIR, RED, MAS_TARDE, PARAR }
    private enum class Subida { OK, PERDIDO, DESCARTAR, REINTENTAR, TOKEN, REABRIR, CERRADO, RED }

    /**
     * Una pasada a la vez, un envío detrás de otro. Red: corta y espera a que vuelva. 5xx o 429: espera y reintenta. Con
     * la sección apagada (la palanca, el link, la cuenta) no sale nada, tampoco el reintento que estaba programado.
     */
    suspend fun drenar() {
        if (_estado.value == null || _cola.value.isEmpty() || !drenando.tryLock()) return
        var huboEnviado = false
        try {
            _sinSenal.value = false
            _detenida.value = false
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
            // Quedó algo, no es la red y nadie lo va a retomar solo: se dice, con «Probar de nuevo».
            _detenida.value = _estado.value != null && _cola.value.isNotEmpty() && !_sinSenal.value && !reintentoProgramado.get()
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
                                apagar()   // se conserva: si lo vuelven a habilitar, sale
                                Fin.PARAR
                            }
                            "id_repetido" -> {
                                // El id ya es de otro: se prueba una vez con uno nuevo.
                                if (regenerados.add(env.id)) {
                                    val nuevo = UUID.randomUUID().toString().lowercase()
                                    regenerados.add(nuevo)
                                    actualizar(env, env.copy(id = nuevo))
                                } else {
                                    descartar(env, Aviso.ERROR)
                                }
                                Fin.SEGUIR
                            }
                            // Un error que la app no conoce no deja el envío trabado para siempre.
                            else -> {
                                descartar(env, Aviso.ERROR)
                                Fin.SEGUIR
                            }
                        }
                    }
                }
                is Resultado.Falla -> return alFallar(r.error, env)
            }
        }

        var seguidas = 0
        while (true) {
            // Se apagó la sección o se cerró la sesión en medio de la pasada: no sale ni un archivo más.
            if (_estado.value == null) return Fin.PARAR
            val a = env.archivos.firstOrNull { !it.subido } ?: break
            _progreso.value = Progreso(env.archivos.count { it.subido } + 1, env.archivos.size)
            when (subir(env, a)) {
                Subida.OK -> {
                    env = actualizar(env, env.copy(archivos = env.archivos.map { if (it.id == a.id) it.copy(subido = true) else it }))
                    seguidas = 0
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
                // 401 (link regenerado) o 403 (la cuenta ya no tiene la función): no es el archivo. La cola queda entera
                // y lo que valga lo dice el próximo `get`.
                Subida.TOKEN -> return Fin.PARAR
                // 404: el servidor no conoce el envío. Se abre de nuevo y se sube todo otra vez (lo ya subido contesta `ya`).
                Subida.REABRIR -> {
                    if (!otraVuelta(env.id)) return Fin.MAS_TARDE
                    actualizar(env, env.copy(creado = false, archivos = env.archivos.map { it.copy(subido = false) }))
                    return Fin.SEGUIR
                }
                // 409: el envío ya no recibe porque ya quedó enviado. `enviar` lo confirma (`ya`).
                Subida.CERRADO -> return cerrar(env, yaCerrado = true)
                Subida.RED -> return Fin.RED
            }
        }
        if (_cola.value.none { it.id == env.id }) return Fin.PARAR   // lo borraron en medio (se cerró la sesión)
        if (env.archivos.isEmpty()) {
            // No quedó ninguno: el envío se descarta en silencio y se le dice que pruebe con otro archivo.
            descartar(env, Aviso.RECHAZADO)
            return Fin.SEGUIR
        }
        return cerrar(env)
    }

    /** `enviar`. Con [yaCerrado] (la subida contestó 409) solo se confirma: si el servidor no dice que sí, el envío no gira. */
    private suspend fun cerrar(env: EnvioEstudios, yaCerrado: Boolean = false): Fin {
        val p = mapOf("p_token" to texto(token), "p_id" to texto(env.id), "p_archivos" to ValorJson.Numero(env.archivos.size.toDouble()))
        return when (val r = cliente.llamar("mypump_estudios_enviar", p)) {
            is Resultado.Ok -> {
                val j = r.valor
                when {
                    j == ValorJson.Nulo -> Fin.PARAR
                    j["ok"] == ValorJson.Booleano(true) -> terminar(env)
                    yaCerrado -> {
                        descartar(env, Aviso.ERROR)
                        Fin.SEGUIR
                    }
                    else -> when (j["error"]?.comoTexto) {
                        // En el servidor hay menos que acá: se suben de nuevo (los que ya están contestan `ya`). Agotadas
                        // las vueltas no se toca nada: queda para una pasada posterior.
                        "faltan_archivos", "sin_archivos" -> {
                            if (!otraVuelta(env.id)) return Fin.MAS_TARDE
                            actualizar(env, env.copy(archivos = env.archivos.map { it.copy(subido = false) }))
                            Fin.SEGUIR
                        }
                        "no_encontrado" -> {
                            if (otraVuelta(env.id)) {
                                actualizar(env, env.copy(creado = false, archivos = env.archivos.map { it.copy(subido = false) }))
                            } else {
                                descartar(env, Aviso.ERROR)
                            }
                            Fin.SEGUIR
                        }
                        "no_habilitado" -> {
                            apagar()
                            Fin.PARAR
                        }
                        else -> {
                            descartar(env, Aviso.ERROR)
                            Fin.SEGUIR
                        }
                    }
                }
            }
            is Resultado.Falla -> alFallar(r.error, env)
        }
    }

    /**
     * Cuenta las vueltas de un envío (subir todo de nuevo): false cuando ya dio las que puede en esta pasada, y la cuenta
     * vuelve a empezar para la próxima. Las pasadas solas tienen su propio tope ([MAX_REINTENTOS_DE_FONDO]).
     */
    private fun otraVuelta(id: String): Boolean {
        val n = vueltas[id] ?: 0
        if (n >= MAX_VUELTAS) {
            vueltas.remove(id)
            return false
        }
        vueltas[id] = n + 1
        return true
    }

    private fun alFallar(e: ErrorRpc, env: EnvioEstudios): Fin {
        // Sin la función o sin permiso (se revirtió el servidor, cambió la clave): la sección se apaga y la cola se conserva.
        if (e.funcionInexistente || e.status in listOf(401, 403, 404)) {
            apagar()
            return Fin.PARAR
        }
        return when (e.clase) {
            ErrorRpc.Clase.RED -> Fin.RED
            ErrorRpc.Clase.TRANSITORIO -> Fin.MAS_TARDE
            // El servidor dijo que no a este envío (un parámetro que no acepta): no se reintenta ni traba a los demás.
            ErrorRpc.Clase.PERMANENTE -> {
                descartar(env, Aviso.ERROR)
                Fin.SEGUIR
            }
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
        // Lo que no habla del archivo sino del link o del envío no gasta el archivo.
        when (r.status) {
            401, 403 -> return Subida.TOKEN
            404 -> return Subida.REABRIR
            409 -> return Subida.CERRADO
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
        // Las pasadas solas se cuentan por envío: recién al terminar uno se vuelve a empezar (si no, un servidor que
        // siempre dice «faltan archivos» haría subir todo de nuevo cada minuto, sin tope).
        reintentosDeFondo = 0
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

    private fun guardarCola(d: Disco): Boolean = ColaEstudios.guardar(d, _cola.value)

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
        const val MAX_INTENTOS_SEGUIDOS = 3
        const val MAX_REINTENTOS_DE_FONDO = 5
        const val MAX_VUELTAS = 2
    }
}
