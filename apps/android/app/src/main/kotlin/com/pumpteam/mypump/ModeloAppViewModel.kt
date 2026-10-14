package com.pumpteam.mypump

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pumpteam.mypump.acceso.PreferenciasCompartidas
import com.pumpteam.mypump.acceso.TokenEnKeystore
import com.pumpteam.mypump.datos.ModeloApp
import java.io.File
import kotlinx.coroutines.launch

/**
 * Dueño del [ModeloApp] mientras vive la app: sobrevive a rotar la pantalla y sus corrutinas (la cola, el sondeo del
 * chat) corren en el `viewModelScope`, en el hilo principal, como el `@MainActor` de iOS.
 *
 * Lo de Android vive acá: el token cifrado con el Keystore (fuera del backup), las preferencias y la carpeta de la app.
 */
class ModeloAppViewModel(app: Application) : AndroidViewModel(app) {
    val modelo = ModeloApp(
        almacen = TokenEnKeystore(File(app.noBackupFilesDir, TokenEnKeystore.ARCHIVO)),
        raizDisco = app.filesDir,
        preferencias = PreferenciasCompartidas(app),
        alcance = viewModelScope,
    )

    init {
        // El `.task` de RaizApp: con una cuenta guardada, se trae todo al abrir.
        viewModelScope.launch { if (modelo.fase.value == ModeloApp.Fase.CARGANDO) modelo.cargar() }
    }

    /** El link del coach (`https://app.mypumpteam.com/?t=…`) abrió la app. */
    fun abrirLink(link: String) {
        viewModelScope.launch { modelo.entrar(link) }
    }

    /** La app pasó a primer plano o a segundo: los sondeos solo corren a la vista (CHA-04). */
    fun primerPlano(visible: Boolean) {
        modelo.enPrimerPlano = visible
        if (visible) viewModelScope.launch { modelo.alVolverAPrimerPlano() }
    }
}
