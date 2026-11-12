import SafariServices
import SwiftUI
import UserNotifications
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

// La videollamada (2.3.0, decisión de Mati del 10/11): el alumno entra desde la app, nunca por un link de WhatsApp.
// · La tarjeta fija arriba de Entreno, desde que se agenda hasta que termina: día y hora (la del teléfono y la de Argentina
//   si difiere), «Vas a entrar a la videollamada desde acá», «Entrar» apagado con la cuenta regresiva y activo desde 10
//   minutos antes (Meet restringido: Mati lo admite y el alumno espera en la sala), y «¿Cómo entro?».
// · Los avisos locales (un día antes y cuando se habilita «Entrar»), solo si la app ya tenía el permiso: nunca lo pide.
// · Con la palanca `elegir_horario`: la pantalla para elegir el horario (10 o 12 de Argentina, lo decide el servidor) y
//   para cambiarlo con el tope que manda el servidor. Sin la palanca, la agenda de la guía queda como en la 2.2.0.
// Al alumno nunca se le dice «entrega»: «videollamada de comienzo» o «de revisión».

@MainActor
enum Videollamada {
    /// La palanca `elegir_horario` (apagada de fábrica). En DEBUG, `-elegirHorario YES` la prende para pruebas y capturas.
    static var elegirHorario: Bool {
        #if DEBUG
        if let v = UserDefaults.standard.string(forKey: "elegirHorario") { return v == "YES" }
        #endif
        return Proveedor.modelo.palanca.elegirHorario
    }
}

// MARK: - En Entreno: la tarjeta fija arriba

/// Arriba de todo en Entreno: la videollamada agendada (hasta que termina) o, con la palanca y horarios libres, «Agendá tu
/// videollamada». También agenda o borra los avisos locales cuando cambia la reserva.
/// Si la pantalla de elegir horario de Entreno está abierta. Vive afuera de la tarjeta: al reservar, la tarjeta pasa de
/// «Agendá» a la videollamada y una hoja colgada de ella se cerraba antes de mostrar «Listo».
@MainActor @Observable
final class EstadoVideollamada {
    static let shared = EstadoVideollamada()
    var elegir = false
    /// La reserva que se está cambiando desde Entreno (misma razón: al cambiar, la tarjeta se rearma y cerraba la hoja).
    var cambiando: ReservaAgenda?
}

struct TarjetaVideollamadaEntreno: View {
    let modelo: ModeloGuia
    /// «Antes de la videollamada» (2.3.0): va dentro de la tarjeta de una reserva de comienzo.
    var listaPrevia: ReglasListaPrevia.Vista? = nil
    var abrirGuia: (() -> Void)? = nil

    var body: some View {
        let r = modelo.reservaTarjeta()
        Group {
            if r != nil {
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    if let r = modelo.reservaTarjeta(ahora: ctx.date) {
                        TarjetaVideollamada(modelo: modelo, reserva: r, ahora: ctx.date, hojaAfuera: true,
                                            listaPrevia: r.tipo == .comienzo ? listaPrevia : nil, abrirGuia: abrirGuia)
                            // En la ventana: la agenda cada 30 s (el link si falta y «Mati ya está en la sala»). Si la reserva
                            // vino solo del resumen (la guía no se abrió), primero se trae la agenda.
                            .task(id: r) {
                                if modelo.agenda.agenda?.reserva == nil { await modelo.agenda.consultar() }
                                await modelo.agenda.vigilarSala()
                            }
                    }
                }
            } else if Videollamada.elegirHorario, case .franjas = modelo.vistaAgenda {
                TarjetaElegirHorario(modelo: modelo) { EstadoVideollamada.shared.elegir = true }
            }
        }
    }
}

/// Los avisos locales y la consulta de la agenda (palanca) de Entreno. Van en la pantalla y no en la tarjeta: sin
/// videollamada la tarjeta es un `Group` vacío, que no corre sus `.task` (y un relleno ocuparía lugar arriba).
struct TareasVideollamada: ViewModifier {
    let modelo: ModeloGuia?

