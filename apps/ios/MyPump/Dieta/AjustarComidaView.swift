import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Ajustar una comida de hoy (feedback de clientes del 20-oct): sumar o restar kcal (las porciones se recalculan parejo),
/// las cantidades de cada alimento a mano, «Hoy no la como» y si la diferencia se compensa en las comidas siguientes. Se
/// ve el efecto en vivo (las kcal, las macros, el resto del día); nada se guarda hasta «Listo». La cuenta es de
/// `AjustePorciones` (la misma en Android).
struct AjustarComidaView: View {
    let modelo: ModeloApp
    let comidaId: String
    /// Las opciones elegidas en Dieta (la de esta comida incluida): cambian qué alimentos tiene cada comida.
    let opciones: [String: Int]
    @Environment(\.dismiss) private var cerrar
    @State private var borrador: AjusteComida
    private let teniaAjuste: Bool

    init(modelo: ModeloApp, comidaId: String, opciones: [String: Int]) {
        self.modelo = modelo
        self.comidaId = comidaId
        self.opciones = opciones
        // La opción como la ve la cuenta del día (acotada a las que hay) y el ajuste guardado sin lo que ya no vale (una
        // cantidad de un alimento que Mati cambió, kcal que ya no entran): si no, los − / + no hacían nada.
        let comida = modelo.comidasParaAjustar(opciones: opciones).first { $0.id == comidaId }
        let elegida = comida?.opcion ?? 0
        var a = modelo.ajustesDeHoy[comidaId] ?? AjusteComida(opcion: elegida)
        if a.opcion != elegida { a.opcion = elegida; a.cantidades = [:]; a.anclas = [:] }
        if let comida { a = AjustePorciones.anclar(a, en: comida) }
        _borrador = State(initialValue: a)
        teniaAjuste = modelo.ajustesDeHoy[comidaId] != nil
    }

    /// Con un alimento puesto a mano entra menos: las kcal sumadas o restadas quedan dentro de lo que la comida absorbe
    /// (si no, el control decía +500 con +210 de verdad y el −50 no hacía nada).
    private func acotarBorrador() {
        guard let c = modelo.comidasParaAjustar(opciones: opciones).first(where: { $0.id == comidaId }) else { return }
        let d = AjustePorciones.acotarDelta(borrador.deltaKcal, AjustePorciones.limitesDelta(c, borrador))
        if d != borrador.deltaKcal { borrador.deltaKcal = d }
    }

    /// Los ajustes del día con el borrador en lugar del guardado.
    private var ajustes: [String: AjusteComida] {
        var aj = modelo.ajustesDeHoy
        aj[comidaId] = borrador.neutro ? nil : borrador
        return aj
    }

