import Foundation
import MyPumpModelos
import MyPumpReglas

// Cargar días anteriores en Dieta y copiar a hoy lo de otro día. Lo de HOY sigue exactamente como estaba (`marcas`, `ajustes`,
// `comidasLibres`, su disco y su hidratación): el día pasado es otra caja (`diaPasado`), que vive solo mientras se la mira,
// se lee del servidor y escribe por la misma cola con la fecha de ese día (las `dedupeKey` llevan la fecha: no pisan otra).
// Los días pasados no van a disco: sin señal no se pueden abrir, porque un día se guarda entero y escribir sin haber leído
// borraría lo que ya tenía.

/// El día anterior que se está mirando en Dieta.
public struct DiaPasado: Equatable, Sendable {
    public let fecha: String
    public var cargando = true
    public var sinRed = false
    public var marcas: [String: MarcaComida] = [:]
    public var ajustes: [String: AjusteComida] = [:]
    public var libres: [ComidaLibre] = []
    public var tipoDia: String?
    /// Ese día regía otro plan (fila de otra dieta o marcas de comidas que ya no existen): se ve el plan actual, sin marcas ni
    /// ajustes, y solo se pueden tocar las comidas libres.
    public var otroPlan = false
    /// Un guardado de ese día no salió: sigue en el teléfono.
    public var sinGuardar = false
    var opcionesVistas: [String: Int] = [:]

    init(fecha: String, tipoDia: String?) { self.fecha = fecha; self.tipoDia = tipoDia }
}

public struct ResultadoCopia: Equatable, Sendable {
    public var comidas = 0
    public var libres = 0
    /// Comidas libres que no se pudieron crear (la copia de comidas libres es directa, no por la cola).
    public var libresFallidas = 0
    /// Comidas que cambiaron mientras se elegía y no se reemplazaron porque el cliente no lo había pedido.
    public var saltadas = 0
    public init() {}
}

/// Lo leído de un día (servidor + lo que sigue en la cola).
struct DatosDia {
    var marcas: [String: MarcaComida]
    var ajustes: [String: AjusteComida]
    var libres: [ComidaLibre]
    var tipoDia: String?
    var otroPlan: Bool
    var sinGuardar: Bool
}

extension ModeloApp {
    // MARK: - Lo que dibuja Dieta

    /// El día a la vista en formato ISO.
    public var fechaVista: String { diaPasado?.fecha ?? FechaLocal.hoy() }
    public var enDiaPasado: Bool { diaPasado != nil }
    /// Hoy y los días anteriores que se pueden abrir. Vacío en la demo: no escribe ni tiene días guardados.
    public var fechasDieta: [String] {
        guard !esDemo, token != nil else { return [] }
        return DiasDieta.seleccionables(hoy: FechaLocal.hoy(), hoyServidor: DiasDieta.hoyServidor())
    }

    public var marcasVista: [String: MarcaComida] { diaPasado?.marcas ?? marcasDeHoy }
    public var ajustesVista: [String: AjusteComida] { diaPasado?.ajustes ?? ajustesDeHoy }
    public var libresVista: [ComidaLibre] { diaPasado?.libres ?? comidasLibres }
    public var tipoDiaVista: String? { diaPasado != nil ? diaPasado?.tipoDia : tipoDia }
    public var ajustesSinGuardarVista: Bool { diaPasado?.sinGuardar ?? ajustesSinGuardar }

    func comidasDeTipo(_ tipo: String?) -> [Comida] {
        guard let e = dieta?.estructura else { return [] }
        if e.tiposDia.isEmpty { return e.comidas }
        return (e.tiposDia.first { $0.id == tipo } ?? e.tiposDia[0]).comidas
    }

    public var comidasVista: [Comida] { diaPasado != nil ? comidasDeTipo(diaPasado?.tipoDia) : comidasDelDia }

    public var objetivoVista: Macros {
        guard let p = diaPasado, let e = dieta?.estructura, !e.tiposDia.isEmpty else { return objetivo }
        return (e.tiposDia.first { $0.id == p.tipoDia } ?? e.tiposDia[0]).macrosTarget ?? Macros()
    }

    /// Se pueden tocar la marca, los ajustes y los agregados (las comidas libres no dependen del plan).
    public var vistaEditable: Bool { diaPasado.map { !$0.cargando && !$0.sinRed && !$0.otroPlan } ?? true }
    /// Se pueden cargar comidas libres: el día ya se leyó.
    public var vistaAdmiteLibres: Bool { diaPasado.map { !$0.cargando && !$0.sinRed } ?? true }

