package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * La pestaña Suplementación de una cuenta (2.1.0): `mypump_suplementacion(p_token)`, de solo lectura.
 *
 * - **Lectura.** [refrescar] al cargar la app y al volver a primer plano, como el resumen de «Tu guía».
 * - **Caché.** La última fila (`suplementacion.json`) en la carpeta de la cuenta, como la copia offline de rutina y dieta:
 *   sin red la pestaña se ve igual.
 * - **Sin suplementación.** Cero filas (token inválido, sin suplementación o todo filtrado) o la función que todavía no
 *   existe (404, PGRST202) borran la caché: la pestaña desaparece y Salud vuelve a la barra.
 * - **Sin red o una forma que no se entiende.** Queda lo que había.
 *
 * Como [ModeloGuia], se usa desde el hilo principal.
 */
class ModeloSuplementacion(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    private val alcance: CoroutineScope,
    /** «Ver demo»: la muestra empaquetada, sin cuenta. No llama al servidor. Ver [demo]. */
    private val esDemo: Boolean = false,
) {
    private val _plan = MutableStateFlow<PlanSuplementacion?>(null)

    /** Lo que muestra la pestaña. null: no hay pestaña. */
    val plan: StateFlow<PlanSuplementacion?> = _plan.asStateFlow()

    /** Lo que se ve es la caché: el último pedido no llegó. */
    private val _desdeCache = MutableStateFlow(false)
    val desdeCache: StateFlow<Boolean> = _desdeCache.asStateFlow()

    /** Ya hubo una respuesta del servidor en esta sesión: lo leído del disco no la pisa. */
    private var respondio = false

    /** El disco, fuera del hilo principal y de a una operación por vez, en el orden en que se pidieron. */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private val serieDisco = Dispatchers.IO.limitedParallelism(1)

    private val lecturaInicial: Job = alcance.launch {
        if (esDemo) return@launch
        val p = withContext(serieDisco) { PlanSuplementacion.desde(disco?.leer(ARCHIVO)) }
        if (!respondio && _plan.value == null && p != null) {
            _plan.value = p
            _desdeCache.value = true
        }
    }

    private fun alDisco(f: Disco.() -> Unit) {
        val d = disco ?: return
        alcance.launch(serieDisco) { d.f() }
    }

    /** Para las pruebas: la caché ya se leyó y lo pedido al disco ya se escribió. */
    suspend fun alDia() {
        lecturaInicial.join()
        alcance.launch(serieDisco) {}.join()
    }

    private var refrescando = false

    suspend fun refrescar() {
        lecturaInicial.join()
        if (esDemo || refrescando) return
        refrescando = true
        try {
            when (val r = cliente.filas(RPC, mapOf("p_token" to ValorJson.Texto(token)), PlanSuplementacion::desde)) {
                is Resultado.Falla -> {
                    // La función no existe (todavía no se aplicó la migración): para la app no hay suplementación.
                    if (r.error.status == 404 || r.error.codigo == "PGRST202") olvidar() else _desdeCache.value = _plan.value != null
                }
                is Resultado.Ok -> {
                    if (r.valor.isEmpty()) {
                        olvidar()
                        return
                    }
                    val p = r.valor.firstNotNullOfOrNull { it }
                    if (p == null) {
                        // Una forma que no se entiende no es «no hay»: queda lo que había.
                        _desdeCache.value = _plan.value != null
                        return
                    }
                    respondio = true
                    _plan.value = p
                    _desdeCache.value = false
                    alDisco { guardar(ARCHIVO, p.aValor()) }
                }
            }
        } finally {
            refrescando = false
        }
    }

    private fun olvidar() {
        respondio = true
        _plan.value = null
        _desdeCache.value = false
        alDisco { borrar(ARCHIVO) }
    }

    companion object {
        const val RPC = "mypump_suplementacion"
        internal const val ARCHIVO = "suplementacion.json"

        /** La de «Ver demo» (`apps/shared/demo/suplementacion.json`, con la forma de la fila). Sin token ni disco. */
        fun demo(cliente: ClienteRpc, plan: PlanSuplementacion, alcance: CoroutineScope): ModeloSuplementacion =
            ModeloSuplementacion(cliente, token = "", disco = null, alcance = alcance, esDemo = true).also { it._plan.value = plan }
    }
}
