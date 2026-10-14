package com.pumpteam.mypump.datos

import java.time.DayOfWeek
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Destinos, preferencias y token como la Capacitor (AvisosTests.swift). */
class AvisosTest {
    @Test
    fun destinos() {
        assertEquals(DestinoAviso.ENTRENO, DestinoAviso.deDestino("train"))
        assertEquals(DestinoAviso.DIETA, DestinoAviso.deDestino("diet"))
        assertEquals(DestinoAviso.PROGRESO, DestinoAviso.deDestino("progress"))
        assertEquals(DestinoAviso.MI_DIA, DestinoAviso.deDestino("myday"))
        assertEquals(DestinoAviso.REVISION, DestinoAviso.deDestino("revision"))
        assertEquals(DestinoAviso.MIS_DATOS, DestinoAviso.deDestino("salud"))
        assertEquals(DestinoAviso.CHAT, DestinoAviso.deDestino("chat"))
        assertEquals(DestinoAviso.CHAT, DestinoAviso.deDestino("comentarios"))
        assertEquals(DestinoAviso.CHAT, DestinoAviso.deDestino(null))
    }

    /**
     * El aviso del domingo llega como un mensaje de Mati (pedido del 14-oct): su nombre de título, como sus mensajes del
     * chat, y escrito como él les escribe a los clientes (sin dos puntos, guiones ni emojis). Abre Revisión.
     */
    @Test
    fun elAvisoDelDomingoEsUnMensajeDeMati() {
        assertEquals("Mati", AvisoDomingo.TITULO)
        assertEquals("1002", AvisoDomingo.ID, "el id de la Capacitor: reprogramar pisa el viejo")
        assertEquals(DayOfWeek.SUNDAY, AvisoDomingo.diaDeLaSemana)
        assertEquals(11 to 0, AvisoDomingo.HORA to AvisoDomingo.MINUTO)
        assertEquals(DestinoAviso.REVISION, DestinoAviso.deDestino(AvisoDomingo.DESTINO))
        val cuerpo = AvisoDomingo.CUERPO
        assertTrue(cuerpo.isNotBlank())
        assertTrue(listOf(":", "-", "–", "—").none { it in cuerpo }, cuerpo)
        // Un emoji es un símbolo (So), va fuera del plano básico o lleva un selector de variación, una unión o un marco de
        // tecla. `Character.isEmoji` recién está en Java 21, y estos módulos son para la 17.
        val emojis = cuerpo.codePoints().filter { c ->
            Character.getType(c) == Character.OTHER_SYMBOL.toInt() || c > 0xFFFF || c == 0xFE0F || c == 0x200D || c == 0x20E3
        }.toArray()
        assertTrue(emojis.isEmpty(), cuerpo)
    }

    @Test
    fun escenaDelLink() {
        assertEquals(DestinoAviso.DIETA, DestinoAviso.deEscena("diet"))
        assertEquals(DestinoAviso.MIS_DATOS, DestinoAviso.deEscena("salud"))
        assertNull(DestinoAviso.deEscena("comentarios"))
        assertNull(DestinoAviso.deEscena(null))
    }

    @Test
    fun preferenciasSeMezclanSobreLasDeFabrica() {
        assertEquals(PreferenciasAvisos.porDefecto, PreferenciasAvisos.leer(null))
        assertEquals(PreferenciasAvisos.porDefecto, PreferenciasAvisos.leer("basura"))
        val p = PreferenciasAvisos.leer("{\"check\":{\"on\":false},\"entreno\":{\"on\":true,\"hora\":7}}")
        assertEquals(PreferenciasAvisos.Recordatorio(on = false, hora = 11, min = 0), p.check)
        val q = PreferenciasAvisos.leer("{\"check\":{\"hora\":9,\"min\":30}}")
        assertEquals(PreferenciasAvisos.Recordatorio(on = true, hora = 9, min = 30), q.check)
        assertEquals(q, PreferenciasAvisos.leer(q.texto))
    }

    @Test
    fun tokenEnMayusculas() {
        assertEquals("0ABCFF00", TokenPush.hex(byteArrayOf(0x0a, 0xbc.toByte(), 0xff.toByte(), 0x00)))
    }

    @Test
    fun registrarPushSoloSiCambio() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ -> if (fn == "mypump_registrar_push") 200 to "true" else 200 to "[]" }
        val prefs = PreferenciasEnMemoria()
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("tokenDePrueba_0000000000"), carpetaTemporal("push"), prefs, alcance)
        assertTrue(m.registrarPush("fcm-1", "2.0.0"))
        assertEquals("fcm-1", prefs.leer("mypump_push_token"))
        assertTrue(m.registrarPush("fcm-1", "2.0.0"))
        assertEquals(1, t.llamadas.count { it == "mypump_registrar_push" })
        // En la demo no se registra nada.
        m.entrarEnDemo(Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"))
        assertFalse(m.registrarPush("fcm-2", "2.0.0"))
    }
}

/** El link pegado, como index.html (LinkPegadoTests.swift y los casos de la web). */
class LinkPegadoTest {
    private val t = "abcdefghij0123456789ABCDEFGHIJ_-"

    @Test
    fun elMensajeEnteroDeWhatsApp() {
        assertEquals(t, FormatoToken.extraer("Hola! Este es tu link para entrar a MyPump: https://app.mypumpteam.com/?t=$t\nCualquier cosa me escribís"))
        assertEquals(t, FormatoToken.extraer("app.mypumpteam.com/cliente.html?t=$t"))
        assertEquals(t, FormatoToken.extraer(t))
        assertNull(FormatoToken.extraer("hola"))
    }

    @Test
    fun linksEnterosYAMedias() {
        assertEquals(t, FormatoToken.extraer("  https://app.mypumpteam.com/?t=$t&utm=wa  "))
        assertEquals(t, FormatoToken.extraer("https://app.mypumpteam.com/cliente.html?scene=diet&t=$t#x"))
        assertEquals(t, FormatoToken.extraer("https://app.mypumpteam.com/acceso/$t"))
        assertEquals(t, FormatoToken.extraer("https://app.mypumpteam.com/?t=%61bcdefghij0123456789ABCDEFGHIJ_-"))
        assertNull(FormatoToken.extraer("https://app.mypumpteam.com/?t=corto"))
        assertNull(FormatoToken.extraer(""))
        // Como la web: el token después de "?" sin "t=" no es un link de acceso.
        assertNull(FormatoToken.extraer("https://app.mypumpteam.com/?$t"))
    }
}
