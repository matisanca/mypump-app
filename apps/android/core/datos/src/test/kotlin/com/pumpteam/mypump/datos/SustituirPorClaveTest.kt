package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Imagenes
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.SustitutoEjercicio
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 13 (gemelo de SustituirPorClaveTests.swift): la hoja de "Sustituir ejercicio" guardaba la
 * POSICIÓN del elegido. Si con la hoja abierta llegaba el catálogo del servidor (`cargarCatalogo`), la lista cambiaba de
 * orden y "Sustituir" aplicaba otro ejercicio. Ahora elige por la clave del sustituto (el slug del catálogo).
 */
class SustituirPorClaveTest {
    /** El del servidor: los mismos tres en otro orden y dos más que van primero. */
    private val catalogoDelServidor = CatalogoEjercicios.desde(
        """
        [{"slug_en":"Lat_Pulldown_Machine","name_en":"Lat Pulldown Machine","primary_muscle":"lats","equipment":"machine","patron_movimiento":"traccion_vertical"},
         {"slug_en":"Chin-Up","name_en":"Chin-Up","primary_muscle":"lats","equipment":"body only","patron_movimiento":"traccion_vertical"},
         {"slug_en":"Pullups","name_en":"Pullups","primary_muscle":"lats","equipment":"body only","patron_movimiento":"traccion_vertical"},
         {"slug_en":"V-Bar_Pulldown","name_en":"V-Bar Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
         {"slug_en":"Wide-Grip_Lat_Pulldown","name_en":"Wide-Grip Lat Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"}]
        """,
    )

    @Test
    fun elElegidoSigueSiendoElMismoCuandoLlegaElCatalogo() = enUnHilo { alcance ->
        val m = Banco(alcance).modelo()
        val antes = m.sustitutos("jal-d1-0")
        assertTrue(antes.size >= 2)
        val i = antes.size - 1
        val elegido = antes[i]

        // Con la hoja abierta llega el catálogo del servidor.
        m.actualizarCatalogo(catalogoDelServidor)
        val despues = m.sustitutos("jal-d1-0")
        assertTrue(despues.size > antes.size)
        assertTrue(i < despues.size)
        assertNotEquals(elegido.nombre, despues[i].nombre, "la misma posición ya es otro ejercicio (lo que aplicaba la hoja)")

        val aplicado = m.sustituto("jal-d1-0", elegido.clave)!!
        assertTrue(aplicado.nombre == elegido.nombre && aplicado.slug == elegido.slug)
        m.sustituir("jal-d1-0", aplicado, fijar = false)
        assertEquals(elegido.nombre, m.efectivo(m.dia.value.ejercicio("jal-d1-0")!!).ejercicio.nombre)
    }

    @Test
    fun laClaveEsUnicaEnLaListaYSinSlugUsaNombreYEquipo() = enUnHilo { alcance ->
        val m = Banco(alcance).modelo()
        m.actualizarCatalogo(catalogoDelServidor)
        val lista = m.sustitutos("jal-d1-0")
        assertEquals(lista.size, lista.map { it.clave }.toSet().size)
        val sinSlug = SustitutoEjercicio(
            slug = null, nombre = "Remo con banda", nombreIngles = null, equipo = "Banda", equipoCrudo = "bands", musculo = null,
            patron = null, imagenes = Imagenes(eccentric = null, concentric = null), mismoEquipo = false,
        )
        assertEquals("Remo con banda|bands", sinSlug.clave)
    }
}
