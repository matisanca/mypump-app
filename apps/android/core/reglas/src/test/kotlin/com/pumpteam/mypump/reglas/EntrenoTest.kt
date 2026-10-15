package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Bloque
import com.pumpteam.mypump.modelos.Comentario
import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.EstadoEjercicio
import com.pumpteam.mypump.modelos.EstructuraRutina
import com.pumpteam.mypump.modelos.NumeroJs
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.RegistroSesion
import com.pumpteam.mypump.modelos.ValorJson
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

// Gemelo de EntrenoTests.swift. Vectores de scripts/nativa/vectores-entreno.mjs: las funciones REALES de cliente.html
// (normalizarRutina, los sugeridos, las variantes, renderSetRow, confirmarSerie, los handlers de bindTrainEvents, la poda,
// el descanso…) corridas con dobles del DOM y de la base. Igualdad total; los textos se comparan por unidades UTF-16.

private val zonaVectores: ZoneId = ZoneId.of("America/Argentina/Buenos_Aires")

// ── Lectura del JSON de los vectores ──

private fun JsonElement?.o(): JsonObject? = this as? JsonObject
private fun JsonElement?.a(): JsonArray = this as? JsonArray ?: JsonArray(emptyList())
private fun JsonElement?.s(): String? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && it.isString }?.content
private fun JsonElement?.d(): Double? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.doubleOrNull
private fun JsonElement?.i(): Int? = (this as? JsonPrimitive)?.takeIf { it !is JsonNull && !it.isString }?.intOrNull
private fun JsonElement?.b(): Boolean = (this as? JsonPrimitive)?.takeIf { it !is JsonNull }?.booleanOrNull ?: false
private fun JsonElement?.nulo(): Boolean = this == null || this is JsonNull
private fun JsonElement?.textos(): List<String> = a().mapNotNull { it.s() }

private fun cargar(p: Path): JsonObject = Json.parseToJsonElement(Files.readString(p)).jsonObject

/** Una serie como la guarda la web (`{reps, kg, rir, confirmed}`) y la extensión de la nativa (nombre y variante). */
private fun serie(e: JsonElement): SerieLocal {
    val o = e.jsonObject
    return SerieLocal(
        reps = o["reps"].s() ?: "", kg = o["kg"].s() ?: "", rir = o["rir"].s() ?: "", confirmada = o["confirmed"].b(),
        nombreRegistrado = o["nombreRegistrado"].s(), varianteRegistrada = o["varianteRegistrada"].s(),
    )
}

private fun estructura(v: JsonElement?): EstructuraRutina? = if (v.nulo()) null else EstructuraRutina.desde(v!!)

/** El `texto()` del decodificador de Kotlin: un número como lo imprime JS. */
private fun textoComoDecodificador(v: JsonElement?): String? {
    val p = v as? JsonPrimitive ?: return null
    if (p is JsonNull) return null
    if (p.isString) return p.content
    return p.content.toDoubleOrNull()?.let(NumeroJs::texto)
}

private fun modal(p: Pregunta?): String = if (p == null) "nil" else "${p.titulo} | ${p.cuerpo} | ${p.confirmar} | ${p.cancelar}"

private fun modalWeb(m: JsonElement?): String {
    val o = m.o() ?: return "nil"
    return "${o["titulo"].s()} | ${o["cuerpo"].s()} | ${o["confirmar"].s()} | ${o["cancelar"].s() ?: ""}"
}

/** Las estructuras privadas, en el orden en que las leyó el generador. */
private fun estructurasPrivadas(archivos: List<String>): List<EstructuraRutina> = archivos.flatMap { rel ->
    Json.parseToJsonElement(Files.readString(Vectores.privadoRelativo(rel))).jsonArray.map { estructura(it) ?: EstructuraRutina() }
}

private fun historiales(e: JsonElement?): List<List<RegistroHistorico>> = e.a().map { h -> h.a().map(RegistroHistorico::desde) }

// ── Verificaciones (públicos y privados usan las mismas) ──

private fun fallasNormalizar(v: JsonObject, privadas: List<EstructuraRutina> = emptyList()): List<String> {
    val fallas = mutableListOf<String>()
    v["normalizar"].a().forEachIndexed { k, cj ->
        val c = cj.jsonObject
        val e: EstructuraRutina? = c["ref"].i()?.let { privadas[it] } ?: estructura(c["est"])
        val r = NormalizacionRutina.normalizar(e)
        val malos = mutableListOf<String>()
        if (r.usable != c["usable"].b()) malos += "usable ${r.usable}"
        if (r.problemas != c["problemas"].textos()) malos += "problemas ${r.problemas} vs ${c["problemas"]}"
        val dias = c["dias"] as? JsonArray
        if (dias != null) {
            if (r.estructura.semanasTotal != c["semanasTotal"].i()) malos += "semanas ${r.estructura.semanasTotal}"
            if (r.estructura.dias.size != dias.size) malos += "días ${r.estructura.dias.size}"
            for ((d, wj) in r.estructura.dias.zip(dias)) {
                val w = wj.jsonObject
                if (d.id != w["id"].s() || d.nombre != w["nombre"].s()) malos += "día ${d.id} ${d.nombre}"
                val n = TextosEntreno.numeroDia(d, r.estructura.dias).toString()
                if (n != w["numero"].s()) malos += "número $n vs ${w["numero"]}"
                val bloques = d.bloques.map { b -> b.ejercicios.map { listOf(it.descansoSegundos ?: -1, it.series ?: -1) } }
                val web = w["bloques"].a().map { b -> b.a().map { x -> x.a().map { it.i() } } }
                if (bloques != web) malos += "bloques $bloques vs $web"
            }
        }
        if (malos.isNotEmpty()) fallas += "#$k: $malos"
    }
    return fallas
}

