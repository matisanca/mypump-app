import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Feedback del alumno (2.3.0): «Me duele» por ejercicio y «Lo compré / lo estoy tomando». Una sola lectura
/// (`mypump_feedback_get`) y dos escrituras directas, sin cola: son avisos que el alumno manda mirando la pantalla y, si no
/// salen, se lo decimos ahí mismo. Con las palancas `me_duele` y `suple_estado` apagadas `ModeloApp` no llama a nada de esto.
@MainActor @Observable
public final class ModeloFeedback {
    public enum Resultado: Equatable, Sendable { case ok, sinSenal, tope, error }

    /// nil: apagado, sin el servidor nuevo, o sin red y sin nada guardado. No se muestra nada.
    public private(set) var estado: EstadoFeedback?
    /// Las marcas que todavía están viajando: la fila se ve marcada enseguida y vuelve atrás si falla.
    public private(set) var marcando: Set<String> = []

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private var esMuestra = false
    /// Cuenta las escrituras: una lectura que salió antes de una escritura no pisa lo que esa escritura dejó.
    @ObservationIgnored private var escrituras = 0
    /// Se cerró sesión: no se vuelve a pedir ni a guardar nada de esta cuenta.
    @ObservationIgnored private var cerrada = false

    static let archivo = "feedback-estado.json"

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
    }

    /// La demo: con molestias y marcas armadas, sin red.
    public init(muestra: EstadoFeedback) {
        cliente = ClienteRPC(); token = ""; disco = nil; esMuestra = true; estado = muestra
    }

    // MARK: Lo que lee la pantalla

    public var dueleHabilitado: Bool { estado?.dueleHabilitado ?? false }
    public var supleHabilitado: Bool { estado?.supleHabilitado ?? false }
    public func molestia(ejercicio id: String) -> Molestia? { estado?.molestia(ejercicio: id) }
    public var marcas: [String: ReglasSupleEstado.Estado] { estado?.marcas ?? [:] }

    // MARK: Servidor

    public func refrescar() async {
        if esMuestra || cerrada { return }
        let antes = escrituras
        let r = await cliente.llamar("mypump_feedback_get", ["p_token": .texto(token)])
        if cerrada || escrituras != antes || !marcando.isEmpty { return }   // la próxima lectura trae lo nuevo
        switch r {
        case .success(.null):
            estado = nil
        case .success(let j):
            guard let e = EstadoFeedback(j) else { apagar(); disco?.borrar(Self.archivo); return }
            estado = e
            disco?.guardar(j, Self.archivo)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
            disco?.borrar(Self.archivo)
        case .failure:
            // Sin red, lo último que se supo: se ve qué se avisó y qué se marcó. Avisar algo nuevo va a decir que no hay señal.
            if estado == nil, let j = disco?.leer(JSONValue.self, Self.archivo), let e = EstadoFeedback(j) { estado = e }
        }
    }

    public func apagar() { estado = nil; marcando = [] }

    /// Cerrar sesión: las molestias avisadas y las marcas de suplementos (lo que se ve) se borran del teléfono. No hay nada
    /// pendiente que conservar: «Me duele» y las marcas salen directo, sin cola (si no salen, se avisa en la pantalla).
    public func olvidarAlSalir() {
        cerrada = true
        apagar()
        disco?.borrar(Self.archivo)
    }

    /// Avisa una molestia. `id` lo pone quien llama y lo repite en cada reintento: el servidor no duplica.
    public func avisar(id: String, ejercicioId: String, ejercicioNombre: String, diaId: String?, _ b: ReglasMolestia.Borrador, version: String?) async -> Resultado {
        guard b.completa, let zona = b.zona, let lado = b.lado, let desde = b.desde, let cuando = b.cuando, let tipo = b.tipo, let intensidad = b.intensidad else { return .error }
        if esMuestra { return .ok }
        let nota = ReglasMolestia.nota(b.nota.trimmingCharacters(in: .whitespacesAndNewlines))
        let r = await cliente.llamar("mypump_molestia_registrar", [
            "p_token": .texto(token), "p_id": .texto(id),
            "p_ejercicio_id": .texto(String(ejercicioId.prefix(160))), "p_ejercicio_nombre": .texto(String(ejercicioNombre.prefix(160))),
            "p_dia_id": diaId.map { .texto(String($0.prefix(80))) } ?? .null,
            "p_zona": .texto(zona), "p_lado": .texto(lado), "p_desde": .texto(desde), "p_cuando": .texto(cuando), "p_tipo": .texto(tipo),
            "p_intensidad": .numero(Double(intensidad)), "p_nota": nota.isEmpty ? .null : .texto(nota),
            "p_plataforma": .texto("ios"), "p_version": version.map { .texto(String($0.prefix(40))) } ?? .null,
        ])
        switch r {
        case .success(let j):
            if case .bool(true)? = j["ok"] {
                escrituras += 1
                if let m = Molestia(j["molestia"]) {
                    var e = estado ?? EstadoFeedback()
                    e.molestias.removeAll { $0.id == m.id }
                    e.molestias.insert(m, at: 0)
                    estado = e
                }
                return .ok
            }
            return j["error"]?.comoTexto == "tope" ? .tope : .error
        case .failure(let e):
            return e.clase == .red || e.clase == .transitorio ? .sinSenal : .error
        }
    }

    /// Marca un suplemento. Se ve enseguida; si el servidor no lo toma, vuelve a como estaba y devuelve false.
    public func marcar(nombre: String, _ nuevo: ReglasSupleEstado.Estado) async -> Bool {
        let k = ReglasSupleEstado.clave(nombre)
        guard !k.isEmpty, var e = estado, !marcando.contains(k) else { return false }
        let antes = e.marcas[k]
        if antes == nuevo { return true }
        e.marcas[k] = nuevo
        estado = e
        if esMuestra { return true }
        marcando.insert(k)
        escrituras += 1
        defer { marcando.remove(k) }
        let r = await cliente.llamar("mypump_suple_marcar", ["p_token": .texto(token), "p_item": .texto(nombre), "p_estado": .texto(nuevo.rawValue), "p_nota": .null])
        if case .success(let j) = r, case .bool(true)? = j["ok"] { return true }
        if var v = estado {   // puede haberse apagado mientras viajaba
            v.marcas[k] = antes
            estado = v
        }
        return false
    }
}
