import Foundation
import MyPumpModelos
import MyPumpReglas

// «✓ Comí» / «✗ Salté» por comida y lo consumido del día (DIE-05..07; volvió en D25, 27-oct: «no puedo hacer el
// seguimiento a las comidas», «no aparecen las calorías que vas consumiendo»). Lo mismo que la web: una marca por
// (cliente, fecha, comida) en `mypump_comidas_marcadas`, que se escribe por la cola (kind `comida`, la última gana) y se
// lee del servidor al cargar, al tirar para actualizar y al volver a la app, así se ven las de la web o del otro teléfono.
// En el teléfono quedan las de hoy (`marcas_comidas.json`) para verlas sin red. La cuenta es de `ConsumoDelDia`.

/// Lo que va a disco: las marcas de UN día (el de hoy). Al cambiar de día no valen.
struct MarcasGuardadas: Codable, Equatable {
    var fecha: String
    var marcas: [String: MarcaComida]
}

extension ModeloApp {
    public nonisolated static let kindMarca = "comida"
    nonisolated static let archivoMarcas = "marcas_comidas.json"

    /// La de la web: `comida|<fecha>|<comida>`. Con la misma, una marca nativa y una de la web pendientes se pisan bien.
    nonisolated static func claveMarca(_ fecha: String, _ comidaId: String) -> String { "comida|\(fecha)|\(comidaId)" }

    /// Las de hoy: si cambió el día con la app abierta, ninguna.
    public var marcasDeHoy: [String: MarcaComida] { fechaMarcas == FechaLocal.hoy() ? marcas : [:] }

    /// Al cargar (y al cambiar de día): las del teléfono, si son de hoy. La demo no tiene carpeta: empieza sin marcas.
    func cargarMarcas() {
        let hoy = FechaLocal.hoy()
        fechaMarcas = hoy
        guard let g = disco?.leer(MarcasGuardadas.self, Self.archivoMarcas), g.fecha == hoy else {
            marcas = [:]
            return
        }
        marcas = g.marcas
    }

    /// Lo comido hoy con las opciones que se ven (las comidas marcadas «Comí» se cuentan con la de la marca), los
    /// reemplazos, los ajustes de hoy y las comidas libres.
    public func consumo(opciones: [String: Int]) -> ConsumoDelDia.Consumo {
        ConsumoDelDia.calcular(comidasDelDia, marcas: marcasDeHoy, libres: comidasLibres, ajustes: ajustesDeHoy, vistas: opciones) {
            efectivo($3, comidaId: $0, opt: $1, idx: $2).alimento
        }
    }

    /// «Comí» o «Salté» con la opción `opcion` (la que se ve), o nil para desmarcar. «Comí» arranca con todo tildado.
    /// Optimista: se ve al toque, queda en el teléfono y sale por la cola (sin red, cuando vuelva). En la demo, en memoria.
    public func marcar(_ comidaId: String, _ estado: MarcaComida.Estado?, opcion: Int) async {
        if fechaMarcas != FechaLocal.hoy() { cargarMarcas() }
        guard let c = comidasDelDia.first(where: { $0.id == comidaId }) else { return }
        let o = c.opciones.isEmpty ? 0 : min(max(0, opcion), c.opciones.count - 1)
        await cambiarMarca(comidaId, estado.map { MarcaComida(opcion: ConsumoDelDia.nombreOpcion(c, o), estado: $0) },
                           opcionAlDesmarcar: ConsumoDelDia.nombreOpcion(c, o))
    }

    /// Consumo parcial (DIE-06): destilda (o vuelve a tildar) un alimento de una comida marcada «Comí». El índice es de la
    /// opción de la marca: Dieta solo muestra los tildes mirando esa opción.
    public func alternarAlimento(_ comidaId: String, _ idx: Int) async {
        if fechaMarcas != FechaLocal.hoy() { cargarMarcas() }
        guard idx >= 0, let m = marcas[comidaId], m.estado == .comido else { return }
        let excluidos = m.excluidos.contains(idx) ? m.excluidos.filter { $0 != idx } : m.excluidos + [idx]
        await cambiarMarca(comidaId, MarcaComida(opcion: m.opcion, estado: .comido, excluidos: excluidos), opcionAlDesmarcar: m.opcion)
    }

