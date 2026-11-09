package com.pumpteam.mypump.ui

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.lifecycle.ViewModelProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.MainActivity
import com.pumpteam.mypump.ModeloAppViewModel
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.irADia
import com.pumpteam.mypump.reglas.DiasDieta
import com.pumpteam.mypump.reglas.FechaLocal
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Cargar días anteriores en Dieta y copiar a hoy (gemela de los XCUITest de iOS): el selector abre en Hoy, un día anterior
 * tiene su aviso y su vuelta, «Comí» en ayer va con la fecha de ayer y copiar de ayer no pisa lo de hoy sin preguntar. Con la
 * cuenta del [ServidorDePrueba]: nunca va a la red. Las capturas de evidencia quedan en [Telefono.CARPETA_CAPTURAS].
 */
@RunWith(AndroidJUnit4::class)
class DietaDiasUiTest : PruebaUi() {
    private val hoy: String get() = FechaLocal.hoy()
    private val ayer: String get() = DiasDieta.sumar(hoy, -1)!!

    private fun irADieta(): ActivityScenario<MainActivity> {
        guardarCuenta()
        val escena = abrir()
        p.tocar(etiqueta("pestana-dieta"))
        p.nodo(etiqueta("dieta-cabecera"))
        return escena
    }

    private fun irA(clave: String) {
        p.esperar("se llega a $clave") {
            val lista = p.nodo(etiqueta("dieta-lista"), ms = 0)
            val i = lista.config[SemanticsProperties.IndexForKey](clave)
            if (i < 0) null else lista.config[SemanticsActions.ScrollToIndex].action?.invoke(i)
        }
        p.quieto(400)
    }

    private fun seleccionado(tag: String): Boolean = p.seleccionado(etiqueta(tag))

    private fun esperarHoyElegido() {
        p.esperar("Hoy elegido", enElPrincipal = false) { if (seleccionado("dia-$hoy")) true else null }
    }

    @Test
    fun elSelectorAbreEnHoy() {
        irADieta()
        esperarHoyElegido()
        assertFalse(seleccionado("dia-$ayer"))
        p.esperarQueNoEste(etiqueta("banner-dia-pasado"))
    }

    @Test
    fun verUnDiaAnteriorConSuAvisoYVolverAHoy() {
        servidor.ponerComidaLibre(ayer, "Pizza de ayer", 800.0, hora = "21:30")
        irADieta()
        p.tocar(etiqueta("dia-$ayer"))
        p.nodo(etiqueta("banner-dia-pasado"))
        p.nodo(texto(DiasDieta.rotuloLargo(ayer)))
        irA("comidas-libres")
        p.nodo(texto("Pizza de ayer"))
        p.tocar(etiqueta("volver-a-hoy"))
        p.esperarQueNoEste(etiqueta("banner-dia-pasado"))
        p.esperarQueNoEste(texto("Pizza de ayer"))
        esperarHoyElegido()
    }

    @Test
    fun marcarEnUnDiaAnteriorVaConSuFechaYNoTocaHoy() {
        irADieta()
        p.tocar(etiqueta("dia-$ayer"))
        p.nodo(etiqueta("banner-dia-pasado"))
        irA("0-c1")
        p.tocar(etiqueta("comi-c1"))
        p.esperar("la marca de ayer llegó") { servidor.marcasGuardadas()["$ayer|c1"]?.takeIf { it.getString("estado") == "comido" } }
        assertNull(servidor.marcasGuardadas()["$hoy|c1"])
        p.tocar(etiqueta("volver-a-hoy"))
        p.esperarQueNoEste(etiqueta("banner-dia-pasado"))
        irA("0-c1")
        assertFalse(seleccionado("comi-c1"))
    }

    @Test
    fun copiarDeAyerSinPisarLoDeHoy() {
        // Ayer comió c1 y c2 y salió a cenar; hoy ya salteó c1: esa queda en conflicto y sin tildar.
        servidor.ponerMarca(ayer, "c1", "A", "comido")
        servidor.ponerMarca(ayer, "c2", "A", "comido")
        servidor.ponerMarca(hoy, "c1", "A", "saltado")
        servidor.ponerComidaLibre(ayer, "Pizza de ayer", 800.0, hora = "21:30")
        irADieta()
        irA("copiar-de-otro-dia")
        p.tocar(etiqueta("copiar-de-otro-dia"))
        p.nodo(etiqueta("hoja-copiar"))
        p.nodo(etiqueta("copiar-item-c1"))
        p.nodo(textoQueContiene("Hoy ya cargaste algo"))
        p.tocar(etiqueta("copiar-confirmar"))
        p.esperarQueNoEste(etiqueta("hoja-copiar"))
        p.esperar("c2 copiada a hoy") { servidor.marcasGuardadas()["$hoy|c2"] }
        // La de hoy sigue siendo «Salté»: no se tildó, no se pisó.
        assertEquals("saltado", servidor.marcasGuardadas()["$hoy|c1"]!!.getString("estado"))
        p.esperar("la comida libre copiada") { servidor.comidasLibresGuardadas().firstOrNull { it.getString("fecha") == hoy && it.getString("descripcion") == "Pizza de ayer" } }
    }

