package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SwapLocal
import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

/**
 * Dónde vive todo (inyectable en los tests). En la app: `filesDir` como [raiz] (la de las carpetas de cuenta de [Disco]) y
 * el lector del WebView. Gemelo de `EntornoLegado` de EjecutorLegado.swift.
 */
class EntornoLegado(val raiz: File, val lector: LectorLegado) {
    /** `legado/`: estado, libro mayor, colas pendientes de la Fase R y recibos. Va al backup (sin él, una restauración
     *  volvería a importar lo que ya se mandó). */
    val carpeta: File get() = File(raiz, "legado")

    /** `legado/crudo/`: las copias crudas. Sirven en ESTE teléfono: están fuera del backup (ver `reglas_backup.xml`). */
    val crudo: File get() = File(carpeta, "crudo")

    fun disco(token: String): Disco = Disco(raiz, token)
}

/**
 * El estado de la migración en este teléfono (`legado/estado.json`). Sin tokens ni valores, salvo las claves que la
 * escritura de vuelta tiene que borrar.
 */
data class EstadoMigracion(
    /** UUID de la migración de este teléfono: va en el recibo y en la marca. */
    val migracion: String,
    val corridas: Int,
    val primera: Double,
    val ultima: Double,
    /** La de la última lectura. Si cambia, alguien volvió a la Capacitor: la Fase L corre de nuevo. */
    val huella: HuellaLegado?,
    val anterior: CorridaAnterior,
    /** Conteos de la última lectura (el "antes" del recibo). */
    val conteos: ConteosLegado,
    /** Falta la Fase R: hay ops por validar, colas estacionadas sin resolver o recibo sin dejar. */
    val faseRPendiente: Boolean,
    /** Lo que falta escribir de vuelta en el `localStorage` (sacar las ops tomadas y los cachés de sesión, dejar la marca). */
    val escritura: EscrituraPendiente?,
    /** Corrida de la última escritura de vuelta hecha, y la última que la lectura confirmó en un arranque siguiente. */
    val escrituraHecha: Int?,
    val escrituraConfirmada: Int?,
    /** La última que se hizo, por si no llegó al disco y hay que repetirla. */
    val escrituraUltima: EscrituraPendiente?,
    val copias: List<String>,
    val recibos: Int,
    /** Cuándo el SERVIDOR confirmó el recibo (G2). La copia cruda se borra 90 días después; sin RPC, nunca. */
    val reciboConfirmadoEn: Double?,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("migracion", texto(migracion))
            put("corridas", numero(corridas))
            put("primera", numero(primera))
            put("ultima", numero(ultima))
            huella?.let { put("huella", it.aValor()) }
            put("anterior", anterior.aValor())
            put("conteos", conteos.aValor())
            put("faseRPendiente", ValorJson.Booleano(faseRPendiente))
            escritura?.let { put("escritura", it.aValor()) }
            escrituraHecha?.let { put("escrituraHecha", numero(it)) }
            escrituraConfirmada?.let { put("escrituraConfirmada", numero(it)) }
            escrituraUltima?.let { put("escrituraUltima", it.aValor()) }
            put("copias", ValorJson.Lista(copias.map { texto(it) }))
            put("recibos", numero(recibos))
            reciboConfirmadoEn?.let { put("reciboConfirmadoEn", numero(it)) }
        },
    )

    companion object {
        fun nuevo(ms: Double) = EstadoMigracion(
            migracion = UUID.randomUUID().toString().lowercase(Locale.ROOT), corridas = 0, primera = ms, ultima = ms, huella = null,
            anterior = CorridaAnterior(), conteos = ConteosLegado(), faseRPendiente = false, escritura = null, escrituraHecha = null,
            escrituraConfirmada = null, escrituraUltima = null, copias = emptyList(), recibos = 0, reciboConfirmadoEn = null,
        )

        fun desde(v: ValorJson?): EstadoMigracion? {
            val o = v as? ValorJson.Objeto ?: return null
            val migracion = o["migracion"]?.comoTexto ?: return null
            fun entero(k: String): Int? = o[k]?.comoNumero?.let(::enteroTruncado)
            return EstadoMigracion(
                migracion = migracion, corridas = entero("corridas") ?: 0, primera = o["primera"]?.comoNumero ?: 0.0,
                ultima = o["ultima"]?.comoNumero ?: 0.0, huella = HuellaLegado.desde(o["huella"]), anterior = CorridaAnterior.desde(o["anterior"]),
                conteos = ConteosLegado.desde(o["conteos"]), faseRPendiente = o["faseRPendiente"] == ValorJson.Booleano(true),
                escritura = EscrituraPendiente.desde(o["escritura"]), escrituraHecha = entero("escrituraHecha"),
                escrituraConfirmada = entero("escrituraConfirmada"), escrituraUltima = EscrituraPendiente.desde(o["escrituraUltima"]),
                copias = (o["copias"] as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList(), recibos = entero("recibos") ?: 0,
                reciboConfirmadoEn = o["reciboConfirmadoEn"]?.comoNumero,
            )
        }
    }
}

