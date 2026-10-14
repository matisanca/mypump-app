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
    /// Lo que no llegó en la última carga por un corte (se muestra la copia guardada de eso, si había).
    public private(set) var sinRedEn: Set<Parte> = []
    /// Por qué no se pudo cargar (para decir "Sin conexión" o "Servicio fuera de línea").
    public private(set) var ultimaFalla: ErrorRPC.Clase?
    /// Lo pone la raíz con el `scenePhase`: los sondeos solo corren con la app a la vista.
    public var enPrimerPlano = true {
        didSet { if enPrimerPlano && fase != .tokenInvalido && !esDemo { chat?.empezarSondeo() } else { chat?.pararSondeo() } }
    }

    public enum Parte: Sendable, Hashable { case rutina, dieta }

    /// Lo que le falta a la dieta publicada (`normalizarDieta`): para el aviso "a tu plan le falta información".
    public private(set) var problemasDieta: [String] = []
    public private(set) var estadoGuardado: EstadoGuardado = .quieto

    // Dieta
    public private(set) var excluir: [String] = []
    public private(set) var alimentosPropios: [AlimentoPropio] = []
    public private(set) var swaps: [String: SwapLocal] = [:]
    /// La palanca remota (G2). Se lee en cada carga; sin la tabla o sin red queda la de fábrica (todo prendido).
    public private(set) var palanca = PalancaRemota.deFabrica

    // MARK: Permiso para la IA (D7, supabase/migrations/nativa_002)

    /// Qué decidió el cliente: true acepta, false "sin IA", nil nunca se le preguntó (o todavía no se sabe).
    public private(set) var consentimientoIA: Bool?
    /// Cuántas cargas terminaron con todo traído del servidor. `cargar()` sobre una cuenta ya cargada no pasa por
    /// `.cargando`: quien espera "la próxima carga con red" (la Fase R después de un corte) mira esto.
    public private(set) var cargasConRed = 0
    /// El servidor puede guardar la decisión. Sin eso (PGRST202) no se pregunta: un "no" no se podría respetar del otro
    /// lado, y todo sigue como hoy.
    public private(set) var consentimientoIADisponible = false
    /// Antes del primer mensaje, de la primera foto analizada y del primer check hay que preguntar (Apple 5.1.2(i)).
    public var faltaConsentimientoIA: Bool { consentimientoIADisponible && consentimientoIA == nil && !esDemo && token != nil }
    /// La foto del plato o de la etiqueta se puede mandar a la IA: aceptó, o el servidor todavía no sabe de permisos.
    public var analisisDeFotoPermitido: Bool { !consentimientoIADisponible || consentimientoIA == true }
    /// Comidas libres (fuera del plan) del día local.
    public private(set) var comidasLibres: [ComidaLibre] = []
    /// El chat con Mati (no existe en la demo ni sin cuenta).
    public private(set) var chat: ModeloChat?
    /// Revisión y Mi Día (no existen en la demo ni sin cuenta).
    public private(set) var revision: ModeloRevision?
    /// Fotos de progreso, con su cola propia en disco.
    public private(set) var fotos: ModeloFotos?
    /// Progreso: se carga al abrir la pestaña (como la web).
    public private(set) var progreso: ModeloProgreso?
    /// El motor de Entreno de la rutina activa (también en la demo, donde no escribe nada).
    public private(set) var entreno: ModeloEntreno?
    /// El catálogo de ejercicios que trae la app (Bases.bundle): lo pone la app al arrancar. Se usa hasta que llega el
    /// del servidor, y para arrancar sin red si nunca llegó.
    public static var catalogoEmpaquetado = CatalogoEjercicios([])
    /// Salud, recuperación y Mi reloj (no existen en la demo ni sin cuenta). Gancho: se crea con la cuenta, arranca al
    /// terminar `cargar()` y sincroniza en `alVolverAPrimerPlano()`; HealthKit lo pone la app (ver ModeloSalud.swift).
    public private(set) var salud: ModeloSalud?
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
    /// El día local de la última carga completa: si al volver a la app cambió, se recarga lo que es "de hoy".
    @ObservationIgnored private var diaCargado: String?
    @ObservationIgnored private var catalogo: CatalogoEjercicios?

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
        // No depende de la fase: al abrir la app tocando el link, la cuenta guardada todavía está cargando.
        if t != token, t == UserDefaults.standard.string(forKey: "mypump_token_invalido"), token != nil, !esDemo {
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
        consentimientoIA = nil
        disco = nil
        outbox = nil
        info = nil; rutina = nil; dieta = nil; swaps = [:]; comidasLibres = []; alimentosPropios = []; excluir = []
        chat?.pararSondeo(); chat = nil; revision = nil; fotos = nil; progreso = nil; salud = nil; entreno = nil
        esDemo = false
        sinRedEn = []
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
        // La demo no escribe NADA: se suelta la cuenta en memoria (token, cola, chat…). El Keychain no se toca: si había
        // una cuenta guardada, "Salir" de la demo vuelve a ella.
        soltarCuentaEnMemoria()
        self.rutina = envolver(rutina, id: "demo").flatMap { try? JSONDecoder().decode(RutinaActiva.self, from: $0) }
        self.dieta = dietaNormalizada(envolver(dieta, id: "demo").flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) })
        desdeCache = false
        sinRedEn = []
        esDemo = true
        if let r = self.rutina {
            entreno = ModeloEntreno(cliente: cliente, token: nil, outbox: nil, disco: nil, rutina: r, catalogo: catalogoVigente)
        }
        fase = .listo
        if let e = entreno { Task { await e.cargar() } }
    }

    /// Salir de la demo vuelve a la bienvenida (o a la cuenta, si había una guardada).
    public func salirDeDemo() async {
        esDemo = false
        rutina = nil; dieta = nil; swaps = [:]; entreno = nil
        token = almacen.leer()
        if let t = token {
            prepararCuenta(t)
            fase = .cargando
            await cargar()
        } else {
            fase = .sinToken
        }
    }

    private func soltarCuentaEnMemoria() {
        token = nil
        consentimientoIA = nil
        disco = nil
        outbox = nil
        info = nil; swaps = [:]; comidasLibres = []; alimentosPropios = []; excluir = []
        chat?.pararSondeo(); chat = nil; revision = nil; fotos = nil; progreso = nil; salud = nil; entreno = nil
    }

    private func prepararCuenta(_ t: String) {
        let disco = Disco(raiz: raizDisco, token: t)
        self.disco = disco
        // El permiso para la IA es de cada cuenta: hasta que conteste la carga vale lo que ESTA cuenta decidió en el
        // teléfono (o nada). Antes seguía valiendo el de la cuenta anterior (lo encontró el gemelo de Android).
        consentimientoIA = disco.leer(ConsentimientoIA.Guardado.self, ConsentimientoIA.archivo)?.acepta
        let escrituras = Escrituras(cliente: cliente, token: t)
        let cola = Outbox(archivo: disco.url("outbox.json")) { op in await escrituras.ejecutar(op) }
        outbox = cola
        chat?.pararSondeo()   // al cambiar de cuenta, el sondeo de la anterior no sigue
        chat = ModeloChat(cliente: cliente, token: t, outbox: cola)
        if enPrimerPlano { chat?.empezarSondeo() }
        revision = ModeloRevision(cliente: cliente, token: t, outbox: cola)
        fotos = ModeloFotos(cliente: cliente, token: t, disco: disco)
        progreso = ModeloProgreso(cliente: cliente, token: t)
        salud = ModeloSalud(cliente: cliente, token: t)
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
        // Todo lo que sigue es de ESTE token: si mientras tanto entró otro (un link tocado al abrir la app), lo que vuelva
        // se descarta sin tocar nada (ni el Keychain ni la pantalla).
        func vigente() -> Bool { token == t && !esDemo }
        let p: [String: JSONValue] = ["p_token": .texto(t)]

        let respuestaInfo: JSONValue
        switch await cliente.llamar("mypump_get_cliente_info", p) {
        case .failure(let e):
            guard vigente() else { return }
            ultimaFalla = e.clase
            // Sin red o servicio caído: la copia offline, si hay.
            if let copia = disco?.leer(CopiaOffline.self, "offline.json") {
                aplicar(copia)
                desdeCache = true
                fase = .listo
                // Sin red igual se puede marcar el día (sale por la cola), como la web con `MYDAY` vacío. Sin esto
                // Mi Día quedaba tapado hasta que volviera la señal (revisión del 14-oct, hallazgo 10).
                if let revision { Task { await revision.cargarMiDia() } }
            } else {
                fase = .sinServicio
            }
            return
        case .success(let j):
            guard vigente() else { return }
            respuestaInfo = j
        }
        ultimaFalla = nil
        // `[]` sin error = token inválido o revocado (la base no tira error: devuelve vacío).
        guard case .lista(let filas) = respuestaInfo, let primera = filas.first else {
            if almacen.leer() == t { almacen.guardar(nil) }
            UserDefaults.standard.set(t, forKey: "mypump_token_invalido")
            chat?.pararSondeo()
            fase = .tokenInvalido
            return
        }
        info = decodificar(ClienteInfo.self, primera)

        async let r = cliente.llamar("mypump_get_rutina_activa", p)
        async let d = cliente.llamar("mypump_get_dieta_activa", p)
        async let cfg = PalancaRemota.leer(cliente)
        async let ci = cliente.llamar("mypump_get_consentimiento_ia", p)
        let (rr, dd, palancaLeida, consentimiento) = await (r, d, cfg, ci)
        guard vigente() else { return }
        if let palancaLeida { palanca = palancaLeida }
        await aplicarConsentimiento(consentimiento)
        // Un corte NO es "no tiene plan": lo que no llegó sale de la copia guardada (y la copia no se pisa con un hueco).
        // `null` o `[]` sin error sí es "no tiene" (Mati la desactivó).
        let copia = disco?.leer(CopiaOffline.self, "offline.json")
        var faltaron: Set<Parte> = []
        let rutinaJSON: JSONValue?
        switch rr {
        case .success(let j): rutinaJSON = j.primeraFila
        case .failure: rutinaJSON = copia?.rutina.flatMap { $0 == .null ? nil : $0 }; faltaron.insert(.rutina)
        }
        let dietaJSON: JSONValue?
        switch dd {
        case .success(let j): dietaJSON = j.primeraFila
        case .failure: dietaJSON = copia?.dieta.flatMap { $0 == .null ? nil : $0 }; faltaron.insert(.dieta)
        }
        rutina = rutinaJSON.flatMap { decodificar(RutinaActiva.self, $0) }
        dieta = dietaNormalizada(dietaJSON)
        if rutinaJSON != nil || dietaJSON != nil || copia != nil {
            disco?.guardar(CopiaOffline(info: primera, rutina: rutinaJSON, dieta: dietaJSON, ts: Date().timeIntervalSince1970 * 1000), "offline.json")
        }
        // Los reemplazos guardados en el teléfono, ANTES de mostrar Dieta (si no, se ven tarde y un reemplazo hecho en
        // ese hueco pisaba el archivo).
        if let id = dieta?.id { swaps = disco?.leer([String: SwapLocal].self, "swaps_\(id).json") ?? [:] } else { swaps = [:] }
        sinRedEn = faltaron
        desdeCache = !faltaron.isEmpty
        if !desdeCache { cargasConRed += 1 }
        prepararEntreno()
        fase = .listo
        if let e = entreno {
            Task {
                await self.cargarCatalogo()
                await e.aplicarLegadoDelDisco()   // la sesión en curso que trajo la migración, una vez
                await e.cargar()
            }
        }

        await hidratarDieta()
        guard vigente() else { return }
        await cargarComidasLibres()
        await outbox?.drenar()
        async let cargaChat: Void = chat?.cargar() ?? ()
        async let cargaMiDia: Void = revision?.cargarMiDia() ?? ()
        async let cargaRevision: Void = revision?.cargarRevision() ?? ()
        async let cargaFotos: Void = fotos?.cargar() ?? ()
        _ = await (cargaChat, cargaMiDia, cargaRevision, cargaFotos)
        await fotos?.drenar()
        diaCargado = FechaLocal.hoy()
        // Salud: sus lecturas, y con Apple Health conectada los 7 días y el historial pendiente (sin frenar la carga).
        if let salud { Task { await salud.alAbrir() } }
    }

    // MARK: - Entreno

    private var catalogoVigente: CatalogoEjercicios { catalogo ?? Self.catalogoEmpaquetado }

    /// El motor de la rutina activa: se crea una vez por rutina; una versión nueva de la misma rutina (Mati la editó, se
    /// avanzó de semana) lo actualiza sin perder lo que está en curso.
    private func prepararEntreno() {
        guard let rutina else { entreno = nil; return }
        if let e = entreno, e.rutina.id == rutina.id {
            if e.rutina != rutina { e.reemplazarRutina(rutina) }
            return
        }
        let e = ModeloEntreno(cliente: cliente, token: token, outbox: outbox, disco: disco, rutina: rutina, info: info,
                              catalogo: catalogoVigente)
        e.alCambiarRutina = { [weak self] nueva in self?.rutina = nueva }
        entreno = e
    }

    private var archivoCatalogo: URL {
        let base = raizDisco ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MyPump/catalogo-ejercicios.json")
    }

    /// `getCatalogoEjercicios`: el catálogo en el orden en que lo da el servidor (como la web: el orden decide empates
    /// en los sustitutos), guardado para arrancar sin red. Si no llega, el guardado o el empaquetado.
    func cargarCatalogo() async {
        let columnas = "slug_en,name_en,name_normalized,aliases_es,primary_muscle,equipment,patron_movimiento,image_eccentric,image_concentric"
        if case .success(let j) = await cliente.tabla("mypump_ejercicios_catalogo", columnas: columnas),
           let datos = try? JSONEncoder().encode(j), let c = try? CatalogoEjercicios(json: datos), !c.entradas.isEmpty {
            catalogo = c
            try? FileManager.default.createDirectory(at: archivoCatalogo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? datos.write(to: archivoCatalogo, options: .atomic)
        } else if catalogo == nil, let d = try? Data(contentsOf: archivoCatalogo), let c = try? CatalogoEjercicios(json: d), !c.entradas.isEmpty {
            catalogo = c
        }
        if let c = catalogo { entreno?.catalogo = c }
    }

    /// Volvió la red (el monitor de la raíz): sale lo pendiente y, si se estaba mostrando la copia guardada, se trae todo.
    public func alVolverLaRed() async {
        guard fase == .listo, !esDemo, token != nil else { return }
        if desdeCache { await cargar(); return }
        await outbox?.drenar()
        await fotos?.drenar()
    }

    /// Al volver a primer plano (GEN-07): salen las colas, se mira el chat, y si cambió el día se recarga lo que es "de
    /// hoy" (comidas libres, Mi Día, el check de la semana). Si se estaba mostrando la copia offline, se intenta traer
    /// todo de nuevo.
    public func alVolverAPrimerPlano() async {
        guard fase == .listo, !esDemo, token != nil else { return }
        if desdeCache { await cargar(); return }
        // Primero lo "de hoy" si cambió el día (lo que se toque ahora tiene que caer en el día nuevo), después las colas.
        let hoy = FechaLocal.hoy()
        if diaCargado != hoy {
            await cargarComidasLibres()
            await revision?.cargarMiDia()
            await revision?.cargarRevision()
            diaCargado = hoy
        }
        await outbox?.drenar()
        await chat?.sondear()
        await fotos?.drenar()
        await salud?.alVolver()   // con Apple Health conectada: 7 días y retomar el historial (visibilitychange de la web)
        _ = await entreno?.alVolverAPrimerPlano()
    }

    /// GEN-05 (`avisarPlanIncompleto`): arriba de Revisión cuando al plan publicado le falta algo. No es para el
    /// cliente: es para que la captura que le manda a Mati diga qué republicar, en vez de "no me carga".
    public var avisoPlanIncompleto: (texto: String, detalle: String)? {
        guard !esDemo else { return nil }
        let p = problemasDieta + (entreno?.problemas ?? [])
        guard !p.isEmpty else { return nil }
        return ("A tu plan le falta información y algunas cosas pueden verse raras. Avisale a Mati y lo republica.",
                p.prefix(3).joined(separator: " · "))
    }

    /// Lo que falta de la semana para el badge de Revisión y el banner de las otras pestañas.
    public var pendientesDeLaSemana: (faltaCheck: Bool, faltanFotos: Bool, total: Int) {
        guard let revision, let fotos else { return (false, false, 0) }
        return FotosProgreso.pendientes(checkinEnviado: revision.checkinEnviado, posesDeLaSemana: fotos.posesDeLaSemana)
    }

    private func aplicar(_ c: CopiaOffline) {
        // Sin red: la decisión sobre la IA es la última guardada en el teléfono.
        if let g = disco?.leer(ConsentimientoIA.Guardado.self, ConsentimientoIA.archivo) {
            consentimientoIADisponible = true
            consentimientoIA = g.acepta
        }
        defer { prepararEntreno(); if let e = entreno { Task { await e.cargar() } } }
        info = decodificar(ClienteInfo.self, c.info)
        rutina = c.rutina.flatMap { decodificar(RutinaActiva.self, $0) }
        dieta = dietaNormalizada(c.dieta)
        if let id = dieta?.id { swaps = disco?.leer([String: SwapLocal].self, "swaps_\(id).json") ?? [:] }
    }

    // MARK: - Dieta

    /// El plan que se está mirando: el tipo de día elegido o el primero; sin tipos de día, la dieta entera.
    public var comidasDelDia: [Comida] {
        guard let e = dieta?.estructura else { return [] }
        if e.tiposDia.isEmpty { return e.comidas }
        return (e.tiposDia.first { $0.id == tipoDia } ?? e.tiposDia[0]).comidas
    }

    /// Objetivo de macros del día: la normalización ya lo completó (sin `macros_target`, la suma de la opción A).
    public var objetivo: Macros {
        guard let e = dieta?.estructura else { return Macros() }
        if e.tiposDia.isEmpty { return e.macrosTarget ?? Macros() }
        return (e.tiposDia.first { $0.id == tipoDia } ?? e.tiposDia[0]).macrosTarget ?? Macros()
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
        // D7: sin permiso la foto no sale del teléfono (las vistas ya no la ofrecen; esto es por las dudas).
        guard analisisDeFotoPermitido else {
            return .failure(ErrorRPC(clase: .permanente, status: 0, codigo: "SIN_PERMISO_IA",
                                     mensaje: "No aceptaste el asistente de IA: cargala a mano o activalo en Mis datos."))
        }
        return await cliente.vision(token: t, tipo: tipo, jpeg: jpeg)
    }

    /// Lo que contestó `mypump_get_consentimiento_ia`. Lo decidido en el teléfono y todavía en la cola gana; sin red
    /// vale lo último guardado.
    private func aplicarConsentimiento(_ r: Result<JSONValue, ErrorRPC>) async {
        let guardado = disco?.leer(ConsentimientoIA.Guardado.self, ConsentimientoIA.archivo)
        switch r {
        case .success(.objeto(let o)):
            consentimientoIADisponible = true
            if case .bool(let b)? = o["acepta"] { consentimientoIA = b } else { consentimientoIA = nil }
        case .failure(let e) where e.funcionInexistente:
            consentimientoIADisponible = false
            consentimientoIA = nil
            return
        default:
            // Sin red, o el token cayó: lo último que se supo.
            if let guardado { consentimientoIADisponible = true; consentimientoIA = guardado.acepta }
        }
        if case .bool(let b)? = await outbox?.pendientesPorClave()[ConsentimientoIA.clave]?.payload["acepta"] {
            consentimientoIA = b
        }
        if let c = consentimientoIA { disco?.guardar(ConsentimientoIA.Guardado(acepta: c), ConsentimientoIA.archivo) }
    }

    /// La respuesta del cliente (la pantalla del primer uso o Mis datos). Sale por la cola, ANTES de lo que dispara la
    /// pregunta (el mensaje, la foto, el check): así el servidor ya la tiene cuando llega lo otro. Con `drenar: false`
    /// solo queda encolada (quien llama encola lo suyo detrás y después vacía la cola).
    public func decidirConsentimientoIA(_ acepta: Bool, drenar: Bool = true) async {
        guard !esDemo, token != nil else { return }
        consentimientoIA = acepta
        disco?.guardar(ConsentimientoIA.Guardado(acepta: acepta), ConsentimientoIA.archivo)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        _ = await outbox?.encolar("consentimiento_ia",
                                  .objeto(["acepta": .bool(acepta), "plataforma": .texto("ios"), "app": version.map(JSONValue.texto) ?? .null]),
                                  dedupeKey: ConsentimientoIA.clave)
        if drenar { await outbox?.drenar() }
    }

    /// Vacía la cola ahora (por ejemplo, después de encolar la decisión sobre la IA y lo que la disparó).
    public func drenarCola() async { await outbox?.drenar() }

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
                                             borrarAnclados: palanca.anclajeBorraSwaps, enPosicion: { SwapsDeComida.enPosicion(e, tipoActivo: tipo, comidaId: $0, optIdx: $1, foodIdx: $2) })
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

    /// La dieta como la usa la web: normalizada (`normalizarDieta`). Sin ninguna comida usable no hay dieta (la web
    /// mostraba la de ejemplo como si fuera del cliente; acá se dice que todavía no hay plan).
    private func dietaNormalizada(_ j: JSONValue?) -> DietaActiva? {
        guard var d = j.flatMap({ decodificar(DietaActiva.self, $0) }) else { problemasDieta = []; return nil }
        let r = NormalizarDieta.normalizar(d.estructura)
        problemasDieta = r.problemas
        guard r.usable else { return nil }
        d.estructura = r.estructura
        return d
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
