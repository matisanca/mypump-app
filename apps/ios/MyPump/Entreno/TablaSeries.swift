import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// La tabla de series del motor: campos grandes que invitan a cargar. Lo de la última vez aparece sugerido en gris y un
/// toque en ✓ lo registra (SER-01); el kg se hereda de la serie anterior (SER-03); el RIR nunca se completa solo
/// (SER-02); lo imposible se rechaza y lo raro se pregunta (SER-05); tocar ✓ de nuevo desconfirma (SER-06). Al
/// confirmar arranca el descanso (salvo el calentamiento) y, con la última, el ejercicio queda completo.
struct TablaSeries: View {
    let motor: ModeloEntreno
    let lugar: String
    let tarjeta: ModeloEntreno.Tarjeta
    let alCompletarDia: (ModeloEntreno.DiaCompletado) -> Void
    /// Adentro de la lista de Entreno (el ejercicio abierto ahí mismo): sin tarjeta propia, va dentro de la del bloque.
    var enLista = false
    @Environment(Preguntador.self) private var preguntador
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    @FocusState private var foco: Campo?
    @State private var confirmadas = 0

    enum Campo: Hashable { case reps(Int), kg(Int) }

    private var series: [SerieLocal] { motor.dia.ejercicios[lugar]?.series ?? [] }

    var body: some View {
        let filas = tarjeta.filas
        let sinKg = filas.first?.sinKg ?? tarjeta.sinKg
        let activa = filas.firstIndex { $0.activa && !$0.confirmada }
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Series").font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(tarjeta.confirmadas) de \(filas.count)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(tarjeta.confirmadas == filas.count && !filas.isEmpty ? Color.marcaTexto : Color.secondary)
                    .contentTransition(.numericText())
            }

