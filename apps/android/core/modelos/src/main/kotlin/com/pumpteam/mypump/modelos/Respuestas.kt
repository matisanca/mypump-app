package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonElement

// Filas que devuelven las RPC de lectura (ver docs/NATIVA_CONTRATO.md §2). Las fechas quedan como texto ISO: las
// interpreta la capa de reglas con calendario gregoriano.

data class ClienteInfo(val clienteId: String, val nombre: String?, val perfil: String?) {
    companion object {
        fun desde(e: JsonElement): ClienteInfo {
            val o = e.comoObjeto("ClienteInfo")
            return ClienteInfo(o.texto("cliente_id") ?: "", o.texto("nombre"), o.texto("perfil"))
        }
    }
}

/** `get_historico_por_clave` (trae `clave`) y el camino viejo por lugar (`ejercicio_id`). */
data class RegistroHistorico(
    val clave: String?,
    val ejercicioId: String?,
    val registradoEn: String,
    val pesoKg: Double?,
    val reps: Int?,
    val rir: Int?,
    val serie: Int?,
    val notas: String?,
    val ejercicioNombre: String?,
) {
    companion object {
        fun desde(e: JsonElement): RegistroHistorico {
            val o = e.comoObjeto("RegistroHistorico")
            return RegistroHistorico(
                clave = o.texto("clave"), ejercicioId = o.texto("ejercicio_id"), registradoEn = o.texto("registrado_en") ?: "",
                pesoKg = o.decimal("peso_kg"), reps = o.entero("reps_realizadas"), rir = o.entero("rir_real"),
                serie = o.entero("serie_numero"), notas = o.texto("notas"), ejercicioNombre = o.texto("ejercicio_nombre"),
            )
        }
    }
}

/** `get_registros_sesion` (fila de `mypump_registros_carga`). */
data class RegistroSesion(
    val ejercicioId: String,
    val serie: Int,
    val pesoKg: Double?,
    val reps: Int?,
    val rir: Int?,
    val ejercicioNombre: String?,
    val notas: String?,
) {
    companion object {
        fun desde(e: JsonElement): RegistroSesion {
            val o = e.comoObjeto("RegistroSesion")
            return RegistroSesion(
                ejercicioId = o.texto("ejercicio_id") ?: "", serie = o.entero("serie_numero") ?: 1, pesoKg = o.decimal("peso_kg"),
                reps = o.entero("reps_realizadas"), rir = o.entero("rir_real"), ejercicioNombre = o.texto("ejercicio_nombre"),
                notas = o.texto("notas"),
            )
        }
    }
}

data class EstadoEjercicio(val ejercicioId: String, val status: String, val seriesCompletadas: Int?, val marcadoManualmente: Boolean) {
    companion object {
        fun desde(e: JsonElement): EstadoEjercicio {
            val o = e.comoObjeto("EstadoEjercicio")
            return EstadoEjercicio(
                ejercicioId = o.texto("ejercicio_id") ?: "", status = o.texto("status") ?: "pendiente",
                seriesCompletadas = o.entero("series_completadas"), marcadoManualmente = o.booleano("marcado_manualmente") ?: false,
            )
        }
    }
}

/** `get_sesion_dia` (con `id`) y `get_sesiones_semana` (sin `id`). */
data class Sesion(val id: String?, val diaId: String, val semana: Int?, val iniciadaEn: String?, val finalizadaEn: String?) {
    val cerrada: Boolean get() = finalizadaEn != null

    companion object {
        fun desde(e: JsonElement): Sesion {
            val o = e.comoObjeto("Sesion")
            return Sesion(o.texto("id"), o.texto("dia_id") ?: "", o.entero("semana"), o.texto("iniciada_en"), o.texto("finalizada_en"))
        }
    }
}

data class HabitosDia(
    val fecha: String?,
    val entrenamiento: String?,
    val comioSegunPlan: Boolean?,
    val durmioBien: Boolean?,
    val cardio: Boolean?,
    val vasosAgua: Int?,
) {
    companion object {
        fun desde(e: JsonElement): HabitosDia {
            val o = e.comoObjeto("HabitosDia")
            return HabitosDia(
                fecha = o.texto("fecha"), entrenamiento = o.texto("entrenamiento"), comioSegunPlan = o.booleano("comio_segun_plan"),
                durmioBien = o.booleano("durmio_bien"), cardio = o.booleano("cardio"), vasosAgua = o.entero("vasos_agua"),
            )
        }
    }
}

