package com.pumpteam.mypump.guia

import android.Manifest
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
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
    /** Arranca a grabar en [archivo]. Tira si el micrófono no se puede usar (lo tiene otra app, una llamada). */
    fun empezar(archivo: File, alCortarse: () -> Unit)

    /** Frena. Devuelve false si no quedó nada que se pueda escuchar. */
    fun detener(): Boolean

    /** Frena sin importar lo grabado. */
    fun soltar()
}

/**
 * MediaRecorder con MPEG_4/AAC, mono, 64 kbps y 44,1 kHz (lo de iOS): `audio/mp4`, unos 2,4 MB en 5 minutos. En Android 9
 * y 10 (API < 31) va el constructor viejo. Sin servicio en primer plano: si la app se va, se frena (ver [ControlAudioDuda]).
 */
class GrabadorMediaRecorder(private val contexto: Context) : GrabadorAudio {
    private var rec: MediaRecorder? = null

    override fun empezar(archivo: File, alCortarse: () -> Unit) {
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
        } catch (e: Exception) {
            r.release()
            throw e
        }
    }

    override fun detener(): Boolean {
        val r = rec ?: return false
        rec = null
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
            g.empezar(f) { viewModelScope.launch { if (estado is Estado.Grabando) aplicar(MaquinaAudioDuda.seCorto()) } }
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
