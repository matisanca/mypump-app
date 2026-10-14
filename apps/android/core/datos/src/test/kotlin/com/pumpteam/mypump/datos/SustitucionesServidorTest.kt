package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import java.util.Collections
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de SustitucionesServidorTests.swift. SER-14: las sustituciones de ejercicio también en el servidor (`nativa_003`).
// Lo que importa: que nada de lo que hoy funciona cambie si la tabla no está (PGRST202), sin red o con el token caído; que
// gane siempre lo último que hizo el cliente, en cualquier teléfono y en cualquier orden de llegada; y que nunca se pierda
// algo que el servidor no tiene. Los casos con nombre de hallazgo son los de la revisión independiente del 14-oct.

private fun e(nombre: String, ts: Double? = null, fijado: Boolean = true, semana: Double = 5.0): ValorJson {
    val o = linkedMapOf<String, ValorJson>(
        "current" to ValorJson.objeto("nombre" to ValorJson.Texto(nombre)), "fijado" to ValorJson.Booleano(fijado), "semana" to ValorJson.Numero(semana),
    )
    if (ts != null) o["_ts"] = ValorJson.Numero(ts)
    return ValorJson.Objeto(o)
}

class SustitucionesServidorReglasTest {
    @Test
    fun lasOpsSalenDeLaDiferenciaYElBorradoLlevaSuHora() {
        val x = e("Dominadas", 10.0)
        val y = e("Remo en T", 20.0)
        val ops = SustitucionesServidor.operaciones(
            mapOf("a" to x, "b" to x, "c" to x), mapOf("a" to x, "b" to y, "d" to y, "e" to ValorJson.Texto("rara")), "R",
        )
        assertEquals(listOf("swap_ej", "swap_ej_del", "swap_ej"), ops.map { it.kind }, "b cambia, c se va, d entra; a igual y e no se sube")
        assertEquals(listOf("b", "c", "d"), ops.map { it.exId })
        assertEquals(listOf("swap_ej_R_b", "swap_ej_R_c", "swap_ej_R_d"), ops.map { it.clave })
        assertEquals(ValorJson.objeto("rutinaId" to ValorJson.Texto("R"), "exId" to ValorJson.Texto("b"), "swap" to y), ops[0].payload)
        assertEquals(
            ValorJson.objeto("rutinaId" to ValorJson.Texto("R"), "exId" to ValorJson.Texto("c"), "ts" to ValorJson.Numero(10.0)), ops[1].payload,
            "el borrado lleva la hora de lo que se borró: no saca algo más nuevo que no se vio",
        )
    }

    /** Revisión 2, hallazgo 3: un cambio le gana a lo que reemplaza aunque eso tenga hora del futuro. */
    @Test
    fun laHoraDeUnCambioNuncaEsMenorQueLaDeLoQueReemplaza() {
        assertEquals(1000.0, SustitucionesServidor.horaDeUnCambio(1000.4, e("X", 5.0)))
        assertEquals(9_001.0, SustitucionesServidor.horaDeUnCambio(1000.0, e("X", 9_000.0)))
        assertEquals(1000.0, SustitucionesServidor.horaDeUnCambio(1000.0, null))
    }

    /** La misma elección con otra hora (el servidor recortó una del futuro): queda la del servidor y no se vuelve a subir. */
    @Test
    fun laMismaEleccionConOtraHoraQuedaLaDelServidor() {
        val r = SustitucionesServidor.combinar(mapOf("x" to e("X", 3000.0)), emptyMap(), mapOf("x" to e("X", 9_000_000.0)), emptyMap(), "R", emptySet())
        assertEquals(mapOf("x" to e("X", 3000.0)), r)
    }

    /** Hallazgo 6: la base cuenta la clave en puntos de código (`length`), no en grafemas. */
    @Test
    fun soloSeSubeLoQueLaBaseAcepta() {
        assertTrue(SustitucionesServidor.subible("a", e("X")))
        assertTrue(SustitucionesServidor.subible("a", e("X", 1_792_000_800_000.0)))
        assertFalse(SustitucionesServidor.subible("a", ValorJson.Lista(emptyList())))
        assertFalse(SustitucionesServidor.subible("", e("X")))
        assertFalse(SustitucionesServidor.subible("x".repeat(121), e("X")))
        val combinadas = "é".repeat(61)
        assertFalse(SustitucionesServidor.subible(combinadas, e("X")), "61 grafemas, 122 puntos de código")
        val emojis = "💪".repeat(61)   // 61 puntos de código, 122 unidades UTF-16: entra
        assertTrue(SustitucionesServidor.subible(emojis, e("X")))
        assertFalse(SustitucionesServidor.subible("a", ValorJson.objeto("relleno" to ValorJson.Texto("x".repeat(13_000)))))
        assertFalse(SustitucionesServidor.subible("a", ValorJson.objeto("_ts" to ValorJson.Texto("ayer"))))
        assertFalse(SustitucionesServidor.subible("a", ValorJson.objeto("_ts" to ValorJson.Numero(-1.0))))
    }