    func body(content: Content) -> some View {
        let r = modelo?.reservaTarjeta()
        content
            .task(id: claveAvisos(r)) {
                // Sin guía (token revocado, baja): r es nil y se borran los que hubiera.
                await AvisosVideollamada.programar(r, desdeMin: modelo?.agenda.entrarDesdeMin)
            }
            .task { if let modelo, Videollamada.elegirHorario, r == nil { await modelo.agenda.consultar() } }
            .sheet(isPresented: Binding(get: { EstadoVideollamada.shared.elegir },
                                        set: { EstadoVideollamada.shared.elegir = $0; if !$0 { EstadoVideollamada.shared.cambiando = nil } })) {
                if let modelo { PantallaHorario(modelo: modelo, cambiando: EstadoVideollamada.shared.cambiando) }
            }
    }

    private func claveAvisos(_ r: ReservaAgenda?) -> String {
        guard let r, r.estado == .confirmada else { return "" }
        return "\(r.inicio)|\(r.tipo.rawValue)|\(modelo?.agenda.entrarDesdeMin ?? 0)"
    }
}

// MARK: - La tarjeta de la videollamada (Entreno y el final de la guía)

struct TarjetaVideollamada: View {
    let modelo: ModeloGuia
    let reserva: ReservaAgenda
    var ahora: Date = Date()
    /// En Entreno la hoja de cambiar cuelga de `TareasVideollamada` (afuera de la tarjeta); en la guía, de la tarjeta.
    var hojaAfuera = false
    /// «Antes de la videollamada» (solo en Entreno, con una reserva de comienzo): debajo de lo que la tarjeta ya tiene.
    var listaPrevia: ReglasListaPrevia.Vista? = nil
    var abrirGuia: (() -> Void)? = nil
    @State private var paraCalendario = false
    @State private var cambiar = false
    @State private var ayuda = false
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private var zona: TimeZone { AgendaUI.zona }
    private var desdeMin: Int? { modelo.agenda.entrarDesdeMin }

