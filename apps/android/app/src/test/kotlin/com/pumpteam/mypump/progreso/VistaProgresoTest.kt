package com.pumpteam.mypump.progreso

import com.pumpteam.mypump.datos.ClienteRpc
import com.pumpteam.mypump.datos.ModeloProgreso
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.TarjetaProgreso
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

/**
 * Lo que la pantalla de Progreso arma con las tarjetas (ProgresoView.swift y ProgresoDetalleView.swift), con el historial
 * grabado de la cuenta de prueba (`apps/shared/fixtures/test-nativa-real`: la rutina de 4 días y 384 filas). Las
 * sesiones son días locales: se leen en Buenos Aires.
 */
class VistaProgresoTest {
    private val ba = ZoneId.of("America/Argentina/Buenos_Aires")
    private var zonaAntes: TimeZone? = null

    @BeforeEach
    fun enBuenosAires() {
        zonaAntes = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone(ba))
    }

    @AfterEach
    fun zonaDeAntes() {
        TimeZone.setDefault(zonaAntes)
    }

    private val raiz: Path by lazy {
        generateSequence(Paths.get("").toAbsolutePath()) { it.parent }.first { Files.isDirectory(it.resolve("apps/shared/fixtures")) }
    }

    private fun grabada(nombre: String): String = raiz.resolve("apps/shared/fixtures/test-nativa-real/$nombre.json").toFile().readText()

    /** Las tarjetas como las arma `ModeloProgreso` con lo grabado (un transporte que contesta el historial). */
    private val tarjetas: List<TarjetaProgreso> by lazy {
        val historial = grabada("get_historico_por_clave")
        val transporte = object : Transporte {
            override suspend fun enviar(pedido: Pedido): Respuesta =
                Respuesta(200, (if (pedido.ruta.endsWith("mypump_get_historico_por_clave")) historial else "[]").toByteArray())
        }
        val fila = (ValorJson.parsear(grabada("get_rutina_activa")) as ValorJson.Lista).elementos.first()
        val p = ModeloProgreso(ClienteRpc(transporte = transporte), "tok")
        runBlocking { p.cargar(RutinaActiva.desde(fila.aJson())) }
        p.tarjetas.value
    }

    private fun tarjeta(clave: String) = tarjetas.first { it.clave == clave }

    @Test
    fun lasSeccionesSonLosDiasEnNombrePropio() {
        assertEquals(32, tarjetas.size)
        val secciones = VistaProgreso.secciones(tarjetas)
        // Una sección por combinación de días, en el orden de la rutina; el mismo ejercicio en dos días va en "Tirón · Piernas".
        assertEquals("Tirón · Piernas", secciones.first().titulo)
        assertEquals("TIRÓN · PIERNAS", secciones.first().id)
        assertEquals(listOf("rollout con ab wheel"), secciones.first().tarjetas.map { it.clave })
        assertTrue(secciones.any { s -> s.titulo == "Tirón" && s.tarjetas.any { it.clave == "jalon al pecho prono" } })
        assertTrue(secciones.any { s -> s.titulo == "Empuje · Torso" && s.tarjetas.any { it.clave == "crunch en maquina" } })
        // Nada queda en mayúsculas, ninguna tarjeta se pierde ni se repite.
        assertTrue(secciones.all { it.titulo != it.titulo.uppercase() })
        assertEquals(tarjetas.map { it.id }.sorted(), secciones.flatMap { s -> s.tarjetas.map { it.id } }.sorted())
    }

    @Test
    fun lasSesionesDelGraficoSonLasDeLaSerie() {
        val jalon = tarjeta("jalon al pecho prono")
        val sesiones = VistaProgreso.sesiones(jalon.filas, ba)
        assertEquals(
            listOf(
                VistaProgreso.Sesion(LocalDate.of(2026, 9, 10), 52.0),
                VistaProgreso.Sesion(LocalDate.of(2026, 9, 17), 54.0),
                VistaProgreso.Sesion(LocalDate.of(2026, 9, 24), 56.0),
                VistaProgreso.Sesion(LocalDate.of(2026, 10, 1), 58.0),
            ),
            sesiones,
        )
        assertEquals(jalon.resumen.serie, sesiones.map { it.kg })
        // Con el peso del cuerpo: 7 sesiones en 0 (sin gráfico en el detalle, como iOS).
        val rollout = tarjeta("rollout con ab wheel")
        assertEquals(List(7) { 0.0 }, VistaProgreso.sesiones(rollout.filas, ba).map { it.kg })
        assertTrue(!VistaProgreso.conPeso(rollout))
    }

    @Test
    fun loQueLeeTalkBackEnCadaFila() {
        assertEquals(
            "Jalón al pecho prono (dorsal ancho): tope 58 kilos, +11,5 % de progresión, récord",
            VistaProgreso.accesible(tarjeta("jalon al pecho prono")),
        )
        assertEquals("Rollout con ab wheel (core anterior): peso corporal", VistaProgreso.accesible(tarjeta("rollout con ab wheel")))
        assertEquals(
            "Máximo por sesión: 52 kg el 10 sept, 54 kg el 17 sept. Tope 54 kg.",
            VistaProgreso.graficoAccesible(listOf(VistaProgreso.Sesion(LocalDate.of(2026, 9, 10), 52.0), VistaProgreso.Sesion(LocalDate.of(2026, 9, 17), 54.0)), 54.0),
        )
    }

    @Test
    fun losNumerosComoIOSEnEsAR() {
        assertEquals("+11,5 %", VistaProgreso.variacion(11.5))
        assertEquals("+12 %", VistaProgreso.variacion(12.0))
        assertEquals("-5,2 %", VistaProgreso.variacion(-5.2))
        assertEquals("0 %", VistaProgreso.variacion(0.0))
        assertEquals("+1.234,5 %", VistaProgreso.variacion(1234.5))
        assertEquals("52,5", VistaProgreso.kg(52.5))
        assertEquals("58", VistaProgreso.kg(58.0))
        // Los kilos sin separador de miles (`grouping(.never)`).
        assertEquals("1050", VistaProgreso.kg(1050.0))
    }

    @Test
    fun lasFechasDeLaTablaSonDelDiaLocal() {
        assertEquals("24 sept", VistaProgreso.fechaCorta("2026-09-24T21:42:00+00:00", ba))
        assertEquals("1 oct", VistaProgreso.fechaCorta("2026-10-01T21:44:00+00:00", ba))
        // Las 2 de la mañana en UTC todavía son el día anterior en Buenos Aires.
        assertEquals("30 sept", VistaProgreso.fechaCorta("2026-10-01T02:00:00+00:00", ba))
        assertEquals("ene", VistaProgreso.fechaCorta(LocalDate.of(2026, 1, 5)).substringAfter(' '))
    }

    @Test
    fun lasMarcasDelEjeSonRedondas() {
        // El jalón: de 52 a 58 con el margen de 30 % (1,8 kg).
        assertEquals(listOf(52.0, 54.0, 56.0, 58.0), VistaProgreso.marcas(50.2, 59.8))
        assertEquals(listOf(0.0, 0.2, 0.4, 0.6, 0.8, 1.0), VistaProgreso.marcas(0.0, 1.0))
        assertEquals(listOf(100.0, 150.0, 200.0), VistaProgreso.marcas(80.0, 210.0))
        assertTrue(VistaProgreso.marcas(5.0, 5.0).isEmpty())
    }
}
