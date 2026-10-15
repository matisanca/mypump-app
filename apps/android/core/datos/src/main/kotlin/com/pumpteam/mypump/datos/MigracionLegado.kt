package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.NumeroSwift
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.SwapLocal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

// La migración del almacenamiento viejo (la app Capacitor, `localStorage` del WebView) a la nativa. Dos fases, como en
// iOS (MigracionLegado.swift):
//
// - Fase L, local y sin red, antes de crear el modelo: `planificar` (función pura, este archivo) decide todo a partir de
//   las claves; `EjecutorLegado` lo aplica (token, ajustes, archivos de la cuenta, cola).
// - Fase R, con red, después del primer `get_cliente_info`: `FaseRemotaLegado` valida las ops que no traen sesión,
//   reasigna las colas de tokens rotados, deja el recibo y arma la escritura de vuelta.
//
// Idempotente y repetible: el libro mayor anota cada op importada (id = sha256 de su contenido, porque hay formatos sin
// `_id`), y si la huella del almacenamiento cambia (alguien volvió a la Capacitor) la Fase L corre de nuevo.

// MARK: Lo que la web guardaba y la nativa todavía no modela (los lee Entreno)

/**
 * `legado-entreno.json`, en la carpeta de la cuenta: lo de Entreno que vivía solo en el teléfono, con los campos de la
 * web. Lo lee el modelo de Entreno ([LegadoEntreno.leer]); la migración solo lo deja.
 */
data class EntrenoLegado(
    /** Por día: `mypump_sesion_<T>_<diaId>` y sus sufijos. Solo las vigentes: sin cerrar y con el arranque hace menos de
     *  `SESION_MAX_H` (6 h). */
    val sesiones: Map<String, SesionLegada> = emptyMap(),
    /** `mypump_rest_<T>`: el descanso en curso, si `autoCloseAt` no pasó. */
    val descanso: DescansoLegado? = null,
    /** `mypump_dia_visualizado_<rutinaId>` → `diaId`. */
    val diaVisualizado: Map<String, String> = emptyMap(),
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("sesiones", ValorJson.Objeto(sesiones.mapValues { it.value.aValor() }))
            descanso?.let { put("descanso", it.aValor()) }
            put("diaVisualizado", ValorJson.Objeto(diaVisualizado.mapValues { texto(it.value) }))
        },
    )

    companion object {
        const val ARCHIVO = "legado-entreno.json"

        fun desde(v: ValorJson?): EntrenoLegado? {
            val o = v as? ValorJson.Objeto ?: return null
            return EntrenoLegado(
                sesiones = (o["sesiones"] as? ValorJson.Objeto)?.campos?.mapNotNull { (k, s) -> SesionLegada.desde(s)?.let { k to it } }?.toMap()
                    ?: emptyMap(),
                descanso = DescansoLegado.desde(o["descanso"]),
                diaVisualizado = (o["diaVisualizado"] as? ValorJson.Objeto)?.campos?.mapNotNull { (k, d) -> d.comoTexto?.let { k to it } }?.toMap()
                    ?: emptyMap(),
            )
        }
    }
}

data class SesionLegada(
    /** El valor de `mypump_sesion_<T>_<diaId>` (uuid de `iniciar_sesion`). */
    val sesionId: String? = null,
    /** `_semana`: la semana de la rutina en la que se abrió. */
    val semana: Int? = null,
    /** `_start`: ms desde 1970 (`Date.now()`). */
    val start: Double? = null,
    /** `_finalizada === '1'`. */
    val finalizada: Boolean = false,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            sesionId?.let { put("sesionId", texto(it)) }
            semana?.let { put("semana", numero(it)) }
            start?.let { put("start", numero(it)) }
            put("finalizada", ValorJson.Booleano(finalizada))
        },
    )

    companion object {
        fun desde(v: ValorJson?): SesionLegada? {
            if (v !is ValorJson.Objeto) return null
            return SesionLegada(
                v["sesionId"]?.comoTexto, v["semana"]?.comoNumero?.let(::enteroTruncado), v["start"]?.comoNumero,
                v["finalizada"] == ValorJson.Booleano(true),
            )
        }
    }
}

/** `{endsAt, target, autoCloseAt}`: anclas de reloj en ms (`target` en segundos), como `persistRest`. */
data class DescansoLegado(val endsAt: Double, val target: Double, val autoCloseAt: Double) {
    fun aValor(): ValorJson = ValorJson.objeto("endsAt" to numero(endsAt), "target" to numero(target), "autoCloseAt" to numero(autoCloseAt))

    companion object {
        fun desde(v: ValorJson?): DescansoLegado? {
            val e = v?.get("endsAt")?.comoNumero ?: return null
            val t = v["target"]?.comoNumero ?: return null
            val c = v["autoCloseAt"]?.comoNumero ?: return null
            return DescansoLegado(e, t, c)
        }
    }
}

