package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.reglas.RelojLocal
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// La nativa contra el bridge REAL de la web (scripts/nativa/vectores-salud.mjs): las mismas respuestas del plugin, en el
// mismo orden, tienen que dar las MISMAS consultas (ventanas al milisegundo), los MISMOS lotes a la base, el mismo
// resultado y el mismo estado guardado. Igualdad total: sin tolerancias. Gemelo de SaludVectoresTests.swift.

class CasoSalud(val o: ValorJson) {
    val nombre: String = o["nombre"]!!.comoTexto!!
    val accion: String = o["accion"]!!.comoTexto!!
    val tz: String = o["tz"]!!.comoTexto!!
    val ahora: Double = o["ahora"]!!.comoNumero!!
    val fuentes: List<List<String>> = (o["fuentes"] as ValorJson.Lista).elementos.map { f -> (f as ValorJson.Lista).elementos.map { it.comoTexto!! } }
    val estadoInicial: Map<String, String> = (o["estadoInicial"] as ValorJson.Objeto).campos.mapValues { it.value.comoTexto!! }
    val consultas: List<ValorJson> = (o["consultas"] as ValorJson.Lista).elementos
    val rpc: List<ValorJson> = (o["rpc"] as ValorJson.Lista).elementos
    val resultado: ValorJson = o["resultado"]!!
    val progreso: List<List<Int>> = (o["progreso"] as ValorJson.Lista).elementos.map { p -> (p as ValorJson.Lista).elementos.map { it.comoNumero!!.toInt() } }
    val estadoFinal: Map<String, String> = (o["estadoFinal"] as ValorJson.Objeto).campos.mapValues { it.value.comoTexto!! }
    val diag: ValorJson? = o["diag"]
    val zona: ZoneId get() = ZoneId.of(tz)
    val instante: Instant get() = Instant.ofEpochMilli(ahora.toLong())
}

fun cargarSalud(nombre: String): List<CasoSalud> {
    val j = ValorJson.parsear(Compartido.texto("vectores/$nombre.json"))
    return (j["casos"] as ValorJson.Lista).elementos.map(::CasoSalud)
}

/** Hace de plugin: contesta lo que contestó el plugin imitado, en orden, y anota cualquier consulta distinta. */
class FuenteGrabada(c: CasoSalud) : FuenteSalud {
    override val plataforma = PlataformaSalud.IOS
    override val iosMayor = 18
    private val consultas = c.consultas
    private val fuentes = c.fuentes
    private var i = 0
    private val _fallas = ArrayList<String>()
    val fallas: List<String> @Synchronized get() = _fallas.toList()
    val pendientes: Int @Synchronized get() = consultas.size - i

    @Synchronized
    private fun siguiente(m: String, chequear: (ValorJson) -> String?): ValorJson {
        if (i >= consultas.size) {
            _fallas += "consulta de más: $m"
            throw ErrorFuenteSalud("de más")
        }
        val e = consultas[i]
        i++
        if (e["m"]?.comoTexto != m) {
            _fallas += "#${i - 1}: la web hizo ${e["m"]?.comoTexto}, la nativa $m"
            throw ErrorFuenteSalud("orden")
        }
        chequear(e)?.let { _fallas += "#${i - 1} $m: $it" }
        e["error"]?.comoTexto?.let { throw ErrorFuenteSalud(it) }
        return e
    }

    private fun textos(j: ValorJson?): List<String> = (j as? ValorJson.Lista)?.elementos?.mapNotNull { it.comoTexto } ?: emptyList()

    private fun ventana(e: ValorJson, desde: Double, hasta: Double): String? =
        if (e["desde"]?.comoNumero == desde && e["hasta"]?.comoNumero == hasta) null
        else "ventana web ${e["desde"]?.comoNumero}…${e["hasta"]?.comoNumero}, nativa $desde…$hasta"

