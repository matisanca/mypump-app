package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson

/**
 * SER-14: las sustituciones de ejercicio también en el servidor (`supabase/migrations/nativa_003_sustituciones_ejercicio.sql`),
 * para que pasen de un teléfono a otro y no se pierdan al reinstalar. Es SustitucionesServidor.swift. El archivo de cada
 * rutina sigue siendo la copia de trabajo, como antes; el servidor la respalda y la comparte.
 *
 * - Cada entrada lleva `_ts`: cuándo la eligió el cliente (lo de la app vieja no tiene y cuenta como 0, lo más viejo). En
 *   el servidor y al leerlo gana lo más nuevo; borrar deja una lápida con la hora de lo que se borró, que no revive con
 *   algo más viejo ni saca algo más nuevo. El servidor recorta las horas del futuro (relojes adelantados).
 * - Cada cambio del cliente sale por la cola (`swap_ej` / `swap_ej_del`, con la misma clave: gana el último). La cola no
 *   muestra avisos por estas: la sustitución ya quedó en el teléfono.
 * - Al leer el servidor, que algo falte allá NO es que se borró: lo del teléfono se vuelve a subir. Solo una lápida más
 *   nueva lo saca.
 * - La poda es solo del teléfono y no se manda: un teléfono viejo no puede borrar lo que el cliente fijó después en otro.
 * - Sin la migración en la base (PGRST202), sin red o con el token caído: todo sigue como antes, solo en el teléfono.
 */
object SustitucionesServidor {
    const val KIND_GUARDAR = "swap_ej"
    const val KIND_BORRAR = "swap_ej_del"

    /** Lo mismo que acepta la base (`mypump_sustitucion_valida`), con margen en el tamaño. */
    private const val MAX_CLAVE = 120
    private const val MAX_TEXTO = 12_000
    private const val MAX_TS = 9_000_000_000_000_000.0

    /** Lo que el servidor deja pasar hacia el futuro (`mypump_sustitucion_tope`): 5 minutos. */
    private const val MARGEN_FUTURO = 300_000.0

    fun clave(rutinaId: String, exId: String): String = "swap_ej_${rutinaId}_$exId"

    /**
     * Lo último que ya está en la cola o en el servidor. Si la app se cierra entre escribir el archivo de la rutina y
     * encolar, al volver a abrir se encola la diferencia.
     */
    fun archivoEncoladas(rutinaId: String): String = "ejercicios-swaps-encoladas_$rutinaId.json"

    /** Lo que se leyó de la app vieja en la última corrida de la migración: la base para [volverDeLaAppVieja]. */
    fun archivoLegado(rutinaId: String): String = "ejercicios-swaps-legado_$rutinaId.json"

    /** `_ts` de una entrada (0 si no tiene: la app vieja, o de antes de SER-14). */
    fun ts(v: ValorJson?): Double {
        val n = ((v as? ValorJson.Objeto)?.campos?.get("_ts") as? ValorJson.Numero)?.valor ?: return 0.0
        return if (n.isFinite() && n >= 0) n else 0.0
    }

    /** La entrada sin su hora: para ver si dos son la misma elección. */
    fun sinHora(v: ValorJson?): ValorJson? = (v as? ValorJson.Objeto)?.let { ValorJson.Objeto(it.campos - "_ts") } ?: v

    /**
     * La hora de un cambio que reemplaza a `actual`: la de ahora, pero nunca menos que la de lo que reemplaza + 1 (si el
     * reloj de este teléfono, o el del que la eligió, iba adelantado, el cambio nuevo igual tiene que ganar). `piso`: la
     * hora más alta que ya tuvo esa clave (por ejemplo, la de lo que se acaba de deshacer): si no, el servidor la ignora
     * contra la lápida.
     */
    fun horaDeUnCambio(ahora: Double, actual: ValorJson?, piso: Double = 0.0): Double =
        maxOf(Math.floor(ahora), ts(actual) + 1, piso + 1)

    /** La entrada con su hora. */
    fun conHora(v: ValorJson, ms: Double): ValorJson {
        val o = v as? ValorJson.Objeto ?: return v
        return ValorJson.Objeto(LinkedHashMap(o.campos).apply { put("_ts", ValorJson.Numero(Math.floor(ms))) })
    }

    /** Lo que el servidor acepta. La clave se cuenta como la base (`length` de Postgres: puntos de código). */
    internal fun subible(exId: String, v: ValorJson): Boolean {
        val o = v as? ValorJson.Objeto ?: return false
        if (exId.codePointCount(0, exId.length) !in 1..MAX_CLAVE) return false
        if (v.serializar().toByteArray(Charsets.UTF_8).size > MAX_TEXTO) return false
        return when (val t = o.campos["_ts"]) {
            null -> true
            is ValorJson.Numero -> t.valor.isFinite() && t.valor >= 0 && t.valor <= MAX_TS
            else -> false
        }
    }

    data class Op(val kind: String, val payload: ValorJson, val clave: String, val exId: String)