/**
 * `ejercicios-swaps_<rutinaId>.json`: `mypump_exercise_swaps_<RUTINA_ID>` (`exId` del lugar → sustitución), el mismo
 * archivo que lee y escribe el modelo de Entreno. La poda (las no fijadas valen por su día y su semana) la hace Entreno al
 * cargar, como `pruneExerciseSwaps` en el arranque de la web.
 */
data class SustitucionEjercicio(
    val original: Ejercicio,
    val current: Ejercicio,
    /** Una entrada sin `fijado` cuenta como fijada: se eligió cuando el swap era permanente (compat de la web, F5). */
    val fijado: Boolean,
    val semana: Int?,
    val diaId: String?,
) {
    data class Ejercicio(
        val slug: String? = null,
        val nombre: String? = null,
        val equipment: String? = null,
        /** `{eccentric, concentric, _matched_slug}` o null, tal cual. */
        val images: ValorJson? = null,
    ) {
        fun aValor(): ValorJson = ValorJson.Objeto(
            buildMap {
                slug?.let { put("slug", texto(it)) }
                nombre?.let { put("nombre", texto(it)) }
                equipment?.let { put("equipment", texto(it)) }
                images?.let { put("images", it) }
            },
        )
    }

    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("original", original.aValor())
            put("current", current.aValor())
            put("fijado", ValorJson.Booleano(fijado))
            semana?.let { put("semana", numero(it)) }
            diaId?.let { put("diaId", texto(it)) }
        },
    )

    companion object {
        fun archivo(rutinaId: String): String = "ejercicios-swaps_$rutinaId.json"
    }
}

/**
 * `mypump_food_swaps_<DIETA>` (el mismo mapa que usa ModeloApp: `swaps_<dieta>.json`) y si la web ya los había subido
 * (`mypump_swaps_migrados_<DIETA>`). Sin la marca, la primera hidratación de la nativa los ancla y los sube por la cola.
 */
data class SwapsComidaLegado(val swaps: Map<String, SwapLocal>, val migrados: Boolean)

/** `mypump_offline_<T>`: `{info, rutina, dieta, ts}`, la misma forma que `offline.json` de ModeloApp. */
data class CopiaOfflineLegada(val info: ValorJson, val rutina: ValorJson?, val dieta: ValorJson?, val ts: Double)

// MARK: Las colas

/** Una op de la cola vieja, ya con la forma nativa. */
data class OpLegada(
    /** sha256(clave + índice + kind + dedupeKey + ts + payload canónico). El índice es el ordinal entre ops IDÉNTICAS de
     *  la misma cola: si la Capacitor drena una de adelante, las de atrás no cambian de id. */
    val idLibro: String,
    val operacion: Operacion,
    /** `carga` o `estado` sin `sesionId`: antes de mandarla hay que confirmar que su día sigue en la rutina activa. */
    val necesitaValidar: Boolean,
) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "idLibro" to texto(idLibro), "operacion" to operacion.aValor(), "necesitaValidar" to ValorJson.Booleano(necesitaValidar),
    )

    companion object {
        fun desde(v: ValorJson?): OpLegada? {
            val id = v?.get("idLibro")?.comoTexto ?: return null
            val op = v["operacion"]?.let { Operacion.desde(it.aJson()) } ?: return null
            return OpLegada(id, op, v["necesitaValidar"] == ValorJson.Booleano(true))
        }
    }
}

/** Lo que dejó una cuenta (un token) para mandar: su cola de escrituras y su cola de fotos. */
data class ColaLegada(
    val clave: String,
    val tipo: Tipo,
    val token: String?,
    val ops: List<OpLegada> = emptyList(),
    /** Entradas que no son una op (sin `kind`): la web las descarta igual. Quedan en la copia cruda. */
    val ilegibles: Int = 0,
    /** El valor entero no era JSON: no se importa nada y la clave no se toca. */
    val valorIlegible: Boolean = false,
    /** La de la clave entera, para borrarla en la escritura de vuelta solo si no cambió. */
    val firma: FirmaValor? = null,
    val fotos: Map<String, FotoPendiente> = emptyMap(),
    /** `rutina.id` de la foto offline de ESE token: contra qué rutina se cargaron las ops sin sesión. */
    val rutinaFoto: String? = null,
    /**
     * `mypump_fotoq_<T>` y su firma: la escritura de vuelta la borra (si no cambió) cuando sus fotos ya pasaron a la
     * nativa. Si quedaba, la Capacitor (el plan B) volvía a subir esas fotos y podía pisar una más nueva de la misma semana
     * y pose (lo encontró el agente de MIG-03, 15-oct; gemelo de iOS 549fdba).
     */
    val claveFotos: String? = null,
    val firmaFotos: FirmaValor? = null,
) {
    enum class Tipo(val crudo: String) {
        /** La cuenta que queda guardada. */
        VIGENTE("vigente"),

        /** `mypump_outbox_anon`: sin token (la demo, o antes de pegar el link). Nunca se ejecuta. */
        ANON("anon"),

        /** Un token rotado: se estaciona y en la Fase R se reasigna solo si resuelve al mismo `cliente_id`. */
        OTRO_TOKEN("otroToken"),
    }
}

