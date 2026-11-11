package com.pumpteam.mypump.ui

import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.ImagenesRemotas
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.progreso.VACIO_SIN_RED
import com.pumpteam.mypump.progreso.VACIO_SIN_SERIES
import com.pumpteam.mypump.reglas.ClaveEjercicio
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.salud.EstadoHealthConnect
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La pestaña Salud (2.1, S1 y S2): el lugar de Progreso, los tres segmentos (Recuperación, Fuerza, Cuerpo) con su
 * captura en claro y oscuro, el segmento que se recuerda, el volumen por músculo en Fuerza y en el cierre del día, y
 * Cuerpo sin fotos ni check. Todo con el servidor de prueba (sin red): una rutina de dos días con el slug del catálogo,
 * un catálogo chico y un historial con fechas de esta semana y la pasada.
 */
@RunWith(AndroidJUnit4::class)
class SaludPestanaUiTest : PruebaUi() {
    @After
    fun sacarSalud() {
        ModeloSalud.fuenteDelSistema = null
        EstadoHealthConnect.forzado = null
    }

    private fun irA(segmento: String) {
        if (!p.existe(etiqueta("salud-pantalla"))) p.abrirSalud()
        p.tocar(etiqueta("segmento-$segmento"))
        p.esperar("$segmento elegido") { p.seleccionado(etiqueta("segmento-$segmento")) }
    }

    /** La rutina, el catálogo y el historial: press banca (pecho) 3 hoy y 1 la semana pasada; remo (espalda media) 2 la pasada. */
    private fun sembrarEntreno(historial: Boolean = true) {
        servidor.respuestas["mypump_get_rutina_activa"] = RUTINA
        servidor.respuestas["mypump_ejercicios_catalogo"] = CATALOGO
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        val hoy = LocalDate.now()
        val pasada = hoy.minusDays(7)
        servidor.respuestas["mypump_get_historico_por_clave"] = if (!historial) "[]" else "[" + listOf(
            fila(PRESS, hoy, 1), fila(PRESS, hoy, 2), fila(PRESS, hoy, 3), fila(PRESS, pasada, 1),
            fila(REMO, pasada, 1), fila(REMO, pasada, 2),
        ).joinToString(",") + "]"
    }

    /** Lo demás para las capturas: fotos de 6 semanas, Oura y WHOOP, la salud del reloj de la cuenta de iOS y el check. */
    private fun sembrarTodo() {
        sembrarEntreno()
        val lunes = DiaCalendario.numero(FotosProgreso.lunes(FechaLocal.hoy()))!!
        val semanas = (1..6).map { DiaCalendario.texto(lunes - 7L * it) }
        servidor.ponerFotos(semanas.associateWith { listOf("frente", "perfil", "espalda") })
        val tonos = mapOf("frente" to Color.rgb(92, 124, 153), "perfil" to Color.rgb(120, 104, 150), "espalda" to Color.rgb(96, 140, 110))
        ImagenesRemotas.bajar = { url -> tonos.entries.firstOrNull { "/${it.key}.jpg" in url }?.let { FotoDePrueba.miniatura(it.value) } }
        servidor.relojes = listOf("oura", "whoop")
        servidor.respuestas["mypump_get_conexiones"] = """[{"proveedor":"whoop","estado":"conectada","ultimo_pull_en":"2026-10-14T07:10:00Z"}]"""
        servidor.respuestas["mypump_get_checkin_semana"] =
            """[{"semana_lunes":"${DiaCalendario.texto(lunes)}","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"Semana pesada en el trabajo, dormí poco el martes."}]"""
        ModeloSalud.fuenteDelSistema = FuenteDeMentira()
        EstadoHealthConnect.forzado = EstadoHealthConnect.DISPONIBLE
        for (f in listOf("get_salud", "get_recuperacion", "get_mostrar_recuperacion")) {
            servidor.respuestas["mypump_$f"] = instr.context.assets.open("test-nativa-ios/$f.json").use { it.readBytes().toString(Charsets.UTF_8) }
        }
        guardarPreferencia(ClaveSalud.CONECTADO, "1")
        guardarPreferencia(ClaveSalud.HISTORIAL_HECHO, "1")
    }

