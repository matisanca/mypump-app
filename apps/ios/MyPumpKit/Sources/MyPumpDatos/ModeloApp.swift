import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// El estado de la app del cliente: quién es, su plan y lo que fue haciendo, con la cola de escrituras detrás. Hace lo
/// mismo que `init()` de cliente.html (8667-8918), en este orden: info → rutina y dieta → copia offline → hidratar →
/// drenar la cola.
@MainActor @Observable
public final class ModeloApp {
    public enum Fase: Equatable, Sendable {
        case sinToken          // "Bienvenido a MyPump": pegá tu link o mirá la demo
        case cargando
        case listo
        case tokenInvalido     // "Este link ya no sirve"
        case sinServicio       // sin red y sin copia offline
    }

    public private(set) var fase: Fase
    public private(set) var info: ClienteInfo?
    public private(set) var rutina: RutinaActiva?
    public private(set) var dieta: DietaActiva?
    /// Lo cargado vino de la copia offline (banner "sin conexión").
    public private(set) var desdeCache = false
    /// Demo ("Ver demo", la que mira App Review): datos de la web empaquetados, sin red ni token, nada se escribe.
    public private(set) var esDemo = false
    public private(set) var estadoGuardado: EstadoGuardado = .quieto

    // Dieta
    public private(set) var excluir: [String] = []
    public private(set) var alimentosPropios: [AlimentoPropio] = []
    public private(set) var swaps: [String: SwapLocal] = [:]
    /// Comidas libres (fuera del plan) del día local.
    public private(set) var comidasLibres: [ComidaLibre] = []
    /// El chat con Mati (no existe en la demo ni sin cuenta).
    public private(set) var chat: ModeloChat?
    /// El tipo de día elegido (entreno/descanso) en dietas con `tipos_dia`. Es global en la web (`mypump_tipo_dia`).
    public var tipoDia: String? {
        didSet { UserDefaults.standard.set(tipoDia, forKey: "mypump_tipo_dia") }
    }

    @ObservationIgnored public let cliente: ClienteRPC
    @ObservationIgnored let almacen: AlmacenToken
    @ObservationIgnored public private(set) var token: String?
    @ObservationIgnored var disco: Disco?
    @ObservationIgnored public private(set) var outbox: Outbox?
    @ObservationIgnored let raizDisco: URL?

    public init(cliente: ClienteRPC = ClienteRPC(), almacen: AlmacenToken = TokenEnKeychain(), raizDisco: URL? = nil) {
        self.cliente = cliente
        self.almacen = almacen
        self.raizDisco = raizDisco
        token = almacen.leer()
        fase = token == nil ? .sinToken : .cargando
        tipoDia = UserDefaults.standard.string(forKey: "mypump_tipo_dia")
        if let token { prepararCuenta(token) }
    }

    // MARK: - Acceso

    /// Lo que pegó o abrió el cliente (link entero, a medias o el token solo).
    @discardableResult
    public func entrar(con texto: String) async -> Bool {
        guard let t = FormatoToken.extraer(de: texto) else { return false }
        // Un link viejo que ya se sabe inválido no pisa una cuenta que anda (ACC-02): pasa al tocar un link de
        // WhatsApp de hace meses.
        if t != token, t == UserDefaults.standard.string(forKey: "mypump_token_invalido"), token != nil, fase == .listo, !esDemo {
            return false
        }
        if t == token, fase == .listo { return true }
        esDemo = false
        almacen.guardar(t)
        token = t
        prepararCuenta(t)
        fase = .cargando
        await cargar()
        return fase == .listo
    }

    public func salir() {
        almacen.guardar(nil)
        token = nil
        disco = nil
        outbox = nil
        info = nil; rutina = nil; dieta = nil; swaps = [:]; comidasLibres = []; alimentosPropios = []; excluir = []
        chat?.pararSondeo(); chat = nil
        esDemo = false
        fase = .sinToken
    }