// MARK: Contexto y plan

/** Lo que ya hay del lado nativo y lo que dejó la corrida anterior: hace falta para no pisar lo que la nativa ya tiene. */
data class ContextoMigracion(
    val tokenNativo: String? = null,
    /** `mypump_token_invalido` de la nativa (ModeloApp lo anota cuando la base dice que el link ya no sirve). */
    val tokenInvalidoNativo: String? = null,
    /** null = primera corrida. */
    val anterior: CorridaAnterior? = null,
)

/** Lo mínimo de la corrida anterior para saber qué cambió desde entonces. Sin tokens ni valores: solo hashes. */
data class CorridaAnterior(
    /** sha256(clave) → sha256(valor). */
    val huellasClaves: Map<String, String> = emptyMap(),
    /** sha256 del `mypump_token` legado que se leyó. */
    val tokenLegado: String? = null,
) {
    fun aValor(): ValorJson = ValorJson.Objeto(
        buildMap {
            put("huellasClaves", ValorJson.Objeto(huellasClaves.mapValues { texto(it.value) }))
            tokenLegado?.let { put("tokenLegado", texto(it)) }
        },
    )

    companion object {
        fun desde(v: ValorJson?): CorridaAnterior = CorridaAnterior(
            (v?.get("huellasClaves") as? ValorJson.Objeto)?.campos?.mapNotNull { (k, x) -> x.comoTexto?.let { k to it } }?.toMap() ?: emptyMap(),
            v?.get("tokenLegado")?.comoTexto,
        )
    }
}

/** Todo lo que hay que hacer, tipado. Lo produce [MigracionLegado.planificar] sin tocar nada. */
data class PlanMigracion(
    // Acceso
    /** `mypump_token` con forma válida y que no es el marcado como inválido (ni del lado web ni del nativo). */
    var tokenLegado: String? = null,
    /** Había un `mypump_token` pero no se usa (marcado inválido o con forma rara). */
    var tokenDescartado: Boolean = false,
    /** La cuenta que queda después de migrar: la nativa, o la legada si no había o si la Capacitor cambió de link después
     *  de la última migración. */
    var tokenVigente: String? = null,
    /** Guardar `tokenVigente` en el almacén del token. */
    var adoptarToken: Boolean = false,
    /** Ajustes nativos, con la misma clave que la web. En una repetición, solo los que cambiaron. */
    val preferencias: MutableMap<String, String> = LinkedHashMap(),
    // De la cuenta vigente
    var entreno: EntrenoLegado? = null,
    var copiaOffline: CopiaOfflineLegada? = null,
    /** rutinaId → exId → sustitución (sin las `_demo`). */
    val sustituciones: MutableMap<String, Map<String, SustitucionEjercicio>> = LinkedHashMap(),
    /** dietaId → swaps (sin las `_demo`). */
    val swapsComida: MutableMap<String, SwapsComidaLegado> = LinkedHashMap(),
    var colas: List<ColaLegada> = emptyList(),
    // Escritura de vuelta
    /** `mypump_sesion_*`: cachés que la Capacitor usaría vencidos si alguien vuelve a ella. Se borran. */
    val sesionesParaBorrar: MutableMap<String, FirmaValor> = LinkedHashMap(),
    /** `mypump_nativa_marca` tal como estaba (la deja la escritura de vuelta; leerla confirma que llegó al disco). */
    var marcaLeida: String? = null,
    // Repetición y recibo
    var huellasClaves: Map<String, String> = emptyMap(),
    var tokenLegadoHash: String? = null,
    var conteos: ConteosLegado = ConteosLegado(),
)

