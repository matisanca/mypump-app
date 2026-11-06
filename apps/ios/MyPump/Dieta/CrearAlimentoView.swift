import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// "Crear alimento personalizado" (openCustomFoodModal / saveCustomFood de la web). Los números se piden en la base
/// que corresponde a la unidad (por 100 g con g o ml, de 1 porción con el resto) y se guardan siempre por 100 g.
/// La categoría es la del alimento que se está reemplazando, como en la web.
struct CrearAlimentoView: View {
    /// Lo que llega de un código de barras que Open Food Facts no tenía o tenía incompleto (2.1, S3): el código (se
    /// muestra y queda asociado al alimento en el teléfono), lo que se pudo leer y si abre directo la foto de la etiqueta.
    struct Precarga: Equatable {
        var codigo: String
        var parcial: CodigoBarras.Parcial?
        var escanearEtiqueta: Bool
    }

    let modelo: ModeloApp
    let categoria: String
    var precarga: Precarga? = nil
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
    @State private var escaneando = false
    @State private var estadoEscaneo: String?
    @State private var precargado = false
    /// La etiqueta no dijo cuánto pesa la porción: se pregunta si los números son por 100 g o de 1 porción (6-nov).
    @State private var preguntaBase = false
    @FocusState private var foco: Campo?

    enum Campo: Hashable { case nombre, kcal, prot, carb, fat, gramos }

    var body: some View {
        Form {
            if modelo.token != nil {
                Section {
                    BotonFoto(maxPx: 1600, abrirAlAparecer: precarga?.escanearEtiqueta == true, alElegir: escanear) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Escanear etiqueta").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text("Sacale una foto a la tabla nutricional y se completa solo").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "text.viewfinder").font(.title3).foregroundStyle(Color.marcaTexto)
                        }
                    }
                    if let estadoEscaneo {
                        Text(estadoEscaneo).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("crear-estado-escaneo")
                    }
                    if preguntaBase {
                        HStack(spacing: 10) {
                            Button("Por 100 g") { elegirBase(porcion: false) }
                                .accessibilityIdentifier("crear-base-100")
                            Button("De 1 porción") { elegirBase(porcion: true) }
                                .accessibilityIdentifier("crear-base-porcion")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } footer: {
                    Text("Después podés corregir cualquier valor.")
                }
            }
            if let codigo = precarga?.codigo {
                Section {
                    LabeledContent {
                        Text(codigo).monospacedDigit().foregroundStyle(.secondary).textSelection(.enabled)
                    } label: {
                        Label("Código de barras", systemImage: "barcode")
                    }
                    .accessibilityIdentifier("crear-codigo")
                } footer: {
                    Text("Queda guardado en este teléfono: la próxima vez que lo escanees, aparece tu alimento.")
                }
            }
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
                Picker("Unidad", selection: Binding(get: { unidad }, set: { unidad = $0; preguntaBase = false })) {
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(AlimentoPropioNuevo.base(unidad: unidad, gramosPorUnidad: AlimentoPropioNuevo.leerNumero(gramos)))
                        + Text(" Si no sabés las calorías, se calculan con los macros.")
                    if let aviso = avisoPolvo {
                        Label(aviso, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.alerta)
                            .accessibilityIdentifier("crear-aviso-polvo")
                    }
                }
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
        .overlay {
            if escaneando {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    AnalizandoFoto(texto: "Leyendo la etiqueta…")
                }
            }
        }
        .onAppear {
            if let p = precarga?.parcial, !precargado {
                precargado = true
                if let n = p.nombre { nombre = n }
                if let k = p.kcal { kcal = String(k.jsEntero) }
                if let v = p.p { prot = v.kg }
                if let v = p.c { carb = v.kg }
                if let v = p.g { fat = v.kg }
            }
            // Con la foto de la etiqueta abriéndose, el teclado estorba.
            if precarga?.escanearEtiqueta != true { foco = .nombre }
        }
        .animation(.snappy, value: unidad)
        .animation(.snappy, value: error)
    }

    private func campo(_ titulo: String, texto: Binding<String>, unidadTexto: String, campo: Campo) -> some View {
        HStack {
            Text(titulo)
            Spacer(minLength: 12)
            TextField("0", text: texto)
                .accessibilityLabel("\(titulo) en \(unidadTexto)")
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($foco, equals: campo)
                .frame(maxWidth: 110)
                .monospacedDigit()
            Text(unidadTexto).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .leading)
        }
    }

    /// No frena el guardado: un polvo de proteína con menos de 300 kcal por 100 g (casi seguro, el scoop cargado como 100 g).
    private var avisoPolvo: String? {
        let leer = AlimentoPropioNuevo.leerNumero
        return AlimentoPropioNuevo.avisoPolvoProteina(nombre: nombre, kcal: leer(kcal), prot: leer(prot), carb: leer(carb),
                                                      fat: leer(fat), unidad: unidad, gramosPorUnidad: leer(gramos))
    }

    /// La respuesta a «¿por 100 g o de 1 porción?». De 1 porción pide los gramos (la etiqueta no los dijo).
    private func elegirBase(porcion: Bool) {
        preguntaBase = false
        error = nil
        unidad = porcion ? "porcion" : "g"
        estadoEscaneo = porcion
            ? "Poné cuánto pesa 1 porción en gramos y revisá los valores."
            : "✓ Quedaron como valores por 100 g. Revisalos y tocá \"Crear y usar\"."
        if porcion { foco = .gramos }
    }

    /// "Escanear etiqueta" (F7): prellena todo editable y dice en qué base quedó. Porción con gramos = unidad "porción"
    /// con sus gramos, como la web; 100 g = unidad g; sin gramos de la porción se pregunta (antes se asumía 100 g).
    private func escanear(_ jpeg: Data) {
        escaneando = true
        foco = nil
        Task {
            let r = await modelo.analizarFoto(jpeg, tipo: .etiqueta)
            escaneando = false
            switch r {
            case .success(let data):
                guard let d = try? JSONDecoder().decode(LecturaEtiqueta.self, from: JSONEncoder().encode(data)) else {
                    estadoEscaneo = "⚠ No pudimos leer la foto (respuesta inesperada). Cargalo a mano o probá otra foto con más luz."
                    return
                }
                if let n = d.nombre, !n.isEmpty { nombre = n }
                if let k = d.kcal { kcal = String(k.jsEntero) }
                if let p = d.prot { prot = p.kg }
                if let c = d.carb { carb = c.kg }
                if let f = d.fat { fat = f.kg }
                let base = AlimentoPropioNuevo.baseLectura(porcionG: d.porcionG, base: d.base)
                switch base {
                case .porcion(let g):
                    unidad = "porcion"
                    gramos = String(g.jsEntero)
                    preguntaBase = false
                case .cien:
                    unidad = "g"
                    preguntaBase = false
                case .desconocida:
                    unidad = "g"
                    preguntaBase = true
                }
                error = nil
                estadoEscaneo = AlimentoPropioNuevo.textoLectura(base, confianzaBaja: d.confianza == "baja", avisos: d.avisos)
            case .failure(let e):
                estadoEscaneo = "⚠ No pudimos leer la foto (\(e.clase == .red ? "sin conexión" : e.mensaje)). Cargalo a mano o probá otra foto con más luz."
            }
        }
    }

    private func crear() async {
        foco = nil   // que el aviso de abajo no quede tapado por el teclado (Android ya lo hace)
        if preguntaBase {
            error = "Antes de guardar, elegí si los valores son por 100 g o de 1 porción."
            return
        }
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
