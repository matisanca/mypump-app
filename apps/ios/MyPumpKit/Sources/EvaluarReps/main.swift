import Foundation
import MyPumpRepsHerramientas
import MyPumpReloj

/// El paso de la app (lo que hace `EstadoReloj.proponer`).
enum PasoApp {
    static func nuevo() -> (Bool, ContadorReps.Resultado) -> Int? {
        var p = PropuestaSerie()
        return { enDescanso, c in enDescanso ? nil : p.proponer(c) }
    }
}

// evaluar-reps: el error del contador de reps por familia sobre lo exportado del modo calibración (tanda 4).
//
//   swift run --package-path apps/ios/MyPumpKit evaluar-reps <archivos .mpcal o carpetas>…
//       [--guardadas]        usa lo que contó el reloj en vivo (por defecto vuelve a contar con el contador de hoy)
//       [--csv salida.csv]   una serie por renglón
//   swift run --package-path apps/ios/MyPumpKit evaluar-reps --sintetico <carpeta>
//       escribe archivos de ejemplo con señales sintéticas (para probar la herramienta sin un reloj)
//
// Las series donde el reloj propuso las reps y se confirmaron sin tocar salen en una tabla aparte y no deciden: su
// etiqueta puede ser la del reloj. Deciden las de etiqueta independiente (sin propuesta o corregidas a mano).

var args = Array(CommandLine.arguments.dropFirst())
@MainActor func sacar(_ flag: String, conValor: Bool) -> String?? {
    guard let i = args.firstIndex(of: flag) else { return nil }
    args.remove(at: i)
    guard conValor else { return .some(nil) }
    guard i < args.count else { FileHandle.standardError.write(Data("falta el valor de \(flag)\n".utf8)); exit(2) }
    return .some(args.remove(at: i))
}