    var body: some View {
        let estado = ReglasAgenda.estadoEntrar(reserva, ahora: ahora, desdeMin: desdeMin)
        let activa = estado == .habilitado
        let inicio = ReglasGuia.instante(reserva.inicio)
        let fin = ReglasGuia.instante(reserva.fin)
        VStack(alignment: .leading, spacing: Espacio.m) {
            if modelo.agenda.desdeCache {
                Label("Sin conexión", systemImage: "wifi.slash")
                    .font(.footnote.weight(.semibold)).foregroundStyle(activa ? Color.sobreMarca.opacity(0.85) : .secondary)
                    .accessibilityIdentifier("agenda-sin-red")
            }
            cabecera(activa: activa)
            if let inicio {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ReglasAgenda.mayusculaPublica(ReglasAgenda.diaLargo(inicio, zona: zona)))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(ReglasAgenda.hora(inicio, zona: zona))
                            .font(Archivo.fuente(44, peso: 800, relativoA: .largeTitle))
                            .monospacedDigit()
                        if let fin {
                            Text("a \(ReglasAgenda.hora(fin, zona: zona))")
                                .font(.title3.weight(.medium)).monospacedDigit()
                                .foregroundStyle(activa ? Color.sobreMarca.opacity(0.85) : .secondary)
                        }
                    }
                    if let ar = ReglasAgenda.horaArgentina(inicio, zona: zona) {
                        Label(ar, systemImage: "globe.americas")
                            .font(.footnote).foregroundStyle(activa ? Color.sobreMarca.opacity(0.85) : .secondary)
                            .accessibilityIdentifier("videollamada-argentina")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("agenda-confirmada")
            }
            if reserva.estado == .pendiente {
                HStack(spacing: Espacio.s) {
                    ProgressView()
                    Text(modelo.agenda.textos.pendiente).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("videollamada-reservando")
            } else {
                botonEntrar(estado)
            }
            if reserva.estado == .confirmada && !activa {
                LineaVideollamada(texto: ReglasAgenda.textoDesdeAca, icono: "hand.tap.fill")
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("videollamada-desde-aca")
            }
            if activa {
                Text(ReglasAgenda.textoAdmite)
                    .font(.subheadline).foregroundStyle(Color.sobreMarca)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("videollamada-admite")
            }
            if reserva.estado == .confirmada { comoEntro(activa: activa) }
            if reserva.estado == .confirmada && !activa { acciones }
            if let listaPrevia {
                Divider().overlay(activa ? Color.sobreMarca.opacity(0.35) : Color.clear)
                ListaPreviaBloque(vista: listaPrevia, sobreVerde: activa, abrirGuia: abrirGuia)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .foregroundStyle(activa ? Color.sobreMarca : .primary)
        .modifier(FondoVideollamada(activa: activa))
        .animation(.snappy, value: activa)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("videollamada")
        .sheet(isPresented: $paraCalendario) { AgregarAlCalendario(reserva: reserva).ignoresSafeArea() }
        .sheet(isPresented: $cambiar) { PantallaHorario(modelo: modelo, cambiando: reserva) }
    }

    private func cabecera(activa: Bool) -> some View {
        HStack(alignment: .center, spacing: Espacio.xs) {
            Image(systemName: "video.fill")
                .font(.footnote.weight(.bold))
                .foregroundStyle(activa ? Color.marca : Color.sobreMarca)
                .frame(width: 30, height: 30)
                .background(activa ? Color.sobreMarca : Color.marca, in: .circle)
                .accessibilityHidden(true)
            Text(ReglasAgenda.tituloTarjeta(reserva.tipo))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(activa ? Color.sobreMarca : Color.marcaTexto)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Espacio.xs)
            if let c = ReglasAgenda.cuando(reserva, zona: zona, ahora: ahora), !tamañoLetra.isAccessibilitySize {
                Text(c)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(activa ? Color.marca : Color.marcaTexto)
                    .background(activa ? Color.sobreMarca : Color.marcaSuave, in: .capsule)
                    .accessibilityIdentifier("videollamada-cuando")
            }
        }
    }

    @ViewBuilder private func botonEntrar(_ e: ReglasAgenda.EstadoEntrar) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            if e == .habilitado {
                Text(ReglasAgenda.textoEntrar(reserva, zona: zona))
                    .font(.headline)
                    .accessibilityIdentifier("agenda-sala")
                Button {
                    if let u = reserva.meetUrl { ReunionMeet.abrir(u) }
                } label: {
                    Label("Entrar a la videollamada", systemImage: "video.fill")
                        .font(.headline)
                        .foregroundStyle(Color.marcaTexto)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.blancoFijo, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre la reunión de Google Meet acá, en la app. Mati te admite en la sala")
                .accessibilityIdentifier("agenda-entrar")
                if let codigo = ReglasAgenda.codigoMeet(reserva.meetUrl) {
                    CodigoReunion(codigo: codigo)
                }
            } else {
                Button {} label: { Label("Entrar", systemImage: "lock.fill") }
                    .buttonStyle(BotonMarca())
                    .disabled(true)
                    .accessibilityIdentifier("videollamada-entrar-apagado")
                if let t = ReglasAgenda.textoCuenta(e, desdeMin: desdeMin) {
                    Text(t)
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("videollamada-cuenta")
                }
            }
        }
    }

