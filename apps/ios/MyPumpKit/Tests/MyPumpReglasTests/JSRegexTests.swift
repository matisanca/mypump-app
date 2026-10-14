import Testing
@testable import MyPumpReglas

/// Casos donde ICU y JS dan distinto si no se traduce. Lo esperado es lo que da JS (verificado en node).
@Suite("JSRegex: semántica de JavaScript")
struct JSRegexTests {
    @Test func limiteDePalabraEsASCII() {
        // En JS "é" no es letra de palabra: hay límite entre "pan" y "é".
        #expect(JSRegex(#"\bpan\b"#).prueba("pané"))
        #expect(JSRegex(#"\bpan\b"#).prueba("pan dulce"))
        #expect(!JSRegex(#"\bpan\b"#).prueba("panceta"))
        // "ñ" tampoco: \bmani\b matchea dentro de "maniñ".
        #expect(JSRegex(#"\bmani\b"#).prueba("maniñ"))
        // Y una palabra que EMPIEZA con acento no tiene límite antes en JS.
        #expect(!JSRegex(#"\bárbol"#).prueba("árbol"))
    }

    @Test func wYdSonASCII() {
        #expect(JSRegex(#"^\w+$"#).prueba("arroz"))
        #expect(!JSRegex(#"^\w+$"#).prueba("arróz"))
        #expect(JSRegex(#"manzan\w*"#).prueba("manzanas"))
        #expect(!JSRegex(#"^\d$"#).prueba("٣"))   // dígito árabe: en JS \d no lo toma
    }

    @Test func clasesConCorchetesYAmpersand() {
        #expect(JSRegex(#"[[]"#).prueba("a[b"))
        #expect(JSRegex(#"[a&b]"#).prueba("&"))
        #expect(JSRegex(#"jam[óo]n"#).prueba("jamón"))
    }

    @Test func reemplazoLiteral() {
        #expect(JSRegex(#"[^a-z0-9 ]+"#).reemplazarTodo("curl $1 (x)", por: " ") == "curl  1  x ")
    }

    @Test func redondeoDeJS() {
        #expect(jsRound(2.5) == 3)
        #expect(jsRound(-2.5) == -2)
        #expect(jsRound(0.49999999999999994) == 0)
        #expect(jsRound(1234.5) == 1235)
    }
}
