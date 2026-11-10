package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Tecnica
import com.pumpteam.mypump.reglas.TextosTecnica
import java.io.IOException
import java.util.UUID
import kotlinx.serialization.json.Json

/**
 * El servidor de técnica de mentira: sigue `tecnica/CONTRATO_APP.md` en memoria. Lo usan las pruebas JVM y las de interfaz (este
 * directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red. Gemelo de DobleTecnica.swift.
 */
class DobleTecnica : Transporte {
    @Volatile var palanca = true
    @Volatile var sinFuncion = false
    @Volatile var habilitado = true
    @Volatile var sinRed = false
    @Volatile var tope = false

    /** Estados forzados para las próximas subidas, en orden. 0 = sin red en esa. */
    val proximasSubidas = ArrayDeque<Int>()
    /** Cortes de red forzados en los próximos `nuevo` (después de haber abierto el envío). */
    @Volatile var cortesEnNuevo = 0
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()
    val envios = java.util.concurrent.CopyOnWriteArrayList<MutableMap<String, ValorJson>>()
    var ultimoNuevo: ValorJson? = null
    var cabecerasUltimaSubida: Map<String, String> = emptyMap()
    val bytesSubidos = java.util.concurrent.CopyOnWriteArrayList<Long>()
    /** El último video recibido, para mirarlo en las pruebas de interfaz. */
    var ultimaRutaSubida: java.io.File? = null
    var usoArchivo = false

