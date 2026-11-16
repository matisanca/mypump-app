package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Por qué no cuenta una toma y cómo se le dice al alumno (`apps/shared/vectores/presion_no_cuenta.json`), y los textos del aviso
 * del reposo. Gemelo de PresionNoCuentaTests.swift. La regla clínica (5 minutos sentado obligatorios) no cambia: `texto` es lo que
 * ya daba [Presion.evaluarSesion].
 */
class PresionNoCuentaTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("presion_no_cuenta")))
    private val casos = (v["casos"] as ValorJson.Lista).elementos

    @Test fun seRecorreTodoElArchivo() {
        assertEquals(setOf("_", "casos", "propios"), (v as ValorJson.Objeto).campos.keys)
        assertEquals(16, casos.size)
    }

    @Test fun cadaCasoDaElMotivoYElTexto() {
        for (c in casos) {
            val nombre = c["nombre"]?.comoTexto
            val s = Presion.Sesion.desde(c["entrada"]!!)
            val sale = c["sale"]!!
            assertEquals(sale["texto"]?.comoTexto, Presion.evaluarSesion(s).texto, "$nombre: texto")
            val motivos = Presion.motivosNoCuenta(s)
            assertEquals((sale["motivos"] as ValorJson.Lista).elementos.map { it.comoTexto }, motivos, "$nombre: motivos")
            val mensaje = sale["mensaje"]?.comoTexto
            if (mensaje != null) assertEquals(mensaje, TextosPresion.T.noCuentaPor(motivos), "$nombre: mensaje")
            else assertEquals("ninguno", Presion.evaluarSesion(s).texto, "$nombre: sin mensaje solo si cuenta")
        }
    }

    /** Cada motivo, solo: el texto nombra lo que pasó y nada de lo que no pasó (lo que confundió a un alumno que no tomó café). */
    @Test fun cadaMotivoNombraSoloLoSuyo() {
        val propio = mapOf(
            "reposo" to "No esperaste los 5 minutos sentado.",
            "cafeina" to "tomaste café, mate, energizante o preentreno",
            "fumo" to "fumaste o vapeaste",
            "comida" to "comiste",
            "ejercicio" to "Entrenaste en la última hora.",
            "entreno_entre_dosis" to "Entrenaste entre la dosis y la toma.",
        )
        for ((m, frase) in propio) {
            val t = TextosPresion.T.noCuentaPor(listOf(m))
            assertTrue(t.startsWith("Esta toma no cuenta."), t)
            assertTrue(t.endsWith("Hacé otra toma otro día."), t)
            assertTrue(frase in t, "$m: «$t»")
            assertTrue("La próxima" in t, "$m: dice qué hacer la próxima vez")
            for ((otro, f) in propio) if (otro != m) assertFalse(f in t, "$m nombra $otro: «$t»")
            if (m != "cafeina") assertFalse("café" in t, "$m habla de café: «$t»")
        }
        assertEquals("Esta toma no cuenta. Hacé otra toma otro día.", TextosPresion.T.noCuentaPor(emptyList()))
    }

    /** El reposo salteado con el botón es exactamente lo que marca la sesión: no cuenta y dice por qué. */
    @Test fun botonDelReposoSalteado() {
        val base = Presion.Sesion(tipo = "estandar", tomas = listOf(Presion.Toma(orden = 1, posicion = "sentado", sis = 124, dia = 78, pulso = 62)))
        val salteado = base.copy(reposoCumplido = false, temporizadorSalteado = true)
        val ev = Presion.evaluarSesion(salteado)
        assertFalse(ev.cuenta)
        assertEquals("condicion_incumplida", ev.motivoExclusion)
        assertEquals("toma_no_cuenta", ev.texto)
        assertEquals(listOf("reposo"), Presion.motivosNoCuenta(salteado))
        assertEquals(
            "Esta toma no cuenta. No esperaste los 5 minutos sentado. La próxima, quedate sentado y quieto hasta que terminen los 5 minutos. Hacé otra toma otro día.",
            TextosPresion.T.noCuentaPor(Presion.motivosNoCuenta(salteado)),
        )
        // Con los 5 minutos cumplidos sí cuenta y no hay motivo.
        val cumplido = base.copy(reposoCumplido = true, temporizadorSalteado = false)
        assertTrue(Presion.evaluarSesion(cumplido).cuenta)
        assertEquals(emptyList<String>(), Presion.motivosNoCuenta(cumplido))
    }

    /** Los textos del aviso son los del vector, el botón ya no dice que esperó y ninguno invita a saltear. */
    @Test fun textosDelAvisoDelReposo() {
        assertEquals(v["propios"], TextosPresion.A.todos)
        assertFalse("esperé" in TextosPresion.A.reposoSalir.lowercase())
        assertTrue("no cuenta" in TextosPresion.A.reposoAviso)
        assertEquals("Seguir esperando", TextosPresion.A.seguirEsperando)
    }

    /** Las mismas reglas de escritura que el resto de Presión: sin «:», «;», guiones ni palabras vedadas. */
    @Test fun textosSinPalabrasVedadas() {
        val todos = (TextosPresion.A.todos as ValorJson.Objeto).campos.values.mapNotNull { it.comoTexto } +
            casos.mapNotNull { it["sale"]?.get("mensaje")?.comoTexto }
        assertTrue(todos.size >= 17)
        val vedadas = listOf("hipertens", "normal", "riesgo", "promedio de", "tu coach", "tu entrenador", "inteligencia artificial")
        for (s in todos) {
            val m = s.lowercase()
            for (p in vedadas) assertFalse(p in m, "«$s» dice «$p»")
            assertFalse(Regex("\\bia\\b").containsMatchIn(m), "«$s» dice IA")
            assertFalse(":" in s || ";" in s || " - " in s || "—" in s || "–" in s, "«$s» lleva puntuación vedada")
        }
    }
}
