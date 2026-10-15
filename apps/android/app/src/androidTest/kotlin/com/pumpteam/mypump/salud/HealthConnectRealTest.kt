package com.pumpteam.mypump.salud

import androidx.health.connect.client.HealthConnectClient
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.FuenteSalud
import com.pumpteam.mypump.datos.HistorialSalud
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.PreferenciasEnMemoria
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.SincronizadorSalud
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.ui.PruebaUi
import com.pumpteam.mypump.ui.Telefono
import com.pumpteam.mypump.ui.etiqueta
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * La fuente de verdad contra el Health Connect de VERDAD del emulador (Android 16), con 40 días sembrados por
 * [SembradoSalud]: la hoja de permisos, los pedidos que arma `ClienteHealthConnectReal` (páginas, rangos, agregados por
 * día y por entreno) y la sincronización de :core, que lo sube como `health_connect` a una base de mentira (acá no se
 * toca la red).
 *
 * Los permisos se dan con `pm grant` y NUNCA se sacan en la corrida: sacar un permiso dado mata el proceso de la app, que
 * es el de las pruebas. Por eso van en orden: primero lo que necesita los permisos sin dar (la hoja, el historial
 * negado), después lo demás. Gradle desinstala la app al terminar, y con ella se van los permisos.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class HealthConnectRealTest : PruebaUi() {
    private val paquete get() = app.packageName
    private val hoy = LocalDate.now(SembradoSalud.zona)
    private lateinit var cliente: HealthConnectClient
    private val fuente by lazy { FuenteHealthConnect(app) }
    private var sembrado = false

    private fun ms(i: Instant) = i.toEpochMilli().toDouble()
    private fun dia(k: Int, h: Int, m: Int = 0) = SembradoSalud.dia(k, h, m, hoy)
    private fun fecha(k: Int) = hoy.minusDays(k.toLong()).toString()

    @Before
    fun health() {
        assumeTrue("el emulador no tiene Health Connect", HealthConnectClient.getSdkStatus(app) == HealthConnectClient.SDK_AVAILABLE)
        cliente = HealthConnectClient.getOrCreate(app)
    }

    @After
    fun limpiar() = runBlocking {
        if (sembrado) SembradoSalud.borrar(cliente, hoy)
    }

    /**
     * Siembra los 40 días. La escritura se da POR LA HOJA (una vez por corrida): con `pm grant` la app no entra en la lista
     * de prioridad de Health Connect y lo que escribe queda afuera de los agregados (pasos, calorías, distancia). La
     * lectura sí va con `pm grant`.
     */
    private suspend fun sembrar(lectura: List<String>) = coroutineScope {
        if (!dados().containsAll(SembradoSalud.escritura)) {
            abrir()
            p.nodo(etiqueta("campo-link"))
            val pedido = async(Dispatchers.Main) { PermisosHealthConnect.pedir(SembradoSalud.escritura.toSet()) }
            HojaHealthConnect.permitirTodo()
            assertTrue(withTimeout(10_000) { pedido.await() }.containsAll(SembradoSalud.escritura))
        }
        SembradoSalud.permisos(paquete, lectura, dar = true)
        SembradoSalud.sembrar(cliente, hoy)
        sembrado = true
    }

    private suspend fun dados(): Set<String> = cliente.permissionController.getGrantedPermissions()

    /** El paquete de la actividad de arriba (`topResumedActivity`). */
    private fun arriba(): String? = Telefono.shell("dumpsys activity activities").lineSequence()
        .firstOrNull { "topResumedActivity=" in it }?.let { Regex("""u\d+ ([A-Za-z0-9_.]+)/""").find(it)?.groupValues?.get(1) }

    /**
     * La hoja de verdad, con el contrato registrado en la MainActivity: se abre la de Health Connect (Android 14+ no la
     * muestra sin el uso de los permisos declarado), el cliente vuelve con Atrás y la espera termina con lo que quedó dado.
     */
    @Test
    fun a1_laHojaDeHealthConnectSeAbreYAtrasLaCierra() = runBlocking {
        val pasos = "android.permission.health.READ_STEPS"
        assumeTrue("ya estaba dado (la corrida no empezó con la app recién instalada)", pasos !in dados())
        val e = abrir()
        p.nodo(etiqueta("campo-link"))
        val pedido = async(Dispatchers.Main) { PermisosHealthConnect.pedir(setOf(pasos)) }
        val hoja = p.esperar("se abre la hoja de Health Connect", ms = 20_000, enElPrincipal = false) { arriba()?.takeIf { it != paquete } }
        // La pide el administrador de permisos del sistema y la muestra Health Connect (o su presentación, la primera vez).
        assertTrue("arriba quedó $hoja", "healthconnect" in hoja || "permissioncontroller" in hoja)
        Telefono.captura("salud-hoja-health-connect")
        Telefono.shell("input keyevent KEYCODE_BACK")
        val quedaron = withTimeout(15_000) { pedido.await() }
        assertFalse(pasos in quedaron)
        p.esperar("vuelve la app", enElPrincipal = false) { arriba() == paquete }
        assertEquals(Lifecycle.State.RESUMED, e.state)
    }

    /**
     * Sin el permiso de historial (Health Connect lo informa sin abrir la hoja): la corrida es de 30 días y no queda
     * hecha. Health Connect no da nada de más de 30 días… salvo lo que escribió la propia app (la siembra): eso no se
     * puede usar para ver el recorte, así que se mira el pedido (las ventanas), que es lo que decide la app.
     */
    @Test
    fun a2_sinElPermisoDeHistorialLaCorridaEsDeTreintaDias() = runBlocking {
        assumeTrue("ya estaba dado el historial", SembradoSalud.HISTORIAL !in dados())
        sembrar(SembradoSalud.lectura)
        assertEquals(HistorialSalud(autorizado = false, disponible = true), fuente.historial())
        val base = Base()
        val alcance = CoroutineScope(coroutineContext + SupervisorJob())
        val almacen = PreferenciasEnMemoria(mapOf(ClaveSalud.CONECTADO to "1"))
        val ventanas = ArrayList<Pair<Instant, Instant>>()
        val espia = object : FuenteSalud by fuente {
            override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double) =
                fuente.agregado(dataType, agregacion, desde, hasta).also { if (dataType == "steps") ventanas += Instant.ofEpochMilli(desde.toLong()) to Instant.ofEpochMilli(hasta.toLong()) }
        }
        try {
            val s = SincronizadorSalud(espia, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", almacen, alcance, zona = SembradoSalud.zona)
            val avances = ArrayList<String>()
            s.alCambiarProgreso = { p -> p?.let { avances += "${it.first}/${it.second}" } }
            s.historial()
            assertEquals("0", almacen.leer(ClaveSalud.HISTORIAL_OK))
            assertEquals("30/30", avances.last())
            assertEquals(6, ventanas.size)
            assertEquals(dia(30, 0), ventanas.first().first)
            assertNull(almacen.leer(ClaveSalud.HISTORIAL_HECHO))
            assertNull(almacen.leer(ClaveSalud.CURSOR))
        } finally {
            alcance.cancel()
        }
    }

    /** Lo que contesta la fuente para cada consulta del bridge, contra lo sembrado. */
    @Test
    fun b_laFuenteLeeLoSembrado() = runBlocking {
        sembrar(SembradoSalud.lectura + SembradoSalud.HISTORIAL)
        assertTrue(fuente.disponible())
        val tipos = PuenteSalud.tiposLectura(PlataformaSalud.ANDROID, 0)
        val permisos = fuente.permisos(tipos)
        assertEquals(tipos, permisos.preguntados)
        assertTrue(permisos.pendientes.isEmpty())
        assertEquals(HistorialSalud(autorizado = true, disponible = true), fuente.historial())
        // Con todo dado no se abre ninguna hoja: vuelve enseguida.
        assertEquals(HistorialSalud(autorizado = true, disponible = true), withTimeout(5_000) { fuente.pedirLecturaConHistorial(PuenteSalud.nucleo) })

        // Pasos: un balde de 24 h por día desde la medianoche de hace 7 días; hoy no tiene (no se sembró).
        val ahora = ms(Instant.now())
        assertEquals((7 downTo 1).map { ms(dia(it, 0)) to 6000.0 + it * 10 }, fuente.agregado("steps", "sum", ms(dia(7, 0)), ahora).map { it.inicio to it.valor })
        assertEquals((7 downTo 1).map { 300.0 + it }, fuente.agregado("calories", "sum", ms(dia(7, 0)), ahora).map { it.valor })
        assertEquals((7 downTo 1).map { 50.0 + it % 7 }, fuente.agregado("restingHeartRate", "average", ms(dia(7, 0)), ahora).map { it.valor })

        // La noche que termina hace 2 días: UNA sesión de 7 h 30 con sus etapas, del reloj.
        val noche = fuente.muestras("sleep", ms(dia(3, 12)), ms(dia(2, 12)), 5000).single()
        assertEquals(ms(dia(3, 23, 30)) to ms(dia(2, 7)), noche.inicio to noche.fin)
        assertEquals(450.0, noche.valor, 0.0)
        assertEquals(listOf("awake", "light", "deep", "rem", "light", "awake"), noche.etapas?.map { it.estado })
        assertEquals(paquete, noche.fuenteId)
        assertEquals("Google Pixel Watch 2", noche.fuenteNombre)

        // El pulso, una muestra por lectura; las basales, la tasa; el peso, en kg; la HRV, en ms.
        assertEquals(listOf(120.0, 130.0, 140.0, 150.0, 160.0, 170.0), fuente.muestras("heartRate", ms(dia(1, 0)), ms(dia(0, 0)), 5000).map { it.valor })
        assertEquals(listOf(1750.0, 1750.0), fuente.muestras("basalCalories", ms(dia(1, 0)), ms(dia(0, 0)), 5000).map { it.valor })
        assertEquals(81.9, fuente.muestras("weight", ms(dia(2, 0)), ms(dia(1, 0)), 5000).single().valor, 1e-9)
        assertEquals(48.0, fuente.muestras("heartRateVariability", ms(dia(8, 0)), ms(dia(7, 0)), 5000).single().valor, 1e-9)

        // Los entrenos de la semana (cada 3 días), del más nuevo al más viejo, con lo que se sumó en su hora.
        val ws = fuente.entrenos(ms(dia(7, 0)), ahora)
        assertEquals(listOf("strengthTraining", "strengthTraining"), ws.map { it.tipo })
        assertEquals(listOf(ms(dia(3, 18)), ms(dia(6, 18))), ws.map { it.inicio })
        assertEquals(listOf(3600.0, 3600.0), ws.map { it.duracion })
        assertEquals(listOf(303.0, 306.0), ws.map { it.kcal })
        assertEquals(listOf(5000.0, 5000.0), ws.map { it.distancia })

        // Lo que Android no tiene (o la app no pide) falla como en el plugin: un tipo que no está y uno sin permiso.
        assertEquals("Unsupported data type: exerciseTime", runCatching { fuente.muestras("exerciseTime", ms(dia(1, 0)), ahora, 10) }.exceptionOrNull()?.message)
        assertTrue(runCatching { fuente.muestras("oxygenSaturation", ms(dia(1, 0)), ahora, 10) }.isFailure)
    }

    /** La base de mentira: anota cada registro de `mypump_ingest_salud` y cada entreno, y dice que entraron. */
    private class Base : Transporte {
        val registros = ArrayList<ValorJson>()
        val entrenos = ArrayList<ValorJson>()
        override suspend fun enviar(pedido: Pedido): Respuesta {
            val cuerpo = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) }
            val salud = (cuerpo?.get("p_registros") as? ValorJson.Lista)?.elementos ?: emptyList()
            val ws = (cuerpo?.get("p_entrenos") as? ValorJson.Lista)?.elementos ?: emptyList()
            synchronized(this) {
                registros += salud
                entrenos += ws
            }
            return Respuesta(200, (salud.size + ws.size).toString().toByteArray())
        }
    }

    /** La semana sincronizada sale como la mandaría la app de hoy en este teléfono. */
    @Test
    fun c_laSemanaSaleComoHealthConnect() = runBlocking {
        sembrar(SembradoSalud.lectura + SembradoSalud.HISTORIAL)
        val base = Base()
        val alcance = CoroutineScope(coroutineContext + SupervisorJob())
        try {
            val s = SincronizadorSalud(fuente, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", PreferenciasEnMemoria(), alcance, zona = SembradoSalud.zona)
            assertTrue(s.sincronizar().ok)
        } finally {
            alcance.cancel()
        }
        fun valor(k: Int, tipo: String) = base.registros.singleOrNull { it["fecha"]?.comoTexto == fecha(k) && it["tipo"]?.comoTexto == tipo }?.get("valor")?.comoNumero
        assertTrue(base.registros.all { it["fuente"]?.comoTexto == "health_connect" })
        for (k in 1..7) {
            assertEquals("pasos $k", 6000.0 + k * 10, valor(k, "pasos"))
            assertEquals("activas $k", 300.0 + k, valor(k, "kcal_activas"))
            assertEquals("reposo $k", 50.0 + k % 7, valor(k, "fc_reposo"))
            assertEquals("sueño $k", 420.0, valor(k, "sueno_min"))   // 110 + 60 + 90 + 160: las etapas sin lo despierto
            assertEquals("eficiencia $k", 93.0, valor(k, "sueno_eficiencia_pct"))   // 420 de 450 en la cama
            assertEquals("hrv $k", 40.0 + k % 10, valor(k, "hrv_ms"))
            assertEquals("basales $k", 1750.0, valor(k, "kcal_basales"))   // la tasa, no la suma
            assertEquals("pulso $k", 145.0, valor(k, "fc_media"))
            assertEquals("distancia $k", 5.0, valor(k, "distancia_km"))
            assertEquals("pisos $k", 4.0, valor(k, "pisos"))
            assertEquals("respiración $k", 14.0, valor(k, "respiracion_rpm"))
            if (k % 2 == 0) assertEquals("peso $k", Math.round((82.0 - k * 0.05) * 10) / 10.0, valor(k, "peso_kg")) else assertNull(valor(k, "peso_kg"))
        }
        val hrv = base.registros.first { it["tipo"]?.comoTexto == "hrv_ms" }
        assertEquals("rmssd", hrv["detalle"]?.get("metrica")?.comoTexto)
        assertEquals("nocturna", hrv["detalle"]?.get("ventana")?.comoTexto)
        // Los entrenos con la FC calculada de las lecturas de su hora.
        assertEquals(2, base.entrenos.size)
        for (w in base.entrenos) {
            assertEquals("strengthTraining", w["tipo"]?.comoTexto)
            assertEquals(60.0, w["duracion_min"]?.comoNumero)
            assertEquals(145.0, w["fc_media"]?.comoNumero)
            assertEquals(170.0, w["fc_max"]?.comoNumero)
            assertEquals("health_connect", w["fuente"]?.comoTexto)
        }
    }

    /** Con el historial (dado desde Health Connect, sin la hoja) la corrida trae los 60 días y queda hecha. */
    @Test
    fun d_conElHistorialSonSesentaDiasYQuedaHecho() = runBlocking {
        sembrar(SembradoSalud.lectura + SembradoSalud.HISTORIAL)
        val base = Base()
        val alcance = CoroutineScope(coroutineContext + SupervisorJob())
        val almacen = PreferenciasEnMemoria(mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.HISTORIAL_OK to "0"))
        try {
            val s = SincronizadorSalud(fuente, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", almacen, alcance, zona = SembradoSalud.zona)
            val avances = ArrayList<String>()
            s.alCambiarProgreso = { p -> p?.let { avances += "${it.first}/${it.second}" } }
            s.historial()
            assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_OK))
            assertEquals("60/60", avances.last())
            assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
            assertEquals(6000.0 + 40 * 10, base.registros.single { it["fecha"]?.comoTexto == fecha(40) && it["tipo"]?.comoTexto == "pasos" }["valor"]?.comoNumero)
            assertTrue(base.registros.all { it["fuente"]?.comoTexto == "health_connect" })
        } finally {
            alcance.cancel()
        }
    }
}