    private func comoEntro(activa: Bool) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Button {
                withAnimation(.snappy) { ayuda.toggle() }
            } label: {
                HStack {
                    Label("¿Cómo entro?", systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption.weight(.bold))
                        .rotationEffect(.degrees(ayuda ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(activa ? Color.sobreMarca : Color.marcaTexto)
            .accessibilityValue(ayuda ? "Abierto" : "Cerrado")
            .accessibilityIdentifier("videollamada-como-entro")
            if ayuda {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    ForEach(Array(ReglasAgenda.ayudaEntrar.enumerated()), id: \.offset) { i, t in
                        HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                            Text("\(i + 1)")
                                .font(.caption.weight(.bold)).monospacedDigit()
                                .frame(width: 22, height: 22)
                                .background(activa ? Color.sobreMarca.opacity(0.2) : Color.marcaSuave, in: .circle)
                                .accessibilityHidden(true)
                            Text(t).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("videollamada-ayuda")
            }
        }
    }

    private var acciones: some View {
        let puedeCambiar = Videollamada.elegirHorario && modelo.agenda.puedeCambiar
        let disposicion = tamañoLetra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs))
                                                          : AnyLayout(HStackLayout(spacing: Espacio.xs))
        return VStack(alignment: .leading, spacing: Espacio.xs) {
            disposicion {
                Button { paraCalendario = true } label: {
                    Label("Al calendario", systemImage: "calendar.badge.plus").lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity)
                }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    .accessibilityLabel("Agregar a mi calendario")
                    .accessibilityIdentifier("agenda-calendario")
                if puedeCambiar {
                    Button {
                        if hojaAfuera { EstadoVideollamada.shared.cambiando = reserva; EstadoVideollamada.shared.elegir = true } else { cambiar = true }
                    } label: {
                        Label("Cambiar horario", systemImage: "arrow.triangle.2.circlepath").lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                    }
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                        .accessibilityIdentifier("videollamada-cambiar")
                }
            }
            if !puedeCambiar {
                Text(modelo.agenda.textos.cambiar)
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Abrir la reunión (2.3.1)

/// Abre la reunión de Meet DENTRO de la app, en un SFSafariViewController, y no con `openURL`.
///
/// Con `openURL`, el link de meet.google.com es un universal link: si el teléfono tiene Gmail o la app de Meet, iOS se lo
/// da a esa app, y con otra cuenta de Google o sin sesión el alumno caía en la bandeja de Gmail o en la portada de Meet,
/// no en la reunión (lo reportó Mati, 12/11). El SFSafariViewController no sigue universal links al cargar, así que abre
/// ESA reunión en la web de Meet, que desde junio de 2026 deja entrar en el iPhone sin app ni cuenta: el alumno escribe
/// su nombre, toca «Solicitar unirse» y Mati lo admite (Meet en TRUSTED, sin moderación).
///
/// Va en una ventana propia, encima de la de la app, y no con un `.fullScreenCover` de la tarjeta ni presentado desde el
/// controlador de arriba: la tarjeta se va cuando termina el horario de la reserva o cuando se rearma, una hoja de SwiftUI
/// que estuviera abierta se puede cerrar por un cambio de estado, y mientras dura la llamada las hojas y alertas de la app
/// tienen que poder abrirse debajo sin chocar («already presenting»). Pantalla completa para que un deslizamiento hacia
/// abajo no la cierre sin querer; se sale con el botón de listo y la ventana se va.
@MainActor
final class ReunionMeet: NSObject, @preconcurrency SFSafariViewControllerDelegate {
    private static let shared = ReunionMeet()
    private var ventana: UIWindow?
    private weak var anterior: UIWindow?

    static func abrir(_ url: URL) { shared.abrir(url) }

    private func abrir(_ url: URL) {
        guard ventana == nil else { return }  // Un segundo toque mientras se abre o con la reunión abierta.
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let escena = escenas.first(where: { $0.activationState == .foregroundActive }) ?? escenas.first else { return }
        anterior = escena.windows.first { $0.isKeyWindow }
        let w = UIWindow(windowScene: escena)
        w.windowLevel = .normal + 1
        w.overrideUserInterfaceStyle = anterior?.overrideUserInterfaceStyle ?? .unspecified
        let raiz = UIViewController()
        raiz.view.backgroundColor = .clear
        w.rootViewController = raiz
        w.makeKeyAndVisible()
        ventana = w
        let c = SFSafariViewController(url: url)
        c.delegate = self
        c.preferredControlTintColor = UIColor(Color.marcaTexto)
        c.dismissButtonStyle = .done
        c.modalPresentationStyle = .fullScreen
        raiz.present(c, animated: true)
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        ventana?.isHidden = true
        ventana = nil
        anterior?.makeKey()
    }
}

/// El respaldo de «Entrar», siempre a la vista debajo del botón: el código de la reunión, «Copiar código» y dónde pegarlo.
private struct CodigoReunion: View {
    let codigo: String
    @State private var copiado = false
    @State private var tarea: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ReglasAgenda.tituloCodigo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.sobreMarca.opacity(0.9))
                Text(codigo)
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .foregroundStyle(Color.sobreMarca)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ReglasAgenda.tituloCodigo): \(codigo.map { $0 == "-" ? "guion" : String($0) }.joined(separator: " "))")
            .accessibilityIdentifier("videollamada-codigo")
            Button(action: copiar) {
                Label(copiado ? ReglasAgenda.textoCodigoCopiado : ReglasAgenda.textoCopiarCodigo,
                      systemImage: copiado ? "checkmark.circle.fill" : "doc.on.doc.fill")
                    .font(.headline)
                    .foregroundStyle(Color.sobreMarca)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay { Capsule().strokeBorder(Color.sobreMarca, lineWidth: 2) }
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: copiado) { _, nuevo in nuevo }
            .accessibilityIdentifier("videollamada-copiar-codigo")
            VStack(alignment: .leading, spacing: 6) {
                Text(ReglasAgenda.tituloPasosCodigo)
                    .font(.body.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(ReglasAgenda.pasosCodigo.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                        Text("\(i + 1)")
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                            .frame(width: 26, height: 26)
                            .background(Color.sobreMarca.opacity(0.22), in: .circle)
                            .accessibilityHidden(true)
                        Text(t).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Paso \(i + 1): \(t)")
                }
            }
            .foregroundStyle(Color.sobreMarca)
            .padding(.top, 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("videollamada-pasos-codigo")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sobreMarca.opacity(0.14), in: .rect(cornerRadius: 16, style: .continuous))
        .onDisappear { tarea?.cancel() }
    }

    private func copiar() {
        UIPasteboard.general.string = codigo
        withAnimation(.snappy) { copiado = true }
        UIAccessibility.post(notification: .announcement, argument: ReglasAgenda.textoCodigoCopiado)
        tarea?.cancel()
        tarea = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { copiado = false }
        }
    }
}

/// Lejos: la tarjeta de siempre con un borde verde. Habilitada: verde lleno, para que no haya dudas de dónde tocar.
private struct FondoVideollamada: ViewModifier {
    let activa: Bool