    private fun muestra(fila: ValorJson, sueno: Boolean): MuestraSalud {
        val a = (fila as ValorJson.Lista).elementos
        val f = a[3].comoNumero!!.toInt()
        return MuestraSalud(a[0].comoNumero!!, a[1].comoNumero!!, a[2].comoNumero!!, fuentes[f][0], fuentes[f][1],
            estadoSueno = if (sueno) a.getOrNull(4)?.comoTexto else null)
    }

    override suspend fun disponible(): Boolean = try {
        siguiente("isAvailable") { null }
        true
    } catch (_: ErrorFuenteSalud) {
        false
    }

    override suspend fun pedirLectura(tipos: List<String>) {
        siguiente("requestAuthorization") { e -> if (textos(e["read"]) == tipos) null else "web ${textos(e["read"])}, nativa $tipos" }
    }

    override suspend fun permisos(tipos: List<String>): PermisosSalud {
        val e = siguiente("checkAuthorization") { e -> if (textos(e["read"]) == tipos) null else "web ${textos(e["read"])}, nativa $tipos" }
        return PermisosSalud(textos(e["r"]?.get("readAuthorized")), textos(e["r"]?.get("readDenied")))
    }

    override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> {
        val e = siguiente("queryAggregated") { e ->
            when {
                e["dataType"]?.comoTexto != dataType -> "tipo web ${e["dataType"]?.comoTexto}, nativa $dataType"
                e["agg"]?.comoTexto != agregacion -> "agregación $agregacion"
                else -> ventana(e, desde, hasta)
            }
        }
        return (e["r"] as? ValorJson.Lista)?.elementos?.map { f ->
            val a = (f as ValorJson.Lista).elementos
            BaldeDiario(a[0].comoNumero!!, a[2].comoNumero!!)
        } ?: emptyList()
    }

    override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> {
        val e = siguiente("readSamples") { e ->
            when {
                e["dataType"]?.comoTexto != dataType -> "tipo web ${e["dataType"]?.comoTexto}, nativa $dataType"
                e["limite"]?.comoNumero != limite.toDouble() || e["asc"] != ValorJson.Booleano(true) -> "límite/orden"
                else -> ventana(e, desde, hasta)
            }
        }
        return (e["r"] as? ValorJson.Lista)?.elementos?.map { muestra(it, dataType == "sleep") } ?: emptyList()
    }

    override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> {
        val e = siguiente("queryWorkouts") { e -> ventana(e, desde, hasta) }
        return (e["r"] as? ValorJson.Lista)?.elementos?.map { f ->
            val a = (f as ValorJson.Lista).elementos
            EntrenoCrudo(a[0].comoTexto ?: "", a[1].comoNumero!!, a[2].comoNumero!!, a[3].comoNumero!!, a[4].comoNumero, a[5].comoNumero)
        } ?: emptyList()
    }
}

