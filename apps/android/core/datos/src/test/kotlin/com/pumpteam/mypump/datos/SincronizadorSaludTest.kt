package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.reglas.RelojLocal
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Una salud de mentira: un peso por día (o nada) y la cuenta de las consultas. */
class FuenteSimple(override val plataforma: PlataformaSalud = PlataformaSalud.IOS) : FuenteSalud {
    override val iosMayor = if (plataforma == PlataformaSalud.IOS) 18 else 0
    var hay = true
    var conPeso = true

    /** La hoja de permisos tarda (para probar el corte del onboarding). */
    var demoraMs: Long? = null
    private var _agregados = 0
    val agregados: Int @Synchronized get() = _agregados
    private val _pedidos = ArrayList<List<String>>()
    val pedidos: List<List<String>> @Synchronized get() = _pedidos.toList()

    override suspend fun disponible(): Boolean = hay

    override suspend fun pedirLectura(tipos: List<String>) {
        demoraMs?.let { delay(it) }
        synchronized(this) { _pedidos += tipos }
    }

    override suspend fun permisos(tipos: List<String>): PermisosSalud = PermisosSalud(tipos, emptyList())

    override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> {
        synchronized(this) { _agregados++ }
        return emptyList()
    }

    override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> {
        if (!conPeso || dataType != "weight") return emptyList()
        return listOf(MuestraSalud(desde + 8 * 3_600_000, desde + 8 * 3_600_000, 80.0, "balanza", "Balanza"))
    }

    override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = emptyList()
}

/** Una base que acepta (o rechaza) todos los lotes de salud, y anota lo que le llegó. */
class BaseSimple : Transporte {
    @Volatile var rechaza = false
    private var _lotes = 0
    val lotes: Int @Synchronized get() = _lotes
    private val _cuerpos = ArrayList<ValorJson>()
    val cuerpos: List<ValorJson> @Synchronized get() = _cuerpos.toList()

    override suspend fun enviar(pedido: Pedido): Respuesta {
        synchronized(this) {
            _lotes++
            pedido.cuerpo?.let { _cuerpos += ValorJson.parsear(it.toString(Charsets.UTF_8)) }
        }
        if (rechaza) return Respuesta(403, """{"code":"42501","message":"permission denied"}""".toByteArray())
        return Respuesta(200, "1".toByteArray())
    }
}

/** Gemelo de SincronizadorSaludTests.swift: el reintento del historial y sin salud del sistema. */
class SincronizadorSaludTest {
    private val ahora = Instant.ofEpochSecond(1_792_000_000)
    private val ms = ahora.toEpochMilli().toDouble()
    private val ar = ZoneId.of("America/Argentina/Buenos_Aires")

    private fun sinc(fuente: FuenteSimple, base: BaseSimple, estado: Map<String, String>, alcance: CoroutineScope): Pair<SincronizadorSalud, PreferenciasEnMemoria> {
        val almacen = PreferenciasEnMemoria(estado)
        val s = SincronizadorSalud(fuente, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", almacen, alcance, { ahora }, ar)
        return s to almacen
    }

    @Test
    fun retomaSiPasaronSeisHoras() = enUnHilo { alcance ->
        val f = FuenteSimple()
        val b = BaseSimple()
        val (s, almacen) = sinc(f, b, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.INTENTO to (ms - 7 * 3_600_000).toLong().toString()), alcance)
        s.retomarHistorialSiFalta()
        val r = s.historialEnCurso?.await()
        assertTrue(r?.ok == true && r.ventanasFallidas == 0)
        assertEquals(36, f.agregados)   // 12 ventanas × 3 agregados
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
        assertNull(almacen.leer(ClaveSalud.CURSOR))
        assertNull(s.historialEnCurso)
    }

