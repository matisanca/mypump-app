package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.FilaSalud
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.SaludVista
import com.pumpteam.mypump.reglas.TextosSalud
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

/** Una base que contesta por función (y la ruta de los relojes) y anota lo que se llamó. */
class BasePorFuncion : Transporte {
    /** función → (status, json). Status 0 es "sin red". */
    val respuestas = HashMap<String, Pair<Int, ValorJson>>()

    /** Respuestas que cambian entre llamadas (el sondeo de `get_conexiones`). */
    val secuencia = HashMap<String, ArrayDeque<ValorJson>>()
    private val _llamadas = ArrayList<Pair<String, ValorJson?>>()

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val ruta = pedido.ruta
        val fn = if (ruta.startsWith("/rest/v1/rpc/")) ruta.substringAfterLast('/') else ruta
        val cuerpo = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) }
        val (status, json) = synchronized(this) {
            _llamadas += fn to cuerpo
            secuencia[fn]?.takeIf { it.isNotEmpty() }?.let { s ->
                val r = s.removeFirst()
                if (s.isEmpty()) secuencia.remove(fn)
                200 to r
            } ?: respuestas[fn] ?: (404 to ValorJson.objeto("code" to ValorJson.Texto("PGRST202"), "message" to ValorJson.Texto("no existe")))
        }
        if (status == 0) throw IOException("sin conexión")
        return Respuesta(status, json.serializar().toByteArray())
    }

    @Synchronized fun cuantas(fn: String): Int = _llamadas.count { it.first == fn }

    @Synchronized fun ultima(fn: String): ValorJson? = _llamadas.lastOrNull { it.first == fn }?.second
}

private fun fila(fecha: String, tipo: String, valor: Double, fuente: String = "apple_health"): ValorJson = ValorJson.objeto(
    "fecha" to ValorJson.Texto(fecha), "tipo" to ValorJson.Texto(tipo), "valor" to ValorJson.Numero(valor), "fuente" to ValorJson.Texto(fuente),
    "detalle" to ValorJson.Nulo,
)

/** Gemelo de ModeloSaludTests.swift: lecturas, Mi reloj y sin salud del sistema. */
class ModeloSaludTest {
    private val hoy = FechaLocal.hoy()

    private fun modelo(base: BasePorFuncion, alcance: CoroutineScope, fuente: FuenteSalud? = null) =
        ModeloSalud(ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", fuente, PreferenciasEnMemoria(), alcance)

    @Test
    fun cargaSaludRecuperacionYPreferencia() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["mypump_get_salud"] = 200 to ValorJson.Lista(listOf(fila(hoy, "pasos", 8000.0), fila(hoy, "sueno_min", 420.0, "oura")))
        base.respuestas["mypump_get_recuperacion"] = 200 to ValorJson.Lista(listOf(ValorJson.objeto(
            "fecha" to ValorJson.Texto(hoy), "score" to ValorJson.Numero(74.0), "estado" to ValorJson.Texto("ok"),
            "banda" to ValorJson.Texto("media"), "componentes" to ValorJson.objeto(),
        )))
        base.respuestas["mypump_get_mostrar_recuperacion"] = 200 to ValorJson.Booleano(false)
        val m = modelo(base, alcance)
        m.cargar()
        assertTrue(m.salud.value.size == 2 && m.recuperacion.value.first().score == 74)
        assertFalse(m.mostrarRecuperacion.value)
        assertEquals(SaludVista.CardRecuperacion.Oculto, m.cardRecuperacion)
        assertTrue(m.resumenSalud?.pasosHoy == 8000.0 && m.resumenSalud?.suenoAnoche == 420.0)
        // 60 días: de hoy − 59 a hoy.
        val p = base.ultima("mypump_get_salud")
        assertEquals(hoy, p?.get("p_hasta")?.comoTexto)
        assertEquals(DiaCalendario.texto(DiaCalendario.numero(hoy)!! - 59), p?.get("p_desde")?.comoTexto)
        assertEquals(ValorJson.Numero(14.0), base.ultima("mypump_get_recuperacion")?.get("p_dias"))
        // null o un error cuentan como "mostrar".
        base.respuestas["mypump_get_mostrar_recuperacion"] = 200 to ValorJson.Nulo
        m.cargar()
        assertTrue(m.mostrarRecuperacion.value)
        base.respuestas["mypump_get_mostrar_recuperacion"] = 500 to ValorJson.objeto("message" to ValorJson.Texto("caída"))
        m.cargar()
        assertTrue(m.mostrarRecuperacion.value)
        assertTrue(m.cargado.value)
    }

