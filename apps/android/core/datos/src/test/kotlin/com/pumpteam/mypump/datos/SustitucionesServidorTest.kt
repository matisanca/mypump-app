package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.RutinaActiva
import com.pumpteam.mypump.modelos.ValorJson
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de SustitucionesServidorTests.swift. SER-14: las sustituciones de ejercicio también en el servidor
// (`nativa_003`). Lo que importa: que nada de lo que hoy funciona cambie si la tabla no está (PGRST202), sin red o con el
// token caído; y que con la tabla lo del teléfono suba una vez y después mande lo del servidor, sin perder lo que todavía
// está en la cola ni lo que se tocó mientras tanto.

private val X: ValorJson = ValorJson.objeto(
    "current" to ValorJson.objeto("nombre" to ValorJson.Texto("Dominadas")), "fijado" to ValorJson.Booleano(true), "semana" to ValorJson.Numero(5.0),
)
private val Y: ValorJson = ValorJson.objeto(
    "current" to ValorJson.objeto("nombre" to ValorJson.Texto("Remo en T")), "fijado" to ValorJson.Booleano(false), "semana" to ValorJson.Numero(5.0),
)

class SustitucionesServidorReglasTest {
    @Test
    fun lasOpsSalenDeLaDiferencia() {
        val ops = SustitucionesServidor.operaciones(
            mapOf("a" to X, "b" to X, "c" to X), mapOf("a" to X, "b" to Y, "d" to Y, "e" to ValorJson.Texto("rara")), "R",
        )
        assertEquals(listOf("swap_ej", "swap_ej_del", "swap_ej"), ops.map { it.kind }, "b cambia, c se va, d entra; a igual y e no se sube")
        assertEquals(listOf("b", "c", "d"), ops.map { it.exId })
        assertEquals(listOf("swap_ej_R_b", "swap_ej_R_c", "swap_ej_R_d"), ops.map { it.clave })
        assertEquals(ValorJson.objeto("rutinaId" to ValorJson.Texto("R"), "exId" to ValorJson.Texto("b"), "swap" to Y), ops[0].payload)
        assertEquals(ValorJson.objeto("rutinaId" to ValorJson.Texto("R"), "exId" to ValorJson.Texto("c")), ops[1].payload)
    }

    @Test
    fun soloSubeLoQueLaBaseAcepta() {
        val r = SustitucionesServidor.subibles(
            mapOf(
                "a" to X, "b" to ValorJson.Lista(emptyList()), "x".repeat(121) to X, "" to X,
                "grande" to ValorJson.objeto("relleno" to ValorJson.Texto("x".repeat(13_000))),
            ),
        )
        assertEquals(mapOf("a" to X), r)
        val muchas = (0..300).associate { "e$it" to X }
        assertNull(SustitucionesServidor.subibles(muchas), "con más de 300 no sube nada (quedan en el teléfono)")
    }

    @Test
    fun combinarLaColaYLoTocadoGananAlServidor() {
        fun op(id: String, kind: String, rutina: String, ex: String, swap: ValorJson?) = Operacion(
            id, kind,
            ValorJson.Objeto(listOfNotNull("rutinaId" to ValorJson.Texto(rutina), "exId" to ValorJson.Texto(ex), swap?.let { "swap" to it }).toMap()),
            "swap_ej_${rutina}_$ex", ts = 0.0,
        )
        val pendientes = mapOf(
            "swap_ej_R_p" to op("1", "swap_ej", "R", "p", Y),
            "swap_ej_R_s" to op("2", "swap_ej_del", "R", "s", null),
            "swap_ej_OTRA_q" to op("3", "swap_ej", "OTRA", "q", Y),
        )
        val r = SustitucionesServidor.combinar(
            servidor = mapOf("s" to X, "t" to X, "u" to X, "malo" to ValorJson.Numero(1.0)),
            local = mapOf("t" to Y, "v" to X, "w" to ValorJson.Texto("nunca subió")),
            pendientes = pendientes, rutinaId = "R", tocadas = setOf("t", "u"),
        )
        assertEquals(
            mapOf("p" to Y, "t" to Y, "w" to ValorJson.Texto("nunca subió")), r,
            "p está en la cola, s se borra en la cola, t y u se tocaron (u se borró), v no está en el servidor ni en la cola",
        )
    }
}

class SustitucionesServidorModeloTest {
    private val noExiste = 404 to """{"code":"PGRST202","message":"Could not find the function"}"""

    /** Una sustitución fijada de esta semana (la poda no la toca). */
    private fun swap(nombre: String, dia: String = "d1"): ValorJson = ValorJson.objeto(
        "original" to ValorJson.objeto("slug" to ValorJson.Nulo, "nombre" to ValorJson.Texto("Original"), "images" to ValorJson.Nulo),
        "current" to ValorJson.objeto(
            "slug" to ValorJson.Nulo, "nombre" to ValorJson.Texto(nombre), "equipment" to ValorJson.Nulo, "images" to ValorJson.Nulo,
        ),
        "fijado" to ValorJson.Booleano(true), "semana" to ValorJson.Numero(5.0), "diaId" to ValorJson.Texto(dia),
    )

