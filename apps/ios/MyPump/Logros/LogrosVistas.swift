import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

// «Récords y logros» (2.3.0, palanca `wins_app`). Los textos son los de `apps/shared/vectores/wins.json` (`ReglasWins`).
// · El festejo: después de «Confirmar y cerrar», si hubo récords en el día, se abre solo. Cuelga de Entreno y no de la hoja
//   de cierre, que para entonces ya se fue.
// · El permiso (explícito): «Contarle a Mati» abre la hoja; con el sí, los récords del festejo quedan en la cola.
// · La app nunca publica nada: solo deja el logro para que Mati lo vea.

/// El festejo que espera a que se cierre la hoja de «Cerrar sesión de hoy» y el que se está mostrando.
@MainActor @Observable
final class EstadoFestejo {
    static let shared = EstadoFestejo()

    struct Festejo: Identifiable {
        let id = UUID()
        let records: [ReglasWins.Record]
    }

    /// Los récords del cierre que acaba de salir bien (los deja `CerrarDiaView`).
    var pendientes: [ReglasWins.Record] = []
    var mostrando: Festejo?

    /// La hoja de cierre ya se fue: ahora sí se puede presentar el festejo.
    func alCerrarseLaHoja() {
        guard !pendientes.isEmpty else { return }
        mostrando = Festejo(records: pendientes)
        pendientes = []
    }
}

@MainActor
enum WinsUI {
    /// ¿Se festeja al cerrar este día? Con cuenta, con la palanca y el servidor activos. En la demo con historial, siempre
    /// (sin palanca, y sin mandar nada). En los bocetos de DEBUG, nunca.
    static func festeja(_ motor: ModeloEntreno) -> Bool { Proveedor.modelo.entreno === motor && activo }

    static var activo: Bool {
        let m = Proveedor.modelo
        guard !DemoUI.bocetos else { return false }
        if m.esDemo { return m.demoHistorial != nil }
        return m.palanca.winsApp && m.wins?.prendida == true
    }

    #if DEBUG
    /// `-festejoDePrueba 1|3`: el festejo con récords de muestra, sin cerrar ninguna sesión (pruebas de interfaz y capturas).
    static var deMuestra: [ReglasWins.Record]? {
        guard let n = Int(UserDefaults.standard.string(forKey: "festejoDePrueba") ?? ""), n >= 1 else { return nil }
        let todos = ReglasWins.records([
            .init(clave: "remo con barra", nombre: "Remo con barra", anteriores: [.init(kg: 55, reps: 8)], hoy: [.init(kg: 57.5, reps: 8)]),
            .init(clave: "pullover en polea", nombre: "Pullover en polea", anteriores: [.init(kg: 25, reps: 10)], hoy: [.init(kg: 25, reps: 11)]),
            .init(clave: "curl con barra z", nombre: "Curl con barra Z", anteriores: [.init(kg: 27.5, reps: 10)], hoy: [.init(kg: 30, reps: 8)]),
        ])
        return Array(todos.prefix(n))
    }
    #endif
}

/// En la pantalla de Entreno: presenta el festejo cuando hay uno.
struct FestejoEnEntreno: ViewModifier {
    @State private var estado = EstadoFestejo.shared

    func body(content: Content) -> some View {
        @Bindable var estado = estado
        content
            .sheet(item: $estado.mostrando) { f in FestejoView(records: f.records) }
            #if DEBUG
            .task {
                guard let r = WinsUI.deMuestra, !DemoUI.abrioYa.contains("festejo") else { return }
                DemoUI.abrioYa.insert("festejo")
                // Que la cuenta de prueba termine de cargar (el permiso) antes de abrirlo.
                for _ in 0..<40 where Proveedor.modelo.fase != .listo { try? await Task.sleep(for: .milliseconds(250)) }
                try? await Task.sleep(for: .milliseconds(600))
                // Con la palanca apagada no se festeja nada, tampoco de muestra.
                guard WinsUI.activo else { return }
                estado.mostrando = .init(records: r)
            }
            #endif
    }
}

// MARK: - El festejo

struct FestejoView: View {
    let records: [ReglasWins.Record]
    @State private var modelo = Proveedor.modelo
    @Environment(\.dismiss) private var cerrar
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var entro = false
    @State private var pidiendoPermiso = false
    @State private var avisoDemo = false
    @State private var festejos = 0
    @ScaledMetric(relativeTo: .largeTitle) private var ladoTrofeo: CGFloat = 96
    @ScaledMetric(relativeTo: .largeTitle) private var tituloTamaño: CGFloat = 38

