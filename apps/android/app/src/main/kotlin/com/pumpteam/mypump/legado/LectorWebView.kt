package com.pumpteam.mypump.legado

import android.content.Context
import com.pumpteam.mypump.datos.FallaLectura
import com.pumpteam.mypump.datos.FaseRemotaLegado
import com.pumpteam.mypump.datos.EscrituraJs
import com.pumpteam.mypump.datos.HuellaLegado
import com.pumpteam.mypump.datos.JsAscii
import com.pumpteam.mypump.datos.LecturaJs
import com.pumpteam.mypump.datos.LecturaLegado
import com.pumpteam.mypump.datos.LectorLegado
import com.pumpteam.mypump.datos.LevelDbLegado
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * El almacenamiento viejo de verdad (gemelo de LectorLegado.swift): dónde está y si cambió, por `stat` sobre el leveldb
 * del WebView ([LevelDbLegado], sin rutas fijas); qué tiene, por un WebView oculto en el origen de la Capacitor
 * ([PaginaLegado]). En Android no hay "Ruta B": leer el leveldb a mano no hace falta (lo dice la prueba de la espía) y la
 * confirmación de la escritura de vuelta es otra lectura por el WebView.
 *
 * @param datos el directorio de datos de la app (`dataDir`): ahí están `app_webview*` y `files/`.
 */
internal class LectorWebView(
    private val contexto: Context,
    private val datos: File = contexto.dataDir,
    private val anotar: (String) -> Unit = {},
    private val intentos: Int = INTENTOS,
    private val esperaMs: Long = ESPERA_MS,
) : LectorLegado {
    override fun hay(): Boolean = LevelDbLegado.ubicar(datos).isNotEmpty()

    override fun huella(): HuellaLegado = LevelDbLegado.huella(datos, LevelDbLegado.ubicar(datos))

    /**
     * Todas las claves, con la firma que calculó JavaScript sobre cada valor. La huella se toma DESPUÉS de leer: abrir el
     * leveldb puede reacomodar sus archivos, y lo que tiene que reconocer el arranque siguiente es cómo quedaron. Un error
     * TIRA (no es "vacío").
     */
    override suspend fun leer(): LecturaLegado? {
        if (!hay()) return null
        val l = conPagina(contexto, intentos, esperaMs, { anotar("lectura, $it") }) { p ->
            val prep = LecturaJs.preparada(p.evaluar(LecturaJs.SCRIPT_PREPARAR, esperaMs))
            val texto = StringBuilder(prep.largo)
            var i = 0
            while (i < prep.largo) {
                val tramo = JsAscii.desenvolver(p.evaluar(LecturaJs.scriptTramo(i), esperaMs)) ?: throw FallaLectura("el tramo $i no llegó")
                texto.append(tramo)
                i += LecturaJs.TRAMO
            }
            runCatching { p.evaluar(LecturaJs.SCRIPT_LIMPIAR, esperaMs) }
            if (texto.length != prep.largo) throw FallaLectura("llegaron ${texto.length} caracteres de ${prep.largo}")
            withContext(Dispatchers.Default) { LecturaJs.decodificar(texto.toString(), prep.n) }
        }
        return LecturaLegado(l.items, l.firmas, huella())
    }

    override fun copiarCrudo(destino: File): List<String> = LevelDbLegado.copiar(datos, LevelDbLegado.ubicar(datos), destino)

    companion object {
        const val INTENTOS = 3

        /** La espía tardó 5-9 s en leer más de 1 MB en el emulador, contando el arranque del WebView. */
        const val ESPERA_MS = 25_000L
    }
}

/**
 * La escritura de vuelta (gemelo de EscritorLegado.swift): con el mismo WebView, borra las claves que la nativa ya tomó si
 * siguen iguales a como se leyeron y deja la marca. Se confirma en el arranque siguiente, cuando la lectura la encuentra.
 */
internal class EscritorLegado(private val contexto: Context, private val anotar: (String) -> Unit = {}) {
    suspend fun escribir(c: FaseRemotaLegado.CambiosEscritura, intentos: Int = 3, esperaMs: Long = 20_000): Map<String, String> =
        conPagina(contexto, intentos, esperaMs, { anotar("escritura de vuelta, $it") }) { p ->
            EscrituraJs.resultado(p.evaluar(EscrituraJs.script(c), esperaMs))
        }
}
