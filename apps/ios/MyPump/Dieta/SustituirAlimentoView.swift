import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Un candidato para reemplazar un alimento, como lo muestra la hoja. `sustituto.foodData` es exactamente lo que se
/// guarda en `food_data` (el objeto que arma `findSubstitutes` de la web).
struct OpcionSustituto: Identifiable, Equatable {
    let sustituto: Sustituto
    var id: String { sustituto.nombre.lowercased() }
}

/// "Sustituir alimento" (openSwapModal de la web): los universales arriba, los propios con ★, la diferencia de kcal
/// contra el original (verde hasta 5 %), los avisos del motor, búsqueda libre y crear un alimento propio.
struct SustituirAlimentoView: View {
    let modelo: ModeloApp
    let original: Alimento
    let alElegir: (JSONValue) -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var busqueda = ""
    @State private var elegido: OpcionSustituto?
    @State private var resultado = MotorSustitutos.Resultado()
    @State private var creando = false
    /// 2.3.1: el reemplazo elegido suma más del 10 % o más de 60 kcal: se confirma antes de usarlo.
    @State private var aConfirmar: OpcionSustituto?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(original.nombre).font(.headline)
                        Text("\(FormatoDieta.cantidad(original.qty, original.unidad)) · \((original.kcal ?? 0).enteroSeguro) kcal")
                            .font(.subheadline).foregroundStyle(.secondary)
                        FormatoDieta.macros(original).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                } header: {
                    Text("Reemplazás")
                } footer: {
                    Text("¿No conseguís este alimento? Elegí una opción 🌍 disponible en cualquier país.")
                }

                if !resultado.avisos.isEmpty {
                    Section {
                        ForEach(resultado.avisos, id: \.self) { aviso in
                            Label(aviso, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.alerta)
                        }
                    }
                }

                let lista = filtradas
                if lista.isEmpty {
                    Section {
                        ContentUnavailableView(busqueda.isEmpty ? "Sin equivalentes" : "Sin resultados para “\(busqueda)”",
                                               systemImage: "magnifyingglass",
                                               description: Text(busqueda.isEmpty
                                                                 ? "No hay sustitutos equivalentes dentro del rango de macros."
                                                                 : "Probá con otro nombre o creá tu alimento personalizado."))
                    }
                    .listRowBackground(Color.clear)
                } else {
                    // 2.3.1: universales arriba y propios primero solo con hasta 15 % de desvío; el resto, por desvío.
                    let orden = ReemplazosKcal.ordenar(lista, kcalOriginal: original.kcal, kcal: { $0.sustituto.kcal },
                                                       universal: \.sustituto.universal, propio: \.sustituto.esPropio)
                    let universales = orden.universales
                    let resto = orden.resto
                    if !universales.isEmpty {
                        Section("🌍 Disponibles en cualquier país") { ForEach(universales) { fila($0) } }
                    }
                    if !resto.isEmpty {
                        Section(universales.isEmpty ? "Equivalentes" : "Otras opciones") { ForEach(resto) { fila($0) } }
                    }
                }

                Section {
                    Button { creando = true } label: {
                        Label("Crear alimento personalizado", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.marcaTexto)
                    }
                } footer: {
                    Text("Cargalo con los valores de la etiqueta y queda para todos tus reemplazos.")
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
                        Text("\(filtradas.count) de \(resultado.opciones.count) · \(MotorSustitutos.nombreCategoria(resultado.categoria))")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .navigationDestination(isPresented: $creando) {
                CrearAlimentoView(modelo: modelo, categoria: resultado.categoria) { creado in
                    // "Crear y usar": si el motor lo ofrece como sustituto, se aplica de una (aplicarCustomFoodComoSwap).
                    resultado = MotorSustitutos.buscar(original: original, modelo: modelo)
                    if let s = resultado.opciones.first(where: { $0.sustituto.nombre.lowercased() == creado.nombre.lowercased() }) {
                        if ReemplazosKcal.pideConfirmacion(original: original.kcal, reemplazo: s.sustituto.kcal) {
                            // 2.3.1: también confirma; «Elegir otro» deja la lista con el creado elegido.
                            creando = false
                            busqueda = ""
                            elegido = s
                            // La alerta se pide después del pop: si se presenta mientras vuelve la pantalla, SwiftUI la pierde.
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                aConfirmar = s
                            }
                        } else {
                            alElegir(s.sustituto.foodData)
                            cerrar()
                        }
                    } else {
                        creando = false
                        busqueda = ""
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let e = elegido else { return }
                    if ReemplazosKcal.pideConfirmacion(original: original.kcal, reemplazo: e.sustituto.kcal) {
                        aConfirmar = e
                    } else {
                        alElegir(e.sustituto.foodData)
                        cerrar()
                    }
                } label: {
                    Text(elegido.map { "Reemplazar por \($0.sustituto.nombre)" } ?? "Elegí un alimento").lineLimit(1)
                }
                .buttonStyle(BotonMarca())
                .accessibilityIdentifier("confirmar-reemplazo")
                .disabled(elegido == nil)   // BotonMarca ya se ve apagado: sin opacidad encima
                .padding(.horizontal).padding(.vertical, 10)
                .background(.bar)
                .sensoryFeedback(.success, trigger: elegido) { _, n in n != nil }
            }
        }
        .task { resultado = MotorSustitutos.buscar(original: original, modelo: modelo) }
        // 2.3.1: nunca subir las kcal del plan en silencio. «Elegir otro» vuelve a la lista.
        .alert(aConfirmar.map { ReemplazosKcal.textoConfirmacion(original: original.kcal, reemplazo: $0.sustituto.kcal) } ?? "",
               isPresented: Binding(get: { aConfirmar != nil }, set: { if !$0 { aConfirmar = nil } })) {
            Button(ReemplazosKcal.usarIgual) {
                if let e = aConfirmar { alElegir(e.sustituto.foodData); cerrar() }
                aConfirmar = nil
            }
            .accessibilityIdentifier("reemplazo-usar-igual")
            Button(ReemplazosKcal.elegirOtro, role: .cancel) { aConfirmar = nil }
                .accessibilityIdentifier("reemplazo-elegir-otro")
        }
        .presentationDragIndicator(.visible)
    }

    private var filtradas: [OpcionSustituto] {
        guard !busqueda.isEmpty else { return resultado.opciones }
        let ids = Set(SustitucionAlimentos.filtrar(resultado.opciones.map(\.sustituto), consulta: busqueda).map { $0.nombre.lowercased() })
        return resultado.opciones.filter { ids.contains($0.id) }
    }

    private func fila(_ o: OpcionSustituto) -> some View {
        let s = o.sustituto
        // 2.3.1: sin kcal en el original no hay porcentaje: «sin dato» (antes, un 0 % verde).
        let delta = ReemplazosKcal.desvioPct(original: original.kcal, reemplazo: s.kcal)
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
                        Text(s.nombre).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if s.esPropio {
                            Text("★ Tuyo").font(.caption2.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.marcaSuave, in: .capsule)
                        }
                    }
                    if let en = s.nombreIngles, !en.isEmpty { Text(en).font(.caption).foregroundStyle(.secondary) }
                    Text("\(FormatoDieta.cantidad(s.qty, s.unidad)) · \(s.kcal.enteroSeguro) kcal")
                        .font(.subheadline).foregroundStyle(.secondary)
                    FormatoDieta.macros(prot: s.prot, carb: s.carb, fat: s.fat)
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                if let delta {
                    Text("\(delta > 0 ? "+" : "")\(delta) %")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(abs(delta) <= 5 ? Color.exito : Color.alerta)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background((abs(delta) <= 5 ? Color.exito : Color.alerta).opacity(0.14), in: .capsule)
                        .accessibilityLabel("\(delta > 0 ? "más" : "menos") \(abs(delta)) por ciento de calorías")
                } else {
                    Text("sin dato")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.campo, in: .capsule)
                        .accessibilityLabel("sin dato de calorías del original")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sustituto")
        .accessibilityAddTraits(marcado ? .isSelected : [])
        .listRowBackground(marcado ? Color.marcaSuave : Color.tarjeta)
    }
}

