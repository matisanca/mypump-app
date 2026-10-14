import Foundation
import MyPumpModelos

/// La categoría de un alimento (proteína, lácteo, grasa…): decide contra qué se lo puede sustituir.
///
/// Port de `_inferCategory` (app.js:353). La web la tiene en TRES copias que se declaran idénticas:
/// `inferFoodCategory` (cliente.html:1948) e `inferCategory` (food-db.js:11, la que categoriza la base). Los vectores
/// corren las tres sobre el mismo corpus (scripts/nativa/vectores-alimentos.mjs) y hoy dan lo mismo en todos los
/// casos, así que alcanza con una. Si alguien edita una sola, `AlimentosTests` lo marca.
///
/// Primero palabras clave, en este orden y sobre el nombre en minúsculas; si ninguna matchea, la heurística por
/// macros. Las regex son de JS sin flag `u` (`\b` y `\w` son ASCII: "ñoquis" no tiene límite de palabra antes de la
/// ñ, y `\bmaní$` no matchea nunca por el `\b` que cierra el grupo), por eso van con `JSRegex` y copiadas literal.
public enum CategoriaAlimento {
    public static let proteina = "proteina"
    public static let lacteo = "lacteo"
    public static let grasa = "grasa"
    public static let frutaVerdura = "fruta_verdura"
    public static let carbohidrato = "carbohidrato"
    public static let condimento = "condimento"
    public static let mixto = "mixto"

