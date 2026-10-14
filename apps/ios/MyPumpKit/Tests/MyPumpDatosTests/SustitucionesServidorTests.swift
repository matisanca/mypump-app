import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// SER-14: las sustituciones de ejercicio también en el servidor (`nativa_003`). Lo que importa: que nada de lo que hoy
/// funciona cambie si la tabla no está (PGRST202), sin red o con el token caído; que gane siempre lo último que hizo el
/// cliente, en cualquier teléfono y en cualquier orden de llegada; y que nunca se pierda algo que el servidor no tiene.
/// Los casos con nombre de hallazgo son los de la revisión independiente del 14-oct.
@Suite("Sustituciones de ejercicio en el servidor: reglas")
struct SustitucionesServidorReglasTests {
    static func e(_ nombre: String, ts: Double? = nil, fijado: Bool = true, semana: Double = 5) -> JSONValue {
        var o: [String: JSONValue] = ["current": .objeto(["nombre": .texto(nombre)]), "fijado": .bool(fijado), "semana": .numero(semana)]
        if let ts { o["_ts"] = .numero(ts) }
        return .objeto(o)
    }

    @Test func lasOpsSalenDeLaDiferencia_yElBorradoLlevaSuHora() {
        let x = Self.e("Dominadas", ts: 10), y = Self.e("Remo en T", ts: 20)
        let ops = SustitucionesServidor.operaciones(antes: ["a": x, "b": x, "c": x],
                                                    ahora: ["a": x, "b": y, "d": y, "e": .texto("rara")], rutinaId: "R", ms: 777.9)
        #expect(ops.map(\.kind) == ["swap_ej", "swap_ej_del", "swap_ej"], "b cambia, c se va, d entra; a igual y e no se sube")
        #expect(ops.map(\.exId) == ["b", "c", "d"])
        #expect(ops.map(\.clave) == ["swap_ej_R_b", "swap_ej_R_c", "swap_ej_R_d"])
        #expect(ops[0].payload == .objeto(["rutinaId": .texto("R"), "exId": .texto("b"), "swap": y]))
        #expect(ops[1].payload == .objeto(["rutinaId": .texto("R"), "exId": .texto("c"), "ts": .numero(777)]))
    }

    /// Hallazgo 6: la base cuenta la clave en puntos de código (`length`), no en grafemas.
    @Test func soloSeSubeLoQueLaBaseAcepta() {
        #expect(SustitucionesServidor.subible("a", Self.e("X")))
        #expect(SustitucionesServidor.subible("a", Self.e("X", ts: 1_792_000_800_000)))
        #expect(!SustitucionesServidor.subible("a", .lista([])))
        #expect(!SustitucionesServidor.subible("", Self.e("X")))
        #expect(!SustitucionesServidor.subible(String(repeating: "x", count: 121), Self.e("X")))
        let combinadas = String(repeating: "e\u{301}", count: 61)   // 61 grafemas, 122 puntos de código
        #expect(combinadas.count == 61 && !SustitucionesServidor.subible(combinadas, Self.e("X")))
        #expect(!SustitucionesServidor.subible("a", .objeto(["relleno": .texto(String(repeating: "x", count: 13_000))])))
        #expect(!SustitucionesServidor.subible("a", .objeto(["_ts": .texto("ayer")])))
        #expect(!SustitucionesServidor.subible("a", .objeto(["_ts": .numero(-1)])))
    }

