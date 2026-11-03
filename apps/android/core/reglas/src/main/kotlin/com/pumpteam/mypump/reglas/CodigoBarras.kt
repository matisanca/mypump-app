package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.AlimentoPropio
import com.pumpteam.mypump.modelos.ValorJson
import kotlin.math.abs
import kotlin.math.max

/**
 * El código de barras de la hoja «Agregar alimento» (2.1, S3; el «Barcode scan» de MyFitnessPal): el número que leyó el
 * escáner, la respuesta de Open Food Facts (API v2, pública y sin clave) llevada a un alimento por 100 g, y la caché por
 * código. Puro; gemelo de `CodigoBarras` de iOS (vectores en `apps/shared/vectores/barras_off.json`, con respuestas reales
 * de productos argentinos).
 */
object CodigoBarras {
    /** Los campos que se le piden a Open Food Facts (el resto no viaja). */
    const val CAMPOS = "product_name,product_name_es,brands,nutriments,serving_size,serving_quantity,serving_quantity_unit,quantity"

    /** Open Food Facts contesta en menos de un segundo; con señal mala se corta antes de que la hoja parezca colgada. */
    const val ESPERA_MS = 8_000L

    /** `https://world.openfoodfacts.org/api/v2/product/<código>.json?fields=…` (el código ya normalizado). */
    fun url(codigo: String): String = "https://world.openfoodfacts.org/api/v2/product/$codigo.json?fields=$CAMPOS"

    /** Open Food Facts pide que cada app se identifique: «PumpTeam/2.1.0 (Android)». */
    fun agenteUsuario(version: String, plataforma: String): String = "PumpTeam/$version ($plataforma)"

    // ── El número ──

    /**
     * El código como se le pregunta a Open Food Facts y como se guarda en la caché, o null si no es un EAN/UPC válido (el
     * dígito de control no cierra, otro largo, letras). EAN-13 y EAN-8 quedan igual; UPC-A (12) pasa a EAN-13 con un 0
     * adelante; UPC-E (8, [upcE]) se expande a UPC-A y de ahí a EAN-13. Un EAN-8 y un UPC-E tienen el mismo largo: decide la
     * simbología que informa el escáner.
     */
    fun normalizar(texto: String, upcE: Boolean = false): String? {
        val t = texto.trim()
        if (t.isEmpty() || !t.all { it in '0'..'9' }) return null
        if (upcE) {
            if (t.length != 8) return null
            return expandirUpcE(t)?.let { "0$it" }
        }
        return when (t.length) {
            13, 8 -> t.takeIf { controlValido(it) }
            12 -> if (controlValido(t)) "0$t" else null
            else -> null
        }
    }

    /** El dígito de control GTIN de los dígitos sin él: pesos 3 y 1 desde la derecha. */
    internal fun digitoControl(sinControl: String): Int {
        val suma = sinControl.reversed().withIndex().sumOf { (i, c) -> (c - '0') * (if (i % 2 == 0) 3 else 1) }
        return (10 - suma % 10) % 10
    }

    internal fun controlValido(c: String): Boolean = c.isNotEmpty() && digitoControl(c.dropLast(1)) == c.last() - '0'

    /** UPC-E (sistema 0 o 1, seis dígitos y el de control) a UPC-A de 12, o null si el control no cierra. */
    internal fun expandirUpcE(c: String): String? {
        if (c.length != 8 || (c[0] != '0' && c[0] != '1')) return null
        val m = c.substring(1, 7)
        val u = m[5]
        val cuerpo = when (u) {
            '0', '1', '2' -> m.substring(0, 2) + u + "0000" + m.substring(2, 5)
            '3' -> m.substring(0, 3) + "00000" + m.substring(3, 5)
            '4' -> m.substring(0, 4) + "00000" + m.substring(4, 5)
            else -> m.substring(0, 5) + "0000" + u
        }
        val a = c[0] + cuerpo + c[7]
        return a.takeIf { controlValido(it) }
    }

    // ── La respuesta de Open Food Facts ──

