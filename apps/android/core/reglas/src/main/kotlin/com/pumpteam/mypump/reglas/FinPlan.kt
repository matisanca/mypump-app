package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson

/*
 * Fin de plan, «Tu recorrido» (2.3.0, palanca `fin_plan`). Lógica pura y textos; contrato en `cola-b/CONTRATO_APP.md`,
 * sección 1. Quién lo ve lo decide el servidor: la app no calcula nada con fechas y no recibe ninguna.
 *
 * Textos: los del contrato, tal cual. Nunca «renovación», «vence» ni «vencimiento»; nunca «tu coach» ni «tu entrenador».
 */

data class LogroRecorrido(val titulo: String, val valor: String, val detalle: String?)

data class ResumenRecorrido(val titulo: String?, val mensaje: String?, val logros: List<LogroRecorrido>)

/** Lo que el alumno le cuenta a Mati antes de hablar. Todo opcional. */
data class RespuestasRecorrido(val mejor: String = "", val costo: String = "", val objetivo: String = "") {
    val vacias: Boolean get() = mejor.isBlank() && costo.isBlank() && objetivo.isBlank()

    fun con(clave: String, texto: String): RespuestasRecorrido = when (clave) {
        FinPlan.CLAVE_MEJOR -> copy(mejor = FinPlan.recortar(texto))
        FinPlan.CLAVE_COSTO -> copy(costo = FinPlan.recortar(texto))
        FinPlan.CLAVE_OBJETIVO -> copy(objetivo = FinPlan.recortar(texto))
        else -> this
    }

    fun de(clave: String): String = when (clave) {
        FinPlan.CLAVE_MEJOR -> mejor
        FinPlan.CLAVE_COSTO -> costo
        FinPlan.CLAVE_OBJETIVO -> objetivo
        else -> ""
    }

    /** Lo que viaja en `p_respuestas` (y lo que se guarda): solo lo que tiene texto, recortado. */
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            for (k in FinPlan.CLAVES) {
                val t = FinPlan.recortar(de(k).trim())
                if (t.isNotEmpty()) put(k, ValorJson.Texto(t))
            }
        },
    )

    companion object {
        fun desde(j: ValorJson?): RespuestasRecorrido = RespuestasRecorrido(
            mejor = FinPlan.recortar(j?.get(FinPlan.CLAVE_MEJOR)?.comoTexto ?: ""),
            costo = FinPlan.recortar(j?.get(FinPlan.CLAVE_COSTO)?.comoTexto ?: ""),
            objetivo = FinPlan.recortar(j?.get(FinPlan.CLAVE_OBJETIVO)?.comoTexto ?: ""),
        )
    }
}

data class Recorrido(
    val estado: Estado,
    val resumen: ResumenRecorrido,
    /** Lo que ya contestó (lo que guardó el servidor). */
    val respuestas: RespuestasRecorrido,
    /** `agenda`: false = Mati le escribe para coordinar (por defecto); true = el horario se elige en la app. */
    val agendaEnApp: Boolean,
) {
    enum class Estado(val clave: String) { PUBLICADO("publicado"), PEDIDO("pedido"), AGENDADO("agendado") }
}

object FinPlan {
    const val MAX_RESPUESTA = 500
    const val MAX_LOGROS = 6
    const val CLAVE_MEJOR = "mejor"
    const val CLAVE_COSTO = "costo"
    const val CLAVE_OBJETIVO = "objetivo"
    val CLAVES = listOf(CLAVE_MEJOR, CLAVE_COSTO, CLAVE_OBJETIVO)

    /** Lo que dijo `mypump_fin_plan_get`. */
    sealed interface Lectura {
        /** `habilitado:false`, o algo que no se entiende: no se ve nada. */
        data object Apagado : Lectura
        /** Prendido, pero a esta cuenta no se le muestra (o el estado o el resumen no sirven). */
        data object NoVisible : Lectura
        data class Visible(val recorrido: Recorrido) : Lectura
    }

    /** Decodificación tolerante: todo campo es opcional y un estado desconocido o un resumen sin logros no se muestra. */
    fun leer(j: ValorJson): Lectura {
        if (j["habilitado"] != ValorJson.Booleano(true)) return Lectura.Apagado
        if (j["visible"] != ValorJson.Booleano(true)) return Lectura.NoVisible
        val estado = estado(j["estado"]?.comoTexto) ?: return Lectura.NoVisible
        val resumen = resumen(j["resumen"]) ?: return Lectura.NoVisible
        return Lectura.Visible(Recorrido(estado, resumen, RespuestasRecorrido.desde(j["respuestas"]), j["agenda"]?.comoTexto == "app"))
    }

    fun estado(clave: String?): Recorrido.Estado? = Recorrido.Estado.entries.firstOrNull { it.clave == clave }

    private fun texto(v: ValorJson?): String? = v?.comoTexto?.trim()?.takeIf { it.isNotEmpty() }

