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
struct TarjetaVideollamadaEntreno: View {
    let modelo: ModeloGuia
    @State private var elegir = false

    var body: some View {
        let r = modelo.reservaTarjeta()
        Group {
            if r != nil {
                TimelineView(.periodic(from: .now, by: 15)) { ctx in
                    if let r = modelo.reservaTarjeta(ahora: ctx.date) {
                        TarjetaVideollamada(modelo: modelo, reserva: r, ahora: ctx.date)
                            // En la ventana: la agenda cada 30 s (el link si falta y «Mati ya está en la sala»). Si la reserva
                            // vino solo del resumen (la guía no se abrió), primero se trae la agenda.
                            .task(id: r) {
                                if modelo.agenda.agenda?.reserva == nil { await modelo.agenda.consultar() }
                                await modelo.agenda.vigilarSala()
                            }
                    }
                }
            } else if Videollamada.elegirHorario, case .franjas = modelo.vistaAgenda {
                TarjetaElegirHorario(modelo: modelo) { elegir = true }
            }
        }
        .task(id: claveAvisos(r)) { await AvisosVideollamada.programar(r, desdeMin: modelo.agenda.entrarDesdeMin) }
        .task { if Videollamada.elegirHorario, r == nil { await modelo.agenda.consultar() } }
        .sheet(isPresented: $elegir) { PantallaHorario(modelo: modelo, cambiando: nil) }
    }

    private func claveAvisos(_ r: ReservaAgenda?) -> String {
        guard let r, r.estado == .confirmada else { return "" }
        return "\(r.inicio)|\(r.tipo.rawValue)|\(modelo.agenda.entrarDesdeMin ?? 0)"
    }
}

// MARK: - La tarjeta de la videollamada (Entreno y el final de la guía)

struct TarjetaVideollamada: View {
    let modelo: ModeloGuia
    let reserva: ReservaAgenda
    var ahora: Date = Date()
    @State private var paraCalendario = false
    @State private var cambiar = false
    @State private var ayuda = false
    @Environment(\.openURL) private var abrirURL
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
                    if let u = reserva.meetUrl { abrirURL(u) }
                } label: {
                    Label("Entrar a la videollamada", systemImage: "video.fill")
                        .font(.headline)
                        .foregroundStyle(Color.marcaTexto)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Color.blancoFijo, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre Google Meet. Mati te admite en la sala")
                .accessibilityIdentifier("agenda-entrar")
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
                Button { paraCalendario = true } label: { Label("Al calendario", systemImage: "calendar.badge.plus") }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    .accessibilityLabel("Agregar a mi calendario")
                    .accessibilityIdentifier("agenda-calendario")
                if puedeCambiar {
                    Button { cambiar = true } label: { Label("Cambiar horario", systemImage: "arrow.triangle.2.circlepath") }
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
        if let c = cambiando { return r.inicio != c.inicio ? r : nil }
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
        guard await hayPermiso() else { return }
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
