package com.pumpteam.mypump.ui

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.acceso.Apariencia
import com.pumpteam.mypump.acceso.Onboarding
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.acceso.TokenEnKeystore
import java.io.File
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
        // Las fotos del catálogo tampoco van a la red: se ve el marcador.
        FotosDePrueba.sinRed()
        Raices.instalar()
        // Avisos: sin Firebase de verdad y con el permiso que dé el teléfono (las de avisos lo fijan).
        AvisosDePrueba.preparar()
    }

    @After
    fun terminarPrueba() {
        // `ActivityScenario.close()` espera a que el hilo principal quede quieto, sin tope: con una animación sin fin en
        // pantalla, en Android 9 eso no pasa nunca y la corrida entera quedó colgada 13 minutos (15-oct, la galería de fotos).
        // Si no queda quieto en 20 s, se terminan las Activity a mano (sin ventanas no hay animación) y se sigue: no falla,
        // porque hay animaciones largas que no son errores (el descanso que corre después de confirmar una serie). Las que
        // no deberían estar (una ruedita sin fin) las miran sus pruebas con `dibujosEn` y `quietoConTope`.
        val trabada = if (escenarios.isNotEmpty() && !Telefono.quietoConTope()) p.resumen() else null
        if (trabada != null) {
            instr.runOnMainSync {
                val monitor = ActivityLifecycleMonitorRegistry.getInstance()
                for (etapa in Stage.values()) for (a in monitor.getActivitiesInStage(etapa)) a.finish()
            }
        }
        for (e in escenarios.asReversed()) runCatching { e.close() }
        escenarios.clear()
        Entorno.transporte = null
        FotosDePrueba.porRed()
        Raices.desinstalar()
        Telefono.modoNoche(false)
        reiniciarEstado()
        AvisosDePrueba.soltar(app)
        if (trabada != null) Log.w("MyPumpPruebas", "la pantalla no quedó quieta en 20 s al terminar; se cerró igual. En pantalla: $trabada")
    }

    /** Sin cuenta, sin preferencias y sin los archivos de ninguna cuenta. Lo de la migración (`files/legado`) no se toca. */
    protected fun reiniciarEstado() {
        File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO).delete()
        app.getSharedPreferences(PreferenciasCompartidas.ARCHIVO, Context.MODE_PRIVATE).edit().clear().commit()
        File(app.filesDir, "MyPump").deleteRecursively()
        // La hoja de permisos de la primera vez ya se vio (el `-sinOnboarding` de iOS): las que la prueban la vuelven a pedir.
        guardarPreferencia(Onboarding.CLAVE, "1")
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

    companion object {
        @JvmStatic
        @BeforeClass
        fun prepararTelefono() {
            Telefono.prepararPantalla()
        }
    }
}
