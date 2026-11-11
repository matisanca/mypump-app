package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Gimnasio
import java.io.IOException
import java.util.UUID
import kotlinx.serialization.json.Json

/**
 * El servidor del gimnasio de mentira: sigue `gimnasio/CONTRATO_APP.md` en memoria. Lo usan las pruebas JVM y las de interfaz
 * (este directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red. Gemelo de DobleGimnasio.swift.
 */
class DobleGimnasio : Transporte {
    data class Foto(val id: String, val zona: String, val bytes: ByteArray, val ronda: Int)

    @Volatile var palanca = true
    @Volatile var sinFuncion = false
    @Volatile var habilitado = true
    @Volatile var sinRed = false

    /** Estados forzados para las próximas subidas, en orden. 0 = sin red en esa. */
    val proximasSubidas = ArrayDeque<Int>()
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()
    var abierta: MutableMap<String, ValorJson>? = null
    var vigente: Map<String, ValorJson>? = null
    val fotos = java.util.concurrent.CopyOnWriteArrayList<Foto>()
    var ultimoEnviar: ValorJson? = null
    var ultimoResponder: ValorJson? = null
    var cabecerasUltimaSubida: Map<String, String> = emptyMap()

    val llamadasGimnasio: List<String> get() = llamadas.filter { "gimnasio" in it }

    // ── Entrenar en casa (`cola-b/CONTRATO_APP.md`, sección 3): la misma fila, con `lugar` ──
    @Volatile var palancaCasa = false
    @Volatile var casaHabilitada = true
    @Volatile var sinFuncionCasa = false

