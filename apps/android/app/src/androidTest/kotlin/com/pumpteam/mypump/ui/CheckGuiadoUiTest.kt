package com.pumpteam.mypump.ui

import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.reglas.CheckGuiado
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * El check guiado (2.3.0) con la palanca `check_guiado` del [ServidorDePrueba] (sin red): el recorrido entero, «Nada de
 * esto», cerrar a medias y retomar, la lista de ciclo y, con la palanca apagada, la Revisión de siempre. Los
 * identificadores son los de la especificación (los mismos en iPhone y en la web). Las capturas quedan en
 * [Telefono.CARPETA_CAPTURAS] (`cg-*`).
 */
@RunWith(AndroidJUnit4::class)
class CheckGuiadoUiTest : PruebaUi() {
    private val hoy get() = FechaLocal.hoy()
    private val lunes get() = FotosProgreso.lunes(hoy)

    @After
    fun soltar() {
        Telefono.shell("settings put system font_scale 1.0")
        Telefono.modoNoche(false)
    }

    /** La palanca prendida y lo que contesta `mypump_check_guiado_get`. */
    private fun prender(enCiclo: Boolean = false, senales: String = "null", catalogo: String = "null", glp1: Boolean? = null, intensidades: String? = null) {
        servidor.respuestas["mypump_get_app_config"] = """{"check_guiado":true}"""
        // `glp1` e `intensidades` (v3) van solo si se piden: sin ellos es el servidor de antes.
        val v3 = (glp1?.let { ""","glp1":$it""" } ?: "") + (intensidades?.let { ""","intensidades":$it""" } ?: "")
        servidor.respuestas["mypump_check_guiado_get"] =
            """{"activo":true,"en_ciclo":$enCiclo,"semana":"$lunes","catalogo":$catalogo,"senales":$senales$v3}"""
    }

    /** Pesos de la semana (para la media) y algo de salud (para «Tu salud, últimos 7 días» del resumen). */
    private fun sembrarSalud() {
        val n = DiaCalendario.numero(hoy)!!
        val filas = ArrayList<String>()
        for (i in 1..5) {
            val f = DiaCalendario.texto(n - i)
            filas += """{"fecha":"$f","tipo":"peso_kg","valor":${78.0 + i * 0.2},"fuente":"manual"}"""
            filas += """{"fecha":"$f","tipo":"pasos","valor":${8000 + i * 150},"fuente":"health_connect"}"""
            filas += """{"fecha":"$f","tipo":"sueno_min","valor":${420 + i * 5},"fuente":"health_connect"}"""
        }
        servidor.respuestas["mypump_get_salud"] = filas.joinToString(",", "[", "]")
    }

