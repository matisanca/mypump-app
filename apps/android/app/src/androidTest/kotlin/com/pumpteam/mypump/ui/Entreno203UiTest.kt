package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.reglas.ClaveEjercicio
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 2.0.3, Entreno (gemelo de Entreno203UITests.swift): el descanso elegido a mano por ejercicio (E2), el aviso de récord al
 * confirmar (E3) y el RIR del plan que se guarda sin mostrarlo (reemplaza a E4). Una rutina de prueba con un remo (descanso del
 * plan 2:00, RIR 1-2) y un historial inventado de 60 kg × 10.
 */
@RunWith(AndroidJUnit4::class)
class Entreno203UiTest : PruebaUi() {
    private val lugar = "remo-d1-0"

    private val curl = "curl-d1-1"

    /** Un remo con barra (compuesto, principal) y un curl con barra Z (monoarticular); con historial, 60 kg × 10 en los dos. */
    private fun rutina(historial: Boolean = true, oscuro: Boolean = false) {
        servidor.respuestas["mypump_get_rutina_activa"] = """[{"id":"r-203","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1 — ESPALDA","ejercicios":[
              {"id":"$lugar","nombre":"Remo con barra (dorsal)","tipo":"compuesto","descanso_segundos":120,
               "progresion":[{"semana":1,"series":3,"reps":"10","rir":"1-2"}]},
              {"id":"$curl","nombre":"Curl con barra Z","tipo":"aislamiento","descanso_segundos":90,
               "progresion":[{"semana":1,"series":3,"reps":"12","rir":"0"}]}]}]}]}}]"""
        servidor.respuestas["mypump_get_historico_por_clave"] = if (!historial) "[]" else listOf("Remo con barra (dorsal)", "Curl con barra Z")
            .joinToString(",", "[", "]") {
                """{"clave":"${ClaveEjercicio.de(it)}","registrado_en":"2026-10-01T15:00:00+00:00","peso_kg":60,"reps_realizadas":10,"serie_numero":1,"ejercicio_nombre":"$it"}"""
            }
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        if (oscuro) Telefono.modoNoche(true)
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
    }

    private fun rutinaConHistorial() {
        rutina()
        abrirEnLaLista(lugar)
        p.nodo(etiqueta("tabla-series"))
    }

    /** Deja el bloque de preparación cerca de arriba de la pantalla antes de una captura. */
    private fun verBloque() {
        val alto = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.heightPixels
        repeat(3) {
            val n = p.nodo(etiqueta("bloque-preparacion"))
            val arriba = p.enPrincipal { n.boundsInRoot.top }
            val d = arriba - alto * 0.18f
            if (kotlin.math.abs(d) < alto * 0.04f) return
            p.desplazar(etiqueta("entreno-lista"), d)
        }
    }

    /** Lo que lee TalkBack de la fila (su descripción, el primer texto bajo la etiqueta). */
    private fun fila(i: Int): String = p.textosBajo(etiqueta("preparacion-$i")).first()

    /**
     * E1: el remo con barra (primer compuesto de su músculo y principal) lleva calentamiento en barra sola, dos
     * aproximaciones y la potenciación opcional con el kg de la última vez; tocar una fila arranca el descanso de 30 s y la
     * deja hecha; el kg sigue en vivo al de la primera efectiva; «Ocultar» lo colapsa y se recuerda.
     */
    private fun preparacionDelCompuesto(sufijo: String) {
        rutina(oscuro = sufijo == "oscuro")
        abrirEnLaLista(lugar)
        p.nodo(etiqueta("bloque-preparacion"))
        assertTrue(fila(1), fila(1).startsWith("Calentamiento") && fila(1).contains("Barra sola"))
        assertTrue(fila(2), fila(2).startsWith("Aproximación 1") && fila(2).contains("35 kilos"))
        assertTrue(fila(3), fila(3).startsWith("Aproximación 2") && fila(3).contains("50 kilos"))
        assertTrue(fila(4), fila(4).startsWith("Potenciación (opcional)") && fila(4).contains("65 kilos"))
        assertTrue("sin el título de las efectivas", p.existe(texto("Series efectivas")))
        assertEquals(listOf("30 s de descanso entre cada una · no se anotan"), p.textosBajo(etiqueta("leyenda-preparacion")))
        verBloque()
        Telefono.captura("v2-compuesto-con-kg-$sufijo")

        p.tocar(etiqueta("preparacion-1"))
        p.esperar("la 1 hecha") { fila(1).endsWith("hecha").takeIf { it } }
        p.tocar(etiqueta("preparacion-2"))
        p.esperar("la 2 hecha") { fila(2).endsWith("hecha").takeIf { it } }
        p.esperar("el descanso de 0:30") { p.textosBajo(etiqueta("descanso-en-tarjeta")).any { it.contains("0:30") }.takeIf { it } }
        p.tocar(etiqueta("saltar-descanso"))
        verBloque()
        Telefono.captura("v2-dos-tocadas-$sufijo")
        // Tocarla de nuevo la desmarca.
        p.tocar(etiqueta("preparacion-2"))
        p.esperar("la 2 sin hacer") { (!fila(2).endsWith("hecha")).takeIf { it } }

        // El kg en vivo: 62,5 en la primera efectiva → la aproximación al 60 % pasa a 37,5.
        fijarCarga("62,5")
        p.esperar("37,5 en la aproximación 1") { fila(2).contains("37,5 kilos").takeIf { it } }

        // «Ocultar» y «Mostrar».
        p.tocar(etiqueta("ocultar-preparacion"))
        p.esperarQueNoEste(etiqueta("preparacion-1"))
        assertTrue(p.existe(texto("Calentamiento y aproximación · 4")))
        verBloque()
        Telefono.captura("v2-colapsado-$sufijo")
        p.tocar(etiqueta("ocultar-preparacion"))
        p.nodo(etiqueta("preparacion-1"))
    }

