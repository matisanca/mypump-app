import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// «Tu presión», arriba de todo en Entreno mientras haya algo para hacer (`presion/CONTRATO_APP.md`, «Fácil de encontrar y súper
/// visible»): la repetición pendiente, preparar (medir el brazo y anotar el tensiómetro), la toma de hoy o el avance.
///
/// Es una tarjeta más: no tapa, no frena ni condiciona la rutina. La presión nunca frena el entrenamiento. Con la palanca
/// apagada, sin el servidor nuevo o sin la sección habilitada, no existe.
///
/// «Mi salud» (11/11): la misma tarjeta va en su bloque de presión. En Entreno (`enInicio`) sale solo con algo para hacer
/// (no en «hoy listo») y el botón lleva a Mi salud, con Presión directo encima en lo que toca.
struct TarjetaPresion: View {
    var enInicio = false
    @State private var app = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?

    private func visible(_ t: ModeloPresion.Tarjeta) -> Bool {
        if enInicio, case .hoyListo = t { return false }
        return true
    }

    var body: some View {
        if let m = app.presion, let t = m.tarjeta, visible(t) {
            Group {
                if case .hoyListo(let hechas, let total) = t {
                    // Sin botón: tocar la tarjeta abre Presión.
                    Button { navegacion?.abrirPresion(directo: false) } label: {
                        caja {
                            circulos(hechas, total)
                            texto(NP.hoyListo)
                        }
                    }
                    .buttonStyle(FilaPresionable())
                    .accessibilityElement(children: .combine)
                } else {
                    caja {
                        switch t {
                        case .repetir:
                            texto(TP.repetirPendiente)
                            boton(NP.repetir)
                        case .preparar:
                            texto(NP.tarjetaPreparar)
                            boton(NP.empezar)
                        case .toma(let hechas, let total, let faltan):
                            texto(TP.faltan(faltan))
                            if hechas == 0 { TextoPresion(NP.tarjetaSerie, fuente: .subheadline, secundario: true) }
                            circulos(hechas, total)
                            boton(NP.tomaDeHoy)
                        case .hoyListo:
                            EmptyView()
                        }
                    }
                    .accessibilityElement(children: .contain)
                }
            }
            .accessibilityIdentifier("tarjeta-presion")
        }
    }

    private func caja<C: View>(@ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(spacing: Espacio.xs) {
                Image(systemName: "heart.text.square.fill").font(.title3).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                Text(NP.tarjeta).font(.title3.weight(.bold)).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            contenido()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
        .overlay { RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).strokeBorder(Color.marcaVivo, lineWidth: 2) }
    }

    private func texto(_ t: String) -> some View { TextoPresion(t, fuente: .headline) }

    /// Un solo botón, ancho completo y con texto: abre Presión directo en lo que toca.
    private func boton(_ t: String) -> some View {
        Button(t) { if enInicio { navegacion?.irAPresion() } else { navegacion?.abrirPresion(directo: true) } }
            .buttonStyle(BotonPresion())
            .accessibilityIdentifier("tarjeta-presion-boton")
    }

    /// Un círculo por toma, lleno o vacío. Sin promedios ni colores de riesgo.
    /// Los círculos crecen con la letra del sistema (con tope, para que entren los tres en el ancho de la tarjeta).
    @ScaledMetric(relativeTo: .body) private var ladoCirculo: CGFloat = 32

    private func circulos(_ hechas: Int, _ total: Int) -> some View {
        let lado = min(ladoCirculo, 64)
        return HStack(spacing: Espacio.s) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                ZStack {
                    Circle().fill(i < hechas ? Color.marcaVivo : Color.clear)
                    Circle().strokeBorder(i < hechas ? Color.marcaVivo : Color.secondary, lineWidth: 2)
                    if i < hechas { Image(systemName: "checkmark").font(.system(size: lado * 0.42, weight: .bold)).foregroundStyle(Color.sobreMarca) }
                }
                .frame(width: lado, height: lado)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(TP.avanceAlt(hechas, total))
        .accessibilityIdentifier("tarjeta-presion-avance")
    }
}
