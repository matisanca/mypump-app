import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Las dudas en audio, dentro del recuadro de la videollamada y debajo del campo de texto: otra forma de dejar la misma
/// duda (pedido de Mati del 4-nov). Grabar, revisar (reproducir, Mandar, Grabar de nuevo, Borrar) y la lista de lo
/// mandado con su estado. Los textos son los de la web (`AUDIO-DUDAS-UI.md`).
struct AudioDudaView: View {
    @Bindable var modelo: ModeloAudioDuda
    let despues: Bool
    @State private var reproductor = ReproductorRevision()
    @Environment(\.scenePhase) private var fase

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(ReglasAudioDuda.textoInvitacion)
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            controles
            if let a = modelo.aviso {
                Text(ReglasAudioDuda.texto(a))
                    .font(.footnote)
                    .foregroundStyle(a == .quedan30 || a == .vistaPrevia ? Color.secondary : Color.peligro)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("audio-aviso")
                if a == .permisoNegado {
                    Button(ReglasAudioDuda.textoAbrirAjustes) {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    .accessibilityIdentifier("audio-ajustes")
                }
            }
            ForEach(modelo.filas) { f in FilaAudioView(fila: f, despues: despues, reintentar: { Task { await modelo.reintentar(f.id) } }) }
        }
        .padding(.top, Espacio.xs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audio-duda")
        // La región viva: cada aviso se anuncia una vez (el contador, solo al terminar).
        .onChange(of: modelo.anuncios) { _, _ in
            AccessibilityNotification.Announcement(modelo.anuncio).post()
        }
        .onChange(of: fase) { _, f in if f == .background { modelo.cortar(); reproductor.pausar() } }
        .onDisappear { modelo.cortar(); reproductor.soltar() }
    }

