import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Un candidato para reemplazar un alimento, como lo muestra la hoja. `json` es exactamente lo que se guarda en
/// `food_data` (el objeto que arma `findSubstitutes` de la web).
struct OpcionSustituto: Identifiable, Equatable {
    let nombre: String
    let qty: Double
    let unidad: String
    let kcal: Double
    let prot: Double
    let carb: Double
    let fat: Double
    let desvio: Double
    let universal: Bool
    let ingles: String?
    let propio: Bool
    let json: JSONValue
    var id: String { nombre.lowercased() }
}

/// "Sustituir alimento" (openSwapModal de la web): búsqueda libre, los universales arriba, los propios con ★, la
/// diferencia de kcal contra el original (verde hasta 5 %), los avisos del motor y crear un alimento propio.
struct SustituirAlimentoView: View {
    let modelo: ModeloApp
    let original: Alimento
    let alElegir: (JSONValue) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var busqueda = ""
    @State private var elegido: OpcionSustituto?
    @State private var resultado = MotorSustitutos.Resultado(opciones: [], avisos: [], categoria: "")

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(original.nombre).font(.headline)
                        Text("\(cantidad(original.qty, original.unidad)) · \(Int(original.kcal ?? 0)) kcal · P \(g(original.prot)) · C \(g(original.carb)) · G \(g(original.fat))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Reemplazás")
                } footer: {
                    Text("¿No conseguís este alimento? Elegí una opción 🌍 disponible en cualquier país.")
                }

                ForEach(resultado.avisos, id: \.self) { aviso in
                    Label(aviso, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.alerta)
                }

                let lista = filtradas
                if lista.isEmpty {
                    ContentUnavailableView(busqueda.isEmpty ? "Sin equivalentes" : "Sin resultados para “\(busqueda)”",
                                           systemImage: "magnifyingglass",
                                           description: Text(busqueda.isEmpty
                                                             ? "No hay sustitutos equivalentes dentro del rango de macros."
                                                             : "Probá con otro nombre o creá tu alimento personalizado."))
                        .listRowBackground(Color.clear)
                } else {
                    let universales = lista.filter(\.universal)
                    let resto = lista.filter { !$0.universal }
                    if !universales.isEmpty {
                        Section("🌍 Disponibles en cualquier país") { ForEach(universales) { fila($0) } }
                    }
                    if !resto.isEmpty {
                        Section(universales.isEmpty ? "Equivalentes" : "Otras opciones") { ForEach(resto) { fila($0) } }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar alimento")
            .navigationTitle("Reemplazar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Reemplazar").font(.headline)
                        Text("\(filtradas.count) de \(resultado.opciones.count) · \(resultado.categoria)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let e = elegido else { return }
                    alElegir(e.json)
                    cerrar()
                } label: {
                    Text(elegido.map { "Reemplazar por \($0.nombre)" } ?? "Elegí un alimento").lineLimit(1)
                }
                .buttonStyle(BotonMarca())
                .disabled(elegido == nil)
                .opacity(elegido == nil ? 0.5 : 1)
                .padding(.horizontal).padding(.vertical, 10)
                .background(.bar)
                .sensoryFeedback(.success, trigger: elegido) { _, n in n != nil }
            }
        }
        .task { resultado = MotorSustitutos.buscar(original: original, modelo: modelo) }
        .presentationDragIndicator(.visible)
    }

    private var filtradas: [OpcionSustituto] {
        let q = busqueda.lowercased().trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? resultado.opciones : resultado.opciones.filter { $0.nombre.lowercased().contains(q) }
    }

    private func fila(_ o: OpcionSustituto) -> some View {
        let delta = (original.kcal ?? 0) > 0 ? Int(jsRound((o.kcal - (original.kcal ?? 0)) / (original.kcal ?? 1) * 100)) : 0
        let marcado = elegido == o
        return Button {
            withAnimation(.snappy) { elegido = marcado ? nil : o }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: marcado ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(marcado ? Color.marcaTexto : Color.secondary.opacity(0.5))
                    .symbolEffect(.bounce, value: marcado)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(o.nombre).font(.body).foregroundStyle(.primary)
                        if o.propio {
                            Text("★ Tuyo").font(.caption2.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.marcaSuave, in: .capsule)
                        }
                    }
                    if let en = o.ingles, !en.isEmpty { Text(en).font(.caption).foregroundStyle(.secondary) }
                    Text("\(cantidad(o.qty, o.unidad)) · \(Int(o.kcal)) kcal · P \(g(o.prot)) · C \(g(o.carb)) · G \(g(o.fat))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 6)
                Text("\(delta > 0 ? "+" : "")\(delta) %")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(abs(delta) <= 5 ? Color.exito : Color.alerta)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((abs(delta) <= 5 ? Color.exito : Color.alerta).opacity(0.14), in: .capsule)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(marcado ? Color.marcaSuave : Color.tarjeta)
    }

    private func cantidad(_ q: Double?, _ u: String?) -> String {
        guard let q else { return u ?? "" }
        return "\(q.kg) \(u ?? "g")"
    }

    private func g(_ v: Double?) -> String { (v ?? 0).kg }
}

/// Puente entre la hoja y el motor de sustitución (port de `findSubstitutes`, en MyPumpReglas).
@MainActor
enum MotorSustitutos {
    struct Resultado {
        var opciones: [OpcionSustituto]
        var avisos: [String]
        var categoria: String
    }

    static func buscar(original: Alimento, modelo: ModeloApp) -> Resultado {
        // Se completa al integrar el motor portado (MyPumpReglas/SustitucionAlimentos).
        Resultado(opciones: [], avisos: [], categoria: original.categoria ?? "")
    }
}

/// La categoría de un alimento del plan: la que trae, o la inferida (se completa con el port de `_inferCategory`).
enum CategoriaComida {
    static func inferir(_ a: Alimento) -> String { a.categoria ?? "" }
}
