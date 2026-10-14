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

    /// El aviso del domingo llega como un mensaje de Mati (pedido del 14-oct): su nombre de título, como sus mensajes del
    /// chat, y escrito como él les escribe a los clientes (sin dos puntos, guiones ni emojis). Abre Revisión.
    @Test func elAvisoDelDomingoEsUnMensajeDeMati() {
        #expect(AvisoDomingo.titulo == "Mati")
        #expect(AvisoDomingo.id == "1002", "el id de la Capacitor: reprogramar pisa el viejo")
        #expect(AvisoDomingo.diaDeLaSemana == 1 && AvisoDomingo.hora == 11 && AvisoDomingo.minuto == 0)
        #expect(DestinoAviso(destino: AvisoDomingo.destino) == .revision)
        let cuerpo = AvisoDomingo.cuerpo
        #expect(!cuerpo.isEmpty)
        #expect(![":", "-", "–", "—"].contains { cuerpo.contains($0) }, "\(cuerpo)")
        #expect(!cuerpo.unicodeScalars.contains { $0.properties.isEmojiPresentation }, "\(cuerpo)")
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

@Suite("El link pegado, como index.html")
struct LinkPegadoTests {
    @Test func elMensajeEnteroDeWhatsApp() {
        let t = "abcdefghij0123456789ABCDEFGHIJ_-"
        #expect(FormatoToken.extraer(de: "Hola! Este es tu link para entrar a MyPump: https://app.mypumpteam.com/?t=\(t)\nCualquier cosa me escribís") == t)
        #expect(FormatoToken.extraer(de: "app.mypumpteam.com/cliente.html?t=\(t)") == t)
        #expect(FormatoToken.extraer(de: t) == t)
        #expect(FormatoToken.extraer(de: "hola") == nil)
    }
}
