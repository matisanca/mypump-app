import SwiftUI
import Charts
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Peso corporal (REV-07): la media de 7 días es lo que importa, así que va grande; el gráfico muestra los pesos del
/// día tenues y la media como línea con degradado. Abajo, la carga del día (30-300 kg, por la cola) y la tendencia
/// contra la semana pasada. Las cuentas son las de la web (`PesoCorporal`).
struct PesoTarjeta: View {
    /// El modelo real, o nil con las muestras (no se guarda nada).
    let revision: ModeloRevision?
    let saludMuestra: [FilaSalud]
    @State private var entrada = ""
    @State private var guardados = 0
    @State private var errores = 0
    @State private var invalido = false
    @State private var precargado = false
    @FocusState private var escribiendo: Bool
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    struct Punto: Identifiable {
        let fecha: Date
        let kg: Double
        let media: Double
        var id: Date { fecha }
    }

    private var serie: [PesoCorporal.Punto] { revision?.serieDePeso ?? PesoCorporal.serie(saludMuestra) }

    var body: some View {
        let s = serie
        let hoy = FechaLocal.hoy()
        let media7 = PesoCorporal.media(s, hasta: hoy, dias: 7)
        let deltaG = PesoCorporal.deltaSemanal(s, hoy: hoy)
        let pesoDeHoy = s.last { $0.fecha == hoy }
        let puntos = zip(s, PesoCorporal.lineaMedia(s)).compactMap { p, m -> Punto? in
            Fechas.dia(p.fecha).map { Punto(fecha: $0, kg: p.kg, media: m.kg) }
        }

        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Peso corporal")
            VStack(alignment: .leading, spacing: Espacio.m) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Media de 7 días").textoCeja()
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(media7.map(PesoCorporal.kg) ?? "—").font(.numeroGrande).contentTransition(.numericText())
                        Text("kg").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let deltaG {
                        // El color es neutro: subir o bajar no es bueno ni malo sin el objetivo, y el rango objetivo
                        // no se le muestra al cliente (lo interpreta Mati).
                        Label {
                            Text("Esta semana: \(Text(PesoCorporal.textoDelta(deltaG)).bold().foregroundStyle(.primary)) vs la semana pasada")
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

                if puntos.count >= 2 {
                    grafico(puntos).frame(height: 168)
                }

                Divider()

                cargaDeHoy(hoyYa: pesoDeHoy != nil)
            }
            .tarjeta()
        }
        // Si ya cargó el de hoy, el campo lo muestra para corregirlo (como la web).
        .onChange(of: pesoDeHoy?.kg, initial: true) { _, kg in
            guard !precargado, let kg else { return }
            precargado = true
            entrada = PesoCorporal.kg(kg)
        }
        // Día nuevo: el peso de ayer no es el de hoy. Antes quedaba en el campo y un toque lo guardaba como el de hoy
        // (revisión del 14-oct, hallazgo 6). Si hoy ya hay uno, el onChange de arriba lo vuelve a poner.
        .onChange(of: revision?.fecha) { _, _ in
            entrada = ""
            precargado = false
            invalido = false
            if let kg = pesoDeHoy?.kg { precargado = true; entrada = PesoCorporal.kg(kg) }
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
            // Con letra de accesibilidad, una fecha cada dos semanas: cada semana se encimaban ("23 se30tsep7t").
            AxisMarks(values: .stride(by: .day, count: tamañoLetra.isAccessibilitySize ? 14 : 7)) { _ in
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
        // Con letra de accesibilidad, el botón abajo del campo: al lado, el peso quedaba en "8… kg".
        let disposicion = tamañoLetra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs))
                                                          : AnyLayout(HStackLayout(spacing: Espacio.xs))
        return VStack(alignment: .leading, spacing: Espacio.xs) {
            disposicion {
                HStack(spacing: 4) {
                    TextField("kg de hoy", text: $entrada)
                        .keyboardType(.decimalPad)
                        .focused($escribiendo)
                        .font(.body.weight(.semibold).monospacedDigit())
                        .onChange(of: entrada) { _, _ in invalido = false }
                        .accessibilityIdentifier("peso-hoy")
                    Text("kg").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.campo, in: .capsule)
                .overlay { Capsule().strokeBorder(Color.peligro, lineWidth: invalido ? 1.5 : 0) }
                .modifier(Sacudida(veces: CGFloat(errores)))
                Button(hoyYa ? "Corregir" : "Guardar", action: guardar)
                    .buttonStyle(BotonMarca(compacto: true))
                    .disabled(entrada.trimmingCharacters(in: .whitespaces).isEmpty)
                    .sensoryFeedback(.success, trigger: guardados)
                    .sensoryFeedback(.error, trigger: errores)
                    .accessibilityIdentifier("guardar-peso")
            }
            Text(invalido ? "Tiene que estar entre 30 y 300 kg." : "En ayunas al despertar, siempre en la misma condición.")
                .font(.caption)
                .foregroundStyle(invalido ? Color.peligro : Color.secondary)
        }
        .animation(.snappy, value: invalido)
    }

    private func guardar() {
        let texto = entrada
        guard let revision else {
            // Muestras: se valida igual, pero no se guarda nada.
            if PesoCorporal.leer(texto) == nil { rechazar() } else { escribiendo = false; guardados += 1 }
            return
        }
        Task {
            if await revision.guardarPeso(texto) {
                escribiendo = false
                if let v = PesoCorporal.leer(texto) { entrada = PesoCorporal.kg(v) }
                guardados += 1
            } else {
                rechazar()
            }
        }
    }

    private func rechazar() {
        invalido = true
        withAnimation(.linear(duration: 0.35)) { errores += 1 }
    }
}

/// Un "no" con la cabeza: el campo se sacude cuando el valor no sirve.
private struct Sacudida: GeometryEffect {
    var veces: CGFloat
    var animatableData: CGFloat {
        get { veces }
        set { veces = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(veces * .pi * 4), y: 0))
    }
}
