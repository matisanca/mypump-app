package com.pumpteam.mypump.diseno

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.dieta.FormatoDieta
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Cómo se escriben los números: lo mismo que muestra iOS (FormatStyle en es_AR, `enteroSeguro`, `FormatoDieta`). */
@RunWith(AndroidJUnit4::class)
class FormatoTest {
    @Test
    fun milesConPunto() {
        assertEquals("2.454", Formato.miles(2454.0))
        assertEquals("719", Formato.miles(719.4))
        assertEquals("1.000.000", Formato.miles(999_999.5))
        assertEquals("-1.200", Formato.miles(-1200.0))
        assertEquals("0", Formato.miles(null))
        assertEquals("0", Formato.miles(Double.NaN))
    }

    @Test
    fun enteroComoSwiftRounded() {
        // `rounded()` de Swift: al más cercano y, en la mitad, lejos del cero.
        assertEquals(3L, Formato.entero(2.5))
        assertEquals(-3L, Formato.entero(-2.5))
        assertEquals(-10L, Formato.entero(-10.2))
        assertEquals(0L, Formato.entero(Double.POSITIVE_INFINITY))
        assertEquals(1_000_000_000_000_000L, Formato.entero(1e20))
    }

    @Test
    fun unDecimalComoElFormatStyleDeIOS() {
        assertEquals("52,5", Formato.decimal(52.5))
        assertEquals("55", Formato.decimal(55.0))
        assertEquals("100", Formato.decimal(100.0))
        assertEquals("0,5", Formato.decimal(0.5))
        assertEquals("15,1", Formato.decimal(15.1))
        // Al par, sobre el decimal más corto (ICU): no "0,3" ni "15,1".
        assertEquals("0,2", Formato.decimal(0.25))
        assertEquals("15,2", Formato.decimal(15.15))
        assertEquals("11,4", Formato.decimal(11.45))
        assertEquals("0", Formato.decimal(-0.04))
        assertEquals("-2,5", Formato.decimal(-2.5))
        assertEquals("0", Formato.decimal(null))
    }

    @Test
    fun cantidadesComoDietaView() {
        assertEquals("100 g", FormatoDieta.cantidad(100.0, "g"))
        assertEquals("0,5 u", FormatoDieta.cantidad(0.5, "u"))
        assertEquals("2 unidades", FormatoDieta.cantidad(2.0, "unidad"))
        assertEquals("1 rebanada", FormatoDieta.cantidad(1.0, "rebanada"))
        assertEquals("3 porciones", FormatoDieta.cantidad(3.0, "porción"))
        assertEquals("2 scoops", FormatoDieta.cantidad(2.0, "scoop"))
        assertEquals("2 cucharadas", FormatoDieta.cantidad(2.0, "cucharada"))
        assertEquals("250 ml", FormatoDieta.cantidad(250.0, "ml"))
        assertEquals("g", FormatoDieta.cantidad(null, null))
    }
}