/// Puente entre la hoja y el motor portado (`SustitucionAlimentos`, verificado con los vectores de la web).
@MainActor
enum MotorSustitutos {
    struct Resultado {
        var opciones: [OpcionSustituto] = []
        var avisos: [String] = []
        var categoria = ""
    }

    /// La base de la web (MYPUMP_FOOD_DB) empaquetada en la app: se lee una vez.
    static let base: BaseAlimentos = {
        guard let url = Bundle.main.url(forResource: "food-db", withExtension: "json", subdirectory: "Bases.bundle"),
              let datos = try? Data(contentsOf: url), let b = try? BaseAlimentos(json: datos) else { return BaseAlimentos([]) }
        return b
    }()

    /// `openSwapModal` + `findSubstitutes`: la base con los alimentos propios del cliente y sus exclusiones.
    static func buscar(original: Alimento, modelo: ModeloApp) -> Resultado {
        let categoria = CategoriaComida.inferir(original)
        let r = SustitucionAlimentos.buscar(original: original, base: base.conPropios(modelo.alimentosPropios), excluir: modelo.excluir)
        var avisos: [String] = []
        if r.info.macrosSospechosos {
            avisos.append("Los datos de este alimento parecen incorrectos: avisale a Mati así lo corrige.")
        }
        if r.info.prefsFiltraron > 0 && !r.sustitutos.contains(where: { !$0.universal && !$0.esPropio }) {
            avisos.append("\(r.info.prefsFiltraron) opciones quedaron ocultas por tus restricciones alimentarias.")
        }
        return Resultado(opciones: r.sustitutos.map(OpcionSustituto.init), avisos: avisos, categoria: categoria)
    }

    static func nombreCategoria(_ c: String) -> String {
        switch c {
        case CategoriaAlimento.proteina: "proteínas"
        case CategoriaAlimento.lacteo: "lácteos"
        case CategoriaAlimento.grasa: "grasas"
        case CategoriaAlimento.frutaVerdura: "frutas y verduras"
        case CategoriaAlimento.carbohidrato: "carbohidratos"
        case CategoriaAlimento.condimento: "condimentos"
        case CategoriaAlimento.mixto: "mixto"
        default: c
        }
    }
}

/// La categoría de un alimento del plan: la que trae o la inferida, igual que `inferFoodCategory` de la web.
enum CategoriaComida {
    static func inferir(_ a: Alimento) -> String { a.categoria.flatMap { $0.isEmpty ? nil : $0 } ?? CategoriaAlimento.inferir(a) }
}
