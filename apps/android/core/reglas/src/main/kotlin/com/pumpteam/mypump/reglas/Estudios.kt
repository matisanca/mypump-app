package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.LocalDate
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

// «Estudios y órdenes» (`estudios/CONTRATO_APP.md`). Lo que llega de `mypump_estudios_get`, decodificado sin exigir nada:
// todo campo es opcional y un `tipo` o un `estado` que la app no conoce no rompe. A la app no le llega nada clínico (ni
// valores, ni rangos, ni diagnósticos) y acá tampoco se arma nada de eso.

private fun ValorJson?.lista(): List<ValorJson> = (this as? ValorJson.Lista)?.elementos ?: emptyList()
private fun ValorJson?.texto(): String? = this?.comoTexto?.takeIf { it.isNotEmpty() }
private fun ValorJson?.entero(): Int? = this?.comoNumero?.takeIf { it.isFinite() && it >= 0 && it < 100_000 }?.toInt()
private fun ValorJson?.dia(): LocalDate? = Estudios.dia(this?.comoTexto)

/**
 * El control que viene y todavía no se puede hacer. Con un control de salud (`controles_app`, [Controles.proximoParaEstudios])
 * trae [cuandoFijo] («El lunes 16/11») y la [nota] de abajo; el del pedido, no.
 */
data class ControlEstudios(
    val tipo: String?,
    val titulo: String,
    val desde: LocalDate?,
    val hasta: LocalDate?,
    val cuandoFijo: String? = null,
    val nota: String? = null,
) {
    /** Lo que dice el bloque debajo del título. */
    val cuando: String? get() = cuandoFijo ?: Estudios.cuandoControl(desde, hasta)
}

/** Algo que Mati pidió y todavía no llegó. `hecho`: el alumno avisó que ya se lo hizo y falta el resultado. */
data class PendienteEstudios(
    val id: String,
    val tipo: String?,
    val titulo: String,
    val detalle: String?,
    val desde: LocalDate?,
    val hasta: LocalDate?,
    val hecho: Boolean,
    val hechoFecha: LocalDate?,
    val ordenId: String?,
    /** El alumno todavía no lo vio. Solo con el `true` del servidor. */
    val nuevo: Boolean = false,
)

data class OrdenEstudios(
    val id: String,
    val tipo: String?,
    val titulo: String,
    val emitida: LocalDate?,
    val vence: LocalDate?,
    val vigente: Boolean,
    /** El alumno todavía no la vio. Solo con el `true` del servidor. */
    val nuevo: Boolean = false,
)

data class EstudioRecibido(val id: String?, val tipo: String?, val titulo: String, val fecha: LocalDate?, val hojas: Int, val visto: Boolean, val sePuedeAbrir: Boolean)

/** Un envío de la app que todavía no se ve como estudio. Los `borrador` no llegan acá. */
data class EnvioRecibido(val id: String?, val archivos: Int, val pedidoId: String?, val enviadoEn: String?)

