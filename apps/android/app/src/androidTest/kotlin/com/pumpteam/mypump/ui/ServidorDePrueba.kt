package com.pumpteam.mypump.ui

import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.delay

/**
 * El backend de las pruebas de interfaz: nunca toca la red. Contesta con las respuestas REALES grabadas de la cuenta
 * `test-nativa-real` (`apps/shared/fixtures`, que van en los assets del APK de pruebas), las mismas de los tests de :core y
 * de iOS, y anota cada llamada.
 *
 * Solo [TOKEN] es una cuenta: cualquier otro token recibe `[]` de `mypump_get_cliente_info`, que es lo que contesta la
 * base con un link revocado ("Este link ya no sirve").
 */
class ServidorDePrueba : Transporte {
    data class Llamada(val funcion: String, val cuerpo: String)

    val llamadas = CopyOnWriteArrayList<Llamada>()

    /** Sin señal: cada pedido tira una IOException (para la cola es falta de red, no un rechazo). */
    @Volatile var sinRed = false

    /** El servicio contesta 503 ("Servicio fuera de línea"). */
    @Volatile var caido = false

    /** Cuánto tarda cada respuesta (una red lenta). */
    @Volatile var demoraMs = 0L

    /** Respuestas propias por función (`mypump_get_chat` → `[…]`); ganan sobre las grabadas. */
    val respuestas = ConcurrentHashMap<String, String>()

