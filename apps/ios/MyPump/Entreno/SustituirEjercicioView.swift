import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Sustituir un ejercicio (SER-11/13): variantes del mismo gesto y músculo (otro equipo primero, hasta 30), debajo los
/// otros ejercicios del mismo músculo (Mati, 20-oct: con la polea ocupada no quedaba nada), búsqueda, y "Fijar para las
/// próximas semanas" (sin fijar vale solo por hoy). Si ya estaba sustituido, "Volver a …".
struct SustituirEjercicioView: View {
    let motor: ModeloEntreno
    let lugar: String
    @Environment(\.dismiss) private var cerrar
    @State private var busqueda = ""
    /// El elegido, no su posición: si con la hoja abierta llega el catálogo del servidor la lista cambia de orden, y la
    /// misma posición era otro ejercicio (revisión del 15-oct, hallazgo 13).
    @State private var elegido: SustitutoEjercicio?
    @State private var fijar = false
    @State private var listo = false

    private var plan: Ejercicio? { motor.dia.ejercicio(lugar) }
    private var todos: [SustitutoEjercicio] { motor.sustitutos(lugar) }

    var body: some View {
        let ef = plan.map(motor.efectivo)
        let original = ef?.nombreOriginal ?? plan?.nombre ?? ""
        let opciones = motor.sustitutos(lugar, busqueda: busqueda)
        let todosOtros = motor.otrosDelMismoMusculo(lugar)
        let otros = SustitucionesEntreno.filtrar(todosOtros, busqueda)
        let totalOtros = todosOtros.count
        let musculo = SustitucionEjercicios.musculo(todosOtros.first?.musculo)
        let total = todos
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(NombreEjercicio(original).principal).font(.headline)
                        Text(todosOtros.isEmpty ? "Mismo gesto · otra variante" : "Otra variante u otro ejercicio \(musculo.map { "de \($0)" } ?? "del mismo músculo")")
                            .font(.subheadline).foregroundStyle(.secondary)
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
                    ForEach(Array(opciones.enumerated()), id: \.offset) { _, s in boton(s, identificador: "variante") }
                } header: {
                    HStack {
                        Text("Variantes del mismo movimiento")
                        Spacer()
                        Text("\(opciones.count)/\(total.count)").monospacedDigit()
                    }
                }

                if !otros.isEmpty {
                    Section {
                        ForEach(Array(otros.enumerated()), id: \.offset) { _, s in boton(s, identificador: "otro-ejercicio") }
                    } header: {
                        HStack {
                            Text(musculo.map { "Otros ejercicios de \($0)" } ?? "Otros ejercicios del mismo músculo")
                            Spacer()
                            Text("\(otros.count)/\(totalOtros)").monospacedDigit()
                        }
                    } footer: {
                        Text("Otro movimiento para el mismo músculo, por si lo del plan está ocupado.")
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
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar ejercicio")
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

    private func boton(_ s: SustitutoEjercicio, identificador: String) -> some View {
        let marcada = elegido?.clave == s.clave
        return Button {
            withAnimation(.snappy(duration: 0.2)) { elegido = s }
        } label: {
            fila(s, elegida: marcada)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcada ? .isSelected : [])
        .accessibilityIdentifier(identificador)
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

    /// La hoja se cierra ya: el cambio se aplica en el acto y el historial del sustituto llega después. Esperarlo la
    /// dejaba abierta hasta 20 s con mala señal, sin indicador, y "Cancelar" ahí no deshacía nada (revisión, hallazgo 14).
    private func sustituir() {
        guard let e = elegido else { return }
        // El mismo, con lo que tenga el catálogo de ahora; si ya no está entre los sustitutos, el que se tocó.
        let s = motor.sustituto(lugar, clave: e.clave) ?? e
        cerrar()
        Task { await motor.sustituir(lugar, por: s, fijar: fijar) }
    }
}