    /// "Ver demo": la rutina y la dieta de ejemplo de la web (`SAMPLE_RUTINA` / `SAMPLE_DIET`, que la app trae
    /// empaquetadas), sin cuenta. No toca la red ni escribe nada; los reemplazos viven en memoria.
    public func entrarEnDemo(rutina: Data, dieta: Data) {
        func envolver(_ estructura: Data, id: String) -> Data? {
            guard let e = try? JSONDecoder().decode(JSONValue.self, from: estructura) else { return nil }
            return try? JSONEncoder().encode(JSONValue.objeto(["id": .texto(id), "version": .numero(1), "estructura": e,
                                                               "semana_actual": .numero(1)]))
        }
        self.rutina = envolver(rutina, id: "demo").flatMap { try? JSONDecoder().decode(RutinaActiva.self, from: $0) }
        self.dieta = envolver(dieta, id: "demo").flatMap { try? JSONDecoder().decode(DietaActiva.self, from: $0) }
        info = nil; swaps = [:]; comidasLibres = []; alimentosPropios = []; excluir = []
        desdeCache = false
        esDemo = true
        fase = .listo
    }

    /// Salir de la demo vuelve a la bienvenida (o a la cuenta, si había una guardada).
    public func salirDeDemo() async {
        esDemo = false
        rutina = nil; dieta = nil; swaps = [:]
        if token != nil { fase = .cargando; await cargar() } else { fase = .sinToken }
    }

    private func prepararCuenta(_ t: String) {
        let disco = Disco(raiz: raizDisco, token: t)
        self.disco = disco
        let escrituras = Escrituras(cliente: cliente, token: t)
        let cola = Outbox(archivo: disco.url("outbox.json")) { op in await escrituras.ejecutar(op) }
        outbox = cola
        chat?.pararSondeo()   // al cambiar de cuenta, el sondeo de la anterior no sigue
        chat = ModeloChat(cliente: cliente, token: t, outbox: cola)
        Task { [weak self] in
            await cola.observar(estado: { e in Task { @MainActor in self?.estadoGuardado = e } },
                                abandonadas: { ops in Task { @MainActor in self?.alAbandonar(ops) } })
        }
    }

    /// Lo que la cola abandonó (va a fallidos, no se borra). Un mensaje del chat se marca en su burbuja para
    /// reintentarlo ("no salió → Reintentar"), como `marcarChatFallido` de la web.
    private func alAbandonar(_ ops: [Operacion]) {
        for op in ops where op.kind == "chat" {
            if let texto = op.payload["contenido"]?.comoTexto { chat?.marcarFallido(contenido: texto) }
        }
    }

    // MARK: - Carga

    struct CopiaOffline: Codable {
        var info: JSONValue
        var rutina: JSONValue?
        var dieta: JSONValue?
        var ts: Double
    }

    public func cargar() async {
        if esDemo { return }   // la demo no toca la red (y "tirar para actualizar" no la cierra)
        guard let t = token else { fase = .sinToken; return }
        let p: [String: JSONValue] = ["p_token": .texto(t)]

        let respuestaInfo: JSONValue
        switch await cliente.llamar("mypump_get_cliente_info", p) {
        case .failure:
            // Sin red o servicio caído: la copia offline, si hay.
            if let copia = disco?.leer(CopiaOffline.self, "offline.json") {
                aplicar(copia)
                desdeCache = true
                fase = .listo
            } else {
                fase = .sinServicio
            }
            return
        case .success(let j):
            respuestaInfo = j
        }
        // `[]` sin error = token inválido o revocado (la base no tira error: devuelve vacío).
        guard case .lista(let filas) = respuestaInfo, let primera = filas.first else {
            almacen.guardar(nil)
            UserDefaults.standard.set(t, forKey: "mypump_token_invalido")
            fase = .tokenInvalido
            return
        }
        info = decodificar(ClienteInfo.self, primera)

        async let r = cliente.llamar("mypump_get_rutina_activa", p)
        async let d = cliente.llamar("mypump_get_dieta_activa", p)
        let (rr, dd) = await (r, d)
        let rutinaJSON = try? rr.get().primeraFila
        let dietaJSON = try? dd.get().primeraFila
        rutina = rutinaJSON.flatMap { decodificar(RutinaActiva.self, $0) }
        dieta = dietaJSON.flatMap { decodificar(DietaActiva.self, $0) }
        if rutinaJSON != nil || dietaJSON != nil {
            disco?.guardar(CopiaOffline(info: primera, rutina: rutinaJSON, dieta: dietaJSON, ts: Date().timeIntervalSince1970 * 1000), "offline.json")
        }
        desdeCache = false
        fase = .listo

        await hidratarDieta()
        await cargarComidasLibres()
        await outbox?.drenar()
        await chat?.cargar()
    }

