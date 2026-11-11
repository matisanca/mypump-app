package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ItemSuplemento
import com.pumpteam.mypump.modelos.ValorJson
import java.net.URI

/*
 * Compras por país, «Dónde comprarlo» (2.3.0, palanca `compras_pais`). Contrato en `cola-b/CONTRATO_APP.md`, sección 2.
 * La app no inventa nada: ni país por defecto, ni tiendas, ni búsquedas armadas. Lo que no viene verificado, no se ve.
 */

data class OpcionCompra(
    val producto: String,
    val tienda: String,
    /** Solo `https://`. Cualquier otra cosa llega como null: la opción se muestra sin botón. */
    val url: String?,
    val nota: String?,
)

/** Lo que dijo `mypump_compras_get`, ya cruzable: nombre del ítem (recortado) → sus opciones. */
data class ComprasPais(val pais: String?, val items: Map<String, List<OpcionCompra>>) {
    val vacio: Boolean get() = items.isEmpty()
}

object Compras {
    const val MAX_OPCIONES = 4

    /** null: `habilitado` no es true (no se ve nada). Con `items` vacío tampoco se ve nada, pero es una respuesta válida. */
    fun leer(j: ValorJson): ComprasPais? {
        if (j["habilitado"] != ValorJson.Booleano(true)) return null
        val items = LinkedHashMap<String, List<OpcionCompra>>()
        for (it in (j["items"] as? ValorJson.Lista)?.elementos ?: emptyList()) {
            val nombre = it["nombre"]?.comoTexto?.trim()?.takeIf { n -> n.isNotEmpty() } ?: continue
            if (nombre in items) continue
            val opciones = ((it["opciones"] as? ValorJson.Lista)?.elementos ?: emptyList()).mapNotNull(::opcion).take(MAX_OPCIONES)
            if (opciones.isNotEmpty()) items[nombre] = opciones
        }
        return ComprasPais(texto(j["pais"]), items)
    }

    private fun texto(v: ValorJson?): String? = v?.comoTexto?.trim()?.takeIf { it.isNotEmpty() }

    /** Una opción necesita producto y tienda; sin eso no hay qué mostrar. */
    private fun opcion(o: ValorJson): OpcionCompra? =
        OpcionCompra(texto(o["producto"]) ?: return null, texto(o["tienda"]) ?: return null, urlSegura(o["url"]?.comoTexto), texto(o["nota"]))

    /** La dirección tal cual si es `https://` con un sitio; si no, null (http, otros esquemas, texto suelto, con espacios). */
    fun urlSegura(s: String?): String? {
        val u = s?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (!u.startsWith("https://", ignoreCase = true) || u.any { it.isWhitespace() || it.isISOControl() }) return null
        return try {
            val uri = URI(u)
            if (uri.scheme.equals("https", ignoreCase = true) && !uri.host.isNullOrEmpty() && uri.userInfo == null) u else null
        } catch (_: Exception) {
            null
        }
    }

    /** Las opciones de un ítem de la pestaña: por nombre exacto, después de recortar espacios. */
    fun opcionesDe(nombre: String, compras: ComprasPais?): List<OpcionCompra> = compras?.items?.get(nombre.trim()) ?: emptyList()

    /**
     * Qué ítems de la suplementación llevan el botón «Dónde comprarlo»: índice del ítem → opciones. Los que se dejan de
     * tomar no lo llevan.
     */
    fun porItem(items: List<ItemSuplemento>, compras: ComprasPais?): Map<Int, List<OpcionCompra>> {
        if (compras == null || compras.vacio) return emptyMap()
        val r = LinkedHashMap<Int, List<OpcionCompra>>()
        for ((i, it) in items.withIndex()) {
            if (it.estado == "sale") continue
            opcionesDe(it.nombre, compras).takeIf { o -> o.isNotEmpty() }?.let { o -> r[i] = o }
        }
        return r
    }

    object Textos {
        const val BOTON = "Dónde comprarlo"
        const val AYUDA = "Tocá “Dónde comprarlo” para ver dónde conseguir cada suplemento."
        const val SUBTITULO = "Dónde comprarlo"
        const val ABRIR_TIENDA = "Abrir la tienda"
        const val PIE = "Son lugares que Mati revisó."
        const val CERRAR = "Cerrar"

        val todos = listOf(BOTON, AYUDA, SUBTITULO, ABRIR_TIENDA, PIE, CERRAR)
    }
}
