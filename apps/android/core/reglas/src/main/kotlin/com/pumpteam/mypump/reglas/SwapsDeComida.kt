package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.EstructuraDieta
import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.ValorJson

/**
 * Un swap de comida como lo guarda el teléfono (`STATE.foodSwaps[key]` de la web): `current` es el `food_data` tal cual
 * va y viene del servidor.
 */
data class SwapLocal(val original: ValorJson? = null, val current: ValorJson)

/** Una escritura que la hidratación pide encolar (`swap` o `swap_del`), con la misma clave que usa la web. */
data class OpSwap(
    val kind: String,
    val clave: String,
    val comidaId: String,
    val optIdx: Int,
    val foodIdx: Int,
    val food: ValorJson?,
) {
    val payload: ValorJson
        get() = ValorJson.Objeto(
            buildMap {
                put("comidaId", ValorJson.Texto(comidaId))
                put("optIdx", ValorJson.Numero(optIdx.toDouble()))
                put("foodIdx", ValorJson.Numero(foodIdx.toDouble()))
                food?.let { put("food", it) }
            },
        )
}

/** El alimento a mostrar en una posición, y si es un sustituto. */
data class AlimentoEfectivo(val alimento: Alimento, val sustituido: Boolean)

object SwapsDeComida {
    /** `swap_<DIETA_ID>_<comida>_<opt>_<food>`: la clave del mapa local, el dedupe de la cola y la key de la web. */
    fun clave(dietaId: String, comidaId: String, optIdx: Int, foodIdx: Int): String = "swap_${dietaId}_${comidaId}_${optIdx}_$foodIdx"

    /**
     * `_conAncla`: el sustituto con el alimento que reemplaza adentro, en `_orig` (nombre, cantidad, unidad). Como
     * `JSON.stringify`, lo que no tiene valor no se escribe.
     */
    fun conAncla(sustituto: ValorJson, original: Alimento): ValorJson {
        val o = LinkedHashMap<String, ValorJson>()
        if (sustituto is ValorJson.Objeto) o.putAll(sustituto.campos)
        val ancla = LinkedHashMap<String, ValorJson>()
        ancla["name"] = ValorJson.Texto(original.nombre)
        original.qty?.let { ancla["qty"] = ValorJson.Numero(it) }
        original.unidad?.let { ancla["unit"] = ValorJson.Texto(it) }
        o["_orig"] = ValorJson.Objeto(ancla)
        return ValorJson.Objeto(o)
    }

    /**
     * `_foodsEnPosicion`: los alimentos de esa posición en el plan activo primero y después en los demás tipos de día.
     * Como en la web, el activo se saca del resto por identidad (dos tipos con el mismo id cuentan los dos).
     */
    fun enPosicion(dieta: EstructuraDieta, tipoActivo: String?, comidaId: String, optIdx: Int, foodIdx: Int): List<Alimento> {
        val planes = if (dieta.tiposDia.isEmpty()) {
            listOf(dieta.comidas)
        } else {
            val iActivo = dieta.tiposDia.indexOfFirst { it.id == tipoActivo }
            val activo = dieta.tiposDia.getOrNull(iActivo)
            (listOfNotNull(activo) + dieta.tiposDia.filterIndexed { i, _ -> i != iActivo }).map { it.comidas }
        }
        return planes.mapNotNull { comidas ->
            comidas.firstOrNull { it.id == comidaId }?.opciones?.getOrNull(optIdx)?.alimentos?.getOrNull(foodIdx)
        }
    }

    data class Hidratacion(
        /** El mapa resultante (lo que se muestra y se guarda en el teléfono). */
        val swaps: Map<String, SwapLocal>,
        /** Lo que hay que encolar, en orden. */
        val operaciones: List<OpSwap>,
        /** Se puede marcar "migrado" ya (la rama de migración lo decide recién después de drenar la cola). */
        val marcarMigrado: Boolean,
        /** La rama de migración encoló: hay que drenar y marcar migrado solo si no quedó ningún swap pendiente. */
        val migrando: Boolean,
    )