    /** null: sin logros válidos (no se muestra). Un logro necesita título y valor. */
    fun resumen(j: ValorJson?): ResumenRecorrido? {
        j as? ValorJson.Objeto ?: return null
        val logros = ((j["logros"] as? ValorJson.Lista)?.elementos ?: emptyList()).mapNotNull { l ->
            LogroRecorrido(texto(l["titulo"]) ?: return@mapNotNull null, texto(l["valor"]) ?: return@mapNotNull null, texto(l["detalle"]))
        }.take(MAX_LOGROS)
        if (logros.isEmpty()) return null
        return ResumenRecorrido(texto(j["titulo"]), texto(j["mensaje"]), logros)
    }

    /** El tope de 500 de cada respuesta (por caracteres, sin partir un par sustituto). */
    fun recortar(s: String): String {
        if (s.codePointCount(0, s.length) <= MAX_RESPUESTA) return s
        return s.substring(0, s.offsetByCodePoints(0, MAX_RESPUESTA))
    }

    // ── Lo que se ve ──

    /** Se abre sola una vez: la primera vez que llega visible y sin pedir. */
    fun seAbreSola(r: Recorrido?, yaSeAbrio: Boolean): Boolean = r != null && r.estado == Recorrido.Estado.PUBLICADO && !yaSeAbrio

    /** Las preguntas y el botón «Agendar con Mati» solo antes de pedir. */
    fun pidePreguntas(r: Recorrido): Boolean = r.estado == Recorrido.Estado.PUBLICADO

    fun tituloHoja(r: Recorrido): String = r.resumen.titulo ?: Textos.HOJA_TITULO

    fun textoTarjeta(e: Recorrido.Estado): String = when (e) {
        Recorrido.Estado.PUBLICADO -> Textos.TARJETA_PUBLICADO
        Recorrido.Estado.PEDIDO -> Textos.TARJETA_PEDIDO
        Recorrido.Estado.AGENDADO -> Textos.TARJETA_AGENDADO
    }

    /** El cartel que reemplaza a las preguntas: (principal, debajo). null antes de pedir. */
    fun cartel(r: Recorrido): Pair<String, String?>? = when (r.estado) {
        Recorrido.Estado.PUBLICADO -> null
        Recorrido.Estado.PEDIDO -> Textos.LISTO to (if (r.agendaEnApp) Textos.LISTO_APP else Textos.LISTO_MATI)
        Recorrido.Estado.AGENDADO -> Textos.TARJETA_AGENDADO to null
    }

    object Textos {
        const val TARJETA_TITULO = "Tu recorrido con Mati"
        const val TARJETA_PUBLICADO = "Mirá todo lo que hiciste en estos meses."
        const val TARJETA_PEDIDO = "Mati ya recibió tu pedido."
        const val TARJETA_AGENDADO = "Tu videollamada con Mati ya está agendada."
        const val TARJETA_BOTON = "Ver mi recorrido"
        const val ENTRADA_MIS_DATOS = "Tu recorrido con Mati"
        const val HOJA_TITULO = "Tu recorrido"
        const val PREGUNTAS_TITULO = "Antes de hablar con Mati"
        const val PREGUNTAS_TEXTO = "Si querés, contale esto. Le sirve para prepararse."
        const val PREGUNTA_MEJOR = "¿Qué fue lo mejor de estos meses?"
        const val PREGUNTA_COSTO = "¿Qué te costó más?"
        const val PREGUNTA_OBJETIVO = "¿Qué te gustaría lograr ahora?"
        const val AGENDAR = "Agendar con Mati"
        const val AGENDAR_DEBAJO = "Es una videollamada para ver cómo seguimos."
        const val ENVIANDO = "Enviando…"
        const val ERROR = "No se pudo enviar. Probá de nuevo."
        const val LISTO = "Listo. Mati ya recibió tu pedido."
        const val LISTO_MATI = "Te escribe para coordinar el horario."
        const val LISTO_APP = "Cuando esté tu horario lo vas a ver arriba de Entreno."
        const val CERRAR = "Cerrar"

        fun pregunta(clave: String): String = when (clave) {
            CLAVE_MEJOR -> PREGUNTA_MEJOR
            CLAVE_COSTO -> PREGUNTA_COSTO
            else -> PREGUNTA_OBJETIVO
        }

        /** Para las pruebas: todo lo que puede leer el alumno. */
        val todos = listOf(
            TARJETA_TITULO, TARJETA_PUBLICADO, TARJETA_PEDIDO, TARJETA_AGENDADO, TARJETA_BOTON, ENTRADA_MIS_DATOS, HOJA_TITULO, PREGUNTAS_TITULO,
            PREGUNTAS_TEXTO, PREGUNTA_MEJOR, PREGUNTA_COSTO, PREGUNTA_OBJETIVO, AGENDAR, AGENDAR_DEBAJO, ENVIANDO, ERROR, LISTO, LISTO_MATI,
            LISTO_APP, CERRAR,
        )
    }
}
