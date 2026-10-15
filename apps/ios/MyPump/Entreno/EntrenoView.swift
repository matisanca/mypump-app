import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Entreno: el día elegido con su progreso, el cronómetro de la sesión, los bloques y cada ejercicio, avanzar de semana
/// y cerrar el día. Todo sale del motor (`ModeloEntreno`, que arma `ModeloApp`). Arriba, el título del día en Archivo;
/// al bajar, el título pasa chico a la barra. Sin rutina (o sin poder traerla), lo dice como Dieta.
struct EntrenoView: View {
    /// Las muestras quedan para las demás pestañas; Entreno ya usa el motor.
    let datos: Muestras
    @Environment(Entrenamiento.self) private var entrenamiento
    @State private var modelo = Proveedor.modelo
    @State private var ruta: [String] = []
    @State private var preguntador = Preguntador()

    var body: some View {
        NavigationStack(path: $ruta) {
            Group {
                switch pantalla {
                case .dia(let m):
                    // Con cuenta y un motor de ejemplo (Mati todavía no publicó el plan): el aviso de la web (ACC-08).
                    ListaEntreno(motor: m, deEjemplo: m.demo && !modelo.esDemo, alCompletarDia: completoDia)
                case .sinRed:
                    // Un corte dejó afuera la rutina y no había copia guardada.
                    ContentUnavailableView {
                        Label("No pudimos traer tu rutina", systemImage: "wifi.slash")
                    } description: {
                        Text("Se cortó la conexión. Probá de nuevo cuando tengas señal.")
                    } actions: {
                        Button("Reintentar") { Task { await modelo.cargar() } }
                            .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    }
                case .sinRutina:
                    ScrollView {
                        ContentUnavailableView("Todavía no hay rutina", systemImage: "dumbbell",
                                               description: Text("Cuando Mati publique tu rutina, la vas a ver acá."))
                            .padding(.top, 80)
                    }
                    .refreshable { await modelo.cargar() }
                case .cargando:
                    ScrollView { EsqueletoEntreno().padding(.horizontal, Espacio.m).anchoLectura() }
                        .scrollDisabled(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fondo)
            .navigationDestination(for: String.self) { lugar in
                if let m = entrenamiento.motor {
                    EjercicioView(motor: m, lugar: lugar, alCompletarDia: completoDia) { siguiente in
                        // El siguiente pendiente reemplaza al que se terminó (como la web abre la card siguiente).
                        ruta = [siguiente]
                    }
                    // Otro ejercicio es otra pantalla: arriba de todo y sin lo que quedó escrito en el anterior.
                    .id(lugar)
                }
            }
        }
        .environment(preguntador)
        .preguntas(preguntador)
        .onChange(of: entrenamiento.motor?.dia.dia.id, initial: true) { _, _ in abrirParaCapturas() }
    }

    private enum Pantalla { case dia(ModeloEntreno), cargando, sinRed, sinRutina }

    /// El día del motor; sin motor, cargando, sin red o sin rutina. Las capturas (`-estado`) fuerzan cada uno.
    private var pantalla: Pantalla {
        switch DemoUI.estado {
        case .cargando: return .cargando
        case .error: return .sinRed
        case .vacio: return .sinRutina
        case nil: break
        }
        // Una rutina publicada sin ningún ejercicio tampoco se puede usar: "Todavía no hay rutina", como sin rutina
        // (D11+; Android ya lo hacía así, lo encontró su agente de Entreno).
        if let m = entrenamiento.motor { return m.usable ? .dia(m) : .sinRutina }
        guard modelo.fase == .listo else { return .cargando }
        return modelo.sinRedEn.contains(.rutina) ? .sinRed : .sinRutina
    }

    /// "🎉 ¡Día completado!" medio segundo después (como la web); con un día siguiente, ofrece ir.
    private func completoDia(_ c: ModeloEntreno.DiaCompletado) {
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            let ir = await preguntador.preguntar(c.pregunta)
            guard ir, let sig = c.siguiente?.id, let m = entrenamiento.motor else { return }
            ruta = []
            await m.cambiarDia(sig)
        }
    }

    /// Capturas: `-abrir ejercicio` entra al primer ejercicio de trabajo del día.
    private func abrirParaCapturas() {
        guard !DemoUI.abrioYa.contains("ejercicio"), DemoUI.abrir == "ejercicio", let m = entrenamiento.motor else { return }
        guard let e = m.dia.lista.first(where: { $0.tipo == "compuesto" }) ?? m.dia.lista.first else { return }
        DemoUI.abrioYa.insert("ejercicio")
        ruta = [e.id]
    }
}

/// El día del motor.
private struct ListaEntreno: View {
    let motor: ModeloEntreno
    let deEjemplo: Bool
    let alCompletarDia: (ModeloEntreno.DiaCompletado) -> Void
    @Environment(Preguntador.self) private var preguntador
    @State private var tituloEnBarra = false
    @State private var cerrando = false
    @State private var trabajando = false
    @ScaledMetric(relativeTo: .title) private var ladoAnillo: CGFloat = 68
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private var titulo: String {
        let t = Bonito.titulo(motor.dia.dia.nombre)
        return t.isEmpty ? "Día \(motor.numero(motor.dia.dia))" : t
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                cabecera
                if deEjemplo {
                    AvisoProgresion(icono: "exclamationmark.triangle.fill",
                                    texto: Text(Bonito.sinEmoji(TextosEntreno.demo).replacingOccurrences(of: "Modo demo — ", with: "")),
                                    tono: .alerta)
                }
                BannerRevision()
                // Con un solo día no hay nada que elegir: la web no lo muestra (`renderDayPicker`).
                if motor.dias.count > 1 { SelectorDias(motor: motor) }
                if motor.vacio {
                    diaVacio
                } else {
                    cuerpo
                }
                PieRespaldo(origen: .entreno)
                    .padding(.top, Espacio.xs)
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .scrollDismissesKeyboard(.interactively)
        // Como Dieta, la carga entera: trae la rutina si Mati la republicó (hallazgo 6).
        .refreshable { await Proveedor.modelo.refrescarEntreno() }
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(titulo).font(.headline)
                    Text("Semana \(motor.semanaMostrada) de \(motor.totalMostrado)")
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                .opacity(tituloEnBarra ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: tituloEnBarra)
                .accessibilityHidden(!tituloEnBarra)
            }
        }
        .sheet(isPresented: $cerrando) { CerrarDiaView(motor: motor) }
    }

    // MARK: Cabecera

    private var cabecera: some View {
        let d = motor.dia.dia
        let total = motor.totalEjercicios, hechos = motor.hechos
        let cerrado = motor.dia.diaFinalizado || motor.hecho(d)
        // Con letra de accesibilidad el anillo va abajo: al costado le dejaba al texto un tercio del ancho y cortaba las
        // palabras ("cerra-do").
        let apilada = tamañoLetra.isAccessibilitySize
        let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.m))
                                  : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.m))
        return disposicion {
            VStack(alignment: .leading, spacing: 6) {
                Text("Día \(motor.numero(d)) · Semana \(motor.semanaMostrada) de \(motor.totalMostrado)").textoCeja()
                Text(titulo)
                    .font(.tituloDia)
                    // Con letra de accesibilidad el nombre del día baja de renglón en vez de cortarse.
                    .lineLimit(tamañoLetra.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(tamañoLetra.isAccessibilitySize ? 1 : 0.6)
                    .accessibilityAddTraits(.isHeader)
                Label(cerrado ? "Día cerrado esta semana" : (total == 1 ? "1 ejercicio" : "\(total) ejercicios"),
                      systemImage: cerrado ? "checkmark.seal.fill" : "list.bullet")
                    .labelStyle(EtiquetaCompacta())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(cerrado ? Color.marcaTexto : Color.secondary)
            }
            if !apilada { Spacer(minLength: 0) }
            AnilloProgreso(fraccion: Double(hechos) / Double(max(total, 1)), grosor: 7) {
                VStack(spacing: -2) {
                    Text("\(hechos)").font(.numeroChico).contentTransition(.numericText())
                    Text("de \(total)").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(8)
            }
            .frame(width: min(ladoAnillo, 108), height: min(ladoAnillo, 108))
            .animation(.snappy, value: hechos)
            .accessibilityElement()
            .accessibilityLabel("\(hechos) de \(total) ejercicios hechos")
        }
        .padding(.top, Espacio.xs)
        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 8 } action: { tituloEnBarra = $0 }
    }

    // MARK: Cuerpo del día

    @ViewBuilder
    private var cuerpo: some View {
        let banner = motor.banner
        if banner.cambian > 0 {
            AvisoProgresion(icono: "chart.line.uptrend.xyaxis",
                            texto: Text("Esta semana \(Text(banner.cambian == 1 ? "1 ejercicio cambia" : "\(banner.cambian) ejercicios cambian").bold()) carga o volumen. Mirá el detalle al abrir cada uno."))
        } else if banner.calibracion {
            AvisoProgresion(icono: "scope",
                            texto: Text("Semana de calibración: llegá cerca del fallo muscular y encontrá tu peso real. Las reps son una guía (±2-3): no te guardes reps."))
        }

        // Con el día cerrado o todo hecho no hay cronómetro (está la tarjeta de cierre): ni su lugar en la pila.
        if !motor.todoHecho {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                cronometro(motor.cronometro())
            }
        }

        ForEach(motor.bloques, id: \.indice) { b in
            BloqueEjercicios(motor: motor, bloque: b, primerNumero: primerNumero(b.indice))
        }

        if motor.todoHecho {
            tarjetaCierre
        } else {
            resumenSesion
        }

        if motor.puedeAvanzar {
            Button(action: avanzar) {
                Label(Bonito.boton(motor.botonAvanzar), systemImage: "arrow.right").labelStyle(TituloYFlecha())
            }
            .buttonStyle(BotonSecundario(tono: .marcaTexto))
            .disabled(trabajando)
            .accessibilityIdentifier("avanzar-semana")
        } else if motor.puedeEmpezarBloque {
            VStack(spacing: Espacio.xs) {
                Button(action: empezarBloque) {
                    Label(Bonito.boton(Bonito.sinEmoji(SemanaEntreno.botonBloqueNuevo)), systemImage: "sparkles")
                }
                .buttonStyle(BotonMarca())
                .disabled(trabajando)
                Text(SemanaEntreno.detalleBloqueNuevo).font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func cronometro(_ c: TiempoEntreno.Cronometro?) -> some View {
        switch c {
        case .empezar:
            VStack(spacing: Espacio.xs) {
                Button {
                    Task { await motor.empezar() }
                } label: {
                    Label(TextosEntreno.empezar, systemImage: "play.fill")
                }
                .buttonStyle(BotonMarca())
                .sensoryFeedback(.impact(weight: .medium), trigger: motor.inicioSesion)
                .accessibilityIdentifier("empezar-entrenamiento")
                Text("Arranca el cronómetro de la sesión. O empezá directo: corre solo con tu primera serie.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        case .enCurso(let texto, let porBoton):
            CronometroSesion(texto: texto, detalle: porBoton ? nil : "Arrancó con tu primera serie") { cerrando = true }
        case .sinCerrar:
            VStack(alignment: .leading, spacing: Espacio.s) {
                Label("Sin cerrar", systemImage: "clock.badge.exclamationmark")
                    .labelStyle(IconoTeñido(color: .alerta))
                    .font(.headline)
                Text("Quedó abierta de antes. No te preocupes, no perdiste nada.").font(.subheadline).foregroundStyle(.secondary)
                Button("Empezar de nuevo") { motor.reiniciarCronometro() }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
            }
            .tarjeta()
        case nil:
            EmptyView()
        }
    }

    /// Todo hecho o el día cerrado: "Sesión completa" o "Día cerrado", cuántos ejercicios quedaron listos, el resumen
    /// y, si falta, cerrarla.
    private var tarjetaCierre: some View {
        let r = motor.resumen
        let finalizado = motor.dia.diaFinalizado
        return VStack(spacing: Espacio.m) {
            VStack(spacing: 4) {
                Label(finalizado ? "Día cerrado" : "Sesión completa",
                      systemImage: finalizado ? "checkmark.seal.fill" : "party.popper.fill")
                    .labelStyle(IconoTeñido(color: .marcaTexto))
                    .textoCeja()
                Text("\(motor.hechos)/\(motor.totalEjercicios) ejercicios listos")
                    .font(.title3.weight(.bold))
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 0) {
                celda("Series", "\(r.series)")
                Divider().frame(height: 36)
                celda("Volumen", "\(JS.texto(r.volumenRedondeado)) kg")
                Divider().frame(height: 36)
                celda("Duración", motor.minutos.map { "\($0) min" } ?? "—")
            }
            if finalizado {
                Label("Tu sesión de hoy quedó guardada.", systemImage: "checkmark.icloud.fill")
                    .labelStyle(IconoTeñido(color: .marcaTexto))
                    .font(.subheadline.weight(.semibold))
            } else {
                Button { cerrando = true } label: { Label("Cerrar sesión de hoy", systemImage: "flag.checkered") }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("cerrar-sesion")
            }
        }
        .tarjeta()
    }

    /// El pie mientras se entrena: hechos, tiempo y lo que resta, y cerrar (habilitado con la sesión iniciada).
    private var resumenSesion: some View {
        let restan = motor.totalEjercicios - motor.hechos
        return VStack(spacing: Espacio.m) {
            HStack(spacing: 0) {
                celda("Hechos", "\(motor.hechos)/\(motor.totalEjercicios)")
                Divider().frame(height: 36)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    celda("Tiempo", motor.minutos.map { "\($0) min" } ?? "—")
                }
                Divider().frame(height: 36)
                celda("Restan", "\(restan) ej")
            }
            Button { cerrando = true } label: {
                Label("Cerrar sesión de hoy", systemImage: "flag.checkered")
            }
            .buttonStyle(BotonSecundario())
            .disabled(!motor.cierreHabilitado)
            .accessibilityIdentifier("cerrar-sesion")
        }
        .tarjeta()
    }

    private func celda(_ titulo: String, _ valor: String) -> some View {
        VStack(spacing: 2) {
            Text(titulo).textoCeja()
            Text(valor).font(.numeroChico).monospacedDigit().contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var diaVacio: some View {
        ContentUnavailableView {
            Label("Día sin ejercicios", systemImage: "figure.cooldown")
        } description: {
            Text(TextosEntreno.diaVacio)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espacio.l)
    }

    private func primerNumero(_ indice: Int) -> Int {
        motor.dia.dia.bloques.prefix(indice).reduce(0) { $0 + $1.ejercicios.count } + 1
    }

    // MARK: Semana y bloque

    /// "Pasar a Semana N" con la confirmación de la web (cambia si el día está incompleto). Si no salió, "Recargar".
    private func avanzar() {
        Task {
            guard let p = motor.preguntaAvanzar, await preguntador.preguntar(p) else { return }
            trabajando = true
            defer { trabajando = false }
            if case .error(let e) = await motor.avanzarSemana(), await preguntador.preguntar(e), e.confirmar == "Recargar" {
                await motor.recargar()
            }
        }
    }

    /// "Empezar bloque nuevo" (ENT-15).
    private func empezarBloque() {
        Task {
            guard await preguntador.preguntar(SemanaEntreno.preguntaBloqueNuevo) else { return }
            trabajando = true
            defer { trabajando = false }
            if case .error(let e) = await motor.empezarBloqueNuevo(), await preguntador.preguntar(e), e.confirmar == "Recargar" {
                await motor.recargar()
            }
        }
    }
}

// MARK: - Piezas

/// Aviso teñido arriba del día ("Esta semana 7 ejercicios cambian carga o volumen").
private struct AvisoProgresion: View {
    let icono: String
    let texto: Text
    var tono: Color = .marcaTexto

    var body: some View {
        HStack(alignment: .top, spacing: Espacio.s) {
            Image(systemName: icono)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tono)
                .frame(width: 22)
            texto.font(.subheadline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tono == .marcaTexto ? Color.marcaSuave : tono.opacity(0.12),
                    in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// La sesión en curso: punto que late, "EN CURSO" y el tiempo (reemplaza al botón de empezar).
private struct CronometroSesion: View {
    let texto: String
    let detalle: String?
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
                Text(texto)
                    .font(.numeroMediano)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let detalle {
                    Text(detalle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Cerrar", systemImage: "flag.checkered", action: cerrar)
                .buttonStyle(BotonSecundario(compacto: true))
        }
        .tarjeta()
        .accessibilityElement(children: .contain)
    }
}

/// Selector de días: cápsulas con "DÍA n" y la primera palabra del nombre. La elegida va invertida y se desliza; las
/// cerradas esta semana llevan el tilde de marca, y las que tienen comentarios de Mati sin leer, el globo.
struct SelectorDias: View {
    let motor: ModeloEntreno
    @Namespace private var ns

    var body: some View {
        ScrollViewReader { lector in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espacio.xs) {
                    ForEach(Array(motor.dias.enumerated()), id: \.offset) { i, d in
                        boton(d, i)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollClipDisabled()
            .onAppear { if let id = motor.dia.dia.id { lector.scrollTo(id, anchor: .center) } }
        }
        .sensoryFeedback(.selection, trigger: motor.dia.dia.id)
    }

    private func boton(_ d: Dia, _ i: Int) -> some View {
        let activo = d.id == motor.dia.dia.id
        let hecho = motor.hecho(d)
        let mensajes = motor.sinLeer(d)
        let corto = Bonito.titulo(motor.nombreCorto(d))
        return Button {
            guard let id = d.id else { return }
            Task { await motor.cambiarDia(id) }
        } label: {
            VStack(spacing: 1) {
                Text("Día \(motor.numero(d))")
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .opacity(activo ? 0.65 : 1)
                    .foregroundStyle(activo ? Color(uiColor: .systemBackground) : Color.secondary)
                Text(corto.isEmpty ? "Día" : corto)
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
                // Los dos a la vez, como la web (ENT-01): un día cerrado puede tener comentarios nuevos de Mati.
                HStack(spacing: 2) {
                    if mensajes > 0 {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Color.peligro, in: .circle)
                    }
                    if hecho {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.sobreMarca)
                            .frame(width: 16, height: 16)
                            .background(Color.marca, in: .circle)
                    }
                }
                .offset(x: 5, y: -5)
            }
        }
        .buttonStyle(.plain)
        .id(d.id)
        .accessibilityLabel("Día \(motor.numero(d)), \(corto)\(hecho ? ", cerrado esta semana" : "")\(mensajes > 0 ? ", \(mensajes) comentarios sin leer" : "")")
        .accessibilityAddTraits(activo ? .isSelected : [])
    }
}

/// Un bloque: "Bloque 1 · Espalda · 0/3" y sus ejercicios en una sola tarjeta, separados por líneas como una lista.
private struct BloqueEjercicios: View {
    let motor: ModeloEntreno
    let bloque: ModeloEntreno.BloqueDelDia
    let primerNumero: Int

    var body: some View {
        let total = bloque.ejercicios.count
        VStack(alignment: .leading, spacing: Espacio.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Bloque \(bloque.indice)").textoCeja()
                HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                    Text(bloque.nombre.isEmpty ? "Bloque \(bloque.indice)" : bloque.nombre.enOracion)
                        .font(.title3.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Espacio.xs)
                    Text("\(bloque.hechos)/\(total)")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(bloque.hechos == total ? Color.marcaTexto : Color.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                ForEach(Array(bloque.ejercicios.enumerated()), id: \.element.id) { j, e in
                    NavigationLink(value: e.id) {
                        FilaEjercicio(motor: motor, ejercicio: e, numero: primerNumero + j)
                    }
                    .buttonStyle(FilaPresionable())
                    .accessibilityIdentifier("fila-ejercicio-\(primerNumero + j)")
                    if j < total - 1 {
                        Divider().padding(.leading, 90)
                    }
                }
            }
            .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .superficieTarjeta()
        }
    }
}

/// La card cerrada de un ejercicio (ENT-10): miniatura con su número o estado, sustitución (fijada o solo hoy),
/// "manual", comentarios sin leer, la pauta de la semana en chips, puntos por serie, y la última vez y el récord (o
/// "Primera vez"). Con letra de accesibilidad, la miniatura pasa arriba y los chips saltan de renglón.
struct FilaEjercicio: View {
    let motor: ModeloEntreno
    /// El ejercicio del PLAN en ese lugar (el efectivo puede ser un sustituto).
    let ejercicio: Ejercicio
    let numero: Int
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let lugar = ejercicio.id
        let ef = motor.efectivo(ejercicio)
        let pauta = Progresiones.pauta(ef.ejercicio, semana: motor.semana)
        let nombre = NombreEjercicio(ef.ejercicio.nombre)
        let estado = motor.dia.estado(lugar)
        let series = motor.dia.ejercicios[lugar]?.series ?? []
        let hechas = series.filter(\.confirmada).count
        let manual = estado == "completo_sin_datos" && motor.dia.meta[lugar]?.manual == true
        let mensajes = motor.comentarios.sinLeer(ejercicio: lugar)
        let tipo = ef.ejercicio.tipo
        let disposicion = tamañoLetra.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))

        disposicion {
            VStack(spacing: Espacio.xs) {
                Miniatura(url: ef.ejercicio.imagenes?.concentric ?? ef.ejercicio.imagenes?.eccentric, tipo: tipo, lado: 60)
                    .overlay(alignment: .topLeading) {
                        MarcaNumero(numero: numero, estado: estado).offset(x: -7, y: -7)
                    }
                if series.count > 1, tipo != "cardio" {
                    PuntosSeries(total: series.count, hechas: hechas)
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
                    if ef.sustituido { InsigniaSustitucion(fijado: ef.fijado) }
                    if manual { Chip(texto: "Manual", icono: "hand.raised.fill") }
                    if mensajes > 0 { Chip(texto: "\(mensajes)", icono: "bubble.left.fill", tono: .peligro) }
                    if tipo == "calentamiento" || tipo == "cardio" {
                        Chip(texto: tipo == "cardio" ? "Cardio" : "Calent.", icono: "flame.fill", tono: .alerta)
                    }
                    if tipo == "cardio" || pauta.series == nil {
                        Chip(texto: pauta.reps ?? "—")
                    } else if let s = pauta.series {
                        Chip(texto: "\(s) × \(pauta.reps ?? "—")")
                    }
                    if let rir = pauta.rir { Chip(texto: "RIR \(rir)") }
                    Chip(texto: TiempoEntreno.fmtTiempo(Double(ejercicio.descansoSegundos ?? NormalizacionRutina.descansoPorDefecto)), icono: "timer")
                }
                .padding(.top, 5)
                // El cardio y lo que va por tiempo no tienen "última vez" que buscar.
                historial(lugar, porTiempo: tipo == "cardio" || pauta.series == nil).padding(.top, 4)
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
        .accessibilityLabel("Ejercicio \(numero): \(ef.ejercicio.nombre)")
        .accessibilityValue(valorAccesible(lugar, estado: estado, hechas: hechas, total: series.count, ef: ef, manual: manual,
                                           mensajes: mensajes, pauta: pauta))
    }

    /// Lo que lee VoiceOver: el estado y lo mismo que se ve en la card (en la web se lee su texto). La etiqueta fija de
    /// arriba tapaba todo lo demás: la sustitución, los mensajes, la pauta y el récord no se oían.
    private func valorAccesible(_ lugar: String, estado: String, hechas: Int, total: Int, ef: EjercicioEfectivo, manual: Bool,
                                mensajes: Int, pauta: Pauta) -> String {
        let tipo = ef.ejercicio.tipo
        var partes = [Self.estadoAccesible(estado, hechas: hechas, de: total)]
        if ef.sustituido { partes.append(ef.fijado ? "sustitución fijada" : "sustituido solo por hoy") }
        if manual { partes.append("marcado a mano") }
        if mensajes > 0 { partes.append(mensajes == 1 ? "1 mensaje sin leer" : "\(mensajes) mensajes sin leer") }
        if tipo == "calentamiento" { partes.append("calentamiento") } else if tipo == "cardio" { partes.append("cardio") }
        let porTiempo = tipo == "cardio" || pauta.series == nil
        if porTiempo {
            if let r = pauta.reps { partes.append(r) }
        } else if let s = pauta.series {
            partes.append("\(s) series de \(pauta.reps ?? "—")")
        }
        if let rir = pauta.rir { partes.append("RIR \(rir)") }
        partes.append("descanso \(TiempoEntreno.fmtTiempo(Double(ejercicio.descansoSegundos ?? NormalizacionRutina.descansoPorDefecto)))")
        let ultima = motor.dia.ultimaVez(lugar, ahora: .now)
        let record = motor.dia.record(lugar)
        if let u = ultima { partes.append("última vez \(Bonito.carga(u.valor)), \(u.cuando)") }
        if let r = record { partes.append("récord \(Bonito.carga(r))") }
        if ultima == nil && record == nil && !porTiempo && !motor.historialCargando.contains(lugar) {
            partes.append("primera vez con este ejercicio")
        }
        return partes.joined(separator: ", ")
    }

    @ViewBuilder
    private func historial(_ lugar: String, porTiempo: Bool) -> some View {
        let ultima = motor.dia.ultimaVez(lugar, ahora: .now)
        let record = motor.dia.record(lugar)
        if ultima != nil || record != nil {
            FilaFluida(espaciado: 8, interlineado: 2) {
                if let u = ultima {
                    // En gris secundario y el valor en negro: en terciario no se leía en el gimnasio (la auditoría de
                    // accesibilidad lo daba en 1,7:1 de contraste).
                    Text("Última: \(Text(Bonito.partir(u.valor).principal).foregroundStyle(.primary)) · \(u.cuando)")
                        .foregroundStyle(.secondary)
                }
                if let r = record {
                    Label(Bonito.partir(r).principal, systemImage: "trophy.fill")
                        .labelStyle(EtiquetaCompacta())
                        .foregroundStyle(Color.record)
                        .fontWeight(.semibold)
                        .accessibilityLabel("Récord: \(Bonito.carga(r))")
                }
            }
            .font(.caption)
        } else if porTiempo {
            EmptyView()
        } else if motor.historialCargando.contains(lugar) {
            Text("Buscando tu última vez…").font(.caption).foregroundStyle(.secondary)
        } else {
            Label("Primera vez con este ejercicio", systemImage: "sparkles")
                .labelStyle(EtiquetaCompacta())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func estadoAccesible(_ estado: String, hechas: Int, de total: Int) -> String {
        switch estado {
        case "completo": return "Completo"
        case "completo_sin_datos": return "Terminado sin series"
        case "saltado": return "Saltado"
        default: return hechas > 0 ? "\(hechas) de \(total) series" : "Pendiente"
        }
    }
}

/// El número del ejercicio en la esquina de la miniatura; tilde de marca cuando está completo.
private struct MarcaNumero: View {
    let numero: Int
    let estado: String
    @ScaledMetric(relativeTo: .caption2) private var lado: CGFloat = 22

    var body: some View {
        ZStack {
            switch estado {
            case "completo":
                Circle().fill(Color.marca)
                Image(systemName: "checkmark").font(.system(size: lado * 0.45, weight: .heavy)).foregroundStyle(Color.sobreMarca)
            case "completo_sin_datos":
                Circle().fill(Color.tarjeta)
                Image(systemName: "checkmark").font(.system(size: lado * 0.45, weight: .heavy)).foregroundStyle(.secondary)
            case "saltado":
                Circle().fill(Color.tarjeta)
                Image(systemName: "minus").font(.system(size: lado * 0.45, weight: .heavy)).foregroundStyle(.secondary)
            default:
                Circle().fill(Color.tarjeta)
                Text("\(numero)").font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(.primary)
            }
        }
        .frame(width: lado, height: lado)
        .overlay { Circle().strokeBorder(Color.borde, lineWidth: 1) }
        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        .symbolEffect(.bounce, value: estado)
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
