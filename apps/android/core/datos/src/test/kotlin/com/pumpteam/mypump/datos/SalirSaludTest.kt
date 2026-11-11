package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasMolestia
import java.io.File
import java.nio.file.Files
import java.time.OffsetDateTime
import java.time.ZoneOffset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Cerrar sesión con presión, fotos de inicio y molestias: como el outbox, lo que se ve se borra del teléfono y lo que espera
 * salir queda en la carpeta de esa cuenta y sale al volver a entrar con el mismo link. Gemelo de SalirSaludTests.swift.
 */
class SalirSaludTest {
    private val token = "tk-prueba-salir-salud"
    private val otro = "tk-prueba-salir-otro"
    private fun raiz(): File = Files.createTempDirectory("salir-salud").toFile()
    private val cuando = OffsetDateTime.of(2026, 11, 10, 9, 30, 0, 0, ZoneOffset.ofHours(-3))

    private fun jpeg(extra: Int = 0): ByteArray {
        val b = mutableListOf(0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, 1600 shr 8, 1600 and 0xFF, 1200 shr 8, 1200 and 0xFF, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01)
        repeat(extra) { b += it and 0x7F }
        b += listOf(0xFF, 0xD9)
        return ByteArray(b.size) { b[it].toByte() }
    }

    // ── Presión ──

    private fun presion(d: DoblePresion, r: File, t: String = token) =
        ModeloPresion(ClienteRpc(transporte = d), t, Disco(r, t), version = { "2.3.0" })

    @Test fun presionAlSalirBorraLoVistoYConservaLaCola(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val r = raiz()
        val disco = Disco(r, token)
        val m = presion(d, r)
        m.refrescar()
        assertTrue(m.habilitado)
        assertTrue(disco.archivo("presion-estado.json").exists())
        d.sinRed = true
        m.empezar("estandar", m.estado.value?.serie?.id, "izq", "anotar")
        m.anotarToma(124, 78, 62, false)
        m.marcarSintoma(listOf("palpitaciones"), "nota de prueba")
        m.drenar()
        assertEquals(2, m.enCola)
        assertNotNull(m.enCurso)

        m.olvidarAlSalir()
        assertFalse(m.habilitado)
        assertNull(m.enCurso)
        assertFalse(disco.archivo("presion-estado.json").exists(), "el estado del servidor no queda en el teléfono")
        val cola = ColaPresion.leer(disco)
        assertNull(cola.enCurso, "la sesión en curso (lo que se ve) se borra")
        assertEquals(2, cola.envios.size, "lo anotado sin señal sigue")
        d.sinRed = false
        val antes = d.llamadas.size
        m.refrescar()
        m.drenar()
        assertEquals(antes, d.llamadas.size, "después de salir no se llama a nada")

        assertEquals(0, presion(d, r, otro).enCola, "con otro link no se ve")

        val m2 = presion(d, r)
        assertEquals(2, m2.enCola)
        assertNull(m2.enCurso)
        m2.refrescar()
        m2.drenar()
        assertEquals(0, m2.enCola)
        assertEquals(1, d.sesiones.size)
        assertEquals(1, d.sintomas.size)
    }

    @Test fun presionSinNadaPendienteNoDejaArchivos(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val r = raiz()
        val disco = Disco(r, token)
        val m = presion(d, r)
        m.refrescar()
        m.empezar("estandar", m.estado.value?.serie?.id, "izq", "anotar")
        m.anotarToma(124, 78, 62, false)
        m.drenar()
        assertEquals(0, m.enCola)
        assertTrue(disco.archivo(ColaPresion.ARCHIVO).exists())
        m.olvidarAlSalir()
        assertFalse(disco.archivo(ColaPresion.ARCHIVO).exists())
        assertFalse(disco.archivo("presion-estado.json").exists())
    }

    // ── Fotos de inicio ──

