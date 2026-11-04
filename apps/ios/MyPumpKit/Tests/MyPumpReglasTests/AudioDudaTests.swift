import Testing
@testable import MyPumpReglas

@Suite("Tu guía: la máquina del grabador de audio")
struct AudioDudaTests {
    private func grabando(desde inicio: Double = 100) -> MaquinaAudio {
        var m = MaquinaAudio()
        _ = m.manejar(.tocarGrabar)
        _ = m.manejar(.permiso(true))
        _ = m.manejar(.empezo(ahora: inicio))
        return m
    }

    @Test func grabarPidePermisoYArranca() {
        var m = MaquinaAudio()
        #expect(m.manejar(.tocarGrabar) == [.pedirPermiso])
        #expect(m.fase == .pidiendoPermiso)
        #expect(m.manejar(.permiso(true)) == [.empezarAGrabar])
        #expect(m.manejar(.empezo(ahora: 10)).isEmpty)
        #expect(m.fase == .grabando(inicio: 10) && m.grabando)
        #expect(m.segundos(ahora: 52.4) == 42.4)
    }

    @Test func permisoNegadoVuelveAReposoConElAviso() {
        var m = MaquinaAudio()
        _ = m.manejar(.tocarGrabar)
        let e = m.manejar(.permiso(false))
        #expect(m.fase == .reposo && m.aviso == .permisoNegado)
        #expect(e == [.anunciar(ReglasAudioDuda.texto(.permisoNegado))])
        // Volver a tocar «Grabar» limpia el aviso y vuelve a preguntar.
        #expect(m.manejar(.tocarGrabar) == [.pedirPermiso])
        #expect(m.aviso == nil)
    }

    @Test func sinMicrofonoUOcupadoNoGraba() {
        for a in [AvisoAudio.sinMicrofono, .ocupado] {
            var m = MaquinaAudio()
            _ = m.manejar(.tocarGrabar)
            _ = m.manejar(.permiso(true))
            #expect(m.manejar(.noEmpezo(a)) == [.descartarArchivo, .anunciar(ReglasAudioDuda.texto(a))])
            #expect(m.fase == .reposo && m.aviso == a)
        }
    }

    @Test func terminarPasaARevisarYAnunciaLoGrabado() {
        var m = grabando()
        let e = m.manejar(.terminar(ahora: 142.5))
        #expect(e == [.pararGrabador, .anunciar("Grabaste 0:42")])
        #expect(m.fase == .revisando(segundos: 42.5))
    }

    @Test func menosDeDosSegundosNoSeManda() {
        var m = grabando()
        let e = m.manejar(.terminar(ahora: 101.9))
        #expect(e == [.pararGrabador, .descartarArchivo, .anunciar("No se escuchó nada, probá de nuevo.")])
        #expect(m.fase == .reposo && m.aviso == .muyCorto)
    }

    @Test func avisaALos270UnaSolaVezYCortaALos300() {
        var m = grabando(desde: 0)
        #expect(m.manejar(.tic(ahora: 269.5)).isEmpty)
        #expect(m.manejar(.tic(ahora: 270)) == [.anunciar("Te quedan 30 segundos.")])
        #expect(m.aviso == .quedan30)
        #expect(m.manejar(.tic(ahora: 280)).isEmpty)
        let e = m.manejar(.tic(ahora: 300.4))
        #expect(e == [.pararGrabador, .anunciar("Grabaste 5:00")])
        #expect(m.fase == .revisando(segundos: 300))
        // Al revisar, el «Te quedan 30 segundos» ya no corresponde.
        #expect(m.aviso == nil)
    }

    @Test func segundoPlanoFrenaYPasaARevisar() {
        var m = grabando()
        #expect(m.manejar(.cortar(ahora: 110)) == [.pararGrabador, .anunciar("Grabaste 0:10")])
        #expect(m.fase == .revisando(segundos: 10))
        // Cortar sin grabar no hace nada.
        #expect(m.manejar(.cortar(ahora: 120)).isEmpty)
        var r = MaquinaAudio()
        #expect(r.manejar(.cortar(ahora: 1)).isEmpty)
    }

    @Test func cortarMientrasPidePermisoDescarta() {
        var m = MaquinaAudio()
        _ = m.manejar(.tocarGrabar)
        #expect(m.manejar(.cortar(ahora: 1)) == [.pararGrabador, .descartarArchivo])
        #expect(m.fase == .reposo)
    }

    @Test func revisarGrabarDeNuevoBorrarYMandar() {
        var m = grabando()
        _ = m.manejar(.terminar(ahora: 110))
        #expect(m.manejar(.grabarDeNuevo) == [.descartarArchivo, .pedirPermiso])
        #expect(m.fase == .pidiendoPermiso)
        _ = m.manejar(.permiso(true)); _ = m.manejar(.empezo(ahora: 200)); _ = m.manejar(.terminar(ahora: 205))
        #expect(m.manejar(.borrar) == [.descartarArchivo])
        #expect(m.fase == .reposo)
        _ = m.manejar(.tocarGrabar); _ = m.manejar(.permiso(true)); _ = m.manejar(.empezo(ahora: 300)); _ = m.manejar(.terminar(ahora: 307.5))
        #expect(m.manejar(.mandar(vistaPrevia: false)) == [.encolar(segundos: 7.5)])
        #expect(m.fase == .reposo)
    }