    @Test
    fun ganaLoMasNuevoYLoQueElServidorNoTieneQueda() {
        val r = SustitucionesServidor.combinar(
            vivas = mapOf(
                "nuevaAlla" to e("S", 20.0), "viejaAlla" to e("S", 5.0), "soloAlla" to e("S", 1.0), "empate" to e("S", 7.0),
                "malo" to ValorJson.Numero(1.0),
            ),
            borradas = mapOf("lapidaNueva" to 30.0, "lapidaVieja" to 2.0, "lapidaDeNada" to 9.0),
            local = mapOf(
                "nuevaAlla" to e("L", 10.0), "viejaAlla" to e("L", 15.0), "empate" to e("L", 7.0), "lapidaNueva" to e("L", 25.0),
                "lapidaVieja" to e("L", 3.0), "soloAca" to e("L"), "rara" to ValorJson.Texto("nunca subió"),
            ),
            pendientes = emptyMap(), rutinaId = "R", tocadas = emptySet(),
        )
        assertEquals(
            mapOf(
                "nuevaAlla" to e("S", 20.0), "viejaAlla" to e("L", 15.0), "soloAlla" to e("S", 1.0), "empate" to e("S", 7.0),
                "lapidaVieja" to e("L", 3.0), "soloAca" to e("L"), "rara" to ValorJson.Texto("nunca subió"),
            ),
            r,
        )
    }

    /** Revisión 3, hallazgo 1: una copia propia del futuro (reloj adelantado) no le gana al servidor; dentro del margen, sí. */
    @Test
    fun unaCopiaPropiaDelFuturoNoLeGanaAlServidor() {
        val ahora = 1_000_000_000.0
        val r = SustitucionesServidor.combinar(
            vivas = mapOf("x" to e("De otro", ahora - 600_000), "y" to e("De otro", ahora - 600_000)),
            borradas = mapOf("z" to ahora - 600_000),
            local = mapOf("x" to e("Mía", ahora + 3 * 3_600_000), "y" to e("Mía", ahora + 60_000), "z" to e("Mía", ahora + 3 * 3_600_000)),
            pendientes = emptyMap(), rutinaId = "R", tocadas = emptySet(), ahora = ahora,
        )
        assertEquals(mapOf("x" to e("De otro", ahora - 600_000), "y" to e("Mía", ahora + 60_000)), r)
    }

    @Test
    fun laColaYLoTocadoGananAlServidor() {
        fun op(id: String, kind: String, rutina: String, ex: String, swap: ValorJson?) = Operacion(
            id, kind,
            ValorJson.Objeto(listOfNotNull("rutinaId" to ValorJson.Texto(rutina), "exId" to ValorJson.Texto(ex), swap?.let { "swap" to it }).toMap()),
            "swap_ej_${rutina}_$ex", ts = 0.0,
        )
        val r = SustitucionesServidor.combinar(
            vivas = mapOf("s" to e("S", 99.0), "t" to e("S", 99.0), "u" to e("S", 99.0)), borradas = emptyMap(),
            local = mapOf("t" to e("L", 1.0)),
            pendientes = mapOf(
                "swap_ej_R_p" to op("1", "swap_ej", "R", "p", e("P", 1.0)), "swap_ej_R_s" to op("2", "swap_ej_del", "R", "s", null),
                "swap_ej_OTRA_q" to op("3", "swap_ej", "OTRA", "q", e("Q", 1.0)),
            ),
            rutinaId = "R", tocadas = setOf("t", "u"),
        )
        assertEquals(
            mapOf("p" to e("P", 1.0), "t" to e("L", 1.0)), r,
            "p y s en la cola; t y u se tocaron (u se borró): gana lo del teléfono aunque el servidor sea más nuevo",
        )
    }

