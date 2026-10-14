import Foundation
import MyPumpModelos

// De muestras a registros: procesarSueno, procesarHRV, la colapsada de SAMPLES, los agregados y los entrenos del
// bridge (healthkit-bridge.js:513-891). Mismo recorrido, mismo orden y mismos redondeos.

extension PuenteSalud {

    // MARK: - Agregados (queryAggregated)

    /// `recolectar`, camino A: un registro por balde con valor > 0, redondeado al entero.
    public static func agregados(_ baldes: [BaldeDiario], tipo: String, reloj: RelojLocal) -> [RegistroSalud] {
        baldes.compactMap { b in
            guard b.valor > 0 else { return nil }
            return RegistroSalud(fecha: reloj.ymd(b.inicio), tipo: tipo, valor: jsRound(b.valor))
        }
    }

    // MARK: - Muestras (readSamples + agregación propia)

    /// `recolectar`, camino B: las muestras de un tipo, por fecha local de inicio (en el orden en que aparecen),
    /// colapsadas con suma, mediana o la última; redondeo a un decimal.
    public static func muestras(_ ms: [MuestraSalud], de m: TipoMuestra, reloj: RelojLocal) -> [RegistroSalud] {
        var orden: [String] = []
        var porFecha: [String: [(v: Double, t: Double)]] = [:]
        for s in ms {
            var v = s.valor
            guard v.isFinite else { continue }
            if let escala = m.escala, v <= 1 { v *= escala }   // SpO2/grasa a veces vienen 0-1
            if let factor = m.factor { v *= factor }           // m → km
            let f = reloj.ymd(s.inicio)
            if porFecha[f] == nil { orden.append(f) }
            porFecha[f, default: []].append((v, s.inicio))
        }
        return orden.compactMap { fecha in
            let xs = porFecha[fecha] ?? []
            let val: Double
            switch m.como {
            case .suma:
                val = xs.reduce(0) { $0 + $1.v }
            case .ultimo:
                // El peso del día es la última pesada; con dos a la misma hora, la que vino después (sort estable + pop).
                var ultimo = xs[0]
                for x in xs.dropFirst() where x.t >= ultimo.t { ultimo = x }
                val = ultimo.v
            case .mediana:
                val = mediana(xs.map(\.v)) ?? .nan
            }
            guard val > 0 else { return nil }
            return RegistroSalud(fecha: fecha, tipo: m.tipo, valor: jsRound(val * 10) / 10)
        }
    }

