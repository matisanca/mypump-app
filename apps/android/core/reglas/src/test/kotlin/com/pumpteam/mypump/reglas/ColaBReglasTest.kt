package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.PlanSuplementacion
import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La cola B (2.3.0): fin de plan, compras por país y entreno en casa. Datos inventados y obvios. */
class ColaBReglasTest {
    private fun j(s: String) = ValorJson.parsear(s)

    // ---------------------------------------------------------------- Textos

    /** Lo que al alumno no se le dice, en ninguna de las tres funciones. */
    @Test fun losTextosCumplenLasReglas() {
        val prohibidas = listOf("coach", "entrenador", "renovaci", "vence", "vencimiento", "vencid", "pausa", "vacaciones", "inteligencia artificial")
        val textos = FinPlan.Textos.todos + Compras.Textos.todos + Casa.Textos.todos + Casa.Textos.hastaKg(20.0)
        for (t in textos) {
            val b = t.lowercase()
            for (p in prohibidas) assertFalse(p in b, "«$t» dice «$p»")
            assertFalse(Regex("\\b(ia|rir)\\b").containsMatchIn(b), t)
        }
    }

    @Test fun losTextosSonLosDelContrato() {
        assertEquals("Tu recorrido con Mati", FinPlan.Textos.TARJETA_TITULO)
        assertEquals("Mirá todo lo que hiciste en estos meses.", FinPlan.textoTarjeta(Recorrido.Estado.PUBLICADO))
        assertEquals("Mati ya recibió tu pedido.", FinPlan.textoTarjeta(Recorrido.Estado.PEDIDO))
        assertEquals("Tu videollamada con Mati ya está agendada.", FinPlan.textoTarjeta(Recorrido.Estado.AGENDADO))
        assertEquals("¿Qué fue lo mejor de estos meses?", FinPlan.Textos.pregunta("mejor"))
        assertEquals("¿Qué te costó más?", FinPlan.Textos.pregunta("costo"))
        assertEquals("¿Qué te gustaría lograr ahora?", FinPlan.Textos.pregunta("objetivo"))
        assertEquals("Tocá “Dónde comprarlo” para ver dónde conseguir cada suplemento.", Compras.Textos.AYUDA)
        assertEquals("Marcá lo que tenés, o “No tengo nada de esto”.", Casa.Textos.SIN_DATOS)
        assertEquals("hasta 20 kg", Casa.Textos.hastaKg(20.0))
        assertEquals("hasta 12,5 kg", Casa.Textos.hastaKg(12.5))
    }

    // ---------------------------------------------------------------- Fin de plan

    private val visible = """{"habilitado":true,"visible":true,"estado":"publicado","agenda":"mati","respuestas":{},
        "resumen":{"titulo":"Tus seis meses","mensaje":"Gran trabajo.","logros":[{"titulo":"Peso","valor":"-6 kg","detalle":"De 90 a 84"},{"titulo":"Entrenos","valor":"72"}]}}"""

    @Test fun finPlanSeLeeTolerante() {
        val r = (FinPlan.leer(j(visible)) as FinPlan.Lectura.Visible).recorrido
        assertEquals(Recorrido.Estado.PUBLICADO, r.estado)
        assertEquals("Tus seis meses", FinPlan.tituloHoja(r))
        assertEquals(listOf(LogroRecorrido("Peso", "-6 kg", "De 90 a 84"), LogroRecorrido("Entrenos", "72", null)), r.resumen.logros)
        assertFalse(r.agendaEnApp)
        assertTrue(FinPlan.pidePreguntas(r))
        assertNull(FinPlan.cartel(r))

        // Apagado, sin la clave, null o cualquier cosa rara: no se ve.
        for (x in listOf("""{"habilitado":false}""", "{}", "null", "[]", "5", """{"habilitado":"true","visible":true}""")) {
            assertEquals(FinPlan.Lectura.Apagado, FinPlan.leer(j(x)), x)
        }
        // Prendido pero no para esta cuenta, estado desconocido o resumen sin logros válidos: no se muestra.
        for (x in listOf(
            """{"habilitado":true,"visible":false}""", """{"habilitado":true}""",
            visible.replace("\"publicado\"", "\"cerrado\""), visible.replace("\"publicado\"", "\"otro_nuevo\""), visible.replace("\"estado\":\"publicado\",", ""),
            """{"habilitado":true,"visible":true,"estado":"publicado","resumen":{"logros":[]}}""",
            """{"habilitado":true,"visible":true,"estado":"publicado","resumen":{"logros":[{"titulo":"Sin valor"},{"valor":"3"},5]}}""",
            """{"habilitado":true,"visible":true,"estado":"publicado"}""",
        )) assertEquals(FinPlan.Lectura.NoVisible, FinPlan.leer(j(x)), x)
    }