if let carpeta = sacar("--sintetico", conValor: true), let c = carpeta {
    let urls = try EvaluacionReps.escribirSinteticos(en: URL(fileURLWithPath: c))
    print("\(urls.count) archivos sintéticos en \(c)")
    exit(0)
}
if sacar("--gimnasio", conValor: false) != nil {
    let semillas: [UInt64] = Array(1...12)
    print("SINTÉTICO: cuadros inyectados de un modelo del brazo. No es una medición real.")
    func correr(_ f: FamiliaMovimiento, _ c: EscenarioGimnasio.Caso, _ s: EscenarioGimnasio.Sensores, reps: Int = 10) -> EscenarioGimnasio.Marcador {
        var m = EscenarioGimnasio.Marcador()
        for x in semillas {
            let l = EscenarioGimnasio.armar(f, caso: c, reps: reps, semilla: x)
            m.sumar(reales: l.reps, EscenarioGimnasio.enVivo(l, sensores: s, proponer: PasoApp.nuevo()))
        }
        return m
    }
    print("\nPor familia (serie normal, 10 reps):")
    var total = EscenarioGimnasio.Marcador()
    for f in FamiliaMovimiento.allCases {
        let m = correr(f, .normal, .vivo)
        print("  \(f.nombre.padding(toLength: 26, withPad: " ", startingAt: 0)) \(m.texto)")
        total.corridas += m.corridas; total.propuestas += m.propuestas; total.exactas += m.exactas
        total.dentroDeUno += m.dentroDeUno; total.conError += m.conError; total.falsas += m.falsas; total.demoras += m.demoras
    }
    print("  TOTAL                      \(total.texto)")
    print("\nCasos difíciles (familias: curl, press, sentadilla, jalón, lateral):")
    let cinco: [FamiliaMovimiento] = [.curl, .empujeHorizontal, .sentadilla, .tironVertical, .elevacionLateral]
    for c in EscenarioGimnasio.Caso.allCases {
        var m = EscenarioGimnasio.Marcador()
        for f in cinco { for x in semillas {
            let l = EscenarioGimnasio.armar(f, caso: c, semilla: x)
            m.sumar(reales: l.reps, EscenarioGimnasio.enVivo(l, proponer: PasoApp.nuevo()))
        } }
        print("  \(c.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)) \(m.texto)")
    }
    print("\nSensores (serie normal, mismas cinco familias):")
    for s in EscenarioGimnasio.Sensores.allCases {
        var m = EscenarioGimnasio.Marcador()
        for f in cinco { for x in semillas {
            let l = EscenarioGimnasio.armar(f, semilla: x)
            m.sumar(reales: l.reps, EscenarioGimnasio.enVivo(l, sensores: s, proponer: PasoApp.nuevo()))
        } }
        print("  \(s.rawValue.padding(toLength: 20, withPad: " ", startingAt: 0)) \(m.texto)")
    }
    exit(0)
}
if let cual = sacar("--banco", conValor: true), let cual {
    // Datos separados: `ajuste` son las semillas con las que se pueden elegir umbrales; `validacion` tiene otras semillas y
    // otro modelo del cuerpo (ver `EscenarioGimnasio.OtroCuerpo`) y no se mira para ajustar.
    let otro = cual == "validacion"
    let semillas: [UInt64] = otro ? Array(101...124) : Array(1...12)
    let repsPosibles = otro ? [6, 8, 10, 12, 15] : [10]
    func correr(_ f: [FamiliaMovimiento], _ c: EscenarioGimnasio.Caso) -> EscenarioGimnasio.Marcador {
        var m = EscenarioGimnasio.Marcador()
        for fam in f { for x in semillas {
            let l = EscenarioGimnasio.armar(fam, caso: c, reps: repsPosibles[Int(x) % repsPosibles.count], semilla: x, otroCuerpo: otro)
            m.sumar(reales: l.reps, EscenarioGimnasio.enVivo(l, proponer: PasoApp.nuevo()))
        } }
        return m
    }
    print("Banco \(cual): \(semillas.count) semillas por combinación. SINTÉTICO.")
    let todas = FamiliaMovimiento.allCases
    let cinco: [FamiliaMovimiento] = [.curl, .empujeHorizontal, .sentadilla, .tironVertical, .elevacionLateral]
    let normal = correr(todas, .normal)
    print("  \("normal, 16 familias".padding(toLength: 26, withPad: " ", startingAt: 0)) \(normal.texto)")
    for c in [EscenarioGimnasio.Caso.lentaAlFallo, .pausaMedia, .drop, .arrancaEnDescanso, .aproximacion, .munecaInmovil] {
        print("  \(c.rawValue.padding(toLength: 26, withPad: " ", startingAt: 0)) \(correr(cinco, c).texto)")
    }
    var inventadas = 0, corridas = 0
    for c in EscenarioGimnasio.casosSinSerie {
        let m = correr(todas, c)
        inventadas += m.falsas; corridas += m.corridas
        print("  \(c.rawValue.padding(toLength: 26, withPad: " ", startingAt: 0)) \(m.corridas) corridas · inventó \(m.falsas)")
    }
    print("  SIN SERIE, total: inventó \(inventadas) de \(corridas)")
    exit(0)
}
if let rutaNeg = sacar("--descansos", conValor: true), let rutaNeg {
    // Lo real antes de la serie: lo que se proponga ahí es inventado. `--inicios 44,177,…` da, en orden, el segundo en que arranca
    // la primera serie de cada ventana, marcado a mano mirando la señal (privado: no va al repo; 0 saltea esa ventana).
    let inicios = (sacar("--inicios", conValor: true) ?? nil)?.split(separator: ",").compactMap { Double($0) } ?? []
    let (registros, _) = EvaluacionReps.leer([URL(fileURLWithPath: rutaNeg)])
    var falsos = 0, con = 0
    for (k, (_, r)) in registros.enumerated() where k < inicios.count {
        guard let c = EvaluacionReps.descansoAntesDeLaSerie(r, inicio: inicios[k]) else { continue }
        con += 1
        let v = EvaluacionReps.repetirEnVivo(c)
        if v.propuesta != nil { falsos += 1 }
        print("serie \(r.encabezado.orden): \(c.cuadros.count / 100) s de descanso · propone \(v.propuesta.map(String.init) ?? "nada")")
    }
    print("descansos reales: \(con) · propuestas inventadas: \(falsos)")
    exit(0)
}
if let rutaCosto = sacar("--costo", conValor: true), let rutaCosto {
    // Lo que tarda un conteo de 120 s (en la Mac): el reloj cuenta una vez por segundo.
    let (registros, _) = EvaluacionReps.leer([URL(fileURLWithPath: rutaCosto)])
    var tiempos: [Double] = [], total = 0
    for _ in 0..<5 { for (_, r) in registros {
        let cs = Array(r.cuadros.suffix(12_000))
        let t0 = DispatchTime.now().uptimeNanoseconds
        total += ContadorReps.contar(cs).reps
        tiempos.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
    } }
    tiempos.sort()
    print(String(format: "conteo de hasta 120 s: mediana %.2f ms · peor %.2f ms (\(tiempos.count) corridas, suma \(total))", tiempos[tiempos.count / 2], tiempos.last ?? 0))
    exit(0)
}
if let rutaVivo = sacar("--vivo", conValor: true), let r = rutaVivo {
    // Repite cada serie real segundo a segundo, como en el reloj: qué proponía y cuándo. Los nombres no salen.
    let (registros, fallas) = EvaluacionReps.leer([URL(fileURLWithPath: r)])
    for f in fallas { FileHandle.standardError.write(Data("no se pudo leer \(f)\n".utf8)) }
    if registros.isEmpty { print("El archivo no trae series: el reloj no grabó ninguna (o no llegaron al iPhone)."); exit(0) }
    for (_, reg) in registros {
        let e = reg.encabezado
        let propias = EvaluacionReps.repetirEnVivo(reg)
        print("\(e.orden) · \(e.familia.rawValue) serie \(e.serie) · cargó \(e.reps) · antes contó \(e.contadas.map(String.init) ?? "-") y propuso \(e.propuesta.map(String.init) ?? "-") · ahora propone \(propias.propuesta.map(String.init) ?? "nada")\(propias.propuesta.map { _ in String(format: " a los %.0f s (del fin de la ventana)", propias.segundosAntesDelFin ?? 0) } ?? "") · \(propias.propuestasDescartadas) cambios · \(e.fuente)")
    }
    exit(0)
}
let guardadas = sacar("--guardadas", conValor: false) != nil
let csv = sacar("--csv", conValor: true) ?? nil
guard !args.isEmpty else {
    print("uso: evaluar-reps <archivos .mpcal o carpetas>… [--guardadas] [--csv salida.csv] | --sintetico <carpeta>")
    exit(2)
}
let (registros, fallas) = EvaluacionReps.leer(args.map { URL(fileURLWithPath: $0) })
for f in fallas { FileHandle.standardError.write(Data("no se pudo leer \(f)\n".utf8)) }
let informe = EvaluacionReps.evaluar(registros, recontar: !guardadas)
print("\(registros.count) series · \(guardadas ? "conteo guardado en el reloj" : "recontadas con el contador de hoy")")
print(EvaluacionReps.texto(informe))
if let csv { try EvaluacionReps.csv(informe).write(toFile: csv, atomically: true, encoding: .utf8) }
