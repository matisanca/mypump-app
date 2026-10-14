import SwiftUI
import HealthKit
import MyPumpDatos
import MyPumpModelos
import MyPumpReglas

/// Banco de pruebas de salud (solo simulador, nunca se publica). Lo maneja scripts/nativa/salud-banco.sh:
///
/// - `-comparar YES`: siembra la Salud del simulador y corre, sobre los MISMOS datos y con el mismo "ahora", la app de
///   hoy (healthkit-bridge.js en JavaScriptCore + el Health.swift del plugin) y la nativa (FuenteHealthKit +
///   SincronizadorSalud). Compara lote por lote lo que cada una mandaría a `ingest_salud` e `ingest_entrenos`, en la
///   sincronización de 7 días y en el historial de 60, y deja el informe en Documents/salud-e2e.json.
/// - `-token <t>` (la cuenta test-nativa-ios): además muestra las vistas de salud con ModeloSalud contra la base real.
@main
struct BancoApp: App {
    @State private var banco = Banco()

    var body: some Scene {
        WindowGroup {
            NavigationStack { BancoView(banco: banco) }
                .task { await banco.arrancar() }
        }
    }
}

struct InformeBanco: Codable {
    struct Fase: Codable {
        var lotesWeb = 0, lotesNativa = 0, registrosWeb = 0, registrosNativa = 0, entrenosWeb = 0, entrenosNativa = 0
        var iguales = false
        var diferencias: [String] = []
        var tipos: [String: Int] = [:]
        var resultadoWeb = ""
    }
    var ahora = ""
    var zona = ""
    var ios = 0
    var sembradas = 0
    var consultasWeb = 0
    var sync = Fase()
    var historial = Fase()
    /// ModeloSalud encuentra FuenteHealthKit por nombre, sin que la app la registre (como en MyPump).
    var fuenteDescubierta = false
    var error: String?
    var iguales: Bool { error == nil && sync.iguales && historial.iguales && fuenteDescubierta }
}

@MainActor @Observable
final class Banco {
    var estado = "Pidiendo permiso a Salud…"
    var informe: InformeBanco?
    var modelo: ModeloSalud?
    private let store = HKHealthStore()

    func arrancar() async {
        let defaults = UserDefaults.standard
        do {
            try await store.requestAuthorization(toShare: Sembrador.escritura, read: Sembrador.lectura)
        } catch {
            estado = "Sin permiso de Salud: \(error.localizedDescription)"
            return
        }
        if let t = defaults.string(forKey: "token") {
            modelo = ModeloSalud(cliente: ClienteRPC(), token: t, fuente: FuenteHealthKit(), almacen: AlmacenSaludDefaults())
        }
        if defaults.bool(forKey: "comparar") {
            informe = await comparar()
            estado = informe?.iguales == true ? "IGUALES" : "DISTINTOS"
        } else {
            estado = "Listo"
        }
        await modelo?.alAbrir()
    }

    // MARK: - La comparación

    func comparar() async -> InformeBanco {
        var inf = InformeBanco()
        let ahora = RelojLocal.ms(Date())
        inf.ahora = RelojLocal.iso(ahora)
        inf.zona = TimeZone.current.identifier
        inf.ios = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        inf.fuenteDescubierta = ModeloSalud.fuenteDelSistema is FuenteHealthKit
        do {
            estado = "Sembrando…"
            _ = try await Sembrador.borrar(store)
            inf.sembradas = try await Sembrador.sembrar(store, ahora: RelojLocal.fecha(ahora))
            guard let url = Bundle.main.url(forResource: "healthkit-bridge", withExtension: "js"), let bridge = try? String(contentsOf: url, encoding: .utf8) else {
                inf.error = "falta healthkit-bridge.js en el bundle"
                return guardar(inf)
            }
            let web = PuenteJS(bridge: bridge, ahora: ahora, iosMayor: inf.ios)
            let captura = CapturaBase()
            let nativa = SincronizadorSalud(fuente: FuenteHealthKit(), cliente: ClienteRPC(transporte: captura), token: "tok-banco",
                                            almacen: AlmacenSaludEnMemoria([ClaveSalud.conectado: "1", ClaveSalud.historialHecho: "1"]),
                                            ahora: { RelojLocal.fecha(ahora) })

            estado = "Sincronización de 7 días…"
            inf.sync.resultadoWeb = await web.correr("MyPumpHealth.sync()", localStorage: [
                "mypump_token": "tok-banco", ClaveSalud.conectado: "1", ClaveSalud.historialHecho: "1"])
            _ = await nativa.sincronizar()
            inf.sync = comparar(web.lotes, captura.tomar(), base: inf.sync)

            estado = "Historial de 60 días…"
            inf.historial.resultadoWeb = await web.correr("MyPumpHealth.backfill()", localStorage: ["mypump_token": "tok-banco", ClaveSalud.conectado: "1"])
            let nativaHistorial = SincronizadorSalud(fuente: FuenteHealthKit(), cliente: ClienteRPC(transporte: captura), token: "tok-banco",
                                                     almacen: AlmacenSaludEnMemoria([ClaveSalud.conectado: "1"]), ahora: { RelojLocal.fecha(ahora) })
            _ = await nativaHistorial.historial()
            inf.historial = comparar(web.lotes, captura.tomar(), base: inf.historial)
            inf.consultasWeb = web.consultas
        } catch {
            inf.error = "\(error)"
        }
        return guardar(inf)
    }

