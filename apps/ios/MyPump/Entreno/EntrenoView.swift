import SwiftUI
import MyPumpModelos
import MyPumpReglas

/// Entreno: el día elegido, con su progreso, los bloques y cada ejercicio. Arriba, el título del día en Archivo; al
/// bajar, el título pasa chico a la barra.
struct EntrenoView: View {
    let datos: Muestras
    @Environment(SesionEnCurso.self) private var sesion
    @Environment(Descanso.self) private var descanso
    @State private var diaId: String?
    @State private var ruta: [Ejercicio] = []
    @State private var tituloEnBarra = false
    @State private var confirmarAvance = false
    @State private var confirmarCierre = false
    @State private var demoArrancada = false
    @ScaledMetric(relativeTo: .title) private var ladoAnillo: CGFloat = 68

    private var rutina: RutinaActiva? { datos.rutina }
    private var dias: [Dia] { rutina?.estructura.dias ?? [] }
    private var dia: Dia? { dias.first { $0.id == diaId } ?? dias.first }
    private var semana: Int { rutina?.semanaActual ?? 1 }
    private var offset: Int { rutina?.estructura.semanaOffset ?? 0 }
    private var total: Int { rutina?.estructura.semanasTotal ?? 12 }
    private var cerrados: Set<String> { Set(datos.sesionesSemana.filter(\.cerrada).map(\.diaId)) }

