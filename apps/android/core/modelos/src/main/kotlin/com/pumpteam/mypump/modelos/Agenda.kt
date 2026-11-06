package com.pumpteam.mypump.modelos

import java.time.Instant
import java.time.OffsetDateTime
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * La agenda de la entrega al final de «Tu guía» (`entregas_app_agenda`, propuesta `entregas_021_agenda`): si ya se puede
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
) {
    /** Se pueden elegir franjas: habilitada **y** autorizada (sin `autorizada` del servidor, nunca). */
    val puedeAgendar: Boolean get() = habilitada && autorizada

    fun aValor(): ValorJson = ValorJson.Objeto(
        linkedMapOf(
            "ok" to ValorJson.Booleano(true),
            "habilitada" to ValorJson.Booleano(habilitada),
            "autorizada" to ValorJson.Booleano(autorizada),
            "faltan" to (faltan?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
            "zona" to (zona?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "franjas" to ValorJson.Lista(franjas.map { it.aValor() }),
            "reserva" to (reserva?.aValor() ?: ValorJson.Nulo),
        ),
    )

    companion object {
        /** La respuesta de `entregas_app_agenda`. null si no es `ok: true` (`token`, `sin_guia` o una forma rota). */
        fun desde(e: JsonElement?): AgendaEntrega? {
            val o = e as? JsonObject ?: return null
            if (o["ok"]?.let(Lector::booleanoCrudo) != true) return null
            val reserva = ReservaEntrega.desde(o["reserva"])
            return AgendaEntrega(
                habilitada = o["habilitada"]?.let(Lector::booleanoCrudo) ?: false,
                autorizada = o["autorizada"]?.let(Lector::booleanoCrudo) ?: false,
                faltan = o.entero("faltan")?.takeIf { it >= 0 },
                zona = o.cadena("zona")?.trim()?.ifEmpty { null },
                // Con una reserva vigente no hay nada que elegir, aunque el servidor mandara franjas de más.
                franjas = if (reserva?.vigente == true) emptyList()
                else o.lista("franjas", FranjaEntrega::desde).distinctBy { it.id }.sortedBy { it.inicio },
                reserva = reserva,
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

/** Una franja libre: 2 h que empiezan a las 10 o a las 14 de Argentina (lo arma el servidor). */
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
            // Sin fin (o uno que no cierra), las 2 h de siempre.
            val fin = AgendaEntrega.instante(o.cadena("fin"))?.takeIf { it.isAfter(inicio) } ?: inicio.plusSeconds(2 * 3600)
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
     * `sala_abierta_en` (opcional, cambio de Mati del 6/11): el daemon lo carga cuando Mati ya entró al Meet. Hasta ahí no
     * hay botón para entrar (salvo el respaldo de la hora de inicio, ver `ReglasAgenda.puedeEntrar`).
     */
    val salaAbiertaEn: Instant? = null,
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
                fin = AgendaEntrega.instante(o.cadena("fin"))?.takeIf { inicio == null || it.isAfter(inicio) } ?: inicio?.plusSeconds(2 * 3600),
                estado = estado,
                // Solo un link https: otra cosa no se abre.
                meetUrl = o.cadena("meet_url")?.trim()?.takeIf { it.startsWith("https://", ignoreCase = true) },
                motivo = o.texto("motivo")?.trim()?.ifEmpty { null },
                salaAbiertaEn = AgendaEntrega.instante(o.cadena("sala_abierta_en")),
            )
        }

        fun desde(v: ValorJson?): ReservaEntrega? = v?.let { desde(it.aJson()) }
    }
}
