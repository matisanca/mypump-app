package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson

/**
 * El permiso para la IA (D7, guía 5.1.2(i) de Apple, que en Android se respeta igual; ver
 * `supabase/migrations/nativa_002_consentimiento_ia.sql`). Cubre todo lo que lee los datos del cliente con IA: el chat
 * (Codex), la foto del plato o de la etiqueta (OpenAI) y la ronda del domingo (Claude). Con un "no", el servidor no le pasa
 * nada a ningún modelo: el chat lo contesta Mati, la foto no se analiza y la ronda usa los respaldos sin IA. Gemelo de
 * ConsentimientoIA.swift.
 *
 * Sin la `nativa_002` (PGRST202) no se pregunta nada y todo sigue como hoy.
 */
object ConsentimientoIA {
    /** La decisión, en el disco de la cuenta (para el arranque sin red). */
    const val ARCHIVO = "consentimiento-ia.json"

    /** La clave de la cola: gana la última decisión. */
    const val CLAVE = "consentimiento_ia"

    /** El kind de la cola (`mypump_guardar_consentimiento_ia`). */
    const val KIND = "consentimiento_ia"

    /** `p_plataforma` de la RPC (la tabla acepta 'ios' y 'android'). */
    const val PLATAFORMA = "android"

    /** `{"acepta": true}`, la misma forma que guarda iOS. */
    data class Guardado(val acepta: Boolean) {
        fun aValor(): ValorJson = ValorJson.objeto("acepta" to ValorJson.Booleano(acepta))

        companion object {
            fun desde(v: ValorJson?): Guardado? = (v?.get("acepta") as? ValorJson.Booleano)?.let { Guardado(it.valor) }
        }
    }
}
