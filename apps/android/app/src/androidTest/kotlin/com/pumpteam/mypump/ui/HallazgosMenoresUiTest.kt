package com.pumpteam.mypump.ui

import android.content.Intent
import android.graphics.RectF
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import androidx.compose.ui.semantics.SemanticsNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.Entorno
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.datos.Pedido
import com.pumpteam.mypump.datos.Respuesta
import com.pumpteam.mypump.datos.Transporte
import com.pumpteam.mypump.entreno.NombreEjercicio
import com.pumpteam.mypump.reglas.CatalogoEjercicios
import com.pumpteam.mypump.reglas.ReferenciaEjercicio
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Lo que los hallazgos menores de la revisión del 15-oct cambiaron en las pantallas, con la app entera: tirar para actualizar
 * en Entreno trae la rutina republicada (6), un link vencido no saca de la cuenta que anda (11) y "Sustituir" aplica el que
 * se eligió aunque con la hoja abierta llegue el catálogo del servidor (13). Lo de adentro lo prueban los tests de :core.
 */
@RunWith(AndroidJUnit4::class)
class HallazgosMenoresUiTest : PruebaUi() {
    // ── 11: un link vencido con la cuenta andando ──

    @Test
    fun unLinkVencidoConLaCuentaAndandoAvisaYSigueEnLaCuenta() {
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        // El link viejo de WhatsApp, tocado con la app abierta (`singleTask`: llega a la misma Activity).
        val vencido = "linkVencidoDePrueba_00000000"
        app.startActivity(intentDeLink("https://app.mypumpteam.com/?t=$vencido").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        p.nodo(texto("Este link ya no sirve"))
        p.nodo(texto("Seguís con tu cuenta."))
        p.tocar(etiqueta("aviso-link-entendido"))
        p.esperarQueNoEste(etiqueta("aviso-link"))
        // Sigue en la cuenta: las pestañas, el token guardado y el link anotado como vencido.
        p.nodo(etiqueta("pestana-entreno"))
        assertFalse("quedó en \"pegá tu link\"", p.existe(etiqueta("campo-link")))
        assertEquals(ServidorDePrueba.TOKEN, tokenGuardado())
        assertEquals(vencido, preferencia(ModeloApp.CLAVE_TOKEN_INVALIDO))
    }

    @Test
    fun sinRedParaRevisarElLinkSeQuedaEnLaCuentaYLoDice() {
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("pestana-entreno"))
        servidor.sinRed = true
        app.startActivity(intentDeLink("https://app.mypumpteam.com/?t=otroLinkDePrueba_000000000").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        p.nodo(texto("No pudimos abrir ese link. Probá de nuevo cuando tengas señal."))
        p.tocar(etiqueta("aviso-link-entendido"))
        p.esperarQueNoEste(etiqueta("aviso-link"))
        p.nodo(etiqueta("pestana-entreno"))
        assertEquals(ServidorDePrueba.TOKEN, tokenGuardado())
    }

    // ── 6: tirar para actualizar en Entreno ──

    @Test
    fun tirarParaActualizarEnEntrenoTraeLaRutinaRepublicada() {
        servidor.respuestas["mypump_get_rutina_activa"] = rutina(version = 1, ejercicio = "Press banca plano con barra (pectoral)")
        servidor.respuestas["mypump_get_historico_por_clave"] = "[]"
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        guardarCuenta()
        abrir()
        p.nodo(etiqueta("entreno-cabecera"))
        p.nodo(textoQueContiene("Press banca plano con barra"))
        val antes = servidor.a("mypump_get_rutina_activa").size

        // Mati cambia el ejercicio y republica; el cliente tira para actualizar.
        servidor.respuestas["mypump_get_rutina_activa"] = rutina(version = 2, ejercicio = "Press inclinado con mancuernas (pectoral)")
        tirarParaActualizar(etiqueta("entreno-lista"))
        p.nodo(textoQueContiene("Press inclinado con mancuernas"))
        assertFalse(p.existe(textoQueContiene("Press banca plano con barra")))
        assertTrue("no se pidió la rutina", servidor.a("mypump_get_rutina_activa").size > antes)
    }

    // ── 13: sustituir con el catálogo llegando ──

    @Test
    fun sustituirAplicaElElegidoAunqueLlegueElCatalogoConLaHojaAbierta() {
        // El catálogo del servidor es el empaquetado con dos sustitutos más del jalón, que van primeros en la lista.
        val empaquetado = app.assets.open("bases/catalogo-ejercicios.json").use { it.readBytes().toString(Charsets.UTF_8) }
        val original = CatalogoEjercicios.desde(empaquetado).resolver(ReferenciaEjercicio(nombre = "Jalón al pecho"))!!
        val otroEquipo = if (original.equipment == "machine") "cable" else "machine"
        fun extra(n: String) =
            """{"slug_en":"Prueba_$n","name_en":"Aaaa prueba $n","primary_muscle":"${original.primaryMuscle}",""" +
                """"equipment":"$otroEquipo","patron_movimiento":"${original.patronMovimiento}"}"""
        val delServidor = empaquetado.trimEnd().removeSuffix("]") + "," + extra("uno") + "," + extra("dos") + "]"
        val catalogo = CatalogoTarde(servidor, delServidor)
        Entorno.transporte = catalogo
        servidor.respuestas["mypump_get_rutina_activa"] = rutina(version = 1, ejercicio = "Jalón al pecho", id = "jal-d1-0")
        servidor.respuestas["mypump_get_historico_por_clave"] = "[]"
        servidor.respuestas["mypump_get_sesion_dia"] = "[]"
        guardarCuenta()
        abrir()
        abrirPaginaDelEjercicio("jal-d1-0")
        p.tocar(etiqueta("sustituir"))
        p.nodo(etiqueta("hoja-sustituir"))
        // Se elige el primero de la lista (con el catálogo empaquetado)…
        val elegida = NombreEjercicio(p.textosBajo(etiqueta("variante")).first()).principal
        p.tocar(etiqueta("variante"))
        p.esperar("la elegida") { p.seleccionado(etiqueta("variante")) }
        // …y con la hoja abierta llega el del servidor: el primero de la lista ya es otro.
        catalogo.llega.complete(Unit)
        p.esperar("el catálogo nuevo en la hoja") { NombreEjercicio(p.textosBajo(etiqueta("variante")).first()).principal != elegida }
        p.tocar(etiqueta("confirmar-sustitucion"))
        p.esperarQueNoEste(etiqueta("hoja-sustituir"))
        p.esperar("el elegido, no el que quedó en su lugar") { p.textosBajo(etiqueta("ejercicio-nombre")) == listOf(elegida) }
    }

    // ── Lo de las pruebas ──

    /** Un día con un ejercicio de una serie, en 4 semanas. */
    private fun rutina(version: Int, ejercicio: String, id: String = "press-d1-0"): String {
        val progresion = (1..4).joinToString(",") { """{"semana":$it,"series":1,"reps":"8","rir":"1"}""" }
        return """[{"id":"r-hallazgos","version":$version,"semana_actual":1,"tiene_siguiente":false,"estructura":{"semanas_total":4,"dias":[
            {"id":"d1","n":1,"nombre":"EMPUJE","bloques":[{"titulo":"BLOQUE 1","ejercicios":[
              {"id":"$id","nombre":"$ejercicio","tipo":"compuesto","descanso_segundos":120,"progresion":[$progresion]}]}]}
        ]}}]"""
    }

    /** El servidor de prueba, con el catálogo de ejercicios que contesta recién cuando la prueba lo suelta ([llega]). */
    private class CatalogoTarde(private val servidor: ServidorDePrueba, private val catalogo: String) : Transporte {
        val llega = CompletableDeferred<Unit>()

        override suspend fun enviar(pedido: Pedido): Respuesta {
            if (!pedido.ruta.endsWith("/mypump_ejercicios_catalogo")) return servidor.enviar(pedido)
            llega.await()
            return Respuesta(200, catalogo.toByteArray())
        }
    }

    /**
     * Tira para actualizar: un dedo que baja desde arriba de [s], el gesto de verdad (pasa por el desplazamiento anidado de
     * `PullToRefreshBox`, que la acción de semántica de desplazar no toca).
     */
    private fun tirarParaActualizar(s: Selector) {
        val r = p.esperar("está $s") { rectEnPantalla(s) }
        val x = r.centerX()
        val desde = r.top + 40f
        val hasta = minOf(r.bottom - 40f, desde + 1_000f)
        val inicio = SystemClock.uptimeMillis()
        fun evento(accion: Int, y: Float, t: Long) =
            MotionEvent.obtain(inicio, t, accion, x, y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
        val eventos = buildList {
            add(evento(MotionEvent.ACTION_DOWN, desde, inicio))
            for (i in 1..25) add(evento(MotionEvent.ACTION_MOVE, desde + (hasta - desde) * i / 25, inicio + i * 20L))
            add(evento(MotionEvent.ACTION_UP, hasta, inicio + 26 * 20L))
        }
        for (e in eventos) {
            instr.sendPointerSync(e)
            e.recycle()
        }
    }

    /** Dónde está en la pantalla el primer nodo que coincide con [s] (null si no está). */
    private fun rectEnPantalla(s: Selector): RectF? = p.enPrincipal {
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
            val donde = IntArray(2)
            r.view.getLocationOnScreen(donde)
            val b = n.boundsInRoot
            if (b.width < 1f || b.height < 1f) continue
            return@enPrincipal RectF(donde[0] + b.left, donde[1] + b.top, donde[0] + b.right, donde[1] + b.bottom)
        }
        null
    }
}
