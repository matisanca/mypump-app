package com.pumpteam.mypump.ui

import android.media.ExifInterface
import android.util.Base64
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.reglas.FechaLocal
import java.time.ZoneId
import java.util.TimeZone
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Dieta con escritura (DIE-08…18), gemela de `DietaUITests` de iOS y más: la mano, reemplazar y volver al del plan (que
 * sobrevive a reabrir la app), el alimento propio a mano y con la etiqueta escaneada, las comidas libres a mano y con la
 * foto del plato, la visión que falla, la recarga al cambiar el día y la demo. Con la cuenta del [ServidorDePrueba] (la
 * dieta grabada de `test-nativa-real`), que guarda lo que se escribe mientras dura la prueba y contesta la visión que
 * pide cada una: nunca va a la red ni gasta la IA. La cámara y el selector de fotos se reemplazan con un monitor que
 * contesta una foto armada acá, como en `RevisionUiTest`.
 */
@RunWith(AndroidJUnit4::class)
class DietaEscrituraUiTest : PruebaUi() {
    private val camaras = ArrayList<CamaraDePrueba>()
    private var zonaAntes: TimeZone? = null

    @After
    fun limpiarDieta() {
        for (c in camaras) c.soltar()
        camaras.clear()
        zonaAntes?.let(TimeZone::setDefault)
        zonaAntes = null
    }

    /** La cámara y el selector de fotos, de mentira: contestan una foto grande con ubicación, sin abrir nada. */
    private fun camara(): CamaraDePrueba = CamaraDePrueba(instr, app).also { camaras += it }