    private var wins: ModeloWins? { modelo.esDemo ? nil : modelo.wins }
    private var conPermiso: Bool { wins?.permiso == true }
    private var n: Int { records.count }

    var body: some View {
        ScrollView {
            VStack(spacing: Espacio.l) {
                trofeo
                    .padding(.top, Espacio.xl)
                VStack(spacing: Espacio.xs) {
                    Text(ReglasWins.titulo(n))
                        .font(Archivo.fuente(tituloTamaño, relativoA: .largeTitle))
                        .foregroundStyle(Color.marcaTexto)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("festejo-titulo")
                    Text(ReglasWins.subtitulo(n))
                        .font(.title3.weight(.semibold))
                        .accessibilityIdentifier("festejo-subtitulo")
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Espacio.s) {
                    ForEach(records) { FilaRecord(record: $0) }
                }
                if conPermiso {
                    Label(ReglasWins.conPermiso(n), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Espacio.m)
                        .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
                        .accessibilityIdentifier("festejo-con-permiso")
                }
                if avisoDemo {
                    Label(ReglasWins.demo, systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("festejo-demo")
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.bottom, Espacio.m)
            .anchoLectura()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.fondo)
        .safeAreaInset(edge: .bottom, spacing: 0) { botones }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: festejos)
        .accessibilityIdentifier("festejo")
        .sheet(isPresented: $pidiendoPermiso) { PermisoLogrosView(records: records) }
        .task {
            // Con el permiso ya dado, los récords quedan en la cola apenas se festejan: no hay nada que tocar.
            wins?.encolar(records)
            festejos += 1
            if reducir { entro = true } else { withAnimation(.spring(duration: 0.6, bounce: 0.45)) { entro = true } }
            AccessibilityNotification.Announcement("\(ReglasWins.titulo(n)). \(ReglasWins.subtitulo(n))").post()
        }
    }

    private var trofeo: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color.oro.opacity(0.45), Color.oro.opacity(0)], center: .center, startRadius: ladoTrofeo * 0.3,
                                     endRadius: ladoTrofeo * 1.1))
                .frame(width: ladoTrofeo * 2.2, height: ladoTrofeo * 2.2)
                .opacity(entro ? 1 : 0)
            Image(systemName: "trophy.fill")
                .font(.system(size: ladoTrofeo * 0.5, weight: .bold))
                .foregroundStyle(Color(red: 0.36, green: 0.25, blue: 0))
                .frame(width: ladoTrofeo, height: ladoTrofeo)
                .background(LinearGradient(colors: [Color.oro, Color(red: 0.93, green: 0.68, blue: 0.1)], startPoint: .top, endPoint: .bottom), in: .circle)
                .shadow(color: Color.oro.opacity(0.5), radius: 18, y: 8)
                .scaleEffect(entro ? 1 : 0.6)
                .rotationEffect(.degrees(entro ? 0 : -12))
        }
        .frame(height: ladoTrofeo * 1.5)
        .accessibilityHidden(true)
    }

    private var botones: some View {
        VStack(spacing: Espacio.xs) {
            if !conPermiso {
                Button {
                    if modelo.esDemo { withAnimation(.snappy) { avisoDemo = true } } else { pidiendoPermiso = true }
                } label: {
                    Label(ReglasWins.contarle, systemImage: "paperplane.fill")
                }
                .buttonStyle(BotonMarca())
                .accessibilityIdentifier("festejo-contarle")
                Button(ReglasWins.seguir) { cerrar() }
                    .buttonStyle(BotonSecundario(tono: .marcaTexto))
                    .accessibilityIdentifier("festejo-seguir")
            } else {
                Button(ReglasWins.seguir) { cerrar() }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("festejo-seguir")
            }
        }
        .padding(.horizontal, Espacio.m)
        .padding(.top, Espacio.s)
        .padding(.bottom, Espacio.xs)
        .anchoLectura()
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(stops: [.init(color: Color.fondo.opacity(0), location: 0), .init(color: Color.fondo, location: 0.25)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

/// Un récord: el ejercicio, la marca nueva grande, cuánto se superó y lo que había antes.
private struct FilaRecord: View {
    let record: ReglasWins.Record
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let nombre = NombreEjercicio(record.ejercicio)
        let disposicion = tamañoLetra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs))
                                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(nombre.principal)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            disposicion {
                Text(record.marca)
                    .font(.numeroMediano).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
                if !tamañoLetra.isAccessibilitySize { Spacer(minLength: Espacio.xs) }
                Text(record.chip)
                    .font(.subheadline.weight(.bold)).monospacedDigit()
                    .foregroundStyle(Color.record)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.record.opacity(0.14), in: .capsule)
            }
            Text(record.antes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nombre.principal), \(record.marca), \(record.chip). \(record.antes)")
        .accessibilityIdentifier("festejo-record-\(record.clave)")
    }
}

