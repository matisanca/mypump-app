package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson

/**
 * La palanca remota (`mypump_app_config`, G2: `nativa_001`): lo que se puede pausar desde el servidor sin publicar una
 * versión nueva. Sin la tabla (PGRST202) vale lo de fábrica, que es lo que la app hace hoy: todo prendido y sin versión
 * mínima. Se lee sin token, junto con la rutina y la dieta. Gemelo de PalancaRemota.swift.
 */
data class PalancaRemota(
    /** false: las ops importadas de la Capacitor no se mandan; quedan guardadas para cuando se vuelva a prender. */
    val opsLegadas: Boolean = true,
    /** false: no se borra nada del almacenamiento viejo de la Capacitor. */
    val escrituraVuelta: Boolean = true,
    /** false: un swap de comida anclado que ya no coincide con la dieta se oculta, pero no se borra del servidor. */
    val anclajeBorraSwaps: Boolean = true,
    val versionMinimaIOS: String? = null,
    val versionMinimaAndroid: String? = null,
) {
    companion object {
        val deFabrica = PalancaRemota()

        /** Lo que devolvió `mypump_get_app_config`. Un valor que no es del tipo esperado no cuenta: queda el de fábrica. */
        fun desde(j: ValorJson): PalancaRemota = PalancaRemota(
            opsLegadas = (j["migracion_ops_legadas"] as? ValorJson.Booleano)?.valor ?: true,
            escrituraVuelta = (j["migracion_escritura_vuelta"] as? ValorJson.Booleano)?.valor ?: true,
            anclajeBorraSwaps = (j["anclaje_borra_swaps"] as? ValorJson.Booleano)?.valor ?: true,
            versionMinimaIOS = (j["version_minima_ios"] as? ValorJson.Texto)?.valor?.takeIf { it.isNotEmpty() },
            versionMinimaAndroid = (j["version_minima_android"] as? ValorJson.Texto)?.valor?.takeIf { it.isNotEmpty() },
        )

        /** null = no se pudo preguntar (red o servicio caído): quien llama decide si espera. */
        suspend fun leer(cliente: ClienteRpc): PalancaRemota? = when (val r = cliente.llamar("mypump_get_app_config", emptyMap())) {
            is Resultado.Ok -> desde(r.valor)
            // PGRST202 (la 001 todavía no está) o cualquier otro rechazo: lo de fábrica, la app sigue como hoy.
            is Resultado.Falla -> if (r.error.clase == ErrorRpc.Clase.PERMANENTE) deFabrica else null
        }

        /** ¿La versión instalada está por debajo de la mínima? Número por número: "2.0.10" es mayor que "2.0.9". */
        fun debajo(version: String?, minima: String?): Boolean {
            if (version == null || minima == null) return false
            // `split(separator:)` de Swift no deja partes vacías, y lo que no es un número vale 0.
            fun partes(s: String) = s.split('.').filter { it.isNotEmpty() }.map { it.toLongOrNull() ?: 0L }
            val a = partes(version)
            val b = partes(minima)
            for (i in 0 until maxOf(a.size, b.size)) {
                val x = a.getOrElse(i) { 0L }
                val y = b.getOrElse(i) { 0L }
                if (x != y) return x < y
            }
            return false
        }
    }
}
