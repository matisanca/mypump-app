import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// La tarjeta del check guiado: lo primero de Revisión con la palanca `check_guiado` prendida. Dice en qué está el check
/// de la semana y tiene un solo botón, grande y con texto, que abre el paso a paso.
struct CheckGuiadoTarjeta: View {
    let revision: ModeloRevision
    let faltanFotos: Bool
    /// Abre el flujo; con un paso, directo ahí («Subir fotos»).
    let abrir: (CheckGuiado.Paso?) -> Void

    private var estado: CheckGuiado.Estado {
        CheckGuiado.estado(enviado: revision.checkinEnviado, borrador: revision.borradorGuiado, semana: revision.semana, faltanFotos: faltanFotos)
    }

    var body: some View {
        let estado = estado
        let enviado = estado == .enviado || estado == .enviadoSinFotos
        let pasos = CheckGuiado.pasos(faltanFotos: faltanFotos)
        VStack(alignment: .leading, spacing: Espacio.m) {
            VStack(alignment: .leading, spacing: Espacio.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Check de la semana").font(.numeroMediano).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Espacio.xs)
                    if enviado {
                        Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                    }
                }
                Text(CheckGuiado.textoTarjeta(estado))
                    .font(.body)
                    .foregroundStyle(Color.apoyoCheck)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if estado == .aMedias, let b = revision.borradorGuiado {
                AvanceCheck(total: pasos.count, hechos: pasos.firstIndex(of: CheckGuiado.retomar(b, pasos: pasos)) ?? 0)
            }
            if estado == .enviado {
                Button(CheckGuiado.botonTarjeta(estado)) { abrir(nil) }
                    .buttonStyle(BotonSecundario())
                    .accessibilityIdentifier("check-guiado-abrir")
            } else {
                Button(CheckGuiado.botonTarjeta(estado)) { abrir(estado == .enviadoSinFotos ? .fotos : nil) }
                    .buttonStyle(BotonCheck())
                    .accessibilityIdentifier("check-guiado-abrir")
            }
        }
        .tarjeta(relleno: 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("check-guiado-tarjeta")
    }
}
