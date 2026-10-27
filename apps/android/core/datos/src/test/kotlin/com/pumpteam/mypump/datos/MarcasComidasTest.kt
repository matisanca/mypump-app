package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AjustePorciones
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.MarcaComida
import com.pumpteam.mypump.reglas.MarcaComida.Estado.COMIDO
import com.pumpteam.mypump.reglas.MarcaComida.Estado.SALTADO
import java.io.IOException
import java.util.Collections
import kotlin.math.abs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * «Comí» / «Salté» y lo consumido del día en el modelo (D25): salen por la cola con el payload de la web, se leen del
 * servidor (las de la web también), sin red quedan en el teléfono y en la cola, lo que se toca mientras viaja la lectura
 * no se pierde, y «Hoy no la como» saca la marca. Gemelo de MarcasComidasTests.swift.
 */
class MarcasComidasTest {
    private val raiz = carpetaTemporal("marcas-comidas")

    /** El servidor de las marcas: una fila por (fecha, comida), como `mypump_comidas_marcadas`. */
    private class Servidor {
        val filas: MutableMap<String, ValorJson> = Collections.synchronizedMap(linkedMapOf())
        val escrituras: MutableList<Pair<String, ValorJson>> = Collections.synchronizedList(mutableListOf())
        @Volatile var sinRed = false

        /** La lectura contesta con lo que había al empezar, pero tarde. */
        @Volatile var lecturaLenta = false
        @Volatile var leyendo = false

        fun foto(): String = synchronized(filas) { ValorJson.Lista(filas.values.toList()).aJson().toString() }

