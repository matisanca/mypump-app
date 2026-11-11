package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CheckGuiado
import com.pumpteam.mypump.reglas.CheckGuiado.Borrador
import com.pumpteam.mypump.reglas.CheckGuiado.Catalogo
import com.pumpteam.mypump.reglas.CheckGuiado.Paso
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

private const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
private const val HOY = "2026-11-11"
private const val LUNES = "2026-11-09"
private const val SIN_FUNCION = """{"code":"PGRST202","message":"Could not find the function"}"""

/**
 * El check guiado en el modelo (CheckGuiadoModeloTests.swift): escribe exactamente lo mismo que el check de siempre (más lo
 * marcado), apagado no llama a nada nuevo, y el borrador se guarda y se retoma.
 */
class CheckGuiadoModeloTest {
    private class Servidor {
        @Volatile var conRed = true
        @Volatile var guiado = """{"activo":true,"en_ciclo":false,"semana":"$LUNES","catalogo":null,"senales":null}"""
        @Volatile var estadoGuiado = 200
        @Volatile var check = "[]"
        val cuerpos = ConcurrentHashMap<String, ValorJson>()
    }

    private class Armado(val m: ModeloRevision, val cola: Outbox, val t: TransporteProgramado)

    private val llenas = mapOf("energia" to 4, "descanso" to 3, "hambre" to 2, "adherencia" to 5)

    private fun armar(s: Servidor, alcance: CoroutineScope, prendido: Boolean = true, disco: Disco? = null, mandar: Boolean = false, hoy: String = HOY): Armado {
        val t = TransporteProgramado { fn, cuerpo ->
            if (!s.conRed) throw IOException("sin conexión a internet")
            s.cuerpos[fn] = cuerpo
            when (fn) {
                "mypump_check_guiado_get" -> s.estadoGuiado to s.guiado
                "mypump_get_checkin_semana" -> 200 to s.check
                "mypump_check_guiado_guardar" -> 200 to "true"
                "mypump_guardar_checkin" -> 200 to """[{"semana_lunes":"$LUNES","energia":4}]"""
                else -> 200 to "[]"
            }
        }
        val cliente = ClienteRpc(transporte = t)
        val esc = Escrituras(cliente, TOKEN)
        val cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { op ->
            if (mandar) esc.ejecutar(op) else ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin red")))
        }
        val m = ModeloRevision(cliente, TOKEN, cola, alcance, disco)
        m.recordarPalancaGuiado(prendido)
        m.diaDeHoy = { hoy }
        return Armado(m, cola, t)
    }

    private fun discoNuevo() = Disco(carpetaTemporal("cg"))

    private fun vector(): ValorJson = ValorJson.parsear(Compartido.texto("vectores/check_guiado.json"))

    @Test
    fun apagadoNoLlamaANadaNuevo() = enUnHilo { alcance ->
        val a = armar(Servidor(), alcance, prendido = false)
        a.m.cargarRevision()
        assertFalse("mypump_check_guiado_get" in a.t.llamadas)
        assertNull(a.m.guiado.value)
        assertEquals(Catalogo.GENERAL, a.m.catalogoGuiado)
        assertFalse(a.m.guiadoPrendido.value)
    }

    @Test
    fun prendidoLeeSiEstaEnCicloYLoYaMarcado() = enUnHilo { alcance ->
        val s = Servidor()
        s.guiado = """{"activo":true,"en_ciclo":true,"semana":"$LUNES","catalogo":"ciclo","senales":["acne"]}"""
        s.check = """[{"semana_lunes":"$LUNES","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"bien"}]"""
        val a = armar(s, alcance)
        a.m.cargarRevision()
        assertEquals(ValorJson.Texto(HOY), s.cuerpos["mypump_check_guiado_get"]?.get("p_fecha"))
        assertEquals(Catalogo.CICLO, a.m.catalogoGuiado)
        assertEquals(Borrador(LUNES, Paso.RESUMEN, valores = llenas, catalogo = Catalogo.CICLO, senales = listOf("acne"), nota = "bien"), a.m.abrirGuiado())
    }

    @Test
    fun sinLaFuncionOConLaPalancaApagadaEnElServidorEsLaListaGeneral() = enUnHilo { alcance ->
        val s = Servidor()
        s.estadoGuiado = 404
        s.guiado = SIN_FUNCION
        val a = armar(s, alcance)
        a.m.cargarRevision()
        assertNull(a.m.guiado.value)
        assertEquals(Catalogo.GENERAL, a.m.catalogoGuiado)
        s.estadoGuiado = 200
        s.guiado = """{"activo":false}"""
        a.m.cargarRevision()
        assertNull(a.m.guiado.value)
    }