    var body: some View {
        let comidas = modelo.comidasParaAjustar(opciones: opciones)
        let ajustes = self.ajustes
        let dia = AjustePorciones.dia(comidas, ajustes: ajustes)
        let comida = comidas.first { $0.id == comidaId }
        let destino = AjustePorciones.destino(comidas, ajustes: ajustes, despuesDe: comidaId)
        NavigationStack {
            List {
                if let comida, let r = dia[comidaId] {
                    Section { resumen(r, comida: comida, dia: dia) }
                    Section {
                        controlKcal(comida)
                        if let destino {
                            Toggle(isOn: $borrador.compensar) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Compensar en \(Self.conArticulo(destino.nombre))")
                                    Text(textoCompensacion(comidas, ajustes))
                                        .font(.footnote).foregroundStyle(.secondary)
                                        .accessibilityIdentifier("ajuste-efecto")
                                }
                            }
                            .tint(Color.marcaVivo)
                            .accessibilityIdentifier("ajuste-compensar")
                        }
                        Toggle(isOn: $borrador.omitida.animation(.snappy)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hoy no la como")
                                Text(borrador.omitida && borrador.compensar && destino != nil
                                     ? "Sus \(r.kcalPlan.enteroSeguro) kcal pasan \(Self.aLa(destino?.nombre ?? ""))."
                                     : "Las porciones de esta comida quedan en cero por hoy.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .tint(Color.marcaVivo)
                        .accessibilityIdentifier("ajuste-omitir")
                    } footer: {
                        if destino == nil {
                            Text("No hay otra comida después para compensar: lo que cambies queda en el total del día.")
                        }
                    }
                    if !borrador.omitida {
                        Section {
                            ForEach(Array(comida.alimentos.enumerated()), id: \.offset) { i, plan in
                                filaAlimento(i, plan: plan, hoy: r.alimentos[safe: i] ?? plan)
                            }
                        } header: {
                            Text("Alimentos")
                        } footer: {
                            Text("Tocá − o + para cambiar la cantidad de un alimento; en 0 no lo comés hoy. Para volver a la del plan, deslizalo.")
                        }
                    }
                    Section {
                        Label("Vale solo por hoy: mañana vuelve tu plan.", systemImage: "calendar")
                            .font(.footnote).foregroundStyle(.secondary)
                        if teniaAjuste || !borrador.neutro {
                            Button("Volver al plan", role: .destructive) {
                                Task { await modelo.ajustar(comidaId, nil, opciones: opciones) }
                                cerrar()
                            }
                            .accessibilityIdentifier("ajuste-volver-plan")
                        }
                    }
                } else {
                    ContentUnavailableView("Esta comida ya no está en tu plan", systemImage: "fork.knife")
                }
            }
            .navigationTitle("Ajustar \(comida?.nombre ?? "comida")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        let a = borrador
                        Task { await modelo.ajustar(comidaId, a.neutro ? nil : a, opciones: opciones) }
                        cerrar()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("ajuste-listo")
                }
            }
            .sensoryFeedback(.selection, trigger: borrador)
            .onChange(of: borrador.cantidades) { acotarBorrador() }
        }
        .presentationDetents([.large])
    }

    // MARK: - Partes

    /// Las kcal de hoy en grande contra las del plan, las macros (Emilio: «jugar con los gramos de proteínas,
    /// carbohidratos y grasas»), lo que le llega de antes y cómo queda el día.
    private func resumen(_ r: AjustePorciones.ComidaAjustada, comida: AjustePorciones.ComidaDelDia,
                         dia: [String: AjustePorciones.ComidaAjustada]) -> some View {
        let diferencia = r.kcal - r.kcalPlan
        let hoy = ModeloApp.sumar(r.alimentos), plan = ModeloApp.sumar(comida.alimentos)
        let diaHoy = dia.values.reduce(0) { $0 + $1.kcal }, diaPlan = dia.values.reduce(0) { $0 + $1.kcalPlan }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(r.kcal.enteroSeguro, format: .number)
                        .font(Archivo.fuente(40, peso: 800, relativoA: .largeTitle))
                        .contentTransition(.numericText())
                    Text("kcal").font(.headline).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    if abs(diferencia) >= 1 {
                        Text(Self.signo(diferencia))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.marcaTexto)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.marcaSuave, in: .capsule)
                    }
                }
                Text("En el plan: \(r.kcalPlan.enteroSeguro) kcal")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Kcal de esta comida")
            .accessibilityValue("\(r.kcal.enteroSeguro) kcal" + (abs(diferencia) >= 1 ? ", \(Self.signo(diferencia)) contra el plan" : "")
                                + ", en el plan \(r.kcalPlan.enteroSeguro)")
            .accessibilityIdentifier("ajuste-kcal")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { macros(hoy, plan) }
                VStack(alignment: .leading, spacing: 6) { macros(hoy, plan) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("ajuste-macros")
            if abs(r.absorbido) >= 1 {
                Label(textoLlega(r), systemImage: r.absorbido < 0 ? "arrow.down.right" : "arrow.up.right")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text("Tu día: \(diaHoy.enteroSeguro) kcal · en el plan \(diaPlan.enteroSeguro)")
                .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityIdentifier("ajuste-dia")
        }
        .animation(.snappy, value: r.kcal)
    }

    @ViewBuilder private func macros(_ hoy: Macros, _ plan: Macros) -> some View {
        MacroDelAjuste(nombre: "Proteínas", letra: "P", hoy: hoy.prot ?? 0, plan: plan.prot ?? 0, color: .proteina)
        MacroDelAjuste(nombre: "Carbohidratos", letra: "C", hoy: hoy.carb ?? 0, plan: plan.carb ?? 0, color: .carbohidrato)
        MacroDelAjuste(nombre: "Grasas", letra: "G", hoy: hoy.fat ?? 0, plan: plan.fat ?? 0, color: .grasa)
    }

    /// −50 / +50 kcal, con lo sumado en el medio. Mantener apretado repite. Los topes (un cuarto, el triple) son de lo que
    /// se puede agrandar o achicar: lo puesto a mano no cuenta.
    private func controlKcal(_ comida: AjustePorciones.ComidaDelDia) -> some View {
        let paso = AjustePorciones.paso
        let base = AjustePorciones.baseEscalable(comida, borrador)
        let limites = AjustePorciones.limitesDelta(comida, borrador)
        let minimo = limites.lowerBound, maximo = limites.upperBound
        let activo = !borrador.omitida && base > 0
        let menos = botonKcal("−\(paso)", "Restar \(paso) kcal", "ajuste-menos", habilitado: activo && borrador.deltaKcal > minimo) {
            borrador.deltaKcal = max(minimo, borrador.deltaKcal - paso)
        }
        let mas = botonKcal("+\(paso)", "Sumar \(paso) kcal", "ajuste-mas", habilitado: activo && borrador.deltaKcal < maximo) {
            borrador.deltaKcal = min(maximo, borrador.deltaKcal + paso)
        }
        let cuanto = VStack(spacing: 0) {
            Text(borrador.deltaKcal == 0 ? "Como el plan" : "\(Self.signo(Double(borrador.deltaKcal))) kcal")
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText())
            Text("a esta comida").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        return VStack(alignment: .leading, spacing: 6) {
            // Con la letra de accesibilidad no entra en un renglón: lo sumado arriba y los botones abajo.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    menos
                    cuanto.fixedSize().frame(maxWidth: .infinity)
                    mas
                }
                VStack(spacing: 10) {
                    cuanto.frame(maxWidth: .infinity)
                    HStack { menos; Spacer(); mas }
                }
            }
            if !borrador.omitida && base == 0 {
                Text(AjustePorciones.baseEscalable(comida, nil) > 0
                     ? "Con todo puesto a mano, las kcal son la suma de los alimentos."
                     : "Esta comida no tiene cantidades para recalcular.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(borrador.omitida ? 0.4 : 1)
    }

    private func botonKcal(_ texto: String, _ etiqueta: String, _ id: String, habilitado: Bool, accion: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { accion() } } label: {
            Text(texto)
                .font(.headline.monospacedDigit())
                .frame(minWidth: 64, minHeight: 44)
                .background(Color.marcaSuave, in: .capsule)
                .foregroundStyle(habilitado ? Color.marcaTexto : Color.secondary)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!habilitado)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }

    /// Un alimento: lo de hoy (con lo del plan al lado si cambió) y − / + para ponerlo a mano.
    private func filaAlimento(_ i: Int, plan: Alimento, hoy: Alimento) -> some View {
        let clave = String(i)
        let aMano = borrador.cantidades[clave] != nil
        let q = hoy.qty ?? 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hoy.nombre).font(.body.weight(.medium))
                Text("\(FormatoDieta.cantidad(hoy.qty, hoy.unidad)) · \((hoy.kcal ?? 0).enteroSeguro) kcal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(hoy.qty != plan.qty ? Color.marcaTexto : .secondary)
                    .contentTransition(.numericText())
                if hoy.qty != plan.qty {
                    Text("En el plan: \(FormatoDieta.cantidad(plan.qty, plan.unidad))\(aMano ? " · a mano" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if plan.qty != nil, (plan.kcal ?? 0) > 0 {
                HStack(spacing: 6) {
                    // Desde la cantidad a mano de ahora si ya la tiene (dos toques seguidos), si no la de hoy. El − llega a 0:
                    // ese alimento sale de la comida por hoy.
                    BotonPaso(icono: "minus", etiqueta: "Menos \(plan.nombre)", habilitado: AjustePorciones.puedeBajar(q)) {
                        borrador.cantidades[clave] = AjustePorciones.bajar(plan, desde: borrador.cantidades[clave] ?? q)
                    }
                    BotonPaso(icono: "plus", etiqueta: "Más \(plan.nombre)", habilitado: AjustePorciones.puedeSubir(plan, desde: q)) {
                        borrador.cantidades[clave] = AjustePorciones.subir(plan, desde: borrador.cantidades[clave] ?? q)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            if aMano {
                Button("Como el plan") {
                    withAnimation(.snappy) {
                        borrador.cantidades[clave] = nil
                        borrador.anclas[clave] = nil
                    }
                }
                .tint(Color.marca)
            }
        }
        .accessibilityIdentifier("ajuste-alimento-\(i)")
    }

    /// Lo que este ajuste le hace al resto del día, comida por comida (y lo que no entra en ninguna).
    private func textoCompensacion(_ comidas: [AjustePorciones.ComidaDelDia], _ ajustes: [String: AjusteComida]) -> String {
        let e = AjustePorciones.efecto(comidas, ajustes: ajustes, de: comidaId)
        guard !e.cambios.isEmpty else {
            return borrador.compensar ? "Lo que cambies acá se compensa ahí." : "El total del día queda con la diferencia."
        }
        let partes = e.cambios.map { c in
            "\(Self.conArticulo(c.nombre)) \(c.kcal < 0 ? "baja" : "sube") \(abs(c.kcal).enteroSeguro) kcal (queda en \(c.queda.enteroSeguro))"
        }
        var t = Self.mayuscula(Self.unir(partes)) + "."
        if abs(e.sinCompensar) >= 1 { t += " No alcanza: \(abs(e.sinCompensar).enteroSeguro) kcal quedan sin compensar." }
        return t
    }

    private func textoLlega(_ r: AjustePorciones.ComidaAjustada) -> String {
        let de = r.compensaDe.map(Self.conArticulo)
        return "\(r.absorbido < 0 ? "Baja" : "Sube") \(abs(r.absorbido).enteroSeguro) kcal por "
            + (de.isEmpty ? "la comida anterior" : Self.unir(de)) + "."
    }

    static func signo(_ x: Double) -> String { "\(x > 0 ? "+" : "−")\(abs(x).enteroSeguro)" }

    static func mayuscula(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// «a», «a y b», «a, b y c» (en castellano aunque el teléfono esté en otro idioma: la app es en castellano).
    static func unir(_ partes: [String]) -> String {
        guard partes.count > 1 else { return partes.first ?? "" }
        return partes.dropLast().joined(separator: ", ") + " y " + partes.last!
    }

    /// «al Almuerzo», «a la Merienda» (a + el = al).
    static func aLa(_ nombre: String) -> String {
        let c = conArticulo(nombre)
        return c.hasPrefix("el ") ? "al " + c.dropFirst(3) : "a " + c
    }

    /// «el Almuerzo», «la Merienda», «la Colación»: femenino si la primera palabra termina en «a» o en «ón».
    static func conArticulo(_ nombre: String) -> String {
        guard !nombre.isEmpty else { return "la comida siguiente" }
        let primera = nombre.lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? ""
        return (primera.hasSuffix("a") || primera.hasSuffix("ón") || primera.hasSuffix("on") ? "la " : "el ") + nombre
    }
}

/// Una macro de la comida: lo de hoy y cuánto se aparta del plan.
private struct MacroDelAjuste: View {
    let nombre: String
    let letra: String
    let hoy: Double
    let plan: Double
    let color: Color

    var body: some View {
        let d = (hoy - plan).rounded()
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(letra).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text("\(hoy.enteroSeguro) g").font(.caption.monospacedDigit().weight(.medium))
                .contentTransition(.numericText())
            if abs(d) >= 1 {
                Text(AjustarComidaView.signo(d)).font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(uiColor: .tertiarySystemFill).opacity(0.6), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(nombre): \(hoy.enteroSeguro) gramos" + (abs(d) >= 1 ? ", \(d > 0 ? "más" : "menos") \(abs(d).enteroSeguro) que el plan" : ""))
    }
}

/// − o + de un alimento: 44 pt de toque.
private struct BotonPaso: View {
    let icono: String
    let etiqueta: String
    let habilitado: Bool
    let accion: () -> Void

    var body: some View {
        Button { withAnimation(.snappy) { accion() } } label: {
            Image(systemName: icono)
                .font(.system(size: 13, weight: .bold))
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: .circle)
                .foregroundStyle(habilitado ? Color.primary : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .disabled(!habilitado)
        .accessibilityLabel(etiqueta)
    }
}