    private func aplicar(_ c: CopiaOffline) {
        info = decodificar(ClienteInfo.self, c.info)
        rutina = c.rutina.flatMap { decodificar(RutinaActiva.self, $0) }
        dieta = c.dieta.flatMap { decodificar(DietaActiva.self, $0) }
        if let id = dieta?.id { swaps = disco?.leer([String: SwapLocal].self, "swaps_\(id).json") ?? [:] }
    }

    // MARK: - Dieta

    /// El plan que se está mirando: el tipo de día elegido o el primero; sin tipos de día, la dieta entera.
    public var comidasDelDia: [Comida] {
        guard let e = dieta?.estructura else { return [] }
        if e.tiposDia.isEmpty { return e.comidas }
        return (e.tiposDia.first { $0.id == tipoDia } ?? e.tiposDia[0]).comidas
    }

    /// Objetivo de macros del día. Sin `macros_target`, la suma de la opción A de cada comida (normalizarDieta).
    public var objetivo: Macros {
        guard let e = dieta?.estructura else { return Macros() }
        let tipo = e.tiposDia.first { $0.id == tipoDia } ?? e.tiposDia.first
        if let m = tipo?.macrosTarget ?? e.macrosTarget, m.kcal != nil { return m }
        return Self.sumar(comidasDelDia.compactMap { $0.opciones.first }.flatMap(\.alimentos))
    }

    public static func sumar(_ a: [Alimento]) -> Macros {
        Macros(kcal: a.compactMap(\.kcal).reduce(0, +), prot: a.compactMap(\.prot).reduce(0, +),
               carb: a.compactMap(\.carb).reduce(0, +), fat: a.compactMap(\.fat).reduce(0, +))
    }

    public func clave(_ comidaId: String, _ opt: Int, _ idx: Int) -> String {
        SwapsDeComida.clave(dietaId: dieta?.id ?? "demo", comidaId: comidaId, optIdx: opt, foodIdx: idx)
    }

    /// Lo que se muestra en esa posición: el sustituto si el swap aplica (anclaje), si no el alimento del plan.
    public func efectivo(_ original: Alimento, comidaId: String, opt: Int, idx: Int) -> (alimento: Alimento, sustituido: Bool) {
        let e = dieta?.estructura ?? EstructuraDieta()
        return SwapsDeComida.efectivo(original, swap: swaps[clave(comidaId, opt, idx)], comidaId: comidaId) {
            SwapsDeComida.enPosicion(e, tipoActivo: tipoDia, comidaId: comidaId, optIdx: opt, foodIdx: idx)
        }
    }

