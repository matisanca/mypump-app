package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.time.ZoneId
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** Los vectores que comparte con iOS (`apps/shared/vectores/estudios.json`): mismos textos, mismas fechas, misma tolerancia. */
class EstudiosVectoresTest {
    private val v: ValorJson = ValorJson.desde(Vectores.json(Vectores.publico("estudios")) as JsonObject)
    private fun lista(j: ValorJson?) = (j as? ValorJson.Lista)?.elementos ?: emptyList()
    private fun textos(j: ValorJson?) = lista(j).mapNotNull { it.comoTexto }
    private fun entero(j: ValorJson?) = j?.comoNumero?.toInt()
    private fun dia(j: ValorJson?) = Estudios.dia(j?.comoTexto)

    @Test fun constantes() {
        assertEquals(entero(v["maxPx"]), Estudios.MAX_PX)
        assertEquals(v["calidad"]?.comoNumero, Estudios.CALIDAD)
        assertEquals(entero(v["topeArchivos"]), Estudios.TOPE_ARCHIVOS)
        assertEquals(entero(v["topeMB"]), Estudios.TOPE_MB)
    }

    @Test fun textosFijos() {
        val t = TextosEstudios
        val propios = mapOf(
            "entradaMisDatos" to t.entrada, "titulo" to t.titulo, "proximoControl" to t.proximoControl, "teFaltaHacer" to t.teFaltaHacer,
            "subirResultado" to t.subirResultado, "yaMeLoHice" to t.yaMeLoHice, "verOrden" to t.verOrden, "deshacer" to t.deshacer,
            "subirEstudio" to t.subirUnEstudio, "tusOrdenes" to t.tusOrdenes, "tusEstudios" to t.tusEstudios, "ver" to t.ver, "recibido" to t.recibido,
            "matiLoVio" to t.matiLoVio, "sinFecha" to t.sinFecha, "ordenVencida" to t.ordenVencida, "notaRecibido" to t.notaFija, "vacio" to t.vacio,
            "errorDeCarga" to t.errorDeCarga, "cuandoTeLoHiciste" to t.cuandoTeLoHiciste, "guardar" to t.guardar, "revisaLaFecha" to t.revisaLaFecha,
            "guiaSubida" to t.guiaSubida, "sacarFotos" to t.sacarFotos, "elegirFotos" to t.elegirFotos, "elegirPDF" to t.elegirPdf, "quitar" to t.quitar,
            "sinSenal" to t.sinSenal, "envioRecibido" to t.recibidoAviso, "topeDia" to t.topeDia, "archivoRechazado" to t.archivoRechazado,
            "comoPrepararte" to t.comoPrepararte, "dondeHacerlo" to t.dondeHacerlo, "noSePudoAbrir" to t.noSePudoAbrir,
        )
        // Si el vector suma un texto, esta prueba falla hasta que Android lo tenga.
        assertEquals((v["textos"] as ValorJson.Objeto).campos.mapValues { it.value.comoTexto }, propios)
    }

    @Test fun pluralesYTopes() {
        for (c in lista(v["subtituloEntrada"])) assertEquals(c["texto"]?.comoTexto, TextosEstudios.subtitulo(entero(c["n"])!!))
        for (c in lista(v["enviarArchivos"])) assertEquals(c["texto"]?.comoTexto, TextosEstudios.enviarArchivos(entero(c["n"])!!))
        for (c in lista(v["hojas"])) assertEquals(c["texto"]?.comoTexto, entero(c["n"])?.takeIf { it > 0 }?.let(TextosEstudios::hojas))
        assertEquals(v["topes"]?.get("archivos")?.comoTexto, TextosEstudios.topeArchivos(Estudios.TOPE_ARCHIVOS))
        assertEquals(v["topes"]?.get("peso")?.comoTexto, TextosEstudios.pesaDeMas(Estudios.TOPE_MB))
        for (c in lista(v["progreso"])) assertEquals(c["texto"]?.comoTexto, Estudios.progreso(entero(c["subidos"])!!, entero(c["total"])!!))
    }

