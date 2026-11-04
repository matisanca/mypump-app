package com.pumpteam.mypump.guia

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.ModeloGuia
import com.pumpteam.mypump.modelos.ResumenGuia
import com.pumpteam.mypump.raiz.LocalNavegacion
import com.pumpteam.mypump.reglas.ReglasGuia

/**
 * La tarjeta de «Tu guía» arriba de Entreno (la verde destacada hasta ver todo, después la compacta con el tilde), con lo que dijo el último `entregas_app_resumen` (o la guía en memoria, si es
 * más nueva). Sin guía o con un token que ya no sirve, no se ve. Pasadas 48 h de la videollamada (`mostrar_tarjeta`) o
 * con «Quitar de Entreno», sale sola, sin cartel, y la guía queda en la fila «Ver mi guía» de Mis datos
 * ([ReglasGuia.lugar]). En la demo es la guía de muestra. No pide nada: el resumen lo trae el modelo al abrir la app y al
 * volver a primer plano.
 */
@Composable
fun TarjetaGuiaDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val guia by modelo.guia.collectAsStateWithLifecycle()
    val g = guia ?: return
    val (resumen, lugar) = lugarDeLaGuia(g)
    if (resumen == null || lugar != ReglasGuia.Lugar.ENTRENO) return
    when (ReglasGuia.estiloTarjeta(resumen)) {
        ReglasGuia.EstiloTarjeta.DESTACADA -> TarjetaGuiaDestacada(
            resumen,
            pulso = remember { PrimeraSesionGuia.decidir(modelo.preferencias) },
            alAbrir = { navegacion?.guia = true },
            // Lo mismo que «Quitar de Entreno» de la sección: la guía queda en la fila de Mis datos, con el aviso y «Deshacer».
            alOcultar = {
                g.ocultarDeEntreno(true)
                navegacion?.let { it.avisoGuiaOculta++ }
            },
            modifier = modifier,
        )
        ReglasGuia.EstiloTarjeta.COMPACTA -> TarjetaGuia(resumen, alAbrir = { navegacion?.guia = true }, modifier = modifier)
    }
}

/** El resumen de la guía y dónde va (la tarjeta en Entreno, la fila de Mis datos o nada). */
@Composable
fun lugarDeLaGuia(g: ModeloGuia): Pair<ResumenGuia?, ReglasGuia.Lugar> {
    val resumen by g.resumen.collectAsStateWithLifecycle()
    val oculta by g.ocultaAMano.collectAsStateWithLifecycle()
    return resumen to ReglasGuia.lugar(resumen, oculta)
}
