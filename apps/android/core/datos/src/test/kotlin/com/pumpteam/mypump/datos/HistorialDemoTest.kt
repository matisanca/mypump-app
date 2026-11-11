package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.reglas.ProgresoEjercicio
import com.pumpteam.mypump.reglas.PumpDelDia
import com.pumpteam.mypump.reglas.ReglasListaPrevia
import com.pumpteam.mypump.reglas.ReglasWins
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicInteger
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La demo con historial (2.3.0): `apps/shared/demo/historial.json` con las fechas relativas a hoy, y lo que ven Progreso,
 * Entreno, el Pump del día, el chat, la devolución y la lista previa. Sin red y sin escribir nada. Gemelo de
 * HistorialDemoTests.swift.
 */
class HistorialDemoTest {
    private val zona = ZoneId.of("America/Argentina/Buenos_Aires")

    /** Un martes a las 16:30 de Buenos Aires. */
    private val ahora = Instant.parse("2026-11-10T19:30:00Z")
    private fun historial(cuando: Instant = ahora) = HistorialDemo.desde(Compartido.texto("demo/historial.json"), cuando, zona)!!

    /** Un transporte que cuenta los pedidos (la demo no tiene que hacer ninguno). */
    private class Espia : Transporte {
        val pedidos = AtomicInteger(0)
        override suspend fun enviar(pedido: Pedido): Respuesta {
            pedidos.incrementAndGet()
            throw java.io.IOException("la demo no llama a nada")
        }
    }

    @Test fun lasFechasSonRelativasAHoy() {
        val h = historial()
        val remo = h.porClave["remo con barra"]!!
        // Del más nuevo al más viejo; la última sesión fue hace 5 días a las 18:40, una serie cada 3 minutos.
        assertEquals("2026-11-05T18:40:00-03:00", remo.first().registradoEn)
        assertEquals(listOf(1, 2, 3, 4), remo.take(4).map { it.serie })
        assertEquals("2026-11-05T18:43:00-03:00", remo[1].registradoEn)
        assertEquals("2026-09-17", remo.last().registradoEn.take(10))
        assertTrue(remo.all { it.clave == "remo con barra" && (it.pesoKg ?: 0.0) >= 50 && (it.reps ?: 0) >= 1 && it.rir == null })
        // Hoy no hay sesión, y otro día es otra fecha.
        assertTrue(h.historial.all { it.registradoEn.take(10) < "2026-11-10" })
        assertEquals("2026-11-06T18:40:00-03:00", historial(ahora.plusSeconds(86_400)).porClave["remo con barra"]?.first()?.registradoEn)
        assertEquals(11, h.porClave.size)
        // La clave es la del ejercicio (la que usa el historial de verdad).
        assertTrue(h.porClave.all { (clave, filas) -> filas.all { ClaveEjercicio.de(it.ejercicioNombre ?: "") == clave } })
    }

    @Test fun pesoPasosYMetas() {
        val h = historial()
        val peso = PesoCorporal.serie(h.salud)
        assertEquals(32, peso.size)
        assertEquals(PesoCorporal.Punto("2026-09-15", 84.5), peso.first())
        assertTrue(peso.all { it.fecha <= "2026-11-10" })
        val pasos = PumpDelDia.pasosPorDia(h.salud)
        assertEquals(6240, pasos["2026-11-10"]?.toInt())
        assertEquals(9000, h.metas?.metaPasos)
        assertEquals(-0.4, h.metas?.ritmoKgSemana)
        val v = PumpDelDia.vista(pasos, 9000, "2026-11-10")!!
        assertTrue(v.pasosHoy == 6240 && !v.cumplido && v.racha >= 2)
    }

    @Test fun chatDevolucionesYListaPrevia() {
        val h = historial()
        assertEquals(10, h.chat.size)
        assertTrue(h.chat.first().esDelCoach)
        assertEquals("Buenas, cómo arrancaste la semana?", h.chat.first().contenido)
        assertEquals("2026-10-29T10:15:00-03:00", h.chat.first().createdAt)
        assertEquals(h.chat.map { it.createdAt }.sorted(), h.chat.map { it.createdAt })
        assertEquals(10, h.chat.map { it.id }.toSet().size)
        // `semanas_atras: 1` = el lunes de la semana pasada (hoy es martes 10: el lunes 2).
        val d = h.devoluciones!!
        assertEquals(listOf("2026-11-02", "2026-10-26", "2026-10-19"), d.devoluciones.map { it.semanaLunes })
        assertEquals(3, d.ultima?.lineas?.size)
        assertEquals("Muy buena semana. Entrenaste los tres días y subiste la sentadilla.", d.ultima?.lineas?.first())
        assertEquals("2026-11-09", d.ultima?.publicadaDia)
        assertEquals("Llevás 1 de 3", ReglasListaPrevia.vista(h.listaPrevia)?.resumen)
    }

    @Test fun unArchivoRotoNoRompeLaDemo() {
        assertNull(HistorialDemo.desde("no es json"))
        assertNull(HistorialDemo.desde("[1,2]"))
        val vacio = HistorialDemo.desde("""{"entreno": "x", "peso": [{"dia": "hoy"}], "chat": [3], "pasos": [{"dia": 3, "pasos": 9}]}""")!!
        assertTrue(vacio.porClave.isEmpty() && vacio.salud.isEmpty() && vacio.chat.isEmpty())
        assertTrue(vacio.metas == null && vacio.devoluciones == null && vacio.listaPrevia == null)
    }

