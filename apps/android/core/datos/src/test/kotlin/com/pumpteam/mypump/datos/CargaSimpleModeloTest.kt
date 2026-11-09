package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CargaSimple
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.claveAumento
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La carga simple contra la cola y el disco de verdad: lo que no puede perderse ni falsearse (gemelo de CargaSimpleModeloTests.swift). */
class CargaSimpleModeloTest {
    private val lugar = "pre-d1-0"
    private val clave = ClaveEjercicio.de("Press banca con barra")

    private fun igual(a: Any?, b: Any?, m: String = "") = assertEquals(a, b, m)

    private fun rutina(rir: String = "2", semana: Int = 2, reps2: String = "8"): RutinaActiva {
        val est = """{"semanas_total":12,"dias":[{"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"B1","ejercicios":[{"id":"pre-d1-0","nombre":"Press banca con barra","tipo":"compuesto","descanso_segundos":120,"progresion":[{"semana":1,"series":4,"reps":"10","rir":"$rir"},{"semana":2,"series":4,"reps":"$reps2","rir":"$rir"}]}]}]}]}"""
        return RutinaActiva.desde(ValorJson.parsear("""{"id":"r1","version":1,"semana_actual":$semana,"tiene_siguiente":false,"estructura":$est}""").aJson())
    }

    /** 80 kg × 10 hace una semana; opcionalmente una fila de HOY (la que el historial trae al recargar). */
    private fun historial(b: Banco, hoyKg: Double? = null) {
        val f = (1..4).map { """{"clave":"$clave","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":0,"serie_numero":$it,"notas":null,"ejercicio_nombre":"Press banca con barra"}""" }.toMutableList()
        hoyKg?.let { f.add(0, """{"clave":"$clave","registrado_en":"2026-10-14T17:00:00Z","peso_kg":$it,"reps_realizadas":8,"rir_real":0,"serie_numero":1,"notas":null,"ejercicio_nombre":"Press banca con barra"}""") }
        b.servidor.cuando("get_historico_por_clave", "[${f.joinToString(",")}]")
    }

    private suspend fun modelo(b: Banco, r: RutinaActiva = rutina()): ModeloEntreno = b.modelo(r).also { it.cargar() }

    private suspend fun cargasEnCola(b: Banco): List<ValorJson> = b.cola.operaciones().filter { it.kind == "carga" }.map { it.payload }

    private suspend fun ok(m: ModeloEntreno, i: Int) = m.okSerie(lugar, i, venceEn = null) { true }

    private fun serie(m: ModeloEntreno, i: Int) = m.dia.value.ejercicios.getValue(lugar).series[i]