data class Racha(val streak: Int, val ultimoDiaValido: String?) {
    companion object {
        fun desde(e: JsonElement): Racha {
            val o = e.comoObjeto("Racha")
            return Racha(o.entero("streak") ?: 0, o.texto("ultimo_dia_valido"))
        }
    }
}

data class DiaAdherencia(
    val fecha: String,
    val entrenamiento: String?,
    val comioSegunPlan: Boolean?,
    val durmioBien: Boolean?,
    val vasosAgua: Int?,
    val esValido: Boolean,
) {
    companion object {
        fun desde(e: JsonElement): DiaAdherencia {
            val o = e.comoObjeto("DiaAdherencia")
            return DiaAdherencia(
                fecha = o.texto("fecha") ?: "", entrenamiento = o.texto("entrenamiento"), comioSegunPlan = o.booleano("comio_segun_plan"),
                durmioBien = o.booleano("durmio_bien"), vasosAgua = o.entero("vasos_agua"), esValido = o.booleano("es_valido") ?: false,
            )
        }
    }
}

data class ComidaMarcada(
    val comidaId: String,
    val opcionElegida: String?,
    val estado: String?,
    val marcadaEn: String?,
    val foodsExcluidos: List<Int>,
) {
    companion object {
        fun desde(e: JsonElement): ComidaMarcada {
            val o = e.comoObjeto("ComidaMarcada")
            return ComidaMarcada(
                comidaId = o.texto("comida_id") ?: "", opcionElegida = o.texto("opcion_elegida"), estado = o.texto("estado"),
                marcadaEn = o.texto("marcada_en"), foodsExcluidos = o.lista("foods_excluidos", Lector::enteroEstricto),
            )
        }
    }
}

data class ComidaLibre(
    val id: String,
    val fecha: String?,
    val hora: String?,
    val descripcion: String?,
    val kcal: Double?,
    val prot: Double?,
    val carb: Double?,
    val fat: Double?,
    val detalle: ValorJson?,
) {
    companion object {
        fun desde(e: JsonElement): ComidaLibre {
            val o = e.comoObjeto("ComidaLibre")
            return ComidaLibre(
                id = o.texto("id") ?: "", fecha = o.texto("fecha"), hora = o.texto("hora"), descripcion = o.texto("descripcion"),
                kcal = o.decimal("kcal"), prot = o.decimal("prot"), carb = o.decimal("carb"), fat = o.decimal("fat"),
                detalle = o.valorJson("detalle"),
            )
        }
    }
}

data class FoodSwap(
    val comidaId: String,
    val optIdx: Int,
    val foodIdx: Int,
    /** Se conserva entero (`_orig`, `_dev`, `_isCustom`…) para devolverlo igual al servidor. */
    val foodData: ValorJson,
) {
    companion object {
        fun desde(e: JsonElement): FoodSwap {
            val o = e.comoObjeto("FoodSwap")
            return FoodSwap(
                comidaId = o.texto("comida_id") ?: "", optIdx = o.entero("opt_idx") ?: 0, foodIdx = o.entero("food_idx") ?: 0,
                foodData = o["food_data"]?.let(ValorJson::desde) ?: ValorJson.Nulo,
            )
        }
    }
}

data class AlimentoPropio(
    val nombre: String,
    val kcal: Double?,
    val prot: Double?,
    val carb: Double?,
    val fat: Double?,
    val unidad: String?,
    val gramosPorUnidad: Double?,
    val categoria: String?,
) {
    companion object {
        fun desde(e: JsonElement): AlimentoPropio {
            val o = e.comoObjeto("AlimentoPropio")
            return AlimentoPropio(
                nombre = o.texto("name") ?: "", kcal = o.decimal("kcal"), prot = o.decimal("prot"), carb = o.decimal("carb"),
                fat = o.decimal("fat"), unidad = o.texto("unit"), gramosPorUnidad = o.decimal("unit_grams"), categoria = o.texto("category"),
            )
        }
    }
}

data class PreferenciasCliente(val excluir: List<String>, val idioma: String) {
    companion object {
        fun desde(e: JsonElement): PreferenciasCliente {
            val o = e.comoObjeto("PreferenciasCliente")
            return PreferenciasCliente(o.textos("excluir") ?: emptyList(), o.texto("idioma") ?: "es")
        }
    }
}

