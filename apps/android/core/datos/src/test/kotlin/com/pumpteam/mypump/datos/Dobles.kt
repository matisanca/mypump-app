package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking

/**
 * Los archivos compartidos con iOS (`apps/shared/`): las respuestas REALES grabadas de la API. Un doble que contesta un
 * contrato inventado pasa con el bug vivo (lección del 19-sep).
 */
object Compartido {
    val raizRepo: Path by lazy {
        System.getProperty("mypump.raizRepo")?.let { Paths.get(it) }
            ?: generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
                .firstOrNull { Files.isDirectory(it.resolve("apps/shared/fixtures")) }
            ?: error("no encuentro la raíz del repo (apps/shared)")
    }

    fun archivo(relativo: String): Path = raizRepo.resolve("apps/shared").resolve(relativo)

    fun texto(relativo: String): String = Files.readString(archivo(relativo))

    /** Una respuesta grabada de la cuenta de prueba `test-nativa-real` (la de los tests de regresión de iOS). */
    fun muestra(nombre: String): String = archivo("fixtures/test-nativa-real/$nombre.json").let {
        if (Files.exists(it)) Files.readString(it) else "[]"
    }
}

/** Transporte que contesta una respuesta grabada de la API (`apps/shared/fixtures/errores/`). */
class Grabado(private val status: Int, private val cuerpo: String) : Transporte {
    override suspend fun enviar(pedido: Pedido): Respuesta = Respuesta(status, cuerpo.toByteArray())

    companion object {
        fun de(nombre: String): Grabado {
            val j = ValorJson.parsear(Compartido.texto("fixtures/errores/$nombre.json"))
            return Grabado(j["status"]?.comoNumero?.toInt() ?: 0, j["cuerpo"]?.comoTexto ?: "")
        }
    }
}

/** Sin señal: OkHttp tira una IOException. */
object SinRed : Transporte {
    override suspend fun enviar(pedido: Pedido): Respuesta = throw IOException("sin conexión a internet")
}

/** El wifi del gym: un 200 que no es JSON. */
object PortalCautivo : Transporte {
    override suspend fun enviar(pedido: Pedido): Respuesta = Respuesta(200, "<html>Iniciá sesión en el wifi del gym</html>".toByteArray())
}

/** Transporte programable: decide por nombre de función y por el cuerpo. Anota cada llamada. */
class TransporteProgramado(private val regla: suspend (fn: String, cuerpo: ValorJson) -> Pair<Int, String>) : Transporte {
    private val anotadas = mutableListOf<String>()
    val llamadas: List<String> get() = synchronized(anotadas) { anotadas.toList() }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val fn = pedido.ruta.substringAfterLast('/')
        val cuerpo = pedido.cuerpo?.let { runCatching { ValorJson.parsear(it.toString(Charsets.UTF_8)) }.getOrNull() } ?: ValorJson.Nulo
        synchronized(anotadas) { anotadas += fn }
        val (status, texto) = regla(fn, cuerpo)
        return Respuesta(status, texto.toByteArray())
    }
}

/**
 * Corre el test como corre la app con el `@MainActor` de iOS: todo en UN hilo (el de `runBlocking`), intercalado solo en
 * las esperas. Lo que los modelos lanzan (sondeo del chat, espera del agua, temporizadores) va a un alcance propio que se
 * cancela al final, así un sondeo de 45 s no deja colgado el test.
 */
fun enUnHilo(cuerpo: suspend CoroutineScope.(alcance: CoroutineScope) -> Unit) = runBlocking {
    val alcance = CoroutineScope(coroutineContext + SupervisorJob())
    try {
        cuerpo(alcance)
    } finally {
        alcance.cancel()
    }
}

/** Una carpeta temporal para los archivos de una cuenta. */
fun carpetaTemporal(prefijo: String): File = Files.createTempDirectory(prefijo).toFile().also { it.deleteOnExit() }
