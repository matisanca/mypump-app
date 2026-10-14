package com.pumpteam.mypump.datos

import com.pumpteam.mypump.datos.Resultado as Rpc
import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.modelos.listaEstricta
import com.pumpteam.mypump.reglas.SwapLocal
import com.pumpteam.mypump.reglas.SwapsDeComida
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

// MARK: Recibo

/**
 * El recibo de una corrida: conteos antes (lo leído del almacenamiento viejo) y después (dónde quedó cada cosa del lado
 * nativo), sin contenido crudo ni claves con token. Gemelo de `ReciboLegado` de FaseRemotaLegado.swift.
 */
data class ReciboLegado(
    val migracion: String,
    val corrida: Int,
    val fecha: String,
    val plataforma: String,
    val app: String?,
    val antes: ConteosLegado,
    val despues: ConteosNativos,
    /** Filas por tabla del cliente en el servidor, antes y después de mandar las ops (`mypump_conteos_cliente`, G2). */
    val servidorAntes: Map<String, Int>? = null,
    val servidorDespues: Map<String, Int>? = null,
    /** El cliente de la corrida: un recibo que quedó en el disco solo se reenvía con la cuenta que lo generó. */
    val cliente: String? = null,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("migracion", texto(migracion))
            put("corrida", numero(corrida))
            put("fecha", texto(fecha))
            put("plataforma", texto(plataforma))
            app?.let { put("app", texto(it)) }
            put("antes", antes.aValor())
            put("despues", despues.aValor())
            servidorAntes?.let { m -> put("servidorAntes", ValorJson.Objeto(m.mapValues { numero(it.value) })) }
            servidorDespues?.let { m -> put("servidorDespues", ValorJson.Objeto(m.mapValues { numero(it.value) })) }
            cliente?.let { put("cliente", texto(it)) }
        },
    )

    companion object {
        fun desde(v: ValorJson?): ReciboLegado? {
            val o = v as? ValorJson.Objeto ?: return null
            fun conteos(k: String): Map<String, Int>? =
                (o[k] as? ValorJson.Objeto)?.campos?.mapNotNull { (c, x) -> x.comoNumero?.let { c to enteroTruncado(it) } }?.toMap()
            return ReciboLegado(
                migracion = o["migracion"]?.comoTexto ?: return null,
                corrida = o["corrida"]?.comoNumero?.let(::enteroTruncado) ?: return null,
                fecha = o["fecha"]?.comoTexto ?: "",
                plataforma = o["plataforma"]?.comoTexto ?: "",
                app = o["app"]?.comoTexto,
                antes = ConteosLegado.desde(o["antes"]),
                despues = ConteosNativos.desde(o["despues"]),
                servidorAntes = conteos("servidorAntes"),
                servidorDespues = conteos("servidorDespues"),
                cliente = o["cliente"]?.comoTexto,
            )
        }
    }
}

data class ConteosNativos(
    /** Destino → ops, sumando todas las corridas (el libro mayor). */
    val libro: Map<String, Int> = emptyMap(),
    val colaPendientes: Int = 0,
    val fallidos: Int = 0,
    val colasEsperando: Int = 0,
    val colasNoResuelven: Int = 0,
    val colasOtroCliente: Int = 0,
    val fotosPendientes: Int = 0,
    val fotosFueraDeVentana: Int = 0,
) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "libro" to ValorJson.Objeto(libro.mapValues { numero(it.value) }), "colaPendientes" to numero(colaPendientes),
        "fallidos" to numero(fallidos), "colasEsperando" to numero(colasEsperando), "colasNoResuelven" to numero(colasNoResuelven),
        "colasOtroCliente" to numero(colasOtroCliente), "fotosPendientes" to numero(fotosPendientes),
        "fotosFueraDeVentana" to numero(fotosFueraDeVentana),
    )

    companion object {
        fun desde(v: ValorJson?): ConteosNativos {
            fun n(k: String): Int = v?.get(k)?.comoNumero?.let(::enteroTruncado) ?: 0
            return ConteosNativos(
                (v?.get("libro") as? ValorJson.Objeto)?.campos?.mapNotNull { (k, x) -> x.comoNumero?.let { k to enteroTruncado(it) } }?.toMap() ?: emptyMap(),
                n("colaPendientes"), n("fallidos"), n("colasEsperando"), n("colasNoResuelven"), n("colasOtroCliente"), n("fotosPendientes"),
                n("fotosFueraDeVentana"),
            )
        }
    }
}