    /// La ventana de «Comí» / «Salté» vigente.
    public var diasMarcar: Int { max(DiasDieta.diasMarcarDeFabrica, min(palanca.diasMarcarDieta ?? DiasDieta.diasMarcarDeFabrica, DiasDieta.diasAtras)) }

    /// ¿«Comí» y «Salté» valen para el día a la vista? (Hoy, siempre.)
    public var vistaPuedeMarcar: Bool {
        guard let p = diaPasado else { return true }
        return vistaEditable && DiasDieta.permiteMarcar(p.fecha, hoyServidor: DiasDieta.hoyServidor(), dias: diasMarcar)
    }

    /// Cambia el tipo de día de lo que se mira: el de un día pasado no toca el de hoy.
    public func elegirTipoDia(_ id: String) {
        guard var p = diaPasado else { tipoDia = id; return }
        guard p.tipoDia != id, vistaEditable else { return }
        p.tipoDia = id
        diaPasado = p
        ordenDiaPasado += 1
        if !p.ajustes.isEmpty { Task { await encolarDiaPasado(p) } }
    }

    // MARK: - Abrir y volver

    /// Abre un día anterior, o vuelve a hoy con nil (o la fecha de hoy).
    public func irADia(_ fecha: String?) async {
        vueltaDiaPasado += 1
        let vuelta = vueltaDiaPasado
        guard let fecha, fecha != FechaLocal.hoy(), fechasDieta.contains(fecha) else {
            diaPasado = nil
            return
        }
        diaPasado = DiaPasado(fecha: fecha, tipoDia: tipoDia)
        await leerDiaPasado(fecha, vuelta: vuelta)
    }

    /// Tirar para actualizar (o volver a la app) mirando un día anterior.
    public func refrescarDiaPasado() async {
        guard let f = diaPasado?.fecha else { return }
        if diaPasado?.sinRed == true { diaPasado?.cargando = true; diaPasado?.sinRed = false }
        vueltaDiaPasado += 1
        await leerDiaPasado(f, vuelta: vueltaDiaPasado)
    }

    private func leerDiaPasado(_ fecha: String, vuelta: Int) async {
        let orden = ordenDiaPasado
        let r = await leerDia(fecha)
        // Otro día elegido (o la vuelta a hoy) mientras viajaba: esta respuesta ya no es de nadie.
        guard vuelta == vueltaDiaPasado, var p = diaPasado, p.fecha == fecha else { return }
        // Tocó algo mientras viajaba: la respuesta es una foto de antes de ese cambio.
        guard orden == ordenDiaPasado else { return }
        guard let r else {
            p.cargando = false
            // Con el día ya a la vista, un corte al refrescar no lo cierra.
            if p.marcas.isEmpty && p.ajustes.isEmpty && p.libres.isEmpty { p.sinRed = true }
            diaPasado = p
            return
        }
        p.cargando = false
        p.sinRed = false
        p.marcas = r.marcas
        p.ajustes = r.ajustes
        p.libres = r.libres
        p.tipoDia = r.tipoDia ?? p.tipoDia
        p.otroPlan = r.otroPlan
        p.sinGuardar = r.sinGuardar
        diaPasado = p
    }

