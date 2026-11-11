import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

// Los tres modelos de la cola B (2.3.0). Cada uno existe con la cuenta, pero solo llama al servidor con su palanca
// prendida; `ModeloApp` decide cuándo. En los tres:
//   · sin el servidor nuevo (PGRST202, 404), token caído, apagado o una forma que no se entiende: no se muestra nada
//     y se borra la copia;
//   · un corte de red deja lo último que se supo.

/// «Tu recorrido» (`fin_plan`): lo que hizo en estos meses y el pedido de la videollamada con Mati.
@MainActor @Observable
public final class ModeloRecorrido {
    static let archivo = "recorrido.json"
    static let archivoBorrador = "recorrido-borrador.json"
    public enum Envio: Equatable, Sendable { case ninguno, enviando, error }

    /// nil = no se muestra.
    public private(set) var estado: EstadoRecorrido?
    public private(set) var envio: Envio = .ninguno
    /// La hoja se tiene que abrir sola (una vez por resumen). Lo apaga `seAbrio()`.
    public private(set) var abrirSola = false
    private var borrador = Borrador()

    struct Borrador: Codable, Equatable {
        var respuestas: [String: String] = [:]
        /// El id del pedido, guardado ANTES de mandarlo: un reintento usa el mismo y no duplica.
        var pedidoId: String?
        /// El resumen que ya se abrió solo.
        var abierto: String?
    }

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private var vistoMandado = false

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
        borrador = disco?.leer(Borrador.self, Self.archivoBorrador) ?? Borrador()
    }

    public var respuestas: [String: String] { borrador.respuestas }

    /// Con la palanca prendida. Sin red, lo último guardado.
    public func refrescar() async {
        switch await cliente.llamar("mypump_fin_plan_get", ["p_token": .texto(token)]) {
        case .success(let j):
            guard let e = EstadoRecorrido(j) else { ocultar(); return }
            aplicar(e)
            disco?.guardar(e, Self.archivo)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            ocultar()
        case .failure:
            if estado == nil, let e = disco?.leer(EstadoRecorrido.self, Self.archivo) { aplicar(e) }
        }
    }

    /// Palanca apagada: no se ve nada y no queda copia.
    public func apagar() { ocultar() }

    private func ocultar() {
        estado = nil
        abrirSola = false
        envio = .ninguno
        disco?.borrar(Self.archivo)
    }

    private func aplicar(_ e: EstadoRecorrido) {
        estado = e
        // Ya pedido: el borrador cumplió. Queda la marca de lo que se abrió.
        if e.estado != .publicado, borrador.pedidoId != nil || !borrador.respuestas.isEmpty {
            borrador.pedidoId = nil; borrador.respuestas = [:]; guardarBorrador()
        }
        abrirSola = e.estado == .publicado && borrador.abierto != Recorrido.huella(e.resumen)
    }

    /// La hoja se mostró (sola o por la tarjeta): no vuelve a abrirse sola con este resumen, y se avisa una vez que lo vio.
    public func seAbrio() {
        guard let e = estado else { return }
        abrirSola = false
        let h = Recorrido.huella(e.resumen)
        if borrador.abierto != h { borrador.abierto = h; guardarBorrador() }
        guard !vistoMandado else { return }
        vistoMandado = true
        Task { _ = await cliente.llamar("mypump_fin_plan_visto", ["p_token": .texto(token)]) }
    }

    public func responder(_ clave: String, _ texto: String) {
        guard Recorrido.preguntas.contains(where: { $0.clave == clave }) else { return }
        let t = String(texto.prefix(Recorrido.maxRespuesta))
        guard borrador.respuestas[clave] ?? "" != t else { return }
        borrador.respuestas[clave] = t
        guardarBorrador()
    }

    /// «Agendar con Mati». No agenda ni le escribe a nadie: deja el pedido, que sigue el circuito de siempre.
    public func pedir() async {
        guard let e = estado, e.estado == .publicado, envio != .enviando else { return }
        envio = .enviando
        if borrador.pedidoId == nil { borrador.pedidoId = UUID().uuidString.lowercased(); guardarBorrador() }
        guard let id = borrador.pedidoId else { envio = .error; return }
        let resp = Recorrido.respuestasParaEnviar(borrador.respuestas)
        let r = await cliente.llamar("mypump_fin_plan_pedir", [
            "p_token": .texto(token), "p_id": .texto(id), "p_respuestas": .objeto(resp.mapValues(JSONValue.texto)),
        ])
        switch r {
        case .success(let j) where j["ok"] == .bool(true):
            envio = .ninguno
            if var nuevo = estado {
                nuevo.estado = j["estado"]?.comoTexto == "agendado" ? .agendado : .pedido
                estado = nuevo
                disco?.guardar(nuevo, Self.archivo)
            }
            borrador.pedidoId = nil; borrador.respuestas = [:]; guardarBorrador()
            await refrescar()
        case .success(.null):
            ocultar()
        case .success(let j):
            // `apagado` o `no_disponible`: ya no corresponde mostrarlo.
            if j["error"]?.comoTexto != nil { ocultar() } else { envio = .error }
        case .failure:
            envio = .error
        }
    }

    private func guardarBorrador() { disco?.guardar(borrador, Self.archivoBorrador) }
}

