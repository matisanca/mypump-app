import Foundation

extension RutinaReloj {
    /// Una rutina de muestra (sin datos de nadie) para el simulador, las capturas y las pruebas: lo que ve el reloj con
    /// `-demo` o mientras el iPhone no mandó nada en la demo.
    public static func demo(fecha: String, generada: Double) -> RutinaReloj {
        func series(_ n: Int, reps: Int?, kg: Double?) -> [SerieReloj] { (1...n).map { SerieReloj(numero: $0, repsSugeridas: reps, kgSugerido: kg) } }
        return RutinaReloj(
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
            proximo: ProximoEntreno(diaId: "d2", nombre: "TIRÓN", ejercicios: 5), demo: true)
    }
}
