package com.pumpteam.mypump.ui

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.reglas.FechaLocal
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de evidencia de Dieta con escritura, en claro y en oscuro (como `CapturasUiTest`): la mano y un reemplazo
 * en la lista, la hoja "Reemplazar", el alimento propio con la etiqueta leída, las comidas libres, la IA mirando el plato,
 * la estimación para corregir, la foto que no se pudo leer, volver al del plan y la carga a mano con la hora. Con la
 * cuenta del [ServidorDePrueba]: la visión la contesta la prueba. Quedan en [Telefono.CARPETA_CAPTURAS] y las baja
 * `scripts/nativa/emu-ui.sh`.
 */
@RunWith(AndroidJUnit4::class)
class DietaCapturasTest : PruebaUi() {
    private var camara: CamaraDePrueba? = null

    @After
    fun soltarCamara() {
        camara?.soltar()
        camara = null
    }

    @Test
    fun enClaro() = recorrer(oscuro = false)

    @Test
    fun enOscuro() = recorrer(oscuro = true)

    /**
     * Lleva un elemento de la lista de Dieta (por su clave: "0-c1", "comidas-libres"…) arriba de todo, con la acción de
     * la semántica que usa un lector de pantalla. Desplazar de a pedazos y medir no sirve: la lista precompone lo que sigue
     * sin ubicarlo, y su posición queda vieja.
     */
    private fun llevarArriba(clave: String) {
        p.esperar("se lleva arriba $clave") {
            val lista = p.nodo(etiqueta("dieta-lista"), ms = 0)
            val i = lista.config[SemanticsProperties.IndexForKey](clave)
            if (i < 0) null else lista.config[SemanticsActions.ScrollToIndex].action?.invoke(i)
        }
        p.quieto(500)
    }

    private fun recorrer(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        camara = CamaraDePrueba(instr, app)
        // Dos comidas libres de hoy: una cargada a mano y una de foto.
        servidor.ponerComidaLibre(FechaLocal.hoy(), "Medialunas con café con leche", 410.0, prot = 9.0, carb = 52.0, fat = 18.0, hora = "09:30")
        servidor.ponerComidaLibre(FechaLocal.hoy(), "Porción de pizza muzzarella", 285.0, prot = 12.0, carb = 33.0, fat = 11.0, hora = "21:15")
        servidor.vision = { tipo ->
            Thread.sleep(2_500)
            if (tipo == "plato") 200 to DietaEscrituraUiTest.PLATO else 200 to ETIQUETA
        }
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(etiqueta("dieta-cabecera"))

            // La clara de huevo, reemplazada; la mano del huevo y la del pan, abiertas.
            p.tocar(etiqueta("reemplazar-c1-1"))
            p.tocar(etiqueta("sustituto"))
            p.tocar(etiqueta("confirmar-reemplazo"))
            p.esperarQueNoEste(etiqueta("hoja-reemplazar"))
            p.tocar(etiqueta("mano-c1-0"))
            p.tocar(etiqueta("mano-c1-2"))
            p.nodo(texto("Porción casera: 4 rebanadas"))
            llevarArriba("0-c1")
            foto("dieta-01-mano-y-reemplazo")

            // "Reemplazar" para el almuerzo, con una opción elegida.
            llevarArriba("1-c2")
            p.tocar(etiqueta("reemplazar-c2-0"))
            p.nodo(texto("55 de 55 · proteínas"))
            p.tocar(etiqueta("sustituto"))
            p.quieto(600)
            foto("dieta-02-reemplazar")

            // El alimento propio con la etiqueta leída.
            repeat(40) {
                if (!p.existe(etiqueta("crear-alimento"))) p.desplazar(etiqueta("lista-sustitutos"), 1_500f)
            }
            p.tocar(etiqueta("crear-alimento"))
            p.nodo(etiqueta("crear-alimento-formulario"))
            p.tocar(etiqueta("escanear-etiqueta"))
            p.tocar(etiqueta("elegir-de-la-galeria"))
            p.nodo(texto("Leyendo la etiqueta…"))
            foto("dieta-03-leyendo-etiqueta")
            p.nodo(texto("✓ Etiqueta leída. Revisá los valores y tocá \"Crear y usar\"."), ms = 30_000)
            p.quieto(400)
            foto("dieta-04-alimento-propio")
            p.tocar(etiqueta("volver-a-reemplazos"))
            p.nodo(etiqueta("lista-sustitutos"))
            p.tocar(etiqueta("cancelar-reemplazo"))
            p.esperarQueNoEste(etiqueta("hoja-reemplazar"))

            // Las comidas libres al pie, y la IA mirando el plato.
            llevarArriba("comidas-libres")
            foto("dieta-05-comidas-libres")
            p.tocar(etiqueta("con-foto"))
            p.tocar(etiqueta("elegir-de-la-galeria"))
            p.nodo(texto("Analizando el plato…"))
            foto("dieta-06-analizando-plato")
            p.nodo(etiqueta("hoja-comida-libre"), ms = 30_000)
            p.quieto(600)
            foto("dieta-07-estimacion")
            p.tocar(etiqueta("cancelar-comida-libre"))
            p.esperarQueNoEste(etiqueta("hoja-comida-libre"))

            // La foto que no se pudo leer.
            servidor.vision = { 502 to """{"ok":false,"error":"no se pudo interpretar la foto, probá con más luz"}""" }
            p.tocar(etiqueta("con-foto"))
            p.tocar(etiqueta("elegir-de-la-galeria"))
            p.nodo(texto("No pudimos leer la foto"), ms = 30_000)
            foto("dieta-08-foto-no-leida")
            p.tocar(etiqueta("cargar-a-mano"))
            p.nodo(etiqueta("hoja-comida-libre"))
            p.escribir(etiqueta("descripcion-comida-libre"), "Alfajor de maicena")
            p.escribir(etiqueta("kcal-comida-libre"), "180")
            p.tocar(etiqueta("hora-comida-libre"))
            p.nodo(etiqueta("hora-listo"))
            foto("dieta-09-comida-libre-hora")
            p.tocar(etiqueta("hora-listo"))
            p.quieto(400)
            foto("dieta-10-comida-libre-a-mano")
            p.tocar(etiqueta("cancelar-comida-libre"))
            p.esperarQueNoEste(etiqueta("hoja-comida-libre"))

            // Volver al alimento del plan.
            llevarArriba("0-c1")
            p.tocar(texto("Reemplazado. Tocá para volver a Clara de huevo"))
            p.nodo(texto("¿Volver al alimento del plan?"))
            foto("dieta-11-volver-al-plan")
            p.tocar(etiqueta("cancelar-volver"))
        }.close()
    }

    companion object {
        const val ETIQUETA = """{"ok":true,"data":{"nombre":"Pan lactal integral","porcion_g":50,"kcal":125,"prot":5.5,"carb":21,"fat":1.8,"confianza":"alta"}}"""
    }
}
