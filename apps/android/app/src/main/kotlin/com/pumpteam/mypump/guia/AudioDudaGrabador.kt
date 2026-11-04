package com.pumpteam.mypump.guia

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pumpteam.mypump.datos.ModeloAudioDudas
import com.pumpteam.mypump.reglas.MaquinaAudioDuda
import com.pumpteam.mypump.reglas.MaquinaAudioDuda.Efecto
import com.pumpteam.mypump.reglas.MaquinaAudioDuda.Estado
import com.pumpteam.mypump.reglas.ReglasAudioDuda
import java.io.File
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Lo que graba. En la app es [GrabadorMediaRecorder]; en las pruebas de interfaz, un doble ([AudioDudaEntorno]). */
interface GrabadorAudio {
    /**
     * Arranca a grabar en [archivo]. Tira si el micrófono no se puede usar (lo tiene otra app, una llamada). [alCortarse]
     * avisa que se cortó a mitad de camino (llamada, pérdida del foco, micrófono silenciado, error): quien graba lo frena.
     */
    fun empezar(archivo: File, alCortarse: () -> Unit)

    /** Frena. Devuelve false si no quedó nada que se pueda escuchar. */
    fun detener(): Boolean

    /** Frena sin importar lo grabado. */
    fun soltar()
}

/**
 * MediaRecorder con MPEG_4/AAC, mono, 64 kbps y 44,1 kHz (lo de iOS): `audio/mp4`, unos 2,4 MB en 5 minutos. En Android 9
 * y 10 (API < 31) va el constructor viejo. Sin servicio en primer plano: si la app se va, se frena (ver [ControlAudioDuda]).
 *
 * Pide el foco del audio transitorio mientras graba (revisión del 4-nov, hallazgo 9): la música del cliente se pausa y, si
 * otra app o una llamada se lo lleva, avisa con `alCortarse`. Desde Android 10 también avisa si el sistema le silencia el
 * micrófono (otra app con prioridad, una llamada). No pide permisos nuevos (nada de READ_PHONE_STATE).
 */
class GrabadorMediaRecorder(private val contexto: Context) : GrabadorAudio {
    private var rec: MediaRecorder? = null
    private val audio: AudioManager? = contexto.getSystemService(AudioManager::class.java)
    private var foco: AudioFocusRequest? = null
    private var vigiaGrabacion: AudioManager.AudioRecordingCallback? = null
    private val principal = Handler(Looper.getMainLooper())

    private fun pedirFoco(alCortarse: () -> Unit) {
        val am = audio ?: return
        val pedido = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build(),
            )
            .setOnAudioFocusChangeListener({ cambio ->
                // Bajar el volumen para una notificación (CAN_DUCK) no corta: una llamada u otra app grabando, sí.
                if (cambio == AudioManager.AUDIOFOCUS_LOSS || cambio == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) alCortarse()
            }, principal)
            .build()
        // Con una llamada en curso el sistema lo niega: el micrófono no se puede usar.
        if (am.requestAudioFocus(pedido) == AudioManager.AUDIOFOCUS_REQUEST_FAILED) throw IllegalStateException("sin foco de audio")
        foco = pedido
    }

    private fun vigilarSilencio(r: MediaRecorder, alCortarse: () -> Unit) {
        val am = audio ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val cb = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>?) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || rec !== r) return
                if (runCatching { r.activeRecordingConfiguration?.isClientSilenced == true }.getOrDefault(false)) alCortarse()
            }
        }
        am.registerAudioRecordingCallback(cb, principal)
        vigiaGrabacion = cb
    }

    private fun soltarFoco() {
        vigiaGrabacion?.let { cb -> audio?.unregisterAudioRecordingCallback(cb) }
        vigiaGrabacion = null
        foco?.let { f -> audio?.abandonAudioFocusRequest(f) }
        foco = null
    }

    override fun empezar(archivo: File, alCortarse: () -> Unit) {
        pedirFoco(alCortarse)
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(contexto) else @Suppress("DEPRECATION") MediaRecorder()
        try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setAudioChannels(1)
            r.setAudioEncodingBitRate(64_000)
            r.setAudioSamplingRate(44_100)
            r.setMaxDuration((ReglasAudioDuda.TOPE_S + 5) * 1000)
            r.setOutputFile(archivo.absolutePath)
            r.setOnErrorListener { _, _, _ -> alCortarse() }
            r.prepare()
            r.start()
            rec = r
            vigilarSilencio(r, alCortarse)
        } catch (e: Exception) {
            r.release()
            soltarFoco()
            throw e
        }
    }

    override fun detener(): Boolean {
        val r = rec ?: return false.also { soltarFoco() }
        rec = null
        soltarFoco()
        return try {
            r.stop()   // tira si no llegó a grabar nada (RuntimeException de MediaRecorder)
            true
        } catch (_: RuntimeException) {
            false
        } finally {
            r.release()
        }
    }

    override fun soltar() {
        soltarFoco()
        val r = rec ?: return
        rec = null
        runCatching { r.stop() }
        r.release()
    }
}

