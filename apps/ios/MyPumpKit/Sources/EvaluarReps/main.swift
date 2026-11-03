import Foundation
import MyPumpRepsHerramientas

// evaluar-reps: el error del contador de reps por familia sobre lo exportado del modo calibración (tanda 4).
//
//   swift run --package-path apps/ios/MyPumpKit evaluar-reps <archivos .mpcal o carpetas>…
//       [--guardadas]        usa lo que contó el reloj en vivo (por defecto vuelve a contar con el contador de hoy)
//       [--csv salida.csv]   una serie por renglón
//   swift run --package-path apps/ios/MyPumpKit evaluar-reps --sintetico <carpeta>
//       escribe archivos de ejemplo con señales sintéticas (para probar la herramienta sin un reloj)

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
