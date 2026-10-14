package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.Descanso
import com.pumpteam.mypump.reglas.EscriturasEntreno
import com.pumpteam.mypump.reglas.FechaJs
import com.pumpteam.mypump.reglas.SemanaEntreno
import com.pumpteam.mypump.reglas.SerieLocal
import com.pumpteam.mypump.reglas.TiempoEntreno
import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de EntrenoModeloTests.swift: el modelo de Entreno contra un servidor de mentira que contesta por RPC (las
// respuestas tienen la forma de las reales: apps/shared/fixtures). Los casos de la sesión cacheada son los de
// scripts/test-sesion-cacheada.mjs de la rama fix/sesion-cache-valida-servidor (SES-02).

/** Contesta cada RPC con lo que diga su regla; null es "sin red". Anota todo lo que le piden. */
class Servidor : Transporte {
    private val reglas = HashMap<String, suspend (ValorJson) -> Pair<Int, String>?>()
    private val anotadas = mutableListOf<Pair<String, ValorJson>>()

    fun regla(fn: String, r: suspend (ValorJson) -> Pair<Int, String>?) = synchronized(this) { reglas["mypump_$fn"] = r }
    fun cuando(fn: String, status: Int, cuerpo: String) = regla(fn) { status to cuerpo }
    fun cuando(fn: String, cuerpo: String) = cuando(fn, 200, cuerpo)
    fun sinRed(fn: String) = regla(fn) { null }

    fun llamadas(fn: String): List<ValorJson> = synchronized(this) { anotadas.filter { it.first == "mypump_$fn" }.map { it.second } }
    val orden: List<String> get() = synchronized(this) { anotadas.map { it.first } }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val fn = pedido.ruta.substringAfterLast('/')
        val cuerpo = pedido.cuerpo?.let { runCatching { ValorJson.parsear(it.toString(Charsets.UTF_8)) }.getOrNull() } ?: ValorJson.Nulo
        val regla = synchronized(this) {
            anotadas += fn to cuerpo
            reglas[fn]
        } ?: return Respuesta(200, "[]".toByteArray())
        val r = regla(cuerpo) ?: throw IOException("sin conexión a internet")
        return Respuesta(r.first, r.second.toByteArray())
    }
}

/** Una demora que NO se corta al cancelar (como una respuesta de red que igual llega). */
suspend fun demora(ms: Long) = withContext(NonCancellable) { delay(ms) }

class RelojDePrueba(@Volatile var ms: Double)

const val AHORA = 1_792_000_800_000.0   // 14-oct-2026 15:00 en Buenos Aires
const val JULIO = 1_784_570_400_000.0   // 20-jul-2026 18:00 UTC
val zonaAR: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

const val ESTRUCTURA_DE_PRUEBA = """
{"semanas_total":12,"dias":[
  {"id":"d1","n":1,"nombre":"TIRÓN A — ANCHO","bloques":[{"titulo":"BLOQUE 1 — ESPALDA","ejercicios":[
    {"id":"jal-d1-0","nombre":"Jalón al pecho","tipo":"compuesto","descanso_segundos":150,"progresion":[{"semana":1,"series":2,"reps":"10","rir":"1"}]},
    {"id":"rem-d1-1","nombre":"Remo con barra","tipo":"compuesto","descanso_segundos":0,"progresion":[{"semana":1,"series":2,"reps":"8","rir":"1"}]}]}]},
  {"id":"d2","n":2,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — PECHO","ejercicios":[
    {"id":"pre-d2-0","nombre":"Press banca","tipo":"compuesto","descanso_segundos":180,"progresion":[{"semana":1,"series":1,"reps":"8","rir":"1"}]}]}]},
  {"id":"d3","nombre":"PIERNA","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
    {"id":"sen-d3-0","nombre":"Sentadilla","tipo":"compuesto","descanso_segundos":180,"progresion":[{"semana":1,"series":1,"reps":"6","rir":"1"}]}]}]}
]}
"""

/** La fila de `get_rutina_activa` de la rutina de prueba. */
fun filaRutina(semana: Int = 5, tieneSiguiente: Boolean = false): String =
    """{"id":"rut-prueba","version":1,"semana_actual":$semana,"tiene_siguiente":$tieneSiguiente,"estructura":$ESTRUCTURA_DE_PRUEBA}"""

fun rutinaDePrueba(semana: Int = 5, tieneSiguiente: Boolean = false): RutinaActiva =
    RutinaActiva.desde(ValorJson.parsear(filaRutina(semana, tieneSiguiente)).aJson())

/** Un catálogo chico: los tres comparten patrón y músculo, así "Jalón al pecho" tiene sustitutos. */
val catalogoDePrueba: CatalogoEjercicios = CatalogoEjercicios.desde(
    """
    [{"slug_en":"Wide-Grip_Lat_Pulldown","name_en":"Wide-Grip Lat Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
     {"slug_en":"V-Bar_Pulldown","name_en":"V-Bar Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
     {"slug_en":"Pullups","name_en":"Pullups","primary_muscle":"lats","equipment":"body only","patron_movimiento":"traccion_vertical"}]
    """,
)

