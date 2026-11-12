package com.pumpteam.mypump.reglas

import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** «¿Cómo se lee?» con los mismos textos que iOS y la web (`como_se_lee.json`). */
class ComoSeLeeTest {
    private val v = Vectores.json(Vectores.publico("como_se_lee"))

    @Test fun textosIgualesALosVectores() {
        assertEquals(v["boton"]!!.jsonPrimitive.content, ComoSeLee.BOTON)
        assertEquals(v["titulo"]!!.jsonPrimitive.content, ComoSeLee.TITULO)
        assertEquals(v["pasos"]!!.jsonArray.map { it.jsonPrimitive.content }, ComoSeLee.PASOS)
        assertEquals(v["verVideo"]!!.jsonPrimitive.content, ComoSeLee.VER_VIDEO)
        assertEquals(v["cerrar"]!!.jsonPrimitive.content, ComoSeLee.CERRAR)
        assertEquals(v["video"].let { if (it == null || it is JsonNull) null else it.jsonPrimitive.content }, ComoSeLee.VIDEO)
        ComoSeLee.PASOS.forEach { assertFalse(it.contains("RIR", ignoreCase = true)); assertFalse(it.contains("entrenador")) }
    }

    @Test fun videoSoloHttps() {
        assertNull(ComoSeLee.urlVideo(null))
        assertNull(ComoSeLee.urlVideo("http://x.com/v"))
        assertNull(ComoSeLee.urlVideo("javascript:alert(1)"))
        assertNull(ComoSeLee.urlVideo("https://x.com/v\"onload=\"x"))
        assertEquals("https://x.com/v", ComoSeLee.urlVideo(" https://x.com/v "))
    }
}