/** Hace de base: compara cada lote con el de la web y contesta lo mismo que contestó la base imitada. */
class BaseGrabada(c: CasoSalud) : Transporte {
    private val esperado = c.rpc
    private var i = 0
    private val _fallas = ArrayList<String>()
    val fallas: List<String> @Synchronized get() = _fallas.toList()
    val pendientes: Int @Synchronized get() = esperado.size - i

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val fn = pedido.ruta.substringAfterLast('/')
        // Las lecturas que hace el modelo para repintar (get_salud, get_recuperacion…) no son parte del vector.
        if (fn != "mypump_ingest_salud" && fn != "mypump_ingest_entrenos") {
            return Respuesta(200, (if (fn == "mypump_get_mostrar_recuperacion") "true" else "[]").toByteArray())
        }
        val cuerpo = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) }
        val (n, e) = synchronized(this) {
            if (i >= esperado.size) {
                _fallas += "lote de más a $fn"
                null
            } else {
                (i to esperado[i]).also { i++ }
            }
        } ?: throw IOException("lote de más")
        synchronized(this) {
            if (e["fn"]?.comoTexto != fn) _fallas += "rpc #$n: la web llamó ${e["fn"]?.comoTexto}, la nativa $fn"
            val lote = cuerpo?.get(if (fn == "mypump_ingest_salud") "p_registros" else "p_entrenos")
            if (lote != e["lote"]) _fallas += "rpc #$n $fn: ${diferencia(e["lote"], lote)}"
            if (cuerpo?.get("p_token") != e["token"]) _fallas += "rpc #$n: token distinto"
        }
        val r = e["r"]
        if (r?.get("success") == ValorJson.Booleano(true)) return Respuesta(200, (r["data"] ?: ValorJson.Nulo).serializar().toByteArray())
        val error = r?.get("error")?.comoTexto ?: ""
        if (error.contains("Load failed")) throw IOException("sin conexión")
        return Respuesta(400, ValorJson.objeto("code" to ValorJson.Texto("42501"), "message" to ValorJson.Texto(error)).serializar().toByteArray())
    }

    private fun diferencia(a: ValorJson?, b: ValorJson?): String {
        val x = (a as? ValorJson.Lista)?.elementos
        val y = (b as? ValorJson.Lista)?.elementos
        if (x == null || y == null) return "web ${a.toString().take(200)}, nativa ${b.toString().take(200)}"
        if (x.size != y.size) return "web ${x.size} filas, nativa ${y.size}"
        for ((k, p) in x.withIndex()) if (p != y[k]) return "fila $k: web $p, nativa ${y[k]}"
        return "?"
    }
}

/** Corre la acción del caso y devuelve todas las diferencias con la web. */
class CorridaSalud(val caso: CasoSalud, alcance: CoroutineScope, descartarNochesPartidas: Boolean = false) {
    val fuente = FuenteGrabada(caso)
    val base = BaseGrabada(caso)
    val almacen = PreferenciasEnMemoria(caso.estadoInicial)

    // Contra los vectores de la web, con el bug de la web (la noche partida del historial) igual que ella.
    val sinc = SincronizadorSalud(
        fuente, ClienteRpc(transporte = base), "tok-de-prueba-nativa-0001", almacen, alcance, { caso.instante }, caso.zona,
        descartarNochesPartidas = descartarNochesPartidas,
    )

