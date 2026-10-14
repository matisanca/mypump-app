package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson
import java.util.Objects

/**
 * De muestras a registros: procesarSueno, procesarHRV, la colapsada de SAMPLES, los agregados y los entrenos del bridge
 * (healthkit-bridge.js:513-891). Mismo recorrido, mismo orden y mismos redondeos. Gemelo de SaludAgregacion.swift.
 */
object AgregacionSalud {

    // MARK: Agregados (queryAggregated)

    /** `recolectar`, camino A: un registro por balde con valor > 0, redondeado al entero. */
    fun agregados(baldes: List<BaldeDiario>, tipo: String, reloj: RelojLocal, plataforma: PlataformaSalud): List<RegistroSalud> =
        baldes.mapNotNull { b -> if (b.valor > 0) RegistroSalud(reloj.ymd(b.inicio), tipo, jsRound(b.valor), plataforma.fuente) else null }

    // MARK: Muestras (readSamples + agregación propia)

    /**
     * `recolectar`, camino B: las muestras de un tipo, por fecha local de inicio (en el orden en que aparecen), colapsadas
     * con suma, mediana o la última; redondeo a un decimal.
     */
    fun muestras(ms: List<MuestraSalud>, m: PuenteSalud.TipoMuestra, reloj: RelojLocal, plataforma: PlataformaSalud): List<RegistroSalud> {
        val orden = ArrayList<String>()
        val porFecha = HashMap<String, MutableList<Pair<Double, Double>>>()
        for (s in ms) {
            var v = s.valor
            if (!v.isFinite()) continue
            m.escala?.let { if (v <= 1) v *= it }   // SpO2/grasa a veces vienen 0-1
            m.factor?.let { v *= it }               // m → km
            val f = reloj.ymd(s.inicio)
            porFecha.getOrPut(f) { orden += f; ArrayList() } += v to s.inicio
        }
        val como = PuenteSalud.como(m, plataforma)
        return orden.mapNotNull { fecha ->
            val xs = porFecha.getValue(fecha)
            val v = when (como) {
                PuenteSalud.Como.SUMA -> xs.fold(0.0) { a, x -> a + x.first }
                PuenteSalud.Como.ULTIMO -> {
                    // El peso del día es la última pesada; con dos a la misma hora, la que vino después (sort estable + pop).
                    var ultimo = xs[0]
                    for (x in xs.drop(1)) if (x.second >= ultimo.second) ultimo = x
                    ultimo.first
                }
                PuenteSalud.Como.MEDIANA -> mediana(xs.map { it.first }) ?: Double.NaN
            }
            if (v > 0) RegistroSalud(fecha, m.tipo, jsRound(v * 10) / 10, plataforma.fuente) else null
        }
    }

    /** `mediana(xs)`: la del medio, o el promedio de las dos del medio. */
    fun mediana(xs: List<Double>): Double? {
        if (xs.isEmpty()) return null
        val s = xs.sorted()
        val m = s.size shr 1
        return if (s.size % 2 == 1) s[m] else (s[m - 1] + s[m]) / 2
    }

    // MARK: Sueño

    /** El bloque principal de cada fecha: con él se filtra la HRV nocturna (una siesta no define la ventana). */
    data class Noche(val fecha: String, val ini: Double, val fin: Double)

    data class Sueno(val filas: List<RegistroSalud>, val noches: List<Noche>)

    private class Evento(val ini: Double, val fin: Double, val st: String, val src: String)

    private val ETAPAS = listOf("light" to "sueno_ligero_min", "deep" to "sueno_profundo_min", "rem" to "sueno_rem_min")

    private class Dia(var fuente: String, var ini: Double, var fin: Double) {
        var total = 0.0
        var cama = 0.0
        var dormidoEnCama = 0.0
        val etapas = ArrayList<Pair<String, Double>>()
        var estimado = false
        var masLargo = -1.0
        var medio: Int? = null
    }

