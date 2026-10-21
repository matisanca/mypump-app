package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.EstadoEjercicio
import com.pumpteam.mypump.modelos.RegistroSesion
import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.Sesion
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.HistorialEntreno
import com.pumpteam.mypump.reglas.ReglasEjercicio
import com.pumpteam.mypump.reglas.SemanaEntreno
import com.pumpteam.mypump.reglas.SustitutoEjercicio
import java.io.File
import kotlinx.coroutines.CoroutineScope
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

/**
 * El motor de Entreno contra el backend REAL, con la cuenta de prueba `test-nativa-android` (invisible para el coach; las
 * otras cuentas son de otros agentes). Gemelo de EntrenoIntegracionTests.swift; corre solo donde está el registro privado
 * de cuentas, y el token no sale de ahí (ni a la consola ni a los mensajes de las aserciones).
 *
 * Para dejar la cuenta como estaba, todo lo que se escribe va a la SEMANA 90 (fuera del plan de 12: la app nunca la
 * muestra, y `iniciar_sesion` y `registrar_carga` son idempotentes, así que correrlo de nuevo no suma filas) y la serie se
 * registra con el nombre de un SUSTITUTO que no está en el plan (no ensucia "Última vez" ni el récord de sus ejercicios).
 * Lo único que queda: esa serie y su sesión en la semana 90, y un comentario en un lugar que no existe en la rutina.
 */
@TestMethodOrder(MethodOrderer.MethodName::class)
class EntrenoIntegracionTest {
    private val semanaDePrueba = 90
    private lateinit var token: String

    @BeforeEach
    fun cuenta() {
        val t = IntegracionTest.tokenDePrueba()
        assumeTrue(t != null, "sin el registro privado de cuentas de prueba")
        token = t!!
    }

    private class Armado(val modelo: ModeloEntreno, val cola: Outbox, val cliente: ClienteRpc)

    /** La rutina activa de la cuenta, con la semana 90. */
    private suspend fun armar(raiz: File, alcance: CoroutineScope): Armado {
        val cliente = ClienteRpc()
        val fila = cliente.llamar("mypump_get_rutina_activa", mapOf("p_token" to texto(token))).valorONull()?.primeraFila as? ValorJson.Objeto
        assertNotNull(fila, "no llegó la rutina activa de test-nativa-android")
        val conSemana = ValorJson.Objeto(fila!!.campos + ("semana_actual" to numero(semanaDePrueba)))
        val rutina = RutinaActiva.desde(conSemana.aJson())
        val escrituras = Escrituras(cliente, token)
        val cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { escrituras.ejecutar(it) }
        val catalogo = CatalogoEjercicios.desde(Compartido.texto("catalogo-ejercicios.json"))
        val m = ModeloEntreno(cliente, token, cola, Disco(raiz, token), rutina, catalogoInicial = catalogo, alcance = alcance)
        return Armado(m, cola, cliente)
    }

    /** La sesión de un día en la semana de prueba, según el servidor. */
    private suspend fun sesionDelServidor(a: Armado, dia: String): Sesion? = a.cliente.filas(
        "mypump_get_sesion_dia",
        mapOf("p_token" to texto(token), "p_dia_id" to texto(dia), "p_semana" to numero(semanaDePrueba)),
        Sesion::desde,
    ).valorONull()?.firstOrNull()

    /** El primer ejercicio del día con kg (no de peso corporal) que tenga un sustituto fuera del plan, y ese sustituto. */
    private fun lugarYSustituto(m: ModeloEntreno): Pair<String, SustitutoEjercicio> {
        val delPlan = m.dias.flatMap { d -> d.bloques.flatMap { it.ejercicios } }.map { ClaveEjercicio.de(it.nombre) }.toSet()
        for (ex in m.dia.value.lista) {
            if (ex.tipo == "cardio" || ReglasEjercicio.sinKg(ex)) continue
            m.sustitutos(ex.id).firstOrNull { ClaveEjercicio.de(it.nombre) !in delPlan }?.let { return ex.id to it }
        }
        error("ningún ejercicio del día tiene un sustituto fuera del plan")
    }