    private fun irADieta() {
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("dieta-cabecera"))
    }

    /**
     * Lleva un elemento de la lista de Dieta (por su clave: "1-c2", "comidas-libres", "pie") arriba, con la acción de la
     * semántica que usa un lector de pantalla: la lista es perezosa y lo de abajo no existe hasta llegar.
     */
    private fun irA(clave: String) {
        p.esperar("se llega a $clave") {
            val lista = p.nodo(etiqueta("dieta-lista"), ms = 0)
            val i = lista.config[SemanticsProperties.IndexForKey](clave)
            if (i < 0) null else lista.config[SemanticsActions.ScrollToIndex].action?.invoke(i)
        }
        p.quieto(400)
    }

    /**
     * Atrás del sistema desde "Alimento propio": vuelve a la lista sin cerrar la hoja. El nombre se enfoca al abrir, así
     * que si el teclado alcanzó a salir, el primer Atrás lo cierra (como en cualquier app) y hace falta otro.
     */
    private fun atrasALaLista() {
        p.atras()
        try {
            p.nodo(etiqueta("lista-sustitutos"), ms = 1_500)
        } catch (_: AssertionError) {
            p.atras()
        }
        p.nodo(etiqueta("lista-sustitutos"))
        p.esperarQueNoEste(etiqueta("crear-alimento-formulario"))
        assertTrue(p.existe(etiqueta("hoja-reemplazar")))
    }

    /** "Crear alimento personalizado", al pie de la lista de la hoja (después de las opciones). */
    private fun crearAlimento() {
        repeat(40) {
            if (p.existe(etiqueta("crear-alimento"))) {
                p.tocar(etiqueta("crear-alimento"))
                p.nodo(etiqueta("crear-alimento-formulario"))
                return
            }
            p.desplazar(etiqueta("lista-sustitutos"), 1_500f)
        }
        p.tocar(etiqueta("crear-alimento"), ms = 2_000)
    }

    /** La foto que llegó a la visión: tipo, medidas y si trae ubicación. */
    private fun fotoQueLlego(tipo: String): FotoDePrueba.Propiedades {
        val f = p.esperar("la foto llegó a la visión") { servidor.fotosVision.firstOrNull { it.tipo == tipo } }
        assertTrue(f.dataUrl.startsWith("data:image/jpeg;base64,"))
        return FotoDePrueba.propiedades(Base64.decode(f.dataUrl.substringAfter(","), Base64.DEFAULT))
    }

    private fun rpc(funcion: String): JSONObject = JSONObject(p.esperar("llegó $funcion") { servidor.a(funcion).lastOrNull() })

    // ── DIE-08: gemela de testLaManoMuestraYOcultaLaPorcionCasera ──

    @Test
    fun laManoMuestraYOcultaLaPorcionCasera() {
        guardarCuenta()
        abrir()
        irADieta()
        // Solo donde hay una equivalencia útil: la clara de huevo en gramos no tiene.
        assertEquals("Ver porción casera", p.textosBajo(etiqueta("mano-c1-0")).single())
        assertFalse(p.existe(etiqueta("mano-c1-1")))
        p.tocar(etiqueta("mano-c1-0"))
        p.nodo(texto("Porción casera: 2 huevos"))
        assertEquals("Ocultar porción casera", p.textosBajo(etiqueta("mano-c1-0")).single())
        // Otra mano abierta a la vez: cada alimento tiene la suya.
        p.tocar(etiqueta("mano-c1-2"))
        p.nodo(texto("Porción casera: 4 rebanadas"))
        p.nodo(texto("Porción casera: 2 huevos"))
        p.tocar(etiqueta("mano-c1-0"))
        p.esperarQueNoEste(texto("Porción casera: 2 huevos"))
        assertEquals("Ver porción casera", p.textosBajo(etiqueta("mano-c1-0")).single())
        p.nodo(texto("Porción casera: 4 rebanadas"))
        // La de otra opción es otra fila: al cambiar a la B no queda nada abierto.
        p.tocar(etiqueta("opcion-c1-1"))
        p.esperarQueNoEste(texto("Porción casera: 4 rebanadas"))
    }

    // ── DIE-09/10/11/13: gemela de testReemplazarUnAlimentoYVolverAlDelPlan ──

    @Test
    fun reemplazarUnAlimentoYVolverAlDelPlan() {
        guardarCuenta()
        abrir().also {
            irADieta()
            // DIE-09: el botón está en lo sustituible.
            assertEquals("Reemplazar Huevo entero", p.textosBajo(etiqueta("reemplazar-c1-0")).single())
            p.tocar(etiqueta("reemplazar-c1-0"))
            p.nodo(etiqueta("hoja-reemplazar"))
            assertEquals(listOf("Huevo entero", "2 unidades · 172 kcal", "P 15,1  ·  C 0,8  ·  G 11,4"), p.textosBajo(etiqueta("reemplazas")))
            // DIE-10: las mismas 55 opciones que la web para el huevo, los 🌍 arriba con el nombre en inglés.
            p.nodo(texto("55 de 55 · proteínas"))
            p.nodo(texto("🌍 Disponibles en cualquier país"))
            assertFalse(p.habilitado(etiqueta("confirmar-reemplazo")))
            p.nodo(texto("Elegí un alimento"))
            val primero = p.textosBajo(etiqueta("sustituto"))
            assertEquals(listOf("Muslo de pollo con piel", "Chicken thigh", "90 g · 173 kcal", "P 16,3  ·  C 0  ·  G 11,3", "más 1 por ciento de calorías"), primero.take(4) + primero.last())
            p.tocar(etiqueta("sustituto"))
            p.nodo(texto("Reemplazar por Muslo de pollo con piel"))
            assertTrue(p.habilitado(etiqueta("confirmar-reemplazo")))
            p.tocar(etiqueta("confirmar-reemplazo"))
            p.esperarQueNoEste(etiqueta("hoja-reemplazar"))
            // La fila muestra el reemplazo con su marca, y sale por la cola anclado al del plan (DIE-11, DIE-13).
            p.nodo(texto("Reemplazado. Tocá para volver a Huevo entero"))
            assertEquals("Muslo de pollo con piel", p.textosBajo(etiqueta("alimento-c1-0")).first())
            assertTrue("90 g · 173 kcal" in p.textosBajo(etiqueta("alimento-c1-0")))
            val guardado = p.esperar("el reemplazo en el servidor") { servidor.reemplazosGuardados()["c1|0|0"] }
            assertEquals("Muslo de pollo con piel", guardado.getString("name"))
            assertEquals(173.0, guardado.getDouble("kcal"), 0.0)
            assertEquals(90.0, guardado.getDouble("qty"), 0.0)
            assertTrue(guardado.getBoolean("_universal"))
            assertEquals("Chicken thigh", guardado.getString("_en"))
            val ancla = guardado.getJSONObject("_orig")
            assertEquals(listOf("Huevo entero", "2", "unidad"), listOf(ancla.getString("name"), ancla.get("qty").toString(), ancla.getString("unit")))
        }.close()

        // Sobrevive a cerrar y abrir la app: lo trae el servidor.
        abrir()
        irADieta()
        p.nodo(texto("Reemplazado. Tocá para volver a Huevo entero"))
        p.tocar(texto("Reemplazado. Tocá para volver a Huevo entero"))
        p.nodo(texto("¿Volver al alimento del plan?"))
        p.nodo(texto("Hoy estás comiendo Muslo de pollo con piel."))
        p.tocar(texto("Volver a Huevo entero"))
        p.esperarQueNoEste(texto("Reemplazado. Tocá para volver a Huevo entero"))
        assertEquals("Huevo entero", p.textosBajo(etiqueta("alimento-c1-0")).first())
        p.esperar("se borró en el servidor") { servidor.reemplazosGuardados().isEmpty() && servidor.a("mypump_delete_food_swap").isNotEmpty() }
    }

    @Test
    fun laBusquedaFiltraYCancelarNoReemplaza() {
        guardarCuenta()
        abrir()
        irADieta()
        irA("1-c2")
        p.tocar(etiqueta("reemplazar-c2-0"))   // Pechuga de pollo (cruda)
        p.nodo(texto("55 de 55 · proteínas"))
        p.escribir(etiqueta("buscar-alimento"), "merluza")
        p.nodo(texto("1 de 55 · proteínas"))
        assertEquals("Merluza", p.textosBajo(etiqueta("sustituto")).first())
        p.escribir(etiqueta("buscar-alimento"), "tofu")
        p.nodo(texto("0 de 55 · proteínas"))
        p.nodo(texto("Sin resultados para “tofu”"))
        p.nodo(texto("Probá con otro nombre o creá tu alimento personalizado."))
        p.tocar(etiqueta("cancelar-reemplazo"))
        p.esperarQueNoEste(etiqueta("hoja-reemplazar"))
        assertEquals("Pechuga de pollo (cruda)", p.textosBajo(etiqueta("alimento-c2-0")).first())
        assertTrue(servidor.a("mypump_save_food_swap").isEmpty())
    }

    /** DIE-10: las restricciones del cliente (`mypump_cliente_prefs.excluir`) sacan lo que no come de las opciones. */
    @Test
    fun lasRestriccionesDelClienteSacanLoQueNoCome() {
        servidor.respuestas["mypump_get_cliente_prefs"] = """[{"excluir":["cerdo","mariscos","lacteos"],"idioma":"es"}]"""
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("reemplazar-c1-0"))
        p.nodo(texto("51 de 51 · proteínas"))
        p.escribir(etiqueta("buscar-alimento"), "ricota")
        p.nodo(texto("0 de 51 · proteínas"))
        p.escribir(etiqueta("buscar-alimento"), "cerdo")
        p.nodo(texto("0 de 51 · proteínas"))
    }

    /**
     * DIE-09: sin reemplazo los condimentos y lo que Mati marcó `swappable: false`; y el aviso del motor cuando los datos
     * del alimento parecen mal cargados (1.200 kcal en 100 g de pollo).
     */
    @Test
    fun soloSeReemplazaLoSustituibleYLosAvisosDelMotorSeVen() {
        servidor.respuestas["mypump_get_dieta_activa"] = """[{"id":"dieta-avisos","version":1,"estructura":{"comidas":[{"id":"c1","name":"Almuerzo","options":[{"name":"A","foods":[
            {"name":"Pechuga de pollo","qty":100,"unit":"g","kcal":1200,"prot":30,"carb":0,"fat":3},
            {"name":"Mostaza","qty":10,"unit":"g","kcal":7,"prot":0.4,"carb":0.6,"fat":0.4},
            {"name":"Avena","qty":50,"unit":"g","kcal":190,"prot":6.5,"carb":33,"fat":3.5,"swappable":false}]}]}]}}]"""
        guardarCuenta()
        abrir()
        irADieta()
        p.nodo(etiqueta("alimento-c1-2"))
        assertTrue(p.existe(etiqueta("reemplazar-c1-0")))
        assertFalse("un condimento no se reemplaza", p.existe(etiqueta("reemplazar-c1-1")))
        assertFalse("swappable: false no se reemplaza", p.existe(etiqueta("reemplazar-c1-2")))
        // La mano sigue estando aunque no se pueda reemplazar.
        assertTrue(p.existe(etiqueta("mano-c1-2")))
        p.tocar(etiqueta("reemplazar-c1-0"))
        p.nodo(texto("Los datos de este alimento parecen incorrectos: avisale a Mati así lo corrige."))
    }

    // ── DIE-14: el alimento propio ──

    @Test
    fun unAlimentoPropioSeCreaYSeUsa() {
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("reemplazar-c1-0"))
        crearAlimento()
        p.nodo(texto("Alimento propio"))
        // Con cuenta se puede escanear la etiqueta.
        p.nodo(etiqueta("escanear-etiqueta"))
        assertFalse(p.habilitado(etiqueta("crear-y-usar")))
        // Atrás vuelve a la lista sin cerrar la hoja.
        atrasALaLista()
        p.nodo(texto("55 de 55 · proteínas"))
        crearAlimento()
        p.escribir(etiqueta("nombre-alimento"), "Tofu firme prueba")
        // Por rebanada: sin los gramos no se puede.
        p.tocar(etiqueta("unidad"))
        p.tocar(etiqueta("unidad-rebanada"))
        p.nodo(texto("Cuánto pesa 1 rebanada en gramos (sirve para la medida casera)."))
        p.escribir(etiqueta("kcal-alimento"), "43,2")
        p.escribir(etiqueta("prot-alimento"), "4,74")
        p.escribir(etiqueta("carb-alimento"), "0,84")
        p.escribir(etiqueta("fat-alimento"), "2,61")
        p.tocar(etiqueta("crear-y-usar"))
        p.nodo(texto("Para \"rebanada\" indicá cuánto pesa 1 rebanada en gramos."))
        assertTrue(servidor.a("mypump_create_custom_food").isEmpty())
        p.escribir(etiqueta("gramos-por-unidad"), "30")
        p.nodo(textoQueContiene("Poné los valores de 1 rebanada (30 g), lo que realmente comés."))
        p.tocar(etiqueta("crear-y-usar"))
        // Se guarda por 100 g (DIE-14) con la categoría del que se reemplaza, y se aplica de una ("Crear y usar").
        val creado = rpc("mypump_create_custom_food")
        assertEquals("Tofu firme prueba", creado.getString("p_name"))
        assertEquals(144.0, creado.getDouble("p_kcal"), 0.0)
        assertEquals(15.8, creado.getDouble("p_prot"), 0.0)
        assertEquals(2.8, creado.getDouble("p_carb"), 0.0)
        assertEquals(8.7, creado.getDouble("p_fat"), 0.0)
        assertEquals("rebanada", creado.getString("p_unit"))
        assertEquals(30.0, creado.getDouble("p_unit_grams"), 0.0)
        assertEquals("proteina", creado.getString("p_category"))
        p.esperarQueNoEste(etiqueta("hoja-reemplazar"))
        p.nodo(texto("Reemplazado. Tocá para volver a Huevo entero"))
        assertEquals("Tofu firme prueba", p.textosBajo(etiqueta("alimento-c1-0")).first())
        val guardado = p.esperar("el reemplazo en el servidor") { servidor.reemplazosGuardados()["c1|0|0"] }
        assertEquals("Tofu firme prueba", guardado.getString("name"))
        assertTrue(guardado.getBoolean("_isCustom"))
        assertEquals("rebanada", guardado.getString("unit"))
        // Queda para los demás reemplazos, con su estrella.
        p.tocar(etiqueta("reemplazar-c1-1"))
        p.nodo(texto("56 de 56 · proteínas"))
        p.escribir(etiqueta("buscar-alimento"), "tofu")
        p.nodo(texto("★ Tuyo"))
    }

    @Test
    fun laEtiquetaEscaneadaPrellenaElAlimento() {
        servidor.vision = { tipo ->
            if (tipo == "etiqueta") {
                200 to """{"ok":true,"data":{"nombre":"Tofu firme","porcion_g":30,"kcal":43,"prot":4.7,"carb":0.8,"fat":2.6,"confianza":"alta"}}"""
            } else {
                500 to """{"ok":false,"error":"tipo inesperado"}"""
            }
        }
        val pedidos = camara().pedidos
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("reemplazar-c1-0"))
        crearAlimento()
        p.tocar(etiqueta("escanear-etiqueta"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("✓ Etiqueta leída. Revisá los valores y tocá \"Crear y usar\"."), ms = 30_000)
        assertEquals(1, pedidos.size)
        // A la IA va reducida (1.600 px de lado mayor) y sin la ubicación.
        val foto = fotoQueLlego("etiqueta")
        assertEquals(1600 to 1200, foto.ancho to foto.alto)
        assertNull(foto.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        // Todo prellenado y editable: una porción de 30 g, con los valores de esa porción.
        assertEquals("Tofu firme", p.textoDe(etiqueta("nombre-alimento")))
        assertEquals(listOf("43", "4,7", "0,8", "2,6"), listOf("kcal", "prot", "carb", "fat").map { p.textoDe(etiqueta("$it-alimento")) })
        assertEquals("porción", p.estado(etiqueta("unidad")))
        assertEquals("30", p.textoDe(etiqueta("gramos-por-unidad")))
        p.tocar(etiqueta("crear-y-usar"))
        val creado = rpc("mypump_create_custom_food")
        assertEquals(listOf(143.0, 15.7, 2.7, 8.7), listOf("p_kcal", "p_prot", "p_carb", "p_fat").map(creado::getDouble))
        assertEquals("porcion", creado.getString("p_unit"))
        assertEquals(30.0, creado.getDouble("p_unit_grams"), 0.0)
        p.nodo(texto("Reemplazado. Tocá para volver a Huevo entero"))
    }

    @Test
    fun unaEtiquetaQueNoSeLeeLoDiceYDejaCargarAMano() {
        servidor.vision = { 502 to """{"ok":false,"error":"no se pudo interpretar la foto, probá con más luz"}""" }
        camara()
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("reemplazar-c1-0"))
        crearAlimento()
        p.tocar(etiqueta("escanear-etiqueta"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("⚠ No pudimos leer la foto (no se pudo interpretar la foto, probá con más luz). Cargalo a mano o probá otra foto con más luz."), ms = 30_000)
        assertEquals("", p.textoDe(etiqueta("nombre-alimento")))
        // Con la confianza baja también avisa, pero prellena.
        servidor.vision = { 200 to """{"ok":true,"data":{"nombre":"Barrita","porcion_g":100,"kcal":380,"prot":10,"carb":60,"fat":12,"confianza":"baja"}}""" }
        p.tocar(etiqueta("escanear-etiqueta"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("⚠ La etiqueta se leyó con poca claridad: revisá los valores antes de guardar."), ms = 30_000)
        assertEquals("Barrita", p.textoDe(etiqueta("nombre-alimento")))
        // Por 100 g: queda en gramos.
        assertEquals("gramos (g)", p.estado(etiqueta("unidad")))
        assertFalse(p.existe(etiqueta("gramos-por-unidad")))
    }

    // ── DIE-15: gemela de testComidaLibreAManoSeRegistraYSeBorra ──

    @Test
    fun comidaLibreAManoSeRegistraYSeBorra() {
        guardarCuenta()
        abrir()
        irADieta()
        irA("comidas-libres")
        p.nodo(texto("Comidas libres"))
        p.nodo(texto("Lo que comiste fuera del plan"))
        p.tocar(etiqueta("a-mano"))
        p.nodo(etiqueta("hoja-comida-libre"))
        p.nodo(texto("Comida libre"))
        // Lo que pide la web antes de guardar.
        p.tocar(etiqueta("registrar-comida-libre"))
        p.nodo(texto("Contá qué comiste."))
        p.escribir(etiqueta("descripcion-comida-libre"), "Prueba UI alfajor")
        p.tocar(etiqueta("registrar-comida-libre"))
        p.nodo(texto("Cargá al menos las calorías o algún macro."))
        p.escribir(etiqueta("kcal-comida-libre"), "250")
        p.tocar(etiqueta("registrar-comida-libre"))
        p.esperarQueNoEste(etiqueta("hoja-comida-libre"))
        p.nodo(texto("Prueba UI alfajor"))
        p.nodo(texto("250 kcal"))
        // Con la fecha y la hora locales (DIE-19), sin detalle (no hubo foto).
        val creada = rpc("mypump_crear_comida_libre")
        assertEquals(FechaLocal.hoy(), creada.getString("p_fecha"))
        assertTrue(Regex("\\d\\d:\\d\\d").matches(creada.getString("p_hora")))
        assertEquals(250.0, creada.getDouble("p_kcal"), 0.0)
        assertTrue(creada.isNull("p_detalle"))
        val id = servidor.comidasLibresGuardadas().single().getString("id")
        p.tocar(texto("Borrar Prueba UI alfajor"))
        p.esperarQueNoEste(texto("Prueba UI alfajor"))
        assertEquals(id, rpc("mypump_borrar_comida_libre").getString("p_id"))
        assertTrue(servidor.comidasLibresGuardadas().isEmpty())
    }

    /** Borrar es optimista (se va en el acto) y, si el servidor no contesta bien, la comida vuelve (DIE-15). */
    @Test
    fun siBorrarFallaLaComidaVuelve() {
        servidor.ponerComidaLibre(FechaLocal.hoy(), "Prueba UI medialunas", 300.0, prot = 6.0, carb = 40.0, fat = 12.0, hora = "09:30")
        servidor.borrarComidaLibreFalla = true
        guardarCuenta()
        abrir()
        irADieta()
        irA("comidas-libres")
        p.nodo(texto("Prueba UI medialunas"))
        p.nodo(texto("09:30"))
        p.nodo(texto("300 kcal"))
        servidor.demoraMs = 2_500
        p.tocar(texto("Borrar Prueba UI medialunas"))
        p.esperarQueNoEste(texto("Prueba UI medialunas"), ms = 2_000)
        p.nodo(texto("Prueba UI medialunas"), ms = 15_000)
        servidor.demoraMs = 0
        assertEquals(1, servidor.a("mypump_borrar_comida_libre").size)
        assertEquals(1, servidor.comidasLibresGuardadas().size)
    }

    // ── DIE-15/16: la foto del plato ──

    @Test
    fun laFotoDelPlatoSeEstimaSeCorrigeYSeRegistra() {
        servidor.vision = { tipo ->
            // La IA tarda: se tiene que ver que está mirando.
            Thread.sleep(1_500)
            if (tipo == "plato") 200 to PLATO else 500 to """{"ok":false,"error":"tipo inesperado"}"""
        }
        camara()
        guardarCuenta()
        abrir()
        irADieta()
        irA("comidas-libres")
        p.tocar(etiqueta("con-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("Analizando el plato…"))
        p.nodo(texto("Puede tardar unos 30 segundos."))
        p.nodo(etiqueta("hoja-comida-libre"), ms = 30_000)
        p.esperarQueNoEste(texto("Analizando el plato…"))
        // A la IA va reducida (1.280 px) y sin la ubicación.
        val foto = fotoQueLlego("plato")
        assertEquals(1280 to 960, foto.ancho to foto.alto)
        assertNull(foto.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        p.nodo(texto("Revisá la estimación"))
        p.nodo(texto("La IA estimó esto de tu foto. Es un estimativo: corregí lo que haga falta."))
        p.nodo(texto("📐 plato playo 26 cm, tenedor de referencia"))
        assertFalse(p.existe(etiqueta("confianza-baja")))
        assertEquals("Milanesa con puré", p.textoDe(etiqueta("descripcion-comida-libre")))
        assertEquals(listOf("150", "200"), listOf(p.textoDe(etiqueta("gramos-0")), p.textoDe(etiqueta("gramos-1"))))
        assertEquals(listOf("510", "31", "45", "23"), listOf("kcal", "prot", "carb", "fat").map { p.textoDe(etiqueta("$it-comida-libre")) })
        // Corregir los gramos re-escala ese alimento y los totales.
        p.escribir(etiqueta("gramos-0"), "300")
        p.esperar("se recalcularon los totales") { p.textoDe(etiqueta("kcal-comida-libre")) == "840" }
        assertEquals(listOf("58", "60", "41"), listOf("prot", "carb", "fat").map { p.textoDe(etiqueta("$it-comida-libre")) })
        p.tocar(etiqueta("registrar-comida-libre"))
        p.esperarQueNoEste(etiqueta("hoja-comida-libre"))
        p.nodo(texto("Milanesa con puré"))
        p.nodo(texto("840 kcal"))
        val creada = rpc("mypump_crear_comida_libre")
        assertEquals(840.0, creada.getDouble("p_kcal"), 0.0)
        // El detalle guarda los gramos corregidos, con sus macros re-escalados, la confianza y la escala.
        val detalle = creada.getJSONObject("p_detalle")
        val milanesa = detalle.getJSONArray("alimentos").getJSONObject(0)
        assertEquals(listOf("Milanesa de carne", "300", "660"), listOf(milanesa.getString("nombre"), milanesa.get("gramos").toString(), milanesa.get("kcal").toString()))
        assertEquals("media", detalle.getString("confianza"))
        assertEquals("plato playo 26 cm, tenedor de referencia", detalle.getString("escala"))
    }

    @Test
    fun siLaVisionFallaAvisaYDejaCargarAMano() {
        servidor.vision = { 502 to """{"ok":false,"error":"no se pudo interpretar la foto, probá con más luz"}""" }
        camara()
        guardarCuenta()
        abrir()
        irADieta()
        irA("comidas-libres")
        p.tocar(etiqueta("con-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("No pudimos leer la foto"), ms = 30_000)
        p.nodo(texto("no se pudo interpretar la foto, probá con más luz. Podés cargarla a mano."))
        p.tocar(etiqueta("cargar-a-mano"))
        p.nodo(texto("Comida libre"))
        assertEquals("", p.textoDe(etiqueta("descripcion-comida-libre")))
        assertFalse(p.existe(etiqueta("gramos-0")))
        p.tocar(etiqueta("cancelar-comida-libre"))
        p.esperarQueNoEste(etiqueta("hoja-comida-libre"))
        // Sin señal también lo dice, con el motivo.
        servidor.sinRed = true
        p.tocar(etiqueta("con-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("sin conexión. Podés cargarla a mano."), ms = 30_000)
        p.tocar(etiqueta("cancelar-foto"))
        p.esperarQueNoEste(texto("No pudimos leer la foto"))
        assertFalse(p.existe(etiqueta("hoja-comida-libre")))
    }

    /**
     * La IA tarda (~30 s) y gasta cupo: si mientras mira el plato el cliente se va a otra pestaña, la estimación lo espera
     * al volver (antes la pantalla se descartaba con su estado y la respuesta se perdía).
     */
    @Test
    fun laFotoDelPlatoNoSePierdeAlCambiarDePestana() {
        servidor.vision = { tipo ->
            Thread.sleep(3_000)
            if (tipo == "plato") 200 to PLATO else 500 to """{"ok":false,"error":"tipo inesperado"}"""
        }
        camara()
        guardarCuenta()
        abrir()
        irADieta()
        irA("comidas-libres")
        p.tocar(etiqueta("con-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("Analizando el plato…"))
        p.tocar(etiqueta("pestana-entreno"))
        p.esperarQueNoEste(etiqueta("dieta-cabecera"))
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("hoja-comida-libre"), ms = 30_000)
        p.nodo(texto("Revisá la estimación"))
        assertEquals("Milanesa con puré", p.textoDe(etiqueta("descripcion-comida-libre")))
        assertEquals(1, servidor.fotosVision.size)
    }

    /** Lo mismo con la etiqueta y el teléfono que gira mientras la IA la lee: el formulario vuelve y se completa. */
    @Test
    fun laEtiquetaNoSePierdeAlGirarElTelefono() {
        servidor.vision = {
            Thread.sleep(3_000)
            200 to """{"ok":true,"data":{"nombre":"Tofu firme","porcion_g":100,"kcal":144,"prot":15.8,"carb":2.8,"fat":8.7,"confianza":"alta"}}"""
        }
        camara()
        guardarCuenta()
        val e = abrir()
        irADieta()
        p.tocar(etiqueta("reemplazar-c1-0"))
        crearAlimento()
        p.tocar(etiqueta("escanear-etiqueta"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("Leyendo la etiqueta…"))
        e.recreate()
        p.nodo(etiqueta("crear-alimento-formulario"))
        p.nodo(texto("✓ Etiqueta leída. Revisá los valores y tocá \"Crear y usar\"."), ms = 30_000)
        assertEquals("Tofu firme", p.textoDe(etiqueta("nombre-alimento")))
        assertEquals("144", p.textoDe(etiqueta("kcal-alimento")))
        assertEquals(1, servidor.fotosVision.size)
    }

    /** Salir del formulario mientras la IA lee la etiqueta la olvida: lo que llega tarde no prellena el próximo alimento. */
    @Test
    fun unaEtiquetaQueLlegaDespuesDeSalirNoSeUsa() {
        servidor.vision = {
            Thread.sleep(3_000)
            200 to """{"ok":true,"data":{"nombre":"Tofu firme","porcion_g":100,"kcal":144,"prot":15.8,"carb":2.8,"fat":8.7,"confianza":"alta"}}"""
        }
        camara()
        guardarCuenta()
        abrir()
        irADieta()
        p.tocar(etiqueta("reemplazar-c1-0"))
        crearAlimento()
        p.tocar(etiqueta("escanear-etiqueta"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("Leyendo la etiqueta…"))
        // Atrás: a la lista (la lectura sigue en camino y llega mientras tanto).
        p.atras()
        p.nodo(etiqueta("lista-sustitutos"))
        p.esperar("la visión contestó") { servidor.fotosVision.isNotEmpty() }
        p.quieto(4_000)
        crearAlimento()
        assertEquals("", p.textoDe(etiqueta("nombre-alimento")))
        assertFalse(p.existe(etiqueta("estado-escaneo")))
        assertFalse(p.existe(texto("Leyendo la etiqueta…")))
    }

    // ── DIE-18: al volver con otro día, se recargan las comidas libres ──

    @Test
    fun alVolverConOtroDiaSeRecarganLasComidasLibres() {
        // El "hoy" local es el del teléfono: de UTC−12 a UTC+14 siempre es otro día (26 h de diferencia).
        zonaAntes = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("Etc/GMT+12"))
        val diaViejo = FechaLocal.hoy()
        val diaNuevo = FechaLocal.hoy(zona = ZoneId.of("Etc/GMT-14"))
        assertTrue(diaViejo != diaNuevo)
        servidor.ponerComidaLibre(diaViejo, "Prueba UI del día viejo", 200.0)
        servidor.ponerComidaLibre(diaNuevo, "Prueba UI del día nuevo", 300.0)
        guardarCuenta()
        val e = abrir()
        irADieta()
        irA("comidas-libres")
        p.nodo(texto("Prueba UI del día viejo"))
        assertFalse(p.existe(texto("Prueba UI del día nuevo")))
        // Que termine la carga entera (ahí se anota el día cargado).
        p.esperar("la carga terminó") { servidor.a("mypump_get_fotos_progreso").isNotEmpty() }
        servidorQuieto()
        TimeZone.setDefault(TimeZone.getTimeZone("Etc/GMT-14"))
        e.moveToState(Lifecycle.State.CREATED)
        e.moveToState(Lifecycle.State.RESUMED)
        p.nodo(texto("Prueba UI del día nuevo"))
        p.esperarQueNoEste(texto("Prueba UI del día viejo"))
        assertTrue(servidor.a("mypump_get_comidas_libres").last().contains("\"p_fecha\":\"$diaNuevo\""))
        // Volver el mismo día no las vuelve a pedir.
        val pedidas = servidor.a("mypump_get_comidas_libres").size
        e.moveToState(Lifecycle.State.CREATED)
        e.moveToState(Lifecycle.State.RESUMED)
        p.quieto(1_500)
        assertEquals(pedidas, servidor.a("mypump_get_comidas_libres").size)
    }

    /** Hasta que el servidor de prueba deja de recibir pedidos un rato. */
    private fun servidorQuieto() {
        var antes = -1
        p.esperar("el servidor quieto", ms = 20_000, enElPrincipal = false) {
            val ahora = servidor.llamadas.size
            if (ahora == antes) {
                true
            } else {
                antes = ahora
                Thread.sleep(1_200)
                null
            }
        }
    }

    // ── La demo: se reemplaza en memoria, sin comidas libres ni IA ──

    @Test
    fun enLaDemoSeReemplazaSinEscribirYNoHayComidasLibres() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        irADieta()
        p.tocar(etiqueta("mano-c1-0"))
        p.nodo(texto("Porción casera: 1¼ tazas"))
        p.tocar(etiqueta("reemplazar-c1-0"))
        p.nodo(etiqueta("hoja-reemplazar"))
        val nombre = p.textosBajo(etiqueta("sustituto")).first()
        p.tocar(etiqueta("sustituto"))
        p.tocar(etiqueta("confirmar-reemplazo"))
        p.esperarQueNoEste(etiqueta("hoja-reemplazar"))
        p.nodo(texto("Reemplazado. Tocá para volver a Avena en copos"))
        assertEquals(nombre, p.textosBajo(etiqueta("alimento-c1-0")).first())
        // Sin cuenta no hay escaneo de etiqueta (no hay IA) …
        p.tocar(etiqueta("reemplazar-c1-1"))
        crearAlimento()
        p.nodo(texto("Alimento propio"))
        assertFalse(p.existe(etiqueta("escanear-etiqueta")))
        // La flecha de volver también vuelve a la lista.
        p.tocar(etiqueta("volver-a-reemplazos"))
        p.nodo(etiqueta("lista-sustitutos"))
        p.tocar(etiqueta("cancelar-reemplazo"))
        p.esperarQueNoEste(etiqueta("hoja-reemplazar"))
        // … ni comidas libres: al pie está el respaldo.
        irA("pie")
        p.nodo(etiqueta("respaldo-cientifico"))
        assertFalse(p.existe(etiqueta("comidas-libres")))
        // Y nada salió a la red.
        assertTrue(servidor.llamadas.isEmpty())
    }

    companion object {
        /** Lo que contesta mini-vision para un plato (la forma de `PROMPTS.plato`). */
        const val PLATO = """{"ok":true,"data":{"descripcion":"Milanesa con puré","escala":"plato playo 26 cm, tenedor de referencia","alimentos":[{"nombre":"Milanesa de carne","gramos":150,"kcal":330,"prot":27,"carb":15,"fat":18},{"nombre":"Puré de papas","gramos":200,"kcal":180,"prot":4,"carb":30,"fat":5}],"kcal":510,"prot":31,"carb":45,"fat":23,"confianza":"media"}}"""
    }
}