    /**
     * Las ops para pasar de `antes` a `ahora`, en un orden fijo (las claves ordenadas). Un borrado lleva la hora de lo que
     * se borra (lo que el cliente veía): así nunca borra en el servidor algo más nuevo que no vio.
     */
    fun operaciones(antes: Map<String, ValorJson>, ahora: Map<String, ValorJson>, rutinaId: String): List<Op> {
        val ops = mutableListOf<Op>()
        for (exId in (antes.keys + ahora.keys).sorted()) {
            val a = antes[exId]
            val n = ahora[exId]
            val p = linkedMapOf<String, ValorJson>("rutinaId" to ValorJson.Texto(rutinaId), "exId" to ValorJson.Texto(exId))
            when {
                n != null && a != n -> {
                    if (!subible(exId, n)) continue
                    p["swap"] = n
                    ops += Op(KIND_GUARDAR, ValorJson.Objeto(p), clave(rutinaId, exId), exId)
                }
                n == null && a != null -> {
                    p["ts"] = ValorJson.Numero(Math.floor(ts(a)))
                    ops += Op(KIND_BORRAR, ValorJson.Objeto(p), clave(rutinaId, exId), exId)
                }
            }
        }
        return ops
    }

    /** Lo que contestó `mypump_get_exercise_swaps`. */
    data class Lectura(val vivas: Map<String, ValorJson>, val borradas: Map<String, Double>, val ahora: Double?)

    /** `{"vivas": {exId: entrada}, "borradas": {exId: ms}, "ahora": ms}`. null si no es eso. */
    fun leer(r: ValorJson): Lectura? {
        val o = r as? ValorJson.Objeto ?: return null
        val vivas = (o.campos["vivas"] as? ValorJson.Objeto)?.campos ?: return null
        val borradas = (o.campos["borradas"] as? ValorJson.Objeto)?.campos.orEmpty()
            .mapNotNull { (k, v) -> (v as? ValorJson.Numero)?.let { k to it.valor } }.toMap()
        val ahora = (o.campos["ahora"] as? ValorJson.Numero)?.valor?.takeIf { it.isFinite() && it > 0 }
        return Lectura(vivas.filterValues { it is ValorJson.Objeto }, borradas, ahora)
    }

    /**
     * El mapa del teléfono después de leer el servidor, clave por clave:
     * - lo que se tocó mientras se esperaba la respuesta, lo que estaba en la cola al empezar y lo que quedó en fallidos:
     *   queda lo del teléfono;
     * - lo que sigue en la cola: se pinta encima;
     * - si no: la del servidor si es tan nueva como la del teléfono; una lápida más nueva la saca; y lo que el servidor no
     *   tiene (o tiene más viejo) queda, para volver a subirlo.
     * Lo que el servidor no acepta (nunca se sube) queda siempre.
     *
     * Con `ahora` (la hora del servidor), lo del teléfono estampado más allá de lo que el servidor deja (un reloj
     * adelantado) no le gana a lo que diga el servidor: si no, volvía a subirse y pisaba lo que el cliente hizo después en
     * otro teléfono.
     */
    fun combinar(
        vivas: Map<String, ValorJson>,
        borradas: Map<String, Double>,
        local: Map<String, ValorJson>,
        pendientes: Map<String, Operacion>,
        rutinaId: String,
        tocadas: Set<String>,
        ahora: Double? = null,
    ): Map<String, ValorJson> {
        fun tsLocal(l: ValorJson): Double {
            val t = ts(l)
            return if (ahora != null && t > ahora + MARGEN_FUTURO) -1.0 else t
        }
        val r = LinkedHashMap<String, ValorJson>()
        val vivasObj = vivas.filterValues { it is ValorJson.Objeto }
        val prefijo = "swap_ej_${rutinaId}_"
        val enCola = HashMap<String, Operacion>()
        for ((k, op) in pendientes) {
            if (!k.startsWith(prefijo)) continue
            op.payload["exId"]?.comoTexto?.let { enCola[it] = op }
        }
        for (exId in (vivasObj.keys + borradas.keys + local.keys + enCola.keys)) {
            val l = local[exId]
            val op = enCola[exId]
            val v = vivasObj[exId]
            val b = borradas[exId]
            val queda: ValorJson? = when {
                exId in tocadas -> l
                op != null -> if (op.kind == KIND_GUARDAR) op.payload["swap"] else null
                // La misma elección con otra hora (el servidor recortó una del futuro): queda la del servidor.
                v != null && l != null && sinHora(v) == sinHora(l) -> v
                v != null && (l == null || ts(v) >= tsLocal(l)) -> v
                b != null && l != null && b >= tsLocal(l) -> null
                else -> l
            }
            if (queda != null) r[exId] = queda else r.remove(exId)
        }
        for ((exId, v) in local) if (!subible(exId, v)) r[exId] = v
        return r
    }

    /**
     * La vuelta a la app vieja (la migración del almacenamiento viejo que se repite): solo lo que el cliente cambió AHÍ desde
     * la corrida anterior (`base`) pisa lo del teléfono, con la hora de ahora para que gane también en el servidor; lo que
     * sacó ahí se saca. Lo demás queda. Sin `base` (una corrida anterior a SER-14), todo lo de la app vieja cuenta como
     * cambiado y nada se saca.
     */
    fun volverDeLaAppVieja(
        nativa: Map<String, ValorJson>,
        legado: Map<String, ValorJson>,
        base: Map<String, ValorJson>?,
        ms: Double,
    ): Map<String, ValorJson> {
        val r = LinkedHashMap(nativa)
        for ((exId, v) in legado) if (base?.get(exId) != v) r[exId] = conHora(v, horaDeUnCambio(ms, nativa[exId]))
        for (exId in base.orEmpty().keys) if (exId !in legado) r.remove(exId)
        return r
    }
}
