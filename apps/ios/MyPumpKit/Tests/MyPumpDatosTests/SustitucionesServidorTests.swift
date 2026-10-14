import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// SER-14: las sustituciones de ejercicio también en el servidor (`nativa_003`). Lo que importa: que nada de lo que hoy
/// funciona cambie si la tabla no está (PGRST202), sin red o con el token caído; y que con la tabla lo del teléfono suba
/// una vez y después mande lo del servidor, sin perder lo que todavía está en la cola ni lo que se tocó mientras tanto.
@Suite("Sustituciones de ejercicio en el servidor: reglas")
struct SustitucionesServidorReglasTests {
    static let x: JSONValue = .objeto(["current": .objeto(["nombre": .texto("Dominadas")]), "fijado": .bool(true), "semana": .numero(5)])
    static let y: JSONValue = .objeto(["current": .objeto(["nombre": .texto("Remo en T")]), "fijado": .bool(false), "semana": .numero(5)])

    @Test func lasOpsSalenDeLaDiferencia() {
        let ops = SustitucionesServidor.operaciones(antes: ["a": Self.x, "b": Self.x, "c": Self.x],
                                                    ahora: ["a": Self.x, "b": Self.y, "d": Self.y, "e": .texto("rara")], rutinaId: "R")
        #expect(ops.map(\.kind) == ["swap_ej", "swap_ej_del", "swap_ej"], "b cambia, c se va, d entra; a igual y e no se sube")
        #expect(ops.map(\.exId) == ["b", "c", "d"])
        #expect(ops.map(\.clave) == ["swap_ej_R_b", "swap_ej_R_c", "swap_ej_R_d"])
        #expect(ops[0].payload == .objeto(["rutinaId": .texto("R"), "exId": .texto("b"), "swap": Self.y]))
        #expect(ops[1].payload == .objeto(["rutinaId": .texto("R"), "exId": .texto("c")]))
    }

    @Test func soloSubeLoQueLaBaseAcepta() {
        let largo = String(repeating: "x", count: 121)
        let r = SustitucionesServidor.subibles(["a": Self.x, "b": .lista([]), largo: Self.x, "": Self.x,
                                                "grande": .objeto(["relleno": .texto(String(repeating: "x", count: 13_000))])])
        #expect(r == ["a": Self.x])
        let muchas = Dictionary(uniqueKeysWithValues: (0...300).map { ("e\($0)", Self.x) })
        #expect(SustitucionesServidor.subibles(muchas) == nil, "con más de 300 no sube nada (quedan en el teléfono)")
    }

    @Test func combinar_laColaYLoTocadoGananAlServidor() {
        let pendientes: [String: Operacion] = [
            "swap_ej_R_p": Operacion(id: "1", kind: "swap_ej", payload: .objeto(["rutinaId": .texto("R"), "exId": .texto("p"), "swap": Self.y]),
                                     dedupeKey: "swap_ej_R_p", ts: 0),
            "swap_ej_R_s": Operacion(id: "2", kind: "swap_ej_del", payload: .objeto(["rutinaId": .texto("R"), "exId": .texto("s")]),
                                     dedupeKey: "swap_ej_R_s", ts: 0),
            "swap_ej_OTRA_q": Operacion(id: "3", kind: "swap_ej", payload: .objeto(["rutinaId": .texto("OTRA"), "exId": .texto("q"), "swap": Self.y]),
                                        dedupeKey: "swap_ej_OTRA_q", ts: 0),
        ]
        let r = SustitucionesServidor.combinar(
            servidor: ["s": Self.x, "t": Self.x, "u": Self.x, "malo": .numero(1)],
            local: ["t": Self.y, "v": Self.x, "w": .texto("nunca subió")],
            pendientes: pendientes, rutinaId: "R", tocadas: ["t", "u"])
        #expect(r == ["p": Self.y, "t": Self.y, "w": .texto("nunca subió")],
                "p está en la cola, s se borra en la cola, t y u se tocaron (u se borró), v no está en el servidor ni en la cola")
    }
}

