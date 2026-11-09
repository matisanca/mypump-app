import SwiftUI
import MyPumpDatos
import MyPumpReloj

/// Los datos del modo calibración en el iPhone (tanda 4): las series que manda el reloj por `transferFile`, juntas en un
/// archivo `.mpcal` por sesión, en una carpeta con tope. Salen del teléfono si el alumno las exporta (hoja de compartir)
/// o, solo con la habilitación que da el servidor para su cuenta (automática o con su consentimiento), a MyPump.
enum DatosCalibracion {
    static var carpeta: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calibracion")
    }
    static var almacen: AlmacenCalibracion { AlmacenCalibracion(carpeta: carpeta, tope: AlmacenCalibracion.topeIPhone) }
    /// Los archivos del reloj ya recibidos (un reenvío no duplica una serie).
    static let claveRecibidos = "mypump-calibracion-recibidos"
    /// De qué cuenta es cada archivo: el iPhone puede tener varias, y a cada una le toca subir solo lo suyo.
    static let claveMarcas = "mypump-calibracion-marcas"
    /// La cuenta automática ya prendió la grabación una vez (si después la apaga a mano, no se vuelve a prender).
    static let claveAutomatica = "mypump-calibracion-automatica"
    /// «?» = dos cuentas con el mismo archivo: no sube ninguna.
    private static func marcar(_ archivo: String, cuenta: String) {
        let defaults = UserDefaults.standard
        var m = defaults.dictionary(forKey: claveMarcas) as? [String: String] ?? [:]
        m[archivo] = m[archivo].map { $0 == cuenta ? cuenta : "?" } ?? cuenta
        defaults.set(m, forKey: claveMarcas)
    }

    @MainActor static let subida = SubidaGrabaciones(cliente: Proveedor.modelo.cliente)

    /// Manda lo pendiente si el servidor lo habilita para esta cuenta. Sin esperar a nadie ni bloquear la pantalla: lo que
    /// no salga queda en el iPhone para la próxima.
    @MainActor static func subirSiCorresponde() {
        let m = Proveedor.modelo
        guard !m.conMuestras, let token = m.token, let cuenta = m.entreno?.cuentaReloj, cuenta != "demo" else { return }
        let subida = subida, carpeta = carpeta
        Task.detached(priority: .utility) {
            await subida.subirPendientes(token: token, archivos: { estado in
                let urls = AlmacenCalibracion(carpeta: carpeta, tope: AlmacenCalibracion.topeIPhone).archivos().map(\.url)
                let marcas = UserDefaults.standard.dictionary(forKey: claveMarcas) as? [String: String] ?? [:]
                return SubidaGrabaciones.deLaCuenta(urls, cuenta: cuenta, marcas: marcas, prendidas: ModoCalibracion().cuentas, estado: estado)
            }, alHabilitar: { estado in
                guard estado.automatica else { return }
                await MainActor.run { prenderAutomatica(cuenta: cuenta) }
            })
        }
    }

    @MainActor private static func prenderAutomatica(cuenta: String) {
        let defaults = UserDefaults.standard
        var ya = defaults.stringArray(forKey: claveAutomatica) ?? []
        guard !ya.contains(cuenta) else { return }
        ya.append(cuenta)
        defaults.set(ya, forKey: claveAutomatica)
        ModoCalibracion().poner(true, cuenta: cuenta)
        PuenteReloj.compartido.mandarRutina(forzar: true)
    }

    /// Un archivo que llegó del reloj. Corre en el hilo de WatchConnectivity y tiene que terminar antes de volver (el
    /// sistema borra el archivo después). Con el modo apagado para esa cuenta se descarta.
    static func recibir(_ url: URL, metadatos: [String: Any]?) {
        let cuenta = metadatos?["cuenta"] as? String ?? ""
        guard ModoCalibracion().prendido(cuenta: cuenta), let d = try? Data(contentsOf: url),
              let registros = try? ArchivoCalibracion.leer(d), !registros.isEmpty else { return }
        let nombre = metadatos?["nombre"] as? String ?? url.lastPathComponent
        let defaults = UserDefaults.standard
        var recibidos = defaults.stringArray(forKey: claveRecibidos) ?? []
        guard !recibidos.contains(nombre) else { return }
        var escrito = true
        for (sesion, rs) in Dictionary(grouping: registros, by: \.encabezado.sesion) {
            let datos = rs.compactMap { try? ArchivoCalibracion.datos($0) }.reduce(Data(), +)
            let archivo = "calibracion-\(seguro(sesion)).\(ArchivoCalibracion.extension_)"
            do { try almacen.anexar(datos, nombre: archivo); marcar(archivo, cuenta: cuenta) } catch { escrito = false }
        }
        // Solo si quedó escrito: si no, un reenvío del reloj lo vuelve a intentar.
        guard escrito else { return }
        recibidos.append(nombre)
        defaults.set(Array(recibidos.suffix(2_000)), forKey: claveRecibidos)
        Task { @MainActor in subirSiCorresponde() }
    }

    static func seguro(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.prefix(40)))
    }

    struct Sesion: Identifiable {
        var url: URL
        var series: Int
        var bytes: Int
        var id: URL { url }
        /// «calibracion-2026-11-03-s2-d3» → «2026-11-03 · semana 2»
        var titulo: String {
            let partes = url.deletingPathExtension().lastPathComponent.split(separator: "-").dropFirst()
            guard partes.count >= 4 else { return url.lastPathComponent }
            return "\(partes.prefix(3).joined(separator: "-")) · semana \(partes[partes.startIndex + 3].dropFirst())"
        }
    }

    static func sesiones() -> [Sesion] {
        almacen.archivos().reversed().map { a in
            let n = (try? Data(contentsOf: a.url)).map { ArchivoCalibracion.encabezados($0).count } ?? 0
            return Sesion(url: a.url, series: n, bytes: a.bytes)
        }
    }
}

