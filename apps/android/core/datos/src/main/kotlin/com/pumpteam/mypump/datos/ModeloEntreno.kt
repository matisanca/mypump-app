package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ClienteInfo
import com.pumpteam.mypump.modelos.Comentario
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.EstadoEjercicio
import com.pumpteam.mypump.modelos.EstructuraRutina
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.RegistroSesion
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.Sesion
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.BannerSemana
import com.pumpteam.mypump.reglas.BarraDescanso
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.Descanso
import com.pumpteam.mypump.reglas.DiaEnCurso
import com.pumpteam.mypump.reglas.EjercicioEfectivo
import com.pumpteam.mypump.reglas.EstadosEjercicio
import com.pumpteam.mypump.reglas.FechaJs
import com.pumpteam.mypump.reglas.FilaSerie
import com.pumpteam.mypump.reglas.IndiceComentarios
import com.pumpteam.mypump.reglas.Js
import com.pumpteam.mypump.reglas.NormalizacionRutina
import com.pumpteam.mypump.reglas.NotaProgresion
import com.pumpteam.mypump.reglas.Pauta
import com.pumpteam.mypump.reglas.Pregunta
import com.pumpteam.mypump.reglas.Progresiones
import com.pumpteam.mypump.reglas.ReglasEjercicio
import com.pumpteam.mypump.reglas.ResumenDia
import com.pumpteam.mypump.reglas.SemanaEntreno
import com.pumpteam.mypump.reglas.SemanticaJs
import com.pumpteam.mypump.reglas.SustitucionesEntreno
import com.pumpteam.mypump.reglas.SustitutoEjercicio
import com.pumpteam.mypump.reglas.TextosEntreno
import com.pumpteam.mypump.reglas.TiempoEntreno
import com.pumpteam.mypump.reglas.UltimaVez
import com.pumpteam.mypump.reglas.VariantesEjercicio
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * El motor de la pantalla de Entreno: la semana, el día que se mira, la sesión del día con sus series, el historial, el
 * descanso, los comentarios, las sustituciones, cerrar el día y avanzar de semana. Hace lo mismo que cliente.html (init,
 * restoreSesionDelDia, loadHistorico, writeFinish, doAvanzarSemana…) y que ModeloEntreno.swift; las reglas puras viven en
 * :core:reglas (`DiaEnCurso` y compañía) y acá se ejecutan sus efectos: la cola, el disco y la base.
 *
 * Se arma con lo que ya cargó [ModeloApp] (cliente, token, cola, disco de la cuenta, rutina e info). Sin token es la
 * demo: no toca la red ni escribe nada. Como `ModeloApp`, se usa desde UN solo hilo (el `@MainActor` de iOS): lo que lanza
 * va al [alcance] (el `viewModelScope`), y cada cambio publica una copia nueva del día y de la barra del descanso.
 */
