import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// La lista previa a la videollamada de comienzo (2.3.0, palanca `lista_previa`). Solo lee: `mypump_lista_previa` con el
/// token, al abrir Entreno, al volver al frente y cuando cambia la guía o la agenda (como mucho un pedido cada 60 s; sin
/// sondeo propio). Con la palanca apagada `ModeloApp` no llama a nada de esto y `vista` queda en nil.
@MainActor @Observable
public final class ModeloListaPrevia {
    /// nil: apagada, inactiva, sin el servidor nuevo o sin ítems. No se muestra nada.
    public private(set) var vista: ReglasListaPrevia.Vista?

    @ObservationIgnored let cliente: ClienteRPC?
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored let reloj: @Sendable () -> Date
    @ObservationIgnored private var ultimoPedido: Date?
    @ObservationIgnored private var pidiendo = false

    static let archivo = "lista-previa.json"
    public static let esperaMinima: TimeInterval = 60

    public init(cliente: ClienteRPC, token: String, disco: Disco?, reloj: @escaping @Sendable () -> Date = { Date() }) {
        self.cliente = cliente; self.token = token; self.disco = disco; self.reloj = reloj
    }

    /// La demo: la lista de `historial.json`, fija. Nunca toca la red.
    public init(muestra: JSONValue?) {
        cliente = nil; token = ""; disco = nil; reloj = { Date() }
        vista = ReglasListaPrevia.vista(muestra)
    }

    /// `forzar`: cambió la guía o la agenda (un video visto, una reserva). Igual respeta los 60 s.
    public func refrescar() async {
        guard let cliente, !pidiendo else { return }
        let ahora = reloj()
        if let u = ultimoPedido, ahora.timeIntervalSince(u) < Self.esperaMinima { return }
        ultimoPedido = ahora
        pidiendo = true
        defer { pidiendo = false }
        switch await cliente.llamar("mypump_lista_previa", ["p_token": .texto(token)]) {
        case .success(let j):
            vista = ReglasListaPrevia.vista(j)
            if vista != nil { disco?.guardar(j, Self.archivo) } else { disco?.borrar(Self.archivo) }
        case .failure(let e) where e.funcionInexistente || e.clase == .permanente:
            apagar()
        case .failure:
            // Sin red: lo último que se supo, si todavía no hay nada en pantalla.
            if vista == nil, let j = disco?.leer(JSONValue.self, Self.archivo) { vista = ReglasListaPrevia.vista(j) }
        }
    }

    /// Palanca apagada o cuenta que se va: no queda nada en pantalla ni en disco.
    public func apagar() {
        vista = nil
        ultimoPedido = nil
        disco?.borrar(Self.archivo)
    }
}