@Suite("Sustituciones de ejercicio en el servidor: el modelo", .serialized)
@MainActor
struct SustitucionesServidorModeloTests {
    static let noExiste = (404, #"{"code":"PGRST202","message":"Could not find the function"}"#)

    /// Una sustitución fijada de esta semana (la poda no la toca).
    static func swap(_ nombre: String, dia: String = "d1") -> JSONValue {
        .objeto(["original": .objeto(["slug": .null, "nombre": .texto("Original"), "images": .null]),
                 "current": .objeto(["slug": .null, "nombre": .texto(nombre), "equipment": .null, "images": .null]),
                 "fijado": .bool(true), "semana": .numero(5), "diaId": .texto(dia)])
    }

    static func json(_ m: [String: JSONValue]) -> String { String(decoding: try! JSONEncoder().encode(JSONValue.objeto(m)), as: UTF8.self) }

    func local(_ b: Banco, _ m: [String: JSONValue]) { b.disco.guardar(m, ModeloEntreno.Archivo.sustituciones("rut-prueba")) }
    func enDisco(_ b: Banco) -> [String: JSONValue]? { b.disco.leer([String: JSONValue].self, ModeloEntreno.Archivo.sustituciones("rut-prueba")) }
    func estado(_ b: Banco) -> SustitucionesServidor.Estado? {
        b.disco.leer(SustitucionesServidor.Estado.self, SustitucionesServidor.Estado.archivo(rutinaId: "rut-prueba"))
    }
    func yaSubidas(_ b: Banco, reemplazar: Bool = false) {
        b.disco.guardar(SustitucionesServidor.Estado(subidas: true, reemplazar: reemplazar), SustitucionesServidor.Estado.archivo(rutinaId: "rut-prueba"))
    }

    @Test func laPrimeraVezSubeLoDelTelefono_yDespuesLee() async {
        let b = Banco()
        local(b, ["jal-d1-0": Self.swap("Dominadas")])
        // Otro teléfono ya había subido la del press.
        b.servidor.cuando("import_exercise_swaps", Self.json(["jal-d1-0": Self.swap("Dominadas"), "pre-d2-0": Self.swap("Press inclinado", dia: "d2")]))
        let m = b.modelo()
        await m.cargar()
        let subida = b.servidor.llamadas("import_exercise_swaps")
        #expect(subida.count == 1)
        #expect(subida.first?["p_swaps"] == .objeto(["jal-d1-0": Self.swap("Dominadas")]))
        #expect(subida.first?["p_reemplazar"] == .bool(false) && subida.first?["p_rutina_id"] == .texto("rut-prueba"))
        #expect(m.dia.sustituciones.keys.sorted() == ["jal-d1-0", "pre-d2-0"], "la del otro teléfono llegó")
        #expect(enDisco(b)?.keys.sorted() == ["jal-d1-0", "pre-d2-0"])
        #expect(estado(b) == SustitucionesServidor.Estado(subidas: true))
        #expect(await b.cola.operaciones.isEmpty, "lo que llega del servidor no vuelve a la cola")

        b.servidor.cuando("get_exercise_swaps", Self.json(["pre-d2-0": Self.swap("Press inclinado", dia: "d2")]))
        await m.sincronizarSustituciones()
        #expect(b.servidor.llamadas("import_exercise_swaps").count == 1, "subir es una sola vez")
        #expect(b.servidor.llamadas("get_exercise_swaps").count == 1)
        #expect(m.dia.sustituciones.keys.sorted() == ["pre-d2-0"], "la del jalón se borró en otro teléfono")
        #expect(m.efectivo(m.dia.ejercicio("jal-d1-0")!).sustituido == false)
    }

    @Test func loQueLlegaDelServidor_noVuelveALaCola() async {
        let b = Banco()
        b.servidor.cuando("import_exercise_swaps", Self.json(["jal-d1-0": Self.swap("Dominadas"), "pre-d2-0": Self.swap("Press inclinado", dia: "d2")]))
        let m = b.modelo()
        await m.sincronizarSustituciones()
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        let ops = await b.cola.operaciones
        #expect(ops.map(\.kind) == ["swap_ej_del"] && ops.first?.payload["exId"] == .texto("jal-d1-0"),
                "sale solo lo que hizo el cliente, no lo que bajó: \(ops.map(\.dedupeKey))")
    }

