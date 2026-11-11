package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson

/*
 * Entrenar en casa (2.3.0, palanca `casa`): el interruptor de «Mi gimnasio». Contrato en `cola-b/CONTRATO_APP.md`, sección 3.
 * Es una excepción dentro de Mi gimnasio: la carga de casa es la misma de `mypump_gimnasio_get` (mismo `id`) con otro lugar.
 * La lista de equipo la da el servidor (`tipos`): acá no hay ninguna escrita.
 */

/** Un renglón de la lista para marcar. [kg]: al marcarlo se puede anotar hasta cuántos kilos. */
data class TipoCasa(val tipo: String, val nombre: String, val kg: Boolean)

data class EquipoCasa(val tipo: String, val kg: Double? = null)

data class CargaCasa(
    val id: String,
    val estado: String,
    /** `gimnasio` o `casa`. */
    val lugar: String,
    val equipos: List<EquipoCasa>,
    val sinEquipo: Boolean,
    val nota: String?,
) {
    val esCasa: Boolean get() = lugar == Casa.LUGAR_CASA
    val esBorrador: Boolean get() = estado == "borrador"

    companion object {
        fun desde(j: ValorJson?): CargaCasa? {
            j as? ValorJson.Objeto ?: return null
            val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            val estado = j["estado"]?.comoTexto ?: return null
            return CargaCasa(
                id = id,
                estado = estado,
                lugar = j["lugar"]?.comoTexto ?: "gimnasio",
                equipos = ((j["equipos"] as? ValorJson.Lista)?.elementos ?: emptyList()).mapNotNull { e ->
                    EquipoCasa(e["tipo"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null, e["kg"]?.comoNumero?.takeIf { it.isFinite() && it > 0 })
                },
                sinEquipo = j["sin_equipo"] == ValorJson.Booleano(true),
                nota = j["nota"]?.comoTexto?.trim()?.takeIf { it.isNotEmpty() },
            )
        }
    }
}

data class EstadoCasa(val tipos: List<TipoCasa>, val abierta: CargaCasa?, val vigente: CargaCasa?) {
    companion object {
        /** null: no es una respuesta con `habilitado:true` (el interruptor no existe). */
        fun desde(j: ValorJson): EstadoCasa? {
            if (j["habilitado"] != ValorJson.Booleano(true)) return null
            val vistos = HashSet<String>()
            val tipos = ((j["tipos"] as? ValorJson.Lista)?.elementos ?: emptyList()).mapNotNull { t ->
                val tipo = t["tipo"]?.comoTexto?.takeIf { it.isNotEmpty() && vistos.add(it) } ?: return@mapNotNull null
                TipoCasa(tipo, t["nombre"]?.comoTexto?.trim()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null, t["kg"] == ValorJson.Booleano(true))
            }
            return EstadoCasa(tipos, CargaCasa.desde(j["abierta"]), CargaCasa.desde(j["vigente"]))
        }
    }
}

object Casa {
    const val LUGAR_CASA = "casa"
    const val MAX_NOTA = 300
    const val KILOS_MINIMO = 1.0
    const val KILOS_MAXIMO = 400.0

    data class Interruptor(
        val prendido: Boolean,
        /** false: ya hay una carga enviada; no se puede mover hasta que quede lista. */
        val sePuedeMover: Boolean,
    )

    /**
     * Prendido = la carga abierta es de casa, o no hay carga abierta y la vigente es de casa. Con una carga ya enviada
     * (cualquier estado que no sea `borrador`) no se puede mover.
     */
    fun interruptor(e: EstadoCasa): Interruptor {
        val a = e.abierta
        return Interruptor(prendido = a?.esCasa ?: (e.vigente?.esCasa == true), sePuedeMover = a == null || a.esBorrador)
    }

    enum class Movimiento {
        /** `mypump_casa_elegir(true)`. */
        ELEGIR_CASA,
        /** `mypump_casa_elegir(false)`: el borrador de casa vuelve a ser de gimnasio. */
        ELEGIR_GIMNASIO,
        /** Sin borrador y con casa vigente: la carga de gimnasio de siempre (`mypump_gimnasio_nuevo` con `completa`). */
        NUEVO_GIMNASIO,
        NADA,
    }

    /** Qué hay que pedir al mover el interruptor a [prender]. */
    fun alMover(e: EstadoCasa, prender: Boolean): Movimiento {
        val i = interruptor(e)
        if (!i.sePuedeMover || i.prendido == prender) return Movimiento.NADA
        if (prender) return Movimiento.ELEGIR_CASA
        return if (e.abierta != null) Movimiento.ELEGIR_GIMNASIO else Movimiento.NUEVO_GIMNASIO
    }

    enum class Pantalla {
        /** Lo de siempre de Mi gimnasio (zonas, recibido, preguntas, listo). */
        GIMNASIO,
        /** Un borrador de casa: la lista para marcar, en lugar de las zonas con fotos. */
        LISTA,
        /** La vigente es de casa y no hay nada abierto. */
        VIGENTE,
    }

    fun pantalla(e: EstadoCasa?): Pantalla {
        e ?: return Pantalla.GIMNASIO
        val a = e.abierta
        return when {
            a != null && a.esCasa && a.esBorrador -> Pantalla.LISTA
            a == null && e.vigente?.esCasa == true -> Pantalla.VIGENTE
            else -> Pantalla.GIMNASIO
        }
    }

    // ── La lista ──

    /** Lo que se puede escribir en «Hasta cuántos kilos»: vacío, o un número de hasta 400 con una coma o un punto. */
    fun kilosEscribibles(s: String): Boolean {
        if (s.isEmpty()) return true
        if (s.length > 5 || s.any { it !in "0123456789.," } || s.count { it == '.' || it == ',' } > 1 || !s[0].isDigit()) return false
        val n = s.replace(',', '.').toDoubleOrNull() ?: return false
        return n <= KILOS_MAXIMO
    }

    /** Los kilos como los quiere el servidor: de 1 a 400, con un decimal. Vacío, cero o algo que no se entiende: sin kilos. */
    fun kilos(s: String): Double? {
        val n = s.trim().replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() } ?: return null
        val r = Math.round(n * 10) / 10.0
        return r.takeIf { it in KILOS_MINIMO..KILOS_MAXIMO }
    }

    fun notaRecortada(s: String): String = s.take(MAX_NOTA)

    /** Hace falta al menos un equipo, o «No tengo nada de esto». */
    fun puedeEnviar(marcados: Collection<String>, sinEquipo: Boolean, tipos: List<TipoCasa>): Boolean =
        sinEquipo || tipos.any { it.tipo in marcados }

    /**
     * `p_equipos`: solo tipos de la lista del servidor, en su orden, y los kilos solo donde se pueden anotar. Con
     * «No tengo nada de esto», ninguno.
     */
    fun equiposParaEnviar(tipos: List<TipoCasa>, marcados: Collection<String>, kilos: Map<String, String>, sinEquipo: Boolean): List<EquipoCasa> =
        if (sinEquipo) emptyList() else tipos.filter { it.tipo in marcados }.map { EquipoCasa(it.tipo, if (it.kg) kilos[it.tipo]?.let(::kilos) else null) }

    fun aValor(equipos: List<EquipoCasa>): ValorJson = ValorJson.Lista(
        equipos.map { e ->
            ValorJson.Objeto(buildMap { put("tipo", ValorJson.Texto(e.tipo)); e.kg?.let { put("kg", ValorJson.Numero(it)) } })
        },
    )

    // ── La vigente ──

    /** «Mancuernas, hasta 20 kg». El nombre sale de `tipos`; un tipo que ya no está en la lista se nombra por su clave. */
    fun renglonVigente(e: EquipoCasa, tipos: List<TipoCasa>): String {
        val nombre = tipos.firstOrNull { it.tipo == e.tipo }?.nombre ?: e.tipo.replace('_', ' ').replaceFirstChar { it.uppercase() }
        return e.kg?.let { "$nombre, ${Textos.hastaKg(it)}" } ?: nombre
    }

    fun numero(kg: Double): String = if (kg == Math.rint(kg)) kg.toLong().toString() else String.format(java.util.Locale.US, "%.1f", kg).replace('.', ',')

    object Textos {
        const val INTERRUPTOR = "Entreno en casa"
        const val INTERRUPTOR_AYUDA = "Prendelo si entrenás en tu casa y no en un gimnasio."
        const val YA_RECIBIDO = "Ya lo recibimos. Lo vas a poder cambiar cuando esté listo."
        const val ERROR_CAMBIAR = "No se pudo cambiar. Probá de nuevo."
        const val LISTA_TITULO = "¿Qué tenés en casa?"
        const val TARJETA = "¿Entrenás en casa? Tocá acá"
        const val LISTA_TEXTO = "Marcá todo lo que tengas. Con eso Mati arma tu rutina."
        const val KILOS = "Hasta cuántos kilos (opcional)"
        const val SIN_EQUIPO = "No tengo nada de esto"
        const val NOTA = "¿Algo más que quieras contarle a Mati?"
        const val ENVIAR = "Enviar a Mati"
        const val ERROR_ENVIAR = "No se pudo enviar. Probá de nuevo."
        const val SIN_DATOS = "Marcá lo que tenés, o “No tengo nada de esto”."
        const val VIGENTE_TITULO = "Entrenás en casa"
        const val VIGENTE_SIN_EQUIPO = "Sin equipo: entrenás con tu cuerpo."
        const val CAMBIAR = "Cambió lo que tengo en casa"
        fun hastaKg(kg: Double) = "hasta ${numero(kg)} kg"

        val todos = listOf(
            INTERRUPTOR, INTERRUPTOR_AYUDA, YA_RECIBIDO, ERROR_CAMBIAR, LISTA_TITULO, LISTA_TEXTO, KILOS, SIN_EQUIPO, NOTA, ENVIAR, ERROR_ENVIAR,
            SIN_DATOS, VIGENTE_TITULO, VIGENTE_SIN_EQUIPO, CAMBIAR, TARJETA,
        )
    }
}
