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

/// Hallazgo 8 de la revisión del 15-oct: el aviso del domingo es de una sola vez (la app lo arma al abrir y al volver al
/// frente); repetido cada semana le seguía llegando para siempre a quien dejó la app.
@Suite("El próximo domingo a las 11")
struct ProximoDomingoTests {
    func fecha(_ s: String, _ zona: String) -> (Date, Calendar) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zona)!
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return (f.date(from: s)!, cal)
    }

    @Test func unMiercolesVaAlDomingoQueViene() {
        let (d, cal) = fecha("2026-10-14 20:00", "America/Argentina/Buenos_Aires")
        let c = AvisoDomingo.proximo(desde: d, calendario: cal)
        #expect(c?.year == 2026 && c?.month == 10 && c?.day == 18 && c?.hour == 11 && c?.minute == 0)
    }

    @Test func unDomingoAntesDeLas11EsHoyYDespuesLaSemanaQueViene() {
        let (antes, cal) = fecha("2026-10-18 10:59", "America/Argentina/Buenos_Aires")
        #expect(AvisoDomingo.proximo(desde: antes, calendario: cal)?.day == 18)
        let (justo, _) = fecha("2026-10-18 11:00", "America/Argentina/Buenos_Aires")
        #expect(AvisoDomingo.proximo(desde: justo, calendario: cal)?.day == 25)
    }

    @Test func conCambioDeHoraSigueSiendoALas11() {
        // Nueva York pasa al horario de verano el domingo 8-mar-2026 a las 2: el aviso de ese día sigue a las 11.
        let (d, cal) = fecha("2026-03-07 12:00", "America/New_York")
        let c = AvisoDomingo.proximo(desde: d, calendario: cal)
        #expect(c?.month == 3 && c?.day == 8 && c?.hour == 11)
    }
}
