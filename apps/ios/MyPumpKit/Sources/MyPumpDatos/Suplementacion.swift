import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// La pestaña Suplementación (2.1.0): `mypump_suplementacion(p_token)`, solo lectura, con copia en el disco de la cuenta
/// para verla sin red. Se trae al cargar la cuenta y al volver a primer plano.
///
/// - Una fila con ítems: la pestaña aparece (y Salud pasa a «Más»).
/// - Cero filas (token inválido o sin suplementación): la pestaña se va y se borra la copia.
/// - Sin red o con un error del servidor: queda lo guardado (un corte no es «no tiene suplementación»).
@MainActor @Observable
public final class ModeloSuplementacion {
    public static let funcion = "mypump_suplementacion"
    static let archivo = "suplementacion.json"

    /// Lo último del servidor (o la copia guardada). nil = no hay suplementación.
    public private(set) var respuesta: RespuestaSuplementacion?
    /// Lo que se ve vino de la copia guardada porque la última carga no llegó.
    public private(set) var desdeCache = false

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String
    @ObservationIgnored let disco: Disco?
    @ObservationIgnored private var esMuestra = false
    @ObservationIgnored private var cargaEnCurso: Task<Void, Never>?

    public init(cliente: ClienteRPC, token: String, disco: Disco?) {
        self.cliente = cliente; self.token = token; self.disco = disco
        respuesta = disco?.leer(RespuestaSuplementacion.self, Self.archivo).flatMap { $0.hay ? $0 : nil }
    }

    /// La demo («Ver demo», la revisión de Apple): una respuesta armada, sin red ni token.
    public init(muestra: RespuestaSuplementacion) {
        cliente = ClienteRPC()
        token = ""
        disco = nil
        esMuestra = true
        respuesta = muestra.hay ? muestra : nil
    }

    /// La agrupación por momento, la misma de «Tu guía». nil = la pestaña no aparece.
    public var vista: VistaSuplementacion? { VistaSuplementacion(respuesta?.suplementacion) }
    /// Hay suplementación para mostrar: la pestaña aparece.
    public var hay: Bool { vista != nil }

    /// Trae la suplementación. Si ya hay una carga en vuelo, espera esa.
    public func cargar() async {
        if esMuestra { return }
        if let t = cargaEnCurso { await t.value; return }
        let t = Task { await self.traer() }
        cargaEnCurso = t
        await t.value
        cargaEnCurso = nil
    }

    private func traer() async {
        switch await cliente.filas(Self.funcion, ["p_token": .texto(token)], como: RespuestaSuplementacion.self) {
        case .failure:
            desdeCache = respuesta != nil
        case .success(let filas):
            desdeCache = false
            if let f = filas.first, f.hay {
                if f != respuesta { respuesta = f }
                disco?.guardar(f, Self.archivo)
            } else {
                respuesta = nil
                disco?.borrar(Self.archivo)
            }
        }
    }
}
