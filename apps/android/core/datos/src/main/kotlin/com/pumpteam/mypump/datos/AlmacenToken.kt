package com.pumpteam.mypump.datos

import java.net.URLDecoder

/**
 * Dónde vive el acceso del cliente (el token de su link). En la app: cifrado con una clave del Keystore y fuera del
 * backup (`TokenEnKeystore`, en :app). En los tests: memoria.
 */
interface AlmacenToken {
    fun leer(): String?

    fun guardar(token: String?)
}

class TokenEnMemoria(private var token: String? = null) : AlmacenToken {
    @Synchronized override fun leer(): String? = token

    @Synchronized override fun guardar(token: String?) {
        this.token = token
    }
}

/**
 * Lo poco que la app recuerda fuera de la cuenta (`UserDefaults` en iOS, `localStorage` en la web): el tipo de día
 * elegido, el último token que se supo inválido, el token push registrado y las preferencias de avisos. En la app es
 * SharedPreferences; en los tests, memoria.
 */
interface Preferencias {
    fun leer(clave: String): String?

    fun guardar(clave: String, valor: String?)
}

class PreferenciasEnMemoria : Preferencias {
    private val mapa = HashMap<String, String>()

    @Synchronized override fun leer(clave: String): String? = mapa[clave]

    @Synchronized override fun guardar(clave: String, valor: String?) {
        if (valor == null) mapa.remove(clave) else mapa[clave] = valor
    }
}

/** El token tiene que tener esta forma (la misma regex de la web: deeplink.js y cliente.html). */
object FormatoToken {
    private val FORMA = Regex("[a-zA-Z0-9_-]{16,64}")

    fun valido(t: String): Boolean = FORMA.matches(t)

    /** Lo que pega el cliente: el link entero, a medias o el token solo (index.html:376-423). */
    fun extraer(texto: String): String? {
        val t = texto.trim()
        if (valido(t)) return t
        // `?t=<token>` del link del coach.
        val consulta = t.substringAfter('?', "").substringBefore('#')
        for (par in consulta.split('&')) {
            val partes = par.split('=', limit = 2)
            if (partes.size == 2 && decodificar(partes[0]) == "t") {
                val q = decodificar(partes[1]) ?: continue
                if (valido(q)) return q
            }
        }
        // El token como último tramo de la ruta (`…/acceso/<token>`).
        val ultimo = t.split('/').lastOrNull { it.isNotEmpty() }?.substringBefore('?')
        if (ultimo != null && valido(ultimo)) return ultimo
        // El mensaje entero de WhatsApp ("Hola! Este es tu link: https://…/?t=…"): el `[?&]t=` de la web.
        return EN_EL_MENSAJE.find(t)?.groupValues?.get(1)
    }

    private val EN_EL_MENSAJE = Regex("[?&]t=([a-zA-Z0-9_-]{16,64})")

    private fun decodificar(s: String): String? = try {
        URLDecoder.decode(s, Charsets.UTF_8)
    } catch (_: Exception) {
        null
    }
}
