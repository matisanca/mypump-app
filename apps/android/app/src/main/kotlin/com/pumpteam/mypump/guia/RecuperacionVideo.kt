package com.pumpteam.mypump.guia

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.PlaybackException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Lo que muestra el video cuando no carga. */
enum class FallaVideo {
    /** El teléfono no tiene red: «Necesitás conexión para ver el video» (vuelve solo cuando hay red). */
    SIN_RED,

    /** Con red, no cargó después de los reintentos: «No se pudo cargar el video». */
    NO_CARGA,
}

/**
 * Qué hacer cuando un reproductor de la guía falla. Con red, un corte, un timeout o un primer buffer lento no son «sin
 * conexión»: se reintenta solo (a 1, 2 y 4 s) sin mostrar nada. Sin red, se muestra [FallaVideo.SIN_RED] y se vuelve a
 * cargar solo apenas hay red. Si con red no carga después de los reintentos (o el error no es de carga), [FallaVideo.NO_CARGA].
 *
 * El 4-nov, en Android 9 (emulador), una vez el primer video tiró un error de carga con red: antes eso mostraba «Necesitás
 * conexión» hasta tocar «Reintentar».
 */
class RecuperacionVideo(
    private val contexto: Context,
    private val alcance: CoroutineScope,
    private val recargar: () -> Unit,
) {
    var falla by mutableStateOf<FallaVideo?>(null)
        private set

    private var intentos = 0
    private var espera: Job? = null
    private var oyente: ConnectivityManager.NetworkCallback? = null

    fun alFallar(e: PlaybackException) {
        Log.w(ETIQUETA, "el video falló: ${e.errorCodeName} (intento ${intentos + 1})", e)
        espera?.cancel()
        when {
            !hayRed() -> {
                falla = FallaVideo.SIN_RED
                esperarRed()
            }
            esPasajero(e) && intentos < ESPERAS_MS.size -> {
                val ms = ESPERAS_MS[intentos++]
                espera = alcance.launch {
                    delay(ms)
                    recargar()
                }
            }
            else -> falla = FallaVideo.NO_CARGA
        }
    }

    /** Cargó (o se cargó otro video, o el cliente tocó «Reintentar»): de cero. */
    fun reiniciar() {
        intentos = 0
        falla = null
        espera?.cancel()
        soltarRed()
    }

    fun soltar() = reiniciar()

    private fun hayRed(): Boolean {
        val cm = contexto.getSystemService(ConnectivityManager::class.java) ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork ?: return false) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun esperarRed() {
        if (oyente != null) return
        val cm = contexto.getSystemService(ConnectivityManager::class.java) ?: return
        val o = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                alcance.launch(Dispatchers.Main) {
                    if (falla == FallaVideo.SIN_RED) {
                        reiniciar()
                        recargar()
                    }
                }
            }
        }
        runCatching { cm.registerDefaultNetworkCallback(o) }.onSuccess { oyente = o }
    }

    private fun soltarRed() {
        val o = oyente ?: return
        oyente = null
        runCatching { contexto.getSystemService(ConnectivityManager::class.java)?.unregisterNetworkCallback(o) }
    }

    companion object {
        private const val ETIQUETA = "MyPumpGuia"
        val ESPERAS_MS = longArrayOf(1_000, 2_000, 4_000)

        /** Errores de carga (red, timeout) y del decodificador al arrancar (en Android viejos queda ocupado un momento). */
        fun esPasajero(e: PlaybackException): Boolean = e.errorCode in 2000..2999 ||
            e.errorCode == PlaybackException.ERROR_CODE_TIMEOUT ||
            e.errorCode == PlaybackException.ERROR_CODE_DECODER_INIT_FAILED ||
            e.errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED
    }
}
