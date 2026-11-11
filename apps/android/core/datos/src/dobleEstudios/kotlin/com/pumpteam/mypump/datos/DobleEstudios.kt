package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlinx.serialization.json.Json

/**
 * El servidor de «Estudios y órdenes» de mentira: sigue `estudios/CONTRATO_APP.md` en memoria. Lo usan las pruebas JVM y las
 * de interfaz (este directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red y todo lo que muestra es
 * inventado: no hay un solo dato de una persona real.
 */
class DobleEstudios : Transporte {
    class Archivo(val id: String, val mime: String, val bytes: ByteArray)
    class Envio(val id: String, val pedidoId: String?, var estado: String = "borrador", val archivos: MutableList<Archivo> = ArrayList())

    @Volatile var palanca = true
    @Volatile var sinFuncion = false
    @Volatile var habilitado = true
    @Volatile var sinRed = false
    @Volatile var tokenCaido = false
    @Volatile var topeDia = false
    /** Cuántas veces `enviar` contesta `faltan_archivos` antes de aceptar. */
    @Volatile var faltanVeces = 0
    /** Un error con el que `envio_nuevo` o `enviar` contestan en vez de atender (para los que la app no conoce). */
    @Volatile var errorEnvioNuevo: String? = null
    @Volatile var errorEnviar: String? = null
    /** El status con el que fallan `envio_nuevo` y `enviar` (400: un parámetro que el servidor no acepta). */
    @Volatile var statusDeEscritura: Int? = null
    /** La imagen que se baja al abrir un estudio propio (las pruebas de interfaz ponen una que se pueda ver). */
    @Volatile var imagenParaVer: ByteArray = JPEG_MINIMO

    /** Estados forzados para las próximas subidas, en orden. 0 = sin red en esa. */
    val proximasSubidas = ArrayDeque<Int>()
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()
    var proximo: ValorJson? = null
    val pendientes = ArrayList<MutableMap<String, ValorJson>>()
    val ordenes = ArrayList<MutableMap<String, ValorJson>>()
    val estudios = ArrayList<Map<String, ValorJson>>()
    val envios = java.util.concurrent.CopyOnWriteArrayList<Envio>()
    var cabecerasUltimaSubida: Map<String, String> = emptyMap()
    var ultimoHecho: ValorJson? = null
    var ultimoUrls: ValorJson? = null
    /** Los `p_ids` de cada `novedades_vistas`, en orden. */
    val vistasPedidas = java.util.concurrent.CopyOnWriteArrayList<List<String>>()
    /** `controles_app` en la config. Sin prender, la app no llama a `mypump_controles_get`. */
    @Volatile var palancaControles = false
    /** `mypump_controles_get` no existe (PGRST202). */
    @Volatile var controlesSinFuncion = false
    /** Corre antes de contestar `mypump_controles_get` (para apagar la palanca mientras la respuesta viaja). */
    @Volatile var antesDeControles: (() -> Unit)? = null
    /** Lo que contesta `mypump_controles_get` (sin próximo ni últimos, de entrada). */
    @Volatile var controles: ValorJson = parsear("""{"habilitado":true,"hoy":"$HOY","proximo":null,"ultimos":[]}""")