data class Comentario(
    val id: String,
    val ambito: String,
    val referenciaId: String?,
    val referenciaNombre: String?,
    val autor: String,
    val contenido: String,
    val leidoPorCliente: Boolean?,
    val createdAt: String,
) {
    companion object {
        fun desde(e: JsonElement): Comentario {
            val o = e.comoObjeto("Comentario")
            return Comentario(
                id = o.texto("id") ?: "", ambito = o.texto("ambito") ?: "general", referenciaId = o.texto("referencia_id"),
                referenciaNombre = o.texto("referencia_nombre"), autor = o.texto("autor") ?: "", contenido = o.texto("contenido") ?: "",
                leidoPorCliente = o.booleano("leido_por_cliente"), createdAt = o.texto("created_at") ?: "",
            )
        }
    }
}

/** `get_chat` y `chat_nuevos` (este último sin `leido_por_cliente`). */
data class MensajeChat(val id: String, val autor: String, val contenido: String, val leidoPorCliente: Boolean?, val createdAt: String) {
    val esDelCoach: Boolean get() = autor == "coach"

    companion object {
        fun desde(e: JsonElement): MensajeChat {
            val o = e.comoObjeto("MensajeChat")
            return MensajeChat(
                id = o.texto("id") ?: "", autor = o.texto("autor") ?: "", contenido = o.texto("contenido") ?: "",
                leidoPorCliente = o.booleano("leido_por_cliente"), createdAt = o.texto("created_at") ?: "",
            )
        }
    }
}

data class FilaSalud(val fecha: String, val tipo: String, val valor: Double?, val fuente: String?, val detalle: ValorJson?) {
    companion object {
        fun desde(e: JsonElement): FilaSalud {
            val o = e.comoObjeto("FilaSalud")
            return FilaSalud(o.texto("fecha") ?: "", o.texto("tipo") ?: "", o.decimal("valor"), o.texto("fuente"), o.valorJson("detalle"))
        }
    }
}

data class Recuperacion(
    val fecha: String,
    val score: Int?,
    val estado: String?,
    val banda: String?,
    val diasDatos: Int?,
    val bandaProvisoria: Boolean?,
    val estadoAutonomico: String?,
    val hrvMetrica: String?,
    val discordancia: Boolean?,
    val cobertura: ValorJson?,
    val motivos: ValorJson?,
) {
    companion object {
        fun desde(e: JsonElement): Recuperacion {
            val o = e.comoObjeto("Recuperacion")
            return Recuperacion(
                fecha = o.texto("fecha") ?: "", score = o.entero("score"), estado = o.texto("estado"), banda = o.texto("banda"),
                diasDatos = o.entero("dias_datos"), bandaProvisoria = o.booleano("banda_provisoria"),
                estadoAutonomico = o.texto("estado_autonomico"), hrvMetrica = o.texto("hrv_metrica"),
                discordancia = o.booleano("discordancia"), cobertura = o.valorJson("cobertura"), motivos = o.valorJson("motivos"),
            )
        }
    }
}

data class Conexion(val proveedor: String, val estado: String, val ultimoPullEn: String?) {
    companion object {
        fun desde(e: JsonElement): Conexion {
            val o = e.comoObjeto("Conexion")
            return Conexion(o.texto("proveedor") ?: "", o.texto("estado") ?: "", o.texto("ultimo_pull_en"))
        }
    }
}

data class CheckinSemana(val energia: Int?, val descanso: Int?, val hambre: Int?, val adherencia: Int?, val nota: String?) {
    companion object {
        fun desde(e: JsonElement): CheckinSemana {
            val o = e.comoObjeto("CheckinSemana")
            return CheckinSemana(o.entero("energia"), o.entero("descanso"), o.entero("hambre"), o.entero("adherencia"), o.texto("nota"))
        }
    }
}

data class FotoProgreso(val semanaLunes: String, val pose: String, val tomadaEl: String?, val createdAt: String?) {
    companion object {
        fun desde(e: JsonElement): FotoProgreso {
            val o = e.comoObjeto("FotoProgreso")
            return FotoProgreso(o.texto("semana_lunes") ?: "", o.texto("pose") ?: "", o.texto("tomada_el"), o.texto("created_at"))
        }
    }
}
