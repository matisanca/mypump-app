import Foundation

/// «Tu guía»: lo que devuelve `entregas_app_get` (obra de entregas, `entregas_010_app`). Los videos cortos de Mati
/// antes de la videollamada, las dudas y la suplementación del cliente. Ver `docs/NATIVA_GUIA_IOS.md`.
///
/// Todo es tolerante: un campo que falta, viene null o con otro tipo no rompe el resto (un clip roto se descarta, no la
/// guía). Con un token inválido o sin página aprobada la base devuelve `{"ok": false}` o `false`: `ok` queda en false.
public struct Guia: Codable, Equatable, Sendable {
    public var ok: Bool
    public var nombrePila: String?
    /// ISO con zona, o solo la fecha. null en el flujo nuevo (la videollamada sin agendar).
    public var fechaEntrega: String?
    public var clips: [ClipGuia]
    public var dudasLlamada: [DudaLlamada]
    public var suplementacion: SuplementacionGuia?

    public init(ok: Bool, nombrePila: String? = nil, fechaEntrega: String? = nil, clips: [ClipGuia] = [],
                dudasLlamada: [DudaLlamada] = [], suplementacion: SuplementacionGuia? = nil) {
        self.ok = ok; self.nombrePila = nombrePila; self.fechaEntrega = fechaEntrega; self.clips = clips
        self.dudasLlamada = dudasLlamada; self.suplementacion = suplementacion
    }

    /// La respuesta de la base tal cual: un objeto, `false`, `null` o cualquier otra cosa (todo lo que no sea un objeto con
    /// `ok: true` es «no hay guía»).
    public init(json: JSONValue) {
        guard case .objeto = json, let d = try? JSONEncoder().encode(json), let g = try? JSONDecoder().decode(Guia.self, from: d) else {
            self.init(ok: false)
            return
        }
        self = g
    }

    enum CodingKeys: String, CodingKey { case ok, nombrePila = "nombre_pila", fechaEntrega = "fecha_entrega", clips, dudasLlamada = "dudas_llamada", suplementacion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.booleano(.ok) ?? false
        nombrePila = c.texto(.nombrePila)
        fechaEntrega = c.texto(.fechaEntrega)
        // Sin id no se puede guardar el avance ni la duda: el clip no sirve.
        clips = c.lista(ClipGuia.self, .clips).filter { !$0.id.isEmpty }
        dudasLlamada = c.lista(DudaLlamada.self, .dudasLlamada).filter { !$0.texto.isEmpty }
        suplementacion = (try? c.decodeIfPresent(SuplementacionGuia.self, forKey: .suplementacion)) ?? nil
    }
}

public struct ClipGuia: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var titulo: String
    /// MP4 público del bucket `videos-entrega`. Sin url, el video todavía se está subiendo (la fila se ve apagada).
    public var url: URL?
    public var minutos: Double
    /// «Para qué te sirve». Puede traer «indicación ||| motivo» (ver `ReglasGuia.partes`).
    public var motivo: String?
    public var bloque: String?
    public var visto: Bool
    public var segundos: Int
    /// Las dudas de este video, acumuladas con un salto de línea (hasta 3200 caracteres).
    public var duda: String?

    public init(id: String, titulo: String, url: URL?, minutos: Double, motivo: String? = nil, bloque: String? = nil,
                visto: Bool = false, segundos: Int = 0, duda: String? = nil) {
        self.id = id; self.titulo = titulo; self.url = url; self.minutos = minutos; self.motivo = motivo; self.bloque = bloque
        self.visto = visto; self.segundos = segundos; self.duda = duda
    }

    enum CodingKeys: String, CodingKey { case id, titulo, url, minutos, motivo, bloque, visto, segundos, duda }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id)?.trimmingCharacters(in: .whitespaces) ?? ""
        titulo = c.texto(.titulo) ?? ""
        url = c.texto(.url).flatMap { s in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let u = URL(string: t), let esquema = u.scheme?.lowercased(), esquema == "https" || esquema == "http" else { return nil }
            return u
        }
        let m = c.decimal(.minutos) ?? 0
        minutos = m.isFinite && m > 0 ? m : 0
        motivo = c.texto(.motivo)
        bloque = c.texto(.bloque)
        visto = c.booleano(.visto) ?? false
        let seg = c.decimal(.segundos) ?? 0
        segundos = seg.isFinite ? Int(min(36_000, max(0, seg))) : 0
        duda = c.texto(.duda).flatMap { $0.isEmpty ? nil : $0 }
    }
}

public struct DudaLlamada: Codable, Equatable, Sendable {
    public var texto: String
    public var en: String?

    public init(texto: String, en: String? = nil) { self.texto = texto; self.en = en }

    enum CodingKeys: String, CodingKey { case texto, en }

    public init(from decoder: Decoder) throws {
        // La web también acepta una lista de textos sueltos: se toleran las dos formas.
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            texto = s; en = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        texto = c.texto(.texto) ?? ""
        en = c.texto(.en)
    }
}

/// La forma del generador de PDF de Pump: los momentos del día (`dia`) y los ítems, cada uno en un momento o en varias
/// tomas. Lo muestra «Tu suplementación», agrupado por momento como «Tu día» del PDF.
public struct SuplementacionGuia: Codable, Equatable, Sendable {
    public var titulo: String?
    public var dia: [MomentoDia]
    public var items: [ItemSuplemento]
    public var sigueTexto: String?
    public var accion: String?

