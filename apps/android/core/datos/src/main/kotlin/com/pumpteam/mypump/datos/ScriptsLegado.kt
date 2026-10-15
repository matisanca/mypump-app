package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Lo que corre adentro del WebView de la migración (en `:app`) y cómo se lee lo que devuelve. Vive acá y no en la app para
 * que los tests de la JVM corran los scripts DE VERDAD con node, como iOS corre el suyo con JavaScriptCore.
 *
 * `evaluateJavascript` devuelve el valor de JavaScript pasado a JSON por Chromium, que en el camino pasa los textos a
 * UTF-8: un surrogate suelto llegaría como U+FFFD y un par cortado entre dos tramos, roto. Por eso los dos scripts
 * devuelven JSON en ASCII puro (todo lo que no es ASCII va como `\uXXXX`), que cruza entero y se puede cortar en
 * cualquier lado.
 */
class FallaLectura(motivo: String) : Exception(motivo)

object LecturaJs {
    /** El origen de la Capacitor en Android (`androidScheme` https, el de fábrica desde Capacitor 6; la app nació con 8). */
    const val ORIGEN = "https://localhost"

    /** Caracteres por tramo de `evaluateJavascript` (la lectura entera de un cliente típico entra en uno). */
    const val TRAMO = 1_000_000

    /**
     * Enumera el `localStorage` sin escribir nada: clave, valor y la firma de cada valor (cantidad de unidades UTF-16 y
     * FNV-1a de 32 bits con `charCodeAt`, la de [FirmaValor]), calculada ACÁ, sobre el valor tal como está. Lo deja en una
     * global como JSON en ASCII y devuelve `{origen, n, largo}`; los tramos se piden con [scriptTramo].
     */
    // Con `window` y no `globalThis` (que es de Chrome 71): la Capacitor anda con WebViews desde el 60, y con uno viejo la
    // lectura tiraba y la migración no leía nada (lo encontró el emulador de Android 9, con el WebView 66, el 15-oct).
    // Nada más nuevo que ES2017 (ni `?.` ni `??`).
    val SCRIPT_PREPARAR: String = """
        (function () {
          function firma(s) {
            let h = 0x811c9dc5;
            for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
            return [s.length, h >>> 0];
          }
          const filas = [];
          const n = localStorage.length;
          for (let i = 0; i < n; i++) {
            const k = localStorage.key(i);
            if (k === null) continue;
            const v = localStorage.getItem(k);
            if (v === null) continue;
            const f = firma(v);
            filas.push([k, v, f[0], f[1]]);
          }
          const texto = ${JsAscii.FUNCION}(JSON.stringify({ origen: location.origin, filas: filas }));
          window.__mypumpLectura = texto;
          return { origen: location.origin, n: filas.length, largo: texto.length };
        })()
    """.trimIndent()

    fun scriptTramo(desde: Int, tramo: Int = TRAMO): String = "window.__mypumpLectura.slice($desde, ${desde.toLong() + tramo})"

    const val SCRIPT_LIMPIAR = "delete window.__mypumpLectura; true"

    /** Lo que devolvió [SCRIPT_PREPARAR]. */
    data class Preparada(val origen: String, val n: Int, val largo: Int)

    fun preparada(crudo: String?): Preparada {
        val o = crudo?.let { runCatching { ValorJson.parsear(it) }.getOrNull() } as? ValorJson.Objeto
            ?: throw FallaLectura("el script de lectura no devolvió nada (¿tiró una excepción?)")
        val origen = o["origen"]?.comoTexto ?: throw FallaLectura("sin origen")
        if (origen != ORIGEN) throw FallaLectura("origen inesperado: $origen")
        val n = o["n"]?.comoNumero?.takeIf { it >= 0 && it == Math.rint(it) } ?: throw FallaLectura("sin cantidad de claves")
        val largo = o["largo"]?.comoNumero?.takeIf { it >= 0 && it == Math.rint(it) && it < Int.MAX_VALUE } ?: throw FallaLectura("sin largo")
        return Preparada(origen, n.toInt(), largo.toInt())
    }

