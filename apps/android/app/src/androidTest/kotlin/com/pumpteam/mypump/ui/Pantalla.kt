package com.pumpteam.mypump.ui

import android.graphics.Bitmap
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.toSize
import androidx.test.platform.app.InstrumentationRegistry
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Las ventanas de Compose de la app (la Activity, las hojas, los menús). `ui-test-junit4` no está en el proyecto, así que
 * se usan las mismas piezas públicas que usa esa librería: `ViewRootForTest.onViewCreatedCallback` avisa cada vez que se
 * crea una ventana de Compose.
 */
object Raices {
    private val vistas = CopyOnWriteArrayList<ViewRootForTest>()

    fun instalar() {
        vistas.clear()
        ViewRootForTest.onViewCreatedCallback = { vistas += it }
    }

    fun desinstalar() {
        ViewRootForTest.onViewCreatedCallback = null
        vistas.clear()
    }

    /** Las que están en pantalla ahora (una hoja que se cerró ya no). */
    fun activas(): List<ViewRootForTest> = vistas.filter { it.view.isAttachedToWindow && it.view.isShown }
}

/** Qué se busca: una etiqueta (`testTag`), un texto exacto o un texto que contiene algo. */
sealed interface Selector {
    fun coincide(n: SemanticsNode): Boolean

    data class Etiqueta(val tag: String) : Selector {
        override fun coincide(n: SemanticsNode) = n.config.getOrNull(SemanticsProperties.TestTag) == tag
        override fun toString() = "etiqueta «$tag»"
    }

    data class Texto(val texto: String, val parcial: Boolean = false) : Selector {
        override fun coincide(n: SemanticsNode): Boolean {
            val textos = textosDe(n)
            return textos.any { if (parcial) it.contains(texto) else it == texto }
        }

        override fun toString() = if (parcial) "texto que contiene «$texto»" else "texto «$texto»"
    }
}

fun etiqueta(tag: String): Selector = Selector.Etiqueta(tag)
fun texto(t: String): Selector = Selector.Texto(t)
fun textoQueContiene(t: String): Selector = Selector.Texto(t, parcial = true)

private fun textosDe(n: SemanticsNode): List<String> =
    (n.config.getOrNull(SemanticsProperties.Text)?.map { it.text } ?: emptyList()) +
        listOfNotNull(n.config.getOrNull(SemanticsProperties.EditableText)?.text) +
        (n.config.getOrNull(SemanticsProperties.ContentDescription) ?: emptyList())

/**
 * Lo que ve una prueba de interfaz: busca en el árbol de semántica SIN fusionar (cada texto en su nodo, con su etiqueta) y
 * toca con las acciones de semántica, lo mismo que hace un lector de pantalla. Todo se lee y se toca en el hilo principal;
 * cada búsqueda espera hasta que aparezca (la red de prueba, las animaciones y la Fase L de la migración son asíncronas).
 */
class Pantalla(private val esperaMs: Long = 15_000) {
    private val instr = InstrumentationRegistry.getInstrumentation()

    /** Corre en el hilo principal (si ya se está en él, directo: `runOnMainSync` desde el principal se traba). */
    fun <T> enPrincipal(f: () -> T): T {
        if (Looper.myLooper() == Looper.getMainLooper()) return f()
        var r: Result<T>? = null
        instr.runOnMainSync { r = runCatching(f) }
        return r!!.getOrThrow()
    }

    /** Todos los nodos de todas las ventanas a la vista, en orden de árbol. Solo en el hilo principal. */
    private fun nodos(): List<SemanticsNode> {
        val todos = ArrayList<SemanticsNode>()
        fun recorrer(n: SemanticsNode) {
            todos += n
            for (h in n.children) recorrer(h)
        }
        for (r in Raices.activas()) {
            try {
                r.measureAndLayoutForTest()
                recorrer(r.semanticsOwner.unmergedRootSemanticsNode)
            } catch (_: IllegalStateException) {
                // Una ventana que se está yendo (la hoja al cerrarse): se ignora en esta vuelta.
            }
        }
        return todos
    }

