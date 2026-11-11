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
    /** Cuántos días atrás acepta «Comí» / «Salté» el servidor (`dieta_dias_marcar`). Sin la clave, lo de fábrica. */
    val diasMarcarDieta: Int? = null,
    /** Gimnasio por fotos (`gimnasio_fotos`). Sin la clave, apagado: ni se muestra ni se llama a nada nuevo. */
    val gimnasioFotos: Boolean = false,
    /** Técnica por video (`tecnica_video`). Sin la clave, apagada: ni se muestra ni se llama a nada nuevo. */
    val tecnicaVideo: Boolean = false,
    /** «Novedades de tu plan» (`novedades_plan`). Sin la clave, apagada: no se guarda ni se muestra nada. */
    val novedadesPlan: Boolean = false,
    /** Devolución de Mati en Revisión (`devolucion_semanal`). Sin la clave, apagada: ni se muestra ni se llama a nada nuevo. */
    val devolucionSemanal: Boolean = false,
    /** Metas de pasos y ritmo de peso, con el «Pump del día» (`metas_pasos`). Sin la clave, apagadas: no se ve nada nuevo. */
    val metasPasos: Boolean = false,
    /** Fotos y audios en el chat (`chat_adjuntos`). Sin la clave, apagado. Prendida, igual decide el servidor por cliente. */
    val chatAdjuntos: Boolean = false,
    /** «Me duele» por ejercicio (`me_duele`). Sin la clave, apagado: ni se muestra ni se llama a nada nuevo. */
    val meDuele: Boolean = false,
    /** «Lo compré / lo estoy tomando» (`suple_estado`). Sin la clave, apagado. */
    val supleEstado: Boolean = false,
    /**
     * Elegir y cambiar el horario de la videollamada en la pantalla nueva (`elegir_horario`, 2.3.0). Sin la clave, apagada:
     * la agenda de la guía queda como en la 2.2.0 y no se llama a `entregas_app_cambiar`.
     */
    val elegirHorario: Boolean = false,
    /** Estudios y órdenes (`estudios_app`). Sin la clave, apagada: ni se muestra ni se llama a nada nuevo. */
    val estudiosApp: Boolean = false,
    /** Fotos de inicio (`fotos_inicio`). Sin la clave, apagadas: ni se muestran ni se llama a nada nuevo. */
    val fotosInicio: Boolean = false,
    /** Fin de plan, «Tu recorrido» (`fin_plan`). Sin la clave, apagada: ni se muestra ni se llama a nada nuevo. */
    val finPlan: Boolean = false,
    /** Compras por país, «Dónde comprarlo» (`compras_pais`). Sin la clave, apagada. */
    val comprasPais: Boolean = false,
    /** Entreno en casa (`casa`): el interruptor de Mi gimnasio. Sin la clave, apagada. Necesita `gimnasio_fotos`. */
    val casa: Boolean = false,
     * Récords y logros (`wins_app`, 2.3.0): el festejo al cerrar la sesión y, con permiso, la cola para Mati. Sin la clave,
     * apagada: ni se muestra ni se llama a nada nuevo.
    val winsApp: Boolean = false,
    /** La lista previa a la videollamada de comienzo (`lista_previa`, 2.3.0). Sin la clave, apagada. */
    val listaPrevia: Boolean = false,
    /** Check guiado (`check_guiado`). Sin la clave, apagado: la Revisión de siempre y ninguna llamada nueva. */
    val checkGuiado: Boolean = false,
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
            diasMarcarDieta = (j["dieta_dias_marcar"] as? ValorJson.Numero)?.valor?.takeIf { it == Math.rint(it) && it in 0.0..30.0 }?.toInt(),
            gimnasioFotos = (j["gimnasio_fotos"] as? ValorJson.Booleano)?.valor ?: false,
            tecnicaVideo = (j["tecnica_video"] as? ValorJson.Booleano)?.valor ?: false,
            novedadesPlan = (j["novedades_plan"] as? ValorJson.Booleano)?.valor ?: false,
            devolucionSemanal = (j["devolucion_semanal"] as? ValorJson.Booleano)?.valor ?: false,
            metasPasos = (j["metas_pasos"] as? ValorJson.Booleano)?.valor ?: false,
            chatAdjuntos = (j["chat_adjuntos"] as? ValorJson.Booleano)?.valor ?: false,
            meDuele = (j["me_duele"] as? ValorJson.Booleano)?.valor ?: false,
            supleEstado = (j["suple_estado"] as? ValorJson.Booleano)?.valor ?: false,
            elegirHorario = (j["elegir_horario"] as? ValorJson.Booleano)?.valor ?: false,
            estudiosApp = (j["estudios_app"] as? ValorJson.Booleano)?.valor ?: false,
            fotosInicio = (j["fotos_inicio"] as? ValorJson.Booleano)?.valor ?: false,
            finPlan = (j["fin_plan"] as? ValorJson.Booleano)?.valor ?: false,
            comprasPais = (j["compras_pais"] as? ValorJson.Booleano)?.valor ?: false,
            casa = (j["casa"] as? ValorJson.Booleano)?.valor ?: false,
            winsApp = (j["wins_app"] as? ValorJson.Booleano)?.valor ?: false,
            listaPrevia = (j["lista_previa"] as? ValorJson.Booleano)?.valor ?: false,
            checkGuiado = (j["check_guiado"] as? ValorJson.Booleano)?.valor ?: false,
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