    /**
     * `procesarSueno`: de muestras crudas a UNA fila de cada cosa por fecha (la del despertar).
     *
     * Con el plugin 8.9.3 cada muestra de iPhone con estado conocido trae una etapa igual a ella misma, y el bridge le
     * agrega un 'inbed' del largo de la muestra: por eso la eficiencia sale de (dormido / todo lo registrado por la fuente
     * ganadora), y una noche sin sueño real se estima con todo lo registrado (en cama y despierto) al 90 %. Una sesión con
     * etapas (Health Connect) da una etapa por evento y un 'inbed' con el largo de la sesión.
     */
    fun procesarSueno(muestras: List<MuestraSalud>, reloj: RelojLocal, plataforma: PlataformaSalud): Sueno {
        val crudos = ArrayList<Evento>()
        for (s in muestras) {
            val src = s.fuenteId.ifEmpty { s.fuenteNombre.ifEmpty { "?" } }
            val etapas = s.etapas?.filter { it.fin > it.inicio }
            if (!etapas.isNullOrEmpty()) {
                for (g in etapas) crudos += Evento(g.inicio, g.fin, Js.minusculas(g.estado), src)
                crudos += Evento(s.inicio, s.fin, "inbed", src)
            } else if (s.estadoSueno != null && s.fin > s.inicio) {
                crudos += Evento(s.inicio, s.fin, Js.minusculas(s.estadoSueno), src)
                crudos += Evento(s.inicio, s.fin, "inbed", src)
            } else {
                crudos += Evento(s.inicio, s.fin, s.estadoSueno?.let(Js::minusculas) ?: "asleep", src)
            }
        }
        // `.filter(fin > ini).sort((a, b) => a.ini - b.ini)`: el sort de JS es estable.
        val evs = SemanticaJs.ordenarEstable(crudos.filter { it.fin > it.ini }) { a, b -> compararJs(a.ini, b.ini) }
        if (evs.isEmpty()) return Sueno(emptyList(), emptyList())

        // Noches: corte cuando hay más de 60 min sin nada, contados desde el fin del ÚLTIMO evento del bloque (no del que
        // termina más tarde): así lo hace la web.
        val noches = ArrayList<List<Evento>>()
        var cur = arrayListOf(evs[0])
        for (e in evs.drop(1)) {
            if (e.ini - cur[cur.size - 1].fin > 60 * 60_000) {
                noches += cur
                cur = arrayListOf(e)
            } else {
                cur += e
            }
        }
        noches += cur

        val porFecha = HashMap<String, Dia>()
        for (noche in noches) {
            // Fuente ganadora: la que más minutos de sueño REAL aportó (en empate, la primera que aparece).
            val ordenSrc = ArrayList<String>()
            val porSrc = HashMap<String, MutableList<Evento>>()
            for (e in noche) porSrc.getOrPut(e.src) { ordenSrc += e.src; ArrayList() } += e
            var mejor = ordenSrc[0]
            var mejorMin = -1.0
            for (src in ordenSrc) {
                val dormido = porSrc.getValue(src).filter(::esDormido)
                val m = if (dormido.isEmpty()) 0.0 else minutos(dormido)
                if (m > mejorMin) {
                    mejorMin = m
                    mejor = src
                }
            }
            val evsN = porSrc.getValue(mejor)
            val dormido = evsN.filter(::esDormido)
            val enCama = evsN.filter { it.st == "inbed" }

            var estimado = false
            val total = when {
                dormido.isNotEmpty() -> minutos(dormido)
                enCama.isNotEmpty() -> {
                    estimado = true
                    minutos(enCama) * 0.90
                }
                else -> continue
            }
            if (!(total > 0)) continue

            // La noche va al día del DESPERTAR.
            val fin = evsN.maxOf { it.fin }
            val ini = evsN.minOf { it.ini }
            val fecha = reloj.ymd(fin)

            val d = porFecha.getOrPut(fecha) { Dia(mejor, ini, fin) }
            d.total += total
            if (estimado) d.estimado = true
            // Eficiencia: numerador y denominador de los mismos bloques (una siesta casi nunca trae 'en cama').
            if (enCama.isNotEmpty() && dormido.isNotEmpty()) {
                d.cama += minutos(enCama)
                d.dormidoEnCama += total
            }
            for ((st, tipo) in ETAPAS) {
                val e = evsN.filter { it.st == st }
                if (e.isEmpty()) continue
                val i = d.etapas.indexOfFirst { it.first == tipo }
                if (i >= 0) d.etapas[i] = tipo to (d.etapas[i].second + minutos(e)) else d.etapas += tipo to minutos(e)
            }
            // El punto medio (regularidad) es el del bloque más largo del día.
            if (total > d.masLargo) {
                d.masLargo = total
                val (h, mi) = reloj.horaYMinutos(Math.floor((ini + fin) / 2))
                d.medio = h * 60 + mi
                d.fuente = mejor
                d.ini = ini
                d.fin = fin
            }
        }

        val filas = ArrayList<RegistroSalud>()
        val nochesOut = ArrayList<Noche>()
        for (fecha in porFecha.keys.sorted()) {
            val d = porFecha.getValue(fecha)
            if (!(d.total > 0)) continue
            val detalle = linkedMapOf<String, ValorJson>("fuente_id" to ValorJson.Texto(d.fuente))
            if (d.estimado) detalle["estimado"] = ValorJson.Booleano(true)
            filas += RegistroSalud(fecha, "sueno_min", jsRound(d.total), plataforma.fuente, ValorJson.Objeto(detalle))
            d.medio?.let { filas += RegistroSalud(fecha, "sueno_medio_min", it.toDouble(), plataforma.fuente) }
            if (d.cama > 0) {
                filas += RegistroSalud(fecha, "sueno_eficiencia_pct", jsRound(minimoJs(100.0, d.dormidoEnCama / d.cama * 100)), plataforma.fuente)
            }
            for ((tipo, m) in d.etapas) filas += RegistroSalud(fecha, tipo, jsRound(m), plataforma.fuente)
            nochesOut += Noche(fecha, d.ini, d.fin)
        }
        return Sueno(filas, nochesOut)
    }

