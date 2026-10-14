package com.pumpteam.mypump.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.acceso.Apariencia
import com.pumpteam.mypump.acceso.HojaPermisoIA
import com.pumpteam.mypump.acceso.PermisoIAEstado
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.acceso.TokenEnKeystore
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.PreferenciasEnMemoria
import com.pumpteam.mypump.datos.TokenEnMemoria
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.TemaMyPump
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.junit.After
import org.junit.Before
import org.junit.BeforeClass

/**
 * Lo común de las pruebas de interfaz (en el emulador: `./gradlew connectedDebugAndroidTest`): la app arranca como recién
 * instalada (como `-reiniciar YES` de iOS: sin cuenta, sin preferencias y sin archivos de cuentas), con el
 * [ServidorDePrueba] en lugar de la red, y el teléfono en claro.
 */
abstract class PruebaUi {
    protected val instr = InstrumentationRegistry.getInstrumentation()
    protected val app: Context get() = instr.targetContext
    protected val p = Pantalla()
    protected lateinit var servidor: ServidorDePrueba
    private val escenarios = ArrayList<ActivityScenario<*>>()

    @Before
    fun prepararPrueba() {
        Telefono.modoNoche(false)
        reiniciarEstado()
        servidor = ServidorDePrueba()
        Entorno.transporte = servidor
        Raices.instalar()
    }

    @After
    fun terminarPrueba() {
        for (e in escenarios.asReversed()) runCatching { e.close() }
        escenarios.clear()
        Entorno.transporte = null
        Raices.desinstalar()
        Telefono.modoNoche(false)
        reiniciarEstado()
    }

    /** Sin cuenta, sin preferencias y sin los archivos de ninguna cuenta. Lo de la migración (`files/legado`) no se toca. */
    protected fun reiniciarEstado() {
        File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO).delete()
        app.getSharedPreferences(PreferenciasCompartidas.ARCHIVO, Context.MODE_PRIVATE).edit().clear().commit()
        File(app.filesDir, "MyPump").deleteRecursively()
    }

    protected fun <A : android.app.Activity> registrar(e: ActivityScenario<A>): ActivityScenario<A> = e.also { escenarios += it }

    /** Abre la app como al tocar el ícono. */
    protected fun abrir(): ActivityScenario<MainActivity> = registrar(ActivityScenario.launch(MainActivity::class.java))

    /** Abre la app tocando un link (el App Link de WhatsApp: `https://app.mypumpteam.com/?t=…`). */
    protected fun abrirConLink(link: String): ActivityScenario<MainActivity> =
        registrar(ActivityScenario.launch(intentDeLink(link)))

    protected fun intentDeLink(link: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(link)).setClassName(app, MainActivity::class.java.name)

    /** Una cuenta ya guardada en el teléfono (la app entra sola al abrir). */
    protected fun guardarCuenta(token: String = ServidorDePrueba.TOKEN) {
        TokenEnKeystore(File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO)).guardar(token)
    }

    protected fun tokenGuardado(): String? = TokenEnKeystore(File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO)).leer()

    protected fun preferencia(clave: String): String? =
        app.getSharedPreferences(PreferenciasCompartidas.ARCHIVO, Context.MODE_PRIVATE).getString(clave, null)

    protected fun guardarPreferencia(clave: String, valor: String) {
        app.getSharedPreferences(PreferenciasCompartidas.ARCHIVO, Context.MODE_PRIVATE).edit().putString(clave, valor).commit()
    }

    /** Entra con la cuenta de prueba pegando el link y espera las pestañas. */
    protected fun entrarConLaCuenta() {
        p.escribir(etiqueta("campo-link"), "https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}")
        p.tocar(etiqueta("entrar"))
        p.nodo(etiqueta("pestana-entreno"))
    }

    /** El tema oscuro que eligió el cliente ("Siempre en modo oscuro"). */
    protected fun guardarTemaOscuro() = guardarPreferencia(Apariencia.CLAVE, Apariencia.OSCURO)

    private val alcances = ArrayList<CoroutineScope>()

    @After
    fun cancelarAlcances() {
        alcances.forEach { it.cancel() }
        alcances.clear()
    }

    /** Un modelo con la cuenta de prueba ya cargada (fuera de la Activity), como lo tiene la app. */
    protected fun modeloConCuenta(esperarPermiso: Boolean = true): Pair<ModeloApp, CoroutineScope> {
        val alcance = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate).also { alcances += it }
        val raiz = File(app.cacheDir, "prueba-ia-${System.nanoTime()}").apply { mkdirs() }
        val m = p.enPrincipal {
            ModeloApp(
                cliente = ClienteRpc(transporte = servidor), almacen = TokenEnMemoria(ServidorDePrueba.TOKEN), raizDisco = raiz,
                preferencias = PreferenciasEnMemoria(), alcance = alcance, versionApp = "2.0.0",
            )
        }
        p.enPrincipal { alcance.launch { m.cargar() } }
        p.esperar("la cuenta cargó") {
            m.fase.value == ModeloApp.Fase.LISTO && (!esperarPermiso || m.consentimientoIADisponible.value)
        }
        return m to alcance
    }

    /**
     * La hoja del permiso de la IA con un disparador: en Android todavía no están las pantallas que la piden (el chat, la
     * foto de una comida, el check), así que "Mandar a Mati" hace lo que va a hacer el chat: `antesDeUsarIA` y, al seguir,
     * mandar el mensaje. Anota cada decisión con la que siguió.
     */
    protected fun armarPermisoIA(m: ModeloApp, alcance: CoroutineScope, decisiones: MutableList<Boolean>) {
        val e = registrar(ActivityScenario.launch(ComponentActivity::class.java))
        e.onActivity { a ->
            a.setContent {
                TemaMyPump(oscuro = isSystemInDarkTheme()) {
                    val estado = remember { PermisoIAEstado() }
                    Box(Modifier.fillMaxSize().background(MyPump.colores.fondo).systemBarsPadding(), contentAlignment = Alignment.Center) {
                        BotonMarca(
                            "Mandar a Mati",
                            alTocar = {
                                estado.antesDeUsarIA(m) { acepta ->
                                    decisiones += acepta
                                    alcance.launch { m.chat.value?.enviar("Hola Mati, ¿cambio el jalón?") }
                                }
                            },
                            compacto = true,
                            modifier = Modifier.testTag("mandar"),
                        )
                    }
                    HojaPermisoIA(m, estado, alcance)
                }
            }
        }
    }

    companion object {
        @JvmStatic
        @BeforeClass
        fun prepararTelefono() {
            Telefono.prepararPantalla()
        }
    }
}
