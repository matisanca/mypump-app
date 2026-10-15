package com.pumpteam.mypump.ui

import android.app.Instrumentation
import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.Disco
import com.pumpteam.mypump.datos.FuenteSalud
import com.pumpteam.mypump.datos.HistorialSalud
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.datos.PermisosSalud
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.salud.DiagnosticoSaludPedido
import com.pumpteam.mypump.salud.EstadoHealthConnect
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Un Health Connect de mentira para las pantallas: disponible, da todo lo que se le pide y tiene una pesada por ventana.
 * Las consultas de verdad contra el Health Connect del emulador están en `salud/HealthConnectRealTest`.
 */
class FuenteDeMentira : FuenteSalud {
    override val plataforma = PlataformaSalud.ANDROID
    val pedidos = CopyOnWriteArrayList<List<String>>()
    val conHistorial = CopyOnWriteArrayList<List<String>>()

    override suspend fun disponible(): Boolean = true

    override suspend fun pedirLectura(tipos: List<String>) {
        pedidos += tipos
    }

    override suspend fun pedirLecturaConHistorial(tipos: List<String>): HistorialSalud {
        pedidos += tipos
        conHistorial += tipos
        return HistorialSalud(autorizado = true, disponible = true)
    }

    override suspend fun permisos(tipos: List<String>): PermisosSalud = PermisosSalud(tipos, emptyList())

    override suspend fun historial(): HistorialSalud = HistorialSalud(autorizado = true, disponible = true)

    override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> = emptyList()

    override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> =
        if (dataType == "weight") listOf(MuestraSalud(desde + 8 * 3_600_000, desde + 8 * 3_600_000, 81.5, "com.withings.wiscale2", "Withings")) else emptyList()

    override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = emptyList()
}

/**
 * Salud en Android (SAL-08…13): la fila de Recuperación de Mis datos abre el detalle, "Mostrarme el score" se guarda,
 * cinco toques en el título de Health Connect (o `?diag=health` en el link) abren el diagnóstico, "Conectar Health
 * Connect" pide el núcleo con el historial y después el resto, y sin Health Connect se ofrece Play (o nada, si el
 * teléfono no lo soporta). Ningún texto dice "Apple" ni "iPhone".
 */
@RunWith(AndroidJUnit4::class)
class SaludUiTest : PruebaUi() {
    private lateinit var fuente: FuenteDeMentira

    @Before
    fun ponerFuente() {
        fuente = FuenteDeMentira()
        ModeloSalud.fuenteDelSistema = fuente
        EstadoHealthConnect.forzado = EstadoHealthConnect.DISPONIBLE
    }

    @After
    fun sacarFuente() {
        ModeloSalud.fuenteDelSistema = null
        EstadoHealthConnect.forzado = null
        DiagnosticoSaludPedido.cerrar()
    }

    /** La salud de la cuenta de iOS (60 días de reloj y 14 de recuperación con score): la que llena todas las secciones. */
    private fun conDatosDeReloj() {
        for (f in listOf("get_salud", "get_recuperacion", "get_mostrar_recuperacion")) {
            servidor.respuestas["mypump_$f"] = instr.context.assets.open("test-nativa-ios/$f.json").use { it.readBytes().toString(Charsets.UTF_8) }
        }
    }

    private fun irAMisDatos() {
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
    }

    private fun sinApple() {
        assertFalse("un texto dice Apple: ${p.resumen()}", p.existe(textoQueContiene("Apple")))
        assertFalse("un texto dice iPhone: ${p.resumen()}", p.existe(textoQueContiene("iPhone")))
    }

