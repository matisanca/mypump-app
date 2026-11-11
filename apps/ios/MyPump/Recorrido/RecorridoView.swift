import SwiftUI
import UIKit
import MyPumpDatos
import MyPumpReglas

private typealias T = TextosColaB.Recorrido

/// «Tu recorrido con Mati» (palanca `fin_plan`): cómo le fue en el plan y el pedido de una videollamada para ver cómo
/// seguir. Solo existe si el servidor dice que se ve; la app no conoce ninguna fecha.
@MainActor @Observable
final class RecorridoUI {
    static let compartido = RecorridoUI()
    var abierta = false
}

/// Si hay una hoja puesta por cualquier pantalla (no solo las de la raíz). SwiftUI no lo cuenta, UIKit sí.
@MainActor
enum HojasAbiertas {
    static var hay: Bool {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .contains { $0.isKeyWindow && $0.rootViewController?.presentedViewController != nil }
    }
}

// MARK: - Arriba de Entreno

/// La tarjeta, lo primero de Entreno: grande, con un botón con texto.
struct TarjetaRecorrido: View {
    @State private var app = Proveedor.modelo

    var body: some View {
        if app.palanca.finPlan, let e = app.recorrido?.estado {
            VStack(alignment: .leading, spacing: Espacio.s) {
                HStack(alignment: .top, spacing: Espacio.s) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(width: 42, height: 42)
                        .background(Color.marcaSuave, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T.tarjetaTitulo)
                            .font(Archivo.fuente(20, peso: 750, relativoA: .title3))
                            .accessibilityAddTraits(.isHeader)
                        Text(T.tarjeta(e.estado)).font(.body).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                Button(T.ver) { RecorridoUI.compartido.abierta = true }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("recorrido-abrir")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tarjeta()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("recorrido-tarjeta")
        }
    }
}

/// La fila de Mis datos, mientras se vea.
struct FilaRecorridoMisDatos: View {
    @State private var app = Proveedor.modelo

