package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * «Tu guía» (`entregas_app_get`, obra de entregas `entregas_010_app`): los videos cortos de Mati antes de la videollamada
 * de comienzo, con lo visto, las dudas y la suplementación. La misma página que abre la web (`pack.html`) con su clave; las
 * dos escriben en las mismas tablas.
 *
 * La decodificación es tolerante como la del resto de la app: un campo que falta o viene null toma su valor por defecto,
 * un clip sin `id` o sin `titulo` se descarta (no rompe la lista) y la sección solo existe con `ok: true`.
 */
data class Guia(
    val nombrePila: String?,
    /** ISO con zona, o null (flujo nuevo: la videollamada todavía no se agendó). */
    val fechaEntrega: String?,
    /** En el orden del servidor: por bloque y, dentro de cada uno, por orden. */
    val clips: List<ClipGuia>,
    val dudasLlamada: List<DudaLlamada>,
    /** null o sin ítems: no se muestra. */
    val suplementacion: Suplementacion?,
) {
    fun clip(id: String): ClipGuia? = clips.firstOrNull { it.id == id }

    /**
     * Los clips de la lista y de «Viste X de N» (como la web desde el 4/11, A5): los del bloque «Tu suplementación» que
     * nombra un suplemento (con nombre, `video_id` y que no «sale») se ven debajo de ese suplemento con «Ver por qué» y no
     * van en la lista. Si ningún suplemento los nombra, quedan en la lista para no perderlos.
     */
    val clipsDeLaLista: List<ClipGuia> by lazy {
        val nombrados = suplementacion?.items.orEmpty()
            .filter { it.nombre.isNotBlank() && it.estado != "sale" && it.videoId != null }
            .mapNotNull { it.videoId }.toSet()
        clips.filterNot { esSuplementacion(it.bloque) && it.id in nombrados }
    }

    /** Los que salen de la lista porque los muestra su suplemento ([clipsDeLaLista]). */
    val clipsDeSuplementos: List<ClipGuia> get() = clips.filterNot { it in clipsDeLaLista }

    /** Lo que se guarda en la caché del teléfono (la misma forma del servidor, así se lee con [desde]). */
    fun aValor(): ValorJson = ValorJson.Objeto(
        linkedMapOf(
            "ok" to ValorJson.Booleano(true),
            "nombre_pila" to (nombrePila?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "fecha_entrega" to (fechaEntrega?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "clips" to ValorJson.Lista(clips.map { it.aValor() }),
            "dudas_llamada" to ValorJson.Lista(dudasLlamada.map { it.aValor() }),
            "suplementacion" to (suplementacion?.crudo ?: ValorJson.Nulo),
        ),
    )

    companion object {
        /** La respuesta de `entregas_app_get`. null si no es `ok: true` (sin guía, token inválido o forma rota). */
        fun desde(e: JsonElement?): Guia? {
            val o = e as? JsonObject ?: return null
            if (o["ok"]?.let(Lector::booleanoCrudo) != true) return null
            return Guia(
                nombrePila = o.cadena("nombre_pila")?.trim()?.ifEmpty { null },
                fechaEntrega = o.cadena("fecha_entrega")?.ifEmpty { null },
                clips = o.lista("clips", ClipGuia::desde),
                dudasLlamada = o.lista("dudas_llamada", DudaLlamada::desde),
                suplementacion = Suplementacion.desde(o["suplementacion"]),
            )
        }

        fun desde(v: ValorJson?): Guia? = v?.let { desde(it.aJson()) }
    }
}

data class ClipGuia(
    val id: String,
    /** La pregunta que contesta el video: es lo único que muestra la fila. */
    val titulo: String,
    /** MP4 público del bucket `videos-entrega`. null o vacío: «Lo estoy subiendo» (la fila no se puede tocar). */
    val url: String?,
    val minutos: Double,
    /** «qué hacer ||| para qué» o solo el para qué (ver `PartesMotivo`). */
    val motivo: String?,
    /** El capítulo. Cambia de cliente a cliente: se muestra tal cual viene. */
    val bloque: String?,
    val visto: Boolean,
    /** Hasta dónde llegó (el servidor guarda el mayor). */
    val segundos: Int,
    /** Lo que ya dejó, acumulado con saltos de línea (hasta 3200 caracteres). */
    val duda: String?,
) {
    val sePuedeVer: Boolean get() = !url.isNullOrBlank()

    fun aValor(): ValorJson = ValorJson.Objeto(
        linkedMapOf(
            "id" to ValorJson.Texto(id),
            "titulo" to ValorJson.Texto(titulo),
            "url" to (url?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "minutos" to ValorJson.Numero(minutos),
            "motivo" to (motivo?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "bloque" to (bloque?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "visto" to ValorJson.Booleano(visto),
            "segundos" to ValorJson.Numero(segundos.toDouble()),
            "duda" to (duda?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        ),
    )

    companion object {
        fun desde(e: JsonElement): ClipGuia? {
            val o = e as? JsonObject ?: return null
            val id = o.texto("id")?.trim()?.ifEmpty { null } ?: return null
            val titulo = o.texto("titulo")?.trim()?.ifEmpty { null } ?: return null
            return ClipGuia(
                id = id,
                titulo = titulo,
                url = o.cadena("url")?.trim()?.ifEmpty { null },
                minutos = o.decimal("minutos")?.takeIf { it >= 0 } ?: 0.0,
                motivo = o.texto("motivo")?.trim()?.ifEmpty { null },
                bloque = o.texto("bloque")?.trim()?.ifEmpty { null },
                visto = o.booleano("visto") ?: false,
                segundos = o.decimal("segundos")?.takeIf { it.isFinite() && it > 0 }?.toInt() ?: 0,
                duda = o.cadena("duda")?.ifBlank { null },
            )
        }
    }
}

data class DudaLlamada(val texto: String, val en: String?) {
    fun aValor(): ValorJson = ValorJson.objeto("texto" to ValorJson.Texto(texto), "en" to (en?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo))

    companion object {
        fun desde(e: JsonElement): DudaLlamada? {
            val o = e as? JsonObject ?: return null
            val t = o.cadena("texto")?.ifBlank { null } ?: return null
            return DudaLlamada(t, o.cadena("en"))
        }
    }
}

/**
 * La suplementación con la forma del generador de PDF de Pump: los momentos del día ([dia], en orden) y los ítems, cada
 * uno con su `momento` o sus `tomas`. Se guarda también el JSON [crudo] para la caché (campos que la app no usa, como
 * `comprar`, no se pierden).
 */
data class Suplementacion(
    val titulo: String?,
    val accion: String?,
    val sigueTexto: String?,
    val dia: List<MomentoDia>,
    val items: List<ItemSuplemento>,
    val crudo: ValorJson,
) {
    companion object {
        /** null si no viene, no es un objeto o no tiene ningún ítem con nombre. */
        fun desde(e: JsonElement?): Suplementacion? {
            val o = e as? JsonObject ?: return null
            val items = o.lista("items", ItemSuplemento::desde)
            if (items.isEmpty()) return null
            return Suplementacion(
                titulo = o.cadena("titulo")?.ifBlank { null },
                accion = o.cadena("accion")?.ifBlank { null },
                sigueTexto = o.cadena("sigue_texto")?.ifBlank { null },
                dia = o.lista("dia", MomentoDia::desde),
                items = items,
                crudo = ValorJson.desde(o),
            )
        }
    }
}

data class MomentoDia(val id: String, val nombre: String?) {
    companion object {
        fun desde(e: JsonElement): MomentoDia? {
            val o = e as? JsonObject ?: return null
            val id = o.texto("id")?.ifBlank { null } ?: return null
            return MomentoDia(id, o.texto("nombre")?.ifBlank { null })
        }
    }
}

data class ItemSuplemento(
    val nombre: String,
    val cantidad: String?,
    val momento: String?,
    val tomas: List<TomaSuplemento>,
    val nota: String?,
    /** Un texto o una lista de textos en el JSON; acá siempre lista. Puede traer *negrita* de Markdown. */
    val detalle: List<String>,
    /** «sigue», «nuevo», «sale» u otro (se muestra como lo muestra el PDF). */
    val estado: String?,
    val opcional: Boolean,
    val porQue: String?,
    /** El `id` de un clip (del bloque «Tu suplementación»): el ítem muestra «Ver por qué». */
    val videoId: String?,
) {
    companion object {
        fun desde(e: JsonElement): ItemSuplemento? {
            val o = e as? JsonObject ?: return null
            val nombre = o.texto("nombre")?.trim()?.ifEmpty { null } ?: return null
            val detalle = when (val d = o["detalle"]) {
                is JsonArray -> d.mapNotNull { Lector.textoTolerante(it)?.ifBlank { null } }
                null -> emptyList()
                else -> listOfNotNull(Lector.textoTolerante(d)?.ifBlank { null })
            }
            return ItemSuplemento(
                nombre = nombre,
                cantidad = o.texto("cantidad")?.ifBlank { null },
                momento = o.texto("momento")?.ifBlank { null },
                tomas = o.lista("tomas", TomaSuplemento::desde),
                nota = o.texto("nota")?.ifBlank { null },
                detalle = detalle,
                estado = o.texto("estado")?.trim()?.lowercase()?.ifEmpty { null },
                opcional = o.booleano("opcional") ?: false,
                porQue = o.texto("por_que")?.ifBlank { null },
                videoId = o.texto("video_id")?.ifBlank { null },
            )
        }
    }
}

data class TomaSuplemento(val momento: String, val cantidad: String?, val nota: String?, val nombre: String?) {
    companion object {
        fun desde(e: JsonElement): TomaSuplemento? {
            val o = e as? JsonObject ?: return null
            val m = o.texto("momento")?.ifBlank { null } ?: return null
            return TomaSuplemento(m, o.texto("cantidad")?.ifBlank { null }, o.texto("nota")?.ifBlank { null }, o.texto("nombre")?.ifBlank { null })
        }
    }
}

/**
 * `entregas_app_resumen`: lo que muestra la tarjeta de inicio. Es de solo lectura y no marca `abierto_en`, así que se puede
 * pedir al abrir la app y al volver a primer plano (el `get` queda solo para cuando el cliente abre la sección).
 */
data class ResumenGuia(val total: Int, val vistos: Int, val minutosRestantes: Double) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "ok" to ValorJson.Booleano(true),
        "total" to ValorJson.Numero(total.toDouble()),
        "vistos" to ValorJson.Numero(vistos.toDouble()),
        "minutos_restantes" to ValorJson.Numero(minutosRestantes),
    )

    companion object {
        /** null si no es `ok: true` (sin guía, token inválido o revocado) o si no trae ningún video. */
        fun desde(e: JsonElement?): ResumenGuia? {
            val o = e as? JsonObject ?: return null
            if (o["ok"]?.let(Lector::booleanoCrudo) != true) return null
            val total = o.entero("total")?.takeIf { it > 0 } ?: return null
            val vistos = (o.entero("vistos") ?: 0).coerceIn(0, total)
            val minutos = o.decimal("minutos_restantes")?.takeIf { it >= 0 } ?: 0.0
            return ResumenGuia(total, vistos, minutos)
        }

        fun desde(v: ValorJson?): ResumenGuia? = v?.let { desde(it.aJson()) }

        /** Lo mismo calculado desde la guía entera (cuando el cliente ya la abrió y hay datos más nuevos en memoria). */
        /** Lo mismo que la web en «Viste X de N» (la cabecera de la sección): solo los clips de la lista ([Guia.clipsDeLaLista]). */
        fun de(g: Guia): ResumenGuia? = de(g.clipsDeLaLista)

        /**
         * Con todos los clips, como cuenta hoy `entregas_app_resumen`: es lo de la tarjeta de inicio, que tiene que coincidir
         * con el resumen del servidor (para no saltar entre dos totales). Si el servidor pasa a contar como la web, se usa [de].
         */
        fun deTodos(g: Guia): ResumenGuia? = de(g.clips)

        private fun de(l: List<ClipGuia>): ResumenGuia? {
            if (l.isEmpty()) return null
            val resta = l.filter { !it.visto }.sumOf { it.minutos }
            return ResumenGuia(l.size, l.count { it.visto }, Math.round(resta * 10) / 10.0)
        }
    }
}

/** «Tu suplementación», sin importar mayúsculas ni el acento (como la web). */
internal fun esSuplementacion(bloque: String?): Boolean =
    bloque?.trim()?.lowercase()?.let { it == "tu suplementación" || it == "tu suplementacion" } == true
