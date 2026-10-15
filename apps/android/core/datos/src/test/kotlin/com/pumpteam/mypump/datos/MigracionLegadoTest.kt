package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.io.File
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// La migración del almacenamiento viejo, la parte pura y su ejecución (MigracionLegadoTests.swift). En iOS el
// almacenamiento son los archivos de WebKit leídos con SQLite; en Android lo lee un WebView en `:app`, que necesita un
// teléfono: acá un lector en memoria hace de `localStorage` (las claves, sus valores y una huella que cambia con cada
// escritura). Los formatos salen de la web: `main` y `v1.0.11`, y `v1.0.2` para la cola sin `_id`.

internal const val tokenA = "tokAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"   // 32, como los de sembrar.mjs
internal const val tokenB = "tokBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
internal const val rutinaR1 = "11111111-1111-4111-8111-111111111111"
internal const val rutinaR2 = "22222222-2222-4222-8222-222222222222"
internal const val dietaD = "00000000-0000-4000-8000-000000000d1e"
internal const val sesionS = "6f0c2a8e-5b1d-4c7e-9a3f-2d8e1b7c4a90"

/** 14-oct-2026 12:00 en Buenos Aires. */
internal val ahoraMig: Instant = Instant.ofEpochSecond(1_791_990_000)
internal val ahoraMigMs = ahoraMig.toEpochMilli().toDouble()
internal val baires: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

/** El `localStorage` de la Capacitor: las claves, sus valores y una huella que se mueve con cada escritura. */
class LectorEnMemoria(inicial: Map<String, String> = emptyMap(), var existe: Boolean = true) : LectorLegado {
    private val items = LinkedHashMap(inicial)
    private var version = 0

    @Synchronized fun escribir(nuevos: Map<String, String>, borrar: List<String> = emptyList()) {
        for (k in borrar) items.remove(k)
        items.putAll(nuevos)
        version++
    }

    /** Lo que quedó después de una escritura de vuelta (el `localStorage` entero). */
    @Synchronized fun reemplazar(todo: Map<String, String>) {
        items.clear()
        items.putAll(todo)
        version++
    }

    val claves: Map<String, String> @Synchronized get() = LinkedHashMap(items)

    override fun hay(): Boolean = existe

    @Synchronized override fun huella(): HuellaLegado =
        HuellaLegado(listOf(HuellaLegado.Archivo("Local Storage/leveldb", items.entries.sumOf { (it.key.length + it.value.length).toLong() }, version.toDouble())))

    override suspend fun leer(): LecturaLegado? {
        if (!existe) return null
        val (i, h) = synchronized(this) { LinkedHashMap(items) to huella() }
        return LecturaLegado(i, i.mapValues { FirmaValor.de(it.value) }, h)
    }

    override fun copiarCrudo(destino: File): List<String> {
        destino.mkdirs()
        File(destino, "localstorage.json").writeText(ValorJson.Objeto(claves.mapValues { ValorJson.Texto(it.value) }).serializar())
        return listOf("localstorage.json")
    }
}

internal fun fechaMig(i: Int): String = FechaLegado.sumar("2026-10-14", -(i % 300))

/**
 * Una cola como la de la web: `{_id, kind, payload, dedupeKey, tries, ts}` con dedupeKeys únicas (la web borra la pendiente
 * con la misma al encolar). Los 9 kinds; `carga` y `estado` con y sin `sesionId`.
 */
internal fun colaWeb(n: Int, t0: Double = 1_791_900_000_000.0, conId: Boolean = true): List<ValorJson> {
    val kinds = listOf("carga", "estado", "swap", "swap_del", "habito", "comida", "peso", "checkin", "chat")
    val ops = ArrayList<ValorJson>()
    for (i in 0 until n) {
        val kind = kinds[i % kinds.size]
        val dia = "b2d${1 + i % 3}"
        val sesion: ValorJson = if (i % 2 == 0) texto(sesionS) else ValorJson.Nulo
        val payload: ValorJson
        val dk: String
        when (kind) {
            "carga" -> {
                payload = ValorJson.objeto(
                    "sesionId" to sesion, "diaId" to texto(dia), "semana" to numero(3),
                    "datos" to ValorJson.objeto(
                        "diaId" to texto(dia), "ejercicioId" to texto("press-banca-$dia-$i"), "ejercicioNombre" to texto("Press inclinado 45° — mancuernas"),
                        "serie" to numero(1 + i % 4), "peso" to numero(62.5), "reps" to numero(8), "rir" to numero(0), "notas" to ValorJson.Nulo,
                    ),
                )
                dk = "carga_${dia}_press-banca-$dia-${i}_${i % 4}"
            }
            "estado" -> {
                payload = ValorJson.objeto(
                    "sesionId" to sesion, "semana" to numero(3), "diaId" to texto(dia), "exId" to texto("remo-$dia-$i"),
                    "seriesObjetivo" to numero(3), "status" to texto("completo"), "manual" to ValorJson.Booleano(false),
                )
                dk = "estado_${dia}_remo-$dia-$i"
            }
            "swap" -> {
                payload = ValorJson.objeto(
                    "dietaId" to texto(dietaD), "comidaId" to texto("desayuno"), "optIdx" to numero(i % 4), "foodIdx" to numero(i),
                    "food" to ValorJson.objeto(
                        "name" to texto("Ricota descremada"), "qty" to numero(150), "unit" to texto("g"), "kcal" to numero(207),
                        "_orig" to ValorJson.objeto("name" to texto("Queso untable light"), "qty" to numero(60), "unit" to texto("g")),
                    ),
                )
                dk = "swap_${dietaD}_desayuno_${i % 4}_$i"
            }
            "swap_del" -> {
                payload = ValorJson.objeto("dietaId" to texto(dietaD), "comidaId" to texto("almuerzo"), "optIdx" to numero(0), "foodIdx" to numero(i))
                dk = "swap_${dietaD}_almuerzo_0_$i"
            }
            "habito" -> {
                payload = ValorJson.objeto("fecha" to texto(fechaMig(i)), "campo" to texto("vasos_agua"), "valor" to texto("${i % 12}"))
                dk = "habito|${fechaMig(i)}|vasos_agua"
            }
            "comida" -> {
                payload = ValorJson.objeto(
                    "fecha" to texto(fechaMig(i)), "comidaId" to texto("almuerzo"), "opcion" to texto("Opción B"), "estado" to texto("comido"),
                    "excl" to ValorJson.Lista(listOf(numero(1))),
                )
                dk = "comida|${fechaMig(i)}|almuerzo"
            }
            "peso" -> {
                payload = ValorJson.objeto("fecha" to texto(fechaMig(i)), "valor" to numero(81.4))
                dk = "peso_${fechaMig(i)}"
            }
            "checkin" -> {
                payload = ValorJson.objeto(
                    "fecha" to texto(fechaMig(i)),
                    "datos" to ValorJson.objeto(
                        "energia" to numero(4), "descanso" to numero(3), "hambre" to numero(2), "adherencia" to numero(5),
                        "nota" to texto("Semana dura, dormí poco 😴"),
                    ),
                )
                dk = "checkin_${fechaMig(i)}"
            }
            else -> {
                val contenido = "Mati, ¿cambio el jalón por remo? ñandú $i"
                payload = ValorJson.objeto("contenido" to texto(contenido))
                dk = "chat_${t0.toLong() + i}_${contenido.take(40)}"
            }
        }
        val o = linkedMapOf(
            "kind" to texto(kind), "payload" to payload, "dedupeKey" to texto(dk), "tries" to numero(listOf(0, 0, 1, 3)[i % 4]), "ts" to numero(t0 + i),
        )
        if (conId) o["_id"] = texto("${t0.toLong() + i}_${i + 1}")
        ops += ValorJson.Objeto(o)
    }
    return ops
}

