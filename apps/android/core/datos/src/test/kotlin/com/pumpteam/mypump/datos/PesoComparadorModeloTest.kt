package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import kotlinx.coroutines.async
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * El peso del comparador de fotos (2.3.3, el `_pcAsegurar` de la web; gemelo de PesoComparadorModeloTests.swift): una serie
 * aparte, solo `peso_kg`, desde el lunes de la semana de la primera foto menos 7 días hasta hoy. La de 60 días de Salud no
 * cambia.
 */
class PesoComparadorModeloTest {
    /** Anota cada pedido (la URL con su filtro y el cuerpo) y contesta según la función y el filtro. */
    private class Servidor : Transporte {
        data class Anotado(val funcion: String, val consulta: String?, val cuerpo: ValorJson)

        private val anotados = mutableListOf<Anotado>()
        val pedidos: List<Anotado> get() = synchronized(anotados) { anotados.toList() }
        val aparte: List<Anotado> get() = pedidos.filter { it.funcion == "mypump_get_salud" && it.consulta != null }

        @Volatile var salud60 = "[]"
        @Volatile var pesoAparte = "[]"
        @Volatile var falla = false

        override suspend fun enviar(pedido: Pedido): Respuesta {
            val uri = java.net.URI(pedido.url)
            val fn = pedido.ruta.substringAfterLast('/')
            val cuerpo = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) } ?: ValorJson.Nulo
            synchronized(anotados) { anotados += Anotado(fn, uri.rawQuery, cuerpo) }
            var status = 200
            var texto = "[]"
            if (fn == "mypump_get_salud") {
                when {
                    uri.rawQuery == null -> texto = salud60
                    falla -> { status = 503; texto = """{"message":"caído"}""" }
                    else -> texto = pesoAparte
                }
            }
            return Respuesta(status, texto.toByteArray())
        }
    }

    private class Reloj(@Volatile var ms: Long = 1_800_000_000_000L, @Volatile var hoy: String = "2026-11-19")

    private fun modelo(s: Servidor, reloj: Reloj, alcance: kotlinx.coroutines.CoroutineScope): ModeloRevision {
        val m = ModeloRevision(ClienteRpc(transporte = s), "tok", null, alcance)
        m.diaDeHoy = { reloj.hoy }
        m.ahoraMs = { reloj.ms }
        return m
    }

    private fun peso(fecha: String, kg: Double, fuente: String = "manual") =
        """{"fecha":"$fecha","tipo":"peso_kg","valor":$kg,"fuente":"$fuente"}"""

    /** Emmanuel: primera foto del 02/09 (semana del 31/08). El pedido va desde el 24/08, filtrado a peso_kg, y el pie da −4,6. */
    @Test
    fun pideDesdeElLunesDeLaPrimeraFotoMenosSieteDias() = enUnHilo { alcance ->
        val s = Servidor()
        s.salud60 = "[${peso("2026-11-16", 68.4)},${peso("2026-11-18", 68.9)}]"
        s.pesoAparte = "[${peso("2026-11-18", 68.9)},${peso("2026-11-16", 68.4)},${peso("2026-09-20", 72.1)},${peso("2026-09-02", 73.0)}]"
        val m = modelo(s, Reloj(), alcance)
        m.cargarRevision()
        // La de 60 días, como siempre: sin filtro, desde hoy − 59.
        val de60 = s.pedidos.first { it.funcion == "mypump_get_salud" && it.consulta == null }
        assertEquals("2026-09-21", de60.cuerpo["p_desde"]?.comoTexto)
        assertEquals(listOf("2026-11-16", "2026-11-18"), m.serieDelComparador.map { it.fecha })

        assertTrue(m.asegurarPesoComparador(listOf("2026-11-16", "2026-08-31", "2026-09-02")))
        assertEquals(1, s.aparte.size)
        val p = s.aparte.first()
        assertEquals("tipo=eq.peso_kg", p.consulta)
        assertEquals("tok", p.cuerpo["p_token"]?.comoTexto)
        assertEquals("2026-08-24", p.cuerpo["p_desde"]?.comoTexto)
        assertEquals("2026-11-19", p.cuerpo["p_hasta"]?.comoTexto)
        assertEquals(listOf("2026-09-02", "2026-09-20", "2026-11-16", "2026-11-18"), m.serieDelComparador.map { it.fecha })
        assertEquals("11 semanas · -4,6 kg", FotosProgreso.resumenComparador("2026-08-31", "2026-11-16", m.serieDelComparador))
        // La de 60 días (Salud y la fila Peso) no recibe los pesos viejos.
        assertEquals(listOf("2026-11-16", "2026-11-18"), m.serieDePeso.map { it.fecha })
    }

    /** Si los 60 días de Salud ya llegan a la primera foto (o no hay fotos), no sale ningún pedido nuevo. */
    @Test
    fun sinPedidoSiLosSesentaDiasAlcanzan() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, Reloj(), alcance)
        assertFalse(m.asegurarPesoComparador(emptyList()))
        // Semana del 28/09: desde el 21/09, el primer día de los 60.
        assertFalse(m.asegurarPesoComparador(listOf("2026-09-28", "2026-11-16")))
        assertTrue(s.aparte.isEmpty())
        // Semana del 21/09: desde el 14/09, que ya no entra.
        assertTrue(m.asegurarPesoComparador(listOf("2026-09-21")))
        assertEquals("2026-09-14", s.aparte.first().cuerpo["p_desde"]?.comoTexto)
    }

    /** La demo (sin token) no pide nada. */
    @Test
    fun laDemoNoPide() = enUnHilo { alcance ->
        val s = Servidor()
        val m = ModeloRevision(ClienteRpc(transporte = s), null, null, alcance)
        assertFalse(m.asegurarPesoComparador(listOf("2026-07-22")))
        assertTrue(s.pedidos.isEmpty())
    }

    /** Una vez por día: no se repite con las mismas fotos; sí con una foto más vieja o con un día nuevo. */
    @Test
    fun unaVezHastaQueApareceUnaFotoMasViejaOCambiaElDia() = enUnHilo { alcance ->
        val s = Servidor()
        val reloj = Reloj()
        val m = modelo(s, reloj, alcance)
        m.asegurarPesoComparador(listOf("2026-09-02"))
        m.asegurarPesoComparador(listOf("2026-09-02", "2026-11-16"))
        assertEquals(1, s.aparte.size)
        m.asegurarPesoComparador(listOf("2026-07-22"))
        assertEquals(2, s.aparte.size)
        assertEquals("2026-07-13", s.aparte.last().cuerpo["p_desde"]?.comoTexto)
        // Una foto más nueva que la más vieja no pide de nuevo (el rango ya la cubre).
        m.asegurarPesoComparador(listOf("2026-08-10"))
        assertEquals(2, s.aparte.size)
        reloj.hoy = "2026-11-20"
        m.asegurarPesoComparador(listOf("2026-07-22"))
        assertEquals(3, s.aparte.size)
        assertEquals("2026-11-20", s.aparte.last().cuerpo["p_hasta"]?.comoTexto)
    }

    /** Dos pedidos a la vez (la tarjeta y la galería) salen como uno. */
    @Test
    fun dosALaVezSonUnPedido() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, Reloj(), alcance)
        val a = async { m.asegurarPesoComparador(listOf("2026-09-02")) }
        val b = async { m.asegurarPesoComparador(listOf("2026-09-02")) }
        a.await(); b.await()
        assertEquals(1, s.aparte.size)
    }

    /** Si falla, el comparador sigue con los 60 días y se reintenta pasados 5 minutos (no en cada recomposición). */
    @Test
    fun siFallaReintentaALosCincoMinutos() = enUnHilo { alcance ->
        val s = Servidor()
        s.falla = true
        s.salud60 = "[${peso("2026-11-16", 68.4)}]"
        val reloj = Reloj()
        val m = modelo(s, reloj, alcance)
        m.cargarRevision()
        assertFalse(m.asegurarPesoComparador(listOf("2026-09-02")))
        assertEquals(listOf("2026-11-16"), m.serieDelComparador.map { it.fecha })
        assertEquals("11 semanas", FotosProgreso.resumenComparador("2026-08-31", "2026-11-16", m.serieDelComparador))
        reloj.ms += 4 * 60_000
        m.asegurarPesoComparador(listOf("2026-09-02"))
        assertEquals(1, s.aparte.size)
        s.falla = false
        s.pesoAparte = "[${peso("2026-09-02", 73.0)}]"
        reloj.ms += 61_000
        assertTrue(m.asegurarPesoComparador(listOf("2026-09-02")))
        assertEquals(2, s.aparte.size)
        assertEquals("11 semanas · -4,6 kg", FotosProgreso.resumenComparador("2026-08-31", "2026-11-16", m.serieDelComparador))
    }

    /** En las fechas que trae Salud manda Salud: el peso de hoy corregido se ve enseguida, aunque la serie aparte tenga el viejo. */
    @Test
    fun laCorreccionDeHoyGanaSobreLaSerieAparte() = enUnHilo { alcance ->
        val s = Servidor()
        s.salud60 = "[${peso("2026-11-19", 80.0)}]"
        s.pesoAparte = "[${peso("2026-09-02", 73.0)},${peso("2026-11-19", 80.0)},${peso("2026-11-19", 79.0, "health_connect")}]"
        val m = modelo(s, Reloj(), alcance)
        m.cargarRevision()
        m.asegurarPesoComparador(listOf("2026-09-02"))
        assertEquals(PesoCorporal.Punto("2026-11-19", 80.0), m.serieDelComparador.last())
        assertTrue(m.guardarPeso("70"))
        assertEquals(listOf(73.0, 70.0), m.serieDelComparador.map { it.kg })
        assertEquals(listOf(70.0), m.serieDePeso.map { it.kg })
        // Lo que junta la pantalla da lo mismo que el modelo.
        assertNotNull(m.pesoComparador.value)
        assertEquals(m.serieDelComparador, m.serieDelComparador(m.salud.value, m.pesoComparador.value))
    }
}
