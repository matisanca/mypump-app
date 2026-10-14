package com.pumpteam.mypump.acceso

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * D5: el tema sigue al teléfono salvo que el cliente haya elegido oscuro. Se guarda como en la web y en iOS
 * (`mypump-theme = "dark"`; sin la clave, sigue al sistema), en las mismas preferencias que [PreferenciasCompartidas]: así
 * lo que trae la migración de la Capacitor (que solo copia el `'dark'`) y el interruptor de Mis datos son lo mismo.
 *
 * Es un [StateFlow] porque cambia con la app abierta: el interruptor, o la Fase L de la migración escribiendo la
 * preferencia mientras se ve la marca.
 */
class Apariencia(contexto: Context) {
    private val prefs = contexto.getSharedPreferences(PreferenciasCompartidas.ARCHIVO, Context.MODE_PRIVATE)
    private val _oscuroGuardado = MutableStateFlow(leer())
    val oscuroGuardado: StateFlow<Boolean> = _oscuroGuardado.asStateFlow()

    // Las SharedPreferences guardan a sus oyentes con referencias débiles: el oyente tiene que vivir en un campo.
    private val oyente = SharedPreferences.OnSharedPreferenceChangeListener { _, clave ->
        // `null` = se borró todo (`clear()`).
        if (clave == null || clave == CLAVE) _oscuroGuardado.value = leer()
    }

    init {
        prefs.registerOnSharedPreferenceChangeListener(oyente)
    }

    private fun leer(): Boolean = prefs.getString(CLAVE, null) == OSCURO

    /** "Siempre en modo oscuro" de Mis datos. Apagado borra la clave: vuelve a seguir al teléfono. */
    fun forzarOscuro(oscuro: Boolean) {
        _oscuroGuardado.value = oscuro
        prefs.edit().apply { if (oscuro) putString(CLAVE, OSCURO) else remove(CLAVE) }.apply()
    }

    fun cerrar() {
        prefs.unregisterOnSharedPreferenceChangeListener(oyente)
    }

    companion object {
        const val CLAVE = "mypump-theme"
        const val OSCURO = "dark"
    }
}
