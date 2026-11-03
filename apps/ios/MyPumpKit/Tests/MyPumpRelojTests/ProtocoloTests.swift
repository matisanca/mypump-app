import Foundation
import Testing
import MyPumpReglas
@testable import MyPumpReloj

// El protocolo entre el iPhone y el reloj: ida y vuelta de cada mensaje, las reglas de versión y lo que no se entiende.

let HOY = "2026-11-03"
let T0 = 1_793_700_000_000.0

func ida(_ m: MensajeReloj) throws -> SobreReloj {
    let sobre = SobreReloj(m, enviado: T0)
    return try ProtocoloReloj.leer(ProtocoloReloj.diccionario(sobre))
}

@Suite struct ProtocoloTests {
    @Test func cadaMensajeVaYVuelveIgual() throws {
        let rutina = RutinaReloj.demo(fecha: HOY, generada: T0)
        let eventos = [
            EventoEnCola(.iniciar(diaId: "d1", semana: 3), creado: T0),
            EventoEnCola(.serie(diaId: "d1", semana: 3, lugar: "press-banca-d1-0", indice: 0, reps: 8, kg: 82.5), creado: T0 + 1),
            EventoEnCola(.serie(diaId: "d1", semana: 3, lugar: "fondos-d1-4", indice: 1, reps: 12, kg: nil), creado: T0 + 2),
            EventoEnCola(.terminar(diaId: "d1", semana: 3), creado: T0 + 3),
        ]
        let mensajes: [MensajeReloj] = [
            .pedirRutina, .rutina(rutina), .eventos(eventos),
            .acuse([AcuseEvento(id: eventos[0].id, resultado: .aplicado), AcuseEvento(id: eventos[1].id, resultado: .rechazado, motivo: "otro día"), AcuseEvento(id: eventos[0].id, resultado: .pendiente)]),
            .incompatible(version: 3),
            .sinRutina(motivo: "Sin rutina activa"),
        ]
        for m in mensajes {
            let s = try ida(m)
            #expect(s.mensaje == m)
            #expect(s.v == ProtocoloReloj.version)
            #expect(s.enviado == T0)
        }
    }

    @Test func elDiccionarioSoloLlevaTiposDePropiedades() throws {
        let d = try ProtocoloReloj.diccionario(SobreReloj(.pedirRutina, enviado: T0))
        #expect(Set(d.keys) == ["v", "mp"])
        #expect(d["v"] is Int)
        #expect(d["mp"] is Data)
        #expect(PropertyListSerialization.propertyList(d, isValidFor: .binary))
    }

    @Test func unaSerieSinKgNoMandaElCampo() throws {
        let e = EventoReloj.serie(diaId: "d1", semana: 1, lugar: "x", indice: 0, reps: 10, kg: nil)
        let json = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        #expect(!json.contains("\"kg\""))
        #expect(try JSONDecoder().decode(EventoReloj.self, from: Data(json.utf8)) == e)
    }

    @Test func unaVersionMasNuevaSeRechazaSinLeerla() throws {
        var sobre = SobreReloj(.pedirRutina, enviado: T0)
        sobre.v = ProtocoloReloj.version + 1
        let d = try ProtocoloReloj.diccionario(sobre)
        #expect(throws: ProtocoloReloj.Fallo.versionNueva(ProtocoloReloj.version + 1)) { try ProtocoloReloj.leer(d) }
        // Aunque el número de afuera falte, el de adentro manda.
        #expect(throws: ProtocoloReloj.Fallo.versionNueva(ProtocoloReloj.version + 1)) { try ProtocoloReloj.leer(["mp": d["mp"]!]) }
    }

    @Test func unaVersionMasViejaQueLaMinimaSeRechaza() throws {
        var sobre = SobreReloj(.pedirRutina, enviado: T0)
        sobre.v = ProtocoloReloj.minimoCompatible - 1
        #expect(throws: ProtocoloReloj.Fallo.versionVieja(ProtocoloReloj.minimoCompatible - 1)) {
            try ProtocoloReloj.leer(try ProtocoloReloj.datos(sobre))
        }
    }

    @Test func unTipoQueNoSeConoceEsDesconocido() throws {
        let json = #"{"v":1,"id":"\#(UUID().uuidString)","enviado":0,"mensaje":{"tipo":"vibrar","fuerte":true}}"#
        #expect(throws: ProtocoloReloj.Fallo.desconocido("vibrar")) { try ProtocoloReloj.leer(Data(json.utf8)) }
    }

    @Test func unCampoOpcionalNuevoNoRompe() throws {
        // Una versión futura compatible agrega un campo: la de hoy lo ignora.
        let json = #"{"v":1,"id":"\#(UUID().uuidString)","enviado":5,"extra":"x","mensaje":{"tipo":"sinRutina","motivo":"m","color":"verde"}}"#
        #expect(try ProtocoloReloj.leer(Data(json.utf8)).mensaje == .sinRutina(motivo: "m"))
    }

    @Test func basuraYFaltantesSonErrores() {
        #expect(throws: ProtocoloReloj.Fallo.sinMensaje) { try ProtocoloReloj.leer(["v": 1]) }
        #expect(throws: ProtocoloReloj.Fallo.ilegible) { try ProtocoloReloj.leer(Data("no es json".utf8)) }
        // Un evento de serie sin reps no se lee a medias.
        let json = #"{"v":1,"id":"\#(UUID().uuidString)","enviado":0,"mensaje":{"tipo":"eventos","eventos":[{"id":"\#(UUID().uuidString)","creado":0,"evento":{"tipo":"serie","diaId":"d1","semana":1,"lugar":"x","indice":0}}]}}"#
        #expect(throws: ProtocoloReloj.Fallo.ilegible) { try ProtocoloReloj.leer(Data(json.utf8)) }
    }

    @Test func elFormatoDeUnEventoEsElDocumentado() throws {
        // El formato en el cable es parte del contrato (docs/NATIVA_TANDAS_2_A_4.md): si cambia, sube la versión.
        let e = EventoReloj.serie(diaId: "d1", semana: 2, lugar: "l", indice: 1, reps: 9, kg: 60)
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        #expect(String(decoding: try enc.encode(e), as: UTF8.self)
                == #"{"diaId":"d1","indice":1,"kg":60,"lugar":"l","reps":9,"semana":2,"tipo":"serie"}"#)
    }
}
