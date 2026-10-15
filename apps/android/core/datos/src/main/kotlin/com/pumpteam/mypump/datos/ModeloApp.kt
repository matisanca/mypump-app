package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.ClienteInfo
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.DietaActiva
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.PreferenciasCliente
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AlimentoEfectivo
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.NormalizarDieta
import com.pumpteam.mypump.reglas.SwapLocal
import com.pumpteam.mypump.reglas.SwapsDeComida
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * El estado de la app del cliente: quién es, su plan y lo que fue haciendo, con la cola de escrituras detrás. Hace lo
 * mismo que `init()` de cliente.html (8667-8918) y que ModeloApp.swift, en este orden: info → rutina y dieta → copia
 * offline → hidratar → drenar la cola.
 *
 * Como el `@MainActor` de iOS: se usa desde UN solo hilo (el principal, con el `viewModelScope` del ViewModel como
 * [alcance]). Dos llamadas pueden intercalarse en las esperas de red —un link tocado mientras carga la cuenta guardada—
 * y por eso cada carga mira, al volver de cada espera, si su token sigue siendo el vigente. Lo que mira la pantalla son
 * [StateFlow]s; la red y el JSON corren fuera del hilo principal ([ClienteRpc]).
 */
class ModeloApp(
    val cliente: ClienteRpc = ClienteRpc(),
    private val almacen: AlmacenToken,
    /** Donde van los archivos de cada cuenta (en la app, `filesDir`). */
    private val raizDisco: File,
    /** `UserDefaults` de iOS: lo poco que se recuerda fuera de la cuenta. */
    val preferencias: Preferencias,
    private val alcance: CoroutineScope,
) {
    enum class Fase {
        /** "Bienvenido a MyPump": pegá tu link o mirá la demo. */
        SIN_TOKEN,
        CARGANDO,
        LISTO,

        /** "Este link ya no sirve". */
        TOKEN_INVALIDO,

        /** Sin red y sin copia offline. */
        SIN_SERVICIO,
    }

    /** Lo que puede faltar de una carga por un corte (y salir de la copia guardada). */
    enum class Parte { RUTINA, DIETA }

    var token: String? = almacen.leer()
        private set
    private var disco: Disco? = null
    var outbox: Outbox? = null
        private set

    /** El día local de la última carga completa: si al volver a la app cambió, se recarga lo que es "de hoy". */
    private var diaCargado: String? = null

    private val _fase = MutableStateFlow(if (token == null) Fase.SIN_TOKEN else Fase.CARGANDO)
    val fase: StateFlow<Fase> = _fase.asStateFlow()

    private val _info = MutableStateFlow<ClienteInfo?>(null)
    val info: StateFlow<ClienteInfo?> = _info.asStateFlow()

    private val _rutina = MutableStateFlow<RutinaActiva?>(null)
    val rutina: StateFlow<RutinaActiva?> = _rutina.asStateFlow()

    private val _dieta = MutableStateFlow<DietaActiva?>(null)
    val dieta: StateFlow<DietaActiva?> = _dieta.asStateFlow()

    /** Lo cargado vino de la copia offline (banner "sin conexión"). */
    private val _desdeCache = MutableStateFlow(false)
    val desdeCache: StateFlow<Boolean> = _desdeCache.asStateFlow()

    /** Demo ("Ver demo", la que mira la revisión de la tienda): datos de la web empaquetados, sin red ni token, nada se escribe. */
    private val _esDemo = MutableStateFlow(false)
    val esDemo: StateFlow<Boolean> = _esDemo.asStateFlow()

    /** Lo que no llegó en la última carga por un corte (se muestra la copia guardada de eso, si había). */
    private val _sinRedEn = MutableStateFlow<Set<Parte>>(emptySet())
    val sinRedEn: StateFlow<Set<Parte>> = _sinRedEn.asStateFlow()

    /**
     * Cuántas cargas terminaron con red (info, rutina y dieta del servidor, sin la copia guardada). Lo mira la migración
     * del almacenamiento viejo para esperar "otra carga con red": `cargar` no pasa por [Fase.CARGANDO] si la cuenta ya
     * estaba lista, así que mirar la fase no alcanza.
     */
    private val _cargasConRed = MutableStateFlow(0)
    val cargasConRed: StateFlow<Int> = _cargasConRed.asStateFlow()

    /** Por qué no se pudo cargar (para decir "Sin conexión" o "Servicio fuera de línea"). */
    private val _ultimaFalla = MutableStateFlow<ErrorRpc.Clase?>(null)
    val ultimaFalla: StateFlow<ErrorRpc.Clase?> = _ultimaFalla.asStateFlow()

    /** Lo que le falta a la dieta publicada (`normalizarDieta`): para el aviso "a tu plan le falta información". */
    private val _problemasDieta = MutableStateFlow<List<String>>(emptyList())
    val problemasDieta: StateFlow<List<String>> = _problemasDieta.asStateFlow()

    private val _estadoGuardado = MutableStateFlow(EstadoGuardado.QUIETO)
    val estadoGuardado: StateFlow<EstadoGuardado> = _estadoGuardado.asStateFlow()

    // Dieta
    private val _excluir = MutableStateFlow<List<String>>(emptyList())
    val excluir: StateFlow<List<String>> = _excluir.asStateFlow()

    private val _alimentosPropios = MutableStateFlow<List<AlimentoPropio>>(emptyList())
    val alimentosPropios: StateFlow<List<AlimentoPropio>> = _alimentosPropios.asStateFlow()

    /** La palanca remota (G2). Se lee en cada carga; sin la tabla o sin red queda la de fábrica (todo prendido). */
    private val _palanca = MutableStateFlow(PalancaRemota.deFabrica)
    val palanca: StateFlow<PalancaRemota> = _palanca.asStateFlow()

    private val _swaps = MutableStateFlow<Map<String, SwapLocal>>(emptyMap())
    val swaps: StateFlow<Map<String, SwapLocal>> = _swaps.asStateFlow()

    /** Comidas libres (fuera del plan) del día local. */
    private val _comidasLibres = MutableStateFlow<List<ComidaLibre>>(emptyList())
    val comidasLibres: StateFlow<List<ComidaLibre>> = _comidasLibres.asStateFlow()

    /** El chat con Mati (no existe sin cuenta; en la demo es el hilo vacío, sin red). */
    private val _chat = MutableStateFlow<ModeloChat?>(null)
    val chat: StateFlow<ModeloChat?> = _chat.asStateFlow()

    /** Revisión y Mi Día (no existen sin cuenta; en la demo, Mi Día sembrado como la web y sin red). */
    private val _revision = MutableStateFlow<ModeloRevision?>(null)
    val revision: StateFlow<ModeloRevision?> = _revision.asStateFlow()

    /** Fotos de progreso, con su cola propia en disco. */
    private val _fotos = MutableStateFlow<ModeloFotos?>(null)
    val fotos: StateFlow<ModeloFotos?> = _fotos.asStateFlow()

    /** Progreso: se carga al abrir la pestaña (como la web). */
    private val _progreso = MutableStateFlow<ModeloProgreso?>(null)
    val progreso: StateFlow<ModeloProgreso?> = _progreso.asStateFlow()

    /** El motor de Entreno de la rutina activa (también en la demo, donde no escribe nada). */
    private val _entreno = MutableStateFlow<ModeloEntreno?>(null)
    val entreno: StateFlow<ModeloEntreno?> = _entreno.asStateFlow()

    /**
     * Salud, recuperación y Mi reloj (no existen en la demo ni sin cuenta). Se crea con la cuenta, arranca al terminar
     * [cargar] y sincroniza en [alVolverAPrimerPlano]; la fuente del sistema la pone `:app` en
     * [ModeloSalud.fuenteDelSistema].
     */
    private val _salud = MutableStateFlow<ModeloSalud?>(null)
    val salud: StateFlow<ModeloSalud?> = _salud.asStateFlow()

    /** El catálogo de ejercicios que llegó del servidor (o el guardado de la última vez). */
    private var catalogo: CatalogoEjercicios? = null

    /** El tipo de día elegido (entreno/descanso) en dietas con `tipos_dia`. Es global en la web (`mypump_tipo_dia`). */
    private val _tipoDia = MutableStateFlow(preferencias.leer(CLAVE_TIPO_DIA))
    val tipoDiaFlow: StateFlow<String?> = _tipoDia.asStateFlow()
    var tipoDia: String?
        get() = _tipoDia.value
        set(v) {
            _tipoDia.value = v
            preferencias.guardar(CLAVE_TIPO_DIA, v)
        }

    /** Lo pone la Activity con su ciclo de vida: los sondeos solo corren con la app a la vista. */
    var enPrimerPlano: Boolean = true
        set(v) {
            field = v
            if (v && _fase.value != Fase.TOKEN_INVALIDO && !_esDemo.value) _chat.value?.empezarSondeo() else _chat.value?.pararSondeo()
        }

    init {
        token?.let(::prepararCuenta)
    }

    // ── Acceso ──

    /** Lo que pegó o abrió el cliente (link entero, a medias o el token solo). */
    suspend fun entrar(texto: String): Boolean {
        val t = FormatoToken.extraer(texto) ?: return false
        // Un link viejo que ya se sabe inválido no pisa una cuenta que anda (ACC-02): pasa al tocar un link de WhatsApp de
        // hace meses. No depende de la fase: al abrir la app tocando el link, la cuenta guardada todavía está cargando.
        if (t != token && t == preferencias.leer(CLAVE_TOKEN_INVALIDO) && token != null && !_esDemo.value) return false
        if (t == token && _fase.value == Fase.LISTO) return true
        _esDemo.value = false
        almacen.guardar(t)
        token = t
        prepararCuenta(t)
        _fase.value = Fase.CARGANDO
        cargar()
        return _fase.value == Fase.LISTO
    }

    fun salir() {
        almacen.guardar(null)
        soltarCuentaEnMemoria()
        _entreno.value = null
        _rutina.value = null
        _dieta.value = null
        _esDemo.value = false
        _sinRedEn.value = emptySet()
        _fase.value = Fase.SIN_TOKEN
    }

    /**
     * "Ver demo": la rutina y la dieta de ejemplo de la web (`SAMPLE_RUTINA` / `SAMPLE_DIET`, que la app trae
     * empaquetadas), sin cuenta. No toca la red ni escribe nada; los reemplazos viven en memoria.
     */
    fun entrarEnDemo(rutina: String, dieta: String) {
        fun envolver(estructura: String): JsonElement? = try {
            ValorJson.objeto(
                "id" to texto("demo"), "version" to numero(1), "estructura" to ValorJson.parsear(estructura), "semana_actual" to numero(1),
            ).aJson()
        } catch (_: Exception) {
            null
        }
        // La demo no escribe NADA: se suelta la cuenta en memoria (token, cola, chat…). El almacén no se toca: si había
        // una cuenta guardada, "Salir" de la demo vuelve a ella.
        soltarCuentaEnMemoria()
        _rutina.value = envolver(rutina)?.let { decodificar(it, RutinaActiva::desde) }
        _dieta.value = dietaNormalizada(envolver(dieta)?.let(ValorJson::desde))
        _desdeCache.value = false
        _sinRedEn.value = emptySet()
        _esDemo.value = true
        // ACC-07: Mi Día sembrado como la web (racha 3, hoy "entrené" y 2 vasos) y el chat con el hilo vacío, sin red ni cola.
        _revision.value = ModeloRevision.demo(cliente, alcance)
        _chat.value = ModeloChat(cliente, token = null, outbox = null, alcance = alcance)
        _entreno.value = _rutina.value?.let { r ->
            ModeloEntreno(cliente, token = null, outbox = null, disco = null, rutinaInicial = r, catalogoInicial = catalogoVigente, alcance = alcance)
        }
        _fase.value = Fase.LISTO
        _entreno.value?.let { e -> alcance.launch { e.cargar() } }
    }

    /** Salir de la demo vuelve a la bienvenida (o a la cuenta, si había una guardada). */
    suspend fun salirDeDemo() {
        _esDemo.value = false
        _rutina.value = null
        _dieta.value = null
        _swaps.value = emptyMap()
        _entreno.value = null
        _revision.value = null   // los de la demo
        _chat.value = null
        val t = almacen.leer()
        token = t
        if (t != null) {
            prepararCuenta(t)
            _fase.value = Fase.CARGANDO
            cargar()
        } else {
            _fase.value = Fase.SIN_TOKEN
        }
    }

    private fun soltarCuentaEnMemoria() {
        token = null
        disco = null
        outbox?.cerrar()
        outbox = null
        _info.value = null
        _swaps.value = emptyMap()
        _comidasLibres.value = emptyList()
        _alimentosPropios.value = emptyList()
        _excluir.value = emptyList()
        _chat.value?.pararSondeo()
        _chat.value = null
        _revision.value = null
        _fotos.value = null
        _progreso.value = null
        _salud.value?.cancelarEspera()
        _salud.value = null
        _entreno.value = null
    }

    private fun prepararCuenta(t: String) {
        val d = Disco(raizDisco, t)
        disco = d
        val escrituras = Escrituras(cliente, t)
        outbox?.cerrar()
        // Las ops de la migración esperan a la palanca remota (`cargar` la lee y se la pasa): hallazgo 2 del 15-oct.
        val cola = Outbox(archivo = d.archivo("outbox.json"), alcance = alcance, retenerLegadas = true) { op -> escrituras.ejecutar(op) }
        outbox = cola
        _chat.value?.pararSondeo()   // al cambiar de cuenta, el sondeo de la anterior no sigue
        val chat = ModeloChat(cliente, t, cola, alcance)
        _chat.value = chat
        if (enPrimerPlano) chat.empezarSondeo()
        _revision.value = ModeloRevision(cliente, t, cola, alcance)
        _fotos.value = ModeloFotos(cliente, t, d)
        _progreso.value = ModeloProgreso(cliente, t)
        _salud.value?.cancelarEspera()
        // Salud por cuenta: con el link de otra persona en este teléfono no se sube la salud del dueño (hallazgo 3 del 15-oct).
        _salud.value = ModeloSalud(cliente, t, almacen = AlmacenSaludPorCuenta(preferencias, Disco.huella(t)), alcance = alcance)
        // Los avisos llegan desde el hilo de la cola: los StateFlow se pueden tocar desde cualquier hilo y así el orden se
        // conserva (en iOS se pasa al principal con un Task por aviso).
        alcance.launch {
            cola.observar(estado = { e -> _estadoGuardado.value = e }, abandonadas = ::alAbandonar)
        }
    }

    /**
     * Lo que la cola abandonó (va a fallidos, no se borra). Un mensaje del chat se marca en su burbuja para reintentarlo
     * ("no salió → Reintentar"), como `marcarChatFallido` de la web.
     */
    private fun alAbandonar(ops: List<Operacion>) {
        for (op in ops) {
            if (op.kind != "chat") continue
            op.payload["contenido"]?.comoTexto?.let { _chat.value?.marcarFallido(it) }
        }
    }

    // ── Carga ──

    /** `offline.json`: lo último que se pudo cargar, para abrir sin señal. */
    internal data class CopiaOffline(val info: ValorJson, val rutina: ValorJson?, val dieta: ValorJson?, val ts: Double) {
        fun aValor(): ValorJson = ValorJson.Objeto(
            buildMap {
                put("info", info)
                rutina?.let { put("rutina", it) }
                dieta?.let { put("dieta", it) }
                put("ts", numero(ts))
            },
        )

        companion object {
            /** Como el `Codable` de iOS: sin `info` o sin `ts` numérico no hay copia; un `null` es lo mismo que no tenerlo. */
            fun desde(e: JsonElement?): CopiaOffline? {
                val o = (e as? JsonObject)?.let { ValorJson.desde(it) } ?: return null
                val info = o["info"] ?: return null
                val ts = o["ts"]?.comoNumero ?: return null
                return CopiaOffline(info, o["rutina"]?.takeUnless { it == ValorJson.Nulo }, o["dieta"]?.takeUnless { it == ValorJson.Nulo }, ts)
            }
        }
    }

    private fun leerCopia(): CopiaOffline? = CopiaOffline.desde(disco?.leer(ARCHIVO_COPIA))

    suspend fun cargar() {
        if (_esDemo.value) return   // la demo no toca la red (y "tirar para actualizar" no la cierra)
        val t = token ?: run {
            _fase.value = Fase.SIN_TOKEN
            return
        }
        // Todo lo que sigue es de ESTE token: si mientras tanto entró otro (un link tocado al abrir la app), lo que vuelva se
        // descarta sin tocar nada (ni el almacén ni la pantalla).
        fun vigente(): Boolean = token == t && !_esDemo.value
        val p = mapOf("p_token" to texto(t))

        val respuestaInfo = when (val r = cliente.llamar("mypump_get_cliente_info", p)) {
            is Resultado.Falla -> {
                if (!vigente()) return
                _ultimaFalla.value = r.error.clase
                // Sin red o servicio caído: la copia offline, si hay.
                val copia = leerCopia()
                if (copia != null) {
                    aplicar(copia)
                    _desdeCache.value = true
                    _fase.value = Fase.LISTO
                    // Sin red igual se puede marcar el día (sale por la cola), como la web con `MYDAY` vacío. Sin esto Mi
                    // Día quedaba tapado hasta que volviera la señal (revisión del 14-oct, hallazgo 10).
                    _revision.value?.let { r -> alcance.launch { r.cargarMiDia() } }
                } else {
                    _fase.value = Fase.SIN_SERVICIO
                }
                return
            }
            is Resultado.Ok -> {
                if (!vigente()) return
                r.valor
            }
        }
        _ultimaFalla.value = null
        // `[]` sin error = token inválido o revocado (la base no tira error: devuelve vacío).
        val primera = (respuestaInfo as? ValorJson.Lista)?.elementos?.firstOrNull()
        if (primera == null) {
            if (almacen.leer() == t) almacen.guardar(null)
            preferencias.guardar(CLAVE_TOKEN_INVALIDO, t)
            _chat.value?.pararSondeo()
            _fase.value = Fase.TOKEN_INVALIDO
            return
        }
        _info.value = decodificar(primera.aJson(), ClienteInfo::desde)
        // La misma persona con otro link (Mati lo regeneró): lo que quedó en la cola de la carpeta vieja sale con este, con el
        // `drenar()` de más abajo (hallazgo 4).
        val discoCuenta = disco
        val colaCuenta = outbox
        val clienteId = _info.value?.clienteId
        if (discoCuenta != null && colaCuenta != null && !clienteId.isNullOrEmpty()) {
            CuentasDelTelefono.anotar(clienteId, discoCuenta)
            CuentasDelTelefono.adoptar(clienteId, discoCuenta, colaCuenta)
            if (!vigente()) return
        }

        val rr: Resultado<ValorJson>
        val dd: Resultado<ValorJson>
        val palancaLeida: PalancaRemota?
        coroutineScope {
            val r = async { cliente.llamar("mypump_get_rutina_activa", p) }
            val d = async { cliente.llamar("mypump_get_dieta_activa", p) }
            val c = async { PalancaRemota.leer(cliente) }
            rr = r.await()
            dd = d.await()
            palancaLeida = c.await()
        }
        if (!vigente()) return
        palancaLeida?.let {
            _palanca.value = it
            // Con la palanca apagada, lo que la migración dejó directo en la cola tampoco sale (no solo la Fase R).
            outbox?.usarPalanca(it.opsLegadas)
        }
        // Un corte NO es "no tiene plan": lo que no llegó sale de la copia guardada (y la copia no se pisa con un hueco).
        // `null` o `[]` sin error sí es "no tiene" (Mati la desactivó).
        val copia = leerCopia()
        val faltaron = LinkedHashSet<Parte>()
        val rutinaJson = when (rr) {
            is Resultado.Ok -> rr.valor.primeraFila
            is Resultado.Falla -> copia?.rutina.also { faltaron += Parte.RUTINA }
        }
        val dietaJson = when (dd) {
            is Resultado.Ok -> dd.valor.primeraFila
            is Resultado.Falla -> copia?.dieta.also { faltaron += Parte.DIETA }
        }
        _rutina.value = rutinaJson?.let { decodificar(it.aJson(), RutinaActiva::desde) }
        _dieta.value = dietaNormalizada(dietaJson)
        if (rutinaJson != null || dietaJson != null || copia != null) {
            disco?.guardar(ARCHIVO_COPIA, CopiaOffline(primera, rutinaJson, dietaJson, System.currentTimeMillis().toDouble()).aValor())
        }
        // Los reemplazos guardados en el teléfono, ANTES de mostrar Dieta (si no, se ven tarde y un reemplazo hecho en ese
        // hueco pisaba el archivo).
        _swaps.value = _dieta.value?.id?.let(::leerSwaps) ?: emptyMap()
        _sinRedEn.value = faltaron
        _desdeCache.value = faltaron.isNotEmpty()
        prepararEntreno()
        _fase.value = Fase.LISTO
        if (faltaron.isEmpty()) _cargasConRed.update { it + 1 }
        _entreno.value?.let { e ->
            alcance.launch {
                cargarCatalogo()
                e.aplicarLegadoDelDisco()   // la sesión en curso que trajo la migración, una vez
                e.cargar()
            }
        }

        hidratarDieta()
        if (!vigente()) return
        cargarComidasLibres()
        outbox?.drenar()
        coroutineScope {
            launch { _chat.value?.cargar() }
            launch { _revision.value?.cargarMiDia() }
            launch { _revision.value?.cargarRevision() }
            launch { _fotos.value?.cargar() }
        }
        _fotos.value?.drenar()
        diaCargado = FechaLocal.hoy()
        // Salud: sus lecturas, y con la salud del sistema conectada los 7 días y el historial pendiente (sin frenar la carga).
        _salud.value?.let { s -> alcance.launch { s.alAbrir() } }
    }

    /** Volvió la red (el monitor de conectividad): sale lo pendiente y, si se mostraba la copia guardada, se trae todo. */
    suspend fun alVolverLaRed() {
        if (_fase.value != Fase.LISTO || _esDemo.value || token == null) return
        if (_desdeCache.value) {
            cargar()
            return
        }
        outbox?.drenar()
        _fotos.value?.drenar()
    }

    /**
     * Al volver a primer plano (GEN-07): salen las colas, se mira el chat, y si cambió el día se recarga lo que es "de
     * hoy" (comidas libres, Mi Día, el check de la semana). Si se estaba mostrando la copia offline, se intenta traer todo
     * de nuevo.
     */
    suspend fun alVolverAPrimerPlano() {
        if (_fase.value != Fase.LISTO || _esDemo.value || token == null) return
        if (_desdeCache.value) {
            cargar()
            return
        }
        // Primero lo "de hoy" si cambió el día (lo que se toque ahora tiene que caer en el día nuevo), después las colas.
        val hoy = FechaLocal.hoy()
        if (diaCargado != hoy) {
            cargarComidasLibres()
            _revision.value?.cargarMiDia()
            _revision.value?.cargarRevision()
            diaCargado = hoy
        }
        outbox?.drenar()
        _chat.value?.sondear()
        _fotos.value?.drenar()
        _salud.value?.alVolver()   // con la salud del sistema conectada: 7 días y retomar el historial (visibilitychange)
        _entreno.value?.alVolverAPrimerPlano()
    }

    // ── Entreno ──

    private val catalogoVigente: CatalogoEjercicios get() = catalogo ?: catalogoEmpaquetado

    /**
     * El motor de la rutina activa: se crea una vez por rutina y por cuenta; una versión nueva de la misma rutina (Mati la
     * editó, se avanzó de semana) lo actualiza sin perder lo que está en curso. Con otro link de la misma persona la rutina
     * es la misma, pero el motor de antes escribía en la cola y la carpeta del link viejo (hallazgo 4).
     */
    private fun prepararEntreno() {
        val rutina = _rutina.value ?: run {
            _entreno.value = null
            return
        }
        val e = _entreno.value
        if (e != null && e.rutina.value.id == rutina.id && e.token == token) {
            if (e.rutina.value != rutina) e.reemplazarRutina(rutina)
            return
        }
        val nuevo = ModeloEntreno(
            cliente, token = token, outbox = outbox, disco = disco, rutinaInicial = rutina, info = _info.value,
            catalogoInicial = catalogoVigente, alcance = alcance,
        )
        // Con el disco de ESTA cuenta, y solo si sigue siendo el motor vigente (como el `[weak e]` de iOS): lo que termine
        // de un motor que ya se soltó no le toca la copia a nadie.
        val d = disco
        nuevo.alCambiarRutina = { cambio -> if (_entreno.value === nuevo) cambioLaRutina(cambio, d) }
        _entreno.value = nuevo
    }

    /**
     * Lo que el motor de Entreno cambió de la rutina (avanzar de semana, bloque nuevo), con la copia offline al día. Si no,
     * un arranque sin señal volvía a la semana anterior y lo que se cargaba pisaba sus series (revisión del 15-oct, hallazgo
     * 1). La web lo resuelve recargando la página, que vuelve a guardar el snapshot.
     */
    private fun cambioLaRutina(cambio: ModeloEntreno.CambioRutina, d: Disco?) {
        var copia = d?.let { CopiaOffline.desde(it.leer(ARCHIVO_COPIA)) }
        when (cambio) {
            is ModeloEntreno.CambioRutina.Nueva -> {
                _rutina.value = cambio.rutina
                copia = copia?.copy(rutina = cambio.fila)
            }
            is ModeloEntreno.CambioRutina.Semana -> {
                _rutina.value = cambio.rutina
                val c = copia
                val o = c?.rutina as? ValorJson.Objeto
                if (c != null && o != null && o["id"]?.comoTexto == cambio.rutina.id) {
                    copia = c.copy(rutina = ValorJson.Objeto(o.campos + ("semana_actual" to numero(cambio.rutina.semanaActual))))
                }
            }
            ModeloEntreno.CambioRutina.BloqueSinTraer -> copia = copia?.copy(rutina = null)
        }
        val c = copia ?: return
        d?.guardar(ARCHIVO_COPIA, c.copy(ts = System.currentTimeMillis().toDouble()).aValor())
    }

    private val archivoCatalogo: File get() = File(raizDisco, "MyPump/catalogo-ejercicios.json")

    /**
     * `getCatalogoEjercicios`: el catálogo en el orden en que lo da el servidor (como la web: el orden decide empates en
     * los sustitutos), guardado para arrancar sin red. Si no llega, el guardado o el empaquetado.
     */
    internal suspend fun cargarCatalogo() {
        val columnas = "slug_en,name_en,name_normalized,aliases_es,primary_muscle,equipment,patron_movimiento,image_eccentric,image_concentric"
        val j = cliente.tabla("mypump_ejercicios_catalogo", columnas).valorONull()
        val nuevo = j?.let { leerCatalogo(it.serializar()) }
        if (nuevo != null) {
            catalogo = nuevo
            escribirAtomico(archivoCatalogo, j.serializar())
        } else if (catalogo == null) {
            catalogo = leerJson(archivoCatalogo)?.let { leerCatalogo(it.toString()) }
        }
        catalogo?.let { c -> _entreno.value?.actualizarCatalogo(c) }
    }

    private fun leerCatalogo(json: String): CatalogoEjercicios? = try {
        CatalogoEjercicios.desde(json).takeIf { it.entradas.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    /**
     * Progreso por el ejercicio que se hace de verdad: el sustituto si hay (PRO-02, `getEffectiveEx` en el
     * `loadProgressAndRender` de la web). Sin el motor de Entreno, por el nombre del plan.
     */
    suspend fun cargarProgreso() {
        val entreno = _entreno.value
        _progreso.value?.cargar(_rutina.value) { entreno?.efectivo(it)?.ejercicio?.nombre ?: it.nombre }
    }

    /** Lo que falta de la semana para el badge de Revisión y el banner de las otras pestañas. */
    val pendientesDeLaSemana: FotosProgreso.Pendientes
        get() {
            val r = _revision.value
            val f = _fotos.value
            if (r == null || f == null) return FotosProgreso.Pendientes(faltaCheck = false, faltanFotos = false, total = 0)
            return FotosProgreso.pendientes(r.checkinEnviado, f.posesDeLaSemana)
        }

    private fun aplicar(c: CopiaOffline) {
        _info.value = decodificar(c.info.aJson(), ClienteInfo::desde)
        _rutina.value = c.rutina?.let { decodificar(it.aJson(), RutinaActiva::desde) }
        _dieta.value = dietaNormalizada(c.dieta)
        _dieta.value?.id?.let { id -> _swaps.value = leerSwaps(id) }
        prepararEntreno()
        _entreno.value?.let { e -> alcance.launch { e.cargar() } }
    }

    // ── Dieta ──

    /** El plan que se está mirando: el tipo de día elegido o el primero; sin tipos de día, la dieta entera. */
    val comidasDelDia: List<Comida>
        get() {
            val e = _dieta.value?.estructura ?: return emptyList()
            if (e.tiposDia.isEmpty()) return e.comidas
            return (e.tiposDia.firstOrNull { it.id == tipoDia } ?: e.tiposDia[0]).comidas
        }

    /** Objetivo de macros del día: la normalización ya lo completó (sin `macros_target`, la suma de la opción A). */
    val objetivo: Macros
        get() {
            val e = _dieta.value?.estructura ?: return Macros()
            if (e.tiposDia.isEmpty()) return e.macrosTarget ?: Macros()
            return (e.tiposDia.firstOrNull { it.id == tipoDia } ?: e.tiposDia[0]).macrosTarget ?: Macros()
        }

    /**
     * GEN-05 (`avisarPlanIncompleto`): arriba de Revisión cuando al plan publicado le falta algo. No es para el cliente: es
     * para que la captura que le manda a Mati diga qué republicar, en vez de "no me carga".
     */
    val avisoPlanIncompleto: Pair<String, String>?
        get() {
            if (_esDemo.value) return null
            // Como la web: primero lo de la rutina y después lo de la dieta (se muestran los tres primeros). A propósito no se
            // suma el "Todavía no tenés dieta publicada." de la web: a quien solo tiene rutina le dejaba un aviso de error
            // fijo, y la pestaña Dieta ya lo dice.
            val p = (_entreno.value?.problemas?.value ?: emptyList()) + _problemasDieta.value
            if (p.isEmpty()) return null
            return "A tu plan le falta información y algunas cosas pueden verse raras. Avisale a Mati y lo republica." to
                p.take(3).joinToString(" · ")
        }

    fun clave(comidaId: String, opt: Int, idx: Int): String = SwapsDeComida.clave(_dieta.value?.id ?: "demo", comidaId, opt, idx)

    /** Lo que se muestra en esa posición: el sustituto si el swap aplica (anclaje), si no el alimento del plan. */
    fun efectivo(original: Alimento, comidaId: String, opt: Int, idx: Int): AlimentoEfectivo {
        val e = _dieta.value?.estructura ?: EstructuraDieta()
        val tipo = tipoDia
        return SwapsDeComida.efectivo(original, _swaps.value[clave(comidaId, opt, idx)], comidaId) {
            SwapsDeComida.enPosicion(e, tipo, comidaId, opt, idx)
        }
    }

    /** Confirmar un sustituto (`confirmSwap`): se guarda anclado y sale por la cola. */
    suspend fun sustituir(original: Alimento, sustituto: ValorJson, comidaId: String, opt: Int, idx: Int) {
        val dietaId = _dieta.value?.id ?: return
        val k = clave(comidaId, opt, idx)
        val anclado = SwapsDeComida.conAncla(sustituto, original)
        _swaps.update { it + (k to SwapLocal(alimentoJson(original), anclado)) }
        guardarSwaps()
        outbox?.encolar(
            "swap",
            ValorJson.objeto(
                "dietaId" to texto(dietaId), "comidaId" to texto(comidaId), "optIdx" to numero(opt), "foodIdx" to numero(idx), "food" to anclado,
            ),
            k,
        )
    }

    /** Volver al alimento del plan. Comparte clave con el swap: si todavía no había salido, lo reemplaza en la cola. */
    suspend fun revertir(comidaId: String, opt: Int, idx: Int) {
        val dietaId = _dieta.value?.id ?: return
        val k = clave(comidaId, opt, idx)
        _swaps.update { it - k }
        guardarSwaps()
        outbox?.encolar(
            "swap_del",
            ValorJson.objeto("dietaId" to texto(dietaId), "comidaId" to texto(comidaId), "optIdx" to numero(opt), "foodIdx" to numero(idx)),
            k,
        )
    }

    /**
     * "Crear y usar" (`saveCustomFood`): va directo, no por la cola, como en la web. Lo creado entra a la base de
     * sustitutos reemplazando al del mismo nombre. Sin cuenta (demo) queda solo en memoria. La función devuelve un
     * conjunto vacío si el token no sirve: eso también es un error para el cliente.
     */
    suspend fun crearAlimentoPropio(d: AlimentoPropioNuevo.Datos): Resultado<AlimentoPropio> {
        val t = token ?: run {
            val a = AlimentoPropio(d.nombre, d.kcal, d.prot, d.carb, d.fat, d.unidad, d.gramosPorUnidad, d.categoria)
            sumarPropio(a)
            return Resultado.Ok(a)
        }
        val p = mapOf(
            "p_token" to texto(t), "p_name" to texto(d.nombre), "p_kcal" to numero(d.kcal), "p_prot" to numero(d.prot),
            "p_carb" to numero(d.carb), "p_fat" to numero(d.fat), "p_unit" to texto(d.unidad),
            "p_unit_grams" to (d.gramosPorUnidad?.let { numero(it) } ?: ValorJson.Nulo),
            "p_category" to (if (d.categoria.isEmpty()) ValorJson.Nulo else texto(d.categoria)),
        )
        return when (val r = cliente.filas("mypump_create_custom_food", p, AlimentoPropio::desde)) {
            is Resultado.Falla -> r
            is Resultado.Ok -> {
                val a = r.valor.firstOrNull()
                    ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_FILA", "mypump_create_custom_food: vacío"))
                sumarPropio(a)
                Resultado.Ok(a)
            }
        }
    }

    // ── Comidas libres ──

    /** `loadComidasLibres`: las del día local. Sin cuenta (demo) no hay. */
    suspend fun cargarComidasLibres() {
        val t = token ?: run {
            _comidasLibres.value = emptyList()
            return
        }
        cliente.filas("mypump_get_comidas_libres", mapOf("p_token" to texto(t), "p_fecha" to texto(FechaLocal.hoy())), ComidaLibre::desde)
            .valorONull()?.let { _comidasLibres.value = it }
    }

    /** `guardarComidaLibre`: directo, no por la cola (como la web), con la fecha local. */
    suspend fun crearComidaLibre(d: ComidaLibreNueva.Datos): Resultado<ComidaLibre> {
        val t = token ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 0, "SIN_CUENTA", "demo"))
        val p = mapOf(
            "p_token" to texto(t), "p_fecha" to texto(FechaLocal.hoy()), "p_hora" to (d.hora?.let { texto(it) } ?: ValorJson.Nulo),
            "p_descripcion" to texto(d.descripcion), "p_kcal" to numero(d.kcal), "p_prot" to numero(d.prot),
            "p_carb" to numero(d.carb), "p_fat" to numero(d.fat), "p_detalle" to (d.detalle ?: ValorJson.Nulo),
        )
        return when (val r = cliente.filas("mypump_crear_comida_libre", p, ComidaLibre::desde)) {
            is Resultado.Falla -> r
            is Resultado.Ok -> {
                val c = r.valor.firstOrNull()
                    ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_FILA", "mypump_crear_comida_libre: vacío"))
                _comidasLibres.update { it + c }
                Resultado.Ok(c)
            }
        }
    }

    /** `borrarComidaLibre`: optimista; si el servidor no contesta bien, vuelve a aparecer. */
    suspend fun borrarComidaLibre(id: String): Boolean {
        val previas = _comidasLibres.value
        _comidasLibres.update { lista -> lista.filterNot { it.id == id } }
        val t = token ?: return true
        if (cliente.llamar("mypump_borrar_comida_libre", mapOf("p_token" to texto(t), "p_id" to texto(id))) is Resultado.Falla) {
            _comidasLibres.value = previas
            return false
        }
        return true
    }

    /** `visionDesdeFoto`: la foto (JPEG ya reducido) a mini-vision. Tarda ~30 s, hasta 150. */
    suspend fun analizarFoto(jpeg: ByteArray, tipo: ClienteRpc.TipoVision): Resultado<ValorJson> {
        val t = token ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 0, "SIN_CUENTA", "demo"))
        return cliente.vision(t, tipo, jpeg)
    }

    /** Como la web: reemplaza en su lugar al del mismo nombre (sin distinguir mayúsculas) o se agrega al final. */
    private fun sumarPropio(a: AlimentoPropio) {
        _alimentosPropios.update { lista ->
            val i = lista.indexOfFirst { it.nombre.lowercase() == a.nombre.lowercase() }
            if (i >= 0) lista.toMutableList().also { it[i] = a } else lista + a
        }
    }

    private fun leerSwaps(dietaId: String): Map<String, SwapLocal> {
        val o = disco?.leer("swaps_$dietaId.json") as? JsonObject ?: return emptyMap()
        val m = LinkedHashMap<String, SwapLocal>()
        for ((k, v) in o) {
            val s = ValorJson.desde(v)
            val current = s["current"] ?: continue
            m[k] = SwapLocal(s["original"]?.takeUnless { it == ValorJson.Nulo }, current)
        }
        return m
    }

    private fun guardarSwaps() {
        val id = _dieta.value?.id ?: return
        val d = disco ?: return
        d.guardar(
            "swaps_$id.json",
            ValorJson.Objeto(
                _swaps.value.mapValues { (_, s) ->
                    ValorJson.Objeto(
                        buildMap {
                            s.original?.let { put("original", it) }
                            put("current", s.current)
                        },
                    )
                },
            ),
        )
    }

    /** Preferencias, alimentos propios y swaps del servidor (hydrateSwapsAndCustomFoodsFromBackend). */
    internal suspend fun hidratarDieta() {
        val t = token ?: return
        val dieta = _dieta.value ?: return
        val p = mapOf("p_token" to texto(t))
        cliente.filas("mypump_get_cliente_prefs", p, PreferenciasCliente::desde).valorONull()?.let {
            _excluir.value = it.firstOrNull()?.excluir ?: emptyList()
        }
        cliente.filas("mypump_get_custom_foods", p, AlimentoPropio::desde).valorONull()?.let { _alimentosPropios.value = it }

        val remotos = cliente.filas("mypump_get_food_swaps", mapOf("p_token" to texto(t), "p_dieta_id" to texto(dieta.id)), FoodSwap::desde)
            .valorONull()
        val pendientes = (outbox?.pendientesPorClave() ?: emptyMap()).mapValues { it.value.kind }
        val marca = "swaps_migrados_${dieta.id}"
        val yaMigrado = (disco?.leer(marca) as? JsonPrimitive)?.booleanOrNull ?: false
        val e = dieta.estructura
        val tipo = tipoDia
        val h = SwapsDeComida.hidratar(remotos, _swaps.value, dieta.id, pendientes, yaMigrado, _palanca.value.anclajeBorraSwaps) { c, o, f ->
            SwapsDeComida.enPosicion(e, tipo, c, o, f)
        } ?: return
        _swaps.value = h.swaps
        guardarSwaps()
        for (op in h.operaciones) {
            val payload = (op.payload as? ValorJson.Objeto)?.let { ValorJson.Objeto(it.campos + ("dietaId" to texto(dieta.id))) } ?: op.payload
            outbox?.encolar(op.kind, payload, op.clave)
        }
        if (h.migrando) {
            outbox?.drenar()
            val quedan = (outbox?.pendientesPorClave() ?: emptyMap()).keys.any { it.startsWith("swap_${dieta.id}_") }
            if (!quedan) disco?.guardar(marca, ValorJson.Booleano(true))
        } else if (h.marcarMigrado) {
            disco?.guardar(marca, ValorJson.Booleano(true))
        }
    }

    /**
     * La dieta como la usa la web: normalizada (`normalizarDieta`). Sin ninguna comida usable no hay dieta (la web mostraba
     * la de ejemplo como si fuera del cliente; acá se dice que todavía no hay plan).
     */
    private fun dietaNormalizada(j: ValorJson?): DietaActiva? {
        val d = j?.let { decodificar(it.aJson(), DietaActiva::desde) }
        if (d == null) {
            _problemasDieta.value = emptyList()
            return null
        }
        val r = NormalizarDieta.normalizar(d.estructura)
        // Como la web: de una dieta que no sirve no se listan sus detalles, se dice que está incompleta.
        _problemasDieta.value = if (r.usable) r.problemas else listOf("Tu dieta está publicada pero incompleta.")
        if (!r.usable) return null
        return d.copy(estructura = r.estructura)
    }

    companion object {
        /**
         * El catálogo de ejercicios que trae la app (el de `apps/shared/catalogo-ejercicios.json`): lo pone la app al
         * arrancar. Se usa hasta que llega el del servidor, y para arrancar sin red si nunca llegó.
         */
        @Volatile
        var catalogoEmpaquetado: CatalogoEjercicios = CatalogoEjercicios(emptyList())

        const val CLAVE_TIPO_DIA = "mypump_tipo_dia"
        const val CLAVE_TOKEN_INVALIDO = "mypump_token_invalido"
        internal const val ARCHIVO_COPIA = "offline.json"

        fun sumar(a: List<Alimento>): Macros = Macros(
            kcal = a.mapNotNull { it.kcal }.sum(), prot = a.mapNotNull { it.prot }.sum(),
            carb = a.mapNotNull { it.carb }.sum(), fat = a.mapNotNull { it.fat }.sum(),
        )

        /** Un alimento del plan devuelto a JSON (el `original` que guarda la web junto al swap). */
        fun alimentoJson(a: Alimento): ValorJson = ValorJson.Objeto(
            buildMap {
                put("name", texto(a.nombre))
                a.qty?.let { put("qty", numero(it)) }
                a.unidad?.let { put("unit", texto(it)) }
                a.kcal?.let { put("kcal", numero(it)) }
                a.prot?.let { put("prot", numero(it)) }
                a.carb?.let { put("carb", numero(it)) }
                a.fat?.let { put("fat", numero(it)) }
                a.categoria?.let { put("category", texto(it)) }
            },
        )

        private fun <T> decodificar(j: JsonElement, leer: (JsonElement) -> T): T? = try {
            leer(j)
        } catch (_: Exception) {
            null
        }
    }
}

/** `rows[0]` de una RPC que devuelve una tabla. */
internal val ValorJson.primeraFila: ValorJson? get() = (this as? ValorJson.Lista)?.elementos?.firstOrNull()
