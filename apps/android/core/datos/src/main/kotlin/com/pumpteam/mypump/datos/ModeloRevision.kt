package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.CheckinSemana
import com.pumpteam.mypump.modelos.DiaAdherencia
import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.HabitosDia
import com.pumpteam.mypump.modelos.Racha
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CheckinSemanal
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.PesoCorporal
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Los hábitos del día como los muestra Mi Día (el `MYDAY` de la web): lo del servidor con lo que el cliente tocó y todavía
 * no salió encima.
 */
data class HabitosHoy(
    /** "entrene" | "descanso" | "falte" | null. */
    val entrenamiento: String? = null,
    val comioSegunPlan: Boolean? = null,
    val durmioBien: Boolean? = null,
    val cardio: Boolean? = null,
    val vasosAgua: Int = 0,
) {
    /** `_valorHabito`: el valor como viaja en la cola (texto) llevado a su tipo. */
    fun aplicar(campo: String, valor: ValorJson?): HabitosHoy {
        val texto = Escrituras.stringJs(valor)
        return when (campo) {
            "vasos_agua" -> copy(vasosAgua = (texto.toDoubleOrNull() ?: 0.0).toInt())
            "entrenamiento" -> copy(entrenamiento = if (texto == "null" || texto.isEmpty()) null else texto)
            "comio_segun_plan" -> copy(comioSegunPlan = booleano(texto))
            "durmio_bien" -> copy(durmioBien = booleano(texto))
            "cardio" -> copy(cardio = booleano(texto))
            else -> this
        }
    }

    companion object {
        fun de(h: HabitosDia?) = HabitosHoy(h?.entrenamiento, h?.comioSegunPlan, h?.durmioBien, h?.cardio, h?.vasosAgua ?: 0)

        private fun booleano(t: String): Boolean? = if (t == "null") null else t == "true"
    }
}

/** Un check de la semana como lo ve el cliente: el guardado (o el optimista recién mandado). */
data class Checkin(val valores: Map<String, Int> = emptyMap(), val nota: String = "")

/**
 * Revisión (lo semanal: check, peso, fotos) y Mi Día (lo diario: entrené/descansé/falté, hábitos, agua, racha, adherencia
 * de 30 días). Todo lo que escribe el cliente sale por la cola con la clave de la web, y lo pendiente gana sobre lo que
 * trae el servidor (DIA-06).
 */
