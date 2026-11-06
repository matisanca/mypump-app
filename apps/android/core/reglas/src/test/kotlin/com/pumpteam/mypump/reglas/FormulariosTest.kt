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

    /** Desvío a propósito de la web (27-oct): lo que 100 g no pueden tener no se guarda (el motor de reemplazos calcula con eso). */
    @Test
    fun loQue100gNoPuedenTenerNoSeGuarda() {
        // El caso real: «1 rebanada de 15 g» con los valores del paquete = 833 kcal y 133 g de proteína por 100 g.
        assertEquals(Formulario.Invalido("Esos valores no entran en 1 rebanada de 15 g: revisá cuánto pesa o los valores."),
            preparar("Jamón de pavo", kcal = 125.0, prot = 20.0, carb = 5.0, fat = 3.0, unidad = "rebanada", gramos = 15.0))
        val deUnPlato = Formulario.Invalido("Esos valores no pueden ser de 100 g: si son de una porción, elegí «porción» y poné cuánto pesa.")
        assertEquals(deUnPlato, preparar(kcal = 700.0, prot = 50.0, carb = 80.0, fat = 20.0))   // 150 g de macros
        assertEquals(deUnPlato, preparar(kcal = 1200.0, prot = 10.0))                          // más que el aceite
        assertEquals(deUnPlato, preparar(fat = 110.0))                                         // las kcal derivadas también cuentan
        assertEquals(Formulario.Invalido("Esos valores no pueden ser de 100 ml: si son de una porción, elegí «porción» y poné cuánto pesa."),
            preparar(kcal = 1000.0, unidad = "ml"))
        assertEquals(Formulario.Invalido("Esos valores no entran en 1 unidad de 12.5 g: revisá cuánto pesa o los valores."),
            preparar(kcal = 300.0, prot = 120.0, unidad = "unidad", gramos = 12.5))

        // Lo que sí puede ser: el aceite, un proteico con el redondeo de la etiqueta y un líquido denso por 100 ml.
        assertEquals(884.0, datos(preparar(kcal = 884.0, fat = 100.0)).kcal)
        val proteico = datos(preparar(kcal = 128.0, prot = 24.0, carb = 3.3, fat = 2.9, unidad = "porcion", gramos = 30.0))
        assertEquals(listOf(80.0, 11.0, 9.7), listOf(proteico.prot, proteico.carb, proteico.fat))   // 100,7 g: entra por el margen
        assertEquals(117.0, datos(preparar(kcal = 430.0, carb = 117.0, unidad = "ml")).carb)
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

    // Lectura de la etiqueta y aviso de proteína en polvo (6-nov, el whey de 30 g guardado como 100 g)

    @Test
    fun laBaseDeLaLectura() {
        assertEquals(AlimentoPropioNuevo.BaseLectura.Porcion(30.0), AlimentoPropioNuevo.baseLectura(30.0, "porcion"))
        assertEquals(AlimentoPropioNuevo.BaseLectura.Cien, AlimentoPropioNuevo.baseLectura(100.0, "100g"))
        assertEquals(AlimentoPropioNuevo.BaseLectura.Desconocida, AlimentoPropioNuevo.baseLectura(null, "desconocida"))
        // Servidor viejo, sin `base`: sin gramos ya no se asume 100 g.
        assertEquals(AlimentoPropioNuevo.BaseLectura.Desconocida, AlimentoPropioNuevo.baseLectura(null, null))
        assertEquals(AlimentoPropioNuevo.BaseLectura.Desconocida, AlimentoPropioNuevo.baseLectura(0.0, null))
        assertEquals(AlimentoPropioNuevo.BaseLectura.Cien, AlimentoPropioNuevo.baseLectura(100.4, null))
        assertEquals(AlimentoPropioNuevo.BaseLectura.Porcion(30.0), AlimentoPropioNuevo.baseLectura(30.0, null))
        assertEquals(AlimentoPropioNuevo.BaseLectura.Desconocida, AlimentoPropioNuevo.baseLectura(null, "porcion"))
    }

    @Test
    fun elTextoDiceLaBase() {
        assertEquals(
            "✓ Etiqueta leída. Quedaron como valores de 1 porción de 30 g. Revisalos y tocá \"Crear y usar\".",
            AlimentoPropioNuevo.textoLectura(AlimentoPropioNuevo.BaseLectura.Porcion(30.0), false),
        )
        assertEquals(
            "✓ Etiqueta leída. Quedaron como valores por 100 g. Revisalos y tocá \"Crear y usar\".",
            AlimentoPropioNuevo.textoLectura(AlimentoPropioNuevo.BaseLectura.Cien, false),
        )
        assertEquals(
            "✓ Etiqueta leída. La etiqueta no dice cuánto pesa la porción. ¿Estos valores son por 100 g o de 1 porción?",
            AlimentoPropioNuevo.textoLectura(AlimentoPropioNuevo.BaseLectura.Desconocida, false),
        )
        assertEquals(
            "⚠ La etiqueta se leyó con poca claridad (las calorías no cierran con los macros): revisá los valores antes de " +
                "guardar. Quedaron como valores por 100 g.",
            AlimentoPropioNuevo.textoLectura(AlimentoPropioNuevo.BaseLectura.Cien, true, listOf("las calorías no cierran con los macros")),
        )
    }

    @Test
    fun avisoDelPolvoDeProteina() {
        fun aviso(nombre: String, kcal: Double?, unidad: String = "g", gramos: Double? = null, prot: Double? = null) =
            AlimentoPropioNuevo.avisoPolvoProteina(nombre, kcal, prot, null, null, unidad, gramos)
        // El caso de Camila: el scoop (132 kcal) cargado como 100 g.
        assertTrue(aviso("BEST WHEY", 132.0)!!.contains("elegí «porción»"))
        assertTrue(aviso("Proteína en polvo", 132.0) != null)
        assertTrue(aviso("Caseína micelar", 120.0) != null)
        assertTrue(aviso("Proteina vegetal en polvo", 110.0) != null)
        // Bien cargado: por 100 g o por porción con sus gramos.
        assertNull(aviso("BEST WHEY", 440.0))
        assertNull(aviso("BEST WHEY", 132.0, unidad = "porcion", gramos = 30.0))
        // Porción con gramos de más: avisa y pide revisar los gramos.
        assertTrue(aviso("BEST WHEY", 132.0, unidad = "porcion", gramos = 100.0)!!.contains("Revisá que los gramos"))
        // Sin kcal se miran los macros (24 g de proteína = 96 kcal).
        assertTrue(aviso("Whey", null, prot = 24.0) != null)
        // No es polvo de proteína: no avisa (leche proteica, cacao en polvo).
        assertNull(aviso("Leche Protein", 37.0))
        assertNull(aviso("Cacao en polvo", 228.0))
        // Porción sin gramos o sin valores: no hay con qué calcular.
        assertNull(aviso("Whey", 132.0, unidad = "porcion", gramos = null))
        assertNull(aviso("Whey", null))
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
