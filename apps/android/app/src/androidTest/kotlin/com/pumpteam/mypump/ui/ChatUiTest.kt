package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.chat.TextosChat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * El chat (CHA-01…06), gemelo de ChatUITests de iOS, con el [ChatDePrueba] encima del servidor de prueba: un hilo con
 * memoria que pagina, sondea y devuelve como fila real lo que la cola manda. Nada sale a la red.
 */
@RunWith(AndroidJUnit4::class)
class ChatUiTest : PruebaUi() {
    private lateinit var chat: ChatDePrueba

    @Before
    fun conElChatDePrueba() {
        chat = ChatDePrueba(servidor)
        Entorno.transporte = chat
    }

    /** Abre la app con la cuenta guardada y va a Chat. */
    private fun abrirElChat() = abrir().also {
        p.tocar(etiqueta("pestana-chat"))
        p.nodo(etiqueta("chat-campo"))
    }

    private fun badgeDelChat(): Boolean = p.textosBajo(etiqueta("pestana-chat")).any { it.endsWith("sin ver") }

    /**
     * CHA-02, gemela de `testUnMensajeDeMasDeMilNoSale`: nunca sale un mensaje de más de 1000 caracteres (la web corta con
     * `maxlength`). No se recorta mientras se escribe: el contador se pone en rojo y Enviar se apaga hasta que vuelva a entrar.
     */
    @Test
    fun unMensajeDeMasDeMilNoSale() {
        guardarCuenta()
        abrirElChat()
        val campo = etiqueta("chat-campo")
        val enviar = etiqueta("chat-enviar")
        val contador = etiqueta("chat-contador")
        p.escribir(campo, "a".repeat(1001))
        p.esperar("el contador") { "Te pasaste: 1.001 de 1.000 caracteres" in p.textosBajo(contador) }
        assertTrue(p.textosBajo(contador).contains("1.001/1.000"))
        assertFalse("con 1001 se podía mandar", p.habilitado(enviar))
        p.escribir(campo, "a".repeat(1000))
        p.esperar("con 1000 se puede mandar") { p.habilitado(enviar) }
        assertEquals(listOf("1.000/1.000", "1.000 de 1.000 caracteres"), p.textosBajo(contador))
        // Hasta 900 no hay contador.
        p.escribir(campo, "a".repeat(900))
        p.esperarQueNoEste(contador)
        assertTrue(servidor.a("mypump_agregar_comentario").isEmpty())
    }

    /**
     * CHA-04: al entrar se marca leído lo general y el badge baja; con el chat a la vista, lo que llega de Mati queda leído
     * enseguida; en otra pestaña el chat queda cerrado y lo nuevo vuelve a sumar al badge.
     */
    @Test
    fun alEntrarSeMarcaLeidoYElBadgeBaja() {
        chat.agregar("coach", "¿Cómo venís con el plan?", Instant.now().minusSeconds(3_600))
        guardarCuenta()
        val e = abrir()
        p.esperar("el badge de Chat") { "1" in p.textosBajo(etiqueta("pestana-chat")) }
        assertTrue("se marcó leído sin abrir el chat", servidor.a("mypump_marcar_leidos_cliente").isEmpty())
        p.tocar(etiqueta("pestana-chat"))
        p.nodo(texto("Mati: ¿Cómo venís con el plan?"))
        p.esperar("marcó leído lo general") { servidor.a("mypump_marcar_leidos_cliente").any { "\"p_ambito\":\"general\"" in it } }
        p.esperar("el badge bajó") { !badgeDelChat() }
        assertEquals(0, chat.sinLeerDeMati())

        val (vm, m) = p.modeloCargado(e)
        assertTrue("con el chat a la vista tiene que estar abierto", m.chat.value!!.abierto)
        chat.agregar("coach", "Dale, mañana lo vemos")
        p.enLaApp(vm) { m.chat.value!!.sondear() }
        p.nodo(texto("Mati: Dale, mañana lo vemos"))
        p.esperar("leído al llegar") { chat.sinLeerDeMati() == 0 }
        p.quieto(300)
        assertFalse(badgeDelChat())

        p.tocar(etiqueta("pestana-dieta"))
        p.esperar("el chat se cerró") { !m.chat.value!!.abierto }
        chat.agregar("coach", "¿Pudiste entrenar?")
        p.enLaApp(vm) { m.chat.value!!.sondear() }
        p.esperar("el badge volvió") { "1" in p.textosBajo(etiqueta("pestana-chat")) }
        assertEquals(1, chat.sinLeerDeMati())
    }