private fun fallasTextos(v: JsonObject): List<String> {
    val fallas = mutableListOf<String>()
    val t = v["textos"].o() ?: return fallas
    for (cj in t["dias"].a()) {
        val c = cj.jsonObject
        val corto = TextosEntreno.nombreCortoDia(c["nombre"].s())
        if (corto != c["corto"].s()) fallas += "día ${c["nombre"]}: web ${c["corto"]}, kotlin \"$corto\""
    }
    for (cj in t["bloques"].a()) {
        val c = cj.jsonObject
        val s = TextosEntreno.nombreBloque(Bloque(titulo = c["titulo"].s(), subtitulo = c["subtitulo"].s()))
        if (s != c["nombre"].s()) fallas += "bloque ${c["titulo"]} / ${c["subtitulo"]}: web ${c["nombre"]}, kotlin \"$s\""
    }
    return fallas
}

private fun fallasEjercicios(v: JsonObject): List<String> {
    val fallas = mutableListOf<String>()
    for (cj in v["ejercicios"].a()) {
        val c = cj.jsonObject
        val nombre = c["nombre"].s() ?: ""
        val tipo = c["tipo"].s()
        val variantes = ReglasEjercicio.variantes(nombre)
        val w = c["variantes"].o()
        val okVar = (variantes == null && w == null) || (
            variantes != null && w != null && variantes.etiqueta == w["etiqueta"].s() &&
                variantes.opciones == w["ops"].textos() && variantes.sinPeso == w["sinPeso"].b()
            )
        val sinPeso = ReglasEjercicio.esSinPeso(nombre, tipo)
        val sinKg = ReglasEjercicio.sinKg(nombre, tipo)
        if (!okVar || sinPeso != c["sinPeso"].b() || sinKg != c["sinKg"].b()) {
            fallas += "\"$nombre\" [$tipo]: variantes $variantes vs $w, sinPeso $sinPeso vs ${c["sinPeso"]}, sinKg $sinKg vs ${c["sinKg"]}"
        }
    }
    for (cj in v["reps"].a()) {
        val c = cj.jsonObject
        val s = ReglasEjercicio.repsDelPlan(textoComoDecodificador(c["reps"]))
        if (s != c["sug"].d()) fallas += "reps ${c["reps"]}: web ${c["sug"]}, kotlin $s"
    }
    return fallas
}

private fun fallasHistorial(v: JsonObject): List<String> {
    val fallas = mutableListOf<String>()
    val ahora = Instant.ofEpochMilli(v["ahora"].d()!!.toLong())
    val hist = v["historial"].o() ?: return fallas
    val ejercicios = hist["ejercicios"].a().map(Ejercicio::desde)
    val hs = historiales(hist["historiales"])
    for (cj in hist["casos"].a()) {
        val c = cj.jsonObject
        val ex = ejercicios[c["ex"].i()!!]
        val h = hs[c["h"].i()!!]
        val idx = c["idx"].i()!!
        val dia = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(ex)))), semana = 1, zona = zonaVectores)
        dia.ejercicios = dia.ejercicios + (ex.id to dia.ejercicios.getValue(ex.id).copy(variante = c["variante"].s()))
        dia.historial = mapOf(ex.id to h)
        val (va, def) = dia.varianteActiva(ex.id)
        val ref = HistorialEntreno.ultimaSerie(h, idx, va, def, zonaVectores)
        val kg = dia.kgUltimaVez(ex.id, idx)
        val reps = dia.repsUltimaVez(ex.id, idx)
        val record = dia.record(ex.id)
        val recordKg = HistorialEntreno.recordKg(h)
        val uv = dia.ultimaVez(ex.id, ahora)
        val uw = c["ultimaVez"].o()
        val okUv = (uv == null && uw == null) || (uv != null && uw != null && uv.valor == uw["val"].s() && uv.cuando == uw["rel"].s())
        if (ref != c["ref"].i() || kg != c["kg"].s() || reps != c["reps"].s() || record != c["record"].s() ||
            recordKg != c["recordKg"].d() || !okUv
        ) {
            fallas += "${ex.nombre} h${c["h"]} ${c["variante"]} #$idx: ref $ref/${c["ref"]} kg $kg/${c["kg"]} reps $reps/${c["reps"]} " +
                "record $record/${c["record"]} $recordKg/${c["recordKg"]} última $uv/$uw"
        }
    }
    return fallas
}

