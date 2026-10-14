package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento

/**
 * La categoría de un alimento (proteína, lácteo, grasa…): decide contra qué se lo puede sustituir.
 *
 * Port de `_inferCategory` (app.js:353). La web la tiene en TRES copias que se declaran idénticas: `inferFoodCategory`
 * (cliente.html:1948) e `inferCategory` (food-db.js:11, la que categoriza la base). Los vectores corren las tres sobre el
 * mismo corpus (scripts/nativa/vectores-alimentos.mjs) y hoy dan lo mismo en todos los casos, así que alcanza con una.
 * Si alguien edita una sola, el test lo marca.
 *
 * Primero palabras clave, en este orden y sobre el nombre en minúsculas; si ninguna matchea, la heurística por macros.
 * Las regex son de JS sin flag `u` (`\b` y `\w` son ASCII: "ñoquis" no tiene límite de palabra antes de la ñ, y `\bmaní$`
 * no matchea nunca por el `\b` que cierra el grupo), por eso van con [JsRegex] y copiadas literal.
 */
object CategoriaAlimento {
    const val PROTEINA = "proteina"
    const val LACTEO = "lacteo"
    const val GRASA = "grasa"
    const val FRUTA_VERDURA = "fruta_verdura"
    const val CARBOHIDRATO = "carbohidrato"
    const val CONDIMENTO = "condimento"
    const val MIXTO = "mixto"

    // 1) Proteínas: carnes, pescados, huevos, fiambres, sustitutos vegetales… si no es leche, yogur o queso.
    private val reProteina = JsRegex("""\b(carne|asado|bife|lomo|paleta|matambre|vacío|vacio|costill|nalga|cuadril|cuadrada|entraña|entrana|hígado|higado|cerdo|lechón|lechon|bondiola|jam[óo]n|salame|chorizo|longaniza|morcilla|salchicha|panceta|tocino|pollo|pavo|pato|pechuga|muslo|alita|pescado|salm[óo]n|merluza|atún|atun|sardin|trucha|lenguado|langostino|camar[óo]n|camaron|mejill[óo]n|mejillon|calamar|pulpo|kani|surimi|huevo|clara de huevo|tofu|tempeh|seit[áa]n|seitan|prote[íi]na (whey|de soja|vegetal)|pavita|cordero|cabrito|conejo|vísc|visc|chinchulín|riñón|rinon|mondongo|carpaccio|carne picada|hamburguesa)""")
    private val reLecheYogurQueso = JsRegex("""leche|yogur|queso""")

    // 2) Lácteos.
    private val reLacteo = JsRegex("""\b(leche(?! de coco)|yogur|yoghurt|kéfir|kefir|requesón|cottage|cuajada|nata|burrata|mozzarella|mozarella|provolone|provoleta|parmesano|reggianito|queso|cheddar|gouda|gruyere|brie|camembert|gorgonzola|fontina|sardo|tybo|port salut|ricotta|crema de leche|caf[ée] con leche|leche de soja|cacao con leche|chocolatada)\b""")

    // 3) Grasas: aceites, frutos secos, derivados grasos.
    private val reGrasa = JsRegex("""\b(aceite|manteca|mantequilla|margarina|mayonesa|crema (?!de leche)|nuez|nueces|almendra|cacahuet|cacahuete|man[íi] |\bmaní$|pistacho|avellana|castaña|piñ[óo]n|semilla|ch[íi]a|lin(o|aza)|s[ée]samo|sesamo|chía|coco rallado|leche de coco|aceitun|olivas|palta|aguacate|tahini|mantequilla de maní|mantequilla de almendras|ghee|sebo)\b""")

    // 4) Frutas y verduras frescas, salvo harinas, cereales y procesados.
    private val reProcesado = JsRegex("""polenta|harina|copos? de ma[íi]z|corn flakes|trigo (sarraceno|burgol)|helado|tarta|torta|kuchen|pie|mermelada|jugo|néctar|nectar|licuado|smoothie|jarabe|sirope""")
    private val reFruta = JsRegex("""\b(manzana|banan|pl[áa]tano|naranja|mandarin|kiwi|fres|frutilla|uva|pera|durazno|melocot[óo]n|ciruela|mel[óo]n|melon|sand[íi]a|pomelo|mango|anan[áa]|piña|pina|ar[áa]ndano|arandano|cereza|lim[óo]n|limon|papaya|mam[óo]n|maracuy[áa]|higo|frambuesa|mora|d[áa]til|datil|grosella|granada|guayaba|caqui|chirimoya|tuna|n[íi]spero|nispero|carambola|pitaya|lychee|rambut[áa]n|fruta de la pasi[óo]n|coco fresco)\w*""")
    private val reVerdura = JsRegex("""\b(zanahoria|calabaza|zapallit|zucchini|tomate|pepino|lechug|r[úu]cula|rucula|apio|repollo|berenjena|morr[óo]n|morron|pimiento|cebolla|chauch|arveja|guisante|remolach|champiñ[óo]n|champinon|hongo|esp[áa]rrago|esparrago|alcauci|alcachof|palmito|ma[íi]z|choclo|puerro|acelga|radicheta|endivia|escarola|espinac|br[óo]coli|brocoli|coliflor|kale|repollito|rabanit|r[áa]bano|nabo|hinojo|jalapeñ|jalapeno|chile(?! con carne)|aj[íi] (picante|verde|rojo|amarillo)|pimentón fresco|jengibre fresco|cúrcuma fresca|verduras? salteadas|wok de verduras|ensalada (?!cesar|c[ée]sar))\w*""")
    private val reAjo = JsRegex("""^ajo$|^ajos$|^cabeza de ajo""")   // ajo solo (no "en polvo")

