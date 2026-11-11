import Foundation
import Testing
import MyPumpModelos
import MyPumpReglas
@testable import MyPumpDatos

/// Cerrar sesión con presión, fotos de inicio y molestias: como el outbox, lo que se ve se borra del teléfono y lo que espera
/// salir queda en la carpeta de esa cuenta y sale al volver a entrar con el mismo link. Gemelas de SalirSaludTest.kt.
@MainActor
struct SalirSaludTests {
    private let token = "tk-prueba-salir-salud"
    private let otro = "tk-prueba-salir-otro"
    private func raiz() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func existe(_ d: Disco, _ n: String) -> Bool { FileManager.default.fileExists(atPath: d.url(n).path) }

    // MARK: Presión

    @Test func presionAlSalirBorraLoVistoYConservaLaCola() async {
        let d = DoblePresion.escenario("serie0")
        let r = raiz()
        let disco = Disco(raiz: r, token: token)
        let m = ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: disco)
        await m.refrescar()
        #expect(m.habilitado)
        #expect(existe(disco, ModeloPresion.archivoEstado))
        d.sinRed = true
        m.empezar(tipo: "estandar", serieId: m.estado?.serie?.id, brazo: "izq", etapa: "anotar")
        _ = m.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)
        m.marcarSintoma(codigos: ["palpitaciones"], nota: "nota de prueba")
        await m.drenar()
        #expect(m.enCola == 2)
        #expect(m.enCurso != nil)

        m.olvidarAlSalir()
        #expect(!m.habilitado)
        #expect(m.enCurso == nil)
        #expect(!existe(disco, ModeloPresion.archivoEstado), "el estado del servidor no queda en el teléfono")
        let cola = disco.leer(ColaPresion.self, ColaPresion.archivo)
        #expect(cola?.enCurso == nil, "la sesión en curso (lo que se ve) se borra")
        #expect(cola?.envios.count == 2, "lo anotado sin señal sigue")
        // Después de salir no se llama a nada.
        d.sinRed = false
        let antes = d.llamadas.count
        await m.refrescar()
        await m.drenar()
        #expect(d.llamadas.count == antes)

        // Con otro link, otra carpeta: no se ve ni se manda.
        let ajeno = ModeloPresion(cliente: ClienteRPC(transporte: d), token: otro, disco: Disco(raiz: r, token: otro))
        #expect(ajeno.enCola == 0)

        // Vuelve con el mismo link: sale lo pendiente.
        let m2 = ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: Disco(raiz: r, token: token))
        #expect(m2.enCola == 2)
        #expect(m2.enCurso == nil)
        await m2.refrescar()
        await m2.drenar()
        #expect(m2.enCola == 0)
        #expect(d.sesiones.count == 1)
        #expect(d.sintomas.count == 1)
    }

    @Test func presionSinNadaPendienteNoDejaArchivos() async {
        let d = DoblePresion.escenario("serie0")
        let disco = Disco(raiz: raiz(), token: token)
        let m = ModeloPresion(cliente: ClienteRPC(transporte: d), token: token, disco: disco)
        await m.refrescar()
        m.empezar(tipo: "estandar", serieId: m.estado?.serie?.id, brazo: "izq", etapa: "anotar")
        _ = m.anotarToma(sis: 124, dia: 78, pulso: 62, latidoIrregular: false)
        await m.drenar()
        #expect(m.enCola == 0)
        #expect(existe(disco, ColaPresion.archivo))
        m.olvidarAlSalir()
        #expect(!existe(disco, ColaPresion.archivo))
        #expect(!existe(disco, ModeloPresion.archivoEstado))
    }

    // MARK: Fotos de inicio

    @Test func fotosInicioAlSalirBorraLoSubidoYConservaLaCola() async {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let disco = Disco(raiz: r, token: token)
        func armar(_ t: String) -> ModeloFotosInicio {
            ModeloFotosInicio(cliente: ClienteRPC(transporte: d), token: t, disco: Disco(raiz: r, token: t), esperar: { _ in })
        }
        let m = armar(token)
        await m.refrescar()
        #expect(m.visible)
        let cuando = Date(timeIntervalSince1970: 1_794_313_800)
        #expect(m.encolar(pose: "frente", jpeg: DobleFotosInicio.jpegDePrueba(), tomadaEn: cuando) == .guardada)
        await m.drenar()
        #expect(d.fotos.count == 1)
        await m.firmar()
        #expect(!m.urls.isEmpty)
        #expect(existe(disco, ModeloFotosInicio.archivoEstado))
        // Sin señal: una foto y la nota esperan.
        d.sinRed = true
        #expect(m.encolar(pose: "perfil", jpeg: DobleFotosInicio.jpegDePrueba(relleno: 9), tomadaEn: cuando) == .guardada)
        #expect(await m.guardarNota("nota de prueba") == .sinSenal)
        await m.drenar()
        let pendiente = m.cola.first!.id

        m.olvidarAlSalir()
        #expect(!m.visible)
        #expect(m.urls.isEmpty, "las miniaturas firmadas no quedan")
        #expect(!existe(disco, ModeloFotosInicio.archivoEstado), "lo ya subido (el estado) no queda en el teléfono")
        #expect(disco.leer([PendienteFotoInicio].self, PendienteFotoInicio.archivo)?.map(\.id) == [pendiente])
        #expect(existe(disco, "\(PendienteFotoInicio.carpeta)/\(pendiente).jpg"))
        #expect(disco.leer(BorradorFotosInicio.self, BorradorFotosInicio.archivo)?.nota == "nota de prueba")
        let jpgs = (try? FileManager.default.contentsOfDirectory(atPath: disco.url(PendienteFotoInicio.carpeta).path)) ?? []
        #expect(jpgs == ["\(pendiente).jpg"], "en el teléfono solo queda el JPEG que no subió")
        d.sinRed = false
        let antes = d.llamadas.count
        await m.refrescar()
        await m.drenar()
        #expect(d.llamadas.count == antes, "después de salir no se llama a nada")

        let ajeno = armar(otro)
        #expect(ajeno.cola.isEmpty && ajeno.notaPendiente == nil)

        let m2 = armar(token)
        #expect(m2.cola.map(\.id) == [pendiente])
        #expect(m2.notaPendiente == "nota de prueba")
        await m2.refrescar()
        await m2.drenar()
        #expect(m2.cola.isEmpty)
        #expect(d.dePose("perfil").count == 1)
        #expect(d.notasRecibidas.last == "nota de prueba")
        #expect(m2.notaPendiente == nil)
    }

    // MARK: Molestias

    @Test func molestiasAlSalirSeBorranDelTelefono() async {
        let d = DobleFeedback()
        let disco = Disco(raiz: raiz(), token: token)
        let m = ModeloFeedback(cliente: ClienteRPC(transporte: d), token: token, disco: disco)
        await m.refrescar()
        var b = ReglasMolestia.Borrador()
        b.zona = "hombro"; b.lado = "derecho"; b.desde = "hoy"; b.cuando = "al_subir"; b.tipo = "sordo"; b.intensidad = 5
        #expect(await m.avisar(id: "id-1", ejercicioId: "press-d1-0", ejercicioNombre: "Press", diaId: "d1", b, version: nil) == .ok)
        await m.refrescar()
        #expect(existe(disco, ModeloFeedback.archivo))
        m.olvidarAlSalir()
        #expect(m.molestia(ejercicio: "press-d1-0") == nil)
        #expect(!m.dueleHabilitado)
        #expect(!existe(disco, ModeloFeedback.archivo))
        let antes = d.llamadas.count
        await m.refrescar()
        #expect(d.llamadas.count == antes)
        #expect(!existe(disco, ModeloFeedback.archivo))
    }

    // MARK: Desde la app

    @Test func salirDeLaAppLimpiaLasTresSecciones() async {
        let d = DobleFotosInicio.escenario("vacio")
        let r = raiz()
        let t = "AAAAAAAAAAAAAAAAAAAA"
        let app = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria(t), raizDisco: r)
        await app.cargar()
        guard let f = app.fotosInicio else { Issue.record("sin modelo"); return }
        for _ in 0..<150 where f.estado == nil { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(f.estado != nil)
        let disco = Disco(raiz: r, token: t)
        #expect(existe(disco, ModeloFotosInicio.archivoEstado))
        // Lo que dejaron las otras dos secciones en una carga anterior.
        disco.guardar(JSONValue.objeto(["habilitado": .bool(true)]), ModeloPresion.archivoEstado)
        disco.guardar(JSONValue.objeto(["molestias": .lista([])]), ModeloFeedback.archivo)
        d.sinRed = true
        #expect(f.encolar(pose: "frente", jpeg: DobleFotosInicio.jpegDePrueba(), tomadaEn: Date()) == .guardada)
        await f.drenar()
        app.salir()
        #expect(app.fotosInicio == nil)
        for n in [ModeloFotosInicio.archivoEstado, ModeloPresion.archivoEstado, ModeloFeedback.archivo] {
            #expect(!existe(disco, n), "\(n)")
        }
        #expect(disco.leer([PendienteFotoInicio].self, PendienteFotoInicio.archivo)?.count == 1)
        // Vuelve con el mismo link: la foto sale.
        d.sinRed = false
        let app2 = ModeloApp(cliente: ClienteRPC(transporte: d), almacen: TokenEnMemoria(t), raizDisco: r)
        await app2.cargar()
        await app2.alVolverLaRed()
        for _ in 0..<150 where d.fotos.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(d.fotos.count == 1)
    }
}
