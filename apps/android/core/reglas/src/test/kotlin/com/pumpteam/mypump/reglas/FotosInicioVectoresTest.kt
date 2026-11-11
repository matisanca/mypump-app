package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS y la web (`apps/shared/vectores/fotos_inicio.json`). Gemelo de FotosInicioVectoresTests.swift. */
class FotosInicioVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("fotos_inicio")) as JsonObject)
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun textos(j: ValorJson?) = lista(j).mapNotNull { it.comoTexto }
    private fun numero(j: ValorJson?) = j?.comoNumero ?: -1.0
    private fun entero(j: ValorJson?) = numero(j).toInt()
    private fun enteroONulo(j: ValorJson?) = j?.comoNumero?.toInt()
    private fun bool(j: ValorJson?) = j == ValorJson.Booleano(true)

    @Test fun posesConsejosYConstantes() {
        assertEquals(lista(v["poses"]).map { it["clave"]?.comoTexto }, FotosInicio.poses.map { it.clave })
        assertEquals(lista(v["poses"]).map { it["nombre"]?.comoTexto }, FotosInicio.poses.map { it.nombre })
        assertEquals(lista(v["poses"]).map { it["instruccion"]?.comoTexto }, FotosInicio.poses.map { it.instruccion })
        assertEquals(textos(v["consejos"]), FotosInicio.consejos)
        assertEquals(entero(v["maxPx"]), FotosInicio.MAX_PX)
        assertEquals(numero(v["calidad"]), FotosInicio.CALIDAD)
        assertEquals(entero(v["minLado"]), FotosInicio.MIN_LADO)
        assertEquals(entero(v["minLadoMotivacion"]), FotosInicio.MIN_LADO_MOTIVACION)
        assertEquals(entero(v["maxMotivacion"]), FotosInicio.MAX_MOTIVACION)
        assertEquals(entero(v["maxNota"]), FotosInicio.MAX_NOTA)
        assertEquals(numero(v["brilloMinimo"]), FotosInicio.BRILLO_MINIMO)
        assertEquals(numero(v["nitidezMinima"]), FotosInicio.NITIDEZ_MINIMA)
        assertEquals(entero(v["diasVieja"]), FotosInicio.DIAS_VIEJA)
        assertEquals(entero(v["ladoAnalisis"]), FotosInicio.LADO_ANALISIS)
        assertEquals(FotosInicio.poses[1], FotosInicio.pose("perfil"))
        assertNull(FotosInicio.pose(FotosInicio.MOTIVACION))
    }

    @Test fun textos() {
        val t = (v["textos"] as ValorJson.Objeto).campos.mapValues { it.value.comoTexto }
        assertEquals(t, TextosFotosInicio.todos)
        // Las fotos son privadas: solo se nombra a Mati.
        val prohibido = Regex("\\bIA\\b|inteligencia|coach", RegexOption.IGNORE_CASE)
        val variables = (1..10).flatMap { listOf(TextosFotosInicio.faltan(it), TextosFotosInicio.cuenta(it), TextosFotosInicio.problemaVieja(it)) }
        for (s in TextosFotosInicio.todos.values + variables + FotosInicio.consejos + FotosInicio.poses.flatMap { listOf(it.nombre, it.instruccion) }) {
            assertFalse(prohibido.containsMatchIn(s), s)
        }
        for (c in lista(v["plurales"])) {
            val n = entero(c["n"])
            assertEquals(c["faltan"]?.comoTexto, TextosFotosInicio.faltan(n))
            assertEquals(c["cuenta"]?.comoTexto, TextosFotosInicio.cuenta(n))
            assertEquals(c["vieja"]?.comoTexto, TextosFotosInicio.problemaVieja(n))
        }
        val p = (v["textosProblema"] as ValorJson.Objeto).campos
        assertEquals(FotosInicio.Problema.entries.map { it.clave }.toSet(), p.keys + "vieja")
        for ((k, s) in p) assertEquals(s.comoTexto, FotosInicio.texto(FotosInicio.Problema.entries.first { it.clave == k }), k)
        assertEquals(TextosFotosInicio.problemaVieja(9), FotosInicio.texto(FotosInicio.Problema.VIEJA, 9))
        assertEquals(TextosFotosInicio.problemaVieja(FotosInicio.DIAS_VIEJA + 1), FotosInicio.texto(FotosInicio.Problema.VIEJA))
    }

    @Test fun lumaYMedida() {
        assertTrue(lista(v["luma"]).isNotEmpty())
        for (c in lista(v["luma"])) assertEquals(entero(c["l"]), FotosInicio.luma(entero(c["r"]), entero(c["g"]), entero(c["b"])), "$c")
        assertTrue(lista(v["medir"]).size > 10)
        for (c in lista(v["medir"])) {
            val luma = lista(c["luma"]).map { entero(it).toByte() }.toByteArray()
            val m = FotosInicio.medir(luma, entero(c["ancho"]), entero(c["alto"]), enteroONulo(c["paso"]))
            val caso = c["caso"]?.comoTexto ?: ""
            assertEquals(numero(c["brillo"]), m.brillo, 1e-9, caso)
            assertEquals(numero(c["nitidez"]), m.nitidez, 1e-9, caso)
        }
        // Faltan datos: no se cuelga.
        assertEquals(FotosInicio.Medida(0.0, 0.0), FotosInicio.medir(byteArrayOf(1, 2), 4, 4))
        assertEquals(FotosInicio.Medida(0.0, 0.0), FotosInicio.medir(ByteArray(0), 0, 0))
    }

    @Test fun problemas() {
        val casos = lista(v["problemas"])
        assertTrue(casos.isNotEmpty())
        for (c in casos) {
            val p = FotosInicio.problemas(
                c["pose"]?.comoTexto ?: "", entero(c["ancho"]), entero(c["alto"]),
                FotosInicio.Medida(numero(c["brillo"]), numero(c["nitidez"])), enteroONulo(c["dias"]),
            )
            assertEquals(textos(c["problemas"]), p.map { it.clave }, "$c")
            assertEquals(bool(c["bloquea"]), FotosInicio.bloquea(p), "$c")
        }
    }

    @Test fun subida() {
        val casos = lista(v["subida"])
        assertTrue(casos.isNotEmpty())
        for (c in casos) {
            val s = FotosInicio.clasificarSubida(entero(c["status"]), bool(c["ok"]))
            assertEquals(c["accion"]?.comoTexto, s.accion.clave, "$c")
            assertEquals(c["aviso"]?.comoTexto, s.aviso?.clave, "$c")
            assertEquals(bool(c["refrescar"]), s.refrescar, "$c")
        }
    }

    @Test fun elSet() {
        for (c in lista(v["faltan"])) {
            assertEquals(textos(c["faltan"]), FotosInicio.faltan(textos(c["enServidor"]).toSet(), textos(c["enCola"]).toSet()), "$c")
        }
        for (c in lista(v["siguiente"])) {
            assertEquals(c["siguiente"]?.comoTexto, FotosInicio.siguiente(c["pose"]?.comoTexto ?: "", textos(c["faltan"])), "$c")
        }
        for (c in lista(v["motivacion"])) {
            assertEquals(bool(c["puede"]), FotosInicio.puedeAgregarMotivacion(entero(c["servidor"]), entero(c["cola"]), entero(c["maximo"])), "$c")
        }
        assertTrue(lista(v["notas"]).isNotEmpty())
        for (c in lista(v["notas"])) assertEquals(c["n"]?.comoTexto, FotosInicio.notaRecortada(c["s"]?.comoTexto ?: ""), c["s"]?.comoTexto?.debug())
        for (c in lista(v["dias"])) {
            assertEquals(entero(c["dias"]), FotosInicio.dias(Instant.parse(c["tomada"]!!.comoTexto!!), Instant.parse(c["ahora"]!!.comoTexto!!)), "$c")
        }
    }

    @Test fun decodificar() {
        for (c in lista(v["decodificar"])) {
            val e = EstadoFotosInicio.desde(c["j"] ?: ValorJson.Nulo)
            assertEquals(bool(c["habilitado"]), e != null, "$c")
            if (e == null) continue
            assertEquals(textos(c["poses"]), e.poses.sorted(), "$c")
            assertEquals(entero(c["motivacion"]), e.deMotivacion.size, "$c")
            assertEquals(c["nota"]?.comoTexto, e.nota, "$c")
            assertEquals(bool(c["completo"]), e.completo, "$c")
            assertEquals(entero(c["maxMotivacion"]), e.maxMotivacion, "$c")
        }
    }

    @Test fun siluetas() {
        val s = v["siluetas"]!!
        assertEquals(listOf(SiluetasFotosInicio.ANCHO, SiluetasFotosInicio.ALTO), lista(s["caja"]).map { numero(it) })
        for (pose in FotosInicio.poses) {
            val sil = SiluetasFotosInicio.de(pose.clave)!!
            assertEquals(s[pose.clave]?.get("contorno")?.comoTexto, sil.contorno, pose.clave)
            assertEquals(s[pose.clave]?.get("detalle")?.comoTexto, sil.detalle, pose.clave)
            val ordenes = SiluetasFotosInicio.ordenes(sil.contorno)
            assertEquals(sil.contorno.count { it in "MCZ" }, ordenes.size, pose.clave)
            assertEquals(SiluetasFotosInicio.Orden.Cerrar, ordenes.last())
            assertEquals(sil.detalle.count { it in "MCZ" }, SiluetasFotosInicio.ordenes(sil.detalle).size, pose.clave)
            // Todo adentro de la caja.
            for (o in ordenes + SiluetasFotosInicio.ordenes(sil.detalle)) {
                val puntos = when (o) {
                    is SiluetasFotosInicio.Orden.Mover -> listOf(o.x to o.y)
                    is SiluetasFotosInicio.Orden.Curva -> listOf(o.x1 to o.y1, o.x2 to o.y2, o.x to o.y)
                    SiluetasFotosInicio.Orden.Cerrar -> emptyList()
                }
                for ((x, y) in puntos) assertTrue(x in 0.0..SiluetasFotosInicio.ANCHO && y in 0.0..SiluetasFotosInicio.ALTO, "${pose.clave} $x,$y")
            }
        }
        assertNull(SiluetasFotosInicio.de(FotosInicio.MOTIVACION))
        assertEquals(
            listOf(SiluetasFotosInicio.Orden.Mover(1.0, 2.0), SiluetasFotosInicio.Orden.Curva(1.0, 2.0, 3.0, 4.0, 5.0, 6.0), SiluetasFotosInicio.Orden.Cerrar),
            SiluetasFotosInicio.ordenes("M1 2 C1 2 3 4 5 6 Z X9 M3"),
        )
        assertEquals(emptyList<SiluetasFotosInicio.Orden>(), SiluetasFotosInicio.ordenes("M1f 2d"))
    }

    @Test fun cubreTodasLasSecciones() {
        // Si los vectores suman una sección, esta prueba obliga a mirarla.
        val cubiertas = setOf(
            "_", "poses", "consejos", "maxPx", "calidad", "minLado", "minLadoMotivacion", "maxMotivacion", "maxNota", "brilloMinimo",
            "nitidezMinima", "diasVieja", "ladoAnalisis", "textos", "plurales", "luma", "medir", "problemas", "textosProblema", "siluetas",
            "subida", "faltan", "siguiente", "motivacion", "notas", "dias", "decodificar",
        )
        assertEquals(cubiertas, (v as ValorJson.Objeto).campos.keys)
    }
}
