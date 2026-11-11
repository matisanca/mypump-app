package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Casa
import com.pumpteam.mypump.reglas.Compras
import com.pumpteam.mypump.reglas.Gimnasio
import com.pumpteam.mypump.reglas.Recorrido
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * La cola B (2.3.0): «Tu recorrido», «Dónde comprarlo» y «Entreno en casa» contra dobles que siguen `cola-b/CONTRATO_APP.md`.
 * Datos inventados y obvios.
 */
class ColaBTest {
    private val token = "tk-prueba-cola-b"
    private val nuevas = listOf("mypump_fin_plan", "mypump_compras", "mypump_casa")
    private fun List<String>.deLaColaB() = filter { fn -> nuevas.any { fn.startsWith(it) } }

    // ---------------------------------------------------------------- Fin de plan

    private fun recorrido(estado: String = "publicado", agenda: String = "mati", respuestas: String = "{}") =
        """{"habilitado":true,"visible":true,"estado":"$estado","agenda":"$agenda","respuestas":$respuestas,
            "resumen":{"titulo":"Tus meses de prueba","logros":[{"titulo":"Entrenos","valor":"72","detalle":"De 80 posibles"}]}}"""

    /** Un servidor de «Tu recorrido» de mentira: guarda el pedido por id, como la función. */
    private inner class ServidorFinPlan {
        var estado = "publicado"
        var visible = true
        var pedidoId: String? = null
        var respuestas = "{}"
        var cortes = 0
        var fallaGet: Pair<Int, String>? = null
        val pedidos = mutableListOf<ValorJson>()
        val t = TransporteProgramado { fn, c ->
            when (fn) {
                "mypump_fin_plan_get" -> fallaGet ?: (200 to if (visible) recorrido(estado, respuestas = respuestas) else """{"habilitado":true,"visible":false}""")
                "mypump_fin_plan_visto" -> 200 to """{"ok":true}"""
                "mypump_fin_plan_pedir" -> {
                    pedidos += c
                    if (cortes > 0) {
                        cortes--
                        // El pedido llegó y la respuesta se perdió.
                        tomar(c)
                        throw java.io.IOException("corte (doble)")
                    }
                    200 to tomar(c)
                }
                else -> 200 to "[]"
            }
        }

        private fun tomar(c: ValorJson): String {
            if (estado != "publicado") return """{"ok":true,"ya":true,"estado":"$estado"}"""
            estado = "pedido"
            pedidoId = c["p_id"]?.comoTexto
            respuestas = c["p_respuestas"]?.serializar() ?: "{}"
            return """{"ok":true,"ya":false,"estado":"pedido"}"""
        }
    }

    private fun finPlan(t: Transporte, raiz: File, ids: Iterator<String> = generateSequence(1) { it + 1 }.map { "id-$it" }.iterator()) =
        ModeloFinPlan(ClienteRpc(transporte = t), token, Disco(raiz, token), nuevoId = { ids.next() }).also { it.usarPalanca(true) }

    @Test fun finPlanSeVeSePideYQuedaPedido(): Unit = runBlocking {
        val s = ServidorFinPlan()
        val m = finPlan(s.t, carpetaTemporal("finplan"))
        assertNull(m.recorrido.value)
        m.refrescar()
        assertEquals(Recorrido.Estado.PUBLICADO, m.recorrido.value?.estado)
        assertTrue(m.seAbreSola)
        m.alAbrirLaHoja()
        assertFalse(m.seAbreSola)
        m.alAbrirLaHoja()
        // El «visto» va una sola vez.
        assertEquals(1, s.t.llamadas.count { it == "mypump_fin_plan_visto" })
        m.escribir("mejor", "  Entrenar con ganas  ")
        m.escribir("costo", "y".repeat(900))
        assertEquals(500, m.local.value.escrito.costo.length)
        assertEquals(ModeloFinPlan.Salida.OK, m.pedir())
        assertEquals(Recorrido.Estado.PEDIDO, m.recorrido.value?.estado)
        assertFalse(m.enviando.value)
        val p = s.pedidos.single()
        assertEquals(token, p["p_token"]?.comoTexto)
        assertEquals("id-1", p["p_id"]?.comoTexto)
        assertEquals("Entrenar con ganas", p["p_respuestas"]?.get("mejor")?.comoTexto)
        assertEquals(500, p["p_respuestas"]?.get("costo")?.comoTexto?.length)
        assertNull(p["p_respuestas"]?.get("objetivo"))
        // Nunca viaja el cliente.
        assertFalse(p.serializar().contains("cliente_id"))
        // Ya pedido: no queda id ni texto a medias, y pedir de nuevo no manda nada.
        assertNull(m.local.value.pedidoId)
        assertTrue(m.local.value.escrito.vacias)
        assertEquals(ModeloFinPlan.Salida.OK, m.pedir())
        assertEquals(1, s.pedidos.size)
    }