    @Test fun finPlanCamposNuevosYFaltantesNoRompen() {
        val r = (FinPlan.leer(j("""{"habilitado":true,"visible":true,"estado":"pedido","agenda":"app","campo_nuevo":[1],
            "respuestas":{"mejor":"Bajé de peso","otra":7},"resumen":{"logros":[{"titulo":"A","valor":"1","nuevo":true},{"titulo":" ","valor":"2"},
            {"titulo":"B","valor":"2"},{"titulo":"C","valor":"3"},{"titulo":"D","valor":"4"},{"titulo":"E","valor":"5"},{"titulo":"F","valor":"6"},{"titulo":"G","valor":"7"}]}}""")) as FinPlan.Lectura.Visible).recorrido
        assertEquals("Tu recorrido", FinPlan.tituloHoja(r))
        assertNull(r.resumen.mensaje)
        assertEquals(FinPlan.MAX_LOGROS, r.resumen.logros.size)
        assertEquals("Bajé de peso", r.respuestas.mejor)
        assertFalse(FinPlan.pidePreguntas(r))
        assertEquals("Listo. Mati ya recibió tu pedido." to "Cuando esté tu horario lo vas a ver arriba de Entreno.", FinPlan.cartel(r))
        assertEquals("Listo. Mati ya recibió tu pedido." to "Te escribe para coordinar el horario.", FinPlan.cartel(r.copy(agendaEnApp = false)))
        assertEquals("Tu videollamada con Mati ya está agendada." to null, FinPlan.cartel(r.copy(estado = Recorrido.Estado.AGENDADO)))
    }

    @Test fun finPlanSeAbreSolaUnaVezYSoloSinPedir() {
        val r = (FinPlan.leer(j(visible)) as FinPlan.Lectura.Visible).recorrido
        assertTrue(FinPlan.seAbreSola(r, yaSeAbrio = false))
        assertFalse(FinPlan.seAbreSola(r, yaSeAbrio = true))
        assertFalse(FinPlan.seAbreSola(r.copy(estado = Recorrido.Estado.PEDIDO), yaSeAbrio = false))
        assertFalse(FinPlan.seAbreSola(null, yaSeAbrio = false))
    }

    @Test fun finPlanRespuestasConTopeYSoloLoEscrito() {
        var r = RespuestasRecorrido().con("mejor", "x".repeat(700)).con("costo", "   ").con("otra", "no")
        assertEquals(500, r.mejor.length)
        assertEquals(ValorJson.objeto("mejor" to ValorJson.Texto("x".repeat(500))), r.aValor())
        r = RespuestasRecorrido().con("objetivo", "  Seguir así  ")
        assertEquals(ValorJson.objeto("objetivo" to ValorJson.Texto("Seguir así")), r.aValor())
        assertEquals(ValorJson.Objeto(emptyMap()), RespuestasRecorrido().aValor())
        // El tope no parte un emoji por la mitad.
        val conEmoji = "a".repeat(499) + "💪💪"
        assertEquals("a".repeat(499) + "💪", FinPlan.recortar(conEmoji))
    }

    // ---------------------------------------------------------------- Compras

    private val supl = PlanSuplementacion.desde(j("""{"suplementacion":{"items":[
        {"nombre":"Creatina de prueba","momento":"desayuno"},{"nombre":"  Omega de prueba ","momento":"almuerzo"},
        {"nombre":"Magnesio de prueba","momento":"dormir"},{"nombre":"Zinc de prueba","estado":"sale"}]},"esquema":1}"""))!!.suplementacion

