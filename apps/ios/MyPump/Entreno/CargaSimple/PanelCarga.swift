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
    @FocusState private var enCorreccionKg: Bool

    var body: some View {
        Group {
            // Con el teclado arriba se esconde: si no, en un teléfono chico tapa el campo y se podría dar OK sin verlo.
            if !teclado, let s = motor.cargaSimple(lugar), debeVerse(s) {
                contenido(s)
                    .frame(maxWidth: 560)
                    .padding(.horizontal, Espacio.m)
                    .padding(.top, Espacio.s)
                    .padding(.bottom, Espacio.xs)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
                    .overlay(alignment: .top) { Divider() }
                    .sensoryFeedback(.success, trigger: cargaConfirmada)
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
        VStack(spacing: Espacio.xs) {
            if let c = motor.corrigiendo, c.lugar == lugar, c.indice < s.series.count {
                correccion(c.indice, s)
            } else if let i = s.activa, !EstadosEjercicio.terminales.contains(motor.dia.estado(lugar)) {
                activa(i, s)
            } else {
                terminado
            }
            filaDeshacer
        }
    }

    private func activa(_ i: Int, _ s: CargaSimple) -> some View {
        let reps = s.reps(i)
        let kg = s.series[i].kg
        let enGuardia = motor.guardia.serie == i && motor.guardia.desde != nil
        return VStack(spacing: Espacio.xs) {
            HStack {
                Text("Serie \(i + 1) de \(s.series.count)").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                DescansoChip(motor: motor)
            }
            DialReps(reps: reps, diferencia: s.diferencia(i), referencia: textoReferencia(i, s)) { d in
                aviso = nil
                motor.cambiarCarga(lugar) { $0.ajustarReps(i, d) }
                motor.limpiarGuardia()
            }
            Button { confirmar(i) } label: { etiquetaOK(reps: reps, kg: kg, i: i, s, enGuardia: enGuardia) }
                .buttonStyle(BotonMarca())
                .tint(enGuardia ? Color.alerta : nil)
                .disabled(!s.puedeConfirmar(i))
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
            if r == .registrada { cargaConfirmada += 1 }
            if r == .faltanDatos { aviso = "Faltan datos para registrar esta serie." }
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
            Text("¿Ya hiciste la serie? Tocá de nuevo").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else if s.pideElegirReps && !s.series[i].tocada {
            Text("Marcá tus reps").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else if !s.sinKg && kg == nil {
            Text("Elegí la carga").frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.7)
        } else {
            HStack(spacing: 8) {
                Text("OK").fontWeight(.heavy)
                Text(s.sinKg ? "\(reps ?? 0) reps" : "\(reps ?? 0) × \(KgTexto.de(kg)) kg").fontWeight(.semibold).monospacedDigit()
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

    /// Reserva siempre su renglón: si apareciera y desapareciera, el panel saltaría y el dial se movería bajo el dedo.
    private var filaDeshacer: some View {
        HStack(spacing: 6) {
            if let d = motor.deshacible {
                Text("Serie \(d.indice + 1) anotada.").font(.footnote).foregroundStyle(.secondary)
                Button("Deshacer") { motor.deshacerOK() }.font(.footnote.weight(.semibold)).accessibilityIdentifier("deshacer-ok")
            } else {
                Text(" ").font(.footnote).accessibilityHidden(true)
            }
        }
    }

    private func correccion(_ i: Int, _ s: CargaSimple) -> some View {
        VStack(spacing: Espacio.xs) {
            HStack {
                Text("Corrigiendo la serie \(i + 1)").font(.subheadline.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Cancelar") { motor.cancelarCorreccion() }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("correccion-cancelar")
            }
            DialReps(reps: repsCorreccion, diferencia: nil, referencia: "Solo cambia esta serie") { d in
                repsCorreccion = min(Int(Verosimilitud.repsMax), max(1, repsCorreccion + d))
            }
            if !s.sinKg { kgCorreccionFila(s) }
            if let t = aviso { Label(t, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Color.peligro) }
            Button("Guardar corrección") {
                enCorreccionKg = false
                Task {
                    switch await motor.guardarCorreccion(reps: repsCorreccion, kg: kgCorreccion, preguntar: { await preguntador.preguntar($0) }) {
                    case .rechazada(let t): aviso = t
                    default: aviso = nil
                    }
                }
            }
            .buttonStyle(BotonMarca())
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
                Image(systemName: "minus.circle.fill").font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Bajar el peso").accessibilityIdentifier("correccion-kg-menos")
            TextField("—", text: Binding(get: { enCorreccionKg ? textoCorreccion : KgTexto.de(kgCorreccion) },
                                         set: { t in textoCorreccion = t; let n = CamposSerie.normalizar("kg", t); kgCorreccion = n.isEmpty ? nil : Double(n) }))
                .keyboardType(.decimalPad).multilineTextAlignment(.center).font(.title3.weight(.semibold).monospacedDigit())
                .focused($enCorreccionKg).frame(width: 90, height: 44).background(Color.campo, in: .rect(cornerRadius: 10))
                .accessibilityLabel("Peso de la serie en kilos").accessibilityIdentifier("correccion-kg")
                .onChange(of: enCorreccionKg) { _, f in if f { textoCorreccion = KgTexto.de(kgCorreccion) } }
            Button { if let k = kgCorreccion { kgCorreccion = AumentoCarga.mover(k, pasos: 1, equipo: s.equipo) } } label: {
                Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Subir el peso").accessibilityIdentifier("correccion-kg-mas")
        }
    }

    private var terminado: some View {
        VStack(spacing: Espacio.xs) {
            Label("Ejercicio completo", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Color.marcaTexto)
                .labelStyle(EtiquetaCompacta()).accessibilityIdentifier("ejercicio-completo")
            Text("Tocá una serie si querés corregirla.").font(.footnote).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espacio.s)
    }
}

/// El descanso en el panel: aparte, para que lo que cambia 4 veces por segundo solo redibuje esto.
private struct DescansoChip: View {
    let motor: ModeloEntreno

    var body: some View {
        if motor.descanso.visible {
            HStack(spacing: 6) {
                Text(motor.descanso.listo ? "A la serie" : "Descanso \(motor.descanso.texto)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(motor.descanso.listo ? Color.marcaTexto : Color.secondary)
                if !motor.descanso.listo {
                    Button("Saltar") { motor.saltarDescanso() }.font(.footnote.weight(.semibold)).accessibilityIdentifier("saltar-descanso")
                }
            }
        }
    }
}