    /** El id se guarda en disco antes de mandar: un corte y hasta cerrar la app reintentan con el mismo. */
    @Test fun finPlanElPedidoEsIdempotenteConElMismoId(): Unit = runBlocking {
        val s = ServidorFinPlan()
        val raiz = carpetaTemporal("finplan-id")
        val ids = listOf("id-uno", "id-dos", "id-tres").iterator()
        val m = finPlan(s.t, raiz, ids)
        m.refrescar()
        m.escribir("objetivo", "Seguir")
        // Sin red: no sale, el botón vuelve y el id queda guardado.
        val sinRed = ModeloFinPlan(ClienteRpc(transporte = SinRed), token, Disco(raiz, token), nuevoId = { ids.next() })
        assertEquals(Recorrido.Estado.PUBLICADO, sinRed.recorrido.value?.estado)   // la copia en disco
        assertEquals(ModeloFinPlan.Salida.ERROR, sinRed.pedir())
        assertFalse(sinRed.enviando.value)
        assertEquals(Recorrido.Estado.PUBLICADO, sinRed.recorrido.value?.estado)
        val guardado = LocalFinPlan.desde(ValorJson.desde(Disco(raiz, token).leer(ModeloFinPlan.ARCHIVO_LOCAL)!!))
        assertEquals("id-uno", guardado.pedidoId)
        assertEquals("Seguir", guardado.escrito.objetivo)

        // Otra apertura de la app: el pedido llega pero la respuesta se pierde; el reintento va con el MISMO id y da `ya`.
        s.estado = "publicado"
        s.cortes = 1
        val otra = finPlan(s.t, raiz, ids)
        otra.refrescar()
        assertEquals(ModeloFinPlan.Salida.ERROR, otra.pedir())
        assertEquals(ModeloFinPlan.Salida.OK, otra.pedir())
        assertEquals(listOf("id-uno", "id-uno"), s.pedidos.map { it["p_id"]?.comoTexto })
        assertEquals("id-uno", s.pedidoId)
        assertEquals(Recorrido.Estado.PEDIDO, otra.recorrido.value?.estado)
        assertNull(otra.local.value.pedidoId)
    }

    @Test fun finPlanApagadoONoDisponibleDejaDeVerse(): Unit = runBlocking {
        for (error in listOf("apagado", "no_disponible")) {
            var visible = true
            val t = TransporteProgramado { fn, _ ->
                when (fn) {
                    "mypump_fin_plan_get" -> 200 to (if (visible) recorrido() else """{"habilitado":true,"visible":false}""")
                    "mypump_fin_plan_pedir" -> {
                        visible = false
                        200 to """{"ok":false,"error":"$error"}"""
                    }
                    else -> 200 to "[]"
                }
            }
            val raiz = carpetaTemporal("finplan-no")
            val m = finPlan(t, raiz)
            m.refrescar()
            assertEquals(ModeloFinPlan.Salida.YA_NO, m.pedir(), error)
            assertNull(m.recorrido.value, error)
            assertNull(Disco(raiz, token).leer(ModeloFinPlan.ARCHIVO), error)
        }
    }

    @Test fun finPlanLoQueNoSeVe(): Unit = runBlocking {
        val noSeVe = listOf(
            200 to "null",   // token caído
            200 to """{"habilitado":false}""",
            200 to """{"habilitado":true,"visible":false}""",
            200 to recorrido(estado = "cerrado"),
            200 to recorrido(estado = "estado_nuevo"),
            404 to """{"code":"PGRST202","message":"no existe"}""",
            404 to "",
        )
        for (r in noSeVe) {
            // Sin nada antes: nada.
            val vacio = finPlan(TransporteProgramado { _, _ -> r }, carpetaTemporal("finplan-x"))
            vacio.refrescar()
            assertNull(vacio.recorrido.value, "$r")
            // Y si antes se veía, deja de verse y se borra la copia.
            var respuesta = 200 to recorrido()
            val raiz = carpetaTemporal("finplan-y")
            val m = finPlan(TransporteProgramado { _, _ -> respuesta }, raiz)
            m.refrescar()
            assertNotNull(m.recorrido.value)
            respuesta = r
            m.refrescar()
            assertNull(m.recorrido.value, "$r")
            assertNull(Disco(raiz, token).leer(ModeloFinPlan.ARCHIVO), "$r")
        }
    }

