package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

// MARK: Recibo en el servidor

/**
 * El recibo va a `mypump_registrar_migracion_nativa` (`nativa_001`) y queda SIEMPRE también en el disco: lo que el
 * servidor no confirma (la RPC todavía no existe, sin red, token caído) se reintenta en el próximo arranque con
 * [reenviar]. Lo confirmado pasa a `recibos/enviados/` y lo que el servidor rechazó (tope del cliente, recibo mal formado)
 * a `recibos/rechazados/`, para no insistir. Gemelo de ServidorMigracion.swift.
 */
class ReciboEnServidor(val cliente: ClienteRpc, val carpeta: File) : ReciboMigracion {
    override suspend fun enviar(recibo: ReciboLegado, token: String): EntregaRecibo {
        val local = ReciboEnDisco(carpeta).enviar(recibo, token)
        return when (mandar(recibo, token, cliente)) {
            Respuesta.CONFIRMADO -> {
                archivar(carpeta, recibo.corrida, "enviados")
                EntregaRecibo.CONFIRMADO
            }
            Respuesta.RECHAZADO -> {
                archivar(carpeta, recibo.corrida, "rechazados")
                local
            }
            Respuesta.REINTENTAR -> local
        }
    }

    internal enum class Respuesta { CONFIRMADO, RECHAZADO, REINTENTAR }

    companion object {
        internal suspend fun mandar(recibo: ReciboLegado, token: String, cliente: ClienteRpc): Respuesta {
            val r = cliente.llamar(
                "mypump_registrar_migracion_nativa",
                mapOf("p_token" to texto(token), "p_migracion" to texto(recibo.migracion), "p_corrida" to numero(recibo.corrida), "p_recibo" to recibo.aValor()),
            )
            return when (r) {
                is Resultado.Ok -> when (r.valor) {
                    ValorJson.Booleano(true) -> Respuesta.CONFIRMADO
                    ValorJson.Booleano(false) -> Respuesta.RECHAZADO   // tope del cliente, o el uuid es de otra cuenta
                    else -> Respuesta.REINTENTAR                        // null: token caído
                }
                is Resultado.Falla -> when {
                    r.error.funcionInexistente -> Respuesta.REINTENTAR                  // la nativa_001 todavía no está aplicada
                    r.error.clase == ErrorRpc.Clase.PERMANENTE -> Respuesta.RECHAZADO   // mal formado (22023): no se insiste
                    else -> Respuesta.REINTENTAR                                         // red o servicio caído
                }
            }
        }

        internal fun archivar(carpeta: File, corrida: Int, subcarpeta: String) {
            val nombre = "recibo-$corrida.json"
            val destino = File(File(carpeta, subcarpeta), nombre)
            destino.parentFile.mkdirs()
            try {
                Files.move(File(carpeta, nombre).toPath(), destino.toPath(), StandardCopyOption.REPLACE_EXISTING)
            } catch (_: Exception) {
            }
        }

        /**
         * Los recibos que quedaron solo en el disco, de nuevo al servidor (los de otra cuenta se dejan). Corta en el primero
         * que no se pudo preguntar: sin red o sin la RPC, los demás tampoco van a entrar. Devuelve cuántos confirmó.
         */
        suspend fun reenviar(carpeta: File, token: String, clienteId: String, cliente: ClienteRpc): Int {
            val nombres = carpeta.list() ?: return 0
            var confirmados = 0
            for (nombre in nombres.sorted()) {
                if (!nombre.startsWith("recibo-") || !nombre.endsWith(".json")) continue
                val recibo = ReciboLegado.desde(leerJson(File(carpeta, nombre))?.let(ValorJson::desde)) ?: continue
                if (recibo.cliente != clienteId) continue
                when (mandar(recibo, token, cliente)) {
                    Respuesta.CONFIRMADO -> {
                        archivar(carpeta, recibo.corrida, "enviados")
                        confirmados++
                    }
                    Respuesta.RECHAZADO -> archivar(carpeta, recibo.corrida, "rechazados")
                    Respuesta.REINTENTAR -> return confirmados
                }
            }
            return confirmados
        }

        /** ¿Queda algún recibo sin confirmar en el disco? (Para no esperar una carga con red si no hay nada que mandar.) */
        fun hayPendientes(carpeta: File): Boolean = carpeta.list()?.any { it.startsWith("recibo-") && it.endsWith(".json") } ?: false
    }
}

// MARK: Conteos del servidor

/**
 * `mypump_conteos_cliente`: filas por tabla del cliente, antes y después de mandar lo importado. null si la RPC todavía no
 * existe, si no hubo red o si el token cayó (el recibo va igual, sin conteos del servidor).
 */
class ConteosRpc(val cliente: ClienteRpc) : ConteosServidor {
    override suspend fun contar(token: String): Map<String, Int>? {
        val r = cliente.llamar("mypump_conteos_cliente", mapOf("p_token" to texto(token)))
        val o = (r as? Resultado.Ok<ValorJson>)?.valor as? ValorJson.Objeto ?: return null
        return o.campos.mapNotNull { (k, v) -> v.comoNumero?.let { k to enteroTruncado(it) } }.toMap()
    }
}