    /// Lo que hay guardado de un día: lo del servidor con lo pendiente de la cola por encima (lo pendiente es lo último que
    /// decidió el cliente). nil si no se pudo leer: nunca se trata un corte como un día vacío.
    func leerDia(_ fecha: String) async -> DatosDia? {
        guard let t = token, !esDemo, let outbox else { return nil }
        // Lo pendiente al empezar también gana: si sale mientras viaja la lectura, la foto del servidor puede ser de antes.
        let pendientesAntes = await outbox.pendientesPorClave()
        let porFecha: [String: JSONValue] = ["p_token": .texto(t), "p_fecha": .texto(fecha)]
        async let lecturaMarcas = cliente.filas("mypump_get_comidas_marcadas", porFecha, como: ComidaMarcada.self)
        async let lecturaLibres = cliente.filas("mypump_get_comidas_libres", porFecha, como: ComidaLibre.self)
        async let lecturaAjustes = cliente.llamar("mypump_get_ajustes_dieta", ["p_token": .texto(t), "p_desde": .texto(fecha), "p_hasta": .texto(fecha)])
        let (rm, rl, ra) = await (lecturaMarcas, lecturaLibres, lecturaAjustes)
        guard token == t, case .success(let filasM) = rm, case .success(let libres) = rl else { return nil }
        var filas: [JSONValue] = []
        switch ra {
        case .success(.lista(let f)): filas = f
        case .success: return nil        // null = token caído
        case .failure(let e) where e.codigo == "PGRST202": break   // sin la tabla: no hay ajustes
        case .failure: return nil
        }

        var marcas = ConsumoDelDia.marcas(filasM)
        let prefijo = Self.claveMarca(fecha, "")
        let pendientes = await outbox.pendientesPorClave()
        for lote in [pendientesAntes, pendientes] {
            for (k, op) in lote where k.hasPrefix(prefijo) { marcas[String(k.dropFirst(prefijo.count))] = Self.marcaDelPayload(op.payload) }
        }

        var ajustes: [String: AjusteComida] = [:]
        var tipo: String?
        var dietaRemota: String?
        /// false: no se pudo leer. No es un día vacío: la próxima edición reemplazaría la fila entera.
        func adoptar(_ a: JSONValue?, _ tipoFila: String?, _ dietaFila: String?) -> Bool {
            guard let a, let d = try? JSONDecoder().decode([String: AjusteComida].self, from: JSONEncoder().encode(a)) else { return false }
            ajustes = d.filter { !$0.value.neutro }
            tipo = tipoFila
            dietaRemota = dietaFila
            return true
        }
        if let f = filas.first(where: { $0["fecha"]?.comoTexto == fecha }) {
            guard adoptar(f["ajustes"], f["tipo_dia"]?.comoTexto, f["dieta_id"]?.comoTexto) else { return nil }
        }
        let clave = Self.claveAjustes(fecha)
        // Lo que la base rechazó sigue valiendo en el teléfono, como el de hoy; lo pendiente manda sobre todo.
        let fallido = await outbox.fallidos.last { $0.op.kind == Self.kindAjustes && $0.op.dedupeKey == clave }
        for op in [fallido?.op, pendientesAntes[clave], pendientes[clave]].compactMap({ $0 }) {
            guard adoptar(op.payload["ajustes"], op.payload["tipoDia"]?.comoTexto, op.payload["dietaId"]?.comoTexto) else { return nil }
        }

        // ¿Regía otro plan? La fila dice con qué dieta se guardó; las marcas, qué comidas había.
        let e = dieta?.estructura
        let idsPlan = Set((e?.comidas ?? []).map(\.id) + (e?.tiposDia ?? []).flatMap { $0.comidas.map(\.id) })
        let otraDieta = !ajustes.isEmpty && dietaRemota != nil && dietaRemota != dieta?.id
        let otroPlan = otraDieta || marcas.keys.contains { !idsPlan.contains($0) }
        let tipoValido = tipo.flatMap { t in (e?.tiposDia ?? []).contains { $0.id == t } ? t : nil }
        return DatosDia(marcas: otroPlan ? [:] : marcas, ajustes: otroPlan ? [:] : ajustes, libres: libres, tipoDia: tipoValido,
                        otroPlan: otroPlan, sinGuardar: fallido != nil && pendientes[clave] == nil && pendientesAntes[clave] == nil)
    }

    // MARK: - Escribir en el día pasado

    func ajustarPasado(_ comidaId: String, _ ajuste: AjusteComida?, opciones: [String: Int]) async {
        guard var p = diaPasado, vistaEditable else { return }
        p.opcionesVistas.merge(opciones) { $1 }
        var a = ajuste
        if let x = a, let c = comidasVistaParaAjustar(p, opciones: p.opcionesVistas).first(where: { $0.id == comidaId }) {
            a = AjustePorciones.anclar(x, en: c)
        }
        var nuevos = p.ajustes
        if let a, !a.neutro { nuevos[comidaId] = a } else { nuevos[comidaId] = nil }
        guard nuevos != p.ajustes else { diaPasado = p; return }
        let antes = p.ajustes[comidaId]?.agregados ?? []
        // Los tildes siguen a los agregados con una marca nueva: fuera de la ventana de «Comí» la base la rechazaría y quedaría
        // un tilde corrido, así que los agregados de una comida marcada no se tocan.
        if antes.map(\.ts) != (nuevos[comidaId]?.agregados ?? []).map(\.ts), p.marcas[comidaId]?.estado == .comido, !vistaPuedeMarcar { diaPasado = p; return }
        p.ajustes = nuevos
        // Los tildes de «Comí» siguen a cada agregado (por `_ts`), como hoy.
        var marcaNueva: MarcaComida?
        var marcaCambio = false
        let despues = nuevos[comidaId]?.agregados ?? []
        if antes.map(\.ts) != despues.map(\.ts), let m = p.marcas[comidaId], m.estado == .comido, let c = comidasDeTipo(p.tipoDia).first(where: { $0.id == comidaId }) {
            let o = ConsumoDelDia.opcionDeLaMarca(c, m) ?? 0
            let n = c.opciones.indices.contains(o) ? c.opciones[o].alimentos.count : 0
            let excl = AgregadosComida.excluidosTrasCambio(m.excluidos, alimentosPlan: n, antes: antes.map(\.ts), despues: despues.map(\.ts))
            if excl != m.excluidos {
                marcaNueva = MarcaComida(opcion: m.opcion, estado: .comido, excluidos: excl)
                marcaCambio = true
                p.marcas[comidaId] = marcaNueva
            }
        }
        // «Ese día no la comí» sobre una marcada: la marca se va, como hoy.
        let saleMarca = nuevos[comidaId]?.omitida == true && p.marcas[comidaId] != nil
        let opcionMarca = p.marcas[comidaId]?.opcion
        if saleMarca { p.marcas[comidaId] = nil }
        ordenDiaPasado += 1
        diaPasado = p
        guard !esDemo else { return }
        if marcaCambio && !saleMarca { await encolarMarcaPasado(p.fecha, comidaId, marcaNueva, opcionAlDesmarcar: marcaNueva?.opcion) }
        await encolarDiaPasado(p)
        if saleMarca { await encolarMarcaPasado(p.fecha, comidaId, nil, opcionAlDesmarcar: opcionMarca) }
    }

