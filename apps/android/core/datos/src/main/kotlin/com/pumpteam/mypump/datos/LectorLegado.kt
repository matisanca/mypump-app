package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File

/**
 * Cuántas unidades UTF-16 tiene un valor y su FNV-1a de 32 bits sobre esas unidades. La escritura de vuelta lo recalcula
 * en JavaScript con `charCodeAt` para comprobar que la clave sigue igual antes de borrarla: es exacto aunque el valor
 * tenga un surrogate suelto (un `String` de Kotlin lo conserva tal cual, como JavaScript). Gemelo de LectorLegado.swift.
 */
data class FirmaValor(val unidades: Int, val fnv: Long) {
    fun aValor(): ValorJson = ValorJson.objeto("unidades" to numero(unidades), "fnv" to numero(fnv.toDouble()))

    companion object {
        fun de(s: CharSequence): FirmaValor {
            var h = 0x811C9DC5.toInt()
            for (c in s) h = (h xor c.code) * 0x01000193
            return FirmaValor(s.length, h.toLong() and 0xFFFFFFFFL)
        }

        fun desde(v: ValorJson?): FirmaValor? {
            val u = v?.get("unidades")?.comoNumero ?: return null
            val f = v["fnv"]?.comoNumero ?: return null
            return FirmaValor(enteroTruncado(u), f.toLong())
        }
    }
}

/**
 * La huella del almacenamiento viejo: fecha y tamaño de sus archivos (en Android, los de leveldb del WebView). Si cambia
 * desde la última migración, alguien volvió a la Capacitor y la migración se repite.
 */
data class HuellaLegado(val archivos: List<Archivo>) {
    data class Archivo(val ruta: String, val bytes: Long, val modificado: Double)

    fun aValor(): ValorJson = ValorJson.objeto(
        "archivos" to ValorJson.Lista(
            archivos.map { ValorJson.objeto("ruta" to texto(it.ruta), "bytes" to numero(it.bytes.toDouble()), "modificado" to numero(it.modificado)) },
        ),
    )

    companion object {
        fun desde(v: ValorJson?): HuellaLegado? {
            val l = v?.get("archivos") as? ValorJson.Lista ?: return null
            return HuellaLegado(
                l.elementos.mapNotNull { a ->
                    val ruta = a["ruta"]?.comoTexto ?: return@mapNotNull null
                    Archivo(ruta, a["bytes"]?.comoNumero?.toLong() ?: -1, a["modificado"]?.comoNumero ?: 0.0)
                },
            )
        }
    }
}

/** Lo leído: las claves del `localStorage` viejo con sus valores tal cual, la firma de cada valor y la huella. */
data class LecturaLegado(val items: Map<String, String>, val firmas: Map<String, FirmaValor>, val huella: HuellaLegado)

/**
 * Cómo se llega al almacenamiento viejo de la app Capacitor. En iOS es la Ruta B (los archivos de WebKit con SQLite); en
 * Android lo lee un WebView en el mismo origen (`https://localhost`), que vive en `:app` y necesita un teléfono: acá queda
 * la interfaz, y los tests usan un lector en memoria.
 */
interface LectorLegado {
    /** ¿Hay almacenamiento viejo? Barato: se mira en cada arranque. */
    fun hay(): Boolean

    /** Solo `stat`: se compara con la de la corrida anterior para saber si hay algo nuevo. */
    fun huella(): HuellaLegado

    /**
     * Lee todas las claves. null = no hay almacenamiento viejo. Un error de lectura TIRA: no es lo mismo que "vacío" (con
     * el teléfono bloqueado o un archivo a medio copiar, concluir "no había nada" perdería todo).
     */
    suspend fun leer(): LecturaLegado?

    /** La copia cruda, ANTES de tocar nada: los archivos tal cual en `destino`. Devuelve las rutas copiadas. */
    fun copiarCrudo(destino: File): List<String>
}
