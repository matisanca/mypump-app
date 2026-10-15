import Foundation
import MyPumpModelos
import MyPumpReglas

// MARK: - Recibo

/// El recibo de una corrida: conteos antes (lo leído del almacenamiento viejo) y después (dónde quedó cada cosa del lado
/// nativo), sin contenido crudo ni claves con token.
public struct ReciboLegado: Codable, Equatable, Sendable {
    public var migracion: String
    public var corrida: Int
    public var fecha: String
    public var plataforma: String
    public var app: String?
    public var antes: ConteosLegado
    public var despues: ConteosNativos
    /// Filas por tabla del cliente en el servidor, antes y después de mandar las ops. Necesitan la RPC
    /// `mypump_conteos_cliente(p_token)` (G2): hasta entonces van vacíos.
    public var servidorAntes: [String: Int]?
    public var servidorDespues: [String: Int]?
    /// El cliente de la corrida: un recibo que quedó en el disco solo se reenvía con la cuenta que lo generó.
    public var cliente: String?
}

public struct ConteosNativos: Codable, Equatable, Sendable {
    /// Destino → ops, sumando todas las corridas (el libro mayor).
    public var libro: [String: Int] = [:]
    public var colaPendientes = 0
    public var fallidos = 0
    public var colasEsperando = 0
    public var colasNoResuelven = 0
    public var colasOtroCliente = 0
    public var fotosPendientes = 0
    public var fotosFueraDeVentana = 0
}

public enum EntregaRecibo: String, Codable, Sendable {
    /// Lo confirmó el servidor: a los 90 días se puede borrar la copia cruda.
    case confirmado
    /// Quedó en el teléfono (sin la RPC del recibo).
    case soloLocal
    case fallo
}

/// A dónde va el recibo: al disco (`ReciboEnDisco`) y, con la `nativa_001` aplicada, también al servidor
/// (`ReciboEnServidor`, `mypump_registrar_migracion_nativa`).
public protocol ReciboMigracion: Sendable {
    func enviar(_ recibo: ReciboLegado, token: String) async -> EntregaRecibo
}

/// El recibo en `legado/recibos/recibo-<corrida>.json`. Nunca "confirmado": sin el servidor, la copia cruda no se borra.
public struct ReciboEnDisco: ReciboMigracion {
    public let carpeta: URL
    public init(carpeta: URL) { self.carpeta = carpeta }

    public func enviar(_ recibo: ReciboLegado, token: String) async -> EntregaRecibo {
        do {
            try ArchivosLegado(carpeta: carpeta).guardar(recibo, "recibo-\(recibo.corrida).json")
            return .soloLocal
        } catch {
            return .fallo
        }
    }
}

/// Filas por tabla del cliente (`mypump_conteos_cliente`, `ConteosRPC`). Sin la RPC, nil.
public protocol ConteosServidor: Sendable {
    func contar(token: String) async -> [String: Int]?
}

public struct SinConteosServidor: ConteosServidor {
    public init() {}
    public func contar(token: String) async -> [String: Int]? { nil }
}

// MARK: - Fase R

/// Lo que se hace con red, después del primer `get_cliente_info` que contestó: validar las ops sin sesión contra la
/// rutina activa, reasignar las colas de tokens rotados, mandar lo importado por la cola normal y dejar el recibo. La
/// escritura de vuelta la hace la app (WebKit) con `escrituraPendiente` / `registrarEscritura`.
@MainActor
public enum FaseRemotaLegado {
    public struct Resultado: Equatable, Sendable {
        public var corrio = false
        /// Algo no se pudo preguntar (red): queda pendiente para la próxima.
        public var sinRed = false
        public var aLaCola = 0
        public var paraRevisar = 0
        public var reasignadas = 0
        public var reemplazadas = 0
        public var noResuelven = 0
        public var otroCliente = 0
        /// Swaps de comida locales que el servidor no tenía y entraron a la cola (la migración que hacía la web).
        public var swapsSinMigrar = 0
        public var recibo: EntregaRecibo?
    }

