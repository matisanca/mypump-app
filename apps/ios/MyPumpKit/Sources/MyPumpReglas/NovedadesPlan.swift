import Foundation
import MyPumpModelos

// «Novedades de tu plan» (2.3.0): qué cambió entre la versión del plan que el alumno ya vio y la que Mati acaba de
// publicar. Determinístico, sin IA: compara la rutina, la dieta y la suplementación que guardó el teléfono con las que
// llegan. Los mismos casos corren en Android y en la web (`apps/shared/fixtures/novedades/casos.json`).
//
// Reglas de los textos (Mati): cortos, sin dos puntos, guiones ni emojis; nunca RIR ni «cerca del fallo» (todo al fallo;
// el RIR ni se compara); las repes son referencia; nunca «tu coach» ni «tu entrenador», solo Mati. Nunca una dosis: de la
// suplementación se nombra el suplemento y nada más (la app solo recibe la natural; la farmacológica no llega).

/// Una parte del plan, tal como se la vio la última vez o como llega ahora.
public enum AreaPlan<T: Sendable>: Sendable {
    /// No se sabe (no llegó por la red, o nunca se guardó): no se compara.
    case desconocida
    /// El servidor dijo que no hay.
    case ninguna
    case hay(T)

    var valor: T? { if case .hay(let v) = self { return v }; return nil }
    var conocida: Bool { if case .desconocida = self { return false }; return true }
}

/// La foto del plan que se compara.
public struct FotoPlan: Sendable {
    public var rutina: AreaPlan<RutinaActiva>
    public var dieta: AreaPlan<DietaActiva>
    public var suplementacion: AreaPlan<SuplementacionGuia>

    public init(rutina: AreaPlan<RutinaActiva> = .desconocida, dieta: AreaPlan<DietaActiva> = .desconocida,
                suplementacion: AreaPlan<SuplementacionGuia> = .desconocida) {
        self.rutina = rutina; self.dieta = dieta; self.suplementacion = suplementacion
    }
}

public struct ParteNovedad: Codable, Equatable, Sendable, Identifiable {
    /// `rutina`, `dieta` o `suplementacion`: a dónde lleva el botón.
    public var area: String
    public var titular: String
    /// Bloque nuevo, dieta nueva o la primera vez que llega: se muestra lo principal, sin listar todo.
    public var grande: Bool
    public var lineas: [String]
    public var id: String { area }

    public init(area: String, titular: String, grande: Bool, lineas: [String]) {
        self.area = area; self.titular = titular; self.grande = grande; self.lineas = lineas
    }
}

/// Lo que se le muestra al alumno.
public struct ResumenNovedad: Codable, Equatable, Sendable {
    public var titular: String
    /// Una línea, para la tarjeta compacta.
    public var resumen: String
    public var partes: [ParteNovedad]

    public init(titular: String, resumen: String, partes: [ParteNovedad]) {
        self.titular = titular; self.resumen = resumen; self.partes = partes
    }
}

public enum NovedadesPlan {
    /// Cuántas líneas se ven por parte; si hay más, la última dice cuántos cambios quedan.
    public static let maxLineas = 4

    /// nil = nada que contar (sin cambios, solo cambió la semana, el RIR o datos internos).
    public static func calcular(antes: FotoPlan, despues: FotoPlan) -> ResumenNovedad? {
        var partes: [ParteNovedad] = []
        if antes.rutina.conocida, let nueva = despues.rutina.valor,
           let p = rutina(antes: antes.rutina.valor, despues: nueva) { partes.append(p) }
        if antes.dieta.conocida, let nueva = despues.dieta.valor,
           let p = dieta(antes: antes.dieta.valor?.estructura, despues: nueva.estructura) { partes.append(p) }
        if antes.suplementacion.conocida, let nueva = despues.suplementacion.valor,
           let p = suplementacion(antes: antes.suplementacion.valor, despues: nueva) { partes.append(p) }
        guard !partes.isEmpty else { return nil }
        if partes.count == 1 {
            return ResumenNovedad(titular: partes[0].titular, resumen: partes[0].lineas.first ?? partes[0].titular, partes: partes)
        }
        let nombres = partes.map { p in
            switch p.area { case "rutina": "tu rutina"; case "dieta": "tu dieta"; default: "tu suplementación" }
        }
        return ResumenNovedad(titular: "Mati actualizó tu plan", resumen: "Hay cambios en \(lista(nombres))", partes: partes)
    }