    @Test
    fun serieConSustitutoEstadoHistorialPorClaveYRestaurar() = enUnHilo { alcance ->
        val a = armar(carpetaTemporal("mypump-entreno-real"), alcance)
        val m = a.modelo
        val d1 = m.dias.first().id!!
        m.cargar()
        m.cambiarDia(d1)
        assertTrue(m.semana == semanaDePrueba && m.dia.value.dia.id == d1)
        val (lugar, sub) = lugarYSustituto(m)
        val nombrePlan = m.dia.value.ejercicio(lugar)!!.nombre

        // Sustituir solo por hoy: la serie va con el nombre del sustituto y el id del lugar (SER-13).
        m.sustituir(lugar, sub, fijar = false)
        assertEquals(sub.nombre, m.efectivo(m.dia.value.ejercicio(lugar)!!).ejercicio.nombre)
        // Una corrida anterior la dejó confirmada en el servidor: el lápiz la abre para volver a escribirla (SER-06).
        if (m.dia.value.ejercicios[lugar]?.series?.get(0)?.confirmada == true) m.editarSerie(lugar, 0)
        m.escribir(lugar, 0, "reps", "10")
        m.escribir(lugar, 0, "kg", "40")
        m.elegirRir(lugar, 0, 0)
        // Si una corrida anterior cerró este día, se reabre (SES-07).
        m.confirmarSerie(lugar, 0) { true }
        assertEquals(true, m.dia.value.ejercicios[lugar]?.series?.get(0)?.confirmada)
        a.cola.drenar()
        assertTrue(a.cola.operaciones().isEmpty(), "la serie no entró")

        val sesion = sesionDelServidor(a, d1)
        val sid = sesion?.id
        assertNotNull(sid)
        val registros = a.cliente.filas(
            "mypump_get_registros_sesion", mapOf("p_token" to texto(token), "p_sesion_id" to texto(sid!!)), RegistroSesion::desde,
        ).valorONull()!!
        val fila = registros.first { it.ejercicioId == lugar && it.serie == 1 }
        assertTrue(fila.ejercicioNombre == sub.nombre && fila.pesoKg == 40.0 && fila.reps == 10)
        assertEquals(0, fila.rir, "RIR 0 es 'fue al fallo', no 'no lo cargó'")
        // La variante viaja en notas solo si el sustituto muestra el selector (revisión del 21-oct: un sustituto sin agarre
        // no se graba con el del plan).
        val conSelector = ReglasEjercicio.variantes(sub.nombre) != null
        assertEquals(if (conSelector) ReglasEjercicio.variantes(nombrePlan)?.opciones?.firstOrNull() else null, fila.notas, "la variante viaja en notas")

        // "Terminé este ejercicio" con una serie: completo, marcado a mano (SER-15).
        m.terminar(lugar) { true }
        a.cola.drenar()
        val estados = a.cliente.filas(
            "mypump_get_ejercicios_estado", mapOf("p_token" to texto(token), "p_sesion_id" to texto(sid)), EstadoEjercicio::desde,
        ).valorONull()!!
        val estado = estados.first { it.ejercicioId == lugar }
        assertTrue(estado.status == "completo" && estado.marcadoManualmente)

        // El historial del lugar sustituido es el del SUSTITUTO, por clave (SER-08), con la serie recién cargada.
        m.invalidarHistorial(lugar)
        m.pedirHistorial(lugar)
        val h = m.dia.value.historial[lugar]!!
        assertTrue(h.all { it.clave == ClaveEjercicio.de(sub.nombre) })
        assertTrue(h.any { it.pesoKg == 40.0 && it.reps == 10 && it.rir == 0 })
        assertNotNull(m.dia.value.record(lugar))

        // Restaurar en otro teléfono (sin nada local): la sesión, la serie y el estado vienen del servidor (SES-02).
        val b = armar(carpetaTemporal("mypump-entreno-real"), alcance)
        b.modelo.cargar()
        b.modelo.cambiarDia(d1)
        assertEquals(sid, b.modelo.dia.value.sesionId)
        val serie = b.modelo.dia.value.ejercicios[lugar]!!.series.first()
        assertTrue(serie.confirmada && serie.kg == "40" && serie.reps == "10" && serie.rir == "0")
        assertEquals(sub.nombre, serie.nombreRegistrado, "reabrir no la renombra al original")
        assertTrue(b.modelo.dia.value.estado(lugar) == "completo" && b.modelo.dia.value.meta[lugar]?.manual == true)

        // Una sesión local que el servidor no conoce se descarta (nada de sesiones fantasma).
        val fantasma = carpetaTemporal("mypump-entreno-real")
        Disco(fantasma, token).guardar(
            ModeloEntreno.Archivo.SESIONES,
            ValorJson.objeto(
                d1 to ModeloEntreno.SesionLocal("00000000-0000-4000-8000-000000000000", semanaDePrueba, finalizada = true, inicio = 1.0).aValor(),
            ),
        )
        val c = armar(fantasma, alcance)
        c.modelo.cargar()
        c.modelo.cambiarDia(d1)
        assertTrue(c.modelo.dia.value.sesionId == sid && c.modelo.inicioSesion.value != 1.0)

        // Dejarlo como estaba: el ejercicio vuelve a pendiente y el lugar al original.
        m.reabrir(lugar)
        a.cola.drenar()
        val despues = a.cliente.filas(
            "mypump_get_ejercicios_estado", mapOf("p_token" to texto(token), "p_sesion_id" to texto(sid)), EstadoEjercicio::desde,
        ).valorONull()!!
        assertEquals("pendiente", despues.first { it.ejercicioId == lugar }.status)
        m.revertirSustitucion(lugar)
        assertEquals(nombrePlan, m.efectivo(m.dia.value.ejercicio(lugar)!!).ejercicio.nombre)
    }

