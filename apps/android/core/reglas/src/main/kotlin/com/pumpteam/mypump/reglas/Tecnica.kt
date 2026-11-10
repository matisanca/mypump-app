package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.ValorJson

/**
 * Reglas y decodificación de «Técnica por video» (`tecnica/CONTRATO_APP.md`). Decodifica con tolerancia: lo que no se entiende se
 * descarta y un campo roto vale lo de fábrica. Gemelo de Tecnica.swift; `apps/shared/vectores/tecnica.json` hace fallar si difieren.
 */
object Tecnica {
    const val MAX_NOTA = 300
    const val MAX_NOMBRE = 120

    enum class Rechazo(val clave: String) {
        CORTO("corto"), LARGO("largo"), PESADO("pesado"), ILEGIBLE("ilegible"), OTRO("otro");

        val texto: String
            get() = when (this) {
                CORTO -> TextosTecnica.rechazoCorto
                LARGO -> TextosTecnica.rechazoLargo
                PESADO -> TextosTecnica.rechazoPesado
                ILEGIBLE -> TextosTecnica.rechazoIlegible
                OTRO -> TextosTecnica.errorGenerico
            }
    }

    enum class Accion(val clave: String) { OK("ok"), REINTENTAR("reintentar"), DESCARTAR("descartar"), GUARDAR("guardar") }
    data class Subida(val accion: Accion, val rechazo: Rechazo? = null)

    /** 429, 5xx y un 200 raro no gastan el video. Un 403 (link caído o cuenta sin habilitar) tampoco. El resto de los 4xx es definitivo. */
    fun clasificarSubida(status: Int, ok: Boolean, error: String?): Subida {
        if (status in 200..299) return Subida(if (ok) Accion.OK else Accion.REINTENTAR)
        if (status == 429 || status >= 500 || status == 0) return Subida(Accion.REINTENTAR)
        if (status == 403) return Subida(Accion.GUARDAR)
        return when (status) {
            413 -> Subida(Accion.DESCARTAR, Rechazo.PESADO)
            400 -> {
                val e = (error ?: "").lowercase()
                Subida(Accion.DESCARTAR, if ("corto" in e) Rechazo.CORTO else if ("largo" in e) Rechazo.LARGO else Rechazo.ILEGIBLE)
            }
            else -> Subida(Accion.DESCARTAR, Rechazo.OTRO)
        }
    }

    /** Lo que el teléfono puede frenar antes de subir. */
    fun validar(duracion: Double, bytes: Long, topes: TopesTecnica): Rechazo? = when {
        duracion <= 0 || bytes <= 0 -> Rechazo.ILEGIBLE
        duracion < topes.duracionMinS -> Rechazo.CORTO
        // El servidor mide con ffprobe: medio segundo de margen por las diferencias de redondeo del contenedor.
        duracion > topes.duracionMaxS + 0.5 -> Rechazo.LARGO
        bytes > topes.bytesMax -> Rechazo.PESADO
        else -> null
    }

    fun slug(e: Ejercicio): String = (e.catalogoSlug ?: e.matchedSlug ?: e.imagenes?.matchedSlug ?: "").take(MAX_NOMBRE)
    fun nota(s: String): String = s.take(MAX_NOTA)

    /** Los ejercicios de la rutina para elegir: una vez cada uno, en orden, sin calentamientos ni cardio. */
    fun ejerciciosParaElegir(dias: List<Dia>, efectivo: (Ejercicio) -> Ejercicio = { it }): List<Ejercicio> {
        val vistos = HashSet<String>()
        return dias.flatMap { d -> d.bloques.flatMap { b -> b.ejercicios.map(efectivo) } }
            .filter { it.tipo != "calentamiento" && it.tipo != "cardio" && it.nombre.isNotEmpty() && vistos.add(it.nombre.lowercase()) }
    }
}

data class TopesTecnica(val duracionMinS: Double = 4.0, val duracionMaxS: Double = 75.0, val bytesMax: Long = 62_914_560, val porSemana: Int = 3) {
    companion object {
        private fun positivo(j: ValorJson?): Double? = (j as? ValorJson.Numero)?.valor?.takeIf { it > 0 }

        fun desde(j: ValorJson?): TopesTecnica {
            val f = TopesTecnica()
            return TopesTecnica(
                positivo(j?.get("duracion_min_s")) ?: f.duracionMinS, positivo(j?.get("duracion_max_s")) ?: f.duracionMaxS,
                positivo(j?.get("bytes_max"))?.toLong() ?: f.bytesMax, positivo(j?.get("por_semana"))?.toInt() ?: f.porSemana,
            )
        }
    }
}