    func body(content: Content) -> some View {
        if activa {
            content
                .background(Color.guiaDestacada, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
                .shadow(color: Color.guiaDestacada.opacity(0.35), radius: 16, x: 0, y: 8)
        } else {
            content
                .superficieTarjeta(radio: Radio.tarjeta)
                .overlay {
                    RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous)
                        .strokeBorder(Color.marca.opacity(0.45), lineWidth: 1.5)
                }
        }
    }
}

extension Color {
    /// Blanco en claro y en oscuro: el botón «Entrar» sobre la tarjeta verde.
    static let blancoFijo = Color(claro: .white, oscuro: UIColor(white: 0.97, alpha: 1))
}

private struct LineaVideollamada: View {
    let texto: String
    let icono: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icono).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
            Text(texto).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(texto)
    }
}

// MARK: - «Agendá tu videollamada» (palanca)

struct TarjetaElegirHorario: View {
    let modelo: ModeloGuia
    let abrir: () -> Void

    var body: some View {
        let a = modelo.agenda.agenda
        let dias = ReglasAgenda.dias(a?.franjas ?? [], zona: AgendaUI.zona)
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(spacing: Espacio.xs) {
                Image(systemName: "calendar")
                    .font(.footnote.weight(.bold)).foregroundStyle(Color.sobreMarca)
                    .frame(width: 30, height: 30).background(Color.marca, in: .circle)
                    .accessibilityHidden(true)
                Text(modelo.agenda.textos.titulo(a?.tipo ?? .comienzo))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            if let aviso = modelo.agenda.aviso {
                Label(modelo.agenda.textos.fallo(aviso), systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.alerta)
                    .accessibilityIdentifier("videollamada-aviso")
            }
            Text(textoDesde(dias))
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action: abrir) { Label("Elegir horario", systemImage: "calendar.badge.clock") }
                .buttonStyle(BotonMarca())
                .accessibilityIdentifier("videollamada-elegir")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .superficieTarjeta(radio: Radio.tarjeta)
        .overlay { RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).strokeBorder(Color.marca.opacity(0.45), lineWidth: 1.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("videollamada-agendar")
    }

    private func textoDesde(_ dias: [ReglasAgenda.Dia]) -> String {
        guard let d = dias.first?.chips.first?.inicio else { return "Elegí el día y el horario. Vas a entrar desde la app." }
        return "Elegí el día y el horario. Hay lugar desde el \(ReglasAgenda.diaCorto(d, zona: AgendaUI.zona))."
    }
}

// MARK: - Elegir o cambiar el horario (palanca)

struct PantallaHorario: View {
    let modelo: ModeloGuia
    /// La reserva que se cambia; nil = elegir por primera vez.
    let cambiando: ReservaAgenda?
    @State private var elegido: ReglasAgenda.Chip?
    @State private var enviado = false
    @State private var conAvisos = false
    @State private var paraCalendario = false
    @Environment(\.dismiss) private var cerrar
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private var zona: TimeZone { AgendaUI.zona }
    private var tipo: TipoVideollamada { cambiando?.tipo ?? modelo.agenda.agenda?.tipo ?? .comienzo }

