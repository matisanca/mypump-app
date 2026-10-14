package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

// Filas de salud que no tenía Respuestas.kt: la recuperación con sus componentes (la escena "Mis datos" muestra cómo se
// arma el score) y los relojes que ofrece el servidor. Gemelo de MyPumpModelos/Salud.swift.

/** `get_recuperacion` entera ([Recuperacion] no trae `componentes`). La última fila es la más nueva. */
data class RecuperacionDia(
    val fecha: String,
    val score: Int? = null,
    val estado: String? = null,
    val banda: String? = null,
    val diasDatos: Int? = null,
    val bandaProvisoria: Boolean? = null,
    val estadoAutonomico: String? = null,
    val hrvMetrica: String? = null,
    val discordancia: Boolean? = null,
    /** `{sueno_min, fc_reposo, …}`: lo que ya se sabe mientras calibra. */
    val cobertura: ValorJson? = null,
    /** `{autonomico: {score, peso}, sueno: …, carga: …, subjetivo: …, otros: …}`. Los pesos vienen SIN normalizar. */
    val componentes: ValorJson? = null,
    /** `[{tipo, dir, valor, baseline, agudo}]`: hechos, la frase se arma en el cliente. */
    val motivos: ValorJson? = null,
) {
    companion object {
        fun desde(e: JsonElement): RecuperacionDia {
            val o = e.comoObjeto("RecuperacionDia")
            return RecuperacionDia(
                fecha = o.texto("fecha") ?: "", score = o.entero("score"), estado = o.texto("estado"), banda = o.texto("banda"),
                diasDatos = o.entero("dias_datos"), bandaProvisoria = o.booleano("banda_provisoria"),
                estadoAutonomico = o.texto("estado_autonomico"), hrvMetrica = o.texto("hrv_metrica"),
                discordancia = o.booleano("discordancia"), cobertura = o.valorJson("cobertura"),
                componentes = o.valorJson("componentes"), motivos = o.valorJson("motivos"),
            )
        }
    }
}

/** `GET /api/wearables/disponibles`: `{proveedores: [{id, nombre}]}`. */
data class ProveedoresDisponibles(val proveedores: List<Proveedor>) {
    data class Proveedor(val id: String, val nombre: String?)

    companion object {
        /**
         * Como el `Decodable` de iOS: la raíz tiene que ser un objeto; `proveedores` que no es un array vale vacío, y un
         * proveedor sin `id` de texto (o con un `nombre` que no es texto) se descarta sin tirar abajo a los demás.
         */
        fun desde(e: JsonElement): ProveedoresDisponibles {
            val o = e.comoObjeto("ProveedoresDisponibles")
            val lista = (o["proveedores"] as? JsonArray)?.mapNotNull { x ->
                val p = x as? JsonObject ?: return@mapNotNull null
                val id = (p["id"] as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content ?: return@mapNotNull null
                val nombre = when (val n = p["nombre"]) {
                    null, JsonNull -> null
                    is JsonPrimitive -> if (n.isString) n.content else return@mapNotNull null
                    else -> return@mapNotNull null
                }
                Proveedor(id, nombre)
            } ?: emptyList()
            return ProveedoresDisponibles(lista)
        }
    }
}
