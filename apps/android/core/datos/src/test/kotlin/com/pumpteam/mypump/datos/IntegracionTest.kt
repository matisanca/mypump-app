package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.MensajeChat
import com.pumpteam.mypump.modelos.FoodSwap
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AlimentoPropioNuevo
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.PesoCorporal
import java.io.File
import java.util.Base64
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.MethodOrderer
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestMethodOrder
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable

/**
 * Contra el backend REAL con la cuenta de prueba `test-nativa-android` (invisible para el coach; escenario en-ritmo).
 * Las otras cuentas de prueba las usan otros agentes: esta es solo de Android. Corre solo donde está el registro privado
 * de cuentas (~/Developer/nativa-evidencia/privado/cuentas-prueba.json); en otra máquina se saltea.
 *
 * El token se lee acá adentro y NUNCA se imprime: ninguna aserción lo compara (un fallo mostraría el valor) y ningún
 * mensaje lo lleva. Escribe datos de prueba en esa cuenta (autorizado) y deja lo que toca como estaba.
 */
@TestMethodOrder(MethodOrderer.MethodName::class)
class IntegracionTest {
    private val raiz = carpetaTemporal("mypump-integracion")
    private lateinit var token: String

    @BeforeEach
    fun cuenta() {
        val t = tokenDePrueba()
        assumeTrue(t != null, "sin el registro privado de cuentas de prueba")
        token = t!!
    }

    private fun modelo(alcance: kotlinx.coroutines.CoroutineScope, cliente: ClienteRpc = ClienteRpc()) =
        ModeloApp(cliente, TokenEnMemoria(token), raiz, PreferenciasEnMemoria(), alcance)

