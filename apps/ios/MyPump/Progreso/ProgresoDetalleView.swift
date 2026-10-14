import SwiftUI
import Charts

/// Detalle de un ejercicio en Progreso (PRO-04): el máximo por sesión en un gráfico con la marca del récord y,
/// abajo, la tabla de las últimas 8 sesiones (fecha, peso, reps, RIR). Tocar o arrastrar el gráfico muestra el valor.
struct ProgresoDetalleView: View {
    let linea: LineaProgreso
    @State private var elegida: Date?

    private var nombre: NombreEjercicio { NombreEjercicio(linea.nombre) }
    private let es = Locale(identifier: "es_AR")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                encabezado
                if linea.sesiones.isEmpty {
                    ContentUnavailableView("Sin cargas para graficar", systemImage: "chart.line.uptrend.xyaxis",
                                           description: Text("Este ejercicio se hace con el peso del cuerpo."))
                } else {
                    grafico
                    tabla
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(nombre.principal)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            if let d = nombre.detalle { Text(d).textoCeja() }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(linea.ultimo.kg).font(.numeroGigante)
                Text("kg").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if linea.esPR { InsigniaPR() }
            }
            HStack(spacing: Espacio.xs) {
                PildoraVariacion(delta: linea.delta)
                Text("en las últimas \(linea.sesiones.count) sesiones").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var grafico: some View {
        let s = linea.sesiones
        let minimo = (s.map(\.kg).min() ?? 0), maximo = (s.map(\.kg).max() ?? 1)
        let margen = max((maximo - minimo) * 0.3, 1)
        let seleccion = elegida.flatMap { e in s.min { abs($0.fecha.timeIntervalSince(e)) < abs($1.fecha.timeIntervalSince(e)) } }
        return VStack(alignment: .leading, spacing: Espacio.s) {
            Text("Máximo por sesión").font(.headline)
            Chart {
                ForEach(s) { p in
                    AreaMark(x: .value("Fecha", p.fecha), yStart: .value("Base", minimo - margen), yEnd: .value("Kg", p.kg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Color.marcaVivo.opacity(0.3), Color.marcaVivo.opacity(0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Fecha", p.fecha), y: .value("Kg", p.kg))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color.marcaVivo)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Fecha", p.fecha), y: .value("Kg", p.kg))
                        .symbolSize(p.kg == linea.record ? 70 : 30)
                        .foregroundStyle(p.kg == linea.record ? Color.record : Color.marcaVivo)
                }
                RuleMark(y: .value("Récord", linea.record))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.record.opacity(0.8))
                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                        Label("Récord \(linea.record.kg) kg", systemImage: "trophy.fill")
                            .labelStyle(EtiquetaCompacta())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.record)
                    }
                if let seleccion {
                    RuleMark(x: .value("Fecha", seleccion.fecha))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 1) {
                                Text("\(seleccion.kg.kg) kg").font(.numeroChico)
                                Text(seleccion.fecha.formatted(.dateTime.day().month(.abbreviated).locale(es)))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .vidrio(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                }
            }
            .chartXSelection(value: $elegida)
            .chartYScale(domain: (minimo - margen)...(maximo + margen))
            .chartXScale(range: .plotDimension(padding: 14))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(es))
                        .font(.caption2)
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4])).foregroundStyle(Color.secondary.opacity(0.4))
                    AxisValueLabel {
                        if let kg = v.as(Double.self) { Text(kg.kg).font(.caption2).foregroundStyle(Color.secondary) }
                    }
                }
            }
            .frame(height: 230)
            .sensoryFeedback(.selection, trigger: seleccion?.fecha)
        }
        .tarjeta()
    }

    private var tabla: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text("Últimas sesiones").font(.title3.weight(.bold)).padding(.horizontal, 4)
            VStack(spacing: 0) {
                fila(["Fecha", "Peso", "Reps", "RIR"], encabezado: true)
                ForEach(Array(linea.sesiones.reversed().enumerated()), id: \.element.id) { i, s in
                    fila([s.fecha.formatted(.dateTime.day().month(.abbreviated).locale(es)),
                          "\(s.kg.kg) kg", s.reps.map(String.init) ?? "—", s.rir.map(String.init) ?? "—"],
                         encabezado: false, destacada: s.kg == linea.record)
                        .background(i % 2 == 0 ? Color.clear : Color.campo.opacity(0.5))
                }
            }
            .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .superficieTarjeta()
        }
    }

    private func fila(_ celdas: [String], encabezado: Bool, destacada: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(celdas.enumerated()), id: \.offset) { i, c in
                HStack(spacing: 4) {
                    if i == 1, destacada { Image(systemName: "trophy.fill").font(.caption2).foregroundStyle(Color.record) }
                    Text(c)
                }
                .frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .font(encabezado ? .caption.weight(.semibold) : .subheadline.monospacedDigit())
        .textCase(encabezado ? .uppercase : nil)
        .foregroundStyle(encabezado ? Color.secondary : Color.primary)
        .padding(.horizontal, Espacio.m)
        .padding(.vertical, encabezado ? 10 : 12)
        .accessibilityElement(children: .combine)
    }
}
