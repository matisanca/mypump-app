import Foundation

/// «Tu cambio» (2.3.0, detrás de `check_guiado`): la foto de la semana 1 al lado de la última, por pose, siempre a la vista
/// en Revisión. Pedido de Mati del 11/11: «está bueno que la gente pueda ver siempre ahí el cambio que está haciendo».
///
/// - La semana 1 es la foto más vieja de esa pose: la de inicio (las fotos de inicio guiadas) si es de esa semana o de
///   antes; si no, la de progreso más vieja. Empate de semana: gana la de inicio.
/// - La última es la foto de progreso más nueva de esa pose, y tiene que ser de una semana posterior a la semana 1.
/// - El par aparece desde que hay dos semanas distintas con alguna foto (contando la de inicio), sin esperar a las 4 del
///   comparador de siempre. Antes: el texto de espera y la foto que haya.
/// - El pie es el del comparador de siempre (`FotosProgreso.resumenComparador`): «8 semanas · -2,4 kg».
/// Los casos están en `apps/shared/vectores/tucambio.json` (los corren iOS, Android y la web).
public enum TuCambio {
    public static let titulo = "Tu cambio"
    public static let textoEspera = "Tu cambio se va a ver acá desde tu segunda semana de fotos"
    public static let rotuloAntes = "Semana 1"
    public static let rotuloEstaSemana = "Esta semana"
    public static let botonVer = "Ver mis fotos"
    /// La pantalla «Listo» del check guiado, arriba del par de frente.
    public static let listoTitulo = "Tu cambio hasta hoy"
    public static let poseInicial = "frente"

    public enum Modo: String, Sendable { case espera, par }
    public enum Origen: String, Sendable { case inicio, progreso }

    public struct Foto: Equatable, Sendable {
        public let origen: Origen
        public let semana: String
        public init(origen: Origen, semana: String) { self.origen = origen; self.semana = semana }
    }

    public struct Vista: Equatable, Sendable {
        public let modo: Modo
        /// La pose que se muestra (en espera puede no ser la elegida: la que tenga foto).
        public let pose: String
        public let antes: Foto?
        public let despues: Foto?
        /// Solo en espera.
        public let texto: String?
        /// Solo con el par completo.
        public let pie: String?
        public let rotuloAntes: String
        public let rotuloDespues: String
        public let accesibleAntes: String
        public let accesibleDespues: String
    }

    /// `fotos`: las de progreso (las del servidor y las que esperan subir), como (semana, pose). `inicio`: las fotos de
    /// inicio del cuerpo, pose → fecha local en que se sacó (AAAA-MM-DD). `semanaActual`: el lunes de esta semana.
    public static func vista(fotos: [(semana: String, pose: String)], inicio: [String: String], semanaActual: String,
                             pose elegida: String, peso: [PesoCorporal.Punto]) -> Vista {
        let poses = FotosProgreso.poses.map(\.clave)
        let elegida = poses.contains(elegida) ? elegida : poseInicial
        let semanasInicio = inicio.filter { poses.contains($0.key) }.mapValues { FotosProgreso.lunes($0) }
        let momentos = Set(fotos.filter { poses.contains($0.pose) }.map(\.semana)).union(semanasInicio.values)

        func semanasDe(_ p: String) -> [String] { Array(Set(fotos.filter { $0.pose == p }.map(\.semana))).sorted() }

        func primera(_ p: String) -> Foto? {
            let deProgreso = semanasDe(p).first
            if let s = semanasInicio[p], deProgreso.map({ s <= $0 }) ?? true { return Foto(origen: .inicio, semana: s) }
            return deProgreso.map { Foto(origen: .progreso, semana: $0) }
        }

        guard momentos.count >= 2 else {
            // Una sola semana (o ninguna): el texto de espera y la foto que haya, de la pose elegida o de la primera que tenga.
            let orden = [elegida] + poses.filter { $0 != elegida }
            let p = orden.first { primera($0) != nil } ?? elegida
            return Vista(modo: .espera, pose: p, antes: primera(p), despues: nil, texto: textoEspera, pie: nil,
                         rotuloAntes: rotuloAntes, rotuloDespues: "", accesibleAntes: accesible(rotuloAntes), accesibleDespues: "")
        }

        let antes = primera(elegida)
        let despues = antes.flatMap { a in semanasDe(elegida).last.flatMap { $0 > a.semana ? Foto(origen: .progreso, semana: $0) : nil } }
        let pie = antes.flatMap { a in despues.map { FotosProgreso.resumenComparador(primera: a.semana, ultima: $0.semana, peso: peso) } }
        let rotuloDespues = rotulo(despues?.semana ?? semanaActual, semanaActual: semanaActual)
        return Vista(modo: .par, pose: elegida, antes: antes, despues: despues, texto: nil, pie: pie,
                     rotuloAntes: rotuloAntes, rotuloDespues: rotuloDespues,
                     accesibleAntes: accesible(rotuloAntes, falta: antes == nil ? elegida : nil),
                     accesibleDespues: accesible(rotuloDespues, falta: despues == nil ? elegida : nil))
    }

    /// «Esta semana» o «Semana del 12 de octubre».
    public static func rotulo(_ semana: String, semanaActual: String) -> String {
        semana == semanaActual ? rotuloEstaSemana : "Semana del \(fecha(semana))"
    }

    /// «Foto de la semana 1», «Foto de esta semana», «Foto de la semana del 12 de octubre»; sin foto, «…, sin foto de perfil».
    public static func accesible(_ rotulo: String, falta pose: String? = nil) -> String {
        let base = rotulo == rotuloEstaSemana ? "Foto de esta semana" : "Foto de la \(rotulo.prefix(1).lowercased())\(rotulo.dropFirst())"
        return pose.map { "\(base), \(sinFoto($0).prefix(1).lowercased())\(sinFoto($0).dropFirst())" } ?? base
    }

    /// Lo que dice el marco vacío: «Sin foto de perfil».
    public static func sinFoto(_ pose: String) -> String {
        "Sin foto de \((FotosProgreso.poses.first { $0.clave == pose }?.etiqueta ?? pose).lowercased())"
    }

    private static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                                "octubre", "noviembre", "diciembre"]

    /// «12 de octubre» (sin depender del idioma del teléfono).
    public static func fecha(_ dia: String) -> String {
        let partes = dia.split(separator: "-")
        guard partes.count == 3, let m = Int(partes[1]), let d = Int(partes[2]), (1...12).contains(m) else { return dia }
        return "\(d) de \(meses[m - 1])"
    }

    /// La fecha local (AAAA-MM-DD) de un `tomada_en` del servidor (ISO 8601 con zona). Sin zona o ilegible: sus 10 primeros caracteres.
    public static func fechaLocal(_ iso: String, zona: TimeZone = .current) -> String? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        guard let d = f.date(from: iso) ?? g.date(from: iso) else {
            let p = String(iso.prefix(10))
            return p.count == 10 && DiaCalendario.numero(p) != nil ? p : nil
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.year, .month, .day], from: d)
        guard let y = c.year, let m = c.month, let dd = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, dd)
    }
}
