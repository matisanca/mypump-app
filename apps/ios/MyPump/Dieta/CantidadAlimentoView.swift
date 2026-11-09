import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Qué cantidad se está eligiendo: un alimento nuevo para sumar a la comida (D1), uno ya agregado o uno del plan (D2).
struct CantidadAlimento: Identifiable {
    enum Que {
        case nuevo(AgregadosComida.Candidato)
        case agregado(Int64)
        case delPlan(Int)
    }

    let comidaId: String
    let que: Que
    /// Con qué abre (un reciente trae la última cantidad); si no, la de siempre.
    var inicial: (cantidad: Double, medida: AgregadosComida.Medida)? = nil

    var id: String {
        switch que {
        case .nuevo(let c): "\(comidaId)|nuevo|\(c.nombre)"
        case .agregado(let ts): "\(comidaId)|agregado|\(ts)"
        case .delPlan(let i): "\(comidaId)|plan|\(i)"
        }
    }
}

/// La hoja de cantidad de un alimento en una comida de hoy (2.0.3, el pedido con capturas de MyFitnessPal): gramos o
/// porciones (la medida casera de la base o de «la mano»), las kcal y las macros en vivo, a qué comida va y, si la comida
/// sube o baja, si se compensa en las siguientes (D3, el mismo mecanismo de «Ajustar esta comida»). Sirve para sumar un
/// alimento (D1), cambiar uno agregado y cambiar la cantidad de uno del plan (D2, escribe en `cantidades` como el − / +
/// de «Ajustar esta comida»). Nada se guarda hasta «Agregar» o «Listo». La cuenta es de `AgregadosComida` y
/// `AjustePorciones` (la misma en Android).
struct CantidadAlimentoView: View {
    typealias Medida = AgregadosComida.Medida

    let modelo: ModeloApp
    let pedido: CantidadAlimento
    let opciones: [String: Int]
    /// Presentada sola (con «Cancelar»); dentro de la hoja de agregar va con la flecha de volver.
    var enHoja = true
    /// Guardó o borró: se cierra (la hoja de agregar entera, si vino de ahí).
    let alTerminar: () -> Void

    @Environment(\.dismiss) private var cerrar
    @State private var comidaId: String
    @State private var cantidad: Double
    @State private var medida: Medida
    @State private var texto: String
    @State private var compensar: Bool
    /// D2: hasta que no se toca, la cantidad de hoy no queda puesta a mano (puede venir escalada por las kcal sumadas).
    @State private var tocado = false
    @State private var aviso: String?
    @FocusState private var enCampo: Bool
    private let ts: Int64

    init(modelo: ModeloApp, pedido: CantidadAlimento, opciones: [String: Int], enHoja: Bool = true, alTerminar: @escaping () -> Void) {
        self.modelo = modelo
        self.pedido = pedido
        self.opciones = opciones
        self.enHoja = enHoja
        self.alTerminar = alTerminar
        let existente = modelo.ajustesVista[pedido.comidaId]
        var q = 100.0, m = Medida.gramo, ts = Self.nuevoTs(existente)
        switch pedido.que {
        case .nuevo(let c):
            (q, m) = pedido.inicial ?? AgregadosComida.inicial(c)
            if let i = pedido.inicial { q = AgregadosComida.acotar(i.cantidad, i.medida) }
        case .agregado(let t):
            ts = t
            if let a = existente?.agregados.first(where: { $0.ts == t }) {
                q = a.cantidad
                m = AgregadosComida.medidas(a.candidato).first { $0.nombre == a.unidad } ?? Medida(nombre: a.unidad, gramos: a.gramosUnidad ?? 1)
            }
        case .delPlan(let i):
            let dia = modelo.diaAjustado(opciones: opciones)
            let plan = modelo.comidasParaAjustar(opciones: opciones).first { $0.id == pedido.comidaId }?.alimentos[safe: i]
            q = dia[pedido.comidaId]?.alimentos[safe: i]?.qty ?? plan?.qty ?? 0
            m = Medida(nombre: plan?.unidad ?? "g", gramos: 1)
        }
        _comidaId = State(initialValue: pedido.comidaId)
        _cantidad = State(initialValue: q)
        _medida = State(initialValue: m)
        _texto = State(initialValue: q.kg)
        _compensar = State(initialValue: existente?.compensar ?? true)
        self.ts = ts
    }

