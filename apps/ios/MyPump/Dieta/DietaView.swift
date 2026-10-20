import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Dieta: el plan del día con sus opciones por comida, los reemplazos, la porción casera y los ajustes de porciones del
/// día (sumar o restar kcal, gramos a mano, «Hoy no la como»; feedback del 20-oct). Sin "Comí / Salté" (decisión de Mati,
/// 14-oct: marcar cada comida le resultaba molesto al cliente).
struct DietaView: View {
    @State private var modelo = Proveedor.modelo
    @State private var opcion: [String: Int] = [:]
    @State private var porcionesAbiertas: Set<String> = []
    @State private var reemplazo: Reemplazo?
    @State private var revertir: Reemplazo?
    @State private var analizandoFoto = false
    @State private var ajustando: ComidaAAjustar?
    /// En iPad la dieta va en una columna centrada: el título grande del sistema quedaba pegado al borde, lejos de la
    /// columna. Ahí el título va adentro de la columna (como el encabezado de Entreno) y arriba queda chico.
    @Environment(\.horizontalSizeClass) private var claseAncho
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    /// La raíz todavía pasa las muestras de los bocetos; Dieta ya usa el modelo real y las ignora.
    init(datos: Muestras? = nil) {}

    struct ComidaAAjustar: Identifiable {
        let id: String
    }

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
                case .listo where modelo.sinRedEn.contains(.dieta):
                    ContentUnavailableView {
                        Label("No pudimos traer tu dieta", systemImage: "wifi.slash")
                    } description: {
                        Text("Se cortó la conexión. Probá de nuevo cuando tengas señal.")
                    } actions: {
                        Button("Reintentar") { Task { await modelo.cargar() } }.buttonStyle(BotonSecundario(compacto: true))
                    }
                case .listo:
                    ScrollView {
                        ContentUnavailableView("Todavía no hay plan de comidas", systemImage: "fork.knife",
                                               description: Text("Cuando Mati publique tu dieta, la vas a ver acá."))
                            .padding(.top, 80)
                    }
                    .refreshable { await modelo.cargar() }
                case .cargando:
                    ProgressView().controlSize(.large)
                case .sinServicio:
                    ContentUnavailableView {
                        Label("Sin conexión", systemImage: "wifi.slash")
                    } description: {
                        Text("No pudimos traer tu plan. Probá de nuevo cuando tengas señal.")
                    } actions: {
                        Button("Reintentar") { Task { await modelo.cargar() } }.buttonStyle(BotonSecundario(compacto: true))
                    }
                case .sinToken, .tokenInvalido:
                    ContentUnavailableView("Entrá con tu link", systemImage: "link",
                                           description: Text("Abrí el link que te pasó Mati para ver tu plan."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fondo)
            .navigationTitle("Dieta")
            .navigationBarTitleDisplayMode(claseAncho == .regular ? .inline : .automatic)
            .toolbar { selectorTipoDia }
        }
        .task { if modelo.fase == .cargando || modelo.fase == .sinServicio { await modelo.cargar() } }
        .sheet(item: $reemplazo) { r in
            SustituirAlimentoView(modelo: modelo, original: r.original) { elegido in
                Task { await modelo.sustituir(r.original, por: elegido, comidaId: r.comidaId, opt: r.opt, idx: r.idx) }
            }
        }
        .sheet(item: $ajustando) { a in
            AjustarComidaView(modelo: modelo, comidaId: a.id, opciones: opcionesVigentes)
        }
    }

    // MARK: - Contenido

    /// La opción que se ve de cada comida: la que se eligió acá, si no la del ajuste de hoy, si no A.
    private var opcionesVigentes: [String: Int] {
        var r: [String: Int] = [:]
        for c in modelo.comidasDelDia { r[c.id] = opcion[c.id] ?? modelo.ajustesDeHoy[c.id]?.opcion ?? 0 }
        return r
    }

    private var contenido: some View {
        let dia = modelo.diaAjustado(opciones: opcionesVigentes)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if claseAncho == .regular {
                        Text("Dieta")
                            .font(Archivo.fuente(34, peso: 800, relativoA: .largeTitle))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, Espacio.s)
                    }
                    Cabecera(objetivo: modelo.objetivo, elegidas: Self.total(dia), conAjustes: !modelo.ajustesDeHoy.isEmpty)
                    BannerRevision()
                    ForEach(Array(modelo.comidasDelDia.enumerated()), id: \.element.id) { n, c in
                        tarjeta(c, numero: n + 1, ajustada: dia[c.id])
                    }
                }
                // Afuera de la lista perezosa: en iOS 17 una `.sheet` o un `.alert` de una vista que vive adentro de un
                // `LazyVStack` no se presenta, y "A mano" y "Con foto" no hacían nada (lo agarró DietaUITests en 17.5; en
                // 18 y 26 andaba).
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

    /// Lo del día con las opciones elegidas, los reemplazos y los ajustes de hoy.
    static func total(_ dia: [String: AjustePorciones.ComidaAjustada]) -> Macros {
        ModeloApp.sumar(dia.values.flatMap(\.alimentos))
    }

    // MARK: - Comida

    private func tarjeta(_ c: Comida, numero: Int, ajustada: AjustePorciones.ComidaAjustada?) -> some View {
        let o = min(opcionesVigentes[c.id] ?? 0, max(c.opciones.count - 1, 0))
        let alimentos = (c.opciones[safe: o]?.alimentos ?? []).enumerated().map { i, a in
            let e = modelo.efectivo(a, comidaId: c.id, opt: o, idx: i)
            // Lo que se muestra: el reemplazo (si hay) con la cantidad del ajuste de hoy (si hay).
            return (i: i, original: a, efectivo: e, hoy: ajustada?.alimentos[safe: i] ?? e.alimento)
        }
        let omitida = ajustada?.omitida == true
        // La ajustó el cliente (no solo le llega lo de otra).
        let propia = modelo.ajustesDeHoy[c.id] != nil
        let total = ModeloApp.sumar(alimentos.map(\.hoy))
        let nombreOpcion = c.opciones[safe: o]?.nombre ?? Self.letra(o)
        // Con letra de accesibilidad lo de cada renglón va uno debajo del otro: lado a lado se cortaban las palabras
        // ("Op-ción A · 3 ali-men-tos") y el total quedaba ilegible ("T / OT / AL").
        let apilada = tamañoLetra.isAccessibilitySize
        let titulo = VStack(alignment: .leading, spacing: 1) {
            Text(c.nombre ?? "Comida \(numero)").font(.title3.weight(.semibold))
            Text("Opción \(nombreOpcion) · \(alimentos.count) \(alimentos.count == 1 ? "alimento" : "alimentos")")
                .font(.footnote).foregroundStyle(.secondary)
        }
        let kcal = Text((total.kcal ?? 0).enteroSeguro, format: .number).font(.numeroMediano).contentTransition(.numericText())
        return VStack(alignment: .leading, spacing: 14) {
            Group {
                if apilada {
                    VStack(alignment: .leading, spacing: 4) {
                        titulo
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            kcal
                            Text("kcal").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: Self.iconoComida(c.nombre))
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color.marcaTexto)
                            .frame(width: 38, height: 38)
                            .background(Color.marcaSuave, in: .rect(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)
                        titulo
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 0) {
                            kcal
                            Text("kcal").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            if c.opciones.count > 1 {
                let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                disposicion {
                    Text("Opción").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Picker("Opción", selection: Binding(get: { o }, set: { nuevo in elegirOpcion(c.id, nuevo) })) {
                        ForEach(Array(c.opciones.enumerated()), id: \.offset) { i, op in Text(op.nombre ?? Self.letra(i)).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: o)
                }
            }
            if let ajustada, AvisoAjuste.hayQueMostrar(ajustada, propia: propia) {
                AvisoAjuste(ajustada: ajustada, propia: propia)
                    .accessibilityIdentifier("ajuste-aviso-\(c.id)")
            }
            if !omitida {
                VStack(spacing: 0) {
                    ForEach(alimentos, id: \.i) { item in
                        let clave = "\(c.id)|\(o)|\(item.i)"
                        FilaAlimento(original: item.original, mostrado: item.hoy, sustituido: item.efectivo.sustituido,
                                     enElPlan: item.hoy.qty != item.efectivo.alimento.qty ? item.efectivo.alimento : nil,
                                     porcionAbierta: porcionesAbiertas.contains(clave)) {
                            withAnimation(.snappy) {
                                if porcionesAbiertas.contains(clave) { porcionesAbiertas.remove(clave) } else { porcionesAbiertas.insert(clave) }
                            }
                        } alReemplazar: {
                            reemplazo = Reemplazo(comidaId: c.id, opt: o, idx: item.i, original: item.original, mostrado: item.efectivo.alimento)
                        } alRevertir: {
                            revertir = Reemplazo(comidaId: c.id, opt: o, idx: item.i, original: item.original, mostrado: item.efectivo.alimento)
                        }
                        // Colgada de la fila: en iOS 26 la confirmación es un globo que apunta a lo que se tocó. Colgada de toda
                        // la pantalla salía arriba, tapando el aviso de la demo y apuntando al gráfico de calorías.
                        .confirmationDialog("¿Volver al alimento del plan?",
                                            isPresented: Binding(get: { revertir?.id == clave }, set: { if !$0 { revertir = nil } }),
                                            titleVisibility: .visible, presenting: revertir) { r in
                            Button("Volver a \(r.original.nombre)") { Task { await modelo.revertir(comidaId: r.comidaId, opt: r.opt, idx: r.idx) } }
                            Button("Cancelar", role: .cancel) {}
                        } message: { r in
                            Text("Hoy estás comiendo \(r.mostrado.nombre).")
                        }
                        if item.i < alimentos.count - 1 { Divider() }
                    }
                }
                Group {
                    let rotulo = Text("Total").font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase).tracking(0.5)
                    if apilada {
                        VStack(alignment: .leading, spacing: 6) {
                            rotulo
                            MacroMini(letra: "P", valor: total.prot, color: .proteina)
                            MacroMini(letra: "C", valor: total.carb, color: .carbohidrato)
                            MacroMini(letra: "G", valor: total.fat, color: .grasa)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(spacing: 16) {
                            rotulo
                            Spacer(minLength: 4)
                            MacroMini(letra: "P", valor: total.prot, color: .proteina)
                            MacroMini(letra: "C", valor: total.carb, color: .carbohidrato)
                            MacroMini(letra: "G", valor: total.fat, color: .grasa)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color(uiColor: .tertiarySystemFill).opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
            }
            Button { ajustando = ComidaAAjustar(id: c.id) } label: {
                Label(propia ? "Cambiar el ajuste" : "Ajustar esta comida", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.marcaTexto)
            .background(Color.marcaSuave.opacity(0.6), in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier("ajustar-\(c.id)")
        }
        .tarjeta()
        .animation(.snappy, value: o)
        .animation(.snappy, value: ajustada?.kcal)
    }

    /// Cambiar la opción de una comida ajustada: las cantidades a mano eran de la otra opción y se descartan (las kcal
    /// sumadas o restadas, «no la como» y compensar siguen).
    private func elegirOpcion(_ comidaId: String, _ nueva: Int) {
        withAnimation(.snappy) { opcion[comidaId] = nueva }
        guard var a = modelo.ajustesDeHoy[comidaId], a.opcion != nueva else { return }
        a.opcion = nueva
        a.cantidades = [:]
        let opciones = opcionesVigentes
        Task { await modelo.ajustar(comidaId, a, opciones: opciones) }
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
    /// Si el ajuste de hoy cambió la cantidad: lo del plan, para mostrarlo al lado.
    var enElPlan: Alimento? = nil
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
                            .contentShape(Rectangle().inset(by: -12))   // 44 pt de toque sin agrandar el distintivo
                            .accessibilityLabel("Reemplazado. Tocá para volver a \(original.nombre)")
                        }
                    }
                    Text("\(FormatoDieta.cantidad(mostrado.qty, mostrado.unidad)) · \((mostrado.kcal ?? 0).enteroSeguro) kcal")
                        .font(.subheadline).foregroundStyle(enElPlan != nil ? Color.marcaTexto : .secondary)
                        .contentTransition(.numericText())
                    if let enElPlan {
                        Text("En el plan: \(FormatoDieta.cantidad(enElPlan.qty, enElPlan.unidad))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
        return parte("P", prot, .proteina) + Text("  ·  ") + parte("C", carb, .carbohidrato) + Text("  ·  ") + parte("G", fat, .grasa)
    }
}

/// El objetivo del día (no lo consumido: desde D10 no se marcan comidas). El anillo reparte las kcal objetivo entre
/// proteínas, carbos y grasas; abajo, cuánto suman las opciones elegidas.
private struct Cabecera: View {
    let objetivo: Macros
    let elegidas: Macros
    var conAjustes = false
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    @Environment(\.horizontalSizeClass) private var claseAncho

    var body: some View {
        let kcalP = (objetivo.prot ?? 0) * 4, kcalC = (objetivo.carb ?? 0) * 4, kcalG = (objetivo.fat ?? 0) * 9
        let total = max(kcalP + kcalC + kcalG, 1)
        let delta = (objetivo.kcal ?? 0) > 0 ? ((elegidas.kcal ?? 0) - (objetivo.kcal ?? 0)) / (objetivo.kcal ?? 1) * 100 : 0
        // Con letra de accesibilidad el anillo crece: en 132 las kcal quedaban en "2...." y "kcal...".
        let lado: CGFloat = tamañoLetra.isAccessibilitySize ? 200 : 132
        let anillo = ZStack {
            AnilloMacros(partes: [(kcalP / total, .proteina), (kcalC / total, .carbohidrato), (kcalG / total, .grasa)])
            VStack(spacing: 0) {
                Text((objetivo.kcal ?? 0).enteroSeguro, format: .number).font(.numeroGrande).contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("kcal por día").font(.caption).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: lado, height: lado)
        .accessibilityElement(children: .combine)
        let macros = [("Proteínas", objetivo.prot, kcalP / total, Color.proteina), ("Carbos", objetivo.carb, kcalC / total, Color.carbohidrato),
                      ("Grasas", objetivo.fat, kcalG / total, Color.grasa)]
        VStack(alignment: .leading, spacing: 16) {
            // En el teléfono, el anillo arriba y los macros en tres cajas de color debajo, en todos los tamaños: lado a lado
            // salía solo en los anchos (el Pro Max, Android) y la cabecera cambiaba de un teléfono a otro (15-oct). En el
            // iPad, lado a lado si entra.
            let tresColumnas = VStack(spacing: 18) {
                anillo
                HStack(alignment: .top, spacing: 10) {
                    ForEach(macros, id: \.0) { ColumnaMacro(nombre: $0.0, gramos: $0.1, porcentaje: $0.2, color: $0.3) }
                }
            }
            .frame(maxWidth: .infinity)
            // Letra muy grande: ni las tres columnas entran (quedaban en "P…", "1…"). Van una debajo de la otra.
            let unaDebajoDeOtra = VStack(spacing: 18) {
                anillo
                VStack(spacing: 10) {
                    ForEach(macros, id: \.0) { ColumnaMacro(nombre: $0.0, gramos: $0.1, porcentaje: $0.2, color: $0.3) }
                }
            }
            .frame(maxWidth: .infinity)
            if claseAncho == .regular {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        anillo
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(macros, id: \.0) { FilaMacro(nombre: $0.0, gramos: $0.1, porcentaje: $0.2, color: $0.3) }
                        }
                    }
                    tresColumnas
                    unaDebajoDeOtra
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    tresColumnas
                    unaDebajoDeOtra
                }
            }
            HStack(spacing: 8) {
                Image(systemName: abs(delta) <= 5 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(abs(delta) <= 5 ? Color.exito : Color.alerta)
                Text(conAjustes ? "Con tus ajustes de hoy: " : "Con las opciones elegidas: ") + Text("\((elegidas.kcal ?? 0).enteroSeguro) kcal").bold()
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

/// Lo que cambió de una comida hoy: lo que hizo el cliente y lo que tomó de las anteriores (lo que solo pasa de largo,
/// porque no la come o no tiene qué escalar, no se cuenta acá: se ve en la que lo recibe).
private struct AvisoAjuste: View {
    let ajustada: AjustePorciones.ComidaAjustada
    /// La ajustó el cliente.
    let propia: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if ajustada.omitida {
                Label("Hoy no la comés", systemImage: "moon.zzz.fill")
            } else if propia {
                Label(abs(ajustada.propio) >= 1 ? "Ajustada: \(AjustarComidaView.signo(ajustada.propio)) kcal" : "Ajustada a mano",
                      systemImage: "slider.horizontal.3")
            }
            let llega = Self.llega(ajustada, propia: propia)
            if !ajustada.omitida, abs(ajustada.absorbido) >= 1, abs(llega) >= 1 {
                let de = ajustada.compensaDe.map(AjustarComidaView.conArticulo)
                Label("\(AjustarComidaView.signo(llega)) kcal por \(de.isEmpty ? "la comida anterior" : AjustarComidaView.unir(de))",
                      systemImage: llega < 0 ? "arrow.down.right" : "arrow.up.right")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(Color.marcaTexto)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.marcaSuave, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Lo que cambió por las anteriores. Si solo recibe, todo lo que cambió es por ellas: la diferencia real (con el redondeo
    /// de las porciones), la misma que anticipó la hoja de la que la mandó. Con un ajuste propio, lo que tomó (lo propio va
    /// en el renglón de arriba).
    static func llega(_ a: AjustePorciones.ComidaAjustada, propia: Bool) -> Double { propia ? a.absorbido : a.kcal - a.kcalPlan }

    static func hayQueMostrar(_ a: AjustePorciones.ComidaAjustada, propia: Bool) -> Bool {
        a.omitida || propia || (abs(a.absorbido) >= 1 && abs(llega(a, propia: false)) >= 1)
    }
}
