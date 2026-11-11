package com.pumpteam.mypump.gimnasio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloCasa
import com.pumpteam.mypump.datos.ModeloGimnasio
import com.pumpteam.mypump.datos.ModeloTecnica
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.LocalRellenoInferior
import com.pumpteam.mypump.diseno.MarcoPantalla
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.raiz.Navegacion
import com.pumpteam.mypump.reglas.Casa
import com.pumpteam.mypump.reglas.DondeEntreno
import com.pumpteam.mypump.reglas.TextosGimnasio
import com.pumpteam.mypump.tecnica.TecnicaPantalla

// «Mi gimnasio y mi técnica» (simplificar, OK de Mati del 11/11): Tu gimnasio (con el interruptor «Entreno en casa»
// adentro) y Mi técnica (lo mandado, su estado y la respuesta de Mati) en una pantalla, cada bloque solo con su palanca de
// siempre (`gimnasio_fotos`, `casa`, `tecnica_video`). Entrada: un renglón grande al final de Entreno; con una respuesta de
// técnica de los últimos 7 días, un botón que la abre directo (un toque). Gemela de `DondeEntrenoRaiz` de iOS.

/** «Tu gimnasio»: con la entrada habilitada, o con «Entreno en casa» para ofrecer. */
@Composable
private fun gimnasioDondeEntreno(modelo: ModeloApp): ModeloGimnasio? {
    val g = modelo.gimnasio.collectAsStateWithLifecycle().value ?: return null
    val estado by g.estado.collectAsStateWithLifecycle()
    val casa = casaDondeEntreno(modelo)
    return g.takeIf { (estado != null && it.entradaVisible) || casa != null }
}

/** «Entreno en casa» (palanca `casa`), con el estado de la cuenta y el gimnasio activo. */
@Composable
private fun casaDondeEntreno(modelo: ModeloApp): ModeloCasa? {
    val g = modelo.gimnasio.collectAsStateWithLifecycle().value ?: return null
    val estadoGimnasio by g.estado.collectAsStateWithLifecycle()
    val c = modelo.casa.collectAsStateWithLifecycle().value ?: return null
    val estado by c.estado.collectAsStateWithLifecycle()
    return c.takeIf { it.palancaRecordada && estadoGimnasio != null && estado != null }
}

/** «Mi técnica», con la sección habilitada para la cuenta. */
@Composable
private fun tecnicaDondeEntreno(modelo: ModeloApp): ModeloTecnica? {
    val t = modelo.tecnica.collectAsStateWithLifecycle().value ?: return null
    val estado by t.estado.collectAsStateWithLifecycle()
    return t.takeIf { estado != null }
}

/** El título de cada bloque. */
@Composable
fun TituloBloqueDondeEntreno(texto: String, etiqueta: String) {
    Text(
        texto,
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.Bold,
        color = MyPump.colores.texto,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp).semantics { heading() }.testTag(etiqueta),
    )
}

/**
 * El renglón grande al final de Entreno: abre «Mi gimnasio y mi técnica». Con una respuesta de técnica de los últimos 7 días,
 * un botón que la abre directo. Sin ninguno de los dos bloques, no existe.
 */
@Composable
fun EntradaDondeEntreno(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current ?: return
    val g = gimnasioDondeEntreno(modelo) != null
    val t = tecnicaDondeEntreno(modelo)
    val titulo = DondeEntreno.titulo(g, t != null) ?: return
    val c = MyPump.colores
    val envios = t?.estado?.collectAsStateWithLifecycle()?.value?.visibles.orEmpty()
    val respuesta = DondeEntreno.respuestaReciente(envios)
    Column(modifier.fillMaxWidth().superficieTarjeta().padding(Espacio.m), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 56.dp)
                .clip(RoundedCornerShape(Radio.tarjeta))
                .clickable(role = Role.Button) { navegacion.abrirDondeEntreno(null) }
                .semantics(mergeDescendants = true) {}
                .testTag("donde-entreno-entrada"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Box(Modifier.size(44.dp).background(c.marcaSuave, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Iconos.Pesa, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(titulo, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = c.texto)
                DondeEntreno.bajada(g, t != null)?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario) }
            }
            Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
        }
        if (respuesta != null) {
            BotonMarca(
                DondeEntreno.VER_RESPUESTA,
                alTocar = { navegacion.abrirDondeEntreno(respuesta.id) },
                modifier = Modifier.fillMaxWidth().testTag("donde-entreno-respuesta"),
            )
        }
    }
}

