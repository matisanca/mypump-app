package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ModeloApp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Dieta en modo lectura (DIE-01..04): el objetivo con sus macros y el respaldo, las opciones A-D por comida y los
 * alimentos. Los números son los de la demo de la web (los mismos que muestra iOS) y los de la cuenta grabada.
 */
@RunWith(AndroidJUnit4::class)
class DietaUiTest : PruebaUi() {
    private fun demoEnDieta() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("dieta-cabecera"))
    }

    @Test
    fun laDemoMuestraElObjetivoLasOpcionesYLosAlimentos() {
        demoEnDieta()
        // DIE-03/07 (D25): lo consumido contra el objetivo (sin `macros_target`, la suma de las opciones A), por macro.
        assertEquals("0 de 2.454 kcal", p.estado(etiqueta("consumido-kcal")))
        p.nodo(texto("de 2.454 kcal"))
        // Supuesto de pantalla: en una cabecera angosta (720×1280, o con letra grande) los macros van en tres columnas debajo
        // del anillo («0 g» y «de 209 g», `ColumnaMacro`); con lugar, en filas al lado («0 / 209 g»). Los tres van en la
        // misma forma.
        val enFilas = p.existe(texto("0 / 209 g"))
        for ((nombre, objetivo) in listOf("Proteínas" to 209, "Carbos" to 272, "Grasas" to 58)) {
            p.nodo(texto(nombre))
            p.nodo(texto(if (enFilas) "0 / $objetivo g" else "de $objetivo g"))
        }
        p.nodo(texto("Tocá «Comí» en cada comida y acá se va sumando lo que comés."))
        p.nodo(texto("Con las opciones elegidas: 2.454 kcal"))
        p.nodo(textoQueContiene("Objetivos calculados con Mifflin-St Jeor"))
        // DIE-04: opción A por defecto, con sus alimentos.
        assertEquals(listOf("Opción A · 3 alimentos"), p.textosBajo(etiqueta("resumen-c1")))
        assertTrue(p.seleccionado(etiqueta("opcion-c1-0")))
        assertEquals(listOf("Avena en copos", "100 g · 380 kcal", "P 13  ·  C 67  ·  G 7"), p.textosBajo(etiqueta("alimento-c1-0")))
        // La B del desayuno: cambian los alimentos, el total de la comida y lo que suman las elegidas (−10 %).
        p.tocar(etiqueta("opcion-c1-1"))
        p.esperar("opción B") { p.textosBajo(etiqueta("resumen-c1")) == listOf("Opción B · 3 alimentos") }
        assertEquals(listOf("Pan integral", "80 g · 200 kcal", "P 8  ·  C 38  ·  G 2"), p.textosBajo(etiqueta("alimento-c1-0")))
        assertEquals("0,5 u · 160 kcal", p.textosBajo(etiqueta("alimento-c1-2"))[1])
        p.nodo(texto("468"))
        p.nodo(texto("Con las opciones elegidas: 2.203 kcal (-10 %)"))
        // La elegida sigue al ir a otra pestaña y volver (vive en memoria, como en la web).
        p.tocar(etiqueta("pestana-entreno"))
        p.esperarQueNoEste(etiqueta("dieta-cabecera"))
        p.tocar(etiqueta("pestana-dieta"))
        // En una pantalla chica la lista puede volver arriba de todo, con el desayuno fuera de la vista: primero se llega a él.
        p.nodo(etiqueta("resumen-c1"))
        p.esperar("sigue la B") { p.textosBajo(etiqueta("resumen-c1")) == listOf("Opción B · 3 alimentos") }
    }

    /** DIE-05/07 (D25) en la demo: «Comí» suma la opción que se ve, en memoria y sin red; tocarlo de nuevo desmarca. */
    @Test
    fun enLaDemoComiSumaLaOpcionQueSeVeYTocarDeNuevoDesmarca() {
        demoEnDieta()
        p.tocar(etiqueta("opcion-c1-1"))
        p.tocar(etiqueta("comi-c1"))
        p.esperar("«Comí» marcado") { p.seleccionado(etiqueta("comi-c1")) }
        assertTrue(!p.seleccionado(etiqueta("salte-c1")))
        p.esperar("suma la B del desayuno") { p.estado(etiqueta("consumido-kcal")) == "468 de 2.454 kcal" }
        p.nodo(texto("Comiste 1 de 5 comidas"))
        p.tocar(etiqueta("comi-c1"))
        p.esperar("desmarcado") { !p.seleccionado(etiqueta("comi-c1")) }
        p.esperar("vuelve a cero") { p.estado(etiqueta("consumido-kcal")) == "0 de 2.454 kcal" }
        p.nodo(texto("Tocá «Comí» en cada comida y acá se va sumando lo que comés."))
        assertTrue("la demo no escribe", servidor.llamadas.isEmpty())
    }

    @Test
    fun verFuentesAbreElRespaldoCientifico() {
        demoEnDieta()
        p.tocar(etiqueta("ver-fuentes"))
        p.nodo(etiqueta("hoja-fuentes"))
        p.nodo(texto("Respaldo científico"))
        p.nodo(textoQueContiene("Tu plan lo arma Mati, que es médico."))
        p.nodo(texto("Cómo se calcula tu objetivo de calorías"))
        p.nodo(textoQueContiene("Mifflin MD, St Jeor ST, Hill LA"))
        p.nodo(texto("https://pubmed.ncbi.nlm.nih.gov/2305711/"))
        p.tocar(etiqueta("fuentes-listo"))
        p.esperarQueNoEste(etiqueta("hoja-fuentes"))
    }

    @Test
    fun conTiposDeDiaSeEligeElDiaYQuedaGuardado() {
        // Formato B (`tipos_dia`, docs/SCHEMA_DIETA.md): cada tipo de día con su objetivo y sus comidas.
        servidor.respuestas["mypump_get_dieta_activa"] = """[{"id":"dieta-b","version":1,"estructura":{"tipos_dia":[
            {"id":"entreno","nombre":"Día de entreno","macros_target":{"kcal":2600,"prot":180,"carb":300,"fat":70},
             "comidas":[{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena en copos","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}]}]}]},
            {"id":"descanso","nombre":"Día de descanso","macros_target":{"kcal":2100,"prot":180,"carb":200,"fat":65},
             "comidas":[{"id":"c1","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Huevos enteros","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18}]}]}]}
        ]}}]"""
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("de 2.600 kcal"))
            p.nodo(texto("Día de entreno"))
            p.nodo(texto("Avena en copos"))
            p.tocar(etiqueta("tipo-dia"))
            p.tocar(etiqueta("tipo-dia-descanso"))
            p.nodo(texto("de 2.100 kcal"))
            p.nodo(texto("Huevos enteros"))
            p.nodo(texto("Día de descanso"))
        }.close()
        // DIE-01: se guarda para todo el teléfono (`mypump_tipo_dia`, como la web): al volver a abrir sigue el de descanso.
        assertEquals("descanso", preferencia(ModeloApp.CLAVE_TIPO_DIA))
        abrir()
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("de 2.100 kcal"))
    }

    @Test
    fun sinDietaUsableNoMuestraLaDeEjemplo() {
        // D11: la web mostraba la dieta de ejemplo de 3.200 kcal como si fuera del cliente.
        servidor.respuestas["mypump_get_dieta_activa"] = "[]"
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("Todavía no hay plan de comidas"))
        p.nodo(texto("Cuando Mati publique tu dieta, la vas a ver acá."))
        assertTrue(!p.existe(etiqueta("dieta-cabecera")))
    }
}