    @Test
    fun cargaTodoYCopiaOffline() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertEquals("test-nativa-android", m.info.value?.clienteId)
        assertEquals(6, m.rutina.value?.estructura?.dias?.size)
        assertTrue(m.comidasDelDia.isNotEmpty())
        // Sin red, arranca desde la copia offline.
        val offline = modelo(alcance, ClienteRpc(transporte = SinRed))
        offline.cargar()
        assertTrue(offline.fase.value == ModeloApp.Fase.LISTO && offline.desdeCache.value)
        assertEquals(m.dieta.value?.id, offline.dieta.value?.id)
        assertEquals(ErrorRpc.Clase.RED, offline.ultimaFalla.value)
    }

    @Test
    fun alimentoPropioSeCreaYEntraALaBase() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        // Upsert por (cliente, nombre): correrlo de nuevo no duplica.
        val datos = AlimentoPropioNuevo.preparar("Yogur prueba nativa", 75.0, 3.0, 10.1, 2.25, "porcion", 30.0, "lacteo").datosONull()!!
        val creado = m.crearAlimentoPropio(datos).valorONull()
        assertNotNull(creado)
        assertEquals("Yogur prueba nativa", creado!!.nombre)
        assertTrue(creado.kcal == 250.0 && creado.prot == 10.0 && creado.gramosPorUnidad == 30.0 && creado.unidad == "porcion")
        assertEquals(1, m.alimentosPropios.value.count { it.nombre == "Yogur prueba nativa" })
        val otra = modelo(alcance)
        otra.cargar()
        assertTrue(otra.alimentosPropios.value.any { it.nombre == "Yogur prueba nativa" && it.kcal == 250.0 })
    }

    @Test
    fun comidaLibreSeCreaSeListaYSeBorra() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        val antes = m.comidasLibres.value.size
        val datos = ComidaLibreNueva.preparar("Prueba nativa Android: alfajor", "10:30", 250.0, 3.0, 35.0, 11.0, null).datosONull()!!
        val creada = m.crearComidaLibre(datos).valorONull()!!
        assertTrue(creada.descripcion == "Prueba nativa Android: alfajor" && creada.kcal == 250.0)
        assertEquals(antes + 1, m.comidasLibres.value.size)
        val otra = modelo(alcance)
        otra.cargar()
        assertTrue(otra.comidasLibres.value.any { it.id == creada.id })
        assertTrue(m.borrarComidaLibre(creada.id))
        otra.cargarComidasLibres()
        assertFalse(otra.comidasLibres.value.any { it.id == creada.id })
    }

    /**
     * La plomería de mini-vision sin gastar una llamada a la IA: con un token que no existe, el servicio corta antes (403)
     * y el mensaje llega tal cual. Si el cuerpo estuviera mal armado contestaría 400 "falta imagen".
     */
    @Test
    fun visionConTokenInvalidoCortaAntesDeLaIa() = enUnHilo {
        val jpeg = Base64.getDecoder().decode(
            "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==",
        )
        val e = ClienteRpc().vision("tokenQueNoExiste_0000000000000000", ClienteRpc.TipoVision.PLATO, jpeg).errorONull()
        assertNotNull(e, "respondió ok con un token inválido")
        assertEquals(403, e!!.status)
        assertEquals(ErrorRpc.Clase.PERMANENTE, e.clase)
    }

    @Test
    fun chatEnviaPorLaColaYNoDuplicaUnReintento() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        val chat = ModeloChat(m.cliente, token, m.outbox, alcance)
        chat.cargar()
        val texto = "Prueba nativa Android ${UUID.randomUUID().toString().take(8)}"
        chat.enviar(texto)
        assertEquals(true, chat.hilo.value.mensajes.lastOrNull()?.pendiente)
        m.outbox!!.drenar()
        assertEquals(0, m.outbox!!.pendientes())
        chat.sondear()
        assertTrue(chat.hilo.value.mensajes.any { it.contenido == texto && !it.pendiente })
        assertFalse(chat.hilo.value.mensajes.any { it.pendiente })
        // La respuesta se perdió y la cola lo reintenta: no se manda de nuevo. Un reintento es una op que ya salió una vez
        // (`intentada`): la primera vez sale directo (hallazgo 7 del 15-oct).
        val e = Escrituras(m.cliente, token)
        val op = Operacion("x", "chat", ValorJson.objeto("contenido" to texto(texto)), null, 0, System.currentTimeMillis() - 5_000.0, intentada = true)
        e.ejecutar(op)
        val filas = m.cliente.filas(
            "mypump_get_chat", mapOf("p_token" to texto(token), "p_antes" to ValorJson.Nulo, "p_limite" to numero(10)), MensajeChat::desde,
        ).valorONull()!!
        assertEquals(1, filas.count { it.contenido == texto })
    }

    @Test
    fun miDiaYRevisionPorLaCola() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        val cola = m.outbox!!
        val r = ModeloRevision(m.cliente, token, cola, alcance)
        r.cargarMiDia()
        assertTrue(r.miDiaCargado.value)
        val previoCardio = r.habitos.value.cardio
        // Tocar "hice cardio ✓" y que llegue.
        r.setHabito("cardio", "true")
        assertEquals(true, r.habitos.value.cardio)
        cola.drenar()
        val otra = ModeloRevision(m.cliente, token, cola, alcance)
        otra.cargarMiDia()
        assertEquals(true, otra.habitos.value.cardio)
        // Agua con la espera de 600 ms.
        val vasos = r.habitos.value.vasosAgua
        r.cambiarAgua(if (vasos >= 12) -1 else 1)
        delay(900)
        cola.drenar()
        otra.cargarMiDia()
        assertEquals(r.habitos.value.vasosAgua, otra.habitos.value.vasosAgua)
        // Dejar la cuenta como estaba.
        r.setHabito("cardio", previoCardio?.toString())
        r.cambiarAgua(vasos - r.habitos.value.vasosAgua)
        delay(900)
        cola.drenar()

        // Check: faltan escalas → no sale; completo → sale.
        assertEquals("Faltan: Descanso, Hambre, Adherencia", r.enviarCheckin(Checkin(mapOf("energia" to 4), "")))
        assertNull(r.enviarCheckin(Checkin(mapOf("energia" to 4, "descanso" to 3, "hambre" to 2, "adherencia" to 5), " prueba nativa ")))
        assertTrue(r.checkinEnviado)
        cola.drenar()
        otra.cargarRevision()
        assertTrue(otra.checkin.value?.valores?.get("hambre") == 2 && otra.checkin.value?.nota == "prueba nativa")

        // Peso fuera de rango no se guarda; uno válido entra a la serie.
        assertFalse(r.guardarPeso("25"))
        assertTrue(r.guardarPeso("81,95"))
        assertEquals(82.0, r.serieDePeso.last().kg)
        cola.drenar()
        otra.cargarRevision()
        assertEquals(PesoCorporal.Punto(FechaLocal.hoy(), 82.0), otra.serieDePeso.last())
        assertEquals(0, cola.pendientes())
    }

    /**
     * Sube UNA foto chica (la de espalda de esta semana: es un upsert, repetir no suma) y pide las URLs firmadas. El
     * servicio deja 12 fotos por día por cliente: corre solo con `MYPUMP_PROBAR_FOTOS=1`.
     */
    @Test
    @EnabledIfEnvironmentVariable(named = "MYPUMP_PROBAR_FOTOS", matches = "1")
    fun fotoDeProgresoSubeYSeFirma() = enUnHilo {
        val m = ModeloFotos(ClienteRpc(), token, Disco(raiz, token))
        // JPEG de 8×8 gris (válido: el servidor mira los bytes mágicos).
        val jpeg = Base64.getDecoder().decode(
            "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAAIAAgBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==",
        )
        val r = m.subir("espalda", jpeg)
        assertEquals(ModeloFotos.Resultado.Guardada, r, "subida: ${r.texto}")
        assertTrue(m.fotos.value.any { it.pose == "espalda" && it.semanaLunes == m.semanaActual })
        assertTrue(m.firmar())
        assertNotNull(m.urls.value["${m.semanaActual}|espalda"])
    }

    @Test
    fun progresoConElHistorialReal() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        val p = ModeloProgreso(m.cliente, token)
        p.cargar(m.rutina.value)
        assertEquals(ModeloProgreso.Estado.LISTO, p.estado.value)
        assertTrue(p.tarjetas.value.isNotEmpty())
        assertTrue(p.sesiones.value > 0)
        // Una tarjeta por clave: nunca dos con la misma.
        assertEquals(p.tarjetas.value.size, p.tarjetas.value.map { it.clave }.toSet().size)
        assertTrue(p.tarjetas.value.all { it.resumen.serie.size <= 8 && it.dias.isNotEmpty() })
        // Sin red avisa y no deja tarjetas viejas mezcladas.
        val offline = ModeloProgreso(ClienteRpc(transporte = SinRed), "x")
        offline.cargar(m.rutina.value)
        assertEquals(ModeloProgreso.Estado.SIN_RED, offline.estado.value)
    }

    @Test
    fun sustituirLlegaAncladoYRevertirLoBorra() = enUnHilo { alcance ->
        val m = modelo(alcance)
        m.cargar()
        val comida = m.comidasDelDia.first()
        val original = comida.opciones.first().alimentos.first()
        val sustituto = ValorJson.objeto(
            "name" to texto("Ricota descremada"), "qty" to numero(150), "unit" to texto("g"), "kcal" to numero(207),
            "prot" to numero(17), "carb" to numero(6), "fat" to numero(12), "category" to texto("lacteo"),
        )
        m.sustituir(original, sustituto, comida.id, 0, 0)
        assertEquals("Ricota descremada", m.efectivo(original, comida.id, 0, 0).alimento.nombre)
        m.outbox!!.drenar()
        assertEquals(0, m.outbox!!.pendientes())

        val dietaId = m.dieta.value!!.id
        val p = mapOf("p_token" to texto(token), "p_dieta_id" to texto(dietaId))
        val remotos = m.cliente.filas("mypump_get_food_swaps", p, FoodSwap::desde).valorONull()!!
        val fila = remotos.firstOrNull { it.comidaId == comida.id && it.optIdx == 0 && it.foodIdx == 0 }
        assertNotNull(fila)
        assertEquals(original.nombre, fila!!.foodData["_orig"]?.get("name")?.comoTexto)

        m.revertir(comida.id, 0, 0)
        m.outbox!!.drenar()
        val despues = m.cliente.filas("mypump_get_food_swaps", p, FoodSwap::desde).valorONull()!!
        assertFalse(despues.any { it.comidaId == comida.id && it.optIdx == 0 && it.foodIdx == 0 })
        assertEquals(original.nombre, m.efectivo(original, comida.id, 0, 0).alimento.nombre)
    }

    @Test
    fun tokenInvalido() = enUnHilo { alcance ->
        val prefs = PreferenciasEnMemoria()
        val almacen = TokenEnMemoria("TokenInvalidoDePrueba00000000000")
        val m = ModeloApp(ClienteRpc(), almacen, raiz, prefs, alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.TOKEN_INVALIDO, m.fase.value)
        assertNull(almacen.leer())
        assertEquals("TokenInvalidoDePrueba00000000000", prefs.leer(ModeloApp.CLAVE_TOKEN_INVALIDO))
    }

    companion object {
        private val registro = File(
            System.getProperty("mypump.carpetaPrivada") ?: (System.getProperty("user.home") + "/Developer/nativa-evidencia/privado"),
            "cuentas-prueba.json",
        )

        /** El token de `test-nativa-android`, o null si no está el registro (otra máquina, CI). */
        fun tokenDePrueba(): String? = try {
            Json.parseToJsonElement(registro.readText()).jsonObject["test-nativa-android"]?.jsonObject?.get("token")?.jsonPrimitive?.contentOrNull
        } catch (_: Exception) {
            null
        }
    }
}
