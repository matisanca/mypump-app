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
        case "vasos_agua": vasosAgua = Int(Double(texto) ?? 0)
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
    public private(set) var miDiaCargado = false
    /// Mis últimos 30 días: se trae al abrirla.
    public private(set) var adherencia: [DiaAdherencia]?
    public private(set) var checkin: Checkin?
    /// Las filas de salud de los últimos 60 días (peso de la card y, más adelante, salud y recuperación).
    public private(set) var salud: [FilaSalud] = []
    public private(set) var fecha = FechaLocal.hoy()

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored private var esperaAgua: Task<Void, Never>?

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?) {
        self.cliente = cliente; self.token = token; self.outbox = outbox
    }

    private var t: JSONValue { .texto(token) }

    // MARK: - Mi Día

    /// `loadMyday`: hábitos de hoy y racha. Sin red quedan los de antes (o vacíos).
    public func cargarMiDia() async {
        fecha = FechaLocal.hoy()
        async let h = cliente.filas("mypump_get_habitos_dia", ["p_token": t, "p_fecha": .texto(fecha)], como: HabitosDia.self)
        async let r = cliente.filas("mypump_get_streak", ["p_token": t], como: Racha.self)
        let (rh, rr) = await (h, r)
        if case .success(let filas) = rh { habitos = HabitosHoy(filas.first) }
        if case .success(let filas) = rr { racha = filas.first?.streak ?? 0 }
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
        habitos.aplicar(campo: campo, valor: v)
        _ = await outbox?.encolar("habito", .objeto(["fecha": .texto(fecha), "campo": .texto(campo), "valor": v]),
                                  dedupeKey: "habito|\(fecha)|\(campo)")
        if ["entrenamiento", "comio_segun_plan", "durmio_bien"].contains(campo) {
            await outbox?.drenar()
            if case .success(let filas) = await cliente.filas("mypump_get_streak", ["p_token": t], como: Racha.self) {
                racha = filas.first?.streak ?? racha
            }
        }
    }

    /// `cambiarAgua`: 0 a 12 vasos, se ve al instante y se guarda 600 ms después del último toque.
    public func cambiarAgua(_ delta: Int) {
        let nuevo = max(0, min(12, habitos.vasosAgua + delta))
        guard nuevo != habitos.vasosAgua else { return }
        habitos.vasosAgua = nuevo
        esperaAgua?.cancel()
        let dia = fecha
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
        let prefijo = "habito|\(fecha)|"
        for (k, op) in await outbox?.pendientesPorClave() ?? [:] where k.hasPrefix(prefijo) {
            habitos.aplicar(campo: String(k.dropFirst(prefijo.count)), valor: op.payload["valor"])
        }
    }

    // MARK: - Revisión

    /// `loadRevision` + `loadSalud`: el check de la semana y 60 días de salud (para el peso).
    public func cargarRevision() async {
        fecha = FechaLocal.hoy()
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
    }

    /// El check está enviado si tiene energía (como la web: `checkin.energia`).
    public var checkinEnviado: Bool { (checkin?.valores["energia"] ?? 0) > 0 }

    /// "Enviar mi check": exige las cuatro escalas; optimista y por la cola (uno por semana: el servidor lo ancla al
    /// lunes ISO).
    public func enviarCheckin(_ c: Checkin) async -> String? {
        if let faltan = CheckinSemanal.faltan(c.valores) { return faltan }
        let nota = c.nota.trimmingCharacters(in: .whitespacesAndNewlines)
        checkin = Checkin(valores: c.valores, nota: nota)
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
        ponerPesoDeHoy(valor)
        _ = await outbox?.encolar("peso", .objeto(["fecha": .texto(fecha), "valor": .numero(valor)]), dedupeKey: "peso_\(fecha)")
        return true
    }

    private func ponerPesoDeHoy(_ valor: Double) {
        let hoy = fecha
        salud.removeAll { $0.tipo == "peso_kg" && $0.fecha == hoy && $0.fuente == "manual" }
        let fila: JSONValue = .objeto(["fecha": .texto(hoy), "tipo": .texto("peso_kg"), "valor": .numero(valor), "fuente": .texto("manual")])
        if let f = try? JSONDecoder().decode(FilaSalud.self, from: JSONEncoder().encode(fila)) { salud.append(f) }
    }
}
