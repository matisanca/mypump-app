package com.pumpteam.mypump.entreno

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.reglas.Pauta
import com.pumpteam.mypump.reglas.UltimaVez
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Cómo se escriben en la app los textos del motor (el `Bonito` de iOS) y lo que lee TalkBack en la card de un ejercicio
 * (el `valorAccesible` de FilaEjercicio). Corre en el teléfono: el `Character` y las cajas son los de Android.
 */
@RunWith(AndroidJUnit4::class)
class BonitoTest {
    @Test
    fun laCargaConComaYEspacio() {
        assertEquals("52,5 kg × 7 · RIR 1", Bonito.carga("52.5kg × 7 · RIR 1"))
        assertEquals("80 kg × 10", Bonito.carga("80kg × 10"))
        assertEquals("82,5 kg × 8 (Soga) · 3 series", Bonito.carga("82.5kg × 8 (Soga) · 3 series"))
        // Con el peso del cuerpo: reps, no "0 kg".
        assertEquals("12 reps · RIR 1", Bonito.carga("0kg × 12 · RIR 1"))
        assertEquals("12 reps · 3 series", Bonito.carga("0kg × 12 · 3 series"))
        // 10 kg no es "1" + "0 kg".
        assertEquals("10 kg × 12", Bonito.carga("10kg × 12"))
        assertEquals("0,5 kg × 12", Bonito.carga("0.5kg × 12"))
        // Lo que no es una carga queda igual.
        assertEquals("Kettlebell", Bonito.carga("Kettlebell"))
    }

    @Test
    fun partirElPrincipalDelDetalle() {
        assertEquals("58 kg × 9" to "RIR 0 · Agarre neutro", Bonito.partir("58kg × 9 · RIR 0 (Agarre neutro)"))
        assertEquals("82,5 kg × 8" to "3 series · Soga", Bonito.partir("82.5kg × 8 (Soga) · 3 series"))
        assertEquals("58 kg × 9" to "4 series", Bonito.partir("58kg × 9 · 4 series"))
        assertEquals("80 kg × 10" to null, Bonito.partir("80kg × 10"))
    }

    @Test
    fun losTextosDeLasPreguntas() {
        assertEquals("Pasar a SEM 6", Bonito.boton("Pasar a SEM 6 →"))
        assertEquals("¡Día completado!", Bonito.sinEmoji("🎉 ¡Día completado!"))
        assertEquals("Modo demo — Mati todavía no publicó tu plan.", Bonito.sinEmoji("⚠ Modo demo — Mati todavía no publicó tu plan."))
        assertEquals("Primera vez con este ejercicio", Bonito.sinEmoji("🎯 Primera vez con este ejercicio"))
        // Lo que empieza con una letra, un signo o un número no se toca.
        assertEquals("¡Nuevo bloque!", Bonito.sinEmoji("¡Nuevo bloque!"))
        assertEquals("3 series", Bonito.sinEmoji("3 series"))
        assertEquals("Ir a Empuje", Bonito.nombres("Ir a EMPUJE"))
        assertEquals("Buen trabajo. ¿Querés ir al siguiente día (Tirón)?", Bonito.nombres("Buen trabajo. ¿Querés ir al siguiente día (TIRÓN)?"))
        // Las siglas cortas quedan.
        assertEquals("Pasar a SEM 6 · RIR 1", Bonito.nombres("Pasar a SEM 6 · RIR 1"))
        assertEquals("¿Confirmás que querés avanzar a la Semana 6?", Bonito.nombres("¿Confirmás que querés avanzar a la SEMANA 6?"))
        // Una palabra con un número pegado no es un nombre.
        assertEquals("TIRON2", Bonito.nombres("TIRON2"))
    }

    @Test
    fun losNombresDeDiasYBloques() {
        assertEquals("Tirón", Bonito.titulo("TIRÓN"))
        assertEquals("Tirón A — Ancho", Bonito.titulo("TIRÓN A — ANCHO"))
        assertEquals("Pecho/Hombro", Bonito.titulo("PECHO/HOMBRO"))
        assertEquals("Tirón A — Ancho", Bonito.titulo("Tirón A — Ancho"))
        assertEquals("", Bonito.titulo(null))
        assertEquals("Deltoides posterior y bíceps", Bonito.enOracion("DELTOIDES POSTERIOR Y BÍCEPS"))
        assertEquals("Espalda", Bonito.enOracion("Espalda"))
        assertEquals("123", Bonito.enOracion("123"))
        assertEquals("52,5", Bonito.coma("52.5"))
    }