    /// - Parameters:
    ///   - token, clienteId: la cuenta abierta (la del modelo, ya cargada con red).
    ///   - outbox: la cola VIVA de esa cuenta (la del modelo): importar con `await` no pisa lo que encoló la app.
    public static func correr(entorno: EntornoLegado, token: String, clienteId: String, cliente: ClienteRPC, outbox: Outbox,
                              recibo: ReciboMigracion, conteos: ConteosServidor = SinConteosServidor(), app: String? = nil,
                              ahora: Date = Date(), zona: TimeZone = .current) async -> Resultado {
        var r = Resultado()
        let a = ArchivosLegado(carpeta: entorno.carpeta)
        guard var estado = a.estado, estado.faseRPendiente else { return r }
        r.corrio = true
        var pendientes = a.pendientes
        var libro = a.libro
        let corrida = estado.corridas
        let servidorAntes = await conteos.contar(token: token)

        // La rutina activa se pregunta una vez y solo si hace falta. `.none` = todavía no; `.some(nil)` = no tiene.
        var activa: RutinaActiva??
        func rutinaActiva() async -> RutinaActiva?? {
            if let activa { return activa }
            switch await cliente.llamar("mypump_get_rutina_activa", ["p_token": .texto(token)]) {
            case .failure:
                return nil
            case .success(let j):
                let fila = j.primeraFila.flatMap { try? JSONDecoder().decode(RutinaActiva.self, from: JSONEncoder().encode($0)) }
                activa = .some(fila)
                return activa
            }
        }

        // Los swaps de comida que el teléfono tenía y el servidor nunca vio: se deciden ANTES de drenar nada.
        switch await subirSwapsSinMigrar(entorno: entorno, token: token, cliente: cliente, outbox: outbox) {
        case .none: r.sinRed = true
        case .some(let n):
            r.swapsSinMigrar = n
            // Decidido: los reemplazos de la cola vieja ya pueden salir (hasta acá los retenía la cola).
            await outbox.soltarSwapsLegados()
        }

        var resueltas: Set<Int> = []
        for i in pendientes.indices where pendientes[i].estado == .esperando {
            let p = pendientes[i]
            if p.token != token {
                // Un token rotado: solo si resuelve al MISMO cliente. Nunca se ejecuta lo de otra persona.
                switch await cliente.llamar("mypump_get_cliente_info", ["p_token": .texto(p.token)]) {
                case .failure:
                    r.sinRed = true
                    continue
                case .success(let j):
                    guard let fila = j.primeraFila else {
                        pendientes[i].estado = .noResuelve
                        for op in p.ops { libro[op.idLibro]?.destino = .noResuelve }
                        r.noResuelven += p.ops.count
                        continue
                    }
                    guard fila["cliente_id"]?.comoTexto == clienteId else {
                        pendientes[i].estado = .otroCliente
                        for op in p.ops { libro[op.idLibro]?.destino = .otroCliente }
                        r.otroCliente += p.ops.count
                        continue
                    }
                }
            }
            var rutina: RutinaActiva?
            if p.ops.contains(where: \.necesitaValidar) {
                guard let consultada = await rutinaActiva() else { r.sinRed = true; continue }
                rutina = consultada
            }
            var buenas: [OpLegada] = []
            var malas: [String: [OpLegada]] = [:]
            for op in p.ops {
                if op.necesitaValidar, let motivo = motivoParaRevisar(op, rutinaFoto: p.rutinaFoto, activa: rutina) {
                    malas[motivo, default: []].append(op)
                } else {
                    buenas.append(op)
                }
            }
            let quedaron = Set(await outbox.importarSinPisar(buenas.map(\.operacion)).map(\.id))
            for op in buenas {
                let entro = quedaron.contains(op.operacion.id)
                libro[op.idLibro] = EntradaLibro(destino: entro ? (p.propia ? .cola : .reasignada) : .reemplazada, kind: op.operacion.kind,
                                                 corrida: libro[op.idLibro]?.corrida ?? corrida)
                if !entro { r.reemplazadas += 1 } else if p.propia { r.aLaCola += 1 } else { r.reasignadas += 1 }
            }
            for (motivo, ops) in malas.sorted(by: { $0.key < $1.key }) {
                await outbox.archivarEnFallidos(ops.map(\.operacion), motivo: "para revisar: \(motivo)")
                for op in ops {
                    libro[op.idLibro] = EntradaLibro(destino: .paraRevisar, kind: op.operacion.kind, corrida: libro[op.idLibro]?.corrida ?? corrida)
                }
                r.paraRevisar += ops.count
            }
            if !p.fotos.isEmpty { EjecutorLegado.sumarFotos(p.fotos, en: entorno.disco(token)) }
            // Lo de un token rotado ya es de esta cuenta: la escritura de vuelta saca su cola (y la de fotos) de la Capacitor.
            if !p.propia {
                var borrar: [String: FirmaValor] = [:]
                if let f = p.firma { borrar[p.clave] = f }
                if let k = p.claveFotos, let f = p.firmaFotos { borrar[k] = f }
                if !borrar.isEmpty {
                    var e = estado.escritura ?? EscrituraPendiente(corrida: corrida, borrar: [:])
                    e.borrar.merge(borrar) { _, nueva in nueva }
                    estado.escritura = e
                }
            }
            resueltas.insert(i)
        }
        pendientes = pendientes.enumerated().filter { !resueltas.contains($0.offset) }.map(\.element)
        try? a.guardar(libro, "libro.json")
        try? a.guardar(pendientes, "pendientes.json")

        if !r.sinRed, r.aLaCola + r.reasignadas + r.swapsSinMigrar > 0 { await outbox.drenar() }

        if !r.sinRed {
            // El recibo, con lo que quedó.
            var despues = ConteosNativos()
            for e in libro.values { despues.libro[e.destino.rawValue, default: 0] += 1 }
            despues.colaPendientes = await outbox.pendientes
            despues.fallidos = await outbox.fallidos.count
            despues.colasEsperando = pendientes.filter { $0.estado == .esperando }.count
            despues.colasNoResuelven = pendientes.filter { $0.estado == .noResuelve }.count
            despues.colasOtroCliente = pendientes.filter { $0.estado == .otroCliente }.count
            let fotos = entorno.disco(token).leer([String: FotoPendiente].self, FotoPendiente.archivo) ?? [:]
            despues.fotosPendientes = fotos.count
            let ms = ahora.timeIntervalSince1970 * 1000
            let hoy = FechaLegado.dia(ms, zona: zona)
            let (desde, hasta) = (FechaLegado.sumar(hoy, -7, zona: zona), FechaLegado.sumar(hoy, 1, zona: zona))
            despues.fotosFueraDeVentana = fotos.values.filter { $0.fecha < desde || $0.fecha > hasta }.count
            let rec = ReciboLegado(migracion: estado.migracion, corrida: corrida, fecha: ISO8601DateFormatter().string(from: ahora),
                                   plataforma: "ios", app: app, antes: estado.conteos, despues: despues,
                                   servidorAntes: servidorAntes, servidorDespues: await conteos.contar(token: token), cliente: clienteId)
            let entrega = await recibo.enviar(rec, token: token)
            r.recibo = entrega
            estado.recibos += 1
            if entrega == .confirmado, estado.reciboConfirmadoEn == nil { estado.reciboConfirmadoEn = ms }
        }
        estado.faseRPendiente = r.sinRed || pendientes.contains { $0.estado == .esperando }
        try? a.guardar(estado, "estado.json")
        return r
    }