private fun fallasFilas(v: JsonObject): List<String> {
    val fallas = mutableListOf<String>()
    val f = v["filas"].o() ?: return fallas
    val ejercicios = f["ejercicios"].a().map(Ejercicio::desde)
    val hs = historiales(f["historiales"])
    val series = f["series"].a().map { s -> s.a().map(::serie) }
    for (cj in f["casos"].a()) {
        val c = cj.jsonObject
        val ex = ejercicios[c["ex"].i()!!]
        val i = c["i"].i()!!
        val activaWeb = c["activa"].b()
        val dia = DiaEnCurso(Dia(id = "d1", bloques = listOf(Bloque(ejercicios = listOf(ex)))), semana = 1, zona = zonaVectores)
        val lasSeries = series[c["series"].i()!!]
        dia.ejercicios = dia.ejercicios + (ex.id to EjercicioEnSesion(lasSeries, variante = c["variante"].s()))
        dia.historial = mapOf(ex.id to hs[c["h"].i()!!])
        val efectivo = ex.copy(nombre = c["efectivo"].s() ?: "")
        val fila = dia.fila(ex.id, i, efectivo)
        if (fila == null) {
            fallas += "sin fila $c"
            continue
        }
        val clase = "set-row" + (if (fila.confirmada) " is-confirmed" else "") + (if (!fila.confirmada && !activaWeb) " is-pending" else "") +
            (if (activaWeb) " is-active" else "")
        val pista = fila.pista?.let { "${it.antes}«${it.negrita}»${it.despues}" }
        val s = lasSeries[i]
        val malos = mutableListOf<String>()
        if (fila.activa != activaWeb) malos += "activa"
        if (clase != c["clase"].s()) malos += "clase $clase"
        if (fila.placeholderReps != c["phReps"].s()) malos += "phReps ${fila.placeholderReps}"
        if (s.reps != c["reps"].s() || fila.confirmada != c["repsSoloLectura"].b()) malos += "reps"
        if (fila.placeholderKg != c["phKg"].s()) malos += "phKg ${fila.placeholderKg}"
        if (fila.kg != c["kg"].s() || (fila.confirmada || fila.sinKg) != c["kgSoloLectura"].b()) malos += "kg ${fila.kg} ${fila.sinKg}"
        if (fila.rir != c["rir"].s()) malos += "rir ${fila.rir}"
        if (fila.confirmada != c["editar"].b() || !fila.puedeConfirmar != c["deshabilitado"].b()) malos += "botón ${fila.puedeConfirmar}"
        if (fila.tituloConfirmar != c["titulo"].s()) malos += "título ${fila.tituloConfirmar}"
        if (pista != c["pista"].s()) malos += "pista $pista"
        if (fila.calibracion != c["calibracion"].s()) malos += "calibración ${fila.calibracion}"
        if (malos.isNotEmpty()) fallas += "${ex.nombre} → ${c["efectivo"]} h${c["h"]} series${c["series"]} ${c["variante"]} #$i: $malos — web $c"
    }
    return fallas
}

private fun fallasBanners(banners: JsonArray, planes: List<EstructuraRutina?>): List<String> {
    val normalizados = HashMap<Int, EstructuraRutina>()
    val fallas = mutableListOf<String>()
    for (bj in banners) {
        val b = bj.jsonObject
        val i = b["ref"].i() ?: b["plan"].i() ?: -1
        val est = normalizados.getOrPut(i) { NormalizacionRutina.normalizar(planes[i]).estructura }
        val r = SemanaEntreno.banner(est.dias[b["dia"].i()!!], b["semana"].i()!!, b["offset"].i()!!)
        if (r.cambian != b["n"].i() || r.calibracion != b["calibracion"].b() || r.texto != b["texto"].s()) {
            fallas += "plan $i día ${b["dia"]} sem ${b["semana"]}+${b["offset"]}: $r vs n ${b["n"]} calibración ${b["calibracion"]}"
        }
    }
    return fallas
}

/** El estado del día después de una acción, contra el de la web. */
private fun diferenciaSesion(d: DiaEnCurso, web: JsonObject?): List<String> {
    val malos = mutableListOf<String>()
    for ((id, wj) in web ?: return malos) {
        val w = wj.jsonObject
        val e = d.ejercicios[id]
        if (e == null) {
            malos += "$id no está"
            continue
        }
        val series = w["sets"].a().map(::serie)
        if (e.series.map { it.copy(aviso = null) } != series) malos += "$id series ${e.series} vs $series"
        if (e.completo != w["completed"].b() || e.estado != w["status"].s() || e.variante != w["variante"].s()) {
            malos += "$id completo ${e.completo}/${w["completed"]} estado ${e.estado}/${w["status"]} variante ${e.variante}/${w["variante"]}"
        }
    }
    return malos
}

/** La cola de Kotlin contra la de la web: mismo payload y la misma clave + la semana (arreglo nativo n.º 1). */
private fun diferenciaCola(efectos: List<DiaEnCurso.Efecto>, web: JsonArray, semana: Int): List<String> {
    val cola = efectos.filterIsInstance<DiaEnCurso.Efecto.Encolar>()
    if (cola.size != web.size) return listOf("cola ${cola.map { it.clave }} vs ${web.map { it.jsonObject["key"] }}")
    val malos = mutableListOf<String>()
    for ((s, wj) in cola.zip(web)) {
        val w = wj.jsonObject
        if (s.kind != w["kind"].s() || s.payload != ValorJson.desde(w["payload"]!!) || s.clave != "${w["key"].s()}_s$semana") {
            malos += "op ${s.kind} ${s.clave} ${s.payload} vs ${w["kind"]} ${w["key"]} ${w["payload"]}"
        }
    }
    return malos
}

private data class Pedidos(
    val historial: List<String>,
    val leidos: List<String>,
    val descanso: Double?,
    val detener: Boolean,
    val asegurar: Boolean,
    val completo: Boolean,
    val guardar: Boolean,
    val reabrio: Boolean,
)

private fun pedidos(efectos: List<DiaEnCurso.Efecto>): Pedidos {
    val h = mutableListOf<String>()
    val l = mutableListOf<String>()
    var d: Double? = null
    var det = false
    var a = false
    var c = false
    var g = false
    var r = false
    for (e in efectos) {
        when (e) {
            is DiaEnCurso.Efecto.PedirHistorial -> h += e.lugar
            is DiaEnCurso.Efecto.MarcarLeidos -> l += e.lugar
            is DiaEnCurso.Efecto.IniciarDescanso -> d = e.segundos
            DiaEnCurso.Efecto.DetenerDescanso -> det = true
            DiaEnCurso.Efecto.AsegurarSesion -> a = true
            DiaEnCurso.Efecto.DiaCompleto -> c = true
            DiaEnCurso.Efecto.GuardarSustituciones -> g = true
            DiaEnCurso.Efecto.ReabrioDia -> r = true
            is DiaEnCurso.Efecto.Encolar -> {}
        }
    }
    return Pedidos(h, l, d, det, a, c, g, r)
}

