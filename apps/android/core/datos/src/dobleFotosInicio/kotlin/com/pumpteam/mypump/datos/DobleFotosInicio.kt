package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FotosInicio
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.serialization.json.Json

/**
 * El servidor de las fotos de inicio de mentira: sigue `docs/NATIVA_CONTRATO.md` (sección 13) en memoria. Lo usan las pruebas
 * JVM y las de interfaz (este directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red.
 */
class DobleFotosInicio : Transporte {
    data class Foto(val id: String, val pose: String, val bytes: ByteArray, val tomada: String?, val ancho: Int, val alto: Int)

    @Volatile var palanca = true
    @Volatile var sinFuncion = false
    @Volatile var habilitado = true
    @Volatile var tokenCaido = false
    @Volatile var sinRed = false
    @Volatile var nota = ""
    @Volatile var maxMotivacion = FotosInicio.MAX_MOTIVACION

    /** Estados forzados para las próximas subidas, en orden. 0 = sin red en esa. */
    val proximasSubidas = ArrayDeque<Int>()
    val llamadas = CopyOnWriteArrayList<String>()
    val fotos = CopyOnWriteArrayList<Foto>()
    /** Cuántas veces se pidió `nota` y con qué. */
    val notasRecibidas = CopyOnWriteArrayList<String>()
    var cabecerasUltimaSubida: Map<String, String> = emptyMap()