    @Test func gánaLoMasNuevo_yLoQueElServidorNoTieneQueda() {
        let r = SustitucionesServidor.combinar(
            vivas: ["nuevaAlla": Self.e("S", ts: 20), "viejaAlla": Self.e("S", ts: 5), "soloAlla": Self.e("S", ts: 1),
                    "empate": Self.e("S", ts: 7), "malo": .numero(1)],
            borradas: ["lapidaNueva": 30, "lapidaVieja": 2, "lapidaDeNada": 9],
            local: ["nuevaAlla": Self.e("L", ts: 10), "viejaAlla": Self.e("L", ts: 15), "empate": Self.e("L", ts: 7),
                    "lapidaNueva": Self.e("L", ts: 25), "lapidaVieja": Self.e("L", ts: 3), "soloAca": Self.e("L"),
                    "rara": .texto("nunca subió")],
            pendientes: [:], rutinaId: "R", tocadas: [])
        #expect(r == ["nuevaAlla": Self.e("S", ts: 20), "viejaAlla": Self.e("L", ts: 15), "soloAlla": Self.e("S", ts: 1),
                      "empate": Self.e("S", ts: 7), "lapidaVieja": Self.e("L", ts: 3), "soloAca": Self.e("L"),
                      "rara": .texto("nunca subió")])
    }

    @Test func laColaYLoTocadoGananAlServidor() {
        func op(_ id: String, _ kind: String, _ rutina: String, _ ex: String, _ swap: JSONValue?) -> Operacion {
            var p: [String: JSONValue] = ["rutinaId": .texto(rutina), "exId": .texto(ex)]
            if let swap { p["swap"] = swap }
            return Operacion(id: id, kind: kind, payload: .objeto(p), dedupeKey: "swap_ej_\(rutina)_\(ex)", ts: 0)
        }
        let r = SustitucionesServidor.combinar(
            vivas: ["s": Self.e("S", ts: 99), "t": Self.e("S", ts: 99), "u": Self.e("S", ts: 99)], borradas: [:],
            local: ["t": Self.e("L", ts: 1)],
            pendientes: ["swap_ej_R_p": op("1", "swap_ej", "R", "p", Self.e("P", ts: 1)), "swap_ej_R_s": op("2", "swap_ej_del", "R", "s", nil),
                         "swap_ej_OTRA_q": op("3", "swap_ej", "OTRA", "q", Self.e("Q", ts: 1))],
            rutinaId: "R", tocadas: ["t", "u"])
        #expect(r == ["p": Self.e("P", ts: 1), "t": Self.e("L", ts: 1)],
                "p y s en la cola; t y u se tocaron (u se borró): gana lo del teléfono aunque el servidor sea más nuevo")
    }

    @Test func volverDeLaAppVieja_soloAplicaLoQueSeCambioAhi() {
        let base: [String: JSONValue] = ["a": Self.e("A"), "b": Self.e("B"), "c": Self.e("C")]
        let legado: [String: JSONValue] = ["a": Self.e("A"), "b": Self.e("B2"), "n": Self.e("N")]   // b cambió, n es nueva, c se sacó
        let nativa: [String: JSONValue] = ["a": Self.e("A nativa", ts: 50), "b": Self.e("B", ts: 0), "c": Self.e("C"),
                                           "x": Self.e("Solo en la nativa", ts: 60)]
        let r = SustitucionesServidor.volverDeLaAppVieja(nativa: nativa, legado: legado, base: base, ms: 1000)
        #expect(r == ["a": Self.e("A nativa", ts: 50), "b": Self.e("B2", ts: 1000), "n": Self.e("N", ts: 1000),
                      "x": Self.e("Solo en la nativa", ts: 60)])
        // Sin base (una corrida de antes de SER-14): todo lo de la app vieja cuenta como cambiado y no se saca nada.
        let sinBase = SustitucionesServidor.volverDeLaAppVieja(nativa: nativa, legado: legado, base: nil, ms: 1000)
        #expect(sinBase == ["a": Self.e("A", ts: 1000), "b": Self.e("B2", ts: 1000), "n": Self.e("N", ts: 1000), "c": Self.e("C"),
                            "x": Self.e("Solo en la nativa", ts: 60)])
    }

    @Test func laRespuestaDelServidorSeLeeConSusDosPartes() {
        let j: JSONValue = .objeto(["vivas": .objeto(["a": Self.e("A"), "malo": .numero(3)]), "borradas": .objeto(["b": .numero(9)])])
        let l = SustitucionesServidor.leer(j)
        #expect(l?.vivas == ["a": Self.e("A")] && l?.borradas == ["b": 9])
        #expect(SustitucionesServidor.leer(.lista([])) == nil && SustitucionesServidor.leer(.null) == nil)
    }
}

