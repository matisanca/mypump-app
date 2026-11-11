package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.Presion
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlin.math.floor
import kotlin.math.roundToLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex

// ── Lo que devuelve `mypump_presion_get` (todo opcional: un campo que falta o que no se entiende vale lo de fábrica) ──

data class SeriePresion(
    val id: String?,
    val motivo: String?,
    /** "estandar" o "bajo_efecto". */
    val tipo: String,
    val estado: String?,
    val tomasObjetivo: Int,
    val fechaInicio: String?,
    val fechaLimite: String?,
    val brazo: String?,
    /** null, "acostado_parado" o "sentado_parado": falta hacerla. */
    val ortostatica: String?,
    val compararBrazos: Boolean,
    val medidaPedida: Boolean,
    val dias: List<String>,
    val faltan: Int,
) {
    companion object {
        fun desde(j: ValorJson?): SeriePresion? {
            if (j !is ValorJson.Objeto) return null
            val objetivo = j["tomas_objetivo"]?.comoNumero?.takeIf { it >= 1 && it <= 30 }?.toInt() ?: 3
            val dias = (j["dias"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList()
            return SeriePresion(
                id = j["id"]?.comoTexto, motivo = j["motivo"]?.comoTexto, tipo = if (j["tipo"]?.comoTexto == "bajo_efecto") "bajo_efecto" else "estandar",
                estado = j["estado"]?.comoTexto, tomasObjetivo = objetivo, fechaInicio = j["fecha_inicio"]?.comoTexto, fechaLimite = j["fecha_limite"]?.comoTexto,
                brazo = j["brazo"]?.comoTexto, ortostatica = j["ortostatica"]?.comoTexto?.takeIf { it == "acostado_parado" || it == "sentado_parado" },
                compararBrazos = j["comparar_brazos"] == ValorJson.Booleano(true), medidaPedida = j["medida_pedida"] == ValorJson.Booleano(true), dias = dias,
                faltan = j["faltan"]?.comoNumero?.takeIf { it >= 0 && it <= 30 }?.toInt() ?: maxOf(0, objetivo - dias.size),
            )
        }
    }
}

/** Una sesión ya guardada, tal como la anotó el alumno. */
data class SesionPresion(val id: String, val serieId: String?, val fecha: String, val tipo: String, val cuenta: Boolean?, val tomas: List<Presion.Toma>) {
    companion object {
        fun desde(j: ValorJson): SesionPresion? {
            val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            return SesionPresion(
                id, j["serie_id"]?.comoTexto, j["fecha"]?.comoTexto ?: "", j["tipo"]?.comoTexto ?: "estandar", (j["cuenta"] as? ValorJson.Booleano)?.valor,
                (j["tomas"] as? ValorJson.Lista)?.elementos?.mapNotNull(Presion.Toma::desde)?.sortedBy { it.orden } ?: emptyList(),
            )
        }
    }
}

data class PendientePresion(
    val sesionId: String,
    /** "alta" o "urgencia". */
    val nivel: String,
    val desde: String?,
) {
    companion object {
        fun desde(j: ValorJson?): PendientePresion? {
            val s = j?.get("sesion_id")?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
            return PendientePresion(s, if (j["nivel"]?.comoTexto == "urgencia") "urgencia" else "alta", j["desde"]?.comoTexto)
        }
    }
}

data class TensiometroPresion(val nombre: String, val codigo: String?, val pais: String?, val nota: String?)

/** La lista de aparatos que sirven, por tramo. null hasta que el equipo la verifique: sin ella no se muestra «Ver cuáles sirven». */
data class TensiometrosPresion(val version: String?, val tramos: Map<String, List<TensiometroPresion>>) {
    companion object {
        fun desde(j: ValorJson?): TensiometrosPresion? {
            val t = (j?.get("tramos") as? ValorJson.Objeto)?.campos ?: return null
            val version = j["version"]?.comoTexto ?: j["version"]?.comoNumero?.let { it.toLong().toString() }
            return TensiometrosPresion(
                version,
                t.mapValues { (_, v) ->
                    (v as? ValorJson.Lista)?.elementos?.mapNotNull { a ->
                        val n = a["nombre"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                        TensiometroPresion(n, a["codigo"]?.comoTexto, a["pais"]?.comoTexto, a["nota"]?.comoTexto)
                    } ?: emptyList()
                },
            )
        }
    }
}

/** `mypump_presion_get` con la sección habilitada. Si no vino `habilitado: true`, null: no se muestra nada. */
data class EstadoPresion(
    val fotos: Boolean,
    val hoy: String?,
    val aparato: Presion.Aparato?,
    val circunferenciaBrazoCm: Double?,
    val serie: SeriePresion?,
    /** Las últimas, la más nueva primero. */
    val sesiones: List<SesionPresion>,
    val pendiente: PendientePresion?,
    val tensiometros: TensiometrosPresion?,
) {
    companion object {
        fun desde(j: ValorJson): EstadoPresion? {
            if (j["habilitado"] != ValorJson.Booleano(true)) return null
            return EstadoPresion(
                fotos = j["fotos"] == ValorJson.Booleano(true), hoy = j["hoy"]?.comoTexto, aparato = Presion.Aparato.desde(j["aparato"]),
                circunferenciaBrazoCm = j["circunferencia_brazo_cm"]?.comoNumero?.takeIf { it > 0 && it.isFinite() }, serie = SeriePresion.desde(j["serie"]),
                sesiones = (j["sesiones"] as? ValorJson.Lista)?.elementos?.mapNotNull(SesionPresion::desde) ?: emptyList(),
                pendiente = PendientePresion.desde(j["pendiente"]), tensiometros = TensiometrosPresion.desde(j["tensiometros"]),
            )
        }
    }
}

// ── Lo que vive en el teléfono ──

private fun texto(s: String?): ValorJson = s?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo
private fun bool(b: Boolean?): ValorJson = b?.let { ValorJson.Booleano(it) } ?: ValorJson.Nulo
private fun num(n: Number?): ValorJson = n?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo

/** El botón «Marcar un síntoma» y la lista del recordatorio (`mypump_presion_sintoma`). */
data class SintomaPresion(
    val id: String,
    val marcadoEn: String,
    val zonaHoraria: String,
    /** "boton" o "recordatorio_180_120". */
    val contexto: String,
    val sesionId: String?,
    val codigos: List<String>,
    val sinSintomasEnLista: Boolean?,
    val nota: String?,
) {
    /** Lo que viaja (y lo que se guarda en la cola). */
    fun aValor(): ValorJson = ValorJson.objeto(
        "id" to ValorJson.Texto(id), "marcado_en" to ValorJson.Texto(marcadoEn), "zona_horaria" to ValorJson.Texto(zonaHoraria), "contexto" to ValorJson.Texto(contexto),
        "sesion_id" to texto(sesionId), "codigos" to ValorJson.Lista(codigos.map { ValorJson.Texto(it) }), "sin_sintomas_en_lista" to bool(sinSintomasEnLista),
        "nota" to texto(nota),
    )

    companion object {
        fun desde(j: ValorJson?): SintomaPresion? {
            val id = j?.get("id")?.comoTexto ?: return null
            return SintomaPresion(
                id, j["marcado_en"]?.comoTexto ?: "", j["zona_horaria"]?.comoTexto ?: "", j["contexto"]?.comoTexto ?: "boton", j["sesion_id"]?.comoTexto,
                (j["codigos"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList(), (j["sin_sintomas_en_lista"] as? ValorJson.Booleano)?.valor,
                j["nota"]?.comoTexto,
            )
        }
    }
}

/** Un envío de la cola: una sesión entera (la última versión) o un síntoma. */
data class EnvioPresion(
    val sesion: Presion.Sesion? = null,
    val textoAlumno: String? = null,
    val sintoma: SintomaPresion? = null,
    /** La repetición retomada sin los datos previos: `previo` viaja en null y el servidor conserva lo que tenía. */
    val sinPrevio: Boolean = false,
    /** Cuándo entró a la cola (ms): pasados 30 días sin poder salir, se descarta. */
    val creadoMs: Long = 0,
) {
    val id: String get() = sesion?.id ?: sintoma?.id ?: ""

    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            sesion?.let { put("sesion", it.aValor()) }
            textoAlumno?.let { put("textoAlumno", ValorJson.Texto(it)) }
            sintoma?.let { put("sintoma", it.aValor()) }
            if (sinPrevio) put("sinPrevio", ValorJson.Booleano(true))
            put("creadoMs", num(creadoMs))
        },
    )

    companion object {
        fun desde(j: ValorJson): EnvioPresion? {
            val s = (j["sesion"] as? ValorJson.Objeto)?.let(Presion.Sesion::desde)
            val x = SintomaPresion.desde(j["sintoma"])
            if (s == null && x == null) return null
            return EnvioPresion(s, j["textoAlumno"]?.comoTexto, x, j["sinPrevio"] == ValorJson.Booleano(true), j["creadoMs"]?.comoNumero?.toLong() ?: 0)
        }
    }
}

/** La sesión que se está haciendo, con su temporizador: sobrevive a cerrar la app para poder retomar la repetición. */
data class EnCursoPresion(
    val sesion: Presion.Sesion,
    /** En qué pantalla quedó. La app pone los nombres. */
    val etapa: String,
    /** Índice en `Presion.pasos` (ortostática y comparación de brazos). */
    val paso: Int = 0,
    /** La hora (ms) en que termina el temporizador que corre. Se guarda la hora, no los segundos que faltan. */
    val finTemporizador: Long? = null,
    val ultimaTomaEn: Long? = null,
    /** Las respuestas de la lista de alarma de la espera, por código. Lo que no está, no se contestó. */
    val lista: Map<String, Boolean> = emptyMap(),
    /** Día local en que empezó: al otro día ya no se retoma. */
    val dia: String,
    /** La variante de la ortostática ("acostado_parado" o "sentado_parado"): la serie deja de traerla cuando se guarda la primera toma. */
    val variante: String? = null,
    /** Retomada de lo que pide el servidor: las preguntas previas no se saben. */
    val retomada: Boolean = false,
) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "sesion" to sesion.aValor(), "etapa" to ValorJson.Texto(etapa), "paso" to num(paso), "finTemporizador" to num(finTemporizador), "ultimaTomaEn" to num(ultimaTomaEn),
        "lista" to ValorJson.Objeto(lista.mapValues { ValorJson.Booleano(it.value) }), "dia" to ValorJson.Texto(dia), "variante" to texto(variante),
        "retomada" to ValorJson.Booleano(retomada),
    )

    companion object {
        fun desde(j: ValorJson?): EnCursoPresion? {
            val s = (j?.get("sesion") as? ValorJson.Objeto)?.let(Presion.Sesion::desde) ?: return null
            return EnCursoPresion(
                s, j["etapa"]?.comoTexto ?: return null, j["paso"]?.comoNumero?.toInt() ?: 0, j["finTemporizador"]?.comoNumero?.toLong(), j["ultimaTomaEn"]?.comoNumero?.toLong(),
                (j["lista"] as? ValorJson.Objeto)?.campos?.mapNotNull { (k, v) -> (v as? ValorJson.Booleano)?.let { k to it.valor } }?.toMap() ?: emptyMap(),
                j["dia"]?.comoTexto ?: "", j["variante"]?.comoTexto, j["retomada"] == ValorJson.Booleano(true),
            )
        }
    }
}

data class ColaPresion(val envios: List<EnvioPresion> = emptyList(), val enCurso: EnCursoPresion? = null) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("envios", ValorJson.Lista(envios.map { it.aValor() }))
            enCurso?.let { put("enCurso", it.aValor()) }
        },
    )

    companion object {
        const val ARCHIVO = "presion-cola.json"

        fun leer(disco: Disco): ColaPresion {
            val v = disco.leer(ARCHIVO)?.let { ValorJson.desde(it) } ?: return ColaPresion()
            return ColaPresion((v["envios"] as? ValorJson.Lista)?.elementos?.mapNotNull(EnvioPresion::desde) ?: emptyList(), EnCursoPresion.desde(v["enCurso"]))
        }
    }
}

