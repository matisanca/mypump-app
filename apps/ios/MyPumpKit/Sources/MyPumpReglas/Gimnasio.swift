import Foundation
import MyPumpModelos

/// «Gimnasio por fotos»: la lógica pura que comparten iOS y Android (`apps/shared/vectores/gimnasio.json`). El contrato con
/// el servidor está en `supabase/propuestas/nativa_gimnasio_fotos.sql` y `..._minivision.mjs`.
public enum Gimnasio {
    public struct Zona: Equatable, Sendable, Identifiable {
        public let clave: String
        public let nombre: String
        /// El consejo de esa zona: qué sacarle.
        public let pedido: String
        public var id: String { clave }
    }

    /// Las 10 zonas, en el orden del servidor. La foto siempre lleva zona.
    public static let zonas: [Zona] = [
        Zona(clave: "poleas", nombre: "Poleas", pedido: "Cada torre y cruce, entero. El peso máximo de la pila"),
        Zona(clave: "accesorios_polea", nombre: "Accesorios de polea", pedido: "Sogas, barras V, rectas, agarres, tobilleras, todos juntos en el piso o colgados"),
        Zona(clave: "piernas", nombre: "Máquinas de piernas", pedido: "Prensa, hack, péndulo, extensora, femorales, aductores, abductores, gemelos, hip thrust"),
        Zona(clave: "empuje", nombre: "Máquinas de empuje", pedido: "Pecho, inclinado, hombros, pec deck, fondos"),
        Zona(clave: "tiron", nombre: "Máquinas de tirón", pedido: "Dorsalera, remos, dominadas asistidas, bíceps, tríceps"),
        Zona(clave: "barras_racks", nombre: "Barras y racks", pedido: "Barras olímpicas y Z, smith, racks, paralelas, barra de dominadas"),
        Zona(clave: "discos", nombre: "Discos", pedido: "Todo el soporte, de cerca: que se lean los números. Incluí los más chicos"),
        Zona(clave: "mancuernas", nombre: "Mancuernas", pedido: "El rack entero, de punta a punta: que se lea hasta cuánto llega"),
        Zona(clave: "bancos", nombre: "Bancos", pedido: "Planos, regulables, Scott"),
        Zona(clave: "otros", nombre: "Otros", pedido: "Bandas, kettlebells, TRX, lo que haya"),
    ]
    public static let zonaOpcional = "otros"
    public static func nombreZona(_ clave: String) -> String { zonas.first { $0.clave == clave }?.nombre ?? clave }

    public static let topeFotos = 80
    public static let maxNota = 300
    public static let maxPx = 1600
    public static let calidad = 0.8
    public static let maxBytes = 8 * 1024 * 1024
    public static let kilosMaximo = 400.0

    // MARK: Zonas y tope

    /// Las zonas que todavía piden respuesta, en orden. La zona con foto no cuenta como «No hay». En una carga parcial no se
    /// exige ninguna.
    public static func zonasFaltantes(conFotos: Set<String>, noHay: Set<String>, modo: String = "completa") -> [String] {
        guard modo == "completa" else { return [] }
        return zonas.map(\.clave).filter { $0 != zonaOpcional && !conFotos.contains($0) && !noHay.contains($0) }
    }

    /// `true` si se puede enviar: la completa con todas las zonas respondidas; la parcial, con una foto nueva o algo que ya no está.
    public static func puedeEnviar(modo: String, conFotos: Set<String>, noHay: Set<String>, quitar: Set<String>) -> Bool {
        if modo == "completa" { return zonasFaltantes(conFotos: conFotos, noHay: noHay).isEmpty }
        return !conFotos.isEmpty || !quitar.isEmpty
    }

    /// Cuántas fotos entran todavía: lo que ya tiene el servidor más lo que espera subir, contra el tope de 80.
    public static func restan(enServidor: Int, enCola: Int) -> Int { max(0, topeFotos - enServidor - enCola) }
    public static func puedeAgregar(enServidor: Int, enCola: Int) -> Bool { restan(enServidor: enServidor, enCola: enCola) > 0 }

    public static func notaRecortada(_ s: String) -> String { String(s.prefix(maxNota)) }

    // MARK: Pantallas

    public enum Pantalla: String, Sendable { case inicio, zonas, recibido, preguntas, listo }

    /// Qué se ve al entrar. Un estado desconocido o `enviado` y parecidos: «Recibido». `reemplazado` no se muestra.
    public static func pantalla(abierta: String?, hayVigente: Bool) -> Pantalla {
        switch abierta {
        case nil, "reemplazado", "listo": return hayVigente ? .listo : .inicio
        case "borrador": return .zonas
        case "a_confirmar": return .preguntas
        default: return .recibido
        }
    }