class ModeloRevision(
    private val cliente: ClienteRpc,
    private val token: String,
    private val outbox: Outbox?,
    private val alcance: CoroutineScope,
) {
    private val _habitos = MutableStateFlow(HabitosHoy())
    val habitos: StateFlow<HabitosHoy> = _habitos.asStateFlow()

    private val _racha = MutableStateFlow(0)
    val racha: StateFlow<Int> = _racha.asStateFlow()

    private val _miDiaCargado = MutableStateFlow(false)
    val miDiaCargado: StateFlow<Boolean> = _miDiaCargado.asStateFlow()

    /** Mis últimos 30 días: se trae al abrirla. */
    private val _adherencia = MutableStateFlow<List<DiaAdherencia>?>(null)
    val adherencia: StateFlow<List<DiaAdherencia>?> = _adherencia.asStateFlow()

    private val _checkin = MutableStateFlow<Checkin?>(null)
    val checkin: StateFlow<Checkin?> = _checkin.asStateFlow()

    /** Las filas de salud de los últimos 60 días (peso de la card y, más adelante, salud y recuperación). */
    private val _salud = MutableStateFlow<List<FilaSalud>>(emptyList())
    val salud: StateFlow<List<FilaSalud>> = _salud.asStateFlow()

    private val _fecha = MutableStateFlow(FechaLocal.hoy())
    val fecha: StateFlow<String> = _fecha.asStateFlow()

    private var esperaAgua: Job? = null
    private val t get() = texto(token)

    // ── Mi Día ──

    /** `loadMyday`: hábitos de hoy y racha. Sin red quedan los de antes (o vacíos). */
    suspend fun cargarMiDia() {
        val hoy = FechaLocal.hoy()
        _fecha.value = hoy
        val (rh, rr) = coroutineScope {
            val h = async { cliente.filas("mypump_get_habitos_dia", mapOf("p_token" to t, "p_fecha" to texto(hoy)), HabitosDia::desde) }
            val r = async { cliente.filas("mypump_get_streak", mapOf("p_token" to t), Racha::desde) }
            h.await() to r.await()
        }
        rh.valorONull()?.let { filas -> _habitos.value = HabitosHoy.de(filas.firstOrNull()) }
        rr.valorONull()?.let { filas -> _racha.value = filas.firstOrNull()?.streak ?: 0 }
        aplicarPendientes()
        _miDiaCargado.value = true
    }

    /** Entrené / descansé / falté y los hábitos de sí o no: tocar lo que ya está lo borra (null). */
    suspend fun tocar(campo: String, valor: String) {
        val h = _habitos.value
        val actual: String? = when (campo) {
            "entrenamiento" -> h.entrenamiento
            "comio_segun_plan" -> h.comioSegunPlan?.toString()
            "durmio_bien" -> h.durmioBien?.toString()
            "cardio" -> h.cardio?.toString()
            else -> null
        }
        setHabito(campo, if (actual == valor) null else valor)
    }

    /** `setHabito`: optimista y por la cola (gana el último por campo y fecha). */
    suspend fun setHabito(campo: String, valor: String?) {
        val v: ValorJson = valor?.let { texto(it) } ?: ValorJson.Nulo
        // La fecha es la de AHORA (la app pudo quedar abierta de un día para otro), como `hoyLocal()` en la web.
        val dia = FechaLocal.hoy()
        _habitos.update { it.aplicar(campo, v) }
        outbox?.encolar("habito", ValorJson.objeto("fecha" to texto(dia), "campo" to texto(campo), "valor" to v), "habito|$dia|$campo")
        if (campo in listOf("entrenamiento", "comio_segun_plan", "durmio_bien")) {
            outbox?.drenar()
            cliente.filas("mypump_get_streak", mapOf("p_token" to t), Racha::desde).valorONull()?.let { filas ->
                _racha.value = filas.firstOrNull()?.streak ?: _racha.value
            }
        }
    }

    /** `cambiarAgua`: 0 a 12 vasos, se ve al instante y se guarda 600 ms después del último toque. */
    fun cambiarAgua(delta: Int) {
        val nuevo = (_habitos.value.vasosAgua + delta).coerceIn(0, 12)
        if (nuevo == _habitos.value.vasosAgua) return
        _habitos.update { it.copy(vasosAgua = nuevo) }
        esperaAgua?.cancel()
        val dia = FechaLocal.hoy()
        esperaAgua = alcance.launch {
            delay(600)
            outbox?.encolar(
                "habito",
                ValorJson.objeto("fecha" to texto(dia), "campo" to texto("vasos_agua"), "valor" to texto(nuevo.toString())),
                "habito|$dia|vasos_agua",
            )
        }
    }

    /** "Mis últimos 30 días". */
    suspend fun cargarAdherencia() {
        cliente.filas("mypump_get_adherencia_30d", mapOf("p_token" to t), DiaAdherencia::desde).valorONull()?.let { _adherencia.value = it }
    }

    private suspend fun aplicarPendientes() {
        val prefijo = "habito|${FechaLocal.hoy()}|"
        val pendientes = outbox?.pendientesPorClave() ?: return
        for ((k, op) in pendientes) {
            if (k.startsWith(prefijo)) _habitos.update { it.aplicar(k.removePrefix(prefijo), op.payload["valor"]) }
        }
    }

    // ── Revisión ──

    /** `loadRevision` + `loadSalud`: el check de la semana y 60 días de salud (para el peso). */
    suspend fun cargarRevision() {
        val hoy = FechaLocal.hoy()
        _fecha.value = hoy
        val desde = DiaCalendario.numero(hoy)?.let { DiaCalendario.texto(it - 59) } ?: hoy
        val (rc, rs) = coroutineScope {
            val c = async { cliente.filas("mypump_get_checkin_semana", mapOf("p_token" to t, "p_fecha" to texto(hoy)), CheckinSemana::desde) }
            val s = async {
                cliente.filas("mypump_get_salud", mapOf("p_token" to t, "p_desde" to texto(desde), "p_hasta" to texto(hoy)), FilaSalud::desde)
            }
            c.await() to s.await()
        }
        rc.valorONull()?.let { filas ->
            _checkin.value = filas.firstOrNull()?.let { f ->
                val v = LinkedHashMap<String, Int>()
                f.energia?.let { v["energia"] = it }
                f.descanso?.let { v["descanso"] = it }
                f.hambre?.let { v["hambre"] = it }
                f.adherencia?.let { v["adherencia"] = it }
                Checkin(v, f.nota ?: "")
            }
        }
        rs.valorONull()?.let { filas ->
            _salud.value = filas
            // Un peso de hoy que todavía no salió gana sobre lo del servidor.
            outbox?.pendientesPorClave()?.get("peso_$hoy")?.payload?.get("valor")?.comoNumero?.let { ponerPesoDeHoy(it) }
        }
    }

    /** El check está enviado si tiene energía (como la web: `checkin.energia`). */
    val checkinEnviado: Boolean get() = (_checkin.value?.valores?.get("energia") ?: 0) > 0

    /**
     * "Enviar mi check": exige las cuatro escalas; optimista y por la cola (uno por semana: el servidor lo ancla al lunes
     * ISO). Devuelve el aviso de lo que falta, o null si salió.
     */
    suspend fun enviarCheckin(c: Checkin): String? {
        CheckinSemanal.faltan(c.valores)?.let { return it }
        val dia = FechaLocal.hoy()
        val nota = TextoJs.recortar(c.nota)
        _checkin.value = Checkin(c.valores, nota)
        val datos = LinkedHashMap<String, ValorJson>()
        datos["nota"] = texto(nota)
        for (m in CheckinSemanal.metricas) datos[m.clave] = numero(c.valores[m.clave] ?: 0)
        outbox?.encolar("checkin", ValorJson.objeto("fecha" to texto(dia), "datos" to ValorJson.Objeto(datos)), "checkin_$dia")
        return null
    }

    val serieDePeso: List<PesoCorporal.Punto> get() = PesoCorporal.serie(_salud.value)

    /** Guardar el peso de hoy (30-300 kg). Devuelve false si el valor no es válido. */
    suspend fun guardarPeso(texto: String): Boolean {
        val valor = PesoCorporal.leer(texto) ?: return false
        val dia = FechaLocal.hoy()
        ponerPesoDeHoy(valor)
        outbox?.encolar("peso", ValorJson.objeto("fecha" to texto(dia), "valor" to numero(valor)), "peso_$dia")
        return true
    }

    private fun ponerPesoDeHoy(valor: Double) {
        val hoy = FechaLocal.hoy()
        val fila = FilaSalud(hoy, "peso_kg", valor, "manual", null)
        _salud.update { lista -> lista.filterNot { it.tipo == "peso_kg" && it.fecha == hoy && it.fuente == "manual" } + fila }
    }
}