data class EstadoEstudios(
    /** El día del servidor (Argentina). Sin él, el del teléfono. */
    val hoy: LocalDate?,
    val topeArchivos: Int,
    val topeMb: Int,
    val proximo: ControlEstudios?,
    val pendientes: List<PendienteEstudios>,
    val ordenes: List<OrdenEstudios>,
    val estudios: List<EstudioRecibido>,
    val envios: List<EnvioRecibido>,
    /** Pedidos a la vista y órdenes vigentes que el alumno todavía no vio. Sin el campo (servidor viejo), 0. */
    val novedades: Int = 0,
) {
    fun orden(id: String?): OrdenEstudios? = id?.let { i -> ordenes.firstOrNull { it.id == i } }

    /**
     * El control de salud (`mypump_controles_get`) alimenta el mismo bloque «Próximo control» y gana sobre el del pedido: un
     * solo lugar, con el mismo texto neutro. null deja lo que vino en `proximo_control`.
     */
    fun conControl(c: ControlEstudios?): EstadoEstudios = if (c == null) this else copy(proximo = c)

    companion object {
        /** null: token caído, apagado para esta cuenta (`habilitado: false`) o una respuesta que no es la esperada. */
        fun desde(j: ValorJson?): EstadoEstudios? {
            if (j?.get("habilitado") != ValorJson.Booleano(true)) return null
            val hoy = j["hoy"].dia()
            fun titulo(v: ValorJson) = v["titulo"].texto() ?: TextosEstudios.tituloSinNombre
            return EstadoEstudios(
                hoy = hoy,
                topeArchivos = j["topes"]?.get("archivos_por_envio").entero()?.takeIf { it > 0 } ?: Estudios.TOPE_ARCHIVOS,
                topeMb = j["topes"]?.get("mb_por_archivo").entero()?.takeIf { it > 0 } ?: Estudios.TOPE_MB,
                proximo = (j["proximo_control"] as? ValorJson.Objeto)?.let { ControlEstudios(it["tipo"].texto(), titulo(it), it["desde"].dia(), it["hasta"].dia()) },
                pendientes = j["pendientes"].lista().mapNotNull { p ->
                    PendienteEstudios(
                        id = p["id"].texto() ?: return@mapNotNull null, tipo = p["tipo"].texto(), titulo = titulo(p), detalle = p["detalle"].texto(),
                        desde = p["desde"].dia(), hasta = p["hasta"].dia(),
                        // Un estado desconocido es «pedido».
                        hecho = p["estado"].texto() == "hecho", hechoFecha = p["hecho_fecha"].dia(), ordenId = p["orden_id"].texto(),
                        nuevo = p["nuevo"] == ValorJson.Booleano(true),
                    )
                },
                ordenes = j["ordenes"].lista().mapNotNull { o ->
                    OrdenEstudios(
                        id = o["id"].texto() ?: return@mapNotNull null, tipo = o["tipo"].texto(), titulo = titulo(o), emitida = o["emitida"].dia(), vence = o["vence"].dia(),
                        // Lo decide el servidor: solo un `false` explícito la cierra (el teléfono no la da por vencida por su cuenta).
                        vigente = o["vigente"] != ValorJson.Booleano(false),
                        nuevo = o["nuevo"] == ValorJson.Booleano(true),
                    )
                },
                estudios = j["estudios"].lista().filter { it is ValorJson.Objeto }.map { e ->
                    EstudioRecibido(
                        id = e["id"].texto(), tipo = e["tipo"].texto(), titulo = titulo(e), fecha = e["fecha"].dia(), hojas = e["hojas"].entero() ?: 0,
                        // Un estado desconocido es «Recibido».
                        visto = e["estado"].texto() == "visto", sePuedeAbrir = e["se_puede_abrir"] == ValorJson.Booleano(true) && e["id"].texto() != null,
                    )
                },
                // Los `borrador` son restos de una subida a medias: no se muestran. Un estado desconocido es «enviado».
                envios = j["envios"].lista().filter { it is ValorJson.Objeto && it["estado"].texto() != "borrador" }.map { s ->
                    EnvioRecibido(s["id"].texto(), s["archivos"].entero() ?: 0, s["pedido_id"].texto(), s["enviado_en"].texto())
                },
                novedades = j["novedades"].entero() ?: 0,
            )
        }
    }
}

/** La lógica pura de «Estudios y órdenes»: qué bloques van, cómo se dice cada fecha y qué se hace con cada respuesta de la subida. */
object Estudios {
    const val TOPE_ARCHIVOS = 20
    const val TOPE_MB = 20
    /** Las fotos van a JPEG con el lado mayor en 2400 px y calidad 0,8 (HEIC y PNG se convierten). */
    const val MAX_PX = 2400
    const val CALIDAD = 0.8
    const val MIME_PDF = "application/pdf"
    const val MIME_JPEG = "image/jpeg"
    /** «Ya me lo hice»: el servidor acepta hasta 120 días atrás (y mañana, por el huso). La app ofrece hasta hoy. */
    const val DIAS_ATRAS_HECHO = 120L

    private val DIAS = listOf("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")

    /** "2026-11-19" (o un instante que empieza así). null si no se entiende. */
    fun dia(iso: String?): LocalDate? = try {
        iso?.takeIf { it.length >= 10 }?.let { LocalDate.parse(it.substring(0, 10)) }
    } catch (_: Exception) {
        null
    }

    /** El día de un instante del servidor (`enviado_en`), en la hora del teléfono. */
    fun diaDeInstante(iso: String?, zona: ZoneId = ZoneId.systemDefault()): LocalDate? = try {
        iso?.let { OffsetDateTime.parse(it.replace(' ', 'T')).atZoneSameInstant(zona).toLocalDate() }
    } catch (_: Exception) {
        dia(iso)
    }

    /** "19/11", "2/1": sin ceros a la izquierda. */
    fun diaMes(f: LocalDate): String = "${f.dayOfMonth}/${f.monthValue}"

    /** "jueves 19/11". */
    fun diaLargo(f: LocalDate): String = "${DIAS[f.dayOfWeek.value - 1]} ${diaMes(f)}"

    // ── Qué se muestra ──

    enum class Bloque { PROXIMO, PENDIENTES, SUBIR, ORDENES, ESTUDIOS, VACIO }

