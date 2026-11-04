import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Un check de la semana como lo ve el cliente: el guardado (o el optimista recién mandado).
public struct Checkin: Equatable, Sendable {
    public var valores: [String: Int]
    public var nota: String
    public init(valores: [String: Int] = [:], nota: String = "") { self.valores = valores; self.nota = nota }
}

/// Revisión (lo semanal: el check y el peso). Todo lo que escribe el cliente sale por la cola con la clave de la web, y
/// lo pendiente gana sobre lo que trae el servidor. Mi Día (hábitos, agua, racha y adherencia) se sacó de la app en la
/// 2.1: las operaciones `habito` que hayan quedado en la cola salen igual (las ejecuta la cola, no este modelo).
@MainActor @Observable
public final class ModeloRevision {
    public private(set) var checkin: Checkin?
    /// Las filas de salud de los últimos 60 días (peso de la card y, más adelante, salud y recuperación).
    public private(set) var salud: [FilaSalud] = []
    public private(set) var fecha = FechaLocal.hoy()
    /// El lunes de la semana de `fecha`: el check es de esa semana (las vistas vacían su borrador cuando cambia).
    public var semana: String { FotosProgreso.lunes(fecha) }
    /// De qué semana es el check que hay en memoria: el de la semana pasada no sirve ni como base (revisión del 14-oct,
    /// hallazgo 4).
    @ObservationIgnored private var semanaDelCheck: String?

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let outbox: Outbox?
    /// El día de hoy (los tests lo fijan para simular la medianoche con la app abierta).
    @ObservationIgnored var diaDeHoy: @Sendable () -> String = { FechaLocal.hoy() }

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?) {
        self.cliente = cliente; self.token = token; self.outbox = outbox
    }

    private var t: JSONValue { .texto(token) }

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
