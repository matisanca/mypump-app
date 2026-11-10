package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Reporte del 4-nov: la cinta, tal como la manda el plan (sin duración y con `progresion: []`), pedía reps, kg y RIR y no
 * ofrecía «Sustituir». La cinta como cardio en el día 1 y como calentamiento en el día 2, con cargas viejas de 60 kg × 10 en
 * su clave (el histórico) y una serie de hoy en el servidor. Gemelo de CardioUITests.swift. Capturas `cardio-*`.
 */
@RunWith(AndroidJUnit4::class)
class CardioUiTest : PruebaUi() {
    private val cintaD1 = "cinta-caminata-inclinada-10-min-d1-0"
    private val cintaD2 = "cinta-caminata-inclinada-10-min-d2-0"

    private fun rutinaConCinta() {
        fun cinta(tipo: String, id: String) =
            """{"id":"$id","tipo":"$tipo","nombre":"Cinta (caminata inclinada 10 min)","catalogo_slug":"Walking_Treadmill","progresion":[],"descanso_segundos":0}"""
        val prog = (1..4).joinToString(",") { """{"semana":$it,"series":3,"reps":"10","rir":"1"}""" }
        servidor.respuestas["mypump_get_rutina_activa"] = """[{"id":"r-cardio","version":1,"semana_actual":3,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1","ejercicios":[${cinta("cardio", cintaD1)},
              {"id":"movilidad-d1-1","tipo":"calentamiento","nombre":"Movilidad de hombros con banda","progresion":[],"series":2,"reps":"15","descanso_segundos":0},
              {"id":"remo-d1-2","nombre":"Remo con barra (dorsal)","tipo":"compuesto","descanso_segundos":120,"progresion":[$prog]}]}]},
            {"id":"d2","n":2,"nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[${cinta("calentamiento", cintaD2)},
              {"id":"sentadilla-d2-1","nombre":"Sentadilla con barra","tipo":"compuesto","descanso_segundos":150,"progresion":[$prog]}]}]}
        ]}}]"""
        servidor.respuestas["mypump_get_historico_por_clave"] =
            """[{"clave":"cinta","registrado_en":"2026-10-30T12:00:00Z","peso_kg":60,"reps_realizadas":10,"rir_real":2,"serie_numero":1}]"""
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
    }

    private fun comprobarPorTiempo(lugar: String, nombre: String) {
        abrirEnLaLista(lugar)
        val valor = p.estado(etiqueta("ejercicio-$lugar")) ?: ""
        assertFalse(valor, valor.contains("última vez") || valor.contains("récord") || valor.contains("series de"))
        assertFalse("$nombre: pide series (reps y kg)", p.existe(etiqueta("tabla-series")))
        assertTrue("$nombre: sin «Terminé»", p.existe(etiqueta("termine-ejercicio")))
        assertTrue("$nombre: «Sustituir» apagado", p.habilitado(etiqueta("sustituir")))
        Telefono.captura("cardio-lista-$nombre")
    }

    @Test
    fun laCintaVaPorTiempoComoCardioYComoCalentamientoYSeSustituye() {
        rutinaConCinta()
        comprobarPorTiempo(cintaD1, "cardio")
        // El calentamiento con banda sigue con su tabla de series.
        abrirEnLaLista("movilidad-d1-1")
        p.nodo(etiqueta("tabla-series"))
        // Sustituir: cardio por cardio.
        abrirEnLaLista(cintaD1)
        p.tocar(etiqueta("sustituir"))
        p.nodo(texto("Bicicleta fija"))
        p.nodo(texto("Elíptico"))
        Telefono.captura("cardio-sustituir")
        p.atras()
        p.tocar(etiqueta("dia-d2"))
        // El día nuevo llega con todo cerrado: el abierto del día anterior no se le contagia al de la misma posición.
        p.nodo(etiqueta("ejercicio-$cintaD2"))
        assertFalse("el ejercicio del día nuevo aparece abierto", p.existe(etiqueta("ejercicio-abierto-$cintaD2")))
        comprobarPorTiempo(cintaD2, "calentamiento")
    }
}
