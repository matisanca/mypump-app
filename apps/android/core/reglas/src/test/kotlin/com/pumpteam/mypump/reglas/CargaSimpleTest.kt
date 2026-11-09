package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.Progresion
import com.pumpteam.mypump.reglas.Preparacion.Equipo
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La carga simple: lo que no puede fallar (qué se registra). Lo del OK de verdad lo prueba `CargaSimpleModeloTest` (gemelo de CargaSimpleTests.swift). */
class CargaSimpleTest {
    private val t0 = 1_800_000_000_000.0
    private fun igual(a: Any?, b: Any?, m: String = "") = assertEquals(a, b, m)

    private enum class R { REGISTRADA, GUARDIA, FALTAN_DATOS }

    private fun CargaSimple.confirmar(i: Int, ahora: Double, insistio: Boolean = false): R = when (val r = evaluarOK(i, ahora, insistio)) {
        CargaSimple.Evaluacion.FaltanDatos -> R.FALTAN_DATOS
        CargaSimple.Evaluacion.Guardia -> R.GUARDIA
        is CargaSimple.Evaluacion.Lista -> {
            series = series.mapIndexed { n, x -> if (n == i) x.copy(reps = r.reps, kg = r.kg, confirmada = true, variante = varianteActual) else x }
            anotarOK(ahora)
            R.REGISTRADA
        }
    }

    private fun ej(semanas: List<Pair<Int, String>>, nombre: String = "Press banca con barra") = Ejercicio(
        id = "x", nombre = nombre, tipo = "compuesto",
        progresion = semanas.mapIndexed { i, s -> Progresion(semana = i + 1, series = s.first, reps = s.second) },
    )

    private val r4 = CargaSimple.Referencia(10, 80.0)
    private val refs = listOf(r4, r4, CargaSimple.Referencia(9, 80.0), CargaSimple.Referencia(8, 80.0))
    private fun normal(g: Double = 0.0) = CargaSimple(ej(listOf(4 to "10", 4 to "10", 4 to "10")), 2, refs, Equipo.BARRA, recordKg = 80.0, guardiaMs = g * 1000)
    private fun todas(s: CargaSimple) = (0 until 4).map { s.reps(it) }

    @Test fun laBaseEsLaVezPasadaPorSerie() {
        val s = normal()
        igual(80.0, s.carga)
        igual(listOf(10, 10, 9, 8), todas(s))
        igual(CargaSimple.OrigenBase.ULTIMA_VEZ, s.base(2).origen)
    }

    @Test fun cargaUnicaSinVolverACargarla() {
        val s = normal()
        s.moverCarga(1)
        for (i in 0 until 4) igual(R.REGISTRADA, s.confirmar(i, t0))
        igual(listOf(82.5, 82.5, 82.5, 82.5), s.series.map { it.kg })
    }

    @Test fun conOtraCargaLasRepsVuelvenAlPlan() {
        val s = normal()
        s.moverCarga(1)
        igual(listOf(10, 10, 10, 10), todas(s))
        igual(CargaSimple.OrigenBase.PLAN, s.base(3).origen)
    }

    @Test fun subirNoReescribeLasHechas() {
        val s = normal()
        s.confirmar(0, t0)
        s.moverCarga(1)
        igual(80.0, s.series[0].kg)
        igual(82.5, s.series[1].kg)
        igual(1, s.hechasConOtraCarga)
        igual(listOf(0), s.aplicarCargaALasHechas())
        igual(82.5, s.series[0].kg)
    }

    @Test fun loMarcadoNoSePisaAlCambiarCarga() {
        val s = normal()
        s.ajustarReps(0, 2)
        s.moverCarga(1)
        igual(12, s.reps(0))
    }

    @Test fun masRepsQueElPlanSiempreVale() {
        val s = normal()
        s.ajustarReps(0, 6)
        igual(R.REGISTRADA, s.confirmar(0, t0))
        igual(16, s.reps(0))
    }

    @Test fun aumentoSoloSiElPlanBajaLasRepsYNuncaEnCalibracion() {
        val baja = CargaSimple(ej(listOf(4 to "10", 4 to "8")), 2, refs, Equipo.BARRA)
        igual(CargaSimple.Aumento.Sugerido(80.0, 82.5), baja.aumento)
        igual(80.0, baja.carga, "sugerido: no sube solo")
        igual(CargaSimple.Aumento.NoCorresponde, CargaSimple(ej(listOf(4 to "10", 4 to "10")), 2, refs, Equipo.BARRA).aumento)
        igual(CargaSimple.Aumento.NoCorresponde, CargaSimple(ej(listOf(4 to "10", 4 to "8")), 1, refs, Equipo.BARRA).aumento)
        igual(CargaSimple.Aumento.NoCorresponde, CargaSimple(ej(listOf(3 to "10", 4 to "8")), 2, refs, Equipo.BARRA).aumento)
    }

    @Test fun pasoSegunEquipo() {
        igual(82.5, AumentoCarga.mover(80.0, 1, Equipo.BARRA))
        igual(65.0, AumentoCarga.mover(60.0, 1, Equipo.MAQUINA))
        igual(22.0, AumentoCarga.mover(21.0, 1, Equipo.MANCUERNA))
        igual(7.0, AumentoCarga.mover(8.0, -1, Equipo.MANCUERNA))
    }