    var body: some View {
        NavigationStack(path: $ruta) {
            contenido
                .background(Color.fondo)
                .navigationTitle(titulo(dia))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(titulo(dia)).font(.headline)
                            Text("Semana \(semana + offset) de \(total + offset)")
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        }
                        .opacity(tituloEnBarra ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: tituloEnBarra)
                        .accessibilityHidden(!tituloEnBarra)
                    }
                }
                .navigationDestination(for: Ejercicio.self) { e in
                    EjercicioView(ejercicio: e, semana: semana, semanaOffset: offset, resumen: datos.resumen(de: e))
                }
        }
        .onAppear(perform: arrancarDemo)
    }

    @ViewBuilder private var contenido: some View {
        switch DemoUI.estado {
        case .cargando:
            ScrollView { EsqueletoEntreno().padding(.horizontal, Espacio.m).anchoLectura() }
                .scrollDisabled(true)
        case .error:
            ContentUnavailableView {
                Label("Sin conexión", systemImage: "wifi.slash")
            } description: {
                Text("No pudimos traer tu plan. Probá de nuevo cuando tengas señal.")
            } actions: {
                Button("Reintentar") {}.buttonStyle(BotonMarca(compacto: true))
            }
        case .vacio, nil:
            lista
        }
    }

    private var lista: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                cabecera
                SelectorDias(dias: dias, seleccionado: dia?.id, cerrados: cerrados) { diaId = $0 }
                if let dia, !dia.bloques.flatMap(\.ejercicios).isEmpty, DemoUI.estado != .vacio {
                    cuerpo(de: dia)
                } else {
                    diaVacio
                }
                RespaldoCientifico(texto: "ACSM · OMS · MedlinePlus (NIH)", estilo: .pie)
                    .padding(.top, Espacio.xs)
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Cabecera

    private var cabecera: some View {
        let todos = dia?.bloques.flatMap(\.ejercicios) ?? []
        let hechos = todos.filter { sesion.final($0.id) != nil }.count
        let cerrado = cerrados.contains(dia?.id ?? "")
        return HStack(alignment: .center, spacing: Espacio.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Día \(dia?.n ?? 1) · Semana \(semana + offset) de \(total + offset)").textoCeja()
                Text(titulo(dia))
                    .font(.tituloDia)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Label(cerrado ? "Día cerrado esta semana" : "\(todos.count) ejercicios",
                      systemImage: cerrado ? "checkmark.seal.fill" : "list.bullet")
                    .labelStyle(EtiquetaCompacta())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(cerrado ? Color.marcaTexto : Color.secondary)
            }
            Spacer(minLength: 0)
            AnilloProgreso(fraccion: Double(hechos) / Double(max(todos.count, 1)), grosor: 7) {
                VStack(spacing: -2) {
                    Text("\(hechos)").font(.numeroChico).contentTransition(.numericText())
                    Text("de \(todos.count)").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(8)
            }
            .frame(width: min(ladoAnillo, 108), height: min(ladoAnillo, 108))
            .animation(.snappy, value: hechos)
            .accessibilityElement()
            .accessibilityLabel("\(hechos) de \(todos.count) ejercicios hechos")
        }
        .padding(.top, Espacio.xs)
        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 8 } action: { tituloEnBarra = $0 }
    }

    // MARK: Cuerpo del día

    @ViewBuilder
    private func cuerpo(de dia: Dia) -> some View {
        let todos = dia.bloques.flatMap(\.ejercicios)
        let cambian = todos.filter { $0.tipo != "calentamiento" && Progresiones.nota($0, semanaActual: semana)?.cambia == true }.count
        let calibracion = semana <= 1 && offset == 0

        if cambian > 0 {
            AvisoProgresion(icono: "chart.line.uptrend.xyaxis",
                            texto: Text("Esta semana \(Text(cambian == 1 ? "1 ejercicio cambia" : "\(cambian) ejercicios cambian").bold()) carga o volumen. Mirá el detalle al abrir cada uno."))
        } else if calibracion {
            AvisoProgresion(icono: "scope",
                            texto: Text("Semana de calibración: llegá cerca del fallo muscular y encontrá tu peso real. Las reps son una guía (±2-3): no te guardes reps."))
        }

        if !cerrados.contains(dia.id ?? "") {
            if let inicio = sesion.inicio {
                CronometroSesion(inicio: inicio) { confirmarCierre = true }
            } else {
                VStack(spacing: Espacio.xs) {
                    Button {
                        withAnimation(.snappy) { sesion.empezar() }
                    } label: {
                        Label("Empezar entrenamiento", systemImage: "play.fill")
                    }
                    .buttonStyle(BotonMarca())
                    .sensoryFeedback(.impact(weight: .medium), trigger: sesion.inicio)
                    Text("Arranca el cronómetro de la sesión. O empezá directo: corre solo con tu primera serie.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        ForEach(Array(dia.bloques.enumerated()), id: \.offset) { i, bloque in
            BloqueEjercicios(indice: i, bloque: bloque, primerNumero: primerNumero(bloque: i, en: dia),
                             semana: semana, datos: datos)
        }

        if sesion.inicio != nil {
            resumenSesion(todos)
        }

        if semana < total {
            Button { confirmarAvance = true } label: {
                Label("Pasar a la semana \(semana + offset + 1)", systemImage: "arrow.right")
                    .labelStyle(TituloYFlecha())
            }
            .buttonStyle(BotonSecundario(tono: .marcaTexto))
            .confirmationDialog("Pasar a la semana \(semana + offset + 1)", isPresented: $confirmarAvance, titleVisibility: .visible) {
                Button("Pasar a la semana \(semana + offset + 1)") {}
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(todos.allSatisfy { sesion.final($0.id) != nil }
                     ? "¿Confirmás que querés avanzar a la semana \(semana + offset + 1)?"
                     : "Todavía tenés ejercicios sin completar en la semana \(semana + offset). Si avanzás, la semana nueva empieza con la progresión actualizada.")
            }
        }
    }

    private func resumenSesion(_ todos: [Ejercicio]) -> some View {
        let hechos = todos.filter { sesion.final($0.id) != nil }.count
        return VStack(spacing: Espacio.m) {
            HStack(spacing: 0) {
                celda("Hechos", "\(hechos)/\(todos.count)")
                Divider().frame(height: 36)
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    celda("Tiempo", "\(Int(ctx.date.timeIntervalSince(sesion.inicio ?? ctx.date) / 60)) min")
                }
                Divider().frame(height: 36)
                celda("Restan", "\(todos.count - hechos) ej")
            }
            Button { confirmarCierre = true } label: {
                Label("Cerrar sesión de hoy", systemImage: "flag.checkered")
            }
            .buttonStyle(BotonSecundario())
            .confirmationDialog("¿Cerrar la sesión de hoy?", isPresented: $confirmarCierre, titleVisibility: .visible) {
                Button("Cerrar sesión") { withAnimation(.snappy) { sesion.reiniciar() } }
                Button("Seguir entrenando", role: .cancel) {}
            } message: {
                Text("Se guardan tus series y Mati ve el resumen.")
            }
        }
        .tarjeta()
    }

    private func celda(_ titulo: String, _ valor: String) -> some View {
        VStack(spacing: 2) {
            Text(titulo).textoCeja()
            Text(valor).font(.numeroChico).monospacedDigit().contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var diaVacio: some View {
        ContentUnavailableView {
            Label("Día sin ejercicios", systemImage: "figure.cooldown")
        } description: {
            Text("Este día no tiene ejercicios cargados. Si es un día de descanso, ¡a descansar! Si no, avisale a Mati.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espacio.l)
    }

    private func primerNumero(bloque i: Int, en dia: Dia) -> Int {
        dia.bloques.prefix(i).reduce(0) { $0 + $1.ejercicios.count } + 1
    }

    /// Los nombres que vienen todo en mayúsculas ("TIRÓN") se muestran capitalizados; los demás, tal cual.
    private func titulo(_ dia: Dia?) -> String {
        guard let n = dia?.nombre, !n.isEmpty else { return "Entreno" }
        return n == n.uppercased() ? n.localizedCapitalized : n
    }

    private func arrancarDemo() {
        guard !demoArrancada else { return }
        demoArrancada = true
        guard DemoUI.estado == nil else { return }
        // Bocetos: un descanso a mitad de camino, para ver la isla. `-abrir ejercicio` entra directo al primer
        // ejercicio de trabajo.
        let primero = dias.first?.bloques.flatMap(\.ejercicios).first { $0.tipo == "compuesto" }
        if !DemoUI.sinDescanso {
            descanso.empezar(segundos: primero?.descansoSegundos ?? 150, ejercicio: primero?.nombre, yaPasaron: 66)
        }
        if DemoUI.abrir == "ejercicio", ruta.isEmpty, let primero { ruta = [primero] }
    }
}

extension Ejercicio: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Piezas

/// Aviso teñido de marca arriba del día ("Esta semana 7 ejercicios cambian carga o volumen").
private struct AvisoProgresion: View {
    let icono: String
    let texto: Text

    var body: some View {
        HStack(alignment: .top, spacing: Espacio.s) {
            Image(systemName: icono)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.marcaTexto)
                .frame(width: 22)
            texto.font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Título con la flecha a la derecha (para "Pasar a la semana 6 →").
private struct TituloYFlecha: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.subheadline.weight(.bold))
        }
    }
}

/// La sesión en curso: punto que late, "EN CURSO" y el tiempo (reemplaza al botón de empezar).
private struct CronometroSesion: View {
    let inicio: Date
    let cerrar: () -> Void
    @State private var late = false
    @Environment(\.accessibilityReduceMotion) private var reducir

    var body: some View {
        HStack(spacing: Espacio.s) {
            Circle()
                .fill(Color.marcaVivo)
                .frame(width: 10, height: 10)
                .overlay {
                    Circle().stroke(Color.marcaVivo.opacity(0.5), lineWidth: 2)
                        .scaleEffect(late ? 2.2 : 1).opacity(late ? 0 : 1)
                }
                .onAppear {
                    guard !reducir else { return }
                    withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { late = true }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text("En curso").textoCeja()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.reloj(ctx.date.timeIntervalSince(inicio)))
                        .font(.numeroMediano)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            Button("Cerrar", systemImage: "flag.checkered", action: cerrar)
                .buttonStyle(BotonSecundario(compacto: true))
        }
        .tarjeta()
        .accessibilityElement(children: .contain)
    }

    static func reloj(_ t: TimeInterval) -> String {
        let s = max(0, Int(t))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : mmss(s)
    }
}

/// Selector de días: cápsulas con "DÍA n" y la primera palabra del nombre. La elegida va invertida y se desliza; las
/// cerradas esta semana llevan el tilde de marca.
struct SelectorDias: View {
    let dias: [Dia]
    let seleccionado: String?
    let cerrados: Set<String>
    let elegir: (String?) -> Void
    @Namespace private var ns

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Espacio.xs) {
                ForEach(Array(dias.enumerated()), id: \.offset) { i, d in
                    let activo = d.id == seleccionado
                    let hecho = cerrados.contains(d.id ?? "")
                    Button {
                        withAnimation(.snappy(duration: 0.3)) { elegir(d.id) }
                    } label: {
                        VStack(spacing: 1) {
                            Text("Día \(d.n ?? i + 1)")
                                .font(.caption2.weight(.bold))
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .opacity(activo ? 0.65 : 1)
                                .foregroundStyle(activo ? Color(uiColor: .systemBackground) : Color.secondary)
                            Text(corto(d.nombre))
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(activo ? Color(uiColor: .systemBackground) : Color.primary)
                        }
                        .frame(minWidth: 70, minHeight: 44)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background {
                            if activo {
                                RoundedRectangle(cornerRadius: Radio.control + 2, style: .continuous)
                                    .fill(Color.primary)
                                    .matchedGeometryEffect(id: "seleccion", in: ns)
                            } else {
                                RoundedRectangle(cornerRadius: Radio.control + 2, style: .continuous)
                                    .fill(Color.tarjeta)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Radio.control + 2, style: .continuous)
                                            .strokeBorder(Color.borde, lineWidth: 1)
                                    }
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if hecho {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .heavy))
                                    .foregroundStyle(Color.sobreMarca)
                                    .frame(width: 16, height: 16)
                                    .background(Color.marca, in: .circle)
                                    .offset(x: 5, y: -5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Día \(d.n ?? i + 1), \(corto(d.nombre))\(hecho ? ", cerrado esta semana" : "")")
                    .accessibilityAddTraits(activo ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: seleccionado)
    }

    private func corto(_ nombre: String?) -> String {
        let p = (nombre ?? "").split(separator: " ").first.map(String.init) ?? ""
        return p == p.uppercased() ? p.localizedCapitalized : p
    }
}

/// Un bloque: "B1 · Espalda · 0/3" y sus ejercicios en una sola tarjeta, separados por líneas como una lista.
private struct BloqueEjercicios: View {
    let indice: Int
    let bloque: Bloque
    let primerNumero: Int
    let semana: Int
    let datos: Muestras
    @Environment(SesionEnCurso.self) private var sesion

    var body: some View {
        let hechos = bloque.ejercicios.filter { sesion.final($0.id) != nil }.count
        VStack(alignment: .leading, spacing: Espacio.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bloque \(numeroBloque)").textoCeja()
                HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                    Text(nombre).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Espacio.xs)
                    Text("\(hechos)/\(bloque.ejercicios.count)")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(hechos == bloque.ejercicios.count ? Color.marcaTexto : Color.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                ForEach(Array(bloque.ejercicios.enumerated()), id: \.element.id) { j, e in
                    NavigationLink(value: e) {
                        FilaEjercicio(ejercicio: e, numero: primerNumero + j, semana: semana, resumen: datos.resumen(de: e))
                    }
                    .buttonStyle(FilaPresionable())
                    if j < bloque.ejercicios.count - 1 {
                        Divider().padding(.leading, 90)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .superficieTarjeta()
        }
    }

    /// "BLOQUE 1 — ESPALDA" → 1. Si no trae número, el orden.
    private var numeroBloque: Int {
        let titulo = bloque.titulo ?? ""
        let digitos = titulo.split(separator: "—").first?.filter(\.isNumber) ?? ""
        return Int(digitos) ?? indice
    }

    /// El subtítulo si viene (formato seed); si no, lo que sigue a la raya del título ("BLOQUE 1 — ESPALDA").
    private var nombre: String {
        if let s = bloque.subtitulo, !s.isEmpty { return s.enOracion }
        let titulo = bloque.titulo ?? ""
        let partes = titulo.components(separatedBy: "—")
        let n = (partes.count > 1 ? partes.dropFirst().joined(separator: "—") : titulo).trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Bloque \(indice + 1)" : n.enOracion
    }
}

/// Fila de un ejercicio: miniatura con su número, nombre y músculo, la pauta de la semana en chips, y lo que hay que
/// superar (o "Primera vez"). Con letra de accesibilidad, la miniatura pasa arriba y los chips saltan de renglón.
struct FilaEjercicio: View {
    let ejercicio: Ejercicio
    let numero: Int
    let semana: Int
    let resumen: ResumenHistorial?
    @Environment(SesionEnCurso.self) private var sesion
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let pauta = Progresiones.pauta(ejercicio, semana: semana)
        let nombre = NombreEjercicio(ejercicio.nombre)
        let hechas = sesion.confirmadas(ejercicio.id)
        let final = sesion.final(ejercicio.id)
        let disposicion = tamañoLetra.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))

        disposicion {
            VStack(spacing: Espacio.xs) {
                Miniatura(url: ejercicio.imagenes?.concentric ?? ejercicio.imagenes?.eccentric, tipo: ejercicio.tipo, lado: 60)
                    .overlay(alignment: .topLeading) {
                        MarcaNumero(numero: numero, final: final).offset(x: -7, y: -7)
                    }
                if let s = pauta.series, s > 1, ejercicio.tipo != "cardio" {
                    PuntosSeries(total: s, hechas: hechas)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(nombre.principal)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let d = nombre.detalle {
                    Text(d).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                FilaFluida(espaciado: 6, interlineado: 6) {
                    if ejercicio.tipo == "calentamiento" || ejercicio.tipo == "cardio" {
                        Chip(texto: ejercicio.tipo == "cardio" ? "Cardio" : "Calent.", icono: "flame.fill", tono: .alerta)
                    }
                    if let s = pauta.series, let r = pauta.reps, ejercicio.tipo != "cardio" { Chip(texto: "\(s) × \(r)") }
                    else if let r = pauta.reps { Chip(texto: r) }
                    if let rir = pauta.rir { Chip(texto: "RIR \(rir)") }
                    if let d = ejercicio.descansoSegundos, d > 0 { Chip(texto: mmss(d), icono: "timer") }
                }
                .padding(.top, 5)
                historial.padding(.top, 4)
            }
            .padding(.trailing, Espacio.m)
        }
        .padding(.horizontal, Espacio.m)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, Espacio.m)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ejercicio \(numero): \(ejercicio.nombre)")
        .accessibilityValue(estadoAccesible(final: final, hechas: hechas, de: pauta.series))
    }

    @ViewBuilder private var historial: some View {
        if let r = resumen, let s = r.ultima.last {
            // Peso corporal (0 kg): como en la web, sin kilos.
            FilaFluida(espaciado: 8, interlineado: 2) {
                Text("Última: \(Text(cargaTexto(s)).foregroundStyle(.secondary)) · \(Fechas.haceCuanto(r.ultimaFecha))")
                    .foregroundStyle(.tertiary)
                if let rec = r.recordKg, rec > 0 {
                    Label("\(rec.kg) kg", systemImage: "trophy.fill")
                        .labelStyle(EtiquetaCompacta())
                        .foregroundStyle(Color.record)
                        .fontWeight(.semibold)
                }
            }
            .font(.caption)
        } else {
            Label("Primera vez con este ejercicio", systemImage: "sparkles")
                .labelStyle(EtiquetaCompacta())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func estadoAccesible(final: SesionEnCurso.Final?, hechas: Int, de total: Int?) -> String {
        switch final {
        case .completo: return "Completo"
        case .completoSinDatos: return "Terminado sin series"
        case nil: return hechas > 0 ? "\(hechas) de \(total ?? hechas) series" : "Pendiente"
        }
    }
}

/// El número del ejercicio en la esquina de la miniatura; tilde de marca cuando está completo.
private struct MarcaNumero: View {
    let numero: Int
    let final: SesionEnCurso.Final?

    var body: some View {
        ZStack {
            switch final {
            case .completo:
                Circle().fill(Color.marca)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.sobreMarca)
            case .completoSinDatos:
                Circle().fill(Color.tarjeta)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
            case nil:
                Circle().fill(Color.tarjeta)
                Text("\(numero)").font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(.primary)
            }
        }
        .frame(width: 22, height: 22)
        .overlay { Circle().strokeBorder(Color.borde, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .symbolEffect(.bounce, value: final)
        .accessibilityHidden(true)
    }
}

/// Esqueleto de la lista mientras carga: la forma real del día, tapada.
private struct EsqueletoEntreno: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Día 1 · Semana 5 de 12").textoCeja()
                Text("Tirón tirón").font(.tituloDia)
                Text("9 ejercicios").font(.subheadline)
            }
            HStack(spacing: Espacio.xs) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radio.control + 2, style: .continuous).fill(Color.campo).frame(width: 84, height: 60)
                }
            }
            RoundedRectangle(cornerRadius: 27, style: .continuous).fill(Color.campo).frame(height: 54)
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Espacio.s) {
                    Text("Bloque de ejemplo").font(.title3.weight(.bold))
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            HStack(alignment: .top, spacing: 14) {
                                RoundedRectangle(cornerRadius: Radio.miniatura, style: .continuous).fill(Color.campo).frame(width: 60, height: 60)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Nombre del ejercicio largo").font(.body.weight(.semibold))
                                    Text("Músculo principal").font(.subheadline)
                                    Text("4 × 10 · RIR 1 · 2:30").font(.caption)
                                }
                                Spacer()
                            }
                            .padding(Espacio.m)
                        }
                    }
                    .superficieTarjeta()
                }
            }
        }
        .padding(.top, Espacio.xs)
        .esqueleto()
    }
}
