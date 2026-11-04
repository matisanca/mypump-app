import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos
@testable import MyPumpReglas

/// 2.1, S2: el historial de Progreso como registros del volumen (la regla está en el kit, con vectores).
@Suite("Volumen por músculo: datos")
struct VolumenDatosTests {
    private func filas(_ json: String) throws -> [RegistroHistorico] {
        try JSONDecoder().decode([RegistroHistorico].self, from: Data(json.utf8))
    }

    @Test func elHistorialSaleConSuNumeroYConElMusculoDeSuClave() throws {
        let zona = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        let h = try ["press banca": filas(#"[{"clave":"press banca","registrado_en":"2026-11-03T02:30:00+00:00","serie_numero":1},{"clave":"press banca","registrado_en":"2026-11-03T13:00:00+00:00","serie_numero":1}]"#),
                     "cinta": filas(#"[{"clave":"cinta","registrado_en":"2026-11-03T13:00:00+00:00","serie_numero":1}]"#),
                     "viejo": filas(#"[{"clave":"viejo","registrado_en":"2026-11-03T13:00:00+00:00","serie_numero":1}]"#)]
        let info = ["press banca": VolumenDatos.Info(musculo: "chest", tipo: "compuesto"), "cinta": .init(musculo: nil, tipo: "cardio")]
        let r = VolumenDatos.registros(historial: h, ejercicios: info, zona: zona)
        #expect(r.map(\.lugar) == ["cinta", "press banca", "press banca", "viejo"])
        // Con su número y su clave (para no sumar de nuevo lo en vivo); cada fila cuenta igual.
        #expect(r.allSatisfy { $0.serie == 1 && $0.clave == $0.lugar })
        // 02:30 UTC del 3 es el 2 a la noche en Buenos Aires.
        #expect(r.filter { $0.lugar == "press banca" }.map(\.fecha) == ["2026-11-02", "2026-11-03"])
        let v = VolumenMusculo.calcular(historial: r, hoy: "2026-11-04")
        // Las dos series de press cuentan (mismo número, otro día); la cinta no; lo que ya no está en el plan, sin músculo.
        #expect(v.filas.map(\.nombre) == ["Pecho", VolumenMusculo.sinMusculo])
        #expect(v.filas.map(\.semana) == [2, 1])
    }

    @Test func unLugarDeTrabajoLeGanaAlCalentamientoConElMismoNombre() {
        #expect(VolumenDatos.esDeTrabajoMejor(ya: "calentamiento", nuevo: "compuesto"))
        #expect(VolumenDatos.esDeTrabajoMejor(ya: "cardio", nuevo: nil))
        #expect(!VolumenDatos.esDeTrabajoMejor(ya: "compuesto", nuevo: "calentamiento"))
        #expect(!VolumenDatos.esDeTrabajoMejor(ya: "compuesto", nuevo: "aislamiento"))
        #expect(!VolumenDatos.esDeTrabajoMejor(ya: "calentamiento", nuevo: "cardio"))
    }
}

/// Revisión del 3-nov: lo confirmado en el teléfono va con su fecha real, no con la de hoy.
@Suite("Volumen por músculo: lo en vivo con su fecha real", .serialized)
@MainActor
struct VolumenEnVivoTests {
    func confirmar(_ m: ModeloEntreno, _ lugar: String, _ i: Int) async {
        m.escribir(lugar, i, campo: "reps", valor: "10")
        m.escribir(lugar, i, campo: "kg", valor: "60")
        await m.confirmarSerie(lugar, i) { _ in true }
    }

    @Test func laSerieTocadaQuedaConLaFechaDelToque() async {
        let b = Banco()
        let m = b.modelo()
        #expect(m.registrosVolumenEnVivo.isEmpty)
        await confirmar(m, "jal-d1-0", 0)
        await confirmar(m, "jal-d1-0", 1)
        let r = m.registrosVolumenEnVivo
        #expect(r.map(\.serie) == [1, 2])
        #expect(r.allSatisfy { $0.fecha == "2026-10-14" && $0.lugar == "jal-d1-0" && $0.clave == ClaveEjercicio.de("Jalón al pecho") })
        // Al día siguiente, el mismo día del plan abierto sigue siendo del 14: no cuenta como hoy.
        b.reloj.ms += 86_400_000
        #expect(m.registrosVolumenEnVivo.allSatisfy { $0.fecha == "2026-10-14" })
        let v = VolumenMusculo.calcular(historial: [], enVivo: m.registrosVolumenEnVivo, hoy: "2026-10-15")
        #expect(v.total == 2 && v.totalHoy == 0)
        // Corregirla (el lápiz) no le cambia la fecha: el servidor conserva el `registrado_en`.
        await m.editarSerie("jal-d1-0", 0)
        await m.confirmarSerie("jal-d1-0", 0) { _ in true }
        #expect(m.registrosVolumenEnVivo.first?.fecha == "2026-10-14")
    }

    @Test func lasSeriesDelServidorTraenSuRegistradoEnYNoSeCuentanDosVeces() async {
        let b = Banco()
        b.servidor.cuando("get_sesion_dia", sesionJSON("ses-lunes"))
        b.servidor.cuando("get_registros_sesion", """
        [{"ejercicio_id":"jal-d1-0","serie_numero":1,"peso_kg":60,"reps_realizadas":10,"rir_real":1,"ejercicio_nombre":"Jalón al pecho","notas":null,"registrado_en":"2026-10-12T22:00:00+00:00"},
         {"ejercicio_id":"jal-d1-0","serie_numero":2,"peso_kg":60,"reps_realizadas":9,"rir_real":1,"ejercicio_nombre":"Jalón al pecho","notas":null,"registrado_en":"2026-10-12T22:03:00+00:00"},
         {"ejercicio_id":"rem-d1-1","serie_numero":1,"peso_kg":50,"reps_realizadas":8,"rir_real":1,"ejercicio_nombre":"Remo con barra","notas":null}]
        """)
        let m = b.modelo()
        await m.restaurarSesion()
        // La sesión del lunes, mirada el miércoles: cada serie con su fecha; la que no trae fecha no va en vivo.
        let r = m.registrosVolumenEnVivo
        #expect(r.map(\.lugar) == ["jal-d1-0", "jal-d1-0"])
        #expect(r.allSatisfy { $0.fecha == "2026-10-12" })
        let clave = ClaveEjercicio.de("Jalón al pecho")
        let historial = [1, 2].map { VolumenMusculo.Registro(musculo: "lats", tipo: "compuesto", fecha: "2026-10-12", lugar: clave, serie: $0, clave: clave) }
        let v = VolumenMusculo.calcular(historial: historial, enVivo: r, hoy: "2026-10-14")
        #expect(v.total == 2, "las del lunes contaban dos veces")
        #expect(v.totalHoy == 0, "y como de hoy")
    }

    @Test func loQueQuedoEnLaColaVaConLaFechaDeLaCola() async throws {
        let b = Banco()
        let m = b.modelo()
        await confirmar(m, "jal-d1-0", 0)
        let op = try #require(await b.cola.operaciones.first { $0.kind == "carga" })
        // Otro arranque, sin red: la serie vuelve de la cola con la fecha en que se encoló.
        b.servidor.sinRed("get_sesion_dia")
        let otro = b.modelo()
        await otro.restaurarSesion()
        let esperada = FechaJS.ymd(Date(timeIntervalSince1970: op.ts / 1000), zona: zonaAR)
        #expect(otro.registrosVolumenEnVivo.map(\.fecha) == [esperada])
    }

    @Test func otraSesionNoHeredaLasFechas() async {
        let b = Banco()
        let m = b.modelo()
        m.anotarFecha("jal-d1-0", 1, "2026-07-20")
        #expect(m.fechasSeries.count == 1)
        b.servidor.cuando("get_sesion_dia", "[]")
        await m.restaurarSesion()
        #expect(m.fechasSeries.isEmpty, "una clave repetida heredaba la fecha de la sesión anterior")
    }

    @Test func unCatalogoNuevoDelMismoTamanoCambiaLaFirma() {
        let m = Banco().modelo()
        let antes = m.firmaVolumenEnVivo
        let otro = try! CatalogoEjercicios(json: Data("""
        [{"slug_en":"A","name_en":"A","primary_muscle":"chest","equipment":"cable","patron_movimiento":"x"},
         {"slug_en":"B","name_en":"B","primary_muscle":"chest","equipment":"cable","patron_movimiento":"x"},
         {"slug_en":"C","name_en":"C","primary_muscle":"chest","equipment":"cable","patron_movimiento":"x"}]
        """.utf8))
        #expect(otro.entradas.count == m.catalogo.entradas.count)
        m.actualizarCatalogo(otro)
        #expect(m.firmaVolumenEnVivo != antes)
    }

    @Test func elVolumenDeLaAppSeCacheaYSeRecalculaAlConfirmar() async throws {
        let hoy = FechaLocal.hoy()
        let banca = ClaveEjercicio.de("Press banca")
        func fila(_ n: Int) -> String {
            #"{"clave":"\#(banca)","registrado_en":"\#(hoy)T15:00:00+00:00","peso_kg":80,"reps_realizadas":8,"rir_real":1,"serie_numero":\#(n),"notas":null,"ejercicio_nombre":"Press banca"}"#
        }
        let historico = "[\(fila(1)),\(fila(2))]", rutina = "[\(filaRutina())]"
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#)
            case "mypump_get_rutina_activa": return (200, rutina)
            case "mypump_get_historico_por_clave": return (200, historico)
            default: return (200, "[]")
            }
        }
        let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("volumen-cache-\(UUID().uuidString)")
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: TokenEnMemoria("AAAAAAAAAAAAAAAAAAAA"), raizDisco: raiz)
        await m.cargar()
        await m.cargarProgreso()
        let entreno = try #require(m.entreno)
        let v1 = m.volumenPorMusculo()
        #expect(v1.total == 2)
        let firma = try #require(m.cacheVolumen?.firma)
        #expect(m.volumenPorMusculo() == v1)
        #expect(m.cacheVolumen?.firma == firma, "sin cambios no se recalcula")
        let lugar = try #require(entreno.dia.lista.first { $0.tipo != "calentamiento" && $0.tipo != "cardio" }?.id)
        entreno.escribir(lugar, 0, campo: "reps", valor: "10")
        entreno.escribir(lugar, 0, campo: "kg", valor: "60")
        await entreno.confirmarSerie(lugar, 0) { _ in true }
        #expect(m.cacheVolumen?.firma == firma)
        let v2 = m.volumenPorMusculo()
        #expect(m.cacheVolumen?.firma != firma, "una serie confirmada cambia la firma")
        #expect(v2.total == 3 && v2.totalHoy == 3, "\(v2)")
    }
}
