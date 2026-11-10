package com.pumpteam.mypump.ui

import androidx.exifinterface.media.ExifInterface
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.DobleGimnasio
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.modelos.ValorJson
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Gimnasio por fotos contra el doble del servidor (sin red). Lo fino de la cola está en `GimnasioTest`; acá, la pantalla de verdad. */
@RunWith(AndroidJUnit4::class)
class GimnasioUiTest : PruebaUi() {
    private var camara: CamaraDePrueba? = null

    @After
    fun soltar() {
        camara?.soltar()
        Telefono.shell("settings put system font_scale 1.0")
    }

    private fun lanzar(escenario: String): DobleGimnasio {
        val d = DobleGimnasio.escenario(escenario)
        usar(d)
        guardarCuenta()
        camara = camara ?: CamaraDePrueba(instr, app)
        abrir()
        return d
    }

    private fun usar(d: DobleGimnasio) {
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("gimnasio" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
    }

    private fun agregarFoto(cuantasDebeHaber: Int) {
        p.tocar(etiqueta("gimnasio-agregar-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.esperar("la foto en la zona", 30_000) { p.cuantos(etiqueta("gimnasio-borrar-foto")).takeIf { it == cuantasDebeHaber } }
    }

    private fun fotoEn(zona: String) {
        p.tocar(etiqueta("gimnasio-zona-$zona"))
        p.nodo(etiqueta("gimnasio-consejo"))
        agregarFoto(1)
        p.atras()
        p.nodo(etiqueta("gimnasio-revisar"))
    }

    private fun noHayEn(zona: String) {
        p.tocar(etiqueta("gimnasio-zona-$zona"))
        p.tocar(etiqueta("gimnasio-no-hay"))
        p.atras()
        p.nodo(etiqueta("gimnasio-revisar"))
    }

    private fun recorridoCompleto(tema: String): DobleGimnasio {
        val d = lanzar("vacio")
        p.nodo(etiqueta("gimnasio-tarjeta"))
        Telefono.captura("gim-tarjeta-$tema")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.nodo(etiqueta("gimnasio-aviso"))
        Telefono.captura("gim-inicio-$tema")
        p.tocar(etiqueta("gimnasio-empezar"))
        p.nodo(etiqueta("gimnasio-zona-poleas"))
        p.nodo(texto("Te faltan 9 zonas"))
        Telefono.captura("gim-zonas-$tema")
        p.tocar(etiqueta("gimnasio-zona-poleas"))
        p.nodo(etiqueta("gimnasio-consejo"))
        agregarFoto(1)
        Telefono.captura("gim-zona-$tema")
        p.atras()
        p.nodo(etiqueta("gimnasio-revisar"))
        for (z in listOf("accesorios_polea", "piernas", "empuje", "tiron", "barras_racks", "discos", "mancuernas")) fotoEn(z)
        noHayEn("bancos")
        p.tocar(etiqueta("gimnasio-revisar"))
        p.nodo(etiqueta("gimnasio-enviar"))
        p.escribir(etiqueta("gimnasio-nota"), "Hay una polea nueva")
        Telefono.captura("gim-revisar-$tema")
        p.tocar(etiqueta("gimnasio-enviar"))
        p.nodo(etiqueta("gimnasio-recibido"), ms = 30_000)
        Telefono.captura("gim-recibido-$tema")
        return d
    }

    @Test
    fun envioCompleto() {
        val d = recorridoCompleto("claro")
        assertEquals(8, d.fotos.size)
        assertEquals(8, d.fotos.map { it.id }.toSet().size)
        assertEquals("terceros-v1", d.ultimoEnviar?.get("p_consentimiento")?.comoTexto)
        assertEquals("Hay una polea nueva", d.ultimoEnviar?.get("p_nota")?.comoTexto)
        val foto = FotoDePrueba.propiedades(d.fotos[0].bytes)
        assertEquals(1600 to 1200, foto.ancho to foto.alto)
        assertNull("la foto no lleva la ubicación", foto.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
    }

    @Test
    fun faltanFotos() {
        lanzar("borrador")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.nodo(texto("Te faltan 9 zonas"))
        p.tocar(etiqueta("gimnasio-revisar"))
        p.nodo(etiqueta("gimnasio-faltan"))
        assertFalse(p.habilitado(etiqueta("gimnasio-enviar")))
    }

    @Test
    fun corteDeRedAMitadYReanuda() {
        val d = lanzar("corte")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.tocar(etiqueta("gimnasio-zona-poleas"))
        agregarFoto(1)
        p.esperar("la primera subió", 30_000) { d.fotos.size.takeIf { it == 1 } }
        agregarFoto(2)
        p.nodo(texto("Esperando señal"), ms = 30_000)
        assertEquals("el corte no perdió ni duplicó", 1, d.fotos.size)
        // Se cierra y se vuelve a abrir: la foto que quedó en el disco sale sola, una sola vez.
        cerrarYAbrir()
        p.esperar("la segunda subió", 30_000) { d.fotos.size.takeIf { it == 2 } }
        assertEquals(2, d.fotos.map { it.id }.toSet().size)
    }

    private fun cerrarYAbrir() {
        Telefono.shell("input keyevent KEYCODE_HOME")
        p.quieto(800)
        abrir()
    }

    @Test
    fun reintentoConEspera() {
        val d = lanzar("reintento")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.tocar(etiqueta("gimnasio-zona-poleas"))
        agregarFoto(1)
        p.esperar("reintentó y subió", 60_000) { d.fotos.size.takeIf { it == 1 } }
        assertTrue(d.intentosDeSubida >= 2)
        assertFalse(p.existe(etiqueta("gimnasio-aviso-foto")))
    }

    @Test
    fun fotoRechazada() {
        val d = lanzar("rechazo")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.tocar(etiqueta("gimnasio-zona-poleas"))
        p.tocar(etiqueta("gimnasio-agregar-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(etiqueta("gimnasio-aviso-foto"), ms = 30_000)
        p.nodo(texto("Una foto no se pudo usar. Sacala de nuevo"))
        assertTrue(d.fotos.isEmpty())
        Telefono.captura("gim-rechazada-claro")
    }

    @Test
    fun palancaApagadaNoSeVeNiLlamaNada() {
        val d = lanzar("apagado")
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("gimnasio-tarjeta")))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        assertFalse(p.existe(etiqueta("mis-datos-gimnasio")))
        assertTrue("con la palanca apagada no se llama nada nuevo: ${d.llamadasGimnasio}", d.llamadasGimnasio.isEmpty())
    }

    @Test
    fun sinElServidorNuevoNoSeVe() {
        lanzar("sinServidor")
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("gimnasio-tarjeta")))
    }

    @Test
    fun tarjetaSinRutina() {
        servidor.respuestas["mypump_get_rutina_activa"] = "[]"
        lanzar("vacio")
        p.nodo(etiqueta("entreno-vacio"))
        p.nodo(etiqueta("gimnasio-tarjeta"))
    }

    @Test
    fun enProcesoSinHoras() {
        lanzar("enProceso")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.nodo(etiqueta("gimnasio-recibido"))
        p.nodo(textoQueContiene("Mati y tu entrenador lo están viendo"))
    }

    private fun preguntas(tema: String): DobleGimnasio {
        val d = lanzar("preguntas")
        p.tocar(etiqueta("gimnasio-tarjeta"))
        p.nodo(texto("Pregunta 1 de 6"))
        p.nodo(texto("Necesitamos 1 foto más"))
        Telefono.captura("gim-pregunta-elegir-$tema")
        assertFalse("ni una pregunta más en la misma pantalla", p.existe(textoQueContiene("agarres para polea")))
        p.tocar(etiqueta("gimnasio-opcion-remo_t"))
        p.tocar(etiqueta("gimnasio-siguiente"))
        p.nodo(texto("Pregunta 2 de 6"))
        p.tocar(etiqueta("gimnasio-no-se"))
        p.tocar(etiqueta("gimnasio-siguiente"))
        p.tocar(etiqueta("gimnasio-opcion-2.5"))
        p.tocar(etiqueta("gimnasio-siguiente"))
        p.escribir(etiqueta("gimnasio-kilos"), "50")
        Telefono.captura("gim-pregunta-numero-$tema")
        p.tocar(etiqueta("gimnasio-siguiente"))
        p.tocar(etiqueta("gimnasio-pec_deck-si"))
        p.tocar(etiqueta("gimnasio-press_inclinado-no_se"))
        Telefono.captura("gim-pregunta-confirmar-$tema")
        p.tocar(etiqueta("gimnasio-siguiente"))
        p.nodo(texto("Pregunta 6 de 6"))
        p.tocar(etiqueta("gimnasio-agregar-foto"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.esperar("la foto subió", 30_000) { d.fotos.size.takeIf { it == 1 } }
        Telefono.captura("gim-pregunta-foto-$tema")
        p.tocar(etiqueta("gimnasio-enviar-respuestas"))
        p.nodo(etiqueta("gimnasio-recibido"), ms = 30_000)
        return d
    }

    @Test
    fun confirmarDudosos() {
        val d = preguntas("claro")
        val r = d.ultimoResponder!!
        assertEquals(ValorJson.Lista(listOf(ValorJson.Texto("remo_t"))), r["remo"])
        assertEquals("no_se", r["accesorios"]?.comoTexto)
        assertEquals("2.5", r["peso_discos"]?.comoTexto)
        assertEquals(50.0, r["peso_mancuernas"]?.comoNumero)
        assertEquals("si", r["confirmar_empuje"]?.get("pec_deck")?.comoTexto)
        assertEquals("no_se", r["confirmar_empuje"]?.get("press_inclinado")?.comoTexto)
        assertEquals("subida", r["foto_1"]?.comoTexto)
    }

    private fun abrirMiGimnasio() {
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(1500)
        assertFalse("con el gimnasio cargado no va la tarjeta", p.existe(etiqueta("gimnasio-tarjeta")))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.tocar(etiqueta("mis-datos-gimnasio"))
    }

    @Test
    fun listoEnMisDatos() {
        lanzar("listo")
        abrirMiGimnasio()
        p.nodo(texto("Adaptado por Mati el 12/11"))
        p.nodo(texto("Cruce de poleas"))
        assertFalse(p.existe(textoQueContiene("inteligencia")))
        Telefono.captura("gim-listo-claro")
        p.tocar(etiqueta("gimnasio-ya-no-esta"))
        assertFalse(p.habilitado(etiqueta("gimnasio-enviar-quitar")))
        p.tocar(etiqueta("gimnasio-quitar-prensa_45"))
        Telefono.captura("gim-ya-no-esta-claro")
        p.atras()
        p.nodo(etiqueta("gimnasio-falta-algo"))
        p.nodo(etiqueta("gimnasio-cambie"))
    }

    @Test
    fun estoYaNoEstaManda() {
        val d = lanzar("listo")
        abrirMiGimnasio()
        p.tocar(etiqueta("gimnasio-ya-no-esta"))
        p.tocar(etiqueta("gimnasio-quitar-prensa_45"))
        p.tocar(etiqueta("gimnasio-enviar-quitar"))
        p.nodo(etiqueta("gimnasio-recibido"), ms = 30_000)
        assertEquals(ValorJson.Lista(listOf(ValorJson.Texto("prensa_45"))), d.ultimoEnviar?.get("p_quitar"))
    }

    @Test
    fun listoSinCambios() {
        lanzar("listoSinCambios")
        abrirMiGimnasio()
        p.nodo(texto("Mati revisó tu gimnasio y tu rutina encaja tal cual"))
    }

    @Test
    fun capturasOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        recorridoCompleto("oscuro")
    }

    @Test
    fun preguntasOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        preguntas("oscuro")
    }

    @Test
    fun letraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        recorridoCompleto("grande")
    }

    @Test
    fun preguntasLetraGrande() {
        Telefono.shell("settings put system font_scale 1.3")
        preguntas("grande")
    }
}
