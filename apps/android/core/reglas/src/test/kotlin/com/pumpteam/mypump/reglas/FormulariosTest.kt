package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.EstimacionPlato
import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Gemelo de AlimentoPropioNuevoTests.swift: la misma validación y conversión a 100 g que `saveCustomFood`. */
class AlimentoPropioNuevoTest {
    private fun preparar(
        nombre: String = "Yogur X",
        kcal: Double? = null,
        prot: Double? = null,
        carb: Double? = null,
        fat: Double? = null,
        unidad: String = "g",
        gramos: Double? = null,
    ) = AlimentoPropioNuevo.preparar(nombre, kcal, prot, carb, fat, unidad, gramos, "lacteo")

    private fun datos(f: Formulario<AlimentoPropioNuevo.Datos>) = f.datosONull() ?: error("no validó: $f")

    @Test
    fun enGramosNoSeConvierte() {
        assertEquals(AlimentoPropioNuevo.Datos("Yogur X", 63.0, 10.0, 4.2, 0.5, "g", null, "lacteo"),
            datos(preparar(kcal = 63.0, prot = 10.0, carb = 4.2, fat = 0.5)))
    }

    @Test
    fun porPorcionSeLlevaA100g() {
        // El caso del comentario de la web: porción de 30 g con 75 kcal = 250 kcal por 100 g.
        val d = datos(preparar(kcal = 75.0, prot = 3.0, carb = 10.1, fat = 2.25, unidad = "porcion", gramos = 30.0))
        assertEquals(250.0, d.kcal)
        assertEquals(10.0, d.prot)       // 3 × 100/30 = 10
        assertEquals(33.7, d.carb)       // 33,666… → 33,7
        assertEquals(7.5, d.fat)
        assertEquals(30.0, d.gramosPorUnidad)
    }

    @Test
    fun sinKcalSeDerivanDeLosMacros() = assertEquals(165.0, datos(preparar(prot = 10.0, carb = 20.0, fat = 5.0)).kcal)   // 10·4 + 20·4 + 5·9

    @Test
    fun negativosYVaciosValenCero() {
        val d = datos(preparar(kcal = -5.0, prot = 12.0, carb = -1.0, fat = null))
        assertEquals(48.0, d.kcal)
        assertEquals(0.0, d.carb)
        assertEquals(0.0, d.fat)
    }

    @Test
    fun errores() {
        assertEquals(Formulario.Invalido("El nombre es obligatorio."), preparar("   ", kcal = 100.0))
        assertEquals(Formulario.Invalido("Cargá al menos las calorías o algún macro."), preparar(kcal = 0.0, prot = 0.0))
        assertEquals(Formulario.Invalido("Para \"rebanada\" indicá cuánto pesa 1 rebanada en gramos."), preparar(kcal = 90.0, unidad = "rebanada"))
        assertEquals(Formulario.Invalido("Para \"rebanada\" indicá cuánto pesa 1 rebanada en gramos."),
            preparar(kcal = 90.0, unidad = "rebanada", gramos = 0.0))
        // La unidad se muestra con tilde.
        assertEquals(Formulario.Invalido("Para \"porción\" indicá cuánto pesa 1 porción en gramos."), preparar(kcal = 90.0, unidad = "porcion"))
    }

    @Test
    fun gramosPorUnidadSeIgnoraEnGramosYMl() {
        val d = datos(preparar(kcal = 50.0, unidad = "ml", gramos = 30.0))
        assertEquals(50.0, d.kcal)
        assertNull(d.gramosPorUnidad)
    }

    @Test
    fun renglonDeLaBase() {
        assertEquals("Poné los valores por 100 g, como vienen en la etiqueta.", AlimentoPropioNuevo.base("g", null))
        assertEquals("Poné los valores de 1 porción (30 g), lo que realmente comés.", AlimentoPropioNuevo.base("porcion", 30.0))
        assertEquals("Poné los valores de 1 taza, lo que realmente comés.", AlimentoPropioNuevo.base("taza", null))
        assertEquals("Poné los valores de 1 unidad (12.5 g), lo que realmente comés.", AlimentoPropioNuevo.base("unidad", 12.5))
    }

    @Test
    fun leerNumeroAceptaComa() {
        assertEquals(1.5, AlimentoPropioNuevo.leerNumero("1,5"))
        assertEquals(12.0, AlimentoPropioNuevo.leerNumero(" 12 "))
        assertNull(AlimentoPropioNuevo.leerNumero(""))
        assertNull(AlimentoPropioNuevo.leerNumero("abc"))
        assertNull(AlimentoPropioNuevo.leerNumero("1.5f"))   // el sufijo que acepta toDouble de Kotlin no es un número
        assertNull(AlimentoPropioNuevo.leerNumero("١٢"))
    }