data class EscrituraPendiente(
    val corrida: Int,
    /** Clave → firma que tenía al leerla: se borra solo si sigue igual. */
    val borrar: Map<String, FirmaValor>,
) {
    fun aValor(): ValorJson = ValorJson.objeto("corrida" to numero(corrida), "borrar" to ValorJson.Objeto(borrar.mapValues { it.value.aValor() }))

    companion object {
        fun desde(v: ValorJson?): EscrituraPendiente? {
            val c = v?.get("corrida")?.comoNumero ?: return null
            val b = (v["borrar"] as? ValorJson.Objeto)?.campos?.mapNotNull { (k, f) -> FirmaValor.desde(f)?.let { k to it } }?.toMap() ?: emptyMap()
            return EscrituraPendiente(enteroTruncado(c), b)
        }
    }
}

/**
 * Una entrada del libro mayor (`legado/libro.json`): qué se hizo con cada op vieja. Lo que está acá no se vuelve a
 * importar nunca, aunque la Capacitor la siga teniendo.
 */
data class EntradaLibro(val destino: Destino, val kind: String, val corrida: Int) {
    enum class Destino(val crudo: String) {
        /** A la cola nativa (se manda por la cola normal). */
        COLA("cola"),

        /** Sin sesión: espera la validación contra la rutina activa (Fase R). */
        POR_VALIDAR("porValidar"),

        /** No pasó la validación: en fallidos, con su motivo. Nunca se descarta. */
        PARA_REVISAR("paraRevisar"),

        /** De un token rotado, esperando la Fase R. */
        ESTACIONADA("estacionada"),

        /** De un token rotado que resolvió al mismo cliente: a la cola. */
        REASIGNADA("reasignada"),

        /** La nativa tenía una pendiente más nueva con la misma dedupeKey. */
        REEMPLAZADA("reemplazada"),

        /** Cola sin token: no se ejecuta nunca. */
        ANON("anon"),

        /** El token rotado es de OTRO cliente: no se ejecuta nunca. */
        OTRO_CLIENTE("otroCliente"),

        /** El token rotado ya no resuelve: queda estacionada, va al recibo. */
        NO_RESUELVE("noResuelve"),
        ;

        companion object {
            fun de(crudo: String?): Destino? = entries.firstOrNull { it.crudo == crudo }
        }
    }

    fun aValor(): ValorJson = ValorJson.objeto("destino" to texto(destino.crudo), "kind" to texto(kind), "corrida" to numero(corrida))

    companion object {
        fun desde(v: ValorJson?): EntradaLibro? {
            val d = Destino.de(v?.get("destino")?.comoTexto) ?: return null
            return EntradaLibro(d, v?.get("kind")?.comoTexto ?: "", v?.get("corrida")?.comoNumero?.let(::enteroTruncado) ?: 0)
        }
    }
}

/**
 * Una cola que espera la Fase R (`legado/pendientes.json`): las ops sin sesión de la cuenta vigente, o todo lo de un token
 * rotado. Guarda el token: hace falta para preguntar `get_cliente_info` y está igual en el almacenamiento viejo.
 */
