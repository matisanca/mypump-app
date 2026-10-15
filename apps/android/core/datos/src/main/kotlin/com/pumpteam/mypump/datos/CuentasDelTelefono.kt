package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Las carpetas de cuenta del teléfono ([Disco], una por token). Un link que Mati regeneró (`mypump_regenerar_token`) es
 * OTRO token de la MISMA persona: la carpeta nueva arrancaba con la cola vacía y lo que quedó en la vieja (series cargadas
 * sin señal, estacionadas con el token caído hasta "que entre con un link nuevo") no salía nunca (revisión del 15-oct,
 * hallazgo 4). Al entrar, lo de las otras carpetas del MISMO `cliente_id` pasa a la cola de la cuenta. Gemelo de
 * CuentasDelTelefono.swift.
 */
internal object CuentasDelTelefono {
    /**
     * El `cliente_id` de la carpeta, anotado en cada carga con red. Las que no lo tienen (de antes) se reconocen por el
     * `info` de su copia offline.
     */
    const val ARCHIVO_CUENTA = "cuenta.json"

    /**
     * Los ids de lo que ya se pasó a otra cuenta: no se vuelve a adoptar ni a mandar aunque la cola vieja lo siga teniendo
     * (una cola de esa cuenta que todavía viva en este proceso puede volver a escribir su archivo).
     */
    const val ARCHIVO_ADOPTADAS = "adoptadas.json"

    fun anotar(clienteId: String, disco: Disco) {
        if (anotado(disco) == clienteId) return
        disco.guardar(ARCHIVO_CUENTA, ValorJson.objeto("cliente_id" to texto(clienteId)))
    }

    fun clienteId(disco: Disco): String? =
        anotado(disco) ?: ModeloApp.CopiaOffline.desde(disco.leer(ModeloApp.ARCHIVO_COPIA))?.info?.get("cliente_id")?.comoTexto

    private fun anotado(disco: Disco): String? =
        ((disco.leer(ARCHIVO_CUENTA) as? JsonObject)?.get("cliente_id") as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** Las otras carpetas de cuenta del teléfono, en orden. */
    private fun otras(disco: Disco): List<Disco> {
        val base = disco.carpeta.parentFile ?: return emptyList()
        val propia = disco.carpeta.name
        return (base.list() ?: emptyArray()).filter { it.startsWith("cuenta-") && it != propia }.sorted().map { Disco(File(base, it)) }
    }

    /**
     * Pasa a [cola] (la de [disco]) lo pendiente y los fallidos de las otras carpetas de la misma persona, en el orden en que
     * estaban. Nunca de otro `cliente_id`, ni de una carpeta que no dice de quién es. Devuelve cuántas pendientes entraron.
     */
    suspend fun adoptar(clienteId: String, disco: Disco, cola: Outbox): Int {
        if (clienteId.isEmpty()) return 0
        var total = 0
        for (otra in otras(disco)) {
            val (viejas, viejosFallidos) = Outbox.leerArchivo(otra.archivo("outbox.json")) ?: continue
            val yaAdoptadas = (otra.leer(ARCHIVO_ADOPTADAS) as? JsonArray)
                ?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }?.toSet() ?: emptySet()
            val ops = viejas.filter { it.id !in yaAdoptadas }
            val fallidos = viejosFallidos.filter { it.op.id !in yaAdoptadas }
            if ((ops.isEmpty() && fallidos.isEmpty()) || clienteId(otra) != clienteId) continue
            total += cola.adoptar(ops, fallidos).size
            // Primero quedó en la cola de esta cuenta (en disco); recién después se anota en la vieja. Si el proceso muere en
            // el medio, la próxima vez no se duplica: lo que ya está en la cola tiene el mismo id.
            val anotadas = yaAdoptadas + ops.map { it.id } + fallidos.map { it.op.id }
            otra.guardar(ARCHIVO_ADOPTADAS, ValorJson.Lista(anotadas.sorted().map { texto(it) }))
        }
        return total
    }
}