class Banco(private val alcance: CoroutineScope, ejecutar: Boolean = false) {
    val servidor = Servidor()
    val reloj = RelojDePrueba(AHORA)
    val raiz: File = carpetaTemporal("mypump-entreno")
    val disco: Disco get() = Disco(raiz, "tok-prueba")
    val cola: Outbox

    init {
        val escrituras = Escrituras(ClienteRpc(transporte = servidor), "tok-prueba")
        cola = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { op ->
            if (ejecutar) escrituras.ejecutar(op) else ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin mandar")))
        }
    }

    fun modelo(rutina: RutinaActiva = rutinaDePrueba(), token: String? = "tok-prueba"): ModeloEntreno {
        val r = reloj
        return ModeloEntreno(
            cliente = ClienteRpc(transporte = servidor), token = token, outbox = if (token == null) null else cola,
            disco = if (token == null) null else disco, rutinaInicial = rutina, catalogoInicial = catalogoDePrueba, zona = zonaAR,
            reloj = { Instant.ofEpochMilli(r.ms.toLong()) }, alcance = alcance,
        )
    }

    fun cacheDeSesion(m: Map<String, ModeloEntreno.SesionLocal>) {
        disco.guardar(ModeloEntreno.Archivo.SESIONES, ValorJson.Objeto(m.mapValues { it.value.aValor() }))
    }

    val sesionesEnDisco: Map<String, ModeloEntreno.SesionLocal>
        get() = (disco.leer(ModeloEntreno.Archivo.SESIONES) as? JsonObject)
            ?.mapValues { ModeloEntreno.SesionLocal.desde(ValorJson.desde(it.value)) } ?: emptyMap()

    val descansoEnDisco: Descanso.Guardado? get() = disco.leer(ModeloEntreno.Archivo.DESCANSO)?.let { Descanso.Guardado.desde(ValorJson.desde(it)) }
}

fun sesionJson(id: String, dia: String = "d1", semana: Int = 5, iniciada: String? = null, finalizada: String? = null): String {
    val i = iniciada?.let { "\"$it\"" } ?: "null"
    val f = finalizada?.let { "\"$it\"" } ?: "null"
    return """[{"id":"$id","dia_id":"$dia","semana":$semana,"iniciada_en":$i,"finalizada_en":$f}]"""
}

/** La sesión del día se confirma con el servidor (SES-02). */
class EntrenoSesionTest {
    /** El teléfono de Matoff: abrió el día 1 de la semana 5 del bloque viejo, lo cerró, y le quedó todo eso guardado. */
    private fun cacheViejo(b: Banco, semana: Int = 5) =
        b.cacheDeSesion(mapOf("d1" to ModeloEntreno.SesionLocal("ses-vieja", semana, finalizada = true, inicio = JULIO)))

    @Test
    fun mismaSesionEnElServidorSeUsaElCache() = enUnHilo { alcance ->
        val b = Banco(alcance)
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-vieja"))
        val m = b.modelo()
        m.restaurarSesion()
        assertEquals("ses-vieja", m.dia.value.sesionId)
        // El cerrado es LOCAL a propósito: reabrir el día solo borra la marca del teléfono.
        assertTrue(m.dia.value.diaFinalizado)
        assertEquals(JULIO, m.inicioSesion.value)
        assertEquals(1, b.servidor.llamadas("get_sesion_dia").size)
        assertEquals("ses-vieja", b.servidor.llamadas("get_registros_sesion").firstOrNull()?.get("p_sesion_id")?.comoTexto)
        assertEquals(1, b.servidor.llamadas("get_ejercicios_estado").size)
    }

    @Test
    fun noHaySesionDelDiaArrancaLimpioYSeBorraElCache() = enUnHilo { alcance ->
        val b = Banco(alcance)
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", "[]")
        val m = b.modelo()
        m.restaurarSesion()
        assertTrue(m.dia.value.sesionId == null && !m.sesionIniciada.value && !m.dia.value.diaFinalizado && m.inicioSesion.value == null)
        assertNull(b.sesionesEnDisco["d1"])
        assertTrue(b.servidor.llamadas("get_registros_sesion").isEmpty(), "traía las series de julio")
        assertEquals(1, b.servidor.llamadas("get_sesion_dia").size)
    }

    @Test
    fun otraSesionSeUsaEsaConSuArranque() = enUnHilo { alcance ->
        val b = Banco(alcance)
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-nueva", iniciada = "2026-09-26T13:00:00Z"))
        val m = b.modelo()
        m.restaurarSesion()
        val iniciada = FechaJs.leer("2026-09-26T13:00:00Z")!!.toEpochMilli().toDouble()
        assertTrue(m.dia.value.sesionId == "ses-nueva" && !m.dia.value.diaFinalizado)
        // El arranque guardado era el de la sesión archivada: no se hereda.
        assertEquals(iniciada, m.inicioSesion.value)
        assertEquals(ModeloEntreno.SesionLocal("ses-nueva", 5, false, iniciada), b.sesionesEnDisco["d1"])
        assertEquals(1, b.servidor.llamadas("get_sesion_dia").size, "se reusa la respuesta")
        assertEquals("ses-nueva", b.servidor.llamadas("get_registros_sesion").firstOrNull()?.get("p_sesion_id")?.comoTexto)
    }

