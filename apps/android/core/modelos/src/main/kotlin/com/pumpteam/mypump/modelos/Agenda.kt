package com.pumpteam.mypump.modelos

import java.time.Instant
import java.time.OffsetDateTime
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * La agenda de la videollamada al final de «Tu guía» (`entregas_app_agenda`, propuesta `entregas_021_agenda`): si ya se puede
 * agendar, las franjas libres del profesional y la reserva, si la hay. El servidor decide todo: la app no calcula franjas
 * ni habla con Google, solo pide, muestra y reserva.
 *
 * Decodificación tolerante como el resto: sin `ok: true` no hay agenda (y la app no muestra nada nuevo); `autorizada` que
 * falta es false (servidor viejo, punto de control E10); una franja sin `id` o con horas que no se entienden se descarta.
 */
data class AgendaEntrega(
    /** Lo que dijo el servidor. Lo que se muestra mira también [autorizada]: ver [puedeAgendar]. */
    val habilitada: Boolean,
    /**
     * `autorizada` (E10, `agenda_habilitada_en` del cliente): Mati ya dio el OK de horarios. Si falta, false. La agenda se
     * abre solo con esto y los obligatorios vistos.
     */
    val autorizada: Boolean,
    /** Los obligatorios que le faltan según el servidor. null si no vino. */
    val faltan: Int?,
    /** La zona de las franjas (la de Argentina). Solo informativa: las horas traen su desplazamiento. */
    val zona: String?,
    /** En orden de inicio. Solo con [habilitada] y sin reserva vigente. */
    val franjas: List<FranjaEntrega>,
    val reserva: ReservaEntrega?,
    /** `aviso_min` (spec §7): desde cuántos minutos antes se avisa en Entreno. null = el de la app (30). */
    val avisoMin: Int? = null,
    /** `textos` (spec §7): clave → texto que pisa el de la app (con `{hora}`, `{dia}`, `{duracion}`, `{faltan}`). */
    val textos: Map<String, String> = emptyMap(),
    /** De comienzo o de revisión: la que se va a agendar (la reserva trae la suya). Sin el campo, de comienzo. */
    val tipo: TipoVideollamada = TipoVideollamada.COMIENZO,
    /** Si la reserva vigente se puede cambiar desde la app (videollamada 2.3.0). null: no (servidor viejo o sin reserva). */
    val cambio: CambioAgenda? = null,
    /** `entrar_desde_min` (1..60): desde cuántos minutos antes se habilita «Entrar». null: los 10 de la app. */
    val entrarDesdeMin: Int? = null,
) {
    /**
     * Se pueden elegir franjas: lo que diga `habilitada` del servidor (spec §7: ya aplica `autorizada` y, si
     * `exigir_obligatorios`, los videos). La app nunca bloquea por su cuenta si el servidor la habilitó.
     */
    val puedeAgendar: Boolean get() = habilitada

    fun aValor(): ValorJson = ValorJson.Objeto(
        linkedMapOf(
            "ok" to ValorJson.Booleano(true),
            "habilitada" to ValorJson.Booleano(habilitada),
            "autorizada" to ValorJson.Booleano(autorizada),
            "faltan" to (faltan?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
            "zona" to (zona?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "franjas" to ValorJson.Lista(franjas.map { it.aValor() }),
            "reserva" to (reserva?.aValor() ?: ValorJson.Nulo),
            "aviso_min" to (avisoMin?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
            "textos" to ValorJson.Objeto(LinkedHashMap(textos.mapValues { ValorJson.Texto(it.value) })),
            "tipo" to ValorJson.Texto(tipo.valor),
            "cambio" to (cambio?.aValor() ?: ValorJson.Nulo),
            "entrar_desde_min" to (entrarDesdeMin?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
        ),
    )

    companion object {
        /** La respuesta de `entregas_app_agenda`. null si no es `ok: true` (`token`, `sin_guia` o una forma rota). */
        fun desde(e: JsonElement?): AgendaEntrega? {
            val o = e as? JsonObject ?: return null
            if (o["ok"]?.let(Lector::booleanoCrudo) != true) return null
            val reserva = ReservaEntrega.desde(o["reserva"])
            val cambio = CambioAgenda.desde(o["cambio"])
            // Con una reserva vigente no hay nada que elegir, aunque el servidor mandara franjas de más. Con una confirmada
            // que el servidor deja cambiar (`cambio.permitido`), sí: son los horarios libres para el cambio.
            val paraCambio = reserva?.estado == ReservaEntrega.Estado.CONFIRMADA && cambio?.permitido == true
            return AgendaEntrega(
                habilitada = o["habilitada"]?.let(Lector::booleanoCrudo) ?: false,
                autorizada = o["autorizada"]?.let(Lector::booleanoCrudo) ?: false,
                faltan = o.entero("faltan")?.takeIf { it >= 0 },
                zona = o.cadena("zona")?.trim()?.ifEmpty { null },
                franjas = if (reserva?.vigente == true && !paraCambio) emptyList()
                else o.lista("franjas", FranjaEntrega::desde).distinctBy { it.id }.sortedBy { it.inicio },
                reserva = reserva,
                avisoMin = o.entero("aviso_min")?.takeIf { it in 0..24 * 60 },
                // Solo textos no vacíos; lo demás (un número, null) se ignora y queda el de la app.
                textos = (o["textos"] as? JsonObject).orEmpty().mapNotNull { (k, v) ->
                    (v as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.ifEmpty { null }?.let { k to it }
                }.toMap(),
                tipo = TipoVideollamada.desde(o.cadena("tipo")),
                cambio = cambio,
                entrarDesdeMin = o.entero("entrar_desde_min")?.takeIf { it in 1..60 },
            )
        }

        fun desde(v: ValorJson?): AgendaEntrega? = v?.let { desde(it.aJson()) }

        /** Una hora ISO con zona («2026-11-12T10:00:00-03:00» o con Z). null si no se entiende. */
        fun instante(iso: String?): Instant? {
            val t = iso?.trim()?.ifEmpty { null } ?: return null
            return try {
                OffsetDateTime.parse(t).toInstant()
            } catch (_: Exception) {
                try {
                    Instant.parse(t)
                } catch (_: Exception) {
                    // Postgres puede mandar «2026-11-12 13:00:00+00»: el espacio y la zona sin minutos.
                    try {
                        OffsetDateTime.parse(t.replace(' ', 'T').replace(Regex("([+-]\\d{2})$"), "$1:00")).toInstant()
                    } catch (_: Exception) {
                        null
                    }
                }
            }
        }
    }
}

/**
 * Una franja libre, como la arma el servidor. Los horarios y la duración son solo datos (pueden cambiar: 10, 11 y 12 con
 * llamadas más cortas): la app no supone ninguna hora ni duración, la saca de [inicio] y [fin].
 */
data class FranjaEntrega(val id: String, val inicio: Instant, val fin: Instant) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "id" to ValorJson.Texto(id),
        "inicio" to ValorJson.Texto(inicio.toString()),
        "fin" to ValorJson.Texto(fin.toString()),
    )

    companion object {
        fun desde(e: JsonElement): FranjaEntrega? {
            val o = e as? JsonObject ?: return null
            val id = o.texto("id")?.trim()?.ifEmpty { null } ?: return null
            val inicio = AgendaEntrega.instante(o.cadena("inicio")) ?: return null
            // Sin fin (o uno que no cierra) no se sabe cuánto dura: la franja no se muestra.
            val fin = AgendaEntrega.instante(o.cadena("fin"))?.takeIf { it.isAfter(inicio) } ?: return null
            return FranjaEntrega(id, inicio, fin)
        }
    }
}

/**
 * La reserva del cliente: `pendiente` (el daemon de la Mini todavía no creó el evento), `confirmada` (con el link de Meet,
 * o null en la demo) o `fallo` (`tomada`: la franja se ocupó en el medio; `error`). Viene en la agenda y, para la tarjeta
 * de Entreno, en `entregas_app_resumen` (sin `id` ni `motivo`).
 */
data class ReservaEntrega(
    val id: String?,
    val inicio: Instant?,
    val fin: Instant?,
    val estado: Estado,
    val meetUrl: String?,
    val motivo: String?,
    /**
     * `sala_abierta_en` (opcional): el daemon lo carga cuando Mati ya entró al Meet. Desde la 2.3.0 «Entrar» se habilita
     * 10 minutos antes sin esto (Meet restringido); con esto, también antes y con «Mati ya está en la sala».
     */
    val salaAbiertaEn: Instant? = null,
    /** De comienzo o de revisión (sin el campo, de comienzo). */
    val tipo: TipoVideollamada = TipoVideollamada.COMIENZO,
) {
    enum class Estado(val valor: String) { PENDIENTE("pendiente"), CONFIRMADA("confirmada"), FALLO("fallo") }

    /** Pendiente o confirmada: no se eligen franjas. */
    val vigente: Boolean get() = estado != Estado.FALLO

    fun aValor(): ValorJson = ValorJson.objeto(
        "id" to (id?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "inicio" to (inicio?.let { ValorJson.Texto(it.toString()) } ?: ValorJson.Nulo),
        "fin" to (fin?.let { ValorJson.Texto(it.toString()) } ?: ValorJson.Nulo),
        "estado" to ValorJson.Texto(estado.valor),
        "meet_url" to (meetUrl?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "motivo" to (motivo?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "sala_abierta_en" to (salaAbiertaEn?.let { ValorJson.Texto(it.toString()) } ?: ValorJson.Nulo),
        "tipo" to ValorJson.Texto(tipo.valor),
    )

    companion object {
        /** null si no es un objeto o el estado no es uno de los tres (uno que no se conoce no se muestra). */
        fun desde(e: JsonElement?): ReservaEntrega? {
            val o = e as? JsonObject ?: return null
            val estado = o.texto("estado")?.trim()?.lowercase()?.let { s -> Estado.entries.firstOrNull { it.valor == s } } ?: return null
            val inicio = AgendaEntrega.instante(o.cadena("inicio"))
            return ReservaEntrega(
                id = o.texto("id")?.trim()?.ifEmpty { null },
                inicio = inicio,
                // Sin fin queda null: no se inventa una duración (ver `ReglasAgenda.finDe`).
                fin = AgendaEntrega.instante(o.cadena("fin"))?.takeIf { inicio == null || it.isAfter(inicio) },
                estado = estado,
                // Solo un link https: otra cosa no se abre.
                meetUrl = o.cadena("meet_url")?.trim()?.takeIf { it.startsWith("https://", ignoreCase = true) },
                motivo = o.texto("motivo")?.trim()?.ifEmpty { null },
                salaAbiertaEn = AgendaEntrega.instante(o.cadena("sala_abierta_en")),
                tipo = TipoVideollamada.desde(o.cadena("tipo")),
            )
        }

        fun desde(v: ValorJson?): ReservaEntrega? = v?.let { desde(it.aJson()) }
    }
}

/**
 * Qué videollamada es (videollamada 2.3.0). Al alumno nunca se le dice «entrega»: «de comienzo» o «de revisión». Sin el
 * campo, o con uno que no se conoce, es la de comienzo (la única que existía).
 */
enum class TipoVideollamada(val valor: String) {
    COMIENZO("comienzo"),
    REVISION("revision"),
    ;

    companion object {
        fun desde(s: String?): TipoVideollamada {
            val t = s?.trim()?.lowercase() ?: return COMIENZO
            return entries.firstOrNull { it.valor == t } ?: COMIENZO
        }
    }
}

/**
 * Si la reserva se puede cambiar desde la app (`cambio` de `entregas_app_agenda`, CONTRATO_RPC de la videollamada). Lo decide
 * el servidor: cuántos cambios le quedan ([restantes]) y hasta cuándo ([hasta]). Sin el objeto, no se puede.
 */
data class CambioAgenda(val permitido: Boolean, val restantes: Int? = null, val hasta: Instant? = null) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "permitido" to ValorJson.Booleano(permitido),
        "restantes" to (restantes?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
        "hasta" to (hasta?.let { ValorJson.Texto(it.toString()) } ?: ValorJson.Nulo),
    )

    companion object {
        /** null si no es un objeto (un texto o un número no cuentan). */
        fun desde(e: JsonElement?): CambioAgenda? {
            val o = e as? JsonObject ?: return null
            return CambioAgenda(
                permitido = o["permitido"]?.let(Lector::booleanoCrudo) ?: false,
                restantes = o.entero("restantes")?.coerceAtLeast(0),
                hasta = AgendaEntrega.instante(o.cadena("hasta")),
            )
        }
    }
}
