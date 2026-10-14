import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Dieta: el plan del día con sus opciones por comida, los reemplazos y la porción casera. Sin "Comí / Salté"
/// (decisión de Mati, 14-oct: marcar cada comida le resultaba molesto al cliente).
struct DietaView: View {
    @State private var modelo = Proveedor.modelo
    @State private var opcion: [String: Int] = [:]
    @State private var porcionesAbiertas: Set<String> = []
    @State private var reemplazo: Reemplazo?
    @State private var revertir: Reemplazo?

    /// La raíz todavía pasa las muestras de los bocetos; Dieta ya usa el modelo real y las ignora.
    init(datos: Muestras? = nil) {}

    struct Reemplazo: Identifiable {
        let comidaId: String
        let opt: Int
        let idx: Int
        let original: Alimento
        let mostrado: Alimento
        var id: String { "\(comidaId)|\(opt)|\(idx)" }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch modelo.fase {
                case .listo where !modelo.comidasDelDia.isEmpty:
                    contenido
                case .listo:
                    ContentUnavailableView("Todavía no hay plan de comidas", systemImage: "fork.knife",
                                           description: Text("Cuando Mati publique tu dieta, la vas a ver acá."))
                case .cargando:
                    ProgressView().controlSize(.large)
                case .sinServicio:
                    ContentUnavailableView {
                        Label("Sin conexión", systemImage: "wifi.slash")
                    } description: {
                        Text("No pudimos traer tu plan. Probá de nuevo cuando tengas señal.")
                    } actions: {
                        Button("Reintentar") { Task { await modelo.cargar() } }.buttonStyle(.bordered)
                    }
                case .sinToken, .tokenInvalido:
                    ContentUnavailableView("Entrá con tu link", systemImage: "link",
                                           description: Text("Abrí el link que te pasó Mati para ver tu plan."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fondo)
            .navigationTitle("Dieta")
            .toolbar { selectorTipoDia }
        }
        .task { if modelo.fase == .cargando || modelo.fase == .sinServicio { await modelo.cargar() } }
        .sheet(item: $reemplazo) { r in
            SustituirAlimentoView(modelo: modelo, original: r.original) { elegido in
                Task { await modelo.sustituir(r.original, por: elegido, comidaId: r.comidaId, opt: r.opt, idx: r.idx) }
            }
        }
        .confirmationDialog("¿Volver al alimento del plan?", isPresented: Binding(get: { revertir != nil }, set: { if !$0 { revertir = nil } }),
                            titleVisibility: .visible, presenting: revertir) { r in
            Button("Volver a \(r.original.nombre)") { Task { await modelo.revertir(comidaId: r.comidaId, opt: r.opt, idx: r.idx) } }
            Button("Cancelar", role: .cancel) {}
        } message: { r in
            Text("Hoy estás comiendo \(r.mostrado.nombre).")
        }
    }

    // MARK: - Contenido