    // ── S1: la pestaña y sus segmentos ──

    /**
     * Salud (2.1.0) ya no es pestaña: se abre desde la tarjeta Recuperación de Revisión, siempre en Recuperación, con sus
     * tres segmentos, y Revisión queda marcada en la barra.
     */
    @Test
    fun saludSeAbreDesdeRevisionEnRecuperacion() {
        sembrarEntreno()
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-revision"))
        assertFalse(p.existe(etiqueta("pestana-salud")))
        assertFalse(p.existe(etiqueta("pestana-progreso")))
        p.abrirSalud()
        assertTrue(p.enSalud())
        p.esperar("arranca en Recuperación") { p.seleccionado(etiqueta("segmento-recuperacion")) }
        for (t in listOf("Recuperación", "Fuerza", "Cuerpo")) p.nodo(texto(t))
        p.nodo(etiqueta("card-recuperacion"))
        irA("cuerpo")
        p.nodo(etiqueta("seccion-peso"))
        // La tarjeta vuelve a abrir Salud en Recuperación, aunque se haya quedado en otro segmento.
        p.tocar(etiqueta("pestana-dieta"))
        p.abrirSalud()
        p.esperar("en Recuperación") { p.seleccionado(etiqueta("segmento-recuperacion")) }
        assertFalse(p.seleccionado(etiqueta("segmento-cuerpo")))
    }