data class CorreccionTecnica(val prioridad: Int, val titulo: String, val queSeVe: String, val porQue: String, val comoCorregir: String, val momentoS: Double?) {
    companion object {
        fun desde(j: ValorJson): CorreccionTecnica? {
            val t = j["titulo"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            return CorreccionTecnica(
                (j["prioridad"] as? ValorJson.Numero)?.valor?.toInt() ?: 99, t, j["que_se_ve"]?.comoTexto ?: "", j["por_que"]?.comoTexto ?: "",
                j["como_corregir"]?.comoTexto ?: "", (j["momento_s"] as? ValorJson.Numero)?.valor?.takeIf { it >= 0 },
            )
        }
    }
}

data class NoEvaluableTecnica(val que: String, val motivo: String)

data class DevolucionTecnica(
    val credito: String,
    val ejercicio: String?,
    val bien: List<String>,
    val correcciones: List<CorreccionTecnica>,
    val noEvaluable: List<NoEvaluableTecnica>,
    /** El cómo, si hace falta otro video. null: no hace falta. */
    val otroVideo: String?,
) {
    companion object {
        private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()

        fun desde(j: ValorJson?): DevolucionTecnica? {
            if (j !is ValorJson.Objeto) return null
            return DevolucionTecnica(
                j["credito"]?.comoTexto ?: "",
                j["ejercicio"]?.comoTexto,
                lista(j["bien"]).mapNotNull { (it as? ValorJson.Texto)?.valor }.filter { it.isNotEmpty() },
                lista(j["correcciones"]).mapNotNull(CorreccionTecnica::desde).sortedBy { it.prioridad },
                lista(j["no_evaluable"]).mapNotNull { n -> n["que"]?.comoTexto?.takeIf { it.isNotEmpty() }?.let { NoEvaluableTecnica(it, n["motivo"]?.comoTexto ?: "") } },
                j["pedir_otro_video"]?.takeIf { it["necesario"] == ValorJson.Booleano(true) }?.let { it["como"]?.comoTexto ?: "" },
            )
        }
    }
}

data class EnvioTecnica(
    val id: String,
    val estado: Estado,
    val slug: String,
    val nombre: String,
    val nota: String? = null,
    val enviadoEn: String? = null,
    val tieneVideo: Boolean = false,
    val rechazoTexto: String? = null,
    val publicadoEn: String? = null,
    val devolucion: DevolucionTecnica? = null,
) {
    enum class Estado { BORRADOR, ENVIADO, PUBLICADO, RECHAZADO }

    companion object {
        fun desde(j: ValorJson): EnvioTecnica? {
            val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            val e = when (j["estado"]?.comoTexto) {
                "borrador" -> Estado.BORRADOR
                "enviado" -> Estado.ENVIADO
                "publicado" -> Estado.PUBLICADO
                "rechazado" -> Estado.RECHAZADO
                else -> return null
            }
            val dev = DevolucionTecnica.desde(j["devolucion"])
            if (e == Estado.PUBLICADO && dev == null) return null
            return EnvioTecnica(
                id, e, j["ejercicio_slug"]?.comoTexto ?: "", j["ejercicio_nombre"]?.comoTexto ?: "", j["nota_alumno"]?.comoTexto, j["enviado_en"]?.comoTexto,
                j["tiene_video"] == ValorJson.Booleano(true), j["rechazo_texto"]?.comoTexto, j["publicado_en"]?.comoTexto, dev,
            )
        }
    }
}

/** `mypump_tecnica_get` con la sección habilitada. Si no vino `habilitado: true`, null: no se muestra nada. */
data class EstadoTecnica(val topes: TopesTecnica, val envios: List<EnvioTecnica>) {
    /** El borrador es del teléfono: el alumno nunca lo ve en la lista. */
    val visibles: List<EnvioTecnica> get() = envios.filter { it.estado != EnvioTecnica.Estado.BORRADOR }
    val enRevision: EnvioTecnica? get() = envios.firstOrNull { it.estado == EnvioTecnica.Estado.ENVIADO }

    companion object {
        fun desde(j: ValorJson): EstadoTecnica? {
            if (j["habilitado"] != ValorJson.Booleano(true)) return null
            return EstadoTecnica(
                TopesTecnica.desde(j["topes"]),
                (j["envios"] as? ValorJson.Lista)?.elementos?.mapNotNull(EnvioTecnica::desde) ?: emptyList(),
            )
        }
    }
}