enum class EntregaRecibo {
    /** Lo confirmó el servidor: a los 90 días se puede borrar la copia cruda. */
    CONFIRMADO,

    /** Quedó en el teléfono (sin la RPC del recibo, o sin red). */
    SOLO_LOCAL,
    FALLO,
}

/** A dónde va el recibo: al disco ([ReciboEnDisco]) y, con la `nativa_001` aplicada, también al servidor ([ReciboEnServidor]). */
fun interface ReciboMigracion {
    suspend fun enviar(recibo: ReciboLegado, token: String): EntregaRecibo
}

/** El recibo en `legado/recibos/recibo-<corrida>.json`. Nunca "confirmado": sin el servidor, la copia cruda no se borra. */
class ReciboEnDisco(val carpeta: File) : ReciboMigracion {
    override suspend fun enviar(recibo: ReciboLegado, token: String): EntregaRecibo = try {
        ArchivosLegado(carpeta).guardar(recibo.aValor(), "recibo-${recibo.corrida}.json")
        EntregaRecibo.SOLO_LOCAL
    } catch (_: Exception) {
        EntregaRecibo.FALLO
    }
}

/** Filas por tabla del cliente (`mypump_conteos_cliente`, [ConteosRpc]). Sin la RPC, null. */
fun interface ConteosServidor {
    suspend fun contar(token: String): Map<String, Int>?
}

object SinConteosServidor : ConteosServidor {
    override suspend fun contar(token: String): Map<String, Int>? = null
}

// MARK: Fase R

/**
 * Lo que se hace con red, después del primer `get_cliente_info` que contestó: validar las ops sin sesión contra la rutina
 * activa, reasignar las colas de tokens rotados, mandar lo importado por la cola normal y dejar el recibo. La escritura de
 * vuelta la hace la app (con el WebView) con [escrituraPendiente] / [registrarEscritura]. Gemelo de FaseRemotaLegado.swift.
 */
object FaseRemotaLegado {
    data class Resultado(
        var corrio: Boolean = false,
        /** Algo no se pudo preguntar (red): queda pendiente para la próxima. */
        var sinRed: Boolean = false,
        var aLaCola: Int = 0,
        var paraRevisar: Int = 0,
        var reasignadas: Int = 0,
        var reemplazadas: Int = 0,
        var noResuelven: Int = 0,
        var otroCliente: Int = 0,
        /** Swaps de comida locales que el servidor no tenía y entraron a la cola (la migración que hacía la web). */
        var swapsSinMigrar: Int = 0,
        var recibo: EntregaRecibo? = null,
    )

    /** La rutina activa preguntada: `rutina` null es que no tiene. */
    private class Consulta(val rutina: RutinaActiva?)