    /**
     * Espera hasta que [f] devuelva algo distinto de null/false, o falla con lo que había en pantalla. [f] corre en el hilo
     * principal salvo con `enElPrincipal = false` (un pantallazo no se saca desde ahí).
     */
    fun <T : Any> esperar(que: String, ms: Long = esperaMs, enElPrincipal: Boolean = true, f: () -> T?): T {
        val fin = SystemClock.uptimeMillis() + ms
        var ultimo: Throwable? = null
        while (true) {
            val r = try {
                if (enElPrincipal) enPrincipal(f) else f()
            } catch (e: Throwable) {
                // Lo que todavía no está (un nodo que no apareció, una ventana que se está yendo): se reintenta.
                ultimo = e
                null
            }
            if (r != null && r != false) return r
            if (SystemClock.uptimeMillis() > fin) throw AssertionError("No pasó en $ms ms: $que.\nEn pantalla: ${resumen()}", ultimo)
            Thread.sleep(40)
        }
    }

    /** El primer nodo que coincide (espera a que aparezca). */
    fun nodo(s: Selector, ms: Long = esperaMs): SemanticsNode = esperar("aparece $s", ms) { nodos().firstOrNull(s::coincide) }

    fun existe(s: Selector): Boolean = enPrincipal { nodos().any(s::coincide) }

    fun cuantos(s: Selector): Int = enPrincipal { nodos().count(s::coincide) }

    fun esperarQueNoEste(s: Selector, ms: Long = esperaMs) {
        esperar("desaparece $s", ms) { nodos().none(s::coincide) }
    }

    /** Lo deja quieto un rato (para afirmar que algo NO pasa). */
    fun quieto(ms: Long) {
        Thread.sleep(ms)
        instr.waitForIdleSync()
    }

    /** Toca: la acción de clic del nodo o, si es un texto adentro de un botón, la del primer ancestro que la tenga. */
    fun tocar(s: Selector, ms: Long = esperaMs) {
        esperar("se puede tocar $s", ms) {
            val n = nodos().firstOrNull(s::coincide) ?: return@esperar null
            var actual: SemanticsNode? = n
            while (actual != null) {
                val accion = actual.config.getOrNull(SemanticsActions.OnClick)?.action
                if (accion != null && actual.config.getOrNull(SemanticsProperties.Disabled) == null) {
                    accion()
                    return@esperar true
                }
                actual = actual.parent
            }
            null
        }
    }

    /** Escribe en un campo (reemplaza lo que tenía), como pegar el texto entero. */
    fun escribir(s: Selector, texto: String) {
        esperar("se puede escribir en $s") {
            val n = nodos().firstOrNull(s::coincide) ?: return@esperar null
            n.config.getOrNull(SemanticsActions.SetText)?.action?.invoke(AnnotatedString(texto)) ?: return@esperar null
            true
        }
        esperar("$s dice «$texto»") { nodos().firstOrNull(s::coincide)?.config?.getOrNull(SemanticsProperties.EditableText)?.text == texto }
    }