    @Test fun finPlanUnCorteDejaLoQueSeVeia(): Unit = runBlocking {
        val raiz = carpetaTemporal("finplan-corte")
        var respuesta = 200 to recorrido()
        val m = finPlan(TransporteProgramado { _, _ -> respuesta }, raiz)
        m.refrescar()
        for (corte in listOf(500 to """{"message":"caído"}""", 503 to "", 429 to "")) {
            respuesta = corte
            m.refrescar()
            assertNotNull(m.recorrido.value, "$corte")
        }
        // Sin red al abrir: la copia. Y con error del servidor al pedir, el aviso de siempre.
        val sinRed = ModeloFinPlan(ClienteRpc(transporte = SinRed), token, Disco(raiz, token))
        sinRed.refrescar()
        assertEquals("Tus meses de prueba", sinRed.recorrido.value?.resumen?.titulo)
        respuesta = 200 to "null"
        assertEquals(ModeloFinPlan.Salida.ERROR, m.pedir())   // token caído
        // Con la palanca apagada la copia no se muestra aunque esté.
        val apagada = ModeloFinPlan(ClienteRpc(transporte = SinRed), token, Disco(raiz, token)).also { it.usarPalanca(false) }
        assertNull(apagada.recorrido.value)
        assertNull(ModeloFinPlan(ClienteRpc(transporte = SinRed), token, Disco(raiz, token)).recorrido.value)
    }

    @Test fun finPlanSeAbreSolaUnaVezPorRecorrido(): Unit = runBlocking {
        val s = ServidorFinPlan()
        val raiz = carpetaTemporal("finplan-sola")
        val m = finPlan(s.t, raiz)
        m.refrescar()
        assertTrue(m.seAbreSola)
        m.marcarAbiertaSola()
        // Otra apertura de la app: ya no.
        val otra = finPlan(s.t, raiz)
        otra.refrescar()
        assertFalse(otra.seAbreSola)
        // Terminó ese recorrido y, meses después, Mati publica otro: se abre solo de nuevo, una vez.
        s.visible = false
        otra.refrescar()
        s.visible = true
        otra.refrescar()
        assertTrue(otra.seAbreSola)
        // Lo que llega ya pedido (desde otro teléfono) no se abre solo.
        s.estado = "pedido"
        val tercero = finPlan(s.t, carpetaTemporal("finplan-otro"))
        tercero.refrescar()
        assertFalse(tercero.seAbreSola)
        // Apagar la palanca y volver a prenderla no la reabre.
        s.estado = "publicado"
        m.usarPalanca(false)
        m.usarPalanca(true)
        m.refrescar()
        assertFalse(m.seAbreSola)
    }

    // ---------------------------------------------------------------- Compras

    private val comprasJson = """{"habilitado":true,"pais":"AR","items":[{"nombre":"Creatina","opciones":[
        {"producto":"Creatina Inventada","tienda":"Tienda Ejemplo","url":"https://tienda-ejemplo.invalid/c"},{"producto":"Otra","tienda":"Tienda Dos","url":"http://sin-candado.invalid"}]}]}"""

    private fun compras(t: Transporte, raiz: File) = ModeloCompras(ClienteRpc(transporte = t), token, Disco(raiz, token)).also { it.usarPalanca(true) }

    @Test fun comprasSeLeenSeGuardanYSeVenSinRed(): Unit = runBlocking {
        val raiz = carpetaTemporal("compras")
        val cuerpos = mutableListOf<ValorJson>()
        val m = compras(TransporteProgramado { _, c -> cuerpos += c; 200 to comprasJson }, raiz)
        assertNull(m.compras.value)
        m.refrescar()
        assertEquals(token, cuerpos.single()["p_token"]?.comoTexto)
        val o = Compras.opcionesDe(" Creatina ", m.compras.value)
        assertEquals(listOf("https://tienda-ejemplo.invalid/c", null), o.map { it.url })
        // Sin red: la copia.
        val sinRed = ModeloCompras(ClienteRpc(transporte = SinRed), token, Disco(raiz, token))
        assertEquals(m.compras.value, sinRed.compras.value)
        sinRed.refrescar()
        assertEquals(m.compras.value, sinRed.compras.value)
        // Con la palanca apagada, ni la copia.
        sinRed.usarPalanca(false)
        assertNull(sinRed.compras.value)
        assertNull(ModeloCompras(ClienteRpc(transporte = SinRed), token, Disco(raiz, token)).compras.value)
    }