internal fun json(v: ValorJson): String = v.serializar()

internal fun fotoOffline(rutina: String, dias: List<String> = listOf("b2d1", "b2d2", "b2d3"), ts: Double = 1_791_900_000_000.0): String = json(
    ValorJson.objeto(
        "info" to ValorJson.objeto("cliente_id" to texto("test-nativa-android"), "nombre" to texto("Test Nativa"), "perfil" to texto("natural")),
        "rutina" to ValorJson.objeto(
            "id" to texto(rutina), "version" to numero(3), "semana_actual" to numero(3),
            "estructura" to ValorJson.objeto("dias" to ValorJson.Lista(dias.map { ValorJson.objeto("id" to texto(it), "nombre" to texto(it), "bloques" to ValorJson.Lista(emptyList())) })),
        ),
        "dieta" to ValorJson.Nulo, "ts" to numero(ts),
    ),
)

/** Un teléfono con la Capacitor: el `localStorage` viejo, `filesDir` vacío, el token y las preferencias propios. */
class Telefono {
    val raiz: File = carpetaTemporal("legado")
    val lector = LectorEnMemoria()
    val entorno = EntornoLegado(raiz, lector)
    val almacen = TokenEnMemoria()
    val ajustes = PreferenciasEnMemoria()

    fun faseL(cuentaViva: String? = null, momento: Instant = ahoraMig): EjecutorLegado.Resultado =
        runBlocking { EjecutorLegado.faseLocal(entorno, almacen, ajustes, momento, baires, cuentaViva) }

    internal val archivos: ArchivosLegado get() = ArchivosLegado(entorno.carpeta)

    fun disco(t: String = tokenA): Disco = entorno.disco(t)

    /** Las ops del `outbox.json` de la cuenta (como las levanta la cola al iniciar). */
    fun cola(t: String = tokenA): List<Operacion> =
        ((disco(t).leer("outbox.json")?.let(ValorJson::desde))?.get("ops") as? ValorJson.Lista)?.elementos?.mapNotNull { Operacion.desde(it.aJson()) }
            ?: emptyList()
}

