import Foundation
import Testing
@testable import MyPumpReglas

/// El check guiado contra los casos compartidos (`apps/shared/vectores/check_guiado.json`): Android y la web dan lo mismo.
@Suite("Check guiado: reglas")
struct CheckGuiadoTests {
    typealias B = CheckGuiado.Borrador
    static var v: [String: Any] {
        let d = try! Data(contentsOf: raizRepo.appendingPathComponent("apps/shared/vectores/check_guiado.json"))
        return try! JSONSerialization.jsonObject(with: d) as! [String: Any]
    }
    static func casos(_ k: String) -> [[String: Any]] { v[k] as! [[String: Any]] }
    static func borrador(_ x: Any?) -> B? {
        guard let x, !(x is NSNull) else { return nil }
        return try! JSONDecoder().decode(B.self, from: JSONSerialization.data(withJSONObject: x))
    }
    static func cat(_ x: Any?) -> CheckGuiado.Catalogo? { (x as? String).flatMap(CheckGuiado.Catalogo.init(rawValue:)) }

    @Test func losCatalogosYLosTextosSonLosAcordados() {
        let c = Self.v["catalogos"] as! [String: [[String]]]
        for (nombre, lista) in c {
            let o = CheckGuiado.opciones(Self.cat(nombre)!)
            #expect(o.map { [$0.clave, $0.etiqueta] } == lista, "\(nombre)")
            #expect(o.last?.clave == CheckGuiado.ninguno)
        }
        let titulos = Self.v["titulos"] as! [String: Any], apoyos = Self.v["apoyos"] as! [String: Any], omitir = Self.v["omitir"] as! [String: Any]
        for p in CheckGuiado.Paso.allCases where p != .senales {
            #expect(CheckGuiado.titulo(p) == titulos[p.rawValue] as? String)
            #expect(CheckGuiado.apoyo(p) == apoyos[p.rawValue] as? String)
        }
        for p in CheckGuiado.Paso.allCases { #expect(CheckGuiado.omitir(p) == omitir[p.rawValue] as? String) }
        for c in [CheckGuiado.Catalogo.general, .ciclo] {
            #expect(CheckGuiado.titulo(.senales, catalogo: c) == (titulos["senales"] as! [String: String])[c.rawValue])
            #expect(CheckGuiado.apoyo(.senales, catalogo: c) == (apoyos["senales"] as! [String: String])[c.rawValue])
        }
        let tarjeta = Self.v["tarjeta"] as! [String: [String]]
        for e in [CheckGuiado.Estado.sinEmpezar, .aMedias, .enviado, .enviadoSinFotos] {
            #expect([CheckGuiado.textoTarjeta(e), CheckGuiado.botonTarjeta(e)] == tarjeta[e.rawValue])
        }
    }

    /// Reglas de producto: en ningún texto del check aparece IA, «tu coach», «tu entrenador» ni RIR.
    @Test func ningunTextoDiceLoQueNoSeDice() {
        var textos: [String] = []
        for c in [CheckGuiado.Catalogo.general, .ciclo] {
            textos += CheckGuiado.opciones(c).map(\.etiqueta)
            textos += CheckGuiado.intensidades.map(\.etiqueta) + [CheckGuiado.preguntaIntensidad, CheckGuiado.avisoIntensidad]
            for p in CheckGuiado.Paso.allCases { textos += [CheckGuiado.titulo(p, catalogo: c), CheckGuiado.apoyo(p, catalogo: c), CheckGuiado.omitir(p) ?? ""] }
        }
        for e in [CheckGuiado.Estado.sinEmpezar, .aMedias, .enviado, .enviadoSinFotos] { textos += [CheckGuiado.textoTarjeta(e), CheckGuiado.botonTarjeta(e)] }
        for t in textos {
            let m = " \(t.lowercased()) "
            for prohibido in [" ia ", "inteligencia artificial", "coach", "entrenador", " rir", "esteroide", "testosterona", "anabólic"] {
                #expect(!m.contains(prohibido), "«\(t)» dice «\(prohibido)»")
            }
        }
    }

    @Test func pasos() {
        for c in Self.casos("pasos") {
            #expect(CheckGuiado.pasos(faltanFotos: c["faltanFotos"] as! Bool).map(\.rawValue) == c["pasos"] as! [String])
        }
    }

    @Test func alternarYNormalizar() {
        for c in Self.casos("alternar") {
            #expect(CheckGuiado.alternar(c["senales"] as! [String], c["clave"] as! String) == c["queda"] as! [String])
        }
        for c in Self.casos("normalizar") {
            #expect(CheckGuiado.normalizar(c["senales"] as! [String], Self.cat(c["catalogo"])!) == c["queda"] as! [String])
        }
        for c in Self.casos("textoSenales") {
            #expect(CheckGuiado.textoSenales(c["senales"] as! [String], Self.cat(c["catalogo"])!,
                                             intensidades: c["intensidades"] as! [String: String]) == c["texto"] as! String)
        }
    }

    /// Los digestivos se muestran solo con GLP-1; cada efecto marcado lleva cuánto molesta (la lista general, no).
    @Test func digestivasEIntensidades() {
        #expect(CheckGuiado.digestivas == Self.v["digestivas"] as! [String])
        for c in Self.casos("opcionesCiclo") {
            #expect(CheckGuiado.opciones(.ciclo, glp1: c["glp1"] as! Bool).map(\.clave) == c["claves"] as! [String])
        }
        #expect(CheckGuiado.opciones(.general, glp1: false) == CheckGuiado.opciones(.general))
        let i = Self.v["intensidades"] as! [String: Any]
        #expect(CheckGuiado.intensidades.map { [$0.clave, $0.etiqueta] } == i["opciones"] as! [[String]])
        #expect(CheckGuiado.avisoIntensidad == i["aviso"] as! String)
        #expect(CheckGuiado.preguntaIntensidad == i["pregunta"] as! String)
        for (n, c) in Self.casos("normalizarIntensidades").enumerated() {
            #expect(CheckGuiado.normalizarIntensidades(c["senales"] as! [String], c["intensidades"] as! [String: String], Self.cat(c["catalogo"])!)
                    == c["queda"] as! [String: String], "caso \(n)")
        }
        for (n, c) in Self.casos("faltaIntensidad").enumerated() {
            #expect(CheckGuiado.faltaIntensidad(Self.borrador(c["borrador"])!) == c["falta"] as! Bool, "caso \(n)")
        }
        // Un borrador guardado antes de las intensidades se lee igual.
        let viejo = #"{"semana":"2026-11-09","paso":"nota","peso":"","valores":{},"catalogo":"ciclo","senales":["acne"],"nota":""}"#
        #expect(try! JSONDecoder().decode(B.self, from: Data(viejo.utf8)).intensidades == [:])
    }

    @Test func puedeSeguirYQueFalta() {
        for (i, c) in Self.casos("puedeSeguir").enumerated() {
            let p = CheckGuiado.Paso(rawValue: c["paso"] as! String)!
            #expect(CheckGuiado.puedeSeguir(p, Self.borrador(c["borrador"])!, fotosHechas: c["fotosHechas"] as! Int) == c["puede"] as! Bool, "caso \(i)")
        }
        for (i, c) in Self.casos("faltaParaEnviar").enumerated() {
            let b = Self.borrador(c["borrador"])!
            #expect(CheckGuiado.faltaParaEnviar(b) == c["falta"] as? String, "caso \(i)")
            #expect(CheckGuiado.pasoQueFalta(b)?.rawValue == c["paso"] as? String, "caso \(i)")
        }
    }

    @Test func abrirRetomarYEstado() {
        for c in Self.casos("abrir") {
            let e = c["enviado"] as? [String: Any]
            let r = CheckGuiado.abrir(guardado: Self.borrador(c["guardado"]), semana: c["semana"] as! String, catalogo: Self.cat(c["catalogo"])!,
                                      enviado: e.map { ($0["valores"] as! [String: Int], $0["nota"] as! String) },
                                      senalesEnviadas: c["senalesEnviadas"] as? [String], catalogoEnviado: Self.cat(c["catalogoEnviado"]),
                                      intensidadesEnviadas: c["intensidadesEnviadas"] as? [String: String])
            #expect(r == Self.borrador(c["queda"]), "\(c["caso"] as! String)")
        }
        for c in Self.casos("retomar") {
            let b = B(semana: "2026-11-09", paso: CheckGuiado.Paso(rawValue: c["paso"] as! String)!)
            #expect(CheckGuiado.retomar(b, pasos: (c["pasos"] as! [String]).compactMap(CheckGuiado.Paso.init(rawValue:))).rawValue == c["abre"] as! String)
        }
        for (i, c) in Self.casos("estado").enumerated() {
            let e = CheckGuiado.estado(enviado: c["enviado"] as! Bool, borrador: Self.borrador(c["borrador"]), semana: c["semana"] as! String,
                                       faltanFotos: c["faltanFotos"] as! Bool)
            #expect(e.rawValue == c["estado"] as! String, "caso \(i)")
        }
    }
}
