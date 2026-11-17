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

    @Test func conElGrabadorElPitidoNoSuena() {
        // Quedaría grabado en la duda.
        var c = CuentaSesionAudio<String>()
        c.contar("grabador")
        #expect(c.alSonarPitido() == .callar)
        #expect(c.alTerminarPitido() == .nada)
        #expect(c.soltarGrabador("grabador") == .soltar)
        #expect(c.alSonarPitido() == .mezclar)
    }

    @Test func elGrabadorNoDesactivaDebajoDeOtroDueño() {
        var c = CuentaSesionAudio<String>()
        _ = c.tomar("guia")
        c.contar("grabador")
        #expect(c.soltarGrabador("grabador") == .reproducir)
        #expect(c.soltar("guia") == .soltar)
    }

    @Test func soltarElGrabadorDosVecesNoDesactivaDosVeces() {
        // Un `empezar` fallido ya soltó; el `terminar` de después no hace nada.
        var c = CuentaSesionAudio<String>()
        c.contar("grabador")
        #expect(c.soltarGrabador("grabador") == .soltar)
        #expect(c.soltarGrabador("grabador") == .nada)
    }

    @Test func unDueñoQueYaNoSuenaNoBloqueaAlPitido() {
        // Una llamada cortó el audio del chat y quedó contado: el pitido lo descarta y vuelve a mezclarse.
        var c = CuentaSesionAudio<String>()
        _ = c.tomar("chat")
        _ = c.tomar("guia")
        #expect(c.alSonarPitido(siguen: { $0 == "guia" }) == .nada)
        #expect(c.activos == ["guia"])
        #expect(c.alSonarPitido(siguen: { _ in false }) == .mezclar)
        #expect(c.alTerminarPitido() == .soltar)
        #expect(c.soltar("guia") == .nada)
    }

    @Test func unGrabadorQueYaNoGrabaNoCallaAlPitido() {
        var c = CuentaSesionAudio<String>()
        c.contar("grabador")
        #expect(c.alSonarPitido(siguen: { _ in false }) == .mezclar)
        #expect(c.grabadores.isEmpty)
    }

    @Test func libreSoloSinDueñosNiPitido() {
        var c = CuentaSesionAudio<String>()
        #expect(c.libre)
        _ = c.alSonarPitido()
        #expect(!c.libre)
        _ = c.alTerminarPitido()
        #expect(c.libre)
        _ = c.tomar("video")
        #expect(!c.libre)
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
