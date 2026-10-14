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
    @State private var analizandoFoto = false

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
            LazyVStack(alignment: .leading, spacing: 16) {
                Cabecera(objetivo: modelo.objetivo, elegidas: totalElegido)
                ForEach(Array(modelo.comidasDelDia.enumerated()), id: \.element.id) { n, c in tarjeta(c, numero: n + 1) }
                if modelo.token != nil {
                    ComidasLibresSeccion(modelo: modelo, analizando: $analizandoFoto)
                }
                PieRespaldo(origen: .dieta)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 32)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await modelo.cargar() }
        .overlay {
            if analizandoFoto {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    AnalizandoFoto(texto: "Analizando el plato…")
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: analizandoFoto)
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

    private func tarjeta(_ c: Comida, numero: Int) -> some View {
        let o = min(opcion[c.id] ?? 0, max(c.opciones.count - 1, 0))
        let alimentos = (c.opciones[safe: o]?.alimentos ?? []).enumerated().map { i, a in
            (i: i, original: a, efectivo: modelo.efectivo(a, comidaId: c.id, opt: o, idx: i))
        }
        let total = ModeloApp.sumar(alimentos.map(\.efectivo.alimento))
        let nombreOpcion = c.opciones[safe: o]?.nombre ?? Self.letra(o)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: Self.iconoComida(c.nombre))
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.marcaTexto)
                    .frame(width: 38, height: 38)
                    .background(Color.marcaSuave, in: .rect(cornerRadius: 11, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.nombre ?? "Comida \(numero)").font(.title3.weight(.semibold))
                    Text("Opción \(nombreOpcion) · \(alimentos.count) \(alimentos.count == 1 ? "alimento" : "alimentos")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text((total.kcal ?? 0).enteroSeguro, format: .number)
                        .font(.numeroMediano)
                        .contentTransition(.numericText())
                    Text("kcal").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if c.opciones.count > 1 {
                HStack(spacing: 12) {
                    Text("Opción").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Picker("Opción", selection: Binding(get: { o }, set: { nuevo in withAnimation(.snappy) { opcion[c.id] = nuevo } })) {
                        ForEach(Array(c.opciones.enumerated()), id: \.offset) { i, op in Text(op.nombre ?? Self.letra(i)).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: o)
                }
            }
            VStack(spacing: 0) {
                ForEach(alimentos, id: \.i) { item in
                    let clave = "\(c.id)|\(o)|\(item.i)"
                    FilaAlimento(original: item.original, mostrado: item.efectivo.alimento, sustituido: item.efectivo.sustituido,
                                 porcionAbierta: porcionesAbiertas.contains(clave)) {
                        withAnimation(.snappy) {
                            if porcionesAbiertas.contains(clave) { porcionesAbiertas.remove(clave) } else { porcionesAbiertas.insert(clave) }
                        }
                    } alReemplazar: {
                        reemplazo = Reemplazo(comidaId: c.id, opt: o, idx: item.i, original: item.original, mostrado: item.efectivo.alimento)
                    } alRevertir: {
                        revertir = Reemplazo(comidaId: c.id, opt: o, idx: item.i, original: item.original, mostrado: item.efectivo.alimento)
                    }
                    if item.i < alimentos.count - 1 { Divider() }
                }
            }
            HStack(spacing: 16) {
                Text("Total").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.5)
                Spacer(minLength: 4)
                MacroMini(letra: "P", valor: total.prot, color: .corazon)
                MacroMini(letra: "C", valor: total.carb, color: .alerta)
                MacroMini(letra: "G", valor: total.fat, color: .sueno)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Color(uiColor: .tertiarySystemFill).opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
        }
        .tarjeta()
        .animation(.snappy, value: o)
    }

    static func letra(_ i: Int) -> String { String(UnicodeScalar(65 + i).map(Character.init) ?? "?") }

    static func iconoComida(_ nombre: String?) -> String {
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

/// Un alimento de la opción elegida: nombre (con el distintivo si está reemplazado), cantidad, kcal y macros, la mano
/// (porción casera) y el reemplazo. Es `renderFood` de la web.
private struct FilaAlimento: View {
    let original: Alimento
    let mostrado: Alimento
    let sustituido: Bool
    let porcionAbierta: Bool
    let alTocarMano: () -> Void
    let alReemplazar: () -> Void
    let alRevertir: () -> Void

    var body: some View {
        let porcion = PorcionCasera.referencia(nombre: mostrado.nombre, qty: mostrado.qty, unidad: mostrado.unidad,
                                               gramosPorUnidad: mostrado.gramosPorUnidad)
        let categoria = CategoriaComida.inferir(original)
        let sustituible = original.sustituible != false && categoria != "condimento"
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mostrado.nombre).font(.body.weight(.medium))
                        if sustituido {
                            Button(action: alRevertir) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption2.weight(.heavy))
                                    .foregroundStyle(Color.sobreMarca)
                                    .padding(5)
                                    .background(Color.marca, in: .circle)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reemplazado. Tocá para volver a \(original.nombre)")
                        }
                    }
                    Text("\(FormatoDieta.cantidad(mostrado.qty, mostrado.unidad)) · \((mostrado.kcal ?? 0).enteroSeguro) kcal")
                        .font(.subheadline).foregroundStyle(.secondary)
                    FormatoDieta.macros(mostrado)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if porcion != nil {
                    BotonCircular(icono: porcionAbierta ? "hand.raised.fill" : "hand.raised", activo: porcionAbierta, accion: alTocarMano)
                        .symbolEffect(.bounce, value: porcionAbierta)
                        .accessibilityLabel(porcionAbierta ? "Ocultar porción casera" : "Ver porción casera")
                }
                if sustituible {
                    BotonCircular(icono: "arrow.left.arrow.right", activo: false, accion: alReemplazar)
                        .accessibilityLabel("Reemplazar \(mostrado.nombre)")
                }
            }
            if porcionAbierta, let porcion {
                Label(porcion.hasPrefix("libre") ? porcion : "≈ \(porcion)", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.marcaSuave, in: .capsule)
                    .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    .accessibilityLabel("Porción casera: \(porcion)")
            }
        }
        .padding(.vertical, 10)
        .sensoryFeedback(.impact(weight: .light), trigger: porcionAbierta)
    }
}

