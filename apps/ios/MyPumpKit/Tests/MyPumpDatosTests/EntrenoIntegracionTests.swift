import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

// El motor de Entreno contra el backend REAL, con la cuenta de prueba test-nativa-real (invisible para el coach). Solo
// corre en la Mac de desarrollo, donde está el registro privado de cuentas de prueba; el token no sale de ahí.
//
// Para dejar la cuenta como estaba, todo lo que se escribe va a la SEMANA 90 (fuera del plan de 12: la app nunca la
// muestra, y `iniciar_sesion` y `registrar_carga` son idempotentes, así que correrlo de nuevo no suma filas) y la serie
// se registra con el nombre de un SUSTITUTO que no está en el plan (no ensucia "Última vez" ni el récord de sus
// ejercicios). Lo único que queda: esa serie y su sesión en la semana 90, y un comentario por corrida en un lugar que
// no existe en la rutina.
private let registro = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Developer/nativa-evidencia/privado/cuentas-prueba.json")

private func tokenDePrueba() -> String? {
    guard let d = try? Data(contentsOf: registro), let j = try? JSONDecoder().decode(JSONValue.self, from: d) else { return nil }
    return j["test-nativa-real"]?["token"]?.comoTexto
}

private let semanaDePrueba = 90
private let raizDelRepo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite("Entreno contra el backend real (cuenta de prueba)", .enabled(if: tokenDePrueba() != nil), .serialized)
@MainActor
struct EntrenoIntegracionTests {
    struct Armado {
        let modelo: ModeloEntreno
        let cola: Outbox
        let cliente: ClienteRPC
        let token: String
    }

    /// La rutina activa de la cuenta, con la semana 90.
    func armar(raiz: URL) async throws -> Armado {
        let token = try #require(tokenDePrueba())
        let cliente = ClienteRPC()
        guard case .success(.lista(let filas)) = await cliente.llamar("mypump_get_rutina_activa", ["p_token": .texto(token)]),
              case .objeto(var fila)? = filas.first else {
            Issue.record("no llegó la rutina activa de test-nativa-real")
            throw CancellationError()
        }
        fila["semana_actual"] = .numero(Double(semanaDePrueba))
        let rutina = try JSONDecoder().decode(RutinaActiva.self, from: JSONEncoder().encode(JSONValue.objeto(fila)))
        let escrituras = Escrituras(cliente: cliente, token: token)
        let cola = Outbox(archivo: nil, reintentoAutomatico: false) { op in await escrituras.ejecutar(op) }
        let catalogo = try CatalogoEjercicios(json: Data(contentsOf: raizDelRepo.appendingPathComponent("apps/shared/catalogo-ejercicios.json")))
        let m = ModeloEntreno(cliente: cliente, token: token, outbox: cola, disco: Disco(raiz: raiz, token: token), rutina: rutina,
                              catalogo: catalogo)
        return Armado(modelo: m, cola: cola, cliente: cliente, token: token)
    }

