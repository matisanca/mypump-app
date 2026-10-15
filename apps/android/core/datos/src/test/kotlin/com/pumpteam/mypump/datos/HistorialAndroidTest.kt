package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Health Connect con un dueño, como la fuente de Android: el núcleo pide también el historial y devuelve el veredicto,
 * y `historial()` lo re-pregunta sin abrir la hoja (o falla, si no se puede preguntar).
 */
class FuenteConHistorial(
    val base: FuenteSimple = FuenteSimple(PlataformaSalud.ANDROID),
    var alPedir: HistorialSalud? = HistorialSalud(autorizado = true, disponible = true),
    var alRepreguntar: HistorialSalud? = null,
) : FuenteSalud by base {
    var repreguntaFalla = false

    /** Las tandas que pidieron el historial (las demás van por `base.pedidos`). */
    val conHistorial = ArrayList<List<String>>()
    var repreguntas = 0

    override suspend fun pedirLecturaConHistorial(tipos: List<String>): HistorialSalud? {
        base.pedirLectura(tipos)
        conHistorial += tipos
        return alPedir
    }

    override suspend fun historial(): HistorialSalud? {
        repreguntas++
        if (repreguntaFalla) throw ErrorFuenteSalud("Health Connect needs an update.")
        return alRepreguntar
    }
}

/**
 * El permiso de historial de Health Connect (healthkit-bridge.js:267-330 y 999-1065): sin él Health Connect no da nada
 * anterior a 30 días y no avisa (devuelve vacío). Se piden 30, se dice 30, y no se da por hecho: el próximo arranque con
 * el permiso completa el resto. El veredicto se guarda (`mypump_health_historial_ok`) y se re-pregunta al empezar cada
 * historial. En iOS nada de esto existe.
 */
class HistorialAndroidTest {
    private val ahora = Instant.ofEpochSecond(1_792_000_000)
    private val ar = ZoneId.of("America/Argentina/Buenos_Aires")

