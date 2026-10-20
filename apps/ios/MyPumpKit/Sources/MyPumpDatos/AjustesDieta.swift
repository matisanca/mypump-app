import Foundation
import MyPumpModelos
import MyPumpReglas

// Los ajustes de porciones del día (feedback de clientes del 20-oct): sumar o restar kcal a una comida, gramos a mano,
// «Hoy no la como» y compensar en la siguiente. La cuenta es de `AjustePorciones` (MyPumpReglas); acá vive lo de HOY:
// en el teléfono (`ajustes_<dieta>.json`, solo el día) y en la base (`mypump_ajustes_dieta`, una fila por día, por la
// cola), para que Mati lo pueda ver y para que el cliente lo encuentre en otro teléfono. Sin la migración nativa_004
// (PGRST202) queda solo en el teléfono, como cualquier otra cosa que todavía no tiene tabla.

/// Lo que va a disco: los ajustes de UN día (el de hoy). Al cambiar de día no valen.
struct AjustesGuardados: Codable, Equatable {
    var fecha: String
    var comidas: [String: AjusteComida]
}

extension ModeloApp {
    public nonisolated static let kindAjustes = "ajustes_dieta"

    nonisolated static func claveAjustes(_ fecha: String) -> String { "ajustes_dieta_\(fecha)" }
    nonisolated static func archivoAjustes(_ dietaId: String) -> String { "ajustes_\(dietaId).json" }

    /// Los de hoy: si cambió el día con la app abierta, ninguno.
    public var ajustesDeHoy: [String: AjusteComida] { fechaAjustes == FechaLocal.hoy() ? ajustes : [:] }

    /// Al cargar la dieta (y al cambiar de día): lo del teléfono, si es de hoy y de esta dieta.
    func cargarAjustes() {
        let hoy = FechaLocal.hoy()
        fechaAjustes = hoy
        guard let id = dieta?.id, let g = disco?.leer(AjustesGuardados.self, Self.archivoAjustes(id)), g.fecha == hoy else {
            ajustes = [:]
            return
        }
        ajustes = g.comidas.filter { !$0.value.neutro }
    }

    /// Las comidas de hoy como las ve el cliente: la opción elegida (`opciones`, si no la del ajuste, si no A) y los
    /// reemplazos. Es lo que necesita la cuenta del día.
    public func comidasParaAjustar(opciones: [String: Int]) -> [AjustePorciones.ComidaDelDia] {
        comidasDelDia.map { c in
            let elegida = opciones[c.id] ?? ajustesDeHoy[c.id]?.opcion ?? 0
            let o = c.opciones.isEmpty ? 0 : min(max(0, elegida), c.opciones.count - 1)
            let alimentos = c.opciones.indices.contains(o)
                ? c.opciones[o].alimentos.enumerated().map { efectivo($1, comidaId: c.id, opt: o, idx: $0).alimento }
                : []
            return AjustePorciones.ComidaDelDia(id: c.id, nombre: c.nombre ?? "", opcion: o, alimentos: alimentos)
        }
    }

    /// El día con los ajustes de hoy aplicados (lo que dibuja Dieta).
    public func diaAjustado(opciones: [String: Int]) -> [String: AjustePorciones.ComidaAjustada] {
        AjustePorciones.dia(comidasParaAjustar(opciones: opciones), ajustes: ajustesDeHoy)
    }

    /// Cambia (o saca, con nil o un ajuste neutro) el ajuste de una comida, lo guarda y manda el día entero. Cada cantidad
    /// a mano queda anclada al alimento que se veía (si Mati vuelve a publicar con otro alimento ahí, no vale). En la demo
    /// queda en memoria.
    public func ajustar(_ comidaId: String, _ ajuste: AjusteComida?, opciones: [String: Int]) async {
        if fechaAjustes != FechaLocal.hoy() { cargarAjustes() }
        opcionesVistas.merge(opciones) { $1 }
        var nuevos = ajustes
        var a = ajuste
        if let x = a, let c = comidasParaAjustar(opciones: opcionesVistas).first(where: { $0.id == comidaId }) {
            a = AjustePorciones.anclar(x, en: c)
        }
        if let a, !a.neutro { nuevos[comidaId] = a } else { nuevos[comidaId] = nil }
        guard nuevos != ajustes else { return }
        ajustes = nuevos
        guard !esDemo, let id = dieta?.id else { return }
        _ = disco?.guardar(AjustesGuardados(fecha: fechaAjustes, comidas: nuevos), Self.archivoAjustes(id))
        await encolarAjustes(opciones: opciones)
    }

