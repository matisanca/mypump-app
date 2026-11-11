package com.pumpteam.mypump

import android.app.Application
import android.net.Uri
import androidx.annotation.VisibleForTesting
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pumpteam.mypump.acceso.Apariencia
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.acceso.TokenEnKeystore
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.DestinoAviso
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.datos.TransporteOkHttp
import com.pumpteam.mypump.entreno.Preguntador
import com.pumpteam.mypump.legado.ArranqueMigracion
import com.pumpteam.mypump.legado.RegistroLegado
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.salud.DiagnosticoSaludPedido
import com.pumpteam.mypump.salud.FuenteHealthConnect
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import com.pumpteam.mypump.guia.ControlReproductor
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Lo que las pruebas de interfaz cambian ANTES de abrir la Activity: el transporte de la red (un doble que contesta las
 * respuestas grabadas, sin tocar el backend). En la app siempre es null y se usa OkHttp.
 */
@VisibleForTesting
object Entorno {
    @Volatile
    var transporte: Transporte? = null

    /**
     * El código que «lee» el escáner de barras (2.1, S3) en las pruebas, sin abrir el escáner de Google (que es otra app,
     * de Play Services). Open Food Facts contesta por [transporte]. En la app siempre es null.
     */
    @Volatile
    var codigoDePrueba: String? = null

    /** Corre bajo una prueba instrumentada (el runner de androidx.test está cargado en el proceso). */
    private val instrumentada: Boolean by lazy {
        runCatching { Class.forName("androidx.test.platform.app.InstrumentationRegistry") }.isSuccess
    }

    /**
     * Una prueba (con un doble de la red, o instrumentada): lo que deja rastro en el sistema, como las alarmas de los
     * avisos de la videollamada, no se agenda.
     */
    val enPruebas: Boolean get() = transporte != null || instrumentada
    /**
     * Fotos de inicio en modo de prueba (`buena`, `oscura`, `chica` o `movida`): el botón de foto arma un JPEG de mentira con
     * ese aspecto en vez de abrir la cámara (FotoSinteticaFotosInicio). Lo prenden las pruebas de interfaz, o en un build de
     * depuración el extra `fotosInicioDePrueba` al abrir la app. En la app siempre es null.
     */
    @Volatile
    var fotosInicioDePrueba: String? = null
}

/**
 * Dueño del [ModeloApp] mientras vive la app: sobrevive a rotar la pantalla y sus corrutinas (la cola, el sondeo del
 * chat) corren en el `viewModelScope`, en el hilo principal, como el `@MainActor` de iOS.
 *
 * Lo de Android vive acá: el token cifrado con el Keystore (fuera del backup), las preferencias, el tema guardado, la
 * carpeta de la app y lo que trae empaquetado (la demo y el catálogo de ejercicios).
 *
 * El modelo NO existe desde el principio: antes corre la Fase L de la migración del almacenamiento viejo
 * ([ArranqueMigracion]), porque el modelo lee el token y la cola al iniciar. En un teléfono que viene de la app Capacitor
 * eso es un WebView oculto (unos segundos, una sola vez); en los demás arranques, mirar fechas y tamaños de archivos.
 * Mientras tanto [modelo] es null y se ve la marca.
 */
