package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FotosInicio
import java.io.File
import java.nio.file.Files
import java.time.OffsetDateTime
import java.time.ZoneOffset
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La cola de las fotos de inicio contra el doble que sigue el contrato (sección 13). */
class FotosInicioTest {
    /** Un JPEG mínimo pero entero (SOI, un SOF de 1200 × 1600 y EOI), para que el doble lo mida como el servidor. */
    private fun jpeg(ancho: Int = 1200, alto: Int = 1600, extra: Int = 0): ByteArray {
        val b = mutableListOf(0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08, alto shr 8, alto and 0xFF, ancho shr 8, ancho and 0xFF, 0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01)
        repeat(extra) { b += it and 0x7F }
        b += listOf(0xFF, 0xD9)
        return ByteArray(b.size) { b[it].toByte() }
    }

    private val token = "tk-prueba-fotos-inicio"
    private val cuando = OffsetDateTime.of(2026, 11, 10, 9, 30, 0, 0, ZoneOffset.ofHours(-3))
    private val medida = FotosInicio.Medida(120.5, 60.25)
    private fun raiz() = Files.createTempDirectory("fotos-inicio").toFile()
    private fun armar(d: DobleFotosInicio, r: File = raiz(), reloj: () -> Long = System::currentTimeMillis) =
        ModeloFotosInicio(ClienteRpc(transporte = d), token, Disco(r, token), esperar = {}, ahora = reloj)

    private fun ModeloFotosInicio.poner(pose: String, bytes: ByteArray = jpeg()) = encolar(pose, bytes, cuando, medida)

    @Test fun subidaFelizDeLasTresPosesYCompleto(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        assertTrue(m.visible)
        assertEquals(listOf("frente", "perfil", "espalda"), m.faltan)
        assertEquals(ModeloFotosInicio.EstadoPose.FALTA, m.estadoPose("frente"))
        for (p in listOf("frente", "perfil", "espalda")) assertEquals(ModeloFotosInicio.Foto.GUARDADA, m.poner(p))
        assertEquals(3, m.hechas)
        assertFalse(m.listas)
        assertEquals(ModeloFotosInicio.EstadoPose.ESPERANDO, m.estadoPose("perfil"))
        val archivos = m.cola.value.map { m.archivo(it.id) }
        assertTrue(archivos.all { it.exists() })
        m.drenar()
        assertTrue(m.cola.value.isEmpty())
        assertTrue(archivos.none { it.exists() }, "los JPEG subidos se borran del teléfono")
        assertEquals(listOf("frente", "perfil", "espalda"), d.fotos.map { it.pose })
        assertEquals(1200 to 1600, d.fotos[0].ancho to d.fotos[0].alto)
        assertTrue(m.estado.value!!.completo, "con la cola vacía se refresca y el servidor dice completo")
        assertTrue(m.listas)
        assertEquals(ModeloFotosInicio.EstadoPose.LISTA, m.estadoPose("espalda"))
        assertEquals(2, d.llamadas.count { it == "mypump_fotos_inicio_get" })
        // Los encabezados del contrato.
        val h = d.cabecerasUltimaSubida
        assertEquals("image/jpeg", h["Content-Type"])
        assertEquals(token, h["x-inicio-token"])
        assertEquals("espalda", h["x-inicio-pose"])
        assertEquals(d.fotos[2].id, h["x-inicio-foto"])
        assertEquals("2026-11-10T09:30:00-03:00", h["x-inicio-tomada"])
        assertEquals(cuando.toInstant(), OffsetDateTime.parse(h["x-inicio-tomada"]).toInstant())
        assertEquals("120.50", h["x-inicio-brillo"])
        assertEquals("60.25", h["x-inicio-nitidez"])
        assertTrue(jpeg().contentEquals(d.fotos[0].bytes))
        assertEquals(3, d.fotos.map { it.id }.toSet().size)
    }

