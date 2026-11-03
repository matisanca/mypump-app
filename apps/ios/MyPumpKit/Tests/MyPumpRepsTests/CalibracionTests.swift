import Foundation
import Testing
@testable import MyPumpReloj
import MyPumpReglas
import MyPumpRepsHerramientas

/// La grabación, el archivo, el almacén, las familias, el modo y la evaluación (tanda 4).
@Suite struct GrabadoraSerieTests {
    /// 800 Hz de aceleración y 200 de giro, como `CMBatchedSensorManager`, en lotes de un segundo.
    func alimentar(_ g: inout GrabadoraSerie, desde t0: Double, segundos: Double, acel: (Double) -> Float = { _ in -1 }) {
        var t = t0
        while t < t0 + segundos {
            let a = (0..<800).map { i in let ti = t + Double(i) / 800; return MuestraEjes(t: ti, x: 0, y: 0, z: acel(ti)) }
            let w = (0..<200).map { i in MuestraEjes(t: t + Double(i) / 200, x: 0.5, y: 0, z: 0) }
            g.agregar(acelerometro: a)
            g.agregar(giroscopio: w)
            t += 1
        }
    }

    @Test func promediaA100HzYRepiteSiFalta() {
        var g = GrabadoraSerie()
        alimentar(&g, desde: 1_000, segundos: 3) { t in t < 1_001 ? -1 : -0.5 }
        // Tres segundos dan ~300 cuadros (el último queda abierto hasta que llega lo que sigue).
        #expect((295...300).contains(g.cuadros.count))
        #expect(g.cuadros[50].az == -1)
        #expect(g.cuadros[150].az == -0.5)
        #expect(g.cuadros[150].gx == 0.5)
    }

    @Test func laVentanaVaDeAbrirACerrarConElFinDelDescanso() throws {
        var g = GrabadoraSerie()
        g.abrirVentana(en: 1_000)
        alimentar(&g, desde: 1_000, segundos: 60)
        g.marcarFinDescanso(en: 1_045)
        let cerrada = g.cerrar(en: 1_059)
        let v = try #require(cerrada)
        #expect(abs(v.cuadros.count - 5_900) <= 2)
        #expect(v.finDescanso.map { abs($0 - 4_500) <= 2 } == true)
        // Cuenta desde 20 s antes del fin del descanso.
        #expect(abs(v.inicioConteo - 2_500) <= 2)
        #expect(v.recortado == 0)
        #expect(g.inicioVentana == nil, "al cerrar, la ventana queda cerrada")
        #expect(g.cerrar(en: 1_060) == nil)
    }

    @Test func elAnilloGuardaLosUltimosCincoMinutos() throws {
        var g = GrabadoraSerie()
        g.abrirVentana(en: 1_000)
        alimentar(&g, desde: 1_000, segundos: 400)
        #expect(g.cuadros.count <= g.capacidad + 1_000)
        let cerrada = g.cerrar(en: 1_399)
        let v = try #require(cerrada)
        #expect(v.cuadros.count <= g.capacidad + 1_000)
        #expect(v.recortado > 80)
        // Sin fin de descanso, el conteo mira los últimos 120 s.
        #expect(abs(Double(v.cuadros.count - v.inicioConteo) - 12_000) <= 2)
    }

    @Test func inicioConteo() {
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 0, finDescanso: nil, hasta: 60) == 0)
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 0, finDescanso: 100, hasta: 150) == 80)
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 90, finDescanso: 100, hasta: 150) == 90)
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 0, finDescanso: 10, hasta: 300) == 180)
    }
}

@Suite struct ArchivoCalibracionTests {
    func registro(_ orden: Int, reps: Int = 10) -> ArchivoCalibracion.Registro {
        let c = SenalSintetica.curlLimpio()
        let enc = EncabezadoSerie(sesion: "s1", orden: orden, confirmada: 1_700_000_000_000, ejercicio: "curl con barra", nombre: "Curl con barra",
                                  familia: .curl, patron: "curl_biceps", equipo: "barbell", serie: orden, reps: reps, kg: 30,
                                  contadas: 10, conteo: ContadorReps.contar(c.cuadros), inicioConteo: 0, fuente: "batched", muneca: "izquierda")
        return .init(encabezado: enc, cuadros: c.cuadros)
    }

