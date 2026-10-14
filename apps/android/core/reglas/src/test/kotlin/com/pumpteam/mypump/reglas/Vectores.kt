package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.NumeroJs
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assumptions.assumeTrue

/**
 * Los vectores que genera la web (scripts/nativa/generar-vectores.mjs y compañía): los mismos archivos que leen los tests
 * de iOS. Los públicos están en el repo; los privados (sacados de los planes reales) solo en la Mac de Mati.
 */
object Vectores {
    val raizRepo: Path by lazy {
        System.getProperty("mypump.raizRepo")?.let { Paths.get(it) }
            ?: generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
                .firstOrNull { Files.isDirectory(it.resolve("apps/shared/vectores")) }
            ?: error("no encuentro la raíz del repo (apps/shared)")
    }

    private val carpetaPrivada: Path by lazy {
        Paths.get(System.getProperty("mypump.carpetaPrivada") ?: (System.getProperty("user.home") + "/Developer/nativa-evidencia/privado"))
    }

    fun compartido(relativo: String): Path = raizRepo.resolve("apps/shared").resolve(relativo)

    fun publico(nombre: String): Path = compartido("vectores/$nombre.json")

    /** El vector privado, o el test se saltea (en CI y en otra Mac no existen). */
    fun privado(nombre: String): Path {
        val p = carpetaPrivada.resolve("vectores/$nombre.json")
        assumeTrue(Files.exists(p), "sin vectores privados ($p)")
        return p
    }

    fun json(p: Path): JsonObject = Json.parseToJsonElement(Files.readString(p)).jsonObject

    fun texto(p: Path): String = Files.readString(p)
}

/** Lo que devolvió JS (número, texto o null) contra un texto de Kotlin. */
fun igualAJs(esperado: JsonElement?, kotlin: String?): Boolean = when {
    esperado == null || esperado is JsonNull -> kotlin == null
    esperado is JsonPrimitive && esperado.isString -> esperado.content == kotlin
    esperado is JsonPrimitive -> esperado.content.toDoubleOrNull()?.let { NumeroJs.texto(it) == kotlin } ?: false
    else -> false
}

/** Lo que devolvió JS contra un entero de Kotlin (`Int(d)` o `Int(texto)`, como el test de Swift). */
fun igualAJs(esperado: JsonElement?, kotlin: Int?): Boolean = when {
    esperado == null || esperado is JsonNull -> kotlin == null
    esperado is JsonPrimitive && esperado.isString -> kotlin == esperado.content.toIntOrNull()
    esperado is JsonPrimitive -> esperado.content.toDoubleOrNull()?.let { kotlin == it.toInt() } ?: false
    else -> false
}

/** Para los mensajes: los invisibles a la vista. */
fun String.debug(): String = "\"" + map { if (it.code < 0x20 || it.code in 0x7F..0xA0 || it.code > 0x2000) "\\u%04x".format(it.code) else "$it" }.joinToString("") + "\""
