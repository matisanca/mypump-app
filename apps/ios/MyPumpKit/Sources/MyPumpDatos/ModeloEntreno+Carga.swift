import Foundation
import MyPumpModelos
import MyPumpReglas

/// La carga simple desde la app (2.3.0): la carga única por ejercicio, el OK con su guardia, el Deshacer real y la
/// corrección. El OK no le promete nada al servidor hasta que vence la ventana de Deshacer: lo escrito queda demorado
/// (en disco, por si la app muere en el medio) y deshacer dentro de la ventana no escribe nada.
extension ModeloEntreno {
    /// Lo que se escribe y sale recién cuando vence la ventana de Deshacer.
    static func seDemora(_ e: DiaEnCurso.Efecto) -> Bool {
        switch e {
        case .encolar, .diaCompleto: return true
        default: return false
        }
    }

    public struct SerieEnCorreccion: Equatable, Sendable {
        public let lugar: String
        public let indice: Int
    }

    /// El último OK, mientras todavía se puede deshacer.
    public struct OKDeshacible: Equatable, Sendable {
        public let id: UUID
        public let lugar: String
        public let indice: Int
    }

    struct EscrituraDemorada: Codable, Equatable {
        var kind: String
        var payload: JSONValue
        var clave: String
    }

    struct OKGuardado: Codable, Equatable {
        var escrituras: [EscrituraDemorada]
        var diaCompleto: Bool
    }

    struct CargasGuardadas: Codable, Equatable {
        var semana: Int
        var dias: [String: [String: CargaSimple.Estado]] = [:]
        var aumentos: Set<String> = []
    }

    /// Lo que hace falta para volver atrás un OK.
    struct FotoOK {
        let id: UUID
        let lugar: String
        let indice: Int
        let ejercicio: EjercicioEnSesion?
        let estado: String?
        let meta: DiaEnCurso.MetaEstado?
        let expandido: String?
        let carga: CargaSimple.Estado?
        let record: RecordSerie.Marca?
        var diferidos: [DiaEnCurso.Efecto]
    }

    public enum ResultadoOK: Equatable, Sendable {
        case registrada
        case faltanDatos
        /// Se levantó la guardia, o un doble toque que no cuenta.
        case guardia
        /// Lo imposible, o «no» a «¿está bien cargado?»: la serie queda como estaba, con el aviso.
        case noRegistrada
    }

    public enum ResultadoCorreccion: Equatable, Sendable {
        case guardada
        case sinCambios
        case rechazada(String)
    }

    /// El contexto del lugar: el ejercicio que se hace, su equipo real, el mensaje de la semana y hoy.
    func contextoCarga(_ lugar: String) -> DiaEnCurso.ContextoCarga? {
        guard let plan = dia.ejercicio(lugar) else { return nil }
        let conEquipo = hecho(plan)
        let mensaje = estructura.mensajesSemana.first { $0.n == semana }?.msg
        return DiaEnCurso.ContextoCarga(efectivo: efectivo(plan).ejercicio,
                                        equipo: Preparacion.equipo(nombre: conEquipo.nombre, equipo: conEquipo.equipo),
                                        mensajeSemana: mensaje, hoy: FechaJS.ymd(reloj(), zona: zona))
    }

    public func cargaSimple(_ lugar: String) -> CargaSimple? {
        contextoCarga(lugar).flatMap { dia.cargaSimple(lugar, contexto: $0) }
    }

    /// Una acción de la tarjeta de carga o del dial.
    public func cambiarCarga(_ lugar: String, _ accion: (inout CargaSimple) -> Void) {
        guard let c = contextoCarga(lugar) else { return }
        dia.cambiarCarga(lugar, contexto: c, accion)
        guardarCargas()
    }

    // MARK: OK

