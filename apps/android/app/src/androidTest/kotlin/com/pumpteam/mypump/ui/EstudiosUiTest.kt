package com.pumpteam.mypump.ui

import android.app.Activity
import android.app.Instrumentation
import android.content.ClipData
import android.content.Intent
import android.graphics.Bitmap
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.datos.DobleEstudios
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.fotos.ProveedorFotos
import java.io.ByteArrayOutputStream
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * «Estudios y órdenes» contra el doble del servidor (sin red y con datos inventados). Lo fino de la cola está en
 * `EstudiosTest`; acá, la pantalla de verdad: la fila de Mis datos, la subida con fotos y PDF, la fecha, la orden dentro de
 * la app y que nada quede en el teléfono.
 */
@RunWith(AndroidJUnit4::class)
class EstudiosUiTest : PruebaUi() {
    private var selectores: Instrumentation.ActivityMonitor? = null

    @After
    fun soltar() {
        selectores?.let(instr::removeMonitor)
        ProveedorFotos.carpeta(app).deleteRecursively()
        Telefono.shell("settings put system font_scale 1.0")
    }

    /** La cámara, el selector de fotos y el de archivos, de mentira: contestan sin abrir nada. El de fotos devuelve dos de una vez. */
    private fun ponerSelectores() {
        val monitor = object : Instrumentation.ActivityMonitor() {
            private var capturas = 0

            private fun otraFoto(n: Int): ByteArray {
                val img = FotoDePrueba.imagen(2400, 1800 - 16 * n)
                try {
                    return FotoDePrueba.jpegDeCamara(app, img)
                } finally {
                    img.recycle()
                }
            }

            private fun archivo(nombre: String, bytes: ByteArray) = ProveedorFotos.uri(app, File(ProveedorFotos.carpeta(app), nombre).apply { parentFile?.mkdirs(); writeBytes(bytes) })

            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                val accion = intent.action ?: return null
                if (accion == MediaStore.ACTION_IMAGE_CAPTURE) {
                    @Suppress("DEPRECATION")
                    val salida = intent.getParcelableExtra<android.net.Uri>(MediaStore.EXTRA_OUTPUT) ?: return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
                    // Cada foto de la cámara es distinta (la hoja no suma dos veces los mismos bytes).
                    app.contentResolver.openOutputStream(salida)!!.use { it.write(if (capturas++ == 0) CamaraDePrueba.fotoGrande() else otraFoto(capturas)) }
                    return Instrumentation.ActivityResult(Activity.RESULT_OK, null)
                }
                val tipos = intent.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)?.toList() ?: emptyList()
                if (accion == Intent.ACTION_OPEN_DOCUMENT && "application/pdf" in tipos) {
                    return Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(archivo("resultado.pdf", DobleEstudios.pdfDePrueba(2))))
                }
                if ("PICK_IMAGES" in accion || accion == Intent.ACTION_OPEN_DOCUMENT || accion == Intent.ACTION_GET_CONTENT) {
                    // Una de cámara (JPEG con la ubicación en el EXIF) y una captura de pantalla (PNG, más grande que el tope de lado).
                    val jpeg = archivo("de-la-galeria.jpg", CamaraDePrueba.fotoGrande())
                    val png = archivo("captura.png", pngGrande())
                    val datos = Intent().apply { clipData = ClipData.newRawUri("fotos", jpeg).apply { addItem(ClipData.Item(png)) } }
                    return Instrumentation.ActivityResult(Activity.RESULT_OK, datos)
                }
                return null
            }
        }
        instr.addMonitor(monitor)
        selectores = monitor
    }

    private fun pngGrande(): ByteArray {
        val img = FotoDePrueba.imagen(3000, 2000)
        try {
            return ByteArrayOutputStream().also { img.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        } finally {
            img.recycle()
        }
    }

    private fun lanzar(escenario: String, abrirLaApp: () -> Unit = { abrir() }): DobleEstudios {
        val d = DobleEstudios.escenario(escenario)
        d.imagenParaVer = CamaraDePrueba.fotoGrande()
        val s = servidor
        Entorno.transporte = Transporte { pedido ->
            if ("estudios" in pedido.ruta || pedido.ruta.endsWith("mypump_get_app_config")) d.enviar(pedido) else s.enviar(pedido)
        }
        guardarCuenta()
        ponerSelectores()
        abrirLaApp()
        return d
    }

    /** Como tocar el aviso «Tenés un estudio nuevo para hacer» con la app cerrada. */
    private fun lanzarDesdeElAviso(escenario: String): DobleEstudios =
        lanzar(escenario) { registrar(ActivityScenario.launch<MainActivity>(CentroAvisos.intentDeAviso(app, "estudios"))) }

    private fun irAMisDatos() {
        p.nodo(etiqueta("pestana-entreno"))
        p.tocar(etiqueta("pestana-revision"))
        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
    }

    /** Estudios vive en «Mi salud» (2.3.0): Revisión → la tarjeta Mi salud → el bloque de Estudios. */
    private fun abrirEstudios() {
        p.nodo(etiqueta("pestana-entreno"))
        p.abrirMiSalud()
        p.nodo(etiqueta("mi-salud-bloque-estudios"))
    }

    private val enCola: File get() = File(app.noBackupFilesDir, "MyPump")
    private fun archivosEn(carpeta: File): List<File> = carpeta.walkTopDown().filter { it.isFile }.toList()

    private fun recorrido(tema: String): DobleEstudios {
        val d = lanzar("completo")
        irAMisDatos()
        // En Mis datos queda una sola fila, «Mi salud», que lleva ahí.
        p.nodo(etiqueta("mis-datos-mi-salud"))
        assertFalse(p.existe(texto("Estudios y órdenes")))
        Telefono.captura("est-mis-datos-$tema")
        p.tocar(etiqueta("mis-datos-mi-salud"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        p.nodo(texto("Estudios y órdenes"))
        p.nodo(texto("Semana del 23/11"))
        p.nodo(texto("Te falta hacer"))
        p.nodo(texto("Antes del jueves 19/11"))
        Telefono.captura("est-pantalla-$tema")
        p.nodo(texto("Era para el jueves 5/11"))
        Telefono.captura("est-pendientes-$tema")
        p.nodo(texto("Hecho el 9/11. Falta subir el resultado."))

        // La subida: dos fotos de una vez y un PDF.
        p.tocar(etiqueta("estudios-subir"))
        p.nodo(texto("Subí todas las hojas juntas, en PDF o en fotos donde se lea bien."))
        p.nodo(texto("Hasta 20 archivos por envío."))
        assertFalse("sin archivos no se envía", p.habilitado(etiqueta("estudios-enviar")))
        Telefono.captura("est-hoja-vacia-$tema")
        p.tocar(etiqueta("estudios-elegir-fotos"))
        p.esperar("las dos fotos en la hoja", 60_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 2 } }
        p.tocar(etiqueta("estudios-elegir-pdf"))
        p.esperar("el PDF en la hoja", 30_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 3 } }
        p.nodo(texto("Enviar 3 archivos"))
        Telefono.captura("est-hoja-$tema")
        p.tocar(etiqueta("estudios-enviar"))
        p.nodo(etiqueta("estudios-recibido"), ms = 60_000)
        p.nodo(texto("Recibido. Mati lo revisa y te escribe."))
        Telefono.captura("est-recibido-$tema")
        p.nodo(etiqueta("estudios-envio"))
        Telefono.captura("est-lista-$tema")
        p.nodo(etiqueta("estudios-nota-fija"))
        Telefono.captura("est-estudios-$tema")

        // La orden: su detalle y el papel, dentro de la app.
        p.tocar(etiqueta("estudios-orden-${DobleEstudios.ORDEN_LAB}"))
        p.nodo(etiqueta("estudios-detalle-orden"))
        p.nodo(texto("Cómo prepararte"))
        Telefono.captura("est-orden-$tema")
        p.nodo(texto("Dónde hacerlo"))
        Telefono.captura("est-orden-donde-$tema")
        p.tocar(etiqueta("estudios-ver-orden"))
        p.esperar("las dos hojas de la orden", 30_000) { p.cuantos(etiqueta("estudios-visor-hoja")).takeIf { it >= 1 } }
        p.quieto(1200)
        Telefono.captura("est-visor-$tema")
        assertEquals("el papel está en un temporal propio mientras se mira", 1, archivosEn(File(app.cacheDir, "estudios-ver")).size)
        p.atras()
        p.nodo(etiqueta("estudios-detalle-orden"))
        p.esperar("el temporal se borra al cerrar") { archivosEn(File(app.cacheDir, "estudios-ver")).isEmpty().takeIf { it } }
        return d
    }

    @Test
    fun recorridoCompleto() {
        val d = recorrido("claro")
        val envio = d.enviados.single()
        assertNull("«Subir un estudio» va suelto", envio.pedidoId)
        assertEquals(listOf("image/jpeg", "image/jpeg", "application/pdf"), envio.archivos.map { it.mime })
        assertEquals(3, envio.archivos.map { it.id }.toSet().size)
        // Lado mayor 2400, también la que era PNG, y sin la ubicación de la cámara.
        val deCamara = FotoDePrueba.propiedades(envio.archivos[0].bytes)
        assertEquals(2400 to 1800, deCamara.ancho to deCamara.alto)
        assertEquals("image/jpeg", deCamara.tipo)
        assertNull("la foto no lleva la ubicación", deCamara.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        val eraPng = FotoDePrueba.propiedades(envio.archivos[1].bytes)
        assertEquals(2400 to 1600, eraPng.ancho to eraPng.alto)
        assertEquals("image/jpeg", eraPng.tipo)
        assertTrue("el PDF va tal cual", DobleEstudios.pdfDePrueba(2).contentEquals(envio.archivos[2].bytes))
        // Enviado: nada queda en el teléfono.
        assertTrue("la cola quedó vacía: ${archivosEn(enCola)}", archivosEn(enCola).isEmpty())
        assertTrue(archivosEn(File(app.cacheDir, "estudios-borrador")).isEmpty())
        assertEquals("orden", d.ultimoUrls?.get("clase")?.comoTexto)
        assertEquals(DobleEstudios.ORDEN_LAB, d.ultimoUrls?.get("id")?.comoTexto)
    }

    @Test
    fun palancaApagadaNoSeVeNiLlamaNada() {
        val d = lanzar("apagado")
        p.nodo(etiqueta("pestana-entreno"))
        p.abrirMiSalud()
        p.quieto(2500)
        // Mi salud sigue (la recuperación), sin el bloque de Estudios.
        assertFalse(p.existe(etiqueta("mi-salud-bloque-estudios")))
        assertTrue("con la palanca apagada no se llama nada nuevo: ${d.llamadasEstudios}", d.llamadasEstudios.isEmpty())
    }

    @Test
    fun sinElServidorNuevoNoSeVe() {
        val d = lanzar("sinServidor")
        p.nodo(etiqueta("pestana-entreno"))
        p.abrirMiSalud()
        p.quieto(2500)
        // Mi salud sigue (la recuperación), sin el bloque de Estudios.
        assertFalse(p.existe(etiqueta("mi-salud-bloque-estudios")))
        assertTrue(d.llamadasEstudios.none { it.startsWith("estudios/") })
    }

    @Test
    fun noHabilitadoNoSeVe() {
        lanzar("noHabilitado")
        p.nodo(etiqueta("pestana-entreno"))
        p.abrirMiSalud()
        p.quieto(2500)
        // Mi salud sigue (la recuperación), sin el bloque de Estudios.
        assertFalse(p.existe(etiqueta("mi-salud-bloque-estudios")))
    }

    @Test
    fun vacioYTodoAlDia() {
        lanzar("vacio")
        abrirEstudios()
        p.nodo(texto("Acá vas a ver los estudios que te pida Mati, tus órdenes y lo que nos mandes."))
        p.nodo(etiqueta("estudios-subir"))
        assertFalse(p.existe(texto("Tus estudios")))
        Telefono.captura("est-vacio-claro")
    }

    private fun yaMeLoHice(tema: String): DobleEstudios {
        val d = lanzar("completo")
        abrirEstudios()
        p.tocar(etiqueta("estudios-ya-me-lo-hice"))
        p.nodo(texto("¿Cuándo te lo hiciste?"))
        p.nodo(texto("martes 10/11"))
        assertFalse("no se ofrece una fecha futura", p.habilitado(etiqueta("estudios-fecha-mas")))
        p.tocar(etiqueta("estudios-fecha-menos"))
        p.nodo(texto("lunes 9/11"))
        Telefono.captura("est-fecha-$tema")
        p.tocar(etiqueta("estudios-guardar-fecha"))
        p.esperar("los dos hechos") { p.cuantos(etiqueta("estudios-hecho")).takeIf { it == 2 } }
        return d
    }

    @Test
    fun yaMeLoHiceYDeshacer() {
        val d = yaMeLoHice("claro")
        assertEquals(DobleEstudios.PEDIDO_LAB, d.ultimoHecho?.get("p_pedido_id")?.comoTexto)
        assertEquals("2026-11-09", d.ultimoHecho?.get("p_fecha")?.comoTexto)
        p.tocar(etiqueta("estudios-deshacer"))
        p.esperar("vuelve a pedido") { p.cuantos(etiqueta("estudios-hecho")).takeIf { it == 1 } }
        p.nodo(texto("Antes del jueves 19/11"))
    }

    @Test
    fun subirResultadoLlevaElPedidoYLaOrdenDesdeLaTarjeta() {
        val d = lanzar("completo")
        abrirEstudios()
        p.tocar(etiqueta("estudios-subir-resultado"))
        p.nodo(texto("Subir resultado"))
        p.tocar(etiqueta("estudios-elegir-pdf"))
        p.esperar("el PDF en la hoja", 30_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 1 } }
        p.nodo(texto("Enviar 1 archivo"))
        p.tocar(etiqueta("estudios-enviar"))
        p.nodo(etiqueta("estudios-recibido"), ms = 60_000)
        assertEquals(DobleEstudios.PEDIDO_LAB, d.enviados.single().pedidoId)
        p.tocar(etiqueta("estudios-ver-orden-pendiente"))
        p.nodo(etiqueta("estudios-detalle-orden"))
    }

    @Test
    fun quitarYCancelarNoDejanNada() {
        val d = lanzar("completo")
        abrirEstudios()
        p.tocar(etiqueta("estudios-subir"))
        p.tocar(etiqueta("estudios-elegir-fotos"))
        p.esperar("las dos fotos en la hoja", 60_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 2 } }
        p.tocar(etiqueta("estudios-quitar"))
        p.esperar("queda una") { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 1 } }
        p.nodo(texto("Enviar 1 archivo"))
        p.tocar(etiqueta("estudios-cancelar-subida"))
        p.esperarQueNoEste(etiqueta("estudios-enviar"))
        p.esperar("los temporales de la hoja se borran") { archivosEn(File(app.cacheDir, "estudios-borrador")).isEmpty().takeIf { it } }
        assertTrue(d.envios.isEmpty())
        assertEquals(0, d.intentosDeSubida)
    }

    @Test
    fun sacarFotoConLaCamara() {
        val d = lanzar("vacio")
        abrirEstudios()
        p.tocar(etiqueta("estudios-subir"))
        p.tocar(etiqueta("estudios-sacar-fotos"))
        p.esperar("la foto en la hoja", 60_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 1 } }
        p.tocar(etiqueta("estudios-sacar-fotos"))
        p.esperar("la segunda foto", 60_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 2 } }
        p.tocar(etiqueta("estudios-enviar"))
        p.nodo(etiqueta("estudios-recibido"), ms = 60_000)
        assertEquals(2, d.enviados.single().archivos.size)
        assertTrue("la foto de la cámara no queda en la caché", archivosEn(ProveedorFotos.carpeta(app)).none { it.name.startsWith("estudios-") || it.name == "foto-estudios.jpg" })
    }

    @Test
    fun archivoRechazadoPorElServidor() {
        val d = lanzar("rechazo")
        abrirEstudios()
        p.tocar(etiqueta("estudios-subir"))
        p.tocar(etiqueta("estudios-elegir-pdf"))
        p.esperar("el PDF en la hoja", 30_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 1 } }
        p.tocar(etiqueta("estudios-enviar"))
        p.nodo(etiqueta("estudios-rechazado"), ms = 60_000)
        p.nodo(texto("No pudimos leer ese archivo. Probá con una foto o un PDF."))
        assertTrue(d.enviados.isEmpty())
        assertTrue(archivosEn(enCola).isEmpty())
        Telefono.captura("est-rechazado-claro")
    }

    @Test
    fun topeDelDia() {
        lanzar("topeDia")
        abrirEstudios()
        p.tocar(etiqueta("estudios-subir"))
        p.tocar(etiqueta("estudios-elegir-pdf"))
        p.esperar("el PDF en la hoja", 30_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 1 } }
        p.tocar(etiqueta("estudios-enviar"))
        p.nodo(texto("Ya mandaste varios envíos hoy. Probá mañana o escribile a Mati."), ms = 60_000)
    }

    @Test
    fun sinSenalQuedaEnColaYSaleAlVolver() {
        val d = lanzar("vacio")
        abrirEstudios()
        p.tocar(etiqueta("estudios-subir"))
        p.tocar(etiqueta("estudios-elegir-pdf"))
        p.esperar("el PDF en la hoja", 30_000) { p.cuantos(etiqueta("estudios-quitar")).takeIf { it == 1 } }
        d.sinRed = true
        p.tocar(etiqueta("estudios-enviar"))
        p.nodo(texto("Sin señal. Se envía solo cuando vuelva."), ms = 60_000)
        Telefono.captura("est-sin-senal-claro")
        assertEquals(1, archivosEn(enCola).size)
        d.sinRed = false
        // Se cierra y se vuelve a abrir: lo que quedó en el disco sale solo, una sola vez.
        Telefono.shell("input keyevent KEYCODE_HOME")
        p.quieto(800)
        abrir()
        p.esperar("salió al volver", 60_000) { d.enviados.size.takeIf { it == 1 } }
        p.esperar("y se borró del teléfono") { archivosEn(enCola).isEmpty().takeIf { it } }
    }

    @Test
    fun verUnEstudioPropioYElQueNoSeAbre() {
        val d = lanzar("completo")
        abrirEstudios()
        p.nodo(texto("Mati lo vio"))
        p.nodo(texto("Sin fecha · 1 hoja"))
        // El que todavía no se puede abrir no es un botón.
        // `tocar` espera una acción de toque: acá se comprueba que no la tiene.
        assertFalse("la fila que no se abre no es un botón", p.tocable(etiqueta("estudios-estudio-${DobleEstudios.ESTUDIO_RECIBIDO}")))
        p.quieto(800)
        assertFalse(p.existe(etiqueta("estudios-visor-cargando")) || p.existe(etiqueta("estudios-visor")))
        assertNull(d.ultimoUrls)
        p.tocar(etiqueta("estudios-estudio-${DobleEstudios.ESTUDIO_VISTO}"))
        p.esperar("la foto y las hojas del PDF", 30_000) { p.cuantos(etiqueta("estudios-visor-hoja")).takeIf { it >= 1 } }
        assertEquals("estudio", d.ultimoUrls?.get("clase")?.comoTexto)
        p.quieto(1200)
        Telefono.captura("est-visor-estudio-claro")
        p.atras()
        p.nodo(etiqueta("mi-salud-pantalla"))
        p.esperar("los temporales se borran al cerrar") { archivosEn(File(app.cacheDir, "estudios-ver")).isEmpty().takeIf { it } }
    }

    @Test
    fun ordenVencidaNoSeAbre() {
        lanzar("completo")
        abrirEstudios()
        p.nodo(texto("Vencida. Si la necesitás, pedísela a Mati por el chat."))
        assertFalse("la orden vencida no es un botón", p.tocable(etiqueta("estudios-orden-${DobleEstudios.ORDEN_VENCIDA}")))
        p.quieto(800)
        assertFalse(p.existe(etiqueta("estudios-detalle-orden")))
    }

    @Test
    fun sinLaPalabraIA() {
        lanzar("completo")
        abrirEstudios()
        assertFalse(p.existe(textoQueContiene("inteligencia")))
        assertFalse(p.existe(textoQueContiene(" IA")))
    }

    @Test
    fun capturasOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        recorrido("oscuro")
    }

    @Test
    fun fechaOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        yaMeLoHice("oscuro")
    }

    /** La letra al máximo que deja Android (200 %): nada se corta. */
    @Test
    fun letraGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        recorrido("grande")
    }

    @Test
    fun fechaLetraGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        yaMeLoHice("grande")
    }


    // ── Novedades: la tarjeta de arriba, el punto, «Nuevo» y el aviso ──

    private fun novedad(tema: String): DobleEstudios {
        val d = lanzar("novedad")
        // Arriba de Entreno, sin tocar nada: la tarjeta verde con el botón grande.
        p.nodo(etiqueta("tarjeta-mi-salud-inicio"))
        p.nodo(texto("Tenés un estudio nuevo para hacer"))
        p.nodo(etiqueta("tarjeta-mi-salud-inicio-boton"))
        p.nodo(texto("Ver"))
        Telefono.captura("est-novedad-inicio-$tema")
        // Un toque: Estudios, con la tarjeta nueva a la vista y su «Nuevo».
        p.tocar(etiqueta("tarjeta-mi-salud-inicio-boton"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        p.nodo(etiqueta("estudios-nuevo-${DobleEstudios.PEDIDO_ECO}"))
        p.nodo(texto("Nuevo"))
        Telefono.captura("est-novedad-estudios-$tema")
        // Estuvo a la vista: deja de ser novedad en el servidor, sigue pendiente y conserva «Nuevo» mientras se la mira.
        p.esperar("el pedido marcado como visto", 15_000, enElPrincipal = false) { d.vistasPedidas.flatten().contains(DobleEstudios.PEDIDO_ECO).takeIf { it } }
        p.quieto(800)
        assertTrue(p.existe(etiqueta("estudios-nuevo-${DobleEstudios.PEDIDO_ECO}")))
        assertTrue(p.existe(etiqueta("estudios-pendiente-${DobleEstudios.PEDIDO_ECO}")))
        return d
    }

    @Test
    fun laTarjetaDeArribaLlevaALaTarjetaNueva() {
        val d = novedad("claro")
        assertTrue("solo se marca lo que era nuevo: ${d.vistasPedidas}", d.vistasPedidas.flatten().all { it == DobleEstudios.PEDIDO_ECO || it == DobleEstudios.ORDEN_LAB })
    }

    @Test
    fun novedadOscuro() {
        Telefono.modoNoche(true)
        guardarTemaOscuro()
        novedad("oscuro")
    }

    /** Con la letra al 200 % la tarjeta de arriba y «Nuevo» no se cortan y el botón sigue ahí. */
    @Test
    fun novedadLetraGrande() {
        Telefono.shell("settings put system font_scale 2.0")
        novedad("grande")
    }

    @Test
    fun sinNovedadLaTarjetaLlevaASubirEnDosToques() {
        lanzar("completo")
        p.nodo(etiqueta("tarjeta-mi-salud-inicio"))
        p.nodo(texto("Tenés un estudio para hacer"))
        p.nodo(etiqueta("tarjeta-mi-salud-inicio-boton"))
        p.nodo(texto("Subir resultado"))
        assertFalse("sin nada sin ver no hay punto", p.existe(etiqueta("pestana-revision-novedad")))
        Telefono.captura("est-para-hacer-inicio-claro")
        // Un toque a Estudios, dos al selector de archivos.
        p.tocar(etiqueta("tarjeta-mi-salud-inicio-boton"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        assertFalse(p.existe(texto("Nuevo")))
        p.tocar(etiqueta("estudios-subir-resultado"))
        p.nodo(etiqueta("estudios-sacar-fotos"))
        p.nodo(etiqueta("estudios-elegir-fotos"))
        p.nodo(etiqueta("estudios-elegir-pdf"))
        Telefono.captura("est-hoja-opciones-claro")
    }

    @Test
    fun sinPedidosNiNovedadNoHayTarjetaArriba() {
        lanzar("vacio")
        p.nodo(etiqueta("pestana-entreno"))
        p.quieto(2500)
        assertFalse(p.existe(etiqueta("tarjeta-mi-salud-inicio")))
    }

    @Test
    fun elCaminoEsLaTarjetaMiSaludYSeApagaAlVerLaOrden() {
        val d = lanzar("ordenNueva")
        p.nodo(texto("Tenés una orden nueva"))
        p.tocar(etiqueta("pestana-revision"))
        // 2.3.0: el camino es la tarjeta «Mi salud» de Revisión, con el número y lo pendiente (el botón de Mis datos ya
        // no lleva punto).
        p.nodo(etiqueta("tarjeta-mi-salud-cuenta"))
        p.nodo(textoQueContiene("Tenés una orden nueva"))
        assertFalse(p.existe(etiqueta("mis-datos-novedad")))
        Telefono.captura("est-novedad-revision-claro")
        p.tocar(etiqueta("tarjeta-mi-salud"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        p.nodo(etiqueta("estudios-nuevo-${DobleEstudios.ORDEN_LAB}"))
        p.esperar("la orden marcada como vista", 15_000, enElPrincipal = false) { d.vistasPedidas.flatten().contains(DobleEstudios.ORDEN_LAB).takeIf { it } }
        p.atras()
        p.nodo(etiqueta("revision-lista"))
        p.esperarQueNoEste(etiqueta("mi-salud-pantalla"))
    }

    @Test
    fun tocarElAvisoConLaAppCerradaAbreEstudios() {
        lanzarDesdeElAviso("novedad")
        p.nodo(etiqueta("mi-salud-pantalla"), ms = 30_000)
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        p.nodo(etiqueta("estudios-nuevo-${DobleEstudios.PEDIDO_ECO}"))
        // Atrás vuelve a Revisión, de donde cuelga Mi salud.
        p.atras()
        p.nodo(etiqueta("revision-lista"))
    }

    @Test
    fun elLinkConLaEscenaAbreEstudios() {
        lanzar("novedad") { abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&scene=estudios") }
        p.nodo(etiqueta("mi-salud-pantalla"), ms = 30_000)
    }

    @Test
    fun tocarElAvisoConLaAppAbiertaAbreEstudios() {
        lanzar("soloOrdenNueva")
        p.nodo(texto("Tenés una orden nueva"))
        app.startActivity(CentroAvisos.intentDeAviso(app, "estudios"))
        p.nodo(etiqueta("mi-salud-pantalla"))
        p.nodo(etiqueta("estudios-nuevo-${DobleEstudios.ORDEN_LAB}"))
    }

    /** Sin la sección, el aviso deja en Mi salud sin el bloque de Estudios: nunca una pantalla en blanco ni el Chat. */
    private fun elAvisoCaeEnMisDatos(escenario: String): DobleEstudios {
        val d = lanzarDesdeElAviso(escenario)
        p.nodo(etiqueta("mi-salud-pantalla"), ms = 30_000)
        p.quieto(7_000)   // más que el tope de la espera
        assertTrue(p.existe(etiqueta("mi-salud-pantalla")))
        assertFalse(p.existe(etiqueta("mi-salud-bloque-estudios")))
        assertTrue(p.existe(etiqueta("mi-salud-bloque-recuperacion")))
        assertTrue(p.seleccionado(etiqueta("pestana-revision")))
        return d
    }

    @Test
    fun elAvisoConLaPalancaApagadaCaeEnMisDatosSinLlamarNada() {
        val d = elAvisoCaeEnMisDatos("apagado")
        assertTrue("con la palanca apagada no se llama nada nuevo: ${d.llamadasEstudios}", d.llamadasEstudios.isEmpty())
    }

    @Test
    fun elAvisoSinElServidorNuevoCaeEnMisDatos() {
        elAvisoCaeEnMisDatos("sinServidor")
    }

    @Test
    fun elAvisoSinLaFuncionCaeEnMisDatos() {
        elAvisoCaeEnMisDatos("noHabilitado")
    }
}
