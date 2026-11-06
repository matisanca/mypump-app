import SwiftUI
import EventKit
import EventKitUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

// La agenda de la entrega al final de «Tu guía» (2.2.0). El servidor decide: acá solo se pide, se muestra y se reserva.
// Sin la 021 (`vistaAgenda == .nada`) no se pinta nada: la guía queda como en la 2.1.0.

/// El final de la guía: el contador de los obligatorios que faltan y la tarjeta de la agenda en el estado que toque.
struct AgendaEntrega: View {
    let modelo: ModeloGuia
    /// «Ir al próximo video» y el contador: salta al primer obligatorio que falta.
    let irAlVideo: (ClipGuia) -> Void
    @State private var elegido: ReglasAgenda.Chip?
    @State private var paraCalendario: ParaCalendario?
    @Environment(\.openURL) private var abrirURL

    private var zona: TimeZone { AgendaUI.zona }

    var body: some View {
        let vista = modelo.vistaAgenda
        if vista != .nada {
            VStack(spacing: Espacio.s) {
                if let n = contador(vista), let c = ReglasAgenda.primeroQueFalta(modelo.guia) {
                    Button { irAlVideo(c) } label: {
                        Label(ReglasAgenda.textoContador(n), systemImage: "play.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.marcaTexto)
                    .accessibilityHint("Va al primer video que te falta")
                    .accessibilityIdentifier("agenda-contador")
                }
                tarjeta(vista)
            }
            .id("agenda")
            .sheet(item: $elegido) { c in
                HojaConfirmar(texto: ReglasAgenda.textoConfirmar(c, zona: zona),
                              confirmar: { elegido = nil; Task { await modelo.agenda.reservar(c.franja) } },
                              otro: { elegido = nil })
            }
            .sheet(item: $paraCalendario) { p in
                AgregarAlCalendario(reserva: p.reserva).ignoresSafeArea()
            }
            .onChange(of: modelo.agenda.anuncios) { _, _ in
                AccessibilityNotification.Announcement(modelo.agenda.anuncio).post()
            }
        }
    }

    /// El contador va con la agenda bloqueada o sin autorizar, si falta alguno.
    private func contador(_ v: ReglasAgenda.Vista) -> Int? {
        switch v {
        case .noAutorizada(let n) where n > 0, .bloqueada(let n) where n > 0: n
        default: nil
        }
    }

    @ViewBuilder private func tarjeta(_ v: ReglasAgenda.Vista) -> some View {
        switch v {
        case .nada:
            EmptyView()
        case .noAutorizada:
            Bloqueada(texto: ReglasAgenda.textoNoAutorizada, sinRed: modelo.agenda.desdeCache, accion: nil)
        case .bloqueada(let n):
            Bloqueada(texto: ReglasAgenda.textoBloqueada(n), sinRed: modelo.agenda.desdeCache,
                      accion: n > 0 ? ReglasAgenda.primeroQueFalta(modelo.guia).map { c in { irAlVideo(c) } } : nil,
                      habilitando: n == 0)
        case .franjas(let aviso):
            Franjas(dias: ReglasAgenda.dias(modelo.agenda.agenda?.franjas ?? [], zona: zona), zona: zona, aviso: aviso,
                    sinRed: modelo.agenda.desdeCache) { elegido = $0 }
        case .sinFranjas(let aviso):
            CajaAgenda(sinRed: modelo.agenda.desdeCache) {
                Encabezado(icono: "calendar", titulo: "Agendá tu entrega")
                if let aviso { AvisoAgenda(texto: aviso.texto) }
                Text(ReglasAgenda.textoSinFranjas).font(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agenda-sin-franjas")
            }
        case .reservando:
            CajaAgenda(sinRed: modelo.agenda.desdeCache) {
                Encabezado(icono: "calendar", titulo: "Agendá tu entrega")
                HStack(spacing: Espacio.s) {
                    ProgressView()
                    Text(ReglasAgenda.textoReservando).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agenda-reservando")
            }
        case .confirmada(let r, let aviso):
            Confirmada(reserva: r, zona: zona, aviso: aviso, sinRed: modelo.agenda.desdeCache,
                       entrar: { if let u = r.meetUrl { abrirURL(u) } },
                       calendario: { paraCalendario = ParaCalendario(reserva: r) })
                // En la franja, con la guía abierta: la agenda cada 30 s hasta que Mati abre la sala.
                .task(id: r) { await modelo.agenda.vigilarSala() }
        }
    }
}

// MARK: - Piezas

private struct ParaCalendario: Identifiable {
    let id = UUID()
    let reserva: ReservaAgenda
}

/// La caja de la agenda: la tarjeta de siempre, con «Sin conexión» arriba si lo que se ve es la copia.
private struct CajaAgenda<Contenido: View>: View {
    var fondo: Color = .tarjeta
    let sinRed: Bool
    @ViewBuilder let contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            if sinRed {
                LineaConIcono(texto: "Sin conexión", icono: "wifi.slash")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("agenda-sin-red")
            }
            contenido
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .superficieTarjeta(radio: Radio.control + 6, color: fondo)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("agenda")
    }
}

private struct Encabezado: View {
    let icono: String
    let titulo: String
    var tono: Color = .primary

    var body: some View {
        Label {
            Text(titulo).font(.headline)
        } icon: {
            Image(systemName: icono).foregroundStyle(tono)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Un ícono y un texto que VoiceOver lee como el texto solo (un `Label` con identificador exponía el nombre del símbolo).
private struct LineaConIcono: View {
    let texto: String
    let icono: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icono).accessibilityHidden(true)
            Text(texto).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texto)
    }
}

private struct AvisoAgenda: View {
    let texto: String

    var body: some View {
        LineaConIcono(texto: texto, icono: "exclamationmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.alerta)
            .accessibilityIdentifier("agenda-aviso")
    }
}

/// La gris con candado: sin autorizar, o con videos que faltan («Ir al próximo video»).
private struct Bloqueada: View {
    let texto: String
    let sinRed: Bool
    let accion: (() -> Void)?
    var habilitando = false

    var body: some View {
        CajaAgenda(fondo: .campo, sinRed: sinRed) {
            Encabezado(icono: "lock.fill", titulo: "Agendá tu entrega", tono: .secondary)
            HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                if habilitando { ProgressView().controlSize(.small) }
                Text(texto).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("agenda-bloqueada")
            if let accion {
                Button(action: accion) { Label("Ir al próximo video", systemImage: "play.fill") }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    .accessibilityIdentifier("agenda-ir-al-video")
            }
        }
    }
}

/// Las franjas por día, en la hora del teléfono, como chips. Tocar uno abre la confirmación.
private struct Franjas: View {
    let dias: [ReglasAgenda.Dia]
    let zona: TimeZone
    let aviso: ReglasAgenda.Aviso?
    let sinRed: Bool
    let elegir: (ReglasAgenda.Chip) -> Void

    var body: some View {
        CajaAgenda(sinRed: sinRed) {
            Encabezado(icono: "calendar", titulo: "Agendá tu entrega", tono: .marcaTexto)
            if let aviso { AvisoAgenda(texto: aviso.texto) }
            Text("Elegí un horario para la videollamada. Dura unas 2 horas.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if ReglasAgenda.difiereDeArgentina(dias.flatMap(\.chips).map(\.inicio), zona: zona) {
                LineaConIcono(texto: ReglasAgenda.textoZonaTelefono, icono: "globe.americas")
                    .font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("agenda-zona")
            }
            ForEach(dias) { d in
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(d.titulo.prefix(1).uppercased() + d.titulo.dropFirst())
                        .font(.subheadline.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    FilaFluida(espaciado: Espacio.xs, interlineado: Espacio.xs) {
                        ForEach(d.chips) { c in
                            Button { elegir(c) } label: { Text(c.texto).monospacedDigit() }
                                .buttonStyle(ChipFranja())
                                .accessibilityLabel("\(d.titulo), de \(c.texto)")
                                .accessibilityHint("Abre la confirmación")
                                .accessibilityIdentifier("agenda-franja-\(c.id)")
                        }
                    }
                }
                .padding(.top, Espacio.xxs)
            }
        }
    }
}

private struct ChipFranja: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.marcaTexto)
            .padding(.horizontal, Espacio.m)
            .frame(minHeight: 44)
            .background(Color.marcaSuave, in: .capsule)
            .overlay { Capsule().strokeBorder(Color.marca.opacity(0.35), lineWidth: 1) }
            .contentShape(.capsule)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// La verde: el día y la hora, «Agregar a mi calendario», cómo cambiarla y, con la sala abierta, «Entrar a la videollamada».
private struct Confirmada: View {
    let reserva: ReservaAgenda
    let zona: TimeZone
    let aviso: ReglasAgenda.Aviso?
    let sinRed: Bool
    let entrar: () -> Void
    let calendario: () -> Void

    var body: some View {
        CajaAgenda(fondo: .marcaSuave, sinRed: sinRed) {
            Encabezado(icono: "checkmark.circle.fill", titulo: "Entrega confirmada", tono: .marcaTexto)
            Text(ReglasAgenda.textoConfirmada(reserva, zona: zona) ?? "Tu entrega está confirmada")
                .font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("agenda-confirmada")
            if ReglasAgenda.difiereDeArgentina(ReglasGuia.instante(reserva.inicio).map { [$0] } ?? [], zona: zona) {
                Text(ReglasAgenda.textoZonaTelefono).font(.footnote).foregroundStyle(.secondary)
            }
            if let aviso { Text(aviso.texto).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("agenda-demo") }
            // El cliente nunca entra directo (Mati, 6/11): el botón aparece con la sala abierta o, de respaldo, a la hora
            // de inicio. El día de la entrega, mientras tanto, el aviso. Antes del día, solo la fecha y la hora.
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                if ReglasAgenda.puedeEntrar(reserva, ahora: ctx.date) {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        Text(ReglasAgenda.textoEntrar(reserva, zona: zona))
                            .font(.headline).foregroundStyle(Color.marcaTexto)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("agenda-sala")
                        Button(action: entrar) { Label("Entrar a la videollamada", systemImage: "video.fill") }
                            .buttonStyle(BotonMarca())
                            .accessibilityHint("Abre Google Meet")
                            .accessibilityIdentifier("agenda-entrar")
                    }
                } else if reserva.meetUrl != nil, ReglasAgenda.esHoy(reserva, zona: zona, ahora: ctx.date) {
                    Text(ReglasAgenda.textoEsperandoSala(reserva, zona: zona))
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("agenda-esperando-sala")
                }
            }
            Button(action: calendario) { Label("Agregar a mi calendario", systemImage: "calendar.badge.plus") }
                .buttonStyle(BotonSecundario(tono: .marcaTexto))
                .accessibilityIdentifier("agenda-calendario")
            Text(ReglasAgenda.textoCambiar).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// La hoja de confirmación: sin formularios, «Confirmar» o «Elegir otro».
private struct HojaConfirmar: View {
    let texto: String
    let confirmar: () -> Void
    let otro: () -> Void
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        ScrollView {
            VStack(spacing: Espacio.l) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 44)).foregroundStyle(Color.marca)
                    .accessibilityHidden(true)
                Text(texto)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agenda-hoja-texto")
                VStack(spacing: Espacio.xs) {
                    Button("Confirmar", action: confirmar)
                        .buttonStyle(BotonMarca())
                        .accessibilityIdentifier("agenda-confirmar")
                    Button("Elegir otro", action: otro)
                        .buttonStyle(BotonSecundario(tono: .marcaTexto))
                        .accessibilityIdentifier("agenda-elegir-otro")
                }
            }
            .padding(Espacio.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .presentationDetents(tamañoLetra.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// «Agregar a mi calendario»: `EKEventEditViewController`, que en iOS 17 corre fuera de la app y no pide acceso al
/// calendario. Nada sale del teléfono.
private struct AgregarAlCalendario: UIViewControllerRepresentable {
    let reserva: ReservaAgenda

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let tienda = EKEventStore()
        let e = EKEvent(eventStore: tienda)
        e.title = "Entrega Pump Team"
        e.startDate = ReglasGuia.instante(reserva.inicio) ?? Date()
        e.endDate = ReglasGuia.instante(reserva.fin) ?? e.startDate.addingTimeInterval(7200)
        e.url = reserva.meetUrl
        e.notes = reserva.meetUrl.map { "Videollamada: \($0.absoluteString)" }
        let vc = EKEventEditViewController()
        vc.eventStore = tienda
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador() }

    final class Coordinador: NSObject, EKEventEditViewDelegate {
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - En Entreno

/// La entrega en Entreno, desde 30 min antes hasta el fin de la franja, con la regla de la guía: «Mati ya está en la
/// videollamada · Entrar» con la sala abierta (o desde la hora de inicio, de respaldo); antes, el aviso sin botón.
struct TarjetaEntregaAhora: View {
    let modelo: ModeloGuia
    @Environment(\.openURL) private var abrirURL

    var body: some View {
        // Solo se mira el reloj si hay una confirmada que no terminó.
        if hayAlguna {
            TimelineView(.periodic(from: .now, by: 15)) { ctx in
                if let r = modelo.reservaEnVentana(ahora: ctx.date) {
                    Group {
                    if ReglasAgenda.puedeEntrar(r, ahora: ctx.date), let u = r.meetUrl {
                        let texto = ReglasAgenda.textoEntrar(r, zona: AgendaUI.zona)
                        Button { abrirURL(u) } label: {
                            fila(icono: "video.fill", Text(texto) + Text(" · ") + Text("Entrar").bold(), flecha: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(texto). Entrar a la videollamada")
                        .accessibilityIdentifier("agenda-entrar-tarjeta")
                    } else {
                        fila(icono: "clock", Text(ReglasAgenda.textoEsperandoSala(r, zona: AgendaUI.zona)), flecha: false)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("agenda-esperando-tarjeta")
                    }
                    }
                    // Ya en la ventana, con Entreno a la vista: la agenda cada 30 s hasta que Mati abre la sala. Si la
                    // reserva vino solo del resumen (la guía no se abrió), primero se trae la agenda.
                    .task(id: r) {
                        if modelo.agenda.agenda?.reserva == nil { await modelo.agenda.consultar() }
                        await modelo.agenda.vigilarSala()
                    }
                }
            }
        }
    }

    private func fila(icono: String, _ texto: Text, flecha: Bool) -> some View {
        HStack(spacing: Espacio.s) {
            Image(systemName: icono).font(.headline).accessibilityHidden(true)
            texto
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if flecha { Image(systemName: "chevron.right").font(.caption.weight(.bold)).accessibilityHidden(true) }
        }
        .foregroundStyle(.white)
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(Color.guiaDestacada, in: .rect(cornerRadius: Radio.control + 6, style: .continuous))
        .contentShape(.rect)
    }

    private var hayAlguna: Bool {
        guard modelo.resumen?.ok != false, modelo.estado != .oculta else { return false }
        return [modelo.agenda.reserva, modelo.resumen?.reserva].contains { r in
            guard let r, r.estado == .confirmada, let f = ReglasGuia.instante(r.fin) else { return false }
            return f > Date()
        }
    }
}

// MARK: - Pruebas y capturas

@MainActor
enum AgendaUI {
    /// La zona del teléfono. En DEBUG, `-zonaTelefono Europe/Madrid` (capturas de «Horario de tu teléfono»).
    static var zona: TimeZone {
        #if DEBUG
        if let z = UserDefaults.standard.string(forKey: "zonaTelefono"), let t = TimeZone(identifier: z) { return t }
        #endif
        return .current
    }

    #if DEBUG
    /// `-agendaDemo <escenario>`: «Tu guía» v2 con un servidor de mentira (nada sale a la red salvo el video público de la
    /// demo). Escenarios: `flujo` (falta un video; reservar queda pendiente y se confirma a la tercera consulta), `tomada`,
    /// `noAutorizada`, `sinFranjas`, `pendiente`, `vencida`, `confirmada` (empieza en 10 min,
    /// sin la sala abierta), `salaAbierta` (lo mismo, con Mati en el Meet) y `salaSeAbre` (la sala se abre a la tercera
    /// consulta; con `-agendaSalaCada 2` se consulta cada 2 s en vez de cada 30).
    /// `-agendaSinRed YES` deja todo sin red (con la copia de la corrida anterior si se pasó `-agendaConservar YES`).
    static var modelo: ModeloGuia? {
        if !creado { creado = true; guardado = crear() }
        return guardado
    }
    private static var creado = false
    private static var guardado: ModeloGuia?

    private static func crear() -> ModeloGuia? {
        let d = UserDefaults.standard
        guard let esc = d.string(forKey: "agendaDemo") else { return nil }
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("agenda-ui", isDirectory: true)
        if !d.bool(forKey: "agendaConservar") { try? FileManager.default.removeItem(at: raiz) }
        let token = "token-agenda-ui"
        let disco = Disco(raiz: raiz, token: token)
        let servidor = ServidorAgendaUI(escenario: esc, sinRed: d.bool(forKey: "agendaSinRed"))
        let cliente = ClienteRPC(transporte: servidor)
        let escrituras = Escrituras(cliente: cliente, token: token, carpetaAudios: raiz.appendingPathComponent("audios"))
        let cola = Outbox(archivo: disco.url("outbox.json")) { await escrituras.ejecutar($0) }
        let sala = Double(d.string(forKey: "agendaSalaCada") ?? "") ?? ReglasAgenda.salaCada
        let m = ModeloGuia(cliente: cliente, token: token, outbox: cola, disco: disco, esperaSala: .seconds(sala))
        Task { await cola.observar(estado: { _ in }, abandonadas: { ops in Task { @MainActor in m.alAbandonar(ops) } },
                                   guardadas: { ops in Task { @MainActor in m.alGuardar(ops) } }) }
        Task { await m.actualizarResumen() }
        return m
    }
    #endif
}

#if DEBUG
/// La 021 de mentira: el get, el resumen, el avance, la agenda y reservar, con el estado en memoria.
final class ServidorAgendaUI: Transporte, @unchecked Sendable {
    private let cerrojo = NSLock()
    private let escenario: String
    private let sinRed: Bool
    private var vistos: Set<String> = []
    private var franjas: [FranjaAgenda]
    private var reserva: ReservaAgenda?
    private var consultasPendiente = 0
    private var reservas = 0
    private var consultasSala = 0
    /// El video que falta ver: uno público y corto de la demo (18 s), así la prueba lo reproduce de verdad.
    static let videoPendiente = "https://gydinputrtptqakdzyvc.supabase.co/storage/v1/object/public/videos-entrega/4f6624e371325690/FT-2b.mp4"

    init(escenario: String, sinRed: Bool) {
        self.escenario = escenario
        self.sinRed = sinRed
        let base = Date()
        var fs: [FranjaAgenda] = []
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let iso = ISO8601DateFormatter()
        iso.timeZone = cal.timeZone
        for (dia, hora) in [(1, 10), (1, 14), (2, 14), (4, 10), (4, 14)] {
            guard let d = cal.date(byAdding: .day, value: dia, to: cal.startOfDay(for: base)),
                  let i = cal.date(bySettingHour: hora, minute: 0, second: 0, of: d) else { continue }
            fs.append(FranjaAgenda(id: "f\(fs.count + 1)", inicio: iso.string(from: i), fin: iso.string(from: i.addingTimeInterval(7200))))
        }
        franjas = escenario == "sinFranjas" ? [] : fs
        let guia = Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(GuiaMuestra.jsonV2().utf8))) ?? .null)
        vistos = Set(guia.clips.filter(\.visto).map(\.id))
        if escenario != "flujo" && escenario != "noAutorizada" { vistos.insert("N-1") }
        switch escenario {
        case "pendiente":
            reserva = ReservaAgenda(id: "r1", inicio: fs[0].inicio, fin: fs[0].fin, estado: .pendiente)
        case "confirmada", "salaAbierta", "salaSeAbre":
            let i = base.addingTimeInterval(10 * 60)
            reserva = ReservaAgenda(id: "r1", inicio: iso.string(from: i), fin: iso.string(from: i.addingTimeInterval(7200)), estado: .confirmada,
                                    meetUrl: URL(string: "https://meet.google.com/abc-defg-hij"),
                                    salaAbiertaEn: escenario == "salaAbierta" ? iso.string(from: base) : nil)
        case "vencida":
            reserva = ReservaAgenda(id: "r1", inicio: fs[0].inicio, fin: fs[0].fin, estado: .fallo, motivo: "vencida")
        default: break
        }
    }

    private var guia: Guia {
        var g = Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(GuiaMuestra.jsonV2(urlPendiente: Self.videoPendiente).utf8))) ?? .null)
        for i in g.clips.indices { g.clips[i].visto = vistos.contains(g.clips[i].id) }
        return g
    }

    private func json<T: Encodable>(_ v: T) -> String { (try? JSONEncoder().encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "null" }

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        try? await Task.sleep(for: .milliseconds(300))
        if sinRed { throw URLError(.notConnectedToInternet) }
        let fn = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let texto: String = cerrojo.withLock {
            switch fn {
            case "entregas_app_get":
                return json(guia)
            case "entregas_app_resumen":
                let g = guia
                let a = ReglasGuia.avance(ReglasGuia.deLaLista(g))
                let nuevos = g.clips.filter(\.nuevo)
                return json(ResumenGuia(ok: true, total: a.total, vistos: a.vistos, minutosRestantes: a.minutosRestantes, mostrarTarjetaServidor: true,
                                        novedadEn: g.novedadEn, reserva: reserva, nuevosTotal: nuevos.count, nuevosVistos: nuevos.filter(\.visto).count))
            case "entregas_app_avance":
                if cuerpo?["p_visto"] == .bool(true), let v = cuerpo?["p_video"]?.comoTexto { vistos.insert(v) }
                return "true"
            case "entregas_app_audios":
                return "[]"
            case "entregas_app_agenda":
                let faltan = ReglasAgenda.faltan(guia)
                if escenario == "salaSeAbre", reserva?.salaAbiertaEn == nil {
                    consultasSala += 1
                    if consultasSala >= 3 { reserva?.salaAbiertaEn = ISO8601DateFormatter().string(from: Date()) }
                }
                let autorizada = escenario != "noAutorizada"
                if reserva?.estado == .pendiente, escenario == "flujo" {
                    consultasPendiente += 1
                    if consultasPendiente >= 3 {
                        reserva?.estado = .confirmada
                        reserva?.meetUrl = URL(string: "https://meet.google.com/abc-defg-hij")
                    }
                }
                let a = AgendaGuia(ok: true, autorizada: autorizada, habilitada: autorizada && faltan == 0, faltan: faltan,
                                   zona: "America/Argentina/Buenos_Aires", franjas: reserva?.vigente == true ? [] : franjas, reserva: reserva)
                return json(a)
            case "entregas_app_reservar":
                reservas += 1
                guard let fid = cuerpo?["p_franja"]?.comoTexto, let f = franjas.first(where: { $0.id == fid }) else {
                    return #"{"ok":false,"motivo":"franja"}"#
                }
                if escenario == "tomada" && reservas == 1 {
                    franjas.removeAll { $0.id == fid }
                    return #"{"ok":false,"motivo":"tomada"}"#
                }
                reserva = ReservaAgenda(id: cuerpo?["p_id"]?.comoTexto, inicio: f.inicio, fin: f.fin, estado: .pendiente)
                consultasPendiente = 0
                return #"{"ok":true,"reserva":\#(json(reserva))}"#
            default:
                return "true"
            }
        }
        return (Data(texto.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
