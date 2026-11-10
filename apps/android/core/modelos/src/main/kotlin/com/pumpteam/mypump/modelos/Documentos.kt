package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * Documentos (contrato y consentimiento, firma propia en `firma.mypumpteam.com`): lo que devuelve
 * `mypump_contrato_get(p_token)`, `{"documentos":[{id, tipo, titulo, estado, firmado_en, revocado_en}], "pendientes": n}`.
 * La app no firma nada: muestra el estado y abre la página del servicio en el navegador del sistema. Gemelo de
 * `Documentos.swift`.
 *
 * Tolerante como el resto: un documento con un tipo o un estado que la app no conoce (o sin id) se descarta sin tirar los
 * demás; una respuesta con otra forma es una lista vacía.
 */
enum class TipoDocumento(val valor: String) {
    SERVICIO_AR("servicio_ar"),
    SERVICIO_EXT("servicio_ext"),
    CONSENTIMIENTO_AR("consentimiento_ar"),
    ;

    /** El contrato de coaching (Argentina o exterior); el consentimiento es otra cosa. */
    val esContrato: Boolean get() = this == SERVICIO_AR || this == SERVICIO_EXT

    companion object {
        fun de(valor: String?): TipoDocumento? = entries.firstOrNull { it.valor == valor }
    }
}

enum class EstadoDocumento(val valor: String) {
    PENDIENTE("pendiente"),
    FIRMADO("firmado"),
    REVOCADO("revocado"),
    ;

    companion object {
        fun de(valor: String?): EstadoDocumento? = entries.firstOrNull { it.valor == valor }
    }
}

data class DocumentoFirma(
    val id: String,
    val tipo: TipoDocumento,
    val estado: EstadoDocumento,
    /** El título de la plantilla; la app muestra su propio nombre por tipo (`TextosDocumentos.nombre`). */
    val titulo: String? = null,
    /** timestamptz ISO, como lo da `jsonb_build_object`. */
    val firmadoEn: String? = null,
    val revocadoEn: String? = null,
) {
    companion object {
        /** Un elemento de `documentos`, o null si no es un objeto, no tiene id, o el tipo o el estado son desconocidos. */
        fun desde(e: JsonElement): DocumentoFirma? {
            val o = e as? JsonObject ?: return null
            val id = o.texto("id")?.ifEmpty { null } ?: return null
            val tipo = TipoDocumento.de(o.texto("tipo")) ?: return null
            val estado = EstadoDocumento.de(o.texto("estado")) ?: return null
            return DocumentoFirma(id, tipo, estado, o.texto("titulo"), o.texto("firmado_en"), o.texto("revocado_en"))
        }

        /** La respuesta entera de `mypump_contrato_get`. Cualquier otra forma: ninguno. */
        fun lista(e: JsonElement?): List<DocumentoFirma> = (e as? JsonObject)?.lista("documentos", ::desde) ?: emptyList()

        fun lista(v: ValorJson?): List<DocumentoFirma> = v?.let { lista(it.aJson()) } ?: emptyList()
    }
}

/**
 * Lo que contesta `POST <firma>/api/app/documentos`: `{"documentos":[{id, tipo, estado, firmado_en, url}]}`. Solo importan
 * el id y el enlace; un elemento sin los dos se descarta.
 */
data class EnlaceDocumento(val id: String, val url: String) {
    companion object {
        fun desde(e: JsonElement): EnlaceDocumento? {
            val o = e as? JsonObject ?: return null
            val id = o.texto("id")?.ifEmpty { null } ?: return null
            val url = o.texto("url")?.ifEmpty { null } ?: return null
            return EnlaceDocumento(id, url)
        }

        fun lista(v: ValorJson?): List<EnlaceDocumento> = (v?.aJson() as? JsonObject)?.lista("documentos", ::desde) ?: emptyList()
    }
}
