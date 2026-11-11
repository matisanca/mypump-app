package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Casa
import com.pumpteam.mypump.reglas.EstadoCasa
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex

/** Lo que el alumno lleva marcado de su casa y todavía no mandó. Queda en disco hasta enviarlo. */
data class BorradorCasa(
    /** La carga a la que pertenece: si el servidor abre otra, lo marcado no se arrastra. */
    val gimnasioId: String? = null,
    val marcados: List<String> = emptyList(),
    /** Lo escrito en «Hasta cuántos kilos», por tipo, tal cual. */
    val kilos: Map<String, String> = emptyMap(),
    val sinEquipo: Boolean = false,
    val nota: String = "",
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            gimnasioId?.let { put("gimnasioId", ValorJson.Texto(it)) }
            put("marcados", ValorJson.Lista(marcados.map { ValorJson.Texto(it) }))
            put("kilos", ValorJson.Objeto(kilos.mapValues { ValorJson.Texto(it.value) }))
            put("sinEquipo", ValorJson.Booleano(sinEquipo)); put("nota", ValorJson.Texto(nota))
        },
    )

    companion object {
        const val ARCHIVO = "casa-borrador.json"

        fun desde(v: ValorJson): BorradorCasa = BorradorCasa(
            gimnasioId = v["gimnasioId"]?.comoTexto,
            marcados = (v["marcados"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList(),
            kilos = (v["kilos"] as? ValorJson.Objeto)?.campos?.mapNotNull { (k, x) -> x.comoTexto?.let { k to it } }?.toMap() ?: emptyMap(),
            sinEquipo = v["sinEquipo"] == ValorJson.Booleano(true),
            nota = v["nota"]?.comoTexto ?: "",
        )
    }
}

/**
 * Entrenar en casa (2.3.0, palanca `casa`; contrato `cola-b/CONTRATO_APP.md`, sección 3): el interruptor de «Mi gimnasio».
 * La carga de casa es la misma fila de `mypump_gimnasio_get` con otro lugar, así que después de cada `elegir` y `enviar` se
 * refrescan los dos ([gimnasio] y este).
 *
 * - **Apagado no se ve.** Hacen falta las palancas `gimnasio_fotos` y `casa`; sin las dos [ModeloApp] no llama a nada y
 *   [estado] queda en null (el interruptor no existe y Mi gimnasio es el de siempre).
 * - PGRST202, 404, `NULL` o `habilitado:false`: null. Sin red, lo último que se supo; al abrir la app sin red, solo para
 *   seguir marcando un borrador de casa.
 */
class ModeloCasa(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    private val gimnasio: ModeloGimnasio,
) {
    enum class Salida { OK, ERROR }
    enum class Aviso { NO_SE_PUDO_CAMBIAR, NO_SE_PUDO_ENVIAR, SIN_DATOS }

    private val palanca = PalancaEnDisco(disco, ARCHIVO_PALANCA)
    val palancaRecordada: Boolean get() = palanca.prendida

    private val _estado = MutableStateFlow<EstadoCasa?>(null)
    /** null: apagado, sin el servidor nuevo o no habilitado. El interruptor no se muestra. */
    val estado: StateFlow<EstadoCasa?> = _estado.asStateFlow()

    private val _borrador = MutableStateFlow(disco?.leer(BorradorCasa.ARCHIVO)?.let { BorradorCasa.desde(ValorJson.desde(it)) } ?: BorradorCasa())
    val borrador: StateFlow<BorradorCasa> = _borrador.asStateFlow()

    /** A dónde se está moviendo el interruptor mientras contesta el servidor (lo que muestra mientras tanto). null: quieto. */
    private val _moviendoA = MutableStateFlow<Boolean?>(null)
    val moviendoA: StateFlow<Boolean?> = _moviendoA.asStateFlow()

    private val _enviando = MutableStateFlow(false)
    val enviando: StateFlow<Boolean> = _enviando.asStateFlow()

    private val _aviso = MutableStateFlow<Aviso?>(null)
    val aviso: StateFlow<Aviso?> = _aviso.asStateFlow()

    private val ocupado = Mutex()

    val interruptor: Casa.Interruptor? get() = _estado.value?.let(Casa::interruptor)
    val pantalla: Casa.Pantalla get() = Casa.pantalla(_estado.value)
    val puedeEnviar: Boolean
        get() = _estado.value?.let { e -> Casa.puedeEnviar(_borrador.value.marcados, _borrador.value.sinEquipo, e.tipos) } ?: false

    fun usarPalanca(prendida: Boolean) {
        palanca.recordar(prendida)
        if (!prendida) apagar()
    }

    fun apagar() {
        _estado.value = null
        _aviso.value = null
    }

    fun limpiarAviso() {
        _aviso.value = null
    }

    private fun p() = mapOf("p_token" to ValorJson.Texto(token))

    /** `get`, junto con `mypump_gimnasio_get`. Solo con las dos palancas prendidas (lo decide [ModeloApp]). */
    suspend fun refrescar() {
        when (val r = cliente.llamar(RPC_GET, p())) {
            is Resultado.Ok -> {
                val e = EstadoCasa.desde(r.valor)
                if (e == null) {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                } else {
                    aplicar(e)
                    disco?.guardar(ARCHIVO_ESTADO, r.valor)
                }
            }
            is Resultado.Falla -> {
                if (r.error.clase == ErrorRpc.Clase.PERMANENTE) {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                } else if (_estado.value == null) {
                    // Solo para seguir marcando un borrador de casa: lo demás, sin señal, no se muestra.
                    disco?.leer(ARCHIVO_ESTADO)?.let { EstadoCasa.desde(ValorJson.desde(it)) }
                        ?.takeIf { Casa.pantalla(it) == Casa.Pantalla.LISTA }
                        ?.let(::aplicar)
                }
            }
        }
    }

    private fun aplicar(e: EstadoCasa) {
        // La palanca se pudo apagar mientras el pedido estaba en camino: lo que vuelve no se muestra.
        if (!palancaRecordada) return
        _estado.value = e
        val id = e.abierta?.id
        if (_borrador.value.gimnasioId != id) guardar(BorradorCasa(gimnasioId = id))
    }

    private suspend fun refrescarLosDos() {
        gimnasio.refrescar()
        refrescar()
    }

    // ── El interruptor ──

    /**
     * Mover el interruptor. Prenderlo: `elegir(true)`. Apagarlo con un borrador de casa: `elegir(false)`. Apagarlo sin
     * borrador y con casa vigente: la carga de gimnasio de siempre (el camino de «Cambié de gimnasio»). Si falla, el
     * interruptor vuelve a como estaba y queda el aviso.
     */
    suspend fun mover(prender: Boolean): Salida {
        val e = _estado.value ?: return Salida.ERROR
        val que = Casa.alMover(e, prender)
        if (que == Casa.Movimiento.NADA) return Salida.OK
        if (!ocupado.tryLock()) return Salida.OK
        _aviso.value = null
        _moviendoA.value = prender
        try {
            val bien = when (que) {
                Casa.Movimiento.NUEVO_GIMNASIO -> gimnasio.empezar("completa") == ModeloGimnasio.Salida.OK
                else -> elegir(prender, reintentos = 1)
            }
            // Pase lo que pase se vuelve a preguntar: lo que diga el servidor es lo que se muestra.
            if (_estado.value != null) if (que == Casa.Movimiento.NUEVO_GIMNASIO) refrescar() else refrescarLosDos()
            if (!bien && _estado.value != null) _aviso.value = Aviso.NO_SE_PUDO_CAMBIAR
            return if (bien) Salida.OK else Salida.ERROR
        } finally {
            _moviendoA.value = null
            ocupado.unlock()
        }
    }

    /** «Cambió lo que tengo en casa»: abre una carga de casa nueva. */
    suspend fun cambiar(): Salida = moverA(true)

    private suspend fun moverA(casa: Boolean): Salida {
        if (_estado.value == null) return Salida.ERROR
        if (!ocupado.tryLock()) return Salida.OK
        _aviso.value = null
        try {
            val bien = elegir(casa, reintentos = 1)
            if (_estado.value != null) refrescarLosDos()
            if (!bien && _estado.value != null) _aviso.value = Aviso.NO_SE_PUDO_CAMBIAR
            return if (bien) Salida.OK else Salida.ERROR
        } finally {
            ocupado.unlock()
        }
    }

    /** true = el servidor lo tomó (o ya estaba). `en_curso` no es un error del alumno: al refrescar el interruptor queda fijo. */
    private suspend fun elegir(casa: Boolean, reintentos: Int): Boolean =
        when (val r = cliente.llamar(RPC_ELEGIR, p() + ("p_casa" to ValorJson.Booleano(casa)))) {
            is Resultado.Falla -> false
            is Resultado.Ok -> when {
                r.valor["ok"] == ValorJson.Booleano(true) -> true
                else -> when (r.valor["error"]?.comoTexto) {
                    "no_habilitado" -> {
                        apagar()
                        disco?.borrar(ARCHIVO_ESTADO)
                        false
                    }
                    "en_curso" -> true
                    "reintentar" -> if (reintentos > 0) elegir(casa, reintentos - 1) else false
                    else -> false   // `NULL` (token caído) u otro
                }
            }
        }

    // ── La lista ──

    fun marcar(tipo: String, marcado: Boolean) {
        val e = _estado.value ?: return
        if (e.tipos.none { it.tipo == tipo }) return
        val b = _borrador.value
        val s = b.marcados.toMutableSet().apply { if (marcado) add(tipo) else remove(tipo) }
        // Marcar un equipo desmarca «No tengo nada de esto». En el orden de la lista del servidor.
        guardar(b.copy(marcados = e.tipos.map { it.tipo }.filter { it in s }, sinEquipo = if (marcado) false else b.sinEquipo))
        _aviso.value = null
    }

    fun fijarKilos(tipo: String, texto: String) {
        if (!Casa.kilosEscribibles(texto)) return
        val b = _borrador.value
        val k = if (texto.isEmpty()) b.kilos - tipo else b.kilos + (tipo to texto)
        if (k != b.kilos) guardar(b.copy(kilos = k))
    }

    /** «No tengo nada de esto»: marcarlo desmarca todo. */
    fun marcarSinEquipo(sin: Boolean) {
        val b = _borrador.value
        guardar(if (sin) b.copy(sinEquipo = true, marcados = emptyList()) else b.copy(sinEquipo = false))
        _aviso.value = null
    }

    fun fijarNota(s: String) {
        val n = Casa.notaRecortada(s)
        if (n != _borrador.value.nota) guardar(_borrador.value.copy(nota = n))
    }

    /** «Enviar a Mati». Reintentar es seguro: el servidor contesta `ya`. Queda en `a_revisar` y se ve «Recibido». */
    suspend fun enviar(): Salida {
        val e = _estado.value ?: return Salida.ERROR
        val a = e.abierta?.takeIf { it.esCasa && it.esBorrador } ?: return Salida.ERROR
        val b = _borrador.value
        if (!Casa.puedeEnviar(b.marcados, b.sinEquipo, e.tipos)) {
            _aviso.value = Aviso.SIN_DATOS
            return Salida.ERROR
        }
        if (!ocupado.tryLock()) return Salida.OK
        _aviso.value = null
        _enviando.value = true
        try {
            val equipos = Casa.equiposParaEnviar(e.tipos, b.marcados, b.kilos, b.sinEquipo)
            val r = cliente.llamar(
                RPC_ENVIAR,
                p() + mapOf(
                    "p_id" to ValorJson.Texto(a.id), "p_equipos" to Casa.aValor(equipos), "p_sin_equipo" to ValorJson.Booleano(equipos.isEmpty()),
                    "p_nota" to ValorJson.Texto(b.nota.trim()),
                ),
            )
            val j = (r as? Resultado.Ok)?.valor
            if (j == null) {
                _aviso.value = Aviso.NO_SE_PUDO_ENVIAR
                return Salida.ERROR
            }
            if (j["ok"] == ValorJson.Booleano(true)) {
                guardar(BorradorCasa(gimnasioId = a.id))
                refrescarLosDos()
                return Salida.OK
            }
            when (j["error"]?.comoTexto) {
                "sin_datos" -> _aviso.value = Aviso.SIN_DATOS
                "no_encontrado", "no_es_casa" -> refrescarLosDos()
                "no_habilitado" -> {
                    apagar()
                    disco?.borrar(ARCHIVO_ESTADO)
                    gimnasio.refrescar()
                }
                else -> _aviso.value = Aviso.NO_SE_PUDO_ENVIAR   // `contradiccion`, `NULL` (token caído) u otro
            }
            return Salida.ERROR
        } finally {
            _enviando.value = false
            ocupado.unlock()
        }
    }

    private fun guardar(b: BorradorCasa) {
        _borrador.value = b
        disco?.guardar(BorradorCasa.ARCHIVO, b.aValor())
    }

    companion object {
        const val RPC_GET = "mypump_casa_get"
        const val RPC_ELEGIR = "mypump_casa_elegir"
        const val RPC_ENVIAR = "mypump_casa_enviar"
        internal const val ARCHIVO_ESTADO = "casa-estado.json"
        internal const val ARCHIVO_PALANCA = "casa-palanca.json"
    }
}
