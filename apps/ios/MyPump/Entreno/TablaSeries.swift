import SwiftUI
import MyPumpModelos
import MyPumpReglas

/// La tabla de series: campos grandes que invitan a cargar. Lo de la última vez aparece sugerido en gris; un toque
/// en ✓ lo registra (SER-01), el kg se hereda de la serie anterior (SER-03), el RIR nunca se completa solo (SER-02) y
/// tocar ✓ de nuevo desconfirma (SER-06). Al confirmar arranca el descanso, salvo en calentamiento y cardio.
struct TablaSeries: View {
    let ejercicio: Ejercicio
    let pauta: Pauta
    let resumen: ResumenHistorial?
    @Environment(SesionEnCurso.self) private var sesion
    @Environment(Descanso.self) private var descanso
    @FocusState private var foco: Campo?
    @State private var aviso = 0
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    enum Campo: Hashable { case reps(Int), kg(Int) }

    private var cantidad: Int { max(pauta.series ?? 3, 1) }
    private var esCalentamiento: Bool { ejercicio.tipo == "calentamiento" || ejercicio.tipo == "cardio" }
    /// Sin columna de kg en calentamiento, cardio o si siempre se hizo con el peso del cuerpo (ENT-13).
    private var sinKg: Bool {
        if esCalentamiento { return true }
        guard let filas = resumen?.ultima, !filas.isEmpty else { return false }
        return filas.allSatisfy { ($0.pesoKg ?? 0) == 0 }
    }
    private var activa: Int? { (0..<cantidad).first { !sesion.valores(ejercicio.id, serie: $0).confirmada } }

    var body: some View {
        let hechas = sesion.confirmadas(ejercicio.id)
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Series").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(hechas) de \(cantidad)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(hechas == cantidad ? Color.marcaTexto : Color.secondary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: Espacio.xs) {
                Text(tamañoLetra.isAccessibilitySize ? "#" : "Serie").fixedSize().frame(width: 30, alignment: .center)
                Text("Reps").frame(maxWidth: .infinity)
                if !sinKg { Text("Kg").frame(maxWidth: .infinity) }
                Text("RIR").frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 1)
            }
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            VStack(spacing: Espacio.xs) {
                ForEach(0..<cantidad, id: \.self) { i in fila(i) }
            }

            Label(resumen == nil
                  ? "Primera vez: buscá un peso con el que llegues cerca del fallo."
                  : "Tocá ✓ para registrar lo de la última vez, o escribí lo que hiciste.",
                  systemImage: resumen == nil ? "scope" : "hand.tap")
                .labelStyle(EtiquetaCompacta())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .tarjeta()
        .sensoryFeedback(.warning, trigger: aviso)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }.fontWeight(.semibold)
            }
        }
    }

    // MARK: Fila

    private func fila(_ i: Int) -> some View {
        let v = sesion.valores(ejercicio.id, serie: i)
        let previa = resumen?.ultima.first { $0.serie == i + 1 }
        let esActiva = activa == i
        return HStack(spacing: Espacio.xs) {
            ZStack {
                Circle().fill(esActiva ? Color.marca : (v.confirmada ? Color.clear : Color.campo))
                Text("\(i + 1)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(esActiva ? Color.sobreMarca : (v.confirmada ? Color.marcaTexto : Color.secondary))
            }
            .frame(width: 30, height: 30)

            CampoSerie(texto: enlace(i, \.reps, filtro: Self.soloDigitos),
                       sugerencia: sugerenciaReps(i, previa: previa) ?? "–",
                       teclado: .numberPad, confirmada: v.confirmada, foco: $foco, campo: .reps(i))
                .accessibilityLabel("Repeticiones de la serie \(i + 1)")
            if !sinKg {
                CampoSerie(texto: enlace(i, \.kg, filtro: Self.decimal),
                           sugerencia: sugerenciaKg(i, previa: previa).map { $0.kg } ?? "–",
                           teclado: .decimalPad, confirmada: v.confirmada, foco: $foco, campo: .kg(i))
                    .accessibilityLabel("Kilos de la serie \(i + 1)")
            }
            SelectorRIR(rir: Binding(get: { sesion.valores(ejercicio.id, serie: i).rir }, set: { nuevo in
                var actual = sesion.valores(ejercicio.id, serie: i)
                actual.rir = nuevo
                sesion.guardar(actual, ejercicioId: ejercicio.id, serie: i)
            }), confirmada: v.confirmada)
            .accessibilityLabel("RIR de la serie \(i + 1)")

            Button { alternar(i, previa: previa) } label: {
                ZStack {
                    Circle()
                        .fill(v.confirmada ? Color.marca : Color.clear)
                        .overlay { Circle().strokeBorder(v.confirmada ? Color.clear : Color(uiColor: .tertiaryLabel), lineWidth: 2) }
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(v.confirmada ? Color.sobreMarca : Color(uiColor: .tertiaryLabel))
                        .symbolEffect(.bounce, value: v.confirmada)
                }
                .frame(width: 34, height: 34)
                .frame(width: 44, height: 48)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: v.confirmada) { _, nuevo in nuevo }
            .accessibilityLabel(v.confirmada ? "Serie \(i + 1) hecha. Tocá para corregirla" : "Confirmar serie \(i + 1)")
        }
        .padding(.vertical, 2)
        .animation(.snappy(duration: 0.25), value: v.confirmada)
    }

    private func enlace(_ i: Int, _ campo: WritableKeyPath<SesionEnCurso.ValoresSerie, String>,
                        filtro: @escaping (String) -> String) -> Binding<String> {
        Binding(
            get: { sesion.valores(ejercicio.id, serie: i)[keyPath: campo] },
            set: { nuevo in
                var v = sesion.valores(ejercicio.id, serie: i)
                v[keyPath: campo] = filtro(nuevo)
                sesion.guardar(v, ejercicioId: ejercicio.id, serie: i)
            })
    }

    // MARK: Lógica del boceto (al cablear, va a MyPumpReglas con vectores)

    private func alternar(_ i: Int, previa: RegistroHistorico?) {
        var v = sesion.valores(ejercicio.id, serie: i)
        if v.confirmada {
            v.confirmada = false
            sesion.guardar(v, ejercicioId: ejercicio.id, serie: i)
            return
        }
        if v.reps.isEmpty, let s = sugerenciaReps(i, previa: previa) { v.reps = s }
        if !sinKg, v.kg.isEmpty, let kg = sugerenciaKg(i, previa: previa) { v.kg = kg.kg }
        // AMRAP, ∞ o máx: no hay registro de un toque (SER-01). Sin kg sugerido, también hay que escribirlo.
        guard !v.reps.isEmpty else { foco = .reps(i); aviso += 1; return }
        guard sinKg || !v.kg.isEmpty else { foco = .kg(i); aviso += 1; return }
        v.confirmada = true
        foco = nil
        sesion.guardar(v, ejercicioId: ejercicio.id, serie: i)
        if !esCalentamiento {
            descanso.empezar(segundos: ejercicio.descansoSegundos, ejercicio: ejercicio.nombre)
        }
    }

    /// Las reps de la última vez en esa serie; si no hay, el tope del rango ("8-10" → 10).
    private func sugerenciaReps(_ i: Int, previa: RegistroHistorico?) -> String? {
        if let r = previa?.reps { return String(r) }
        let numeros = (pauta.reps ?? "").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        return numeros.max().map(String.init)
    }

    /// El kg de la última vez en esa serie; si no, el de la serie anterior ya confirmada hoy.
    private func sugerenciaKg(_ i: Int, previa: RegistroHistorico?) -> Double? {
        if let kg = previa?.pesoKg, kg > 0 { return kg }
        for j in stride(from: i - 1, through: 0, by: -1) {
            let v = sesion.valores(ejercicio.id, serie: j)
            if v.confirmada, let kg = Double(v.kg.replacingOccurrences(of: ",", with: ".")) { return kg }
        }
        return nil
    }

    static func soloDigitos(_ s: String) -> String { String(s.filter(\.isNumber).prefix(3)) }

    static func decimal(_ s: String) -> String {
        var salida = "", separador = false
        for c in s {
            if c.isNumber { salida.append(c) } else if (c == "," || c == "."), !separador { salida.append(","); separador = true }
        }
        return String(salida.prefix(6))
    }
}