data class ColaPendiente(
    val token: String,
    val clave: String,
    val firma: FirmaValor?,
    /** De la cuenta vigente al leerla. Si no, es de un token rotado (estacionada). */
    val propia: Boolean,
    val ops: List<OpLegada>,
    val fotos: Map<String, FotoPendiente>,
    val rutinaFoto: String?,
    val estado: Estado,
    val corrida: Int,
    /** La cola de fotos de ese token en la Capacitor ([ColaLegada.claveFotos]). */
    val claveFotos: String? = null,
    val firmaFotos: FirmaValor? = null,
) {
    enum class Estado(val crudo: String) {
        ESPERANDO("esperando"),
        NO_RESUELVE("noResuelve"),
        OTRO_CLIENTE("otroCliente"),
    }

    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("token", texto(token))
            put("clave", texto(clave))
            firma?.let { put("firma", it.aValor()) }
            put("propia", ValorJson.Booleano(propia))
            put("ops", ValorJson.Lista(ops.map { it.aValor() }))
            put("fotos", ValorJson.Objeto(fotos.mapValues { it.value.aValor() }))
            rutinaFoto?.let { put("rutinaFoto", texto(it)) }
            put("estado", texto(estado.crudo))
            put("corrida", numero(corrida))
            claveFotos?.let { put("claveFotos", texto(it)) }
            firmaFotos?.let { put("firmaFotos", it.aValor()) }
        },
    )

    companion object {
        fun desde(v: ValorJson?): ColaPendiente? {
            val o = v as? ValorJson.Objeto ?: return null
            return ColaPendiente(
                token = o["token"]?.comoTexto ?: return null,
                clave = o["clave"]?.comoTexto ?: "",
                firma = FirmaValor.desde(o["firma"]),
                propia = o["propia"] == ValorJson.Booleano(true),
                ops = (o["ops"] as? ValorJson.Lista)?.elementos?.mapNotNull(OpLegada::desde) ?: emptyList(),
                fotos = (o["fotos"] as? ValorJson.Objeto)?.campos?.mapNotNull { (k, f) -> FotoPendiente.desde(f)?.let { k to it } }?.toMap() ?: emptyMap(),
                rutinaFoto = o["rutinaFoto"]?.comoTexto,
                estado = Estado.entries.firstOrNull { it.crudo == o["estado"]?.comoTexto } ?: Estado.ESPERANDO,
                corrida = o["corrida"]?.comoNumero?.let(::enteroTruncado) ?: 0,
                claveFotos = o["claveFotos"]?.comoTexto,
                firmaFotos = FirmaValor.desde(o["firmaFotos"]),
            )
        }
    }
}

/** Archivos de `legado/`, con escritura atómica. Escribir tira: el estado no puede avanzar sobre algo que no quedó. */
internal class ArchivosLegado(val carpeta: File) {
    fun leer(nombre: String): ValorJson? = leerJson(File(carpeta, nombre))?.let(ValorJson::desde)

    fun guardar(v: ValorJson, nombre: String) {
        if (!escribirAtomico(File(carpeta, nombre), v.serializar())) throw IOException("no se pudo escribir legado/$nombre")
    }

    val estado: EstadoMigracion? get() = EstadoMigracion.desde(leer("estado.json"))

    val libro: Map<String, EntradaLibro>
        get() = (leer("libro.json") as? ValorJson.Objeto)?.campos?.mapNotNull { (k, e) -> EntradaLibro.desde(e)?.let { k to it } }?.toMap()
            ?: emptyMap()

    val pendientes: List<ColaPendiente>
        get() = (leer("pendientes.json") as? ValorJson.Lista)?.elementos?.mapNotNull(ColaPendiente::desde) ?: emptyList()

    fun guardarLibro(libro: Map<String, EntradaLibro>) = guardar(ValorJson.Objeto(libro.mapValues { it.value.aValor() }), "libro.json")

    fun guardarPendientes(p: List<ColaPendiente>) = guardar(ValorJson.Lista(p.map { it.aValor() }), "pendientes.json")

    fun guardarEstado(e: EstadoMigracion) = guardar(e.aValor(), "estado.json")
}

/**
 * La Fase L aplicada: lee, copia, planifica y deja todo en su lugar. Sin red, para correr antes de crear el modelo (que lee
 * el token y la cola al iniciar). Gemelo de EjecutorLegado.swift.
 */
