import Foundation
import Testing
@testable import MyPumpDatos
import MyPumpReglas

@Suite("La última proporción de cada clip")
struct ProporcionesVideoTests {
    private func preferencias() -> UserDefaults {
        let n = "prop-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        d.removePersistentDomain(forName: n)
        return d
    }

    @Test func seGuardaPorIdYSeLee() {
        let d = preferencias()
        let p = ProporcionesVideo(preferencias: d)
        #expect(p.proporcion("FT-1") == nil)
        p.guardar(570.0 / 720.0, para: "FT-1")
        p.guardar(1, para: "FT-2")
        #expect(p.proporcion("FT-1") == 570.0 / 720.0)
        #expect(ProporcionesVideo(preferencias: d).proporcion("FT-2") == 1)
    }

    @Test func loRotoNoSeGuardaYLoRaroNoSeLee() {
        let d = preferencias()
        let p = ProporcionesVideo(preferencias: d)
        p.guardar(0, para: "FT-1")
        p.guardar(.nan, para: "FT-1")
        p.guardar(1, para: "")
        #expect(d.dictionary(forKey: ProporcionesVideo.clave) == nil)
        d.set(["FT-9": 900.0, "FT-8": "x"] as [String: Any], forKey: ProporcionesVideo.clave)
        #expect(p.proporcion("FT-9") == nil)
        #expect(p.proporcion("FT-8") == nil)
    }

    @Test func conElTopeEmpiezaDeNuevo() {
        let d = preferencias()
        let p = ProporcionesVideo(preferencias: d)
        for i in 0..<ProporcionesVideo.tope { p.guardar(1, para: "c\(i)") }
        p.guardar(2, para: "nuevo")
        #expect(p.proporcion("nuevo") == 2)
        #expect(p.proporcion("c0") == nil)
        // Uno que ya estaba se pisa sin vaciar.
        p.guardar(1.5, para: "nuevo")
        #expect(p.proporcion("nuevo") == 1.5)
    }
}

@Suite("Lo medido de cada clip, en disco")
struct RecuadrosGuardadosTests {
    @Test func porIdYUrl() {
        let n = "rec-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: n)!
        let p = ProporcionesVideo(preferencias: d)
        let u = URL(string: "https://x.invalid/FT-2b.mp4")!
        #expect(p.recuadro("FT-2b", url: u) == nil)
        p.guardar(RecuadroVideo(x: 0.32, y: 0, ancho: 0.36, alto: 1), para: "FT-2b", url: u)
        #expect(ProporcionesVideo(preferencias: d).recuadro("FT-2b", url: u) == RecuadroVideo(x: 0.32, y: 0, ancho: 0.36, alto: 1))
        // Otro archivo (lo volvieron a exportar): se mide de nuevo.
        #expect(p.recuadro("FT-2b", url: URL(string: "https://x.invalid/FT-2b-v2.mp4")!) == nil)
        p.olvidarTodo()
        #expect(p.recuadro("FT-2b", url: u) == nil)
        d.removePersistentDomain(forName: n)
    }
}