    @Test func sinLaTablaEnLaBase_quedaComoHoy() async throws {
        let b = Banco(ejecutar: true)
        local(b, ["jal-d1-0": Self.swap("Dominadas")])
        b.servidor.cuando("import_exercise_swaps", Self.noExiste.0, Self.noExiste.1)
        b.servidor.cuando("save_exercise_swap", Self.noExiste.0, Self.noExiste.1)
        b.servidor.cuando("delete_exercise_swap", Self.noExiste.0, Self.noExiste.1)
        let m = b.modelo()
        await m.cargar()
        #expect(m.dia.sustituciones == ["jal-d1-0": Self.swap("Dominadas")])
        #expect(estado(b) == nil, "no se marca como subida: cuando exista la tabla, sube")
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        await m.encoladoSustituciones?.value
        await b.cola.drenar()
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        await b.cola.drenar()
        #expect(b.servidor.llamadas("save_exercise_swap").count == 1 && b.servidor.llamadas("delete_exercise_swap").count == 1)
        let (ops, fallidos) = (await b.cola.operaciones, await b.cola.fallidos)
        #expect(ops.isEmpty && fallidos.isEmpty, "la cola las da por hechas: no hay 'no se guardó'")
        #expect(b.servidor.llamadas("get_cliente_info").isEmpty, "ni se sospecha del token")
        #expect(enDisco(b) == [:])
        await m.sincronizarSustituciones()
        #expect(b.servidor.llamadas("import_exercise_swaps").count == 2, "se vuelve a intentar subir")
    }

    @Test func sinRedOConElTokenCaido_quedaLoDelTelefono() async {
        for respuesta in [nil, (200, "null"), (200, "[]")] as [(Int, String)?] {
            let b = Banco()
            yaSubidas(b)
            local(b, ["jal-d1-0": Self.swap("Dominadas")])
            b.servidor.regla("get_exercise_swaps") { _ in respuesta }
            let m = b.modelo()
            await m.sincronizarSustituciones()
            #expect(m.dia.sustituciones == ["jal-d1-0": Self.swap("Dominadas")], "con \(String(describing: respuesta))")
            #expect(enDisco(b) == ["jal-d1-0": Self.swap("Dominadas")])
        }
    }

