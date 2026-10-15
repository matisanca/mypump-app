package com.pumpteam.mypump.ui

import android.graphics.Bitmap
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewTreeObserver
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
import com.pumpteam.mypump.diseno.ImagenesRemotas
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import java.util.concurrent.atomic.AtomicInteger

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

    private companion object {
        /** Cuánto se espera a que algo aparezca solo antes de desplazar las listas perezosas para buscarlo ([Recorrido]). */
        const val GRACIA_MS = 1_000L

        /** Cuánto tiene que estar quieto un nodo en la pantalla para tocarlo con el dedo ([tocarDeVerdad]). */
        const val QUIETO_PARA_TOCAR_MS = 300L
    }

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

    /**
     * Busca un nodo y, si no está, desplaza las listas perezosas hasta encontrarlo: lo que hace `performScrollToNode` de
     * ui-test sobre lo desplazable. Una `LazyColumn` no compone lo que queda fuera de la vista, así que en una pantalla chica
     * (720×1280, el emulador de Android 9) «Desayuno» de Dieta no existe en el árbol hasta llegar a él; en una `Column` con
     * `verticalScroll` (Entreno, Revisión) todo está compuesto y no hace falta. Primero se espera [GRACIA_MS], porque lo
     * normal es que lo buscado esté o esté cargando; después, cada vuelta lleva cada lista perezosa a la vista al elemento
     * siguiente (`ScrollToIndex`, desde el primero) y al pasarse del último vuelve a empezar: lo buscado pudo llegar de la
     * red mientras tanto. Sin [desplazar] solo busca. Todo en el hilo principal.
     */
    private inner class Recorrido(private val desplazar: Boolean) {
        private val desde = SystemClock.uptimeMillis()
        private val siguiente = HashMap<Int, Int>()

        fun buscar(s: Selector): SemanticsNode? {
            val todos = nodos()
            todos.firstOrNull(s::coincide)?.let { return it }
            if (!desplazar || SystemClock.uptimeMillis() - desde < GRACIA_MS) return null
            for (lista in todos) {
                val ir = lista.config.getOrNull(SemanticsActions.ScrollToIndex)?.action ?: continue
                val i = siguiente[lista.id] ?: 0
                // Pasarse del último tira IllegalArgumentException ("out of bounds"): ahí se vuelve al primero.
                val fue = try {
                    ir(i)
                } catch (_: IllegalArgumentException) {
                    false
                }
                siguiente[lista.id] = if (fue) i + 1 else 0
            }
            return null
        }
    }

    /**
     * El primer nodo que coincide: espera a que aparezca y, si está en una lista perezosa fuera de la vista, desplaza hasta
     * él ([Recorrido]). Con `ms = 0` (para mirar adentro de otra espera) solo busca: no desplaza nada.
     */
    fun nodo(s: Selector, ms: Long = esperaMs): SemanticsNode {
        val r = Recorrido(desplazar = ms > 0)
        return esperar("aparece $s", ms) { r.buscar(s) }
    }

    /**
     * El nodo para leerle algo. Llamado desde la prueba, primero lo espera como [nodo] (y desplaza hasta él); adentro de un
     * [esperar] (en el hilo principal) solo lo busca: una espera anidada dormiría el hilo principal.
     */
    private fun <T> leer(s: Selector, f: (SemanticsNode) -> T): T {
        if (Looper.myLooper() != Looper.getMainLooper()) nodo(s)
        return enPrincipal {
            val n = nodos().firstOrNull(s::coincide) ?: throw AssertionError("no está $s")
            f(n)
        }
    }

    fun existe(s: Selector): Boolean = enPrincipal { nodos().any(s::coincide) }

    fun cuantos(s: Selector): Int = enPrincipal { nodos().count(s::coincide) }

    fun esperarQueNoEste(s: Selector, ms: Long = esperaMs) {
        esperar("desaparece $s", ms) { nodos().none(s::coincide) }
    }

    /** Lo deja quieto un rato (para afirmar que algo NO pasa). */
    fun quieto(ms: Long) {
        Thread.sleep(ms)
        Telefono.quietoConTope()
    }

    /**
     * Cuántas veces se dibujó alguna ventana de la app en [ms]. Una pantalla quieta no se dibuja; una animación sin fin (una
     * ruedita que no para) se dibuja decenas de veces por segundo. Sirve en todas las versiones: que el hilo principal no
     * quede quieto con una animación andando solo se nota en las viejas (ver [Telefono.quietoConTope]).
     */
    fun dibujosEn(ms: Long): Int {
        val dibujos = AtomicInteger()
        val escucha = ViewTreeObserver.OnDrawListener { dibujos.incrementAndGet() }
        val vistas = enPrincipal { Raices.activas().map { it.view }.onEach { it.viewTreeObserver.addOnDrawListener(escucha) } }
        try {
            Thread.sleep(ms)
        } finally {
            enPrincipal { for (v in vistas) if (v.viewTreeObserver.isAlive) v.viewTreeObserver.removeOnDrawListener(escucha) }
        }
        return dibujos.get()
    }

    /** Toca: la acción de clic del nodo o, si es un texto adentro de un botón, la del primer ancestro que la tenga. */
    fun tocar(s: Selector, ms: Long = esperaMs) {
        val r = Recorrido(desplazar = ms > 0)
        esperar("se puede tocar $s", ms) {
            val n = r.buscar(s) ?: return@esperar null
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
        val r = Recorrido(desplazar = true)
        esperar("se puede escribir en $s") {
            val n = r.buscar(s) ?: return@esperar null
            n.config.getOrNull(SemanticsActions.SetText)?.action?.invoke(AnnotatedString(texto)) ?: return@esperar null
            true
        }
        esperar("$s dice «$texto»") { nodos().firstOrNull(s::coincide)?.config?.getOrNull(SemanticsProperties.EditableText)?.text == texto }
    }

    fun habilitado(s: Selector): Boolean = leer(s) { n -> n.config.getOrNull(SemanticsProperties.Disabled) == null }

    fun prendido(s: Selector): Boolean = leer(s) { n -> n.config.getOrNull(SemanticsProperties.ToggleableState) == ToggleableState.On }

    fun seleccionado(s: Selector): Boolean = leer(s) { n -> n.config.getOrNull(SemanticsProperties.Selected) == true }

    /** El estado que lee TalkBack después de la etiqueta (`stateDescription`, el `accessibilityValue` de iOS). */
    fun estado(s: Selector): String? = leer(s) { n -> n.config.getOrNull(SemanticsProperties.StateDescription) }

    fun enfocado(s: Selector): Boolean = leer(s) { n -> n.config.getOrNull(SemanticsProperties.Focused) == true }

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
    fun textoDe(s: Selector): String = leer(s) { n ->
        n.config.getOrNull(SemanticsProperties.EditableText)?.text ?: throw AssertionError("$s no es un campo")
    }

    /** Lo seleccionado en un campo (inicio y fin). */
    fun seleccion(s: Selector): Pair<Int, Int> = leer(s) { n ->
        val r = n.config.getOrNull(SemanticsProperties.TextSelectionRange) ?: throw AssertionError("$s no es un campo")
        r.start to r.end
    }

    /**
     * Escribe en el campo enfocado como el teclado: lo nuevo va donde está el cursor y REEMPLAZA lo seleccionado (a
     * diferencia de [escribir], que pisa el campo entero).
     */
    fun teclear(s: Selector, texto: String) {
        val r = Recorrido(desplazar = true)
        esperar("se puede teclear en $s") {
            val n = r.buscar(s) ?: return@esperar null
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
        var quietoDesde = 0L
        val recorrido = Recorrido(desplazar = true)
        val (x, y) = esperar("está quieto y a la vista $s") {
            // Que esté compuesto (en una lista perezosa, desplazando hasta él); después se lo ubica entero en pantalla.
            recorrido.buscar(s) ?: return@esperar null
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
                    quietoDesde = SystemClock.uptimeMillis()
                    return@esperar null
                }
                // Quieto un rato y no solo dos lecturas seguidas: con el emulador cargado una transición puede tardar en
                // arrancar, y el toque caía donde estaba el campo antes de moverse (Android 11, 15-oct).
                if (SystemClock.uptimeMillis() - quietoDesde < QUIETO_PARA_TOCAR_MS) return@esperar null
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
    fun textosBajo(s: Selector): List<String> = leer(s) { n ->
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

    /**
     * Un comando de shell, con tope: `executeShellCommand` no tiene, y el 15-oct en Android 11 `svc power stayon true` quedó
     * vivo sin terminar nunca, y con él la corrida entera (13 minutos hasta matarlo a mano). Si no termina en [topeMs], se
     * cierra la salida y falla diciendo qué comando fue.
     */
    fun shell(comando: String, topeMs: Long = 30_000): String {
        val entrada = ParcelFileDescriptor.AutoCloseInputStream(instr.uiAutomation.executeShellCommand(comando))
        val leido = CompletableFuture<ByteArray>()
        Thread({ leido.complete(runCatching { entrada.readBytes() }.getOrElse { ByteArray(0) }) }, "shell-de-prueba").apply {
            isDaemon = true
            start()
        }
        try {
            return leido.get(topeMs, TimeUnit.MILLISECONDS).toString(Charsets.UTF_8)
        } catch (_: TimeoutException) {
            throw AssertionError("el comando de shell no terminó en ${topeMs / 1000} s: $comando")
        } finally {
            runCatching { entrada.close() }
        }
    }

    fun captura(nombre: String) {
        Thread.sleep(400)   // que terminen las animaciones de entrada
        quietoConTope()
        shell("mkdir -p $CARPETA_CAPTURAS")
        shell("screencap -p $CARPETA_CAPTURAS/$nombre.png")
    }

    /**
     * Espera a que el hilo principal quede quieto, como `Instrumentation.waitForIdleSync`, pero con tope. Con una animación
     * sin fin en pantalla, en Android 9 el hilo principal nunca queda quieto y `waitForIdleSync` no vuelve nunca: el 15-oct
     * la galería de fotos colgó la corrida 13 minutos, adentro de `ActivityScenario.close()`. Devuelve si quedó quieto antes
     * del tope.
     */
    fun quietoConTope(ms: Long = 20_000): Boolean {
        val quieto = CountDownLatch(1)
        instr.runOnMainSync {
            Looper.myQueue().addIdleHandler {
                quieto.countDown()
                false
            }
        }
        return quieto.await(ms, TimeUnit.MILLISECONDS)
    }

    fun pantallazo(): Bitmap = instr.uiAutomation.takeScreenshot()

    /** El modo noche del sistema (lo que sigue la app salvo que el cliente haya elegido oscuro). Recrea la Activity. */
    fun modoNoche(oscuro: Boolean) {
        shell("cmd uimode night ${if (oscuro) "yes" else "no"}")
    }

    /** Pantalla prendida y sin bloqueo, y la barra de estado quieta (9:41, batería llena) para que las capturas sean parejas. */
    fun prepararPantalla() {
        val comandos = listOf(
            "svc power stayon true",
            "input keyevent KEYCODE_WAKEUP",
            "wm dismiss-keyguard",
            "settings put global sysui_demo_allowed 1",
            "am broadcast -a com.android.systemui.demo -e command enter",
            "am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941",
            "am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false",
            "am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 -e mobile show -e datatype none -e level 4",
            "am broadcast -a com.android.systemui.demo -e command notifications -e visible false",
        )
        // Son comodidades (la pantalla ya está prendida en el emulador): uno que se cuelga no frena la clase entera.
        for (c in comandos) {
            try {
                shell(c)
            } catch (e: AssertionError) {
                Log.w("MyPumpPruebas", e.message ?: c)
            }
        }
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

/** Las fotos del catálogo de ejercicios en las pruebas: sin red (se ve el marcador), y al terminar, como en la app. */
object FotosDePrueba {
    fun sinRed() {
        ImagenesRemotas.bajar = { null }
        ImagenesRemotas.vaciar()
    }

    fun porRed() {
        ImagenesRemotas.bajar = ImagenesRemotas.porRed
    }
}
