package com.pumpteam.mypump.ui

import android.app.Activity
import android.app.Instrumentation
import android.content.Intent
import android.content.pm.PackageManager
import android.media.ExifInterface
import android.net.Uri
import android.provider.MediaStore
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.Disco
import com.pumpteam.mypump.datos.FotoPendiente
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.diseno.ImagenesRemotas
import com.pumpteam.mypump.fotos.FotoDePrueba
import com.pumpteam.mypump.fotos.ProveedorFotos
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import com.pumpteam.mypump.salud.EstadoHealthConnect
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Revisión con Mi Día (REV-01…08, DIA-01…06, SAL-09/10), gemela de `RevisionUITests` de iOS y más: con la cuenta del
 * [ServidorDePrueba] (las respuestas grabadas de `test-nativa-real`, sin red) y en la demo, que no escribe nada. La cámara
 * y el selector de fotos del teléfono se reemplazan con un monitor que contesta una foto armada acá (sin abrir nada),
 * como el navegador de `CustomTabsTest`.
 */
@RunWith(AndroidJUnit4::class)
class RevisionUiTest : PruebaUi() {
    private val monitores = ArrayList<Instrumentation.ActivityMonitor>()
    private val lunes get() = FotosProgreso.lunes(FechaLocal.hoy())

    @After
    fun limpiarRevision() {
        for (m in monitores) instr.removeMonitor(m)
        monitores.clear()
        ModeloSalud.fuenteDelSistema = null
        EstadoHealthConnect.forzado = null
        ProveedorFotos.carpeta(app).deleteRecursively()
    }

