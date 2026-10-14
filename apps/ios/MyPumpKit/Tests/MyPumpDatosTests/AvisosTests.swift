import Foundation
import Testing
@testable import MyPumpDatos

@Suite("Avisos: destinos, preferencias y token como la Capacitor")
struct AvisosTests {
    @Test func destinos() {
        #expect(DestinoAviso(destino: "train") == .entreno)
        #expect(DestinoAviso(destino: "diet") == .dieta)
        #expect(DestinoAviso(destino: "progress") == .progreso)
        #expect(DestinoAviso(destino: "myday") == .miDia)
        #expect(DestinoAviso(destino: "revision") == .revision)
        #expect(DestinoAviso(destino: "salud") == .misDatos)
        #expect(DestinoAviso(destino: "chat") == .chat)
        #expect(DestinoAviso(destino: "comentarios") == .chat)
        #expect(DestinoAviso(destino: nil) == .chat)
    }

    @Test func escenaDelLink() {
        #expect(DestinoAviso(escena: "diet") == .dieta)
        #expect(DestinoAviso(escena: "salud") == .misDatos)
        #expect(DestinoAviso(escena: "comentarios") == nil)
        #expect(DestinoAviso(escena: nil) == nil)
    }

    @Test func preferenciasSeMezclanSobreLasDeFabrica() {
        #expect(PreferenciasAvisos.leer(nil) == .porDefecto)
        #expect(PreferenciasAvisos.leer("basura") == .porDefecto)
        let p = PreferenciasAvisos.leer(#"{"check":{"on":false},"entreno":{"on":true,"hora":7}}"#)
        #expect(p.check == .init(on: false, hora: 11, min: 0))
        let q = PreferenciasAvisos.leer(#"{"check":{"hora":9,"min":30}}"#)
        #expect(q.check == .init(on: true, hora: 9, min: 30))
        #expect(PreferenciasAvisos.leer(q.texto) == q)
    }

    @Test func tokenEnMayusculas() {
        #expect(TokenPush.hex(Data([0x0a, 0xbc, 0xff, 0x00])) == "0ABCFF00")
    }
}