    @Test
    fun laOtraYaEstaCerradaElDiaApareceCerrado() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.cacheDeSesion(mapOf("d1" to ModeloEntreno.SesionLocal("ses-vieja", 5, finalizada = false, inicio = JULIO)))
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-nueva", iniciada = "2026-09-25T13:00:00Z", finalizada = "2026-09-25T14:10:00Z"))
        val m = b.modelo()
        m.restaurarSesion()
        assertTrue(m.dia.value.diaFinalizado)
        assertEquals(true, b.sesionesEnDisco["d1"]?.finalizada)
    }

    @Test
    fun sinRedSeConfiaEnElCache() = enUnHilo { alcance ->
        val b = Banco(alcance)
        cacheViejo(b)
        b.servidor.sinRed("get_sesion_dia")
        val m = b.modelo()
        m.restaurarSesion()
        assertTrue(m.dia.value.sesionId == "ses-vieja" && m.dia.value.diaFinalizado && m.inicioSesion.value == JULIO)
        assertEquals(ModeloEntreno.SesionLocal("ses-vieja", 5, true, JULIO), b.sesionesEnDisco["d1"])
    }

    @Test
    fun errorDelServidorTampocoSeDescarta() = enUnHilo { alcance ->
        val b = Banco(alcance)
        cacheViejo(b)
        b.servidor.cuando("get_sesion_dia", 503, """{"code":"","message":"Service Unavailable"}""")
        val m = b.modelo()
        m.restaurarSesion()
        assertEquals("ses-vieja", m.dia.value.sesionId)
        assertEquals("ses-vieja", b.sesionesEnDisco["d1"]?.sesionId)
    }

    @Test
    fun cacheDeOtraSemanaSeBorraYSePreguntaUnaVez() = enUnHilo { alcance ->
        val b = Banco(alcance)
        cacheViejo(b, semana = 4)
        b.servidor.cuando("get_sesion_dia", "[]")
        val m = b.modelo()
        m.restaurarSesion()
        assertNull(m.dia.value.sesionId)
        assertNull(b.sesionesEnDisco["d1"])
        assertEquals(listOf(ValorJson.Numero(5.0)), b.servidor.llamadas("get_sesion_dia").map { it["p_semana"] })
    }

    @Test
    fun sinCachePreguntaYGuardaLoQueVenga() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-x", iniciada = "2026-10-14T17:00:00Z"))
        val m = b.modelo()
        m.restaurarSesion()
        assertTrue(m.dia.value.sesionId == "ses-x" && m.sesionIniciada.value)
        assertEquals("ses-x", b.sesionesEnDisco["d1"]?.sesionId)
        assertEquals(60, m.minutos)
    }

    @Test
    fun laRespuestaTardiaDelDiaAnteriorNoPisaLaDelDiaNuevo() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.cacheDeSesion(mapOf("d1" to ModeloEntreno.SesionLocal("ses-vieja", 5), "d2" to ModeloEntreno.SesionLocal("ses-d2", 5)))
        b.servidor.regla("get_sesion_dia") { p ->
            if (p["p_dia_id"]?.comoTexto == "d1") {
                demora(150)
                200 to sesionJson("ses-vieja")
            } else {
                200 to sesionJson("ses-d2", dia = "d2")
            }
        }
        val m = b.modelo()
        val primera = async { m.restaurarSesion() }   // día 1: la respuesta tarda
        delay(20)
        m.cambiarDia("d2")                            // día 2: responde enseguida
        primera.await()
        assertTrue(m.dia.value.dia.id == "d2" && m.dia.value.sesionId == "ses-d2")
        assertFalse(b.servidor.llamadas("get_registros_sesion").any { it["p_sesion_id"]?.comoTexto == "ses-vieja" })
    }

    @Test
    fun loQueSigueEnLaColaSePintaEncimaDeLoDelServidor() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1"))
        // El servidor tiene la serie 2 con lo de antes; en la cola está corregida (sin red): gana la cola.
        b.servidor.cuando(
            "get_registros_sesion",
            """[{"ejercicio_id":"jal-d1-0","serie_numero":2,"peso_kg":60,"reps_realizadas":8,"rir_real":null,"notas":null,"ejercicio_nombre":"Jalón al pecho"}]""",
        )
        b.cola.encolar(
            "carga",
            EscriturasEntreno.carga(
                "ses-1", "d1", 5, "jal-d1-0", 1, SerieLocal(reps = "9", kg = "62,5", rir = "0", varianteRegistrada = "Supino"),
                "Jalón al pecho", "Prono",
            ),
            EscriturasEntreno.claveCarga("d1", "jal-d1-0", 1, 5),
        )
        // Otra semana: no es de este día que se mira.
        b.cola.encolar(
            "carga",
            EscriturasEntreno.carga(null, "d1", 4, "jal-d1-0", 0, SerieLocal(reps = "8", kg = "60"), "Jalón al pecho", null),
            EscriturasEntreno.claveCarga("d1", "jal-d1-0", 0, 4),
        )
        val m = b.modelo()
        m.restaurarSesion()
        val series = m.dia.value.ejercicios["jal-d1-0"]?.series
        assertEquals(
            SerieLocal(reps = "9", kg = "62.5", rir = "0", confirmada = true, nombreRegistrado = "Jalón al pecho", varianteRegistrada = "Supino"),
            series?.get(1),
        )
        assertEquals(false, series?.get(0)?.confirmada)
        assertEquals(2, b.cola.pendientes(), "las dos semanas conviven en la cola (dedupe con semana)")
    }

    /**
     * Revisión del 14-oct, hallazgo 5: sin señal en el gimnasio la sesión no se pudo crear y las series quedaron en la
     * cola. Al volver al día (o abrir la app sin red) tienen que verse confirmadas, no vacías.
     */
    @Test
    fun sinSesionYSinRedLaColaIgualSePinta() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.sinRed("get_sesion_dia")
        b.cola.encolar(
            "carga",
            EscriturasEntreno.carga(null, "d1", 5, "jal-d1-0", 0, SerieLocal(reps = "10", kg = "60"), "Jalón al pecho", null),
            EscriturasEntreno.claveCarga("d1", "jal-d1-0", 0, 5),
        )
        val m = b.modelo()
        m.restaurarSesion()
        assertNull(m.dia.value.sesionId)
        assertEquals(true, m.dia.value.ejercicios["jal-d1-0"]?.series?.get(0)?.confirmada)
        assertEquals("60", m.dia.value.ejercicios["jal-d1-0"]?.series?.get(0)?.kg)
    }
}

