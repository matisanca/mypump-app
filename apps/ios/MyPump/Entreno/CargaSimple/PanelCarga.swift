import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// El panel fijo arriba de las pestañas: la serie que toca, el dial y el OK. Va fuera de la lista que se desplaza, así
/// deslizar el dial nunca mueve la pantalla y desplazar la pantalla nunca cambia las reps. Absorbe la barra del descanso.
struct PanelCarga: View {
    let motor: ModeloEntreno
    let lugar: String
    @Environment(Preguntador.self) private var preguntador
    @Environment(Entrenamiento.self) private var entrenamiento
    @State private var teclado = false
    @State private var aviso: String?
    @State private var repsCorreccion = 0
    @State private var kgCorreccion: Double?
    @State private var textoCorreccion = ""
    @State private var cargaConfirmada = 0
    @State private var selloVisible = false
    @FocusState private var enCorreccionKg: Bool
    @Environment(\.accessibilityReduceMotion) private var reducir
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        Group {
            // Con el teclado arriba se esconde: si no, en un teléfono chico tapa el campo y se podría dar OK sin verlo.
            if !teclado, let s = motor.cargaSimple(lugar), debeVerse(s) {
                contenido(s)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Espacio.m + 2)
                    .padding(.top, Espacio.s)
                    .padding(.bottom, Espacio.xs)
                    .frame(maxWidth: .infinity)
                    .background { SuperficiePanelCarga() }
                    .overlay(alignment: .top) { filaDeshacer.alignmentGuide(.top) { $0[.bottom] + Espacio.s } }
                    .sensoryFeedback(.success, trigger: cargaConfirmada)
                    .sensoryFeedback(trigger: motor.guardia.desde) { _, nueva in nueva != nil ? .warning : nil }
                    .onAppear { entrenamiento.panelesCarga += 1 }
                    .onDisappear { entrenamiento.panelesCarga -= 1 }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in teclado = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in teclado = false }
    }

    private func debeVerse(_ s: CargaSimple) -> Bool {
        if motor.corrigiendo?.lugar == lugar || motor.deshacible != nil { return true }
        return !s.completo && !EstadosEjercicio.terminales.contains(motor.dia.estado(lugar))
    }

    @ViewBuilder private func contenido(_ s: CargaSimple) -> some View {
        Group {
            if let c = motor.corrigiendo, c.lugar == lugar, c.indice < s.series.count {
                correccion(c.indice, s)
            } else if let i = s.activa, !EstadosEjercicio.terminales.contains(motor.dia.estado(lugar)) {
                activa(i, s)
            } else {
                terminado
            }
        }
        .animation(reducir ? nil : EstiloCarga.resorte, value: s.completo)
    }

    private func activa(_ i: Int, _ s: CargaSimple) -> some View {
        let reps = s.reps(i)
        let kg = s.series[i].kg
        let enGuardia = motor.guardia.serie == i && motor.guardia.desde != nil
        return VStack(spacing: Espacio.xs) {
            ProgresoSeries(total: s.series.count, hechas: s.confirmadas, actual: i)
            // Con letra de accesibilidad, el descanso va abajo del título: al lado partía las palabras.
            let cabecera = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xxs))
                                                     : AnyLayout(HStackLayout(spacing: Espacio.xs))
            cabecera {
                // El récord entra en el renglón del título: la tarjeta puede estar fuera de vista y el panel no cambia de alto.
                if let a = motor.avisoRecord, a.lugar == lugar {
                    Label(a.texto, systemImage: "trophy.fill").labelStyle(EtiquetaCompacta()).font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.record).accessibilityIdentifier("aviso-record-panel")
                } else {
                    Text("Serie \(i + 1) de \(s.series.count)")
                        .font(Archivo.fuente(15, peso: 700, relativoA: .subheadline))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .animation(EstiloCarga.resorte, value: i)
                        .accessibilityAddTraits(.isHeader)
                }
                if !letra.isAccessibilitySize { Spacer() }
                DescansoChip(motor: motor)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            DialReps(reps: reps, diferencia: s.diferencia(i), referencia: textoReferencia(i, s), clave: i) { d in
                aviso = nil
                motor.cambiarCarga(lugar) { $0.ajustarReps(i, d) }
                motor.limpiarGuardia()
            }
            Button { confirmar(i) } label: { etiquetaOK(reps: reps, kg: kg, i: i, s, enGuardia: enGuardia) }
                .buttonStyle(BotonConfirmar(alerta: enGuardia))
                .disabled(!s.puedeConfirmar(i))
                .overlay { sello }
                .accessibilityIdentifier("ok-serie")
                .accessibilityLabel(etiquetaAccesibleOK(reps: reps, kg: kg, i: i, s, enGuardia: enGuardia))
            if let t = aviso ?? motor.dia.ejercicios[lugar]?.series[safe: i]?.aviso, !t.isEmpty {
                Label(t, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.peligro)
            }
        }
        .task(id: motor.guardia.desde) {
            guard motor.guardia.desde != nil else { return }
            try? await Task.sleep(for: .milliseconds(Int(GuardiaOK.venceEn)))
            motor.limpiarGuardia()
        }
    }

    private func confirmar(_ i: Int) {
        Task {
            aviso = nil
            let r = await motor.okSerie(lugar, i, venceEn: UIAccessibility.isVoiceOverRunning ? nil : 6) { await preguntador.preguntar($0) }
            if r == .registrada {
                cargaConfirmada += 1
                sellar()
            }
            if r == .faltanDatos { aviso = "Faltan datos para registrar esta serie." }
        }
    }

    /// Medio segundo de tilde sobre el botón: la serie quedó anotada, sin tapar nada ni frenar el próximo toque.
    private func sellar() {
        guard !reducir else { return }
        withAnimation(.snappy(duration: 0.18)) { selloVisible = true }
        Task {
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(.snappy(duration: 0.22)) { selloVisible = false }
        }
    }

    @ViewBuilder private var sello: some View {
        if selloVisible {
            ZStack {
                Capsule().fill(Color.marca)
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(Color.sobreMarca)
                    .symbolEffect(.bounce, value: selloVisible)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    private func textoReferencia(_ i: Int, _ s: CargaSimple) -> String? {
        let b = s.base(i)
        switch b.origen {
        case .ultimaVez: return b.reps.map { "La vez pasada: \($0)" }
        case .plan: return "Según el plan: \(s.repsPlan ?? "—")"
        case .ninguno: return s.pideElegirReps ? "Marcá las que hiciste" : nil
        }
    }

    @ViewBuilder private func etiquetaOK(reps: Int?, kg: Double?, i: Int, _ s: CargaSimple, enGuardia: Bool) -> some View {
        if enGuardia {
            Text("¿Ya hiciste la serie? Tocá de nuevo").font(.headline).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else if s.pideElegirReps && !s.series[i].tocada {
            Text("Marcá tus reps").font(.headline).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else if !s.sinKg && kg == nil {
            Text("Elegí la carga").font(.headline).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("OK").font(Archivo.fuente(22, peso: 900, relativoA: .title3))
                Text(s.sinKg ? "\(reps ?? 0) reps" : "\(reps ?? 0) × \(KgTexto.de(kg)) kg")
                    .font(Archivo.fuente(20, peso: 700, relativoA: .headline))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: reps)
            }
            .frame(maxWidth: .infinity)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private func etiquetaAccesibleOK(reps: Int?, kg: Double?, i: Int, _ s: CargaSimple, enGuardia: Bool) -> String {
        if enGuardia { return "¿Ya hiciste la serie? Tocá de nuevo para registrarla" }
        guard s.puedeConfirmar(i) else { return "Falta completar la serie" }
        return s.sinKg ? "OK, registrar \(reps ?? 0) repeticiones" : "OK, registrar \(reps ?? 0) repeticiones con \(KgTexto.de(kg)) kilos"
    }

    /// Flota arriba del panel: no le cambia el alto (el dial no se mueve bajo el dedo) ni guarda un renglón vacío.
    @ViewBuilder private var filaDeshacer: some View {
        Group {
            if let d = motor.deshacible {
                HStack(spacing: Espacio.xs) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                    Text("Serie \(d.indice + 1) anotada.").font(.subheadline.weight(.medium))
                    Button("Deshacer") { motor.deshacerOK() }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.marcaTexto)
                        .fixedSize()
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityIdentifier("deshacer-ok")
                }
                .padding(.horizontal, Espacio.m)
                .frame(minHeight: 44)
                .vidrio()
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reducir ? nil : EstiloCarga.resorte, value: motor.deshacible?.indice)
    }

    private func correccion(_ i: Int, _ s: CargaSimple) -> some View {
        VStack(spacing: Espacio.xs) {
            HStack {
                Text("Corrigiendo la serie \(i + 1)").font(Archivo.fuente(15, peso: 700, relativoA: .subheadline)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancelar") { motor.cancelarCorreccion() }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("correccion-cancelar")
            }
            DialReps(reps: repsCorreccion, diferencia: nil, referencia: "Solo cambia esta serie", clave: i) { d in
                repsCorreccion = min(Int(Verosimilitud.repsMax), max(1, repsCorreccion + d))
            }
            if !s.sinKg { kgCorreccionFila(s) }
            if let t = aviso { Label(t, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.peligro) }
            Button {
                enCorreccionKg = false
                Task {
                    switch await motor.guardarCorreccion(reps: repsCorreccion, kg: kgCorreccion, preguntar: { await preguntador.preguntar($0) }) {
                    case .rechazada(let t): aviso = t
                    default: aviso = nil
                    }
                }
            } label: {
                Text("Guardar corrección").font(Archivo.fuente(19, peso: 800, relativoA: .headline))
            }
            .buttonStyle(BotonConfirmar())
            .accessibilityIdentifier("correccion-guardar")
        }
        .onChange(of: i, initial: true) { _, _ in
            repsCorreccion = s.reps(i) ?? 1
            kgCorreccion = s.series[i].kg
            aviso = nil
        }
    }

    private func kgCorreccionFila(_ s: CargaSimple) -> some View {
        HStack(spacing: Espacio.s) {
            Button { if let k = kgCorreccion { kgCorreccion = AumentoCarga.mover(k, pasos: -1, equipo: s.equipo) } } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(BotonCircularCarga(lado: 44, tamañoIcono: 16)).foregroundStyle(.primary).accessibilityLabel("Bajar el peso").accessibilityIdentifier("correccion-kg-menos")
            TextField("—", text: Binding(get: { enCorreccionKg ? textoCorreccion : KgTexto.de(kgCorreccion) },
                                         set: { t in textoCorreccion = t; let n = CamposSerie.normalizar("kg", t); kgCorreccion = n.isEmpty ? nil : Double(n) }))
                .keyboardType(.decimalPad).multilineTextAlignment(.center).font(Archivo.fuente(24, peso: 800, relativoA: .title3).monospacedDigit())
                .focused($enCorreccionKg).frame(width: 96, height: 44)
                .accessibilityLabel("Peso de la serie en kilos").accessibilityIdentifier("correccion-kg")
                .onChange(of: enCorreccionKg) { _, f in if f { textoCorreccion = KgTexto.de(kgCorreccion) } }
            Button { if let k = kgCorreccion { kgCorreccion = AumentoCarga.mover(k, pasos: 1, equipo: s.equipo) } } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(BotonCircularCarga(lado: 44, tamañoIcono: 16)).foregroundStyle(.primary).accessibilityLabel("Subir el peso").accessibilityIdentifier("correccion-kg-mas")
        }
    }

    private var terminado: some View {
        VStack(spacing: Espacio.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.sobreMarca, Color.marca)
                .symbolEffect(.bounce, value: cargaConfirmada)
                .accessibilityHidden(true)
            Text("Ejercicio completo").font(Archivo.fuente(20, peso: 800, relativoA: .title3))
                .accessibilityIdentifier("ejercicio-completo")
            Text("Tocá una serie si querés corregirla.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espacio.xs)
    }
}

/// El descanso en el panel: aparte, para que lo que cambia 4 veces por segundo solo redibuje esto.
private struct DescansoChip: View {
    let motor: ModeloEntreno

    var body: some View {
        if motor.descanso.visible {
            HStack(spacing: Espacio.xs) {
                Text(motor.descanso.listo ? "A la serie" : "Descanso \(motor.descanso.texto)")
                    .font(Archivo.fuente(14, peso: 700, relativoA: .footnote).monospacedDigit())
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(countsDown: true))
                    .foregroundStyle(motor.descanso.listo ? Color.marcaTexto : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(motor.descanso.listo ? Color.marcaSuave : Color.campo, in: .capsule)
                if !motor.descanso.listo {
                    Button("Saltar") { motor.saltarDescanso() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .fixedSize()
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityIdentifier("saltar-descanso")
                }
            }
        }
    }
}
