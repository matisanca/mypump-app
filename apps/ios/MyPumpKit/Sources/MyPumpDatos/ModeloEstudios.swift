import CryptoKit
import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Un archivo de un envío. Los bytes van en su propio archivo en caché (`estudios-archivos/<id>.pdf|jpg`) y acá solo el índice.
public struct ArchivoEstudio: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let formato: Estudios.Formato
    /// Ya está en el servidor. El archivo local se borra recién cuando el envío entero queda `enviado`.
    public var subido = false

    var nombre: String { "\(id).\(formato.extensionArchivo)" }
}

/// Un envío que el alumno ya mandó y todavía no terminó de salir. Sobrevive a cerrar la app.
public struct EnvioEstudioPendiente: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var pedidoId: String?
    public var archivos: [ArchivoEstudio]
    /// `envio_nuevo` ya contestó que sí.
    var abierto = false
    /// Archivos que el servidor no aceptó o que el teléfono perdió: al terminar se le avisa.
    var rechazados = 0
    /// Cuándo se mandó: un envío que no pudo salir en `diasDeVida` días se borra del teléfono.
    var creado: Date?

    public static let archivo = "estudios-cola.json"
    public static let carpeta = "estudios-archivos"
    public static let carpetaBorrador = "estudios-borrador"
    public static let carpetaVer = "estudios-ver"
}

/// Estudios y órdenes. Mismo criterio de cola que `ModeloGimnasio`: en disco, sobrevive a cerrar la app y a quedarse sin
/// señal, un 5xx o un 429 no gasta el archivo y todo otro 4xx es definitivo para ese archivo. Con la palanca apagada, o
/// sin haberla leído en esta sesión, no se llama a nada: `estado` queda en nil y no se ve ni se pide nada.
///
/// Son datos médicos: los archivos viven en Caches, fuera del respaldo de iCloud, y se borran al quedar enviados; lo que se
/// abre para ver va a un temporal que se borra al cerrar; el estado del servidor no se guarda en el teléfono; nada va a
/// Fotos ni a un registro.
@MainActor @Observable
public final class ModeloEstudios {
    public enum Resultado: Equatable, Sendable { case ok, fecha, sinSenal, error }
    public enum Aviso: Equatable, Sendable { case recibido, recibidoConRechazo, rechazado, topeDia, error }
    /// `todaviaNo`: el estudio llegó pero aún no se puede abrir (409 `todavia_no`); no es un error.
    public enum Abrir: Equatable, Sendable { case archivos([ArchivoParaVer]), todaviaNo, error }

    public struct ArchivoParaVer: Equatable, Sendable {
        public let url: URL
        public let pdf: Bool
    }

    /// Un archivo elegido en la hoja de subida, antes de «Enviar».
    public struct Elegido: Equatable, Sendable, Identifiable {
        public let id: String
        public let formato: Estudios.Formato
        public let url: URL
        /// Para no sumar dos veces los mismos bytes: el servidor guarda uno solo y el envío no cerraría nunca.
        let huella: String
    }

    /// nil: apagado, sin el servidor nuevo, o todavía no se supo nada. No se muestra nada.
    public private(set) var estado: EstadoEstudios?
    /// El último `get` falló por red o servicio y lo que se ve puede estar viejo.
    public private(set) var errorDeCarga = false
    public private(set) var cola: [EnvioEstudioPendiente] = []
    public private(set) var borrador: [Elegido] = []
    public private(set) var sinSenal = false
    /// Hay una pasada en curso: fuera de eso, lo que queda en la cola está esperando.
    public private(set) var subiendo = false
    /// La última pasada se cortó por algo que no es la red (el link, el servidor) y nada la va a retomar sola: hay que
    /// decirlo y ofrecer «Probar de nuevo».
    public private(set) var detenida = false
    /// La palanca `estudios_app` leída en esta sesión; nil hasta que se lee. No se recuerda de una vez para la otra.
    public private(set) var palanca: Bool?
    /// Cambia cada vez que se descarta lo elegido: una foto que se estaba convirtiendo para la hoja anterior no entra en la próxima.
    public private(set) var hoja = 0
    public private(set) var aviso: Aviso?

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    /// La carpeta de esta cuenta en Caches.
    @ObservationIgnored let cache: URL
    @ObservationIgnored private let esperar: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var drenando = false
    @ObservationIgnored private var reintentoProgramado = false
    @ObservationIgnored private var reintentosDeFondo = 0
    @ObservationIgnored private var vueltas: [String: Int] = [:]

