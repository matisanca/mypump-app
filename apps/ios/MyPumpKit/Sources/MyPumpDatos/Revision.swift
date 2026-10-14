import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Los hábitos del día como los muestra Mi Día (el `MYDAY` de la web): lo del servidor con lo que el cliente tocó y
/// todavía no salió encima.
public struct HabitosHoy: Equatable, Sendable {
    /// "entrene" | "descanso" | "falte" | nil.
    public var entrenamiento: String?
    public var comioSegunPlan: Bool?
    public var durmioBien: Bool?
    public var cardio: Bool?
    public var vasosAgua: Int

    public init(entrenamiento: String? = nil, comioSegunPlan: Bool? = nil, durmioBien: Bool? = nil, cardio: Bool? = nil, vasosAgua: Int = 0) {
        self.entrenamiento = entrenamiento; self.comioSegunPlan = comioSegunPlan; self.durmioBien = durmioBien
        self.cardio = cardio; self.vasosAgua = vasosAgua
    }

    init(_ h: HabitosDia?) {
        self.init(entrenamiento: h?.entrenamiento, comioSegunPlan: h?.comioSegunPlan, durmioBien: h?.durmioBien, cardio: h?.cardio,
                  vasosAgua: h?.vasosAgua ?? 0)
    }

    /// `_valorHabito`: el valor como viaja en la cola (texto) llevado a su tipo.
    mutating func aplicar(campo: String, valor: JSONValue?) {
        let texto = Escrituras.stringJS(valor)
        switch campo {
        case "vasos_agua": vasosAgua = (Double(JS.trim(texto)) ?? 0).enteroTruncado
        case "entrenamiento": entrenamiento = (texto == "null" || texto.isEmpty) ? nil : texto
        case "comio_segun_plan": comioSegunPlan = Self.booleano(texto)
        case "durmio_bien": durmioBien = Self.booleano(texto)
        case "cardio": cardio = Self.booleano(texto)
        default: break
        }
    }

    private static func booleano(_ t: String) -> Bool? { t == "null" ? nil : t == "true" }
}

/// Un check de la semana como lo ve el cliente: el guardado (o el optimista recién mandado).
public struct Checkin: Equatable, Sendable {
    public var valores: [String: Int]
    public var nota: String
    public init(valores: [String: Int] = [:], nota: String = "") { self.valores = valores; self.nota = nota }
}