class MigracionLegadoTest {
    /**
     * D14: el respaldo de Google restaura el almacenamiento de la app vieja y `files/legado/`, pero no el token de la nativa.
     * Con la misma huella, la Fase L cortaba y el teléfono nuevo pedía el link (hoy la huella cambia por las fechas que
     * Android restaura en 1970). Ahora, sin token guardado, vuelve a adoptar el de la app vieja; si está marcado inválido, no.
     */
    @Test
    fun despuesDeRestaurarUnRespaldoSinTokenVuelveAAdoptarElDeLaAppVieja() {
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(2)))))
        assertTrue(tel.faseL().adoptoToken)
        val cola = tel.cola().map { it.id }
        // El respaldo: lo mismo de antes (misma huella), sin el token de la nativa.
        tel.almacen.guardar(null)
        val r = tel.faseL()
        assertEquals(tokenA, tel.almacen.leer(), "con la misma huella cortaba y el teléfono pedía el link")
        assertTrue(r.adoptoToken)
        assertEquals(cola, tel.cola().map { it.id }, "no duplica la cola")
        // Con el token marcado inválido no se vuelve a adoptar (ni se repite la corrida cada vez).
        tel.almacen.guardar(null)
        tel.ajustes.guardar("mypump_token_invalido", tokenA)
        assertFalse(tel.faseL().corrio)
        assertNull(tel.almacen.leer())
    }

    /**
     * Revisión adversarial del 15-oct, hallazgo 3: la nativa anduvo con OTRA cuenta (B, pegada después de migrar) y B se venció.
     * Con la misma huella volvía a adoptar A (la de la app vieja, que puede ser de otra persona) en silencio.
     */
    @Test
    fun sinTokenYConOtraCuentaDeLaNativaNoVuelveALaDeLaAppVieja() {
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(2)))))
        assertTrue(tel.faseL().adoptoToken)
        assertEquals(JsonLegado.sha256(tokenA), UltimaCuenta.hash(tel.ajustes))
        // El cliente pegó otro link en la nativa (ModeloApp anota la cuenta), y ese link se venció.
        UltimaCuenta.anotar(tokenB, tel.ajustes)
        tel.almacen.guardar(null)
        tel.ajustes.guardar("mypump_token_invalido", tokenB)
        val r = tel.faseL()
        assertTrue(!r.adoptoToken && tel.almacen.leer() == null, "volvió a entrar a la cuenta de la app vieja")
        // Lo mismo si la Capacitor cambió (otra huella): la rama de la primera adopción tampoco entra.
        tel.lector.escribir(mapOf("mypump_tipo_dia" to "descanso"))
        val r2 = tel.faseL()
        assertTrue(r2.corrio && !r2.adoptoToken && tel.almacen.leer() == null)
    }

    /** Hallazgo 5: una repetición de la Fase L no vuelve a poner en la cola una foto que ya pasó (y quizás se subió). */
    @Test
    fun unaRepeticionNoVuelveAEncolarFotosYaImportadas() {
        val tel = Telefono()
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA,
                "mypump_fotoq_$tokenA" to """{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-13","dataUrl":"data:image/jpeg;base64,AAAA","intentos":0}}""",
            ),
        )
        assertTrue(tel.faseL().adoptoToken)
        assertNotNull(tel.disco().leer(FotoPendiente.ARCHIVO))
        tel.disco().archivo(FotoPendiente.ARCHIVO).delete()   // la nativa la subió
        tel.almacen.guardar(null)                               // restauración sin el token
        assertTrue(tel.faseL().adoptoToken)
        assertNull(tel.disco().leer(FotoPendiente.ARCHIVO), "la foto ya subida volvió a la cola")
        assertNotNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_fotoq_$tokenA"), "la cola de fotos de la Capacitor tiene que salir igual")
    }

    @Test
    fun quinientasOpsDeLosNueveKinds() {
        val tel = Telefono()
        val ops = colaWeb(500)
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(ops)), "mypump_offline_$tokenA" to fotoOffline(rutinaR1)))
        val r = tel.faseL()
        assertTrue(r.corrio && r.adoptoToken && r.tokenVigente == tokenA)
        assertEquals(tokenA, tel.almacen.leer())
        val plan = r.plan!!
        assertEquals(9, plan.conteos.opsPorKind.size)
        assertEquals(500, plan.conteos.opsPorKind.values.sum())
        assertTrue(plan.conteos.opsPorKind["carga"] == 56 && plan.conteos.opsPorKind["chat"] == 55)
        // Con sesión (o que no son de Entreno) van a la cola; las sin sesión esperan la validación de la Fase R.
        val sinSesion = ops.filter { o -> o["kind"]?.comoTexto in listOf("carga", "estado") && o["payload"]?.get("sesionId") == ValorJson.Nulo }
        assertTrue(r.porValidar == sinSesion.size && r.porValidar == 56)
        assertEquals(500 - 56, r.aLaCola)
        val cola = tel.cola()
        assertEquals(444, cola.size)
        assertEquals(9, cola.map { it.kind }.toSet().size)
        assertTrue(cola.all { it.id.startsWith("legado-") })
        // El payload llega tal cual (el ejecutor de la cola lo manda igual que la web).
        val primera = cola.first { it.kind == "carga" }
        assertEquals("Press inclinado 45° — mancuernas", primera.payload["datos"]?.get("ejercicioNombre")?.comoTexto)
        assertEquals(ValorJson.Numero(0.0), primera.payload["datos"]?.get("rir"))
        val pendientes = tel.archivos.pendientes
        assertTrue(pendientes.size == 1 && pendientes[0].propia && pendientes[0].ops.size == 56 && pendientes[0].rutinaFoto == rutinaR1)
        assertEquals(500, tel.archivos.libro.size)
        // La copia cruda, antes de tocar nada.
        val estado = tel.archivos.estado!!
        val copia = File(tel.entorno.crudo, estado.copias.first())
        assertTrue(File(copia, "localstorage.json").isFile && File(copia, "manifiesto.json").isFile)
        assertTrue(estado.faseRPendiente && estado.escritura?.borrar?.get("mypump_outbox_$tokenA") != null)
        // Y la foto offline sembró la caché de la cuenta, en el formato nativo.
        val offline = ModeloApp.CopiaOffline.desde(tel.disco().leer(ModeloApp.ARCHIVO_COPIA))!!
        assertTrue(offline.rutina?.get("id")?.comoTexto == rutinaR1 && offline.info["cliente_id"]?.comoTexto == "test-nativa-android")
    }

    @Test
    fun colaSinIdComoLaV102() {
        val tel = Telefono()
        val ops = colaWeb(30, conId = false)
        assertTrue(ops.all { it["_id"] == null })
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(ops))))
        val r = tel.faseL()
        assertEquals(30, r.aLaCola + r.porValidar)
        val ids = tel.cola().map { it.id }
        assertEquals(ids.size, ids.toSet().size)
        // El id sale del contenido: otra lectura de los mismos datos da los mismos ids.
        val otra = MigracionLegado.planificar(tel.lector.claves, ahora = ahoraMig, zona = baires)
        val vigente = otra.colas.first { it.tipo == ColaLegada.Tipo.VIGENTE }
        assertEquals(ids.toSet(), vigente.ops.filter { !it.necesitaValidar }.map { it.operacion.id }.toSet())
    }

    @Test
    fun dosOpsIdenticasSinIdNoSeFunden() {
        // Sin `_id` dos entradas pueden ser idénticas; el índice entre idénticas las separa.
        val op = ValorJson.objeto(
            "kind" to texto("peso"), "payload" to ValorJson.objeto("fecha" to texto("2026-10-13"), "valor" to numero(80)),
            "dedupeKey" to ValorJson.Nulo, "tries" to numero(0), "ts" to numero(1),
        )
        val plan = MigracionLegado.planificar(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(listOf(op, op)))), ahora = ahoraMig)
        val ids = plan.colas.first().ops.map { it.idLibro }
        assertTrue(ids.size == 2 && ids.toSet().size == 2)
    }

    @Test
    fun laColaAnonNuncaSeEjecuta() {
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(4))), "mypump_outbox_anon" to json(ValorJson.Lista(colaWeb(7, t0 = 5.0)))))
        val r = tel.faseL()
        assertEquals(7, r.anon)
        assertEquals(4, tel.cola().size + (tel.archivos.pendientes.firstOrNull()?.ops?.size ?: 0))
        assertEquals(7, tel.archivos.libro.values.count { it.destino == EntradaLibro.Destino.ANON })
        assertFalse(tel.archivos.pendientes.any { it.clave == "mypump_outbox_anon" })
        // Y no se borra de la Capacitor: no se tomó.
        assertNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_outbox_anon"))
    }

    @Test
    fun lasClavesDemoNoSeAplican() {
        val tel = Telefono()
        val swaps = """{"jalon-d1-0":{"original":{"slug":"a","nombre":"A"},"current":{"slug":"b","nombre":"B"},"fijado":true,"semana":1,"diaId":"d1"}}"""
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA,
                "mypump_exercise_swaps_demo" to swaps, "mypump_food_swaps_demo" to """{"swap_demo_x_0_0":{"original":null,"current":{"name":"Z"}}}""",
                "mypump_swaps_migrados_demo" to "1", "mypump_dia_visualizado_demo" to "d2",
                "mypump_exercise_swaps_$rutinaR1" to swaps, "mypump_dia_visualizado_$rutinaR1" to "b2d2",
            ),
        )
        val r = tel.faseL()
        val plan = r.plan!!
        assertEquals(4, plan.conteos.demo)
        assertEquals(listOf(rutinaR1), plan.sustituciones.keys.sorted())
        assertNull(tel.ajustes.leer("mypump_dia_visualizado_demo"))
        assertEquals("b2d2", tel.ajustes.leer("mypump_dia_visualizado_$rutinaR1"))
        assertFalse(tel.disco().archivo(SustitucionEjercicio.archivo("demo")).exists())
        assertFalse(tel.disco().archivo("swaps_demo.json").exists())
        assertEquals(1, (tel.disco().leer(SustitucionEjercicio.archivo(rutinaR1))?.let(ValorJson::desde) as? ValorJson.Objeto)?.campos?.size)
    }

    /**
     * SER-14: si el cliente vuelve a la Capacitor, solo lo que cambió AHÍ desde la corrida anterior pisa lo del teléfono
     * (con la hora de la corrida, para que gane también en el servidor) y lo que sacó ahí se saca; lo hecho en la nativa
     * queda. Antes se pisaba todo con lo de la app vieja.
     */
    @Test
    fun laVueltaALaAppViejaSoloAplicaLoQueSeCambioAhi() {
        val tel = Telefono()
        fun entrada(n: String) = """{"original":{"slug":"a","nombre":"A"},"current":{"slug":"b","nombre":"$n"},"fijado":true,"semana":1,"diaId":"d1"}"""
        val clave = "mypump_exercise_swaps_$rutinaR1"
        tel.lector.escribir(mapOf("mypump_token" to tokenA, clave to """{"jalon-d1-0":${entrada("B")}}"""))
        tel.faseL()
        val nombre = SustitucionEjercicio.archivo(rutinaR1)
        val disco = tel.disco()
        fun mapa(n: String) = (disco.leer(n) as? JsonObject)?.mapValues { ValorJson.desde(it.value) }
        val nativa = LinkedHashMap(mapa(nombre)!!)
        assertEquals("B", nativa["jalon-d1-0"]?.get("current")?.get("nombre")?.comoTexto)
        assertNull(nativa["jalon-d1-0"]?.get("_ts"))
        assertFalse(disco.archivo(SustitucionesServidor.archivoEncoladas(rutinaR1)).exists())
        // En la nativa el cliente sustituye otro ejercicio.
        val propia = ValorJson.objeto(
            "current" to ValorJson.objeto("nombre" to ValorJson.Texto("Nativa")), "fijado" to ValorJson.Booleano(true), "_ts" to ValorJson.Numero(500.0),
        )
        nativa["x-d1-1"] = propia
        disco.guardar(nombre, ValorJson.Objeto(nativa))
        // Vuelve a la Capacitor: cambia la del jalón y agrega otra.
        tel.lector.escribir(mapOf(clave to """{"jalon-d1-0":${entrada("C")},"nuevo-d2-0":${entrada("N")}}"""))
        val momento = ahoraMig.plusSeconds(3600)
        val r = tel.faseL(momento = momento)
        assertTrue(r.repeticion)
        val despues = mapa(nombre)!!
        assertEquals("C", despues["jalon-d1-0"]?.get("current")?.get("nombre")?.comoTexto)
        assertEquals(ValorJson.Numero(momento.toEpochMilli().toDouble()), despues["jalon-d1-0"]?.get("_ts"))
        assertEquals("N", despues["nuevo-d2-0"]?.get("current")?.get("nombre")?.comoTexto)
        assertEquals(propia, despues["x-d1-1"], "lo hecho en la nativa quedó")
        // Lo que había quedó anotado como ya subido: al abrir, lo cambiado sale como guardado.
        assertEquals(nativa, mapa(SustitucionesServidor.archivoEncoladas(rutinaR1)))
        // Otra vuelta: saca la nueva en la Capacitor y no toca la del jalón.
        tel.lector.escribir(mapOf(clave to """{"jalon-d1-0":${entrada("C")}}"""))
        tel.faseL(momento = momento.plusSeconds(3600))
        val otra = mapa(nombre)!!
        assertNull(otra["nuevo-d2-0"], "lo que sacó en la app vieja se sacó")
        assertEquals(despues["jalon-d1-0"], otra["jalon-d1-0"], "lo que no cambió ahí no se toca (ni su hora)")
        assertEquals(propia, otra["x-d1-1"])
    }

    @Test
    fun elTokenMarcadoInvalidoNoSeUsa() {
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_token_invalido" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(3)))))
        val r = tel.faseL()
        assertTrue(!r.adoptoToken && r.tokenVigente == null && tel.almacen.leer() == null)
        assertEquals(true, r.plan?.tokenDescartado)
        // Su cola no se pierde ni se ejecuta: queda estacionada hasta saber de quién es.
        assertTrue(r.estacionadas == 3 && tel.cola().isEmpty())
        assertEquals(tokenA, tel.ajustes.leer("mypump_token_invalido"))
        // Lo mismo si el que la nativa tiene marcado es el que dejó la Capacitor.
        val plan = MigracionLegado.planificar(mapOf("mypump_token" to tokenB), ahora = ahoraMig, contexto = ContextoMigracion(tokenInvalidoNativo = tokenB))
        assertTrue(plan.tokenVigente == null && plan.tokenDescartado)
    }

    @Test
    fun unicodeNulYUnMegaByte() {
        val tel = Telefono()
        val grande = "x".repeat(1024 * 1024)
        val raro = "valor con \u0000 nulo, emoji 😀, acento á y \u0000\u0000 al final\u0000"
        tel.lector.escribir(mapOf("mypump_unicode_∂ñ😀" to raro, "mypump_valor_grande" to grande, "mypump_token" to tokenA))
        val lectura = runBlocking { tel.lector.leer() }!!
        assertEquals(FirmaValor.de(raro), lectura.firmas["mypump_unicode_∂ñ😀"])
        // Una clave desconocida se cuenta, no se pierde (queda en la copia cruda) y no rompe nada.
        val r = tel.faseL()
        assertEquals(2, r.plan?.conteos?.desconocidas)
        assertEquals(1024 * 1024 + raro.length + tokenA.length, r.plan?.conteos?.unidadesUTF16)
        val copia = File(File(tel.entorno.crudo, tel.archivos.estado!!.copias.first()), "localstorage.json").readText()
        assertTrue(copia.contains("mypump_unicode_∂ñ😀"))
    }

    @Test
    fun sesionEnCursoVigenteYVencida() {
        val tel = Telefono()
        val hace1h = ahoraMigMs - 3_600_000
        val hace7h = ahoraMigMs - 7 * 3_600_000
        val p = "mypump_sesion_${tokenA}_"
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA,
                p + "b2d1" to sesionS, p + "b2d1_semana" to "3", p + "b2d1_start" to hace1h.toLong().toString(),
                p + "b2d2" to "otra", p + "b2d2_semana" to "3", p + "b2d2_start" to hace7h.toLong().toString(),
                p + "b2d3" to "cerrada", p + "b2d3_semana" to "3", p + "b2d3_start" to hace1h.toLong().toString(), p + "b2d3_finalizada" to "1",
                "mypump_rest_$tokenA" to """{"endsAt":${ahoraMigMs.toLong() + 30_000},"target":90,"autoCloseAt":${ahoraMigMs.toLong() + 32_000}}""",
                "mypump_dia_visualizado_$rutinaR1" to "b2d3",
            ),
        )
        val r = tel.faseL()
        assertTrue(r.plan?.conteos?.sesionesVigentes == 1 && r.plan?.conteos?.sesionesVencidas == 2)
        val e = EntrenoLegado.desde(tel.disco().leer(EntrenoLegado.ARCHIVO)?.let(ValorJson::desde))!!
        assertEquals(listOf("b2d1"), e.sesiones.keys.sorted())
        assertEquals(SesionLegada(sesionS, 3, hace1h, false), e.sesiones["b2d1"])
        assertEquals(90.0, e.descanso?.target)
        // Los cachés de sesión se borran de la Capacitor en la escritura de vuelta (todos, vigentes o no).
        assertEquals(10, tel.archivos.estado?.escritura?.borrar?.keys?.count { it.startsWith("mypump_sesion_") })

        // Y lo lee el modelo de Entreno (en iOS no: el lector espera otra forma y la sesión se pierde).
        val l = LegadoEntreno.leer(tel.disco(), tokenA, rutinaR1)!!
        assertEquals(listOf(LegadoEntreno.SesionDia("b2d1", sesionS, 3, hace1h, false)), l.sesiones)
        assertEquals("b2d3", l.diaVisualizado)
        assertEquals(90.0, l.descanso?.target)

        // Un descanso que ya terminó no se trae.
        val viejo = MigracionLegado.planificar(mapOf("mypump_token" to tokenA, "mypump_rest_$tokenA" to """{"endsAt":1,"target":90,"autoCloseAt":2}"""), ahora = ahoraMig)
        assertTrue(viejo.entreno?.descanso == null && !viejo.conteos.descansoVigente)
    }

    @Test
    fun temaClaroNoEsUnaEleccionOscuroSi() {
        assertNull(MigracionLegado.planificar(mapOf("mypump-theme" to "light"), ahora = ahoraMig).preferencias["mypump-theme"])
        assertEquals("dark", MigracionLegado.planificar(mapOf("mypump-theme" to "dark"), ahora = ahoraMig).preferencias["mypump-theme"])

        val tel = Telefono()
        tel.lector.escribir(
            mapOf(
                "mypump-theme" to "dark", "mypump_tipo_dia" to "descanso", "mypump_notif_prefs" to """{"check":{"on":false,"hora":9,"min":30}}""",
                "mypump_notif_pedido" to "1", "mypump_onboarding_v1" to "1", "mypump_health_connected" to "1",
                "mypump_health_backfill_off" to """{"off":20,"alcance":60}""", "mypump_health_last_sync" to "2026-10-13T22:00:00.000Z",
                "mypump_health_diag" to """{"x":1}""",
            ),
        )
        tel.ajustes.guardar("mypump_tipo_dia", "entreno")   // la nativa ya tenía uno: gana el suyo
        tel.faseL()
        assertEquals("dark", tel.ajustes.leer("mypump-theme"))
        assertEquals("entreno", tel.ajustes.leer("mypump_tipo_dia"))
        assertEquals("""{"check":{"on":false,"hora":9,"min":30}}""", tel.ajustes.leer("mypump_notif_prefs"))
        assertTrue(tel.ajustes.leer("mypump_notif_pedido") == "1" && tel.ajustes.leer("mypump_onboarding_v1") == "1")
        assertEquals("1", tel.ajustes.leer(ClaveSalud.CONECTADO))
        assertEquals("""{"off":20,"alcance":60}""", tel.ajustes.leer(ClaveSalud.CURSOR))
        assertEquals("2026-10-13T22:00:00.000Z", tel.ajustes.leer(ClaveSalud.ULTIMA_SYNC))
        assertNull(tel.ajustes.leer(ClaveSalud.DIAG))
    }

    @Test
    fun dosCorridasDanLoMismo() {
        val tel = Telefono()
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(120))),
                "mypump_outbox_$tokenB" to json(ValorJson.Lista(colaWeb(5, t0 = 9.0))), "mypump_outbox_anon" to json(ValorJson.Lista(colaWeb(2, t0 = 7.0))),
                "mypump_tipo_dia" to "entreno",
            ),
        )
        val r1 = tel.faseL()
        val cola1 = tel.cola()
        val libro1 = tel.archivos.libro
        val pendientes1 = tel.archivos.pendientes
        // Mismo almacenamiento: ni siquiera corre.
        val r2 = tel.faseL()
        assertTrue(r1.corrio && !r2.corrio)
        // Y si corre igual (la huella se movió sin cambiar nada), el libro mayor no deja duplicar.
        tel.lector.escribir(emptyMap())
        val r3 = tel.faseL()
        assertTrue(r3.corrio && r3.repeticion && r3.aLaCola == 0 && r3.porValidar == 0 && r3.estacionadas == 0 && r3.anon == 0)
        assertEquals(127, r3.yaEnElLibro)
        assertEquals(cola1, tel.cola())
        assertEquals(libro1.mapValues { it.value.destino }, tel.archivos.libro.mapValues { it.value.destino })
        assertEquals(pendientes1.map { it.ops }, tel.archivos.pendientes.map { it.ops })
        assertEquals(2, tel.archivos.estado?.corridas)
    }

    @Test
    fun seRepiteCuandoCambiaLaHuellaYSoloTraeLoNuevo() {
        val tel = Telefono()
        val base = colaWeb(20)
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(base)), "mypump_tipo_dia" to "entreno"))
        tel.faseL()
        val antes = tel.cola().size
        // La nativa cambia el tipo de día; después el cliente vuelve a la Capacitor (plan B) y carga dos cosas más.
        tel.ajustes.guardar("mypump_tipo_dia", "descanso")
        val nuevas = colaWeb(2, t0 = 1_792_000_000_000.0).map { op ->
            val o = (op as ValorJson.Objeto).campos.toMutableMap()
            o["dedupeKey"] = texto("nueva-${JsonLegado.numero(o["ts"]!!.comoNumero!!)}")
            ValorJson.Objeto(o)
        }
        tel.lector.escribir(mapOf("mypump_outbox_$tokenA" to json(ValorJson.Lista(base + nuevas))))
        val r = tel.faseL()
        assertTrue(r.corrio && r.repeticion)
        assertTrue(r.yaEnElLibro == 20 && r.aLaCola + r.porValidar == 2)
        assertEquals(antes + r.aLaCola, tel.cola().size)
        // El tipo de día no cambió en la Capacitor: no pisa lo que eligió en la nativa.
        assertEquals("descanso", tel.ajustes.leer("mypump_tipo_dia"))
        // Si lo cambia en la Capacitor, es lo último que hizo: gana.
        tel.lector.escribir(mapOf("mypump_tipo_dia" to "refeed"))
        tel.faseL()
        assertEquals("refeed", tel.ajustes.leer("mypump_tipo_dia"))
    }

    @Test
    fun unaOpViejaNoPisaAUnaNativaMasNueva() {
        val tel = Telefono()
        // La nativa ya tiene pendiente el agua de hoy, cargada DESPUÉS que la de la Capacitor.
        val nativa = Operacion(
            "nativa_1", "habito", ValorJson.objeto("fecha" to texto("2026-10-14"), "campo" to texto("vasos_agua"), "valor" to texto("6")),
            "habito|2026-10-14|vasos_agua", ts = 2_000_000_000_000.0,
        )
        Outbox.importarEnArchivo(tel.disco().archivo("outbox.json"), listOf(nativa))
        val vieja = ValorJson.objeto(
            "_id" to texto("1_1"), "kind" to texto("habito"), "dedupeKey" to texto("habito|2026-10-14|vasos_agua"),
            "payload" to ValorJson.objeto("fecha" to texto("2026-10-14"), "campo" to texto("vasos_agua"), "valor" to texto("2")),
            "tries" to numero(0), "ts" to numero(1_791_000_000_000.0),
        )
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(listOf(vieja)))))
        val r = tel.faseL()
        assertTrue(r.reemplazadas == 1 && r.aLaCola == 0)
        assertEquals(listOf("nativa_1"), tel.cola().map { it.id })
        assertEquals(EntradaLibro.Destino.REEMPLAZADA, tel.archivos.libro.values.first().destino)
    }

    @Test
    fun unSurrogateSueltoNoTiraLaColaEntera() {
        // `'chat_' + Date.now() + '_' + contenido.slice(0, 40)` puede cortar un emoji a la mitad, y JSON.stringify lo escribe
        // como `\ud83d` suelto.
        val a39 = "a".repeat(39)
        val contenido = a39 + "😀 y sigue"
        val roto = """[{"_id":"1_1","kind":"chat","payload":{"contenido":"$contenido"},"dedupeKey":"chat_1_$a39\ud83d","tries":0,"ts":1},""" +
            """{"_id":"2_2","kind":"peso","payload":{"fecha":"2026-10-13","valor":80},"dedupeKey":"peso_2026-10-13","tries":0,"ts":2},""" +
            """{"_id":"3_3","kind":"chat","payload":{"contenido":"barra \\ud83d literal"},"dedupeKey":"x\udc00y","tries":0,"ts":3}]"""
        val plan = MigracionLegado.planificar(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to roto), ahora = ahoraMig)
        val ops = plan.colas.first().ops
        assertEquals(3, ops.size)
        assertEquals(contenido, ops[0].operacion.payload["contenido"]?.comoTexto)
        assertEquals("chat_1_$a39�", ops[0].operacion.dedupeKey)
        assertEquals("barra \\ud83d literal", ops[2].operacion.payload["contenido"]?.comoTexto)   // una barra escapada no es un escape
        assertEquals("x�y", ops[2].operacion.dedupeKey)
        // El par completo no se toca.
        assertEquals("""{"t":"😀"}""".let { JsonLegado.parsear(it) }, JsonLegado.parsear("""{"t":"😀"}"""))
    }

    @Test
    fun fotosYSwapsDeComidaQuedanParaSusModelos() {
        val tel = Telefono()
        val foto = "data:image/jpeg;base64,/9j/" + "A".repeat(2000)
        tel.lector.escribir(
            mapOf(
                "mypump_token" to tokenA,
                "mypump_fotoq_$tokenA" to """{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-13","dataUrl":"$foto","intentos":1},""" +
                    """"2026-09-28|perfil":{"pose":"perfil","fecha":"2026-09-30","dataUrl":"$foto","intentos":0},""" +
                    """"2026-10-12|espalda":{"pose":"espalda","fecha":"2026-10-13","intentos":0}}""",
                "mypump_food_swaps_$dietaD" to """{"swap_${dietaD}_desayuno_0_1":{"original":{"name":"Queso"},"current":{"name":"Ricota","qty":150}}}""",
                "mypump_food_swaps_otra-dieta" to """{"swap_otra-dieta_cena_0_0":{"original":null,"current":{"name":"Pollo"}}}""",
                "mypump_swaps_migrados_otra-dieta" to "1",
            ),
        )
        val r = tel.faseL()
        val fotos = (tel.disco().leer(FotoPendiente.ARCHIVO)?.let(ValorJson::desde) as ValorJson.Objeto).campos.mapValues { FotoPendiente.desde(it.value)!! }
        assertEquals(listOf("2026-09-28|perfil", "2026-10-12|frente"), fotos.keys.sorted())   // sin dataUrl la web la tira
        assertEquals(FotoPendiente("frente", "2026-10-13", foto, 1), fotos["2026-10-12|frente"])
        assertEquals(1, r.plan?.conteos?.fotosFueraDeVentana)
        // Los swaps de comida sin migrar quedan donde los busca ModeloApp, sin la marca: su hidratación los sube.
        val swaps = tel.disco().leer("swaps_$dietaD.json")?.let(ValorJson::desde)
        assertEquals("Ricota", swaps?.get("swap_${dietaD}_desayuno_0_1")?.get("current")?.get("name")?.comoTexto)
        assertNull(tel.disco().leer("swaps_migrados_$dietaD"))
        assertEquals("true", tel.disco().leer("swaps_migrados_otra-dieta").toString())
        // La escritura de vuelta saca la cola de fotos de la Capacitor: si el cliente volviera a ella, no las subiría de
        // nuevo encima de una más nueva de la misma semana y pose (agente de MIG-03, 15-oct).
        assertNotNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_fotoq_$tokenA"))
    }

    @Test
    fun unaColaDeFotosQueNoSeLeeNoSeBorra() {
        val tel = Telefono()
        tel.lector.escribir(
            mapOf("mypump_token" to tokenA, "mypump_fotoq_$tokenA" to "{no es json", "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(1, t0 = 10.0)))),
        )
        tel.faseL()
        val borrar = tel.archivos.estado?.escritura?.borrar ?: emptyMap()
        assertNull(borrar["mypump_fotoq_$tokenA"], "se borraba una cola de fotos que no se pudo importar")
        assertNotNull(borrar["mypump_outbox_$tokenA"])
    }

    @Test
    fun sustitucionSinFijadoCuentaComoFijada() {
        val s = MigracionLegado.leerSustituciones(
            """
            {"a-d1-0":{"original":{"slug":"Wide-Grip_Lat_Pulldown","nombre":"Jalón al pecho","images":null},"current":{"slug":"Seated_Cable_Rows","nombre":"Remo","equipment":"cable","images":{"eccentric":"https://x/e.jpg","_matched_slug":"Seated_Cable_Rows"}},"fijado":false,"semana":"3","diaId":"b2d1"},
             "b-d2-1":{"original":{"slug":"x","nombre":"Press"},"current":{"slug":"y","nombre":"Press Smith 🏋️"},"semana":1,"diaId":"b2d2"},
             "c-d3-2":{"original":{"nombre":"Curl"},"current":{"nombre":"Curl sentado"},"fijado":null},
             "roto":{"original":{"nombre":"sin current"}}}
            """.trimIndent(),
        )
        assertEquals(listOf("a-d1-0", "b-d2-1", "c-d3-2"), s.keys.sorted())
        val a = s.getValue("a-d1-0")
        assertTrue(!a.fijado && a.semana == 3 && a.current.images?.get("_matched_slug")?.comoTexto == "Seated_Cable_Rows")
        assertTrue(s.getValue("b-d2-1").fijado && s.getValue("b-d2-1").current.nombre == "Press Smith 🏋️")
        assertFalse(s.getValue("c-d3-2").fijado)   // `null` no es `undefined`: la web lo deja como no fijado
    }

    @Test
    fun conLaColaVivaTodoPasaPorLaFaseR() {
        // El modelo ya existía (la Fase L se demoró): su cola está viva y escribir el archivo la pisaría.
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(18)))))
        tel.almacen.guardar(tokenA)
        val r = tel.faseL(cuentaViva = tokenA)
        assertTrue(r.aLaCola == 0 && r.porValidar == 18)
        assertFalse(tel.disco().archivo("outbox.json").exists())
        assertEquals(18, tel.archivos.pendientes.firstOrNull()?.ops?.size)
    }

    /** La marca de OTRA migración (otro teléfono restaurado, otra instalación) no confirma nada: la escritura sigue pendiente. */
    @Test
    fun unaMarcaAjenaNoConfirmaLaEscritura() {
        val tel = Telefono()
        val ajena = Marca("99999999-9999-4999-8999-999999999999", 1, "2026-10-01T00:00:00Z", "2.0.0").texto
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_nativa_marca" to ajena))
        val r = tel.faseL()
        assertNull(r.escrituraConfirmada)
        val estado = tel.archivos.estado!!
        assertNull(estado.escrituraConfirmada)
        assertNotNull(estado.escritura)   // falta dejar la marca de esta migración
        // La propia sí: con la de esta migración, sin nada para borrar, no queda escritura pendiente.
        tel.lector.escribir(mapOf("mypump_nativa_marca" to Marca(estado.migracion, 1, "2026-10-14T15:00:00Z").texto))
        val r2 = tel.faseL()
        assertEquals(1, r2.escrituraConfirmada)
        assertNull(tel.archivos.estado!!.escritura)
    }

    /** Una cola que no es JSON no se importa ni se borra de la Capacitor (queda en la copia cruda y en el almacenamiento). */
    @Test
    fun unaColaIlegibleNoSeBorra() {
        val tel = Telefono()
        tel.lector.escribir(mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to "[{roto"))
        val r = tel.faseL()
        assertEquals(1, r.plan?.conteos?.colasIlegibles)
        assertTrue(tel.cola().isEmpty())
        assertNull(tel.archivos.estado?.escritura?.borrar?.get("mypump_outbox_$tokenA"))
    }

    /**
     * Sospecha de la revisión del 15-oct, confirmada en iOS (gemelo de `siElKeychainNoGuardaElTokenLaFaseLNoQuedaHecha`): si
     * el almacén no guarda el token (en Android, el Keystore falla y `TokenEnKeystore` borra el archivo sin tirar), la Fase L
     * quedaba hecha igual (con la huella anotada no vuelve a correr) y la app abría en "pegá tu link" para siempre, con la
     * cola esperando en una carpeta que nadie abre.
     */
    @Test
    fun siElAlmacenNoGuardaElTokenLaFaseLNoQuedaHecha() {
        val tel = Telefono()
        tel.lector.escribir(
            mapOf("mypump_token" to tokenA, "mypump_outbox_$tokenA" to json(ValorJson.Lista(colaWeb(9))), "mypump_offline_$tokenA" to fotoOffline(rutinaR1)),
        )
        val roto = AlmacenQueNoGuarda()
        assertThrows(IOException::class.java, { runBlocking { EjecutorLegado.faseLocal(tel.entorno, roto, tel.ajustes, ahoraMig, baires) } }) {
            "la Fase L terminó como si el token hubiera quedado guardado"
        }
        // El arranque siguiente, con el almacén andando, corre de nuevo y adopta el token.
        val r = tel.faseL()
        assertTrue(r.corrio && r.adoptoToken && tel.almacen.leer() == tokenA)
        assertTrue(r.aLaCola + r.porValidar == 9 && r.yaEnElLibro == 0)
    }

    /** Sin almacenamiento viejo no hace nada (ni copia ni estado). */
    @Test
    fun sinLegadoNoHaceNada() {
        val tel = Telefono()
        tel.lector.existe = false
        val r = tel.faseL()
        assertFalse(r.huboLegado || r.corrio)
        assertFalse(tel.entorno.carpeta.exists())
    }

    /** NumerosAbsurdosTests.swift: lo del almacenamiento viejo corre al arrancar, así que un valor raro no puede romper nada. */
    @Test
    fun almacenamientoViejoConNumerosRaros() {
        val op = """{"_id":"a1","kind":"peso","payload":{"fecha":"2026-10-13","valor":80},"dedupeKey":"peso|2026-10-13","tries":"nan","ts":"inf"}"""
        val op2 = """{"_id":"a2","kind":"peso","payload":{"fecha":"2026-10-12","valor":81},"dedupeKey":"peso|2026-10-12","tries":1e300,"ts":1}"""
        val items = mapOf(
            "mypump_token" to tokenA,
            "mypump_outbox_$tokenA" to "[$op,$op2]",
            "mypump_fotoq_$tokenA" to """{"2026-10-12|frente":{"pose":"frente","fecha":"2026-10-12","dataUrl":"data:image/jpeg;base64,AA==","intentos":"nan"},""" +
                """"2026-10-12|perfil":{"pose":"perfil","fecha":"2026-10-12","dataUrl":"data:image/jpeg;base64,AA==","intentos":-1e300}}""",
            "mypump_exercise_swaps_r1" to """{"ex1":{"original":{"nombre":"A"},"current":{"nombre":"B"},"fijado":false,"semana":"nan","diaId":"d1"},""" +
                """"ex2":{"original":{"nombre":"A"},"current":{"nombre":"C"},"fijado":false,"semana":1e300,"diaId":"d1"}}""",
        )
        val plan = MigracionLegado.planificar(items, ahora = ahoraMig)
        val cola = plan.colas.first { it.token == tokenA }
        // iOS: [0, 10^15] (su Int es de 64 bits); acá el entero acotado es el de 32.
        assertEquals(listOf(0, Int.MAX_VALUE), cola.ops.map { it.operacion.tries })
        assertEquals(listOf(0.0, 1.0), cola.ops.map { it.operacion.ts })   // "inf" no es un número que sirva
        assertEquals(listOf(0, 0), cola.fotos.values.map { it.intentos })
        assertNull(plan.sustituciones["r1"]?.get("ex1")?.semana)
        assertEquals(Int.MAX_VALUE, plan.sustituciones["r1"]?.get("ex2")?.semana)
        // La sesión de la app vieja con una semana que no entra en un entero.
        val l = LegadoEntreno.desdeAlmacenamiento(
            mapOf("mypump_sesion_${tokenA}_d1" to "s-1", "mypump_sesion_${tokenA}_d1_semana" to "99999999999999999999"), tokenA, "r1",
        )
        assertEquals("s-1", l.sesiones.first().sesionId)
        assertNull(l.sesiones.first().semana)
    }
}

/** Un almacén en el que guardar falla sin tirar, como `TokenEnKeystore` con el Keystore roto: no queda nada. */
private class AlmacenQueNoGuarda : AlmacenToken {
    override fun leer(): String? = null

    override fun guardar(token: String?) {}
}
