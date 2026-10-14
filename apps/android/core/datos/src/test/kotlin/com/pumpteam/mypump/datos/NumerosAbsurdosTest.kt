package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.PesoCorporal
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource
import org.junit.jupiter.api.Test

/**
 * NumerosAbsurdosTests.swift: todo esto se lee de afuera (la base, la cola, el almacenamiento viejo, las preferencias) y
 * un valor raro no puede cerrar la app ni dejarla en un estado imposible. En Kotlin `toInt()` no cierra nada, pero un
 * 1e20 quedaba como una hora 2147483647. (Los de la migración y de Salud están en sus tests.)
 */
class NumerosAbsurdosTest {
    @Test
    fun rutinaConSemanaGigante() {
        val r = RutinaActiva.desde(Json.parseToJsonElement("""{"id":"r","version":1,"semana_actual":1e19,"estructura":{"dias":[]}}"""))
        assertEquals(1, r.semanaActual)   // no sirve: queda el valor por defecto, como con cualquier otro dato roto
        assertEquals(3, RutinaActiva.desde(Json.parseToJsonElement("""{"id":"r","semana_actual":3.0}""")).semanaActual)
    }

    @ParameterizedTest
    @ValueSource(strings = ["nan", "NaN", "inf", "-Infinity", "1e20", "-1e300", "abc", ""])
    fun aguaConUnValorRaro(valor: String) {
        val h = HabitosHoy().aplicar("vasos_agua", ValorJson.Texto(valor))
        assertTrue(Math.abs(h.vasosAgua.toLong()) <= 1_000_000_000_000_000L)
    }

    @Test
    fun aguaNormal() {
        assertEquals(7, HabitosHoy().aplicar("vasos_agua", ValorJson.Texto("7")).vasosAgua)
        assertEquals(4, HabitosHoy().aplicar("vasos_agua", ValorJson.Numero(4.0)).vasosAgua)
    }

    @Test
    fun recordatorioConHoraImposible() {
        val porDefecto = PreferenciasAvisos.Recordatorio(on = true, hora = 11, min = 0)
        assertEquals(porDefecto, PreferenciasAvisos.leer("""{"check":{"on":true,"hora":1e20,"min":0}}""").check)
        assertEquals(PreferenciasAvisos.Recordatorio(on = false, hora = 11, min = 0), PreferenciasAvisos.leer("""{"check":{"on":false,"hora":25,"min":-3}}""").check)
        assertEquals(porDefecto, PreferenciasAvisos.leer("""{"check":{"on":true,"hora":9.5,"min":1e300}}""").check)
        assertEquals(PreferenciasAvisos.Recordatorio(on = true, hora = 9, min = 30), PreferenciasAvisos.leer("""{"check":{"on":true,"hora":9,"min":30}}""").check)
    }

    @Test
    fun pesoConUnValorAbsurdo() {
        val serie = listOf(PesoCorporal.Punto("2026-10-01", 80.0), PesoCorporal.Punto("2026-10-08", 1e300))
        assertEquals(Int.MAX_VALUE, PesoCorporal.deltaSemanal(serie, "2026-10-08"))   // iOS: 10^15 (su Int es de 64 bits)
    }
}
