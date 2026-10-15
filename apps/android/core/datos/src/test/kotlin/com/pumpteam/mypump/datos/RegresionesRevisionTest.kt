package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.ValueSource

private const val TOK_A = "AAAAAAAAAAAAAAAAAAAA"
private const val TOK_B = "BBBBBBBBBBBBBBBBBBBB"
private const val INFO = """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""

/**
 * Regresiones de la revisión adversarial del 14-oct (RegresionesRevisionTests.swift): cada test reproduce una falla real
 * que se encontró en el código de iOS (carreras de token, cola trabada, plan que desaparecía, demo que escribía, badge
 * del chat…). Tienen que pasar siempre.
 */
class RegresionesRevisionTest {
    private val raiz = carpetaTemporal("verif")

    private fun modelo(t: Transporte, almacen: AlmacenToken, alcance: CoroutineScope, prefs: Preferencias = PreferenciasEnMemoria()) =
        ModeloApp(ClienteRpc(transporte = t), almacen, raiz, prefs, alcance)

    // 1. Arranque en frío por un link nuevo mientras carga la cuenta vieja (revocada).
    @Test
    fun carreraArranqueConLinkNuevo() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, cuerpo ->
            val tok = cuerpo["p_token"]?.comoTexto
            when {
                fn != "mypump_get_cliente_info" -> 200 to "[]"
                tok == TOK_A -> {
                    delay(150)
                    200 to "[]"
                }
                else -> {
                    delay(30)
                    200 to INFO
                }
            }
        }
        val almacen = TokenEnMemoria(TOK_A)
        val m = modelo(t, almacen, alcance)
        val a = async { m.cargar() }
        delay(5)
        val b = async { m.entrar("https://app.mypumpteam.com/?t=$TOK_B") }
        a.await()
        assertTrue(b.await())
        assertEquals(TOK_B, almacen.leer())
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
    }

    // 2. resolverSesion: sin rutina activa (iniciar_sesion → null) la cola se congelaba y lo de atrás no salía nunca.
    @Test
    fun colaCongeladaPorSesionNula() = runBlocking {
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_sesion_dia" -> 200 to "[]"
                "mypump_iniciar_sesion" -> 200 to "null"
                "mypump_set_habito" -> 200 to """[{"fecha":"2026-10-14","vasos_agua":3}]"""
                "mypump_get_cliente_info" -> 200 to INFO   // el token anda: es "sin rutina activa", no un token caído
                else -> 200 to "[]"
            }
        }
        val alcance = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val esc = Escrituras(ClienteRpc(transporte = t), TOK_A)
            val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
            o.encolar(
                "carga",
                ValorJson.objeto(
                    "diaId" to texto("d1"), "semana" to numero(1),
                    "datos" to ValorJson.objeto("diaId" to texto("d1"), "ejercicioId" to texto("x-d1-0"), "serie" to numero(1)),
                ),
                "carga_d1_x_0",
            )
            o.encolar("habito", ValorJson.objeto("fecha" to texto("2026-10-14"), "campo" to texto("vasos_agua"), "valor" to texto("3")), "habito|2026-10-14|vasos_agua")
            repeat(20) { o.drenar() }
            assertTrue("mypump_set_habito" in t.llamadas)
            // La carga sin sesión gasta intentos como un rechazo (y al octavo va a fallidos): no congela la cola.
            assertEquals(1, o.fallidos().size)
            assertEquals(0, o.pendientes())
        } finally {
            alcance.cancel()
        }
    }

    // 3. Demo después de "Este link ya no sirve": no escribe nada.
    @Test
    fun demoConTokenVencidoNoEscribe() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to "[]"
                "mypump_save_food_swap" -> 400 to """{"code":"22P02","message":"invalid input syntax for type uuid: \"demo\""}"""
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, TokenEnMemoria(TOK_A), alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.TOKEN_INVALIDO, m.fase.value)
        m.entrarEnDemo(Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"))
        val c = m.comidasDelDia.first()
        val a = c.opciones.first().alimentos.first()
        m.sustituir(
            a,
            ValorJson.objeto(
                "name" to texto("Ricota"), "qty" to numero(100), "unit" to texto("g"), "kcal" to numero(138),
                "prot" to numero(11), "carb" to numero(4), "fat" to numero(9),
            ),
            c.id, 0, 0,
        )
        delay(300)
        val alimento = m.crearAlimentoPropio(AlimentoPropioNuevo.Datos("X", 100.0, 1.0, 1.0, 1.0, "g", null, ""))
        assertTrue(alimento is Resultado.Ok)
        assertFalse("mypump_save_food_swap" in t.llamadas)
        assertFalse("mypump_create_custom_food" in t.llamadas)
    }

    // 4. Se cae solo la dieta (red) con la info bien: no se pierde de la pantalla ni de la copia offline.
    @Test
    fun fallaParcialNoPisaLaCopiaOffline() = enUnHilo { alcance ->
        val caeDieta = AtomicBoolean(false)
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to INFO
                "mypump_get_rutina_activa" -> 200 to Compartido.muestra("get_rutina_activa")
                "mypump_get_dieta_activa" -> if (caeDieta.get()) throw IOException("timeout") else 200 to Compartido.muestra("get_dieta_activa")
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, TokenEnMemoria(TOK_A), alcance)
        m.cargar()
        assertNotNull(m.dieta.value)
        caeDieta.set(true)
        m.cargar()   // "tirar para actualizar" con la señal del gym
        val copia = ModeloApp.CopiaOffline.desde(Disco(raiz, TOK_A).leer(ModeloApp.ARCHIVO_COPIA))
        assertNotNull(m.dieta.value)
        assertNotNull(copia?.dieta)
        assertTrue(m.desdeCache.value)
        assertEquals(setOf(ModeloApp.Parte.DIETA), m.sinRedEn.value)
    }

    // 4b. Se cae la RUTINA (o las dos) con la info bien: la web usa la copia; la nativa también.
    @ParameterizedTest
    @ValueSource(booleans = [false, true])
    fun fallaRutinaNoPisaLaCopia(tambienDieta: Boolean) = enUnHilo { alcance ->
        val cae = AtomicBoolean(false)
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to INFO
                "mypump_get_rutina_activa" -> if (cae.get()) throw IOException("timeout") else 200 to Compartido.muestra("get_rutina_activa")
                "mypump_get_dieta_activa" ->
                    if (tambienDieta && cae.get()) throw IOException("timeout") else 200 to Compartido.muestra("get_dieta_activa")
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, TokenEnMemoria(TOK_A), alcance)
        m.cargar()
        cae.set(true)
        m.cargar()
        val copia = ModeloApp.CopiaOffline.desde(Disco(raiz, TOK_A).leer(ModeloApp.ARCHIVO_COPIA))
        assertNotNull(m.rutina.value)
        assertNotNull(m.dieta.value)
        assertNotNull(copia?.rutina)
        assertNotNull(copia?.dieta)
    }

    // 5. Token revocado: las ops se estacionan (arreglo nativo n.º 3), no se abandonan.
    @Test
    fun tokenRevocadoEstaciona() = runBlocking {
        val t = TransporteProgramado { _, _ -> 200 to "null" }
        val alcance = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        try {
            val esc = Escrituras(ClienteRpc(transporte = t), TOK_A)
            val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
            o.encolar("habito", ValorJson.objeto("fecha" to texto("2026-10-14"), "campo" to texto("durmio_bien"), "valor" to texto("true")), "habito|2026-10-14|durmio_bien")
            o.encolar("peso", ValorJson.objeto("fecha" to texto("2026-10-14"), "valor" to numero(80)), "peso_2026-10-14")
            o.encolar("chat", ValorJson.objeto("contenido" to texto("hola")), "chat_1_hola")
            repeat(10) { o.drenar() }
            assertEquals(3, o.pendientes())
            assertTrue(o.operaciones().all { it.tries == 0 })
            assertTrue("mypump_get_cliente_info" in t.llamadas)
            // Y lo pregunta una vez por minuto como mucho, no en cada pasada.
            assertEquals(1, t.llamadas.count { it == "mypump_get_cliente_info" })
        } finally {
            alcance.cancel()
        }
    }

    // 7. Una op encolada durante una pasada sale sola (sin otro disparador).
    @Test
    fun encoladoDuranteLaPasadaSale() = runBlocking {
        var atascadas = 0
        repeat(60) {
            val alcance = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            try {
                val o = Outbox(archivo = null, reintentoAutomatico = true, alcance = alcance) {
                    delay(3)
                    ResultadoOp.Respuesta(Resultado.Ok(texto("id")))
                }
                o.encolar("x", ValorJson.Nulo, "a")
                delay(1)
                o.encolar("x", ValorJson.Nulo, "b")
                delay(120)
                if (o.pendientes() > 0) {
                    delay(2_000)
                    if (o.pendientes() > 0) atascadas += 1
                }
            } finally {
                alcance.cancel()
            }
        }
        assertEquals(0, atascadas)
    }

    // 8. Arranque en frío tocando un link VIEJO (ya marcado inválido) con una cuenta buena guardada (ACC-02).
    @Test
    fun linkViejoEnArranqueEnFrio() = enUnHilo { alcance ->
        val viejo = "VVVVVVVVVVVVVVVVVVVV"
        val prefs = PreferenciasEnMemoria().apply { guardar(ModeloApp.CLAVE_TOKEN_INVALIDO, viejo) }
        val t = TransporteProgramado { fn, cuerpo ->
            if (fn == "mypump_get_cliente_info") {
                delay(60)
                if (cuerpo["p_token"]?.comoTexto == viejo) 200 to "[]" else 200 to INFO
            } else {
                200 to "[]"
            }
        }
        val almacen = TokenEnMemoria(TOK_A)
        val m = modelo(t, almacen, alcance, prefs)
        val a = async { m.cargar() }   // al crear la Activity
        delay(5)
        val b = async { m.entrar("https://app.mypumpteam.com/?t=$viejo") }   // el intent del link
        a.await()
        assertFalse(b.await())
        assertEquals(TOK_A, almacen.leer())
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
    }

    // 9. Reemplazar mientras hidrata (antes de leer los swaps del disco) pisaba el archivo local.
    @Test
    fun reemplazarDuranteLaHidratacionNoPisaLosSwapsLocales() = enUnHilo { alcance ->
        val dietaId = "15a9a59f-9b90-4e42-b6a4-07b1e4bb4a7f"
        val disco = Disco(raiz, TOK_A)
        fun sw(n: String) = ValorJson.objeto("current" to ValorJson.objeto("name" to texto(n), "qty" to numero(100), "unit" to texto("g")))
        disco.guardar("swaps_$dietaId.json", ValorJson.objeto("swap_${dietaId}_c1_0_1" to sw("Ricota"), "swap_${dietaId}_c2_0_1" to sw("Fideos")))
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to INFO
                "mypump_get_rutina_activa" -> 200 to Compartido.muestra("get_rutina_activa")
                "mypump_get_dieta_activa" -> 200 to Compartido.muestra("get_dieta_activa")
                "mypump_get_cliente_prefs" -> {
                    delay(300)
                    200 to "[]"
                }
                "mypump_get_food_swaps" -> throw IOException("timeout")
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, TokenEnMemoria(TOK_A), alcance)
        val carga = async { m.cargar() }
        var listoSinSwaps = true
        for (i in 0 until 50) {
            if (m.fase.value == ModeloApp.Fase.LISTO) {
                listoSinSwaps = m.swaps.value.isEmpty()
                break
            }
            delay(5)
        }
        assertEquals(dietaId, m.dieta.value?.id)
        assertFalse(listoSinSwaps)
        val c = m.comidasDelDia.first()
        val a = c.opciones.first().alimentos.first()
        m.sustituir(a, ValorJson.objeto("name" to texto("Tofu"), "qty" to numero(100), "unit" to texto("g")), c.id, 0, 0)
        carga.await()
        val enDisco = disco.leer("swaps_$dietaId.json") as JsonObject
        assertEquals(3, enDisco.size)
        assertEquals(3, m.swaps.value.size)
    }

    // 9b. Volver al plan mientras una recarga esperaba los swaps del servidor: si el borrado salía antes de que la respuesta
    // llegara, la respuesta vieja resucitaba el reemplazo hasta la próxima carga (15-oct: DietaEscrituraUiTest
    // .reemplazarUnAlimentoYVolverAlDelPlan fallaba de a ratos).
    @Test
    fun volverAlPlanMientrasHidrataNoLoResucita() = enUnHilo { alcance ->
        val enServidor = HashMap<String, ValorJson>()
        var pedidosDeSwaps = 0
        val pidio = CompletableDeferred<Unit>()
        val puerta = CompletableDeferred<Unit>()
        fun clave(p: ValorJson) =
            "${p["p_comida_id"]?.comoTexto}/${(p["p_opt_idx"]?.comoNumero ?: 0.0).toInt()}/${(p["p_food_idx"]?.comoNumero ?: 0.0).toInt()}"
        val t = TransporteProgramado { fn, cuerpo ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to INFO
                "mypump_get_rutina_activa" -> 200 to Compartido.muestra("get_rutina_activa")
                "mypump_get_dieta_activa" -> 200 to Compartido.muestra("get_dieta_activa")
                "mypump_get_food_swaps" -> {
                    // La foto se saca antes de esperar: es la respuesta vieja.
                    val foto = ValorJson.Lista(
                        enServidor.map { (k, v) ->
                            val q = k.split("/")
                            ValorJson.objeto("comida_id" to texto(q[0]), "opt_idx" to numero(q[1].toDouble()), "food_idx" to numero(q[2].toDouble()), "food_data" to v)
                        },
                    ).serializar()
                    pedidosDeSwaps += 1
                    if (pedidosDeSwaps == 2) {
                        pidio.complete(Unit)
                        puerta.await()
                    }
                    200 to foto
                }
                "mypump_save_food_swap" -> {
                    enServidor[clave(cuerpo)] = cuerpo["p_food_data"] ?: ValorJson.Nulo
                    200 to """[{"ok":true}]"""
                }
                "mypump_delete_food_swap" -> 200 to (if (enServidor.remove(clave(cuerpo)) == null) "false" else "true")
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, TokenEnMemoria(TOK_A), alcance)
        m.cargar()
        val c = m.comidasDelDia.first()
        val a = c.opciones.first().alimentos.first()
        m.sustituir(a, ValorJson.objeto("name" to texto("Tofu"), "qty" to numero(100), "unit" to texto("g")), c.id, 0, 0)
        m.outbox?.drenar()
        val k = m.clave(c.id, 0, 0)
        assertTrue(k in m.swaps.value)
        assertEquals(1, enServidor.size)

        val recarga = async { m.hidratarDieta() }
        withTimeout(5_000) { pidio.await() }
        m.revertir(c.id, 0, 0)
        m.outbox?.drenar()
        assertTrue(enServidor.isEmpty())
        puerta.complete(Unit)
        recarga.await()
        assertFalse(k in m.swaps.value, "la respuesta vieja resucitó el reemplazo")
    }

    // 10. El badge del chat: lo que llegó por el sondeo (sin campo de leído) se perdía al recargar.
    @Test
    fun badgeDelChatNoSePierdeAlRecargar() = enUnHilo { alcance ->
        val paso = AtomicBoolean(false)
        val m1 = """{"id":"m1","autor":"coach","contenido":"hola","leido_por_cliente":true,"created_at":"2026-10-14T10:00:00.123456+00:00"}"""
        val m2nuevo = """{"id":"m2","autor":"coach","contenido":"¿cómo venís?","created_at":"2026-10-14T11:00:00.123456+00:00"}"""
        val m2 = """{"id":"m2","autor":"coach","contenido":"¿cómo venís?","leido_por_cliente":false,"created_at":"2026-10-14T11:00:00.123456+00:00"}"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_chat" -> 200 to (if (paso.get()) "[$m2,$m1]" else "[$m1]")
                "mypump_chat_nuevos" -> 200 to "[$m2nuevo]"
                else -> 200 to "[]"
            }
        }
        val chat = ModeloChat(ClienteRpc(transporte = t), TOK_A, null, alcance)
        chat.cargar()
        chat.sondear()
        assertEquals(1, chat.noLeidos.value)
        paso.set(true)
        chat.cargar()   // ModeloApp.cargar() → chat.cargar() (tirar para actualizar, volver con copia offline)
        assertEquals(1, chat.noLeidos.value)
    }

    // 10b. Una fila que vuelve sin el campo de leído (o una página que no la trae) tampoco baja el badge: solo lo baja
    // marcarLeido.
    @Test
    fun elBadgeSoloLoBajaMarcarLeido() = enUnHilo { alcance ->
        val m1 = """{"id":"m1","autor":"coach","contenido":"hola","leido_por_cliente":true,"created_at":"2026-10-14T10:00:00+00:00"}"""
        val m2 = """{"id":"m2","autor":"coach","contenido":"¿cómo venís?","created_at":"2026-10-14T11:00:00+00:00"}"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_chat" -> 200 to "[$m2,$m1]"
                "mypump_chat_nuevos" -> 200 to "[$m2]"
                else -> 200 to "[]"
            }
        }
        val chat = ModeloChat(ClienteRpc(transporte = t), TOK_A, null, alcance)
        chat.cargar()
        assertEquals(0, chat.noLeidos.value)
        val sinM2 = TransporteProgramado { fn, _ -> if (fn == "mypump_chat_nuevos") 200 to "[$m2]" else 200 to "[$m1]" }
        val otro = ModeloChat(ClienteRpc(transporte = sinM2), TOK_A, null, alcance)
        otro.cargar()
        otro.sondear()
        assertEquals(1, otro.noLeidos.value)
        otro.cargar()
        assertEquals(1, otro.noLeidos.value)
        otro.marcarLeido()
        assertEquals(0, otro.noLeidos.value)
    }

    // 11. El chat deja de decir "enviando…" apenas sale, sin esperar el sondeo de 15-45 s.
    @Test
    fun laBurbujaSeConfirmaApenasSale() = enUnHilo { alcance ->
        val llego = AtomicBoolean(false)
        val fila = """{"id":"r1","autor":"cliente","contenido":"listo el entreno","created_at":"2026-10-14T11:00:00+00:00"}"""
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_agregar_comentario" -> {
                    llego.set(true)
                    200 to "\"r1\""
                }
                "mypump_get_chat" -> 200 to (if (llego.get()) "[$fila]" else "[]")
                "mypump_chat_nuevos" -> 200 to (if (llego.get()) "[$fila]" else "[]")
                "mypump_get_cliente_info" -> 200 to INFO
                else -> 200 to "[]"
            }
        }
        val cliente = ClienteRpc(transporte = t)
        val esc = Escrituras(cliente, TOK_A)
        val o = Outbox(archivo = null, alcance = alcance) { esc.ejecutar(it) }
        val chat = ModeloChat(cliente, TOK_A, o, alcance)
        chat.enviar("  listo el entreno  ")
        assertTrue(chat.hilo.value.mensajes.single().pendiente)
        delay(700)
        assertEquals(listOf("r1"), chat.hilo.value.mensajes.map { it.id })
    }

    // 12. Salir de la cuenta no deja reintentos vivos de la cola vieja (en iOS el temporizador muere con la cola).
    @Test
    fun salirNoDejaReintentosVivos() = enUnHilo { alcance ->
        val hayRed = AtomicBoolean(false)
        val t = TransporteProgramado { fn, _ ->
            when {
                fn == "mypump_set_habito" && !hayRed.get() -> throw IOException("sin señal")
                fn == "mypump_set_habito" -> 200 to """[{"vasos_agua":3}]"""
                fn == "mypump_get_cliente_info" -> 200 to INFO
                else -> 200 to "[]"
            }
        }
        val m = modelo(t, TokenEnMemoria(TOK_A), alcance)
        m.revision.value!!.setHabito("cardio", "true")
        delay(100)
        assertEquals(1, t.llamadas.count { it == "mypump_set_habito" })
        m.salir()
        hayRed.set(true)
        delay(2_600)   // el reintento estaba programado a 2 s
        assertEquals(1, t.llamadas.count { it == "mypump_set_habito" })
        // Lo pendiente sigue en el archivo de la cuenta: sale cuando vuelva a entrar.
        val ops = (Disco(raiz, TOK_A).leer("outbox.json") as JsonObject)["ops"].toString()
        assertTrue(ops.contains("habito|"))
    }
}