    private fun irARevision() {
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("seccion-midia"))
    }

    /** Dónde empieza una sección, medido en pantallas de lo que se ve de Revisión (0 = arriba de todo, 1 = abajo). */
    private fun altura(seccion: String): Float = p.esperar("se ubica $seccion") { alturaYa(seccion) }

    /**
     * [altura] sin esperar, para usar ADENTRO de un `p.esperar` (que corre en el hilo principal): una espera anidada
     * dormía el hilo principal hasta 15 s, y con la pantalla recién cambiada Revisión no llegaba a armarse.
     */
    private fun alturaYa(seccion: String): Float {
        val visible = p.nodo(etiqueta("revision-lista"), ms = 0).boundsInRoot
        val s = p.nodo(etiqueta("seccion-$seccion"), ms = 0)
        return (s.positionInRoot.y - visible.top) / visible.height
    }

    /**
     * La cámara y el selector de fotos, de mentira: contestan con [foto] sin abrir nada. Devuelve los pedidos que
     * atendió (la cámara recibe el `content://` de [ProveedorFotos] y escribe ahí, como la app de cámara).
     */
    private fun fotosDePrueba(foto: () -> ByteArray): List<Intent> {
        val pedidos = CopyOnWriteArrayList<Intent>()
        val m = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                val accion = intent.action ?: return null
                if (accion == MediaStore.ACTION_IMAGE_CAPTURE) {
                    pedidos += intent
                    @Suppress("DEPRECATION")
                    val salida = intent.getParcelableExtra<Uri>(MediaStore.EXTRA_OUTPUT) ?: return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
                    app.contentResolver.openOutputStream(salida)!!.use { it.write(foto()) }
                    return Instrumentation.ActivityResult(Activity.RESULT_OK, null)
                }
                if ("PICK_IMAGES" in accion || accion == Intent.ACTION_OPEN_DOCUMENT || accion == Intent.ACTION_GET_CONTENT) {
                    pedidos += intent
                    val f = File(ProveedorFotos.carpeta(app), "de-la-galeria").apply {
                        parentFile?.mkdirs()
                        writeBytes(foto())
                    }
                    return Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(ProveedorFotos.uri(app, f)))
                }
                return null
            }
        }
        instr.addMonitor(m)
        monitores += m
        return pedidos
    }

    private fun fotoDeCamara(): ByteArray {
        val img = FotoDePrueba.imagen(2000, 1500)
        try {
            return FotoDePrueba.jpegDeCamara(app, img, orientacion = ExifInterface.ORIENTATION_ROTATE_90)
        } finally {
            img.recycle()
        }
    }

    // ── REV-01: el orden de la web ──

    @Test
    fun lasTarjetasVanEnElOrdenDeLaWeb() {
        servidor.relojes = listOf("oura")
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(etiqueta("card-reloj"))
        val ys = listOf("fotos", "check", "peso", "reloj", "midia").map { it to altura(it) }
        assertEquals("Fotos → Check → Peso → Mi reloj → Mi Día: $ys", ys.sortedBy { it.second }.map { it.first }, ys.map { it.first })
        // El encabezado de la semana sigue arriba, y sin relojes en el servidor la tarjeta no ocupa lugar.
        p.nodo(textoQueContiene("Semana del"))
        Telefono.captura("revision-orden-claro")
    }

    // ── DIA-03: gemela de testUnHabitoSeMarcaYSeBorra ──

    /** Un hábito se marca y, tocado otra vez, se borra (DIA-03). La cuenta queda como estaba. */
    @Test
    fun unHabitoSeMarcaYSeBorra() {
        guardarCuenta()
        abrir()
        irARevision()
        val si = texto("Dormí bien: sí")
        p.esperar("Mi Día cargado") { p.habilitado(si) }
        val antes = p.estado(si) == "marcado"
        p.tocar(si)
        p.esperar("tocar \"sí\" cambió el hábito") { (p.estado(si) == "marcado") != antes }
        p.esperar("salió por la cola") { servidor.a("mypump_set_habito").firstOrNull { "\"p_campo\":\"durmio_bien\"" in it && "\"p_valor\":\"true\"" in it } }
        Telefono.captura("revision-habito-tocado-claro")
        p.tocar(si)
        p.esperar("tocarlo otra vez lo devolvió a como estaba") { (p.estado(si) == "marcado") == antes }
        p.esperar("se borró en el servidor") { servidor.a("mypump_set_habito").firstOrNull { "\"p_campo\":\"durmio_bien\"" in it && "\"p_valor\":\"null\"" in it } }
    }

    /**
     * Gemela de testMisDatosAbreElRespaldoYLaPolitica (la de los interruptores es `SinPermisoIAUiTest`): desde Mis datos
     * se abren el respaldo científico y la política de privacidad (en la Custom Tab, que acá no se abre de verdad: el
     * monitor se queda con el pedido). Y el pie de Mi Día abre el mismo respaldo (GEN-09).
     */
    @Test
    fun misDatosAbreElRespaldoYLaPoliticaYMiDiaTambienElRespaldo() {
        val vistos = CopyOnWriteArrayList<Intent>()
        val m = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_VIEW) return null
                vistos += intent
                return Instrumentation.ActivityResult(0, null)
            }
        }
        instr.addMonitor(m)
        monitores += m
        guardarCuenta()
        abrir()
        irARevision()
        p.tocar(etiqueta("respaldo-cientifico"))
        p.nodo(etiqueta("hoja-fuentes"))
        p.nodo(texto("Cómo se calcula tu objetivo de calorías"))
        p.tocar(etiqueta("fuentes-listo"))
        p.esperarQueNoEste(etiqueta("hoja-fuentes"))

        p.tocar(etiqueta("mis-datos"))
        p.nodo(etiqueta("mis-datos-pantalla"))
        p.tocar(etiqueta("mis-datos-respaldo"))
        p.nodo(etiqueta("hoja-fuentes"))
        p.tocar(etiqueta("fuentes-listo"))
        p.esperarQueNoEste(etiqueta("hoja-fuentes"))
        p.tocar(texto("Política de privacidad"))
        val i = p.esperar("se abrió la política") { vistos.firstOrNull() }
        assertEquals(com.pumpteam.mypump.acceso.URL_PRIVACIDAD, i.dataString)
        // En la Custom Tab con el navegador fijo o, sin un navegador con Custom Tabs, con el selector de navegadores.
        comprobarQueVaAlNavegador(i, app)
    }

    // ── DIA-01, DIA-02 y DIA-04 ──

    @Test
    fun laRachaEntreneYElAgua() {
        servidor.respuestas["mypump_get_streak"] = """[{"streak":5,"ultimo_dia_valido":"2026-10-13"}]"""
        guardarCuenta()
        abrir()
        irARevision()
        // ⚡ desde 3 días, con el último día válido como la web.
        p.nodo(texto("Último día válido: martes, 13 de octubre"))
        p.nodo(texto("⚡"))
        p.nodo(texto("Buen ritmo"))
        // Entrené: se marca, sale por la cola y se vuelve a pedir la racha.
        val rachasAntes = servidor.a("mypump_get_streak").size
        p.tocar(etiqueta("entrenamiento-entrene"))
        p.esperar("Entrené elegido") { p.seleccionado(etiqueta("entrenamiento-entrene")) }
        p.esperar("salió") { servidor.a("mypump_set_habito").firstOrNull { "\"p_campo\":\"entrenamiento\"" in it && "\"p_valor\":\"entrene\"" in it } }
        p.esperar("se volvió a pedir la racha") { servidor.a("mypump_get_streak").size > rachasAntes }
        // Agua: se ve al instante y se guarda UNA vez, 600 ms después del último toque.
        p.tocar(texto("Un vaso más"))
        p.tocar(texto("Un vaso más"))
        p.tocar(texto("Un vaso más"))
        p.tocar(texto("Un vaso menos"))
        p.nodo(texto("2 de 12 vasos de agua"))
        p.esperar("el agua salió") { servidor.a("mypump_set_habito").firstOrNull { "\"p_campo\":\"vasos_agua\"" in it && "\"p_valor\":\"2\"" in it } }
        p.quieto(1_000)
        assertEquals("el agua se guarda una sola vez", 1, servidor.a("mypump_set_habito").count { "vasos_agua" in it })
    }

    // ── DIA-05: los 30 días se traen al abrirlos ──

    @Test
    fun losUltimos30DiasSeTraenAlAbrirlos() {
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(texto("Ver mi historial de adherencia"))
        p.quieto(500)
        assertTrue("se pidió el historial antes de abrirlo", servidor.a("mypump_get_adherencia_30d").isEmpty())
        p.tocar(etiqueta("ultimos-30"))
        p.nodo(etiqueta("grilla-30"))
        assertEquals(1, servidor.a("mypump_get_adherencia_30d").size)
        // La cuenta grabada no cumplió ningún día de los 30.
        p.nodo(texto("0/30"))
        p.nodo(textoQueContiene(": sin datos"))
        for (leyenda in listOf("Cumplido", "Parcial", "Sin datos")) p.nodo(texto(leyenda))
        // Cerrarla y abrirla de nuevo no la vuelve a pedir.
        p.tocar(etiqueta("ultimos-30"))
        p.tocar(etiqueta("ultimos-30"))
        p.nodo(etiqueta("grilla-30"))
        assertEquals(1, servidor.a("mypump_get_adherencia_30d").size)
    }

    // ── REV-06: el check dice lo que falta ──

    @Test
    fun elCheckDiceLoQueFaltaYSaleConLasCuatro() {
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(texto("Faltan: Energía, Descanso, Hambre, Adherencia"))
        assertFalse(p.habilitado(etiqueta("enviar-check")))
        p.tocar(texto("Energía: 4 de 5"))
        p.tocar(texto("Descanso: 3 de 5"))
        p.tocar(texto("Hambre: 2 de 5"))
        p.nodo(texto("Faltan: Adherencia"))
        assertFalse(p.habilitado(etiqueta("enviar-check")))
        // Tocar el elegido lo borra.
        p.tocar(texto("Hambre: 2 de 5"))
        p.nodo(texto("Faltan: Hambre, Adherencia"))
        p.tocar(texto("Hambre: 2 de 5"))
        p.tocar(texto("Adherencia: 5 de 5"))
        p.esperarQueNoEste(textoQueContiene("Faltan:"))
        p.nodo(texto("4/4"))
        p.escribir(etiqueta("nota-check"), "Bien la semana, el sábado me pasé un poco.")
        Telefono.captura("revision-check-completo-claro")
        p.tocar(etiqueta("enviar-check"))
        val cuerpo = p.esperar("el check salió") { servidor.a("mypump_guardar_checkin").firstOrNull() }
        for (campo in listOf("\"p_energia\":4", "\"p_descanso\":3", "\"p_hambre\":2", "\"p_adherencia\":5", "\"p_nota\":\"Bien la semana")) {
            assertTrue("falta $campo en $cuerpo", campo in cuerpo)
        }
        p.nodo(etiqueta("check-enviado"))
        p.nodo(texto("Actualizar mi check"))
        // El badge de Revisión baja: ya solo faltan las fotos.
        p.esperar("el badge baja a 1") { "1" in p.textosBajo(etiqueta("pestana-revision")) }
    }

    // ── REV-07: el peso fuera de rango no sale ──

    @Test
    fun unPesoFueraDeRangoNoSeGuarda() {
        guardarCuenta()
        abrir()
        irARevision()
        // La cuenta grabada tiene 21 días de peso: el gráfico (la tendencia depende de la fecha del teléfono).
        p.nodo(etiqueta("grafico-peso"))
        p.escribir(etiqueta("peso-hoy"), "25")
        p.tocar(etiqueta("guardar-peso"))
        p.nodo(texto("Tiene que estar entre 30 y 300 kg."))
        Telefono.captura("revision-peso-invalido-claro")
        p.quieto(600)
        assertTrue("salió un peso inválido", servidor.a("mypump_ingest_salud").isEmpty())
        // Escribir de nuevo saca el aviso; uno válido sale por la cola, de fuente manual.
        p.escribir(etiqueta("peso-hoy"), "81,4")
        p.nodo(texto("En ayunas al despertar, siempre en la misma condición."))
        p.tocar(etiqueta("guardar-peso"))
        val cuerpo = p.esperar("el peso salió") { servidor.a("mypump_ingest_salud").firstOrNull() }
        assertTrue(cuerpo, "\"valor\":81.4" in cuerpo && "\"fuente\":\"manual\"" in cuerpo && "\"tipo\":\"peso_kg\"" in cuerpo)
        p.nodo(texto("Corregir"))
    }

    // ── REV-02/03/05: una foto de la cámara, reducida y subida ──

    @Test
    fun unaFotoDeLaCamaraSeReduceYSube() {
        val miniaturas = CopyOnWriteArrayList<String>()
        ImagenesRemotas.bajar = { url ->
            miniaturas += url
            null
        }
        val pedidos = fotosDePrueba(::fotoDeCamara)
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(texto("0/3"))
        p.tocar(etiqueta("foto-frente"))
        p.tocar(etiqueta("sacar-foto"))
        val subida = p.esperar("la foto subió", ms = 30_000) { servidor.fotosSubidas.firstOrNull() }
        assertEquals("frente", subida.pose)
        assertEquals(1, pedidos.count { it.action == MediaStore.ACTION_IMAGE_CAPTURE })
        // Lo que llegó: un JPEG de 900 px de alto, derecho y sin ubicación.
        assertTrue(subida.dataUrl.startsWith("data:image/jpeg;base64,"))
        val jpeg = Base64.decode(subida.dataUrl.substringAfter(","), Base64.DEFAULT)
        val r = FotoDePrueba.propiedades(jpeg)
        assertEquals(675 to 900, r.ancho to r.alto)
        assertNull("subió con la ubicación", r.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
        p.nodo(texto("Listo, guardada ✓"))
        p.esperar("el marco dice Lista") { p.estado(etiqueta("foto-frente")) == "Lista" }
        p.nodo(texto("1/3"))
        // La miniatura va con la URL firmada (`/progreso/urls`).
        p.esperar("se firmaron las URLs") { servidor.a("urls").firstOrNull() }
        p.esperar("se pidió la miniatura firmada") { miniaturas.firstOrNull { it.startsWith("https://fotos.prueba.invalid/$lunes/frente.jpg") } }
        // La foto de la cámara no queda en el teléfono.
        assertFalse("la foto quedó en la caché", ProveedorFotos.archivo(app, "frente").exists())
        // Sin pedir CAMERA: la saca la app de cámara.
        assertEquals(
            PackageManager.PERMISSION_DENIED,
            app.packageManager.checkPermission(android.Manifest.permission.CAMERA, app.packageName),
        )
    }

    /**
     * Sacar de nuevo una foto que ya estaba (un upsert: siguen siendo las mismas fotos) firma otra vez y muestra la
     * miniatura nueva. Antes quedaba la vieja hasta que vencían las URLs (visto contra la base real el 15-oct).
     */
    @Test
    fun reemplazarUnaFotoMuestraLaMiniaturaNueva() {
        val miniaturas = CopyOnWriteArrayList<String>()
        ImagenesRemotas.bajar = { url ->
            miniaturas += url
            null
        }
        servidor.ponerFotos(mapOf(lunes to listOf("frente")))
        fotosDePrueba(::fotoDeCamara)
        guardarCuenta()
        abrir()
        irARevision()
        p.esperar("la miniatura de antes") { miniaturas.firstOrNull { "/$lunes/frente.jpg" in it } }
        val firmasAntes = servidor.firmas
        p.tocar(etiqueta("foto-frente"))
        p.tocar(etiqueta("sacar-foto"))
        p.nodo(texto("Listo, guardada ✓"))
        p.nodo(texto("1/3"))
        p.esperar("se firmó de nuevo") { servidor.firmas > firmasAntes }
        p.esperar("se pidió la miniatura nueva") { miniaturas.firstOrNull { it == servidor.urlDeFoto(lunes, "frente", servidor.firmas) } }
    }

    /** Una HEIC de la galería (el selector de fotos del sistema) también entra, reducida a JPEG. */
    @Test
    fun unaHEICDeLaGaleriaTambien() {
        val heic = instr.context.assets.open("fotos/con-gps.heic").use { it.readBytes() }
        val pedidos = fotosDePrueba { heic }
        guardarCuenta()
        abrir()
        irARevision()
        p.tocar(etiqueta("foto-espalda"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        val subida = p.esperar("la foto subió", ms = 30_000) { servidor.fotosSubidas.firstOrNull() }
        assertEquals("espalda", subida.pose)
        assertTrue("no se abrió el selector de fotos", pedidos.any { it.action != MediaStore.ACTION_IMAGE_CAPTURE })
        val r = FotoDePrueba.propiedades(Base64.decode(subida.dataUrl.substringAfter(","), Base64.DEFAULT))
        assertEquals("image/jpeg", r.tipo)
        assertEquals(900 to 600, r.ancho to r.alto)
        assertNull(r.exif.getAttribute(ExifInterface.TAG_GPS_LATITUDE))
    }

    /** Lo que no es una foto se avisa, como la web, y no sube nada. */
    @Test
    fun loQueNoEsUnaFotoSeAvisa() {
        fotosDePrueba { "no es una foto".toByteArray() }
        guardarCuenta()
        abrir()
        irARevision()
        p.tocar(etiqueta("foto-perfil"))
        p.tocar(etiqueta("elegir-de-la-galeria"))
        p.nodo(texto("No se pudo leer esa foto"))
        p.nodo(texto("Probá con otra, o sacala con la cámara."))
        p.tocar(etiqueta("foto-ilegible-ok"))
        p.esperarQueNoEste(texto("No se pudo leer esa foto"))
        assertTrue(servidor.fotosSubidas.isEmpty())
    }

    // ── REV-03: la cola de 3 ──

    @Test
    fun conTresFotosEsperandoUnaMasNoEntra() {
        // Tres fotos de la semana pasada que todavía no pudieron subir (y el servicio de fotos sin red).
        val lunesPasado = DiaCalendario.texto(DiaCalendario.numero(lunes)!! - 7)
        val cola = FotosProgreso.poses.associate { (pose, _) ->
            "$lunesPasado|$pose" to FotoPendiente(pose, lunesPasado, "data:image/jpeg;base64,AAAA").aValor()
        }
        Disco(app.filesDir, ServidorDePrueba.TOKEN).guardar(FotoPendiente.ARCHIVO, ValorJson.Objeto(cola))
        servidor.fotosSinRed = true
        fotosDePrueba(::fotoDeCamara)
        guardarCuenta()
        abrir()
        irARevision()
        // Al abrir se intentó subirlas (sin red: no gastan intentos y siguen en la cola).
        p.esperar("se intentó drenar la cola") { servidor.a("upload").firstOrNull() }
        p.tocar(etiqueta("foto-frente"))
        p.tocar(etiqueta("sacar-foto"))
        p.nodo(texto("Hay fotos esperando subir. Probá cuando tengas señal."))
        Telefono.captura("revision-fotos-cola-llena-claro")
        assertTrue(servidor.fotosSubidas.isEmpty())
        // Las de esta semana siguen sin foto: la cuarta no entró.
        assertEquals("Agregar", p.estado(etiqueta("foto-frente")))
        assertEquals(3, (Disco(app.filesDir, ServidorDePrueba.TOKEN).leer(FotoPendiente.ARCHIVO) as kotlinx.serialization.json.JsonObject).size)
    }

    /** Sin señal la foto queda guardada en la cola y el marco dice "Esperando señal". */
    @Test
    fun sinSenalLaFotoEsperaEnLaCola() {
        servidor.fotosSinRed = true
        fotosDePrueba(::fotoDeCamara)
        guardarCuenta()
        abrir()
        irARevision()
        p.tocar(etiqueta("foto-perfil"))
        p.tocar(etiqueta("sacar-foto"))
        p.nodo(texto("Sin conexión: queda guardada y se sube sola."))
        p.esperar("el marco dice Esperando señal") { p.estado(etiqueta("foto-perfil")) == "Esperando señal" }
        // Cuenta como hecha para la semana (está en la cola).
        p.nodo(texto("1/3"))
    }

    // ── REV-04: la galería por semana y el comparador desde la 4.ª semana ──

    @Test
    fun laGaleriaPorSemanaYElComparadorDesdeLaCuarta() {
        val n = DiaCalendario.numero(lunes)!!
        val semanas = (0..4).map { DiaCalendario.texto(n - 7L * (4 - it)) }
        servidor.ponerFotos(semanas.associateWith { listOf("frente", "perfil", "espalda") })
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(texto("5 semanas seguidas registradas"))
        p.nodo(texto("Completas"))
        p.tocar(etiqueta("ver-mis-fotos"))
        p.nodo(etiqueta("galeria-fotos"))
        p.nodo(etiqueta("comparador"))
        p.nodo(texto("Antes y ahora"))
        // El pie del comparador: semanas y Δkg (el peso grabado arranca el 23-sep).
        p.nodo(textoQueContiene("4 semanas"))
        p.nodo(texto("Semana del ${com.pumpteam.mypump.revision.fechaLarga(lunes)}"))
        p.tocar(etiqueta("galeria-listo"))
        p.esperarQueNoEste(etiqueta("galeria-fotos"))
    }

    @Test
    fun conMenosDeCuatroSemanasElComparadorEspera() {
        servidor.ponerFotos(mapOf(lunes to listOf("frente")))
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(texto("Ver mis fotos · 1 semana"))
        p.nodo(texto("El comparador antes/después se abre en 3 semanas más."))
        p.tocar(etiqueta("ver-mis-fotos"))
        p.nodo(etiqueta("galeria-fotos"))
        assertFalse(p.existe(etiqueta("comparador")))
    }

    // ── Las anclas: el banner y ?scene=myday ──

    @Test
    fun elBannerConSoloElCheckLlevaAlCheck() {
        // Las fotos de la semana están: falta solo el check.
        servidor.ponerFotos(mapOf(lunes to listOf("frente", "perfil", "espalda")))
        guardarCuenta()
        abrir()
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(texto("Te falta tu check de la semana"))
        p.tocar(etiqueta("banner-revision"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.esperar("el check arriba de todo") { alturaYa("check").let { it in -0.05f..0.2f } }
        assertTrue("las fotos tendrían que quedar arriba, fuera de la vista", altura("fotos") < 0f)
        Telefono.captura("revision-ancla-check-claro")
    }

    @Test
    fun elBannerConLasFotosPendientesLlevaALasFotos() {
        guardarCuenta()
        abrir()
        irARevision()
        // Desplazada hasta abajo; el banner la lleva de nuevo a las fotos.
        p.desplazar(etiqueta("revision-lista"), 5_000f)
        p.esperar("bien abajo") { alturaYa("fotos") < -1f }
        p.tocar(etiqueta("pestana-dieta"))
        p.tocar(etiqueta("banner-revision"))
        p.esperar("las fotos arriba de todo") { alturaYa("fotos").let { it in -0.05f..0.2f } }
    }

    @Test
    fun unLinkConSceneMyDayAbreMiDia() {
        abrirConLink("https://app.mypumpteam.com/?t=${ServidorDePrueba.TOKEN}&scene=myday")
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.esperar("Mi día arriba de todo") { alturaYa("midia").let { it in -0.05f..0.2f } }
        Telefono.captura("revision-ancla-midia-claro")
        // Tocar la pestaña después vuelve donde quedó (el ancla se consumió: no salta de nuevo).
        p.tocar(etiqueta("pestana-entreno"))
        p.tocar(etiqueta("pestana-revision"))
        p.quieto(800)
        assertTrue(altura("midia") in -0.05f..0.2f)
    }

    @Test
    fun unAvisoDeRevisionAbreArriba() {
        guardarCuenta()
        abrir()
        irARevision()
        p.desplazar(etiqueta("revision-lista"), 5_000f)
        p.tocar(etiqueta("pestana-entreno"))
        app.startActivity(com.pumpteam.mypump.avisos.CentroAvisos.intentDeAviso(app, "myday"))
        p.esperar("Revisión elegida") { p.seleccionado(etiqueta("pestana-revision")) }
        p.esperar("Mi día arriba de todo") { alturaYa("midia").let { it in -0.05f..0.2f } }
    }

    // ── REV-08: Mi reloj ──

    /**
     * "Conectar" abre la autorización en el NAVEGADOR, fijo, aunque el link sea de `app.mypumpteam.com` y ese dominio
     * esté elegido para MyPump (como en un build de Play con el dominio verificado: `NavegadorFueraDeLaAppTest`). El
     * navegador no se abre de verdad (el link lleva el token y va al sitio real): el monitor se queda con el pedido.
     * "Quitar" pide confirmación.
     */
    @Test
    fun miRelojConectaPorElNavegadorYQuitarPregunta() {
        val paquete = app.packageName
        val dominio = "app.mypumpteam.com"
        val dejarComoEstaba = elegirElDominioParaLaApp(app, dominio)
        val navegador = CopyOnWriteArrayList<Intent>()
        val m = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_VIEW) return null
                navegador += intent
                return Instrumentation.ActivityResult(0, null)
            }
        }
        instr.addMonitor(m)
        monitores += m
        try {
            servidor.relojes = listOf("oura", "whoop")
            servidor.respuestas["mypump_get_conexiones"] = """[{"proveedor":"whoop","estado":"conectada","ultimo_pull_en":"2026-10-14T10:00:00Z"}]"""
            guardarCuenta()
            abrir()
            irARevision()
            p.nodo(etiqueta("card-reloj"))
            p.nodo(texto("Si usás Oura o WHOOP, conectalo y tus datos de sueño y recuperación entran solos. Tu reloj no se conecta acá: va por Health Connect."))
            p.nodo(texto("conectado"))
            p.nodo(textoQueContiene("Última sincronización: "))
            Telefono.captura("revision-mi-reloj-claro")

            // Quitar pregunta antes; Cancelar no hace nada.
            p.tocar(etiqueta("reloj-quitar-whoop"))
            p.nodo(texto("¿Quitar whoop?"))
            p.nodo(texto("Dejamos de traer tus datos. Los que ya están se quedan."))
            p.tocar(etiqueta("cancelar-quitar-reloj"))
            p.esperarQueNoEste(texto("¿Quitar whoop?"))
            assertTrue(servidor.a("mypump_desconectar_wearable").isEmpty())
            p.tocar(etiqueta("reloj-quitar-whoop"))
            p.tocar(etiqueta("confirmar-quitar-reloj"))
            p.esperar("se desconectó") { servidor.a("mypump_desconectar_wearable").firstOrNull { "\"p_proveedor\":\"whoop\"" in it } }

            // Conectar: el navegador fijo, nunca MyPump.
            p.tocar(etiqueta("reloj-conectar-oura"))
            val i = p.esperar("se abrió el navegador") { navegador.firstOrNull() }
            assertEquals("https://$dominio/api/wearables/iniciar?t=${ServidorDePrueba.TOKEN}&proveedor=oura", i.dataString)
            // Una Custom Tab con el navegador fijo o, sin un navegador con Custom Tabs (Android 9 del emulador), el selector de
            // navegadores: nunca MyPump.
            comprobarQueVaAlNavegador(i, app)
            // Sin fijarlo, el mismo link lo abriría MyPump (por eso va fijo).
            val implicito = Intent(Intent.ACTION_VIEW, Uri.parse(i.dataString)).addCategory(Intent.CATEGORY_BROWSABLE)
            assertEquals(paquete, app.packageManager.resolveActivity(implicito, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName)
            p.nodo(texto("Te va a abrir el sitio de oura. Cuando termines, volvé acá — se conecta solo."))
            p.nodo(texto("Abriendo…"))
            assertFalse(p.habilitado(etiqueta("reloj-conectar-oura")))
            // El callback no vuelve a la app: se pregunta cada 3 s hasta que aparece conectado.
            servidor.respuestas["mypump_get_conexiones"] = """[{"proveedor":"oura","estado":"conectada","ultimo_pull_en":null}]"""
            p.nodo(texto("✅ Listo. Tus datos van a aparecer en un rato."), ms = 15_000)
            p.esperar("Oura quedó conectado") { p.existe(etiqueta("reloj-quitar-oura")) }
        } finally {
            dejarComoEstaba()
        }
    }

    // ── SAL-09 y SAL-10: Recuperación y Salud dentro de Mi Día ──

    @Test
    fun recuperacionYSaludVanEnMiDia() {
        ModeloSalud.fuenteDelSistema = FuenteDeMentira()
        EstadoHealthConnect.forzado = EstadoHealthConnect.DISPONIBLE
        for (f in listOf("get_salud", "get_recuperacion", "get_mostrar_recuperacion")) {
            servidor.respuestas["mypump_$f"] = instr.context.assets.open("test-nativa-ios/$f.json").use { it.readBytes().toString(Charsets.UTF_8) }
        }
        guardarPreferencia(ClaveSalud.CONECTADO, "1")
        guardarPreferencia(ClaveSalud.HISTORIAL_HECHO, "1")
        guardarCuenta()
        abrir()
        irARevision()
        p.nodo(etiqueta("card-recuperacion"))
        p.nodo(etiqueta("card-salud"))
        // Después del agua y antes de los 30 días, como la web.
        val agua = p.nodo(etiqueta("agua")).positionInRoot.y
        val recuperacion = p.nodo(etiqueta("card-recuperacion")).positionInRoot.y
        val treinta = p.nodo(etiqueta("ultimos-30")).positionInRoot.y
        assertTrue("Recuperación fuera de lugar ($agua, $recuperacion, $treinta)", agua < recuperacion && recuperacion < treinta)
        p.tocar(etiqueta("ver-todos-mis-datos"))
        p.nodo(etiqueta("salud-detalle"))
        p.atras()
        p.esperarQueNoEste(etiqueta("salud-detalle"))
    }

    // ── La demo: se toca todo y no sale nada ──

    @Test
    fun laDemoSeTocaYNoEscribeNada() {
        abrir()
        p.tocar(etiqueta("ver-demo"))
        p.tocar(etiqueta("pestana-revision"))
        p.nodo(etiqueta("seccion-midia"))
        servidor.llamadas.clear()
        // Mi Día sembrado como la web: racha de 3 hasta hoy, "entrené", dieta y sueño cumplidos y 2 vasos.
        p.nodo(texto("⚡"))
        assertTrue(p.seleccionado(etiqueta("entrenamiento-entrene")))
        p.nodo(texto("2 de 12 vasos de agua"))
        p.tocar(texto("Hice cardio: sí"))
        p.esperar("cardio marcado") { p.estado(texto("Hice cardio: sí")) == "marcado" }
        p.tocar(texto("Un vaso más"))
        p.nodo(texto("3 de 12 vasos de agua"))
        // El check y el peso se llenan igual.
        for (t in listOf("Energía: 4 de 5", "Descanso: 4 de 5", "Hambre: 3 de 5", "Adherencia: 5 de 5")) p.tocar(texto(t))
        p.tocar(etiqueta("enviar-check"))
        p.nodo(etiqueta("check-enviado"))
        p.escribir(etiqueta("peso-hoy"), "80")
        p.tocar(etiqueta("guardar-peso"))
        p.nodo(texto("Corregir"))
        // Las fotos no se guardan (ni se abre la cámara).
        p.tocar(etiqueta("foto-frente"))
        p.nodo(texto("En la demo las fotos no se guardan."))
        assertFalse(p.existe(etiqueta("sacar-foto")))
        // Los 30 días de la demo, sin pedirlos.
        p.tocar(etiqueta("ultimos-30"))
        p.nodo(etiqueta("grilla-30"))
        p.nodo(texto("18/30"))
        // Sin cuenta no hay reloj ni salud.
        assertFalse(p.existe(etiqueta("card-reloj")))
        assertFalse(p.existe(etiqueta("card-recuperacion")))
        p.quieto(1_500)
        assertTrue("la demo tocó la red: ${servidor.llamadas.map { it.funcion }}", servidor.llamadas.isEmpty())
    }
}
