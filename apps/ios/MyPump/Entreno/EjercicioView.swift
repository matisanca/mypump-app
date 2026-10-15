import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// La card abierta de un ejercicio (ENT-11) como pantalla: el movimiento, la pauta de la semana, la nota de progresión,
/// la variante, la tabla de series, la última vez y el récord a superar, sustituir/comentar/video, la técnica, los
/// comentarios con Mati y marcar completo, "Terminé este ejercicio" o reabrir. Todo pasa por el motor. En iPad, en
/// dos columnas.
struct EjercicioView: View {
    let motor: ModeloEntreno
    let lugar: String
    /// "🎉 ¡Día completado!" (lo pregunta la lista, que sabe a qué día ir).
    let alCompletarDia: (ModeloEntreno.DiaCompletado) -> Void
    /// Abrir otro ejercicio del día en lugar de este (el siguiente pendiente).
    let abrir: (String) -> Void
    @Environment(\.horizontalSizeClass) private var claseAncho
    @Environment(\.dynamicTypeSize) private var letraDeLaVista
    @State private var tituloEnBarra = false
    @State private var comentario = ""
    @State private var enviando = false
    @State private var falloComentario = false
    @State private var sustituyendo = false
    @State private var video: URL?
    @State private var demoHecha = false
    @FocusState private var escribiendo: Bool

