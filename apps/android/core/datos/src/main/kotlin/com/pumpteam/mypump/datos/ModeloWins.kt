package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.ReglasWins
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * «Récords y logros» (2.3.0, palanca `wins_app`; gemelo de ModeloWins.swift): el permiso del alumno para que Mati se
 * entere de sus logros y la cola local de los que faltan dejar en el servidor. Contrato:
 * `supabase/propuestas/nativa_wins_lista_previa.sql`.
 *
 * - Con la palanca apagada no se llama a nada: queda lo último que se supo del permiso (para que el interruptor de Mis
 *   datos se siga viendo y se pueda apagar) y nada más. La única llamada que anda apagada es sacar el permiso.
 * - Un logro solo se encola con la palanca prendida, el servidor activo y el último permiso conocido en true.
 * - La app nunca publica ni manda mensajes: deja filas `pendiente` con `mypump_wins_registrar`. No usa el Outbox general.
 *
 * Como `ModeloApp`, se usa desde un solo hilo. [lanzar] corre el vaciado sin frenar a quien encola.
 */
class ModeloWins(
    private val cliente: ClienteRpc,
    private val token: String,
    private val disco: Disco?,
    private val lanzar: (suspend () -> Unit) -> Unit = {},
) {
    /** Un logro en la cola local. */
    data class Logro(
        /** UUID propio: un reintento no duplica. */
        val id: String,
        val tipo: ReglasWins.Tipo,
        val clave: String,
        /** Fecha local YYYY-MM-DD. */
        val dia: String,
        val datos: ValorJson,
        /** Las veces que el servidor contestó algo que no sirve (token caído, respuesta rara). A la tercera, sale de la cola. */
        val intentos: Int = 0,
    ) {
        fun aValor(): ValorJson = ValorJson.objeto(
            "id" to ValorJson.Texto(id), "tipo" to ValorJson.Texto(tipo.valor), "clave" to ValorJson.Texto(clave),
            "dia" to ValorJson.Texto(dia), "datos" to datos, "intentos" to ValorJson.Numero(intentos.toDouble()),
        )

        /** El mismo logro: tipo, clave, día y datos (el id no cuenta). */
        fun igualA(tipo: ReglasWins.Tipo, clave: String, dia: String, datos: ValorJson): Boolean =
            this.tipo == tipo && this.clave == clave && this.dia == dia && this.datos == datos

        companion object {
            /** Lo que no se entiende (un tipo de otra versión, un archivo tocado) se descarta. */
            fun desde(j: ValorJson): Logro? {
                val id = j["id"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
                val tipo = ReglasWins.Tipo.desde(j["tipo"]?.comoTexto) ?: return null
                val clave = j["clave"]?.comoTexto?.takeIf { it.isNotEmpty() } ?: return null
                val dia = j["dia"]?.comoTexto?.takeIf { it.length == 10 } ?: return null
                val datos = j["datos"] as? ValorJson.Objeto ?: return null
                val intentos = j["intentos"]?.comoNumero?.takeIf { it.isFinite() && it >= 0 && it < TOPE_INTENTOS }?.toInt() ?: 0
                return Logro(id, tipo, clave, dia, datos, intentos)
            }
        }
    }

    /** Lo que mira la pantalla. */
    data class Estado(
        /** La palanca `wins_app`, como se leyó la última vez (se recuerda por cuenta). */
        val palanca: Boolean = false,
        /**
         * El servidor dijo que la función está prendida (`activa` de `mypump_wins_estado`). Se recuerda: sin red en el
         * gimnasio vale lo último que se supo. Sin haberlo sabido nunca, apagada.
         */
        val activa: Boolean = false,
        /** El último permiso conocido (se recuerda en disco para decidir sin red). */
        val permiso: Boolean = false,
        val cola: List<Logro> = emptyList(),
    ) {
        /**
         * Lo que decide la pantalla (el festejo y la hoja de permiso): la palanca y que el servidor haya dicho que está
         * activa. Con la función inexistente (PGRST202) o sin haber podido preguntar nunca, no se muestra nada.
         */
        val prendida: Boolean get() = palanca && activa

        /** El interruptor de Mis datos: prendida, o apagada si el permiso quedó dado (para poder sacarlo). */
        val visibleEnMisDatos: Boolean get() = prendida || permiso
    }

    private val _estado = MutableStateFlow(leer())
    val estado: StateFlow<Estado> = _estado.asStateFlow()

    val prendida: Boolean get() = _estado.value.prendida
    val permiso: Boolean get() = _estado.value.permiso
    val cola: List<Logro> get() = _estado.value.cola
    val palancaRecordada: Boolean get() = _estado.value.palanca

    private var vaciando = false

    /** Lo que el servidor ya recibió en esta sesión de la app: reabrir el festejo no lo manda de nuevo. */
    private val enviados = ArrayList<Logro>()

    private fun leer(): Estado {
        val j = disco?.leer(ARCHIVO)?.let(ValorJson::desde) ?: return Estado()
        return Estado(
            palanca = j["palanca"] == ValorJson.Booleano(true),
            activa = j["activa"] == ValorJson.Booleano(true),
            permiso = j["permiso"] == ValorJson.Booleano(true),
            cola = (j["cola"] as? ValorJson.Lista)?.elementos?.mapNotNull(Logro::desde)?.takeLast(TOPE_COLA) ?: emptyList(),
        )
    }

    private fun fijar(e: Estado) {
        if (e == _estado.value) return
        _estado.value = e
        disco?.guardar(
            ARCHIVO,
            ValorJson.objeto(
                "palanca" to ValorJson.Booleano(e.palanca), "activa" to ValorJson.Booleano(e.activa),
                "permiso" to ValorJson.Booleano(e.permiso), "cola" to ValorJson.Lista(e.cola.map { it.aValor() }),
            ),
        )
    }

    /** La palanca que se acaba de leer. Apagada no se llama a nada; el permiso recordado queda (para poder sacarlo). */
    fun recordarPalanca(prendida: Boolean) = fijar(_estado.value.copy(palanca = prendida))

    private fun fijarPermiso(nuevo: Boolean, activa: Boolean = _estado.value.activa) {
        val e = _estado.value
        fijar(e.copy(activa = activa, permiso = nuevo, cola = if (nuevo) e.cola else emptyList()))
    }

    // ── Estado ──

    /** Al abrir y al volver al frente, con la palanca prendida. */
    suspend fun refrescar() {
        if (!palancaRecordada) return
        when (val r = cliente.llamar("mypump_wins_estado", mapOf("p_token" to texto(token)))) {
            is Resultado.Ok -> {
                val j = r.valor
                if (j["ok"] != ValorJson.Booleano(true)) return   // token caído: no se toca nada
                fijarPermiso(j["permiso"] == ValorJson.Booleano(true), activa = j["activa"] == ValorJson.Booleano(true))
            }
            is Resultado.Falla -> {
                // El servidor todavía no tiene la función: nada que mostrar ni que mandar. Sin red: vale lo último que se supo.
                if (r.error.funcionInexistente) fijarPermiso(false, activa = false)
            }
        }
    }

    // ── Permiso ──

    /**
     * «Sí, compartir». true si el servidor lo dejó dado; ahí los récords del festejo entran a la cola. Sin red o con un
     * error no queda dado.
     */
    suspend fun darPermiso(records: List<ReglasWins.Record> = emptyList(), dia: String = FechaLocal.hoy()): Boolean {
        if (!prendida) return false
        val r = cliente.llamar(
            "mypump_wins_permiso",
            mapOf(
                "p_token" to texto(token), "p_otorga" to ValorJson.Booleano(true), "p_version" to numero(ReglasWins.PERMISO_VERSION),
                "p_plataforma" to texto(PLATAFORMA),
            ),
        )
        val j = r.valorONull() ?: return false
        if (j["ok"] != ValorJson.Booleano(true) || j["permiso"] != ValorJson.Booleano(true)) return false
        fijar(_estado.value.copy(permiso = true))
        encolar(records, dia)
        return true
    }

    /** Apagar el interruptor. true si el servidor lo sacó: la cola local se vacía. Anda también con la palanca apagada. */
    suspend fun revocar(): Boolean {
        val r = cliente.llamar("mypump_wins_permiso", mapOf("p_token" to texto(token), "p_otorga" to ValorJson.Booleano(false)))
        if (r.valorONull()?.get("ok") != ValorJson.Booleano(true)) return false
        fijarPermiso(false)
        return true
    }

    // ── Cola ──

    /** Los récords de un festejo. No encola nada sin la palanca o sin el permiso. Devuelve si quedaron en la cola. */
    fun encolar(records: List<ReglasWins.Record>, dia: String = FechaLocal.hoy()): Boolean {
        val e = _estado.value
        if (!e.prendida || !e.permiso || records.isEmpty()) return false
        fijar(e.copy(cola = records.fold(e.cola) { cola, r -> agregar(cola, r.tipo, r.clave, dia, r.datos) }))
        lanzar { vaciar() }
        return true
    }

    /** La racha de pasos, si es un hito y hay permiso. Devuelve si quedó en la cola (la celebración suma su línea). */
    fun encolarRacha(dias: Int, meta: Int, dia: String = FechaLocal.hoy()): Boolean {
        val e = _estado.value
        if (!e.prendida || !e.permiso || !ReglasWins.esHito(dias)) return false
        fijar(e.copy(cola = agregar(e.cola, ReglasWins.Tipo.RACHA_PASOS, CLAVE_PASOS, dia, ReglasWins.datosRacha(dias, meta))))
        lanzar { vaciar() }
        return true
    }

    /**
     * Uno por tipo, clave y día (como el servidor). El mismo logro con los mismos datos, en la cola o ya enviado en esta
     * sesión, no se encola otra vez (rotar la pantalla o reabrir el festejo no genera ids nuevos). Con datos distintos
     * (mejoró la marca) reemplaza al que todavía no salió, con id nuevo.
     */
    private fun agregar(cola: List<Logro>, tipo: ReglasWins.Tipo, clave: String, dia: String, datos: ValorJson): List<Logro> {
        if (cola.any { it.igualA(tipo, clave, dia, datos) } || enviados.any { it.igualA(tipo, clave, dia, datos) }) return cola
        // Tope: lo más viejo se descarta.
        return (cola.filterNot { it.tipo == tipo && it.clave == clave && it.dia == dia } + Logro(UUID.randomUUID().toString(), tipo, clave, dia, datos))
            .takeLast(TOPE_COLA)
    }

    /**
     * Manda lo que haya: al encolar, al abrir la app y al volver al frente. Lo que el servidor contesta (guardado o no) sale
     * de la cola; un corte o un 5xx lo deja para después.
     */
    suspend fun vaciar() {
        if (!prendida || vaciando) return
        vaciando = true
        try {
            while (true) {
                val l = _estado.value.cola.firstOrNull() ?: return
                val r = cliente.llamar(
                    "mypump_wins_registrar",
                    mapOf(
                        "p_token" to texto(token), "p_id" to texto(l.id), "p_tipo" to texto(l.tipo.valor), "p_clave" to texto(l.clave),
                        "p_dia" to texto(l.dia), "p_datos" to l.datos,
                    ),
                )
                when (r) {
                    is Resultado.Ok -> {
                        val ok = (r.valor["ok"] as? ValorJson.Booleano)?.valor
                        val motivo = r.valor["motivo"]?.comoTexto
                        when {
                            // Sin permiso (lo sacó desde otro lado): se recuerda y se vacía toda la cola.
                            motivo == "sin_permiso" -> {
                                fijarPermiso(false)
                                return
                            }
                            // Guardado o no (`apagada`, `fecha`, `tope`): el servidor ya contestó, no se reintenta.
                            ok == true -> {
                                recordarEnviado(l)
                                quitar(l)
                            }
                            ok == false && motivo == "datos" -> quitar(l)
                            // Token caído u otra respuesta que no se entiende: se reintenta, y a la tercera sale.
                            else -> if (!fallo(l)) return
                        }
                    }
                    is Resultado.Falla -> when {
                        // El servidor no tiene la función: nada que mandar ni que mostrar.
                        r.error.funcionInexistente -> {
                            fijarPermiso(false, activa = false)
                            return
                        }
                        // Un rechazo que no es de red ni un 5xx: cuenta como intento fallido.
                        r.error.clase == ErrorRpc.Clase.PERMANENTE -> if (!fallo(l)) return
                        // Red caída o 5xx: queda para después, sin contar intentos.
                        else -> return
                    }
                }
            }
        } finally {
            vaciando = false
        }
    }

    /** Un intento fallido de [l]. true si con este se agotaron y salió de la cola (se sigue con el próximo). */
    private fun fallo(l: Logro): Boolean {
        if (l.intentos + 1 >= TOPE_INTENTOS) {
            quitar(l)
            return true
        }
        fijar(_estado.value.copy(cola = _estado.value.cola.map { if (it.id == l.id) it.copy(intentos = l.intentos + 1) else it }))
        return false
    }

    private fun recordarEnviado(l: Logro) {
        enviados += l
        if (enviados.size > TOPE_COLA) enviados.removeAt(0)
    }

    private fun quitar(l: Logro) = fijar(_estado.value.copy(cola = _estado.value.cola.filterNot { it.id == l.id }))

    companion object {
        const val ARCHIVO = "wins.json"
        const val TOPE_COLA = 50
        const val TOPE_INTENTOS = 3
        const val PLATAFORMA = "android"
        const val CLAVE_PASOS = "pasos"
    }
}
