package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.LocalDate
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Las reglas de «Estudios y órdenes» contra `estudios/CONTRATO_APP.md`: los textos van tal cual. Datos inventados. */
class EstudiosReglasTest {
    private fun d(s: String) = LocalDate.parse(s)
    private val hoy = d("2026-11-10")
    private val bsas = ZoneId.of("America/Argentina/Buenos_Aires")

    private val completo = """{
      "habilitado": true, "hoy": "2026-11-10", "topes": {"archivos_por_envio": 20, "mb_por_archivo": 20},
      "proximo_control": {"tipo": "laboratorio", "titulo": "Análisis de laboratorio", "desde": "2026-11-23", "hasta": "2026-11-29"},
      "pendientes": [{"id": "p1", "tipo": "laboratorio", "titulo": "Análisis de laboratorio", "detalle": null, "desde": null, "hasta": "2026-11-19",
                      "estado": "pedido", "hecho_fecha": null, "orden_id": "o1"}],
      "ordenes": [{"id": "o1", "tipo": "laboratorio", "titulo": "Análisis de laboratorio", "emitida": "2026-11-03", "vence": "2027-01-02", "vigente": true}],
      "estudios": [{"id": "e1", "tipo": "laboratorio", "titulo": "Análisis de laboratorio", "fecha": "2026-11-03", "hojas": 4, "estado": "recibido",
                    "recibido_en": "2026-11-04T13:02:11Z", "se_puede_abrir": false}],
      "envios": [{"id": "s1", "estado": "enviado", "archivos": 3, "pedido_id": null, "enviado_en": "2026-11-10T12:00:00Z"}]
    }"""

    @Test fun decodificaElEjemploDelContrato() {
        val e = EstadoEstudios.desde(ValorJson.parsear(completo))!!
        assertEquals(hoy, e.hoy)
        assertEquals(20 to 20, e.topeArchivos to e.topeMb)
        assertEquals(ControlEstudios("laboratorio", "Análisis de laboratorio", d("2026-11-23"), d("2026-11-29")), e.proximo)
        assertEquals(PendienteEstudios("p1", "laboratorio", "Análisis de laboratorio", null, null, d("2026-11-19"), false, null, "o1"), e.pendientes.single())
        assertEquals(OrdenEstudios("o1", "laboratorio", "Análisis de laboratorio", d("2026-11-03"), d("2027-01-02"), true), e.ordenes.single())
        assertEquals(EstudioRecibido("e1", "laboratorio", "Análisis de laboratorio", d("2026-11-03"), 4, visto = false, sePuedeAbrir = false), e.estudios.single())
        assertEquals(EnvioRecibido("s1", 3, null, "2026-11-10T12:00:00Z"), e.envios.single())
        assertEquals(e.ordenes.single(), e.orden("o1"))
        assertNull(e.orden(null))
    }

    @Test fun sinHabilitarOTokenCaidoNoHayNada() {
        assertNull(EstadoEstudios.desde(null))
        assertNull(EstadoEstudios.desde(ValorJson.Nulo))
        assertNull(EstadoEstudios.desde(ValorJson.parsear("""{"habilitado":false}""")))
        assertNull(EstadoEstudios.desde(ValorJson.parsear("""{"habilitado":"si"}""")))
        assertNull(EstadoEstudios.desde(ValorJson.parsear("[]")))
    }

