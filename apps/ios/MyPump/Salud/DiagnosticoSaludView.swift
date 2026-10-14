import SwiftUI
import MyPumpDatos
import MyPumpModelos

/// El diagnóstico de Apple Health (SAL-13, cliente.html:8605-8665): qué trajo cada tipo en 14 días y por qué camino, el
/// error textual del que falló, el estado ("tipos ya preguntados" NO es "permisos dados"), el último intento de
/// conectar, el último rechazo de la base y el sueño por noche y por fuente. Es una herramienta nuestra: se abre con 5
/// toques en el título "Salud de Apple" de Mis datos (o desde un modo de depuración).
struct DiagnosticoSaludView: View {
    let modelo: ModeloSalud
    @Environment(\.dismiss) private var cerrar
    @State private var diag: DiagnosticoSalud?
    @State private var estado: EstadoSalud?

    var body: some View {
        List {
            if let estado {
                Section("Estado") {
                    renglon("HealthKit", estado.disponible ? "sí" : "no")
                    renglon("Conectado", estado.conectado ? "sí" : "no")
                    renglon("No llega nada", estado.sinDatos ? "sí" : "no")
                    renglon("Tipos ya preguntados", estado.preguntados.map { "\($0)/\(estado.total)" } ?? "?")
                    renglon("Última sync", estado.ultimaSync ?? "nunca")
                    renglon("iOS", "\(estado.ios)")
                    if let e = estado.errorEstado { Text("checkAuthorization: \(e)").foregroundStyle(Color.peligro) }
                    Text("\"Tipos ya preguntados\" NO es \"permisos dados\": HealthKit no informa el permiso de lectura. Si dice 19/19 y abajo todo da 0, es que se denegó.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let e = modelo.ultimoErrorIngesta ?? diag?.errorIngesta {
                Section {
                    Text("⚠ El servidor rechazó la última ingesta: \(e)").foregroundStyle(Color.peligro)
                    Text("Los datos se leen bien de HealthKit pero no se están guardando. Es un problema del backend, no del teléfono.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Último intento de conectar") {
                Text(textoIntento).font(.caption.monospaced()).textSelection(.enabled)
            }
            if let diag {
                Section("Tipos (14 días)") {
                    ForEach(diag.tipos, id: \.dataType) { t in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(t.tipo).font(.caption.monospaced())
                                Text(t.via).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(t.n)").font(.caption.monospaced().weight(.bold)).foregroundStyle(t.n > 0 ? Color.exito : Color.peligro)
                            }
                            if let p = t.primero { Text(p + (t.ultimo.map { $0 != p ? " → \($0)" : "" } ?? "")).font(.caption2).foregroundStyle(.secondary) }
                            if let e = t.error { Text(String(e.prefix(90))).font(.caption2).foregroundStyle(Color.peligro) }
                        }
                    }
                }
                Section {
                    if diag.noches.isEmpty { Text("sin datos de sueño").italic() }
                    ForEach(diag.noches.suffix(10), id: \.fecha) { n in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.fecha).font(.caption.weight(.bold))
                            ForEach(n.fuentes.keys.sorted(), id: \.self) { f in
                                let estados = (n.fuentes[f] ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)m" }.joined(separator: ", ")
                                Text("  \(f): \(estados)").font(.caption2.monospaced())
                            }
                        }
                    }
                } header: {
                    Text("Sueño por noche y por fuente")
                } footer: {
                    Text("Si una noche aparece con 2 fuentes, se queda solo con la que más minutos de sueño real aportó (si no, se duplicarían las horas).")
                }
                if !diag.errores.isEmpty {
                    Section("Errores") { ForEach(diag.errores, id: \.self) { Text($0).font(.caption2.monospaced()) } }
                }
            } else {
                Section { ProgressView("Consultando…") }
            }
        }
        .navigationTitle("Diagnóstico Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Volver") { cerrar() } } }
        .task {
            estado = await modelo.estado()
            diag = await modelo.diagnostico()
        }
    }

    private var textoIntento: String {
        guard let j = modelo.ultimoIntento, let d = try? JSONEncoder().encode(j) else { return "(todavía no se intentó conectar)" }
        return String(decoding: d, as: UTF8.self)
    }

    private func renglon(_ k: String, _ v: String) -> some View {
        LabeledContent(k) { Text(v).monospacedDigit() }.font(.subheadline)
    }
}
