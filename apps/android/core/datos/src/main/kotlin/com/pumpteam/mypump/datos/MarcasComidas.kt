package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.MarcaComida

/**
 * «✓ Comí» / «✗ Salté» por comida y lo consumido del día (DIE-05..07; volvió en D25, 27-oct: «no puedo hacer el
 * seguimiento a las comidas», «no aparecen las calorías que vas consumiendo»). Lo mismo que la web: una marca por
 * (cliente, fecha, comida) en `mypump_comidas_marcadas`, que se escribe por la cola (kind `comida`, la última gana) y se
 * lee del servidor al cargar, al tirar para actualizar y al volver a la app, así se ven las de la web o del otro teléfono.
 * En el teléfono quedan las de hoy (`marcas_comidas.json`) para verlas sin red. La cuenta es de `ConsumoDelDia` (reglas);
 * el estado vive en el [ModeloApp]. Gemelo de MarcasComidas.swift (mismo archivo y mismo payload).
 */
object MarcasComidas {
    const val KIND = "comida"
    const val ARCHIVO = "marcas_comidas.json"

    /** La de la web: `comida|<fecha>|<comida>`. Con la misma, una marca nativa y una de la web pendientes se pisan bien. */
    fun clave(fecha: String, comidaId: String): String = "comida|$fecha|$comidaId"

    /** Lo que va a disco: las marcas de UN día (el de hoy). Al cambiar de día no valen. */
    fun guardadas(fecha: String, marcas: Map<String, MarcaComida>): ValorJson =
        ValorJson.objeto("fecha" to ValorJson.Texto(fecha), "marcas" to ValorJson.Objeto(marcas.mapValues { it.value.aValor() }))

    /** Las del teléfono: lo que no se entiende queda afuera. */
    fun desde(v: ValorJson?): Map<String, MarcaComida> =
        (v as? ValorJson.Objeto)?.campos.orEmpty().mapNotNull { (k, x) -> MarcaComida.desde(x)?.let { k to it } }.toMap()

    /** El payload de la web (`toggleComidaEstado` / `toggleFoodComido`): sin estado, Escrituras desmarca. */
    fun payload(fecha: String, comidaId: String, marca: MarcaComida?, opcionAlDesmarcar: String?): ValorJson = ValorJson.objeto(
        "fecha" to ValorJson.Texto(fecha), "comidaId" to ValorJson.Texto(comidaId),
        "opcion" to ((marca?.opcion ?: opcionAlDesmarcar)?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
        "estado" to (marca?.let { ValorJson.Texto(it.estado.valor) } ?: ValorJson.Nulo),
        "excl" to ValorJson.Lista(marca?.excluidos.orEmpty().map { ValorJson.Numero(it.toDouble()) }),
    )

    /** La marca que deja una op `comida` de la cola (null = desmarcar). */
    fun desdePayload(p: ValorJson): MarcaComida? {
        val e = MarcaComida.Estado.desde(p["estado"]?.comoTexto) ?: return null
        val excl = (p["excl"] as? ValorJson.Lista)?.elementos.orEmpty()
            .mapNotNull { it.comoNumero?.takeIf { d -> d.isFinite() && d == Math.floor(d) }?.toInt() }
        return MarcaComida(p["opcion"]?.comoTexto, e, excl)
    }
}
