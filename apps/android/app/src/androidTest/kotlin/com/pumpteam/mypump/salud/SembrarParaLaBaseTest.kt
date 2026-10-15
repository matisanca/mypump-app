package com.pumpteam.mypump.salud

import androidx.health.connect.client.HealthConnectClient
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.MainActivity
import java.time.LocalDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Para la prueba de punta a punta contra la base REAL (a mano, solo con la cuenta `test-nativa-android`; ver el README):
 * deja el Health Connect del EMULADOR con los 40 días sembrados y los permisos dados, sin borrar nada al terminar, para
 * que después la app abierta con esa cuenta conecte y suba. No corre en la suite: hace falta `-e sembrarSalud 1` (o
 * `-e sembrarSalud borrar` para sacar lo sembrado) y correrla con `am instrument`, que no desinstala la app.
 */
@RunWith(AndroidJUnit4::class)
class SembrarParaLaBaseTest {
    private val instr = InstrumentationRegistry.getInstrumentation()
    private val app = instr.targetContext
    private val pedido: String? get() = InstrumentationRegistry.getArguments().getString("sembrarSalud")

    @Test
    fun sembrar() = runBlocking {
        assumeTrue("solo a mano (-e sembrarSalud 1)", pedido == "1")
        assumeTrue(HealthConnectClient.getSdkStatus(app) == HealthConnectClient.SDK_AVAILABLE)
        val cliente = HealthConnectClient.getOrCreate(app)
        // La escritura por la hoja (así la app entra en la lista de prioridad y lo sembrado cuenta en los agregados).
        if (!cliente.permissionController.getGrantedPermissions().containsAll(SembradoSalud.escritura)) {
            val e = ActivityScenario.launch(MainActivity::class.java)
            Thread.sleep(1_500)
            val hoja = async(Dispatchers.Main) { PermisosHealthConnect.pedir(SembradoSalud.escritura.toSet()) }
            HojaHealthConnect.permitirTodo()
            assertTrue(withTimeout(10_000) { hoja.await() }.containsAll(SembradoSalud.escritura))
            e.close()
        }
        SembradoSalud.permisos(app.packageName, SembradoSalud.lectura + SembradoSalud.HISTORIAL, dar = true)
        SembradoSalud.sembrar(cliente, LocalDate.now(SembradoSalud.zona))
    }

    /** Borrar necesita la escritura (alcanza con `pm grant`: la lista de prioridad no cuenta para borrar). */
    @Test
    fun borrar() = runBlocking {
        assumeTrue("solo a mano (-e sembrarSalud borrar)", pedido == "borrar")
        SembradoSalud.permisos(app.packageName, SembradoSalud.escritura, dar = true)
        SembradoSalud.borrar(HealthConnectClient.getOrCreate(app), LocalDate.now(SembradoSalud.zona))
    }
}
