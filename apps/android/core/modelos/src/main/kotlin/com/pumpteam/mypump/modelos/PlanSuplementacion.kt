package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * La pestaña Suplementación (2.1.0): una fila de `mypump_suplementacion(p_token)` (migración `entregas_015`, contrato en
 * `docs/NATIVA_CONTRATO.md`, sección 10). Token inválido o sin suplementación = cero filas (no hay pestaña).
 *
 * El jsonb tiene la misma forma que la suplementación de «Tu guía», así que se lee con [Suplementacion.desde]: los
 * mismos ítems, momentos y estados. Decodificación tolerante: los campos desconocidos se ignoran y un `esquema` mayor que
 * 1 se lee igual con lo que se entienda.
 */
data class PlanSuplementacion(
    val suplementacion: Suplementacion,
    /** `final` (después de la llamada) o `pre`. Hoy la app no lo muestra. */
    val fase: String?,
    /** ISO con zona: cuándo se escribió la versión que vino. */
    val actualizado: String?,
    /** Versión del contrato (hoy 1). Sin el campo, 1. */
    val esquema: Int,
) {
    /** Lo que se guarda en la caché del teléfono: la misma forma de la fila, así se lee con [desde]. */
    fun aValor(): ValorJson = ValorJson.objeto(
        "suplementacion" to suplementacion.crudo,
        "fase" to (fase?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "actualizado" to (actualizado?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "esquema" to ValorJson.Numero(esquema.toDouble()),
    )

    companion object {
        /** Una fila del RPC. null si no es un objeto o la suplementación no trae ningún ítem con nombre. */
        fun desde(e: JsonElement?): PlanSuplementacion? {
            val o = e as? JsonObject ?: return null
            val s = Suplementacion.desde(o["suplementacion"]) ?: return null
            return PlanSuplementacion(
                suplementacion = s,
                fase = o.cadena("fase")?.trim()?.ifEmpty { null },
                actualizado = o.cadena("actualizado")?.trim()?.ifEmpty { null },
                esquema = o.entero("esquema")?.takeIf { it > 0 } ?: 1,
            )
        }

        fun desde(v: ValorJson?): PlanSuplementacion? = v?.let { desde(it.aJson()) }
    }
}