    private func comparar(_ web: [(fn: String, json: String)], _ nativa: [(fn: String, lote: JSONValue)], base: InformeBanco.Fase) -> InformeBanco.Fase {
        var f = base
        let w = web.map { (fn: $0.fn, lote: (try? JSONDecoder().decode(JSONValue.self, from: Data($0.json.utf8))) ?? .null) }
        func filas(_ l: [(fn: String, lote: JSONValue)], _ fn: String) -> [JSONValue] {
            l.filter { $0.fn == fn }.flatMap { if case .lista(let x) = $0.lote { return x }; return [] }
        }
        f.lotesWeb = w.count; f.lotesNativa = nativa.count
        let rw = filas(w, "mypump_ingest_salud"), rn = filas(nativa, "mypump_ingest_salud")
        let ew = filas(w, "mypump_ingest_entrenos"), en = filas(nativa, "mypump_ingest_entrenos")
        f.registrosWeb = rw.count; f.registrosNativa = rn.count; f.entrenosWeb = ew.count; f.entrenosNativa = en.count
        for r in rw { if let t = r["tipo"]?.comoTexto { f.tipos[t, default: 0] += 1 } }
        if w.map(\.fn) != nativa.map(\.fn) { f.diferencias.append("lotes: web \(w.map(\.fn)), nativa \(nativa.map(\.fn))") }
        for (i, (a, b)) in zip(w, nativa).enumerated() where a.lote != b.lote {
            guard case .lista(let x) = a.lote, case .lista(let y) = b.lote else { f.diferencias.append("lote \(i): forma"); continue }
            if x.count != y.count { f.diferencias.append("lote \(i) \(a.fn): web \(x.count) filas, nativa \(y.count)") }
            for (k, (p, q)) in zip(x, y).enumerated() where p != q {
                f.diferencias.append("lote \(i) fila \(k): web \(Self.texto(p)) · nativa \(Self.texto(q))")
                if f.diferencias.count > 40 { break }
            }
        }
        f.iguales = f.diferencias.isEmpty && rw.count == rn.count && ew.count == en.count && w.count == nativa.count
        return f
    }

    static func texto(_ j: JSONValue) -> String {
        (try? JSONEncoder().encode(j)).map { String(decoding: $0, as: UTF8.self) } ?? "?"
    }

    private func guardar(_ inf: InformeBanco) -> InformeBanco {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(inf), let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? d.write(to: dir.appendingPathComponent("salud-e2e.json"))
            print("[banco] informe: \(String(decoding: d, as: UTF8.self))")
        }
        return inf
    }
}

/// Hace de base para la nativa: guarda cada lote y contesta "guardé N".
final class CapturaBase: Transporte, @unchecked Sendable {
    private var lotes: [(fn: String, lote: JSONValue)] = []
    private let candado = NSLock()

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        let fn = pedido.url?.lastPathComponent ?? ""
        let cuerpo = pedido.httpBody.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) }
        let lote = cuerpo?["p_registros"] ?? cuerpo?["p_entrenos"] ?? .null
        candado.withLock { lotes.append((fn, lote)) }
        let n: Int = { if case .lista(let l) = lote { return l.count }; return 0 }()
        return (Data("\(n)".utf8), HTTPURLResponse(url: pedido.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    func tomar() -> [(fn: String, lote: JSONValue)] {
        candado.withLock {
            defer { lotes = [] }
            return lotes
        }
    }
}

struct BancoView: View {
    let banco: Banco

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(banco.estado).font(.title2.bold()).accessibilityIdentifier("estado-banco")
                if let inf = banco.informe {
                    Group {
                        Text("\(inf.sembradas) muestras sembradas · \(inf.consultasWeb) consultas del bridge · \(inf.zona)")
                        fase("Sincronización (7 días)", inf.sync)
                        fase("Historial (60 días)", inf.historial)
                        if let e = inf.error { Text(e).foregroundStyle(.red) }
                    }
                    .font(.footnote.monospaced())
                }
                if let m = banco.modelo {
                    Divider()
                    CardRecuperacionView(modelo: m)
                    CardSaludView(modelo: m)
                    MiRelojView(modelo: m)
                    NavigationLink("Mis datos de salud") { SaludDetalleView(modelo: m) }
                }
            }
            .padding()
        }
        .background(Color.fondo)
        .navigationTitle("Banco de salud")
    }

    private func fase(_ titulo: String, _ f: InformeBanco.Fase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(titulo): \(f.iguales ? "iguales" : "DISTINTOS")").bold().foregroundStyle(f.iguales ? .green : .red)
            Text("registros web \(f.registrosWeb) / nativa \(f.registrosNativa) · entrenos \(f.entrenosWeb) / \(f.entrenosNativa) · lotes \(f.lotesWeb) / \(f.lotesNativa)")
            ForEach(f.diferencias.prefix(8), id: \.self) { Text($0).foregroundStyle(.red) }
        }
    }
}
