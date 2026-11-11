package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.IOException

/**
 * El servidor de mentira de la cola A (2.3.0): contesta las palancas, «Récords y logros» (`mypump_wins_*`) y la lista previa
 * (`mypump_lista_previa`) como la propuesta `nativa_wins_lista_previa.sql`. Lo usan las pruebas JVM y las de interfaz (este
 * directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red. Gemelo de DobleColaA.swift.
 */
class DobleColaA : Transporte {
    data class Registro(val id: String, val tipo: String, val clave: String, val dia: String, val datos: ValorJson?)

    @Volatile var palancaWins = true
    @Volatile var palancaLista = true

    /** El permiso vigente del alumno en el servidor. */
    @Volatile var permiso = false

    /** Las funciones no existen (PGRST202). */
    @Volatile var sinFuncion = false
    @Volatile var sinRed = false

    /** Solo dar o sacar el permiso falla por la red (lo demás contesta). */
    @Volatile var sinRedPermiso = false

    /** `mypump_wins_registrar` contesta 503. */
    @Volatile var registrarCaido = false

    /** `mypump_wins_registrar` contesta `{ok: false, motivo: 'datos'}`. */
    @Volatile var registrarRechaza = false
    @Volatile var tokenCaido = false

    /** Lo que contesta `mypump_lista_previa` (por defecto, la lista de la demo). */
    @Volatile var lista: String = LISTA_DEMO
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()
    val registrados = java.util.concurrent.CopyOnWriteArrayList<Registro>()

    /** Los `p_otorga` que llegaron a `mypump_wins_permiso`. */
    val permisosPedidos = java.util.concurrent.CopyOnWriteArrayList<Boolean>()

    /** Los cuerpos de `mypump_wins_permiso`, tal cual llegaron. */
    val cuerposPermiso = java.util.concurrent.CopyOnWriteArrayList<ValorJson>()

    val llamadasWins: List<String> get() = llamadas.filter { it.startsWith("mypump_wins") }
    val llamadasLista: List<String> get() = llamadas.filter { it == "mypump_lista_previa" }

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val f = pedido.ruta.substringAfterLast('/')
        llamadas += f
        if (sinRed) throw IOException("sin red (doble)")
        val cuerpo = pedido.cuerpo?.let { runCatching { ValorJson.parsear(String(it)) }.getOrNull() }
        val noExiste = 404 to """{"code":"PGRST202","message":"Could not find the function"}"""
        val (status, texto) = when (f) {
            "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c-prueba","nombre":"Cliente","perfil":"natural"}]"""
            "mypump_get_app_config" -> 200 to """{"wins_app":$palancaWins,"lista_previa":$palancaLista}"""
            "mypump_wins_estado" -> when {
                sinFuncion -> noExiste
                tokenCaido -> 200 to """{"ok":false,"motivo":"token"}"""
                else -> 200 to """{"ok":true,"activa":$palancaWins,"permiso":$permiso}"""
            }
            "mypump_wins_permiso" -> {
                if (sinRedPermiso) throw IOException("sin red (doble)")
                val otorga = (cuerpo?.get("p_otorga") as? ValorJson.Booleano)?.valor
                when {
                    sinFuncion -> noExiste
                    otorga == null -> 200 to """{"ok":false,"motivo":"datos"}"""
                    else -> {
                        permisosPedidos += otorga
                        cuerpo?.let { cuerposPermiso += it }
                        if (otorga && !palancaWins) {
                            200 to """{"ok":false,"motivo":"apagada"}"""
                        } else {
                            permiso = otorga
                            200 to if (otorga) """{"ok":true,"permiso":true}""" else """{"ok":true,"permiso":false,"retirados":0}"""
                        }
                    }
                }
            }
            "mypump_wins_registrar" -> when {
                sinFuncion -> noExiste
                registrarCaido -> 503 to """{"message":"caído"}"""
                tokenCaido -> 200 to """{"ok":false,"motivo":"token"}"""
                !palancaWins -> 200 to """{"ok":true,"guardado":false,"motivo":"apagada"}"""
                !permiso -> 200 to """{"ok":true,"guardado":false,"motivo":"sin_permiso"}"""
                registrarRechaza -> 200 to """{"ok":false,"motivo":"datos"}"""
                else -> {
                    val id = cuerpo?.get("p_id")?.comoTexto ?: ""
                    if (registrados.any { it.id == id }) {
                        200 to """{"ok":true,"guardado":true,"ya":true}"""
                    } else {
                        registrados += Registro(
                            id, cuerpo?.get("p_tipo")?.comoTexto ?: "", cuerpo?.get("p_clave")?.comoTexto ?: "",
                            cuerpo?.get("p_dia")?.comoTexto ?: "", cuerpo?.get("p_datos"),
                        )
                        200 to """{"ok":true,"guardado":true,"ya":false}"""
                    }
                }
            }
            "mypump_lista_previa" -> when {
                sinFuncion -> noExiste
                tokenCaido -> 200 to """{"ok":false,"motivo":"token"}"""
                !palancaLista -> 200 to """{"ok":true,"activa":false,"items":[]}"""
                else -> 200 to lista
            }
            else -> 200 to "[]"
        }
        return Respuesta(status, texto.toByteArray())
    }

    companion object {
        const val LISTA_DEMO = """{"ok":true,"activa":true,"items":[{"clave":"guia","estado":"falta","faltan":2},""" +
            """{"clave":"dudas","estado":"falta","opcional":true},{"clave":"formulario","estado":"hecho"},{"clave":"fotos","estado":"falta"}]}"""
        const val LISTA_LISTA = """{"ok":true,"activa":true,"items":[{"clave":"guia","estado":"hecho","faltan":0},""" +
            """{"clave":"dudas","estado":"falta","opcional":true},{"clave":"fotos","estado":"hecho"}]}"""

        /**
         * `sinPermiso` (palancas prendidas, sin permiso), `conPermiso`, `sinRedPermiso` (dar el permiso falla), `apagado`
         * (palancas apagadas), `apagadoConPermiso`, `sinServidor` (PGRST202), `sinRed`, `listaLista` (todo hecho),
         * `listaInactiva`.
         */
        fun escenario(nombre: String): DobleColaA {
            val d = DobleColaA()
            when (nombre) {
                "conPermiso" -> d.permiso = true
                "sinRedPermiso" -> d.sinRedPermiso = true
                "apagado" -> { d.palancaWins = false; d.palancaLista = false }
                "apagadoConPermiso" -> { d.palancaWins = false; d.palancaLista = false; d.permiso = true }
                "sinServidor" -> d.sinFuncion = true
                "sinRed" -> d.sinRed = true
                "listaLista" -> d.lista = LISTA_LISTA
                "listaInactiva" -> d.lista = """{"ok":true,"activa":false,"items":[]}"""
            }
            return d
        }
    }
}