/// Un campo de la tabla: grande, centrado, con la sugerencia en gris y teñido de marca cuando la serie está hecha.
private struct CampoSerie: View {
    @Binding var texto: String
    let sugerencia: String
    let teclado: UIKeyboardType
    let confirmada: Bool
    var foco: FocusState<TablaSeries.Campo?>.Binding
    let campo: TablaSeries.Campo

    var body: some View {
        let enfocado = foco.wrappedValue == campo
        TextField(sugerencia, text: $texto)
            .focused(foco, equals: campo)
            .keyboardType(teclado)
            .multilineTextAlignment(.center)
            .font(.title3.weight(.semibold).monospacedDigit())
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(confirmada ? Color.marcaSuave : Color.campo, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.marcaVivo, lineWidth: enfocado ? 2 : 0)
            }
            .disabled(confirmada)
    }
}

/// RIR 0-5 en un menú (nunca se completa solo). "–" = sin dato, que no es lo mismo que 0.
private struct SelectorRIR: View {
    @Binding var rir: Int?
    let confirmada: Bool

    var body: some View {
        Menu {
            Picker("RIR", selection: $rir) {
                Text("Sin dato").tag(Int?.none)
                ForEach(0...5, id: \.self) { n in
                    Text(n == 0 ? "0 · al fallo" : "\(n)").tag(Int?.some(n))
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(rir.map(String.init) ?? "–")
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rir == nil ? Color.secondary : Color.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(confirmada ? Color.marcaSuave : Color.campo, in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .menuIndicator(.hidden)
        .sensoryFeedback(.selection, trigger: rir)
    }
}
