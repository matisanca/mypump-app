package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FechaLocal
import kotlinx.coroutines.delay
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** La demo ("Ver demo", la que mira la revisión de la tienda): sin red, sin token y sin escribir nada (DemoTests.swift). */
class DemoTest {
    @Test
    fun demoSinRedNiToken() = enUnHilo { alcance ->
        val raiz = carpetaTemporal("mypump-demo")
        val m = ModeloApp(ClienteRpc(transporte = SinRed), TokenEnMemoria(null), raiz, PreferenciasEnMemoria(), alcance)
        assertEquals(ModeloApp.Fase.SIN_TOKEN, m.fase.value)
        m.entrarEnDemo(Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"))
        assertTrue(m.fase.value == ModeloApp.Fase.LISTO && m.esDemo.value)
        assertFalse(m.rutina.value?.estructura?.dias.isNullOrEmpty())
        assertTrue(m.comidasDelDia.isNotEmpty())
        // El objetivo de la demo es la suma de las opciones A (no trae `macros_target`, f7aa713): la tarjeta de macros no
        // marca "−23 %" en lo que ve la revisión de la tienda, y la demo no avisa "a tu plan le falta información".
        val opcionesA = ModeloApp.sumar(m.comidasDelDia.flatMap { it.opciones.first().alimentos })
        assertEquals(opcionesA.kcal!!, m.objetivo.kcal!!, 1.0)
        assertNull(m.avisoPlanIncompleto)
        m.cargar()   // "tirar para actualizar" en la demo: no la cierra
        assertTrue(m.fase.value == ModeloApp.Fase.LISTO && m.esDemo.value)
        // Un reemplazo en la demo queda en memoria y no sale a ningún lado.
        val c = m.comidasDelDia.first()
        val a = c.opciones.first().alimentos.first()
        m.sustituir(
            a,
            ValorJson.objeto(
                "name" to texto("Ricota"), "qty" to numero(100), "unit" to texto("g"), "kcal" to numero(138),
                "prot" to numero(11), "carb" to numero(4), "fat" to numero(9),
            ),
            c.id, 0, 0,
        )
        assertTrue(m.efectivo(a, c.id, 0, 0).sustituido)
        m.salirDeDemo()
        assertTrue(m.fase.value == ModeloApp.Fase.SIN_TOKEN && !m.esDemo.value)
        assertNull(m.dieta.value)
        // Nada quedó en el disco.
        assertFalse(raiz.resolve("MyPump").exists())
    }

    @Test
    fun salirDeLaDemoVuelveALaCuentaGuardada() = enUnHilo { alcance ->
        val t = TransporteProgramado { fn, _ ->
            if (fn == "mypump_get_cliente_info") 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]""" else 200 to "[]"
        }
        val almacen = TokenEnMemoria("tokenDePrueba_0000000000")
        val m = ModeloApp(ClienteRpc(transporte = t), almacen, carpetaTemporal("mypump-demo"), PreferenciasEnMemoria(), alcance)
        m.entrarEnDemo(Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"))
        assertNull(m.token)
        assertNull(m.outbox)
        assertEquals("tokenDePrueba_0000000000", almacen.leer())   // el almacén no se toca
        m.salirDeDemo()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertEquals("c1", m.info.value?.clienteId)
    }

    /**
     * ACC-07: en la demo, Revisión existe sin cuenta y el chat tiene el hilo vacío. Se toca igual, pero nada sale: ni red,
     * ni cola, ni disco. Mi Día ya no existe (2.1).
     */
    @Test
    fun revisionYElChatVacioSinRed() = enUnHilo { alcance ->
        val t = TransporteProgramado { _, _ -> 200 to "[]" }
        val raiz = carpetaTemporal("mypump-demo")
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria(null), raiz, PreferenciasEnMemoria(), alcance)
        m.entrarEnDemo(Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"))
        val r = m.revision.value!!
        assertEquals(FechaLocal.hoy(), r.fecha.value)
        val chat = m.chat.value!!
        assertTrue(chat.demo)
        assertTrue(chat.hilo.value.mensajes.isEmpty() && !chat.hilo.value.hayMas)

        // Se toca igual y nada sale.
        assertTrue(r.guardarPeso("80"))
        r.cargarRevision()
        assertEquals(80.0, r.serieDePeso.lastOrNull()?.kg)
        chat.enviar("Hola Mati")
        chat.cargar()
        chat.sondear()
        chat.marcarLeido(forzar = true)
        m.enPrimerPlano = true
        chat.empezarSondeo()
        assertTrue(chat.hilo.value.mensajes.isEmpty())
        assertNull(chat.sondeoEnCurso)
        delay(100)   // lo que la demo lanzó (la carga del Entreno de ejemplo) tampoco sale
        assertEquals(emptyList<String>(), t.llamadas)
        assertFalse(raiz.resolve("MyPump").exists())

        // Salir de la demo no deja su Mi Día ni su chat.
        m.salirDeDemo()
        assertNull(m.revision.value)
        assertNull(m.chat.value)
    }
}