    /**
     * «Tu progreso» (2.1.0) debajo de Recuperación en Revisión: con lo sembrado (press hoy y la semana pasada, remo hace 7
     * días) dice las sesiones de la semana; con un récord, el texto sin emojis y el trofeo. Abre Salud en Fuerza.
     */
    @Test
    fun laTarjetaTuProgresoDiceLaSemanaYAbreFuerza() {
        sembrarEntreno()
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("tarjeta-progreso-revision"))
        // La tarjeta trae el progreso sola (sin pasar por Fuerza).
        p.nodo(texto("1 sesión entrenada esta semana"), ms = 20_000)
        assertFalse(p.existe(etiqueta("trofeo-progreso")))
        p.nodo(texto("Tu progreso"))
        // Pegada a Recuperación: debajo, antes que las fotos.
        val y = { t: String -> p.nodo(etiqueta(t)).let { n -> p.enPrincipal { n.positionInRoot.y } } }
        assertTrue(y("tarjeta-recuperacion-revision") < y("tarjeta-progreso-revision"))
        assertTrue(y("tarjeta-progreso-revision") < y("seccion-fotos"))
        p.tocar(etiqueta("tarjeta-progreso-revision"))
        p.nodo(etiqueta("salud-pantalla"))
        p.esperar("Fuerza elegida") { p.seleccionado(etiqueta("segmento-fuerza")) }
        assertTrue(p.enSalud())
    }

    @Test
    fun conUnRecordLaTarjetaTuProgresoLlevaElTrofeo() {
        sembrarEntreno()
        val hoy = LocalDate.now()
        servidor.respuestas["mypump_get_historico_por_clave"] =
            "[" + listOf(fila(PRESS, hoy, 1, kg = 65), fila(PRESS, hoy.minusDays(7), 1)).joinToString(",") + "]"
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(texto("Récord en $PRESS, 65 kg"), ms = 20_000)
        p.nodo(etiqueta("trofeo-progreso"))
        Telefono.captura("salud-rev-03-progreso-record")
    }

    // ── S2: el volumen por músculo ──
    // (Cada fila es una sola frase para TalkBack: la primera de lo que hay bajo la etiqueta; el árbol sin fusionar que lee
    // la prueba también trae los textos de adentro.)

    /** Fuerza: «Series por músculo» arriba, una fila por músculo que TalkBack lee entera, y lo de Progreso debajo. */
    @Test
    fun fuerzaMuestraLasSeriesPorMusculo() {
        sembrarEntreno()
        guardarCuenta()
        abrir()
        irA("fuerza")
        p.nodo(etiqueta("volumen-musculo"))
        p.nodo(texto("Series por músculo"))
        p.nodo(texto("esta semana"))
        p.esperar("la fila de pecho") { p.existe(etiqueta("volumen-chest")) }
        assertEquals("Pecho, 3 series esta semana, 1 la semana pasada", p.textosBajo(etiqueta("volumen-chest")).first())
        assertEquals("Espalda media, 0 series esta semana, 2 la semana pasada", p.textosBajo(etiqueta("volumen-middle back")).first())
        // Más series esta semana primero.
        val pecho = p.nodo(etiqueta("volumen-chest")).positionInRoot.y
        val espalda = p.nodo(etiqueta("volumen-middle back")).positionInRoot.y
        assertTrue("pecho va antes ($pecho, $espalda)", pecho < espalda)
        p.nodo(texto("Series efectivas registradas, de lunes a domingo. La preparación no cuenta."))
        // Debajo, lo que era Progreso.
        p.esperar("los totales") { p.textosBajo(etiqueta("progreso-totales")).containsAll(listOf("Ejercicios", "2")) }
        assertTrue(p.nodo(etiqueta("volumen-musculo")).positionInRoot.y < p.nodo(etiqueta("progreso-totales")).positionInRoot.y)
    }

    /** Sin el historial (no llegó por la red), la card no dice «Todavía no registraste» (revisión del 3-nov). */
    @Test
    fun sinElHistorialLaCardNoDiceQueNoRegistraste() {
        sembrarEntreno()
        servidor.fallas += "mypump_get_historico_por_clave"
        guardarCuenta()
        abrir()
        irA("fuerza")
        p.nodo(texto(VACIO_SIN_RED))
        assertFalse(p.existe(texto(VACIO_SIN_SERIES)))
        assertFalse(p.existe(etiqueta("volumen-chest")))
    }

    /** Sin series esta semana, la card lo dice (sin filas). */
    @Test
    fun sinSeriesEstaSemanaLaCardLoDice() {
        sembrarEntreno(historial = false)
        guardarCuenta()
        abrir()
        irA("fuerza")
        p.nodo(texto("Todavía no registraste series esta semana."))
        p.nodo(etiqueta("progreso-vacio"))
        assertFalse(p.existe(etiqueta("volumen-chest")))
    }

    /**
     * El cierre del día: «Series por músculo hoy» con lo de hoy y lo de la semana. Sin haber abierto Fuerza, el cierre pide
     * el historial (todas las claves del plan) para sumar los días anteriores.
     */
    @Test
    fun elCierreDelDiaMuestraLasSeriesDeHoy() {
        sembrarEntreno()
        // El historial: solo la semana pasada (lo de hoy sale de lo confirmado en el teléfono).
        val pasada = LocalDate.now().minusDays(7)
        servidor.respuestas["mypump_get_historico_por_clave"] = "[" + fila(PRESS, pasada, 1) + "]"
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
        p.tocar(etiqueta("ejercicio-press-d1-0"))
        fijarCarga("60")
        darOK()
        p.nodo(etiqueta("pregunta"))
        p.tocar(etiqueta("pregunta-no"))
        p.esperarQueNoEste(etiqueta("pregunta"))
        p.tocar(etiqueta("cerrar-sesion"))
        p.nodo(etiqueta("hoja-cerrar-dia"))
        p.nodo(etiqueta("volumen-hoy"))
        p.nodo(texto("Series por músculo hoy"))
        assertEquals("Pecho, 1 serie hoy, 1 en la semana", p.textosBajo(etiqueta("volumen-hoy-chest")).first())
        p.esperar("pidió el historial de todo el plan") {
            servidor.a("mypump_get_historico_por_clave").any { JSONObject(it).getJSONArray("p_claves").length() == 2 }
        }
        Telefono.captura("salud-cierre-volumen-hoy-claro")
    }

    // ── Cuerpo sin nada: lleva a Revisión ──

    @Test
    fun cuerpoSinFotosNiCheckLlevaARevision() {
        sembrarEntreno()
        guardarCuenta()
        abrir()
        irA("cuerpo")
        p.nodo(etiqueta("cuerpo-fotos"))
        p.nodo(texto("Las fotos se suben desde Revisión."))
        p.nodo(texto("Todavía no mandaste el check de esta semana."))
        p.tocar(etiqueta("cuerpo-ir-check"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.nodo(etiqueta("seccion-check"))
    }

    // ── Las capturas de los tres segmentos ──

    @Test
    fun capturasEnClaro() = capturas(oscuro = false)

    @Test
    fun capturasEnOscuro() = capturas(oscuro = true)

    private fun capturas(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        sembrarTodo()
        guardarCuenta()
        abrir().also {
            p.abrirSalud()
            p.nodo(etiqueta("card-recuperacion"))
            p.nodo(etiqueta("card-salud"))
            p.quieto(800)
            foto("salud-01-recuperacion")
            p.desplazar(etiqueta("recuperacion-lista"), 1_600f)
            foto("salud-02-recuperacion-abajo")

            irA("fuerza")
            p.esperar("la fila de pecho") { p.existe(etiqueta("volumen-chest")) }
            p.esperar("los totales") { p.existe(etiqueta("progreso-totales")) }
            p.quieto(600)
            foto("salud-03-fuerza")

            irA("cuerpo")
            p.nodo(etiqueta("grafico-peso"))
            p.esperar("el check") { p.existe(etiqueta("cuerpo-check-energia")) }
            p.quieto(600)
            foto("salud-04-cuerpo")
            p.desplazar(etiqueta("cuerpo-lista"), 1_600f)
            p.quieto(400)
            foto("salud-05-cuerpo-abajo")
            assertEquals("Energía: 4 de 5", p.textosBajo(etiqueta("cuerpo-check-energia")).first())
            p.nodo(etiqueta("cuerpo-check-nota"))
            p.nodo(texto("6 semanas seguidas"))
        }.close()

        // La demo: Recuperación sin datos.
        reiniciarEstado()
        abrir().also {
            p.tocar(etiqueta("ver-demo"))
            // Salud se abre desde la tarjeta Recuperación de Revisión.
            p.abrirSalud()
            p.nodo(etiqueta("recuperacion-vacia"))
            p.nodo(texto("La recuperación sale de tu reloj o de tu teléfono. En la demo no hay datos."))
            foto("salud-06-demo-recuperacion")
        }.close()
    }

    private companion object {
        const val PRESS = "Press banca plano con barra (pectoral)"
        const val REMO = "Remo con barra (dorsal)"

        val CATALOGO = """[{"slug_en":"Barbell_Bench_Press_-_Medium_Grip","name_en":"Barbell Bench Press","primary_muscle":"chest","equipment":"barbell","patron_movimiento":"empuje_horizontal"},""" +
            """{"slug_en":"Bent_Over_Barbell_Row","name_en":"Bent Over Barbell Row","primary_muscle":"middle back","equipment":"barbell","patron_movimiento":"traccion_horizontal"}]"""

        private fun progresion(reps: String) = (1..4).joinToString(",") { """{"semana":$it,"series":1,"reps":"$reps","rir":"1"}""" }

        /** Dos días de un ejercicio con una serie (la de EntrenoUiTest), con el slug del catálogo. */
        val RUTINA = """[{"id":"r-salud","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — PECHO","ejercicios":[
              {"id":"press-d1-0","nombre":"$PRESS","catalogo_slug":"Barbell_Bench_Press_-_Medium_Grip","tipo":"compuesto","descanso_segundos":120,"progresion":[${progresion("8")}]}]}]},
            {"id":"d2","n":2,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1 — ESPALDA","ejercicios":[
              {"id":"remo-d2-0","nombre":"$REMO","catalogo_slug":"Bent_Over_Barbell_Row","tipo":"compuesto","descanso_segundos":120,"progresion":[${progresion("10")}]}]}]}
        ]}}]"""

        /** Una serie del historial a las 12 locales de ese día. */
        fun fila(nombre: String, dia: LocalDate, serie: Int, kg: Int = 60): String {
            val cuando = dia.atTime(12, 0).atZone(ZoneId.systemDefault()).toOffsetDateTime()
            return """{"clave":"${ClaveEjercicio.de(nombre)}","registrado_en":"$cuando","peso_kg":$kg,"reps_realizadas":8,""" +
                """"rir_real":1,"serie_numero":$serie,"notas":null,"ejercicio_nombre":"$nombre"}"""
        }
    }
}