/** Conteos para el recibo, sin contenido crudo ni claves con token. */
data class ConteosLegado(
    var claves: Int = 0,
    var unidadesUTF16: Int = 0,
    val opsPorKind: MutableMap<String, Int> = LinkedHashMap(),
    val opsPorCola: MutableMap<String, Int> = LinkedHashMap(),
    var opsSinSesion: Int = 0,
    var opsIlegibles: Int = 0,
    var colasIlegibles: Int = 0,
    var fotos: Int = 0,
    var fotosFueraDeVentana: Int = 0,
    var sustituciones: Int = 0,
    var swapsComida: Int = 0,
    var sesionesVigentes: Int = 0,
    var sesionesVencidas: Int = 0,
    var descansoVigente: Boolean = false,
    var preferencias: Int = 0,
    /** Claves de la demo (`*_demo`) o sin cuenta (token vacío): nunca se aplican. */
    var demo: Int = 0,
    var ignoradas: Int = 0,
    var desconocidas: Int = 0,
) {
    fun aValor(): ValorJson = ValorJson.objeto(
        "claves" to numero(claves), "unidadesUTF16" to numero(unidadesUTF16),
        "opsPorKind" to ValorJson.Objeto(opsPorKind.mapValues { numero(it.value) }),
        "opsPorCola" to ValorJson.Objeto(opsPorCola.mapValues { numero(it.value) }),
        "opsSinSesion" to numero(opsSinSesion), "opsIlegibles" to numero(opsIlegibles), "colasIlegibles" to numero(colasIlegibles),
        "fotos" to numero(fotos), "fotosFueraDeVentana" to numero(fotosFueraDeVentana), "sustituciones" to numero(sustituciones),
        "swapsComida" to numero(swapsComida), "sesionesVigentes" to numero(sesionesVigentes), "sesionesVencidas" to numero(sesionesVencidas),
        "descansoVigente" to ValorJson.Booleano(descansoVigente), "preferencias" to numero(preferencias), "demo" to numero(demo),
        "ignoradas" to numero(ignoradas), "desconocidas" to numero(desconocidas),
    )

    companion object {
        fun desde(v: ValorJson?): ConteosLegado {
            fun n(k: String): Int = v?.get(k)?.comoNumero?.let(::enteroTruncado) ?: 0
            fun mapa(k: String): MutableMap<String, Int> =
                (v?.get(k) as? ValorJson.Objeto)?.campos?.mapNotNull { (c, x) -> x.comoNumero?.let { c to enteroTruncado(it) } }?.toMap(LinkedHashMap())
                    ?: LinkedHashMap()
            return ConteosLegado(
                n("claves"), n("unidadesUTF16"), mapa("opsPorKind"), mapa("opsPorCola"), n("opsSinSesion"), n("opsIlegibles"), n("colasIlegibles"),
                n("fotos"), n("fotosFueraDeVentana"), n("sustituciones"), n("swapsComida"), n("sesionesVigentes"), n("sesionesVencidas"),
                v?.get("descansoVigente") == ValorJson.Booleano(true), n("preferencias"), n("demo"), n("ignoradas"), n("desconocidas"),
            )
        }
    }
}

// MARK: Fase L, la parte pura

object MigracionLegado {
    /** `SESION_MAX_H` de la web. */
    internal const val SESION_MAXIMA: Double = 6.0 * 3600 * 1000

    /** Claves de salud que se pasan tal cual (las lee el sincronizador nativo). `mypump_health_diag` no: es un
     *  diagnóstico de la Capacitor. */
    internal val clavesSalud: Set<String> = setOf(
        "mypump_health_connected", "mypump_health_denegado", "mypump_health_racha_vacia", "mypump_health_backfill_v1",
        "mypump_health_backfill_off", "mypump_health_backfill_intento", "mypump_health_historial_ok", "mypump_health_last_sync",
    )

    /** Cachés y registros que la nativa rehace por su cuenta. */
    internal val clavesIgnoradas: Set<String> = setOf(
        "mypump_health_diag", "mypump_push_token", "mypump_push_web_endpoint", "mypump_ejercicio_catalogo_v1",
        "mypump_a2hs_v1", "mypump_dl_pospuesto", "mypump_reload_online",
    )

    const val CLAVE_MARCA = "mypump_nativa_marca"