    private val compras = """{"habilitado":true,"pais":"AR","items":[
        {"nombre":"Creatina de prueba","opciones":[
            {"producto":"Creatina Inventada 300 g","tienda":"Tienda Ejemplo Uno","url":"https://tienda-uno.invalid/creatina","nota":"La de pote blanco"},
            {"producto":"Creatina Falsa","tienda":"Tienda Ejemplo Dos","url":"http://tienda-dos.invalid/x"},
            {"producto":"Sin tienda"},{"tienda":"Sin producto"}]},
        {"nombre":" Omega de prueba","opciones":[{"producto":"Omega Inventado","tienda":"Tienda Ejemplo Uno"}]},
        {"nombre":"magnesio de prueba","opciones":[{"producto":"No cruza","tienda":"Tienda Ejemplo Uno"}]},
        {"nombre":"Zinc de prueba","opciones":[{"producto":"Zinc Inventado","tienda":"Tienda Ejemplo Uno"}]},
        {"nombre":"Vacío","opciones":[]},{"opciones":[{"producto":"x","tienda":"y"}]}]}"""

    @Test fun comprasCruzaPorNombreExactoDespuesDeRecortar() {
        val c = Compras.leer(j(compras))!!
        assertEquals("AR", c.pais)
        val por = Compras.porItem(supl.items, c)
        // Creatina y Omega (con espacios de más de los dos lados) cruzan; «magnesio» en minúscula no; el que sale no lleva botón.
        assertEquals(setOf(0, 1), por.keys)
        assertEquals(listOf("Creatina Inventada 300 g", "Creatina Falsa"), por[0]!!.map { it.producto })
        assertEquals("Tienda Ejemplo Uno", por[0]!![0].tienda)
        assertEquals("La de pote blanco", por[0]!![0].nota)
        assertTrue(Compras.opcionesDe("Creatina", c).isEmpty())
        assertTrue(Compras.porItem(supl.items, null).isEmpty())
    }

    @Test fun comprasUrlQueNoEsHttpsSeIgnora() {
        val c = Compras.leer(j(compras))!!
        val o = Compras.opcionesDe("Creatina de prueba", c)
        assertEquals("https://tienda-uno.invalid/creatina", o[0].url)
        // La opción con http se muestra, sin botón.
        assertEquals("Creatina Falsa", o[1].producto)
        assertNull(o[1].url)
        for (mala in listOf(
            "http://tienda.invalid", "ftp://tienda.invalid", "javascript:alert(1)", "tienda.invalid", "//tienda.invalid", "https://", "https:///ruta",
            "https://tienda.invalid/a b", " ", "", "intent://tienda.invalid#Intent;end", "https://usuario@tienda.invalid/", "market://details?id=x",
            "https://tienda.invalid/\nhttp://otra.invalid",
        )) assertNull(Compras.urlSegura(mala), "«$mala»")
        assertNull(Compras.urlSegura(null))
        assertEquals("https://tienda.invalid/p?id=1&x=á", Compras.urlSegura("  https://tienda.invalid/p?id=1&x=á "))
        assertNotNull(Compras.urlSegura("HTTPS://Tienda.invalid"))
    }

    @Test fun comprasApagadoVacioYTope() {
        for (x in listOf("""{"habilitado":false}""", "null", "{}", "[]")) assertNull(Compras.leer(j(x)), x)
        val vacio = Compras.leer(j("""{"habilitado":true,"items":[]}"""))!!
        assertTrue(vacio.vacio)
        assertNull(vacio.pais)
        assertTrue(Compras.porItem(supl.items, vacio).isEmpty())
        assertTrue(Compras.leer(j("""{"habilitado":true}"""))!!.vacio)
        val muchas = (1..7).joinToString(",") { """{"producto":"P$it","tienda":"Tienda Ejemplo"}""" }
        val c = Compras.leer(j("""{"habilitado":true,"items":[{"nombre":"Creatina de prueba","opciones":[$muchas]},{"nombre":"Creatina de prueba","opciones":[{"producto":"Repetido","tienda":"T"}]}]}"""))!!
        assertEquals(listOf("P1", "P2", "P3", "P4"), Compras.opcionesDe("Creatina de prueba", c).map { it.producto })
    }

    // ---------------------------------------------------------------- Casa

