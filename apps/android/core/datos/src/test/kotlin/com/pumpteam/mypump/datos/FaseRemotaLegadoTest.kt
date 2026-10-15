package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SwapLocal
import com.pumpteam.mypump.reglas.SwapsDeComida
import java.io.File
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

/** Un servidor de mentira para la Fase R: contesta por función y anota cada llamada con sus parámetros. */
class ServidorLegado(private val responder: (String, ValorJson) -> Pair<Int, String>) : Transporte {
    private val lista = ArrayList<Pair<String, ValorJson>>()

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val fn = pedido.ruta.substringAfterLast('/')
        val p = pedido.cuerpo?.let { runCatching { ValorJson.parsear(it.toString(Charsets.UTF_8)) }.getOrNull() } ?: ValorJson.Nulo
        synchronized(this) { lista += fn to p }
        val (status, cuerpo) = responder(fn, p)
        return Respuesta(status, cuerpo.toByteArray())
    }

    fun de(fn: String): List<ValorJson> = synchronized(this) { lista.filter { it.first == fn }.map { it.second } }
}

internal fun rutinaActiva(id: String, dias: List<String> = listOf("b2d1", "b2d2", "b2d3")): String {
    val d = dias.joinToString(",") { """{"id":"$it","nombre":"$it","bloques":[]}""" }
    return """[{"id":"$id","version":3,"semana_actual":3,"tiene_siguiente":false,"estructura":{"dias":[$d]}}]"""
}

/** Contesta como la base: OK a cada escritura; `get_cliente_info` según el token; la rutina activa que se pida. */
internal fun servidorLegado(activa: String = rutinaR1, clientes: Map<String, String> = mapOf(tokenA to "test-nativa-android")) = ServidorLegado { fn, p ->
    when (fn) {
        "mypump_get_cliente_info" -> {
            val c = p["p_token"]?.comoTexto?.let { clientes[it] }
            200 to (if (c == null) "[]" else """[{"cliente_id":"$c","nombre":"Test","perfil":"natural"}]""")
        }
        "mypump_get_rutina_activa" -> 200 to (if (activa.isEmpty()) "[]" else rutinaActiva(activa))
        "mypump_get_sesion_dia" -> 200 to "[]"
        "mypump_iniciar_sesion" -> 200 to "\"99999999-0000-4000-8000-000000000001\""
        "mypump_ingest_salud" -> 200 to "1"
        "mypump_delete_food_swap", "mypump_desmarcar_comida" -> 200 to "true"
        "mypump_set_habito", "mypump_marcar_comida", "mypump_save_food_swap", "mypump_guardar_checkin" -> 200 to """[{"ok":true}]"""
        else -> 200 to "\"00000000-0000-4000-8000-0000000000ff\""
    }
}

/** Una base con estado para los swaps de comida: lo que se guarda, después se lee. */
class BaseDeSwaps(iniciales: List<String>) : Transporte {
    private val swaps = sortedMapOf<String, ValorJson>()   // "comida/opt/food" → food_data

    init {
        for (k in iniciales) swaps[k] = ValorJson.objeto("name" to texto("de otro teléfono"))
    }

    val claves: Set<String> @Synchronized get() = swaps.keys.toSet()

    @Synchronized fun filas(): List<FoodSwap> = swaps.map { (k, v) ->
        val p = k.split("/")
        FoodSwap.desde(
            ValorJson.objeto("comida_id" to texto(p[0]), "opt_idx" to numero(p[1].toDouble()), "food_idx" to numero(p[2].toDouble()), "food_data" to v).aJson(),
        )
    }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val fn = pedido.ruta.substringAfterLast('/')
        val p = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) } ?: ValorJson.Nulo
        fun clave() = "${p["p_comida_id"]?.comoTexto ?: ""}/${(p["p_opt_idx"]?.comoNumero ?: 0.0).toInt()}/${(p["p_food_idx"]?.comoNumero ?: 0.0).toInt()}"
        val cuerpo = synchronized(this) {
            when (fn) {
                "mypump_get_dieta_activa" -> """[{"id":"$dietaD","version":1,"estructura":{"comidas":[]}}]"""
                "mypump_get_food_swaps" -> ValorJson.Lista(
                    swaps.map { (k, v) ->
                        val q = k.split("/")
                        ValorJson.objeto("comida_id" to texto(q[0]), "opt_idx" to numero(q[1].toDouble()), "food_idx" to numero(q[2].toDouble()), "food_data" to v)
                    },
                ).serializar()
                "mypump_save_food_swap" -> {
                    swaps[clave()] = p["p_food_data"] ?: ValorJson.Nulo
                    """[{"ok":true}]"""
                }
                "mypump_delete_food_swap" -> if (swaps.remove(clave()) == null) "false" else "true"
                else -> "[]"
            }
        }
        return Respuesta(200, cuerpo.toByteArray())
    }
}

