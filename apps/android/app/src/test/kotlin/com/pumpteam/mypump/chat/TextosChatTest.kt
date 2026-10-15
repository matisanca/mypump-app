package com.pumpteam.mypump.chat

import com.pumpteam.mypump.datos.BurbujaChat
import java.time.LocalDate
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Lo que la pantalla del chat arma con el hilo (ChatView.swift): separadores, grupos, hora y el límite de CHA-02. */
class TextosChatTest {
    private val ba = ZoneId.of("America/Argentina/Buenos_Aires")
    private val hoy = LocalDate.of(2026, 10, 14)

    private fun burbuja(id: String, autor: String, iso: String, pendiente: Boolean = false) =
        BurbujaChat(id = id, autor = autor, contenido = "m$id", leidoPorCliente = true, createdAt = iso, pendiente = pendiente)

    @Test
    fun separadoresHoyAyerYLaFechaComoIOS() {
        assertEquals("Hoy", TextosChat.separador("2026-10-14", hoy))
        assertEquals("Ayer", TextosChat.separador("2026-10-13", hoy))
        // iOS en es_AR (`weekday(.wide).day().month(.wide)`): con la coma y la inicial en mayúscula.
        assertEquals("Lunes, 12 de octubre", TextosChat.separador("2026-10-12", hoy))
        assertEquals("Martes, 1 de septiembre", TextosChat.separador("2026-09-01", hoy))
        assertEquals("Miércoles, 31 de diciembre", TextosChat.separador("2025-12-31", hoy))
        // Lo que no es una fecha queda tal cual (como `Fechas.dia` que da nil).
        assertEquals("cualquier cosa", TextosChat.separador("cualquier cosa", hoy))
    }

    @Test
    fun laHoraEsLaDelTelefonoEn24() {
        assertEquals("18:52", TextosChat.hora("2026-10-14T21:52:00+00:00", ba))
        assertEquals("18:52", TextosChat.hora("2026-10-14T21:52:59.123456+00:00", ba))
        assertEquals("09:05", TextosChat.hora("2026-10-14T12:05:00Z", ba))
        assertNull(TextosChat.hora("", ba))
        assertNull(TextosChat.hora("ayer", ba))
    }

    /**
     * Los grupos de ChatView.swift: dos de Mati seguidas son un grupo (la primera sin hora ni colita, más pegadas), la del
     * cliente abre otro, y un día nuevo corta el grupo aunque el autor sea el mismo. La hora va en la última del grupo.
     */
    @Test
    fun separadoresYGrupos() {
        val m = listOf(
            burbuja("1", "coach", "2026-10-13T13:00:00Z"),
            burbuja("2", "coach", "2026-10-13T13:01:00Z"),
            burbuja("3", "cliente", "2026-10-13T13:05:00Z"),
            // 01:30 UTC del 14 es todavía el 13 en Buenos Aires: mismo día, mismo grupo que el 3.
            burbuja("4", "cliente", "2026-10-14T01:30:00Z"),
            burbuja("5", "cliente", "2026-10-14T12:00:00Z"),
            burbuja("6", "coach", "2026-10-14T12:10:00Z"),
        )
        val filas = TextosChat.filas(m, hoy, ba)
        val resumen = filas.map {
            when (it) {
                is FilaHilo.Dia -> "[${it.texto}]"
                is FilaHilo.Mensaje -> "${it.burbuja.id}${if (it.iniciaGrupo) "^" else ""}${if (it.cierraGrupo) "$" else ""}${it.hora?.let { h -> " $h" } ?: ""}"
            }
        }
        assertEquals(listOf("[Ayer]", "1^", "2$ 10:01", "3^", "4$ 22:30", "[Hoy]", "5^$ 09:00", "6^$ 09:10"), resumen)
        // Las claves no se repiten: la lista las usa para animar y para no perder el lugar.
        assertEquals(filas.size, filas.map { it.clave }.toSet().size)
        assertEquals(listOf("dia-2026-10-13", "dia-2026-10-14"), filas.filterIsInstance<FilaHilo.Dia>().map { it.clave })
    }

    @Test
    fun unaOptimistaTambienCierraSuGrupo() {
        val filas = TextosChat.filas(
            listOf(burbuja("1", "cliente", "2026-10-14T12:00:00Z"), burbuja("tmp_1", "cliente", "2026-10-14T12:00:05.000Z", pendiente = true)),
            hoy, ba,
        )
        val ultima = filas.last() as FilaHilo.Mensaje
        assertTrue(ultima.cierraGrupo)
        assertEquals("09:00", ultima.hora)
        assertFalse((filas[1] as FilaHilo.Mensaje).cierraGrupo)
    }

    /** CHA-02 como iOS: se cuentan los caracteres que se ven (`String.count`), no las unidades de UTF-16. */
    @Test
    fun losCaracteresSonLosQueSeVen() {
        assertEquals(0, TextosChat.caracteres(""))
        assertEquals(1001, TextosChat.caracteres("a".repeat(1001)))
        assertEquals(5, TextosChat.caracteres("ñandú"))
        assertEquals(1, TextosChat.caracteres("👍🏽"))
        assertEquals(1, TextosChat.caracteres("🇦🇷"))
        assertEquals(1, TextosChat.caracteres("é"))
        assertEquals(1, TextosChat.caracteres("\r\n"))
        assertEquals(3, TextosChat.caracteres("a😀b"))
    }

    @Test
    fun elContadorYLoQueSePuedeMandar() {
        assertEquals("1.001/1.000", TextosChat.contador(1001))
        assertEquals("950/1.000", TextosChat.contador(950))
        // Lo que lee TalkBack, igual que el `accessibilityLabel` de iOS (ChatUITests).
        assertEquals("Te pasaste: 1.001 de 1.000 caracteres", TextosChat.contadorAccesible(1001))
        assertEquals("1.000 de 1.000 caracteres", TextosChat.contadorAccesible(1000))
        assertTrue(TextosChat.sePuedeMandar("a".repeat(1000)))
        assertFalse(TextosChat.sePuedeMandar("a".repeat(1001)))
        // Mil emojis entran (son mil caracteres aunque sean dos mil unidades de UTF-16).
        assertTrue(TextosChat.sePuedeMandar("😀".repeat(1000)))
        // Solo espacios no se manda: el `trim()` de JS (con el espacio ideográfico).
        assertFalse(TextosChat.sePuedeMandar("  \n\t　"))
        assertTrue(TextosChat.sePuedeMandar("  hola  "))
    }
}
