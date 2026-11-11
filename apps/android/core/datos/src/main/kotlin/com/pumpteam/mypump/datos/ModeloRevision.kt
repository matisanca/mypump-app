package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.CheckinSemana
import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CheckGuiado
import com.pumpteam.mypump.reglas.CheckinSemanal
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.reglas.PesoCorporal
import com.pumpteam.mypump.reglas.SemanaRevision
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/** Un check de la semana como lo ve el cliente: el guardado (o el optimista recién mandado). */
data class Checkin(val valores: Map<String, Int> = emptyMap(), val nota: String = "")

/** Lo que la app sabe del check guiado por el servidor: si está en ciclo y lo que ya marcó esta semana. */
data class GuiadoServidor(
    val enCiclo: Boolean,
    val semana: String? = null,
    val catalogo: CheckGuiado.Catalogo? = null,
    val senales: List<String>? = null,
) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "enCiclo" to ValorJson.Booleano(enCiclo),
        "semana" to (semana?.let { texto(it) } ?: ValorJson.Nulo),
        "catalogo" to (catalogo?.let { texto(it.clave) } ?: ValorJson.Nulo),
        "senales" to (senales?.let { l -> ValorJson.Lista(l.map { texto(it) }) } ?: ValorJson.Nulo),
    )

    companion object {
        fun desde(j: ValorJson?): GuiadoServidor? {
            val o = j as? ValorJson.Objeto ?: return null
            return GuiadoServidor(
                enCiclo = o["enCiclo"] == ValorJson.Booleano(true),
                semana = o["semana"]?.comoTexto,
                catalogo = CheckGuiado.Catalogo.desde(o["catalogo"]?.comoTexto),
                senales = (o["senales"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto },
            )
        }
    }
}

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
    private val disco: Disco? = null,
) {
    /**
     * El día de revisión del alumno (`mypump_get_revision_dia`, 1 = lunes … 7 = domingo): cuándo sale el aviso local. La
     * semana no cambia por esto: sigue siendo de lunes a domingo. Lo elige el equipo; la app solo lo lee.
     */
    private val _revisionDia = MutableStateFlow(SemanaRevision.normalizado((disco?.leer(ARCHIVO_DIA) as? JsonPrimitive)?.intOrNull))
    val revisionDia: StateFlow<Int> = _revisionDia.asStateFlow()

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

    /**
     * Check guiado: la palanca `check_guiado` que se leyó por última vez ([ModeloApp] la pasa con [recordarPalancaGuiado]).
     * Apagada (o sin la clave, o en la demo), este modelo no llama a nada nuevo y Revisión es la de siempre. Se recuerda en
     * el teléfono: prendida, sin red la Revisión no vuelve a la pantalla anterior.
     */
    private val _guiadoPrendido = MutableStateFlow(token != null && disco?.leer(ARCHIVO_PALANCA_GUIADO)?.let { ValorJson.desde(it) } == ValorJson.Booleano(true))
    val guiadoPrendido: StateFlow<Boolean> = _guiadoPrendido.asStateFlow()

    fun recordarPalancaGuiado(prendida: Boolean) {
        if (token == null || prendida == _guiadoPrendido.value) return
        _guiadoPrendido.value = prendida
        disco?.guardar(ARCHIVO_PALANCA_GUIADO, ValorJson.Booleano(prendida))
    }

    /** Lo último que dijo `mypump_check_guiado_get` (queda en el disco: sin señal, la lista de «¿Notaste algo?» no cambia). */
    private val _guiado = MutableStateFlow(GuiadoServidor.desde(disco?.leer(ARCHIVO_GUIADO)?.let { ValorJson.desde(it) }))
    val guiado: StateFlow<GuiadoServidor?> = _guiado.asStateFlow()

    /** Lo que el alumno lleva contestado del check guiado de esta semana y todavía no mandó. */
    private val _borradorGuiado = MutableStateFlow(CheckGuiado.Borrador.desde(disco?.leer(ARCHIVO_BORRADOR)?.let { ValorJson.desde(it) }))
    val borradorGuiado: StateFlow<CheckGuiado.Borrador?> = _borradorGuiado.asStateFlow()

    private val t get() = texto(token ?: "")   // la demo no llega acá: no toca la red

    // ── Revisión ──

    /**
     * Sin red o con un error pasajero queda el último que se supo (el aviso se arma también sin señal). Sin la función en la
     * base (PGRST202: nativa_008 todavía no aplicada, o revertida) es el domingo, lo de siempre.
     */
    private fun aplicarDia(r: Resultado<ValorJson>) {
        val nuevo = when (r) {
            is Resultado.Ok -> SemanaRevision.normalizado(r.valor.comoNumero?.toInt())
            is Resultado.Falla -> if (r.error.funcionInexistente) SemanaRevision.DIA_POR_DEFECTO else return
        }
        if (nuevo == _revisionDia.value) return
        _revisionDia.value = nuevo
        disco?.guardar(ARCHIVO_DIA, JsonPrimitive(nuevo))
    }

    /** `loadRevision` + `loadSalud`: el check de la semana y 60 días de salud (para el peso). */
    suspend fun cargarRevision() {
        if (token == null) return   // la demo, como la web: sin check, peso ni fotos
        val hoy = diaDeHoy()
        _fecha.value = hoy
        // Semana nueva: el check de la anterior no es el de esta, haya red o no (la web lo vacía).
        if (semanaDelCheck != semana) _checkin.value = null
        semanaDelCheck = semana
        val desde = DiaCalendario.numero(hoy)?.let { DiaCalendario.texto(it - 59) } ?: hoy
        val prendido = _guiadoPrendido.value
        var rg: Resultado<ValorJson>? = null
        val (rc, rs, rd) = coroutineScope {
            val c = async { cliente.filas("mypump_get_checkin_semana", mapOf("p_token" to t, "p_fecha" to texto(hoy)), CheckinSemana::desde) }
            val s = async {
                cliente.filas("mypump_get_salud", mapOf("p_token" to t, "p_desde" to texto(desde), "p_hasta" to texto(hoy)), FilaSalud::desde)
            }
            val d = async { cliente.llamar("mypump_get_revision_dia", mapOf("p_token" to t)) }
            // Solo con la palanca prendida: apagada no sale ni una llamada nueva.
            val g = if (prendido) async { cliente.llamar("mypump_check_guiado_get", mapOf("p_token" to t, "p_fecha" to texto(hoy))) } else null
            rg = g?.await()
            Triple(c.await(), s.await(), d.await())
        }
        aplicarDia(rd)
        rg?.let { aplicarGuiado(it) }
        // El borrador de otra semana no es de esta.
        if (_borradorGuiado.value?.let { it.semana != semana } == true) descartarBorrador()
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
        if (prendido) aplicarGuiadoPendiente()
    }

    /** Lo marcado en «¿Notaste algo?» que todavía no salió gana sobre lo que trae el servidor, como el check. */
    private suspend fun aplicarGuiadoPendiente() {
        val semana = semana
        val pendientes = (outbox?.pendientesPorClave() ?: emptyMap()).filter { (k, op) ->
            k.startsWith("${KIND_GUIADO}_") && op.payload["fecha"]?.comoTexto?.let(FotosProgreso::lunes) == semana
        }
        val op = pendientes.values.maxByOrNull { it.ts } ?: return
        val r = op.payload["respuestas"] ?: return
        val senales = (r["senales"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: return
        _guiado.value = GuiadoServidor(_guiado.value?.enCiclo ?: false, semana, CheckGuiado.Catalogo.desde(r["catalogo"]?.comoTexto), senales)
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

    // ── Check guiado ──

    /**
     * Sin red o con un error pasajero queda lo último que se supo. Sin la función (la propuesta sin aplicar) o con la
     * palanca apagada en el servidor, nadie está en ciclo: la lista general.
     */
    private fun aplicarGuiado(r: Resultado<ValorJson>) {
        val nuevo: GuiadoServidor? = when (r) {
            is Resultado.Ok -> r.valor.takeIf { it["activo"] == ValorJson.Booleano(true) }?.let { j ->
                GuiadoServidor(
                    enCiclo = j["en_ciclo"] == ValorJson.Booleano(true),
                    semana = j["semana"]?.comoTexto,
                    catalogo = CheckGuiado.Catalogo.desde(j["catalogo"]?.comoTexto),
                    senales = (j["senales"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto },
                )
            }
            is Resultado.Falla -> if (r.error.funcionInexistente) null else return
        }
        if (nuevo == _guiado.value) return
        _guiado.value = nuevo
        if (nuevo != null) disco?.guardar(ARCHIVO_GUIADO, nuevo.aValor()) else disco?.borrar(ARCHIVO_GUIADO)
    }

    /** La lista de «¿Notaste algo?» que le toca. */
    val catalogoGuiado: CheckGuiado.Catalogo get() = CheckGuiado.Catalogo.de(_guiado.value?.enCiclo ?: false)

    /** El borrador con el que se abre el check guiado: el guardado de esta semana o uno nuevo con lo ya enviado. */
    fun abrirGuiado(): CheckGuiado.Borrador {
        val g = _guiado.value
        val deEstaSemana = g?.semana == semana
        return CheckGuiado.abrir(
            guardado = _borradorGuiado.value,
            semana = semana,
            catalogo = catalogoGuiado,
            enviado = if (checkinEnviado) _checkin.value?.let { CheckGuiado.Enviado(it.valores, it.nota) } else null,
            senalesEnviadas = if (deEstaSemana) g?.senales else null,
            catalogoEnviado = if (deEstaSemana) g?.catalogo else null,
        )
    }

    /** Guardado parcial: cada paso deja el borrador en el teléfono, así se retoma donde quedó. */
    fun guardarBorrador(b: CheckGuiado.Borrador) {
        if (b == _borradorGuiado.value) return
        _borradorGuiado.value = b
        disco?.guardar(ARCHIVO_BORRADOR, b.aValor())
    }

    fun descartarBorrador() {
        _borradorGuiado.value = null
        disco?.borrar(ARCHIVO_BORRADOR)
    }

    /**
     * El paso del peso: lo guarda en el momento, por la misma cola que la tarjeta de peso. false = no es un peso válido. Si
     * es el que ya está cargado hoy, no lo manda de nuevo.
     */
    suspend fun guardarPesoGuiado(texto: String): Boolean {
        val valor = PesoCorporal.leer(texto) ?: return false
        val hoy = diaDeHoy()
        if (_salud.value.any { it.tipo == "peso_kg" && it.fecha == hoy && it.fuente == "manual" && it.valor == valor }) return true
        return guardarPeso(texto)
    }

    /** El peso manual de hoy, si ya está cargado (el paso del peso lo trae puesto). */
    val pesoDeHoy: Double? get() = diaDeHoy().let { hoy -> _salud.value.lastOrNull { it.tipo == "peso_kg" && it.fecha == hoy && it.fuente == "manual" }?.valor }

    /**
     * «Enviar mi check» del check guiado. Manda lo de siempre por donde siempre (`checkin` y `peso`) y, aparte, lo marcado
     * en «¿Notaste algo?» (`check_guiado`). Devuelve qué falta, o null si salió.
     */
    suspend fun enviarGuiado(b: CheckGuiado.Borrador): String? {
        CheckGuiado.faltaParaEnviar(b)?.let { return it }
        val kilos = b.peso.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
        if (kilos.isNotEmpty() && PesoCorporal.leer(kilos) == null) return CheckGuiado.AVISO_RANGO_PESO
        enviarCheckin(Checkin(b.valores, b.nota))?.let { return it }
        if (kilos.isNotEmpty()) guardarPesoGuiado(kilos)
        val dia = diaDeHoy()
        val senales = CheckGuiado.normalizar(b.senales, b.catalogo)
        outbox?.encolar(
            KIND_GUIADO,
            ValorJson.objeto(
                "fecha" to texto(dia),
                "respuestas" to ValorJson.objeto("catalogo" to texto(b.catalogo.clave), "senales" to ValorJson.Lista(senales.map { texto(it) })),
            ),
            "${KIND_GUIADO}_$dia",
        )
        val nuevo = GuiadoServidor(_guiado.value?.enCiclo ?: false, FotosProgreso.lunes(dia), b.catalogo, senales)
        _guiado.value = nuevo
        disco?.guardar(ARCHIVO_GUIADO, nuevo.aValor())
        descartarBorrador()
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
        private const val ARCHIVO_DIA = "revision_dia.json"
        private const val ARCHIVO_GUIADO = "check_guiado.json"
        private const val ARCHIVO_BORRADOR = "check_guiado_borrador.json"
        private const val ARCHIVO_PALANCA_GUIADO = "check-guiado-palanca.json"

        /** El kind de la cola de lo marcado en «¿Notaste algo?». */
        const val KIND_GUIADO = "check_guiado"

        /** "Ver demo" (ACC-07): sin cuenta, sin red ni cola; el check y el peso se tocan igual y no sale nada. */
        fun demo(cliente: ClienteRpc, alcance: CoroutineScope, hoy: String = FechaLocal.hoy()): ModeloRevision =
            ModeloRevision(cliente, token = null, outbox = null, alcance = alcance).also { m -> m._fecha.value = hoy }
    }
}
