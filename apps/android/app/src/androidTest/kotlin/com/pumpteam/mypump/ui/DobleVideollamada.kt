package com.pumpteam.mypump.ui

import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.reglas.ReglasAgenda
import java.time.Instant
import java.time.temporal.ChronoUnit
import org.json.JSONObject

/**
 * El doble de la videollamada 2.3.0 para las pruebas de interfaz (gemelo de `ServidorAgendaUI` de iPhone). Nunca toca la
 * red ni la producción: contesta la agenda, reservar y cambiar, y la palanca; lo demás va a [base]. El link es de mentira
 * (`https://meet.google.com/abc-defg-hij`): no se crea ninguna videollamada.
 *
 * Escenarios:
 * - `elegir`: horarios de 10 y 12 de Argentina, 1 h, los 5 próximos días hábiles; reservar confirma enseguida.
 * - `diasAntes`: confirmada a 2 días hábiles, a las 10, con un cambio disponible (`entregas_app_cambiar`; el segundo, `tope`).
 * - `porEntrar`: confirmada que empieza en 6 min: «Entrar» ya está habilitado.
 *
 * [palanca]: lo que contesta `mypump_get_app_config` para `elegir_horario`.
 */
class DobleVideollamada(private val escenario: String, private val base: Transporte, private val palanca: Boolean = true) : Transporte {
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<Pair<String, String>>()
    private val franjas = mutableListOf<JSONObject>()
    @Volatile private var reserva: JSONObject? = null
    @Volatile private var cambios = 0

    init {
        val hoy = Instant.now().atZone(ReglasAgenda.ARGENTINA).toLocalDate()
        for (dia in 1..5) for (hora in listOf(10, 12)) {
            val i = ReglasAgenda.diaHabil(hoy, dia).atTime(hora, 0).atZone(ReglasAgenda.ARGENTINA).toOffsetDateTime()
            val n = franjas.size + 1
            franjas += JSONObject().put("id", "00000000-0000-4000-8000-0000000000%02d".format(n)).put("inicio", i.toString()).put("fin", i.plusHours(1).toString())
        }
        when (escenario) {
            "diasAntes" -> reserva = conf(franjas[2].getString("inicio"), franjas[2].getString("fin"))
            "porEntrar" -> {
                val i = Instant.now().plus(390, ChronoUnit.SECONDS)
                reserva = conf(i.toString(), i.plus(1, ChronoUnit.HOURS).toString())
            }
        }
    }

    private fun conf(inicio: String, fin: String) = JSONObject().put("id", "r1").put("inicio", inicio).put("fin", fin)
        .put("estado", "confirmada").put("tipo", "comienzo").put("meet_url", meet)

    fun a(funcion: String): List<String> = llamadas.filter { it.first == funcion }.map { it.second }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val funcion = pedido.ruta.substringAfterLast('/')
        val cuerpo = pedido.cuerpo?.toString(Charsets.UTF_8) ?: ""
        val texto = when (funcion) {
            "mypump_get_app_config" -> """{"elegir_horario": $palanca}"""
            "entregas_app_agenda" -> agenda()
            "entregas_app_resumen" -> """{"ok": true, "total": 6, "vistos": 6, "minutos_restantes": 0, "reserva": ${reserva ?: "null"}}"""
            "entregas_app_reservar" -> synchronized(this) {
                val f = franjas.firstOrNull { it.getString("id") == JSONObject(cuerpo).optString("p_franja") }
                    ?: return@synchronized """{"ok": false, "motivo": "franja"}"""
                // Confirmada enseguida (el daemon de la Mini es rápido): pasa directo a «Listo, quedó agendada».
                reserva = conf(f.getString("inicio"), f.getString("fin"))
                """{"ok": true, "reserva": $reserva}"""
            }
            "entregas_app_cambiar" -> synchronized(this) {
                val f = franjas.firstOrNull { it.getString("id") == JSONObject(cuerpo).optString("p_franja") }
                if (f == null || reserva == null) return@synchronized """{"ok": false, "motivo": "franja"}"""
                if (cambios >= 1) return@synchronized """{"ok": false, "motivo": "tope"}"""
                cambios++
                reserva = conf(f.getString("inicio"), f.getString("fin"))
                """{"ok": true, "reserva": $reserva}"""
            }
            else -> return base.enviar(pedido)
        }
        llamadas += funcion to cuerpo
        return Respuesta(200, texto.toByteArray())
    }

    private fun agenda(): String = synchronized(this) {
        val r = reserva
        // Con un cambio disponible (diasAntes, o elegir después de reservar), van los horarios para cambiar.
        val cambio = if (r != null && escenario != "porEntrar") {
            val hasta = java.time.OffsetDateTime.parse(r.getString("inicio")).toInstant().minus(24, ChronoUnit.HOURS)
            JSONObject().put("permitido", cambios < 1).put("restantes", maxOf(0, 1 - cambios)).put("hasta", hasta.toString())
        } else null
        val conFranjas = r == null || cambio?.getBoolean("permitido") == true
        val libres = franjas.filter { r == null || it.getString("inicio") != r.getString("inicio") }
        JSONObject().put("ok", true).put("autorizada", true).put("habilitada", true).put("faltan", 0)
            .put("zona", "America/Argentina/Buenos_Aires").put("tipo", "comienzo")
            .put("franjas", org.json.JSONArray(if (conFranjas) libres else emptyList<JSONObject>()))
            .put("reserva", r ?: JSONObject.NULL).put("cambio", cambio ?: JSONObject.NULL).toString()
    }

    companion object {
        const val MEET = "https://meet.google.com/abc-defg-hij"
        /** `-e meetUrl <link>`: otra sala de prueba para abrirla de verdad (VideollamadaUiTest.entrarDeVerdad), sin escribirla acá. */
        val meet: String get() = androidx.test.platform.app.InstrumentationRegistry.getArguments().getString("meetUrl") ?: MEET
    }
}
