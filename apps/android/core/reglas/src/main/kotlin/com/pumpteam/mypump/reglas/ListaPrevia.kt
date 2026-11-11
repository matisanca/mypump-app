package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson

/**
 * La lista previa a la videollamada de comienzo (2.3.0, palanca `lista_previa`; gemelo de ListaPrevia.swift): lo que
 * devuelve `mypump_lista_previa` → lo que se muestra. La referencia es `scripts/nativa/generar-vectores-cola-a.py` y los
 * vectores de `apps/shared/vectores/lista_previa.json`.
 *
 * Solo con `ok` y `activa` en true. Un ítem vale si es un objeto con una clave conocida y un estado conocido; una clave
 * repetida, la primera. `opcional` solo si es true. `faltan` solo en la guía, si falta, y si es un entero >= 1. Sin ítems
 * válidos no se muestra nada. El orden es el del servidor.
 */
object ReglasListaPrevia {
    /** A dónde lleva tocar un punto que falta. */
    enum class Destino(val valor: String) {
        /** La guía de videos. */
        GUIA("guia"),

        /** Las fotos de Revisión. */
        FOTOS("fotos"),
    }

    data class Item(
        val clave: String,
        val titulo: String,
        val hecho: Boolean,
        val opcional: Boolean,
        val detalle: String?,
        /** null: la fila no es un botón. */
        val destino: Destino?,
        val accesible: String,
    )

    data class Vista(
        val items: List<Item>,
        /** «Llevás 1 de 3» o «Ya tenés todo listo»; null con solo opcionales. */
        val resumen: String?,
        val todoListo: Boolean,
    )

    const val TITULO = "Antes de la videollamada"
    const val TODO_LISTO = "Ya tenés todo listo"
    const val CONSEJO = "Ese día buscá un lugar tranquilo y con buena conexión."
    const val OPCIONAL = "Opcional"
    const val HECHO = "Hecho"
    const val FALTA = "Falta"

    /** Las claves que la app conoce (el orden que manda es el del servidor). */
    val TITULOS: Map<String, String> = linkedMapOf(
        "guia" to "Mirar los videos de tu guía",
        "dudas" to "Dejarle tus dudas a Mati",
        "formulario" to "Responder las preguntas de Mati",
        "fotos" to "Subir tus fotos de inicio",
        "estudios" to "Subir tus estudios",
        "contrato" to "Firmar el contrato",
    )
    val DESTINOS: Map<String, Destino> = mapOf("guia" to Destino.GUIA, "dudas" to Destino.GUIA, "fotos" to Destino.FOTOS)

    fun vista(j: ValorJson?): Vista? {
        if (j !is ValorJson.Objeto || j["ok"] != ValorJson.Booleano(true) || j["activa"] != ValorJson.Booleano(true)) return null
        val lista = (j["items"] as? ValorJson.Lista)?.elementos ?: return null
        val items = mutableListOf<Item>()
        val vistas = HashSet<String>()
        for (it in lista) {
            if (it !is ValorJson.Objeto) continue
            val clave = it["clave"]?.comoTexto ?: continue
            val estado = it["estado"]?.comoTexto ?: continue
            val titulo = TITULOS[clave] ?: continue
            if ((estado != "hecho" && estado != "falta") || !vistas.add(clave)) continue
            val hecho = estado == "hecho"
            val opcional = it["opcional"] == ValorJson.Booleano(true)
            val faltan = it["faltan"]?.comoNumero
            val detalle = when {
                !hecho && clave == "guia" && faltan != null && faltan.isFinite() && faltan == Math.rint(faltan) && faltan >= 1 && faltan < 1e9 ->
                    if (faltan.toInt() == 1) "Te falta 1 video" else "Te faltan ${faltan.toInt()} videos"
                !hecho && opcional -> OPCIONAL
                else -> null
            }
            val accesible = listOfNotNull(
                titulo,
                if (hecho) HECHO else if (opcional) detalle else FALTA,
                detalle.takeIf { !opcional },
            ).filter { it.isNotEmpty() }.joinToString(", ")
            items += Item(clave, titulo, hecho, opcional, detalle, if (hecho) null else DESTINOS[clave], accesible)
        }
        if (items.isEmpty()) return null
        val obligatorios = items.filter { !it.opcional }
        val hechos = obligatorios.count { it.hecho }
        val todo = obligatorios.isNotEmpty() && hechos == obligatorios.size
        val resumen = when {
            obligatorios.isEmpty() -> null
            todo -> TODO_LISTO
            else -> "Llevás $hechos de ${obligatorios.size}"
        }
        return Vista(items, resumen, todo)
    }
}