    @Test func idaYVueltaConLaEscala() throws {
        let r = registro(1)
        let d = try ArchivoCalibracion.datos(r)
        let leidos = try ArchivoCalibracion.leer(d)
        #expect(leidos.count == 1)
        let l = leidos[0]
        #expect(l.encabezado.muestras == r.cuadros.count)
        #expect(l.encabezado.reps == 10 && l.encabezado.familia == .curl && l.encabezado.contadas == 10)
        for i in stride(from: 0, to: r.cuadros.count, by: 97) {
            #expect(abs(l.cuadros[i].az - r.cuadros[i].az) <= 0.00026)
            #expect(abs(l.cuadros[i].gy - r.cuadros[i].gy) <= 0.00051)
        }
        // El contador da lo mismo sobre lo guardado (la cuantización no le cambia nada).
        #expect(ContadorReps.contar(l.cuadros).reps == ContadorReps.contar(r.cuadros).reps)
        // Compacto: 12 bytes por cuadro sin comprimir; con zlib, menos.
        #expect(d.count < r.cuadros.count * 12)
    }

    @Test func concatenarDaUnArchivoValido() throws {
        let d = try ArchivoCalibracion.datos(registro(1)) + ArchivoCalibracion.datos(registro(2, reps: 8))
        let leidos = try ArchivoCalibracion.leer(d)
        #expect(leidos.map(\.encabezado.orden) == [1, 2])
        #expect(ArchivoCalibracion.encabezados(d).map(\.reps) == [10, 8])
    }

    @Test func unRegistroCortadoAlFinalNoPierdeLosAnteriores() throws {
        let uno = try ArchivoCalibracion.datos(registro(1))
        let dos = try ArchivoCalibracion.datos(registro(2))
        let d = uno + dos.prefix(dos.count / 2)
        #expect(try ArchivoCalibracion.leer(d).count == 1)
        #expect(throws: ArchivoCalibracion.Fallo.magia) { try ArchivoCalibracion.leer(Data("hola mundo".utf8)) }
    }

    /// Nada de la cuenta ni del token en el archivo.
    @Test func elEncabezadoNoTraeLaCuenta() throws {
        let d = try ArchivoCalibracion.datos(registro(1))
        let texto = String(decoding: d, as: UTF8.self)
        #expect(!texto.contains("cuenta") && !texto.contains("token"))
    }
}

@Suite struct AlmacenCalibracionTests {
    func carpeta() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("mpcal-\(UUID().uuidString)") }

    @Test func respetaElTopeBorrandoLosMasViejos() throws {
        let a = AlmacenCalibracion(carpeta: carpeta(), tope: 2_500)
        defer { a.borrarTodo() }
        for i in 0..<5 {
            try a.guardar(Data(repeating: UInt8(i), count: 1_000), nombre: "s\(i).mpcal")
            Thread.sleep(forTimeInterval: 0.01)
        }
        let nombres = a.archivos().map(\.url.lastPathComponent)
        #expect(nombres == ["s3.mpcal", "s4.mpcal"])
        #expect(a.bytes <= 2_500)
    }

    @Test func anexarJuntaLasSeriesDeUnaSesion() throws {
        let a = AlmacenCalibracion(carpeta: carpeta(), tope: AlmacenCalibracion.topeIPhone)
        defer { a.borrarTodo() }
        let r = ArchivoCalibracionTests().registro(1)
        try a.anexar(try ArchivoCalibracion.datos(r), nombre: "sesion.mpcal")
        try a.anexar(try ArchivoCalibracion.datos(ArchivoCalibracionTests().registro(2)), nombre: "sesion.mpcal")
        let d = try Data(contentsOf: a.archivos()[0].url)
        #expect(ArchivoCalibracion.encabezados(d).count == 2)
    }
}