    private fun abrirRevision(): ActivityScenario<MainActivity> {
        guardarCuenta()
        val e = abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("seccion-check"))
        return e
    }

    /** Lleva la tarjeta del check a la vista (Revisión es una columna que desliza: lo de abajo existe pero no se ve). */
    private fun mostrarTarjeta() {
        p.nodo(etiqueta("check-guiado-abrir"))
        val delta = p.esperar("se ubica la tarjeta") {
            val visible = p.nodo(etiqueta("revision-lista"), ms = 0).boundsInRoot
            p.nodo(etiqueta("seccion-check"), ms = 0).positionInRoot.y - visible.top - 24f
        }
        p.desplazar(etiqueta("revision-lista"), delta)
        p.quieto(400)
    }

    /** v2: el avance se lee con palabras («Paso 2 de 6»), no solo en los segmentos. */
    private fun avance(): String = p.textosBajo(etiqueta("cg-avance")).joinToString(" ")

    private fun titulo(): String = p.textosBajo(etiqueta("cg-titulo")).joinToString(" ")

    private fun esperarPaso(paso: CheckGuiado.Paso, catalogo: CheckGuiado.Catalogo = CheckGuiado.Catalogo.GENERAL) {
        p.nodo(etiqueta("cg-paso-${paso.clave}"))
        p.esperar("el título de ${paso.clave}") { p.cuantos(etiqueta("cg-titulo")) == 1 && titulo() == CheckGuiado.titulo(paso, catalogo) }
    }

    private fun elegirEscalas() {
        for ((clave, n) in listOf("energia" to 4, "descanso" to 3, "hambre" to 2, "adherencia" to 5)) p.tocar(etiqueta("cg-escala-$clave-$n"))
    }

    /** El recorrido completo, con una captura por paso. [tema] va en el nombre de cada captura. */
    private fun recorrido(tema: String) {
        prender()
        sembrarSalud()
        abrirRevision()
        // La tarjeta reemplaza al check de siempre (y va primera: `laTarjetaEsLoPrimeroDeRevision`).
        p.nodo(etiqueta("check-guiado-tarjeta"))
        assertFalse(p.existe(etiqueta("enviar-check")))
        assertEquals(listOf(CheckGuiado.textoTarjeta(CheckGuiado.Estado.SIN_EMPEZAR)), p.textosBajo(etiqueta("check-guiado-texto")))
        assertEquals(listOf("Empezar"), p.textosBajo(etiqueta("check-guiado-abrir")))
        mostrarTarjeta()
        Telefono.captura("cg-0-tarjeta-$tema")
        p.tocar(etiqueta("check-guiado-abrir"))

        // 1. Peso: vacío no sigue; fuera de rango lo dice; válido sale por la cola de siempre, en el momento.
        esperarPaso(CheckGuiado.Paso.PESO)
        assertEquals("Paso 1 de 6", avance())
        assertFalse(p.habilitado(etiqueta("cg-seguir")))
        assertFalse("en el primer paso no hay Atrás", p.existe(etiqueta("cg-atras")))
        p.nodo(etiqueta("cg-peso-media"))
        Telefono.captura("cg-1-peso-vacio-$tema")
        // Con el teclado abierto, el botón principal sube con él (no queda tapado).
        p.tocarDeVerdad(etiqueta("cg-peso"))
        p.esperar("el peso tiene el foco") { p.enfocado(etiqueta("cg-peso")) }
        p.quieto(1200)
        Telefono.captura("cg-1-peso-teclado-$tema")
        p.escribir(etiqueta("cg-peso"), "12")
        p.tocar(etiqueta("cg-seguir"))
        assertEquals(listOf(CheckGuiado.AVISO_RANGO_PESO), p.textosBajo(etiqueta("cg-falta")))
        p.escribir(etiqueta("cg-peso"), "78,4")
        Telefono.captura("cg-1-peso-$tema")
        p.tocar(etiqueta("cg-seguir"))
        val peso = p.esperar("el peso salió") { servidor.a("mypump_ingest_salud").firstOrNull { "peso_kg" in it } }
        assertTrue(peso, "\"valor\":78.4" in peso && "\"fuente\":\"manual\"" in peso && "\"fecha\":\"$hoy\"" in peso)

        // 2. Escalas: con las cuatro.
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        assertFalse(p.habilitado(etiqueta("cg-seguir")))
        p.tocar(etiqueta("cg-escala-energia-4"))
        p.esperar("dice lo que falta") { p.textosBajo(etiqueta("cg-falta")) == listOf("Faltan: Descanso, Hambre, Adherencia") }
        // Tocar el elegido lo borra.
        p.tocar(etiqueta("cg-escala-energia-4"))
        p.esperarQueNoEste(etiqueta("cg-falta"))
        elegirEscalas()
        p.esperar("las cuatro escalas") { p.habilitado(etiqueta("cg-seguir")) }
        assertTrue(p.seleccionado(etiqueta("cg-escala-hambre-2")))
        assertFalse(p.existe(etiqueta("cg-falta")))
        Telefono.captura("cg-2-escalas-$tema")
        // Con letra grande el contenido desliza: abajo de todo, la leyenda de la última escala queda entera arriba del botón.
        p.desplazar(etiqueta("cg-paso-escalas"), 4000f)
        p.esperar("la última escala, entera arriba del botón") {
            p.nodo(etiqueta("cg-escala-adherencia-5"), ms = 0).boundsInRoot.bottom < p.nodo(etiqueta("cg-seguir"), ms = 0).boundsInRoot.top
        }
        Telefono.captura("cg-2-escalas-abajo-$tema")
        p.tocar(etiqueta("cg-seguir"))

        // 3. Fotos: sin las tres no sigue; se pueden dejar para después.
        esperarPaso(CheckGuiado.Paso.FOTOS)
        assertFalse(p.habilitado(etiqueta("cg-seguir")))
        assertEquals(listOf("0 de 3"), p.textosBajo(etiqueta("cg-fotos-cuenta")))
        assertEquals(listOf("Las subo después"), p.textosBajo(etiqueta("cg-omitir")))
        Telefono.captura("cg-3-fotos-$tema")
        p.tocar(etiqueta("cg-omitir"))

        // 4. Lo marcado: la lista general (el servidor no dijo que esté en ciclo).
        esperarPaso(CheckGuiado.Paso.SENALES)
        assertFalse(p.existe(etiqueta("cg-senal-acne")))
        assertFalse(p.habilitado(etiqueta("cg-seguir")))
        p.tocar(etiqueta("cg-senal-dolor"))
        p.tocar(etiqueta("cg-senal-animo"))
        p.esperar("dos marcadas") { p.prendido(etiqueta("cg-senal-dolor")) && p.prendido(etiqueta("cg-senal-animo")) }
        Telefono.captura("cg-4-senales-$tema")
        p.tocar(etiqueta("cg-seguir"))

        // 5. La nota, opcional.
        esperarPaso(CheckGuiado.Paso.NOTA)
        assertTrue(p.habilitado(etiqueta("cg-seguir")))
        Telefono.captura("cg-5-nota-vacia-$tema")
        p.tocarDeVerdad(etiqueta("cg-nota"))
        p.esperar("la nota tiene el foco") { p.enfocado(etiqueta("cg-nota")) }
        p.escribir(etiqueta("cg-nota"), "Bien la semana, el sábado me pasé un poco.")
        p.quieto(1200)
        Telefono.captura("cg-5-nota-teclado-$tema")
        Telefono.captura("cg-5-nota-$tema")
        p.tocar(etiqueta("cg-seguir"))

        // 6. El resumen: lo contestado, la salud de 7 días y el envío.
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        assertEquals("Paso 6 de 6", avance())
        assertTrue("78,4 kg" in p.textosBajo(etiqueta("cg-fila-peso")))
        assertTrue("4 de 5" in p.textosBajo(etiqueta("cg-fila-escalas")))
        assertTrue("2 de 5" in p.textosBajo(etiqueta("cg-fila-escalas-hambre")))
        assertTrue("0 de 3" in p.textosBajo(etiqueta("cg-fila-fotos")))
        assertTrue("Dolor o molestia al entrenar, Ánimo bajo" in p.textosBajo(etiqueta("cg-fila-senales")))
        assertTrue(p.textosBajo(etiqueta("cg-fila-nota")).any { it.startsWith("Bien la semana") })
        p.nodo(etiqueta("salud-del-check"))
        assertEquals(listOf("Enviar mi check"), p.textosBajo(etiqueta("cg-enviar")))
        assertFalse(p.existe(etiqueta("cg-falta")))
        Telefono.captura("cg-6-resumen-$tema")
        // La salud de 7 días, que queda abajo del resumen.
        p.desplazar(etiqueta("cg-paso-resumen"), 4000f)
        Telefono.captura("cg-6-resumen-abajo-$tema")
        // Una fila lleva a su paso, y de ahí se vuelve al resumen.
        p.tocar(etiqueta("cg-fila-nota"))
        esperarPaso(CheckGuiado.Paso.NOTA)
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        servidor.llamadas.clear()
        p.tocar(etiqueta("cg-enviar"))

        // Listo, y sale lo de siempre más lo marcado.
        p.nodo(etiqueta("cg-listo"))
        assertEquals(listOf("Mati lo ve antes de tu devolución."), p.textosBajo(etiqueta("cg-listo-texto")))
        Telefono.captura("cg-7-listo-$tema")
        val check = p.esperar("el check salió") { servidor.a("mypump_guardar_checkin").firstOrNull() }
        for (campo in listOf("\"p_energia\":4", "\"p_descanso\":3", "\"p_hambre\":2", "\"p_adherencia\":5", "\"p_nota\":\"Bien la semana", "\"p_fecha\":\"$hoy\"")) {
            assertTrue("falta $campo en $check", campo in check)
        }
        val marcado = p.esperar("lo marcado salió") { servidor.a("mypump_check_guiado_guardar").firstOrNull() }
        assertTrue(marcado, "\"p_respuestas\":{\"catalogo\":\"general\",\"senales\":[\"dolor\",\"animo\"],\"intensidades\":{}}" in marcado && "\"p_fecha\":\"$hoy\"" in marcado)
        assertTrue("el peso ya estaba guardado: no se manda otra vez", servidor.a("mypump_ingest_salud").none { "peso_kg" in it })
        p.tocar(etiqueta("cg-cerrar-listo"))

        // De vuelta en Revisión: enviado, y faltan las fotos.
        p.esperarQueNoEste(etiqueta("check-guiado"))
        p.esperar("la tarjeta dice enviado") { p.textosBajo(etiqueta("check-guiado-texto")) == listOf(CheckGuiado.textoTarjeta(CheckGuiado.Estado.ENVIADO_SIN_FOTOS)) }
        assertEquals(listOf("Subir fotos"), p.textosBajo(etiqueta("check-guiado-abrir")))
        mostrarTarjeta()
        Telefono.captura("cg-8-tarjeta-enviado-$tema")
        // «Subir fotos» abre directo en las fotos.
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.FOTOS)
    }

    @Test fun recorridoClaro() = recorrido("claro")

    @Test fun recorridoOscuro() {
        Telefono.modoNoche(true)
        recorrido("oscuro")
    }

    @Test fun recorridoLetraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        recorrido("grande")
    }

    /** «Nada de esto» no convive con otra: marcarla borra las demás y cualquier otra la borra a ella. */
    @Test
    fun nadaDeEstoEsExclusiva() {
        prender()
        abrirRevision()
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.PESO)
        assertEquals(listOf("Hoy no me pesé"), p.textosBajo(etiqueta("cg-omitir")))
        p.tocar(etiqueta("cg-omitir"))
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        elegirEscalas()
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.FOTOS)
        p.tocar(etiqueta("cg-omitir"))
        esperarPaso(CheckGuiado.Paso.SENALES)
        p.tocar(etiqueta("cg-senal-dolor"))
        p.tocar(etiqueta("cg-senal-enfermo"))
        p.esperar("dos marcadas") { p.prendido(etiqueta("cg-senal-dolor")) && p.prendido(etiqueta("cg-senal-enfermo")) }
        p.tocar(etiqueta("cg-senal-ninguno"))
        p.esperar("solo «Nada de esto»") {
            p.prendido(etiqueta("cg-senal-ninguno")) && !p.prendido(etiqueta("cg-senal-dolor")) && !p.prendido(etiqueta("cg-senal-enfermo"))
        }
        assertTrue(p.habilitado(etiqueta("cg-seguir")))
        Telefono.captura("cg-4-senales-nada")
        p.tocar(etiqueta("cg-senal-animo"))
        p.esperar("la otra borra «Nada de esto»") { p.prendido(etiqueta("cg-senal-animo")) && !p.prendido(etiqueta("cg-senal-ninguno")) }
        // Desmarcar la única deja sin nada: no se sigue.
        p.tocar(etiqueta("cg-senal-animo"))
        p.esperar("sin nada marcado no sigue") { !p.habilitado(etiqueta("cg-seguir")) }
        p.tocar(etiqueta("cg-senal-ninguno"))
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.NOTA)
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        assertTrue("Sin cargar" in p.textosBajo(etiqueta("cg-fila-peso")))
        assertTrue("Nada de esto" in p.textosBajo(etiqueta("cg-fila-senales")))
        p.tocar(etiqueta("cg-enviar"))
        p.nodo(etiqueta("cg-listo"))
        val marcado = p.esperar("lo marcado salió") { servidor.a("mypump_check_guiado_guardar").firstOrNull() }
        assertTrue(marcado, "\"senales\":[\"ninguno\"]" in marcado)
        assertTrue("sin peso no se manda peso", servidor.a("mypump_ingest_salud").none { "peso_kg" in it })
    }

    /** Cerrar a medias guarda el borrador sin preguntar; al volver (también después de cerrar la app) sigue donde quedó. */
    @Test
    fun cerrarAMediasYRetomarDondeQuedo() {
        prender()
        val primera = abrirRevision()
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.PESO)
        p.escribir(etiqueta("cg-peso"), "80")
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        p.tocar(etiqueta("cg-escala-energia-4"))
        p.tocar(etiqueta("cg-escala-descanso-3"))
        // Atrás vuelve al peso, que sigue puesto; y adelante, a las escalas con lo elegido.
        p.tocar(etiqueta("cg-atras"))
        esperarPaso(CheckGuiado.Paso.PESO)
        assertEquals("80", p.textoDe(etiqueta("cg-peso")))
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        p.tocar(etiqueta("cg-cerrar"))
        p.esperarQueNoEste(etiqueta("check-guiado"))
        assertTrue("nada se mandó como check", servidor.a("mypump_guardar_checkin").isEmpty())

        // La tarjeta lo dice y el botón pasa a «Seguir».
        p.esperar("la tarjeta dice a medias") { p.textosBajo(etiqueta("check-guiado-texto")) == listOf(CheckGuiado.textoTarjeta(CheckGuiado.Estado.A_MEDIAS)) }
        assertEquals(listOf("Seguir"), p.textosBajo(etiqueta("check-guiado-abrir")))
        mostrarTarjeta()
        Telefono.captura("cg-0-tarjeta-a-medias")
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        assertTrue(p.seleccionado(etiqueta("cg-escala-energia-4")))
        assertTrue(p.seleccionado(etiqueta("cg-escala-descanso-3")))
        assertFalse(p.seleccionado(etiqueta("cg-escala-hambre-2")))
        p.tocar(etiqueta("cg-escala-hambre-2"))
        p.tocar(etiqueta("cg-cerrar"))
        p.esperarQueNoEste(etiqueta("check-guiado"))

        // Se cierra la app: el borrador está en el teléfono.
        primera.close()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("seccion-check"))
        p.esperar("sigue a medias") { p.textosBajo(etiqueta("check-guiado-abrir")) == listOf("Seguir") }
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        assertTrue(p.seleccionado(etiqueta("cg-escala-hambre-2")))
        // El peso de hoy ya salió por la cola: en el resumen está.
        p.tocar(etiqueta("cg-escala-adherencia-5"))
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.FOTOS)
    }

    /** Palanca apagada (así está producción): la Revisión de siempre, sin la tarjeta y sin ninguna llamada nueva. */
    @Test
    fun conLaPalancaApagadaEsLaPantallaDeSiempre() {
        // Sin tocar nada: el servidor de prueba contesta que la palanca no existe.
        val primera = abrirRevision()
        p.nodo(etiqueta("enviar-check"))
        p.nodo(etiqueta("nota-check"))
        p.nodo(etiqueta("peso-check"))
        p.nodo(texto("Faltan: Energía, Descanso, Hambre, Adherencia"))
        assertFalse(p.existe(etiqueta("check-guiado-tarjeta")))
        assertFalse(p.existe(etiqueta("check-guiado-abrir")))
        assertTrue("ni una llamada del check guiado", servidor.llamadas.none { "check_guiado" in it.funcion })
        p.desplazar(etiqueta("revision-lista"), 4000f)
        p.quieto(400)
        Telefono.captura("cg-9-palanca-apagada")

        // Y con la clave en false, lo mismo.
        primera.close()
        servidor.respuestas["mypump_get_app_config"] = """{"check_guiado":false}"""
        servidor.llamadas.clear()
        abrir()
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("seccion-check"))
        p.nodo(etiqueta("enviar-check"))
        assertFalse(p.existe(etiqueta("check-guiado-tarjeta")))
        assertTrue(servidor.llamadas.none { "check_guiado" in it.funcion })
    }

    /** Hasta el paso de «¿Notaste algo de esto?» de una cuenta en ciclo (sin peso ni fotos). */
    private fun hastaLosEfectos() {
        abrirRevision()
        p.esperar("pidió el check guiado con la fecha de hoy") { servidor.a("mypump_check_guiado_get").firstOrNull { "\"p_fecha\":\"$hoy\"" in it } }
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.PESO)
        p.tocar(etiqueta("cg-omitir"))
        esperarPaso(CheckGuiado.Paso.ESCALAS)
        elegirEscalas()
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.FOTOS)
        p.tocar(etiqueta("cg-omitir"))
        esperarPaso(CheckGuiado.Paso.SENALES, CheckGuiado.Catalogo.CICLO)
        assertEquals("¿Notaste algo de esto?", titulo())
        assertFalse("la lista general no aparece", p.existe(etiqueta("cg-senal-dolor")))
    }

    private fun intensidad(efecto: String, cuanto: String) = etiqueta("cg-intensidad-$efecto-$cuanto")

    /**
     * La cuenta en ciclo de siempre (sin GLP-1): la lista de efectos sin los digestivos, y cada efecto marcado pide cuánto
     * molesta. Sin elegirlo, «Seguir» no avanza y lo dice; elegido, avanza, el resumen lo muestra y sale en lo que se manda.
     */
    @Test
    fun enCicloCadaEfectoPideCuantoMolesta() {
        // `glp1` no viene (el servidor de antes) o viene en false: es lo mismo.
        prender(enCiclo = true)
        hastaLosEfectos()
        val lista = CheckGuiado.opciones(CheckGuiado.Catalogo.CICLO, glp1 = false)
        for (o in lista) assertEquals(listOf(o.etiqueta), p.textosBajo(etiqueta("cg-senal-${o.clave}")))
        for (clave in CheckGuiado.DIGESTIVAS) assertFalse("sin GLP-1 no se ve $clave", p.existe(etiqueta("cg-senal-$clave")))
        assertFalse("sin nada marcado no hay intensidades", p.existe(etiqueta("cg-intensidad-acne")))

        p.tocar(etiqueta("cg-senal-acne"))
        p.esperar("acné marcado") { p.prendido(etiqueta("cg-senal-acne")) }
        // Debajo del efecto: el rótulo y los tres botones con texto, ninguno elegido.
        assertEquals(listOf(CheckGuiado.ROTULO_INTENSIDAD, "Leve", "Moderado", "Fuerte"), p.textosBajo(etiqueta("cg-intensidad-acne")))
        for (i in CheckGuiado.INTENSIDADES) assertFalse(p.seleccionado(intensidad("acne", i.clave)))
        val densidad = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density
        val cajas = p.esperar("los tres botones ubicados") { CheckGuiado.INTENSIDADES.map { p.nodo(intensidad("acne", it.clave), ms = 0).boundsInRoot } }
        assertTrue("alto de 48 o más", cajas.all { it.height >= 48f * densidad - 1f })
        assertTrue("uno al lado del otro", cajas[0].right <= cajas[1].left && cajas[1].right <= cajas[2].left && cajas[0].top == cajas[2].top)
        assertTrue("debajo del efecto", cajas[0].top >= p.nodo(etiqueta("cg-senal-acne")).boundsInRoot.bottom)

        // Marcado sin intensidad: «Seguir» está habilitado, pero no avanza y lo dice.
        assertTrue(p.habilitado(etiqueta("cg-seguir")))
        assertFalse(p.existe(etiqueta("cg-falta")))
        p.tocar(etiqueta("cg-seguir"))
        p.esperar("avisa que falta la intensidad") { p.existe(etiqueta("cg-falta")) && p.textosBajo(etiqueta("cg-falta")) == listOf(CheckGuiado.AVISO_INTENSIDAD) }
        esperarPaso(CheckGuiado.Paso.SENALES, CheckGuiado.Catalogo.CICLO)
        Telefono.captura("cg-4-intensidad-falta-claro")

        // Al elegir, el aviso se va y el elegido queda marcado (uno solo).
        p.tocar(intensidad("acne", "moderado"))
        p.esperar("moderado elegido") { p.seleccionado(intensidad("acne", "moderado")) }
        p.esperarQueNoEste(etiqueta("cg-falta"))
        assertFalse(p.seleccionado(intensidad("acne", "leve")))
        p.tocar(intensidad("acne", "leve"))
        p.esperar("cambia a leve") { p.seleccionado(intensidad("acne", "leve")) && !p.seleccionado(intensidad("acne", "moderado")) }
        p.tocar(intensidad("acne", "moderado"))
        p.esperar("vuelve a moderado") { p.seleccionado(intensidad("acne", "moderado")) }

        // Otro efecto: el suyo aparte. Desmarcarlo borra su intensidad (al volver a marcarlo, pide de nuevo).
        p.tocar(etiqueta("cg-senal-sueno"))
        p.tocar(intensidad("sueno", "fuerte"))
        p.esperar("fuerte elegido") { p.seleccionado(intensidad("sueno", "fuerte")) }
        p.tocar(etiqueta("cg-senal-sueno"))
        p.esperarQueNoEste(etiqueta("cg-intensidad-sueno"))
        p.tocar(etiqueta("cg-senal-sueno"))
        p.esperar("vuelve sin intensidad") { p.existe(intensidad("sueno", "fuerte")) && !p.seleccionado(intensidad("sueno", "fuerte")) }
        p.tocar(intensidad("sueno", "fuerte"))
        p.esperar("fuerte elegido de nuevo") { p.seleccionado(intensidad("sueno", "fuerte")) }

        p.desplazar(etiqueta("cg-paso-senales"), -4000f)
        p.nodo(etiqueta("cg-senal-acne"))
        Telefono.captura("cg-4-intensidad-claro")
        Telefono.modoNoche(true)
        p.nodo(etiqueta("cg-senal-acne"))
        Telefono.captura("cg-4-intensidad-oscuro")
        Telefono.modoNoche(false)
        esperarPaso(CheckGuiado.Paso.SENALES, CheckGuiado.Catalogo.CICLO)
        assertTrue(
            "lo marcado y su intensidad sobreviven al cambio de tema",
            p.prendido(etiqueta("cg-senal-acne")) && p.seleccionado(intensidad("acne", "moderado")) && p.seleccionado(intensidad("sueno", "fuerte")),
        )

        // Con todo elegido, avanza; el resumen dice «Efecto · Intensidad» y sale en lo que se manda.
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.NOTA)
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        assertTrue("Acné o piel grasa · Moderado, Insomnio o sudor de noche · Fuerte" in p.textosBajo(etiqueta("cg-fila-senales")))
        Telefono.captura("cg-6-resumen-intensidad-claro")
        p.tocar(etiqueta("cg-enviar"))
        p.nodo(etiqueta("cg-listo"))
        val marcado = p.esperar("lo marcado salió") { servidor.a("mypump_check_guiado_guardar").firstOrNull() }
        assertTrue(
            marcado,
            "\"p_respuestas\":{\"catalogo\":\"ciclo\",\"senales\":[\"acne\",\"sueno\"],\"intensidades\":{\"acne\":\"moderado\",\"sueno\":\"fuerte\"}}" in marcado,
        )
        p.tocar(etiqueta("cg-cerrar-listo"))
        p.esperarQueNoEste(etiqueta("check-guiado"))
    }

    /** La cuenta «ciclo con GLP-1»: ve además los cinco efectos digestivos, cada uno con su intensidad. «Nada de esto» borra todo. */
    @Test
    fun enCicloConGlp1VeLosEfectosDigestivos() {
        prender(enCiclo = true, glp1 = true)
        hastaLosEfectos()
        val lista = CheckGuiado.opciones(CheckGuiado.Catalogo.CICLO, glp1 = true)
        assertEquals(CheckGuiado.opciones(CheckGuiado.Catalogo.CICLO), lista)
        for (o in lista) assertEquals(listOf(o.etiqueta), p.textosBajo(etiqueta("cg-senal-${o.clave}")))
        assertEquals(listOf("Náuseas"), p.textosBajo(etiqueta("cg-senal-nauseas")))

        p.tocar(etiqueta("cg-senal-nauseas"))
        p.tocar(etiqueta("cg-senal-acidez"))
        p.esperar("dos digestivas marcadas") { p.prendido(etiqueta("cg-senal-nauseas")) && p.prendido(etiqueta("cg-senal-acidez")) }
        // Con una sola intensidad elegida todavía falta la otra.
        p.tocar(intensidad("nauseas", "moderado"))
        p.esperar("moderado elegido") { p.seleccionado(intensidad("nauseas", "moderado")) }
        p.tocar(etiqueta("cg-seguir"))
        p.esperar("avisa que falta una") { p.existe(etiqueta("cg-falta")) && p.textosBajo(etiqueta("cg-falta")) == listOf(CheckGuiado.AVISO_INTENSIDAD) }
        esperarPaso(CheckGuiado.Paso.SENALES, CheckGuiado.Catalogo.CICLO)

        // «Nada de esto» desmarca todo y se lleva las intensidades; al volver a marcar, piden de nuevo.
        p.tocar(etiqueta("cg-senal-ninguno"))
        p.esperar("solo «Nada de esto»") { p.prendido(etiqueta("cg-senal-ninguno")) && !p.prendido(etiqueta("cg-senal-nauseas")) }
        assertFalse(p.existe(etiqueta("cg-intensidad-nauseas")))
        assertFalse("«Nada de esto» no pide intensidad", p.existe(etiqueta("cg-intensidad-ninguno")))
        p.tocar(etiqueta("cg-senal-nauseas"))
        p.esperar("náuseas, sin intensidad") { p.existe(intensidad("nauseas", "moderado")) && !p.seleccionado(intensidad("nauseas", "moderado")) }
        p.tocar(intensidad("nauseas", "moderado"))
        p.tocar(etiqueta("cg-senal-acidez"))
        p.tocar(intensidad("acidez", "leve"))
        p.esperar("las dos elegidas") { p.seleccionado(intensidad("nauseas", "moderado")) && p.seleccionado(intensidad("acidez", "leve")) }
        p.desplazar(etiqueta("cg-paso-senales"), 4000f)
        p.quieto(400)
        Telefono.captura("cg-4-intensidad-glp1-claro")
        Telefono.modoNoche(true)
        p.nodo(etiqueta("cg-senal-nauseas"))
        p.desplazar(etiqueta("cg-paso-senales"), 4000f)
        p.quieto(400)
        Telefono.captura("cg-4-intensidad-glp1-oscuro")
        Telefono.modoNoche(false)
        esperarPaso(CheckGuiado.Paso.SENALES, CheckGuiado.Catalogo.CICLO)

        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.NOTA)
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        assertTrue("Náuseas · Moderado, Acidez o reflujo · Leve" in p.textosBajo(etiqueta("cg-fila-senales")))
        Telefono.captura("cg-6-resumen-intensidad-glp1-claro")
        p.tocar(etiqueta("cg-enviar"))
        p.nodo(etiqueta("cg-listo"))
        val marcado = p.esperar("lo marcado salió") { servidor.a("mypump_check_guiado_guardar").firstOrNull() }
        assertTrue(
            marcado,
            "\"p_respuestas\":{\"catalogo\":\"ciclo\",\"senales\":[\"nauseas\",\"acidez\"],\"intensidades\":{\"nauseas\":\"moderado\",\"acidez\":\"leve\"}}" in marcado,
        )
    }

    /** Con la letra al 200 % los tres botones van apilados, enteros y con texto; elegir funciona igual. */
    @Test
    fun laIntensidadConLetraGrandeVaApilada() {
        Telefono.shell("settings put system font_scale 2.0")
        prender(enCiclo = true, glp1 = true)
        hastaLosEfectos()
        p.tocar(etiqueta("cg-senal-acne"))
        p.esperar("acné marcado") { p.prendido(etiqueta("cg-senal-acne")) }
        val cajas = p.esperar("los tres botones ubicados") { CheckGuiado.INTENSIDADES.map { p.nodo(intensidad("acne", it.clave), ms = 0).boundsInRoot } }
        assertTrue("apilados", cajas[0].bottom <= cajas[1].top && cajas[1].bottom <= cajas[2].top && cajas[0].left == cajas[2].left)
        p.tocar(etiqueta("cg-seguir"))
        p.esperar("avisa que falta la intensidad") { p.existe(etiqueta("cg-falta")) }
        Telefono.captura("cg-4-intensidad-falta-grande")
        p.tocar(intensidad("acne", "fuerte"))
        p.esperar("fuerte elegido") { p.seleccionado(intensidad("acne", "fuerte")) }
        p.esperarQueNoEste(etiqueta("cg-falta"))
        // El botón principal sigue a la vista, entero, debajo de lo que desliza.
        val seguir = p.nodo(etiqueta("cg-seguir")).boundsInRoot
        val pantalla = p.nodo(etiqueta("check-guiado")).boundsInRoot
        assertTrue("«Seguir» entero en pantalla", seguir.bottom <= pantalla.bottom && seguir.height > 0f)
        Telefono.captura("cg-4-intensidad-grande")
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.NOTA)
        p.tocar(etiqueta("cg-seguir"))
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        assertTrue("Acné o piel grasa · Fuerte" in p.textosBajo(etiqueta("cg-fila-senales")))
        Telefono.captura("cg-6-resumen-intensidad-grande")
    }

    /** Con las tres fotos de la semana ya subidas no hay paso de fotos; y lo ya enviado abre en el resumen («Cambiar algo»). */
    @Test
    fun conLasFotosSubidasNoHayPasoDeFotosYLoEnviadoAbreEnElResumen() {
        prender(enCiclo = true, senales = """["retencion"]""", catalogo = "\"ciclo\"", intensidades = """{"retencion":"fuerte"}""")
        servidor.ponerFotos(mapOf(lunes to listOf("frente", "perfil", "espalda")))
        servidor.respuestas["mypump_get_checkin_semana"] =
            """[{"semana_lunes":"$lunes","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"todo bien"}]"""
        abrirRevision()
        p.esperar("la tarjeta dice enviado") { p.textosBajo(etiqueta("check-guiado-texto")) == listOf(CheckGuiado.textoTarjeta(CheckGuiado.Estado.ENVIADO)) }
        assertEquals(listOf("Cambiar algo"), p.textosBajo(etiqueta("check-guiado-abrir")))
        mostrarTarjeta()
        Telefono.captura("cg-8-tarjeta-enviado-completo")
        p.tocar(etiqueta("check-guiado-abrir"))
        esperarPaso(CheckGuiado.Paso.RESUMEN)
        assertEquals("Paso 5 de 5", avance())
        assertTrue("3 de 3" in p.textosBajo(etiqueta("cg-fila-fotos")))
        // v3: lo enviado vuelve con su intensidad.
        assertTrue("Retención de líquido o hinchazón · Fuerte" in p.textosBajo(etiqueta("cg-fila-senales")))
        assertFalse(p.existe(etiqueta("cg-falta")))
        assertTrue("todo bien" in p.textosBajo(etiqueta("cg-fila-nota")))
        assertEquals(listOf("Actualizar mi check"), p.textosBajo(etiqueta("cg-enviar")))
        // Abrir y cerrar sin tocar nada no deja un borrador: sigue «Enviado».
        p.tocar(etiqueta("cg-cerrar"))
        p.esperarQueNoEste(etiqueta("check-guiado"))
        assertEquals(listOf("Cambiar algo"), p.textosBajo(etiqueta("check-guiado-abrir")))
    }

    /** v2: con la palanca prendida, la tarjeta del check es lo primero de Revisión y su botón es grande, de lado a lado y con texto. */
    @Test
    fun laTarjetaEsLoPrimeroDeRevision() {
        prender()
        abrirRevision()
        p.nodo(etiqueta("check-guiado-abrir"))
        val m = p.esperar("todo ubicado") {
            listOf("check-guiado-tarjeta", "check-guiado-abrir", "tarjeta-recuperacion-revision", "tarjeta-progreso-revision", "seccion-fotos", "revision-lista")
                .map { p.nodo(etiqueta(it), ms = 0).boundsInRoot }
        }
        val (tarjeta, boton, recuperacion, progreso, fotos) = m
        val lista = m[5]
        assertTrue("arriba de Recuperación", tarjeta.bottom <= recuperacion.top)
        assertTrue("arriba de Tu progreso", tarjeta.bottom <= progreso.top)
        assertTrue("arriba de las fotos", tarjeta.bottom <= fotos.top)
        assertTrue("entera a la vista sin deslizar", tarjeta.top >= lista.top && tarjeta.bottom <= lista.bottom)
        val densidad = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density
        assertTrue("el botón mide al menos 58 de alto", boton.height >= 58f * densidad - 1f)
        assertTrue("el botón va de lado a lado de la tarjeta", boton.width >= tarjeta.width * 0.85f)
        assertEquals(listOf("Empezar"), p.textosBajo(etiqueta("check-guiado-abrir")))
        Telefono.captura("cg-0-revision-arriba-claro")
    }

    /** v2: el banner «Te falta tu check…» de las otras pestañas (ancla `check`) abre el check guiado directamente. */
    @Test
    fun elAnclaCheckAbreElFlujo() {
        prender()
        // Las fotos de la semana están: falta solo el check.
        servidor.ponerFotos(mapOf(lunes to listOf("frente", "perfil", "espalda")))
        guardarCuenta()
        abrir()
        p.esperar("se leyó la palanca y se pidió el check guiado") { servidor.a("mypump_check_guiado_get").firstOrNull() }
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("Te falta tu check de la semana"))
        p.tocar(etiqueta("banner-revision"))
        // Sin tocar nada más: el check abierto en el primer paso (con las fotos subidas no hay paso de fotos).
        esperarPaso(CheckGuiado.Paso.PESO)
        assertEquals("Paso 1 de 5", avance())
        assertEquals(listOf("Salir"), p.textosBajo(etiqueta("cg-cerrar")))
        Telefono.captura("cg-10-ancla-abre-claro")
        // «Salir» deja Revisión, con la tarjeta arriba.
        p.tocar(etiqueta("cg-cerrar"))
        p.esperarQueNoEste(etiqueta("check-guiado"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.nodo(etiqueta("check-guiado-tarjeta"))
        // Y no se vuelve a abrir solo.
        p.quieto(1500)
        assertFalse(p.existe(etiqueta("check-guiado")))
    }
}