    @Test
    fun sinRedQuedaLoUltimoQueSeSupo() = enUnHilo { alcance ->
        val s = Servidor()
        val disco = discoNuevo()
        s.guiado = """{"activo":true,"en_ciclo":true,"semana":"$LUNES","catalogo":null,"senales":null}"""
        armar(s, alcance, disco = disco).m.cargarRevision()
        s.conRed = false
        val b = ModeloRevision(ClienteRpc(transporte = SinRed), TOKEN, null, alcance, disco)
        assertEquals(Catalogo.CICLO, b.catalogoGuiado, "al arrancar sin señal, lo del disco")
        assertTrue(b.guiadoPrendido.value, "y la palanca recordada: sin red la Revisión no vuelve a la pantalla anterior")
        b.cargarRevision()
        assertEquals(Catalogo.CICLO, b.catalogoGuiado)
    }

    /** Si la propuesta se revierte, lo guardado no deja a nadie en la lista de ciclo. */
    @Test
    fun alDesaparecerLaFuncionSeOlvidaLoGuardado() = enUnHilo { alcance ->
        val s = Servidor()
        val disco = discoNuevo()
        s.guiado = """{"activo":true,"en_ciclo":true,"semana":"$LUNES","catalogo":null,"senales":null}"""
        armar(s, alcance, disco = disco).m.cargarRevision()
        s.estadoGuiado = 404
        s.guiado = SIN_FUNCION
        armar(s, alcance, disco = disco).m.cargarRevision()
        assertNull(armar(s, alcance, disco = disco).m.guiado.value)
    }

    /** Lo central: lo que sale por la cola es lo del vector compartido, y `checkin` y `peso` son idénticos a los de siempre. */
    @Test
    fun enviarEscribeLoMismoQueElCheckDeSiempreMasLoMarcado() = enUnHilo { alcance ->
        val p = vector()["payload"]!!
        val b = Borrador.desde(p["borrador"])!!
        assertEquals(HOY, p["fecha"]?.comoTexto)

        val a = armar(Servidor(), alcance)
        assertNull(a.m.enviarGuiado(b))
        val ops = a.cola.operaciones()
        val esperadas = (p["ops"] as ValorJson.Lista).elementos
        assertEquals(esperadas.map { it["kind"]?.comoTexto }, ops.map { it.kind })
        for ((op, e) in ops.zip(esperadas)) {
            assertEquals(e["dedupeKey"]?.comoTexto, op.dedupeKey)
            assertEquals(e["payload"], op.payload, op.kind)
            // Y tal como queda escrito en la cola (lo que se manda), campo por campo.
            assertEquals(e["payload"], ValorJson.parsear(op.payload.serializar()), op.kind)
        }

        // El check de siempre, con los mismos datos, encola un `checkin` y un `peso` iguales.
        val viejo = armar(Servidor(), alcance, prendido = false)
        viejo.m.enviarCheckin(Checkin(b.valores, b.nota))
        viejo.m.guardarPeso(b.peso)
        val viejas = viejo.cola.operaciones()
        assertEquals(listOf("checkin", "peso"), viejas.map { it.kind })
        assertEquals(viejas.map { it.payload }, ops.take(2).map { it.payload })
        assertEquals(viejas.map { it.payload.serializar() }, ops.take(2).map { it.payload.serializar() }, "byte a byte")
        assertEquals(viejas.map { it.dedupeKey }, ops.take(2).map { it.dedupeKey })

        assertTrue(a.m.checkinEnviado)
        assertNull(a.m.borradorGuiado.value)
        assertEquals(listOf("acne", "sueno"), a.m.guiado.value?.senales)
    }

