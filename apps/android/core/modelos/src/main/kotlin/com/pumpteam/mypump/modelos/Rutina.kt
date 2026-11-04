package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonElement

/** Fila de `mypump_get_rutina_activa`. */
data class RutinaActiva(
    val id: String,
    val version: Int,
    val estructura: EstructuraRutina,
    val semanaActual: Int,
    val fechaInicio: String?,
    val fechaFin: String?,
    val tieneSiguiente: Boolean,
) {
    /**
     * La misma rutina en otra semana: al pasar de semana no cambia nada más. Para cuando el servidor ya avanzó y la rutina
     * nueva no llegó (`ModeloEntreno.avanzarSemana`, revisión del 15-oct, hallazgo 1).
     */
    fun conSemana(s: Int): RutinaActiva = copy(semanaActual = s)

    companion object {
        fun desde(e: JsonElement): RutinaActiva {
            val o = e.comoObjeto("RutinaActiva")
            return RutinaActiva(
                id = o.texto("id") ?: "",
                version = o.entero("version") ?: 1,
                estructura = o.objeto("estructura")?.let(EstructuraRutina::desde) ?: EstructuraRutina(),
                semanaActual = o.entero("semana_actual") ?: 1,
                fechaInicio = o.texto("fecha_inicio"),
                fechaFin = o.texto("fecha_fin"),
                tieneSiguiente = o.booleano("tiene_siguiente") ?: false,
            )
        }
    }
}

/**
 * `mypump_rutinas.estructura`, tal como la publica el Cerebro (`expandirRutinaParaMyPump`). Ver la 001 y
 * `docs/NATIVA_CONTRATO.md`.
 */
data class EstructuraRutina(
    val nombrePlan: String? = null,
    val perfil: PerfilPlan? = null,
    val semanasTotal: Int? = null,
    val dias: List<Dia> = emptyList(),
    val mensajesSemana: List<MensajeSemana> = emptyList(),
    val semanaOffset: Int? = null,
    val fase: Int? = null,
) {
    companion object {
        fun desde(e: JsonElement): EstructuraRutina {
            val o = e.comoObjeto("EstructuraRutina")
            return EstructuraRutina(
                nombrePlan = o.texto("nombre_plan"),
                perfil = o.objeto("perfil")?.let(PerfilPlan::desde),
                semanasTotal = o.entero("semanas_total"),
                dias = o.lista("dias", Dia::desde),
                mensajesSemana = o.lista("mensajes_semana", MensajeSemana::desde),
                semanaOffset = o.entero("semana_offset"),
                fase = o.entero("fase"),
            )
        }
    }
}

data class PerfilPlan(
    val nivel: String? = null,
    val split: String? = null,
    val diasSemana: Int? = null,
    val objetivo: String? = null,
    val resumen: String? = null,
) {
    companion object {
        fun desde(e: JsonElement): PerfilPlan {
            val o = e.comoObjeto("PerfilPlan")
            return PerfilPlan(o.texto("nivel"), o.texto("split"), o.entero("diasSemana"), o.texto("objetivo"), o.texto("resumen"))
        }
    }
}

data class MensajeSemana(val n: Int? = null, val titulo: String? = null, val msg: String? = null) {
    companion object {
        fun desde(e: JsonElement): MensajeSemana {
            val o = e.comoObjeto("MensajeSemana")
            return MensajeSemana(o.entero("n"), o.texto("titulo"), o.texto("msg"))
        }
    }
}

/** Un día de la rutina. El `id` es una clave opaca (`d<n>`, `b<v>d<n>`, `r<n>d<n>`, `lun`…): nunca se parsea. */
data class Dia(
    val id: String? = null,
    val n: Int? = null,
    val nombre: String? = null,
    val abreviado: String? = null,
    val bloques: List<Bloque> = emptyList(),
    val esComodin: Boolean? = null,
    val reemplaza: List<String>? = null,
) {
    companion object {
        fun desde(e: JsonElement): Dia {
            val o = e.comoObjeto("Dia")
            return Dia(
                id = o.texto("id"),
                n = o.entero("n"),
                nombre = o.texto("nombre"),
                abreviado = o.texto("abreviado"),
                bloques = o.lista("bloques", Bloque::desde),   // un bloque vaciado puede venir null (Facundo, d4)
                esComodin = o.booleano("es_comodin"),
                reemplaza = o.textos("reemplaza"),
            )
        }
    }
}

data class Bloque(val titulo: String? = null, val subtitulo: String? = null, val ejercicios: List<Ejercicio> = emptyList()) {
    companion object {
        fun desde(e: JsonElement): Bloque {
            val o = e.comoObjeto("Bloque")
            return Bloque(o.texto("titulo"), o.texto("subtitulo"), o.lista("ejercicios", Ejercicio::desde))
        }
    }
}

/**
 * Un ejercicio. El `id` es del LUGAR en la rutina (`slug-d<n>-<i>`), no del ejercicio: el historial va por
 * `claveEjercicio(nombre efectivo)`.
 */
