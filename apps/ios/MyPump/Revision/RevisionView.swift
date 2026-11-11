import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Revisión: arriba de todo la devolución de Mati, si hay una publicada (2.3.0); después las tarjetas Recuperación y Tu progreso, que abren Salud (2.1.0, pedido de Mati del 4-nov:
/// Salud ya no es una pestaña); después subir la semana: las fotos y el check, que trae el peso del día y la salud de los últimos 7 días. En
/// iPad, las dos tarjetas lado a lado y debajo dos columnas: las fotos a la izquierda, el check a la derecha. Con una cuenta sale de `ModeloRevision` y `ModeloFotos`; en la demo y en los bocetos, de las
/// muestras.
struct RevisionView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    @Environment(\.horizontalSizeClass) private var claseAncho
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @State private var misDatos = false
    /// El check guiado abierto, y en qué paso si se pidió uno («Subir fotos»).
    @State private var flujoGuiado: AperturaCheck?

    /// Un aviso o el banner pidieron el check: se abre apenas se sabe que corresponde (`resolverApertura`).
    @State private var abrirPendiente = false

    private func resolverApertura() {
        guard abrirPendiente, let revision, revision.cargadaUnaVez else { return }
        abrirPendiente = false
        if let guiado, !guiado.checkinEnviado, flujoGuiado == nil { flujoGuiado = AperturaCheck(paso: nil) }
    }

    private struct AperturaCheck: Identifiable {
        let id = UUID()
        let paso: CheckGuiado.Paso?
    }
    /// Check guiado: con cuenta y con la palanca `check_guiado` prendida. Apagada, la Revisión de siempre.
    private var guiado: ModeloRevision? { modelo.palanca.checkGuiado ? revision : nil }

    private var revision: ModeloRevision? { modelo.conMuestras ? nil : modelo.revision }
    private var modeloFotos: ModeloFotos? { modelo.conMuestras ? nil : modelo.fotos }
    /// Sin cuenta: las muestras en los bocetos; la demo, como la web, sin fotos ni check.
    private var muestras: Muestras { datos.paraPantalla() }

    var body: some View {
        NavigationStack {
            ScrollViewReader { lector in
                ScrollView {
                    Group {
                        if claseAncho == .regular {
                            VStack(alignment: .leading, spacing: Espacio.l) {
                                TarjetaFotosInicio()
                                devolucion
                                if guiado != nil { check; tuCambio }
                                HStack(alignment: .top, spacing: Espacio.l) {
                                    recuperacion.frame(maxWidth: .infinity, alignment: .top)
                                    progreso.frame(maxWidth: .infinity, alignment: .top)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                diaDeRevision
                                avisoPlan
                                notaSemanal
                                // Cada columna a su alto ideal: si no, la pila horizontal negocia alturas y corta textos.
                                HStack(alignment: .top, spacing: Espacio.l) {
                                    VStack(alignment: .leading, spacing: Espacio.xl) { fotos }
                                        .frame(maxWidth: .infinity, alignment: .top)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .topeArriba()
                                    if guiado == nil {
                                        VStack(alignment: .leading, spacing: Espacio.xl) { check }
                                            .frame(maxWidth: .infinity, alignment: .top)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .topeArriba()
                                    }
                                }
                            }
                            .anchoLectura(Ancho.doble)
                        } else {
                            VStack(alignment: .leading, spacing: Espacio.xl) {
                                // La explicación de la semana va pegada al título: es contexto de toda la pantalla.
                                notaSemanal
                                TarjetaFotosInicio()
                                devolucion   // lo que Mati le dejó va primero, con la semana a medias o no
                                // Check guiado: la tarjeta va arriba, para que nadie tenga que buscarla.
                                if guiado != nil { check; tuCambio }
                                if semanaPendiente {
                                    // U1 (auditoría del 10/11): con la semana a medias, lo que vino a hacer va arriba. Antes las
                                    // fotos y el check quedaban fuera de la primera pantalla de un iPhone común.
                                    diaDeRevision; avisoPlan; fotos
                                    if guiado == nil { check }
                                    comoVengo
                                } else {
                                    comoVengo
                                    diaDeRevision; avisoPlan; fotos
                                    if guiado == nil { check }
                                }
                            }
                                .anchoLectura()
                        }
                    }
                    .padding(.horizontal, Espacio.m)
                    .padding(.top, Espacio.xs)
                    .padding(.bottom, Espacio.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                // Tirar para actualizar: el check y las fotos (sin cuenta no hay nada que traer).
                .refreshable {
                    guard let revision else { return }
                    async let r: Void = revision.cargarRevision()
                    async let f: Void = modeloFotos?.cargar() ?? ()
                    async let s: Void = modelo.salud?.cargar() ?? ()
                    async let d: Void = modelo.palanca.devolucionSemanal ? (modelo.devolucion?.refrescar() ?? ()) : ()
                    _ = await (r, f, s, d)
                }
                .task {
                    // Bocetos: `-ir check` (o fotos) abre desplazado hasta esa sección.
                    guard let ancla = DemoUI.ir else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    lector.scrollTo(ancla, anchor: .top)
                    if ancla == "check" { abrirPendiente = true; resolverApertura() }
                }
                // Un aviso o el banner de las otras pestañas piden una sección: se va y se consume.
                .onChange(of: navegacion?.anclaRevision, initial: true) { _, ancla in
                    guard let ancla else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        // «aviso» (tocar la notificación de revisión) no desplaza: solo abre el check guiado si corresponde.
                        if ancla != "aviso" { withAnimation(.snappy) { lector.scrollTo(ancla, anchor: .top) } }
                        navegacion?.anclaRevision = nil
                        // Check guiado: el aviso y el banner llevan directo al paso a paso, no solo a la tarjeta.
                        if ancla == "check" || ancla == "aviso" { abrirPendiente = true; resolverApertura() }
                    }
                }
            }
            .background(Color.fondo)
            .navigationTitle("Revisión")
            .subtituloNavegacion(Self.semanaActual())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Un solo camino a Mis datos (el mismo que usan los avisos): así nunca se apila dos veces.
                    Button { misDatos = true } label: {
                        Image(systemName: "person.crop.circle")
                            // Un estudio o una orden sin ver: el punto sigue hasta la fila «Estudios y órdenes».
                            .overlay(alignment: .topTrailing) {
                                if novedadEstudios {
                                    Circle().fill(Color.marcaVivo).frame(width: 10, height: 10).offset(x: 3, y: -3).accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel("Mis datos")
                    .accessibilityValue(novedadEstudios ? TextosEstudios.novedad : "")
                }
            }
            .navigationDestination(isPresented: $misDatos) { MisDatosView(datos: datos) }
        }
        // El aviso pudo llegar antes de saber si la palanca está prendida o si el check ya salió: se resuelve al saberlo.
        .onChange(of: revision?.cargadaUnaVez) { _, _ in resolverApertura() }
        .onChange(of: modelo.palanca.checkGuiado) { _, prendida in
            // Si se apaga con el paso a paso abierto, se cierra: no queda una pantalla vacía.
            if !prendida { flujoGuiado = nil }
            resolverApertura()
        }
        .fullScreenCover(item: $flujoGuiado) { apertura in
            if let guiado {
                CheckGuiadoFlujo(revision: guiado, fotos: modeloFotos, saludSemana: saludSemana, sincronizarSalud: sincronizarSalud,
                                 pasoInicial: apertura.paso, tuCambio: fuentesTuCambio)
            }
        }
        .onAppear { if DemoUI.abrir == "misdatos" || DemoUI.abrir == "novedades" { misDatos = true } }
        .onChange(of: navegacion?.misDatos ?? false, initial: true) { _, abrir in
            guard abrir else { return }
            misDatos = true
            navegacion?.misDatos = false
        }
    }

    /// La devolución de Mati, arriba de todo. Sin cuenta, apagada o sin ninguna publicada, no hay nada.
    @ViewBuilder private var devolucion: some View {
        if !modelo.conMuestras, modelo.palanca.devolucionSemanal, let d = modelo.devolucion, let ultima = d.ultima {
            DevolucionTarjeta(ultima: ultima, anteriores: d.anteriores)
                .id("devolucion")
        } else if modelo.demoConHistorial, let d = modelo.demoHistorial?.devoluciones, let ultima = d.ultima {
            // La demo: las devoluciones de ejemplo de su historial (no se pide ni se marca nada).
            DevolucionTarjeta(ultima: ultima, anteriores: d.anteriores)
                .id("devolucion")
        }
    }
    /// Hay un estudio pedido o una orden sin ver (nunca en la demo ni en los bocetos).
    private var novedadEstudios: Bool { !modelo.conMuestras && modelo.estudios?.hayNovedad == true }

    /// Quien revisa otro día que el domingo lo ve acá (el dato lo carga el equipo). El domingo no agrega nada.
    @ViewBuilder private var diaDeRevision: some View {
        if let texto = SemanaRevision.textoDia(modelo.diaDeRevision) {
            Text(texto)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("dia-de-revision")
        }
    }

    /// GEN-05: al plan publicado le falta algo. No es para el cliente sino para la captura que le manda a Mati (qué
    /// republicar): discreto, con el detalle chico y gris.
    @ViewBuilder private var avisoPlan: some View {
        if let aviso = modelo.avisoPlanIncompleto {
            HStack(alignment: .top, spacing: Espacio.s) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.alerta)
                VStack(alignment: .leading, spacing: 4) {
                    Text(aviso.texto).font(.subheadline)
                    Text(aviso.detalle).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.alerta.opacity(0.10), in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("aviso-plan-incompleto")
        }
    }

    /// Lo principal de Salud; tocarla abre Salud en Recuperación.
    private var recuperacion: some View {
        RecuperacionTarjeta(modelo: modelo.conMuestras ? nil : modelo.salud) { navegacion?.irASalud(.recuperacion) }
            .id("recuperacion")
    }
    /// Las dos de Salud son una sola cosa («cómo vengo»): una tarjeta de dos filas con azulejo suave.
    private var comoVengo: some View {
        VStack(spacing: 0) {
            recuperacionFila
            Divider().padding(.leading, 58)
            progresoFila
        }
        .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
        .superficieTarjeta()
    }
    private var recuperacionFila: some View {
        RecuperacionTarjeta(modelo: modelo.conMuestras ? nil : modelo.salud, enFila: true) { navegacion?.irASalud(.recuperacion) }
            .id("recuperacion")
    }
    private var progresoFila: some View {
        ProgresoTarjeta(linea: lineaProgreso, enFila: true) { navegacion?.irASalud(.fuerza) }
            .id("progreso")
            .task {
                guard let p = modelo.conMuestras ? nil : modelo.progreso, p.tarjetas.isEmpty || p.estado == .sinRed else { return }
                await modelo.cargarProgresoSiHaceFalta()
            }
    }
    /// Lo que era la pestaña Progreso, en una línea; tocarla abre Salud en Fuerza.
    private var progreso: some View {
        ProgresoTarjeta(linea: lineaProgreso) { navegacion?.irASalud(.fuerza) }
            .id("progreso")
            // El historial se trae al abrir Fuerza; si todavía no se abrió, acá (una vez, o al volver la red).
            .task {
                guard let p = modelo.conMuestras ? nil : modelo.progreso, p.tarjetas.isEmpty || p.estado == .sinRed else { return }
                await modelo.cargarProgresoSiHaceFalta()
            }
    }
    private var lineaProgreso: ProgresoSemana.Linea? {
        if modelo.demoConHistorial {
            // La demo: lo mismo, con las series de su historial de ejemplo.
            let lineas = LineaProgreso.desdeMuestras(muestras)
            return ProgresoSemana.linea(lineas.map { ProgresoSemana.ejercicio(nombre: $0.nombre, filas: $0.filas) }, hoy: FechaLocal.hoy())
        }
        guard let p = modelo.conMuestras ? nil : modelo.progreso else { return nil }
        return ProgresoSemana.linea(p.tarjetas.map { ProgresoSemana.ejercicio(nombre: $0.nombre, filas: $0.filas) }, hoy: FechaLocal.hoy())
    }
    /// Faltan fotos o el check de esta semana (con cuenta; la demo y las muestras siguen con el orden de siempre).
    private var semanaPendiente: Bool {
        guard let revision, let modeloFotos else { return false }
        return FotosProgreso.pendientes(checkinEnviado: revision.checkinEnviado, posesDeLaSemana: modeloFotos.posesDeLaSemana).total > 0
    }
    private var fotos: some View {
        FotosSemana(modelo: modeloFotos, muestras: muestras.fotos, peso: revision?.serieDePeso ?? PesoCorporal.serie(muestras.salud),
                    tuCambio: fuentesTuCambio)
            .id("fotos")
    }
    /// «Tu cambio» (pedido de Mati del 11/11): con cuenta y con la palanca `check_guiado`. Apagada, nada de esto existe.
    private var fuentesTuCambio: FuentesTuCambio? {
        guard let guiado, let modeloFotos else { return nil }
        return FuentesTuCambio(fotos: modeloFotos, inicio: modelo.fotosInicio, peso: guiado.serieDePeso)
    }
    @ViewBuilder private var tuCambio: some View {
        if let fuentesTuCambio { TuCambioTarjeta(fuentes: fuentesTuCambio).id("tucambio") }
    }
    private var notaSemanal: some View {
        Text(SemanaRevision.explicacion)
            .font(.footnote)
            .foregroundStyle(Color.apoyo)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("nota-revision-semanal")
    }

    @ViewBuilder private var check: some View {
        if let guiado {
            CheckGuiadoTarjeta(revision: guiado, faltanFotos: (modeloFotos?.posesDeLaSemana.count ?? 3) < 3) { paso in
                flujoGuiado = AperturaCheck(paso: paso)
            }
            .id("check")
        } else {
            checkDeSiempre
        }
    }

    private var checkDeSiempre: some View {
        CheckSemanal(revision: revision, muestra: DemoUI.lleno ? MuestrasExtra.checkinLleno : muestras.checkin,
                     saludSemana: saludSemana, sincronizarSalud: sincronizarSalud).id("check")
    }
    /// Lo de salud que acompaña al check: con cuenta, de `ModeloSalud`; sin cuenta, de las muestras (vacías en la demo).
    private var saludSemana: [SaludSemana.Fila] {
        if let s = modelo.conMuestras ? nil : modelo.salud {
            return SaludSemana.resumen(salud: s.salud, recuperacion: s.recuperacion, hoy: s.fecha, mostrarScore: s.mostrarRecuperacion)
        }
        return SaludSemana.resumen(salud: muestras.salud, recuperacion: [], hoy: FechaLocal.hoy(), mostrarScore: false)
    }
    private var sincronizarSalud: (() -> Void)? {
        guard let s = modelo.conMuestras ? nil : modelo.salud, s.conectado else { return nil }
        return { Task { _ = await s.sincronizar() } }
    }
    /// "Semana del 12 al 18 de octubre" (de lunes a domingo).
    static func semanaActual(_ hoy: Date = .now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.locale = Locale(identifier: "es_AR")
        guard let lunes = cal.dateInterval(of: .weekOfYear, for: hoy)?.start,
              let domingo = cal.date(byAdding: .day, value: 6, to: lunes) else { return "" }
        let es = Locale(identifier: "es_AR")
        let mismoMes = cal.component(.month, from: lunes) == cal.component(.month, from: domingo)
        let desde = mismoMes
            ? lunes.formatted(.dateTime.day().locale(es))
            : lunes.formatted(.dateTime.day().month(.wide).locale(es))
        let hasta = domingo.formatted(.dateTime.day().month(.wide).locale(es))
        return "Semana del \(desde) al \(hasta)"
    }
}
