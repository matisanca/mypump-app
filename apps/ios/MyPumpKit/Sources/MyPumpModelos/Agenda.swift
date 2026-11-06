import Foundation

// La agenda de la entrega al final de «Tu guía» (2.2.0). Contrato de la obra de entregas (`entregas_021_agenda.sql`):
// - `entregas_app_agenda(p_token)` → `{ok, autorizada, habilitada, faltan, zona, franjas: [{id, inicio, fin}], reserva}`.
// - `entregas_app_reservar(p_token, p_franja, p_id)` → `{ok, reserva}` o `{ok: false, motivo}`, idempotente por `p_id`.
// El servidor decide: la app no calcula franjas ni habla con Google. Todo tolerante, como la guía: un campo que falta o
// viene con otro tipo no rompe el resto (una franja rota se descarta, no la agenda).

/// Un horario libre para la entrega. Los horarios y la duración los decide el servidor (hoy 10:00 o 14:00 de Argentina,
/// 2 h; pueden cambiar sin tocar la app). Las horas quedan como vinieron (ISO con zona) y las lee `ReglasAgenda`.
public struct FranjaAgenda: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var inicio: String
    public var fin: String

    public init(id: String, inicio: String, fin: String) { self.id = id; self.inicio = inicio; self.fin = fin }

    enum CodingKeys: String, CodingKey { case id, inicio, fin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        inicio = c.texto(.inicio)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        fin = c.texto(.fin)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Sin id no se puede reservar; sin horas no se puede mostrar.
        guard !id.isEmpty, !inicio.isEmpty, !fin.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "franja incompleta"))
        }
    }
}

/// La reserva del cliente: `pendiente` (el daemon de la Mini todavía no creó el evento), `confirmada` (con el link de
/// Meet) o `fallo` (`motivo: tomada|error`: se eligió otra).
public struct ReservaAgenda: Codable, Equatable, Sendable {
    public enum Estado: String, Codable, Sendable { case pendiente, confirmada, fallo }

    /// El `p_id` de la reserva. El resumen no lo manda.
    public var id: String?
    public var inicio: String
    public var fin: String
    public var estado: Estado
    /// Solo https (lo que no lo es no se abre).
    public var meetUrl: URL?
    public var motivo: String?
    /// Cuándo entró Mati al Meet (lo carga el daemon de la Mini con la Meet API). Opcional: sin esto no hay botón para
    /// entrar hasta la hora de inicio (cambio de Mati del 6/11: el cliente nunca entra directo).
    public var salaAbiertaEn: String?

    public init(id: String? = nil, inicio: String, fin: String, estado: Estado, meetUrl: URL? = nil, motivo: String? = nil,
                salaAbiertaEn: String? = nil) {
        self.id = id; self.inicio = inicio; self.fin = fin; self.estado = estado; self.meetUrl = meetUrl; self.motivo = motivo
        self.salaAbiertaEn = salaAbiertaEn
    }

    enum CodingKeys: String, CodingKey { case id, inicio, fin, estado, meetUrl = "meet_url", motivo, salaAbiertaEn = "sala_abierta_en" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id).flatMap { $0.isEmpty ? nil : $0 }
        inicio = c.texto(.inicio)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        fin = c.texto(.fin)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Un estado que no se conoce (uno futuro) no se adivina: la reserva no se muestra.
        guard let e = c.texto(.estado).flatMap({ Estado(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }),
              !inicio.isEmpty, !fin.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "reserva incompleta"))
        }
        estado = e
        meetUrl = c.texto(.meetUrl).flatMap { s in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: t), u.scheme?.lowercased() == "https", u.host?.isEmpty == false else { return nil }
            return u
        }
        motivo = c.texto(.motivo).flatMap { $0.isEmpty ? nil : $0 }
        salaAbiertaEn = c.texto(.salaAbiertaEn).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// La reserva sigue en pie (no se eligen otras franjas).
    public var vigente: Bool { estado == .pendiente || estado == .confirmada }
}

/// Lo que devuelve `entregas_app_agenda`. Con `ok: false` (`token` o `sin_guia`), con `false`, `null` o cualquier otra
/// cosa, no se muestra la agenda.
public struct AgendaGuia: Codable, Equatable, Sendable {
    public var ok: Bool
    public var motivo: String?
    /// El punto de control (E10): Mati dio el OK de horarios de este cliente. Si falta (servidor viejo), false.
    public var autorizada: Bool
    /// `autorizada` y todos los obligatorios vistos (lo cuenta el servidor).
    public var habilitada: Bool
    /// Cuántos obligatorios faltan según el servidor. nil si no vino.
    public var faltan: Int?
    /// La zona de los horarios (la de Mati). Informativa: las horas ya traen su zona.
    public var zona: String?
    public var franjas: [FranjaAgenda]
    public var reserva: ReservaAgenda?
    /// Desde cuántos minutos antes del inicio aparece la entrega en Entreno (spec §7: lo edita Mati). nil: los 30 de la app.
    public var avisoMin: Int?
    /// Los textos que Mati edita (`clave → texto`, spec §7): pisan los de la app. Solo los que vienen como texto no vacío.
    public var textos: [String: String]

    public init(ok: Bool, motivo: String? = nil, autorizada: Bool = false, habilitada: Bool = false, faltan: Int? = nil, zona: String? = nil,
                franjas: [FranjaAgenda] = [], reserva: ReservaAgenda? = nil, avisoMin: Int? = nil, textos: [String: String] = [:]) {
        self.ok = ok; self.motivo = motivo; self.autorizada = autorizada; self.habilitada = habilitada; self.faltan = faltan
        self.zona = zona; self.franjas = franjas; self.reserva = reserva; self.avisoMin = avisoMin; self.textos = textos
    }

    public init(json: JSONValue) {
        guard case .objeto = json, let d = try? JSONEncoder().encode(json), let a = try? JSONDecoder().decode(AgendaGuia.self, from: d) else {
            self.init(ok: false)
            return
        }
        self = a
    }

    enum CodingKeys: String, CodingKey { case ok, motivo, autorizada, habilitada, faltan, zona, franjas, reserva, avisoMin = "aviso_min", textos }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.booleano(.ok) ?? false
        motivo = c.texto(.motivo)
        autorizada = c.booleano(.autorizada) ?? false
        // Sin autorización no hay agenda habilitada, diga lo que diga el campo.
        habilitada = autorizada && (c.booleano(.habilitada) ?? false)
        faltan = c.entero(.faltan).map { max(0, $0) }
        zona = c.texto(.zona).flatMap { $0.isEmpty ? nil : $0 }
        reserva = (try? c.decodeIfPresent(ReservaAgenda.self, forKey: .reserva)) ?? nil
        // Las franjas solo valen con la agenda habilitada y sin una reserva vigente (como dice el contrato).
        let fs = c.lista(FranjaAgenda.self, .franjas)
        var vistas = Set<String>()
        franjas = habilitada && reserva?.vigente != true ? fs.filter { vistas.insert($0.id).inserted } : []
        // Hasta un día antes; lo que no tiene sentido queda en los 30 de la app.
        avisoMin = c.entero(.avisoMin).flatMap { (0...1440).contains($0) ? $0 : nil }
        let crudos = (try? c.decodeIfPresent([String: JSONValue].self, forKey: .textos)) ?? nil
        textos = (crudos ?? [:]).reduce(into: [:]) { r, par in
            if case .texto(let t) = par.value, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { r[par.key] = t }
        }
    }
}