    suspend fun diferencias(): List<String> {
        val difs = ArrayList<String>()
        val ticks = ArrayList<List<Int>>()
        sinc.alProgresar = { h, t -> ticks += listOf(h, t) }
        val r = caso.resultado
        fun igual(campo: String, web: Any?, nativa: Any?) {
            if (web != nativa) difs += "$campo: web $web, nativa $nativa"
        }
        fun entero(j: ValorJson?): Int? = j?.comoNumero?.toInt()
        fun bool(j: ValorJson?): Boolean? = (j as? ValorJson.Booleano)?.valor

        when (caso.accion) {
            "sync" -> {
                val s = sinc.sincronizar()
                igual("ok", bool(r["ok"]), s.ok)
                igual("ingresados", entero(r["ingresados"]), s.ingresados)
                igual("entrenos", entero(r["entrenos"]), s.entrenos)
                val errWeb = r["errorIngesta"]?.comoTexto
                if (errWeb?.contains("Load failed") == true) igual("hubo error de ingesta", true, s.errorIngesta != null)
                else igual("errorIngesta", errWeb, s.errorIngesta)
            }
            "backfill" -> {
                val h = sinc.historial()
                igual("ok", bool(r["ok"]), h.ok)
                igual("saltado", bool(r["saltado"]) ?: false, h.saltado)
                if (!h.saltado) {
                    igual("ingresados", entero(r["ingresados"]), h.ingresados)
                    igual("ventanasFallidas", entero(r["ventanasFallidas"]), h.ventanasFallidas)
                }
            }
            "conectar" -> {
                val c = sinc.conectar(esperarHistorial = true)
                val h = c.historial?.await()
                igual("ok", bool(r["ok"]), c.ok)
                igual("preguntados", entero(r["preguntados"]), c.preguntados)
                igual("total", entero(r["total"]), c.total)
                igual("sinDatos", bool(r["sinDatos"]), c.sinDatos)
                val b = r["backfill"]
                igual("historial.ok", bool(b?.get("ok")), h?.ok)
                igual("historial.saltado", bool(b?.get("saltado")) ?: false, h?.saltado)
                igual("historial.sinDatos", bool(b?.get("sinDatos")), h?.sinDatos)
                if (h?.saltado == false) {
                    igual("historial.ingresados", entero(b?.get("ingresados")), h.ingresados)
                    igual("historial.ventanasFallidas", entero(b?.get("ventanasFallidas")), h.ventanasFallidas)
                }
            }
            "estado" -> {
                val e = sinc.estado()
                igual("disponible", bool(r["disponible"]), e.disponible)
                igual("conectado", bool(r["conectado"]), e.conectado)
                igual("sinDatos", bool(r["sinDatos"]), e.sinDatos)
                igual("preguntados", entero(r["preguntados"]), e.preguntados)
                igual("total", entero(r["total"]), e.total)
                igual("ultimaSync", r["ultimaSync"]?.comoTexto, e.ultimaSync)
            }
            else -> difs += "acción desconocida ${caso.accion}"
        }
        igual("avance del historial", caso.progreso, ticks)
        igual("estado guardado", caso.estadoFinal, almacen.todo - ClaveSalud.DIAG)
        val d = caso.diag
        if (d is ValorJson.Objeto) {
            val mio = sinc.ultimoIntento
            igual("diag.paso", d["paso"]?.comoTexto, mio?.get("paso")?.comoTexto)
            igual("diag.preguntados", entero(d["preguntados"]), entero(mio?.get("preguntados")))
            igual("diag.total", entero(d["total"]), entero(mio?.get("total")))
            igual("diag.rechazados", d["rechazados"], mio?.get("rechazados"))
        }
        difs += fuente.fallas + base.fallas
        if (fuente.pendientes > 0) difs += "la web hizo ${fuente.pendientes} consultas más"
        if (base.pendientes > 0) difs += "la web mandó ${base.pendientes} lotes más"
        return difs
    }
}

class SaludVectoresTest {
    private fun verificar(archivo: String, minimo: Int) = enUnHilo { alcance ->
        val casos = cargarSalud(archivo)
        assertTrue(casos.size >= minimo, "${casos.size} casos")
        for (c in casos) {
            val difs = CorridaSalud(c, alcance).diferencias()
            assertTrue(difs.isEmpty(), "${c.nombre}: ${difs.take(6).joinToString(" | ")}")
        }
    }

    @Test
    fun sincronizarSieteDias() = verificar("salud_sync", 20)

    @Test
    fun historialDeSesentaDias() = verificar("salud_backfill", 9)

    @Test
    fun conectarYEstado() = verificar("salud_conectar", 6)

    /** Cuánto cubren los vectores (para el informe): registros y entrenos que tienen que salir idénticos. */
    @Test
    fun coberturaDeLosVectores() {
        var registros = 0
        var entrenos = 0
        var consultas = 0
        val tipos = HashSet<String>()
        for (archivo in listOf("salud_sync", "salud_backfill", "salud_conectar")) {
            for (c in cargarSalud(archivo)) {
                consultas += c.consultas.size
                for (r in c.rpc) {
                    val lote = (r["lote"] as? ValorJson.Lista)?.elementos ?: continue
                    if (r["fn"]?.comoTexto == "mypump_ingest_salud") {
                        registros += lote.size
                        lote.forEach { x -> x["tipo"]?.comoTexto?.let(tipos::add) }
                    } else {
                        entrenos += lote.size
                    }
                }
            }
        }
        assertTrue(registros > 5000, "$registros")
        assertTrue(entrenos > 100, "$entrenos")
        // Todos los tipos que manda el iPhone salen en algún vector.
        val todos = (PuenteSalud.agregados.map { it.tipo } + PuenteSalud.muestras.map { it.tipo } +
            listOf("sueno_min", "sueno_medio_min", "sueno_eficiencia_pct", "sueno_ligero_min", "sueno_profundo_min", "sueno_rem_min", "hrv_ms")).toSet()
        assertTrue((todos - tipos).isEmpty(), "sin vector: ${(todos - tipos).sorted()}")
        println("vectores de salud: $registros registros, $entrenos entrenos, $consultas consultas al plugin, ${tipos.size} tipos")
    }
}

