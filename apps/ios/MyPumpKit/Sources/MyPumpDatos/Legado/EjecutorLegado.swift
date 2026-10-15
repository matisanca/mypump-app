import Foundation
import MyPumpModelos
import MyPumpReglas

/// Dónde vive todo (inyectable en los tests). En la app: `Library` y `Application Support` del contenedor.
public struct EntornoLegado: Sendable {
    /// `Library`: ahí están los archivos de WebKit.
    public var library: URL
    /// `Application Support`: la raíz de `legado/` y de las carpetas de cuenta (`Disco`).
    public var soporte: URL

    public init(library: URL? = nil, soporte: URL? = nil) {
        let fm = FileManager.default
        self.library = library ?? fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        self.soporte = soporte ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// `Application Support/legado/`: copias crudas, estado, libro mayor, colas pendientes de la Fase R y recibos.
    public var carpeta: URL { soporte.appendingPathComponent("legado", isDirectory: true) }

    public func disco(_ token: String) -> Disco { Disco(raiz: soporte, token: token) }
}

/// El estado de la migración en este teléfono (`legado/estado.json`). Sin tokens ni valores, salvo las claves que la
/// escritura de vuelta tiene que borrar.
public struct EstadoMigracion: Codable, Equatable, Sendable {
    /// UUID de la migración de este teléfono (no el IDFV): va en el recibo y en la marca.
    public var migracion: String
    public var corridas: Int
    public var primera: Double
    public var ultima: Double
    /// La de la última lectura. Si cambia, alguien volvió a la Capacitor: la Fase L corre de nuevo.
    public var huella: HuellaLegado?
    public var anterior: CorridaAnterior
    /// Conteos de la última lectura (el "antes" del recibo).
    public var conteos: ConteosLegado
    /// Falta la Fase R: hay ops por validar, colas estacionadas sin resolver o recibo sin dejar.
    public var faseRPendiente: Bool
    /// Lo que falta escribir de vuelta en el `localStorage` (sacar las ops tomadas y los cachés de sesión, dejar la marca).
    public var escritura: EscrituraPendiente?
    /// Corrida de la última escritura de vuelta hecha, y la última que la Ruta B leyó del disco en un arranque siguiente.
    public var escrituraHecha: Int?
    public var escrituraConfirmada: Int?
    /// La última que se hizo, por si no llegó al disco y hay que repetirla.
    public var escrituraUltima: EscrituraPendiente?
    public var copias: [String]
    public var recibos: Int
    /// Cuándo el SERVIDOR confirmó el recibo (G2). La copia cruda se borra 90 días después; sin RPC, nunca.
    public var reciboConfirmadoEn: Double?
}

public struct EscrituraPendiente: Codable, Equatable, Sendable {
    public var corrida: Int
    /// Clave → firma que tenía al leerla: se borra solo si sigue igual.
    public var borrar: [String: FirmaValor]
}

/// Una entrada del libro mayor (`legado/libro.json`): qué se hizo con cada op vieja. Lo que está acá no se vuelve a
/// importar nunca, aunque la Capacitor la siga teniendo.
public struct EntradaLibro: Codable, Equatable, Sendable {
    public enum Destino: String, Codable, Sendable, CaseIterable {
        /// A la cola nativa (se manda por la cola normal).
        case cola
        /// Sin sesión: espera la validación contra la rutina activa (Fase R).
        case porValidar
        /// No pasó la validación: en fallidos, con su motivo. Nunca se descarta.
        case paraRevisar
        /// De un token rotado, esperando la Fase R.
        case estacionada
        /// De un token rotado que resolvió al mismo cliente: a la cola.
        case reasignada
        /// La nativa tenía una pendiente más nueva con la misma dedupeKey.
        case reemplazada
        /// Cola sin token: no se ejecuta nunca.
        case anon
        /// El token rotado es de OTRO cliente: no se ejecuta nunca.
        case otroCliente
        /// El token rotado ya no resuelve: queda estacionada, va al recibo.
        case noResuelve
    }
    public var destino: Destino
    public var kind: String
    public var corrida: Int
}

/// Una cola que espera la Fase R (`legado/pendientes.json`): las ops sin sesión de la cuenta vigente, o todo lo de un
/// token rotado. Guarda el token: hace falta para preguntar `get_cliente_info` y está igual en los archivos de WebKit.
public struct ColaPendiente: Codable, Equatable, Sendable {
    public enum Estado: String, Codable, Sendable { case esperando, noResuelve, otroCliente }
    public var token: String
    public var clave: String
    public var firma: FirmaValor?
    /// De la cuenta vigente al leerla. Si no, es de un token rotado (estacionada).
    public var propia: Bool
    public var ops: [OpLegada]
    public var fotos: [String: FotoPendiente]
    public var rutinaFoto: String?
    public var estado: Estado
    public var corrida: Int
    /// La cola de fotos de ese token en la Capacitor (`ColaLegada.claveFotos`).
    public var claveFotos: String? = nil
    public var firmaFotos: FirmaValor? = nil
}

/// Archivos de `legado/`, con escritura atómica.
struct ArchivosLegado {
    let carpeta: URL

