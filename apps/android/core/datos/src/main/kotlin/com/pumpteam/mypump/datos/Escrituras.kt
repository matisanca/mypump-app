package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AnclajeSwaps
import com.pumpteam.mypump.reglas.SemanticaJs
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Cómo se ejecuta cada `kind` de la cola: las MISMAS RPC y parámetros que el EXEC de la web (cliente.html:2722-2790,
 * supabase-client.js) y que Escrituras.swift. Las ops que trae la migración del almacenamiento viejo son acciones reales
 * del cliente, así que todos los kinds se ejecutan aunque la nativa ya no genere algunos (por ejemplo `comida`, desde que
 * se sacó "Comí / Salté").
 */
class Escrituras(private val cliente: ClienteRpc, private val token: String) {
    private val sesiones = ConcurrentHashMap<String, String>()
    private val verificacion = VerificacionToken()

    /**
     * Ejecuta la op y, si no se guardó, mira una vez si el token cayó (arreglo nativo n.º 3): un token revocado hace que la
     * base devuelva vacío a TODO, y sin esto la cola abandonaría todo lo del cliente en ~1 minuto. Con el token caído las
     * ops quedan estacionadas sin gastar intentos hasta que entre con un link nuevo.
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
            // D7 (`nativa_002`): TRUE = guardado; NULL = token caído (la cola lo estaciona).
            ConsentimientoIA.KIND -> ResultadoOp.Respuesta(
                cliente.llamar(
                    "mypump_guardar_consentimiento_ia",
                    mapOf("p_token" to t, "p_acepta" to de(p, "acepta"), "p_plataforma" to de(p, "plataforma"), "p_app" to de(p, "app")),
                ),
            )
            // Un kind desconocido no se descarta: va a fallidos (arreglo nativo n.º 2).
            else -> ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 0, "KIND_DESCONOCIDO", op.kind)))
        }
    }

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
        val clave = "$dia|${AnclajeSwaps.numeroJs(semana.comoNumero)}"
        sesiones[clave]?.let { return Resultado.Ok(it) }
        val parametros = mapOf("p_token" to texto(token), "p_dia_id" to texto(dia), "p_semana" to semana)
        when (val r = cliente.llamar("mypump_get_sesion_dia", parametros)) {
            is Resultado.Falla -> return r
            is Resultado.Ok -> {
                val id = (r.valor as? ValorJson.Lista)?.elementos?.firstOrNull()?.get("id")?.comoTexto
                if (id != null) {
                    sesiones[clave] = id
                    return Resultado.Ok(id)
                }
            }
        }
        return when (val r = cliente.llamar("mypump_iniciar_sesion", parametros)) {
            is Resultado.Falla -> r
            is Resultado.Ok -> r.valor.comoTexto?.let { id ->
                sesiones[clave] = id
                Resultado.Ok(id)
            } ?: Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 200, "SIN_SESION", "mypump_iniciar_sesion: vacío"))
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
