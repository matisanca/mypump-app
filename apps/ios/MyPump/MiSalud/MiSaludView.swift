import SwiftUI
import MyPumpReglas
import MyPumpDatos

// «Mi salud» (pedido de Mati, 11/11: «ya son demasiadas secciones»): una sola pantalla con todo lo de salud, empujada dentro
// de Revisión, sin sumar pestañas. En orden y cada bloque solo si hoy se muestra: el próximo control, Estudios y órdenes,
// Presión arterial y Recuperación. Las vistas son las de siempre (`ProximoControlEstudios`, `EstudiosBloque`,
// `TarjetaPresion`, `PresionRaiz` y `RecuperacionTarjeta`): acá solo se juntan. Qué bloques van y qué dice la tarjeta de
// Revisión sale de `MiSalud` (kit), igual que en Android. Textos compartidos en `nativa-evidencia/mi-salud/DECISIONES.md`.

/// Lo que se sabe hoy de cada parte, leído de `ModeloApp` (las mismas condiciones con que cada cosa se mostraba antes).
@MainActor
enum MiSaludUI {
    /// Estudios habilitado (como la fila vieja de Mis datos).
    static func estudios(_ m: ModeloApp) -> ModeloEstudios? { m.estudios.flatMap { $0.habilitado ? $0 : nil } }
    static func presion(_ m: ModeloApp) -> ModeloPresion? { m.presion.flatMap { $0.habilitado ? $0 : nil } }

    static func partes(_ m: ModeloApp) -> MiSalud.Partes {
        let e = estudios(m)
        return MiSalud.Partes(control: e?.estado?.proximoControl != nil, estudios: e != nil, presion: presion(m) != nil, recuperacion: true)
    }

    /// Lo mismo que piden las tarjetas de arriba de Entreno (nunca en la demo ni en los bocetos).
    static func pendientes(_ m: ModeloApp) -> MiSalud.Pendientes {
        guard !m.conMuestras else { return MiSalud.Pendientes() }
        let e = estudios(m)
        let presion: String? = switch presion(m)?.tarjeta {
        case .repetir: MiSalud.repetirPresion
        case .preparar: MiSalud.prepararPresion
        case .toma(_, _, let faltan): MiSalud.faltanTomas(faltan)
        case .hoyListo, nil: nil
        }
        return MiSalud.Pendientes(estudios: e?.tarjetaInicio?.titulo, control: m.palanca.controlesApp && e?.tarjetaControl != nil, presion: presion)
    }

    static func tarjeta(_ m: ModeloApp) -> MiSalud.Tarjeta? { MiSalud.tarjeta(partes(m), pendientes: pendientes(m)) }
}

/// La tarjeta grande de arriba de Revisión: «Mi salud», qué hay adentro o lo primero pendiente, con el número de cosas por
/// hacer. Sin ningún bloque no existe.
struct TarjetaMiSalud: View {
    let abrir: () -> Void
    @State private var app = Proveedor.modelo
    @ScaledMetric(relativeTo: .title2) private var ladoIcono: CGFloat = 48
    @ScaledMetric(relativeTo: .body) private var ladoInsignia: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        if let t = MiSaludUI.tarjeta(app) {
            Button(action: abrir) {
                let apilada = letra.isAccessibilitySize
                let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.m))
                disposicion {
                    HStack(spacing: Espacio.s) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: ladoIcono * 0.45, weight: .bold))
                            .foregroundStyle(Color.sobreMarca)
                            .frame(width: ladoIcono, height: ladoIcono)
                            .background(Color.marca, in: .rect(cornerRadius: ladoIcono * 0.27, style: .continuous))
                        // Con letra de accesibilidad, el número y la flecha van arriba, al lado del ícono.
                        if apilada { Spacer(minLength: 0); insignia(t.cuenta); flecha }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MiSalud.titulo).font(.title2.weight(.bold)).foregroundStyle(.primary)
                        Text(t.linea)
                            .font(.body.weight(t.cuenta > 0 ? .semibold : .regular))
                            .foregroundStyle(t.cuenta > 0 ? Color.primary : Color.secondary)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    if !apilada { Spacer(minLength: 0); insignia(t.cuenta); flecha }
                }
                .padding(Espacio.m)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
                .superficieTarjeta()
                .overlay {
                    if t.cuenta > 0 {
                        RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).strokeBorder(Color.marcaVivo, lineWidth: 2)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(t.cuenta > 0 ? "\(MiSalud.titulo), \(t.cuenta) para hacer. \(t.linea)" : "\(MiSalud.titulo). \(t.linea)")
            .accessibilityHint(MiSalud.abre)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("tarjeta-mi-salud")
        }
    }

    @ViewBuilder private func insignia(_ n: Int) -> some View {
        if n > 0 {
            Text(verbatim: "\(n)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.sobreMarca)
                .frame(minWidth: ladoInsignia, minHeight: ladoInsignia)
                .background(Color.marcaVivo, in: .circle)
                .accessibilityIdentifier("tarjeta-mi-salud-cuenta")
        }
    }

    private var flecha: some View {
        Image(systemName: "chevron.right").font(.body.weight(.bold)).foregroundStyle(.tertiary)
    }
}