    /**
     * CHA-03: sin señal la burbuja aparece igual, tenue y "enviando…", y el campo queda vacío. Cuando vuelve la red la cola
     * lo manda y la fila real reemplaza a la optimista: una sola burbuja, con su hora.
     */
    @Test
    fun sinRedElMensajeQuedaEnviandoYSaleCuandoVuelve() {
        guardarCuenta()
        val e = abrirElChat()
        val (vm, m) = p.modeloCargado(e)
        p.nodo(etiqueta("chat-vacio"))
        p.nodo(texto("Escribile a Mati"))
        servidor.sinRed = true
        p.escribir(etiqueta("chat-campo"), MENSAJE)
        p.tocar(etiqueta("chat-enviar"))
        val burbuja = texto("Vos: $MENSAJE")
        p.nodo(texto("enviando…"))
        assertEquals("Enviando", p.estado(burbuja))
        assertEquals("", p.textoDe(etiqueta("chat-campo")))
        // Con el hilo ya no está el encabezado de "vacío".
        assertFalse(p.existe(etiqueta("chat-vacio")))
        p.nodo(etiqueta("chat-encabezado"))
        p.quieto(500)
        assertTrue(chat.delCliente().isEmpty())

        servidor.sinRed = false
        p.enLaApp(vm) {
            m.outbox?.drenar()
            m.chat.value?.sondear()
        }
        p.esperar("salió") { chat.delCliente() == listOf(MENSAJE) }
        p.esperarQueNoEste(texto("enviando…"))
        assertNull(p.estado(burbuja))
        assertEquals(1, p.cuantos(burbuja))
        assertTrue(p.textosBajo(burbuja).any { Regex("[0-9]{2}:[0-9]{2}").matches(it) })
        p.nodo(texto("Hoy"))
    }

    /**
     * CHA-03: si la cola se rinde (8 intentos rechazados), la burbuja dice "no salió" con Reintentar y el texto no se pierde;
     * Reintentar lo vuelve a encolar y sale.
     */
    @Test
    fun siLaColaSeRindeDiceNoSalioYSePuedeReintentar() {
        // La base lo rechaza (devuelve vacío): cada pasada de la cola gasta un intento.
        servidor.respuestas["mypump_agregar_comentario"] = "null"
        guardarCuenta()
        val e = abrirElChat()
        val (_, m) = p.modeloCargado(e)
        p.escribir(etiqueta("chat-campo"), MENSAJE)
        p.tocar(etiqueta("chat-enviar"))
        p.nodo(texto("enviando…"))
        // Los 8 intentos sin esperar las pausas de la cola (2, 4, 6… s): cada `drenar` hace una pasada.
        val cola = m.outbox!!
        p.esperar("la cola se rindió", ms = 60_000, enElPrincipal = false) {
            if (p.existe(texto("no salió"))) true else null.also { runBlocking { cola.drenar() } }
        }
        val burbuja = texto("Vos: $MENSAJE")
        assertEquals("No salió", p.estado(burbuja))
        assertFalse(p.existe(texto("enviando…")))
        assertEquals("los 8 intentos de la web", 8, servidor.a("mypump_agregar_comentario").size)
        assertTrue(chat.delCliente().isEmpty())

        // Ya no lo rechaza: Reintentar lo vuelve a mandar.
        servidor.respuestas.remove("mypump_agregar_comentario")
        p.tocar(etiqueta("chat-reintentar"))
        p.esperar("salió") { chat.delCliente() == listOf(MENSAJE) }
        p.esperarQueNoEste(texto("no salió"))
        p.esperarQueNoEste(texto("enviando…"))
        assertEquals(1, p.cuantos(burbuja))
        assertNull(p.estado(burbuja))
    }