/**
 * La pantalla «Mi gimnasio y mi técnica», encima de Entreno (Atrás vuelve). Con Mi técnica, la de técnica de siempre con el
 * bloque del gimnasio arriba ([TecnicaPantalla] con su pila: la devolución y su video); sin técnica, solo el gimnasio.
 */
@Composable
fun DondeEntrenoPantalla(modelo: ModeloApp, navegacion: Navegacion) {
    val g = gimnasioDondeEntreno(modelo)
    val casa = casaDondeEntreno(modelo)
    val t = tecnicaDondeEntreno(modelo)
    val titulo = DondeEntreno.titulo(g != null, t != null) ?: DondeEntreno.TITULO_AMBOS
    val cerrar = { navegacion.cerrarDondeEntreno() }
    LaunchedEffect(Unit) {
        modelo.gimnasio.value?.refrescar()
        casa?.refrescar()
    }
    val bloqueGimnasio: @Composable ColumnScope.() -> Unit = {
        if (g != null) BloqueGimnasio(g, casa, abrir = { navegacion.gimnasio = true })
    }
    if (t != null) {
        Box(Modifier.fillMaxSize().testTag("donde-entreno")) {
            TecnicaPantalla(t, modelo, alVolver = cerrar, titulo = titulo, cabeza = bloqueGimnasio, conTitulo = g != null, devolucion = navegacion.devolucionDondeEntreno)
        }
    } else {
        MarcoPantalla(titulo, alVolver = cerrar) { relleno ->
            Column(
                Modifier
                    .padding(relleno)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = Espacio.m)
                    .padding(top = Espacio.s, bottom = Espacio.xl + LocalRellenoInferior.current)
                    .testTag("donde-entreno"),
                verticalArrangement = Arrangement.spacedBy(Espacio.m),
            ) {
                bloqueGimnasio()
                if (g == null) NotaGimnasio(DondeEntreno.VACIO, Modifier.testTag("donde-entreno-vacio"))
            }
        }
    }
}

@Composable
private fun BloqueGimnasio(g: ModeloGimnasio, casa: ModeloCasa?, abrir: () -> Unit) {
    val c = MyPump.colores
    TituloBloqueDondeEntreno(DondeEntreno.TITULO_GIMNASIO, "donde-entreno-bloque-gimnasio")
    if (casa != null) InterruptorCasa(casa)
    val estado by g.estado.collectAsStateWithLifecycle()
    if (estado != null && g.entradaVisible) {
        val estadoCasa = casa?.estado?.collectAsStateWithLifecycle()?.value
        Row(
            Modifier
                .fillMaxWidth()
                .superficieTarjeta()
                .clip(RoundedCornerShape(Radio.tarjeta))
                .clickable(role = Role.Button, onClick = abrir)
                .heightIn(min = 64.dp)
                .padding(Espacio.m)
                .testTag("donde-entreno-gimnasio"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(TextosGimnasio.tarjetaTitulo, style = MaterialTheme.typography.titleMedium, color = c.texto)
                Text(
                    if (Casa.pantalla(estadoCasa) == Casa.Pantalla.LISTA) Casa.Textos.LISTA_TITULO else detalleTarjetaGimnasio(g),
                    style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
                )
            }
            Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
        }
    }
}
