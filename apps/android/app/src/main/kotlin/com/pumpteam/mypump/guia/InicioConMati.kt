package com.pumpteam.mypump.guia

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.ReglasNovedad

// «Tu inicio con Mati» (simplificar, OK de Mati del 11/11): Tu guía, la videollamada de comienzo y «Antes de la
// videollamada» eran tres tarjetas del mismo camino que podían salir juntas arriba de Entreno. Ahora van en una sola, en el
// lugar de la videollamada. Adentro, las piezas de siempre ([TarjetaGuiaDe], [LlamadaEntreno], [TarjetaListaPrevia]), en
// este orden:
// · la guía GRANDE con su avance mientras falte ver algo (o haya un video nuevo de Mati): es lo primero;
// · la videollamada de comienzo (con la lista previa adentro) o «Elegí tu horario» (palanca `elegir_horario`). Cuando ya se
//   puede entrar, va arriba de todo: ese día lo urgente es entrar;
// · la lista previa sola, sin videollamada (palanca `lista_previa`);
// · con todo visto, la fila discreta «Tu guía», durante 7 días desde que se terminó ([lugarDeLaGuia]); después la guía
//   queda en Mis datos.
// Una videollamada de REVISIÓN no es parte del inicio: va con su tarjeta propia, como antes. La bienvenida de la guía,
// «Quitar de Entreno» y el aviso con «Deshacer» no cambian. Gemela de `InicioConMati.swift`.

object TextosInicioConMati {
    const val TITULO = "Tu inicio con Mati"
}

@Composable
fun TarjetaInicioConMati(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val llamada = rememberEstadoVideollamada(modelo)
    // La de revisión, afuera y como siempre.
    if (llamada.deRevision) LlamadaEntreno(llamada, modifier)
    val g = llamada.guia
    if (g == null) {
        // Sin guía (raro: la lista es de la entrega) la lista previa igual se ve, sola, como antes.
        llamada.listaSola?.let { TarjetaListaPrevia(it, abrirGuia = null, modifier = modifier) }
        return
    }
    val (resumen, lugar) = lugarDeLaGuia(g)
    val enMemoria by g.guia.collectAsStateWithLifecycle()
    val enEntreno = resumen != null && lugar == ReglasGuia.Lugar.ENTRENO
    val grande = enEntreno && (ReglasNovedad.tarjeta(resumen!!, enMemoria) != null || ReglasGuia.estiloTarjeta(resumen) == ReglasGuia.EstiloTarjeta.DESTACADA)
    val fila = enEntreno && !grande
    val conLlamada = llamada.hayLlamadaDeInicio
    val lista = llamada.listaSola
    if (!grande && !fila && !conLlamada && lista == null) return
    val llamadaPrimero = conLlamada && llamada.habilitada
    val c = MyPump.colores
    val forma = RoundedCornerShape(Radio.tarjeta + 4.dp)
    Column(
        modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = Radio.tarjeta + 4.dp)
            .border(1.5.dp, c.marca.copy(alpha = 0.45f), forma)
            .clip(forma)
            .testTag("inicio-con-mati")
            .padding(Espacio.s),
        verticalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Encabezado()
        if (llamadaPrimero) LlamadaEntreno(llamada)
        if (grande) TarjetaGuiaDe(modelo, solo = ReglasGuia.EstiloTarjeta.DESTACADA)
        if (conLlamada && !llamadaPrimero) LlamadaEntreno(llamada)
        if (lista != null) TarjetaListaPrevia(lista, llamada.abrirGuia)
        if (fila) TarjetaGuiaDe(modelo, solo = ReglasGuia.EstiloTarjeta.COMPACTA)
    }
}

@Composable
private fun Encabezado() {
    val c = MyPump.colores
    Row(
        Modifier.padding(start = Espacio.xs, top = Espacio.xs, end = Espacio.xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Box(Modifier.size(34.dp).clip(CircleShape).background(c.marca), contentAlignment = Alignment.Center) {
            Icon(Iconos.Bandera, contentDescription = null, tint = c.sobreMarca, modifier = Modifier.size(18.dp))
        }
        Text(
            TextosInicioConMati.TITULO,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = c.texto,
            modifier = Modifier.weight(1f).semantics { heading() }.testTag("inicio-con-mati-titulo"),
        )
    }
}
