package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AjusteComida

/**
 * Los ajustes de porciones del día (feedback de clientes del 20-oct): sumar o restar kcal a una comida, gramos a mano,
 * «Hoy no la como» y compensar en la siguiente. La cuenta es de `AjustePorciones` (reglas); lo de HOY vive en el
 * [ModeloApp]: en el teléfono (`ajustes_<dieta>.json`, solo el día) y en la base (`mypump_ajustes_dieta`, una fila por día,
 * por la cola), para que Mati lo pueda ver y para que el cliente lo encuentre en otro teléfono. Sin la migración
 * nativa_004 (PGRST202) queda solo en el teléfono, como cualquier otra cosa que todavía no tiene tabla. Gemelo de
 * AjustesDieta.swift.
 */
object AjustesDieta {
    const val KIND = "ajustes_dieta"

    /** Una op por día en la cola: la última gana. */
    fun clave(fecha: String): String = "ajustes_dieta_$fecha"

    fun archivo(dietaId: String): String = "ajustes_$dietaId.json"

    /** Lo que va a disco: los ajustes de UN día (el de hoy). Al cambiar de día no valen. */
    fun guardados(fecha: String, comidas: Map<String, AjusteComida>): ValorJson =
        ValorJson.objeto("fecha" to ValorJson.Texto(fecha), "comidas" to aValor(comidas))

    fun aValor(comidas: Map<String, AjusteComida>): ValorJson = ValorJson.Objeto(comidas.mapValues { it.value.aValor() })

    /** Un mapa de ajustes por comida; null si no es un objeto o algo de adentro no es un ajuste (como el `Decodable` de iOS). */
    fun comidasDesde(v: ValorJson?): Map<String, AjusteComida>? {
        val o = v as? ValorJson.Objeto ?: return null
        val r = o.campos.mapValues { AjusteComida.desde(it.value) }
        return if (r.values.all { it != null }) r.mapValues { it.value!! } else null
    }
}
