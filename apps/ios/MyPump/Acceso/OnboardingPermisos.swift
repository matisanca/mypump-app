import SwiftUI
import MyPumpDatos

/// La primera vez con una cuenta (GEN-06, cliente.html:4447-4593): Salud y después Notificaciones, cada una con su
/// porqué. "Ahora no" nunca dispara la hoja del sistema y nunca se traba; Salud corta a los 20 s (el permiso sigue de
/// fondo); si dice que no, se le explica dónde cambiarlo. Se muestra una sola vez (`mypump_onboarding_v1`, la misma
/// clave de la web: quien ya lo vio en la app vieja no lo ve de nuevo).
struct OnboardingPermisos: View {
    let modelo: ModeloApp
    let alTerminar: () -> Void

    enum Paso { case salud, avisos }

    @State private var pasos: [Paso] = []
    @State private var i = 0
    @State private var trabajando = false
    @State private var aviso: String?
    @State private var resultado: String?
    /// Un paso que se cerró a mano mientras esperaba: lo que vuelva no se pinta encima del siguiente.
    @State private var generacion = 0

    static let clave = "mypump_onboarding_v1"
    static var pendiente: Bool { UserDefaults.standard.string(forKey: clave) != "1" }

    /// Queda vista y no vuelve. También al cerrarla deslizando: cuenta como "Ahora no" y no pide nada, como en Android.
    /// Antes solo se marcaba al terminar los pasos y volvía en cada arranque (revisión del 15-oct, hallazgo 12).
    static func marcarVista() { UserDefaults.standard.set("1", forKey: clave) }

    var body: some View {
        VStack(spacing: 18) {
            if i < pasos.count {
                let paso = pasos[i]
                Spacer(minLength: 12)
                Image(systemName: paso == .salud ? "heart.fill" : "bell.badge.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(paso == .salud ? Color.white : Color.sobreMarca)
                    .frame(width: 88, height: 88)
                    .background((paso == .salud ? Color.corazon : Color.marca).gradient, in: .rect(cornerRadius: 24, style: .continuous))
                    .shadow(color: (paso == .salud ? Color.corazon : Color.marca).opacity(0.35), radius: 16, y: 6)
                    .symbolEffect(.bounce, value: i)
                    .accessibilityHidden(true)
                    .padding(.bottom, 4)
                Text(paso == .salud ? "Conectá tu salud" : "Que no se te pase nada")
                    .font(Archivo.fuente(28, peso: 800, relativoA: .title1))
                    .multilineTextAlignment(.center)
                Text(paso == .salud
                     ? "MyPump puede leer lo que ya mide tu iPhone o tu reloj: pasos, sueño, pulso en reposo y variabilidad. Con eso Mati ve cómo venís recuperando de verdad y te ajusta el plan con datos, no a ojo."
                     : "Para que te lleguen los mensajes de Mati y su aviso de los domingos para la revisión. Nada más: no te vamos a llenar el teléfono de notificaciones.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // El aviso del domingo no se configura (pedido de Mati, 14-oct): no se promete apagarlo ni cambiar la hora.
                if paso == .salud {
                    Text("Se lee solo. Nunca escribimos nada en tu app de Salud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let texto = aviso ?? resultado {
                    Text(texto)
                        .font(.footnote)
                        .foregroundStyle(resultado != nil ? Color.alerta : .secondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
                }
                Spacer(minLength: 4)
                if resultado == nil {
                    Button {
                        Task { await aceptar(paso) }
                    } label: {
                        if trabajando { ProgressView().tint(Color.sobreMarca) } else {
                            Text(paso == .salud ? "Permitir acceso a Salud" : "Activar notificaciones")
                        }
                    }
                    .buttonStyle(BotonMarca())
                    .disabled(trabajando)
                }
                // La puerta de salida nunca se traba (la 1.0.4 dejaba "Un momento…" sin salida).
                Button(resultado == nil ? "Ahora no" : (i == pasos.count - 1 ? "Entendido" : "Seguir")) { siguiente() }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                Text("\(pasos.count > 1 ? "paso \(i + 1) de \(pasos.count) · " : "")esto lo podés cambiar después en Mis datos")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .presentationDetents([.large])
        .interactiveDismissDisabled(trabajando)
        .task {
            var p: [Paso] = []
            if modelo.salud != nil, await ModeloSalud.fuenteDelSistema?.disponible() == true { p.append(.salud) }
            p.append(.avisos)
            pasos = p
        }
    }

    private func aceptar(_ paso: Paso) async {
        trabajando = true
        let gen = generacion
        defer { if gen == generacion { trabajando = false } }
        switch paso {
        case .salud:
            let r = await modelo.salud?.conectar(esperandoComoMucho: .seconds(20))
            guard gen == generacion else { return }
            guard let r else {
                aviso = "Salud está tardando un poco más de lo normal: sigue conectándose de fondo."
                siguiente(conservarAviso: true)
                return
            }
            if r.ok { siguiente() } else { resultado = "No se pudo activar ahora. Podés intentarlo más tarde desde Mis datos." }
        case .avisos:
            let ok = await CentroAvisos.shared.activar()
            guard gen == generacion else { return }
            if ok {
                siguiente()
            } else {
                resultado = "Quedó sin permiso. Si cambiás de idea: Ajustes → Notificaciones → MyPump."
            }
        }
    }

    private func siguiente(conservarAviso: Bool = false) {
        generacion += 1
        trabajando = false
        resultado = nil
        if !conservarAviso { aviso = nil }
        if i + 1 >= pasos.count {
            Self.marcarVista()
            alTerminar()
        } else {
            i += 1
        }
    }
}
