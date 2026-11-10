package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasMolestia
import com.pumpteam.mypump.reglas.ReglasSupleEstado
import java.io.IOException
import kotlinx.serialization.json.Json

/**
 * El servidor de feedback de mentira: sigue `supabase/propuestas/nativa_feedback_alumno.sql` en memoria. Lo usan las pruebas JVM
 * y las de interfaz (este directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red. Gemelo de DobleFeedback.swift.
 */
class DobleFeedback : Transporte {
    @Volatile var meDuele = true
    @Volatile var supleEstado = true
    @Volatile var sinFuncion = false
    @Volatile var sinRed = false
    @Volatile var tope = false
    /** Falla la próxima marca de suplemento con un 500. */
    @Volatile var fallaMarcar = false
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()
    val molestias = java.util.concurrent.CopyOnWriteArrayList<Map<String, ValorJson>>()
    val marcas = java.util.concurrent.ConcurrentHashMap<String, String>()
    /** Los ítems que la suplementación del alumno tiene, por clave → es protector. */
    val items = java.util.concurrent.ConcurrentHashMap(
        mapOf("creatina monohidrato" to false, "omega 3" to false, "cafeina" to false, "magnesio glicinato" to false, "telmisartan" to true),
    )
    @Volatile var ultimoRegistro: ValorJson? = null