/** Historial por clave (SER-08/09/10). */
class EntrenoHistorialTest {
    private val filaJalon =
        """{"clave":"jalon al pecho","registrado_en":"2026-10-12T21:00:00+00:00","peso_kg":60,"reps_realizadas":10,"rir_real":1,"serie_numero":1,"notas":null,"ejercicio_nombre":"Jalón al pecho"}"""

    @Test
    fun unPedidoPorDiaYLaClaveEsLaDelEfectivo() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_historico_por_clave", "[$filaJalon]")
        val m = b.modelo()
        m.precargarHistorial()
        assertEquals(1, b.servidor.llamadas("get_historico_por_clave").size)
        val pedido = b.servidor.llamadas("get_historico_por_clave").first()
        assertEquals(ValorJson.Lista(listOf(ValorJson.Texto("jalon al pecho"), ValorJson.Texto("remo con barra"))), pedido["p_claves"])
        assertEquals(ValorJson.Numero(48.0), pedido["p_limit_por_ej"])
        assertTrue(m.dia.value.historial["jal-d1-0"]?.size == 1 && m.dia.value.historial["rem-d1-1"] == emptyList<Any>())
        assertEquals("60kg × 10 · RIR 1", m.dia.value.record("jal-d1-0"))
    }

    @Test
    fun pgrst202CaeAlCaminoViejoYQuedaRecordado() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando(
            "get_historico_por_clave", 404,
            """{"code":"PGRST202","message":"Could not find the function public.mypump_get_historico_por_clave"}""",
        )
        b.servidor.cuando("get_historico_ejercicio", "[$filaJalon]")
        val m = b.modelo()
        m.pedirHistorial("jal-d1-0")
        assertEquals(1, m.dia.value.historial["jal-d1-0"]?.size)
        m.pedirHistorial("rem-d1-1")
        assertEquals(1, b.servidor.llamadas("get_historico_por_clave").size, "la ausencia se recuerda")
        assertEquals(
            listOf(ValorJson.Texto("jal-d1-0"), ValorJson.Texto("rem-d1-1")),
            b.servidor.llamadas("get_historico_ejercicio").map { it["p_ejercicio_id"] },
        )
    }

    @Test
    fun sinRedQuedaSinCargarYNuncaCaeAlCaminoPorLugar() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.sinRed("get_historico_por_clave")
        val m = b.modelo()
        m.pedirHistorial("jal-d1-0")
        assertNull(m.dia.value.historial["jal-d1-0"], "un corte no es 'Primera vez'")
        assertTrue(b.servidor.llamadas("get_historico_ejercicio").isEmpty(), "por lugar el historial viene mezclado")
        // Vuelve la señal: el próximo toque lo trae.
        b.servidor.cuando("get_historico_por_clave", "[$filaJalon]")
        m.tocarCard("jal-d1-0")
        assertEquals(1, m.dia.value.historial["jal-d1-0"]?.size)
    }

    @Test
    fun unaRespuestaViejaNoPisaElHistorialDeUnLugarYaSustituido() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.regla("get_historico_por_clave") { p ->
            if (p["p_claves"] == ValorJson.Lista(listOf(ValorJson.Texto("jalon al pecho")))) {
                demora(150)   // llega DESPUÉS que la del sustituto
                200 to "[$filaJalon]"
            } else {
                200 to "[]"
            }
        }
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        val viejo = async { m.pedirHistorial("jal-d1-0") }
        delay(20)
        m.sustituir("jal-d1-0", sub, fijar = false)
        viejo.await()
        delay(200)   // que llegue (y se descarte) la respuesta vieja
        assertEquals(ClaveEjercicio.de(sub.nombre), m.clave("jal-d1-0"))
        assertEquals(emptyList<Any>(), m.dia.value.historial["jal-d1-0"], "quedó el historial del original bajo el lugar sustituido")
        assertEquals(2, b.servidor.llamadas("get_historico_por_clave").size)
    }
}