/// «Dónde comprarlo» (`compras_pais`): las tiendas que Mati revisó para el país del alumno, por suplemento.
@MainActor @Observable
public final class ModeloCompras {
    static let archivo = "compras.json"

    /// Vacío = no se muestra nada.
    public private(set) var items: [ComprasItem] = []

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
    }

    public var hay: Bool { !items.isEmpty }
    public func opciones(para nombre: String) -> [OpcionCompra] { Compras.opciones(para: nombre, en: items) }

    public func refrescar() async {
        switch await cliente.llamar("mypump_compras_get", ["p_token": .texto(token)]) {
        case .success(let j):
            let nuevos = Compras.items(j)
            if nuevos != items { items = nuevos }
            if nuevos.isEmpty { disco?.borrar(Self.archivo) } else { disco?.guardar(nuevos, Self.archivo) }
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
        case .failure:
            if items.isEmpty, let g = disco?.leer([ComprasItem].self, Self.archivo) { items = g }
        }
    }

    public func apagar() {
        if !items.isEmpty { items = [] }
        disco?.borrar(Self.archivo)
    }
}

/// «Entreno en casa» (`casa`): el interruptor de Mi gimnasio y la lista de lo que tiene en casa.
@MainActor @Observable
public final class ModeloCasa {
    static let archivoBorrador = "casa-borrador.json"
    public enum Resultado: Equatable, Sendable { case ok, sinSenal, error, enCurso, sinDatos }

    /// nil = el interruptor no se muestra.
    public private(set) var estado: EstadoCasa?
    public private(set) var enviando = false
    public private(set) var cambiando = false
    private var borrador = Borrador()