    /**
     * Un producto que se puede agregar: macros por 100 g ya validadas como las de un alimento propio y, si la etiqueta trae
     * porción, su medida («barra» de 23 g, «porción» de 200 g). [propio]: es un alimento propio que el cliente creó al
     * escanear un código que Open Food Facts no tenía.
     */
    data class Producto(
        val codigo: String,
        val nombre: String,
        val por100: MacrosPor100,
        val medida: String?,
        val gramosMedida: Double?,
        val propio: Boolean = false,
    ) {
        /** Para la hoja de cantidad: origen «barras» con el código (o «propio», con el código igual). */
        val candidato: AgregadosComida.Candidato
            get() = AgregadosComida.Candidato(
                nombre, por100, medida, gramosMedida,
                if (propio) AlimentoAgregado.Origen.PROPIO else AlimentoAgregado.Origen.BARRAS, codigo,
            )
    }

    /** Lo que se pudo leer de un producto incompleto: precarga el alimento propio (todo editable). */
    data class Parcial(
        val codigo: String,
        val motivo: Motivo,
        val nombre: String? = null,
        val kcal: Double? = null,
        val p: Double? = null,
        val c: Double? = null,
        val g: Double? = null,
    ) {
        /** [EN_CERO]: las macros en cero y sin calorías declaradas (no se sabe si es agua o si nadie cargó la etiqueta). */
        enum class Motivo(val valor: String) { SIN_NOMBRE("sinNombre"), FALTAN_DATOS("faltanDatos"), NO_CIERRAN("noCierran"), EN_CERO("enCero") }

        /** El renglón de la hoja: por qué no se puede agregar directo. */
        val texto: String
            get() = when (motivo) {
                Motivo.SIN_NOMBRE, Motivo.FALTAN_DATOS -> "Open Food Facts tiene este producto, pero le faltan datos de la etiqueta."
                Motivo.NO_CIERRAN -> "Open Food Facts tiene este producto, pero sus valores no cierran."
                Motivo.EN_CERO -> "Open Food Facts tiene este producto con todo en cero y sin calorías: revisá la etiqueta y cargalo."
            }
    }

    sealed interface Lectura {
        data class Encontrado(val producto: Producto) : Lectura
        data class Incompleto(val parcial: Parcial) : Lectura
        data object NoEncontrado : Lectura
    }