@Suite("Sustituciones de ejercicio en el servidor: el modelo", .serialized)
@MainActor
struct SustitucionesServidorModeloTests {
    static let noExiste = (404, #"{"code":"PGRST202","message":"Could not find the function"}"#)

    /// Una sustitución de esta semana (la poda no la toca si está fijada).
    static func swap(_ nombre: String, dia: String = "d1", ts: Double? = nil, fijado: Bool = true, semana: Double = 5) -> JSONValue {
        var o: [String: JSONValue] = [
            "original": .objeto(["slug": .null, "nombre": .texto("Original"), "images": .null]),
            "current": .objeto(["slug": .null, "nombre": .texto(nombre), "equipment": .null, "images": .null]),
            "fijado": .bool(fijado), "semana": .numero(semana), "diaId": .texto(dia)]
        if let ts { o["_ts"] = .numero(ts) }
        return .objeto(o)
    }

    static func json(vivas: [String: JSONValue] = [:], borradas: [String: Double] = [:]) -> String {
        let j: JSONValue = .objeto(["vivas": .objeto(vivas), "borradas": .objeto(borradas.mapValues { .numero($0) })])
        return String(decoding: try! JSONEncoder().encode(j), as: UTF8.self)
    }

    func local(_ b: Banco, _ m: [String: JSONValue]) { b.disco.guardar(m, ModeloEntreno.Archivo.sustituciones("rut-prueba")) }
    func enDisco(_ b: Banco) -> [String: JSONValue]? { b.disco.leer([String: JSONValue].self, ModeloEntreno.Archivo.sustituciones("rut-prueba")) }
    func claves(_ b: Banco) async -> [String] { await b.cola.operaciones.compactMap(\.dedupeKey) }

    @Test func laPrimeraVez_seSubeLoDelTelefonoYLlegaLoDeOtro() async {
        let b = Banco()
        local(b, ["jal-d1-0": Self.swap("Dominadas")])   // de la app vieja: sin hora
        b.servidor.cuando("get_exercise_swaps", Self.json(vivas: ["pre-d2-0": Self.swap("Press inclinado", dia: "d2", ts: 100)]))
        let m = b.modelo()
        await m.cargar()
        #expect(m.dia.sustituciones.keys.sorted() == ["jal-d1-0", "pre-d2-0"], "la del otro teléfono llegó y la de acá quedó")
        #expect(enDisco(b)?.keys.sorted() == ["jal-d1-0", "pre-d2-0"])
        await m.encoladoSustituciones?.value
        let ops = await b.cola.operaciones
        #expect(ops.map(\.dedupeKey) == ["swap_ej_rut-prueba_jal-d1-0"] && ops.first?.kind == "swap_ej", "sube solo lo que el servidor no tiene")
        #expect(ops.first?.payload["swap"] == Self.swap("Dominadas"))
    }

    /// Hallazgo 1: un teléfono viejo con una "solo hoy" vencida no borra en el servidor la que el cliente fijó después
    /// en otro teléfono; al leer, se queda con la fijada.
    @Test func laPodaDeUnTelefonoViejoNoBorraLoFijadoEnOtro() async {
        let b = Banco()
        local(b, ["jal-d1-0": Self.swap("Remo en T", ts: 1000, fijado: false, semana: 4)])
        b.servidor.cuando("get_exercise_swaps", Self.json(vivas: ["jal-d1-0": Self.swap("Dominadas", ts: 5000)]))
        let m = b.modelo()
        await m.cargar()
        await m.encoladoSustituciones?.value
        #expect(await claves(b).isEmpty, "la poda mandó un borrado")
        #expect(m.dia.sustituciones == ["jal-d1-0": Self.swap("Dominadas", ts: 5000)])
    }

    /// Lo vencido que vuelve del servidor se poda acá, sin mandar nada y sin cambiar lo que se ve.
    @Test func loVencidoQueVuelveDelServidor_sePodaSinMandarNada() async {
        let b = Banco()
        b.servidor.cuando("get_exercise_swaps", Self.json(vivas: ["jal-d1-0": Self.swap("Remo en T", ts: 1000, fijado: false, semana: 4)]))
        let m = b.modelo()
        await m.cargar()
        await m.encoladoSustituciones?.value
        #expect(m.dia.sustituciones.isEmpty && (enDisco(b) ?? [:]).isEmpty)
        #expect(await claves(b).isEmpty)
        #expect(b.servidor.llamadas("get_historico_por_clave").count <= 1, "pidió el historial de nuevo")
    }

    @Test func loMasNuevoGana_deUnLadoYDelOtro() async {
        let b = Banco()
        local(b, ["jal-d1-0": Self.swap("Dominadas", ts: 1000), "rem-d1-1": Self.swap("Remo en T", ts: 3000)])
        b.servidor.cuando("get_exercise_swaps", Self.json(vivas: ["jal-d1-0": Self.swap("Jalón cerrado", ts: 2000),
                                                                   "rem-d1-1": Self.swap("Remo bajo", ts: 2000)]))
        let m = b.modelo()
        await m.cargar()
        await m.encoladoSustituciones?.value
        #expect(m.dia.sustituciones["jal-d1-0"] == Self.swap("Jalón cerrado", ts: 2000), "el servidor era más nuevo")
        #expect(m.dia.sustituciones["rem-d1-1"] == Self.swap("Remo en T", ts: 3000), "acá era más nuevo")
        let ops = await b.cola.operaciones
        #expect(ops.map(\.dedupeKey) == ["swap_ej_rut-prueba_rem-d1-1"], "sube solo la más nueva de acá")
    }

    /// Hallazgo 3: una lápida más nueva saca la de acá; una más vieja no (y la de acá se vuelve a subir).
    @Test func lasLapidas_sacanLoMasViejoYNoLoMasNuevo() async {
        let b = Banco()
        local(b, ["jal-d1-0": Self.swap("Dominadas", ts: 1000), "rem-d1-1": Self.swap("Remo en T", ts: 3000)])
        b.servidor.cuando("get_exercise_swaps", Self.json(borradas: ["jal-d1-0": 2000, "rem-d1-1": 2000]))
        let m = b.modelo()
        await m.cargar()
        await m.encoladoSustituciones?.value
        #expect(m.dia.sustituciones.keys.sorted() == ["rem-d1-1"])
        #expect(await claves(b) == ["swap_ej_rut-prueba_rem-d1-1"])
    }

    /// Hallazgo 2: si la tabla se vaciara (o se recreara), lo del teléfono se vuelve a subir: que falte allá no es un borrado.
    @Test func siElServidorNoTieneNada_noSePierdeNadaYSeVuelveASubir() async {
        let b = Banco()
        local(b, ["jal-d1-0": Self.swap("Dominadas", ts: 1000), "rem-d1-1": Self.swap("Remo en T", ts: 2000)])
        b.disco.guardar(["jal-d1-0": Self.swap("Dominadas", ts: 1000), "rem-d1-1": Self.swap("Remo en T", ts: 2000)],
                        SustitucionesServidor.archivoEncoladas(rutinaId: "rut-prueba"))   // ya habían subido
        b.servidor.cuando("get_exercise_swaps", Self.json())
        let m = b.modelo()
        await m.cargar()
        await m.encoladoSustituciones?.value
        #expect(m.dia.sustituciones.keys.sorted() == ["jal-d1-0", "rem-d1-1"])
        #expect(await claves(b) == ["swap_ej_rut-prueba_jal-d1-0", "swap_ej_rut-prueba_rem-d1-1"])
    }

    @Test func sinLaTablaEnLaBase_quedaComoHoy() async throws {
        let b = Banco(ejecutar: true)
        local(b, ["jal-d1-0": Self.swap("Dominadas")])
        b.servidor.cuando("get_exercise_swaps", Self.noExiste.0, Self.noExiste.1)
        b.servidor.cuando("save_exercise_swap", Self.noExiste.0, Self.noExiste.1)
        b.servidor.cuando("delete_exercise_swap", Self.noExiste.0, Self.noExiste.1)
        let estados = EstadosDeGuardado()
        await b.cola.observar(estado: { estados.anotar($0) }, abandonadas: { _ in })
        let m = b.modelo()
        await m.cargar()
        #expect(m.dia.sustituciones == ["jal-d1-0": Self.swap("Dominadas")])
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
        #expect(!estados.lista.contains(.perdido) && !estados.lista.contains(.sinConexion))
        #expect(enDisco(b) == [:])
    }

    @Test func sinRedOConElTokenCaido_quedaLoDelTelefono() async {
        for respuesta in [nil, (200, "null"), (200, "[]")] as [(Int, String)?] {
            let b = Banco()
            local(b, ["jal-d1-0": Self.swap("Dominadas", ts: 1)])
            b.servidor.regla("get_exercise_swaps") { _ in respuesta }
            let m = b.modelo()
            await m.sincronizarSustituciones()
            await m.encoladoSustituciones?.value
            #expect(m.dia.sustituciones == ["jal-d1-0": Self.swap("Dominadas", ts: 1)], "con \(String(describing: respuesta))")
            #expect(enDisco(b) == ["jal-d1-0": Self.swap("Dominadas", ts: 1)])
            #expect(await claves(b).isEmpty)
        }
    }

    @Test func cadaCambioSaleALaColaConSuHora_yGanaElUltimo() async throws {
        let b = Banco()
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: false)
        await m.encoladoSustituciones?.value
        let guardar = try #require(await b.cola.operaciones.first)
        #expect(guardar.kind == "swap_ej" && guardar.dedupeKey == "swap_ej_rut-prueba_jal-d1-0")
        #expect(guardar.payload["rutinaId"] == .texto("rut-prueba") && guardar.payload["exId"] == .texto("jal-d1-0"))
        #expect(guardar.payload["swap"] == m.dia.sustituciones["jal-d1-0"], "va lo mismo que queda en el teléfono")
        #expect(guardar.payload["swap"]?["_ts"] == .numero(AHORA), "con la hora del cambio")
        b.reloj.ms = AHORA + 5000
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        let ops = await b.cola.operaciones
        #expect(ops.count == 1 && ops.first?.kind == "swap_ej_del", "volver al original reemplaza a la de guardar")
        #expect(ops.first?.payload["ts"] == .numero(AHORA + 5000))
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
        #expect(guardada["p_swap"]?["_ts"] == .numero(AHORA))
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        await b.cola.drenar()
        let borrada = try #require(b.servidor.llamadas("delete_exercise_swap").first)
        #expect(borrada["p_ex_id"] == .texto("jal-d1-0") && borrada["p_ts"] == .numero(AHORA))
        let (ops, fallidos) = (await b.cola.operaciones, await b.cola.fallidos)
        #expect(ops.isEmpty && fallidos.isEmpty)
    }

