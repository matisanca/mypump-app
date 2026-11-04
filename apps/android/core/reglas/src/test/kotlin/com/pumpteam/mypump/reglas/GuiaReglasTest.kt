package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ClipGuia
import com.pumpteam.mypump.modelos.Guia
import com.pumpteam.mypump.modelos.ResumenGuia
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths
import java.time.Instant
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class GuiaReglasTest {
    private val raiz: Path = generateSequence(Paths.get("").toAbsolutePath()) { it.parent }
        .first { Files.isDirectory(it.resolve("apps/shared/fixtures/guia")) }

    private fun guia(n: String) = Guia.desde(Json.parseToJsonElement(Files.readString(raiz.resolve("apps/shared/fixtures/guia/$n.json"))))!!

    private fun clip(id: String, bloque: String? = "B", visto: Boolean = false, segundos: Int = 0, url: String? = "https://x/$id.mp4", minutos: Double = 1.0) =
        ClipGuia(id, "¿$id?", url, minutos, null, bloque, visto, segundos, null)

    @Test
    fun bloquesEnOrdenConTuAppPrimero() {
        val c = listOf(clip("a", "Tu entrenamiento"), clip("b", "Tu app"), clip("c", "Tu entrenamiento"), clip("d", null), clip("e", "tu app "))
        val o = ReglasGuia.ordenados(c)
        assertEquals(listOf("b", "e", "a", "c", "d"), o.map { it.id })
        val b = ReglasGuia.bloques(o)
        assertEquals(listOf("Tu app", "tu app ", "Tu entrenamiento", "Videos"), b.map { it.titulo })
        assertEquals(listOf(2, 3), b[2].indices)
        assertEquals("2 videos, unos 2 minutos", b[2].resumen)
        assertEquals("1 video, unos 1 minutos", b[3].resumen)
    }

    @Test
    fun conLaFixture() {
        val g = guia("get-tomas")
        val b = ReglasGuia.bloques(ReglasGuia.ordenados(g.clips))
        assertEquals(listOf("Tu app", "Lo que no te podés saltear", "Tu entrenamiento", "Tu alimentación", "Tu suplementación"), b.map { it.titulo })
        // 3,5 en coma flotante es 3,4999…: la web también redondea a 3.
        assertEquals("8 videos, unos 3 minutos", b[0].resumen)
    }

    @Test
    fun avanceYTarjeta() {
        assertEquals("Viste 4 de 13, te quedan unos 12 minutos", ReglasGuia.textoAvance(ResumenGuia(13, 4, 11.6)))
        assertEquals("Viste 0 de 2, te quedan unos 1 minutos", ReglasGuia.textoAvance(ResumenGuia(2, 0, 0.3)))
        assertEquals("Viste todos, nos vemos en la videollamada", ReglasGuia.textoAvance(ResumenGuia(5, 5, 0.0)))
        assertEquals("4 de 13 videos, te quedan 12 min", ReglasGuia.textoTarjeta(ResumenGuia(13, 4, 11.6)))
        assertEquals("Viste los 5 videos", ReglasGuia.textoTarjeta(ResumenGuia(5, 5, 0.0)))
        assertEquals(0.25f, ReglasGuia.fraccion(ResumenGuia(8, 2, 1.0)))
    }

    @Test
    fun duracion() {
        assertEquals("0:42", ReglasGuia.duracion(0.7))
        assertEquals("1:48", ReglasGuia.duracion(1.8))
        assertEquals("0:00", ReglasGuia.duracion(0.0))
        assertEquals("42 segundos", ReglasGuia.duracionHablada(0.7))
        assertEquals("1 minuto 48 segundos", ReglasGuia.duracionHablada(1.8))
        assertEquals("2 minutos", ReglasGuia.duracionHablada(2.0))
    }

    @Test
    fun motivoPartido() {
        assertEquals("Hacé esto" to "Para esto", ReglasGuia.partesMotivo("Hacé esto ||| Para esto"))
        assertEquals("Hacé esto" to null, ReglasGuia.partesMotivo("Hacé esto |||"))
        assertEquals(null to "Solo el para qué", ReglasGuia.partesMotivo(" Solo el para qué "))
        assertEquals(null to null, ReglasGuia.partesMotivo(null))
        assertEquals(null to null, ReglasGuia.partesMotivo(" ||| "))
    }

    @Test
    fun fechasYCabecera() {
        val ahora = Instant.parse("2026-11-04T12:00:00Z")
        assertEquals("viernes 6/11", ReglasGuia.fechaCorta("2026-11-06T14:00:00-03:00"))
        // 23:30 del 6 en Argentina es el 7 en UTC: manda la hora de Argentina.
        assertEquals("viernes 6/11", ReglasGuia.fechaCorta("2026-11-07T02:30:00Z"))
        assertEquals("viernes 6/11", ReglasGuia.fechaCorta("2026-11-06"))
        assertNull(ReglasGuia.fechaCorta("mañana"))
        assertFalse(ReglasGuia.yaPaso(null, ahora))
        assertFalse(ReglasGuia.yaPaso("2026-11-06T14:00:00-03:00", ahora))
        assertTrue(ReglasGuia.yaPaso("2026-11-03T14:00:00-03:00", ahora))
        assertFalse(ReglasGuia.yaPaso("2026-11-04", ahora))
        assertTrue(ReglasGuia.yaPaso("2026-11-03", ahora))
        val g = guia("get-tomas-avanzado")
        assertEquals("Armé estos videos para vos, antes de nuestra videollamada del viernes 6/11, según lo que me contaste.", ReglasGuia.lineaCabecera(g, ahora))
        assertEquals("Armé estos videos para vos, según lo que me contaste.", ReglasGuia.lineaCabecera(g.copy(fechaEntrega = null), ahora))
        assertTrue(ReglasGuia.lineaCabecera(g, Instant.parse("2026-11-08T12:00:00Z")).startsWith("Te dejo estos videos"))
        assertEquals("Hola Tomás", ReglasGuia.saludo(g))
        assertEquals("Hola", ReglasGuia.saludo(g.copy(nombrePila = null)))
    }

    @Test
    fun dudaValida() {
        assertEquals("hola", ReglasGuia.dudaValida("  hola \n"))
        assertNull(ReglasGuia.dudaValida("   "))
        assertEquals(1000, ReglasGuia.dudaValida("x".repeat(1000))!!.length)
        assertNull(ReglasGuia.dudaValida("x".repeat(1001)))
    }

    @Test
    fun inicialSiguienteYAnterior() {
        val c = listOf(clip("a", visto = true), clip("b", url = null), clip("c"), clip("d", visto = true), clip("e", url = ""))
        assertEquals(2, ReglasReproductor.indiceInicial(c))
        assertEquals(0, ReglasReproductor.indiceInicial(c.map { it.copy(visto = true) }))
        assertEquals(-1, ReglasReproductor.indiceInicial(c.map { it.copy(url = null) }))
        assertEquals(2, ReglasReproductor.siguiente(c, 0))
        assertEquals(3, ReglasReproductor.siguiente(c, 2))
        assertNull(ReglasReproductor.siguiente(c, 3))
        assertEquals(0, ReglasReproductor.anterior(c, 2))
        assertNull(ReglasReproductor.anterior(c, 0))
        assertEquals(3, ReglasReproductor.anterior(c, 4))
    }

    @Test
    fun retomar() {
        assertEquals(30.0, ReglasReproductor.retomarDesde(clip("a", segundos = 30), 60.0))
        assertEquals(0.0, ReglasReproductor.retomarDesde(clip("a", segundos = 30, visto = true), 60.0))
        assertEquals(0.0, ReglasReproductor.retomarDesde(clip("a", segundos = 5), 60.0))
        assertEquals(6.0, ReglasReproductor.retomarDesde(clip("a", segundos = 6), 60.0))
        assertEquals(0.0, ReglasReproductor.retomarDesde(clip("a", segundos = 55), 60.0))
        assertEquals(54.0, ReglasReproductor.retomarDesde(clip("a", segundos = 54), 60.0))
        assertEquals(0.0, ReglasReproductor.retomarDesde(clip("a", segundos = 30), 0.0))
    }

    @Test
    fun velocidadYTextos() {
        assertEquals(1.25f, ReglasReproductor.velocidadSiguiente(1f))
        assertEquals(1.5f, ReglasReproductor.velocidadSiguiente(1.25f))
        assertEquals(1f, ReglasReproductor.velocidadSiguiente(1.5f))
        assertEquals(1f, ReglasReproductor.velocidadSiguiente(0.7f))
        assertEquals("1x", ReglasReproductor.textoVelocidad(1f))
        assertEquals("1,25x", ReglasReproductor.textoVelocidad(1.25f))
        assertEquals("1,5x", ReglasReproductor.textoVelocidad(1.5f))
        assertEquals("Otro tema · Video 3 de 20", ReglasReproductor.textoPlaca(2, 20))
        assertEquals("Video 1 de 20 · Tu app", ReglasReproductor.textoNumero(0, 20, "Tu app"))
        assertEquals("Video 1 de 20", ReglasReproductor.textoNumero(0, 20, null))
    }

    @Test
    fun guardaCadaDiezSegundosDeReproduccion() {
        val s = SeguimientoAvance(clip("a"))
        val guardados = mutableListOf<SeguimientoAvance.Guardado>()
        var t = 0.0
        while (t <= 25.0) {
            s.alAvanzar(t, 100.0)?.let { guardados += it }
            t += 0.5
        }
        assertEquals(listOf(10, 20), guardados.map { it.segundos })
        assertTrue(guardados.none { it.visto })
    }

    @Test
    fun unSaltoNoCuentaComoReproduccion() {
        val s = SeguimientoAvance(clip("a"))
        assertNull(s.alAvanzar(0.0, 100.0))
        assertNull(s.alAvanzar(1.0, 100.0))
        // Salto a 40: no cuenta, pero el máximo sube.
        assertNull(s.alAvanzar(40.0, 100.0))
        var g: SeguimientoAvance.Guardado? = null
        var t = 40.0
        while (g == null && t < 60) {
            t += 0.5
            g = s.alAvanzar(t, 100.0)
        }
        assertEquals(49.0, t)
        assertEquals(49, g!!.segundos)
        // Vuelve atrás: los segundos guardados no bajan.
        s.alInterrumpir()
        assertNull(s.alAvanzar(5.0, 100.0))
        t = 5.0
        g = null
        while (g == null) {
            t += 1.0
            g = s.alAvanzar(t, 100.0)
        }
        assertEquals(49, g.segundos)
    }

    @Test
    fun alOchentaMarcaVistoUnaSolaVezYDespuesSiempreVaVisto() {
        val s = SeguimientoAvance(clip("a"))
        assertNull(s.alAvanzar(78.0, 100.0))
        val g = s.alAvanzar(80.0, 100.0)!!
        assertTrue(g.visto)
        assertEquals(80, g.segundos)
        assertNull(s.alAvanzar(80.5, 100.0))
        var t = 80.5
        var siguiente: SeguimientoAvance.Guardado? = null
        while (siguiente == null) {
            t += 0.5
            siguiente = s.alAvanzar(t, 100.0)
        }
        assertTrue(siguiente.visto)
        val fin = s.alTerminar(100.4)
        assertEquals(SeguimientoAvance.Guardado("a", 100, true), fin)
    }

    @Test
    fun unVistoDelServidorSigueVisto() {
        val s = SeguimientoAvance(clip("a", visto = true, segundos = 50))
        var t = 0.0
        var g: SeguimientoAvance.Guardado? = null
        while (g == null) {
            t += 0.5
            g = s.alAvanzar(t, 100.0)
        }
        assertTrue(g.visto)
        assertEquals(50, g.segundos)
    }

    @Test
    fun fusionarNoPierdeLoPendiente() {
        val v = SeguimientoAvance.Guardado("a", 80, true)
        assertEquals(SeguimientoAvance.Guardado("a", 80, true), SeguimientoAvance.fusionar(v, SeguimientoAvance.Guardado("a", 20, false)))
        assertEquals(SeguimientoAvance.Guardado("a", 90, true), SeguimientoAvance.fusionar(v, SeguimientoAvance.Guardado("a", 90, false)))
        assertEquals(SeguimientoAvance.Guardado("b", 1, false), SeguimientoAvance.fusionar(v, SeguimientoAvance.Guardado("b", 1, false)))
        assertEquals(v, SeguimientoAvance.fusionar(null, v))
        assertEquals(36_000, SeguimientoAvance(clip("x")).alTerminar(99_999.0).segundos)
    }

    @Test
    fun suplementacionPorMomento() {
        val v = SuplementacionVista.armar(guia("get-tomas").suplementacion!!)
        assertEquals("Tu suplementación", v.titulo)
        assertEquals(listOf("Desayuno", "30 a 60 minutos antes de entrenar", "Antes de dormir", "Además"), v.momentos.map { it.titulo })
        val desayuno = v.momentos[0].filas
        assertEquals(listOf("Creatina", "Omega 3"), desayuno.map { it.nombre })
        // La creatina aparece dos veces: el por qué, el detalle y el «Ver por qué» solo la primera.
        assertEquals("Te sostiene la fuerza entre series", desayuno[0].porQue)
        assertEquals("FT-50b", desayuno[0].videoId)
        assertEquals("Los días que no entrenás", desayuno[0].nota)
        val pre = v.momentos[1].filas
        assertEquals("Creatina", pre[0].nombre)
        assertNull(pre[0].porQue)
        assertNull(pre[0].videoId)
        assertTrue(pre[0].detalle.isEmpty())
        assertTrue(pre[1].nuevo)
        val dormir = v.momentos[2].filas
        assertTrue(dormir[1].opcional)
        assertEquals(listOf("Vitamina D"), v.momentos[3].filas.map { it.nombre })
        assertEquals(listOf("Té verde en cápsulas"), v.sale.map { it.nombre })
        assertEquals("Tu multivitamínico, como venías", v.sigue)
    }

    @Test
    fun suplementacionSinDiaUsaElOrdenConocido() {
        val s = guia("get-tomas").suplementacion!!
        val v = SuplementacionVista.armar(s.copy(dia = emptyList()))
        assertEquals(listOf("Desayuno", "Antes de entrenar", "Antes de dormir", "Además"), v.momentos.map { it.titulo })
    }

    @Test
    fun negritas() {
        assertEquals(listOf("Que diga " to false, "L-citrulina" to true, " sola." to false), SuplementacionVista.tramos("Que diga *L-citrulina* sola."))
        assertEquals(listOf("sin marcas" to false), SuplementacionVista.tramos("sin marcas"))
    }

    /**
     * Ningún video queda inaccesible: cada clip que sale de la lista (regla de `entregas_012`) tiene su «Ver por qué» en la
     * vista de la suplementación, con los mismos bordes que la web (estado «Sale» no es «sale», un nombre de espacios cuenta).
     */
    @Test
    fun cadaVideoQueSaleDeLaListaTieneSuVerPorQue() {
        val casos = listOf(
            """{"nombre":"Magnesio","estado":"sigue","video_id":"V1","momento":"desayuno"}""",
            """{"nombre":"Magnesio","estado":"Sale","video_id":"V1","momento":"desayuno"}""",
            """{"nombre":"  ","estado":"nuevo","video_id":"V1"}""",
            """{"nombre":"Magnesio","video_id":"V1"}""",
        )
        for (item in casos) {
            val g = Guia.desde(Json.parseToJsonElement(
                """{"ok":true,"clips":[{"id":"V1","titulo":"T","url":"https://x.invalid/v1.mp4","minutos":0.5,"bloque":"Tu suplementación"}],"suplementacion":{"items":[$item]}}""",
            ))!!
            assertEquals(listOf("V1"), g.clipsDeSuplementos.map { it.id }, item)
            val v = SuplementacionVista.armar(g.suplementacion!!)
            val conBoton = v.momentos.flatMap { it.filas }.mapNotNull { it.videoId }
            assertTrue("V1" in conBoton, item)
        }
        // Un ítem que «sale» (exacto) no saca el video de la lista ni le da botón: el clip sigue en la lista.
        val sale = Guia.desde(Json.parseToJsonElement(
            """{"ok":true,"clips":[{"id":"V1","titulo":"T","url":"u","minutos":0.5,"bloque":"Tu suplementación"}],"suplementacion":{"items":[{"nombre":"M","estado":"sale","video_id":"V1"}]}}""",
        ))!!
        assertTrue(sale.clipsDeSuplementos.isEmpty())
        // El id del clip no se recorta: « V1» no es el «V1» del ítem.
        val conEspacio = Guia.desde(Json.parseToJsonElement(
            """{"ok":true,"clips":[{"id":" V1","titulo":"T","url":"u","minutos":0.5,"bloque":"Tu suplementación"}],"suplementacion":{"items":[{"nombre":"M","video_id":"V1"}]}}""",
        ))!!
        assertEquals(listOf(" V1"), conEspacio.clipsDeLaLista.map { it.id })
    }

    /** Al cortar (pausa, otro video, cerrar, segundo plano) se guarda el tramo que faltaba, solo si el máximo subió. */
    @Test
    fun alCortarGuardaElTramoQueFaltaba() {
        val clip = ClipGuia("V", "T", "u", 1.0, null, null, visto = false, segundos = 0, duda = null)
        val s = SeguimientoAvance(clip)
        var t = 0.0
        while (t <= 7.0) { assertNull(s.alAvanzar(t, 60.0)); t += 0.5 }
        assertEquals(SeguimientoAvance.Guardado("V", 7, false), s.alCortar(7.2))
        // Sin avanzar, cortar de nuevo no guarda nada.
        assertNull(s.alCortar(7.2))
        assertNull(s.alCortar(null))
        // Lo que ya tenía el servidor no se vuelve a mandar.
        val visto = SeguimientoAvance(clip.copy(segundos = 30))
        assertNull(visto.alCortar(12.0))
        assertEquals(SeguimientoAvance.Guardado("V", 31, false), visto.alCortar(31.0))
    }

    // ── Después de la entrega (`entregas_014`) ──

    private val ahora: Instant = Instant.parse("2026-11-10T15:00:00Z")

    private fun res(fecha: String? = null, mostrar: Boolean? = null) = ResumenGuia(10, 3, 5.0, fechaEntrega = fecha, mostrarTarjeta = mostrar)

    @Test
    fun mostrarTarjetaLosCuatroCasos() {
        // 1 y 2: el campo del servidor manda, aunque la fecha diga otra cosa.
        assertTrue(ReglasGuia.mostrarTarjeta(res("2026-10-01T13:00:00+00:00", true), ahora))
        assertFalse(ReglasGuia.mostrarTarjeta(res(null, false), ahora))
        // 3: sin el campo (vuelta atrás a la 012), la misma cuenta con la fecha: 48 h exactas.
        assertFalse(ReglasGuia.mostrarTarjeta(res("2026-11-08T15:00:00Z"), ahora))
        assertTrue(ReglasGuia.mostrarTarjeta(res("2026-11-08T15:00:01Z"), ahora))
        assertTrue(ReglasGuia.mostrarTarjeta(res("2026-11-08T12:00:01-03:00"), ahora))
        assertFalse(ReglasGuia.mostrarTarjeta(res("2026-11-01T13:00:00+00:00"), ahora))
        assertTrue(ReglasGuia.mostrarTarjeta(res("2026-11-12T13:00:00+00:00"), ahora))
        // 4: sin ninguno de los dos (o una fecha que no se entiende), la tarjeta.
        assertTrue(ReglasGuia.mostrarTarjeta(res(), ahora))
        assertTrue(ReglasGuia.mostrarTarjeta(res("cualquier cosa larga"), ahora))
    }

    @Test
    fun resumenLeeLosCamposNuevosYSuFalta() {
        fun r(s: String) = ResumenGuia.desde(Json.parseToJsonElement(s))
        val nuevo = r("""{"ok":true,"total":8,"vistos":2,"minutos_restantes":3,"fecha_entrega":"2026-11-01T13:00:00+00:00","mostrar_tarjeta":false}""")!!
        assertEquals("2026-11-01T13:00:00+00:00", nuevo.fechaEntrega)
        assertEquals(false, nuevo.mostrarTarjeta)
        val viejo = r("""{"ok":true,"total":8,"vistos":2,"minutos_restantes":3}""")!!
        assertNull(viejo.fechaEntrega)
        assertNull(viejo.mostrarTarjeta)
        // ok:false no trae mostrar_tarjeta: no hay resumen, ni tarjeta ni fila.
        assertNull(r("""{"ok":false}"""))
        assertEquals(ReglasGuia.Lugar.NINGUNO, ReglasGuia.lugar(null, false, ahora))
        assertEquals(ReglasGuia.AccionEntreno.NINGUNA, ReglasGuia.accionEntreno(null, false, ahora))
        // La caché guarda lo mismo y lo vuelve a leer igual.
        assertEquals(nuevo, ResumenGuia.desde(nuevo.aValor().aJson()))
        assertEquals(viejo, ResumenGuia.desde(viejo.aValor().aJson()))
    }

    @Test
    fun lugarYAccionConLaOcultacionManual() {
        val vigente = res(mostrar = true)
        val vencida = res(mostrar = false)
        assertEquals(ReglasGuia.Lugar.ENTRENO, ReglasGuia.lugar(vigente, false, ahora))
        assertEquals(ReglasGuia.AccionEntreno.QUITAR, ReglasGuia.accionEntreno(vigente, false, ahora))
        // «Quitar de Entreno»: a Mis datos, y se puede volver a mostrar mientras el plazo no pasó.
        assertEquals(ReglasGuia.Lugar.MIS_DATOS, ReglasGuia.lugar(vigente, true, ahora))
        assertEquals(ReglasGuia.AccionEntreno.VOLVER_A_MOSTRAR, ReglasGuia.accionEntreno(vigente, true, ahora))
        // Pasado el plazo: Mis datos, sin acción (oculta o no).
        assertEquals(ReglasGuia.Lugar.MIS_DATOS, ReglasGuia.lugar(vencida, false, ahora))
        assertEquals(ReglasGuia.Lugar.MIS_DATOS, ReglasGuia.lugar(vencida, true, ahora))
        assertEquals(ReglasGuia.AccionEntreno.NINGUNA, ReglasGuia.accionEntreno(vencida, false, ahora))
        assertEquals(ReglasGuia.AccionEntreno.NINGUNA, ReglasGuia.accionEntreno(vencida, true, ahora))
    }

    // ── La guía bien destacada (GUIA_DESTACADA.md) ──

    private val nueva = ResumenGuia(20, 0, 14.4, mostrarTarjeta = true)
    private val aMitad = ResumenGuia(20, 4, 11.6, mostrarTarjeta = true)
    private val completa = ResumenGuia(20, 20, 0.0, mostrarTarjeta = true)

    @Test
    fun bienvenidaSoloConCeroVistosUnaVezYNuncaEnLaDemo() {
        val ahora = Instant.parse("2026-11-04T18:00:00Z")
        assertTrue(ReglasGuia.mostrarBienvenida(nueva, ocultaAMano = false, yaVista = false, esDemo = false, ahora = ahora))
        // Una sola vez.
        assertFalse(ReglasGuia.mostrarBienvenida(nueva, false, yaVista = true, esDemo = false, ahora = ahora))
        // Ya vio alguno.
        assertFalse(ReglasGuia.mostrarBienvenida(aMitad, false, false, false, ahora))
        // La demo, sin guía, oculta a mano o fuera del plazo de la tarjeta: no.
        assertFalse(ReglasGuia.mostrarBienvenida(nueva, false, false, esDemo = true, ahora = ahora))
        assertFalse(ReglasGuia.mostrarBienvenida(null, false, false, false, ahora))
        assertFalse(ReglasGuia.mostrarBienvenida(nueva, ocultaAMano = true, yaVista = false, esDemo = false, ahora = ahora))
        assertFalse(ReglasGuia.mostrarBienvenida(nueva.copy(mostrarTarjeta = false), false, false, false, ahora))
        // Sin `mostrar_tarjeta` (vuelta atrás), la cuenta de las 48 h.
        assertTrue(ReglasGuia.mostrarBienvenida(nueva.copy(mostrarTarjeta = null, fechaEntrega = "2026-11-03T13:00:00Z"), false, false, false, ahora))
        assertFalse(ReglasGuia.mostrarBienvenida(nueva.copy(mostrarTarjeta = null, fechaEntrega = "2026-11-01T13:00:00Z"), false, false, false, ahora))
    }

    @Test
    fun destacadaHastaVerTodoYDespuesCompacta() {
        assertEquals(ReglasGuia.EstiloTarjeta.DESTACADA, ReglasGuia.estiloTarjeta(nueva))
        assertEquals(ReglasGuia.EstiloTarjeta.DESTACADA, ReglasGuia.estiloTarjeta(aMitad))
        assertEquals(ReglasGuia.EstiloTarjeta.DESTACADA, ReglasGuia.estiloTarjeta(ResumenGuia(20, 19, 0.5)))
        assertEquals(ReglasGuia.EstiloTarjeta.COMPACTA, ReglasGuia.estiloTarjeta(completa))
    }

    @Test
    fun textosDeLaDestacadaYLaBienvenida() {
        assertEquals("20 videos cortos, unos 14 min", ReglasGuia.textoDestacada(nueva))
        assertEquals("4 de 20 videos, te quedan 12 min", ReglasGuia.textoDestacada(aMitad))
        assertEquals("1 video corto, unos 1 min", ReglasGuia.textoDestacada(ResumenGuia(1, 0, 0.3)))
        assertEquals("Ver mi guía", ReglasGuia.botonDestacada(nueva))
        assertEquals("Seguir viendo", ReglasGuia.botonDestacada(aMitad))
        assertEquals(
            "Antes de empezar, mirá tu guía. Son 20 videos cortos que armé para vos, unos 14 min. Así en la videollamada vamos directo a lo tuyo.",
            ReglasGuia.textoBienvenida(nueva),
        )
        assertTrue(ReglasGuia.textoBienvenida(ResumenGuia(1, 0, 2.0)).contains("Es un video corto que armé para vos, de unos 2 min."))
        assertEquals("Hola Tomás", ReglasGuia.saludoBienvenida("Tomás", "Otro Nombre"))
        assertEquals("Hola Tomás", ReglasGuia.saludoBienvenida(null, "  Tomás  Ruiz "))
        assertEquals("Hola", ReglasGuia.saludoBienvenida(" ", null))
        assertEquals("Hola", ReglasGuia.saludoBienvenida(null, "   "))
        // Sin «:» al final ni emojis.
        for (t in listOf(ReglasGuia.textoBienvenida(nueva), ReglasGuia.textoDestacada(nueva), ReglasGuia.textoDestacada(aMitad))) {
            assertFalse(t.trimEnd().endsWith(":"))
            assertTrue(t.codePoints().noneMatch { it > 0x2FFF })
        }
    }
}
