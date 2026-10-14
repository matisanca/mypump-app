package com.pumpteam.mypump.datos

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Dónde está el leveldb del `localStorage` viejo. Nunca una ruta fija (la lección del TF-0 de iOS): las dos disposiciones
 * conocidas del WebView, las dos a la vez, y lo que NO es el `localStorage` aunque se parezca.
 */
class LevelDbLegadoTest {
    /** Un leveldb como el que deja Chromium: datos en el `.log`, el manifiesto, `CURRENT`, y el candado y el registro. */
    private fun leveldb(datos: File, ruta: String, log: String = "datos"): File {
        val d = File(datos, ruta).apply { mkdirs() }
        File(d, "CURRENT").writeText("MANIFEST-000001\n")
        File(d, "MANIFEST-000001").writeText("manifiesto")
        File(d, "000003.log").writeText(log)
        File(d, "LOCK").writeText("")
        File(d, "LOG").writeText("abierto")
        return d
    }

    @Test
    fun webViewConPerfiles() {
        val datos = carpetaTemporal("datos")
        leveldb(datos, "app_webview/Default/Local Storage/leveldb")
        assertEquals(listOf("app_webview/Default/Local Storage/leveldb"), LevelDbLegado.ubicar(datos).map { LevelDbLegado.relativa(it, datos) })
    }

    @Test
    fun webViewViejoSinPerfiles() {
        val datos = carpetaTemporal("datos")
        leveldb(datos, "app_webview/Local Storage/leveldb")
        assertEquals(listOf("app_webview/Local Storage/leveldb"), LevelDbLegado.ubicar(datos).map { LevelDbLegado.relativa(it, datos) })
    }

    /** Un teléfono que pasó de un WebView viejo a uno nuevo puede tener las dos: se miran (y se copian) las dos. */
    @Test
    fun lasDosALaVez() {
        val datos = carpetaTemporal("datos")
        leveldb(datos, "app_webview/Local Storage/leveldb")
        leveldb(datos, "app_webview/Default/Local Storage/leveldb")
        val rutas = LevelDbLegado.ubicar(datos).map { LevelDbLegado.relativa(it, datos) }
        assertEquals(listOf("app_webview/Default/Local Storage/leveldb", "app_webview/Local Storage/leveldb"), rutas)
        val destino = File(datos, "files/legado/crudo/x")
        val copiados = LevelDbLegado.copiar(datos, LevelDbLegado.ubicar(datos), destino)
        assertEquals(10, copiados.size)
        assertTrue(copiados.any { it.startsWith("1-app_webview_Default_Local_Storage_leveldb/") })
        assertTrue(copiados.any { it.startsWith("2-app_webview_Local_Storage_leveldb/") })
        assertEquals("datos", File(destino, "1-app_webview_Default_Local_Storage_leveldb/000003.log").readText())
    }

    /** Otras rutas posibles (un perfil con nombre, un sufijo de directorio) se encuentran igual, sin armarlas. */
    @Test
    fun otrasDisposiciones() {
        val datos = carpetaTemporal("datos")
        leveldb(datos, "app_webview/Profiles/Default/Local Storage/leveldb")
        leveldb(datos, "app_webview_otro/Default/Local Storage/leveldb")
        assertEquals(
            listOf("app_webview/Profiles/Default/Local Storage/leveldb", "app_webview_otro/Default/Local Storage/leveldb"),
            LevelDbLegado.ubicar(datos).map { LevelDbLegado.relativa(it, datos) },
        )
    }

    /** Lo que se parece y no es: IndexedDB, Session Storage, un leveldb sin `CURRENT`, una copia cruda en files/. */
    @Test
    fun loQueNoEsElLocalStorage() {
        val datos = carpetaTemporal("datos")
        leveldb(datos, "app_webview/Default/IndexedDB/https_localhost_0.indexeddb.leveldb")
        leveldb(datos, "app_webview/Default/Session Storage")
        File(datos, "app_webview/Default/Local Storage/leveldb").mkdirs()   // sin CURRENT: a medio crear
        leveldb(datos, "files/legado/crudo/20261014T120000Z-abcd1234/Local Storage/leveldb")
        assertTrue(LevelDbLegado.ubicar(datos).isEmpty())
        // Sin app_webview (instalación nueva de la nativa, o la Capacitor nunca abrió): no hay nada.
        assertTrue(LevelDbLegado.ubicar(carpetaTemporal("vacio")).isEmpty())
    }

    /** La huella mira los archivos de datos con `stat`; el candado y el registro de texto cambian solos y no cuentan. */
    @Test
    fun huella() {
        val datos = carpetaTemporal("datos")
        val d = leveldb(datos, "app_webview/Default/Local Storage/leveldb")
        val h1 = LevelDbLegado.huella(datos, LevelDbLegado.ubicar(datos))
        assertEquals(
            listOf("000003.log", "CURRENT", "MANIFEST-000001").map { "app_webview/Default/Local Storage/leveldb/$it" },
            h1.archivos.map { it.ruta },
        )
        File(d, "LOG").appendText(" otra vez")
        File(d, "LOCK").setLastModified(System.currentTimeMillis() + 5_000)
        assertEquals(h1, LevelDbLegado.huella(datos, LevelDbLegado.ubicar(datos)))
        File(d, "000003.log").appendText(" y una escritura")
        assertNotEquals(h1, LevelDbLegado.huella(datos, LevelDbLegado.ubicar(datos)))
        // Una tabla nueva también (leveldb pasa el .log a un .ldb).
        val h2 = LevelDbLegado.huella(datos, LevelDbLegado.ubicar(datos))
        File(d, "000005.ldb").writeText("tabla")
        assertNotEquals(h2, LevelDbLegado.huella(datos, LevelDbLegado.ubicar(datos)))
    }
}