    @Test func loQueSigueEnLaCola_noLoPisaElServidor() async throws {
        let b = Banco()   // la cola no manda nada: queda pendiente
        local(b, ["rem-d1-1": Self.swap("Remo en T", ts: 1)])
        b.servidor.cuando("get_exercise_swaps", Self.json(vivas: ["rem-d1-1": Self.swap("Remo en T", ts: 1)]))
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        await m.revertirSustitucion("rem-d1-1")
        await m.sincronizarSustituciones()
        await m.encoladoSustituciones?.value
        #expect(m.dia.sustituciones.keys.sorted() == ["jal-d1-0"], "la nueva queda y la revertida no vuelve")
        let ops = await b.cola.operaciones
        #expect(ops.compactMap(\.dedupeKey).sorted() == ["swap_ej_rut-prueba_jal-d1-0", "swap_ej_rut-prueba_rem-d1-1"])
        #expect(ops.first { $0.kind == "swap_ej_del" }?.payload["ts"] == .numero(AHORA), "no se reencoló con otra hora")
    }

    @Test func loQueSeTocaMientrasSeEspera_noLoPisaLaRespuesta() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("save_exercise_swap", "true")
        let vacio = Self.json()
        b.servidor.regla("get_exercise_swaps") { _ in
            await demora(200)
            return (200, vacio)   // salió antes de que se guardara la nueva
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
        await m.encoladoSustituciones?.value
        #expect(b.servidor.llamadas("save_exercise_swap").count == 1, "no se volvió a mandar")
    }