    struct Borrador: Codable, Equatable {
        var cargaId: String?
        var marcados: [String] = []
        var kilos: [String: String] = [:]
        var sinEquipo = false
        var nota = ""
    }

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
        borrador = disco?.leer(Borrador.self, Self.archivoBorrador) ?? Borrador()
    }

    public var visible: Bool { estado != nil }
    public var prendido: Bool { Casa.prendido(estado) }
    public var fijo: Bool { Casa.fijo(estado) }
    public var pantalla: Casa.Pantalla { Casa.pantalla(estado) }
    public var marcados: Set<String> { Set(borrador.marcados) }
    public var sinEquipo: Bool { borrador.sinEquipo }
    public var nota: String { borrador.nota }
    public func kilos(_ tipo: String) -> String { borrador.kilos[tipo] ?? "" }
    public var puedeEnviar: Bool { Casa.puedeEnviar(marcados: marcados, sinEquipo: sinEquipo) }
    public func nombre(_ tipo: String) -> String { estado?.tipos.first { $0.tipo == tipo }?.nombre ?? tipo }

    public func refrescar() async {
        switch await cliente.llamar("mypump_casa_get", ["p_token": .texto(token)]) {
        case .success(let j):
            guard let e = EstadoCasa(j) else { apagar(); return }
            aplicar(e)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
        case .failure:
            break   // sin señal queda lo que se veía; si nunca se supo nada, no se muestra
        }
    }

    public func apagar() { estado = nil }

    private func aplicar(_ e: EstadoCasa) {
        estado = e
        // Lo marcado es de UNA carga: con otra (o sin borrador de casa) se empieza de cero.
        let id = e.abierta.flatMap { $0.enCasa && $0.estado == "borrador" ? $0.id : nil }
        if borrador.cargaId != id {
            borrador = Borrador(cargaId: id)
            guardarBorrador()
        }
    }

    /// El interruptor. Prenderlo abre (o pasa a casa) el borrador; apagarlo con un borrador de casa lo devuelve al
    /// gimnasio. Apagarlo con casa vigente y sin borrador no pasa por acá: es «Cambié de gimnasio», de Mi gimnasio.
    public func elegir(_ casa: Bool) async -> Resultado {
        guard !cambiando else { return .error }
        cambiando = true
        defer { cambiando = false }
        return await elegir(casa, reintentos: 1)
    }

    private func elegir(_ casa: Bool, reintentos: Int) async -> Resultado {
        switch await cliente.llamar("mypump_casa_elegir", ["p_token": .texto(token), "p_casa": .bool(casa)]) {
        case .success(.null): apagar(); return .error
        case .success(let j):
            if j["ok"] == .bool(true) { await refrescar(); return .ok }
            switch j["error"]?.comoTexto {
            case "en_curso": await refrescar(); return .enCurso
            case "no_habilitado": apagar(); return .error
            case "reintentar" where reintentos > 0: return await elegir(casa, reintentos: reintentos - 1)
            default: return .error
            }
        case .failure(let e): return e.clase == .permanente ? .error : .sinSenal
        }
    }

    public func marcar(_ tipo: String, _ si: Bool) {
        guard estado?.tipos.contains(where: { $0.tipo == tipo }) == true else { return }
        var m = marcados
        if si { m.insert(tipo); borrador.sinEquipo = false } else { m.remove(tipo); borrador.kilos[tipo] = nil }
        borrador.marcados = (estado?.tipos.map(\.tipo) ?? []).filter(m.contains)
        guardarBorrador()
    }

    public func marcarSinEquipo(_ si: Bool) {
        borrador.sinEquipo = si
        if si { borrador.marcados = []; borrador.kilos = [:] }
        guardarBorrador()
    }

    public func fijarKilos(_ tipo: String, _ texto: String) {
        borrador.kilos[tipo] = String(texto.prefix(6))
        guardarBorrador()
    }

    public func fijarNota(_ s: String) {
        borrador.nota = String(s.prefix(Casa.maxNota))
        guardarBorrador()
    }

    /// «Enviar a Mati». Reintentar es seguro: el servidor contesta `ya`.
    public func enviar() async -> Resultado {
        guard let e = estado, let a = e.abierta, a.enCasa, a.estado == "borrador", !enviando else { return .error }
        guard puedeEnviar else { return .sinDatos }
        enviando = true
        defer { enviando = false }
        let equipos = Casa.equiposParaEnviar(tipos: e.tipos, marcados: marcados, kilos: borrador.kilos).map { q -> JSONValue in
            var o: [String: JSONValue] = ["tipo": .texto(q.tipo)]
            if let k = q.kg { o["kg"] = .numero(k) }
            return .objeto(o)
        }
        let nota = borrador.nota.trimmingCharacters(in: .whitespacesAndNewlines)
        let r = await cliente.llamar("mypump_casa_enviar", [
            "p_token": .texto(token), "p_id": .texto(a.id), "p_equipos": .lista(equipos),
            "p_sin_equipo": .bool(borrador.sinEquipo), "p_nota": nota.isEmpty ? .null : .texto(nota),
        ])
        switch r {
        case .success(.null): apagar(); return .error
        case .success(let j):
            if j["ok"] == .bool(true) { await refrescar(); return .ok }
            switch j["error"]?.comoTexto {
            case "sin_datos", "contradiccion": return .sinDatos
            case "no_habilitado": apagar(); return .error
            default: await refrescar(); return .error   // `no_encontrado`, `no_es_casa`: lo que haya ahora
            }
        case .failure(let e): return e.clase == .permanente ? .error : .sinSenal
        }
    }

    private func guardarBorrador() { disco?.guardar(borrador, Self.archivoBorrador) }
}