    /**
     * @param token la cuenta abierta (la del modelo, ya cargada con red), y [clienteId] el suyo.
     * @param outbox la cola VIVA de esa cuenta (la del modelo): importar por ella no pisa lo que encoló la app.
     */
    suspend fun correr(
        entorno: EntornoLegado,
        token: String,
        clienteId: String,
        cliente: ClienteRpc,
        outbox: Outbox,
        recibo: ReciboMigracion,
        conteos: ConteosServidor = SinConteosServidor,
        app: String? = null,
        ahora: Instant = Instant.now(),
        zona: ZoneId = ZoneId.systemDefault(),
    ): Resultado {
        val r = Resultado()
        val a = ArchivosLegado(entorno.carpeta)
        var estado = a.estado ?: return r
        if (!estado.faseRPendiente) return r
        r.corrio = true
        val pendientes = a.pendientes.toMutableList()
        val libro = LinkedHashMap(a.libro)
        val corrida = estado.corridas
        val servidorAntes = conteos.contar(token)

        // La rutina activa se pregunta una vez y solo si hace falta. null = no se pudo preguntar (se reintenta).
        var activa: Consulta? = null
        suspend fun rutinaActiva(): Consulta? {
            activa?.let { return it }
            return when (val res = cliente.llamar("mypump_get_rutina_activa", mapOf("p_token" to texto(token)))) {
                is Rpc.Falla -> null
                is Rpc.Ok -> Consulta(
                    res.valor.primeraFila?.let {
                        try {
                            RutinaActiva.desde(it.aJson())
                        } catch (_: Exception) {
                            null
                        }
                    },
                ).also { activa = it }
            }
        }

        // Los swaps de comida que el teléfono tenía y el servidor nunca vio: se deciden ANTES de drenar nada.
        when (val n = subirSwapsSinMigrar(entorno, token, cliente, outbox)) {
            null -> r.sinRed = true
            else -> r.swapsSinMigrar = n
        }

        val resueltas = HashSet<Int>()
        for (i in pendientes.indices) {
            val p = pendientes[i]
            if (p.estado != ColaPendiente.Estado.ESPERANDO) continue
            if (p.token != token) {
                // Un token rotado: solo si resuelve al MISMO cliente. Nunca se ejecuta lo de otra persona.
                when (val res = cliente.llamar("mypump_get_cliente_info", mapOf("p_token" to texto(p.token)))) {
                    is Rpc.Falla -> {
                        r.sinRed = true
                        continue
                    }
                    is Rpc.Ok -> {
                        val fila = res.valor.primeraFila
                        if (fila == null) {
                            pendientes[i] = p.copy(estado = ColaPendiente.Estado.NO_RESUELVE)
                            for (op in p.ops) libro[op.idLibro]?.let { libro[op.idLibro] = it.copy(destino = EntradaLibro.Destino.NO_RESUELVE) }
                            r.noResuelven += p.ops.size
                            continue
                        }
                        if (fila["cliente_id"]?.comoTexto != clienteId) {
                            pendientes[i] = p.copy(estado = ColaPendiente.Estado.OTRO_CLIENTE)
                            for (op in p.ops) libro[op.idLibro]?.let { libro[op.idLibro] = it.copy(destino = EntradaLibro.Destino.OTRO_CLIENTE) }
                            r.otroCliente += p.ops.size
                            continue
                        }
                    }
                }
            }
            var rutina: RutinaActiva? = null
            if (p.ops.any { it.necesitaValidar }) {
                val consultada = rutinaActiva()
                if (consultada == null) {
                    r.sinRed = true
                    continue
                }
                rutina = consultada.rutina
            }
            val buenas = ArrayList<OpLegada>()
            val malas = sortedMapOf<String, MutableList<OpLegada>>()
            for (op in p.ops) {
                val motivo = if (op.necesitaValidar) motivoParaRevisar(op, p.rutinaFoto, rutina) else null
                if (motivo != null) malas.getOrPut(motivo) { ArrayList() } += op else buenas += op
            }
            val quedaron = outbox.importarSinPisar(buenas.map { it.operacion }).map { it.id }.toSet()
            for (op in buenas) {
                val entro = op.operacion.id in quedaron
                val destino = when {
                    !entro -> EntradaLibro.Destino.REEMPLAZADA
                    p.propia -> EntradaLibro.Destino.COLA
                    else -> EntradaLibro.Destino.REASIGNADA
                }
                libro[op.idLibro] = EntradaLibro(destino, op.operacion.kind, libro[op.idLibro]?.corrida ?: corrida)
                if (!entro) r.reemplazadas++ else if (p.propia) r.aLaCola++ else r.reasignadas++
            }
            for ((motivo, ops) in malas) {
                outbox.archivarEnFallidos(ops.map { it.operacion }, "para revisar: $motivo")
                for (op in ops) {
                    libro[op.idLibro] = EntradaLibro(EntradaLibro.Destino.PARA_REVISAR, op.operacion.kind, libro[op.idLibro]?.corrida ?: corrida)
                }
                r.paraRevisar += ops.size
            }
            if (p.fotos.isNotEmpty()) EjecutorLegado.sumarFotos(p.fotos, entorno.disco(token))
            // Lo de un token rotado ya es de esta cuenta: la escritura de vuelta saca su cola de la Capacitor.
            if (!p.propia && p.firma != null) {
                val e = estado.escritura ?: EscrituraPendiente(corrida, emptyMap())
                estado = estado.copy(escritura = e.copy(borrar = e.borrar + (p.clave to p.firma)))
            }
            resueltas += i
        }
        val quedan = pendientes.filterIndexed { i, _ -> i !in resueltas }
        runCatching { a.guardarLibro(libro) }
        runCatching { a.guardarPendientes(quedan) }

        if (!r.sinRed && r.aLaCola + r.reasignadas + r.swapsSinMigrar > 0) outbox.drenar()

        if (!r.sinRed) {
            // El recibo, con lo que quedó.
            val porDestino = LinkedHashMap<String, Int>()
            for (e in libro.values) porDestino[e.destino.crudo] = (porDestino[e.destino.crudo] ?: 0) + 1
            val fotos = (entorno.disco(token).leer(FotoPendiente.ARCHIVO)?.let(ValorJson::desde) as? ValorJson.Objeto)?.campos
                ?.mapNotNull { (k, f) -> FotoPendiente.desde(f)?.let { k to it } }?.toMap() ?: emptyMap()
            val ms = ahora.toEpochMilli().toDouble()
            val hoy = FechaLegado.dia(ms, zona)
            val desde = FechaLegado.sumar(hoy, -7)
            val hasta = FechaLegado.sumar(hoy, 1)
            val despues = ConteosNativos(
                libro = porDestino,
                colaPendientes = outbox.pendientes(),
                fallidos = outbox.fallidos().size,
                colasEsperando = quedan.count { it.estado == ColaPendiente.Estado.ESPERANDO },
                colasNoResuelven = quedan.count { it.estado == ColaPendiente.Estado.NO_RESUELVE },
                colasOtroCliente = quedan.count { it.estado == ColaPendiente.Estado.OTRO_CLIENTE },
                fotosPendientes = fotos.size,
                fotosFueraDeVentana = fotos.values.count { it.fecha < desde || it.fecha > hasta },
            )
            val rec = ReciboLegado(
                migracion = estado.migracion, corrida = corrida, fecha = DateTimeFormatter.ISO_INSTANT.format(ahora.truncatedTo(ChronoUnit.SECONDS)),
                plataforma = "android", app = app, antes = estado.conteos, despues = despues, servidorAntes = servidorAntes,
                servidorDespues = conteos.contar(token), cliente = clienteId,
            )
            val entrega = recibo.enviar(rec, token)
            r.recibo = entrega
            estado = estado.copy(
                recibos = estado.recibos + 1,
                reciboConfirmadoEn = if (entrega == EntregaRecibo.CONFIRMADO && estado.reciboConfirmadoEn == null) ms else estado.reciboConfirmadoEn,
            )
        }
        estado = estado.copy(faseRPendiente = r.sinRed || quedan.any { it.estado == ColaPendiente.Estado.ESPERANDO })
        runCatching { a.guardarEstado(estado) }
        return r
    }

