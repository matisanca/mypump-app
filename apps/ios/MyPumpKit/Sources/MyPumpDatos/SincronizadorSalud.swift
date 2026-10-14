import Foundation
import MyPumpModelos
import MyPumpReglas

/// La sincronización de Apple Health, igual que `window.MyPumpHealth` (healthkit-bridge.js:241-1378):
///
/// - `conectar`: permisos en dos tandas (núcleo y resto, de a uno si la tanda falla), nunca escritura; después los
///   últimos 7 días y el historial de 60 de fondo.
/// - `sincronizar`: los últimos 7 días (al abrir, al volver y con el botón), en lotes de 300 a `ingest_salud` y de 200
///   a `ingest_entrenos`.
/// - `historial`: 60 días en ventanas de 5 con cursor; se retoma si se cortó, con un reintento cada 6 h si no avanza.
/// - "No llega nada" se deduce de los datos: 3 sincronizaciones vacías seguidas, o 60 días sin una muestra.
///
/// Todo el estado vive en `AlmacenSalud` con las claves de la web. Corre en el actor principal como el bridge en el
/// hilo de JS: la sincronización y el historial se pueden intercalar en cada espera, igual que allá.
@MainActor
public final class SincronizadorSalud {
    public let fuente: any FuenteSalud
    let cliente: ClienteRPC
    let token: String
    let almacen: any AlmacenSalud
    let ahora: @Sendable () -> Date
    public let reloj: RelojLocal
    let recolector: RecolectorSalud

    /// Avance del historial en curso ("Trayendo tu historial… 40/60 días"); nil si no hay uno corriendo.
    public private(set) var progresoHistorial: (hecho: Int, total: Int)? {
        didSet { alCambiarProgreso?(progresoHistorial) }
    }
    /// Cada cambio del avance, el 0/60 del arranque y el nil del final incluidos (para la card).
    public var alCambiarProgreso: (@MainActor ((hecho: Int, total: Int)?) -> Void)?
    /// El historial de fondo en vuelo (`backfillEnCurso()`).
    public private(set) var historialEnCurso: Task<ResultadoHistorial, Never>?
    /// El último rechazo de la base (lo muestra el diagnóstico).
    public private(set) var ultimoErrorIngesta: String?
    /// Hay datos nuevos en la base: la web repinta las cards (`loadSalud` + `loadRecuperacion`).
    public var alCambiar: (@MainActor () -> Void)?
    /// Cada ventana del historial que termina (`onProgreso`).
    public var alProgresar: (@MainActor (Int, Int) -> Void)?
    private var silencio = false

    public static let alcance = 60
    static let esperaReintento: Double = 6 * 60 * 60 * 1000

    /// Desvío a propósito de la web (bug encontrado el 14-oct): la última ventana del historial lee la noche de hoy
    /// solo hasta la medianoche y la mandaba igual, pisando el sueño completo que había subido la sincronización de 7
    /// días (470 → 89 minutos en el caso `conectar-primera-vez`) hasta la próxima sincronización. Con esto, en el
    /// historial se descartan las filas con fecha igual o posterior al cierre de cada ventana (en las ventanas del medio
    /// también, pero esas las vuelve a mandar completas la ventana siguiente). Los vectores de la web lo apagan.
    let descartarNochesPartidas: Bool

    public init(fuente: any FuenteSalud, cliente: ClienteRPC, token: String, almacen: any AlmacenSalud,
                ahora: @escaping @Sendable () -> Date = { Date() }, zona: TimeZone = .current, descartarNochesPartidas: Bool = true) {
        self.descartarNochesPartidas = descartarNochesPartidas
        self.fuente = fuente; self.cliente = cliente; self.token = token; self.almacen = almacen; self.ahora = ahora
        reloj = RelojLocal(zona: zona)
        recolector = RecolectorSalud(fuente: fuente, reloj: reloj)
    }

    // MARK: - Estado