    @Test fun comprasLoQueNoSeVe(): Unit = runBlocking {
        for (r in listOf(200 to "null", 200 to """{"habilitado":false}""", 404 to """{"code":"PGRST202","message":"no existe"}""", 404 to "")) {
            var respuesta = 200 to comprasJson
            val raiz = carpetaTemporal("compras-x")
            val m = compras(TransporteProgramado { _, _ -> respuesta }, raiz)
            m.refrescar()
            assertNotNull(m.compras.value)
            respuesta = r
            m.refrescar()
            assertNull(m.compras.value, "$r")
            assertNull(Disco(raiz, token).leer(ModeloCompras.ARCHIVO), "$r")
        }
        // Sin dato verificado: una respuesta válida y vacía (no hay botón ni cartel).
        val vacio = compras(TransporteProgramado { _, _ -> 200 to """{"habilitado":true,"items":[]}""" }, carpetaTemporal("compras-v"))
        vacio.refrescar()
        assertTrue(vacio.compras.value!!.vacio)
        // Un error del servidor deja lo que había.
        var respuesta = 200 to comprasJson
        val m = compras(TransporteProgramado { _, _ -> respuesta }, carpetaTemporal("compras-e"))
        m.refrescar()
        respuesta = 500 to ""
        m.refrescar()
        assertFalse(m.compras.value!!.vacio)
    }

    // ---------------------------------------------------------------- Casa

    private class Cuenta(val d: DobleGimnasio, val gimnasio: ModeloGimnasio, val casa: ModeloCasa) {
        suspend fun refrescar() {
            gimnasio.refrescar()
            casa.refrescar()
        }
    }

    private fun cuenta(d: DobleGimnasio, raiz: File = carpetaTemporal("casa")): Cuenta {
        val c = ClienteRpc(transporte = d)
        val disco = Disco(raiz, token)
        val g = ModeloGimnasio(c, token, disco, esperar = {})
        return Cuenta(d, g, ModeloCasa(c, token, disco, g).also { it.usarPalanca(true) })
    }

    @Test fun casaPrenderMarcarYEnviar(): Unit = runBlocking {
        val x = cuenta(DobleGimnasio.escenario("casaConGimnasioVigente"))
        x.refrescar()
        assertEquals(Casa.Interruptor(prendido = false, sePuedeMover = true), x.casa.interruptor)
        assertEquals(Casa.Pantalla.GIMNASIO, x.casa.pantalla)
        assertEquals(5, x.casa.estado.value!!.tipos.size)

        assertEquals(ModeloCasa.Salida.OK, x.casa.mover(true))
        assertNull(x.casa.moviendoA.value)
        assertEquals(Casa.Interruptor(prendido = true, sePuedeMover = true), x.casa.interruptor)
        assertEquals(Casa.Pantalla.LISTA, x.casa.pantalla)
        // Los dos se refrescaron: el gimnasio también ve la carga abierta.
        assertEquals("borrador", x.gimnasio.abierta?.estado)

        assertFalse(x.casa.puedeEnviar)
        assertEquals(ModeloCasa.Salida.ERROR, x.casa.enviar())
        assertEquals(ModeloCasa.Aviso.SIN_DATOS, x.casa.aviso.value)
        x.casa.marcarSinEquipo(true)
        assertTrue(x.casa.puedeEnviar)
        // Marcar un equipo desmarca «No tengo nada de esto», y al revés.
        x.casa.marcar("banco_plano", true)
        x.casa.marcar("mancuernas", true)
        x.casa.marcar("maquina_inventada", true)
        assertFalse(x.casa.borrador.value.sinEquipo)
        assertEquals(listOf("mancuernas", "banco_plano"), x.casa.borrador.value.marcados)
        x.casa.marcarSinEquipo(true)
        assertTrue(x.casa.borrador.value.marcados.isEmpty())
        x.casa.marcar("mancuernas", true)
        x.casa.marcar("banco_plano", true)
        x.casa.fijarKilos("mancuernas", "22,5")
        x.casa.fijarKilos("mancuernas", "999")   // no entra: queda lo anterior
        x.casa.fijarKilos("banco_plano", "40")   // no lleva kilos: no viaja
        x.casa.fijarNota("  Tengo poco lugar  " + "x".repeat(400))
        assertEquals(300, x.casa.borrador.value.nota.length)
        assertNull(x.casa.aviso.value)

        assertEquals(ModeloCasa.Salida.OK, x.casa.enviar())
        val e = x.d.ultimoEnviarCasa!!
        assertEquals(token, e["p_token"]?.comoTexto)
        assertEquals(x.gimnasio.abierta?.id, e["p_id"]?.comoTexto)
        assertEquals(ValorJson.parsear("""[{"tipo":"mancuernas","kg":22.5},{"tipo":"banco_plano"}]"""), e["p_equipos"])
        assertEquals(ValorJson.Booleano(false), e["p_sin_equipo"])
        assertFalse(e.serializar().contains("cliente_id"))
        // Queda en `a_revisar`: la pantalla «Recibido» de siempre, y el interruptor fijo.
        assertEquals(Casa.Pantalla.GIMNASIO, x.casa.pantalla)
        assertEquals(Gimnasio.Pantalla.RECIBIDO, x.gimnasio.pantalla)
        assertEquals(Casa.Interruptor(prendido = true, sePuedeMover = false), x.casa.interruptor)
        assertEquals(ModeloCasa.Salida.OK, x.casa.mover(false))
        assertEquals(1, x.d.llamadas.count { it == "mypump_casa_elegir" })
        assertTrue(x.casa.borrador.value.marcados.isEmpty())

        // Mati la aprueba: es la vigente de casa.
        x.d.aprobarCasa()
        x.refrescar()
        assertEquals(Casa.Pantalla.VIGENTE, x.casa.pantalla)
        assertEquals(listOf("Mancuernas, hasta 22,5 kg", "Banco plano"), x.casa.estado.value!!.let { s -> s.vigente!!.equipos.map { Casa.renglonVigente(it, s.tipos) } })
        // «Cambió lo que tengo en casa» abre otra carga de casa.
        assertEquals(ModeloCasa.Salida.OK, x.casa.cambiar())
        assertEquals(Casa.Pantalla.LISTA, x.casa.pantalla)
    }

