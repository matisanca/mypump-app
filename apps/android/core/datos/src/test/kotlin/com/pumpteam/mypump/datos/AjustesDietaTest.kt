package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AnclaAlimento
import com.pumpteam.mypump.reglas.FechaLocal
import java.util.Collections
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Los ajustes de porciones del día (feedback del 20-oct) en el modelo: quedan en el teléfono solo por hoy, salen por la
 * cola con el día entero (una op por día), sin la tabla (PGRST202) no se pierden ni avisan, al hidratar gana lo del
 * teléfono que todavía no salió y las cantidades a mano quedan ancladas a su alimento. Gemelo de AjustesDietaTests.swift.
 */
class AjustesDietaTest {
    private val raiz = carpetaTemporal("ajustes-dieta")

    /** El servidor: guarda lo que le llega y contesta las lecturas. `sinTabla` = la migración nativa_004 no está. */
    private class Servidor {
        val guardados: MutableList<ValorJson> = Collections.synchronizedList(mutableListOf())
        @Volatile var sinTabla = false

        /** `mypump_guardar_ajustes_dieta` falla (un 500: la op queda en la cola). */
        @Volatile var guardarFalla = false

        /** `mypump_get_food_swaps` falla (un 500). */
        @Volatile var sinSwaps = false
        @Volatile var filas = "[]"

        /** Otra estructura con el mismo id: Mati volvió a publicar (013 actualiza en el lugar). */
        @Volatile var dieta: String? = null