    /// Hallazgo 4: la op estaba en la cola al empezar, se mandó mientras se esperaba la respuesta (que salió antes) y ya no
    /// está en la cola al combinar: igual queda lo del teléfono.
    @Test func unaOpEncoladaAntesDeLeer_queSaleEnElMedio_noSePierde() async throws {
        let b = Banco(ejecutar: true)
        b.servidor.cuando("save_exercise_swap", "true")
        let vacio = Self.json()
        b.servidor.regla("get_exercise_swaps") { _ in
            await demora(200)
            return (200, vacio)
        }
        let m = b.modelo()
        let sub = try #require(m.sustitutos("jal-d1-0").first)
        await m.sustituir("jal-d1-0", por: sub, fijar: true)
        await m.encoladoSustituciones?.value
        #expect(await b.cola.operaciones.count == 1)
        async let sync: Void = m.sincronizarSustituciones()
        try await Task.sleep(for: .milliseconds(60))
        await b.cola.drenar()
        await sync
        #expect(m.dia.sustituciones["jal-d1-0"]?["current"]?["nombre"]?.comoTexto == sub.nombre)
        await m.encoladoSustituciones?.value
        #expect(await b.cola.operaciones.isEmpty && b.servidor.llamadas("save_exercise_swap").count == 1)
    }