    @Test fun casaSinEquipoViajaSinEquipos(): Unit = runBlocking {
        val x = cuenta(DobleGimnasio.escenario("casaBorrador"))
        x.refrescar()
        x.casa.marcarSinEquipo(true)
        assertEquals(ModeloCasa.Salida.OK, x.casa.enviar())
        assertEquals(ValorJson.Lista(emptyList()), x.d.ultimoEnviarCasa!!["p_equipos"])
        assertEquals(ValorJson.Booleano(true), x.d.ultimoEnviarCasa!!["p_sin_equipo"])
    }

    @Test fun casaApagarElInterruptor(): Unit = runBlocking {
        // Con un borrador de casa: el borrador vuelve a ser de gimnasio (`elegir(false)`), no se abre otra carga.
        val b = cuenta(DobleGimnasio.escenario("casaBorrador"))
        b.refrescar()
        assertEquals(Casa.Pantalla.LISTA, b.casa.pantalla)
        assertEquals(ModeloCasa.Salida.OK, b.casa.mover(false))
        assertEquals(Casa.Interruptor(prendido = false, sePuedeMover = true), b.casa.interruptor)
        assertEquals(Casa.Pantalla.GIMNASIO, b.casa.pantalla)
        assertEquals(Gimnasio.Pantalla.ZONAS, b.gimnasio.pantalla)
        assertFalse("mypump_gimnasio_nuevo" in b.d.llamadas)

        // Sin borrador y con casa vigente: la carga de gimnasio de siempre, completa.
        val v = cuenta(DobleGimnasio.escenario("casaVigente"))
        v.refrescar()
        assertEquals(Casa.Interruptor(prendido = true, sePuedeMover = true), v.casa.interruptor)
        assertEquals(ModeloCasa.Salida.OK, v.casa.mover(false))
        assertTrue("mypump_gimnasio_nuevo" in v.d.llamadas)
        assertFalse("mypump_casa_elegir" in v.d.llamadas)
        assertEquals("completa", v.d.abierta?.get("modo")?.comoTexto)
        assertEquals(Casa.Interruptor(prendido = false, sePuedeMover = true), v.casa.interruptor)
        assertEquals(Gimnasio.Pantalla.ZONAS, v.gimnasio.pantalla)
        // Mover a donde ya está no llama a nada.
        val antes = v.d.llamadas.size
        assertEquals(ModeloCasa.Salida.OK, v.casa.mover(false))
        assertEquals(antes, v.d.llamadas.size)
    }

