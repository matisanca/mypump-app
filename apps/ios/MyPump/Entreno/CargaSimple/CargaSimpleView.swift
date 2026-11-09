#if DEBUG
import SwiftUI
import MyPumpModelos
import MyPumpReglas

/// El prototipo de la pantalla de ejercicio: una carga por ejercicio, arriba; las series como lista corta; y abajo, fijo y
/// al alcance del pulgar, el dock con el dial de la serie que toca y el OK.
struct CargaSimpleView: View {
    @State var modelo: PrototipoCarga
    @FocusState private var enCarga: Bool
    @FocusState private var kgFila: Int?
    @FocusState private var enCorreccionKg: Bool
    @State private var textoCorreccion = ""
    @State private var textoCarga = ""
    @State private var verPayload = false
    @State private var kgTextos: [Int: String] = [:]
    @Environment(\.dynamicTypeSize) private var letra

    private var s: CargaSimple { modelo.s }
    private var e: EscenarioCarga { modelo.escenario }
    private var pauta: Pauta { Progresiones.pauta(e.ejercicio, semana: e.semana) }

    var body: some View {
        ScrollViewReader { lector in ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                encabezado
                if let v = e.variantes.keys.sorted().isEmpty ? nil : ["Prono", "Supino", "Neutro"] { selector(v) }
                if e.conPreparacion, !s.sinKg { preparacion }
                if !s.sinKg { tarjetaCarga }
                listaSeries
                if verPayload { payload }
            }
            .anchoLectura()
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.m)
        }
        .onChange(of: s.activa) { _, a in if let a { withAnimation(.snappy) { lector.scrollTo("fila-\(a)", anchor: .center) } } }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.fondo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { verPayload.toggle() } label: { Image(systemName: "curlybraces") }
                    .accessibilityLabel("Ver lo que se guardaría")
                    .accessibilityIdentifier("ver-payload")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { enCarga = false; kgFila = nil; enCorreccionKg = false }.fontWeight(.semibold).accessibilityIdentifier("teclado-listo")
            }
        }
        // Con el teclado arriba el dock se va: si no, en un teléfono chico el campo quedaría tapado y se podría dar OK sin verlo.
        .safeAreaInset(edge: .bottom, spacing: 0) { if !enCarga && kgFila == nil { dock } }
        .onAppear { textoCarga = Self.kg(s.carga) }
        .onChange(of: s.carga) { _, c in if !enCarga { textoCarga = Self.kg(c) } }
        .sensoryFeedback(.success, trigger: s.confirmadas) { a, b in b > a }
        .alert(modelo.pregunta?.titulo ?? "", isPresented: Binding(get: { modelo.pregunta != nil }, set: { if !$0 { modelo.pregunta = nil } })) {
            Button(modelo.pregunta?.confirmar ?? "Sí") { modelo.responderPregunta() }
            Button(modelo.pregunta?.cancelar ?? "No", role: .cancel) {}
        } message: { Text(modelo.pregunta?.cuerpo ?? "") }
    }

    static func kg(_ v: Double?) -> String { v.map { JS.texto($0).replacingOccurrences(of: ".", with: ",") } ?? "" }

    // MARK: Encabezado

    private var encabezado: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NombreEjercicio(e.ejercicio.nombre).principal).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
            if let o = e.sustituyeA {
                Label("En lugar de \(o)", systemImage: "arrow.left.arrow.right")
                    .font(.footnote).foregroundStyle(.secondary).labelStyle(EtiquetaCompacta())
            }
            Text("\(pauta.series ?? 0) × \(pauta.reps ?? "—") · Al fallo · \(TiempoEntreno.fmtTiempo(Double(e.ejercicio.descansoSegundos ?? 90)))")
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary).monospacedDigit()
            if let n = Progresiones.nota(e.ejercicio, semanaActual: e.semana), n.calibracion {
                Label("Semana de calibración: buscá el fallo y anotá lo que salga", systemImage: "scope")
                    .font(.footnote).foregroundStyle(.secondary).labelStyle(EtiquetaCompacta())
            }
        }
    }

    private func selector(_ v: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agarre").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Agarre", selection: Binding(get: { modelo.varianteActual ?? "" }, set: { modelo.elegirVariante($0) })) {
                ForEach(v, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    /// La preparación sigue siendo solo indicación: el kg se recalcula en vivo con la carga (el de `Preparacion`).
    private var preparacion: some View {
        let c = s.carga ?? 0
        let filas: [(String, String)] = [("Aproximación 1", "5 × \(Self.kg(Preparacion.redondear(c * 0.6, equipo: s.equipo) ?? c * 0.6)) kg"),
                                         ("Aproximación 2", "5 × \(Self.kg(Preparacion.redondear(c * 0.85, equipo: s.equipo) ?? c * 0.85)) kg")]
        return VStack(alignment: .leading, spacing: 4) {
            Text("Aproximación · no se anota").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            ForEach(filas, id: \.0) { f in
                HStack { Text(f.0); Spacer(); Text(f.1).monospacedDigit() }.font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Espacio.s).padding(.vertical, Espacio.xs)
        .background(Color(uiColor: .quaternarySystemFill), in: .rect(cornerRadius: Radio.control, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bloque-preparacion")
    }

    // MARK: Carga

    private var tarjetaCarga: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Carga").textoCeja().accessibilityAddTraits(.isHeader)
                Spacer()
                if let c = s.cargaUltimaVez, let u = e.cuando { Text("La vez pasada \(Self.kg(c)) kg · \(u)").font(.caption).foregroundStyle(.secondary) }
            }
            if s.mismoPeso {
                HStack(spacing: Espacio.s) {
                    botonCarga("minus", "Bajar la carga", id: "carga-menos", pasos: -1)
                    campoCarga
                    botonCarga("plus", "Subir la carga", id: "carga-mas", pasos: 1)
                }
            } else {
                Text("Cada serie lleva su peso: ajustalo en la lista.").font(.footnote).foregroundStyle(.secondary)
            }
            bannerAumento
            if s.hechasConOtraCarga > 0 { bannerHechas }
            if s.ultimaVezMixta && s.mismoPeso && !s.series.contains(where: \.confirmada) {
                Text("La vez pasada una serie fue con otro peso. Si querés repetirlo, destildá abajo.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Mismo peso en todas las series", isOn: Binding(get: { s.mismoPeso }, set: { nuevo in modelo.cambiar { $0.usarMismoPeso(nuevo) } }))
                .font(.subheadline.weight(.medium))
                .tint(Color.marca)
                .accessibilityIdentifier("toggle-mismo-peso")
        }
        .tarjeta()
    }

    private func botonCarga(_ icono: String, _ etiqueta: String, id: String, pasos: Int) -> some View {
        Button {
            enCarga = false
            modelo.cambiar { $0.moverCarga(pasos) }
        } label: {
            Image(systemName: icono).font(.system(size: 18, weight: .bold)).frame(width: 48, height: 48).background(Color.campo, in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(s.carga == nil)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }

    private var campoCarga: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("—", text: $textoCarga)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.numeroGrande)
                .monospacedDigit()
                .focused($enCarga)
                .fixedSize()
                .accessibilityLabel("Carga en kilos")
                .accessibilityIdentifier("carga-valor")
                .onChange(of: textoCarga) { _, t in
                    guard enCarga else { return }
                    let n = CamposSerie.normalizar("kg", t)
                    modelo.cambiar { $0.fijarCarga(n.isEmpty ? nil : Double(n)) }
                }
                .onChange(of: enCarga) { _, ahora in
                    if ahora {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil) }
                    } else { textoCarga = Self.kg(s.carga) }
                }
            Text("kg").font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .contentShape(.rect)
        .onTapGesture { enCarga = true }
    }

    @ViewBuilder private var bannerAumento: some View {
        switch s.aumento {
        case let .sugerido(desde, hasta):
            VStack(alignment: .leading, spacing: Espacio.xs) {
                Label("Esta semana bajan las reps: toca subir", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto).labelStyle(EtiquetaCompacta())
                HStack(spacing: Espacio.xs) {
                    Button { modelo.cambiar { $0.aceptarAumento() } } label: { Text("Subir a \(Self.kg(hasta)) kg").frame(maxWidth: .infinity) }
                        .buttonStyle(BotonMarca(compacto: true))
                        .accessibilityIdentifier("aumento-subir")
                    Button { modelo.cambiar { $0.descartarAumento() } } label: { Text("Dejar \(Self.kg(desde)) kg").frame(maxWidth: .infinity) }
                        .buttonStyle(BotonSecundario(compacto: true))
                        .accessibilityIdentifier("aumento-dejar")
                }
            }
            .padding(Espacio.s)
            .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control, style: .continuous))
        case let .aceptado(desde, hasta):
            HStack {
                Label(s.series.contains(where: \.confirmada) ? "Subiste a \(Self.kg(hasta)) kg en las que faltan" : "Subiste a \(Self.kg(hasta)) kg en todas las series", systemImage: "checkmark").font(.footnote).labelStyle(EtiquetaCompacta())
                Spacer()
                if !s.series.contains(where: \.confirmada) {
                    Button("Volver a \(Self.kg(desde))") { modelo.cambiar { $0.deshacerAumento() } }
                        .font(.footnote.weight(.semibold)).accessibilityIdentifier("aumento-volver")
                }
            }
        default: EmptyView()
        }
    }

    private var bannerHechas: some View {
        let n = s.hechasConOtraCarga
        return HStack(alignment: .firstTextBaseline) {
            Text(n == 1 ? "La serie hecha sigue con su peso." : "Las \(n) hechas siguen con su peso.").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: Espacio.xs)
            Button("Cambiarlas también") { modelo.aplicarALasHechas() }.font(.footnote.weight(.semibold)).accessibilityIdentifier("aplicar-a-hechas")
        }
    }

    // MARK: Lista

    private var listaSeries: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            HStack {
                Text("Series").textoCeja().accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(s.confirmadas) de \(s.series.count)").font(.subheadline.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(s.series.indices, id: \.self) { fila($0).id("fila-\($0)") }
        }
        .tarjeta()
    }

    private func fila(_ i: Int) -> some View {
        let h = s.series[i]
        let activa = s.activa == i && modelo.corrigiendo == nil
        let enCorreccion = modelo.corrigiendo == i
        return HStack(spacing: Espacio.s) {
            ZStack {
                Circle().fill(h.confirmada ? Color.marca : (activa ? Color.marcaSuave : Color.campo))
                if h.confirmada { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color.sobreMarca) }
                else { Text("\(i + 1)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(activa ? Color.marcaTexto : Color.secondary) }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            Text(s.reps(i).map { "\($0) reps" } ?? "—")
                .font(.body.weight(activa || h.confirmada ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(h.confirmada || activa ? Color.primary : Color.secondary)
            Spacer(minLength: 4)
            if !s.sinKg {
                if !s.mismoPeso && !h.confirmada {
                    kgPorSerie(i)
                } else {
                    Text(h.kg.map { "\(Self.kg($0)) kg" } ?? "—")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(h.confirmada ? Color.primary : Color.secondary)
                }
            }
            if h.confirmada {
                Image(systemName: enCorreccion ? "pencil.circle.fill" : "pencil").font(.footnote).foregroundStyle(Color.secondary).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Espacio.xs)
        .background(activa ? Color.marcaSuave.opacity(0.6) : Color.clear, in: .rect(cornerRadius: 10, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { if h.confirmada { modelo.abrirCorreccion(i) } }
        .accessibilityElement(children: h.confirmada || s.mismoPeso ? .ignore : .contain)
        .accessibilityLabel(etiquetaFila(i))
        .accessibilityAddTraits(h.confirmada ? .isButton : [])
        .accessibilityIdentifier("fila-serie-\(i + 1)")
    }

    private func etiquetaFila(_ i: Int) -> String {
        let h = s.series[i]
        let kg = s.sinKg ? "" : ", \(Self.kg(h.kg)) kilos"
        return h.confirmada ? "Serie \(i + 1), hecha: \(s.reps(i) ?? 0) repeticiones\(kg). Tocá para corregirla"
                            : "Serie \(i + 1), pendiente: \(s.reps(i).map(String.init) ?? "sin dato") repeticiones\(kg)"
    }

    private func kgPorSerie(_ i: Int) -> some View {
        HStack(spacing: 4) {
            Button { modelo.cambiar { $0.moverKg(i, pasos: -1) } } label: { Image(systemName: "minus.circle.fill").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Bajar el peso de la serie \(i + 1)").accessibilityIdentifier("kg-menos-\(i + 1)")
            TextField("—", text: Binding(get: { kgFila == i ? (kgTextos[i] ?? "") : Self.kg(s.series[i].kg) },
                                         set: { t in kgTextos[i] = t; let n = CamposSerie.normalizar("kg", t); modelo.cambiar { $0.fijarKg(i, n.isEmpty ? nil : Double(n)) } }))
                .keyboardType(.decimalPad).multilineTextAlignment(.center).font(.body.weight(.semibold).monospacedDigit())
                .focused($kgFila, equals: i).frame(minWidth: 52, minHeight: 40).background(Color.campo, in: .rect(cornerRadius: 8))
                .accessibilityLabel("Peso de la serie \(i + 1) en kilos").accessibilityIdentifier("kg-serie-\(i + 1)")
                .onChange(of: kgFila) { _, f in if f == i { kgTextos[i] = Self.kg(s.series[i].kg) } }
            Button { modelo.cambiar { $0.moverKg(i, pasos: 1) } } label: { Image(systemName: "plus.circle.fill").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Subir el peso de la serie \(i + 1)").accessibilityIdentifier("kg-mas-\(i + 1)")
        }
    }

    // MARK: Dock

    private var dock: some View {
        VStack(spacing: Espacio.xs) {
            if let i = modelo.corrigiendo { correccion(i) }
            else if let i = s.activa { activa(i) }
            else { terminado }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, Espacio.m)
        .padding(.top, Espacio.s)
        .padding(.bottom, Espacio.xs)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func activa(_ i: Int) -> some View {
        let reps = s.reps(i)
        let kg = s.series[i].kg
        return VStack(spacing: Espacio.xs) {
            HStack {
                Text("Serie \(i + 1) de \(s.series.count)").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                descansoChip
            }
            DialReps(reps: reps, diferencia: s.diferencia(i), referencia: textoReferencia(i)) { d in
                modelo.aviso = nil
                modelo.cambiar { $0.ajustarReps(i, d) }
            }
            Button { modelo.confirmarActiva() } label: { etiquetaOK(reps: reps, kg: kg, i: i) }
                .buttonStyle(BotonMarca())
                .tint(modelo.enGuardia ? Color.alerta : nil)
                .disabled(!s.puedeConfirmar(i))
                .accessibilityIdentifier("ok-serie")
                .accessibilityLabel(etiquetaAccesibleOK(reps: reps, kg: kg, i: i))
            if let t = modelo.aviso { Label(t, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.peligro) }
            filaDeshacer
        }
    }

    private func textoReferencia(_ i: Int) -> String? {
        let b = s.base(i)
        switch b.origen {
        case .ultimaVez: return b.reps.map { "La vez pasada: \($0)" }
        case .plan: return "Según el plan: \(s.repsPlan ?? "—")"
        case .ninguno: return s.pideElegirReps ? "Marcá las que hiciste" : nil
        }
    }

    @ViewBuilder private func etiquetaOK(reps: Int?, kg: Double?, i: Int) -> some View {
        if modelo.enGuardia {
            Text("¿Ya hiciste la serie? Tocá de nuevo").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else if s.pideElegirReps && !s.series[i].tocada {
            Text("Marcá tus reps").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else if !s.sinKg && kg == nil {
            Text("Elegí la carga").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else {
            HStack(spacing: 8) {
                Text("OK").fontWeight(.heavy)
                Text(s.sinKg ? "\(reps ?? 0) reps" : "\(reps ?? 0) × \(Self.kg(kg)) kg").fontWeight(.semibold).monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func etiquetaAccesibleOK(reps: Int?, kg: Double?, i: Int) -> String {
        if modelo.enGuardia { return "¿Ya hiciste la serie? Tocá de nuevo para registrarla" }
        guard s.puedeConfirmar(i) else { return "Falta completar la serie" }
        return s.sinKg ? "OK, registrar \(reps ?? 0) repeticiones" : "OK, registrar \(reps ?? 0) repeticiones con \(Self.kg(kg)) kilos"
    }

    @ViewBuilder private var descansoChip: some View {
        if let fin = modelo.descansoFin {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let resto = max(0, Int(fin.timeIntervalSince(ctx.date).rounded(.up)))
                HStack(spacing: 6) {
                    Text(resto > 0 ? "Descanso \(TiempoEntreno.fmtTiempo(Double(resto)))" : "A la serie").font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(resto > 0 ? Color.secondary : Color.marcaTexto)
                    if resto > 0 {
                        Button("Saltar") { modelo.descansoFin = nil }.font(.footnote.weight(.semibold)).accessibilityIdentifier("saltar-descanso")
                    }
                }
            }
        } else {
            Text(s.calibracion ? "Calibración" : "Al fallo").font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Va siempre con su lugar reservado: si apareciera y desapareciera, el dock saltaría y el dial se movería bajo el dedo.
    private var filaDeshacer: some View {
        let i = modelo.deshacible
        return HStack(spacing: 6) {
            if let i {
                Text("Serie \(i + 1) anotada.").font(.footnote).foregroundStyle(.secondary)
                Button("Deshacer") { modelo.deshacerUltima() }.font(.footnote.weight(.semibold)).accessibilityIdentifier("deshacer-ok")
            } else {
                Text(" ").font(.footnote).accessibilityHidden(true)
            }
        }
        .task(id: i) {
            guard let i else { return }
                // Con VoiceOver no vence: 6 segundos no alcanzan para llegar al botón.
                guard !UIAccessibility.isVoiceOverRunning, (try? await Task.sleep(for: .seconds(6))) != nil else { return }
                if modelo.deshacible == i { modelo.deshacible = nil }
        }
    }

    private func correccion(_ i: Int) -> some View {
        VStack(spacing: Espacio.xs) {
            HStack {
                Text("Corrigiendo la serie \(i + 1)").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancelar") { modelo.corrigiendo = nil }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("correccion-cancelar")
            }
            DialReps(reps: modelo.repsCorreccion, diferencia: nil, referencia: "Solo cambia esta serie") { d in
                modelo.repsCorreccion = min(Int(Verosimilitud.repsMax), max(1, modelo.repsCorreccion + d))
            }
            if !s.sinKg {
                HStack(spacing: Espacio.s) {
                    Button { if let k = modelo.kgCorreccion { modelo.kgCorreccion = AumentoCarga.mover(k, pasos: -1, equipo: s.equipo) } } label: {
                        Image(systemName: "minus.circle.fill").font(.title2).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Bajar el peso").accessibilityIdentifier("correccion-kg-menos")
                    TextField("—", text: Binding(get: { enCorreccionKg ? textoCorreccion : Self.kg(modelo.kgCorreccion) },
                                                 set: { t in textoCorreccion = t; let n = CamposSerie.normalizar("kg", t); modelo.kgCorreccion = Double(n) }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.center).font(.title3.weight(.semibold).monospacedDigit())
                        .focused($enCorreccionKg).frame(width: 90, height: 44).background(Color.campo, in: .rect(cornerRadius: 10))
                        .accessibilityLabel("Peso de la serie en kilos").accessibilityIdentifier("correccion-kg")
                        .onChange(of: enCorreccionKg) { _, f in if f { textoCorreccion = Self.kg(modelo.kgCorreccion) } }
                    Button { if let k = modelo.kgCorreccion { modelo.kgCorreccion = AumentoCarga.mover(k, pasos: 1, equipo: s.equipo) } } label: {
                        Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Subir el peso").accessibilityIdentifier("correccion-kg-mas")
                }
            }
            if let t = modelo.aviso { Label(t, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.peligro) }
            Button("Guardar corrección") { enCorreccionKg = false; modelo.guardarCorreccion() }.buttonStyle(BotonMarca()).accessibilityIdentifier("correccion-guardar")
        }
    }

    private var terminado: some View {
        VStack(spacing: Espacio.xs) {
            Label("Ejercicio completo", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Color.marcaTexto)
                .labelStyle(EtiquetaCompacta()).accessibilityIdentifier("ejercicio-completo")
            Text("Tocá una serie si querés corregirla.").font(.footnote).foregroundStyle(.secondary)
            filaDeshacer
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espacio.s)
    }

    // MARK: Payload

    private var payload: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lo que se guardaría (registrar_carga) · \(modelo.escrituras) escrituras").textoCeja()
            if modelo.registros.isEmpty { Text("Nada todavía.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(modelo.registros.keys.sorted(), id: \.self) { k in
                Text(modelo.registros[k] ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .tarjeta()
        .accessibilityIdentifier("panel-payload")
    }
}

/// La lista de escenarios: «navegable» sin cuenta. `-cargaSimple menu` o `-cargaSimple <id>` para entrar directo.
struct CargaSimpleMenu: View {
    let inicial: EscenarioCarga?
    @State private var ruta: [EscenarioCarga] = []

    var body: some View {
        NavigationStack(path: $ruta) {
            List(EscenarioCarga.todos) { e in
                NavigationLink(value: e) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.titulo).font(.headline)
                        Text(e.detalle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("escenario-\(e.id)")
            }
            .navigationTitle("Prototipo de carga")
            .navigationDestination(for: EscenarioCarga.self) { CargaSimpleView(modelo: PrototipoCarga($0)) }
        }
        .onAppear { if let i = inicial, ruta.isEmpty { ruta = [i] } }
    }
}

enum DemoCarga {
    /// `-cargaSimple menu|<id>`: el prototipo en lugar de la app.
    static var activo: Bool { UserDefaults.standard.string(forKey: "cargaSimple") != nil }
    static var inicial: EscenarioCarga? {
        let id = UserDefaults.standard.string(forKey: "cargaSimple")
        return EscenarioCarga.todos.first { $0.id == id }
    }
}
#endif
