package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.OffsetDateTime
import java.time.ZoneId

/** «Gimnasio por fotos»: la lógica pura que comparten iOS y Android (`apps/shared/vectores/gimnasio.json`). Gemelo de Gimnasio.swift. */
object Gimnasio {
    data class Zona(val clave: String, val nombre: String, val pedido: String)

    /** Las 10 zonas, en el orden del servidor. La foto siempre lleva zona. */
    val zonas = listOf(
        Zona("poleas", "Poleas", "Cada torre y cruce, entero. El peso máximo de la pila"),
        Zona("accesorios_polea", "Accesorios de polea", "Sogas, barras V, rectas, agarres, tobilleras, todos juntos en el piso o colgados"),
        Zona("piernas", "Máquinas de piernas", "Prensa, hack, péndulo, extensora, femorales, aductores, abductores, gemelos, hip thrust"),
        Zona("empuje", "Máquinas de empuje", "Pecho, inclinado, hombros, pec deck, fondos"),
        Zona("tiron", "Máquinas de tirón", "Dorsalera, remos, dominadas asistidas, bíceps, tríceps"),
        Zona("barras_racks", "Barras y racks", "Barras olímpicas y Z, smith, racks, paralelas, barra de dominadas"),
        Zona("discos", "Discos", "Todo el soporte, de cerca: que se lean los números. Incluí los más chicos"),
        Zona("mancuernas", "Mancuernas", "El rack entero, de punta a punta: que se lea hasta cuánto llega"),
        Zona("bancos", "Bancos", "Planos, regulables, Scott"),
        Zona("otros", "Otros", "Bandas, kettlebells, TRX, lo que haya"),
    )
    const val ZONA_OPCIONAL = "otros"
    const val TOPE_FOTOS = 80
    const val MAX_NOTA = 300
    const val MAX_PX = 1600
    const val CALIDAD = 0.8
    const val KILOS_MAXIMO = 400.0

    fun nombreZona(clave: String): String = zonas.firstOrNull { it.clave == clave }?.nombre ?: clave

    fun zonasFaltantes(conFotos: Set<String>, noHay: Set<String>, modo: String = "completa"): List<String> =
        if (modo != "completa") emptyList() else zonas.map { it.clave }.filter { it != ZONA_OPCIONAL && it !in conFotos && it !in noHay }

    fun puedeEnviar(modo: String, conFotos: Set<String>, noHay: Set<String>, quitar: Set<String>): Boolean =
        if (modo == "completa") zonasFaltantes(conFotos, noHay).isEmpty() else conFotos.isNotEmpty() || quitar.isNotEmpty()

    fun restan(enServidor: Int, enCola: Int): Int = maxOf(0, TOPE_FOTOS - enServidor - enCola)
    fun puedeAgregar(enServidor: Int, enCola: Int): Boolean = restan(enServidor, enCola) > 0
    fun notaRecortada(s: String): String = s.take(MAX_NOTA)

    enum class Pantalla(val clave: String) { INICIO("inicio"), ZONAS("zonas"), RECIBIDO("recibido"), PREGUNTAS("preguntas"), LISTO("listo") }

    fun pantalla(abierta: String?, hayVigente: Boolean): Pantalla = when (abierta) {
        null, "reemplazado", "listo" -> if (hayVigente) Pantalla.LISTO else Pantalla.INICIO
        "borrador" -> Pantalla.ZONAS
        "a_confirmar" -> Pantalla.PREGUNTAS
        else -> Pantalla.RECIBIDO
    }

    fun tarjetaVisible(habilitado: Boolean, abierta: String?, hayVigente: Boolean): Boolean = habilitado && (!hayVigente || abierta == "a_confirmar")
    fun entradaVisible(habilitado: Boolean, hayVigente: Boolean): Boolean = habilitado && hayVigente

    enum class Accion(val clave: String) { OK("ok"), DESCARTAR("descartar"), REINTENTAR("reintentar") }
    enum class AvisoFoto(val clave: String) { RECHAZADA("rechazada"), TOPE("tope") }
    data class Subida(val accion: Accion, val refrescar: Boolean = false, val aviso: AvisoFoto? = null)

