package com.pumpteam.mypump.ui

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import androidx.compose.ui.semantics.SemanticsNode
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import java.time.Instant
import java.time.OffsetDateTime
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * El chat del [ServidorDePrueba] con memoria, como la base: `mypump_get_chat` pagina de a `p_limite` hacia atrás desde
 * `p_antes` (de la más nueva a la más vieja, con `leido_por_cliente`), `mypump_chat_nuevos` trae lo posterior a `p_desde`
 * (sin ese campo, como la RPC de verdad), lo que se manda con `mypump_agregar_comentario` vuelve como una fila real del
 * cliente si el servidor no lo rechazó, y `mypump_marcar_leidos_cliente` deja leído lo de Mati.
 *
 * Se pone ENCIMA del servidor (`Entorno.transporte`): todo pasa primero por él, así que se anota igual, sin red tira y un
 * rechazo propio (`respuestas["mypump_agregar_comentario"] = "null"`) sigue siendo un rechazo. Lo demás contesta él.
 */
class ChatDePrueba(private val servidor: ServidorDePrueba) : Transporte {
    private class Fila(val id: String, val autor: String, val contenido: String, @Volatile var leido: Boolean, val creado: Instant)

    private val filas = CopyOnWriteArrayList<Fila>()
    private val secuencia = AtomicInteger()

    /** Un mensaje en el hilo (de Mati: sin leer). Devuelve su id. */
    fun agregar(autor: String, contenido: String, creado: Instant = Instant.now(), leido: Boolean = autor != "coach"): String {
        val id = "fila-${secuencia.incrementAndGet()}"
        filas += Fila(id, autor, contenido, leido, creado)
        return id
    }

    /** Lo que llegó del cliente (las filas reales que dejó la cola). */
    fun delCliente(): List<String> = filas.filter { it.autor == "cliente" }.map { it.contenido }

    fun sinLeerDeMati(): Int = filas.count { it.autor == "coach" && !it.leido }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val r = servidor.enviar(pedido)
        if (r.status != 200) return r
        val funcion = pedido.ruta.substringAfterLast('/')
        val cuerpo = try {
            JSONObject(pedido.cuerpo?.toString(Charsets.UTF_8) ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        return when (funcion) {
            "mypump_get_chat" -> {
                val antes = instante(cuerpo.optString("p_antes", ""))
                val limite = cuerpo.optInt("p_limite", 30)
                val pagina = filas.filter { antes == null || it.creado < antes }.sortedByDescending { it.creado }.take(limite)
                json(pagina, conLeido = true)
            }
            "mypump_chat_nuevos" -> {
                val desde = instante(cuerpo.optString("p_desde", "")) ?: Instant.EPOCH
                json(filas.filter { it.creado > desde }.sortedBy { it.creado }, conLeido = false)
            }
            "mypump_agregar_comentario" -> {
                // Si el servidor lo rechazó (la base devuelve vacío), no llegó.
                val texto = r.cuerpo.toString(Charsets.UTF_8).trim()
                if (texto !in setOf("null", "[]", "0", "false", "") && cuerpo.optString("p_ambito") == "general") {
                    agregar("cliente", cuerpo.optString("p_contenido"))
                }
                r
            }
            "mypump_marcar_leidos_cliente" -> {
                if (cuerpo.optString("p_ambito") == "general") filas.filter { it.autor == "coach" }.forEach { it.leido = true }
                r
            }
            else -> r
        }
    }

    private fun json(lista: List<Fila>, conLeido: Boolean): Respuesta {
        val a = JSONArray()
        for (f in lista) {
            val o = JSONObject().put("id", f.id).put("autor", f.autor).put("contenido", f.contenido).put("created_at", f.creado.toString())
            if (conLeido) o.put("leido_por_cliente", f.leido)
            a.put(o)
        }
        return Respuesta(200, a.toString().toByteArray())
    }

    private fun instante(s: String): Instant? {
        if (s.isEmpty() || s == "null") return null
        return runCatching { Instant.parse(s) }.getOrNull() ?: runCatching { OffsetDateTime.parse(s).toInstant() }.getOrNull()
    }
}

/** El ViewModel de la app abierta y su modelo, con la cuenta ya cargada (lo que miran las pruebas de Chat y Progreso). */
fun Pantalla.modeloCargado(e: ActivityScenario<MainActivity>): Pair<ModeloAppViewModel, ModeloApp> {
    var vm: ModeloAppViewModel? = null
    e.onActivity { a -> vm = ViewModelProvider(a)[ModeloAppViewModel::class.java] }
    val v = vm!!
    return v to esperar("la cuenta cargó") { v.modelo.value?.takeIf { it.fase.value == ModeloApp.Fase.LISTO } }
}

/** Lo que haría la app (un sondeo, una pasada de la cola), en su alcance y en el hilo principal, como lo pide una pantalla. */
fun Pantalla.enLaApp(vm: ModeloAppViewModel, f: suspend () -> Unit) {
    enPrincipal { vm.viewModelScope.launch { f() } }
}

/**
 * Apoya un dedo en [fraccion] del ancho de [s] (a media altura) y lo deja apoyado; devuelve cómo levantarlo. Es lo que hace
 * el cliente con el gráfico del detalle de Progreso para ver el valor de una sesión.
 */
fun Pantalla.apoyar(s: Selector, fraccion: Float): () -> Unit {
    fun buscar(n: SemanticsNode): SemanticsNode? {
        if (s.coincide(n)) return n
        for (h in n.children) buscar(h)?.let { return it }
        return null
    }
    val (x, y) = esperar("está a la vista $s") {
        for (r in Raices.activas()) {
            val n = buscar(r.semanticsOwner.unmergedRootSemanticsNode) ?: continue
            val b = n.boundsInRoot
            if (b.width < 1f || b.height < 1f) return@esperar null
            val donde = IntArray(2)
            r.view.getLocationOnScreen(donde)
            return@esperar (donde[0] + b.left + b.width * fraccion) to (donde[1] + b.center.y)
        }
        null
    }
    val instr = InstrumentationRegistry.getInstrumentation()
    val t = SystemClock.uptimeMillis()
    instr.sendPointerSync(MotionEvent.obtain(t, t, MotionEvent.ACTION_DOWN, x, y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN })
    return {
        val fin = SystemClock.uptimeMillis()
        instr.sendPointerSync(MotionEvent.obtain(t, fin, MotionEvent.ACTION_UP, x, y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN })
    }
}