    @Test
    fun laColaLlamaALaFuncionConLosParametrosDelContrato() = enUnHilo { alcance ->
        val s = Servidor()
        val a = armar(s, alcance, mandar = true)
        a.m.enviarGuiado(Borrador(LUNES, valores = llenas, catalogo = Catalogo.GENERAL, senales = listOf("ninguno")))
        repeat(3) { a.cola.drenar() }
        assertTrue("mypump_guardar_checkin" in a.t.llamadas)
        val c = s.cuerpos["mypump_check_guiado_guardar"]
        assertEquals(ValorJson.Texto(HOY), c?.get("p_fecha"))
        assertEquals(ValorJson.parsear("""{"catalogo":"general","senales":["ninguno"]}"""), c?.get("p_respuestas"))
        assertEquals(ValorJson.Texto(TOKEN), c?.get("p_token"))
        assertEquals(setOf("p_token", "p_fecha", "p_respuestas"), (c as ValorJson.Objeto).campos.keys)
        assertTrue(a.cola.operaciones().isEmpty())
        // Lo del vector: la función y sus parámetros.
        val rpc = vector()["payload"]!!["rpc"]!!["check_guiado"]!!
        assertEquals("mypump_check_guiado_guardar", rpc["funcion"]?.comoTexto)
        assertEquals((rpc["parametros"] as ValorJson.Objeto).campos.keys + "p_token", c.campos.keys)
        // El check de siempre no lleva ni un parámetro más.
        assertEquals(
            setOf("p_token", "p_fecha", "p_energia", "p_descanso", "p_hambre", "p_adherencia", "p_nota"),
            (s.cuerpos["mypump_guardar_checkin"] as ValorJson.Objeto).campos.keys,
        )
    }