    /**
     * "Ancla y sube los swaps de comida sin migrar": los del mapa local de la dieta activa que el servidor nunca vio (un
     * teléfono que viene de antes de que los swaps se guardaran en la base). La hidratación del modelo hace lo mismo, pero
     * corre EN PARALELO con esta fase: si el drenado de acá manda primero un swap de la cola vieja, la hidratación ve el
     * servidor con algo y descarta los locales que no están en la cola. Por eso se decide acá, antes de drenar, con la misma
     * función. Devuelve cuántos encoló; null = no se pudo preguntar.
     */
    internal suspend fun subirSwapsSinMigrar(entorno: EntornoLegado, token: String, cliente: ClienteRpc, outbox: Outbox): Int? {
        val disco = entorno.disco(token)
        val dietaRes = cliente.llamar("mypump_get_dieta_activa", mapOf("p_token" to texto(token)))
        if (dietaRes is Rpc.Falla) return null
        val dieta = (dietaRes as Rpc.Ok<ValorJson>).valor.primeraFila?.get("id")?.comoTexto ?: return 0
        if ((disco.leer("swaps_migrados_$dieta") as? JsonPrimitive)?.booleanOrNull == true) return 0
        val locales = leerSwaps(disco, "swaps_$dieta.json")
        if (locales.isNullOrEmpty()) return 0
        // `null` es la red, no "cero swaps": tratarlo como vacío volvería a subir lo que se borró en otro lado.
        val crudo = (cliente.llamar("mypump_get_food_swaps", mapOf("p_token" to texto(token), "p_dieta_id" to texto(dieta))) as? Rpc.Ok<ValorJson>)?.valor
        if (crudo == null || crudo == ValorJson.Nulo) return null
        val remotos = try {
            listaEstricta(crudo.aJson(), FoodSwap::desde)
        } catch (_: Exception) {
            return null
        }
        val pendientes = outbox.pendientesPorClave().mapValues { it.value.kind }
        val h = SwapsDeComida.hidratar(remotos, locales, dieta, pendientes, yaMigrado = false) { _, _, _ -> emptyList() } ?: return 0
        if (!h.migrando) return 0
        var n = 0
        for (op in h.operaciones) {
            if (op.clave in pendientes) continue
            val payload = (op.payload as? ValorJson.Objeto)?.let { ValorJson.Objeto(it.campos + ("dietaId" to texto(dieta))) } ?: op.payload
            outbox.encolar(op.kind, payload, op.clave)
            n++
        }
        return n
    }

