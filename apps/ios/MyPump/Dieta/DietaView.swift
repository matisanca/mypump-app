import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Dieta: el plan del día con sus opciones por comida, los reemplazos, la porción casera, los ajustes de porciones del
/// día (sumar o restar kcal, gramos a mano, «Hoy no la como»; feedback del 20-oct) y «✓ Comí» / «✗ Salté» con lo
/// consumido arriba (D25, 27-oct: los clientes de 2.0.x no podían seguir lo que comían; en D10 se había sacado).
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

    /// La opción que se ve de cada comida: la que se eligió acá, si no la que comió («Comí»), si no la del ajuste de hoy,
    /// si no A. Dentro de las que hay (si Mati vuelve a publicar con menos opciones, la del ajuste puede no existir).
    private var opcionesVigentes: [String: Int] {
        var r: [String: Int] = [:]
        let marcas = modelo.marcasDeHoy
        for c in modelo.comidasDelDia {
            let o = opcion[c.id] ?? ConsumoDelDia.opcionDeLaMarca(c, marcas[c.id]) ?? modelo.ajustesDeHoy[c.id]?.opcion ?? 0
            r[c.id] = c.opciones.isEmpty ? 0 : min(max(0, o), c.opciones.count - 1)
        }
        return r
    }

    private var contenido: some View {
        let opciones = opcionesVigentes
        let dia = modelo.diaAjustado(opciones: opciones)
        let consumo = modelo.consumo(opciones: opciones)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if claseAncho == .regular {
                        Text("Dieta")
                            .font(Archivo.fuente(34, peso: 800, relativoA: .largeTitle))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, Espacio.s)
                    }
                    Cabecera(objetivo: modelo.objetivo, consumo: consumo, elegidas: Self.total(dia), conAjustes: !modelo.ajustesDeHoy.isEmpty)
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
        // «Comí» / «Salté» (D25). La que hoy no come no se marca.
        let marca = omitida ? nil : modelo.marcasDeHoy[c.id]
        // Los tildes por alimento son índices de la opción con que marcó «Comí»: solo se ven mirando esa opción (la web
        // guardaba el índice de la que se miraba contra la marcada y descontaba otro alimento).
        let oMarcada = ConsumoDelDia.opcionDeLaMarca(c, marca)
        let excluidos: Set<Int>? = oMarcada == o ? Set(marca?.excluidos ?? []) : nil
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
                        Image(systemName: marca?.estado == .comido ? "checkmark" : marca?.estado == .saltado ? "xmark" : Self.iconoComida(c.nombre))
                            .font(.system(size: 17, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(marca?.estado == .comido ? Color.sobreMarca : marca?.estado == .saltado ? Color.secondary : Color.marcaTexto)
                            .frame(width: 38, height: 38)
                            .background(marca?.estado == .comido ? Color.marca : marca?.estado == .saltado ? Color.campo : Color.marcaSuave,
                                        in: .rect(cornerRadius: 11, style: .continuous))
                            .contentTransition(.symbolEffect(.replace))
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
            .accessibilityValue(marca?.estado == .comido ? "La comiste" : marca?.estado == .saltado ? "La salteaste" : "")
            if c.opciones.count > 1 {
                let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
                disposicion {
                    Text("Opción").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Picker("Opción", selection: Binding(get: { o }, set: { nuevo in elegirOpcion(c.id, nuevo) })) {
                        ForEach(Array(c.opciones.enumerated()), id: \.offset) { i, op in Text(op.nombre ?? Self.letra(i)).tag(i) }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: o)
                    .accessibilityIdentifier("opciones-\(c.id)")
                }
            }
            if !omitida {
                BotonesMarca(estado: marca?.estado, comidaId: c.id) { nuevo in
                    Task { await modelo.marcar(c.id, nuevo, opcion: o) }
                }
            }
            if let oMarcada {
                if let excluidos {
                    let contado = alimentos.filter { !excluidos.contains($0.i) }.reduce(0.0) { $0 + ($1.hoy.kcal ?? 0) }
                    let texto = excluidos.isEmpty ? "Destildá lo que no comiste: solo cuenta lo tildado."
                                                  : "Cuenta lo tildado: \(contado.enteroSeguro) de \((total.kcal ?? 0).enteroSeguro) kcal."
                    // Un solo elemento con el texto: si no, VoiceOver (y las pruebas) agarraban el ícono ("checklist").
                    Label(texto, systemImage: "checklist")
                        .font(.footnote).foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(texto)
                        .accessibilityIdentifier("tildes-\(c.id)")
                } else {
                    let comida = c.opciones[safe: oMarcada]?.nombre ?? Self.letra(oMarcada)
                    let texto = "Comiste la opción \(comida). Para marcar qué dejaste, volvé a esa."
                    VStack(alignment: .leading, spacing: 6) {
                        Label(texto, systemImage: "eye")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(texto)
                            .accessibilityIdentifier("tildes-\(c.id)")
                        Button("Ver la opción \(comida)") { elegirOpcion(c.id, oMarcada) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.marcaTexto)
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("ver-opcion-\(c.id)")
                    }
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
                                     tildado: excluidos.map { !$0.contains(item.i) }, idTilde: "comido-\(c.id)-\(item.i)",
                                     alTildar: { Task { await modelo.alternarAlimento(c.id, item.i) } },
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
        .animation(.snappy, value: marca)
    }

    /// Cambiar la opción de una comida ajustada: las cantidades a mano eran de la otra opción y se descartan (las kcal
    /// sumadas o restadas, «no la como» y compensar siguen).
    private func elegirOpcion(_ comidaId: String, _ nueva: Int) {
        withAnimation(.snappy) { opcion[comidaId] = nueva }
        let opciones = opcionesVigentes
        if var a = modelo.ajustesDeHoy[comidaId] {
            guard a.opcion != nueva else { return }
            a.opcion = nueva
            a.cantidades = [:]
            Task { await modelo.ajustar(comidaId, a, opciones: opciones) }
        } else {
            // Sin ajuste en esta comida, igual cambian las kcal del día: el resumen de los ajustes se rehace.
            Task { await modelo.verOpcion(comidaId, nueva) }
        }
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
    /// Con «Comí», mirando la opción que comió: si lo comió (tildado) o lo dejó (DIE-06). nil, sin tilde.
    var tildado: Bool? = nil
    var idTilde: String = ""
    var alTildar: () -> Void = {}
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
                if let tildado {
                    Button(action: alTildar) {
                        Image(systemName: tildado ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(tildado ? Color.marca : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mostrado.nombre)
                    .accessibilityValue(tildado ? "Lo comiste" : "No lo comiste")
                    .accessibilityHint(tildado ? "Tocá si no lo comiste" : "Tocá si lo comiste")
                    .accessibilityAddTraits(.isToggle)
                    .accessibilityIdentifier(idTilde)
                    .sensoryFeedback(.selection, trigger: tildado)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(mostrado.nombre).font(.body.weight(.medium))
                            .strikethrough(tildado == false)
                            .foregroundStyle(tildado == false ? Color.secondary : Color.primary)
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

/// «✓ Comí» / «✗ Salté» de una comida (DIE-05). Tocar el que está marcado lo desmarca, como en la web.
private struct BotonesMarca: View {
    let estado: MarcaComida.Estado?
    let comidaId: String
    let alElegir: (MarcaComida.Estado?) -> Void
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let disposicion = tamañoLetra.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
        disposicion {
            boton(.comido, "Comí", icono: "checkmark", id: "comi")
            boton(.saltado, "Salté", icono: "xmark", id: "salte")
        }
        .sensoryFeedback(trigger: estado) { _, nuevo in
            switch nuevo {
            case .comido: .success
            case .saltado: .selection
            case nil: .impact(weight: .light)
            }
        }
    }

    private func boton(_ e: MarcaComida.Estado, _ texto: String, icono: String, id: String) -> some View {
        let activo = estado == e
        let tinta: Color = e == .comido ? .marca : .alerta
        return Button { alElegir(activo ? nil : e) } label: {
            Label(texto, systemImage: activo ? "\(icono).circle.fill" : icono)
                .font(.subheadline.weight(.semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(activo ? (e == .comido ? Color.sobreMarca : Color.alerta) : Color.primary.opacity(0.8))
        .background(activo ? (e == .comido ? tinta : tinta.opacity(0.16)) : Color.campo, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("\(id)-\(comidaId)")
        .accessibilityAddTraits(activo ? .isSelected : [])
        .accessibilityHint(activo ? "Tocá para desmarcar" : "")
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

/// Lo consumido hoy contra el objetivo del día (DIE-07, D25): el anillo se llena con las kcal de las comidas marcadas
/// «Comí» (con lo que destildó, las porciones de hoy y las comidas libres) y cada macro con su barra. Abajo, cuántas
/// comidas van y cuánto suman las opciones elegidas contra el objetivo.
private struct Cabecera: View {
    let objetivo: Macros
    let consumo: ConsumoDelDia.Consumo
    let elegidas: Macros
    var conAjustes = false
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    @Environment(\.horizontalSizeClass) private var claseAncho

    var body: some View {
        let meta = objetivo.kcal ?? 0
        let delta = meta > 0 ? ((elegidas.kcal ?? 0) - meta) / meta * 100 : 0
        // Con letra de accesibilidad el anillo crece: en 132 las kcal quedaban en "2...." y "kcal...".
        let lado: CGFloat = tamañoLetra.isAccessibilitySize ? 200 : 132
        // Se llena hasta el objetivo; pasado, queda lleno.
        let anillo = AnilloProgreso(fraccion: meta > 0 ? consumo.kcal / meta : 0, grosor: 14, color: .marca) {
            VStack(spacing: 0) {
                Text(consumo.kcal.enteroSeguro, format: .number).font(.numeroGrande).contentTransition(.numericText())
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(meta > 0 ? "de \(meta.enteroSeguro.formatted()) kcal" : "kcal hoy").font(.caption).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.5).lineLimit(1)
            }
            .padding(.horizontal, 14)
        }
        .frame(width: lado, height: lado)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Consumido hoy")
        .accessibilityValue(meta > 0 ? "\(consumo.kcal.enteroSeguro) de \(meta.enteroSeguro) kcal" : "\(consumo.kcal.enteroSeguro) kcal")
        .accessibilityIdentifier("consumido-kcal")
        let macros = [("Proteínas", consumo.prot, objetivo.prot, Color.proteina), ("Carbos", consumo.carb, objetivo.carb, Color.carbohidrato),
                      ("Grasas", consumo.fat, objetivo.fat, Color.grasa)]
        VStack(alignment: .leading, spacing: 16) {
            // En el teléfono, el anillo arriba y los macros en tres cajas de color debajo, en todos los tamaños: lado a lado
            // salía solo en los anchos (el Pro Max, Android) y la cabecera cambiaba de un teléfono a otro (15-oct). En el
            // iPad, lado a lado si entra.
            let tresColumnas = VStack(spacing: 18) {
                anillo
                HStack(alignment: .top, spacing: 10) {
                    ForEach(macros, id: \.0) { ColumnaMacro(nombre: $0.0, consumido: $0.1, objetivo: $0.2, color: $0.3) }
                }
            }
            .frame(maxWidth: .infinity)
            // Letra muy grande: ni las tres columnas entran (quedaban en "P…", "1…"). Van una debajo de la otra.
            let unaDebajoDeOtra = VStack(spacing: 18) {
                anillo
                VStack(spacing: 10) {
                    ForEach(macros, id: \.0) { ColumnaMacro(nombre: $0.0, consumido: $0.1, objetivo: $0.2, color: $0.3) }
                }
            }
            .frame(maxWidth: .infinity)
            if claseAncho == .regular {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) {
                        anillo
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(macros, id: \.0) { FilaMacro(nombre: $0.0, consumido: $0.1, objetivo: $0.2, color: $0.3) }
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
            Group {
                if consumo.hechas + consumo.salteadas == 0 {
                    Label("Tocá «Comí» en cada comida y acá se va sumando lo que comés.", systemImage: "hand.tap")
                } else {
                    Label {
                        Text("Comiste ") + Text("\(consumo.hechas) de \(consumo.comidas)").bold()
                            + Text(consumo.comidas == 1 ? " comida" : " comidas")
                            + Text(consumo.salteadas > 0 ? " · salteaste \(consumo.salteadas)" : "")
                    } icon: {
                        Image(systemName: "fork.knife")
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("consumido-comidas")
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
        .animation(.snappy, value: consumo)
    }
}

/// Lo consumido de un macro contra el objetivo, con una barra en su color.
private struct BarraMacro: View {
    let consumido: Double
    let objetivo: Double?
    let color: Color

    var body: some View {
        let o = objetivo ?? 0
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule().fill(color).frame(width: o > 0 ? g.size.width * min(1, max(0, consumido / o)) : 0)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct FilaMacro: View {
    let nombre: String
    let consumido: Double
    let objetivo: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(nombre).font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                (Text("\(consumido.enteroSeguro)").font(.numeroMediano).monospacedDigit()
                    + Text(" / \((objetivo ?? 0).enteroSeguro) g").font(.subheadline).foregroundColor(.secondary))
                    .contentTransition(.numericText())
            }
            BarraMacro(consumido: consumido, objetivo: objetivo, color: color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre)
        .accessibilityValue("\(consumido.enteroSeguro) de \((objetivo ?? 0).enteroSeguro) g")
    }
}

/// Un macro en columna (cabecera angosta): nombre, lo consumido grande, el objetivo y la barra.
private struct ColumnaMacro: View {
    let nombre: String
    let consumido: Double
    let objetivo: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(nombre).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text("\(consumido.enteroSeguro) g").font(.numeroMediano).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text("de \((objetivo ?? 0).enteroSeguro) g").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            BarraMacro(consumido: consumido, objetivo: objetivo, color: color)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(nombre)
        .accessibilityValue("\(consumido.enteroSeguro) de \((objetivo ?? 0).enteroSeguro) g")
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
