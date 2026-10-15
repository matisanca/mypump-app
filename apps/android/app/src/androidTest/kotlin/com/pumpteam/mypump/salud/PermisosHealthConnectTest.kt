package com.pumpteam.mypump.salud

import android.app.Instrumentation
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.acceso.URL_PRIVACIDAD
import com.pumpteam.mypump.ui.PruebaUi
import com.pumpteam.mypump.ui.etiqueta
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Lo que Health Connect necesita de la app para mostrar la hoja de permisos (la justificación y el uso de los permisos,
 * que abren la política de privacidad en una Custom Tab) y el puente de la hoja sin una pantalla a la vista. La hoja de
 * verdad, con Health Connect del emulador, está en [HealthConnectRealTest] (los permisos de una corrida van en orden).
 */
@RunWith(AndroidJUnit4::class)
class PermisosHealthConnectTest : PruebaUi() {
    private val paquete get() = app.packageName

    /** Sin una pantalla a la vista no se abre nada (desde segundo plano no se mostraría y la espera quedaría colgada). */
    @Test
    fun sinPantallaALaVistaNoAbreNada() {
        val e = abrir()
        p.nodo(etiqueta("campo-link"))
        e.moveToState(Lifecycle.State.CREATED)
        val r = runCatching { runBlocking { PermisosHealthConnect.pedir(setOf("android.permission.health.READ_STEPS")) } }
        assertTrue("${r.exceptionOrNull()}", r.exceptionOrNull() is IllegalStateException)
        // Cerrar un escenario parado espera su tope (45 s): se lo vuelve a la vista antes.
        e.moveToState(Lifecycle.State.RESUMED)
    }

    /**
     * La justificación (`ACTION_SHOW_PERMISSIONS_RATIONALE`) y el uso de los permisos (el `activity-alias` que solo puede
     * abrir el sistema) existen, y la justificación (abierta como la abre Health Connect: el componente que encontró)
     * muestra la política de privacidad en una Custom Tab con el navegador fijo.
     */
    @Test
    fun laJustificacionAbreLaPoliticaDePrivacidad() {
        val pm = app.packageManager
        val razones = pm.queryIntentActivities(Intent("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE").setPackage(paquete), 0)
        val actividad = razones.single().activityInfo
        assertEquals("com.pumpteam.mypump.salud.PoliticaSaludActivity", actividad.name)
        assertTrue(actividad.exported)
        val uso = pm.queryIntentActivities(
            Intent("android.intent.action.VIEW_PERMISSION_USAGE").addCategory("android.intent.category.HEALTH_PERMISSIONS").setPackage(paquete),
            PackageManager.MATCH_DISABLED_COMPONENTS,
        ).single().activityInfo
        assertEquals("com.pumpteam.mypump.ViewPermissionUsageActivity", uso.name)
        assertEquals("com.pumpteam.mypump.salud.PoliticaSaludActivity", uso.targetActivity)
        assertEquals("android.permission.START_VIEW_PERMISSION_USAGE", uso.permission)

        var capturado: Intent? = null
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action == Intent.ACTION_VIEW) {
                    capturado = intent
                    return Instrumentation.ActivityResult(0, null)
                }
                return null
            }
        }
        instr.addMonitor(monitor)
        try {
            app.startActivity(
                Intent("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")
                    .setComponent(ComponentName(paquete, actividad.name))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            p.esperar("se abre la política", enElPrincipal = false) { capturado }
        } finally {
            instr.removeMonitor(monitor)
        }
        val i = capturado
        assertNotNull(i)
        assertEquals(URL_PRIVACIDAD, i!!.dataString)
        assertTrue("no es una Custom Tab", i.hasExtra("android.support.customtabs.extra.SESSION"))
        assertNotNull(i.`package`)
        assertNotEquals(paquete, i.`package`)
    }
}
