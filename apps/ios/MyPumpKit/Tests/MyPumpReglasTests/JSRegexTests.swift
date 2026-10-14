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

    @Test func puntoYBlancosComoLosDeJS() {
        // El `.` de JS solo se corta en \n, \r, U+2028 y U+2029; el de ICU también en VT, FF y NEL.
        for s in ["a\u{0B}b", "a\u{0C}b", "a\u{85}b", "a b"] { #expect(JSRegex(#"^a.b$"#).prueba(s)) }
        for s in ["a\nb", "a\rb", "a\u{2028}b", "a\u{2029}b"] { #expect(!JSRegex(#"^a.b$"#).prueba(s)) }
        // `\s` de JS: con VT y U+FEFF, sin NEL. Afuera y adentro de una clase.
        for s in ["\u{0B}", "\u{FEFF}", "\u{A0}", "\u{3000}", "\t"] { #expect(JSRegex(#"^\s$"#).prueba(s)) }
        #expect(!JSRegex(#"^\s$"#).prueba("\u{85}"))
        #expect(JSRegex(#"^[\s/]+$"#).prueba("\u{FEFF}/\u{0B} "))
        #expect(!JSRegex(#"^\S$"#).prueba("\u{FEFF}"))
        #expect(JSRegex(#"^\S$"#).prueba("\u{85}"))
    }

    @Test func negadosAdentroDeUnaClase() {
        #expect(JSRegex(#"^[\W]$"#).prueba("é"))          // en JS "é" no es de palabra
        #expect(!JSRegex(#"^[\W]$"#).prueba("a"))
        #expect(JSRegex(#"^[\D]$"#).prueba("٣"))          // ni el dígito árabe un dígito
        #expect(!JSRegex(#"^[\D]$"#).prueba("3"))
        #expect(JSRegex(#"^[\Sx]+$"#).prueba("abx"))
        #expect(!JSRegex(#"^[\S]$"#).prueba("\u{FEFF}"))
        #expect(!JSRegex(#"^[^\W]$"#).prueba("é"))
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
