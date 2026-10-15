package com.pumpteam.mypump.ui

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.acceso.URL_PRIVACIDAD
import com.pumpteam.mypump.diseno.navegadorConPestanas
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La política de privacidad se abre en el NAVEGADOR aunque el dominio sea de la app. El App Link de la MainActivity toma
 * todo `app.mypumpteam.com` (con `autoVerify`): en un build de Play, con el dominio verificado, un VIEW implícito a
 * `privacidad.html` volvía a MyPump (que no hacía nada con él) en vez de abrirse. En debug no se ve porque el dominio no
 * está verificado; acá se fuerza (el cliente lo elige para la app) y se deja como estaba al terminar.
 */
@RunWith(AndroidJUnit4::class)
class NavegadorFueraDeLaAppTest : PruebaUi() {
    private val dominio = "app.mypumpteam.com"

    @Test
    fun laPoliticaDePrivacidadSeAbreEnElNavegadorAunqueElDominioSeaDeLaApp() {
        val paquete = app.packageName
        val antes = Telefono.shell("pm get-app-links --user cur $paquete")
        val elegidoAntes = Regex("""Enabled:\s*\n\s*${Regex.escape(dominio)}""").containsMatchIn(antes)
        Telefono.shell("pm set-app-links-user-selection --user cur --package $paquete true $dominio")
        try {
            // Así quedó armado el problema: un VIEW implícito a la política la abre MyPump, no un navegador.
            val implicito = Intent(Intent.ACTION_VIEW, Uri.parse(URL_PRIVACIDAD)).addCategory(Intent.CATEGORY_BROWSABLE)
            assertEquals(
                "con el dominio elegido para la app, el link tendría que resolver a MyPump",
                paquete, app.packageManager.resolveActivity(implicito, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName,
            )
            val navegador = navegadorConPestanas(app)
            assertNotNull("el emulador no tiene un navegador con Custom Tabs", navegador)

            guardarCuenta()
            abrir()
            p.tocar(etiqueta("pestana-revision"))
            p.tocar(etiqueta("mis-datos"))
            p.nodo(etiqueta("mis-datos-pantalla"))
            p.tocar(texto("Política de privacidad"))

            // Arriba queda el navegador. Si el link hubiera vuelto a MyPump, arriba seguiría la MainActivity.
            val arriba = p.esperar("el navegador queda arriba", ms = 20_000, enElPrincipal = false) {
                actividadArriba()?.takeIf { it != paquete }
            }
            assertEquals(navegador, arriba)
            assertNotEquals(paquete, arriba)
        } finally {
            // Se cierra el navegador y el dominio vuelve a como estaba.
            repeat(2) {
                if (actividadArriba() != paquete) Telefono.shell("input keyevent KEYCODE_BACK")
                Thread.sleep(600)
            }
            Telefono.shell("pm set-app-links-user-selection --user cur --package $paquete $elegidoAntes $dominio")
        }
    }

    /** El paquete de la actividad que está arriba (`topResumedActivity` de `dumpsys`). */
    private fun actividadArriba(): String? {
        val d = Telefono.shell("dumpsys activity activities")
        val linea = d.lineSequence().firstOrNull { "topResumedActivity=" in it } ?: d.lineSequence().firstOrNull { "ResumedActivity:" in it }
        return linea?.let { Regex("""u\d+ ([A-Za-z0-9_.]+)/""").find(it)?.groupValues?.get(1) }
    }
}
