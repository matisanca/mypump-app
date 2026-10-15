package com.pumpteam.mypump.ui

import android.app.Instrumentation
import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
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
        assertEquals("1", preferencia(ClaveSalud.CONECTADO))
        assertEquals("1", preferencia(ClaveSalud.HISTORIAL_OK))
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