    @Test
    fun laRecuperacionDeMisDatosAbreElDetalleYElDiagnostico() {
        conDatosDeReloj()
        guardarPreferencia(ClaveSalud.CONECTADO, "1")
        guardarPreferencia(ClaveSalud.HISTORIAL_HECHO, "1")
        irAMisDatos()
        // El score de la última fila (45), con su banda.
        p.nodo(textoQueContiene("45/100"))
        Telefono.captura("salud-mis-datos")
        p.tocar(etiqueta("mis-datos-salud"))
        p.nodo(etiqueta("salud-detalle"))
        for (t in listOf("Cómo se arma tu recuperación", "Sueño", "Corazón", "Actividad", "Cuerpo", "Preferencias", "Health Connect")) p.nodo(texto(t))
        // Las secciones sin datos no se muestran (la cuenta no tiene respiración, oxígeno ni temperatura).
        assertFalse(p.existe(texto("Otras señales")))
        p.nodo(etiqueta("sincronizar-salud"))
        sinApple()
        Telefono.captura("salud-detalle")

        // "Mostrarme el score": optimista y guardado. (El servidor de prueba no guarda nada: lo que lee después sigue
        // diciendo que sí, así que el interruptor se mira una sola vez, apenas se toca.)
        assertTrue(p.prendido(etiqueta("mostrar-score")))
        p.tocar(etiqueta("mostrar-score"))
        p.esperar("se apaga el interruptor") { !p.prendido(etiqueta("mostrar-score")) }
        p.esperar("se guarda el interruptor") { servidor.a("mypump_set_mostrar_recuperacion").any { "\"p_mostrar\":false" in it } }

        // Cinco toques en el título abren el diagnóstico; Atrás lo cierra y vuelve al detalle.
        repeat(5) { p.tocar(etiqueta("titulo-health-connect")) }
        p.nodo(etiqueta("diagnostico-salud"))
        p.nodo(texto("Estado de Health Connect"))
        p.nodo(etiqueta("diagnostico-tipos"), ms = 20_000)
        p.nodo(texto("Permisos dados"))
        sinApple()
        Telefono.captura("salud-diagnostico")
        p.atras()
        p.esperarQueNoEste(etiqueta("diagnostico-salud"))
        p.nodo(etiqueta("salud-detalle"))
        p.atras()
        p.esperarQueNoEste(etiqueta("salud-detalle"))
        p.nodo(etiqueta("mis-datos-pantalla"))
    }

    /** "Conectar Health Connect" pide el núcleo con el historial, después el resto (nunca escritura), y sincroniza. */
    @Test
    fun conectarDesdeMisDatosPideElNucleoConElHistorialYSincroniza() {
        irAMisDatos()
        p.nodo(textoQueContiene("Conectá tu reloj o Health Connect"))
        sinApple()
        p.tocar(etiqueta("conectar-salud"))
        p.esperar("se pidieron las dos tandas") { fuente.pedidos.size >= 2 }
        assertEquals(PuenteSalud.nucleo, fuente.pedidos[0])
        assertEquals(listOf(PuenteSalud.nucleo), fuente.conHistorial.toList())
        assertEquals(PuenteSalud.resto(PlataformaSalud.ANDROID, 0), fuente.pedidos[1])
        // Los 7 días se suben como Health Connect, y el botón se va.
        p.esperar("se subió la salud") { servidor.a("mypump_ingest_salud").any { "\"fuente\":\"health_connect\"" in it } }
        p.esperarQueNoEste(etiqueta("conectar-salud"))
        // Lo guardado es de la cuenta (hallazgo 3 del 15-oct): las claves llevan su huella.
        val deLaCuenta = "_" + Disco.huella(ServidorDePrueba.TOKEN)
        assertEquals("1", preferencia(ClaveSalud.CONECTADO + deLaCuenta))
        assertEquals("1", preferencia(ClaveSalud.HISTORIAL_OK + deLaCuenta))
    }

