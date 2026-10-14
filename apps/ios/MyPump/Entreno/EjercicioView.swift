import SwiftUI
import MyPumpModelos
import MyPumpReglas

/// Detalle de un ejercicio: el movimiento (inicio y pico), la pauta de la semana, la nota de progresión, la tabla de
/// series, lo que hay que superar, las acciones, la técnica y los comentarios. En iPad, en dos columnas.
struct EjercicioView: View {
    let ejercicio: Ejercicio
    let semana: Int
    let semanaOffset: Int
    let resumen: ResumenHistorial?
    @Environment(SesionEnCurso.self) private var sesion
    @Environment(\.horizontalSizeClass) private var claseAncho
    @Environment(\.dismiss) private var volver
    @State private var tituloEnBarra = false
    @State private var confirmarSinDatos = false
    @State private var comentario = ""
    @State private var demoHecha = false
    @FocusState private var escribiendo: Bool

    private var pauta: Pauta { Progresiones.pauta(ejercicio, semana: semana) }
    private var nombre: NombreEjercicio { NombreEjercicio(ejercicio.nombre) }
    private var cantidad: Int { max(pauta.series ?? 3, 1) }

    var body: some View {
        ScrollViewReader { lector in
            ScrollView {
                Group {
                    if claseAncho == .regular {
                        // Cada columna a su alto ideal: si no, la pila horizontal negocia alturas y corta textos.
                        HStack(alignment: .top, spacing: Espacio.l) {
                            VStack(alignment: .leading, spacing: Espacio.l) {
                                encabezado(lector); metricas; nota; comoSeHace
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                            .topeArriba()
                            VStack(alignment: .leading, spacing: Espacio.l) {
                                series; aSuperar; acciones(lector); comentarios; cierre
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                            .topeArriba()
                        }
                        .anchoLectura(Ancho.doble)
                    } else {
                        // En el teléfono, lo que se usa en el gimnasio va primero: la pauta y la tabla quedan a la
                        // vista sin desplazar; el "cómo se hace" (fotos grandes y técnica) va después.
                        VStack(alignment: .leading, spacing: Espacio.l) {
                            encabezado(lector); metricas; nota; series; aSuperar; acciones(lector); comoSeHace
                            comentarios; cierre
                        }
                        .anchoLectura()
                    }
                }
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.xs)
                .padding(.bottom, Espacio.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                // Bocetos: `-ir series` (o movimiento, comentarios) abre desplazado hasta esa sección.
                guard let ancla = DemoUI.ir else { return }
                try? await Task.sleep(for: .milliseconds(400))
                lector.scrollTo(ancla, anchor: .top)
            }
        }
        .background(Color.fondo)
        .navigationTitle(nombre.principal)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(nombre.principal)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(tituloEnBarra ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: tituloEnBarra)
                    .accessibilityHidden(!tituloEnBarra)
            }
        }
        .onAppear(perform: demo)
    }

    // MARK: Secciones

    private var urlInicio: URL? { ejercicio.imagenes?.eccentric.flatMap(URL.init(string:)) }
    private var urlPico: URL? { ejercicio.imagenes?.concentric.flatMap(URL.init(string:)) }

    /// Nombre y músculo, con el movimiento en chico al lado (tocarlo lleva a las fotos grandes).
    private func encabezado(_ lector: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 14) {
            if urlInicio != nil || urlPico != nil {
                Button {
                    withAnimation(.snappy) { lector.scrollTo("movimiento", anchor: .top) }
                } label: {
                    ImagenesMovimiento(inicio: urlInicio, pico: urlPico, compacto: true)
                        .frame(width: 84, height: 84)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ver cómo se hace")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(nombre.principal)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let d = nombre.detalle {
                    Text(d).font(.headline.weight(.regular)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 0 } action: { tituloEnBarra = $0 }
    }

    private var metricas: some View {
        MetricasPauta(pauta: pauta, descanso: ejercicio.descansoSegundos, tipo: ejercicio.tipo)
    }

    /// Las fotos grandes del movimiento y la nota técnica de Mati, juntas.
    @ViewBuilder private var comoSeHace: some View {
        let hayFotos = urlInicio != nil || urlPico != nil
        let notas = ejercicio.notasTecnica.flatMap { $0.isEmpty ? nil : $0 }
        if hayFotos || notas != nil {
            VStack(alignment: .leading, spacing: Espacio.s) {
                Text("Cómo se hace").font(.title3.weight(.bold)).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Espacio.m) {
                    if hayFotos { ImagenesMovimiento(inicio: urlInicio, pico: urlPico) }
                    if let notas {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Nota técnica de Mati", systemImage: "text.quote")
                                .labelStyle(EtiquetaCompacta())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(notas).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, hayFotos ? 4 : 0)
                        .accessibilityElement(children: .combine)
                    }
                }
                .tarjeta(relleno: hayFotos ? 10 : 16)
            }
            .id("movimiento")
        }
    }