    @Test fun unaPoseNuevaReemplazaALaDeLaCola(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        d.sinRed = true
        m.poner("frente")
        m.poner("perfil")
        val vieja = m.cola.value.first { it.pose == "frente" }
        m.poner("frente")
        assertEquals(2, m.cola.value.size)
        assertFalse(m.archivo(vieja.id).exists(), "la reemplazada se borra del disco")
        val nueva = m.cola.value.first { it.pose == "frente" }
        assertNotEquals(vieja.id, nueva.id)
        assertEquals(listOf("perfil", "frente"), m.cola.value.map { it.pose }, "la nueva va al final, en el orden en que se encoló")
        d.sinRed = false
        m.drenar()
        assertEquals(listOf(nueva.id), d.dePose("frente").map { it.id })
        assertEquals(2, d.intentosDeSubida, "la reemplazada nunca se intentó subir")
        // La motivación no se reemplaza: se suman.
        m.poner(FotosInicio.MOTIVACION, jpeg(400, 500))
        m.poner(FotosInicio.MOTIVACION, jpeg(400, 500))
        assertEquals(2, m.cola.value.size)
    }

    @Test fun unaPoseNuevaReemplazaALaDelServidorSinEsperarlo(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("dos")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        val viejoFrente = m.estado.value!!.foto("frente")!!.id
        val viejoPerfil = m.estado.value!!.foto("perfil")!!.id
        assertEquals(listOf("espalda"), m.faltan)
        m.poner("frente")
        m.poner("perfil")
        val nuevoFrente = m.cola.value[0].id
        // La primera sube y la segunda se corta: la cola no queda vacía y no se le pregunta al servidor.
        d.proximasSubidas.addAll(listOf(200, 0))
        m.drenar()
        assertEquals(1, d.llamadas.count { it == "mypump_fotos_inicio_get" })
        assertEquals(nuevoFrente, m.estado.value!!.foto("frente")!!.id, "el estado ya muestra la nueva")
        assertEquals(1, m.estado.value!!.fotos.count { it.pose == "frente" })
        assertEquals(viejoPerfil, m.estado.value!!.foto("perfil")!!.id)
        assertEquals(ModeloFotosInicio.EstadoPose.ESPERANDO, m.estadoPose("perfil"))
        assertEquals(listOf(nuevoFrente), d.dePose("frente").map { it.id })
        assertNotEquals(viejoFrente, nuevoFrente)
        // Lo que se actualizó en el teléfono queda guardado: sin red se ve igual.
        d.sinRed = true
        val m2 = armar(d, r)
        m2.refrescar()
        assertEquals(nuevoFrente, m2.estado.value?.foto("frente")?.id)
    }

    @Test fun sinRedQuedaEnDiscoYReanuda(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        d.sinRed = true
        m.poner("frente")
        m.poner(FotosInicio.MOTIVACION, jpeg(400, 600))
        m.drenar()
        assertEquals(2, m.cola.value.size)
        assertEquals(ModeloFotosInicio.EstadoPose.ESPERANDO, m.estadoPose("frente"))
        assertTrue(m.motivacion.single().esperando)
        // Se cierra la app sin red: el modelo nuevo lee la cola y el último estado del disco.
        val viva = m.archivo(m.cola.value[0].id)
        val huerfana = File(viva.parentFile, "huerfana.jpg").apply { writeBytes(jpeg()) }
        val m2 = armar(d, r)
        assertFalse(huerfana.exists(), "se barren los JPEG que no están en el índice")
        assertTrue(viva.exists())
        assertEquals(m.cola.value, m2.cola.value)
        m2.refrescar()
        assertNotNull(m2.estado.value, "sin red, lo último que se supo")
        d.sinRed = false
        m2.drenar()
        assertTrue(m2.cola.value.isEmpty())
        assertEquals(listOf("frente", FotosInicio.MOTIVACION), d.fotos.map { it.pose })
    }

    @Test fun sinRedYSinNadaGuardadoNoSeMuestra(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        d.sinRed = true
        val m = armar(d)
        m.refrescar()
        assertNull(m.estado.value)
        assertEquals(ModeloFotosInicio.Foto.NO_SE_GUARDO, m.poner("frente"))
    }