    /** Sin Health Connect: si se consigue, se ofrece desde Play (con su presentación); si el teléfono no lo soporta, nada. */
    @Test
    fun sinHealthConnectSeOfreceDesdePlayYSiNoSeSoportaNoSeOfreceNada() {
        EstadoHealthConnect.forzado = EstadoHealthConnect.INSTALAR
        var capturado: Intent? = null
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action == Intent.ACTION_VIEW && intent.dataString?.startsWith("market://") == true) {
                    capturado = intent
                    return Instrumentation.ActivityResult(0, null)
                }
                return null
            }
        }
        instr.addMonitor(monitor)
        try {
            irAMisDatos()
            p.nodo(texto("Este teléfono no tiene Health Connect. Se instala gratis desde Google Play."))
            assertFalse(p.existe(etiqueta("conectar-salud")))
            p.nodo(texto("Instalar Health Connect"))
            p.tocar(etiqueta("instalar-health-connect"))
            p.esperar("se abrió Play") { capturado }
        } finally {
            instr.removeMonitor(monitor)
        }
        val i = capturado
        assertNotNull(i)
        assertEquals("market://details?id=com.google.android.apps.healthdata&url=healthconnect%3A%2F%2Fonboarding", i!!.dataString)
        assertEquals("com.android.vending", i.`package`)
    }

    /**
     * Sin Health Connect DE VERDAD, sin dobles: la fuente y el estado del teléfono. Es lo que pasa en Android 9 a 13 sin la
     * app de Play, como en los emuladores de la matriz. Mis datos lo ofrece desde Play (o nada, si el teléfono no lo
     * soporta) y no ofrece conectarlo, el detalle dice por qué, el diagnóstico abre y la app sigue andando. Supuesto: donde
     * Health Connect viene con el sistema (Android 14+) no se lo puede sacar; ahí lo prueban las de arriba, con el estado
     * forzado.
     */
    @Test
    fun sinHealthConnectDeVerdadOfreceInstalarloYNoSeRompe() {
        ModeloSalud.fuenteDelSistema = null   // la de verdad: la pone el ViewModel (`FuenteHealthConnect.instalar`)
        EstadoHealthConnect.forzado = null
        val estado = EstadoHealthConnect.de(app)
        assumeTrue("este teléfono tiene Health Connect (Android 14+, o la app de Play)", estado != EstadoHealthConnect.DISPONIBLE)
        val porque = when (estado) {
            EstadoHealthConnect.INSTALAR -> "Este teléfono no tiene Health Connect. Se instala gratis desde Google Play."
            EstadoHealthConnect.ACTUALIZAR -> "Hay que actualizar Health Connect para conectarlo. Se actualiza gratis desde Google Play."
            else -> "Este teléfono no es compatible con Health Connect."
        }
        val play = CopyOnWriteArrayList<Intent>()
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_VIEW || EstadoHealthConnect.PAQUETE !in (intent.dataString ?: "")) return null
                play += intent
                return Instrumentation.ActivityResult(0, null)
            }
        }
        instr.addMonitor(monitor)
        try {
            irAMisDatos()
            p.nodo(etiqueta("mis-datos-salud"))
            if (estado == EstadoHealthConnect.NO_SOPORTADO) {
                p.quieto(500)
                assertFalse(p.existe(etiqueta("instalar-health-connect")))
            } else {
                p.nodo(texto(porque))
                p.nodo(texto(if (estado == EstadoHealthConnect.INSTALAR) "Instalar Health Connect" else "Actualizar Health Connect"))
                p.tocar(etiqueta("instalar-health-connect"))
                val i = p.esperar("se abrió Play") { play.firstOrNull() }
                assertEquals("market://details?id=com.google.android.apps.healthdata&url=healthconnect%3A%2F%2Fonboarding", i.dataString)
            }
            assertFalse("sin Health Connect no se ofrece conectarlo", p.existe(etiqueta("conectar-salud")))
            // El detalle dice por qué y tampoco ofrece conectar.
            p.tocar(etiqueta("mis-datos-salud"))
            p.nodo(etiqueta("salud-detalle"))
            p.nodo(texto(porque))
            assertFalse(p.existe(etiqueta("conectar-health-connect")))
            sinApple()
        } finally {
            instr.removeMonitor(monitor)
        }
        // El diagnóstico (`?diag=health`) con la fuente de verdad: termina y dice que no está, sin cerrarse la app.
        abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&diag=health")
        p.nodo(etiqueta("diagnostico-salud"))
        p.nodo(etiqueta("diagnostico-tipos"), ms = 20_000)
        val textos = p.textosBajo(etiqueta("diagnostico-salud"))
        assertEquals("el diagnóstico tendría que decir que no hay Health Connect: $textos", "no", textos.getOrNull(textos.indexOf("Health Connect") + 1))
        p.atras()
        p.esperarQueNoEste(etiqueta("diagnostico-salud"))
        // Y la app sigue andando.
        p.tocar(etiqueta("pestana-entreno"))
        p.nodo(etiqueta("entreno-lista"))
    }

    @Test
    fun unHealthConnectViejoSeActualizaYUnTelefonoSinSoporteNoOfreceNada() {
        EstadoHealthConnect.forzado = EstadoHealthConnect.ACTUALIZAR
        irAMisDatos()
        p.nodo(texto("Actualizar Health Connect"))
        p.atras()
        p.esperarQueNoEste(etiqueta("mis-datos-pantalla"))
        // Sin soporte: ni conectar ni instalar (la sección sigue: el resumen y, adentro, el diagnóstico).
        EstadoHealthConnect.forzado = EstadoHealthConnect.NO_SOPORTADO
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-salud"))
        p.quieto(500)
        assertFalse(p.existe(etiqueta("conectar-salud")))
        assertFalse(p.existe(etiqueta("instalar-health-connect")))
        p.tocar(etiqueta("mis-datos-salud"))
        p.nodo(texto("Este teléfono no es compatible con Health Connect."))
        assertFalse(p.existe(etiqueta("instalar-health-connect")))
        assertFalse(p.existe(etiqueta("conectar-health-connect")))
    }

    /**
     * "No está llegando ningún dato": la ruta de Android (no la de Ajustes del iPhone), Reintentar, y "Abrir Health
     * Connect", que lleva a los permisos de MyPump en Health Connect (los permisos de Android se cambian ahí).
     */
    @Test
    fun siNoLlegaNadaLlevaALosPermisosDeHealthConnect() {
        guardarPreferencia(ClaveSalud.CONECTADO, "1")
        guardarPreferencia(ClaveSalud.HISTORIAL_HECHO, "1")
        guardarPreferencia(ClaveSalud.DENEGADO, "1")
        // Sin una muestra en la semana: la sospecha no se borra al abrir.
        ModeloSalud.fuenteDelSistema = object : FuenteSalud by fuente {
            override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> = emptyList()
        }
        irAMisDatos()
        p.tocar(etiqueta("mis-datos-salud"))
        p.nodo(texto("No está llegando ningún dato. Revisá que esté todo activado en Ajustes → Salud y bienestar → Health Connect → MyPump."))
        p.nodo(texto("Reintentar"))
        sinApple()
        // Supuesto del teléfono: a dónde lleva el botón se ve con el Health Connect de verdad. Acá el estado está forzado
        // (la fuente es de mentira); en Android 9 a 13 sin la app de Play no hay pantalla de Health Connect que abrir, y sin
        // Health Connect la app no muestra este botón (lo prueba `sinHealthConnectDeVerdadOfreceInstalarloYNoSeRompe`).
        assumeTrue(
            "este teléfono no tiene Health Connect para abrir",
            HealthConnectClient.getSdkStatus(app) == HealthConnectClient.SDK_AVAILABLE,
        )
        p.tocar(etiqueta("abrir-health-connect"))
        val arriba = p.esperar("se abre Health Connect", ms = 20_000, enElPrincipal = false) {
            Telefono.shell("dumpsys activity activities").lineSequence().firstOrNull { "topResumedActivity=" in it }
                ?.let { Regex("""u\d+ ([A-Za-z0-9_.]+)/""").find(it)?.groupValues?.get(1) }?.takeIf { it != app.packageName }
        }
        assertTrue("arriba quedó $arriba", "healthconnect" in arriba)
        Telefono.shell("input keyevent KEYCODE_BACK")
    }

    /** `?diag=health` en el link abre el diagnóstico directo (SAL-13, ACC-09). */
    @Test
    fun elLinkConDiagHealthAbreElDiagnostico() {
        guardarCuenta()
        abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&diag=health")
        p.nodo(etiqueta("diagnostico-salud"))
        p.nodo(etiqueta("diagnostico-tipos"), ms = 20_000)
        p.atras()
        p.esperarQueNoEste(etiqueta("diagnostico-salud"))
        p.nodo(etiqueta("pestana-entreno"))
    }
}
