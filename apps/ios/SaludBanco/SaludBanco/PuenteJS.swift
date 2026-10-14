import Foundation
import JavaScriptCore

/// La app Capacitor de hoy, sin WebView: healthkit-bridge.js (de origin/main) corre en JavaScriptCore y su
/// `Capacitor.Plugins.Health` llama a la clase `Health` del plugin (@capgo/capacitor-health 8.9.3, Health.swift copiado
/// de node_modules) con los mismos argumentos que le pasaría HealthPlugin.swift. Los resultados vuelven a JS como
/// JSON (JSONSerialization, como el puente de Capacitor). Lo que el bridge manda a la base queda en `lotes`.
@MainActor
final class PuenteJS {
    private let contexto: JSContext
    private let plugin = Health()
    private(set) var lotes: [(fn: String, json: String)] = []
    private(set) var consultas = 0
    private var fin: CheckedContinuation<String, Never>?

    init(bridge: String, ahora: Double, iosMayor: Int) {
        contexto = JSContext()!
        contexto.exceptionHandler = { _, e in print("[banco][js] excepción: \(e?.toString() ?? "?")") }
        let log: @convention(block) (String) -> Void = { print("[banco][js] \($0)") }
        contexto.setObject(log, forKeyedSubscript: "__log" as NSString)
        let llamar: @convention(block) (String, String, JSValue, JSValue) -> Void = { [weak self] metodo, args, res, rej in
            MainActor.assumeIsolated { self?.llamar(metodo, args, res, rej) }
        }
        contexto.setObject(llamar, forKeyedSubscript: "__plugin" as NSString)
        let ingest: @convention(block) (String, String) -> String = { [weak self] fn, json in
            MainActor.assumeIsolated { self?.lotes.append((fn, json)) }
            let n = ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any])?.count ?? 0
            return "{\"success\":true,\"data\":\(n),\"error\":null}"
        }
        contexto.setObject(ingest, forKeyedSubscript: "__ingest" as NSString)
        let terminar: @convention(block) (String) -> Void = { [weak self] r in
            MainActor.assumeIsolated {
                self?.fin?.resume(returning: r)
                self?.fin = nil
            }
        }
        contexto.setObject(terminar, forKeyedSubscript: "__fin" as NSString)
        contexto.evaluateScript(Self.entorno(ahora: ahora, iosMayor: iosMayor))
        contexto.evaluateScript(bridge)
    }

    /// Lo mínimo del navegador que usa el bridge, con el reloj clavado en `ahora` (el mismo que usa la nativa).
    static func entorno(ahora: Double, iosMayor: Int) -> String {
        """
        var window = globalThis;
        var console = { log: (...a) => __log(a.join(' ')), warn: (...a) => __log(a.join(' ')), error: (...a) => __log(a.join(' ')) };
        var __ls = {};
        var localStorage = { getItem: (k) => (k in __ls ? __ls[k] : null), setItem: (k, v) => { __ls[k] = String(v); }, removeItem: (k) => { delete __ls[k]; } };
        var navigator = { userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS \(iosMayor)_0 like Mac OS X)' };
        var document = { addEventListener() {}, hidden: false };
        function addEventListener() {}
        const __DateReal = Date;
        class __DateFalsa extends __DateReal {
          constructor(...a) { if (a.length === 0) super(\(Int(ahora))); else super(...a); }
          static now() { return \(Int(ahora)); }
        }
        Date = __DateFalsa;
        const __llamar = (metodo, args) => new Promise((res, rej) =>
          __plugin(metodo, JSON.stringify(args || {}), (j) => res(JSON.parse(j)), (e) => rej(new Error(e))));
        var Capacitor = { isNativePlatform: () => true, getPlatform: () => 'ios', Plugins: { Health: {
          isAvailable: (o) => __llamar('isAvailable', o), requestAuthorization: (o) => __llamar('requestAuthorization', o),
          checkAuthorization: (o) => __llamar('checkAuthorization', o), readSamples: (o) => __llamar('readSamples', o),
          queryAggregated: (o) => __llamar('queryAggregated', o), queryWorkouts: (o) => __llamar('queryWorkouts', o) } } };
        window.mypumpDB = {
          ingestSalud: async (t, r) => JSON.parse(__ingest('mypump_ingest_salud', JSON.stringify(r))),
          ingestEntrenos: async (t, e) => JSON.parse(__ingest('mypump_ingest_entrenos', JSON.stringify(e))),
        };
        """
    }

    /// Prepara el localStorage y corre `expr` (una promesa) hasta que termina. Devuelve su resultado en JSON.
    func correr(_ expr: String, localStorage: [String: String]) async -> String {
        lotes = []
        let ls = (try? JSONSerialization.data(withJSONObject: localStorage)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return await withCheckedContinuation { c in
            fin = c
            contexto.evaluateScript("__ls = \(ls); (\(expr)).then(r => __fin(JSON.stringify(r)), e => __fin(JSON.stringify({ error: String(e) })));")
        }
    }

    // MARK: - Lo que hace HealthPlugin.swift con cada llamada

    private func llamar(_ metodo: String, _ argsJSON: String, _ res: JSValue, _ rej: JSValue) {
        consultas += 1
        let a = ((try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8))) as? [String: Any]) ?? [:]
        func devolver(_ r: Result<[String: Any], Error>) {
            DispatchQueue.main.async {
                switch r {
                case .success(let d):
                    let json = (try? JSONSerialization.data(withJSONObject: d)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                    res.call(withArguments: [json])
                case .failure(let e):
                    rej.call(withArguments: [e.localizedDescription])
                }
            }
        }
        let read = (a["read"] as? [String]) ?? [], write = (a["write"] as? [String]) ?? []
        switch metodo {
        case "isAvailable":
            devolver(.success(plugin.availabilityPayload()))
        case "requestAuthorization":
            plugin.requestAuthorization(readIdentifiers: read, writeIdentifiers: write) { r in devolver(r.map { $0.toDictionary() }) }
        case "checkAuthorization":
            plugin.checkAuthorization(readIdentifiers: read, writeIdentifiers: write) { r in devolver(r.map { $0.toDictionary() }) }
        case "readSamples":
            do {
                try plugin.readSamples(dataTypeIdentifier: a["dataType"] as? String ?? "", startDateString: a["startDate"] as? String,
                                       endDateString: a["endDate"] as? String, limit: a["limit"] as? Int,
                                       ascending: a["ascending"] as? Bool ?? false) { r in devolver(r.map { ["samples": $0] }) }
            } catch { devolver(.failure(error)) }
        case "queryAggregated":
            var aggs: [String] = []
            if let s = a["aggregation"] as? String { aggs = [s] } else if let l = a["aggregation"] as? [String] { aggs = l }
            plugin.queryAggregated(dataTypeIdentifier: a["dataType"] as? String ?? "", startDateString: a["startDate"] as? String,
                                   endDateString: a["endDate"] as? String, bucketString: a["bucket"] as? String, aggregations: aggs) { r in devolver(r) }
        case "queryWorkouts":
            plugin.queryWorkouts(workoutTypeString: a["workoutType"] as? String, startDateString: a["startDate"] as? String,
                                 endDateString: a["endDate"] as? String, limit: a["limit"] as? Int, ascending: a["ascending"] as? Bool ?? false,
                                 anchorString: a["anchor"] as? String) { r in devolver(r) }
        default:
            devolver(.failure(NSError(domain: "banco", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(metodo) is not implemented"])))
        }
    }
}