/**
 * Lo que las pruebas de interfaz cambian antes de abrir la Activity: el grabador (el micrófono del emulador no siempre
 * existe) y la respuesta del permiso (el cartel del sistema no se puede tocar desde la prueba). En la app, los dos son null.
 */
object AudioDudaEntorno {
    @Volatile var grabador: ((Context) -> GrabadorAudio)? = null

    /** true: como si lo hubiera dado; false: como si lo negara (también al pedirlo). */
    @Volatile var permiso: Boolean? = null
}

/**
 * El grabador de las dudas en audio, en un ViewModel: sobrevive al giro de pantalla (la Activity se arma de nuevo y lo que
 * estaba grabando sigue). Corre la [MaquinaAudioDuda] con el MediaRecorder y un MediaPlayer para la revisión. El permiso lo
 * pide la pantalla (necesita la Activity) y le avisa con [alPermiso].
 */
class ControlAudioDuda(app: Application) : AndroidViewModel(app) {
    var estado: Estado by mutableStateOf(Estado.Reposo)
        private set
    var aviso: MaquinaAudioDuda.Aviso? by mutableStateOf(null)
        private set

    /** Los segundos que van, para el contador (la máquina solo los calcula al terminar). */
    var segundos by mutableIntStateOf(0)
        private set
    var escuchando by mutableStateOf(false)
        private set
    var posicionEscucha by mutableIntStateOf(0)
        private set

    /** Se está moviendo el audio a la cola (un toque doble en «Mandar» no lo manda dos veces). */
    var mandando by mutableStateOf(false)
        private set

    private val carpeta = File(app.cacheDir, "audio-duda")
    private var archivo: File? = null
    private var grabador: GrabadorAudio? = null
    private var reloj: Job? = null
    private var reproductor: MediaPlayer? = null

    private fun ahora() = SystemClock.elapsedRealtime()

    /** Lo que se hace antes de grabar o escuchar (pausar el video de la guía, sacar el foco del campo). */
    var alEmpezar: () -> Unit = {}