    /** Lo que contestan los próximos `mypump_casa_elegir`, en orden: "red" (corte), "reintentar", "nulo" (token caído). */
    val proximosElegir = ArrayDeque<String>()
    /** Lo mismo para `mypump_casa_enviar`: "red", "nulo" o un error del contrato. */
    val proximosEnviarCasa = ArrayDeque<String>()
    var ultimoEnviarCasa: ValorJson? = null
    val llamadasCasa: List<String> get() = llamadas.filter { "casa" in it }
    val intentosDeSubida: Int get() = llamadas.count { it == "gimnasio/upload" }

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        val ruta = pedido.ruta
        val f = ruta.substringAfterLast('/')
        val nombre = if ("/gimnasio/" in ruta) "gimnasio/$f" else f
        llamadas += nombre
        if (sinRed) throw IOException("sin red (doble)")
        val (status, cuerpo) = atender(nombre, pedido)
        Respuesta(status, cuerpo.toByteArray())
    }

    private fun cuerpo(p: Pedido): ValorJson = p.cuerpo?.let { ValorJson.desde(Json.parseToJsonElement(it.toString(Charsets.UTF_8))) } ?: ValorJson.Nulo
    private val si = ValorJson.Booleano(true)
    private val no = ValorJson.Booleano(false)
    private fun t(s: String) = ValorJson.Texto(s)

    private fun atender(nombre: String, p: Pedido): Pair<Int, String> {
        if (nombre == "mypump_get_app_config") return 200 to """{"gimnasio_fotos":$palanca,"casa":$palancaCasa}"""
        if (nombre.startsWith("mypump_gimnasio") && sinFuncion) return 404 to """{"code":"PGRST202","message":"no existe"}"""
        if (nombre.startsWith("mypump_casa") && sinFuncionCasa) return 404 to """{"code":"PGRST202","message":"no existe"}"""
        return when (nombre) {
            "mypump_casa_get" -> 200 to (if (!casaHabilitada) """{"habilitado":false}""" else vistaCasa().serializar())
            "mypump_casa_elegir" -> 200 to elegirCasa(cuerpo(p))
            "mypump_casa_enviar" -> 200 to enviarCasa(cuerpo(p))
            "mypump_gimnasio_get" -> if (!habilitado) 200 to """{"habilitado":false}""" else 200 to vista().serializar()
            "mypump_gimnasio_nuevo" -> nuevo(cuerpo(p))
            "mypump_gimnasio_enviar" -> 200 to enviarCarga(cuerpo(p))
            "mypump_gimnasio_responder" -> 200 to responderCarga(cuerpo(p))
            "gimnasio/upload" -> subida(p)
            "gimnasio/urls" -> 200 to ValorJson.objeto(
                "ok" to si, "expira_en" to ValorJson.Numero(3600.0),
                "fotos" to ValorJson.Lista(fotos.map { ValorJson.objeto("id" to t(it.id), "zona" to t(it.zona), "url" to t("https://ejemplo.invalid/${it.id}.jpg")) }),
            ).serializar()
            "gimnasio/borrar" -> {
                if (abierta?.get("estado")?.comoTexto != "borrador") return 409 to """{"ok":false}"""
                val id = cuerpo(p)["foto_id"]?.comoTexto
                fotos.removeAll { it.id == id }
                200 to """{"ok":true}"""
            }
            else -> 200 to "[]"
        }
    }

    private fun nuevo(j: ValorJson): Pair<Int, String> {
        if (j["p_modo"]?.comoTexto == "parcial" && vigente == null) return 200 to """{"ok":false,"error":"sin_gimnasio_vigente"}"""
        abierta?.let { a -> return 200 to ValorJson.objeto("ok" to si, "ya" to si, "id" to a["id"]!!, "estado" to a["estado"]!!).serializar() }
        val id = UUID.randomUUID().toString()
        abierta = linkedMapOf("id" to t(id), "estado" to t("borrador"), "modo" to (j["p_modo"] ?: t("completa")))
        return 200 to ValorJson.objeto("ok" to si, "ya" to no, "id" to t(id), "estado" to t("borrador")).serializar()
    }

    private fun subida(p: Pedido): Pair<Int, String> {
        if (proximasSubidas.isNotEmpty()) {
            val s = proximasSubidas.removeFirst()
            if (s == 0) throw IOException("corte (doble)")
            if (s != 200) return s to """{"ok":false,"error":"forzado"}"""
        }
        val h = p.cabeceras
        cabecerasUltimaSubida = h
        val id = h["x-gimnasio-foto"]
        val zona = h["x-gimnasio-zona"]
        if (id == null || zona == null || h["x-gimnasio-id"] != abierta?.get("id")?.comoTexto) return 404 to """{"ok":false}"""
        val estado = abierta?.get("estado")?.comoTexto
        if (estado != "borrador" && estado != "a_confirmar") return 409 to """{"ok":false}"""
        if (fotos.any { it.id == id }) return 200 to """{"ok":true,"ya":true}"""
        if (fotos.size >= Gimnasio.TOPE_FOTOS) return 413 to """{"ok":false}"""
        fotos += Foto(id, zona, p.cuerpo ?: ByteArray(0), if (estado == "borrador") 0 else 1)
        return 200 to """{"ok":true}"""
    }

    private fun lista(v: ValorJson?): List<String> = (v as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList()

    private fun enviarCarga(j: ValorJson): String {
        val a = abierta
        if (a == null || a["id"] != j["p_id"]) return """{"ok":false,"error":"no_encontrado"}"""
        if (a["estado"]?.comoTexto != "borrador") return """{"ok":true,"ya":true,"estado":"enviado"}"""
        ultimoEnviar = j
        val con = fotos.map { it.zona }.toSet()
        if (a["modo"]?.comoTexto == "completa") {
            val f = Gimnasio.zonasFaltantes(con, lista(j["p_no_hay"]).toSet())
            if (f.isNotEmpty()) return ValorJson.objeto("ok" to no, "error" to t("faltan_zonas"), "faltan" to ValorJson.Lista(f.map { t(it) })).serializar()
        } else if (con.isEmpty() && lista(j["p_quitar"]).isEmpty()) {
            return """{"ok":false,"error":"sin_novedad"}"""
        }
        a["estado"] = t("enviado")
        return """{"ok":true,"ya":false,"estado":"enviado"}"""
    }

    private fun responderCarga(j: ValorJson): String {
        val a = abierta
        if (a == null || a["id"] != j["p_id"]) return """{"ok":false,"error":"no_encontrado"}"""
        if (a["estado"]?.comoTexto != "a_confirmar") return """{"ok":true,"ya":true,"estado":"respondido"}"""
        ultimoResponder = j["p_respuestas"]
        a["estado"] = t("respondido")
        a["preguntas"] = ValorJson.Lista(emptyList())
        return """{"ok":true,"ya":false,"estado":"respondido"}"""
    }

    // ── Casa ──

    private fun vistaCasa(): ValorJson {
        fun carga(c: Map<String, ValorJson>?): ValorJson {
            c ?: return ValorJson.Nulo
            return ValorJson.objeto(
                "id" to c["id"]!!, "estado" to c["estado"]!!, "lugar" to (c["lugar"] ?: t("gimnasio")),
                "equipos" to (c["casa_equipos"] ?: ValorJson.Lista(emptyList())), "sin_equipo" to (c["casa_sin_equipo"] ?: no), "nota" to (c["casa_nota"] ?: ValorJson.Nulo),
            )
        }
        return ValorJson.objeto("habilitado" to si, "tipos" to TIPOS_CASA, "abierta" to carga(abierta), "vigente" to carga(vigente))
    }

    private fun elegirCasa(j: ValorJson): String {
        if (proximosElegir.isNotEmpty()) {
            when (val forzado = proximosElegir.removeFirst()) {
                "red" -> throw IOException("corte (doble)")
                "nulo" -> return "null"
                else -> return """{"ok":false,"error":"$forzado"}"""
            }
        }
        if (!casaHabilitada) return """{"ok":false,"error":"no_habilitado"}"""
        val aCasa = j["p_casa"] == si
        val lugar = if (aCasa) "casa" else "gimnasio"
        val a = abierta
        if (a != null) {
            if ((a["lugar"]?.comoTexto ?: "gimnasio") == lugar) return ValorJson.objeto("ok" to si, "ya" to si, "id" to a["id"]!!, "estado" to a["estado"]!!, "lugar" to t(lugar)).serializar()
            if (a["estado"]?.comoTexto != "borrador") return """{"ok":false,"error":"en_curso"}"""
            a["lugar"] = t(lugar)
            if (aCasa) a["modo"] = t("completa")
            return ValorJson.objeto("ok" to si, "ya" to no, "id" to a["id"]!!, "estado" to t("borrador"), "lugar" to t(lugar)).serializar()
        }
        if (!aCasa) return """{"ok":true,"ya":true,"id":null,"lugar":"gimnasio"}"""
        val id = UUID.randomUUID().toString()
        abierta = linkedMapOf("id" to t(id), "estado" to t("borrador"), "modo" to t("completa"), "lugar" to t("casa"))
        return ValorJson.objeto("ok" to si, "ya" to no, "id" to t(id), "estado" to t("borrador"), "lugar" to t("casa")).serializar()
    }

    private fun enviarCasa(j: ValorJson): String {
        if (proximosEnviarCasa.isNotEmpty()) {
            when (val forzado = proximosEnviarCasa.removeFirst()) {
                "red" -> throw IOException("corte (doble)")
                "nulo" -> return "null"
                else -> return """{"ok":false,"error":"$forzado"}"""
            }
        }
        val a = abierta
        if (a == null || a["id"] != j["p_id"]) return """{"ok":false,"error":"no_encontrado"}"""
        if (a["lugar"]?.comoTexto != "casa") return """{"ok":false,"error":"no_es_casa"}"""
        if (a["estado"]?.comoTexto != "borrador") return ValorJson.objeto("ok" to si, "ya" to si, "estado" to a["estado"]!!).serializar()
        if (!casaHabilitada) return """{"ok":false,"error":"no_habilitado"}"""
        ultimoEnviarCasa = j
        val equipos = (j["p_equipos"] as? ValorJson.Lista)?.elementos ?: emptyList()
        val sin = j["p_sin_equipo"] == si
        if (equipos.isEmpty() && !sin) return """{"ok":false,"error":"sin_datos"}"""
        if (equipos.isNotEmpty() && sin) return """{"ok":false,"error":"contradiccion"}"""
        a["estado"] = t("a_revisar")
        a["casa_equipos"] = ValorJson.Lista(equipos)
        a["casa_sin_equipo"] = if (sin) si else no
        j["p_nota"]?.comoTexto?.trim()?.takeIf { it.isNotEmpty() }?.let { a["casa_nota"] = t(it) }
        return """{"ok":true,"ya":false,"estado":"a_revisar"}"""
    }

    /** Mati la aprobó: pasa a ser la vigente. */
    fun aprobarCasa() {
        val a = abierta ?: return
        vigente = LinkedHashMap(a).also { it["estado"] = t("listo") }
        abierta = null
    }

    private fun vista(): ValorJson {
        fun carga(c: Map<String, ValorJson>?): ValorJson {
            c ?: return ValorJson.Nulo
            val m = LinkedHashMap(c)
            if (c["estado"]?.comoTexto != "listo") {
                m["fotos"] = ValorJson.Lista(fotos.map { ValorJson.objeto("id" to t(it.id), "zona" to t(it.zona), "ronda" to ValorJson.Numero(it.ronda.toDouble())) })
            }
            return ValorJson.Objeto(m)
        }
        return ValorJson.objeto(
            "habilitado" to si, "abierta" to carga(abierta), "vigente" to carga(vigente),
        )
    }

    companion object {
        private const val ID = "11111111-1111-4111-8111-111111111111"
        private fun parsear(s: String) = ValorJson.desde(Json.parseToJsonElement(s))
        val PREGUNTAS: ValorJson by lazy {
            parsear(
                """[{"id":"remo","clase":"elegir","multiple":true,"zona":"tiron","texto":"¿Cuál de estas tenés en tu gimnasio?","fotos":[],"opciones":[{"valor":"remo_t","texto":"Remo T"},{"valor":"remo_pecho_apoyado","texto":"Remo con pecho apoyado"}]},
                {"id":"accesorios","clase":"elegir","multiple":true,"zona":"accesorios_polea","texto":"¿Cuáles de estos agarres para polea hay en tu gimnasio?","fotos":[],"opciones":[{"valor":"soga","texto":"Soga"},{"valor":"barra_v","texto":"Barra V"},{"valor":"barra_recta","texto":"Barra recta"}]},
                {"id":"peso_discos","clase":"elegir","multiple":false,"zona":"discos","texto":"¿Cuál es el disco más chico que hay?","fotos":[],"opciones":[{"valor":"1.25","texto":"1,25 kg"},{"valor":"2.5","texto":"2,5 kg"},{"valor":"5","texto":"5 kg"}]},
                {"id":"peso_mancuernas","clase":"numero","zona":"mancuernas","texto":"¿Hasta cuántos kilos llegan las mancuernas?","unidad":"kg","fotos":[]},
                {"id":"confirmar_empuje","clase":"confirmar","zona":"empuje","texto":"Confirmanos qué de esto hay en tu gimnasio","fotos":[],"items":[{"tipo":"pec_deck","texto":"Pec deck","fotos":[]},{"tipo":"press_inclinado","texto":"Press inclinado","fotos":[]}]},
                {"id":"foto_1","clase":"foto","zona":"bancos","texto":"Necesitamos otra foto de esta zona, sin gente y con el equipo entero","fotos":[]}]""",
            )
        }
        /** La lista de casa, como la da `mypump_casa_get` (recortada). */
        val TIPOS_CASA: ValorJson by lazy {
            parsear(
                """[{"tipo":"mancuernas","nombre":"Mancuernas","kg":true},{"tipo":"barra_olimpica","nombre":"Barra","kg":false},{"tipo":"discos","nombre":"Discos","kg":true},
                {"tipo":"banco_plano","nombre":"Banco plano","kg":false},{"tipo":"bandas_elasticas","nombre":"Bandas elásticas","kg":false}]""",
            )
        }
        val EQUIPOS: ValorJson by lazy {
            parsear(
                """[{"tipo":"polea_doble","nombre":"Cruce de poleas","zona":"poleas","cantidad":2},{"tipo":"prensa_45","nombre":"Prensa 45°","zona":"piernas","cantidad":1},
                {"tipo":"banco_regulable","nombre":"Banco regulable","zona":"bancos","cantidad":3},{"tipo":"mancuernas","nombre":"Mancuernas hasta 50 kg","zona":"mancuernas","cantidad":1}]""",
            )
        }

        fun escenario(nombre: String): DobleGimnasio {
            val d = DobleGimnasio()
            fun t(s: String) = ValorJson.Texto(s)
            when (nombre) {
                "apagado" -> d.palanca = false
                "sinServidor" -> d.sinFuncion = true
                "borrador", "corte", "rechazo", "reintento" -> {
                    d.abierta = linkedMapOf("id" to t(ID), "estado" to t("borrador"), "modo" to t("completa"))
                    when (nombre) {
                        "corte" -> d.proximasSubidas.addAll(listOf(200, 0))
                        "rechazo" -> d.proximasSubidas.add(400)
                        "reintento" -> d.proximasSubidas.add(503)
                    }
                }
                "enProceso" -> {
                    d.abierta = linkedMapOf("id" to t(ID), "estado" to t("procesando"), "modo" to t("completa"))
                }
                "preguntas" -> {
                    d.abierta = linkedMapOf("id" to t(ID), "estado" to t("a_confirmar"), "modo" to t("completa"), "preguntas" to PREGUNTAS)
                }
                // Entrenar en casa: con la palanca `casa` prendida.
                "casaVacio" -> d.palancaCasa = true
                "casaBorrador" -> {
                    d.palancaCasa = true
                    d.abierta = linkedMapOf("id" to t(ID), "estado" to t("borrador"), "modo" to t("completa"), "lugar" to t("casa"))
                }
                "casaEnviada" -> {
                    d.palancaCasa = true
                    d.abierta = linkedMapOf("id" to t(ID), "estado" to t("a_revisar"), "modo" to t("completa"), "lugar" to t("casa"))
                }
                "casaVigente", "casaVigenteSinEquipo" -> {
                    d.palancaCasa = true
                    d.vigente = linkedMapOf(
                        "id" to t(ID), "estado" to t("listo"), "modo" to t("completa"), "lugar" to t("casa"),
                        "casa_equipos" to (if (nombre == "casaVigente") parsear("""[{"tipo":"mancuernas","kg":20},{"tipo":"banco_plano"}]""") else ValorJson.Lista(emptyList())),
                        "casa_sin_equipo" to ValorJson.Booleano(nombre != "casaVigente"),
                    )
                }
                "casaConGimnasioVigente" -> {
                    d.palancaCasa = true
                    d.vigente = linkedMapOf(
                        "id" to t(ID), "estado" to t("listo"), "modo" to t("completa"), "resultado" to t("adaptada"),
                        "publicado_en" to t("2026-11-12T15:00:00+00:00"), "equipos" to EQUIPOS,
                    )
                }
                "listo", "listoSinCambios" -> {
                    d.vigente = linkedMapOf(
                        "id" to t(ID), "estado" to t("listo"), "modo" to t("completa"), "resultado" to t(if (nombre == "listo") "adaptada" else "sin_cambios"),
                        "publicado_en" to t("2026-11-12T15:00:00+00:00"), "equipos" to EQUIPOS,
                    )
                }
            }
            return d
        }
    }
}