    private fun leerSwaps(disco: Disco, nombre: String): Map<String, SwapLocal>? {
        val o = disco.leer(nombre) as? JsonObject ?: return null
        val m = LinkedHashMap<String, SwapLocal>()
        for ((k, v) in o) {
            val s = ValorJson.desde(v)
            val current = s["current"] ?: continue
            m[k] = SwapLocal(s["original"]?.takeUnless { it == ValorJson.Nulo }, current)
        }
        return m
    }

    /**
     * Por qué una op SIN sesión no se puede mandar (null = se puede). Con otra rutina activa, `resolveSesion` le crearía
     * una sesión al bloque nuevo con las series del viejo: una sesión fantasma. No se descarta: va a fallidos.
     */
    internal fun motivoParaRevisar(op: OpLegada, rutinaFoto: String?, activa: RutinaActiva?): String? {
        if (activa == null) return "no hay rutina activa"
        val foto = rutinaFoto ?: return "sin foto offline, no se sabe de qué rutina era"
        if (foto != activa.id) return "la rutina activa ya no es la de la foto"
        val dia = op.operacion.payload["diaId"]?.comoTexto
        if (dia == null || activa.estructura.dias.none { it.id == dia }) return "el día no está en la rutina activa"
        return null
    }

    /** Hay algo para la Fase R o para escribir de vuelta. Sin esto la app no espera la carga con red. */
    fun hayPendiente(entorno: EntornoLegado): Boolean {
        val e = ArchivosLegado(entorno.carpeta).estado ?: return false
        return e.faseRPendiente || e.escritura != null
    }

    /** Solo la Fase R (sin contar la escritura de vuelta): es lo que pausa la palanca `migracion_ops_legadas`. */
    fun faseRPendiente(entorno: EntornoLegado): Boolean = ArchivosLegado(entorno.carpeta).estado?.faseRPendiente ?: false

    // MARK: Escritura de vuelta (la hace la app con el WebView)

    /**
     * Lo que la app tiene que escribir en el `localStorage` viejo: borrar esas claves (si siguen iguales) y dejar la marca.
     * null = nada, o la Fase R todavía no terminó (las colas que se reasignen también se sacan, de una vez).
     */
    data class CambiosEscritura(val corrida: Int, val borrar: Map<String, FirmaValor>, val marca: String)

    fun escrituraPendiente(entorno: EntornoLegado, app: String? = null, ahora: Instant = Instant.now()): CambiosEscritura? {
        val estado = ArchivosLegado(entorno.carpeta).estado ?: return null
        if (estado.faseRPendiente) return null
        val e = estado.escritura ?: return null
        val marca = Marca(estado.migracion, e.corrida, DateTimeFormatter.ISO_INSTANT.format(ahora.truncatedTo(ChronoUnit.SECONDS)), app)
        return CambiosEscritura(e.corrida, e.borrar, marca.texto)
    }

