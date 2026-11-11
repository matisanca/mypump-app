package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.EstadoFeedback
import com.pumpteam.mypump.reglas.Molestia
import com.pumpteam.mypump.reglas.ReglasMolestia
import com.pumpteam.mypump.reglas.ReglasSupleEstado
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * Feedback del alumno (2.3.0): «Me duele» por ejercicio y «Lo compré / lo estoy tomando». Una sola lectura
 * (`mypump_feedback_get`) y dos escrituras directas, sin cola: son avisos que el alumno manda mirando la pantalla y, si no
 * salen, se lo decimos ahí mismo. Con las palancas `me_duele` y `suple_estado` apagadas [ModeloApp] no llama a nada de esto.
 * Gemelo de ModeloFeedback.swift.
 */
class ModeloFeedback(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
) {
    enum class Salida { OK, SIN_SENAL, TOPE, ERROR }

    private val _estado = MutableStateFlow<EstadoFeedback?>(null)
    /** null: apagado, sin el servidor nuevo, o sin red y sin nada guardado. No se muestra nada. */
    val estado: StateFlow<EstadoFeedback?> = _estado.asStateFlow()
    private val _marcando = MutableStateFlow<Set<String>>(emptySet())
    /** Las marcas que todavía están viajando: la fila se ve marcada enseguida y vuelve atrás si falla. */
    val marcando: StateFlow<Set<String>> = _marcando.asStateFlow()

    // ── Lo que lee la pantalla ──

    val dueleHabilitado: Boolean get() = _estado.value?.dueleHabilitado ?: false
    val supleHabilitado: Boolean get() = _estado.value?.supleHabilitado ?: false
    fun molestia(ejercicio: String): Molestia? = _estado.value?.molestia(ejercicio)
    val marcas: Map<String, ReglasSupleEstado.Estado> get() = _estado.value?.marcas ?: emptyMap()

    // ── Servidor ──

    /** Cuenta las escrituras: una lectura que salió antes de una escritura no pisa lo que esa escritura dejó. */
    private val escrituras = java.util.concurrent.atomic.AtomicInteger(0)
    /** Se cerró sesión: no se vuelve a pedir ni a guardar nada de esta cuenta. */
    @Volatile private var cerrada = false

    suspend fun refrescar() {
        if (cerrada) return
        val antes = escrituras.get()
        val r = cliente.llamar("mypump_feedback_get", mapOf("p_token" to ValorJson.Texto(token)))
        if (cerrada || escrituras.get() != antes || _marcando.value.isNotEmpty()) return   // la próxima lectura trae lo nuevo
        when (r) {
            is Resultado.Ok -> {
                if (r.valor == ValorJson.Nulo) {
                    _estado.value = null
                    return
                }
                val e = EstadoFeedback.desde(r.valor)
                if (e == null) {
                    apagar()
                    disco?.borrar(ARCHIVO)
                    return
                }
                _estado.value = e
                disco?.guardar(ARCHIVO, r.valor)
            }
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                    disco?.borrar(ARCHIVO)
                } else if (_estado.value == null) {
                    // Sin red, lo último que se supo: se ve qué se avisó y qué se marcó. Avisar algo nuevo va a decir que no hay señal.
                    disco?.leer(ARCHIVO)?.let { EstadoFeedback.desde(ValorJson.desde(it)) }?.let { _estado.value = it }
                }
            }
        }
    }

    fun apagar() {
        _estado.value = null
        _marcando.value = emptySet()
    }

    /**
     * Cerrar sesión: las molestias avisadas y las marcas de suplementos (lo que se ve) se borran del teléfono. No hay nada
     * pendiente que conservar: «Me duele» y las marcas salen directo, sin cola (si no salen, se avisa en la pantalla).
     */
    fun olvidarAlSalir() {
        cerrada = true
        apagar()
        disco?.borrar(ARCHIVO)
    }

    /** Avisa una molestia. [id] lo pone quien llama y lo repite en cada reintento: el servidor no duplica. */
    suspend fun avisar(id: String, ejercicioId: String, ejercicioNombre: String, diaId: String?, b: ReglasMolestia.Borrador, version: String?): Salida {
        if (!b.completa) return Salida.ERROR
        val nota = ReglasMolestia.nota(b.nota.trim())
        fun texto(s: String?) = s?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo
        val r = cliente.llamar(
            "mypump_molestia_registrar",
            mapOf(
                "p_token" to ValorJson.Texto(token), "p_id" to ValorJson.Texto(id),
                "p_ejercicio_id" to ValorJson.Texto(recortar(ejercicioId, 160)), "p_ejercicio_nombre" to ValorJson.Texto(recortar(ejercicioNombre, 160)),
                "p_dia_id" to texto(diaId?.let { recortar(it, 80) }),
                "p_zona" to texto(b.zona), "p_lado" to texto(b.lado), "p_desde" to texto(b.desde), "p_cuando" to texto(b.cuando), "p_tipo" to texto(b.tipo),
                "p_intensidad" to ValorJson.Numero((b.intensidad ?: 0).toDouble()), "p_nota" to texto(nota.ifEmpty { null }),
                "p_plataforma" to ValorJson.Texto("android"), "p_version" to texto(version?.let { recortar(it, 40) }),
            ),
        )
        return when (r) {
            is Resultado.Ok -> {
                if (r.valor["ok"] == ValorJson.Booleano(true)) {
                    escrituras.incrementAndGet()
                    Molestia.desde(r.valor["molestia"])?.let { m ->
                        _estado.update { e -> (e ?: EstadoFeedback()).let { it.copy(molestias = listOf(m) + it.molestias.filter { x -> x.id != m.id }) } }
                    }
                    Salida.OK
                } else if (r.valor["error"]?.comoTexto == "tope") Salida.TOPE else Salida.ERROR
            }
            is Resultado.Falla ->
                if (r.error.clase == ErrorRpc.Clase.RED || r.error.clase == ErrorRpc.Clase.TRANSITORIO) Salida.SIN_SENAL else Salida.ERROR
        }
    }

    /** Marca un suplemento. Se ve enseguida; si el servidor no lo toma, vuelve a como estaba y devuelve false. */
    suspend fun marcar(nombre: String, nuevo: ReglasSupleEstado.Estado): Boolean {
        val k = ReglasSupleEstado.clave(nombre)
        if (k.isEmpty()) return false
        val antes: ReglasSupleEstado.Estado?
        synchronized(this) {
            val e = _estado.value ?: return false
            if (k in _marcando.value) return false
            antes = e.marcas[k]
            if (antes == nuevo) return true
            _estado.value = e.copy(marcas = e.marcas + (k to nuevo))
            _marcando.update { it + k }
            escrituras.incrementAndGet()
        }
        val r = try {
            cliente.llamar(
                "mypump_suple_marcar",
                mapOf("p_token" to ValorJson.Texto(token), "p_item" to ValorJson.Texto(nombre), "p_estado" to ValorJson.Texto(nuevo.clave), "p_nota" to ValorJson.Nulo),
            )
        } finally {
            _marcando.update { it - k }
        }
        if (r is Resultado.Ok && r.valor["ok"] == ValorJson.Booleano(true)) return true
        // Puede haberse apagado mientras viajaba: ahí no hay nada que devolver a su lugar.
        _estado.update { v -> v?.copy(marcas = if (antes == null) v.marcas - k else v.marcas + (k to antes)) }
        return false
    }

    companion object {
        const val ARCHIVO = "feedback-estado.json"

        /** Los primeros [n] caracteres, sin partir uno de dos unidades. */
        internal fun recortar(s: String, n: Int): String = if (s.codePointCount(0, s.length) <= n) s else s.substring(0, s.offsetByCodePoints(0, n))
    }
}