private fun DiaEnCurso.ponerSeries(id: String, series: List<SerieLocal>) {
    val e = ejercicios[id] ?: return
    ejercicios = ejercicios + (id to e.copy(series = series))
}

private fun DiaEnCurso.ponerEstado(id: String, estado: String) {
    estados = estados + (id to estado)
    val e = ejercicios[id] ?: return
    ejercicios = ejercicios + (id to e.copy(estado = estado))
}

private fun valores(m: JsonElement?): Map<String, ValorJson> = m.o()?.mapValues { ValorJson.desde(it.value) } ?: emptyMap()

class EntrenoVectoresTest {
    private val v: JsonObject by lazy { cargar(Vectores.publico("entreno")) }

    @Test
    fun normalizarRutina() {
        assertTrue(v["normalizar"].a().size >= 10)
        val f = fallasNormalizar(v)
        assertTrue(f.isEmpty(), "${f.size} de ${v["normalizar"].a().size}: ${f.take(5)}")
    }

    @Test
    fun textosDeDiaYBloque() {
        val f = fallasTextos(v)
        assertTrue(f.isEmpty(), "${f.size}: ${f.take(8)}")
    }

    @Test
    fun variantesSinKgYRepsDelPlan() {
        assertTrue(v["ejercicios"].a().size > 100)
        val f = fallasEjercicios(v)
        assertTrue(f.isEmpty(), "${f.size}: ${f.take(8)}")
    }

    @Test
    fun camposYRir() {
        for (cj in v["campos"].a()) {
            val c = cj.jsonObject
            val k = CamposSerie.normalizar(c["campo"].s()!!, c["v"].s())
            assertEquals(c["out"].s(), k, "${c["campo"]} ${c["v"]}")
        }
        for (cj in v["rir"].a()) {
            val c = cj.jsonObject
            assertEquals(c["out"].d(), CamposSerie.rir(c["v"].s()), "rir ${c["v"]}")
        }
    }

    @Test
    fun historialSugeridosRecordYUltimaVez() {
        assertTrue(v["historial"].o()!!["casos"].a().size > 500)
        val f = fallasHistorial(v)
        assertTrue(f.isEmpty(), "${f.size}: ${f.take(5)}")
        val her = v["heredable"].o()!!
        val series = her["series"].a().map { s -> s.a().map(::serie) }
        for (cj in her["casos"].a()) {
            val c = cj.jsonObject
            val s = HistorialEntreno.kgHeredable(series[c["series"].i()!!], c["idx"].i()!!)
            assertEquals(c["kg"].s(), s, "heredable ${c["series"]} #${c["idx"]}")
        }
    }

    @Test
    fun filaDeUnaSerie() {
        assertTrue(v["filas"].o()!!["casos"].a().size > 1000)
        val f = fallasFilas(v)
        assertTrue(f.isEmpty(), "${f.size}: ${f.take(4)}")
    }

    /** Lo que hace el modelo: un paso, y si pregunta, otro con la respuesta. */
    private fun confirmar(d: DiaEnCurso, id: String, idx: Int, preguntar: (Pregunta) -> Boolean): List<DiaEnCurso.Efecto> {
        var r = DiaEnCurso.Respuestas()
        val efectos = mutableListOf<DiaEnCurso.Efecto>()
        while (true) {
            val paso = d.confirmarSerie(id, idx, r)
            efectos += paso.efectos
            val p = paso.pregunta ?: return efectos
            val motivo = paso.motivo ?: return efectos
            val si = preguntar(p)
            r = when (motivo) {
                DiaEnCurso.Paso.Motivo.REABRIR -> r.copy(reabrir = si)
                DiaEnCurso.Paso.Motivo.REGISTRAR_IGUAL -> r.copy(registrarIgual = si)
            }
        }
    }

    @Test
    fun confirmarSerie() {
        val c = v["confirmar"].o()!!
        val diaPlan = Dia.desde(c["dia"]!!)
        val historial = c["historial"].o()!!.mapValues { (_, h) -> h.a().map(RegistroHistorico::desde) }
        val casos = c["casos"].a()
        assertTrue(casos.size > 30)
        val fallas = mutableListOf<String>()
        for (cj in casos) {
            val caso = cj.jsonObject
            val ex = caso["ex"].s()!!
            val idx = caso["idx"].i()!!
            val semana = caso["semana"].i()!!
            val diaFinalizadoAntes = caso["diaFinalizado"].b()
            val d = DiaEnCurso(diaPlan, semana, sesionId = caso["sesionId"].s(), diaFinalizado = diaFinalizadoAntes, zona = zonaVectores)
            d.historial = historial
            d.expandido = ex
            val antes = caso["antes"].o()!!
            for ((k, s) in antes["sets"].o()!!) d.ponerSeries(k, s.a().map(::serie))
            for ((k, x) in antes["variante"].o()!!) d.ejercicios[k]?.let { d.ejercicios = d.ejercicios + (k to it.copy(variante = x.s())) }
            for ((k, x) in antes["status"].o()!!) d.ponerEstado(k, x.s()!!)
            d.sustituciones = valores(antes["swaps"])
            val respuestas = ArrayDeque(caso["respuestas"].a().map { it.b() })
            val preguntas = mutableListOf<Pregunta>()
            val efectos = confirmar(d, ex, idx) { p ->
                preguntas += p
                respuestas.removeFirstOrNull() ?: false
            }
            val despues = caso["despues"].o()!!
            val malos = (diferenciaSesion(d, despues["sesion"].o()) + diferenciaCola(efectos, caso["cola"].a(), semana)).toMutableList()
            val p = pedidos(efectos)
            if (preguntas.map(::modal) != caso["modales"].a().map(::modalWeb)) malos += "modales ${preguntas.map(::modal)}"
            val aviso = d.ejercicios[ex]?.series?.getOrNull(idx)?.aviso
            val dudosas = caso["dudosas"].a()
            val avisoWeb = if (dudosas.isEmpty()) null else dudosas.last().s() ?: ""
            if (aviso != avisoWeb) malos += "aviso $aviso vs $dudosas"
            if (p.descanso != caso["descanso"].d()) malos += "descanso ${p.descanso}"
            // Desvío a propósito (D13): la web marca leídos los comentarios del siguiente porque abre su card sola; acá
            // "Siguiente" es un botón y se marcan al abrirla. Confirmar nunca marca leídos.
            if (p.historial != caso["historialPedido"].textos() || p.leidos.isNotEmpty()) malos += "historial ${p.historial} leídos ${p.leidos}"
            if (p.asegurar != caso["sesionAsegurada"].b() || p.completo != caso["diaCompleto"].b()) malos += "sesión ${p.asegurar} día completo ${p.completo}"
            if (d.diaFinalizado != despues["diaFinalizado"].b() || d.expandido != despues["expandido"].s()) malos += "día ${d.diaFinalizado} expandido ${d.expandido}"
            val finalizadaLocal = if (diaFinalizadoAntes && !p.reabrio) "1" else null
            if (finalizadaLocal != despues["finalizadaLocal"].s()) malos += "marca local $finalizadaLocal"
            if (malos.isNotEmpty()) fallas += "${caso["nombre"]}: $malos"
        }
        assertTrue(fallas.isEmpty(), fallas.take(5).joinToString("\n"))
    }

