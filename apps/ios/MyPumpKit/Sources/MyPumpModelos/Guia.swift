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
    /// La fase de la guía (2.2.0): `1` o `2` (la guía v2, con la tanda nueva). Si falta, 1.
    public var fase: Int
    /// Cuándo se aprobó la última tanda nueva (timestamptz ISO). nil = no hay novedad (servidor viejo o fase 1).
    public var novedadEn: String?
    /// «Lo que más te importa». Opcional: sin el campo, o con el texto en blanco, nil y la guía de siempre.
    public var dolor: DolorGuia?

    public init(ok: Bool, nombrePila: String? = nil, fechaEntrega: String? = nil, clips: [ClipGuia] = [],
                dudasLlamada: [DudaLlamada] = [], suplementacion: SuplementacionGuia? = nil, fase: Int = 1, novedadEn: String? = nil,
                dolor: DolorGuia? = nil) {
        self.ok = ok; self.nombrePila = nombrePila; self.fechaEntrega = fechaEntrega; self.clips = clips
        self.dudasLlamada = dudasLlamada; self.suplementacion = suplementacion; self.fase = fase; self.novedadEn = novedadEn
        self.dolor = dolor
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

    enum CodingKeys: String, CodingKey {
        case ok, nombrePila = "nombre_pila", fechaEntrega = "fecha_entrega", clips, dudasLlamada = "dudas_llamada", suplementacion, fase
        case novedadEn = "novedad_en", dolor
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.booleano(.ok) ?? false
        nombrePila = c.texto(.nombrePila)
        fechaEntrega = c.texto(.fechaEntrega)
        // Sin id no se puede guardar el avance ni la duda: el clip no sirve.
        clips = c.lista(ClipGuia.self, .clips).filter { !$0.id.isEmpty }
        dudasLlamada = c.lista(DudaLlamada.self, .dudasLlamada).filter { !$0.texto.isEmpty }
        suplementacion = (try? c.decodeIfPresent(SuplementacionGuia.self, forKey: .suplementacion)) ?? nil
        // Lo de la 2.2.0, todo opcional: sin los campos (servidor viejo), la guía es la de la 2.1.0.
        fase = c.entero(.fase) == 2 ? 2 : 1
        novedadEn = c.texto(.novedadEn).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        // Un `dolor` de otro tipo o sin texto es lo mismo que no tenerlo.
        dolor = ((try? c.decodeIfPresent(DolorGuia.self, forKey: .dolor)) ?? nil).flatMap { $0.texto.isEmpty ? nil : $0 }
    }
}

/// El texto del caso (`dolor` en `entregas_app_get`): `titulo` opcional y `texto` con párrafos separados por una línea en
/// blanco; un párrafo «## Título» abre una parte aparte. Las reglas están en `ReglasDolor`.
public struct DolorGuia: Codable, Equatable, Sendable {
    public var titulo: String?
    public var texto: String

    public init(titulo: String? = nil, texto: String) { self.titulo = titulo; self.texto = texto }

    enum CodingKeys: String, CodingKey { case titulo, texto }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        titulo = c.texto(.titulo)
        texto = c.texto(.texto) ?? ""
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
    /// 2.2.0: es de la última tanda (va en el bloque «Novedad», arriba de todo).
    public var nuevo: Bool
    /// 2.2.0: cuenta para habilitar la agenda. nil = el servidor no mandó el campo (ahí cuentan todos los que tienen url,
    /// si ningún clip lo trae: `ReglasAgenda.obligatorios`).
    public var obligatorio: Bool?

    public init(id: String, titulo: String, url: URL?, minutos: Double, motivo: String? = nil, bloque: String? = nil,
                visto: Bool = false, segundos: Int = 0, duda: String? = nil, nuevo: Bool = false, obligatorio: Bool? = nil) {
        self.id = id; self.titulo = titulo; self.url = url; self.minutos = minutos; self.motivo = motivo; self.bloque = bloque
        self.visto = visto; self.segundos = segundos; self.duda = duda; self.nuevo = nuevo; self.obligatorio = obligatorio
    }

