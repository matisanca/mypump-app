import Testing
@testable import MyPumpReglas

/// «Mi salud»: qué bloques van, qué dice la tarjeta de Revisión y cuándo no está (los mismos casos que `MiSaludTest.kt`).
struct MiSaludTests {
    @Test func bloquesEnOrdenYSoloLosQueVan() {
        #expect(MiSalud.bloques(.init(control: true, estudios: true, presion: true)) == [.control, .estudios, .presion, .recuperacion])
        #expect(MiSalud.bloques(.init(presion: true)) == [.presion, .recuperacion])
        #expect(MiSalud.bloques(.init(recuperacion: false)) == [])
    }

    @Test func sinBloquesNoHayTarjeta() {
        #expect(MiSalud.tarjeta(.init(recuperacion: false), pendientes: .init(estudios: "x", control: true, presion: "y")) == nil)
    }

    @Test func sinPendientesDiceLoQueHayAdentro() {
        let t = MiSalud.tarjeta(.init(control: true, estudios: true, presion: true), pendientes: .init())
        #expect(t == .init(linea: "Control, estudios, presión y recuperación", cuenta: 0))
        #expect(MiSalud.tarjeta(.init(), pendientes: .init())?.linea == "Recuperación")
        #expect(MiSalud.tarjeta(.init(presion: true), pendientes: .init())?.linea == "Presión y recuperación")
    }

    @Test func conPendientesLaPrimeraEnOrdenYLaCuentaDeCosas() {
        let todo = MiSalud.Partes(control: true, estudios: true, presion: true)
        let t = MiSalud.tarjeta(todo, pendientes: .init(estudios: TextosEstudios.ordenNueva, control: true, presion: MiSalud.faltanTomas(2)))
        #expect(t == .init(linea: "Tenés una orden nueva", cuenta: 3))
        #expect(MiSalud.tarjeta(todo, pendientes: .init(control: true, presion: MiSalud.repetirPresion)) == .init(linea: MiSalud.controlCerca, cuenta: 2))
        #expect(MiSalud.tarjeta(todo, pendientes: .init(presion: MiSalud.prepararPresion)) == .init(linea: MiSalud.prepararPresion, cuenta: 1))
    }

    @Test func unPendienteDeUnBloqueQueNoVaNoCuenta() {
        // Presión apagada: aunque quede una línea vieja, no se cuenta ni se muestra.
        let t = MiSalud.tarjeta(.init(estudios: false, presion: false), pendientes: .init(estudios: "x", presion: "y"))
        #expect(t == .init(linea: "Recuperación", cuenta: 0))
        // El control cerca cuenta con la sección de estudios, aunque todavía no haya «Próximo control».
        #expect(MiSalud.tarjeta(.init(estudios: true), pendientes: .init(control: true))?.cuenta == 1)
    }

    @Test func textosYEtiquetas() {
        #expect(MiSalud.titulo == "Mi salud")
        #expect(MiSalud.faltanTomas(1) == "Te falta 1 toma de presión")
        #expect(MiSalud.Bloque.presion.etiqueta == "mi-salud-bloque-presion")
    }
}
