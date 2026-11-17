import Testing
@testable import MyPumpReglas

/// La sesión de audio se decide por la cuenta de reproductores, nunca por la categoría (revisión de 83920fe0).
@Suite("Batería: la cuenta de la sesión de audio")
struct BateriaSesionAudioTests {
    @Test func elPitidoSinNadaSonandoSeMezclaYSeSuelta() {
        var c = CuentaSesionAudio<String>()
        #expect(c.alSonarPitido() == .mezclar)
        #expect(c.alTerminarPitido() == .soltar)
        #expect(c.alTerminarPitido() == .nada)
    }

    @Test func despuesDeUnVideoElPitidoVuelveASerAmbient() {
        // El caso del bug: abrir un video de técnica, cerrarlo y terminar un descanso con Spotify sonando.
        var c = CuentaSesionAudio<String>()
        #expect(c.tomar("tecnica") == .reproducir)
        #expect(c.soltar("tecnica") == .soltar)
        #expect(c.alSonarPitido() == .mezclar)
        #expect(c.alTerminarPitido() == .soltar)
    }

    @Test func conUnVideoSonandoElPitidoNoTocaLaSesion() {
        var c = CuentaSesionAudio<String>()
        _ = c.tomar("guia")
        #expect(c.alSonarPitido() == .nada)
        #expect(c.alTerminarPitido() == .nada)
        #expect(c.hayReproductor)
        #expect(c.soltar("guia") == .soltar)
    }

    @Test func conElGrabadorElPitidoNoTocaLaSesion() {
        var c = CuentaSesionAudio<String>()
        c.contar("grabador")
        #expect(c.alSonarPitido() == .nada)
        #expect(c.soltar("grabador") == .soltar)
    }

    @Test func soloElUltimoSuelta() {
        var c = CuentaSesionAudio<String>()
        _ = c.tomar("video")
        _ = c.tomar("verPorQue")
        _ = c.tomar("video")
        #expect(c.soltar("video") == .nada)
        #expect(c.soltar("video") == .nada)
        #expect(c.soltar("verPorQue") == .soltar)
        #expect(c.soltar("verPorQue") == .nada)
        #expect(!c.hayReproductor)
    }

    @Test func soltarSinHaberTomadoNoHaceNada() {
        var c = CuentaSesionAudio<String>()
        #expect(c.soltar("chat") == .nada)
        _ = c.alSonarPitido()
        #expect(c.soltar("chat") == .nada)
        #expect(c.alTerminarPitido() == .soltar)
    }

    @Test func siUnVideoArrancaDuranteElPitidoElPitidoNoLaSuelta() {
        var c = CuentaSesionAudio<String>()
        #expect(c.alSonarPitido() == .mezclar)
        #expect(c.tomar("chat") == .reproducir)
        #expect(c.alTerminarPitido() == .nada)
        #expect(c.soltar("chat") == .soltar)
        #expect(c.alTerminarPitido() == .nada)
    }
}
