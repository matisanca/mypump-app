package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.ValorJson
import java.text.Normalizer

/**
 * «Me duele» por ejercicio (2.3.0, `supabase/propuestas/nativa_feedback_alumno.sql`). Los valores son los del servidor; los
 * textos, los de [TextosFeedback]. Gemelo de Feedback.swift; `apps/shared/fixtures/feedback/casos.json` hace fallar si difieren.
 */
object ReglasMolestia {
    const val MAX_NOTA = 500

    data class Opcion(val id: String, val texto: String)

    /** Zona → nombre, si es femenino y lo que va después del lado («Muslo derecho adelante»). */
    data class Zona(val id: String, val nombre: String, val femenino: Boolean = false, val cola: String = "")

    val zonas: List<Zona> = listOf(
        Zona("cuello", "Cuello"), Zona("hombro", "Hombro"), Zona("pecho", "Pecho"), Zona("brazo", "Brazo"),
        Zona("codo", "Codo"), Zona("antebrazo", "Antebrazo"), Zona("muneca", "Muñeca o mano", femenino = true),
        Zona("abdomen", "Abdomen"), Zona("espalda_alta", "Espalda alta", femenino = true), Zona("espalda_baja", "Espalda baja", femenino = true),
        Zona("cadera", "Cadera", femenino = true), Zona("gluteo", "Glúteo"), Zona("muslo_frente", "Muslo", cola = " adelante"),
        Zona("muslo_atras", "Muslo", cola = " atrás"), Zona("rodilla", "Rodilla", femenino = true), Zona("pantorrilla", "Pantorrilla", femenino = true),
        Zona("tobillo", "Tobillo o pie"),
    )
    val lados: List<String> = listOf("izquierdo", "derecho", "ambos", "centro")

    val desde: List<Opcion> = listOf(
        Opcion("hoy", "Hoy"), Opcion("esta_semana", "Esta semana"), Opcion("semanas", "Hace unas semanas"), Opcion("mas_de_un_mes", "Más de un mes"),
    )
    val cuando: List<Opcion> = listOf(
        Opcion("al_bajar", "Al bajar"), Opcion("al_subir", "Al subir"), Opcion("todo_el_recorrido", "En todo el recorrido"),
        Opcion("despues", "Después de entrenar"), Opcion("al_dia_siguiente", "Al día siguiente"),
    )
    val tipo: List<Opcion> = listOf(Opcion("punzante", "Punzante"), Opcion("sordo", "Sordo, de fondo"), Opcion("hormigueo", "Hormigueo"))

    /** Los lados que se eligen a mano, en el orden de la pantalla. */
    val ladosParaElegir: List<Opcion> = listOf(
        Opcion("derecho", TextosFeedback.dueleLadoDerecho), Opcion("izquierdo", TextosFeedback.dueleLadoIzquierdo), Opcion("ambos", TextosFeedback.dueleLadoAmbos),
    )

    /** La escala simple: cuatro escalones que se guardan como 2, 5, 7 y 9 de 10. */
    data class Nivel(val id: Int, val texto: String)

    val niveles: List<Nivel> = listOf(Nivel(2, "Poco"), Nivel(5, "Bastante"), Nivel(7, "Mucho"), Nivel(9, "No puedo seguir"))

    /** El escalón de una intensidad guardada (0 a 10): hasta 3 poco, hasta 5 bastante, hasta 7 mucho. */
    fun nivel(intensidad: Int): Nivel = when {
        intensidad <= 3 -> niveles[0]
        intensidad <= 5 -> niveles[1]
        intensidad <= 7 -> niveles[2]
        else -> niveles[3]
    }

    /** Desde «Mucho» se suma la línea de dejar el ejercicio por hoy. Es no seguir cargando algo que duele, nada más. */
    fun esFuerte(intensidad: Int): Boolean = intensidad >= 7

    fun zonaValida(z: String): Boolean = zonas.any { it.id == z }

