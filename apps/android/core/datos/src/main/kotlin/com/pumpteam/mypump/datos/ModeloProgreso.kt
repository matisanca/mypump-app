package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.ProgresoEjercicio
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Una tarjeta de Progreso: un ejercicio (agrupado por clave entre los días donde aparece) con su resumen y las filas. */
data class TarjetaProgreso(
    val id: String,
    val nombre: String,
    val clave: String,
    /** "Tirón · Piernas": los días donde aparece, en el orden de la rutina. */
    val dias: String,
    val resumen: ProgresoEjercicio.Resumen,
    /** Las filas tal cual vinieron (de la más nueva a la más vieja): el detalle muestra 8. */
    val filas: List<RegistroHistorico>,
)

/**
 * Progreso (`loadProgressAndRender`): UN pedido con todas las claves del plan (48 filas por clave); si la RPC por clave
 * no existe (PGRST202) se cae al camino viejo por lugar; si se cortó la red se avisa y se reintenta al volver.
 */
class ModeloProgreso(private val cliente: ClienteRpc, private val token: String) {
    enum class Estado { CARGANDO, LISTO, SIN_RED }

    private val _estado = MutableStateFlow(Estado.CARGANDO)
    val estado: StateFlow<Estado> = _estado.asStateFlow()

    private val _tarjetas = MutableStateFlow<List<TarjetaProgreso>>(emptyList())
    val tarjetas: StateFlow<List<TarjetaProgreso>> = _tarjetas.asStateFlow()

    private val _sesiones = MutableStateFlow(0)
    val sesiones: StateFlow<Int> = _sesiones.asStateFlow()

    /** Lo traído por clave, para que Entreno use el mismo historial (última vez y récord). */
    private val _historialPorClave = MutableStateFlow<Map<String, List<RegistroHistorico>>>(emptyMap())
    val historialPorClave: StateFlow<Map<String, List<RegistroHistorico>>> = _historialPorClave.asStateFlow()

    private class Entrada(val id: String, val ids: MutableList<String>, val clave: String, val nombre: String, val dias: MutableList<String>)

    /** [nombreEfectivo] da el nombre que se está haciendo (el del sustituto si el ejercicio está sustituido). */
    suspend fun cargar(rutina: RutinaActiva?, nombreEfectivo: (Ejercicio) -> String = { it.nombre }) {
        _estado.value = Estado.CARGANDO
        val dias = rutina?.estructura?.dias
        if (dias == null) {
            _tarjetas.value = emptyList()
            _sesiones.value = 0
            _estado.value = Estado.LISTO
            return
        }
        // Una entrada por clave del ejercicio efectivo, con los días donde aparece.
        val porClave = LinkedHashMap<String, Entrada>()
        dias.forEachIndexed { i, d ->
            val diaNombre = d.nombre?.takeIf { it.isNotEmpty() } ?: "Día ${d.n ?: (i + 1)}"
            for (b in d.bloques) for (ex in b.ejercicios) {
                if (ex.tipo == "calentamiento") continue
                val nombre = nombreEfectivo(ex)
                val c = ClaveEjercicio.de(nombre)
                val clave = c.ifEmpty { ex.id }
                val e = porClave[clave]
                if (e != null) {
                    if (diaNombre !in e.dias) e.dias += diaNombre
                    e.ids += ex.id
                } else {
                    porClave[clave] = Entrada(ex.id, mutableListOf(ex.id), clave, nombre, mutableListOf(diaNombre))
                }
            }
        }
        val entradas = porClave.values.toList()
        val filasPor = LinkedHashMap<String, MutableList<RegistroHistorico>>()
        val r = cliente.filas(
            "mypump_get_historico_por_clave",
            mapOf("p_token" to texto(token), "p_claves" to ValorJson.Lista(entradas.map { texto(it.clave) }), "p_limit_por_ej" to numero(48)),
            RegistroHistorico::desde,
        )
        when {
            r is Resultado.Ok -> for (f in r.valor) f.clave?.let { filasPor.getOrPut(it) { mutableListOf() } += f }
            r.errorONull()?.funcionInexistente == true -> {
                // La 072 sin aplicar: el camino viejo por id de lugar (24 filas).
                val viejo = cliente.filas(
                    "mypump_get_historico_ejercicios",
                    mapOf("p_token" to texto(token), "p_ejercicio_ids" to ValorJson.Lista(entradas.map { texto(it.id) }), "p_limit_por_ej" to numero(24)),
                    RegistroHistorico::desde,
                )
                val claveDeId = LinkedHashMap<String, String>()
                for (e in entradas) claveDeId.putIfAbsent(e.id, e.clave)
                viejo.valorONull()?.forEach { f ->
                    val c = f.ejercicioId?.let { claveDeId[it] } ?: return@forEach
                    filasPor.getOrPut(c) { mutableListOf() } += f
                }
            }
            else -> {
                // Sin red: NO se cae al camino por lugar (mezclaría original y sustituto) y se reintenta al volver.
                _estado.value = Estado.SIN_RED
                return
            }
        }
        _historialPorClave.value = filasPor
        _tarjetas.value = entradas.mapNotNull { e ->
            val filas = filasPor[e.clave] ?: return@mapNotNull null
            val resumen = ProgresoEjercicio.resumen(filas) ?: return@mapNotNull null
            TarjetaProgreso(e.id, e.nombre, e.clave, e.dias.joinToString(" · "), resumen, filas)
        }
        _sesiones.value = ProgresoEjercicio.sesiones(filasPor.values.flatten()).size
        _estado.value = Estado.LISTO
    }
}