/** `SCRIPT_ESCRITURA` hecho en Kotlin, sobre un `localStorage` en memoria (el de verdad corre en el WebView; ver abajo). */
internal fun correrEscritura(c: FaseRemotaLegado.CambiosEscritura, ls: MutableMap<String, String>): Map<String, String> {
    val res = LinkedHashMap<String, String>()
    for ((clave, esperado) in c.borrar) {
        val v = ls[clave]
        if (v == null) {
            res[clave] = "no estaba"
            continue
        }
        if (FirmaValor.de(v) != esperado) {
            res[clave] = "cambio"
            continue
        }
        ls.remove(clave)
        res[clave] = "borrada"
    }
    ls[MigracionLegado.CLAVE_MARCA] = c.marca
    res[MigracionLegado.CLAVE_MARCA] = "ok"
    return res
}

/** node, si está en esta máquina (para correr el script de verdad). */
internal object Node {
    private val ruta: String? by lazy {
        listOf("/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node").firstOrNull { File(it).canExecute() }
            ?: runCatching { ProcessBuilder("node", "--version").start().let { if (it.waitFor(10, TimeUnit.SECONDS) && it.exitValue() == 0) "node" else null } }.getOrNull()
    }

    val hay: Boolean get() = ruta != null

    fun correr(programa: String): String {
        val p = ProcessBuilder(ruta!!, "-e", programa).redirectErrorStream(true).start()
        val salida = p.inputStream.readBytes().toString(Charsets.UTF_8)
        check(p.waitFor(30, TimeUnit.SECONDS) && p.exitValue() == 0) { "node: $salida" }
        return salida
    }
}

class FaseRemotaLegadoTest {
    private fun cola(tel: Telefono, cliente: ClienteRpc, alcance: CoroutineScope): Outbox {
        val escrituras = Escrituras(cliente, tokenA)
        return Outbox(archivo = tel.disco().archivo("outbox.json"), reintentoAutomatico = false, alcance = alcance) { op -> escrituras.ejecutar(op) }
    }

    private fun recibos(tel: Telefono) = ReciboEnDisco(File(tel.entorno.carpeta, "recibos"))

