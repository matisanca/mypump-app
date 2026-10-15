package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

/**
 * Los scripts que corre el WebView de la migración, corridos DE VERDAD con node sobre un `localStorage` de mentira (el de
 * verdad lo prueba `LegadoWebViewTest` en el emulador). Lo que importa: que cada valor cruce entero, también un surrogate
 * suelto, un `\0`, un emoji partido entre dos tramos y un valor de más de un tramo.
 */
class ScriptsLegadoTest {
    /** Un literal de JavaScript en ASCII puro: así el programa cruza entero por la línea de comandos de node. */
    private fun js(s: String): String = buildString {
        append('\'')
        for (c in s) {
            when {
                c == '\'' -> append("\\'")
                c == '\\' -> append("\\\\")
                c.code < 0x20 || c.code >= 0x7F -> append("\\u").append(String.format("%04x", c.code))
                else -> append(c)
            }
        }
        append('\'')
    }

    /** Clave → (expresión de JavaScript, el valor que tiene que llegar). */
    private val casos: List<Triple<String, String, String>> = listOf(
        Triple("mypump_chat", js("Mati, ¿cambio el jalón? 😀"), "Mati, ¿cambio el jalón? 😀"),
        Triple("nulo", js("nulo\u0000adentro"), "nulo\u0000adentro"),
        Triple("suelto_alto", js("a\uD83Db"), "a\uD83Db"),
        Triple("suelto_bajo", js("\uDC00z"), "\uDC00z"),
        Triple("mypump_unicode_∂ñ😀", js("valor con emoji 😀 y acento á"), "valor con emoji 😀 y acento á"),
        Triple("clave\uD800rota", js("la clave tiene un surrogate suelto"), "la clave tiene un surrogate suelto"),
        Triple("vacio", js(""), ""),
        Triple("json", js("""{"a":"b\\c","q":"\"","n":[1,2]}"""), """{"a":"b\\c","q":"\"","n":[1,2]}"""),
        Triple("separadores", js("línea párrafo fin"), "línea párrafo fin"),
        Triple("grande", "'y'.repeat(1100000) + '😀'", "y".repeat(1_100_000) + "😀"),
    )

    /** Corre la lectura como la corre la app: preparar, los tramos uno por uno, limpiar. Devuelve lo que devolvió cada paso. */
    private fun correrLectura(tramo: Int, casos: List<Triple<String, String, String>>): Pair<String, List<String>> {
        val ls = casos.joinToString(",\n") { (k, expr, _) -> "[${js(k)}, $expr]" }
        val programa = """
            const datos = new Map([$ls]);
            globalThis.window = globalThis;   // en el WebView los scripts usan window (no globalThis, que es de Chrome 71)
            globalThis.location = { origin: 'https://localhost' };
            globalThis.localStorage = {
              get length() { return datos.size; },
              key: (i) => Array.from(datos.keys())[i] ?? null,
              getItem: (k) => datos.has(k) ? datos.get(k) : null,
              setItem: () => { throw new Error('la lectura no escribe'); },
              removeItem: () => { throw new Error('la lectura no borra'); },
            };
            // evaluateJavascript devuelve el valor en JSON.
            const prep = JSON.stringify(eval(${js(LecturaJs.SCRIPT_PREPARAR)}));
            const largo = JSON.parse(prep).largo;
            const tramos = [];
            for (let i = 0; i < largo; i += $tramo) tramos.push(JSON.stringify(eval('window.__mypumpLectura.slice(' + i + ', ' + (i + $tramo) + ')')));
            eval(${js(LecturaJs.SCRIPT_LIMPIAR)});
            if (globalThis.__mypumpLectura !== undefined) throw new Error('quedó la global');
            process.stdout.write(JSON.stringify({ prep, tramos }));
        """.trimIndent()
        val salida = ValorJson.parsear(Node.correr(programa))
        return salida["prep"]!!.comoTexto!! to (salida["tramos"] as ValorJson.Lista).elementos.map { it.comoTexto!! }
    }

    private fun leer(tramo: Int, casos: List<Triple<String, String, String>> = this.casos): LecturaWebView {
        val (prep, tramos) = correrLectura(tramo, casos)
        val p = LecturaJs.preparada(prep)
        assertEquals(casos.size, p.n)
        // Cada tramo es ASCII puro: nada que Chromium pueda romper al pasarlo a UTF-8.
        assertTrue(tramos.all { t -> t.all { it.code < 0x7F } })
        val texto = tramos.joinToString("") { JsAscii.desenvolver(it)!! }
        assertEquals(p.largo, texto.length)
        return LecturaJs.decodificar(texto, p.n)
    }

    @Test
    fun cadaValorCruzaEnteroConSuFirma() {
        assumeTrue(Node.hay, "sin node en esta máquina")
        val l = leer(LecturaJs.TRAMO)
        assertEquals(casos.associate { (k, _, v) -> k to v }, l.items)
        // La firma la calculó JavaScript sobre el valor de verdad; la de Kotlin sobre lo que llegó: iguales.
        for ((k, v) in l.items) assertEquals(FirmaValor.de(v), l.firmas[k], k)
        assertEquals(FirmaValor(3, FirmaValor.de("a\uD83Db").fnv), l.firmas["suelto_alto"])
    }

