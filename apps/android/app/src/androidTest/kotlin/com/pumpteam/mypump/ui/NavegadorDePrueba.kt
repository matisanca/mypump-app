package com.pumpteam.mypump.ui

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.pumpteam.mypump.diseno.navegadorConPestanas
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

/**
 * Que [i] (el pedido de abrir un link, capturado por un monitor sin abrir nada) va a un navegador y nunca a MyPump, como
 * lo arma `abrirEnNavegador`. Qué camino toca lo decide el teléfono, así que cada uno se prueba donde existe:
 * - con un navegador con Custom Tabs (Chrome), una Custom Tab con ese navegador fijo (el App Link de MyPump toma todo
 *   `app.mypumpteam.com`, ver NavegadorFueraDeLaAppTest);
 * - sin ninguno (el emulador de Android 9 no trae Chrome; un teléfono puede no tenerlo), un VIEW con el selector de
 *   `CATEGORY_APP_BROWSER`, que solo resuelve a navegadores. Abrir otro navegador en ese caso está bien.
 */
fun comprobarQueVaAlNavegador(i: Intent, contexto: Context) {
    val propio = contexto.packageName
    val conPestanas = navegadorConPestanas(contexto)
    val esCustomTab = i.hasExtra("android.support.customtabs.extra.SESSION")
    if (conPestanas != null) {
        assertTrue("no es una Custom Tab: ${i.extras?.keySet()}", esCustomTab)
        assertEquals("la Custom Tab no fija el navegador", conPestanas, i.`package`)
    } else {
        assertFalse("sin un navegador con Custom Tabs no puede ser una Custom Tab", esCustomTab)
        // Lo que de verdad abriría el sistema con ese pedido: solo navegadores (en el emulador de Android 9, que no tiene
        // ninguno, nada). El sistema resuelve con el selector y no mira el selector del selector.
        val pm = contexto.packageManager
        val navegadores = pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_APP_BROWSER), PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo.packageName }.toSet()
        val abriria = pm.queryIntentActivities(i, PackageManager.MATCH_DEFAULT_ONLY).map { it.activityInfo.packageName }
        assertTrue("sin Custom Tabs el link lo abriría algo que no es un navegador: $abriria", abriria.all { it in navegadores })
        val selector = i.selector
        assertNotNull("sin Custom Tabs, el VIEW tiene que ir con el selector de navegadores: $i", selector)
        assertEquals(Intent.ACTION_MAIN, selector!!.action)
        assertTrue("el selector no es el de los navegadores: $selector", selector.hasCategory(Intent.CATEGORY_APP_BROWSER))
        assertNull("sin Custom Tabs el navegador lo elige el selector, no un paquete fijo", i.`package`)
    }
    assertNotEquals("el link volvía a MyPump", propio, i.`package`)
}

/**
 * Elige [dominio] para MyPump como lo haría el cliente ("Abrir links compatibles" en los ajustes de la app), que es lo que
 * pasa sin tocar nada en un build de Play con el dominio verificado, y devuelve cómo dejarlo como estaba. Desde Android 12 es
 * la selección por dominio (`pm set-app-links-user-selection`); antes, el estado de los links de toda la app
 * (`pm set-app-link … always`, de Android 6 a 11): el primero no existe en Android 9 y no elegía nada.
 */
fun elegirElDominioParaLaApp(contexto: Context, dominio: String): () -> Unit {
    val paquete = contexto.packageName
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val antes = Telefono.shell("pm get-app-links --user cur $paquete")
        val elegidoAntes = Regex("""Enabled:\s*\n\s*${Regex.escape(dominio)}""").containsMatchIn(antes)
        Telefono.shell("pm set-app-links-user-selection --user cur --package $paquete true $dominio")
        return { Telefono.shell("pm set-app-links-user-selection --user cur --package $paquete $elegidoAntes $dominio") }
    }
    // `get-app-link` dice "always ask" y `set-app-link` lo pide como "always-ask".
    val antes = Telefono.shell("pm get-app-link $paquete").trim().replace(' ', '-')
        .takeIf { it in setOf("undefined", "ask", "always", "never", "always-ask") } ?: "undefined"
    Telefono.shell("pm set-app-link $paquete always")
    return { Telefono.shell("pm set-app-link $paquete $antes") }
}