/// Arriba de Entreno (simplificar, 11/11): en lugar de las tarjetas de presión, estudios y control, UNA sola «Mi salud», y
/// solo con algo para hacer. Verde como las viejas, con la línea de lo primero pendiente, el número de cosas y un botón
/// grande con el texto de siempre de esa cosa. El botón lleva a lo primero pendiente: estudios y control a su bloque de Mi
/// salud; la presión, directo a la toma (con Mi salud debajo), como la tarjeta vieja.
struct TarjetaMiSaludInicio: View {
    @State private var app = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @ScaledMetric(relativeTo: .title2) private var ladoIcono: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var ladoInsignia: CGFloat = 30
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        let partes = MiSaludUI.partes(app), pendientes = MiSaludUI.pendientes(app)
        if let t = MiSalud.tarjeta(partes, pendientes: pendientes), t.cuenta > 0,
           let primero = MiSalud.primerPendiente(partes, pendientes: pendientes), let boton = boton(primero) {
            let apilada = letra.isAccessibilitySize
            VStack(alignment: .leading, spacing: Espacio.s) {
                let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
                disposicion {
                    HStack(spacing: Espacio.s) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: ladoIcono * 0.42, weight: .bold))
                            .frame(width: ladoIcono, height: ladoIcono)
                            .background(.white.opacity(0.2), in: .circle)
                        if apilada { Spacer(minLength: 0); insignia(t.cuenta) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MiSalud.cejaInicio)
                            .textCase(.uppercase)
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                        Text(t.linea).font(.title3.weight(.bold))
                        if let mas = MiSalud.masCosas(t.cuenta) { Text(mas).font(.body.weight(.medium)) }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    if !apilada { Spacer(minLength: 0); insignia(t.cuenta) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(MiSalud.titulo), \(t.cuenta) para hacer. \(t.linea)")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("tarjeta-mi-salud-inicio-texto")

                Button { withAnimation(.snappy) { ir(primero) } } label: {
                    Label(boton.texto, systemImage: boton.icono).multilineTextAlignment(.center)
                }
                .buttonStyle(BotonSobreVerde())
                .accessibilityLabel(boton.texto)
                .accessibilityHint(t.linea)
                .accessibilityIdentifier("tarjeta-mi-salud-inicio-boton")
            }
            .foregroundStyle(.white)
            .padding(Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.guiaDestacada, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .shadow(color: Color.guiaDestacada.opacity(0.28), radius: 16, x: 0, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("tarjeta-mi-salud-inicio")
        }
    }

    /// El texto del botón de la tarjeta vieja de esa cosa.
    private func boton(_ b: MiSalud.Bloque) -> (texto: String, icono: String)? {
        let e = MiSaludUI.estudios(app)
        switch b {
        case .estudios:
            guard let t = e?.tarjetaInicio else { return nil }
            return (t.boton, t.nueva ? "arrow.right" : "arrow.up.doc.fill")
        case .control:
            guard let t = e?.tarjetaControl else { return (TextosControles.verMisEstudios, "arrow.right") }
            return (t.boton, "arrow.right")
        case .presion:
            switch MiSaludUI.presion(app)?.tarjeta {
            case .repetir: return (NP.repetir, "heart.text.square.fill")
            case .preparar: return (NP.empezar, "heart.text.square.fill")
            case .toma: return (NP.tomaDeHoy, "heart.text.square.fill")
            case .hoyListo, nil: return nil
            }
        case .recuperacion: return nil
        }
    }

    private func ir(_ b: MiSalud.Bloque) {
        switch b {
        case .estudios: navegacion?.irAEstudios()
        // Sin el bloque «Próximo control» (otra lectura del servidor), el control se ve en Estudios.
        case .control: if MiSaludUI.partes(app).control { navegacion?.irAMiSalud(.control) } else { navegacion?.irAEstudios() }
        case .presion: navegacion?.irAPresion()
        case .recuperacion: navegacion?.irAMiSalud(.recuperacion)
        }
    }

    @ViewBuilder private func insignia(_ n: Int) -> some View {
        Text(verbatim: "\(n)")
            .font(.headline.monospacedDigit())
            .foregroundStyle(Color.guiaSobreBlanco)
            .frame(minWidth: ladoInsignia, minHeight: ladoInsignia)
            .background(.white, in: .circle)
            .accessibilityIdentifier("tarjeta-mi-salud-inicio-cuenta")
    }
}

/// La fila «Mi salud» de Mis datos: donde estaban «Estudios y órdenes», «Presión arterial» y la recuperación. Con un estudio
/// o una orden sin ver, el punto.
struct FilaMiSaludMisDatos: View {
    @State private var app = Proveedor.modelo