    private val tipos = """[{"tipo":"mancuernas","nombre":"Mancuernas","kg":true},{"tipo":"banco_plano","nombre":"Banco plano","kg":false},{"tipo":"bandas_elasticas","nombre":"Bandas elásticas"}]"""
    private fun casa(abierta: String? = null, vigente: String? = null) =
        EstadoCasa.desde(j("""{"habilitado":true,"tipos":$tipos,"abierta":${abierta ?: "null"},"vigente":${vigente ?: "null"}}"""))!!
    private fun carga(estado: String, lugar: String, extra: String = "") = """{"id":"11111111-1111-4111-8111-111111111111","estado":"$estado","lugar":"$lugar","equipos":[],"sin_equipo":false,"nota":null$extra}"""

    @Test fun casaSeLeeTolerante() {
        for (x in listOf("""{"habilitado":false}""", "null", "{}", "[]")) assertNull(EstadoCasa.desde(j(x)), x)
        val e = EstadoCasa.desde(j("""{"habilitado":true,"nuevo":1,"tipos":[{"tipo":"mancuernas","nombre":"Mancuernas","kg":true,"x":1},{"tipo":"mancuernas","nombre":"Repetida"},{"tipo":"sin_nombre"},{"nombre":"Sin tipo"},7],
            "abierta":{"id":"a","estado":"borrador","lugar":"casa","equipos":[{"tipo":"mancuernas","kg":20},{"tipo":"banco_plano"},{"kg":3}],"sin_equipo":false,"nota":" Tengo poco lugar "},
            "vigente":{"id":"v","estado":"listo"}}"""))!!
        assertEquals(listOf(TipoCasa("mancuernas", "Mancuernas", true)), e.tipos)
        assertEquals(listOf(EquipoCasa("mancuernas", 20.0), EquipoCasa("banco_plano", null)), e.abierta!!.equipos)
        assertEquals("Tengo poco lugar", e.abierta!!.nota)
        // Sin `lugar` (un servidor anterior): gimnasio.
        assertFalse(e.vigente!!.esCasa)
        // Sin tipos igual hay interruptor.
        assertTrue(EstadoCasa.desde(j("""{"habilitado":true}"""))!!.tipos.isEmpty())
    }

    @Test fun casaElInterruptorEnCadaEstado() {
        data class Caso(val nombre: String, val e: EstadoCasa, val prendido: Boolean, val seMueve: Boolean, val alPrender: Casa.Movimiento, val alApagar: Casa.Movimiento, val pantalla: Casa.Pantalla)
        val nada = Casa.Movimiento.NADA
        val casos = listOf(
            Caso("sin nada", casa(), false, true, Casa.Movimiento.ELEGIR_CASA, nada, Casa.Pantalla.GIMNASIO),
            Caso("borrador de gimnasio", casa(carga("borrador", "gimnasio")), false, true, Casa.Movimiento.ELEGIR_CASA, nada, Casa.Pantalla.GIMNASIO),
            Caso("borrador de casa", casa(carga("borrador", "casa")), true, true, nada, Casa.Movimiento.ELEGIR_GIMNASIO, Casa.Pantalla.LISTA),
            Caso("casa enviada", casa(carga("a_revisar", "casa")), true, false, nada, nada, Casa.Pantalla.GIMNASIO),
            Caso("gimnasio enviado", casa(carga("enviado", "gimnasio")), false, false, nada, nada, Casa.Pantalla.GIMNASIO),
            Caso("gimnasio a confirmar", casa(carga("a_confirmar", "gimnasio"), carga("listo", "casa")), false, false, nada, nada, Casa.Pantalla.GIMNASIO),
            Caso("un estado que la app no conoce", casa(carga("estado_nuevo", "casa")), true, false, nada, nada, Casa.Pantalla.GIMNASIO),
            Caso("casa vigente", casa(vigente = carga("listo", "casa")), true, true, nada, Casa.Movimiento.NUEVO_GIMNASIO, Casa.Pantalla.VIGENTE),
            Caso("gimnasio vigente", casa(vigente = carga("listo", "gimnasio")), false, true, Casa.Movimiento.ELEGIR_CASA, nada, Casa.Pantalla.GIMNASIO),
            Caso("casa vigente y borrador de gimnasio", casa(carga("borrador", "gimnasio"), carga("listo", "casa")), false, true, Casa.Movimiento.ELEGIR_CASA, nada, Casa.Pantalla.GIMNASIO),
            Caso("casa vigente y borrador de casa", casa(carga("borrador", "casa"), carga("listo", "casa")), true, true, nada, Casa.Movimiento.ELEGIR_GIMNASIO, Casa.Pantalla.LISTA),
            Caso("gimnasio vigente y borrador de casa", casa(carga("borrador", "casa"), carga("listo", "gimnasio")), true, true, nada, Casa.Movimiento.ELEGIR_GIMNASIO, Casa.Pantalla.LISTA),
        )
        for (c in casos) {
            val i = Casa.interruptor(c.e)
            assertEquals(c.prendido, i.prendido, "${c.nombre}: prendido")
            assertEquals(c.seMueve, i.sePuedeMover, "${c.nombre}: se puede mover")
            assertEquals(c.alPrender, Casa.alMover(c.e, true), "${c.nombre}: al prender")
            assertEquals(c.alApagar, Casa.alMover(c.e, false), "${c.nombre}: al apagar")
            assertEquals(c.pantalla, Casa.pantalla(c.e), "${c.nombre}: pantalla")
        }
        assertEquals(Casa.Pantalla.GIMNASIO, Casa.pantalla(null))
    }