    // MARK: - Rutina

    struct EjercicioPlano {
        let clave: String
        let nombre: String
        let ejercicio: Ejercicio
    }

    static func ejercicios(_ d: Dia) -> [EjercicioPlano] {
        var vistos = Set<String>()
        var r: [EjercicioPlano] = []
        for b in d.bloques {
            for e in b.ejercicios {
                let nombre = limpio(e.nombre)
                let k = clave(nombre)
                guard !k.isEmpty, vistos.insert(k).inserted else { continue }
                r.append(EjercicioPlano(clave: k, nombre: nombre, ejercicio: e))
            }
        }
        return r
    }

    static func claveDia(_ d: Dia, _ i: Int) -> String {
        if let id = d.id.map(limpio), !id.isEmpty { return "id:\(id)" }
        return "i:\(i)"
    }

    /// «Tirón A — Ancho» → «Tirón A» (sin guiones en el texto); «TORSO A» → «Torso A».
    static func nombreDia(_ d: Dia, _ i: Int) -> String {
        var n = limpio(d.nombre ?? "")
        for sep in [" — ", " – ", " - "] {
            if let r = n.range(of: sep) { n = limpio(String(n[..<r.lowerBound])) }
        }
        if n.isEmpty { return "Día \(d.n ?? (i + 1))" }
        if n == n.uppercased(), n != n.lowercased() {
            n = n.split(separator: " ").map { p in p.prefix(1).uppercased() + p.dropFirst().lowercased() }.joined(separator: " ")
        }
        return n
    }

    /// Series y repes de una semana, como `getProgresionActual`: la semana se acota al largo de la progresión.
    static func pauta(_ e: Ejercicio, semana: Int) -> (Int?, String?) {
        if !e.progresion.isEmpty {
            let p = e.progresion[max(0, min(semana - 1, e.progresion.count - 1))]
            return (p.series, repsNormal(p.reps))
        }
        return (e.series, repsNormal(e.reps))
    }

    static func pautas(_ e: Ejercicio) -> [(Int?, String?)] {
        e.progresion.isEmpty ? [(e.series, repsNormal(e.reps))] : e.progresion.map { ($0.series, repsNormal($0.reps)) }
    }

