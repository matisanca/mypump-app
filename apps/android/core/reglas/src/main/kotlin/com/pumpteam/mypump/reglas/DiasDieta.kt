package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.ComidaLibre
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * Qué días se pueden cargar en Dieta y cómo se llaman (pedido de un cliente: «salí a cenar y al día siguiente no pude
 * cargar esa cena»). El servidor mira la fecha de Argentina: `mypump_crear_comida_libre`, `mypump_desmarcar_comida` y
 * `mypump_guardar_ajustes_dieta` aceptan de −7 a +1, pero `mypump_marcar_comida` solo de −2 a 0 (verificado en la base el
 * 9-nov). Por eso «Comí» y «Salté» tienen su propia ventana, que dice la palanca remota (`dieta_dias_marcar`). Gemelo de
 * DiasDieta.swift.
 */
object DiasDieta {
    const val DIAS_ATRAS = 7

    /** Lo que acepta hoy `mypump_marcar_comida`. */
    const val DIAS_MARCAR_DE_FABRICA = 2

    val zonaServidor: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

    fun hoyServidor(ahora: Instant = Instant.now()): String = FechaLocal.hoy(ahora, zonaServidor)

    private fun fecha(iso: String): LocalDate? = try {
        LocalDate.parse(iso)
    } catch (_: java.time.format.DateTimeParseException) {
        null
    }

    /** [iso] más [dias] (negativo: para atrás). */
    fun sumar(iso: String, dias: Int): String? = fecha(iso)?.plusDays(dias.toLong())?.toString()

    /**
     * Hoy primero y después los días anteriores que el servidor todavía acepta: un teléfono atrasado respecto de Argentina
     * no ofrece un día que la base rechazaría.
     */
    fun seleccionables(hoy: String, hoyServidor: String): List<String> {
        val piso = sumar(hoyServidor, -DIAS_ATRAS) ?: hoy
        return (0..DIAS_ATRAS).mapNotNull { sumar(hoy, -it) }.filter { it == hoy || it >= piso }
    }

    /** ¿`mypump_marcar_comida` acepta esa fecha? [dias] es la ventana vigente (la palanca remota). */
    fun permiteMarcar(iso: String, hoyServidor: String, dias: Int): Boolean {
        val piso = sumar(hoyServidor, -dias.coerceIn(0, DIAS_ATRAS)) ?: return false
        return iso >= piso && iso <= hoyServidor
    }

    private val SEMANA = listOf("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado")
    private val SEMANA_CORTA = listOf("Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb")
    private val MESES = listOf("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre")

    /** Lo que dice cada día en el selector: «Hoy», «Ayer», «Sáb 7». */
    fun rotuloCorto(iso: String, hoy: String): String {
        if (iso == hoy) return "Hoy"
        if (iso == sumar(hoy, -1)) return "Ayer"
        val f = fecha(iso) ?: return iso
        return "${SEMANA_CORTA[f.dayOfWeek.value % 7]} ${f.dayOfMonth}"
    }

    /** «sábado 7 de noviembre». */
    fun rotuloLargo(iso: String): String {
        val f = fecha(iso) ?: return iso
        return "${SEMANA[f.dayOfWeek.value % 7]} ${f.dayOfMonth} de ${MESES[f.monthValue - 1]}"
    }
}

/**
 * Copiar a hoy lo cargado otro día (pedido de un cliente: «así no agrego todas las comidas todos los días, porque comemos
 * casi lo mismo en una semana»). De cada comida se copia lo que representa lo que comió: el ajuste (opción, gramos a mano,
 * kcal y alimentos agregados) y la marca «Comí» con sus tildes. «Salté» y «Hoy no la como» no se copian: dicen que ese día
 * no la comió, no lo que come. Las comidas libres se copian como comidas nuevas. Gemelo de CopiaDeComidas de iOS.
 */
object CopiaDeComidas {
    enum class Estado {
        /** Hoy no hay nada cargado en esa comida. */
        NUEVA,

        /** Hoy ya está exactamente eso. */
        IGUAL,

        /** Hoy hay otra cosa cargada: solo se reemplaza si el cliente lo pide. */
        CONFLICTO,
    }

