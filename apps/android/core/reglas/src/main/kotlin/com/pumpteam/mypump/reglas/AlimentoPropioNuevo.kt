package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.TextoJs

/**
 * "Crear alimento personalizado" (`saveCustomFood`, cliente.html:9510): valida lo que cargó el cliente y lo lleva a la
 * base de la tabla, que es SIEMPRE por 100 g. Con g o ml los valores ya vienen por 100 g (como la etiqueta); con
 * cualquier otra unidad vienen de 1 porción y se convierten con los gramos por unidad. Sin esa conversión un yogur de
 * porción 30 g / 75 kcal entraba como 75 kcal por 100 g y el motor lo calculaba 3,5 veces por debajo.
 */
object AlimentoPropioNuevo {
    /** Las unidades que ofrece el formulario, en su orden: el valor y el texto del selector. */
    val unidades: List<Pair<String, String>> = listOf(
        "g" to "gramos (g)", "ml" to "mililitros (ml)", "unidad" to "unidad", "rebanada" to "rebanada",
        "taza" to "taza", "porcion" to "porción", "cucharada" to "cucharada",
    )

    /** Lo que se manda a `mypump_create_custom_food` (`foodData` de la web). */
    data class Datos(
        val nombre: String,
        val kcal: Double,
        val prot: Double,
        val carb: Double,
        val fat: Double,
        val unidad: String,
        val gramosPorUnidad: Double?,
        val categoria: String,
    )

    fun porUnidad(unidad: String): Boolean = unidad != "g" && unidad != "ml"

    /** "porción" para mostrar (la web imprime el valor del selector, "porcion"). */
    fun texto(unidad: String): String = if (unidad == "porcion") "porción" else unidad

    /** El renglón que dice en qué base se cargan los números (cambia con la unidad, como `syncUnitGramsField`). */
    fun base(unidad: String, gramosPorUnidad: Double?): String {
        if (!porUnidad(unidad)) return "Poné los valores por 100 g, como vienen en la etiqueta."
        val g = if ((gramosPorUnidad ?: 0.0) > 0) " (${NumeroJs.texto(gramosPorUnidad!!)} g)" else ""
        return "Poné los valores de 1 ${texto(unidad)}$g, lo que realmente comés."
    }

    /**
     * Valida y convierte. Los números llegan ya leídos (null = campo vacío o ilegible; ver [leerNumero]); negativos y no
     * finitos valen 0 como en la web. Devuelve el mensaje de error de la web si no se puede guardar.
     */
    fun preparar(
        nombre: String,
        kcal: Double?,
        prot: Double?,
        carb: Double?,
        fat: Double?,
        unidad: String,
        gramosPorUnidad: Double?,
        categoria: String,
    ): Formulario<Datos> {
        val n = TextoJs.recortar(nombre)
        fun num(x: Double?) = if (x != null && x.isFinite() && x > 0) x else 0.0
        val p = num(prot)
        val c = num(carb)
        val f = num(fat)
        // Sin kcal se derivan de los macros (4/4/9): mucha gente sabe los macros pero no las calorías.
        val k = if (kcal != null && kcal.isFinite() && kcal > 0) kcal else jsRound(p * 4 + c * 4 + f * 9)
        val ug = if (porUnidad(unidad)) gramosPorUnidad else null

        if (n.isEmpty()) return Formulario.Invalido("El nombre es obligatorio.")
        if (k <= 0 && p <= 0 && c <= 0 && f <= 0) return Formulario.Invalido("Cargá al menos las calorías o algún macro.")
        if (porUnidad(unidad) && !((ug ?: 0.0) > 0)) {
            return Formulario.Invalido("Para \"${texto(unidad)}\" indicá cuánto pesa 1 ${texto(unidad)} en gramos.")
        }

        val porcionG = if (porUnidad(unidad)) (ug ?: 0.0) else 100.0
        val aCien = if (porcionG > 0) 100 / porcionG else 1.0
        fun r1(x: Double) = jsRound(x * aCien * 10) / 10
        val d = Datos(n, jsRound(k * aCien), r1(p), r1(c), r1(f), unidad, if ((ug ?: 0.0) > 0) ug else null, categoria)
        if (imposible(d)) {
            return Formulario.Invalido(
                if (porUnidad(unidad)) {
                    "Esos valores no entran en 1 ${texto(unidad)} de ${NumeroJs.texto(ug ?: 0.0)} g: revisá cuánto pesa o los valores."
                } else {
                    "Esos valores no pueden ser de 100 $unidad: si son de una porción, elegí «porción» y poné cuánto pesa."
                },
            )
        }
        return Formulario.Valido(d)
    }

    /**
     * Lo que 100 g no pueden tener: más de 100 g de macros (110 con el margen del redondeo de la etiqueta) o más calorías
     * que el aceite (900). Con ml no se miran los macros, que en un líquido denso pasan de 100 por 100 ml. Desvío a
     * propósito de la web, que lo guarda igual (27-oct): «1 rebanada de 15 g» con los valores del paquete quedó en 833 kcal
     * y 133 g de proteína por 100 g, y con eso el motor de reemplazos calcula las porciones.
     */
    const val MAXIMO_MACROS_POR_100 = 110.0
    const val MAXIMO_KCAL_POR_100 = 950.0

    internal fun imposible(d: Datos): Boolean =
        d.kcal > MAXIMO_KCAL_POR_100 || (d.unidad != "ml" && d.prot + d.carb + d.fat > MAXIMO_MACROS_POR_100)

    /** Lo que escribe el cliente en un campo numérico (ver [leerNumeroEscrito]). */
    fun leerNumero(texto: String): Double? = leerNumeroEscrito(texto)
}