    /// Un `_ts` nuevo (ms) que no tenga otro agregado de la comida.
    static func nuevoTs(_ a: AjusteComida?) -> Int64 {
        var t = Int64(Date().timeIntervalSince1970 * 1000)
        while a?.agregados.contains(where: { $0.ts == t }) == true { t += 1 }
        return t
    }

    /// El ajuste de una comida tal como está, en la opción que se ve (si era de otra, las cantidades a mano no valen, como
    /// en «Ajustar esta comida»). Sin ajuste, uno nuevo con compensar prendido.
    static func base(_ modelo: ModeloApp, _ comidaId: String, opciones: [String: Int]) -> AjusteComida {
        let opcion = modelo.comidasParaAjustar(opciones: opciones).first { $0.id == comidaId }?.opcion ?? 0
        var a = modelo.ajustesVista[comidaId] ?? AjusteComida(opcion: opcion)
        if a.opcion != opcion { a.opcion = opcion; a.cantidades = [:]; a.anclas = [:] }
        return a
    }

    // MARK: - La cuenta

    private var comidas: [AjustePorciones.ComidaDelDia] { modelo.comidasParaAjustar(opciones: opciones) }

    /// El alimento del plan que se está cambiando (D2), como se ve hoy (con su reemplazo).
    private var delPlan: (i: Int, plan: Alimento)? {
        guard case .delPlan(let i) = pedido.que, let a = comidas.first(where: { $0.id == comidaId })?.alimentos[safe: i] else { return nil }
        return (i, a)
    }

    private var candidato: AgregadosComida.Candidato? {
        switch pedido.que {
        case .nuevo(let c): c
        case .agregado(let t): modelo.ajustesVista[comidaId]?.agregados.first { $0.ts == t }?.candidato
        case .delPlan: nil
        }
    }

    /// Las formas de contar: las del alimento (D1) o la unidad del plan y, si va en gramos, la casera (D2).
    private var medidas: [Medida] {
        if let c = candidato { return AgregadosComida.medidas(c) }
        guard let p = delPlan?.plan else { return [medida] }
        let propia = Medida(nombre: p.unidad ?? "g", gramos: 1)
        guard AjustePorciones.esPeso(p.unidad), let casera = AgregadosComida.medidaCasera(p.nombre) else { return [propia] }
        return [propia, casera]
    }

    /// La cantidad que vale (lo escrito, acotado a lo que se puede servir).
    private var cantidadValida: Double {
        if let p = delPlan?.plan {
            if esMedidaDelPlan { return min(max(0, cantidad.isFinite ? cantidad : 0), AjustePorciones.maximoCantidad(p)) }
            return AgregadosComida.acotar(cantidad, medida)
        }
        return AgregadosComida.acotar(cantidad, medida)
    }

    private var esMedidaDelPlan: Bool { delPlan != nil && medida.gramos == 1 && medida.nombre == (delPlan?.plan.unidad ?? "g") }

    /// D2: la cantidad en la unidad del plan.
    private var cantidadDelPlan: Double {
        guard let p = delPlan?.plan else { return 0 }
        if esMedidaDelPlan { return cantidadValida }
        return min(AjustePorciones.redondear(cantidadValida * medida.gramos, unidad: p.unidad), AjustePorciones.maximoCantidad(p))
    }

    private var agregadoNuevo: AlimentoAgregado? {
        candidato.map { AgregadosComida.agregado($0, cantidad: cantidad, medida: medida, ts: ts) }
    }

    /// El ajuste de la comida con lo de la hoja.
    private var borrador: AjusteComida {
        var a = Self.base(modelo, comidaId, opciones: opciones)
        a.compensar = compensar
        switch pedido.que {
        case .nuevo:
            if let n = agregadoNuevo { a.agregados.append(n) }
        case .agregado(let t):
            if let n = agregadoNuevo, let j = a.agregados.firstIndex(where: { $0.ts == t }) { a.agregados[j] = n }
        case .delPlan(let i):
            if tocado {
                let k = String(i)
                a.cantidades[k] = cantidadDelPlan
                a.anclas[k] = nil
            }
        }
        return a
    }