    var body: some View {
        NavigationLink(value: RutaRevision.miSalud) {
            HStack(spacing: Espacio.s) {
                Label { Text(MiSalud.titulo).foregroundStyle(.primary) } icon: { IconoAzulejo("heart.fill", color: .marcaTexto) }
                Spacer(minLength: 0)
                if !app.conMuestras, app.estudios?.hayNovedad == true { PuntoNovedad().accessibilityIdentifier("mis-datos-mi-salud-novedad") }
            }
        }
        .accessibilityIdentifier("mis-datos-mi-salud")
    }
}

/// Lo que se empuja dentro de Revisión.
enum RutaRevision: Hashable { case misDatos, miSalud, novedades }

/// La pantalla «Mi salud».
struct MiSaludView: View {
    @State private var app = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?

    var body: some View {
        let bloques = MiSalud.bloques(MiSaludUI.partes(app))
        ScrollViewReader { lector in
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.xl) {
                    if bloques.isEmpty {
                        Text(MiSalud.vacio)
                            .font(.body).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("mi-salud-vacio")
                    }
                    ForEach(bloques, id: \.self) { b in
                        bloque(b, lector: lector)
                            .id(b)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(b.etiqueta)
                    }
                }
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.xs)
                .padding(.bottom, Espacio.xl)
                .anchoLectura()
            }
            // Un aviso, un link o una tarjeta piden un bloque: se va (si está) y se consume.
            .onChange(of: navegacion?.bloqueMiSalud, initial: true) { _, pedido in
                guard let pedido else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    if bloques.contains(pedido) { withAnimation(.snappy) { lector.scrollTo(pedido, anchor: .top) } }
                    navegacion?.bloqueMiSalud = nil
                }
            }
        }
        .background(Color.fondo)
        .navigationTitle(MiSalud.titulo)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            async let e: Void = MiSaludUI.estudios(app)?.sincronizar() ?? ()
            async let p: Void = MiSaludUI.presion(app)?.refrescar() ?? ()
            async let s: Void = (app.conMuestras ? nil : app.salud)?.cargar() ?? ()
            _ = await (e, p, s)
        }
        // Se pidió Estudios y la sección no está (palanca apagada, cuenta sin la función, `get` caído): el pedido no queda
        // esperando. Si está, `EstudiosBloque` lo consume y va a la tarjeta nueva.
        .task(id: navegacion?.estudios ?? false) {
            guard navegacion?.estudios == true else { return }
            let seccion = await app.estudiosParaAviso()
            if !Task.isCancelled, seccion == nil { navegacion?.estudios = false }
        }
        // La presión se refresca al llegar (la tarjeta del bloque sale de ahí).
        .task { await MiSaludUI.presion(app)?.refrescar() }
    }

    @ViewBuilder private func bloque(_ b: MiSalud.Bloque, lector: ScrollViewProxy) -> some View {
        switch b {
        case .control:
            if let c = MiSaludUI.estudios(app)?.estado?.proximoControl { ProximoControlEstudios(control: c) }
        case .estudios:
            if let e = MiSaludUI.estudios(app) {
                VStack(alignment: .leading, spacing: Espacio.s) {
                    titulo(MiSalud.tituloEstudios)
                    EstudiosBloque(modelo: e, lector: lector)
                }
            }
        case .presion:
            if let p = MiSaludUI.presion(app) {
                VStack(alignment: .leading, spacing: Espacio.s) {
                    titulo(MiSalud.tituloPresion)
                    TarjetaPresion()
                    Button { navegacion?.abrirPresion(directo: false) } label: {
                        HStack(spacing: Espacio.s) {
                            Label { Text(MiSalud.verPresion).foregroundStyle(.primary) } icon: { IconoAzulejo("heart.text.square.fill", color: .marcaTexto) }
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        .padding(Espacio.m)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(FilaPresionable())
                    .superficieTarjeta()
                    .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
                    .accessibilityIdentifier("mi-salud-ver-presion")
                    .task { p.drenarEnFondo() }
                }
            }
        case .recuperacion:
            // La fila que estaba en «Cómo vengo» de Revisión: abre Salud en Recuperación (y vuelve acá al cerrarla).
            RecuperacionTarjeta(modelo: app.conMuestras ? nil : app.salud, enFila: true) { navegacion?.irASalud(.recuperacion) }
                .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
                .superficieTarjeta()
        }
    }

    private func titulo(_ t: String) -> some View {
        Text(t).font(.title2.weight(.bold)).foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