    /** «Hombro derecho», «Muñeca o mano izquierda», «Muslo derecho adelante», «Rodilla, los dos lados», «Espalda baja». */
    fun nombreZona(zona: String, lado: String): String {
        val z = zonas.firstOrNull { it.id == zona } ?: return ""
        return when (lado) {
            "izquierdo" -> "${z.nombre} ${if (z.femenino) "izquierda" else "izquierdo"}${z.cola}"
            "derecho" -> "${z.nombre} ${if (z.femenino) "derecha" else "derecho"}${z.cola}"
            "ambos" -> "${z.nombre}${z.cola}, los dos lados"
            else -> z.nombre + z.cola
        }
    }

    /** Por puntos de código, como cuenta el SQL. */
    fun nota(s: String): String {
        if (s.codePointCount(0, s.length) <= MAX_NOTA) return s
        return s.substring(0, s.offsetByCodePoints(0, MAX_NOTA))
    }

    /** Lo que se manda. [completa] = se puede avisar. */
    data class Borrador(
        val zona: String? = null,
        val lado: String? = null,
        val desde: String? = null,
        val cuando: String? = null,
        val tipo: String? = null,
        val intensidad: Int? = null,
        val nota: String = "",
    ) {
        val completa: Boolean
            get() {
                val z = zona ?: return false
                val l = lado ?: return false
                val d = desde ?: return false
                val c = cuando ?: return false
                val t = tipo ?: return false
                val i = intensidad ?: return false
                return zonaValida(z) && l in lados && ReglasMolestia.desde.any { it.id == d } && ReglasMolestia.cuando.any { it.id == c } &&
                    ReglasMolestia.tipo.any { it.id == t } && i in 0..10
            }

        val nombreZona: String? get() = zona?.let { z -> lado?.let { ReglasMolestia.nombreZona(z, it) } }

        companion object {
            /** Para corregir un aviso: abre con lo que ya se avisó, con la intensidad llevada a su escalón. */
            fun de(m: Molestia): Borrador = Borrador(m.zona, m.lado, m.desde, m.cuando, m.tipo, m.intensidad?.let { nivel(it).id }, m.nota ?: "")
        }
    }
}