    @Test
    fun lasSinSesionContraOtraRutinaVanAFallidos() = enUnHilo { alcance ->
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(18))), "mypump_offline_$tokenA" to fotoOffline(rutinaR1)))
        tel.faseL()
        // Mati activó otro bloque: la rutina activa ya no es la de la foto.
        val servidor = servidorLegado(activa = rutinaR2)
        val cliente = ClienteRpc(transporte = servidor)
        val o = cola(tel, cliente, alcance)
        val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "test-nativa-android", cliente, o, recibos(tel), ahora = ahoraMig, zona = baires)
        assertTrue(r.paraRevisar == 2 && r.aLaCola == 0 && !r.sinRed)
        val f = o.fallidos()
        assertTrue(f.size == 2 && f.all { it.motivo == "para revisar: la rutina activa ya no es la de la foto" })
        assertTrue(f.all { it.op.kind in listOf("carga", "estado") && it.op.payload["sesionId"] == ValorJson.Nulo })
        // Nunca se creó una sesión para ellas.
        assertTrue(servidor.de("mypump_iniciar_sesion").isEmpty() && servidor.de("mypump_get_sesion_dia").isEmpty())
        assertEquals(2, tel.archivos.libro.values.count { it.destino == EntradaLibro.Destino.PARA_REVISAR })
        assertTrue(tel.archivos.pendientes.isEmpty())
        assertEquals(false, tel.archivos.estado?.faseRPendiente)
    }

    @Test
    fun lasSinSesionDeLaMismaRutinaSeMandanYLasDeUnDiaQueNoEstaNo() = enUnHilo { alcance ->
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(18))), "mypump_offline_$tokenA" to fotoOffline(rutinaR1)))
        tel.faseL()
        // Misma rutina, pero Mati sacó el día b2d2 al republicarla.
        val servidor = ServidorLegado { fn, _ ->
            when (fn) {
                "mypump_get_rutina_activa" -> 200 to rutinaActiva(rutinaR1, listOf("b2d1", "b2d3"))
                "mypump_get_sesion_dia" -> 200 to "[]"
                "mypump_iniciar_sesion" -> 200 to "\"99999999-0000-4000-8000-000000000001\""
                "mypump_ingest_salud" -> 200 to "1"
                "mypump_delete_food_swap", "mypump_desmarcar_comida" -> 200 to "true"
                else -> 200 to """[{"ok":true}]"""
            }
        }
        val cliente = ClienteRpc(transporte = servidor)
        val o = cola(tel, cliente, alcance)
        val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "test-nativa-android", cliente, o, recibos(tel), ahora = ahoraMig, zona = baires)
        // colaWeb(18): las sin sesión son carga i=9 (b2d1) y estado i=1 (b2d2).
        assertTrue(r.aLaCola == 1 && r.paraRevisar == 1, "$r")
        assertEquals("para revisar: el día no está en la rutina activa", o.fallidos().firstOrNull()?.motivo)
        // Se mandó por la cola normal (resolveSesion: get_sesion_dia → iniciar_sesion → registrar_carga), con las demás.
        val cargas = servidor.de("mypump_registrar_carga")
        assertTrue(cargas.any { it["p_sesion_id"]?.comoTexto == "99999999-0000-4000-8000-000000000001" && it["p_dia_id"]?.comoTexto == "b2d1" })
        assertEquals(1, servidor.de("mypump_iniciar_sesion").size)
        assertEquals(0, o.pendientes())
        // El recibo quedó en disco, sin contenido crudo.
        val recibo = File(tel.entorno.carpeta, "recibos/recibo-1.json").readText()
        assertTrue(!recibo.contains(tokenA) && !recibo.contains("Press inclinado") && recibo.contains("\"paraRevisar\":1") && recibo.contains("\"android\""))
        assertEquals(EntregaRecibo.SOLO_LOCAL, r.recibo)
    }

    @Test
    fun colaDeUnTokenRotado() {
        for ((caso, clientes, esperado) in listOf(
            Triple("mismo", mapOf(tokenA to "c1", tokenB to "c1"), EntradaLibro.Destino.REASIGNADA),
            Triple("otro", mapOf(tokenA to "c1", tokenB to "c2"), EntradaLibro.Destino.OTRO_CLIENTE),
            Triple("revocado", mapOf(tokenA to "c1"), EntradaLibro.Destino.NO_RESUELVE),
        )) {
            enUnHilo { alcance ->
                val tel = Telefono()
                val foto = "data:image/jpeg;base64,/9j/AAAA"
                tel.lector.escribir(
                    mapOf(
                        "mypump_token" to tokenA, "mypump_outbox_$tokenB" to json(ValorJson.Lista(colaWeb(9, t0 = 50.0))),
                        "mypump_offline_$tokenB" to fotoOffline(rutinaR1),
                        "mypump_fotoq_$tokenB" to """{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-13","dataUrl":"$foto","intentos":0}}""",
                    ),
                )
                assertEquals(9, tel.faseL().estacionadas, caso)
                val servidor = servidorLegado(clientes = clientes)
                val cliente = ClienteRpc(transporte = servidor)
                val o = cola(tel, cliente, alcance)
                val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "c1", cliente, o, recibos(tel), ahora = ahoraMig, zona = baires)
                val destinos = tel.archivos.libro.values.map { it.destino }.toSet()
                val fotos = (tel.disco().leer(FotoPendiente.ARCHIVO)?.let(ValorJson::desde) as? ValorJson.Objeto)?.campos ?: emptyMap()
                if (esperado == EntradaLibro.Destino.REASIGNADA) {
                    assertTrue(r.reasignadas == 9 && destinos == setOf(EntradaLibro.Destino.REASIGNADA), caso)
                    assertTrue(servidor.de("mypump_registrar_carga").size == 1 && servidor.de("mypump_agregar_comentario").size == 1, caso)
                    assertEquals(1, fotos.size, caso)
                    assertTrue(tel.archivos.pendientes.isEmpty(), caso)
                    // Ya es de esta cuenta: la escritura de vuelta saca su cola y su cola de fotos de la Capacitor.
                    assertNotNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_outbox_$tokenB"), caso)
                    assertNotNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_fotoq_$tokenB"), caso)
                } else {
                    assertTrue(r.reasignadas == 0 && destinos == setOf(esperado), caso)
                    assertTrue(servidor.de("mypump_registrar_carga").isEmpty() && o.pendientes() == 0, caso)
                    assertTrue(fotos.isEmpty(), caso)
                    assertEquals(esperado.crudo, tel.archivos.pendientes.firstOrNull()?.estado?.crudo, caso)
                    assertNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_outbox_$tokenB"), caso)
                    assertNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_fotoq_$tokenB"), caso)
                }
                // Nunca se preguntó con el token de otra persona más que para saber de quién era.
                assertTrue(servidor.de("mypump_get_cliente_info").all { it["p_token"]?.comoTexto == tokenB }, caso)
            }
        }
    }

    /**
     * Revisión adversarial del 15-oct, hallazgo 2: la Fase R dejaba las fotos del token rotado en el ARCHIVO, por detrás del
     * modelo de fotos vivo, que tiene su cola en memoria y lo pisa al guardar: se perdían.
     */
    @Test
    fun lasFotosDelTokenRotadoVanAlModeloDeFotosVivo() = enUnHilo { alcance ->
        val tel = Telefono()
        val foto = "data:image/jpeg;base64,/9j/AAAA"
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA, "mypump_outbox_$tokenB" to json(ValorJson.Lista(colaWeb(2, t0 = 50.0))),
                "mypump_offline_$tokenB" to fotoOffline(rutinaR1),
                "mypump_fotoq_$tokenB" to """{"2026-10-12|perfil":{"pose":"perfil","fecha":"2026-10-13","dataUrl":"$foto","intentos":0}}""",
            ),
        )
        tel.faseL()
        val cliente = ClienteRpc(transporte = servidorLegado(clientes = mapOf(tokenA to "c1", tokenB to "c1")))
        tel.disco().guardar(
            FotoPendiente.ARCHIVO,
            ValorJson.objeto("2026-10-12|frente" to FotoPendiente("frente", "2026-10-14", foto, 0).aValor()),
        )
        val fotos = ModeloFotos(cliente, tokenA, tel.disco())
        val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "c1", cliente, cola(tel, cliente, alcance), recibos(tel), ahora = ahoraMig, zona = baires,
                                        fotos = fotos)
        assertEquals(2, r.reasignadas)
        assertEquals(setOf("2026-10-12|frente", "2026-10-12|perfil"), fotos.pendientes.value.keys, "la foto del token rotado no llegó a la cola viva")
        assertNotNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_fotoq_$tokenB"))
    }

    @Test
    fun sinRedQuedaPendienteYNoSeEscribeDeVuelta() = enUnHilo { alcance ->
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(10)))))
        tel.faseL()
        val cliente = ClienteRpc(transporte = SinRed)
        val o = cola(tel, cliente, alcance)
        val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "c1", cliente, o, recibos(tel), ahora = ahoraMig)
        assertTrue(r.sinRed && r.recibo == null)
        assertEquals(2, tel.archivos.pendientes.firstOrNull()?.ops?.size)
        assertNull(FaseRemotaLegado.escrituraPendiente(tel.entorno))   // la Fase R no terminó
        assertTrue(FaseRemotaLegado.hayPendiente(tel.entorno) && FaseRemotaLegado.faseRPendiente(tel.entorno))
    }

    @Test
    fun escrituraDeVueltaConfirmadaEnElArranqueSiguiente() = enUnHilo { alcance ->
        val tel = Telefono()
        val p = "mypump_sesion_${tokenA}_"
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(12))), "mypump_outbox_anon" to json(ValorJson.Lista(colaWeb(2))),
                "mypump_offline_$tokenA" to fotoOffline(rutinaR1), p + "b2d1" to sesionS, p + "b2d1_semana" to "3", "mypump_tipo_dia" to "entreno",
            ),
        )
        tel.faseL()
        val cliente = ClienteRpc(transporte = servidorLegado())
        FaseRemotaLegado.correr(tel.entorno, tokenA, "test-nativa-android", cliente, cola(tel, cliente, alcance), recibos(tel), ahora = ahoraMig)
        val cambios = FaseRemotaLegado.escrituraPendiente(tel.entorno, "2.0.0 (100)", ahoraMig)!!
        assertEquals(setOf("mypump_outbox_$tokenA", p + "b2d1", p + "b2d1_semana"), cambios.borrar.keys)

        // La escritura de vuelta sobre el `localStorage` (con la misma lógica que el script del WebView).
        val ls = tel.lector.claves.toMutableMap()
        ls[p + "b2d1_semana"] = "4"   // cambió después de leerla: no se borra
        val resultado = correrEscritura(cambios, ls)
        assertEquals(
            mapOf("mypump_outbox_$tokenA" to "borrada", p + "b2d1" to "borrada", p + "b2d1_semana" to "cambio", "mypump_nativa_marca" to "ok"),
            resultado,
        )
        FaseRemotaLegado.registrarEscritura(tel.entorno, cambios, resultado)
        assertTrue(tel.archivos.estado?.escrituraHecha == 1 && tel.archivos.estado?.escritura == null)

        // El almacenamiento queda como lo bajaría el WebView. Arranque siguiente: la lectura encuentra la marca y lo
        // confirma; no hay nada nuevo para traer.
        tel.lector.reemplazar(ls)
        val r = tel.faseL()
        assertTrue(r.corrio && r.escrituraConfirmada == 1)
        assertTrue(r.aLaCola == 0 && r.porValidar == 0 && r.anon == 0 && r.yaEnElLibro == 2)   // solo queda la anon (no se toma)
        val estado = tel.archivos.estado!!
        assertEquals(1, estado.escrituraConfirmada)
        assertEquals(listOf(p + "b2d1_semana"), estado.escritura?.borrar?.keys?.sorted())   // lo que cambió se reintenta
        assertEquals(estado.migracion, Marca.leer(tel.lector.claves["mypump_nativa_marca"])?.migracion)
        assertEquals("2.0.0 (100)", Marca.leer(tel.lector.claves["mypump_nativa_marca"])?.app)
    }

    @Test
    fun siLaEscrituraNoLlegoAlDiscoSeRepite() = enUnHilo { alcance ->
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(3)))))
        tel.faseL()
        val cliente = ClienteRpc(transporte = servidorLegado())
        FaseRemotaLegado.correr(tel.entorno, tokenA, "test-nativa-android", cliente, cola(tel, cliente, alcance), recibos(tel), ahora = ahoraMig)
        val cambios = FaseRemotaLegado.escrituraPendiente(tel.entorno)!!
        FaseRemotaLegado.registrarEscritura(tel.entorno, cambios, mapOf("mypump_nativa_marca" to "ok"))
        assertNull(FaseRemotaLegado.escrituraPendiente(tel.entorno))
        // El proceso murió antes de que el WebView bajara al disco: el almacenamiento no cambió.
        val r = tel.faseL()
        assertFalse(r.corrio)
        assertEquals(cambios.borrar, FaseRemotaLegado.escrituraPendiente(tel.entorno)?.borrar)
    }

    /** Si la marca no quedó escrita (el WebView contestó "fallo"), la escritura no cuenta como hecha: sigue pendiente. */
    @Test
    fun sinLaMarcaLaEscrituraSiguePendiente() = enUnHilo { alcance ->
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(3)))))
        tel.faseL()
        val cliente = ClienteRpc(transporte = servidorLegado())
        FaseRemotaLegado.correr(tel.entorno, tokenA, "test-nativa-android", cliente, cola(tel, cliente, alcance), recibos(tel), ahora = ahoraMig)
        val cambios = FaseRemotaLegado.escrituraPendiente(tel.entorno)!!
        FaseRemotaLegado.registrarEscritura(tel.entorno, cambios, mapOf("mypump_outbox_$tokenA" to "borrada", "mypump_nativa_marca" to "fallo"))
        assertNull(tel.archivos.estado?.escrituraHecha)
        assertEquals(cambios.borrar, FaseRemotaLegado.escrituraPendiente(tel.entorno)?.borrar)
    }

    @Test
    fun losSwapsDeComidaSinMigrarSeSubenAntesDeDrenar() {
        // Un teléfono de la v1.0.11 (sin la marca de migrados) con un swap local que el servidor nunca vio, y en la cola
        // vieja un swap de OTRA posición. Si la Fase R drenara primero, la hidratación del modelo vería el servidor con algo,
        // tomaría el merge y tiraría el local. Se decide antes de drenar.
        for ((caso, servidorTiene, marcaNativa, esperado) in listOf(
            Cuatro("vacío", false, false, 1), Cuatro("ya tiene uno", true, false, 0), Cuatro("marca nativa", false, true, 0),
        )) {
            enUnHilo { alcance ->
                val tel = Telefono()
                val c1 = ValorJson.objeto(
                    "_id" to texto("1_1"), "kind" to texto("swap"), "dedupeKey" to texto("swap_${dietaD}_c1_0_0"),
                    "payload" to ValorJson.objeto(
                        "dietaId" to texto(dietaD), "comidaId" to texto("c1"), "optIdx" to numero(0), "foodIdx" to numero(0),
                        "food" to ValorJson.objeto("name" to texto("Ricota"), "_orig" to ValorJson.objeto("name" to texto("Pollo"))),
                    ),
                    "tries" to numero(0), "ts" to numero(1),
                )
                tel.lector.escribir(
                    mapOf(
                        "mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(listOf(c1))),
                        "mypump_food_swaps_$dietaD" to """{"swap_${dietaD}_c3_0_0":{"original":{"name":"Merluza"},"current":{"name":"Atún","_orig":{"name":"Merluza","qty":250,"unit":"g"}}}}""",
                    ),
                )
                tel.faseL()
                if (marcaNativa) tel.disco().guardar("swaps_migrados_$dietaD", kotlinx.serialization.json.JsonPrimitive(true))
                val base = BaseDeSwaps(if (servidorTiene) listOf("c4/0/0") else emptyList())
                val cliente = ClienteRpc(transporte = base)
                val o = cola(tel, cliente, alcance)
                val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "c1", cliente, o, recibos(tel), ahora = ahoraMig)
                assertEquals(esperado, r.swapsSinMigrar, caso)
                o.drenar()
                assertTrue("c1/0/0" in base.claves, caso)   // el de la cola vieja sale siempre
                assertEquals(esperado == 1, "c3/0/0" in base.claves, caso)
                // Y la hidratación del modelo, corra cuando corra, ya no lo pierde: o está en la base o está en la cola.
                val pendientes = o.pendientesPorClave().mapValues { it.value.kind }
                val locales = (tel.disco().leer("swaps_$dietaD.json")?.let(ValorJson::desde) as? ValorJson.Objeto)?.campos
                    ?.mapValues { (_, s) -> SwapLocal(s["original"]?.takeUnless { it == ValorJson.Nulo }, s["current"] ?: ValorJson.Nulo) } ?: emptyMap()
                val yaMigrado = tel.disco().leer("swaps_migrados_$dietaD")?.toString() == "true"
                val h = SwapsDeComida.hidratar(base.filas(), locales, dietaD, pendientes, yaMigrado) { _, _, _ -> emptyList() }
                if (esperado == 1) assertNotNull(h?.swaps?.get("swap_${dietaD}_c3_0_0"), caso)
            }
        }
    }

    private data class Cuatro(val caso: String, val servidorTiene: Boolean, val marcaNativa: Boolean, val esperado: Int)

    /** El script de verdad (el que corre el WebView) da lo mismo que la versión en Kotlin, también con emoji y surrogates. */
    @Test
    fun elScriptDelWebViewHaceLoMismo() {
        assumeTrue(Node.hay, "sin node en esta máquina")
        val ls = mapOf(
            "a" to "Mati, ¿cambio el jalón? 😀", "b" to "nulo\u0000adentro", "c" to "x".repeat(10_000), "d" to "cambió",
            "mypump_otra" to "no se toca",
        )
        val cambios = FaseRemotaLegado.CambiosEscritura(
            corrida = 3,
            borrar = mapOf("a" to FirmaValor.de(ls.getValue("a")), "b" to FirmaValor.de(ls.getValue("b")), "c" to FirmaValor.de(ls.getValue("c")),
                "d" to FirmaValor.de("otro valor"), "falta" to FirmaValor.de("z")),
            marca = Marca("0b5c6c1e-0000-4000-8000-000000000001", 3, "2026-10-14T15:00:00Z", "2.0.0").texto,
        )
        val enKotlin = ls.toMutableMap()
        val resKotlin = correrEscritura(cambios, enKotlin)
        val programa = """
            const ls = new Map(Object.entries(${ValorJson.Objeto(ls.mapValues { ValorJson.Texto(it.value) }).serializar()}));
            globalThis.localStorage = { getItem: (k) => ls.has(k) ? ls.get(k) : null, setItem: (k, v) => { ls.set(k, String(v)); }, removeItem: (k) => { ls.delete(k); } };
            const res = ${FaseRemotaLegado.scriptConArgumentos(cambios)};
            process.stdout.write(JSON.stringify({ res, ls: Object.fromEntries(ls) }));
        """.trimIndent()
        val salida = ValorJson.parsear(Node.correr(programa))
        assertEquals(ValorJson.Objeto(resKotlin.mapValues { ValorJson.Texto(it.value) }), salida["res"])
        assertEquals(ValorJson.Objeto(enKotlin.mapValues { ValorJson.Texto(it.value) }), salida["ls"])
        // La firma de JavaScript (charCodeAt + Math.imul) con un surrogate suelto, que en Kotlin es una unidad más.
        val js = ValorJson.parsear(Node.correr(
            "function firma(s){let h=0x811c9dc5;for(let i=0;i<s.length;i++){h^=s.charCodeAt(i);h=Math.imul(h,0x01000193);}return [s.length,h>>>0];}" +
                "process.stdout.write(JSON.stringify(firma('a\\ud83db')));",
        )) as ValorJson.Lista
        val f = FirmaValor.de("a\uD83Db")
        assertEquals(listOf(f.unidades.toDouble(), f.fnv.toDouble()), js.elementos.map { it.comoNumero })
    }

    /** Con el recibo confirmado por el servidor, la copia cruda se borra a los 90 días (y antes no). */
    @Test
    fun laCopiaCrudaSeBorraNoventaDiasDespuesDelReciboConfirmado() = enUnHilo { alcance ->
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(3)))))
        tel.faseL()
        val cliente = ClienteRpc(transporte = servidorLegado())
        val confirma = ReciboMigracion { _, _ -> EntregaRecibo.CONFIRMADO }
        val r = FaseRemotaLegado.correr(tel.entorno, tokenA, "test-nativa-android", cliente, cola(tel, cliente, alcance), confirma, ahora = ahoraMig)
        assertEquals(EntregaRecibo.CONFIRMADO, r.recibo)
        val copia = File(tel.entorno.crudo, tel.archivos.estado!!.copias.single())
        FaseRemotaLegado.podarCopias(tel.entorno, ahoraMig.plusSeconds(89L * 86_400))
        assertTrue(copia.exists())
        FaseRemotaLegado.podarCopias(tel.entorno, ahoraMig.plusSeconds(91L * 86_400))
        assertFalse(copia.exists())
        assertTrue(tel.archivos.estado!!.copias.isEmpty())
    }
}
