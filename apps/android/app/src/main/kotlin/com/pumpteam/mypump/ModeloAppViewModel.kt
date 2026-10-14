package com.pumpteam.mypump

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.acceso.TokenEnKeystore
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.legado.ArranqueMigracion
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Dueño del [ModeloApp] mientras vive la app: sobrevive a rotar la pantalla y sus corrutinas (la cola, el sondeo del
 * chat) corren en el `viewModelScope`, en el hilo principal, como el `@MainActor` de iOS.
 *
 * Lo de Android vive acá: el token cifrado con el Keystore (fuera del backup), las preferencias y la carpeta de la app.
 *
 * El modelo NO existe desde el principio: antes corre la Fase L de la migración del almacenamiento viejo
 * ([ArranqueMigracion]), porque el modelo lee el token y la cola al iniciar. En un teléfono que viene de la app Capacitor
 * eso es un WebView oculto (unos segundos, una sola vez); en los demás arranques, mirar fechas y tamaños de archivos.
 * Mientras tanto [modelo] es null y se ve la marca.
 */
class ModeloAppViewModel(app: Application) : AndroidViewModel(app) {
    private val almacen = TokenEnKeystore(File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO))
    private val preferencias = PreferenciasCompartidas(app)
    private val _modelo = MutableStateFlow<ModeloApp?>(null)
    val modelo: StateFlow<ModeloApp?> = _modelo.asStateFlow()

    /** Lo que dijo la Activity antes de que el modelo existiera. */
    private var aLaVista = true

    init {
        viewModelScope.launch {
            val m = ArranqueMigracion.arrancar(app, almacen, preferencias, viewModelScope) {
                ModeloApp(almacen = almacen, raizDisco = app.filesDir, preferencias = preferencias, alcance = viewModelScope)
            }
            m.enPrimerPlano = aLaVista
            _modelo.value = m
            // El `.task` de RaizApp: con una cuenta guardada, se trae todo al abrir.
            if (m.fase.value == ModeloApp.Fase.CARGANDO) m.cargar()
        }
    }

    /** El link del coach (`https://app.mypumpteam.com/?t=…`) abrió la app. Si la migración todavía corre, espera al modelo. */
    fun abrirLink(link: String) {
        viewModelScope.launch { _modelo.filterNotNull().first().entrar(link) }
    }

    /** La app pasó a primer plano o a segundo: los sondeos solo corren a la vista (CHA-04). */
    fun primerPlano(visible: Boolean) {
        aLaVista = visible
        val m = _modelo.value ?: return
        m.enPrimerPlano = visible
        if (visible) viewModelScope.launch { m.alVolverAPrimerPlano() }
    }
}