    val llamadasFeedback: List<String> get() = llamadas.filter { "feedback" in it || "molestia" in it || "suple_marcar" in it }

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        val nombre = pedido.ruta.substringAfterLast('/')
        llamadas += nombre
        if (sinRed) throw IOException("sin red (doble)")
        val (status, cuerpo) = atender(nombre, pedido)
        Respuesta(status, cuerpo.toByteArray())
    }

    private fun cuerpo(p: Pedido): ValorJson = p.cuerpo?.let { ValorJson.desde(Json.parseToJsonElement(it.toString(Charsets.UTF_8))) } ?: ValorJson.Nulo

    private fun atender(nombre: String, p: Pedido): Pair<Int, String> = when {
        nombre == "mypump_get_app_config" -> 200 to """{"me_duele":$meDuele,"suple_estado":$supleEstado}"""
        nombre in PROPIAS && sinFuncion -> 404 to """{"code":"PGRST202","message":"no existe"}"""
        nombre == "mypump_feedback_get" -> 200 to ValorJson.objeto(
            "me_duele" to ValorJson.objeto(
                "habilitado" to ValorJson.Booleano(meDuele),
                "molestias" to ValorJson.Lista(if (meDuele) molestias.map { ValorJson.Objeto(it) } else emptyList()),
            ),
            "suple_estado" to ValorJson.objeto(
                "habilitado" to ValorJson.Booleano(supleEstado),
                "items" to ValorJson.Lista(
                    if (supleEstado) marcas.toSortedMap().map { ValorJson.objeto("item" to ValorJson.Texto(it.key), "estado" to ValorJson.Texto(it.value), "nota" to ValorJson.Nulo) } else emptyList(),
                ),
            ),
        ).serializar()
        nombre == "mypump_molestia_registrar" -> registrar(cuerpo(p))
        nombre == "mypump_suple_marcar" -> marcar(cuerpo(p))
        else -> 200 to "[]"
    }

    private fun registrar(j: ValorJson): Pair<Int, String> {
        ultimoRegistro = j
        if (!meDuele) return 200 to """{"ok":false,"error":"apagado"}"""
        if (tope) return 200 to """{"ok":false,"error":"tope"}"""
        val id = j["p_id"]?.comoTexto
        val ej = j["p_ejercicio_id"]?.comoTexto?.takeIf { it.isNotEmpty() }
        val zona = j["p_zona"]?.comoTexto?.takeIf(ReglasMolestia::zonaValida)
        val n = j["p_intensidad"]?.comoNumero?.takeIf { it in 0.0..10.0 }
        if (id == null || ej == null || zona == null || n == null) return 200 to """{"ok":false,"error":"datos"}"""
        fun campo(c: String) = j[c] ?: ValorJson.Nulo
        val m = linkedMapOf(
            "id" to ValorJson.Texto(id), "ejercicio_id" to ValorJson.Texto(ej), "ejercicio_nombre" to campo("p_ejercicio_nombre"), "zona" to ValorJson.Texto(zona),
            "lado" to campo("p_lado"), "desde" to campo("p_desde"), "cuando" to campo("p_cuando"), "tipo" to campo("p_tipo"),
            "intensidad" to ValorJson.Numero(n), "nota" to campo("p_nota"), "estado" to ValorJson.Texto("avisada"),
        )
        // Una abierta por ejercicio: volver a avisar la corrige y conserva su id.
        val i = molestias.indexOfFirst { it["id"]?.comoTexto == id || (it["ejercicio_id"]?.comoTexto == ej && it["estado"]?.comoTexto == "avisada") }
        val ya = i >= 0
        if (ya) {
            m["id"] = molestias[i]["id"]!!
            molestias[i] = m
        } else {
            molestias.add(0, m)
        }
        return 200 to ValorJson.objeto("ok" to ValorJson.Booleano(true), "ya" to ValorJson.Booleano(ya), "molestia" to ValorJson.Objeto(m)).serializar()
    }

    private fun marcar(j: ValorJson): Pair<Int, String> {
        if (fallaMarcar) {
            fallaMarcar = false
            return 500 to """{"message":"caído"}"""
        }
        if (!supleEstado) return 200 to """{"ok":false,"error":"apagado"}"""
        val k = ReglasSupleEstado.clave(j["p_item"]?.comoTexto ?: "")
        val e = j["p_estado"]?.comoTexto?.takeIf { ReglasSupleEstado.Estado.de(it) != null } ?: return 200 to """{"ok":false,"error":"datos"}"""
        if (items[k] != false) return 200 to """{"ok":false,"error":"item"}"""
        val ya = marcas[k] == e
        marcas[k] = e
        return 200 to ValorJson.objeto("ok" to ValorJson.Booleano(true), "ya" to ValorJson.Booleano(ya), "item" to ValorJson.Texto(k), "estado" to ValorJson.Texto(e)).serializar()
    }

    companion object {
        val PROPIAS = listOf("mypump_feedback_get", "mypump_molestia_registrar", "mypump_suple_marcar")

        /** ¿Esta llamada la contesta el doble? Para las pruebas de interfaz, que mezclan este doble con el resto del servidor de prueba. */
        fun esSuya(funcion: String): Boolean = funcion in PROPIAS || funcion == "mypump_get_app_config"

        /** `vacio`, `avisada` (una molestia abierta en cada ejercicio de [ejercicios]), `resuelta`, `marcado`, `apagado`. */
        fun escenario(nombre: String, ejercicios: List<String> = emptyList()): DobleFeedback {
            val d = DobleFeedback()
            when (nombre) {
                "apagado" -> { d.meDuele = false; d.supleEstado = false }
                "avisada", "resuelta" -> ejercicios.forEachIndexed { n, id ->
                    d.molestias += mapOf(
                        "id" to ValorJson.Texto("11111111-1111-4111-8111-%012d".format(n)), "ejercicio_id" to ValorJson.Texto(id), "ejercicio_nombre" to ValorJson.Texto("Ejercicio"),
                        "zona" to ValorJson.Texto("hombro"), "lado" to ValorJson.Texto("derecho"), "desde" to ValorJson.Texto("esta_semana"), "cuando" to ValorJson.Texto("al_subir"),
                        "tipo" to ValorJson.Texto("sordo"), "intensidad" to ValorJson.Numero(5.0), "nota" to ValorJson.Nulo, "estado" to ValorJson.Texto(nombre),
                    )
                }
                "marcado" -> { d.marcas["creatina monohidrato"] = "tomando"; d.marcas["omega 3"] = "comprado" }
                else -> Unit   // "vacio": prendido, sin nada
            }
            return d
        }
    }
}