    @Test
    fun mostrarElScoreEsOptimista() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["mypump_set_mostrar_recuperacion"] = 200 to ValorJson.Booleano(true)
        val m = modelo(base, alcance)
        m.cambiarMostrarRecuperacion(false)
        assertFalse(m.mostrarRecuperacion.value)
        assertEquals(ValorJson.Booleano(false), base.ultima("mypump_set_mostrar_recuperacion")?.get("p_mostrar"))
    }

    @Test
    fun sinSaludDelSistemaNoHaceNada() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        val m = modelo(base, alcance)
        val c = m.conectar()
        assertTrue(!c.ok && c.motivo == "no_disponible")
        assertFalse(m.sincronizar().ok)
        assertTrue(!m.disponible.value && !m.conectado.value)
        assertEquals(0, base.cuantas("mypump_ingest_salud"))
        assertEquals(SaludVista.CardRecuperacion.SinConectar, m.cardRecuperacion)
    }

    @Test
    fun relojesVisiblesYTextos() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["/api/wearables/disponibles"] = 200 to ValorJson.objeto(
            "proveedores" to ValorJson.Lista(listOf(ValorJson.objeto("id" to ValorJson.Texto("oura"), "nombre" to ValorJson.Texto("Oura")))),
        )
        base.respuestas["mypump_get_conexiones"] = 200 to ValorJson.Lista(listOf(ValorJson.objeto(
            "proveedor" to ValorJson.Texto("whoop"), "estado" to ValorJson.Texto("error"), "ultimo_pull_en" to ValorJson.Nulo,
        )))
        val m = modelo(base, alcance)
        m.cargarRelojes()
        // Oura porque el servidor lo ofrece; WHOOP porque ya lo tenía (aunque hoy no se ofrezca).
        assertEquals(listOf("oura", "whoop"), m.relojesVisibles.map { it.id })
        assertTrue(m.relojesVisibles[1].enError && !m.relojesVisibles[1].conectado)
        assertEquals(
            "Si usás Oura o WHOOP, conectalo y tus datos de sueño y recuperación entran solos. Tu reloj no se conecta acá: va por Health Connect.",
            m.textoRelojes,
        )
        val ios = ModeloSalud(ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", null, PreferenciasEnMemoria(), alcance, textos = TextosSalud.IOS)
        ios.cargarRelojes()
        assertTrue(ios.textoRelojes.endsWith("Apple Watch no se conecta acá: va por Salud de Apple desde la app de iPhone."))
        // Lo que ofrece el servidor se pregunta una sola vez por modelo.
        m.cargarRelojes()
        assertEquals(2, base.cuantas("/api/wearables/disponibles"))
        assertEquals("https://app.mypumpteam.com/api/wearables/iniciar?t=tok-de-prueba-nativa-0001&proveedor=oura", m.urlConectar("oura"))
    }

    @Test
    fun sinRedNoSeOfreceNingunReloj() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["/api/wearables/disponibles"] = 0 to ValorJson.Nulo
        base.respuestas["mypump_get_conexiones"] = 200 to ValorJson.Lista(emptyList())
        val m = modelo(base, alcance)
        m.cargarRelojes()
        assertEquals(emptyList<String>(), m.relojesDisponibles.value)
        assertTrue(m.relojesVisibles.isEmpty())
    }

    @Test
    fun losProveedoresRarosSeDescartanSinTirarAbajoLaLista() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["/api/wearables/disponibles"] = 200 to ValorJson.objeto("proveedores" to ValorJson.Lista(listOf(
            ValorJson.objeto("id" to ValorJson.Texto("oura")), ValorJson.objeto("id" to ValorJson.Numero(3.0)), ValorJson.Texto("whoop"),
            ValorJson.objeto("id" to ValorJson.Texto("whoop"), "nombre" to ValorJson.Numero(1.0)),
        )))
        base.respuestas["mypump_get_conexiones"] = 200 to ValorJson.Lista(emptyList())
        val m = modelo(base, alcance)
        m.cargarRelojes()
        assertEquals(listOf("oura"), m.relojesDisponibles.value)
        // Una respuesta que no es un objeto: no se pudo preguntar.
        base.respuestas["/api/wearables/disponibles"] = 200 to ValorJson.Lista(emptyList())
        assertNull(ClienteRpc(transporte = base).relojesDisponibles())
    }

    @Test
    fun esperaLaConexionYRecarga() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.secuencia["mypump_get_conexiones"] = ArrayDeque(listOf(
            ValorJson.Lista(emptyList()),
            ValorJson.Lista(listOf(ValorJson.objeto("proveedor" to ValorJson.Texto("oura"), "estado" to ValorJson.Texto("pendiente")))),
            ValorJson.Lista(listOf(ValorJson.objeto(
                "proveedor" to ValorJson.Texto("oura"), "estado" to ValorJson.Texto("conectada"),
                "ultimo_pull_en" to ValorJson.Texto("2026-10-14T13:59:00.123456+00:00"),
            ))),
        ))
        base.respuestas["mypump_get_salud"] = 200 to ValorJson.Lista(emptyList())
        base.respuestas["mypump_get_recuperacion"] = 200 to ValorJson.Lista(emptyList())
        base.respuestas["mypump_get_mostrar_recuperacion"] = 200 to ValorJson.Booleano(true)
        base.respuestas["/api/wearables/disponibles"] = 200 to ValorJson.objeto("proveedores" to ValorJson.Lista(listOf(ValorJson.objeto("id" to ValorJson.Texto("oura")))))
        val m = modelo(base, alcance)
        m.cargarRelojes()   // se lleva la primera (vacía)
        val ok = m.esperarConexion("oura", cadaMs = 5, intentos = 40)
        assertTrue(ok)
        assertNull(m.esperandoReloj.value)
        assertEquals(true, m.relojesVisibles.first().conectado)
        assertTrue(m.relojesVisibles.first().ultimaSincronizacion?.endsWith("oct") == true, "${m.relojesVisibles.first().ultimaSincronizacion}")
        assertEquals(1, base.cuantas("mypump_get_salud"))   // al conectar se recargan salud y recuperación
    }

    @Test
    fun dejaDePreguntarALos40Intentos() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["mypump_get_conexiones"] = 200 to ValorJson.Lista(emptyList())
        val m = modelo(base, alcance)
        assertFalse(m.esperarConexion("whoop", cadaMs = 1, intentos = 40))
        assertEquals(40, base.cuantas("mypump_get_conexiones"))
    }

    /** Una espera nueva (u otro "Conectar") corta la anterior: la vieja contesta que no, sin colgarse. */
    @Test
    fun otraEsperaCortaLaAnterior() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["mypump_get_conexiones"] = 200 to ValorJson.Lista(emptyList())
        val m = modelo(base, alcance)
        val primera = alcance.async { m.esperarConexion("oura", cadaMs = 50, intentos = 40) }
        delay(10)
        m.cancelarEspera()
        assertFalse(primera.await())
        assertNull(m.esperandoReloj.value)
    }

    @Test
    fun quitarDesconectaYRelee() = enUnHilo { alcance ->
        val base = BasePorFuncion()
        base.respuestas["mypump_desconectar_wearable"] = 200 to ValorJson.Booleano(true)
        base.respuestas["mypump_get_conexiones"] = 200 to ValorJson.Lista(emptyList())
        base.respuestas["/api/wearables/disponibles"] = 200 to ValorJson.objeto("proveedores" to ValorJson.Lista(emptyList()))
        val m = modelo(base, alcance)
        m.quitar("oura")
        assertEquals("oura", base.ultima("mypump_desconectar_wearable")?.get("p_proveedor")?.comoTexto)
        assertEquals(1, base.cuantas("mypump_get_conexiones"))
    }

    @Test
    fun conectarConLaFuenteSincronizaYDejaElHistorialDeFondo() = enUnHilo { alcance ->
        // El caso "conectar-primera-vez" de los vectores, a través del modelo.
        val caso = cargarSalud("salud_conectar").first { it.nombre == "conectar-primera-vez" }
        val base = BaseGrabada(caso)
        val fuente = FuenteGrabada(caso)
        val almacen = PreferenciasEnMemoria(caso.estadoInicial)
        val m = ModeloSalud(ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", fuente, almacen, alcance, { caso.instante }, caso.zona)
        val r = m.conectar()
        assertTrue(r.ok && m.conectado.value)
        r.historial?.await()
        assertTrue(fuente.fallas.isEmpty(), "${fuente.fallas.take(3)}")
        assertEquals(0, fuente.pendientes)
        assertEquals("1", almacen.leer(ClaveSalud.HISTORIAL_HECHO))
        assertEquals("Ya estabas al día.", ModeloSalud.textoSincronizacion(ResultadoSync(true, null, 0, 0, null)))
        assertEquals("Listo: 3 datos nuevos.", ModeloSalud.textoSincronizacion(ResultadoSync(true, null, 3, 0, null)))
        assertEquals("No se pudieron guardar los datos (x). Probá de nuevo en un rato.", ModeloSalud.textoSincronizacion(ResultadoSync(true, null, 3, 0, "x")))
        // Lo que vio la card mientras traía el historial, y la última sincronización leída del ISO guardado.
        assertEquals(Instant.parse(almacen.leer(ClaveSalud.ULTIMA_SYNC)), m.ultimaSync.value)
    }
}