    /// "Ancla y sube los swaps de comida sin migrar": los del mapa local de la dieta activa que el servidor nunca vio (un
    /// teléfono que viene de antes de que los swaps se guardaran en la base; la v1.0.11 no tenía la marca de migrados).
    /// La hidratación del modelo hace lo mismo (`SwapsDeComida.hidratar`, rama de migración), pero corre EN PARALELO con
    /// esta fase: si el drenado de acá manda primero un swap de la cola vieja, la hidratación ve el servidor con algo, toma
    /// el merge y descarta los locales que no están en la cola. Por eso se decide acá, antes de drenar, con la misma
    /// función: si el servidor no tiene ninguno, los locales entran a la cola y la hidratación los respeta (lo pendiente
    /// gana). Devuelve cuántos encoló; nil = no se pudo preguntar.
    static func subirSwapsSinMigrar(entorno: EntornoLegado, token: String, cliente: ClienteRPC, outbox: Outbox) async -> Int? {
        let disco = entorno.disco(token)
        switch await cliente.llamar("mypump_get_dieta_activa", ["p_token": .texto(token)]) {
        case .failure:
            return nil
        case .success(let j):
            guard let dieta = j.primeraFila?["id"]?.comoTexto, disco.leer(Bool.self, "swaps_migrados_\(dieta)") != true,
                  let locales = disco.leer([String: SwapLocal].self, "swaps_\(dieta).json"), !locales.isEmpty else { return 0 }
            // `null` es la red, no "cero swaps": tratarlo como vacío volvería a subir lo que se borró en otro lado.
            guard case .success(let crudo) = await cliente.llamar("mypump_get_food_swaps", ["p_token": .texto(token), "p_dieta_id": .texto(dieta)]),
                  crudo != .null, let remotos = try? JSONDecoder().decode([FoodSwap].self, from: JSONEncoder().encode(crudo)) else { return nil }
            let pendientes = (await outbox.pendientesPorClave()).mapValues(\.kind)
            guard let h = SwapsDeComida.hidratar(remotos: remotos, locales: locales, dietaId: dieta, pendientes: pendientes, yaMigrado: false,
                                                 enPosicion: { _, _, _ in [] }), h.migrando else { return 0 }
            var n = 0
            for op in h.operaciones where pendientes[op.clave] == nil {
                var payload = op.payload
                if case .objeto(var o) = payload { o["dietaId"] = .texto(dieta); payload = .objeto(o) }
                await outbox.encolar(op.kind, payload, dedupeKey: op.clave)
                n += 1
            }
            return n
        }
    }

