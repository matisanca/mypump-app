package com.pumpteam.mypump.dieta

import android.content.Context
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.reglas.CodigoBarras

/**
 * El escáner de códigos de barras de «Agregar alimento» (2.1, S3; gemelo de EscanerCodigo.swift): el de Google (Google
 * code scanner, de Play Services), que abre su propia pantalla de cámara y devuelve solo el código. Por eso MyPump no pide
 * el permiso de cámara. Solo EAN-13, EAN-8, UPC-A y UPC-E.
 */
object EscanerCodigo {
    sealed interface Resultado {
        /** El código ya normalizado ([CodigoBarras.normalizar]). */
        data class Leido(val codigo: String) : Resultado
        data object Cancelado : Resultado
        /** Un código que no es EAN/UPC (un QR, un código interno de un comercio). */
        data object Invalido : Resultado
        /** Sin Play Services, o el escáner todavía se está bajando. */
        data class NoDisponible(val bajando: Boolean) : Resultado
    }

    fun escanear(contexto: Context, alTerminar: (Resultado) -> Unit) {
        // Las pruebas de interfaz: el código de [Entorno], sin abrir el escáner de Google.
        Entorno.codigoDePrueba?.let { c ->
            alTerminar(CodigoBarras.normalizar(c)?.let { Resultado.Leido(it) } ?: Resultado.Invalido)
            return
        }
        val opciones = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_EAN_13, Barcode.FORMAT_EAN_8, Barcode.FORMAT_UPC_A, Barcode.FORMAT_UPC_E)
            .enableAutoZoom()
            .build()
        val escaner = try {
            GmsBarcodeScanning.getClient(contexto, opciones)
        } catch (_: Exception) {
            alTerminar(Resultado.NoDisponible(bajando = false))
            return
        }
        escaner.startScan()
            .addOnSuccessListener { b ->
                val codigo = b.rawValue?.let { CodigoBarras.normalizar(it, upcE = b.format == Barcode.FORMAT_UPC_E) }
                alTerminar(codigo?.let { Resultado.Leido(it) } ?: Resultado.Invalido)
            }
            .addOnCanceledListener { alTerminar(Resultado.Cancelado) }
            .addOnFailureListener { e ->
                val bajando = (e as? MlKitException)?.errorCode == MlKitException.UNAVAILABLE
                if (bajando) {
                    // El módulo no estaba (el meta-data del manifest lo pide al instalar; si no llegó, se pide ahora).
                    runCatching {
                        ModuleInstall.getClient(contexto).installModules(
                            com.google.android.gms.common.moduleinstall.ModuleInstallRequest.newBuilder().addApi(escaner).build(),
                        )
                    }
                }
                alTerminar(Resultado.NoDisponible(bajando))
            }
    }
}