    static let maxIntentosSeguidos = 3
    static let maxReintentosDeFondo = 5
    static let maxVueltas = 2
    static let diasDeVida = 14.0
    static let sesionEfimera = URLSession(configuration: .ephemeral)

    public init(cliente: ClienteRPC, token: String, disco: Disco?, cache raiz: URL? = nil,
                esperar: @escaping @Sendable (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.esperar = esperar
        cache = Self.carpetaCache(raiz: raiz, cuenta: "cuenta-\(Disco.huella(token))")
        // Lo que quedó de una hoja de subida sin enviar o de un archivo abierto para ver se borra al arrancar.
        Self.limpiarSueltos(cache)
        cola = Self.sanear(disco: disco, cache: cache, ahora: Date())
        // Y lo suelto de las otras cuentas de este teléfono (se cambió de link sin cerrar la app). Su cola espera a que
        // la vengan a buscar (`adoptar`) o al plazo, que mira `barrerTelefono` en cada arranque.
        let base = cache.deletingLastPathComponent()
        for otra in (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? [] where otra.hasPrefix("cuenta-") && otra != cache.lastPathComponent {
            Self.limpiarSueltos(base.appendingPathComponent(otra, isDirectory: true))
        }
    }

    static func carpetaCache(raiz: URL?, cuenta: String) -> URL {
        (raiz ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]).appendingPathComponent("MyPump/\(cuenta)", isDirectory: true)
    }

    /// Lo elegido y no enviado, y lo que se bajó para ver.
    static func limpiarSueltos(_ cache: URL) {
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(EnvioEstudioPendiente.carpetaBorrador))
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(EnvioEstudioPendiente.carpetaVer))
    }

    /// Deja la cola de una cuenta como tiene que estar y la devuelve: sin los envíos que no pudieron salir en dos semanas
    /// y sin archivos que ningún envío nombre (un cierre entre la copia y el índice).
    static func sanear(disco: Disco?, cache: URL, ahora: Date) -> [EnvioEstudioPendiente] {
        var cola = disco?.leer([EnvioEstudioPendiente].self, EnvioEstudioPendiente.archivo) ?? []
        let limite = ahora.addingTimeInterval(-diasDeVida * 86_400)
        if cola.contains(where: { ($0.creado ?? .distantFuture) < limite }) {
            cola.removeAll { ($0.creado ?? .distantFuture) < limite }
            if cola.isEmpty { disco?.borrar(EnvioEstudioPendiente.archivo) } else { _ = disco?.guardar(cola, EnvioEstudioPendiente.archivo) }
        }
        let fm = FileManager.default
        let carpeta = cache.appendingPathComponent(EnvioEstudioPendiente.carpeta)
        let vivos = Set(cola.flatMap { $0.archivos.map(\.nombre) })
        for f in (try? fm.contentsOfDirectory(atPath: carpeta.path)) ?? [] where !vivos.contains(f) {
            try? fm.removeItem(at: carpeta.appendingPathComponent(f))
        }
        return cola
    }

    /// Al arrancar la app, con o sin la sección prendida y con o sin sesión: lo de «Estudios» de TODAS las cuentas de
    /// este teléfono (otro link, sesión cerrada, cuenta dada de baja). Lo suelto se borra ya; la cola que nadie vino a
    /// buscar (`adoptar`), pasado el plazo. `raizDisco` y `raizCache` son las de las pruebas (nil: las del sistema).
    public static func barrerTelefono(raizDisco: URL? = nil, raizCache: URL? = nil, ahora: Date = Date()) {
        let fm = FileManager.default
        let soporte = (raizDisco ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]).appendingPathComponent("MyPump", isDirectory: true)
        let caches = carpetaCache(raiz: raizCache, cuenta: "x").deletingLastPathComponent()
        func cuentas(_ base: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).filter { $0.hasPrefix("cuenta-") } }
        for nombre in Set(cuentas(soporte) + cuentas(caches)) {
            let cache = caches.appendingPathComponent(nombre, isDirectory: true)
            limpiarSueltos(cache)
            // Sin la carpeta de la cuenta no hay índice: sus archivos no los va a subir nadie.
            let carpeta = soporte.appendingPathComponent(nombre, isDirectory: true)
            _ = sanear(disco: fm.fileExists(atPath: carpeta.path) ? Disco(carpeta: carpeta) : nil, cache: cache, ahora: ahora)
        }
    }

    /// Cerrar sesión: de esta cuenta no queda nada médico en el teléfono, ni lo que esperaba salir, ni lo elegido, ni lo
    /// que se bajó para ver. Una pasada en curso se corta en el próximo paso.
    public func borrarTodo() {
        apagar()
        palanca = false
        descartarBorrador()
        cerrarVisor()
        cola = []
        vueltas = [:]
        aviso = nil
        disco?.borrar(EnvioEstudioPendiente.archivo)
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(EnvioEstudioPendiente.carpeta))
    }

    // MARK: Lo que lee la pantalla

    public var habilitado: Bool { estado != nil }
    public var pendientes: Int { estado?.pendientes.count ?? 0 }
    public var topeArchivos: Int { estado?.topeArchivos ?? Estudios.topeArchivos }
    public var topeMB: Int { estado?.topeMB ?? Estudios.topeMB }
    public var puedeAgregar: Bool { borrador.count < topeArchivos }
    /// «Subiendo 2 de 5», del envío que está saliendo.
    public var progreso: String? {
        guard let e = cola.first else { return nil }
        return Estudios.progreso(subidos: e.archivos.filter(\.subido).count, total: e.archivos.count)
    }

    public func limpiarAviso() { aviso = nil }

    // MARK: Servidor

    /// `get`. Token caído, función inexistente o `habilitado: false`: la sección no existe. Sin red se queda con lo que ya
    /// se veía en esta sesión (nada se guarda en el teléfono) y avisa que no se pudo cargar.
    public func refrescar() async {
        switch await cliente.llamar("mypump_estudios_get", ["p_token": .texto(token)]) {
        case .success(.null):
            apagar()
        case .success(let j):
            guard let e = EstadoEstudios(j) else { apagar(); return }
            estado = e
            errorDeCarga = false
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
        case .failure:
            errorDeCarga = estado != nil
        }
    }

    public func apagar() { estado = nil; errorDeCarga = false; detenida = false }

    /// Lo que dijo `get_app_config` recién. Apagada, la sección deja de existir en el momento.
    public func usarPalanca(_ prendida: Bool) {
        palanca = prendida
        if !prendida { apagar() }
    }

    /// Lo que hace la pantalla al abrirse y al deslizar, y la app en cada carga: con la palanca prendida, `get` y que
    /// salga lo pendiente (sin esperarlo: varios archivos de 20 MB no frenan a nadie). Si no, nada.
    public func sincronizar() async {
        guard palanca == true else { apagar(); return }
        await refrescar()
        if habilitado { drenarEnFondo() }
    }

    /// «Probar de nuevo» con la cola detenida.
    public func reintentar() async {
        reintentosDeFondo = 0
        detenida = false
        await sincronizar()
    }

    /// «Ya me lo hice» con su fecha (`AAAA-MM-DD`), o nil para deshacerlo.
    public func marcarHecho(pedidoId: String, fecha: Estudios.Dia?) async -> Resultado {
        let r = await cliente.llamar("mypump_estudios_hecho", ["p_token": .texto(token), "p_pedido_id": .texto(pedidoId),
                                                              "p_fecha": fecha.map { .texto($0.iso) } ?? .null])
        switch r {
        case .success(.null): return .error
        case .success(let j):
            if j["ok"] == .bool(true) { await refrescar(); return .ok }
            switch j["error"]?.comoTexto {
            case "fecha": return .fecha
            case "no_encontrado": await refrescar(); return .ok   // ya llegó o lo cerraron: lo que valga es lo del servidor
            case "no_habilitado": apagar(); return .error
            default: return .error
            }
        case .failure(let e): return e.clase == .permanente ? .error : .sinSenal
        }
    }

    // MARK: Hoja de subida

    /// Suma un archivo a lo que se está por enviar. Las fotos ya llegan en JPEG (2400 px, 0,8, sin EXIF); el PDF, tal cual.
    @discardableResult
    public func elegir(_ datos: Data) -> Estudios.Agregado {
        let formato = Estudios.formato(datos)
        let r = Estudios.puedeAgregar(bytes: datos.count, formato: formato, yaHay: borrador.count, topeArchivos: topeArchivos, topeMB: topeMB)
        guard r == .ok, let formato else { return r }
        let huella = SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
        if borrador.contains(where: { $0.huella == huella }) { return .ok }   // el mismo archivo dos veces: ya está
        let id = UUID().uuidString.lowercased()
        let carpeta = cache.appendingPathComponent(EnvioEstudioPendiente.carpetaBorrador, isDirectory: true)
        guard Self.prepararCarpeta(carpeta) else { return .noSeGuardo }
        let url = carpeta.appendingPathComponent("\(id).\(formato.extensionArchivo)")
        do { try datos.write(to: url, options: Self.escritura) } catch { return .noSeGuardo }
        borrador.append(Elegido(id: id, formato: formato, url: url, huella: huella))
        return .ok
    }

    public func quitar(_ id: String) {
        guard let i = borrador.firstIndex(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: borrador[i].url)
        borrador.remove(at: i)
    }

    /// Se cerró la hoja sin enviar: no queda nada.
    public func descartarBorrador() {
        hoja += 1
        borrador = []
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(EnvioEstudioPendiente.carpetaBorrador))
    }

    /// «Enviar»: los archivos pasan a la carpeta de la cola y se anota el envío en disco; sale con `drenar()`. false = no se
    /// pudo guardar en el teléfono (lo elegido queda en la hoja).
    @discardableResult
    public func enviar(pedidoId: String? = nil) -> Bool {
        guard !borrador.isEmpty, disco != nil else { return false }
        let carpeta = cache.appendingPathComponent(EnvioEstudioPendiente.carpeta, isDirectory: true)
        guard Self.prepararCarpeta(carpeta) else { return false }
        var envio = EnvioEstudioPendiente(id: UUID().uuidString.lowercased(), pedidoId: pedidoId, archivos: [], creado: Date())
        let fm = FileManager.default
        for e in borrador {
            let a = ArchivoEstudio(id: e.id, formato: e.formato)
            do { try fm.moveItem(at: e.url, to: carpeta.appendingPathComponent(a.nombre)) } catch {
                // Lo que ya se movió vuelve a la hoja: o sale todo o no sale nada.
                for hecho in envio.archivos { try? fm.moveItem(at: carpeta.appendingPathComponent(hecho.nombre), to: borrador.first { $0.id == hecho.id }!.url) }
                return false
            }
            envio.archivos.append(a)
        }
        cola.append(envio)
        guard guardarCola() else {
            cola.removeLast()
            for a in envio.archivos { try? fm.moveItem(at: carpeta.appendingPathComponent(a.nombre), to: borrador.first { $0.id == a.id }!.url) }
            return false
        }
        borrador = []
        hoja += 1
        aviso = nil
        detenida = false
        return true
    }

    // MARK: Cola

    public func drenarEnFondo() { Task { await drenar() } }

    /// Una pasada a la vez, un envío por vez: `envio_nuevo` → cada archivo → `enviar`. Red: corta y espera a que vuelva.
    /// 5xx o 429: espera y reintenta, y a la tercera seguida corta la pasada y prueba sola más tarde. Con la sección
    /// apagada (la palanca, el link, la cuenta) no sale nada: tampoco el reintento que estaba programado.
    public func drenar() async {
        guard estado != nil, !drenando, !cola.isEmpty else { return }
        drenando = true
        subiendo = true
        sinSenal = false
        detenida = false
        defer {
            drenando = false; subiendo = false
            // Quedó algo, no es la red y nadie lo va a retomar solo: se dice, con «Probar de nuevo».
            detenida = estado != nil && !cola.isEmpty && !sinSenal && !reintentoProgramado
        }
        var termino = false
        pasada: while estado != nil, let envio = cola.first {
            switch await sacar(envio) {
            case .listo: termino = true
            case .seguir: continue
            case .cortar: break pasada
            }
        }
        if termino { await refrescar() }
    }

    private enum Paso { case listo, seguir, cortar }

    private func sacar(_ envio: EnvioEstudioPendiente) async -> Paso {
        if !envio.abierto { return await abrir(envio) }
        var seguidas = 0
        // `estado`: se apagó la sección o se cerró la sesión en medio de la pasada; no sale ni un archivo más.
        while estado != nil, let a = cola.first?.archivos.first(where: { !$0.subido }), cola.first?.id == envio.id {
            switch await subir(a, envio: envio.id) {
            case .ok:
                marcar(envio.id) { e in if let i = e.archivos.firstIndex(where: { $0.id == a.id }) { e.archivos[i].subido = true } }
                seguidas = 0
            case .descartar:
                borrarArchivo(a)
                marcar(envio.id) { e in e.archivos.removeAll { $0.id == a.id }; e.rechazados += 1 }
            case .token:
                // 403: el link o la habilitación, no el archivo. No se pierde nada: lo que valga lo dice el próximo `get`.
                return .cortar
            case .reabrir:
                // 404: el servidor no conoce el envío. Se abre de nuevo y se sube todo otra vez.
                guard darVuelta(envio.id) else { programarReintento(); vueltas[envio.id] = 0; return .cortar }
                marcar(envio.id) { e in e.abierto = false; for i in e.archivos.indices { e.archivos[i].subido = false } }
                return .seguir
            case .cerrado:
                // 409: el envío ya no recibe porque ya quedó enviado. `enviar` lo confirma (`ya`).
                return await cerrar(cola.first ?? envio, yaCerrado: true)
            case .reintentar:
                seguidas += 1
                if seguidas >= Self.maxIntentosSeguidos { programarReintento(); return .cortar }
                await esperar(pow(2, Double(seguidas)))
            case .red:
                sinSenal = true
                return .cortar
            }
        }
        guard estado != nil else { return .cortar }
        guard let actual = cola.first, actual.id == envio.id else { return .seguir }
        if actual.archivos.isEmpty {
            // No quedó ninguno: el envío se descarta en silencio y se le dice que pruebe de otra forma.
            terminar(actual, aviso: .rechazado)
            return .seguir
        }
        return await cerrar(actual)
    }

    private func abrir(_ envio: EnvioEstudioPendiente) async -> Paso {
        let r = await cliente.llamar("mypump_estudios_envio_nuevo", [
            "p_token": .texto(token), "p_id": .texto(envio.id), "p_pedido_id": envio.pedidoId.map(JSONValue.texto) ?? .null,
        ])
        switch r {
        case .success(.null):
            return .cortar   // token caído: queda guardado para el link nuevo
        case .success(let j):
            if j["ok"] == .bool(true) {
                if j["estado"]?.comoTexto == "enviado" { terminar(envio, aviso: envio.rechazados > 0 ? .recibidoConRechazo : .recibido); return .listo }
                marcar(envio.id) { $0.abierto = true }
                return .seguir
            }
            switch j["error"]?.comoTexto {
            case "tope_dia": terminar(envio, aviso: .topeDia)
            case "no_habilitado": apagar(); return .cortar   // se conserva: si lo vuelven a habilitar, sale
            case "id_repetido" where darVuelta(envio.id):
                // El id ya es de otro envío: se prueba con uno nuevo (los archivos son los mismos).
                let nuevo = UUID().uuidString.lowercased()
                vueltas[nuevo] = vueltas[envio.id]
                marcar(envio.id) { $0.id = nuevo }
            default: terminar(envio, aviso: .error)
            }
            return .seguir
        case .failure(let e):
            return falla(e, envio)
        }
    }

    private func cerrar(_ envio: EnvioEstudioPendiente, yaCerrado: Bool = false) async -> Paso {
        let r = await cliente.llamar("mypump_estudios_enviar", [
            "p_token": .texto(token), "p_id": .texto(envio.id), "p_archivos": .numero(Double(envio.archivos.count)),
        ])
        switch r {
        case .success(.null):
            return .cortar
        case .success(let j):
            if j["ok"] == .bool(true) {
                terminar(envio, aviso: envio.rechazados > 0 ? .recibidoConRechazo : .recibido)
                return .listo
            }
            switch j["error"]?.comoTexto {
            case _ where yaCerrado: terminar(envio, aviso: .error)
            case "faltan_archivos", "sin_archivos":
                // En el servidor hay menos de los que subieron: se suben de nuevo (los que ya están contestan `ya`).
                guard darVuelta(envio.id) else { programarReintento(); vueltas[envio.id] = 0; return .cortar }
                marcar(envio.id) { e in for i in e.archivos.indices { e.archivos[i].subido = false } }
            case "no_encontrado":
                guard darVuelta(envio.id) else { terminar(envio, aviso: .error); return .seguir }
                marcar(envio.id) { e in e.abierto = false; for i in e.archivos.indices { e.archivos[i].subido = false } }
            case "no_habilitado": apagar(); return .cortar
            default: terminar(envio, aviso: .error)
            }
            return .seguir
        case .failure(let e):
            return falla(e, envio)
        }
    }

    private func falla(_ e: ErrorRPC, _ envio: EnvioEstudioPendiente) -> Paso {
        // Sin la función o sin permiso (se revirtió el servidor, cambió la clave): la sección se apaga y la cola se conserva.
        if e.funcionInexistente || [401, 403, 404].contains(e.status) { apagar(); return .cortar }
        switch e.clase {
        case .permanente: terminar(envio, aviso: .error); return .seguir   // error de programación (22023): no se reintenta
        case .red: sinSenal = true; return .cortar
        case .transitorio: programarReintento(); return .cortar
        }
    }

    /// Cuenta las vueltas de un envío (subir todo de nuevo, cambiarle el id): false cuando ya dio las que puede.
    private func darVuelta(_ id: String) -> Bool {
        let n = vueltas[id, default: 0]
        guard n < Self.maxVueltas else { return false }
        vueltas[id] = n + 1
        return true
    }

    private enum Subida { case ok, descartar, reintentar, token, reabrir, cerrado, red }

    private func subir(_ a: ArchivoEstudio, envio: String) async -> Subida {
        let archivo = cache.appendingPathComponent(EnvioEstudioPendiente.carpeta).appendingPathComponent(a.nombre)
        // El sistema puede vaciar Caches con el disco lleno: ese archivo ya no existe. Si está y no se puede leer (el
        // teléfono bloqueado), no se pierde: se prueba más tarde.
        guard FileManager.default.fileExists(atPath: archivo.path) else { return .descartar }
        guard let datos = try? Data(contentsOf: archivo, options: .mappedIfSafe) else { return .reintentar }
        guard !datos.isEmpty else { return .descartar }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("estudios/upload"), timeoutInterval: 180)
        pedido.httpMethod = "POST"
        pedido.setValue(a.formato.mime, forHTTPHeaderField: "Content-Type")
        pedido.setValue(String(datos.count), forHTTPHeaderField: "Content-Length")
        pedido.setValue(token, forHTTPHeaderField: "x-estudios-token")
        pedido.setValue(envio, forHTTPHeaderField: "x-estudios-envio")
        pedido.setValue(a.id, forHTTPHeaderField: "x-estudios-archivo")
        pedido.httpBody = datos
        guard let (cuerpo, resp) = try? await cliente.transporte.enviar(pedido) else { return .red }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // Lo que no habla del archivo sino del link o del envío no gasta el archivo.
        switch status {
        case 401, 403: return .token      // 401: link regenerado; 403: la cuenta ya no tiene la función
        case 404: return .reabrir
        case 409: return .cerrado
        default: break
        }
        let j = try? JSONDecoder().decode(JSONValue.self, from: cuerpo)
        switch Estudios.clasificarSubida(status: status, ok: j?["ok"] == .bool(true)) {
        case .ok: return .ok
        case .descartar: return .descartar
        case .reintentar: return .reintentar
        }
    }

    /// Después de una tanda de errores del servidor, una pasada más sola, con la app abierta.
    private func programarReintento() {
        guard !reintentoProgramado, reintentosDeFondo < Self.maxReintentosDeFondo else { return }
        reintentoProgramado = true
        reintentosDeFondo += 1
        Task { [weak self, esperar] in
            await esperar(60)
            self?.reintentoProgramado = false
            await self?.drenar()
        }
    }

    private func marcar(_ id: String, _ cambio: (inout EnvioEstudioPendiente) -> Void) {
        guard let i = cola.firstIndex(where: { $0.id == id }) else { return }
        cambio(&cola[i])
        _ = guardarCola()
    }

    /// El envío sale de la cola (enviado o descartado) y sus archivos se borran del teléfono.
    private func terminar(_ envio: EnvioEstudioPendiente, aviso nuevo: Aviso?) {
        for a in envio.archivos { borrarArchivo(a) }
        cola.removeAll { $0.id == envio.id }
        vueltas[envio.id] = nil
        _ = guardarCola()
        if let nuevo { aviso = nuevo }
        // Las pasadas solas se cuentan por envío: recién al terminar uno se vuelve a empezar (si no, un servidor que
        // siempre dice «faltan archivos» haría subir todo de nuevo cada minuto).
        reintentosDeFondo = 0
    }

    private func borrarArchivo(_ a: ArchivoEstudio) {
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(EnvioEstudioPendiente.carpeta).appendingPathComponent(a.nombre))
    }

    // MARK: Abrir una orden o un estudio propio

    /// Pide las URL (duran 10 minutos: nunca se guardan), baja los archivos a un temporal y devuelve dónde quedaron. Quien
    /// los muestra llama a `cerrarVisor()` al cerrar.
    public func bajarParaVer(clase: String, id: String) async -> Abrir {
        cerrarVisor()   // lo que hubiera quedado de antes no sobrevive a un intento nuevo, salga bien o mal
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("estudios/urls"), timeoutInterval: 30)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto(["token": .texto(token), "clase": .texto(clase), "id": .texto(id)]))
        guard let (datos, resp) = try? await cliente.transporte.enviar(pedido) else { return .error }
        let status = (resp as? HTTPURLResponse)?.statusCode
        let j = try? JSONDecoder().decode(JSONValue.self, from: datos)
        if status == 409, j?["error"]?.comoTexto == "todavia_no" { return .todaviaNo }
        guard status == 200, let j, j["ok"] == .bool(true), case .lista(let filas)? = j["archivos"], !filas.isEmpty else { return .error }
        cerrarVisor()
        // Con la red de verdad, una sesión efímera: el archivo no queda en el caché de URLSession.
        let descarga: any Transporte = cliente.transporte is URLSession ? Self.sesionEfimera : cliente.transporte
        let carpeta = cache.appendingPathComponent(EnvioEstudioPendiente.carpetaVer, isDirectory: true)
        guard Self.prepararCarpeta(carpeta) else { return .error }
        var salida: [ArchivoParaVer] = []
        for (i, f) in filas.enumerated() {
            guard let u = f["url"]?.comoTexto.flatMap(URL.init(string:)), u.scheme == "https",
                  let (bytes, r) = try? await descarga.enviar(URLRequest(url: u, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)),
                  (r as? HTTPURLResponse)?.statusCode == 200, let formato = Estudios.formato(bytes) else { cerrarVisor(); return .error }
            let destino = carpeta.appendingPathComponent("\(i + 1).\(formato.extensionArchivo)")
            do { try bytes.write(to: destino, options: Self.escritura) } catch { cerrarVisor(); return .error }
            salida.append(ArchivoParaVer(url: destino, pdf: formato == .pdf))
        }
        return .archivos(salida)
    }

    /// Borra lo que se bajó para ver.
    public func cerrarVisor() {
        try? FileManager.default.removeItem(at: cache.appendingPathComponent(EnvioEstudioPendiente.carpetaVer))
    }

    // MARK: Disco

    /// Atómica y cifrada con el teléfono bloqueado (la cola solo sale con la app abierta; si no se puede leer, espera).
    static let escritura: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]

    /// Crea la carpeta y la deja fuera del respaldo de iCloud.
    static func prepararCarpeta(_ carpeta: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            var c = carpeta
            var valores = URLResourceValues()
            valores.isExcludedFromBackup = true
            try? c.setResourceValues(valores)
            return true
        } catch { return false }
    }

    private func guardarCola() -> Bool {
        guard let disco else { return false }
        if cola.isEmpty { disco.borrar(EnvioEstudioPendiente.archivo); return true }
        return disco.guardar(cola, EnvioEstudioPendiente.archivo)
    }

    /// Los envíos que quedaron en la carpeta de otro link de la misma persona (`CuentasDelTelefono.adoptarEstudios`).
    func adoptar(_ otros: [EnvioEstudioPendiente], desde otra: URL) -> Bool {
        guard disco != nil else { return false }
        let carpeta = cache.appendingPathComponent(EnvioEstudioPendiente.carpeta, isDirectory: true)
        guard Self.prepararCarpeta(carpeta) else { return false }
        let origen = otra.appendingPathComponent(EnvioEstudioPendiente.carpeta)
        for var e in otros where !cola.contains(where: { $0.id == e.id }) {
            for a in e.archivos { try? FileManager.default.moveItem(at: origen.appendingPathComponent(a.nombre), to: carpeta.appendingPathComponent(a.nombre)) }
            // Con el link nuevo el envío se abre de nuevo (mismo id, misma persona: el servidor contesta `ya`).
            e.abierto = false
            cola.append(e)
        }
        return guardarCola()
    }
}