// MARK: - La hoja de permiso

/// «¿Compartir tus logros con Mati?»: el permiso explícito. Con el sí, `mypump_wins_permiso`; si sale bien se cierra (y los
/// récords del festejo quedan en la cola). Sin red no queda dado. «Ahora no» cierra y no se vuelve a ofrecer solo.
struct PermisoLogrosView: View {
    /// Los récords del festejo desde el que se abrió (vacío desde Mis datos).
    var records: [ReglasWins.Record] = []
    @State private var modelo = Proveedor.modelo
    @Environment(\.dismiss) private var cerrar
    @State private var enviando = false
    @State private var aviso: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                Image(systemName: "trophy.fill")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.sobreMarca)
                    .frame(width: 64, height: 64)
                    .background(Color.marca, in: .circle)
                    .accessibilityHidden(true)
                    .padding(.top, Espacio.xl)
                Text(ReglasWins.permisoTitulo)
                    .font(.title.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("permiso-logros-titulo")
                VStack(alignment: .leading, spacing: Espacio.m) {
                    ForEach(Array(ReglasWins.permisoCuerpo.enumerated()), id: \.offset) { _, t in
                        Text(t).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let aviso {
                    Label(aviso, systemImage: "wifi.exclamationmark")
                        .labelStyle(IconoTeñido(color: .peligro))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("permiso-logros-aviso")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Espacio.l)
            .padding(.bottom, Espacio.m)
            .anchoLectura()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color.fondo)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Espacio.xs) {
                Button(action: aceptar) {
                    if enviando { ProgressView().tint(Color.sobreMarca) } else { Text(ReglasWins.permisoSi) }
                }
                .buttonStyle(BotonMarca(ocupado: enviando))
                .disabled(enviando)
                .accessibilityIdentifier("permiso-logros-si")
                Button(ReglasWins.permisoNo) { cerrar() }
                    .buttonStyle(BotonSecundario(tono: .marcaTexto))
                    .disabled(enviando)
                    .accessibilityIdentifier("permiso-logros-no")
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.s)
            .padding(.bottom, Espacio.xs)
            .anchoLectura()
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(stops: [.init(color: Color.fondo.opacity(0), location: 0), .init(color: Color.fondo, location: 0.25)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(enviando)
        .animation(.snappy, value: aviso)
        .accessibilityIdentifier("permiso-logros")
    }

    private func aceptar() {
        guard let wins = modelo.wins, !modelo.esDemo else { cerrar(); return }
        enviando = true
        aviso = nil
        Task {
            let ok = await wins.darPermiso(records: records)
            enviando = false
            if ok { cerrar() } else { aviso = ReglasWins.sinRed }
        }
    }
}

// MARK: - Mis datos

/// Mis datos → «Logros»: el interruptor para compartir los logros con Mati. Prenderlo abre la hoja de permiso; apagarlo lo
/// saca en el servidor. Sin red, lo dice y el interruptor vuelve a como estaba.
struct SeccionLogros: View {
    let wins: ModeloWins
    @State private var pidiendo = false
    @State private var trabajando = false
    @State private var aviso: String?

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { wins.permiso }, set: { nuevo in
                aviso = nil
                if nuevo { pidiendo = true } else { apagar() }
            })) {
                Label { Text(ReglasWins.ajusteInterruptor) } icon: { IconoAzulejo("trophy.fill", color: .record) }
            }
            .tint(Color.marcaVivo)
            .disabled(trabajando)
            .accessibilityIdentifier("logros-interruptor")
            if let aviso {
                Text(aviso)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("logros-aviso")
            }
        } header: {
            Text(ReglasWins.ajusteSeccion)
        } footer: {
            Text(ReglasWins.ajustePie)
        }
        .sheet(isPresented: $pidiendo) { PermisoLogrosView() }
    }

    private func apagar() {
        trabajando = true
        Task {
            let ok = await wins.revocar()
            trabajando = false
            aviso = ok ? ReglasWins.desactivado : ReglasWins.sinRed
            if ok { AccessibilityNotification.Announcement(ReglasWins.desactivado).post() }
        }
    }
}
