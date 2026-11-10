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
    @State private var elegirPantalla = false

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
                HojaConfirmar(texto: modelo.agenda.textos.confirmar(c, zona: zona, tipo: modelo.agenda.agenda?.tipo ?? .comienzo),
                              confirmar: { elegido = nil; Task { await modelo.agenda.reservar(c.franja) } },
                              otro: { elegido = nil })
            }
            .sheet(isPresented: $elegirPantalla) { PantallaHorario(modelo: modelo, cambiando: nil) }
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
        let t = modelo.agenda.textos
        let titulo = t.titulo(modelo.agenda.agenda?.tipo ?? .comienzo)
        switch v {
        case .nada:
            EmptyView()
        case .noAutorizada:
            Bloqueada(titulo: titulo, texto: t.noAutorizada, sinRed: modelo.agenda.desdeCache, accion: nil)
        case .bloqueada(let n):
            Bloqueada(titulo: titulo, texto: t.bloqueada(n), sinRed: modelo.agenda.desdeCache,
                      accion: n > 0 ? ReglasAgenda.primeroQueFalta(modelo.guia).map { c in { irAlVideo(c) } } : nil,
                      habilitando: n == 0)
        case .franjas where Videollamada.elegirHorario:
            // La palanca `elegir_horario`: la pantalla nueva para elegir (y después cambiar).
            TarjetaElegirHorario(modelo: modelo) { elegirPantalla = true }
        case .franjas(let aviso):
            Franjas(t: t, titulo: titulo, dias: ReglasAgenda.dias(modelo.agenda.agenda?.franjas ?? [], zona: zona), zona: zona, aviso: aviso,
                    sinRed: modelo.agenda.desdeCache) { elegido = $0 }
        case .sinFranjas(let aviso):
            CajaAgenda(sinRed: modelo.agenda.desdeCache) {
                Encabezado(icono: "calendar", titulo: titulo)
                if let aviso { AvisoAgenda(texto: t.fallo(aviso)) }
                Text(t.sinFranjas).font(.body).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("agenda-sin-franjas")
            }
        case .reservando:
            CajaAgenda(sinRed: modelo.agenda.desdeCache) {
                Encabezado(icono: "calendar", titulo: titulo)
                HStack(spacing: Espacio.s) {
                    ProgressView()
                    Text(t.pendiente).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agenda-reservando")
            }
        case .confirmada(let r, let aviso):
            // La misma tarjeta que arriba de Entreno (videollamada 2.3.0).
            VStack(alignment: .leading, spacing: Espacio.xs) {
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    TarjetaVideollamada(modelo: modelo, reserva: r, ahora: ctx.date)
                }
                if let aviso { Text(aviso.texto).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("agenda-demo") }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("agenda")
            // En la franja, con la guía abierta: la agenda cada 30 s (el link si falta y la sala).
            .task(id: r) { await modelo.agenda.vigilarSala() }
        }
    }
}