/**
 * Contra el backend real, con la cuenta `test-nativa-android` (y ninguna otra). Gemelo de SaludIntegracionTests de
 * ModeloSaludTests.swift. El token sale del registro privado y no se imprime.
 */
class SaludIntegracionTest {
    /**
     * Lo que arma la nativa entra a la base tal cual: el caso "sintetica-normal" de los vectores (fechas del 7 al
     * 14-oct-2026) se manda a la cuenta de prueba y se relee. El upsert es por (cliente, fecha, tipo, fuente): correrlo
     * de nuevo no duplica.
     */
    @Test
    fun ingestaYRelectura() = enUnHilo { alcance ->
        val token = IntegracionTest.tokenDePrueba()
        assumeTrue(token != null, "sin el registro privado de cuentas de prueba")
        val caso = cargarSalud("salud_sync").first { it.nombre == "sintetica-normal" }
        val fuente = FuenteGrabada(caso)
        val sinc = SincronizadorSalud(fuente, ClienteRpc(), token!!, PreferenciasEnMemoria(caso.estadoInicial), alcance, { caso.instante }, caso.zona)
        val r = sinc.sincronizar()
        assertTrue(fuente.fallas.isEmpty())
        assertNull(r.errorIngesta, "la base rechazó: ${r.errorIngesta}")
        val enviados = caso.rpc.filter { it["fn"]?.comoTexto == "mypump_ingest_salud" }.flatMap { (it["lote"] as? ValorJson.Lista)?.elementos ?: emptyList() }
        assertEquals(enviados.size, r.ingresados, "la base aceptó ${r.ingresados} de ${enviados.size}")

        val filas = ClienteRpc().filas(
            "mypump_get_salud", mapOf("p_token" to texto(token), "p_desde" to texto("2026-10-07"), "p_hasta" to texto("2026-10-14")), FilaSalud::desde,
        ).valorONull()
        assertTrue(filas != null, "no se pudo releer")
        val faltan = ArrayList<String>()
        for (e in enviados) {
            val fecha = e["fecha"]?.comoTexto ?: ""
            val tipo = e["tipo"]?.comoTexto ?: ""
            val f = filas!!.firstOrNull { it.fecha.startsWith(fecha) && it.tipo == tipo && it.fuente == "apple_health" }
            if (f == null) {
                faltan += "$fecha $tipo"
                continue
            }
            if (f.valor != e["valor"]?.comoNumero) faltan += "$fecha $tipo: ${f.valor} ≠ ${e["valor"]}"
            // Sin detalle la clave no viaja y la base guarda NULL (no un JSON null).
            if (e["detalle"] == null && f.detalle != null) faltan += "$fecha $tipo: detalle ${f.detalle}"
            e["detalle"]?.let { d -> if (f.detalle != d) faltan += "$fecha $tipo: detalle ${f.detalle} ≠ $d" }
        }
        assertTrue(faltan.isEmpty(), "${faltan.take(5)}")
    }

    @Test
    fun preferenciaRelojesYConexiones() = enUnHilo { alcance ->
        val token = IntegracionTest.tokenDePrueba()
        assumeTrue(token != null, "sin el registro privado de cuentas de prueba")
        val m = ModeloSalud(ClienteRpc(), token!!, null, PreferenciasEnMemoria(), alcance)
        m.cambiarMostrarRecuperacion(false)
        m.cargar()
        assertFalse(m.mostrarRecuperacion.value)
        m.cambiarMostrarRecuperacion(true)
        m.cargar()
        assertTrue(m.mostrarRecuperacion.value)
        assertTrue(m.cargado.value)
        m.cargarRelojes()
        assertTrue(m.relojesDisponibles.value != null)
        assertTrue(m.conexiones.value.all { it.proveedor in listOf("oura", "whoop") })
    }
}