    /** El orden de la pantalla. Cada bloque va solo si tiene contenido; el botón de subir, siempre. Sin nada de nada, el texto de vacío. */
    fun bloques(e: EstadoEstudios): List<Bloque> {
        val hayLista = e.estudios.isNotEmpty() || e.envios.isNotEmpty()
        val nada = e.proximo == null && e.pendientes.isEmpty() && e.ordenes.isEmpty() && !hayLista
        return buildList {
            if (nada) add(Bloque.VACIO)
            if (e.proximo != null) add(Bloque.PROXIMO)
            if (e.pendientes.isNotEmpty()) add(Bloque.PENDIENTES)
            add(Bloque.SUBIR)
            if (e.ordenes.isNotEmpty()) add(Bloque.ORDENES)
            if (hayLista) add(Bloque.ESTUDIOS)
        }
    }

    /** El subtítulo de la fila de Mis datos: lo que falta (también lo ya hecho sin resultado) o «Todo al día». */
    fun subtitulo(e: EstadoEstudios): String = TextosEstudios.subtitulo(e.pendientes.size)

    // ── Novedades ──

    /** El `destino` del aviso al teléfono y la escena del link (`?scene=estudios`). */
    const val DESTINO = "estudios"

    /** La tarjeta a la que hay que llevar al alumno dentro de Estudios. */
    sealed interface Ancla {
        val id: String

        data class Pendiente(override val id: String) : Ancla
        data class Orden(override val id: String) : Ancla
    }

    /** La novedad de Estudios para una lista de novedades del plan: el texto y a dónde lleva. */
    data class Novedad(val titulo: String, val destino: String)

    /** La tarjeta de arriba de la primera pestaña. `nueva`: hay algo sin ver; si no, es el recordatorio de lo que falta hacer. */
    data class TarjetaInicio(val titulo: String, val boton: String, val nueva: Boolean)

    /** El punto de la pestaña y de la fila de Mis datos: mientras el servidor diga que hay algo sin ver. */
    fun hayNovedad(e: EstadoEstudios): Boolean = e.novedades > 0

    /** Los ids (pedidos y órdenes, mezclados) que el alumno todavía no vio: lo único que se manda a marcar. */
    fun nuevas(e: EstadoEstudios): List<String> = e.pendientes.filter { it.nuevo }.map { it.id } + e.ordenes.filter { it.nuevo }.map { it.id }

    /**
     * Con algo sin ver: «Tenés un estudio nuevo para hacer» si hay un pedido nuevo y «Tenés una orden nueva» si lo nuevo son
     * solo órdenes. Ninguno dice qué estudio ni por qué. Si el servidor cuenta novedades y no marca ninguna fila, se decide
     * por lo que hay: con pedidos, el estudio; sin pedidos, la orden.
     */
    fun novedad(e: EstadoEstudios): Novedad? {
        if (!hayNovedad(e)) return null
        val pedido = e.pendientes.any { it.nuevo } || (e.ordenes.none { it.nuevo } && e.pendientes.isNotEmpty())
        return Novedad(if (pedido) TextosEstudios.estudioNuevo else TextosEstudios.ordenNueva, DESTINO)
    }

    /**
     * Con novedad, su texto y «Ver». Sin novedad y con algo por hacer, «Tenés un estudio para hacer» y «Subir resultado».
     * Sin ninguna de las dos cosas no hay tarjeta.
     */
    fun tarjetaInicio(e: EstadoEstudios): TarjetaInicio? {
        novedad(e)?.let { return TarjetaInicio(it.titulo, TextosEstudios.ver, nueva = true) }
        if (e.pendientes.isEmpty()) return null
        return TarjetaInicio(TextosEstudios.estudioParaHacer, TextosEstudios.subirResultado, nueva = false)
    }

    /**
     * A qué tarjeta se lleva al llegar desde un aviso o desde la tarjeta de arriba: la primera nueva en el orden de la
     * pantalla (los pedidos van antes que las órdenes); sin nada nuevo, el primer pedido. null: no hay a dónde.
     */
    fun ancla(e: EstadoEstudios): Ancla? =
        e.pendientes.firstOrNull { it.nuevo }?.let { Ancla.Pendiente(it.id) }
            ?: e.ordenes.firstOrNull { it.nuevo }?.let { Ancla.Orden(it.id) }
            ?: e.pendientes.firstOrNull()?.let { Ancla.Pendiente(it.id) }

    // ── Fechas ──

    /** «Semana del 23/11» si de punta a punta hay hasta 7 días; si no, «Entre el lunes 23/11 y el viernes 4/12». */
    fun cuandoControl(desde: LocalDate?, hasta: LocalDate?): String? = when {
        desde != null && hasta != null && hasta.isBefore(desde) -> TextosEstudios.semanaDel(diaMes(desde))
        desde != null && hasta != null && ChronoUnit.DAYS.between(desde, hasta) > 7 -> TextosEstudios.entreElYEl(diaLargo(desde), diaLargo(hasta))
        desde != null -> TextosEstudios.semanaDel(diaMes(desde))
        hasta != null -> TextosEstudios.antesDel(diaLargo(hasta))
        else -> null
    }