        val transporte = TransporteProgramado { fn, cuerpo ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to (dieta ?: DIETA)
                "mypump_get_food_swaps" -> if (sinSwaps) 500 to """{"message":"caído"}""" else 200 to "[]"
                "mypump_guardar_ajustes_dieta" ->
                    if (sinTabla) 404 to """{"code":"PGRST202","message":"Could not find the function"}"""
                    else if (guardarFalla) 500 to """{"message":"caído"}"""
                    else {
                        guardados += cuerpo
                        200 to "true"
                    }
                "mypump_get_ajustes_dieta" ->
                    if (sinTabla) 404 to """{"code":"PGRST202","message":"Could not find the function"}""" else 200 to filas
                else -> 200 to "[]"
            }
        }
    }

    private fun modelo(s: Servidor, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = s.transporte), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)

    private val hoy get() = FechaLocal.hoy()

    @Test
    fun ajustarCambiaElDiaLoGuardaYLoMandaEntero() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        assertTrue(m.ajustesDeHoy.isEmpty())
        m.ajustar("desayuno", AjusteComida(deltaKcal = 200), emptyMap())
        val dia = m.diaAjustado(emptyMap())
        assertTrue(dia.getValue("desayuno").kcal > dia.getValue("desayuno").kcalPlan, "sube el desayuno")
        assertTrue(dia.getValue("almuerzo").kcal < dia.getValue("almuerzo").kcalPlan, "compensa en el almuerzo")
        // La cola puede haberla mandado ya; si sigue ahí, es UNA, del día.
        val ops = m.outbox?.operaciones().orEmpty()
        assertTrue(ops.size <= 1 && ops.all { it.kind == AjustesDieta.KIND && it.dedupeKey == "ajustes_dieta_$hoy" }, ops.toString())
        m.outbox?.drenar()
        assertEquals(0, m.outbox?.pendientes())
        val g = s.guardados.last()
        assertEquals(hoy, g["p_fecha"]?.comoTexto)
        assertEquals(DIETA_ID, g["p_dieta_id"]?.comoTexto)
        assertEquals(200.0, g["p_ajustes"]?.get("desayuno")?.get("deltaKcal")?.comoNumero)
        val resumen = (g["p_resumen"] as ValorJson.Lista).elementos
        assertEquals(listOf("desayuno", "almuerzo"), resumen.map { it["comida_id"]?.comoTexto })
        assertEquals(dia.values.sumOf { it.kcalPlan }, g["p_kcal_plan"]?.comoNumero)
        assertEquals(dia.values.sumOf { it.kcal }, g["p_kcal_dia"]?.comoNumero)

        // Otro arranque lo encuentra en el teléfono.
        val otro = modelo(s, alcance)
        otro.cargar()
        assertEquals(200, otro.ajustesDeHoy["desayuno"]?.deltaKcal)
    }

    /** Nunca quedan dos ops del mismo día y lo último que recibe el servidor es el estado final. */
    @Test
    fun variosCambiosSeguidosDejanUnaOpYLaUltimaGana() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        m.ajustar("desayuno", AjusteComida(deltaKcal = 50), emptyMap())
        m.ajustar("desayuno", AjusteComida(deltaKcal = 100), emptyMap())
        m.ajustar("almuerzo", AjusteComida(deltaKcal = -50, compensar = false), emptyMap())
        assertTrue(m.outbox?.operaciones().orEmpty().size <= 1)
        m.outbox?.drenar()
        assertEquals(0, m.outbox?.pendientes())
        val ultimo = s.guardados.last()
        assertEquals(100.0, ultimo["p_ajustes"]?.get("desayuno")?.get("deltaKcal")?.comoNumero)
        assertEquals(ValorJson.Booleano(false), ultimo["p_ajustes"]?.get("almuerzo")?.get("compensar"))
    }

    @Test
    fun volverAlPlanMandaElDiaVacio() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        m.ajustar("desayuno", AjusteComida(deltaKcal = 100), emptyMap())
        m.outbox?.drenar()
        m.ajustar("desayuno", null, emptyMap())
        assertTrue(m.ajustesDeHoy.isEmpty())
        m.outbox?.drenar()
        assertEquals(ValorJson.Objeto(emptyMap()), s.guardados.last()["p_ajustes"])
        assertEquals(ValorJson.Nulo, s.guardados.last()["p_resumen"])
        // Un ajuste neutro (sin kcal, sin gramos, comiéndola) es lo mismo que sacarlo: nada que mandar.
        m.ajustar("desayuno", AjusteComida(), emptyMap())
        assertTrue(m.outbox?.operaciones().orEmpty().isEmpty())
    }

    @Test
    fun sinLaTablaQuedaEnElTelefonoSinAvisosNiFallidos() = enUnHilo { alcance ->
        val s = Servidor().apply { sinTabla = true }
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        m.ajustar("desayuno", AjusteComida(omitida = true), emptyMap())
        m.outbox?.drenar()
        assertEquals(0, m.outbox?.pendientes())
        assertTrue(m.outbox?.fallidos().orEmpty().isEmpty())
        assertEquals(true, m.ajustesDeHoy["desayuno"]?.omitida)
        assertEquals(EstadoGuardado.QUIETO, m.estadoGuardado.value, "sin «Guardando…» ni «no se guardó»")
    }

    @Test
    fun alHidratarGanaLoDelServidorSalvoQueHayaAlgoSinSalir() = enUnHilo { alcance ->
        val s = Servidor()
        s.filas = """[{"fecha":"$hoy","dieta_id":"$DIETA_ID","tipo_dia":null,"ajustes":{"almuerzo":{"deltaKcal":-100,"compensar":false,"omitida":false,"opcion":0,"cantidades":{}}}}]"""
        val m = modelo(s, alcance)
        m.cargar()
        assertEquals(-100, m.ajustesDeHoy["almuerzo"]?.deltaKcal, "lo de otro teléfono")
        // Con un cambio local que todavía no salió (el servidor no contesta), lo del servidor no lo pisa.
        s.guardarFalla = true
        m.ajustar("desayuno", AjusteComida(deltaKcal = 50), emptyMap())
        m.outbox?.drenar()
        assertEquals(1, m.outbox?.pendientes(), "la op sigue esperando")
        m.hidratarDieta()
        assertEquals(50, m.ajustesDeHoy["desayuno"]?.deltaKcal, "lo del teléfono gana")
        assertEquals(-100, m.ajustesDeHoy["almuerzo"]?.deltaKcal)
        // Cuando sale, el servidor recibe el día entero.
        s.guardarFalla = false
        m.outbox?.drenar()
        assertEquals(50.0, s.guardados.last()["p_ajustes"]?.get("desayuno")?.get("deltaKcal")?.comoNumero)
        assertEquals(-100.0, s.guardados.last()["p_ajustes"]?.get("almuerzo")?.get("deltaKcal")?.comoNumero)
    }

    /** Volver al plan en otro teléfono deja la fila con {}: acá también se va (no se resucita lo que se sacó). */
    @Test
    fun loQueSeSacoEnOtroTelefonoSeVaAca() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(deltaKcal = 150), emptyMap())
        m.outbox?.drenar()
        s.filas = """[{"fecha":"$hoy","dieta_id":"$DIETA_ID","ajustes":{}}]"""
        val antes = s.guardados.size
        m.hidratarDieta()
        assertTrue(m.ajustesDeHoy.isEmpty())
        m.outbox?.drenar()
        assertEquals(antes, s.guardados.size, "no lo vuelve a subir")
    }

    @Test
    fun sinLosReemplazosLosAjustesSeHidratanIgual() = enUnHilo { alcance ->
        val s = Servidor().apply { sinSwaps = true }
        s.filas = """[{"fecha":"$hoy","dieta_id":"$DIETA_ID","ajustes":{"almuerzo":{"deltaKcal":-100}}}]"""
        val m = modelo(s, alcance)
        m.cargar()
        assertEquals(-100, m.ajustesDeHoy["almuerzo"]?.deltaKcal)
    }

    @Test
    fun otraDietaEnElServidorNoSeMezcla() = enUnHilo { alcance ->
        val s = Servidor()
        s.filas = """[{"fecha":"$hoy","dieta_id":"55555555-5555-4555-8555-555555555555","ajustes":{"desayuno":{"deltaKcal":300}}}]"""
        val m = modelo(s, alcance)
        m.cargar()
        assertTrue(m.ajustesDeHoy.isEmpty())
    }

    /** Lo que se ajustó antes de la migración (salió «sin tabla») sube en la primera hidratación con la tabla. */
    @Test
    fun siElServidorNoTieneNadaYElTelefonoSiSeSube() = enUnHilo { alcance ->
        val s = Servidor()
        Disco(raiz, TOKEN).guardar(AjustesDieta.archivo(DIETA_ID), AjustesDieta.guardados(hoy, mapOf("desayuno" to AjusteComida(deltaKcal = 150))))
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        assertEquals(150.0, s.guardados.lastOrNull()?.get("p_ajustes")?.get("desayuno")?.get("deltaKcal")?.comoNumero)
    }

    @Test
    fun losDeAyerNoValen() = enUnHilo { alcance ->
        val s = Servidor()
        Disco(raiz, TOKEN).guardar(AjustesDieta.archivo(DIETA_ID), AjustesDieta.guardados("2026-01-01", mapOf("desayuno" to AjusteComida(deltaKcal = 150))))
        val m = modelo(s, alcance)
        m.cargar()
        assertTrue(m.ajustesDeHoy.isEmpty())
    }

    @Test
    fun laOpcionElegidaVaEnLaCuentaYLasCantidadesDeOtraNoValen() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(opcion = 0, cantidades = mapOf("0" to 50.0)), mapOf("desayuno" to 0))
        assertEquals(50.0, m.diaAjustado(mapOf("desayuno" to 0)).getValue("desayuno").alimentos[0].qty)
        // Con la opción B a la vista, las cantidades de la A no se aplican.
        val b = m.diaAjustado(mapOf("desayuno" to 1)).getValue("desayuno")
        assertEquals(listOf("Yogur"), b.alimentos.map { it.nombre })
        assertEquals(200.0, b.alimentos[0].qty)
        // Sin decir cuál se ve, la del ajuste.
        assertEquals(0, m.comidasParaAjustar(emptyMap()).first().opcion)
    }

    /**
     * La dieta se vuelve a publicar con el mismo id: si en la posición de una cantidad a mano queda otro alimento, esa
     * cantidad no vale (los 60 g de avena no pueden pasar a ser 60 huevos).
     */
    @Test
    fun lasCantidadesAManoQuedanAncladasAlAlimento() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(deltaKcal = 50, opcion = 0, cantidades = mapOf("0" to 60.0)), mapOf("desayuno" to 0))
        assertEquals(mapOf("0" to AnclaAlimento("Avena", "g")), m.ajustesDeHoy["desayuno"]?.anclas)
        m.outbox?.drenar()
        assertEquals("Avena", s.guardados.last()["p_ajustes"]?.get("desayuno")?.get("anclas")?.get("0")?.get("nombre")?.comoTexto)
        // Mati invierte el orden de los alimentos del desayuno.
        s.dieta = DIETA.replace(AVENA + "," + HUEVOS, "$HUEVOS,$AVENA").replace("\"version\":1", "\"version\":2")
        assertNotEquals(DIETA, s.dieta)
        m.cargar()
        val d = m.diaAjustado(mapOf("desayuno" to 0)).getValue("desayuno")
        assertEquals(listOf("Huevos", "Avena"), d.alimentos.map { it.nombre })
        assertNotEquals(60.0, d.alimentos[0].qty, "los 60 eran de avena")
        assertTrue(d.kcal > d.kcalPlan, "las +50 siguen")
    }

    /** 60 g de avena a mano y después la reemplaza por pan: los «60» no pueden quedar pegados al pan (60 rebanadas). */
    @Test
    fun unReemplazoSueltaLaCantidadAManoDeEseAlimento() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(deltaKcal = 100, opcion = 0, cantidades = mapOf("0" to 60.0, "1" to 4.0)), mapOf("desayuno" to 0))
        val avena = m.comidasDelDia[0].opciones[0].alimentos[0]
        m.sustituir(
            avena,
            ValorJson.parsear("""{"name":"Pan integral","qty":2,"unit":"rebanada","kcal":140,"prot":6,"carb":24,"fat":2}"""),
            "desayuno", 0, 0,
        )
        assertEquals(mapOf("1" to 4.0), m.ajustesDeHoy["desayuno"]?.cantidades, "la de la avena se va, la de los huevos queda")
        assertEquals(100, m.ajustesDeHoy["desayuno"]?.deltaKcal)
        m.revertir("desayuno", 0, 1)
        assertEquals(emptyMap<String, Double>(), m.ajustesDeHoy["desayuno"]?.cantidades)
    }

    @Test
    fun enLaDemoNoSeEscribeNada() = enUnHilo { alcance ->
        val m = ModeloApp(ClienteRpc(transporte = TransporteProgramado { _, _ -> 200 to "[]" }), TokenEnMemoria(null), raiz, PreferenciasEnMemoria(), alcance)
        m.entrarEnDemo(
            """{"dias":[]}""",
            """{"macros_target":{"kcal":2000},"comidas":[{"id":"d","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}]}]}]}""",
        )
        m.ajustar("d", AjusteComida(deltaKcal = 100), emptyMap())
        assertEquals(100, m.ajustesDeHoy["d"]?.deltaKcal, "en la demo se puede probar")
        assertNull(m.outbox)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
        const val DIETA_ID = "44444444-4444-4444-8444-444444444444"
        const val AVENA = """{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7}"""
        const val HUEVOS = """{"name":"Huevos","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18}"""
        val DIETA = """[{"id":"$DIETA_ID","version":1,"estructura":{"macros_target":{"kcal":2000,"prot":150,"carb":200,"fat":60},"comidas":[""" +
            """{"id":"desayuno","name":"Desayuno","options":[{"name":"A","foods":[$AVENA,$HUEVOS]},{"name":"B","foods":[{"name":"Yogur","qty":200,"unit":"g","kcal":120,"prot":10,"carb":14,"fat":3}]}]},""" +
            """{"id":"almuerzo","name":"Almuerzo","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7},{"name":"Arroz","qty":150,"unit":"g","kcal":195,"prot":4,"carb":42,"fat":0.5}]}]}""" +
            "]}}]"
    }
}