    static func rutina(antes: RutinaActiva?, despues: RutinaActiva) -> ParteNovedad? {
        let nuevaE = despues.estructura
        let diasNuevos = nuevaE.dias.enumerated().map { ($0.offset, $0.element) }.filter { !ejercicios($0.1).isEmpty }
        guard !diasNuevos.isEmpty else { return nil }
        guard let antes else {
            return ParteNovedad(area: "rutina", titular: "Mati te armó tu rutina", grande: true,
                                lineas: lineasBloque(diasNuevos.map { nombreDia($0.1, $0.0) }, nuevos: 0))
        }
        let viejaE = antes.estructura
        let diasViejos = viejaE.dias.enumerated().map { ($0.offset, $0.element) }.filter { !ejercicios($0.1).isEmpty }

        // ¿Bloque nuevo? Otro plan, otra fase, o la mitad de los ejercicios (al menos 3) son nuevos.
        let clavesViejas = Set(diasViejos.flatMap { ejercicios($0.1).map(\.clave) })
        var clavesNuevas: [String] = []
        for (_, d) in diasNuevos { for e in ejercicios(d) where !clavesNuevas.contains(e.clave) { clavesNuevas.append(e.clave) } }
        let nuevos = clavesNuevas.filter { !clavesViejas.contains($0) }.count
        let otroPlan = { () -> Bool in
            if let a = viejaE.nombrePlan.map(clave), let b = nuevaE.nombrePlan.map(clave), !a.isEmpty, !b.isEmpty, a != b { return true }
            if let a = viejaE.fase, let b = nuevaE.fase, a != b { return true }
            return false
        }()
        if otroPlan || (nuevos >= 3 && nuevos * 2 >= clavesNuevas.count) {
            return ParteNovedad(area: "rutina", titular: "Mati te armó un bloque nuevo", grande: true,
                                lineas: lineasBloque(diasNuevos.map { nombreDia($0.1, $0.0) }, nuevos: nuevos))
        }

        let semana = max(1, despues.semanaActual)
        var lineas: [String] = []
        var usados = Set<String>()
        for (i, d) in diasNuevos {
            let k = claveDia(d, i)
            let nombre = nombreDia(d, i)
            guard let (_, v) = diasViejos.first(where: { claveDia($0.1, $0.0) == k }) else {
                lineas.append("Se suma un día nuevo, \(nombre)")
                continue
            }
            usados.insert(k)
            let viejos = ejercicios(v), actuales = ejercicios(d)
            let clavesV = Set(viejos.map(\.clave)), clavesA = Set(actuales.map(\.clave))
            let salen = viejos.filter { !clavesA.contains($0.clave) }
            let entran = actuales.filter { !clavesV.contains($0.clave) }
            let pares = min(salen.count, entran.count)
            for j in 0..<pares { lineas.append("En \(nombre) cambia \(salen[j].nombre) por \(entran[j].nombre)") }
            for e in entran.dropFirst(pares) { lineas.append("En \(nombre) se suma \(e.nombre)") }
            for e in salen.dropFirst(pares) { lineas.append("En \(nombre) sale \(e.nombre)") }
            for e in actuales {
                guard let anterior = viejos.first(where: { $0.clave == e.clave }) else { continue }
                let (sN, rN) = pauta(e.ejercicio, semana: semana)
                let (sV, rV) = pauta(anterior.ejercicio, semana: semana)
                if sN != sV || rN != rV {
                    if let f = formatoPauta(sN, rN) { lineas.append("En \(nombre), \(e.nombre) pasa a \(f)") }
                    continue
                }
                // Lo que viene después de esta semana (solo lo que las dos versiones tienen).
                let pn = pautas(e.ejercicio), pv = pautas(anterior.ejercicio)
                let desde = semana, hasta = min(pn.count, pv.count)
                if desde < hasta, (desde..<hasta).contains(where: { pn[$0].0 != pv[$0].0 || pn[$0].1 != pv[$0].1 }) {
                    lineas.append("En \(nombre), \(e.nombre) cambia en las próximas semanas")
                }
            }
        }
        for (i, v) in diasViejos where !usados.contains(claveDia(v, i)) {
            lineas.append("Sale el día \(nombreDia(v, i))")
        }
        guard !lineas.isEmpty else { return nil }
        return ParteNovedad(area: "rutina", titular: "Mati actualizó tu rutina", grande: false, lineas: recortar(lineas))
    }

    static func lineasBloque(_ dias: [String], nuevos: Int) -> [String] {
        var r: [String] = []
        if dias.count == 1 { r.append("Un día, \(dias[0])") }
        else if dias.count <= 5 { r.append("\(dias.count) días, \(lista(dias))") }
        else { r.append("\(dias.count) días de entrenamiento") }
        if nuevos == 1 { r.append("Un ejercicio nuevo") } else if nuevos > 1 { r.append("\(nuevos) ejercicios nuevos") }
        return r
    }