    /** Con tramos de 7 caracteres los cortes caen en medio de un `\uXXXX`, de un par y de un valor: no importa. */
    @Test
    fun tramosChicos() {
        assumeTrue(Node.hay, "sin node en esta máquina")
        val chicos = casos.filter { it.first != "grande" }
        val l = leer(7, chicos)
        assertEquals(chicos.associate { (k, _, v) -> k to v }, l.items)
        for ((k, v) in l.items) assertEquals(FirmaValor.de(v), l.firmas[k], k)
    }

    @Test
    fun loQueNoCierraTira() {
        val bueno = """{"origen":"https://localhost","filas":[["k","hola",4,${FirmaValor.de("hola").fnv}]]}"""
        assertEquals(mapOf("k" to "hola"), LecturaJs.decodificar(bueno, 1).items)
        // Otra cantidad de claves que la que contó JavaScript.
        assertThrows(FallaLectura::class.java) { LecturaJs.decodificar(bueno, 2) }
        // Un valor que no es el que firmó JavaScript (se rompió en el camino).
        assertThrows(FallaLectura::class.java) { LecturaJs.decodificar(bueno.replace("\"hola\"", "\"holi\""), 1) }
        // Otro origen.
        assertThrows(FallaLectura::class.java) { LecturaJs.decodificar(bueno.replace("https://localhost", "http://localhost"), 1) }
        // Cortado.
        val e = assertThrows(FallaLectura::class.java) { LecturaJs.decodificar(bueno.dropLast(5), 1) }
        assertTrue(e.message!!.contains("no es JSON") && !e.message!!.contains("hola"))   // sin contenido en el mensaje
        // El script tiró (evaluateJavascript devuelve "null").
        assertThrows(FallaLectura::class.java) { LecturaJs.preparada("null") }
        assertThrows(FallaLectura::class.java) { LecturaJs.preparada("""{"origen":"http://localhost","n":1,"largo":10}""") }
        assertEquals(LecturaJs.Preparada("https://localhost", 3, 120), LecturaJs.preparada("""{"origen":"https://localhost","n":3,"largo":120}"""))
    }

    /** La escritura envuelta para el WebView da lo mismo que la versión en Kotlin, y su respuesta cruza en ASCII. */
    @Test
    fun laEscrituraEnvueltaHaceLoMismo() {
        assumeTrue(Node.hay, "sin node en esta máquina")
        val ls = linkedMapOf(
            "mypump_outbox_$tokenA" to "[{\"kind\":\"chat\",\"payload\":{\"contenido\":\"hola 😀\"}}]",
            "mypump_sesion_${tokenA}_b2d1" to "6f0c2a8e",
            "mypump_sesion_${tokenA}_b2d1_semana" to "3",
            "mypump_sesion_${tokenA}_díañ" to "valor\uD83D",
            "no se toca" to "nada",
        )
        val cambios = FaseRemotaLegado.CambiosEscritura(
            corrida = 2,
            borrar = mapOf(
                "mypump_outbox_$tokenA" to FirmaValor.de(ls.getValue("mypump_outbox_$tokenA")),
                "mypump_sesion_${tokenA}_b2d1" to FirmaValor.de("6f0c2a8e"),
                "mypump_sesion_${tokenA}_b2d1_semana" to FirmaValor.de("4"),   // cambió: no se borra
                "mypump_sesion_${tokenA}_díañ" to FirmaValor.de("valor\uD83D"),
                "no estaba" to FirmaValor.de("x"),
            ),
            marca = Marca("0b5c6c1e-0000-4000-8000-000000000002", 2, "2026-10-14T15:00:00Z", "2.0.0 (100)").texto,
        )
        val enKotlin = ls.toMutableMap()
        val esperado = correrEscritura(cambios, enKotlin)
        assertTrue(EscrituraJs.script(cambios).all { it.code < 0x7F })   // evaluateJavascript recibe ASCII
        val datos = ls.entries.joinToString(",") { (k, v) -> "[${js(k)}, ${js(v)}]" }
        val programa = """
            const ls = new Map([$datos]);
            globalThis.localStorage = { getItem: (k) => ls.has(k) ? ls.get(k) : null, setItem: (k, v) => { ls.set(k, String(v)); }, removeItem: (k) => { ls.delete(k); } };
            const crudo = JSON.stringify(eval(${js(EscrituraJs.script(cambios))}));
            const quedan = JSON.stringify(Object.fromEntries(ls)).replace(/[\u007f-￿]/g, (c) => '\\u' + ('000' + c.charCodeAt(0).toString(16)).slice(-4));
            process.stdout.write(JSON.stringify({ crudo, quedan }));
        """.trimIndent()
        val salida = ValorJson.parsear(Node.correr(programa))
        val crudo = salida["crudo"]!!.comoTexto!!
        assertTrue(crudo.all { it.code < 0x7F })
        assertEquals(esperado, EscrituraJs.resultado(crudo))
        assertEquals("cambio", esperado["mypump_sesion_${tokenA}_b2d1_semana"])
        assertEquals("borrada", esperado["mypump_sesion_${tokenA}_díañ"])
        assertEquals(ValorJson.Objeto(enKotlin.mapValues { ValorJson.Texto(it.value) }), ValorJson.parsear(salida["quedan"]!!.comoTexto!!))
        // Si el script tiró, evaluateJavascript devuelve null: es un error, no "nada que hacer".
        assertThrows(FallaLectura::class.java) { EscrituraJs.resultado("null") }
    }
}
