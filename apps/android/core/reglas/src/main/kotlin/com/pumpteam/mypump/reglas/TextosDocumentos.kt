package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.DocumentoFirma
import com.pumpteam.mypump.modelos.EstadoDocumento
import com.pumpteam.mypump.modelos.TipoDocumento
import java.time.ZoneId
import java.util.Locale

/**
 * Los textos de Documentos (contrato y consentimiento), iguales en iOS (`TextosDocumentos` de MyPumpReglas), Android y la
 * web. Nada de pagos ni precios: solo el estado y abrir el documento.
 */
object TextosDocumentos {
    const val titulo = "Documentos"
    const val entradaMisDatos = "Documentos"
    const val pie = "Tu contrato y tu consentimiento. Se abren en el navegador para leerlos, firmarlos o descargarlos."
    const val avisoContrato = "Tenés el contrato pendiente de firma"
    const val avisoContratoDetalle = "Tocá para leerlo y firmarlo."
    const val errorAbrirTitulo = "No pudimos abrir el documento."
    const val errorAbrirDetalle = "Probá de nuevo en un rato o usá el enlace que te llegó por correo."
    const val errorAbrir = "$errorAbrirTitulo $errorAbrirDetalle"
    const val leerYFirmar = "Leer y firmar"
    const val verDocumento = "Ver documento"
    const val pendiente = "Pendiente"

    fun nombre(tipo: TipoDocumento): String = when (tipo) {
        TipoDocumento.SERVICIO_AR, TipoDocumento.SERVICIO_EXT -> "Contrato de coaching"
        TipoDocumento.CONSENTIMIENTO_AR -> "Consentimiento de atención médica"
    }

    /** «Pendiente de firma», «Firmado el 10/11/2026», «Revocado el 10/11/2026». Sin fecha legible, el estado solo. */
    fun estado(d: DocumentoFirma, zona: ZoneId = ZoneId.systemDefault()): String = when (d.estado) {
        EstadoDocumento.PENDIENTE -> "Pendiente de firma"
        EstadoDocumento.FIRMADO -> fechada("Firmado", d.firmadoEn, zona)
        EstadoDocumento.REVOCADO -> fechada("Revocado", d.revocadoEn, zona)
    }

    fun boton(estado: EstadoDocumento): String = if (estado == EstadoDocumento.PENDIENTE) leerYFirmar else verDocumento

    /** El aviso de la pantalla principal: solo con un contrato de coaching pendiente (el consentimiento no lo prende). */
    fun hayContratoPendiente(docs: List<DocumentoFirma>): Boolean =
        docs.any { it.tipo.esContrato && it.estado == EstadoDocumento.PENDIENTE }

    /** "dd/mm/aaaa" de un timestamptz, en la zona del teléfono. null si no se entiende. */
    fun fecha(iso: String?, zona: ZoneId = ZoneId.systemDefault()): String? {
        val i = iso?.let(FechaIsoReglas::instante) ?: return null
        val f = i.atZone(zona)
        return String.format(Locale.ROOT, "%02d/%02d/%04d", f.dayOfMonth, f.monthValue, f.year)
    }

    private fun fechada(palabra: String, iso: String?, zona: ZoneId): String =
        fecha(iso, zona)?.let { "$palabra el $it" } ?: palabra
}