    /**
     * La respuesta de `/api/v2/product/<código>.json`. Encontrado solo si tiene nombre, las tres macros y los valores pasan
     * la validación del alimento propio ([AlimentoPropioNuevo.preparar] con «g»: nada de más de 950 kcal o 110 g de macros
     * cada 100 g) y las kcal cierran con las macros. Lo demás es incompleto, con lo que se pudo leer.
     *
     * Todo en cero (agua, gaseosa sin azúcar): `preparar` lo rechaza («Cargá al menos las calorías o algún macro», que es
     * para lo que tipea el cliente), así que se acepta acá, SOLO para Open Food Facts, cuando la etiqueta declara 0 kcal (o
     * 0 kJ). Sin calorías declaradas es [Parcial.Motivo.EN_CERO]: no se sabe si es agua o si faltan los datos.
     *
     * La porción solo se usa si viene en gramos: con `serving_quantity_unit` «ml» se queda por 100 g (la app muestra las
     * medidas en gramos y 200 ml no son 200 g).
     */
    fun leer(j: ValorJson, codigo: String): Lectura {
        val p = j["product"] as? ValorJson.Objeto
        if (j["status"]?.comoNumero != 1.0 || p == null) return Lectura.NoEncontrado
        var nombre = limpio(p["product_name_es"]).ifEmpty { limpio(p["product_name"]) }
        val marca = limpio(p["brands"]).split(",").map { it.trim() }.firstOrNull { it.isNotEmpty() } ?: ""
        if (nombre.isNotEmpty()) {
            nombre = nombre.replaceFirstChar { it.uppercase() }
            if (marca.isNotEmpty() && !PorcionCasera.normalizar(nombre).contains(PorcionCasera.normalizar(marca))) nombre += " ($marca)"
            nombre = AgregadosComida.recortar(nombre).trim()
        }
        val n = p["nutriments"]
        val prot = numero(n?.get("proteins_100g"))
        val carb = numero(n?.get("carbohydrates_100g"))
        val grasa = numero(n?.get("fat_100g"))
        val kcalDeclaradas = numero(n?.get("energy-kcal_100g"))
        // `energy_100g` de Open Food Facts va siempre en kJ.
        val kj = numero(n?.get("energy-kj_100g")) ?: numero(n?.get("energy_100g"))
        val kcalDeKj = kj?.let { it / 4.184 }
        val atwater = if (prot != null && carb != null && grasa != null) 4 * prot + 4 * carb + 9 * grasa else null
        val kcal: Double? = if (kcalDeclaradas != null && kcalDeKj != null) {
            // Las dos y no coinciden (pasa: un alfajor con 376 kcal y 2138 kJ): vale la que cierra con las macros.
            if (abs(kcalDeclaradas - kcalDeKj) > 0.1 * max(kcalDeclaradas, kcalDeKj) && atwater != null) {
                if (abs(kcalDeclaradas - atwater) <= abs(kcalDeKj - atwater)) kcalDeclaradas else kcalDeKj
            } else {
                kcalDeclaradas
            }
        } else {
            kcalDeclaradas ?: kcalDeKj
        }
        fun parcial(m: Parcial.Motivo) = Lectura.Incompleto(
            Parcial(codigo, m, nombre.ifEmpty { null }, kcal?.let(::jsRound), prot?.let(::r1), carb?.let(::r1), grasa?.let(::r1)),
        )
        if (nombre.isEmpty()) return parcial(Parcial.Motivo.SIN_NOMBRE)
        if (prot == null || carb == null || grasa == null || atwater == null) return parcial(Parcial.Motivo.FALTAN_DATOS)
        if (kcal != null && !(0.6 * atwater - 25 <= kcal && kcal <= 1.4 * atwater + 40)) return parcial(Parcial.Motivo.NO_CIERRAN)
        val por100 = if (prot == 0.0 && carb == 0.0 && grasa == 0.0 && (kcal?.let(::jsRound) ?: 0.0) == 0.0) {
            if (kcal == null) return parcial(Parcial.Motivo.EN_CERO)
            MacrosPor100(0.0, 0.0, 0.0, 0.0)
        } else {
            val d = AlimentoPropioNuevo.preparar(nombre, kcal, prot, carb, grasa, "g", null, "").datosONull()
                ?: return parcial(Parcial.Motivo.NO_CIERRAN)
            MacrosPor100(d.kcal, d.prot, d.carb, d.fat)
        }
        val sq = numero(p["serving_quantity"])
        val unidadPorcion = limpio(p["serving_quantity_unit"]).lowercase()
        val conMedida = sq != null && sq >= 1 && sq <= 1000 && jsRound(sq) != 100.0 && (unidadPorcion.isEmpty() || unidadPorcion == "g")
        return Lectura.Encontrado(
            Producto(
                codigo, nombre, por100,
                if (conMedida) nombreMedida(p["serving_size"]?.comoTexto) else null, if (conMedida) r1(sq!!) else null,
            ),
        )
    }

    /** La medida de la porción: «1 barra/bar (23 g)» → «barra», «1 vaso 200 ml» → «vaso»; si no, «porción». */
    internal fun nombreMedida(s: String?): String {
        val t = (s ?: "").trim().lowercase()
        if (t.length < 3 || t[0] != '1' || (t[1] != ' ' && t[1] != '\t')) return "porción"
        var i = 1
        while (i < t.length && (t[i] == ' ' || t[i] == '\t')) i++
        var j = i
        while (j < t.length && t[j] in LETRAS) j++
        val w = t.substring(i, j)
        if (w.isEmpty() || w in NO_ES_MEDIDA || w.length > 20) return "porción"
        return w
    }

    private const val LETRAS = "abcdefghijklmnopqrstuvwxyzáéíóúüñ"
    private val NO_ES_MEDIDA = setOf(
        "portion", "portions", "serving", "servings", "porcion", "porción", "porciones",
        "unit", "g", "gr", "grs", "gramo", "gramos", "ml", "cc", "oz", "kg", "l", "lt",
    )