/** Una molestia como la devuelve `mypump_feedback_get`. Al alumno no le llega nada interno (ni destino ni resolución). */
data class Molestia(
    val id: String,
    val ejercicioId: String,
    val ejercicioNombre: String,
    val zona: String,
    val lado: String,
    val desde: String? = null,
    val cuando: String? = null,
    val tipo: String? = null,
    val intensidad: Int? = null,
    val nota: String? = null,
    /** `avisada` o `resuelta`. Otro valor (de un servidor más nuevo) se descarta al decodificar. */
    val estado: String,
) {
    val abierta: Boolean get() = estado == "avisada"
    val nombreZona: String get() = ReglasMolestia.nombreZona(zona, lado)

    companion object {
        fun desde(j: ValorJson?): Molestia? {
            j ?: return null
            val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            val e = j["ejercicio_id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            val zona = j["zona"]?.comoTexto?.takeIf(ReglasMolestia::zonaValida) ?: return null
            val estado = j["estado"]?.comoTexto?.takeIf { it == "avisada" || it == "resuelta" } ?: return null
            val lado = j["lado"]?.comoTexto ?: "centro"
            return Molestia(
                id = id, ejercicioId = e, ejercicioNombre = j["ejercicio_nombre"]?.comoTexto ?: "",
                zona = zona, lado = if (lado in ReglasMolestia.lados) lado else "centro",
                desde = j["desde"]?.comoTexto, cuando = j["cuando"]?.comoTexto, tipo = j["tipo"]?.comoTexto,
                intensidad = j["intensidad"]?.comoNumero?.takeIf { it.isFinite() && it in 0.0..10.0 }?.toInt(),
                nota = j["nota"]?.comoTexto?.takeIf { it.isNotEmpty() },
                estado = estado,
            )
        }
    }
}

/** «Lo compré / lo estoy tomando»: una marca por ítem, una sola vez, y se puede cambiar. */
object ReglasSupleEstado {
    enum class Estado(val clave: String, /** Lo que elige el alumno. */ val accion: String, /** Cómo queda marcado. */ val marcado: String) {
        COMPRADO("comprado", "Lo compré", "Comprado"),
        TOMANDO("tomando", "Lo estoy tomando", "Lo estás tomando"),
        NO_LO_CONSIGO("no_lo_consigo", "No lo consigo", "No lo conseguís"),
        LO_DEJE("lo_deje", "Lo dejé", "Lo dejaste");

        companion object {
            fun de(clave: String?): Estado? = entries.firstOrNull { it.clave == clave }
        }
    }

    private val sinTilde: Map<Char, Char> = mapOf(
        'á' to 'a', 'à' to 'a', 'ä' to 'a', 'â' to 'a', 'é' to 'e', 'è' to 'e', 'ë' to 'e', 'ê' to 'e', 'í' to 'i', 'ì' to 'i', 'ï' to 'i', 'î' to 'i',
        'ó' to 'o', 'ò' to 'o', 'ö' to 'o', 'ô' to 'o', 'ú' to 'u', 'ù' to 'u', 'ü' to 'u', 'û' to 'u', 'ñ' to 'n',
    )

    /** La clave de un ítem, la misma cuenta que `mypump_suple_clave`: minúsculas, sin tildes y con un solo espacio. */
    fun clave(nombre: String): String {
        val plano = buildString {
            for (c in Normalizer.normalize(nombre, Normalizer.Form.NFC).lowercase(java.util.Locale.ROOT)) append(sinTilde[c] ?: c)
        }
        return plano.split(Regex("""[\s   ]+""")).filter { it.isNotEmpty() }.joinToString(" ")
    }

    /** [id] es la clave. */
    data class Fila(val id: String, val nombre: String, val estado: Estado?)

    /**
     * Lo que se puede marcar: cada suplemento una vez, en el orden del plan. Los protectores (fármacos) no van nunca; lo que
     * «sale» tampoco, salvo que ya tenga una marca.
     */
    fun filas(items: List<ItemSuplemento>, marcas: Map<String, Estado>): List<Fila> {
        val vistos = HashSet<String>()
        val salen = ArrayList<Fila>()
        for (it in items) {
            if (it.protector) continue
            val k = clave(it.nombre)
            if (k.isEmpty() || !vistos.add(k)) continue
            if (it.estado == "sale" && marcas[k] == null) continue
            salen += Fila(k, it.nombre.trim(), marcas[k])
        }
        return salen
    }

    /** «2 de 5 marcados», para el encabezado. */
    fun resumen(filas: List<Fila>): String = "${filas.count { it.estado != null }} de ${filas.size} marcados"
}

/** Lo que devuelve `mypump_feedback_get`. Tolerante: lo que no se entiende se descarta. */
data class EstadoFeedback(
    val dueleHabilitado: Boolean = false,
    val molestias: List<Molestia> = emptyList(),
    val supleHabilitado: Boolean = false,
    val marcas: Map<String, ReglasSupleEstado.Estado> = emptyMap(),
) {
    /** La molestia que se muestra en un ejercicio: la abierta, o la última cerrada. */
    fun molestia(ejercicio: String): Molestia? {
        val suyas = molestias.filter { it.ejercicioId == ejercicio }
        return suyas.firstOrNull { it.abierta } ?: suyas.firstOrNull()
    }

    companion object {
        fun desde(j: ValorJson): EstadoFeedback? {
            if (j !is ValorJson.Objeto) return null
            val duele = j["me_duele"]
            val suple = j["suple_estado"]
            val marcas = LinkedHashMap<String, ReglasSupleEstado.Estado>()
            (suple?.get("items") as? ValorJson.Lista)?.elementos?.forEach { x ->
                val k = x["item"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return@forEach
                val e = ReglasSupleEstado.Estado.de(x["estado"]?.comoTexto) ?: return@forEach
                marcas[k] = e
            }
            return EstadoFeedback(
                dueleHabilitado = (duele?.get("habilitado") as? ValorJson.Booleano)?.valor ?: false,
                molestias = (duele?.get("molestias") as? ValorJson.Lista)?.elementos?.mapNotNull(Molestia::desde) ?: emptyList(),
                supleHabilitado = (suple?.get("habilitado") as? ValorJson.Booleano)?.valor ?: false,
                marcas = marcas,
            )
        }
    }
}