    enum CodingKeys: String, CodingKey { case id, titulo, url, minutos, motivo, bloque, visto, segundos, duda, nuevo, obligatorio }

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
        nuevo = c.booleano(.nuevo) ?? false
        obligatorio = c.booleano(.obligatorio)
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
        // Como la web (`if (!it || !it.nombre) return`): sin nombre no va; un nombre en blanco sí (y su video también).
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
    /// Contrato 10 (`mypump_suplementacion`): `"todos"`, `"gym"`, `"descanso"` o los días de la semana. Un texto suelto
    /// queda como lista de uno; vacío = todos los días.
    public var dias: [String]
    /// La dosis anterior (con `sube`, `baja` o `cambia`).
    public var antes: String?
    /// El texto del cambio («de 3 a 5 g»).
    public var cambio: String?
    /// Qué buscar en la tienda.
    public var comprar: CompraSuplemento?
    /// Es un protector (un fármaco, `entregas_016`). Se muestra como los demás, pero no se marca «lo compré / lo estoy tomando».
    public var protector: Bool = false
    /// El `video_id` que este ítem saca de la lista y de los conteos, con la regla de `entregas_012` y de pack.html sobre los
    /// valores tal como vienen: nombre no vacío, estado distinto de «sale» y `video_id` no vacío. nil si no saca ninguno.
    public var nombraVideo: String? {
        guard !nombre.isEmpty, estado != "sale", let v = videoId, !v.isEmpty else { return nil }
        return v
    }

    public init(nombre: String, cantidad: String? = nil, momento: String? = nil, tomas: [TomaSuplemento] = [], nota: String? = nil,
                detalle: [String] = [], estado: String? = nil, opcional: Bool = false, porQue: String? = nil, videoId: String? = nil,
                dias: [String] = [], antes: String? = nil, cambio: String? = nil, comprar: CompraSuplemento? = nil) {
        self.nombre = nombre; self.cantidad = cantidad; self.momento = momento; self.tomas = tomas; self.nota = nota
        self.detalle = detalle; self.estado = estado; self.opcional = opcional; self.porQue = porQue; self.videoId = videoId
        self.dias = dias; self.antes = antes; self.cambio = cambio; self.comprar = comprar
    }

    enum CodingKeys: String, CodingKey {
        case nombre, cantidad, momento, tomas, nota, detalle, estado, opcional, porQue = "por_que", videoId = "video_id", dias, antes, cambio, comprar, protector
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tal como viene (como la web y `entregas_012`): un nombre en blanco no es un nombre vacío.
        nombre = c.texto(.nombre) ?? ""
        cantidad = c.texto(.cantidad)
        momento = c.texto(.momento)
        tomas = c.lista(TomaSuplemento.self, .tomas)
        nota = c.texto(.nota)
        detalle = (c.textos(.detalle) ?? []).filter { !$0.isEmpty }
        // Tal como viene: «sale» y «nuevo» se comparan exactos, como la web (`it.estado === 'sale'`).
        estado = c.texto(.estado)
        opcional = c.booleano(.opcional) ?? false
        porQue = c.texto(.porQue).flatMap { $0.isEmpty ? nil : $0 }
        videoId = c.texto(.videoId).flatMap { $0.isEmpty ? nil : $0 }
        dias = (c.textosTolerantes(.dias) ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        antes = c.texto(.antes).flatMap { $0.isEmpty ? nil : $0 }
        cambio = c.texto(.cambio).flatMap { $0.isEmpty ? nil : $0 }
        comprar = (try? c.decodeIfPresent(CompraSuplemento.self, forKey: .comprar)).flatMap { $0?.vacia == false ? $0 : nil }
        protector = c.booleano(.protector) ?? false
    }
}

/// `comprar` de un ítem: qué buscar, dónde y una aclaración. Un texto suelto se toma como `buscar`.
public struct CompraSuplemento: Codable, Equatable, Sendable {
    public var buscar: String?
    public var donde: String?
    public var nota: String?

    public init(buscar: String? = nil, donde: String? = nil, nota: String? = nil) { self.buscar = buscar; self.donde = donde; self.nota = nota }

    enum CodingKeys: String, CodingKey { case buscar, donde, nota }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            buscar = s.isEmpty ? nil : s; donde = nil; nota = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buscar = c.texto(.buscar).flatMap { $0.isEmpty ? nil : $0 }
        donde = c.texto(.donde).flatMap { $0.isEmpty ? nil : $0 }
        nota = c.texto(.nota).flatMap { $0.isEmpty ? nil : $0 }
    }