    @Test
    fun cerrarElDiaYReabrirloConUnaSerie() = enUnHilo { alcance ->
        val a = armar(carpetaTemporal("mypump-entreno-real"), alcance)
        val m = a.modelo
        val d1 = m.dias.first().id!!
        m.cargar()
        m.cambiarDia(d1)
        val (lugar, sub) = lugarYSustituto(m)
        m.sustituir(lugar, sub, fijar = false)
        m.empezar()
        val sid = m.dia.value.sesionId
        assertNotNull(sid)
        assertTrue(m.sesionIniciada.value && m.inicioSesion.value != null)
        assertEquals(ModeloEntreno.ResultadoCierre.CERRADO, m.cerrarDia("prueba del motor de Entreno"))
        val cerrada = sesionDelServidor(a, d1)
        assertTrue(cerrada?.id == sid && cerrada?.finalizadaEn != null)
        assertTrue(m.dia.value.diaFinalizado && m.hecho(m.dias.first { it.id == d1 }))
        // La sustitución "solo hoy" del día cerrado se conserva (para reabrir y corregir).
        assertNotNull(m.dia.value.sustituciones[lugar])

        // Cargar una serie en el día cerrado pregunta, reabre y usa la MISMA sesión (SES-07).
        val preguntas = mutableListOf<String>()
        if (m.dia.value.ejercicios[lugar]?.series?.get(1)?.confirmada == true) m.editarSerie(lugar, 1)
        m.escribir(lugar, 1, "reps", "8")
        m.escribir(lugar, 1, "kg", "40")
        m.confirmarSerie(lugar, 1) { p ->
            preguntas += p.titulo
            true
        }
        assertTrue(preguntas.firstOrNull() == "Este día ya lo cerraste" && !m.dia.value.diaFinalizado)
        val op = a.cola.operaciones().first { it.kind == "carga" }
        assertTrue(op.payload["sesionId"]?.comoTexto == sid && op.dedupeKey == "carga_${d1}_${lugar}_1_s$semanaDePrueba")
        a.cola.drenar()
        assertEquals(0, a.cola.pendientes())
        m.revertirSustitucion(lugar)
    }

    @Test
    fun comentarioDirectoYLeidos() = enUnHilo { alcance ->
        val a = armar(carpetaTemporal("mypump-entreno-real"), alcance)
        val m = a.modelo
        m.cargar()
        // Un lugar que no existe en la rutina: no aparece en ninguna card.
        val lugar = "prueba-nativa-entreno-d0-0"
        // Texto fijo: el servidor descarta el mismo texto dentro de 2 minutos (075), y lo que quede se reconoce.
        val texto = "prueba del motor de Entreno (test de integración de la app nativa Android)"
        assertTrue(m.comentar(lugar, "  $texto  "))
        assertTrue(m.comentarios.value.comentarios(lugar).any { it.contenido == texto && it.autor == "cliente" })
        assertEquals(0, m.comentarios.value.sinLeer(lugar), "lo del cliente no cuenta como no leído")
        m.marcarLeidos(lugar)
        assertFalse(m.comentar(lugar, "   "))
    }