class ModeloAppViewModel(private val app: Application) : AndroidViewModel(app) {
    private val almacen = TokenEnKeystore(File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO))
    private val preferencias = PreferenciasCompartidas(app)
    private val _modelo = MutableStateFlow<ModeloApp?>(null)
    val modelo: StateFlow<ModeloApp?> = _modelo.asStateFlow()

    /** D5: lo que eligió el cliente ("Siempre en modo oscuro"). */
    val apariencia = Apariencia(app)

    /** "2.0.0 (100)", como en el recibo de la migración. */
    val version: String = ArranqueMigracion.version(app)

    /** "2.0.0": lo que se compara con la versión mínima de la palanca remota. */
    val versionCorta: String = version.substringBefore(" (")

    /** Lo que anotó la migración (para "Informe de la actualización" en Mis datos). */
    val registroMigracion: File get() = RegistroLegado.archivo(app)

    /**
     * Las preguntas de Entreno que esperan respuesta (reabrir el día, "¿Está bien cargado?", "¡Día completado!"…). Viven
     * acá: lo que las espera corre en el alcance de la app y una pregunta abierta sobrevive a rotar la pantalla.
     */
    val preguntasEntreno = Preguntador()

    /** Lo que dijo la Activity antes de que el modelo existiera. */
    private var aLaVista = true

    // Salud: Health Connect como la fuente del sistema, ANTES de crear el ModeloApp (el ModeloSalud de la cuenta la lee
    // al crearse). Una prueba que ya puso un doble lo conserva.
    init {
        FuenteHealthConnect.instalar(app)
    }

    init {
        viewModelScope.launch {
            // El catálogo empaquetado (440 KB) se lee mientras corre la Fase L: lo usa Entreno hasta que llega el del
            // servidor, y para arrancar sin red si nunca llegó.
            val catalogo = async(Dispatchers.IO) { leerCatalogo() }
            val cliente = ClienteRpc(transporte = Entorno.transporte ?: TransporteOkHttp())
            val m = ArranqueMigracion.arrancar(app, almacen, preferencias, viewModelScope) {
                ModeloApp(
                    cliente = cliente, almacen = almacen, raizDisco = app.filesDir, preferencias = preferencias,
                    alcance = viewModelScope, raizSinRespaldo = app.noBackupFilesDir, raizCache = app.cacheDir,
                )
            }
            catalogo.await()?.let { ModeloApp.catalogoEmpaquetado = it }
            m.versionApp = versionCorta
            m.enPrimerPlano = aLaVista
            _modelo.value = m
            // El `.task` de RaizApp: con una cuenta guardada, se trae todo al abrir.
            if (m.fase.value == ModeloApp.Fase.CARGANDO) m.cargar()
        }
    }

    private fun leerCatalogo(): CatalogoEjercicios? = try {
        app.assets.open("bases/catalogo-ejercicios.json").use { CatalogoEjercicios.desde(it.readBytes().toString(Charsets.UTF_8)) }
            .takeIf { it.entradas.isNotEmpty() }
    } catch (_: Exception) {
        null
    }

    // Dieta: la base de alimentos de la web (food-db.json, 42 KB) para la hoja "Reemplazar", leída una vez al arrancar
    // como el catálogo de ejercicios. La hoja la espera si se abre antes (`MotorSustitutos.base` es un flujo). Con los
    // nombres enteros, sin tocar los imports de arriba.
    init {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { leerBaseAlimentos() }?.let(com.pumpteam.mypump.dieta.MotorSustitutos::instalar)
        }
    }

    private fun leerBaseAlimentos(): com.pumpteam.mypump.reglas.BaseAlimentos? = try {
        app.assets.open("bases/food-db.json").use { com.pumpteam.mypump.dieta.MotorSustitutos.leer(it.readBytes().toString(Charsets.UTF_8)) }
    } catch (_: Exception) {
        null
    }

    /** A dónde pidió ir un link (`?scene=diet`, ACC-09): lo consume la navegación al llegar. */
    private val _destino = MutableStateFlow<DestinoAviso?>(null)
    val destino: StateFlow<DestinoAviso?> = _destino.asStateFlow()

    fun destinoConsumido() {
        _destino.value = null
    }

    /**
     * El link del coach (`https://app.mypumpteam.com/?t=…`) abrió la app. Si la migración todavía corre, espera al modelo.
     * Con `?scene=` (una escena que existe) va después a esa pestaña, como iOS.
     */
    fun abrirLink(link: String) {
        viewModelScope.launch {
            _modelo.filterNotNull().first().entrar(link)
            val escena = try {
                Uri.parse(link).getQueryParameter("scene")
            } catch (_: Exception) {
                null
            }
            DestinoAviso.deEscena(escena)?.let { _destino.value = it }
            // Salud: `?diag=health` (SAL-13) abre el diagnóstico de Salud directo, sin los cinco toques.
            DiagnosticoSaludPedido.desdeLink(link)
        }
    }

    // ── Avisos (NOT-03) ──

    /**
     * Se tocó un aviso (un push de Mati, el del domingo, el fin del descanso): a su pestaña. Si la app recién arranca, la
     * navegación lo consume cuando aparecen las pestañas.
     */
    fun abrirAviso(destino: DestinoAviso) {
        _destino.value = destino
    }

    /** "Ver demo": la rutina, la dieta, la guía, la suplementación y el historial de ejemplo, empaquetados. Sin red ni cuenta. */
    fun entrarEnDemo() {
        viewModelScope.launch {
            val m = _modelo.value ?: return@launch
            val (rutina, dieta, opcionales) = withContext(Dispatchers.IO) {
                fun leer(n: String) = app.assets.open("demo/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }
                // La guía y la suplementación de muestra son opcionales: si faltaran, la demo sigue sin ellas.
                Triple(leer("rutina"), leer("dieta"), listOf("guia", "suplementacion", "agenda", "historial").map { runCatching { leer(it) }.getOrNull() })
            }
            m.entrarEnDemo(rutina, dieta, opcionales[0], opcionales[1], opcionales[2], historial = opcionales[3])
        }
    }

    /** "Salir" de la barra de la demo: vuelve a la bienvenida, o a la cuenta si había una guardada. */
    fun salirDeDemo() {
        viewModelScope.launch { _modelo.value?.salirDeDemo() }
    }

    private var _reproductorGuia: ControlReproductor? = null

    /** El reproductor de «Tu guía»: vive acá para que girar el teléfono (la Activity se vuelve a crear) no corte el video. */
    val reproductorGuia: ControlReproductor
        get() = _reproductorGuia ?: ControlReproductor(app, viewModelScope).also { _reproductorGuia = it }

    /**
     * La app pasó a primer plano o a segundo: los sondeos solo corren a la vista (CHA-04), y con la app atrás el video de
     * la guía se pausa (y no vuelve a sonar solo, ver [ControlReproductor.pausar]).
     */
    fun primerPlano(visible: Boolean) {
        aLaVista = visible
        // Con la app atrás, el video de la guía no sigue sonando.
        if (!visible) _reproductorGuia?.pausar()
        val m = _modelo.value ?: return
        m.enPrimerPlano = visible
        if (visible) {
            viewModelScope.launch { m.alVolverAPrimerPlano() }
        } else {
            // Ir a segundo plano cierra la ventana de Deshacer: lo anotado no puede quedar dependiendo de que la app viva.
            viewModelScope.launch { m.entreno.value?.vaciarDeshacer() }
        }
    }

    override fun onCleared() {
        apariencia.cerrar()
        _reproductorGuia?.liberar()
    }
}