    private fun json(m: Map<String, ValorJson>): String = ValorJson.Objeto(m).serializar()

    private fun local(b: Banco, m: Map<String, ValorJson>) {
        b.disco.guardar(ModeloEntreno.Archivo.sustituciones("rut-prueba"), ValorJson.Objeto(m))
    }

    private fun enDisco(b: Banco): Map<String, ValorJson>? =
        (b.disco.leer(ModeloEntreno.Archivo.sustituciones("rut-prueba")) as? JsonObject)?.mapValues { ValorJson.desde(it.value) }

    private fun estado(b: Banco) = SustitucionesServidor.Estado.leer(b.disco, "rut-prueba")

    private fun yaSubidas(b: Banco, reemplazar: Boolean = false) {
        b.disco.guardar(SustitucionesServidor.Estado.archivo("rut-prueba"), SustitucionesServidor.Estado(true, reemplazar).aValor())
    }

    @Test
    fun laPrimeraVezSubeLoDelTelefonoYDespuesLee() = enUnHilo { alcance ->
        val b = Banco(alcance)
        local(b, mapOf("jal-d1-0" to swap("Dominadas")))
        // Otro teléfono ya había subido la del press.
        b.servidor.cuando("import_exercise_swaps", json(mapOf("jal-d1-0" to swap("Dominadas"), "pre-d2-0" to swap("Press inclinado", "d2"))))
        val m = b.modelo()
        m.cargar()
        val subida = b.servidor.llamadas("import_exercise_swaps")
        assertEquals(1, subida.size)
        assertEquals(ValorJson.objeto("jal-d1-0" to swap("Dominadas")), subida.first()["p_swaps"])
        assertEquals(ValorJson.Booleano(false), subida.first()["p_reemplazar"])
        assertEquals(ValorJson.Texto("rut-prueba"), subida.first()["p_rutina_id"])
        assertEquals(listOf("jal-d1-0", "pre-d2-0"), m.dia.value.sustituciones.keys.sorted(), "la del otro teléfono llegó")
        assertEquals(listOf("jal-d1-0", "pre-d2-0"), enDisco(b)?.keys?.sorted())
        assertEquals(SustitucionesServidor.Estado(subidas = true), estado(b))
        assertTrue(b.cola.operaciones().isEmpty(), "lo que llega del servidor no vuelve a la cola")

        b.servidor.cuando("get_exercise_swaps", json(mapOf("pre-d2-0" to swap("Press inclinado", "d2"))))
        m.sincronizarSustituciones()
        assertEquals(1, b.servidor.llamadas("import_exercise_swaps").size, "subir es una sola vez")
        assertEquals(1, b.servidor.llamadas("get_exercise_swaps").size)
        assertEquals(listOf("pre-d2-0"), m.dia.value.sustituciones.keys.sorted(), "la del jalón se borró en otro teléfono")
        assertFalse(m.efectivo(m.dia.value.ejercicio("jal-d1-0")!!).sustituido)
    }

    @Test
    fun loQueLlegaDelServidorNoVuelveALaCola() = enUnHilo { alcance ->
        val b = Banco(alcance)
        b.servidor.cuando("import_exercise_swaps", json(mapOf("jal-d1-0" to swap("Dominadas"), "pre-d2-0" to swap("Press inclinado", "d2"))))
        val m = b.modelo()
        m.sincronizarSustituciones()
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        val ops = b.cola.operaciones()
        assertEquals(listOf("swap_ej_del"), ops.map { it.kind }, "sale solo lo que hizo el cliente, no lo que bajó: ${ops.map { it.dedupeKey }}")
        assertEquals(ValorJson.Texto("jal-d1-0"), ops.first().payload["exId"])
    }

    /**
     * La app escribió la sustitución en el archivo y se cerró antes de pasarla a la cola: al volver a abrir se encola, y la
     * lectura del servidor (que no la tiene) no la borra.
     */
    @Test
    fun loQueNoLlegoALaColaAntesDeCerrarseSeEncolaAlVolverAAbrir() = enUnHilo { alcance ->
        val b = Banco(alcance)
        yaSubidas(b)
        b.disco.guardar(SustitucionesServidor.archivoEncoladas("rut-prueba"), ValorJson.objeto("rem-d1-1" to swap("Remo en T")))
        local(b, mapOf("rem-d1-1" to swap("Remo en T"), "jal-d1-0" to swap("Dominadas")))
        b.servidor.cuando("get_exercise_swaps", json(mapOf("rem-d1-1" to swap("Remo en T"))))
        val m = b.modelo()
        m.cargar()
        val ops = b.cola.operaciones()
        assertEquals(listOf("swap_ej_rut-prueba_jal-d1-0"), ops.map { it.dedupeKey })
        assertEquals("swap_ej", ops.first().kind)
        assertEquals(listOf("jal-d1-0", "rem-d1-1"), m.dia.value.sustituciones.keys.sorted(), "la lectura del servidor la borraba")
        m.encoladoSustituciones?.join()
        val anotadas = (b.disco.leer(SustitucionesServidor.archivoEncoladas("rut-prueba")) as? JsonObject)?.keys?.sorted()
        assertEquals(listOf("jal-d1-0", "rem-d1-1"), anotadas, "queda anotado que ya está en la cola")
    }

