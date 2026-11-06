package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.AgendaEntrega
import com.pumpteam.mypump.modelos.FranjaEntrega
import com.pumpteam.mypump.modelos.ReservaEntrega
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ReglasAgenda
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * La agenda de la entrega al final de «Tu guía» (2.2.0, `entregas_021_agenda`, por token). Lo del teléfono:
 *
 * - **Disponible.** [agenda] null = no hay agenda: la función no existe (PGRST202 o 404, la base todavía sin la 021), `ok:
 *   false` (`token`, `sin_guia`) o una forma que no se entiende sin nada guardado. Así, sin el servidor nuevo, la guía se ve
 *   exactamente como en la 2.1.0: sin etiqueta, sin contador y sin agenda.
 * - **Caché.** La última respuesta en `guia-agenda.json` (carpeta de la cuenta). Sin red queda lo guardado con «Sin
 *   conexión» ([desdeCache]): con la reserva confirmada, el link sigue a mano.
 * - **Reservar.** Por la cola, en su carril ([KIND], ver [Outbox]): una op con su `p_id` (uuid) fijo, armado una sola vez
 *   al encolar, así cada reintento manda el mismo y el servidor devuelve la misma reserva. Sin red no se gasta intento.
 *   Mientras sale, [reservando] (la pantalla muestra «Estamos reservando tu horario…»); un segundo toque no encola otra.
 * - **Consultas.** Al abrir la guía y al volver a primer plano con ella abierta ([seguir], que la pantalla corre a la
 *   vista), al marcar visto el último obligatorio ([ModeloGuia]) y al volver a primer plano con una reserva pendiente
 *   ([alVolverAPrimerPlano]). Con la reserva `pendiente`, cada 5 s durante 60 s; después, solo al volver.
 *
 * Se usa desde el hilo principal, como [ModeloGuia]; lo que avisa la cola llega desde su hilo y se pasa a [alcance].
 */