    @Test
    fun tildarLoQueEstaCargadoPreguntaAntesDeReemplazar() {
        servidor.ponerMarca(ayer, "c1", "A", "comido")
        servidor.ponerMarca(hoy, "c1", "A", "saltado")
        irADieta()
        p.tocar(etiqueta("dia-$ayer"))
        p.tocar(etiqueta("copiar-a-hoy"))
        p.tocar(etiqueta("copiar-item-c1"))
        p.tocar(etiqueta("copiar-confirmar"))
        p.nodo(etiqueta("copiar-preguntar"))
        p.tocar(etiqueta("copiar-reemplazar"))
        p.esperar("reemplazada") { servidor.marcasGuardadas()["$hoy|c1"]?.takeIf { it.getString("estado") == "comido" } }
        // Después de copiar, vuelve a hoy.
        p.esperarQueNoEste(etiqueta("banner-dia-pasado"))
    }

    @Test
    fun unaHojaDeUnDiaAnteriorSeCierraSiCambiaElDia() {
        val escena = irADieta()
        p.tocar(etiqueta("dia-$ayer"))
        p.nodo(etiqueta("banner-dia-pasado"))
        irA("0-c1")
        p.tocar(etiqueta("ajustar-c1"))
        p.nodo(etiqueta("hoja-ajuste"))
        var modelo: ModeloApp? = null
        escena.onActivity { modelo = ViewModelProvider(it)[ModeloAppViewModel::class.java].modelo.value }
        runBlocking { modelo!!.irADia(null) }
        p.esperarQueNoEste(etiqueta("hoja-ajuste"))
        p.esperarQueNoEste(etiqueta("banner-dia-pasado"))
    }

    @Test
    fun laComidaLibreDiceElDiaEnElQueSeCarga() {
        irADieta()
        p.tocar(etiqueta("dia-$ayer"))
        p.nodo(etiqueta("banner-dia-pasado"))
        irA("comidas-libres")
        p.tocar(etiqueta("a-mano"))
        p.nodo(texto("Se carga en: ${DiasDieta.rotuloLargo(ayer)}"))
    }

    @Test
    fun fueraDeLaVentanaNoSeAgregaAUnaComidaMarcada() {
        val hace5 = DiasDieta.sumar(hoy, -5)!!
        servidor.ponerMarca(hace5, "c1", "A", "comido")
        irADieta()
        p.esperar("se llega al día") { p.nodo(etiqueta("selector-dias"), ms = 0).config[SemanticsActions.ScrollToIndex].action?.invoke(5) }
        p.quieto(400)
        p.tocar(etiqueta("dia-$hace5"))
        p.nodo(etiqueta("dia-sin-marcas"))
        irA("0-c1")
        p.nodo(etiqueta("ajustar-c1"))
        assertFalse(p.existe(etiqueta("agregar-c1")))
    }

    @Test
    fun capturasClaro() = capturas(oscuro = false)

    @Test
    fun capturasOscuro() = capturas(oscuro = true)

    private fun capturas(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("android-chico-$nombre-$tema")
        Telefono.modoNoche(oscuro)
        servidor.ponerMarca(ayer, "c1", "A", "comido")
        servidor.ponerMarca(ayer, "c2", "A", "comido")
        servidor.ponerMarca(hoy, "c1", "A", "saltado")
        servidor.ponerComidaLibre(ayer, "Milanesa con ensalada", 620.0, prot = 38.0, carb = 30.0, fat = 32.0, hora = "21:30")
        irADieta()
        p.quieto(800)
        foto("selector")
        p.tocar(etiqueta("dia-$ayer"))
        p.nodo(etiqueta("banner-dia-pasado"))
        p.quieto(800)
        foto("dia-anterior")
        p.tocar(etiqueta("copiar-a-hoy"))
        p.nodo(etiqueta("copiar-item-c1"))
        p.nodo(textoQueContiene("Hoy ya cargaste algo"))
        p.quieto(800)
        foto("copiar")
    }
}
