import SwiftUI
import UIKit

/// Espía de la Fase 0: misma bundle id que MyPump. Instalada encima de la app Capacitor (como un update), lee el
/// localStorage viejo por las dos rutas, las compara, prueba escribir de vuelta y deja un informe en
/// Application Support/spike-informe.json.
@main
struct SpikeApp: App {
    var body: some Scene {
        WindowGroup { VistaSpike() }
    }
}

struct VistaSpike: View {
    @State private var texto = "Leyendo el almacenamiento viejo…"

    var body: some View {
        ScrollView {
            Text(texto)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Anfitrion { contenedor in
            Task { @MainActor in texto = await Spike.correr(en: contenedor) }
        })
    }
}

/// Le da al WKWebView una vista real dentro de la ventana: oculto, pero adjunto.
struct Anfitrion: UIViewRepresentable {
    let alListo: @MainActor (UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        DispatchQueue.main.async { alListo(v) }
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

@MainActor
enum Spike {
    static var lector: LectorWebView?

    static func correr(en contenedor: UIView) async -> String {
        var informe: [String: Any] = [:]
        let limitar = Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") != nil
        informe["variante"] = limitar ? "appbound" : "sin-appbound"
        informe["ios"] = UIDevice.current.systemVersion
        informe["arranque"] = ISO8601DateFormatter().string(from: Date())

        // Ruta B primero, antes de levantar WebKit.
        var itemsB: [String: String] = [:]
        do {
            let lecturas = try LectorArchivoLegado.leer()
            informe["rutaB_archivos"] = lecturas.map {
                ["ruta": $0.ruta.replacingOccurrences(of: NSHomeDirectory(), with: "~"), "formato": $0.formato, "claves": $0.items.count] as [String: Any]
            }
            for l in lecturas { itemsB.merge(l.items) { primero, _ in primero } }
        } catch {
            informe["rutaB_error"] = "\(error)"
        }
        informe["rutaB_claves"] = itemsB.keys.sorted()
        informe["marca_previa_rutaB"] = itemsB["mypump_nativa_marca"] ?? NSNull()

        // Ruta A.
        let lector = LectorWebView()
        self.lector = lector
        var itemsA: [String: String] = [:]
        var errorA: String?
        do {
            itemsA = try await lector.leer(en: contenedor, limitarAppBound: limitar)
        } catch {
            errorA = "\(error)"
            informe["rutaA_error"] = errorA
        }
        informe["rutaA_claves"] = itemsA.keys.sorted()

        // Comparación clave por clave y valor por valor.
        let todas = Set(itemsA.keys).union(itemsB.keys)
        let diferencias = todas.sorted().filter { itemsA[$0] != itemsB[$0] }
        informe["diferencias"] = diferencias
        informe["iguales"] = errorA == nil && diferencias.isEmpty
        informe["valores_rutaA"] = itemsA
        informe["valores_rutaB"] = itemsB

        // Escritura de vuelta: se confirma en el arranque siguiente con la Ruta B (marca_previa_rutaB).
        if errorA == nil {
            let marca = ISO8601DateFormatter().string(from: Date())
            do {
                informe["writeback_marca"] = marca
                informe["writeback_leido"] = try await lector.escribir(clave: "mypump_nativa_marca", valor: marca) ?? NSNull()
            } catch {
                informe["writeback_error"] = "\(error)"
            }
        }

        let soporte = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: soporte, withIntermediateDirectories: true)
        let url = soporte.appendingPathComponent("spike-informe.json")
        guard let data = try? JSONSerialization.data(withJSONObject: informe, options: [.prettyPrinted, .sortedKeys]) else {
            return "No se pudo serializar el informe"
        }
        try? data.write(to: url)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