    private fun esDormido(e: Evento): Boolean = e.st.isNotEmpty() && e.st != "inbed" && e.st != "awake"

    /** Minutos de la unión de los intervalos (`mins(fusionar(ivs))`). */
    private fun minutos(ivs: List<Evento>): Double {
        val s = ivs.sortedWith { a, b -> compararJs(a.ini, b.ini) }
        val out = ArrayList<DoubleArray>()
        for (iv in s) {
            val u = out.lastOrNull()
            if (u != null && iv.ini <= u[1]) u[1] = maxOf(u[1], iv.fin) else out += doubleArrayOf(iv.ini, iv.fin)
        }
        return out.fold(0.0) { a, x -> a + (x[1] - x[0]) } / 60_000
    }

    // MARK: HRV

    /**
     * `procesarHRV`: la mediana por fecha, primero lo medido durante el sueño de esa noche, después lo de antes de las
     * 10:00 y por último el resto del día.
     */
    fun procesarHRV(muestras: List<MuestraSalud>, noches: List<Noche>, reloj: RelojLocal, plataforma: PlataformaSalud): List<RegistroSalud> {
        class Grupo(val fecha: String, val ventana: String, val vals: MutableList<Double>)
        val orden = ArrayList<String>()
        val porClave = HashMap<String, Grupo>()
        for (s in muestras) {
            val t = s.inicio
            val v = s.valor
            if (!(v > 0)) continue
            val n = noches.firstOrNull { t >= it.ini && t <= it.fin }
            val fecha: String
            val ventana: String
            if (n != null) {
                fecha = n.fecha
                ventana = "nocturna"
            } else {
                fecha = reloj.ymd(t)
                ventana = if (reloj.horaYMinutos(t).first < 10) "madrugada" else "dia"
            }
            val k = "$fecha|$ventana"
            porClave.getOrPut(k) { orden += k; Grupo(fecha, ventana, ArrayList()) }.vals += v
        }
        fun rango(ventana: String): Int = if (ventana == "nocturna") 0 else if (ventana == "madrugada") 1 else 2
        val fechas = ArrayList<String>()
        val mejor = HashMap<String, Pair<Int, Grupo>>()
        for (k in orden) {
            val g = porClave.getValue(k)
            val r = rango(g.ventana)
            val m = mejor[g.fecha]
            if (m != null && r >= m.first) continue
            if (m == null) fechas += g.fecha
            mejor[g.fecha] = r to g
        }
        return fechas.mapNotNull { f ->
            val g = mejor.getValue(f).second
            val med = mediana(g.vals) ?: return@mapNotNull null
            RegistroSalud(
                f, "hrv_ms", jsRound(med), plataforma.fuente,
                ValorJson.objeto(
                    "metrica" to ValorJson.Texto(plataforma.metricaHRV), "ventana" to ValorJson.Texto(g.ventana),
                    "n" to ValorJson.Numero(g.vals.size.toDouble()),
                ),
            )
        }
    }

