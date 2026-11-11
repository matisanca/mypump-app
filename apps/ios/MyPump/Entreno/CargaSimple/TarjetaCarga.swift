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
    /// Sube al aceptar el aumento: el número se enciende un momento y vibra una vez.
    @State private var pulsoCarga = 0
    @State private var encendido = false
    @State private var toquesCarga = 0
    @Environment(\.dynamicTypeSize) private var letra
    /// Crece con la letra: a tamaños de accesibilidad un 82,5 no entraba en el ancho fijo y salían puntos suspensivos.
    @ScaledMetric(relativeTo: .headline) private var anchoKgFila: CGFloat = 66
    @Environment(\.accessibilityReduceMotion) private var reducir

    var body: some View {
        if let s = motor.cargaSimple(lugar) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                AvisoRecordVista(motor: motor, lugar: lugar)
                if let v = tarjeta.variantes { selector(v) }
                if !s.sinKg { tarjetaCarga(s) }
                listaSeries(s)
            }
            .modifier(SuperficieCarga(enLista: enLista))
            .sensoryFeedback(.impact(weight: .medium), trigger: pulsoCarga)
            .sensoryFeedback(.selection, trigger: toquesCarga)
            .animation(reducir ? nil : EstiloCarga.resorte, value: s.aumento)
            .onAppear {
                textoCarga = KgTexto.de(s.carga)
                DemoUI.aplicarAumentoDePrueba(motor: motor, lugar: lugar, ejercicio: tarjeta.efectivo.ejercicio)
            }
            .onChange(of: s.carga) { _, c in
                if !enCarga { textoCarga = KgTexto.de(c) }
                DemoUI.aplicarAumentoDePrueba(motor: motor, lugar: lugar, ejercicio: tarjeta.efectivo.ejercicio)
            }
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
            if s.mismoPeso {
                let disposicion = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                                            : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.xs))
                disposicion {
                    resumenCarga(s)
                    if !letra.isAccessibilitySize { Spacer(minLength: 0) }
                    HStack(spacing: Espacio.xs + 2) {
                        botonCarga("minus", "Bajar la carga", id: "carga-menos", pasos: -1, s)
                        botonCarga("plus", "Subir la carga", id: "carga-mas", pasos: 1, s)
                    }
                }
            } else {
                Text("Carga").textoCeja().accessibilityAddTraits(.isHeader)
                Text("Cada serie lleva su peso: ajustalo en la lista.").font(.footnote).foregroundStyle(.secondary)
            }
            bannerAumento(s)
            if s.hechasConOtraCarga > 0 { bannerHechas(s) }
            if s.ultimaVezMixta && s.mismoPeso && s.confirmadas == 0 {
                Text("La vez pasada una serie fue con otro peso. Si querés repetirlo, destildá abajo.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Mismo peso en todas las series", isOn: Binding(get: { s.mismoPeso }, set: { nuevo in motor.cambiarCarga(lugar) { $0.usarMismoPeso(nuevo) } }))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .tint(Color.marca)
                .accessibilityIdentifier("toggle-mismo-peso")
        }
    }

    private func resumenCarga(_ s: CargaSimple) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Carga").textoCeja().accessibilityAddTraits(.isHeader)
            campoCarga(s)
            if let c = s.cargaUltimaVez { Text("La vez pasada \(KgTexto.de(c)) kg").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    private func botonCarga(_ icono: String, _ etiqueta: String, id: String, pasos: Int, _ s: CargaSimple) -> some View {
        Button {
            enCarga = false
            motor.cambiarCarga(lugar) { $0.moverCarga(pasos) }
            toquesCarga += 1
        } label: {
            Image(systemName: icono)
        }
        .buttonStyle(BotonCircularCarga(lado: 56, tamañoIcono: 20))
        .foregroundStyle(s.carga == nil ? Color.secondary : Color.primary)
        .disabled(s.carga == nil)
        .accessibilityLabel(etiqueta)
        .accessibilityIdentifier(id)
    }

    /// El número es un texto que anima y el campo va encima, transparente hasta que se lo toca: así el kilo crece como
    /// las reps y el «kg» queda pegado, escriba lo que escriba.
    private func campoCarga(_ s: CargaSimple) -> some View {
        let tamaño: CGFloat = textoCarga.count >= 5 ? 42 : textoCarga.count == 4 ? 48 : 54
        let fuente = Archivo.fuente(tamaño, peso: 900, relativoA: .largeTitle)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(textoCarga.isEmpty ? "—" : textoCarga)
                .font(fuente)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(encendido ? Color.marcaTexto : Color.primary)
                .scaleEffect(encendido ? 1.06 : 1, anchor: .leading)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.24), value: textoCarga)
                .opacity(enCarga && !textoCarga.isEmpty ? 0 : 1)
                .padding(.trailing, enCarga ? 10 : 0)
                .accessibilityHidden(true)
                .overlay(alignment: .leading) {
                    TextField("", text: $textoCarga)
                        .keyboardType(.decimalPad)
                        .font(fuente)
                        .foregroundStyle(enCarga ? Color.primary : Color.clear)
                        .tint(Color.marca)
                        .focused($enCarga)
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
                }
            Text("kg").font(Archivo.fuente(20, peso: 700, relativoA: .headline)).foregroundStyle(.secondary)
        }
        .frame(minHeight: 60)
    }

    private func subir() {
        motor.cambiarCarga(lugar) { $0.aceptarAumento() }
        pulsoCarga += 1
        guard !reducir else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { encendido = true }
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.smooth(duration: 0.4)) { encendido = false }
        }
    }

    @ViewBuilder private func bannerAumento(_ s: CargaSimple) -> some View {
        switch s.aumento {
        case let .sugerido(desde, hasta):
            VStack(alignment: .leading, spacing: Espacio.s) {
                HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(Color.marcaTexto)
                        .accessibilityHidden(true)
                    Text("Esta semana bajan las reps: toca subir")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                }
                ViewThatFits(in: .horizontal) {
                    filaAumento(desde: desde, hasta: hasta, apilado: false)
                    filaAumento(desde: desde, hasta: hasta, apilado: true)
                }
            }
            .padding(Espacio.s)
            .background(Color.marcaSuave, in: .rect(cornerRadius: 20, style: .continuous))
            .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
        case let .aceptado(desde, hasta):
            HStack(spacing: Espacio.xs) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                Text(s.confirmadas > 0 ? "Subiste a \(KgTexto.de(hasta)) kg en las que faltan" : "Subiste a \(KgTexto.de(hasta)) kg en todas las series")
                    .font(.footnote.weight(.medium))
                Spacer(minLength: Espacio.xs)
                if s.confirmadas == 0 {
                    Button("Volver a \(KgTexto.de(desde))") { motor.cambiarCarga(lugar) { $0.deshacerAumento() } }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                        .accessibilityIdentifier("aumento-volver")
                }
            }
            .transition(.opacity)
        default: EmptyView()
        }
    }

    @ViewBuilder private func filaAumento(desde: Double, hasta: Double, apilado: Bool) -> some View {
        let subirBoton = Button { subir() } label: {
            Text("Subir a \(KgTexto.de(hasta)) kg").font(Archivo.fuente(17, peso: 800, relativoA: .headline)).lineLimit(1)
        }
        .buttonStyle(BotonConfirmar(compacto: true))
        .accessibilityIdentifier("aumento-subir")
        let dejarBoton = Button { motor.cambiarCarga(lugar) { $0.descartarAumento() } } label: {
            Text("Dejar \(KgTexto.de(desde)) kg").font(.subheadline.weight(.semibold)).lineLimit(1).frame(minHeight: 48).padding(.horizontal, Espacio.xs).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier("aumento-dejar")
        if apilado {
            VStack(spacing: Espacio.xxs) { subirBoton; dejarBoton }
        } else {
            HStack(spacing: Espacio.xs) { subirBoton; dejarBoton.fixedSize() }
        }
    }

    private func bannerHechas(_ s: CargaSimple) -> some View {
        let n = s.hechasConOtraCarga
        return HStack(alignment: .firstTextBaseline) {
            Text(n == 1 ? "La serie hecha sigue con su peso." : "Las \(n) hechas siguen con su peso.").font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: Espacio.xs)
            Button("Cambiarlas también") { Task { await motor.aplicarCargaALasHechas(lugar) } }.font(.footnote.weight(.semibold)).foregroundStyle(Color.marcaTexto).frame(minHeight: 44).contentShape(.rect).accessibilityIdentifier("aplicar-a-hechas")
        }
    }

    // MARK: Lista

    private func listaSeries(_ s: CargaSimple) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(motor.preparacion(lugar).isEmpty ? "Series" : "Series efectivas")
                    .font(Archivo.fuente(enLista ? 17 : 20, peso: 800, relativoA: .headline))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(s.confirmadas) de \(s.series.count)").font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(s.confirmadas == s.series.count ? Color.marcaTexto : Color.secondary)
                    .contentTransition(.numericText())
                    .animation(EstiloCarga.resorte, value: s.confirmadas)
            }
            if let leyenda = motor.leyendaRIR(lugar) {
                Text(leyenda).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("leyenda-rir")
            }
            if let i = s.activa, let c = tarjeta.filas[safe: i]?.calibracion {
                Label(Bonito.sinEmoji(c), systemImage: "scope").labelStyle(IconoTeñido(color: .marcaTexto)).font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(s.series.indices, id: \.self) { fila($0, s).id("fila-\($0)") }
            }
        }
    }

    private func fila(_ i: Int, _ s: CargaSimple) -> some View {
        let h = s.series[i]
        let enCorreccion = motor.corrigiendo?.lugar == lugar && motor.corrigiendo?.indice == i
        let activa = s.activa == i && motor.corrigiendo?.lugar != lugar
        let resaltada = h.confirmada || activa
        // Con letra de accesibilidad y peso por serie, los botones del kilo van abajo: al lado partían el número de reps.
        let apilar = letra.isAccessibilitySize && !s.sinKg && !s.mismoPeso && !h.confirmada
        return HStack(spacing: Espacio.s) {
            insignia(i, hecha: h.confirmada, activa: activa)
            let cuerpo = apilar ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xxs)) : AnyLayout(HStackLayout(spacing: Espacio.s))
            cuerpo {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(s.reps(i).map(String.init) ?? "—")
                        .font(Archivo.fuente(activa ? 24 : 20, peso: resaltada ? 800 : 600, relativoA: .title3))
                        .foregroundStyle(resaltada ? Color.primary : Color.secondary)
                        .contentTransition(.numericText())
                        .fixedSize()
                    if s.reps(i) != nil {
                        Text("reps").font(.subheadline).foregroundStyle(.secondary).fixedSize()
                    }
                }
                if !apilar { Spacer(minLength: 4) }
                if !s.sinKg {
                    if !s.mismoPeso && !h.confirmada {
                        kgPorSerie(i, s)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(KgTexto.de(h.kg).isEmpty ? "—" : KgTexto.de(h.kg))
                                .font(Archivo.fuente(18, peso: resaltada ? 700 : 600, relativoA: .headline))
                                .monospacedDigit()
                                .foregroundStyle(resaltada ? Color.primary : Color.secondary)
                                .contentTransition(.numericText())
                                .fixedSize()
                            if h.kg != nil { Text("kg").font(.footnote).foregroundStyle(.secondary).fixedSize() }
                        }
                    }
                }
                if h.confirmada {
                    Image(systemName: enCorreccion ? "pencil.circle.fill" : "pencil").font(.caption).foregroundStyle(Color.secondary.opacity(0.7)).accessibilityHidden(true)
                }
            }
        }
        .frame(minHeight: 56)
        .background(alignment: .leading) { conector(i, s) }
        .background(enCorreccion ? Color.marcaSuave : Color.clear, in: .rect(cornerRadius: 12, style: .continuous))
        .animation(reducir ? nil : EstiloCarga.resorte, value: h.confirmada)
        .animation(reducir ? nil : EstiloCarga.resorte, value: activa)
        .contentShape(.rect)
        .onTapGesture { if h.confirmada { Task { await motor.editarSerie(lugar, i) } } }
        .accessibilityElement(children: h.confirmada || s.mismoPeso ? .ignore : .contain)
        .accessibilityLabel(etiquetaFila(i, s))
        .accessibilityAddTraits(h.confirmada ? .isButton : [])
        .accessibilityIdentifier("fila-serie-\(i + 1)")
    }

    private func insignia(_ i: Int, hecha: Bool, activa: Bool) -> some View {
        ZStack {
            if hecha {
                Circle().fill(Color.marca)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .black)).foregroundStyle(Color.sobreMarca)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else if activa {
                Circle().fill(Color.marcaSuave)
                Circle().strokeBorder(Color.marca, lineWidth: 2)
                Text("\(i + 1)").font(Archivo.fuente(14, peso: 800, relativoA: .footnote).monospacedDigit()).foregroundStyle(Color.marcaTexto)
            } else {
                Circle().fill(Color.campo)
                Text("\(i + 1)").font(Archivo.fuente(14, peso: 600, relativoA: .footnote).monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    /// El hilo entre series: se pinta de verde lo que ya se hizo.
    private func conector(_ i: Int, _ s: CargaSimple) -> some View {
        let hueco: CGFloat = 20
        return VStack(spacing: 0) {
            Rectangle().fill(i > 0 && s.series[i - 1].confirmada && s.series[i].confirmada ? Color.marca.opacity(0.6) : Color.campo)
                .frame(width: 2).padding(.bottom, hueco).opacity(i == 0 ? 0 : 1)
            Rectangle().fill(i + 1 < s.series.count && s.series[i].confirmada && s.series[i + 1].confirmada ? Color.marca.opacity(0.6) : Color.campo)
                .frame(width: 2).padding(.top, hueco).opacity(i + 1 == s.series.count ? 0 : 1)
        }
        .padding(.leading, 15)
        .accessibilityHidden(true)
    }

    private func etiquetaFila(_ i: Int, _ s: CargaSimple) -> String {
        let h = s.series[i]
        let kg = s.sinKg ? "" : ", \(KgTexto.de(h.kg)) kilos"
        return h.confirmada ? "Serie \(i + 1), hecha: \(s.reps(i) ?? 0) repeticiones\(kg). Tocá para corregirla"
                            : "Serie \(i + 1), pendiente: \(s.reps(i).map(String.init) ?? "sin dato") repeticiones\(kg)"
    }

    private func kgPorSerie(_ i: Int, _ s: CargaSimple) -> some View {
        HStack(spacing: 4) {
            Button { motor.cambiarCarga(lugar) { $0.moverKg(i, pasos: -1) }; toquesCarga += 1 } label: { Image(systemName: "minus") }
                .buttonStyle(BotonCircularCarga(lado: 44, tamañoIcono: 15)).foregroundStyle(.primary).accessibilityLabel("Bajar el peso de la serie \(i + 1)").accessibilityIdentifier("kg-menos-\(i + 1)")
            TextField("—", text: Binding(get: { kgFila == i ? (kgTextos[i] ?? "") : KgTexto.de(s.series[i].kg) },
                                         set: { t in kgTextos[i] = t; let n = CamposSerie.normalizar("kg", t); motor.cambiarCarga(lugar) { $0.fijarKg(i, n.isEmpty ? nil : Double(n)) } }))
                .keyboardType(.decimalPad).multilineTextAlignment(.center).font(Archivo.fuente(19, peso: 800, relativoA: .headline).monospacedDigit())
                .focused($kgFila, equals: i).frame(width: anchoKgFila, height: 44)
                .accessibilityLabel("Peso de la serie \(i + 1) en kilos").accessibilityIdentifier("kg-serie-\(i + 1)")
                .onChange(of: kgFila) { _, f in if f == i { kgTextos[i] = KgTexto.de(s.series[i].kg) } }
            Button { motor.cambiarCarga(lugar) { $0.moverKg(i, pasos: 1) }; toquesCarga += 1 } label: { Image(systemName: "plus") }
                .buttonStyle(BotonCircularCarga(lado: 44, tamañoIcono: 15)).foregroundStyle(.primary).accessibilityLabel("Subir el peso de la serie \(i + 1)").accessibilityIdentifier("kg-mas-\(i + 1)")
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