    @ViewBuilder private var nota: some View {
        if ejercicio.tipo != "calentamiento", let nota = Progresiones.nota(ejercicio, semanaActual: semana) {
            // La web muestra "calibración" solo en la semana 1 sin offset.
            let calibracion = nota.calibracion && semana == 1 && semanaOffset == 0
            let rotulo = nota.cambia ? "Cambio de la semana" : (calibracion ? "Semana 1" : "Esta semana")
            let icono = nota.cambia ? "chart.line.uptrend.xyaxis" : (calibracion ? "scope" : "equal.circle")
            VStack(alignment: .leading, spacing: 6) {
                Label(rotulo, systemImage: icono)
                    .labelStyle(EtiquetaCompacta())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                Text(nota.texto)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(nota.cambia ? Color.marcaSuave : Color.tarjeta,
                        in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var series: some View {
        TablaSeries(ejercicio: ejercicio, pauta: pauta, resumen: resumen).id("series")
    }

    @ViewBuilder private var aSuperar: some View {
        if let r = resumen {
            HStack(spacing: Espacio.s) {
                Dato(titulo: "Última vez", valor: r.ultima.last.map(cargaTexto) ?? "—",
                     detalle: Fechas.haceCuanto(r.ultimaFecha), icono: "calendar")
                Dato(titulo: "Récord a superar", valor: r.recordKg.map { "\($0.kg) kg" } ?? "—", detalle: "mejor serie",
                     icono: "trophy.fill", tono: .record)
            }
        }
    }

    private func acciones(_ lector: ScrollViewProxy) -> some View {
        HStack(spacing: Espacio.s) {
            Button {} label: { Label("Sustituir", systemImage: "arrow.triangle.2.circlepath") }
            Button {
                withAnimation(.snappy) { lector.scrollTo("comentarios", anchor: .center) }
                escribiendo = true
            } label: { Label("Comentar", systemImage: "bubble.left.fill") }
            if ejercicio.videoURL != nil {
                Button {} label: { Label("Video", systemImage: "play.rectangle.fill") }
            }
        }
        .buttonStyle(AccionTarjeta())
    }

    private var comentarios: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text("Comentarios").font(.title3.weight(.bold)).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Espacio.s) {
                Text("Todavía no hay comentarios. Dejale una nota a Mati o contale cómo te fue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .bottom, spacing: Espacio.xs) {
                    TextField("Escribí una nota…", text: $comentario, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($escribiendo)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.campo, in: .rect(cornerRadius: 20, style: .continuous))
                    Button { comentario = ""; escribiendo = false } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(comentario.isEmpty ? Color.secondary : Color.sobreMarca)
                            .frame(width: 40, height: 40)
                            .background(comentario.isEmpty ? Color.campo : Color.marca, in: .circle)
                    }
                    .buttonStyle(.plain)
                    .disabled(comentario.isEmpty)
                    .accessibilityLabel("Enviar comentario")
                }
            }
            .tarjeta()
        }
        .id("comentarios")
    }

