import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// «Devolución de Mati» en Revisión. Solo lee: `mypump_devolucion_get` con el token. Con la palanca `devolucion_semanal`
/// apagada `ModeloApp` no llama a nada de esto y `estado` queda en nil. Sin red muestra lo último que se supo.
@MainActor @Observable
public final class ModeloDevolucion {
    /// nil: apagada, sin el servidor nuevo o sin habilitar. No se muestra nada.
    public private(set) var estado: EstadoDevolucion?

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?

    static let archivo = "devolucion-estado.json"

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
    }

    public var ultima: DevolucionSemanal? { estado?.ultima }
    public var anteriores: [DevolucionSemanal] { estado?.anteriores ?? [] }

    public func refrescar() async {
        switch await cliente.llamar("mypump_devolucion_get", ["p_token": .texto(token)]) {
        case .success(let j):
            // NULL (token caído) o `habilitado: false`: se apaga y se olvida lo guardado.
            guard let e = EstadoDevolucion(j) else { apagar(); return }
            estado = e
            disco?.guardar(j, Self.archivo)
        case .failure(let e) where e.funcionInexistente || e.status == 404 || e.clase == .permanente:
            apagar()
        case .failure:
            if estado == nil, let j = disco?.leer(JSONValue.self, Self.archivo), let e = EstadoDevolucion(j) { estado = e }
        }
    }

    /// Palanca apagada o cuenta que se va: no queda nada en pantalla ni en disco.
    public func apagar() {
        estado = nil
        disco?.borrar(Self.archivo)
    }

    #if DEBUG
    /// Bocetos y capturas: un estado fijo, sin servidor.
    public func fijar(_ e: EstadoDevolucion?) { estado = e }
    #endif
}