    /** Lo que se llamó de las fotos de inicio (las RPC y mini-vision). */
    val llamadasFotosInicio: List<String> get() = llamadas.filter { "inicio" in it }
    val intentosDeSubida: Int get() = llamadas.count { it == "inicio/upload" }
    fun dePose(p: String): List<Foto> = fotos.filter { it.pose == p }

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        val ruta = pedido.ruta
        val f = ruta.substringAfterLast('/')
        val nombre = if ("/inicio/" in ruta) "inicio/$f" else f
        llamadas += nombre
        if (sinRed) throw IOException("sin red (doble)")
        val (status, cuerpo) = atender(nombre, pedido)
        Respuesta(status, cuerpo.toByteArray())
    }

    private fun cuerpo(p: Pedido): ValorJson = try {
        p.cuerpo?.let { ValorJson.desde(Json.parseToJsonElement(it.toString(Charsets.UTF_8))) } ?: ValorJson.Nulo
    } catch (_: Exception) {
        ValorJson.Nulo
    }

    private fun t(s: String) = ValorJson.Texto(s)
    private val si = ValorJson.Booleano(true)

    private fun atender(nombre: String, p: Pedido): Pair<Int, String> {
        if (nombre == "mypump_get_app_config") return 200 to """{"fotos_inicio":$palanca}"""
        if (nombre.startsWith("mypump_fotos_inicio") && sinFuncion) return 404 to """{"code":"PGRST202","message":"no existe"}"""
        if (nombre.startsWith("inicio/") && sinFuncion) return 404 to """{"ok":false}"""
        return when (nombre) {
            "mypump_fotos_inicio_get" -> when {
                tokenCaido -> 200 to "null"
                !habilitado -> 200 to """{"habilitado":false}"""
                else -> 200 to vista().serializar()
            }
            "mypump_fotos_inicio_nota" -> {
                val n = cuerpo(p)["p_nota"]?.comoTexto ?: ""
                notasRecibidas += n
                when {
                    tokenCaido -> 200 to "null"
                    !habilitado -> 200 to """{"ok":false,"error":"no_habilitado"}"""
                    else -> {
                        nota = FotosInicio.notaRecortada(n)
                        200 to ValorJson.objeto("ok" to si, "nota" to t(nota)).serializar()
                    }
                }
            }
            "inicio/upload" -> subida(p)
            "inicio/urls" -> {
                if (!tokenValido(cuerpo(p)["token"]?.comoTexto)) return 403 to """{"ok":false}"""
                200 to ValorJson.objeto(
                    "ok" to si,
                    "fotos" to ValorJson.Lista(fotos.map { ValorJson.objeto("id" to t(it.id), "pose" to t(it.pose), "url" to t("https://ejemplo.invalid/inicio/${it.id}.jpg")) }),
                ).serializar()
            }
            "inicio/borrar" -> {
                val c = cuerpo(p)
                if (!tokenValido(c["token"]?.comoTexto)) return 403 to """{"ok":false}"""
                val f = fotos.firstOrNull { it.id == c["foto_id"]?.comoTexto } ?: return 404 to """{"ok":false}"""
                if (f.pose != FotosInicio.MOTIVACION) return 400 to """{"ok":false,"error":"solo_motivacion"}"""
                fotos.remove(f)
                200 to """{"ok":true}"""
            }
            else -> 200 to "[]"
        }
    }

    private fun tokenValido(token: String?): Boolean = !token.isNullOrEmpty() && !tokenCaido && habilitado

    private fun subida(p: Pedido): Pair<Int, String> {
        if (proximasSubidas.isNotEmpty()) {
            val s = proximasSubidas.removeFirst()
            if (s == 0) throw IOException("corte (doble)")
            if (s != 200) return s to """{"ok":false,"error":"forzado"}"""
        }
        val h = p.cabeceras
        cabecerasUltimaSubida = h
        if (!tokenValido(h["x-inicio-token"])) return 403 to """{"ok":false}"""
        val id = h["x-inicio-foto"] ?: return 400 to """{"ok":false}"""
        val pose = h["x-inicio-pose"]
        if (pose != FotosInicio.MOTIVACION && FotosInicio.pose(pose ?: "") == null) return 400 to """{"ok":false}"""
        val bytes = p.cuerpo ?: ByteArray(0)
        fotos.firstOrNull { it.id == id }?.let { return if (it.pose == pose) 200 to """{"ok":true,"ya":true}""" else 409 to """{"ok":false}""" }
        if (!jpegEntero(bytes)) return 400 to """{"ok":false,"error":"no_jpeg"}"""
        if (bytes.size > 4 * 1024 * 1024) return 413 to """{"ok":false,"error":"pesada"}"""
        val (ancho, alto) = medidas(bytes)
        val lado = maxOf(ancho, alto)
        if (lado > 0 && lado < (if (pose == FotosInicio.MOTIVACION) FotosInicio.MIN_LADO_MOTIVACION else FotosInicio.MIN_LADO)) return 422 to """{"ok":false}"""
        if (pose == FotosInicio.MOTIVACION) {
            if (dePose(FotosInicio.MOTIVACION).size >= maxMotivacion) return 413 to """{"ok":false,"error":"tope"}"""
        } else {
            fotos.removeAll { it.pose == pose }   // la del cuerpo reemplaza a la de esa pose
        }
        fotos += Foto(id, pose!!, bytes, h["x-inicio-tomada"], ancho, alto)
        return 200 to """{"ok":true}"""
    }

    private fun vista(): ValorJson {
        val completo = FotosInicio.poses.all { p -> fotos.any { it.pose == p.clave } }
        return ValorJson.objeto(
            "habilitado" to si,
            "completo" to ValorJson.Booleano(completo),
            "completado_en" to if (completo) t("2026-11-10T17:00:00+00:00") else ValorJson.Nulo,
            "nota" to t(nota),
            "max_motivacion" to ValorJson.Numero(maxMotivacion.toDouble()),
            "campo_del_futuro" to t("no rompe"),
            "fotos" to ValorJson.Lista(
                fotos.map {
                    ValorJson.objeto(
                        "id" to t(it.id), "pose" to t(it.pose), "tomada_en" to (it.tomada?.let(::t) ?: ValorJson.Nulo),
                        "ancho" to ValorJson.Numero(it.ancho.toDouble()), "alto" to ValorJson.Numero(it.alto.toDouble()),
                    )
                },
            ),
        )
    }

    companion object {
        /** Empieza con FF D8 y termina con FF D9: lo mínimo de un JPEG entero. */
        fun jpegEntero(b: ByteArray): Boolean =
            b.size >= 4 && b[0] == 0xFF.toByte() && b[1] == 0xD8.toByte() && b[b.size - 2] == 0xFF.toByte() && b[b.size - 1] == 0xD9.toByte()

        /** Ancho y alto del primer SOF (0 y 0 si no se encuentra): como mide el servidor. */
        fun medidas(b: ByteArray): Pair<Int, Int> {
            var i = 2
            fun u(k: Int) = b[k].toInt() and 0xFF
            while (i + 9 < b.size) {
                if (u(i) != 0xFF) return 0 to 0
                val marca = u(i + 1)
                val largo = (u(i + 2) shl 8) or u(i + 3)
                if (marca in 0xC0..0xCF && marca != 0xC4 && marca != 0xC8 && marca != 0xCC) {
                    return ((u(i + 7) shl 8) or u(i + 8)) to ((u(i + 5) shl 8) or u(i + 6))
                }
                i += 2 + largo
            }
            return 0 to 0
        }

        private const val ID_FRENTE = "11111111-1111-4111-8111-111111111111"
        private const val ID_PERFIL = "22222222-2222-4222-8222-222222222222"
        private const val ID_ESPALDA = "33333333-3333-4333-8333-333333333333"

        fun escenario(nombre: String): DobleFotosInicio {
            val d = DobleFotosInicio()
            fun foto(id: String, pose: String) = Foto(id, pose, ByteArray(0), "2026-11-09T10:00:00-03:00", 1200, 1600)
            when (nombre) {
                "apagado" -> d.palanca = false
                "sinServidor" -> d.sinFuncion = true
                "noHabilitado" -> d.habilitado = false
                "tokenCaido" -> d.tokenCaido = true
                "dos" -> {
                    d.fotos += foto(ID_FRENTE, "frente")
                    d.fotos += foto(ID_PERFIL, "perfil")
                }
                "completo" -> {
                    d.fotos += foto(ID_FRENTE, "frente")
                    d.fotos += foto(ID_PERFIL, "perfil")
                    d.fotos += foto(ID_ESPALDA, "espalda")
                    d.nota = "Los hombros"
                }
                "topeMotivacion" -> repeat(FotosInicio.MAX_MOTIVACION) { d.fotos += foto("4444444$it-4444-4444-8444-444444444444", FotosInicio.MOTIVACION) }
                "corte" -> d.proximasSubidas.addAll(listOf(200, 0))
                "rechazo" -> d.proximasSubidas.add(400)
                "reintento" -> d.proximasSubidas.add(503)
            }
            return d
        }
    }
}