    /// Por qué una op SIN sesión no se puede mandar (nil = se puede). Con otra rutina activa, `resolveSesion` le crearía
    /// una sesión al bloque nuevo con las series del viejo: una sesión fantasma. No se descarta: va a fallidos.
    static func motivoParaRevisar(_ op: OpLegada, rutinaFoto: String?, activa: RutinaActiva?) -> String? {
        guard let activa else { return "no hay rutina activa" }
        guard let foto = rutinaFoto else { return "sin foto offline, no se sabe de qué rutina era" }
        guard foto == activa.id else { return "la rutina activa ya no es la de la foto" }
        guard let dia = op.operacion.payload["diaId"]?.comoTexto, activa.estructura.dias.contains(where: { $0.id == dia }) else {
            return "el día no está en la rutina activa"
        }
        return nil
    }

    /// Hay algo para la Fase R o para escribir de vuelta. Sin esto la app no espera la carga con red.
    public static func hayPendiente(entorno: EntornoLegado) -> Bool {
        guard let e = ArchivosLegado(carpeta: entorno.carpeta).estado else { return false }
        return e.faseRPendiente || e.escritura != nil
    }

    /// Solo la Fase R (sin contar la escritura de vuelta): es lo que pausa la palanca `migracion_ops_legadas`.
    public static func faseRPendiente(entorno: EntornoLegado) -> Bool {
        ArchivosLegado(carpeta: entorno.carpeta).estado?.faseRPendiente ?? false
    }

    // MARK: - Escritura de vuelta (la hace la app con WebKit, Ruta A)

    /// Lo que la app tiene que escribir en el `localStorage` viejo: borrar esas claves (si siguen iguales) y dejar la
    /// marca. nil = nada, o la Fase R todavía no terminó (las colas que se reasignen también se sacan, de una vez).
    public struct CambiosEscritura: Equatable, Sendable {
        public let corrida: Int
        public let borrar: [String: FirmaValor]
        public let marca: String
    }

    public static func escrituraPendiente(entorno: EntornoLegado, app: String? = nil, ahora: Date = Date()) -> CambiosEscritura? {
        guard let estado = ArchivosLegado(carpeta: entorno.carpeta).estado, !estado.faseRPendiente, let e = estado.escritura else { return nil }
        let marca = Marca(migracion: estado.migracion, corrida: e.corrida, fecha: ISO8601DateFormatter().string(from: ahora), app: app)
        return CambiosEscritura(corrida: e.corrida, borrar: e.borrar, marca: marca.texto)
    }