    @Test fun okDentroDeLaVentanaNoSaleHastaQueVence() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        igual(ModeloEntreno.ResultadoOK.REGISTRADA, ok(m, 0))
        assertTrue(serie(m, 0).confirmada)
        igual("80", serie(m, 0).kg)
        assertTrue(cargasEnCola(b).isEmpty(), "todavía se puede deshacer")
        m.vaciarDeshacer()
        igual(1, cargasEnCola(b).size)
    }

    @Test fun laVentanaVenceSola() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        m.okSerie(lugar, 0, venceEn = 0.02) { true }
        delay(300)
        igual(1, cargasEnCola(b).size)
        igual(null, m.deshacible.value)
    }

    @Test fun deshacerEsDeVerdadNoEscribeYAlRecargarNoVuelve() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        ok(m, 0)
        m.deshacerOK()
        assertFalse(serie(m, 0).confirmada)
        igual("", serie(m, 0).reps)
        assertFalse(m.descanso.value.visible)
        m.vaciarDeshacer()
        assertTrue(cargasEnCola(b).isEmpty(), "deshecha no se registra")
        b.servidor.cuando("get_sesion_dia", sesionJson("s1", semana = 2))
        m.restaurarSesion()
        assertFalse(serie(m, 0).confirmada, "no vuelve como fantasma")
    }

    @Test fun deshacerLaUltimaSerieNoDejaElEjercicioCompleto() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        for (i in 0 until 3) {
            ok(m, i)
            m.vaciarDeshacer()
            b.reloj.ms += 120_000
        }
        ok(m, 3)
        igual("completo", m.dia.value.estado(lugar))
        m.deshacerOK()
        igual("pendiente", m.dia.value.estado(lugar))
        assertFalse(m.dia.value.ejercicios.getValue(lugar).completo)
        assertTrue(b.cola.operaciones().none { it.kind == "estado" }, "el «completo» no llegó a salir")
    }

    @Test fun siLaAppMuereEnLaVentanaLaSerieNoSePierde() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        ok(m, 0)
        val m2 = modelo(b)   // relanzar: otro modelo con el mismo disco
        igual(1, cargasEnCola(b).size, "se recupera del disco")
        assertTrue(serie(m2, 0).confirmada)
        modelo(b)
        igual(1, cargasEnCola(b).size, "y no se manda dos veces")
    }

    /** Tirar para actualizar dentro de la ventana: el OK se cierra antes de leer y no queda un Deshacer que ya no deshace. */
    @Test fun refrescarEnLaVentanaNoDejaUnDeshacerFantasma() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        ok(m, 0)
        m.cargar()
        igual(null, m.deshacible.value)
        m.deshacerOK()
        igual(1, cargasEnCola(b).size)
        assertTrue(serie(m, 0).confirmada, "lo que está en la cola sigue hecho en pantalla")
    }

    @Test fun relanzarTrasAceptarNoVuelveASugerir() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        igual(CargaSimple.Aumento.Sugerido(80.0, 82.5), m.cargaSimple(lugar)?.aumento)
        m.cambiarCarga(lugar) { it.aceptarAumento() }
        igual(82.5, m.cargaSimple(lugar)?.carga)
        historial(b, hoyKg = 82.5)   // al recargar, el historial trae también lo de hoy: no puede sugerir 85
        val m2 = modelo(b)
        igual(CargaSimple.Aumento.Aceptado(80.0, 82.5), m2.cargaSimple(lugar)?.aumento)
        igual(82.5, m2.cargaSimple(lugar)?.carga)
    }

    @Test fun dejarLaSugerenciaTampocoVuelveAlRelanzar() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        modelo(b).cambiarCarga(lugar) { it.descartarAumento() }
        val m2 = modelo(b)
        igual(CargaSimple.Aumento.Descartado, m2.cargaSimple(lugar)?.aumento)
        igual(80.0, m2.cargaSimple(lugar)?.carga)
    }

    @Test fun aMedioEjercicioNoSePierdeNada() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(reps2 = "10"))
        m.cambiarCarga(lugar) {
            it.moverCarga(1)
            it.ajustarReps(1, 2)
            it.usarMismoPeso(false)
            it.fijarKg(2, 75.0)
        }
        val c = modelo(b, rutina(reps2 = "10")).cargaSimple(lugar)!!
        igual(82.5, c.carga)
        assertFalse(c.mismoPeso)
        igual(12, c.reps(1))
        igual(75.0, c.series[2].kg)
    }

    @Test fun laSemanaQueVieneNoHeredaLoDeEsta() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        modelo(b).cambiarCarga(lugar) { it.aceptarAumento() }
        igual(null, modelo(b, rutina(semana = 3)).dia.value.cargas[lugar])
    }

    @Test fun elMismoEjercicioNoSubeDosVecesEnLaSemana() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b)
        m.cambiarCarga(lugar) { it.aceptarAumento() }
        m.dia.value.cargas = emptyMap()   // otro lugar con el mismo ejercicio en la misma semana: ya subió
        assertTrue(m.dia.value.claveAumento(lugar) in m.dia.value.aumentosSemana)
        igual(CargaSimple.Aumento.NoCorresponde, m.cargaSimple(lugar)?.aumento)
    }

    @Test fun subirNoReescribeLoHechoYLaSiguienteVaConLaNueva() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(reps2 = "10"))
        ok(m, 0)
        b.reloj.ms += 120_000
        m.cambiarCarga(lugar) { it.moverCarga(1) }
        ok(m, 1)
        m.vaciarDeshacer()
        igual(listOf(80.0, 82.5), cargasEnCola(b).mapNotNull { it["datos"]?.get("peso")?.comoNumero })
    }

    @Test fun guardiaElOKApuradoPideOtroToqueSinFrenarElDescanso() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(reps2 = "10"))
        ok(m, 0)
        b.reloj.ms += 3_000
        igual(ModeloEntreno.ResultadoOK.GUARDIA, ok(m, 1))
        assertFalse(serie(m, 1).confirmada)
        assertTrue(m.descanso.value.visible, "el descanso sigue corriendo")
        b.reloj.ms += 300
        igual(ModeloEntreno.ResultadoOK.GUARDIA, ok(m, 1), "un doble toque no la vence")
        b.reloj.ms += 900
        igual(ModeloEntreno.ResultadoOK.REGISTRADA, ok(m, 1))
        m.vaciarDeshacer()
        b.reloj.ms += 10_000
        igual(ModeloEntreno.ResultadoOK.REGISTRADA, ok(m, 2))
    }

    @Test fun noRegistradaNoQuedaComoSiLaHubieraTipeado() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(reps2 = "10"))
        m.cambiarCarga(lugar) { it.fijarCarga(9000.0) }
        igual(ModeloEntreno.ResultadoOK.NO_REGISTRADA, ok(m, 0))
        val s = serie(m, 0)
        assertFalse(s.confirmada)
        igual("" to "", s.reps to s.kg)
        assertFalse(s.aviso.isNullOrEmpty())
    }

    @Test fun elRirDelPlanNuncaSeCopia() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(rir = "2-3"))
        ok(m, 0)
        m.vaciarDeshacer()
        igual(ValorJson.Numero(0.0), cargasEnCola(b).first()["datos"]?.get("rir"))
    }

    @Test fun corregirReescribeEsaSerieSinDesmarcarla() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(reps2 = "10"))
        ok(m, 0)
        m.vaciarDeshacer()
        val antes = cargasEnCola(b).size
        m.editarSerie(lugar, 0)
        igual(ModeloEntreno.SerieEnCorreccion(lugar, 0), m.corrigiendo.value)
        assertTrue(serie(m, 0).confirmada)
        igual(ModeloEntreno.ResultadoCorreccion.SinCambios, m.guardarCorreccion(10, 80.0) { true }, "sin cambios no escribe")
        igual(antes, cargasEnCola(b).size)
        m.editarSerie(lugar, 0)
        igual(ModeloEntreno.ResultadoCorreccion.Guardada, m.guardarCorreccion(12, 77.5) { true })
        val filas = cargasEnCola(b)
        igual(antes, filas.size, "misma clave de cola: la reemplaza")
        igual(12.0, filas.last()["datos"]?.get("reps")?.comoNumero)
        igual(77.5, filas.last()["datos"]?.get("peso")?.comoNumero)
        assertTrue(serie(m, 0).confirmada)
        igual(null, m.corrigiendo.value)
    }

    @Test fun cerrarElDiaMandaLoDemoradoAntes() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a, ejecutar = true).also(::historial)
        b.servidor.cuando("registrar_carga", "null")
        b.servidor.cuando("get_sesion_dia", sesionJson("s1", semana = 2))
        val m = modelo(b)
        ok(m, 0)
        m.cerrarDia("")
        igual(1, b.servidor.llamadas("registrar_carga").size)
    }

    @Test fun laPreparacionUsaLaCargaYNoEsUnaSerie() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a).also(::historial)
        val m = modelo(b, rutina(reps2 = "10"))
        m.cambiarCarga(lugar) { it.moverCarga(1) }
        val series = m.preparacion(lugar)
        assertTrue(series.isNotEmpty())
        assertTrue(series.all { (it.kg ?: 0.0) < 82.5 }, "la preparación no hereda la carga como serie")
        igual(4, m.dia.value.ejercicios.getValue(lugar).series.size, "no suma series efectivas")
    }

    @Test fun sinHistorialTodaviaLaCargaNoQuedaVacia() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a)
        val m = modelo(b, rutina(reps2 = "10"))
        m.cambiarCarga(lugar) { it.ajustarReps(0, 1) }   // tocó el dial antes de que llegara el historial
        historial(b)
        m.dia.value.historial = m.dia.value.historial - lugar
        m.pedirHistorial(lugar)
        igual(80.0, m.cargaSimple(lugar)?.carga)
    }

    /** Cambiar el ejercicio borra su carga, y eso tiene que quedar en disco: si no, al relanzar el OK registra el kilo del anterior. */
    @Test fun sustituirBorraLaCargaTambienDelDisco() = enUnHilo { a: CoroutineScope ->
        val b = Banco(a)
        val otro = "jal-d1-0"
        val fila = """{"clave":"${ClaveEjercicio.de("Jalón al pecho")}","ejercicio_id":"$otro","registrado_en":"2026-10-07T18:00:00Z","peso_kg":80,"reps_realizadas":10,"rir_real":0,"serie_numero":1,"notas":null,"ejercicio_nombre":"Jalón al pecho"}"""
        b.servidor.cuando("get_historico_por_clave", "[$fila]")
        val m = b.modelo().also { it.cargar() }
        m.pedirHistorial(otro)
        m.cambiarCarga(otro) { it.moverCarga(1) }
        assertTrue(otro in m.dia.value.cargas)
        m.sustituir(otro, m.sustitutos(otro).first(), fijar = false)
        assertFalse(otro in m.dia.value.cargas)
        assertFalse(otro in b.modelo().also { it.cargar() }.dia.value.cargas, "relanzar no trae la carga del ejercicio anterior")
    }
}
