package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.DudaLlamada
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.SeguimientoAvance
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * «Tu guía» de una cuenta (`entregas_010_app`): la tarjeta de inicio, la sección y lo que el cliente escribe en ella.
 *
 * - **Lecturas.** [refrescarResumen] (`entregas_app_resumen`, solo lectura, no marca `abierto_en`) al abrir la app y al
 *   volver a primer plano: es lo que mira la tarjeta. [abrir] (`entregas_app_get`, que SÍ marca `abierto_en` la primera
 *   vez, como la web) solo cuando el cliente abre la sección, nunca en segundo plano.
 * - **Caché.** El último `get` (`guia.json`) y el último resumen (`guia-resumen.json`) en la carpeta de la cuenta, como la
 *   copia offline de info, rutina y dieta: sin red la lista se ve igual.
 * - **Escrituras.** Todo por la cola de la app ([Outbox]), así no se pierde sin red. El avance de un video se deduplica por
 *   video (gana el último, fusionado con el pendiente: el mayor de los segundos y visto si alguno lo tenía); las dudas NO
 *   se deduplican (dos iguales son dos dudas). `false` del servidor en una duda (tope o token) = «No se pudo guardar», y
 *   el texto vuelve al campo.
 * - **Sin guía.** `{"ok": false}` (sin página aprobada, token inválido o revocado) borra la caché: la sección y la tarjeta
 *   desaparecen sin mensaje.
 *
 * Como [ModeloApp], se usa desde el hilo principal; lo que avisa la cola llega desde su hilo y se pasa a [alcance].
 */
