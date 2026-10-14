package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Conexion
import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.RecuperacionDia
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.PuntoSalud
import com.pumpteam.mypump.reglas.RelojLocal
import com.pumpteam.mypump.reglas.SaludVista
import com.pumpteam.mypump.reglas.SemanticaJs
import com.pumpteam.mypump.reglas.TextosSalud
import java.time.Instant
import java.time.ZoneId
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Salud, recuperación y "Mi reloj" del cliente: lo que la web hace con `loadSalud`, `loadRecuperacion`, `loadConexiones` y
 * `window.MyPumpHealth`. Las cards leen de acá (SAL-09 a SAL-13, REV-08). Gemelo de ModeloSalud.swift.
 *
 * - Salud del teléfono: [conectar] (onboarding y botones), [sincronizar] (botón "Sincronizar"), [alAbrir] y [alVolver]
 *   (sincronizan 7 días y retoman el historial si está conectada; los llama [ModeloApp]).
 * - Lecturas: [cargar] trae 60 días de salud, 14 de recuperación y si el cliente quiere ver el score.
 * - Mi reloj: [cargarRelojes], [urlConectar] (se abre en una Custom Tab), [esperarConexion] (cada 3 s durante 2 min) y
 *   [quitar].
 *
 * Sin fuente (la demo, o un teléfono sin Health Connect) nada de la salud del sistema hace nada y [disponible] es false.
 * Como el `@MainActor` de iOS, se usa desde un solo hilo con el [alcance] del ViewModel.
 */
