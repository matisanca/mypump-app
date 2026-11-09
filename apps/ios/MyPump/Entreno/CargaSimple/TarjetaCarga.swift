import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// La carga única del ejercicio y sus series, en la lista de Entreno o en la página del ejercicio. Lo que se confirma va
/// en el panel fijo de abajo (`PanelCarga`). Las series hechas se tocan para corregirlas: no se desmarcan.
struct TarjetaCarga: View {
    let motor: ModeloEntreno
    let lugar: String
    let tarjeta: ModeloEntreno.Tarjeta
    var enLista = false
    @FocusState private var enCarga: Bool
    @FocusState private var kgFila: Int?
    @State private var textoCarga = ""
    @State private var kgTextos: [Int: String] = [:]

    var body: some View {
        if let s = motor.cargaSimple(lugar) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                AvisoRecordVista(motor: motor, lugar: lugar)
                if let v = tarjeta.variantes { selector(v) }
                if !s.sinKg { tarjetaCarga(s) }
                listaSeries(s)
            }
            .modifier(SuperficieCarga(enLista: enLista))
            .sensoryFeedback(.success, trigger: s.confirmadas) { a, b in b > a }
            .onAppear { textoCarga = KgTexto.de(s.carga) }
            .onChange(of: s.carga) { _, c in if !enCarga { textoCarga = KgTexto.de(c) } }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { enCarga = false; kgFila = nil }.fontWeight(.semibold).accessibilityIdentifier("teclado-listo")
                }
            }
        }
    }

    private func selector(_ v: VariantesEjercicio) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(v.etiqueta).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(v.etiqueta, selection: Binding(get: { tarjeta.varianteActual ?? v.opciones.first ?? "" },
                                                  set: { motor.elegirVariante(lugar, $0) })) {
                ForEach(v.opciones, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(motor.dia.diaFinalizado)
        }
    }

    // MARK: Carga

    private func tarjetaCarga(_ s: CargaSimple) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Carga").textoCeja().accessibilityAddTraits(.isHeader)
                Spacer()
                if let c = s.cargaUltimaVez { Text("La vez pasada \(KgTexto.de(c)) kg").font(.caption).foregroundStyle(.secondary) }
            }
            if s.mismoPeso {
                HStack(spacing: Espacio.s) {
                    botonCarga("minus", "Bajar la carga", id: "carga-menos", pasos: -1, s)
                    campoCarga(s)
                    botonCarga("plus", "Subir la carga", id: "carga-mas", pasos: 1, s)
                }
            } else {
                Text("Cada serie lleva su peso: ajustalo en la lista.").font(.footnote).foregroundStyle(.secondary)
            }
            bannerAumento(s)
            if s.hechasConOtraCarga > 0 { bannerHechas(s) }
            if s.ultimaVezMixta && s.mismoPeso && s.confirmadas == 0 {
                Text("La vez pasada una serie fue con otro peso. Si querés repetirlo, destildá abajo.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Mismo peso en todas las series", isOn: Binding(get: { s.mismoPeso }, set: { nuevo in motor.cambiarCarga(lugar) { $0.usarMismoPeso(nuevo) } }))
                .font(.subheadline.weight(.medium))
                .tint(Color.marca)
                .accessibilityIdentifier("toggle-mismo-peso")
        }
    }

    private func botonCarga(_ icono: String, _ etiqueta: String, id: String, pasos: Int, _ s: CargaSimple) -> some View {
        Button {
            enCarga = false
            motor.cambiarCarga(lugar) { $0.moverCarga(pasos) }
        } label: {
            Image(systemName: icono).font(.system(size: 18, weight: .bold)).frame(width: 48, height: 48).background(Color.campo, in: .circle).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(s.carga == nil)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }

    private func campoCarga(_ s: CargaSimple) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("—", text: $textoCarga)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.numeroGrande)
                .monospacedDigit()
                .focused($enCarga)
                .fixedSize()
                .frame(minWidth: 96, alignment: .trailing)
                .accessibilityLabel("Carga en kilos")
                .accessibilityIdentifier("carga-valor")
                .onChange(of: textoCarga) { _, t in
                    guard enCarga else { return }
                    let n = CamposSerie.normalizar("kg", t)
                    motor.cambiarCarga(lugar) { $0.fijarCarga(n.isEmpty ? nil : Double(n)) }
                }
                .onChange(of: enCarga) { _, ahora in
                    if ahora { KgTexto.seleccionarTodo() } else { textoCarga = KgTexto.de(motor.cargaSimple(lugar)?.carga) }
                }
            Text("kg").font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .contentShape(.rect)
        .onTapGesture { if !enCarga { enCarga = true } }
    }

    @ViewBuilder private func bannerAumento(_ s: CargaSimple) -> some View {
        switch s.aumento {
        case let .sugerido(desde, hasta):
            VStack(alignment: .leading, spacing: Espacio.xs) {
                Label("Esta semana bajan las reps: toca subir", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto).labelStyle(EtiquetaCompacta())
                HStack(spacing: Espacio.xs) {
                    Button { motor.cambiarCarga(lugar) { $0.aceptarAumento() } } label: { Text("Subir a \(KgTexto.de(hasta)) kg").frame(maxWidth: .infinity) }
                        .buttonStyle(BotonMarca(compacto: true))
                        .accessibilityIdentifier("aumento-subir")
                    Button { motor.cambiarCarga(lugar) { $0.descartarAumento() } } label: { Text("Dejar \(KgTexto.de(desde)) kg").frame(maxWidth: .infinity) }
                        .buttonStyle(BotonSecundario(compacto: true))
                        .accessibilityIdentifier("aumento-dejar")
                }
            }
            .padding(Espacio.s)
            .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control, style: .continuous))
        case let .aceptado(desde, hasta):
            HStack {
                Label(s.confirmadas > 0 ? "Subiste a \(KgTexto.de(hasta)) kg en las que faltan" : "Subiste a \(KgTexto.de(hasta)) kg en todas las series", systemImage: "checkmark")
                    .font(.footnote).labelStyle(EtiquetaCompacta())
                Spacer()
                if s.confirmadas == 0 {
                    Button("Volver a \(KgTexto.de(desde))") { motor.cambiarCarga(lugar) { $0.deshacerAumento() } }
                        .font(.footnote.weight(.semibold)).accessibilityIdentifier("aumento-volver")
                }
            }
        default: EmptyView()
        }
    }

    private func bannerHechas(_ s: CargaSimple) -> some View {
        let n = s.hechasConOtraCarga
        return HStack(alignment: .firstTextBaseline) {
            Text(n == 1 ? "La serie hecha sigue con su peso." : "Las \(n) hechas siguen con su peso.").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: Espacio.xs)
            Button("Cambiarlas también") { Task { await motor.aplicarCargaALasHechas(lugar) } }.font(.footnote.weight(.semibold)).accessibilityIdentifier("aplicar-a-hechas")
        }
    }

    // MARK: Lista

    private func listaSeries(_ s: CargaSimple) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            HStack {
                Text(motor.preparacion(lugar).isEmpty ? "Series" : "Series efectivas").font(enLista ? .headline : .title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(s.confirmadas) de \(s.series.count)").font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(s.confirmadas == s.series.count ? Color.marcaTexto : Color.secondary)
                    .contentTransition(.numericText())
            }
            if let leyenda = motor.leyendaRIR(lugar) {
                Text(leyenda).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("leyenda-rir")
            }
            if let i = s.activa, let c = tarjeta.filas[safe: i]?.calibracion {
                Label(Bonito.sinEmoji(c), systemImage: "scope").labelStyle(IconoTeñido(color: .marcaTexto)).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(s.series.indices, id: \.self) { fila($0, s).id("fila-\($0)") }
        }
    }

    private func fila(_ i: Int, _ s: CargaSimple) -> some View {
        let h = s.series[i]
        let enCorreccion = motor.corrigiendo?.lugar == lugar && motor.corrigiendo?.indice == i
        let activa = s.activa == i && motor.corrigiendo?.lugar != lugar
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
                    kgPorSerie(i, s)
                } else {
                    Text(h.kg.map { "\(KgTexto.de($0)) kg" } ?? "—")
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
        .onTapGesture { if h.confirmada { Task { await motor.editarSerie(lugar, i) } } }
        .accessibilityElement(children: h.confirmada || s.mismoPeso ? .ignore : .contain)
        .accessibilityLabel(etiquetaFila(i, s))
        .accessibilityAddTraits(h.confirmada ? .isButton : [])
        .accessibilityIdentifier("fila-serie-\(i + 1)")
    }

    private func etiquetaFila(_ i: Int, _ s: CargaSimple) -> String {
        let h = s.series[i]
        let kg = s.sinKg ? "" : ", \(KgTexto.de(h.kg)) kilos"
        return h.confirmada ? "Serie \(i + 1), hecha: \(s.reps(i) ?? 0) repeticiones\(kg). Tocá para corregirla"
                            : "Serie \(i + 1), pendiente: \(s.reps(i).map(String.init) ?? "sin dato") repeticiones\(kg)"
    }

    private func kgPorSerie(_ i: Int, _ s: CargaSimple) -> some View {
        HStack(spacing: 4) {
            Button { motor.cambiarCarga(lugar) { $0.moverKg(i, pasos: -1) } } label: { Image(systemName: "minus.circle.fill").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Bajar el peso de la serie \(i + 1)").accessibilityIdentifier("kg-menos-\(i + 1)")
            TextField("—", text: Binding(get: { kgFila == i ? (kgTextos[i] ?? "") : KgTexto.de(s.series[i].kg) },
                                         set: { t in kgTextos[i] = t; let n = CamposSerie.normalizar("kg", t); motor.cambiarCarga(lugar) { $0.fijarKg(i, n.isEmpty ? nil : Double(n)) } }))
                .keyboardType(.decimalPad).multilineTextAlignment(.center).font(.body.weight(.semibold).monospacedDigit())
                .focused($kgFila, equals: i).frame(minWidth: 52, minHeight: 40).background(Color.campo, in: .rect(cornerRadius: 8))
                .accessibilityLabel("Peso de la serie \(i + 1) en kilos").accessibilityIdentifier("kg-serie-\(i + 1)")
                .onChange(of: kgFila) { _, f in if f == i { kgTextos[i] = KgTexto.de(s.series[i].kg) } }
            Button { motor.cambiarCarga(lugar) { $0.moverKg(i, pasos: 1) } } label: { Image(systemName: "plus.circle.fill").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Subir el peso de la serie \(i + 1)").accessibilityIdentifier("kg-mas-\(i + 1)")
        }
    }
}

enum KgTexto {
    static func de(_ v: Double?) -> String { v.map { JS.texto($0).replacingOccurrences(of: ".", with: ",") } ?? "" }

    /// Como la web (`select()` al enfocar): al corregir, lo que se escribe reemplaza lo anterior.
    static func seleccionarTodo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }
}

/// En su tarjeta (la página del ejercicio) o suelta, con su margen, adentro de la tarjeta del bloque.
private struct SuperficieCarga: ViewModifier {
    let enLista: Bool
    func body(content: Content) -> some View {
        if enLista {
            content.padding(.horizontal, Espacio.m).padding(.vertical, Espacio.s)
        } else {
            content.tarjeta()
        }
    }
}
