package com.pumpteam.mypump.modelos

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/** Dónde están los archivos compartidos con iOS. Gradle pasa las rutas; si no (un IDE), se busca la raíz hacia arriba. */
object Rutas {
    val raizRepo: Path by lazy {
        System.getProperty("mypump.raizRepo")?.let { Paths.get(it) }
            ?: generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
                .firstOrNull { Files.isDirectory(it.resolve("apps/shared/vectores")) }
            ?: error("no encuentro la raíz del repo (apps/shared)")
    }

    /** Los datos sacados de los planes reales: fuera del repo, y en otra Mac no existen (los tests se saltean). */
    val carpetaPrivada: Path by lazy {
        Paths.get(System.getProperty("mypump.carpetaPrivada") ?: (System.getProperty("user.home") + "/Developer/nativa-evidencia/privado"))
    }

    fun compartido(relativo: String): Path = raizRepo.resolve("apps/shared").resolve(relativo)

    fun leer(p: Path): String = Files.readString(p)
}
