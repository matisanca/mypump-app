package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.reglas.ClaveEjercicio
import java.util.TimeZone
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Progreso (PRO-01…05), con el historial grabado de la cuenta de prueba (`test-nativa-real`: la rutina de 4 días y 384
 * filas), como ProgresoGrabadoTest de `:core` pero en la pantalla. Las sesiones son días locales: el teléfono va en Buenos
 * Aires (la prueba corre en el proceso de la app).
 */
@RunWith(AndroidJUnit4::class)
class ProgresoUiTest : PruebaUi() {
    private var zonaAntes: TimeZone? = null

    @Before
    fun enBuenosAires() {
        zonaAntes = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Argentina/Buenos_Aires"))
    }

    @After
    fun zonaDeAntes() {
        TimeZone.setDefault(zonaAntes)
    }

    private fun abrirProgreso() = abrir().also {
        p.tocar(etiqueta("pestana-progreso"))
        p.nodo(etiqueta("progreso-pantalla"))
    }

    /** PRO-01 a 03: los totales, las secciones por día y cada fila con su PR, su tope, su curva y la variación. */
    @Test
    fun laListaConLoGrabado() {
        guardarCuenta()
        abrirProgreso()
        p.esperar("los totales") { p.textosBajo(etiqueta("progreso-totales")).containsAll(listOf("Ejercicios", "32", "Sesiones", "14")) }
        // UN pedido con todas las claves del plan (33), al abrir la pestaña. Entreno pide aparte las de su día.
        assertEquals(1, pedidosDeProgreso())
        // El mismo ejercicio en dos días es una sola fila, en "Tirón · Piernas"; los días van en nombre propio.
        val textos = p.textosBajo(etiqueta("progreso-lista"))
        assertTrue(textos.toString(), textos.indexOf("Tirón · Piernas") in 0 until textos.indexOf("Tirón"))
        assertTrue(textos.contains("máx. por sesión"))
        assertFalse(textos.any { it == "TIRÓN" || it == "TIRÓN · PIERNAS" })
        // Con el peso del cuerpo: "Peso corporal" y sin variación.
        val rollout = p.textosBajo(etiqueta("progreso-fila-$ROLLOUT"))
        assertTrue(rollout.toString(), rollout.containsAll(listOf("Rollout con ab wheel", "Core anterior", "Peso corporal", "—")))
        assertTrue(rollout.contains("Rollout con ab wheel (core anterior): peso corporal"))
        // El jalón: 🏆, Top 58 kg y +11,5 % en las últimas 4 sesiones.
        val jalon = p.textosBajo(etiqueta("progreso-fila-$JALON"))
        assertTrue(jalon.toString(), jalon.containsAll(listOf("Jalón al pecho prono", "Dorsal ancho", "Top 58 kg", "+11,5 %")))
        assertTrue(jalon.contains("Jalón al pecho prono (dorsal ancho): tope 58 kilos, +11,5 % de progresión, récord"))
        // Volver a la pestaña no lo vuelve a pedir: ya hay tarjetas (se actualiza tirando).
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("2.373"))
        p.tocar(etiqueta("pestana-progreso"))
        p.nodo(etiqueta("progreso-totales"))
        p.quieto(500)
        assertEquals(1, pedidosDeProgreso())
    }

    /** PRO-04: el detalle del jalón con el tope, el PR, el gráfico de las 4 sesiones y los últimos 8 registros. */
    @Test
    fun elDetalleConElGraficoYLaTabla() {
        guardarCuenta()
        abrirProgreso()
        p.tocar(etiqueta("progreso-fila-$JALON"))
        p.nodo(etiqueta("progreso-detalle"))
        // Que termine de entrar (la lista ya no está): con el detalle todavía deslizándose, el dedo de abajo caía en otro lado.
        p.esperarQueNoEste(etiqueta("progreso-lista"))
        val encabezado = p.textosBajo(etiqueta("progreso-encabezado"))
        assertEquals(
            "Dorsal ancho · Top: 58 kilos, récord personal, +11,5 % de progresión en las últimas 4 sesiones",
            encabezado.first(),
        )
        assertTrue(encabezado.toString(), encabezado.containsAll(listOf("DORSAL ANCHO · TOP", "58", "kg", "+11,5 %", "de progresión en las últimas 4 sesiones")))
        assertEquals(
            listOf("Máximo por sesión", "Máximo por sesión: 52 kg el 10 sept, 54 kg el 17 sept, 56 kg el 24 sept, 58 kg el 1 oct. Tope 58 kg."),
            p.textosBajo(etiqueta("progreso-grafico")),
        )
        // La tabla: del más nuevo al más viejo, 8 filas, con el tope marcado.
        p.nodo(texto("Últimos registros"))
        assertTrue(p.textosBajo(etiqueta("progreso-tabla")).containsAll(listOf("FECHA", "PESO", "REPS", "RIR")))
        assertEquals(listOf("1 oct", "58 kg", "9", "0"), p.textosBajo(etiqueta("progreso-registro-0")))
        assertEquals("Tope", p.estado(etiqueta("progreso-registro-0")))
        assertEquals(listOf("1 oct", "58 kg", "10", "0"), p.textosBajo(etiqueta("progreso-registro-3")))
        assertEquals(listOf("24 sept", "56 kg", "8", "0"), p.textosBajo(etiqueta("progreso-registro-4")))
        assertNull(p.estado(etiqueta("progreso-registro-4")))
        assertEquals(listOf("17 sept", "54 kg", "10", "0"), p.textosBajo(etiqueta("progreso-registro-7")))
        assertFalse(p.existe(etiqueta("progreso-registro-8")))
        // Con el dedo sobre la última sesión, su valor; al soltar, se va.
        val soltar = p.apoyar(textoQueContiene("Máximo por sesión: "), 0.84f)
        try {
            p.esperar("el globo de la última sesión") { p.textosBajo(etiqueta("progreso-globo")) == listOf("58 kg", "1 oct") }
        } finally {
            soltar()
        }
        p.esperarQueNoEste(etiqueta("progreso-globo"))
        // La flecha vuelve a la lista; Atrás también.
        p.tocar(etiqueta("volver"))
        p.nodo(etiqueta("progreso-lista"))
        p.tocar(etiqueta("progreso-fila-$JALON"))
        // El detalle que se estaba yendo todavía está en el árbol: hasta que la lista no se va, el detalle nuevo no es el de
        // la pantalla y Atrás (en Android 9, apenas tocada la fila) le llegaba a las pestañas, que van a Entreno.
        p.nodo(etiqueta("progreso-detalle"))
        p.esperarQueNoEste(etiqueta("progreso-lista"))
        p.atras()
        p.nodo(etiqueta("progreso-lista"))
        p.esperarQueNoEste(etiqueta("progreso-detalle"))
        assertTrue(p.seleccionado(etiqueta("pestana-progreso")))
    }

    /** Con el peso del cuerpo no hay gráfico de kilos: el progreso está en las repeticiones. */
    @Test
    fun conElPesoDelCuerpoNoHayGrafico() {
        guardarCuenta()
        abrirProgreso()
        p.tocar(etiqueta("progreso-fila-$ROLLOUT"))
        p.nodo(etiqueta("progreso-detalle"))
        val encabezado = p.textosBajo(etiqueta("progreso-encabezado"))
        assertTrue(encabezado.toString(), encabezado.containsAll(listOf("CORE ANTERIOR · TOP", "Peso corporal", "Con el peso del cuerpo, el progreso está en las repeticiones.")))
        assertFalse(p.existe(etiqueta("progreso-grafico")))
        assertEquals(listOf("4 oct", "—", "12", "1"), p.textosBajo(etiqueta("progreso-registro-0")))
        assertNull(p.estado(etiqueta("progreso-registro-0")))
    }

    /** PRO-05: sin red, "No pudimos traer tu historial" con Reintentar, que lo trae cuando vuelve la señal. */
    @Test
    fun sinRedConReintentar() {
        guardarCuenta()
        val e = abrir()
        p.modeloCargado(e)
        servidor.sinRed = true
        p.tocar(etiqueta("pestana-progreso"))
        p.nodo(etiqueta("progreso-sin-red"))
        p.nodo(texto("No pudimos traer tu historial"))
        p.nodo(texto("Sin conexión. Revisá la señal y probá de nuevo."))
        servidor.sinRed = false
        p.tocar(etiqueta("progreso-reintentar"))
        p.esperar("la lista") { p.textosBajo(etiqueta("progreso-totales")).contains("32") }
        assertFalse(p.existe(etiqueta("progreso-sin-red")))
    }

    /** Sin red al abrir la pestaña, volver a ella con señal lo vuelve a pedir solo (como el `.task` de iOS con `.sinRed`). */
    @Test
    fun sinRedVolverALaPestanaLoVuelveAPedir() {
        guardarCuenta()
        val e = abrir()
        p.modeloCargado(e)
        servidor.sinRed = true
        p.tocar(etiqueta("pestana-progreso"))
        p.nodo(etiqueta("progreso-sin-red"))
        servidor.sinRed = false
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("2.373"))
        p.tocar(etiqueta("pestana-progreso"))
        p.esperar("la lista") { p.textosBajo(etiqueta("progreso-totales")).contains("32") }
    }

    /**
     * PRO-02: Progreso agrupa por el ejercicio que se hace de verdad. El press banca del día 1 está sustituido (fijado, por
     * el servidor) por el press inclinado que el día 2 tiene en el plan: es UNA fila, "Empuje · Torso", y el press banca no
     * aparece ni se pide.
     */
    @Test
    fun unaSustitucionAgrupaPorElSustituto() {
        servidor.respuestas["mypump_get_rutina_activa"] = RUTINA
        servidor.respuestas["mypump_get_exercise_swaps"] = SUSTITUCIONES
        servidor.respuestas["mypump_get_historico_por_clave"] = "[" + listOf(
            fila(ClaveEjercicio.de("Press inclinado con mancuernas"), "Press inclinado con mancuernas", 30.0),
            fila(ClaveEjercicio.de("Press banca"), "Press banca", 80.0),
            fila(ClaveEjercicio.de("Sentadilla"), "Sentadilla", 100.0),
        ).joinToString(",") + "]"
        guardarCuenta()
        val e = abrir()
        val (_, m) = p.modeloCargado(e)
        // Que el motor de Entreno ya tenga la sustitución del servidor (Progreso la usa para agrupar).
        val press = p.esperar("la rutina") { m.rutina.value?.estructura?.dias?.firstOrNull()?.bloques?.firstOrNull()?.ejercicios?.firstOrNull() }
        p.esperar("la sustitución aplicada") { m.entreno.value?.efectivo(press)?.ejercicio?.nombre == "Press inclinado con mancuernas" }
        p.quieto(500)
        // Lo que pidió Entreno para su día queda antes: el de Progreso es el que sale al abrir la pestaña.
        val antes = servidor.a("mypump_get_historico_por_clave").size
        p.tocar(etiqueta("pestana-progreso"))
        p.esperar("los totales") { p.textosBajo(etiqueta("progreso-totales")).containsAll(listOf("2", "1")) }
        p.nodo(texto("Empuje · Torso"))
        p.nodo(texto("Empuje"))
        assertTrue(p.textosBajo(etiqueta("progreso-fila-press-d1-0")).containsAll(listOf("Press inclinado con mancuernas", "Top 30 kg")))
        p.nodo(texto("Sentadilla"))
        assertFalse(p.existe(texto("Press banca")))
        val pedidos = servidor.a("mypump_get_historico_por_clave").drop(antes)
        assertEquals(pedidos.toString(), 1, pedidos.size)
        val claves = JSONObject(pedidos.single()).getJSONArray("p_claves").let { a -> List(a.length()) { a.getString(it) } }
        assertEquals(listOf(ClaveEjercicio.de("Press inclinado con mancuernas"), ClaveEjercicio.de("Sentadilla")), claves)
    }

    /** En la demo, como la web, no hay historial: el vacío, sin pedir nada. */
    @Test
    fun enLaDemoNoHayHistorial() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-progreso"))
        p.nodo(etiqueta("progreso-vacio"))
        p.nodo(texto("Aún no hay historial"))
        p.nodo(texto("Aún no hay historial registrado. Empezá tu primera sesión para ver el progreso acá."))
        assertTrue(servidor.llamadas.none { "historico" in it.funcion })
    }

    /** Los pedidos del historial de Progreso: los que llevan todas las claves del plan grabado (Entreno pide las de su día). */
    private fun pedidosDeProgreso(): Int =
        servidor.a("mypump_get_historico_por_clave").count { JSONObject(it).getJSONArray("p_claves").length() == 33 }

    private companion object {
        const val ROLLOUT = "rollout-con-ab-wheel-core-anterior-d1-1"
        const val JALON = "jalon-al-pecho-prono-dorsal-ancho-d1-0"

        private fun ejercicio(id: String, nombre: String) =
            """{"id":"$id","tipo":"principal","nombre":"$nombre","progresion":[{"semana":1,"series":3,"reps":"8","rir":2}]}"""

        /** Dos días (la de ProgresoEfectivoTest): el press banca del día 1 y el press inclinado del día 2. */
        val RUTINA = """[{"id":"rut-progreso","version":1,"semana_actual":1,"estructura":{"dias":[""" +
            """{"n":1,"id":"d1","nombre":"EMPUJE","bloques":[{"titulo":"A","ejercicios":[""" +
            ejercicio("press-d1-0", "Press banca") + "," + ejercicio("sentadilla-d1-1", "Sentadilla") + "]}]}," +
            """{"n":2,"id":"d2","nombre":"TORSO","bloques":[{"titulo":"A","ejercicios":[""" +
            ejercicio("inclinado-d2-0", "Press inclinado con mancuernas") + "]}]}]}}]"

        /** El press banca sustituido por el press inclinado, fijado desde la semana 1. */
        const val SUSTITUCIONES = """{"vivas":{"press-d1-0":{"current":{"slug":null,"nombre":"Press inclinado con mancuernas",""" +
            """"equipment":null,"images":null},"fijado":true,"semana":1,"_ts":1000}},"borradas":{},"ahora":2000}"""

        fun fila(clave: String, nombre: String, kg: Double) =
            """{"clave":"$clave","registrado_en":"2026-10-10T15:00:00+00:00","peso_kg":$kg,"reps_realizadas":8,""" +
                """"rir_real":2,"serie_numero":1,"notas":null,"ejercicio_nombre":"$nombre"}"""
    }
}
