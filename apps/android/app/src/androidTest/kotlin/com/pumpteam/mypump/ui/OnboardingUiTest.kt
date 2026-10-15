package com.pumpteam.mypump.ui

import org.junit.Assume.assumeTrue
import androidx.health.connect.client.HealthConnectClient
import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.acceso.Onboarding
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.avisos.PermisoAvisos
import com.pumpteam.mypump.avisos.PermisoDePrueba
import com.pumpteam.mypump.datos.FuenteSalud
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.datos.PermisosSalud
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import kotlinx.coroutines.awaitCancellation
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La hoja de permisos de la primera vez (GEN-06, gemela de OnboardingUITests.swift y AvisosUITests.swift): aparece sola con
 * una cuenta, "Ahora no" la cierra sin pedirle nada al sistema y no vuelve a salir; "Activar notificaciones" pide el permiso
 * y con el sí deja agendado el aviso del domingo y registrado el push; con el no, dice dónde cambiarlo.
 */
@RunWith(AndroidJUnit4::class)
class OnboardingUiTest : PruebaUi() {
    private var fuenteAntes: FuenteSalud? = null

    @Before
    fun guardarFuente() {
        fuenteAntes = ModeloSalud.fuenteDelSistema
        // El emulador trae Health Connect, y si no hay ninguna fuente el ViewModel instala la de verdad: el paso de Salud
        // saldría adelante de Notificaciones. Cada prueba que lo quiere pone la suya.
        ModeloSalud.fuenteDelSistema = SinHealthConnect
        // Como un teléfono recién instalado con Android 13+: sin el permiso todavía. Si no, dependía de si otra prueba lo
        // había dado (y hasta Android 12 viene dado), y el paso de Notificaciones no aparece con el permiso ya dado.
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
    }

    @After
    fun devolverFuente() {
        ModeloSalud.fuenteDelSistema = fuenteAntes
        PermisoDePrueba.estado = null
        PermisoDePrueba.respuesta = null
    }