    private var contenido: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Cabecera(objetivo: modelo.objetivo, elegidas: totalElegido)
                ForEach(modelo.comidasDelDia, id: \.id) { c in tarjeta(c) }
                RespaldoCientifico(texto: "Tu plan lo arma Mati, que es médico, con base en ISSN, NASEM y OMS")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await modelo.cargar() }
    }

    @ToolbarContentBuilder
    private var selectorTipoDia: some ToolbarContent {
        if let tipos = modelo.dieta?.estructura.tiposDia, tipos.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Tipo de día", selection: Binding(get: { modelo.tipoDia ?? tipos[0].id }, set: { modelo.tipoDia = $0 })) {
                        ForEach(tipos, id: \.id) { Text($0.nombre ?? $0.id).tag($0.id) }
                    }
                } label: {
                    Label(tipos.first { $0.id == (modelo.tipoDia ?? tipos[0].id) }?.nombre ?? "Tipo de día", systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var totalElegido: Macros {
        ModeloApp.sumar(modelo.comidasDelDia.flatMap { c -> [Alimento] in
            let o = opcion[c.id] ?? 0
            return (c.opciones[safe: o]?.alimentos ?? []).enumerated().map { i, a in
                modelo.efectivo(a, comidaId: c.id, opt: o, idx: i).alimento
            }
        })
    }

    // MARK: - Comida

    private func tarjeta(_ c: Comida) -> some View {
        let o = min(opcion[c.id] ?? 0, max(c.opciones.count - 1, 0))
        let alimentos = (c.opciones[safe: o]?.alimentos ?? []).enumerated().map { i, a in
            (i: i, original: a, efectivo: modelo.efectivo(a, comidaId: c.id, opt: o, idx: i))
        }
        let total = ModeloApp.sumar(alimentos.map(\.efectivo.alimento))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: iconoComida(c.nombre))
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.marcaTexto)
                    .frame(width: 28)
                Text(c.nombre ?? "Comida").font(.title3.weight(.semibold))
                Spacer()
                Text("\(Int(total.kcal ?? 0)) kcal")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            if c.opciones.count > 1 {
                Picker("Opción", selection: Binding(get: { o }, set: { nuevo in withAnimation(.snappy) { opcion[c.id] = nuevo } })) {
                    ForEach(Array(c.opciones.enumerated()), id: \.offset) { i, _ in Text("Opción \(letra(i))").tag(i) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: o)
            }
            VStack(spacing: 0) {
                ForEach(alimentos, id: \.i) { item in
                    fila(c, opt: o, idx: item.i, original: item.original, mostrado: item.efectivo.alimento, sustituido: item.efectivo.sustituido)
                    if item.i < alimentos.count - 1 { Divider().padding(.leading, 2) }
                }
            }
            HStack(spacing: 14) {
                MacroMini(letra: "P", valor: total.prot, color: .corazon)
                MacroMini(letra: "C", valor: total.carb, color: .alerta)
                MacroMini(letra: "G", valor: total.fat, color: .sueno)
            }
        }
        .tarjeta()
        .animation(.snappy, value: o)
    }

    private func fila(_ c: Comida, opt: Int, idx: Int, original: Alimento, mostrado: Alimento, sustituido: Bool) -> some View {
        let id = "\(c.id)|\(opt)|\(idx)"
        let porcion = PorcionCasera.referencia(nombre: mostrado.nombre, qty: mostrado.qty, unidad: mostrado.unidad, gramosPorUnidad: mostrado.gramosPorUnidad)
        let categoria = original.categoria ?? CategoriaComida.inferir(original)
        let sustituible = original.sustituible != false && categoria != "condimento"
        let abierta = porcionesAbiertas.contains(id)
        let r = Reemplazo(comidaId: c.id, opt: opt, idx: idx, original: original, mostrado: mostrado)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mostrado.nombre).font(.body)
                        if sustituido {
                            Button { revertir = r } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.marcaTexto)
                                    .padding(4)
                                    .background(Color.marcaSuave, in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reemplazado. Tocá para volver a \(original.nombre)")
                        }
                    }
                    Text(cantidad(mostrado)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(Int(mostrado.kcal ?? 0))")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                if porcion != nil {
                    Button {
                        withAnimation(.snappy) { if abierta { porcionesAbiertas.remove(id) } else { porcionesAbiertas.insert(id) } }
                    } label: {
                        Image(systemName: abierta ? "hand.raised.fill" : "hand.raised")
                            .symbolEffect(.bounce, value: abierta)
                            .frame(width: 36, height: 36)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(abierta ? Color.marcaTexto : Color.secondary)
                    .accessibilityLabel("Ver porción casera")
                }
                if sustituible {
                    Button { reemplazo = r } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .frame(width: 36, height: 36)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(Color.secondary)
                    .accessibilityLabel("Reemplazar \(mostrado.nombre)")
                }
            }
            .buttonStyle(.borderless)
            if abierta, let porcion {
                Label(porcion.hasPrefix("libre") ? porcion : "≈ \(porcion)", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.marcaTexto)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.marcaSuave, in: .capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.impact(weight: .light), trigger: abierta)
    }

    private func cantidad(_ a: Alimento) -> String {
        guard let q = a.qty else { return a.unidad ?? "" }
        return "\(q.kg) \(a.unidad ?? "g")"
    }

    private func letra(_ i: Int) -> String { String(UnicodeScalar(65 + i).map(Character.init) ?? "?") }

    private func iconoComida(_ nombre: String?) -> String {
        let n = (nombre ?? "").lowercased()
        if n.contains("desayuno") { return "sunrise.fill" }
        if n.contains("almuerzo") { return "sun.max.fill" }
        if n.contains("merienda") { return "cup.and.saucer.fill" }
        if n.contains("cena") { return "moon.stars.fill" }
        if n.contains("pre") || n.contains("post") || n.contains("entreno") { return "bolt.fill" }
        if n.contains("colaci") || n.contains("snack") { return "carrot.fill" }
        return "fork.knife"
    }
}

