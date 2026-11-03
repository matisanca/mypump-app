import Foundation
import MyPumpModelos
import MyPumpReglas

// El código de barras de «Agregar alimento» (2.1, S3): con el número que leyó el escáner se pregunta a Open Food Facts
// (pública, gratis y sin clave; solo viaja el código, sin token ni nada de la cuenta) y la respuesta se lleva a un alimento
// con `CodigoBarras.leer`. Lo buscado queda en el teléfono (`codigos_barras.json`, por cuenta), así un producto de todos
// los días no vuelve a la red y se encuentra sin señal.

extension ModeloApp {
    nonisolated static let archivoCodigos = "codigos_barras.json"

    /// Lo que pasó al buscar: una lectura (de la caché o de Open Food Facts) o que no hubo respuesta.
    public enum BusquedaCodigo: Equatable, Sendable {
        case lectura(CodigoBarras.Lectura)
        case sinRed
    }

    private var cache: CacheCodigos {
        get {
            if let c = cacheCodigos { return c }
            let c = disco?.leer(CacheCodigos.self, Self.archivoCodigos) ?? CacheCodigos()
            cacheCodigos = c
            return c
        }
        set {
            cacheCodigos = newValue
            if !esDemo { disco?.guardar(newValue, Self.archivoCodigos) }
        }
    }

    private static var ahoraMs: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// La versión de la app para el User-Agent que pide Open Food Facts.
    nonisolated static var versionApp: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2"
    }

    /// Busca un código ya normalizado (`CodigoBarras.normalizar`). Sin respuesta (sin señal, timeout, Open Food Facts caído)
    /// es `.sinRed` y no se guarda nada. En la demo no se pregunta a nadie: no está (con las salidas de siempre).
    public func buscarCodigo(_ codigo: String) async -> BusquedaCodigo {
        if esDemo { return .lectura(.noEncontrado) }
        if let l = cache.vigente(codigo, ahoraMs: Self.ahoraMs) { return .lectura(l) }
        guard let url = CodigoBarras.url(codigo) else { return .lectura(.noEncontrado) }
        var pedido = URLRequest(url: url, timeoutInterval: CodigoBarras.esperaSegundos)
        pedido.setValue(CodigoBarras.agenteUsuario(version: Self.versionApp, plataforma: "iOS"), forHTTPHeaderField: "User-Agent")
        pedido.setValue("application/json", forHTTPHeaderField: "Accept")
        let transporte = transporteBarras ?? cliente.transporte
        let datos: Data, respuesta: URLResponse
        do {
            // `timeoutInterval` corta solo si la conexión se queda callada; el plazo es para toda la consulta.
            let listo = pedido
            (datos, respuesta) = try await Self.conPlazo(esperaBarras) { try await transporte.enviar(listo) }
        } catch {
            return .sinRed
        }
        let status = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: datos)
        let lectura: CodigoBarras.Lectura
        if let j, (200..<300).contains(status) || status == 404, let st = j["status"]?.comoNumero, st == 0 || st == 1 {
            // Un producto que no está contesta 404 con `status: 0`. Sin `status` 0 o 1 (un proxy, otra API) no se sabe nada
            // del producto: no se guarda.
            lectura = CodigoBarras.leer(j, codigo: codigo)
        } else {
            // 429, 5xx, una página de error o un JSON sin `status`: no es una respuesta sobre el producto.
            return .sinRed
        }
        var c = cache
        c.guardar(codigo, lectura, ahoraMs: Self.ahoraMs)
        cache = c
        return .lectura(lectura)
    }

    /// Corre `op` con un plazo total: pasado, se cancela y tira `URLError(.timedOut)`.
    nonisolated static func conPlazo<T: Sendable>(_ segundos: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, segundos) * 1_000_000_000))
                throw URLError(.timedOut)
            }
            defer { g.cancelAll() }
            guard let r = try await g.next() else { throw URLError(.timedOut) }
            return r
        }
    }

    /// Los propios creados desde un código que se borraron o se editaron dejan de aparecer al escanear (`conciliarPropios`).
    func conciliarCodigosPropios() {
        var c = cache
        if c.conciliarPropios(alimentosPropios) { cache = c }
    }

    /// Lo buscado se va con la cuenta: al salir se borra del teléfono.
    func borrarCodigosDelDisco() {
        cacheCodigos = nil
        disco?.borrar(Self.archivoCodigos)
    }

    /// Un alimento propio creado desde un código que Open Food Facts no tenía (o tenía incompleto): la próxima vez que se
    /// escanee, aparece el suyo.
    public func recordarCodigoPropio(_ codigo: String, _ c: AgregadosComida.Candidato) {
        var cc = cache
        cc.guardar(codigo, .encontrado(CodigoBarras.Producto(codigo: codigo, nombre: c.nombre, por100: c.por100, medida: c.unidad,
                                                               gramosMedida: c.gramosPorUnidad, propio: true)), ahoraMs: Self.ahoraMs)
        cache = cc
    }
}