    @ViewBuilder private var controles: some View {
        switch modelo.fase {
        case .reposo, .pidiendoPermiso:
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    // Que el teclado no tape «Terminar».
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    modelo.tocarGrabar()
                } label: {
                    Label(ReglasAudioDuda.textoGrabar, systemImage: "mic.fill")
                }
                .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                .disabled(modelo.fase == .pidiendoPermiso)
                .accessibilityIdentifier("audio-grabar")
                if modelo.faltaPermiso {
                    Text(ReglasAudioDuda.textoAntesDelPermiso).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .grabando:
            HStack(spacing: Espacio.s) {
                Button(action: modelo.terminar) {
                    Label(ReglasAudioDuda.textoTerminar, systemImage: "stop.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Espacio.m)
                        .frame(minHeight: 44)
                        .background(Color.peligro, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ReglasAudioDuda.textoTerminarAccesible)
                .accessibilityAddTraits(.isSelected)
                .accessibilityIdentifier("audio-terminar")
                PuntoQueLate()
                Text(ReglasAudioDuda.contador(modelo.segundos))
                    .font(.body.monospacedDigit().weight(.semibold))
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("audio-contador")
                Spacer(minLength: 0)
            }
        case .revisando(let s):
            VStack(alignment: .leading, spacing: Espacio.xs) {
                HStack(spacing: Espacio.s) {
                    Button {
                        if let u = modelo.archivoActual { reproductor.alternar(u) }
                    } label: {
                        Image(systemName: reproductor.sonando ? "pause.fill" : "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(Color.marcaSuave, in: .circle)
                            .foregroundStyle(Color.marcaTexto)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(reproductor.sonando ? "Pausar tu audio" : "Escuchar tu audio")
                    .accessibilityIdentifier("audio-escuchar")
                    ProgressView(value: min(reproductor.actual, s), total: max(s, 0.1))
                        .tint(Color.marca)
                        .accessibilityHidden(true)
                    Text(ReglasAudioDuda.contador(reproductor.sonando ? reproductor.actual : s))
                        .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel("Dura \(ReglasAudioDuda.contador(s))")
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Espacio.xs) { botonesRevision }
                    VStack(alignment: .leading, spacing: Espacio.xs) { botonesRevision }
                }
            }
        }
    }

    @ViewBuilder private var botonesRevision: some View {
        Button(ReglasAudioDuda.textoMandar) { reproductor.soltar(); modelo.mandar() }
            .buttonStyle(BotonMarca(compacto: true))
            .accessibilityIdentifier("audio-mandar")
        Button(ReglasAudioDuda.textoGrabarDeNuevo) { reproductor.soltar(); modelo.grabarDeNuevo() }
            .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
            .accessibilityIdentifier("audio-de-nuevo")
        Button(ReglasAudioDuda.textoBorrar) { reproductor.soltar(); modelo.borrar() }
            .buttonStyle(BotonSecundario(compacto: true, tono: .peligro))
            .accessibilityIdentifier("audio-borrar")
    }
}

/// El punto rojo que late mientras graba. Con «Reducir movimiento», fijo.
private struct PuntoQueLate: View {
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var encendido = false

    var body: some View {
        Circle().fill(Color.peligro).frame(width: 12, height: 12)
            .opacity(sinMovimiento ? 1 : (encendido ? 1 : 0.25))
            .animation(sinMovimiento ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: encendido)
            .onAppear { encendido = true }
            .accessibilityHidden(true)
    }
}

/// Un audio mandado: mandando, no se pudo, rechazado, pasando a texto, transcripto o con error.
private struct FilaAudioView: View {
    let fila: FilaAudio
    let despues: Bool
    let reintentar: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Espacio.xs) {
            Image(systemName: icono).foregroundStyle(tono).frame(width: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                switch fila.estado {
                case .mandando:
                    Text(ReglasAudioDuda.textoMandando).foregroundStyle(.secondary)
                case .noSeMando:
                    Text(ReglasAudioDuda.textoNoSeMando).foregroundStyle(Color.peligro)
                    Button(ReglasAudioDuda.textoReintentar, action: reintentar)
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                        .accessibilityIdentifier("audio-reintentar")
                case .rechazado(let a):
                    Text(ReglasAudioDuda.texto(a)).foregroundStyle(Color.peligro)
                case .subido:
                    Text(ReglasAudioDuda.textoSubido(despues: despues)).foregroundStyle(.secondary)
                case .transcripto(let t):
                    Text(ReglasAudioDuda.textoEntendi).font(.caption.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                    Text(t)
                    Text(ReglasAudioDuda.textoSiQuedoMal).font(.caption).foregroundStyle(.secondary)
                case .error:
                    Text(ReglasAudioDuda.textoErrorTranscripcion).foregroundStyle(Color.peligro)
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("audio-fila")
    }

    private var icono: String {
        switch fila.estado {
        case .mandando: "arrow.up.circle"
        case .noSeMando, .rechazado, .error: "exclamationmark.circle"
        case .subido: "checkmark.circle"
        case .transcripto: "text.bubble"
        }
    }

    private var tono: Color {
        switch fila.estado {
        case .noSeMando, .rechazado, .error: .peligro
        case .subido, .transcripto: .marca
        case .mandando: .secondary
        }
    }
}

#if DEBUG
/// Las pruebas de interfaz y las capturas (`-audioDoble YES`): la guía de muestra con el micrófono de mentira y, con
/// `-audioServidor YES`, una cola y un servidor de mentira (la 019 simulada), así se ve «Mandando», «Listo» y la
/// transcripción sin tocar la base. `-audioEstado transcripto|mandando|noSeMando|error` deja la lista armada.
@MainActor enum AudioDudaUI {
    static func preparar(_ guia: ModeloGuia) {
        let d = UserDefaults.standard
        guard d.bool(forKey: "audioDoble") else { return }
        if d.bool(forKey: "audioServidor") {
            let s = ServidorAudioUI()
            let cliente = ClienteRPC(transporte: s)
            let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("audios-ui", isDirectory: true)
            let escrituras = Escrituras(cliente: cliente, token: "token-ui", carpetaAudios: carpeta)
            let cola = Outbox(archivo: nil) { await escrituras.ejecutar($0) }
            let m = ModeloAudioDuda(cliente: cliente, token: "token-ui", outbox: cola, disco: nil, carpeta: carpeta, esperaSondeo: .seconds(2))
            Task { await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                                       guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } }) }
            guia.usarAudios(m)
        }
        switch d.string(forKey: "audioEstado") {
        case "transcripto":
            guia.audios.ponerServidor([AudioServidor(id: "m1", estado: .transcripto, texto: "¿Puedo entrenar a la noche?")])
        case "mandando": guia.audios.ponerLocal(FilaAudio(id: "m2", estado: .mandando))
        case "noSeMando": guia.audios.ponerLocal(FilaAudio(id: "m3", estado: .noSeMando))
        case "subido": guia.audios.ponerServidor([AudioServidor(id: "m4", estado: .subido)])
        default: break
        }
    }

    static var grabador: any GrabadorAudio { UserDefaults.standard.bool(forKey: "audioDoble") ? GrabadorDobleUI() : GrabadorAV() }
}

/// La 019 de mentira: un ticket, la subida aceptada y la lista que pasa de «subido» a «transcripto» a la segunda consulta.
final class ServidorAudioUI: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private var ids: [String] = []
    private var consultas = 0

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        try? await Task.sleep(for: .milliseconds(600))
        let fn = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let texto: String = cerrojo.withLock {
            switch fn {
            case "entregas_app_audio_iniciar":
                let id = cuerpo?["p_id"]?.comoTexto ?? "x"
                return #"{"ok":true,"id":"\#(id)","bucket":"entregas-audio","ruta":"prueba/\#(id).m4a","mime":"audio/mp4"}"#
            case "entregas_app_audio_subido":
                if let id = cuerpo?["p_id"]?.comoTexto, !ids.contains(id) { ids.append(id) }
                consultas = 0
                return #"{"ok":true,"estado":"subido"}"#
            case "entregas_app_audios":
                consultas += 1
                let estado = consultas >= 2 ? #""transcripto","texto":"¿Puedo tomar café antes de entrenar?""# : #""subido""#
                return "[" + ids.map { #"{"id":"\#($0)","estado":\#(estado)}"# }.joined(separator: ",") + "]"
            default:
                return "{}"
            }
        }
        return (Data(texto.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#else
@MainActor enum AudioDudaUI {
    static func preparar(_ guia: ModeloGuia) {}
    static var grabador: any GrabadorAudio { GrabadorAV() }
}
#endif