/// El objetivo del día (no lo consumido: desde D10 no se marcan comidas). El anillo reparte las kcal objetivo entre
/// proteínas, carbos y grasas; abajo, cuánto suman las opciones elegidas.
private struct Cabecera: View {
    let objetivo: Macros
    let elegidas: Macros

    var body: some View {
        let kcalP = (objetivo.prot ?? 0) * 4, kcalC = (objetivo.carb ?? 0) * 4, kcalG = (objetivo.fat ?? 0) * 9
        let total = max(kcalP + kcalC + kcalG, 1)
        let delta = (objetivo.kcal ?? 0) > 0 ? ((elegidas.kcal ?? 0) - (objetivo.kcal ?? 0)) / (objetivo.kcal ?? 1) * 100 : 0
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                ZStack {
                    AnilloMacros(partes: [(kcalP / total, .corazon), (kcalC / total, .alerta), (kcalG / total, .sueno)])
                    VStack(spacing: 0) {
                        Text(Int(objetivo.kcal ?? 0), format: .number).font(.numeroGrande).contentTransition(.numericText())
                        Text("kcal por día").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)
                VStack(alignment: .leading, spacing: 12) {
                    FilaMacro(nombre: "Proteínas", gramos: objetivo.prot, porcentaje: kcalP / total, color: .corazon)
                    FilaMacro(nombre: "Carbos", gramos: objetivo.carb, porcentaje: kcalC / total, color: .alerta)
                    FilaMacro(nombre: "Grasas", gramos: objetivo.fat, porcentaje: kcalG / total, color: .sueno)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: abs(delta) <= 5 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(abs(delta) <= 5 ? Color.exito : Color.alerta)
                Text("Con las opciones elegidas: ") + Text("\(Int(elegidas.kcal ?? 0)) kcal").bold()
                    + Text(abs(delta) < 0.5 ? "" : " (\(delta > 0 ? "+" : "")\(Int(delta.rounded())) %)")
            }
            .font(.footnote)
            .contentTransition(.numericText())
            RespaldoCientifico()
        }
        .tarjeta()
        .animation(.snappy, value: elegidas.kcal)
    }
}

private struct AnilloMacros: View {
    let partes: [(Double, Color)]

    var body: some View {
        ZStack {
            Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 14)
            ForEach(Array(segmentos.enumerated()), id: \.offset) { _, s in
                Circle()
                    .trim(from: s.desde, to: s.hasta)
                    .stroke(s.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    private var segmentos: [(desde: Double, hasta: Double, color: Color)] {
        var acumulado = 0.0
        let hueco = 0.012
        return partes.map { p in
            let s = (desde: acumulado + hueco / 2, hasta: acumulado + max(p.0 - hueco / 2, hueco / 2), color: p.1)
            acumulado += p.0
            return s
        }
    }
}

private struct FilaMacro: View {
    let nombre: String
    let gramos: Double?
    let porcentaje: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(nombre).font(.subheadline.weight(.medium))
                Text("\(Int((porcentaje * 100).rounded())) % de las kcal").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("\(Int(gramos ?? 0)) g").font(.numeroMediano).monospacedDigit()
        }
    }
}

private struct MacroMini: View {
    let letra: String
    let valor: Double?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(letra).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(Int((valor ?? 0).rounded())) g").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