    /// La tarjeta arriba en Entreno: mientras no haya gimnasio cargado, o si hay preguntas por contestar.
    public static func tarjetaVisible(habilitado: Bool, abierta: String?, hayVigente: Bool) -> Bool {
        guard habilitado else { return false }
        return !hayVigente || abierta == "a_confirmar"
    }

    /// La fila de Mis datos: una vez que ya hay gimnasio.
    public static func entradaVisible(habilitado: Bool, hayVigente: Bool) -> Bool { habilitado && hayVigente }

    // MARK: Cola de subida

    public enum Accion: String, Sendable { case ok, descartar, reintentar }
    public enum AvisoFoto: String, Sendable { case rechazada, tope }

    public struct Subida: Equatable, Sendable {
        public let accion: Accion
        public var refrescar = false
        public var aviso: AvisoFoto?
    }

    /// Qué hace la cola con la respuesta de `/gimnasio/upload`. Todo 4xx salvo 429 es definitivo; 5xx y 429, reintentar.
    public static func clasificarSubida(status: Int, ok: Bool) -> Subida {
        switch status {
        case 200..<300: return ok ? Subida(accion: .ok) : Subida(accion: .reintentar)
        case 429: return Subida(accion: .reintentar)
        case 403: return Subida(accion: .descartar)
        case 404, 409: return Subida(accion: .descartar, refrescar: true)
        case 413: return Subida(accion: .descartar, aviso: .tope)
        case 400..<500: return Subida(accion: .descartar, aviso: .rechazada)
        default: return Subida(accion: .reintentar)
        }
    }

    // MARK: Respuestas

    /// `true` si el valor sirve como respuesta a esa pregunta (lo que no sirve no se manda: queda dudoso y lo ve EDITOR).
    public static func respuestaValida(_ p: PreguntaGimnasio, _ v: JSONValue) -> Bool {
        if v == .texto("no_se") { return p.clase != .foto }
        switch p.clase {
        case .elegir:
            let validos = Set(p.opciones.map(\.valor))
            if p.multiple {
                guard case .lista(let l) = v else { return false }
                return l.allSatisfy { if case .texto(let s) = $0 { validos.contains(s) } else { false } }
            }
            if case .texto(let s) = v { return validos.contains(s) }
            return false
        case .numero:
            if case .numero(let n) = v { return n > 0 && n <= kilosMaximo }
            return false
        case .confirmar:
            guard case .objeto(let o) = v else { return false }
            let tipos = Set(p.items.map(\.tipo))
            return o.allSatisfy { k, x in tipos.contains(k) && (x == .texto("si") || x == .texto("no") || x == .texto("no_se")) }
        case .foto:
            return v == .texto("subida") || v == .texto("no_puedo")
        case .desconocida:
            return false
        }
    }

    /// Lo que se manda a `responder`: solo preguntas que existen y respuestas válidas. Puede quedar incompleto.
    public static func respuestasParaEnviar(_ preguntas: [PreguntaGimnasio], _ borrador: [String: JSONValue]) -> [String: JSONValue] {
        var r: [String: JSONValue] = [:]
        for p in preguntas { if let v = borrador[p.id], respuestaValida(p, v) { r[p.id] = v } }
        return r
    }

    /// Cuántas fotos faltan de las que pidió la ronda.
    public static func fotosPedidas(_ preguntas: [PreguntaGimnasio], _ borrador: [String: JSONValue]) -> Int {
        preguntas.filter { $0.clase == .foto && borrador[$0.id] == nil }.count
    }

    /// El número que escribe el alumno: admite coma; 0, negativos, más de 400 o texto, no sirven.
    public static func kilos(_ s: String) -> Double? {
        guard let n = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), n.isFinite, n > 0, n <= kilosMaximo else { return nil }
        return n
    }

    /// "12/11", en la hora del teléfono. nil si la fecha no se entiende.
    public static func fechaCorta(_ iso: String?, zona: TimeZone = .current) -> String? {
        guard var s = iso else { return nil }
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) { s.removeSubrange(r) }
        s = s.replacingOccurrences(of: " ", with: "T")
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: s) else { return nil }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zona
        let p = c.dateComponents([.day, .month], from: d)
        guard let dia = p.day, let mes = p.month else { return nil }
        return String(format: "%02d/%02d", dia, mes)
    }
}

// MARK: - Lo que contesta el servidor (decodificación tolerante: lo que falta es opcional, lo desconocido no rompe)

public struct OpcionGimnasio: Equatable, Sendable, Identifiable {
    public let valor: String
    public let texto: String
    public var id: String { valor }
}

public struct ItemGimnasio: Equatable, Sendable, Identifiable {
    public let tipo: String
    public let texto: String
    public let fotos: [String]
    public var id: String { tipo }
}