        val transporte = TransporteProgramado { fn, c ->
            if (sinRed) throw IOException("sin conexión a internet")
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to DIETA
                "mypump_get_comidas_marcadas" -> {
                    val foto = foto()
                    if (lecturaLenta) {
                        leyendo = true
                        repeat(300) { if (escrituras.isEmpty()) delay(10) }
                        delay(50)
                        leyendo = false
                    }
                    200 to foto
                }
                "mypump_marcar_comida" -> {
                    escrituras += fn to c
                    val id = c["p_comida_id"]!!.comoTexto!!
                    filas[id] = ValorJson.objeto(
                        "comida_id" to ValorJson.Texto(id), "fecha" to (c["p_fecha"] ?: ValorJson.Nulo),
                        "opcion_elegida" to (c["p_opcion"] ?: ValorJson.Nulo), "estado" to (c["p_estado"] ?: ValorJson.Nulo),
                        "foods_excluidos" to (c["p_foods_excluidos"] ?: ValorJson.Nulo),
                    )
                    200 to "[${filas[id]!!.aJson()}]"
                }
                "mypump_desmarcar_comida" -> {
                    escrituras += fn to c
                    filas.remove(c["p_comida_id"]!!.comoTexto!!)
                    200 to "true"
                }
                else -> 200 to "[]"
            }
        }
    }

    private fun modelo(s: Servidor, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = s.transporte), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)

    private fun fila(id: String, opcion: String, estado: String, excl: List<Int>? = null) = ValorJson.objeto(
        "comida_id" to ValorJson.Texto(id), "opcion_elegida" to ValorJson.Texto(opcion), "estado" to ValorJson.Texto(estado),
        "foods_excluidos" to (excl?.let { l -> ValorJson.Lista(l.map { ValorJson.Numero(it.toDouble()) }) } ?: ValorJson.Nulo),
    )

    @Test
    fun comiConLaOpcionQueSeVeYTocarDeNuevoDesmarca() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        assertTrue(m.marcasDeHoy.isEmpty())
        assertEquals(0.0, m.consumo(emptyMap()).kcal)
        m.marcar("desayuno", COMIDO, 1)
        // Al toque, antes de que salga.
        assertEquals(MarcaComida("B", COMIDO), m.marcasDeHoy["desayuno"])
        val c = m.consumo(emptyMap())
        assertEquals(120.0, c.kcal)
        assertEquals(10.0, c.prot)
        assertEquals(1, c.hechas)
        assertEquals(2, c.comidas)
        m.outbox?.drenar()
        val (fn, cuerpo) = s.escrituras.last()
        assertEquals("mypump_marcar_comida", fn)
        assertEquals(FechaLocal.hoy(), cuerpo["p_fecha"]?.comoTexto)
        assertEquals("desayuno", cuerpo["p_comida_id"]?.comoTexto)
        assertEquals("B", cuerpo["p_opcion"]?.comoTexto)
        assertEquals("comido", cuerpo["p_estado"]?.comoTexto)
        assertEquals(ValorJson.Nulo, cuerpo["p_foods_excluidos"])
        // Mirando la A, lo comido sigue siendo la B.
        assertEquals(120.0, m.consumo(mapOf("desayuno" to 0)).kcal)
        // «Salté» pisa a «Comí»; desmarcar la borra del servidor.
        m.marcar("desayuno", SALTADO, 0)
        assertEquals(0.0, m.consumo(emptyMap()).kcal)
        assertEquals(1, m.consumo(emptyMap()).salteadas)
        m.marcar("desayuno", null, 0)
        m.outbox?.drenar()
        assertEquals("mypump_desmarcar_comida", s.escrituras.last().first)
        assertNull(s.filas["desayuno"])
        assertTrue(m.marcasDeHoy.isEmpty())
        assertEquals(0, m.outbox?.pendientes())
        // Una comida que no está en el plan no se marca.
        m.marcar("cena", COMIDO, 0)
        assertTrue(m.marcasDeHoy.isEmpty())
    }

    @Test
    fun destildarUnAlimentoLoDescuentaYVuelveATildar() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.marcar("desayuno", COMIDO, 0)
        m.alternarAlimento("desayuno", 1)
        assertEquals(listOf(1), m.marcasDeHoy["desayuno"]?.excluidos)
        assertEquals(380.0, m.consumo(emptyMap()).kcal)
        m.outbox?.drenar()
        assertEquals(ValorJson.Lista(listOf(ValorJson.Numero(1.0))), s.escrituras.last().second["p_foods_excluidos"])
        // Una sola op por comida y día: la última gana.
        m.alternarAlimento("desayuno", 0)
        m.alternarAlimento("desayuno", 1)
        assertEquals(listOf(0), m.marcasDeHoy["desayuno"]?.excluidos)
        m.outbox?.drenar()
        assertEquals(ValorJson.Lista(listOf(ValorJson.Numero(0.0))), s.filas["desayuno"]?.get("foods_excluidos"))
        m.alternarAlimento("desayuno", 0)
        m.outbox?.drenar()
        assertEquals(ValorJson.Nulo, s.escrituras.last().second["p_foods_excluidos"])
        assertEquals(614.0, m.consumo(emptyMap()).kcal)
        // Sin «Comí», destildar no hace nada.
        m.alternarAlimento("almuerzo", 0)
        assertNull(m.marcasDeHoy["almuerzo"])
    }

    @Test
    fun lasDeLaWebSeVenAlCargarYAlVolver() = enUnHilo { alcance ->
        val s = Servidor()
        s.filas["almuerzo"] = fila("almuerzo", "A", "comido", listOf(1))
        val m = modelo(s, alcance)
        m.cargar()
        assertEquals(MarcaComida("A", COMIDO, listOf(1)), m.marcasDeHoy["almuerzo"])
        assertEquals(330.0, m.consumo(emptyMap()).kcal)
        // La web la desmarca y marca el desayuno: al volver a la app se ve.
        s.filas.remove("almuerzo")
        s.filas["desayuno"] = fila("desayuno", "A", "saltado")
        m.alVolverAPrimerPlano()
        assertEquals(mapOf("desayuno" to MarcaComida("A", SALTADO)), m.marcasDeHoy)
    }

    @Test
    fun sinRedQuedaEnElTelefonoYEnLaColaYGanaAlVolver() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.sinRed = true
        m.marcar("almuerzo", COMIDO, 0)
        m.alternarAlimento("almuerzo", 1)
        m.outbox?.drenar()
        assertEquals(1, m.outbox?.pendientes())
        assertEquals(330.0, m.consumo(emptyMap()).kcal)
        m.outbox?.cerrar()
        // Otro arranque sin red: la copia offline y las marcas del teléfono.
        val otro = modelo(s, alcance)
        otro.cargar()
        assertEquals(MarcaComida("A", COMIDO, listOf(1)), otro.marcasDeHoy["almuerzo"])
        // Vuelve la red: el servidor todavía no la tiene, pero lo de la cola gana sobre lo que lee; después sale.
        s.sinRed = false
        otro.hidratarMarcas()
        assertEquals(listOf(1), otro.marcasDeHoy["almuerzo"]?.excluidos)
        otro.outbox?.drenar()
        assertEquals(ValorJson.Lista(listOf(ValorJson.Numero(1.0))), s.filas["almuerzo"]?.get("foods_excluidos"))
    }

    /**
     * La lectura sale, el cliente marca, la escritura llega antes que la respuesta: la respuesta (sin la marca) no la borra
     * (en la web, «la comida se desmarcaba sola al terminar la carga»).
     */
    @Test
    fun loQueSeTocaMientrasViajaLaLecturaNoSePierde() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.lecturaLenta = true
        val lectura = async { m.hidratarMarcas() }
        repeat(200) { if (!s.leyendo) delay(5) }
        m.marcar("desayuno", COMIDO, 0)
        m.outbox?.drenar()
        lectura.await()
        assertEquals(COMIDO, m.marcasDeHoy["desayuno"]?.estado)
        s.lecturaLenta = false
        m.hidratarMarcas()
        assertEquals(COMIDO, m.marcasDeHoy["desayuno"]?.estado)
    }

    @Test
    fun hoyNoLaComoSacaLaMarcaYNoCuenta() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.marcar("desayuno", COMIDO, 0)
        m.marcar("almuerzo", COMIDO, 0)
        m.outbox?.drenar()
        m.ajustar("desayuno", AjusteComida(compensar = true, omitida = true), emptyMap())
        assertNull(m.marcasDeHoy["desayuno"])
        m.outbox?.drenar()
        assertNull(s.filas["desayuno"])
        val c = m.consumo(emptyMap())
        // El almuerzo se come con lo que le pasa el desayuno (porciones de hoy): más que su plan.
        assertEquals(1, c.comidas)
        assertEquals(1, c.hechas)
        assertTrue(c.kcal > 525, "${c.kcal}")
        val dia = m.diaAjustado(emptyMap())
        assertTrue(abs(c.kcal - AjustePorciones.kcal(dia.getValue("almuerzo").alimentos)) < 1e-9)
    }

    @Test
    fun alCambiarElDiaNoValenYLaDemoNoEscribe() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.marcar("desayuno", COMIDO, 0)
        m.outbox?.drenar()
        // Lo del teléfono de otro día no vale.
        assertTrue(Disco(raiz, TOKEN).guardar(MarcasComidas.ARCHIVO, MarcasComidas.guardadas("2000-01-01", mapOf("almuerzo" to MarcaComida("A", COMIDO)))))
        val otroDia = modelo(Servidor().also { it.sinRed = true }, alcance)
        otroDia.cargar()
        assertTrue(otroDia.marcasDeHoy.isEmpty())
        // Demo: en memoria, nada al servidor.
        val antes = s.escrituras.size
        val demo = modelo(s, alcance)
        demo.entrarEnDemo("{}", DIETA_DEMO)
        assertTrue(demo.marcasDeHoy.isEmpty())
        demo.marcar("almuerzo", COMIDO, 0)
        demo.alternarAlimento("almuerzo", 0)
        assertEquals(listOf(0), demo.marcasDeHoy["almuerzo"]?.excluidos)
        assertEquals(195.0, demo.consumo(emptyMap()).kcal)
        // Al salir, lo de la cuenta (el desayuno del servidor), sin lo de la demo.
        demo.salirDeDemo()
        assertNull(demo.marcasDeHoy["almuerzo"])
        assertEquals(COMIDO, demo.marcasDeHoy["desayuno"]?.estado)
        assertEquals(antes, s.escrituras.size)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
        const val ESTRUCTURA = """{"macros_target":{"kcal":2000,"prot":150,"carb":200,"fat":60},"comidas":[""" +
            """{"id":"desayuno","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":67,"fat":7},{"name":"Huevos","qty":3,"unit":"u","kcal":234,"prot":18,"carb":0,"fat":18}]},{"name":"B","foods":[{"name":"Yogur","qty":200,"unit":"g","kcal":120,"prot":10,"carb":14,"fat":3}]}]},""" +
            """{"id":"almuerzo","name":"Almuerzo","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7},{"name":"Arroz","qty":150,"unit":"g","kcal":195,"prot":4,"carb":42,"fat":0.5}]}]}""" +
            "]}"
        const val DIETA = """[{"id":"55555555-5555-4555-8555-555555555555","version":1,"estructura":$ESTRUCTURA}]"""
        const val DIETA_DEMO = ESTRUCTURA
    }
}