    @Test fun fechas() {
        for (c in lista(v["fechas"])) {
            val f = dia(c["fecha"])
            assertEquals(c["corta"]?.comoTexto, f?.let(Estudios::diaMes), "${c["fecha"]}")
            assertEquals(c["conDia"]?.comoTexto, f?.let(Estudios::diaLargo), "${c["fecha"]}")
        }
        for (c in lista(v["fechaPendiente"])) {
            val r = Estudios.cuandoPendiente(dia(c["desde"]), dia(c["hasta"]), dia(c["hoy"]))
            assertEquals(c["texto"]?.comoTexto, r?.texto, "$c")
            assertEquals(c["pasada"] == ValorJson.Booleano(true), r?.pasada ?: false, "$c")
        }
        for (c in lista(v["fechaControl"])) assertEquals(c["texto"]?.comoTexto, Estudios.cuandoControl(dia(c["desde"]), dia(c["hasta"])), "$c")
        for (c in lista(v["hecho"])) assertEquals(c["texto"]?.comoTexto, Estudios.hecho(dia(c["fecha"])))
    }

    @Test fun ordenesEstudiosYEnvios() {
        for (c in lista(v["orden"])) {
            assertEquals(c["texto"]?.comoTexto, Estudios.renglonesOrden(OrdenEstudios("o", null, "x", dia(c["emitida"]), dia(c["vence"]), true)).joinToString(" · "))
        }
        for (c in lista(v["estudio"])) {
            assertEquals(c["texto"]?.comoTexto, Estudios.detalleEstudio(EstudioRecibido("e", null, "x", dia(c["fecha"]), entero(c["hojas"]) ?: 0, visto = false, sePuedeAbrir = false)))
        }
        for (c in lista(v["envio"])) {
            assertEquals(c["texto"]?.comoTexto, Estudios.envioCompleto(EnvioRecibido("s", entero(c["archivos"]) ?: 0, null, c["enviado_en"]?.comoTexto), ZoneId.of(c["zona"]!!.comoTexto!!)))
        }
    }

    @Test fun preparacionYDonde() {
        for ((tipo, renglones) in (v["preparacion"] as ValorJson.Objeto).campos) assertEquals(textos(renglones), TextosEstudios.preparacion(tipo), tipo)
        for ((tipo, renglones) in (v["donde"] as ValorJson.Objeto).campos) assertEquals(textos(renglones), TextosEstudios.donde(tipo), tipo)
    }

    @Test fun subida() {
        for (c in lista(v["subida"])) {
            assertEquals(c["accion"]?.comoTexto, Estudios.clasificarSubida(entero(c["status"])!!, c["ok"] == ValorJson.Booleano(true)).name.lowercase(), "$c")
        }
    }

    @Test fun elGetTolerante() {
        val g = v["get"]!!
        for (j in lista(g["noHabilitado"])) assertNull(EstadoEstudios.desde(j), "$j")
        val e = EstadoEstudios.desde(g["respuesta"])!!
        val espera = g["espera"]!!
        assertEquals(entero(espera["pendientes"]), e.pendientes.size)
        assertEquals(entero(espera["pendientesHechos"]), e.pendientes.count { it.hecho })
        assertEquals(entero(espera["ordenes"]), e.ordenes.size)
        assertEquals(entero(espera["ordenesVigentes"]), e.ordenes.count { it.vigente })
        assertEquals(entero(espera["estudios"]), e.estudios.size)
        assertEquals(entero(espera["estudiosVistos"]), e.estudios.count { it.visto })
        assertEquals(entero(espera["estudiosQueSeAbren"]), e.estudios.count { it.sePuedeAbrir })
        assertEquals(entero(espera["enviosVisibles"]), e.envios.size)
        assertEquals(espera["subtitulo"]?.comoTexto, Estudios.subtitulo(e))
        assertEquals(espera["tituloSinTitulo"]?.comoTexto, e.estudios.last().titulo)
        fun bloques(x: EstadoEstudios) = Estudios.bloques(x).let { b ->
            mapOf(
                "proximoControl" to (Estudios.Bloque.PROXIMO in b), "pendientes" to (Estudios.Bloque.PENDIENTES in b), "ordenes" to (Estudios.Bloque.ORDENES in b),
                "estudios" to (Estudios.Bloque.ESTUDIOS in b), "vacio" to (Estudios.Bloque.VACIO in b),
            )
        }
        assertEquals((espera["bloques"] as ValorJson.Objeto).campos.mapValues { it.value == ValorJson.Booleano(true) }, bloques(e))
        val vacia = EstadoEstudios.desde(g["vacia"])!!
        assertEquals(mapOf("proximoControl" to false, "pendientes" to false, "ordenes" to false, "estudios" to false, "vacio" to true), bloques(vacia))
        assertEquals(TextosEstudios.todoAlDia, Estudios.subtitulo(vacia))
    }
}