    /** Todo 4xx salvo 429 es definitivo; 5xx y 429, reintentar. */
    fun clasificarSubida(status: Int, ok: Boolean): Subida = when (status) {
        in 200..299 -> Subida(if (ok) Accion.OK else Accion.REINTENTAR)
        429 -> Subida(Accion.REINTENTAR)
        403 -> Subida(Accion.DESCARTAR)
        404, 409 -> Subida(Accion.DESCARTAR, refrescar = true)
        413 -> Subida(Accion.DESCARTAR, aviso = AvisoFoto.TOPE)
        in 400..499 -> Subida(Accion.DESCARTAR, aviso = AvisoFoto.RECHAZADA)
        else -> Subida(Accion.REINTENTAR)
    }

    private val noSe = ValorJson.Texto("no_se")

    /** `true` si el valor sirve como respuesta (lo que no sirve no se manda: queda dudoso y lo ve EDITOR). */
    fun respuestaValida(p: PreguntaGimnasio, v: ValorJson): Boolean {
        if (v == noSe) return p.clase != PreguntaGimnasio.Clase.FOTO
        return when (p.clase) {
            PreguntaGimnasio.Clase.ELEGIR -> {
                val validos = p.opciones.map { it.valor }.toSet()
                if (p.multiple) {
                    (v as? ValorJson.Lista)?.elementos?.all { it.comoTexto in validos } == true
                } else {
                    v.comoTexto in validos
                }
            }
            PreguntaGimnasio.Clase.NUMERO -> (v.comoNumero ?: return false).let { it > 0 && it <= KILOS_MAXIMO }
            PreguntaGimnasio.Clase.CONFIRMAR -> {
                val o = (v as? ValorJson.Objeto)?.campos ?: return false
                val tipos = p.items.map { it.tipo }.toSet()
                o.all { (k, x) -> k in tipos && x.comoTexto in setOf("si", "no", "no_se") }
            }
            PreguntaGimnasio.Clase.FOTO -> v.comoTexto == "subida" || v.comoTexto == "no_puedo"
            PreguntaGimnasio.Clase.DESCONOCIDA -> false
        }
    }

    /**
     * Lo que se manda a `responder`. [vistas]: las preguntas que el alumno tuvo en pantalla; una de opción múltiple que vio
     * y no marcó va como `[]` («lo que no marques cuenta como que no está»). «No sé» sigue yendo como duda.
     */
    fun respuestasParaEnviar(
        preguntas: List<PreguntaGimnasio>, borrador: Map<String, ValorJson>, vistas: Set<String> = emptySet(),
    ): Map<String, ValorJson> {
        val r = LinkedHashMap<String, ValorJson>()
        for (p in preguntas) {
            val v = borrador[p.id]?.takeIf { respuestaValida(p, it) }
            if (v != null) r[p.id] = v
            else if (p.clase == PreguntaGimnasio.Clase.ELEGIR && p.multiple && p.id in vistas) r[p.id] = ValorJson.Lista(emptyList())
        }
        return r
    }

    fun fotosPedidas(preguntas: List<PreguntaGimnasio>, borrador: Map<String, ValorJson>): Int =
        preguntas.count { it.clase == PreguntaGimnasio.Clase.FOTO && it.id !in borrador }

    fun kilos(s: String): Double? = s.trim().replace(',', '.').toDoubleOrNull()?.takeIf { it.isFinite() && it > 0 && it <= KILOS_MAXIMO }

    /** "12/11", en la hora del teléfono. null si la fecha no se entiende. */
    fun fechaCorta(iso: String?, zona: ZoneId = ZoneId.systemDefault()): String? {
        if (iso == null) return null
        return try {
            val f = OffsetDateTime.parse(iso.replace(' ', 'T')).atZoneSameInstant(zona)
            "%02d/%02d".format(f.dayOfMonth, f.monthValue)
        } catch (_: Exception) {
            null
        }
    }
}

private fun ValorJson?.lista(): List<ValorJson> = (this as? ValorJson.Lista)?.elementos ?: emptyList()

data class OpcionGimnasio(val valor: String, val texto: String)

data class ItemGimnasio(val tipo: String, val texto: String, val fotos: List<String>)