    @Test
    fun volverDeLaAppViejaSoloAplicaLoQueSeCambioAhi() {
        val base = mapOf("a" to e("A"), "b" to e("B"), "c" to e("C"))
        val legado = mapOf("a" to e("A"), "b" to e("B2"), "n" to e("N"))
        val nativa = mapOf("a" to e("A nativa", 50.0), "b" to e("B", 0.0), "c" to e("C"), "x" to e("Solo en la nativa", 60.0))
        assertEquals(
            mapOf("a" to e("A nativa", 50.0), "b" to e("B2", 1000.0), "n" to e("N", 1000.0), "x" to e("Solo en la nativa", 60.0)),
            SustitucionesServidor.volverDeLaAppVieja(nativa, legado, base, 1000.0),
        )
        // Lo cambiado le gana a lo que reemplaza aunque tenga hora del futuro.
        val futura = SustitucionesServidor.volverDeLaAppVieja(mapOf("b" to e("B", 5000.0)), legado, base, 1000.0)
        assertEquals(e("B2", 5001.0), futura["b"])
        assertEquals(
            mapOf("a" to e("A", 1000.0), "b" to e("B2", 1000.0), "n" to e("N", 1000.0), "c" to e("C"), "x" to e("Solo en la nativa", 60.0)),
            SustitucionesServidor.volverDeLaAppVieja(nativa, legado, null, 1000.0),
            "sin base: todo lo de la app vieja cuenta como cambiado y no se saca nada",
        )
    }

    @Test
    fun laRespuestaDelServidorSeLeeConSusDosPartes() {
        val j = ValorJson.objeto(
            "vivas" to ValorJson.objeto("a" to e("A"), "malo" to ValorJson.Numero(3.0)), "borradas" to ValorJson.objeto("b" to ValorJson.Numero(9.0)),
        )
        val l = SustitucionesServidor.leer(j)!!
        assertEquals(mapOf("a" to e("A")), l.vivas)
        assertEquals(mapOf("b" to 9.0), l.borradas)
        assertNull(l.ahora)
        assertNull(SustitucionesServidor.leer(ValorJson.Lista(emptyList())))
        assertNull(SustitucionesServidor.leer(ValorJson.Nulo))
    }
}

class SustitucionesServidorModeloTest {
    private val noExiste = 404 to """{"code":"PGRST202","message":"Could not find the function"}"""
    private val ahora = AHORA

    /** Una sustitución de esta semana (la poda no la toca si está fijada). */
    private fun swap(nombre: String, dia: String = "d1", ts: Double? = null, fijado: Boolean = true, semana: Double = 5.0): ValorJson {
        val o = linkedMapOf<String, ValorJson>(
            "original" to ValorJson.objeto("slug" to ValorJson.Nulo, "nombre" to ValorJson.Texto("Original"), "images" to ValorJson.Nulo),
            "current" to ValorJson.objeto(
                "slug" to ValorJson.Nulo, "nombre" to ValorJson.Texto(nombre), "equipment" to ValorJson.Nulo, "images" to ValorJson.Nulo,
            ),
            "fijado" to ValorJson.Booleano(fijado), "semana" to ValorJson.Numero(semana), "diaId" to ValorJson.Texto(dia),
        )
        if (ts != null) o["_ts"] = ValorJson.Numero(ts)
        return ValorJson.Objeto(o)
    }

    private fun json(vivas: Map<String, ValorJson> = emptyMap(), borradas: Map<String, Double> = emptyMap()): String =
        ValorJson.objeto("vivas" to ValorJson.Objeto(vivas), "borradas" to ValorJson.Objeto(borradas.mapValues { ValorJson.Numero(it.value) })).serializar()

    private fun local(b: Banco, m: Map<String, ValorJson>) {
        b.disco.guardar(ModeloEntreno.Archivo.sustituciones("rut-prueba"), ValorJson.Objeto(m))
    }

    private fun enDisco(b: Banco): Map<String, ValorJson>? =
        (b.disco.leer(ModeloEntreno.Archivo.sustituciones("rut-prueba")) as? JsonObject)?.mapValues { ValorJson.desde(it.value) }

    private suspend fun claves(b: Banco): List<String> = b.cola.operaciones().mapNotNull { it.dedupeKey }