    val llamadasEstudios: List<String> get() = llamadas.filter { "estudios" in it }
    val intentosDeSubida: Int get() = llamadas.count { it == "estudios/upload" }
    val enviados: List<Envio> get() = envios.filter { it.estado == "enviado" }

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        val ruta = pedido.ruta
        val f = ruta.substringAfterLast('/')
        val nombre = when {
            "/estudios/archivo/" in ruta -> "estudios/archivo"
            "/estudios/" in ruta -> "estudios/$f"
            else -> f
        }
        llamadas += nombre
        if (sinRed) throw IOException("sin red (doble)")
        if (nombre == "estudios/archivo") return@synchronized Respuesta(200, if (f.endsWith(".pdf")) pdfDePrueba(2) else imagenParaVer)
        val (status, cuerpo) = atender(nombre, pedido)
        Respuesta(status, cuerpo.toByteArray())
    }

    private fun cuerpo(p: Pedido): ValorJson = p.cuerpo?.let { ValorJson.desde(Json.parseToJsonElement(it.toString(Charsets.UTF_8))) } ?: ValorJson.Nulo
    private val si = ValorJson.Booleano(true)
    private fun t(s: String) = ValorJson.Texto(s)

    private fun atender(nombre: String, p: Pedido): Pair<Int, String> {
        if (nombre == "mypump_get_app_config") return 200 to """{"estudios_app":$palanca,"controles_app":${palanca && palancaControles}}"""
        if (nombre == "mypump_controles_get") {
            antesDeControles?.invoke()
            if (controlesSinFuncion) return 404 to """{"code":"PGRST202","message":"no existe"}"""
            if (tokenCaido) return 200 to "null"
            return 200 to if (palancaControles) controles.serializar() else """{"habilitado":false}"""
        }
        // Una cuenta inventada, para las pruebas que arman `ModeloApp` entero.
        if (nombre == "mypump_get_cliente_info") return 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
        if (nombre.startsWith("mypump_estudios") && sinFuncion) return 404 to """{"code":"PGRST202","message":"no existe"}"""
        if (nombre.startsWith("mypump_estudios") && tokenCaido) return 200 to "null"
        if (nombre == "mypump_estudios_envio_nuevo" || nombre == "mypump_estudios_enviar") {
            statusDeEscritura?.let { return it to """{"code":"22023","message":"forzado (doble)"}""" }
            (if (nombre.endsWith("nuevo")) errorEnvioNuevo else errorEnviar)?.let { return 200 to """{"ok":false,"error":"$it"}""" }
        }
        return when (nombre) {
            "mypump_estudios_get" -> if (!habilitado) 200 to """{"habilitado":false}""" else 200 to vista().serializar()
            "mypump_estudios_envio_nuevo" -> 200 to envioNuevo(cuerpo(p))
            "mypump_estudios_enviar" -> 200 to enviarEnvio(cuerpo(p))
            "mypump_estudios_hecho" -> 200 to hecho(cuerpo(p))
            "mypump_estudios_novedades_vistas" -> 200 to novedadesVistas(cuerpo(p))
            "estudios/upload" -> subida(p)
            "estudios/urls" -> urls(cuerpo(p))
            else -> 200 to "[]"
        }
    }

    private fun envioNuevo(j: ValorJson): String {
        if (!habilitado) return """{"ok":false,"error":"no_habilitado"}"""
        val id = j["p_id"]?.comoTexto ?: return """{"ok":false,"error":"id_repetido"}"""
        envios.firstOrNull { it.id == id }?.let { return """{"ok":true,"ya":true,"id":"$id","estado":"${it.estado}"}""" }
        if (topeDia) return """{"ok":false,"error":"tope_dia"}"""
        envios += Envio(id, j["p_pedido_id"]?.comoTexto)
        return """{"ok":true,"ya":false,"id":"$id","estado":"borrador"}"""
    }

    private fun subida(p: Pedido): Pair<Int, String> {
        if (proximasSubidas.isNotEmpty()) {
            val s = proximasSubidas.removeFirst()
            if (s == 0) throw IOException("corte (doble)")
            if (s != 200) return s to """{"ok":false,"error":"forzado"}"""
        }
        val h = p.cabeceras
        cabecerasUltimaSubida = h
        val id = h["x-estudios-archivo"] ?: return 400 to """{"ok":false}"""
        val envio = envios.firstOrNull { it.id == h["x-estudios-envio"] } ?: return 404 to """{"ok":false}"""
        if (envio.estado != "borrador") return 409 to """{"ok":false}"""
        if (envio.archivos.any { it.id == id }) return 200 to """{"ok":true,"ya":true}"""
        if (envio.archivos.size >= 20) return 413 to """{"ok":false}"""
        val bytes = p.archivo?.readBytes() ?: p.cuerpo ?: ByteArray(0)
        val mime = h["Content-Type"]
        val esPdf = mime == "application/pdf" && bytes.size > 5 && String(bytes, 0, 5, Charsets.US_ASCII) == "%PDF-"
        val esJpeg = mime == "image/jpeg" && bytes.size > 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xD8.toByte()
        if (!esPdf && !esJpeg) return 400 to """{"ok":false,"error":"formato"}"""
        if (bytes.size > 20 * 1024 * 1024) return 413 to """{"ok":false}"""
        envio.archivos += Archivo(id, mime!!, bytes)
        return 200 to """{"ok":true}"""
    }

    private fun enviarEnvio(j: ValorJson): String {
        val e = envios.firstOrNull { it.id == j["p_id"]?.comoTexto } ?: return """{"ok":false,"error":"no_encontrado"}"""
        if (e.estado != "borrador") return """{"ok":true,"ya":true,"estado":"enviado"}"""
        if (e.archivos.isEmpty()) return """{"ok":false,"error":"sin_archivos"}"""
        val dice = j["p_archivos"]?.comoNumero?.toInt()
        if (faltanVeces > 0 || (dice != null && e.archivos.size < dice)) {
            if (faltanVeces > 0) faltanVeces--
            return """{"ok":false,"error":"faltan_archivos","hay":${e.archivos.size}}"""
        }
        e.estado = "enviado"
        return """{"ok":true,"ya":false,"estado":"enviado"}"""
    }

    private fun hecho(j: ValorJson): String {
        ultimoHecho = j
        val p = pendientes.firstOrNull { it["id"] == j["p_pedido_id"] } ?: return """{"ok":false,"error":"no_encontrado"}"""
        val fecha = j["p_fecha"]?.comoTexto
        if (fecha == null) {
            p["estado"] = t("pedido")
            p["hecho_fecha"] = ValorJson.Nulo
            return """{"ok":true,"estado":"pedido"}"""
        }
        val f = java.time.LocalDate.parse(fecha)
        val hoy = java.time.LocalDate.parse(HOY)
        if (f.isAfter(hoy.plusDays(1)) || f.isBefore(hoy.minusDays(120))) return """{"ok":false,"error":"fecha"}"""
        p["estado"] = t("hecho")
        p["hecho_fecha"] = t(fecha)
        return """{"ok":true,"estado":"hecho"}"""
    }

    /** Solo lo propio y lo que seguía sin ver; lo demás se ignora. */
    private fun novedadesVistas(j: ValorJson): String {
        if (!habilitado) return """{"ok":false,"error":"no_habilitado"}"""
        val ids = (j["p_ids"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: return """{"ok":false,"error":"ids"}"""
        vistasPedidas += ids
        var marcadas = 0
        for (fila in pendientes + ordenes) {
            if (fila["nuevo"] == si && fila["id"]?.comoTexto in ids) {
                fila["nuevo"] = ValorJson.Booleano(false)
                marcadas++
            }
        }
        return """{"ok":true,"marcadas":$marcadas}"""
    }

    private fun urls(j: ValorJson): Pair<Int, String> {
        ultimoUrls = j
        val id = j["id"]?.comoTexto
        return when (j["clase"]?.comoTexto) {
            "orden" -> {
                val o = ordenes.firstOrNull { it["id"]?.comoTexto == id } ?: return 404 to """{"ok":false}"""
                if (o["vigente"] != si) return 404 to """{"ok":false}"""
                200 to """{"ok":true,"archivos":[{"url":"https://ejemplo.invalid/estudios/archivo/orden.pdf","mime":"application/pdf"}],"expira_en":600}"""
            }
            "estudio" -> {
                val e = estudios.firstOrNull { it["id"]?.comoTexto == id } ?: return 404 to """{"ok":false}"""
                if (e["se_puede_abrir"] != si) return 409 to """{"ok":false,"error":"todavia_no"}"""
                200 to """{"ok":true,"archivos":[{"url":"https://ejemplo.invalid/estudios/archivo/hoja.jpg","mime":"image/jpeg"},{"url":"https://ejemplo.invalid/estudios/archivo/estudio.pdf","mime":"application/pdf"}],"expira_en":600}"""
            }
            else -> 400 to """{"ok":false}"""
        }
    }

    private fun vista(): ValorJson = ValorJson.objeto(
        "habilitado" to si, "hoy" to t(HOY),
        // Como el servidor: pedidos a la vista (no los ya hechos) y órdenes vigentes que todavía no se vieron.
        "novedades" to ValorJson.Numero(
            (pendientes.count { it["nuevo"] == si && it["estado"]?.comoTexto != "hecho" } + ordenes.count { it["nuevo"] == si && it["vigente"] == si }).toDouble(),
        ),
        "topes" to ValorJson.objeto("archivos_por_envio" to ValorJson.Numero(20.0), "mb_por_archivo" to ValorJson.Numero(20.0)),
        "proximo_control" to (proximo ?: ValorJson.Nulo),
        "pendientes" to ValorJson.Lista(pendientes.map { ValorJson.Objeto(LinkedHashMap(it)) }),
        "ordenes" to ValorJson.Lista(ordenes.map { ValorJson.Objeto(LinkedHashMap(it)) }),
        "estudios" to ValorJson.Lista(estudios.map { ValorJson.Objeto(it) }),
        "envios" to ValorJson.Lista(
            envios.map {
                ValorJson.objeto(
                    "id" to t(it.id), "estado" to t(it.estado), "archivos" to ValorJson.Numero(it.archivos.size.toDouble()),
                    "pedido_id" to (it.pedidoId?.let(::t) ?: ValorJson.Nulo), "enviado_en" to if (it.estado == "enviado") t("${HOY}T15:00:00Z") else ValorJson.Nulo,
                )
            },
        ),
    )

    companion object {
        const val HOY = "2026-11-10"
        val ESCENARIOS_CONTROLES = setOf("controlesApagado", "sinControl", "controlLejano", "controlEnVentana", "controlOrdenes")
        const val PEDIDO_LAB = "22222222-2222-4222-8222-222222222201"
        const val PEDIDO_ECO = "22222222-2222-4222-8222-222222222202"
        const val PEDIDO_HECHO = "22222222-2222-4222-8222-222222222203"
        const val ORDEN_LAB = "33333333-3333-4333-8333-333333333301"
        const val ORDEN_VENCIDA = "33333333-3333-4333-8333-333333333302"
        const val ESTUDIO_VISTO = "44444444-4444-4444-8444-444444444401"
        const val ESTUDIO_RECIBIDO = "44444444-4444-4444-8444-444444444402"

        /** El JPEG más chico que empieza como un JPEG (para la cola; no es una imagen que se pueda ver). */
        val JPEG_MINIMO = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 1, 2, 3)

        private fun parsear(s: String) = ValorJson.desde(Json.parseToJsonElement(s))
        private fun mapa(s: String): MutableMap<String, ValorJson> = LinkedHashMap((parsear(s) as ValorJson.Objeto).campos)

        /** Un PDF de verdad, de [paginas] hojas A4, con un texto inventado: lo abre cualquier lector. */
        fun pdfDePrueba(paginas: Int = 1): ByteArray {
            val objetos = ArrayList<String>()
            val hijos = (0 until paginas).joinToString(" ") { "${4 + it * 2} 0 R" }
            objetos += "<< /Type /Catalog /Pages 2 0 R >>"
            objetos += "<< /Type /Pages /Kids [$hijos] /Count $paginas >>"
            objetos += "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
            for (i in 0 until paginas) {
                val texto = "BT /F1 26 Tf 72 740 Td (Documento de prueba) Tj 0 -40 Td /F1 16 Tf (Hoja ${i + 1} de $paginas. Sin datos reales.) Tj ET"
                objetos += "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>"
                objetos += "<< /Length ${texto.length} >>\nstream\n$texto\nendstream"
            }
            val s = ByteArrayOutputStream()
            fun escribir(x: String) = s.write(x.toByteArray(Charsets.US_ASCII))
            escribir("%PDF-1.4\n")
            val posiciones = ArrayList<Int>()
            objetos.forEachIndexed { i, o ->
                posiciones += s.size()
                escribir("${i + 1} 0 obj\n$o\nendobj\n")
            }
            val xref = s.size()
            escribir("xref\n0 ${objetos.size + 1}\n0000000000 65535 f \n")
            posiciones.forEach { escribir("%010d 00000 n \n".format(it)) }
            escribir("trailer\n<< /Size ${objetos.size + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n")
            return s.toByteArray()
        }

        fun escenario(nombre: String): DobleEstudios {
            val d = DobleEstudios()
            when (nombre) {
                "apagado" -> d.palanca = false
                "sinServidor" -> d.sinFuncion = true
                "noHabilitado" -> d.habilitado = false
                "vacio" -> Unit
                "rechazo" -> d.proximasSubidas.add(400)
                "reintento" -> d.proximasSubidas.add(503)
                "corte" -> d.proximasSubidas.addAll(listOf(200, 0))
                "topeDia" -> d.topeDia = true
                "completo", "novedad", "ordenNueva", "soloOrdenNueva" -> {
                    d.proximo = parsear("""{"tipo":"laboratorio","titulo":"Análisis de laboratorio","desde":"2026-11-23","hasta":"2026-11-29"}""")
                    d.pendientes += mapa("""{"id":"$PEDIDO_LAB","tipo":"laboratorio","titulo":"Análisis de laboratorio","detalle":null,"desde":null,"hasta":"2026-11-19","estado":"pedido","hecho_fecha":null,"orden_id":"$ORDEN_LAB"}""")
                    d.pendientes += mapa("""{"id":"$PEDIDO_ECO","tipo":"ecocardiograma","titulo":"Ecocardiograma","detalle":null,"desde":null,"hasta":"2026-11-05","estado":"pedido","hecho_fecha":null,"orden_id":null}""")
                    d.pendientes += mapa("""{"id":"$PEDIDO_HECHO","tipo":"ecografia","titulo":"Ecografía","detalle":null,"desde":"2026-11-16","hasta":"2026-11-20","estado":"hecho","hecho_fecha":"2026-11-09","orden_id":null}""")
                    d.ordenes += mapa("""{"id":"$ORDEN_LAB","tipo":"laboratorio","titulo":"Análisis de laboratorio","emitida":"2026-11-03","vence":"2027-01-02","vigente":true}""")
                    d.ordenes += mapa("""{"id":"$ORDEN_VENCIDA","tipo":"ergometria","titulo":"Ergometría","emitida":"2026-08-20","vence":"2026-10-19","vigente":false}""")
                    d.estudios += mapa("""{"id":"$ESTUDIO_VISTO","tipo":"laboratorio","titulo":"Análisis de laboratorio","fecha":"2026-08-14","hojas":4,"estado":"visto","recibido_en":"2026-08-15T13:02:11Z","se_puede_abrir":true}""")
                    d.estudios += mapa("""{"id":"$ESTUDIO_RECIBIDO","tipo":"ecografia","titulo":"Ecografía","fecha":null,"hojas":1,"estado":"recibido","recibido_en":"2026-11-04T13:02:11Z","se_puede_abrir":false}""")
                    when (nombre) {
                        // Un pedido y su orden sin ver: la tarjeta de arriba dice «estudio nuevo», y adentro las dos llevan «Nuevo».
                        "novedad" -> {
                            d.pendientes.first { it["id"]?.comoTexto == PEDIDO_ECO }["nuevo"] = ValorJson.Booleano(true)
                            d.ordenes.first { it["id"]?.comoTexto == ORDEN_LAB }["nuevo"] = ValorJson.Booleano(true)
                        }
                        // Solo una orden sin ver.
                        "ordenNueva" -> d.ordenes.first { it["id"]?.comoTexto == ORDEN_LAB }["nuevo"] = ValorJson.Booleano(true)
                        // Solo una orden sin ver y nada por hacer.
                        "soloOrdenNueva" -> {
                            d.pendientes.clear()
                            d.ordenes.first { it["id"]?.comoTexto == ORDEN_LAB }["nuevo"] = ValorJson.Booleano(true)
                        }
                    }
                }
            }
            // Controles de salud (`controles_app`), sobre «completo»: apagada con un control cargado, prendida sin control, uno
            // lejano, uno dentro de la ventana de aviso y uno con las órdenes ya enviadas. Fechas inventadas, con hoy = 10/11.
            if (nombre in ESCENARIOS_CONTROLES) {
                val base = escenario("completo")
                fun control(fecha: String, avisar: String, estado: String) =
                    """{"titulo_alumno":"Control de salud","fecha_objetivo":"$fecha","avisar_desde":"$avisar","estado":"$estado"}"""
                fun controles(proximo: String) {
                    base.controles = parsear("""{"habilitado":true,"hoy":"$HOY","proximo":$proximo,"ultimos":[${control("2026-10-01", "2026-09-24", "revisado")}]}""")
                }
                when (nombre) {
                    "controlesApagado" -> controles(control("2026-11-16", "2026-11-09", "programado"))
                    "sinControl" -> base.palancaControles = true
                    "controlLejano" -> { base.palancaControles = true; controles(control("2026-12-30", "2026-12-23", "programado")) }
                    "controlEnVentana" -> { base.palancaControles = true; controles(control("2026-11-16", "2026-11-09", "programado")) }
                    "controlOrdenes" -> { base.palancaControles = true; controles(control("2026-11-16", "2026-11-09", "ordenes_enviadas")) }
                }
                return base
            }
            return d
        }
    }
}