    @Test func enLaVistaPreviaMandarNoEncola() {
        var m = grabando()
        _ = m.manejar(.terminar(ahora: 105))
        #expect(m.manejar(.mandar(vistaPrevia: true)) == [.anunciar("Vista previa: el audio no se manda.")])
        #expect(m.fase == .revisando(segundos: 5) && m.aviso == .vistaPrevia)
    }

    @Test func eventosFueraDeLugarNoHacenNada() {
        var m = MaquinaAudio()
        #expect(m.manejar(.terminar(ahora: 1)).isEmpty)
        #expect(m.manejar(.mandar(vistaPrevia: false)).isEmpty)
        #expect(m.manejar(.borrar).isEmpty)
        #expect(m.manejar(.permiso(true)).isEmpty)
        var g = grabando()
        #expect(g.manejar(.tocarGrabar).isEmpty)
        #expect(g.grabando)
    }

    @Test func contador() {
        #expect(ReglasAudioDuda.contador(0) == "0:00")
        #expect(ReglasAudioDuda.contador(42.9) == "0:42")
        #expect(ReglasAudioDuda.contador(270) == "4:30")
        #expect(ReglasAudioDuda.contador(300) == "5:00")
        #expect(ReglasAudioDuda.contador(-3) == "0:00")
        #expect(ReglasAudioDuda.contador(.nan) == "0:00")
    }

    @Test func motivosDelServidor() {
        #expect(ReglasAudioDuda.aviso(motivo: "tope") == .tope)
        #expect(ReglasAudioDuda.aviso(motivo: "pendientes") == .pendientes)
        #expect(ReglasAudioDuda.aviso(motivo: "tamano") == .largo)
        #expect(ReglasAudioDuda.aviso(motivo: "largo") == .largo)
        #expect(ReglasAudioDuda.aviso(motivo: "formato") == .formato)
        // El texto de Android: nada de navegador, Safari ni Chrome (punto 14).
        #expect(ReglasAudioDuda.texto(.formato) == "Este audio está en un formato que no puedo recibir. Escribime la duda acá arriba.")
        #expect(ReglasAudioDuda.aviso(motivo: "error") == .yaFallo)
        #expect(ReglasAudioDuda.aviso(motivo: "id") == .noSeMando)
        #expect(ReglasAudioDuda.aviso(motivo: nil) == .noSeMando)
        #expect(ReglasAudioDuda.texto(.tope) == "Ya me mandaste 10 audios. Lo que te falte escribímelo o lo vemos en la llamada.")
    }

    @Test func losTextosNoLlevanDosPuntosNiGuiones() {
        let todos = [AvisoAudio.permisoNegado, .sinMicrofono, .ocupado, .muyCorto, .quedan30, .tope, .pendientes, .largo, .formato,
                     .noSeMando, .yaFallo].map(ReglasAudioDuda.texto)
            + [ReglasAudioDuda.textoInvitacion, ReglasAudioDuda.textoAntesDelPermiso, ReglasAudioDuda.textoSubido(despues: true),
               ReglasAudioDuda.textoSubido(despues: false), ReglasAudioDuda.textoErrorTranscripcion]
        for t in todos { #expect(!t.contains(":") && !t.contains(" - "), "\(t)") }
    }

    /// Mati, 4-nov 18:40: el cliente no se entera de que el audio se pasa a texto.
    @Test func losTextosNoDicenQueSePasaATexto() {
        #expect(ReglasAudioDuda.textoInvitacion == "¿Te es más fácil hablarlo? Mandame un audio, como por WhatsApp. Hasta 5 minutos cada uno.")
        #expect(ReglasAudioDuda.textoSubido(despues: false) == "Listo, me llegó tu audio, lo escucho antes de la videollamada.")
        #expect(ReglasAudioDuda.textoSubido(despues: true) == "Listo, me llegó tu audio, te contesto por WhatsApp.")
        #expect(ReglasAudioDuda.textoErrorTranscripcion == "No pude escuchar bien este audio, ¿me lo mandás de nuevo o lo escribís?")
        let todos = [ReglasAudioDuda.textoInvitacion, ReglasAudioDuda.textoSubido(despues: false), ReglasAudioDuda.textoSubido(despues: true)]
            + [AvisoAudio.tope, .pendientes, .largo, .noSeMando].map(ReglasAudioDuda.texto)
        for t in todos { #expect(!t.lowercased().contains("texto") && !t.contains("entendí"), "\(t)") }
    }

    @Test func deduplicaLasDudasTranscriptas() {
        let dudas = ["¿Puedo tomar café?", " Me duele la rodilla ", "Otra"]
        #expect(ReglasAudioDuda.sinTranscriptos(dudas, transcriptos: ["Me duele la rodilla"]) == ["¿Puedo tomar café?", "Otra"])
        #expect(ReglasAudioDuda.sinTranscriptos(dudas, transcriptos: []) == dudas)
    }
}
