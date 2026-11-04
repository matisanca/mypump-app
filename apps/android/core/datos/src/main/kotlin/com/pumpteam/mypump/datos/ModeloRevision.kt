package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.CheckinSemana
import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CheckinSemanal
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Un check de la semana como lo ve el cliente: el guardado (o el optimista recién mandado). */
data class Checkin(val valores: Map<String, Int> = emptyMap(), val nota: String = "")

/**
 * Revisión (lo semanal: check, peso; las fotos son de [ModeloFotos]). Todo lo que escribe el cliente sale por la cola con
 * la clave de la web, y lo pendiente gana sobre lo que trae el servidor. Sin token es la demo ([demo]): se toca igual y
 * no sale nada. Mi Día (hábitos, agua, racha, adherencia) se sacó en la 2.1: la cola igual sabe vaciar operaciones
 * `habito` viejas (EjecutorLegado).
 */
class ModeloRevision(
    private val cliente: ClienteRpc,
    /** null es la demo: no toca la red (y sin cola no guarda nada). */
    private val token: String?,
    private val outbox: Outbox?,
    private val alcance: CoroutineScope,
) {
    private val _checkin = MutableStateFlow<Checkin?>(null)
    val checkin: StateFlow<Checkin?> = _checkin.asStateFlow()

    /** Las filas de salud de los últimos 60 días (peso de la card y, más adelante, salud y recuperación). */
    private val _salud = MutableStateFlow<List<FilaSalud>>(emptyList())
    val salud: StateFlow<List<FilaSalud>> = _salud.asStateFlow()

    private val _fecha = MutableStateFlow(FechaLocal.hoy())
    val fecha: StateFlow<String> = _fecha.asStateFlow()

    /** El lunes de la semana de [fecha]: el check es de esa semana (las vistas vacían su borrador cuando cambia). */
    val semana: String get() = FotosProgreso.lunes(_fecha.value)

    /** De qué semana es el check que hay en memoria: el de la semana anterior no sirve ni como base. */
    private var semanaDelCheck: String? = null

    /** El día de hoy (los tests lo fijan para simular la medianoche con la app abierta). */
    internal var diaDeHoy: () -> String = { FechaLocal.hoy() }

    private val t get() = texto(token ?: "")   // la demo no llega acá: no toca la red

    // ── Revisión ──

    /** `loadRevision` + `loadSalud`: el check de la semana y 60 días de salud (para el peso). */
    suspend fun cargarRevision() {
        if (token == null) return   // la demo, como la web: sin check, peso ni fotos
        val hoy = diaDeHoy()
        _fecha.value = hoy
        // Semana nueva: el check de la anterior no es el de esta, haya red o no (la web lo vacía).
        if (semanaDelCheck != semana) _checkin.value = null
        semanaDelCheck = semana
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
        // Un check de esta semana que todavía no salió también (se mandó sin señal): si no, se vería sin enviar.
        aplicarCheckPendiente()
    }

    private suspend fun aplicarCheckPendiente() {
        val semana = semana
        val pendientes = (outbox?.pendientesPorClave() ?: emptyMap()).filter { (k, op) ->
            k.startsWith("checkin_") && op.payload["fecha"]?.comoTexto?.let(FotosProgreso::lunes) == semana
        }
        val op = pendientes.values.maxByOrNull { it.ts } ?: return
        val d = op.payload["datos"] ?: return
        val v = LinkedHashMap<String, Int>()
        for (m in CheckinSemanal.metricas) d[m.clave]?.comoNumero?.let { v[m.clave] = enteroTruncado(it) }
        _checkin.value = Checkin(v, d["nota"]?.comoTexto ?: "")
    }

    /** El check está enviado si tiene energía (como la web: `checkin.energia`). */
    val checkinEnviado: Boolean get() = (_checkin.value?.valores?.get("energia") ?: 0) > 0

    /**
     * "Enviar mi check": exige las cuatro escalas; optimista y por la cola (uno por semana: el servidor lo ancla al lunes
     * ISO). Devuelve el aviso de lo que falta, o null si salió.
     */
    suspend fun enviarCheckin(c: Checkin): String? {
        CheckinSemanal.faltan(c.valores)?.let { return it }
        val dia = diaDeHoy()
        val nota = TextoJs.recortar(c.nota)
        _checkin.value = Checkin(c.valores, nota)
        semanaDelCheck = FotosProgreso.lunes(dia)
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
        val dia = diaDeHoy()
        ponerPesoDeHoy(valor)
        outbox?.encolar("peso", ValorJson.objeto("fecha" to texto(dia), "valor" to numero(valor)), "peso_$dia")
        return true
    }

    private fun ponerPesoDeHoy(valor: Double) {
        val hoy = diaDeHoy()
        val fila = FilaSalud(hoy, "peso_kg", valor, "manual", null)
        _salud.update { lista -> lista.filterNot { it.tipo == "peso_kg" && it.fecha == hoy && it.fuente == "manual" } + fila }
    }

    companion object {
        /** "Ver demo" (ACC-07): sin cuenta, sin red ni cola; el check y el peso se tocan igual y no sale nada. */
        fun demo(cliente: ClienteRpc, alcance: CoroutineScope, hoy: String = FechaLocal.hoy()): ModeloRevision =
            ModeloRevision(cliente, token = null, outbox = null, alcance = alcance).also { m -> m._fecha.value = hoy }
    }
}
