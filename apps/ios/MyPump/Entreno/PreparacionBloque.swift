import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// E1 (2.0.3): «Calentamiento y aproximación», el bloque liviano antes de las series efectivas. Es una indicación, no un
/// registro: celdas de solo lectura con borde (las efectivas son las rellenas), las reps, el kg (en vivo con el de la
/// primera efectiva) y el descanso en cada fila. Tocar una fila la atenúa como hecha y arranca el descanso de 30 s; no se
/// guarda nada como carga. «Ocultar» se recuerda por ejercicio; el «?» explica el criterio en una hoja corta.
struct PreparacionBloque: View {
    let motor: ModeloEntreno
    let lugar: String
    let series: [Preparacion.Serie]
    let sinKg: Bool
    @State private var ayuda = false
    private static let descanso = "\(Preparacion.descansoSegundos) s de descanso"
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let oculta = motor.preparacionOculta(lugar)
        let hechas = motor.preparacionHecha(lugar)
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Calentamiento y aproximación")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Button { ayuda = true } label: {
                    Image(systemName: "questionmark.circle").font(.subheadline).foregroundStyle(.tertiary)
                        .frame(minWidth: 28, minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cómo se arma la preparación")
                .accessibilityIdentifier("ayuda-preparacion")
                Spacer(minLength: 0)
                Button(oculta ? "Mostrar" : "Ocultar") {
                    withAnimation(.snappy) { motor.ocultarPreparacion(lugar, !oculta) }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.marcaTexto)
                .frame(minHeight: 32)
                .accessibilityIdentifier("ocultar-preparacion")
            }
            if !oculta {
                if !sinKg && series.contains(where: { $0.kg == nil && !$0.barraSola }) {
                    Text(Preparacion.textoSinKg).font(.caption).foregroundStyle(.secondary)
                }
                encabezado
                VStack(spacing: 6) {
                    ForEach(Array(series.enumerated()), id: \.offset) { i, s in fila(i, s, hecha: hechas.contains(i)) }
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bloque-preparacion")
        .sheet(isPresented: $ayuda) { AyudaPreparacion() }
    }

    private var encabezado: some View {
        HStack(spacing: Espacio.xs) {
            Text("Serie").frame(maxWidth: .infinity, alignment: .leading)
            Text("Reps").frame(width: 64)
            if !sinKg { Text("Kg").frame(width: 84) }
        }
        .font(.caption2.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.6)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityHidden(true)
    }

    private func fila(_ i: Int, _ s: Preparacion.Serie, hecha: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { motor.tocarPreparacion(lugar, i) }
        } label: {
            HStack(spacing: Espacio.xs) {
                HStack(spacing: 6) {
                    Image(systemName: hecha ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(hecha ? Color.marcaTexto : Color(uiColor: .tertiaryLabel))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.etiqueta).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(s.nota.map { "\($0) · \(Self.descanso)" } ?? Self.descanso)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                celda(s.reps).frame(width: 64)
                if !sinKg { celda(s.textoKg ?? "–", chica: s.barraSola).frame(width: 84) }
            }
            .opacity(hecha ? 0.45 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiquetaAccesible(s, hecha: hecha))
        .accessibilityHint(hecha ? "Tocá para desmarcarla" : "Tocá cuando la hagas: arranca un descanso de 30 segundos")
        .accessibilityIdentifier("preparacion-\(i + 1)")
        .sensoryFeedback(.selection, trigger: hecha)
    }

    /// Una celda liviana: solo el borde, sin relleno (las de las efectivas son rellenas y más grandes).
    private func celda(_ texto: String, chica: Bool = false) -> some View {
        Text(texto)
            .font((chica ? Font.caption : Font.subheadline).weight(.semibold).monospacedDigit())
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: tamañoLetra.isAccessibilitySize ? 44 : 36)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 1)
            }
    }

    private func etiquetaAccesible(_ s: Preparacion.Serie, hecha: Bool) -> String {
        var partes = [s.etiqueta, "\(s.reps) repeticiones"]
        if !sinKg, let k = s.textoKg { partes.append(s.barraSola ? k : "\(k) kilos") }
        if let n = s.nota { partes.append(n) }
        if hecha { partes.append("hecha") }
        return partes.joined(separator: ", ")
    }
}

/// El «?» del bloque: el criterio en pocas líneas.
private struct AyudaPreparacion: View {
    @Environment(\.dismiss) private var cerrar

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.m) {
                    punto("Calentamiento", "16 a 20 reps muy livianas, en el primer ejercicio principal de cada músculo del día.")
                    punto("Aproximaciones", "Series de 5 reps (máximo 6), nunca al fallo, para llegar al peso de trabajo: al 60 y al 85 % en el primer principal del músculo, y una al 75 % en los siguientes. En los accesorios, una de 5 a 6 al 60 %, solo la primera vez que trabajás ese músculo.")
                    punto("Potenciación (opcional)", "En el primer principal del músculo, 1 a 3 reps con un poco más que tu peso de trabajo. Si no te sentís bien, salteala.")
                    punto("Descanso", "30 segundos entre cada una. No se registran: tu progreso cuenta solo las series efectivas.")
                }
                .padding(Espacio.m)
            }
            .navigationTitle("Antes de las efectivas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func punto(_ titulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.subheadline.weight(.semibold))
            Text(texto).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
