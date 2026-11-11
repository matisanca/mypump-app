package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.CheckGuiado.Borrador
import com.pumpteam.mypump.reglas.CheckGuiado.Catalogo
import com.pumpteam.mypump.reglas.CheckGuiado.Estado
import com.pumpteam.mypump.reglas.CheckGuiado.Paso
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** El check guiado contra los casos compartidos (`apps/shared/vectores/check_guiado.json`): iOS y la web dan lo mismo. */
class CheckGuiadoTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("check_guiado")))
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun casos(k: String) = lista(v[k])
    private fun textos(j: ValorJson?) = lista(j).map { it.comoTexto!! }
    private fun textosONull(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos?.map { it.comoTexto!! }
    private fun bool(j: ValorJson?) = j == ValorJson.Booleano(true)
    private fun cat(j: ValorJson?) = Catalogo.desde(j?.comoTexto)
    private fun mapa(j: ValorJson?) = (j as? ValorJson.Objeto)?.campos?.mapValues { it.value.comoTexto!! } ?: emptyMap()
    private fun mapaONull(j: ValorJson?) = (j as? ValorJson.Objeto)?.campos?.mapValues { it.value.comoTexto!! }
    private fun borrador(j: ValorJson?) = if (j == null || j == ValorJson.Nulo) null else Borrador.desde(j)!!

    @Test
    fun losCatalogosYLosTextosSonLosAcordados() {
        for ((nombre, esperado) in (v["catalogos"] as ValorJson.Objeto).campos) {
            if (nombre == "_") continue
            val o = CheckGuiado.opciones(Catalogo.desde(nombre)!!)
            assertEquals(lista(esperado).map { textos(it) }, o.map { listOf(it.clave, it.etiqueta) }, nombre)
            assertEquals(CheckGuiado.NINGUNO, o.last().clave)
        }
        val titulos = v["titulos"]!!
        val apoyos = v["apoyos"]!!
        val omitir = v["omitir"]!!
        for (p in Paso.entries) {
            if (p != Paso.SENALES) {
                assertEquals(titulos[p.clave]?.comoTexto, CheckGuiado.titulo(p))
                assertEquals(apoyos[p.clave]?.comoTexto, CheckGuiado.apoyo(p))
            }
            assertEquals(omitir[p.clave]?.comoTexto, CheckGuiado.omitir(p), p.clave)
        }
        for (c in Catalogo.entries) {
            assertEquals(titulos["senales"]!![c.clave]?.comoTexto, CheckGuiado.titulo(Paso.SENALES, c))
            assertEquals(apoyos["senales"]!![c.clave]?.comoTexto, CheckGuiado.apoyo(Paso.SENALES, c))
        }
        val tarjeta = v["tarjeta"]!!
        assertEquals(Estado.entries.size, (tarjeta as ValorJson.Objeto).campos.size)
        for (e in Estado.entries) {
            assertEquals(textos(tarjeta[e.clave]), listOf(CheckGuiado.textoTarjeta(e), CheckGuiado.botonTarjeta(e)))
        }
    }

    /** Reglas de producto: en ningún texto del check aparece IA, «tu coach», «tu entrenador» ni RIR. */
    @Test
    fun ningunTextoDiceLoQueNoSeDice() {
        val todos = ArrayList<String>()
        for (c in Catalogo.entries) {
            todos += CheckGuiado.opciones(c).map { it.etiqueta }
            for (p in Paso.entries) todos += listOf(CheckGuiado.titulo(p, c), CheckGuiado.apoyo(p, c), CheckGuiado.omitir(p) ?: "")
        }
        for (e in Estado.entries) todos += listOf(CheckGuiado.textoTarjeta(e), CheckGuiado.botonTarjeta(e))
        todos += CheckGuiado.AVISO_RANGO_PESO
        todos += CheckGuiado.INTENSIDADES.map { it.etiqueta } + CheckGuiado.ROTULO_INTENSIDAD + CheckGuiado.AVISO_INTENSIDAD
        for (t in todos) {
            val m = " ${t.lowercase()} "
            for (prohibido in listOf(" ia ", "inteligencia artificial", "coach", "entrenador", " rir", "esteroide", "testosterona", "anabólic")) {
                assertFalse(prohibido in m, "«$t» dice «$prohibido»")
            }
        }
    }

    @Test
    fun pasos() {
        for (c in casos("pasos")) assertEquals(textos(c["pasos"]), CheckGuiado.pasos(bool(c["faltanFotos"])).map { it.clave })
    }

    @Test
    fun alternarYNormalizar() {
        for (c in casos("alternar")) assertEquals(textos(c["queda"]), CheckGuiado.alternar(textos(c["senales"]), c["clave"]!!.comoTexto!!))
        for (c in casos("normalizar")) assertEquals(textos(c["queda"]), CheckGuiado.normalizar(textos(c["senales"]), cat(c["catalogo"])!!))
        for (c in casos("textoSenales")) {
            assertEquals(c["texto"]?.comoTexto, CheckGuiado.textoSenales(textos(c["senales"]), cat(c["catalogo"])!!, mapa(c["intensidades"])))
        }
    }

    /** v3: las digestivas se muestran solo con GLP-1, y cada efecto marcado lleva cuánto molesta. */
    @Test
    fun digestivasEIntensidades() {
        assertEquals(textos(v["digestivas"]), CheckGuiado.DIGESTIVAS)
        for (c in casos("opcionesCiclo")) {
            assertEquals(textos(c["claves"]), CheckGuiado.opciones(Catalogo.CICLO, bool(c["glp1"])).map { it.clave })
        }
        // La lista general no cambia con GLP-1.
        assertEquals(CheckGuiado.opciones(Catalogo.GENERAL), CheckGuiado.opciones(Catalogo.GENERAL, true))
        assertEquals(CheckGuiado.opciones(Catalogo.GENERAL), CheckGuiado.opciones(Catalogo.GENERAL, false))
        val i = v["intensidades"]!!
        assertEquals(lista(i["opciones"]).map { textos(it) }, CheckGuiado.INTENSIDADES.map { listOf(it.clave, it.etiqueta) })
        assertEquals(i["aviso"]?.comoTexto, CheckGuiado.AVISO_INTENSIDAD)
        casos("normalizarIntensidades").forEachIndexed { n, c ->
            val queda = CheckGuiado.normalizarIntensidades(textos(c["senales"]), mapa(c["intensidades"]), cat(c["catalogo"])!!)
            assertEquals(mapa(c["queda"]), queda, "caso $n")
            // Sale en el orden del catálogo (así el payload es el mismo en todas las plataformas).
            assertEquals(CheckGuiado.opciones(cat(c["catalogo"])!!).map { it.clave }.filter { it in queda }, queda.keys.toList(), "caso $n")
        }
        casos("faltaIntensidad").forEachIndexed { n, c -> assertEquals(bool(c["falta"]), CheckGuiado.faltaIntensidad(borrador(c["borrador"])!!), "caso $n") }
    }

    @Test
    fun puedeSeguirYQueFalta() {
        casos("puedeSeguir").forEachIndexed { i, c ->
            val p = Paso.desde(c["paso"]?.comoTexto)!!
            assertEquals(bool(c["puede"]), CheckGuiado.puedeSeguir(p, borrador(c["borrador"])!!, c["fotosHechas"]!!.comoNumero!!.toInt()), "caso $i")
        }
        casos("faltaParaEnviar").forEachIndexed { i, c ->
            val b = borrador(c["borrador"])!!
            assertEquals(c["falta"]?.comoTexto, CheckGuiado.faltaParaEnviar(b), "caso $i")
            assertEquals(c["paso"]?.comoTexto, CheckGuiado.pasoQueFalta(b)?.clave, "caso $i")
        }
    }

    @Test
    fun abrirRetomarYEstado() {
        for (c in casos("abrir")) {
            val e = (c["enviado"] as? ValorJson.Objeto)?.let { o ->
                CheckGuiado.Enviado((o["valores"] as ValorJson.Objeto).campos.mapValues { it.value.comoNumero!!.toInt() }, o["nota"]!!.comoTexto!!)
            }
            val r = CheckGuiado.abrir(borrador(c["guardado"]), c["semana"]!!.comoTexto!!, cat(c["catalogo"])!!, e, textosONull(c["senalesEnviadas"]), cat(c["catalogoEnviado"]), mapaONull(c["intensidadesEnviadas"]))
            assertEquals(borrador(c["queda"]), r, c["caso"]?.comoTexto)
        }
        for (c in casos("retomar")) {
            val b = Borrador(semana = "2026-11-09", paso = Paso.desde(c["paso"]?.comoTexto)!!)
            assertEquals(c["abre"]?.comoTexto, CheckGuiado.retomar(b, textos(c["pasos"]).map { Paso.desde(it)!! }).clave)
        }
        casos("estado").forEachIndexed { i, c ->
            val e = CheckGuiado.estado(bool(c["enviado"]), borrador(c["borrador"]), c["semana"]!!.comoTexto!!, bool(c["faltanFotos"]))
            assertEquals(c["estado"]?.comoTexto, e.clave, "caso $i")
        }
    }

    /** El borrador va y vuelve del disco sin perder nada, y uno roto no se retoma. */
    @Test
    fun elBorradorSeGuardaYSeLeeIgual() {
        val b = Borrador("2026-11-09", Paso.SENALES, "78,4", mapOf("energia" to 4, "descanso" to 3), Catalogo.CICLO, listOf("acne"), "hola\nchau", mapOf("acne" to "moderado"))
        assertEquals(b, Borrador.desde(ValorJson.parsear(b.aValor().serializar())))
        assertNull(Borrador.desde(ValorJson.parsear("""{"semana":"2026-11-09","paso":"inventado","peso":"","valores":{},"catalogo":"general","senales":[],"nota":""}""")))
        assertNull(Borrador.desde(ValorJson.Nulo))
        // Un borrador guardado antes de las intensidades (sin el campo) se retoma, con intensidades vacías.
        val viejo = Borrador.desde(ValorJson.parsear("""{"semana":"2026-11-09","paso":"senales","peso":"","valores":{},"catalogo":"ciclo","senales":["acne"],"nota":""}"""))
        assertEquals(Borrador("2026-11-09", Paso.SENALES, catalogo = Catalogo.CICLO, senales = listOf("acne")), viejo)
        // Los nombres de los casos son los que guarda iOS.
        assertEquals(listOf("peso", "escalas", "fotos", "senales", "nota", "resumen"), Paso.entries.map { it.clave })
    }
}
