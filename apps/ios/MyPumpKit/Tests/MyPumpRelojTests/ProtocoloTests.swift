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
            .pedirRutina, .pedirDia(diaId: "d3"), .rutina(rutina), .eventos(eventos),
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

    // MARK: - Elegir el día

    @Test func pedirDiaTieneElFormatoDocumentado() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = .sortedKeys
        #expect(String(decoding: try enc.encode(MensajeReloj.pedirDia(diaId: "d2")), as: UTF8.self) == #"{"diaId":"d2","tipo":"pedirDia"}"#)
        // Sin el día no se lee a medias.
        let json = #"{"v":1,"id":"\#(UUID().uuidString)","enviado":0,"mensaje":{"tipo":"pedirDia"}}"#
        #expect(throws: ProtocoloReloj.Fallo.ilegible) { try ProtocoloReloj.leer(Data(json.utf8)) }
    }

    @Test func laRutinaLlevaLosDiasYElAviso() throws {
        var r = RutinaReloj.demo(fecha: HOY, generada: T0)
        r.avisoDia = "En el iPhone hay otro día en curso."
        let s = try ida(.rutina(r))
        guard case .rutina(let leida) = s.mensaje else { Issue.record("no es rutina"); return }
        #expect(leida.dias == RutinaReloj.diasDemo)
        #expect(leida.avisoDia == r.avisoDia)
    }

    @Test func unaRutinaSinLosCamposNuevosSeLeeYMuestraSoloSuDia() throws {
        // Lo que manda un iPhone de antes de elegir el día: sin `dias` ni `avisoDia`.
        var vieja = RutinaReloj.demo(fecha: HOY, generada: T0)
        vieja.dias = nil
        let datos = try ProtocoloReloj.datos(SobreReloj(.rutina(vieja), enviado: T0))
        let json = String(decoding: datos, as: UTF8.self)
        #expect(!json.contains("\"dias\"") && !json.contains("avisoDia"))
        guard case .rutina(let r) = try ProtocoloReloj.leer(datos).mensaje else { Issue.record("no es rutina"); return }
        #expect(r.dias == nil)
        #expect(r.diasParaElegir.map(\.id) == ["d1"])
        #expect(r.diasParaElegir.first?.ejercicios == r.ejercicios.count)
        #expect(r.diaSugerido == "d1")
    }

    @Test func unIPhoneViejoNoEntiendePedirDiaPeroNoContestaIncompatible() throws {
        // Un lado de la versión 1 sin `pedirDia` lo ve como un tipo desconocido: se descarta, sin marcar «incompatible»
        // (eso cortaría el paso de las series). El reloj deja de esperar solo (`SesionReloj.esperaDia`).
        let d = try ProtocoloReloj.diccionario(SobreReloj(.pedirDia(diaId: "d2"), enviado: T0))
        #expect(d["v"] as? Int == ProtocoloReloj.version)
        let json = #"{"v":1,"id":"\#(UUID().uuidString)","enviado":0,"mensaje":{"tipo":"pedirSemana","diaId":"d2"}}"#
        let viejo: [String: Any] = ["v": 1, "mp": Data(json.utf8)]
        #expect(throws: ProtocoloReloj.Fallo.desconocido("pedirSemana")) { try ProtocoloReloj.leer(viejo) }
        #expect(ProtocoloReloj.respuestaIncompatible(viejo, ahora: T0) == nil)
    }

    @Test func elDiaSugeridoEsElAbiertoOElProximoSiYaEstaHecho() {
        var r = RutinaReloj.demo(fecha: HOY, generada: T0)
        #expect(r.diaSugerido == "d1")
        r.diaFinalizado = true
        #expect(r.diaSugerido == "d2")
        // Un próximo que no está en la lista no se marca.
        r.proximo = ProximoEntreno(diaId: "d9", nombre: "X", ejercicios: 1)
        #expect(r.diaSugerido == "d1")
    }
}