    func marcarPasado(_ comidaId: String, _ estado: MarcaComida.Estado?, opcion: Int) async {
        guard let p = diaPasado, vistaPuedeMarcar, let c = comidasDeTipo(p.tipoDia).first(where: { $0.id == comidaId }) else { return }
        let o = c.opciones.isEmpty ? 0 : min(max(0, opcion), c.opciones.count - 1)
        await cambiarMarcaPasado(comidaId, estado.map { MarcaComida(opcion: ConsumoDelDia.nombreOpcion(c, o), estado: $0) }, opcionAlDesmarcar: ConsumoDelDia.nombreOpcion(c, o))
    }

    func alternarAlimentoPasado(_ comidaId: String, _ idx: Int) async {
        guard let p = diaPasado, vistaPuedeMarcar, idx >= 0, let m = p.marcas[comidaId], m.estado == .comido else { return }
        let excl = m.excluidos.contains(idx) ? m.excluidos.filter { $0 != idx } : m.excluidos + [idx]
        await cambiarMarcaPasado(comidaId, MarcaComida(opcion: m.opcion, estado: .comido, excluidos: excl), opcionAlDesmarcar: m.opcion)
    }

    private func cambiarMarcaPasado(_ comidaId: String, _ nueva: MarcaComida?, opcionAlDesmarcar: String?) async {
        guard var p = diaPasado, nueva != p.marcas[comidaId] else { return }
        p.marcas[comidaId] = nueva
        ordenDiaPasado += 1
        diaPasado = p
        await encolarMarcaPasado(p.fecha, comidaId, nueva, opcionAlDesmarcar: opcionAlDesmarcar)
    }

    private func encolarMarcaPasado(_ fecha: String, _ comidaId: String, _ nueva: MarcaComida?, opcionAlDesmarcar: String?) async {
        guard !esDemo, let outbox else { return }
        let payload: JSONValue = .objeto([
            "fecha": .texto(fecha), "comidaId": .texto(comidaId),
            "opcion": (nueva?.opcion ?? opcionAlDesmarcar).map(JSONValue.texto) ?? .null,
            "estado": nueva.map { .texto($0.estado.rawValue) } ?? .null,
            "excl": .lista((nueva?.excluidos ?? []).map { .numero(Double($0)) }),
        ])
        await outbox.encolar(Self.kindMarca, payload, dedupeKey: Self.claveMarca(fecha, comidaId))
    }

    func verOpcionPasado(_ comidaId: String, _ opcion: Int) async {
        guard var p = diaPasado else { return }
        p.opcionesVistas[comidaId] = opcion
        diaPasado = p
        if !p.ajustes.isEmpty, !esDemo, vistaEditable { await encolarDiaPasado(p) }
    }

    /// El día pasado entero a la cola (la clave lleva su fecha: no pisa el de hoy).
    func encolarDiaPasado(_ p: DiaPasado) async {
        await encolarDia(fecha: p.fecha, ajustes: p.ajustes, tipo: p.tipoDia,
                         comidas: comidasVistaParaAjustar(p, opciones: p.opcionesVistas))
    }

