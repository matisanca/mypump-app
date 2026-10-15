package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.ClaveEjercicio
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/**
 * PRO-02 (ProgresoEfectivoTests de iOS): Progreso agrupa por el ejercicio que se hace de verdad, con el sustituto si hay
 * (`getEffectiveEx` en el `loadProgressAndRender` de la web, cliente.html:6085-6101). Pasando solo la rutina se agrupaba
 * por el nombre del plan: un press sustituido salía con el nombre y el historial del original.
 */
class ProgresoEfectivoTest {
    private val info = """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""

    private fun ejercicio(id: String, nombre: String) =
        """{"id":"$id","tipo":"principal","nombre":"$nombre","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"""

    /** Dos días: el press banca del día 1 está sustituido (fijado) por el mismo press inclinado que tiene el día 2. */
    private val rutina = """[{"id":"rut-progreso","version":1,"semana_actual":1,"estructura":{"dias":[""" +
        """{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[""" +
        ejercicio("press-d1-0", "Press banca") + "," + ejercicio("sentadilla-d1-1", "Sentadilla") + "]}]}," +
        """{"n":2,"id":"d2","nombre":"TORSO","bloques":[{"titulo":"A","ejercicios":[""" +
        ejercicio("inclinado-d2-0", "Press inclinado con mancuernas") + "]}]}]}}]"

    private val swaps = """{"vivas":{"press-d1-0":{"current":{"slug":null,"nombre":"Press inclinado con mancuernas",""" +
        """"equipment":null,"images":null},"fijado":true,"semana":1,"_ts":1000}},"borradas":{},"ahora":2000}"""

    private fun fila(clave: String, nombre: String, kg: Double) =
        """{"clave":"$clave","registrado_en":"2026-10-10T12:00:00+00:00","peso_kg":$kg,"reps_realizadas":8,""" +
            """"rir_real":2,"serie_numero":1,"notas":null,"ejercicio_nombre":"$nombre"}"""

    @Test
    fun unEjercicioSustituidoSeAgrupaPorElSustituto() = enUnHilo { alcance ->
        val inclinado = ClaveEjercicio.de("Press inclinado con mancuernas")
        val banca = ClaveEjercicio.de("Press banca")
        val sentadilla = ClaveEjercicio.de("Sentadilla")
        // Las claves que pidió Progreso (la regla del transporte corre en otro hilo).
        val pedidas = AtomicReference<List<String>>(emptyList())
        val t = TransporteProgramado { fn, cuerpo ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_rutina_activa" -> 200 to rutina
                "mypump_get_exercise_swaps" -> 200 to swaps
                "mypump_get_historico_por_clave" -> {
                    (cuerpo["p_claves"] as? ValorJson.Lista)?.let { l -> pedidas.set(l.elementos.mapNotNull { it.comoTexto }) }
                    200 to "[" + listOf(
                        fila(inclinado, "Press inclinado con mancuernas", 30.0),
                        fila(banca, "Press banca", 80.0),
                        fila(sentadilla, "Sentadilla", 100.0),
                    ).joinToString(",") + "]"
                }
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("progreso-efectivo"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        val entreno = m.entreno.value!!
        entreno.cargar()
        val press = m.rutina.value!!.estructura.dias.first().bloques.first().ejercicios.first()
        // La carga que lanzó ModeloApp.cargar() puede tener la sincronización todavía en vuelo (una a la vez): se espera.
        repeat(100) { if (entreno.efectivo(press).ejercicio.nombre != "Press inclinado con mancuernas") delay(20) }
        assertEquals("Press inclinado con mancuernas", entreno.efectivo(press).ejercicio.nombre, "la sustitución del servidor tiene que estar aplicada")

        m.cargarProgreso()
        val tarjetas = m.progreso.value!!.tarjetas.value
        assertEquals(
            listOf("Press inclinado con mancuernas", "Sentadilla"), tarjetas.map { it.nombre },
            "el sustituto y el original del día 2 son una sola tarjeta; el press banca no aparece",
        )
        assertEquals("EMPUJE · TORSO", tarjetas.first().dias)
        assertEquals(listOf(inclinado, sentadilla), pedidas.get(), "pide la clave del sustituto, no la del plan")
    }

    @Test
    fun sinSustitucionesQuedaComoElPlan() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to info
                "mypump_get_rutina_activa" -> 200 to rutina
                "mypump_get_exercise_swaps" -> 200 to """{"vivas":{},"borradas":{},"ahora":2000}"""
                "mypump_get_historico_por_clave" -> 200 to "[" + fila(ClaveEjercicio.de("Press banca"), "Press banca", 80.0) + "]"
                else -> 200 to "[]"
            }
        }
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), carpetaTemporal("progreso-efectivo"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        m.entreno.value?.cargar()
        m.cargarProgreso()
        assertEquals(listOf("Press banca"), m.progreso.value?.tarjetas?.value?.map { it.nombre })
    }
}