    @Test fun todoCampoEsOpcionalYLoDesconocidoNoRompe() {
        val minimo = EstadoEstudios.desde(ValorJson.parsear("""{"habilitado":true}"""))!!
        assertNull(minimo.hoy)
        assertNull(minimo.proximo)
        assertEquals(Estudios.TOPE_ARCHIVOS to Estudios.TOPE_MB, minimo.topeArchivos to minimo.topeMb)
        assertTrue(minimo.pendientes.isEmpty() && minimo.ordenes.isEmpty() && minimo.estudios.isEmpty() && minimo.envios.isEmpty())
        assertEquals(listOf(Estudios.Bloque.VACIO, Estudios.Bloque.SUBIR), Estudios.bloques(minimo))

        val raro = EstadoEstudios.desde(
            ValorJson.parsear(
                """{"habilitado":true,"hoy":"mañana","topes":"muchos","proximo_control":7,"campo_nuevo":{"x":1},
                "pendientes":[{"id":"p1","tipo":"resonancia","titulo":"Resonancia","estado":"en_camino","hasta":"2026-13-45","desde":17},{"titulo":"sin id"},"texto",null],
                "ordenes":[{"id":"o1","tipo":"nuevo","vence":"2026-11-01"},{"tipo":"sin id"}],
                "estudios":[{"estado":"archivado","hojas":"cuatro","fecha":null},{"id":"e2","estado":"visto","se_puede_abrir":"si","hojas":-3},9],
                "envios":[{"id":"s1","estado":"borrador","archivos":2},{"id":"s2","estado":"procesando","archivos":1},{"estado":null}]}""",
            ),
        )!!
        assertNull(raro.hoy)
        assertNull(raro.proximo)
        // Un pendiente de estado desconocido es «pedido»; sin id no se puede usar y no va.
        assertEquals(listOf(PendienteEstudios("p1", "resonancia", "Resonancia", null, null, null, false, null, null)), raro.pendientes)
        // Sin un `vigente: false` del servidor, no se la da por vencida.
        assertEquals(listOf(OrdenEstudios("o1", "nuevo", "Estudio", null, d("2026-11-01"), true)), raro.ordenes)
        // Un estudio de estado desconocido es «Recibido», y sin un `true` de verdad no se abre.
        assertEquals(2, raro.estudios.size)
        assertEquals(EstudioRecibido(null, null, "Estudio", null, 0, visto = false, sePuedeAbrir = false), raro.estudios[0])
        assertEquals(EstudioRecibido("e2", null, "Estudio", null, 0, visto = true, sePuedeAbrir = false), raro.estudios[1])
        assertEquals("Recibido", Estudios.estado(raro.estudios[0]))
        assertEquals("Sin fecha", Estudios.detalleEstudio(raro.estudios[0]))
        // Los borradores no se muestran; un envío de estado desconocido es «enviado».
        assertEquals(listOf("s2", null), raro.envios.map { it.id })
    }

    @Test fun laVigenciaDeUnaOrdenLaDiceElServidor() {
        // El teléfono no la da por vencida por su cuenta: solo un `false` explícito la cierra (como iOS y la web).
        val e = EstadoEstudios.desde(
            ValorJson.parsear(
                """{"habilitado":true,"hoy":"2026-11-10","ordenes":[{"id":"a","vence":"2026-11-09"},{"id":"b","vence":"2026-11-10"},
                {"id":"c","vence":"2027-01-01","vigente":false},{"id":"d","vence":"2026-11-01","vigente":true},{"id":"e","vigente":"false"}]}""",
            ),
        )!!
        assertEquals(listOf(true, true, false, true, true), e.ordenes.map { it.vigente })
    }

    @Test fun bloquesEnOrdenYSoloConContenido() {
        val e = EstadoEstudios.desde(ValorJson.parsear(completo))!!
        assertEquals(listOf(Estudios.Bloque.PROXIMO, Estudios.Bloque.PENDIENTES, Estudios.Bloque.SUBIR, Estudios.Bloque.ORDENES, Estudios.Bloque.ESTUDIOS), Estudios.bloques(e))
        assertEquals(listOf(Estudios.Bloque.SUBIR, Estudios.Bloque.ESTUDIOS), Estudios.bloques(e.copy(proximo = null, pendientes = emptyList(), ordenes = emptyList(), estudios = emptyList())))
        assertEquals(listOf(Estudios.Bloque.PENDIENTES, Estudios.Bloque.SUBIR), Estudios.bloques(e.copy(proximo = null, ordenes = emptyList(), estudios = emptyList(), envios = emptyList())))
        assertEquals(listOf(Estudios.Bloque.VACIO, Estudios.Bloque.SUBIR), Estudios.bloques(e.copy(proximo = null, pendientes = emptyList(), ordenes = emptyList(), estudios = emptyList(), envios = emptyList())))
    }