    public init(titulo: String? = nil, dia: [MomentoDia] = [], items: [ItemSuplemento] = [], sigueTexto: String? = nil, accion: String? = nil) {
        self.titulo = titulo; self.dia = dia; self.items = items; self.sigueTexto = sigueTexto; self.accion = accion
    }

    enum CodingKeys: String, CodingKey { case titulo, dia, items, sigueTexto = "sigue_texto", accion }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titulo = c.texto(.titulo)
        dia = c.lista(MomentoDia.self, .dia).filter { !$0.id.isEmpty }
        items = c.lista(ItemSuplemento.self, .items).filter { !$0.nombre.isEmpty }
        sigueTexto = c.texto(.sigueTexto).flatMap { $0.isEmpty ? nil : $0 }
        accion = c.texto(.accion).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// null, sin ítems o vacía: no se muestra.
    public var vacia: Bool { items.isEmpty }
}

public struct MomentoDia: Codable, Equatable, Sendable {
    public var id: String
    public var nombre: String?

    public init(id: String, nombre: String? = nil) { self.id = id; self.nombre = nombre }

    enum CodingKeys: String, CodingKey { case id, nombre }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.texto(.id) ?? ""
        nombre = c.texto(.nombre)
    }
}

public struct TomaSuplemento: Codable, Equatable, Sendable {
    public var momento: String?
    public var cantidad: String?
    public var nota: String?
    /// Una toma puede llamarse distinto que el ítem (el PDF lo permite).
    public var nombre: String?

    public init(momento: String?, cantidad: String? = nil, nota: String? = nil, nombre: String? = nil) {
        self.momento = momento; self.cantidad = cantidad; self.nota = nota; self.nombre = nombre
    }

    enum CodingKeys: String, CodingKey { case momento, cantidad, nota, nombre }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        momento = c.texto(.momento)
        cantidad = c.texto(.cantidad)
        nota = c.texto(.nota)
        nombre = c.texto(.nombre)
    }
}

public struct ItemSuplemento: Codable, Equatable, Sendable {
    public var nombre: String
    public var cantidad: String?
    public var momento: String?
    public var tomas: [TomaSuplemento]
    public var nota: String?
    /// Texto o lista de textos (con `*negrita*` como el PDF).
    public var detalle: [String]
    /// `sigue`, `nuevo`, `sale`… (como el PDF).
    public var estado: String?
    public var opcional: Bool
    public var porQue: String?
    /// El id de un clip del bloque «Tu suplementación»: el ítem muestra «Ver por qué».
    public var videoId: String?

    public init(nombre: String, cantidad: String? = nil, momento: String? = nil, tomas: [TomaSuplemento] = [], nota: String? = nil,
                detalle: [String] = [], estado: String? = nil, opcional: Bool = false, porQue: String? = nil, videoId: String? = nil) {
        self.nombre = nombre; self.cantidad = cantidad; self.momento = momento; self.tomas = tomas; self.nota = nota
        self.detalle = detalle; self.estado = estado; self.opcional = opcional; self.porQue = porQue; self.videoId = videoId
    }

    enum CodingKeys: String, CodingKey { case nombre, cantidad, momento, tomas, nota, detalle, estado, opcional, porQue = "por_que", videoId = "video_id" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nombre = c.texto(.nombre)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cantidad = c.texto(.cantidad)
        momento = c.texto(.momento)
        tomas = c.lista(TomaSuplemento.self, .tomas)
        nota = c.texto(.nota)
        detalle = (c.textos(.detalle) ?? []).filter { !$0.isEmpty }
        estado = c.texto(.estado)?.lowercased()
        opcional = c.booleano(.opcional) ?? false
        porQue = c.texto(.porQue).flatMap { $0.isEmpty ? nil : $0 }
        videoId = c.texto(.videoId).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Lo que devuelve `entregas_app_resumen` (`entregas_011`): solo lee y no marca `abierto_en`. Es lo que usa la tarjeta de
/// inicio, al abrir la app y al volver a primer plano. Con token inválido, revocado o sin guía, `{"ok": false}`.
public struct ResumenGuia: Codable, Equatable, Sendable {
    public var ok: Bool
    public var total: Int
    public var vistos: Int
    /// Ya viene redondeado a un decimal.
    public var minutosRestantes: Double

    public init(ok: Bool, total: Int = 0, vistos: Int = 0, minutosRestantes: Double = 0) {
        self.ok = ok; self.total = total; self.vistos = vistos; self.minutosRestantes = minutosRestantes
    }

    public init(json: JSONValue) {
        guard case .objeto = json, let d = try? JSONEncoder().encode(json), let r = try? JSONDecoder().decode(ResumenGuia.self, from: d) else {
            self.init(ok: false)
            return
        }
        self = r
    }

    enum CodingKeys: String, CodingKey { case ok, total, vistos, minutosRestantes = "minutos_restantes" }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.booleano(.ok) ?? false
        total = max(0, c.entero(.total) ?? 0)
        vistos = min(max(0, c.entero(.vistos) ?? 0), max(0, c.entero(.total) ?? 0))
        let m = c.decimal(.minutosRestantes) ?? 0
        minutosRestantes = m.isFinite && m > 0 ? m : 0
    }

    /// Hay guía para mostrar la tarjeta: `ok` y al menos un video.
    public var hayGuia: Bool { ok && total > 0 }
}