object EjecutorLegado {
    data class Resultado(
        /** Había almacenamiento viejo. */
        var huboLegado: Boolean = false,
        /** Corrió (la huella era nueva). false = no había nada que hacer. */
        var corrio: Boolean = false,
        var corrida: Int = 0,
        var repeticion: Boolean = false,
        var tokenVigente: String? = null,
        var adoptoToken: Boolean = false,
        var aLaCola: Int = 0,
        var porValidar: Int = 0,
        var estacionadas: Int = 0,
        var anon: Int = 0,
        var yaEnElLibro: Int = 0,
        var reemplazadas: Int = 0,
        /** La lectura encontró la marca de una escritura de vuelta anterior: llegó al disco. */
        var escrituraConfirmada: Int? = null,
        var plan: PlanMigracion? = null,
    )

    /**
     * @param cuentaViva el token que ya tiene una `Outbox` viva en este proceso (el modelo ya existe). Sus ops no se
     *   escriben al archivo (la cola viva lo pisaría al guardar): van todas a la Fase R, que las importa por la cola viva.
     */
    suspend fun faseLocal(
        entorno: EntornoLegado,
        almacen: AlmacenToken,
        ajustes: Preferencias,
        ahora: Instant = Instant.now(),
        zona: ZoneId = ZoneId.systemDefault(),
        cuentaViva: String? = null,
    ): Resultado {
        val r = Resultado()
        val lector = entorno.lector
        if (!lector.hay()) return r
        r.huboLegado = true
        val a = ArchivosLegado(entorno.carpeta)
        val previo = a.estado
        val huella = lector.huella()
        if (previo != null && previo.huella == huella) {
            // Se escribió de vuelta pero el almacenamiento no cambió: no llegó al disco (el proceso murió antes de que el
            // WebView la bajara). Se repite. Si llegó, la huella cambió y esta misma función la confirma leyendo la marca.
            val hecha = previo.escrituraHecha
            if (hecha != null && hecha > (previo.escrituraConfirmada ?: 0) && previo.escritura == null && previo.escrituraUltima != null) {
                a.guardarEstado(previo.copy(escritura = previo.escrituraUltima))
            }
            return r
        }

        val ms = ahora.toEpochMilli().toDouble()
        var estado = previo ?: EstadoMigracion.nuevo(ms)
        val corrida = estado.corridas + 1
        r.corrida = corrida
        r.repeticion = previo != null

        // 1. La copia cruda, antes de tocar nada. Lleva la huella en el nombre: si una lectura falla y se reintenta en el
        //    arranque siguiente con lo mismo, no se copia de nuevo.
        val h8 = JsonLegado.sha256(JsonLegado.canonico(huella.aValor())).take(8)
        val existente = entorno.crudo.list()?.sorted()?.firstOrNull { it.endsWith("-$h8") }
        val nombreCopia = existente ?: "${sello(ahora)}-$h8"
        if (existente == null) {
            val destino = File(entorno.crudo, nombreCopia)
            destino.mkdirs()
            val copiados = lector.copiarCrudo(destino)
            ArchivosLegado(destino).guardar(
                ValorJson.objeto(
                    "huella" to huella.aValor(), "copiados" to ValorJson.Lista(copiados.map { texto(it) }), "corrida" to numero(corrida),
                ),
                "manifiesto.json",
            )
        }

        // 2. Leer y planificar.
        val lectura = lector.leer() ?: return r
        val contexto = ContextoMigracion(almacen.leer(), ajustes.leer("mypump_token_invalido"), previo?.anterior)
        val plan = MigracionLegado.planificar(lectura.items, lectura.firmas, ahora, zona, contexto)
        r.plan = plan
        r.tokenVigente = plan.tokenVigente

        // 3. Token. Se lee de vuelta: si el almacén no lo guardó (con el Keystore fallando, `TokenEnKeystore` borra el archivo y
        //    no tira), la Fase L quedaba hecha igual (con la huella anotada no vuelve a correr) y la app abría en "pegá tu
        //    link" para siempre (sospecha de la revisión del 15-oct, confirmada en iOS). Así no queda hecha: todavía no se
        //    escribió nada más (la copia cruda ya está y no se repite) y se reintenta con la app abierta o en el arranque
        //    siguiente (`ArranqueMigracion`).
        val vigente = plan.tokenVigente
        if (plan.adoptarToken && vigente != null) {
            almacen.guardar(vigente)
            if (almacen.leer() != vigente) throw IOException("el almacén no guardó el token adoptado")
            r.adoptoToken = true
        }

        // 4. Ajustes: en la primera corrida no se pisa uno que la nativa ya tenga; en una repetición, lo que cambió en la
        //    Capacitor es lo último que hizo el cliente.
        for ((k, v) in plan.preferencias) if (previo != null || ajustes.leer(k) == null) ajustes.guardar(k, v)

        // 5. Lo de la cuenta vigente.
        val libro = LinkedHashMap(a.libro)
        val pendientes = a.pendientes.toMutableList()
        val borrar = LinkedHashMap(estado.escritura?.borrar ?: emptyMap())
        if (vigente != null) {
            val disco = entorno.disco(vigente)
            plan.entreno?.let { guardarEntreno(it, disco) }
            plan.copiaOffline?.let { c ->
                val actual = ModeloApp.CopiaOffline.desde(disco.leer(ModeloApp.ARCHIVO_COPIA))
                if (actual == null || actual.ts < c.ts) disco.guardar(ModeloApp.ARCHIVO_COPIA, ModeloApp.CopiaOffline(c.info, c.rutina, c.dieta, c.ts).aValor())
            }
            for ((rutina, s) in plan.sustituciones) {
                val nombre = SustitucionEjercicio.archivo(rutina)
                val legado = s.mapValues { it.value.aValor() }
                if (previo == null) {
                    if (!disco.archivo(nombre).exists()) disco.guardar(nombre, ValorJson.Objeto(legado))
                } else {
                    // El cliente volvió a la app vieja y cambió algo ahí. SER-14: solo lo que cambió AHÍ desde la corrida
                    // anterior pisa lo del teléfono (con la hora de ahora, para que gane también en el servidor) y lo que
                    // sacó ahí se saca; lo hecho en la nativa o llegado de otro teléfono queda. Antes se pisaba todo.
                    val nativa = mapaDe(disco.leer(nombre)) ?: emptyMap()
                    val base = mapaDe(disco.leer(SustitucionesServidor.archivoLegado(rutina)))
                    // Lo que había se toma como ya subido: así lo que se saca sale como borrado y lo cambiado como guardado.
                    val encoladas = SustitucionesServidor.archivoEncoladas(rutina)
                    if (!disco.archivo(encoladas).exists()) disco.guardar(encoladas, ValorJson.Objeto(nativa))
                    disco.guardar(nombre, ValorJson.Objeto(SustitucionesServidor.volverDeLaAppVieja(nativa, legado, base, ms)))
                }
                // Lo que se leyó de la app vieja: la base para la próxima vuelta.
                disco.guardar(SustitucionesServidor.archivoLegado(rutina), ValorJson.Objeto(legado))
            }
            for ((dieta, s) in plan.swapsComida) {
                // El mapa local es una caché del servidor: si la nativa ya tiene el suyo, gana el suyo.
                if (s.swaps.isNotEmpty() && !disco.archivo("swaps_$dieta.json").exists()) disco.guardar("swaps_$dieta.json", swapsAValor(s.swaps))
                val marca = (disco.leer("swaps_migrados_$dieta") as? JsonPrimitive)?.booleanOrNull
                if (s.migrados && marca != true) disco.guardar("swaps_migrados_$dieta", JsonPrimitive(true))
            }
        }

        // 6. Las colas.
        for (q in plan.colas) {
            val nuevas = q.ops.filter { it.idLibro !in libro }
            r.yaEnElLibro += q.ops.size - nuevas.size
            when (q.tipo) {
                ColaLegada.Tipo.ANON -> {
                    for (op in nuevas) libro[op.idLibro] = EntradaLibro(EntradaLibro.Destino.ANON, op.operacion.kind, corrida)
                    r.anon += nuevas.size
                }
                ColaLegada.Tipo.VIGENTE -> {
                    val t = q.token ?: continue
                    val disco = entorno.disco(t)
                    val alArchivo = t != cuentaViva
                    val directas = if (alArchivo) nuevas.filter { !it.necesitaValidar } else emptyList()
                    val aLaFaseR = if (alArchivo) nuevas.filter { it.necesitaValidar } else nuevas
                    if (directas.isNotEmpty()) {
                        val quedaron = Outbox.importarEnArchivo(disco.archivo("outbox.json"), directas.map { it.operacion }).map { it.id }.toSet()
                        for (op in directas) {
                            val entro = op.operacion.id in quedaron
                            libro[op.idLibro] = EntradaLibro(if (entro) EntradaLibro.Destino.COLA else EntradaLibro.Destino.REEMPLAZADA, op.operacion.kind, corrida)
                            if (entro) r.aLaCola++ else r.reemplazadas++
                        }
                    }
                    if (aLaFaseR.isNotEmpty()) {
                        encolarPendiente(pendientes, t, q, aLaFaseR, emptyMap(), propia = true, corrida = corrida)
                        for (op in aLaFaseR) {
                            val destino = if (op.necesitaValidar) EntradaLibro.Destino.POR_VALIDAR else EntradaLibro.Destino.ESTACIONADA
                            libro[op.idLibro] = EntradaLibro(destino, op.operacion.kind, corrida)
                        }
                        r.porValidar += aLaFaseR.size
                    }
                    if (q.fotos.isNotEmpty()) sumarFotos(q.fotos, disco)
                    if (!q.valorIlegible) q.firma?.let { borrar[q.clave] = it }
                    if (q.claveFotos != null && q.firmaFotos != null) borrar[q.claveFotos] = q.firmaFotos
                }
                ColaLegada.Tipo.OTRO_TOKEN -> {
                    val t = q.token ?: continue
                    if (nuevas.isEmpty() && q.fotos.isEmpty()) continue
                    encolarPendiente(pendientes, t, q, nuevas, q.fotos, propia = false, corrida = corrida)
                    for (op in nuevas) libro[op.idLibro] = EntradaLibro(EntradaLibro.Destino.ESTACIONADA, op.operacion.kind, corrida)
                    r.estacionadas += nuevas.size
                }
            }
        }

        // 7. La escritura de vuelta: los cachés de sesión, y la marca si no está la de esta migración.
        borrar.putAll(plan.sesionesParaBorrar)
        val marca = Marca.leer(plan.marcaLeida)
        if (marca != null && marca.migracion == estado.migracion) {
            r.escrituraConfirmada = marca.corrida
            estado = estado.copy(escrituraConfirmada = maxOf(estado.escrituraConfirmada ?: 0, marca.corrida))
        }
        val falta = borrar.isNotEmpty() || r.escrituraConfirmada == null
        estado = estado.copy(escritura = if (falta) EscrituraPendiente(corrida, borrar) else null)

        // 8. Primero lo que ya quedó en la cola (arriba), después el libro y por último el estado: si el proceso muere en el
        //    medio, la corrida se repite y la cola no duplica (mismo id).
        a.guardarLibro(libro)
        a.guardarPendientes(pendientes)
        estado = estado.copy(
            corridas = corrida,
            ultima = ms,
            huella = lectura.huella,
            anterior = CorridaAnterior(plan.huellasClaves, plan.tokenLegadoHash),
            conteos = plan.conteos,
            copias = if (nombreCopia in estado.copias) estado.copias else estado.copias + nombreCopia,
            faseRPendiente = estado.faseRPendiente || pendientes.any { it.estado == ColaPendiente.Estado.ESPERANDO } || estado.escritura != null ||
                r.aLaCola > 0 || r.porValidar > 0,
        )
        a.guardarEstado(estado)
        r.corrio = true
        return r
    }