/** Registra lo que se manda a `ingest_salud` y contesta que entró todo. */
class BaseQueAnota : Transporte {
    private val _lotes = ArrayList<List<ValorJson>>()
    val lotes: List<List<ValorJson>> @Synchronized get() = _lotes.toList()

    override suspend fun enviar(pedido: Pedido): Respuesta {
        val fn = pedido.ruta.substringAfterLast('/')
        var respuesta = "[]"
        if (fn == "mypump_ingest_salud" || fn == "mypump_ingest_entrenos") {
            val cuerpo = pedido.cuerpo?.let { ValorJson.parsear(it.toString(Charsets.UTF_8)) }
            val l = (cuerpo?.get(if (fn == "mypump_ingest_salud") "p_registros" else "p_entrenos") as? ValorJson.Lista)?.elementos
            if (l != null) {
                if (fn == "mypump_ingest_salud") synchronized(this) { _lotes += l }
                respuesta = l.size.toString()
            }
        } else if (fn == "mypump_get_mostrar_recuperacion") {
            respuesta = "true"
        }
        return Respuesta(200, respuesta.toByteArray())
    }
}

/** El historial no pisa la noche de hoy (desvío a propósito de la web, el mismo de iOS). */
class SaludNocheParcialTest {
    /**
     * Corre "conectar-primera-vez" y devuelve las filas de sueño que mandó el HISTORIAL con fecha de hoy. Con [descartar]
     * null, el sincronizador como lo arma la app (el valor por defecto).
     */
    private fun suenoDeHoyEnElHistorial(descartar: Boolean?): List<ValorJson> {
        var partidas: List<ValorJson> = emptyList()
        enUnHilo { alcance ->
            val caso = cargarSalud("salud_conectar").first { it.nombre == "conectar-primera-vez" }
            val base = BaseQueAnota()
            val cliente = ClienteRpc(transporte = base)
            val almacen = PreferenciasEnMemoria(caso.estadoInicial)
            val sinc = if (descartar == null) {
                SincronizadorSalud(FuenteGrabada(caso), cliente, "tok-de-prueba-nativa-0001", almacen, alcance, { caso.instante }, caso.zona)
            } else {
                SincronizadorSalud(FuenteGrabada(caso), cliente, "tok-de-prueba-nativa-0001", almacen, alcance, { caso.instante }, caso.zona, descartar)
            }
            sinc.conectar(esperarHistorial = true).historial?.await()
            val hoy = RelojLocal(caso.zona).ymd(caso.ahora)
            // El primer lote es la sincronización de 7 días; lo que sigue es el historial.
            partidas = base.lotes.drop(1).flatten().filter {
                (it["tipo"]?.comoTexto ?: "").startsWith("sueno") && it["fecha"]?.comoTexto == hoy
            }
        }
        return partidas
    }

    @Test
    fun conElArregloNoSeMandaLaNochePartida() {
        val partidas = suenoDeHoyEnElHistorial(descartar = null)   // el de la app
        assertTrue(partidas.isEmpty(), "$partidas")
    }

    @Test
    fun sinElArregloSeMandaba() {
        // Lo que hace la web hoy: confirma que el test de arriba muerde.
        assertFalse(suenoDeHoyEnElHistorial(descartar = false).isEmpty())
    }
}