    var body: some View {
        if app.palanca.finPlan, app.recorrido?.estado != nil {
            Button { RecorridoUI.compartido.abierta = true } label: {
                Label { Text(T.tarjetaTitulo).foregroundStyle(.primary) } icon: { IconoAzulejo("flag.checkered", color: .marcaTexto) }
            }
            .accessibilityIdentifier("mis-datos-recorrido")
        }
    }
}

// MARK: - La hoja

struct HojaRecorrido: View {
    let modelo: ModeloRecorrido
    let cerrar: () -> Void
    @Environment(\.dynamicTypeSize) private var letra
    @FocusState private var foco: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let e = modelo.estado {
                    VStack(alignment: .leading, spacing: Espacio.l) {
                        VStack(alignment: .leading, spacing: Espacio.xs) {
                            Text(e.resumen.titulo ?? T.titulo)
                                .font(Archivo.fuente(30, peso: 800, relativoA: .largeTitle))
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("recorrido-titulo")
                            if let m = e.resumen.mensaje {
                                Text(m).font(.body).foregroundStyle(.secondary).accessibilityIdentifier("recorrido-mensaje")
                            }
                        }
                        VStack(spacing: Espacio.s) {
                            ForEach(Array(e.resumen.logros.enumerated()), id: \.offset) { n, l in
                                Logro(logro: l).accessibilityIdentifier("recorrido-logro-\(n)")
                            }
                        }
                        switch e.estado {
                        case .publicado: preguntas
                        case .pedido: cartel(T.listo, e.agendaEnLaApp ? T.listoApp : T.listoMati)
                        case .agendado: cartel(T.tarjetaAgendado, nil)
                        }
                    }
                    .padding(.horizontal, Espacio.m)
                    .padding(.top, Espacio.s)
                    .padding(.bottom, Espacio.xl)
                    .anchoLectura()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.fondo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(T.cerrar, action: cerrar).accessibilityIdentifier("recorrido-cerrar")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(TextosGimnasio.listoTeclado) { foco = nil }.fontWeight(.semibold).accessibilityIdentifier("teclado-listo")
                }
            }
            .safeAreaInset(edge: .bottom) { if modelo.estado?.estado == .publicado { pie } }
        }
        .accessibilityIdentifier("recorrido-hoja")
        .onAppear { modelo.seAbrio() }
        // Dejó de corresponder (o cambió la cuenta): no queda una hoja vacía.
        .onChange(of: modelo.estado == nil, initial: true) { _, sinNada in if sinNada { cerrar() } }
    }

    private var preguntas: some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            VStack(alignment: .leading, spacing: Espacio.xxs) {
                Text(T.antesTitulo).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(T.antesTexto).font(.body).foregroundStyle(.secondary)
            }
            ForEach(Recorrido.preguntas) { p in
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(p.texto).font(.headline)
                    TextField("", text: Binding(get: { modelo.respuestas[p.clave] ?? "" }, set: { modelo.responder(p.clave, $0) }), axis: .vertical)
                        .lineLimit(3...8)
                        .padding(Espacio.s)
                        .background(Color.campo, in: .rect(cornerRadius: Radio.control))
                        .disabled(modelo.envio == .enviando)
                        .focused($foco, equals: p.clave)
                        .accessibilityLabel(p.texto)
                        .accessibilityIdentifier("recorrido-\(p.clave)")
                }
            }
        }
    }

    private func cartel(_ titulo: String, _ bajada: String?) -> some View {
        VStack(spacing: Espacio.xs) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
            Text(titulo).font(.title3.weight(.bold))
            if let bajada { Text(bajada).font(.body).foregroundStyle(.secondary) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .tarjeta()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("recorrido-listo")
    }

    private var pie: some View {
        VStack(spacing: Espacio.xs) {
            if modelo.envio == .error {
                Label(T.error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.alerta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recorrido-error")
            }
            Button(modelo.envio == .enviando ? T.enviando : T.agendar) { Task { await modelo.pedir() } }
                .buttonStyle(BotonMarca(ocupado: modelo.envio == .enviando))
                .disabled(modelo.envio == .enviando)
                .accessibilityIdentifier("recorrido-agendar")
            // Con la letra muy grande el renglón de abajo le sacaba media pantalla a las preguntas.
            if !letra.isAccessibilitySize {
                Text(T.agendarPie).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Espacio.m)
        .padding(.vertical, Espacio.s)
        .anchoLectura()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

private struct Logro: View {
    let logro: LogroRecorrido

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(logro.valor)
                .font(Archivo.fuente(40, peso: 800, relativoA: .largeTitle))
                .foregroundStyle(Color.marcaTexto)
            Text(logro.titulo).font(.headline)
            if let d = logro.detalle { Text(d).font(.subheadline).foregroundStyle(.secondary) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - En la raíz

extension View {
    /// La hoja de «Tu recorrido» (la tarjeta y Mis datos la piden) y, la primera vez que Mati lo publica, sola.
    func hojaDeRecorrido(otraHoja: Bool) -> some View { modifier(HojaDeRecorrido(otraHoja: otraHoja)) }
}

private struct HojaDeRecorrido: ViewModifier {
    let otraHoja: Bool
    @State private var ui = RecorridoUI.compartido
    @State private var app = Proveedor.modelo
    /// Cambia para volver a esperar cuando justo se abrió otra hoja.
    @State private var reintento = 0

    private var sola: Bool { app.palanca.finPlan && app.fase == .listo && app.recorrido?.abrirSola == true }

    func body(content: Content) -> some View {
        @Bindable var ui = ui
        content
            .sheet(isPresented: $ui.abierta) {
                if let m = app.recorrido {
                    HojaRecorrido(modelo: m, cerrar: { ui.abierta = false })
                        .presentationDragIndicator(.visible)
                }
            }
            .onChange(of: app.recorrido.map(ObjectIdentifier.init)) { ui.abierta = false }
            .task(id: "\(sola)-\(otraHoja)-\(reintento)") {
                guard sola else { return }
                // Espera a que no haya ninguna otra hoja: permisos, la guía, Salud, una novedad o la de cualquier pantalla.
                while otraHoja || OnboardingPermisos.pendiente || NovedadesUI.compartido.abierta != nil || HojasAbiertas.hay {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled, sola, !otraHoja else { return }
                guard NovedadesUI.compartido.abierta == nil, !HojasAbiertas.hay else { reintento += 1; return }
                ui.abierta = true
            }
    }
}