/// Revisión (lo semanal: check, peso, fotos) y Mi Día (lo diario: entrené/descansé/falté, hábitos, agua, racha,
/// adherencia de 30 días). Todo lo que escribe el cliente sale por la cola con la clave de la web, y lo pendiente gana
/// sobre lo que trae el servidor (DIA-06).
@MainActor @Observable
public final class ModeloRevision {
    public private(set) var habitos = HabitosHoy()
    public private(set) var racha = 0
    /// `ultimo_dia_valido` de `get_streak` (YYYY-MM-DD): "Último día válido: martes, 21 de julio" con 2 días o más.
    public private(set) var ultimoDiaValido: String?
    public private(set) var miDiaCargado = false
    /// Mis últimos 30 días: se trae al abrirla.
    public private(set) var adherencia: [DiaAdherencia]?
    public private(set) var checkin: Checkin?
    /// Las filas de salud de los últimos 60 días (peso de la card y, más adelante, salud y recuperación).
    public private(set) var salud: [FilaSalud] = []
    public private(set) var fecha = FechaLocal.hoy()
    /// El lunes de la semana de `fecha`: el check es de esa semana (las vistas vacían su borrador cuando cambia).
    public var semana: String { FotosProgreso.lunes(fecha) }
    /// De qué día son los hábitos y de qué semana el check que hay en memoria. Lo de ayer no sirve ni como base: un
    /// toque sobre los 8 vasos de ayer encolaba 9 para hoy (revisión del 14-oct, hallazgos 3 y 4).
    @ObservationIgnored private var diaDeLosHabitos: String?
    @ObservationIgnored private var semanaDelCheck: String?

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored private var esperaAgua: Task<Void, Never>?
    /// El día de hoy (los tests lo fijan para simular la medianoche con la app abierta).
    @ObservationIgnored var diaDeHoy: @Sendable () -> String = { FechaLocal.hoy() }

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?) {
        self.cliente = cliente; self.token = token; self.outbox = outbox
    }

    private var t: JSONValue { .texto(token) }

    // MARK: - Mi Día

    /// `loadMyday`: hábitos de hoy y racha. Sin red quedan los de hoy si ya estaban; los de otro día no (la web
    /// vacía `MYDAY`): se puede marcar igual y sale por la cola. Lo pendiente de hoy se pinta encima.
    public func cargarMiDia() async {
        fecha = diaDeHoy()
        let hoy = fecha
        if diaDeLosHabitos != hoy { habitos = HabitosHoy() }
        diaDeLosHabitos = hoy
        async let h = cliente.filas("mypump_get_habitos_dia", ["p_token": t, "p_fecha": .texto(hoy)], como: HabitosDia.self)
        async let r = cliente.filas("mypump_get_streak", ["p_token": t], como: Racha.self)
        let (rh, rr) = await (h, r)
        if case .success(let filas) = rh, diaDeHoy() == hoy { habitos = HabitosHoy(filas.first) }
        if case .success(let filas) = rr { racha = filas.first?.streak ?? 0; ultimoDiaValido = filas.first?.ultimoDiaValido }
        await aplicarPendientes()
        miDiaCargado = true
    }

    /// Entrené / descansé / falté y los hábitos de sí o no: tocar lo que ya está lo borra (nil).
    public func tocar(campo: String, valor: String) async {
        let actual: String? = switch campo {
        case "entrenamiento": habitos.entrenamiento
        case "comio_segun_plan": habitos.comioSegunPlan.map { $0 ? "true" : "false" }
        case "durmio_bien": habitos.durmioBien.map { $0 ? "true" : "false" }
        case "cardio": habitos.cardio.map { $0 ? "true" : "false" }
        default: nil
        }
        await setHabito(campo: campo, valor: actual == valor ? nil : valor)
    }

    /// `setHabito`: optimista y por la cola (gana el último por campo y fecha).
    public func setHabito(campo: String, valor: String?) async {
        let v: JSONValue = valor.map { .texto($0) } ?? .null
        // La fecha es la de AHORA (la app pudo quedar abierta de un día para otro), como `hoyLocal()` en la web.
        let fecha = diaDeHoy()
        habitos.aplicar(campo: campo, valor: v)
        _ = await outbox?.encolar("habito", .objeto(["fecha": .texto(fecha), "campo": .texto(campo), "valor": v]),
                                  dedupeKey: "habito|\(fecha)|\(campo)")
        if ["entrenamiento", "comio_segun_plan", "durmio_bien"].contains(campo) {
            await outbox?.drenar()
            if case .success(let filas) = await cliente.filas("mypump_get_streak", ["p_token": t], como: Racha.self) {
                racha = filas.first?.streak ?? racha
                if let f = filas.first { ultimoDiaValido = f.ultimoDiaValido }
            }
        }
    }

    /// `cambiarAgua`: 0 a 12 vasos, se ve al instante y se guarda 600 ms después del último toque.
    public func cambiarAgua(_ delta: Int) {
        let nuevo = max(0, min(12, habitos.vasosAgua + delta))
        guard nuevo != habitos.vasosAgua else { return }
        habitos.vasosAgua = nuevo
        esperaAgua?.cancel()
        let dia = diaDeHoy()
        esperaAgua = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self else { return }
            _ = await self.outbox?.encolar("habito", .objeto(["fecha": .texto(dia), "campo": .texto("vasos_agua"), "valor": .texto(String(nuevo))]),
                                           dedupeKey: "habito|\(dia)|vasos_agua")
        }
    }

    /// "Mis últimos 30 días".
    public func cargarAdherencia() async {
        if case .success(let filas) = await cliente.filas("mypump_get_adherencia_30d", ["p_token": t], como: DiaAdherencia.self) {
            adherencia = filas
        }
    }

    private func aplicarPendientes() async {
        let prefijo = "habito|\(diaDeHoy())|"
        for (k, op) in await outbox?.pendientesPorClave() ?? [:] where k.hasPrefix(prefijo) {
            habitos.aplicar(campo: String(k.dropFirst(prefijo.count)), valor: op.payload["valor"])
        }
    }

    // MARK: - Revisión

    /// `loadRevision` + `loadSalud`: el check de la semana y 60 días de salud (para el peso).
    public func cargarRevision() async {
        fecha = diaDeHoy()
        // Semana nueva: el check de la anterior no es el de esta, haya red o no (la web lo vacía).
        if semanaDelCheck != semana { checkin = nil }
        semanaDelCheck = semana
        async let c = cliente.filas("mypump_get_checkin_semana", ["p_token": t, "p_fecha": .texto(fecha)], como: CheckinSemana.self)
        let desde = DiaCalendario.numero(fecha).map { DiaCalendario.texto($0 - 59) } ?? fecha
        async let s = cliente.filas("mypump_get_salud", ["p_token": t, "p_desde": .texto(desde), "p_hasta": .texto(fecha)], como: FilaSalud.self)
        let (rc, rs) = await (c, s)
        if case .success(let filas) = rc {
            checkin = filas.first.map { f in
                var v: [String: Int] = [:]
                v["energia"] = f.energia; v["descanso"] = f.descanso; v["hambre"] = f.hambre; v["adherencia"] = f.adherencia
                return Checkin(valores: v, nota: f.nota ?? "")
            }
        }
        if case .success(let filas) = rs {
            salud = filas
            // Un peso de hoy que todavía no salió gana sobre lo del servidor.
            if let op = await outbox?.pendientesPorClave()["peso_\(fecha)"], let v = op.payload["valor"]?.comoNumero {
                ponerPesoDeHoy(v)
            }
        }
        // Un check de esta semana que todavía no salió también (se mandó sin señal): si no, se vería sin enviar.
        await aplicarCheckPendiente()
    }

    private func aplicarCheckPendiente() async {
        let semana = semana
        let pendientes = (await outbox?.pendientesPorClave() ?? [:]).filter { k, op in
            k.hasPrefix("checkin_") && op.payload["fecha"]?.comoTexto.map(FotosProgreso.lunes) == semana
        }
        guard let op = pendientes.values.max(by: { $0.ts < $1.ts }), let d = op.payload["datos"] else { return }
        var v: [String: Int] = [:]
        for m in CheckinSemanal.metricas { if let n = d[m.clave]?.comoNumero { v[m.clave] = n.enteroTruncado } }
        checkin = Checkin(valores: v, nota: d["nota"]?.comoTexto ?? "")
    }

    /// El check está enviado si tiene energía (como la web: `checkin.energia`).
    public var checkinEnviado: Bool { (checkin?.valores["energia"] ?? 0) > 0 }

    /// "Enviar mi check": exige las cuatro escalas; optimista y por la cola (uno por semana: el servidor lo ancla al
    /// lunes ISO).
    public func enviarCheckin(_ c: Checkin) async -> String? {
        if let faltan = CheckinSemanal.faltan(c.valores) { return faltan }
        let fecha = diaDeHoy()
        let nota = c.nota.trimmingCharacters(in: .whitespacesAndNewlines)
        checkin = Checkin(valores: c.valores, nota: nota)
        semanaDelCheck = FotosProgreso.lunes(fecha)
        var datos: [String: JSONValue] = ["nota": .texto(nota)]
        for m in CheckinSemanal.metricas { datos[m.clave] = .numero(Double(c.valores[m.clave] ?? 0)) }
        _ = await outbox?.encolar("checkin", .objeto(["fecha": .texto(fecha), "datos": .objeto(datos)]), dedupeKey: "checkin_\(fecha)")
        return nil
    }

    public var serieDePeso: [PesoCorporal.Punto] { PesoCorporal.serie(salud) }

    /// Guardar el peso de hoy (30-300 kg). Devuelve false si el valor no es válido.
    @discardableResult
    public func guardarPeso(_ texto: String) async -> Bool {
        guard let valor = PesoCorporal.leer(texto) else { return false }
        let fecha = diaDeHoy()
        ponerPesoDeHoy(valor)
        _ = await outbox?.encolar("peso", .objeto(["fecha": .texto(fecha), "valor": .numero(valor)]), dedupeKey: "peso_\(fecha)")
        return true
    }

    private func ponerPesoDeHoy(_ valor: Double) {
        let hoy = diaDeHoy()
        salud.removeAll { $0.tipo == "peso_kg" && $0.fecha == hoy && $0.fuente == "manual" }
        let fila: JSONValue = .objeto(["fecha": .texto(hoy), "tipo": .texto("peso_kg"), "valor": .numero(valor), "fuente": .texto("manual")])
        if let f = try? JSONDecoder().decode(FilaSalud.self, from: JSONEncoder().encode(fila)) { salud.append(f) }
    }
}