    @Test fun fotosInicioAlSalirBorraLoSubidoYConservaLaCola(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val r = raiz()
        val disco = Disco(r, token)
        fun armar(t: String) = ModeloFotosInicio(ClienteRpc(transporte = d), t, Disco(r, t), esperar = {})
        val m = armar(token)
        m.refrescar()
        assertTrue(m.visible)
        assertEquals(ModeloFotosInicio.Foto.GUARDADA, m.encolar("frente", jpeg(), cuando))
        m.drenar()
        assertEquals(1, d.fotos.size)
        m.firmar()
        assertTrue(m.urls.value.isNotEmpty())
        assertTrue(disco.archivo(ModeloFotosInicio.ARCHIVO_ESTADO).exists())
        d.sinRed = true
        assertEquals(ModeloFotosInicio.Foto.GUARDADA, m.encolar("perfil", jpeg(3), cuando))
        assertEquals(ModeloFotosInicio.Salida.SIN_SENAL, m.guardarNota("nota de prueba"))
        m.drenar()
        val pendiente = m.cola.value.single().id

        m.olvidarAlSalir()
        assertFalse(m.visible)
        assertTrue(m.urls.value.isEmpty(), "las miniaturas firmadas no quedan")
        assertFalse(disco.archivo(ModeloFotosInicio.ARCHIVO_ESTADO).exists(), "lo ya subido (el estado) no queda en el teléfono")
        assertEquals(listOf(pendiente), PendienteFotoInicio.leerCola(disco).map { it.id })
        assertEquals(listOf("$pendiente.jpg"), disco.archivo(PendienteFotoInicio.CARPETA).list()?.toList(), "solo queda el JPEG que no subió")
        assertEquals("nota de prueba", PendienteFotoInicio.leerNota(disco))
        d.sinRed = false
        val antes = d.llamadas.size
        m.refrescar()
        m.drenar()
        assertEquals(antes, d.llamadas.size, "después de salir no se llama a nada")

        val ajeno = armar(otro)
        assertTrue(ajeno.cola.value.isEmpty() && ajeno.notaPendiente.value == null)

        val m2 = armar(token)
        assertEquals(listOf(pendiente), m2.cola.value.map { it.id })
        assertEquals("nota de prueba", m2.notaPendiente.value)
        m2.refrescar()
        m2.drenar()
        assertTrue(m2.cola.value.isEmpty())
        assertEquals(1, d.dePose("perfil").size)
        assertEquals("nota de prueba", d.notasRecibidas.last())
        assertNull(m2.notaPendiente.value)
    }

    // ── Molestias ──

    @Test fun molestiasAlSalirSeBorranDelTelefono(): Unit = runBlocking {
        val d = DobleFeedback()
        val disco = Disco(raiz(), token)
        val m = ModeloFeedback(ClienteRpc(transporte = d), token, disco)
        m.refrescar()
        val b = ReglasMolestia.Borrador(zona = "hombro", lado = "derecho", desde = "hoy", cuando = "al_subir", tipo = "sordo", intensidad = 5)
        assertEquals(ModeloFeedback.Salida.OK, m.avisar("id-1", "press-d1-0", "Press", "d1", b, null))
        m.refrescar()
        assertTrue(disco.archivo(ModeloFeedback.ARCHIVO).exists())
        m.olvidarAlSalir()
        assertNull(m.molestia("press-d1-0"))
        assertFalse(m.dueleHabilitado)
        assertFalse(disco.archivo(ModeloFeedback.ARCHIVO).exists())
        val antes = d.llamadas.size
        m.refrescar()
        assertEquals(antes, d.llamadas.size)
        assertFalse(disco.archivo(ModeloFeedback.ARCHIVO).exists())
    }

    // ── Desde la app ──

    @Test fun salirDeLaAppLimpiaLasTresSecciones() = enUnHilo { alcance ->
        val d = DobleFotosInicio.escenario("vacio")
        val r = carpetaTemporal("salir-salud-app")
        val t = "AAAAAAAAAAAAAAAAAAAA"
        fun app() = ModeloApp(ClienteRpc(transporte = transporteFotos(d)), TokenEnMemoria(t), r, PreferenciasEnMemoria(), alcance)
        val m = app()
        m.cargar()
        val f = m.fotosInicio.value!!
        assertTrue(esperar { f.estado.value != null })
        val disco = Disco(r, t)
        assertTrue(disco.archivo(ModeloFotosInicio.ARCHIVO_ESTADO).exists())
        // Lo que dejaron las otras dos secciones en una carga anterior.
        disco.guardar("presion-estado.json", ValorJson.objeto("habilitado" to ValorJson.Booleano(true)))
        disco.guardar(ModeloFeedback.ARCHIVO, ValorJson.objeto("molestias" to ValorJson.Lista(emptyList())))
        d.sinRed = true
        assertEquals(ModeloFotosInicio.Foto.GUARDADA, f.encolar("frente", jpeg(), cuando))
        f.drenar()
        m.salir()
        assertNull(m.fotosInicio.value)
        for (n in listOf(ModeloFotosInicio.ARCHIVO_ESTADO, "presion-estado.json", ModeloFeedback.ARCHIVO)) {
            assertFalse(disco.archivo(n).exists(), n)
        }
        assertEquals(1, PendienteFotoInicio.leerCola(disco).size)
        d.sinRed = false
        val m2 = app()
        m2.cargar()
        m2.alVolverLaRed()
        assertTrue(esperar { d.fotos.size == 1 }, "con el mismo link sale lo pendiente")
    }

    private fun transporteFotos(d: DobleFotosInicio) = Transporte { pedido ->
        val fn = pedido.ruta.substringAfterLast('/')
        when {
            "inicio" in pedido.ruta || fn == "mypump_get_app_config" -> d.enviar(pedido)
            fn == "mypump_get_cliente_info" -> Respuesta(200, """[{"cliente_id":"c-fotos","nombre":"Cliente","perfil":"natural"}]""".toByteArray())
            else -> Respuesta(200, "[]".toByteArray())
        }
    }

    private suspend fun esperar(condicion: () -> Boolean): Boolean {
        repeat(150) {
            if (condicion()) return true
            delay(20)
        }
        return condicion()
    }
}