            if let v = tarjeta.variantes {
                VStack(alignment: .leading, spacing: 6) {
                    Text(v.etiqueta).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker(v.etiqueta, selection: Binding(get: { tarjeta.varianteActual ?? v.opciones.first ?? "" },
                                                          set: { motor.elegirVariante(lugar, $0) })) {
                        ForEach(v.opciones, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(motor.dia.diaFinalizado)
                }
                .padding(.bottom, 2)
            }

            if filas.isEmpty {
                Text("Este ejercicio no tiene series esta semana.").font(.subheadline).foregroundStyle(.secondary)
            } else {
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
                    ForEach(Array(filas.enumerated()), id: \.offset) { i, f in fila(i, f, sinKg: sinKg) }
                }

                if let i = activa {
                    pista(i, filas[i])
                        .padding(.top, 2)
                }
            }
        }
        .modifier(SuperficieTabla(enLista: enLista))
        .sensoryFeedback(.success, trigger: confirmadas)
        .onChange(of: tarjeta.confirmadas) { viejo, nuevo in if nuevo > viejo { confirmadas += 1 } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { foco = nil }.fontWeight(.semibold)
            }
        }
    }

    // MARK: Fila

    private func fila(_ i: Int, _ f: FilaSerie, sinKg: Bool) -> some View {
        let s = i < series.count ? series[i] : SerieLocal()
        let marcada = s.aviso != nil && !f.confirmada
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Espacio.xs) {
                ZStack {
                    Circle().fill(f.activa && !f.confirmada ? Color.marca : (f.confirmada ? Color.clear : Color.campo))
                    Text("\(i + 1)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(f.activa && !f.confirmada ? Color.sobreMarca : (f.confirmada ? Color.marcaTexto : Color.secondary))
                }
                .frame(width: 30, height: 30)

                CampoSerie(texto: enlace(i, "reps", valor: s.reps), sugerencia: f.placeholderReps.isEmpty ? "–" : f.placeholderReps,
                           teclado: .numberPad, confirmada: f.confirmada, marcada: marcada, foco: $foco, campo: .reps(i))
                    .accessibilityLabel("Repeticiones de la serie \(i + 1)")
                if !sinKg {
                    // Con las reps escritas y el kg vacío se guarda el kg de la serie anterior (SER-03): que la
                    // sugerencia muestre ese, no el de la última vez.
                    let heredado = !f.confirmada && !s.reps.isEmpty && s.kg.isEmpty ? HistorialEntreno.kgHeredable(series, indice: i) : ""
                    let sugerido = heredado.isEmpty ? f.placeholderKg : heredado
                    CampoSerie(texto: enlace(i, "kg", valor: s.kg), sugerencia: Self.coma(sugerido.isEmpty ? "–" : sugerido),
                               teclado: .decimalPad, confirmada: f.confirmada, marcada: marcada, foco: $foco, campo: .kg(i))
                        .accessibilityLabel("Kilos de la serie \(i + 1)")
                }
                SelectorRIR(rir: s.rir, confirmada: f.confirmada) { n in
                    Task { await motor.elegirRIR(lugar, i, n) }
                }
                .accessibilityLabel("RIR de la serie \(i + 1)")

                Button { tocarCheck(i, f) } label: {
                    ZStack {
                        Circle()
                            .fill(f.confirmada ? Color.marca : Color.clear)
                            .overlay {
                                Circle().strokeBorder(f.confirmada ? Color.clear : (f.puedeConfirmar ? Color.marcaVivo : Color(uiColor: .tertiaryLabel)),
                                                      lineWidth: 2)
                            }
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(f.confirmada ? Color.sobreMarca : (f.puedeConfirmar ? Color.marcaTexto : Color(uiColor: .tertiaryLabel)))
                            .symbolEffect(.bounce, value: f.confirmada)
                    }
                    .frame(width: 34, height: 34)
                    .frame(width: 44, height: 48)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!f.puedeConfirmar)
                .accessibilityLabel(f.confirmada ? "Serie \(i + 1) hecha. Tocá para corregirla" : (f.tituloConfirmar ?? "Confirmar serie \(i + 1)"))
                .accessibilityIdentifier("confirmar-serie-\(i + 1)")
            }
            .padding(.vertical, 2)
            .animation(.snappy(duration: 0.25), value: f.confirmada)

            if let aviso = s.aviso, !aviso.isEmpty, !f.confirmada {
                Label(aviso, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(IconoTeñido(color: .peligro))
                    .font(.caption)
                    .foregroundStyle(Color.peligro)
                    .padding(.leading, 38)
                    .transition(.opacity)
            }
        }
    }

    /// Lo que se escribe pasa por el motor (que normaliza: coma a punto en kg, solo dígitos en reps). En kg se muestra
    /// con la coma de acá.
    private func enlace(_ i: Int, _ campo: String, valor: String) -> Binding<String> {
        Binding(get: { campo == "kg" ? Self.coma(valor) : valor },
                set: { motor.escribir(lugar, i, campo: campo, valor: $0) })
    }

    private func tocarCheck(_ i: Int, _ f: FilaSerie) {
        if f.confirmada {
            Task { await motor.editarSerie(lugar, i) }
            return
        }
        foco = nil
        Task {
            let completo = await motor.confirmarSerie(lugar, i) { await preguntador.preguntar($0) }
            if let completo { alCompletarDia(completo) }
        }
    }

    /// La pista de la fila activa: lo de la última vez a un toque, o la calibración la primera vez. Como en la web
    /// (`data-sugconfirm`), la pista de la última vez ES un botón: tocarla registra la serie igual que el ✓. En la 101 era
    /// solo texto y "Tocá para registrar" no hacía nada (lo encontró Mati el 14-oct).
    @ViewBuilder
    private func pista(_ i: Int, _ f: FilaSerie) -> some View {
        if let p = f.pista {
            // "✓ Tocá para registrar lo de la última vez · **80kg × 10** — o editá si hiciste otra cosa", con la
            // puntuación de una frase de iOS.
            let antes = p.antes.replacingOccurrences(of: "✓ ", with: "").replacingOccurrences(of: " · ", with: "")
            let despues = p.despues.replacingOccurrences(of: " — ", with: "").trimmingCharacters(in: .whitespaces)
            Button { tocarCheck(i, f) } label: {
                Label {
                    Text("\(antes): \(Text(Bonito.carga(p.negrita)).bold().foregroundStyle(.primary)). \(despues.prefix(1).uppercased() + despues.dropFirst()).")
                        .multilineTextAlignment(.leading)
                } icon: {
                    Image(systemName: "hand.tap.fill").foregroundStyle(Color.marcaTexto)
                }
                .labelStyle(EtiquetaCompacta())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.marcaSuave, in: .rect(cornerRadius: 12, style: .continuous))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!f.puedeConfirmar)
            .accessibilityLabel("Registrar lo de la última vez: \(Bonito.carga(p.negrita))")
            .accessibilityIdentifier("registrar-ultima-vez")
        } else if let c = f.calibracion {
            Label(Bonito.sinEmoji(c), systemImage: "scope")
                .labelStyle(IconoTeñido(color: .marcaTexto))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func coma(_ s: String) -> String { s.replacingOccurrences(of: ".", with: ",") }
}