public struct PreguntaGimnasio: Equatable, Sendable, Identifiable {
    public enum Clase: String, Sendable { case elegir, numero, confirmar, foto, desconocida }
    public let id: String
    public let clase: Clase
    public let multiple: Bool
    public let zona: String?
    public let texto: String
    public let unidad: String?
    public let opciones: [OpcionGimnasio]
    public let items: [ItemGimnasio]
    public let fotos: [String]

    public init?(_ j: JSONValue) {
        guard let id = j["id"]?.comoTexto, !id.isEmpty,
              let texto = j["texto"]?.comoTexto ?? (j["clase"]?.comoTexto == "confirmar" ? TextosGimnasio.confirmarTarjeta : nil) else { return nil }
        self.id = id
        self.texto = texto
        clase = j["clase"]?.comoTexto.flatMap(Clase.init(rawValue:)) ?? .desconocida
        multiple = j["multiple"] == .bool(true)
        zona = j["zona"]?.comoTexto
        unidad = j["unidad"]?.comoTexto
        opciones = (j["opciones"]?.listaGim ?? []).compactMap { o in
            guard let v = o["valor"]?.comoTexto, let t = o["texto"]?.comoTexto else { return nil }
            return OpcionGimnasio(valor: v, texto: t)
        }
        items = (j["items"]?.listaGim ?? []).compactMap { o in
            guard let v = o["tipo"]?.comoTexto, let t = o["texto"]?.comoTexto else { return nil }
            return ItemGimnasio(tipo: v, texto: t, fotos: (o["fotos"]?.listaGim ?? []).compactMap(\.comoTexto))
        }
        fotos = (j["fotos"]?.listaGim ?? []).compactMap(\.comoTexto)
    }
}

public struct FotoGimnasio: Equatable, Sendable, Identifiable {
    public let id: String
    public let zona: String
    public let ronda: Int
    public init(id: String, zona: String, ronda: Int) { self.id = id; self.zona = zona; self.ronda = ronda }
}

public struct EquipoGimnasio: Equatable, Sendable {
    public let tipo: String
    public let nombre: String
    public let zona: String
    public let cantidad: Int
}

public struct CargaGimnasio: Equatable, Sendable {
    public let id: String
    public let estado: String
    public let modo: String
    public let resultado: String?
    public let publicadoEn: String?
    /// Las de clase desconocida no se muestran: una app vieja no puede contestarlas.
    public let preguntas: [PreguntaGimnasio]
    public var fotos: [FotoGimnasio]
    public let zonasNoHay: [String]
    public let equipos: [EquipoGimnasio]

    public init?(_ j: JSONValue?) {
        guard let j, let id = j["id"]?.comoTexto, let estado = j["estado"]?.comoTexto else { return nil }
        self.id = id
        self.estado = estado
        modo = j["modo"]?.comoTexto ?? "completa"
        resultado = j["resultado"]?.comoTexto
        publicadoEn = j["publicado_en"]?.comoTexto
        preguntas = (j["preguntas"]?.listaGim ?? []).compactMap(PreguntaGimnasio.init).filter { $0.clase != .desconocida }
        fotos = (j["fotos"]?.listaGim ?? []).compactMap { f in
            guard let i = f["id"]?.comoTexto, let z = f["zona"]?.comoTexto else { return nil }
            var ronda = 0
            if case .numero(let n)? = f["ronda"], let r = Int(exactly: n) { ronda = r }
            return FotoGimnasio(id: i, zona: z, ronda: ronda)
        }
        zonasNoHay = (j["zonas_no_hay"]?.listaGim ?? []).compactMap(\.comoTexto)
        equipos = (j["equipos"]?.listaGim ?? []).compactMap { e in
            guard let t = e["tipo"]?.comoTexto else { return nil }
            var cantidad = 1
            if case .numero(let n)? = e["cantidad"], n >= 1, let c = Int(exactly: n.rounded(.down)) { cantidad = c }
            return EquipoGimnasio(tipo: t, nombre: e["nombre"]?.comoTexto ?? t.replacingOccurrences(of: "_", with: " "),
                                  zona: e["zona"]?.comoTexto ?? Gimnasio.zonaOpcional, cantidad: cantidad)
        }
    }
}

public struct EstadoGimnasio: Equatable, Sendable {
    public var abierta: CargaGimnasio?
    public let vigente: CargaGimnasio?

    /// nil: no es una respuesta con `habilitado:true`.
    public init?(_ j: JSONValue) {
        guard j["habilitado"] == .bool(true) else { return nil }
        abierta = CargaGimnasio(j["abierta"])
        vigente = CargaGimnasio(j["vigente"])
    }
}

extension JSONValue {
    var listaGim: [JSONValue]? { if case .lista(let l) = self { l } else { nil } }
}