    // 5) Tubérculos densos.
    private val reTuberculo = JsRegex("""\b(papa(?! frita)|patata(?! frita)|batata|camote|boniato|yuca|mandioca|cassava|tap[íi]oca|tapioca|polenta|plátano macho|platano macho)\b""")

    // 6) Legumbres: Mati las usa como carbohidrato.
    private val reLegumbre = JsRegex("""\b(lenteja|garbanzo|frijol|poroto|jud[íi]a blanca|judia blanca|alubia|haba|soja cocida|soya|edamame|chícharo|chicharo)\b""")

    // 7) Carbohidratos clásicos.
    private val reCarbohidrato = JsRegex("""\b(arroz|pasta|fideo|spaguett|spaghet|tallarines|ravioli|ñoqui|gnocch|pan(?! con|cake)|pancake|hotcake|tostada|harina|avena|cuscus|cousc[óo]us|quinoa|cebada|bulgur|trigo (sarraceno)?|cereal|granola|galleta|tortilla(?! española)|bollillo|telera|pita|wrap|arepa|crouton|chocolate|miel|az[úu]car|edulcorante|mermelada|dulce de leche|alfajor|barrita|snack|cracker|chip|salsa de tomate|kétchup|ketchup|panqueque|waffle|donut|crep|brownie|muffin|budín|budin|bizcoch|torta|magdalena|barra cereal|gomitas|caramelo|chuche)\b""")

    // 8) Condimentos: sin valor calórico significativo.
    private val reCondimento = JsRegex("""\b(mostaza|vinagre|sal\b|pimienta|albahaca|comino|perejil|orégano|oregano|romero|tomillo|laurel|nuez moscada|p[áa]prika|cilantro|hierba|condimento|caldo cubo|sazonador|chimichurri|salsa picante|tabasco|sriracha)\b""")

    /**
     * La categoría de un alimento del plan (macros totales de la porción: la heurística solo mira proporciones).
     *
     * Ojo: [Alimento] decodifica `"fat": null` igual que si faltara (null), y para la web no es lo mismo (ver
     * [inferir] con macros sueltas). Los planes publicados traen siempre las cuatro macros.
     */
    fun inferir(a: Alimento): String = inferir(a.nombre, a.prot, a.carb, a.fat)

    /**
     * null es `undefined` de JS. Un `null` de JSON se pasa como 0: en esta regla vale lo mismo (`null / total` es 0 y
     * `null > 0` es falso), mientras que `undefined / total` es NaN. La diferencia solo se ve en la grasa: con proteína y
     * carbohidrato, `fPct < 0.3` da "lacteo" si la grasa es null y no si falta.
     */
    fun inferir(nombre: String?, prot: Double?, carb: Double?, fat: Double?): String {
        val name = (nombre ?: "").lowercase()
        if (reProteina.prueba(name) && !reLecheYogurQueso.prueba(name)) return PROTEINA
        if (reLacteo.prueba(name)) return LACTEO
        if (reGrasa.prueba(name)) return GRASA
        if (!reProcesado.prueba(name) && (reFruta.prueba(name) || reVerdura.prueba(name) || reAjo.prueba(name))) return FRUTA_VERDURA
        if (reTuberculo.prueba(name)) return CARBOHIDRATO
        if (reLegumbre.prueba(name)) return CARBOHIDRATO
        if (reCarbohidrato.prueba(name)) return CARBOHIDRATO
        if (reCondimento.prueba(name)) return CONDIMENTO

        // Fallback heurístico. El total usa `|| 0`; los porcentajes, el valor pelado (undefined → NaN, que no pasa
        // ninguna comparación).
        val total = SemanticaJs.oCero(prot) + SemanticaJs.oCero(carb) + SemanticaJs.oCero(fat)
        if (total == 0.0) return CONDIMENTO
        val p = prot ?: Double.NaN
        val c = carb ?: Double.NaN
        val f = fat ?: Double.NaN
        val pPct = p / total
        val cPct = c / total
        val fPct = f / total
        if (pPct > 0.5) return PROTEINA
        if (cPct > 0.5) return CARBOHIDRATO
        if (fPct > 0.5) return GRASA
        if (p > 0 && c > 0 && fPct < 0.3) return LACTEO
        if (cPct > 0.4) return FRUTA_VERDURA
        return MIXTO
    }

    /**
     * `_categoryByMacros` (app.js:148): la categoría SOLO por macros, ignorando el nombre. Es el fallback (F8) para los
     * alimentos del Cerebro cuyo nombre no matchea nada y caen en mixto u otra. null si no hay macro claro.
     */
    fun porMacros(prot: Double?, carb: Double?, fat: Double?): String? {
        val p = SemanticaJs.oCero(prot) * 4
        val c = SemanticaJs.oCero(carb) * 4
        val f = SemanticaJs.oCero(fat) * 9
        val total = p + c + f
        if (total <= 0) return null
        if (p / total > 0.45) return PROTEINA
        if (f / total > 0.55) return GRASA
        if (c / total > 0.5) return CARBOHIDRATO
        return null
    }
}