    @Test
    fun accionesDeLaCard() {
        val c = v["confirmar"].o()!!
        val diaPlan = Dia.desde(c["dia"]!!)
        val historial = c["historial"].o()!!.mapValues { (_, h) -> h.a().map(RegistroHistorico::desde) }
        val a = v["acciones"].o()!!
        val fallas = mutableListOf<String>()
        for (cj in a["casos"].a()) {
            val caso = cj.jsonObject
            val antes = caso["antes"].o()!!
            val d = DiaEnCurso(diaPlan, 1, sesionId = "ses-1", zona = zonaVectores)
            d.historial = if (antes["conHistorial"].b()) historial else emptyMap()
            d.expandido = antes["expandido"].s()
            for ((k, modo) in antes["sets"].o()!!) {
                val series = d.ejercicios.getValue(k).series.mapIndexed { i, s ->
                    if (modo.s() == "todas" || i == 0) SerieLocal(reps = "10", kg = "50", confirmada = true) else s
                }
                d.ponerSeries(k, series)
            }
            for ((k, x) in antes["status"].o()!!) d.ponerEstado(k, x.s()!!)
            d.sustituciones = valores(antes["swaps"])
            val respuestas = ArrayDeque(caso["respuestas"].a().map { it.b() })
            val preguntas = mutableListOf<Pregunta>()
            var asegurada = false
            val valor = caso["valor"].s()!!
            val id = valor.substringBefore('|')
            val resto = if ('|' in valor) valor.substringAfter('|') else ""
            val efectos: List<DiaEnCurso.Efecto> = when (caso["attr"].s()) {
                "data-mark" -> d.marcarCompleto(id)
                "data-finish" -> {
                    val p = d.preguntaTerminar(id)
                    if (p != null) preguntas += p
                    if (p != null && !(respuestas.removeFirstOrNull() ?: false)) {
                        emptyList()
                    } else {
                        asegurada = true
                        d.terminar(id)
                    }
                }
                "data-reopen" -> d.reabrir(id)
                "data-edit" -> d.editarSerie(id, resto.toInt())
                "data-variante" -> {
                    d.elegirVariante(id, resto)
                    emptyList()
                }
                "data-toggle" -> d.tocarCard(id)
                "data-revert-ex" -> d.revertir(id)
                else -> {
                    fallas += "acción desconocida ${caso["attr"]}"
                    continue
                }
            }
            val despues = caso["despues"].o()!!
            val malos = (diferenciaSesion(d, despues["sesion"].o()) + diferenciaCola(efectos, caso["cola"].a(), 1)).toMutableList()
            val p = pedidos(efectos)
            if (preguntas.map(::modal) != caso["modales"].a().map(::modalWeb)) malos += "modales ${preguntas.map(::modal)}"
            if (d.expandido != despues["expandido"].s()) malos += "expandido ${d.expandido}"
            if (d.sustituciones.keys.sorted() != despues["swaps"].textos()) malos += "swaps ${d.sustituciones.keys.sorted()}"
            if (d.historial.keys.sorted() != despues["historialEnCache"].textos()) malos += "historial en caché ${d.historial.keys.sorted()}"
            if (p.detener != caso["stopRest"].b() || (asegurada || p.asegurar) != caso["sesionAsegurada"].b()) malos += "descanso ${p.detener} sesión $asegurada"
            if (p.historial != caso["historialPedido"].textos() || p.leidos != caso["leidos"].textos() || p.completo != caso["diaCompleto"].b()) {
                malos += "pedidos $p"
            }
            val guardadas = if (p.guardar) d.sustituciones.keys.sorted() else null
            val guardadasWeb = (caso["swapsGuardados"] as? JsonArray)?.textos()
            if (guardadas != guardadasWeb) malos += "guardadas ${p.guardar}"
            if (malos.isNotEmpty()) fallas += "${caso["nombre"]}: $malos"
        }
        for (rj in a["rir"].a()) {
            val r = rj.jsonObject
            val ex = r["ex"].s()!!
            val d = DiaEnCurso(diaPlan, 1, sesionId = "ses-1", zona = zonaVectores)
            val series = d.ejercicios.getValue(ex).series.toMutableList()
            series[1] = SerieLocal(
                reps = "8", kg = "82.5", rir = r["inicial"].s()!!, confirmada = r["confirmada"].b(),
                varianteRegistrada = r["varianteRegistrada"].s(),
            )
            d.ponerSeries(ex, series)
            assertEquals(r["leyenda"].s(), CamposSerie.leyendaRir(r["inicial"].s()!!))
            val efectos = d.elegirRir(ex, 1, r["valor"].s()!!)
            assertEquals(serie(r["serie"]!!), d.ejercicios.getValue(ex).series[1])
            val cola = diferenciaCola(efectos, r["cola"].a(), 1)
            assertTrue(cola.isEmpty(), "rir ${r["valor"]}: $cola")
        }
        assertTrue(fallas.isEmpty(), fallas.take(5).joinToString("\n"))
    }

