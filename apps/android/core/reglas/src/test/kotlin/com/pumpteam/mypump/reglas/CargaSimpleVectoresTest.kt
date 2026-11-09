package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.Progresion
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS (`apps/shared/vectores/carga_simple.json`): las mismas respuestas en las dos apps. */
class CargaSimpleVectoresTest {
    private val v: JsonObject = Vectores.json(Vectores.publico("carga_simple"))

    private fun igual(a: Any?, b: Any?, m: String = "") = assertEquals(a, b, m)

    private fun JsonObject.lista(k: String): List<JsonObject> = getValue(k).jsonArray.map { it.jsonObject }
    private fun JsonObject.presente(k: String): JsonElement? = this[k]?.takeIf { it !is JsonNull }
    private fun JsonObject.d(k: String): Double? = presente(k)?.jsonPrimitive?.doubleOrNull
    private fun JsonObject.t(k: String): String? = presente(k)?.jsonPrimitive?.content
    private fun equipo(s: String) = Preparacion.Equipo.valueOf(s.uppercase())

    private fun ejercicio(c: JsonObject, nombre: String = "Press banca con barra", tipo: String = "compuesto"): Ejercicio = Ejercicio(
        id = "x", nombre = nombre, tipo = tipo,
        progresion = c.lista("progresion").map {
            Progresion(semana = it.getValue("semana").jsonPrimitive.int, series = it.getValue("series").jsonPrimitive.int, reps = it.getValue("reps").jsonPrimitive.content, titulo = it.t("titulo"))
        },
    )

    private fun texto(a: CargaSimple.Aumento): String = when (a) {
        CargaSimple.Aumento.NoCorresponde -> "noCorresponde"
        CargaSimple.Aumento.Descartado -> "descartado"
        is CargaSimple.Aumento.Sugerido -> "sugerido:${Js.texto(a.desde)}:${Js.texto(a.hasta)}"
        is CargaSimple.Aumento.Aceptado -> "aceptado:${Js.texto(a.desde)}:${Js.texto(a.hasta)}"
    }

    @Test fun corresponde() {
        val casos = v.lista("corresponde")
        assertTrue(casos.size >= 25)
        for (c in casos) {
            igual(c.getValue("espera").jsonPrimitive.boolean, AumentoCarga.corresponde(ejercicio(c, tipo = c.t("tipo") ?: "compuesto"), c.getValue("semana").jsonPrimitive.int, c.t("mensaje")), c.t("caso") ?: "")
        }
    }

    @Test fun hastaMoverModaGuardia() {
        for (h in v.lista("hasta")) igual(h.d("espera"), AumentoCarga.hasta(h.d("desde")!!, equipo(h.t("equipo")!!)), "$h")
        for (m in v.lista("mover")) igual(m.d("espera"), AumentoCarga.mover(m.d("desde")!!, m.getValue("pasos").jsonPrimitive.int, equipo(m.t("equipo")!!)), "$m")
        for (m in v.lista("moda")) igual(m.d("espera"), AumentoCarga.moda(m.getValue("kilos").jsonArray.map { it.jsonPrimitive.double }), "$m")
        for (g in v.lista("guardia")) {
            var s = GuardiaOK()
            g.d("desde")?.let { s = s.levantar(1, it) }
            val serie = g.getValue("serie").jsonPrimitive.int
            val espera = g.getValue("espera").jsonObject
            igual(espera.getValue("doble").jsonPrimitive.boolean, s.esDobleToque(serie, g.d("ahora")!!), g.t("caso")!!)
            igual(espera.getValue("segundo").jsonPrimitive.boolean, s.esSegundoToque(serie, g.d("ahora")!!), g.t("caso")!!)
        }
    }

    @Test fun escenarios() {
        val todos = v.lista("escenarios")
        assertTrue(todos.size >= 17)
        for (e in todos) {
            val caso = e.t("caso")!!
            val s = CargaSimple(
                ejercicio(e, nombre = e.t("nombre") ?: "Press banca con barra"), e.getValue("semana").jsonPrimitive.int,
                e.lista("ultimaVez").map { CargaSimple.Referencia(it.getValue("reps").jsonPrimitive.int, it.d("kg")) }, equipo(e.t("equipo")!!),
            )
            for (p in e.lista("pasos")) {
                val valor = p.presente("valor")?.jsonPrimitive
                val i = p.presente("i")?.jsonPrimitive?.intOrNull
                val espera = p.presente("espera")?.jsonObject
                when (val accion = p.t("accion")) {
                    "moverCarga" -> s.moverCarga(valor!!.int)
                    "fijarCarga" -> s.fijarCarga(valor?.doubleOrNull)
                    "aceptar" -> s.aceptarAumento()
                    "descartar" -> s.descartarAumento()
                    "ajustarReps" -> s.ajustarReps(i!!, valor!!.int)
                    "mismoPeso" -> s.usarMismoPeso(valor!!.booleanOrNull!!)
                    "mirar" -> {
                        espera?.t("aumento")?.let { igual(it, texto(s.aumento), caso) }
                        espera?.d("carga")?.let { igual(it, s.carga, caso) }
                    }
                    "ok", "okInsistir" -> {
                        val ahora = p.d("ahora")!!
                        val r = s.evaluarOK(i!!, ahora, insistio = accion == "okInsistir")
                        val res = espera?.t("res")
                        when {
                            r == CargaSimple.Evaluacion.FaltanDatos && res == "faltanDatos" -> Unit
                            r == CargaSimple.Evaluacion.Guardia && res == "guardia" -> Unit
                            r is CargaSimple.Evaluacion.Lista && res == "lista" -> {
                                igual(espera?.d("reps")?.toInt(), r.reps, caso)
                                igual(espera?.d("kg"), r.kg, caso)
                                s.series = s.series.mapIndexed { n, x -> if (n == i) x.copy(reps = r.reps, kg = r.kg, confirmada = true) else x }
                                s.anotarOK(ahora)
                            }
                            else -> fail("$caso: $r ≠ $res")
                        }
                    }
                    else -> fail("acción desconocida: $accion")
                }
            }
            val f = e.presente("final")?.jsonObject ?: continue
            f.d("carga")?.let { igual(it, s.carga, caso) }
            f.t("aumento")?.let { igual(it, texto(s.aumento), caso) }
            f.presente("reps")?.let { r -> igual(r.jsonArray.map { it.jsonPrimitive.int }, s.series.indices.map { s.reps(it) }, caso) }
            f.presente("kg")?.let { k -> igual(k.jsonArray.map { it.jsonPrimitive.double }, s.series.map { it.kg }, caso) }
            f.d("confirmadas")?.let { igual(it.toInt(), s.confirmadas, caso) }
            f.d("hechasConOtraCarga")?.let { igual(it.toInt(), s.hechasConOtraCarga, caso) }
        }
    }
}
