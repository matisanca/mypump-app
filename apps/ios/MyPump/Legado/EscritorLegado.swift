import UIKit
import WebKit
import MyPumpDatos

/// Ruta A, para la escritura de vuelta: un WKWebView oculto en el mismo origen que usaba la Capacitor
/// (`capacitor://localhost`, almacén por defecto) con una página vacía que sirve un `WKURLSchemeHandler`. Escribe en el
/// MISMO archivo que lee la Ruta B (lo probó la espía en iOS 17.5, 18.6 y 26.5, docs/NATIVA_SPIKE_ALMACENAMIENTO.md).
///
/// La app no declara `WKAppBoundDomains` y no hace falta: la espía leyó y escribió igual sin ellos.
@MainActor
final class EscritorLegado: NSObject, WKNavigationDelegate, WKURLSchemeHandler {
    enum Falla: Error, CustomStringConvertible {
        case sinVentana
        case timeout(String)
        case procesoMuerto
        case navegacion(String)
        case respuesta(String)

        var description: String {
            switch self {
            case .sinVentana: return "sin ventana donde poner el WebView"
            case .timeout(let s): return "timeout (\(s))"
            case .procesoMuerto: return "murió el proceso de contenido"
            case .navegacion(let s): return "navegación: \(s)"
            case .respuesta(let s): return "respuesta: \(s)"
            }
        }
    }

    private var webView: WKWebView?
    /// Cada intento tiene su número: el timeout de un intento viejo no corta al que sigue.
    private var intento = 0
    private var esperaCarga: CheckedContinuation<Void, Error>?
    private var esperaScript: CheckedContinuation<[String: String], Error>?

    private static let pagina = Data("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>".utf8)

    /// Corre `FaseRemotaLegado.scriptEscritura` y devuelve qué pasó con cada clave. Si el proceso de contenido muere
    /// (pasa con poca memoria) o algo no contesta a tiempo, arma un WebView nuevo y reintenta.
    func escribir(_ cambios: FaseRemotaLegado.CambiosEscritura, timeout: Duration = .seconds(20), intentos: Int = 3) async throws -> [String: String] {
        var ultimo: Error = Falla.sinVentana
        for n in 1...max(1, intentos) {
            do {
                defer { desarmar() }
                try await cargarPagina(timeout: timeout)
                return try await correr(cambios, timeout: timeout)
            } catch Falla.sinVentana {
                throw Falla.sinVentana
            } catch {
                ultimo = error
                RegistroLegado.anotar("escritura de vuelta, intento \(n): \(error)")
                try? await Task.sleep(for: .seconds(n))
            }
        }
        throw ultimo
    }

    private func cargarPagina(timeout: Duration) async throws {
        guard let ventana = Self.ventana() else { throw Falla.sinVentana }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(self, forURLScheme: "capacitor")
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.isHidden = true
        wv.isUserInteractionEnabled = false
        wv.navigationDelegate = self
        ventana.addSubview(wv)   // adjunto pero oculto, como la espía: fuera de la jerarquía WebKit lo puede suspender
        webView = wv
        intento += 1
        let este = intento
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            esperaCarga = c
            wv.load(URLRequest(url: URL(string: "capacitor://localhost/")!))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.intento == este else { return }
                self.terminarCarga(.failure(Falla.timeout("carga")))
            }
        }
    }

    private func correr(_ cambios: FaseRemotaLegado.CambiosEscritura, timeout: Duration) async throws -> [String: String] {
        guard let wv = webView else { throw Falla.procesoMuerto }
        let este = intento
        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: String], Error>) in
            esperaScript = c
            wv.callAsyncJavaScript(FaseRemotaLegado.scriptEscritura, arguments: FaseRemotaLegado.argumentosEscritura(cambios),
                                   in: nil, in: .page) { [weak self] r in
                let salida: Result<[String: String], Error>
                switch r {
                case .success(let v):
                    if let d = v as? [String: Any] {
                        salida = .success(d.compactMapValues { $0 as? String })
                    } else {
                        salida = .failure(Falla.respuesta("\(type(of: v))"))
                    }
                case .failure(let e):
                    salida = .failure(Falla.respuesta("\(e)"))
                }
                MainActor.assumeIsolated {
                    guard let self, self.intento == este else { return }
                    self.terminarScript(salida)
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, self.intento == este else { return }
                self.terminarScript(.failure(Falla.timeout("script")))
            }
        }
    }

    private func terminarCarga(_ r: Result<Void, Error>) {
        guard let c = esperaCarga else { return }
        esperaCarga = nil
        c.resume(with: r)
    }

    private func terminarScript(_ r: Result<[String: String], Error>) {
        guard let c = esperaScript else { return }
        esperaScript = nil
        c.resume(with: r)
    }

    private func desarmar() {
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    static func ventana() -> UIWindow? {
        let ventanas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return ventanas.first(where: \.isKeyWindow) ?? ventanas.first
    }

    // MARK: WKURLSchemeHandler: cualquier pedido a capacitor://localhost recibe la página vacía.

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": "text/html; charset=utf-8"]) else { return }
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(Self.pagina)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { terminarCarga(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        terminarCarga(.failure(Falla.navegacion("\(error)")))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        terminarCarga(.failure(Falla.navegacion("\(error)")))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        terminarCarga(.failure(Falla.procesoMuerto))
        terminarScript(.failure(Falla.procesoMuerto))
    }
}