/** Series, cola, cierre y semana. */
class EntrenoAccionesTest {
    @Test
    fun confirmarEncolaConLaSemanaYArrancaElDescanso() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "62,5")
        m.elegirRir("jal-d1-0", 0, 0)
        m.confirmarSerie("jal-d1-0", 0) { true }
        val op = b.cola.operaciones().first()
        assertTrue(op.kind == "carga" && op.dedupeKey == "carga_d1_jal-d1-0_0_s5")
        assertTrue(op.payload["datos"]?.get("peso") == ValorJson.Numero(62.5) && op.payload["datos"]?.get("rir") == ValorJson.Numero(0.0))
        assertEquals("Prono", op.payload["datos"]?.get("notas")?.comoTexto, "la variante default del jalón")
        assertTrue(m.descanso.value.descanso?.objetivo == 150.0 && m.descanso.value.visible)
        assertEquals(150.0, b.descansoEnDisco?.target)
        assertEquals(AHORA, m.inicioSesion.value, "el cronómetro arranca con la primera serie")
        // El descanso 0 del plan es 90 (normalizarRutina).
        m.escribir("rem-d1-1", 0, "reps", "8")
        m.escribir("rem-d1-1", 0, "kg", "70")
        m.confirmarSerie("rem-d1-1", 0) { true }
        assertEquals(90.0, m.descanso.value.descanso?.objetivo)
    }

    @Test
    fun conSustitucionVaElNombreDelSustitutoYElIdDelLugar() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "50")
        m.confirmarSerie("jal-d1-0", 0) { true }
        val op = b.cola.operaciones().first()
        assertEquals(sub.nombre, op.payload["datos"]?.get("ejercicioNombre")?.comoTexto)
        assertEquals("jal-d1-0", op.payload["datos"]?.get("ejercicioId")?.comoTexto)
        // En disco, con el formato de la web.
        val guardadas = ValorJson.desde(b.disco.leer(ModeloEntreno.Archivo.sustituciones("rut-prueba"))!!)
        val g = guardadas["jal-d1-0"]
        assertEquals(sub.nombre, g?.get("current")?.get("nombre")?.comoTexto)
        assertTrue(g?.get("fijado") == ValorJson.Booleano(true) && g["semana"] == ValorJson.Numero(5.0))
        assertTrue(g?.get("diaId")?.comoTexto == "d1" && g["original"]?.get("nombre")?.comoTexto == "Jalón al pecho")
        m.revertirSustitucion("jal-d1-0")
        assertFalse(m.efectivo(m.dia.value.ejercicio("jal-d1-0")!!).sustituido)
    }

    @Test
    fun lasNoFijadasDeOtraSemanaSePodanAlCargar() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.disco.guardar(
            ModeloEntreno.Archivo.sustituciones("rut-prueba"),
            ValorJson.objeto(
                "jal-d1-0" to ValorJson.objeto(
                    "original" to ValorJson.objeto("nombre" to texto("Jalón al pecho")), "current" to ValorJson.objeto("nombre" to texto("Dominadas")),
                    "fijado" to ValorJson.Booleano(false), "semana" to numero(4), "diaId" to texto("d1"),
                ),
                "rem-d1-1" to ValorJson.objeto("current" to ValorJson.objeto("nombre" to texto("Remo en T")), "semana" to numero(4), "diaId" to texto("d1")),
            ),
        )
        val m = b.modelo()
        m.cargar()
        // La de otra semana sin fijar se va; la que no tenía `fijado` cuenta como fijada y queda.
        assertEquals(listOf("rem-d1-1"), m.dia.value.sustituciones.keys.sorted())
        assertEquals("Remo en T", m.efectivo(m.dia.value.ejercicio("rem-d1-1")!!).ejercicio.nombre)
    }

    @Test
    fun cerrarElDiaPrimeroVaciaLaCola() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1", iniciada = "2026-10-14T17:30:00Z"))
        b.servidor.cuando("registrar_carga", "\"fila-1\"")
        b.servidor.cuando("finalizar_sesion", "true")
        val m = b.modelo()
        m.restaurarSesion()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        val r = m.cerrarDia("  molestia en el hombro  ")
        assertEquals(ModeloEntreno.ResultadoCierre.CERRADO, r)
        val orden = b.servidor.orden.filter { it == "mypump_registrar_carga" || it == "mypump_finalizar_sesion" }
        assertTrue(orden.last() == "mypump_finalizar_sesion" && "mypump_registrar_carga" in orden)
        val fin = b.servidor.llamadas("finalizar_sesion").first()
        assertTrue(fin["p_notas"]?.comoTexto == "molestia en el hombro" && fin["p_duracion_segundos"] == ValorJson.Numero(1800.0))
        assertTrue(m.dia.value.diaFinalizado && m.hecho(m.dias[0]) && b.sesionesEnDisco["d1"]?.finalizada == true)
        assertEquals(0, b.cola.pendientes())
    }

    @Test
    fun cerrarElDiaConFalseAvisaYConMasDe6hLaDuracionVaNull() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1", iniciada = "2026-10-14T03:00:00Z"))
        b.servidor.cuando("finalizar_sesion", "false")
        val m = b.modelo()
        m.restaurarSesion()
        assertEquals(TiempoEntreno.Cronometro.SinCerrar, m.cronometro())
        assertEquals(ModeloEntreno.ResultadoCierre.FALLO, m.cerrarDia(""))
        assertEquals(ValorJson.Nulo, b.servidor.llamadas("finalizar_sesion").first()["p_duracion_segundos"])
        assertFalse(m.dia.value.diaFinalizado)
    }

    @Test
    fun diaCerradoCargarUnaSeriePreguntaSiSeReabre() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.cacheDeSesion(mapOf("d1" to ModeloEntreno.SesionLocal("ses-1", 5, finalizada = true)))
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1", finalizada = "2026-10-14T17:00:00Z"))
        val m = b.modelo()
        m.restaurarSesion()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        val preguntas = mutableListOf<String>()
        m.confirmarSerie("jal-d1-0", 0) { p ->
            preguntas += p.titulo
            false
        }
        assertTrue(preguntas == listOf("Este día ya lo cerraste") && m.dia.value.diaFinalizado && b.cola.pendientes() == 0)
        m.confirmarSerie("jal-d1-0", 0) { p ->
            preguntas += p.titulo
            true
        }
        assertTrue(!m.dia.value.diaFinalizado && b.sesionesEnDisco["d1"]?.finalizada == false)
        assertEquals("ses-1", b.cola.operaciones().first().payload["sesionId"]?.comoTexto, "la misma sesión")
    }

    @Test
    fun avanzarSemanaMandaElDestinoBorraLasSesionesYRecarga() = enUnHilo { alcance ->
        val b = Banco(alcance)
        // También la de un día que no se mira: si no se borra, queda colgada hasta que se lo abra.
        b.cacheDeSesion(mapOf("d1" to ModeloEntreno.SesionLocal("ses-1", 5), "d3" to ModeloEntreno.SesionLocal("ses-3", 5, finalizada = true)))
        b.servidor.cuando("avanzar_semana", "6")
        b.servidor.cuando("get_rutina_activa", "[${filaRutina(semana = 6)}]")
        val m = b.modelo()
        var avisada: RutinaActiva? = null
        m.alCambiarRutina = { avisada = it }
        assertTrue(m.puedeAvanzar && m.botonAvanzar == "Pasar a Semana 6 →")
        assertEquals(ModeloEntreno.ResultadoAvance.Listo, m.avanzarSemana())
        assertEquals(ValorJson.Numero(6.0), b.servidor.llamadas("avanzar_semana").first()["p_semana_destino"])
        assertTrue(m.semana == 6 && avisada?.semanaActual == 6)
        assertTrue(b.sesionesEnDisco.isEmpty())
    }

    @Test
    fun avanzarSemanaSinRedYRechazado() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.sinRed("avanzar_semana")
        val m = b.modelo()
        assertEquals(ModeloEntreno.ResultadoAvance.Error(SemanaEntreno.errorAvanzar(true)), m.avanzarSemana())
        b.servidor.cuando("avanzar_semana", 400, """{"code":"P0001","message":"no"}""")
        assertEquals(ModeloEntreno.ResultadoAvance.Error(SemanaEntreno.errorAvanzar(false)), m.avanzarSemana())
        b.servidor.cuando("activar_siguiente", "false")
        assertEquals(ModeloEntreno.ResultadoAvance.Error(SemanaEntreno.errorBloqueNuevo(false)), m.empezarBloqueNuevo())
    }

    @Test
    fun comentariosDirectosConAvisoYLeidosOptimistas() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando(
            "get_comentarios",
            """[{"id":"c1","ambito":"ejercicio","referencia_id":"jal-d1-0","referencia_nombre":"Jalón al pecho","autor":"coach","contenido":"bajá el peso","leido_por_cliente":false,"leido_por_coach":true,"created_at":"2026-10-13T12:00:00+00:00"},{"id":"c2","ambito":"general","referencia_id":null,"referencia_nombre":null,"autor":"coach","contenido":"hola","leido_por_cliente":false,"leido_por_coach":true,"created_at":"2026-10-13T12:00:00+00:00"}]""",
        )
        val m = b.modelo()
        m.cargarComentarios()
        assertTrue(m.sinLeerEntreno == 1 && m.sinLeer(m.dias[0]) == 1, "el chat no cuenta en Entreno")
        b.servidor.cuando("agregar_comentario", "null")
        assertFalse(m.comentar("jal-d1-0", "  hice 2 menos  "), "null es que no se guardó")
        b.servidor.cuando("agregar_comentario", "\"c3\"")
        assertTrue(m.comentar("jal-d1-0", "  hice 2 menos  "))
        val enviado = b.servidor.llamadas("agregar_comentario").last()
        assertTrue(enviado["p_contenido"]?.comoTexto == "hice 2 menos" && enviado["p_referencia_nombre"]?.comoTexto == "Jalón al pecho")
        m.marcarLeidos("jal-d1-0")
        assertEquals(0, m.comentarios.value.sinLeer("jal-d1-0"))
        assertEquals("jal-d1-0", b.servidor.llamadas("marcar_leidos_cliente").first()["p_referencia_id"]?.comoTexto)
    }

    @Test
    fun elDescansoSobreviveAlReinicioYRestaurarLoBorra() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        m.ajustarDescanso(15)
        b.reloj.ms = AHORA + 60_000
        val otro = b.modelo()
        otro.cargar()
        assertTrue(otro.descanso.value.visible && otro.descanso.value.descanso?.objetivo == 165.0 && otro.descanso.value.texto == "1:45")
        assertNull(b.descansoEnDisco, "como la web: restaurar lo borra")
        b.reloj.ms = AHORA + 165_000
        assertTrue(otro.tickDescanso())
        b.reloj.ms = AHORA + 167_000
        otro.tickDescanso()
        assertFalse(otro.descanso.value.visible)
    }

    @Test
    fun diaCompletoUnaSolaVez() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        m.cambiarDia("d2")
        m.escribir("pre-d2-0", 0, "reps", "8")
        m.escribir("pre-d2-0", 0, "kg", "80")
        val completo = m.confirmarSerie("pre-d2-0", 0) { true }
        assertNotNull(completo)
        assertTrue(completo!!.pregunta.cuerpo == "Buen trabajo. ¿Querés ir al siguiente día (PIERNA)?" && completo.siguiente?.id == "d3")
        m.reabrir("pre-d2-0")
        assertNull(m.marcarCompleto("pre-d2-0"), "ya se mostró en este día")
    }

    @Test
    fun laSesionEnVueloDeOtroDiaNoSeReusa() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.regla("iniciar_sesion") { p ->
            if (p["p_dia_id"]?.comoTexto == "d1") {
                demora(150)
                200 to "\"ses-d1\""
            } else {
                200 to "\"ses-d2\""
            }
        }
        val m = b.modelo()
        val primera = async { m.asegurarSesion() }
        delay(20)
        m.cambiarDia("d2")
        val segunda = m.asegurarSesion()
        primera.await()
        assertTrue(segunda == "ses-d2" && m.dia.value.sesionId == "ses-d2")
        assertNull(b.sesionesEnDisco["d1"]?.sesionId, "la del día 1 llegó tarde: no se guarda como la del día que se mira")
    }

    @Test
    fun otroCargarNoBorraElDescansoEnCurso() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        m.cargar()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        m.cargar()
        assertTrue(m.descanso.value.visible && b.descansoEnDisco != null)
    }

    @Test
    fun demoNoEscribeNiTocaLaRed() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo(token = null)
        m.cargar()
        m.escribir("jal-d1-0", 0, "reps", "10")
        m.escribir("jal-d1-0", 0, "kg", "60")
        m.confirmarSerie("jal-d1-0", 0) { true }
        assertTrue(m.dia.value.ejercicios["jal-d1-0"]?.series?.get(0)?.confirmada == true && m.descanso.value.visible)
        assertTrue(b.servidor.orden.isEmpty())
        assertFalse(m.puedeAvanzar)
    }
}