    fun permisoActual(): MaquinaAudioDuda.Permiso {
        AudioDudaEntorno.permiso?.let { return if (it) MaquinaAudioDuda.Permiso.CONCEDIDO else MaquinaAudioDuda.Permiso.SIN_PEDIR }
        val ok = ContextCompat.checkSelfPermission(getApplication(), Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        return if (ok) MaquinaAudioDuda.Permiso.CONCEDIDO else MaquinaAudioDuda.Permiso.SIN_PEDIR
    }

    /** Tocó «Grabar un audio» o «Grabar de nuevo». [pedirPermiso] abre el cartel del sistema. */
    fun grabar(permiso: MaquinaAudioDuda.Permiso, pedirPermiso: () -> Unit) {
        val paso = MaquinaAudioDuda.grabar(estado, permiso)
        aplicar(paso)
        if (Efecto.PedirPermiso in paso.efectos) {
            if (AudioDudaEntorno.permiso == false) alPermiso(false) else pedirPermiso()
        }
    }

    fun alPermiso(concedido: Boolean) = aplicar(MaquinaAudioDuda.permiso(concedido))

    fun terminar() = aplicar(MaquinaAudioDuda.terminar(estado, ahora()))

    /** La app se fue a segundo plano o se salió de la guía: se frena y pasa a revisar. */
    fun segundoPlano() {
        pararEscucha()
        if (estado is Estado.Grabando) terminar()
    }

    fun borrar() = aplicar(MaquinaAudioDuda.borrar(estado))

    /** «Mandar». En la demo, el aviso de vista previa. */
    fun mandar(audios: ModeloAudioDudas) {
        if (mandando) return
        val paso = MaquinaAudioDuda.mandar(estado, vistaPrevia = audios.esDemo)
        val encolar = paso.efectos.filterIsInstance<Efecto.Encolar>().firstOrNull()
        if (encolar == null) {
            aplicar(paso)
            return
        }
        val f = archivo ?: return
        pararEscucha()
        mandando = true
        viewModelScope.launch {
            try {
                if (audios.mandar(f, encolar.segundos)) {
                    archivo = null
                    estado = paso.estado
                    aviso = null
                } else {
                    aviso = MaquinaAudioDuda.Aviso(ReglasAudioDuda.NO_SE_PUDO, error = true)
                }
            } finally {
                mandando = false
            }
        }
    }

    fun avisoVisto() {
        aviso = null
    }

    // ── La revisión ──

    fun escuchar() {
        if (escuchando) {
            reproductor?.pause()
            escuchando = false
            return
        }
        val f = archivo ?: return
        alEmpezar()
        val mp = reproductor ?: try {
            MediaPlayer().apply {
                setDataSource(f.absolutePath)
                prepare()
                setOnCompletionListener {
                    escuchando = false
                    posicionEscucha = 0
                    it.seekTo(0)
                }
            }.also { reproductor = it }
        } catch (_: Exception) {
            aviso = MaquinaAudioDuda.Aviso(ReglasAudioDuda.MUY_CORTO, error = true)
            return
        }
        mp.start()
        escuchando = true
        viewModelScope.launch {
            while (isActive && escuchando) {
                posicionEscucha = runCatching { mp.currentPosition / 1000 }.getOrDefault(0)
                delay(250)
            }
        }
    }

    private fun pararEscucha() {
        escuchando = false
        posicionEscucha = 0
        reproductor?.let { runCatching { it.stop() }; it.release() }
        reproductor = null
    }

    // ── Lo de adentro ──

    private fun aplicar(p: MaquinaAudioDuda.Paso) {
        for (e in p.efectos) when (e) {
            Efecto.Descartar -> descartar()
            Efecto.Detener -> detener()
            Efecto.Empezar, Efecto.PedirPermiso, is Efecto.Encolar -> Unit
        }
        estado = p.estado
        aviso = p.aviso ?: if (Efecto.Empezar in p.efectos || Efecto.Descartar in p.efectos) null else aviso
        if (Efecto.Empezar in p.efectos) empezar()
    }

    private fun empezar() {
        val app = getApplication<Application>()
        if (AudioDudaEntorno.grabador == null && !app.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)) {
            aplicar(MaquinaAudioDuda.noEmpezo(MaquinaAudioDuda.Fallo.SIN_MICROFONO))
            return
        }
        alEmpezar()
        pararEscucha()
        carpeta.mkdirs()
        carpeta.listFiles()?.forEach { it.delete() }
        val f = File(carpeta, "grabacion-${System.currentTimeMillis()}.m4a")
        val g = AudioDudaEntorno.grabador?.invoke(app) ?: GrabadorMediaRecorder(app)
        try {
            // Una llamada, otra app con el foco del audio, el micrófono silenciado o un error: se frena y pasa a revisar.
            g.empezar(f) { viewModelScope.launch { if (estado is Estado.Grabando) aplicar(MaquinaAudioDuda.seCorto(estado, ahora())) } }
        } catch (_: Exception) {
            f.delete()
            aplicar(MaquinaAudioDuda.noEmpezo(MaquinaAudioDuda.Fallo.OCUPADO))
            return
        }
        archivo = f
        grabador = g
        segundos = 0
        aplicar(MaquinaAudioDuda.empezo(ahora()))
        reloj?.cancel()
        reloj = viewModelScope.launch {
            while (isActive) {
                delay(200)
                val e = estado as? Estado.Grabando ?: break
                segundos = e.segundos(ahora())
                MaquinaAudioDuda.tic(e, ahora())?.let(::aplicar)
            }
        }
    }

    private fun detener() {
        reloj?.cancel()
        reloj = null
        val g = grabador
        grabador = null
        if (g != null && !g.detener()) {
            // MediaRecorder no dejó nada que se pueda escuchar: como si fuera muy corto.
            archivo?.delete()
            archivo = null
            viewModelScope.launch {
                estado = Estado.Reposo
                aviso = MaquinaAudioDuda.Aviso(ReglasAudioDuda.MUY_CORTO, error = true)
            }
        }
    }

    private fun descartar() {
        reloj?.cancel()
        reloj = null
        grabador?.soltar()
        grabador = null
        pararEscucha()
        archivo?.delete()
        archivo = null
        segundos = 0
    }

    override fun onCleared() {
        descartar()
    }
}