    @Test
    fun sinLaFuncionEnLaBaseLaOpNoQuedaTrabada() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ -> if (fn == "mypump_check_guiado_guardar") 404 to SIN_FUNCION else 200 to "[]" }
        val esc = Escrituras(ClienteRpc(transporte = t), TOKEN)
        val cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        cola.encolar(
            "check_guiado",
            ValorJson.parsear("""{"fecha":"$HOY","respuestas":{"catalogo":"general","senales":["dolor"]}}"""),
            "check_guiado_$HOY",
        )
        cola.drenar()
        assertTrue(cola.operaciones().isEmpty())
        assertTrue(cola.fallidos().isEmpty())
    }

    /** FALSE (la palanca apagada en el servidor) también es «hecho»: no se reintenta ni va a fallidos. */
    @Test
    fun conFalseDelServidorLaOpTampocoQuedaTrabada() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ -> if (fn == "mypump_check_guiado_guardar") 200 to "false" else 200 to "[]" }
        val esc = Escrituras(ClienteRpc(transporte = t), TOKEN)
        val cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { esc.ejecutar(it) }
        cola.encolar("check_guiado", ValorJson.parsear("""{"fecha":"$HOY","respuestas":{"catalogo":"general","senales":["dolor"]}}"""), "check_guiado_$HOY")
        cola.drenar()
        assertTrue(cola.operaciones().isEmpty())
        assertTrue(cola.fallidos().isEmpty())
    }

    @Test
    fun sinLoObligatorioNoSaleNada() = enUnHilo { alcance ->
        val a = armar(Servidor(), alcance)
        assertEquals("Faltan: Descanso, Hambre, Adherencia", a.m.enviarGuiado(Borrador(LUNES, valores = mapOf("energia" to 4))))
        assertEquals("Falta: ¿Algo de esto esta semana?", a.m.enviarGuiado(Borrador(LUNES, valores = llenas)))
        assertEquals(CheckGuiado.AVISO_RANGO_PESO, a.m.enviarGuiado(Borrador(LUNES, peso = "12", valores = llenas, senales = listOf("ninguno"))))
        assertTrue(a.cola.operaciones().isEmpty())
        assertFalse(a.m.checkinEnviado)
    }

    @Test
    fun sinPesoNoSeMandaPeso() = enUnHilo { alcance ->
        val a = armar(Servidor(), alcance)
        assertNull(a.m.enviarGuiado(Borrador(LUNES, valores = llenas, senales = listOf("dolor"))))
        assertEquals(listOf("checkin", "check_guiado"), a.cola.operaciones().map { it.kind })
    }

    @Test
    fun elPesoDelPasoSeGuardaEnElMomentoYNoSeRepite() = enUnHilo { alcance ->
        val a = armar(Servidor(), alcance)
        assertFalse(a.m.guardarPesoGuiado("abc"))
        assertNull(a.m.pesoDeHoy)
        assertTrue(a.m.guardarPesoGuiado("78,4"))
        assertEquals(78.4, a.m.pesoDeHoy)
        assertEquals(listOf("peso"), a.cola.operaciones().map { it.kind })
        val primera = a.cola.operaciones().first().id
        assertTrue(a.m.guardarPesoGuiado("78.4"))
        assertEquals(primera, a.cola.operaciones().first().id, "el mismo peso no se encola de nuevo")
        assertNull(a.m.enviarGuiado(Borrador(LUNES, peso = "78,4", valores = llenas, senales = listOf("ninguno"))))
        assertEquals(listOf("peso", "checkin", "check_guiado"), a.cola.operaciones().map { it.kind })
        assertEquals(primera, a.cola.operaciones().first().id)
    }

    @Test
    fun elBorradorSeGuardaSeRetomaYElDeOtraSemanaSeDescarta() = enUnHilo { alcance ->
        val s = Servidor()
        val disco = discoNuevo()
        val a = armar(s, alcance, disco = disco)
        a.m.cargarRevision()
        var b = a.m.abrirGuiado()
        assertEquals(Borrador(LUNES), b)
        b = b.copy(peso = "78,4", valores = llenas, paso = Paso.SENALES)
        a.m.guardarBorrador(b)

        // Se cierra la app: al volver está donde quedó (también antes de que conteste el servidor).
        val c = armar(s, alcance, disco = disco)
        assertEquals(b, c.m.borradorGuiado.value)
        c.m.cargarRevision()
        assertEquals(b, c.m.borradorGuiado.value)
        assertEquals(b, c.m.abrirGuiado())
        assertEquals(CheckGuiado.Estado.A_MEDIAS, CheckGuiado.estado(c.m.checkinEnviado, c.m.borradorGuiado.value, c.m.semana, faltanFotos = true))

        // Semana nueva: el borrador de la anterior no es de esta.
        val d = armar(s, alcance, disco = disco, hoy = "2026-11-16")
        d.m.cargarRevision()
        assertNull(d.m.borradorGuiado.value)
        assertEquals(Borrador("2026-11-16"), d.m.abrirGuiado())
        assertNull(armar(s, alcance, disco = disco).m.borradorGuiado.value, "también se borró del disco")
    }

    /** Dos cuentas en el mismo teléfono: el borrador de una no aparece en la otra. */
    @Test
    fun elBorradorEsDeLaCuenta() = enUnHilo { alcance ->
        val raiz = carpetaTemporal("cg-cuentas")
        val a = armar(Servidor(), alcance, disco = Disco(raiz, TOKEN))
        a.m.cargarRevision()
        a.m.guardarBorrador(a.m.abrirGuiado().copy(nota = "de la primera"))
        val otra = ModeloRevision(ClienteRpc(transporte = SinRed), "BBBBBBBBBBBBBBBBBBBB", null, alcance, Disco(raiz, "BBBBBBBBBBBBBBBBBBBB"))
        assertNull(otra.borradorGuiado.value)
        assertFalse(otra.guiadoPrendido.value)
    }

    @Test
    fun loMarcadoQueNoSalioGanaSobreElServidor() = enUnHilo { alcance ->
        val a = armar(Servidor(), alcance)
        a.m.enviarGuiado(Borrador(LUNES, valores = llenas, catalogo = Catalogo.GENERAL, senales = listOf("dolor")))
        a.m.cargarRevision()   // el servidor todavía no lo tiene
        assertEquals(listOf("dolor"), a.m.guiado.value?.senales)
        assertTrue(a.m.checkinEnviado)
        assertEquals(listOf("dolor"), a.m.abrirGuiado().senales)
        assertEquals(Paso.RESUMEN, a.m.abrirGuiado().paso)
    }

    @Test
    fun laPalancaSeLeeYSinLaClaveEstaApagada() {
        assertFalse(PalancaRemota.desde(ValorJson.parsear("{}")).checkGuiado)
        assertTrue(PalancaRemota.desde(ValorJson.parsear("""{"check_guiado":true}""")).checkGuiado)
        assertFalse(PalancaRemota.desde(ValorJson.parsear("""{"check_guiado":"true"}""")).checkGuiado)
        assertFalse(PalancaRemota.deFabrica.checkGuiado)
    }

    /** La demo no tiene check guiado: ni palanca ni llamadas. */
    @Test
    fun laDemoEsLaDeSiempre() = enUnHilo { alcance ->
        val t = TransporteProgramado { _, _ -> 200 to "[]" }
        val m = ModeloRevision.demo(ClienteRpc(transporte = t), alcance)
        m.recordarPalancaGuiado(true)
        m.cargarRevision()
        assertFalse(m.guiadoPrendido.value)
        assertTrue(t.llamadas.isEmpty())
    }
}
