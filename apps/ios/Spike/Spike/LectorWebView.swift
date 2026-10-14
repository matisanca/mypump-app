import UIKit
import WebKit

/// Ruta A: abre un WKWebView en el mismo origen que usaba Capacitor (`capacitor://localhost`, con el almacén por
/// defecto y la misma configuración de app-bound domains) y le pide a una página mínima todo el localStorage.
@MainActor
final class LectorWebView: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKURLSchemeHandler {
    private var webView: WKWebView?
    private var espera: CheckedContinuation<[String: String], Error>?

    private static let pagina = """
    <!doctype html><html><head><meta charset="utf-8"></head><body><script>
    (function () {
      try {
        var o = {};
        for (var i = 0; i < localStorage.length; i++) { var k = localStorage.key(i); o[k] = localStorage.getItem(k); }
        window.webkit.messageHandlers.legado.postMessage(JSON.stringify(o));
      } catch (e) {
        window.webkit.messageHandlers.legado.postMessage(JSON.stringify({ "__error__": String(e) }));
      }
    })();
    </script></body></html>
    """

    func leer(en contenedor: UIView, limitarAppBound: Bool, timeout: Duration = .seconds(15)) async throws -> [String: String] {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.setURLSchemeHandler(self, forURLScheme: "capacitor")
        config.limitsNavigationsToAppBoundDomains = limitarAppBound
        config.userContentController.add(self, name: "legado")

        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.isHidden = true
        wv.navigationDelegate = self
        contenedor.addSubview(wv)
        webView = wv

        return try await withCheckedThrowingContinuation { (c: CheckedContinuation<[String: String], Error>) in
            espera = c
            wv.load(URLRequest(url: URL(string: "capacitor://localhost/__migrar.html")!))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                self?.fallar(ErrorLegado.webView("timeout"))
            }
        }
    }

    func escribir(clave: String, valor: String) async throws -> String? {
        guard let wv = webView else { return nil }
        let r = try await wv.callAsyncJavaScript(
            "localStorage.setItem(k, v); return localStorage.getItem(k);",
            arguments: ["k": clave, "v": valor],
            contentWorld: .page)
        return r as? String
    }

    // MARK: WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                         headerFields: ["Content-Type": "text/html; charset=utf-8"]) else { return }
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(Data(Self.pagina.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let c = espera else { return }
        espera = nil
        guard let s = message.body as? String, let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] else {
            c.resume(throwing: ErrorLegado.webView("mensaje inválido"))
            return
        }
        if let e = o["__error__"] { c.resume(throwing: ErrorLegado.webView(e)) } else { c.resume(returning: o) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { fallar(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { fallar(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fallar(ErrorLegado.webView("murió el proceso de contenido")) }

    private func fallar(_ e: Error) {
        guard let c = espera else { return }
        espera = nil
        c.resume(throwing: e)
    }
}