class ModeloSalud(
    private val cliente: ClienteRpc,
    private val token: String,
    fuente: FuenteSalud? = fuenteDelSistema,
    almacen: Preferencias,
    private val alcance: CoroutineScope,
    private val ahora: () -> Instant = Instant::now,
    private val zona: ZoneId = ZoneId.systemDefault(),
    /** Los textos de la plataforma (`_TXT_SALUD`): en Android, los de Health Connect. */
    val textos: TextosSalud = TextosSalud.ANDROID,
) {
    data class ProgresoHistorial(val hecho: Int, val total: Int)

    // MARK: Lo que muestran las cards

    /** `get_salud` de hoy − 59 a hoy (todas las fuentes; la vista elige la mejor por día). */
    private val _salud = MutableStateFlow<List<FilaSalud>>(emptyList())
    val salud: StateFlow<List<FilaSalud>> = _salud.asStateFlow()

    /** `get_recuperacion(14)`: la última es la más nueva. */
    private val _recuperacion = MutableStateFlow<List<RecuperacionDia>>(emptyList())
    val recuperacion: StateFlow<List<RecuperacionDia>> = _recuperacion.asStateFlow()

    /** `get_mostrar_recuperacion` (null o un error cuentan como true: el default es que el score exista). */
    private val _mostrarRecuperacion = MutableStateFlow(true)
    val mostrarRecuperacion: StateFlow<Boolean> = _mostrarRecuperacion.asStateFlow()

    /** `get_conexiones`. */
    private val _conexiones = MutableStateFlow<List<Conexion>>(emptyList())
    val conexiones: StateFlow<List<Conexion>> = _conexiones.asStateFlow()

    /** Los relojes que el servidor tiene habilitados (null = todavía no se preguntó). */
    private val _relojesDisponibles = MutableStateFlow<List<String>?>(null)
    val relojesDisponibles: StateFlow<List<String>?> = _relojesDisponibles.asStateFlow()

    private val _cargado = MutableStateFlow(false)
    val cargado: StateFlow<Boolean> = _cargado.asStateFlow()

    private val _fecha = MutableStateFlow(FechaLocal.hoy(ahora(), zona))
    val fecha: StateFlow<String> = _fecha.asStateFlow()

    // MARK: La salud del sistema

    private val _disponible = MutableStateFlow(false)
    val disponible: StateFlow<Boolean> = _disponible.asStateFlow()

    private val _conectado = MutableStateFlow(false)
    val conectado: StateFlow<Boolean> = _conectado.asStateFlow()

    private val _sinDatos = MutableStateFlow(false)
    val sinDatos: StateFlow<Boolean> = _sinDatos.asStateFlow()

    private val _ultimaSync = MutableStateFlow<Instant?>(null)
    val ultimaSync: StateFlow<Instant?> = _ultimaSync.asStateFlow()

    /** "Trayendo tu historial… 40/60 días". */
    private val _progresoHistorial = MutableStateFlow<ProgresoHistorial?>(null)
    val progresoHistorial: StateFlow<ProgresoHistorial?> = _progresoHistorial.asStateFlow()

    private val _sincronizando = MutableStateFlow(false)
    val sincronizando: StateFlow<Boolean> = _sincronizando.asStateFlow()

    private val _conectando = MutableStateFlow(false)
    val conectando: StateFlow<Boolean> = _conectando.asStateFlow()

    /** El proveedor que se está esperando después de "Conectar" (Oura/WHOOP). */
    private val _esperandoReloj = MutableStateFlow<String?>(null)
    val esperandoReloj: StateFlow<String?> = _esperandoReloj.asStateFlow()

    val sincronizador: SincronizadorSalud? = fuente?.let { SincronizadorSalud(it, cliente, token, almacen, alcance, ahora, zona) }
    private var sondeo: Deferred<Boolean>? = null

    init {
        sincronizador?.alCambiar = { alcance.launch { cargar() } }
        sincronizador?.alCambiarProgreso = { p -> _progresoHistorial.value = p?.let { ProgresoHistorial(it.first, it.second) } }
        leerEstado()
    }

    // MARK: Ciclo de vida

    /** Al arrancar la app con la cuenta: las lecturas y, si la salud está conectada, los 7 días y el historial pendiente. */
    suspend fun alAbrir() {
        val s = sincronizador
        if (s != null) {
            _disponible.value = disponibleSeguro(s)
            if (s.conectado) {
                s.retomarHistorialSiFalta()
                vigilarHistorial()
            }
        }
        coroutineScope {
            val lecturas = launch { cargar() }
            val relojes = launch { cargarRelojes() }
            if (sincronizador?.conectado == true) sincronizar()
            lecturas.join()
            relojes.join()
        }
    }

    /** Al volver a primer plano (`visibilitychange`; lo llama `ModeloApp.alVolverAPrimerPlano`): si está conectada, 7
     *  días y retomar el historial. */
    suspend fun alVolver() {
        _fecha.value = FechaLocal.hoy(ahora(), zona)
        val s = sincronizador ?: return
        if (!s.conectado) return
        s.retomarHistorialSiFalta()
        vigilarHistorial()
        sincronizar()
    }

    // MARK: La salud del sistema

    /**
     * "Conectar Health Connect": permisos en dos tandas, 7 días y el historial de fondo. El aviso de "no llegó nada" espera
     * al historial (con 7 días vacíos no se puede acusar a nadie de haber denegado).
     */
    suspend fun conectar(): ResultadoConexion {
        val s = sincronizador ?: return ResultadoConexion(false, "no_disponible", null, null, 0, false, emptyList(), null)
        _conectando.value = true
        try {
            val r = s.conectar()
            leerEstado()
            if (r.ok) {
                vigilarHistorial()
                cargar()
            }
            return r
        } finally {
            _conectando.value = false
        }
    }

    /**
     * Para el onboarding de permisos (GEN-06): espera la conexión como mucho [limiteMs] (la web corta a los 20 s con
     * `_conTimeout`). Si se pasa devuelve null y la conexión SIGUE de fondo: la puerta de salida nunca se traba.
     */
    suspend fun conectar(limiteMs: Long): ResultadoConexion? {
        val tarea = alcance.async { conectar() }
        return withTimeoutOrNull(limiteMs) { tarea.await() }
    }

    /** "Sincronizar" (y al abrir y al volver): los últimos 7 días. */
    suspend fun sincronizar(): ResultadoSync {
        val s = sincronizador ?: return ResultadoSync(false, "no_disponible", 0, 0, null)
        _sincronizando.value = true
        try {
            val r = s.sincronizar()
            leerEstado()
            return r
        } finally {
            _sincronizando.value = false
        }
    }

    /** Solo local: deja de sincronizar, lo subido queda. */
    fun desconectar() {
        sincronizador?.desconectar()
        leerEstado()
    }

    suspend fun estado(): EstadoSalud? = sincronizador?.estado()
    suspend fun diagnostico(): DiagnosticoSalud? = sincronizador?.diagnostico()
    val ultimoIntento: ValorJson? get() = sincronizador?.ultimoIntento
    val ultimoErrorIngesta: String? get() = sincronizador?.ultimoErrorIngesta

    private suspend fun disponibleSeguro(s: SincronizadorSalud): Boolean = try {
        s.fuente.disponible()
    } catch (e: CancellationException) {
        throw e
    } catch (_: Exception) {
        false
    }

    private fun leerEstado() {
        val s = sincronizador
        _conectado.value = s?.conectado ?: false
        _sinDatos.value = s?.sinDatos ?: false
        _ultimaSync.value = s?.ultimaSync?.let(RelojLocal::desdeIso)?.let { Instant.ofEpochMilli(it.toLong()) }
        _progresoHistorial.value = s?.progresoHistorial?.let { ProgresoHistorial(it.first, it.second) }
    }

    /** Sigue al historial de fondo para apagar el contador cuando termina. */
    private fun vigilarHistorial() {
        leerEstado()
        val t = sincronizador?.historialEnCurso ?: return
        alcance.launch {
            t.join()
            leerEstado()
        }
    }

    // MARK: Lecturas

    /** `loadSalud` + `loadRecuperacion`. */
    suspend fun cargar() {
        val hoy = FechaLocal.hoy(ahora(), zona)
        _fecha.value = hoy
        val t = texto(token)
        val desde = DiaCalendario.numero(hoy)?.let { DiaCalendario.texto(it - 59) } ?: hoy
        coroutineScope {
            val s = async { cliente.filas("mypump_get_salud", mapOf("p_token" to t, "p_desde" to texto(desde), "p_hasta" to texto(hoy)), FilaSalud::desde) }
            val r = async { cliente.filas("mypump_get_recuperacion", mapOf("p_token" to t, "p_dias" to numero(14)), RecuperacionDia::desde) }
            val m = async { cliente.llamar("mypump_get_mostrar_recuperacion", mapOf("p_token" to t)) }
            _salud.value = s.await().valorONull() ?: emptyList()
            _recuperacion.value = r.await().valorONull() ?: emptyList()
            // `(m === null || m === undefined) ? true : !!m`, y un error también es "mostrar".
            val v = m.await().valorONull()
            _mostrarRecuperacion.value = v == null || v == ValorJson.Nulo || SemanticaJs.esVerdadero(v)
        }
        _cargado.value = true
        leerEstado()
    }

    /** "Mostrarme el score": optimista (la pantalla responde ya). */
    suspend fun cambiarMostrarRecuperacion(mostrar: Boolean) {
        _mostrarRecuperacion.value = mostrar
        cliente.llamar("mypump_set_mostrar_recuperacion", mapOf("p_token" to texto(token), "p_mostrar" to ValorJson.Booleano(mostrar)))
    }

    // MARK: Lo que derivan las cards

    val cardRecuperacion: SaludVista.CardRecuperacion
        get() = SaludVista.cardRecuperacion(
            _recuperacion.value, _conectado.value, _mostrarRecuperacion.value, _salud.value,
            _progresoHistorial.value?.let { it.hecho to it.total }, _sinDatos.value, _fecha.value,
        )

    val resumenSalud: SaludVista.ResumenSalud? get() = SaludVista.resumen(_salud.value, _fecha.value)

    fun valor(tipo: String, fecha: String): Double? = SaludVista.valor(_salud.value, tipo, fecha)

    fun serie(tipo: String): List<PuntoSalud> = SaludVista.serie(_salud.value, tipo)

    /** Para "Cómo se arma tu recuperación" (la última fila, como la escena de la web). */
    val componentes: List<SaludVista.Componente> get() = SaludVista.componentes(_recuperacion.value.lastOrNull())
    val scoreDeHoy: Int? get() = _recuperacion.value.lastOrNull()?.score

    // MARK: Mi reloj (Oura, WHOOP)

    data class Reloj(
        val id: String,
        val nombre: String,
        val descripcion: String,
        val conectado: Boolean,
        val enError: Boolean,
        val ultimaSincronizacion: String?,
    )

    /** `loadConexiones`: qué ofrece el servidor (una vez) y qué tiene conectado el cliente. */
    suspend fun cargarRelojes() {
        if (_relojesDisponibles.value == null) _relojesDisponibles.value = cliente.relojesDisponibles() ?: emptyList()
        val r = cliente.filas("mypump_get_conexiones", mapOf("p_token" to texto(token)), Conexion::desde)
        if (r is Resultado.Ok) _conexiones.value = r.valor
    }

    /** Se muestra un reloj si el servidor lo habilita O si el cliente ya lo tenía (para que pueda verlo y quitarlo). */
    val relojesVisibles: List<Reloj>
        get() {
            val disponibles = _relojesDisponibles.value ?: emptyList()
            return relojes.mapNotNull { (id, nombre, descripcion) ->
                val c = _conexiones.value.firstOrNull { it.proveedor == id }
                if (id !in disponibles && c == null) return@mapNotNull null
                val conectada = c?.estado == "conectada"
                Reloj(id, nombre, descripcion, conectada, c?.estado == "error", if (conectada) c.ultimoPullEn?.let(::fechaCorta) else null)
            }
        }

    /** "Si usás Oura o WHOOP, conectalo y…" (cliente.html:8169, con la frase de cada plataforma). */
    val textoRelojes: String
        get() {
            val nombres = relojesVisibles.joinToString(" o ") { it.nombre }
            val cola = if (textos == TextosSalud.ANDROID) "Tu reloj no se conecta acá: va por Health Connect."
            else "Apple Watch no se conecta acá: va por Salud de Apple desde la app de iPhone."
            return "Si usás $nombres, conectalo y tus datos de sueño y recuperación entran solos. $cola"
        }

    fun urlConectar(proveedor: String): String = cliente.urlConectarReloj(token, proveedor)

    /**
     * Después de abrir la autorización: `get_conexiones` cada 3 s, 40 veces (2 min). El callback no vuelve a la app, así
     * que la app pregunta. true si quedó conectado (y ya se recargó lo demás).
     */
    suspend fun esperarConexion(proveedor: String, cadaMs: Long = 3_000, intentos: Int = 40): Boolean {
        sondeo?.cancel()
        _esperandoReloj.value = proveedor
        val tarea = alcance.async(start = CoroutineStart.LAZY) {
            repeat(intentos) {
                delay(cadaMs)
                val r = cliente.filas("mypump_get_conexiones", mapOf("p_token" to texto(token)), Conexion::desde)
                if (r is Resultado.Ok && r.valor.any { it.proveedor == proveedor && it.estado == "conectada" }) {
                    _conexiones.value = r.valor
                    return@async true
                }
            }
            false
        }
        sondeo = tarea
        tarea.start()
        val ok = try {
            tarea.await()
        } catch (e: CancellationException) {
            // Cortaron el sondeo (otra espera o "salir"): para quien esperaba es un "no".
            if (!currentCoroutineContext().isActive) throw e
            false
        }
        if (sondeo === tarea) {
            _esperandoReloj.value = null
            sondeo = null
        }
        if (ok) cargar()
        return ok
    }

    /** Corta el sondeo (al salir de la cuenta). Cerrar el navegador NO lo corta: como en la web, se sigue preguntando los
     *  2 minutos, porque el callback del proveedor puede llegar después de que el cliente volvió a la app. */
    fun cancelarEspera() {
        sondeo?.cancel()
        sondeo = null
        _esperandoReloj.value = null
    }

    /** "Quitar" (con confirmación en la vista): dejamos de traer sus datos; los que ya están se quedan. */
    suspend fun quitar(proveedor: String) {
        cliente.llamar("mypump_desconectar_wearable", mapOf("p_token" to texto(token), "p_proveedor" to texto(proveedor)))
        cargarRelojes()
    }

    /** `new Date(iso).toLocaleDateString('es-AR', {day: 'numeric', month: 'short'})`: el día local, "12 oct". */
    internal fun fechaCorta(iso: String): String {
        val ms = RelojLocal.desdeIso(iso) ?: return iso
        return SaludVista.fechaCorta(RelojLocal(zona).ymd(ms)) ?: iso
    }

    companion object {
        /** La fuente del sistema: la pone `:app` (Health Connect) al arrancar; sin ella, nada de la salud del sistema. */
        @Volatile var fuenteDelSistema: FuenteSalud? = null

        /** `PROVEEDORES_UI`. */
        val relojes: List<Triple<String, String, String>> = listOf(
            Triple("oura", "Oura", "Anillo · trae sueño, pulso y variabilidad reales"),
            Triple("whoop", "WHOOP", "Banda · trae sueño, pulso y variabilidad reales"),
        )

        /** El texto de "Sincronizar" en Mis datos. */
        fun textoSincronizacion(r: ResultadoSync): String {
            r.errorIngesta?.let { return "No se pudieron guardar los datos ($it). Probá de nuevo en un rato." }
            return if (r.ingresados > 0) "Listo: ${r.ingresados} datos nuevos." else "Ya estabas al día."
        }
    }
}
