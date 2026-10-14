import Foundation
import ImageIO
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Contra el backend REAL, con la cuenta de prueba test-nativa-real (invisible para el coach). Solo corre en la Mac de
/// desarrollo, donde está el registro privado de cuentas de prueba. Escribe datos de prueba (autorizado).
private let registro = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Developer/nativa-evidencia/privado/cuentas-prueba.json")

private func tokenDePrueba() -> String? {
    guard let d = try? Data(contentsOf: registro), let j = try? JSONDecoder().decode(JSONValue.self, from: d) else { return nil }
    return j["test-nativa-real"]?["token"]?.comoTexto
}

@Suite("Integración con el backend real (cuenta de prueba)", .enabled(if: tokenDePrueba() != nil), .serialized)
@MainActor
struct IntegracionTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("mypump-integracion-\(UUID().uuidString)")

    @Test func cargaTodoYCopiaOffline() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .listo)
        #expect(m.info?.clienteId == "test-nativa-real")
        #expect((m.rutina?.estructura.dias.count ?? 0) == 4)
        #expect(!(m.comidasDelDia.isEmpty))
        // Sin red, arranca desde la copia offline.
        struct SinRed: Transporte { func enviar(_ p: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let offline = ModeloApp(cliente: ClienteRPC(transporte: SinRed()), almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await offline.cargar()
        #expect(offline.fase == .listo && offline.desdeCache)
        #expect(offline.dieta?.id == m.dieta?.id)
    }

    @Test func alimentoPropioSeCreaYEntraALaBase() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        // Upsert por (cliente, nombre): correrlo de nuevo no duplica.
        let datos = try AlimentoPropioNuevo.preparar(nombre: "Yogur prueba nativa", kcal: 75, prot: 3, carb: 10.1, fat: 2.25,
                                                     unidad: "porcion", gramosPorUnidad: 30, categoria: "lacteo").get()
        let creado = try await m.crearAlimentoPropio(datos).get()
        #expect(creado.nombre == "Yogur prueba nativa")
        #expect(creado.kcal == 250 && creado.prot == 10 && creado.gramosPorUnidad == 30 && creado.unidad == "porcion")
        #expect(m.alimentosPropios.filter { $0.nombre == "Yogur prueba nativa" }.count == 1)
        let otra = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await otra.cargar()
        #expect(otra.alimentosPropios.contains { $0.nombre == "Yogur prueba nativa" && $0.kcal == 250 })
    }

    @Test func comidaLibreSeCreaSeListaYSeBorra() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let antes = m.comidasLibres.count
        let datos = try ComidaLibreNueva.preparar(descripcion: "Prueba nativa: alfajor", hora: "10:30", kcal: 250, prot: 3,
                                                  carb: 35, fat: 11, detalle: nil).get()
        let creada = try await m.crearComidaLibre(datos).get()
        #expect(creada.descripcion == "Prueba nativa: alfajor" && creada.kcal == 250)
        #expect(m.comidasLibres.count == antes + 1)
        let otra = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await otra.cargar()
        #expect(otra.comidasLibres.contains { $0.id == creada.id })
        #expect(await m.borrarComidaLibre(creada.id))
        await otra.cargarComidasLibres()
        #expect(!otra.comidasLibres.contains { $0.id == creada.id })
    }

    /// La plomería de mini-vision sin gastar una llamada a la IA: con un token que no existe, el servicio corta antes
    /// (403) y el mensaje llega tal cual. Si el body estuviera mal armado contestaría 400 "falta imagen".
    @Test func visionConTokenInvalidoCortaAntesDeLaIA() async throws {
        let c = ClienteRPC()
        let jpeg = Data(base64Encoded: "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==")!
        let r = await c.vision(token: "tokenQueNoExiste_0000000000000000", tipo: .plato, jpeg: jpeg)
        guard case .failure(let e) = r else { Issue.record("respondió ok con un token inválido"); return }
        #expect(e.status == 403)
        #expect(e.clase == .permanente)
    }

    @Test func chatEnviaPorLaColaYNoDuplicaUnReintento() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let t = try #require(tokenDePrueba())
        let chat = ModeloChat(cliente: m.cliente, token: t, outbox: m.outbox)
        await chat.cargar()
        let texto = "Prueba nativa \(UUID().uuidString.prefix(8))"
        await chat.enviar(texto)
        #expect(chat.hilo.mensajes.last?.pendiente == true)
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)
        await chat.sondear()
        #expect(chat.hilo.mensajes.contains { $0.contenido == texto && !$0.pendiente })
        #expect(!chat.hilo.mensajes.contains { $0.pendiente })
        // La respuesta se perdió y la cola lo reintenta: no se manda de nuevo.
        let e = Escrituras(cliente: m.cliente, token: t)
        let op = Operacion(id: "x", kind: "chat", payload: .objeto(["contenido": .texto(texto)]), dedupeKey: nil, tries: 0,
                           ts: Date().timeIntervalSince1970 * 1000 - 5_000)
        _ = await e.ejecutar(op)
        let filas = try await m.cliente.filas("mypump_get_chat", ["p_token": .texto(t), "p_antes": .null, "p_limite": .numero(10)],
                                              como: MensajeChat.self).get()
        #expect(filas.filter { $0.contenido == texto }.count == 1)
    }

    @Test func miDiaYRevisionPorLaCola() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let t = try #require(tokenDePrueba())
        let r = ModeloRevision(cliente: m.cliente, token: t, outbox: m.outbox)
        await r.cargarMiDia()
        #expect(r.miDiaCargado)
        let previoCardio = r.habitos.cardio
        // Tocar "hice cardio ✓" y que llegue.
        await r.setHabito(campo: "cardio", valor: "true")
        #expect(r.habitos.cardio == true)
        await m.outbox?.drenar()
        let otra = ModeloRevision(cliente: m.cliente, token: t, outbox: m.outbox)
        await otra.cargarMiDia()
        #expect(otra.habitos.cardio == true)
        // Agua con la espera de 600 ms.
        let vasos = r.habitos.vasosAgua
        r.cambiarAgua(vasos >= 12 ? -1 : 1)
        try await Task.sleep(for: .milliseconds(900))
        await m.outbox?.drenar()
        await otra.cargarMiDia()
        #expect(otra.habitos.vasosAgua == r.habitos.vasosAgua)
        // Dejar la cuenta como estaba.
        await r.setHabito(campo: "cardio", valor: previoCardio.map { $0 ? "true" : "false" })
        r.cambiarAgua(vasos - r.habitos.vasosAgua)
        try await Task.sleep(for: .milliseconds(900))
        await m.outbox?.drenar()

        // Check: faltan escalas → no sale; completo → sale.
        #expect(await r.enviarCheckin(Checkin(valores: ["energia": 4], nota: "")) == "Faltan: Descanso, Hambre, Adherencia")
        #expect(await r.enviarCheckin(Checkin(valores: ["energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5], nota: " prueba nativa ")) == nil)
        #expect(r.checkinEnviado)
        await m.outbox?.drenar()
        await otra.cargarRevision()
        #expect(otra.checkin?.valores["hambre"] == 2 && otra.checkin?.nota == "prueba nativa")

        // Peso fuera de rango no se guarda; uno válido entra a la serie.
        #expect(await r.guardarPeso("25") == false)
        #expect(await r.guardarPeso("81,95"))
        #expect(r.serieDePeso.last?.kg == 82)
        await m.outbox?.drenar()
        await otra.cargarRevision()
        #expect(otra.serieDePeso.last == PesoCorporal.Punto(fecha: FechaLocal.hoy(), kg: 82))
    }

    /// REV-02/REV-03 de punta a punta: una foto como las de la cámara de un iPhone (4032×3024 apaisada con orientación 6,
    /// o sea vertical en pantalla, con GPS y EXIF) pasa por la MISMA reducción que la galería de Revisión (900 px, 0,7),
    /// sube (la de espalda de esta semana: es un upsert, repetir no suma), se piden las URLs firmadas y se baja lo que
    /// quedó guardado: tiene que ser un JPEG de 675×900, derecho y sin ubicación. El servicio deja 12 fotos por día por
    /// cliente: corre solo con `MYPUMP_PROBAR_FOTOS=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYPUMP_PROBAR_FOTOS"] == "1"))
    func fotoDeProgresoSubeReducidaSinUbicacionYSeFirma() async throws {
        let t = try #require(tokenDePrueba())
        let m = ModeloFotos(cliente: ClienteRPC(), token: t, disco: Disco(raiz: raiz, token: t))
        let original = try #require(ReduccionFotoTests.archivo(ReduccionFotoTests.imagen(4032, 3024), orientacion: 6))
        let jpeg = try #require(ReduccionFoto.jpeg(original, maxPx: 900, calidad: 0.7))
        let r = await m.subir(pose: "espalda", jpeg: jpeg)
        #expect(r == .guardada, "subida: \(r.texto)")
        #expect(m.fotos.contains { $0.pose == "espalda" && $0.semanaLunes == m.semanaActual })
        #expect(await m.firmar())
        let url = try #require(m.urls["\(m.semanaActual)|espalda"])
        let (guardada, respuesta) = try await URLSession.shared.data(from: url)
        #expect((respuesta as? HTTPURLResponse)?.statusCode == 200)
        let p = ReduccionFotoTests.propiedades(guardada)
        #expect(p.tipo == "public.jpeg" && p.ancho == 675 && p.alto == 900, "en el servidor quedó \(p.ancho)×\(p.alto) \(p.tipo ?? "?")")
        #expect(p.props[kCGImagePropertyGPSDictionary] == nil, "en el servidor quedó con la ubicación")
        #expect((p.props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(guardada.count < 400_000, "pesa \(guardada.count) bytes")
    }

    /// MIG-03: la foto que trae la migración del almacenamiento viejo (la cola de la web, `mypump_fotoq_<T>`, que la Fase L
    /// deja tal cual en `fotos-pendientes.json`) sube sola al vaciar la cola, y queda guardada. La de perfil de esta semana
    /// (upsert). Corre solo con `MYPUMP_PROBAR_FOTOS=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYPUMP_PROBAR_FOTOS"] == "1"))
    func fotoQueTraeLaMigracionSubeAlVaciarLaCola() async throws {
        let t = try #require(tokenDePrueba())
        let disco = Disco(raiz: raiz, token: t)
        let original = try #require(ReduccionFotoTests.archivo(ReduccionFotoTests.imagen(3024, 4032)))
        let jpeg = try #require(ReduccionFoto.jpeg(original, maxPx: 900, calidad: 0.7))
        let hoy = FechaLocal.hoy()
        let lunes = FotosProgreso.lunes(hoy)
        // Como la deja la Fase L: "<lunes>|<pose>" → {pose, fecha, dataUrl, intentos}.
        disco.guardar(["\(lunes)|perfil": FotoPendiente(pose: "perfil", fecha: hoy, dataUrl: "data:image/jpeg;base64," + jpeg.base64EncodedString())],
                      FotoPendiente.archivo)
        let m = ModeloFotos(cliente: ClienteRPC(), token: t, disco: disco)
        #expect(m.pendientes.count == 1)
        await m.drenar()
        #expect(m.pendientes.isEmpty, "quedó en la cola")
        #expect((disco.leer([String: FotoPendiente].self, FotoPendiente.archivo) ?? [:]).isEmpty, "quedó en el archivo de la cola")
        #expect(m.fotos.contains { $0.pose == "perfil" && $0.semanaLunes == lunes })
        #expect(await m.firmar())
        let url = try #require(m.urls["\(lunes)|perfil"])
        let (guardada, _) = try await URLSession.shared.data(from: url)
        let p = ReduccionFotoTests.propiedades(guardada)
        #expect(p.ancho == 675 && p.alto == 900, "en el servidor quedó \(p.ancho)×\(p.alto)")
    }

    /// SER-14 de punta a punta contra el servidor real (nativa_003, aplicada el 14-oct): una sustitución fijada en un
    /// teléfono llega al otro, y "Volver a …" en el segundo llega al primero. Dos teléfonos = dos discos con el mismo token
    /// (la cuenta de prueba). Repetirla no deja basura: la vuelta al original deja la lápida, y la próxima corrida la
    /// supera (es también la prueba del piso por clave).
    @Test func unaSustitucionPasaDeUnTelefonoAOtro() async throws {
        let t = try #require(tokenDePrueba())
        let a = ModeloApp(almacen: TokenEnMemoria(t), raizDisco: raiz.appendingPathComponent("telefono-a"))
        let b = ModeloApp(almacen: TokenEnMemoria(t), raizDisco: raiz.appendingPathComponent("telefono-b"))
        await a.cargar()
        await b.cargar()
        await a.cargarCatalogo()
        await b.cargarCatalogo()
        let ea = try #require(a.entreno), eb = try #require(b.entreno)
        await ea.cargar()
        await eb.cargar()
        #expect(ea.rutina.id == eb.rutina.id)
        let lugar = try #require(ea.dia.lista.first { !ea.sustitutos($0.id).isEmpty }?.id, "ningún ejercicio con sustitutos")
        let sub = try #require(ea.sustitutos(lugar).first)

        // A fija la sustitución; sale por la cola al servidor.
        await ea.sustituir(lugar, por: sub, fijar: true)
        await ea.encoladoSustituciones?.value
        await a.outbox?.drenar()
        #expect(await a.outbox?.operaciones.isEmpty == true, "no salió de la cola de A")

        // B la lee.
        await eb.sincronizarSustituciones()
        #expect(eb.dia.sustituciones[lugar]?["current"]?["nombre"]?.comoTexto == sub.nombre, "no llegó a B")
        #expect(eb.dia.sustituciones[lugar]?["fijado"] == .bool(true))
        #expect(eb.efectivo(try #require(eb.dia.ejercicio(lugar))).ejercicio.nombre == sub.nombre)

        // B vuelve al original; A lo ve.
        await eb.revertirSustitucion(lugar)
        await eb.encoladoSustituciones?.value
        await b.outbox?.drenar()
        await ea.sincronizarSustituciones()
        #expect(ea.dia.sustituciones[lugar] == nil, "la vuelta al original no llegó a A")
    }

    @Test func progresoConElHistorialReal() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let p = ModeloProgreso(cliente: m.cliente, token: try #require(tokenDePrueba()))
        await p.cargar(rutina: m.rutina)
        #expect(p.estado == .listo)
        #expect(!p.tarjetas.isEmpty)
        #expect(p.sesiones > 0)
        // Una tarjeta por clave: nunca dos con la misma.
        #expect(Set(p.tarjetas.map(\.clave)).count == p.tarjetas.count)
        #expect(p.tarjetas.allSatisfy { $0.resumen.serie.count <= 8 && !$0.dias.isEmpty })
        // Sin red avisa y no deja tarjetas viejas mezcladas.
        struct SinRed: Transporte { func enviar(_ q: URLRequest) async throws -> (Data, URLResponse) { throw URLError(.notConnectedToInternet) } }
        let offline = ModeloProgreso(cliente: ClienteRPC(transporte: SinRed()), token: "x")
        await offline.cargar(rutina: m.rutina)
        #expect(offline.estado == .sinRed)
    }

    @Test func elEntrenoQuedaArmadoConLaRutinaYElCatalogo() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let e = try #require(m.entreno)
        #expect(e.rutina.id == m.rutina?.id)
        #expect(!e.dias.isEmpty)
        #expect(!e.demo)
        await m.cargarCatalogo()
        #expect(e.catalogo.entradas.count > 500)   // el del servidor (~873)
    }

    @Test func sustituirLlegaAnclado_yRevertirLoBorra() async throws {
        let m = ModeloApp(almacen: TokenEnMemoria(tokenDePrueba()), raizDisco: raiz)
        await m.cargar()
        let comida = try #require(m.comidasDelDia.first)
        let original = try #require(comida.opciones.first?.alimentos.first)
        let sustituto: JSONValue = .objeto(["name": .texto("Ricota descremada"), "qty": .numero(150), "unit": .texto("g"),
                                            "kcal": .numero(207), "prot": .numero(17), "carb": .numero(6), "fat": .numero(12), "category": .texto("lacteo")])
        await m.sustituir(original, por: sustituto, comidaId: comida.id, opt: 0, idx: 0)
        #expect(m.efectivo(original, comidaId: comida.id, opt: 0, idx: 0).alimento.nombre == "Ricota descremada")
        await m.outbox?.drenar()
        #expect(await m.outbox?.pendientes == 0)

        let t = try #require(tokenDePrueba())
        let dietaId = try #require(m.dieta?.id)
        let remotos = try await m.cliente.filas("mypump_get_food_swaps", ["p_token": .texto(t), "p_dieta_id": .texto(dietaId)], como: FoodSwap.self).get()
        let fila = try #require(remotos.first { $0.comidaId == comida.id && $0.optIdx == 0 && $0.foodIdx == 0 })
        #expect(fila.foodData["_orig"]?["name"]?.comoTexto == original.nombre)

        await m.revertir(comidaId: comida.id, opt: 0, idx: 0)
        await m.outbox?.drenar()
        let despues = try await m.cliente.filas("mypump_get_food_swaps", ["p_token": .texto(t), "p_dieta_id": .texto(dietaId)], como: FoodSwap.self).get()
        #expect(!despues.contains { $0.comidaId == comida.id && $0.optIdx == 0 && $0.foodIdx == 0 })
        #expect(m.efectivo(original, comidaId: comida.id, opt: 0, idx: 0).alimento.nombre == original.nombre)
    }

    @Test func tokenInvalido() async {
        let m = ModeloApp(almacen: TokenEnMemoria("TokenInvalidoDePrueba00000000000"), raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .tokenInvalido)
    }
}