    @Test
    fun resumenDelCierre() {
        val diaPlan = Dia.desde(v["confirmar"].o()!!["dia"]!!)
        val r = v["resumen"].o()!!
        val series = r["series"].a()
        val estados = r["estados"].a()
        val casos = r["casos"].a()
        assertTrue(casos.size > 50)
        for (cj in casos) {
            val caso = cj.jsonObject
            val d = DiaEnCurso(diaPlan, 1, zona = zonaVectores)
            for ((k, s) in series[caso["series"].i()!!].jsonObject) d.ponerSeries(k, s.a().map(::serie))
            for ((k, x) in estados[caso["estados"].i()!!].jsonObject) d.estados = d.estados + (k to x.s()!!)
            val minutos = TiempoEntreno.minutosSesion(caso["inicio"].d(), caso["ahora"].d()!!)
            val modal = caso["modal"].s()
            val texto = if (modal == "openFinishModal") d.resumen.textoCierre else d.resumen.textoCierreAnticipado(minutos)
            assertEquals(caso["texto"].s(), texto, "$modal series ${caso["series"]}")
            if (modal == "openEarlyFinishModal") {
                assertEquals(caso["aviso"].s(), d.avisoPendientes)
                assertEquals(caso["pendientes"].textos(), d.pendientes)
            }
        }
    }

    @Test
    fun restaurarRegistrosYEstados() {
        val diaPlan = Dia.desde(v["confirmar"].o()!!["dia"]!!)
        for (cj in v["restaurar"].a()) {
            val caso = cj.jsonObject
            val d = DiaEnCurso(diaPlan, 1, sesionId = "ses-1", zona = zonaVectores)
            if (caso["confirmadaLocal"].b()) {
                val s = d.ejercicios.getValue("pre-d2-0").series.toMutableList()
                s[1] = SerieLocal(reps = "7", kg = "85", confirmada = true)
                d.ponerSeries("pre-d2-0", s)
            }
            d.aplicarEstados(caso["estados"].a().map(EstadoEjercicio::desde))
            d.aplicarRegistros(caso["registros"].a().map(RegistroSesion::desde))
            val malos = diferenciaSesion(d, caso["sesion"].o())
            assertTrue(malos.isEmpty(), "${caso["nombre"]}: $malos")
            assertEquals(caso["estadosLocales"].o()!!.mapValues { it.value.s() }, d.estados, "${caso["nombre"]}: estados")
            val metaWeb = caso["meta"].o()!!.mapValues { (_, m) ->
                listOf(m.jsonObject["series_completadas"].i(), if (m.jsonObject["marcado_manualmente"].b()) 1 else 0)
            }
            assertEquals(metaWeb, d.meta.mapValues { listOf(it.value.seriesCompletadas, if (it.value.manual) 1 else 0) }, "${caso["nombre"]}: meta")
        }
    }

    @Test
    fun podaDeSustituciones() {
        val p = v["poda"].o()!!
        val mapas = p["mapas"].a().map(::valores)
        val casos = p["casos"].a()
        assertTrue(casos.size > 100)
        for (cj in casos) {
            val c = cj.jsonObject
            val opciones = c["opciones"].o()
            val (quedan, borradas) = SustitucionesEntreno.podar(
                mapas[c["mapa"].i()!!], c["semana"].i()!!, c["completados"].textos().toSet(), c["diaId"].s(),
                c["diaFinalizado"].b(), conservarDiaActual = opciones?.get("conservarDiaActual").b(),
            )
            val sinPrefetch = opciones?.get("sinPrefetch").b()
            val bien = quedan.keys.sorted() == c["quedan"].textos() && borradas.sorted() == c["invalidados"].textos() &&
                borradas.isNotEmpty() == c["guardo"].b() && (borradas.isNotEmpty() && !sinPrefetch) == c["prefetch"].b()
            assertTrue(bien, "mapa ${c["mapa"]} sem ${c["semana"]} ${c["completados"]} ${c["diaId"]}: ${quedan.keys.sorted()} vs ${c["quedan"]}")
        }
    }

    @Test
    fun comentarios() {
        val c = v["comentarios"].o()!!
        val dia = Dia.desde(v["confirmar"].o()!!["dia"]!!)
        val filas = c["filas"].a().map(Comentario::desde)
        for (cj in c["casos"].a()) {
            val caso = cj.jsonObject
            val elegidas = caso["filas"].textos().mapNotNull { id -> filas.firstOrNull { it.id == id } }
            val i = IndiceComentarios(elegidas)
            assertEquals(caso["porRef"].o()!!.mapValues { it.value.textos() }, i.porReferencia.mapValues { l -> l.value.map { it.id } })
            assertEquals(caso["sinLeer"].o()!!.mapValues { it.value.i() }, i.sinLeerPorClave)
            assertEquals(caso["total"].i(), i.totalEntreno)
            assertEquals(caso["dia"].i(), i.sinLeerDia(dia))
        }
        for (fj in c["fechas"].a()) {
            val f = fj.jsonObject
            assertEquals(f["texto"].s(), IndiceComentarios.fecha(f["iso"].s()!!, zonaVectores), "${f["iso"]}")
        }
    }