    /** E1: el curl (monoarticular) lleva una sola aproximación; sin historial, solo reps y el texto de la primera vez; el «?». */
    private fun monoarticularYSinKg(sufijo: String) {
        rutina(oscuro = sufijo == "oscuro")
        abrirEnLaLista(curl)
        p.nodo(etiqueta("bloque-preparacion"))
        assertTrue(fila(1), fila(1).startsWith("Aproximación"))
        assertTrue("el monoarticular lleva una sola", !p.existe(etiqueta("preparacion-2")))
        verBloque()
        Telefono.captura("v2-monoarticular-$sufijo")
    }

    private fun sinKgYAyuda(sufijo: String) {
        rutina(historial = false, oscuro = sufijo == "oscuro")
        abrirEnLaLista(lugar)
        p.nodo(etiqueta("bloque-preparacion"))
        assertEquals(
            listOf("Usalas para encontrar tu peso de trabajo · 30 s entre cada una"),
            p.textosBajo(etiqueta("leyenda-preparacion")),
        )
        assertTrue(fila(2), fila(2).contains("repeticiones") && !fila(2).contains("kilos"))
        verBloque()
        Telefono.captura("v2-sin-kg-$sufijo")
        p.tocar(etiqueta("ayuda-preparacion"))
        p.nodo(etiqueta("hoja-ayuda-preparacion"))
        p.nodo(texto("Antes de las efectivas"))
        p.quieto(800)
        Telefono.captura("v2-ayuda-$sufijo")
        p.tocar(etiqueta("listo-ayuda-preparacion"))
        p.esperarQueNoEste(etiqueta("hoja-ayuda-preparacion"))
    }

    @Test fun preparacionDelCompuestoClaro() = preparacionDelCompuesto("claro")
    @Test fun preparacionDelCompuestoOscuro() = preparacionDelCompuesto("oscuro")
    @Test fun preparacionMonoarticularClaro() = monoarticularYSinKg("claro")
    @Test fun preparacionMonoarticularOscuro() = monoarticularYSinKg("oscuro")
    @Test fun preparacionSinKgYAyudaClaro() = sinKgYAyuda("claro")
    @Test fun preparacionSinKgYAyudaOscuro() = sinKgYAyuda("oscuro")

    /** 2.3.0: todo al fallo; el RIR del plan (1-2) no se copia, va 0. E3: 62,5 × 10 contra 60 × 10 de la última vez avisa el récord. */
    @Test
    fun elRirDelPlanSeGuardaYElRecordSeAvisa() {
        rutinaConHistorial()
        assertEquals(listOf("Al fallo"), p.textosBajo(etiqueta("leyenda-rir")))
        fijarCarga("62,5")
        // Con otra carga la base es la del plan: para el récord (más kilo con las mismas reps) tienen que ser las 10.
        fijarReps(10)
        // Sin `darOK`: el aviso dura 3 s y en un emulador chico su espera se los come.
        p.tocar(etiqueta("ok-serie"))
        p.esperar("el aviso de récord") { p.textosBajo(etiqueta("aviso-record-panel")).contains("Récord: +2,5 kg") }
        Telefono.captura("203-record-aviso")
        val carga = p.esperar("la serie en el servidor") { servidor.a("mypump_registrar_carga").firstOrNull() }
        assertTrue(carga, carga.contains("\"p_peso\":62.5") && carga.contains("\"p_rir\":0"))
        // Se va solo.
        p.esperarQueNoEste(etiqueta("aviso-record-panel"), ms = 8_000)
        // La segunda con el mismo peso y las mismas reps: ya avisado, no se repite.
        p.tocar(etiqueta("saltar-descanso"))
        darOK()
        p.esperar("2 de 3") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("2 de 3") }
        assertTrue("no se repite", !p.existe(etiqueta("aviso-record-panel")))
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
        darOK()   // lo de la última vez, de un toque
        p.esperar("el descanso de 2:15") { p.textosBajo(etiqueta("descanso-en-tarjeta")).any { it.contains("2:15") }.takeIf { it } }
        p.tocar(etiqueta("saltar-descanso"))
        p.tocar(etiqueta("descanso-ejercicio"))
        p.tocar(etiqueta("descanso-del-plan"))
        p.esperar("de vuelta al del plan") { p.textosBajo(etiqueta("descanso-ejercicio")).contains("2:00") }
    }
}