/// Un campo de la tabla: grande, centrado, con la sugerencia en gris y teñido de marca cuando la serie está hecha.
/// Mientras se escribe, el campo es dueño de su texto y cada cambio va al motor: si leyera de vuelta lo normalizado
/// en cada tecla, al tipear rápido ("52,5") un redibujo atrasado se comía la coma y lo que seguía.
private struct CampoSerie: View {
    @Binding var texto: String
    let sugerencia: String
    let teclado: UIKeyboardType
    let confirmada: Bool
    let marcada: Bool
    var foco: FocusState<TablaSeries.Campo?>.Binding
    let campo: TablaSeries.Campo
    @State private var local = ""

    var body: some View {
        let enfocado = foco.wrappedValue == campo
        TextField(sugerencia, text: $local)
            .onAppear { local = texto }
            .onChange(of: local) { _, nuevo in if nuevo != texto { texto = nuevo } }
            // Lo que cambia el motor (confirmar, desconfirmar, otra variante) entra cuando no se está escribiendo.
            .onChange(of: texto) { _, nuevo in if !enfocado && nuevo != local { local = nuevo } }
            .onChange(of: enfocado) { _, ahora in
                if ahora { CampoSerie.seleccionarTodo() } else { local = texto }
            }
            .focused(foco, equals: campo)
            .keyboardType(teclado)
            .multilineTextAlignment(.center)
            .font(.title3.weight(.semibold).monospacedDigit())
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(confirmada ? Color.marcaSuave : Color.campo, in: .rect(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(marcada ? Color.peligro : Color.marcaVivo, lineWidth: enfocado || marcada ? 2 : 0)
            }
            .disabled(confirmada)
    }

    /// Como la web (`select()` al enfocar): al corregir, lo que se escribe reemplaza lo anterior. Sin esto, 8 kg
    /// corregido a 7 quedaba "87" y entraba sin pregunta (revisión del 14-oct, hallazgo 2). Va un instante después del
    /// foco: el toque ubica el cursor al soltar y pisaría la selección.
    static func seleccionarTodo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        }
    }
}

/// RIR 0-5 en un menú, con la leyenda de la web; nunca se completa solo. "–" es sin dato, que no es lo mismo que 0.
private struct SelectorRIR: View {
    let rir: String
    let confirmada: Bool
    let elegir: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(0...5, id: \.self) { n in
                Button {
                    elegir(n)
                } label: {
                    if rir == String(n) {
                        Label("\(n) · \(CamposSerie.leyendaRIR(String(n)))", systemImage: "checkmark")
                    } else {
                        Text("\(n) · \(CamposSerie.leyendaRIR(String(n)))")
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(rir.isEmpty ? "–" : rir)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(rir.isEmpty ? Color.secondary : Color.primary)
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

/// La tabla en su tarjeta (la página del ejercicio) o suelta, con su margen, adentro de la tarjeta del bloque.
private struct SuperficieTabla: ViewModifier {
    let enLista: Bool
    func body(content: Content) -> some View {
        if enLista {
            content.padding(.horizontal, Espacio.m).padding(.vertical, Espacio.s)
        } else {
            content.tarjeta()
        }
    }
}
