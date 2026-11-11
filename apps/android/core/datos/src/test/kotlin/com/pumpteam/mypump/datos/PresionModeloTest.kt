package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.Presion
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La cola y el recorrido de «Presión arterial» contra el doble que sigue el contrato. Gemelo de PresionModeloTests.swift. */
class PresionModeloTest {
    private val token = "tk-prueba-presion"
    private fun raiz() = Files.createTempDirectory("presion").toFile()

    /** El modelo y lo que dejó para hacer en segundo plano. */
    private class Armado(val m: ModeloPresion, val raiz: File, val fondo: MutableList<suspend () -> Unit>) {
        /** Deja pasar lo que quedó drenando en segundo plano. */
        suspend fun asentar() {
            while (fondo.isNotEmpty()) fondo.removeAt(0)()
            m.drenar()
        }
    }

    private fun armar(d: DoblePresion, r: File = raiz(), ahora: () -> Instant = { Instant.now() }): Armado {
        val fondo = mutableListOf<suspend () -> Unit>()
        return Armado(ModeloPresion(ClienteRpc(transporte = d), token, Disco(r, token), ahora = ahora, version = { "2.3.0" }, lanzar = { fondo += it }), r, fondo)
    }

    private fun json(s: String) = ValorJson.parsear(s)
    private fun si(x: Boolean) = ValorJson.Booleano(x)
    private fun tomasDe(s: Map<String, ValorJson>?) = (s?.get("tomas") as? ValorJson.Lista)?.elementos ?: emptyList()

    // ── Palanca ──

    @Test fun palancaDeFabricaApagadaYSeRecuerda() {
        assertFalse(PalancaRemota.deFabrica.presionApp)
        assertFalse(PalancaRemota.desde(ValorJson.objeto()).presionApp)
        assertFalse(PalancaRemota.desde(ValorJson.objeto("presion_app" to ValorJson.Texto("true"))).presionApp)
        assertTrue(PalancaRemota.desde(ValorJson.objeto("presion_app" to si(true))).presionApp)
        val a = armar(DoblePresion.escenario("serie0"))
        assertFalse(a.m.palancaRecordada)
        a.m.recordarPalanca(true)
        assertTrue(armar(DoblePresion.escenario("serie0"), a.raiz).m.palancaRecordada)
        a.m.recordarPalanca(false)
        assertFalse(armar(DoblePresion.escenario("serie0"), a.raiz).m.palancaRecordada)
    }

    @Test fun palancaApagadaNoLlamaANada(): Unit = runBlocking {
        val d = DoblePresion.escenario("apagado")
        assertEquals(false, PalancaRemota.leer(ClienteRpc(transporte = d))?.presionApp)
        val a = armar(d)
        // Lo que hace `ModeloApp.sincronizarPresion` con la palanca apagada.
        a.m.apagar()
        assertFalse(a.m.habilitado)
        assertEquals(ModeloPresion.Salida.ERROR, a.m.guardarMedida(35.0))
        assertEquals(ModeloPresion.Salida.ERROR, a.m.guardarAparato(Presion.Aparato(tipo = "brazo")))
        a.m.marcarSintoma(listOf("palpitaciones"), null)
        a.asentar()
        assertTrue(d.llamadasPresion.isEmpty())
    }

    @Test fun sinElServidorNuevoONoHabilitadoNoSeVeNada(): Unit = runBlocking {
        val m = armar(DoblePresion.escenario("sinServidor")).m
        m.refrescar()
        assertFalse(m.habilitado)
        val m2 = armar(DoblePresion.escenario("serie0").apply { habilitado = false }).m
        m2.refrescar()
        assertFalse(m2.habilitado)
        val m3 = armar(DoblePresion.escenario("serie0").apply { tokenCaido = true }).m
        m3.refrescar()
        assertFalse(m3.habilitado)
    }

    /** El contrato: un 404 o PGRST202 no borra la cola. */
    @Test fun sinElServidorNuevoLaColaSeConserva(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        d.sinRed = true
        a.m.marcarSintoma(listOf("palpitaciones"), null)
        a.asentar()
        d.sinRed = false
        d.sinFuncion = true
        a.m.drenar()
        assertFalse(a.m.habilitado)
        assertEquals(1, a.m.enCola)
        // Otro arranque, ya con el servidor: sale.
        d.sinFuncion = false
        val b = armar(d, a.raiz)
        assertEquals(1, b.m.enCola)
        b.m.refrescar()
        b.m.drenar()
        assertEquals(0, b.m.enCola)
        assertEquals(1, d.sintomas.size)
        // Pasados 30 días sin poder salir, se descarta.
        d.sinRed = true
        b.m.marcarSintoma(listOf("palpitaciones"), null)
        b.asentar()
        assertEquals(1, b.m.enCola)
        assertEquals(1, armar(d, a.raiz, ahora = { Instant.now().plusSeconds(29L * 86_400) }).m.enCola)
        assertEquals(0, armar(d, a.raiz, ahora = { Instant.now().plusSeconds(31L * 86_400) }).m.enCola)
    }