    func leer<T: Decodable>(_ t: T.Type, _ nombre: String) -> T? {
        guard let d = try? Data(contentsOf: carpeta.appendingPathComponent(nombre)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    func guardar<T: Encodable>(_ v: T, _ nombre: String) throws {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        try e.encode(v).write(to: carpeta.appendingPathComponent(nombre), options: [.atomic])
    }

    var estado: EstadoMigracion? { leer(EstadoMigracion.self, "estado.json") }
    var libro: [String: EntradaLibro] { leer([String: EntradaLibro].self, "libro.json") ?? [:] }
    var pendientes: [ColaPendiente] { leer([ColaPendiente].self, "pendientes.json") ?? [] }
}

extension Outbox.Persistido {
    /// La regla de `importar` (sin repetir ids, gana la última por dedupeKey) más "lo pendiente más nuevo gana".
    /// Devuelve las que quedaron en la cola (también las que ya estaban por id). `deLaMigracion: false` es lo que se
    /// adopta de otra carpeta de la misma persona (hallazgo 4): conserva su marca.
    mutating func importarSinPisar(_ nuevas: [Operacion], deLaMigracion: Bool = true) -> [Operacion] {
        var quedaron: [Operacion] = []
        for var op in nuevas {
            if ops.contains(where: { $0.id == op.id }) { quedaron.append(op); continue }
            if let k = op.dedupeKey, let otra = ops.last(where: { $0.dedupeKey == k }), otra.ts > op.ts { continue }
            if let k = op.dedupeKey { ops.removeAll { $0.dedupeKey == k } }
            // Son de la Capacitor: la palanca remota las puede frenar aunque ya estén en la cola (hallazgo 2).
            if deLaMigracion { op.legado = true }
            ops.append(op)
            quedaron.append(op)
        }
        return quedaron
    }
}

extension Outbox {
    /// Sin una cola viva de esa cuenta en el proceso (la Fase L corre antes de crear el modelo): directo al archivo,
    /// con la misma regla. La cola que arme el modelo lo levanta al iniciar. Tira si no puede escribir: así el libro
    /// mayor no anota algo que no quedó en la cola.
    static func importarEnArchivo(_ archivo: URL, _ ops: [Operacion]) throws -> [Operacion] {
        var p = (try? Data(contentsOf: archivo)).flatMap { try? JSONDecoder().decode(Persistido.self, from: $0) } ?? Persistido()
        let quedaron = p.importarSinPisar(ops)
        try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(p).write(to: archivo, options: [.atomic])
        return quedaron
    }
}

/// La Fase L aplicada: lee, copia, planifica y deja todo en su lugar. Síncrona y sin red, para correr antes de crear el
/// modelo (que lee el Keychain y la cola al iniciar).
public enum EjecutorLegado {
    public struct Resultado: Equatable, Sendable {
        /// Había almacenamiento viejo.
        public var huboLegado = false
        /// Corrió (la huella era nueva). false = no había nada que hacer.
        public var corrio = false
        public var corrida = 0
        public var repeticion = false
        public var tokenVigente: String?
        public var adoptoToken = false
        public var aLaCola = 0
        public var porValidar = 0
        public var estacionadas = 0
        public var anon = 0
        public var yaEnElLibro = 0
        public var reemplazadas = 0
        /// La Ruta B leyó la marca de una escritura de vuelta anterior: llegó al disco.
        public var escrituraConfirmada: Int?
        public var plan: PlanMigracion?
    }

    /// Una restauración que trae el almacenamiento de la app vieja y `legado/` pero no el Keychain (un respaldo local de
    /// Finder sin cifrar): con la misma huella, la Fase L cortaba y pedía el link. Sin token guardado, si la corrida
    /// anterior vio un token de la app vieja que no quedó marcado inválido, se vuelve a correr y se adopta (gemelo del D14
    /// de Android, 15-oct). No hay un «salir» a la vista del cliente que esto deshaga.
    static func hayQueVolverAAdoptar(_ previo: EstadoMigracion, almacen: AlmacenToken, ajustes: UserDefaults) -> Bool {
        guard let legado = previo.anterior.tokenLegado, almacen.leer() == nil else { return false }
        // Solo si la nativa anduvo con ESA cuenta (o con ninguna): si anduvo con otra, no se vuelve a la de la app vieja.
        if let ultima = UltimaCuenta.hash(en: ajustes), ultima != legado { return false }
        guard let invalido = ajustes.string(forKey: "mypump_token_invalido") else { return true }
        return JSONLegado.sha256(invalido) != legado
    }

    /// El libro de las fotos que ya pasaron a la nativa: una repetición de la Fase L no las vuelve a poner en la cola (una
    /// ya subida podía pisar en el servidor otra más nueva de la misma semana y pose; revisión adversarial, hallazgo 5).
    static let archivoFotosImportadas = "fotos-importadas.json"

    static func idFoto(_ clave: String, _ k: String, _ f: FotoPendiente) -> String {
        JSONLegado.sha256("\(clave)|\(k)|\(f.fecha)|\(JSONLegado.sha256(f.dataUrl))")
    }

    /// - Parameters:
    ///   - cuentaViva: el token que ya tiene una `Outbox` viva en este proceso (el modelo ya existe). Sus ops no se
    ///     escriben al archivo (la cola viva lo pisaría al guardar): van todas a la Fase R, que las importa con `await`.
    public static func faseLocal(entorno: EntornoLegado, almacen: AlmacenToken, ajustes: UserDefaults,
                                 ahora: Date = Date(), zona: TimeZone = .current, cuentaViva: String? = nil) throws -> Resultado {
        var r = Resultado()
        let archivos = LectorLegado.ubicar(library: entorno.library)
        guard !archivos.isEmpty else { return r }
        r.huboLegado = true
        let a = ArchivosLegado(carpeta: entorno.carpeta)
        let previo = a.estado
        let huella = LectorLegado.huella(library: entorno.library, archivos: archivos)
        if var previo, previo.huella == huella, !hayQueVolverAAdoptar(previo, almacen: almacen, ajustes: ajustes) {
            // Se escribió de vuelta pero los archivos no cambiaron: no llegó al disco (el proceso murió antes de que WebKit
            // la bajara). Se repite. Si llegó, la huella cambió y esta misma función la confirma leyendo la marca.
            if let hecha = previo.escrituraHecha, hecha > (previo.escrituraConfirmada ?? 0), previo.escritura == nil,
               let ultima = previo.escrituraUltima {
                previo.escritura = ultima
                try a.guardar(previo, "estado.json")
            }
            return r
        }

        let ms = ahora.timeIntervalSince1970 * 1000
        var estado = previo ?? EstadoMigracion(migracion: UUID().uuidString.lowercased(), corridas: 0, primera: ms, ultima: ms, huella: nil,
                                               anterior: CorridaAnterior(), conteos: ConteosLegado(), faseRPendiente: false,
                                               escritura: nil, escrituraHecha: nil, escrituraConfirmada: nil, escrituraUltima: nil,
                                               copias: [], recibos: 0, reciboConfirmadoEn: nil)
        let corrida = estado.corridas + 1
        r.corrida = corrida
        r.repeticion = previo != nil

        // 1. La copia cruda, antes de tocar nada. Lleva la huella en el nombre: si una lectura falla y se reintenta en el
        //    arranque siguiente con los mismos archivos, no se copia de nuevo.
        let h8 = String(JSONLegado.sha256((try? String(decoding: JSONEncoder().encode(huella), as: UTF8.self)) ?? "").prefix(8))
        let existente = ((try? FileManager.default.contentsOfDirectory(atPath: entorno.carpeta.path)) ?? []).first { $0.hasSuffix("-\(h8)") }
        let nombreCopia = existente ?? "\(Self.sello(ahora))-\(h8)"
        if existente == nil {
            let destino = entorno.carpeta.appendingPathComponent(nombreCopia, isDirectory: true)
            let copiados = try LectorLegado.copiarCrudo(library: entorno.library, archivos: archivos, a: destino)
            try ArchivosLegado(carpeta: destino).guardar(Manifiesto(huella: huella, archivos: archivos, copiados: copiados, corrida: corrida),
                                                         "manifiesto.json")
            // Sirve en ESTE teléfono: no va al backup (los archivos de WebKit ya van por su lado). El estado y el libro
            // mayor sí van: restaurados sin ellos, la migración volvería a importar lo que ya se mandó.
            Self.excluirDelBackup(destino)
        }

        // 2. Leer (de una copia aparte: la cruda no se abre nunca) y planificar.
        guard let lectura = try LectorLegado.leer(library: entorno.library) else { return r }
        let contexto = ContextoMigracion(tokenNativo: almacen.leer(), tokenInvalidoNativo: ajustes.string(forKey: "mypump_token_invalido"),
                                         anterior: previo?.anterior, ultimaCuenta: UltimaCuenta.hash(en: ajustes))
        let plan = MigracionLegado.planificar(lectura.items, firmas: lectura.firmas, ahora: ahora, zona: zona, contexto: contexto)
        r.plan = plan
        r.tokenVigente = plan.tokenVigente

        // 3. Token. Accesible después del primer desbloqueo (TokenEnKeychain). Se lee de vuelta: si `SecItemAdd` falló, la
        //    Fase L quedaba hecha igual (con la huella anotada no vuelve a correr) y la app abría en "pegá tu link" para
        //    siempre (sospecha de la revisión del 15-oct, confirmada). Así no queda hecha: todavía no se escribió nada más
        //    (la copia cruda ya está y no se repite) y se reintenta enseguida o en el arranque siguiente.
        if plan.adoptarToken, let t = plan.tokenVigente {
            almacen.guardar(t)
            guard almacen.leer() == t else { throw ErrorLegado.keychain }
            UltimaCuenta.anotar(t, en: ajustes)
            r.adoptoToken = true
        }

        // 4. Ajustes: en la primera corrida no se pisa uno que la nativa ya tenga; en una repetición, lo que cambió en la
        //    Capacitor es lo último que hizo el cliente.
        for (k, v) in plan.preferencias where previo != nil || ajustes.object(forKey: k) == nil {
            ajustes.set(v, forKey: k)
        }

        // 5. Lo de la cuenta vigente.
        var libro = a.libro
        var pendientes = a.pendientes
        var fotosImportadas = Set(a.leer([String].self, Self.archivoFotosImportadas) ?? [])
        var borrar = estado.escritura?.borrar ?? [:]
        if let t = plan.tokenVigente {
            let disco = entorno.disco(t)
            if let e = plan.entreno { Self.guardarEntreno(e, en: disco) }
            if let c = plan.copiaOffline {
                let actual = disco.leer(ModeloApp.CopiaOffline.self, "offline.json")
                if actual == nil || (actual?.ts ?? 0) < c.ts {
                    disco.guardar(ModeloApp.CopiaOffline(info: c.info, rutina: c.rutina, dieta: c.dieta, ts: c.ts), "offline.json")
                }
            }
            for (rutina, s) in plan.sustituciones {
                let nombre = SustitucionEjercicio.archivo(rutinaId: rutina)
                let legado = (try? JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(s))) ?? [:]
                if previo == nil {
                    if !FileManager.default.fileExists(atPath: disco.url(nombre).path) { disco.guardar(s, nombre) }
                } else {
                    // El cliente volvió a la app vieja y cambió algo ahí. SER-14: solo lo que cambió AHÍ desde la corrida
                    // anterior pisa lo del teléfono (con la hora de ahora, para que gane también en el servidor) y lo que
                    // sacó ahí se saca; lo hecho en la nativa o llegado de otro teléfono queda. Antes se pisaba todo.
                    let nativa = disco.leer([String: JSONValue].self, nombre) ?? [:]
                    let base = disco.leer([String: JSONValue].self, SustitucionesServidor.archivoLegado(rutinaId: rutina))
                    // Lo que había se toma como ya subido: así lo que se saca sale como borrado y lo cambiado como guardado.
                    let encoladas = SustitucionesServidor.archivoEncoladas(rutinaId: rutina)
                    if !FileManager.default.fileExists(atPath: disco.url(encoladas).path) { disco.guardar(nativa, encoladas) }
                    disco.guardar(SustitucionesServidor.volverDeLaAppVieja(nativa: nativa, legado: legado, base: base,
                                                                         ms: ahora.timeIntervalSince1970 * 1000), nombre)
                }
                // Lo que se leyó de la app vieja: la base para la próxima vuelta.
                disco.guardar(legado, SustitucionesServidor.archivoLegado(rutinaId: rutina))
            }
            for (dieta, s) in plan.swapsComida {
                // El mapa local es una caché del servidor: si la nativa ya tiene el suyo, gana el suyo.
                if !s.swaps.isEmpty, !FileManager.default.fileExists(atPath: disco.url("swaps_\(dieta).json").path) {
                    disco.guardar(s.swaps, "swaps_\(dieta).json")
                }
                if s.migrados, disco.leer(Bool.self, "swaps_migrados_\(dieta)") != true { disco.guardar(true, "swaps_migrados_\(dieta)") }
            }
        }

        // 6. Las colas.
        for q in plan.colas {
            let nuevas = q.ops.filter { libro[$0.idLibro] == nil }
            r.yaEnElLibro += q.ops.count - nuevas.count
            switch q.tipo {
            case .anon:
                for op in nuevas { libro[op.idLibro] = EntradaLibro(destino: .anon, kind: op.operacion.kind, corrida: corrida) }
                r.anon += nuevas.count
            case .vigente:
                guard let t = q.token else { continue }
                let disco = entorno.disco(t)
                let alArchivo = t != cuentaViva
                let directas = alArchivo ? nuevas.filter { !$0.necesitaValidar } : []
                let aLaFaseR = alArchivo ? nuevas.filter(\.necesitaValidar) : nuevas
                if !directas.isEmpty {
                    let quedaron = Set(try Outbox.importarEnArchivo(disco.url("outbox.json"), directas.map(\.operacion)).map(\.id))
                    for op in directas {
                        let entro = quedaron.contains(op.operacion.id)
                        libro[op.idLibro] = EntradaLibro(destino: entro ? .cola : .reemplazada, kind: op.operacion.kind, corrida: corrida)
                        if entro { r.aLaCola += 1 } else { r.reemplazadas += 1 }
                    }
                }
                if !aLaFaseR.isEmpty {
                    Self.encolarPendiente(&pendientes, token: t, cola: q, ops: aLaFaseR, fotos: [:], propia: true, corrida: corrida)
                    for op in aLaFaseR {
                        libro[op.idLibro] = EntradaLibro(destino: op.necesitaValidar ? .porValidar : .estacionada, kind: op.operacion.kind, corrida: corrida)
                    }
                    r.porValidar += aLaFaseR.count
                }
                if !q.valorIlegible, let f = q.firma { borrar[q.clave] = f }
                let fotos = q.fotos.filter { !fotosImportadas.contains(Self.idFoto(q.clave, $0.key, $0.value)) }
                if alArchivo {
                    // La cola de fotos de la Capacitor se borra solo si las fotos quedaron en la nativa.
                    if fotos.isEmpty || Self.sumarFotos(fotos, en: disco) {
                        for (k, f) in fotos { fotosImportadas.insert(Self.idFoto(q.clave, k, f)) }
                        if let k = q.claveFotos, let f = q.firmaFotos { borrar[k] = f }
                    }
                } else if !fotos.isEmpty {
                    // Con el modelo vivo, las fotos van por la Fase R, que las suma a su cola en memoria: escribir el archivo
                    // por detrás las perdía (la cola lo pisa al guardar; revisión adversarial del 15-oct, hallazgo 2).
                    Self.encolarPendiente(&pendientes, token: t, cola: q, ops: [], fotos: fotos, propia: true, corrida: corrida)
                    for (k, f) in fotos { fotosImportadas.insert(Self.idFoto(q.clave, k, f)) }
                } else if let k = q.claveFotos, let f = q.firmaFotos {
                    borrar[k] = f
                }
            case .otroToken:
                let fotos = q.fotos.filter { !fotosImportadas.contains(Self.idFoto(q.clave, $0.key, $0.value)) }
                guard let t = q.token, !nuevas.isEmpty || !fotos.isEmpty else { continue }
                Self.encolarPendiente(&pendientes, token: t, cola: q, ops: nuevas, fotos: fotos, propia: false, corrida: corrida)
                for (k, f) in fotos { fotosImportadas.insert(Self.idFoto(q.clave, k, f)) }
                for op in nuevas { libro[op.idLibro] = EntradaLibro(destino: .estacionada, kind: op.operacion.kind, corrida: corrida) }
                r.estacionadas += nuevas.count
            }
        }

        // 7. La escritura de vuelta: los cachés de sesión, y la marca si no está la de esta migración.
        for (k, f) in plan.sesionesParaBorrar { borrar[k] = f }
        if let marca = Marca.leer(plan.marcaLeida), marca.migracion == estado.migracion {
            r.escrituraConfirmada = marca.corrida
            estado.escrituraConfirmada = max(estado.escrituraConfirmada ?? 0, marca.corrida)
        }
        let falta = !borrar.isEmpty || r.escrituraConfirmada == nil
        estado.escritura = falta ? EscrituraPendiente(corrida: corrida, borrar: borrar) : nil

        // 8. Primero lo que ya quedó en la cola (arriba), después el libro y por último el estado: si el proceso muere en
        //    el medio, la corrida se repite y la cola no duplica (mismo id).
        try a.guardar(libro, "libro.json")
        try a.guardar(pendientes, "pendientes.json")
        try a.guardar(fotosImportadas.sorted(), Self.archivoFotosImportadas)
        estado.corridas = corrida
        estado.ultima = ms
        estado.huella = lectura.huella
        estado.anterior = CorridaAnterior(huellasClaves: plan.huellasClaves, tokenLegado: plan.tokenLegadoHash)
        estado.conteos = plan.conteos
        if !estado.copias.contains(nombreCopia) { estado.copias.append(nombreCopia) }
        estado.faseRPendiente = estado.faseRPendiente || pendientes.contains { $0.estado == .esperando } || estado.escritura != nil
            || r.aLaCola > 0 || r.porValidar > 0
        try a.guardar(estado, "estado.json")
        r.corrio = true
        return r
    }

    /// `legado/<corrida>-<sello>/manifiesto.json`: qué hay en la copia cruda.
    struct Manifiesto: Codable {
        let huella: HuellaLegado
        let archivos: [ArchivoLegado]
        let copiados: [String]
        let corrida: Int
    }

    static func encolarPendiente(_ pendientes: inout [ColaPendiente], token: String, cola q: ColaLegada, ops: [OpLegada],
                                 fotos: [String: FotoPendiente], propia: Bool, corrida: Int) {
        if let i = pendientes.firstIndex(where: { $0.token == token && $0.propia == propia }) {
            let ya = Set(pendientes[i].ops.map(\.idLibro))
            pendientes[i].ops.append(contentsOf: ops.filter { !ya.contains($0.idLibro) })
            pendientes[i].fotos.merge(fotos) { actual, nueva in nueva.fecha >= actual.fecha ? nueva : actual }
            pendientes[i].firma = q.firma ?? pendientes[i].firma
            pendientes[i].rutinaFoto = q.rutinaFoto ?? pendientes[i].rutinaFoto
            pendientes[i].estado = .esperando
            pendientes[i].corrida = corrida
            if let k = q.claveFotos, let f = q.firmaFotos { pendientes[i].claveFotos = k; pendientes[i].firmaFotos = f }
        } else {
            pendientes.append(ColaPendiente(token: token, clave: q.clave, firma: q.firma, propia: propia, ops: ops, fotos: fotos,
                                            rutinaFoto: q.rutinaFoto, estado: .esperando, corrida: corrida,
                                            claveFotos: q.claveFotos, firmaFotos: q.firmaFotos))
        }
    }

    /// Junta con lo que la cuenta ya tenía: por `"<lunes>|<pose>"`, gana la foto más nueva.
    /// Devuelve si quedaron en el disco.
    @discardableResult
    static func sumarFotos(_ fotos: [String: FotoPendiente], en disco: Disco) -> Bool {
        var actuales = disco.leer([String: FotoPendiente].self, FotoPendiente.archivo) ?? [:]
        actuales.merge(fotos) { actual, nueva in nueva.fecha >= actual.fecha ? nueva : actual }
        return disco.guardar(actuales, FotoPendiente.archivo)
    }

    /// Por día gana lo leído ahora; el descanso, si hay uno nuevo.
    static func guardarEntreno(_ e: EntrenoLegado, en disco: Disco) {
        var actual = disco.leer(EntrenoLegado.self, EntrenoLegado.archivo) ?? EntrenoLegado()
        actual.sesiones.merge(e.sesiones) { _, nueva in nueva }
        if let d = e.descanso { actual.descanso = d }
        actual.diaVisualizado.merge(e.diaVisualizado) { _, nuevo in nuevo }
        disco.guardar(actual, EntrenoLegado.archivo)
    }

    static func sello(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: d)
    }

    /// La copia cruda sirve en ESTE teléfono: no va al backup de iCloud (lo de WebKit ya va por su lado).
    static func excluirDelBackup(_ url: URL) {
        var u = url
        var v = URLResourceValues()
        v.isExcludedFromBackup = true
        try? u.setResourceValues(v)
    }
}

/// `mypump_nativa_marca`: la deja la escritura de vuelta. Leerla en el arranque siguiente con la Ruta B confirma que
/// llegó al disco.
public struct Marca: Codable, Equatable, Sendable {
    public var migracion: String
    public var corrida: Int
    public var fecha: String
    public var app: String?

    static func leer(_ s: String?) -> Marca? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Marca.self, from: d)
    }

    var texto: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}