    /**
     * El JSON entero (los tramos ya pegados) a claves, valores y firmas. Lo que cruzó tiene que ser EXACTAMENTE lo que
     * estaba: la firma recalculada acá sobre el valor recibido tiene que dar la que calculó JavaScript. Si algo no cierra,
     * tira (un valor roto no es "vacío"). Los mensajes no llevan contenido: pueden ir al registro.
     */
    fun decodificar(json: String, esperadas: Int): LecturaWebView {
        val raiz = try {
            Json.parseToJsonElement(json)
        } catch (_: Exception) {
            throw FallaLectura("la lectura no es JSON (${json.length} caracteres)")
        }
        val o = raiz as? JsonObject ?: throw FallaLectura("la lectura no es un objeto")
        if ((o["origen"] as? JsonPrimitive)?.contentOrNull != ORIGEN) throw FallaLectura("la lectura es de otro origen")
        val filas = o["filas"] as? JsonArray ?: throw FallaLectura("la lectura no trae filas")
        if (filas.size != esperadas) throw FallaLectura("llegaron ${filas.size} claves de $esperadas")
        val items = LinkedHashMap<String, String>()
        val firmas = LinkedHashMap<String, FirmaValor>()
        for ((i, f) in filas.withIndex()) {
            val a = f as? JsonArray
            val k = (a?.getOrNull(0) as? JsonPrimitive)?.takeIf { it.isString }?.content
            val v = (a?.getOrNull(1) as? JsonPrimitive)?.takeIf { it.isString }?.content
            val unidades = (a?.getOrNull(2) as? JsonPrimitive)?.longOrNull
            val fnv = (a?.getOrNull(3) as? JsonPrimitive)?.longOrNull
            if (k == null || v == null || unidades == null || fnv == null || unidades !in 0..Int.MAX_VALUE || fnv !in 0..0xFFFFFFFFL) {
                throw FallaLectura("la fila $i no tiene la forma esperada")
            }
            val firma = FirmaValor(unidades.toInt(), fnv)
            if (FirmaValor.de(v) != firma) throw FallaLectura("el valor de la fila $i no llegó entero")
            if (k in items) throw FallaLectura("clave repetida en la fila $i")
            items[k] = v
            firmas[k] = firma
        }
        return LecturaWebView(items, firmas)
    }
}

/** Las claves y las firmas que leyó el WebView (la huella la pone el lector, con `stat`). */
data class LecturaWebView(val items: Map<String, String>, val firmas: Map<String, FirmaValor>)

/** La escritura de vuelta desde el WebView: el script de [FaseRemotaLegado], con la respuesta en ASCII. */
object EscrituraJs {
    /**
     * El script entero, en ASCII: lo único que no es ASCII son las claves y la marca, que van adentro de literales de texto,
     * y ahí `\uXXXX` vale lo mismo (también para un surrogate suelto).
     */
    fun script(c: FaseRemotaLegado.CambiosEscritura): String = JsAscii.escapar(
        "(function () {\nconst r = ${FaseRemotaLegado.scriptConArgumentos(c)};\nreturn ${JsAscii.FUNCION}(JSON.stringify(r));\n})()",
    )

    /** Clave → `borrada` / `no estaba` / `cambio` / `fallo`, y la marca → `ok` / `fallo`. Tira si no es eso. */
    fun resultado(crudo: String?): Map<String, String> {
        val texto = JsAscii.desenvolver(crudo) ?: throw FallaLectura("la escritura no devolvió nada (¿tiró una excepción?)")
        val o = try {
            Json.parseToJsonElement(texto) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: throw FallaLectura("la escritura devolvió algo que no es un objeto")
        return o.mapValues { (_, v) -> (v as? JsonPrimitive)?.takeIf { it.isString }?.content ?: throw FallaLectura("respuesta de la escritura mal formada") }
    }
}

/** Ida y vuelta de texto entre JavaScript y Kotlin sin perder nada. */
object JsAscii {
    /** Función de JavaScript: el texto con todo lo que no es ASCII (de U+007F en adelante, unidad por unidad) como `\uXXXX`. */
    const val FUNCION = """(function (s) { return s.replace(/[\u007f-￿]/g, function (c) { return '\\u' + ('000' + c.charCodeAt(0).toString(16)).slice(-4); }); })"""

    /** Lo mismo del lado de Kotlin, para un texto que solo tiene lo no ASCII adentro de literales de texto. */
    fun escapar(s: String): String {
        if (s.all { it.code < 0x7F }) return s
        val b = StringBuilder(s.length + 16)
        for (c in s) {
            if (c.code < 0x7F) b.append(c) else b.append("\\u").append(String.format(java.util.Locale.ROOT, "%04x", c.code))
        }
        return b.toString()
    }

    /**
     * Lo que pasa `evaluateJavascript` a su callback es el valor en JSON: un texto viene entre comillas y escapado. Devuelve
     * el texto, o null si el valor no era un texto (`null` cuando el script tira).
     */
    fun desenvolver(crudo: String?): String? {
        if (crudo == null) return null
        val e = try {
            Json.parseToJsonElement(crudo)
        } catch (_: Exception) {
            return null
        }
        return (e as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}
