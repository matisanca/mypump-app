package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AgregadosComida
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AlimentoAgregado
import com.pumpteam.mypump.reglas.MacrosPor100
import com.pumpteam.mypump.reglas.MarcaComida
import com.pumpteam.mypump.reglas.AnclaAlimento
import com.pumpteam.mypump.reglas.FechaLocal
import java.util.Collections
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
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

        /** La base rechaza el día (el 22023 de nativa_004 con un `ajustes` de más de 16000 bytes en jsonb). */
        @Volatile var rechaza = false

        /** `mypump_get_food_swaps` falla (un 500). */
        @Volatile var sinSwaps = false
        @Volatile var filas = "[]"

        /** Otra estructura con el mismo id: Mati volvió a publicar (013 actualiza en el lugar). */
        @Volatile var dieta: String? = null

        /** La lectura de los ajustes contesta tarde: la escritura que sale después llega antes (revisión del 20-oct). */
        @Volatile var getLento = false
        @Volatile var getEmpezo = false

        /** Dos teléfonos de la misma cuenta: lo que guarda uno es lo que lee el otro (el día de ajustes y las marcas). */
        @Volatile var persistente = false

        /** Las marcas no salen (sin red para esa escritura): quedan en la cola. */
        @Volatile var marcasCaidas = false
        val marcas: MutableMap<String, ValorJson> = Collections.synchronizedMap(mutableMapOf())
        @Volatile var marcasEscritas = 0

        val transporte = TransporteProgramado { fn, cuerpo ->
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to (dieta ?: DIETA)
                "mypump_get_food_swaps" -> if (sinSwaps) 500 to """{"message":"caído"}""" else 200 to "[]"
                "mypump_guardar_ajustes_dieta" ->
                    if (sinTabla) 404 to """{"code":"PGRST202","message":"Could not find the function"}"""
                    else if (guardarFalla) 500 to """{"message":"caído"}"""
                    else if (rechaza) 400 to """{"code":"22023","message":"ajustes invalidos"}"""
                    else {
                        guardados += cuerpo
                        if (persistente) {
                            filas = ValorJson.Lista(listOf(ValorJson.objeto(
                                "fecha" to (cuerpo["p_fecha"] ?: ValorJson.Nulo), "dieta_id" to (cuerpo["p_dieta_id"] ?: ValorJson.Nulo),
                                "tipo_dia" to ValorJson.Nulo, "ajustes" to (cuerpo["p_ajustes"] ?: ValorJson.objeto()),
                            ))).serializar()
                        }
                        200 to "true"
                    }
                "mypump_marcar_comida" ->
                    if (marcasCaidas) {
                        503 to """{"message":"sin red"}"""
                    } else {
                        marcasEscritas++
                        val id = cuerpo["p_comida_id"]!!.comoTexto!!
                        marcas[id] = ValorJson.objeto(
                            "comida_id" to ValorJson.Texto(id), "opcion_elegida" to (cuerpo["p_opcion"] ?: ValorJson.Nulo),
                            "estado" to (cuerpo["p_estado"] ?: ValorJson.Nulo),
                            "foods_excluidos" to (cuerpo["p_foods_excluidos"]?.takeIf { it !is ValorJson.Nulo } ?: ValorJson.Lista(emptyList())),
                        )
                        200 to "true"
                    }
                "mypump_desmarcar_comida" -> {
                    marcasEscritas++
                    cuerpo["p_comida_id"]?.comoTexto?.let { marcas.remove(it) }
                    200 to "true"
                }
                "mypump_get_comidas_marcadas" ->
                    200 to (if (persistente) ValorJson.Lista(synchronized(marcas) { marcas.values.toList() }).serializar() else "[]")
                "mypump_get_ajustes_dieta" ->
                    if (sinTabla) {
                        404 to """{"code":"PGRST202","message":"Could not find the function"}"""
                    } else {
                        val foto = filas   // lo que tiene el servidor cuando lee
                        getEmpezo = true
                        if (getLento) {
                            repeat(300) { if (guardados.isEmpty()) delay(10) }
                            delay(50)
                        }
                        200 to foto
                    }
                "mypump_save_food_swap", "mypump_delete_food_swap" -> 200 to "true"
                else -> 200 to "[]"
            }
        }
    }

    private fun modelo(s: Servidor, alcance: CoroutineScope, otra: java.io.File? = null) =
        ModeloApp(ClienteRpc(transporte = s.transporte), TokenEnMemoria(TOKEN), otra ?: raiz, PreferenciasEnMemoria(), alcance)

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

    /**
     * Revisión del 20-oct: un cambio hecho mientras la hidratación espera al servidor llegaba antes que la respuesta (la
     * cola manda al toque) y la foto vieja del servidor lo pisaba; el cambio siguiente borraba también lo del servidor.
     */
    @Test
    fun unCambioDuranteLaHidratacionNoSePierde() = enUnHilo { alcance ->
        val s = Servidor()
        s.filas = """[{"fecha":"$hoy","dieta_id":"$DIETA_ID","ajustes":{}}]"""
        s.getLento = true
        val m = modelo(s, alcance)
        val carga = async { m.cargar() }
        repeat(500) { if (!s.getEmpezo) delay(10) }
        assertTrue(s.getEmpezo)
        m.ajustar("desayuno", AjusteComida(deltaKcal = 100), emptyMap())
        carga.await()
        assertEquals(100, m.ajustesDeHoy["desayuno"]?.deltaKcal, "el cambio sobrevive a la hidratación")
        m.ajustar("almuerzo", AjusteComida(deltaKcal = -50), emptyMap())
        m.outbox?.drenar()
        assertEquals(100.0, s.guardados.last()["p_ajustes"]?.get("desayuno")?.get("deltaKcal")?.comoNumero, "y el siguiente no lo borra del servidor")
    }

    /** El resumen que ve Mati son las kcal del plan de hoy: otra opción a la vista o un reemplazo lo cambian. */
    @Test
    fun otraOpcionOUnReemplazoRehacenElResumen() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.ajustar("almuerzo", AjusteComida(deltaKcal = -50, compensar = false), emptyMap())
        m.outbox?.drenar()
        fun planDelDesayuno(): Double? = (s.guardados.last()["p_resumen"] as? ValorJson.Lista)?.elementos
            ?.firstOrNull { it["comida_id"]?.comoTexto == "desayuno" }?.get("kcal_plan")?.comoNumero
        assertEquals(614.0, planDelDesayuno())
        m.verOpcion("desayuno", 1)
        m.outbox?.drenar()
        assertEquals(120.0, planDelDesayuno(), "el yogur de la B")
        m.verOpcion("desayuno", 0)
        val avena = m.comidasDelDia[0].opciones[0].alimentos[0]
        m.sustituir(
            avena,
            ValorJson.parsear("""{"name":"Pan integral","qty":2,"unit":"rebanada","kcal":140,"prot":6,"carb":24,"fat":2}"""),
            "desayuno", 0, 0,
        )
        m.outbox?.drenar()
        assertEquals(374.0, planDelDesayuno(), "el pan (140) y los huevos (234)")
    }

    @Test
    fun lasOpcionesVistasNoPasanALaDemo() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.verOpcion("desayuno", 1)
        assertEquals(1, m.opcionesVistas["desayuno"])
        m.entrarEnDemo("""{"dias":[]}""", """{"comidas":[]}""")
        assertTrue(m.opcionesVistas.isEmpty())
        m.salirDeDemo()
        assertTrue(m.opcionesVistas.isEmpty())
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
        // Sin kcal sumadas: con los dos alimentos a mano no queda nada que escalar y se acotarían a cero.
        m.ajustar("desayuno", AjusteComida(opcion = 0, cantidades = mapOf("0" to 60.0, "1" to 4.0)), mapOf("desayuno" to 0))
        val avena = m.comidasDelDia[0].opciones[0].alimentos[0]
        m.sustituir(
            avena,
            ValorJson.parsear("""{"name":"Pan integral","qty":2,"unit":"rebanada","kcal":140,"prot":6,"carb":24,"fat":2}"""),
            "desayuno", 0, 0,
        )
        assertEquals(mapOf("1" to 4.0), m.ajustesDeHoy["desayuno"]?.cantidades, "la de la avena se va, la de los huevos queda")
        m.revertir("desayuno", 0, 1)
        assertNull(m.ajustesDeHoy["desayuno"], "sin nada a mano ni kcal, el ajuste se va")
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

    // ── Alimentos agregados (2.0.3, D1) ──

    private fun huevo(ts: Long): AlimentoAgregado = AgregadosComida.agregado(
        AgregadosComida.Candidato("Huevo entero", MacrosPor100(143.0, 12.6, 0.7, 9.5), "unidad", 60.0, AlimentoAgregado.Origen.BASE),
        1.0, AgregadosComida.Medida("unidad", 60.0), ts,
    )

    /** Un agregado solo (sin otro cambio) ya es un ajuste: se guarda, sale con el día y va en el resumen de esa comida. */
    @Test
    fun unAgregadoSaleConElDiaYVaEnElResumen() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.drenar()
        m.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(1))), emptyMap())
        assertEquals(1, m.ajustesDeHoy["desayuno"]?.agregados?.size)
        assertEquals(614.0 + 86, m.diaAjustado(emptyMap()).getValue("desayuno").kcal)
        m.outbox?.drenar()
        val g = s.guardados.last()
        val ag = (g["p_ajustes"]?.get("desayuno")?.get("agregados") as ValorJson.Lista).elementos
        assertEquals("Huevo entero", ag[0]["nombre"]?.comoTexto)
        assertEquals(614.0 + 525 + 86, g["p_kcal_dia"]?.comoNumero)
        val resumen = (g["p_resumen"] as ValorJson.Lista).elementos
        val r0 = (resumen[0]["agregados"] as ValorJson.Lista).elementos
        assertEquals(86.0, r0[0]["kcal"]?.comoNumero)
        assertEquals(60.0, r0[0]["gramos"]?.comoNumero)
        // El almuerzo, sin agregados, queda como antes (sin la clave).
        assertNull(resumen[1]["agregados"])
        val otro = modelo(Servidor(), alcance)
        otro.cargar()
        assertEquals(listOf(1L), otro.ajustesDeHoy["desayuno"]?.agregados?.map { it.ts })
    }

    /** Borrar un agregado de una comida marcada «Comí»: el tilde del borrado se va y los de los siguientes bajan uno. */
    @Test
    fun borrarUnAgregadoCorreLosTildes() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(1), huevo(2), huevo(3))), emptyMap())
        m.marcar("desayuno", MarcaComida.Estado.COMIDO, 0)
        // Plan de 2 (avena, huevos): los agregados son 2, 3 y 4. Destilda el segundo y el tercero.
        m.alternarAlimento("desayuno", 3)
        m.alternarAlimento("desayuno", 4)
        m.borrarAgregado("desayuno", 2, emptyMap())
        assertEquals(listOf(1L, 3L), m.ajustesDeHoy["desayuno"]?.agregados?.map { it.ts })
        assertEquals(listOf(3), m.marcasDeHoy["desayuno"]?.excluidos)
        assertEquals(614.0 + 86, m.consumo(emptyMap()).kcal)
        m.borrarAgregado("desayuno", 1, emptyMap())
        m.borrarAgregado("desayuno", 3, emptyMap())
        assertNull(m.ajustesDeHoy["desayuno"])
        assertEquals(emptyList<Int>(), m.marcasDeHoy["desayuno"]?.excluidos)
    }

    /**
     * Revisión del 3-nov: un día que la base rechaza termina en fallidos; la hidratación ya no lo veía pendiente y la fila
     * vieja del servidor pisaba el día del teléfono sin aviso. Ahora no lo pisa, Dieta avisa y el próximo cambio lo resuelve.
     */
    @Test
    fun unDiaQueLaBaseRechazaNoLoPisaLaHidratacionYSeAvisa() = enUnHilo { alcance ->
        val s = Servidor().apply { rechaza = true }
        val m = modelo(s, alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(deltaKcal = 50), emptyMap())
        repeat(12) { if ((m.outbox?.pendientes() ?: 0) > 0) m.outbox?.drenar() }
        assertEquals(0, m.outbox?.pendientes())
        assertEquals(1, m.outbox?.fallidos()?.size)
        assertTrue(m.ajustesSinGuardar.value, "Dieta avisa que no se guardó")
        // La fila vieja del servidor no pisa el día del teléfono.
        s.filas = """[{"fecha":"$hoy","dieta_id":"$DIETA_ID","tipo_dia":null,"ajustes":{"almuerzo":{"deltaKcal":-100,"compensar":false,"omitida":false,"opcion":0,"cantidades":{}}}}]"""
        m.hidratarDieta()
        assertEquals(50, m.ajustesDeHoy["desayuno"]?.deltaKcal)
        assertNull(m.ajustesDeHoy["almuerzo"])
        assertTrue(m.ajustesSinGuardar.value)
        // El próximo cambio sale entero: el aviso se va y el fallido de ese día se olvida (la hidratación vuelve a valer).
        s.rechaza = false
        m.ajustar("desayuno", AjusteComida(deltaKcal = 100), emptyMap())
        m.outbox?.drenar()
        repeat(100) { if (m.ajustesSinGuardar.value || m.outbox?.fallidos().orEmpty().isNotEmpty()) delay(10) }
        assertFalse(m.ajustesSinGuardar.value)
        assertTrue(m.outbox?.fallidos().orEmpty().isEmpty())
        m.hidratarDieta()
        assertEquals(-100, m.ajustesDeHoy["almuerzo"]?.deltaKcal, "con el día guardado, lo del servidor vuelve a valer")
    }

    /** «Volver al plan» no deja en la marca tildes de agregados que ya no están: siguen a cada agregado por `_ts`. */
    @Test
    fun volverAlPlanNoDejaTildesDeAgregadosViejos() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(1), huevo(2))), emptyMap())
        m.marcar("desayuno", MarcaComida.Estado.COMIDO, 0)
        m.alternarAlimento("desayuno", 0)
        m.alternarAlimento("desayuno", 3)
        assertEquals(listOf(0, 3), m.marcasDeHoy["desayuno"]?.excluidos)
        m.ajustar("desayuno", null, emptyMap())
        assertEquals(listOf(0), m.marcasDeHoy["desayuno"]?.excluidos, "el del plan queda; el del agregado se va")
        m.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(5), huevo(6))), emptyMap())
        assertEquals(234.0 + 86 * 2, m.consumo(emptyMap()).kcal, "los agregados nuevos llegan tildados")
    }

    /** Dos «Sacar» seguidos sin esperar (dos toques rápidos): cada uno saca el suyo y los tildes quedan bien. */
    @Test
    fun dosBorradosSeguidosNoCorrenMalLosTildes() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(1), huevo(2), huevo(3))), emptyMap())
        m.marcar("desayuno", MarcaComida.Estado.COMIDO, 0)
        m.alternarAlimento("desayuno", 4)
        listOf(
            alcance.launch { m.borrarAgregado("desayuno", 1, emptyMap()) },
            alcance.launch { m.borrarAgregado("desayuno", 2, emptyMap()) },
            alcance.launch { m.borrarAgregado("desayuno", 2, emptyMap()) },
        ).joinAll()
        assertEquals(listOf(3L), m.ajustesDeHoy["desayuno"]?.agregados?.map { it.ts })
        assertEquals(listOf(2), m.marcasDeHoy["desayuno"]?.excluidos, "el tercero sigue destildado, ahora en el índice 2")
    }

    /** Cambiar de opción saca las cantidades a mano (eran de la otra) pero deja los agregados. */
    @Test
    fun losAgregadosSobrevivenAlCambioDeOpcion() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.ajustar("desayuno", AjusteComida(cantidades = mapOf("0" to 50.0), agregados = listOf(huevo(1))), mapOf("desayuno" to 0))
        val a = m.ajustesDeHoy.getValue("desayuno")
        m.ajustar("desayuno", a.copy(opcion = 1, cantidades = emptyMap()), mapOf("desayuno" to 1))
        assertEquals(1, m.ajustesDeHoy["desayuno"]?.agregados?.size)
        assertTrue(m.ajustesDeHoy["desayuno"]?.cantidades?.isEmpty() == true)
        assertEquals(120.0 + 86, m.diaAjustado(mapOf("desayuno" to 1)).getValue("desayuno").kcal)
    }

    @Test
    fun losRecientesQuedanEnElTelefono() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.recordarReciente(huevo(1))
        m.recordarReciente(huevo(2).copy(nombre = "Clara de huevo"))
        m.recordarReciente(huevo(3))
        assertEquals(listOf(3L, 2L), m.agregadosRecientes.value.map { it.ts })
        val otro = modelo(Servidor(), alcance)
        otro.cargar()
        assertEquals(listOf("Huevo entero", "Clara de huevo"), otro.agregadosRecientes.value.map { it.nombre })
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

    /**
     * Segunda revisión del 3-nov: la hidratación de los ajustes corría los tildes ENCOLANDO una marca. Como en el arranque los
     * ajustes se hidratan antes que las marcas, la marca vieja de este teléfono quedaba en la cola y le ganaba a la más nueva
     * de otro: se perdían las exclusiones del otro teléfono. Ahora se remapea solo en memoria.
     */
    @Test
    fun laHidratacionNoPisaLaMarcaDeOtroTelefono() = enUnHilo { alcance ->
        val s = Servidor().apply { persistente = true }
        // Teléfono A: dos huevos agregados, «Comí» y destilda el segundo (índice 3: plan de 2 + agregado 1).
        val a = modelo(s, alcance)
        a.cargar()
        a.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(1), huevo(2))), emptyMap())
        a.marcar("desayuno", MarcaComida.Estado.COMIDO, 0)
        a.alternarAlimento("desayuno", 3)
        a.outbox?.drenar()
        assertEquals(0, a.outbox?.pendientes())

        // Teléfono B: lo lee, saca el primer huevo (el segundo pasa al índice 2) y destilda la avena.
        val b = modelo(s, alcance, carpetaTemporal("ajustes-dieta-b"))
        b.cargar()
        assertEquals(listOf(3), b.marcasDeHoy["desayuno"]?.excluidos)
        b.borrarAgregado("desayuno", 1, emptyMap())
        b.alternarAlimento("desayuno", 0)
        b.outbox?.drenar()
        assertEquals(0, b.outbox?.pendientes())
        assertEquals(setOf(0, 2), b.marcasDeHoy["desayuno"]?.excluidos?.toSet())
        val escritas = s.marcasEscritas

        // A vuelve a abrir: trae el día de B y su marca, sin mandar la suya vieja.
        a.cargar()
        a.outbox?.drenar()
        assertEquals(listOf(2L), a.ajustesDeHoy["desayuno"]?.agregados?.map { it.ts })
        assertEquals(setOf(0, 2), a.marcasDeHoy["desayuno"]?.excluidos?.toSet(), "la marca de B, no la vieja de A remapeada")
        assertTrue(a.outbox?.pendientesPorClave().orEmpty().keys.none { it.startsWith("comida|") })
        assertEquals(escritas, s.marcasEscritas, "A no escribió ninguna marca")
        val excl = (s.marcas["desayuno"]?.get("foods_excluidos") as ValorJson.Lista).elementos.mapNotNull { it.comoNumero?.toInt() }
        assertEquals(setOf(0, 2), excl.toSet())
    }

    /**
     * Con una marca de esa comida todavía en la cola (lo último que hizo el cliente en este teléfono), la hidratación sí
     * corrige la cola: si no, saldría con los índices viejos.
     */
    @Test
    fun conUnaMarcaEnLaColaLaHidratacionLaCorrigeEnLaCola() = enUnHilo { alcance ->
        val s = Servidor().apply { persistente = true }
        val a = modelo(s, alcance)
        a.cargar()
        a.ajustar("desayuno", AjusteComida(compensar = false, agregados = listOf(huevo(1), huevo(2))), emptyMap())
        a.outbox?.drenar()
        s.marcasCaidas = true
        a.marcar("desayuno", MarcaComida.Estado.COMIDO, 0)
        a.alternarAlimento("desayuno", 3)   // queda en la cola: esa escritura no sale
        // Otro teléfono sacó el primer huevo.
        val ajustes = ValorJson.objeto("desayuno" to AjusteComida(compensar = false, agregados = listOf(huevo(2))).aValor())
        s.filas = ValorJson.Lista(listOf(ValorJson.objeto(
            "fecha" to ValorJson.Texto(hoy), "dieta_id" to ValorJson.Texto(DIETA_ID), "tipo_dia" to ValorJson.Nulo, "ajustes" to ajustes,
        ))).serializar()
        a.hidratarDieta()
        assertEquals(listOf(2L), a.ajustesDeHoy["desayuno"]?.agregados?.map { it.ts })
        assertEquals(listOf(2), a.marcasDeHoy["desayuno"]?.excluidos)
        val op = a.outbox?.pendientesPorClave().orEmpty()["comida|$hoy|desayuno"]
        assertEquals(listOf(2), op?.let { MarcasComidas.desdePayload(it.payload) }?.excluidos, "la cola sale con el índice nuevo")
    }

    /** El aviso que quedó de ayer (la app abierta pasada la medianoche) se apaga al hidratar si hoy no hay fallidos. */
    @Test
    fun elAvisoDeAyerSeApagaAlHidratarSinFallidosDeHoy() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m._ajustesSinGuardar.value = true   // lo que dejó el día anterior
        s.sinTabla = true                   // tampoco hace falta que el servidor conteste
        m.hidratarDieta()
        assertFalse(m.ajustesSinGuardar.value)
    }
}
