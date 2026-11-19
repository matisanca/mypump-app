import XCTest
@testable import MyPumpReglas

/// 2.3.3: el OK del panel no registra con el toque que cierra el teclado, y el kilo y la rueda crecen con la letra hasta 1,15.
/// Los mismos casos que `EsperaTecladoTest` de Android.
final class EsperaTecladoTests: XCTestCase {
    func testSinTecladoNuncaEspera() {
        let e = EsperaTrasTeclado()
        XCTAssertTrue(e.admite(ahora: 0))
        XCTAssertTrue(e.admite(ahora: 10_000))
    }

    func testConElTecladoArribaNoAdmite() {
        var e = EsperaTrasTeclado()
        e.ver(oculto: true, ahora: 1_000)
        XCTAssertFalse(e.admite(ahora: 1_000))
        XCTAssertFalse(e.admite(ahora: 60_000), "Escondido no registra aunque pase el tiempo")
    }

    func testAlVolverEsperaMedioSegundo() {
        var e = EsperaTrasTeclado()
        e.ver(oculto: true, ahora: 1_000)
        e.ver(oculto: false, ahora: 2_000)
        XCTAssertFalse(e.admite(ahora: 2_000), "El toque que cerró el teclado")
        XCTAssertFalse(e.admite(ahora: 2_499))
        XCTAssertTrue(e.admite(ahora: 2_500))
        XCTAssertTrue(e.admite(ahora: 9_000))
    }

    func testRepetirElMismoEstadoNoReiniciaLaEspera() {
        var e = EsperaTrasTeclado()
        e.ver(oculto: true, ahora: 0)
        e.ver(oculto: false, ahora: 1_000)
        e.ver(oculto: false, ahora: 1_400)   // la vista se vuelve a dibujar
        XCTAssertTrue(e.admite(ahora: 1_500))
        e.ver(oculto: false, ahora: 3_000)
        XCTAssertTrue(e.admite(ahora: 3_000), "Visible desde antes: no vuelve a esperar")
    }

    func testCadaVueltaDelTecladoEsperaDeNuevo() {
        var e = EsperaTrasTeclado()
        for vuelta in 0..<3 {
            let t = Double(vuelta) * 10_000
            e.ver(oculto: true, ahora: t)
            e.ver(oculto: false, ahora: t + 100)
            XCTAssertFalse(e.admite(ahora: t + 400), "vuelta \(vuelta)")
            XCTAssertTrue(e.admite(ahora: t + 600), "vuelta \(vuelta)")
        }
    }

    func testOtraDuracion() {
        var e = EsperaTrasTeclado(ms: 4_000)
        e.ver(oculto: true, ahora: 0)
        e.ver(oculto: false, ahora: 0)
        XCTAssertFalse(e.admite(ahora: 3_999))
        XCTAssertTrue(e.admite(ahora: 4_000))
        XCTAssertEqual(EsperaTrasTeclado().ms, 500)
    }

    func testLetraConTope() {
        // De la letra más chica a la de accesibilidad más grande: nunca pasa de base × 1,15 y abajo queda como la pide.
        for escala in [0.85, 1.0, 1.1, 1.15, 1.3, 1.6, 2.0, 3.1] {
            let t = LetraConTope.tamaño(46, escalado: 46 * escala)
            XCTAssertLessThanOrEqual(t, 46 * 1.15 + 1e-9, "escala \(escala)")
            if escala <= 1.15 { XCTAssertEqual(t, 46 * escala, accuracy: 1e-9) } else { XCTAssertEqual(t, 52.9, accuracy: 1e-9) }
        }
        XCTAssertEqual(LetraConTope.tamaño(76, escalado: 200), 87.4, accuracy: 1e-9)
        XCTAssertEqual(LetraConTope.tope, 1.15)
    }
}
