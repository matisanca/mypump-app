package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.reglas.ClaveEjercicio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 2.0.3, Entreno (gemelo de Entreno203UITests.swift): el descanso elegido a mano por ejercicio (E2), el aviso de récord al
 * confirmar (E3) y el RIR que arranca en el objetivo de la semana (E4). Una rutina de prueba con un remo (descanso del
 * plan 2:00, RIR 1-2) y un historial inventado de 60 kg × 10.
 */
@RunWith(AndroidJUnit4::class)
class Entreno203UiTest : PruebaUi() {
    private val lugar = "remo-d1-0"

    private fun rutinaConHistorial() {
        servidor.respuestas["mypump_get_rutina_activa"] = """[{"id":"r-203","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1 — ESPALDA","ejercicios":[
              {"id":"$lugar","nombre":"Remo con barra (dorsal)","tipo":"compuesto","descanso_segundos":120,
               "progresion":[{"semana":1,"series":3,"reps":"10","rir":"1-2"}]}]}]}]}}]"""
        servidor.respuestas["mypump_get_historico_por_clave"] =
            """[{"clave":"${ClaveEjercicio.de("Remo con barra (dorsal)")}","registrado_en":"2026-10-01T15:00:00+00:00","peso_kg":60,"reps_realizadas":10,"serie_numero":1,"ejercicio_nombre":"Remo con barra (dorsal)"}]"""
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
        abrirEnLaLista(lugar)
        p.nodo(etiqueta("tabla-series"))
    }

    /** E4: arranca en 1 (el primer número de «1-2»). E3: 62,5 × 10 contra 60 × 10 de la última vez avisa el récord. */
    @Test
    fun elRirArrancaEnElObjetivoYElRecordSeAvisa() {
        rutinaConHistorial()
        p.esperar("RIR 1 preseleccionado") { p.estado(etiqueta("rir-serie-1"))?.startsWith("1") == true }
        p.escribir(etiqueta("campo-reps-1"), "10")
        p.escribir(etiqueta("campo-kg-1"), "62,5")
        p.tocar(etiqueta("confirmar-serie-1"))
        p.esperar("el aviso de récord") { p.textosBajo(etiqueta("aviso-record")).contains("Récord: +2,5 kg") }
        Telefono.captura("203-record-aviso")
        val carga = p.esperar("la serie en el servidor") { servidor.a("mypump_registrar_carga").firstOrNull() }
        assertTrue(carga, carga.contains("\"p_peso\":62.5") && carga.contains("\"p_rir\":1"))
        // Se va solo.
        p.esperarQueNoEste(etiqueta("aviso-record"), ms = 8_000)
        // La segunda con el mismo peso y las mismas reps: ya avisado, no se repite.
        p.tocar(etiqueta("descanso-saltar"))
        p.escribir(etiqueta("campo-reps-2"), "10")
        p.tocar(etiqueta("confirmar-serie-2"))
        p.esperar("2 de 3") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("2 de 3") }
        assertTrue("no se repite", !p.existe(etiqueta("aviso-record")))
    }

    /** E2: elegir 2:15 para este ejercicio; es el que arranca al confirmar, y «Volver al del plan» deja el 2:00. */
    @Test
    fun elDescansoElegidoEsElQueArranca() {
        rutinaConHistorial()
        p.tocar(etiqueta("descanso-ejercicio"))
        p.nodo(etiqueta("hoja-descanso"))
        p.tocar(etiqueta("opcion-descanso-135"))
        p.tocar(etiqueta("guardar-descanso"))
        p.esperarQueNoEste(etiqueta("hoja-descanso"))
        p.esperar("el botón con 2:15") { p.textosBajo(etiqueta("descanso-ejercicio")).contains("2:15") }
        p.tocar(etiqueta("confirmar-serie-1"))   // lo de la última vez, de un toque
        p.nodo(etiqueta("descanso"))
        assertEquals(listOf("Descanso / 2:15"), p.textosBajo(etiqueta("descanso-rotulo")))
        p.tocar(etiqueta("descanso-saltar"))
        p.tocar(etiqueta("descanso-ejercicio"))
        p.tocar(etiqueta("descanso-del-plan"))
        p.esperar("de vuelta al del plan") { p.textosBajo(etiqueta("descanso-ejercicio")).contains("2:00") }
    }
}