    val llamadasTecnica: List<String> get() = llamadas.filter { "tecnica" in it }
    val intentosDeSubida: Int get() = llamadas.count { it == "tecnica/upload" }

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        val ruta = pedido.ruta
        val f = ruta.substringAfterLast('/')
        val nombre = if ("/tecnica/" in ruta) "tecnica/$f" else f
        llamadas += nombre
        if (sinRed) throw IOException("sin red (doble)")
        val (status, cuerpo) = atender(nombre, pedido)
        Respuesta(status, cuerpo.toByteArray())
    }

    private fun cuerpo(p: Pedido): ValorJson = p.cuerpo?.let { ValorJson.desde(Json.parseToJsonElement(it.toString(Charsets.UTF_8))) } ?: ValorJson.Nulo

    private fun atender(nombre: String, p: Pedido): Pair<Int, String> = when {
        nombre == "mypump_get_app_config" -> 200 to """{"tecnica_video":$palanca}"""
        nombre.startsWith("mypump_tecnica") && sinFuncion -> 404 to """{"code":"PGRST202","message":"no existe"}"""
        nombre == "mypump_tecnica_get" -> if (!habilitado) 200 to """{"habilitado":false}""" else 200 to ValorJson.objeto(
            "habilitado" to ValorJson.Booleano(true),
            "topes" to ValorJson.objeto("duracion_min_s" to ValorJson.Numero(4.0), "duracion_max_s" to ValorJson.Numero(75.0), "bytes_max" to ValorJson.Numero(62914560.0), "por_semana" to ValorJson.Numero(3.0)),
            "envios" to ValorJson.Lista(envios.map { ValorJson.Objeto(it.toMap()) }),
        ).serializar()
        nombre == "mypump_tecnica_nuevo" -> nuevo(cuerpo(p))
        nombre == "mypump_tecnica_cancelar" -> {
            val id = cuerpo(p)["p_id"]
            envios.removeAll { it["id"] == id && it["estado"]?.comoTexto == "borrador" }
            200 to """{"ok":true,"borrado":true}"""
        }
        nombre == "tecnica/upload" -> subida(p)
        nombre == "tecnica/url" -> 200 to """{"ok":true,"url":"https://ejemplo.invalid/video.mp4","expira_en":3600}"""
        nombre == "tecnica/borrar" -> {
            val id = cuerpo(p)["id"]
            envios.firstOrNull { it["id"] == id }?.put("tiene_video", ValorJson.Booleano(false))
            200 to """{"ok":true}"""
        }
        else -> 200 to "[]"
    }

    private fun nuevo(j: ValorJson): Pair<Int, String> {
        envios.firstOrNull { it["estado"]?.comoTexto in listOf("enviado", "procesando") }?.let { return 200 to """{"ok":false,"error":"en_curso","id":"${it["id"]?.comoTexto}"}""" }
        if (tope) return 200 to """{"ok":false,"error":"tope_semanal"}"""
        ultimoNuevo = j
        val borrador = envios.firstOrNull { it["estado"]?.comoTexto == "borrador" }
        val id = if (borrador != null) {
            borrador["ejercicio_nombre"] = j["p_ejercicio_nombre"] ?: ValorJson.Nulo
            borrador["id"]!!.comoTexto!!
        } else {
            val n = UUID.randomUUID().toString()
            envios.add(0, mutableMapOf("id" to ValorJson.Texto(n), "estado" to ValorJson.Texto("borrador"), "ejercicio_slug" to (j["p_ejercicio_slug"] ?: ValorJson.Nulo), "ejercicio_nombre" to (j["p_ejercicio_nombre"] ?: ValorJson.Nulo), "tiene_video" to ValorJson.Booleano(false)))
            n
        }
        if (cortesEnNuevo > 0) {
            cortesEnNuevo--
            throw IOException("corte (doble)")
        }
        return 200 to """{"ok":true,"ya":false,"id":"$id","estado":"borrador"}"""
    }

    private fun subida(p: Pedido): Pair<Int, String> {
        proximasSubidas.removeFirstOrNull()?.let { s ->
            if (s == 0) throw IOException("corte (doble)")
            if (s == 400) return 400 to """{"ok":false,"error":"video muy corto"}"""
            if (s == 413) return 413 to """{"ok":false,"error":"video muy pesado"}"""
            if (s != 200) return s to """{"ok":false,"error":"forzado"}"""
        }
        cabecerasUltimaSubida = p.cabeceras
        val e = envios.firstOrNull { it["id"]?.comoTexto == p.cabeceras["x-tecnica-id"] } ?: return 404 to """{"ok":false,"error":"envío no encontrado"}"""
        if (e["estado"]?.comoTexto != "borrador") return 200 to """{"ok":true,"ya":true}"""
        usoArchivo = p.archivo != null
        bytesSubidos.add(p.archivo?.length() ?: (p.cuerpo?.size?.toLong() ?: 0))
        e["estado"] = ValorJson.Texto("enviado")
        e["tiene_video"] = ValorJson.Booleano(true)
        return 200 to """{"ok":true}"""
    }

    companion object {
        private fun json(s: String) = ValorJson.desde(Json.parseToJsonElement(s))

        val devolucionDeEjemplo: ValorJson = json(
            """{"credito":"Lo revisó Mati","ejercicio":"Sentadilla","bien":["Bajás con la espalda firme","La profundidad es buena"],
            "correcciones":[{"prioridad":1,"titulo":"Las rodillas se van para adentro","que_se_ve":"Al subir, las dos rodillas se cierran","por_que":"Cargás de más la cara interna de la rodilla","como_corregir":"Empujá el piso hacia afuera con los pies","momento_s":3.5}],
            "no_evaluable":[{"que":"El agarre","motivo":"No se llega a ver desde este ángulo"}],"pedir_otro_video":{"necesario":true,"como":"Grabá de costado y con todo el cuerpo adentro"}}""",
        )
        val devolucionSinCorrecciones: ValorJson = json("""{"credito":"Lo revisó Mati","ejercicio":"Sentadilla","bien":["Serie muy prolija"],"correcciones":[],"no_evaluable":[],"pedir_otro_video":{"necesario":false,"como":""}}""")

        /** El estado de partida de cada escenario de las pruebas de interfaz. */
        fun escenario(nombre: String): DobleTecnica {
            val d = DobleTecnica()
            val id = "22222222-2222-4222-8222-222222222222"
            fun envio(estado: String, vararg extra: Pair<String, ValorJson>): MutableMap<String, ValorJson> = mutableMapOf(
                "id" to ValorJson.Texto(id), "estado" to ValorJson.Texto(estado), "ejercicio_slug" to ValorJson.Texto("sentadilla"), "ejercicio_nombre" to ValorJson.Texto("Sentadilla"),
                "enviado_en" to ValorJson.Texto("2026-11-10T15:00:00+00:00"), "tiene_video" to ValorJson.Booleano(true), *extra,
            )
            val publicado = "publicado_en" to ValorJson.Texto("2026-11-12T15:00:00+00:00")
            when (nombre) {
                "apagado" -> d.palanca = false
                "sinServidor" -> d.sinFuncion = true
                "corte" -> { d.proximasSubidas += 0 }
                "rechazo" -> { d.proximasSubidas += 400 }
                "reintento" -> { d.proximasSubidas += listOf(503, 429) }
                "tope" -> { d.tope = true }
                "enRevision" -> { d.envios += envio("enviado") }
                "publicado" -> { d.envios += envio("publicado", publicado, "devolucion" to devolucionDeEjemplo) }
                "publicadoSinCorrecciones" -> { d.envios += envio("publicado", publicado, "devolucion" to devolucionSinCorrecciones) }
                "rechazado" -> { d.envios += envio("rechazado", "rechazo_texto" to ValorJson.Texto(TextosTecnica.rechazoIlegible), "tiene_video" to ValorJson.Booleano(false)) }
                else -> Unit   // "vacio": habilitado, sin nada
            }
            return d
        }
    }
}