    internal fun encolarPendiente(
        pendientes: MutableList<ColaPendiente>,
        token: String,
        q: ColaLegada,
        ops: List<OpLegada>,
        fotos: Map<String, FotoPendiente>,
        propia: Boolean,
        corrida: Int,
    ) {
        val i = pendientes.indexOfFirst { it.token == token && it.propia == propia }
        if (i >= 0) {
            val p = pendientes[i]
            val ya = p.ops.map { it.idLibro }.toSet()
            pendientes[i] = p.copy(
                ops = p.ops + ops.filter { it.idLibro !in ya },
                fotos = mezclarFotos(p.fotos, fotos),
                firma = q.firma ?: p.firma,
                rutinaFoto = q.rutinaFoto ?: p.rutinaFoto,
                estado = ColaPendiente.Estado.ESPERANDO,
                corrida = corrida,
                claveFotos = if (q.firmaFotos != null) q.claveFotos else p.claveFotos,
                firmaFotos = q.firmaFotos ?: p.firmaFotos,
            )
        } else {
            pendientes += ColaPendiente(token, q.clave, q.firma, propia, ops, fotos, q.rutinaFoto, ColaPendiente.Estado.ESPERANDO, corrida,
                q.claveFotos, q.firmaFotos)
        }
    }

    /** Por `"<lunes>|<pose>"`, gana la foto más nueva. */
    private fun mezclarFotos(actuales: Map<String, FotoPendiente>, nuevas: Map<String, FotoPendiente>): Map<String, FotoPendiente> {
        val m = LinkedHashMap(actuales)
        for ((k, nueva) in nuevas) {
            val actual = m[k]
            m[k] = if (actual == null || nueva.fecha >= actual.fecha) nueva else actual
        }
        return m
    }