class ModeloEntreno(
    val cliente: ClienteRpc,
    val token: String?,
    private val outbox: Outbox?,
    private val disco: Disco?,
    rutinaInicial: RutinaActiva,
    val info: ClienteInfo? = null,
    catalogoInicial: CatalogoEjercicios = CatalogoEjercicios(emptyList()),
    esDemo: Boolean? = null,
    private val zona: ZoneId = ZoneId.systemDefault(),
    private val reloj: () -> Instant = Instant::now,
    private val alcance: CoroutineScope,
) {
    val demo: Boolean = esDemo ?: (token == null || outbox == null)

    private val normalizacionInicial = NormalizacionRutina.normalizar(rutinaInicial.estructura)

    private val _rutina = MutableStateFlow(rutinaInicial)
    val rutina: StateFlow<RutinaActiva> = _rutina.asStateFlow()

    /** La estructura ya normalizada (`normalizarRutina`, ENT-04). */
    private val _estructura = MutableStateFlow(normalizacionInicial.estructura)
    val estructura: StateFlow<EstructuraRutina> = _estructura.asStateFlow()

    /** Hay al menos un día con ejercicios. Si no, la app muestra la rutina de ejemplo (ACC-08). */
    private val _usable = MutableStateFlow(normalizacionInicial.usable)
    val usable: StateFlow<Boolean> = _usable.asStateFlow()

    /** Lo que le faltaba al plan (el aviso de GEN-05). */
    private val _problemas = MutableStateFlow(normalizacionInicial.problemas)
    val problemas: StateFlow<List<String>> = _problemas.asStateFlow()

    /** Días con la sesión de ESTA semana cerrada (el ✓ del selector, `get_sesiones_semana`). */
    private val _diasCompletados = MutableStateFlow<Set<String>>(emptySet())
    val diasCompletados: StateFlow<Set<String>> = _diasCompletados.asStateFlow()

    private val _comentarios = MutableStateFlow(IndiceComentarios())
    val comentarios: StateFlow<IndiceComentarios> = _comentarios.asStateFlow()

    /** Lo último que se escribió del descanso (el tick corre cada 250 ms: se escribe solo si cambió). */
    private var descansoEnDisco: Descanso.Guardado? = disco?.leer(Archivo.DESCANSO)?.let { Descanso.Guardado.desde(ValorJson.desde(it)) }

    private val _descanso = MutableStateFlow(BarraDescanso(descansoEnDisco))
    val descanso: StateFlow<BarraDescanso> = _descanso.asStateFlow()

    /** Cuándo arrancó la sesión del día (ms desde 1970, `_sessionStart`). */
    private val _inicioSesion = MutableStateFlow<Double?>(null)
    val inicioSesion: StateFlow<Double?> = _inicioSesion.asStateFlow()

    /** Se tocó "Empezar entrenamiento" (si no, el cronómetro dice "⏱ arrancó con tu primera serie"). */
    private val _iniciadaConBoton = MutableStateFlow(false)
    val iniciadaConBoton: StateFlow<Boolean> = _iniciadaConBoton.asStateFlow()

    /** Hay sesión en el servidor (o se pidió crearla): el botón "Cerrar sesión de hoy" se ve habilitado. */
    private val _sesionIniciada = MutableStateFlow(false)
    val sesionIniciada: StateFlow<Boolean> = _sesionIniciada.asStateFlow()

    /** Historial pedido y todavía sin respuesta. */
    private val _historialCargando = MutableStateFlow<Set<String>>(emptySet())
    val historialCargando: StateFlow<Set<String>> = _historialCargando.asStateFlow()

    private val _catalogo = MutableStateFlow(catalogoInicial)
    val catalogo: StateFlow<CatalogoEjercicios> = _catalogo.asStateFlow()

    /** Se llama cuando el modelo trae una rutina nueva (avanzar de semana, bloque nuevo, recargar), para que [ModeloApp] la tenga también. */
    var alCambiarRutina: ((RutinaActiva) -> Unit)? = null

    private var sesionesLocales: Map<String, SesionLocal> = disco?.let { leerSesiones(it) } ?: emptyMap()
    private var sinHistorialPorClave = false
    private val generacionHistorial = HashMap<String, Int>()
    private val historialEnVuelo = HashMap<String, Job>()

    /** La creación de la sesión en vuelo, por día y semana (la de otro día no sirve). */
    private var sesionEnVuelo: Pair<String, Deferred<String?>>? = null

    /** SER-14: lo último que se escribió en el archivo de la rutina. Lo que cambie desde acá sale por la cola. */
    private var sustitucionesGuardadas: Map<String, ValorJson> = emptyMap()

    /** SER-14: mientras se espera al servidor, lo que se tocó en el medio (ahí gana lo del teléfono). null = no se espera. */
    private var tocadasDuranteSync: MutableSet<String>? = null

    /** SER-14: la sincronización en curso (una a la vez; cambiar de rutina la deja sin efecto). */
    private var syncSustituciones: Any? = null

    /** SER-14: los encolados de sustituciones, en fila (si no, dos cambios seguidos podían llegar a la cola al revés). */
    internal var encoladoSustituciones: Job? = null
        private set
    private var restauracion = 0
    private var diaCompletadoMostrado = false

    /** Había un día guardado en este teléfono al arrancar (si no, el del almacenamiento viejo puede ganar). */
    private var habiaDiaGuardado: Boolean

    /** El día que se mira, con su sesión, sus series, su historial y las sustituciones de la rutina. */
    private val _dia: MutableStateFlow<DiaEnCurso>
    val dia: StateFlow<DiaEnCurso>

    init {
        val semana = if (rutinaInicial.semanaActual == 0) 1 else rutinaInicial.semanaActual
        val guardado = disco?.let { leerTexto(it, Archivo.dia(rutinaInicial.id)) }
        habiaDiaGuardado = guardado != null
        val elegido = TextosEntreno.diaSugerido(normalizacionInicial.estructura.dias, guardado) ?: Dia(id = "d1")
        val d = DiaEnCurso(elegido, semana, demo, zona = zona)
        d.sustituciones = SustitucionesEntreno.compat(leerSustituciones(rutinaInicial.id))
        sustitucionesGuardadas = leerEncoladas(rutinaInicial.id) ?: d.sustituciones
        _dia = MutableStateFlow(d)
        dia = _dia.asStateFlow()
        guardarDiaVisualizado()
    }

    /**
     * Lo que la web hace en el arranque después de pintar: poda las sustituciones vencidas, vuelve a poner el descanso
     * que estaba corriendo, trae el historial del día, restaura la sesión del día (confirmándola con el servidor), los
     * días completados de la semana y los comentarios.
     */
    suspend fun cargar() {
        // Lo que se cambió y no llegó a la cola (la app se cerró en el medio), antes de leer el servidor.
        encolarSustituciones()
        podarSustituciones()
        // Solo si no hay uno corriendo: restaurar borra lo guardado (como la web), y un segundo `cargar()` (tirar para
        // actualizar) dejaría el descanso en curso sin copia en disco.
        if (_descanso.value.descanso == null) {
            mutarDescanso { it.restaurar(ahoraMs) }
            guardarDescanso()
        }
        coroutineScope {
            val historial = launch { precargarHistorial() }
            val servidor = launch { sincronizarSustituciones() }
            restaurarSesion()
            val completados = launch { cargarDiasCompletados() }
            val coms = launch { cargarComentarios() }
            historial.join()
            servidor.join()
            completados.join()
            coms.join()
        }
    }

    // ── Semana y días ──

    /** `semana_actual || 1`: la que se usa para escribir. `semana_offset` solo cambia rótulos (ENT-09). */
    val semana: Int get() = _dia.value.semana
    val semanasTotal: Int get() = _estructura.value.semanasTotal ?: 12
    val offset: Int get() = _estructura.value.semanaOffset ?: 0

    /** "SEM x/y" del encabezado, con el offset del macrociclo. */
    val semanaMostrada: Int get() = semana + offset
    val totalMostrado: Int get() = semanasTotal + offset
    val dias: List<Dia> get() = _estructura.value.dias

    /** "DÍA n" de un día (`getDayNum`). */
    fun numero(d: Dia): Int = TextosEntreno.numeroDia(d, dias)

    /** La primera palabra del nombre (`getDayShortName`). */
    fun nombreCorto(d: Dia): String = TextosEntreno.nombreCortoDia(d.nombre)

    /** ✓ del selector: el día tiene la sesión de esta semana cerrada. */
    fun hecho(d: Dia): Boolean = d.id?.let { it in _diasCompletados.value } ?: false

    /** 💬 del selector. */
    fun sinLeer(d: Dia): Int = _comentarios.value.sinLeerDia(d)

    /** El badge de la pestaña Entreno (sin el chat). */
    val sinLeerEntreno: Int get() = _comentarios.value.totalEntreno

    /** ENT-07/08 */
    val banner: BannerSemana get() = SemanaEntreno.banner(_dia.value.dia, semana, offset)
    val puedeAvanzar: Boolean get() = SemanaEntreno.puedeAvanzar(semana, semanasTotal, demo)
    val puedeEmpezarBloque: Boolean get() = SemanaEntreno.puedeEmpezarBloque(semana, semanasTotal, _rutina.value.tieneSiguiente, demo)
    val botonAvanzar: String get() = SemanaEntreno.botonAvanzar(semana, offset)

    /** La confirmación de "Pasar a Semana N" (cambia si el día está incompleto). */
    val preguntaAvanzar: Pregunta? get() = SemanaEntreno.preguntaAvanzar(semana, semanasTotal, offset, _dia.value.diaCompleto)

    /**
     * `cambiarDia` (ENT-02): la ÚNICA forma de cambiar de día. Poda antes de mover (con el estado del día que se deja),
     * arma la sesión del nuevo, recuerda el día en este teléfono y restaura su sesión.
     */
    suspend fun cambiarDia(id: String) {
        val nuevo = dias.firstOrNull { it.id == id } ?: return
        if (nuevo.id == _dia.value.dia.id) return
        mutarDescanso { it.detener() }
        guardarDescanso()
        podarSustituciones(sinPrecarga = true)
        val sustituciones = _dia.value.sustituciones
        val semana = this.semana
        historialEnVuelo.values.forEach { it.cancel() }
        historialEnVuelo.clear()
        _historialCargando.value = emptySet()
        generacionHistorial.replaceAll { _, g -> g + 1 }
        _dia.value = DiaEnCurso(nuevo, semana, demo, zona = zona).also { it.sustituciones = sustituciones }
        diaCompletadoMostrado = false
        guardarDiaVisualizado()
        coroutineScope {
            val historial = launch { precargarHistorial() }
            restaurarSesion()
            historial.join()
        }
    }

    // ── El día ──

    /** Un bloque como lo pinta la web: "B{i} · NOMBRE · hechos/total" (ENT-05). */
    data class BloqueDelDia(val indice: Int, val nombre: String, val hechos: Int, val ejercicios: List<Ejercicio>)

    val bloques: List<BloqueDelDia>
        get() {
            val d = _dia.value
            return d.dia.bloques.mapIndexed { i, b ->
                BloqueDelDia(i, TextosEntreno.nombreBloque(b), b.ejercicios.count { d.estado(it.id) in EstadosEjercicio.terminales }, b.ejercicios)
            }
        }

    val totalEjercicios: Int get() = _dia.value.lista.size
    val hechos: Int get() = _dia.value.hechos

    /** "Este día no tiene ejercicios cargados…" (ENT-16) */
    val vacio: Boolean get() = _dia.value.lista.isEmpty()

    /** Todos en un estado terminal, o el día cerrado: se muestra la card de cierre. */
    val todoHecho: Boolean get() = (totalEjercicios > 0 && hechos == totalEjercicios) || _dia.value.diaFinalizado
    val resumen: ResumenDia get() = _dia.value.resumen

    /** Los minutos de la sesión, o null (más de 6 h, SES-03): la UI pinta "—". */
    val minutos: Int? get() = TiempoEntreno.minutosSesion(_inicioSesion.value, ahoraMs)

    /** El cronómetro de arriba (llamarlo en cada tick de la vista). */
    fun cronometro(): TiempoEntreno.Cronometro? =
        TiempoEntreno.cronometro(_inicioSesion.value, ahoraMs, _iniciadaConBoton.value, _dia.value.diaFinalizado, todoHecho)

    /** El botón "Cerrar sesión de hoy" del pie se ve habilitado. */
    val cierreHabilitado: Boolean get() = _sesionIniciada.value || hechos > 0

    /** La card de un ejercicio del día, con todo lo que muestra (ENT-10/11). */
    data class Tarjeta(
        val lugar: String,
        val efectivo: EjercicioEfectivo,
        val estado: String,
        /** Chip "manual": `completo_sin_datos` marcado a mano. */
        val manual: Boolean,
        val sinLeer: Int,
        val pauta: Pauta,
        /** La nota de la semana (null en el calentamiento). */
        val nota: NotaProgresion?,
        val sinKg: Boolean,
        val variantes: VariantesEjercicio?,
        val varianteActual: String?,
        val filas: List<FilaSerie>,
        val confirmadas: Int,
        /** "🏆 Récord" / "Primera vez con este ejercicio" (null). */
        val record: String?,
        val ultimaVez: UltimaVez?,
        val puedeSustituir: Boolean,
        /** El chip del descanso ("2:30"). */
        val descanso: String,
        val comentarios: List<Comentario>,
    )

    fun tarjeta(lugar: String): Tarjeta? {
        val d = _dia.value
        val plan = d.ejercicio(lugar) ?: return null
        val ef = efectivo(plan)
        val e = d.ejercicios[lugar]
        val variantes = ReglasEjercicio.variantes(ef.ejercicio.nombre)
        return Tarjeta(
            lugar = lugar, efectivo = ef, estado = d.estado(lugar),
            manual = d.estado(lugar) == "completo_sin_datos" && d.meta[lugar]?.manual == true,
            sinLeer = _comentarios.value.sinLeer(lugar), pauta = Progresiones.pauta(ef.ejercicio, semana),
            nota = if (ef.ejercicio.tipo == "calentamiento") null else Progresiones.nota(ef.ejercicio, semanaActual = semana),
            sinKg = ReglasEjercicio.sinKg(ef.ejercicio), variantes = variantes,
            varianteActual = Js.verdadero(e?.variante) ?: variantes?.opciones?.firstOrNull(),
            filas = e?.series?.indices?.mapNotNull { d.fila(lugar, it, ef.ejercicio) } ?: emptyList(),
            confirmadas = e?.series?.count { it.confirmada } ?: 0,
            record = d.record(lugar), ultimaVez = d.ultimaVez(lugar, reloj()),
            puedeSustituir = _catalogo.value.sustitutos(ef).isNotEmpty(),
            descanso = TiempoEntreno.fmtTiempo((plan.descansoSegundos ?: NormalizacionRutina.DESCANSO_POR_DEFECTO).toDouble()),
            comentarios = _comentarios.value.comentarios(lugar),
        )
    }

    /** `getEffectiveEx`: el sustituto si hay, o las fotos del catálogo si el plan no las trae. */
    fun efectivo(ex: Ejercicio): EjercicioEfectivo =
        _catalogo.value.efectivo(ex, SustitucionesEntreno.aplicada(_dia.value.sustituciones[ex.id]))

    fun actualizarCatalogo(c: CatalogoEjercicios) {
        _catalogo.value = c
    }

    // ── Acciones de la card ──

    /**
     * Lo que pasa después de una acción que puede completar el día: la pregunta "🎉 ¡Día completado!" (una sola vez por
     * día) y el día siguiente al que ofrece ir.
     */
    data class DiaCompletado(val pregunta: Pregunta, val siguiente: Dia?)

    /** Abrir o cerrar una card (al abrir: historial y comentarios leídos). */
    suspend fun tocarCard(lugar: String) {
        ejecutar(mutarDia { it.tocarCard(lugar) })
    }

    /** Un campo de la serie (SER-04). */
    fun escribir(lugar: String, idx: Int, campo: String, valor: String) {
        mutarDia { it.escribir(lugar, idx, campo, valor) }
    }

    /**
     * El check o el "✓ Tocá para registrar lo de la última vez" (SER-01/03/05). `preguntar` muestra la pregunta y devuelve
     * lo que eligió el cliente (reabrir el día cerrado; "¿Está bien cargado?").
     */
    suspend fun confirmarSerie(lugar: String, idx: Int, preguntar: suspend (Pregunta) -> Boolean): DiaCompletado? {
        var respuestas = DiaEnCurso.Respuestas()
        var completo: DiaCompletado? = null
        // Lo que se muestra (el sustituto, si hay) decide si la serie lleva kg, como en la fila (revisión del 14-oct).
        val ef = _dia.value.ejercicio(lugar)?.let { efectivo(it).ejercicio }
        while (true) {
            val paso = mutarDia { it.confirmarSerie(lugar, idx, respuestas, ef) }
            ejecutar(paso.efectos)?.let { completo = it }
            val p = paso.pregunta ?: return completo
            val motivo = paso.motivo ?: return completo
            val si = preguntar(p)
            respuestas = when (motivo) {
                DiaEnCurso.Paso.Motivo.REABRIR -> respuestas.copy(reabrir = si)
                DiaEnCurso.Paso.Motivo.REGISTRAR_IGUAL -> respuestas.copy(registrarIgual = si)
            }
        }
    }

    /** El lápiz (SER-06). */
    suspend fun editarSerie(lugar: String, idx: Int) {
        ejecutar(mutarDia { it.editarSerie(lugar, idx) })
    }

    /** El selector de RIR 0-5 (SER-02): la leyenda del valor actual es `CamposSerie.leyendaRir`. */
    suspend fun elegirRir(lugar: String, idx: Int, valor: Int) {
        ejecutar(mutarDia { it.elegirRir(lugar, idx, valor.toString()) })
    }

    /** Agarre o nivel (SER-07). */
    fun elegirVariante(lugar: String, v: String) {
        mutarDia { it.elegirVariante(lugar, v) }
    }

    /** "Marcar ejercicio completo" */
    suspend fun marcarCompleto(lugar: String): DiaCompletado? = ejecutar(mutarDia { it.marcarCompleto(lugar) })

    /** "Terminé este ejercicio" (SER-15) */
    suspend fun terminar(lugar: String, preguntar: suspend (Pregunta) -> Boolean): DiaCompletado? {
        val p = _dia.value.preguntaTerminar(lugar)
        if (p != null && !preguntar(p)) return null
        // La web espera la sesión antes de marcar: el estado sale con su id.
        asegurarSesion()
        return ejecutar(mutarDia { it.terminar(lugar) })
    }

    /** "Reabrir ejercicio" */
    suspend fun reabrir(lugar: String) {
        ejecutar(mutarDia { it.reabrir(lugar) })
    }

    // ── Sesión (SES-01/02/03) ──

    /** "▶ Empezar entrenamiento": arranca el cronómetro y crea la sesión. */
    suspend fun empezar() {
        _iniciadaConBoton.value = true
        asegurarSesion()
    }

    /** "Empezar de nuevo" con una sesión de más de 6 h: solo mueve el arranque del cronómetro. */
    fun reiniciarCronometro() {
        _inicioSesion.value = ahoraMs
        _iniciadaConBoton.value = true
        guardarInicio()
    }

    /**
     * `ensureSesionIniciada`: arranca el cronómetro y crea la sesión del día y la semana (idempotente desde la 075).
     * Devuelve el id, o null si no se pudo (sin red, demo).
     */
    suspend fun asegurarSesion(): String? {
        arrancarCronometro()
        _dia.value.sesionId?.let { return it }
        if (demo) {
            _sesionIniciada.value = true
            return null
        }
        val diaId = _dia.value.dia.id ?: return null
        val t = token ?: return null
        val semana = this.semana
        val clave = "$diaId|$semana"
        sesionEnVuelo?.let { (c, tarea) -> if (c == clave) return tarea.await() }
        val tarea = alcance.async {
            cliente.llamar(
                "mypump_iniciar_sesion",
                mapOf("p_token" to texto(t), "p_dia_id" to texto(diaId), "p_semana" to numero(semana)),
            ).valorONull()?.comoTexto?.let(Js::verdadero)
        }
        sesionEnVuelo = clave to tarea
        val id = tarea.await()
        if (sesionEnVuelo?.first == clave) sesionEnVuelo = null
        // Si se cambió de día mientras viajaba, no es la sesión del día que se mira.
        if (id != null && _dia.value.dia.id == diaId && _dia.value.semana == semana) {
            mutarDia { it.sesionId = id }
            _sesionIniciada.value = true
            val l = (sesionesLocales[diaId] ?: SesionLocal(semana = semana)).copy(sesionId = id, semana = semana)
            sesionesLocales = sesionesLocales + (diaId to l)
            guardarSesiones()
        }
        return id
    }

    /** La parte sincrónica de `ensureSesionIniciada`: el cronómetro arranca con la primera serie aunque la sesión todavía no exista. */
    internal fun arrancarCronometro() {
        if (_inicioSesion.value != null) return
        _inicioSesion.value = ahoraMs
        guardarInicio()
    }

    /**
     * `restoreSesionDelDia` con el arreglo de la rama `fix/sesion-cache-valida-servidor` (SES-02): la sesión que recuerda
     * el teléfono se CONFIRMA con el servidor. Si el servidor no devuelve esa (archivó el bloque viejo, 070b/071/078), se
     * descarta sin heredar su arranque; sin red se confía en el caché. Lo ya confirmado en el teléfono no se pisa.
     */
    suspend fun restaurarSesion() {
        restauracion += 1
        val seq = restauracion
        mutarDia {
            it.sesionId = null
            it.diaFinalizado = false
        }
        _sesionIniciada.value = false
        _inicioSesion.value = null
        if (demo) return
        val diaId = _dia.value.dia.id ?: return
        val semana = this.semana
        var local = sesionesLocales[diaId]
        // Un caché de otra semana no sirve (ni su arranque).
        if (local != null && local.semana != semana) {
            sesionesLocales = sesionesLocales - diaId
            guardarSesiones()
            local = null
        }
        var inicioGuardado = local?.inicio ?: 0.0
        var cacheValido = local?.sesionId != null
        var remota: ConsultaSesion? = null
        if (cacheValido) {
            val r = consultarSesionDia(diaId, semana)
            if (seq != restauracion) return
            if (r is ConsultaSesion.Respondio) {
                remota = r
                if (r.sesion?.id != local?.sesionId) {
                    cacheValido = false
                    inicioGuardado = 0.0
                }
            }
        }
        if (cacheValido && local != null) {
            mutarDia {
                it.sesionId = local.sesionId
                // El cerrado es LOCAL a propósito: reabrir el día solo borra la marca del teléfono.
                it.diaFinalizado = local.finalizada
            }
            _sesionIniciada.value = true
            if (inicioGuardado > 0) _inicioSesion.value = inicioGuardado
            cargarEstadosYSeries(seq)
            return
        }
        if (local?.sesionId != null) {
            sesionesLocales = sesionesLocales - diaId
            guardarSesiones()
        }
        if (remota == null) {
            remota = consultarSesionDia(diaId, semana)
            if (seq != restauracion) return
        }
        val s = (remota as? ConsultaSesion.Respondio)?.sesion
        val id = s?.let { Js.verdadero(it.id) }
        if (s == null || id == null) {
            // Sin sesión conocida (sin red, o todavía no se pudo crear): lo que está en la cola para este día se pinta igual.
            // Antes las series confirmadas sin señal aparecían vacías y un toque las pisaba (revisión del 14-oct, hallazgo 5).
            aplicarPendientes()
            return
        }
        mutarDia {
            it.sesionId = id
            it.diaFinalizado = s.finalizadaEn != null
        }
        _sesionIniciada.value = true
        if (inicioGuardado > 0) {
            _inicioSesion.value = inicioGuardado
        } else {
            s.iniciadaEn?.let(FechaJs::leer)?.let { _inicioSesion.value = it.toEpochMilli().toDouble() }
        }
        sesionesLocales = sesionesLocales + (diaId to SesionLocal(id, semana, _dia.value.diaFinalizado, _inicioSesion.value))
        guardarSesiones()
        cargarEstadosYSeries(seq)
    }

    internal sealed interface ConsultaSesion {
        /** El servidor contestó: la sesión del día y la semana, o ninguna. */
        data class Respondio(val sesion: Sesion?) : ConsultaSesion

        /** No se le pudo preguntar (sin red o error): la web confía en el caché. */
        data object SinRespuesta : ConsultaSesion
    }

    internal suspend fun consultarSesionDia(diaId: String, semana: Int): ConsultaSesion {
        val t = token ?: return ConsultaSesion.SinRespuesta
        return when (
            val r = cliente.filas(
                "mypump_get_sesion_dia",
                mapOf("p_token" to texto(t), "p_dia_id" to texto(diaId), "p_semana" to numero(semana)),
                Sesion::desde,
            )
        ) {
            is Resultado.Ok -> ConsultaSesion.Respondio(r.valor.firstOrNull())
            is Resultado.Falla -> ConsultaSesion.SinRespuesta
        }
    }

    /**
     * `loadExerciseStates` + `loadRegistrosCarga`, y encima lo que sigue en la cola para este día y esta semana (lo
     * pendiente gana: una serie confirmada sin red no vuelve a aparecer vacía si se cerró la app).
     */
    internal suspend fun cargarEstadosYSeries(seq: Int) {
        val t = token
        val sid = _dia.value.sesionId
        if (t == null || sid == null) {
            aplicarPendientes()
            return
        }
        val p = mapOf("p_token" to texto(t), "p_sesion_id" to texto(sid))
        val (estados, registros) = coroutineScope {
            val e = async { cliente.filas("mypump_get_ejercicios_estado", p, EstadoEjercicio::desde) }
            val r = async { cliente.filas("mypump_get_registros_sesion", p, RegistroSesion::desde) }
            e.await() to r.await()
        }
        if (seq != restauracion || _dia.value.sesionId != sid) return
        estados.valorONull()?.let { f -> mutarDia { it.aplicarEstados(f) } }
        registros.valorONull()?.let { f -> mutarDia { it.aplicarRegistros(f) } }
        aplicarPendientes()
    }

    /**
     * Lo que está en la cola sin mandar para el día y la semana que se miran se pinta encima de lo del servidor: es lo
     * más nuevo (una serie corregida sin red le gana a la que el servidor ya tenía).
     */
    internal suspend fun aplicarPendientes() {
        val ops = outbox?.operaciones() ?: return
        val diaId = _dia.value.dia.id ?: return
        val semana = this.semana
        mutarDia { d ->
            for (op in ops) {
                val p = op.payload
                if (p["diaId"]?.comoTexto != diaId || p["semana"]?.comoNumero != semana.toDouble()) continue
                val datos = p["datos"]
                val ex = datos?.get("ejercicioId")?.comoTexto
                val n = datos?.get("serie")?.comoNumero
                val exId = p["exId"]?.comoTexto
                val status = p["status"]?.comoTexto
                if (op.kind == "carga" && datos != null && ex != null && n != null) {
                    val i = enteroTruncado(n) - 1
                    val e = d.ejercicios[ex] ?: continue
                    if (i < 0 || i >= e.series.size) continue
                    val series = e.series.toMutableList()
                    series[i] = series[i].copy(
                        kg = datos["peso"]?.comoNumero?.let(Js::texto) ?: "",
                        reps = datos["reps"]?.comoNumero?.let(Js::texto) ?: "",
                        rir = datos["rir"]?.comoNumero?.let(Js::texto) ?: "",
                        confirmada = true,
                        nombreRegistrado = datos["ejercicioNombre"]?.comoTexto,
                        varianteRegistrada = datos["notas"]?.comoTexto,
                    )
                    d.ejercicios = d.ejercicios + (ex to e.copy(series = series))
                } else if (op.kind == "estado" && exId != null && status != null) {
                    d.estados = d.estados + (exId to status)
                    d.ejercicios[exId]?.let { e ->
                        d.ejercicios = d.ejercicios + (exId to e.copy(estado = status, completo = status == "completo" || status == "completo_sin_datos"))
                    }
                }
            }
        }
    }

    // ── Cerrar el día (SES-06/07) ──

    enum class ResultadoCierre {
        CERRADO,

        /** "No se pudo guardar la sesión. Revisá tu conexión e intentá de nuevo." */
        SIN_SESION,

        /** "No se pudo cerrar la sesión. Revisá tu conexión e intentá de nuevo." */
        FALLO,

        /** Demo: no se cierra nada. */
        DEMO,
        ;

        val aviso: String?
            get() = when (this) {
                SIN_SESION -> TextosEntreno.CERRAR_SIN_SESION
                FALLO -> TextosEntreno.CERRAR_FALLO
                CERRADO, DEMO -> null
            }
    }

    /**
     * `writeFinish`: PRIMERO vacía la cola (las series tienen que estar en la base antes de cerrar), después
     * `finalizar_sesion` con la duración (null si pasa de 6 h). Un `false` es que no se cerró.
     */
    suspend fun cerrarDia(notas: String): ResultadoCierre {
        val t = token
        if (demo || t == null) return ResultadoCierre.DEMO
        asegurarSesion()
        val sid = _dia.value.sesionId ?: return ResultadoCierre.SIN_SESION
        outbox?.drenar()
        val minutos = TiempoEntreno.minutosSesion(_inicioSesion.value, ahoraMs)
        val nota = Js.trim(notas)
        val r = cliente.llamar(
            "mypump_finalizar_sesion",
            mapOf(
                "p_token" to texto(t), "p_sesion_id" to texto(sid), "p_notas" to (if (nota.isEmpty()) ValorJson.Nulo else texto(nota)),
                "p_duracion_segundos" to (minutos?.let { numero(it * 60) } ?: ValorJson.Nulo),
            ),
        )
        if (r !is Resultado.Ok || r.valor == ValorJson.Booleano(false)) return ResultadoCierre.FALLO
        mutarDia { it.diaFinalizado = true }
        _dia.value.dia.id?.let { d ->
            sesionesLocales = sesionesLocales + (d to (sesionesLocales[d] ?: SesionLocal(semana = semana)).copy(finalizada = true))
            guardarSesiones()
            _diasCompletados.value = _diasCompletados.value + d
        }
        // Las "solo hoy" de OTROS días expiran; las de hoy se conservan por si se reabre para corregir.
        podarSustituciones(conservarDiaActual = true)
        return ResultadoCierre.CERRADO
    }

    // ── Semana nueva y bloque nuevo (ENT-14/15) ──

    sealed interface ResultadoAvance {
        /** Se avanzó: la rutina ya se recargó. */
        data object Listo : ResultadoAvance

        /** No salió: la pregunta de la web ("Sin conexión" / "No se pudo pasar de semana"); "Recargar" es [recargar]. */
        data class Error(val pregunta: Pregunta) : ResultadoAvance
    }

    /**
     * `doAvanzarSemana`: manda la semana DESTINO (`actual + 1`, idempotente; el servidor nunca retrocede, 077), borra los
     * cachés de sesión y recarga.
     */
    suspend fun avanzarSemana(): ResultadoAvance {
        val t = token
        if (t == null || demo) return ResultadoAvance.Error(SemanaEntreno.errorAvanzar(false))
        val r = cliente.llamar("mypump_avanzar_semana", mapOf("p_token" to texto(t), "p_semana_destino" to numero(semana + 1)))
        if (r is Resultado.Ok && r.valor != ValorJson.Nulo) {
            borrarCachesDeSesion()
            recargar()
            return ResultadoAvance.Listo
        }
        return ResultadoAvance.Error(SemanaEntreno.errorAvanzar(sinRed(r)))
    }

    /** `doEmpezarBloqueNuevo`: `activar_siguiente`, y si activó, lo mismo que avanzar. */
    suspend fun empezarBloqueNuevo(): ResultadoAvance {
        val t = token
        if (t == null || demo) return ResultadoAvance.Error(SemanaEntreno.errorBloqueNuevo(false))
        val r = cliente.llamar("mypump_activar_siguiente", mapOf("p_token" to texto(t)))
        if (r is Resultado.Ok && SemanticaJs.esVerdadero(r.valor)) {
            borrarCachesDeSesion()
            recargar()
            return ResultadoAvance.Listo
        }
        return ResultadoAvance.Error(SemanaEntreno.errorBloqueNuevo(sinRed(r)))
    }

    /** Lo que en la web es `location.reload()`: trae la rutina activa y arranca de nuevo. false si no llegó. */
    suspend fun recargar(): Boolean {
        val t = token ?: return false
        val fila = cliente.llamar("mypump_get_rutina_activa", mapOf("p_token" to texto(t))).valorONull()?.primeraFila ?: return false
        val nueva = try {
            RutinaActiva.desde(fila.aJson())
        } catch (_: Exception) {
            return false
        }
        reemplazarRutina(nueva)
        alCambiarRutina?.invoke(nueva)
        cargar()
        return true
    }

    /** Una rutina nueva (la trajo este modelo o [ModeloApp]): todo lo del día se arma de cero. */
    fun reemplazarRutina(nueva: RutinaActiva) {
        historialEnVuelo.values.forEach { it.cancel() }
        historialEnVuelo.clear()
        _historialCargando.value = emptySet()
        generacionHistorial.replaceAll { _, g -> g + 1 }
        restauracion += 1
        _rutina.value = nueva
        val n = NormalizacionRutina.normalizar(nueva.estructura)
        _estructura.value = n.estructura
        _usable.value = n.usable
        _problemas.value = n.problemas
        val semana = if (nueva.semanaActual == 0) 1 else nueva.semanaActual
        val elegido = TextosEntreno.diaSugerido(n.estructura.dias, disco?.let { leerTexto(it, Archivo.dia(nueva.id)) }) ?: Dia(id = "d1")
        val sustituciones = SustitucionesEntreno.compat(leerSustituciones(nueva.id))
        _dia.value = DiaEnCurso(elegido, semana, demo, zona = zona).also { it.sustituciones = sustituciones }
        sustitucionesGuardadas = leerEncoladas(nueva.id) ?: sustituciones
        syncSustituciones = null
        tocadasDuranteSync = null
        _diasCompletados.value = emptySet()
        diaCompletadoMostrado = false
        _inicioSesion.value = null
        _sesionIniciada.value = false
        guardarDiaVisualizado()
    }

    internal fun borrarCachesDeSesion() {
        sesionesLocales = emptyMap()
        disco?.borrar(Archivo.SESIONES)
    }

    /** `loadDiasCompletados`: los días con la sesión de esta semana cerrada. Después se podan las sustituciones. */
    suspend fun cargarDiasCompletados() {
        val t = token
        if (demo || t == null) return
        val filas = cliente.filas("mypump_get_sesiones_semana", mapOf("p_token" to texto(t), "p_semana" to numero(semana)), Sesion::desde)
            .valorONull() ?: return
        _diasCompletados.value = filas.filter { it.finalizadaEn != null }.map { it.diaId }.toSet()
        podarSustituciones()
    }

    // ── Historial por clave (SER-08/09/10) ──

    /** La clave del ejercicio EFECTIVO de un lugar (cualquier día de la rutina): `claveDeSlot`. */
    fun clave(lugar: String): String? {
        val ex = dias.asSequence().flatMap { d -> d.bloques.asSequence().flatMap { it.ejercicios } }.firstOrNull { it.id == lugar } ?: return null
        val nombre = SustitucionesEntreno.aplicada(_dia.value.sustituciones[lugar])?.nombre ?: ex.nombre
        return Js.verdadero(ClaveEjercicio.de(nombre))
    }

    internal sealed interface Historial {
        data class Filas(val filas: List<RegistroHistorico>) : Historial

        /** Falló este pedido (red): queda sin cargar para reintentar. NUNCA se cae al camino por lugar. */
        data object SinRed : Historial
    }

    /**
     * `loadHistorico`: el historial por clave del efectivo (48 filas). Si ya hay uno en vuelo, espera a ese. Con
     * PGRST202 (la 072 no está) cae al camino viejo por lugar, y se recuerda.
     */
    suspend fun pedirHistorial(lugar: String) {
        historialEnVuelo[lugar]?.let {
            it.join()
            return
        }
        if (_dia.value.historial[lugar] != null) return
        val clave = clave(lugar)
        val gen = (generacionHistorial[lugar] ?: 0) + 1
        generacionHistorial[lugar] = gen
        _historialCargando.value = _historialCargando.value + lugar
        val t = alcance.launch {
            val r = traerHistorial(clave, lugar)
            // CARRERA (SER-10): si mientras viajaba se sustituyó o se revirtió, esta respuesta es de OTRO ejercicio.
            if (generacionHistorial[lugar] != gen || clave(lugar) != clave) return@launch
            _historialCargando.value = _historialCargando.value - lugar
            historialEnVuelo.remove(lugar)
            if (r is Historial.Filas) mutarDia { it.historial = it.historial + (lugar to r.filas) }
        }
        historialEnVuelo[lugar] = t
        t.join()
    }

    internal suspend fun traerHistorial(clave: String?, lugar: String): Historial {
        val t = token ?: return Historial.Filas(emptyList())
        if (clave != null && !sinHistorialPorClave) {
            when (val m = porClave(listOf(clave))) {
                is PorClave.Ok -> return Historial.Filas(m.filas[clave] ?: emptyList())
                PorClave.Fallo -> return Historial.SinRed
                PorClave.NoExiste -> {}   // camino viejo
            }
        }
        return when (
            val r = cliente.filas(
                "mypump_get_historico_ejercicio",
                mapOf("p_token" to texto(t), "p_ejercicio_id" to texto(lugar), "p_limit" to numero(48)),
                RegistroHistorico::desde,
            )
        ) {
            is Resultado.Ok -> Historial.Filas(r.valor)
            is Resultado.Falla -> Historial.SinRed
        }
    }

    internal sealed interface PorClave {
        /** La RPC no existe (PGRST202): se recuerda. */
        data object NoExiste : PorClave

        /** Falló (red). */
        data object Fallo : PorClave

        /** Las filas por clave, con TODAS las claves pedidas (vacías si no hay nada). */
        data class Ok(val filas: Map<String, List<RegistroHistorico>>) : PorClave
    }

    /** `getHistoricoPorClave` */
    internal suspend fun porClave(claves: List<String>): PorClave {
        val t = token ?: return PorClave.Fallo
        if (sinHistorialPorClave) return PorClave.NoExiste
        val ks = claves.filter { it.isNotEmpty() }.distinct()
        val m = LinkedHashMap<String, MutableList<RegistroHistorico>>()
        for (k in ks) m[k] = mutableListOf()
        if (ks.isEmpty()) return PorClave.Ok(m)
        return when (
            val r = cliente.filas(
                "mypump_get_historico_por_clave",
                mapOf("p_token" to texto(t), "p_claves" to ValorJson.Lista(ks.map { texto(it) }), "p_limit_por_ej" to numero(48)),
                RegistroHistorico::desde,
            )
        ) {
            is Resultado.Falla -> if (noExiste(r.error)) {
                sinHistorialPorClave = true
                PorClave.NoExiste
            } else {
                PorClave.Fallo
            }
            is Resultado.Ok -> {
                for (f in r.valor) f.clave?.let { c -> m[c]?.add(f) }
                PorClave.Ok(m)
            }
        }
    }

    /**
     * `prefetchHistoricoDia`: UN pedido para todo el día, repartido a los lugares que comparten clave. Si no salió, de a
     * uno (que deja sin cargar lo que falle por red).
     */
    suspend fun precargarHistorial() {
        val d = _dia.value
        val ids = d.lista.filter { it.tipo != "calentamiento" && d.historial[it.id] == null && historialEnVuelo[it.id] == null }.map { it.id }
        if (ids.isEmpty()) return
        val claves = ids.mapNotNull { clave(it) }.distinct()
        val lote = if (claves.isEmpty()) PorClave.Fallo else porClave(claves)
        if (lote !is PorClave.Ok) {
            coroutineScope { for (id in ids) launch { pedirHistorial(id) } }
            return
        }
        mutarDia { dia ->
            for (id in ids) {
                if (historialEnVuelo[id] != null) continue
                val k = clave(id) ?: continue
                val filas = lote.filas[k] ?: continue
                dia.historial = dia.historial + (id to filas)
            }
        }
        val faltan = ids.filter { _dia.value.historial[it] == null }
        coroutineScope { for (id in faltan) launch { pedirHistorial(id) } }
    }

    /** `invalidarHistorico`: el lugar pasó a ser otro ejercicio; lo que había (o venía en camino) es de otro. */
    internal fun invalidarHistorial(lugar: String) {
        mutarDia { it.historial = it.historial - lugar }
        historialEnVuelo.remove(lugar)?.cancel()
        _historialCargando.value = _historialCargando.value - lugar
        generacionHistorial[lugar] = (generacionHistorial[lugar] ?: 0) + 1
    }

    // ── Sustituciones (SER-11..14) ──

    /** Los sustitutos del lugar (mismo patrón y músculo, otro equipo primero, 30), filtrados por la búsqueda del modal. */
    fun sustitutos(lugar: String, busqueda: String = ""): List<SustitutoEjercicio> {
        val ex = _dia.value.ejercicio(lugar) ?: return emptyList()
        return SustitucionesEntreno.filtrar(_catalogo.value.sustitutos(efectivo(ex)), busqueda)
    }

    /** El "🔒 Fijar" arranca como estaba la sustitución previa (al cambiar de sustituto no se pierde). */
    fun fijadaAntes(lugar: String): Boolean = SustitucionesEntreno.aplicada(_dia.value.sustituciones[lugar])?.fijado ?: false

    /** `confirmExSwap`: sin fijar vale solo por hoy. La serie se registra con el nombre del sustituto y el id del lugar. */
    suspend fun sustituir(lugar: String, sub: SustitutoEjercicio, fijar: Boolean) {
        val ex = _dia.value.ejercicio(lugar) ?: return
        val ef = efectivo(ex)
        invalidarHistorial(lugar)
        val ms = ahoraMs
        val previa = _dia.value.sustituciones[lugar]
        ejecutar(
            mutarDia { d ->
                val efectos = d.sustituir(lugar, sub, ef, fijar)
                // SER-14: la hora del cambio (en el servidor gana lo más nuevo), nunca menos que la de lo que reemplaza. Es
                // solo de la nativa: la web no la lee.
                d.sustituciones[lugar]?.let {
                    d.sustituciones = d.sustituciones + (lugar to SustitucionesServidor.conHora(it, SustitucionesServidor.horaDeUnCambio(ms, previa)))
                }
                efectos
            },
        )
    }

    /** "Volver a …" */
    suspend fun revertirSustitucion(lugar: String) {
        invalidarHistorial(lugar)
        ejecutar(mutarDia { it.revertir(lugar) })
    }

    /** `pruneExerciseSwaps` (SER-12): las no fijadas de otra semana o de un día cerrado se van. */
    internal fun podarSustituciones(conservarDiaActual: Boolean = false, sinPrecarga: Boolean = false) {
        val d = _dia.value
        val (quedan, borradas) = SustitucionesEntreno.podar(
            d.sustituciones, semana, _diasCompletados.value, d.dia.id, d.diaFinalizado, conservarDiaActual,
        )
        if (borradas.isEmpty()) return
        mutarDia { it.sustituciones = quedan }
        // SER-14: la poda es solo de este teléfono y no se manda: un teléfono viejo no puede borrar en el servidor lo que el
        // cliente fijó después en otro (lo vencido que quede allá, cada teléfono lo poda al leerlo).
        sustitucionesGuardadas = sustitucionesGuardadas - borradas.toSet()
        for (id in borradas) invalidarHistorial(id)
        guardarSustituciones()
        anotarEncoladas(sustitucionesGuardadas, _rutina.value.id)
        if (!sinPrecarga) alcance.launch { precargarHistorial() }
    }

    /**
     * SER-14: lee el servidor y lo combina con lo del teléfono clave por clave (gana lo más nuevo; ver
     * [SustitucionesServidor.combinar]), y sube lo que el servidor no tiene o tiene más viejo. Sin la tabla en la base
     * (PGRST202), sin red o con el token caído queda lo del teléfono, como antes, y se reintenta al recargar.
     */
    suspend fun sincronizarSustituciones() {
        val t = token
        if (demo || t == null || syncSustituciones != null) return
        val mia = Any()
        syncSustituciones = mia
        tocadasDuranteSync = mutableSetOf()
        try {
            // Lo que ya se cambió tiene que estar en la cola antes de preguntar.
            encoladoSustituciones?.join()
            if (syncSustituciones !== mia) return
            val rutinaId = _rutina.value.id
            // Lo que está en la cola al empezar (la respuesta puede no traerlo aunque se mande en el medio) y lo que quedó
            // en fallidos (nunca llegó): ahí queda lo del teléfono.
            val prefijo = "swap_ej_${rutinaId}_"
            outbox?.let { cola ->
                val enCola = cola.pendientesPorClave().filterKeys { it.startsWith(prefijo) }.values
                val fallidas = cola.fallidos().map { it.op }.filter { (it.dedupeKey ?: "").startsWith(prefijo) }
                for (op in enCola + fallidas) op.payload["exId"]?.comoTexto?.let { tocadasDuranteSync?.add(it) }
            }
            if (syncSustituciones !== mia) return
            val r = cliente.llamar("mypump_get_exercise_swaps", mapOf("p_token" to texto(t), "p_rutina_id" to texto(rutinaId)))
            if (syncSustituciones !== mia || _rutina.value.id != rutinaId) return
            val (vivas, borradasServidor) = (r as? Resultado.Ok)?.valor?.let { SustitucionesServidor.leer(it) } ?: return
            encoladoSustituciones?.join()
            val pendientes = outbox?.pendientesPorClave() ?: emptyMap()
            if (syncSustituciones !== mia || _rutina.value.id != rutinaId) return
            val tocadas = tocadasDuranteSync?.toSet() ?: emptySet()
            val antes = _dia.value.sustituciones
            val combinado = SustitucionesEntreno.compat(
                SustitucionesServidor.combinar(vivas, borradasServidor, antes, pendientes, rutinaId, tocadas),
            )
            // La poda antes de comparar: lo vencido que vuelve del servidor ni se muestra ni pide su historial de nuevo.
            val d = _dia.value
            val (quedan, podadas) = SustitucionesEntreno.podar(combinado, semana, _diasCompletados.value, d.dia.id, d.diaFinalizado, false)
            val cambiadas = (quedan.keys + antes.keys).filter { quedan[it] != antes[it] }
            // Contra lo que tiene el servidor se calcula qué subir. Lo podado no se manda, y lo que ya está en la cola (o se
            // tocó, o quedó en fallidos) no se vuelve a encolar.
            val base = LinkedHashMap(SustitucionesEntreno.compat(vivas))
            for (id in podadas) base.remove(id)
            val yaEncoladas = tocadas + pendientes.keys.filter { it.startsWith(prefijo) }.map { it.removePrefix(prefijo) }
            for (id in yaEncoladas) {
                val q = quedan[id]
                if (q != null) base[id] = q else base.remove(id)
            }
            sustitucionesGuardadas = base
            mutarDia { it.sustituciones = quedan }
            guardarSustituciones()
            anotarEncoladas(sustitucionesGuardadas, rutinaId)
            for (id in cambiadas) invalidarHistorial(id)
            if (cambiadas.isNotEmpty()) precargarHistorial()
        } finally {
            if (syncSustituciones === mia) {
                syncSustituciones = null
                tocadasDuranteSync = null
            }
        }
    }

    // ── Comentarios (SES-08) ──

    /** `loadComentarios`. Si falla, quedan los que había (la web los borraba hasta el próximo intento). */
    suspend fun cargarComentarios() {
        val t = token
        if (demo || t == null) return
        cliente.filas(
            "mypump_get_comentarios",
            mapOf("p_token" to texto(t), "p_ambito" to ValorJson.Nulo, "p_referencia_id" to ValorJson.Nulo),
            Comentario::desde,
        ).valorONull()?.let { _comentarios.value = IndiceComentarios(it) }
    }

    /** `enviarComentarioEjercicio`: va directo (no por la cola). false: avisar `TextosEntreno.COMENTARIO_FALLO`. */
    suspend fun comentar(lugar: String, textoComentario: String): Boolean {
        val contenido = Js.trim(textoComentario)
        val t = token
        if (contenido.isEmpty() || demo || t == null) return false
        val r = cliente.llamar(
            "mypump_agregar_comentario",
            mapOf(
                "p_token" to texto(t), "p_ambito" to texto("ejercicio"), "p_referencia_id" to texto(lugar),
                "p_referencia_nombre" to texto(_dia.value.ejercicio(lugar)?.nombre ?: ""), "p_contenido" to texto(contenido),
            ),
        )
        if (r !is Resultado.Ok || !Outbox.seGuardo(r.valor)) return false
        cargarComentarios()
        return true
    }

    /** `marcarLeidosEjercicio`: optimista (el badge se va ya); la base se avisa sin esperar. */
    suspend fun marcarLeidos(lugar: String) {
        if (_comentarios.value.sinLeer(lugar) <= 0) return
        _comentarios.value = _comentarios.value.marcarLeidos(lugar)
        val t = token
        if (demo || t == null) return
        cliente.llamar(
            "mypump_marcar_leidos_cliente",
            mapOf("p_token" to texto(t), "p_ambito" to texto("ejercicio"), "p_referencia_id" to texto(lugar)),
        )
    }

    // ── Descanso (SES-04) ──

    /** El tick de la barra (cada 250 ms y al volver a primer plano). true la vez que termina: la app suena y vibra. */
    fun tickDescanso(): Boolean {
        var termino = false
        mutarDescanso { termino = it.tick(ahoraMs) }
        guardarDescanso()
        return termino
    }

    /** −15 / +15 */
    fun ajustarDescanso(segundos: Int) {
        mutarDescanso { it.ajustar(segundos.toString(), ahoraMs) }
        guardarDescanso()
    }

    /** "Saltar" */
    fun saltarDescanso() {
        mutarDescanso { it.ajustar("skip", ahoraMs) }
        guardarDescanso()
    }

    /** Al volver a primer plano (GEN-07): el descanso se recalcula contra el reloj y la cola se drena. */
    suspend fun alVolverAPrimerPlano(): Boolean {
        val termino = tickDescanso()
        outbox?.drenar()
        return termino
    }

    // ── Efectos ──

    internal suspend fun ejecutar(efectos: List<DiaEnCurso.Efecto>): DiaCompletado? {
        var completo: DiaCompletado? = null
        for (e in efectos) {
            when (e) {
                is DiaEnCurso.Efecto.Encolar -> outbox?.encolar(e.kind, e.payload, e.clave)
                is DiaEnCurso.Efecto.IniciarDescanso -> {
                    mutarDescanso { it.iniciar(e.segundos, ahoraMs) }
                    guardarDescanso()
                }
                DiaEnCurso.Efecto.DetenerDescanso -> {
                    mutarDescanso { it.detener() }
                    guardarDescanso()
                }
                DiaEnCurso.Efecto.AsegurarSesion -> {
                    arrancarCronometro()
                    alcance.launch { asegurarSesion() }
                }
                is DiaEnCurso.Efecto.PedirHistorial -> pedirHistorial(e.lugar)
                is DiaEnCurso.Efecto.MarcarLeidos -> alcance.launch { marcarLeidos(e.lugar) }
                DiaEnCurso.Efecto.GuardarSustituciones -> guardarSustituciones()
                DiaEnCurso.Efecto.ReabrioDia -> {
                    val d = _dia.value.dia.id
                    val l = d?.let { sesionesLocales[it] }
                    if (d != null && l != null) {
                        sesionesLocales = sesionesLocales + (d to l.copy(finalizada = false))
                        guardarSesiones()
                    }
                }
                DiaEnCurso.Efecto.DiaCompleto -> if (!diaCompletadoMostrado) {
                    diaCompletadoMostrado = true
                    val (p, sig) = SemanaEntreno.preguntaDiaCompletado(dias, _dia.value.dia.id)
                    completo = DiaCompletado(p, sig)
                }
            }
        }
        return completo
    }

    // ── Lo que vive en el teléfono ──

    /** Lo que la web guardaba en `mypump_sesion_<TOKEN>_<dia>{,_semana,_finalizada,_start}`. */
    data class SesionLocal(
        val sesionId: String? = null,
        val semana: Int?,
        val finalizada: Boolean = false,
        /** `_start` (ms). */
        val inicio: Double? = null,
    ) {
        fun aValor(): ValorJson = ValorJson.Objeto(
            buildMap {
                sesionId?.let { put("sesionId", texto(it)) }
                semana?.let { put("semana", numero(it)) }
                put("finalizada", ValorJson.Booleano(finalizada))
                inicio?.let { put("inicio", numero(it)) }
            },
        )

        companion object {
            fun desde(v: ValorJson): SesionLocal = SesionLocal(
                sesionId = v["sesionId"]?.comoTexto,
                semana = v["semana"]?.comoNumero?.let(::enteroTruncado),
                finalizada = (v["finalizada"] as? ValorJson.Booleano)?.valor ?: false,
                inicio = v["inicio"]?.comoNumero,
            )
        }
    }

    object Archivo {
        const val SESIONES = "entreno-sesiones.json"
        const val DESCANSO = "entreno-descanso.json"
        const val LEGADO = "legado-entreno.json"
        fun dia(rutinaId: String): String = "entreno-dia_$rutinaId.json"
        fun sustituciones(rutinaId: String): String = "ejercicios-swaps_$rutinaId.json"
    }

    internal val ahoraMs: Double get() = reloj().toEpochMilli().toDouble()

    private inline fun <T> mutarDia(f: (DiaEnCurso) -> T): T {
        val d = _dia.value.copia()
        val r = f(d)
        _dia.value = d
        return r
    }

    private inline fun mutarDescanso(f: (BarraDescanso) -> Unit) {
        val b = _descanso.value.copia()
        f(b)
        _descanso.value = b
    }

    internal val discoDeLaCuenta: Disco? get() = disco

    /** Lo que trae la migración del almacenamiento viejo pasa por acá (ver [LegadoEntreno]). */
    internal fun ponerSesionLocal(diaId: String, l: SesionLocal) {
        sesionesLocales = sesionesLocales + (diaId to l)
    }

    internal fun tieneSesionLocal(diaId: String): Boolean = sesionesLocales.containsKey(diaId)

    internal fun reemplazarDescanso(b: BarraDescanso) {
        _descanso.value = b
    }

    internal fun ponerSustituciones(m: Map<String, ValorJson>) {
        mutarDia { it.sustituciones = m }
    }

    internal var diaGuardadoAlArrancar: Boolean
        get() = habiaDiaGuardado
        set(v) {
            habiaDiaGuardado = v
        }

    internal fun guardarDiaVisualizado() {
        val id = _dia.value.dia.id ?: return
        disco?.guardar(Archivo.dia(_rutina.value.id), texto(id))
    }

    internal fun guardarSustituciones() {
        disco?.guardar(Archivo.sustituciones(_rutina.value.id), ValorJson.Objeto(_dia.value.sustituciones))
        encolarSustituciones()
    }

    /**
     * SER-14: lo que cambió desde la última escritura sale por la cola, en orden (sin la tabla en la base, la cola lo da por
     * hecho y queda solo en el teléfono, como antes).
     */
    private fun encolarSustituciones() {
        val ahora = _dia.value.sustituciones
        val ops = SustitucionesServidor.operaciones(sustitucionesGuardadas, ahora, _rutina.value.id)
        sustitucionesGuardadas = ahora
        val cola = outbox
        if (demo || token == null || cola == null || ops.isEmpty()) return
        tocadasDuranteSync?.addAll(ops.map { it.exId })
        val anterior = encoladoSustituciones
        val rutinaId = _rutina.value.id
        encoladoSustituciones = alcance.launch {
            anterior?.join()
            for (op in ops) cola.encolar(op.kind, op.payload, op.clave)
            disco?.guardar(SustitucionesServidor.archivoEncoladas(rutinaId), ValorJson.Objeto(ahora))
        }
    }

    /** Anota en disco que `m` ya está en la cola (o en el servidor), detrás de los encolados en curso. */
    private fun anotarEncoladas(m: Map<String, ValorJson>, rutinaId: String) {
        val anterior = encoladoSustituciones
        encoladoSustituciones = alcance.launch {
            anterior?.join()
            disco?.guardar(SustitucionesServidor.archivoEncoladas(rutinaId), ValorJson.Objeto(m))
        }
    }

    private fun leerEncoladas(rutinaId: String): Map<String, ValorJson>? =
        (disco?.leer(SustitucionesServidor.archivoEncoladas(rutinaId)) as? JsonObject)?.mapValues { ValorJson.desde(it.value) }

    internal fun guardarSesiones() {
        disco?.guardar(Archivo.SESIONES, ValorJson.Objeto(sesionesLocales.mapValues { it.value.aValor() }))
    }

    private fun guardarInicio() {
        val d = _dia.value.dia.id ?: return
        val l = sesionesLocales[d] ?: SesionLocal(semana = semana)
        sesionesLocales = sesionesLocales + (d to l.copy(inicio = _inicioSesion.value, semana = l.semana ?: semana))
        guardarSesiones()
    }

    internal fun guardarDescanso() {
        val g = _descanso.value.guardado
        if (g == descansoEnDisco) return
        descansoEnDisco = g
        if (g != null) disco?.guardar(Archivo.DESCANSO, g.aValor()) else disco?.borrar(Archivo.DESCANSO)
    }

    private fun leerSustituciones(rutinaId: String): Map<String, ValorJson> =
        (disco?.leer(Archivo.sustituciones(rutinaId)) as? JsonObject)?.mapValues { ValorJson.desde(it.value) } ?: emptyMap()

    companion object {
        internal fun sinRed(r: Resultado<*>): Boolean = (r as? Resultado.Falla)?.error?.clase?.let { it != ErrorRpc.Clase.PERMANENTE } ?: false

        private val NO_EXISTE = Regex("PGRST202|could not find the function|does not exist", RegexOption.IGNORE_CASE)

        internal fun noExiste(e: ErrorRpc): Boolean = e.funcionInexistente || NO_EXISTE.containsMatchIn(e.mensaje)

        private fun leerSesiones(d: Disco): Map<String, SesionLocal> =
            (d.leer(Archivo.SESIONES) as? JsonObject)?.mapValues { SesionLocal.desde(ValorJson.desde(it.value)) } ?: emptyMap()

        private fun leerTexto(d: Disco, nombre: String): String? = (d.leer(nombre) as? JsonPrimitive)?.takeIf { it.isString }?.content
    }
}

/**
 * `Int(x)` que trunca hacia el cero sin riesgo (`enteroTruncado` de iOS): NaN o infinito valen 0 y lo de más de ±10^15 se
 * acota. Para lo que se lee de la cola o del almacenamiento viejo.
 */
internal fun enteroTruncado(d: Double): Int {
    if (!d.isFinite()) return 0
    val t = maxOf(-1e15, minOf(1e15, d))
    return if (t >= Int.MAX_VALUE) Int.MAX_VALUE else if (t <= Int.MIN_VALUE) Int.MIN_VALUE else t.toInt()
}
