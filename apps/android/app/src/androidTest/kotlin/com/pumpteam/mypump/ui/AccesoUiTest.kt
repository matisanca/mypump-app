package com.pumpteam.mypump.ui

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ModeloApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La bienvenida (ACC-03), el link vencido (ACC-04), sin conexión (ACC-05), la demo (ACC-07) y el App Link: el gemelo de
 * AccesoUITests.swift, con el backend de prueba en lugar de la red.
 */
@RunWith(AndroidJUnit4::class)
class AccesoUiTest : PruebaUi() {
    @Test
    fun laBienvenidaPideElLinkYOfreceLaDemo() {
        abrir()
        p.nodo(texto("Entrá con tu link"))
        p.nodo(texto("Abrí el link que te pasó Mati por WhatsApp. Si no se abre solo, copialo y pegalo acá."))
        p.nodo(etiqueta("campo-link"))
        p.nodo(etiqueta("pegar"))
        assertFalse("Entrar tiene que estar apagado con el campo vacío", p.habilitado(etiqueta("entrar")))
        p.nodo(textoQueContiene("Ver demo"))
        p.nodo(texto("Política de privacidad"))
        assertFalse(p.existe(etiqueta("link-vencido")))
        // Sin cuenta, la app no le pregunta nada al backend.
        assertTrue("llamó a ${servidor.llamadas.map { it.funcion }}", servidor.llamadas.isEmpty())
    }

    @Test
    fun laDemoEntraYSaleSinRedNiCuenta() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(texto("Estás viendo la demo"))
        for (pestana in listOf("entreno", "dieta", "chat", "revision", "progreso")) p.nodo(etiqueta("pestana-$pestana"))
        p.tocar(etiqueta("pestana-dieta"))
        // La dieta de ejemplo de la web: el objetivo es la suma de las opciones A.
        p.nodo(texto("Desayuno"))
        p.nodo(texto("2.454"))
        p.tocar(etiqueta("salir-demo"))
        p.nodo(etiqueta("ver-demo"))
        p.esperarQueNoEste(texto("Estás viendo la demo"))
        assertTrue("la demo tocó la red: ${servidor.llamadas.map { it.funcion }}", servidor.llamadas.isEmpty())
        assertNull("la demo no guarda una cuenta", tokenGuardado())
    }

    @Test
    fun unLinkQueNoEsDeMyPumpAvisa() {
        abrir()
        p.escribir(etiqueta("campo-link"), "hola")
        assertTrue(p.habilitado(etiqueta("entrar")))
        p.tocar(etiqueta("entrar"))
        p.nodo(texto("No reconocí ese link. Copialo entero de WhatsApp y pegalo de nuevo."))
        assertTrue("con un link que no es de MyPump no se llama al backend", servidor.llamadas.isEmpty())
        // Sigue en la bienvenida.
        p.nodo(texto("Entrá con tu link"))
    }

    @Test
    fun unLinkVencidoDiceQueYaNoSirveYDejaPegarOtro() {
        abrir()
        val vencido = "linkVencidoDePrueba_00000000"
        p.escribir(etiqueta("campo-link"), "Hola! Este es tu link: https://app.mypumpteam.com/?t=$vencido")
        p.tocar(etiqueta("entrar"))
        p.nodo(etiqueta("link-vencido"))
        p.nodo(texto("Este link ya no sirve"))
        p.nodo(texto("Pedile a Mati un link nuevo y pegalo acá abajo."))
        assertNull("un link vencido no queda guardado", tokenGuardado())
        assertEquals(vencido, preferencia(ModeloApp.CLAVE_TOKEN_INVALIDO))
        // Pega el nuevo, a medias (sin https): entra.
        p.escribir(etiqueta("campo-link"), "app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}")
        p.tocar(etiqueta("entrar"))
        p.nodo(etiqueta("pestana-entreno"))
        assertEquals(ServidorDePrueba.TOKEN, tokenGuardado())
    }

    @Test
    fun elTokenSoloTambienEntraYQuedaGuardado() {
        abrir().also {
            p.escribir(etiqueta("campo-link"), "  ${ServidorDePrueba.TOKEN}  ")
            p.tocar(etiqueta("entrar"))
            p.nodo(etiqueta("pestana-entreno"))
        }.close()
        assertEquals(ServidorDePrueba.TOKEN, tokenGuardado())
        // Al reabrir entra solo, sin pasar por la bienvenida.
        abrir()
        p.nodo(etiqueta("pestana-dieta"))
        assertFalse(p.existe(etiqueta("ver-demo")))
    }

    /**
     * Con la red lenta, la carga de la cuenta tarda más que el fundido de la bienvenida. La bienvenida lanzaba `entrar` en
     * su propio alcance y, al salir de pantalla, lo cancelaba: la app quedaba en la marca para siempre.
     */
    @Test
    fun entrarConLaRedLentaNoSeCortaCuandoLaBienvenidaSaleDePantalla() {
        servidor.demoraMs = 400
        servidor.respuestas["mypump_get_chat"] =
            """[{"id":"m1","autor":"coach","contenido":"¿Cómo venís?","leido_por_cliente":false,"created_at":"2026-10-14T12:00:00Z"}]"""
        abrir()
        p.escribir(etiqueta("campo-link"), ServidorDePrueba.TOKEN)
        p.tocar(etiqueta("entrar"))
        p.nodo(etiqueta("pestana-entreno"), ms = 30_000)
        // Lo último de la carga (el chat) también llegó.
        p.esperar("el badge del chat", ms = 30_000) { "1" in p.textosBajo(etiqueta("pestana-chat")) }
    }

    @Test
    fun sinConexionSePuedeReintentar() {
        servidor.sinRed = true
        abrir()
        p.escribir(etiqueta("campo-link"), ServidorDePrueba.TOKEN)
        p.tocar(etiqueta("entrar"))
        p.nodo(etiqueta("sin-conexion"))
        p.nodo(texto("Sin conexión"))
        p.nodo(texto("No pudimos traer tu plan. Cuando vuelva la señal lo intentamos solos."))
        // La cuenta quedó guardada: con señal, "Reintentar" entra.
        servidor.sinRed = false
        p.tocar(etiqueta("reintentar"))
        p.nodo(etiqueta("pestana-entreno"))
    }

    @Test
    fun conElServicioCaidoDiceQueEsDelServicio() {
        servidor.caido = true
        guardarCuenta()
        abrir()
        p.nodo(texto("Servicio fuera de línea"))
        p.nodo(textoQueContiene("Estamos con un problema del servicio"))
    }

    @Test
    fun elLinkDelCoachEntraALaCuentaYVaALaEscenaPedida() {
        abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&scene=diet")
        p.nodo(etiqueta("pestana-dieta"))
        p.esperar("Dieta elegida") { p.seleccionado(etiqueta("pestana-dieta")) }
        // La dieta de la cuenta de prueba (grabada de test-nativa-real).
        p.nodo(texto("Desayuno"))
        p.nodo(texto("2.373"))
        assertEquals(ServidorDePrueba.TOKEN, tokenGuardado())
    }

    @Test
    fun conLaAppAbiertaElLinkTambienEntra() {
        abrir()
        p.nodo(etiqueta("ver-demo"))
        // `singleTask`: el link llega a la misma Activity (onNewIntent), como al tocarlo en WhatsApp con la app abierta.
        app.startActivity(intentDeLink("https://app.mypumpteam.com/cliente.html?t=${ServidorDePrueba.TOKEN}").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        p.nodo(etiqueta("pestana-entreno"))
        assertEquals(ServidorDePrueba.TOKEN, tokenGuardado())
    }
}
