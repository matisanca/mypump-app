import Foundation

extension RutinaReloj {
    /// Una rutina de muestra (sin datos de nadie) para el simulador, las capturas y las pruebas: lo que ve el reloj con
    /// `-demo` o mientras el iPhone no mandó nada en la demo.
    /// La semana de la demo: cuatro días para elegir (el último ya hecho, para ver el tilde).
    public static let diasDemo: [DiaReloj] = [
        DiaReloj(id: "d1", nombre: "EMPUJE", numero: 1, ejercicios: 5, hecho: false),
        DiaReloj(id: "d2", nombre: "TIRÓN", numero: 2, ejercicios: 4, hecho: false),
        DiaReloj(id: "d3", nombre: "PIERNAS", numero: 3, ejercicios: 4, hecho: false),
        DiaReloj(id: "d4", nombre: "BRAZOS", numero: 4, ejercicios: 3, hecho: true),
    ]

    /// La demo de un día de la semana de muestra (`diasDemo`): EMPUJE es el de hoy; los otros, para probar el cambio de
    /// día sin iPhone.
    public static func demo(fecha: String, generada: Double, dia: String) -> RutinaReloj {
        guard dia != "d1", let d = diasDemo.first(where: { $0.id == dia }) else { return demo(fecha: fecha, generada: generada) }
        func ej(_ i: Int, _ slug: String, _ nombre: String, _ tipo: String, _ musculo: String, _ equipo: String, reps: Int, kg: Double) -> EjercicioReloj {
            EjercicioReloj(lugar: "\(slug)-\(dia)-\(i)", nombre: nombre, tipo: tipo, musculo: musculo, equipo: equipo, sinKg: false,
                           descansoSegundos: tipo == "compuesto" ? 120 : 75, repsPlan: "\(reps)",
                           series: (1...3).map { SerieReloj(numero: $0, repsSugeridas: reps, kgSugerido: kg) })
        }
        let ejercicios: [EjercicioReloj]
        switch dia {
        case "d2": ejercicios = [ej(0, "dominadas-lastre", "Dominadas con lastre", "compuesto", "lats", "body only", reps: 6, kg: 10),
                                 ej(1, "remo-barra", "Remo con barra", "compuesto", "middle back", "barbell", reps: 8, kg: 70),
                                 ej(2, "jalon-polea", "Jalón en polea", "compuesto", "lats", "cable", reps: 10, kg: 55),
                                 ej(3, "curl-barra", "Curl con barra", "aislamiento", "biceps", "barbell", reps: 10, kg: 30)]
        case "d3": ejercicios = [ej(0, "sentadilla", "Sentadilla", "compuesto", "quadriceps", "barbell", reps: 6, kg: 100),
                                 ej(1, "peso-muerto-rumano", "Peso muerto rumano", "compuesto", "hamstrings", "barbell", reps: 8, kg: 90),
                                 ej(2, "prensa", "Prensa", "compuesto", "quadriceps", "machine", reps: 10, kg: 180),
                                 ej(3, "gemelos-pie", "Gemelos de pie", "aislamiento", "calves", "machine", reps: 12, kg: 80)]
        default: ejercicios = [ej(0, "curl-mancuernas", "Curl con mancuernas", "aislamiento", "biceps", "dumbbell", reps: 10, kg: 14),
                               ej(1, "press-frances", "Press francés", "aislamiento", "triceps", "barbell", reps: 10, kg: 25),
                               ej(2, "extension-polea", "Extensión en polea", "aislamiento", "triceps", "cable", reps: 12, kg: 25)]
        }
        var r = RutinaReloj(cuenta: "demo", rutinaId: "demo", diaId: d.id, semana: 1, nombreDia: d.nombre, fecha: fecha, generada: generada,
                            ejercicios: ejercicios, diaFinalizado: d.hecho,
                            proximo: ProximoEntreno(diaId: "d1", nombre: "EMPUJE", ejercicios: 5), demo: true)
        r.dias = diasDemo
        return r
    }

    public static func demo(fecha: String, generada: Double) -> RutinaReloj {
        func series(_ n: Int, reps: Int?, kg: Double?) -> [SerieReloj] { (1...n).map { SerieReloj(numero: $0, repsSugeridas: reps, kgSugerido: kg) } }
        var r = RutinaReloj(
            cuenta: "demo", rutinaId: "demo", diaId: "d1", semana: 1, nombreDia: "EMPUJE", fecha: fecha, generada: generada,
            ejercicios: [
                EjercicioReloj(lugar: "press-banca-d1-0", nombre: "Press banca", bloque: "Pecho", tipo: "compuesto", musculo: "chest",
                               equipo: "barbell", sinKg: false, descansoSegundos: 150, repsPlan: "6-8",
                               series: series(3, reps: 8, kg: 80), anteriores: [MarcaReloj(kg: 80, reps: 8), MarcaReloj(kg: 77.5, reps: 8)]),
                EjercicioReloj(lugar: "press-inclinado-mancuernas-d1-1", nombre: "Press inclinado con mancuernas", bloque: "Pecho",
                               tipo: "compuesto", musculo: "chest", equipo: "dumbbell", sinKg: false, descansoSegundos: 120,
                               repsPlan: "8-10", series: series(3, reps: 10, kg: 26), anteriores: [MarcaReloj(kg: 26, reps: 10)]),
                EjercicioReloj(lugar: "press-militar-d1-2", nombre: "Press militar con barra", bloque: "Hombros", tipo: "compuesto",
                               musculo: "shoulders", equipo: "barbell", sinKg: false, descansoSegundos: 120, repsPlan: "8",
                               series: series(3, reps: 8, kg: 45), anteriores: [MarcaReloj(kg: 45, reps: 8)]),
                EjercicioReloj(lugar: "elevaciones-laterales-d1-3", nombre: "Elevaciones laterales", bloque: "Hombros",
                               tipo: "aislamiento", musculo: "shoulders", equipo: "dumbbell", sinKg: false, descansoSegundos: 60,
                               repsPlan: "12-15", series: series(3, reps: 15, kg: 10)),
                EjercicioReloj(lugar: "fondos-d1-4", nombre: "Fondos en paralelas", bloque: "Tríceps", tipo: "compuesto",
                               musculo: "triceps", equipo: "body only", sinKg: true, sinPeso: true, descansoSegundos: 90,
                               repsPlan: "10-12", series: series(2, reps: 12, kg: nil)),
            ],
            proximo: ProximoEntreno(diaId: "d2", nombre: "TIRÓN", ejercicios: 4), demo: true)
        r.dias = diasDemo
        return r
    }
}