    public var vacia: Bool { buscar == nil && donde == nil && nota == nil }
}

/// Lo que devuelve `entregas_app_resumen` (`entregas_011`, y desde `entregas_014` también `fecha_entrega` y
/// `mostrar_tarjeta`): solo lee y no marca `abierto_en`. Es lo que usa la tarjeta de inicio, al abrir la app y al volver a
/// primer plano. Con token inválido, revocado o sin guía, `{"ok": false}` (y ahí no viene `mostrar_tarjeta`).
public struct ResumenGuia: Codable, Equatable, Sendable {
    public var ok: Bool
    public var total: Int
    public var vistos: Int
    /// Ya viene redondeado a un decimal.
    public var minutosRestantes: Double
    /// La de la videollamada, como en el get (timestamptz ISO o null). nil también si el servidor no la manda (la 012).
    public var fechaEntrega: String?
    /// Lo que dijo el servidor: `fecha_entrega` null o antes de las 48 h siguientes. nil = no vino (vuelta atrás a la 012):
    /// la app hace la cuenta con `fechaEntrega` (`ReglasGuia.mostrarTarjeta`).
    public var mostrarTarjetaServidor: Bool?
    /// 2.2.0, opcional: cuándo se aprobó la última tanda nueva (como en el get). Hace reaparecer la tarjeta ocultada.
    public var novedadEn: String?
    /// 2.2.0, opcional: la reserva de la entrega (`{inicio, fin, estado, meet_url}`), para el «Entrar» de la tarjeta sin
    /// pedir el get.
    public var reserva: ReservaAgenda?
    /// 2.2.0, opcionales: el avance de la tanda nueva, para la tarjeta «NOVEDAD EN TU GUÍA».
    public var nuevosTotal: Int?
    public var nuevosVistos: Int?

    public init(ok: Bool, total: Int = 0, vistos: Int = 0, minutosRestantes: Double = 0, fechaEntrega: String? = nil,
                mostrarTarjetaServidor: Bool? = nil, novedadEn: String? = nil, reserva: ReservaAgenda? = nil,
                nuevosTotal: Int? = nil, nuevosVistos: Int? = nil) {
        self.ok = ok; self.total = total; self.vistos = vistos; self.minutosRestantes = minutosRestantes
        self.fechaEntrega = fechaEntrega; self.mostrarTarjetaServidor = mostrarTarjetaServidor
        self.novedadEn = novedadEn; self.reserva = reserva; self.nuevosTotal = nuevosTotal; self.nuevosVistos = nuevosVistos
    }

    public init(json: JSONValue) {
        guard case .objeto = json, let d = try? JSONEncoder().encode(json), let r = try? JSONDecoder().decode(ResumenGuia.self, from: d) else {
            self.init(ok: false)
            return
        }
        self = r
    }

    enum CodingKeys: String, CodingKey {
        case ok, total, vistos, minutosRestantes = "minutos_restantes", fechaEntrega = "fecha_entrega", mostrarTarjetaServidor = "mostrar_tarjeta"
        case novedadEn = "novedad_en", reserva, nuevosTotal = "nuevos_total", nuevosVistos = "nuevos_vistos"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.booleano(.ok) ?? false
        total = max(0, c.entero(.total) ?? 0)
        vistos = min(max(0, c.entero(.vistos) ?? 0), max(0, c.entero(.total) ?? 0))
        let m = c.decimal(.minutosRestantes) ?? 0
        minutosRestantes = m.isFinite && m > 0 ? m : 0
        fechaEntrega = c.texto(.fechaEntrega).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        // Se lee primero ok: con false no hay tarjeta ni fila, venga lo que venga.
        mostrarTarjetaServidor = ok ? c.booleano(.mostrarTarjetaServidor) : nil
        novedadEn = ok ? c.texto(.novedadEn).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } : nil
        reserva = ok ? ((try? c.decodeIfPresent(ReservaAgenda.self, forKey: .reserva)) ?? nil) : nil
        let nt = ok ? c.entero(.nuevosTotal).map { max(0, $0) } : nil
        nuevosTotal = nt
        nuevosVistos = nt.flatMap { t in c.entero(.nuevosVistos).map { min(max(0, $0), t) } }
    }

    /// Hay guía para mostrar la tarjeta: `ok` y al menos un video.
    public var hayGuia: Bool { ok && total > 0 }
}
