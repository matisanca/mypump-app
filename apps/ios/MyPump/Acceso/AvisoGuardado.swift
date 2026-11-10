import SwiftUI
import MyPumpDatos

/// El aviso de guardado de la web (GEN-04, `showSaveState`), como una pastilla flotante sobre la barra de pestañas:
/// "Guardando…" solo si el envío tarda más de 900 ms; "Guardado" solo después de un problema (reasegura); "Sin conexión,
/// se reintenta solo" mientras dure; y "Algo no se pudo guardar" 9 segundos o hasta tocarlo.
struct AvisoGuardado: View {
    let estado: EstadoGuardado
    @State private var visible: EstadoGuardado?
    @State private var ocultar: Task<Void, Never>?

    var body: some View {
        ZStack {
            if let v = visible, let c = contenido(v) {
                Label(c.texto, systemImage: c.icono)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(c.color)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: .capsule)
                    .overlay(Capsule().strokeBorder(c.color.opacity(0.25)))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .onTapGesture { withAnimation(.snappy) { visible = nil } }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.snappy, value: visible)
        .onChange(of: estado, initial: true) { _, nuevo in mostrar(nuevo) }
        .sensoryFeedback(.warning, trigger: visible) { _, v in v == .perdido }
    }

    private func mostrar(_ e: EstadoGuardado) {
        // "Algo no se pudo guardar" se queda sus 9 segundos aunque la cola vuelva a quedar quieta.
        if e == .quieto, visible == .perdido { return }
        ocultar?.cancel()
        switch e {
        case .quieto:
            // "Guardado" se deja ver un momento antes de irse.
            if visible == .guardado { programarOcultar(1.6) } else { visible = nil }
        case .guardando:
            visible = e
        case .sinConexion:
            // Como la web: avisa y se va (el banner de arriba queda si se está viendo la copia guardada).
            visible = e
            programarOcultar(3.2)
        case .guardado:
            visible = e
            programarOcultar(1.6)
        case .perdido:
            visible = e
            programarOcultar(9)
        }
    }

    private func programarOcultar(_ segundos: Double) {
        ocultar = Task { @MainActor in
            try? await Task.sleep(for: .seconds(segundos))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { visible = nil }
        }
    }

    private func contenido(_ e: EstadoGuardado) -> (texto: String, icono: String, color: Color)? {
        switch e {
        case .quieto: nil
        case .guardando: ("Guardando…", "arrow.triangle.2.circlepath", .secondary)
        case .guardado: ("Guardado", "checkmark.circle.fill", Color.exito)
        case .sinConexion: ("Sin conexión, se reintenta solo", "wifi.slash", Color.alerta)
        case .perdido: ("Algo no se pudo guardar. Arriba podés reintentarlo", "exclamationmark.triangle.fill", Color.peligro)
        }
    }
}

/// Arriba de todo cuando lo que se ve es la copia guardada en el teléfono (OFF-06).
struct BannerSinConexion: View {
    var body: some View {
        Label("Sin conexión: estás viendo tu plan guardado", systemImage: "wifi.slash")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.alerta)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.bar)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// F5 (auditoría 10/11): lo que la cola no pudo guardar queda a la vista con «Reintentar» (antes era un cartel de 9 s que
/// el alumno casi nunca veía porque estaba entrenando).
struct BannerPerdidos: View {
    let cantidad: Int
    let reintentar: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label(cantidad == 1 ? "Algo no se pudo guardar" : "\(cantidad) cosas no se pudieron guardar",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.peligro)
            Spacer(minLength: 0)
            Button("Reintentar", action: reintentar)
                .font(.footnote.weight(.bold))
                .accessibilityIdentifier("reintentar-perdidos")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
