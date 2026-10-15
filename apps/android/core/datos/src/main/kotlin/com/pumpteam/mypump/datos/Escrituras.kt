package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AnclajeSwaps
import com.pumpteam.mypump.reglas.Js
import com.pumpteam.mypump.reglas.SemanticaJs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Cómo se ejecuta cada `kind` de la cola: las MISMAS RPC y parámetros que el EXEC de la web (cliente.html:2722-2790,
 * supabase-client.js) y que Escrituras.swift. Las ops que trae la migración del almacenamiento viejo son acciones reales
 * del cliente, así que todos los kinds se ejecutan aunque la nativa ya no genere algunos (por ejemplo `comida`, desde que
 * se sacó "Comí / Salté").
 */
class Escrituras(
    private val cliente: ClienteRpc,
    private val token: String,
    /** La de la cuenta: la comparte con la pantalla de Entreno ([ModeloEntreno.asegurarSesion]). */
    private val sesiones: SesionesDelDia = SesionesDelDia(),
) {
    private val verificacion = VerificacionToken()

    /**
     * Ejecuta la op y, si no se guardó, mira una vez si el token cayó (arreglo nativo n.º 3): un token revocado hace que la
     * base devuelva vacío a TODO, y sin esto la cola abandonaría todo lo del cliente en ~1 minuto. Con el token caído las
     * ops quedan estacionadas sin gastar intentos hasta que entre con un link nuevo: si es de la misma persona, su cuenta
     * las adopta ([CuentasDelTelefono], hallazgo 4).
     */
    suspend fun ejecutar(op: Operacion): ResultadoOp {
        val r = ejecutarSinVerificar(op)
        if (r !is ResultadoOp.Respuesta) return r
        val noGuardado = when (val res = r.resultado) {
            is Resultado.Ok -> !Outbox.seGuardo(res.valor)
            is Resultado.Falla -> res.error.clase == ErrorRpc.Clase.PERMANENTE && res.error.codigo != "KIND_DESCONOCIDO"
        }
        if (noGuardado && verificacion.cayo(cliente, token)) return ResultadoOp.TokenCaido
        return r
    }

    internal suspend fun ejecutarSinVerificar(op: Operacion): ResultadoOp {
        val p = op.payload
        val t = texto(token)
        fun de(v: ValorJson?, clave: String): ValorJson = v?.get(clave) ?: ValorJson.Nulo
        return when (op.kind) {
            "carga" -> {
                val sid = when (val r = resolverSesion(p)) {
                    is Resultado.Ok -> r.valor
                    is Resultado.Falla -> return ResultadoOp.Respuesta(r)
                }
                val d = p["datos"] ?: ValorJson.Objeto(emptyMap())
                ResultadoOp.Respuesta(
                    cliente.llamar(
                        "mypump_registrar_carga",
                        mapOf(
                            "p_token" to t, "p_sesion_id" to texto(sid), "p_dia_id" to de(d, "diaId"), "p_ejercicio_id" to de(d, "ejercicioId"),
                            "p_ejercicio_nombre" to de(d, "ejercicioNombre"), "p_serie" to de(d, "serie"), "p_peso" to de(d, "peso"),
                            "p_reps" to de(d, "reps"), "p_rir" to de(d, "rir"), "p_notas" to de(d, "notas"),
                        ),
                    ),
                )
            }
            "estado" -> {
                val sid = when (val r = resolverSesion(p)) {
                    is Resultado.Ok -> r.valor
                    is Resultado.Falla -> return ResultadoOp.Respuesta(r)
                }
                ResultadoOp.Respuesta(
                    cliente.llamar(
                        "mypump_marcar_ejercicio_estado",
                        mapOf(
                            "p_token" to t, "p_sesion_id" to texto(sid), "p_dia_id" to de(p, "diaId"), "p_ejercicio_id" to de(p, "exId"),
                            "p_series_objetivo" to de(p, "seriesObjetivo"), "p_status" to de(p, "status"),
                            "p_marcado_manualmente" to (p["manual"] ?: ValorJson.Booleano(false)),
                        ),
                    ),
                )
            }
            "swap" -> ResultadoOp.Respuesta(
                cliente.llamar(
                    "mypump_save_food_swap",
                    mapOf(
                        "p_token" to t, "p_dieta_id" to de(p, "dietaId"), "p_comida_id" to de(p, "comidaId"),
                        "p_opt_idx" to de(p, "optIdx"), "p_food_idx" to de(p, "foodIdx"), "p_food_data" to de(p, "food"),
                    ),
                ),
            )
            // FALSE = no había fila: objetivo cumplido.
            "swap_del" -> ResultadoOp.Respuesta(
                cliente.llamar(
                    "mypump_delete_food_swap",
                    mapOf(
                        "p_token" to t, "p_dieta_id" to de(p, "dietaId"), "p_comida_id" to de(p, "comidaId"),
                        "p_opt_idx" to de(p, "optIdx"), "p_food_idx" to de(p, "foodIdx"),
                    ),
                ).map { texto("ok") },
            )
            "habito" -> ResultadoOp.Respuesta(
                cliente.llamar(
                    "mypump_set_habito",
                    mapOf("p_token" to t, "p_fecha" to de(p, "fecha"), "p_campo" to de(p, "campo"), "p_valor" to texto(stringJs(p["valor"]))),
                ),
            )
            "comida" -> {
                val estado = p["estado"]
                if (estado == null || estado == ValorJson.Nulo) {
                    return ResultadoOp.Respuesta(
                        cliente.llamar(
                            "mypump_desmarcar_comida",
                            mapOf("p_token" to t, "p_fecha" to de(p, "fecha"), "p_comida_id" to de(p, "comidaId")),
                        ).map { texto("ok") },
                    )
                }
                val excl = (p["excl"] as? ValorJson.Lista)?.takeIf { it.elementos.isNotEmpty() } ?: ValorJson.Nulo
                ResultadoOp.Respuesta(
                    cliente.llamar(
                        "mypump_marcar_comida",
                        mapOf(
                            "p_token" to t, "p_fecha" to de(p, "fecha"), "p_comida_id" to de(p, "comidaId"), "p_opcion" to de(p, "opcion"),
                            "p_estado" to estado, "p_foods_excluidos" to excl,
                        ),
                    ),
                )
            }
            "peso" -> {
                val registro = ValorJson.objeto(
                    "fecha" to de(p, "fecha"), "tipo" to texto("peso_kg"), "valor" to de(p, "valor"), "fuente" to texto("manual"),
                )
                ResultadoOp.Respuesta(cliente.llamar("mypump_ingest_salud", mapOf("p_token" to t, "p_registros" to ValorJson.Lista(listOf(registro)))))
            }
            "checkin" -> {
                val d = p["datos"] ?: ValorJson.Objeto(emptyMap())
                // `nota || null` de la web.
                val nota = d["nota"]?.takeIf { SemanticaJs.esVerdadero(it) } ?: ValorJson.Nulo
                ResultadoOp.Respuesta(
                    cliente.llamar(
                        "mypump_guardar_checkin",
                        mapOf(
                            "p_token" to t, "p_fecha" to de(p, "fecha"), "p_energia" to de(d, "energia"), "p_descanso" to de(d, "descanso"),
                            "p_hambre" to de(d, "hambre"), "p_adherencia" to de(d, "adherencia"), "p_nota" to nota,
                        ),
                    ),
                )
            }
            "chat" -> {
                // Arreglo nativo n.º 4 (el chat "en vuelo"): si el mensaje ya llegó (se mandó, se cortó la señal antes de
                // la respuesta y la cola lo reintenta), no se manda de nuevo. El servidor deduplica el mismo texto dentro
                // de 2 minutos (mig 075), pero un reintento puede llegar mucho después.
                if (yaLlego(p["contenido"]?.comoTexto, op.ts)) return ResultadoOp.Respuesta(Resultado.Ok(texto("ya estaba")))
                ResultadoOp.Respuesta(
                    cliente.llamar(
                        "mypump_agregar_comentario",
                        mapOf(
                            "p_token" to t, "p_ambito" to texto("general"), "p_referencia_id" to ValorJson.Nulo,
                            "p_referencia_nombre" to ValorJson.Nulo, "p_contenido" to de(p, "contenido"),
                        ),
                    ),
                )
            }
            // D7 se sacó el 14-oct (Mati: la IA no es algo que el cliente acepte). La app ya no lo encola; esto vacía lo que
            // haya quedado en una cola. Solo registra lo que se eligió (`nativa_002`): nada del servidor lo lee. TRUE =
            // guardado; NULL = token caído (la cola lo estaciona).
            "consentimiento_ia" -> ResultadoOp.Respuesta(
                cliente.llamar(
                    "mypump_guardar_consentimiento_ia",
                    mapOf("p_token" to t, "p_acepta" to de(p, "acepta"), "p_plataforma" to de(p, "plataforma"), "p_app" to de(p, "app")),
                ),
            )
            // SER-14 (`nativa_003`). TRUE también si el servidor tenía algo más nuevo. FALSE = la rutina ya no es del
            // cliente: no hay nada que guardar (cuenta como hecho).
            SustitucionesServidor.KIND_GUARDAR -> ResultadoOp.Respuesta(
                sinTablaEsHecho(
                    cliente.llamar(
                        "mypump_save_exercise_swap",
                        mapOf("p_token" to t, "p_rutina_id" to de(p, "rutinaId"), "p_ex_id" to de(p, "exId"), "p_swap" to de(p, "swap")),
                    ),
                ),
            )
            SustitucionesServidor.KIND_BORRAR -> ResultadoOp.Respuesta(
                sinTablaEsHecho(
                    cliente.llamar(
                        "mypump_delete_exercise_swap",
                        // Deja la lápida con la hora del borrado (gana lo más nuevo).
                        mapOf("p_token" to t, "p_rutina_id" to de(p, "rutinaId"), "p_ex_id" to de(p, "exId"), "p_ts" to de(p, "ts")),
                    ),
                ),
            )
            // Un kind desconocido no se descarta: va a fallidos (arreglo nativo n.º 2).
            else -> ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 0, "KIND_DESCONOCIDO", op.kind)))
        }
    }

    /**
     * SER-14: sin la migración 003 en la base (PGRST202), la sustitución vive solo en el teléfono, como antes: la op se da
     * por hecha (si no, gastaría intentos y terminaría en "no se guardó"). Lo del teléfono sube en la primera
     * sincronización con la tabla ya creada.
     */
    private fun sinTablaEsHecho(r: Resultado<ValorJson>): Resultado<ValorJson> =
        if (r is Resultado.Falla && r.error.funcionInexistente) Resultado.Ok(texto("sin tabla")) else r

    /**
     * ¿Hay en el hilo un mensaje del cliente con ese texto, escrito desde que se encoló? (con un minuto de margen por la
     * diferencia de reloj entre el teléfono y el servidor). Sin red, se manda igual y decide la cola.
     */
    internal suspend fun yaLlego(contenido: String?, desde: Double): Boolean {
        if (contenido.isNullOrEmpty()) return false
        val r = cliente.filas(
            "mypump_get_chat",
            mapOf("p_token" to texto(token), "p_antes" to ValorJson.Nulo, "p_limite" to numero(10)),
            MensajeChat::desde,
        )
        val filas = r.valorONull() ?: return false
        return filas.any { it.autor == "cliente" && it.contenido == contenido && FechaIso.ms(it.createdAt) >= desde - 60_000 }
    }

    /**
     * `resolveSesion` (cliente.html:2698): la sesión capturada al encolar, o la de ESE día y semana, o se crea. "No pude
     * preguntar" no es "no existe": con un fallo de red se devuelve ese error (la cola corta sin gastar intento) y nunca se
     * crea una segunda sesión, que partiría las series del día. Si la base no da sesión (sin rutina activa, token
     * revocado), es un rechazo: gasta intento y la cola sigue con las demás, como la web.
     */
    internal suspend fun resolverSesion(p: ValorJson): Resultado<String> {
        p["sesionId"]?.comoTexto?.takeIf { it.isNotEmpty() }?.let { return Resultado.Ok(it) }
        val dia = p["diaId"]?.comoTexto
            ?: return Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 0, "SIN_DIA", "op sin diaId"))
        val semana = p["semana"] ?: ValorJson.Nulo
        val clave = SesionesDelDia.clave(dia, semana.comoNumero)
        sesiones.leer(clave)?.let { return Resultado.Ok(it) }
        val parametros = mapOf("p_token" to texto(token), "p_dia_id" to texto(dia), "p_semana" to semana)
        // Si la pantalla ya la está creando (la primera serie del día), no se pregunta: se espera esa misma llamada.
        if (!sesiones.enVuelo(clave)) {
            when (val r = cliente.llamar("mypump_get_sesion_dia", parametros)) {
                is Resultado.Falla -> return r
                is Resultado.Ok -> {
                    val id = (r.valor as? ValorJson.Lista)?.elementos?.firstOrNull()?.get("id")?.comoTexto
                    if (id != null) {
                        sesiones.guardar(clave, id)
                        return Resultado.Ok(id)
                    }
                }
            }
        }
        return when (val r = sesiones.iniciar(clave, usarResueltas = true) { cliente.llamar("mypump_iniciar_sesion", parametros) }) {
            is Resultado.Falla -> r
            is Resultado.Ok -> Js.verdadero(r.valor.comoTexto)?.let { Resultado.Ok(it) }
                ?: Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_SESION", "mypump_iniciar_sesion: vacío"))
        }
    }

    companion object {
        /**
         * `valor === null ? 'null' : String(valor)` de la web (`setHabito`): null → "null", true → "true", 12 → "12".
         * Un valor que falta también es "null" (en la web sería "undefined", y no pasa: la app siempre lo manda).
         */
        fun stringJs(v: ValorJson?): String = when (v) {
            null, ValorJson.Nulo -> "null"
            is ValorJson.Booleano -> v.valor.toString()
            is ValorJson.Numero -> NumeroJs.texto(v.valor)
            is ValorJson.Texto -> v.valor
            is ValorJson.Lista -> v.elementos.joinToString(",") { if (it == ValorJson.Nulo) "" else stringJs(it) }
            is ValorJson.Objeto -> "[object Object]"
        }
    }
}