    // 1) Proteínas: carnes, pescados, huevos, fiambres, sustitutos vegetales… si no es leche, yogur o queso.
    static let reProteina = JSRegex(#"\b(carne|asado|bife|lomo|paleta|matambre|vacío|vacio|costill|nalga|cuadril|cuadrada|entraña|entrana|hígado|higado|cerdo|lechón|lechon|bondiola|jam[óo]n|salame|chorizo|longaniza|morcilla|salchicha|panceta|tocino|pollo|pavo|pato|pechuga|muslo|alita|pescado|salm[óo]n|merluza|atún|atun|sardin|trucha|lenguado|langostino|camar[óo]n|camaron|mejill[óo]n|mejillon|calamar|pulpo|kani|surimi|huevo|clara de huevo|tofu|tempeh|seit[áa]n|seitan|prote[íi]na (whey|de soja|vegetal)|pavita|cordero|cabrito|conejo|vísc|visc|chinchulín|riñón|rinon|mondongo|carpaccio|carne picada|hamburguesa)"#)
    static let reLecheYogurQueso = JSRegex(#"leche|yogur|queso"#)
    // 2) Lácteos.
    static let reLacteo = JSRegex(#"\b(leche(?! de coco)|yogur|yoghurt|kéfir|kefir|requesón|cottage|cuajada|nata|burrata|mozzarella|mozarella|provolone|provoleta|parmesano|reggianito|queso|cheddar|gouda|gruyere|brie|camembert|gorgonzola|fontina|sardo|tybo|port salut|ricotta|crema de leche|caf[ée] con leche|leche de soja|cacao con leche|chocolatada)\b"#)
    // 3) Grasas: aceites, frutos secos, derivados grasos.
    static let reGrasa = JSRegex(#"\b(aceite|manteca|mantequilla|margarina|mayonesa|crema (?!de leche)|nuez|nueces|almendra|cacahuet|cacahuete|man[íi] |\bmaní$|pistacho|avellana|castaña|piñ[óo]n|semilla|ch[íi]a|lin(o|aza)|s[ée]samo|sesamo|chía|coco rallado|leche de coco|aceitun|olivas|palta|aguacate|tahini|mantequilla de maní|mantequilla de almendras|ghee|sebo)\b"#)
    // 4) Frutas y verduras frescas, salvo harinas, cereales y procesados.
    static let reProcesado = JSRegex(#"polenta|harina|copos? de ma[íi]z|corn flakes|trigo (sarraceno|burgol)|helado|tarta|torta|kuchen|pie|mermelada|jugo|néctar|nectar|licuado|smoothie|jarabe|sirope"#)
    static let reFruta = JSRegex(#"\b(manzana|banan|pl[áa]tano|naranja|mandarin|kiwi|fres|frutilla|uva|pera|durazno|melocot[óo]n|ciruela|mel[óo]n|melon|sand[íi]a|pomelo|mango|anan[áa]|piña|pina|ar[áa]ndano|arandano|cereza|lim[óo]n|limon|papaya|mam[óo]n|maracuy[áa]|higo|frambuesa|mora|d[áa]til|datil|grosella|granada|guayaba|caqui|chirimoya|tuna|n[íi]spero|nispero|carambola|pitaya|lychee|rambut[áa]n|fruta de la pasi[óo]n|coco fresco)\w*"#)
    static let reVerdura = JSRegex(#"\b(zanahoria|calabaza|zapallit|zucchini|tomate|pepino|lechug|r[úu]cula|rucula|apio|repollo|berenjena|morr[óo]n|morron|pimiento|cebolla|chauch|arveja|guisante|remolach|champiñ[óo]n|champinon|hongo|esp[áa]rrago|esparrago|alcauci|alcachof|palmito|ma[íi]z|choclo|puerro|acelga|radicheta|endivia|escarola|espinac|br[óo]coli|brocoli|coliflor|kale|repollito|rabanit|r[áa]bano|nabo|hinojo|jalapeñ|jalapeno|chile(?! con carne)|aj[íi] (picante|verde|rojo|amarillo)|pimentón fresco|jengibre fresco|cúrcuma fresca|verduras? salteadas|wok de verduras|ensalada (?!cesar|c[ée]sar))\w*"#)
    static let reAjo = JSRegex(#"^ajo$|^ajos$|^cabeza de ajo"#)     // ajo solo (no "en polvo")
    // 5) Tubérculos densos.
    static let reTuberculo = JSRegex(#"\b(papa(?! frita)|patata(?! frita)|batata|camote|boniato|yuca|mandioca|cassava|tap[íi]oca|tapioca|polenta|plátano macho|platano macho)\b"#)
    // 6) Legumbres: Mati las usa como carbohidrato.
    static let reLegumbre = JSRegex(#"\b(lenteja|garbanzo|frijol|poroto|jud[íi]a blanca|judia blanca|alubia|haba|soja cocida|soya|edamame|chícharo|chicharo)\b"#)
    // 7) Carbohidratos clásicos.
    static let reCarbohidrato = JSRegex(#"\b(arroz|pasta|fideo|spaguett|spaghet|tallarines|ravioli|ñoqui|gnocch|pan(?! con|cake)|pancake|hotcake|tostada|harina|avena|cuscus|cousc[óo]us|quinoa|cebada|bulgur|trigo (sarraceno)?|cereal|granola|galleta|tortilla(?! española)|bollillo|telera|pita|wrap|arepa|crouton|chocolate|miel|az[úu]car|edulcorante|mermelada|dulce de leche|alfajor|barrita|snack|cracker|chip|salsa de tomate|kétchup|ketchup|panqueque|waffle|donut|crep|brownie|muffin|budín|budin|bizcoch|torta|magdalena|barra cereal|gomitas|caramelo|chuche)\b"#)
    // 8) Condimentos: sin valor calórico significativo.
    static let reCondimento = JSRegex(#"\b(mostaza|vinagre|sal\b|pimienta|albahaca|comino|perejil|orégano|oregano|romero|tomillo|laurel|nuez moscada|p[áa]prika|cilantro|hierba|condimento|caldo cubo|sazonador|chimichurri|salsa picante|tabasco|sriracha)\b"#)

    /// La categoría de un alimento del plan (macros totales de la porción: la heurística solo mira proporciones).
    ///
    /// Ojo: `Alimento` decodifica `"fat": null` igual que si faltara (nil), y para la web no es lo mismo (ver
    /// `inferir(nombre:prot:carb:fat:)`). Los planes publicados traen siempre las cuatro macros.
    public static func inferir(_ a: Alimento) -> String {
        inferir(nombre: a.nombre, prot: a.prot, carb: a.carb, fat: a.fat)
    }

    /// nil es `undefined` de JS. Un `null` de JSON se pasa como 0: en esta regla vale lo mismo (`null / total` es 0 y
    /// `null > 0` es falso), mientras que `undefined / total` es NaN. La diferencia solo se ve en la grasa: con
    /// proteína y carbohidrato, `fPct < 0.3` da "lacteo" si la grasa es null y no si falta.
    public static func inferir(nombre: String?, prot: Double?, carb: Double?, fat: Double?) -> String {
        let name = (nombre ?? "").lowercased()
        if reProteina.prueba(name) && !reLecheYogurQueso.prueba(name) { return proteina }
        if reLacteo.prueba(name) { return lacteo }
        if reGrasa.prueba(name) { return grasa }
        if !reProcesado.prueba(name) && (reFruta.prueba(name) || reVerdura.prueba(name) || reAjo.prueba(name)) {
            return frutaVerdura
        }
        if reTuberculo.prueba(name) { return carbohidrato }
        if reLegumbre.prueba(name) { return carbohidrato }
        if reCarbohidrato.prueba(name) { return carbohidrato }
        if reCondimento.prueba(name) { return condimento }

        // Fallback heurístico. El total usa `|| 0`; los porcentajes, el valor pelado (undefined → NaN, que no pasa
        // ninguna comparación).
        let total = SemanticaJS.oCero(prot) + SemanticaJS.oCero(carb) + SemanticaJS.oCero(fat)
        if total == 0 { return condimento }
        let p = prot ?? .nan, c = carb ?? .nan, f = fat ?? .nan
        let pPct = p / total, cPct = c / total, fPct = f / total
        if pPct > 0.5 { return proteina }
        if cPct > 0.5 { return carbohidrato }
        if fPct > 0.5 { return grasa }
        if p > 0 && c > 0 && fPct < 0.3 { return lacteo }
        if cPct > 0.4 { return frutaVerdura }
        return mixto
    }

    /// `_categoryByMacros` (app.js:148): la categoría SOLO por macros, ignorando el nombre. Es el fallback (F8) para
    /// los alimentos del Cerebro cuyo nombre no matchea nada y caen en mixto u otra. nil si no hay macro claro.
    public static func porMacros(prot: Double?, carb: Double?, fat: Double?) -> String? {
        let p = SemanticaJS.oCero(prot) * 4, c = SemanticaJS.oCero(carb) * 4, f = SemanticaJS.oCero(fat) * 9
        let total = p + c + f
        if total <= 0 { return nil }
        if p / total > 0.45 { return proteina }
        if f / total > 0.55 { return grasa }
        if c / total > 0.5 { return carbohidrato }
        return nil
    }
}