    public var conectado: Bool { almacen.leer(ClaveSalud.conectado) == "1" }
    /// "No llega nada": una sospecha por falta de datos, no un veredicto de HealthKit (que nunca lo da).
    public var sinDatos: Bool { almacen.leer(ClaveSalud.denegado) == "1" }
    public var ultimaSync: String? { almacen.leer(ClaveSalud.ultimaSync) }
    public var historialHecho: Bool { almacen.leer(ClaveSalud.historialHecho) == "1" }

    var ms: Double { RelojLocal.ms(ahora()) }

    private func refrescar() { if !silencio { alCambiar?() } }
    private func marcarSync() { almacen.escribir(ClaveSalud.ultimaSync, RelojLocal.iso(ms)) }

    /// `registrarCosecha`: se cuenta lo que entregó HealthKit, NO lo que aceptó el servidor (un problema de red no es
    /// falta de permiso). Un iPhone siempre tiene pasos: tres veces nada de nada es permiso denegado.
    private func registrarCosecha(_ n: Int) {
        if n > 0 {
            almacen.escribir(ClaveSalud.rachaVacia, "0")
            almacen.escribir(ClaveSalud.denegado, nil)
            return
        }
        let r = (Self.parseInt(almacen.leer(ClaveSalud.rachaVacia)) ?? 0) + 1
        almacen.escribir(ClaveSalud.rachaVacia, String(r))
        if r >= 3 { almacen.escribir(ClaveSalud.denegado, "1") }
    }

    // MARK: - Envío

    /// `postearDetalle`: lotes de 300. Un lote rechazado (o sin red) cuenta y guarda su texto.
    func postear(_ registros: [RegistroSalud]) async -> (ok: Int, rechazados: Int, error: String?) {
        var ok = 0, rechazados = 0
        var error: String?
        for i in stride(from: 0, to: registros.count, by: PuenteSalud.loteSalud) {
            let lote = registros[i..<min(i + PuenteSalud.loteSalud, registros.count)]
            let r = await cliente.llamar("mypump_ingest_salud", ["p_token": .texto(token), "p_registros": .lista(lote.map(\.json))])
            switch r {
            case .success(let j): ok += Self.numeroJS(j)
            case .failure(let e):
                rechazados += 1
                error = e.mensaje.isEmpty ? "error desconocido" : e.mensaje
                ultimoErrorIngesta = error
            }
        }
        return (ok, rechazados, error)
    }

    /// `postearEntrenos`: lotes de 200 (la base no acepta más de 500).
    func postearEntrenos(_ entrenos: [EntrenoSalud]) async -> Int {
        var ok = 0
        for i in stride(from: 0, to: entrenos.count, by: PuenteSalud.loteEntrenos) {
            let lote = entrenos[i..<min(i + PuenteSalud.loteEntrenos, entrenos.count)]
            if case .success(let j) = await cliente.llamar("mypump_ingest_entrenos", ["p_token": .texto(token), "p_entrenos": .lista(lote.map(\.json))]) {
                ok += Self.numeroJS(j)
            }
        }
        return ok
    }

    // MARK: - Sincronizar (7 días)

    /// `sync()`: los últimos 7 días desde la medianoche (el día del borde entero) hasta ahora.
    @discardableResult
    public func sincronizar() async -> ResultadoSync {
        ultimoErrorIngesta = nil
        let hasta = ms, desde = reloj.medianoche(haceDias: 7, desde: hasta)
        let registros = await recolector.recolectar(desde: desde, hasta: hasta, iosMayor: fuente.iosMayor)
        registrarCosecha(registros.count)
        let envio = registros.isEmpty ? (ok: 0, rechazados: 0, error: nil) : await postear(registros)
        // Los entrenos van por su propia vía: si fallan, lo diario ya quedó guardado.
        let nEnt = await postearEntrenos(await recolector.entrenos(desde: desde, hasta: hasta))
        marcarSync()
        refrescar()
        return ResultadoSync(ok: true, motivo: nil, ingresados: envio.ok, entrenos: nEnt, errorIngesta: envio.error)
    }

