import SwiftUI
import WidgetKit
import MyPumpReloj

/// Las complicaciones del reloj (tanda 3, 2.2): el próximo entreno y el descanso en curso. Leen el estado que deja la app
/// del reloj en el contenedor del App Group (`EstadoComplicacion`); la app recarga las líneas de tiempo cuando cambia.
@main
struct Complicaciones: WidgetBundle {
    var body: some Widget {
        ProximoEntrenoWidget()
        DescansoWidget()
    }
}

private let verde = Color(red: 0x5B / 255, green: 0xBE / 255, blue: 0x62 / 255)
private let grupo = "group.com.pumpteam.mypump.reloj"

struct Entrada: TimelineEntry {
    let date: Date
    let estado: EstadoComplicacion?
    /// El descanso corre en esta entrada.
    var finDescanso: Date? {
        guard let f = estado?.finDescanso else { return nil }
        let fin = Date(timeIntervalSince1970: f / 1000)
        return fin > date ? fin : nil
    }
}

struct Proveedor: TimelineProvider {
    static var estado: EstadoComplicacion? {
        guard let c = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: grupo) else { return nil }
        return EstadoComplicacion.leer(c.appendingPathComponent(EstadoComplicacion.archivo))
    }

    static let muestra = EstadoComplicacion(titulo: "Empuje", detalle: "2 de 5 ejercicios", hechos: 2, total: 5,
                                            finDescanso: (Date().timeIntervalSince1970 + 75) * 1000, objetivoDescanso: 90)

    func placeholder(in context: Context) -> Entrada { Entrada(date: .now, estado: Self.muestra) }

    func getSnapshot(in context: Context, completion: @escaping (Entrada) -> Void) {
        completion(Entrada(date: .now, estado: context.isPreview ? Self.muestra : Self.estado))
    }

    /// Una entrada ahora y, si corre un descanso, otra en su fin (para que se apague sola).
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entrada>) -> Void) {
        let e = Self.estado
        var entradas = [Entrada(date: .now, estado: e)]
        if let f = e?.finDescanso {
            let fin = Date(timeIntervalSince1970: f / 1000)
            if fin > .now { entradas.append(Entrada(date: fin, estado: e)) }
        }
        completion(Timeline(entries: entradas, policy: .never))
    }
}

// MARK: - Próximo entreno

struct ProximoEntrenoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "proximo-entreno", provider: Proveedor()) { e in
            ProximoVista(entrada: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Próximo entreno")
        .description("La rutina de hoy o la próxima.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct ProximoVista: View {
    let entrada: Entrada
    @Environment(\.widgetFamily) private var familia

    var body: some View {
        let e = entrada.estado
        let titulo = e?.titulo ?? "Pump Team"
        let detalle = e?.detalle ?? "Abrí la app"
        let avance = (e?.total ?? 0) > 0 ? Double(e?.hechos ?? 0) / Double(e!.total) : 0
        switch familia {
        case .accessoryCircular:
            Gauge(value: avance) {
                Image(systemName: "dumbbell.fill")
            } currentValueLabel: {
                Text("\(e?.hechos ?? 0)/\(e?.total ?? 0)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(verde)
        case .accessoryInline:
            Label("\(titulo) · \(detalle)", systemImage: "dumbbell.fill")
        case .accessoryCorner:
            Image(systemName: "dumbbell.fill")
                .font(.title3)
                .widgetLabel { Text(titulo) }
        default:
            VStack(alignment: .leading, spacing: 1) {
                Label("Pump Team", systemImage: "dumbbell.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(verde)
                Text(titulo).font(.headline).lineLimit(1)
                Text(detalle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Descanso en curso

struct DescansoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "descanso", provider: Proveedor()) { e in
            DescansoVista(entrada: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Descanso")
        .description("La cuenta regresiva del descanso entre series.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct DescansoVista: View {
    let entrada: Entrada
    @Environment(\.widgetFamily) private var familia

    var body: some View {
        if let fin = entrada.finDescanso {
            let inicio = fin.addingTimeInterval(-(entrada.estado?.objetivoDescanso ?? 90))
            switch familia {
            case .accessoryCircular:
                ProgressView(timerInterval: inicio...fin, countsDown: true) {
                    Image(systemName: "timer")
                } currentValueLabel: {
                    Text(timerInterval: inicio...fin, countsDown: true).monospacedDigit()
                }
                .progressViewStyle(.circular)
                .tint(verde)
            case .accessoryInline:
                Text("Descanso \(Text(timerInterval: inicio...fin, countsDown: true))")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Descanso", systemImage: "timer").font(.caption2.weight(.semibold)).foregroundStyle(verde)
                    Text(timerInterval: inicio...fin, countsDown: true)
                        .font(.title2.weight(.bold).monospacedDigit())
                    ProgressView(timerInterval: inicio...fin, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .tint(verde)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch familia {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "timer").font(.title3)
                }
            case .accessoryInline:
                Label("Sin descanso", systemImage: "timer")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Label("Descanso", systemImage: "timer").font(.caption2.weight(.semibold)).foregroundStyle(verde)
                    Text("Sin descanso").font(.headline)
                    Text(entrada.estado?.titulo ?? "Pump Team").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