    @Test fun modaUnaSerieConMenosNoCorreLaBase() {
        igual(80.0, AumentoCarga.moda(listOf(80.0, 80.0, 80.0, 75.0)))
        igual(80.0, AumentoCarga.moda(listOf(80.0, 75.0)))
        val a = CargaSimple.Referencia(10, 60.0)
        val s = CargaSimple(ej(listOf(4 to "10", 4 to "10")), 2, listOf(a, a, CargaSimple.Referencia(9, 60.0), CargaSimple.Referencia(10, 55.0)), Equipo.MAQUINA)
        igual(listOf(60.0, 60.0, 60.0, 60.0), s.series.map { it.kg })
        s.usarMismoPeso(false)
        igual(listOf(60.0, 60.0, 60.0, 55.0), s.series.map { it.kg })
    }

    @Test fun primeraVezSinCargaNoHayOK() {
        val s = CargaSimple(ej(listOf(3 to "10-12")), 1, emptyList(), Equipo.BARRA)
        assertFalse(s.puedeConfirmar(0))
        s.fijarCarga(60.0)
        igual(12, s.reps(0))
        assertTrue(s.puedeConfirmar(0))
    }

    @Test fun amrapHayQueMarcar() {
        val s = CargaSimple(ej(listOf(3 to "máx", 3 to "máx"), nombre = "Lagartijas"), 2, listOf(CargaSimple.Referencia(20, null)), Equipo.OTRO)
        assertTrue(s.sinKg)
        assertFalse(s.puedeConfirmar(0))
        s.ajustarReps(0, 1)
        igual(21, s.reps(0))
        assertTrue(s.puedeConfirmar(0))
    }

    @Test fun guardiaRafagaSinTocarPideOtroToque() {
        val s = normal(10.0)
        igual(R.REGISTRADA, s.confirmar(0, t0))
        igual(R.GUARDIA, s.confirmar(1, t0 + 3000))
        assertFalse(s.series[1].confirmada)
        igual(R.REGISTRADA, s.confirmar(1, t0 + 4000, insistio = true))
        s.ajustarReps(2, -1)
        igual(R.REGISTRADA, s.confirmar(2, t0 + 5000), "si tocó el dial, miró")
        igual(R.REGISTRADA, s.confirmar(3, t0 + 120000))
    }

    @Test fun guardiaSumarYRestarLoMismoNoCuentaComoMirar() {
        val s = normal(10.0)
        s.confirmar(0, t0)
        s.ajustarReps(1, 1)
        s.ajustarReps(1, -1)
        igual(R.GUARDIA, s.confirmar(1, t0 + 3000))
    }

    @Test fun varianteLasHechasNoSeMezclan() {
        val s = normal()
        s.varianteActual = "Prono"
        s.confirmar(0, t0)
        s.varianteActual = "Supino"
        s.moverCarga(1)
        igual(0, s.hechasConOtraCarga)
        igual(emptyList<Int>(), s.aplicarCargaALasHechas())
        igual("Prono", s.series[0].variante)
    }

    @Test fun cambiarlasTambienSeVaAlConfirmarLaSiguiente() {
        val s = normal()
        s.confirmar(0, t0)
        s.moverCarga(-1)
        igual(1, s.hechasConOtraCarga)
        s.confirmar(1, t0 + 100000)
        igual(0, s.hechasConOtraCarga, "bajar por fatiga no ofrece reescribir lo anterior")
    }

    @Test fun aumentoSeInvalidaSiLaCargaCambioAMano() {
        val s = CargaSimple(ej(listOf(4 to "10", 4 to "8")), 2, refs, Equipo.BARRA)
        s.moverCarga(2)
        igual(CargaSimple.Aumento.Descartado, s.aumento)
        igual(85.0, s.carga)
    }

    @Test fun aumentoConPesoPorSerieSubeLasQueFaltan() {
        val s = CargaSimple(ej(listOf(4 to "10", 4 to "8")), 2, refs, Equipo.BARRA)
        s.usarMismoPeso(false)
        s.aceptarAumento()
        igual(listOf(82.5, 82.5, 82.5, 82.5), s.series.map { it.kg })
    }

    @Test fun retildarSinCargaTomaLaPrimeraConPeso() {
        val s = CargaSimple(ej(listOf(2 to "10")), 1, emptyList(), Equipo.BARRA)
        s.usarMismoPeso(false)
        s.fijarKg(0, 50.0)
        s.usarMismoPeso(true)
        igual(50.0, s.carga)
        igual(listOf(50.0, 50.0), s.series.map { it.kg })
    }

    @Test fun modaIgnoraCeros() = igual(40.0, AumentoCarga.moda(listOf(0.0, 0.0, 40.0)))

    @Test fun elEstadoVuelveIgualDelDisco() {
        val s = normal()
        s.moverCarga(1)
        s.confirmar(0, t0)
        s.ajustarReps(1, 2)
        val e = s.estado
        igual(e, CargaSimple.Estado.desde(e.aValor()))
    }
}