    /// Confirmar un sustituto (`confirmSwap`): se guarda anclado y sale por la cola.
    public func sustituir(_ original: Alimento, por sustituto: JSONValue, comidaId: String, opt: Int, idx: Int) async {
        guard let dietaId = dieta?.id else { return }
        let k = clave(comidaId, opt, idx)
        let anclado = SwapsDeComida.conAncla(sustituto, original: original)
        swaps[k] = SwapLocal(original: try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(AlimentoJSON(original))), current: anclado)
        guardarSwaps()
        await outbox?.encolar("swap", .objeto(["dietaId": .texto(dietaId), "comidaId": .texto(comidaId), "optIdx": .numero(Double(opt)),
                                                "foodIdx": .numero(Double(idx)), "food": anclado]), dedupeKey: k)
    }

    /// Volver al alimento del plan. Comparte clave con el swap: si todavía no había salido, lo reemplaza en la cola.
    public func revertir(comidaId: String, opt: Int, idx: Int) async {
        guard let dietaId = dieta?.id else { return }
        let k = clave(comidaId, opt, idx)
        swaps[k] = nil
        guardarSwaps()
        await outbox?.encolar("swap_del", .objeto(["dietaId": .texto(dietaId), "comidaId": .texto(comidaId), "optIdx": .numero(Double(opt)),
                                                    "foodIdx": .numero(Double(idx))]), dedupeKey: k)
    }

    /// "Crear y usar" (`saveCustomFood`): va directo, no por la cola, como en la web. Lo creado entra a la base de
    /// sustitutos reemplazando al del mismo nombre. Sin cuenta (demo) queda solo en memoria. La función devuelve un
    /// conjunto vacío si el token no sirve: eso también es un error para el cliente.
    public func crearAlimentoPropio(_ d: AlimentoPropioNuevo.Datos) async -> Result<AlimentoPropio, ErrorRPC> {
        guard let t = token else {
            let a = AlimentoPropio(nombre: d.nombre, kcal: d.kcal, prot: d.prot, carb: d.carb, fat: d.fat, unidad: d.unidad,
                                   gramosPorUnidad: d.gramosPorUnidad, categoria: d.categoria)
            sumarPropio(a)
            return .success(a)
        }
        let p: [String: JSONValue] = [
            "p_token": .texto(t), "p_name": .texto(d.nombre), "p_kcal": .numero(d.kcal), "p_prot": .numero(d.prot),
            "p_carb": .numero(d.carb), "p_fat": .numero(d.fat), "p_unit": .texto(d.unidad),
            "p_unit_grams": d.gramosPorUnidad.map(JSONValue.numero) ?? .null,
            "p_category": d.categoria.isEmpty ? .null : .texto(d.categoria),
        ]
        switch await cliente.filas("mypump_create_custom_food", p, como: AlimentoPropio.self) {
        case .failure(let e):
            return .failure(e)
        case .success(let creados):
            guard let a = creados.first else {
                return .failure(ErrorRPC(clase: .permanente, status: 200, codigo: "SIN_FILA", mensaje: "mypump_create_custom_food: vacío"))
            }
            sumarPropio(a)
            return .success(a)
        }
    }

    // MARK: - Comidas libres

    /// `loadComidasLibres`: las del día local. Sin cuenta (demo) no hay.
    public func cargarComidasLibres() async {
        guard let t = token else { comidasLibres = []; return }
        if case .success(let filas) = await cliente.filas("mypump_get_comidas_libres", ["p_token": .texto(t), "p_fecha": .texto(FechaLocal.hoy())],
                                                          como: ComidaLibre.self) {
            comidasLibres = filas
        }
    }

    /// `guardarComidaLibre`: directo, no por la cola (como la web), con la fecha local.
    public func crearComidaLibre(_ d: ComidaLibreNueva.Datos) async -> Result<ComidaLibre, ErrorRPC> {
        guard let t = token else { return .failure(ErrorRPC(clase: .permanente, status: 0, codigo: "SIN_CUENTA", mensaje: "demo")) }
        let p: [String: JSONValue] = [
            "p_token": .texto(t), "p_fecha": .texto(FechaLocal.hoy()), "p_hora": d.hora.map(JSONValue.texto) ?? .null,
            "p_descripcion": .texto(d.descripcion), "p_kcal": .numero(d.kcal), "p_prot": .numero(d.prot),
            "p_carb": .numero(d.carb), "p_fat": .numero(d.fat), "p_detalle": d.detalle ?? .null,
        ]
        switch await cliente.filas("mypump_crear_comida_libre", p, como: ComidaLibre.self) {
        case .failure(let e):
            return .failure(e)
        case .success(let filas):
            guard let c = filas.first else {
                return .failure(ErrorRPC(clase: .permanente, status: 200, codigo: "SIN_FILA", mensaje: "mypump_crear_comida_libre: vacío"))
            }
            comidasLibres.append(c)
            return .success(c)
        }
    }

    /// `borrarComidaLibre`: optimista; si el servidor no contesta bien, vuelve a aparecer.
    @discardableResult
    public func borrarComidaLibre(_ id: String) async -> Bool {
        let previas = comidasLibres
        comidasLibres.removeAll { $0.id == id }
        guard let t = token else { return true }
        if case .failure = await cliente.llamar("mypump_borrar_comida_libre", ["p_token": .texto(t), "p_id": .texto(id)]) {
            comidasLibres = previas
            return false
        }
        return true
    }

    /// `visionDesdeFoto`: la foto (JPEG ya reducido) a mini-vision. Tarda ~30 s, hasta 150.
    public func analizarFoto(_ jpeg: Data, tipo: ClienteRPC.TipoVision) async -> Result<JSONValue, ErrorRPC> {
        guard let t = token else { return .failure(ErrorRPC(clase: .permanente, status: 0, codigo: "SIN_CUENTA", mensaje: "demo")) }
        return await cliente.vision(token: t, tipo: tipo, jpeg: jpeg)
    }

    /// Como la web: reemplaza en su lugar al del mismo nombre (sin distinguir mayúsculas) o se agrega al final.
    private func sumarPropio(_ a: AlimentoPropio) {
        if let i = alimentosPropios.firstIndex(where: { $0.nombre.lowercased() == a.nombre.lowercased() }) {
            alimentosPropios[i] = a
        } else {
            alimentosPropios.append(a)
        }
    }

    private func guardarSwaps() {
        guard let id = dieta?.id else { return }
        disco?.guardar(swaps, "swaps_\(id).json")
    }

    /// Preferencias, alimentos propios y swaps del servidor (hydrateSwapsAndCustomFoodsFromBackend).
    func hidratarDieta() async {
        guard let t = token, let dieta else { return }
        let p: [String: JSONValue] = ["p_token": .texto(t)]
        if case .success(let prefs) = await cliente.filas("mypump_get_cliente_prefs", p, como: PreferenciasCliente.self) {
            excluir = prefs.first?.excluir ?? []
        }
        if case .success(let propios) = await cliente.filas("mypump_get_custom_foods", p, como: AlimentoPropio.self) {
            alimentosPropios = propios
        }
        if swaps.isEmpty { swaps = disco?.leer([String: SwapLocal].self, "swaps_\(dieta.id).json") ?? [:] }

        let remotos: [FoodSwap]?
        switch await cliente.filas("mypump_get_food_swaps", ["p_token": .texto(t), "p_dieta_id": .texto(dieta.id)], como: FoodSwap.self) {
        case .success(let f): remotos = f
        case .failure: remotos = nil
        }
        let pendientes = (await outbox?.pendientesPorClave() ?? [:]).mapValues(\.kind)
        let marca = "swaps_migrados_\(dieta.id)"
        let yaMigrado = disco?.leer(Bool.self, marca) ?? false
        let e = dieta.estructura
        let tipo = tipoDia
        guard let h = SwapsDeComida.hidratar(remotos: remotos, locales: swaps, dietaId: dieta.id, pendientes: pendientes, yaMigrado: yaMigrado,
                                             enPosicion: { SwapsDeComida.enPosicion(e, tipoActivo: tipo, comidaId: $0, optIdx: $1, foodIdx: $2) })
        else { return }
        swaps = h.swaps
        guardarSwaps()
        for op in h.operaciones {
            var payload = op.payload
            if case .objeto(var o) = payload { o["dietaId"] = .texto(dieta.id); payload = .objeto(o) }
            await outbox?.encolar(op.kind, payload, dedupeKey: op.clave)
        }
        if h.migrando {
            await outbox?.drenar()
            let quedan = (await outbox?.pendientesPorClave() ?? [:]).keys.contains { $0.hasPrefix("swap_\(dieta.id)_") }
            if !quedan { disco?.guardar(true, marca) }
        } else if h.marcarMigrado {
            disco?.guardar(true, marca)
        }
    }

    private func decodificar<T: Decodable>(_ tipo: T.Type, _ j: JSONValue) -> T? {
        try? JSONDecoder().decode(T.self, from: JSONEncoder().encode(j))
    }
}

/// Un alimento del plan devuelto a JSON (el `original` que guarda la web junto al swap).
struct AlimentoJSON: Encodable {
    let a: Alimento
    init(_ a: Alimento) { self.a = a }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Clave.self)
        try c.encode(a.nombre, forKey: .name)
        try c.encodeIfPresent(a.qty, forKey: .qty)
        try c.encodeIfPresent(a.unidad, forKey: .unit)
        try c.encodeIfPresent(a.kcal, forKey: .kcal)
        try c.encodeIfPresent(a.prot, forKey: .prot)
        try c.encodeIfPresent(a.carb, forKey: .carb)
        try c.encodeIfPresent(a.fat, forKey: .fat)
        try c.encodeIfPresent(a.categoria, forKey: .category)
    }
    enum Clave: String, CodingKey { case name, qty, unit, kcal, prot, carb, fat, category }
}

extension JSONValue {
    /// `rows[0]` de una RPC que devuelve una tabla.
    var primeraFila: JSONValue? {
        if case .lista(let a) = self { return a.first }
        return nil
    }
}
