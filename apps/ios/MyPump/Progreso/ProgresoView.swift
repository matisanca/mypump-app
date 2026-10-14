import SwiftUI
import Charts
import MyPumpModelos
import MyPumpReglas

/// Progreso: una tarjeta por EJERCICIO (por clave, no por lugar en la rutina), con el máximo por sesión.
struct ProgresoView: View {
    let datos: Muestras

    private struct Punto: Identifiable { let id: String; let fecha: Date; let kg: Double }
    private struct Linea: Identifiable { let id: String; let nombre: String; let puntos: [Punto] }

    private var lineas: [Linea] {
        var vistas = Set<String>()
        let ejercicios = (datos.rutina?.estructura.dias ?? []).flatMap { $0.bloques.flatMap(\.ejercicios) }
        return ejercicios.compactMap { e in
            let clave = ClaveEjercicio.de(e.nombre)
            guard !vistas.contains(clave), let filas = datos.historialPorClave[clave], !filas.isEmpty else { return nil }
            vistas.insert(clave)
            let porDia = Dictionary(grouping: filas) { String($0.registradoEn.prefix(10)) }
            let puntos = porDia.compactMap { dia, fs -> Punto? in
                guard let f = Fechas.dia(dia), let max = fs.compactMap(\.pesoKg).max(), max > 0 else { return nil }
                return Punto(id: dia, fecha: f, kg: max)
            }.sorted { $0.fecha < $1.fecha }.suffix(8)
            return puntos.isEmpty ? nil : Linea(id: clave, nombre: e.nombre, puntos: Array(puntos))
        }
    }

    var body: some View {
        NavigationStack {
            let ls = lineas
            List {
                Section {
                    HStack(spacing: 12) {
                        Dato(titulo: "Ejercicios", valor: "\(ls.count)", icono: "dumbbell")
                        Dato(titulo: "Sesiones", valor: "\(Set(datos.historial.map { String($0.registradoEn.prefix(10)) }).count)", icono: "calendar")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                Section("Tus ejercicios") {
                    ForEach(ls) { l in fila(l) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Progreso")
        }
    }

    private func fila(_ l: Linea) -> some View {
        let primero = l.puntos.first?.kg ?? 0, ultimo = l.puntos.last?.kg ?? 0
        let pr = l.puntos.count > 1 && ultimo > (l.puntos.dropLast().map(\.kg).max() ?? 0)
        let delta = primero > 0 ? (ultimo - primero) / primero * 100 : 0
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(l.nombre).font(.subheadline.weight(.semibold)).lineLimit(2)
                    if pr { Text("PR").font(.caption2.weight(.heavy)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.marca, in: .capsule).foregroundStyle(Color.sobreMarca) }
                }
                Text("\(ultimo.kg) kg · \(delta >= 0 ? "+" : "")\(Int(delta.rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(delta >= 0 ? Color.exito : Color.peligro)
            }
            Spacer()
            Chart(l.puntos) { p in
                LineMark(x: .value("Fecha", p.fecha), y: .value("Kg", p.kg)).interpolationMethod(.monotone).foregroundStyle(Color.marcaTexto)
                AreaMark(x: .value("Fecha", p.fecha), y: .value("Kg", p.kg)).foregroundStyle(Color.marcaSuave.gradient)
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(width: 96, height: 40)
        }
        .padding(.vertical, 4)
    }
}