    /** Junta con lo que la cuenta ya tenía: por `"<lunes>|<pose>"`, gana la foto más nueva. */
    internal fun sumarFotos(fotos: Map<String, FotoPendiente>, disco: Disco) {
        val actuales = (disco.leer(FotoPendiente.ARCHIVO)?.let(ValorJson::desde) as? ValorJson.Objeto)?.campos
            ?.mapNotNull { (k, f) -> FotoPendiente.desde(f)?.let { k to it } }?.toMap() ?: emptyMap()
        disco.guardar(FotoPendiente.ARCHIVO, ValorJson.Objeto(mezclarFotos(actuales, fotos).mapValues { it.value.aValor() }))
    }

    /** Por día gana lo leído ahora; el descanso, si hay uno nuevo. */
    internal fun guardarEntreno(e: EntrenoLegado, disco: Disco) {
        val actual = EntrenoLegado.desde(disco.leer(EntrenoLegado.ARCHIVO)?.let(ValorJson::desde)) ?: EntrenoLegado()
        disco.guardar(
            EntrenoLegado.ARCHIVO,
            EntrenoLegado(actual.sesiones + e.sesiones, e.descanso ?: actual.descanso, actual.diaVisualizado + e.diaVisualizado).aValor(),
        )
    }

    private fun swapsAValor(swaps: Map<String, SwapLocal>): ValorJson = ValorJson.Objeto(
        swaps.mapValues { (_, s) ->
            ValorJson.Objeto(
                buildMap {
                    s.original?.let { put("original", it) }
                    put("current", s.current)
                },
            )
        },
    )