    /**
     * Port de la mitad de `hydrateSwapsAndCustomFoodsFromBackend` que trata los swaps (cliente.html:5956-6027) y de
     * `_anclarOSacarSwap` (5900). Devuelve null si `remotos` es null: no se pudo preguntar (red) y no se toca nada —
     * tratarlo como "cero swaps" volvía a subir lo que el cliente o Mati habían borrado.
     *
     * @param pendientes clave → kind de lo que está en la cola sin subir. Lo que el cliente hizo gana.
     * @param borrarAnclados la palanca remota (`anclaje_borra_swaps`). En false, un swap anclado que ya no coincide queda
     *   guardado y oculto (`aplica` da falso) en vez de borrarse del servidor.
     */
    fun hidratar(
        remotos: List<FoodSwap>?,
        locales: Map<String, SwapLocal>,
        dietaId: String,
        pendientes: Map<String, String>,
        yaMigrado: Boolean,
        borrarAnclados: Boolean = true,
        enPosicion: (String, Int, Int) -> List<Alimento>,
    ): Hidratacion? {
        if (remotos == null) return null
        var swaps: Map<String, SwapLocal> = locales
        val ops = mutableListOf<OpSwap>()
        var migrando = false

        if (remotos.isEmpty() && locales.isNotEmpty() && yaMigrado) {
            // El servidor es la fuente de verdad y está vacío: lo local se borró en otro lado. Queda solo lo pendiente.
            swaps = locales.filterKeys { it in pendientes }
        } else if (remotos.isEmpty() && locales.isNotEmpty()) {
            // Migración, una vez por dispositivo: lo local de antes del backend sube POR LA COLA. (La web recorre en el
            // orden en que se insertaron las claves; acá no hay ese orden y se usa el alfabético, como en iOS.)
            val re = JsRegex("^swap_${escaparParaRegex(dietaId)}_(.+?)_(\\d+)_(\\d+)$")
            for ((clave, swap) in locales.entries.sortedBy { it.key }) {
                if (!SemanticaJs.esVerdadero(swap.current)) continue
                val m = re.primera(clave) ?: continue
                val o = m[2]!!.toIntOrNull() ?: continue
                val f = m[3]!!.toIntOrNull() ?: continue
                ops += OpSwap("swap", clave, m[1]!!, o, f, swap.current)
            }
            migrando = ops.isNotEmpty()
        } else if (remotos.isNotEmpty()) {
            val nuevos = LinkedHashMap<String, SwapLocal>()
            for (s in remotos) {
                val k = clave(dietaId, s.comidaId, s.optIdx, s.foodIdx)
                nuevos[k] = SwapLocal(original = null, current = s.foodData)
                anclarOSacar(nuevos, k, s, pendientes, borrarAnclados, enPosicion)?.let { ops += it }
            }
            for ((k, local) in locales) if (k in pendientes) nuevos[k] = local      // local más nuevo, sin subir
            for ((k, kind) in pendientes) if (kind == "swap_del") nuevos.remove(k)  // una reversión pendiente no resucita
            swaps = nuevos
        }
        val marcar = remotos.isNotEmpty() || swaps.isEmpty()
        return Hidratacion(swaps, ops, marcar, migrando)
    }

    /**
     * `_anclarOSacarSwap`: un swap remoto legado (sin `_orig`) se ancla al alimento actual y se re-sube; uno anclado que
     * ya no coincide con NINGÚN tipo de día se saca y se borra en el backend. Lo pendiente del cliente no se toca.
     */
    internal fun anclarOSacar(
        mapa: MutableMap<String, SwapLocal>,
        clave: String,
        fila: FoodSwap,
        pendientes: Map<String, String>,
        borrarAnclados: Boolean = true,
        enPosicion: (String, Int, Int) -> List<Alimento>,
    ): OpSwap? {
        val actual = mapa[clave]?.current
        if (!SemanticaJs.esVerdadero(actual)) return null
        if (clave in pendientes) return null
        val candidatos = enPosicion(fila.comidaId, fila.optIdx, fila.foodIdx)
        val primero = candidatos.firstOrNull() ?: return null   // posición inexistente: no se aplica de todos modos
        val ancla = actual!!["_orig"]
        if (!SemanticaJs.esVerdadero(ancla)) {
            val anclado = conAncla(actual, primero)
            mapa[clave] = mapa.getValue(clave).copy(current = anclado)
            return OpSwap("swap", clave, fila.comidaId, fila.optIdx, fila.foodIdx, anclado)
        }
        val h = AnclajeSwaps.huella(ancla!!)
        if (borrarAnclados && candidatos.none { AnclajeSwaps.huella(it) == h }) {
            mapa.remove(clave)
            return OpSwap("swap_del", clave, fila.comidaId, fila.optIdx, fila.foodIdx, null)
        }
        return null
    }

    /** `getEffectiveFood`: el alimento a mostrar en esa posición (el sustituto si el swap aplica). */
    fun efectivo(original: Alimento, swap: SwapLocal?, comidaId: String?, enPosicion: () -> List<Alimento>): AlimentoEfectivo {
        if (swap == null || !AnclajeSwaps.aplica(swap.current, original, comidaId, enPosicion)) return AlimentoEfectivo(original, false)
        val a = Alimento.desdeValor(swap.current) ?: return AlimentoEfectivo(original, false)
        return AlimentoEfectivo(a, true)
    }

    /** Un texto como literal adentro de una regex de JS (la web no lo escapa: un UUID no tiene nada que escapar). */
    private fun escaparParaRegex(s: String): String =
        s.map { if (it in ".*+?^\${}()|[]\\/-") "\\$it" else "$it" }.joinToString("")
}