class ModeloGuia(
    private val cliente: ClienteRpc,
    private val token: String,
    private val outbox: Outbox?,
    private val disco: Disco?,
    private val alcance: CoroutineScope,
    /**
     * «Ver demo» (revisión de Apple): la guía de muestra empaquetada, sin cuenta. No llama al servidor; lo visto y las
     * dudas quedan en memoria, como las demás escrituras de la demo. Ver [demo].
     */
    private val esDemo: Boolean = false,
) {
    enum class Estado {
        /** Nunca se abrió en este teléfono y todavía no se pidió. */
        SIN_DATOS,
        CARGANDO,
        LISTA,

        /** `ok: false`: la sección no existe para esta cuenta. */
        NO_HAY,

        /** Sin red y sin caché. */
        SIN_RED,
    }

    /** Una duda que salió del teléfono y todavía no volvió la respuesta. [video] null = para la videollamada. */
    data class DudaPendiente(val opId: String, val video: String?, val texto: String)

    /** Lo que volvió de una duda, para que la pantalla avise (y la consuma con [avisoVisto]). */
    sealed interface AvisoDuda {
        val video: String?

        data class Guardada(override val video: String?) : AvisoDuda

        /** El texto vuelve al campo («No se pudo guardar»). */
        data class Rechazada(override val video: String?, val texto: String) : AvisoDuda
    }

    private val _guia = MutableStateFlow<Guia?>(null)

    /** La guía con lo del teléfono encima (lo visto que todavía no salió). */
    val guia: StateFlow<Guia?> = _guia.asStateFlow()

    private val _resumen = MutableStateFlow<ResumenGuia?>(null)

    /** Lo que muestra la tarjeta de inicio. null: no hay tarjeta. */
    val resumen: StateFlow<ResumenGuia?> = _resumen.asStateFlow()

    private val _estado = MutableStateFlow(Estado.SIN_DATOS)
    val estado: StateFlow<Estado> = _estado.asStateFlow()

    /** Lo que se ve es la caché: el último `get` no llegó. */
    private val _desdeCache = MutableStateFlow(false)
    val desdeCache: StateFlow<Boolean> = _desdeCache.asStateFlow()

    private val _pendientes = MutableStateFlow<List<DudaPendiente>>(emptyList())
    val pendientes: StateFlow<List<DudaPendiente>> = _pendientes.asStateFlow()

    private val _avisos = MutableStateFlow<List<AvisoDuda>>(emptyList())
    val avisos: StateFlow<List<AvisoDuda>> = _avisos.asStateFlow()

    private val _ocultaAMano = MutableStateFlow(false)

    /**
     * El cliente tocó «Quitar de Entreno»: la tarjeta sale antes de tiempo y la guía queda en la fila de Mis datos. Solo en
     * este teléfono y por cuenta (`guia-oculta.json` en la carpeta de la cuenta). Ver `ReglasGuia.lugar`.
     */
    val ocultaAMano: StateFlow<Boolean> = _ocultaAMano.asStateFlow()

    /** Se tocó antes de que terminara de leerse el disco: lo leído no lo pisa. */
    private var ocultaTocada = false

    private val _bienvenidaVista = MutableStateFlow<Boolean?>(null)

    /**
     * La bienvenida de la primera vez ya salió en este teléfono para esta cuenta (`guia-bienvenida.json` en su carpeta).
     * null mientras no se leyó el disco: hasta saberlo no se muestra (así no sale dos veces). Ver `ReglasGuia.mostrarBienvenida`.
     */
    val bienvenidaVista: StateFlow<Boolean?> = _bienvenidaVista.asStateFlow()

    private var abriendo = false

    /** El disco, fuera del hilo principal y de a una operación por vez, en el orden en que se pidieron. */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private val serieDisco = Dispatchers.IO.limitedParallelism(1)

    /** La caché se lee al armar el modelo, en [serieDisco]; [abrir] y [refrescarResumen] la esperan. */
    private val lecturaInicial: Job = alcance.launch {
        val (g, r) = withContext(serieDisco) { Guia.desde(disco?.leer(ARCHIVO_GUIA)) to ResumenGuia.desde(disco?.leer(ARCHIVO_RESUMEN)) }
        val oculta = withContext(serieDisco) { disco?.leer(ARCHIVO_OCULTA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true) }
        if (!ocultaTocada) _ocultaAMano.value = oculta
        val bienvenida = withContext(serieDisco) { disco?.leer(ARCHIVO_BIENVENIDA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true) }
        if (_bienvenidaVista.value == null) _bienvenidaVista.value = bienvenida
        if (_estado.value == Estado.SIN_DATOS && _guia.value == null && g != null) {
            _guia.value = g
            _estado.value = Estado.LISTA
            _desdeCache.value = true
        }
        if (_resumen.value == null && _estado.value != Estado.NO_HAY) _resumen.value = r ?: g?.let(ResumenGuia::de)
        // Las dudas que quedaron en la cola (la app se cerró antes de que salieran) se ven como pendientes.
        outbox?.let { cola ->
            val ops = cola.operaciones()
            _pendientes.value = ops.mapNotNull(::pendienteDe)
            val conAvance = aplicarPendientes(_guia.value, ops)
            if (conAvance != _guia.value) _guia.value = conAvance
        }
    }

    private fun alDisco(f: Disco.() -> Unit) {
        val d = disco ?: return
        alcance.launch(serieDisco) { d.f() }
    }

    /** Para las pruebas: la caché ya se leyó y lo pedido al disco ya se escribió. */
    suspend fun alDia() {
        lecturaInicial.join()
        alcance.launch(serieDisco) {}.join()
    }

    private val parametros: Map<String, ValorJson> get() = mapOf("p_token" to ValorJson.Texto(token))

    // ── Lecturas ──

    /**
     * La tarjeta de inicio: `entregas_app_resumen`. Sin red queda lo de la caché; `ok: false` borra todo (la tarjeta y la
     * sección desaparecen). Si la guía está en memoria y tiene lo visto en el teléfono que todavía no salió, se respeta.
     */
    suspend fun refrescarResumen() {
        lecturaInicial.join()
        if (esDemo) return
        val r = cliente.llamar("entregas_app_resumen", parametros)
        // La función no existe (404, PGRST202): para la app no hay guía (la tarjeta no queda colgada de la caché).
        if (r is Resultado.Falla && (r.error.status == 404 || r.error.codigo == "PGRST202")) {
            olvidar()
            return
        }
        val valor = (r as? Resultado.Ok)?.valor ?: return
        // `ok: true` con total 0 (Mati sacó todos los videos): tampoco hay tarjeta.
        if (esNoHay(valor) || (valor["ok"] == ValorJson.Booleano(true) && valor["total"]?.comoNumero?.let { it <= 0.0 } == true)) {
            olvidar()
            return
        }
        val nuevo = ResumenGuia.desde(valor) ?: return
        val local = _guia.value?.let(ResumenGuia::de)
        // Lo visto en el teléfono gana, pero la fecha y `mostrar_tarjeta` son siempre las del servidor.
        val final = if (local != null && local.total == nuevo.total && local.vistos > nuevo.vistos) {
            local.copy(fechaEntrega = nuevo.fechaEntrega, mostrarTarjeta = nuevo.mostrarTarjeta)
        } else {
            nuevo
        }
        _resumen.value = final
        alDisco { guardar(ARCHIVO_RESUMEN, final.aValor()) }
    }

    /**
     * El cliente abrió la sección: `entregas_app_get` (marca `abierto_en` la primera vez). Sin red queda la caché
     * ([desdeCache]); sin caché, [Estado.SIN_RED].
     */
    suspend fun abrir() {
        if (abriendo) return
        abriendo = true
        try {
            lecturaInicial.join()
            if (esDemo) {
                _estado.value = if (_guia.value != null) Estado.LISTA else Estado.NO_HAY
                return
            }
            if (_guia.value == null) _estado.value = Estado.CARGANDO
            when (val r = cliente.llamar("entregas_app_get", parametros)) {
                is Resultado.Falla -> {
                    _desdeCache.value = _guia.value != null
                    _estado.value = if (_guia.value != null) Estado.LISTA else Estado.SIN_RED
                }
                is Resultado.Ok -> {
                    if (esNoHay(r.valor)) {
                        olvidar()
                        return
                    }
                    val g = Guia.desde(r.valor)
                    if (g == null) {
                        // Una forma que no se entiende no es «no hay guía»: queda lo que había.
                        _desdeCache.value = _guia.value != null
                        _estado.value = if (_guia.value != null) Estado.LISTA else Estado.SIN_RED
                        return
                    }
                    val ops = outbox?.operaciones().orEmpty()
                    _pendientes.value = ops.mapNotNull(::pendienteDe)
                    publicar(aplicarPendientes(g, ops) ?: g)
                    _desdeCache.value = false
                    _estado.value = Estado.LISTA
                }
            }
        } finally {
            abriendo = false
        }
    }

    private fun esNoHay(v: ValorJson): Boolean = v == ValorJson.Booleano(false) || v == ValorJson.Nulo || v["ok"] == ValorJson.Booleano(false)

    /** La sección deja de existir: sin caché y sin tarjeta. */
    private fun olvidar() {
        _guia.value = null
        _resumen.value = null
        _desdeCache.value = false
        _estado.value = Estado.NO_HAY
        alDisco {
            borrar(ARCHIVO_GUIA)
            borrar(ARCHIVO_RESUMEN)
        }
    }

    private fun publicar(g: Guia) {
        _guia.value = g
        // Dónde va la tarjeta sale del resumen (`fecha_entrega` y `mostrar_tarjeta`), no del get: calculado desde la guía
        // quedan los del último resumen; sin resumen todavía, la fecha de la guía.
        val previo = _resumen.value
        val resumen = ResumenGuia.de(g)?.let { r ->
            if (previo != null) r.copy(fechaEntrega = previo.fechaEntrega, mostrarTarjeta = previo.mostrarTarjeta) else r
        }
        resumen?.let { _resumen.value = it }
        alDisco {
            guardar(ARCHIVO_GUIA, g.aValor())
            resumen?.let { guardar(ARCHIVO_RESUMEN, it.aValor()) }
        }
    }

    // ── Escrituras ──

    /** «Quitar de Entreno» (true) o «Volver a mostrar en Entreno» (false). Queda en el teléfono; no llama al servidor. */
    fun ocultarDeEntreno(oculta: Boolean) {
        ocultaTocada = true
        _ocultaAMano.value = oculta
        alDisco { if (oculta) guardar(ARCHIVO_OCULTA, ValorJson.Booleano(true)) else borrar(ARCHIVO_OCULTA) }
    }

    /** La bienvenida ya se mostró: no vuelve a salir para esta cuenta en este teléfono. No llama al servidor. */
    fun marcarBienvenidaVista() {
        if (_bienvenidaVista.value == true) return
        _bienvenidaVista.value = true
        alDisco { guardar(ARCHIVO_BIENVENIDA, ValorJson.Booleano(true)) }
    }

    /** Lo que decidió [SeguimientoAvance]: queda en el teléfono y sale por la cola (deduplicado por video). */
    suspend fun guardarAvance(g: SeguimientoAvance.Guardado) {
        val clave = claveAvance(g.video)
        val previo = outbox?.pendientesPorClave()?.get(clave)?.let(::avanceDe)
        val final = SeguimientoAvance.fusionar(previo, g)
        _guia.value?.let { actual -> publicar(conAvance(actual, final)) }
        outbox?.encolar(
            KIND_AVANCE,
            ValorJson.objeto(
                "video" to ValorJson.Texto(final.video),
                "segundos" to ValorJson.Numero(final.segundos.toDouble()),
                "visto" to ValorJson.Booleano(final.visto),
            ),
            clave,
        )
    }

    /** Una duda de un video. Devuelve false si el texto no es válido (vacío o más de 1000) o no hay cola. */
    suspend fun enviarDudaVideo(video: String, texto: String): Boolean {
        val t = ReglasGuia.dudaValida(texto) ?: return false
        if (esDemo) return dudaEnDemo(video, t)
        val cola = outbox ?: return false
        val op = cola.encolar(KIND_DUDA, ValorJson.objeto("video" to ValorJson.Texto(video), "texto" to ValorJson.Texto(t), "id" to ValorJson.Texto(nuevoId())), null)
        agregarPendiente(DudaPendiente(op.id, video, t))
        return true
    }

    /** Una duda para la videollamada (hasta 30, compartidas con la web). */
    suspend fun enviarDudaLlamada(texto: String): Boolean {
        val t = ReglasGuia.dudaValida(texto) ?: return false
        if (!puedeSumarDudaLlamada()) return false
        if (esDemo) return dudaEnDemo(null, t)
        val cola = outbox ?: return false
        val op = cola.encolar(KIND_DUDA_LLAMADA, ValorJson.objeto("texto" to ValorJson.Texto(t), "id" to ValorJson.Texto(nuevoId())), null)
        agregarPendiente(DudaPendiente(op.id, null, t))
        return true
    }

    /** Todavía hay lugar (las guardadas más las que están saliendo no llegan a 30). */
    fun puedeSumarDudaLlamada(): Boolean =
        (_guia.value?.dudasLlamada?.size ?: 0) + _pendientes.value.count { it.video == null } < ReglasGuia.TOPE_DUDAS_LLAMADA

    /** En la demo la duda no sale del teléfono: se suma a lo que se ve y se avisa «Listo», como si se hubiera guardado. */
    private fun dudaEnDemo(video: String?, t: String): Boolean {
        val g = _guia.value ?: return false
        publicar(conDuda(g, DudaPendiente(nuevoId(), video, t)))
        _avisos.update { it + AvisoDuda.Guardada(video) }
        return true
    }

    private fun agregarPendiente(p: DudaPendiente) {
        // La respuesta pudo haber vuelto antes que esto (la cola manda enseguida): ahí ya no está pendiente.
        if (p.opId in resueltas) {
            resueltas -= p.opId
            return
        }
        _pendientes.update { it + p }
    }

    private val resueltas = HashSet<String>()

    fun avisoVisto(a: AvisoDuda) {
        _avisos.update { it - a }
    }

    /** Lo que el servidor guardó (lo pasa [ModeloApp] desde la cola). */
    fun alGuardar(ops: List<OpGuardada>) {
        val nuestras = ops.filter { it.op.kind == KIND_DUDA || it.op.kind == KIND_DUDA_LLAMADA }
        if (nuestras.isEmpty()) return
        alcance.launch {
            for (g in nuestras) {
                val ok = g.respuesta == ValorJson.Booleano(true)
                resolver(g.op, ok)
            }
        }
    }

    /** Lo que la cola abandonó tras 8 intentos (va a fallidos): la duda vuelve al campo. */
    fun alAbandonar(ops: List<Operacion>) {
        val nuestras = ops.filter { it.kind == KIND_DUDA || it.kind == KIND_DUDA_LLAMADA }
        if (nuestras.isEmpty()) return
        alcance.launch { for (op in nuestras) resolver(op, false) }
    }

    private fun resolver(op: Operacion, ok: Boolean) {
        val p = pendienteDe(op) ?: return
        if (_pendientes.value.none { it.opId == op.id }) resueltas += op.id
        _pendientes.update { l -> l.filterNot { it.opId == op.id } }
        if (ok) {
            _guia.value?.let { g -> publicar(conDuda(g, p)) }
            _avisos.update { it + AvisoDuda.Guardada(p.video) }
        } else {
            _avisos.update { it + AvisoDuda.Rechazada(p.video, p.texto) }
        }
    }

    companion object {
        const val KIND_AVANCE = "guia_avance"
        /**
         * El `p_id` de una duda (`entregas_013`): un uuid v4 al azar, armado una sola vez al entrar a la cola y guardado en
         * el payload (`id`), así cada reintento de la cola manda el mismo y el servidor no la suma dos veces.
         */
        fun nuevoId(): String = java.util.UUID.randomUUID().toString()

        const val KIND_DUDA = "guia_duda"
        const val KIND_DUDA_LLAMADA = "guia_duda_llamada"

        internal const val ARCHIVO_GUIA = "guia.json"
        internal const val ARCHIVO_RESUMEN = "guia-resumen.json"
        internal const val ARCHIVO_OCULTA = "guia-oculta.json"
        internal const val ARCHIVO_BIENVENIDA = "guia-bienvenida.json"

        /**
         * La guía de «Ver demo»: [guia] es la respuesta de muestra con la forma del get (`apps/shared/demo/guia.json`). Sin
         * token, cola ni disco: [refrescarResumen] y [abrir] no llaman al servidor.
         */
        fun demo(cliente: ClienteRpc, guia: Guia, alcance: CoroutineScope): ModeloGuia =
            ModeloGuia(cliente, token = "", outbox = null, disco = null, alcance = alcance, esDemo = true).also { m ->
                m._guia.value = guia
                m._resumen.value = ResumenGuia.de(guia)
                m._estado.value = Estado.LISTA
            }

        fun claveAvance(video: String): String = "guia_avance_$video"

        internal fun avanceDe(op: Operacion): SeguimientoAvance.Guardado? {
            if (op.kind != KIND_AVANCE) return null
            val v = op.payload["video"]?.comoTexto ?: return null
            return SeguimientoAvance.Guardado(
                v,
                op.payload["segundos"]?.comoNumero?.toInt() ?: 0,
                (op.payload["visto"] as? ValorJson.Booleano)?.valor == true,
            )
        }

        internal fun pendienteDe(op: Operacion): DudaPendiente? {
            val t = op.payload["texto"]?.comoTexto ?: return null
            return when (op.kind) {
                KIND_DUDA -> op.payload["video"]?.comoTexto?.let { DudaPendiente(op.id, it, t) }
                KIND_DUDA_LLAMADA -> DudaPendiente(op.id, null, t)
                else -> null
            }
        }

        /** Lo visto y los segundos del teléfono encima de lo del servidor (el servidor también se queda con el mayor). */
        internal fun conAvance(g: Guia, a: SeguimientoAvance.Guardado): Guia = g.copy(
            clips = g.clips.map { c -> if (c.id == a.video) c.copy(visto = c.visto || a.visto, segundos = maxOf(c.segundos, a.segundos)) else c },
        )

        internal fun aplicarPendientes(g: Guia?, ops: List<Operacion>): Guia? {
            var r = g ?: return null
            for (op in ops) avanceDe(op)?.let { r = conAvance(r, it) }
            return r
        }

        /** La duda ya guardada, sumada como la suma el servidor (con un salto de línea). */
        internal fun conDuda(g: Guia, p: DudaPendiente): Guia {
            if (p.video == null) return g.copy(dudasLlamada = g.dudasLlamada + DudaLlamada(p.texto, null))
            return g.copy(clips = g.clips.map { c -> if (c.id == p.video) sumarDuda(c, p.texto) else c })
        }

        private fun sumarDuda(c: ClipGuia, t: String): ClipGuia {
            // Dos dudas iguales son dos dudas (no se deduplican). Si un `get` llegó entre que se guardó y que volvió la
            // respuesta, se vería repetida hasta el próximo `get`: es solo lo que se muestra, el servidor la tiene una vez.
            val antes = c.duda
            return c.copy(duda = if (antes.isNullOrEmpty()) t else "$antes\n$t")
        }
    }
}