    /// Un reemplazo (o volver al alimento del plan) cambia el alimento de esa posición: la cantidad puesta a mano era del
    /// anterior y en otra unidad (60 g de avena no son 60 rebanadas de pan), así que se descarta.
    func soltarCantidad(comidaId: String, opt: Int, idx: Int) async {
        guard var a = ajustesDeHoy[comidaId], a.opcion == opt, a.cantidades[String(idx)] != nil else { return }
        a.cantidades[String(idx)] = nil
        await ajustar(comidaId, a, opciones: [comidaId: opt])
    }

    /// El día entero a la cola (una op por día: la última gana). Con el resumen por comida para que Mati lo lea sin la app.
    func encolarAjustes(opciones: [String: Int]) async {
        guard let dieta, let outbox else { return }
        let comidas = comidasParaAjustar(opciones: opcionesVistas.merging(opciones) { $1 })
        let dia = AjustePorciones.dia(comidas, ajustes: ajustes)
        var resumen: [JSONValue] = []
        var plan = 0.0, hoy = 0.0
        for c in comidas {
            guard let d = dia[c.id] else { continue }
            plan += d.kcalPlan
            hoy += d.kcal
            resumen.append(.objeto(["comida_id": .texto(c.id), "nombre": .texto(c.nombre), "kcal_plan": .numero(d.kcalPlan),
                                    "kcal_dia": .numero(d.kcal), "omitida": .bool(d.omitida)]))
        }
        let ajustesJSON = (try? JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(ajustes))) ?? .objeto([:])
        let payload: JSONValue = .objeto([
            "fecha": .texto(fechaAjustes), "dietaId": .texto(dieta.id), "tipoDia": tipoDia.map(JSONValue.texto) ?? .null,
            "ajustes": ajustesJSON, "resumen": ajustes.isEmpty ? .null : .lista(resumen),
            "kcalPlan": ajustes.isEmpty ? .null : .numero(plan), "kcalDia": ajustes.isEmpty ? .null : .numero(hoy),
        ]).sinNoFinitos
        await outbox.encolar(Self.kindAjustes, payload, dedupeKey: Self.claveAjustes(fechaAjustes))
    }

    /// Al hidratar la dieta: lo que tiene el servidor para hoy, salvo que haya un cambio del teléfono que todavía no
    /// salió (ese gana). Si el servidor no tiene nada y el teléfono sí (la migración se aplicó después, o salió sin
    /// tabla), se sube. Otra dieta en el servidor (Mati la volvió a publicar) no se mezcla.
    func hidratarAjustes(token t: String, dieta: DietaActiva, vigente: () -> Bool) async {
        let hoy = FechaLocal.hoy()
        let r = await cliente.llamar("mypump_get_ajustes_dieta", ["p_token": .texto(t), "p_desde": .texto(hoy), "p_hasta": .texto(hoy)])
        guard vigente(), case .success(let v) = r, case .lista(let filas) = v, let outbox else { return }
        let pendiente = (await outbox.pendientesPorClave())[Self.claveAjustes(hoy)] != nil
        guard vigente(), !pendiente else { return }
        if fechaAjustes != hoy { cargarAjustes() }
        let remota = filas.first { $0["fecha"]?.comoTexto == hoy }
        if let remota {
            guard (remota["dieta_id"]?.comoTexto ?? dieta.id) == dieta.id, let a = remota["ajustes"],
                  let comidas = try? JSONDecoder().decode([String: AjusteComida].self, from: JSONEncoder().encode(a))
            else { return }
            let validas = comidas.filter { !$0.value.neutro }
            guard validas != ajustes else { return }
            ajustes = validas
            _ = disco?.guardar(AjustesGuardados(fecha: hoy, comidas: validas), Self.archivoAjustes(dieta.id))
        } else if !ajustes.isEmpty {
            await encolarAjustes(opciones: [:])
        }
    }
}