    @Test
    fun historialDelDiaUnPedido() = enUnHilo { alcance ->
        val a = armar(carpetaTemporal("mypump-entreno-real"), alcance)
        val m = a.modelo
        m.cambiarDia(m.dias[1].id!!)
        m.precargarHistorial()
        val trabajo = m.dia.value.lista.filter { it.tipo != "calentamiento" }
        assertTrue(trabajo.all { m.dia.value.historial[it.id] != null }, "quedó algún ejercicio sin historial")
        // La cuenta tiene historia de las semanas anteriores en los ejercicios de trabajo: el récord sale de ahí. "Última
        // vez" es la sesión anterior a HOY: la historia de esta cuenta se sembró por las RPC (con la fecha del día de la
        // siembra), así que solo aparece si hay alguna fila de otro día.
        val conHistoria = trabajo.filter { !m.dia.value.historial[it.id].isNullOrEmpty() }
        assertTrue(conHistoria.isNotEmpty())
        val hoy = FechaLocal.hoy()
        for (ex in conHistoria) {
            assertNotNull(m.dia.value.record(ex.id))
            val deOtroDia = m.dia.value.historial[ex.id]!!.any { HistorialEntreno.fechaLocal(it.registradoEn, java.time.ZoneId.systemDefault()) != hoy }
            if (deOtroDia) assertNotNull(m.tarjeta(ex.id)?.ultimaVez) else assertNull(m.tarjeta(ex.id)?.ultimaVez)
        }
    }

    @Test
    fun bloqueNuevoSinBloqueEnColaNoHaceNada() = enUnHilo { alcance ->
        val a = armar(carpetaTemporal("mypump-entreno-real"), alcance)
        assertTrue(!a.modelo.rutina.value.tieneSiguiente && !a.modelo.puedeEmpezarBloque)
        assertEquals(ModeloEntreno.ResultadoAvance.Error(SemanaEntreno.errorBloqueNuevo(false)), a.modelo.empezarBloqueNuevo())
    }

    @Test
    fun elModeloDeLaAppArmaElEntrenoConElCatalogoDelServidor() = enUnHilo { alcance ->
        val m = ModeloApp(ClienteRpc(), TokenEnMemoria(token), carpetaTemporal("mypump-entreno-real"), PreferenciasEnMemoria(), alcance)
        m.cargar()
        val e = m.entreno.value
        assertNotNull(e)
        assertTrue(e!!.rutina.value.id == m.rutina.value?.id && e.dias.isNotEmpty() && !e.demo)
        m.cargarCatalogo()
        assertTrue(e.catalogo.value.entradas.size > 500, "el del servidor (~873)")
    }

    /**
     * SER-14 de punta a punta contra el servidor real (nativa_003, aplicada el 14-oct): una sustitución fijada en un
     * teléfono llega al otro, y "Volver a …" en el segundo llega al primero. Gemelo de
     * IntegracionTests.unaSustitucionPasaDeUnTelefonoAOtro (iOS). Dos teléfonos = dos discos con el mismo token. Repetirla
     * no deja basura: la vuelta al original deja la lápida, y la próxima corrida la supera (es también la prueba del piso
     * por clave).
     */
    @Test
    fun unaSustitucionPasaDeUnTelefonoAOtro() = enUnHilo { alcance ->
        val a = armar(carpetaTemporal("mypump-sustituciones-a"), alcance)
        val b = armar(carpetaTemporal("mypump-sustituciones-b"), alcance)
        a.modelo.cargar()
        b.modelo.cargar()
        assertEquals(a.modelo.rutina.value.id, b.modelo.rutina.value.id)
        val (lugar, sub) = lugarYSustituto(a.modelo)

        // A la fija; sale por la cola al servidor.
        a.modelo.sustituir(lugar, sub, fijar = true)
        a.modelo.encoladoSustituciones?.join()
        a.cola.drenar()
        assertTrue(a.cola.operaciones().isEmpty(), "no salió de la cola de A")

        // B la lee.
        b.modelo.sincronizarSustituciones()
        val enB = b.modelo.dia.value.sustituciones[lugar]
        assertEquals(sub.nombre, enB?.get("current")?.get("nombre")?.comoTexto, "no llegó a B")
        assertEquals(ValorJson.Booleano(true), enB?.get("fijado"))
        assertEquals(sub.nombre, b.modelo.efectivo(b.modelo.dia.value.ejercicio(lugar)!!).ejercicio.nombre)

        // B vuelve al original; A lo ve.
        b.modelo.revertirSustitucion(lugar)
        b.modelo.encoladoSustituciones?.join()
        b.cola.drenar()
        assertTrue(b.cola.operaciones().isEmpty(), "no salió de la cola de B")
        a.modelo.sincronizarSustituciones()
        assertNull(a.modelo.dia.value.sustituciones[lugar], "la vuelta al original no llegó a A")
    }
}
