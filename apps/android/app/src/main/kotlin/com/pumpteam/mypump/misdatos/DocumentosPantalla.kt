package com.pumpteam.mypump.misdatos

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloDocumentos
import com.pumpteam.mypump.diseno.Aviso
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.BotonSecundario
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.IconoAzulejo
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.PantallaConTitulo
import com.pumpteam.mypump.diseno.PieSeccion
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.abrirEnNavegadorDelSistema
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.modelos.DocumentoFirma
import com.pumpteam.mypump.modelos.EstadoDocumento
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.TextosDocumentos
import kotlinx.coroutines.launch

/**
 * Documentos (contrato y consentimiento), desde Mis datos. Gemelo de `DocumentosView.swift`. La app no firma: cada
 * documento muestra su estado y, al tocarlo, se pide el enlace personal al servicio de firma y se abre en el navegador del
 * sistema (no en una Custom Tab ni en un WebView), donde se lee, se firma o se baja el PDF.
 */
@Composable
fun DocumentosPantalla(modelo: ModeloDocumentos, alVolver: () -> Unit) {
    val documentos by modelo.documentos.collectAsStateWithLifecycle()
    val contexto = LocalContext.current
    val alcance = rememberCoroutineScope()
    /** El documento cuyo enlace se está pidiendo (su botón muestra la ruedita y los demás esperan). */
    var abriendo by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { modelo.refrescar() }
    // Sin documentos (un error, o ya no hay): de vuelta a Mis datos.
    LaunchedEffect(documentos.isEmpty()) { if (documentos.isEmpty()) alVolver() }

    fun abrir(d: DocumentoFirma) {
        if (abriendo != null) return
        abriendo = d.id
        error = false
        alcance.launch {
            try {
                val url = modelo.enlace(d)
                if (url == null || !abrirEnNavegadorDelSistema(contexto, url)) error = true
            } finally {
                abriendo = null
            }
        }
    }

    PantallaConTitulo(TextosDocumentos.titulo, alVolver = alVolver, desplazable = true, modifier = Modifier.testTag("documentos-pantalla")) {
        if (error) {
            Aviso(
                Iconos.Alerta, TextosDocumentos.errorAbrirTitulo, TextosDocumentos.errorAbrirDetalle,
                modifier = Modifier.padding(horizontal = Espacio.m).testTag("documentos-error"),
            )
        }
        Column(Modifier.padding(horizontal = Espacio.m)) {
            Column(Modifier.fillMaxWidth().superficieTarjeta()) {
                documentos.forEachIndexed { i, d ->
                    if (i > 0) Separador(sangria = Espacio.m)
                    FilaDocumento(d, abriendo = abriendo == d.id, ocupado = abriendo != null) { abrir(d) }
                }
            }
            PieSeccion(TextosDocumentos.pie)
        }
    }
}

@Composable
private fun FilaDocumento(d: DocumentoFirma, abriendo: Boolean, ocupado: Boolean, alTocar: () -> Unit) {
    val c = MyPump.colores
    val pendiente = d.estado == EstadoDocumento.PENDIENTE
    Column(Modifier.fillMaxWidth().padding(Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s), verticalAlignment = Alignment.CenterVertically) {
            IconoAzulejo(Iconos.Documento, if (pendiente) c.alerta else c.marcaTexto)
            Column(Modifier.weight(1f)) {
                Text(TextosDocumentos.nombre(d.tipo), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
                Text(
                    TextosDocumentos.estado(d),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (pendiente) c.alerta else c.textoSecundario,
                )
            }
        }
        val etiqueta = Modifier.testTag("documento-${d.id}")
        if (pendiente) {
            BotonMarca(TextosDocumentos.boton(d.estado), alTocar, etiqueta, habilitado = !ocupado, compacto = true, cargando = abriendo)
        } else {
            BotonSecundario(TextosDocumentos.boton(d.estado), alTocar, etiqueta, compacto = true, tono = c.marcaTexto, habilitado = !ocupado, cargando = abriendo)
        }
    }
}

/**
 * «Tenés el contrato pendiente de firma», arriba de Entreno: un renglón discreto que lleva a Documentos. No bloquea nada.
 * Solo con un contrato de coaching pendiente (el consentimiento solo no lo prende); en la demo y sin cuenta no hay.
 */
@Composable
fun AvisoContratoPendiente(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val m by modelo.documentos.collectAsStateWithLifecycle()
    val docs = m ?: return
    val lista by docs.documentos.collectAsStateWithLifecycle()
    if (esDemo || !TextosDocumentos.hayContratoPendiente(lista)) return
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.control + 6.dp)
            .clickable(role = Role.Button) { navegacion?.irADocumentos() }
            .padding(Espacio.s)
            .testTag("aviso-contrato"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(32.dp).clip(CircleShape).background(c.alerta.copy(alpha = 0.14f)), contentAlignment = Alignment.Center) {
            Icon(Iconos.Documento, contentDescription = null, tint = c.alerta, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(TextosDocumentos.avisoContrato, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(TextosDocumentos.avisoContratoDetalle, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
}