    private func cambiarMarca(_ comidaId: String, _ nueva: MarcaComida?, opcionAlDesmarcar: String?) async {
        guard nueva != marcas[comidaId] else { return }
        ordenMarcas[comidaId, default: 0] += 1
        marcas[comidaId] = nueva
        guard !esDemo, let outbox else { return }
        _ = disco?.guardar(MarcasGuardadas(fecha: fechaMarcas, marcas: marcas), Self.archivoMarcas)
        // El payload de la web (`toggleComidaEstado` / `toggleFoodComido`): sin estado, Escrituras desmarca.
        let payload: JSONValue = .objeto([
            "fecha": .texto(fechaMarcas), "comidaId": .texto(comidaId),
            "opcion": (nueva?.opcion ?? opcionAlDesmarcar).map(JSONValue.texto) ?? .null,
            "estado": nueva.map { .texto($0.estado.rawValue) } ?? .null,
            "excl": .lista((nueva?.excluidos ?? []).map { .numero(Double($0)) }),
        ])
        await outbox.encolar(Self.kindMarca, payload, dedupeKey: Self.claveMarca(fechaMarcas, comidaId))
    }

    /// Lo que dice el servidor de hoy, con dos excepciones por comida: lo que está en la cola sin salir gana (se lee del
    /// payload, como la web: es lo último que decidió el cliente) y lo que se tocó o estaba en la cola mientras viajaba la
    /// lectura queda como está en el teléfono (la respuesta puede ser una foto de antes de ese cambio). Sin red, nada cambia.
    func hidratarMarcas() async {
        guard let t = token, !esDemo, let outbox, dieta != nil else { return }
        let hoy = FechaLocal.hoy()
        if fechaMarcas != hoy { cargarMarcas() }
        let prefijo = Self.claveMarca(hoy, "")
        func enCola() async -> [String: Operacion] {
            var r: [String: Operacion] = [:]
            for (k, op) in await outbox.pendientesPorClave() where k.hasPrefix(prefijo) { r[String(k.dropFirst(prefijo.count))] = op }
            return r
        }
        let antes = ordenMarcas
        let enColaAntes = await enCola()
        let r = await cliente.filas("mypump_get_comidas_marcadas", ["p_token": .texto(t), "p_fecha": .texto(hoy)], como: ComidaMarcada.self)
        guard token == t, !esDemo, fechaMarcas == hoy, case .success(let filas) = r else { return }
        let enColaAhora = await enCola()
        guard token == t, !esDemo, fechaMarcas == hoy else { return }
        var nuevas = ConsumoDelDia.marcas(filas)
        for id in Set(enColaAntes.keys).union(ordenMarcas.keys.filter { antes[$0] != ordenMarcas[$0] }) { nuevas[id] = marcas[id] }
        for (id, op) in enColaAhora { nuevas[id] = Self.marcaDelPayload(op.payload) }
        guard nuevas != marcas else { return }
        marcas = nuevas
        _ = disco?.guardar(MarcasGuardadas(fecha: hoy, marcas: nuevas), Self.archivoMarcas)
    }

    /// La marca que deja una op `comida` de la cola (nil = desmarcar).
    nonisolated static func marcaDelPayload(_ p: JSONValue) -> MarcaComida? {
        guard let e = p["estado"]?.comoTexto.flatMap(MarcaComida.Estado.init(rawValue:)) else { return nil }
        var excl: [Int] = []
        if case .lista(let a)? = p["excl"] { excl = a.compactMap { $0.comoNumero.flatMap { $0 == $0.rounded() ? Int(exactly: $0) : nil } } }
        return MarcaComida(opcion: p["opcion"]?.comoTexto, estado: e, excluidos: excl)
    }
}
