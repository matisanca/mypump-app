package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.datos.ClaveSalud
import com.pumpteam.mypump.datos.ModeloSalud
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.salud.EstadoHealthConnect
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith

/**
 * La recuperación con `confianza` y `motivo_falta` (nativa_007, R1 de la 2.0.3), con una serie inventada: la pastilla
 * «Confianza baja» con el número apagado, que al tocarla dice cómo mejorarla; el detalle con la explicación a la vista; y
 * calibrando con el texto del servidor. Captura en claro y en oscuro. Gemelo de `RecuperacionConfianzaUITests.swift`.
 */
@RunWith(AndroidJUnit4::class)
class RecuperacionConfianzaUiTest : PruebaUi() {
    @After
    fun sacarSalud() {
        ModeloSalud.fuenteDelSistema = null
        EstadoHealthConnect.forzado = null
    }

    /** 14 días hasta hoy; los últimos [conScore] con score, el de hoy con [hoy] (las columnas nuevas). */
    private fun serie(hoy: String, conScore: Int = 6): String {
        val n = DiaCalendario.numero(FechaLocal.hoy())!!
        return (13 downTo 0).joinToString(",", "[", "]") { i ->
            val fecha = DiaCalendario.texto(n - i)
            when {
                i == 0 -> """{"fecha":"$fecha",$hoy}"""
                i < conScore -> """{"fecha":"$fecha","score":${50 + i * 3},"estado":"ok","banda":"media","dias_datos":40,"confianza":"media"}"""
                else -> """{"fecha":"$fecha","score":null,"estado":"insuficiente"}"""
            }
        }
    }

    private fun sembrar(recuperacion: String) {
        ModeloSalud.fuenteDelSistema = FuenteDeMentira()
        EstadoHealthConnect.forzado = EstadoHealthConnect.DISPONIBLE
        servidor.respuestas["mypump_get_salud"] = instr.context.assets.open("test-nativa-ios/get_salud.json").use { it.readBytes().toString(Charsets.UTF_8) }
        servidor.respuestas["mypump_get_recuperacion"] = recuperacion
        servidor.respuestas["mypump_get_mostrar_recuperacion"] = "true"
        guardarPreferencia(ClaveSalud.CONECTADO, "1")
        guardarPreferencia(ClaveSalud.HISTORIAL_HECHO, "1")
        guardarCuenta()
    }

    /** Salud → Recuperación (donde arranca Salud desde la 2.1): la card de recuperación va arriba de todo. */
    private fun hastaLaCard() {
        p.tocar(etiqueta("pestana-salud"))
        p.esperar("Recuperación elegida") { p.seleccionado(etiqueta("segmento-recuperacion")) }
        p.nodo(etiqueta("card-recuperacion"))
        p.quieto(400)
    }

    @Test
    fun confianzaBajaEnClaro() = confianzaBaja(oscuro = false)

    @Test
    fun confianzaBajaEnOscuro() = confianzaBaja(oscuro = true)

    private fun confianzaBaja(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        Telefono.modoNoche(oscuro)
        sembrar(
            serie(
                """"score":41,"estado":"ok","banda":"media","dias_datos":40,"banda_provisoria":false,"discordancia":false,""" +
                    """"motivos":[],"motivo_falta":"Confianza baja. Para mejorarla, usá el reloj para dormir.","confianza":"baja"""",
            ),
        )
        abrir().also {
            hastaLaCard()
            p.nodo(texto("41"))
            p.nodo(texto("Confianza baja"))
            p.esperarQueNoEste(etiqueta("explicacion-confianza"))
            Telefono.captura("r203-recuperacion-confianza-baja-$tema")
            p.tocar(etiqueta("confianza-recuperacion"))
            p.nodo(texto("Para mejorarla, usá el reloj para dormir."))
            Telefono.captura("r203-recuperacion-confianza-abierta-$tema")
            // Se vuelve a cerrar.
            p.tocar(etiqueta("confianza-recuperacion"))
            p.esperarQueNoEste(etiqueta("explicacion-confianza"))
            // En el detalle va a la vista.
            p.tocar(etiqueta("ver-todos-mis-datos"))
            p.nodo(etiqueta("detalle-confianza"))
            p.nodo(texto("Para mejorarla, usá el reloj para dormir."))
            Telefono.captura("r203-recuperacion-detalle-$tema")
        }.close()
    }

    @Test
    fun calibrandoMuestraElMotivo() {
        val falta = "Calibrando, hay 5 de 14 días con datos del reloj. Faltan 9 días."
        sembrar(serie(""""score":null,"estado":"calibrando","dias_datos":5,"motivo_falta":"$falta","confianza":null""", conScore = 0))
        abrir().also {
            hastaLaCard()
            p.nodo(texto(falta))
            Telefono.captura("r203-recuperacion-calibrando-claro")
        }.close()
    }

    @Test
    fun confianzaAltaQuedaComoSiempre() {
        sembrar(serie(""""score":74,"estado":"ok","banda":"alta","dias_datos":40,"motivos":[],"motivo_falta":null,"confianza":"alta""""))
        abrir().also {
            hastaLaCard()
            p.nodo(texto("74"))
            p.esperarQueNoEste(etiqueta("confianza-recuperacion"))
        }.close()
    }
}
