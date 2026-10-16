import SwiftUI
import UIKit
import MyPumpDatos

/// "Bienvenido a MyPump" (index.html:376-423 + cliente.html:3415-3484): se entra con el link personal que manda Mati
/// (por universal link se abre solo; si no, se pega acá), o se mira la demo. Con un token que ya no sirve explica qué
/// pasó y deja pegar uno nuevo.
struct AccesoView: View {
    let modelo: ModeloApp

    @State private var texto = ""
    @State private var entrando = false
    @State private var error: String?
    @FocusState private var enfocado: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)
                Marca()
                if modelo.fase == .tokenInvalido {
                    Aviso(icono: "link.badge.plus", titulo: "Este link ya no sirve",
                          texto: "Pedile a Mati un link nuevo y pegalo acá abajo.")
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                tarjetaLink
                Button {
                    entrarEnDemo()
                } label: {
                    (Text("¿Querés ver cómo funciona? ").foregroundStyle(.secondary) + Text("Ver demo").fontWeight(.semibold).foregroundStyle(Color.marcaTexto))
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ver-demo")
                Spacer(minLength: 12)
                Link("Política de privacidad", destination: URL(string: "https://app.mypumpteam.com/privacidad.html")!)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(FondoMarca())
        .animation(.snappy, value: error)
        .sensoryFeedback(.error, trigger: error) { _, nuevo in nuevo != nil }
    }

    private var tarjetaLink: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Entrá con tu link").font(.title3.weight(.semibold))
            Text("Abrí el link que te pasó Mati por WhatsApp. Si no se abre solo, copialo y pegalo acá.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                TextField("app.mypumpteam.com/?t=…", text: $texto)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($enfocado)
                    .onSubmit { Task { await entrar(texto) } }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("campo-link")
                PasteButton(payloadType: String.self) { pegados in
                    guard let t = pegados.first else { return }
                    Task { @MainActor in
                        texto = t
                        await entrar(t)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle(radius: 12))
                .tint(Color.marcaTexto)
                .frame(minHeight: 48)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.peligro)
                    .transition(.opacity)
            }
            Button {
                Task { await entrar(texto) }
            } label: {
                if entrando { ProgressView().tint(Color.sobreMarca) } else { Text("Entrar") }
            }
            .buttonStyle(BotonMarca())
            .disabled(texto.trimmingCharacters(in: .whitespaces).isEmpty || entrando)
            .opacity(texto.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("entrar")
        }
        .padding(20)
        .background(Color.tarjeta, in: .rect(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 6)
    }

    private func entrar(_ t: String) async {
        enfocado = false
        guard FormatoToken.extraer(de: t) != nil else {
            error = "No reconocí ese link. Copialo entero de WhatsApp y pegalo de nuevo."
            return
        }
        error = nil
        entrando = true
        defer { entrando = false }
        let ok = await modelo.entrar(con: t)
        if !ok {
            switch modelo.fase {
            case .tokenInvalido: error = nil   // lo explica el aviso de arriba
            case .sinServicio: error = "Sin conexión. Probá de nuevo cuando tengas señal."
            default: error = "No pudimos entrar. Probá de nuevo."
            }
        }
    }

    private func entrarEnDemo() {
        guard let r = Bundle.main.url(forResource: "rutina", withExtension: "json", subdirectory: "Demo.bundle"),
              let d = Bundle.main.url(forResource: "dieta", withExtension: "json", subdirectory: "Demo.bundle"),
              let rutina = try? Data(contentsOf: r), let dieta = try? Data(contentsOf: d) else { return }
        withAnimation(.snappy) { modelo.entrarEnDemo(rutina: rutina, dieta: dieta) }
    }
}

/// La marca: el logo de Pump Team (el del ícono) y el nombre en mayúsculas pesadas, negro, como el logo de Mati.
struct Marca: View {
    var body: some View {
        VStack(spacing: 12) {
            LogoPumpTeam(lado: 84)
                .shadow(color: Color.marca.opacity(0.4), radius: 16, y: 6)
            Text("PUMP TEAM")
                .font(Archivo.fuente(40, peso: 900, relativoA: .largeTitle))
                .tracking(0.5)
                .foregroundStyle(.primary)
            Text("Tu entrenamiento y tu nutrición, con Mati.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Fondo de las pantallas de acceso: el del sistema con un resplandor verde arriba.
struct FondoMarca: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.fondo
            RadialGradient(colors: [Color.marca.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 420)
                .frame(height: 520)
        }
        .ignoresSafeArea()
    }
}

/// Aviso destacado (link vencido, sin conexión).
struct Aviso: View {
    let icono: String
    let titulo: String
    let texto: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icono).font(.title3).foregroundStyle(Color.alerta)
            VStack(alignment: .leading, spacing: 3) {
                Text(titulo).font(.headline)
                Text(texto).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.alerta.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
