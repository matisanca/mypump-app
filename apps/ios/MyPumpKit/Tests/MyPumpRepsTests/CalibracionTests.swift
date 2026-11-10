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
        // Cuenta la ventana entera: la serie puede arrancar antes de que termine el descanso.
        #expect(v.inicioConteo == 0)
        #expect(v.recortado == 0)
        #expect(g.inicioVentana == nil, "al cerrar, la ventana queda cerrada")
        #expect(g.cerrar(en: 1_060) == nil)
    }

    @Test func unHuecoDeHorasNoRellenaMasQueElAnillo() throws {
        var g = GrabadoraSerie()
        g.abrirVentana(en: 1_000)
        alimentar(&g, desde: 1_000, segundos: 10)
        alimentar(&g, desde: 1_000 + 8 * 3_600, segundos: 2)
        #expect(g.cuadros.capacity <= 2 * (g.capacidad + 1_000), "sin el salto el array llegaba a millones de cuadros")
        #expect((g.capacidad...(g.capacidad + 200)).contains(g.cuadros.count))
        let h = try #require(g.ultimoHueco)
        #expect(abs(h.desde - 1_010) < 0.1, "el hueco arranca donde terminó lo grabado")
        #expect(abs(h.hasta - (1_000 + 8 * 3_600)) < 0.1)
        #expect(g.cuadros.last?.gx == 0.5, "lo posterior al hueco quedó")
    }

    @Test func unHuecoCortoSeSigueRellenando() {
        var g = GrabadoraSerie()
        alimentar(&g, desde: 1_000, segundos: 2)
        alimentar(&g, desde: 1_100, segundos: 2)
        #expect(g.primero == 0)
        #expect(g.cuadros.count > 10_000)
        #expect(g.ultimoHueco != nil)
    }

    @Test func alCerrarCuentaConLaMismaReglaQueEnVivo() throws {
        let serie = SenalSintetica.casos[0].cuadros
        func muestras(_ c: ArraySlice<CuadroSensor>, _ t0: Double) -> [MuestraEjes] { c.enumerated().map { MuestraEjes(t: t0 + (Double($0.offset) + 0.5) / 100, x: $0.element.ax, y: $0.element.ay, z: $0.element.az) } }
        var g = GrabadoraSerie()
        g.abrirVentana(en: 1_000)
        let m = muestras(serie[...], 1_000)
        g.agregar(acelerometro: m, giroscopio: m)
        let duracion = Double(serie.count) / 100
        let sinMarca = g.contarEnVivo(hasta: 1_000 + duracion)
        #expect((sinMarca?.reps ?? 0) >= 5, "la señal de prueba tiene que contar")
        let silencio = (0..<2_500).map { _ in CuadroSensor(ax: serie[serie.count - 1].ax, ay: serie[serie.count - 1].ay, az: serie[serie.count - 1].az, gx: 0, gy: 0, gz: 0) }
        let s = muestras(silencio[...], 1_000 + duracion)
        g.agregar(acelerometro: s, giroscopio: s)
        g.marcarFinDescanso(en: 1_000 + duracion + 24)   // terminó de descansar 24 s después de la racha: no era la serie
        let t = 1_000 + duracion + 24.9
        let vivo = try #require(g.contarEnVivo(hasta: t))
        let cerrada = g.cerrar(en: t)
        let v = try #require(cerrada)
        #expect(vivo.reps == 0)
        #expect(v.contar().reps == vivo.reps)
        var sinDescanso = v
        sinDescanso.finDescanso = nil
        #expect(sinDescanso.contar().reps >= 5, "sin fin de descanso se cuenta como siempre")
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

    /// El conteo no depende del descanso: en la grabación real una serie hecha antes de cerrarlo quedaba afuera.
    @Test func inicioConteo() {
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 0, hasta: 60) == 0)
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 90, hasta: 150) == 90)
        #expect(GrabadoraSerie.inicioConteo(inicioVentana: 0, hasta: 300) == 180)
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

    /// Lo que propuso el reloj y si se tocó viajan en el encabezado, también al rearmarlo como hace el iPhone.
    @Test func elEncabezadoConLaPropuestaVaYVuelve() throws {
        var r = registro(1)
        r.encabezado.propuesta = 9
        r.encabezado.corregida = true
        let l = try #require(ArchivoCalibracion.leer(ArchivoCalibracion.datos(r)).first)
        #expect(l.encabezado.propuesta == 9 && l.encabezado.corregida == true)
        // El iPhone vuelve a escribir los registros que le llegan (CalibracionView.recibir).
        let otra = try #require(ArchivoCalibracion.leer(ArchivoCalibracion.datos(l)).first)
        #expect(otra.encabezado == l.encabezado)
        #expect(try ArchivoCalibracion.encabezados(ArchivoCalibracion.datos(r)).first?.propuesta == 9)
        // Sin propuesta, las claves no se escriben (un archivo nuevo sin propuesta es igual a uno viejo).
        let sin = String(decoding: try ArchivoCalibracion.datos(registro(1)), as: UTF8.self)
        #expect(!sin.contains("propuesta") && !sin.contains("corregida"))
    }

    /// Un archivo de antes (encabezado sin `propuesta` ni `corregida`) se sigue leyendo.
    @Test func unArchivoViejoSeLee() throws {
        let c = SenalSintetica.curlLimpio().cuadros.prefix(200)
        var crudo = Data()
        for q in c {
            for (v, e) in [(q.ax, ArchivoCalibracion.escalaAcel), (q.ay, ArchivoCalibracion.escalaAcel), (q.az, ArchivoCalibracion.escalaAcel),
                           (q.gx, ArchivoCalibracion.escalaGiro), (q.gy, ArchivoCalibracion.escalaGiro), (q.gz, ArchivoCalibracion.escalaGiro)] {
                withUnsafeBytes(of: Int16(clamping: Int((Double(v) / e).rounded())).littleEndian) { crudo.append(contentsOf: $0) }
            }
        }
        let comprimido = try (crudo as NSData).compressed(using: .zlib) as Data
        // El JSON tal como lo escribía el reloj antes del 3-nov.
        let json = Data(#"{"confirmada":1700000000000,"contadas":10,"ejercicio":"curl con barra","escalaAcel":0.0005,"escalaGiro":0.001,"familia":"curl","fuente":"batched","hz":100,"inicioConteo":0,"muestras":200,"nombre":"Curl con barra","orden":1,"recortado":0,"reps":10,"serie":1,"sesion":"s1","v":1}"#.utf8)
        var d = ArchivoCalibracion.magia
        ArchivoCalibracion.anexar(UInt32(json.count), a: &d); d.append(json)
        ArchivoCalibracion.anexar(UInt32(comprimido.count), a: &d); d.append(comprimido)
        let l = try #require(ArchivoCalibracion.leer(d).first)
        #expect(l.encabezado.reps == 10 && l.cuadros.count == 200)
        #expect(l.encabezado.propuesta == nil && l.encabezado.corregida == nil)
        #expect(EvaluacionReps.Origen.de(l.encabezado) == .sinPropuesta)
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
    let conteo = ContadorReps.Resultado(reps: 10, periodo: 2.5, calidad: 0.9, senal: .acel, desde: 5, hasta: 30, quieto: true, esfuerzo: 0.15, amplitud: 0.5)

    /// Propone en todas las familias, con las condiciones de serie clara.
    @Test func proponeSoloConSerieClara() {
        #expect(ConfirmacionReps.propuesta(conteo) == 10)
        var c = conteo; c.quieto = false
        #expect(ConfirmacionReps.propuesta(c) == nil, "serie sin terminar")
        c = conteo; c.calidad = ConfirmacionReps.calidadMinima - 0.01
        #expect(ConfirmacionReps.propuesta(c) == nil, "poco clara")
        c.calidad = ConfirmacionReps.calidadMinima
        #expect(ConfirmacionReps.propuesta(c) == 10, "justo en el mínimo")
        c = conteo; c.esfuerzo = 0.04
        #expect(ConfirmacionReps.propuesta(c) == nil, "sin carga: una racha del descanso")
        c = conteo; c.reps = ContadorReps.repsMinimas - 1
        #expect(ConfirmacionReps.propuesta(c) == nil, "debajo del mínimo")
        c.reps = SesionReloj.repsMax + 1
        #expect(ConfirmacionReps.propuesta(c) == nil, "arriba del rango")
        #expect(ConfirmacionReps.texto(10) == "¿10 reps?" && ConfirmacionReps.texto(1) == "¿1 rep?")
        #expect(ConfirmacionReps.textoAccesible(10).contains("contó 10 repeticiones"))
    }

    @Test func nuncaSePisaLoQueGiro() {
        var p = PropuestaSerie()
        #expect(p.corregida(confirmadas: 10) == nil && !p.enLaCorona(10))
        p.girar()
        #expect(p.proponer(conteo) == nil, "giró antes: no se le pisa")
        #expect(p.reps == nil && p.corregida(confirmadas: 12) == nil)
        p.reiniciar()
        #expect(p == PropuestaSerie())
        #expect(p.proponer(conteo) == 10)
        #expect(p.enLaCorona(10) && p.corregida(confirmadas: 10) == false)
        p.girar()
        var mas = conteo; mas.reps = 12
        #expect(p.proponer(mas) == nil, "giró después: tampoco")
        #expect(p.corregida(confirmadas: 11) == true && !p.enLaCorona(11) && p.reps == 10)
    }

    /// Sin que el alumno toque, la propuesta sigue a la última serie clara: una racha falsa del descanso no se gasta la real.
    @Test func laPropuestaSigueALaUltimaSerieClara() {
        var p = PropuestaSerie()
        var falsa = conteo; falsa.reps = 6
        #expect(p.proponer(falsa) == 6)
        #expect(p.proponer(falsa) == nil, "lo mismo no se repite")
        #expect(p.proponer(conteo) == 10, "la serie real, más larga, la reemplaza")
        var sinTerminar = conteo; sinTerminar.quieto = false; sinTerminar.reps = 3
        #expect(p.proponer(sinTerminar) == nil, "lo que no es claro no mueve la corona")
        #expect(p.reps == 10)
    }

    @Test func laPantallaNuncaQuedaMuda() {
        func a(prendido: Bool = true, iniciada: Bool = true, descanso: Bool = false, propuesta: Bool = false, muestras: Bool = true, viva: Bool = true,
               conteo: ContadorReps.Resultado? = nil, f: FamiliaMovimiento = .curl) -> AvisoConteo {
            AvisoConteo.de(prendido: prendido, iniciada: iniciada, enDescanso: descanso, conPropuesta: propuesta, muestras: muestras,
                           sesionViva: viva, conteo: conteo, familia: f)
        }
        #expect(a(prendido: false) == .ninguno)
        #expect(a(descanso: true) == .ninguno)
        #expect(a(propuesta: true) == .ninguno)
        #expect(a(iniciada: false) == .falta_empezar)
        #expect(a(muestras: false) == .sinSensores, "permiso negado o sensor apagado")
        #expect(a(viva: false) == .sinSesion, "sesión cortada")
        var enCurso = conteo; enCurso.quieto = false; enCurso.reps = 6
        #expect(a(conteo: enCurso) == .contando(6))
        #expect(a() == .noPude(munecaQuieta: false))
        #expect(a(f: .maquinaMunecaQuieta) == .noPude(munecaQuieta: true))
        for caso: AvisoConteo in [.falta_empezar, .sinSensores, .sinSesion, .contando(3), .noPude(munecaQuieta: true), .noPude(munecaQuieta: false)] {
            #expect(caso.texto?.isEmpty == false)
        }
    }

    /// Un hueco de muestras dentro de la serie (app suspendida, sesión cortada) no da la serie por terminada.
    @Test func unHuecoNoEsElFinDeLaSerie() {
        var g = GrabadoraSerie()
        g.abrirVentana(en: 1_000)
        func picos(_ t: Double) -> Float { Float(-1 + 0.2 * max(0, sin(2 * .pi * t / 3))) }
        var t = 1_000.0
        func dar(hasta fin: Double) {
            while t < fin {
                var ac: [MuestraEjes] = [], gi: [MuestraEjes] = []
                for k in 0..<25 { let ts = t + Double(k) / 100 + 0.005; ac.append(.init(t: ts, x: 0, y: 0, z: picos(ts - 1_000))); gi.append(.init(t: ts, x: 0, y: 0, z: 0)) }
                g.agregar(acelerometro: ac, giroscopio: gi)
                t += 0.25
            }
        }
        dar(hasta: 1_030)
        t = 1_050   // 20 s sin nada: la app estuvo suspendida
        dar(hasta: 1_052)
        let v = try? #require(g.contarEnVivo(hasta: 1_052))
        #expect(v?.quieto == false, "\(String(describing: v))")
        #expect(g.ultimoHueco != nil)
    }

    /// `corregida` sale de lo que se confirma, no de si se giró: girar y volver al número propuesto deja la etiqueta
    /// igual a la del reloj (aceptada, del lado seguro); y si la corona cambió sin que el alumno girara (la rutina del
    /// iPhone la recargó), lo confirmado ya no es la propuesta y el cartel «¿N reps?» no se muestra.
    @Test func corregidaSaleDeLoQueSeConfirma() {
        var p = PropuestaSerie()
        #expect(p.proponer(conteo) == 10)
        p.girar(); p.girar()   // +1 y −1
        #expect(p.corregida(confirmadas: 10) == false && p.enLaCorona(10))
        var q = PropuestaSerie()
        #expect(q.proponer(conteo) == 10)
        // Sin girar, la corona volvió a lo sugerido (12).
        #expect(q.corregida(confirmadas: 12) == true && !q.enLaCorona(12))
        #expect(EvaluacionReps.Origen.de(EncabezadoSerie(sesion: "s", orden: 1, confirmada: 0, ejercicio: "curl", nombre: "Curl",
                                                         familia: .curl, serie: 1, reps: 12, propuesta: 10,
                                                         corregida: q.corregida(confirmadas: 12), fuente: "t")) == .corregida)
    }

    /// Grabar a archivo es aparte del contador: apagado por defecto, por cuenta y nunca en la demo.
    @Test func elModoVieneApagadoSePrendePorCuentaYNuncaEnLaDemo() throws {
        let d = try #require(UserDefaults(suiteName: "calibracion-\(UUID().uuidString)"))
        let m = ModoCalibracion(defaults: d)
        #expect(!m.prendido(cuenta: "abc") && !m.prendido(cuenta: "otra"))
        m.poner(true, cuenta: "abc")
        #expect(m.prendido(cuenta: "abc") && !m.prendido(cuenta: "otra"))
        m.poner(false, cuenta: "abc")
        #expect(!m.prendido(cuenta: "abc"))
        m.poner(true, cuenta: "demo")
        #expect(!m.prendido(cuenta: "demo") && !m.prendido(cuenta: ""))
        #expect(ModoCalibracion.textoPrivacidad.contains("Apagado por defecto"))
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

    /// Un iPhone viejo no manda la clave: el reloj cuenta. Sólo un false explícito lo apaga.
    /// Un relanzamiento del reloj no puede olvidar que el alumno giró ni que el número lo puso el reloj.
    @Test func laPropuestaSobreviveAlRelanzamiento() throws {
        var p = PropuestaSerie()
        #expect(p.proponer(conteoParaPropuesta) == 10)
        p.girar()
        let leida = try JSONDecoder().decode(PropuestaSerie.self, from: JSONEncoder().encode(p))
        #expect(leida == p && leida.tocada && leida.reps == 10)
    }

    /// Ya a la vista, una racha posterior más corta no cambia el número; si la serie siguió, sube.
    @Test func elNumeroALaVistaSoloSube() {
        var p = PropuestaSerie()
        var c = conteoParaPropuesta
        #expect(p.proponer(c) == 10)
        c.reps = 6
        #expect(p.proponer(c) == nil && p.reps == 10)
        c.reps = 11
        #expect(p.proponer(c) == 11)
    }

    @Test func laPalancaDelContadorEsOpcional() throws {
        var r = RutinaReloj.demo(fecha: "2026-11-03", generada: 1)
        #expect(r.contadorReps == nil)
        #expect(!String(decoding: try JSONEncoder().encode(r), as: UTF8.self).contains("contadorReps"))
        r.contadorReps = false
        #expect(try JSONDecoder().decode(RutinaReloj.self, from: JSONEncoder().encode(r)).contadorReps == false)
    }
}