    /** La Fase L sin tocar nada: de las claves del `localStorage` viejo a todo lo que hay que hacer. */
    fun planificar(
        items: Map<String, String>,
        firmas: Map<String, FirmaValor> = emptyMap(),
        ahora: Instant,
        zona: ZoneId = ZoneId.systemDefault(),
        contexto: ContextoMigracion = ContextoMigracion(),
    ): PlanMigracion {
        val plan = PlanMigracion()
        val ms = ahora.toEpochMilli().toDouble()
        val primera = contexto.anterior == null
        val huellas = HashMap<String, String>()
        for ((k, v) in items) huellas[JsonLegado.sha256(k)] = JsonLegado.sha256(v)
        plan.huellasClaves = huellas

        /** En una repetición, lo que no cambió ya se aplicó (y la nativa pudo haberlo cambiado después): no se pisa. */
        fun cambio(k: String): Boolean {
            val ant = contexto.anterior ?: return true
            return ant.huellasClaves[JsonLegado.sha256(k)] != huellas[JsonLegado.sha256(k)]
        }
        val c = ConteosLegado()
        c.claves = items.size
        c.unidadesUTF16 = items.values.sumOf { it.length }

        // 1. Acceso: el token legado, respetando los marcados como inválidos.
        val invalidoWeb = items["mypump_token_invalido"]
        items["mypump_token"]?.let { t ->
            if (FormatoToken.valido(t) && t != invalidoWeb && t != contexto.tokenInvalidoNativo) plan.tokenLegado = t else plan.tokenDescartado = true
        }
        plan.tokenLegadoHash = plan.tokenLegado?.let(JsonLegado::sha256)
        val nativo = contexto.tokenNativo
        val legado = plan.tokenLegado
        when {
            nativo == null -> {
                plan.tokenVigente = legado
                plan.adoptarToken = legado != null
            }
            // La Capacitor cambió de link DESPUÉS de la última migración: es lo último que hizo el cliente.
            legado != null && legado != nativo && !primera && plan.tokenLegadoHash != contexto.anterior.tokenLegado -> {
                plan.tokenVigente = legado
                plan.adoptarToken = true
            }
            else -> plan.tokenVigente = nativo
        }
        val vigente = plan.tokenVigente

        // 2. Clasificar todas las claves. Por token; las que no tienen token (`anon`, o un sufijo que no es un token) van
        //    cada una aparte.
        val colas = LinkedHashMap<String, ColaLegada>()
        fun cola(token: String, clave: String): ColaLegada {
            colas[token.ifEmpty { clave }]?.let { return it }
            val tipo = if (token.isEmpty()) ColaLegada.Tipo.ANON else if (token == vigente) ColaLegada.Tipo.VIGENTE else ColaLegada.Tipo.OTRO_TOKEN
            return ColaLegada(clave = if (token.isEmpty()) clave else "mypump_outbox_$token", tipo = tipo, token = token.ifEmpty { null })
        }
        fun tokenDe(s: String): String = if (FormatoToken.valido(s)) s else ""
        val sesiones = HashMap<String, SesionLegada>()
        val sesionCambio = HashSet<String>()
        val sesionesEntreno = LinkedHashMap<String, SesionLegada>()
        var descansoEntreno: DescansoLegado? = null
        val diaVisualizado = LinkedHashMap<String, String>()
        var entrenoCambio = false

        for (k in items.keys.sorted()) {
            val v = items.getValue(k)
            if (k == "mypump_token" || k == CLAVE_MARCA) continue
            if (k in clavesIgnoradas) {
                c.ignoradas++
                continue
            }
            val outbox = sufijo(k, "mypump_outbox_")
            val fotoq = sufijo(k, "mypump_fotoq_")
            val offline = sufijo(k, "mypump_offline_")
            val rest = sufijo(k, "mypump_rest_")
            val swapsEj = sufijo(k, "mypump_exercise_swaps_")
            val swapsComida = sufijo(k, "mypump_food_swaps_")
            val migrados = sufijo(k, "mypump_swaps_migrados_")
            val visualizado = sufijo(k, "mypump_dia_visualizado_")
            when {
                outbox != null -> {
                    val token = if (outbox == "anon") "" else tokenDe(outbox)
                    var q = cola(token, k).copy(clave = k, firma = firmas[k])
                    val lista = JsonLegado.parsear(v) as? ValorJson.Lista
                    if (lista != null) {
                        val (ops, ilegibles) = leerOps(lista.elementos, k)
                        q = q.copy(ops = ops, ilegibles = ilegibles)
                    } else {
                        q = q.copy(valorIlegible = true)
                        c.colasIlegibles++
                    }
                    colas[token.ifEmpty { k }] = q
                }
                fotoq != null -> {
                    val token = tokenDe(fotoq)
                    if (token.isEmpty()) {
                        c.demo++
                        continue
                    }
                    // Solo si la web la puede leer (un objeto): un valor roto no se importa y la clave no se toca.
                    val legible = JsonLegado.parsear(v) is ValorJson.Objeto
                    colas[token] = cola(token, k).copy(
                        fotos = leerFotos(v),
                        claveFotos = if (legible) k else null,
                        firmaFotos = if (legible) firmas[k] else null,
                    )
                }
                offline != null -> {
                    val token = tokenDe(offline)
                    if (token.isEmpty()) {
                        c.demo++
                        continue
                    }
                    val copia = leerCopiaOffline(v)
                    JsonLegado.texto(copia?.rutina?.get("id"))?.let { id -> colas[token] = cola(token, k).copy(rutinaFoto = id) }
                    if (token == vigente && copia != null && cambio(k)) plan.copiaOffline = copia
                }
                rest != null -> {
                    if (vigente == null || rest != vigente) {
                        if (tokenDe(rest).isEmpty()) c.demo++
                        continue
                    }
                    val d = leerDescanso(v)
                    if (d != null && d.autoCloseAt > ms) {
                        c.descansoVigente = true
                        if (cambio(k)) {
                            descansoEntreno = d
                            entrenoCambio = true
                        }
                    }
                }
                k.startsWith("mypump_sesion_") -> {
                    plan.sesionesParaBorrar[k] = firmas[k] ?: FirmaValor.de(v)
                    if (vigente == null) continue
                    val resto = sufijo(k, "mypump_sesion_${vigente}_")
                    if (resto.isNullOrEmpty()) continue
                    var dia = resto
                    val s: SesionLegada
                    val semana = sinFinal(resto, "_semana")
                    val start = sinFinal(resto, "_start")
                    val finalizada = sinFinal(resto, "_finalizada")
                    when {
                        semana != null -> {
                            dia = semana
                            s = (sesiones[dia] ?: SesionLegada()).copy(semana = enteroSwift(NumeroSwift.recortarEspacios(v)))
                        }
                        start != null -> {
                            dia = start
                            s = (sesiones[dia] ?: SesionLegada()).copy(start = NumeroSwift.desdeTexto(NumeroSwift.recortarEspacios(v)))
                        }
                        finalizada != null -> {
                            dia = finalizada
                            s = (sesiones[dia] ?: SesionLegada()).copy(finalizada = v == "1")
                        }
                        else -> s = (sesiones[dia] ?: SesionLegada()).copy(sesionId = v)
                    }
                    sesiones[dia] = s
                    if (cambio(k)) sesionCambio += dia
                }
                swapsEj != null -> {
                    if (swapsEj == "demo" || !nombreSeguro(swapsEj)) {
                        c.demo++
                        continue
                    }
                    val s = leerSustituciones(v)
                    c.sustituciones += s.size
                    if (s.isNotEmpty() && cambio(k)) plan.sustituciones[swapsEj] = s
                }
                swapsComida != null -> {
                    if (swapsComida == "demo" || !nombreSeguro(swapsComida)) {
                        c.demo++
                        continue
                    }
                    val swaps = leerSwapsComida(v)
                    c.swapsComida += swaps.size
                    val yaMigrados = items["mypump_swaps_migrados_$swapsComida"] == "1"
                    if (swaps.isNotEmpty() || yaMigrados) plan.swapsComida[swapsComida] = SwapsComidaLegado(swaps, yaMigrados)
                }
                migrados != null -> {
                    if (migrados == "demo" || !nombreSeguro(migrados)) {
                        c.demo++
                        continue
                    }
                    if (v == "1" && items["mypump_food_swaps_$migrados"] == null) plan.swapsComida[migrados] = SwapsComidaLegado(emptyMap(), true)
                }
                visualizado != null -> {
                    if (visualizado == "demo" || v.isEmpty()) {
                        c.demo++
                        continue
                    }
                    c.preferencias++
                    if (cambio(k)) {
                        plan.preferencias[k] = v
                        diaVisualizado[visualizado] = v
                        entrenoCambio = true
                    }
                }
                else -> {
                    val p = preferencia(k, v)
                    if (p != null) {
                        c.preferencias++
                        if (cambio(k)) plan.preferencias[k] = p
                    } else if (k == "mypump-theme" || k == "mypump_tipo_dia" || k == "mypump_notif_prefs" || k == "mypump_notif_pedido" ||
                        k == "mypump_onboarding_v1" || k == "mypump_token_invalido" || k in clavesSalud
                    ) {
                        c.ignoradas++   // una preferencia conocida con un valor que no es una elección (tema 'light', etc.)
                    } else {
                        c.desconocidas++
                    }
                }
            }
        }

        // 3. Sesiones vigentes de la cuenta.
        for ((dia, s) in sesiones.entries.sortedBy { it.key }) {
            val start = s.start
            val vigenteSesion = !s.finalizada && start != null && ms - start >= 0 && ms - start <= SESION_MAXIMA
            if (vigenteSesion) {
                c.sesionesVigentes++
                if (dia in sesionCambio) {
                    sesionesEntreno[dia] = s
                    entrenoCambio = true
                }
            } else {
                c.sesionesVencidas++
            }
        }
        if (entrenoCambio) plan.entreno = EntrenoLegado(sesionesEntreno, descansoEntreno, diaVisualizado)

        // 4. Colas: orden estable (vigente, otras, anon) y conteos.
        val hoy = FechaLegado.dia(ms, zona)
        val desde = FechaLegado.sumar(hoy, -7)
        val hasta = FechaLegado.sumar(hoy, 1)
        plan.colas = colas.values.sortedWith(compareBy<ColaLegada>({ it.tipo.ordinalDeOrden() }, { it.clave }))
        for (q in plan.colas) {
            c.opsPorCola[q.tipo.crudo] = (c.opsPorCola[q.tipo.crudo] ?: 0) + q.ops.size
            c.opsIlegibles += q.ilegibles
            for (op in q.ops) {
                c.opsPorKind[op.operacion.kind] = (c.opsPorKind[op.operacion.kind] ?: 0) + 1
                if (op.necesitaValidar) c.opsSinSesion++
            }
            c.fotos += q.fotos.size
            c.fotosFueraDeVentana += q.fotos.values.count { it.fecha < desde || it.fecha > hasta }
            if (q.tipo == ColaLegada.Tipo.ANON) c.demo++
        }
        plan.marcaLeida = items[CLAVE_MARCA]
        plan.conteos = c
        return plan
    }