    /// Lo que ya quedó: la reserva confirmada que no es la que se cambia.
    private var lista: ReservaAgenda? {
        guard enviado, let r = modelo.agenda.reserva, r.estado == .confirmada else { return nil }
        if let c = cambiando { return ReglasGuia.instante(r.inicio) != ReglasGuia.instante(c.inicio) ? r : nil }
        return r
    }

    private var enviando: Bool { enviado && lista == nil && (modelo.agenda.enCola != nil || modelo.agenda.reserva?.estado == .pendiente) }

    var body: some View {
        NavigationStack {
            Group {
                if let r = lista {
                    listo(r)
                } else {
                    elegir
                }
            }
            .background(Color.fondo)
            .navigationTitle(lista != nil ? "" : (cambiando == nil ? "Elegí tu horario" : "Cambiar horario"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if lista == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { cerrar() }.accessibilityIdentifier("horario-cerrar")
                    }
                }
            }
        }
        .task { conAvisos = await AvisosVideollamada.hayPermiso() }
        .onChange(of: modelo.agenda.anuncios) { _, _ in
            // Tomada, vencida o sin cambio: se vuelve a elegir con el aviso arriba.
            if modelo.agenda.aviso != nil { enviado = false; elegido = nil }
        }
        .sheet(isPresented: $paraCalendario) {
            if let r = lista { AgregarAlCalendario(reserva: r).ignoresSafeArea() }
        }
    }

    // MARK: Elegir

