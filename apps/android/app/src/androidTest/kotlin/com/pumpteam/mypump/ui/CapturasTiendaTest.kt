package com.pumpteam.mypump.ui

import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.datos.ConfigBackend
import com.pumpteam.mypump.datos.produccion
import com.pumpteam.mypump.diseno.ImagenesRemotas
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import java.time.Instant
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.delay
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de la ficha de Play (gemelo de `scripts/nativa/capturas-tienda-ios.sh`): Entreno, un ejercicio abierto con
 * series, Dieta, Revisión y Progreso, en claro y en oscuro. Las corre `scripts/nativa/capturas-tienda-android.sh`, que
 * achica la pantalla a 9:16 (Play no acepta un lado más del doble que el otro, y 1080×2400 lo es) y las baja.
 *
 * Los datos son los de siempre de las pruebas de interfaz: el [ServidorDePrueba] con las respuestas grabadas de la cuenta
 * de prueba `test-nativa-real`, con un token inventado. Nunca un cliente, y la API nunca va a la red. Lo único que sale
 * del teléfono son las fotos PÚBLICAS del catálogo de ejercicios (el bucket `exercise-images`, las mismas que ve
 * cualquiera en la demo): sin eso las cards muestran el marcador gris.
 *
 * Solo corre si se pide (`-e tienda 1`): en la suite de siempre queda salteada, así no depende de la red.
 */
@RunWith(AndroidJUnit4::class)
class CapturasTiendaTest : PruebaUi() {
    /** Fotos del catálogo que se están bajando, y cuándo cambió eso por última vez (para saber que terminaron). */
    private val bajando = AtomicInteger(0)
    private val ultimoMovimiento = AtomicLong(0)
    private val bajadas = ConcurrentHashMap.newKeySet<String>()
    private val fallidas = ConcurrentHashMap.newKeySet<String>()
    private val bloqueadas = ConcurrentHashMap.newKeySet<String>()

    @Before
    fun prepararTienda() {
        assumeTrue("solo con -e tienda 1 (scripts/nativa/capturas-tienda-android.sh)", InstrumentationRegistry.getArguments().getString("tienda") == "1")
        barraLimpia()
        // Después del @Before de PruebaUi, que deja las fotos sin red: acá pasan solo las del catálogo, por la red de verdad.
        ImagenesRemotas.vaciar()
        ImagenesRemotas.bajar = { url ->
            if (!esFotoDelCatalogo(url)) {
                bloqueadas += url
                null
            } else {
                bajando.incrementAndGet()
                ultimoMovimiento.set(SystemClock.uptimeMillis())
                try {
                    // Hasta tres intentos: una foto que no baja queda con el marcador en la captura.
                    var bytes: ByteArray? = null
                    for (intento in 1..3) {
                        bytes = try {
                            ImagenesRemotas.porRed(url)
                        } catch (e: CancellationException) {
                            throw e   // la card dejó de verse (se cambió de pantalla): no es una foto que falló
                        } catch (_: Exception) {
                            null
                        }
                        if (bytes != null) break
                        if (intento < 3) delay(1_000L * intento)
                    }
                    bytes.also { if (it != null) bajadas += url else fallidas += url }
                } finally {
                    bajando.decrementAndGet()
                    ultimoMovimiento.set(SystemClock.uptimeMillis())
                }
            }
        }
    }

    @Test
    fun enClaro() = recorrer(oscuro = false)

    @Test
    fun enOscuro() = recorrer(oscuro = true)

    private fun recorrer(oscuro: Boolean) {
        val modo = if (oscuro) "dark" else "light"
        Telefono.modoNoche(oscuro)

        // Revisión primero, con el check de la semana enviado y las fotos por sacar (como la de iOS): las tres poses
        // vacías con "Agregar". El badge de Revisión dice 1 (las fotos), y es la pestaña que se ve.
        checkEnviado()
        guardarCuenta()
        abrir().also {
            p.nodo(etiqueta("pestana-entreno"))
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("check-enviado"))
            p.nodo(etiqueta("foto-frente"))
            captura("$modo-4-revision")
        }.close()