    @Test func cadaCambioSaleALaCola_yGanaElUltimo() async throws {
        let b = Banco()
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: false)
        await m.encoladoSustituciones?.value
        let guardar = try #require(await b.cola.operaciones.first)
        #expect(guardar.kind == "swap_ej" && guardar.dedupeKey == "swap_ej_rut-prueba_jal-d1-0")
        #expect(guardar.payload["rutinaId"] == .texto("rut-prueba") && guardar.payload["exId"] == .texto("jal-d1-0"))
        #expect(guardar.payload["swap"] == m.dia.sustituciones["jal-d1-0"], "va lo mismo que queda en el teléfono")
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        let ops = await b.cola.operaciones
        #expect(ops.count == 1 && ops.first?.kind == "swap_ej_del", "volver al original reemplaza a la de guardar")
    }

    @Test func conLaTabla_laColaGuardaYBorra() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("save_exercise_swap", "true")
        b.servidor.cuando("delete_exercise_swap", "true")
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        await m.encoladoSustituciones?.value
        await b.cola.drenar()
        let guardada = try #require(b.servidor.llamadas("save_exercise_swap").first)
        #expect(guardada["p_rutina_id"] == .texto("rut-prueba") && guardada["p_ex_id"] == .texto("jal-d1-0"))
        #expect(guardada["p_swap"]?["current"]?["nombre"]?.comoTexto == sub.nombre && guardada["p_swap"]?["fijado"] == .bool(true))
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        await b.cola.drenar()
        #expect(b.servidor.llamadas("delete_exercise_swap").first?["p_ex_id"] == .texto("jal-d1-0"))
        let (ops, fallidos) = (await b.cola.operaciones, await b.cola.fallidos)
        #expect(ops.isEmpty && fallidos.isEmpty)
    }

    @Test func loQueSigueEnLaCola_noLoPisaElServidor() async throws {
        let b = Banco()   // la cola no manda nada: queda pendiente
        yaSubidas(b)
        local(b, ["rem-d1-1": Self.swap("Remo en T")])
        b.servidor.cuando("get_exercise_swaps", Self.json(["rem-d1-1": Self.swap("Remo en T")]))
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        await m.revertirSustitucion("rem-d1-1")
        await m.sincronizarSustituciones()
        #expect(m.dia.sustituciones.keys.sorted() == ["jal-d1-0"], "la nueva queda y la revertida no vuelve")
    }

    @Test func loQueSeTocaMientrasSeEspera_noLoPisaLaRespuesta() async throws {
        let b = Banco(ejecutar: true)
        yaSubidas(b)
        b.servidor.cuando("save_exercise_swap", "true")
        b.servidor.regla("get_exercise_swaps") { _ in
            await demora(200)
            return (200, "{}")   // salió antes de que se guardara la nueva
        }
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        async let sync: Void = m.sincronizarSustituciones()
        try await Task.sleep(for: .milliseconds(30))
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        await m.encoladoSustituciones?.value
        await b.cola.drenar()   // ya se guardó: la cola no la tiene
        await sync
        #expect(m.dia.sustituciones["jal-d1-0"]?["current"]?["nombre"]?.comoTexto == sub.nombre)
        #expect(enDisco(b)?["jal-d1-0"] != nil)
    }

    @Test func siLaMigracionSeRepitio_loDeLaAppViejaReemplaza() async {
        let b = Banco()
        yaSubidas(b, reemplazar: true)
        local(b, ["jal-d1-0": Self.swap("Dominadas")])
        b.servidor.cuando("import_exercise_swaps", Self.json(["jal-d1-0": Self.swap("Dominadas")]))
        let m = b.modelo()
        await m.sincronizarSustituciones()
        #expect(b.servidor.llamadas("import_exercise_swaps").first?["p_reemplazar"] == .bool(true))
        #expect(estado(b) == SustitucionesServidor.Estado(subidas: true, reemplazar: false))
        #expect(b.servidor.llamadas("get_exercise_swaps").isEmpty)
    }

    @Test func siCambiaLaRutinaEnElMedio_laRespuestaNoSeUsa() async {
        let b = Banco()
        yaSubidas(b)
        let respuesta = Self.json(["jal-d1-0": Self.swap("Dominadas")])
        b.servidor.regla("get_exercise_swaps") { _ in
            await demora(150)
            return (200, respuesta)
        }
        let m = b.modelo()
        async let sync: Void = m.sincronizarSustituciones()
        try? await Task.sleep(for: .milliseconds(30))
        let fila = filaRutina().replacingOccurrences(of: #""id":"rut-prueba""#, with: #""id":"rut-otra""#)
        m.reemplazarRutina(try! JSONDecoder().decode(RutinaActiva.self, from: Data(fila.utf8)))
        await sync
        #expect(m.dia.sustituciones.isEmpty)
        #expect(b.disco.leer([String: JSONValue].self, ModeloEntreno.Archivo.sustituciones("rut-otra")) == nil)
    }
}