    @Test fun cincoXXNoPierdeLaFotoYSeReintenta(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        m.poner("frente")
        d.proximasSubidas.addAll(listOf(503, 429, 502, 200))
        m.drenar()
        assertEquals(1, m.cola.value.size, "tres errores seguidos cortan la pasada")
        assertEquals(3, d.intentosDeSubida)
        m.drenar()
        assertTrue(m.cola.value.isEmpty())
        assertEquals(1, d.fotos.size)
        assertEquals(4, d.intentosDeSubida)
        assertNull(m.aviso.value)
    }

    @Test fun cuatroXXDescartaConAvisoYSigue(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        m.poner("frente")
        m.poner("perfil")
        d.proximasSubidas.add(422)
        m.drenar()
        assertEquals(FotosInicio.Aviso.RECHAZADA, m.aviso.value)
        assertTrue(m.cola.value.isEmpty())
        assertEquals(listOf("perfil"), d.fotos.map { it.pose })
        assertEquals(ModeloFotosInicio.EstadoPose.FALTA, m.estadoPose("frente"))
        // Lo que el servidor no recibe (no es un JPEG entero) también es definitivo.
        m.poner("frente", byteArrayOf(1, 2, 3))
        m.drenar()
        assertEquals(FotosInicio.Aviso.RECHAZADA, m.aviso.value)
        assertTrue(m.cola.value.isEmpty())
        m.limpiarAviso()
        assertNull(m.aviso.value)
    }

    @Test fun cuatroCeroTresDescartaYRefresca(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        m.poner("frente")
        m.poner("perfil")
        d.habilitado = false   // Mati cerró la sección
        m.drenar()
        assertTrue(d.fotos.isEmpty())
        assertEquals(1, d.intentosDeSubida, "con 403 no se sigue probando con las demás")
        assertEquals(2, d.llamadas.count { it == "mypump_fotos_inicio_get" })
        assertNull(m.estado.value, "se refrescó: ya no está habilitado")
        assertNull(m.aviso.value)
    }

    @Test fun topeDeMotivacion(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        repeat(4) { assertEquals(ModeloFotosInicio.Foto.GUARDADA, m.poner(FotosInicio.MOTIVACION, jpeg(400, 500))) }
        assertFalse(m.puedeAgregarMotivacion)
        assertEquals(ModeloFotosInicio.Foto.TOPE, m.poner(FotosInicio.MOTIVACION, jpeg(400, 500)))
        assertEquals(FotosInicio.Aviso.TOPE, m.aviso.value)
        m.drenar()
        assertEquals(4, d.dePose(FotosInicio.MOTIVACION).size)
        assertEquals(4, m.motivacion.size)
        assertFalse(m.puedeAgregarMotivacion)
        // El servidor manda: si su tope es menor, contesta 413 y se avisa.
        val d2 = DobleFotosInicio.escenario("vacio").also { it.maxMotivacion = 1 }
        val m2 = armar(d2)
        m2.refrescar()
        assertEquals(1, m2.maxMotivacion)
        m2.poner(FotosInicio.MOTIVACION, jpeg(400, 500))
        assertEquals(ModeloFotosInicio.Foto.TOPE, m2.poner(FotosInicio.MOTIVACION, jpeg(400, 500)))
        d2.maxMotivacion = 0
        m2.drenar()
        assertEquals(FotosInicio.Aviso.TOPE, m2.aviso.value)
        assertTrue(d2.fotos.isEmpty())
    }

    @Test fun borrarMotivacionEnColaYEnElServidor(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        m.poner(FotosInicio.MOTIVACION, jpeg(400, 500))
        val enCola = m.cola.value.single()
        assertEquals(ModeloFotosInicio.Salida.OK, m.borrarMotivacion(enCola.id))
        assertTrue(m.cola.value.isEmpty())
        assertFalse(m.archivo(enCola.id).exists())
        assertFalse("inicio/borrar" in d.llamadas, "la de la cola no llega a preguntarle al servidor")
        m.poner(FotosInicio.MOTIVACION, jpeg(400, 500))
        m.poner("frente")
        m.drenar()
        val id = d.dePose(FotosInicio.MOTIVACION).single().id
        assertEquals(listOf(id), m.motivacion.map { it.id })
        assertNull(m.motivacion.single().archivoLocal)
        d.sinRed = true
        assertEquals(ModeloFotosInicio.Salida.SIN_SENAL, m.borrarMotivacion(id))
        assertEquals(1, m.motivacion.size)
        d.sinRed = false
        assertEquals(ModeloFotosInicio.Salida.OK, m.borrarMotivacion(id))
        assertTrue(d.dePose(FotosInicio.MOTIVACION).isEmpty())
        assertTrue(m.motivacion.isEmpty())
        // Las del cuerpo no se borran: se reemplazan.
        assertEquals(ModeloFotosInicio.Salida.ERROR, m.borrarMotivacion(d.dePose("frente").single().id))
        assertEquals(1, d.dePose("frente").size)
    }

