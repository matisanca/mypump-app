package com.pumpteam.mypump.salud

import android.accessibilityservice.AccessibilityServiceInfo
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.platform.app.InstrumentationRegistry

/**
 * La hoja de permisos de Health Connect tocada como la tocaría el cliente, desde las pruebas (sin UI Automator, que no
 * está en el proyecto): se lee la pantalla con el `UiAutomation` de la instrumentación (la API del sistema) y se toca cada
 * cosa con su acción, buscando por resource-id (no por texto: así anda en cualquier idioma).
 *
 * Hace falta para sembrar: Health Connect deja AFUERA de los agregados (pasos, calorías, distancia) lo que escribió una
 * app que no está en su lista de prioridad, y a la lista entra quien recibe el permiso de escritura POR LA HOJA (con
 * `pm grant` no entra).
 */
object HojaHealthConnect {
    private val ua get() = InstrumentationRegistry.getInstrumentation().uiAutomation

    private fun nodos(): List<AccessibilityNodeInfo> {
        val info = ua.serviceInfo
        if (info.flags and AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS == 0) {
            info.flags = info.flags or AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            ua.serviceInfo = info
        }
        val raiz = ua.rootInActiveWindow ?: return emptyList()
        val todos = ArrayList<AccessibilityNodeInfo>()
        fun recorrer(n: AccessibilityNodeInfo) {
            todos += n
            for (i in 0 until n.childCount) n.getChild(i)?.let(::recorrer)
        }
        recorrer(raiz)
        return todos
    }

    private fun AccessibilityNodeInfo.id(): String = viewIdResourceName ?: ""

    /** Toca el nodo o, si no se deja, al primero de sus ancestros que se deje. */
    private fun tocar(n: AccessibilityNodeInfo) {
        var actual: AccessibilityNodeInfo? = n
        while (actual != null) {
            if (actual.isClickable && actual.performAction(AccessibilityNodeInfo.ACTION_CLICK)) return
            actual = actual.parent
        }
    }

    /**
     * Mientras esté la hoja (o la presentación de Health Connect de la primera vez): "Empezar", "Permitir todo" y
     * "Permitir". Vuelve cuando Health Connect ya no está en pantalla.
     */
    fun permitirTodo(esperaMs: Long = 30_000) {
        val fin = SystemClock.uptimeMillis() + esperaMs
        var vioLaHoja = false
        var ultima = emptyList<AccessibilityNodeInfo>()
        while (SystemClock.uptimeMillis() < fin) {
            val p = try {
                nodos()
            } catch (_: Exception) {
                emptyList()
            }
            ultima = p
            if (p.none { esDeHealthConnect(it.id()) }) {
                if (vioLaHoja) return
                Thread.sleep(400)
                continue
            }
            vioLaHoja = true
            // "Empezar" de la presentación: `primary_button_full` en el Health Connect de Android 16, `get_started_button` en el
            // de Android 14.
            val empezar = p.firstOrNull { it.id().endsWith(":id/primary_button_full") || it.id().endsWith(":id/get_started_button") }
            val todo = p.firstOrNull { it.id() == "android:id/switch_widget" && it.isCheckable }
            // "Permitir": `primary_button_outline` o `primary_button` en el de Android 16, `allow` en el de Android 14.
            val permitir = p.firstOrNull {
                it.id().endsWith(":id/primary_button_outline") || it.id().endsWith(":id/primary_button") || it.id().endsWith(":id/allow")
            }
            when {
                empezar != null -> tocar(empezar)
                todo != null && !todo.isChecked -> tocar(todo)
                permitir != null && permitir.isEnabled -> tocar(permitir)
            }
            Thread.sleep(800)
        }
        val visto = ultima.mapNotNull { n -> "${n.id()}|${n.text ?: ""}|${n.contentDescription ?: ""}".takeIf { it != "||" } }
        error("la hoja de Health Connect no se cerró en $esperaMs ms. En pantalla: ${visto.joinToString(" · ").take(2_500)}")
    }

    /**
     * Los recursos de la pantalla de Health Connect. Su paquete cambia: `com.android.healthconnect.controller` en Android 16 y
     * `com.google.android.healthconnect.controller` en el Android 14 de Google Play.
     */
    private fun esDeHealthConnect(id: String) = id.startsWith("com.android.healthconnect.controller:") ||
        id.startsWith("com.google.android.healthconnect.controller:")
}