    internal fun sello(d: Instant): String = DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'", Locale.ROOT).withZone(ZoneOffset.UTC).format(d)
}

/**
 * `mypump_nativa_marca`: la deja la escritura de vuelta. Leerla en el arranque siguiente confirma que llegó al disco.
 */
data class Marca(val migracion: String, val corrida: Int, val fecha: String, val app: String? = null) {
    /** JSON con las claves ordenadas, como lo escribe iOS. */
    val texto: String
        get() = ValorJson.Objeto(
            sortedMapOf<String, ValorJson>().apply {
                app?.let { put("app", texto(it)) }
                put("corrida", numero(corrida))
                put("fecha", texto(fecha))
                put("migracion", texto(migracion))
            },
        ).serializar()

    companion object {
        fun leer(s: String?): Marca? {
            val j = s?.let(JsonLegado::parsear) as? ValorJson.Objeto ?: return null
            val migracion = j["migracion"]?.comoTexto ?: return null
            val corrida = j["corrida"]?.comoNumero?.takeIf { it == Math.rint(it) && Math.abs(it) < Int.MAX_VALUE } ?: return null
            val fecha = j["fecha"]?.comoTexto ?: return null
            val app = when (val a = j["app"]) {
                null, ValorJson.Nulo -> null
                is ValorJson.Texto -> a.valor
                else -> return null
            }
            return Marca(migracion, corrida.toInt(), fecha, app)
        }
    }
}

/** Un mapa JSON del disco (`exId → entrada`), o null si no hay. */
private fun mapaDe(e: JsonElement?): Map<String, ValorJson>? = (e as? JsonObject)?.mapValues { ValorJson.desde(it.value) }
