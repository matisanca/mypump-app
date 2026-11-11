import XCTest
import Foundation
import MyPumpModelos
@testable import MyPumpReglas

/// Los vectores que comparte con Android (`apps/shared/vectores/estudios.json`): textos, fechas y decodificación tolerante.
final class EstudiosVectoresTests: XCTestCase {
    private func vectores() throws -> JSONValue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("shared/vectores/estudios.json")
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }
    private func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }
    private func textos(_ j: JSONValue?) -> [String] { lista(j).compactMap(\.comoTexto) }
    private func entero(_ j: JSONValue?) -> Int? { if case .numero(let n)? = j { Int(n) } else { nil } }
    private func dia(_ j: JSONValue?) -> Estudios.Dia? { Estudios.Dia(j?.comoTexto) }

    func testConstantes() throws {
        let v = try vectores()
        XCTAssertEqual(Estudios.maxPx, entero(v["maxPx"]))
        XCTAssertEqual(Estudios.calidad, v["calidad"]?.comoNumero)
        XCTAssertEqual(Estudios.topeArchivos, entero(v["topeArchivos"]))
        XCTAssertEqual(Estudios.topeMB, entero(v["topeMB"]))
    }

    func testTextos() throws {
        let v = try vectores()
        guard case .objeto(let t)? = v["textos"] else { return XCTFail() }
        typealias T = TextosEstudios
        let enCodigo: [String: String] = [
            "entradaMisDatos": T.entradaMisDatos, "titulo": T.titulo, "proximoControl": T.proximoControl, "teFaltaHacer": T.teFaltaHacer,
            "subirResultado": T.subirResultado, "yaMeLoHice": T.yaMeLoHice, "verOrden": T.verOrden, "deshacer": T.deshacer,
            "subirEstudio": T.subirEstudio, "tusOrdenes": T.tusOrdenes, "tusEstudios": T.tusEstudios, "ver": T.ver, "recibido": T.recibido,
            "matiLoVio": T.matiLoVio, "sinFecha": T.sinFecha, "ordenVencida": T.ordenVencida, "notaRecibido": T.notaRecibido, "vacio": T.vacio,
            "errorDeCarga": T.errorDeCarga, "cuandoTeLoHiciste": T.cuandoTeLoHiciste, "guardar": T.guardar, "revisaLaFecha": T.revisaLaFecha,
            "guiaSubida": T.guiaSubida, "sacarFotos": T.sacarFotos, "elegirFotos": T.elegirFotos, "elegirPDF": T.elegirPDF, "quitar": T.quitar,
            "sinSenal": T.sinSenal, "envioRecibido": T.envioRecibido, "topeDia": T.topeDia, "archivoRechazado": T.archivoRechazado,
            "comoPrepararte": T.comoPrepararte, "dondeHacerlo": T.dondeHacerlo, "noSePudoAbrir": T.noSePudoAbrir,
            "estudioNuevo": T.estudioNuevo, "ordenNueva": T.ordenNueva, "estudioParaHacer": T.estudioParaHacer, "nuevo": T.nuevo, "novedad": T.novedad,
        ]
        XCTAssertEqual(Set(enCodigo.keys), Set(t.keys))
        for (k, s) in enCodigo { XCTAssertEqual(t[k]?.comoTexto, s, k) }
        for c in lista(v["subtituloEntrada"]) { XCTAssertEqual(T.subtituloEntrada(entero(c["n"]) ?? -1), c["texto"]?.comoTexto) }
        for c in lista(v["enviarArchivos"]) { XCTAssertEqual(T.enviarArchivos(entero(c["n"]) ?? -1), c["texto"]?.comoTexto) }
        for c in lista(v["hojas"]) { XCTAssertEqual(Estudios.hojas(entero(c["n"])), c["texto"]?.comoTexto) }
        XCTAssertEqual(T.topeArchivos(20), v["topes"]?["archivos"]?.comoTexto)
        XCTAssertEqual(T.archivoMuyGrande(20), v["topes"]?["peso"]?.comoTexto)
        for c in lista(v["progreso"]) { XCTAssertEqual(Estudios.progreso(subidos: entero(c["subidos"]) ?? -1, total: entero(c["total"]) ?? -1), c["texto"]?.comoTexto) }
    }

    /// Ni la sigla ni rangos ni valores: lo que tarda es «de Mati».
    func testNingunTextoNombraQuienLee() throws {
        let v = try vectores()
        var todos: [String] = []
        func juntar(_ j: JSONValue) {
            switch j {
            case .texto(let s): todos.append(s)
            case .lista(let l): l.forEach(juntar)
            case .objeto(let o): o.values.forEach(juntar)
            default: break
            }
        }
        for k in ["textos", "subtituloEntrada", "enviarArchivos", "topes", "preparacion", "donde"] { if let j = v[k] { juntar(j) } }
        XCTAssertGreaterThan(todos.count, 60)
        for s in todos {
            let palabras = s.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            XCTAssertFalse(palabras.contains("ia") || palabras.contains("inteligencia") || palabras.contains("automático") || palabras.contains("robot"), s)
        }
    }

    func testFechas() throws {
        let v = try vectores()
        for c in lista(v["fechas"]) {
            let d = dia(c["fecha"])
            XCTAssertEqual(d?.corta, c["corta"]?.comoTexto, "\(c)")
            XCTAssertEqual(d?.conDia, c["conDia"]?.comoTexto, "\(c)")
        }
        for c in lista(v["fechaPendiente"]) {
            let r = Estudios.fechaPendiente(desde: dia(c["desde"]), hasta: dia(c["hasta"]), hoy: dia(c["hoy"]))
            XCTAssertEqual(r?.texto, c["texto"]?.comoTexto, "\(c)")
            XCTAssertEqual(r?.pasada ?? false, c["pasada"] == .bool(true), "\(c)")
        }
        for c in lista(v["fechaControl"]) {
            XCTAssertEqual(Estudios.fechaControl(desde: dia(c["desde"]), hasta: dia(c["hasta"])), c["texto"]?.comoTexto, "\(c)")
        }
        for c in lista(v["hecho"]) { XCTAssertEqual(Estudios.hecho(dia(c["fecha"])), c["texto"]?.comoTexto) }
    }

    func testDiaNumeroYSemana() {
        XCTAssertEqual(Estudios.Dia("1970-01-01")?.numero, 0)
        XCTAssertEqual(Estudios.Dia("1970-01-01")?.diaSemana, 4)
        XCTAssertEqual(Estudios.Dia("2026-11-10")!.numero - Estudios.Dia("2026-07-13")!.numero, 120)
        XCTAssertEqual(Estudios.Dia("2026-11-10T12:00:00Z")?.iso, "2026-11-10")
        XCTAssertNil(Estudios.Dia("2026-13-01"))
        XCTAssertNil(Estudios.Dia("2026-1-1"))
        XCTAssertNil(Estudios.Dia(nil))
        XCTAssertTrue(Estudios.Dia("2026-11-09")! < Estudios.Dia("2026-11-10")!)
        XCTAssertTrue(Estudios.Dia("2026-12-01")! > Estudios.Dia("2026-11-30")!)
    }

    func testFilasDeOrdenEstudioYEnvio() throws {
        let v = try vectores()
        func estado(_ campo: String, _ filas: [JSONValue], zona: TimeZone = .current) -> EstadoEstudios {
            EstadoEstudios(.objeto(["habilitado": .bool(true), campo: .lista(filas)]), zona: zona)!
        }
        for c in lista(v["orden"]) {
            let o = estado("ordenes", [.objeto(["id": .texto("x"), "emitida": c["emitida"] ?? .null, "vence": c["vence"] ?? .null])]).ordenes[0]
            XCTAssertEqual(Estudios.detalleOrden(o), c["texto"]?.comoTexto)
        }
        for c in lista(v["estudio"]) {
            let e = estado("estudios", [.objeto(["id": .texto("x"), "fecha": c["fecha"] ?? .null, "hojas": c["hojas"] ?? .null])]).estudios[0]
            XCTAssertEqual(Estudios.detalleEstudio(e), c["texto"]?.comoTexto)
        }
        for c in lista(v["envio"]) {
            let zona = TimeZone(identifier: c["zona"]?.comoTexto ?? "")!
            let e = estado("envios", [.objeto(["id": .texto("x"), "enviado_en": c["enviado_en"] ?? .null, "archivos": c["archivos"] ?? .null])], zona: zona).envios[0]
            XCTAssertEqual(Estudios.lineaEnvio(e), c["texto"]?.comoTexto)
        }
    }

    func testPreparacionYDonde() throws {
        let v = try vectores()
        guard case .objeto(let p)? = v["preparacion"], case .objeto(let d)? = v["donde"] else { return XCTFail() }
        XCTAssertGreaterThanOrEqual(p.count, 10)
        for (tipo, l) in p { XCTAssertEqual(Estudios.preparacion(tipo: tipo), textos(l), tipo) }
        for (tipo, l) in d { XCTAssertEqual(Estudios.donde(tipo: tipo), textos(l), tipo) }
        XCTAssertEqual(Estudios.preparacion(tipo: nil), Estudios.preparacion(tipo: "otro"))
        XCTAssertEqual(Estudios.donde(tipo: nil), Estudios.donde(tipo: "otro"))
    }

    func testSubida() throws {
        let v = try vectores()
        for c in lista(v["subida"]) {
            let r = Estudios.clasificarSubida(status: entero(c["status"]) ?? -1, ok: c["ok"] == .bool(true))
            XCTAssertEqual("\(r)", c["accion"]?.comoTexto, "\(c)")
        }
        let pdf = Data("%PDF-1.4 x".utf8), jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1])
        XCTAssertEqual(Estudios.formato(pdf), .pdf)
        XCTAssertEqual(Estudios.formato(jpeg), .jpeg)
        XCTAssertNil(Estudios.formato(Data([0x89, 0x50, 0x4E, 0x47])))
        XCTAssertNil(Estudios.formato(Data()))
        XCTAssertEqual(Estudios.puedeAgregar(bytes: 10, formato: .pdf, yaHay: 0), .ok)
        XCTAssertEqual(Estudios.puedeAgregar(bytes: 10, formato: .pdf, yaHay: 20), .tope)
        XCTAssertEqual(Estudios.puedeAgregar(bytes: 20 * 1024 * 1024, formato: .jpeg, yaHay: 19), .ok)
        XCTAssertEqual(Estudios.puedeAgregar(bytes: 20 * 1024 * 1024 + 1, formato: .jpeg, yaHay: 0), .muyGrande)
        XCTAssertEqual(Estudios.puedeAgregar(bytes: 10, formato: nil, yaHay: 0), .ilegible)
    }

    /// `novedades` y `nuevo`: el punto, la tarjeta de arriba, la novedad para la lista del plan, a qué tarjeta se lleva y qué
    /// ids se mandan a marcar. Los textos no nombran qué estudio ni por qué.
    func testNovedades() throws {
        let v = try vectores()
        XCTAssertEqual(Estudios.destino, v["destino"]?.comoTexto)
        let casos = lista(v["novedades"])
        XCTAssertGreaterThanOrEqual(casos.count, 10)
        for c in casos {
            let nombre = c["nombre"]?.comoTexto ?? ""
            let e = try XCTUnwrap(EstadoEstudios(try XCTUnwrap(c["respuesta"])), nombre)
            let x = try XCTUnwrap(c["espera"])
            XCTAssertEqual(Estudios.hayNovedad(e), x["indicador"] == .bool(true), nombre)
            let n = Estudios.novedad(e)
            XCTAssertEqual(n?.titulo, x["novedad"]?.comoTexto, nombre)
            if let n { XCTAssertEqual(n.destino, "estudios", nombre) }
            let t = Estudios.tarjetaInicio(e)
            if case .objeto? = x["tarjeta"] {
                XCTAssertEqual(t?.titulo, x["tarjeta"]?["titulo"]?.comoTexto, nombre)
                XCTAssertEqual(t?.boton, x["tarjeta"]?["boton"]?.comoTexto, nombre)
                XCTAssertEqual(t?.nueva, x["tarjeta"]?["nueva"] == .bool(true), nombre)
            } else {
                XCTAssertNil(t, nombre)
            }
            let a = Estudios.ancla(e)
            if case .objeto? = x["ancla"] {
                let clase = x["ancla"]?["clase"]?.comoTexto, id = x["ancla"]?["id"]?.comoTexto ?? ""
                XCTAssertEqual(a, clase == "orden" ? .orden(id) : .pendiente(id), nombre)
            } else {
                XCTAssertNil(a, nombre)
            }
            XCTAssertEqual(Estudios.nuevas(e), textos(x["nuevas"]), nombre)
        }
    }

    func testDecodificacionTolerante() throws {
        let v = try vectores()
        let e = try XCTUnwrap(EstadoEstudios(try XCTUnwrap(v["get"]?["respuesta"])))
        let x = try XCTUnwrap(v["get"]?["espera"])
        XCTAssertEqual(e.hoy?.iso, "2026-11-10")
        XCTAssertEqual(e.pendientes.count, entero(x["pendientes"]))
        XCTAssertEqual(e.pendientes.filter(\.hecho).count, entero(x["pendientesHechos"]))
        XCTAssertEqual(e.ordenes.count, entero(x["ordenes"]))
        XCTAssertEqual(e.ordenes.filter(\.vigente).count, entero(x["ordenesVigentes"]))
        XCTAssertEqual(e.estudios.count, entero(x["estudios"]))
        XCTAssertEqual(e.estudios.filter(\.visto).count, entero(x["estudiosVistos"]))
        XCTAssertEqual(e.estudios.filter(\.sePuedeAbrir).count, entero(x["estudiosQueSeAbren"]))
        XCTAssertEqual(e.enviosVisibles.count, entero(x["enviosVisibles"]))
        XCTAssertEqual(TextosEstudios.subtituloEntrada(e.pendientes.count), x["subtitulo"]?.comoTexto)
        XCTAssertEqual(e.estudios.last?.titulo, x["tituloSinTitulo"]?.comoTexto)
        let b = Estudios.bloques(e)
        XCTAssertEqual(b.proximoControl, x["bloques"]?["proximoControl"] == .bool(true))
        XCTAssertEqual(b.pendientes, x["bloques"]?["pendientes"] == .bool(true))
        XCTAssertEqual(b.ordenes, x["bloques"]?["ordenes"] == .bool(true))
        XCTAssertEqual(b.estudios, x["bloques"]?["estudios"] == .bool(true))
        XCTAssertEqual(b.vacio, x["bloques"]?["vacio"] == .bool(true))
        for j in lista(v["get"]?["noHabilitado"]) { XCTAssertNil(EstadoEstudios(j), "\(j)") }
        let vacia = try XCTUnwrap(EstadoEstudios(try XCTUnwrap(v["get"]?["vacia"])))
        XCTAssertTrue(Estudios.bloques(vacia).vacio)
        XCTAssertEqual(vacia.topeArchivos, 20)
        XCTAssertNil(vacia.hoy)
    }
}
