import Foundation
import Testing
@testable import MyPumpDatos

@Suite("Avisos: destinos, preferencias y token como la Capacitor")
struct AvisosTests {
    @Test func destinos() {
        #expect(DestinoAviso(destino: "train") == .entreno)
        #expect(DestinoAviso(destino: "diet") == .dieta)
        #expect(DestinoAviso(destino: "progress") == .fuerza)
        #expect(DestinoAviso(destino: "myday") == .recuperacion)
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

    private static let t = "abcdefghij0123456789ABCDEFGHIJ_-"

    /// Un token válido no puede salir con «No reconocí ese link» por lo que le agrega el copiar y pegar.
    @Test(arguments: [
        "\u{200E}\(t)\u{200F}",                                          // marcas invisibles de dirección (WhatsApp)
        "\u{FEFF}https://app.mypumpteam.com/?t=\(t)\u{200B}",
        "\(t).",                                                         // el punto final de la frase
        "«\(t)»",
        "(https://app.mypumpteam.com/acceso/\(t))",
        "Tu link: https://app.mypumpteam.com/acceso/\(t) entrá cuando puedas",
        "https://app.mypumpteam.com/? t=\(t)",                            // un espacio del autocorrector
        "https://app.mypumpteam.com/?t=\n\(t)",
        "  \n\(t)\n  ",
        "?t=\(t)",
    ])
    func loQueAgregaElPegarNoLoRompe(pegado: String) {
        #expect(FormatoToken.extraer(de: pegado) == Self.t, "no reconoció: \(pegado.debugDescription)")
    }

    @Test(arguments: [
        "https://app.mypumpteam.com/",
        "hola este mensaje largo no trae ningun link",
        "holaestemensajelargonotraeningunlink ok",
        "https://app.mypumpteam.com/?t=corto",
        "https://app.mypumpteam.com/?t=corto hola que tal todo",
        "https://app.mypumpteam.com/?\(t)",
        "",
    ])
    func loQueNoTraeTokenSigueSinReconocerse(pegado: String) {
        #expect(FormatoToken.extraer(de: pegado) == nil)
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

    /// R2 de la 2.0.3: con la semana de revisión completa, el aviso de esta semana se saltea; incompleta, como siempre.
    @Test func conLaSemanaCompletaSeSalteaElDomingo() {
        let zona = "America/Argentina/Buenos_Aires"
        let (sabado, cal) = fecha("2026-10-31 18:00", zona)
        #expect(AvisoDomingo.proximo(desde: sabado, semanaCompleta: true, calendario: cal)?.day == 8)
        let s = AvisoDomingo.proximo(desde: sabado, semanaCompleta: false, calendario: cal)
        #expect(s?.month == 11 && s?.day == 1 && s?.hour == 11 && s?.minute == 0)
        #expect(s == AvisoDomingo.proximo(desde: sabado, calendario: cal))
        let (domingo, _) = fecha("2026-11-01 10:30", zona)
        #expect(AvisoDomingo.proximo(desde: domingo, semanaCompleta: true, calendario: cal)?.day == 8)
        #expect(AvisoDomingo.proximo(desde: domingo, semanaCompleta: false, calendario: cal)?.day == 1)
        // El lunes la semana es otra: completa, el domingo de ESTA semana se saltea.
        let (lunes, _) = fecha("2026-11-02 09:00", zona)
        #expect(AvisoDomingo.proximo(desde: lunes, semanaCompleta: false, calendario: cal)?.day == 8)
        #expect(AvisoDomingo.proximo(desde: lunes, semanaCompleta: true, calendario: cal)?.day == 15)
    }

    /// Sin la semana completa, la cuenta nueva da lo mismo que la de siempre (`nextDate`), en cualquier hora de dos semanas.
    @Test func incompletaEsIgualALaDeSiempre() {
        for zona in ["America/Argentina/Buenos_Aires", "America/New_York", "Europe/Madrid"] {
            var (d, cal) = fecha("2026-10-24 00:00", zona)
            for _ in 0..<(14 * 24 * 2) {
                let a = AvisoDomingo.proximo(desde: d, calendario: cal)
                let b = AvisoDomingo.proximo(desde: d, semanaCompleta: false, calendario: cal)
                #expect(a?.year == b?.year && a?.month == b?.month && a?.day == b?.day && a?.hour == b?.hour && a?.minute == b?.minute, "\(d)")
                d.addTimeInterval(1_800)
            }
        }
    }

    @Test func conCambioDeHoraSigueSiendoALas11() {
        // Nueva York pasa al horario de verano el domingo 8-mar-2026 a las 2: el aviso de ese día sigue a las 11.
        let (d, cal) = fecha("2026-03-07 12:00", "America/New_York")
        let c = AvisoDomingo.proximo(desde: d, calendario: cal)
        #expect(c?.month == 3 && c?.day == 8 && c?.hour == 11)
    }
}
