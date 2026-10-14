import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Sustituir un ejercicio (SER-11/13): variantes del mismo gesto y músculo (otro equipo primero, hasta 30), búsqueda,
/// y "Fijar para las próximas semanas" (sin fijar vale solo por hoy). Si ya estaba sustituido, "Volver a …".
struct SustituirEjercicioView: View {
    let motor: ModeloEntreno
    let lugar: String
    @Environment(\.dismiss) private var cerrar
    @State private var busqueda = ""
    @State private var elegido: Int?
    @State private var fijar = false
    @State private var listo = false

    private var plan: Ejercicio? { motor.dia.ejercicio(lugar) }
    private var todos: [SustitutoEjercicio] { motor.sustitutos(lugar) }

    var body: some View {
        let ef = plan.map(motor.efectivo)
        let original = ef?.nombreOriginal ?? plan?.nombre ?? ""
        let opciones = motor.sustitutos(lugar, busqueda: busqueda)
        let total = todos
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NombreEjercicio(original).principal).font(.headline)
                        Text("Mismo gesto · otra variante").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    if ef?.sustituido == true {
                        Button {
                            Task {
                                await motor.revertirSustitucion(lugar)
                                cerrar()
                            }
                        } label: {
                            Label("Volver a \(NombreEjercicio(original).principal)", systemImage: "arrow.uturn.backward")
                        }
                    }
                }

                Section {
                    if opciones.isEmpty {
                        Text(busqueda.isEmpty ? "No hay variantes equivalentes." : "Sin resultados para “\(busqueda)”.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(opciones.enumerated()), id: \.offset) { _, s in
                        let i = total.firstIndex(of: s)
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { elegido = i }
                        } label: {
                            fila(s, elegida: i != nil && i == elegido)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(i == elegido ? .isSelected : [])
                    }
                } header: {
                    HStack {
                        Text("Variantes del mismo movimiento")
                        Spacer()
                        Text("\(opciones.count)/\(total.count)").monospacedDigit()
                    }
                }

                Section {
                    Toggle(isOn: $fijar) {
                        Label("Fijar para las próximas semanas", systemImage: "lock.fill")
                    }
                    .tint(Color.marcaVivo)
                } footer: {
                    Text("Si no lo fijás, vale solo por hoy: la próxima sesión vuelve “\(NombreEjercicio(original).principal)”.")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar variante")
            .navigationTitle("Sustituir ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sustituir") { sustituir() }
                        .fontWeight(.semibold)
                        .disabled(elegido == nil)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            guard !listo else { return }
            listo = true
            fijar = motor.fijadaAntes(lugar)
        }
    }

    private func fila(_ s: SustitutoEjercicio, elegida: Bool) -> some View {
        HStack(spacing: Espacio.s) {
            Miniatura(url: s.imagenes.concentric ?? s.imagenes.eccentric, tipo: nil, lado: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.nombre).font(.body).foregroundStyle(.primary)
                Text(s.equipo).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Espacio.xs)
            Image(systemName: elegida ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(elegida ? Color.marcaVivo : Color(uiColor: .tertiaryLabel))
                .symbolEffect(.bounce, value: elegida)
        }
        .contentShape(.rect)
    }

    private func sustituir() {
        guard let i = elegido, i < todos.count else { return }
        let s = todos[i]
        Task {
            await motor.sustituir(lugar, por: s, fijar: fijar)
            cerrar()
        }
    }
}