    @Test
    fun lasUnidadesDelSelector() {
        assertEquals(listOf("g", "ml", "unidad", "rebanada", "taza", "porcion", "cucharada"), AlimentoPropioNuevo.unidades.map { it.first })
        assertEquals("porción", AlimentoPropioNuevo.texto("porcion"))
    }
}

/** Gemelo de ComidaLibreNuevaTests.swift: el mismo re-escalado y validación que la web. */
class ComidaLibreNuevaTest {
    private val estimacion = EstimacionPlato(
        descripcion = "Milanesa con puré", escala = "plato de 26 cm",
        alimentos = listOf(
            EstimacionPlato.AlimentoEstimado("Milanesa de carne", 205.0, 451.0, 36.9, 22.6, 23.4),
            EstimacionPlato.AlimentoEstimado("Puré de papa", 180.4, 158.0, 3.4, 27.2, 4.1),
        ),
        kcal = 609.0, prot = 40.3, carb = 49.8, fat = 27.5, confianza = "media",
    )

    @Test
    fun lasBasesSonPorGramoYLosGramosInicialesRedondeados() {
        val b = ComidaLibreNueva.bases(estimacion)
        assertEquals(2, b.size)
        assertEquals(180.0, b[1].gramosIniciales)
        assertEquals(451.0 / 205, b[0].kcal)
    }

    @Test
    fun corregirGramosReEscalaLosTotales() {
        val b = ComidaLibreNueva.bases(estimacion)
        // Sin tocar: los mismos totales (con los gramos sin redondear de la IA se escala por 180, el redondeado).
        assertEquals(listOf(205.0, 180.0), ComidaLibreNueva.gramos(b, listOf(null, null)))
        // 205 → 260 g de milanesa.
        val t = ComidaLibreNueva.totales(b, ComidaLibreNueva.gramos(b, listOf(260.0, null)))
        assertEquals(730.0, t.kcal)          // 451/205·260 + 158/180.4·180 = 572,0 + 157,6
        assertEquals(50.2, t.prot)           // 46,8 + 3,39
        assertEquals(33.8, t.fat)
    }

    @Test
    fun unGramajeIlegibleVuelveAlInicial() {
        val b = ComidaLibreNueva.bases(estimacion)
        assertEquals(listOf(205.0, 180.0), ComidaLibreNueva.gramos(b, listOf(-3.0, Double.NaN)))
    }

    @Test
    fun elDetalleGuardaLosGramosCorregidos() {
        val b = ComidaLibreNueva.bases(estimacion)
        val d = ComidaLibreNueva.detalle(b, listOf(260.0, 180.0), "media", null)!!
        val alimentos = (d["alimentos"] as ValorJson.Lista).elementos
        assertEquals(ValorJson.Numero(260.0), alimentos[0]["gramos"])
        assertEquals(ValorJson.Numero(572.0), alimentos[0]["kcal"])
        assertEquals(ValorJson.Texto("media"), d["confianza"])
        assertEquals(ValorJson.Nulo, d["escala"])
        assertNull(ComidaLibreNueva.detalle(emptyList(), emptyList(), null, null))
    }

    @Test
    fun validacion() {
        assertEquals(Formulario.Invalido("Contá qué comiste."), ComidaLibreNueva.preparar("  ", null, 300.0, null, null, null, null))
        assertEquals(Formulario.Invalido("Cargá al menos las calorías o algún macro."),
            ComidaLibreNueva.preparar("Alfajor", "", 0.0, -2.0, null, null, null))
        val ok = ComidaLibreNueva.preparar(" Alfajor ", "", 250.0, null, 35.0, 11.0, null).datosONull()
        assertTrue(ok?.descripcion == "Alfajor" && ok.hora == null && ok.prot == 0.0 && ok.carb == 35.0, "$ok")
    }

    @Test
    fun fechaYHoraLocales() {
        val d = Instant.ofEpochSecond(1_791_950_000)   // 2026-10-14 03:53 UTC
        val ar = ZoneId.of("America/Argentina/Buenos_Aires")
        assertEquals("2026-10-14", FechaLocal.hoy(d, ar))
        assertEquals("2026-10-13", FechaLocal.hoy(d, ZoneId.of("America/Los_Angeles")))
        assertEquals("00:53", ComidaLibreNueva.hora(d, ar))
    }
}
