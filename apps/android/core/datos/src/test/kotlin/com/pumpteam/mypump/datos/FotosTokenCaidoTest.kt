package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Gemelo de FotosTokenCaidoTests.swift (lo encontró el agente de los hallazgos menores de iOS, 15-oct): con el link vencido o
 * regenerado, `progreso/upload` contesta 403 «token inválido» y la foto se borraba como un rechazo definitivo (la web también
 * la perdía). Ahora queda guardada y la adopta la cuenta del link nuevo de la misma persona.
 */
class FotosTokenCaidoTest {
    private val raiz = carpetaTemporal("fotos-token")
    private val jpeg = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 0x00, 0x10)

    /** Los tokens con que se subió cada foto (la regla corre fuera del hilo del test). */
    private val subidas = mutableListOf<String>()

    private fun transporte() = TransporteProgramado { fn, cuerpo ->
        when (fn) {
            "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
            "upload" -> {
                synchronized(subidas) { subidas += cuerpo["token"]?.comoTexto ?: "?" }
                200 to """{"ok":true}"""
            }
            else -> 200 to "[]"
        }
    }

    /** Una foto que no llegó a subirse, en la carpeta de otro link, anotada como de [clienteId]. */
    private fun carpetaConFoto(token: String, clienteId: String): Disco {
        val d = Disco(raiz, token)
        CuentasDelTelefono.anotar(clienteId, d)
        val hoy = FechaLocal.hoy()
        d.guardar(
            FotoPendiente.ARCHIVO,
            ValorJson.objeto("${FotosProgreso.lunes(hoy)}|perfil" to FotoPendiente("perfil", hoy, "data:image/jpeg;base64,AAAA").aValor()),
        )
        return d
    }

    @Test
    fun unTokenCaidoNoBorraLaFotoNiGastaIntentos() = enUnHilo {
        val g = Guion(403 to """{"ok":false,"error":"token inválido"}""", 403 to """{"ok":false,"error":"token inválido"}""")
        val f = ModeloFotos(ClienteRpc(transporte = g), TOKEN, Disco(raiz, TOKEN))
        assertEquals(ModeloFotos.Resultado.TokenCaido, f.subir("frente", jpeg))
        assertEquals(1, f.pendientes.value.size, "se borraba como un rechazo")
        f.drenar()
        assertTrue(f.pendientes.value.size == 1 && f.pendientes.value.values.first().intentos == 0)
    }

    @Test
    fun unRechazoQueNoEsDelTokenSiLaDescarta() = enUnHilo {
        val g = Guion(400 to """{"ok":false,"error":"fecha fuera de la ventana"}""")
        val f = ModeloFotos(ClienteRpc(transporte = g), TOKEN, Disco(raiz, TOKEN))
        assertEquals(ModeloFotos.Resultado.Rechazada("fecha fuera de la ventana"), f.subir("frente", jpeg))
        assertTrue(f.pendientes.value.isEmpty())
    }

    @Test
    fun elLinkNuevoDeLaMismaPersonaSeLlevaLasFotos() = enUnHilo { alcance ->
        // La carpeta del link viejo: de c1, con una foto que no llegó a subirse.
        val carpetaVieja = carpetaConFoto("VIEJOVIEJOVIEJOVIEJO", "c1")
        val nuevo = "NUEVONUEVONUEVONUEVO"
        val m = ModeloApp(ClienteRpc(transporte = transporte()), TokenEnMemoria(nuevo), raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        m.fotos.value!!.drenar()
        assertEquals(listOf(nuevo), synchronized(subidas) { subidas.toList() }, "la foto del link viejo no salió con el nuevo")
        assertNull(carpetaVieja.leer(FotoPendiente.ARCHIVO))
    }

    @Test
    fun deOtraPersonaNoSeAdopta() = enUnHilo { alcance ->
        val carpetaAjena = carpetaConFoto("AJENOAJENOAJENOAJENO", "otra")
        val m = ModeloApp(ClienteRpc(transporte = transporte()), TokenEnMemoria("NUEVONUEVONUEVONUEVO"), raiz, PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertTrue(synchronized(subidas) { subidas.isEmpty() })
        assertEquals(1, (carpetaAjena.leer(FotoPendiente.ARCHIVO) as? JsonObject)?.size)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
    }
}