    private var elegir: some View {
        let dias = ReglasAgenda.dias(modelo.agenda.agenda?.franjas ?? [], zona: zona)
            .map { d in ReglasAgenda.Dia(id: d.id, titulo: d.titulo, chips: d.chips.filter { $0.inicio != cambiando.flatMap { ReglasGuia.instante($0.inicio) } }) }
            .filter { !$0.chips.isEmpty }
        let chips = dias.flatMap(\.chips)
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(cambiando == nil ? ReglasAgenda.tituloElegir(tipo) : "Elegí el nuevo horario")
                        .font(Archivo.fuente(28, peso: 800, relativoA: .title1))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("horario-titulo")
                    Text(ReglasAgenda.textoElegirPantalla(chips))
                        .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if ReglasAgenda.difiereDeArgentina(chips.map(\.inicio), zona: zona) {
                        Label(ReglasAgenda.textoZonaTelefono, systemImage: "globe.americas")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let c = cambiando {
                    VStack(alignment: .leading, spacing: 4) {
                        if let t = ReglasAgenda.textoAhoraEs(c, zona: zona) { Text(t).font(.subheadline.weight(.semibold)) }
                        if let t = ReglasAgenda.textoTope(modelo.agenda.agenda?.cambio, zona: zona) {
                            Text(t).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(Espacio.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("horario-ahora-es")
                }
                if let aviso = modelo.agenda.aviso {
                    Label(modelo.agenda.textos.fallo(aviso), systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.alerta)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("horario-aviso")
                }
                if dias.isEmpty {
                    Text(modelo.agenda.textos.sinFranjas).font(.body).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("horario-sin-franjas")
                }
                ForEach(dias) { d in dia(d) }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.s)
            .padding(.bottom, Espacio.l)
            .anchoLectura()
        }
        .safeAreaInset(edge: .bottom) { barraConfirmar }
        .disabled(enviando)
    }

    private func dia(_ d: ReglasAgenda.Dia) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text(ReglasAgenda.mayusculaPublica(d.titulo))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            let disposicion = tamañoLetra.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Espacio.xs))
                                                              : AnyLayout(HStackLayout(spacing: Espacio.xs))
            disposicion {
                ForEach(d.chips) { c in
                    let sel = elegido?.id == c.id
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { elegido = sel ? nil : c }
                    } label: {
                        VStack(spacing: 2) {
                            Text(ReglasAgenda.hora(c.inicio, zona: zona))
                                .font(Archivo.fuente(24, peso: 800, relativoA: .title2)).monospacedDigit()
                            Text(ReglasAgenda.horaArgentina(c.inicio, zona: zona) ?? "a \(ReglasAgenda.hora(c.fin, zona: zona))")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(sel ? Color.sobreMarca.opacity(0.85) : .secondary)
                        }
                        .foregroundStyle(sel ? Color.sobreMarca : .primary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                        .background(sel ? Color.marca : Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            if sel {
                                Image(systemName: "checkmark.circle.fill").font(.body)
                                    .foregroundStyle(Color.sobreMarca).padding(8)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d.titulo), a las \(ReglasAgenda.hora(c.inicio, zona: zona))")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                    .accessibilityIdentifier("horario-franja-\(c.id)")
                }
            }
        }
        .padding(Espacio.m)
        .superficieTarjeta(radio: Radio.control + 6)
    }