    /// El cuerpo de la función que corre en `capacitor://localhost` (`callAsyncJavaScript`, con los argumentos `borrar`
    /// = `{clave: {unidades, fnv}}` y `marca`). Borra cada clave SOLO si sigue igual a como se leyó (misma cantidad de
    /// unidades UTF-16 y mismo FNV-1a de 32 bits, el de `FirmaValor`), deja la marca y devuelve qué pasó con cada una.
    /// Vive acá y no en la app para que `swift test` lo corra con JavaScriptCore.
    public static let scriptEscritura = """
    function firma(s) {
      let h = 0x811c9dc5;
      for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
      return [s.length, h >>> 0];
    }
    const res = {};
    for (const clave of Object.keys(borrar)) {
      const esperado = borrar[clave];
      const v = localStorage.getItem(clave);
      if (v === null) { res[clave] = 'no estaba'; continue; }
      const f = firma(v);
      if (f[0] !== esperado.unidades || f[1] !== esperado.fnv) { res[clave] = 'cambio'; continue; }
      localStorage.removeItem(clave);
      res[clave] = localStorage.getItem(clave) === null ? 'borrada' : 'fallo';
    }
    localStorage.setItem('mypump_nativa_marca', marca);
    res['mypump_nativa_marca'] = localStorage.getItem('mypump_nativa_marca') === marca ? 'ok' : 'fallo';
    return res;
    """

    /// Los argumentos de `scriptEscritura`, en tipos que WebKit sabe pasar a JavaScript.
    public static func argumentosEscritura(_ c: CambiosEscritura) -> [String: Any] {
        var borrar: [String: Any] = [:]
        for (k, f) in c.borrar { borrar[k] = ["unidades": f.unidades, "fnv": Double(f.fnv)] }
        return ["borrar": borrar, "marca": c.marca]
    }

    /// Lo que contestó el `localStorage` por clave (`borrada`, `no estaba`, `cambio`, `fallo`) y por la marca (`ok`).
    /// Con la marca escrita queda hecha; se confirma en el arranque siguiente, cuando la Ruta B la lee del disco. Lo que
    /// "cambió" no se borra: la huella cambió y la Fase L va a correr de nuevo con lo nuevo.
    public static func registrarEscritura(entorno: EntornoLegado, cambios: CambiosEscritura, resultado: [String: String]) {
        let a = ArchivosLegado(carpeta: entorno.carpeta)
        guard var estado = a.estado, resultado[MigracionLegado.claveMarca] == "ok" else { return }
        estado.escrituraHecha = cambios.corrida
        estado.escrituraUltima = estado.escritura
        estado.escritura = nil
        try? a.guardar(estado, "estado.json")
    }

    /// Los recibos que quedaron solo en el disco (la RPC todavía no existía, o no hubo red), otra vez al servidor, con la
    /// misma cuenta que los generó. El primero que confirma arranca la cuenta de los 90 días de la copia cruda.
    @discardableResult
    public static func reenviarRecibos(entorno: EntornoLegado, token: String, clienteId: String, cliente: ClienteRPC,
                                       ahora: Date = Date()) async -> Int {
        let n = await ReciboEnServidor.reenviar(carpeta: entorno.carpeta.appendingPathComponent("recibos"), token: token,
                                                clienteId: clienteId, cliente: cliente)
        let a = ArchivosLegado(carpeta: entorno.carpeta)
        if n > 0, var estado = a.estado, estado.reciboConfirmadoEn == nil {
            estado.reciboConfirmadoEn = ahora.timeIntervalSince1970 * 1000
            try? a.guardar(estado, "estado.json")
        }
        return n
    }

    /// La copia cruda se borra 90 días después de que el SERVIDOR confirmó el recibo (con el recibo solo en disco, nunca).
    public static func podarCopias(entorno: EntornoLegado, ahora: Date = Date()) {
        let a = ArchivosLegado(carpeta: entorno.carpeta)
        guard var estado = a.estado, let confirmado = estado.reciboConfirmadoEn,
              ahora.timeIntervalSince1970 * 1000 - confirmado > 90 * 86_400_000, !estado.copias.isEmpty else { return }
        for c in estado.copias { try? FileManager.default.removeItem(at: entorno.carpeta.appendingPathComponent(c)) }
        estado.copias = []
        try? a.guardar(estado, "estado.json")
    }
}