    @Test fun casaSiElegirFallaElInterruptorVuelveYAvisa(): Unit = runBlocking {
        val x = cuenta(DobleGimnasio.escenario("casaVacio"))
        x.refrescar()
        for (falla in listOf("red", "nulo", "error_nuevo")) {
            x.d.proximosElegir.add(falla)
            assertEquals(ModeloCasa.Salida.ERROR, x.casa.mover(true), falla)
            assertEquals(ModeloCasa.Aviso.NO_SE_PUDO_CAMBIAR, x.casa.aviso.value, falla)
            assertEquals(false, x.casa.interruptor?.prendido, falla)
            assertNull(x.casa.moviendoA.value, falla)
        }
        // `reintentar`: una vez más, sola.
        x.d.proximosElegir.add("reintentar")
        assertEquals(ModeloCasa.Salida.OK, x.casa.mover(true))
        assertNull(x.casa.aviso.value)
        assertEquals(true, x.casa.interruptor?.prendido)
        // Dos `reintentar` seguidos: no insiste más.
        val y = cuenta(DobleGimnasio.escenario("casaVacio"))
        y.refrescar()
        y.d.proximosElegir.addAll(listOf("reintentar", "reintentar"))
        assertEquals(ModeloCasa.Salida.ERROR, y.casa.mover(true))
        assertEquals(2, y.d.llamadas.count { it == "mypump_casa_elegir" })
        // `no_habilitado`: el interruptor se esconde.
        val z = cuenta(DobleGimnasio.escenario("casaVacio"))
        z.refrescar()
        z.d.proximosElegir.add("no_habilitado")
        z.d.casaHabilitada = false
        assertEquals(ModeloCasa.Salida.ERROR, z.casa.mover(true))
        assertNull(z.casa.estado.value)
        assertNull(z.casa.aviso.value)
        // `en_curso`: no es un error del alumno; al refrescar queda fijo.
        val w = cuenta(DobleGimnasio.escenario("casaVacio"))
        w.refrescar()
        w.d.abierta = linkedMapOf("id" to ValorJson.Texto("otra"), "estado" to ValorJson.Texto("enviado"), "modo" to ValorJson.Texto("completa"))
        assertEquals(ModeloCasa.Salida.OK, w.casa.mover(true))
        assertEquals(Casa.Interruptor(prendido = false, sePuedeMover = false), w.casa.interruptor)
        assertNull(w.casa.aviso.value)
    }

    @Test fun casaErroresAlEnviar(): Unit = runBlocking {
        fun preparado(): Cuenta = cuenta(DobleGimnasio.escenario("casaBorrador")).also { x ->
            runBlocking { x.refrescar() }
            x.casa.marcar("mancuernas", true)
        }
        for (falla in listOf("red", "nulo", "contradiccion", "error_nuevo")) {
            val x = preparado()
            x.d.proximosEnviarCasa.add(falla)
            assertEquals(ModeloCasa.Salida.ERROR, x.casa.enviar(), falla)
            assertEquals(ModeloCasa.Aviso.NO_SE_PUDO_ENVIAR, x.casa.aviso.value, falla)
            assertFalse(x.casa.enviando.value)
            // Lo marcado sigue ahí, y reintentar sale.
            assertEquals(listOf("mancuernas"), x.casa.borrador.value.marcados, falla)
            assertEquals(ModeloCasa.Salida.OK, x.casa.enviar(), falla)
        }
        val sinDatos = preparado()
        sinDatos.d.proximosEnviarCasa.add("sin_datos")
        assertEquals(ModeloCasa.Salida.ERROR, sinDatos.casa.enviar())
        assertEquals(ModeloCasa.Aviso.SIN_DATOS, sinDatos.casa.aviso.value)
        // `no_encontrado`: se refresca (acá, la carga ya no es un borrador de casa).
        val otro = preparado()
        otro.d.proximosEnviarCasa.add("no_encontrado")
        otro.d.abierta = null
        assertEquals(ModeloCasa.Salida.ERROR, otro.casa.enviar())
        assertEquals(Casa.Pantalla.GIMNASIO, otro.casa.pantalla)
        assertNull(otro.casa.aviso.value)
        // Ya enviada (un reintento tras un corte): `ya`, y sigue.
        val ya = preparado()
        ya.d.abierta!!["estado"] = ValorJson.Texto("a_revisar")
        assertEquals(ModeloCasa.Salida.OK, ya.casa.enviar())
        assertEquals(Gimnasio.Pantalla.RECIBIDO, ya.gimnasio.pantalla)
    }

    @Test fun casaLoMarcadoQuedaEnDiscoYSinRedSeSigueMarcando(): Unit = runBlocking {
        val raiz = carpetaTemporal("casa-disco")
        val d = DobleGimnasio.escenario("casaBorrador")
        val x = cuenta(d, raiz)
        x.refrescar()
        x.casa.marcar("discos", true)
        x.casa.fijarKilos("discos", "60")
        x.casa.fijarNota("Tengo una barra corta")
        d.sinRed = true
        val otra = cuenta(d, raiz)
        assertEquals(listOf("discos"), otra.casa.borrador.value.marcados)
        assertNull(otra.casa.estado.value)
        otra.refrescar()
        // Sin señal solo se sigue un borrador de casa.
        assertEquals(Casa.Pantalla.LISTA, otra.casa.pantalla)
        assertEquals("60", otra.casa.borrador.value.kilos["discos"])
        assertEquals(ModeloCasa.Salida.ERROR, otra.casa.enviar())
        assertEquals(ModeloCasa.Aviso.NO_SE_PUDO_ENVIAR, otra.casa.aviso.value)
        // Una vigente de casa, sin señal al abrir, no se muestra (como el gimnasio).
        val v = DobleGimnasio.escenario("casaVigente")
        val raizV = carpetaTemporal("casa-disco-v")
        cuenta(v, raizV).refrescar()
        v.sinRed = true
        val sinRed = cuenta(v, raizV)
        sinRed.refrescar()
        assertNull(sinRed.casa.estado.value)
    }