    private fun ColaLegada.Tipo.ordinalDeOrden(): Int = when (this) {
        ColaLegada.Tipo.VIGENTE -> 0
        ColaLegada.Tipo.OTRO_TOKEN -> 1
        ColaLegada.Tipo.ANON -> 2
    }

    /** Ajustes que pasan tal cual, con la regla de cada uno. null = no es una de estas claves o el valor no es una elección. */
    internal fun preferencia(k: String, v: String): String? = when (k) {
        // theme.js escribe 'light' en CADA carga (`apply(stored || 'light')`): solo 'dark' es una elección.
        "mypump-theme" -> if (v == "dark") v else null
        "mypump_tipo_dia" -> v.ifEmpty { null }
        "mypump_notif_prefs" -> if (JsonLegado.parsear(v) is ValorJson.Objeto) v else null
        "mypump_notif_pedido", "mypump_onboarding_v1" -> if (v == "1") v else null
        "mypump_token_invalido" -> if (FormatoToken.valido(v)) v else null
        else -> if (k in clavesSalud && v.isNotEmpty()) v else null
    }

    /** Las entradas de una cola, en orden. Las que no tienen `kind` no son ops (la web las descarta igual). */
    internal fun leerOps(entradas: List<ValorJson>, clave: String): Pair<List<OpLegada>, Int> {
        val ops = ArrayList<OpLegada>()
        var ilegibles = 0
        val vistas = HashMap<String, Int>()
        for (e in entradas) {
            val o = e as? ValorJson.Objeto
            val kind = o?.get("kind")?.comoTexto
            if (o == null || kind.isNullOrEmpty()) {
                ilegibles++
                continue
            }
            val payload = o["payload"] ?: ValorJson.Nulo
            val dedupe = o["dedupeKey"]?.comoTexto
            val ts = JsonLegado.numero(o["ts"]) ?: 0.0
            val tries = maxOf(0, enteroTruncado(JsonLegado.numero(o["tries"]) ?: 0.0))
            val dk: ValorJson = dedupe?.let { texto(it) } ?: ValorJson.Nulo
            val contenido = JsonLegado.canonico(ValorJson.Lista(listOf(texto(clave), texto(kind), dk, numero(ts), payload)))
            val indice = vistas[contenido] ?: 0
            vistas[contenido] = indice + 1
            val id = JsonLegado.sha256(JsonLegado.canonico(ValorJson.Lista(listOf(texto(clave), numero(indice), texto(kind), dk, numero(ts), payload))))
            val op = Operacion(id = "legado-${id.take(32)}", kind = kind, payload = payload, dedupeKey = dedupe, tries = tries, ts = ts)
            val sinSesion = (kind == "carga" || kind == "estado") && (payload["sesionId"]?.comoTexto ?: "").isEmpty()
            ops += OpLegada(id, op, sinSesion)
        }
        return ops to ilegibles
    }