    @Test fun casaLosKilos() {
        assertEquals(20.0, Casa.kilos("20"))
        assertEquals(12.5, Casa.kilos(" 12,5 "))
        assertEquals(12.3, Casa.kilos("12.34"))
        assertEquals(1.0, Casa.kilos("1"))
        assertEquals(400.0, Casa.kilos("400"))
        for (x in listOf("", "0", "0,9", "401", "abc", "-5", "NaN", "0.04")) assertNull(Casa.kilos(x), x)
        for (x in listOf("", "2", "20", "20,", "20,5", "400", "12.5")) assertTrue(Casa.kilosEscribibles(x), x)
        for (x in listOf("401", "4000", ",5", "1,2,3", "12a", "-3", "1e2", "123456")) assertFalse(Casa.kilosEscribibles(x), x)
    }

    @Test fun casaLoQueSeEnvia() {
        val t = casa().tipos
        assertFalse(Casa.puedeEnviar(emptyList(), false, t))
        assertTrue(Casa.puedeEnviar(emptyList(), true, t))
        assertTrue(Casa.puedeEnviar(listOf("mancuernas"), false, t))
        // Un tipo que no está en la lista del servidor no cuenta ni viaja.
        assertFalse(Casa.puedeEnviar(listOf("maquina_inventada"), false, t))
        val kilos = mapOf("mancuernas" to "22,5", "banco_plano" to "50", "bandas_elasticas" to "abc")
        val e = Casa.equiposParaEnviar(t, listOf("banco_plano", "maquina_inventada", "mancuernas"), kilos, sinEquipo = false)
        // En el orden del servidor; los kilos solo donde `kg` es true.
        assertEquals(listOf(EquipoCasa("mancuernas", 22.5), EquipoCasa("banco_plano", null)), e)
        assertEquals(j("""[{"tipo":"mancuernas","kg":22.5},{"tipo":"banco_plano"}]"""), Casa.aValor(e))
        assertTrue(Casa.equiposParaEnviar(t, listOf("mancuernas"), kilos, sinEquipo = true).isEmpty())
        assertEquals(listOf(EquipoCasa("mancuernas", null)), Casa.equiposParaEnviar(t, listOf("mancuernas"), mapOf("mancuernas" to "0"), false))
        assertEquals(300, Casa.notaRecortada("x".repeat(400)).length)
    }

    @Test fun casaLosRenglonesDeLaVigente() {
        val t = casa().tipos
        assertEquals("Mancuernas, hasta 20 kg", Casa.renglonVigente(EquipoCasa("mancuernas", 20.0), t))
        assertEquals("Banco plano", Casa.renglonVigente(EquipoCasa("banco_plano"), t))
        assertEquals("Barra z", Casa.renglonVigente(EquipoCasa("barra_z"), t))
    }
}
