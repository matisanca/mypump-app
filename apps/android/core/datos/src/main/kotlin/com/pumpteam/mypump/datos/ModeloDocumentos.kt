package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.DocumentoFirma
import com.pumpteam.mypump.modelos.EnlaceDocumento
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.TextosDocumentos
import java.net.URI
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Documentos (contrato y consentimiento) de una cuenta: `mypump_contrato_get(p_token)`, solo lectura y sin copia en el
 * disco. Se trae al cargar la cuenta y al volver a primer plano (quien firmó en el navegador vuelve y ve «Firmado»).
 * Gemelo de `ModeloDocumentos` de iOS.
 *
 * - Al menos un documento: aparece la fila «Documentos» de Mis datos (y, con un contrato pendiente, el aviso de Entreno).
 * - Cualquier error (sin red, token inválido, la función todavía no está en la base) es «sin documentos», en silencio: ni
 *   la fila ni el aviso aparecen, y nada se rompe.
 *
 * La app no firma: [enlace] pide al servicio de firma el enlace personal del documento y la pantalla lo abre en el
 * navegador del sistema. Como [ModeloSuplementacion], se usa desde el hilo principal.
 */
class ModeloDocumentos(private val cliente: ClienteRpc, private val token: String) {
    private val _documentos = MutableStateFlow<List<DocumentoFirma>>(emptyList())
    val documentos: StateFlow<List<DocumentoFirma>> = _documentos.asStateFlow()

    /** Hay al menos un documento: la fila de Mis datos aparece. */
    val hay: Boolean get() = _documentos.value.isNotEmpty()

    /** Un contrato de coaching sin firmar: el aviso de la pantalla principal. */
    val contratoPendiente: Boolean get() = TextosDocumentos.hayContratoPendiente(_documentos.value)

    private var refrescando = false

    suspend fun refrescar() {
        if (refrescando) return
        refrescando = true
        try {
            val r = cliente.llamar(RPC, mapOf("p_token" to ValorJson.Texto(token)))
            val nuevos = (r as? Resultado.Ok)?.let { DocumentoFirma.lista(it.valor) } ?: emptyList()
            if (nuevos != _documentos.value) _documentos.value = nuevos
        } finally {
            refrescando = false
        }
    }

    /**
     * El enlace personal del documento (firmar, o ver y bajar el PDF si ya está firmado). null si el servicio no contesta,
     * no lo conoce o devuelve algo que no es una página https del propio servicio de firma.
     */
    suspend fun enlace(documento: DocumentoFirma): String? {
        val r = cliente.enlacesDocumentos(token) as? Resultado.Ok ?: return null
        val crudo = EnlaceDocumento.lista(r.valor).firstOrNull { it.id == documento.id }?.url ?: return null
        return enlaceSeguro(crudo, cliente.config.firma)
    }

    companion object {
        const val RPC = "mypump_contrato_get"

        /** Solo se abre https y en el mismo host que el servicio de firma: nunca otro esquema ni otro sitio. */
        fun enlaceSeguro(texto: String, servicio: String): String? {
            val u = runCatching { URI(texto) }.getOrNull() ?: return null
            val host = u.host?.lowercase() ?: return null
            val propio = runCatching { URI(servicio).host?.lowercase() }.getOrNull() ?: return null
            if (u.scheme?.lowercase() != "https" || host != propio) return null
            return texto
        }
    }
}