/// Botón redondo de acción en una fila (mano, reemplazo): 44 pt de toque, 34 pt visibles.
private struct BotonCircular: View {
    let icono: String
    let activo: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(activo ? Color.sobreMarca : Color.primary.opacity(0.75))
                .frame(width: 34, height: 34)
                .background(activo ? AnyShapeStyle(Color.marca) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Cómo se escriben cantidades y macros en Dieta.
enum FormatoDieta {
    /// "2 unidades", "110 g", "1 rebanada": la web imprime `qty unit` crudo ("2 unidad"); acá se pluraliza solo lo que
    /// es palabra (las unidades reales de los planes: g, unidad, rebanada, ml, vianda, cuchara, scoop).
    static func cantidad(_ q: Double?, _ u: String?) -> String {
        let unidad = u ?? "g"
        guard let q else { return unidad }
        return "\(q.kg) \(q == 1 ? unidad : plural(unidad))"
    }

    static func plural(_ u: String) -> String {
        let l = u.lowercased()
        if ["g", "gr", "kg", "ml", "l", "cc", "mg", "oz"].contains(l) || l.hasSuffix(".") || u.count <= 2 { return u }
        if l.hasSuffix("s") { return u }
        if l.hasSuffix("ón") { return String(u.dropLast(2)) + "ones" }
        if l.hasSuffix("on") { return u + "es" }
        if let ultima = l.last, "aeiouáéó".contains(ultima) { return u + "s" }
        if l.hasSuffix("d") || l.hasSuffix("r") || l.hasSuffix("l") || l.hasSuffix("n") { return u + "es" }
        return u + "s"
    }

    /// "P 15,1 · C 0,8 · G 11,4", con la letra en el color del macro (como el anillo de arriba).
    static func macros(_ a: Alimento) -> Text { macros(prot: a.prot, carb: a.carb, fat: a.fat) }

    static func macros(prot: Double?, carb: Double?, fat: Double?) -> Text {
        func parte(_ letra: String, _ v: Double?, _ color: Color) -> Text {
            Text(letra).foregroundColor(color).fontWeight(.bold) + Text(" \((v ?? 0).kg)")
        }
        return parte("P", prot, .corazon) + Text("  ·  ") + parte("C", carb, .alerta) + Text("  ·  ") + parte("G", fat, .sueno)
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
        let anillo = ZStack {
            AnilloMacros(partes: [(kcalP / total, .corazon), (kcalC / total, .alerta), (kcalG / total, .sueno)])
            VStack(spacing: 0) {
                Text((objetivo.kcal ?? 0).enteroSeguro, format: .number).font(.numeroGrande).contentTransition(.numericText())
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("kcal por día").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .combine)
        let macros = [("Proteínas", objetivo.prot, kcalP / total, Color.corazon), ("Carbos", objetivo.carb, kcalC / total, Color.alerta),
                      ("Grasas", objetivo.fat, kcalG / total, Color.sueno)]
        VStack(alignment: .leading, spacing: 16) {
            // Anillo y macros lado a lado si entran sin cortar; si no (pantallas angostas, letra grande), uno arriba
            // del otro con los macros en tres columnas.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    anillo
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(macros, id: \.0) { FilaMacro(nombre: $0.0, gramos: $0.1, porcentaje: $0.2, color: $0.3) }
                    }
                }
                VStack(spacing: 18) {
                    anillo
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(macros, id: \.0) { ColumnaMacro(nombre: $0.0, gramos: $0.1, porcentaje: $0.2, color: $0.3) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 8) {
                Image(systemName: abs(delta) <= 5 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(abs(delta) <= 5 ? Color.exito : Color.alerta)
                Text("Con las opciones elegidas: ") + Text("\((elegidas.kcal ?? 0).enteroSeguro) kcal").bold()
                    + Text(abs(delta) < 0.5 ? "" : " (\(delta > 0 ? "+" : "")\(delta.enteroSeguro) %)")
            }
            .font(.footnote)
            .contentTransition(.numericText())
            RenglonFuentes()
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
                Text("\((porcentaje * 100).enteroSeguro) % de las kcal").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text("\((gramos ?? 0).enteroSeguro) g").font(.numeroMediano).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Un macro en columna (cabecera angosta): nombre, gramos grandes y el porcentaje de las kcal.
private struct ColumnaMacro: View {
    let nombre: String
    let gramos: Double?
    let porcentaje: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(nombre).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("\((gramos ?? 0).enteroSeguro) g").font(.numeroMediano).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text("\((porcentaje * 100).enteroSeguro) % kcal").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct MacroMini: View {
    let letra: String
    let valor: Double?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(letra).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("\((valor ?? 0).enteroSeguro) g").font(.caption.monospacedDigit().weight(.medium))
                .contentTransition(.numericText())
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