// MARK: - Piezas

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
    let titulo: String
    let texto: String
    let sinRed: Bool
    let accion: (() -> Void)?
    var habilitando = false

    var body: some View {
        CajaAgenda(fondo: .campo, sinRed: sinRed) {
            Encabezado(icono: "lock.fill", titulo: titulo, tono: .secondary)
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
    let t: ReglasAgenda.Textos
    let titulo: String
    let dias: [ReglasAgenda.Dia]
    let zona: TimeZone
    let aviso: ReglasAgenda.Aviso?
    let sinRed: Bool
    let elegir: (ReglasAgenda.Chip) -> Void

    var body: some View {
        CajaAgenda(sinRed: sinRed) {
            Encabezado(icono: "calendar", titulo: titulo, tono: .marcaTexto)
            if let aviso { AvisoAgenda(texto: t.fallo(aviso)) }
            Text(t.encabezado(dias.flatMap(\.chips)))
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
struct AgregarAlCalendario: UIViewControllerRepresentable {
    let reserva: ReservaAgenda

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let tienda = EKEventStore()
        let e = EKEvent(eventStore: tienda)
        e.title = ReglasAgenda.mayusculaPublica(ReglasAgenda.nombre(reserva.tipo)) + " con Mati"
        e.startDate = ReglasGuia.instante(reserva.inicio) ?? Date()
        e.endDate = ReglasGuia.instante(reserva.fin) ?? e.startDate.addingTimeInterval(3600)
        e.url = reserva.meetUrl
        // Se entra desde la app (Mati, 10/11); el link queda en el evento solo de respaldo.
        e.notes = "Entrá desde la app MyPump, en Entreno. Mati te admite en la sala."
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
    private var cambios = 0
    /// El video que falta ver: uno público y corto de la demo (18 s), así la prueba lo reproduce de verdad.
    static let videoPendiente = "https://gydinputrtptqakdzyvc.supabase.co/storage/v1/object/public/videos-entrega/4f6624e371325690/FT-2b.mp4"

    init(escenario: String, sinRed: Bool) {
        self.escenario = escenario
        self.sinRed = sinRed
        let base = Date()
        var fs: [FranjaAgenda] = []
        // (las de la 2.2.0: 10 y 14, 1 h; las de la videollamada 2.3.0 van más abajo)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let iso = ISO8601DateFormatter()
        iso.timeZone = cal.timeZone
        // Días hábiles, como el servidor (`agenda_lib.huecos`): el próximo, el siguiente y el cuarto, nunca fin de semana.
        for (dia, hora) in [(1, 10), (1, 14), (2, 14), (4, 10), (4, 14)] {
            let d = ReglasAgenda.diaHabil(dia, desde: base, cal)
            guard let i = cal.date(bySettingHour: hora, minute: 0, second: 0, of: d) else { continue }
            fs.append(FranjaAgenda(id: "f\(fs.count + 1)", inicio: iso.string(from: i), fin: iso.string(from: i.addingTimeInterval(3600))))
        }
        // La videollamada 2.3.0: 10 y 12 de Argentina, 1 h, días hábiles.
        if ["elegir", "diasAntes", "porEntrar"].contains(escenario) {
            fs = []
            for dia in 1...5 {
                let d = ReglasAgenda.diaHabil(dia, desde: base, cal)
                for hora in [10, 12] {
                    guard let i = cal.date(bySettingHour: hora, minute: 0, second: 0, of: d) else { continue }
                    fs.append(FranjaAgenda(id: "f\(fs.count + 1)", inicio: iso.string(from: i), fin: iso.string(from: i.addingTimeInterval(3600))))
                }
            }
        }
        franjas = escenario == "sinFranjas" ? [] : fs
        let guia = Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(GuiaMuestra.jsonV2().utf8))) ?? .null)
        vistos = Set(guia.clips.filter(\.visto).map(\.id))
        if escenario != "flujo" && escenario != "noAutorizada" { vistos.insert("N-1") }
        switch escenario {
        case "pendiente":
            reserva = ReservaAgenda(id: "r1", inicio: fs[0].inicio, fin: fs[0].fin, estado: .pendiente)
        case "diasAntes":
            // Confirmada a 2 días hábiles, a las 10 (el 3.er horario de la lista), con un cambio disponible.
            reserva = ReservaAgenda(id: "r1", inicio: fs[2].inicio, fin: fs[2].fin, estado: .confirmada,
                                    meetUrl: URL(string: "https://meet.google.com/abc-defg-hij"))
        case "porEntrar":
            // Empieza en 6 min: «Entrar» ya está habilitado.
            let i = base.addingTimeInterval(6 * 60 + 30)
            reserva = ReservaAgenda(id: "r1", inicio: iso.string(from: i), fin: iso.string(from: i.addingTimeInterval(3600)), estado: .confirmada,
                                    meetUrl: URL(string: "https://meet.google.com/abc-defg-hij"))
        case "confirmada", "salaAbierta", "salaSeAbre":
            let i = base.addingTimeInterval(25 * 60)
            reserva = ReservaAgenda(id: "r1", inicio: iso.string(from: i), fin: iso.string(from: i.addingTimeInterval(3600)), estado: .confirmada,
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
                // Con un cambio disponible (diasAntes, o elegir después de reservar), van las franjas para cambiar.
                var cambio: CambioAgenda?
                if ["diasAntes", "elegir"].contains(escenario), let r = reserva, r.estado == .confirmada, let i = ReglasGuia.instante(r.inicio) {
                    cambio = CambioAgenda(permitido: cambios < 1, restantes: max(0, 1 - cambios),
                                          hasta: ISO8601DateFormatter().string(from: i.addingTimeInterval(-24 * 3600)))
                }
                let conFranjas = reserva?.vigente != true || cambio?.permitido == true
                let a = AgendaGuia(ok: true, autorizada: autorizada, habilitada: autorizada && faltan == 0, faltan: faltan,
                                   zona: "America/Argentina/Buenos_Aires", franjas: conFranjas ? franjas : [], reserva: reserva, cambio: cambio)
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
                // La videollamada 2.3.0: el horario elegido queda confirmado enseguida (el daemon de la Mini es rápido).
                let directo = escenario == "elegir"
                reserva = ReservaAgenda(id: cuerpo?["p_id"]?.comoTexto, inicio: f.inicio, fin: f.fin, estado: directo ? .confirmada : .pendiente,
                                        meetUrl: directo ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
                consultasPendiente = 0
                return #"{"ok":true,"reserva":\#(json(reserva))}"#
            case "entregas_app_cambiar":
                guard let fid = cuerpo?["p_franja"]?.comoTexto, let f = franjas.first(where: { $0.id == fid }), let vieja = reserva else {
                    return #"{"ok":false,"motivo":"franja"}"#
                }
                guard cambios < 1 else { return #"{"ok":false,"motivo":"tope"}"# }
                cambios += 1
                reserva = ReservaAgenda(id: vieja.id, inicio: f.inicio, fin: f.fin, estado: .confirmada, meetUrl: vieja.meetUrl, tipo: vieja.tipo)
                return #"{"ok":true,"reserva":\#(json(reserva))}"#
            default:
                return "true"
            }
        }
        return (Data(texto.utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
