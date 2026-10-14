import SwiftUI
import MyPumpDatos

/// El permiso para la IA (D7, guía 5.1.2(i) de Apple): una sola vez por cliente, justo antes del primer uso (mandar un
/// mensaje, analizar una foto, mandar el check). Dice qué lee la IA y de quién es, y el "no" es real: el servidor no le
/// pasa nada a ningún modelo (supabase/migrations/nativa_002, chat_worker y centinela).
struct PermisoIAView: View {
    let alDecidir: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Espacio.m) {
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.sobreMarca)
                    .frame(width: 84, height: 84)
                    .background(Color.marca.gradient, in: .rect(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.marca.opacity(0.35), radius: 16, y: 6)
                    .accessibilityHidden(true)
                    .padding(.top, Espacio.l)
                Text("Antes de seguir: el asistente de IA")
                    .font(Archivo.fuente(26, peso: 800, relativoA: .title1))
                    .multilineTextAlignment(.center)
                Text("Para contestarte más rápido, Mati usa herramientas de inteligencia artificial de OpenAI y Anthropic. Esto es lo que leen:")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Espacio.m) {
                    fila("bubble.left.and.bubble.right.fill", "Chat",
                         "Tus mensajes, tu nombre de pila y el resumen de tu check (por ejemplo, tu peso), para preparar la respuesta. Lo que es sobre tu plan, tu salud o tus números lo contesta Mati.")
                    fila("camera.fill", "Fotos",
                         "La foto de un plato o de una etiqueta que mandes a analizar, para calcular los valores.")
                    fila("checklist", "Revisión semanal",
                         "Tu check y tus métricas, para ayudar a Mati con tu devolución. Los datos de salud van sin tu nombre.")
                }
                .padding(Espacio.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.campo, in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
                Text("Si decís que no, ninguna IA lee tus datos: te contesta Mati y las fotos no se analizan. Lo podés cambiar cuando quieras en Mis datos.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Espacio.xs) {
                    Button("Acepto") { alDecidir(true) }
                        .buttonStyle(BotonMarca())
                        .accessibilityIdentifier("ia-acepto")
                    Button("No, sin IA") { alDecidir(false) }
                        .buttonStyle(BotonSecundario())
                        .accessibilityIdentifier("ia-no")
                }
                .padding(.top, Espacio.xs)
            }
            .padding(.horizontal, Espacio.l)
            .padding(.bottom, Espacio.l)
            .anchoLectura()
        }
        .background(Color.fondo)
        .presentationDetents([.large])
        .interactiveDismissDisabled()   // hay que elegir: los dos caminos siguen (el "no" también manda el mensaje)
    }

    private func fila(_ icono: String, _ titulo: String, _ texto: String) -> some View {
        HStack(alignment: .top, spacing: Espacio.s) {
            Image(systemName: icono)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.marcaTexto)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.subheadline.weight(.semibold))
                Text(texto).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Lo que el cliente estaba por hacer cuando apareció la pregunta: sigue con lo que eligió.
struct PedidoIA: Identifiable {
    let id = UUID()
    let seguir: @MainActor (Bool) -> Void
}

extension View {
    /// Muestra el permiso cuando hay un pedido; guarda la decisión (sale por la cola antes que lo demás) y sigue.
    func permisoIA(_ pedido: Binding<PedidoIA?>, modelo: ModeloApp) -> some View {
        sheet(item: pedido) { p in
            PermisoIAView { acepta in
                pedido.wrappedValue = nil
                Task { @MainActor in
                    // Primero la decisión entra a la cola, después lo que la disparó (queda detrás), y recién ahí se vacía:
                    // con mala señal el mensaje no espera a que salga la decisión.
                    await modelo.decidirConsentimientoIA(acepta, drenar: false)
                    p.seguir(acepta)
                    await modelo.drenarCola()
                }
            }
        }
    }
}