    @Test
    fun laPrimeraVezSeSubeLoDelTelefonoYLlegaLoDeOtro() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Dominadas")))   // de la app vieja: sin hora
        b.servidor.cuando("get_exercise_swaps", json(vivas = mapOf("pre-d2-0" to swap("Press inclinado", "d2", ts = 100.0))))
        val m = b.modelo()
        m.cargar()
        assertEquals(listOf("jal-d1-0", "pre-d2-0"), m.dia.value.sustituciones.keys.sorted(), "la del otro teléfono llegó y la de acá quedó")
        assertEquals(listOf("jal-d1-0", "pre-d2-0"), enDisco(b)?.keys?.sorted())
        m.encoladoSustituciones?.join()
        val ops = b.cola.operaciones()
        assertEquals(listOf("swap_ej_rut-prueba_jal-d1-0"), ops.map { it.dedupeKey }, "sube solo lo que el servidor no tiene")
        assertEquals(swap("Dominadas"), ops.first().payload["swap"])
    }

    /** Hallazgo 1: un teléfono viejo con una "solo hoy" vencida no borra en el servidor la que el cliente fijó después en otro. */
    @Test
    fun laPodaDeUnTelefonoViejoNoBorraLoFijadoEnOtro() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Remo en T", ts = 1000.0, fijado = false, semana = 4.0)))
        b.servidor.cuando("get_exercise_swaps", json(vivas = mapOf("jal-d1-0" to swap("Dominadas", ts = 5000.0))))
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertTrue(claves(b).isEmpty(), "la poda mandó un borrado")
        assertEquals(mapOf("jal-d1-0" to swap("Dominadas", ts = 5000.0)), m.dia.value.sustituciones)
    }

    @Test
    fun loVencidoQueVuelveDelServidorSePodaSinMandarNada() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("get_exercise_swaps", json(vivas = mapOf("jal-d1-0" to swap("Remo en T", ts = 1000.0, fijado = false, semana = 4.0))))
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertTrue(m.dia.value.sustituciones.isEmpty() && (enDisco(b) ?: emptyMap()).isEmpty())
        assertTrue(claves(b).isEmpty())
    }

    @Test
    fun loMasNuevoGanaDeUnLadoYDelOtro() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Dominadas", ts = 1000.0), "rem-d1-1" to swap("Remo en T", ts = 3000.0)))
        b.servidor.cuando(
            "get_exercise_swaps",
            json(vivas = mapOf("jal-d1-0" to swap("Jalón cerrado", ts = 2000.0), "rem-d1-1" to swap("Remo bajo", ts = 2000.0))),
        )
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertEquals(swap("Jalón cerrado", ts = 2000.0), m.dia.value.sustituciones["jal-d1-0"], "el servidor era más nuevo")
        assertEquals(swap("Remo en T", ts = 3000.0), m.dia.value.sustituciones["rem-d1-1"], "acá era más nuevo")
        assertEquals(listOf("swap_ej_rut-prueba_rem-d1-1"), claves(b), "sube solo la más nueva de acá")
    }

    /** Hallazgo 3: una lápida más nueva saca la de acá; una más vieja no (y la de acá se vuelve a subir). */
    @Test
    fun lasLapidasSacanLoMasViejoYNoLoMasNuevo() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Dominadas", ts = 1000.0), "rem-d1-1" to swap("Remo en T", ts = 3000.0)))
        b.servidor.cuando("get_exercise_swaps", json(borradas = mapOf("jal-d1-0" to 2000.0, "rem-d1-1" to 2000.0)))
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertEquals(listOf("rem-d1-1"), m.dia.value.sustituciones.keys.sorted())
        assertEquals(listOf("swap_ej_rut-prueba_rem-d1-1"), claves(b))
    }

    /** Hallazgo 2: si la tabla se vaciara (o se recreara), lo del teléfono se vuelve a subir. */
    @Test
    fun siElServidorNoTieneNadaNoSePierdeNadaYSeVuelveASubir() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val mio = mapOf("jal-d1-0" to swap("Dominadas", ts = 1000.0), "rem-d1-1" to swap("Remo en T", ts = 2000.0))
        local(b, mio)
        b.disco.guardar(SustitucionesServidor.archivoEncoladas("rut-prueba"), ValorJson.Objeto(mio))   // ya habían subido
        b.servidor.cuando("get_exercise_swaps", json())
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertEquals(listOf("jal-d1-0", "rem-d1-1"), m.dia.value.sustituciones.keys.sorted())
        assertEquals(listOf("swap_ej_rut-prueba_jal-d1-0", "swap_ej_rut-prueba_rem-d1-1"), claves(b))
    }

    @Test
    fun sinLaTablaEnLaBaseQuedaComoHoy() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        local(b, mapOf("jal-d1-0" to swap("Dominadas")))
        b.servidor.cuando("get_exercise_swaps", noExiste.first, noExiste.second)
        b.servidor.cuando("save_exercise_swap", noExiste.first, noExiste.second)
        b.servidor.cuando("delete_exercise_swap", noExiste.first, noExiste.second)
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        b.cola.observar({ estados += it }, { })
        val m = b.modelo()
        m.cargar()
        assertEquals(mapOf("jal-d1-0" to swap("Dominadas")), m.dia.value.sustituciones)
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.encoladoSustituciones?.join()
        b.cola.drenar()
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        b.cola.drenar()
        assertEquals(1, b.servidor.llamadas("save_exercise_swap").size)
        assertEquals(1, b.servidor.llamadas("delete_exercise_swap").size)
        assertTrue(b.cola.operaciones().isEmpty() && b.cola.fallidos().isEmpty(), "la cola las da por hechas: no hay 'no se guardó'")
        assertTrue(b.servidor.llamadas("get_cliente_info").isEmpty(), "ni se sospecha del token")
        assertFalse(EstadoGuardado.PERDIDO in estados || EstadoGuardado.SIN_CONEXION in estados, "$estados")
        assertEquals(emptyMap<String, ValorJson>(), enDisco(b))
    }

    @Test
    fun sinRedOConElTokenCaidoQuedaLoDelTelefono() = enUnHilo { alcance ->
        for (respuesta in listOf<Pair<Int, String>?>(null, 200 to "null", 200 to "[]")) {
            val b = Banco(alcance)
            local(b, mapOf("jal-d1-0" to swap("Dominadas", ts = 1.0)))
            b.servidor.regla("get_exercise_swaps") { respuesta }
            val m = b.modelo()
            m.sincronizarSustituciones()
            m.encoladoSustituciones?.join()
            assertEquals(mapOf("jal-d1-0" to swap("Dominadas", ts = 1.0)), m.dia.value.sustituciones, "con $respuesta")
            assertEquals(mapOf("jal-d1-0" to swap("Dominadas", ts = 1.0)), enDisco(b))
            assertTrue(claves(b).isEmpty())
        }
    }

    @Test
    fun cadaCambioSaleALaColaConSuHoraYGanaElUltimo() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = false)
        m.encoladoSustituciones?.join()
        val guardar = b.cola.operaciones().first()
        assertTrue(guardar.kind == "swap_ej" && guardar.dedupeKey == "swap_ej_rut-prueba_jal-d1-0")
        assertEquals(ValorJson.Texto("rut-prueba"), guardar.payload["rutinaId"])
        assertEquals(ValorJson.Texto("jal-d1-0"), guardar.payload["exId"])
        assertEquals(m.dia.value.sustituciones["jal-d1-0"], guardar.payload["swap"], "va lo mismo que queda en el teléfono")
        assertEquals(ValorJson.Numero(ahora), guardar.payload["swap"]?.get("_ts"), "con la hora del cambio")
        b.reloj.ms = ahora + 5000
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        val ops = b.cola.operaciones()
        assertTrue(ops.size == 1 && ops.first().kind == "swap_ej_del", "volver al original reemplaza a la de guardar")
        assertEquals(ValorJson.Numero(ahora), ops.first().payload["ts"], "la hora de lo que se veía")
    }

    /** Revisión 2, hallazgo 3: con la del teléfono del futuro (otro reloj), el cambio nuevo igual le gana. */
    @Test
    fun unCambioLeGanaALoQueReemplazaAunqueVengaDelFuturo() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val manana = ahora + 86_400_000
        local(b, mapOf("jal-d1-0" to swap("Dominadas", ts = manana)))
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first { it.nombre != "Dominadas" }
        m.sustituir("jal-d1-0", sub, fijar = true)
        assertEquals(ValorJson.Numero(manana + 1), m.dia.value.sustituciones["jal-d1-0"]?.get("_ts"))
    }

    /** Revisión 3: con la hora del servidor, los cambios se estampan con el reloj corregido (este teléfono va 3 h adelantado). */
    @Test
    fun conLaHoraDelServidorLosCambiosSeEstampanCorregidos() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val tres = 3 * 3_600_000.0
        b.servidor.cuando("get_exercise_swaps", """{"vivas":{},"borradas":{},"ahora":${(ahora - tres).toLong()}}""")
        val m = b.modelo()
        m.sincronizarSustituciones()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        assertEquals(ValorJson.Numero(ahora - tres), m.dia.value.sustituciones["jal-d1-0"]?.get("_ts"))
        // Otro arranque, todavía sin leer el servidor, recuerda el desfase (y queda un ms arriba de la lápida de deshacer).
        val otro = b.modelo()
        otro.revertirSustitucion("jal-d1-0")
        otro.sustituir("jal-d1-0", sub, fijar = false)
        assertEquals(ValorJson.Numero(ahora - tres + 1), otro.dia.value.sustituciones["jal-d1-0"]?.get("_ts"))
    }

    /** Revisión 3, hallazgo 2: deshacer una que venía un poco adelantada y volver a elegir: la nueva supera a la lápida. */
    @Test
    fun deshacerYVolverAElegirLaNuevaSuperaALaLapida() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Dominadas", ts = ahora + 240_000)))
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first { it.nombre != "Dominadas" }
        m.revertirSustitucion("jal-d1-0")
        m.sustituir("jal-d1-0", sub, fijar = true)
        val ts = SustitucionesServidor.ts(m.dia.value.sustituciones["jal-d1-0"])
        assertTrue(ts > ahora + 240_000, "quedó ${ts - ahora} ms: el servidor la ignoraba contra la lápida")
    }

    /** Revisión 3, hallazgo 1, en el modelo: la copia propia del futuro no vuelve a subirse sobre lo que cambió otro teléfono. */
    @Test
    fun unaCopiaPropiaDelFuturoNoPisaLoQueCambioOtroTelefono() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val futura = swap("Dominadas", ts = ahora + 3 * 3_600_000)
        local(b, mapOf("jal-d1-0" to futura))
        b.disco.guardar(SustitucionesServidor.archivoEncoladas("rut-prueba"), ValorJson.objeto("jal-d1-0" to futura))
        val delOtro = swap("Remo en T", ts = ahora - 600_000)
        b.servidor.cuando("get_exercise_swaps", """{"vivas":{"jal-d1-0":${delOtro.serializar()}},"borradas":{},"ahora":${ahora.toLong()}}""")
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertEquals("Remo en T", m.dia.value.sustituciones["jal-d1-0"]?.get("current")?.get("nombre")?.comoTexto)
        assertTrue(claves(b).isEmpty(), "volvió a subir la del futuro: ${claves(b)}")
    }

    /** El servidor recortó una hora del futuro: la misma elección baja con la hora corregida y no se vuelve a subir. */
    @Test
    fun laHoraCorregidaPorElServidorSeAdoptaSinVolverASubir() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Dominadas", ts = ahora + 86_400_000)))
        b.servidor.cuando("get_exercise_swaps", json(vivas = mapOf("jal-d1-0" to swap("Dominadas", ts = ahora + 300_000))))
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertEquals(ValorJson.Numero(ahora + 300_000), m.dia.value.sustituciones["jal-d1-0"]?.get("_ts"))
        assertTrue(claves(b).isEmpty(), "volvió a subir la del futuro: ${claves(b)}")
    }

    /**
     * Revisión 2, hallazgo 2: lo que la app vieja sacó (por ejemplo, porque la podó) sale como borrado con la hora de lo
     * que había, no con la de ahora: no saca lo que el cliente fijó después en otro teléfono.
     */
    @Test
    fun loQueSacoLaAppViejaSeBorraConLaHoraDeLoQueHabia() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.disco.guardar(
            SustitucionesServidor.archivoEncoladas("rut-prueba"),
            ValorJson.objeto("jal-d1-0" to swap("Remo en T", ts = 100.0, fijado = false)),
        )
        local(b, emptyMap())
        b.servidor.sinRed("get_exercise_swaps")
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        val op = b.cola.operaciones().single()
        assertEquals("swap_ej_del", op.kind)
        assertEquals(ValorJson.Numero(100.0), op.payload["ts"])
    }

    @Test
    fun conLaTablaLaColaGuardaYBorra() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("save_exercise_swap", "true")
        b.servidor.cuando("delete_exercise_swap", "true")
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.encoladoSustituciones?.join()
        b.cola.drenar()
        val guardada = b.servidor.llamadas("save_exercise_swap").first()
        assertEquals(ValorJson.Texto("rut-prueba"), guardada["p_rutina_id"])
        assertEquals(ValorJson.Texto("jal-d1-0"), guardada["p_ex_id"])
        assertEquals(sub.nombre, guardada["p_swap"]?.get("current")?.get("nombre")?.comoTexto)
        assertEquals(ValorJson.Booleano(true), guardada["p_swap"]?.get("fijado"))
        assertEquals(ValorJson.Numero(ahora), guardada["p_swap"]?.get("_ts"))
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        b.cola.drenar()
        val borrada = b.servidor.llamadas("delete_exercise_swap").first()
        assertEquals(ValorJson.Texto("jal-d1-0"), borrada["p_ex_id"])
        assertEquals(ValorJson.Numero(ahora), borrada["p_ts"])
        assertTrue(b.cola.operaciones().isEmpty() && b.cola.fallidos().isEmpty())
    }

    @Test
    fun loQueSigueEnLaColaNoLoPisaElServidor() = enUnHilo { alcance ->
        val b = Banco(alcance) // la cola no manda nada: queda pendiente
        local(b, mapOf("rem-d1-1" to swap("Remo en T", ts = 1.0)))
        b.servidor.cuando("get_exercise_swaps", json(vivas = mapOf("rem-d1-1" to swap("Remo en T", ts = 1.0))))
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.revertirSustitucion("rem-d1-1")
        m.sincronizarSustituciones()
        m.encoladoSustituciones?.join()
        assertEquals(listOf("jal-d1-0"), m.dia.value.sustituciones.keys.sorted(), "la nueva queda y la revertida no vuelve")
        val ops = b.cola.operaciones()
        assertEquals(listOf("swap_ej_rut-prueba_jal-d1-0", "swap_ej_rut-prueba_rem-d1-1"), ops.mapNotNull { it.dedupeKey }.sorted())
        assertEquals(ValorJson.Numero(1.0), ops.first { it.kind == "swap_ej_del" }.payload["ts"], "no se reencoló con otra hora")
    }

    @Test
    fun loQueSeTocaMientrasSeEsperaNoLoPisaLaRespuesta() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("save_exercise_swap", "true")
        val vacio = json()
        b.servidor.regla("get_exercise_swaps") {
            demora(200)
            200 to vacio // salió antes de que se guardara la nueva
        }
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        val sync = async { m.sincronizarSustituciones() }
        delay(30)
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.encoladoSustituciones?.join()
        b.cola.drenar() // ya se guardó: la cola no la tiene
        sync.await()
        assertEquals(sub.nombre, m.dia.value.sustituciones["jal-d1-0"]?.get("current")?.get("nombre")?.comoTexto)
        assertNotNull(enDisco(b)?.get("jal-d1-0"))
        m.encoladoSustituciones?.join()
        assertEquals(1, b.servidor.llamadas("save_exercise_swap").size, "no se volvió a mandar")
    }

    /** Hallazgo 4: la op estaba en la cola al empezar y se mandó mientras se esperaba la respuesta (que salió antes). */
    @Test
    fun unaOpEncoladaAntesDeLeerQueSaleEnElMedioNoSePierde() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        b.servidor.cuando("save_exercise_swap", "true")
        val vacio = json()
        b.servidor.regla("get_exercise_swaps") {
            demora(200)
            200 to vacio
        }
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.encoladoSustituciones?.join()
        assertEquals(1, b.cola.operaciones().size)
        val sync = async { m.sincronizarSustituciones() }
        delay(60)
        b.cola.drenar()
        sync.await()
        assertEquals(sub.nombre, m.dia.value.sustituciones["jal-d1-0"]?.get("current")?.get("nombre")?.comoTexto)
        m.encoladoSustituciones?.join()
        assertTrue(b.cola.operaciones().isEmpty())
        assertEquals(1, b.servidor.llamadas("save_exercise_swap").size)
    }

    /** La app escribió la sustitución en el archivo y se cerró antes de pasarla a la cola: al volver a abrir se encola. */
    @Test
    fun loQueNoLlegoALaColaAntesDeCerrarseSeEncolaAlVolverAAbrir() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.disco.guardar(SustitucionesServidor.archivoEncoladas("rut-prueba"), ValorJson.objeto("rem-d1-1" to swap("Remo en T", ts = 1.0)))
        local(b, mapOf("rem-d1-1" to swap("Remo en T", ts = 1.0), "jal-d1-0" to swap("Dominadas", ts = 2.0)))
        b.servidor.sinRed("get_exercise_swaps")
        val m = b.modelo()
        m.cargar()
        m.encoladoSustituciones?.join()
        assertEquals(listOf("swap_ej_rut-prueba_jal-d1-0"), claves(b))
        val anotadas = (b.disco.leer(SustitucionesServidor.archivoEncoladas("rut-prueba")) as? JsonObject)?.keys?.sorted()
        assertEquals(listOf("jal-d1-0", "rem-d1-1"), anotadas, "queda anotado que ya está en la cola")
    }

    @Test
    fun loQueLlegaDelServidorNoVuelveALaCola() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando(
            "get_exercise_swaps",
            json(vivas = mapOf("jal-d1-0" to swap("Dominadas", ts = 1.0), "pre-d2-0" to swap("Press inclinado", "d2", ts = 1.0))),
        )
        val m = b.modelo()
        m.sincronizarSustituciones()
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        val ops = b.cola.operaciones()
        assertEquals(listOf("swap_ej_del"), ops.map { it.kind }, "sale solo lo que hizo el cliente, no lo que bajó: ${ops.map { it.dedupeKey }}")
        assertEquals(ValorJson.Texto("jal-d1-0"), ops.first().payload["exId"])
    }

    @Test
    fun siCambiaLaRutinaEnElMedioLaRespuestaNoSeUsa() = enUnHilo { alcance ->
        val b = Banco(alcance)
        val respuesta = json(vivas = mapOf("jal-d1-0" to swap("Dominadas", ts = 1.0)))
        b.servidor.regla("get_exercise_swaps") {
            demora(150)
            200 to respuesta
        }
        val m = b.modelo()
        val sync = async { m.sincronizarSustituciones() }
        delay(30)
        val fila = filaRutina().replace(""""id":"rut-prueba"""", """"id":"rut-otra"""")
        m.reemplazarRutina(RutinaActiva.desde(ValorJson.parsear(fila).aJson()))
        sync.await()
        assertTrue(m.dia.value.sustituciones.isEmpty())
        assertNull(b.disco.leer(ModeloEntreno.Archivo.sustituciones("rut-otra")))
    }
}

