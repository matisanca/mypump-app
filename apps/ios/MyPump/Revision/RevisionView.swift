import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Revisión: lo de la semana (fotos, check, peso), el reloj y, al final, Mi Día (lo de todos los días). Mismo orden
/// que la web (REV-01). En iPad, en dos columnas: lo semanal a la izquierda, lo diario a la derecha. Con una cuenta
/// sale de `ModeloRevision` y `ModeloFotos`; en la demo y en los bocetos, de las muestras.
struct RevisionView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    @Environment(\.horizontalSizeClass) private var claseAncho
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @State private var misDatos = false

    private var revision: ModeloRevision? { modelo.conMuestras ? nil : modelo.revision }
    private var modeloFotos: ModeloFotos? { modelo.conMuestras ? nil : modelo.fotos }

    var body: some View {
        NavigationStack {
            ScrollViewReader { lector in
                ScrollView {
                    Group {
                        if claseAncho == .regular {
                            // Cada columna a su alto ideal: si no, la pila horizontal negocia alturas y corta textos.
                            HStack(alignment: .top, spacing: Espacio.l) {
                                VStack(alignment: .leading, spacing: Espacio.xl) { fotos; check; peso }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .topeArriba()
                                VStack(alignment: .leading, spacing: Espacio.xl) { miDia; reloj }
                                    .frame(maxWidth: .infinity, alignment: .top)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .topeArriba()
                            }
                            .anchoLectura(Ancho.doble)
                        } else {
                            VStack(alignment: .leading, spacing: Espacio.xl) { fotos; check; peso; reloj; miDia }
                                .anchoLectura()
                        }
                    }
                    .padding(.horizontal, Espacio.m)
                    .padding(.top, Espacio.xs)
                    .padding(.bottom, Espacio.xl)
                }
                .scrollDismissesKeyboard(.interactively)
                // Tirar para actualizar: el check, el peso, Mi Día y las fotos (sin cuenta no hay nada que traer).
                .refreshable {
                    guard let revision else { return }
                    async let r: Void = revision.cargarRevision()
                    async let d: Void = revision.cargarMiDia()
                    async let f: Void = modeloFotos?.cargar() ?? ()
                    _ = await (r, d, f)
                }
                .task {
                    // Bocetos: `-ir peso` (o check, reloj, midia, dias) abre desplazado hasta esa sección.
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

    private var fotos: some View {
        FotosSemana(modelo: modeloFotos, muestras: datos.fotos, peso: revision?.serieDePeso ?? PesoCorporal.serie(datos.salud))
            .id("fotos")
    }
    private var check: some View {
        CheckSemanal(revision: revision, muestra: DemoUI.lleno ? MuestrasExtra.checkinLleno : datos.checkin).id("check")
    }
    private var peso: some View { PesoTarjeta(revision: revision, saludMuestra: datos.salud).id("peso") }
    private var reloj: some View { MiReloj().id("reloj") }
    private var miDia: some View {
        MiDia(revision: revision, muestra: muestraMiDia).id("midia")
    }

    /// La demo de la web viene sembrada (racha 3); los bocetos llenos, con 30 días de historia; si no, las muestras.
    private var muestraMiDia: MuestrasExtra.MiDia {
        if modelo.esDemo { return MuestrasExtra.demo }
        if DemoUI.lleno { return MuestrasExtra.lleno }
        return MuestrasExtra.MiDia(racha: datos.racha, habitos: datos.habitos, adherencia: datos.adherencia)
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

// MARK: - Mi reloj

/// Oura y WHOOP (REV-08). La autorización se abre en el navegador del sistema; acá, el boceto de las filas.
private struct MiReloj: View {
    private let proveedores = [
        ("Oura", "Anillo · trae sueño, pulso y variabilidad reales", "circle.circle", Color.sueno),
        ("WHOOP", "Banda · trae sueño, pulso y variabilidad reales", "waveform.path.ecg", Color.corazon),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Mi reloj")
            VStack(alignment: .leading, spacing: 0) {
                Text("Si usás Oura o WHOOP, conectalo y tus datos de sueño y recuperación entran solos. Apple Watch no se conecta acá: va por Salud de Apple.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, Espacio.s)
                ForEach(Array(proveedores.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: Espacio.s) {
                        IconoAzulejo(p.2, color: p.3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.0).font(.body.weight(.semibold))
                            Text(p.1).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Espacio.xs)
                        Button("Conectar") {}
                            .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    }
                    .padding(.vertical, Espacio.xs)
                    if i < proveedores.count - 1 { Divider().padding(.leading, 42) }
                }
            }
            .tarjeta()
        }
    }
}