    /** Con las notificaciones ya prendidas (Android 12 o menos, o dadas antes) y sin Health Connect no hay nada que pedir. */
    @Test
    fun conLasNotificacionesYaPrendidasYSinSaludNoSale() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        pendiente()
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(3_000)
        assertFalse("la hoja salió sin nada que pedir", p.existe(etiqueta("onboarding-permisos")))
        assertEquals("1", preferencia(Onboarding.CLAVE))
    }

    /** Con las notificaciones ya prendidas, Salud es el único paso. */
    @Test
    fun conLasNotificacionesYaPrendidasSoloPideSalud() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        ModeloSalud.fuenteDelSistema = FuenteQueNoVuelve
        pendiente()
        guardarCuenta()
        abrir()
        p.nodo(texto("Conectá tu salud"))
        p.tocar(etiqueta("onboarding-ahora-no"))
        p.esperarQueNoEste(etiqueta("onboarding-permisos"))
        assertFalse(p.existe(texto("Que no se te pase nada")))
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertEquals(0, CentroAvisos.pedidos)
    }

    /** Como una cuenta que nunca la vio (en el resto de las pruebas ya está vista). */
    private fun pendiente() {
        app.getSharedPreferences(PreferenciasCompartidas.ARCHIVO, Context.MODE_PRIVATE).edit().remove(Onboarding.CLAVE).commit()
    }

    @Test
    fun ahoraNoCierraSinPedirNadaYNoVuelve() {
        pendiente()
        guardarCuenta()
        abrir().also {
            p.nodo(etiqueta("onboarding-permisos"))
            p.nodo(texto("Que no se te pase nada"))
            p.nodo(
                texto(
                    "Para que te lleguen los mensajes de Mati y su aviso de los domingos para la revisión. Nada más: no te vamos a llenar el teléfono de notificaciones.",
                ),
            )
            p.nodo(texto("Activar notificaciones"))
            // Sin Health Connect (hoy, en Android) no hay paso de Salud: es uno solo y no dice "paso 1 de 2".
            p.nodo(texto("esto lo podés cambiar después en Mis datos"))
            assertFalse(p.existe(texto("Conectá tu salud")))
            Telefono.captura("22-onboarding-notificaciones-claro")
            p.tocar(etiqueta("onboarding-ahora-no"))
            p.esperarQueNoEste(etiqueta("onboarding-permisos"))
            p.nodo(etiqueta("pestana-entreno"))
        }.close()
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertEquals("«Ahora no» no pide nada", 0, CentroAvisos.pedidos)
        assertNull("la hoja del sistema no se mostró", preferencia(CentroAvisos.CLAVE_PEDIDO))
        // Ya se vio: al volver a abrir no aparece.
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(3_000)
        assertFalse("la hoja de permisos volvió a salir", p.existe(etiqueta("onboarding-permisos")))
    }

    @Test
    fun activarNotificacionesPideElPermisoYConElSiCierraLaHoja() {
        pendiente()
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
        PermisoDePrueba.respuesta = true
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("onboarding-aceptar"))
        // Con permiso la hoja se cierra sola (sin permiso diría "Quedó sin permiso").
        p.esperarQueNoEste(etiqueta("onboarding-permisos"))
        assertEquals(1, CentroAvisos.pedidos)
        assertEquals("1", preferencia(CentroAvisos.CLAVE_PEDIDO))
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertTrue("el aviso del domingo quedó agendado", CentroAvisos.domingoAgendado(app))
        // Y el push, registrado apenas se dio el permiso (no en el próximo arranque).
        val registro = p.esperar("el registro del push") { servidor.a("mypump_registrar_push").firstOrNull() }
        assertTrue(registro, "\"p_device\":\"${AvisosDePrueba.TOKEN_PUSH}\"" in registro)
        assertTrue(registro, "\"p_plataforma\":\"android\"" in registro)
    }

    @Test
    fun conElNoDiceDondeCambiarloYEntendidoCierra() {
        pendiente()
        PermisoDePrueba.estado = PermisoAvisos.SIN_PEDIR
        PermisoDePrueba.respuesta = false
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("onboarding-aceptar"))
        p.nodo(texto("Quedó sin permiso. Si cambiás de idea, lo activás desde Mis datos."))
        assertFalse("sin el botón de activar", p.existe(etiqueta("onboarding-aceptar")))
        assertEquals(listOf("Entendido"), p.textosBajo(etiqueta("onboarding-ahora-no")))
        p.tocar(etiqueta("onboarding-ahora-no"))
        p.esperarQueNoEste(etiqueta("onboarding-permisos"))
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertFalse(CentroAvisos.domingoAgendado(app))
        assertTrue(servidor.a("mypump_registrar_push").isEmpty())
    }

    /** Si ya lo negó para siempre, la hoja del sistema no vuelve a salir: ni se pide, se dice dónde cambiarlo. */
    @Test
    fun yaNegadoNoLoVuelveAPedir() {
        pendiente()
        PermisoDePrueba.estado = PermisoAvisos.NEGADO
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("onboarding-aceptar"))
        p.nodo(texto("Quedó sin permiso. Si cambiás de idea, lo activás desde Mis datos."))
        assertEquals(0, CentroAvisos.pedidos)
    }

    /**
     * Con Health Connect (cuando lo instale la etapa de Salud) va primero Salud, con los textos de Android, y la puerta de
     * salida no se traba aunque la conexión no vuelva (la 1.0.4 dejaba "Un momento…" sin salida).
     */
    @Test
    fun conSaludSonDosPasosYAhoraNoNoSeTraba() {
        ModeloSalud.fuenteDelSistema = FuenteQueNoVuelve
        pendiente()
        guardarCuenta()
        abrir()
        p.nodo(texto("Conectá tu salud"))
        p.nodo(
            texto(
                "MyPump puede leer lo que ya mide tu teléfono o tu reloj: pasos, sueño, pulso en reposo y variabilidad. Con eso Mati ve cómo venís recuperando de verdad y te ajusta el plan con datos, no a ojo.",
            ),
        )
        p.nodo(texto("Se lee solo. Nunca escribimos nada en tu app de Salud."))
        p.nodo(texto("paso 1 de 2 · esto lo podés cambiar después en Mis datos"))
        assertFalse("en Android no dice Apple", p.resumen().contains("Apple"))
        Telefono.captura("23-onboarding-salud-claro")
        p.tocar(etiqueta("onboarding-aceptar"))
        p.esperar("conectando") { !p.habilitado(etiqueta("onboarding-aceptar")) }
        // Mientras Health Connect no contesta, "Ahora no" sigue andando.
        p.tocar(etiqueta("onboarding-ahora-no"))
        p.nodo(texto("Que no se te pase nada"))
        p.nodo(texto("paso 2 de 2 · esto lo podés cambiar después en Mis datos"))
        p.tocar(etiqueta("onboarding-ahora-no"))
        p.esperarQueNoEste(etiqueta("onboarding-permisos"))
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertEquals(0, CentroAvisos.pedidos)
    }

    /** Con el Health Connect del emulador (la fuente que instala el ViewModel), Salud va primero y "Ahora no" pasa a Notificaciones. */
    @Test
    fun conHealthConnectDeVerdadElPrimerPasoEsSalud() {
        // Health Connect viene con Android 14+; en 9 a 13 es una app aparte que un emulador sin cuenta de Google no tiene.
        assumeTrue(
            "este teléfono no tiene Health Connect",
            HealthConnectClient.getSdkStatus(app) == HealthConnectClient.SDK_AVAILABLE,
        )
        ModeloSalud.fuenteDelSistema = null
        pendiente()
        guardarCuenta()
        abrir()
        p.nodo(texto("Conectá tu salud"))
        p.nodo(texto("paso 1 de 2 · esto lo podés cambiar después en Mis datos"))
        p.tocar(etiqueta("onboarding-ahora-no"))
        p.nodo(texto("Que no se te pase nada"))
        p.nodo(texto("paso 2 de 2 · esto lo podés cambiar después en Mis datos"))
        p.tocar(etiqueta("onboarding-ahora-no"))
        p.esperarQueNoEste(etiqueta("onboarding-permisos"))
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertEquals(0, CentroAvisos.pedidos)
    }

    /** Nunca en la demo (la que mira la revisión de las tiendas). */
    @Test
    fun enLaDemoNoSale() {
        pendiente()
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(texto("Estás viendo la demo"))
        p.quieto(3_000)
        assertFalse(p.existe(etiqueta("onboarding-permisos")))
        assertNull(preferencia(Onboarding.CLAVE))
    }

    /** Atrás la cierra como "Ahora no": no pide nada y no vuelve. */
    @Test
    fun atrasLaCierraSinPedirNada() {
        pendiente()
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("onboarding-permisos"))
        p.atras()
        p.esperarQueNoEste(etiqueta("onboarding-permisos"))
        p.nodo(etiqueta("pestana-entreno"))
        assertEquals("1", preferencia(Onboarding.CLAVE))
        assertEquals(0, CentroAvisos.pedidos)
    }

    /** Un teléfono sin Health Connect: la hoja es solo Notificaciones. */
    private object SinHealthConnect : FuenteSalud {
        override val plataforma = PlataformaSalud.ANDROID

        override suspend fun disponible() = false

        override suspend fun pedirLectura(tipos: List<String>) = Unit

        override suspend fun permisos(tipos: List<String>) = PermisosSalud(emptyList(), tipos)

        override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> = emptyList()

        override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> = emptyList()

        override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = emptyList()
    }

    /** Health Connect que está pero cuya hoja de permisos nunca vuelve. */
    private object FuenteQueNoVuelve : FuenteSalud {
        override val plataforma = PlataformaSalud.ANDROID

        override suspend fun disponible() = true

        override suspend fun pedirLectura(tipos: List<String>) {
            awaitCancellation()
        }

        override suspend fun permisos(tipos: List<String>) = PermisosSalud(emptyList(), tipos)

        override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> = emptyList()

        override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> = emptyList()

        override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = emptyList()
    }
}