    @Test fun laDemoMuestraElHistorialSinRedYSinEscribir() = enUnHilo { alcance ->
        val espia = Espia()
        val raiz = carpetaTemporal("mypump-demo-historial")
        val m = ModeloApp(ClienteRpc(transporte = espia), TokenEnMemoria(null), raiz, PreferenciasEnMemoria(), alcance)
        m.entrarEnDemo(
            Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"), historial = Compartido.texto("demo/historial.json"),
        )
        assertTrue(m.esDemo.value && m.demoHistorial.value != null)
        val e = m.entreno.value!!
        e.cargar()
        e.precargarHistorial()
        // «Última vez» y «récord a superar» en Entreno, del historial de la demo.
        val lugar = e.dia.value.lista.first { it.tipo != "calentamiento" }
        e.pedirHistorial(lugar.id)
        val t = e.tarjeta(lugar.id)!!
        assertNotNull(t.record)
        assertNotNull(t.ultimaVez)
        // Progreso: una tarjeta por ejercicio con historial, con su récord, sin ir a la red.
        val filas = m.demoHistorial.value!!.porClave[ClaveEjercicio.de(lugar.nombre)]!!
        m.cargarProgreso()
        val p = m.progreso.value!!
        assertEquals(ModeloProgreso.Estado.LISTO, p.estado.value)
        assertEquals(11, p.tarjetas.value.size)
        assertEquals(ProgresoEjercicio.resumen(filas)!!.tope, p.tarjetas.value.first { it.clave == ClaveEjercicio.de(lugar.nombre) }.resumen.tope)
        assertTrue(p.tarjetas.value.all { it.resumen.tope > 0 })
        // El peso (Salud → Cuerpo) y los pasos.
        assertEquals(32, PesoCorporal.serie(m.revision.value!!.salud.value).size)
        // Pump del día y ritmo de peso, sin palanca.
        assertEquals(9000, m.metas()?.metaPasos)
        assertEquals(-0.4, m.metas()?.ritmoKgSemana)
        val (vista, conectado) = m.pumpDelDia()!!
        assertTrue(conectado && vista.pasosHoy == 6240 && vista.meta == 9000)
        // La celebración queda anotada en memoria (no hay disco).
        m.marcarPumpCelebrado()
        assertEquals(listOf(FechaLocal.hoy()), m.registroMetas.value.celebrados)
        // El chat con Mati y su devolución.
        val hilo = m.chat.value!!.hilo.value
        assertEquals(10, hilo.mensajes.size)
        assertFalse(hilo.hayMas)
        assertEquals(3, m.demoHistorial.value?.devoluciones?.devoluciones?.size)
        assertNull(m.devolucion.value)
        // La lista previa de la demo, como tarjeta propia.
        assertEquals(4, m.listaPrevia.value?.vista?.value?.items?.size)
        assertNull(m.wins.value)
        // Cargar más kg que la última vez: récord, y al cerrar hay festejo. Nada viaja.
        assertTrue(e.recordsDeHoy().isEmpty())
        val ultimo = filas.mapNotNull { it.pesoKg }.max()
        e.escribir(lugar.id, 0, "kg", (ultimo + 2.5).toString())
        e.escribir(lugar.id, 0, "reps", "8")
        e.confirmarSerie(lugar.id, 0) { true }
        val records = e.recordsDeHoy()
        assertEquals(1, records.size)
        assertEquals(ReglasWins.Tipo.RECORD_KG, records.first().tipo)
        assertEquals("+2,5 kg", records.first().chip)
        assertEquals(lugar.nombre, records.first().ejercicio)
        assertEquals(ModeloEntreno.ResultadoCierre.DEMO, e.cerrarDia(""))
        m.alVolverAPrimerPlano()
        m.sincronizarListaPrevia()
        assertEquals(0, espia.pedidos.get())
        assertFalse(raiz.resolve("MyPump").exists(), "la demo no escribe nada en disco")
        // Salir de la demo no deja nada.
        m.salirDeDemo()
        assertTrue(m.demoHistorial.value == null && m.listaPrevia.value == null && m.metas() == null && m.progreso.value == null)
        assertTrue(m.registroMetas.value.celebrados.isEmpty())
    }

    @Test fun sinElHistorialLaDemoQuedaComoAntes() = enUnHilo { alcance ->
        val m = ModeloApp(ClienteRpc(transporte = Espia()), TokenEnMemoria(null), carpetaTemporal("demo-sin"), PreferenciasEnMemoria(), alcance)
        m.entrarEnDemo(Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"))
        assertTrue(m.demoHistorial.value == null && m.listaPrevia.value == null && m.metas() == null && m.pumpDelDia() == null)
        assertNull(m.progreso.value)
        assertTrue(m.chat.value!!.hilo.value.mensajes.isEmpty())
        val e = m.entreno.value!!
        e.cargar()
        val lugar = e.dia.value.lista.first { it.tipo != "calentamiento" }
        e.pedirHistorial(lugar.id)
        assertNull(e.tarjeta(lugar.id)?.record)
        assertTrue(e.recordsDeHoy().isEmpty())
    }
}