    /**
     * Un texto de Open Food Facts saneado (lo escribe cualquiera): sin etiquetas `<…>` (las que empiezan con letra, «/» o «!»: «2 < 3» queda), con los caracteres de control y todos
     * los espacios Unicode (NBSP U+00A0 incluido: `\s` de Java no lo cubre) como separadores, y sin espacios de más. Igual
     * que en iOS.
     */
    internal fun limpio(v: ValorJson?): String {
        val s = v?.comoTexto ?: return ""
        return s.replace(ETIQUETA, " ").split(SEPARADOR).filter { it.isNotEmpty() }.joinToString(" ")
    }

    private val ETIQUETA = Regex("<[/!]?[A-Za-z][^<>]*>")
    private val SEPARADOR = Regex("[\\p{Cc}\\p{Zs}\\p{Zl}\\p{Zp}\\u00A0]+")

    /** Un número de Open Food Facts: número o texto («7,5»); negativo, infinito o ilegible = null. */
    internal fun numero(v: ValorJson?): Double? {
        val x = when (v) {
            is ValorJson.Numero -> v.valor
            is ValorJson.Texto -> AlimentoPropioNuevo.leerNumero(v.valor)
            else -> null
        }
        return x?.takeIf { it.isFinite() && it >= 0 }
    }

    private fun r1(x: Double): Double = jsRound(x * 10) / 10
}

/**
 * Lo ya buscado, por código (en el teléfono): un producto encontrado vale 30 días; uno que no está o está incompleto, un
 * día. Los alimentos propios creados desde un código no vencen. Gemela de `CacheCodigos` de iOS (mismo JSON en disco no:
 * cada plataforma guarda el suyo).
 */
class CacheCodigos(entradas: Map<String, Entrada> = emptyMap()) {
    data class Entrada(val lectura: CodigoBarras.Lectura, val ms: Long)

    private val _entradas = LinkedHashMap(entradas)
    val entradas: Map<String, Entrada> get() = _entradas

    /** Lo guardado que sigue valiendo. */
    fun vigente(codigo: String, ahoraMs: Long): CodigoBarras.Lectura? {
        val e = _entradas[codigo] ?: return null
        val vida = when (val l = e.lectura) {
            is CodigoBarras.Lectura.Encontrado -> if (l.producto.propio) Long.MAX_VALUE else 30 * DIA_MS
            else -> DIA_MS
        }
        val edad = ahoraMs - e.ms
        return if (edad in 0 until vida) e.lectura else null
    }

    /** Guarda una lectura (no pisa un propio con lo que diga Open Food Facts). Pasado el máximo, se van las más viejas (los propios, al final). */
    fun guardar(codigo: String, l: CodigoBarras.Lectura, ahoraMs: Long) {
        if (esPropio(_entradas[codigo]?.lectura) && !esPropio(l)) return
        _entradas[codigo] = Entrada(l, ahoraMs)
        if (_entradas.size > MAXIMO) {
            val viejas = _entradas.entries
                .sortedWith(compareBy<Map.Entry<String, Entrada>>({ if (esPropio(it.value.lectura)) 1 else 0 }, { it.value.ms }, { it.key }))
                .take(_entradas.size - MAXIMO).map { it.key }
            viejas.forEach { _entradas.remove(it) }
        }
    }

    /**
     * Suelta los propios creados desde un código que ya no son como el alimento propio de la cuenta: se borró o se editó (en
     * la app o en la web). El próximo escaneo vuelve a preguntar. Se compara por nombre (sin distinguir mayúsculas, como
     * `sumarPropio`), macros, unidad y gramos por unidad. Devuelve si soltó alguno.
     */
    fun conciliarPropios(propios: List<AlimentoPropio>): Boolean {
        val sueltos = _entradas.filter { (_, e) ->
            val p = (e.lectura as? CodigoBarras.Lectura.Encontrado)?.producto
            p != null && p.propio && propios.none { mismo(p, it) }
        }.keys
        sueltos.forEach { _entradas.remove(it) }
        return sueltos.isNotEmpty()
    }

    private fun esPropio(l: CodigoBarras.Lectura?) = (l as? CodigoBarras.Lectura.Encontrado)?.producto?.propio == true