/// Mis datos → Conteo de reps (con el reloj emparejado). El contador va para todos; acá se prende la grabación de las
/// series (apagada por defecto), se explica qué se graba y se exportan los datos (un archivo por sesión).
struct CalibracionView: View {
    let cuenta: String
    private let modo = ModoCalibracion()
    @State private var prendido = false
    @State private var sesiones: [DatosCalibracion.Sesion] = []
    @State private var confirmarBorrado = false
    /// nil = sin la parte del servidor (o sin red): no se muestra nada de la subida.
    @State private var subidaEstado: EstadoSubidaReps?
    @State private var pedirConsentimiento = false
    @State private var guardandoConsentimiento = false
    @State private var errorConsentimiento = false

    /// BORRADOR para el OK de Mati: el texto del consentimiento.
    private static let textoConsentimiento = """
        Si lo prendés, MyPump recibe las series que grabaste y las que grabes con el Apple Watch: el movimiento del reloj, \
        el ejercicio, las reps y los kilos. No incluye tu nombre. Se usa solo para mejorar el conteo de reps. Lo podés apagar \
        cuando quieras: se dejan de mandar y se borra lo que ya recibimos.
        """

    private var seManda: Bool { subidaEstado?.puedeSubir == true }

    /// Lo que pasa con el archivo, verdadero según la cuenta.
    private var textoArchivo: String {
        seManda
            ? "Un archivo por sesión de entreno. Se manda a MyPump para mejorar el conteo; si lo exportás, elegís vos a dónde más va."
            : "Un archivo por sesión de entreno. Al exportarlo elegís a dónde va; la app no lo manda a ningún lado."
    }

    private func consentir(_ acepta: Bool) {
        guard let token = Proveedor.modelo.token, !guardandoConsentimiento else { return }
        guardandoConsentimiento = true
        Task {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            let ok = await Proveedor.modelo.cliente.guardarConsentimientoReps(token: token, acepta: acepta, plataforma: "ios", app: version)
            guardandoConsentimiento = false
            guard ok else { errorConsentimiento = true; return }
            subidaEstado?.acepta = acepta
            if acepta {
                prendido = true
                modo.poner(true, cuenta: cuenta)
                PuenteReloj.compartido.mandarRutina(forzar: true)
                DatosCalibracion.subirSiCorresponde()
            } else {
                await DatosCalibracion.subida.olvidarSubidas()
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { prendido }, set: { nuevo in
                    prendido = nuevo
                    modo.poner(nuevo, cuenta: cuenta)
                    PuenteReloj.compartido.mandarRutina(forzar: true)
                })) {
                    Label { Text("Grabar mis series") } icon: { IconoAzulejo("waveform.path.ecg", color: .agua) }
                }
                .tint(Color.marcaVivo)
                .accessibilityIdentifier("modo-calibracion")
            } header: {
                Text("Experimental")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("El conteo de reps del Apple Watch es experimental: propone las reps al terminar la serie y vos las confirmás o corregís con la corona. Nunca registra una serie solo.")
                    Text(ModoCalibracion.textoPrivacidad)
                }
            }

            if let estado = subidaEstado {
                Section {
                    if estado.automatica {
                        Label("Se manda a MyPump", systemImage: "icloud.and.arrow.up")
                    } else {
                        Toggle(isOn: Binding(get: { estado.acepta == true }, set: { nuevo in
                            if nuevo { pedirConsentimiento = true } else { consentir(false) }
                        })) {
                            Label("Ayudar a mejorar el conteo", systemImage: "icloud.and.arrow.up")
                        }
                        .tint(Color.marcaVivo)
                        .disabled(guardandoConsentimiento)
                        .accessibilityIdentifier("reps-consentimiento")
                    }
                } footer: {
                    Text(estado.automatica
                         ? "En esta cuenta las series grabadas se mandan solas a MyPump, sin tu nombre: el movimiento del reloj, el ejercicio, las reps y los kilos."
                         : Self.textoConsentimiento)
                }
            }

            Section {
                if sesiones.isEmpty {
                    Text("Todavía no hay series grabadas.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sesiones) { s in
                        LabeledContent(s.titulo, value: "\(s.series) \(s.series == 1 ? "serie" : "series") · \(ByteCountFormatter.string(fromByteCount: Int64(s.bytes), countStyle: .file))")
                    }
                    ShareLink(items: sesiones.map(\.url)) {
                        Label("Exportar series grabadas", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportar-calibracion")
                    Button("Borrar series grabadas", role: .destructive) { confirmarBorrado = true }
                }
            } header: {
                Text("Grabado en este iPhone")
            } footer: {
                Text(textoArchivo)
            }
        }
        .navigationTitle("Conteo de reps")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Borrar todas las series grabadas en este iPhone?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                DatosCalibracion.almacen.borrarTodo()
                sesiones = []
            }
        }
        .alert("¿Mandar tus series a MyPump?", isPresented: $pedirConsentimiento) {
            Button("Aceptar") { consentir(true) }
            Button("Ahora no", role: .cancel) {}
        } message: {
            Text(Self.textoConsentimiento)
        }
        .alert("No se pudo guardar. Probá de nuevo con conexión.", isPresented: $errorConsentimiento) { Button("OK", role: .cancel) {} }
        .task {
            prendido = modo.prendido(cuenta: cuenta)
            sesiones = DatosCalibracion.sesiones()
            if let token = Proveedor.modelo.token, !Proveedor.modelo.conMuestras {
                subidaEstado = await Proveedor.modelo.cliente.estadoSubidaReps(token: token)
            }
        }
    }
}