    var body: some View {
        Group {
            if let t = motor.tarjeta(lugar) {
                contenido(t)
            } else {
                ContentUnavailableView("Este ejercicio ya no está en el día", systemImage: "dumbbell",
                                       description: Text("Volvé a la lista para ver el día actualizado."))
            }
        }
        .background(Color.fondo)
        // Al volver, el ejercicio queda abierto en la lista de Entreno, donde se carga (15-oct).
        .task { await abrirCard() }
        .sheet(isPresented: $sustituyendo) { SustituirEjercicioView(motor: motor, lugar: lugar) }
        .sheet(item: Binding(get: { video.map(URLVideo.init) }, set: { video = $0?.url })) { v in
            NavegadorInterno(url: v.url).ignoresSafeArea()
        }
        .alert("No se pudo enviar", isPresented: $falloComentario) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(TextosEntreno.comentarioFallo)
        }
    }

    private func contenido(_ t: ModeloEntreno.Tarjeta) -> some View {
        let nombre = NombreEjercicio(t.efectivo.ejercicio.nombre)
        return ScrollViewReader { lector in
            ScrollView {
                Group {
                    if claseAncho == .regular {
                        // Cada columna a su alto ideal: si no, la pila horizontal negocia alturas y corta textos.
                        HStack(alignment: .top, spacing: Espacio.l) {
                            VStack(alignment: .leading, spacing: Espacio.l) {
                                encabezado(t, lector); metricas(t); nota(t); comoSeHace(t)
                            }
                            .frame(maxWidth: .infinity, alignment: .top)
                            .fixedSize(horizontal: false, vertical: true)
                            .topeArriba()
                            VStack(alignment: .leading, spacing: Espacio.l) {
                                series(t); aSuperar(t); acciones(t, lector); comentarios(t); cierre(t)
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
                            encabezado(t, lector); metricas(t); nota(t); series(t); aSuperar(t); acciones(t, lector)
                            comoSeHace(t); comentarios(t); cierre(t)
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
                // Capturas: `-ir series` (o movimiento, comentarios) abre desplazado hasta esa sección.
                guard let ancla = DemoUI.ir else { return }
                try? await Task.sleep(for: .milliseconds(400))
                lector.scrollTo(ancla, anchor: .top)
            }
        }
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
    }

    // MARK: Secciones

    /// Nombre y músculo, con el movimiento en chico al lado (tocarlo lleva a las fotos grandes), y si está sustituido,
    /// de qué y hasta cuándo.
    private func encabezado(_ t: ModeloEntreno.Tarjeta, _ lector: ScrollViewProxy) -> some View {
        let ef = t.efectivo
        let nombre = NombreEjercicio(ef.ejercicio.nombre)
        let inicio = ef.ejercicio.imagenes?.eccentric.flatMap(URL.init(string:))
        let pico = ef.ejercicio.imagenes?.concentric.flatMap(URL.init(string:))
        return VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .center, spacing: 14) {
                if inicio != nil || pico != nil {
                    Button {
                        withAnimation(.snappy) { lector.scrollTo("movimiento", anchor: .top) }
                    } label: {
                        ImagenesMovimiento(inicio: inicio, pico: pico, compacto: true).frame(width: 84, height: 84)
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

            if ef.sustituido {
                HStack(spacing: Espacio.xs) {
                    InsigniaSustitucion(fijado: ef.fijado)
                    Text("En lugar de \(NombreEjercicio(ef.nombreOriginal ?? "").principal)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            FilaFluida(espaciado: 6, interlineado: 6) {
                if t.manual { Chip(texto: "Marcado a mano", icono: "hand.raised.fill") }
                if t.sinLeer > 0 { Chip(texto: "\(t.sinLeer) de Mati", icono: "bubble.left.fill", tono: .marcaTexto) }
            }
        }
    }

    private func metricas(_ t: ModeloEntreno.Tarjeta) -> some View {
        MetricasPauta(pauta: t.pauta, descanso: t.descanso, tipo: t.efectivo.ejercicio.tipo)
    }

    @ViewBuilder
    private func nota(_ t: ModeloEntreno.Tarjeta) -> some View {
        if let nota = t.nota {
            let rotulo = nota.cambia ? "Cambio de la semana" : (nota.calibracion ? "Semana 1" : "Esta semana")
            let icono = nota.cambia ? "chart.line.uptrend.xyaxis" : (nota.calibracion ? "scope" : "equal.circle")
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
            .background(nota.cambia ? Color.marcaSuave : Color.tarjeta, in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// La tabla, si el ejercicio lleva series (el cardio y lo que va por tiempo no: se marca con "Terminé").
    @ViewBuilder
    private func series(_ t: ModeloEntreno.Tarjeta) -> some View {
        if !t.filas.isEmpty {
            TablaSeries(motor: motor, lugar: lugar, tarjeta: t, alCompletarDia: alCompletarDia).id("series")
        }
    }

    /// "📅 Última vez (…)" y "🏆 Récord a superar", o la primera vez.
    @ViewBuilder
    private func aSuperar(_ t: ModeloEntreno.Tarjeta) -> some View {
        if t.ultimaVez != nil || t.record != nil {
            // Con letra de accesibilidad, una debajo de la otra: lado a lado el peso quedaba en "60 k…".
            let disposicion = letraDeLaVista.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                                                 : AnyLayout(HStackLayout(alignment: .top, spacing: Espacio.s))
            disposicion {
                if let u = t.ultimaVez {
                    let p = Bonito.partir(u.valor)
                    Dato(titulo: "Última vez", valor: p.principal,
                         detalle: [u.cuando, p.detalle].compactMap { $0 }.joined(separator: " · "), icono: "calendar")
                }
                if let r = t.record {
                    let p = Bonito.partir(r)
                    Dato(titulo: "Récord a superar", valor: p.principal, detalle: p.detalle ?? "mejor serie",
                         icono: "trophy.fill", tono: .record)
                }
            }
        } else if !t.filas.isEmpty && !t.sinKg && motor.historialCargando.contains(lugar) {
            HStack(spacing: Espacio.xs) {
                ProgressView()
                Text("Buscando tu última vez…").font(.subheadline).foregroundStyle(.secondary)
            }
            .tarjeta()
        }
        // Sin historial no va nada acá: la primera vez ya la explica la tabla (la calibración), como en la web.
    }

    private func acciones(_ t: ModeloEntreno.Tarjeta, _ lector: ScrollViewProxy) -> some View {
        let puede = t.puedeSustituir || t.efectivo.sustituido
        let disposicion = letraDeLaVista.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Espacio.s)) : AnyLayout(HStackLayout(spacing: Espacio.s))
        return VStack(alignment: .leading, spacing: Espacio.xs) {
            disposicion {
                Button { sustituyendo = true } label: {
                    Label(t.efectivo.sustituido ? "Cambiar" : "Sustituir", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!puede)
                Button {
                    withAnimation(.snappy) { lector.scrollTo("comentarios", anchor: .center) }
                    escribiendo = true
                } label: { Label("Comentar", systemImage: "bubble.left.fill") }
                if let v = t.efectivo.ejercicio.videoURL, let url = URL(string: v) {
                    Button { video = url } label: { Label("Video", systemImage: "play.rectangle.fill") }
                }
            }
            .buttonStyle(AccionTarjeta())
            if !puede, t.efectivo.ejercicio.tipo != "calentamiento", t.efectivo.ejercicio.tipo != "cardio" {
                Text(TextosEntreno.sinVariantes).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
    }

    /// Las fotos grandes del movimiento y la nota técnica de Mati, juntas.
    @ViewBuilder
    private func comoSeHace(_ t: ModeloEntreno.Tarjeta) -> some View {
        let inicio = t.efectivo.ejercicio.imagenes?.eccentric.flatMap(URL.init(string:))
        let pico = t.efectivo.ejercicio.imagenes?.concentric.flatMap(URL.init(string:))
        let hayFotos = inicio != nil || pico != nil
        let notas = t.efectivo.ejercicio.notasTecnica.flatMap { $0.isEmpty ? nil : $0 }
        if hayFotos || notas != nil {
            VStack(alignment: .leading, spacing: Espacio.s) {
                Text("Cómo se hace").font(.title3.weight(.bold)).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: Espacio.m) {
                    if hayFotos { ImagenesMovimiento(inicio: inicio, pico: pico) }
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

    /// Los comentarios con Mati sobre este ejercicio (SES-08): van directo, no por la cola.
    private func comentarios(_ t: ModeloEntreno.Tarjeta) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text("Comentarios").font(.title3.weight(.bold)).padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Espacio.s) {
                if t.comentarios.isEmpty {
                    Text(TextosEntreno.sinComentarios).font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(t.comentarios.enumerated()), id: \.element.id) { _, c in
                        let deMati = c.autor == "coach"
                        VStack(alignment: deMati ? .leading : .trailing, spacing: 3) {
                            Text(c.contenido)
                                .font(.subheadline)
                                .foregroundStyle(deMati ? Color.primary : Color.sobreMarca)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(deMati ? Color.campo : Color.marca, in: .rect(cornerRadius: 16, style: .continuous))
                                .textSelection(.enabled)
                            Text("\(deMati ? "Mati" : "Vos") · \(IndiceComentarios.fecha(c.createdAt, zona: .current))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: deMati ? .leading : .trailing)
                        .accessibilityElement(children: .combine)
                    }
                }
                HStack(alignment: .bottom, spacing: Espacio.xs) {
                    TextField("Escribí una nota… (ej: hice plano con mancuernas porque la máquina estaba ocupada)", text: $comentario, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($escribiendo)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color.campo, in: .rect(cornerRadius: 20, style: .continuous))
                    Button(action: comentar) {
                        Group {
                            if enviando { ProgressView() } else { Image(systemName: "arrow.up").font(.system(size: 15, weight: .bold)) }
                        }
                        .foregroundStyle(vacio ? Color.secondary : Color.sobreMarca)
                        .frame(width: 40, height: 40)
                        .background(vacio ? Color.campo : Color.marca, in: .circle)
                        .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(vacio || enviando || motor.demo)
                    .accessibilityLabel("Enviar comentario")
                }
            }
            .tarjeta()
        }
        .id("comentarios")
    }

    private var vacio: Bool { comentario.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Marcar completo (con todas las series), "Terminé este ejercicio" o reabrir; con el ejercicio hecho, el
    /// siguiente pendiente a un toque (ENT-17).
    @ViewBuilder
    private func cierre(_ t: ModeloEntreno.Tarjeta) -> some View {
        let terminal = EstadosEjercicio.terminales.contains(t.estado)
        let todas = !t.filas.isEmpty && t.confirmadas == t.filas.count
        VStack(spacing: Espacio.s) {
            if terminal {
                if let sig = motor.dia.expandido, sig != lugar, let e = motor.dia.ejercicio(sig) {
                    Button { abrir(sig) } label: {
                        Label("Siguiente: \(NombreEjercicio(motor.efectivo(e).ejercicio.nombre).principal)", systemImage: "arrow.right")
                            .labelStyle(TituloYFlecha())
                    }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("siguiente-ejercicio")
                }
                Button {
                    Task { await motor.reabrir(lugar) }
                } label: { Label("Reabrir ejercicio", systemImage: "pencil") }
                .buttonStyle(BotonSecundario())
            } else if t.filas.isEmpty {
                // Sin series (cardio, por tiempo): se marca hecho directamente.
                Button { terminar() } label: { Label("Terminé este ejercicio", systemImage: "checkmark") }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("termine-ejercicio")
            } else {
                Button {
                    Task { if let c = await motor.marcarCompleto(lugar) { alCompletarDia(c) } }
                } label: {
                    Label(todas ? "Marcar ejercicio completo" : "Confirmá las series para completar", systemImage: "checkmark")
                }
                .buttonStyle(BotonMarca())
                .disabled(!todas)
                .accessibilityIdentifier("marcar-completo")

                Button("Terminé este ejercicio") { terminar() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("termine-ejercicio")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Espacio.xs)
        .sensoryFeedback(.success, trigger: terminal) { _, nuevo in nuevo }
        .animation(.snappy, value: terminal)
    }

    @Environment(Preguntador.self) private var preguntador

    private func terminar() {
        Task {
            if let c = await motor.terminar(lugar, preguntar: { await preguntador.preguntar($0) }) { alCompletarDia(c) }
        }
    }

    private func comentar() {
        let texto = comentario
        escribiendo = false
        enviando = true
        Task {
            let ok = await motor.comentar(lugar, texto)
            enviando = false
            if ok { comentario = "" } else { falloComentario = true }
        }
    }

    /// Al entrar: la card queda abierta (pide el historial y marca leídos los comentarios). En la demo de las capturas
    /// (`-series N`) se cargan N series, que la demo no escribe en ningún lado.
    private func abrirCard() async {
        if motor.dia.expandido != lugar {
            await motor.tocarCard(lugar)
        } else {
            // "Siguiente" abre la card que el motor dejó abierta al completar la anterior: `tocarCard` la cerraría, así
            // que se hace lo mismo que al abrirla, comentarios leídos e historial (lo encontró el agente de Android).
            await motor.marcarLeidos(lugar)
            await motor.pedirHistorial(lugar)
        }
        guard motor.demo, !demoHecha, DemoUI.seriesHechas > 0 else { return }
        demoHecha = true
        let n = min(DemoUI.seriesHechas, motor.dia.ejercicios[lugar]?.series.count ?? 0)
        let reps = Progresiones.pauta(motor.dia.ejercicio(lugar) ?? Ejercicio(id: lugar, nombre: ""), semana: motor.semana).reps
        let tope = (reps ?? "10").split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.max() ?? 10
        for i in 0..<n {
            motor.escribir(lugar, i, campo: "reps", valor: String(max(tope - i, 1)))
            motor.escribir(lugar, i, campo: "kg", valor: "57.5")
            await motor.elegirRIR(lugar, i, i == 0 ? 1 : 0)
            _ = await motor.confirmarSerie(lugar, i) { _ in true }
        }
        if DemoUI.sinDescanso { motor.saltarDescanso() }
    }
}

private struct URLVideo: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// "Fijado" (vale para las próximas semanas) o "Solo hoy".
struct InsigniaSustitucion: View {
    let fijado: Bool

    var body: some View {
        Label(fijado ? "Fijado" : "Solo hoy", systemImage: fijado ? "lock.fill" : "arrow.left.arrow.right")
            .labelStyle(EtiquetaCompacta())
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.marcaTexto)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.marcaSuave, in: .capsule)
            .accessibilityLabel(fijado ? "Sustitución fijada para las próximas semanas" : "Sustituido solo por hoy")
    }
}

/// Título con la flecha a la derecha ("Siguiente: Remo →", "Pasar a la semana 6 →").
struct TituloYFlecha: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.subheadline.weight(.bold))
        }
    }
}

// MARK: - Piezas

/// La pauta de la semana como métricas, no como chips: series × reps, RIR y descanso, con el número en Archivo.
private struct MetricasPauta: View {
    let pauta: Pauta
    /// "2:30", como lo arma el motor.
    let descanso: String?
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
        if let d = descanso, !d.isEmpty, d != "0:00" { m.append(Metrica(titulo: "Descanso", valor: d)) }
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
