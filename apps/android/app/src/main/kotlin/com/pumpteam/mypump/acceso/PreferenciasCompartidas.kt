package com.pumpteam.mypump.acceso

import android.content.Context
import com.pumpteam.mypump.datos.Preferencias

/**
 * Lo poco que la app recuerda fuera de la cuenta (el `UserDefaults` de iOS, el `localStorage` de la web): tipo de día,
 * el último link que se supo inválido, el token de push registrado y los avisos. Nada de esto es secreto ni de la cuenta,
 * así que puede ir en la copia de Google (ver reglas_backup.xml).
 */
class PreferenciasCompartidas(contexto: Context) : Preferencias {
    private val prefs = contexto.getSharedPreferences(ARCHIVO, Context.MODE_PRIVATE)

    override fun leer(clave: String): String? = prefs.getString(clave, null)

    override fun guardar(clave: String, valor: String?) {
        prefs.edit().apply { if (valor == null) remove(clave) else putString(clave, valor) }.apply()
    }

    companion object {
        const val ARCHIVO = "mypump"
    }
}
