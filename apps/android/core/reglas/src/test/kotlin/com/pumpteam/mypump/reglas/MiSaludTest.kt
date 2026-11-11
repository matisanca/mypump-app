package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.reglas.MiSalud.Bloque
import com.pumpteam.mypump.reglas.MiSalud.Partes
import com.pumpteam.mypump.reglas.MiSalud.Pendientes
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class MiSaludTest {
    @Test
    fun losBloquesVanEnOrdenYSoloSiSeMuestran() {
        assertEquals(listOf(Bloque.CONTROL, Bloque.ESTUDIOS, Bloque.PRESION, Bloque.RECUPERACION), MiSalud.bloques(Partes(true, true, true, true)))
        assertEquals(listOf(Bloque.PRESION, Bloque.RECUPERACION), MiSalud.bloques(Partes(presion = true)))
        assertEquals(listOf(Bloque.ESTUDIOS), MiSalud.bloques(Partes(estudios = true, recuperacion = false)))
        assertEquals(emptyList<Bloque>(), MiSalud.bloques(Partes(recuperacion = false)))
    }

    @Test
    fun sinNingunBloqueNoHayTarjeta() {
        assertNull(MiSalud.tarjeta(Partes(recuperacion = false), Pendientes(estudios = "x", control = true, presion = "y")))
    }

    @Test
    fun sinPendientesDiceQueHayAdentro() {
        val t = MiSalud.tarjeta(Partes(control = true, estudios = true, presion = true), Pendientes())!!
        assertEquals("Control, estudios, presión y recuperación", t.linea)
        assertEquals(0, t.cuenta)
        assertNull(t.bloque)
        assertEquals("Recuperación", MiSalud.tarjeta(Partes(), Pendientes())!!.linea)
        assertEquals("Presión y recuperación", MiSalud.tarjeta(Partes(presion = true), Pendientes())!!.linea)
    }

    @Test
    fun conPendientesCuentaYDiceLoPrimero() {
        val todo = MiSalud.tarjeta(
            Partes(control = true, estudios = true, presion = true),
            Pendientes(estudios = TextosEstudios.ordenNueva, control = true, presion = MiSalud.faltanTomas(2)),
        )!!
        assertEquals(TextosEstudios.ordenNueva, todo.linea)
        assertEquals(3, todo.cuenta)
        assertEquals(Bloque.ESTUDIOS, todo.bloque, "tocarla lleva a lo primero pendiente")
        val soloPresion = MiSalud.tarjeta(Partes(estudios = true, presion = true), Pendientes(presion = MiSalud.faltanTomas(1)))!!
        assertEquals("Te falta 1 toma de presión", soloPresion.linea)
        assertEquals(Bloque.PRESION, soloPresion.bloque)
        assertEquals(1, soloPresion.cuenta)
        val control = MiSalud.tarjeta(Partes(control = true, estudios = true), Pendientes(control = true))!!
        assertEquals(MiSalud.CONTROL_CERCA, control.linea)
    }

    @Test
    fun loPendienteDeUnaParteQueNoEstaNoCuenta() {
        val t = MiSalud.tarjeta(Partes(), Pendientes(estudios = TextosEstudios.estudioParaHacer, control = true, presion = MiSalud.REPETIR_PRESION))!!
        assertEquals(0, t.cuenta)
        assertEquals("Recuperación", t.linea)
    }

    @Test
    fun losTextosNoNombranNadaClinico() {
        val todos = listOf(MiSalud.TITULO, MiSalud.CONTROL_CERCA, MiSalud.REPETIR_PRESION, MiSalud.PREPARAR_PRESION, MiSalud.VER_PRESION, MiSalud.ABRE, MiSalud.faltanTomas(3))
        for (t in todos) for (prohibido in listOf("ciclo", "entrenador", "RIR", "IA", "testosterona")) {
            assert(!t.contains(prohibido)) { "$t dice $prohibido" }
        }
        assertEquals("Mi salud", MiSalud.TITULO)
    }

    @Test
    fun masCosasDebajoDeLaLinea() {
        assertEquals(null, MiSalud.masCosas(0))
        assertEquals(null, MiSalud.masCosas(1))
        assertEquals("Y 1 cosa más", MiSalud.masCosas(2))
        assertEquals("Y 2 cosas más", MiSalud.masCosas(3))
    }
}