    // ── Aparato y medida ──

    @Test fun aparatoYMedida(): Unit = runBlocking {
        val d = DoblePresion.escenario("vacio")
        val m = armar(d).m
        m.refrescar()
        assertTrue(m.habilitado)
        assertNull(m.estado.value?.aparato)
        assertEquals(ModeloPresion.Salida.ERROR, m.guardarMedida(19.9))
        assertEquals(0, d.cuantas("mypump_presion_medida"))
        assertEquals(ModeloPresion.Salida.OK, m.guardarMedida(35.44))
        assertEquals(35.4, m.estado.value?.circunferenciaBrazoCm)
        assertEquals(ModeloPresion.Salida.OK, m.guardarAparato(Presion.Aparato(tipo = "brazo", marca = " Marca ", modelo = "", manguitoMinCm = 22.0, manguitoMaxCm = 42.0)))
        assertEquals("brazo", m.estado.value?.aparato?.tipo)
        assertEquals("Marca", m.estado.value?.aparato?.marca)
        assertNull(m.estado.value?.aparato?.modelo)
        assertEquals(true, Presion.manguitoCalza(m.estado.value?.circunferenciaBrazoCm, m.estado.value?.aparato))
        d.sinRed = true
        assertEquals(ModeloPresion.Salida.SIN_SENAL, m.guardarMedida(36.0))
    }

    // ── Sesión ──