    @Test
    fun tiempoDeLaSesion() {
        val t = v["tiempo"].o()!!
        for (cj in t["fmt"].a()) assertEquals(cj.jsonObject["texto"].s(), TiempoEntreno.fmtTiempo(cj.jsonObject["s"].d()!!), "fmtTime($cj)")
        for (cj in t["crono"].a()) assertEquals(cj.jsonObject["texto"].s(), TiempoEntreno.fmtCrono(cj.jsonObject["ms"].d()!!), "fmtCrono($cj)")
        for (cj in t["minutos"].a()) {
            val c = cj.jsonObject
            assertEquals(c["min"].i(), TiempoEntreno.minutosSesion(c["inicio"].d(), c["ahora"].d()!!), "minutosSesion($c)")
        }
    }

    @Test
    fun descanso() {
        val base = v["ahora"].d()!!
        for ((k, pasos) in v["descanso"].a().withIndex()) {
            val b = BarraDescanso()
            var disparos = 0
            for (pj in pasos.a()) {
                val p = pj.jsonObject
                val ahora = base + p["t"].d()!!
                when (p["accion"].s()) {
                    "iniciar" -> b.iniciar(p["arg"].d() ?: 0.0, ahora)
                    "tick" -> if (b.tick(ahora)) disparos += 1
                    "restaurar" -> b.restaurar(ahora)
                    "saltar" -> b.ajustar("skip", ahora)
                    else -> b.ajustar(p["arg"].s() ?: "", ahora)
                }
                val d = b.descanso?.let { listOf(it.fin - base, it.objetivo, it.cierre - base, if (it.terminado) 1.0 else 0.0) }
                val dw = p["descanso"].o()?.let { listOf(it["fin"].d(), it["objetivo"].d(), it["cierre"].d(), if (it["terminado"].b()) 1.0 else 0.0) }
                val g = b.guardado?.let { listOf(it.endsAt - base, it.target, (it.autoCloseAt ?: 0.0) - base) }
                val gw = p["guardado"].o()?.let { listOf(it["fin"].d(), it["objetivo"].d(), it["cierre"].d()) }
                val ancho = b.porcentaje?.let { Js.texto(it) + "%" }
                val bien = d == dw && g == gw && disparos == p["disparos"].i() && b.visible == p["visible"].b() && b.listo == p["listo"].b() &&
                    b.texto == p["texto"].s() && b.textoObjetivo == p["objetivoTexto"].s() && ancho == p["ancho"].s()
                assertTrue(bien, "secuencia $k, ${p["accion"]} en ${p["t"]}: d=$d g=$g disparos=$disparos visible=${b.visible} listo=${b.listo} " +
                    "texto=${b.texto} objetivo=${b.textoObjetivo} ancho=$ancho vs $p")
            }
        }
    }

    @Test
    fun semanaBannersYPreguntas() {
        val s = v["semana"].o()!!
        val planes = s["planes"].a().map(::estructura)
        val banners = s["banners"].a()
        assertTrue(banners.size > 100)
        val f = fallasBanners(banners, planes)
        assertTrue(f.isEmpty(), "${f.size}: ${f.take(5)}")
        for (cj in s["avanzar"].a()) {
            val c = cj.jsonObject
            val p = SemanaEntreno.preguntaAvanzar(c["semana"].i()!!, c["total"].i()!!, c["offset"].i()!!, c["diaCompleto"].b())
            assertEquals(modalWeb(c["modal"]), modal(p), "avanzar $c")
        }
        for (cj in s["errores"].a()) {
            val c = cj.jsonObject
            val sinRed = c["caso"].s() == "red" || c["caso"].s() == "transitorio"
            val p = if (c["fn"].s() == "doAvanzarSemana") SemanaEntreno.errorAvanzar(sinRed) else SemanaEntreno.errorBloqueNuevo(sinRed)
            assertEquals(modalWeb(c["modal"]), modal(p), "${c["fn"]} ${c["caso"]}")
        }
        assertEquals(modalWeb(s["bloque"]), modal(SemanaEntreno.preguntaBloqueNuevo))
        val dc = s["diaCompleto"].o()
        if (dc != null) {
            val dias = dc["dias"].a().map(Dia::desde)
            for (cj in dc["casos"].a()) {
                val c = cj.jsonObject
                val p = if (c["mostrado"].b()) null else SemanaEntreno.preguntaDiaCompletado(dias, c["actual"].s()).first
                assertEquals(modalWeb(c["modal"]), modal(p), "día completado ${c["actual"]}")
            }
        }
    }

    @Test
    fun textosFijosIgualesALaWeb() {
        val t = v["textosFijos"].o()!!.mapValues { it.value.s() }
        val nuestros = mapOf(
            "diaVacio" to TextosEntreno.DIA_VACIO, "demo" to TextosEntreno.DEMO, "empezar" to TextosEntreno.EMPEZAR,
            "empezarDetalle" to TextosEntreno.EMPEZAR_DETALLE, "sinCerrar" to TextosEntreno.SIN_CERRAR,
            "porPrimeraSerie" to TextosEntreno.POR_PRIMERA_SERIE, "sinComentarios" to TextosEntreno.SIN_COMENTARIOS,
            "comentarioFallo" to TextosEntreno.COMENTARIO_FALLO, "cerrarSinSesion" to TextosEntreno.CERRAR_SIN_SESION,
            "cerrarFallo" to TextosEntreno.CERRAR_FALLO, "sinVariantes" to TextosEntreno.SIN_VARIANTES,
        )
        assertEquals(t, nuestros)
    }