class ModeloAgenda(
    private val cliente: ClienteRpc,
    private val token: String,
    private val outbox: Outbox?,
    private val disco: Disco?,
    private val alcance: CoroutineScope,
    private val reloj: () -> Long = System::currentTimeMillis,
    private val esperar: suspend (Long) -> Unit = { delay(it) },
    /**
     * «Ver demo»: la agenda de muestra empaquetada ([demo]). No llama al servidor; `habilitada` sale de lo visto en el
     * teléfono ([faltanDemo]) y reservar confirma enseguida, sin videollamada.
     */
    private val plantillaDemo: AgendaEntrega? = null,
    private val faltanDemo: () -> Int = { 0 },
) {
    val esDemo: Boolean get() = plantillaDemo != null

    private val _agenda = MutableStateFlow<AgendaEntrega?>(null)

    /** null: no hay agenda (servidor viejo o sin guía): no se muestra nada nuevo. */
    val agenda: StateFlow<AgendaEntrega?> = _agenda.asStateFlow()

    private val _desdeCache = MutableStateFlow(false)

    /** Lo que se ve es lo guardado: la última consulta no llegó. */
    val desdeCache: StateFlow<Boolean> = _desdeCache.asStateFlow()

    private val _reservando = MutableStateFlow<FranjaEntrega?>(null)

    /** La reserva que está en la cola sin respuesta todavía (la franja elegida). */
    val reservando: StateFlow<FranjaEntrega?> = _reservando.asStateFlow()

    private val _aviso = MutableStateFlow<String?>(null)

    /** Lo que volvió de un intento que no se pudo (la franja se ocupó, por ejemplo): se muestra arriba de las franjas. */
    val aviso: StateFlow<String?> = _aviso.asStateFlow()

    /** Desde cuándo se consulta seguido por una reserva pendiente (el tope de 60 s). */
    private var pendienteDesde = 0L
    private val reinicios = MutableStateFlow(0)

    /** El disco, fuera del hilo principal y de a una operación por vez, en el orden en que se pidieron (como [ModeloGuia]). */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private val serieDisco = Dispatchers.IO.limitedParallelism(1)

    /** La caché y la cola se leen al armar el modelo; [refrescar] y [reservar] lo esperan. */
    private val inicial: Job = alcance.launch {
        if (plantillaDemo != null) {
            _agenda.value = armarDemo(plantillaDemo, null)
            return@launch
        }
        val cache = withContext(serieDisco) { AgendaEntrega.desde(disco?.leer(ARCHIVO)) }
        if (_agenda.value == null && cache != null) _agenda.value = cache
        leerCola()
    }

    /** Para las pruebas: ya se leyó la caché y la cola, y lo pedido al disco ya se escribió. */
    suspend fun alDia() {
        inicial.join()
        alcance.launch(serieDisco) {}.join()
    }

    private suspend fun leerCola() {
        val op = outbox?.operaciones()?.lastOrNull { it.kind == KIND } ?: return
        franjaDe(op)?.let { if (_reservando.value == null) _reservando.value = it }
    }

    // ── Consultas ──

    /** `entregas_app_agenda`. Devuelve si contestó. */
    suspend fun refrescar(): Boolean {
        inicial.join()
        plantillaDemo?.let { p ->
            _agenda.value = armarDemo(p, _agenda.value?.reserva)
            return true
        }
        val r = cliente.llamar("entregas_app_agenda", mapOf("p_token" to ValorJson.Texto(token)))
        if (r is Resultado.Falla) {
            // La función no existe (antes de la 021): no hay agenda y la guía queda como en la 2.1.0.
            if (r.error.funcionInexistente || r.error.status == 404) {
                olvidar()
                return false
            }
            _desdeCache.value = _agenda.value != null
            return false
        }
        val v = (r as Resultado.Ok).valor
        if (v == ValorJson.Nulo || v == ValorJson.Booleano(false) || v["ok"] == ValorJson.Booleano(false)) {
            olvidar()
            return true
        }
        val a = AgendaEntrega.desde(v)
        if (a == null) {
            // Una forma que no se entiende no es «no hay agenda»: queda lo que había.
            _desdeCache.value = _agenda.value != null
            return false
        }
        val antes = _agenda.value?.reserva?.estado
        _agenda.value = a
        _desdeCache.value = false
        if (a.reserva?.estado == ReservaEntrega.Estado.FALLO && antes != ReservaEntrega.Estado.FALLO) {
            _aviso.value = ReglasAgenda.avisoFallo(a.reserva?.motivo)
        } else if (a.reserva?.vigente == true) {
            _aviso.value = null
        }
        if (a.reserva?.estado == ReservaEntrega.Estado.PENDIENTE && antes != ReservaEntrega.Estado.PENDIENTE) empezarASeguir()
        guardarCache(a)
        return true
    }

    /**
     * Lo que corre la pantalla mientras «Tu guía» está a la vista y en primer plano (se cancela al salir o al ir a segundo
     * plano; al volver, empieza de nuevo y consulta). Con la reserva pendiente, cada 5 s hasta 60 s. Con la confirmada y
     * Mati todavía sin entrar al Meet, cada 30 s desde 30 min antes hasta el fin de la franja (si falta, espera a esa hora).
     */
    suspend fun seguir() {
        if (esDemo) {
            refrescar()
            return
        }
        empezarASeguir()
        refrescar()
        while (true) {
            val vuelta = reinicios.value
            val antes = _agenda.value
            if (seguirConsultando()) {
                esperar(CONSULTA_CADA_MS)
                refrescar()
                continue
            }
            val sala = esperaSala(antes?.reserva)
            if (sala != null) {
                esperar(sala)
                refrescar()
                continue
            }
            // Nada que seguir: hasta que empiece una reserva o cambie la agenda (por ejemplo, al volver a primer plano).
            combine(reinicios, _agenda) { v, a -> v != vuelta || a !== antes }.first { it }
        }
    }

    /**
     * La tarjeta de Entreno abierta (y en primer plano): cada 30 s mira si está en la franja esperando que Mati abra la sala
     * y, si es así, consulta. La reserva es la de la agenda o, si no se consultó, la del resumen.
     */
    suspend fun seguirSala(reserva: () -> ReservaEntrega?) {
        if (esDemo) return
        inicial.join()
        while (true) {
            if (ReglasAgenda.esperandoSala(reserva(), ahora(), _agenda.value?.avisoMin)) refrescar()
            esperar(ReglasAgenda.CONSULTA_SALA_MS)
        }
    }

    private fun ahora(): Instant = Instant.ofEpochMilli(reloj())

    /** Cuánto esperar para la próxima consulta de la sala: 30 s dentro de la franja, hasta 30 min antes si falta; null si no aplica. */
    private fun esperaSala(r: ReservaEntrega?): Long? {
        if (r == null || r.estado != ReservaEntrega.Estado.CONFIRMADA || r.salaAbiertaEn != null) return null
        val i = r.inicio ?: return null
        val n = ahora()
        val avisoMin = _agenda.value?.avisoMin
        if (ReglasAgenda.esperandoSala(r, n, avisoMin)) return ReglasAgenda.CONSULTA_SALA_MS
        val ventana = i.minusSeconds(ReglasAgenda.minutosAntes(avisoMin) * 60)
        return if (n.isBefore(ventana)) Duration.between(n, ventana).toMillis().coerceAtLeast(1) else null
    }

    private fun seguirConsultando(): Boolean {
        val pendiente = _reservando.value != null || _agenda.value?.reserva?.estado == ReservaEntrega.Estado.PENDIENTE
        return pendiente && reloj() - pendienteDesde < TOPE_CONSULTAS_MS
    }

    private fun empezarASeguir() {
        pendienteDesde = reloj()
        reinicios.update { it + 1 }
    }

    /** La app volvió a primer plano (con la guía cerrada): solo con una reserva pendiente o esperando que Mati abra la sala. */
    suspend fun alVolverAPrimerPlano() {
        inicial.join()
        if (esDemo) return
        val r = _agenda.value?.reserva
        if (_reservando.value != null || r?.estado == ReservaEntrega.Estado.PENDIENTE || ReglasAgenda.esperandoSala(r, ahora(), _agenda.value?.avisoMin)) refrescar()
    }

    private fun olvidar() {
        _agenda.value = null
        _desdeCache.value = false
        _aviso.value = null
        disco?.let { d -> alcance.launch(serieDisco) { d.borrar(ARCHIVO) } }
    }

    private fun guardarCache(a: AgendaEntrega) {
        val d = disco ?: return
        alcance.launch(serieDisco) { d.guardar(ARCHIVO, a.aValor()) }
    }

    // ── Reservar ──

    /**
     * El cliente confirmó [f] en la hoja: sale por la cola. Devuelve false si no se encoló (otra en curso, ya hay una
     * reserva vigente o no hay cola).
     */
    suspend fun reservar(f: FranjaEntrega): Boolean {
        inicial.join()
        if (_reservando.value != null || _agenda.value?.reserva?.vigente == true) return false
        _aviso.value = null
        plantillaDemo?.let {
            // La demo confirma enseguida y no crea ninguna videollamada.
            val r = ReservaEntrega(nuevoId(), f.inicio, f.fin, ReservaEntrega.Estado.CONFIRMADA, meetUrl = null, motivo = null)
            _agenda.value = _agenda.value?.copy(reserva = r, franjas = emptyList())
            return true
        }
        val cola = outbox ?: return false
        _reservando.value = f
        cola.encolar(
            KIND,
            ValorJson.objeto(
                "franja" to ValorJson.Texto(f.id),
                "id" to ValorJson.Texto(nuevoId()),
                "inicio" to ValorJson.Texto(f.inicio.toString()),
                "fin" to ValorJson.Texto(f.fin.toString()),
            ),
            CLAVE,
        )
        empezarASeguir()
        return true
    }

    /** Lo que el servidor contestó (lo pasa [ModeloGuia] desde la cola). */
    fun alGuardar(ops: List<OpGuardada>) {
        val nuestras = ops.filter { it.op.kind == KIND }
        if (nuestras.isEmpty()) return
        alcance.launch {
            val g = nuestras.last()
            // Otra elección entró a la cola mientras esta volaba: la que manda es la nueva.
            val sigue = outbox?.operaciones()?.any { it.kind == KIND } == true
            if (!sigue) _reservando.value = null
            val v = g.respuesta
            val reserva = ReservaEntrega.desde(v["reserva"])
            val motivo = v["motivo"]?.comoTexto
            when {
                v["ok"] == ValorJson.Booleano(true) || (motivo == "ya_tiene" && reserva != null) -> {
                    if (reserva != null) {
                        _agenda.value = _agenda.value?.copy(reserva = reserva, franjas = if (reserva.vigente) emptyList() else _agenda.value?.franjas.orEmpty())
                    }
                    _aviso.value = null
                }
                motivo == "obligatorios" || motivo == "autorizada" -> Unit // la consulta de abajo muestra lo que falta
                else -> if (!sigue) _aviso.value = ReglasAgenda.avisoFallo(motivo)
            }
            _agenda.value?.let(::guardarCache)
            empezarASeguir()
            refrescar()
        }
    }

    /** Lo que la cola abandonó (8 intentos o un error nuestro): se puede elegir de nuevo. */
    fun alAbandonar(ops: List<Operacion>) {
        if (ops.none { it.kind == KIND }) return
        alcance.launch {
            if (outbox?.operaciones()?.any { it.kind == KIND } != true) _reservando.value = null
            _aviso.value = "No pudimos reservar ese horario, probá de nuevo."
        }
    }

    /** La demo: las franjas de muestra corridas para que empiecen mañana, y habilitada con lo visto en el teléfono. */
    private fun armarDemo(p: AgendaEntrega, reserva: ReservaEntrega?): AgendaEntrega {
        val faltan = faltanDemo()
        val primero = p.franjas.minOfOrNull { it.inicio }
        val corridas = if (primero == null) p.franjas else {
            val hoy = LocalDate.ofInstant(Instant.ofEpochMilli(reloj()), ReglasAgenda.ARGENTINA)
            val dias = java.time.temporal.ChronoUnit.DAYS.between(LocalDate.ofInstant(primero, ReglasAgenda.ARGENTINA), hoy.plusDays(1))
            p.franjas.map { it.copy(inicio = it.inicio.plus(Duration.ofDays(dias)), fin = it.fin.plus(Duration.ofDays(dias))) }
        }
        val habilitada = p.autorizada && faltan == 0
        return p.copy(
            habilitada = habilitada,
            faltan = faltan,
            franjas = if (habilitada && reserva?.vigente != true) corridas else emptyList(),
            reserva = reserva,
        )
    }

    companion object {
        const val KIND = "guia_reserva"

        /** Una sola reserva a la vez: elegir otra antes de que salga la primera la reemplaza en la cola. */
        const val CLAVE = "guia_reserva"

        internal const val ARCHIVO = "guia-agenda.json"
        const val CONSULTA_CADA_MS = 5_000L
        const val TOPE_CONSULTAS_MS = 60_000L

        fun nuevoId(): String = java.util.UUID.randomUUID().toString()

        internal fun franjaDe(op: Operacion): FranjaEntrega? {
            val id = op.payload["franja"]?.comoTexto ?: return null
            val i = AgendaEntrega.instante(op.payload["inicio"]?.comoTexto) ?: return null
            val f = AgendaEntrega.instante(op.payload["fin"]?.comoTexto)?.takeIf { it.isAfter(i) } ?: return null
            return FranjaEntrega(id, i, f)
        }

        /** La agenda de «Ver demo» (`apps/shared/demo/agenda.json`), para [ModeloGuia.demo]. */
        fun demo(cliente: ClienteRpc, plantilla: AgendaEntrega, alcance: CoroutineScope, faltan: () -> Int): ModeloAgenda =
            ModeloAgenda(cliente, token = "", outbox = null, disco = null, alcance = alcance, plantillaDemo = plantilla, faltanDemo = faltan)
    }
}