    @Test fun subtituloDeLaEntrada() {
        assertEquals("Estudios y órdenes", TextosEstudios.entrada)
        assertEquals("Todo al día", TextosEstudios.subtitulo(0))
        assertEquals("Te falta 1 estudio", TextosEstudios.subtitulo(1))
        assertEquals("Te faltan 3 estudios", TextosEstudios.subtitulo(3))
        assertEquals("Te falta 1 estudio", Estudios.subtitulo(EstadoEstudios.desde(ValorJson.parsear(completo))!!))
    }

    @Test fun fechasDelProximoControl() {
        assertEquals("Semana del 23/11", Estudios.cuandoControl(d("2026-11-23"), d("2026-11-29")))
        assertEquals("Semana del 23/11", Estudios.cuandoControl(d("2026-11-23"), d("2026-11-30")))
        assertEquals("Entre el lunes 23/11 y el viernes 4/12", Estudios.cuandoControl(d("2026-11-23"), d("2026-12-04")))
        assertEquals("Semana del 23/11", Estudios.cuandoControl(d("2026-11-23"), null))
        assertEquals("Antes del domingo 29/11", Estudios.cuandoControl(null, d("2026-11-29")))
        assertNull(Estudios.cuandoControl(null, null))
    }

    @Test fun fechasDeLoPendiente() {
        assertEquals(Estudios.Cuando("Antes del jueves 19/11", false), Estudios.cuandoPendiente(null, d("2026-11-19"), hoy))
        assertEquals(Estudios.Cuando("Entre el lunes 16/11 y el jueves 19/11", false), Estudios.cuandoPendiente(d("2026-11-16"), d("2026-11-19"), hoy))
        assertEquals(Estudios.Cuando("Era para el jueves 19/11", true), Estudios.cuandoPendiente(null, d("2026-11-19"), d("2026-11-20")))
        assertEquals(Estudios.Cuando("Era para el jueves 19/11", true), Estudios.cuandoPendiente(d("2026-11-16"), d("2026-11-19"), d("2026-12-01")))
        // El último día todavía no pasó.
        assertEquals(Estudios.Cuando("Antes del jueves 19/11", false), Estudios.cuandoPendiente(null, d("2026-11-19"), d("2026-11-19")))
        assertNull(Estudios.cuandoPendiente(d("2026-11-16"), null, hoy))
        assertEquals("Hecho el 12/11. Falta subir el resultado.", Estudios.hecho(d("2026-11-12")))
    }

    @Test fun diasDeLaSemanaYSinCeros() {
        assertEquals(
            listOf("lunes 2/11", "martes 3/11", "miércoles 4/11", "jueves 5/11", "viernes 6/11", "sábado 7/11", "domingo 8/11"),
            (2..8).map { Estudios.diaLargo(LocalDate.of(2026, 11, it)) },
        )
        assertEquals("2/1", Estudios.diaMes(d("2027-01-02")))
        assertNull(Estudios.dia("ayer"))
        assertNull(Estudios.dia(null))
        assertEquals(d("2026-11-04"), Estudios.dia("2026-11-04T13:02:11Z"))
    }

    @Test fun ordenesYEstudios() {
        assertEquals(listOf("Emitida el 3/11", "Vale hasta el 2/1"), Estudios.renglonesOrden(OrdenEstudios("o", "laboratorio", "x", d("2026-11-03"), d("2027-01-02"), true)))
        assertEquals(
            listOf("Emitida el 20/8", "Vencida. Si la necesitás, pedísela a Mati por el chat."),
            Estudios.renglonesOrden(OrdenEstudios("o", "laboratorio", "x", d("2026-08-20"), d("2026-10-19"), false)),
        )
        assertEquals("3/11 · 4 hojas", Estudios.detalleEstudio(EstudioRecibido("e", null, "x", d("2026-11-03"), 4, false, false)))
        assertEquals("Sin fecha · 1 hoja", Estudios.detalleEstudio(EstudioRecibido("e", null, "x", null, 1, false, false)))
        assertEquals("Mati lo vio", Estudios.estado(EstudioRecibido("e", null, "x", null, 1, true, false)))
        assertEquals("Envío del 10/11 · 3 archivos · Recibido", Estudios.envioCompleto(EnvioRecibido("s", 3, null, "2026-11-10T12:00:00Z"), bsas))
        assertEquals("Envío del 10/11 · 1 archivo · Recibido", Estudios.envioCompleto(EnvioRecibido("s", 1, null, "2026-11-11T01:30:00Z"), bsas))
        assertEquals("Envío · Recibido", Estudios.envioCompleto(EnvioRecibido("s", 0, null, null), bsas))
    }

