import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// E1 (2.0.3): «Calentamiento y aproximación», la indicación liviana antes de las series efectivas. No es un lugar para
/// cargar: filas de texto (etiqueta a la izquierda, «5 × 35 kg» a la derecha) sobre un relleno apenas distinto del de las
/// efectivas, sin campos ni controles. Tocar una fila la atenúa con un check chico y arranca el descanso de 30 s; tocarla
/// de nuevo lo deshace. No se guarda nada como carga. «Ocultar» lo colapsa a una línea y se recuerda por ejercicio.
struct PreparacionBloque: View {
    let motor: ModeloEntreno
    let lugar: String
    let series: [Preparacion.Serie]
    let sinKg: Bool
    @State private var ayuda = false
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private static let titulo = "Calentamiento y aproximación"
    /// Sin el kg de la última vez no hay número que mostrar: solo las reps.
    private var sinReferencia: Bool { sinKg || series.contains { $0.kg == nil && !$0.barraSola } }

    var body: some View {
        let oculta = motor.preparacionOculta(lugar)
        let hechas = motor.preparacionHecha(lugar)
        VStack(alignment: .leading, spacing: 0) {
            if oculta {
                colapsada
            } else {
                encabezado
                Text(sinReferencia ? "Usalas para encontrar tu peso de trabajo · 30 s entre cada una"
                                   : "30 s de descanso entre cada una · no se anotan")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("leyenda-preparacion")
                ForEach(Array(series.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Divider().overlay(Color.borde) }
                    fila(i, s, hecha: hechas.contains(i))
                }
            }
        }
        .padding(.horizontal, Espacio.s)
        .padding(.vertical, oculta ? 6 : Espacio.xs)
        .background(Color(uiColor: .quaternarySystemFill), in: .rect(cornerRadius: Radio.control, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bloque-preparacion")
        .sheet(isPresented: $ayuda) { AyudaPreparacion() }
    }

    private var encabezado: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(Self.titulo)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Button { ayuda = true } label: {
                Image(systemName: "questionmark.circle").font(.footnote).foregroundStyle(.tertiary)
                    .frame(minWidth: 28, minHeight: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cómo se arma la preparación")
            .accessibilityIdentifier("ayuda-preparacion")
            Spacer(minLength: 0)
            botonOcultar(oculta: false)
        }
    }

    private var colapsada: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(Self.titulo) · \(series.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            botonOcultar(oculta: true)
        }
    }

    private func botonOcultar(oculta: Bool) -> some View {
        Button(oculta ? "Mostrar" : "Ocultar") {
            withAnimation(.snappy) { motor.ocultarPreparacion(lugar, !oculta) }
        }
        .font(.subheadline)
        .foregroundStyle(Color.marcaTexto)
        .frame(minHeight: 32)
        .accessibilityIdentifier("ocultar-preparacion")
    }

    private func fila(_ i: Int, _ s: Preparacion.Serie, hecha: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { motor.tocarPreparacion(lugar, i) }
        } label: {
            HStack(spacing: Espacio.xs) {
                Text(s.tipo == .potenciacion ? "Potenciación" : s.etiqueta)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if s.opcional {
                    Text("opcional")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.campo, in: .capsule)
                }
                Spacer(minLength: Espacio.xs)
                cantidad(s)
                if hecha {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.exito)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(minHeight: tamañoLetra.isAccessibilitySize ? 52 : 40)
            .opacity(hecha ? 0.4 : 1)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(etiquetaAccesible(s, hecha: hecha))
        .accessibilityHint(hecha ? "Tocá para desmarcarla" : "Tocá para arrancar el descanso")
        .accessibilityIdentifier("preparacion-\(i + 1)")
        .sensoryFeedback(.selection, trigger: hecha)
    }

    /// «5 × 35 kg»: las reps en secundario, los kg en primario y semibold; sin kg de referencia, «5 reps».
    private func cantidad(_ s: Preparacion.Serie) -> some View {
        let reps = s.reps.replacingOccurrences(of: "-", with: "–")
        let kg: String? = sinKg ? nil : (s.barraSola ? "barra sola" : s.textoKg.map { "\($0) kg" })
        return Group {
            if let kg {
                Text("\(reps) × ").foregroundStyle(.secondary) + Text(kg).foregroundStyle(.primary).fontWeight(.semibold)
            } else {
                Text("\(reps) reps").foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func etiquetaAccesible(_ s: Preparacion.Serie, hecha: Bool) -> String {
        var partes = [s.etiqueta, "\(s.reps.replacingOccurrences(of: "-", with: " a ")) repeticiones"]
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
                    punto("Calentamiento", "Muy liviano, de 16 a 20 reps, para que entren en calor la articulación y el músculo. Va solo en el primer ejercicio de cada músculo.")
                    punto("Aproximaciones", "Pocas reps (5, nunca más de 6), subiendo el peso hasta el de tu primera serie efectiva. Lejos del fallo: preparan y no cansan. La subida, lo más explosiva que puedas.")
                    punto("Potenciación (opcional)", "De 1 a 3 reps con un poco más que tu peso de trabajo. Suele darte 1 o 2 reps extra en las efectivas. Si no te sentís bien, salteala.")
                    punto("Los kilos", "Se calculan solos con el que pongas en tu primera serie efectiva.")
                    punto("Descanso", "De 20 a 30 segundos entre cada una. No se anotan: solo cuentan las efectivas.")
                }
                .padding(Espacio.m)
            }
            .navigationTitle("Antes de las efectivas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() } } }
        }
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
    }

    private func punto(_ titulo: String, _ texto: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(.subheadline.weight(.semibold))
            Text(texto).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
