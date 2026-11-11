package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.DietaActiva
import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.Suplementacion
import com.pumpteam.mypump.reglas.AreaPlan
import com.pumpteam.mypump.reglas.FotoPlan
import com.pumpteam.mypump.reglas.NovedadesPlan
import com.pumpteam.mypump.reglas.ParteNovedad
import com.pumpteam.mypump.reglas.ResumenNovedad
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Una novedad guardada: lo que cambió en una publicación de Mati y si el alumno ya la vio. */
data class NovedadPlan(
    val id: String,
    /** Cuándo la detectó el teléfono (ms desde 1970). */
    val fecha: Double,
    val titular: String,
    val resumen: String,
    val partes: List<ParteNovedad>,
    val vista: Boolean = false,
) {
    constructor(id: String, fecha: Double, r: ResumenNovedad, vista: Boolean = false) :
        this(id, fecha, r.titular, r.resumen, r.partes, vista)

    fun aJson(): JsonElement = buildJsonObject {
        put("id", id); put("fecha", fecha); put("titular", titular); put("resumen", resumen); put("vista", vista)
        put("partes", buildJsonArray {
            for (p in partes) add(buildJsonObject {
                put("area", p.area); put("titular", p.titular); put("grande", p.grande)
                put("lineas", JsonArray(p.lineas.map(::JsonPrimitive)))
            })
        })
    }

    companion object {
        private fun JsonObject.txt(k: String): String? = (this[k] as? JsonPrimitive)?.takeIf { it.isString }?.content

        /** Igual que el Codable de iOS: si falta algo, no hay novedad. */
        fun desde(e: JsonElement): NovedadPlan? {
            val o = e as? JsonObject ?: return null
            val partes = (o["partes"] as? JsonArray)?.map { pe ->
                val p = pe as? JsonObject ?: return null
                ParteNovedad(
                    p.txt("area") ?: return null, p.txt("titular") ?: return null,
                    (p["grande"] as? JsonPrimitive)?.booleanOrNull ?: return null,
                    (p["lineas"] as? JsonArray)?.map { (it as? JsonPrimitive)?.content ?: return null } ?: return null,
                )
            } ?: return null
            return NovedadPlan(
                o.txt("id") ?: return null, (o["fecha"] as? JsonPrimitive)?.doubleOrNull ?: return null,
                o.txt("titular") ?: return null, o.txt("resumen") ?: return null, partes,
                (o["vista"] as? JsonPrimitive)?.booleanOrNull ?: false,
            )
        }
    }
}

/**
 * «Novedades de tu plan» (2.3.0, palanca `novedades_plan`). Gemelo de Novedades.swift: el plan que el alumno ya vio queda
 * en `novedades_base.json`; cuando llega otro, [NovedadesPlan.calcular] dice qué cambió y se guarda en `novedades.json`
 * (las últimas 12). La base no está en el servidor: desde la 013 publicar pisa la versión anterior.
 */
class ModeloNovedades(private val disco: Disco?, private val ahora: () -> Long = System::currentTimeMillis) {
    private val _lista = MutableStateFlow(disco?.leer(ARCHIVO_LISTA)?.let(::leerLista) ?: emptyList())

    /** La más nueva primero. */
    val lista: StateFlow<List<NovedadPlan>> = _lista.asStateFlow()

    /** La demo y las capturas: una lista armada, sin disco. */
    constructor(muestra: List<NovedadPlan>) : this(null) { _lista.value = muestra }

    /** La que se muestra sola al abrir: la más nueva sin ver. */
    val pendiente: NovedadPlan? get() = _lista.value.firstOrNull { !it.vista }

    /** La tarjeta de Entreno: la última, durante [DIAS_TARJETA] días. */
    fun reciente(lista: List<NovedadPlan> = _lista.value): NovedadPlan? =
        lista.firstOrNull()?.takeIf { ahora() - it.fecha < DIAS_TARJETA * 86_400_000.0 }

    @Synchronized
    fun marcarVista(id: String) {
        val l = _lista.value
        val i = l.indexOfFirst { it.id == id }
        if (i < 0 || l[i].vista) return
        _lista.value = l.toMutableList().also { it[i] = l[i].copy(vista = true) }
        guardarLista()
    }

    /** Lo que llegó en esta carga, por área. */
    sealed interface Entrada {
        data object NoLlego : Entrada
        data object Ninguna : Entrada
        data class Hay(val valor: JsonElement) : Entrada
    }

