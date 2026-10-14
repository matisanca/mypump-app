import SwiftUI
import Charts
import MyPumpModelos

/// Peso corporal (REV-07): la media de 7 días es lo que importa, así que va grande; el gráfico muestra los pesos del
/// día tenues y la media como línea con degradado. Abajo, la carga del día y la tendencia contra la semana pasada.
struct PesoTarjeta: View {
    let salud: [FilaSalud]
    @State private var entrada = ""
    @State private var guardados = 0
    @FocusState private var escribiendo: Bool

    struct Punto: Identifiable {
        let fecha: Date
        let kg: Double
        let media: Double
        var id: Date { fecha }
    }

    /// Un peso por fecha (gana la carga manual sobre la del reloj), ordenado, con su media móvil de 7 días.
    private var serie: [Punto] {
        var porFecha: [String: FilaSalud] = [:]
        for f in salud where f.tipo == "peso_kg" && (f.valor ?? 0) > 0 {
            if let previo = porFecha[f.fecha], previo.fuente == "manual", f.fuente != "manual" { continue }
            porFecha[f.fecha] = f
        }
        let crudos = porFecha.values.compactMap { f -> (Date, Double)? in
            guard let d = Fechas.dia(f.fecha), let v = f.valor else { return nil }
            return (d, v)
        }.sorted { $0.0 < $1.0 }
        return crudos.map { d, v in Punto(fecha: d, kg: v, media: Self.media(crudos, hasta: d) ?? v) }
    }

    /// Media de los pesos con fecha en (fin − 7 días, fin], como `_pesoMedia` de la web.
    static func media(_ serie: [(Date, Double)], hasta fin: Date, dias: Int = 7) -> Double? {
        guard let inicio = Calendar.current.date(byAdding: .day, value: -dias, to: fin) else { return nil }
        let vals = serie.filter { $0.0 > inicio && $0.0 <= fin }.map(\.1)
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }

    var body: some View {
        let s = serie
        let crudos = s.map { ($0.fecha, $0.kg) }
        let hoy = Calendar.current.startOfDay(for: .now)
        let m7 = Self.media(crudos, hasta: hoy)
        let m7previa = Calendar.current.date(byAdding: .day, value: -7, to: hoy).flatMap { Self.media(crudos, hasta: $0) }
        let deltaG = m7.flatMap { a in m7previa.map { b in Int(((a - b) * 1000).rounded()) } }

        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Peso corporal")
            VStack(alignment: .leading, spacing: Espacio.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media de 7 días").textoCeja()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(m7.map { $0.kg } ?? "—").font(.numeroGrande).contentTransition(.numericText())
                        Text("kg").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let deltaG {
                        // El color es neutro: subir o bajar no es bueno ni malo sin el objetivo, y el rango objetivo
                        // no se le muestra al cliente (lo interpreta Mati).
                        Label {
                            Text("Esta semana: \(Text(Self.textoDelta(deltaG)).bold().foregroundStyle(.primary)) vs la semana pasada")
                        } icon: {
                            Image(systemName: deltaG > 0 ? "arrow.up.right" : (deltaG < 0 ? "arrow.down.right" : "equal"))
                                .fontWeight(.bold)
                        }
                        .labelStyle(EtiquetaCompacta())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    } else if !s.isEmpty {
                        Text("Cargá tu peso unos días más para ver la tendencia semanal.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if s.count >= 2 {
                    grafico(s).frame(height: 168)
                }

                Divider()

                cargaDeHoy(hoyYa: s.last.map { Calendar.current.isDateInToday($0.fecha) } ?? false)
            }
            .tarjeta()
        }
    }

    // MARK: Gráfico

    private func grafico(_ s: [Punto]) -> some View {
        let valores = s.flatMap { [$0.kg, $0.media] }
        let minimo = (valores.min() ?? 0) - 0.3, maximo = (valores.max() ?? 1) + 0.3
        let ultimo = s.last
        return Chart {
            ForEach(s) { p in
                AreaMark(x: .value("Fecha", p.fecha), yStart: .value("Base", minimo), yEnd: .value("Media", p.media))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.marcaVivo.opacity(0.28), Color.marcaVivo.opacity(0.0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Fecha", p.fecha), y: .value("Media", p.media))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.marcaVivo)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                PointMark(x: .value("Fecha", p.fecha), y: .value("Kg del día", p.kg))
                    .symbolSize(18)
                    .foregroundStyle(Color.secondary.opacity(0.45))
            }
            if let ultimo {
                PointMark(x: .value("Fecha", ultimo.fecha), y: .value("Media", ultimo.media))
                    .symbolSize(90)
                    .foregroundStyle(Color.tarjeta)
                PointMark(x: .value("Fecha", ultimo.fecha), y: .value("Media", ultimo.media))
                    .symbolSize(40)
                    .foregroundStyle(Color.marcaVivo)
            }
        }
        .chartYScale(domain: minimo...maximo)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(Locale(identifier: "es_AR")))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.secondary.opacity(0.4))
                AxisValueLabel {
                    if let kg = v.as(Double.self) { Text(kg.kg).font(.caption2).foregroundStyle(Color.secondary) }
                }
            }
        }
        .accessibilityLabel("Peso de los últimos \(s.count) días, con la media de 7 días")
    }

    // MARK: Carga de hoy

    private func cargaDeHoy(hoyYa: Bool) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            HStack(spacing: Espacio.xs) {
                HStack(spacing: 4) {
                    TextField("kg de hoy", text: $entrada)
                        .keyboardType(.decimalPad)
                        .focused($escribiendo)
                        .font(.body.weight(.semibold).monospacedDigit())
                    Text("kg").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.campo, in: .capsule)
                Button(hoyYa ? "Corregir" : "Guardar") {
                    escribiendo = false
                    entrada = ""
                    guardados += 1
                }
                .buttonStyle(BotonMarca(compacto: true))
                .disabled(Double(entrada.replacingOccurrences(of: ",", with: ".")).map { $0 < 30 || $0 > 300 } ?? true)
                .sensoryFeedback(.success, trigger: guardados)
            }
            Text("En ayunas al despertar, siempre en la misma condición.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func textoDelta(_ g: Int) -> String {
        let signo = g > 0 ? "+" : (g < 0 ? "−" : "")
        let abs = Swift.abs(g)
        return abs >= 1000 ? "\(signo)\((Double(abs) / 1000).kg) kg" : "\(signo)\(abs) g"
    }
}