    @ViewBuilder private var cierre: some View {
        let hechas = sesion.confirmadas(ejercicio.id)
        let final = sesion.final(ejercicio.id)
        VStack(spacing: Espacio.s) {
            if final != nil {
                Button {
                    withAnimation(.snappy) { sesion.terminar(ejercicio.id, nil) }
                } label: { Label("Reabrir ejercicio", systemImage: "pencil") }
                .buttonStyle(BotonSecundario())
            } else {
                Button {
                    withAnimation(.snappy) { sesion.terminar(ejercicio.id, .completo) }
                    volver()
                } label: {
                    Label(hechas == cantidad ? "Marcar ejercicio completo" : "Confirmá las series para completar",
                          systemImage: "checkmark")
                }
                .buttonStyle(BotonMarca())
                .disabled(hechas < cantidad)
                .sensoryFeedback(.success, trigger: final) { _, nuevo in nuevo == .completo }

                Button("Terminé este ejercicio") { confirmarSinDatos = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .frame(minHeight: 44)
                    .confirmationDialog("¿Terminaste sin cargar las series?", isPresented: $confirmarSinDatos,
                                        titleVisibility: .visible) {
                        Button("Sí, lo terminé") {
                            withAnimation(.snappy) { sesion.terminar(ejercicio.id, .completoSinDatos) }
                            volver()
                        }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("Queda marcado como hecho, sin kilos ni repeticiones.")
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Espacio.xs)
    }

    /// Bocetos: `-series 2` abre el ejercicio con dos series ya confirmadas (para ver ese estado en la captura).
    private func demo() {
        guard !demoHecha, DemoUI.seriesHechas > 0 else { return }
        demoHecha = true
        for i in 0..<min(DemoUI.seriesHechas, cantidad) where !sesion.valores(ejercicio.id, serie: i).confirmada {
            let previa = resumen?.ultima.first { $0.serie == i + 1 }
            var v = SesionEnCurso.ValoresSerie()
            v.reps = previa?.reps.map(String.init) ?? "10"
            v.kg = previa?.pesoKg.map { $0.kg } ?? ""
            v.rir = i == 0 ? 1 : 0
            v.confirmada = true
            sesion.guardar(v, ejercicioId: ejercicio.id, serie: i)
        }
    }
}

// MARK: - Piezas

/// La pauta de la semana como métricas, no como chips: series × reps, RIR y descanso, con el número en Archivo.
private struct MetricasPauta: View {
    let pauta: Pauta
    let descanso: Int?
    let tipo: String?
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private struct Metrica: Identifiable {
        let titulo: String
        let valor: String
        var detalle: String?
        var id: String { titulo }
    }

    private var metricas: [Metrica] {
        var m: [Metrica] = []
        if let r = pauta.reps {
            if let s = pauta.series, tipo != "cardio" { m.append(Metrica(titulo: "Series × reps", valor: "\(s) × \(r)")) }
            else { m.append(Metrica(titulo: "Duración", valor: r)) }
        }
        if let rir = pauta.rir {
            let partes = Self.partir(rir)
            m.append(Metrica(titulo: "RIR", valor: partes.0, detalle: partes.1))
        }
        if let d = descanso, d > 0 { m.append(Metrica(titulo: "Descanso", valor: mmss(d))) }
        return m
    }

    var body: some View {
        let ms = metricas
        Group {
            if tamañoLetra.isAccessibilitySize {
                // Con letra de accesibilidad, una métrica por renglón: rótulo a la izquierda, número a la derecha.
                VStack(spacing: Espacio.s) {
                    ForEach(ms) { m in
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.titulo).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(m.valor).font(.numeroMediano).monospacedDigit()
                                if let d = m.detalle { Text(d).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(ms.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { separador }
                        metrica(m.titulo, m.valor, detalle: m.detalle)
                    }
                }
                // El alto lo ponen los números; los separadores se estiran hasta ahí y no más.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tarjeta(relleno: 14)
    }

    private var separador: some View {
        Rectangle().fill(Color.borde).frame(width: 1).frame(maxHeight: .infinity).padding(.vertical, 2)
    }

    private func metrica(_ titulo: String, _ valor: String, detalle: String? = nil) -> some View {
        VStack(spacing: 3) {
            Text(titulo)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(valor)
                .font(.numeroMediano)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detalle {
                Text(detalle).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "0 (al fallo)" → ("0", "al fallo"). Sin paréntesis, entero.
    static func partir(_ s: String) -> (String, String?) {
        guard s.hasSuffix(")"), let abre = s.firstIndex(of: "(") else { return (s, nil) }
        let principal = s[..<abre].trimmingCharacters(in: .whitespaces)
        let detalle = s[s.index(after: abre)..<s.index(before: s.endIndex)].trimmingCharacters(in: .whitespaces)
        return (principal.isEmpty ? s : principal, detalle.isEmpty ? nil : detalle)
    }
}

/// Las dos fotos del catálogo (inicio y pico) alternándose como un flipbook: se ve el recorrido sin video. Con
/// Reducir movimiento no se alternan solas; el selector de abajo elige cuál ver (y frena la alternancia).
struct ImagenesMovimiento: View {
    let inicio: URL?
    let pico: URL?
    /// En chico (la miniatura del encabezado): cuadrada, sin selector.
    var compacto = false
    @State private var fase = 0
    @State private var automatico = true
    @Environment(\.accessibilityReduceMotion) private var reducir

    private var urls: [URL?] { [inicio, pico] }
    private var radio: CGFloat { compacto ? Radio.miniatura + 6 : Radio.tarjeta - 10 }

    var body: some View {
        Color.white
            .aspectRatio(compacto ? 1 : 3 / 2, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        if let u = urls[i] {
                            AsyncImage(url: u, transaction: Transaction(animation: .easeOut(duration: 0.25))) { f in
                                if let img = f.image {
                                    img.resizable().scaledToFill()
                                } else if f.error != nil {
                                    Image(systemName: "photo").font(compacto ? .title3 : .largeTitle).foregroundStyle(.tertiary)
                                } else {
                                    Color.campo
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(fase == i ? 1 : 0)
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: radio, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radio, style: .continuous).strokeBorder(Color.borde, lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                if !compacto, inicio != nil, pico != nil { selector.padding(Espacio.s) }
            }
            .task(id: automatico && !reducir && inicio != nil && pico != nil) {
                guard automatico, !reducir, inicio != nil, pico != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.6))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.45)) { fase = 1 - fase }
                }
            }
            .accessibilityElement(children: compacto ? .ignore : .contain)
            .accessibilityLabel("Fotos del movimiento: inicio y pico")
    }

    private var selector: some View {
        HStack(spacing: 2) {
            ForEach(Array(["Inicio", "Pico"].enumerated()), id: \.offset) { i, t in
                Button {
                    automatico = false
                    withAnimation(.snappy) { fase = i }
                } label: {
                    Text(t)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(fase == i ? Color.sobreMarca : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 32)
                        .background {
                            if fase == i { Capsule().fill(Color.marca) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(fase == i ? .isSelected : [])
            }
        }
        .padding(3)
        .vidrio(Capsule())
        .frame(minHeight: 44)
    }
}
