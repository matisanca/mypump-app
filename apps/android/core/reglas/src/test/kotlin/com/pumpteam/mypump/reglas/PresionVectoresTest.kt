package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Los vectores que comparten la web, iOS y el servidor (`apps/shared/vectores/presion.json`). Se recorre TODO el archivo y se
 * compara la salida completa. Gemelo de PresionTests.swift.
 */
class PresionVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("presion")))
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun n(i: Int?): ValorJson = i?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo
    private fun t(s: String?): ValorJson = s?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo
    private fun b(x: Boolean?): ValorJson = x?.let { ValorJson.Booleano(it) } ?: ValorJson.Nulo
    private fun textos(xs: List<String>): ValorJson = ValorJson.Lista(xs.map { ValorJson.Texto(it) })
    private fun valor(x: Presion.Valor?): ValorJson = x?.let { ValorJson.objeto("sis" to n(it.sis), "dia" to n(it.dia), "pulso" to n(it.pulso)) } ?: ValorJson.Nulo
    /** Los vectores traen `null` explícito: para comparar, una clave ausente y un null son lo mismo. */
    private fun sale(c: ValorJson): ValorJson = c["sale"] ?: ValorJson.Nulo

    private fun json(e: Presion.Evaluacion): ValorJson = ValorJson.objeto(
        "paso" to t(e.paso.clave), "texto" to t(e.texto), "cuenta" to b(e.cuenta), "motivo_exclusion" to t(e.motivoExclusion), "valor" to valor(e.valor),
        "valida_bajo_efecto" to b(e.validaBajoEfecto), "urgencia" to b(e.urgencia),
        "ortostatica" to (
            e.ortostatica?.let {
                ValorJson.objeto(
                    "caida_sis_max" to n(it.caidaSisMax), "caida_dia_max" to n(it.caidaDiaMax), "subida_pulso_max" to n(it.subidaPulsoMax),
                    "hipotension" to b(it.hipotension), "hipertension_posible" to b(it.hipertensionPosible),
                )
            } ?: ValorJson.Nulo
            ),
        "reglas" to textos(e.reglas),
    )

    private fun json(r: Presion.ResumenSerie): ValorJson = ValorJson.objeto(
        "tomas_validas" to n(r.tomasValidas), "dias" to textos(r.dias), "serie_valida" to b(r.serieValida), "faltan" to n(r.faltan), "promedio" to valor(r.promedio),
        "maximos" to (r.maximos?.let { ValorJson.objeto("sis" to n(it.first), "dia" to n(it.second)) } ?: ValorJson.Nulo), "categoria" to t(r.categoria),
        "bajo_efecto" to ValorJson.objeto(
            "n" to n(r.bajoEfecto.n), "validas" to n(r.bajoEfecto.validas), "promedio" to valor(r.bajoEfecto.promedio),
            "tomas_pulso_100_o_mas" to n(r.bajoEfecto.tomasPulso100OMas), "aviso" to b(r.bajoEfecto.aviso), "alta" to b(r.bajoEfecto.alta),
        ),
        "reglas" to textos(r.reglas),
    )

    /** Ninguna clave del archivo queda sin recorrer: si los vectores suman una, esta prueba falla hasta que se cubra. */
    @Test fun seRecorreTodoElArchivo() {
        assertEquals(
            setOf(
                "_", "limites", "espera_repeticion_s", "reposo_s", "recordatorio_min", "sin_repetir_min", "alarma", "otros", "sintomas", "validar", "nivel", "tramo",
                "calza", "metodo", "momento", "pasos", "sesion", "serie", "textos", "propios",
            ),
            (v as ValorJson.Objeto).campos.keys,
        )
    }

    @Test fun constantes() {
        assertEquals(
            ValorJson.objeto(
                "sisMin" to n(Presion.Lim.SIS_MIN), "sisMax" to n(Presion.Lim.SIS_MAX), "diaMin" to n(Presion.Lim.DIA_MIN), "diaMax" to n(Presion.Lim.DIA_MAX),
                "pulMin" to n(Presion.Lim.PUL_MIN), "pulMax" to n(Presion.Lim.PUL_MAX), "difMin" to n(Presion.Lim.DIF_MIN),
            ),
            v["limites"],
        )
        assertEquals(n(Presion.ESPERA_REPETICION_S), v["espera_repeticion_s"])
        assertEquals(n(Presion.REPOSO_S), v["reposo_s"])
        assertEquals(n(Presion.RECORDATORIO_MIN), v["recordatorio_min"])
        assertEquals(n(Presion.SIN_REPETIR_MIN), v["sin_repetir_min"])
        assertEquals(textos(Presion.alarma), v["alarma"])
        assertEquals(textos(Presion.otros), v["otros"])
        assertEquals(ValorJson.Objeto(TextosPresion.sintomas.mapValues { ValorJson.Texto(it.value) }), v["sintomas"])
    }

    /** Clave por clave, idénticos a `textos` (T) y `propios` (N), sin ninguno de más ni de menos. */
    @Test fun textos() {
        val esperados = (v["textos"] as ValorJson.Objeto).campos
        val mios = (TextosPresion.T.todos as ValorJson.Objeto).campos
        assertEquals(esperados.keys, mios.keys)
        for ((k, e) in esperados) assertEquals(e, mios[k], "textos.$k")
        val propios = (v["propios"] as ValorJson.Objeto).campos
        val misN = (TextosPresion.N.todos as ValorJson.Objeto).campos
        assertEquals(propios.keys, misN.keys)
        for ((k, e) in propios) assertEquals(e, misN[k], "propios.$k")
    }

    /** El alumno no lee ninguna de estas palabras, y los textos no llevan «:», «;» ni guiones. */
    @Test fun textosSinPalabrasVedadas() {
        val todos = mutableListOf<String>()
        fun juntar(j: ValorJson) {
            when (j) {
                is ValorJson.Texto -> todos += j.valor
                is ValorJson.Lista -> j.elementos.forEach(::juntar)
                is ValorJson.Objeto -> j.campos.values.forEach(::juntar)
                else -> Unit
            }
        }
        juntar(TextosPresion.T.todos)
        juntar(TextosPresion.N.todos)
        todos += TextosPresion.sintomas.values
        assertTrue(todos.size > 150)
        val vedadas = listOf("hipertens", "normal", "riesgo", "promedio de", "tu coach", "tu entrenador", "inteligencia artificial")
        for (s in todos) {
            val m = s.lowercase()
            for (p in vedadas) assertFalse(p in m, "«$s» dice «$p»")
            assertFalse(Regex("\\bia\\b").containsMatchIn(m), "«$s» dice IA")
            assertFalse(":" in s || ";" in s || " - " in s || "—" in s || "–" in s, "«$s» lleva puntuación vedada")
        }
    }

    @Test fun validarNivelTramoYMomento() {
        for (c in lista(v["validar"])) {
            val x = c["toma"]
            assertEquals(sale(c).comoTexto, Presion.validarToma(x?.get("sis")?.comoNumero, x?.get("dia")?.comoNumero, x?.get("pulso")?.comoNumero).clave, "$c")
        }
        for (c in lista(v["nivel"])) {
            val x = c["toma"]!!
            assertEquals(sale(c).comoTexto, Presion.nivelToma(Presion.entero(x["sis"])!!, Presion.entero(x["dia"])!!).clave, "$c")
        }
        for (c in lista(v["tramo"])) assertEquals(sale(c), t(Presion.tramoBrazo(c["cm"]?.comoNumero)), "$c")
        for (c in lista(v["momento"])) assertEquals(sale(c).comoTexto, Presion.momento(Presion.entero(c["hora"])!!), "$c")
        assertEquals(listOf(21, 10, 7, 12, 5).sorted(), listOf("validar", "nivel", "tramo", "calza", "momento").map { lista(v[it]).size }.sorted())
    }

    @Test fun calzaYMetodo() {
        for (c in lista(v["calza"])) assertEquals(sale(c), b(Presion.manguitoCalza(c["cm"]?.comoNumero, Presion.Aparato.desde(c["aparato"]))), "$c")
        for (c in lista(v["metodo"])) {
            val m = Presion.metodo(c["cm"]?.comoNumero, Presion.Aparato.desde(c["aparato"]))
            assertEquals(
                sale(c),
                ValorJson.objeto(
                    "metodo" to t(m.metodo), "provisoria" to b(m.provisoria), "pedir_brazo" to b(m.pedirBrazo), "pedir_validado" to b(m.pedirValidado),
                    "admite_tomas" to b(m.admiteTomas),
                ),
                "$c",
            )
        }
        assertEquals(8, lista(v["metodo"]).size)
    }

    @Test fun pasos() {
        for (c in lista(v["pasos"])) {
            val p = Presion.pasos(c["tipo"]!!.comoTexto!!, c["variante"]?.comoTexto)
            assertEquals(
                sale(c),
                ValorJson.Lista(p.map { ValorJson.objeto("espera_s" to n(it.esperaS), "posicion" to t(it.posicion), "minutos_de_pie" to n(it.minutosDePie), "brazo" to t(it.brazo)) }),
                "$c",
            )
        }
        assertEquals(6, lista(v["pasos"]).size)
    }

    @Test fun sesion() {
        for (c in lista(v["sesion"])) assertEquals(sale(c), json(Presion.evaluarSesion(Presion.Sesion.desde(c["entrada"]!!))), c["nombre"]?.comoTexto)
        assertEquals(50, lista(v["sesion"]).size)
    }

    @Test fun serie() {
        for (c in lista(v["serie"])) {
            val e = c["entrada"]!!
            val s = e["serie"]
            val entrada = Presion.EntradaSerie(
                tipo = s?.get("tipo")?.comoTexto, tomasObjetivo = Presion.entero(s?.get("tomas_objetivo")), fechaInicio = s?.get("fecha_inicio")?.comoTexto,
                sesiones = lista(e["sesiones"]).map(Presion.Sesion::desde), soloUrgencias = e["solo_urgencias"] == ValorJson.Booleano(true),
                basalPulso = Presion.entero(e["basal_pulso"]),
            )
            assertEquals(sale(c), json(Presion.resumenSerie(entrada)), c["nombre"]?.comoTexto)
        }
        assertEquals(24, lista(v["serie"]).size)
    }

    /** La sesión guardada en el teléfono vuelve igual. */
    @Test fun laSesionVaYVuelve() {
        for (c in lista(v["sesion"])) {
            val s = Presion.Sesion.desde(c["entrada"]!!)
            assertEquals(s.copy(minutosDesdeUltima = 0.0), Presion.Sesion.desde(s.aValor()))
        }
    }
}