@Suite struct FamiliaMovimientoTests {
    @Test func porPatronDelCatalogo() {
        #expect(FamiliaMovimiento.de(patron: "curl_biceps", equipo: "dumbbell", nombre: "Curl alterno") == .curl)
        #expect(FamiliaMovimiento.de(patron: "empuje_horizontal", equipo: "barbell", nombre: "Press banca") == .empujeHorizontal)
        #expect(FamiliaMovimiento.de(patron: "jalon_vertical", equipo: "cable", nombre: "Jalón al pecho") == .tironVertical)
        #expect(FamiliaMovimiento.de(patron: "sentadilla_prensa", equipo: "barbell", nombre: "Sentadilla") == .sentadilla)
        #expect(FamiliaMovimiento.de(patron: "sentadilla_prensa", equipo: "machine", nombre: "Prensa 45") == .maquinaMunecaQuieta)
        #expect(FamiliaMovimiento.de(patron: "extension_rodilla", equipo: "machine", nombre: "Sillón de cuádriceps") == .maquinaMunecaQuieta)
        #expect(FamiliaMovimiento.de(patron: "elevacion_lateral", equipo: "dumbbell", nombre: "Vuelos laterales") == .elevacionLateral)
    }

    @Test func sinPatronPorElNombre() {
        #expect(FamiliaMovimiento.de(patron: nil, equipo: nil, nombre: "Press francés con barra Z") == .extensionCodo)
        #expect(FamiliaMovimiento.de(patron: nil, equipo: nil, nombre: "Remo con mancuerna") == .tironHorizontal)
        #expect(FamiliaMovimiento.de(patron: nil, equipo: nil, nombre: "Press militar") == .empujeVertical)
        #expect(FamiliaMovimiento.de(patron: nil, equipo: nil, nombre: "Peso muerto rumano") == .bisagra)
        #expect(FamiliaMovimiento.de(patron: nil, equipo: nil, nombre: "Estocadas búlgaras") == .zancada)
        #expect(FamiliaMovimiento.de(patron: nil, equipo: nil, nombre: "Algo raro") == .otra)
        #expect(FamiliaMovimiento.de(patron: "patron_nuevo", equipo: nil, nombre: "Curl martillo") == .curl)
    }

    /// Todos los patrones del catálogo compartido tienen familia (si aparece uno nuevo, esta prueba avisa).
    @Test func todosLosPatronesDelCatalogo() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../shared/catalogo-ejercicios.json").standardizedFileURL
        let lista = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]] ?? []
        let patrones = Set(lista.compactMap { $0["patron_movimiento"] as? String })
        #expect(patrones.count > 30)
        for p in patrones { #expect(FamiliaMovimiento.dePatron(p, maquina: false, nombre: "") != nil, "\(p) sin familia") }
    }
}

@Suite struct ConfirmacionYModoTests {
    let conteo = ContadorReps.Resultado(reps: 10, periodo: 2.5, calidad: 0.9, senal: .giro, desde: 5, hasta: 30, quieto: true)

    @Test func elFlujoFinalEstaApagado() {
        #expect(ConfirmacionReps.habilitadas.isEmpty)
        for f in FamiliaMovimiento.allCases {
            #expect(ConfirmacionReps.propuesta(f, conteo: conteo, calibrando: false) == nil)
            #expect(!ConfirmacionReps.cuenta(f))
        }
    }

    @Test func conUnaFamiliaHabilitadaPropone() {
        let h: Set<FamiliaMovimiento> = [.curl]
        #expect(ConfirmacionReps.propuesta(.curl, conteo: conteo, calibrando: false, habilitadas: h) == 10)
        #expect(ConfirmacionReps.propuesta(.sentadilla, conteo: conteo, calibrando: false, habilitadas: h) == nil)
        // En calibración nunca toca las reps.
        #expect(ConfirmacionReps.propuesta(.curl, conteo: conteo, calibrando: true, habilitadas: h) == nil)
        // Con la serie sin terminar o poco clara, tampoco.
        var c = conteo; c.quieto = false
        #expect(ConfirmacionReps.propuesta(.curl, conteo: c, calibrando: false, habilitadas: h) == nil)
        c = conteo; c.calidad = 0.4
        #expect(ConfirmacionReps.propuesta(.curl, conteo: c, calibrando: false, habilitadas: h) == nil)
        #expect(ConfirmacionReps.texto(10) == "¿10 reps?" && ConfirmacionReps.texto(1) == "¿1 rep?")
    }

