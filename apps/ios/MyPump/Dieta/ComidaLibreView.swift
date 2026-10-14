import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Registrar una comida fuera del plan (`openComidaLibreModal`): vacía, o con la estimación de la foto del plato.
/// Todo es editable; corregir los gramos de un alimento re-escala sus macros y recalcula los totales.
struct ComidaLibreView: View {
    let modelo: ModeloApp
    let estimacion: EstimacionPlato?

    @Environment(\.dismiss) private var cerrar
    @State private var descripcion: String
    @State private var hora = Date()
    @State private var kcal: String
    @State private var prot: String
    @State private var carb: String
    @State private var fat: String
    @State private var gramos: [String]
    @State private var error: String?
    @State private var guardando = false
    private let bases: [ComidaLibreNueva.Base]

    init(modelo: ModeloApp, estimacion: EstimacionPlato?) {
        self.modelo = modelo
        self.estimacion = estimacion
        let b = ComidaLibreNueva.bases(estimacion)
        bases = b
        _descripcion = State(initialValue: estimacion?.descripcion ?? "")
        _kcal = State(initialValue: estimacion?.kcal.map { String($0.jsEntero) } ?? "")
        _prot = State(initialValue: estimacion?.prot.map(\.kg) ?? "")
        _carb = State(initialValue: estimacion?.carb.map(\.kg) ?? "")
        _fat = State(initialValue: estimacion?.fat.map(\.kg) ?? "")
        _gramos = State(initialValue: b.map { String($0.gramosIniciales.enteroSeguro) })
    }

    var body: some View {
        NavigationStack {
            Form {
                if let estimacion {
                    Section {
                        Label {
                            Text("La IA estimó esto de tu foto. Es un estimativo: corregí lo que haga falta.")
                        } icon: {
                            Image(systemName: "sparkles").foregroundStyle(Color.marcaTexto)
                        }
                        .font(.subheadline)
                        if estimacion.confianza == "baja" {
                            Label("La foto se leyó con poca claridad.", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(Color.alerta)
                        }
                    }
                }
                if !bases.isEmpty {
                    Section {
                        ForEach(Array(bases.enumerated()), id: \.offset) { i, b in
                            HStack {
                                Text(b.nombre)
                                Spacer(minLength: 12)
                                TextField("0", text: $gramos[i])
                                    .accessibilityLabel("Gramos de \(b.nombre)")
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                                    .frame(maxWidth: 80)
                                Text("g").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Lo que vio en el plato")
                    } footer: {
                        if let escala = estimacion?.escala, !escala.isEmpty { Text("📐 \(escala)") }
                    }
                }
                Section("Qué comiste") {
                    TextField("Ej: Milanesa con puré", text: $descripcion)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
                }
                Section {
                    campo("Calorías", texto: $kcal, unidad: "kcal").accessibilityIdentifier("kcal-comida-libre")
                    campo("Proteínas", texto: $prot, unidad: "g")
                    campo("Carbohidratos", texto: $carb, unidad: "g")
                    campo("Grasas", texto: $fat, unidad: "g")
                } header: {
                    Text("Valores")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill").foregroundStyle(Color.peligro).font(.subheadline)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(estimacion == nil ? "Comida libre" : "Revisá la estimación")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando { ProgressView() } else {
                        Button("Registrar") { Task { await guardar() } }.fontWeight(.semibold)
                    }
                }
            }
            .onChange(of: gramos) { _, nuevos in recalcular(nuevos) }
            .sensoryFeedback(.error, trigger: error) { _, nuevo in nuevo != nil }
        }
    }

    private func campo(_ titulo: String, texto: Binding<String>, unidad: String) -> some View {
        HStack {
            Text(titulo)
            Spacer(minLength: 12)
            TextField("0", text: texto)
                .accessibilityLabel("\(titulo) en \(unidad)")
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 110)
            Text(unidad).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .leading)
        }
    }

    private var gramosVigentes: [Double] {
        ComidaLibreNueva.gramos(bases, escritos: gramos.map(AlimentoPropioNuevo.leerNumero))
    }

    private func recalcular(_ nuevos: [String]) {
        let t = ComidaLibreNueva.totales(bases, gramos: ComidaLibreNueva.gramos(bases, escritos: nuevos.map(AlimentoPropioNuevo.leerNumero)))
        kcal = String(t.kcal.enteroSeguro); prot = t.prot.kg; carb = t.carb.kg; fat = t.fat.kg
    }

    private func guardar() async {
        let leer = AlimentoPropioNuevo.leerNumero
        let detalle = ComidaLibreNueva.detalle(bases, gramos: gramosVigentes, confianza: estimacion?.confianza, escala: estimacion?.escala)
        switch ComidaLibreNueva.preparar(descripcion: descripcion, hora: ComidaLibreNueva.hora(hora), kcal: leer(kcal), prot: leer(prot),
                                         carb: leer(carb), fat: leer(fat), detalle: detalle) {
        case .failure(let e):
            error = e.mensaje
        case .success(let datos):
            error = nil
            guardando = true
            defer { guardando = false }
            switch await modelo.crearComidaLibre(datos) {
            case .success: cerrar()
            case .failure(let e):
                error = e.clase == .red ? "Sin conexión: probá de nuevo cuando tengas señal." : "No se pudo guardar. Probá de nuevo."
            }
        }
    }
}