/** Lo que dejó la app vieja. */
class EntrenoLegadoTest {
    @Test
    fun clavesCrudasDelLocalStorage() {
        val l = LegadoEntreno.desdeAlmacenamiento(
            mapOf(
                "mypump_sesion_tok_d1" to "ses-vieja", "mypump_sesion_tok_d1_semana" to "5", "mypump_sesion_tok_d1_start" to "1784570400000",
                "mypump_sesion_tok_d1_finalizada" to "1", "mypump_sesion_tok_b2d3_start" to "1784570500000",
                "mypump_sesion_otro_d1" to "de-otra-cuenta", "mypump_rest_tok" to """{"endsAt":1792000830000,"target":90,"autoCloseAt":1792000832000}""",
                "mypump_dia_visualizado_rut-prueba" to "d2",
                "mypump_exercise_swaps_rut-prueba" to """{"jal-d1-0":{"current":{"nombre":"Dominadas"},"fijado":true}}""",
            ),
            token = "tok", rutinaId = "rut-prueba",
        )
        assertEquals(
            listOf(
                LegadoEntreno.SesionDia("b2d3", inicio = 1_784_570_500_000.0),
                LegadoEntreno.SesionDia("d1", sesionId = "ses-vieja", semana = 5, inicio = JULIO, finalizada = true),
            ),
            l.sesiones,
        )
        assertEquals(Descanso.Guardado(1_792_000_830_000.0, 90.0, 1_792_000_832_000.0), l.descanso)
        assertTrue(l.diaVisualizado == "d2" && l.sustituciones?.get("jal-d1-0")?.get("current")?.get("nombre")?.comoTexto == "Dominadas")
    }