        // El resto con la semana completa (check y fotos): sin badge ni el banner de Revisión arriba de cada pestaña. Y
        // Entreno con una sesión en curso: el calentamiento hecho y el jalón con 2 de 4 series.
        ponerFotosDeLaSemana()
        sesionEnCurso()
        abrir().also {
            p.tocar(etiqueta("pestana-entreno"))
            p.nodo(etiqueta("cronometro"))
            p.nodo(texto("2 de 9 ejercicios hechos"))
            p.esperarQueNoEste(etiqueta("banner-revision"))
            esperarFotos()
            captura("$modo-1-entreno")

            p.desplazar(etiqueta("entreno-lista"), 1_450f)
            p.tocar(etiqueta("ejercicio-jalon-al-pecho-prono-dorsal-ancho-d1-0"))
            p.nodo(etiqueta("pista-serie"))
            mostrarTablaEntera()
            esperarFotos()
            captura("$modo-2-ejercicio")
            p.tocar(etiqueta("volver"))
            p.nodo(etiqueta("entreno-lista"))

            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.373"))
            p.nodo(etiqueta("dieta-cabecera"))
            captura("$modo-3-dieta")

            p.tocar(etiqueta("pestana-progreso"))
            p.esperar("los totales de Progreso") { p.textosBajo(etiqueta("progreso-totales")).contains("32") }
            esperarFotos()
            captura("$modo-5-progreso")
        }.close()