    @Test fun casaLoQueNoSeVe(): Unit = runBlocking {
        val noHabilitada = cuenta(DobleGimnasio.escenario("casaBorrador").also { it.casaHabilitada = false })
        noHabilitada.refrescar()
        assertNull(noHabilitada.casa.estado.value)
        assertNull(noHabilitada.casa.interruptor)
        assertEquals(Casa.Pantalla.GIMNASIO, noHabilitada.casa.pantalla)
        val sinFuncion = cuenta(DobleGimnasio.escenario("casaBorrador").also { it.sinFuncionCasa = true })
        sinFuncion.refrescar()
        assertNull(sinFuncion.casa.estado.value)
        // El gimnasio sigue como siempre.
        assertNotNull(sinFuncion.gimnasio.estado.value)
        val tokenCaido = ModeloCasa(ClienteRpc(transporte = TransporteProgramado { _, _ -> 200 to "null" }), token, null, noHabilitada.gimnasio)
        tokenCaido.refrescar()
        assertNull(tokenCaido.estado.value)
        assertEquals(ModeloCasa.Salida.ERROR, tokenCaido.mover(true))
        assertEquals(ModeloCasa.Salida.ERROR, tokenCaido.enviar())
    }

    // ---------------------------------------------------------------- La carga entera, con las palancas

    private val filaSupl = """[{"suplementacion":{"items":[{"nombre":"Creatina","momento":"desayuno"}]},"esquema":1}]"""

