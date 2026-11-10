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
    /// El alumno de esta cuenta revocó y el servidor todavía no lo confirmó (por cuenta: el iPhone puede tener varias).
    static func claveRevocarPendiente(_ cuenta: String) -> String { "mypump-reps-revocar-pendiente-\(cuenta)" }
    /// Lo último que dijo el servidor por cuenta: sin estado, si alguna vez se mandó no se puede afirmar ni una cosa ni la otra.
    static func claveSeManda(_ cuenta: String) -> String { "mypump-reps-se-manda-\(cuenta)" }
    private static let quietudSegundos: TimeInterval = 15 * 60
    /// «?» = dos cuentas con el mismo archivo: no sube ninguna.
    private static func marcar(_ archivo: String, cuenta: String) {
        let defaults = UserDefaults.standard
        var m = defaults.dictionary(forKey: claveMarcas) as? [String: String] ?? [:]
        m[archivo] = m[archivo].map { $0 == cuenta ? cuenta : "?" } ?? cuenta
        defaults.set(m, forKey: claveMarcas)
    }

    @MainActor static let subida = SubidaGrabaciones(cliente: Proveedor.modelo.cliente)

    /// Con el link dado de baja no se sube más, pero revocar sigue valiendo: el servidor lo acepta y lo prometimos. No depende
    /// de la fase: al arrancar de nuevo el link caído ya no está en el almacén y la app queda en `.sinToken`.
    @MainActor static func revocarLinkCaido() {
        let m = Proveedor.modelo
        guard !m.conMuestras, let viejo = SubidaGrabaciones.linkCaidoARevocar(
            caido: UserDefaults.standard.string(forKey: "mypump_token_invalido"), activo: m.token, activoListo: m.fase == .listo,
            pendiente: { UserDefaults.standard.bool(forKey: claveRevocarPendiente(ModeloEntreno.hashCuenta($0))) }
        ) else { return }
        let cuenta = ModeloEntreno.hashCuenta(viejo), cliente = m.cliente
        Task.detached(priority: .utility) {
            guard await cliente.guardarConsentimientoReps(token: viejo, acepta: false, plataforma: "ios", app: nil) else { return }
            UserDefaults.standard.set(false, forKey: claveRevocarPendiente(cuenta))
        }
    }

    /// Manda lo pendiente si el servidor lo habilita para esta cuenta. Sin esperar a nadie ni bloquear la pantalla: lo que
    /// no salga queda en el iPhone para la próxima.
    @MainActor static func subirSiCorresponde() {
        revocarLinkCaido()
        let m = Proveedor.modelo
        // La cuenta sale del token, no de `entreno`: al cambiar de link los dos están un rato desfasados.
        guard m.fase == .listo, !m.conMuestras, let token = m.token else { return }
        let cuenta = ModeloEntreno.hashCuenta(token)
        guard cuenta != "demo" else { return }
        let subida = subida, carpeta = carpeta, cliente = m.cliente
        Task.detached(priority: .utility) {
            // Una revocación que no llegó al servidor va primero, y mientras no salga no se sube nada.
            if UserDefaults.standard.bool(forKey: claveRevocarPendiente(cuenta)) {
                guard await cliente.guardarConsentimientoReps(token: token, acepta: false, plataforma: "ios", app: nil) else { return }
                UserDefaults.standard.set(false, forKey: claveRevocarPendiente(cuenta))
                await subida.olvidarSubidas()
            }
            await subida.subirPendientes(token: token, archivos: { estado in
                // Con la sesión en curso el archivo crece: se espera a que quede quieto para no mandarlo una vez por serie.
                let urls = AlmacenCalibracion(carpeta: carpeta, tope: AlmacenCalibracion.topeIPhone).archivos()
                    .filter { Date().timeIntervalSince($0.fecha) >= quietudSegundos }.map(\.url)
                let marcas = UserDefaults.standard.dictionary(forKey: claveMarcas) as? [String: String] ?? [:]
                return SubidaGrabaciones.deLaCuenta(urls, cuenta: cuenta, marcas: marcas, prendidas: ModoCalibracion().cuentas, estado: estado)
            }, alHabilitar: { estado in
                UserDefaults.standard.set(true, forKey: claveSeManda(cuenta))
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

    /// Texto del consentimiento, aprobado el 9/11/2026.
    private static let textoConsentimiento = """
        Si lo prendés, Pump Team recibe las series que grabaste y las que grabes con el Apple Watch: el movimiento del reloj, \
        el ejercicio, las reps, los kilos, la fecha y en qué muñeca llevás el reloj. No incluye tu nombre; queda asociado a tu \
        cuenta para poder borrarlo. Se usa solo para mejorar el conteo de reps. Lo podés apagar cuando quieras: se dejan de \
        mandar y se borra lo que ya recibimos. Si ya no tenés acceso a la app, escribinos y lo borramos.
        """

    /// Solo el servidor habilita: sin su estado (sin red o sin la parte del servidor) nunca se afirma que se manda.
    private var seManda: Bool { subidaEstado?.puedeSubir == true }

    /// Lo que pasa con el archivo, verdadero según la cuenta. Sin estado, si esta cuenta alguna vez mandó no se afirma nada.
    private var textoArchivo: String {
        if seManda { return "Un archivo por sesión de entreno. Se manda a Pump Team para mejorar el conteo. Si lo exportás, elegís vos a dónde más va." }
        if subidaEstado == nil, UserDefaults.standard.bool(forKey: DatosCalibracion.claveSeManda(cuenta)) {
            return "Un archivo por sesión de entreno. Al exportarlo elegís a dónde va."
        }
        return "Un archivo por sesión de entreno. Al exportarlo elegís a dónde va; la app no lo manda a ningún lado."
    }

    private func consentir(_ acepta: Bool) {
        guard let token = Proveedor.modelo.token, !guardandoConsentimiento else { return }
        guardandoConsentimiento = true
        let cuenta = ModeloEntreno.hashCuenta(token)   // revocación y marca, a la cuenta del token que se manda
        Task {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            // Una revocación que no llegó va primero: aceptar de nuevo no puede saltearse el borrado prometido.
            if acepta, UserDefaults.standard.bool(forKey: DatosCalibracion.claveRevocarPendiente(cuenta)) {
                guard await Proveedor.modelo.cliente.guardarConsentimientoReps(token: token, acepta: false, plataforma: "ios", app: version) else {
                    guardandoConsentimiento = false
                    errorConsentimiento = true
                    return
                }
                UserDefaults.standard.set(false, forKey: DatosCalibracion.claveRevocarPendiente(cuenta))
                await DatosCalibracion.subida.olvidarSubidas()
            }
            if !acepta {
                // Antes de mandar: si la app muere en el camino la revocación sigue en pie, y lo que estaba subiendo se frena ya.
                UserDefaults.standard.set(true, forKey: DatosCalibracion.claveRevocarPendiente(cuenta))
                await DatosCalibracion.subida.olvidarSubidas()
            }
            let ok = await Proveedor.modelo.cliente.guardarConsentimientoReps(token: token, acepta: acepta, plataforma: "ios", app: version)
            guardandoConsentimiento = false
            guard ok else {
                if acepta { errorConsentimiento = true; return }
                // Revocar no se pierde por falta de red: se apaga acá y se reintenta antes de cualquier subida.
                subidaEstado?.acepta = false
                UserDefaults.standard.set(false, forKey: DatosCalibracion.claveSeManda(cuenta))
                return
            }
            UserDefaults.standard.set(false, forKey: DatosCalibracion.claveRevocarPendiente(cuenta))
            subidaEstado?.acepta = acepta
            UserDefaults.standard.set(acepta, forKey: DatosCalibracion.claveSeManda(cuenta))
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
                    Text(Proveedor.modelo.palanca.contadorRepsReloj
                         ? "El conteo de reps del Apple Watch es experimental: propone las reps al terminar la serie y vos las confirmás o corregís con la corona. Nunca registra una serie solo."
                         : "El conteo de reps del Apple Watch es experimental y por ahora no propone las reps. Las cargás con la corona.")
                    Text(ModoCalibracion.textoPrivacidad)
                    if seManda { Text("Además se manda a Pump Team para mejorar el conteo.") }
                }
            }

            if let estado = subidaEstado {
                Section {
                    if estado.automatica {
                        Label("Se manda a Pump Team", systemImage: "icloud.and.arrow.up")
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
                         ? "En esta cuenta las series grabadas se mandan solas a Pump Team, sin tu nombre. Van el movimiento del reloj, el ejercicio, las reps y los kilos."
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
        .alert("¿Mandar tus series a Pump Team?", isPresented: $pedirConsentimiento) {
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
                if UserDefaults.standard.bool(forKey: DatosCalibracion.claveRevocarPendiente(cuenta)) { subidaEstado?.acepta = false }
                if let e = subidaEstado { UserDefaults.standard.set(e.puedeSubir, forKey: DatosCalibracion.claveSeManda(cuenta)) }
            }
        }
    }
}