/**
 * La sesión del día por día y semana, de una cuenta: las que ya se resolvieron y la creación en vuelo. La comparten la cola
 * ([Escrituras.resolverSesion]) y la pantalla de Entreno ([ModeloEntreno.asegurarSesion]): al confirmar la primera serie
 * salen las dos a la vez y cada una mandaba su `iniciar_sesion`. La web comparte la promesa en vuelo (`_sesionInflight`);
 * acá también (revisión del 15-oct, hallazgo 5). Gemelo de `SesionesDelDia` de iOS. La cola la usa desde su hilo y la
 * pantalla desde el principal: lo de adentro va con candado.
 */
class SesionesDelDia(
    /** Donde corre la creación compartida (en la app, la de la cuenta): no depende de quién la espera, como el `Task` de iOS. */
    private val alcance: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    private val candado = Mutex()
    private val resueltas = HashMap<String, String>()
    private val vuelos = HashMap<String, Deferred<Resultado<ValorJson>>>()

    internal suspend fun leer(k: String): String? = candado.withLock { resueltas[k] }

    internal suspend fun guardar(k: String, id: String) = candado.withLock { resueltas[k] = id }

    internal suspend fun enVuelo(k: String): Boolean = candado.withLock { k in vuelos }

    /**
     * `iniciar_sesion` una sola vez por clave: si ya hay una creación en vuelo, se espera esa; si no, sale [crear]. Lo que
     * devuelve queda resuelto para la cola. La pantalla no lee lo resuelto (`usarResueltas = false`): confirma su sesión con
     * el servidor al restaurar, y una que el servidor archivó en el medio no tiene que volver por acá.
     */
    internal suspend fun iniciar(k: String, usarResueltas: Boolean, crear: suspend () -> Resultado<ValorJson>): Resultado<ValorJson> {
        val vuelo = candado.withLock {
            if (usarResueltas) resueltas[k]?.let { return Resultado.Ok(texto(it)) }
            vuelos[k] ?: alcance.async {
                var r: Resultado<ValorJson>? = null
                try {
                    crear().also { r = it }
                } finally {
                    // El vuelo se suelta pase lo que pase (si no, el próximo esperaría uno muerto), y lo creado queda resuelto.
                    withContext(NonCancellable) {
                        candado.withLock {
                            vuelos.remove(k)
                            Js.verdadero((r as? Resultado.Ok)?.valor?.comoTexto)?.let { resueltas[k] = it }
                        }
                    }
                }
            }.also { vuelos[k] = it }
        }
        return vuelo.await()
    }

    companion object {
        /** `"<día>|<semana>"`, con la semana como la escribe JS (la clave de `_sesionPorDia` de la web). */
        fun clave(dia: String, semana: Double?): String = "$dia|${AnclajeSwaps.numeroJs(semana)}"
    }
}

/**
 * "¿Cayó el token?" una vez por minuto como mucho: un `get_cliente_info` que devuelve `[]` es un token revocado. Sin red no
 * se sabe: se asume que no (decide la cola).
 */
internal class VerificacionToken(private val reloj: () -> Long = System::currentTimeMillis) {
    private val candado = Mutex()
    private var ultima: Pair<Long, Boolean>? = null

    suspend fun cayo(cliente: ClienteRpc, token: String): Boolean = candado.withLock { consultar(cliente, token) }

    private suspend fun consultar(cliente: ClienteRpc, token: String): Boolean {
        ultima?.let { (cuando, cayo) -> if (reloj() - cuando < 60_000) return cayo }
        val r = cliente.llamar("mypump_get_cliente_info", mapOf("p_token" to texto(token))).valorONull() ?: return false
        val cayo = if (r is ValorJson.Lista) r.elementos.isEmpty() else r == ValorJson.Nulo
        ultima = reloj() to cayo
        return cayo
    }
}