    @Test func elModoEsPorCuentaYNuncaEnLaDemo() throws {
        let d = try #require(UserDefaults(suiteName: "calibracion-\(UUID().uuidString)"))
        let m = ModoCalibracion(defaults: d)
        #expect(!m.prendido(cuenta: "abc"))
        #expect(!m.visible(cuenta: "abc"))
        m.poner(true, cuenta: "abc")
        #expect(m.prendido(cuenta: "abc") && !m.prendido(cuenta: "otra"))
        #expect(m.visible(cuenta: "abc"))
        m.poner(true, cuenta: "demo")
        #expect(!m.prendido(cuenta: "demo"))
        m.poner(false, cuenta: "abc")
        #expect(!m.prendido(cuenta: "abc"))
        m.mostrar()
        #expect(m.visible(cuenta: "otra"))
        #expect(ModoCalibracion.cuentasPrecargadas.isEmpty)
        #expect(ModoCalibracion.textoPrivacidad.contains("no sale del teléfono salvo que vos lo exportes"))
    }

    /// La rutina sin los campos nuevos se sigue leyendo (un iPhone viejo), y con el modo apagado no viajan.
    @Test func losCamposNuevosSonOpcionales() throws {
        let r = RutinaReloj.demo(fecha: "2026-11-03", generada: 1)
        #expect(r.calibracion == nil)
        let json = try JSONEncoder().encode(r)
        #expect(!String(decoding: json, as: UTF8.self).contains("calibracion"))
        var conModo = r
        conModo.calibracion = true
        conModo.ejercicios[0].patron = "curl_biceps"
        let leida = try JSONDecoder().decode(RutinaReloj.self, from: JSONEncoder().encode(conModo))
        #expect(leida.calibracion == true && leida.ejercicios[0].familia == .curl)
    }
}

@Suite struct EvaluacionRepsTests {
    @Test func losArchivosSinteticosDanElErrorPorFamilia() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent("eval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: carpeta) }
        let urls = try EvaluacionReps.escribirSinteticos(en: carpeta)
        #expect(urls.count == 5)
        let (registros, fallas) = EvaluacionReps.leer([carpeta])
        #expect(fallas.isEmpty && registros.count == 5)
        let informe = EvaluacionReps.evaluar(registros)
        #expect(informe.total.series == 5)
        #expect(informe.total.dentroDeUno == 5, "\(informe.series)")
        let curl = try #require(informe.filas.first { $0.familia == .curl })
        #expect(curl.series == 2 && curl.porcentajeDentroDeUno == 1)
        #expect(!curl.habilitable, "con 2 series no alcanza: faltan series")
        // Lo guardado en vivo y lo recontado coinciden (mismo contador, mismos datos).
        let guardadas = EvaluacionReps.evaluar(registros, recontar: false)
        #expect(guardadas.series.map(\.contadas) == informe.series.map(\.contadas))
        let texto = EvaluacionReps.texto(informe)
        #expect(texto.contains("Curl") && texto.contains("TOTAL") && texto.contains("faltan series"))
        #expect(EvaluacionReps.csv(informe).split(separator: "\n").count == 6)
    }

    @Test func lasCuentasDelInforme() {
        var s: [EvaluacionReps.Serie] = []
        for i in 0..<40 {
            let contadas: Int = i >= 37 ? 13 : (i % 3 == 0 ? 11 : 10)
            s.append(EvaluacionReps.Serie(archivo: "a", familia: .curl, ejercicio: "curl", cargadas: 10, contadas: contadas, calidad: 0.9))
        }
        let f = EvaluacionReps.informe(s).filas[0]
        #expect(f.series == 40 && f.dentroDeUno == 37 && f.exactas == 24)
        #expect(abs(f.porcentajeDentroDeUno - 0.925) < 1e-9)
        #expect(f.habilitable)
        #expect(abs(f.errorMedio - (13.0 + 9.0) / 40) < 1e-9)
    }
}