    // MARK: - Historial (60 días)

    struct Cursor: Equatable { let off: Int; let alcance: Int? }

    /// `_cursorGuardado()`: `{"off":20,"alcance":60}` o el formato viejo (solo el número, alcance 60).
    func cursorGuardado() -> Cursor? {
        guard let raw = almacen.leer(ClaveSalud.cursor), !raw.isEmpty else { return nil }
        if raw.hasPrefix("{") {
            guard let j = try? JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)) else { return nil }
            let off = j["off"]?.comoNumero ?? 0
            guard off > 0 else { return nil }
            return Cursor(off: off.enteroTruncado, alcance: j["alcance"]?.comoNumero.map(\.enteroTruncado))
        }
        guard let v = Self.parseInt(raw), v > 0, v <= 60 else { return nil }
        return Cursor(off: v, alcance: 60)
    }

    func guardarCursor(_ off: Int, _ alcance: Int) {
        almacen.escribir(ClaveSalud.cursor, "{\"off\":\(off),\"alcance\":\(alcance)}")
    }

    /// `backfill()`: una sola vez (hasta que quede hecho). El motor no da score con menos de 14 días de historia: con
    /// esto el cliente ve su score el primer día.
    public func historial() async -> ResultadoHistorial {
        if historialHecho { return ResultadoHistorial(ok: true, saltado: true, ingresados: 0, ventanasFallidas: 0, sinDatos: sinDatos) }
        defer { progresoHistorial = nil }   // si quedara colgado, la card diría "25/60" para siempre
        var total = 0, cosechados = 0, ventanas = 0, fallaron = 0
        let alcance = Self.alcance
        let cur = cursorGuardado()
        let desdeOff = (cur.flatMap(\.alcance).map { $0 >= alcance } ?? false) ? min(cur!.off, alcance) : alcance
        progresoHistorial = (alcance - desdeOff, alcance)
        var off = desdeOff
        while off > 0 {
            // Las dos puntas a medianoche: si no, el día de cada costura sale partido en dos.
            let ahora = ms
            let hasta = reloj.medianoche(haceDias: off - 5, desde: ahora)
            let desde = reloj.medianoche(haceDias: off, desde: ahora)
            ventanas += 1
            var regs = await recolector.recolectar(desde: desde, hasta: hasta, iosMayor: fuente.iosMayor)
            cosechados += regs.count
            if descartarNochesPartidas {
                let corte = reloj.ymd(hasta)
                regs.removeAll { $0.fecha >= corte }
            }
            let envio = await postear(regs)
            total += envio.ok
            // Una ventana con lotes rechazados es una ventana fallida (si no, sin señal quedaba "completo" sin nada).
            if envio.rechazados > 0 { fallaron += 1 }
            _ = await postearEntrenos(await recolector.entrenos(desde: desde, hasta: hasta))
            progresoHistorial = (alcance - off + 5, alcance)
            guardarCursor(off - 5, alcance)
            alProgresar?(alcance - off + 5, alcance)
            off -= 5
        }
        // Las 12 ventanas sin una muestra: "no llega nada" de una, salvo que no se haya podido mirar.
        let todoFallo = fallaron == ventanas
        let nadaEntro = cosechados > 0 && total == 0
        if cosechados == 0 && !todoFallo { almacen.escribir(ClaveSalud.denegado, "1") }
        // Se marca hecho solo si al menos una ventana anduvo y entró algo. El orden de las ramas es el de la web: si se
        // leyó y no entró nada, el cursor queda (en 0) aunque hayan fallado todas.
        if !todoFallo && !nadaEntro {
            almacen.escribir(ClaveSalud.historialHecho, "1")
            almacen.escribir(ClaveSalud.cursor, nil)
        } else if nadaEntro {
            // no se marca hecho: se reintenta
        } else {
            almacen.escribir(ClaveSalud.cursor, nil)
        }
        refrescar()
        return ResultadoHistorial(ok: !todoFallo, saltado: false, ingresados: total, ventanasFallidas: fallaron, sinDatos: sinDatos)
    }

    /// `_retomarBackfillSiFalta()`: al abrir y al volver. Si un historial se cortó (la app se cerró a mitad), sigue desde
    /// el cursor; si no avanza (todo falla), espera 6 h para no repetir 12 ventanas en cada vuelta a la app.
    public func retomarHistorialSiFalta() {
        guard conectado, historialEnCurso == nil, !historialHecho else { return }
        let ultimo = Double(Self.parseInt(almacen.leer(ClaveSalud.intento) ?? "0") ?? 0)
        guard ms - ultimo >= Self.esperaReintento else { return }
        let antes = cursorGuardado()
        let mio = UUID()
        slot = mio
        historialEnCurso = Task { [weak self] in
            guard let self else { return ResultadoHistorial(ok: false, saltado: false, ingresados: 0, ventanasFallidas: 0, sinDatos: false) }
            let r = await self.historial()
            // El sello de las 6 h se pone solo si no avanzó: si avanzó, la próxima vuelta tiene que poder seguir.
            let avanzo = self.normalizado(self.cursorGuardado()) != self.normalizado(antes)
            if !avanzo && !self.historialHecho { self.almacen.escribir(ClaveSalud.intento, String(Int(self.ms))) }
            self.liberar(mio)
            return r
        }
    }

    /// Quién tiene el historial en curso (para no pisar el slot de otro al terminar).
    private var slot: UUID?
    private func liberar(_ id: UUID) {
        guard slot == id else { return }
        slot = nil
        historialEnCurso = nil
    }

    private func normalizado(_ c: Cursor?) -> String { c.map { "\($0.off)|\($0.alcance.map(String.init) ?? "-")" } ?? "null" }

    // MARK: - Conectar

    /// `connect()`: espera los permisos y los 7 días; el historial sale de fondo (en un iPhone con años de historia son
    /// minutos, y la app no se puede quedar congelada esperándolo).
    public func conectar(esperarHistorial: Bool = false) async -> ResultadoConexion {
        guard await fuente.disponible() else {
            anotarIntento(["paso": .texto("isAvailable"), "motivo": .texto("no_disponible"), "error": .null])
            return ResultadoConexion(ok: false, motivo: "no_disponible", detalle: nil, preguntados: nil, total: 0, sinDatos: sinDatos,
                                     rechazados: [], historial: nil)
        }
        let p = await pedirPermisos()
        guard p.ok else {
            anotarIntento(["paso": .texto("permiso"), "motivo": .texto(p.motivo ?? ""), "error": p.detalle.map(JSONValue.texto) ?? .null])
            return ResultadoConexion(ok: false, motivo: p.motivo, detalle: p.detalle, preguntados: nil, total: 0, sinDatos: sinDatos,
                                     rechazados: [], historial: nil)
        }
        anotarIntento([
            "paso": .texto("ok"), "preguntados": p.preguntados.map { .numero(Double($0)) } ?? .null, "total": .numero(Double(p.total)),
            "errEstado": p.errorEstado.map(JSONValue.texto) ?? .null,
            "rechazados": p.rechazados.isEmpty ? .null
                : .lista(p.rechazados.map { .objeto(["tipo": .texto($0.tipo), "error": .texto($0.error)]) }),
        ])
        // Se reinicia la RACHA, no el veredicto: "Reintentar" no apaga el cartel sin haber leído una muestra.
        almacen.escribir(ClaveSalud.rachaVacia, "0")
        almacen.escribir(ClaveSalud.conectado, "1")
        silencio = true
        await sincronizar()
        marcarSync()
        silencio = false
        refrescar()
        // El slot se reserva antes de soltar el hilo: un "volver a la app" en el medio no larga un segundo historial.
        let mio = UUID()
        slot = mio
        let tarea = Task { [weak self] () -> ResultadoHistorial in
            guard let self else { return ResultadoHistorial(ok: false, saltado: false, ingresados: 0, ventanasFallidas: 0, sinDatos: false) }
            var r = await self.historial()
            r.sinDatos = self.sinDatos
            self.liberar(mio)
            return r
        }
        historialEnCurso = tarea
        if esperarHistorial { _ = await tarea.value }
        return ResultadoConexion(ok: true, motivo: nil, detalle: nil, preguntados: p.preguntados, total: p.total, sinDatos: sinDatos,
                                 rechazados: p.rechazados, historial: tarea)
    }

    struct Permisos {
        let ok: Bool
        var motivo: String?
        var detalle: String?
        var preguntados: Int?
        var total = 0
        var errorEstado: String?
        var rechazados: [(tipo: String, error: String)] = []
    }

    /// `requestPermission()`: primero el núcleo (existe desde iOS 8: la hoja aparece sí o sí); si falla, lo mínimo
    /// (pasos y sueño). Después el resto en otra tanda que puede fallar sin arrastrar a la primera; si falla en bloque,
    /// de a uno: que se pierda un tipo es aceptable, que se lleve puestos a los otros doce, no.
    func pedirPermisos() async -> Permisos {
        do {
            try await fuente.pedirLectura(PuenteSalud.nucleo)
        } catch {
            do { try await fuente.pedirLectura(["steps", "sleep"]) }
            catch { return Permisos(ok: false, motivo: "error_nativo", detalle: "\(error)") }
        }
        let resto = PuenteSalud.resto(iosMayor: fuente.iosMayor)
        var rechazados: [(tipo: String, error: String)] = []
        if !resto.isEmpty {
            do { try await fuente.pedirLectura(resto) } catch {
                for t in resto {
                    do { try await fuente.pedirLectura([t]) } catch { rechazados.append((t, "\(error)")) }
                }
            }
        }
        // En HealthKit "listo" significa "se mostró la hoja", no "me dieron permiso": de acá solo sale cuántos se
        // preguntaron.
        let est = await estadoPermisos()
        return Permisos(ok: true, preguntados: est.preguntados, total: est.total, errorEstado: est.error, rechazados: rechazados)
    }

    /// `estadoPermisos()`.
    func estadoPermisos() async -> (preguntados: Int?, total: Int, pendientes: [String], error: String?) {
        let tipos = PuenteSalud.tiposLectura(iosMayor: fuente.iosMayor)
        do {
            let r = try await fuente.permisos(tipos)
            return (r.preguntados.count, tipos.count, r.pendientes, nil)
        } catch {
            return (nil, tipos.count, [], "\(error)")
        }
    }

    /// `disconnect()`: solo local. Lo ya subido queda (es del cliente y el coach lo usa).
    public func desconectar() {
        almacen.escribir(ClaveSalud.conectado, nil)
        almacen.escribir(ClaveSalud.ultimaSync, nil)
        almacen.escribir(ClaveSalud.historialHecho, nil)
    }

    /// `estado()`.
    public func estado() async -> EstadoSalud {
        let disponible = await fuente.disponible()
        let est = disponible ? await estadoPermisos() : (nil, 0, [], nil)
        return EstadoSalud(disponible: disponible, conectado: conectado, sinDatos: sinDatos, preguntados: est.0, total: est.1,
                           pendientes: est.2, errorEstado: est.3, ultimaSync: ultimaSync, ios: fuente.iosMayor)
    }

    /// El rastro del último intento de conectar (queda en el teléfono y lo muestra el diagnóstico).
    private func anotarIntento(_ datos: [String: JSONValue]) {
        var o: [String: JSONValue] = ["cuando": .texto(RelojLocal.iso(ms)), "ios": .numero(Double(fuente.iosMayor)), "nativo": .bool(true),
                                      "plugin": .bool(true)]
        for (k, v) in datos { o[k] = v }
        if let d = try? JSONEncoder().encode(JSONValue.objeto(o)) { almacen.escribir(ClaveSalud.diag, String(decoding: d, as: UTF8.self)) }
    }

    public var ultimoIntento: JSONValue? {
        almacen.leer(ClaveSalud.diag).flatMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }

    // MARK: - Diagnóstico

    /// `diagnostico()`: 14 días de cada tipo por su camino, y el sueño por noche y por fuente (lo que decide si la
    /// elección de fuente está bien para los datos reales de este cliente).
    public func diagnostico() async -> DiagnosticoSalud {
        let errores = RecolectorSalud.Errores()
        let disponible = await fuente.disponible()
        guard disponible else {
            return DiagnosticoSalud(disponible: false, conToken: !token.isEmpty, errorIngesta: ultimoErrorIngesta, tipos: [], noches: [], errores: [])
        }
        let hasta = ms, desde = reloj.medianoche(haceDias: 14, desde: hasta)
        var tipos: [DiagnosticoSalud.Tipo] = []
        for a in PuenteSalud.agregados {
            do {
                let s = try await fuente.agregado(a.dataType, agregacion: a.agregacion, desde: desde, hasta: hasta)
                tipos.append(.init(tipo: a.tipo, dataType: a.dataType, via: "aggregated", n: s.count, primero: s.first.map { reloj.ymd($0.inicio) },
                                   ultimo: s.last.map { reloj.ymd($0.inicio) }, error: nil))
            } catch {
                tipos.append(.init(tipo: a.tipo, dataType: a.dataType, via: "aggregated", n: 0, primero: nil, ultimo: nil, error: "\(error)"))
            }
        }
        let todos = PuenteSalud.muestras.map { ($0.dataType, $0.tipo) } + [("heartRateVariability", "hrv_ms")]
        for (dataType, tipo) in todos {
            let ms = await recolector.leer(dataType, desde: desde, hasta: hasta, errores: errores)
            tipos.append(.init(tipo: tipo, dataType: dataType, via: "samples", n: ms.count, primero: ms.first.map { reloj.ymd($0.inicio) },
                               ultimo: ms.last.map { reloj.ymd($0.inicio) }, error: nil))
        }
        var porNoche: [String: [String: [String: Double]]] = [:]
        for s in await recolector.leer("sleep", desde: desde, hasta: hasta, errores: errores) {
            let k = reloj.ymd(s.fin)
            let src = !s.fuenteNombre.isEmpty ? s.fuenteNombre : (!s.fuenteId.isEmpty ? s.fuenteId : "?")
            let st = s.estadoSueno?.lowercased() ?? "asleep"
            porNoche[k, default: [:]][src, default: [:]][st, default: 0] = jsRound((porNoche[k]?[src]?[st] ?? 0) + (s.fin - s.inicio) / 60_000)
        }
        let noches = porNoche.keys.sorted().map { f in
            DiagnosticoSalud.NocheFuente(fecha: f, fuentes: (porNoche[f] ?? [:]).mapValues { $0.mapValues(\.enteroTruncado) })
        }
        return DiagnosticoSalud(disponible: true, conToken: !token.isEmpty, errorIngesta: ultimoErrorIngesta, tipos: tipos, noches: noches,
                                errores: errores.todos)
    }

    // MARK: - Ayudas de JS

    /// `parseInt(x, 10)`: el entero del principio (con espacios y signo), o nil (NaN).
    static func parseInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        var t = Substring(s.drop { $0 == " " || $0 == "\t" || $0 == "\n" })
        var signo = 1
        if t.first == "-" { signo = -1; t = t.dropFirst() } else if t.first == "+" { t = t.dropFirst() }
        let digitos = t.prefix { $0.isASCII && $0.isNumber }
        guard !digitos.isEmpty, let n = Int(digitos) else { return nil }
        return signo * n
    }

    /// `Number(r.data) || 0`.
    static func numeroJS(_ j: JSONValue) -> Int {
        switch j {
        case .numero(let d): return d.enteroTruncado
        case .texto(let s): return (Double(JS.trim(s)) ?? 0).enteroTruncado
        case .bool(let b): return b ? 1 : 0
        default: return 0
        }
    }
}