/**
 * Presión arterial. Las sesiones y los síntomas se guardan primero en el teléfono y se mandan en orden: sin red, con un 5xx o un
 * 429 quedan y se reintentan (al volver al frente y al abrir la pantalla); un 4xx que no sea 429, o `ok: false`, se descarta y se
 * refresca el estado. Un 404 o PGRST202 no borra la cola: se conserva 30 días. El texto de guardia lo decide
 * `Presion.evaluarSesion` acá, sin esperar al servidor. Con la palanca `presion_app` apagada [ModeloApp] no llama a nada de esto:
 * [estado] queda en null y no se ve ni se pide nada. Gemelo de ModeloPresion.swift.
 *
 * Nada de esta clase toca Entreno ni la rutina: la presión nunca frena el entrenamiento.
 */
class ModeloPresion(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    private val ahora: () -> Instant = { Instant.now() },
    private val version: () -> String = { "" },
    private val lanzar: (suspend () -> Unit) -> Unit = {},
) {
    enum class Salida { OK, SIN_SENAL, ERROR }

    private val _estado = MutableStateFlow<EstadoPresion?>(null)
    /** null: apagado, sin el servidor nuevo, o sin red y sin nada guardado. No se muestra nada. */
    val estado: StateFlow<EstadoPresion?> = _estado.asStateFlow()
    private val _local = MutableStateFlow(disco?.let { ColaPresion.leer(it) } ?: ColaPresion())
    /** La cola y la sesión en curso, para que la pantalla se entere de los cambios. */
    val local: StateFlow<ColaPresion> = _local.asStateFlow()

    private val drenando = Mutex()
    @Volatile private var apagado = false
    /** Se cerró sesión: no se vuelve a pedir, mostrar, mandar ni guardar el estado de esta cuenta. */
    @Volatile private var cerrada = false

    init {
        var c = _local.value
        // La repetición se retoma el mismo día: al otro día el servidor ya no la pide.
        if (c.enCurso?.let { it.dia != FechaLocal.hoy(ahora()) } == true) c = c.copy(enCurso = null)
        // Lo que no pudo salir en 30 días ya no sale.
        val limite = ahora().toEpochMilli() - DIAS_EN_COLA * 86_400_000L
        if (c.envios.any { it.creadoMs in 1 until limite }) c = c.copy(envios = c.envios.filter { it.creadoMs !in 1 until limite })
        if (c != _local.value) {
            _local.value = c
            guardar()
        }
    }

    /** La palanca `presion_app` que se leyó por última vez: prendida, una toma en la cola sigue saliendo aunque se arranque sin red. */
    val palancaRecordada: Boolean get() = disco?.leer(ARCHIVO_PALANCA)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true)

    fun recordarPalanca(prendida: Boolean) {
        if (prendida != palancaRecordada) disco?.guardar(ARCHIVO_PALANCA, ValorJson.Booleano(prendida))
    }

    // ── Lo que lee la pantalla ──

    val habilitado: Boolean get() = _estado.value != null
    val enCurso: EnCursoPresion? get() = _local.value.enCurso
    /** Cuántos envíos esperan señal. */
    val enCola: Int get() = _local.value.envios.size
    val hoy: String get() = _estado.value?.hoy ?: FechaLocal.hoy(ahora())
    /** Esa sesión tiene una versión que todavía no salió: lo que diga el servidor de ella puede estar viejo. */
    fun esperaSalir(sesionId: String): Boolean = _local.value.envios.any { it.sesion?.id == sesionId }

    /**
     * La serie con lo que todavía no confirmó el servidor: una toma en la cola que cuenta ya suma su día, y la comparación de
     * brazos o la ortostática en la cola ya no se vuelven a pedir.
     */
    val serieVista: SeriePresion?
        get() {
            var s = _estado.value?.serie ?: return null
            val base = s.dias.size
            for (envio in _local.value.envios) {
                val c = envio.sesion ?: continue
                if (c.serieId == null || c.serieId != s.id) continue
                if (c.tipo == "comparacion_brazos" && c.tomas.size >= 4) s = s.copy(compararBrazos = false)
                if (c.tipo == "ortostatica" && c.tomas.size >= 3) s = s.copy(ortostatica = null)
                if ((c.tipo != "estandar" && c.tipo != "bajo_efecto") || envio.sinPrevio) continue
                val dia = c.inicio?.let { runCatching { FechaLocal.hoy(Instant.parse(it)) }.getOrNull() } ?: continue
                if (dia in s.dias || s.dias.size >= s.tomasObjetivo) continue
                val ev = Presion.evaluarSesion(c)
                if (if (s.tipo == "bajo_efecto") ev.validaBajoEfecto else ev.cuenta) s = s.copy(dias = s.dias + dia)
            }
            return s.copy(faltan = maxOf(0, s.faltan - (s.dias.size - base)))
        }

    /** La de hoy ya está hecha (con lo que espera en la cola). */
    val hoyListo: Boolean get() = serieVista?.dias?.contains(hoy) == true

    /** La repetición que falta: la del teléfono si quedó a medias, o la que pide el servidor (salvo que ya esté saliendo de la cola). */
    val pendiente: PendientePresion?
        get() {
            val e = _local.value.enCurso
            val id = e?.sesion?.id
            if (e != null && id != null && e.sesion.tomas.isNotEmpty() && e.sesion.tipo != "ortostatica" && e.sesion.tipo != "comparacion_brazos") {
                val ev = evaluar()
                if (ev != null && (ev.paso == Presion.Paso.REPETIR || ev.paso == Presion.Paso.REPETIR_CON_LISTA)) {
                    return PendientePresion(id, if (ev.paso == Presion.Paso.REPETIR_CON_LISTA) "urgencia" else "alta", e.sesion.inicio)
                }
            }
            return _estado.value?.pendiente?.takeIf { !esperaSalir(it.sesionId) }
        }

    /** La tarjeta de arriba en la primera pestaña (CONTRATO_APP.md). Es una tarjeta más: no frena ni condiciona la rutina. */
    sealed interface Tarjeta {
        /** Quedó una repetición sin hacer. */
        data object Repetir : Tarjeta
        /** Serie abierta y falta el aparato, o medir el brazo para esta serie. */
        data object Preparar : Tarjeta
        /** Serie abierta y sin toma válida hoy. */
        data class Toma(val hechas: Int, val total: Int, val faltan: Int) : Tarjeta
        /** Serie abierta y la de hoy hecha. */
        data class HoyListo(val hechas: Int, val total: Int) : Tarjeta
    }

    /** null: no hay tarjeta. */
    val tarjeta: Tarjeta?
        get() {
            val e = _estado.value ?: return null
            if (pendiente != null) return Tarjeta.Repetir
            val s = serieVista ?: return null
            val hechas = minOf(s.tomasObjetivo, maxOf(0, s.tomasObjetivo - s.faltan))
            if (e.aparato == null || !Presion.metodo(e.circunferenciaBrazoCm, e.aparato).admiteTomas || s.medidaPedida) return Tarjeta.Preparar
            if (hoy in s.dias) return Tarjeta.HoyListo(hechas, s.tomasObjetivo)
            if (s.faltan <= 0) return null
            return Tarjeta.Toma(hechas, s.tomasObjetivo, s.faltan)
        }

    /** Las tomas de una sesión guardada, para retomar una repetición que pide el servidor. */
    fun sesionGuardada(id: String): SesionPresion? = _estado.value?.sesiones?.firstOrNull { it.id == id }

    // ── Servidor ──

    private val zona: String get() = ZoneId.systemDefault().id

    suspend fun refrescar() {
        if (cerrada) return
        val r = cliente.llamar("mypump_presion_get", mapOf("p_token" to ValorJson.Texto(token), "p_zona" to ValorJson.Texto(zona)))
        if (cerrada) return
        when (r) {
            is Resultado.Ok -> if (r.valor == ValorJson.Nulo) _estado.value = null else aplicar(r.valor)
            is Resultado.Falla -> {
                if (r.error.funcionInexistente || r.error.status == 404 || r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                } else if (_estado.value == null && !apagado) {
                    // Sin red, lo último que se supo: los pasos y la cola siguen vivos.
                    disco?.leer(ARCHIVO_ESTADO)?.let { EstadoPresion.desde(ValorJson.desde(it)) }?.let { _estado.value = it }
                }
            }
        }
    }

    /** El estado que devuelve el servidor (en `get` y en cada escritura). */
    private fun aplicar(j: ValorJson) {
        if (cerrada) return
        val e = EstadoPresion.desde(j)
        if (e == null) {
            apagar()
            disco?.borrar(ARCHIVO_ESTADO)
            return
        }
        apagado = false
        _estado.value = e
        disco?.guardar(ARCHIVO_ESTADO, j)
    }

    fun apagar() {
        _estado.value = null
        apagado = true
    }

    /**
     * Cerrar sesión, con el mismo criterio que el outbox: lo que se ve (el estado del servidor, la sesión en curso con su
     * temporizador) se borra del teléfono; lo anotado que todavía no salió queda en `presion-cola.json` de la carpeta de esa
     * cuenta y sale al volver a entrar con el mismo link. Con otro link es otra carpeta: no se ve ni se manda. Una pasada en
     * curso se corta en el próximo paso. Gemelo de `olvidarAlSalir` en ModeloPresion.swift.
     */
    fun olvidarAlSalir() {
        cerrada = true
        apagar()
        _local.update { it.copy(enCurso = null) }
        guardar()
        disco?.borrar(ARCHIVO_ESTADO)
    }

    private suspend fun escribir(funcion: String, parametros: Map<String, ValorJson>): Salida {
        if (_estado.value == null) return Salida.ERROR
        return when (val r = cliente.llamar(funcion, parametros + ("p_token" to ValorJson.Texto(token)))) {
            is Resultado.Ok -> {
                if (r.valor["ok"] != ValorJson.Booleano(true)) return Salida.ERROR
                val e = r.valor["estado"]
                if (e != null && e != ValorJson.Nulo) aplicar(e) else refrescar()
                Salida.OK
            }
            is Resultado.Falla -> when {
                r.error.funcionInexistente -> {
                    apagar()
                    Salida.ERROR
                }
                r.error.clase == ErrorRpc.Clase.PERMANENTE -> Salida.ERROR
                else -> Salida.SIN_SENAL
            }
        }
    }

    /** Cambiar aparato o manguito crea uno nuevo en el servidor (el anterior queda inactivo). */
    suspend fun guardarAparato(a: Presion.Aparato): Salida {
        fun t(s: String?): ValorJson = s?.trim()?.takeIf { it.isNotEmpty() }?.let { ValorJson.Texto(it.take(80)) } ?: ValorJson.Nulo
        return escribir(
            "mypump_presion_aparato",
            mapOf(
                "p_aparato" to ValorJson.objeto(
                    "tipo" to t(a.tipo), "marca" to t(a.marca), "modelo" to t(a.modelo), "modelo_codigo" to t(a.modeloCodigo),
                    "manguito_min_cm" to num(a.manguitoMinCm), "manguito_max_cm" to num(a.manguitoMaxCm),
                ),
            ),
        )
    }

    /** La medida del brazo, de 20 a 70 cm con un decimal. */
    suspend fun guardarMedida(cm: Double): Salida {
        if (!(cm >= 20 && cm <= 70)) return Salida.ERROR
        return escribir("mypump_presion_medida", mapOf("p_cm" to ValorJson.Numero((cm * 10).roundToLong() / 10.0), "p_zona" to ValorJson.Texto(zona)))
    }

    // ── La sesión en curso ──

    private fun sello(d: Instant): String = d.truncatedTo(ChronoUnit.SECONDS).toString()

    /** Empieza una sesión nueva con su id. No manda nada hasta la primera toma. */
    fun empezar(tipo: String, serieId: String?, brazo: String?, etapa: String, variante: String? = null): EnCursoPresion {
        val s = Presion.Sesion(id = UUID.randomUUID().toString(), serieId = serieId, tipo = tipo, inicio = sello(ahora()), zonaHoraria = zona, brazo = brazo ?: "izq")
        val e = EnCursoPresion(sesion = s, etapa = etapa, dia = FechaLocal.hoy(ahora()), variante = variante)
        _local.update { it.copy(enCurso = e) }
        guardar()
        return e
    }

    /**
     * Retoma la repetición que pide el servidor (`pendiente`) cuando el teléfono no tiene la sesión: con las tomas que ya están
     * guardadas, para que la regla vea las dos. Lo que no viene en `sesiones` (las preguntas previas, el reposo) queda sin dato.
     * Si la sesión no está entre las guardadas se refresca antes de dejar anotar: sin sus tomas la nueva saldría con orden 1 y el
     * servidor la ignoraría. Si sigue sin estar, devuelve null y la pantalla empieza una toma nueva normal.
     */
    suspend fun retomar(p: PendientePresion, etapa: String): EnCursoPresion? {
        enCurso?.let { if (it.sesion.id == p.sesionId) return it }
        if (sesionGuardada(p.sesionId) == null) refrescar()
        val g = sesionGuardada(p.sesionId) ?: return null
        val s = Presion.Sesion(
            id = p.sesionId, serieId = g.serieId, tipo = g.tipo ?: "suelta", inicio = p.desde, zonaHoraria = zona,
            brazo = g.tomas.firstOrNull()?.brazo ?: _estado.value?.serie?.brazo ?: "izq", tomas = g.tomas,
        )
        val e = EnCursoPresion(sesion = s, etapa = etapa, dia = FechaLocal.hoy(ahora()), retomada = true)
        _local.update { it.copy(enCurso = e) }
        guardar()
        return e
    }

    /** Cambia lo que haga falta de la sesión en curso (la etapa, el temporizador, las respuestas) y lo deja en disco. */
    fun cambiar(f: (EnCursoPresion) -> EnCursoPresion) {
        val e = enCurso ?: return
        _local.update { it.copy(enCurso = f(e)) }
        guardar()
    }

    /** Minutos desde la última toma: lo que mira la regla para el recordatorio. */
    private fun conMinutos(e: EnCursoPresion): Presion.Sesion =
        e.sesion.copy(minutosDesdeUltima = e.ultimaTomaEn?.let { floor(maxOf(0.0, (ahora().toEpochMilli() - it) / 60_000.0)) } ?: 0.0)

    /** Qué toca ahora, con lo anotado hasta acá. null sin sesión en curso. */
    fun evaluar(): Presion.Evaluacion? = enCurso?.let { Presion.evaluarSesion(conMinutos(it)) }

    /** Anota una toma ya validada, la deja en la cola con la sesión entera y devuelve qué toca. Se decide acá, sin esperar al servidor. */
    fun anotarToma(
        sis: Int,
        dia: Int,
        pulso: Int,
        latidoIrregular: Boolean,
        posicion: String = "sentado",
        minutosDePie: Int? = null,
        brazo: String? = null,
        confirmada: Boolean = false,
        sintomas: List<String> = emptyList(),
    ): Presion.Evaluacion? {
        val e = enCurso ?: return null
        if (Presion.validarToma(sis, dia, pulso) == Presion.Validez.IMPOSIBLE) return null
        val orden = (e.sesion.tomas.maxOfOrNull { it.orden } ?: 0) + 1
        val t = ahora()
        val toma = Presion.Toma(orden, posicion, minutosDePie, brazo ?: e.sesion.brazo, sis, dia, pulso, latidoIrregular, sello(t), confirmada)
        val s = e.sesion.copy(tomas = e.sesion.tomas + toma, sintomas = e.sesion.sintomas + sintomas.filter { it !in e.sesion.sintomas }.distinct(), listaEspera = null)
        _local.update { it.copy(enCurso = e.copy(sesion = s, ultimaTomaEn = t.toEpochMilli(), lista = emptyMap())) }
        return encolarSesion()
    }

    /**
     * Una respuesta de la lista de alarma de la espera. Con un Sí, guardia por síntomas en el acto; con todas en No queda «no»; si
     * falta alguna, la lista queda sin contestar (no cuenta como «no»).
     */
    fun responderLista(codigo: String, si: Boolean): Presion.Evaluacion? {
        val e = enCurso ?: return null
        val lista = e.lista + (codigo to si)
        val sintomas = e.sesion.sintomas.filter { it != codigo } + (if (si) listOf(codigo) else emptyList())
        val antes = e.sesion.listaEspera
        val ahoraLista = when {
            lista.values.any { it } -> "si"
            Presion.alarma.all { it in lista } -> "no"
            else -> null
        }
        _local.update { it.copy(enCurso = e.copy(lista = lista, sesion = e.sesion.copy(sintomas = sintomas, listaEspera = ahoraLista))) }
        // Se manda cuando la lista dice algo nuevo: un Sí o todas en No.
        if (ahoraLista != antes || si) return encolarSesion()
        guardar()
        return evaluar()
    }

    /** Síntomas marcados dentro de la sesión (la hoja que se abre con el pulso o la alta fuera de lo esperado, o «Me mareé»). */
    fun sumarSintomas(codigos: List<String>, nota: String? = null): Presion.Evaluacion? {
        val e = enCurso ?: return null
        val n = (nota ?: "").trim().take(500).ifEmpty { null }
        val s = e.sesion.copy(sintomas = e.sesion.sintomas + codigos.filter { it !in e.sesion.sintomas }.distinct(), nota = n ?: e.sesion.nota)
        _local.update { it.copy(enCurso = e.copy(sesion = s)) }
        // Sin ninguna toma todavía no hay nada que mandar: viaja con la primera.
        if (s.tomas.isEmpty()) {
            guardar()
            return evaluar()
        }
        return encolarSesion()
    }

    private fun encolarSesion(): Presion.Evaluacion? {
        val e = enCurso ?: return null
        val ev = Presion.evaluarSesion(conMinutos(e))
        // Una repetición retomada no sabe el reposo ni las previas: eso no la hace «no cuenta».
        val texto = if (e.retomada && ev.texto == "toma_no_cuenta") "ninguno" else ev.texto
        val envio = EnvioPresion(sesion = e.sesion, textoAlumno = texto, sinPrevio = e.retomada, creadoMs = ahora().toEpochMilli())
        _local.update { c ->
            val i = c.envios.indexOfFirst { it.sesion != null && it.id == envio.id }
            c.copy(envios = if (i >= 0) c.envios.toMutableList().also { it[i] = envio.copy(creadoMs = c.envios[i].creadoMs) } else c.envios + envio)
        }
        guardar()
        drenarEnFondo()
        return ev
    }

    /** «Esta no cuenta» al alumno: nunca en una repetición retomada (reposo y previas sin dato no son una condición incumplida). */
    fun noCuenta(ev: Presion.Evaluacion?): Boolean = ev?.texto == "toma_no_cuenta" && enCurso?.retomada != true

    /** El id de la sesión en curso para un síntoma: solo si ya tiene alguna toma (ya viajó o espera en la cola), si no el servidor lo rechaza. */
    val sesionParaSintoma: String? get() = enCurso?.takeIf { it.sesion.tomas.isNotEmpty() }?.sesion?.id

    /** Lo que dejó «Marcar un síntoma»: si hay alguno de alarma y, si se sumó a la sesión en curso, su evaluación nueva. */
    data class SintomaMarcado(val alarma: Boolean, val evaluacion: Presion.Evaluacion?)

    /**
     * El botón «Marcar un síntoma». Con una sesión en curso que ya tiene tomas ([enSesion]: la pantalla dice si la sesión sigue
     * abierta, no en guardia ni cerrada), además de viajar como síntoma se suma a la sesión y la regla decide el paso.
     */
    fun marcarSintomaBoton(codigos: List<String>, nota: String?, enSesion: Boolean = true): SintomaMarcado {
        val id = if (enSesion) sesionParaSintoma else null
        val alarma = marcarSintoma(codigos, nota, sesionId = id)
        return SintomaMarcado(alarma, if (id != null) sumarSintomas(codigos, nota) else null)
    }

    /** «Me mareé» en la ortostática. Sin ninguna toma viaja como síntoma suelto (sin id de sesión). Devuelve lo que decide la regla. */
    fun meMaree(): Presion.Evaluacion? {
        val e = enCurso ?: return null
        if (e.sesion.tomas.isEmpty()) marcarSintoma(listOf(MAREO), null)
        return sumarSintomas(listOf(MAREO))
    }

    /** Cierra la sesión en curso. Lo anotado ya está en la cola. */
    fun terminar() {
        if (enCurso == null) return
        _local.update { it.copy(enCurso = null) }
        guardar()
    }

    /** «Marcar un síntoma» o la lista del recordatorio. Devuelve si hay alguno de alarma: ahí va el texto de guardia, sin esperar. */
    fun marcarSintoma(codigos: List<String>, nota: String?, contexto: String = "boton", sesionId: String? = null, sinSintomasEnLista: Boolean? = null): Boolean {
        val n = (nota ?: "").trim()
        val s = SintomaPresion(UUID.randomUUID().toString(), sello(ahora()), zona, contexto, sesionId, codigos, sinSintomasEnLista, n.take(500).ifEmpty { null })
        _local.update { it.copy(envios = it.envios + EnvioPresion(sintoma = s, creadoMs = ahora().toEpochMilli())) }
        guardar()
        drenarEnFondo()
        return Presion.deAlarma(codigos)
    }

    // ── Cola ──

    fun drenarEnFondo() {
        lanzar { drenar() }
    }

    /** En orden y de a uno. Sin red, 5xx o 429: corta y queda para después. 4xx u `ok: false`: se descarta y se refresca el estado. */
    suspend fun drenar() {
        if (cerrada || _estado.value == null || !drenando.tryLock()) return
        try {
            var refrescarAlFinal = false
            while (_estado.value != null && !cerrada) {
                val envio = _local.value.envios.firstOrNull() ?: break
                val r = when {
                    envio.sesion != null -> cliente.llamar(
                        "mypump_presion_sesion",
                        mapOf("p_token" to ValorJson.Texto(token), "p_sesion" to json(envio.sesion, envio.textoAlumno ?: "ninguno", version(), envio.sinPrevio)),
                    )
                    envio.sintoma != null -> cliente.llamar("mypump_presion_sintoma", mapOf("p_token" to ValorJson.Texto(token), "p_sintoma" to envio.sintoma.aValor()))
                    else -> {
                        quitar(envio)
                        continue
                    }
                }
                when (r) {
                    is Resultado.Ok -> {
                        if (r.valor == ValorJson.Nulo) return   // token caído: queda guardado para el link nuevo
                        // Mientras viajaba pudo entrar otra toma de la misma sesión: esa versión nueva sigue en la cola.
                        quitar(envio)
                        val e = r.valor["estado"]
                        if (r.valor["ok"] == ValorJson.Booleano(true) && e != null && e != ValorJson.Nulo) {
                            aplicar(e)
                            refrescarAlFinal = false
                        } else {
                            refrescarAlFinal = true
                        }
                    }
                    is Resultado.Falla -> {
                        // Sin el servidor nuevo la cola no se borra: se conserva y se reintenta.
                        if (r.error.funcionInexistente || r.error.status == 404) {
                            apagar()
                            return
                        }
                        if (r.error.clase != ErrorRpc.Clase.PERMANENTE) return   // red, 5xx, 429: queda
                        quitar(envio)
                        refrescarAlFinal = true
                    }
                }
            }
            if (refrescarAlFinal) refrescar()
        } finally {
            drenando.unlock()
        }
    }

    /** Saca el envío que se mandó, salvo que mientras tanto lo haya reemplazado una versión más nueva de la misma sesión. */
    private fun quitar(envio: EnvioPresion) {
        _local.update { c -> c.envios.indexOf(envio).let { i -> if (i >= 0) c.copy(envios = c.envios.filterIndexed { k, _ -> k != i }) else c } }
        guardar()
    }

    private fun guardar(): Boolean {
        val d = disco ?: return false
        // Al cerrar sesión no queda un archivo vacío: solo lo que espera salir.
        if (cerrada && _local.value.envios.isEmpty()) {
            d.borrar(ColaPresion.ARCHIVO)
            return true
        }
        return d.guardar(ColaPresion.ARCHIVO, _local.value.aValor())
    }

    companion object {
        private const val ARCHIVO_ESTADO = "presion-estado.json"
        private const val ARCHIVO_PALANCA = "presion-palanca.json"
        private const val DIAS_EN_COLA = 30L
        private const val MAREO = "mareo_al_pararse"

        /** Pulso de 120 o más, de 40 o menos, o alta menor de 90: después de guardar la toma se pregunta por síntomas. */
        fun pideSintomas(sis: Int, pulso: Int): Boolean = pulso >= 120 || pulso <= 40 || sis < 90

        /** Lo que viaja en `p_sesion`. */
        fun json(s: Presion.Sesion, textoAlumno: String, version: String, sinPrevio: Boolean = false): ValorJson = ValorJson.objeto(
            "id" to texto(s.id), "serie_id" to texto(s.serieId), "tipo" to ValorJson.Texto(s.tipo), "inicio" to texto(s.inicio), "zona_horaria" to texto(s.zonaHoraria),
            "brazo" to texto(s.brazo), "previo" to (if (sinPrevio) ValorJson.Nulo else s.previo.aValor()),
            "reposo_cumplido" to bool(s.reposoCumplido), "temporizador_salteado" to bool(s.temporizadorSalteado),
            "dosis_estimulante_hora" to texto(s.dosisEstimulanteHora), "entreno_entre_dosis_y_toma" to bool(s.entrenoEntreDosisYToma),
            "sintomas" to ValorJson.Lista(s.sintomas.map { ValorJson.Texto(it) }), "lista_espera" to texto(s.listaEspera), "nota" to texto(s.nota),
            "texto_alumno" to ValorJson.Texto(textoAlumno), "app_version" to ValorJson.Texto(version), "plataforma" to ValorJson.Texto("android"),
            "tomas" to ValorJson.Lista(
                s.tomas.map { m ->
                    ValorJson.objeto(
                        "orden" to num(m.orden), "posicion" to ValorJson.Texto(m.posicion ?: "sentado"), "minutos_de_pie" to num(m.minutosDePie),
                        "brazo" to texto(m.brazo ?: s.brazo), "sis" to num(m.sis), "dia" to num(m.dia), "pulso" to num(m.pulso),
                        "latido_irregular" to ValorJson.Booleano(m.latidoIrregular), "medido_en" to texto(m.medidoEn),
                        "confirmada_por_alumno" to ValorJson.Booleano(m.confirmadaPorAlumno),
                    )
                },
            ),
        )
    }
}
