import Foundation
import Testing
@testable import MyPumpReglas

@Suite("Alimento personalizado: la misma validación y conversión a 100 g que saveCustomFood")
struct AlimentoPropioNuevoTests {
    private func preparar(_ nombre: String = "Yogur X", kcal: Double? = nil, prot: Double? = nil, carb: Double? = nil,
                          fat: Double? = nil, unidad: String = "g", gramos: Double? = nil) -> Result<AlimentoPropioNuevo.Datos, ErrorFormulario> {
        AlimentoPropioNuevo.preparar(nombre: nombre, kcal: kcal, prot: prot, carb: carb, fat: fat, unidad: unidad,
                                     gramosPorUnidad: gramos, categoria: "lacteo")
    }

    @Test func enGramosNoSeConvierte() throws {
        let d = try preparar(kcal: 63, prot: 10, carb: 4.2, fat: 0.5).get()
        #expect(d == .init(nombre: "Yogur X", kcal: 63, prot: 10, carb: 4.2, fat: 0.5, unidad: "g", gramosPorUnidad: nil, categoria: "lacteo"))
    }

    @Test func porPorcionSeLlevaA100g() throws {
        // El caso del comentario de la web: porción de 30 g con 75 kcal = 250 kcal por 100 g.
        let d = try preparar(kcal: 75, prot: 3, carb: 10.1, fat: 2.25, unidad: "porcion", gramos: 30).get()
        #expect(d.kcal == 250)
        #expect(d.prot == 10)        // 3 × 100/30 = 10
        #expect(d.carb == 33.7)      // 33,666… → 33,7
        #expect(d.fat == 7.5)
        #expect(d.gramosPorUnidad == 30)
    }

    @Test func sinKcalSeDerivanDeLosMacros() throws {
        let d = try preparar(prot: 10, carb: 20, fat: 5).get()
        #expect(d.kcal == 165)       // 10·4 + 20·4 + 5·9
    }

    @Test func negativosYVaciosValenCero() throws {
        let d = try preparar(kcal: -5, prot: 12, carb: -1, fat: nil).get()
        #expect(d.kcal == 48)
        #expect(d.carb == 0)
        #expect(d.fat == 0)
    }

    @Test func errores() {
        #expect(preparar("   ", kcal: 100) == .failure(ErrorFormulario("El nombre es obligatorio.")))
        #expect(preparar(kcal: 0, prot: 0) == .failure(ErrorFormulario("Cargá al menos las calorías o algún macro.")))
        #expect(preparar(kcal: 90, unidad: "rebanada") == .failure(ErrorFormulario("Para \"rebanada\" indicá cuánto pesa 1 rebanada en gramos.")))
        #expect(preparar(kcal: 90, unidad: "rebanada", gramos: 0) == .failure(ErrorFormulario("Para \"rebanada\" indicá cuánto pesa 1 rebanada en gramos.")))
    }

    /// Desvío a propósito de la web (27-oct): lo que 100 g no pueden tener no se guarda, porque el motor de reemplazos
    /// calcula las porciones con eso.
    @Test func loQue100gNoPuedenTenerNoSeGuarda() throws {
        // El caso real: «1 rebanada de 15 g» con los valores del paquete = 833 kcal y 133 g de proteína por 100 g.
        #expect(preparar("Jamón de pavo", kcal: 125, prot: 20, carb: 5, fat: 3, unidad: "rebanada", gramos: 15)
                == .failure(ErrorFormulario("Esos valores no entran en 1 rebanada de 15 g: revisá cuánto pesa o los valores.")))
        let deUnPlato = ErrorFormulario("Esos valores no pueden ser de 100 g: si son de una porción, elegí «porción» y poné cuánto pesa.")
        #expect(preparar(kcal: 700, prot: 50, carb: 80, fat: 20) == .failure(deUnPlato))   // 150 g de macros
        #expect(preparar(kcal: 1200, prot: 10) == .failure(deUnPlato))                   // más que el aceite
        #expect(preparar(fat: 110) == .failure(deUnPlato))                                // las kcal derivadas también cuentan
        #expect(preparar(kcal: 1000, unidad: "ml")
                == .failure(ErrorFormulario("Esos valores no pueden ser de 100 ml: si son de una porción, elegí «porción» y poné cuánto pesa.")))
        #expect(preparar(kcal: 300, prot: 120, unidad: "unidad", gramos: 12.5)
                == .failure(ErrorFormulario("Esos valores no entran en 1 unidad de 12.5 g: revisá cuánto pesa o los valores.")))

        // Lo que sí puede ser: el aceite, un proteico con el redondeo de la etiqueta y un líquido denso por 100 ml.
        let aceite = try preparar(kcal: 884, fat: 100).get()
        #expect(aceite.kcal == 884)
        let proteico = try preparar(kcal: 128, prot: 24, carb: 3.3, fat: 2.9, unidad: "porcion", gramos: 30).get()
        #expect(proteico.prot == 80 && proteico.carb == 11 && proteico.fat == 9.7)   // 100,7 g: entra por el margen
        let denso = try preparar(kcal: 430, carb: 117, unidad: "ml").get()
        #expect(denso.carb == 117)
    }

    @Test func gramosPorUnidadSeIgnoraEnGramosYMl() throws {
        let d = try preparar(kcal: 50, unidad: "ml", gramos: 30).get()
        #expect(d.kcal == 50)
        #expect(d.gramosPorUnidad == nil)
    }

    @Test func renglonDeLaBase() {
        #expect(AlimentoPropioNuevo.base(unidad: "g", gramosPorUnidad: nil) == "Poné los valores por 100 g, como vienen en la etiqueta.")
        #expect(AlimentoPropioNuevo.base(unidad: "porcion", gramosPorUnidad: 30) == "Poné los valores de 1 porción (30 g), lo que realmente comés.")
        #expect(AlimentoPropioNuevo.base(unidad: "taza", gramosPorUnidad: nil) == "Poné los valores de 1 taza, lo que realmente comés.")
    }

    @Test func leerNumeroAceptaComa() {
        #expect(AlimentoPropioNuevo.leerNumero("1,5") == 1.5)
        #expect(AlimentoPropioNuevo.leerNumero(" 12 ") == 12)
        #expect(AlimentoPropioNuevo.leerNumero("") == nil)
        #expect(AlimentoPropioNuevo.leerNumero("abc") == nil)
    }
}