    func comidasVistaParaAjustar(_ p: DiaPasado, opciones: [String: Int]) -> [AjustePorciones.ComidaDelDia] {
        comidasAjustables(comidasDeTipo(p.tipoDia), ajustes: p.ajustes, tipo: p.tipoDia, opciones: opciones)
    }

    // MARK: - Copiar a hoy

    /// Lo que se puede copiar de `fecha` a hoy. nil si no se pudo leer ese día.
    public func prepararCopia(desde fecha: String) async -> CopiaDeComidas.Plan? {
        guard fecha != FechaLocal.hoy(), let d = await leerDia(fecha) else { return nil }
        if fechaAjustes != FechaLocal.hoy() { cargarAjustes() }
        if fechaMarcas != FechaLocal.hoy() { cargarMarcas() }
        return CopiaDeComidas.plan(comidas: comidasDelDia, origenMarcas: d.marcas, origenAjustes: d.ajustes, origenLibres: d.libres,
                                   hoyMarcas: marcasDeHoy, hoyAjustes: ajustesDeHoy, hoyLibres: comidasLibres, otroPlan: d.otroPlan) { c, m, a, o in
            let sintetica = m ?? MarcaComida(opcion: ConsumoDelDia.nombreOpcion(c, o), estado: .comido)
            return ConsumoDelDia.calcular([c], marcas: [c.id: sintetica], libres: [], ajustes: a.map { [c.id: $0] } ?? [:], vistas: [c.id: o]) {
                self.efectivo($3, comidaId: $0, opt: $1, idx: $2).alimento
            }.kcal
        }
    }

    /// Copia a hoy lo elegido. `reemplazar` son las comidas que el cliente aceptó pisar: lo que no esté ahí y hoy tenga algo
    /// cargado se saltea, aunque haya cambiado después de armar la lista.
    public func copiarAHoy(comidas: [CopiaDeComidas.ItemComida], libres: [CopiaDeComidas.ItemLibre], reemplazar: Set<String>) async -> ResultadoCopia {
        var r = ResultadoCopia()
        guard !esDemo else { return r }
        if fechaAjustes != FechaLocal.hoy() { cargarAjustes() }
        if fechaMarcas != FechaLocal.hoy() { cargarMarcas() }
        for i in comidas {
            let actual = CopiaDeComidas.estado(marca: i.marca, ajuste: i.ajuste, hoyMarca: marcasDeHoy[i.comidaId], hoyAjuste: ajustesDeHoy[i.comidaId])
            if actual == .igual { continue }
            if actual == .conflicto && !reemplazar.contains(i.comidaId) { r.saltadas += 1; continue }
            // Los mismos topes que al agregar a mano: un día que no entra haría rechazar la fila entera de hoy.
            var nuevos = ajustesDeHoy
            nuevos[i.comidaId] = i.ajuste
            if AgregadosComida.motivoNoEntra(nuevos, comidaId: i.comidaId) != nil { r.saltadas += 1; continue }
            let opcionHoy = marcasDeHoy[i.comidaId]?.opcion
            await ajustarHoy(i.comidaId, i.ajuste, opciones: [i.comidaId: i.opcion])
            // Reemplazar es que hoy quede lo de ese día, marca incluida. Si no pisaba nada y ese día no la marcó, no se marca.
            if actual == .conflicto || i.marca != nil { await cambiarMarca(i.comidaId, i.marca, opcionAlDesmarcar: i.marca?.opcion ?? opcionHoy) }
            r.comidas += 1
        }
        // Por conteo: cada una de hoy cubre una sola del origen.
        var deHoy = comidasLibres
        for i in libres {
            if let j = deHoy.firstIndex(where: { CopiaDeComidas.mismaLibre($0, i.libre) }) { deHoy.remove(at: j); continue }
            // Ya estaba cuando se armó la lista y hoy ya no: el cliente no la pidió.
            if i.estado == .igual { continue }
            let d = ComidaLibreNueva.Datos(hora: i.libre.hora.map { String($0.prefix(5)) }, descripcion: i.libre.descripcion ?? "",
                                           kcal: i.libre.kcal ?? 0, prot: i.libre.prot ?? 0, carb: i.libre.carb ?? 0, fat: i.libre.fat ?? 0, detalle: i.libre.detalle)
            switch await crearComidaLibreEn(FechaLocal.hoy(), d) {
            case .success: r.libres += 1
            case .failure: r.libresFallidas += 1
            }
        }
        if r.libresFallidas > 0 { await cargarComidasLibres() }
        return r
    }
}
