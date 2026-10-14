package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.concurrent.CopyOnWriteArrayList
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de evidencia, en claro y en oscuro: recorre la bienvenida, el link vencido, la demo, las fuentes, una
 * cuenta (con badges y el banner de Revisión), Mis datos, sin red y el permiso de la IA. Quedan en
 * [Telefono.CARPETA_CAPTURAS] y las baja `scripts/nativa/emu-ui.sh` a `~/Developer/nativa-evidencia/android-ui/<fecha>/`.
 */
@RunWith(AndroidJUnit4::class)
class CapturasUiTest : PruebaUi() {
    @Test
    fun enClaro() = recorrer(oscuro = false)

    @Test
    fun enOscuro() = recorrer(oscuro = true)

    private fun recorrer(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        servidor.respuestas["mypump_get_chat"] =
            """[{"id":"m1","autor":"coach","contenido":"¿Cómo venís con el plan?","leido_por_cliente":false,"created_at":"2026-10-14T12:00:00Z"}]"""

        abrir().also {
            p.nodo(etiqueta("ver-demo"))
            foto("01-bienvenida")
            p.escribir(etiqueta("campo-link"), "https://app.mypumpteam.com/?t=linkVencidoDePrueba_00000000")
            p.tocar(etiqueta("entrar"))
            p.nodo(etiqueta("link-vencido"))
            foto("02-link-vencido")
            p.tocar(etiqueta("ver-demo"))
            p.nodo(texto("Estás viendo la demo"))
            foto("03-demo-entreno")
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.454"))
            foto("04-demo-dieta")
            p.tocar(etiqueta("ver-fuentes"))
            p.nodo(texto("Cómo se calcula tu objetivo de calorías"))
            foto("05-fuentes")
            p.tocar(etiqueta("fuentes-listo"))
            p.esperarQueNoEste(etiqueta("hoja-fuentes"))
            p.tocar(etiqueta("salir-demo"))
            p.nodo(etiqueta("ver-demo"))
            entrarConLaCuenta()
            p.esperar("los badges") { "1" in p.textosBajo(etiqueta("pestana-chat")) && "2" in p.textosBajo(etiqueta("pestana-revision")) }
            foto("06-cuenta-entreno")
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.373"))
            p.nodo(etiqueta("banner-revision"))
            foto("07-cuenta-dieta")
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(textoQueContiene("Semana del"))
            foto("08-cuenta-revision")
            p.tocar(etiqueta("mis-datos"))
            p.nodo(etiqueta("asistente-ia"))
            foto("09-cuenta-mis-datos")
        }.close()

        // Sin red con la copia guardada: el plan de la última vez, con el aviso arriba (OFF-06).
        servidor.sinRed = true
        abrir().also {
            p.nodo(etiqueta("banner-sin-conexion"))
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.373"))
            foto("10-sin-red-con-copia")
        }.close()

        // Sin red y sin copia: "Sin conexión" con Reintentar (ACC-05).
        reiniciarEstado()
        guardarCuenta()
        abrir().also {
            p.nodo(etiqueta("sin-conexion"))
            foto("11-sin-conexion")
        }.close()

        // El permiso de la IA antes del primer mensaje (D7).
        servidor.sinRed = false
        val (m, alcance) = modeloConCuenta()
        armarPermisoIA(m, alcance, CopyOnWriteArrayList())
        p.tocar(etiqueta("mandar"))
        p.nodo(etiqueta("ia-acepto"))
        foto("12-permiso-ia")
    }
}