    private var ajustesConBorrador: [String: AjusteComida] {
        var aj = modelo.ajustesVista
        let b = borrador
        aj[comidaId] = b.neutro ? nil : b
        return aj
    }

    /// Lo que se ve arriba: el agregado o el alimento del plan con la cantidad de la hoja.
    private func mostrado(_ dia: [String: AjustePorciones.ComidaAjustada]) -> Alimento? {
        if let n = agregadoNuevo { return n.alimento }
        if let d = delPlan { return tocado ? AjustePorciones.conCantidad(d.plan, cantidadDelPlan) : (dia[comidaId]?.alimentos[safe: d.i] ?? d.plan) }
        return nil
    }

    // MARK: - Vista

    var body: some View {
        let ajustes = ajustesConBorrador
        let dia = AjustePorciones.dia(comidas, ajustes: ajustes)
        let destino = AjustePorciones.destino(comidas, ajustes: ajustes, despuesDe: comidaId)
        let nombreComida = comidas.first { $0.id == comidaId }?.nombre ?? "la comida"
        List {
            if let a = mostrado(dia) {
                Section { cabecera(a) }
                Section {
                    controlCantidad(a)
                    if medidas.count > 1 {
                        Picker("Medida", selection: Binding(get: { medida }, set: { cambiarMedida($0) })) {
                            ForEach(medidas, id: \.self) { m in
                                Text(m.esGramo || m.gramos == 1 ? m.nombre : "\(m.nombre) (\(m.gramos.kg) g)").tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("cantidad-medida")
                    }
                } header: {
                    Text("Cantidad")
                } footer: {
                    if let p = delPlan?.plan {
                        Text("En el plan: \(FormatoDieta.cantidad(p.qty, p.unidad)). \(modelo.enDiaPasado ? "Vale solo para ese día." : "Vale solo por hoy.")")
                    } else if let casera = textoCasera(a) {
                        Text("≈ \(casera)")
                    }
                }
                Section {
                    if case .nuevo = pedido.que {
                        Picker("Comida", selection: Binding(get: { comidaId }, set: { elegirComida($0) })) {
                            ForEach(comidas.filter { modelo.ajustesVista[$0.id]?.omitida != true }, id: \.id) { Text($0.nombre).tag($0.id) }
                        }
                        .accessibilityIdentifier("cantidad-comida")
                    } else {
                        LabeledContent("Comida", value: nombreComida)
                    }
                    if let destino {
                        Toggle(isOn: $compensar) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Compensar en \(AjustarComidaView.conArticulo(destino.nombre))")
                                Text(AjustarComidaView.textoEfecto(comidas, ajustes, de: comidaId, compensar: compensar))
                                    .font(.footnote).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("cantidad-efecto")
                            }
                        }
                        .tint(Color.marcaVivo)
                        .accessibilityIdentifier("cantidad-compensar")
                    }
                } footer: {
                    if destino == nil {
                        Text("No hay otra comida después para compensar: lo que sumes queda en el total del día.")
                    } else {
                        Text("Para mantener las macros del día, lo que esta comida sube (o baja) sale de las siguientes.")
                    }
                }
                acciones
            } else {
                ContentUnavailableView("Este alimento ya no está en la comida", systemImage: "fork.knife")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if enHoja { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { enCampo = false }
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if let aviso {
                    Label(aviso, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Color.alerta)
                        .accessibilityIdentifier("cantidad-aviso")
                }
                Button(action: guardar) {
                    Text(textoGuardar(nombreComida)).lineLimit(1)
                }
                .buttonStyle(BotonMarca())
                .accessibilityIdentifier("cantidad-confirmar")
                .disabled(mostrado(dia) == nil)
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
        }
        .sensoryFeedback(.selection, trigger: cantidad)
        .onChange(of: texto) { _, t in
            if let v = Double(t.replacingOccurrences(of: ",", with: ".")), v.isFinite { cantidad = v; tocado = true }
        }
    }

    private var titulo: String {
        switch pedido.que {
        case .nuevo: "Agregar alimento"
        case .agregado: "Alimento agregado"
        case .delPlan: "Cantidad"
        }
    }

    private func textoGuardar(_ comida: String) -> String {
        if case .nuevo = pedido.que { return "Agregar \(AjustarComidaView.aLa(comida))" }
        return "Listo"
    }

    /// El nombre, las kcal en grande dentro del anillo de macros (el % de las kcal de cada una) y los gramos de cada macro.
    private func cabecera(_ a: Alimento) -> some View {
        let p = a.prot ?? 0, c = a.carb ?? 0, g = a.fat ?? 0
        let total = max(1, p * 4 + c * 4 + g * 9)
        let partes: [(String, Double, Double, Color)] = [("Carbohidratos", c, c * 4 / total, .carbohidrato),
                                                         ("Grasas", g, g * 9 / total, .grasa), ("Proteínas", p, p * 4 / total, .proteina)]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(a.nombre).font(.headline)
                if candidato?.origen == .propio {
                    Text("★ Tuyo").font(.caption2.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.marcaSuave, in: .capsule)
                }
            }
            // Escaneado (2.1, S3): de dónde salen los valores (la licencia de Open Food Facts pide nombrarla).
            if candidato?.origen == .barras, let codigo = candidato?.codigo {
                Label("Valores de Open Food Facts · \(codigo)", systemImage: "barcode")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityIdentifier("cantidad-origen-barras")
            }
            HStack(spacing: 18) {
                AnilloMacros(partes: partes.map { ($0.2, $0.3) }) {
                    VStack(spacing: 0) {
                        Text((a.kcal ?? 0).enteroSeguro, format: .number).font(.numeroMediano).contentTransition(.numericText())
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 86, height: 86)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Kcal")
                .accessibilityValue("\((a.kcal ?? 0).enteroSeguro) kcal")
                .accessibilityIdentifier("cantidad-kcal")
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(partes, id: \.0) { nombre, gramos, fraccion, color in
                        HStack(spacing: 6) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(nombre).font(.subheadline)
                            Spacer(minLength: 4)
                            Text("\(gramos.kg) g").font(.subheadline.monospacedDigit().weight(.semibold)).contentTransition(.numericText())
                            Text("\((fraccion * 100).enteroSeguro) %").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .frame(minWidth: 34, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: a.kcal)
    }

    /// − / el número / +: se escribe o se toca. El − de uno del plan llega a 0 (no lo come hoy), como en «Ajustar esta comida».
    private func controlCantidad(_ a: Alimento) -> some View {
        HStack(spacing: 12) {
            BotonCantidad(icono: "minus", etiqueta: "Menos", id: "cantidad-menos", habilitado: puedeBajar) { mover(-1) }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                TextField("0", text: $texto)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(Archivo.fuente(30, peso: 800, relativoA: .title1))
                    .focused($enCampo)
                    .fixedSize()
                    .accessibilityLabel("Cantidad en \(medida.nombre)")
                    .accessibilityIdentifier("cantidad-campo")
                Text(medida.nombre.contains(" ") || cantidadValida <= 1 ? medida.nombre : FormatoDieta.plural(medida.nombre))
                    .font(.headline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            BotonCantidad(icono: "plus", etiqueta: "Más", id: "cantidad-mas", habilitado: puedeSubir) { mover(1) }
        }
        .padding(.vertical, 4)
    }

    private var puedeBajar: Bool {
        if delPlan != nil && esMedidaDelPlan { return AjustePorciones.puedeBajar(cantidadValida) }
        return AgregadosComida.bajar(cantidadValida, medida) < cantidadValida
    }

    private var puedeSubir: Bool {
        if let p = delPlan?.plan {
            if esMedidaDelPlan { return AjustePorciones.puedeSubir(p, desde: cantidadValida) }
            return cantidadDelPlan < AjustePorciones.maximoCantidad(p)
        }
        return AgregadosComida.subir(cantidadValida, medida) > cantidadValida
    }

    private func mover(_ sentido: Int) {
        let q = cantidadValida
        let nueva: Double
        if let p = delPlan?.plan, esMedidaDelPlan {
            nueva = sentido > 0 ? AjustePorciones.subir(p, desde: q) : AjustePorciones.bajar(p, desde: q)
        } else {
            nueva = sentido > 0 ? AgregadosComida.subir(q, medida) : AgregadosComida.bajar(q, medida)
        }
        withAnimation(.snappy) {
            cantidad = nueva
            texto = nueva.kg
            tocado = true
        }
    }

    /// Otra medida: la misma cantidad en gramos, contada en la nueva.
    private func cambiarMedida(_ m: Medida) {
        let gramos = cantidadValida * medida.gramos
        medida = m
        let q: Double
        if let p = delPlan?.plan, esMedidaDelPlan { q = min(AjustePorciones.redondear(gramos, unidad: p.unidad), AjustePorciones.maximoCantidad(p)) }
        else { q = AgregadosComida.acotar(gramos / m.gramos, m) }
        cantidad = q
        texto = q.kg
    }

    /// Otra comida destino (solo al agregar): su compensar es el de su ajuste.
    private func elegirComida(_ id: String) {
        comidaId = id
        compensar = modelo.ajustesVista[id]?.compensar ?? true
        aviso = nil
    }

    /// «≈ 1 palma» de lo que se está por agregar en gramos (la misma mano de las filas).
    private func textoCasera(_ a: Alimento) -> String? {
        guard medida.esGramo else { return nil }
        let p = PorcionCasera.referencia(nombre: a.nombre, qty: cantidadValida, unidad: "g", gramosPorUnidad: nil)
        return p.flatMap { $0.hasPrefix("libre") ? nil : $0 }
    }

    @ViewBuilder private var acciones: some View {
        switch pedido.que {
        case .agregado(let t):
            Section {
                Button("Sacar de la comida", role: .destructive) {
                    let id = comidaId
                    Task { await modelo.borrarAgregado(id, ts: t, opciones: opciones) }
                    alTerminar()
                }
                .accessibilityIdentifier("cantidad-borrar")
            }
        case .delPlan(let i):
            if modelo.ajustesVista[comidaId]?.cantidades[String(i)] != nil {
                Section {
                    Button("Como el plan") {
                        var a = borrador
                        a.cantidades[String(i)] = nil
                        a.anclas[String(i)] = nil
                        let id = comidaId
                        Task { await modelo.ajustar(id, a.neutro ? nil : a, opciones: opciones) }
                        alTerminar()
                    }
                    .accessibilityIdentifier("cantidad-como-plan")
                }
            }
        case .nuevo:
            EmptyView()
        }
    }

    private func guardar() {
        let a = borrador
        var dia = modelo.ajustesVista
        dia[comidaId] = a
        if case .delPlan = pedido.que {} else if let m = AgregadosComida.motivoNoEntra(dia, comidaId: comidaId) {
            aviso = m
            return
        }
        let id = comidaId
        Task { await modelo.ajustar(id, a.neutro ? nil : a, opciones: opciones) }
        // A los recientes, solo lo que se agrega (editar uno no lo sube de nuevo; igual en Android).
        if case .nuevo = pedido.que, let n = agregadoNuevo { modelo.recordarReciente(n) }
        alTerminar()
    }
}

/// − o + de la hoja de cantidad: 44 pt de toque, mantener apretado repite.
private struct BotonCantidad: View {
    let icono: String
    let etiqueta: String
    let id: String
    let habilitado: Bool
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Image(systemName: icono)
                .font(.system(size: 17, weight: .bold))
                .frame(width: 46, height: 46)
                .background(Color.marcaSuave, in: .circle)
                .foregroundStyle(habilitado ? Color.marcaTexto : Color.secondary)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!habilitado)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }
}

/// El anillo de las kcal partido por macro (el % de las kcal que pone cada una), como el de MyFitnessPal.
struct AnilloMacros<Centro: View>: View {
    let partes: [(fraccion: Double, color: Color)]
    var grosor: CGFloat = 9
    @ViewBuilder var centro: Centro

    var body: some View {
        ZStack {
            Circle().stroke(Color.campo, lineWidth: grosor)
            let inicios = partes.indices.map { i in partes[..<i].reduce(0) { $0 + $1.fraccion } }
            ForEach(partes.indices, id: \.self) { i in
                if partes[i].fraccion > 0.005 {
                    Circle()
                        .trim(from: inicios[i], to: min(1, inicios[i] + partes[i].fraccion))
                        .stroke(partes[i].color, style: StrokeStyle(lineWidth: grosor, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            centro
        }
        .padding(grosor / 2)
        .animation(.snappy, value: partes.map(\.fraccion))
    }
}
