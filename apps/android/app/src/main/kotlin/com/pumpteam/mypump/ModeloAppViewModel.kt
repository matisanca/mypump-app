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
import com.pumpteam.mypump.legado.ArranqueMigracion
import com.pumpteam.mypump.legado.RegistroLegado
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
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

    /** Lo que dijo la Activity antes de que el modelo existiera. */
    private var aLaVista = true

    init {
        viewModelScope.launch {
            // El catálogo empaquetado (440 KB) se lee mientras corre la Fase L: lo usa Entreno hasta que llega el del
            // servidor, y para arrancar sin red si nunca llegó.
            val catalogo = async(Dispatchers.IO) { leerCatalogo() }
            val cliente = ClienteRpc(transporte = Entorno.transporte ?: TransporteOkHttp())
            val m = ArranqueMigracion.arrancar(app, almacen, preferencias, viewModelScope) {
                ModeloApp(
                    cliente = cliente, almacen = almacen, raizDisco = app.filesDir, preferencias = preferencias,
                    alcance = viewModelScope,
                )
            }
            catalogo.await()?.let { ModeloApp.catalogoEmpaquetado = it }
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
        }
    }

    /** "Ver demo": la rutina y la dieta de ejemplo de la web, empaquetadas. Sin red ni cuenta. */
    fun entrarEnDemo() {
        viewModelScope.launch {
            val m = _modelo.value ?: return@launch
            val (rutina, dieta) = withContext(Dispatchers.IO) {
                fun leer(n: String) = app.assets.open("demo/$n.json").use { it.readBytes().toString(Charsets.UTF_8) }
                leer("rutina") to leer("dieta")
            }
            m.entrarEnDemo(rutina, dieta)
        }
    }

    /** "Salir" de la barra de la demo: vuelve a la bienvenida, o a la cuenta si había una guardada. */
    fun salirDeDemo() {
        viewModelScope.launch { _modelo.value?.salirDeDemo() }
    }

    /** La app pasó a primer plano o a segundo: los sondeos solo corren a la vista (CHA-04). */
    fun primerPlano(visible: Boolean) {
        aLaVista = visible
        val m = _modelo.value ?: return
        m.enPrimerPlano = visible
        if (visible) viewModelScope.launch { m.alVolverAPrimerPlano() }
    }

    override fun onCleared() {
        apariencia.cerrar()
    }
}