    internal fun leerFotos(v: String): Map<String, FotoPendiente> {
        val o = JsonLegado.parsear(v) as? ValorJson.Objeto ?: return emptyMap()
        val fotos = LinkedHashMap<String, FotoPendiente>()
        for ((k, x) in o.campos) {
            // Sin dataUrl la web la borra de la cola sin intentar (`if (!item || !item.dataUrl)`).
            val dataUrl = x["dataUrl"]?.comoTexto
            if (dataUrl.isNullOrEmpty()) continue
            // `split(separator:maxSplits:)` de Swift no deja partes vacías.
            val partes = k.split("|", limit = 2).filter { it.isNotEmpty() }
            fotos[k] = FotoPendiente(
                pose = x["pose"]?.comoTexto ?: (if (partes.size == 2) partes[1] else ""),
                fecha = x["fecha"]?.comoTexto ?: partes.firstOrNull() ?: "",
                dataUrl = dataUrl,
                intentos = maxOf(0, enteroTruncado(JsonLegado.numero(x["intentos"]) ?: 0.0)),
            )
        }
        return fotos
    }

    /** La web solo usa la foto si trae `info` y `rutina` (`snap && snap.info && snap.rutina`). */
    internal fun leerCopiaOffline(v: String): CopiaOfflineLegada? {
        val j = JsonLegado.parsear(v) ?: return null
        val info = j["info"] as? ValorJson.Objeto ?: return null
        val rutina = j["rutina"] as? ValorJson.Objeto ?: return null
        return CopiaOfflineLegada(info, rutina, j["dieta"]?.takeUnless { it == ValorJson.Nulo }, JsonLegado.numero(j["ts"]) ?: 0.0)
    }