        // El script lo junta del logcat para el informe.
        Log.i(ETIQUETA_LOG, "$modo: fotos del catálogo bajadas ${bajadas.size}, fallidas ${fallidas.size}, otras (no del catálogo) bloqueadas ${bloqueadas.size}")
        if (bajadas.isEmpty()) throw AssertionError("no bajó ninguna foto del catálogo (¿el emulador tiene red?): las cards quedan con el marcador")
        if (fallidas.isNotEmpty()) throw AssertionError("no bajaron ${fallidas.size} fotos del catálogo: alguna card quedó con el marcador")
    }

    /**
     * Si la tarjeta de series no entra entera (en un teléfono 9:16 no entra con la foto, la pauta y el cambio de la semana),
     * desplaza el ejercicio hasta que quede arriba, debajo de la barra (el nombre pasa a la barra). En la tablet entra sin
     * desplazar.
     */
    private fun mostrarTablaEntera() {
        val margen = 16 * app.resources.displayMetrics.density
        // Cuando la pantalla ya entró (mientras se desliza desde la derecha está afuera y sin tamaño) y quedó quieta.
        var anterior: Float? = null
        val desplazar = p.esperar("se ubica la tabla de series") {
            val visible = p.nodo(etiqueta("ejercicio-pantalla"), ms = 0).boundsInRoot
            val tabla = p.nodo(etiqueta("tabla-series"), ms = 0)
            if (visible.height < 1f || tabla.positionInRoot.x < 0f || tabla.positionInRoot.x >= visible.right) return@esperar null
            val arriba = tabla.positionInRoot.y
            val d = if (arriba + tabla.size.height + margen <= visible.bottom) 0f else arriba - visible.top - margen
            if (d != anterior) {
                anterior = d
                return@esperar null
            }
            d
        }
        if (desplazar > 0f) p.desplazar(etiqueta("ejercicio-pantalla"), desplazar)
    }

    // ── Los datos (sobre las respuestas grabadas de test-nativa-real) ──

    private val lunes: String get() = FotosProgreso.lunes(FechaLocal.hoy())

    private fun checkEnviado() {
        servidor.respuestas["mypump_get_checkin_semana"] =
            """[{"semana_lunes":"$lunes","energia":4,"descanso":3,"hambre":2,"adherencia":5,"nota":"Buena semana: llegué a todos los entrenos."}]"""
    }

    private fun ponerFotosDeLaSemana() {
        servidor.ponerFotos(mapOf(lunes to listOf("frente", "perfil", "espalda")))
    }

    /** Como `CapturasUiTest.recorrerEntreno`, sin el comentario sin leer (sería un badge en Entreno). */
    private fun sesionEnCurso() {
        val inicio = Instant.now().minusSeconds(23 * 60).toString()
        servidor.respuestas["mypump_get_sesion_dia"] =
            """[{"id":"ses-captura","dia_id":"d1","semana":5,"iniciada_en":"$inicio","finalizada_en":null}]"""
        val ayer = Instant.now().minusSeconds(26 * 3600)
        servidor.respuestas["mypump_get_sesiones_semana"] =
            """[{"dia_id":"d2","semana":5,"iniciada_en":"${ayer.minusSeconds(65 * 60)}","finalizada_en":"$ayer"}]"""
        servidor.respuestas["mypump_get_ejercicios_estado"] = """[
            {"ejercicio_id":"cinta-10-min-entrada-en-calor-d1-0","status":"completo_sin_datos","series_completadas":0,"marcado_manualmente":true},
            {"ejercicio_id":"rollout-con-ab-wheel-core-anterior-d1-1","status":"completo","series_completadas":3,"marcado_manualmente":false}]"""
        fun serie(ej: String, nombre: String, n: Int, kg: Number, reps: Int, rir: Int) =
            """{"ejercicio_id":"$ej","ejercicio_nombre":"$nombre","serie_numero":$n,"peso_kg":$kg,"reps_realizadas":$reps,"rir_real":$rir,"notas":null}"""
        servidor.respuestas["mypump_get_registros_sesion"] = "[" + listOf(
            serie("rollout-con-ab-wheel-core-anterior-d1-1", "Rollout con ab wheel (core anterior)", 1, 0, 13, 1),
            serie("rollout-con-ab-wheel-core-anterior-d1-1", "Rollout con ab wheel (core anterior)", 2, 0, 12, 1),
            serie("rollout-con-ab-wheel-core-anterior-d1-1", "Rollout con ab wheel (core anterior)", 3, 0, 12, 1),
            serie("jalon-al-pecho-prono-dorsal-ancho-d1-0", "Jalón al pecho prono (dorsal ancho)", 1, 60, 10, 0),
            serie("jalon-al-pecho-prono-dorsal-ancho-d1-0", "Jalón al pecho prono (dorsal ancho)", 2, 60, 9, 0),
        ).joinToString(",") + "]"
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-captura\""
    }

    // ── El teléfono ──

    /**
     * La barra de estado del modo demo de SystemUI: 9:41, batería llena, wifi lleno y SIN el «!» de "sin internet"
     * (`fully`), sin la señal del celular ni notificaciones. Se repite acá porque `PruebaUi` arma la suya antes (con el
     * celular y el wifi sin `fully`). La apaga el script al terminar.
     */
    private fun barraLimpia() {
        Telefono.shell("settings put global sysui_demo_allowed 1")
        for (c in BARRA) Telefono.shell("am broadcast -a com.android.systemui.demo $c")
    }

    /**
     * Espera que terminen de bajar las fotos del catálogo que pidió la pantalla: nada bajando y nada nuevo por un rato (la
     * pantalla las pide al componerse), más el fundido de `ImagenRemota`.
     */
    private fun esperarFotos() {
        p.quieto(300)
        p.esperar("las fotos del catálogo", ms = 60_000, enElPrincipal = false) {
            bajando.get() == 0 && SystemClock.uptimeMillis() - ultimoMovimiento.get() > 1_500
        }
        p.quieto(600)
    }

    private fun captura(nombre: String) {
        p.quieto(700)   // las animaciones de entrada y el fundido de las fotos
        Telefono.shell("mkdir -p $CARPETA")
        Telefono.shell("screencap -p $CARPETA/$nombre.png")
    }

    companion object {
        /** Donde quedan (las baja el script; la carpeta de la app se borra al desinstalar). */
        const val CARPETA = "/data/local/tmp/mypump-tienda"

        private const val ETIQUETA_LOG = "MyPumpTienda"

        /** Las fotos del catálogo de ejercicios: el bucket público `exercise-images`. Ni la API ni nada más. */
        private val PREFIJO_FOTOS = ConfigBackend.produccion.supabase + "/storage/v1/object/public/exercise-images/"

        fun esFotoDelCatalogo(url: String): Boolean =
            url.startsWith(PREFIJO_FOTOS) && !url.contains("..") && !url.contains('?') && !url.contains('#')

        private val BARRA = listOf(
            "-e command enter",
            "-e command clock -e hhmm 0941",
            "-e command battery -e level 100 -e plugged false -e powersave false",
            "-e command network -e wifi show -e level 4 -e fully true",
            "-e command network -e mobile hide",
            "-e command network -e airplane hide",
            "-e command notifications -e visible false",
            "-e command status -e volume hide -e bluetooth hide -e location hide -e alarm hide -e zen hide -e sync hide " +
                "-e tty hide -e eri hide -e mute hide -e speakerphone hide",
        )
    }
}
