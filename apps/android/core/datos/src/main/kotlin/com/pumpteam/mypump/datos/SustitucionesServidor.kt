package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * SER-14: las sustituciones de ejercicio también en el servidor (`supabase/migrations/nativa_003_sustituciones_ejercicio.sql`),
 * para que pasen de un teléfono a otro y no se pierdan al reinstalar. Es SustitucionesServidor.swift. El archivo de cada
 * rutina sigue siendo la copia de trabajo, como antes; el servidor es la referencia cuando contesta.
 *
 * - Cada cambio sale por la cola (`swap_ej` / `swap_ej_del`, con la misma clave: gana el último).
 * - La primera vez que un teléfono sincroniza una rutina SUBE lo que tenía guardado (`mypump_import_exercise_swaps`): lo
 *   de antes de la tabla o lo que trajo la migración. De ahí en más, LEE el servidor y lo pone por encima.
 * - Sin la migración en la base (PGRST202), sin red o con el token caído: todo sigue como antes, solo en el teléfono.
 */
object SustitucionesServidor {
    const val KIND_GUARDAR = "swap_ej"
    const val KIND_BORRAR = "swap_ej_del"

    /**
     * Lo mismo que acepta la base (`mypump_sustitucion_valida`), con margen en el tamaño: la base cuenta el texto con
     * espacios después de `:` y `,`.
     */
    private const val MAX_CLAVE = 120
    private const val MAX_TEXTO = 12_000
    private const val MAX_POR_RUTINA = 300

    fun clave(rutinaId: String, exId: String): String = "swap_ej_${rutinaId}_$exId"

    /**
     * Lo último que ya está en la cola. Si la app se cierra entre escribir el archivo de la rutina y encolar, al volver a
     * abrir se encola la diferencia (si no, la primera lectura del servidor borraría lo que nunca le llegó).
     */
    fun archivoEncoladas(rutinaId: String): String = "ejercicios-swaps-encoladas_$rutinaId.json"

    /** Lo que se recuerda en el teléfono sobre la sincronización de una rutina (mismo archivo y campos que en iOS). */
    data class Estado(
        /** Lo de este teléfono ya se subió una vez: de ahí en más se lee el servidor. */
        val subidas: Boolean,
        /**
         * La migración del almacenamiento viejo se repitió (el cliente volvió a la app vieja): lo que trajo es lo último que
         * hizo y, en la próxima sincronización, reemplaza a lo del servidor.
         */
        val reemplazar: Boolean = false,
    ) {
        fun aValor(): ValorJson = ValorJson.objeto("subidas" to ValorJson.Booleano(subidas), "reemplazar" to ValorJson.Booleano(reemplazar))

        companion object {
            fun archivo(rutinaId: String): String = "ejercicios-swaps-sync_$rutinaId.json"

            fun leer(disco: Disco?, rutinaId: String): Estado? {
                val o = disco?.leer(archivo(rutinaId)) as? JsonObject ?: return null
                val subidas = (o["subidas"] as? JsonPrimitive)?.booleanOrNull ?: return null
                return Estado(subidas, (o["reemplazar"] as? JsonPrimitive)?.booleanOrNull ?: false)
            }
        }
    }

    /** Lo que el servidor acepta. Lo que no (nunca pasó con datos reales), queda solo en el teléfono. */
    internal fun subible(exId: String, v: ValorJson): Boolean =
        v is ValorJson.Objeto && exId.length in 1..MAX_CLAVE && v.serializar().toByteArray(Charsets.UTF_8).size <= MAX_TEXTO

    /** Lo que sube la primera sincronización. Si pasa del tope de la base, no sube nada (quedan en el teléfono, como antes). */
    fun subibles(m: Map<String, ValorJson>): Map<String, ValorJson>? {
        val r = m.filter { subible(it.key, it.value) }
        return if (r.size <= MAX_POR_RUTINA) r else null
    }

    data class Op(val kind: String, val payload: ValorJson, val clave: String, val exId: String)

    /** Las ops para pasar de `antes` a `ahora`, en un orden fijo (las claves ordenadas). */
    fun operaciones(antes: Map<String, ValorJson>, ahora: Map<String, ValorJson>, rutinaId: String): List<Op> {
        val ops = mutableListOf<Op>()
        for (exId in (antes.keys + ahora.keys).sorted()) {
            val a = antes[exId]
            val n = ahora[exId]
            val base = linkedMapOf<String, ValorJson>("rutinaId" to ValorJson.Texto(rutinaId), "exId" to ValorJson.Texto(exId))
            when {
                n != null && a != n -> {
                    if (!subible(exId, n)) continue
                    base["swap"] = n
                    ops += Op(KIND_GUARDAR, ValorJson.Objeto(base), clave(rutinaId, exId), exId)
                }
                n == null && a != null -> ops += Op(KIND_BORRAR, ValorJson.Objeto(base), clave(rutinaId, exId), exId)
            }
        }
        return ops
    }

    /**
     * El mapa que queda después de leer el servidor: lo del servidor, con lo que todavía está en la cola por encima (es más
     * nuevo), lo que se tocó mientras se esperaba la respuesta (la respuesta puede no traerlo) y lo que el servidor no
     * acepta (nunca se subió: si no, se perdería).
     */
    fun combinar(
        servidor: Map<String, ValorJson>,
        local: Map<String, ValorJson>,
        pendientes: Map<String, Operacion>,
        rutinaId: String,
        tocadas: Set<String>,
    ): Map<String, ValorJson> {
        val r = LinkedHashMap(servidor.filterValues { it is ValorJson.Objeto })
        val prefijo = "swap_ej_${rutinaId}_"
        for ((k, op) in pendientes) {
            if (!k.startsWith(prefijo)) continue
            val exId = op.payload["exId"]?.comoTexto ?: continue
            when (op.kind) {
                KIND_GUARDAR -> op.payload["swap"]?.let { r[exId] = it }
                KIND_BORRAR -> r.remove(exId)
            }
        }
        for (exId in tocadas) {
            val v = local[exId]
            if (v != null) r[exId] = v else r.remove(exId)
        }
        for ((exId, v) in local) if (!subible(exId, v)) r[exId] = v
        return r
    }
}