    /** `restoreRest` exige `autoCloseAt`. */
    internal fun leerDescanso(v: String): DescansoLegado? {
        val j = JsonLegado.parsear(v) ?: return null
        val cierre = JsonLegado.numero(j["autoCloseAt"])?.takeIf { it > 0 } ?: return null
        return DescansoLegado(JsonLegado.numero(j["endsAt"]) ?: cierre, JsonLegado.numero(j["target"]) ?: 0.0, cierre)
    }

    fun leerSustituciones(v: String): Map<String, SustitucionEjercicio> {
        val o = JsonLegado.parsear(v) as? ValorJson.Objeto ?: return emptyMap()
        fun ejercicio(e: ValorJson?) = SustitucionEjercicio.Ejercicio(
            JsonLegado.texto(e?.get("slug")), JsonLegado.texto(e?.get("nombre")), JsonLegado.texto(e?.get("equipment")), e?.get("images"),
        )
        val r = LinkedHashMap<String, SustitucionEjercicio>()
        for ((exId, s) in o.campos) {
            val campos = (s as? ValorJson.Objeto)?.campos ?: continue
            if (campos["current"] !is ValorJson.Objeto) continue
            // Compat F5: `fijado === undefined` → fijado. Ojo: `null` no es undefined (la web lo deja como no fijado).
            val fijado = if ("fijado" in campos) JsonLegado.verdadero(campos["fijado"]) else true
            r[exId] = SustitucionEjercicio(
                ejercicio(campos["original"]), ejercicio(campos["current"]), fijado,
                JsonLegado.numero(campos["semana"])?.let(::enteroTruncado), JsonLegado.texto(campos["diaId"]),
            )
        }
        return r
    }

    internal fun leerSwapsComida(v: String): Map<String, SwapLocal> {
        val o = JsonLegado.parsear(v) as? ValorJson.Objeto ?: return emptyMap()
        val r = LinkedHashMap<String, SwapLocal>()
        for ((k, s) in o.campos) {
            val campos = (s as? ValorJson.Objeto)?.campos ?: continue
            r[k] = SwapLocal(original = campos["original"]?.takeUnless { it == ValorJson.Nulo }, current = campos["current"] ?: ValorJson.Nulo)
        }
        return r
    }

    internal fun sufijo(k: String, prefijo: String): String? = if (k.startsWith(prefijo)) k.substring(prefijo.length) else null

    internal fun sinFinal(k: String, final: String): String? = if (k.endsWith(final) && k.length > final.length) k.dropLast(final.length) else null

    /** Un id que va a parar a un nombre de archivo. */
    internal fun nombreSeguro(s: String): Boolean =
        s.isNotEmpty() && s.length <= 80 && s.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '_' }

    /** `Int(String)` de Swift: signo opcional y dígitos ASCII (lo que no entra en un Int, nada). */
    private fun enteroSwift(s: String): Int? {
        val inicio = if (s.startsWith("+") || s.startsWith("-")) 1 else 0
        if (inicio == s.length || (inicio until s.length).any { s[it] !in '0'..'9' }) return null
        return s.toIntOrNull()
    }
}

/** Fechas `YYYY-MM-DD` locales, gregoriano, como `hoyLocal()` de la web. */
object FechaLegado {
    fun dia(ms: Double, zona: ZoneId): String {
        val d = Instant.ofEpochMilli(ms.toLong()).atZone(zona)
        return String.format(Locale.ROOT, "%04d-%02d-%02d", d.year, d.monthValue, d.dayOfMonth)
    }

    /** `dia` ± `n` días de calendario (un mes o un día fuera de rango pasa al de al lado, como `Calendar`). */
    fun sumar(dia: String, n: Int): String {
        val p = dia.split("-").filter { it.isNotEmpty() }.mapNotNull { it.toIntOrNull() }
        if (p.size != 3) return dia
        return try {
            val d = LocalDate.of(p[0], 1, 1).plusMonths(p[1].toLong() - 1).plusDays(p[2].toLong() - 1).plusDays(n.toLong())
            String.format(Locale.ROOT, "%04d-%02d-%02d", d.year, d.monthValue, d.dayOfMonth)
        } catch (_: Exception) {
            dia
        }
    }
}
