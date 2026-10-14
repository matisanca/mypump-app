package com.pumpteam.mypump.spike

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File

/**
 * Abre un WebView en el MISMO origen que la Capacitor (`https://localhost`, su `androidScheme` por defecto), con el
 * almacén por defecto (sin sufijo de directorio), lee todo el `localStorage`, escribe la marca y deja el informe en
 * `files/spike-informe.json`. La página la sirve la propia app (`shouldInterceptRequest`): no sale nada a la red.
 * Chromium guarda el localStorage en tandas: el script de la prueba mide cuánto hay que esperar después de escribir
 * para que la marca sobreviva a un cierre forzado.
 */
class Espia : Activity() {
    private val leer = """
        (function () {
          const valores = {};
          for (let i = 0; i < localStorage.length; i++) { const k = localStorage.key(i); valores[k] = localStorage.getItem(k); }
          const previa = localStorage.getItem('mypump_nativa_marca');
          localStorage.setItem('mypump_nativa_marca', JSON.stringify({ espia: 1, ts: Date.now() }));
          return JSON.stringify({ origen: location.origin, n: Object.keys(valores).length, valores: valores, previa: previa });
        })()
    """.trimIndent()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val inicio = System.currentTimeMillis()
        val web = WebView(this)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
                if (request.url.host == "localhost") {
                    WebResourceResponse("text/html", "utf-8", "<!doctype html><meta charset=utf-8><title>migrar</title>".byteInputStream())
                } else {
                    null
                }

            override fun onPageFinished(view: WebView, url: String) {
                view.evaluateJavascript(leer) { crudo ->
                    // evaluateJavascript devuelve el valor codificado como JSON: acá es un texto con el JSON adentro.
                    val texto = (JSONTokener(crudo).nextValue() as? String) ?: "{}"
                    val informe = JSONObject(texto)
                    informe.put("url", url)
                    informe.put("android", Build.VERSION.SDK_INT)
                    informe.put("webview", WebView.getCurrentWebViewPackage()?.versionName)
                    informe.put("ms", System.currentTimeMillis() - inicio)
                    File(filesDir, "spike-informe.json").writeText(informe.toString())
                    File(filesDir, "spike-listo").writeText("1")
                }
            }
        }
        setContentView(web)
        web.loadUrl("https://localhost/__migrar")
    }
}
