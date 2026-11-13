import Testing
@testable import MyPumpReglas

/// La comida marcada plegada se tiene que poder abrir a la vista (bug del 13-nov: no podía destildar ni desmarcar).
struct PliegueComidaTests {
    let comi = MarcaComida(opcion: "A", estado: .comido, excluidos: [1])
    let salte = MarcaComida(opcion: "A", estado: .saltado)

    @Test func sinMarcaNuncaSePliega() {
        #expect(!PliegueComida.plegada(marca: nil, abierta: false))
        #expect(!PliegueComida.plegada(marca: nil, abierta: true))
    }

    @Test func marcadaSePliegaSalvoAbierta() {
        #expect(PliegueComida.plegada(marca: comi, abierta: false))
        #expect(!PliegueComida.plegada(marca: comi, abierta: true))
        #expect(PliegueComida.plegada(marca: salte, abierta: false))
    }

    @Test func elBotonDiceQueSePuedeDestildarYDesmarcar() {
        #expect(PliegueComida.rotuloAbrir(.comido) == "Destildar lo que no comiste o desmarcar")
        #expect(PliegueComida.rotuloAbrir(.saltado) == "Ver la comida o desmarcar")
    }
}
