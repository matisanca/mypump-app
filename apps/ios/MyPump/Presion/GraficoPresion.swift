import Charts
import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// «Tus tomas»: la alta y la baja de cada toma, por día, tal como las anotó. Un solo color neutro, sin líneas de corte, sin
/// promedio y sin colores de riesgo (PROTOCOLO §5.3). La alta es el punto lleno y la baja el hueco.
struct GraficoPresion: View {
    let sesiones: [SesionPresion]

    private struct Punto: Identifiable {
        let id: Int
        let fecha: String
        let sis: Int
        let dia: Int
    }

    /// En orden de fecha, las últimas 30.
    private var puntos: [Punto] {
        let tomas = sesiones.reversed().flatMap { s in s.tomas.map { (s.fecha, $0) } }.suffix(30)
        return tomas.enumerated().map { i, t in Punto(id: i, fecha: t.0, sis: t.1.sis, dia: t.1.dia) }
    }

    var body: some View {
        let p = puntos
        // La fecha, una vez por día; si son muchas, salteadas.
        let primeros = p.enumerated().filter { $0.offset == 0 || p[$0.offset - 1].fecha != $0.element.fecha }.map(\.element.id)
        let paso = max(1, Int((Double(primeros.count) / 5).rounded(.up)))
        let marcas = primeros.enumerated().filter { $0.offset % paso == 0 }.map(\.element)
        let piso = Double((p.map(\.dia).min() ?? 60) - 10)
        let techo = Double((p.map(\.sis).max() ?? 140) + 10)
        VStack(alignment: .leading, spacing: Espacio.s) {
            Chart(p) { x in
                RuleMark(x: .value("Toma", x.id), yStart: .value(NP.baja, x.dia), yEnd: .value(NP.alta, x.sis))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                PointMark(x: .value("Toma", x.id), y: .value(NP.alta, x.sis))
                    .symbol { Circle().fill(Color.secondary).frame(width: 9, height: 9) }
                PointMark(x: .value("Toma", x.id), y: .value(NP.baja, x.dia))
                    .symbol { Circle().fill(Color.tarjeta).overlay(Circle().strokeBorder(Color.secondary, lineWidth: 2)).frame(width: 9, height: 9) }
            }
            .chartXScale(domain: -0.6...(Double(max(p.count, 1)) - 0.4))
            .chartYScale(domain: piso...techo)
            .chartXAxis {
                AxisMarks(values: marcas) { v in
                    AxisValueLabel { if let i = v.as(Int.self), p.indices.contains(i) { Text(NumeroPresion.diaCorto(p[i].fecha)) } }
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 190)
            .accessibilityElement()
            .accessibilityLabel(NP.graficoAlt(p.count))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("presion-grafico")
            HStack(spacing: Espacio.m) {
                HStack(spacing: Espacio.xxs) { Circle().fill(Color.secondary).frame(width: 9, height: 9); Text(NP.alta) }
                HStack(spacing: Espacio.xxs) { Circle().strokeBorder(Color.secondary, lineWidth: 2).frame(width: 9, height: 9); Text(NP.baja) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }
}

/// La lista de tomas, la más nueva primero: el día, la alta y la baja y el pulso. Sin categorías ni colores.
struct ListaTomasPresion: View {
    let sesiones: [SesionPresion]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let filas = sesiones.filter { !$0.tomas.isEmpty }
            ForEach(Array(filas.enumerated()), id: \.element.id) { i, s in
                VStack(alignment: .leading, spacing: Espacio.xxs) {
                    Text(NumeroPresion.dia(s.fecha)).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(s.tomas, id: \.orden) { t in
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: Espacio.s) { valores(t); Spacer(minLength: 0); pulso(t) }
                            VStack(alignment: .leading, spacing: 2) { valores(t); pulso(t) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(NP.alta) \(t.sis). \(NP.baja) \(t.dia). \(NP.pulso) \(t.pulso)." + (t.latidoIrregular ? " \(NP.irregular)." : ""))
                    }
                }
                .padding(.vertical, Espacio.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("presion-toma-\(i)")
                if i < filas.count - 1 { Divider() }
            }
        }
    }

    private func valores(_ t: Presion.Toma) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
            Text("\(t.sis)/\(t.dia)").font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
            if t.latidoIrregular { Image(systemName: "waveform.path.ecg").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func pulso(_ t: Presion.Toma) -> some View {
        Text("\(NP.pulso) \(t.pulso)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
    }
}