    data class ItemComida(
        val comidaId: String,
        val nombre: String,
        val opcion: Int,
        val nombreOpcion: String,
        val marca: MarcaComida?,
        val ajuste: AjusteComida?,
        val kcal: Double,
        val estado: Estado,
    ) {
        val id: String get() = comidaId
        val agregados: Int get() = ajuste?.agregados?.size ?: 0
        val conCantidades: Boolean get() = !ajuste?.cantidades.isNullOrEmpty() || (ajuste?.deltaKcal ?: 0) != 0
    }

    data class ItemLibre(val libre: ComidaLibre, val estado: Estado) {
        val id: String get() = libre.id
    }

    data class Plan(
        val comidas: List<ItemComida> = emptyList(),
        val libres: List<ItemLibre> = emptyList(),
        /** El plan de ese día era otro: solo se ofrecen las comidas libres. */
        val otroPlan: Boolean = false,
    ) {
        val vacio: Boolean get() = comidas.isEmpty() && libres.isEmpty()
    }

    /** El estado de una comida contra lo que ya hay hoy. */
    fun estado(marca: MarcaComida?, ajuste: AjusteComida?, hoyMarca: MarcaComida?, hoyAjuste: AjusteComida?): Estado {
        if (hoyMarca == null && hoyAjuste == null) return Estado.NUEVA
        return if (hoyMarca == marca && hoyAjuste == ajuste) Estado.IGUAL else Estado.CONFLICTO
    }

    private fun normalizar(s: String?): String = s.orEmpty().trim().lowercase()

    /** La misma descripción y las mismas kcal (redondeadas): copiarla de nuevo la duplicaría. */
    fun mismaLibre(a: ComidaLibre, b: ComidaLibre): Boolean =
        normalizar(a.descripcion) == normalizar(b.descripcion) && jsRound(a.kcal ?: 0.0) == jsRound(b.kcal ?: 0.0)

    /** Lo que se puede copiar de ese día. [kcal] calcula lo de una comida con su marca y su ajuste. */
    fun plan(
        comidas: List<Comida>,
        origenMarcas: Map<String, MarcaComida>,
        origenAjustes: Map<String, AjusteComida>,
        origenLibres: List<ComidaLibre>,
        hoyMarcas: Map<String, MarcaComida>,
        hoyAjustes: Map<String, AjusteComida>,
        hoyLibres: List<ComidaLibre>,
        otroPlan: Boolean = false,
        kcal: (Comida, MarcaComida?, AjusteComida?, Int) -> Double,
    ): Plan {
        // Por conteo: dos iguales en el origen y una hoy son una que ya está y una nueva.
        val quedan = hoyLibres.toMutableList()
        val libres = origenLibres.map { l ->
            val j = quedan.indexOfFirst { mismaLibre(it, l) }
            if (j >= 0) quedan.removeAt(j)
            ItemLibre(l, if (j >= 0) Estado.IGUAL else Estado.NUEVA)
        }
        if (otroPlan) return Plan(libres = libres, otroPlan = true)
        val items = ArrayList<ItemComida>()
        for (c in comidas) {
            if (c.opciones.isEmpty()) continue
            val m = origenMarcas[c.id]
            val a = origenAjustes[c.id]
            if ((m == null && a == null) || m?.estado == MarcaComida.Estado.SALTADO || a?.omitida == true) continue
            // La opción de la marca tiene que seguir existiendo: `indiceOpcion` caería a la A y copiaría otra comida.
            var o = a?.opcion ?: 0
            if (m != null) {
                val nombre = m.opcion?.takeIf { it.isNotEmpty() } ?: continue
                val existe = c.opciones.any { it.nombre == nombre } ||
                    c.opciones.indices.any { c.opciones[it].nombre.isNullOrEmpty() && ConsumoDelDia.letra(it) == nombre }
                if (!existe) continue
                o = ConsumoDelDia.indiceOpcion(c, nombre)
            }
            if (o !in c.opciones.indices || (a != null && a.opcion !in c.opciones.indices)) continue
            val marca = m?.let { actual ->
                val tope = c.opciones[o].alimentos.size + (a?.agregados?.size ?: 0)
                MarcaComida(actual.opcion, actual.estado, actual.excluidos.filter { it < tope })
            }
            items += ItemComida(
                c.id, c.nombre ?: "", o, ConsumoDelDia.nombreOpcion(c, o), marca, a, kcal(c, marca, a, o),
                estado(marca, a, hoyMarcas[c.id], hoyAjustes[c.id]),
            )
        }
        return Plan(items, libres, otroPlan = false)
    }
}