    /// «4 series de 8 a 10», «3 series», «10 a 12 repes». nil = no hay nada que decir.
    static func formatoPauta(_ series: Int?, _ reps: String?) -> String? {
        // Repes con texto que no puede salir (RIR, fallo, guiones, dos puntos): se dicen solo las series.
        let r = reps.flatMap { $0.isEmpty || $0.range(of: #"(?i)rir|fallo|[-–—:]"#, options: .regularExpression) != nil ? nil : $0 }
        let numerico = r.map { $0.range(of: #"^\d+( a \d+)?$"#, options: .regularExpression) != nil } ?? false
        switch (series, r) {
        case let (s?, r?): return numerico ? "\(s) \(s == 1 ? "serie" : "series") de \(r)" : "\(s) \(s == 1 ? "serie" : "series"), \(r)"
        case let (s?, nil): return "\(s) \(s == 1 ? "serie" : "series")"
        case let (nil, r?): return numerico ? "\(r) repes" : r
        default: return nil
        }
    }

    /// «8-10», «8 - 10», «8–10» → «8 a 10». Espacios de más afuera.
    static func repsNormal(_ r: String?) -> String? {
        guard let r else { return nil }
        var s = limpio(r)
        s = s.replacingOccurrences(of: #"^(\d+)\s*[-–—]\s*(\d+)$"#, with: "$1 a $2", options: .regularExpression)
        return s.isEmpty ? nil : s
    }

    // MARK: - Dieta

    struct ComidaPlana {
        let clave: String
        let nombre: String
        let comida: Comida
    }

    static func comidas(_ cs: [Comida]) -> [ComidaPlana] {
        var vistas = Set<String>()
        var r: [ComidaPlana] = []
        for (i, c) in cs.enumerated() {
            let nombre = limpio(c.nombre ?? "").isEmpty ? "Comida \(i + 1)" : limpio(c.nombre ?? "")
            let id = limpio(c.id)
            let k = id.isEmpty ? "n:\(clave(nombre))" : "id:\(id)"
            guard vistas.insert(k).inserted else { continue }
            r.append(ComidaPlana(clave: k, nombre: nombre, comida: c))
        }
        return r
    }

    static func alimentosDe(_ e: EstructuraDieta) -> [String] {
        let cs = e.tiposDia.isEmpty ? e.comidas : e.tiposDia.flatMap(\.comidas)
        var r: [String] = []
        for c in cs { for o in c.opciones { for a in o.alimentos {
            let k = clave(a.nombre)
            if !k.isEmpty, !r.contains(k) { r.append(k) }
        } } }
        return r
    }

    static func cantidadComidas(_ e: EstructuraDieta) -> Int {
        e.tiposDia.isEmpty ? comidas(e.comidas).count : (e.tiposDia.map { comidas($0.comidas).count }.max() ?? 0)
    }

    static func lineasDietaNueva(_ e: EstructuraDieta) -> [String] {
        var r: [String] = []
        let n = cantidadComidas(e)
        if e.tiposDia.count > 1 {
            let nombres = e.tiposDia.enumerated().map { limpio($0.element.nombre ?? "").isEmpty ? "Día \($0.offset + 1)" : limpio($0.element.nombre ?? "") }
            r.append("\(e.tiposDia.count) tipos de día, \(lista(nombres))")
        }
        if n == 1 { r.append("Una comida por día") } else if n > 1 { r.append("\(n) comidas por día") }
        let kcal = e.tiposDia.isEmpty ? e.macrosTarget?.kcal : (e.tiposDia.count == 1 ? e.tiposDia[0].macrosTarget?.kcal : nil)
        if let k = kcal, k > 0 { r.append("Objetivo de \(formatoKcal(k)) kcal por día") }
        return r
    }

    static func dieta(antes: EstructuraDieta?, despues: EstructuraDieta) -> ParteNovedad? {
        let todosNuevos = alimentosDe(despues)
        guard !todosNuevos.isEmpty else { return nil }
        guard let antes else {
            return ParteNovedad(area: "dieta", titular: "Mati te armó tu dieta", grande: true, lineas: lineasDietaNueva(despues))
        }
        let viejos = Set(alimentosDe(antes))
        let nuevos = todosNuevos.filter { !viejos.contains($0) }.count
        let cambioDeFormato = antes.tiposDia.isEmpty != despues.tiposDia.isEmpty
        if cambioDeFormato || (nuevos >= 4 && nuevos * 2 >= todosNuevos.count) {
            return ParteNovedad(area: "dieta", titular: "Mati te armó una dieta nueva", grande: true, lineas: lineasDietaNueva(despues))
        }

        var lineas: [String] = []
        if despues.tiposDia.isEmpty {
            lineas += lineasKcal(antes.macrosTarget, despues.macrosTarget, tipo: nil)
            lineas += lineasComidas(antes.comidas, despues.comidas, tipo: nil)
        } else {
            let varios = despues.tiposDia.count > 1
            var usados = Set<String>()
            for (i, t) in despues.tiposDia.enumerated() {
                let nombre = limpio(t.nombre ?? "").isEmpty ? "Día \(i + 1)" : limpio(t.nombre ?? "")
                let k = limpio(t.id).isEmpty ? "n:\(clave(nombre))" : "id:\(limpio(t.id))"
                guard let v = antes.tiposDia.enumerated().first(where: { (j, x) in
                    let nx = limpio(x.nombre ?? "").isEmpty ? "Día \(j + 1)" : limpio(x.nombre ?? "")
                    return (limpio(x.id).isEmpty ? "n:\(clave(nx))" : "id:\(limpio(x.id))") == k
                })?.element else {
                    lineas.append("Se suma un tipo de día, \(nombre)")
                    continue
                }
                usados.insert(k)
                lineas += lineasKcal(v.macrosTarget, t.macrosTarget, tipo: varios ? nombre : nil)
                lineas += lineasComidas(v.comidas, t.comidas, tipo: varios ? nombre : nil)
            }
            for (j, x) in antes.tiposDia.enumerated() {
                let nx = limpio(x.nombre ?? "").isEmpty ? "Día \(j + 1)" : limpio(x.nombre ?? "")
                let k = limpio(x.id).isEmpty ? "n:\(clave(nx))" : "id:\(limpio(x.id))"
                if !usados.contains(k) { lineas.append("Sale el tipo de día \(nx)") }
            }
        }
        guard !lineas.isEmpty else { return nil }
        return ParteNovedad(area: "dieta", titular: "Mati actualizó tu dieta", grande: false, lineas: recortar(lineas))
    }

    static func lineasKcal(_ a: Macros?, _ b: Macros?, tipo: String?) -> [String] {
        guard let x = a?.kcal, let y = b?.kcal, x > 0, y > 0, abs(y - x) >= 50 else { return [] }
        if let tipo { return ["En \(tipo), tu objetivo pasa a \(formatoKcal(y)) kcal"] }
        return ["Tu objetivo del día pasa a \(formatoKcal(y)) kcal"]
    }

    static func lineasComidas(_ viejas: [Comida], _ nuevas: [Comida], tipo: String?) -> [String] {
        var lineas: [String] = []
        let cv = comidas(viejas), cn = comidas(nuevas)
        func etiqueta(_ n: String) -> String { tipo.map { "\(n) (\($0))" } ?? n }
        for c in cn {
            guard let v = cv.first(where: { $0.clave == c.clave }) ?? cv.first(where: { clave($0.nombre) == clave(c.nombre) }) else {
                lineas.append("Se suma \(etiqueta(c.nombre))")
                continue
            }
            let nombre = etiqueta(c.nombre)
            let on = c.comida.opciones, ov = v.comida.opciones
            let varias = on.count > 1
            for i in 0..<min(on.count, ov.count) {
                let letra = limpio(on[i].nombre ?? "").isEmpty ? letraOpcion(i) : limpio(on[i].nombre ?? "")
                let lugar = varias ? "En \(nombre), opción \(letra)," : "En \(nombre)"
                let lugarComa = varias ? lugar : "\(lugar),"
                lineas += lineasOpcion(ov[i].alimentos, on[i].alimentos, lugar: lugar, lugarComa: lugarComa)
            }
            if on.count > ov.count {
                lineas.append(on.count - ov.count == 1 ? "En \(nombre) se suma una opción" : "En \(nombre) se suman \(on.count - ov.count) opciones")
            } else if ov.count > on.count {
                lineas.append(ov.count - on.count == 1 ? "En \(nombre) sale una opción" : "En \(nombre) salen \(ov.count - on.count) opciones")
            }
        }
        for v in cv where !cn.contains(where: { $0.clave == v.clave || clave($0.nombre) == clave(v.nombre) }) {
            lineas.append("Sale \(etiqueta(v.nombre))")
        }
        return lineas
    }

    static func lineasOpcion(_ viejos: [Alimento], _ nuevos: [Alimento], lugar: String, lugarComa: String) -> [String] {
        func planos(_ xs: [Alimento]) -> [(String, Alimento)] {
            var vistos = Set<String>()
            return xs.compactMap { a in
                let k = clave(a.nombre)
                guard !k.isEmpty, vistos.insert(k).inserted else { return nil }
                return (k, a)
            }
        }
        let v = planos(viejos), n = planos(nuevos)
        let kv = Set(v.map(\.0)), kn = Set(n.map(\.0))
        let salen = v.filter { !kn.contains($0.0) }, entran = n.filter { !kv.contains($0.0) }
        let pares = min(salen.count, entran.count)
        var r: [String] = []
        for j in 0..<pares { r.append("\(lugar) cambia \(limpio(salen[j].1.nombre)) por \(limpio(entran[j].1.nombre))") }
        for e in entran.dropFirst(pares) { r.append("\(lugar) se suma \(limpio(e.1.nombre))") }
        for e in salen.dropFirst(pares) { r.append("\(lugar) sale \(limpio(e.1.nombre))") }
        for (k, a) in n {
            guard let (_, b) = v.first(where: { $0.0 == k }) else { continue }
            let mismaUnidad = unidadNormal(a.unidad) == unidadNormal(b.unidad)
            let mismaCantidad: Bool = switch (a.qty, b.qty) {
            case let (x?, y?): abs(x - y) < 0.001
            case (nil, nil): true
            default: false
            }
            if !(mismaUnidad && mismaCantidad), let q = a.qty {
                r.append("\(lugarComa) \(limpio(a.nombre)) pasa a \(formatoCantidad(q, a.unidad))")
            }
        }
        return r
    }

    static func letraOpcion(_ i: Int) -> String {
        let letras = Array("ABCDEFGHIJ")
        return i < letras.count ? String(letras[i]) : "\(i + 1)"
    }

    static func unidadNormal(_ u: String?) -> String {
        let s = clave(u ?? "")
        return s.isEmpty ? "g" : s
    }

    /// «200 g», «1,5 unidades», «1 unidad».
    static func formatoCantidad(_ q: Double, _ unidad: String?) -> String {
        let num = formatoNumero(q)
        let u = unidadNormal(unidad)
        if ["unidad", "unidades", "u", "un", "ud", "uds"].contains(u) { return "\(num) \(num == "1" ? "unidad" : "unidades")" }
        return "\(num) \(limpio(unidad ?? "").isEmpty ? "g" : limpio(unidad ?? ""))"
    }

    static func formatoNumero(_ q: Double) -> String {
        let r = (q * 10).rounded() / 10
        // Un número absurdo (un error de tipeo en el editor) no puede cerrar la app: Int(r) se cae fuera de rango.
        if r == r.rounded() { return abs(r) < 1e15 ? String(Int(r)) : String(format: "%.0f", r) }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }

    /// 2400 → «2.400».
    static func formatoKcal(_ k: Double) -> String {
        guard abs(k) < 1e15 else { return String(format: "%.0f", k) }
        let n = Int(k.rounded())
        let s = String(abs(n))
        var r = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0, i % 3 == 0 { r.append(".") }
            r.append(ch)
        }
        return (n < 0 ? "-" : "") + String(r.reversed())
    }

    // MARK: - Suplementación

    static func suplementacion(antes: SuplementacionGuia?, despues: SuplementacionGuia) -> ParteNovedad? {
        func activos(_ s: SuplementacionGuia?) -> [(String, ItemSuplemento)] {
            var vistos = Set<String>()
            return (s?.items ?? []).compactMap { it in
                let k = clave(it.nombre)
                guard !k.isEmpty, clave(it.estado ?? "") != "sale", vistos.insert(k).inserted else { return nil }
                return (k, it)
            }
        }
        let n = activos(despues)
        guard let antes else {
            guard !n.isEmpty else { return nil }
            return ParteNovedad(area: "suplementacion", titular: "Mati te armó tu suplementación", grande: true,
                                lineas: [n.count == 1 ? "Un suplemento para tu día" : "\(n.count) suplementos para tu día"])
        }
        let v = activos(antes)
        let kv = Set(v.map(\.0)), kn = Set(n.map(\.0))
        var lineas: [String] = []
        for (k, it) in n where !kv.contains(k) { lineas.append("Se suma \(limpio(it.nombre))") }
        for (k, it) in v where !kn.contains(k) { lineas.append("Dejás de tomar \(limpio(it.nombre))") }
        for (k, it) in n {
            guard let (_, b) = v.first(where: { $0.0 == k }) else { continue }
            if firma(it) != firma(b) { lineas.append("Cambia cómo tomás \(limpio(it.nombre))") }
        }
        guard !lineas.isEmpty else { return nil }
        return ParteNovedad(area: "suplementacion", titular: "Mati actualizó tu suplementación", grande: false, lineas: recortar(lineas))
    }

    /// Lo que cuenta como «cambia cómo lo tomás»: la cantidad, el momento, las tomas, los días y si es opcional. La
    /// cantidad se compara pero nunca se muestra.
    static func firma(_ it: ItemSuplemento) -> String {
        let tomas = it.tomas.map { "\(clave($0.momento ?? ""))=\(clave($0.cantidad ?? ""))" }.joined(separator: ";")
        let dias = it.dias.map(clave).sorted().joined(separator: ",")
        return [clave(it.cantidad ?? ""), clave(it.momento ?? ""), tomas, dias, it.opcional ? "1" : "0"].joined(separator: "|")
    }

    // MARK: - Texto

    /// Si hay más de `maxLineas`, las primeras y «Y n cambios más».
    static func recortar(_ l: [String]) -> [String] {
        guard l.count > maxLineas else { return l }
        let resto = l.count - (maxLineas - 1)
        return Array(l.prefix(maxLineas - 1)) + [resto == 1 ? "Y un cambio más" : "Y \(resto) cambios más"]
    }

    /// «a», «a y b», «a, b y c».
    static func lista(_ xs: [String]) -> String {
        guard xs.count > 1 else { return xs.first ?? "" }
        return xs.dropLast().joined(separator: ", ") + " y " + xs.last!
    }

    /// Espacios de más afuera.
    static func limpio(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " ")
    }

    /// Para comparar: minúsculas, sin tildes (solo las vocales; la ñ queda) y sin espacios de más.
    static func clave(_ s: String) -> String {
        let mapa: [Character: Character] = [
            "á": "a", "à": "a", "ä": "a", "â": "a", "é": "e", "è": "e", "ë": "e", "ê": "e", "í": "i", "ì": "i", "ï": "i",
            "î": "i", "ó": "o", "ò": "o", "ö": "o", "ô": "o", "ú": "u", "ù": "u", "ü": "u", "û": "u",
        ]
        return String(limpio(s).lowercased().map { mapa[$0] ?? $0 })
    }
}