    @Test
    fun elAvanceArrancaEnCeroYTerminaVacio() = enUnHilo { alcance ->
        val (s, _) = sinc(FuenteSimple(), BaseSimple(), mapOf(ClaveSalud.CONECTADO to "1"), alcance)
        val avances = ArrayList<String>()
        s.alCambiarProgreso = { p -> avances += p?.let { "${it.first}/${it.second}" } ?: "nil" }
        s.historial()
        assertEquals("0/60", avances.first())
        assertEquals("nil", avances.last())
        assertEquals((1..12).map { "${it * 5}/60" }, avances.drop(1).dropLast(1))
    }

    @Test
    fun noLoRepiteAntesDeSeisHorasNiSinConectar() = enUnHilo { alcance ->
        val f = FuenteSimple()
        val b = BaseSimple()
        val (s, _) = sinc(f, b, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.INTENTO to (ms - 3_600_000).toLong().toString()), alcance)
        s.retomarHistorialSiFalta()
        assertNull(s.historialEnCurso)
        val (s2, _) = sinc(f, b, emptyMap(), alcance)
        s2.retomarHistorialSiFalta()
        assertNull(s2.historialEnCurso)
        val (s3, _) = sinc(f, b, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.HISTORIAL_HECHO to "1"), alcance)
        s3.retomarHistorialSiFalta()
        assertNull(s3.historialEnCurso)
        assertEquals(0, f.agregados)
    }

    @Test
    fun siTodoFallaSellaElReintentoYNoQuedaHecho() = enUnHilo { alcance ->
        val f = FuenteSimple()
        val b = BaseSimple()
        b.rechaza = true
        val (s, almacen) = sinc(f, b, mapOf(ClaveSalud.CONECTADO to "1"), alcance)
        s.retomarHistorialSiFalta()
        val r = s.historialEnCurso?.await()
        assertTrue(r?.ok == false && r.ventanasFallidas == 12)
        assertNull(almacen.leer(ClaveSalud.HISTORIAL_HECHO))
        assertEquals(ms.toLong().toString(), almacen.leer(ClaveSalud.INTENTO))   // la próxima vuelta espera 6 h
        assertNull(almacen.leer(ClaveSalud.DENEGADO))                             // se leyó algo: no es falta de permiso
    }

    @Test
    fun unHistorialEnCursoNoSeDuplica() = enUnHilo { alcance ->
        val f = FuenteSimple()
        val (s, _) = sinc(f, BaseSimple(), mapOf(ClaveSalud.CONECTADO to "1"), alcance)
        s.retomarHistorialSiFalta()
        val primero = s.historialEnCurso
        s.retomarHistorialSiFalta()
        assertSame(primero, s.historialEnCurso)
        primero?.await()
        assertEquals(36, f.agregados)
    }

    /**
     * Con el despachador inmediato del ViewModel (`Main.immediate`) el historial corre en el acto, y sin nada que mandar
     * termina sin soltar el hilo: el slot igual tiene que quedar limpio (si no, no se retoma nunca más).
     */
    @Test
    fun unHistorialQueTerminaEnElActoLiberaElSlot() {
        // Fuera de una corrutina y con un despachador inmediato: `start()` corre el cuerpo en el acto.
        val alcance = CoroutineScope(Dispatchers.Unconfined + SupervisorJob())
        val f = FuenteSimple()
        f.conPeso = false
        val (s, almacen) = sinc(f, BaseSimple(), mapOf(ClaveSalud.CONECTADO to "1"), alcance)
        s.retomarHistorialSiFalta()
        assertNull(s.historialEnCurso)
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
        alcance.cancel()
    }

    @Test
    fun sinSaludDisponibleNoPidePermisos() = enUnHilo { alcance ->
        val f = FuenteSimple()
        val b = BaseSimple()
        f.hay = false
        val (s, almacen) = sinc(f, b, emptyMap(), alcance)
        val r = s.conectar()
        assertTrue(!r.ok && r.motivo == "no_disponible")
        assertTrue(f.pedidos.isEmpty() && b.lotes == 0)
        assertNull(almacen.leer(ClaveSalud.CONECTADO))
        assertEquals("isAvailable", s.ultimoIntento?.get("paso")?.comoTexto)
        val e = s.estado()
        assertTrue(!e.disponible && e.total == 0 && e.preguntados == null)
    }

    @Test
    fun nuncaPideEscrituraYLaSegundaTandaEsElResto() = enUnHilo { alcance ->
        val f = FuenteSimple()
        val (s, _) = sinc(f, BaseSimple(), mapOf(ClaveSalud.HISTORIAL_HECHO to "1"), alcance)
        s.conectar()
        assertEquals(PuenteSalud.nucleo, f.pedidos.first())
        assertEquals(PuenteSalud.resto(PlataformaSalud.IOS, 18), f.pedidos[1])
        assertEquals(PuenteSalud.tiposLectura(PlataformaSalud.IOS, 18).toSet(), f.pedidos.flatten().toSet())
        assertFalse(PuenteSalud.tiposLectura(PlataformaSalud.IOS, 15).contains("appleSleepingWristTemperature"))
    }

    /** En Android: las tablas de Health Connect (sin los soloIOS), la fuente `health_connect` y la HRV como rMSSD. */
    @Test
    fun enAndroidPideYMarcaLoDeHealthConnect() = enUnHilo { alcance ->
        val f = FuenteSimple(PlataformaSalud.ANDROID)
        val b = BaseSimple()
        val (s, _) = sinc(f, b, mapOf(ClaveSalud.HISTORIAL_HECHO to "1"), alcance)
        assertTrue(s.conectar().ok)
        assertEquals(PuenteSalud.resto(PlataformaSalud.ANDROID, 0), f.pedidos[1])
        assertFalse(f.pedidos.flatten().any { it in listOf("oxygenSaturation", "exerciseTime", "bloodGlucose", "bodyTemperature", "mindfulness") })
        val registros = b.cuerpos.mapNotNull { it["p_registros"] as? ValorJson.Lista }.flatMap { it.elementos }
        assertTrue(registros.isNotEmpty())
        assertTrue(registros.all { it["fuente"]?.comoTexto == "health_connect" }, "$registros")
    }

    @Test
    fun elOnboardingNoEsperaMasDelLimiteYLaConexionSigue() = enUnHilo { alcance ->
        val f = FuenteSimple()
        f.demoraMs = 300
        val m = ModeloSalud(ClienteRpc(transporte = BaseSimple()), "tok-de-prueba-nativa-0001", f,
            PreferenciasEnMemoria(mapOf(ClaveSalud.HISTORIAL_HECHO to "1")), alcance)
        val r = m.conectar(limiteMs = 20)
        assertNull(r)                          // cortó: la pantalla avanza
        assertFalse(m.conectado.value)
        repeat(100) { if (!m.conectado.value) delay(20) }
        assertTrue(m.conectado.value)          // y la conexión terminó de fondo
        assertEquals(true, m.conectar(limiteMs = 5_000)?.ok)
    }

    @Test
    fun desconectarEsSoloLocal() = enUnHilo { alcance ->
        val b = BaseSimple()
        val (s, almacen) = sinc(FuenteSimple(), b, mapOf(
            ClaveSalud.CONECTADO to "1", ClaveSalud.ULTIMA_SYNC to "x", ClaveSalud.HISTORIAL_HECHO to "1", ClaveSalud.RACHA_VACIA to "2",
        ), alcance)
        s.desconectar()
        assertTrue(almacen.leer(ClaveSalud.CONECTADO) == null && almacen.leer(ClaveSalud.ULTIMA_SYNC) == null &&
            almacen.leer(ClaveSalud.HISTORIAL_HECHO) == null)
        assertEquals("2", almacen.leer(ClaveSalud.RACHA_VACIA))
        assertEquals(0, b.lotes)
    }

    /**
     * `leerMuestras`: con el límite justo se parte la ventana al medio, y la muestra que cruza el corte (sale en las dos
     * mitades: HealthKit devuelve todo lo que se solapa) cuenta una sola vez. Los vectores no lo cubren: en el de la
     * bisección ninguna muestra cruza el corte.
     */
    @Test
    fun laVentanaPartidaNoCuentaDosVecesLaQueCruzaElCorte() = enUnHilo { _ ->
        val desde = 1_791_000_000_000.0
        val hasta = desde + 2 * 24 * 3_600_000
        val medio = Math.floor((desde + hasta) / 2)
        val todas = listOf(
            MuestraSalud(desde + 1_000, desde + 2_000, 100.0, "reloj", "Reloj"),
            MuestraSalud(medio - 60_000, medio + 60_000, 250.0, "reloj", "Reloj"),   // cruza el corte
            MuestraSalud(hasta - 2_000, hasta - 1_000, 50.0, "reloj", "Reloj"),
        )
        val consultas = ArrayList<Pair<Double, Double>>()
        val fuente = object : FuenteSalud by FuenteSimple() {
            override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> {
                consultas += desde to hasta
                // La ventana entera vuelve llena (el límite justo): quedaron más afuera.
                if (consultas.size == 1) return List(limite) { todas[0] }
                return todas.filter { it.fin >= desde && it.inicio < hasta }
            }
        }
        val ms = RecolectorSalud(fuente, RelojLocal(ZoneId.of("UTC"))).leer("distance", desde, hasta)
        assertEquals(listOf(desde to medio, medio to hasta), consultas.drop(1))
        assertEquals(listOf(100.0, 250.0, 50.0), ms.map { it.valor })
    }

    /** NumerosAbsurdosTests.swift: lo que contesta la ingesta, con `Number(r.data) || 0`. */
    @Test
    fun respuestasDeLaIngestaConNumerosRaros() {
        assertEquals(Int.MAX_VALUE, SincronizadorSalud.numeroJs(ValorJson.Numero(1e300)))   // iOS: 10^15 (su Int es de 64 bits)
        assertEquals(0, SincronizadorSalud.numeroJs(ValorJson.Texto("nan")))
        assertEquals(12, SincronizadorSalud.numeroJs(ValorJson.Texto(" 12 ")))
        assertEquals(7, SincronizadorSalud.numeroJs(ValorJson.Numero(7.0)))
        assertEquals(5, SincronizadorSalud.numeroJs(ValorJson.Lista(listOf(ValorJson.Numero(5.0)))))   // Number([5])
    }

    /** La racha de sincronizaciones vacías y el cursor viejo, con el `parseInt` de JS. */
    @Test
    fun rachaYCursorComoJs() = enUnHilo { alcance ->
        val f = FuenteSimple()
        f.conPeso = false
        val (s, almacen) = sinc(f, BaseSimple(), mapOf(ClaveSalud.RACHA_VACIA to " 2abc"), alcance)
        s.sincronizar()
        assertEquals("3", almacen.leer(ClaveSalud.RACHA_VACIA))
        assertEquals("1", almacen.leer(ClaveSalud.DENEGADO))
        // Llegó algo: se borra la sospecha y la racha vuelve a 0.
        f.conPeso = true
        s.sincronizar()
        assertEquals("0", almacen.leer(ClaveSalud.RACHA_VACIA))
        assertNull(almacen.leer(ClaveSalud.DENEGADO))
        for ((raw, esperado) in listOf("20" to SincronizadorSalud.Cursor(20, 60), "61" to null, "0" to null, "x" to null, "  15días" to SincronizadorSalud.Cursor(15, 60),
            """{"off":20,"alcance":30}""" to SincronizadorSalud.Cursor(20, 30), """{"off":0}""" to null, "{roto" to null, """{"off":25}""" to SincronizadorSalud.Cursor(25, null))) {
            almacen.guardar(ClaveSalud.CURSOR, raw)
            assertEquals(esperado, s.cursorGuardado(), raw)
        }
        assertEquals("2026-10-14T17:46:40.000Z", RelojLocal.iso(ms))
    }
}