data class PreguntaGimnasio(
    val id: String,
    val clase: Clase,
    val multiple: Boolean,
    val zona: String?,
    val texto: String,
    val unidad: String?,
    val opciones: List<OpcionGimnasio>,
    val items: List<ItemGimnasio>,
    val fotos: List<String>,
) {
    enum class Clase(val clave: String) { ELEGIR("elegir"), NUMERO("numero"), CONFIRMAR("confirmar"), FOTO("foto"), DESCONOCIDA("desconocida") }

    companion object {
        fun desde(j: ValorJson): PreguntaGimnasio? {
            val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            val texto = j["texto"]?.comoTexto ?: (if (j["clase"]?.comoTexto == "confirmar") TextosGimnasio.confirmarTarjeta else return null)
            val clave = j["clase"]?.comoTexto
            return PreguntaGimnasio(
                id = id,
                clase = Clase.entries.firstOrNull { it.clave == clave } ?: Clase.DESCONOCIDA,
                multiple = j["multiple"] == ValorJson.Booleano(true),
                zona = j["zona"]?.comoTexto,
                texto = texto,
                unidad = j["unidad"]?.comoTexto,
                opciones = j["opciones"].lista().mapNotNull { o ->
                    OpcionGimnasio(o["valor"]?.comoTexto ?: return@mapNotNull null, o["texto"]?.comoTexto ?: return@mapNotNull null)
                },
                items = j["items"].lista().mapNotNull { o ->
                    ItemGimnasio(o["tipo"]?.comoTexto ?: return@mapNotNull null, o["texto"]?.comoTexto ?: return@mapNotNull null, o["fotos"].lista().mapNotNull { it.comoTexto })
                },
                fotos = j["fotos"].lista().mapNotNull { it.comoTexto },
            )
        }
    }
}

data class FotoGimnasio(val id: String, val zona: String, val ronda: Int)

data class EquipoGimnasio(val tipo: String, val nombre: String, val zona: String, val cantidad: Int)

data class CargaGimnasio(
    val id: String,
    val estado: String,
    val modo: String,
    val resultado: String?,
    val publicadoEn: String?,
    /** Las de clase desconocida no se muestran: una app vieja no puede contestarlas. */
    val preguntas: List<PreguntaGimnasio>,
    val fotos: List<FotoGimnasio>,
    val zonasNoHay: List<String>,
    val equipos: List<EquipoGimnasio>,
) {
    companion object {
        fun desde(j: ValorJson?): CargaGimnasio? {
            j ?: return null
            val id = j["id"]?.comoTexto ?: return null
            val estado = j["estado"]?.comoTexto ?: return null
            return CargaGimnasio(
                id = id,
                estado = estado,
                modo = j["modo"]?.comoTexto ?: "completa",
                resultado = j["resultado"]?.comoTexto,
                publicadoEn = j["publicado_en"]?.comoTexto,
                preguntas = j["preguntas"].lista().mapNotNull(PreguntaGimnasio::desde).filter { it.clase != PreguntaGimnasio.Clase.DESCONOCIDA },
                fotos = j["fotos"].lista().mapNotNull { f ->
                    FotoGimnasio(f["id"]?.comoTexto ?: return@mapNotNull null, f["zona"]?.comoTexto ?: return@mapNotNull null, f["ronda"]?.comoNumero?.toInt() ?: 0)
                },
                zonasNoHay = j["zonas_no_hay"].lista().mapNotNull { it.comoTexto },
                equipos = j["equipos"].lista().mapNotNull { e ->
                    val t = e["tipo"]?.comoTexto ?: return@mapNotNull null
                    EquipoGimnasio(t, e["nombre"]?.comoTexto ?: t.replace('_', ' '), e["zona"]?.comoTexto ?: Gimnasio.ZONA_OPCIONAL, e["cantidad"]?.comoNumero?.toInt()?.takeIf { it >= 1 } ?: 1)
                },
            )
        }
    }
}

data class EstadoGimnasio(
    val abierta: CargaGimnasio?,
    val vigente: CargaGimnasio?,
) {
    companion object {
        /** null: no es una respuesta con `habilitado:true`. */
        fun desde(j: ValorJson): EstadoGimnasio? {
            if (j["habilitado"] != ValorJson.Booleano(true)) return null
            return EstadoGimnasio(
                abierta = CargaGimnasio.desde(j["abierta"]),
                vigente = CargaGimnasio.desde(j["vigente"]),
            )
        }
    }
}