    @Test fun tomaComunCompletaLaSerieDeADia(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie2")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        assertEquals(1, m.estado.value?.serie?.faltan)
        assertEquals(2, m.estado.value?.serie?.dias?.size)
        m.empezar("estandar", m.estado.value?.serie?.id, "izq", "anotar")
        m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true, temporizadorSalteado = false)) }
        val ev = m.anotarToma(124, 78, 62, false)
        assertEquals(Presion.Paso.LISTO, ev?.paso)
        assertEquals(true, ev?.cuenta)
        a.asentar()
        assertEquals(0, m.enCola)
        assertEquals(0, m.estado.value?.serie?.faltan)
        assertEquals(124, m.estado.value?.sesiones?.first()?.tomas?.first()?.sis)
        val p = d.recibidas.last()
        assertEquals("android", p["plataforma"]?.comoTexto)
        assertEquals("2.3.0", p["app_version"]?.comoTexto)
        assertEquals("ninguno", p["texto_alumno"]?.comoTexto)
        assertEquals(DoblePresion.ID_SERIE, p["serie_id"]?.comoTexto)
        assertEquals(si(true), p["reposo_cumplido"])
        assertTrue(p["previo"] is ValorJson.Objeto)
        assertNotNull(p["tomas"])
        assertFalse(p["zona_horaria"]?.comoTexto.isNullOrEmpty())
        assertTrue(Regex("\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\dZ").matches(p["inicio"]?.comoTexto ?: ""))
        m.terminar()
        assertNull(m.enCurso)
    }

    @Test fun valorImposibleNoSeAnota(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        a.m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        assertNull(a.m.anotarToma(300, 80, 60, false))
        assertNull(a.m.anotarToma(100, 95, 60, false))
        assertEquals(true, a.m.enCurso?.sesion?.tomas?.isEmpty())
        a.asentar()
        assertEquals(0, d.cuantas("mypump_presion_sesion"))
    }

    @Test fun tomaAltaPideRepetirYConfirmada(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true)) }
        assertEquals(Presion.Paso.REPETIR, m.anotarToma(160, 100, 70, false, confirmada = true)?.paso)
        a.asentar()
        assertEquals("alta", m.estado.value?.pendiente?.nivel)
        val ev = m.anotarToma(164, 101, 72, false, confirmada = true)
        assertEquals(Presion.Paso.LISTO, ev?.paso)
        assertEquals(listOf("alta_toma_160_100"), ev?.reglas)
        a.asentar()
        assertNull(m.estado.value?.pendiente)
        assertEquals(1, d.sesiones.size)
        assertEquals(2, m.estado.value?.sesiones?.first()?.tomas?.size)
    }

    @Test fun urgenciaListaYGuardia(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        assertEquals(Presion.Paso.REPETIR_CON_LISTA, m.anotarToma(182, 120, 80, false, confirmada = true)?.paso)
        // Sin contestar no es «no».
        assertNull(m.enCurso?.sesion?.listaEspera)
        for (c in Presion.alarma.dropLast(1)) assertEquals(Presion.Paso.REPETIR_CON_LISTA, m.responderLista(c, false)?.paso)
        assertNull(m.enCurso?.sesion?.listaEspera)
        assertEquals(Presion.Paso.REPETIR_CON_LISTA, m.responderLista(Presion.alarma.last(), false)?.paso)
        assertEquals("no", m.enCurso?.sesion?.listaEspera)
        // Todos en No y la repetición sigue alta: guardia por presión.
        val ev = m.anotarToma(181, 110, 82, false, confirmada = true)
        assertEquals(Presion.Paso.GUARDIA_PRESION, ev?.paso)
        assertEquals("guardia_presion", ev?.texto)
        a.asentar()
        assertEquals("guardia_presion", d.recibidas.last()["texto_alumno"]?.comoTexto)
        assertEquals(1, d.sesiones.size)

        // Un Sí en la espera: guardia por síntomas en el acto, y aunque no haya red.
        val d2 = DoblePresion.escenario("serie0")
        val m2 = armar(d2).m
        m2.refrescar()
        d2.sinRed = true
        m2.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        assertEquals(Presion.Paso.REPETIR_CON_LISTA, m2.anotarToma(182, 120, 80, false, confirmada = true)?.paso)
        val ev2 = m2.responderLista("dolor_pecho", true)
        assertEquals(Presion.Paso.GUARDIA_SINTOMAS, ev2?.paso)
        assertEquals(true, ev2?.reglas?.contains("sintoma_alarma_en_espera"))
        assertEquals("si", m2.enCurso?.sesion?.listaEspera)
        assertEquals(1, m2.enCola)
    }

    // ── Cola ──

    @Test fun sinRedQuedaEnColaYSaleAlReintentar(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        d.sinRed = true
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true)) }
        assertEquals(Presion.Paso.LISTO, m.anotarToma(124, 78, 62, false)?.paso)
        assertFalse(m.marcarSintoma(listOf("palpitaciones"), " hoy "))
        a.asentar()
        assertEquals(2, m.enCola)
        assertTrue(d.sesiones.isEmpty())
        // Se cerró la app: otro modelo, la misma carpeta, todavía sin red. Arranca de lo guardado.
        val m2 = armar(d, a.raiz).m
        m2.refrescar()
        assertTrue(m2.habilitado)
        assertEquals(2, m2.enCola)
        assertEquals(1, m2.enCurso?.sesion?.tomas?.size)
        m2.drenar()
        assertEquals(2, m2.enCola)
        d.sinRed = false
        m2.drenar()
        assertEquals(0, m2.enCola)
        assertEquals(1, d.sesiones.size)
        assertEquals(1, d.sintomas.size)
        assertEquals("hoy", d.sintomas.first()["nota"]?.comoTexto)
        assertEquals("boton", d.sintomas.first()["contexto"]?.comoTexto)
        // En orden: primero la sesión, después el síntoma.
        val escrituras = d.llamadasPresion.filter { it == "mypump_presion_sesion" || it == "mypump_presion_sintoma" }
        assertEquals(listOf("mypump_presion_sesion", "mypump_presion_sintoma"), escrituras.takeLast(2))
        assertEquals(2, m2.estado.value?.serie?.faltan)
    }

    @Test fun cincoXXY429NoGastanElEnvio(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        d.proximas += listOf(503, 429, 0)
        a.m.marcarSintoma(listOf("mareo_al_pararse"), null)
        a.asentar()
        assertEquals(1, a.m.enCola)
        // `asentar` ya gastó el 503 y el 429; queda el corte de red.
        a.m.drenar()
        assertEquals(1, a.m.enCola)
        assertTrue(d.sintomas.isEmpty())
        a.m.drenar()
        assertEquals(0, a.m.enCola)
        assertEquals(1, d.sintomas.size)
        assertEquals(4, d.cuantas("mypump_presion_sintoma"))
    }

    @Test fun cuatroXXYOkFalseSeDescartanYRefrescan(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        d.proximas += 400
        val antes = d.cuantas("mypump_presion_get")
        m.marcarSintoma(listOf("palpitaciones"), null)
        a.asentar()
        assertEquals(0, m.enCola)
        assertTrue(d.sintomas.isEmpty())
        assertEquals(antes + 1, d.cuantas("mypump_presion_get"))
        assertTrue(m.habilitado)

        d.proximoError = "serie"
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        m.anotarToma(124, 78, 62, false)
        m.marcarSintoma(listOf("vomitos_diarrea"), null)
        a.asentar()
        // La sesión rechazada se descarta y lo que sigue en la cola sale igual.
        assertEquals(0, m.enCola)
        assertTrue(d.sesiones.isEmpty())
        assertEquals(1, d.sintomas.size)
        assertEquals(antes + 2, d.cuantas("mypump_presion_get"))
    }

    @Test fun idempotenteAunqueSeCorteDespuesDeGuardar(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true)) }
        m.anotarToma(162, 96, 70, false, confirmada = true)
        a.asentar()
        assertEquals(1, d.sesiones.size)
        // La segunda toma viaja con la sesión entera: el servidor no duplica la sesión ni pisa la primera toma.
        m.anotarToma(150, 92, 68, true, confirmada = false)
        a.asentar()
        assertEquals(1, d.sesiones.size)
        assertEquals(2, d.cuantas("mypump_presion_sesion"))
        val tomas = tomasDe(d.sesiones.first())
        assertEquals(2, tomas.size)
        assertEquals(162.0, tomas.first()["sis"]?.comoNumero)
        assertEquals(d.recibidas.first()["id"], d.recibidas.last()["id"])
        // El mismo síntoma mandado dos veces queda una sola vez.
        val s = SintomaPresion("55555555-5555-4555-8555-555555555555", "2026-11-10T10:00:00Z", "UTC", "boton", null, listOf("palpitaciones"), null, null)
        val c = ClienteRpc(transporte = d)
        repeat(2) { c.llamar("mypump_presion_sintoma", mapOf("p_token" to ValorJson.Texto(token), "p_sintoma" to s.aValor())) }
        assertEquals(1, d.sintomas.size)
    }

    @Test fun unaVersionMasNuevaDeLaSesionReemplazaALaQueEspera(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        d.sinRed = true
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        m.anotarToma(165, 96, 70, false, confirmada = true)
        m.anotarToma(150, 92, 68, false)
        a.asentar()
        assertEquals(1, m.enCola)
        d.sinRed = false
        m.drenar()
        assertEquals(1, d.sesiones.size)
        assertEquals(2, tomasDe(d.sesiones.first()).size)
    }

    @Test fun laSesionEnCursoSeRetomaElMismoDiaYNoAlOtro(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        a.m.empezar("estandar", DoblePresion.ID_SERIE, "der", "reposo")
        val fin = System.currentTimeMillis() + 300_000
        a.m.cambiar { it.copy(etapa = "espera", finTemporizador = fin, lista = mapOf("confusion" to false), variante = "sentado_parado") }
        val m2 = armar(d, a.raiz).m
        assertEquals("espera", m2.enCurso?.etapa)
        assertEquals("der", m2.enCurso?.sesion?.brazo)
        assertEquals(fin, m2.enCurso?.finTemporizador)
        assertEquals(a.m.enCurso, m2.enCurso)
        val manana = armar(d, a.raiz, ahora = { Instant.now().plusSeconds(36 * 3600) }).m
        assertNull(manana.enCurso)
    }

    @Test fun retomarLaRepeticionQuePideElServidor(): Unit = runBlocking {
        val d = DoblePresion.escenario("pendienteUrgencia")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        val p = m.estado.value?.pendiente
        assertEquals("urgencia", p?.nivel)
        m.retomar(p!!, "anotar")
        assertEquals(1, m.enCurso?.sesion?.tomas?.size)
        assertEquals(p.sesionId, m.enCurso?.sesion?.id)
        assertEquals(Presion.Paso.LISTO, m.anotarToma(150, 90, 70, false)?.paso)
        a.asentar()
        assertNull(m.estado.value?.pendiente)
        // El mismo `id`, con la toma nueva; lo que no se sabe viaja en null y el servidor conserva lo que tenía.
        assertEquals(p.sesionId, d.recibidas.last()["id"]?.comoTexto)
        assertEquals(ValorJson.Nulo, d.recibidas.last()["previo"])
        assertEquals(ValorJson.Nulo, d.recibidas.last()["reposo_cumplido"])
        // La lista del recordatorio viaja como síntoma.
        assertFalse(m.marcarSintoma(emptyList(), null, contexto = "recordatorio_180_120", sesionId = p.sesionId, sinSintomasEnLista = true))
        assertTrue(m.marcarSintoma(listOf("confusion"), null, contexto = "recordatorio_180_120", sesionId = p.sesionId, sinSintomasEnLista = false))
        a.asentar()
        assertEquals(2, d.sintomas.size)
        assertEquals(si(true), d.sintomas.first()["sin_sintomas_en_lista"])
    }

    // ── Tarjeta de arriba y vencimiento ──

    @Test fun tarjetaLosEstadosEnElOrdenDelContrato(): Unit = runBlocking {
        suspend fun tarjeta(escenario: String): ModeloPresion.Tarjeta? {
            val m = armar(DoblePresion.escenario(escenario)).m
            m.refrescar()
            return m.tarjeta
        }
        assertNull(tarjeta("sinServidor"))
        assertNull(tarjeta("sinSerie"))
        assertNull(tarjeta("vacio"), "sin serie abierta no hay tarjeta aunque falte el aparato")
        assertEquals(ModeloPresion.Tarjeta.Toma(0, 3, 3), tarjeta("serie0"))
        assertEquals(ModeloPresion.Tarjeta.Toma(2, 3, 1), tarjeta("serie2"))
        assertEquals(ModeloPresion.Tarjeta.Preparar, tarjeta("medirDeNuevo"))
        assertEquals(ModeloPresion.Tarjeta.HoyListo(2, 3), tarjeta("hoyListo"))
        assertEquals(ModeloPresion.Tarjeta.Repetir, tarjeta("pendienteUrgencia"))
        assertEquals(ModeloPresion.Tarjeta.Repetir, tarjeta("pendienteAlta"))
        // Serie abierta sin aparato, o con reloj: primero preparar.
        val d = DoblePresion.escenario("serie0")
        d.aparato = null
        val m = armar(d).m
        m.refrescar()
        assertEquals(ModeloPresion.Tarjeta.Preparar, m.tarjeta)
        d.aparato = mutableMapOf("id" to ValorJson.Texto("a"), "tipo" to ValorJson.Texto("reloj_anillo_otro"))
        m.refrescar()
        assertEquals(ModeloPresion.Tarjeta.Preparar, m.tarjeta)
    }

    @Test fun tarjetaSigueALoAnotadoSinSenal(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        d.sinRed = true
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true)) }
        assertEquals(Presion.Paso.LISTO, m.anotarToma(124, 78, 62, false)?.paso)
        a.asentar()
        assertEquals(3, m.estado.value?.serie?.faltan, "el servidor todavía no se enteró")
        assertTrue(m.hoyListo)
        assertEquals(ModeloPresion.Tarjeta.HoyListo(1, 3), m.tarjeta)
        m.terminar()
        assertEquals(ModeloPresion.Tarjeta.HoyListo(1, 3), m.tarjeta)
        // Una toma que pide repetición: la tarjeta lleva a repetir, con la sesión todavía en el teléfono.
        val m2 = armar(DoblePresion.escenario("serie0")).m
        m2.refrescar()
        m2.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        assertEquals(Presion.Paso.REPETIR, m2.anotarToma(164, 98, 70, false, confirmada = true)?.paso)
        assertEquals(ModeloPresion.Tarjeta.Repetir, m2.tarjeta)
        assertEquals("alta", m2.pendiente?.nivel)
    }

    @Test fun laColaVenceALos30Dias(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val r = raiz()
        val hace31 = Instant.now().minusSeconds(31L * 86_400)
        val viejo = armar(d, r) { hace31 }
        viejo.m.refrescar()
        d.sinRed = true
        viejo.m.marcarSintoma(listOf("palpitaciones"), null)
        viejo.asentar()
        assertEquals(1, viejo.m.enCola)
        // A los 29 días sigue; a los 31, ya no.
        val hace2 = Instant.now().minusSeconds(2L * 86_400)
        assertEquals(1, armar(d, r) { hace2 }.m.enCola)
        assertEquals(0, armar(d, r).m.enCola)
    }

    @Test fun laRepeticionRetomadaViajaConElMismoIdYSinInventarLasPrevias(): Unit = runBlocking {
        val d = DoblePresion.escenario("pendienteAlta")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        val p = m.pendiente!!
        m.retomar(p, "anotar")
        assertEquals(Presion.Paso.LISTO, m.anotarToma(150, 90, 70, false)?.paso)
        a.asentar()
        val enviada = d.recibidas.last()
        assertEquals(p.sesionId, enviada["id"]?.comoTexto)
        assertEquals(ValorJson.Nulo, enviada["previo"])
        assertEquals(ValorJson.Nulo, enviada["reposo_cumplido"])
        assertEquals(2, (enviada["tomas"] as ValorJson.Lista).elementos.size)
        assertNull(m.estado.value?.pendiente)
        // Una sesión común sí manda sus previas.
        val d2 = DoblePresion.escenario("serie0")
        val a2 = armar(d2)
        a2.m.refrescar()
        a2.m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        a2.m.anotarToma(124, 78, 62, false)
        a2.asentar()
        assertEquals(si(false), d2.recibidas.last()["previo"]?.get("cafeina"))
    }

    // ── Revisión del 11-nov ──

    /** Punto 1: un síntoma antes de la primera toma no lleva el id de una sesión que nunca viajó (el servidor lo rechaza). */
    @Test fun sintomaAntesDeLaPrimeraTomaViajaSinSesion(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        a.m.empezar("estandar", DoblePresion.ID_SERIE, null, "reposo")
        assertNull(a.m.sesionParaSintoma)
        val r = a.m.marcarSintomaBoton(listOf("palpitaciones"), null)
        assertNull(r.evaluacion)
        assertFalse(r.alarma)
        // «Me mareé» en la ortostática sin ninguna toma: también suelto.
        a.m.empezar("ortostatica", DoblePresion.ID_SERIE, "izq", "guiaEspera", variante = "sentado_parado")
        assertEquals(Presion.Paso.LISTO, a.m.meMaree()?.paso)
        a.asentar()
        assertEquals(2, d.sintomas.size)
        assertTrue(d.sintomas.all { (it["sesion_id"] ?: ValorJson.Nulo) == ValorJson.Nulo })
        assertEquals("mareo_al_pararse", (d.sintomas.last()["codigos"] as ValorJson.Lista).elementos.single().comoTexto)
        assertEquals(0, d.cuantas("mypump_presion_sesion"))
        // Con una toma ya anotada, sí lleva el id.
        a.m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        a.m.anotarToma(124, 78, 62, false)
        val id = a.m.enCurso!!.sesion.id
        assertEquals(id, a.m.sesionParaSintoma)
        a.m.marcarSintomaBoton(listOf("vomitos_diarrea"), null)
        a.asentar()
        assertEquals(id, d.sintomas.last()["sesion_id"]?.comoTexto)
    }

    /** Punto 2: la toma con el pulso o la alta fuera de lo esperado se guarda antes de la hoja de síntomas. */
    @Test fun tomaFueraDeLoEsperadoSeGuardaAntesDeLaHoja(): Unit = runBlocking {
        assertTrue(ModeloPresion.pideSintomas(130, 120))
        assertTrue(ModeloPresion.pideSintomas(130, 40))
        assertTrue(ModeloPresion.pideSintomas(89, 70))
        assertFalse(ModeloPresion.pideSintomas(90, 41))
        assertFalse(ModeloPresion.pideSintomas(150, 119))
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        a.m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        a.m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true, temporizadorSalteado = false)) }
        assertNotNull(a.m.anotarToma(118, 76, 125, false))
        // Ya está en disco y en la cola antes de abrir la hoja: si cierra la app, la toma quedó.
        a.m.cambiar { it.copy(etapa = "sintomas") }
        val reabierto = armar(d, a.raiz).m
        assertEquals(1, reabierto.enCola)
        assertEquals(1, reabierto.enCurso?.sesion?.tomas?.size)
        assertEquals("sintomas", reabierto.enCurso?.etapa)
        // Al contestar, se suman a la sesión y la regla decide: pulso de 120 o más con palpitaciones es guardia.
        assertEquals(Presion.Paso.GUARDIA_SINTOMAS, a.m.sumarSintomas(listOf("palpitaciones"))?.paso)
        a.asentar()
        assertEquals(1, d.sesiones.size)
        assertEquals(listOf("palpitaciones"), (d.recibidas.last()["sintomas"] as ValorJson.Lista).elementos.map { it.comoTexto })
        assertEquals("guardia_sintomas", d.recibidas.last()["texto_alumno"]?.comoTexto)
        // Sin síntomas marcados, sigue lo que dice la toma.
        a.m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        a.m.anotarToma(118, 76, 125, false)
        assertEquals(Presion.Paso.LISTO, a.m.sumarSintomas(emptyList())?.paso)
    }

    /** Punto 3: «Me mareé» con pulso de 120 o más es guardia por síntomas, no la pantalla de mareo. */
    @Test fun meMareeConPulsoAltoEsGuardia(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        a.m.refrescar()
        a.m.empezar("ortostatica", DoblePresion.ID_SERIE, "izq", "guiaAnotar", variante = "sentado_parado")
        a.m.anotarToma(124, 78, 125, false, posicion = "sentado")
        assertEquals(Presion.Paso.GUARDIA_SINTOMAS, a.m.meMaree()?.paso)
        a.asentar()
        assertEquals(listOf("mareo_al_pararse"), (d.recibidas.last()["sintomas"] as ValorJson.Lista).elementos.map { it.comoTexto })
        // Con el pulso común, la pantalla de mareo de siempre.
        a.m.empezar("ortostatica", DoblePresion.ID_SERIE, "izq", "guiaAnotar", variante = "sentado_parado")
        a.m.anotarToma(124, 78, 70, false, posicion = "sentado")
        assertTrue(a.m.meMaree()?.paso != Presion.Paso.GUARDIA_SINTOMAS)
    }

    /** Punto 4: «Marcar un síntoma» con una sesión con tomas lo suma a la sesión y la regla decide el paso. */
    @Test fun marcarSintomaConSesionEnCursoLoSumaYRutea(): Unit = runBlocking {
        val d = DoblePresion.escenario("serie0")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        m.empezar("estandar", DoblePresion.ID_SERIE, null, "espera")
        m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = true)) }
        assertEquals(Presion.Paso.REPETIR, m.anotarToma(160, 100, 70, false, confirmada = true)?.paso)
        val id = m.enCurso!!.sesion.id
        val r = m.marcarSintomaBoton(listOf("palpitaciones"), " me late fuerte ")
        assertFalse(r.alarma)
        assertEquals(Presion.Paso.REPETIR, r.evaluacion?.paso)
        assertEquals(listOf("palpitaciones"), m.enCurso?.sesion?.sintomas)
        assertEquals("me late fuerte", m.enCurso?.sesion?.nota)
        val g = m.marcarSintomaBoton(listOf("dolor_pecho"), null)
        assertTrue(g.alarma)
        assertEquals(Presion.Paso.GUARDIA_SINTOMAS, g.evaluacion?.paso)
        a.asentar()
        assertEquals(2, d.sintomas.size)
        assertTrue(d.sintomas.all { it["sesion_id"]?.comoTexto == id })
        assertEquals(listOf("palpitaciones", "dolor_pecho"), (d.recibidas.last()["sintomas"] as ValorJson.Lista).elementos.map { it.comoTexto })
        // Con la sesión ya en guardia o cerrada (la pantalla dice que no está abierta), viaja suelto y no se suma.
        val suelto = m.marcarSintomaBoton(listOf("vomitos_diarrea"), null, enSesion = false)
        assertNull(suelto.evaluacion)
        a.asentar()
        assertEquals(ValorJson.Nulo, d.sintomas.last()["sesion_id"] ?: ValorJson.Nulo)
        assertFalse("vomitos_diarrea" in (m.enCurso?.sesion?.sintomas ?: emptyList()))
    }

    /** Punto 6: una repetición retomada no dice «Esta no cuenta» ni lo manda en texto_alumno. */
    @Test fun laRepeticionRetomadaNoDiceQueNoCuenta(): Unit = runBlocking {
        val d = DoblePresion.escenario("pendienteAlta")
        val a = armar(d)
        val m = a.m
        m.refrescar()
        m.retomar(m.pendiente!!, "anotar")
        val ev = m.anotarToma(150, 90, 70, false)
        assertEquals(Presion.Paso.LISTO, ev?.paso)
        assertEquals("toma_no_cuenta", ev?.texto)
        assertFalse(m.noCuenta(ev))
        a.asentar()
        assertEquals("ninguno", d.recibidas.last()["texto_alumno"]?.comoTexto)
        // Una sesión común con el reposo salteado sí lo dice.
        val d2 = DoblePresion.escenario("serie0")
        val a2 = armar(d2)
        a2.m.refrescar()
        a2.m.empezar("estandar", DoblePresion.ID_SERIE, null, "anotar")
        a2.m.cambiar { it.copy(sesion = it.sesion.copy(reposoCumplido = false, temporizadorSalteado = true)) }
        val ev2 = a2.m.anotarToma(124, 78, 62, false)
        assertTrue(a2.m.noCuenta(ev2))
        a2.asentar()
        assertEquals("toma_no_cuenta", d2.recibidas.last()["texto_alumno"]?.comoTexto)
    }

    /** Punto 7: sin la sesión guardada se refresca antes de anotar; si sigue sin estar, no se retoma (toma nueva normal). */
    @Test fun retomarSinLaSesionGuardadaRefrescaAntes(): Unit = runBlocking {
        val d = DoblePresion.escenario("pendienteAlta")
        val a = armar(d)
        a.m.refrescar()
        val p = a.m.estado.value!!.pendiente!!
        // Lo que se guardó sin la lista de sesiones (por ejemplo, de un arranque sin red).
        val disco = Disco(a.raiz, token)
        val guardado = ValorJson.desde(disco.leer("presion-estado.json")!!) as ValorJson.Objeto
        disco.guardar("presion-estado.json", ValorJson.Objeto(guardado.campos + ("sesiones" to ValorJson.Lista(emptyList()))))
        d.sinRed = true
        val b = armar(d, a.raiz)
        b.m.refrescar()
        assertNull(b.m.sesionGuardada(p.sesionId))
        d.sinRed = false
        val antes = d.cuantas("mypump_presion_get")
        val e = b.m.retomar(p, "anotar")
        assertEquals(antes + 1, d.cuantas("mypump_presion_get"))
        assertEquals(1, e?.sesion?.tomas?.size)
        b.m.anotarToma(150, 90, 70, false)
        assertEquals(2, b.m.enCurso?.sesion?.tomas?.last()?.orden)
        // Una sesión que el servidor tampoco tiene: no se retoma con tomas vacías.
        val c = armar(DoblePresion.escenario("pendienteAlta"))
        c.m.refrescar()
        assertNull(c.m.retomar(PendientePresion("no-esta", "alta", null), "anotar"))
        assertNull(c.m.enCurso)
    }

    /** Punto 8: marca, modelo y código se cortan a 80 caracteres. */
    @Test fun marcaModeloYCodigoA80(): Unit = runBlocking {
        val d = DoblePresion.escenario("vacio")
        val m = armar(d).m
        m.refrescar()
        val largo = "x".repeat(120)
        assertEquals(ModeloPresion.Salida.OK, m.guardarAparato(Presion.Aparato(tipo = "brazo", marca = largo, modelo = largo, modeloCodigo = largo)))
        for (k in listOf("marca", "modelo", "modelo_codigo")) assertEquals(80, d.aparato?.get(k)?.comoTexto?.length)
    }

    // ── Decodificación ──

    @Test fun decodificacionTolerante() {
        assertNull(EstadoPresion.desde(json("""{"habilitado":false}""")))
        assertNull(EstadoPresion.desde(json("""{"habilitado":"si"}""")))
        assertNull(EstadoPresion.desde(json("[]")))
        val minimo = EstadoPresion.desde(json("""{"habilitado":true}"""))
        assertNotNull(minimo)
        assertTrue(minimo!!.aparato == null && minimo.serie == null && minimo.sesiones.isEmpty() && minimo.pendiente == null && minimo.tensiometros == null && !minimo.fotos)
        // Tipos cambiados, campos de más y filas rotas: lo que no se entiende se descarta, lo demás queda.
        val raro = EstadoPresion.desde(
            json(
                """
        {"habilitado":true,"fotos":"si","hoy":20261110,"algo_nuevo":{"x":1},
         "aparato":{"tipo":"brazo","validado":7,"manguito_min_cm":"22","manguito_max_cm":42,"otro":true},
         "circunferencia_brazo_cm":"35",
         "serie":{"id":"s1","tipo":"rara","tomas_objetivo":"tres","dias":["2026-11-08",9,null],"ortostatica":"de_cabeza","comparar_brazos":"si","medida_pedida":true},
         "sesiones":[{"id":"a","fecha":"2026-11-08","tipo":"estandar","cuenta":true,"tomas":[{"orden":2,"sis":130,"dia":82,"pulso":60},{"orden":1,"sis":"x","dia":80,"pulso":60},{"sis":128,"dia":80,"pulso":61,"latido_irregular":true}]},
                     {"fecha":"2026-11-07"},7,{"id":"b","tomas":"ninguna"}],
         "pendiente":{"nivel":"urgencia"},
         "tensiometros":{"version":3,"tramos":{"estandar":[{"nombre":"Uno","codigo":"A-1"},{"codigo":"sin nombre"}],"grande":"no"}}}
        """,
            ),
        )
        assertNotNull(raro)
        raro!!
        assertFalse(raro.fotos)
        assertNull(raro.hoy)
        assertEquals("brazo", raro.aparato?.tipo)
        assertNull(raro.aparato?.validado)
        assertNull(raro.aparato?.manguitoMinCm)
        assertEquals(42.0, raro.aparato?.manguitoMaxCm)
        assertNull(raro.circunferenciaBrazoCm)
        assertEquals("estandar", raro.serie?.tipo)
        assertEquals(3, raro.serie?.tomasObjetivo)
        assertEquals(listOf("2026-11-08"), raro.serie?.dias)
        assertEquals(2, raro.serie?.faltan)
        assertNull(raro.serie?.ortostatica)
        assertEquals(false, raro.serie?.compararBrazos)
        assertEquals(true, raro.serie?.medidaPedida)
        assertEquals(listOf("a", "b"), raro.sesiones.map { it.id })
        assertEquals(listOf(128, 130), raro.sesiones.first().tomas.map { it.sis })
        assertTrue(raro.sesiones.first().tomas.first().latidoIrregular)
        assertTrue(raro.sesiones.last().tomas.isEmpty())
        assertNull(raro.pendiente)
        assertEquals("3", raro.tensiometros?.version)
        assertEquals(listOf("Uno"), raro.tensiometros?.tramos?.get("estandar")?.map { it.nombre })
        assertEquals(true, raro.tensiometros?.tramos?.get("grande")?.isEmpty())
    }

    @Test fun losEscenariosDelDobleArrancan(): Unit = runBlocking {
        val casos = listOf(
            Triple("vacio", false, false), Triple("sinSerie", true, false), Triple("serie0", true, true), Triple("serie2", true, true),
            Triple("pendienteUrgencia", true, true), Triple("completa", true, true), Triple("muneca", true, true), Triple("bajoEfecto", true, true),
            Triple("ortostatica", true, true), Triple("noValidado", true, true), Triple("brazos", true, true), Triple("medirDeNuevo", true, true),
            Triple("conLista", true, true), Triple("reloj", true, false),
        )
        for ((nombre, conAparato, conSerie) in casos) {
            val m = armar(DoblePresion.escenario(nombre)).m
            m.refrescar()
            assertTrue(m.habilitado, nombre)
            assertEquals(conAparato, m.estado.value?.aparato != null, nombre)
            assertEquals(conSerie, m.estado.value?.serie != null, nombre)
        }
        suspend fun de(nombre: String) = armar(DoblePresion.escenario(nombre)).m.also { it.refrescar() }.estado.value
        assertEquals(0, de("completa")?.serie?.faltan)
        assertEquals(3, de("completa")?.sesiones?.size)
        val u = de("muneca")
        assertEquals("muneca_provisoria", Presion.metodo(u?.circunferenciaBrazoCm, u?.aparato).metodo)
        assertEquals("acostado_parado", de("ortostatica")?.serie?.ortostatica)
        assertEquals("bajo_efecto", de("bajoEfecto")?.serie?.tipo)
        assertEquals(true, de("brazos")?.serie?.compararBrazos)
        assertEquals(true, de("medirDeNuevo")?.serie?.medidaPedida)
        assertNull(de("serie0")?.tensiometros)
        assertEquals(1, de("conLista")?.tensiometros?.tramos?.get("grande")?.size)
    }
}