    @Test
    fun unaSesionViejaQueElServidorArchivoSeDescarta() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_sesion_dia", "[]")
        b.disco.guardar(
            ModeloEntreno.Archivo.LEGADO,
            ValorJson.objeto(
                "dias" to ValorJson.objeto(
                    "d1" to ValorJson.objeto(
                        "sesionId" to texto("ses-julio"), "_semana" to numero(5), "_start" to numero(JULIO), "_finalizada" to ValorJson.Booleano(true),
                    ),
                ),
                "descanso" to ValorJson.objeto("endsAt" to numero(AHORA + 30_000), "target" to numero(90), "autoCloseAt" to numero(AHORA + 32_000)),
                "diaVisualizado" to texto("d1"),
            ),
        )
        val m = b.modelo()
        m.cargar()
        assertTrue(m.aplicarLegadoDelDisco())
        assertTrue(m.dia.value.sesionId == null && !m.dia.value.diaFinalizado, "nada de sesiones fantasma")
        assertTrue(m.descanso.value.visible && m.descanso.value.texto == "0:30")
        assertNull(b.disco.leer(ModeloEntreno.Archivo.LEGADO))
        assertFalse(m.aplicarLegadoDelDisco(), "no se aplica dos veces")
    }

    /**
     * De punta a punta: lo que ESCRIBE la migración ([EjecutorLegado.guardarEntreno]) es lo que LEE Entreno, y el descanso
     * que venía corriendo sigue después de pasar al día que se estaba viendo. Gemelo de loQueDejaLaMigracionSeLeeEntero
     * de iOS; lo destapó la prueba de punta a punta en el emulador (scripts/nativa/emu-migracion.sh).
     */
    @Test
    fun loQueDejaLaMigracionSeLeeEntero() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1"))
        EjecutorLegado.guardarEntreno(
            EntrenoLegado(
                sesiones = mapOf("d1" to SesionLegada(sesionId = "ses-1", semana = 5, start = AHORA - 600_000)),
                descanso = DescansoLegado(endsAt = AHORA + 30_000, target = 90.0, autoCloseAt = AHORA + 32_000),
                diaVisualizado = mapOf("otra-rutina" to "d9", "rut-prueba" to "d2"),
            ),
            b.disco,
        )
        val l = LegadoEntreno.leer(b.disco, "tok-prueba", "rut-prueba")
        assertEquals(listOf(LegadoEntreno.SesionDia("d1", sesionId = "ses-1", semana = 5, inicio = AHORA - 600_000)), l?.sesiones)
        assertEquals(Descanso.Guardado(AHORA + 30_000, 90.0, AHORA + 32_000), l?.descanso)
        assertEquals("d2", l?.diaVisualizado)
        val m = b.modelo()
        assertTrue(m.aplicarLegadoDelDisco())
        assertEquals("ses-1", b.sesionesEnDisco["d1"]?.sesionId)
        assertEquals(AHORA - 600_000, b.sesionesEnDisco["d1"]?.inicio)
        assertEquals("d2", m.dia.value.dia.id, "el día que se estaba viendo")
        // El descanso que venía corriendo sigue: el cambio al día visto va antes (cambiar de día lo detiene).
        assertTrue(m.descanso.value.visible && m.descanso.value.texto == "0:30", "${m.descanso.value}")
    }

    @Test
    fun laSesionViejaConfirmadaSeRetoma() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_sesion_dia", sesionJson("ses-1"))
        b.servidor.cuando(
            "get_registros_sesion",
            """[{"ejercicio_id":"jal-d1-0","serie_numero":1,"peso_kg":60,"reps_realizadas":10,"rir_real":0,"notas":"Neutro","ejercicio_nombre":"Jalón al pecho"}]""",
        )
        val m = b.modelo()
        m.aplicarLegado(LegadoEntreno(sesiones = listOf(LegadoEntreno.SesionDia("d1", sesionId = "ses-1", semana = 5, inicio = AHORA - 600_000))))
        assertTrue(m.dia.value.sesionId == "ses-1" && m.inicioSesion.value == AHORA - 600_000)
        val e = m.dia.value.ejercicios["jal-d1-0"]
        assertTrue(e?.series?.get(0)?.confirmada == true && e.variante == "Neutro")
    }
}