    private var barraConfirmar: some View {
        VStack(spacing: Espacio.xs) {
            if enviando {
                HStack(spacing: Espacio.s) {
                    ProgressView()
                    Text(cambiando == nil ? modelo.agenda.textos.pendiente : "Estamos cambiando tu horario…")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minHeight: 54)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("horario-enviando")
            } else {
                Button {
                    guard let c = elegido else { return }
                    enviado = true
                    Task {
                        if cambiando != nil { await modelo.agenda.cambiar(a: c.franja) } else { await modelo.agenda.reservar(c.franja) }
                    }
                } label: {
                    Text(elegido.map { ReglasAgenda.textoBotonElegir($0, cambiando: cambiando != nil, zona: zona) } ?? "Elegí un horario")
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(BotonMarca())
                .disabled(elegido == nil)
                .accessibilityIdentifier("horario-confirmar")
            }
        }
        .padding(.horizontal, Espacio.m)
        .padding(.top, Espacio.s)
        .padding(.bottom, Espacio.xs)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    // MARK: Listo

    private func listo(_ r: ReservaAgenda) -> some View {
        ScrollView {
            VStack(spacing: Espacio.l) {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Color.sobreMarca)
                    .frame(width: 84, height: 84)
                    .background(Color.marca, in: .circle)
                    .padding(.top, Espacio.xl)
                    .accessibilityHidden(true)
                Text(cambiando == nil ? "Listo, quedó agendada" : "Listo, la cambiamos")
                    .font(Archivo.fuente(28, peso: 800, relativoA: .title1))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("horario-listo")
                if let i = ReglasGuia.instante(r.inicio) {
                    VStack(spacing: 4) {
                        Text(ReglasAgenda.tituloTarjeta(r.tipo)).font(.subheadline.weight(.bold)).foregroundStyle(Color.marcaTexto)
                        Text(ReglasAgenda.mayusculaPublica(ReglasAgenda.diaLargo(i, zona: zona))).font(.title3.weight(.semibold))
                        Text(ReglasAgenda.hora(i, zona: zona)).font(Archivo.fuente(44, peso: 800, relativoA: .largeTitle)).monospacedDigit()
                        if let ar = ReglasAgenda.horaArgentina(i, zona: zona) {
                            Text(ar).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(Espacio.l)
                    .superficieTarjeta(radio: Radio.tarjeta)
                    .accessibilityElement(children: .combine)
                }
                VStack(alignment: .leading, spacing: Espacio.s) {
                    LineaVideollamada(texto: "Vas a entrar a la videollamada desde la app, en Entreno. El botón se habilita 10 minutos antes.",
                                      icono: "hand.tap.fill")
                    if conAvisos {
                        LineaVideollamada(texto: "Te avisamos un día antes y cuando se habilite el botón.", icono: "bell.fill")
                    }
                    LineaVideollamada(texto: "Mati te admite en la sala. Si tarda un poco, esperá ahí sin salir.", icono: "person.crop.circle.badge.checkmark")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("horario-listo-texto")
                VStack(spacing: Espacio.xs) {
                    Button { cerrar() } label: { Text("Listo") }
                        .buttonStyle(BotonMarca())
                        .accessibilityIdentifier("horario-listo-cerrar")
                    Button { paraCalendario = true } label: { Label("Agregar a mi calendario", systemImage: "calendar.badge.plus") }
                        .buttonStyle(BotonSecundario(tono: .marcaTexto))
                        .accessibilityIdentifier("horario-calendario")
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.bottom, Espacio.l)
            .anchoLectura()
        }
    }
}

// MARK: - Avisos locales

/// Un día antes y cuando se habilita «Entrar». Solo con el permiso de notificaciones que la app ya tenía: nunca lo pide.
/// Se agendan con ids fijos (reprogramar pisa) y se borran si ya no hay reserva confirmada.
@MainActor
enum AvisosVideollamada {
    static func hayPermiso() async -> Bool {
        [.authorized, .provisional, .ephemeral].contains(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    static func programar(_ r: ReservaAgenda?, desdeMin: Int?) async {
        let centro = UNUserNotificationCenter.current()
        let ids = [ReglasAgenda.idAvisoDia, ReglasAgenda.idAvisoEntrar]
        #if DEBUG
        if AgendaUI.modelo != nil || UserDefaults.standard.bool(forKey: "guiaMuestra") { return }   // pruebas: sin avisos
        #endif
        centro.removePendingNotificationRequests(withIdentifiers: ids)
        // La demo (también la de Apple): ningún aviso real.
        guard !Proveedor.modelo.esDemo, await hayPermiso() else { return }
        for a in ReglasAgenda.avisosLocales(r, zona: AgendaUI.zona, desdeMin: desdeMin) {
            let c = UNMutableNotificationContent()
            c.title = a.titulo
            c.body = a.cuerpo
            c.sound = .default
            c.userInfo = ["destino": "train"]
            let t = UNTimeIntervalNotificationTrigger(timeInterval: max(1, a.fecha.timeIntervalSinceNow), repeats: false)
            try? await centro.add(UNNotificationRequest(identifier: a.id, content: c, trigger: t))
        }
    }
}