private let conteoParaPropuesta = ContadorReps.Resultado(reps: 10, periodo: 2.5, calidad: 0.9, senal: .acel, desde: 5, hasta: 30, quieto: true, esfuerzo: 0.15, amplitud: 0.5)

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
        // La sentadilla sintética casi no mueve el reloj: el contador de aceleración la cuenta de menos (y no la propone).
        #expect(informe.total.dentroDeUno >= 3, "\(informe.series)")
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

    @Test func elOrigenDeLaEtiqueta() {
        func enc(_ p: Int?, _ c: Bool?) -> EncabezadoSerie {
            EncabezadoSerie(sesion: "s", orden: 1, confirmada: 0, ejercicio: "curl", nombre: "Curl", familia: .curl, serie: 1, reps: 10,
                            propuesta: p, corregida: c, fuente: "x")
        }
        #expect(EvaluacionReps.Origen.de(enc(nil, nil)) == .sinPropuesta)
        #expect(EvaluacionReps.Origen.de(enc(10, false)) == .aceptada)
        #expect(EvaluacionReps.Origen.de(enc(10, true)) == .corregida)
        // Sin el dato de si se tocó, del lado seguro: no decide.
        #expect(EvaluacionReps.Origen.de(enc(10, nil)) == .aceptada)
    }

    /// Las aceptadas sin tocar van aparte y no deciden: 40 aceptadas «perfectas» no prenden una familia.
    @Test func lasAceptadasSinTocarNoDeciden() throws {
        var s: [EvaluacionReps.Serie] = []
        for _ in 0..<40 {
            s.append(.init(archivo: "a", familia: .curl, ejercicio: "curl", cargadas: 10, contadas: 10, calidad: 0.9, propuesta: 10, origen: .aceptada))
        }
        s.append(.init(archivo: "b", familia: .curl, ejercicio: "curl", cargadas: 10, contadas: 8, calidad: 0.9, propuesta: 8, origen: .corregida))
        s.append(.init(archivo: "c", familia: .curl, ejercicio: "curl", cargadas: 10, contadas: 10, calidad: 0.9))
        let i = EvaluacionReps.informe(s)
        let curl = try #require(i.filas.first { $0.familia == .curl })
        #expect(curl.series == 2 && curl.dentroDeUno == 1 && !curl.habilitable)
        #expect(i.total.series == 2)
        #expect(i.aceptadas.series == 40 && i.filasAceptadas.first?.familia == .curl && i.corregidas == 1)
        #expect(i.series.count == 42)
        let texto = EvaluacionReps.texto(i)
        #expect(texto.contains("DECIDEN") && texto.contains("NO deciden"))
        #expect(texto.contains("41 series con propuesta: 40 aceptadas sin tocar, 1 corregidas."))
        let csv = EvaluacionReps.csv(i).split(separator: "\n")
        #expect(csv[0].hasSuffix(",propuesta,origen") && csv.count == 43)
        #expect(csv.contains { $0.hasSuffix(",10,aceptada") } && csv.contains { $0.hasSuffix(",,sin_propuesta") })
        // Sin propuestas, el texto no muestra la segunda tabla.
        #expect(!EvaluacionReps.texto(EvaluacionReps.informe(Array(s.suffix(1)))).contains("NO deciden"))
    }

    /// Desde los archivos: el encabezado decide el grupo.
    @Test func desdeLosArchivosSeparaLosGrupos() {
        let c = SenalSintetica.curlLimpio()
        func reg(_ p: Int?, _ k: Bool?) -> (archivo: String, registro: ArchivoCalibracion.Registro) {
            ("x", .init(encabezado: EncabezadoSerie(sesion: "s", orden: 1, confirmada: 0, ejercicio: "curl", nombre: "Curl", familia: .curl,
                                                    serie: 1, reps: c.reps, propuesta: p, corregida: k, fuente: "x"), cuadros: c.cuadros))
        }
        let i = EvaluacionReps.evaluar([reg(nil, nil), reg(c.reps, false), reg(c.reps, true)])
        #expect(i.total.series == 2 && i.aceptadas.series == 1 && i.corregidas == 1)
        #expect(i.series.map(\.origen) == [.sinPropuesta, .aceptada, .corregida])
    }
}