    @Test fun laNotaSinRedQuedaGuardadaYSaleConLaCola(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        d.sinRed = true
        assertEquals(ModeloFotosInicio.Salida.SIN_SENAL, m.guardarNota("  Hombros\ny cintura  "))
        assertEquals("Hombros y cintura", m.notaPendiente.value)
        assertTrue(File(r, "").walkTopDown().any { it.name == ModeloFotosInicio.ARCHIVO_NOTA })
        // Se cierra la app: la nota sigue esperando.
        val m2 = armar(d, r)
        assertEquals("Hombros y cintura", m2.notaPendiente.value)
        d.sinRed = false
        m2.refrescar()
        m2.drenar()
        assertEquals("Hombros y cintura", d.nota)
        assertNull(m2.notaPendiente.value)
        assertEquals("Hombros y cintura", m2.estado.value?.nota)
        assertFalse(File(r, "").walkTopDown().any { it.name == ModeloFotosInicio.ARCHIVO_NOTA })
        // Con red sale en el momento, recortada como la guarda el servidor (300 puntos de código: un emoji cuenta uno).
        assertEquals(ModeloFotosInicio.Salida.OK, m2.guardarNota("💪".repeat(320)))
        assertEquals(300, d.nota.codePointCount(0, d.nota.length))
        assertEquals(d.notasRecibidas.last(), d.nota)
    }

    @Test fun laNotaConLaSeccionCerradaNoQuedaPendiente(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val m = armar(d)
        m.refrescar()
        d.habilitado = false
        assertEquals(ModeloFotosInicio.Salida.ERROR, m.guardarNota("algo"))
        assertNull(m.notaPendiente.value)
        assertNull(m.estado.value)
    }

    @Test fun tokenCaido(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        d.sinRed = true
        m.guardarNota("la de antes")
        d.sinRed = false
        d.tokenCaido = true
        assertEquals(ModeloFotosInicio.Salida.TOKEN_CAIDO, m.guardarNota("la nota"))
        assertTrue(m.tokenCaido.value)
        assertEquals("la nota", m.notaPendiente.value, "queda guardada para el link nuevo")
        m.refrescar()
        assertNull(m.estado.value)
        assertTrue(m.tokenCaido.value)
        // Desde cero con el token caído: no se ve nada, aunque el disco tenga el estado de antes.
        val m2 = armar(d, r)
        m2.refrescar()
        assertNull(m2.estado.value)
    }

    @Test fun apagadoSinServidorONoHabilitadoNoMuestraNada(): Unit = runBlocking {
        for (e in listOf("sinServidor", "noHabilitado")) {
            val d = DobleFotosInicio.escenario("vacio")
            val r = raiz()
            armar(d, r).refrescar()
            assertTrue(File(r, "").walkTopDown().any { it.name == ModeloFotosInicio.ARCHIVO_ESTADO })
            if (e == "sinServidor") d.sinFuncion = true else d.habilitado = false
            val m = armar(d, r)
            m.refrescar()
            assertNull(m.estado.value, e)
            assertFalse(m.visible, e)
            assertFalse(File(r, "").walkTopDown().any { it.name == ModeloFotosInicio.ARCHIVO_ESTADO }, "$e: se olvida lo guardado")
            m.drenar()
            assertEquals(0, d.intentosDeSubida, e)
        }
    }