    func carpeta() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("mypump-entreno-real-\(UUID().uuidString)") }

    /// La sesión del día 1 en la semana de prueba, según el servidor.
    func sesionDelServidor(_ a: Armado, dia: String = "d1") async -> Sesion? {
        guard case .success(let filas) = await a.cliente.filas("mypump_get_sesion_dia", ["p_token": .texto(a.token), "p_dia_id": .texto(dia),
                                                                                         "p_semana": .numero(Double(semanaDePrueba))], como: Sesion.self)
        else { return nil }
        return filas.first
    }

    /// El primer ejercicio del día 1 con kg (no de peso corporal) que tenga un sustituto fuera del plan, y ese sustituto.
    func lugarYSustituto(_ m: ModeloEntreno) throws -> (String, SustitutoEjercicio) {
        let delPlan = Set(m.dias.flatMap { $0.bloques.flatMap(\.ejercicios) }.map { ClaveEjercicio.de($0.nombre) })
        for ex in m.dia.lista where ex.tipo != "cardio" && !ReglasEjercicio.sinKg(ex) {
            if let sub = m.sustitutos(ex.id).first(where: { !delPlan.contains(ClaveEjercicio.de($0.nombre)) }) { return (ex.id, sub) }
        }
        Issue.record("ningún ejercicio del día 1 tiene un sustituto fuera del plan")
        throw CancellationError()
    }

    @Test func serieConSustituto_estado_historialPorClave_yRestaurar() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = try await armar(raiz: raiz)
        let m = a.modelo
        await m.cargar()
        await m.cambiarDia("d1")
        #expect(m.semana == semanaDePrueba && m.dia.dia.id == "d1")
        let (lugar, sub) = try lugarYSustituto(m)
        let nombrePlan = try #require(m.dia.ejercicio(lugar)).nombre

        // Sustituir solo por hoy: la serie va con el nombre del sustituto y el id del lugar (SER-13).
        await m.sustituir(lugar, por: sub, fijar: false)
        #expect(m.efectivo(m.dia.ejercicio(lugar)!).ejercicio.nombre == sub.nombre)
        // Una corrida anterior la dejó confirmada en el servidor: el lápiz la abre para volver a escribirla (SER-06).
        if m.dia.ejercicios[lugar]?.series[0].confirmada == true { await m.editarSerie(lugar, 0) }
        m.escribir(lugar, 0, campo: "reps", valor: "10")
        m.escribir(lugar, 0, campo: "kg", valor: "40")
        await m.elegirRIR(lugar, 0, 0)
        // Si una corrida anterior cerró este día, se reabre (SES-07).
        await m.confirmarSerie(lugar, 0) { _ in true }
        #expect(m.dia.ejercicios[lugar]?.series[0].confirmada == true)
        await a.cola.drenar()
        let quedaron = await a.cola.operaciones
        #expect(quedaron.isEmpty, "la serie no entró: \(quedaron)")

        let sesion = try #require(await sesionDelServidor(a))
        let sid = try #require(sesion.id)
        let registros = try await a.cliente.filas("mypump_get_registros_sesion", ["p_token": .texto(a.token), "p_sesion_id": .texto(sid)],
                                                  como: RegistroSesion.self).get()
        let fila = try #require(registros.first { $0.ejercicioId == lugar && $0.serie == 1 })
        #expect(fila.ejercicioNombre == sub.nombre && fila.pesoKg == 40 && fila.reps == 10)
        #expect(fila.rir == 0, "RIR 0 es 'fue al fallo', no 'no lo cargó'")
        // La variante viaja en notas solo si el sustituto muestra el selector (revisión del 21-oct: un sustituto sin
        // agarre no se graba con el del plan).
        let conSelector = ReglasEjercicio.variantes(sub.nombre) != nil
        #expect(fila.notas == (conSelector ? ReglasEjercicio.variantes(nombrePlan)?.opciones.first : nil), "la variante viaja en notas")

        // "Terminé este ejercicio" con una serie: completo, marcado a mano (SER-15).
        await m.terminar(lugar) { _ in true }
        await a.cola.drenar()
        let estados = try await a.cliente.filas("mypump_get_ejercicios_estado", ["p_token": .texto(a.token), "p_sesion_id": .texto(sid)],
                                                como: EstadoEjercicio.self).get()
        let estado = try #require(estados.first { $0.ejercicioId == lugar })
        #expect(estado.status == "completo" && estado.marcadoManualmente)

        // El historial del lugar sustituido es el del SUSTITUTO, por clave (SER-08), con la serie recién cargada.
        m.invalidarHistorial(lugar)
        await m.pedirHistorial(lugar)
        let h = try #require(m.dia.historial[lugar])
        #expect(h.allSatisfy { $0.clave == ClaveEjercicio.de(sub.nombre) })
        #expect(h.contains { $0.pesoKg == 40 && $0.reps == 10 && $0.rir == 0 })
        #expect(m.dia.record(lugar) != nil)

        // Restaurar en otro teléfono (sin nada local): la sesión, la serie y el estado vienen del servidor (SES-02).
        let otraRaiz = carpeta()
        defer { try? FileManager.default.removeItem(at: otraRaiz) }
        let b = try await armar(raiz: otraRaiz)
        await b.modelo.cargar()
        await b.modelo.cambiarDia("d1")
        #expect(b.modelo.dia.sesionId == sid)
        let serie = try #require(b.modelo.dia.ejercicios[lugar]?.series.first)
        #expect(serie.confirmada && serie.kg == "40" && serie.reps == "10" && serie.rir == "0")
        #expect(serie.nombreRegistrado == sub.nombre, "reabrir no la renombra al original")
        #expect(b.modelo.dia.estado(lugar) == "completo" && b.modelo.dia.meta[lugar]?.manual == true)

        // Una sesión local que el servidor no conoce se descarta (nada de sesiones fantasma).
        let fantasma = carpeta()
        defer { try? FileManager.default.removeItem(at: fantasma) }
        Disco(raiz: fantasma, token: a.token).guardar(["d1": ModeloEntreno.SesionLocal(sesionId: "00000000-0000-4000-8000-000000000000",
                                                                                         semana: semanaDePrueba, finalizada: true, inicio: 1)],
                                                     ModeloEntreno.Archivo.sesiones)
        let c = try await armar(raiz: fantasma)
        await c.modelo.cargar()
        await c.modelo.cambiarDia("d1")
        #expect(c.modelo.dia.sesionId == sid && c.modelo.inicioSesion != 1)

        // Dejarlo como estaba: el ejercicio vuelve a pendiente y el lugar al original.
        await m.reabrir(lugar)
        await a.cola.drenar()
        let despues = try await a.cliente.filas("mypump_get_ejercicios_estado", ["p_token": .texto(a.token), "p_sesion_id": .texto(sid)],
                                                como: EstadoEjercicio.self).get()
        #expect(despues.first { $0.ejercicioId == lugar }?.status == "pendiente")
        await m.revertirSustitucion(lugar)
        #expect(m.efectivo(m.dia.ejercicio(lugar)!).ejercicio.nombre == nombrePlan)
        #expect(m.dia.historial[lugar].map { h in h.allSatisfy { $0.clave == ClaveEjercicio.de(nombrePlan) } } ?? true)
    }

    @Test func cerrarElDia_yReabrirloConUnaSerie() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = try await armar(raiz: raiz)
        let m = a.modelo
        await m.cargar()
        await m.cambiarDia("d1")
        let (lugar, sub) = try lugarYSustituto(m)
        await m.sustituir(lugar, por: sub, fijar: false)
        await m.empezar()
        let sid = try #require(m.dia.sesionId)
        #expect(m.sesionIniciada && m.inicioSesion != nil)
        #expect(await m.cerrarDia(notas: "prueba del motor de Entreno") == .cerrado)
        let cerrada = try #require(await sesionDelServidor(a))
        #expect(cerrada.id == sid && cerrada.finalizadaEn != nil)
        #expect(m.dia.diaFinalizado && m.hecho(m.dias.first { $0.id == "d1" }!))
        // La sustitución "solo hoy" del día cerrado se conserva (para reabrir y corregir).
        #expect(m.dia.sustituciones[lugar] != nil)

        // Cargar una serie en el día cerrado pregunta, reabre y usa la MISMA sesión (SES-07).
        var preguntas: [String] = []
        if m.dia.ejercicios[lugar]?.series[1].confirmada == true { await m.editarSerie(lugar, 1) }
        m.escribir(lugar, 1, campo: "reps", valor: "8")
        m.escribir(lugar, 1, campo: "kg", valor: "40")
        await m.confirmarSerie(lugar, 1) { p in preguntas.append(p.titulo); return true }
        #expect(preguntas.first == "Este día ya lo cerraste" && !m.dia.diaFinalizado)
        let op = try #require(await a.cola.operaciones.first { $0.kind == "carga" })
        #expect(op.payload["sesionId"]?.comoTexto == sid && op.dedupeKey == "carga_d1_\(lugar)_1_s\(semanaDePrueba)")
        await a.cola.drenar()
        #expect(await a.cola.pendientes == 0)
        await m.revertirSustitucion(lugar)
    }

    @Test func comentarioDirecto_yLeidos() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = try await armar(raiz: raiz)
        let m = a.modelo
        await m.cargar()
        // Un lugar que no existe en la rutina: no aparece en ninguna card.
        let lugar = "prueba-nativa-entreno-d0-0"
        // Texto fijo: el servidor descarta el mismo texto dentro de 2 minutos (075), y lo que quede se reconoce.
        let texto = "prueba del motor de Entreno (test de integración de la app nativa)"
        #expect(await m.comentar(lugar, "  \(texto)  "))
        #expect(m.comentarios.comentarios(ejercicio: lugar).contains { $0.contenido == texto && $0.autor == "cliente" })
        #expect(m.comentarios.sinLeer(ejercicio: lugar) == 0, "lo del cliente no cuenta como no leído")
        await m.marcarLeidos(lugar)
        #expect(await m.comentar(lugar, "   ") == false)
    }

    @Test func historialDelDia_unPedido() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = try await armar(raiz: raiz)
        let m = a.modelo
        await m.cambiarDia("d2")
        await m.precargarHistorial()
        let trabajo = m.dia.lista.filter { $0.tipo != "calentamiento" }
        #expect(trabajo.allSatisfy { m.dia.historial[$0.id] != nil }, "quedó algún ejercicio sin historial")
        // La cuenta tiene historia de las semanas 1-4 en los ejercicios de trabajo: récord y última vez salen de ahí.
        let conHistoria = trabajo.filter { !(m.dia.historial[$0.id] ?? []).isEmpty }
        #expect(!conHistoria.isEmpty)
        for ex in conHistoria {
            #expect(m.dia.record(ex.id) != nil)
            #expect(m.tarjeta(ex.id)?.ultimaVez != nil)
        }
    }

    @Test func bloqueNuevoSinBloqueEnCola_noHaceNada() async throws {
        let raiz = carpeta()
        defer { try? FileManager.default.removeItem(at: raiz) }
        let a = try await armar(raiz: raiz)
        #expect(!a.modelo.rutina.tieneSiguiente && !a.modelo.puedeEmpezarBloque)
        #expect(await a.modelo.empezarBloqueNuevo() == .error(SemanaEntreno.errorBloqueNuevo(sinRed: false)))
    }
}
