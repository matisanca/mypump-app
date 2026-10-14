package com.pumpteam.mypump.legado

import android.annotation.SuppressLint
import android.content.Context
import android.os.Build
import android.os.Looper
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import com.pumpteam.mypump.datos.LecturaJs
import java.io.ByteArrayInputStream
import kotlin.coroutines.cancellation.CancellationException
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** Lo que puede salir mal con el WebView. Los textos van al registro: nunca llevan contenido. */
internal sealed class FallaPagina(motivo: String) : Exception(motivo) {
    class SinWebView(tipo: String) : FallaPagina("no se pudo crear el WebView ($tipo)")

    class Timeout(paso: String) : FallaPagina("timeout ($paso)")

    class ProcesoMuerto : FallaPagina("murió el proceso del renderer")

    class Navegacion(codigo: Int) : FallaPagina("navegación: error $codigo")
}

/**
 * Un WebView oculto en el MISMO origen que la Capacitor (`https://localhost`, su `androidScheme` por defecto) y con el
 * almacén por defecto del WebView (sin sufijo de directorio): ve el mismo `localStorage` que ella. Es lo que probó la
 * espía en el emulador (docs/NATIVA_SPIKE_ALMACENAMIENTO.md). La app nunca cambia ni el origen ni el directorio de datos
 * del WebView: con eso perdería lo de la Capacitor.
 *
 * La página se carga con `loadDataWithBaseURL`: el documento toma el origen de la URL base SIN pedirla, así que no pasa
 * por el service worker que la web registró para ese origen (`sw.js`, network-first para las navegaciones: sin red
 * contestaría la app vieja guardada en su caché, que arrancaría adentro de este WebView). Nada sale a la red: la página
 * no tiene recursos y cualquier pedido se contesta vacío.
 *
 * Se usa desde el hilo principal ([conPagina]).
 */
internal class PaginaLegado(private val contexto: Context) {
    private var web: WebView? = null
    private var esperaCarga: CancellableContinuation<Result<Unit>>? = null
    private var esperaScript: CancellableContinuation<Result<String?>>? = null

    private val cliente = object : WebViewClient() {
        /**
         * La página misma llega acá como un `data:` (así implementa el WebView `loadDataWithBaseURL`, medido en el
         * emulador): esa pasa. Cualquier otra cosa se contesta vacía; contestar también la `data:` deja el documento en
         * `chrome-error://` sin `localStorage`.
         */
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
            if (request.url.scheme == "data") null else WebResourceResponse("text/plain", "utf-8", 404, "Sin recursos", emptyMap(), ByteArrayInputStream(ByteArray(0)))

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

        override fun onPageFinished(view: WebView, url: String?) {
            if (view === web) terminarCarga(Result.success(Unit))
        }

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (view === web && request.isForMainFrame) terminarCarga(Result.failure(FallaPagina.Navegacion(error.errorCode)))
        }

        /** Con poca memoria el sistema mata el renderer. Hay que contestar true: si no, mata también a la app. */
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            if (view === web) {
                terminarCarga(Result.failure(FallaPagina.ProcesoMuerto()))
                terminarScript(Result.failure(FallaPagina.ProcesoMuerto()))
                cerrar()
            } else {
                view.destroy()
            }
            return true
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    suspend fun abrir(esperaMs: Long) {
        check(Looper.myLooper() == Looper.getMainLooper()) { "el WebView va en el hilo principal" }
        val wv = try {
            WebView(contexto)
        } catch (e: Exception) {
            // Sin WebView instalado, o actualizándose justo ahora (MissingWebViewPackageException).
            throw FallaPagina.SinWebView(e.javaClass.simpleName)
        }
        web = wv
        wv.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            blockNetworkLoads = true
            cacheMode = WebSettings.LOAD_NO_CACHE
        }
        wv.webViewClient = cliente
        val r = withTimeoutOrNull(esperaMs) {
            suspendCancellableCoroutine<Result<Unit>> { c ->
                esperaCarga = c
                c.invokeOnCancellation { if (esperaCarga === c) esperaCarga = null }
                wv.loadDataWithBaseURL("${LecturaJs.ORIGEN}/__migrar", PAGINA, "text/html", "utf-8", null)
            }
        } ?: throw FallaPagina.Timeout("carga")
        r.getOrThrow()
    }

    /** Corre el script y devuelve su valor en JSON, como lo pasa `evaluateJavascript` (null si el script tiró). */
    suspend fun evaluar(js: String, esperaMs: Long): String? {
        val wv = web ?: throw FallaPagina.ProcesoMuerto()
        val r = withTimeoutOrNull(esperaMs) {
            suspendCancellableCoroutine<Result<String?>> { c ->
                esperaScript = c
                c.invokeOnCancellation { if (esperaScript === c) esperaScript = null }
                wv.evaluateJavascript(js) { valor -> if (esperaScript === c) terminarScript(Result.success(valor)) }
            }
        } ?: throw FallaPagina.Timeout("script")
        return r.getOrThrow()
    }

    private fun terminarCarga(r: Result<Unit>) {
        val c = esperaCarga ?: return
        esperaCarga = null
        if (c.isActive) c.resume(r)
    }

    private fun terminarScript(r: Result<String?>) {
        val c = esperaScript ?: return
        esperaScript = null
        if (c.isActive) c.resume(r)
    }

    /** Para las pruebas en el emulador: mata el renderer como lo haría el sistema con poca memoria (Android 10+). */
    internal fun matarRenderer(): Boolean =
        if (Build.VERSION.SDK_INT >= 29) web?.webViewRenderProcess?.terminate() ?: false else false

    fun cerrar() {
        val wv = web ?: return
        web = null
        esperaCarga = null
        esperaScript = null
        wv.webViewClient = WebViewClient()
        wv.stopLoading()
        wv.destroy()
    }

    companion object {
        private const val PAGINA = "<!doctype html><html><head><meta charset=\"utf-8\"><title>migrar</title></head><body></body></html>"
    }
}

/**
 * Abre una página, corre [bloque] y la cierra. Si algo falla (el renderer murió, un timeout, una respuesta rota), arma un
 * WebView nuevo y reintenta; después del último intento TIRA: un error nunca es "no había nada".
 */
internal suspend fun <T> conPagina(
    contexto: Context,
    intentos: Int,
    esperaMs: Long,
    anotar: (String) -> Unit,
    bloque: suspend (PaginaLegado) -> T,
): T = withContext(Dispatchers.Main) {
    var ultimo: Exception? = null
    for (n in 1..maxOf(1, intentos)) {
        val p = PaginaLegado(contexto.applicationContext)
        try {
            p.abrir(esperaMs)
            return@withContext bloque(p)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            ultimo = e
            anotar("intento $n: ${describir(e)}")
        } finally {
            p.cerrar()
        }
        if (n < intentos) delay(n * 1_000L)
    }
    throw ultimo ?: FallaPagina.Timeout("sin intentos")
}

/** Para el registro: nuestras fallas con su texto (sin contenido); cualquier otra, solo su tipo (un mensaje de un parser
 *  puede traer un pedazo del `localStorage`, y ahí hay tokens). */
internal fun describir(e: Throwable): String = when (e) {
    is FallaPagina, is com.pumpteam.mypump.datos.FallaLectura -> e.message ?: e.javaClass.simpleName
    is java.io.IOException -> "${e.javaClass.simpleName}: ${e.message}"   // rutas de archivos, nunca valores
    else -> e.javaClass.simpleName
}
