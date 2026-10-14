package com.pumpteam.mypump.reglas

import java.text.Collator
import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test

/**
 * `localeCompare(…, 'es')` caso por caso. Lo esperado es el signo de `Intl.Collator('es').compare` en node (V8 + ICU).
 * El orden de todos los nombres del catálogo lo cubre el vector `orden` (SustitucionEjerciciosTest); estos casos dejan
 * escrito el porqué. Además se probó contra 20.000 pares al azar con acentos, ñ compuesta y suelta, ß, ½, puntuación y
 * mayúsculas, sin diferencias.
 */
class ColacionEspanolTest {
    private val casos = listOf(
        Triple("Curl de bíceps a una mano", "Curl de bíceps agarre ancho", -1),   // el espacio pesa y va antes que las letras
        Triple("nz", "ña", -1),
        Triple("ñz", "oa", -1),                   // la ñ es una letra entre la n y la o
        Triple("ñ", "ñ", 0),                // la ñ con la tilde suelta es la misma
        Triple("Ñandú", "ñandu", 1),
        Triple("a", "A", -1),                     // minúscula antes que mayúscula (tercer nivel)
        Triple("A", "á", -1),                     // el acento (segundo nivel) pesa más que la mayúscula
        Triple("á", "à", -1),
        Triple("à", "â", -1),
        Triple("â", "ä", -1),
        Triple("pres", "Prés", -1),
        Triple("Curl 10", "Curl 2", -1),          // sin orden numérico
        Triple("Curl", "Curl ", -1),
        Triple(" Curl", "Curl", -1),
        Triple("Curl-a", "Curl a", 1),
        Triple("Curl(a)", "Curl/a", -1),
        Triple("Curl'a", "Curl,a", 1),
        Triple("a-b", "a_b", 1),
        Triple("", " ", -1),
        Triple("9", "a", -1),
        Triple("(", "0", -1),
        Triple("ß", "ss", 1),
        Triple("a­b", "ab", 0),              // el guion blando no pesa
        Triple("Elevación", "Elevacion", 1),
        Triple("Elevaciön", "Elevación", 1),
        Triple("chaleco", "cuchillo", -1),        // ch y ll no son letras aparte (el español tradicional no es el default)
        Triple("llama", "lomo", -1),
        Triple("½", "1/2", 1),
    )

    @Test
    fun comoLocaleCompareDeJs() {
        for ((a, b, js) in casos) {
            assertEquals(js, Integer.signum(ColacionEspanol.comparar(a, b)), "${a.debug()} vs ${b.debug()}")
            assertEquals(-js, Integer.signum(ColacionEspanol.comparar(b, a)), "${b.debug()} vs ${a.debug()}")
        }
    }

    /** Por qué no `java.text.Collator`: el de OpenJDK ignora el espacio y ordena al revés que la web. */
    @Test
    fun elCollatorDeLaJvmNoAlcanza() {
        val jdk = Collator.getInstance(Locale.forLanguageTag("es"))
        assertNotEquals(-1, Integer.signum(jdk.compare("Curl de bíceps a una mano", "Curl de bíceps agarre ancho")))
    }
}