    /// La app escribió la sustitución en el archivo y se cerró antes de pasarla a la cola: al volver a abrir se encola.
    @Test func loQueNoLlegoALaColaAntesDeCerrarse_seEncolaAlVolverAAbrir() async {
        let b = Banco()
        b.disco.guardar(["rem-d1-1": Self.swap("Remo en T", ts: 1)], SustitucionesServidor.archivoEncoladas(rutinaId: "rut-prueba"))
        local(b, ["rem-d1-1": Self.swap("Remo en T", ts: 1), "jal-d1-0": Self.swap("Dominadas", ts: 2)])
        b.servidor.sinRed("get_exercise_swaps")
        let m = b.modelo()
        await m.cargar()
        await m.encoladoSustituciones?.value
        #expect(await claves(b) == ["swap_ej_rut-prueba_jal-d1-0"])
        let anotadas = b.disco.leer([String: JSONValue].self, SustitucionesServidor.archivoEncoladas(rutinaId: "rut-prueba"))
        #expect(anotadas?.keys.sorted() == ["jal-d1-0", "rem-d1-1"], "queda anotado que ya está en la cola")
    }

    @Test func loQueLlegaDelServidor_noVuelveALaCola() async {
        let b = Banco()
        b.servidor.cuando("get_exercise_swaps", Self.json(vivas: ["jal-d1-0": Self.swap("Dominadas", ts: 1),
                                                                   "pre-d2-0": Self.swap("Press inclinado", dia: "d2", ts: 1)]))
        let m = b.modelo()
        await m.sincronizarSustituciones()
        await m.revertirSustitucion("jal-d1-0")
        await m.encoladoSustituciones?.value
        let ops = await b.cola.operaciones
        #expect(ops.map(\.kind) == ["swap_ej_del"] && ops.first?.payload["exId"] == .texto("jal-d1-0"),
                "sale solo lo que hizo el cliente, no lo que bajó: \(ops.map(\.dedupeKey))")
    }

    @Test func siCambiaLaRutinaEnElMedio_laRespuestaNoSeUsa() async {
        let b = Banco()
        let respuesta = Self.json(vivas: ["jal-d1-0": Self.swap("Dominadas", ts: 1)])
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

/// Hallazgo 5: antes de SER-14 una sustitución no tocaba la red; sus ops no muestran avisos (las demás sí).
@Suite("Sustituciones de ejercicio en el servidor: la cola no avisa")
struct SustitucionesSilenciosasTests {
    static let sinRed: ResultadoOp = .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin red")))

    @Test func sinRed_unaSustitucionSolaNoAvisa_yConUnaSerieSi() async {
        let estados = EstadosDeGuardado()
        let o = Outbox(archivo: nil, reintentoAutomatico: false) { _ in Self.sinRed }
        await o.observar(estado: { estados.anotar($0) }, abandonadas: { _ in })
        await o.encolar("swap_ej", .objeto([:]), dedupeKey: "swap_ej_R_a")
        await o.drenar()
        #expect(!estados.lista.contains(.sinConexion), "\(estados.lista)")
        await o.encolar("carga", .objeto([:]), dedupeKey: "k1")
        await o.drenar()
        #expect(estados.lista.contains(.sinConexion))
    }

    @Test func lentaNoMuestraGuardando() async {
        let estados = EstadosDeGuardado()
        let o = Outbox(archivo: nil, reintentoAutomatico: false) { _ in
            try? await Task.sleep(for: .milliseconds(1100))
            return .respuesta(.success(.bool(true)))
        }
        await o.observar(estado: { estados.anotar($0) }, abandonadas: { _ in })
        await o.encolar("swap_ej_del", .objeto([:]), dedupeKey: "swap_ej_R_a")
        await o.drenar()
        #expect(!estados.lista.contains(.guardando), "\(estados.lista)")
    }

    @Test func abandonadaNoAvisaPerdido_peroQuedaEnFallidos() async {
        let estados = EstadosDeGuardado()
        let o = Outbox(archivo: nil, reintentoAutomatico: false) { _ in
            .respuesta(.failure(ErrorRPC(clase: .permanente, status: 400, codigo: "22023", mensaje: "inválida")))
        }
        await o.observar(estado: { estados.anotar($0) }, abandonadas: { _ in })
        await o.encolar("swap_ej", .objeto([:]), dedupeKey: "swap_ej_R_a")
        for _ in 0..<12 where await o.pendientes > 0 { await o.drenar() }
        #expect(!estados.lista.contains(.perdido), "\(estados.lista)")
        #expect(await o.fallidos.count == 1)
    }
}

/// Registro sincrónico de los avisos de la cola.
final class EstadosDeGuardado: @unchecked Sendable {
    private let lock = NSLock()
    private var _lista: [EstadoGuardado] = []
    var lista: [EstadoGuardado] { lock.withLock { _lista } }
    func anotar(_ e: EstadoGuardado) { lock.withLock { _lista.append(e) } }
}