    /**
     * El cuerpo de la función que corre en el origen de la Capacitor (con los argumentos `borrar` =
     * `{clave: {unidades, fnv}}` y `marca`). Borra cada clave SOLO si sigue igual a como se leyó (misma cantidad de
     * unidades UTF-16 y mismo FNV-1a de 32 bits, el de [FirmaValor]), deja la marca y devuelve qué pasó con cada una. Es el
     * mismo de iOS.
     */
    const val SCRIPT_ESCRITURA = """
    function firma(s) {
      let h = 0x811c9dc5;
      for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
      return [s.length, h >>> 0];
    }
    const res = {};
    for (const clave of Object.keys(borrar)) {
      const esperado = borrar[clave];
      const v = localStorage.getItem(clave);
      if (v === null) { res[clave] = 'no estaba'; continue; }
      const f = firma(v);
      if (f[0] !== esperado.unidades || f[1] !== esperado.fnv) { res[clave] = 'cambio'; continue; }
      localStorage.removeItem(clave);
      res[clave] = localStorage.getItem(clave) === null ? 'borrada' : 'fallo';
    }
    localStorage.setItem('mypump_nativa_marca', marca);
    res['mypump_nativa_marca'] = localStorage.getItem('mypump_nativa_marca') === marca ? 'ok' : 'fallo';
    return res;
    """

    /** El script entero para `evaluateJavascript` del WebView: la función con sus dos argumentos ya puestos (en JSON). */
    fun scriptConArgumentos(c: CambiosEscritura): String {
        val borrar = ValorJson.Objeto(c.borrar.mapValues { (_, f) -> ValorJson.objeto("unidades" to numero(f.unidades), "fnv" to numero(f.fnv.toDouble())) })
        return "(function(borrar, marca) {\n$SCRIPT_ESCRITURA\n})(${borrar.serializar()}, ${ValorJson.Texto(c.marca).serializar()})"
    }

    /**
     * Lo que contestó el `localStorage` por clave (`borrada`, `no estaba`, `cambio`, `fallo`) y por la marca (`ok`). Con la
     * marca escrita queda hecha; se confirma en el arranque siguiente, cuando la lectura la encuentra. Lo que "cambió" no se
     * borra: la huella cambió y la Fase L va a correr de nuevo con lo nuevo.
     */
    fun registrarEscritura(entorno: EntornoLegado, cambios: CambiosEscritura, resultado: Map<String, String>) {
        val a = ArchivosLegado(entorno.carpeta)
        val estado = a.estado ?: return
        if (resultado[MigracionLegado.CLAVE_MARCA] != "ok") return
        runCatching { a.guardarEstado(estado.copy(escrituraHecha = cambios.corrida, escrituraUltima = estado.escritura, escritura = null)) }
    }

    /**
     * Los recibos que quedaron solo en el disco (la RPC todavía no existía, o no hubo red), otra vez al servidor, con la
     * misma cuenta que los generó. El primero que confirma arranca la cuenta de los 90 días de la copia cruda.
     */
    suspend fun reenviarRecibos(entorno: EntornoLegado, token: String, clienteId: String, cliente: ClienteRpc, ahora: Instant = Instant.now()): Int {
        val n = ReciboEnServidor.reenviar(File(entorno.carpeta, "recibos"), token, clienteId, cliente)
        val a = ArchivosLegado(entorno.carpeta)
        val estado = a.estado
        if (n > 0 && estado != null && estado.reciboConfirmadoEn == null) {
            runCatching { a.guardarEstado(estado.copy(reciboConfirmadoEn = ahora.toEpochMilli().toDouble())) }
        }
        return n
    }

    /** La copia cruda se borra 90 días después de que el SERVIDOR confirmó el recibo (con el recibo solo en disco, nunca). */
    fun podarCopias(entorno: EntornoLegado, ahora: Instant = Instant.now()) {
        val a = ArchivosLegado(entorno.carpeta)
        val estado = a.estado ?: return
        val confirmado = estado.reciboConfirmadoEn ?: return
        if (ahora.toEpochMilli() - confirmado <= 90.0 * 86_400_000 || estado.copias.isEmpty()) return
        for (c in estado.copias) File(entorno.crudo, c).deleteRecursively()
        runCatching { a.guardarEstado(estado.copy(copias = emptyList())) }
    }
}
