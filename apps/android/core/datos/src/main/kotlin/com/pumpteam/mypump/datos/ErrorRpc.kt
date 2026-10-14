package com.pumpteam.mypump.datos

/**
 * Un error de una llamada al backend, clasificado como `clasificarError` de la web (supabase-client.js:41-48) y como
 * `ErrorRPC` de iOS. La clase decide qué hace la cola: la red y lo transitorio NO gastan intentos; lo permanente sí.
 * Un token revocado no llega acá: casi todas las RPC contestan 200 con `null`, `[]`, `0` o `false`.
 */
data class ErrorRpc(
    val clase: Clase,
    /** 0 si no hubo respuesta. */
    val status: Int,
    /** El `code` de PostgREST (P0001, 22P02, PGRST202…), si vino. */
    val codigo: String? = null,
    val mensaje: String,
) {
    enum class Clase {
        /** No hubo respuesta: sin señal, timeout, host, o un 200 que no es JSON (portal cautivo del wifi del gym). */
        RED,

        /** El servidor respondió que está ocupado: 5xx, 429, 408. */
        TRANSITORIO,

        /** El servidor dijo que no: cualquier otro 4xx (P0001, PGRST202, 401/403…). */
        PERMANENTE,
    }

    /** Lo que cuenta para abandonar una escritura de la cola. */
    val gastaIntento: Boolean get() = clase == Clase.PERMANENTE

    /** `mypump_get_historico_por_clave` no existe en la base: la única caída legítima al camino viejo del historial. */
    val funcionInexistente: Boolean get() = codigo == "PGRST202"

    companion object {
        /** La clase de una respuesta HTTP que no fue 2xx. 0 es que no hubo respuesta. */
        fun claseDe(status: Int): Clase = when {
            status == 0 -> Clase.RED
            status == 429 || status == 408 || status in 500..599 -> Clase.TRANSITORIO
            else -> Clase.PERMANENTE
        }
    }
}