    fun habilitado(s: Selector): Boolean = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        n.config.getOrNull(SemanticsProperties.Disabled) == null
    }

    fun prendido(s: Selector): Boolean = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        n.config.getOrNull(SemanticsProperties.ToggleableState) == ToggleableState.On
    }

    fun seleccionado(s: Selector): Boolean = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        n.config.getOrNull(SemanticsProperties.Selected) == true
    }

    /** El estado que lee TalkBack después de la etiqueta (`stateDescription`, el `accessibilityValue` de iOS). */
    fun estado(s: Selector): String? = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        n.config.getOrNull(SemanticsProperties.StateDescription)
    }

    fun enfocado(s: Selector): Boolean = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        n.config.getOrNull(SemanticsProperties.Focused) == true
    }

    /** Desplaza una lista (la acción de desplazar de la semántica, como un lector de pantalla). */
    fun desplazar(s: Selector, dy: Float) {
        esperar("se puede desplazar $s") {
            val n = nodos().firstOrNull(s::coincide) ?: return@esperar null
            n.config.getOrNull(SemanticsActions.ScrollBy)?.action?.invoke(0f, dy) ?: return@esperar null
            true
        }
        quieto(300)
    }

    /** Lo que tiene escrito un campo. */
    fun textoDe(s: Selector): String = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        n.config.getOrNull(SemanticsProperties.EditableText)?.text ?: throw AssertionError("$s no es un campo")
    }

    /** Lo seleccionado en un campo (inicio y fin). */
    fun seleccion(s: Selector): Pair<Int, Int> = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        val r = n.config.getOrNull(SemanticsProperties.TextSelectionRange) ?: throw AssertionError("$s no es un campo")
        r.start to r.end
    }

    /**
     * Escribe en el campo enfocado como el teclado: lo nuevo va donde está el cursor y REEMPLAZA lo seleccionado (a
     * diferencia de [escribir], que pisa el campo entero).
     */
    fun teclear(s: Selector, texto: String) {
        esperar("se puede teclear en $s") {
            val n = nodos().firstOrNull(s::coincide) ?: return@esperar null
            n.config.getOrNull(SemanticsActions.InsertTextAtCursor)?.action?.invoke(AnnotatedString(texto)) ?: return@esperar null
            true
        }
    }

    /**
     * Toca de verdad: un dedo en el centro del nodo (bajar y subir), lo mismo que el cliente. A diferencia de [tocar] (la
     * acción de semántica), pasa por los gestos: en un campo de texto el toque además ubica el cursor.
     */
    fun tocarDeVerdad(s: Selector) {
        // Donde está el nodo en la pantalla, cuando ya está quieto (sin animación de entrada) y entero a la vista: un
        // nodo recién compuesto o recortado da un rectángulo vacío, y el toque caía en la barra de estado.
        var anterior: Pair<Float, Float>? = null
        val (x, y) = esperar("está quieto y a la vista $s") {
            for (r in Raices.activas()) {
                try {
                    r.measureAndLayoutForTest()
                } catch (_: IllegalStateException) {
                    continue
                }
                var hallado: SemanticsNode? = null
                fun buscar(n: SemanticsNode) {
                    if (hallado != null) return
                    if (s.coincide(n)) {
                        hallado = n
                        return
                    }
                    for (h in n.children) buscar(h)
                }
                buscar(r.semanticsOwner.unmergedRootSemanticsNode)
                val n = hallado ?: continue
                // Si una lista lo tapa (está abajo o arriba de lo que se ve), se la desplaza hasta que quede al medio.
                val entero = Rect(n.positionInRoot, n.size.toSize())
                var lista = n.parent
                while (lista != null && lista.config.getOrNull(SemanticsActions.ScrollBy) == null) lista = lista.parent
                if (lista != null) {
                    val ventana = lista.boundsInRoot
                    if (entero.top < ventana.top || entero.bottom > ventana.bottom) {
                        lista.config[SemanticsActions.ScrollBy].action?.invoke(0f, entero.center.y - ventana.center.y)
                        anterior = null
                        return@esperar null
                    }
                }
                val b = n.boundsInRoot
                if (b.width < 1f || b.height < 1f) return@esperar null
                if (b.left < 0f || b.top < 0f || b.right > r.view.width || b.bottom > r.view.height) return@esperar null
                val donde = IntArray(2)
                r.view.getLocationOnScreen(donde)
                val punto = (donde[0] + b.center.x) to (donde[1] + b.center.y)
                if (punto != anterior) {
                    anterior = punto
                    return@esperar null
                }
                return@esperar punto
            }
            null
        }
        val t = SystemClock.uptimeMillis()
        val abajo = MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
        val arriba = MotionEvent.obtain(t, t + 60, MotionEvent.ACTION_UP, x, y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
        instr.sendPointerSync(abajo)
        instr.sendPointerSync(arriba)
        abajo.recycle()
        arriba.recycle()
    }

    /** Los textos que hay debajo de un nodo (el resumen de una tarjeta, el contenido de un badge). */
    fun textosBajo(s: Selector): List<String> = enPrincipal {
        val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
        val out = ArrayList<String>()
        fun recorrer(x: SemanticsNode) {
            out += textosDe(x)
            for (h in x.children) recorrer(h)
        }
        recorrer(n)
        out
    }

    /** El botón Atrás del sistema (a la ventana que tenga el foco: la hoja, si hay una). */
    fun atras() {
        instr.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
    }

    /** Lo que hay en pantalla, para el mensaje de una prueba que falla. */
    fun resumen(): String = try {
        enPrincipal {
            nodos().mapNotNull { n ->
                val tag = n.config.getOrNull(SemanticsProperties.TestTag)
                val t = textosDe(n).joinToString(" | ")
                when {
                    tag != null && t.isNotEmpty() -> "[$tag] $t"
                    tag != null -> "[$tag]"
                    t.isNotEmpty() -> t
                    else -> null
                }
            }.joinToString(" · ").take(3_000)
        }
    } catch (e: Throwable) {
        "(no se pudo leer: $e)"
    }
}

