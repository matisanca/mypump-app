package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
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
}