    @Test
    fun elNombreDelEjercicioEnDosRenglones() {
        val n = NombreEjercicio("Jalón al pecho prono (dorsal ancho)")
        assertEquals("Jalón al pecho prono", n.principal)
        assertEquals("Dorsal ancho", n.detalle)
        val s = NombreEjercicio("Remo con barra")
        assertEquals("Remo con barra", s.principal)
        assertNull(s.detalle)
        // Con dos paréntesis, el músculo es el último.
        assertEquals("Press (inclinado)", NombreEjercicio("Press (inclinado) (pectoral)").principal)
    }

    @Test
    fun loQueLeeTalkBackEnLaCard() {
        assertEquals(
            "Pendiente, 4 series de 10, RIR 0 (al fallo), descanso 2:30, última vez 58 kg × 9 · 4 series, hace 3 días, récord 58 kg × 9 · RIR 0",
            CardAccesible.valor(
                "pendiente", 0, 4, sustituido = false, fijado = false, manual = false, mensajes = 0, tipo = "compuesto",
                pauta = Pauta(4, "10", "0 (al fallo)"), descansoSegundos = 150,
                ultima = UltimaVez("58kg × 9 · 4 series", "hace 3 días"), record = "58kg × 9 · RIR 0", buscandoHistorial = false,
            ),
        )
        assertEquals(
            "2 de 4 series, sustitución fijada, 1 mensaje sin leer, 4 series de 8-10, RIR 1-2, descanso 2:30, primera vez con este ejercicio",
            CardAccesible.valor(
                "pendiente", 2, 4, sustituido = true, fijado = true, manual = false, mensajes = 1, tipo = "compuesto",
                pauta = Pauta(4, "8-10", "1-2"), descansoSegundos = 150, ultima = null, record = null, buscandoHistorial = false,
            ),
        )
        assertEquals(
            "Terminado sin series, sustituido solo por hoy, marcado a mano, 3 mensajes sin leer, cardio, 10 min, descanso 1:30",
            CardAccesible.valor(
                "completo_sin_datos", 0, 0, sustituido = true, fijado = false, manual = true, mensajes = 3, tipo = "cardio",
                pauta = Pauta(null, "10 min", null), descansoSegundos = 90, ultima = null, record = null, buscandoHistorial = false,
            ),
        )
        // Mientras se busca el historial no dice "primera vez".
        val buscando = CardAccesible.valor(
            "completo", 4, 4, sustituido = false, fijado = false, manual = false, mensajes = 0, tipo = "calentamiento",
            pauta = Pauta(2, "10", null), descansoSegundos = 30, ultima = null, record = null, buscandoHistorial = true,
        )
        assertEquals("Completo, calentamiento, 2 series de 10, descanso 0:30", buscando)
        assertEquals("Saltado", CardAccesible.estado("saltado", 0, 3))
    }

    @Test
    fun elPitidoDelDescanso() {
        // 120 ms + 60 ms + 160 ms a 44,1 kHz, con silencio al medio y sin pasarse del 35 %.
        val p = SonidoDescanso.pitido()
        assertEquals((44_100 * 0.12).toInt() + (44_100 * 0.06).toInt() + (44_100 * 0.16).toInt(), p.size)
        assertTrue(p.maxOf { it.toInt() } <= (Short.MAX_VALUE * 0.35).toInt() + 1)
        val inicioSilencio = (44_100 * 0.12).toInt()
        assertTrue(p.slice(inicioSilencio until inicioSilencio + (44_100 * 0.06).toInt()).all { it.toInt() == 0 })
        // Las rampas: arranca y termina en silencio (no hace clic).
        assertEquals(0, p.first().toInt())
        assertTrue(kotlin.math.abs(p.last().toInt()) < 200)
    }
}