    private fun app(config: String, raiz: File, alcance: CoroutineScope, suplementacion: String = filaSupl, registro: MutableList<String>): ModeloApp {
        val t = TransporteProgramado { fn, _ ->
            synchronized(registro) { registro += fn }
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente de prueba","perfil":"natural"}]"""
                "mypump_get_app_config" -> if (config == "CORTE") 503 to "" else 200 to config
                "mypump_suplementacion" -> 200 to suplementacion
                "mypump_fin_plan_get" -> 200 to recorrido()
                "mypump_compras_get" -> 200 to comprasJson
                "mypump_gimnasio_get" -> 200 to """{"habilitado":true,"abierta":null,"vigente":null}"""
                "mypump_casa_get" -> 200 to """{"habilitado":true,"tipos":[{"tipo":"mancuernas","nombre":"Mancuernas","kg":true}],"abierta":null,"vigente":null}"""
                else -> 200 to "[]"
            }
        }
        return ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raiz, PreferenciasEnMemoria(), alcance)
    }

    private suspend fun ModeloApp.asentar() {
        suplementacion.value?.alDia()
        kotlinx.coroutines.yield()
    }

    /** Sin la clave, con `false` o con algo que no es `true`: no se llama a ningún RPC nuevo ni queda nada a la vista. */
    @Test fun conLasPalancasApagadasNoSeLlamaANadaNuevo() = enUnHilo { alcance ->
        for (config in listOf(
            "{}", """{"fin_plan":false,"compras_pais":false,"casa":false}""", """{"fin_plan":"true","compras_pais":1,"casa":"si","gimnasio_fotos":true}""",
            """{"novedades_plan":true,"gimnasio_fotos":true,"tecnica_video":true}""",
        )) {
            val registro = java.util.concurrent.CopyOnWriteArrayList<String>()
            val m = app(config, carpetaTemporal("colab-off"), alcance, registro = registro)
            m.cargar()
            m.asentar()
            m.alVolverAPrimerPlano()
            m.asentar()
            kotlinx.coroutines.delay(50)
            assertEquals(emptyList<String>(), registro.deLaColaB(), config)
            assertNull(m.finPlan.value?.recorrido?.value, config)
            assertNull(m.compras.value?.compras?.value, config)
            assertNull(m.casa.value?.estado?.value, config)
        }
    }

    @Test fun conLasPalancasPrendidasSeConsultaAlCargarYAlVolver() = enUnHilo { alcance ->
        val registro = java.util.concurrent.CopyOnWriteArrayList<String>()
        val raiz = carpetaTemporal("colab-on")
        val m = app("""{"fin_plan":true,"compras_pais":true,"casa":true,"gimnasio_fotos":true}""", raiz, alcance, registro = registro)
        m.cargar()
        m.asentar()
        assertEquals(setOf("mypump_fin_plan_get", "mypump_compras_get", "mypump_casa_get"), registro.deLaColaB().toSet())
        assertEquals(1, registro.count { it == "mypump_fin_plan_get" })
        assertEquals(1, registro.count { it == "mypump_compras_get" })
        // Una sola consulta de suplementación al cargar.
        assertEquals(1, registro.count { it == "mypump_suplementacion" })
        assertEquals(Recorrido.Estado.PUBLICADO, m.finPlan.value?.recorrido?.value?.estado)
        assertFalse(m.compras.value?.compras?.value?.vacio ?: true)
        assertNotNull(m.casa.value?.estado?.value)
        m.alVolverAPrimerPlano()
        m.asentar()
        kotlinx.coroutines.delay(50)
        assertEquals(2, registro.count { it == "mypump_fin_plan_get" })
        // Las compras van con la suplementación, que al volver no se relee antes de su intervalo (arreglos F11): sigue en 1.
        assertEquals(1, registro.count { it == "mypump_compras_get" })
        assertEquals(1, registro.count { it == "mypump_casa_get" })   // va con el gimnasio, que tampoco se relee antes de su intervalo

        // Se apagan: la carga siguiente no llama a nada nuevo y deja de verse todo, también lo guardado.
        // Con su propio registro: lo que la primera todavía tenga en vuelo no cuenta acá.
        val registroApagada = java.util.concurrent.CopyOnWriteArrayList<String>()
        val apagada = app("{}", raiz, alcance, registro = registroApagada)
        apagada.cargar()
        apagada.asentar()
        assertEquals(emptyList<String>(), registroApagada.deLaColaB())
        assertNull(apagada.finPlan.value?.recorrido?.value)
        assertNull(apagada.compras.value?.compras?.value)
        assertNull(apagada.casa.value?.estado?.value)
    }

    /** `casa` necesita `gimnasio_fotos`; compras, que haya suplementación. */
    @Test fun casaNecesitaElGimnasioYComprasLaSuplementacion() = enUnHilo { alcance ->
        val registro = java.util.concurrent.CopyOnWriteArrayList<String>()
        val m = app("""{"compras_pais":true,"casa":true}""", carpetaTemporal("colab-dep"), alcance, suplementacion = "[]", registro = registro)
        m.cargar()
        m.asentar()
        m.alVolverAPrimerPlano()
        m.asentar()
        kotlinx.coroutines.delay(50)
        assertEquals(emptyList<String>(), registro.deLaColaB())
    }

    /** Si la palanca no se pudo leer (un corte), vale la última que se supo: lo que se veía se sigue viendo. */
    @Test fun sinPoderLeerLaPalancaValeLaUltima() = enUnHilo { alcance ->
        val raiz = carpetaTemporal("colab-corte")
        val registro = java.util.concurrent.CopyOnWriteArrayList<String>()
        app("""{"fin_plan":true}""", raiz, alcance, registro = registro).also { it.cargar(); it.asentar() }
        registro.clear()
        val m = app("CORTE", raiz, alcance, registro = registro)
        // Antes de cargar ya se ve la copia.
        m.cargar()
        m.asentar()
        assertEquals(listOf("mypump_fin_plan_get"), registro.deLaColaB())
        assertNotNull(m.finPlan.value?.recorrido?.value)
        // Y una cuenta que nunca la tuvo prendida, con el mismo corte, no llama a nada.
        registro.clear()
        val nueva = app("CORTE", carpetaTemporal("colab-corte-2"), alcance, registro = registro)
        nueva.cargar()
        nueva.asentar()
        assertEquals(emptyList<String>(), registro.deLaColaB())
    }

    @Test fun lasPalancasSeLeenDeSusClaves() {
        val p = PalancaRemota.desde(ValorJson.parsear("""{"fin_plan":true,"compras_pais":true,"casa":true}"""))
        assertTrue(p.finPlan && p.comprasPais && p.casa)
        val f = PalancaRemota.deFabrica
        assertFalse(f.finPlan || f.comprasPais || f.casa)
        val rara = PalancaRemota.desde(ValorJson.parsear("""{"fin_plan":"true","compras_pais":1,"casa":null}"""))
        assertFalse(rara.finPlan || rara.comprasPais || rara.casa)
    }
}
