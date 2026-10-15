package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de evidencia de Chat y Progreso, en claro y en oscuro (como CapturasUiTest, aparte para no pisar su
 * numeración). Quedan en [Telefono.CARPETA_CAPTURAS] y las baja `scripts/nativa/emu-ui.sh`.
 */
@RunWith(AndroidJUnit4::class)
class CapturasChatProgresoUiTest : PruebaUi() {
    private lateinit var chat: ChatDePrueba
    private var zonaAntes: TimeZone? = null

    @Before
    fun preparar() {
        chat = ChatDePrueba(servidor)
        Entorno.transporte = chat
        zonaAntes = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("America/Argentina/Buenos_Aires"))
    }

    @After
    fun zonaDeAntes() {
        TimeZone.setDefault(zonaAntes)
    }

    @Test
    fun chatEnClaro() = recorrerChat(oscuro = false)

    @Test
    fun chatEnOscuro() = recorrerChat(oscuro = true)

    @Test
    fun progresoEnClaro() = recorrerProgreso(oscuro = false)

    @Test
    fun progresoEnOscuro() = recorrerProgreso(oscuro = true)

    /**
     * Un hilo de tres días (como el boceto de iOS), uno que no salió y otro enviándose sin señal, el contador pasado de mil, el
     * hilo vacío, el esqueleto y la demo.
     */
    private fun recorrerChat(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        val zona = ZoneId.systemDefault()
        val hoy = LocalDate.now(zona)
        fun a(dias: Long, h: Int, m: Int) = hoy.minusDays(dias).atTime(h, m).atZone(zona).toInstant()
        chat.agregar("coach", "¿Cómo venís con la semana 5? Acordate que bajan las reps y sube la carga.", a(2, 11, 2), leido = true)
        chat.agregar("cliente", "¡Bien! El jalón lo subí a 55, me costó la última serie", a(2, 15, 40))
        chat.agregar("coach", "Perfecto, así es. Si la próxima te salen las 6 limpias, subí 2,5.", a(2, 15, 52), leido = true)
        chat.agregar("cliente", "Dale. Una duda: el sábado tengo un cumple, ¿qué hago con la cena?", a(1, 8, 15))
        chat.agregar("coach", "Disfrutalo. Ese día priorizá la proteína y mantené liviano el resto de las comidas.", a(1, 9, 2), leido = true)
        chat.agregar("coach", "Y el domingo seguimos como siempre.", a(1, 9, 3), leido = true)
        guardarCuenta()
        abrir().also { e ->
            val (vm, m) = p.modeloCargado(e)
            p.tocar(etiqueta("pestana-chat"))
            p.nodo(texto("Mati: Y el domingo seguimos como siempre."))
            foto("chat-01-conversacion")

            // Uno que la cola abandonó ("no salió") y otro sin señal ("enviando…").
            servidor.respuestas["mypump_agregar_comentario"] = "null"
            p.escribir(etiqueta("chat-campo"), "Te mando las fotos a la noche")
            p.tocar(etiqueta("chat-enviar"))
            val cola = m.outbox!!
            p.esperar("no salió", ms = 60_000, enElPrincipal = false) {
                if (p.existe(texto("no salió"))) true else null.also { runBlocking { cola.drenar() } }
            }
            servidor.respuestas.remove("mypump_agregar_comentario")
            servidor.sinRed = true
            p.escribir(etiqueta("chat-campo"), "¿Mañana entreno igual?")
            p.tocar(etiqueta("chat-enviar"))
            p.nodo(texto("enviando…"))
            foto("chat-02-no-salio-y-enviando")

            // Con señal sale lo pendiente; el contador, sin el aviso de guardado encima.
            servidor.sinRed = false
            p.enLaApp(vm) {
                m.outbox?.drenar()
                m.chat.value?.sondear()
            }
            p.esperarQueNoEste(texto("enviando…"))
            p.esperarQueNoEste(etiqueta("aviso-guardado"))
            p.escribir(etiqueta("chat-campo"), "a".repeat(1001))
            p.nodo(etiqueta("chat-contador"))
            foto("chat-03-contador")
        }.close()

        // El hilo vacío (otra cuenta en el mismo teléfono, sin mensajes).
        reiniciarEstado()
        chat = ChatDePrueba(servidor)
        Entorno.transporte = chat
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-chat"))
            p.nodo(etiqueta("chat-vacio"))
            foto("chat-04-vacio")
        }.close()

        // El esqueleto: la red lenta y el chat abierto antes de que llegue.
        servidor.demoraMs = 2_500
        abrir().also {
            p.nodo(etiqueta("pestana-chat"), ms = 40_000)
            p.tocar(etiqueta("pestana-chat"))
            p.nodo(etiqueta("chat-cargando"), ms = 40_000)
            foto("chat-05-cargando")
        }.close()
        servidor.demoraMs = 0

        reiniciarEstado()
        abrir().also {
            p.tocar(etiqueta("ver-demo"))
            p.tocar(etiqueta("pestana-chat"))
            p.nodo(etiqueta("chat-demo"))
            foto("chat-06-demo")
        }.close()
    }

    /** La lista con lo grabado, el detalle (con el dedo en el gráfico) y la tabla, peso corporal, sin red, cargando y vacío. */
    private fun recorrerProgreso(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-progreso"))
            p.esperar("los totales") { p.textosBajo(etiqueta("progreso-totales")).contains("32") }
            foto("progreso-01-lista")
            p.desplazar(etiqueta("progreso-lista"), 1_400f)
            foto("progreso-02-lista-abajo")
            p.desplazar(etiqueta("progreso-lista"), -3_000f)
            p.tocar(etiqueta("progreso-fila-jalon-al-pecho-prono-dorsal-ancho-d1-0"))
            p.nodo(etiqueta("progreso-grafico"))
            foto("progreso-03-detalle")
            val soltar = p.apoyar(textoQueContiene("Máximo por sesión: "), 0.6f)
            try {
                p.nodo(etiqueta("progreso-globo"))
                foto("progreso-04-detalle-con-el-dedo")
            } finally {
                soltar()
            }
            p.desplazar(etiqueta("progreso-detalle-contenido"), 1_200f)
            foto("progreso-05-tabla")
            p.tocar(etiqueta("volver"))
            p.tocar(etiqueta("progreso-fila-rollout-con-ab-wheel-core-anterior-d1-1"))
            p.nodo(texto("Con el peso del cuerpo, el progreso está en las repeticiones."))
            foto("progreso-06-peso-corporal")
        }.close()

        abrir().also { e ->
            p.modeloCargado(e)
            servidor.sinRed = true
            p.tocar(etiqueta("pestana-progreso"))
            p.nodo(etiqueta("progreso-sin-red"))
            foto("progreso-07-sin-red")
            servidor.sinRed = false
        }.close()

        servidor.demoraMs = 2_500
        abrir().also {
            p.nodo(etiqueta("pestana-progreso"), ms = 40_000)
            p.tocar(etiqueta("pestana-progreso"))
            p.nodo(etiqueta("progreso-cargando"), ms = 20_000)
            foto("progreso-08-cargando")
        }.close()
        servidor.demoraMs = 0

        reiniciarEstado()
        abrir().also {
            p.tocar(etiqueta("ver-demo"))
            p.tocar(etiqueta("pestana-progreso"))
            p.nodo(etiqueta("progreso-vacio"))
            foto("progreso-09-vacio")
        }.close()
    }
}
