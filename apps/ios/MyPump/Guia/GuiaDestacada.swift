import SwiftUI
import UIKit
import MyPumpReglas
import MyPumpDatos

// «Tu guía» bien destacada (Mati, 4-nov: «cuando entro a la aplicación ni me di cuenta que había un coso de tu guía …
// tiene que ser súper llamativo, súper guiado, porque es lo primero»). Tres piezas:
// · la bienvenida de la primera vez (sin ningún video visto, una sola vez por cliente);
// · la tarjeta verde arriba de Entreno mientras falte algo, con «Ocultar» y el aviso con «Deshacer»;
// · con todo visto, la tarjeta compacta de siempre (`TarjetaGuia`).
// Nada de esto llama a `entregas_app_get`: sale del resumen y de la copia guardada.

extension Color {
    /// El verde de la tarjeta destacada, con texto blanco encima. El del logo (#1D9330) da 4,0:1 con blanco y no llega
    /// a 4,5:1 para el texto chico: va uno de la misma familia un poco más hondo (#17852B, 4,7:1; en oscuro #157A28,
    /// 5,5:1, que encandila menos sobre el fondo negro).
    static let guiaDestacada = Color(claro: UIColor(hex: 0x17852B), oscuro: UIColor(hex: 0x157A28))
    /// El texto verde del botón blanco (5,5:1 sobre blanco).
    static let guiaSobreBlanco = Color(uiColor: UIColor(hex: 0x157A28))
}

// MARK: - Tarjeta destacada

/// La tarjeta verde de arriba de Entreno, antes de terminar la guía: «EMPEZÁ POR ACÁ», el avance con su barra, el botón
/// blanco y «Ocultar» (lo mismo que «Quitar de Entreno»: la guía pasa a Mis datos).
struct TarjetaGuiaDestacada: View {
    let modelo: ModeloGuia
    let abrir: () -> Void
    let ocultar: (() -> Void)?
    @ScaledMetric(relativeTo: .title2) private var ladoIcono: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let a = modelo.avanceTarjeta
        let apilada = tamañoLetra.isAccessibilitySize
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .center, spacing: Espacio.xs) {
                Text("Empezá por acá")
                    .textCase(.uppercase)
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilitySortPriority(4)
                // Con letra de accesibilidad «Ocultar» baja al pie: al lado cortaba las dos palabras («EMPE-ZÁ», «Ocul-tar»).
                if !apilada {
                    Spacer(minLength: Espacio.xs)
                    botonOcultar
                }
            }
            // La zona de toque de «Ocultar» es de 44 pt; lo que se ve queda alineado con el margen de la tarjeta.
            .padding(.top, apilada ? 0 : -Espacio.xs)
            .padding(.trailing, apilada ? 0 : -Espacio.xs)

            let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                      : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
            disposicion {
                IconoPlayGuia(lado: ladoIcono, relleno: .white.opacity(0.2), simbolo: .white, halo: .white,
                              pulso: modelo.primeraSesionTarjeta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tu guía").font(Archivo.fuente(26, relativoA: .title2))
                    Text(ReglasGuia.textoTarjeta(a)).font(.subheadline.weight(.medium))
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tu guía, \(ReglasGuia.textoTarjeta(a))")
            .accessibilityIdentifier("guia-tarjeta-texto")
            .accessibilitySortPriority(3)

            BarraAvanceGuia(fraccion: a.fraccion)
                .padding(.vertical, 2)
                .accessibilityHidden(true)

            Button(action: abrir) {
                Label(ReglasGuia.botonTarjeta(a), systemImage: "play.fill")
            }
            .buttonStyle(BotonSobreVerde())
            .accessibilityHint("Abre los videos de Mati")
            .accessibilityIdentifier("guia-tarjeta")
            .accessibilitySortPriority(2)

            if apilada { botonOcultar.frame(maxWidth: .infinity) }
        }
        .foregroundStyle(.white)
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.guiaDestacada, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
        .shadow(color: Color.guiaDestacada.opacity(0.28), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guia-destacada")
        .onAppear { modelo.marcarTarjetaVista() }
    }
}

extension TarjetaGuiaDestacada {
    @ViewBuilder fileprivate var botonOcultar: some View {
        if let ocultar {
            Button("Ocultar", action: ocultar)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Espacio.xs)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .accessibilityHint("La guía queda en Mis datos")
                .accessibilityIdentifier("guia-ocultar")
                .accessibilitySortPriority(1)
        }
    }
}

/// La barra blanca del avance sobre el verde.
private struct BarraAvanceGuia: View {
    let fraccion: Double

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.28))
            .frame(height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { p in
                    Capsule().fill(.white)
                        .frame(width: fraccion > 0 ? max(6, p.size.width * fraccion) : 0)
                }
            }
    }
}

/// El botón principal de la tarjeta: blanco con el texto verde, en cápsula como `BotonMarca`.
private struct BotonSobreVerde: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.guiaSobreBlanco)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.white, in: .capsule)
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// El play en un círculo. Con `pulso`, un halo suave que sale cuatro veces (solo en la primera sesión) y nada con
/// «Reducir movimiento».
struct IconoPlayGuia: View {
    let lado: CGFloat
    let relleno: Color
    let simbolo: Color
    let halo: Color
    let pulso: Bool
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento
    @State private var latido = false

