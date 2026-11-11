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
    @ObservationIgnored let disco: Disco?
    /// El día de revisión del alumno (`mypump_get_revision_dia`, 1 = lunes … 7 = domingo): cuándo sale el aviso local. La
    /// semana no cambia por esto: sigue siendo de lunes a domingo. Lo elige el equipo; la app solo lo lee.
    public private(set) var revisionDia: Int
    /// El día de hoy (los tests lo fijan para simular la medianoche con la app abierta).
    @ObservationIgnored var diaDeHoy: @Sendable () -> String = { FechaLocal.hoy() }

    /// Check guiado: lo prende `ModeloApp` con la palanca `check_guiado`. Apagado, este modelo no llama a nada nuevo.
    public var guiadoPrendido = false
    /// Lo último que dijo `mypump_check_guiado_get` (queda en el disco: sin señal, la lista de «¿Notaste algo?» no cambia).
    public private(set) var guiado: GuiadoServidor?
    /// Ya se preguntó al servidor al menos una vez (haya contestado o no): recién ahí se sabe si el check está enviado.
    public private(set) var cargadaUnaVez = false
    /// Lo que el alumno lleva contestado del check guiado de esta semana y todavía no mandó.
    public private(set) var borradorGuiado: CheckGuiado.Borrador?

    public init(cliente: ClienteRPC, token: String, outbox: Outbox?, disco: Disco? = nil) {
        self.cliente = cliente; self.token = token; self.outbox = outbox; self.disco = disco
        revisionDia = SemanaRevision.normalizado(disco?.leer(Int.self, Self.archivoDia))
        guiado = disco?.leer(GuiadoServidor.self, Self.archivoGuiado)
        borradorGuiado = disco?.leer(CheckGuiado.Borrador.self, Self.archivoBorrador)
    }

    private static let archivoDia = "revision_dia.json"
    private static let archivoGuiado = "check_guiado.json"
    private static let archivoBorrador = "check_guiado_borrador.json"
    static let kindGuiado = "check_guiado"

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
        async let d = cliente.llamar("mypump_get_revision_dia", ["p_token": t])
        async let g: Result<JSONValue, ErrorRPC>? = guiadoPrendido
            ? cliente.llamar("mypump_check_guiado_get", ["p_token": t, "p_fecha": .texto(fecha)]) : nil
        let (rc, rs, rd, rg) = await (c, s, d, g)
        aplicarDia(rd)
        if let rg { aplicarGuiado(rg) }
        // El borrador de otra semana no es de esta.
        if let b = borradorGuiado, b.semana != semana { descartarBorrador() }
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
        if guiadoPrendido { await aplicarGuiadoPendiente() }
        cargadaUnaVez = true
    }

    /// Lo marcado en «¿Notaste algo?» que todavía no salió gana sobre lo que trae el servidor, como el check.
    private func aplicarGuiadoPendiente() async {
        let semana = semana
        let pendientes = (await outbox?.pendientesPorClave() ?? [:]).filter { k, op in
            k.hasPrefix("\(Self.kindGuiado)_") && op.payload["fecha"]?.comoTexto.map(FotosProgreso.lunes) == semana
        }
        guard let op = pendientes.values.max(by: { $0.ts < $1.ts }), let r = op.payload["respuestas"],
              case .lista(let a)? = r["senales"] else { return }
        guiado = GuiadoServidor(enCiclo: guiado?.enCiclo ?? false, semana: semana,
                                catalogo: r["catalogo"]?.comoTexto.flatMap(CheckGuiado.Catalogo.init(rawValue:)), senales: a.compactMap(\.comoTexto))
    }

    /// Sin red o con un error pasajero queda el último que se supo (el aviso se arma también sin señal). Sin la función en
    /// la base (PGRST202: nativa_008 todavía no aplicada, o revertida) es el domingo, lo de siempre.
    private func aplicarDia(_ r: Result<JSONValue, ErrorRPC>) {
        let nuevo: Int
        switch r {
        case .success(let j): nuevo = SemanaRevision.normalizado(j.comoNumero.map(\.enteroTruncado))
        case .failure(let e) where e.funcionInexistente: nuevo = SemanaRevision.diaPorDefecto
        case .failure: return
        }
        guard nuevo != revisionDia else { return }
        revisionDia = nuevo
        _ = disco?.guardar(nuevo, Self.archivoDia)
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

    // MARK: - Check guiado

    /// Lo que la app sabe del check guiado por el servidor: si está en ciclo y lo que ya marcó esta semana.
    public struct GuiadoServidor: Codable, Equatable, Sendable {
        public var enCiclo: Bool
        public var semana: String?
        public var catalogo: CheckGuiado.Catalogo?
        public var senales: [String]?
        public init(enCiclo: Bool, semana: String? = nil, catalogo: CheckGuiado.Catalogo? = nil, senales: [String]? = nil) {
            self.enCiclo = enCiclo; self.semana = semana; self.catalogo = catalogo; self.senales = senales
        }
    }

    /// Sin red o con un error pasajero queda lo último que se supo. Sin la función (la propuesta sin aplicar) o con la
    /// palanca apagada en el servidor, nadie está en ciclo: la lista general.
    private func aplicarGuiado(_ r: Result<JSONValue, ErrorRPC>) {
        var nuevo: GuiadoServidor?
        switch r {
        case .success(let j):
            guard j["activo"] == .bool(true) else { break }
            var senales: [String]?
            if case .lista(let a)? = j["senales"] { senales = a.compactMap(\.comoTexto) }
            nuevo = GuiadoServidor(enCiclo: j["en_ciclo"] == .bool(true), semana: j["semana"]?.comoTexto,
                                   catalogo: j["catalogo"]?.comoTexto.flatMap(CheckGuiado.Catalogo.init(rawValue:)), senales: senales)
        case .failure(let e) where e.funcionInexistente: break
        case .failure: return
        }
        guard nuevo != guiado else { return }
        guiado = nuevo
        if let nuevo { _ = disco?.guardar(nuevo, Self.archivoGuiado) } else { disco?.borrar(Self.archivoGuiado) }
    }

    /// La lista de «¿Notaste algo?» que le toca.
    public var catalogoGuiado: CheckGuiado.Catalogo { CheckGuiado.Catalogo(enCiclo: guiado?.enCiclo ?? false) }

    /// El borrador con el que se abre el check guiado: el guardado de esta semana o uno nuevo con lo ya enviado.
    public func abrirGuiado() -> CheckGuiado.Borrador {
        let deEstaSemana = guiado?.semana == semana
        var b = CheckGuiado.abrir(guardado: borradorGuiado, semana: semana, catalogo: catalogoGuiado,
                                  enviado: checkinEnviado ? checkin.map { ($0.valores, $0.nota) } : nil,
                                  senalesEnviadas: deEstaSemana ? guiado?.senales : nil,
                                  catalogoEnviado: deEstaSemana ? guiado?.catalogo : nil)
        // El peso del borrador vale solo si es el de hoy: uno de otro día no se manda con la fecha de hoy.
        if !b.peso.isEmpty, PesoCorporal.leer(b.peso) != pesoDeHoy { b.peso = "" }
        return b
    }

    /// El peso manual de hoy, si ya está cargado (el paso del peso lo trae puesto).
    public var pesoDeHoy: Double? {
        let hoy = diaDeHoy()
        return salud.last(where: { $0.tipo == "peso_kg" && $0.fecha == hoy && $0.fuente == "manual" })?.valor
    }

    /// Guardado parcial: cada paso deja el borrador en el teléfono, así se retoma donde quedó.
    public func guardarBorrador(_ b: CheckGuiado.Borrador) {
        guard b != borradorGuiado else { return }
        borradorGuiado = b
        _ = disco?.guardar(b, Self.archivoBorrador)
    }

    public func descartarBorrador() {
        borradorGuiado = nil
        disco?.borrar(Self.archivoBorrador)
    }

    /// El paso del peso: lo guarda en el momento, por la misma cola que la tarjeta de peso. false = no es un peso válido.
    /// Si es el que ya está cargado hoy, no lo manda de nuevo.
    public func guardarPesoGuiado(_ texto: String) async -> Bool {
        guard let valor = PesoCorporal.leer(texto) else { return false }
        let hoy = diaDeHoy()
        if salud.contains(where: { $0.tipo == "peso_kg" && $0.fecha == hoy && $0.fuente == "manual" && $0.valor == valor }) { return true }
        return await guardarPeso(texto)
    }

    /// «Enviar mi check» del check guiado. Manda lo de siempre por donde siempre (`checkin` y `peso`) y, aparte, lo
    /// marcado en «¿Notaste algo?» (`check_guiado`). Devuelve qué falta, o nil si salió.
    public func enviarGuiado(_ b: CheckGuiado.Borrador) async -> String? {
        if let falta = CheckGuiado.faltaParaEnviar(b) { return falta }
        let kilos = b.peso.trimmingCharacters(in: .whitespaces)
        if !kilos.isEmpty, PesoCorporal.leer(kilos) == nil { return PesoCorporal.avisoRango }
        if let falta = await enviarCheckin(Checkin(valores: b.valores, nota: b.nota)) { return falta }
        if !kilos.isEmpty { _ = await guardarPesoGuiado(kilos) }
        let fecha = diaDeHoy()
        let senales = CheckGuiado.normalizar(b.senales, b.catalogo)
        _ = await outbox?.encolar(Self.kindGuiado, .objeto([
            "fecha": .texto(fecha),
            "respuestas": .objeto(["catalogo": .texto(b.catalogo.rawValue), "senales": .lista(senales.map(JSONValue.texto))]),
        ]), dedupeKey: "\(Self.kindGuiado)_\(fecha)")
        let nuevo = GuiadoServidor(enCiclo: guiado?.enCiclo ?? false, semana: FotosProgreso.lunes(fecha), catalogo: b.catalogo, senales: senales)
        guiado = nuevo
        _ = disco?.guardar(nuevo, Self.archivoGuiado)
        descartarBorrador()
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