    @Test
    fun sinLaTablaEnLaBaseQuedaComoHoy() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        local(b, mapOf("jal-d1-0" to swap("Dominadas")))
        b.servidor.cuando("import_exercise_swaps", noExiste.first, noExiste.second)
        b.servidor.cuando("save_exercise_swap", noExiste.first, noExiste.second)
        b.servidor.cuando("delete_exercise_swap", noExiste.first, noExiste.second)
        val m = b.modelo()
        m.cargar()
        assertEquals(mapOf("jal-d1-0" to swap("Dominadas")), m.dia.value.sustituciones)
        assertNull(estado(b), "no se marca como subida: cuando exista la tabla, sube")
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
        assertEquals(emptyMap<String, ValorJson>(), enDisco(b))
        m.sincronizarSustituciones()
        assertEquals(2, b.servidor.llamadas("import_exercise_swaps").size, "se vuelve a intentar subir")
    }

    @Test
    fun sinRedOConElTokenCaidoQuedaLoDelTelefono() = enUnHilo { alcance ->
        for (respuesta in listOf<Pair<Int, String>?>(null, 200 to "null", 200 to "[]")) {
            val b = Banco(alcance)
            yaSubidas(b)
            local(b, mapOf("jal-d1-0" to swap("Dominadas")))
            b.servidor.regla("get_exercise_swaps") { respuesta }
            val m = b.modelo()
            m.sincronizarSustituciones()
            assertEquals(mapOf("jal-d1-0" to swap("Dominadas")), m.dia.value.sustituciones, "con $respuesta")
            assertEquals(mapOf("jal-d1-0" to swap("Dominadas")), enDisco(b))
        }
    }

    @Test
    fun cadaCambioSaleALaColaYGanaElUltimo() = enUnHilo { alcance ->
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
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        val ops = b.cola.operaciones()
        assertTrue(ops.size == 1 && ops.first().kind == "swap_ej_del", "volver al original reemplaza a la de guardar")
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
        m.revertirSustitucion("jal-d1-0")
        m.encoladoSustituciones?.join()
        b.cola.drenar()
        assertEquals(ValorJson.Texto("jal-d1-0"), b.servidor.llamadas("delete_exercise_swap").firstOrNull()?.get("p_ex_id"))
        assertTrue(b.cola.operaciones().isEmpty() && b.cola.fallidos().isEmpty())
    }

    @Test
    fun loQueSigueEnLaColaNoLoPisaElServidor() = enUnHilo { alcance ->
        val b = Banco(alcance) // la cola no manda nada: queda pendiente
        yaSubidas(b)
        local(b, mapOf("rem-d1-1" to swap("Remo en T")))
        b.servidor.cuando("get_exercise_swaps", json(mapOf("rem-d1-1" to swap("Remo en T"))))
        val m = b.modelo()
        val sub = m.sustitutos("jal-d1-0").first()
        m.sustituir("jal-d1-0", sub, fijar = true)
        m.revertirSustitucion("rem-d1-1")
        m.sincronizarSustituciones()
        assertEquals(listOf("jal-d1-0"), m.dia.value.sustituciones.keys.sorted(), "la nueva queda y la revertida no vuelve")
    }

    @Test
    fun loQueSeTocaMientrasSeEsperaNoLoPisaLaRespuesta() = enUnHilo { alcance ->
        val b = Banco(alcance, ejecutar = true)
        yaSubidas(b)
        b.servidor.cuando("save_exercise_swap", "true")
        b.servidor.regla("get_exercise_swaps") {
            demora(200)
            200 to "{}" // salió antes de que se guardara la nueva
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
    }

    @Test
    fun siLaMigracionSeRepitioLoDeLaAppViejaReemplaza() = enUnHilo { alcance ->
        val b = Banco(alcance)
        yaSubidas(b, reemplazar = true)
        local(b, mapOf("jal-d1-0" to swap("Dominadas")))
        b.servidor.cuando("import_exercise_swaps", json(mapOf("jal-d1-0" to swap("Dominadas"))))
        val m = b.modelo()
        m.sincronizarSustituciones()
        assertEquals(ValorJson.Booleano(true), b.servidor.llamadas("import_exercise_swaps").firstOrNull()?.get("p_reemplazar"))
        assertEquals(SustitucionesServidor.Estado(subidas = true, reemplazar = false), estado(b))
        assertTrue(b.servidor.llamadas("get_exercise_swaps").isEmpty())
    }

    @Test
    fun siCambiaLaRutinaEnElMedioLaRespuestaNoSeUsa() = enUnHilo { alcance ->
        val b = Banco(alcance)
        yaSubidas(b)
        val respuesta = json(mapOf("jal-d1-0" to swap("Dominadas")))
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