    /** El archivo en el teléfono. */
    fun aValor(): ValorJson = ValorJson.Objeto(
        _entradas.mapValues { (_, e) -> ValorJson.objeto("lectura" to lecturaAValor(e.lectura), "ms" to ValorJson.Numero(e.ms.toDouble())) },
    )

    companion object {
        const val MAXIMO = 300
        const val DIA_MS = 86_400_000L

        /** Lo que no se puede leer se descarta (solo esa entrada). */
        fun desde(v: ValorJson?): CacheCodigos {
            val o = (v as? ValorJson.Objeto)?.campos ?: return CacheCodigos()
            val r = LinkedHashMap<String, Entrada>()
            for ((k, x) in o) {
                val l = lecturaDesde(x["lectura"]) ?: continue
                val ms = x["ms"]?.comoNumero?.takeIf { it.isFinite() } ?: continue
                r[k] = Entrada(l, ms.toLong())
            }
            return CacheCodigos(r)
        }

        internal fun mismo(p: CodigoBarras.Producto, a: AlimentoPropio): Boolean {
            fun cerca(x: Double?, y: Double?) = if (x == null || y == null) x == y else abs(x - y) < 0.05
            return p.nombre.lowercase() == a.nombre.lowercase() &&
                cerca(p.por100.kcal, a.kcal ?: 0.0) && cerca(p.por100.p, a.prot ?: 0.0) && cerca(p.por100.c, a.carb ?: 0.0) &&
                cerca(p.por100.g, a.fat ?: 0.0) && p.medida == a.unidad && cerca(p.gramosMedida, a.gramosPorUnidad)
        }

        private fun numeroONull(d: Double?): ValorJson = d?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo

        fun lecturaAValor(l: CodigoBarras.Lectura): ValorJson = when (l) {
            CodigoBarras.Lectura.NoEncontrado -> ValorJson.objeto("estado" to ValorJson.Texto("noEncontrado"))
            is CodigoBarras.Lectura.Encontrado -> with(l.producto) {
                ValorJson.objeto(
                    "estado" to ValorJson.Texto("encontrado"), "codigo" to ValorJson.Texto(codigo), "nombre" to ValorJson.Texto(nombre),
                    "por100" to por100.aValor(), "medida" to (medida?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
                    "gramosMedida" to numeroONull(gramosMedida), "propio" to ValorJson.Booleano(propio),
                )
            }
            is CodigoBarras.Lectura.Incompleto -> with(l.parcial) {
                ValorJson.objeto(
                    "estado" to ValorJson.Texto("incompleto"), "codigo" to ValorJson.Texto(codigo), "motivo" to ValorJson.Texto(motivo.valor),
                    "nombre" to (nombre?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo), "kcal" to numeroONull(kcal),
                    "p" to numeroONull(p), "c" to numeroONull(c), "g" to numeroONull(g),
                )
            }
        }

        fun lecturaDesde(v: ValorJson?): CodigoBarras.Lectura? {
            val o = v as? ValorJson.Objeto ?: return null
            fun num(k: String) = o[k]?.comoNumero?.takeIf { it.isFinite() && it >= 0 }
            return when (o["estado"]?.comoTexto) {
                "noEncontrado" -> CodigoBarras.Lectura.NoEncontrado
                "encontrado" -> CodigoBarras.Lectura.Encontrado(
                    CodigoBarras.Producto(
                        o["codigo"]?.comoTexto ?: return null, o["nombre"]?.comoTexto?.takeIf { it.isNotBlank() } ?: return null,
                        MacrosPor100.desde(o["por100"]) ?: return null, o["medida"]?.comoTexto, num("gramosMedida")?.takeIf { it > 0 },
                        (o["propio"] as? ValorJson.Booleano)?.valor == true,
                    ),
                )
                "incompleto" -> CodigoBarras.Lectura.Incompleto(
                    CodigoBarras.Parcial(
                        o["codigo"]?.comoTexto ?: return null,
                        CodigoBarras.Parcial.Motivo.entries.firstOrNull { it.valor == o["motivo"]?.comoTexto } ?: return null,
                        o["nombre"]?.comoTexto, num("kcal"), num("p"), num("c"), num("g"),
                    ),
                )
                else -> null
            }
        }
    }
}
