package com.pumpteam.mypump.guia

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import java.time.Instant
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloGuia
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.ReglasGuia
import com.pumpteam.mypump.reglas.ReglasNovedad

/**
 * La tarjeta de «Tu guía» arriba de Entreno (la verde destacada hasta ver todo, después la compacta con el tilde), con lo que dijo el último `entregas_app_resumen` (o la guía en memoria, si es
 * más nueva). Sin guía o con un token que ya no sirve, no se ve. Pasadas 48 h de la videollamada (`mostrar_tarjeta`) o
 * con «Quitar de Entreno», sale sola, sin cartel, y la guía queda en la fila «Ver mi guía» de Mis datos
 * ([ReglasGuia.lugar]). En la demo es la guía de muestra. No pide nada: el resumen lo trae el modelo al abrir la app y al
 * volver a primer plano.
 */
@Composable
fun TarjetaGuiaDe(modelo: ModeloApp, modifier: Modifier = Modifier, solo: ReglasGuia.EstiloTarjeta? = null) {
    val navegacion = LocalNavegacion.current
    val guia by modelo.guia.collectAsStateWithLifecycle()
    val g = guia ?: return
    val (resumen, lugar) = lugarDeLaGuia(g)
    val enMemoria by g.guia.collectAsStateWithLifecycle()
    if (resumen == null || lugar != ReglasGuia.Lugar.ENTRENO) return
    // Con novedad sin ver (2.2.0), la verde con «NOVEDAD EN TU GUÍA»: la compacta solo si también vio los nuevos.
    val novedad = ReglasNovedad.tarjeta(resumen, enMemoria)
    val estilo = if (novedad != null) ReglasGuia.EstiloTarjeta.DESTACADA else ReglasGuia.estiloTarjeta(resumen)
    // Entreno pone la destacada arriba de la cabecera y la compacta debajo: cada lugar pide la suya.
    if (solo != null && estilo != solo) return
    if (estilo == ReglasGuia.EstiloTarjeta.DESTACADA) LaunchedEffect(g) { g.marcarTarjetaVista() }
    when (estilo) {
        ReglasGuia.EstiloTarjeta.DESTACADA -> TarjetaGuiaDestacada(
            resumen,
            // Por cuenta, como iOS: la primera sesión en que esta cuenta ve la tarjeta.
            pulso = g.pulsoTarjeta.collectAsStateWithLifecycle().value == true,
            alAbrir = { navegacion?.guia = true },
            // Lo mismo que «Quitar de Entreno» de la sección: la guía queda en la fila de Mis datos, con el aviso y «Deshacer».
            alOcultar = {
                g.ocultarDeEntreno(true)
                navegacion?.let { it.avisoGuiaOculta++ }
            },
            modifier = modifier,
            novedad = novedad,
            // Grande mientras haya riesgo de que la pasen por alto; en fila solo con la guía de base completa y la
            // novedad con más de 7 días. Con letra grande, siempre grande.
            enFila = novedad != null && LocalDensity.current.fontScale < 1.3f &&
                TamanoGuia.vaEnFila(novedad, resumen, Instant.now()),
        )
        ReglasGuia.EstiloTarjeta.COMPACTA -> TarjetaGuia(resumen, alAbrir = { navegacion?.guia = true }, modifier = modifier)
    }
}

/**
 * El resumen de la guía y dónde va (la tarjeta en Entreno, la fila de Mis datos o nada). Simplificar (11/11): con todo
 * visto, la guía sigue en Entreno como fila discreta de «Tu inicio con Mati» solo 7 días desde que se terminó
 * ([ModeloGuia.completaEn], que se anota acá al detectarlo); después queda en Mis datos. Un video nuevo de Mati la vuelve
 * grande y la cuenta empieza de nuevo al verlo.
 */
@Composable
fun lugarDeLaGuia(g: ModeloGuia): Pair<ResumenGuia?, ReglasGuia.Lugar> {
    val resumen by g.resumen.collectAsStateWithLifecycle()
    val oculta by g.ocultaAMano.collectAsStateWithLifecycle()
    val enMemoria by g.guia.collectAsStateWithLifecycle()
    val completaEn by g.completaEn.collectAsStateWithLifecycle()
    val r = resumen
    val completa = r != null && ReglasNovedad.tarjeta(r, enMemoria) == null && ReglasGuia.estiloTarjeta(r) == ReglasGuia.EstiloTarjeta.COMPACTA
    LaunchedEffect(g, r != null, completa) { if (r != null) g.anotarCompleta(completa) }
    val lugar = ReglasGuia.lugar(r, oculta)
    return r to if (lugar == ReglasGuia.Lugar.ENTRENO && completa && !ReglasGuia.filaInicioVigente(completaEn)) ReglasGuia.Lugar.MIS_DATOS else lugar
}
