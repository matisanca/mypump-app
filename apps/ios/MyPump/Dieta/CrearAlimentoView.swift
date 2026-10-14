import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// "Crear alimento personalizado" (openCustomFoodModal / saveCustomFood de la web). Los números se piden en la base
/// que corresponde a la unidad (por 100 g con g o ml, de 1 porción con el resto) y se guardan siempre por 100 g.
/// La categoría es la del alimento que se está reemplazando, como en la web.
struct CrearAlimentoView: View {
    let modelo: ModeloApp
    let categoria: String
    let alCrear: (AlimentoPropio) -> Void

    @State private var nombre = ""
    @State private var kcal = ""
    @State private var prot = ""
    @State private var carb = ""
    @State private var fat = ""
    @State private var unidad = "g"
    @State private var gramos = ""
    @State private var error: String?
    @State private var guardando = false
    @FocusState private var foco: Campo?

    enum Campo: Hashable { case nombre, kcal, prot, carb, fat, gramos }

    var body: some View {
        Form {
            Section {
                TextField("Ej: Pan integral marca X", text: $nombre)
                    .focused($foco, equals: .nombre)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit { foco = .kcal }
            } header: {
                Text("Nombre")
            }

            Section {
                Picker("Unidad", selection: $unidad) {
                    ForEach(AlimentoPropioNuevo.unidades, id: \.valor) { Text($0.texto).tag($0.valor) }
                }
                if AlimentoPropioNuevo.porUnidad(unidad) {
                    campo("Gramos por \(AlimentoPropioNuevo.texto(unidad))", texto: $gramos, unidadTexto: "g", campo: .gramos)
                }
            } header: {
                Text("Cómo lo medís")
            } footer: {
                if AlimentoPropioNuevo.porUnidad(unidad) {
                    Text("Cuánto pesa 1 \(AlimentoPropioNuevo.texto(unidad)) en gramos (sirve para la medida casera).")
                }
            }

            Section {
                campo("Calorías", texto: $kcal, unidadTexto: "kcal", campo: .kcal)
                campo("Proteínas", texto: $prot, unidadTexto: "g", campo: .prot)
                campo("Carbohidratos", texto: $carb, unidadTexto: "g", campo: .carb)
                campo("Grasas", texto: $fat, unidadTexto: "g", campo: .fat)
            } header: {
                Text("Valores")
            } footer: {
                Text(AlimentoPropioNuevo.base(unidad: unidad, gramosPorUnidad: AlimentoPropioNuevo.leerNumero(gramos)))
                    + Text(" Si no sabés las calorías, se calculan con los macros.")
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Color.peligro)
                        .font(.subheadline)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Alimento propio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if guardando {
                    ProgressView()
                } else {
                    Button("Crear y usar") { Task { await crear() } }
                        .fontWeight(.semibold)
                        .disabled(nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }
            }
        }
        .sensoryFeedback(.error, trigger: error) { _, nuevo in nuevo != nil }
        .onAppear { foco = .nombre }
        .animation(.snappy, value: unidad)
        .animation(.snappy, value: error)
    }

    private func campo(_ titulo: String, texto: Binding<String>, unidadTexto: String, campo: Campo) -> some View {
        HStack {
            Text(titulo)
            Spacer(minLength: 12)
            TextField("0", text: texto)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($foco, equals: campo)
                .frame(maxWidth: 110)
                .monospacedDigit()
            Text(unidadTexto).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .leading)
        }
    }

    private func crear() async {
        let leer = AlimentoPropioNuevo.leerNumero
        switch AlimentoPropioNuevo.preparar(nombre: nombre, kcal: leer(kcal), prot: leer(prot), carb: leer(carb), fat: leer(fat),
                                            unidad: unidad, gramosPorUnidad: leer(gramos), categoria: categoria) {
        case .failure(let e):
            error = e.mensaje
        case .success(let datos):
            error = nil
            guardando = true
            defer { guardando = false }
            switch await modelo.crearAlimentoPropio(datos) {
            case .success(let creado):
                alCrear(creado)
            case .failure(let e):
                error = e.clase == .red
                    ? "Sin conexión: probá de nuevo cuando tengas señal."
                    : "No se pudo crear el alimento. Probá de nuevo."
            }
        }
    }
}
