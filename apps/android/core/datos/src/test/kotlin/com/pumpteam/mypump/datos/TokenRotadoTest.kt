package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 4 (gemelo de TokenRotadoTests.swift): la carpeta de cada cuenta va por la huella del token.
 * Si Mati regenera el link (`mypump_regenerar_token`) y el cliente pega el nuevo, la cuenta nueva arrancaba con la cola
 * vacía y lo que quedó en la vieja (las series cargadas sin señal, estacionadas con el token caído) no salía nunca. Ahora,
 * si el token nuevo es de la MISMA persona (`cliente_id`), adopta lo pendiente y los fallidos de la carpeta vieja; de otra
 * persona, nunca.
 */
class TokenRotadoTest {
    private val raiz = carpetaTemporal("token-rotado")

    /** Qué token vale para cada cliente (la regla del servidor corre fuera del hilo del test). */
    private class Vigentes(inicial: Map<String, String>) {
        private val porToken = HashMap(inicial)

        @Synchronized fun cliente(token: String?): String? = token?.let { porToken[it] }

        /** `mypump_regenerar_token`: el link viejo deja de valer y el nuevo es del mismo cliente. */
        @Synchronized fun regenerar(viejo: String, nuevo: String, cliente: String) {
            porToken.remove(viejo)
            porToken[nuevo] = cliente
        }

        @Synchronized fun agregar(token: String, cliente: String) {
            porToken[token] = cliente
        }
    }

    /** La base: cada token resuelve a su cliente mientras sea el vigente de ese cliente (regenerar reemplaza el viejo). */
    private fun servidor(v: Vigentes): Servidor {
        val s = Servidor()
        s.regla("get_cliente_info") { p ->
            val c = v.cliente(p["p_token"]?.comoTexto) ?: return@regla 200 to "[]"
            200 to """[{"cliente_id":"$c","nombre":"Cliente","perfil":"natural"}]"""
        }
        s.regla("get_rutina_activa") { p -> if (v.cliente(p["p_token"]?.comoTexto) == null) 200 to "[]" else 200 to "[${filaRutina()}]" }
        s.regla("registrar_carga") { p -> if (v.cliente(p["p_token"]?.comoTexto) == null) 200 to "null" else 200 to "\"fila-1\"" }
        return s
    }

    private fun modelo(s: Servidor, token: String, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = s), TokenEnMemoria(token), raiz, PreferenciasEnMemoria(), alcance)

    private fun cargasCon(s: Servidor, token: String): List<ValorJson> =
        s.llamadas("registrar_carga").filter { it["p_token"]?.comoTexto == token }

    @Test
    fun laSerieQueQuedoConElLinkViejoSaleConElNuevo() = enUnHilo { alcance ->
        val vigentes = Vigentes(mapOf(TOK_A to "c1"))
        val s = servidor(vigentes)
        val m = modelo(s, TOK_A, alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)

        // Mati regenera el link: A ya no vale. La serie que se carga ahora queda estacionada (token caído) en la cola de A,
        // y un fallido viejo de A (lo que la migración dejó "para revisar") también está ahí.
        vigentes.regenerar(TOK_A, TOK_B, "c1")
        m.outbox!!.encolar("carga", CARGA, "carga_d1_jal-d1-0_0_s5")
        val revisar = Operacion(
            id = "viejo-1", kind = "carga", payload = ValorJson.objeto("diaId" to texto("b2d1"), "semana" to numero(3)),
            dedupeKey = "carga_b2d1_x_0", ts = 1_000.0,
        )
        m.outbox!!.archivarEnFallidos(listOf(revisar), "para revisar: la rutina activa ya no es la de la foto")
        m.outbox!!.drenar()
        assertEquals(1, m.outbox!!.pendientes(), "con el token caído la serie queda en la cola")
        assertTrue(cargasCon(s, TOK_B).isEmpty())

        // El cliente pega el link nuevo.
        assertTrue(m.entrar("https://app.mypumpteam.com/?t=$TOK_B"))
        m.outbox!!.drenar()
        val enviadas = cargasCon(s, TOK_B)
        assertEquals(1, enviadas.size, "la serie de la cola vieja no salió con el link nuevo")
        assertEquals("ses-1", enviadas.first()["p_sesion_id"]?.comoTexto)
        assertEquals(ValorJson.Numero(60.0), enviadas.first()["p_peso"])
        assertEquals(0, m.outbox!!.pendientes())
        // Lo "para revisar" sigue en fallidos (no se manda, no se pierde).
        assertEquals(listOf("viejo-1"), m.outbox!!.fallidos().map { it.op.id })
        // Entreno escribe en la cuenta nueva: el motor de la misma rutina no se queda con el token viejo.
        assertEquals(TOK_B, m.entreno.value?.token)

        // Otro arranque con B: lo adoptado no se vuelve a adoptar ni a mandar.
        val otra = modelo(s, TOK_B, alcance)
        otra.cargar()
        otra.outbox!!.drenar()
        assertEquals(1, cargasCon(s, TOK_B).size, "se mandó dos veces")
        assertEquals(1, otra.outbox!!.fallidos().size)
    }

    @Test
    fun loDeOtraPersonaNoSeAdoptaNunca() = enUnHilo { alcance ->
        val vigentes = Vigentes(mapOf(TOK_A to "c1"))
        val s = servidor(vigentes)
        val a = modelo(s, TOK_A, alcance)
        a.cargar()
        vigentes.regenerar(TOK_A, TOK_B, "c1")
        a.outbox!!.encolar("carga", CARGA, "carga_d1_jal-d1-0_0_s5")
        a.outbox!!.drenar()

        // En el mismo teléfono se abre el link de OTRO cliente (Mati mirando una cuenta): no se lleva nada de A.
        vigentes.agregar(TOK_C, "c2")
        val c = modelo(s, TOK_C, alcance)
        c.cargar()
        c.outbox!!.drenar()
        assertTrue(cargasCon(s, TOK_C).isEmpty(), "mandó la serie de otra persona")
        assertEquals(0, c.outbox!!.pendientes())
        assertEquals(0, c.outbox!!.fallidos().size)
        // La de A sigue esperando en su carpeta, para su link nuevo.
        val b = modelo(s, TOK_B, alcance)
        b.cargar()
        b.outbox!!.drenar()
        assertEquals(1, cargasCon(s, TOK_B).size)
    }

    private companion object {
        const val TOK_A = "AAAAAAAAAAAAAAAAAAAA"
        const val TOK_B = "BBBBBBBBBBBBBBBBBBBB"
        const val TOK_C = "CCCCCCCCCCCCCCCCCCCC"

        /** Una serie con su sesión, como la deja Entreno en la cola. */
        val CARGA: ValorJson = ValorJson.objeto(
            "sesionId" to texto("ses-1"), "diaId" to texto("d1"), "semana" to numero(5),
            "datos" to ValorJson.objeto(
                "diaId" to texto("d1"), "ejercicioId" to texto("jal-d1-0"), "ejercicioNombre" to texto("Jalón al pecho"),
                "serie" to numero(1), "peso" to numero(60), "reps" to numero(10), "rir" to ValorJson.Nulo, "notas" to ValorJson.Nulo,
            ),
        )
    }
}