/** Lo que se hace con el teléfono desde las pruebas: comandos de shell, capturas y el modo noche. */
object Telefono {
    private val instr get() = InstrumentationRegistry.getInstrumentation()

    /** Las capturas quedan acá y las baja `scripts/nativa/emu-ui.sh` (la carpeta de la app se borra al desinstalar). */
    const val CARPETA_CAPTURAS = "/data/local/tmp/mypump-capturas"

    fun shell(comando: String): String {
        val pfd = instr.uiAutomation.executeShellCommand(comando)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().toString(Charsets.UTF_8) }
    }

    fun captura(nombre: String) {
        Thread.sleep(400)   // que terminen las animaciones de entrada
        instr.waitForIdleSync()
        shell("mkdir -p $CARPETA_CAPTURAS")
        shell("screencap -p $CARPETA_CAPTURAS/$nombre.png")
    }

    fun pantallazo(): Bitmap = instr.uiAutomation.takeScreenshot()

    /** El modo noche del sistema (lo que sigue la app salvo que el cliente haya elegido oscuro). Recrea la Activity. */
    fun modoNoche(oscuro: Boolean) {
        shell("cmd uimode night ${if (oscuro) "yes" else "no"}")
    }

    /** Pantalla prendida y sin bloqueo, y la barra de estado quieta (9:41, batería llena) para que las capturas sean parejas. */
    fun prepararPantalla() {
        shell("svc power stayon true")
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        shell("settings put global sysui_demo_allowed 1")
        shell("am broadcast -a com.android.systemui.demo -e command enter")
        shell("am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941")
        shell("am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false")
        shell("am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e mobile show -e datatype none -e level 4")
        shell("am broadcast -a com.android.systemui.demo -e command notifications -e visible false")
    }

    /**
     * ¿La pantalla está oscura? La luminancia media de una franja del fondo (el margen izquierdo, a media altura), donde no
     * hay tarjetas ni texto: el fondo claro es #F2F2F7 y el oscuro, negro.
     */
    fun fondoOscuro(): Boolean {
        val b = pantallazo()
        try {
            var suma = 0.0
            var n = 0
            for (y in (b.height * 45 / 100) until (b.height * 55 / 100) step 6) {
                for (x in 2..10 step 2) {
                    val p = b.getPixel(x, y)
                    val r = (p shr 16) and 0xFF
                    val g = (p shr 8) and 0xFF
                    val bl = p and 0xFF
                    suma += (0.2126 * r + 0.7152 * g + 0.0722 * bl) / 255
                    n++
                }
            }
            return suma / n < 0.5
        } finally {
            b.recycle()
        }
    }
}