    /** CHA-02: lo que se está escribiendo no lo pisa un mensaje que llega, y sobrevive a ir a otra pestaña y volver. */
    @Test
    fun elBorradorSobreviveCuandoLlegaUnMensaje() {
        chat.agregar("coach", "Hola, ¿cómo vas?", Instant.now().minusSeconds(600))
        guardarCuenta()
        val e = abrirElChat()
        val (vm, m) = p.modeloCargado(e)
        p.nodo(texto("Mati: Hola, ¿cómo vas?"))
        val borrador = "Todavía lo estoy escribiendo"
        p.escribir(etiqueta("chat-campo"), borrador)
        chat.agregar("coach", "Acordate de mandarme el peso")
        p.enLaApp(vm) { m.chat.value!!.sondear() }
        p.nodo(texto("Mati: Acordate de mandarme el peso"))
        p.quieto(300)
        assertEquals(borrador, p.textoDe(etiqueta("chat-campo")))
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("2.373"))
        p.tocar(etiqueta("pestana-chat"))
        p.esperar("el borrador sigue") { p.textoDe(etiqueta("chat-campo")) == borrador }
        assertTrue(servidor.a("mypump_agregar_comentario").isEmpty())
    }

    /**
     * CHA-01: el hilo de a 30 con "Ver mensajes anteriores", los separadores Hoy / Ayer / la fecha y las burbujas a los
     * costados (D12). Traer la página anterior pide desde el más viejo y, con menos de 30, el botón se va.
     */
    @Test
    fun verMensajesAnterioresYLosSeparadores() {
        val zona = ZoneId.systemDefault()
        val hoy = LocalDate.now(zona)
        val inicioDeHoy = hoy.atStartOfDay(zona).toInstant()
        val hace10 = hoy.minusDays(10)
        // 40 de hace 10 días (el 1 es el más viejo), 3 de ayer y 2 de hoy: 45 en total.
        for (i in 1..40) {
            chat.agregar(if (i % 2 == 0) "coach" else "cliente", "Mensaje $i", hace10.atTime(9, 0).atZone(zona).toInstant().plusSeconds(60L * i))
        }
        for (i in 1..3) chat.agregar(if (i == 2) "cliente" else "coach", "De ayer $i", inicioDeHoy.minusSeconds(43_200L - 60 * i))
        chat.agregar("coach", "De hoy 1", inicioDeHoy.plusSeconds(60))
        chat.agregar("cliente", "De hoy 2", inicioDeHoy.plusSeconds(120))
        guardarCuenta()
        abrirElChat()
        // Abajo de todo, lo más nuevo: hoy y ayer con sus separadores.
        p.nodo(texto("Vos: De hoy 2"))
        p.nodo(texto("Hoy"))
        p.nodo(texto("Mati: De hoy 1"))
        p.nodo(texto("Ayer"))
        p.nodo(texto("Mati: De ayer 3"))
        // Arriba de la primera página (los 30 más nuevos: del 16 al 40 de hace 10 días, más ayer y hoy), el botón.
        val lista = etiqueta("chat-lista")
        val anteriores = etiqueta("chat-anteriores")
        hastaQueAparezca(lista, anteriores)
        p.nodo(texto(TextosChat.separador(hace10.toString(), hoy)))
        assertTrue(p.existe(texto("Mati: Mensaje 16")))
        assertFalse(p.existe(texto("Vos: Mensaje 15")))
        assertEquals(1, servidor.a("mypump_get_chat").count { "\"p_antes\":null" in it })
        p.tocar(anteriores)
        p.esperar("la página anterior") { servidor.a("mypump_get_chat").any { "\"p_antes\":\"" in it } }
        p.esperarQueNoEste(anteriores)
        hastaQueAparezca(lista, texto("Vos: Mensaje 1"))
        // Los 15 de antes son del mismo día: no se repite el separador.
        assertEquals(1, p.cuantos(texto(TextosChat.separador(hace10.toString(), hoy))))
    }

    /** ACC-07: en la demo el hilo está vacío, Enviar no se prende y nada toca la red. */
    @Test
    fun enLaDemoNoSeManda() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-chat"))
        p.nodo(etiqueta("chat-vacio"))
        p.nodo(texto("En la demo los mensajes no se envían."))
        p.escribir(etiqueta("chat-campo"), "Hola Mati")
        p.quieto(300)
        assertFalse(p.habilitado(etiqueta("chat-enviar")))
        assertFalse(p.existe(etiqueta("chat-anteriores")))
        assertTrue(
            servidor.llamadas.map { it.funcion }.toString(),
            servidor.llamadas.none { "chat" in it.funcion || "comentario" in it.funcion || "leidos" in it.funcion },
        )
    }

    /** Desplaza la conversación hacia lo más viejo hasta que aparezca [s] (la lista solo compone lo que se ve). */
    private fun hastaQueAparezca(lista: Selector, s: Selector) {
        // Con `reverseLayout` el sentido de la acción de desplazar depende de la versión de Compose: se prueban los dos (hacia
        // abajo de todo no se mueve nada).
        for (paso in listOf(1_500f, -1_500f)) {
            repeat(10) {
                if (p.existe(s)) return
                p.desplazar(lista, paso)
            }
        }
        p.nodo(s, ms = 2_000)
    }

    private companion object {
        const val MENSAJE = "Prueba de la app nativa (cuenta de prueba, ignorar)"
    }
}