    @Test fun miniaturasConCache(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("dos")
        var reloj = 1_000_000L
        val m = armar(d, reloj = { reloj })
        m.refrescar()
        m.firmar()
        assertEquals(2, m.urls.value.size)
        m.firmar()
        assertEquals(1, d.llamadas.count { it == "inicio/urls" }, "dentro de los 50 min no se piden de nuevo")
        m.poner("espalda")
        m.drenar()
        m.firmar()
        assertEquals(2, d.llamadas.count { it == "inicio/urls" }, "apareció una que no estaba")
        assertEquals(3, m.urls.value.size)
        reloj += 51 * 60 * 1000L
        m.firmar()
        assertEquals(3, d.llamadas.count { it == "inicio/urls" }, "a los 50 min se piden de nuevo")
    }

    @Test fun elLinkNuevoAdoptaLasFotosYLaNota(): Unit = runBlocking {
        val d = DobleFotosInicio.escenario("vacio")
        val r = raiz()
        val m = armar(d, r)
        m.refrescar()
        d.sinRed = true
        m.poner("frente")
        m.guardarNota("hombros")
        val nuevo = ModeloFotosInicio(ClienteRpc(transporte = d), "tk-otro-link", Disco(r, "tk-otro-link"), esperar = {})
        assertTrue(nuevo.adoptar(m.cola.value, Disco(r, token)))
        assertEquals(1, nuevo.cola.value.size)
        assertTrue(nuevo.archivo(nuevo.cola.value[0].id).exists())
        assertEquals("hombros", nuevo.notaPendiente.value)
    }

    @Test fun palancaApagadaNoLlamaANadaDeFotosDeInicio() = enUnHilo { alcance ->
        val j = ValorJson.parsear("""{"fotos_inicio":false}""")
        assertFalse(PalancaRemota.desde(j).fotosInicio)
        assertTrue(PalancaRemota.desde(ValorJson.parsear("""{"fotos_inicio":true}""")).fotosInicio)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("""{"fotos_inicio":"si"}""")).fotosInicio)
        assertFalse(PalancaRemota.deFabrica.fotosInicio)

        val d = DobleFotosInicio.escenario("apagado")
        val m = modeloApp(d, alcance)
        m.cargar()
        val f = m.fotosInicio.value!!
        assertFalse(f.palancaRecordada)
        m.alVolverAPrimerPlano()
        m.alVolverLaRed()
        delay(50)
        assertNull(f.estado.value)
        assertTrue(d.llamadasFotosInicio.isEmpty(), "con la palanca apagada no se llama nada: ${d.llamadasFotosInicio}")
    }

    @Test fun palancaPrendidaCargaYSubeLoQueQuedo() = enUnHilo { alcance ->
        val d = DobleFotosInicio.escenario("vacio")
        val m = modeloApp(d, alcance)
        m.cargar()
        val f = m.fotosInicio.value!!
        assertTrue(f.palancaRecordada)
        // La palanca se lee junto con la rutina: la primera carga ya pregunta.
        assertTrue(esperar { f.estado.value != null })
        d.sinRed = true
        assertEquals(ModeloFotosInicio.Foto.GUARDADA, f.poner("frente"))
        f.drenar()
        d.sinRed = false
        m.alVolverLaRed()
        assertTrue(esperar { d.fotos.size == 1 }, "al volver la red sale lo pendiente")
        // Al apagarse la palanca deja de verse en la próxima carga.
        d.palanca = false
        m.cargar()
        assertNull(m.fotosInicio.value?.estado?.value)
    }

    private suspend fun esperar(condicion: () -> Boolean): Boolean {
        repeat(150) {
            if (condicion()) return true
            delay(20)
        }
        return condicion()
    }

    private fun modeloApp(d: DobleFotosInicio, alcance: kotlinx.coroutines.CoroutineScope): ModeloApp {
        val t = Transporte { pedido ->
            val fn = pedido.ruta.substringAfterLast('/')
            when {
                "inicio" in pedido.ruta || fn == "mypump_get_app_config" -> d.enviar(pedido)
                fn == "mypump_get_cliente_info" -> Respuesta(200, """[{"cliente_id":"c-fotos","nombre":"Cliente","perfil":"natural"}]""".toByteArray())
                else -> Respuesta(200, "[]".toByteArray())
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("fotos-inicio-app"), PreferenciasEnMemoria(), alcance)
    }
}
