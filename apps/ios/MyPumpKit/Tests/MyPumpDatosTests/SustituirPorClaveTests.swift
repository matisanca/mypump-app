import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 13: la hoja de "Sustituir ejercicio" guardaba la POSICIÓN del elegido. Si con la hoja
/// abierta llegaba el catálogo del servidor (`cargarCatalogo`), la lista cambiaba de orden y "Sustituir" aplicaba otro
/// ejercicio. Ahora elige por la clave del sustituto (el slug del catálogo).
@Suite("Sustituir un ejercicio elige por clave, no por posición", .serialized)
@MainActor
struct SustituirPorClaveTests {
    /// El del servidor: los mismos tres en otro orden y dos más que van primero.
    let catalogoDelServidor = try! CatalogoEjercicios(json: Data("""
    [{"slug_en":"Lat_Pulldown_Machine","name_en":"Lat Pulldown Machine","primary_muscle":"lats","equipment":"machine","patron_movimiento":"traccion_vertical"},
     {"slug_en":"Chin-Up","name_en":"Chin-Up","primary_muscle":"lats","equipment":"body only","patron_movimiento":"traccion_vertical"},
     {"slug_en":"Pullups","name_en":"Pullups","primary_muscle":"lats","equipment":"body only","patron_movimiento":"traccion_vertical"},
     {"slug_en":"V-Bar_Pulldown","name_en":"V-Bar Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"},
     {"slug_en":"Wide-Grip_Lat_Pulldown","name_en":"Wide-Grip Lat Pulldown","primary_muscle":"lats","equipment":"cable","patron_movimiento":"traccion_vertical"}]
    """.utf8))

    @Test func elElegidoSigueSiendoElMismoCuandoLlegaElCatalogo() async throws {
        let b = Banco()
        let m = b.modelo()
        let antes = m.sustitutos("jal-d1-0")
        #expect(antes.count >= 2)
        let i = antes.count - 1
        let elegido = antes[i]

        // Con la hoja abierta llega el catálogo del servidor.
        m.actualizarCatalogo(catalogoDelServidor)
        let despues = m.sustitutos("jal-d1-0")
        #expect(despues.count > antes.count)
        #expect(i < despues.count && despues[i].nombre != elegido.nombre, "la misma posición ya es otro ejercicio (lo que aplicaba la hoja)")

        let aplicado = try #require(m.sustituto("jal-d1-0", clave: elegido.clave))
        #expect(aplicado.nombre == elegido.nombre && aplicado.slug == elegido.slug)
        await m.sustituir("jal-d1-0", por: aplicado, fijar: false)
        #expect(m.efectivo(try #require(m.dia.ejercicio("jal-d1-0"))).ejercicio.nombre == elegido.nombre)
    }

    @Test func laClaveEsUnicaEnLaListaYSinSlugUsaNombreYEquipo() {
        let b = Banco()
        let m = b.modelo()
        m.actualizarCatalogo(catalogoDelServidor)
        let lista = m.sustitutos("jal-d1-0")
        #expect(Set(lista.map(\.clave)).count == lista.count)
        let sinSlug = SustitutoEjercicio(slug: nil, nombre: "Remo con banda", nombreIngles: nil, equipo: "Banda", equipoCrudo: "bands",
                                         musculo: nil, patron: nil, imagenes: .init(eccentric: nil, concentric: nil), mismoEquipo: false)
        #expect(sinSlug.clave == "Remo con banda|bands")
    }
}