    /// El OK del panel: guardia, confirmación por el mismo camino de siempre y, si se registró, la ventana de Deshacer.
    /// `venceEn` (segundos): nil no vence sola (VoiceOver).
    public func okSerie(_ lugar: String, _ idx: Int, venceEn: Double? = 6, preguntar: (Pregunta) async -> Bool) async -> ResultadoOK {
        let ahora = ahoraMs
        if guardia.esDobleToque(serie: idx, ahora: ahora) { return .guardia }
        let insistio = guardia.esSegundoToque(serie: idx, ahora: ahora)
        guard let carga = cargaSimple(lugar) else { return .faltanDatos }
        switch carga.evaluarOK(idx, ahora: ahora, insistio: insistio) {
        case .faltanDatos:
            return .faltanDatos
        case .guardia:
            guardia.levantar(serie: idx, ahora: ahora)
            return .guardia
        case .lista(let reps, let kg):
            guardia.limpiar()
            await vaciarDeshacer()
            let e = dia.ejercicios[lugar]
            let foto = FotoOK(id: UUID(), lugar: lugar, indice: idx, ejercicio: e, estado: dia.estados[lugar], meta: dia.meta[lugar],
                              expandido: dia.expandido, carga: dia.cargas[lugar], record: dia.recordsAvisados["\(lugar)|\(idx)"], diferidos: [])
            dia.escribir(lugar, idx, campo: "reps", valor: String(reps))
            dia.escribir(lugar, idx, campo: "kg", valor: kg.map(JS.texto) ?? "")
            let r = await confirmarSerieInterno(lugar, idx, demorar: true, preguntar: preguntar)
            guard dia.ejercicios[lugar]?.series[safe: idx]?.confirmada == true else {
                // No se registró (imposible o «no»): lo que puso el OK no queda como si lo hubiera tipeado. El aviso, sí.
                let aviso = dia.ejercicios[lugar]?.series[safe: idx]?.aviso
                dia.ejercicios[lugar] = e
                dia.ejercicios[lugar]?.series[idx].aviso = aviso
                return .noRegistrada
            }
            cambiarCarga(lugar) { $0.anotarOK(ahora: ahora) }
            if let c = r.completo { diaCompletado = c }
            ventanaDeshacer(foto, diferidos: r.diferidos, venceEn: venceEn)
            return .registrada
        }
    }