    /// `mediana(xs)`: la del medio, o el promedio de las dos del medio.
    public static func mediana(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted()
        let m = s.count >> 1
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    // MARK: - Sueño

    /// El bloque principal de cada fecha: con él se filtra la HRV nocturna (una siesta no define la ventana).
    public struct Noche: Sendable, Equatable {
        public let fecha: String
        public let ini: Double
        public let fin: Double
    }

    struct Evento {
        let ini: Double
        let fin: Double
        let st: String
        let src: String
    }

    private static let etapas: [(st: String, tipo: String)] = [("light", "sueno_ligero_min"), ("deep", "sueno_profundo_min"), ("rem", "sueno_rem_min")]

    /// `procesarSueno`: de muestras crudas a UNA fila de cada cosa por fecha (la del despertar).
    ///
    /// Con el plugin 8.9.3 cada muestra con estado conocido trae una etapa igual a ella misma, y el bridge le agrega un
    /// 'inbed' del largo de la muestra: por eso la eficiencia sale de (dormido / todo lo registrado por la fuente
    /// ganadora), y una noche sin sueño real se estima con todo lo registrado (en cama y despierto) al 90 %.
    public static func procesarSueno(_ muestras: [MuestraSalud], reloj: RelojLocal) -> (filas: [RegistroSalud], noches: [Noche]) {
        // Eventos: etapa + 'inbed' por cada muestra con estado; sin estado, la muestra es sueño ("asleep").
        var crudos: [Evento] = []
        for s in muestras {
            let src = !s.fuenteId.isEmpty ? s.fuenteId : (!s.fuenteNombre.isEmpty ? s.fuenteNombre : "?")
            if let estado = s.estadoSueno, s.fin > s.inicio {
                crudos.append(Evento(ini: s.inicio, fin: s.fin, st: estado.lowercased(), src: src))
                crudos.append(Evento(ini: s.inicio, fin: s.fin, st: "inbed", src: src))
            } else {
                crudos.append(Evento(ini: s.inicio, fin: s.fin, st: s.estadoSueno?.lowercased() ?? "asleep", src: src))
            }
        }
        // `.filter(fin > ini).sort((a, b) => a.ini - b.ini)`: el sort de JS es estable.
        let evs = crudos.enumerated().filter { $0.element.fin > $0.element.ini }
            .sorted { $0.element.ini != $1.element.ini ? $0.element.ini < $1.element.ini : $0.offset < $1.offset }
            .map(\.element)
        guard let primero = evs.first else { return ([], []) }

        // Noches: corte cuando hay más de 60 min sin nada, contados desde el fin del ÚLTIMO evento del bloque (no del
        // que termina más tarde): así lo hace la web, y una etapa que empieza más de una hora después del fin de la
        // anterior abre otro bloque aunque caiga adentro de una muestra larga.
        var noches: [[Evento]] = []
        var cur: [Evento] = [primero]
        for e in evs.dropFirst() {
            if e.ini - cur[cur.count - 1].fin > 60 * 60_000 { noches.append(cur); cur = [e] } else { cur.append(e) }
        }
        noches.append(cur)

        struct Dia {
            var total = 0.0, cama = 0.0, dormidoEnCama = 0.0
            var etapas: [(tipo: String, min: Double)] = []
            var estimado = false
            var fuente: String
            var masLargo = -1.0
            var medio: Int?
            var ini: Double, fin: Double
        }
        var porFecha: [String: Dia] = [:]

        for noche in noches {
            // Fuente ganadora: la que más minutos de sueño REAL aportó (en empate, la primera que aparece).
            var ordenSrc: [String] = []
            var porSrc: [String: [Evento]] = [:]
            for e in noche {
                if porSrc[e.src] == nil { ordenSrc.append(e.src) }
                porSrc[e.src, default: []].append(e)
            }
            var mejor = ordenSrc[0], mejorMin = -1.0
            for src in ordenSrc {
                let dormido = (porSrc[src] ?? []).filter(esDormido)
                let m = dormido.isEmpty ? 0 : minutos(dormido)
                if m > mejorMin { mejorMin = m; mejor = src }
            }
            let evsN = porSrc[mejor] ?? []
            let dormido = evsN.filter(esDormido)
            let enCama = evsN.filter { $0.st == "inbed" }

            let total: Double
            var estimado = false
            if !dormido.isEmpty { total = minutos(dormido) }
            else if !enCama.isEmpty { total = minutos(enCama) * 0.90; estimado = true }
            else { continue }
            guard total > 0 else { continue }

            // La noche va al día del DESPERTAR.
            let fin = evsN.map(\.fin).max() ?? 0
            let ini = evsN.map(\.ini).min() ?? 0
            let fecha = reloj.ymd(fin)

            var d = porFecha[fecha] ?? Dia(fuente: mejor, ini: ini, fin: fin)
            d.total += total
            if estimado { d.estimado = true }
            // Eficiencia: numerador y denominador de los mismos bloques (una siesta casi nunca trae 'en cama').
            if !enCama.isEmpty && !dormido.isEmpty {
                d.cama += minutos(enCama)
                d.dormidoEnCama += total
            }
            for (st, tipo) in etapas {
                let e = evsN.filter { $0.st == st }
                guard !e.isEmpty else { continue }
                if let i = d.etapas.firstIndex(where: { $0.tipo == tipo }) { d.etapas[i].min += minutos(e) }
                else { d.etapas.append((tipo, minutos(e))) }
            }
            // El punto medio (regularidad) es el del bloque más largo del día.
            if total > d.masLargo {
                d.masLargo = total
                let medio = reloj.horaYMinutos(((ini + fin) / 2).rounded(.down))
                d.medio = Int(jsRound(Double(medio.hora * 60 + medio.minutos)))
                d.fuente = mejor
                d.ini = ini; d.fin = fin
            }
            porFecha[fecha] = d
        }

        var filas: [RegistroSalud] = []
        var nochesOut: [Noche] = []
        for fecha in porFecha.keys.sorted() {
            guard let d = porFecha[fecha], d.total > 0 else { continue }
            var detalle: [String: JSONValue] = ["fuente_id": .texto(d.fuente)]
            if d.estimado { detalle["estimado"] = .bool(true) }
            filas.append(RegistroSalud(fecha: fecha, tipo: "sueno_min", valor: jsRound(d.total), detalle: .objeto(detalle)))
            if let medio = d.medio { filas.append(RegistroSalud(fecha: fecha, tipo: "sueno_medio_min", valor: Double(medio))) }
            if d.cama > 0 {
                filas.append(RegistroSalud(fecha: fecha, tipo: "sueno_eficiencia_pct", valor: jsRound(min(100, d.dormidoEnCama / d.cama * 100))))
            }
            for e in d.etapas { filas.append(RegistroSalud(fecha: fecha, tipo: e.tipo, valor: jsRound(e.min))) }
            nochesOut.append(Noche(fecha: fecha, ini: d.ini, fin: d.fin))
        }
        return (filas, nochesOut)
    }

    private static func esDormido(_ e: Evento) -> Bool { !e.st.isEmpty && e.st != "inbed" && e.st != "awake" }

    /// Minutos de la unión de los intervalos (`mins(fusionar(ivs))`).
    static func minutos(_ ivs: [Evento]) -> Double {
        let s = ivs.sorted { $0.ini < $1.ini }
        var out: [(ini: Double, fin: Double)] = []
        for iv in s {
            if let u = out.last, iv.ini <= u.fin { out[out.count - 1].fin = max(u.fin, iv.fin) }
            else { out.append((iv.ini, iv.fin)) }
        }
        return out.reduce(0) { $0 + ($1.fin - $1.ini) } / 60_000
    }

    // MARK: - HRV

    /// `procesarHRV`: la mediana por fecha, primero lo medido durante el sueño de esa noche, después lo de antes de
    /// las 10:00 y por último el resto del día.
    public static func procesarHRV(_ muestras: [MuestraSalud], noches: [Noche], reloj: RelojLocal) -> [RegistroSalud] {
        var orden: [String] = []
        var porClave: [String: (fecha: String, ventana: String, vals: [Double])] = [:]
        for s in muestras {
            let t = s.inicio, v = s.valor
            guard v > 0 else { continue }
            let fecha: String, ventana: String
            if let n = noches.first(where: { t >= $0.ini && t <= $0.fin }) {
                fecha = n.fecha; ventana = "nocturna"
            } else {
                fecha = reloj.ymd(t)
                ventana = reloj.horaYMinutos(t).hora < 10 ? "madrugada" : "dia"
            }
            let k = "\(fecha)|\(ventana)"
            if porClave[k] == nil { orden.append(k) }
            porClave[k, default: (fecha, ventana, [])].vals.append(v)
        }
        func rango(_ ventana: String) -> Int { ventana == "nocturna" ? 0 : ventana == "madrugada" ? 1 : 2 }
        var fechas: [String] = []
        var mejor: [String: (rango: Int, ventana: String, vals: [Double])] = [:]
        for k in orden {
            guard let g = porClave[k] else { continue }
            let r = rango(g.ventana)
            if let m = mejor[g.fecha], r >= m.rango { continue }
            if mejor[g.fecha] == nil { fechas.append(g.fecha) }
            mejor[g.fecha] = (r, g.ventana, g.vals)
        }
        return fechas.compactMap { f in
            guard let m = mejor[f], let med = mediana(m.vals) else { return nil }
            return RegistroSalud(fecha: f, tipo: "hrv_ms", valor: jsRound(med),
                                 detalle: .objeto(["metrica": .texto(metricaHRV), "ventana": .texto(m.ventana), "n": .numero(Double(m.vals.count))]))
        }
    }

    // MARK: - Entrenos

    /// `recolectarEntrenos`: cada entrenamiento con su FC media y máxima, calculadas con las muestras de frecuencia
    /// cardíaca que caen adentro (el plugin no las trae en el payload).
    public static func entrenos(_ ws: [EntrenoCrudo], fc: [MuestraSalud]) -> [EntrenoSalud] {
        let hr = fc.enumerated()
            .filter { $0.element.inicio.isFinite && $0.element.valor.isFinite && $0.element.valor > 0 }
            .sorted { $0.element.inicio != $1.element.inicio ? $0.element.inicio < $1.element.inicio : $0.offset < $1.offset }
            .map { (t: $0.element.inicio, v: $0.element.valor) }
        func fcDe(_ ini: Double, _ fin: Double) -> (media: Double?, max: Double?) {
            guard !hr.isEmpty, fin > ini else { return (nil, nil) }
            let dentro = hr.filter { $0.t >= ini && $0.t <= fin }
            guard !dentro.isEmpty else { return (nil, nil) }
            let suma = dentro.reduce(0) { $0 + $1.v }
            return (jsRound(suma / Double(dentro.count)), jsRound(dentro.reduce(0) { $1.v > $0 ? $1.v : $0 }))
        }
        return ws.map { w in
            let dur = w.duracion / 60
            let km = w.distancia.map { $0 / 1000 }
            let fc = fcDe(w.inicio, w.fin)
            return EntrenoSalud(
                inicio: RelojLocal.iso(w.inicio),
                fin: RelojLocal.iso(w.fin),
                tipo: w.tipo.isEmpty ? "other" : w.tipo,
                duracionMin: dur.isFinite ? jsRound(dur * 10) / 10 : nil,
                kcal: w.kcal.flatMap { $0.isFinite ? jsRound($0) : nil },
                distanciaKm: km.flatMap { $0.isFinite && $0 > 0 ? jsRound($0 * 100) / 100 : nil },
                fcMedia: fc.media,
                fcMax: fc.max,
                fuente: fuente)
        }
    }

    // MARK: - Lecturas partidas

    /// La identidad de una muestra al pegar las dos mitades de una ventana partida (el plugin no da el UUID): misma
    /// fuente, mismo inicio, fin y valor = la misma muestra.
    public static func sinRepetidas(_ a: [MuestraSalud], _ b: [MuestraSalud]) -> [MuestraSalud] {
        struct Clave: Hashable { let ini: Double, fin: Double, valor: Double, fuente: String }
        var vistas = Set<Clave>()
        return (a + b).filter { vistas.insert(Clave(ini: $0.inicio, fin: $0.fin, valor: $0.valor, fuente: $0.fuenteId)).inserted }
    }
}