    // MARK: Entrenos

    /**
     * `recolectarEntrenos`: cada entrenamiento con su FC media y máxima, calculadas con las muestras de frecuencia
     * cardíaca que caen adentro (el plugin no las trae en el payload).
     */
    fun entrenos(ws: List<EntrenoCrudo>, fc: List<MuestraSalud>, plataforma: PlataformaSalud): List<EntrenoSalud> {
        val hr = SemanticaJs.ordenarEstable(fc.filter { it.inicio.isFinite() && it.valor.isFinite() && it.valor > 0 }) { a, b ->
            compararJs(a.inicio, b.inicio)
        }.map { it.inicio to it.valor }

        fun fcDe(ini: Double, fin: Double): Pair<Double?, Double?> {
            if (hr.isEmpty() || !(fin > ini)) return null to null
            val dentro = hr.filter { it.first >= ini && it.first <= fin }
            if (dentro.isEmpty()) return null to null
            val suma = dentro.fold(0.0) { a, x -> a + x.second }
            return jsRound(suma / dentro.size) to jsRound(dentro.fold(0.0) { a, x -> if (x.second > a) x.second else a })
        }
        return ws.map { w ->
            val dur = w.duracion / 60
            val km = w.distancia?.let { it / 1000 }
            val (media, max) = fcDe(w.inicio, w.fin)
            EntrenoSalud(
                inicio = RelojLocal.iso(w.inicio),
                fin = RelojLocal.iso(w.fin),
                tipo = w.tipo.ifEmpty { "other" },
                duracionMin = if (dur.isFinite()) jsRound(dur * 10) / 10 else null,
                kcal = w.kcal?.takeIf { it.isFinite() }?.let(::jsRound),
                distanciaKm = km?.takeIf { it.isFinite() && it > 0 }?.let { jsRound(it * 100) / 100 },
                fcMedia = media,
                fcMax = max,
                fuente = plataforma.fuente,
            )
        }
    }

    // MARK: Lecturas partidas

    /** La identidad de una muestra al pegar las dos mitades de una ventana partida (el plugin no da un id): misma fuente,
     *  mismo inicio, fin y valor = la misma muestra. La web arma la clave con el texto (`${s.value}`): 0 y −0 son el
     *  mismo valor, y dos NaN también. */
    private class Clave(val ini: Double, val fin: Double, val valor: Double, val fuente: String) {
        override fun equals(other: Any?): Boolean =
            other is Clave && mismo(ini, other.ini) && mismo(fin, other.fin) && mismo(valor, other.valor) && fuente == other.fuente

        private fun mismo(a: Double, b: Double): Boolean = a == b || (a.isNaN() && b.isNaN())

        override fun hashCode(): Int = Objects.hash(h(ini), h(fin), h(valor), fuente)

        private fun h(d: Double): Int = if (d == 0.0) 0 else d.hashCode()
    }

    fun sinRepetidas(a: List<MuestraSalud>, b: List<MuestraSalud>): List<MuestraSalud> {
        val vistas = HashSet<Clave>()
        return (a + b).filter { vistas.add(Clave(it.inicio, it.fin, it.valor, it.fuenteId)) }
    }

    /** `a - b` como comparador de un sort de JS, para números que no son NaN (−0 y +0 empatan). */
    private fun compararJs(a: Double, b: Double): Int = if (a < b) -1 else if (a > b) 1 else 0

    /** `Math.min(a, b)` de Swift (`min(100, x)`), sin NaN acá: el divisor es > 0. */
    private fun minimoJs(a: Double, b: Double): Double = if (b < a) b else a
}