    @Test fun pluralesYTopes() {
        assertEquals("Enviar 1 archivo", TextosEstudios.enviarArchivos(1))
        assertEquals("Enviar 5 archivos", TextosEstudios.enviarArchivos(5))
        assertEquals("1 hoja", TextosEstudios.hojas(1))
        assertEquals("4 hojas", TextosEstudios.hojas(4))
        assertEquals("Subiendo 2 de 5", TextosEstudios.subiendo(2, 5))
        assertEquals("Hasta 20 archivos por envío.", TextosEstudios.topeArchivos(20))
        assertEquals("Ese archivo pesa más de 20 MB.", TextosEstudios.pesaDeMas(20))
        assertEquals(0, Estudios.restan(20))
        assertEquals(0, Estudios.restan(25))
        assertEquals(3, Estudios.restan(17))
        assertFalse(Estudios.pesaDeMas(20L * 1024 * 1024))
        assertTrue(Estudios.pesaDeMas(20L * 1024 * 1024 + 1))
        assertTrue(Estudios.esPdf("%PDF-1.7\n".toByteArray()))
        assertFalse(Estudios.esPdf("PK\u0003\u0004".toByteArray()))
        assertFalse(Estudios.esPdf(ByteArray(0)))
        assertEquals(2400 to 0.8, Estudios.MAX_PX to Estudios.CALIDAD)
    }

    @Test fun fechaDeYaMeLoHice() {
        assertTrue(Estudios.fechaHechoValida(hoy, hoy))
        assertTrue(Estudios.fechaHechoValida(hoy.minusDays(120), hoy))
        assertFalse(Estudios.fechaHechoValida(hoy.minusDays(121), hoy))
        assertFalse(Estudios.fechaHechoValida(hoy.plusDays(1), hoy))
    }

    @Test fun queHacerConCadaRespuestaDeLaSubida() {
        assertEquals(Estudios.Accion.OK, Estudios.clasificarSubida(200, true))
        assertEquals(Estudios.Accion.REINTENTAR, Estudios.clasificarSubida(200, false))
        // 408 no es distinto del resto de los 4xx (contrato: solo 429 y 5xx reintentan).
        for (s in listOf(400, 403, 404, 408, 409, 411, 413, 415, 422)) assertEquals(Estudios.Accion.DESCARTAR, Estudios.clasificarSubida(s, false), "$s")
        for (s in listOf(429, 500, 502, 503)) assertEquals(Estudios.Accion.REINTENTAR, Estudios.clasificarSubida(s, false), "$s")
    }

    @Test fun comoPrepararteYDondePorTipo() {
        val siempre = listOf("Si Mati te dio una indicación propia, vale esa.", "No dejes ninguna medicación sin que Mati te lo diga.")
        val corazon = "Si tenés dolor de pecho, falta de aire o palpitaciones, avisale a Mati antes de hacerlo."
        assertEquals(
            listOf(
                "Ayuno de 8 a 12 horas. Podés tomar agua, y andá bien hidratado.", "Extracción entre las 7 y las 10 de la mañana.",
                "48 horas antes: sin entrenar y sin alcohol.", "3 días antes: sin biotina (viene en suplementos para pelo y uñas y en algunos multivitamínicos).",
                "Si te piden orina, la primera de la mañana.", "Si estás enfermo o pasaste la noche sin dormir, mejor pasalo a otro día.",
            ) + siempre,
            TextosEstudios.preparacion("laboratorio"),
        )
        assertEquals(listOf("Si es abdominal, ayuno de 6 a 8 horas.", "Para otras ecografías, seguí lo que te indique el centro al sacar el turno.") + siempre, TextosEstudios.preparacion("ecografia"))
        for (t in listOf("ecocardiograma", "electrocardiograma")) assertEquals(listOf("No necesita preparación.", corazon) + siempre, TextosEstudios.preparacion(t))
        for (t in listOf("ergometria", "eco_estres")) {
            assertEquals(listOf("Comida liviana 2 horas antes.", "Ese día, sin café, mate ni tabaco.", "Llevá ropa y zapatillas para hacer ejercicio.", corazon) + siempre, TextosEstudios.preparacion(t))
        }
        assertEquals(
            listOf(
                "Elegí un día común de semana.", "En cada toma, dejá el brazo quieto y relajado.", "Anotá lo que vas haciendo: comidas, entreno y sueño.",
                "Con el aparato puesto no te podés duchar.", corazon,
            ) + siempre,
            TextosEstudios.preparacion("mapa"),
        )
        for (t in listOf("densitometria", "estudios", "otro", "algo_nuevo", null)) assertEquals(listOf("Seguí lo que te indique el centro al sacar el turno.") + siempre, TextosEstudios.preparacion(t))

        assertEquals(
            listOf(
                "En cualquier laboratorio de análisis clínicos. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI.",
                "Si podés, siempre en el mismo laboratorio: así los resultados se comparan mejor.",
            ),
            TextosEstudios.donde("laboratorio"),
        )
        for (t in listOf("ecografia", "mapa", "algo_nuevo", null)) {
            assertEquals(
                listOf("En un centro de diagnóstico o de cardiología, con turno. Si tenés obra social o prepaga, en uno de tu cartilla: llevá la orden, tu credencial y tu DNI."),
                TextosEstudios.donde(t),
            )
        }
    }

