package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.ClienteInfo
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.ComidaMarcada
import com.pumpteam.mypump.modelos.DietaActiva
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.PreferenciasCliente
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AjustePorciones
import com.pumpteam.mypump.reglas.AgregadosComida
import com.pumpteam.mypump.reglas.CacheCodigos
import com.pumpteam.mypump.reglas.CodigoBarras
import com.pumpteam.mypump.reglas.AlimentoAgregado
import com.pumpteam.mypump.reglas.AlimentoEfectivo
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import com.pumpteam.mypump.reglas.ConsumoDelDia
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.SemanaRevision
import com.pumpteam.mypump.reglas.MarcaComida
import com.pumpteam.mypump.reglas.NormalizarDieta
import com.pumpteam.mypump.reglas.MetasPlan
import com.pumpteam.mypump.reglas.PumpDelDia
import com.pumpteam.mypump.reglas.SaludVista
import com.pumpteam.mypump.reglas.SwapLocal
import com.pumpteam.mypump.reglas.SwapsDeComida
import java.io.File
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
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
    internal val alcance: CoroutineScope,
    /** Donde esperan los archivos de «Estudios» hasta subir (en la app, `noBackupFilesDir`). Sin ella, [raizDisco]. */
    private val raizSinRespaldo: File? = null,
    /** La caché de la app (`cacheDir`): lo de «Estudios» que quedó ahí se barre al arrancar y al cerrar sesión. */
    private val raizCache: File? = null,
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

    /** La sesión del día de la cuenta: la comparten la cola y el motor de Entreno (hallazgo 5). */
    private var sesionesDelDia = SesionesDelDia(alcance)

    /** El día local de la última carga completa: si al volver a la app cambió, se recarga lo que es "de hoy". */
    private var diaCargado: String? = null

    private val _fase = MutableStateFlow(if (token == null) faseSinCuenta() else Fase.CARGANDO)

    /**
     * Sin cuenta guardada: si la última que hubo la dio de baja la base, se sigue explicando (F10, auditoría del 10/11). Antes,
     * al volver a abrir la app después de «Este link ya no sirve», se veía la bienvenida vacía sin decir qué pasó.
     */
    private fun faseSinCuenta(): Fase = if (preferencias.leer(CLAVE_TOKEN_INVALIDO) == null) Fase.SIN_TOKEN else Fase.TOKEN_INVALIDO
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
    private val _perdidos = MutableStateFlow(0)

    /** F5 (auditoría 10/11): cuántas cosas la cola no pudo guardar (quedan a la vista con «Reintentar» hasta que salgan). */
    val perdidos: StateFlow<Int> = _perdidos.asStateFlow()

    // Dieta
    private val _excluir = MutableStateFlow<List<String>>(emptyList())
    val excluir: StateFlow<List<String>> = _excluir.asStateFlow()

    private val _alimentosPropios = MutableStateFlow<List<AlimentoPropio>>(emptyList())
    val alimentosPropios: StateFlow<List<AlimentoPropio>> = _alimentosPropios.asStateFlow()

    /** La palanca remota (G2). Se lee en cada carga; sin la tabla o sin red queda la de fábrica (todo prendido). */
    private val _palanca = MutableStateFlow(PalancaRemota.deFabrica)

    /** La palanca se leyó en esta cuenta (si no, los adjuntos del chat quedan como la última vez que se supo). */
    @Volatile private var palancaLeidaEnSesion = false
    val palanca: StateFlow<PalancaRemota> = _palanca.asStateFlow()

    /** «Pump del día» (2.3.0): las fechas ya celebradas de esta cuenta (`metas.json` en su disco; en la demo, en memoria). */
    private val _registroMetas = MutableStateFlow(PumpDelDia.Registro())
    val registroMetas: StateFlow<PumpDelDia.Registro> = _registroMetas.asStateFlow()

    /** Las metas del plan, o null con la palanca `metas_pasos` apagada o sin ninguna meta (planes viejos: no se inventa). */
    fun metas(): MetasPlan? {
        // La demo con historial trae sus metas inventadas (no depende de ninguna palanca: no hay servidor).
        if (_esDemo.value) return _demoHistorial.value?.metas
        if (!_palanca.value.metasPasos) return null
        val e = _dieta.value?.estructura ?: return null
        return MetasPlan.desde(e).takeIf { !it.vacio }
    }

    /** El «Pump del día» de hoy con los pasos de Salud. null sin meta de pasos. `second`: hay de dónde sacar los pasos. */
    fun pumpDelDia(hoy: String = FechaLocal.hoy()): Pair<PumpDelDia.Vista, Boolean>? {
        val meta = metas()?.metaPasos ?: return null
        val s = _salud.value
        val demo = _demoHistorial.value?.takeIf { _esDemo.value }
        val filas = demo?.salud ?: s?.salud?.value ?: emptyList()
        val v = PumpDelDia.vista(PumpDelDia.pasosPorDia(filas), meta, hoy) ?: return null
        val conectado = demo != null || s?.conectado?.value == true || SaludVista.tieneReciente(filas, listOf("pasos"), 7, hoy)
        return v to conectado
    }

    /** ¿Toca la celebración ahora? Una sola vez por día y por cuenta. */
    fun debeCelebrarPump(v: PumpDelDia.Vista, hoy: String = FechaLocal.hoy()): Boolean =
        PumpDelDia.debeCelebrar(_registroMetas.value, hoy, v.pasosHoy, v.meta)

    /** Anota el día como celebrado (apenas empieza la animación, para que no se repita). */
    fun marcarPumpCelebrado(hoy: String = FechaLocal.hoy()) {
        val r = PumpDelDia.marcar(_registroMetas.value, hoy)
        _registroMetas.value = r
        disco?.guardar(ARCHIVO_METAS, ValorJson.objeto("celebrados" to ValorJson.Lista(r.celebrados.map { ValorJson.Texto(it) })))
    }

    private fun leerRegistroMetas(d: Disco): PumpDelDia.Registro {
        val j = d.leer(ARCHIVO_METAS)?.let(ValorJson::desde) ?: return PumpDelDia.Registro()
        val l = (j["celebrados"] as? ValorJson.Lista)?.elementos ?: return PumpDelDia.Registro()
        return PumpDelDia.Registro(l.mapNotNull { (it as? ValorJson.Texto)?.valor })
    }

    private val _swaps = MutableStateFlow<Map<String, SwapLocal>>(emptyMap())

    /**
     * Los reemplazos que el cliente tocó en este teléfono (sustituir o volver al del plan), con su número de orden. Si una
     * hidratación estaba esperando los swaps del servidor cuando el cliente tocó uno, lo de acá gana: si no, y el cambio
     * ya había salido por la cola, la respuesta vieja lo resucitaba hasta la próxima carga (15-oct).
     */
    private val tocadosSwaps = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val ordenSwaps = java.util.concurrent.atomic.AtomicLong()

    private fun anotarSwapTocado(k: String) {
        tocadosSwaps[k] = ordenSwaps.incrementAndGet()
    }
    val swaps: StateFlow<Map<String, SwapLocal>> = _swaps.asStateFlow()

    /**
     * Los ajustes de porciones del día, por comida (feedback del 20-oct; ver AjustesDieta.kt). Solo valen el día de
     * [fechaAjustes]: lo que se muestra es [ajustesDeHoy].
     */
    private val _ajustes = MutableStateFlow<Map<String, AjusteComida>>(emptyMap())
    val ajustes: StateFlow<Map<String, AjusteComida>> = _ajustes.asStateFlow()
    @Volatile internal var fechaAjustes = ""
        private set

    /** Las opciones que se vieron por última vez en Dieta: el resumen que va al servidor las usa aunque el cambio venga de otro lado. */
    @Volatile internal var opcionesVistas: Map<String, Int> = emptyMap()
        private set

    /** Cuántas veces cambió el cliente los ajustes (la hidratación no pisa lo que se tocó mientras esperaba al servidor). */
    private val ordenAjustes = java.util.concurrent.atomic.AtomicLong()

    /**
     * Los últimos alimentos agregados a una comida (2.0.3, D1), con su cantidad: «Recientes» de la hoja de agregar. Solo en
     * el teléfono (`agregados_recientes.json`).
     */
    /**
     * Los ajustes de hoy no se pudieron guardar en el servidor (la base los rechazó o se abandonaron): quedan en el
     * teléfono, la hidratación no los pisa y Dieta lo avisa. Se baja cuando sale el día de nuevo. Gemelo de iOS.
     */
    internal val _ajustesSinGuardar = MutableStateFlow(false)
    val ajustesSinGuardar: StateFlow<Boolean> = _ajustesSinGuardar.asStateFlow()

    private val _agregadosRecientes = MutableStateFlow<List<AlimentoAgregado>>(emptyList())
    val agregadosRecientes: StateFlow<List<AlimentoAgregado>> = _agregadosRecientes.asStateFlow()

    /**
     * «Comí» / «Salté» de hoy, por comida (D25; ver MarcasComidas.kt). Solo valen el día de [fechaMarcas]: lo que se
     * muestra es [marcasDeHoy].
     */
    private val _marcas = MutableStateFlow<Map<String, MarcaComida>>(emptyMap())
    val marcas: StateFlow<Map<String, MarcaComida>> = _marcas.asStateFlow()
    @Volatile internal var fechaMarcas = ""
        private set

    /** Cuándo tocó el cliente cada marca por última vez (la lectura del servidor no pisa lo que se tocó mientras viajaba). */
    private val ordenMarcas = java.util.concurrent.ConcurrentHashMap<String, Long>()
    private val contadorMarcas = java.util.concurrent.atomic.AtomicLong()

    /** Comidas libres (fuera del plan) del día local. */
    private val _comidasLibres = MutableStateFlow<List<ComidaLibre>>(emptyList())
    val comidasLibres: StateFlow<List<ComidaLibre>> = _comidasLibres.asStateFlow()

    /** El día anterior que se está mirando en Dieta (null: hoy). Ver DiaPasadoDieta.kt. */
    internal val _diaPasado = MutableStateFlow<DiaPasado?>(null)
    val diaPasado: StateFlow<DiaPasado?> = _diaPasado.asStateFlow()
    internal var vueltaDiaPasado = 0

    /** Cuántas veces tocó algo del día pasado (la lectura no pisa lo que se tocó mientras viajaba). */
    internal var ordenDiaPasado = 0

    /** El chat con Mati (no existe sin cuenta; en la demo es el hilo vacío, sin red). */
    private val _chat = MutableStateFlow<ModeloChat?>(null)
    val chat: StateFlow<ModeloChat?> = _chat.asStateFlow()

    /** Revisión: el check y el peso de la semana (en la demo, sin red ni cola). */
    private val _revision = MutableStateFlow<ModeloRevision?>(null)
    val revision: StateFlow<ModeloRevision?> = _revision.asStateFlow()

    /** Fotos de progreso, con su cola propia en disco. */
    private val _fotos = MutableStateFlow<ModeloFotos?>(null)
    val fotos: StateFlow<ModeloFotos?> = _fotos.asStateFlow()

    /** Gimnasio por fotos: existe con cuenta, pero solo llama al servidor con la palanca `gimnasio_fotos` prendida. */
    private val _gimnasio = MutableStateFlow<ModeloGimnasio?>(null)
    val gimnasio: StateFlow<ModeloGimnasio?> = _gimnasio.asStateFlow()

    /** Fotos de inicio: existe con cuenta, pero solo llama al servidor con la palanca `fotos_inicio` prendida. */
    private val _fotosInicio = MutableStateFlow<ModeloFotosInicio?>(null)
    val fotosInicio: StateFlow<ModeloFotosInicio?> = _fotosInicio.asStateFlow()

    /** Técnica por video: existe con cuenta, pero solo llama al servidor con la palanca `tecnica_video` prendida. */
    private val _tecnica = MutableStateFlow<ModeloTecnica?>(null)
    val tecnica: StateFlow<ModeloTecnica?> = _tecnica.asStateFlow()
    /** Devolución de Mati: existe con cuenta, pero solo llama al servidor con la palanca `devolucion_semanal` prendida. */
    private val _devolucion = MutableStateFlow<ModeloDevolucion?>(null)
    val devolucion: StateFlow<ModeloDevolucion?> = _devolucion.asStateFlow()

    /** Feedback del alumno: existe con cuenta, pero solo llama al servidor con `me_duele` o `suple_estado` prendidas. */
    private val _feedback = MutableStateFlow<ModeloFeedback?>(null)
    val feedback: StateFlow<ModeloFeedback?> = _feedback.asStateFlow()

    /** Estudios y órdenes: existe con cuenta, pero solo llama al servidor con la palanca `estudios_app` prendida. */
    private val _estudios = MutableStateFlow<ModeloEstudios?>(null)
    val estudios: StateFlow<ModeloEstudios?> = _estudios.asStateFlow()
    /** «Récords y logros» (2.3.0): existe con cuenta, pero solo llama al servidor con la palanca `wins_app` prendida. */
    private val _wins = MutableStateFlow<ModeloWins?>(null)
    val wins: StateFlow<ModeloWins?> = _wins.asStateFlow()
    /** La lista previa a la videollamada (2.3.0): con cuenta y la palanca `lista_previa`; en la demo, la fija del historial. */
    private val _listaPrevia = MutableStateFlow<ModeloListaPrevia?>(null)
    val listaPrevia: StateFlow<ModeloListaPrevia?> = _listaPrevia.asStateFlow()
    /** El historial inventado de la demo sin cuenta (null con cuenta, o si la app no lo trae). Nunca se mezcla con una cuenta. */
    private val _demoHistorial = MutableStateFlow<HistorialDemo?>(null)
    val demoHistorial: StateFlow<HistorialDemo?> = _demoHistorial.asStateFlow()

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
    /** «Tu guía»: la tarjeta de inicio y la sección (con una cuenta, o la de muestra en la demo: [ModeloGuia.demo]). */
    private val _guia = MutableStateFlow<ModeloGuia?>(null)
    val guia: StateFlow<ModeloGuia?> = _guia.asStateFlow()

    /**
     * La pestaña Suplementación (2.1.0): con una cuenta, o la de muestra en la demo ([ModeloSuplementacion.demo]). La
     * pestaña existe solo si su [ModeloSuplementacion.plan] no es null.
     */
    private val _suplementacion = MutableStateFlow<ModeloSuplementacion?>(null)
    val suplementacion: StateFlow<ModeloSuplementacion?> = _suplementacion.asStateFlow()

    /** «Novedades de tu plan» (2.3.0): existe con cuenta; solo compara y se muestra con la palanca `novedades_plan`. */
    private val _novedades = MutableStateFlow<ModeloNovedades?>(null)
    val novedades: StateFlow<ModeloNovedades?> = _novedades.asStateFlow()

    /** Fin de plan, «Tu recorrido» (2.3.0): existe con cuenta; solo llama al servidor con la palanca `fin_plan` prendida. */
    private val _finPlan = MutableStateFlow<ModeloFinPlan?>(null)
    val finPlan: StateFlow<ModeloFinPlan?> = _finPlan.asStateFlow()

    /** Compras por país, «Dónde comprarlo» (2.3.0): existe con cuenta; solo llama con la palanca `compras_pais` prendida. */
    private val _compras = MutableStateFlow<ModeloCompras?>(null)
    val compras: StateFlow<ModeloCompras?> = _compras.asStateFlow()

    /** Entrenar en casa (2.3.0): el interruptor de Mi gimnasio. Solo llama con las palancas `gimnasio_fotos` y `casa`. */
    private val _casa = MutableStateFlow<ModeloCasa?>(null)
    val casa: StateFlow<ModeloCasa?> = _casa.asStateFlow()

    /** La demo con novedades de muestra (capturas). Solo en la demo: nunca toca una cuenta. */
    fun usarNovedadesDeMuestra(m: ModeloNovedades) {
        if (_esDemo.value) _novedades.value = m
    }
    /**
     * Documentos (contrato y consentimiento): la fila de Mis datos y el aviso de Entreno, solo si `mypump_contrato_get`
     * devolvió algo. No existe en la demo ni sin cuenta.
     */
    private val _documentos = MutableStateFlow<ModeloDocumentos?>(null)
    val documentos: StateFlow<ModeloDocumentos?> = _documentos.asStateFlow()

    private val _salud = MutableStateFlow<ModeloSalud?>(null)
    val salud: StateFlow<ModeloSalud?> = _salud.asStateFlow()

    /** El catálogo de ejercicios que llegó del servidor (o el guardado de la última vez). */
    private var catalogo: CatalogoEjercicios? = null

    /** Lo que el motor de Entreno carga aparte después de cada carga (sesión, historial, comentarios). */
    private var cargaDelMotor: Job? = null

    /** El tipo de día elegido (entreno/descanso) en dietas con `tipos_dia`. Es global en la web (`mypump_tipo_dia`). */
    private val _tipoDia = MutableStateFlow(preferencias.leer(CLAVE_TIPO_DIA))
    val tipoDiaFlow: StateFlow<String?> = _tipoDia.asStateFlow()
    var tipoDia: String?
        get() = _tipoDia.value
        set(v) {
            val antes = _tipoDia.value
            _tipoDia.value = v
            preferencias.guardar(CLAVE_TIPO_DIA, v)
            // Otro tipo de día es otro plan: el resumen de los ajustes que ve Mati se rehace.
            if (antes != v && ajustesDeHoy.isNotEmpty() && !_esDemo.value) alcance.launch { encolarAjustes(emptyMap()) }
        }

    /** Lo pone la Activity con su ciclo de vida: los sondeos solo corren con la app a la vista. */
    var enPrimerPlano: Boolean = true
        set(v) {
            field = v
            if (v && _fase.value != Fase.TOKEN_INVALIDO && !_esDemo.value) _chat.value?.empezarSondeo() else _chat.value?.pararSondeo()
        }

    init {
        // Antes que nada, y sin mirar la palanca ni si hay sesión: lo médico que venció o quedó suelto no sigue en el teléfono.
        ColaEstudios.barrerTelefono(raizDisco, raizSinRespaldo ?: raizDisco, raizCache)
        token?.let(::prepararCuenta)
    }

    // ── Acceso ──

    /** Un link tocado con una cuenta andando que no se usó: el aviso que ve el cliente, que sigue en su cuenta. */
    enum class AvisoLink {
        /** "Este link ya no sirve" */
        VENCIDO,

        /** No se pudo revisar el link (sin red): no se cambia de cuenta sin saber si anda. */
        SIN_CONEXION,

        /** Un link de la app que llegó cortado o mal copiado (F10): antes la app se abría y no decía nada. */
        MAL_FORMADO,
    }

    /** Lo muestra la raíz y lo borra al cerrarlo ([cerrarAvisoLink]). */
    private val _avisoLink = MutableStateFlow<AvisoLink?>(null)
    val avisoLink: StateFlow<AvisoLink?> = _avisoLink.asStateFlow()

    fun cerrarAvisoLink() {
        _avisoLink.value = null
    }

    private var entradas = 0

    /**
     * Lo que pegó o abrió el cliente (link entero, a medias o el token solo). `avisar = false` para lo que no tocó el cliente
     * (el token que adoptó la migración): ahí no se le muestra nada.
     */
    suspend fun entrar(texto: String, avisar: Boolean = true): Boolean {
        val t = FormatoToken.extraer(texto) ?: run {
            if (avisar && FormatoToken.pareceLink(texto)) _avisoLink.value = AvisoLink.MAL_FORMADO
            return false
        }
        // El link puede llegar antes que la vuelta a primer plano: con una cuenta que no se pudo leer al nacer, no la pisa.
        retomarCuentaGuardada()
        entradas += 1
        val entrada = entradas
        // Un link viejo que ya se sabe inválido no pisa una cuenta que anda (ACC-02): pasa al tocar un link de WhatsApp de
        // hace meses. No depende de la fase: al abrir la app tocando el link, la cuenta guardada todavía está cargando.
        if (t != token && t == preferencias.leer(CLAVE_TOKEN_INVALIDO) && token != null && !_esDemo.value) {
            if (avisar) _avisoLink.value = AvisoLink.VENCIDO
            return false
        }
        if (t == token && _fase.value == Fase.LISTO) return true
        // Con una cuenta que anda, el link nuevo se revisa ANTES de reemplazarla. Antes se guardaba primero y se borraba al ver
        // `[]`: un link viejo nunca usado en este teléfono dejaba al cliente en "pegá tu link" y sin la cuenta que tenía
        // (revisión del 15-oct, hallazgo 11). Sin cuenta (o con la suya vencida), como siempre.
        val actual = token
        if (actual != null && t != actual && !_esDemo.value && _fase.value != Fase.TOKEN_INVALIDO) {
            val r = cliente.llamar("mypump_get_cliente_info", mapOf("p_token" to ValorJson.Texto(t)))
            // Mientras se preguntaba se tocó otro link: gana el último.
            if (entrada != entradas || token != actual || _esDemo.value) return false
            // Si mientras tanto la cuenta guardada resultó vencida, ya no hay una que anda: sigue como sin cuenta. Si no,
            // volvía a guardar la vencida y avisaba "Seguís con tu cuenta." encima de "Este link ya no sirve".
            if (_fase.value != Fase.TOKEN_INVALIDO) when (r) {
                is Resultado.Falla -> {
                    if (avisar) _avisoLink.value = AvisoLink.SIN_CONEXION
                    return false
                }
                is Resultado.Ok -> {
                    // Un 200 que no es una lista (vacío, un objeto: un proxy, un corte) no dice nada de ese link.
                    val filas = r.valor as? ValorJson.Lista
                    if (filas == null) {
                        if (avisar) _avisoLink.value = AvisoLink.SIN_CONEXION
                        return false
                    }
                    if (filas.elementos.isEmpty()) {
                        preferencias.guardar(CLAVE_TOKEN_INVALIDO, t)
                        // La cuenta que anda es la que queda guardada (la migración pudo haber dejado el otro en el almacén).
                        if (almacen.leer() != actual) almacen.guardar(actual)
                        if (avisar) _avisoLink.value = AvisoLink.VENCIDO
                        return false
                    }
                }
            }
        }
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
        preferencias.guardar(CLAVE_TOKEN_INVALIDO, null)   // salió él: la próxima vez, la bienvenida
        // Lo buscado por código se va con la cuenta: se borra del teléfono.
        disco?.borrar(ARCHIVO_CODIGOS)
        // Lo médico tampoco se queda: ni los estudios que esperaban salir, ni lo elegido, ni lo que se bajó para ver.
        _estudios.value?.borrarTodo()
        raizCache?.let { ColaEstudios.limpiarCache(it) }
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
    fun entrarEnDemo(
        rutina: String,
        dieta: String,
        guia: String? = null,
        suplementacion: String? = null,
        agenda: String? = null,
        historial: String? = null,
    ) {
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
        fechaAjustes = FechaLocal.hoy()
        fechaMarcas = FechaLocal.hoy()
        _desdeCache.value = false
        _sinRedEn.value = emptySet()
        _esDemo.value = true
        // ACC-07: Revisión y el chat con el hilo vacío, sin red ni cola.
        // El historial inventado (2.3.0), opcional: sin él la demo queda como antes. Días relativos a hoy; nada viaja ni se escribe.
        val h = historial?.let { HistorialDemo.desde(it) }
        _demoHistorial.value = h
        _revision.value = ModeloRevision.demo(cliente, alcance, salud = h?.salud ?: emptyList())
        _chat.value = ModeloChat(cliente, token = null, outbox = null, alcance = alcance, muestra = h?.chat ?: emptyList())
        _listaPrevia.value = h?.listaPrevia?.let { ModeloListaPrevia.demo(it) }
        _progreso.value = h?.let { ModeloProgreso(cliente, "", muestra = it.porClave) }
        // «Tu guía» de muestra (los clips genéricos de «Tu app»), como la rutina: sin red; lo visto y las dudas en memoria.
        _guia.value?.cerrar()
        _guia.value = guia?.let { g ->
            try {
                Guia.desde(ValorJson.parsear(g).aJson())
            } catch (_: Exception) {
                null
            }
        }?.let { g ->
            // La agenda de muestra (2.2.0), opcional: sin ella la guía de la demo queda como en la 2.1.0.
            val a = agenda?.let { runCatching { AgendaEntrega.desde(ValorJson.parsear(it).aJson()) }.getOrNull() }
            ModeloGuia.demo(cliente, g, alcance, a)
        }
        // La suplementación de muestra (la fila del RPC), opcional como la guía.
        _suplementacion.value = suplementacion?.let { s ->
            try {
                PlanSuplementacion.desde(ValorJson.parsear(s))
            } catch (_: Exception) {
                null
            }
        }?.let { ModeloSuplementacion.demo(cliente, it, alcance) }
        _entreno.value = _rutina.value?.let { r ->
            ModeloEntreno(cliente, token = null, outbox = null, disco = null, rutinaInicial = r, catalogoInicial = catalogoVigente, alcance = alcance)
                .also { it.historialDemo = h?.porClave }
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
        _ajustes.value = emptyMap()
        opcionesVistas = emptyMap()
        _marcas.value = emptyMap()
        ordenMarcas.clear()
        _diaPasado.value = null
        _entreno.value = null
        _revision.value = null   // los de la demo
        _chat.value = null
        _demoHistorial.value = null
        _listaPrevia.value = null
        _progreso.value = null
        _registroMetas.value = PumpDelDia.Registro()
        _guia.value?.cerrar()
        _guia.value = null
        _suplementacion.value = null
        _novedades.value = null
        _documentos.value = null
        _finPlan.value = null
        _compras.value = null
        _casa.value = null
        val t = almacen.leer()
        token = t
        if (t != null) {
            prepararCuenta(t)
            _fase.value = Fase.CARGANDO
            cargar()
        } else {
            _fase.value = faseSinCuenta()
        }
    }

    private fun soltarCuentaEnMemoria() {
        token = null
        disco = null
        _registroMetas.value = PumpDelDia.Registro()
        cacheCodigos = null
        outbox?.cerrar()
        outbox = null
        _info.value = null
        _swaps.value = emptyMap()
        _ajustes.value = emptyMap()
        opcionesVistas = emptyMap()
        _marcas.value = emptyMap()
        ordenMarcas.clear()
        _diaPasado.value = null
        _comidasLibres.value = emptyList()
        _alimentosPropios.value = emptyList()
        _excluir.value = emptyList()
        _chat.value?.pararSondeo()
        _chat.value = null
        _revision.value = null
        _fotos.value = null
        _gimnasio.value = null
        _fotosInicio.value = null
        _tecnica.value = null
        _devolucion.value = null
        _feedback.value = null
        _estudios.value = null
        _wins.value = null
        _listaPrevia.value = null
        _demoHistorial.value = null
        _progreso.value = null
        _salud.value?.cancelarEspera()
        _salud.value = null
        _guia.value?.cerrar()
        _guia.value = null
        _suplementacion.value = null
        _novedades.value = null
        _documentos.value = null
        _finPlan.value = null
        _compras.value = null
        _casa.value = null
        _entreno.value = null
    }

    /**
     * Hay un mapa de reemplazos de comida sin la marca de migrados: el servidor quizás nunca los vio y, hasta decidirlo, la
     * cola retiene los `swap` y `swap_del` (también los nativos).
     */
    internal fun faltaDecidirSwaps(d: Disco): Boolean = faltaDecidirSwapsEn(d)

    private fun prepararCuenta(t: String) {
        // Otra cuenta (un link tocado mirando un día anterior): lo que se estaba mirando no es de esta.
        _diaPasado.value = null
        val d = Disco(raizDisco, t)
        disco = d
        cacheCodigos = null
        _registroMetas.value = leerRegistroMetas(d)
        val sesiones = SesionesDelDia(alcance)
        sesionesDelDia = sesiones
        val escrituras = Escrituras(cliente, t, sesiones) { elegirHorarioForzado ?: elegirHorarioRecordado(d) }
        outbox?.cerrar()
        // Las ops de la migración esperan a la palanca remota (`cargar` la lee y se la pasa): hallazgo 2 del 15-oct.
        UltimaCuenta.anotar(t, preferencias)
        val cola = Outbox(
            archivo = d.archivo("outbox.json"), ventanaAbandonoMs = VENTANA_ABANDONO_MS, alcance = alcance, retenerLegadas = true,
            retenerSwaps = faltaDecidirSwaps(d),
        ) { op ->
            val r = escrituras.ejecutar(op)
            if (r is ResultadoOp.TokenCaido) alCaerElToken(t)
            r
        }
        outbox = cola
        _chat.value?.pararSondeo()   // al cambiar de cuenta, el sondeo de la anterior no sigue
        val chat = ModeloChat(cliente, t, cola, alcance, carpetaAdjuntos = d.archivo(CARPETA_ADJUNTOS_CHAT))
        _chat.value = chat
        palancaLeidaEnSesion = false
        if (enPrimerPlano) chat.empezarSondeo()
        // Las fotos y audios del chat que quedaron en la cola (la app cerrada sin señal) vuelven a su burbuja.
        alcance.launch { chat.cargarAdjuntosDeLaCola() }
        _revision.value = ModeloRevision(cliente, t, cola, alcance, d)
        _fotos.value = ModeloFotos(cliente, t, d)
        val gimnasioCuenta = ModeloGimnasio(cliente, t, d, lanzar = { tarea -> alcance.launch { tarea() } })
        _gimnasio.value = gimnasioCuenta
        _fotosInicio.value = ModeloFotosInicio(cliente, t, d, lanzar = { tarea -> alcance.launch { tarea() } })
        _casa.value = ModeloCasa(cliente, t, d, gimnasioCuenta)
        _finPlan.value = ModeloFinPlan(cliente, t, d)
        _compras.value = ModeloCompras(cliente, t, d)
        _tecnica.value = ModeloTecnica(cliente, t, d, lanzar = { tarea -> alcance.launch { tarea() } })
        _devolucion.value = ModeloDevolucion(cliente, t, d)
        _feedback.value = ModeloFeedback(cliente, t, d)
        _estudios.value = ModeloEstudios(cliente, t, d, ColaEstudios.carpeta(raizSinRespaldo ?: raizDisco, d), lanzar = { tarea -> alcance.launch { tarea() } })
        _wins.value = ModeloWins(cliente, t, d, lanzar = { tarea -> alcance.launch { tarea() } })
        _listaPrevia.value = ModeloListaPrevia(cliente, t, d)
        _progreso.value = ModeloProgreso(cliente, t)
        _guia.value?.cerrar()
        _guia.value = ModeloGuia(cliente, t, cola, d, alcance)
        _suplementacion.value = ModeloSuplementacion(cliente, t, d, alcance)
        _novedades.value = ModeloNovedades(d)
        _documentos.value = ModeloDocumentos(cliente, t, d)
        _salud.value?.cancelarEspera()
        // Salud por cuenta: con el link de otra persona en este teléfono no se sube la salud del dueño (hallazgo 3 del 15-oct).
        _salud.value = ModeloSalud(cliente, t, almacen = AlmacenSaludPorCuenta(preferencias, Disco.huella(t)), alcance = alcance)
        // Los avisos llegan desde el hilo de la cola: los StateFlow se pueden tocar desde cualquier hilo y así el orden se
        // conserva (en iOS se pasa al principal con un Task por aviso).
        alcance.launch {
            _perdidos.value = cola.perdidos().size
            cola.observar(estado = { e -> _estadoGuardado.value = e }, abandonadas = ::alAbandonar, guardadas = ::alGuardar)
        }
    }

    /** F5: «Reintentar» de «No se pudo guardar». */
    suspend fun reintentarPerdidos() {
        val cola = outbox ?: return
        cola.reintentarPerdidos()
        _perdidos.value = cola.perdidos().size
        cola.drenar()
        _perdidos.value = cola.perdidos().size
    }

    /** Lo que el servidor guardó: un mensaje del chat que deduplicó (la fila que ya estaba) saca su burbuja "enviando…". */
    private fun alGuardar(ops: List<OpGuardada>) {
        _guia.value?.alGuardar(ops)
        // Salió el día: si era el de hoy, ya no hay nada sin guardar, y los fallidos viejos de ese día se olvidan (si no,
        // la hidratación no volvería a traer lo del servidor nunca más ese día).
        for (g in ops) {
            if (g.op.kind != AjustesDieta.KIND) continue
            val clave = g.op.dedupeKey ?: continue
            if (clave == AjustesDieta.clave(FechaLocal.hoy())) _ajustesSinGuardar.value = false
            _diaPasado.update { p -> if (p != null && clave == AjustesDieta.clave(p.fecha)) p.copy(sinGuardar = false) else p }
            outbox?.let { cola -> alcance.launch { cola.olvidarFallidos(clave) } }
        }
        for (g in ops) {
            if (g.op.kind != "chat") continue
            val contenido = g.op.payload["contenido"]?.comoTexto ?: continue
            g.respuesta.comoTexto?.let { id -> _chat.value?.confirmar(contenido, id) }
        }
        _chat.value?.alGuardarAdjuntos(ops)
    }

    /**
     * Lo que la cola abandonó (va a fallidos, no se borra). Un mensaje del chat se marca en su burbuja para reintentarlo
     * ("no salió → Reintentar"), como `marcarChatFallido` de la web.
     */
    private fun alAbandonar(ops: List<Operacion>) {
        outbox?.let { cola -> alcance.launch { _perdidos.value = cola.perdidos().size } }
        _guia.value?.alAbandonar(ops)
        // La cola abandonó el día (8 intentos o un rechazo de la base, como el 22023 de un día demasiado grande).
        if (ops.any { it.kind == AjustesDieta.KIND && it.dedupeKey == AjustesDieta.clave(FechaLocal.hoy()) }) _ajustesSinGuardar.value = true
        _diaPasado.update { p -> if (p != null && ops.any { it.kind == AjustesDieta.KIND && it.dedupeKey == AjustesDieta.clave(p.fecha) }) p.copy(sinGuardar = true) else p }
        for (op in ops) {
            if (op.kind != "chat") continue
            op.payload["contenido"]?.comoTexto?.let { _chat.value?.marcarFallido(it) }
        }
        _chat.value?.let { c -> alcance.launch { c.alAbandonarAdjuntos(ops) } }
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

    /** La base dice que el link ya no sirve: se olvida (la cola y la carpeta quedan para el link nuevo de la misma persona). */
    private fun marcarLinkCaido(t: String) {
        if (almacen.leer() == t) almacen.guardar(null)
        preferencias.guardar(CLAVE_TOKEN_INVALIDO, t)
        _chat.value?.pararSondeo()
        _fase.value = Fase.TOKEN_INVALIDO
    }

    private val revisandoCaida = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * F10: con la app abierta, la cola vio que el link dejó de andar. Antes se avisaba «sin conexión» para siempre; ahora se
     * confirma con la base (un `[]` sin error) y se muestra «Este link ya no está activo».
     */
    internal suspend fun alCaerElToken(t: String) {
        if (t != token || _esDemo.value || _fase.value != Fase.LISTO || !revisandoCaida.compareAndSet(false, true)) return
        try {
            val r = cliente.llamar("mypump_get_cliente_info", mapOf("p_token" to ValorJson.Texto(t)))
            val vacia = ((r as? Resultado.Ok)?.valor as? ValorJson.Lista)?.elementos?.isEmpty() == true
            if (!vacia) return
            // La cola corre en su propio hilo: lo que toca la pantalla y las preferencias va en el del modelo (revisión 10/11).
            withContext(alcance.coroutineContext[kotlin.coroutines.ContinuationInterceptor] ?: kotlin.coroutines.EmptyCoroutineContext) {
                if (t == token && !_esDemo.value) marcarLinkCaido(t)
            }
        } finally {
            revisandoCaida.set(false)
        }
    }

    private fun leerCopia(): CopiaOffline? = CopiaOffline.desde(disco?.leer(ARCHIVO_COPIA))

    /**
     * Cuántas cargas completas están en curso. Con la copia guardada la fase pasa a LISTO antes de pedir nada (F2): mientras
     * tanto, volver a la app o a la red no lanza otra carga en paralelo (revisión del 10/11).
     */
    private val cargasEnCurso = java.util.concurrent.atomic.AtomicInteger(0)
    internal val cargando: Boolean get() = cargasEnCurso.get() > 0

    suspend fun cargar() {
        cargasEnCurso.incrementAndGet()
        try {
            cargarSinGuarda()
        } finally {
            cargasEnCurso.decrementAndGet()
        }
    }

    private suspend fun cargarSinGuarda() {
        if (_esDemo.value) return   // la demo no toca la red (y "tirar para actualizar" no la cierra)
        val t = token ?: run {
            _fase.value = Fase.SIN_TOKEN
            return
        }
        // Todo lo que sigue es de ESTE token: si mientras tanto entró otro (un link tocado al abrir la app), lo que vuelva se
        // descarta sin tocar nada (ni el almacén ni la pantalla).
        fun vigente(): Boolean = token == t && !_esDemo.value
        val p = mapOf("p_token" to texto(t))
        // El chat y cuántas veces había traído su última página al empezar: si mientras se carga lo demás la trae otro (el
        // Chat abierto antes de que termine la carga, o su sondeo), al llegar al chat no se pide de nuevo.
        val chatAlEmpezar = _chat.value
        val traidasAlEmpezar = chatAlEmpezar?.ultimasTraidas

        // F2 (auditoría 10/11): con el plan guardado en el teléfono, se muestra ya y se actualiza por detrás. Antes se miraba
        // el logo hasta 20 a 40 segundos con mala señal, aunque el plan estuviera guardado.
        var motorDeLaCopia: ModeloEntreno? = null
        var rutinaDeLaCopia: RutinaActiva? = null
        if (_fase.value == Fase.CARGANDO) {
            leerCopia()?.let { c ->
                aplicar(c, cargarMotor = false)
                _entreno.value?.let { e ->
                    motorDeLaCopia = e
                    rutinaDeLaCopia = e.rutina.value
                    cargaDelMotor = alcance.launch {
                        cargarCatalogo()
                        e.aplicarLegadoDelDisco()
                        e.cargar()
                    }
                }
                _fase.value = Fase.LISTO
            }
        }

        // Sin red o servicio caído: la copia offline, si hay. La cuenta sigue guardada.
        fun sinRespuesta(clase: ErrorRpc.Clase) {
            _ultimaFalla.value = clase
            if (motorDeLaCopia != null || (_fase.value == Fase.LISTO && _info.value != null)) {
                // Ya se está mostrando la copia: solo se avisa que es la guardada.
                _desdeCache.value = true
                _fase.value = Fase.LISTO
                return
            }
            val copia = leerCopia()
            if (copia != null) {
                aplicar(copia)
                _desdeCache.value = true
                _fase.value = Fase.LISTO
            } else {
                _fase.value = Fase.SIN_SERVICIO
            }
        }

        val respuestaInfo = when (val r = cliente.llamar("mypump_get_cliente_info", p)) {
            is Resultado.Falla -> {
                if (!vigente()) return
                sinRespuesta(r.error.clase)
                return
            }
            is Resultado.Ok -> {
                if (!vigente()) return
                // Un 200 que no es una lista (vacío, `null`, un objeto: un proxy, un corte) no dice que el token no sirva: antes
                // cerraba la sesión y dejaba anotado como vencido un token válido.
                if (r.valor !is ValorJson.Lista) {
                    sinRespuesta(ErrorRpc.Clase.TRANSITORIO)
                    return
                }
                r.valor
            }
        }
        _ultimaFalla.value = null
        // `[]` sin error = token inválido o revocado (la base no tira error: devuelve vacío).
        val primera = (respuestaInfo as? ValorJson.Lista)?.elementos?.firstOrNull()
        if (primera == null) {
            marcarLinkCaido(t)
            return
        }
        _info.value = decodificar(primera.aJson(), ClienteInfo::desde)
        // La misma persona con otro link (Mati lo regeneró): lo que quedó en la cola de la carpeta vieja sale con este, con el
        // `drenar()` de más abajo (hallazgo 4).
        // La carpeta, la cola y las fotos se toman juntas antes de esperar: si mientras tanto entra el link de otra persona,
        // lo de esta no puede terminar en la cuenta de esa.
        val discoCuenta = disco
        val colaCuenta = outbox
        val fotosCuenta = _fotos.value
        val gimnasioCuenta = _gimnasio.value
        val fotosInicioCuenta = _fotosInicio.value
        val tecnicaCuenta = _tecnica.value
        val estudiosCuenta = _estudios.value
        val clienteId = _info.value?.clienteId
        if (discoCuenta != null && colaCuenta != null && !clienteId.isNullOrEmpty()) {
            CuentasDelTelefono.anotar(clienteId, discoCuenta)
            CuentasDelTelefono.adoptar(clienteId, discoCuenta, colaCuenta)
            // Los reemplazos de comida que esa carpeta tenía sin decidir vienen con ellas: hasta decidir, la cola los retiene
            // (sin esto, un reemplazo que estaba solo en la carpeta del link viejo se perdía; hallazgo 9).
            if (CuentasDelTelefono.adoptarSwaps(clienteId, discoCuenta)) colaCuenta.retenerSwapsHastaDecidir()
            fotosCuenta?.let { f -> CuentasDelTelefono.adoptarFotos(clienteId, discoCuenta, f) }
            gimnasioCuenta?.let { g -> CuentasDelTelefono.adoptarGimnasio(clienteId, discoCuenta, g) }
            fotosInicioCuenta?.let { f -> CuentasDelTelefono.adoptarFotosInicio(clienteId, discoCuenta, f) }
            tecnicaCuenta?.let { x -> CuentasDelTelefono.adoptarTecnica(clienteId, discoCuenta, x) }
            estudiosCuenta?.let { x -> CuentasDelTelefono.adoptarEstudios(clienteId, discoCuenta, x) }
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
            palancaLeidaEnSesion = true
            _gimnasio.value?.recordarPalanca(it.gimnasioFotos)
            _fotosInicio.value?.recordarPalanca(it.fotosInicio)
            _tecnica.value?.recordarPalanca(it.tecnicaVideo)
            _devolucion.value?.recordarPalanca(it.devolucionSemanal)
            disco?.let { d -> if (elegirHorarioRecordado(d) != it.elegirHorario) d.guardar(ARCHIVO_PALANCA_ELEGIR, ValorJson.Booleano(it.elegirHorario)) }
            _estudios.value?.usarPalanca(it.estudiosApp)
            // La cola B (2.3.0): apagadas (o sin la clave) no se llama a nada nuevo ni queda nada a la vista.
            _finPlan.value?.usarPalanca(it.finPlan)
            _compras.value?.usarPalanca(it.comprasPais)
            _casa.value?.usarPalanca(it.casa && it.gimnasioFotos)
            _wins.value?.recordarPalanca(it.winsApp)
            _listaPrevia.value?.recordarPalanca(it.listaPrevia)
            _revision.value?.recordarPalancaGuiado(it.checkGuiado)
            _documentos.value?.recordarPalanca(it.contratoApp)
            // Con la palanca apagada, lo que la migración dejó directo en la cola tampoco sale (no solo la Fase R).
            outbox?.usarPalanca(it.opsLegadas)
        }
        // Un corte NO es "no tiene plan": lo que no llegó sale de la copia guardada (y la copia no se pisa con un hueco).
        // `null` o `[]` sin error sí es "no tiene" (Mati la desactivó).
        val copia = leerCopia()
        // «Novedades de tu plan»: lo que el teléfono tenía antes de esta carga, por si todavía no hay base.
        val suplAntes = disco?.leer(ModeloSuplementacion.ARCHIVO)
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
        // El servidor dijo que no hay dieta: no hay reemplazos del teléfono que decidir y los de la cola vieja pueden salir.
        // Si la dieta no llegó (red), siguen esperando.
        // El servidor dijo que no hay dieta (ninguna fila): no hay reemplazos que decidir y pueden salir. Si no llegó (red) o llegó
        // una que todavía no se puede usar (Mati la está armando), siguen esperando: soltarlos ahí perdía los que estaban solo
        // en el teléfono cuando la dieta volvía a servir (revisión adversarial del 15-oct, hallazgo 4).
        if (dd is Resultado.Ok && dietaJson == null) outbox?.soltarSwaps()
        if (rutinaJson != null || dietaJson != null || copia != null) {
            disco?.guardar(ARCHIVO_COPIA, CopiaOffline(primera, rutinaJson, dietaJson, System.currentTimeMillis().toDouble()).aValor())
        }
        // Los reemplazos guardados en el teléfono, ANTES de mostrar Dieta (si no, se ven tarde y un reemplazo hecho en ese
        // hueco pisaba el archivo).
        _swaps.value = _dieta.value?.id?.let(::leerSwaps) ?: emptyMap()
        cargarAjustes()
        cargarMarcas()
        _sinRedEn.value = faltaron
        _desdeCache.value = faltaron.isNotEmpty()
        prepararEntreno()
        _fase.value = Fase.LISTO
        if (faltaron.isEmpty()) _cargasConRed.update { it + 1 }
        // El motor que ya arrancó con la copia no se vuelve a cargar, salvo que la rutina haya cambiado: `prepararEntreno` la
        // reemplazó y eso deja el día limpio (sin la sesión ni las series), así que hay que restaurarlo.
        _entreno.value?.takeIf { it !== motorDeLaCopia || it.rutina.value != rutinaDeLaCopia }?.let { e ->
            cargaDelMotor = alcance.launch {
                cargarCatalogo()
                e.aplicarLegadoDelDisco()   // la sesión en curso que trajo la migración, una vez
                e.cargar()
            }
        }

        hidratarDieta()
        if (!vigente()) return
        // Las dos son de hoy y hacen falta para lo consumido de Dieta.
        coroutineScope {
            launch { cargarComidasLibres() }
            launch { hidratarMarcas() }
        }
        if (!vigente()) return
        outbox?.drenar()
        coroutineScope {
            launch { _chat.value?.let { c -> if (c !== chatAlEmpezar || c.ultimasTraidas == traidasAlEmpezar) c.cargar() } }
            launch { _revision.value?.cargarRevision() }
            launch { _fotos.value?.cargar() }
            // «Tu guía»: solo el resumen (no marca `abierto_en`); el `get` es solo al abrir la sección.
            launch { _guia.value?.refrescarResumen() }
            launch {
                _suplementacion.value?.refrescar()
                sincronizarCompras()
            }
            launch { sincronizarFinPlan() }
        }
        if (!vigente()) return
        // «Novedades de tu plan» (palanca `novedades_plan`): lo que llegó contra lo que ya se vio.
        val nov = _novedades.value
        if (_palanca.value.novedadesPlan && nov != null) {
            fun entrada(r: Resultado<*>, fila: ValorJson?): ModeloNovedades.Entrada = when {
                r is Resultado.Falla -> ModeloNovedades.Entrada.NoLlego
                fila == null -> ModeloNovedades.Entrada.Ninguna
                else -> ModeloNovedades.Entrada.Hay(fila.aJson())
            }
            fun guardado(v: ValorJson?): ModeloNovedades.Entrada = v?.let { ModeloNovedades.Entrada.Hay(it.aJson()) } ?: ModeloNovedades.Entrada.NoLlego
            val semilla = Triple(guardado(copia?.rutina), guardado(copia?.dieta),
                suplAntes?.let { ModeloNovedades.Entrada.Hay(it) } ?: ModeloNovedades.Entrada.NoLlego)
            nov.observar(entrada(rr, rutinaJson.takeIf { rr is Resultado.Ok }), entrada(dd, dietaJson.takeIf { dd is Resultado.Ok }),
                _suplementacion.value?.entradaNovedades ?: ModeloNovedades.Entrada.NoLlego, semilla)
        } else if (palancaLeida != null && !palancaLeida.novedadesPlan) {
            // Apagada (leída en ESTA carga, no por un corte): la base no se queda vieja para cuando se vuelva a prender.
            nov?.olvidarBase()
        }
        // Documentos: aparte, así no demora la carga (un error es «sin documentos»). Con `contrato_app` apagada, nada.
        _documentos.value?.let { m -> alcance.launch { m.refrescar() } }
        sincronizarGimnasio()
        sincronizarFotosInicio()
        sincronizarTecnica()
        sincronizarDevolucion()
        _chat.value?.consultarAdjuntos(if (palancaLeidaEnSesion) _palanca.value.chatAdjuntos else null)
        sincronizarFeedback()
        sincronizarEstudios()
        sincronizarWins()
        sincronizarListaPreviaYa()
        _fotos.value?.drenar()
        diaCargado = FechaLocal.hoy()
        anotarCargaCompleta()
        // Salud: sus lecturas, y con la salud del sistema conectada los 7 días y el historial pendiente (sin frenar la carga).
        _salud.value?.let { s -> alcance.launch { s.alAbrir() } }
    }

    /** Volvió la red (el monitor de conectividad): sale lo pendiente y, si se mostraba la copia guardada, se trae todo. */
    suspend fun alVolverLaRed() {
        if (_fase.value != Fase.LISTO || _esDemo.value || token == null || cargando) return
        if (_desdeCache.value) {
            cargar()
            return
        }
        outbox?.drenar()
        _fotos.value?.drenar()
        _gimnasio.value?.takeIf { it.palancaRecordada }?.drenarEnFondo()
        _fotosInicio.value?.takeIf { it.palancaRecordada }?.drenarEnFondo()
        _tecnica.value?.takeIf { it.palancaRecordada }?.drenarEnFondo()
        _estudios.value?.takeIf { it.palanca.value == true }?.drenarEnFondo()
    }

    /** Con la palanca apagada, o sin haberla leído en esta sesión, no se llama a nada: la app es la de siempre. */
    private suspend fun sincronizarEstudios() {
        _estudios.value?.sincronizar()
    }

    /**
     * Tocaron un aviso de Estudios o un link con `?scene=estudios`: la sección, si existe; null = no está disponible (la
     * palanca apagada, la cuenta sin la función, el `get` caído) y se queda en Mis datos. Con la app recién abierta la carga
     * puede no haber terminado: se espera a saberlo, con un tope corto. No llama a nada: solo mira.
     */
    suspend fun estudiosParaAviso(topeMs: Long = 6_000, pasoMs: Long = 200, esperar: suspend (Long) -> Unit = { delay(it) }): ModeloEstudios? {
        var quedan = topeMs
        while (true) {
            if (_esDemo.value || (_fase.value != Fase.CARGANDO && _fase.value != Fase.LISTO)) return null
            val e = _estudios.value
            if (e != null && e.resuelto.value) return e.takeIf { it.estado.value != null }
            if (quedan <= 0) return null
            esperar(pasoMs)
            quedan -= pasoMs
        }
    }

    /** Con las dos palancas apagadas no se llama a nada: la app es la de siempre. */
    private suspend fun sincronizarFeedback() {
        val f = _feedback.value ?: return
        val p = _palanca.value
        if (p.meDuele || p.supleEstado) f.refrescar() else f.apagar()
    }

    /** Con la palanca apagada no se llama a nada: la app es la de siempre. */
    private suspend fun sincronizarTecnica() {
        val x = _tecnica.value ?: return
        if (x.palancaRecordada) {
            x.refrescar()
            x.drenarEnFondo()   // un video grande no frena el resto de la carga
        } else {
            x.apagar()
        }
    }

    /** Solo lectura. Apagada, se borra lo guardado: no queda nada en pantalla. */
    private suspend fun sincronizarDevolucion() {
        val x = _devolucion.value ?: return
        if (x.palancaRecordada) x.refrescar() else x.apagar()
    }

    /** «Récords y logros»: el permiso vigente y lo que quedó en la cola. Con la palanca apagada, ni una llamada. */
    private suspend fun sincronizarWins() {
        val x = _wins.value ?: return
        if (!x.palancaRecordada) return
        x.refrescar()
        x.vaciar()
    }

    /**
     * La lista previa a la videollamada: al cargar, al volver al frente y al abrir Entreno (como mucho un pedido por minuto).
     * Con la palanca apagada no se llama a nada y no queda nada en pantalla. La de la demo es fija.
     */
    suspend fun sincronizarListaPrevia() {
        // Mientras carga no: la palanca recordada puede ser vieja, y `cargar` la mira apenas la lee.
        if (_fase.value != Fase.LISTO) return
        sincronizarListaPreviaYa()
    }

    private suspend fun sincronizarListaPreviaYa() {
        if (_esDemo.value || token == null) return
        val x = _listaPrevia.value ?: return
        if (x.palancaRecordada) x.refrescar() else x.apagar()
    }

    /** Con la palanca apagada no se llama a nada: la app es la de siempre. */
    private suspend fun sincronizarFotosInicio() {
        val f = _fotosInicio.value ?: return
        if (f.palancaRecordada) {
            f.refrescar()
            f.drenarEnFondo()
        } else {
            f.apagar()
        }
    }

    /** Con la palanca apagada no se llama a nada: la app es la de siempre. */
    private suspend fun sincronizarGimnasio() {
        val g = _gimnasio.value ?: return
        val casa = _casa.value
        if (g.palancaRecordada) {
            g.refrescar()
            // Entrenar en casa: junto con el gimnasio, y solo con las dos palancas (`gimnasio_fotos` y `casa`).
            if (casa?.palancaRecordada == true) casa.refrescar() else casa?.apagar()
            g.drenarEnFondo()   // decenas de fotos no frenan el resto de la carga
        } else {
            g.apagar()
            casa?.apagar()
        }
    }

    /** «Tu recorrido»: al cargar la cuenta y al volver a primer plano, solo con la palanca `fin_plan` prendida. */
    private suspend fun sincronizarFinPlan() {
        val f = _finPlan.value ?: return
        if (f.palancaRecordada) f.refrescar()
    }

    /** «Dónde comprarlo»: junto con la suplementación, solo con la palanca `compras_pais` prendida y si hay suplementación. */
    private suspend fun sincronizarCompras() {
        val c = _compras.value ?: return
        if (c.palancaRecordada && _suplementacion.value?.plan?.value != null) c.refrescar()
    }

    /**
     * El modelo pudo nacer sin poder leer el almacén (una falla pasajera del Keystore): parecía que no había cuenta y quedaba
     * en «Entrá con tu link» con la sesión guardada. Al volver se mira de nuevo (gemelo de iOS).
     */
    private suspend fun retomarCuentaGuardada(): Boolean {
        if (_fase.value != Fase.SIN_TOKEN || token != null || _esDemo.value) return false
        val t = almacen.leer()?.takeIf(FormatoToken::valido) ?: return false
        token = t
        prepararCuenta(t)
        _fase.value = Fase.CARGANDO
        cargar()
        return true
    }

    /**
     * Al volver a primer plano (GEN-07): salen las colas, se mira el chat, y si cambió el día se recarga lo que es "de
     * hoy" (comidas libres, el check de la semana). Si se estaba mostrando la copia offline, se intenta traer todo
     * de nuevo.
     */
    suspend fun alVolverAPrimerPlano() {
        if (retomarCuentaGuardada()) return
        if (_fase.value != Fase.LISTO || _esDemo.value || token == null || cargando) return
        if (_desdeCache.value) {
            cargar()
            return
        }
        // Primero lo "de hoy" si cambió el día (lo que se toque ahora tiene que caer en el día nuevo), después las colas.
        val hoy = FechaLocal.hoy()
        if (diaCargado != hoy) {
            cargarAjustes()
            cargarMarcas()
            cargarComidasLibres()
            _revision.value?.cargarRevision()
            diaCargado = hoy
            // Cambió el día: se vuelve a hoy (el que se miraba pudo salir de la ventana del servidor).
            irADia(null)
        }
        // F7 (auditoría 10/11): la rutina y la dieta se pedían solo al arrancar. Un plan publicado hoy no se veía hasta
        // cerrar la app del todo. Ahora se vuelven a pedir pasados unos minutos.
        if (toca(Relectura.PLAN) && !refrescarPlan()) olvidar(Relectura.PLAN)   // sin respuesta: se intenta en la próxima vuelta
        outbox?.drenar()
        // Las marcas de hoy se releen en cada vuelta: las pudo cambiar la web u otro teléfono (DIE-05, D25) y es un pedido
        // chico. F11: lo demás no se relee en cada vuelta (el alumno entra y sale veinte veces en un entreno).
        hidratarMarcas()
        refrescarDiaPasado()
        _chat.value?.sondear()
        _fotos.value?.drenar()
        if (toca(Relectura.GIMNASIO)) {
            sincronizarGimnasio()
            sincronizarTecnica()
            _chat.value?.consultarAdjuntos(if (palancaLeidaEnSesion) _palanca.value.chatAdjuntos else null)
            sincronizarFeedback()
        }
        // La devolución y los estudios llegan con un aviso que trae al alumno: se releen en cada vuelta (un pedido chico
        // cada uno, y solo con su palanca prendida), sin esperar el intervalo.
        sincronizarDevolucion()
        sincronizarEstudios()
        sincronizarFotosInicio()
        if (toca(Relectura.GUIA)) _guia.value?.refrescarResumen()
        sincronizarWins()
        sincronizarListaPreviaYa()
        // La agenda de la entrega, solo con una reserva pendiente (con la guía abierta la consulta su pantalla).
        _guia.value?.agenda?.let { a -> alcance.launch { a.alVolverAPrimerPlano() } }
        // Suplementación: aparte, así no demora lo que sigue (es solo lectura).
        if (toca(Relectura.SUPLEMENTACION)) _suplementacion.value?.let { m ->
            val nov = if (_palanca.value.novedadesPlan) _novedades.value else null
            alcance.launch {
                m.refrescar()
                if (nov != null && _novedades.value === nov) {
                    nov.observar(ModeloNovedades.Entrada.NoLlego, ModeloNovedades.Entrada.NoLlego, m.entradaNovedades, soloConBase = true)
                }
                if (_suplementacion.value === m) sincronizarCompras()
            }
        }
        // «Tu recorrido»: aparte también (es una lectura).
        alcance.launch { sincronizarFinPlan() }
        // Documentos, cada vez: quien firmó en el navegador vuelve y ve «Firmado» (y el aviso se va).
        _documentos.value?.let { m -> alcance.launch { m.refrescar() } }
        if (toca(Relectura.SALUD)) _salud.value?.alVolver()   // con la salud del sistema conectada: 7 días y el historial
        _entreno.value?.alVolverAPrimerPlano()
    }

    // ── F7 y F11: cada cuánto se relee al volver a la app ──

    /** Lo que se relee al volver a la app, con su tiempo mínimo (ms) entre una lectura y la siguiente. */
    enum class Relectura(val cadaMs: Long) {
        PLAN(5 * 60_000L),
        GUIA(10 * 60_000L),
        SUPLEMENTACION(10 * 60_000L),
        GIMNASIO(10 * 60_000L),
        SALUD(60 * 60_000L),
    }

    /** El reloj de las relecturas (ms; las pruebas lo mueven). */
    var relojRelecturas: () -> Long = System::currentTimeMillis
    private val ultimaRelectura = HashMap<Relectura, Long>()

    /** Si ya pasó su tiempo mínimo desde la última vez (y la anota). Una carga completa cuenta como lectura de todo. */
    internal fun toca(r: Relectura): Boolean {
        val ahora = relojRelecturas()
        val u = ultimaRelectura[r]
        if (u != null && ahora - u < r.cadaMs) return false
        ultimaRelectura[r] = ahora
        return true
    }

    private fun olvidar(r: Relectura) {
        ultimaRelectura.remove(r)
    }

    private fun anotarCargaCompleta() {
        val ahora = relojRelecturas()
        for (r in Relectura.entries) ultimaRelectura[r] = ahora
    }

    /**
     * Hay un entrenamiento abierto ahora: arrancó hace menos de 4 horas y no se cerró. El plan no se cambia en el medio
     * (reemplazar la rutina cierra la tarjeta de carga y deja el día limpio); se aplica en la próxima vuelta.
     */
    private val entrenoAbierto: Boolean
        get() {
            val e = _entreno.value ?: return false
            val ini = e.inicioSesion.value ?: return false
            return e.sesionIniciada.value && !e.dia.value.diaFinalizado && relojRelecturas() - ini < 4 * 3600_000.0
        }

    /**
     * F7: la rutina y la dieta de nuevo, sin el resto de la carga. Lo que no llega (red) no toca nada. Devuelve si alguna de
     * las dos respondió.
     */
    internal suspend fun refrescarPlan(): Boolean {
        val t = token ?: return false
        if (_esDemo.value) return false
        val p = mapOf("p_token" to texto(t))
        val conEntreno = entrenoAbierto
        val rr: Resultado<ValorJson>?
        val dd: Resultado<ValorJson>
        coroutineScope {
            val r = if (conEntreno) null else async { cliente.llamar("mypump_get_rutina_activa", p) }
            val d = async { cliente.llamar("mypump_get_dieta_activa", p) }
            rr = r?.await()
            dd = d.await()
        }
        if (token != t || _esDemo.value) return false
        var copia = leerCopia()
        // El entreno pudo empezar mientras viajaba el pedido: entonces la rutina nueva queda solo en la copia guardada.
        val aplicarRutina = !entrenoAbierto
        if (rr is Resultado.Ok) {
            val fila = rr.valor.primeraFila
            val nueva = fila?.let { decodificar(it.aJson(), RutinaActiva::desde) }
            copia = copia?.copy(rutina = fila)
            if (aplicarRutina && nueva != _rutina.value) {
                _rutina.value = nueva
                prepararEntreno()
                // Motor nuevo, o el mismo con la rutina reemplazada (eso deja el día limpio): se restaura.
                _entreno.value?.let { e ->
                    cargaDelMotor = alcance.launch {
                        cargarCatalogo()
                        e.cargar()
                    }
                }
            }
        }
        if (dd is Resultado.Ok) {
            val fila = dd.valor.primeraFila
            val nueva = dietaNormalizada(fila)
            copia = copia?.copy(dieta = fila)
            if (nueva != _dieta.value) {
                _dieta.value = nueva
                _swaps.value = nueva?.id?.let(::leerSwaps) ?: emptyMap()
                cargarAjustes()
                cargarMarcas()
                hidratarDieta()
            }
        }
        // «Novedades de tu plan»: lo releído también se compara con lo ya visto. La rutina que no se aplicó (hay un entreno
        // abierto) no se anuncia todavía: queda para la próxima carga, contra la base.
        if (_palanca.value.novedadesPlan) _novedades.value?.let { nov ->
            fun entrada(r: Resultado<ValorJson>?, vale: Boolean): ModeloNovedades.Entrada =
                if (r !is Resultado.Ok || !vale) ModeloNovedades.Entrada.NoLlego
                else r.valor.primeraFila?.let { ModeloNovedades.Entrada.Hay(it.aJson()) } ?: ModeloNovedades.Entrada.Ninguna
            nov.observar(entrada(rr, aplicarRutina), entrada(dd, true), ModeloNovedades.Entrada.NoLlego, soloConBase = true)
        }
        copia?.let { disco?.guardar(ARCHIVO_COPIA, it.copy(ts = System.currentTimeMillis().toDouble()).aValor()) }
        return rr is Resultado.Ok || dd is Resultado.Ok
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
            catalogoInicial = catalogoVigente, alcance = alcance, sesiones = sesionesDelDia,
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
     * "Tirar para actualizar" en Entreno: como en Dieta, la carga entera, que trae la rutina (si Mati la republicó, se ve).
     * Antes la pantalla recargaba solo lo del motor (la sesión, el historial, los comentarios) y la rutina nueva no aparecía
     * hasta reabrir la app (revisión del 15-oct, hallazgo 6). Espera también lo del motor, como antes.
     */
    suspend fun refrescarEntreno() {
        if (_esDemo.value) {
            _entreno.value?.cargar()
            return
        }
        cargar()
        cargaDelMotor?.join()
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

    /**
     * La semana de revisión ya está completa (el check y las tres fotos): el aviso del domingo se saltea esta semana. Sin
     * cuenta, en la demo o sin el check y las fotos cargados, false: el aviso sale como siempre.
     */
    val semanaDeRevisionCompleta: Boolean
        get() {
            if (_esDemo.value) return false
            val r = _revision.value ?: return false
            val f = _fotos.value ?: return false
            return SemanaRevision.completa(r.checkinEnviado, f.posesDeLaSemana)
        }

    /** El día de revisión del alumno (1 = lunes … 7 = domingo). Sin cuenta o en la demo, el domingo. */
    val diaDeRevision: Int
        get() = if (_esDemo.value) SemanaRevision.DIA_POR_DEFECTO else _revision.value?.revisionDia?.value ?: SemanaRevision.DIA_POR_DEFECTO

    private fun aplicar(c: CopiaOffline, cargarMotor: Boolean = true) {
        _info.value = decodificar(c.info.aJson(), ClienteInfo::desde)
        _rutina.value = c.rutina?.let { decodificar(it.aJson(), RutinaActiva::desde) }
        _dieta.value = dietaNormalizada(c.dieta)
        _dieta.value?.id?.let { id -> _swaps.value = leerSwaps(id) }
        cargarAjustes()
        cargarMarcas()
        prepararEntreno()
        if (cargarMotor) _entreno.value?.let { e -> cargaDelMotor = alcance.launch { e.cargar() } }
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
    fun efectivo(original: Alimento, comidaId: String, opt: Int, idx: Int, tipo: String? = tipoDia): AlimentoEfectivo {
        val e = _dieta.value?.estructura ?: EstructuraDieta()
        return SwapsDeComida.efectivo(original, _swaps.value[clave(comidaId, opt, idx)], comidaId) {
            SwapsDeComida.enPosicion(e, tipo, comidaId, opt, idx)
        }
    }

    /** Confirmar un sustituto (`confirmSwap`): se guarda anclado y sale por la cola. */
    suspend fun sustituir(original: Alimento, sustituto: ValorJson, comidaId: String, opt: Int, idx: Int) {
        val dietaId = _dieta.value?.id ?: return
        val k = clave(comidaId, opt, idx)
        // Sin NaN ni infinito: en memoria como queda en el archivo y en la cola (null, como `JSON.stringify`).
        val anclado = SwapsDeComida.conAncla(sustituto, original).sinNoFinitos
        anotarSwapTocado(k)
        _swaps.update { it + (k to SwapLocal(alimentoJson(original), anclado)) }
        guardarSwaps()
        outbox?.encolar(
            "swap",
            ValorJson.objeto(
                "dietaId" to texto(dietaId), "comidaId" to texto(comidaId), "optIdx" to numero(opt), "foodIdx" to numero(idx), "food" to anclado,
            ),
            k,
        )
        planCambio(comidaId, opt, idx)
    }

    /** Volver al alimento del plan. Comparte clave con el swap: si todavía no había salido, lo reemplaza en la cola. */
    suspend fun revertir(comidaId: String, opt: Int, idx: Int) {
        val dietaId = _dieta.value?.id ?: return
        val k = clave(comidaId, opt, idx)
        anotarSwapTocado(k)
        _swaps.update { it - k }
        guardarSwaps()
        outbox?.encolar(
            "swap_del",
            ValorJson.objeto("dietaId" to texto(dietaId), "comidaId" to texto(comidaId), "optIdx" to numero(opt), "foodIdx" to numero(idx)),
            k,
        )
        planCambio(comidaId, opt, idx)
    }

    // ── Ajustes de porciones del día (feedback del 20-oct) ──

    /** Los de hoy: si cambió el día con la app abierta, ninguno. */
    val ajustesDeHoy: Map<String, AjusteComida>
        get() = if (fechaAjustes == FechaLocal.hoy()) _ajustes.value else emptyMap()

    /** Al cargar la dieta (y al cambiar de día): lo del teléfono, si es de hoy y de esta dieta. */
    internal fun cargarAjustes() {
        val hoy = FechaLocal.hoy()
        fechaAjustes = hoy
        cargarRecientes()
        val g = _dieta.value?.id?.let { id -> disco?.leer(AjustesDieta.archivo(id)) }?.let(ValorJson::desde)
        _ajustes.value = if (g == null || g["fecha"]?.comoTexto != hoy) emptyMap()
        else AjustesDieta.comidasDesde(g["comidas"]).orEmpty().filterValues { !it.neutro }
    }

    /**
     * Las comidas de hoy como las ve el cliente: la opción elegida ([opciones], si no la del ajuste, si no A) y los
     * reemplazos. Es lo que necesita la cuenta del día.
     */
    fun comidasParaAjustar(opciones: Map<String, Int>): List<AjustePorciones.ComidaDelDia> =
        _diaPasado.value?.let { comidasVistaParaAjustar(it, opciones) } ?: comidasDeHoyParaAjustar(opciones)

    /** Las de hoy, se esté mirando el día que se esté mirando (lo que sale a la cola para hoy). */
    internal fun comidasDeHoyParaAjustar(opciones: Map<String, Int>): List<AjustePorciones.ComidaDelDia> =
        comidasAjustables(comidasDelDia, ajustesDeHoy, tipoDia, opciones)

    internal fun comidasAjustables(
        comidas: List<Comida>,
        ajustes: Map<String, AjusteComida>,
        tipo: String?,
        opciones: Map<String, Int>,
    ): List<AjustePorciones.ComidaDelDia> = comidas.map { c ->
        val elegida = opciones[c.id] ?: ajustes[c.id]?.opcion ?: 0
        val o = if (c.opciones.isEmpty()) 0 else elegida.coerceIn(0, c.opciones.size - 1)
        val alimentos = c.opciones.getOrNull(o)?.alimentos?.mapIndexed { i, a -> efectivo(a, c.id, o, i, tipo).alimento } ?: emptyList()
        AjustePorciones.ComidaDelDia(c.id, c.nombre ?: "", o, alimentos)
    }

    /** El día con los ajustes del día a la vista aplicados (lo que dibuja Dieta). */
    fun diaAjustado(opciones: Map<String, Int>): Map<String, AjustePorciones.ComidaAjustada> =
        AjustePorciones.dia(comidasParaAjustar(opciones), ajustesVista)

    /**
     * Cambia (o saca, con null o un ajuste neutro) el ajuste de una comida, lo guarda y manda el día entero. Cada cantidad
     * a mano queda anclada al alimento que se veía (si Mati vuelve a publicar con otro alimento ahí, no vale). En la demo
     * queda en memoria.
     */
    suspend fun ajustar(comidaId: String, ajuste: AjusteComida?, opciones: Map<String, Int>, fecha: String? = null) {
        // La hoja era de otro día (medianoche, o se volvió a hoy): no guarda en una fecha que no es la que mostraba.
        if (fecha != null && fecha != fechaVista) return
        if (_diaPasado.value != null) ajustarPasado(comidaId, ajuste, opciones) else ajustarHoy(comidaId, ajuste, opciones)
    }

    internal suspend fun ajustarHoy(comidaId: String, ajuste: AjusteComida?, opciones: Map<String, Int>) {
        if (fechaAjustes != FechaLocal.hoy()) cargarAjustes()
        opcionesVistas = opcionesVistas + opciones
        val anclado = ajuste?.let { a -> comidasDeHoyParaAjustar(opcionesVistas).firstOrNull { it.id == comidaId }?.let { AjustePorciones.anclar(a, it) } ?: a }
        val actuales = _ajustes.value
        val nuevos = if (anclado != null && !anclado.neutro) actuales + (comidaId to anclado) else actuales - comidaId
        if (nuevos == actuales) return
        ordenAjustes.incrementAndGet()
        _ajustes.value = nuevos
        seguirTildes(comidaId, actuales[comidaId]?.agregados.orEmpty(), nuevos[comidaId]?.agregados.orEmpty())
        val id = _dieta.value?.id
        if (!_esDemo.value && id != null) {
            disco?.guardar(AjustesDieta.archivo(id), AjustesDieta.guardados(fechaAjustes, nuevos))
            encolarAjustes(opciones)
        }
        // «Hoy no la como» sobre una comida marcada: la marca se va (D25: no se come, no se marca ni cuenta). Al final: la
        // espera de la cola, entre el ajuste en memoria y el del disco, dejaba que una carga leyera el ajuste viejo.
        if (ajustesDeHoy[comidaId]?.omitida == true && marcasDeHoy[comidaId] != null) marcarHoy(comidaId, null, 0)
    }

    /**
     * Un reemplazo (o volver al alimento del plan) cambia el alimento de esa posición: la cantidad puesta a mano era del
     * anterior y en otra unidad (60 g de avena no son 60 rebanadas de pan), así que se descarta. Con otros ajustes en el
     * día, el resumen que ve Mati se rehace igual (cambiaron las kcal del plan).
     */
    private suspend fun planCambio(comidaId: String, opt: Int, idx: Int) {
        val a = ajustesDeHoy[comidaId]
        val k = idx.toString()
        if (a != null && a.opcion == opt && a.cantidades[k] != null) {
            ajustarHoy(comidaId, a.copy(cantidades = a.cantidades - k, anclas = a.anclas - k), mapOf(comidaId to opt))
        } else if (ajustesDeHoy.isNotEmpty() && !_esDemo.value) {
            encolarAjustes(emptyMap())
        }
    }

    /** Otra opción a la vista en una comida sin ajuste: el resumen del día (si hay ajustes) se rehace con ella. */
    suspend fun verOpcion(comidaId: String, opcion: Int) {
        if (_diaPasado.value != null) {
            verOpcionPasado(comidaId, opcion)
            return
        }
        opcionesVistas = opcionesVistas + (comidaId to opcion)
        if (ajustesDeHoy.isNotEmpty() && !_esDemo.value) encolarAjustes(emptyMap())
    }

    /** El día entero a la cola (una op por día: la última gana). Con el resumen por comida para que Mati lo lea sin la app. */
    private suspend fun encolarAjustes(opciones: Map<String, Int>) {
        encolarDia(fechaAjustes, _ajustes.value, tipoDia, comidasDeHoyParaAjustar(opcionesVistas + opciones))
    }

    /** Un día entero a la cola (hoy o un día anterior: la clave lleva la fecha). */
    internal suspend fun encolarDia(fecha: String, ajustes: Map<String, AjusteComida>, tipo: String?, comidas: List<AjustePorciones.ComidaDelDia>) {
        val dieta = _dieta.value ?: return
        val cola = outbox ?: return
        val dia = AjustePorciones.dia(comidas, ajustes)
        var plan = 0.0
        var hoy = 0.0
        val resumen = comidas.mapNotNull { c ->
            val d = dia[c.id] ?: return@mapNotNull null
            plan += d.kcalPlan
            hoy += d.kcal
            val renglon = linkedMapOf(
                "comida_id" to texto(c.id), "nombre" to texto(c.nombre), "kcal_plan" to numero(d.kcalPlan),
                "kcal_dia" to numero(d.kcal), "omitida" to ValorJson.Booleano(d.omitida),
            )
            // 2.0.3 (D1): lo que sumó a la comida, si sumó algo y la come (`kcal_dia` ya lo incluye).
            val agregados = if (d.omitida) emptyList() else AgregadosComida.resumen(ajustes[c.id])
            if (agregados.isNotEmpty()) renglon["agregados"] = ValorJson.Lista(agregados)
            ValorJson.Objeto(renglon)
        }
        val vacio = ajustes.isEmpty()
        val payload = ValorJson.objeto(
            "fecha" to texto(fecha), "dietaId" to texto(dieta.id), "tipoDia" to (tipo?.let(::texto) ?: ValorJson.Nulo),
            "ajustes" to AjustesDieta.aValor(ajustes), "resumen" to (if (vacio) ValorJson.Nulo else ValorJson.Lista(resumen)),
            "kcalPlan" to (if (vacio) ValorJson.Nulo else numero(plan)), "kcalDia" to (if (vacio) ValorJson.Nulo else numero(hoy)),
        ).sinNoFinitos
        cola.encolar(AjustesDieta.KIND, payload, AjustesDieta.clave(fecha))
    }

    /**
     * Al hidratar la dieta: lo que tiene el servidor para hoy, salvo que haya un cambio del teléfono que todavía no salió
     * (ese gana). Si el servidor no tiene nada y el teléfono sí (la migración se aplicó después, o salió sin tabla), se
     * sube. Una fila de otra dieta no se mezcla.
     */
    private suspend fun hidratarAjustes(t: String, dieta: DietaActiva, vigente: () -> Boolean) {
        val hoy = FechaLocal.hoy()
        val cola = outbox ?: return
        // Lo que estaba en la cola y lo que el cliente toque mientras se espera al servidor ganan: la cola manda al toque y
        // el cambio puede llegar antes que la respuesta, que entonces es una foto vieja (revisión del 20-oct: se perdía el
        // cambio y el siguiente borraba también lo del servidor).
        val antes = ordenAjustes.get()
        val pendienteAntes = cola.pendientesPorClave()[AjustesDieta.clave(hoy)] != null
        // El aviso de «no se pudo guardar» sale de la cola, no del servidor: se corrige aunque no haya red (y se apaga el de
        // ayer al pasar la medianoche con la app abierta).
        val fallidoAntes = cola.fallidos().any { it.op.kind == AjustesDieta.KIND && it.op.dedupeKey == AjustesDieta.clave(hoy) }
        if (vigente()) _ajustesSinGuardar.value = fallidoAntes
        val r = cliente.llamar("mypump_get_ajustes_dieta", mapOf("p_token" to texto(t), "p_desde" to texto(hoy), "p_hasta" to texto(hoy)))
        if (!vigente()) return
        val filas = ((r as? Resultado.Ok)?.valor as? ValorJson.Lista)?.elementos ?: return
        val pendiente = cola.pendientesPorClave()[AjustesDieta.clave(hoy)] != null
        // Un día que no se pudo guardar (la base lo rechazó): la fila del servidor es vieja y pisaría lo del teléfono.
        val fallido = cola.fallidos().any { it.op.kind == AjustesDieta.KIND && it.op.dedupeKey == AjustesDieta.clave(hoy) }
        if (vigente()) _ajustesSinGuardar.value = fallido
        if (!vigente() || pendienteAntes || pendiente || fallido || ordenAjustes.get() != antes) return
        if (fechaAjustes != hoy) cargarAjustes()
        val remota = filas.firstOrNull { it["fecha"]?.comoTexto == hoy }
        if (remota != null) {
            if ((remota["dieta_id"]?.comoTexto ?: dieta.id) != dieta.id) return
            val validas = AjustesDieta.comidasDesde(remota["ajustes"])?.filterValues { !it.neutro } ?: return
            if (validas == _ajustes.value) return
            val previos = _ajustes.value
            _ajustes.value = validas
            for (id in previos.keys + validas.keys) seguirTildes(id, previos[id]?.agregados.orEmpty(), validas[id]?.agregados.orEmpty(), delUsuario = false)
            disco?.guardar(AjustesDieta.archivo(dieta.id), AjustesDieta.guardados(hoy, validas))
        } else if (_ajustes.value.isNotEmpty()) {
            encolarAjustes(emptyMap())
        }
    }

    // ── Alimentos agregados a una comida (2.0.3, D1) ──
    // Van dentro del ajuste de esa comida y de ese día (AjusteComida.agregados), así que viajan con el resto del ajuste:
    // en el teléfono, por la cola (`ajustes_dieta`, una op por día) y en `mypump_ajustes_dieta`. Gemelo de AgregadosDieta.swift.

    /** Los recientes del teléfono (de cualquier día). La demo no tiene carpeta: los suyos duran hasta la próxima carga. */
    private fun cargarRecientes() {
        val v = disco?.leer(ARCHIVO_RECIENTES)?.let(ValorJson::desde) as? ValorJson.Lista
        _agregadosRecientes.value = v?.elementos.orEmpty().mapNotNull { AlimentoAgregado.desde(it) }
    }

    // ── Código de barras (2.1, S3) ──
    // Con el número que leyó el escáner se pregunta a Open Food Facts (pública, gratis y sin clave; solo viaja el código, sin
    // token ni nada de la cuenta) y la respuesta se lleva a un alimento con [CodigoBarras.leer]. Lo buscado queda en el
    // teléfono (`codigos_barras.json`, por cuenta): un producto de todos los días no vuelve a la red y se encuentra sin señal.
    // Gemelo de BarrasDieta.swift.

    /** Lo que pasó al buscar: una lectura (de la caché o de Open Food Facts) o que no hubo respuesta. */
    sealed interface BusquedaCodigo {
        data class Leido(val lectura: CodigoBarras.Lectura) : BusquedaCodigo
        data object SinRed : BusquedaCodigo
    }

    /** La versión de la app para el User-Agent que pide Open Food Facts (la pone el ViewModel). */
    var versionApp: String = "2"

    /** El doble de Open Food Facts de las pruebas; sin él, va por el transporte del cliente. */
    var transporteBarras: Transporte? = null

    private var cacheCodigos: CacheCodigos? = null

    private fun cacheCodigos(): CacheCodigos =
        cacheCodigos ?: CacheCodigos.desde(disco?.leer(ARCHIVO_CODIGOS)?.let { ValorJson.desde(it) }).also { cacheCodigos = it }

    private fun guardarCodigos(c: CacheCodigos) {
        cacheCodigos = c
        if (!_esDemo.value) disco?.guardar(ARCHIVO_CODIGOS, c.aValor())
    }

    /**
     * Busca un código ya normalizado ([CodigoBarras.normalizar]). Sin respuesta (sin señal, timeout, Open Food Facts caído)
     * es [BusquedaCodigo.SinRed] y no se guarda nada. En la demo no se pregunta a nadie: no está (con las salidas de siempre).
     */
    suspend fun buscarCodigo(codigo: String): BusquedaCodigo {
        if (_esDemo.value) return BusquedaCodigo.Leido(CodigoBarras.Lectura.NoEncontrado)
        cacheCodigos().vigente(codigo, System.currentTimeMillis())?.let { return BusquedaCodigo.Leido(it) }
        val pedido = Pedido(
            url = CodigoBarras.url(codigo), metodo = "GET",
            cabeceras = mapOf("User-Agent" to CodigoBarras.agenteUsuario(versionApp, "Android"), "Accept" to "application/json"),
            cuerpo = null, esperaMs = CodigoBarras.ESPERA_MS,
        )
        val r = try {
            (transporteBarras ?: cliente.transporte).enviar(pedido)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            return BusquedaCodigo.SinRed
        }
        // Un producto que no está contesta 404 con `status: 0`; 429, 5xx o una página de error no dicen nada del producto.
        if (r.status !in 200..299 && r.status != 404) return BusquedaCodigo.SinRed
        val j = withContext(Dispatchers.Default) { runCatching { ValorJson.parsear(r.cuerpo.toString(Charsets.UTF_8)) }.getOrNull() }
            ?: return BusquedaCodigo.SinRed
        // Sin `status` 0 o 1 (un proxy, otra API) no se sabe nada del producto: no se guarda.
        val st = j["status"]?.comoNumero
        if (st != 0.0 && st != 1.0) return BusquedaCodigo.SinRed
        val lectura = CodigoBarras.leer(j, codigo)
        val c = cacheCodigos()
        c.guardar(codigo, lectura, System.currentTimeMillis())
        guardarCodigos(c)
        return BusquedaCodigo.Leido(lectura)
    }

    /** Un alimento propio creado desde un código que Open Food Facts no tenía: la próxima vez que se escanee, aparece el suyo. */
    fun recordarCodigoPropio(codigo: String, c: AgregadosComida.Candidato) {
        val cc = cacheCodigos()
        cc.guardar(
            codigo,
            CodigoBarras.Lectura.Encontrado(CodigoBarras.Producto(codigo, c.nombre, c.por100, c.unidad, c.gramosPorUnidad, propio = true)),
            System.currentTimeMillis(),
        )
        guardarCodigos(cc)
    }

    /** Los propios creados desde un código que se borraron o se editaron dejan de aparecer al escanear. */
    private fun conciliarCodigosPropios() {
        val c = cacheCodigos()
        if (c.conciliarPropios(_alimentosPropios.value)) guardarCodigos(c)
    }

    /** Lo último agregado va primero (un mismo alimento una sola vez, con la última cantidad). */
    fun recordarReciente(a: AlimentoAgregado) {
        val r = listOf(a) + _agregadosRecientes.value.filter { it.nombre.lowercase() != a.nombre.lowercase() }
        _agregadosRecientes.value = r.take(MAXIMO_RECIENTES)
        if (!_esDemo.value) disco?.guardar(ARCHIVO_RECIENTES, ValorJson.Lista(_agregadosRecientes.value.map { it.aValor() }))
    }

    /**
     * Saca un agregado de una comida de hoy (los tildes de «Comí» los corre [ajustar], por `_ts`). Se busca por `_ts` en el
     * ajuste de AHORA: dos toques seguidos en «Sacar» no borran otro.
     */
    suspend fun borrarAgregado(comidaId: String, ts: Long, opciones: Map<String, Int>) {
        val a = ajustesVista[comidaId] ?: return
        if (a.agregados.none { it.ts == ts }) return
        ajustar(comidaId, a.copy(agregados = a.agregados.filter { it.ts != ts }), opciones)
    }

    /**
     * Cambiaron los agregados de una comida marcada «Comí» (se borró uno, «Volver al plan», llegó otro día del servidor):
     * sus tildes siguen a cada agregado por `_ts`. Va antes de cualquier espera (la marca cambia en memoria al toque), así dos
     * cambios seguidos no leen una marca vieja.
     * [delUsuario] false (la hidratación): se remapea solo en memoria y en disco, sin encolar ni contar como un toque, así
     * [hidratarMarcas] trae igual la marca del servidor (la de otro teléfono, más nueva, no se pisa con la vieja de este). Si
     * ya hay una op de marca de esa comida en la cola, esa es lo último del cliente y se corrige en la cola.
     */
    private suspend fun seguirTildes(comidaId: String, antes: List<AlimentoAgregado>, despues: List<AlimentoAgregado>, delUsuario: Boolean = true) {
        if (antes.map { it.ts } == despues.map { it.ts }) return
        val m = marcasDeHoy[comidaId] ?: return
        if (m.estado != MarcaComida.Estado.COMIDO) return
        val c = comidasDelDia.firstOrNull { it.id == comidaId } ?: return
        val o = ConsumoDelDia.opcionDeLaMarca(c, m) ?: 0
        val n = c.opciones.getOrNull(o)?.alimentos?.size ?: 0
        val excluidos = AgregadosComida.excluidosTrasCambio(m.excluidos, n, antes.map { it.ts }, despues.map { it.ts })
        if (excluidos == m.excluidos) return
        val nueva = MarcaComida(m.opcion, MarcaComida.Estado.COMIDO, excluidos)
        if (!delUsuario && !_esDemo.value) {
            val fecha = fechaMarcas
            val enCola = outbox?.pendientesPorClave()?.containsKey(MarcasComidas.clave(fecha, comidaId)) == true
            // Mientras se miraba la cola la marca pudo cambiar (un toque): ese toque ya encoló lo suyo.
            if (_marcas.value[comidaId] != m) return
            if (!enCola) {
                val todas = _marcas.value + (comidaId to nueva)
                _marcas.value = todas
                disco?.guardar(MarcasComidas.ARCHIVO, MarcasComidas.guardadas(fecha, todas))
                return
            }
        }
        cambiarMarca(comidaId, nueva, m.opcion)
    }

    // ── «Comí» / «Salté» y lo consumido (D25) ──

    /** Las de hoy: si cambió el día con la app abierta, ninguna. */
    val marcasDeHoy: Map<String, MarcaComida>
        get() = if (fechaMarcas == FechaLocal.hoy()) _marcas.value else emptyMap()

    /** Al cargar (y al cambiar de día): las del teléfono, si son de hoy. La demo no tiene carpeta: empieza sin marcas. */
    internal fun cargarMarcas() {
        val hoy = FechaLocal.hoy()
        fechaMarcas = hoy
        val g = disco?.leer(MarcasComidas.ARCHIVO)?.let(ValorJson::desde)
        _marcas.value = if (g == null || g["fecha"]?.comoTexto != hoy) emptyMap() else MarcasComidas.desde(g["marcas"])
    }

    /**
     * Lo comido hoy con las opciones que se ven (las comidas marcadas «Comí» se cuentan con la de la marca), los
     * reemplazos, los ajustes de hoy y las comidas libres.
     */
    fun consumo(opciones: Map<String, Int>): ConsumoDelDia.Consumo =
        ConsumoDelDia.calcular(comidasVista, marcasVista, libresVista, ajustesVista, opciones) { cid, o, i, a ->
            efectivoVista(a, cid, o, i).alimento
        }

    /**
     * «Comí» o «Salté» con la opción [opcion] (la que se ve), o null para desmarcar. «Comí» arranca con todo tildado.
     * Optimista: se ve al toque, queda en el teléfono y sale por la cola (sin red, cuando vuelva). En la demo, en memoria.
     */
    suspend fun marcar(comidaId: String, estado: MarcaComida.Estado?, opcion: Int) {
        if (_diaPasado.value != null) marcarPasado(comidaId, estado, opcion) else marcarHoy(comidaId, estado, opcion)
    }

    private suspend fun marcarHoy(comidaId: String, estado: MarcaComida.Estado?, opcion: Int) {
        if (fechaMarcas != FechaLocal.hoy()) cargarMarcas()
        val c = comidasDelDia.firstOrNull { it.id == comidaId } ?: return
        val o = if (c.opciones.isEmpty()) 0 else opcion.coerceIn(0, c.opciones.size - 1)
        val nombre = ConsumoDelDia.nombreOpcion(c, o)
        cambiarMarca(comidaId, estado?.let { MarcaComida(nombre, it) }, nombre)
    }

    /**
     * Consumo parcial (DIE-06): destilda (o vuelve a tildar) un alimento de una comida marcada «Comí». El índice es de la
     * opción de la marca: Dieta solo muestra los tildes mirando esa opción.
     */
    suspend fun alternarAlimento(comidaId: String, idx: Int) {
        if (_diaPasado.value != null) {
            alternarAlimentoPasado(comidaId, idx)
            return
        }
        if (fechaMarcas != FechaLocal.hoy()) cargarMarcas()
        val m = _marcas.value[comidaId] ?: return
        if (idx < 0 || m.estado != MarcaComida.Estado.COMIDO) return
        val excluidos = if (idx in m.excluidos) m.excluidos - idx else m.excluidos + idx
        cambiarMarca(comidaId, MarcaComida(m.opcion, MarcaComida.Estado.COMIDO, excluidos), m.opcion)
    }

    internal suspend fun cambiarMarca(comidaId: String, nueva: MarcaComida?, opcionAlDesmarcar: String?) {
        val actuales = _marcas.value
        if (nueva == actuales[comidaId]) return
        ordenMarcas[comidaId] = contadorMarcas.incrementAndGet()
        val todas = if (nueva != null) actuales + (comidaId to nueva) else actuales - comidaId
        _marcas.value = todas
        if (_esDemo.value) return
        val cola = outbox ?: return
        val fecha = fechaMarcas
        disco?.guardar(MarcasComidas.ARCHIVO, MarcasComidas.guardadas(fecha, todas))
        cola.encolar(MarcasComidas.KIND, MarcasComidas.payload(fecha, comidaId, nueva, opcionAlDesmarcar), MarcasComidas.clave(fecha, comidaId))
    }

    /**
     * Lo que dice el servidor de hoy, con dos excepciones por comida: lo que está en la cola sin salir gana (se lee del
     * payload, como la web: es lo último que decidió el cliente) y lo que se tocó o estaba en la cola mientras viajaba la
     * lectura queda como está en el teléfono (la respuesta puede ser una foto de antes de ese cambio). Sin red, nada cambia.
     */
    internal suspend fun hidratarMarcas() {
        val t = token ?: return
        if (_esDemo.value || _dieta.value == null) return
        val cola = outbox ?: return
        val hoy = FechaLocal.hoy()
        if (fechaMarcas != hoy) cargarMarcas()
        val prefijo = MarcasComidas.clave(hoy, "")
        suspend fun enCola(): Map<String, Operacion> =
            cola.pendientesPorClave().filterKeys { it.startsWith(prefijo) }.mapKeys { it.key.removePrefix(prefijo) }
        val antes = HashMap(ordenMarcas)
        val enColaAntes = enCola()
        val r = cliente.filas("mypump_get_comidas_marcadas", mapOf("p_token" to texto(t), "p_fecha" to texto(hoy)), ComidaMarcada::desde)
        if (!deLaCuenta(t) || fechaMarcas != hoy) return
        val filas = r.valorONull() ?: return
        val enColaAhora = enCola()
        if (!deLaCuenta(t) || fechaMarcas != hoy) return
        val locales = _marcas.value
        val nuevas = ConsumoDelDia.marcas(filas).toMutableMap()
        val tocadas = ordenMarcas.filter { (id, n) -> antes[id] != n }.keys
        for (id in enColaAntes.keys + tocadas) {
            val m = locales[id]
            if (m != null) nuevas[id] = m else nuevas.remove(id)
        }
        for ((id, op) in enColaAhora) {
            val m = MarcasComidas.desdePayload(op.payload)
            if (m != null) nuevas[id] = m else nuevas.remove(id)
        }
        if (nuevas == locales) return
        _marcas.value = nuevas
        disco?.guardar(MarcasComidas.ARCHIVO, MarcasComidas.guardadas(hoy, nuevas))
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
                // Se creó en la cuenta de `t`. Si mientras tanto entró otra (o la demo), no se suma a la de ahora.
                if (deLaCuenta(t)) sumarPropio(a)
                Resultado.Ok(a)
            }
        }
    }

    /**
     * Lo que vuelve del servidor es de la cuenta de [t]: como el `vigente()` de [hidratarDieta] (hallazgo 10), si mientras se
     * esperaba entró el link de otra persona o la demo, no se aplica. Antes las comidas libres y el alimento propio de A
     * terminaban en B (y un borrado que fallaba le volvía a poner a B las comidas de A).
     */
    internal fun deLaCuenta(t: String): Boolean = token == t && !_esDemo.value

    // ── Comidas libres ──

    /** `loadComidasLibres`: las del día local. Sin cuenta (demo) no hay. */
    suspend fun cargarComidasLibres() {
        val t = token ?: run {
            _comidasLibres.value = emptyList()
            return
        }
        val filas = cliente.filas("mypump_get_comidas_libres", mapOf("p_token" to texto(t), "p_fecha" to texto(FechaLocal.hoy())), ComidaLibre::desde)
        if (!deLaCuenta(t)) return
        filas.valorONull()?.let { _comidasLibres.value = it }
    }

    /** `guardarComidaLibre`: directo, no por la cola (como la web), con la fecha local. */
    suspend fun crearComidaLibre(d: ComidaLibreNueva.Datos, fecha: String? = null): Resultado<ComidaLibre> = crearComidaLibreEn(fecha ?: fechaVista, d)

    /** La crea en [fecha] y la suma a esa caja (hoy o el día pasado que se siga mirando). */
    internal suspend fun crearComidaLibreEn(fecha: String, d: ComidaLibreNueva.Datos): Resultado<ComidaLibre> {
        val t = token ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 0, "SIN_CUENTA", "demo"))
        val p = mapOf(
            "p_token" to texto(t), "p_fecha" to texto(fecha), "p_hora" to (d.hora?.let { texto(it) } ?: ValorJson.Nulo),
            "p_descripcion" to texto(d.descripcion), "p_kcal" to numero(d.kcal), "p_prot" to numero(d.prot),
            "p_carb" to numero(d.carb), "p_fat" to numero(d.fat), "p_detalle" to (d.detalle ?: ValorJson.Nulo),
        )
        return when (val r = cliente.filas("mypump_crear_comida_libre", p, ComidaLibre::desde)) {
            is Resultado.Falla -> r
            is Resultado.Ok -> {
                val c = r.valor.firstOrNull()
                    ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_FILA", "mypump_crear_comida_libre: vacío"))
                // Quedó guardada en la cuenta de `t`: en la lista de otra no va.
                if (deLaCuenta(t)) {
                    if (fecha == _diaPasado.value?.fecha) {
                        ordenDiaPasado += 1
                        _diaPasado.update { p -> p?.copy(libres = p.libres + c) }
                    } else if (fecha == FechaLocal.hoy()) _comidasLibres.update { it + c }
                }
                Resultado.Ok(c)
            }
        }
    }

    /** `borrarComidaLibre`: optimista; si el servidor no contesta bien, vuelve a aparecer. */
    suspend fun borrarComidaLibre(id: String): Boolean {
        if (_diaPasado.value?.libres?.any { it.id == id } == true) return borrarComidaLibrePasada(id)
        val previas = _comidasLibres.value
        _comidasLibres.update { lista -> lista.filterNot { it.id == id } }
        val t = token ?: return true
        if (cliente.llamar("mypump_borrar_comida_libre", mapOf("p_token" to texto(t), "p_id" to texto(id))) is Resultado.Falla) {
            // Volver atrás solo en la misma cuenta: con otra en el medio, `previas` son las comidas de la anterior.
            if (deLaCuenta(t)) _comidasLibres.value = previas
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
        var editado = false
        _alimentosPropios.update { lista ->
            val i = lista.indexOfFirst { it.nombre.lowercase() == a.nombre.lowercase() }
            editado = i >= 0
            if (i >= 0) lista.toMutableList().also { it[i] = a } else lista + a
        }
        // Editado: si salió de un código con otros valores, el escaneo deja de traer el viejo.
        if (editado) conciliarCodigosPropios()
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

    /**
     * Preferencias, alimentos propios y swaps del servidor (hydrateSwapsAndCustomFoodsFromBackend). Todo es de ESTA cuenta y
     * de ESTA dieta: si mientras se espera al servidor entra otro link (o llega otra dieta), lo que vuelve se descarta. Antes
     * se aplicaba igual y lo de A quedaba en B: sus preferencias, sus alimentos propios y sus reemplazos, en memoria, en la
     * carpeta de B y en su cola (revisión del 15-oct, hallazgo 10). La cola y la carpeta son las de la cuenta del principio,
     * aunque cambie en el medio.
     */
    internal suspend fun hidratarDieta() {
        val t = token ?: return
        val dieta = _dieta.value ?: return
        val d = disco ?: return
        val cola = outbox ?: return
        fun vigente(): Boolean = token == t && !_esDemo.value && _dieta.value?.id == dieta.id
        val p = mapOf("p_token" to texto(t))
        val prefs = cliente.filas("mypump_get_cliente_prefs", p, PreferenciasCliente::desde)
        if (!vigente()) return
        prefs.valorONull()?.let { _excluir.value = it.firstOrNull()?.excluir ?: emptyList() }
        val propios = cliente.filas("mypump_get_custom_foods", p, AlimentoPropio::desde)
        if (!vigente()) return
        propios.valorONull()?.let {
            _alimentosPropios.value = it
            conciliarCodigosPropios()
        }

        // Lo que el cliente toque desde acá (mientras se espera la respuesta) le gana a lo que traiga el servidor.
        val desde = ordenSwaps.get()
        val remotos = cliente.filas("mypump_get_food_swaps", mapOf("p_token" to texto(t), "p_dieta_id" to texto(dieta.id)), FoodSwap::desde)
            .valorONull()
        val pendientes = cola.pendientesPorClave().mapValues { it.value.kind }
        if (!vigente()) return
        val marca = "swaps_migrados_${dieta.id}"
        val yaMigrado = (d.leer(marca) as? JsonPrimitive)?.booleanOrNull ?: false
        val e = dieta.estructura
        val tipo = tipoDia
        val h = SwapsDeComida.hidratar(remotos, _swaps.value, dieta.id, pendientes, yaMigrado, _palanca.value.anclajeBorraSwaps) { c, o, f ->
            SwapsDeComida.enPosicion(e, tipo, c, o, f)
        } ?: run {
            // Los reemplazos no llegaron (red): los ajustes del día no dependen de eso.
            hidratarAjustes(t, dieta) { vigente() }
            return
        }
        val tocados = tocadosSwaps.filterValues { it > desde }.keys
        _swaps.value = if (tocados.isEmpty()) h.swaps else h.swaps.filterKeys { it !in tocados } + _swaps.value.filterKeys { it in tocados }
        guardarSwaps()   // sin esperas desde `vigente()`: la carpeta y la dieta siguen siendo las del principio
        for (op in h.operaciones) {
            if (op.clave in tocados) continue
            val payload = (op.payload as? ValorJson.Objeto)?.let { ValorJson.Objeto(it.campos + ("dietaId" to texto(dieta.id))) } ?: op.payload
            cola.encolar(op.kind, payload, op.clave)
        }
        // Decidido con lo que tenía el servidor ANTES de los reemplazos de la cola vieja: ahora pueden salir.
        cola.soltarSwaps()
        if (h.migrando) {
            cola.drenar()
            val quedan = cola.pendientesPorClave().keys.any { it.startsWith("swap_${dieta.id}_") }
            if (!quedan) d.guardar(marca, ValorJson.Booleano(true))
        } else if (h.marcarMigrado) {
            d.guardar(marca, ValorJson.Booleano(true))
        }
        hidratarAjustes(t, dieta) { vigente() }
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
        /** F5: lo mínimo que se sigue intentando algo que el servidor rechaza antes de darlo por perdido. */
        const val VENTANA_ABANDONO_MS = 30L * 60 * 1000
        /**
         * Solo en las builds de prueba (MainActivity con `--ez elegirHorario`, o una prueba): pisa la palanca
         * `elegir_horario`. En la de la tienda queda en null y manda la palanca.
         */
        @Volatile
        var elegirHorarioForzado: Boolean? = null

        internal const val ARCHIVO_PALANCA_ELEGIR = "elegir-horario-palanca.json"

        /** La palanca `elegir_horario` que se leyó por última vez en esta cuenta (de fábrica, apagada). */
        internal fun elegirHorarioRecordado(d: Disco): Boolean =
            d.leer(ARCHIVO_PALANCA_ELEGIR)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

        /** Ver [faltaDecidirSwaps]. */
        internal fun faltaDecidirSwapsEn(d: Disco): Boolean = d.carpeta.list().orEmpty().any { n ->
            if (!n.startsWith("swaps_") || !n.endsWith(".json")) return@any false
            val dieta = n.removePrefix("swaps_").removeSuffix(".json")
            val marca = (d.leer("swaps_migrados_$dieta") as? JsonPrimitive)?.booleanOrNull ?: false
            !marca && ((d.leer(n) as? JsonObject)?.isNotEmpty() ?: false)
        }

        /**
         * El catálogo de ejercicios que trae la app (el de `apps/shared/catalogo-ejercicios.json`): lo pone la app al
         * arrancar. Se usa hasta que llega el del servidor, y para arrancar sin red si nunca llegó.
         */
        @Volatile
        var catalogoEmpaquetado: CatalogoEjercicios = CatalogoEjercicios(emptyList())

        const val CLAVE_TIPO_DIA = "mypump_tipo_dia"
        const val CLAVE_TOKEN_INVALIDO = "mypump_token_invalido"
        internal const val ARCHIVO_COPIA = "offline.json"
        internal const val ARCHIVO_METAS = "metas.json"
        internal const val ARCHIVO_RECIENTES = "agregados_recientes.json"
        internal const val ARCHIVO_CODIGOS = "codigos_barras.json"

        /** Cuántos recientes se guardan. */
        internal const val MAXIMO_RECIENTES = 12

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