    var body: some View {
        ZStack {
            if pulso && !reducirMovimiento {
                Circle()
                    .stroke(halo, lineWidth: 2)
                    .scaleEffect(latido ? 1.5 : 1)
                    .opacity(latido ? 0 : 0.7)
            }
            Circle().fill(relleno)
            Image(systemName: "play.fill")
                .font(.system(size: lado * 0.38, weight: .bold))
                .foregroundStyle(simbolo)
                .offset(x: lado * 0.035)   // el triángulo se ve centrado
        }
        .frame(width: lado, height: lado)
        .accessibilityHidden(true)
        .onAppear {
            guard pulso, !reducirMovimiento, !latido else { return }
            withAnimation(.easeOut(duration: 1.8).delay(0.4).repeatCount(4, autoreverses: false)) { latido = true }
        }
    }
}

// MARK: - Aviso de «Ocultar»

/// «La encontrás en Mis datos» con «Deshacer», flotando abajo de Entreno unos segundos.
struct AvisoGuiaOculta: View {
    let deshacer: () -> Void
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let grande = tamañoLetra.isAccessibilitySize
        let forma = RoundedRectangle(cornerRadius: grande ? Radio.tarjeta : 30, style: .continuous)
        let disposicion = grande ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                                 : AnyLayout(HStackLayout(spacing: Espacio.s))
        disposicion {
            Label("La encontrás en Mis datos", systemImage: "eye.slash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, grande ? Espacio.s : 0)
            Button("Deshacer", action: deshacer)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.marcaTexto)
                .padding(.horizontal, Espacio.xs)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
                .accessibilityHint("Vuelve a poner la guía en Entreno")
                .accessibilityIdentifier("guia-deshacer")
        }
        .padding(.leading, Espacio.m)
        .padding(.trailing, grande ? Espacio.m : Espacio.xs)
        .padding(.vertical, 2)
        .vidrio(forma, interactivo: true)
        .padding(.horizontal, Espacio.m)
        // Flota sobre el contenido: con la letra más grande tapaba media pantalla. Hasta AX2 sigue creciendo.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("guia-aviso-oculta")
    }
}

// MARK: - Bienvenida

/// La primera vez, antes de todo: «Hola Tomás», cuántos videos son y cuánto duran, «Ver mi guía» y «Más tarde». Sale
/// una sola vez por cliente (queda guardado al aparecer).
struct BienvenidaGuia: View {
    let modelo: ModeloGuia
    /// El nombre de la cuenta (`ClienteInfo.nombre`): si la guía no trae `nombre_pila`, se saluda con el de pila de la cuenta.
    var nombreCuenta: String? = nil
    let ver: () -> Void
    let despues: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var ladoEscalado: CGFloat = 104
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    /// El ícono crece con la letra, con tope: con letra de accesibilidad se comía la pantalla.
    private var ladoIcono: CGFloat { min(ladoEscalado, 128) }

    var body: some View {
        Group {
            if tamañoLetra.isAccessibilitySize {
                // Con letra de accesibilidad todo se desplaza junto: los botones fijos abajo tapaban el texto.
                ScrollView {
                    VStack(spacing: Espacio.l) { contenido; botones }.padding(.top, Espacio.xl)
                }
            } else {
                // Entra en la pantalla: centrada, con los botones abajo. Si no entra, se desplaza.
                ViewThatFits(in: .vertical) {
                    contenido.frame(maxHeight: .infinity)
                    ScrollView { contenido.padding(.vertical, Espacio.l) }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { botones }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.fondo)
        .presentationDragIndicator(.visible)
        .onAppear { modelo.marcarBienvenidaVista() }
    }

    private var contenido: some View {
        VStack(spacing: Espacio.l) {
            ZStack {
                Circle().fill(Color.marcaSuave).frame(width: ladoIcono * 1.4, height: ladoIcono * 1.4)
                IconoPlayGuia(lado: ladoIcono, relleno: .marca, simbolo: .sobreMarca, halo: .marca, pulso: true)
                    .shadow(color: Color.marca.opacity(0.35), radius: 18, x: 0, y: 8)
            }
            VStack(spacing: Espacio.s) {
                Text(ReglasGuia.tituloBienvenida(modelo.guia?.nombrePila, nombreCuenta: nombreCuenta))
                    .font(Archivo.fuente(34, relativoA: .largeTitle))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("guia-bienvenida-titulo")
                Text(ReglasGuia.textoBienvenida(modelo.avanceTarjeta))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("guia-bienvenida-texto")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Espacio.l)
        .frame(maxWidth: 520)
    }

    private var botones: some View {
        VStack(spacing: Espacio.xxs) {
            Button(action: ver) { Label("Ver mi guía", systemImage: "play.fill") }
                .buttonStyle(BotonMarca())
                .accessibilityHint("Abre los videos de Mati")
                .accessibilityIdentifier("guia-bienvenida-ver")
            Button("Más tarde", action: despues)
                .font(.headline)
                .foregroundStyle(Color.marcaTexto)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(.rect)
                .accessibilityHint("La guía te queda arriba de Entreno")
                .accessibilityIdentifier("guia-bienvenida-despues")
        }
        .padding(.horizontal, Espacio.l)
        .padding(.top, Espacio.s)
        .padding(.bottom, Espacio.xs)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Color.fondo)
    }
}
