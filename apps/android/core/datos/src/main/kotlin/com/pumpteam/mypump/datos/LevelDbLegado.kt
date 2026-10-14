package com.pumpteam.mypump.datos

import java.io.File
import java.io.IOException

/**
 * Dónde dejó la app Capacitor su `localStorage`: el leveldb del WebView del sistema, adentro del directorio de datos de la
 * app. Es la parte del lector que no necesita un teléfono (encontrar la carpeta, mirar fechas y tamaños, copiarla); la
 * lectura la hace un WebView en `:app`.
 *
 * La ruta NO se arma. Depende de la versión del WebView: `app_webview/Default/Local Storage/leveldb` en el emulador con el
 * WebView 133 (desde que el WebView tiene perfiles) y `app_webview/Local Storage/leveldb` en los viejos, y en un teléfono
 * puede ser otra. Es la lección del TF-0 de iOS: la 2.0.0 (100) buscaba la ruta del simulador, en el iPhone no encontró
 * nada y arrancó como recién instalada. Acá se recorren las carpetas `app_webview*` y el leveldb se reconoce por su forma:
 * una carpeta `leveldb` adentro de una `Local Storage`, con su `CURRENT`.
 */
object LevelDbLegado {
    /** Lo que cambia aunque nadie escriba nada: el candado y el registro de texto de leveldb. */
    private val FUERA_DE_LA_HUELLA = setOf("LOCK", "LOG", "LOG.old")

    /** Hasta dónde se baja buscando (`app_webview/Default/Local Storage/leveldb` está a 3; un perfil con nombre, a 4 o 5). */
    private const val PROFUNDIDAD = 8

    /**
     * Las carpetas leveldb del `localStorage` del WebView, en orden de ruta. Vacío = no hay almacenamiento viejo (la
     * Capacitor nunca abrió, o es una instalación nueva de la nativa).
     */
    fun ubicar(datos: File): List<File> {
        val raices = datos.listFiles { f -> f.isDirectory && f.name.startsWith("app_webview") } ?: return emptyList()
        val encontradas = ArrayList<File>()
        for (raiz in raices) {
            raiz.walkTopDown()
                .maxDepth(PROFUNDIDAD)
                .filter { it.isDirectory && esLevelDb(it) }
                .forEach { encontradas += it }
        }
        return encontradas.distinctBy { relativa(it, datos) }.sortedBy { relativa(it, datos) }
    }

    private fun esLevelDb(d: File): Boolean =
        d.name == "leveldb" && d.parentFile?.name == "Local Storage" && File(d, "CURRENT").isFile

    /**
     * Fecha y tamaño de los archivos de datos (`*.log`, `*.ldb`, `MANIFEST-*`, `CURRENT`), con la ruta relativa al
     * directorio de datos de la app. Solo `stat`: se mira en cada arranque.
     */
    fun huella(datos: File, carpetas: List<File>): HuellaLegado {
        val archivos = ArrayList<HuellaLegado.Archivo>()
        for (c in carpetas) {
            val hijos = c.listFiles { f -> f.isFile && f.name !in FUERA_DE_LA_HUELLA } ?: continue
            for (f in hijos.sortedBy { it.name }) {
                archivos += HuellaLegado.Archivo(relativa(f, datos), f.length(), f.lastModified() / 1000.0)
            }
        }
        return HuellaLegado(archivos)
    }

    /**
     * La copia cruda, ANTES de tocar nada: cada carpeta leveldb tal cual (todos sus archivos, también `LOCK` y `LOG`), en
     * `destino/<n>-<ruta>/`. Devuelve las rutas copiadas, relativas a `destino`. Tira si no puede copiar: sin la copia no
     * se sigue (es la red de seguridad de todo lo demás).
     */
    fun copiar(datos: File, carpetas: List<File>, destino: File): List<String> {
        if (!destino.isDirectory && !destino.mkdirs()) throw IOException("no se pudo crear la carpeta de la copia cruda")
        val copiados = ArrayList<String>()
        carpetas.forEachIndexed { n, c ->
            val nombre = "${n + 1}-" + relativa(c, datos).replace(Regex("[^A-Za-z0-9._-]"), "_")
            val dir = File(destino, nombre)
            if (!dir.isDirectory && !dir.mkdirs()) throw IOException("no se pudo crear $nombre")
            val hijos = c.listFiles { f -> f.isFile } ?: throw IOException("no se pudo listar ${relativa(c, datos)}")
            for (f in hijos.sortedBy { it.name }) {
                f.copyTo(File(dir, f.name), overwrite = true)
                copiados += "$nombre/${f.name}"
            }
        }
        return copiados
    }

    /** La ruta relativa al directorio de datos: el absoluto no sirve para comparar (y no dice nada en el recibo). */
    fun relativa(f: File, datos: File): String {
        val base = datos.absoluteFile.normalize().path.trimEnd('/')
        val p = f.absoluteFile.normalize().path
        return if (p.startsWith("$base/")) p.substring(base.length + 1) else f.name
    }
}
