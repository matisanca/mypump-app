package com.pumpteam.mypump.ui

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.entreno.NombreEjercicio
import com.pumpteam.mypump.entreno.SonidoDescanso
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Entreno (ENT, SER y SES): la lista del día con sus cards y lo que lee TalkBack, el detalle de un ejercicio con la
 * tabla de series, tocar un campo (SER-04), sustituir y fijar, el descanso, cerrar el día, reabrirlo, avanzar de semana y
 * el bloque nuevo. El gemelo de EntrenoUITests.swift, con la cuenta grabada (`test-nativa-real`, semana 5) o la demo.
 */
@RunWith(AndroidJUnit4::class)
class EntrenoUiTest : PruebaUi() {
    /** La cuenta grabada con el día sin sesión (nada hecho todavía); la sesión que crea la cola es `ses-prueba-1`. */
    private fun cuentaSinSesion() {
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
    }

    private fun demoEnUnEjercicio(lugar: String = "ex_010") {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("ejercicio-$lugar"))
        p.nodo(etiqueta("tabla-series"))
    }

    private val jalon = etiqueta("ejercicio-jalon-al-pecho-prono-dorsal-ancho-d1-0")

    @Test
    fun laListaDelDiaConSusCardsYLoQueLeeTalkBack() {
        cuentaSinSesion()
        // ENT-09 y GEN-02: "DÍA n · SEMANA x DE y", el nombre, cuántos ejercicios y el anillo.
        p.nodo(texto("DÍA 1 · SEMANA 5 DE 12"))
        assertEquals(listOf("Tirón"), p.textosBajo(etiqueta("entreno-titulo")))
        assertEquals(listOf("9 ejercicios"), p.textosBajo(etiqueta("entreno-cantidad")))
        p.nodo(texto("0 de 9 ejercicios hechos"))
        // ENT-01: los cuatro días, el primero elegido.
        for (d in listOf("d1", "d2", "d3", "d4")) p.nodo(etiqueta("dia-$d"))
        assertTrue(p.seleccionado(etiqueta("dia-d1")))
        assertFalse(p.seleccionado(etiqueta("dia-d2")))
        p.nodo(texto("Día 2, Empuje"))
        // ENT-07: de la semana 4 a la 5 suben las reps de los 7 que no son el cardio ni el core.
        assertTrue(p.textosBajo(etiqueta("banner-progresion")).any { it.contains("Esta semana 7 ejercicios cambian carga o volumen.") })
        p.nodo(etiqueta("empezar-entrenamiento"))
        // ENT-10: la card del jalón con su número, la pauta, el descanso, la última vez y el récord.
        p.nodo(texto("Ejercicio 3: Jalón al pecho prono (dorsal ancho)"))
        p.esperar("el historial del jalón") { p.estado(jalon)?.contains("récord") == true }
        val valor = p.estado(jalon)!!
        assertTrue(valor, valor.startsWith("Pendiente, 4 series de 10, descanso 2:30, última vez 58 kg × 9 · 4 series, "))
        assertTrue(valor, valor.endsWith(", récord 58 kg × 9"))
        val textos = p.textosBajo(jalon)
        for (t in listOf("Jalón al pecho prono", "Dorsal ancho", "4 × 10", "2:30", "58 kg × 9")) {
            assertTrue("falta «$t» en $textos", t in textos)
        }
        assertTrue(textos.toString(), textos.any { it.startsWith("Última: 58 kg × 9 · ") })
        // El core va por el peso del cuerpo: "12 reps", no "0 kg × 12".
        val rollout = etiqueta("ejercicio-rollout-con-ab-wheel-core-anterior-d1-1")
        p.esperar("el historial del rollout") { p.estado(rollout)?.contains("récord") == true }
        val vRollout = p.estado(rollout)!!
        assertTrue(vRollout, vRollout.startsWith("Pendiente, 3 series de 12-15, descanso 1:00, última vez 12 reps · 3 series, "))
        assertTrue(vRollout, vRollout.endsWith(", récord 12 reps"))
        // El cardio: sin series ni historial, con su chip; el descanso que faltaba es 1:30 (ENT-04).
        val cinta = etiqueta("ejercicio-cinta-10-min-entrada-en-calor-d1-0")
        assertEquals("Pendiente, cardio, 10 min, descanso 1:30", p.estado(cinta))
        assertTrue("Cardio" in p.textosBajo(cinta))
        // ENT-05: los bloques con su nombre y hechos/total.
        assertEquals(listOf("BLOQUE 1", "Bloque 1", "Espalda", "0/3"), p.textosBajo(etiqueta("bloque-1")).take(4))
    }

    @Test
    fun enLaDemoLaRutinaDeEjemplo() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.nodo(texto("DÍA 1 · SEMANA 1 DE 12"))
        assertEquals(listOf("Tirón A — Ancho"), p.textosBajo(etiqueta("entreno-titulo")))
        // ENT-08: semana 1 sin offset, calibración.
        p.nodo(etiqueta("banner-calibracion"))
        // El calentamiento con su chip, y sin historial "Primera vez".
        val movilidad = etiqueta("ejercicio-ex_001")
        assertTrue("Calent." in p.textosBajo(movilidad))
        assertEquals("Pendiente, calentamiento, 2 series de 10, descanso 0:30, primera vez con este ejercicio", p.estado(movilidad))
        assertTrue(p.textosBajo(etiqueta("ejercicio-ex_010")).contains("Primera vez con este ejercicio"))
        // La demo no llama a nadie (ni para las fotos: las pruebas no van a la red).
        assertTrue("la demo tocó la red: ${servidor.llamadas.map { it.funcion }}", servidor.llamadas.isEmpty())
    }

    @Test
    fun abrirUnEjercicioYConfirmarUnaSerie() {
        cuentaSinSesion()
        abrirPaginaDelEjercicio("jalon-al-pecho-prono-dorsal-ancho-d1-0")
        p.nodo(etiqueta("tabla-series"))
        assertEquals(listOf("Jalón al pecho prono"), p.textosBajo(etiqueta("ejercicio-nombre")))
        assertEquals(listOf("SERIES × REPS", "Series × reps", "4 × 10", "DESCANSO", "Descanso", "2:30"), p.textosBajo(etiqueta("metricas")))
        assertEquals(listOf("0 de 4"), p.textosBajo(etiqueta("series-confirmadas")))
        // SER-07: el agarre, prono por defecto.
        assertTrue(p.seleccionado(etiqueta("variante-Prono")))
        // SER-01: la carga de la vez pasada ya está puesta y el OK dice qué registra (la misma serie y el mismo agarre).
        p.esperar("la carga de la vez pasada") { (p.textoDe(etiqueta("carga-valor")) == "58").takeIf { it } }
        p.esperar("el OK con lo de la vez pasada") { (p.descripcion(etiqueta("ok-serie")) == "OK, registrar 10 repeticiones con 58 kilos").takeIf { it } }
        p.nodo(texto("Récord a superar"))
        darOK()
        p.esperar("1 de 4") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("1 de 4") }
        assertEquals("Serie 1, hecha: 10 repeticiones, 58 kilos. Tocá para corregirla", p.descripcion(etiqueta("fila-serie-1")))
        // SES-04: arranca el descanso del ejercicio (en el panel, y la tarjeta grande).
        p.nodo(etiqueta("descanso-chip"))
        assertTrue(p.textosBajo(etiqueta("descanso-en-tarjeta")).toString(), p.textosBajo(etiqueta("descanso-en-tarjeta")).any { it.contains("2:30") })
        // La serie sale por la cola, con el agarre en las notas (SER-07) y en la sesión que creó la cola.
        val carga = p.esperar("la serie en el servidor") { servidor.a("mypump_registrar_carga").firstOrNull() }
        for (parte in listOf(
            "\"p_sesion_id\":\"ses-prueba-1\"", "\"p_ejercicio_id\":\"jalon-al-pecho-prono-dorsal-ancho-d1-0\"", "\"p_serie\":1",
            "\"p_peso\":58", "\"p_reps\":10", "\"p_rir\":0", "\"p_notas\":\"Prono\"",
        )) {
            assertTrue("falta $parte en $carga", carga.contains(parte))
        }
        // SER-04: en kg la coma pasa a punto. 2.3.0: el RIR no se muestra ni se elige, siempre 0 (al fallo).
        assertEquals(listOf("Al fallo"), p.textosBajo(etiqueta("leyenda-rir")))
        assertFalse(p.existe(etiqueta("rir-serie-2")))
        fijarCarga("52,5")
        // Con otra carga las reps vuelven al plan: 10, y bajan a 8.
        p.esperar("las reps del plan") { (p.descripcion(etiqueta("ok-serie")) == "OK, registrar 10 repeticiones con 52,5 kilos").takeIf { it } }
        repeat(2) { p.tocar(etiqueta("reps-menos")) }
        darOK()
        p.esperar("2 de 4") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("2 de 4") }
        assertEquals("Serie 2, hecha: 8 repeticiones, 52,5 kilos. Tocá para corregirla", p.descripcion(etiqueta("fila-serie-2")))
        val segunda = p.esperar("la segunda serie") { servidor.a("mypump_registrar_carga").firstOrNull { it.contains("\"p_serie\":2") } }
        assertTrue(segunda, segunda.contains("\"p_peso\":52.5") && segunda.contains("\"p_reps\":8") && segunda.contains("\"p_rir\":0"))
        // De vuelta en la lista, la card lo dice.
        p.tocar(etiqueta("volver"))
        p.esperar("la card con 2 de 4") { p.estado(jalon)?.startsWith("2 de 4 series, ") == true }
    }

    /** SER-01: el OK del panel registra la carga de la última vez con las reps que dice. */
    @Test
    fun elOKRegistraLoDeLaUltimaVez() {
        cuentaSinSesion()
        p.tocar(jalon)
        val ok = etiqueta("ok-serie")
        p.esperar("el OK con 58 × 10") { (p.descripcion(ok) == "OK, registrar 10 repeticiones con 58 kilos").takeIf { it } }
        assertTrue(p.habilitado(ok))
        // Con el dedo, como el cliente.
        p.tocarDeVerdad(ok)
        p.esperar("1 de 4") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("1 de 4") }
        val carga = p.esperar("la serie en el servidor") { servidor.a("mypump_registrar_carga").firstOrNull() }
        assertTrue(carga, carga.contains("\"p_serie\":1") && carga.contains("\"p_peso\":58") && carga.contains("\"p_reps\":10"))
        // El OK pasa a la serie 2. Esta semana el plan cambia las reps (ENT-07), así que manda el plan: 10, con el mismo kilo.
        p.esperar("el OK de la serie 2") { (p.descripcion(ok) == "OK, registrar 10 repeticiones con 58 kilos").takeIf { it } }
        darOK()
        p.esperar("2 de 4") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("2 de 4") }
    }

    /** SER-04: al tocar el campo se selecciona todo; lo que se escribe reemplaza lo anterior (sin esto, 80 corregido a 7 quedaba "870"). */
    @Test
    fun tocarUnCampoLoSeleccionaEntero() {
        demoEnUnEjercicio()
        val kg = etiqueta("carga-valor")
        p.tocarDeVerdad(kg)
        p.esperar("el foco en la carga") { p.enfocado(kg).takeIf { it } }
        p.teclear(kg, "80")
        p.esperar("80") { (p.textoDe(kg) == "80").takeIf { it } }
        p.tocar(etiqueta("carga-mas"))   // el foco se va
        p.esperar("sin foco") { (!p.enfocado(kg)).takeIf { it } }
        val largo = p.textoDe(kg).length
        p.tocarDeVerdad(kg)
        p.esperar("todo seleccionado") { (p.enfocado(kg) && p.seleccion(kg) == (0 to largo)).takeIf { it } }
        p.teclear(kg, "7")
        p.quieto(300)
        assertEquals("lo nuevo no reemplazó a lo anterior", "7", p.textoDe(kg))
    }

    /** ENT-10 y TalkBack: después de sustituir y fijar, la card de la lista lo dice, con la pauta y el descanso. */
    @Test
    fun sustituirYFijarLoDiceLaCard() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        abrirPaginaDelEjercicio("ex_010")
        p.tocar(etiqueta("sustituir"))
        p.nodo(etiqueta("hoja-sustituir"))
        p.nodo(texto("Mismo gesto · otra variante"))   // al remo no le queda otro ejercicio de espalda media que ofrecer
        val elegida = NombreEjercicio(p.textosBajo(etiqueta("variante")).first()).principal
        // SER-11: la búsqueda filtra (y "Sin resultados" si no hay).
        p.escribir(etiqueta("buscar-variante"), "zzz")
        p.nodo(texto("Sin resultados para “zzz”."))
        p.escribir(etiqueta("buscar-variante"), "")
        p.tocar(etiqueta("variante"))
        p.esperar("la elegida") { p.seleccionado(etiqueta("variante")) }
        assertFalse("sin tildar vale solo por hoy", p.prendido(etiqueta("fijar")))
        p.tocar(etiqueta("fijar"))
        p.esperar("fijada") { p.prendido(etiqueta("fijar")) }
        p.tocar(etiqueta("confirmar-sustitucion"))
        p.esperarQueNoEste(etiqueta("hoja-sustituir"))
        // El detalle ya es el sustituto, fijado, en lugar del del plan.
        p.esperar("el sustituto") { p.textosBajo(etiqueta("ejercicio-nombre")) == listOf(elegida) }
        assertEquals(listOf("En lugar de Remo con barra"), p.textosBajo(etiqueta("en-lugar-de")))
        p.nodo(texto("Sustitución fijada para las próximas semanas"))
        p.tocar(etiqueta("volver"))
        val card = etiqueta("ejercicio-ex_010")
        p.esperar("la card sustituida") { p.estado(card)?.contains("sustitución fijada") == true }
        val valor = p.estado(card)!!
        assertTrue(valor, valor.startsWith("Pendiente, sustitución fijada, 4 series de 8-10, descanso 2:30"))
        assertTrue(p.textosBajo(card).containsAll(listOf(elegida, "Fijado")))
        p.nodo(textoQueContiene("Ejercicio 3: $elegida"))
        // "Volver a Remo con barra" la deshace (la fila quedó abierta en la lista: a la página por «Técnica y notas»).
        abrirPaginaDelEjercicio("ex_010")
        p.tocar(etiqueta("sustituir"))
        p.tocar(etiqueta("volver-al-original"))
        p.esperarQueNoEste(etiqueta("hoja-sustituir"))
        p.esperar("el original") { p.textosBajo(etiqueta("ejercicio-nombre")) == listOf("Remo con barra") }
        assertFalse(p.existe(etiqueta("insignia-sustitucion")))
    }

    /**
     * Mati, 20-oct (Eric, con la polea ocupada): a la extensión de tríceps en polea, debajo de las variantes del mismo
     * movimiento, le aparecen los otros ejercicios de tríceps (fondos incluidos), y uno de ellos sustituye igual. Gemela de
     * testLosOtrosDelMismoMusculoTambienSustituyen de iOS.
     */
    @Test
    fun losOtrosDelMismoMusculoTambienSustituyen() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("dia-mar"))
        abrirPaginaDelEjercicio("ex_111")
        p.tocar(etiqueta("sustituir"))
        p.nodo(etiqueta("hoja-sustituir"))
        p.nodo(texto("Otra variante u otro ejercicio de tríceps"))
        // La ceja se ve en mayúsculas y TalkBack la lee como se escribe.
        assertEquals(listOf("OTROS EJERCICIOS DE TRÍCEPS", "Otros ejercicios de tríceps"), p.textosBajo(etiqueta("titulo-otros")))
        // Y los títulos de las dos secciones son encabezados (revisión del 21-oct): TalkBack salta de uno a otro.
        assertTrue("las variantes sin encabezado", p.encabezado(etiqueta("titulo-variantes")))
        assertTrue("los otros sin encabezado", p.encabezado(etiqueta("titulo-otros")))
        Telefono.captura("35-otros-del-mismo-musculo-claro")
        p.tocar(texto("Fondos"))
        Telefono.captura("36-otros-fondos-elegido-claro")
        p.tocar(etiqueta("confirmar-sustitucion"))
        p.esperarQueNoEste(etiqueta("hoja-sustituir"))
        p.esperar("el sustituto") { p.textosBajo(etiqueta("ejercicio-nombre")) == listOf("Fondos") }
        assertEquals(listOf("En lugar de Extensión tríceps en polea"), p.textosBajo(etiqueta("en-lugar-de")))
    }

    /**
     * Revisión del 21-oct: la sugerencia de kg de la tabla se calculaba con todas las series. Polea 2×30, cambio a fondos y
     * las reps de la serie 3: el campo sugería «30» (y el cliente lo cargaba) aunque al confirmar ya no se heredaba. Ahora la
     * tabla sugiere lo mismo que se graba. Gemela de testAlCambiarDeMovimientoElKgNoSugiereElDeLaPolea de iOS.
     */
    @Test
    fun alCambiarDeMovimientoElKgNoSugiereElDeLaPolea() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("dia-mar"))
        abrirPaginaDelEjercicio("ex_111")
        fijarCarga("30")
        for (n in 1..2) {
            darOK()
            p.esperar("$n de 3") { p.textosBajo(etiqueta("series-confirmadas")) == listOf("$n de 3") }
        }
        // Con la polea, la serie 3 sigue con los 30.
        assertTrue(p.descripcion(etiqueta("fila-serie-3")), p.descripcion(etiqueta("fila-serie-3")).contains("30 kilos"))
        p.tocar(etiqueta("sustituir"))
        p.nodo(etiqueta("hoja-sustituir"))
        p.tocar(texto("Fondos"))
        p.tocar(etiqueta("confirmar-sustitucion"))
        p.esperarQueNoEste(etiqueta("hoja-sustituir"))
        p.esperar("el sustituto") { p.textosBajo(etiqueta("ejercicio-nombre")) == listOf("Fondos") }
        // Ya en fondos, la serie 3 no sugiere los kg de la polea (y no se puede registrar sin cargar el kg).
        p.quieto(300)
        assertFalse("ya en fondos sugiere los kg de la polea", p.descripcion(etiqueta("fila-serie-3")).contains("30 kilos"))
        Telefono.captura("38-fondos-sin-los-kg-de-la-polea-claro")
    }

    /**
     * Revisión del 21-oct (D24, hallazgo 5): buscar «fondos» en la extensión en polea decía «Sin resultados para “fondos”»
     * arriba de los fondos que sí había entre los otros ejercicios. Solo se dice si no hay en ninguna lista. Gemela de
     * testBuscarUnOtroEjercicioNoDiceSinResultados de iOS.
     */
    @Test
    fun buscarUnOtroEjercicioNoDiceSinResultados() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("dia-mar"))
        abrirPaginaDelEjercicio("ex_111")
        p.tocar(etiqueta("sustituir"))
        p.nodo(etiqueta("hoja-sustituir"))
        p.escribir(etiqueta("buscar-variante"), "fondos")
        p.esperar("los fondos entre los otros") { p.textosBajo(etiqueta("otro-ejercicio")).firstOrNull() == "Fondos" }
        assertFalse("dice «Sin resultados» con los fondos abajo", p.existe(etiqueta("sin-variantes")))
        Telefono.captura("37-buscar-fondos-claro")
        // Sin nada en ninguna de las dos, sí.
        p.escribir(etiqueta("buscar-variante"), "fondoszzz")
        p.nodo(texto("Sin resultados para “fondoszzz”."))
        assertFalse(p.existe(etiqueta("otro-ejercicio")))
    }

    /** SES-04: el descanso con −15 / +15 y saltar; al terminar suena y, a los 2 s, se cierra solo. */
    @Test
    fun elDescansoConMasMenosYSaltar() {
        demoEnUnEjercicio()
        fijarCarga("60")
        darOK()
        // Con el panel a la vista el descanso va ahí; la barra flotante se ve en las otras pestañas.
        p.nodo(etiqueta("descanso-chip"))
        assertFalse("dos barras apiladas", p.existe(etiqueta("descanso")))
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("descanso"))
        assertEquals(listOf("Descanso / 2:30"), p.textosBajo(etiqueta("descanso-rotulo")))
        val t0 = segundos()
        assertTrue("arrancó en $t0", t0 in 120..150)
        // +15 suma al objetivo y a lo que queda (lo que tarda el emulador entre lectura y lectura se descuenta).
        var desde = SystemClock.elapsedRealtime()
        p.tocar(etiqueta("descanso-mas"))
        p.esperar("+15") { p.textosBajo(etiqueta("descanso-rotulo")) == listOf("Descanso / 2:45") }
        val t1 = segundos()
        var paso = ((SystemClock.elapsedRealtime() - desde) / 1000).toInt()
        assertTrue("$t0 → $t1 en $paso s", t1 in t0 + 15 - paso - 1..t0 + 15)
        desde = SystemClock.elapsedRealtime()
        p.tocar(etiqueta("descanso-menos"))
        val t2 = p.esperar("−15") { segundos().takeIf { it <= t1 - 14 } }
        paso = ((SystemClock.elapsedRealtime() - desde) / 1000).toInt()
        assertTrue("$t1 → $t2 en $paso s", t2 >= t1 - 15 - paso - 1)
        // Restar no achica el objetivo (como la web).
        assertEquals(listOf("Descanso / 2:45"), p.textosBajo(etiqueta("descanso-rotulo")))
        p.nodo(textoQueContiene("Descanso, quedan "))
        p.tocar(etiqueta("descanso-saltar"))
        p.esperarQueNoEste(etiqueta("descanso"))

        // La serie 2 hereda el kg (SER-03).
        p.tocar(etiqueta("pestana-entreno"))
        darOK()
        p.esperar("el kg heredado") { p.descripcion(etiqueta("fila-serie-2")).contains("60 kilos").takeIf { it } }
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("descanso"))
        // Al terminar suena (una vez) y, a los 2 s, la barra se cierra sola. El "¡A la próxima serie!" en verde dura esos 2 s:
        // en un emulador lento puede no llegar a leerse, así que se anota pero no se exige (la regla la prueban los tests del
        // motor, EntrenoTest.descanso).
        val antes = SonidoDescanso.reproducciones
        while (segundos() > 20) p.tocar(etiqueta("descanso-menos"))
        p.esperar("sonó", ms = 40_000) { SonidoDescanso.reproducciones > antes }
        val alSonar = SystemClock.elapsedRealtime()
        val vioListo = try {
            "¡A la próxima serie!" in p.textosBajo(etiqueta("descanso-rotulo")) && !p.habilitado(etiqueta("descanso-saltar"))
        } catch (_: AssertionError) {
            false
        }
        println("Entreno: la barra verde del fin del descanso ${if (vioListo) "se vio" else "no llegó a leerse"}")
        p.esperarQueNoEste(etiqueta("descanso"), ms = 10_000)
        val cerro = SystemClock.elapsedRealtime() - alSonar
        assertTrue("se cerró a los $cerro ms de sonar", cerro < 8_000)
        assertEquals("sonó una sola vez", antes + 1, SonidoDescanso.reproducciones)
    }

    /** D11+: sin rutina publicada, "Todavía no hay rutina" (la de ejemplo es solo de la demo). */
    @Test
    fun sinRutinaTodaviaNoHayRutina() {
        servidor.respuestas["mypump_get_rutina_activa"] = "[]"
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-vacio"))
        p.nodo(texto("Todavía no hay rutina"))
        p.nodo(texto("Cuando Mati publique tu rutina, la vas a ver acá."))
        assertFalse(p.existe(etiqueta("entreno-cabecera")))
        assertFalse(p.existe(texto("Tirón A — Ancho")))
    }

    /** D11+ también con una rutina publicada sin un solo ejercicio (la web mostraba la de ejemplo). */
    @Test
    fun unaRutinaSinEjerciciosTampocoSeMuestra() {
        servidor.respuestas["mypump_get_rutina_activa"] =
            """[{"id":"r-vacia","version":1,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":8,"dias":[{"id":"d1","nombre":"Día A","bloques":[]}]}}]"""
        guardarCuenta()
        abrir()
        p.nodo(texto("Todavía no hay rutina"))
        assertFalse(p.existe(etiqueta("entreno-cabecera")))
    }

    /** SES-06 y SES-07: cerrar el día con notas (primero la cola, después `finalizar_sesion`) y reabrirlo al cargar otra serie. */
    @Test
    fun cerrarElDiaYReabrirlo() {
        rutinaDePrueba(semana = 2)
        p.nodo(texto("DÍA 1 · SEMANA 2 DE 4"))
        assertEquals(listOf("1 ejercicio"), p.textosBajo(etiqueta("entreno-cantidad")))
        p.tocar(etiqueta("ejercicio-press-d1-0"))
        fijarCarga("60")
        darOK()
        // ENT-17: con todo hecho, "¡Día completado!" (una vez) ofrece ir al día siguiente.
        p.nodo(etiqueta("pregunta"))
        p.nodo(texto("¡Día completado!"))
        p.nodo(texto("Buen trabajo. ¿Querés ir al siguiente día (Tirón)?"))
        p.nodo(texto("Ir a Tirón"))
        p.tocar(etiqueta("pregunta-no"))
        p.esperarQueNoEste(etiqueta("pregunta"))
        // Hecho el último, no hay "Siguiente" (D13): queda reabrir.
        p.nodo(etiqueta("reabrir-ejercicio"))
        assertFalse(p.existe(etiqueta("siguiente-ejercicio")))
        // Con el día completo no queda descanso (D23, 20-oct): no hay próxima serie que esperar.
        assertFalse("la última serie del día no deja descanso", p.existe(etiqueta("descanso-saltar")))
        assertFalse(p.existe(etiqueta("descanso-en-tarjeta")))
        // El ejercicio se abrió en la lista (15-oct): no hay página de la que volver.
        p.nodo(etiqueta("tarjeta-cierre"))
        p.nodo(texto("SESIÓN COMPLETA"))
        p.nodo(texto("1/1 ejercicios listos"))
        p.tocar(etiqueta("cerrar-sesion"))
        p.nodo(etiqueta("hoja-cerrar-dia"))
        assertEquals(listOf("SERIES", "Series", "1", "REPS", "Reps", "8", "VOLUMEN", "Volumen", "480 kg"), p.textosBajo(etiqueta("resumen-cierre")).take(9))
        assertFalse("con todo hecho no hay pendientes", p.existe(etiqueta("pendientes-cierre")))
        p.escribir(etiqueta("notas-sesion"), "Buena sesión")
        p.tocar(etiqueta("confirmar-cierre"))
        p.esperarQueNoEste(etiqueta("hoja-cerrar-dia"))
        val fin = p.esperar("cerró en el servidor") { servidor.a("mypump_finalizar_sesion").firstOrNull() }
        assertTrue(fin, fin.contains("\"p_sesion_id\":\"ses-prueba-1\"") && fin.contains("\"p_notas\":\"Buena sesión\""))
        // Primero la cola: la serie llegó antes del cierre.
        val orden = servidor.llamadas.map { it.funcion }
        assertTrue(orden.toString(), orden.indexOf("mypump_registrar_carga") in 0 until orden.indexOf("mypump_finalizar_sesion"))
        p.nodo(texto("DÍA CERRADO"))
        p.nodo(texto("Tu sesión de hoy quedó guardada."))
        assertEquals(listOf("Día cerrado esta semana"), p.textosBajo(etiqueta("entreno-cantidad")))
        p.nodo(texto("Día 1, Empuje, cerrado esta semana"))

        // SES-07: corregir una serie en el día cerrado reescribe esa serie en la misma sesión, sin desmarcarla.
        abrirEnLaLista("press-d1-0")
        p.tocar(etiqueta("fila-serie-1"))
        p.nodo(etiqueta("correccion-guardar"))
        p.tocar(etiqueta("reps-mas"))
        p.tocar(etiqueta("correccion-guardar"))
        p.esperarQueNoEste(etiqueta("correccion-guardar"))
        p.esperar("la serie corregida") { servidor.a("mypump_registrar_carga").any { it.contains("\"p_reps\":9") && it.contains("ses-prueba-1") } }
        assertTrue(p.descripcion(etiqueta("fila-serie-1")), p.descripcion(etiqueta("fila-serie-1")).contains("hecha: 9 repeticiones"))
        // "¡Día completado!" sale una sola vez por día.
        p.quieto(1_000)
        assertFalse(p.existe(etiqueta("pregunta")))
    }

    /** ENT-14 y ENT-15: avanzar de semana con la pregunta de la web, y en la última, empezar el bloque nuevo. */
    @Test
    fun avanzarDeSemanaYEmpezarElBloqueNuevo() {
        rutinaDePrueba(semana = 3)
        p.nodo(texto("DÍA 1 · SEMANA 3 DE 4"))
        p.tocar(etiqueta("avanzar-semana"))
        // Con el día incompleto, la confirmación lo dice.
        p.nodo(texto("Pasar a Semana 4"))
        p.nodo(texto("Todavía tenés ejercicios sin completar en la Semana 3. Si avanzás, la semana nueva empieza con progresión actualizada. ¿Continuar?"))
        p.nodo(texto("Pasar a SEM 4"))
        servidor.respuestas["mypump_get_rutina_activa"] = rutina(semana = 4, siguiente = true)
        p.tocar(etiqueta("pregunta-si"))
        p.nodo(texto("DÍA 1 · SEMANA 4 DE 4"))
        assertTrue(servidor.a("mypump_avanzar_semana").single().contains("\"p_semana_destino\":4"))
        // Última semana con otro bloque en cola: no hay a dónde avanzar, sí "Empezar bloque nuevo".
        assertFalse(p.existe(etiqueta("avanzar-semana")))
        p.nodo(texto("Terminaste tu plan. Tu próximo bloque ya está listo."))
        p.tocar(etiqueta("empezar-bloque"))
        p.nodo(texto("¡Nuevo bloque!"))
        servidor.respuestas["mypump_get_rutina_activa"] = rutina(semana = 1, siguiente = false, id = "r-bloque-2")
        p.tocar(etiqueta("pregunta-si"))
        p.nodo(texto("DÍA 1 · SEMANA 1 DE 4"))
        assertEquals(1, servidor.a("mypump_activar_siguiente").size)
        assertFalse(p.existe(etiqueta("empezar-bloque")))
        p.nodo(etiqueta("avanzar-semana"))
    }

    // ── La rutina de prueba ──

    private fun rutinaDePrueba(semana: Int) {
        servidor.respuestas["mypump_get_rutina_activa"] = rutina(semana)
        servidor.respuestas["mypump_get_historico_por_clave"] = "[]"
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-prueba-1\""
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
    }

    /** Dos días de un ejercicio con una serie, en 4 semanas. */
    private fun rutina(semana: Int, siguiente: Boolean = false, id: String = "r-prueba"): String {
        fun progresion(reps: String) = (1..4).joinToString(",") { """{"semana":$it,"series":1,"reps":"$reps","rir":"1"}""" }
        return """[{"id":"$id","version":1,"semana_actual":$semana,"tiene_siguiente":$siguiente,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1 — PECHO","ejercicios":[
              {"id":"press-d1-0","nombre":"Press banca plano con barra (pectoral)","tipo":"compuesto","descanso_segundos":120,"progresion":[${progresion("8")}]}]}]},
            {"id":"d2","n":2,"nombre":"TIRÓN","bloques":[{"titulo":"BLOQUE 1 — ESPALDA","ejercicios":[
              {"id":"remo-d2-0","nombre":"Remo con barra (dorsal)","tipo":"compuesto","descanso_segundos":120,"progresion":[${progresion("10")}]}]}]}
        ]}}]"""
    }

    /** Lo que queda del descanso, en segundos ("2:29" → 149). */
    private fun segundos(): Int {
        val t = p.textosBajo(etiqueta("descanso-tiempo")).single()
        val (m, s) = t.split(":").map { it.toInt() }
        return m * 60 + s
    }
}