data class Ejercicio(
    val id: String,
    val nombre: String,
    val tipo: String? = null,
    val descansoSegundos: Int? = null,
    val notasTecnica: String? = null,
    val videoUrl: String? = null,
    val imagenes: Imagenes? = null,
    val catalogoSlug: String? = null,
    /** `_matched_slug` suelto (245 ejercicios reales lo tienen fuera de `images`). */
    val matchedSlug: String? = null,
    val progresion: List<Progresion> = emptyList(),
    // Campos viejos: los usa la demo de la web y los planes de antes de la progresión por semana.
    val series: Int? = null,
    val reps: String? = null,
    val rirObjetivo: String? = null,
    /** `rir` suelto: último respaldo de `getProgresionActual` (`ej.rir_objetivo ?? ej.rir`). */
    val rirSuelto: String? = null,
    /**
     * El `equipment` del catálogo cuando el lugar está sustituido (lo pone `CatalogoEjercicios.efectivo`). El plan no lo
     * trae: en los del plan decide el nombre, que escribe Mati con el equipo («Crunch en polea»).
     */
    val equipo: String? = null,
    /**
     * E1 (2.0.3): la preparación que pone el plan a mano. Gana a la que arma la app; `[]` = sin preparación; null = la
     * arma la app. Si no se puede leer, null (nunca tira abajo el ejercicio). Gemelo de `Aproximacion.lista` en Swift.
     */
    val aproximaciones: List<Aproximacion>? = null,
) {
    companion object {
        fun desde(e: JsonElement): Ejercicio {
            val o = e.comoObjeto("Ejercicio")
            return Ejercicio(
                id = o.texto("id") ?: "",
                nombre = o.texto("nombre") ?: "",
                tipo = o.texto("tipo"),
                descansoSegundos = o.entero("descanso_segundos"),
                notasTecnica = o.texto("notas_tecnica"),
                videoUrl = o.texto("video_url"),
                imagenes = o.objeto("images")?.let(Imagenes::desde),
                catalogoSlug = o.texto("catalogo_slug"),
                matchedSlug = o.texto("_matched_slug"),
                progresion = o.lista("progresion", Progresion::desde),
                series = o.entero("series"),
                reps = o.texto("reps"),
                rirObjetivo = o.texto("rir_objetivo"),
                rirSuelto = o.texto("rir"),
                aproximaciones = Aproximacion.lista(o.valorJson("aproximaciones")),
            )
        }
    }
}

/** Una serie de preparación escrita en el plan: reps (número o texto corto), % del peso de trabajo o kg, y una nota. */
data class Aproximacion(val reps: String? = null, val pct: Double? = null, val kg: Double? = null, val nota: String? = null) {
    companion object {
        /** La lista del plan: null si no es una lista o si ninguna serie se pudo leer; `[]` queda `[]`. */
        fun lista(v: ValorJson?): List<Aproximacion>? {
            val l = (v as? ValorJson.Lista)?.elementos ?: return null
            val series = l.mapNotNull(::una)
            return if (l.isEmpty() || series.isNotEmpty()) series else null
        }

        internal fun una(v: ValorJson): Aproximacion? {
            val o = (v as? ValorJson.Objeto)?.campos ?: return null
            val reps = when (val r = o["reps"]) {
                is ValorJson.Numero -> r.valor.takeIf { it.isFinite() && it >= 1 && it <= 100 }?.let { Math.round(it).toInt().toString() }
                is ValorJson.Texto -> r.valor.trim().takeIf { it.isNotEmpty() && r.valor.length <= 12 }
                else -> null
            }
            val pct = numero(o["pct"])?.takeIf { it > 0 && it <= 150 }
            val kg = numero(o["kg"])?.takeIf { it > 0 && it <= 1000 }
            val nota = (o["nota"] as? ValorJson.Texto)?.valor?.takeIf { it.isNotBlank() }
            return if (reps != null || kg != null) Aproximacion(reps, pct, kg, nota) else null
        }

        private fun numero(v: ValorJson?): Double? = when (v) {
            is ValorJson.Numero -> v.valor.takeIf { it.isFinite() }
            is ValorJson.Texto -> v.valor.replace("%", "").replace(",", ".").trim().toDoubleOrNull()?.takeIf { it.isFinite() }
            else -> null
        }
    }
}

data class Imagenes(
    val eccentric: String? = null,
    val concentric: String? = null,
    /** El slug que lee la app para los sustitutos (no `catalogo_slug`). Ver `reference_sustitutos_ejercicio_app`. */
    val matchedSlug: String? = null,
) {
    companion object {
        fun desde(e: JsonElement): Imagenes {
            val o = e.comoObjeto("Imagenes")
            return Imagenes(o.texto("eccentric"), o.texto("concentric"), o.texto("_matched_slug"))
        }
    }
}

/** Una semana de la progresión, YA CALCULADA por el Cerebro: la app la muestra, no la inventa. */
data class Progresion(
    val semana: Int? = null,
    val series: Int? = null,
    val reps: String? = null,
    val rir: String? = null,
    val titulo: String? = null,
) {
    companion object {
        fun desde(e: JsonElement): Progresion {
            val o = e.comoObjeto("Progresion")
            return Progresion(o.entero("semana"), o.entero("series"), o.texto("reps"), o.texto("rir"), o.texto("titulo"))
        }
    }
}