    /**
     * Compara lo que llegó con lo que ya se vio, guarda la base nueva y, si cambió algo, la novedad. [semilla]: lo que
     * había en el teléfono antes de esta carga, por si todavía no hay base. [soloConBase]: sin base no se arranca una.
     */
    @Synchronized
    fun observar(
        rutina: Entrada, dieta: Entrada, suplementacion: Entrada,
        semilla: Triple<Entrada, Entrada, Entrada> = Triple(Entrada.NoLlego, Entrada.NoLlego, Entrada.NoLlego),
        soloConBase: Boolean = false,
    ): NovedadPlan? {
        val d = disco ?: return null
        val guardada = d.leer(ARCHIVO_BASE) as? JsonObject
        if (soloConBase && guardada == null) return null
        val antes: Map<String, JsonElement?> = guardada?.let { g -> AREAS.associateWith { g[it] } }
            ?: mapOf("rutina" to guardar(semilla.first), "dieta" to guardar(semilla.second), "suplementacion" to guardar(semilla.third))
        val nueva = antes.toMutableMap()
        guardar(rutina)?.let { nueva["rutina"] = it }
        guardar(dieta)?.let { nueva["dieta"] = it }
        guardar(suplementacion)?.let { nueva["suplementacion"] = it }
        val nuevaJson = JsonObject(nueva.filterValues { it != null }.mapValues { it.value!! })
        if (nuevaJson != guardada) d.guardar(ARCHIVO_BASE, nuevaJson)

        val fotoAntes = FotoPlan(area(antes["rutina"], RutinaActiva::desde), area(antes["dieta"], DietaActiva::desde), suplementacion(antes["suplementacion"]))
        val fotoDespues = FotoPlan(area(guardar(rutina), RutinaActiva::desde), area(guardar(dieta), DietaActiva::desde), suplementacion(guardar(suplementacion)))
        val r = NovedadesPlan.calcular(fotoAntes, fotoDespues) ?: return null
        val n = NovedadPlan(UUID.randomUUID().toString(), ahora().toDouble(), r)
        // Las anteriores quedan vistas: se muestra la de esta publicación, nunca una vieja que no se llegó a abrir.
        _lista.value = (listOf(n) + _lista.value.map { it.copy(vista = true) }).take(MAXIMO)
        guardarLista()
        return n
    }

    /**
     * Con la palanca apagada: se borra el plan «ya visto» (la lista de novedades guardadas no se toca). Así, al volver a
     * prenderla, se compara contra la copia de la última carga y no contra una base de hace semanas (un resumen enorme).
     */
    @Synchronized
    fun olvidarBase() {
        disco?.borrar(ARCHIVO_BASE)
    }

    private fun guardarLista() {
        disco?.guardar(ARCHIVO_LISTA, JsonArray(_lista.value.map { it.aJson() }))
    }

    companion object {
        internal const val ARCHIVO_BASE = "novedades_base.json"
        internal const val ARCHIVO_LISTA = "novedades.json"
        const val MAXIMO = 12
        const val DIAS_TARJETA = 7
        private val AREAS = listOf("rutina", "dieta", "suplementacion")

        private fun leerLista(e: JsonElement): List<NovedadPlan> = (e as? JsonArray)?.mapNotNull(NovedadPlan::desde) ?: emptyList()

        /** Un área como se guarda: `{"hay":false}` = el servidor dijo que no hay; sin la clave = no se sabe. */
        private fun guardar(e: Entrada): JsonElement? = when (e) {
            Entrada.NoLlego -> null
            Entrada.Ninguna -> buildJsonObject { put("hay", false) }
            is Entrada.Hay -> buildJsonObject { put("hay", true); put("valor", e.valor) }
        }

        private fun <T> area(a: JsonElement?, f: (JsonElement) -> T): AreaPlan<T> {
            val o = a as? JsonObject ?: return AreaPlan.Desconocida
            if ((o["hay"] as? JsonPrimitive)?.booleanOrNull != true) return AreaPlan.Ninguna
            val v = o["valor"]?.takeUnless { it is JsonNull } ?: return AreaPlan.Desconocida
            return try { AreaPlan.Hay(f(v)) } catch (_: Exception) { AreaPlan.Desconocida }
        }

        private fun suplementacion(a: JsonElement?): AreaPlan<Suplementacion> = when (val x = area(a) { PlanSuplementacion.desde(it) }) {
            is AreaPlan.Hay -> x.valor?.let { AreaPlan.Hay(it.suplementacion) } ?: AreaPlan.Ninguna
            AreaPlan.Ninguna -> AreaPlan.Ninguna
            AreaPlan.Desconocida -> AreaPlan.Desconocida
        }
    }
}
