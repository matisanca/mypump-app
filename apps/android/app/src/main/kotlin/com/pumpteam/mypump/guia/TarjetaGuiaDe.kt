package com.pumpteam.mypump.guia

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.raiz.LocalNavegacion

/**
 * La tarjeta de «Tu guía» arriba de Entreno, con lo que dijo el último `entregas_app_resumen` (o la guía en memoria, si es
 * más nueva). Sin guía, en la demo o con un token que ya no sirve, no se ve. No pide nada: el resumen lo trae el modelo al
 * abrir la app y al volver a primer plano.
 */
@Composable
fun TarjetaGuiaDe(modelo: ModeloApp, modifier: Modifier = Modifier) {
    val navegacion = LocalNavegacion.current
    val esDemo by modelo.esDemo.collectAsStateWithLifecycle()
    val guia by modelo.guia.collectAsStateWithLifecycle()
    val resumen = guia?.resumen?.collectAsStateWithLifecycle()?.value
    if (esDemo || resumen == null) return
    TarjetaGuia(resumen, alAbrir = { navegacion?.guia = true }, modifier = modifier)
}