    /** Privados: las estructuras de los planes activos reales (fuera del repo). */
    @Test
    fun planesReales() {
        val p = cargar(Vectores.privado("entreno"))
        val privadas = estructurasPrivadas(p["archivos"].textos())
        assertTrue(p["normalizar"].a().size > 50)
        val n = fallasNormalizar(p, privadas)
        assertTrue(n.isEmpty(), "normalizar: ${n.size}: ${n.take(3)}")
        val t = fallasTextos(p)
        assertTrue(t.isEmpty(), "textos: ${t.size}: ${t.take(5)}")
        assertTrue(p["ejercicios"].a().size > 1000)
        val e = fallasEjercicios(p)
        assertTrue(e.isEmpty(), "ejercicios: ${e.size}: ${e.take(5)}")
        val h = fallasHistorial(p)
        assertTrue(h.isEmpty(), "historial: ${h.size}: ${h.take(3)}")
        assertTrue(p["filas"].o()!!["casos"].a().size > 10_000)
        val f = fallasFilas(p)
        assertTrue(f.isEmpty(), "filas: ${f.size}: ${f.take(3)}")
        val b = fallasBanners(p["semana"].o()!!["banners"].a(), privadas)
        assertTrue(b.isEmpty(), "banners: ${b.size}: ${b.take(3)}")
    }

    /** `new Date(iso)` de V8 (node 26, TZ=America/Argentina/Buenos_Aires), con los bordes que iOS lee distinto. */
    @Test
    fun fechasComoJs() {
        val ar = java.util.TimeZone.getDefault()
        java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("America/Argentina/Buenos_Aires"))
        try {
            val casos = listOf(
                "2026-10-04T24:30:00Z" to null,                       // iOS: 1791160200000
                "2026-10-04T24:00:00Z" to 1791158400000L,
                "2026-10-04T10:00:00+19:00" to 1791039600000L,        // iOS: 1791118800000 (la toma como hora local)
                "2026-10-04T10:00:00-20:30" to 1791181800000L,        // iOS: 1791118800000
                "2026-10-04T10:00:00+18:00" to 1791043200000L,
                "2026-02-31" to 1772496000000L,
                "2026-02-31T10:00:00Z" to 1772532000000L,
                "2026-10-04 10:00:00" to 1791118800000L,
                "2026-10-04T10:00Z" to 1791108000000L,
                "2026-10-04T10:00:00.5+00:00" to 1791108000500L,
                "2026-10-04T10:00:00,123Z" to null,                   // iOS la lee
                "2026-10-04T10:00:00+0530" to 1791088200000L,
            )
            for ((iso, esperado) in casos) assertEquals(esperado, FechaJs.leer(iso)?.toEpochMilli(), iso)
        } finally {
            java.util.TimeZone.setDefault(ar)
        }
    }
}

/**
 * Revisión del 14-oct, hallazgo 1 (SustitutoConOtraCargaTests de iOS): con un sustituto de otra clase (uno lleva kg y el
 * otro no) la fila y la confirmación tienen que decidir lo mismo. Antes la fila usaba el sustituto y la confirmación el
 * plan: se borraba el kg o la serie no se podía registrar. La web tiene el mismo bug; acá va el arreglo.
 */
class SustitutoConOtraCargaTest {
    private fun dia(nombre: String): Dia = Dia.desde(
        Json.parseToJsonElement("""{"id":"d1","nombre":"Día 1","bloques":[{"nombre":"B","ejercicios":[{"id":"e1","nombre":"$nombre","series":3,"reps":"12"}]}]}"""),
    )

    private fun ejercicio(nombre: String): Ejercicio = Ejercicio.desde(Json.parseToJsonElement("""{"id":"e1","nombre":"$nombre","series":3,"reps":"12"}"""))

    @Test
    fun delPlanSinKgAUnoConKg() {
        val plan = dia("Crunch")
        val sustituto = ejercicio("Crunch en polea")
        assertTrue(ReglasEjercicio.sinKg(plan.bloques[0].ejercicios[0]) && !ReglasEjercicio.sinKg(sustituto))
        val d = DiaEnCurso(plan, 1, sesionId = "s1")
        d.escribir("e1", 0, "reps", "12")
        d.escribir("e1", 0, "kg", "20")
        val paso = d.confirmarSerie("e1", 0, efectivo = sustituto)
        assertEquals(true, d.ejercicios["e1"]?.series?.get(0)?.confirmada)
        assertEquals("20", d.ejercicios["e1"]?.series?.get(0)?.kg)
        val carga = paso.efectos.filterIsInstance<DiaEnCurso.Efecto.Encolar>().firstOrNull { it.kind == "carga" }?.payload
        assertEquals(20.0, carga?.get("datos")?.get("peso")?.comoNumero)
    }

    @Test
    fun delPlanConKgAUnoSinKg() {
        val plan = dia("Crunch en polea")
        val sustituto = ejercicio("Crunch")
        assertTrue(!ReglasEjercicio.sinKg(plan.bloques[0].ejercicios[0]) && ReglasEjercicio.sinKg(sustituto))
        val d = DiaEnCurso(plan, 1, sesionId = "s1")
        d.escribir("e1", 0, "reps", "15")
        d.confirmarSerie("e1", 0, efectivo = sustituto)
        assertEquals(true, d.ejercicios["e1"]?.series?.get(0)?.confirmada)   // antes: el ✓ no hacía nada (faltaba el kg)
    }
}