    private fun sinc(fuente: FuenteSalud, estado: Map<String, String>, alcance: CoroutineScope, base: BaseSimple = BaseSimple()) =
        PreferenciasEnMemoria(estado).let { almacen ->
            SincronizadorSalud(fuente, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", almacen, alcance, { ahora }, ar) to almacen
        }

    @Test
    fun sinElPermisoTraeTreintaDiasYNoLoDaPorHecho() = enUnHilo { alcance ->
        val f = FuenteConHistorial(alPedir = HistorialSalud(autorizado = false, disponible = true))
        val (s, almacen) = sinc(f, emptyMap(), alcance)
        val avances = ArrayList<String>()
        s.alCambiarProgreso = { p -> avances += p?.let { "${it.first}/${it.second}" } ?: "nil" }
        val r = s.conectar(esperarHistorial = true)
        assertTrue(r.ok)
        assertEquals("0", almacen.leer(ClaveSalud.HISTORIAL_OK))
        assertEquals(HistorialSalud(autorizado = false, disponible = true), s.historialAndroid)
        assertTrue(s.sinHistorialAndroid)
        // 7 días (1 ventana) + 6 ventanas de 5: 3 agregados por ventana.
        assertEquals(3 + 6 * 3, f.base.agregados)
        assertEquals(listOf("0/30") + (1..6).map { "${it * 5}/30" } + "nil", avances)
        // No queda hecho ni con cursor: la corrida de 60 empieza de cero cuando lo habilite.
        assertNull(almacen.leer(ClaveSalud.HISTORIAL_HECHO))
        assertNull(almacen.leer(ClaveSalud.CURSOR))
    }

    @Test
    fun conElPermisoTraeLosSesentaYQuedaHecho() = enUnHilo { alcance ->
        val f = FuenteConHistorial(alPedir = HistorialSalud(autorizado = true, disponible = true))
        val (s, almacen) = sinc(f, emptyMap(), alcance)
        assertTrue(s.conectar(esperarHistorial = true).ok)
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_OK))
        assertFalse(s.sinHistorialAndroid)
        assertEquals(3 + 12 * 3, f.base.agregados)
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
    }

    /** Solo la tanda del núcleo lleva el historial (`opts` va en el primer requestAuthorization). */
    @Test
    fun soloElNucleoPideElHistorial() = enUnHilo { alcance ->
        val f = FuenteConHistorial()
        val (s, _) = sinc(f, mapOf(ClaveSalud.HISTORIAL_HECHO to "1"), alcance)
        s.conectar()
        assertEquals(listOf(PuenteSalud.nucleo), f.conHistorial)
        assertEquals(listOf(PuenteSalud.nucleo, PuenteSalud.resto(PlataformaSalud.ANDROID, 0)), f.base.pedidos)
    }

    /** Lo negó y después lo habilitó desde Health Connect (sin volver a "Conectar"): el historial lo ve al empezar. */
    @Test
    fun elVeredictoGuardadoSeRepreguntaSinAbrirLaHoja() = enUnHilo { alcance ->
        val f = FuenteConHistorial(alRepreguntar = HistorialSalud(autorizado = true, disponible = true))
        val (s, almacen) = sinc(f, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.HISTORIAL_OK to "0"), alcance)
        assertTrue(s.sinHistorialAndroid)
        s.historial()
        assertEquals(1, f.repreguntas)
        assertTrue(f.base.pedidos.isEmpty())   // ninguna hoja
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_OK))
        assertEquals(12 * 3, f.base.agregados)
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
    }

    /** Si no se puede re-preguntar (Health Connect caído o viejo), vale lo guardado. */
    @Test
    fun siNoSePuedeRepreguntarValeLoGuardado() = enUnHilo { alcance ->
        val f = FuenteConHistorial()
        f.repreguntaFalla = true
        val (s, almacen) = sinc(f, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.HISTORIAL_OK to "0"), alcance)
        s.historial()
        assertEquals("0", almacen.leer(ClaveSalud.HISTORIAL_OK))
        assertEquals(6 * 3, f.base.agregados)
        assertNull(almacen.leer(ClaveSalud.HISTORIAL_HECHO))
    }

    /** Sin veredicto (un Android que no pasó por la hoja, o una fuente que no lo informa) se asume que hay historial. */
    @Test
    fun sinVeredictoAsumeQueHayHistorial() = enUnHilo { alcance ->
        val f = FuenteConHistorial(alRepreguntar = null)
        val (s, almacen) = sinc(f, mapOf(ClaveSalud.CONECTADO to "1"), alcance)
        assertFalse(s.sinHistorialAndroid)
        s.historial()
        assertEquals(12 * 3, f.base.agregados)
        assertNull(almacen.leer(ClaveSalud.HISTORIAL_OK))
    }

    /**
     * El cursor guarda el alcance con el que se escribió: uno de una corrida de 30 cortada no le sirve a la de 60 (si no,
     * las ventanas 60 → 30 no se pedirían nunca). Al revés sí: la de 30 retoma el de 60.
     */
    @Test
    fun elCursorDeUnaCorridaDeTreintaNoTapaLasVentanasViejas() = enUnHilo { alcance ->
        val f = FuenteConHistorial(alRepreguntar = HistorialSalud(autorizado = true, disponible = true))
        val (s, _) = sinc(f, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.CURSOR to """{"off":20,"alcance":30}"""), alcance)
        s.historial()
        assertEquals(12 * 3, f.base.agregados)

        val g = FuenteConHistorial(alRepreguntar = HistorialSalud(autorizado = false, disponible = false))
        val (s2, almacen2) = sinc(g, mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.CURSOR to """{"off":20,"alcance":60}"""), alcance)
        val avances = ArrayList<String>()
        s2.alCambiarProgreso = { p -> avances += p?.let { "${it.first}/${it.second}" } ?: "nil" }
        s2.historial()
        assertEquals(4 * 3, g.base.agregados)   // de 20 a 0
        assertEquals("10/30", avances.first())
        assertEquals("0", almacen2.leer(ClaveSalud.HISTORIAL_OK))
    }

    /** En iOS no hay historial que pedir: ni la tanda lo lleva ni se guarda nada. */
    @Test
    fun enIosNoExiste() = enUnHilo { alcance ->
        val f = FuenteConHistorial(base = FuenteSimple(PlataformaSalud.IOS))
        val (s, almacen) = sinc(f, emptyMap(), alcance)
        assertTrue(s.conectar(esperarHistorial = true).ok)
        assertTrue(f.conHistorial.isEmpty())
        assertEquals(0, f.repreguntas)
        assertNull(almacen.leer(ClaveSalud.HISTORIAL_OK))
        assertFalse(s.sinHistorialAndroid)
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
    }
}
