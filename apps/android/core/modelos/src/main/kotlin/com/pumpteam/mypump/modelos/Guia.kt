package com.pumpteam.mypump.modelos

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

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
    /**
     * Los `video_id` que saca de la lista la regla del servidor (`entregas_012`), leídos del JSON tal cual vino (sin
     * recortar ni pasar a minúsculas, como `it ->> 'nombre'` en SQL). Ver [idsNombrados].
     */
    val idsDeSuplementos: Set<String> = emptySet(),
    /** La suplementación tal cual vino, para la caché (así [desde] la vuelve a leer igual). */
    val suplementacionCruda: ValorJson? = suplementacion?.crudo,
) {
    fun clip(id: String): ClipGuia? = clips.firstOrNull { it.id == id }

    /**
     * Los clips de la lista y de «Viste X de N», con la misma regla que `entregas_app_resumen` (`entregas_012`) y la web
     * (A5): un clip sale solo si (a) su bloque es «Tu suplementación» (sin espacios alrededor y sin distinguir mayúsculas;
     * un bloque null no lo es) y (b) su id es el `video_id` de un ítem con nombre no vacío, estado distinto de «sale» y
     * `video_id` no vacío. Esos se ven debajo de su suplemento con «Ver por qué». Si ningún suplemento lo nombra, el clip
     * se sigue mostrando y contando.
     */
    val clipsDeLaLista: List<ClipGuia> by lazy {
        clips.filterNot { esSuplementacion(it.bloque) && it.id in idsDeSuplementos }
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
            "suplementacion" to (suplementacionCruda ?: ValorJson.Nulo),
        ),
    )

    companion object {
        /** La respuesta de `entregas_app_get`. null si no es `ok: true` (sin guía, token inválido o forma rota). */
        fun desde(e: JsonElement?): Guia? {
            val o = e as? JsonObject ?: return null
            if (o["ok"]?.let(Lector::booleanoCrudo) != true) return null
            val s = o["suplementacion"]
            return Guia(
                nombrePila = o.cadena("nombre_pila")?.trim()?.ifEmpty { null },
                fechaEntrega = o.cadena("fecha_entrega")?.ifEmpty { null },
                clips = o.lista("clips", ClipGuia::desde),
                dudasLlamada = o.lista("dudas_llamada", DudaLlamada::desde),
                suplementacion = Suplementacion.desde(s),
                idsDeSuplementos = idsNombrados(s),
                suplementacionCruda = (s as? JsonObject)?.let { ValorJson.desde(it) },
            )
        }

        /**
         * La condición (b) de `entregas_012`, sobre el JSON crudo de `suplementacion`: por cada ítem, `nombre`, `estado` y
         * `video_id` como texto de SQL (`->>`: null o ausente = vacío, un número o un booleano = su texto) y sin tocar.
         */
        fun idsNombrados(s: JsonElement?): Set<String> {
            val items = (s as? JsonObject)?.get("items") as? JsonArray ?: return emptySet()
            fun comoSql(v: JsonElement?): String = when (v) {
                null, is JsonNull -> ""
                is JsonPrimitive -> v.content
                else -> v.toString()
            }
            return items.mapNotNull { it as? JsonObject }
                .filter { comoSql(it["nombre"]) != "" && comoSql(it["estado"]) != "sale" && comoSql(it["video_id"]) != "" }
                .map { comoSql(it["video_id"]) }
                .toSet()
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
            // El id tal cual (como lo compara el servidor con `video_id`): sin recortar.
            val id = o.texto("id")?.ifEmpty { null } ?: return null
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
            // Como la web (`!it.nombre`): solo se descarta sin nombre o con "". Un nombre de espacios cuenta (y nombra su video).
            val nombre = o.texto("nombre")?.ifEmpty { null } ?: return null
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
                // Tal cual: la web y el servidor comparan exacto (`estado === 'sale'`); «Sale» no es «sale».
                estado = o.texto("estado")?.ifEmpty { null },
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
        /**
         * «Viste X de N» de la cabecera y de la tarjeta de inicio: solo los clips de la lista ([Guia.clipsDeLaLista]), como
         * cuenta `entregas_app_resumen` desde `entregas_012` y la web.
         */
        fun de(g: Guia): ResumenGuia? = de(g.clipsDeLaLista)

        private fun de(l: List<ClipGuia>): ResumenGuia? {
            if (l.isEmpty()) return null
            val resta = l.filter { !it.visto }.sumOf { it.minutos }
            return ResumenGuia(l.size, l.count { it.visto }, Math.round(resta * 10) / 10.0)
        }
    }
}

/**
 * La condición (a) de `entregas_012`, la misma expresión del servidor: `coalesce(bloque, '') ~*
 * '^[\s\u00a0\ufeff]*tu suplementaci[oóÓ]n[\s\u00a0\ufeff]*$'` (espacios, no-break y BOM alrededor; sin distinguir
 * mayúsculas). Un bloque null no lo es.
 */
private val BLOQUE_SUPLEMENTACION = Regex("^[\\s\u00a0\ufeff]*tu suplementaci[oóÓ]n[\\s\u00a0\ufeff]*$", RegexOption.IGNORE_CASE)

internal fun esSuplementacion(bloque: String?): Boolean = BLOQUE_SUPLEMENTACION.matches(bloque ?: "")