/** Hallazgo 5: antes de SER-14 una sustitución no tocaba la red; sus ops no muestran avisos (las demás sí). */
class SustitucionesSilenciosasTest {
    private val sinRed: ResultadoOp = ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.RED, 0, mensaje = "sin red")))

    @Test
    fun sinRedUnaSustitucionSolaNoAvisaYConUnaSerieSi() = enUnHilo { alcance ->
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { sinRed }
        o.observar({ estados += it }, { })
        o.encolar("swap_ej", ValorJson.objeto(), "swap_ej_R_a")
        o.drenar()
        assertFalse(EstadoGuardado.SIN_CONEXION in estados, "$estados")
        o.encolar("carga", ValorJson.objeto(), "k1")
        o.drenar()
        assertTrue(EstadoGuardado.SIN_CONEXION in estados)
    }

    @Test
    fun lentaNoMuestraGuardando() = enUnHilo { alcance ->
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) {
            delay(1100)
            ResultadoOp.Respuesta(Resultado.Ok(ValorJson.Booleano(true)))
        }
        o.observar({ estados += it }, { })
        o.encolar("swap_ej_del", ValorJson.objeto(), "swap_ej_R_a")
        o.drenar()
        assertFalse(EstadoGuardado.GUARDANDO in estados, "$estados")
    }

    /** Revisión 2, hallazgo 1: una serie que tarda y se guarda, y una sustitución que falla sin red: no queda "Guardando…". */
    @Test
    fun unaSerieGuardadaYUnaSustitucionSinRedNoDejanGuardando() = enUnHilo { alcance ->
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) { op ->
            if (op.kind == "carga") {
                delay(1100)
                ResultadoOp.Respuesta(Resultado.Ok(ValorJson.Texto("row-id")))
            } else {
                sinRed
            }
        }
        o.observar({ estados += it }, { })
        o.encolar("carga", ValorJson.objeto(), "k1")
        o.encolar("swap_ej", ValorJson.objeto(), "swap_ej_R_a")
        o.drenar()
        // Con la falla, la pasada no cerraba nada: quedaba el "Guardando…" (si llegó a salir) o ningún aviso.
        assertEquals(EstadoGuardado.QUIETO, estados.lastOrNull(), "quedó colgado: $estados")
    }

    @Test
    fun abandonadaNoAvisaPerdidoPeroQuedaEnFallidos() = enUnHilo { alcance ->
        val estados = Collections.synchronizedList(mutableListOf<EstadoGuardado>())
        val o = Outbox(archivo = null, reintentoAutomatico = false, alcance = alcance) {
            ResultadoOp.Respuesta(Resultado.Falla(ErrorRpc(ErrorRpc.Clase.PERMANENTE, 400, "22023", "inválida")))
        }
        o.observar({ estados += it }, { })
        o.encolar("swap_ej", ValorJson.objeto(), "swap_ej_R_a")
        repeat(12) { if (o.operaciones().isNotEmpty()) o.drenar() }
        assertFalse(EstadoGuardado.PERDIDO in estados, "$estados")
        assertEquals(1, o.fallidos().size)
    }
}