    init {
        // Sin la tabla de la palanca remota: vale la de fábrica.
        respuestas["mypump_get_app_config"] = SIN_FUNCION
    }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val funcion = pedido.ruta.substringAfterLast('/')
        val cuerpo = pedido.cuerpo?.toString(Charsets.UTF_8) ?: ""
        llamadas += Llamada(funcion, cuerpo)
        if (demoraMs > 0) delay(demoraMs)
        if (sinRed) throw IOException("sin conexión (prueba)")
        if (caido) return Respuesta(503, """{"message":"servicio caído (prueba)"}""".toByteArray())
        // Revisión: las fotos de progreso y los relojes no son RPC (ver el bloque de Revisión, abajo).
        rutaDeRevision(pedido.ruta, cuerpo)?.let { return it }
        // Dieta: la visión y lo que la cuenta guarda de la dieta (ver el bloque de Dieta, abajo).
        rutaDeDieta(pedido.ruta, funcion, cuerpo)?.let { return it }
        val token = Regex("\"p_token\":\"([^\"]*)\"").find(cuerpo)?.groupValues?.get(1)
        val propia = respuestas[funcion]
        val (status, texto) = when {
            propia == SIN_FUNCION -> 404 to """{"code":"PGRST202","details":null,"hint":null,"message":"Could not find the function public.$funcion"}"""
            funcion == "mypump_get_cliente_info" && token != TOKEN -> 200 to "[]"
            propia != null -> 200 to propia
            funcion.startsWith("mypump_get_") -> 200 to (grabada(funcion.removePrefix("mypump_")) ?: "[]")
            // Las escrituras salen bien (la cola las da por guardadas).
            funcion.startsWith("mypump_") -> 200 to "true"
            // Tablas (el catálogo de ejercicios) y servicios aparte: vacío.
            else -> 200 to "[]"
        }
        return Respuesta(status, texto.toByteArray())
    }

    /** Las llamadas a una función, con su cuerpo (para ver qué se mandó). */
    fun a(funcion: String): List<String> = llamadas.filter { it.funcion == funcion }.map { it.cuerpo }

    // ── Revisión: las rutas que no son RPC ─────────────────────────────────────────────────────────────────────────
    // Las fotos de progreso van al servicio de la Mini (`/progreso/upload` y `/progreso/urls`) y los relojes se preguntan
    // al sitio (`/api/wearables/disponibles`). Antes todo lo que no era `mypump_*` contestaba `[]`. En `llamadas` quedan
    // con el último tramo de la ruta: `upload`, `urls` y `disponibles`.

    /** Lo que llegó a `/progreso/upload`. */
    data class FotoSubida(val pose: String, val fecha: String, val dataUrl: String)

    val fotosSubidas = CopyOnWriteArrayList<FotoSubida>()

    /** Las fotos de la cuenta (lunes de la semana → poses): las contestan `get_fotos_progreso` y `/progreso/urls`. */
    private val fotosDeLaCuenta = ConcurrentHashMap<String, MutableSet<String>>()

    /** Subir una foto se queda sin red (lo demás contesta): la cola de fotos la guarda y reintenta sin gastar intentos. */
    @Volatile var fotosSinRed = false

    /** Los relojes que el servidor tiene habilitados (`/api/wearables/disponibles`): ninguno, como sin credenciales. */
    @Volatile var relojes: List<String> = emptyList()

    /** La cuenta ya tiene estas fotos (lunes → poses), como si se hubieran subido antes. */
    fun ponerFotos(porSemana: Map<String, List<String>>) {
        for ((lunes, poses) in porSemana) fotosDeLaCuenta.getOrPut(lunes) { java.util.Collections.synchronizedSet(LinkedHashSet()) } += poses
        actualizarFotos()
    }

    /** Cuántas veces se pidieron las URLs firmadas. Cada firma da URLs distintas, como el servicio real. */
    @Volatile var firmas = 0

    /** La URL firmada de prueba de una foto (https, para que `ImagenRemota` la pida), la de la firma [firma]. */
    fun urlDeFoto(lunes: String, pose: String, firma: Int = firmas): String = "https://fotos.prueba.invalid/$lunes/$pose.jpg?firma=$firma"

    private fun actualizarFotos() {
        val filas = fotosDeLaCuenta.entries.sortedBy { it.key }.flatMap { (lunes, poses) ->
            poses.toList().map { """{"semana_lunes":"$lunes","pose":"$it","tomada_el":"$lunes","created_at":"${lunes}T12:00:00+00:00"}""" }
        }
        respuestas["mypump_get_fotos_progreso"] = filas.joinToString(",", "[", "]")
    }

    // Con los nombres enteros (sin tocar los imports de arriba, que comparten otras pantallas).
    private fun rutaDeRevision(ruta: String, cuerpo: String): Respuesta? = when (ruta) {
        "/progreso/upload" -> {
            if (fotosSinRed) throw IOException("sin conexión para las fotos (prueba)")
            val o = kotlinx.serialization.json.Json.parseToJsonElement(cuerpo) as kotlinx.serialization.json.JsonObject
            fun campo(k: String) = (o[k] as? kotlinx.serialization.json.JsonPrimitive)?.content ?: ""
            if (campo("token") != TOKEN) {
                Respuesta(401, """{"ok":false,"error":"token inválido"}""".toByteArray())
            } else {
                fotosSubidas += FotoSubida(campo("pose"), campo("fecha"), campo("imagen_base64"))
                ponerFotos(mapOf(com.pumpteam.mypump.reglas.FotosProgreso.lunes(campo("fecha")) to listOf(campo("pose"))))
                Respuesta(200, """{"ok":true}""".toByteArray())
            }
        }
        "/progreso/urls" -> {
            firmas += 1
            val fotos = fotosDeLaCuenta.entries.flatMap { (lunes, poses) ->
                poses.toList().map { """{"semana_lunes":"$lunes","pose":"$it","url":"${urlDeFoto(lunes, it)}"}""" }
            }
            Respuesta(200, """{"ok":true,"fotos":${fotos.joinToString(",", "[", "]")}}""".toByteArray())
        }
        "/api/wearables/disponibles" ->
            Respuesta(200, """{"proveedores":${relojes.joinToString(",", "[", "]") { """{"id":"$it","nombre":"$it"}""" }}}""".toByteArray())
        else -> null
    }

    // ── Dieta con escritura: la visión, las comidas libres, los alimentos propios y los reemplazos ────────────────────
    // La foto del plato y la de la etiqueta van a mini-vision (`POST /vision`, no es RPC): contesta lo que ponga la prueba
    // en [vision]. Las comidas libres, los alimentos propios y los reemplazos de comida quedan guardados mientras dura la
    // prueba, como en la base (en las grabadas de la cuenta están vacíos): así reabrir la app los vuelve a traer. Una
    // respuesta propia en [respuestas] gana, como siempre. Con los nombres enteros (sin tocar los imports de arriba).

    /** Lo que llegó a `/vision`: el tipo ("plato" o "etiqueta") y la foto como data URL. */
    data class FotoVision(val tipo: String, val dataUrl: String)

    val fotosVision = CopyOnWriteArrayList<FotoVision>()

    /** Lo que contesta `/vision` según el tipo: el status y el cuerpo (`{"ok":true,"data":{…}}` o `{"ok":false,"error":"…"}`). */
    @Volatile var vision: (tipo: String) -> Pair<Int, String> = { 503 to """{"ok":false,"error":"servicio de visión no configurado (prueba)"}""" }

    /** Borrar una comida libre falla (500): la fila tiene que volver a aparecer. */
    @Volatile var borrarComidaLibreFalla = false

    private val comidasLibres = CopyOnWriteArrayList<org.json.JSONObject>()
    private val alimentosPropios = CopyOnWriteArrayList<org.json.JSONObject>()
    private val reemplazos = ConcurrentHashMap<String, org.json.JSONObject>()

    /** Una comida libre que la cuenta ya tiene (de [fecha], "YYYY-MM-DD"). */
    fun ponerComidaLibre(fecha: String, descripcion: String, kcal: Double, prot: Double = 0.0, carb: Double = 0.0, fat: Double = 0.0, hora: String? = null) {
        comidasLibres += filaComidaLibre(fecha, hora, descripcion, kcal, prot, carb, fat, org.json.JSONObject.NULL)
    }

    /** Las comidas libres guardadas (las filas, como las devuelve la base). */
    fun comidasLibresGuardadas(): List<org.json.JSONObject> = comidasLibres.toList()

    fun alimentosPropiosGuardados(): List<org.json.JSONObject> = alimentosPropios.toList()

    /** Los reemplazos guardados: "comida|opción|alimento" → `food_data`. */
    fun reemplazosGuardados(): Map<String, org.json.JSONObject> =
        reemplazos.values.associate { "${it.getString("comida_id")}|${it.getInt("opt_idx")}|${it.getInt("food_idx")}" to it.getJSONObject("food_data") }

    private fun filaComidaLibre(fecha: String, hora: String?, descripcion: String, kcal: Double, prot: Double, carb: Double, fat: Double, detalle: Any): org.json.JSONObject =
        org.json.JSONObject()
            .put("id", java.util.UUID.randomUUID().toString())
            .put("cliente_id", "test-nativa-real")
            .put("fecha", fecha)
            // TIME de Postgres: "13:45:00".
            .put("hora", hora?.let { if (it.length == 5) "$it:00" else it } ?: org.json.JSONObject.NULL)
            .put("descripcion", descripcion)
            .put("kcal", kcal).put("prot", prot).put("carb", carb).put("fat", fat)
            .put("detalle", detalle)
            .put("created_at", java.time.Instant.now().toString())

    private fun lista(filas: List<org.json.JSONObject>): Respuesta = Respuesta(200, org.json.JSONArray(filas).toString().toByteArray())

    private fun rutaDeDieta(ruta: String, funcion: String, cuerpo: String): Respuesta? {
        if (ruta == "/vision") {
            val o = org.json.JSONObject(cuerpo)
            val tipo = o.optString("tipo")
            fotosVision += FotoVision(tipo, o.optString("imagen_base64"))
            if (o.optString("token") != TOKEN) return Respuesta(403, """{"ok":false,"error":"token inválido"}""".toByteArray())
            val (status, texto) = vision(tipo)
            return Respuesta(status, texto.toByteArray())
        }
        if (!funcion.startsWith("mypump_") || respuestas.containsKey(funcion)) return null
        val p = try {
            org.json.JSONObject(cuerpo)
        } catch (_: org.json.JSONException) {
            return null
        }
        if (p.optString("p_token") != TOKEN) return null
        fun num(k: String) = if (p.isNull(k)) 0.0 else p.optDouble(k, 0.0)
        return when (funcion) {
            "mypump_get_comidas_libres" -> {
                val fecha = p.optString("p_fecha")
                // ORDER BY hora NULLS LAST, created_at
                lista(comidasLibres.filter { it.getString("fecha") == fecha }.sortedBy { if (it.isNull("hora")) "~" else it.getString("hora") })
            }
            "mypump_crear_comida_libre" -> {
                val fila = filaComidaLibre(
                    p.getString("p_fecha"), if (p.isNull("p_hora")) null else p.getString("p_hora"), p.getString("p_descripcion"),
                    num("p_kcal"), num("p_prot"), num("p_carb"), num("p_fat"), p.opt("p_detalle") ?: org.json.JSONObject.NULL,
                )
                comidasLibres += fila
                lista(listOf(fila))
            }
            "mypump_borrar_comida_libre" -> {
                if (borrarComidaLibreFalla) return Respuesta(500, """{"message":"no se pudo borrar (prueba)"}""".toByteArray())
                val borrada = comidasLibres.removeIf { it.getString("id") == p.optString("p_id") }
                Respuesta(200, "$borrada".toByteArray())
            }
            "mypump_create_custom_food" -> {
                val fila = org.json.JSONObject()
                    .put("id", java.util.UUID.randomUUID().toString())
                    .put("name", p.getString("p_name").trim())
                    .put("kcal", num("p_kcal")).put("prot", num("p_prot")).put("carb", num("p_carb")).put("fat", num("p_fat"))
                    .put("unit", p.getString("p_unit"))
                    .put("unit_grams", if (p.isNull("p_unit_grams")) org.json.JSONObject.NULL else p.getDouble("p_unit_grams"))
                    .put("category", if (p.isNull("p_category")) org.json.JSONObject.NULL else p.getString("p_category"))
                alimentosPropios.removeIf { it.getString("name").lowercase() == fila.getString("name").lowercase() }
                alimentosPropios += fila
                lista(listOf(fila))
            }
            "mypump_get_custom_foods" -> lista(alimentosPropios.sortedBy { it.getString("name") })
            "mypump_save_food_swap" -> {
                val fila = org.json.JSONObject()
                    .put("dieta_id", p.getString("p_dieta_id")).put("comida_id", p.getString("p_comida_id"))
                    .put("opt_idx", p.getInt("p_opt_idx")).put("food_idx", p.getInt("p_food_idx"))
                    .put("food_data", p.getJSONObject("p_food_data"))
                reemplazos["${fila.getString("dieta_id")}|${fila.getString("comida_id")}|${fila.getInt("opt_idx")}|${fila.getInt("food_idx")}"] = fila
                lista(listOf(fila))
            }
            "mypump_delete_food_swap" -> {
                val k = "${p.getString("p_dieta_id")}|${p.getString("p_comida_id")}|${p.getInt("p_opt_idx")}|${p.getInt("p_food_idx")}"
                Respuesta(200, "${reemplazos.remove(k) != null}".toByteArray())
            }
            "mypump_get_food_swaps" -> lista(reemplazos.values.filter { it.getString("dieta_id") == p.optString("p_dieta_id") })
            else -> null
        }
    }

    companion object {
        /** El token de la cuenta de prueba de este servidor (inventado: no es de nadie). */
        const val TOKEN = "pruebaInterfazAndroid_0001"

        /** Para que una función conteste "no existe" (PGRST202). */
        const val SIN_FUNCION = "\u0000sin-funcion"

        private fun grabada(nombre: String): String? = try {
            InstrumentationRegistry.getInstrumentation().context.assets.open("test-nativa-real/$nombre.json").use {
                it.readBytes().toString(Charsets.UTF_8)
            }
        } catch (_: FileNotFoundException) {
            null
        }
    }
}