    /** `pasada`: va en ámbar, nunca en rojo ni con tono de alarma. */
    data class Cuando(val texto: String, val pasada: Boolean)

    /** «Antes del jueves 19/11», «Entre el lunes 16/11 y el jueves 19/11» o, ya pasada, «Era para el jueves 19/11». */
    fun cuandoPendiente(desde: LocalDate?, hasta: LocalDate?, hoy: LocalDate?): Cuando? {
        hasta ?: return null
        return when {
            // Sin el día del servidor no se da nada por pasado.
            hoy != null && hasta.isBefore(hoy) -> Cuando(TextosEstudios.eraParaEl(diaLargo(hasta)), true)
            desde != null && desde.isBefore(hasta) -> Cuando(TextosEstudios.entreElYEl(diaLargo(desde), diaLargo(hasta)), false)
            else -> Cuando(TextosEstudios.antesDel(diaLargo(hasta)), false)
        }
    }

    fun hecho(fecha: LocalDate?): String = fecha?.let { TextosEstudios.hechoEl(diaMes(it)) } ?: TextosEstudios.hechoSinFecha

    /** Los renglones de una orden: «Emitida el 3/11» y «Vale hasta el 2/1», o el aviso de vencida. */
    fun renglonesOrden(o: OrdenEstudios): List<String> = buildList {
        o.emitida?.let { add(TextosEstudios.emitidaEl(diaMes(it))) }
        if (o.vigente) o.vence?.let { add(TextosEstudios.valeHasta(diaMes(it))) } else add(TextosEstudios.ordenVencida)
    }

    /** «3/11 · 4 hojas» o «Sin fecha · 1 hoja». */
    fun detalleEstudio(e: EstudioRecibido): String =
        listOfNotNull(e.fecha?.let(::diaMes) ?: TextosEstudios.sinFecha, e.hojas.takeIf { it > 0 }?.let(TextosEstudios::hojas)).joinToString(" · ")

    fun estado(e: EstudioRecibido): String = if (e.visto) TextosEstudios.matiLoVio else TextosEstudios.recibido

    fun tituloEnvio(s: EnvioRecibido, zona: ZoneId = ZoneId.systemDefault()): String =
        diaDeInstante(s.enviadoEn, zona)?.let { TextosEstudios.envioDel(diaMes(it)) } ?: TextosEstudios.envio

    /** «Envío del 10/11 · 3 archivos · Recibido», entero, para el lector de pantalla. */
    fun envioCompleto(s: EnvioRecibido, zona: ZoneId = ZoneId.systemDefault()): String =
        listOfNotNull(tituloEnvio(s, zona), s.archivos.takeIf { it > 0 }?.let(TextosEstudios::archivos), TextosEstudios.recibido).joinToString(" · ")

    /** Los días que ofrece «¿Cuándo te lo hiciste?»: de hoy hacia atrás. */
    fun fechaHechoValida(f: LocalDate, hoy: LocalDate): Boolean = !f.isAfter(hoy) && !f.isBefore(hoy.minusDays(DIAS_ATRAS_HECHO))

    // ── La hoja de subida ──

    /** «Subiendo 2 de 5»: el que está saliendo, nunca más que el total. */
    fun progreso(subidos: Int, total: Int): String {
        val t = maxOf(1, total)
        return TextosEstudios.subiendo((subidos + 1).coerceIn(1, t), t)
    }

    fun restan(enLaHoja: Int, tope: Int = TOPE_ARCHIVOS): Int = maxOf(0, tope - enLaHoja)
    fun pesaDeMas(bytes: Long, topeMb: Int = TOPE_MB): Boolean = bytes > topeMb.toLong() * 1024 * 1024

    /** Un PDF empieza con `%PDF-`. Lo demás que venga del selector de archivos no se manda. */
    fun esPdf(principio: ByteArray): Boolean {
        val marca = "%PDF-".toByteArray(Charsets.US_ASCII)
        return principio.size >= marca.size && marca.indices.all { principio[it] == marca[it] }
    }

    // ── La cola ──

    enum class Accion { OK, DESCARTAR, REINTENTAR }

    /** 200 con `ok` (también `ya`): hecho. 429 y 5xx: más tarde. Cualquier otro 4xx (también 408) es definitivo para ese archivo. */
    fun clasificarSubida(status: Int, ok: Boolean): Accion = when {
        status in 200..299 -> if (ok) Accion.OK else Accion.REINTENTAR
        status == 429 || status >= 500 -> Accion.REINTENTAR
        status in 400..499 -> Accion.DESCARTAR
        else -> Accion.REINTENTAR
    }
}
