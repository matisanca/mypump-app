package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

/**
 * Archivos JSON del cliente, uno por cuenta (la carpeta lleva un hash del token, como la web lleva el token en la clave
 * de localStorage: dos cuentas en el mismo teléfono no se mezclan). Escritura atómica: se escribe un temporal al lado y
 * se renombra encima, así un corte a mitad de escritura deja el archivo anterior entero y nunca uno a medias (T1).
 *
 * En la app la raíz es `filesDir`, y `MyPump/` está fuera del backup (ver `reglas_backup.xml`): restaurar en otro
 * teléfono la cola de escrituras de hace semanas mandaría de nuevo acciones viejas.
 */
class Disco(raiz: File, token: String) {
    val carpeta: File = File(raiz, "MyPump/cuenta-" + huella(token))

    fun archivo(nombre: String): File = File(carpeta, nombre)

    /** El JSON guardado, o null si no está o está roto. */
    fun leer(nombre: String): JsonElement? = leerJson(archivo(nombre))

    /** Devuelve si quedó escrito. */
    fun guardar(nombre: String, valor: JsonElement): Boolean = escribirAtomico(archivo(nombre), valor.toString())

    fun guardar(nombre: String, valor: ValorJson): Boolean = guardar(nombre, valor.aJson())

    fun borrar(nombre: String) {
        archivo(nombre).delete()
    }

    companion object {
        fun sha256(texto: String): String =
            MessageDigest.getInstance("SHA-256").digest(texto.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

        /** Identifica la cuenta sin guardar el token: la carpeta, el push (`mypump_push_cuenta`) y Salud la usan. */
        fun huella(token: String): String = sha256(token).take(16)
    }
}

internal fun leerJson(archivo: File): JsonElement? = try {
    if (archivo.isFile) Json.parseToJsonElement(archivo.readText(Charsets.UTF_8)) else null
} catch (_: Exception) {
    null
}

internal fun escribirAtomico(archivo: File, texto: String): Boolean = escribirAtomico(archivo, texto.toByteArray(Charsets.UTF_8))

/**
 * Escribe un temporal en la misma carpeta y lo renombra encima del archivo (rename es atómico en el mismo disco). El
 * temporal se baja al disco (fsync) antes del rename: si el teléfono se apaga justo después, el archivo nuevo está
 * entero, no vacío. Lo usa también el token cifrado de :app. Devuelve si quedó escrito.
 */
fun escribirAtomico(archivo: File, bytes: ByteArray): Boolean = try {
    val carpeta = archivo.absoluteFile.parentFile
    carpeta.mkdirs()
    val temporal = File.createTempFile(".${archivo.name}.", ".tmp", carpeta)
    try {
        java.io.FileOutputStream(temporal).use { s ->
            s.write(bytes)
            s.fd.sync()
        }
        try {
            Files.move(temporal.toPath(), archivo.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (_: AtomicMoveNotSupportedException) {
            Files.move(temporal.toPath(), archivo.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
        true
    } finally {
        temporal.delete()   // si el rename salió, ya no existe
    }
} catch (_: Exception) {
    false
}