    @Test fun textosFijosDelContrato() {
        val t = TextosEstudios
        assertEquals("Estudios", t.titulo)
        assertEquals("Próximo control", t.proximoControl)
        assertEquals("Te falta hacer", t.teFaltaHacer)
        assertEquals(listOf("Subir resultado", "Ya me lo hice", "Ver orden", "Deshacer"), listOf(t.subirResultado, t.yaMeLoHice, t.verOrden, t.deshacer))
        assertEquals(listOf("¿Cuándo te lo hiciste?", "Guardar", "Revisá la fecha."), listOf(t.cuandoTeLoHiciste, t.guardar, t.revisaLaFecha))
        assertEquals("Subir un estudio", t.subirUnEstudio)
        assertEquals("Subí todas las hojas juntas, en PDF o en fotos donde se lea bien.", t.guiaSubida)
        assertEquals(listOf("Sacar fotos", "Elegir fotos", "Elegir PDF", "Quitar"), listOf(t.sacarFotos, t.elegirFotos, t.elegirPdf, t.quitar))
        assertEquals("Sin señal. Se envía solo cuando vuelva.", t.sinSenal)
        assertEquals("Recibido. Mati lo revisa y te escribe.", t.recibidoAviso)
        assertEquals("Ya mandaste varios envíos hoy. Probá mañana o escribile a Mati.", t.topeDia)
        assertEquals("No pudimos leer ese archivo. Probá con una foto o un PDF.", t.archivoRechazado)
        assertEquals(listOf("Tus órdenes", "Cómo prepararte", "Dónde hacerlo", "No se pudo abrir. Probá de nuevo."), listOf(t.tusOrdenes, t.comoPrepararte, t.dondeHacerlo, t.noSePudoAbrir))
        assertEquals(listOf("Tus estudios", "Recibido", "Mati lo vio", "Ver"), listOf(t.tusEstudios, t.recibido, t.matiLoVio, t.ver))
        assertEquals("Recibido quiere decir que llegó. Mati lo revisa y te escribe. Si te sentís mal, no esperes: escribile o consultá a un médico.", t.notaFija)
        assertEquals("Acá vas a ver los estudios que te pida Mati, tus órdenes y lo que nos mandes.", t.vacio)
        assertEquals("No se pudo cargar. Deslizá para reintentar.", t.errorDeCarga)
    }

    @Test fun sinLaPalabraIANiNadaClinico() {
        val todo = (TextosEstudios.preparacion("laboratorio") + TextosEstudios.preparacion("mapa") + TextosEstudios.donde(null) +
            listOf(TextosEstudios.notaFija, TextosEstudios.vacio, TextosEstudios.recibidoAviso, TextosEstudios.guiaSubida, TextosEstudios.topeDia)).joinToString(" ")
        assertFalse(Regex("""\bIA\b|inteligencia artificial""", RegexOption.IGNORE_CASE).containsMatchIn(todo))
        assertNotNull(todo)
    }
}
