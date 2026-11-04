import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Revisión: arriba de todo las tarjetas Recuperación y Tu progreso, que abren Salud (2.1.0, pedido de Mati del 4-nov:
/// Salud ya no es una pestaña); después subir la semana: las fotos y el check, que trae el peso del día y la salud de los últimos 7 días. En
/// iPad, las dos tarjetas lado a lado y debajo dos columnas: las fotos a la izquierda, el check a la derecha. Con una cuenta sale de `ModeloRevision` y `ModeloFotos`; en la demo y en los bocetos, de las
/// muestras.
struct RevisionView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    @Environment(\.horizontalSizeClass) private var claseAncho
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @State private var misDatos = false

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
                                HStack(alignment: .top, spacing: Espacio.l) {
                                    recuperacion.frame(maxWidth: .infinity, alignment: .top)
                                    progreso.frame(maxWidth: .infinity, alignment: .top)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                avisoPlan
                                // Cada columna a su alto ideal: si no, la pila horizontal negocia alturas y corta textos.
                                HStack(alignment: .top, spacing: Espacio.l) {
                                    VStack(alignment: .leading, spacing: Espacio.xl) { fotos }
                                        .frame(maxWidth: .infinity, alignment: .top)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .topeArriba()
                                    VStack(alignment: .leading, spacing: Espacio.xl) { check }
                                        .frame(maxWidth: .infinity, alignment: .top)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .topeArriba()
                                }
                            }
                            .anchoLectura(Ancho.doble)
                        } else {
                            VStack(alignment: .leading, spacing: Espacio.xl) {
                                // Las dos tarjetas de Salud, juntas: son una sola cosa ("cómo vengo").
                                VStack(spacing: Espacio.m) { recuperacion; progreso }
                                avisoPlan; fotos; check
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
                    _ = await (r, f, s)
                }
                .task {
                    // Bocetos: `-ir check` (o fotos) abre desplazado hasta esa sección.
                    guard let ancla = DemoUI.ir else { return }
                    try? await Task.sleep(for: .milliseconds(350))
                    lector.scrollTo(ancla, anchor: .top)
                }
                // Un aviso o el banner de las otras pestañas piden una sección: se va y se consume.
                .onChange(of: navegacion?.anclaRevision, initial: true) { _, ancla in
                    guard let ancla else { return }
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.snappy) { lector.scrollTo(ancla, anchor: .top) }
                        navegacion?.anclaRevision = nil
                    }
                }
            }
            .background(Color.fondo)
            .navigationTitle("Revisión")
            .subtituloNavegacion(Self.semanaActual())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { MisDatosView(datos: datos) } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Mis datos")
                }
            }
            .navigationDestination(isPresented: $misDatos) { MisDatosView(datos: datos) }
        }
        .onAppear { if DemoUI.abrir == "misdatos" { misDatos = true } }
        .onChange(of: navegacion?.misDatos ?? false, initial: true) { _, abrir in
            guard abrir else { return }
            misDatos = true
            navegacion?.misDatos = false
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
    /// Lo que era la pestaña Progreso, en una línea; tocarla abre Salud en Fuerza.
    private var progreso: some View {
        ProgresoTarjeta(linea: lineaProgreso) { navegacion?.irASalud(.fuerza) }
            .id("progreso")
            // El historial se trae al abrir Fuerza; si todavía no se abrió, acá (una vez, o al volver la red).
            .task {
                guard let p = modelo.conMuestras ? nil : modelo.progreso, p.tarjetas.isEmpty || p.estado == .sinRed else { return }
                await modelo.cargarProgreso()
            }
    }
    private var lineaProgreso: ProgresoSemana.Linea? {
        guard let p = modelo.conMuestras ? nil : modelo.progreso else { return nil }
        return ProgresoSemana.linea(p.tarjetas.map { ProgresoSemana.ejercicio(nombre: $0.nombre, filas: $0.filas) }, hoy: FechaLocal.hoy())
    }
    private var fotos: some View {
        FotosSemana(modelo: modeloFotos, muestras: muestras.fotos, peso: revision?.serieDePeso ?? PesoCorporal.serie(muestras.salud))
            .id("fotos")
    }
    private var check: some View {
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