    func ventanaDeshacer(_ foto: FotoOK, diferidos: [DiaEnCurso.Efecto], venceEn: Double?) {
        var f = foto
        f.diferidos = diferidos
        fotoOK = f
        deshacible = OKDeshacible(id: f.id, lugar: f.lugar, indice: f.indice)
        guardarOKDemorado(f)
        guard let venceEn else { return }
        let id = f.id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(venceEn * 1000)))
            guard let self, self.fotoOK?.id == id else { return }
            await self.vaciarDeshacer()
        }
    }

    /// El botón Deshacer: el servidor todavía no sabe nada, así que volver atrás es volver atrás de verdad.
    public func deshacerOK() {
        guard let f = fotoOK else { return }
        fotoOK = nil
        deshacible = nil
        disco?.borrar(Archivo.okDemorado)
        dia.ejercicios[f.lugar] = f.ejercicio
        if let s = f.estado { dia.estados[f.lugar] = s } else { dia.estados[f.lugar] = nil }
        dia.meta[f.lugar] = f.meta
        dia.expandido = f.expandido
        dia.cargas[f.lugar] = f.carga
        dia.recordsAvisados["\(f.lugar)|\(f.indice)"] = f.record
        if avisoRecord?.lugar == f.lugar { avisoRecord = nil }
        fechasSeries[claveFecha(f.lugar, f.indice + 1)] = nil
        descanso.detener()
        guardarDescanso()
        guardarCargas()
    }

    /// Cierra la ventana: lo demorado sale a la cola. También al irse a segundo plano, al próximo OK y antes de todo lo que
    /// lea o cambie el día (cerrar, cambiar de día, recargar…).
    public func vaciarDeshacer() async {
        guard let f = fotoOK else { return }
        fotoOK = nil
        deshacible = nil
        let c = await ejecutar(f.diferidos)
        disco?.borrar(Archivo.okDemorado)
        if let c { diaCompletado = c }
    }

    func guardarOKDemorado(_ f: FotoOK) {
        var escrituras: [EscrituraDemorada] = []
        var completo = false
        for e in f.diferidos {
            switch e {
            case .encolar(let kind, let payload, let clave): escrituras.append(EscrituraDemorada(kind: kind, payload: payload, clave: clave))
            case .diaCompleto: completo = true
            default: break
            }
        }
        guard !escrituras.isEmpty || completo else { return }
        disco?.guardar(OKGuardado(escrituras: escrituras, diaCompleto: completo), Archivo.okDemorado)
    }

    /// La app murió con un OK dentro de la ventana: esa serie se registró y no se pierde. Va a la cola antes de leer el
    /// servidor, así `aplicarPendientes` la pinta.
    func recuperarDeshacerGuardado() async {
        guard let g = disco?.leer(OKGuardado.self, Archivo.okDemorado) else { return }
        for e in g.escrituras { await outbox?.encolar(e.kind, e.payload, dedupeKey: e.clave) }
        disco?.borrar(Archivo.okDemorado)
    }

    // MARK: Corrección

    public func cancelarCorreccion() { corrigiendo = nil }

    /// Guardar la corrección abierta: pasa por los mismos topes y reescribe esa serie.
    public func guardarCorreccion(reps: Int, kg: Double?, preguntar: (Pregunta) async -> Bool) async -> ResultadoCorreccion {
        guard let c = corrigiendo, let ctx = contextoCarga(c.lugar) else { return .sinCambios }
        var r = dia.corregirSerie(c.lugar, c.indice, reps: reps, kg: kg, efectivo: ctx.efectivo)
        if case .preguntar(let p) = r {
            let si = await preguntar(p)
            r = dia.corregirSerie(c.lugar, c.indice, reps: reps, kg: kg, efectivo: ctx.efectivo, registrarIgual: si)
        }
        switch r {
        case .guardada(let efectos):
            await ejecutar(efectos)
            corrigiendo = nil
            return .guardada
        case .sinCambios, .faltanDatos, .preguntar:
            corrigiendo = nil
            return .sinCambios
        case .rechazada(let aviso):
            return .rechazada(aviso)
        }
    }

    /// «Cambiarlas también»: las hechas pasan a la carga actual, de a una por el camino de la corrección.
    public func aplicarCargaALasHechas(_ lugar: String) async {
        guard let ctx = contextoCarga(lugar) else { return }
        await vaciarDeshacer()
        var indices: [Int] = []
        dia.cambiarCarga(lugar, contexto: ctx) { indices = $0.aplicarCargaALasHechas() }
        guard let carga = dia.cargaSimple(lugar, contexto: ctx)?.carga else { return }
        for i in indices {
            guard let s = dia.ejercicios[lugar]?.series[safe: i], let r = Int(s.reps) else { continue }
            if case .guardada(let efectos) = dia.corregirSerie(lugar, i, reps: r, kg: carga, efectivo: ctx.efectivo, registrarIgual: true) {
                await ejecutar(efectos)
            }
        }
        guardarCargas()
    }

    // MARK: Disco

    func guardarCargas() {
        guard let d = dia.dia.id else { return }
        var g = disco?.leer(CargasGuardadas.self, Archivo.cargas(rutina.id)) ?? CargasGuardadas(semana: semana)
        if g.semana != semana { g = CargasGuardadas(semana: semana) }
        g.dias[d] = dia.cargas
        g.aumentos = dia.aumentosSemana
        disco?.guardar(g, Archivo.cargas(rutina.id))
    }

    /// Solo la semana actual: la semana que viene las referencias vuelven a salir del historial.
    func leerCargas() {
        guard let d = dia.dia.id, let g = disco?.leer(CargasGuardadas.self, Archivo.cargas(rutina.id)), g.semana == semana else {
            dia.cargas = [:]
            dia.aumentosSemana = []
            return
        }
        dia.cargas = g.dias[d] ?? [:]
        dia.aumentosSemana = g.aumentos
    }
}
