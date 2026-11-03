import CryptoKit
import Foundation
import MyPumpModelos
import MyPumpReglas
import MyPumpReloj

/// El Apple Watch visto desde el motor de Entreno (tanda 3, 2.2): la rutina del día para el reloj y los eventos del reloj
/// aplicados por el mismo camino que un toque en la pantalla (así van a la cola de siempre, con su sesión, su descanso y
/// su récord). El iPhone es el único que habla con el servidor.
extension ModeloEntreno {
    /// La rutina del día como la ve el reloj: lo mismo que pintan las cards (lo sugerido de cada serie, el descanso, la
    /// preparación del plan o los datos para que el reloj la arme con el kit, y las marcas para el récord).
    public func rutinaReloj() -> RutinaReloj {
        let hoy = FechaJS.ymd(reloj(), zona: zona)
        let ejercicios: [EjercicioReloj] = dia.lista.map { plan in
            let lugar = plan.id
            let ef = efectivo(plan).ejercicio
            let conEquipo = hecho(plan)
            let sinKg = ReglasEjercicio.sinKg(ef)
            let local = dia.ejercicios[lugar]?.series ?? []
            let series: [SerieReloj] = local.indices.map { i in
                let s = local[i]
                let f = dia.fila(lugar, i, efectivo: ef)
                return SerieReloj(numero: i + 1, repsSugeridas: Self.entero(f?.placeholderReps),
                                  kgSugerido: sinKg ? nil : Self.numero(f?.placeholderKg),
                                  confirmada: s.confirmada, reps: s.confirmada ? Self.entero(s.reps) : nil,
                                  kg: s.confirmada && !sinKg ? Self.numero(s.kg) : nil)
            }
            let historial = dia.historial[lugar] ?? []
            var e = EjercicioReloj(
                lugar: lugar, nombre: conEquipo.nombre, bloque: nil, tipo: ef.tipo, musculo: musculo(plan), equipo: conEquipo.equipo,
                sinKg: sinKg, sinPeso: ReglasEjercicio.esSinPeso(nombre: ef.nombre, tipo: ef.tipo, equipo: ef.equipo),
                aproximacionesPlan: conEquipo.aproximaciones?.map(AproximacionReloj.init),
                descansoSegundos: dia.descanso(lugar), repsPlan: Progresiones.pauta(ef, semana: semana).reps,
                estado: dia.estado(lugar), series: series,
                anteriores: RecordSerie.anteriores(historial, hoy: hoy, zona: zona).map(MarcaReloj.init),
                historiaSuficiente: RecordSerie.historiaSuficiente(historial, hoy: hoy, zona: zona))
            e.patron = patron(plan)
            return e
        }
        var r = RutinaReloj(cuenta: cuentaReloj, rutinaId: rutina.id, diaId: dia.dia.id ?? "", semana: semana, nombreDia: dia.dia.nombre ?? "",
                            fecha: hoy, generada: ahoraMs, ejercicios: ejercicios, inicioSesion: inicioSesion,
                            diaFinalizado: dia.diaFinalizado, proximo: proximoEntreno(), descanso: descanso.descanso?.guardado, demo: demo)
        r.dias = diasReloj()
        return r
    }

    /// Los días de la semana como los pinta el selector de Entreno (`SelectorDias`): «Día n», el nombre, cuántos
    /// ejercicios y el tilde de la sesión cerrada esta semana.
    func diasReloj() -> [DiaReloj] {
        dias.compactMap { d in
            d.id.map { DiaReloj(id: $0, nombre: d.nombre ?? "", numero: numero(d), ejercicios: Self.cantidadEjercicios(d), hecho: hecho(d)) }
        }
    }

    static func cantidadEjercicios(_ d: Dia) -> Int { d.bloques.reduce(0) { $0 + $1.ejercicios.count } }

    static let motivoOtroDiaEnCurso = "En el iPhone hay otro día en curso. Terminalo ahí para cambiar."

    /// El alumno eligió un día en el reloj (`MensajeReloj.pedirDia`): se abre con el mismo camino que el selector de
    /// Entreno (`cambiarDia`), así el día del reloj y el del teléfono son el mismo y las series del reloj caen en ese día
    /// del servidor. Igual que con un evento de otro día, no se le cambia la pantalla a un día con algo en curso (la
    /// sesión empezada, una serie confirmada o algo tipeado): gana el teléfono. Devuelve por qué no se pudo (para el
    /// reloj) o nil si quedó abierto.
    public func elegirDiaReloj(_ id: String) async -> String? {
        if id == dia.dia.id { return nil }
        guard dias.contains(where: { $0.id == id }) else { return "Ese día ya no está en tu rutina." }
        if diaConActividad { return Self.motivoOtroDiaEnCurso }
        await cambiarDia(id)
        return dia.dia.id == id ? nil : "No se pudo abrir el día en el iPhone."
    }

    /// El `patron_movimiento` del que se hace (el del sustituto, si hay; si no, el del catálogo): para la familia de
    /// movimiento del conteo de reps del reloj (tanda 4).
    func patron(_ ex: Ejercicio) -> String? {
        efectivo(ex).slugSustituto.flatMap { catalogo.entrada(slug: $0)?.patronMovimiento } ?? catalogo.resolver(ex)?.patronMovimiento
    }

    /// El próximo día que falta en la semana (después del que se mira, dando la vuelta).
    func proximoEntreno() -> ProximoEntreno? {
        guard let i = dias.firstIndex(where: { $0.id == dia.dia.id }), dias.count > 1 else { return nil }
        let orden = dias[(i + 1)...] + dias[..<i]
        guard let d = orden.first(where: { !hecho($0) }) ?? orden.first, let id = d.id else { return nil }
        return ProximoEntreno(diaId: id, nombre: d.nombre ?? "", ejercicios: Self.cantidadEjercicios(d))
    }

    static func entero(_ s: String?) -> Int? {
        guard let s, let v = JS.parseInt(s), v.isFinite, v >= 1 else { return nil }
        return Int(v)
    }

    static func numero(_ s: String?) -> Double? {
        guard let s, let v = JS.parseFloat(s.replacingOccurrences(of: ",", with: ".")), v.isFinite, v >= 0 else { return nil }
        return v
    }

    /// La cuenta para el reloj: un hash corto del token (nunca el token). En la demo, "demo".
    public var cuentaReloj: String { Self.hashCuenta(token) }

    static let motivoDiaCerrado = "ese día ya lo cerraste en el teléfono."

    nonisolated public static func hashCuenta(_ token: String?) -> String {
        guard let token, !token.isEmpty else { return "demo" }
        return SHA256.hash(data: Data(("mypump-reloj|" + token).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// El día que se mira tiene algo en curso que cambiar de día haría perder o esconder: la sesión empezada y abierta,
    /// una serie confirmada o algo tipeado sin confirmar.
    /// Un día cerrado no bloquea (es lo normal después de entrenar): no hay nada que perder al cambiar.
    var diaConActividad: Bool {
        if dia.diaFinalizado { return false }
        if inicioSesion != nil { return true }
        return dia.ejercicios.values.contains { e in e.series.contains { $0.confirmada || !$0.reps.isEmpty || !$0.kg.isEmpty } }
    }

    /// Aplica un evento del reloj y dice qué contestarle. Nunca descarta en silencio: lo que no se puede aplicar ahora es
    /// `pendiente` (queda en la cola del reloj y se reintenta) y lo que no se va a poder aplicar nunca, `rechazado` con
    /// el motivo que el reloj le muestra al alumno. `creado` (ms) es cuándo pasó en el reloj: solo arranca el cronómetro,
    /// ancla el descanso y cierra la duración (la serie se fecha con la hora del iPhone, como el servidor).
    public func aplicarEventoReloj(_ ec: EventoEnCola) async -> AcuseEvento {
        func r(_ res: AcuseEvento.Resultado, _ motivo: String? = nil) -> AcuseEvento { AcuseEvento(id: ec.id, resultado: res, motivo: motivo) }
        let e = ec.evento
        if ahoraMs - ec.creado > ReceptorReloj.vencimiento { return r(.rechazado, ReceptorReloj.motivoVencido) }
        if let c = ec.cuenta, c != cuentaReloj {
            return r(.pendiente, demo ? "El iPhone está en la demo: entrá con tu link." : "El iPhone tiene otra cuenta abierta.")
        }
        // En la demo no se escribe nada: solo se aplica lo hecho con la rutina de la demo (no hay nada que perder).
        if demo, ec.cuenta != "demo" { return r(.pendiente, "El iPhone está en la demo: entrá con tu link.") }
        if let rid = ec.rutinaId, rid != rutina.id { return r(.rechazado, "tu rutina cambió desde que la hiciste.") }
        if e.semana < semana { return r(.rechazado, "el iPhone ya pasó a la semana \(semanaMostrada).") }
        if e.semana > semana { return r(.pendiente, "El iPhone todavía no pasó a esa semana.") }
        if e.diaId != dia.dia.id {
            guard let otro = dias.first(where: { $0.id == e.diaId }) else { return r(.rechazado, "ese día ya no está en tu rutina.") }
            // Un día ya cerrado en el teléfono no se reabre desde el reloj: gana el teléfono (ni se cambia de pantalla).
            if hecho(otro) {
                if case .serie = e { return r(.rechazado, Self.motivoDiaCerrado) }
                return r(.aplicado)
            }
            // Otro día abierto con algo en curso: no se le cambia la pantalla ni se pierde lo tipeado. Queda pendiente.
            if diaConActividad { return r(.pendiente, "En el iPhone hay otro día abierto. Cerralo para pasar esto.") }
            await cambiarDia(e.diaId)
            guard dia.dia.id == e.diaId else { return r(.pendiente, "No se pudo abrir el día en el iPhone.") }
        }
        switch e {
        case .iniciar:
            guard !dia.diaFinalizado else { return r(.aplicado) }
            await empezar(desde: ec.creado)
            return r(.aplicado)
        case .serie(_, _, let lugar, let i, let reps, let kg):
            guard let ej = dia.ejercicios[lugar], i >= 0, i < ej.series.count else { return r(.rechazado, "la serie ya no está en tu rutina.") }
            let s = ej.series[i]
            let igual = s.confirmada && Self.entero(s.reps) == reps && (kg == nil || Self.numero(s.kg) == kg)
            if igual { return r(.aplicado) }
            // Gana el teléfono: un día cerrado no se reabre, y una serie confirmada en el teléfono no se pisa. Solo una
            // corrección del reloj sobre una serie que vino del reloj (y es más nueva) la reemplaza.
            if dia.diaFinalizado { return r(.rechazado, Self.motivoDiaCerrado) }
            if s.confirmada {
                guard let previa = seriesDelReloj[claveFecha(lugar, i + 1)], previa < ec.creado else {
                    return r(.rechazado, "ya cargaste esta serie en el teléfono.")
                }
                await editarSerie(lugar, i)
            }
            // El cronómetro arranca cuando se hizo la primera serie en el reloj, no cuando llegó.
            if inicioSesion == nil, ec.creado <= ahoraMs {
                inicioSesion = ec.creado
                guardarInicio()
            }
            escribir(lugar, i, campo: "reps", valor: String(reps))
            if let kg { escribir(lugar, i, campo: "kg", valor: JS.texto(kg)) }
            // Lo confirmó en el reloj: «¿está bien cargado?» y «reabrir el día» se contestan que sí.
            await confirmarSerie(lugar, i, delReloj: min(ec.creado, ahoraMs)) { _ in true }
            return dia.ejercicios[lugar]?.series[i].confirmada == true ? r(.aplicado) : r(.rechazado, "el iPhone no la pudo registrar.")
        case .terminar:
            // Sin nada hecho no hay qué cerrar; con algo hecho (aunque la sesión todavía no exista: sin red) se intenta.
            guard cierreHabilitado || inicioSesion != nil, !dia.diaFinalizado else { return r(.aplicado) }
            switch await cerrarDia(notas: "", fin: ec.creado) {
            case .cerrado, .demo: return r(.aplicado)
            case .sinSesion, .fallo: return r(.pendiente, "No se pudo cerrar la sesión en el iPhone (sin conexión).")
            }
        }
    }
}

/// Recibe los eventos del reloj en el iPhone: contesta los repetidos por id (guardados en el disco de la cuenta) y aplica
/// el resto en orden sobre el motor de Entreno. Cada evento se contesta solo: uno pendiente (un «terminar» sin red) no
/// traba a los de atrás. El id se anota ANTES de aplicar, así un lote duplicado que llega en el medio (otra vía de
/// WatchConnectivity) no lo aplica dos veces; si al final queda pendiente, se saca.
@MainActor
public final class ReceptorReloj {
    public static let archivo = "reloj-aplicados.json"
    /// Un evento que no pudo pasar en 7 días ya no se aplica: vuelve rechazado (el reloj lo muestra).
    public static let vencimiento: Double = 7 * 24 * 3_600_000
    public static let motivoVencido = "pasaron más de 7 días sin que llegara al iPhone."
    /// Desde cuándo un pendiente se avisa en Entreno.
    public static let avisarDespues: Double = 3 * 3_600_000
    private let disco: Disco?
    private var aplicados: AplicadosReloj
    /// Los que se están aplicando ahora (un duplicado en el medio contesta `pendiente`, no `repetido`).
    private var enCurso: Set<UUID> = []

    /// ms de ahora cuando no hay motor (para el vencimiento); con motor manda el reloj del motor.
    private let reloj: () -> Double

    public init(disco: Disco?, ahora: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }) {
        self.disco = disco
        reloj = ahora
        aplicados = disco?.leer(AplicadosReloj.self, Self.archivo) ?? AplicadosReloj()
    }

    public func recibir(_ eventos: [EventoEnCola], motor: ModeloEntreno?) async -> [AcuseEvento] {
        var acuses: [AcuseEvento] = []
        for e in eventos.sorted(by: { $0.creado < $1.creado }) {
            if enCurso.contains(e.id) {
                acuses.append(AcuseEvento(id: e.id, resultado: .pendiente, motivo: "Se está guardando en el iPhone."))
                continue
            }
            if aplicados.contiene(e.id) {
                acuses.append(AcuseEvento(id: e.id, resultado: .repetido))
                continue
            }
            guard let motor else {
                let vencido = reloj() - e.creado > Self.vencimiento
                acuses.append(vencido ? AcuseEvento(id: e.id, resultado: .rechazado, motivo: Self.motivoVencido)
                                      : AcuseEvento(id: e.id, resultado: .pendiente, motivo: "Abrí Pump Team en el iPhone."))
                continue
            }
            aplicados.anotar(e.id)
            enCurso.insert(e.id)
            let a = await motor.aplicarEventoReloj(e)
            enCurso.remove(e.id)
            if a.resultado == .pendiente { aplicados.quitar(e.id) }
            _ = disco?.guardar(aplicados, Self.archivo)
            acuses.append(a)
        }
        if let motor { avisar(motor, eventos, acuses) }
        return acuses
    }
}

extension ReceptorReloj {
    /// El aviso de Entreno: el pendiente más viejo de este lote, si espera hace más de `avisarDespues`. Un lote sin
    /// pendientes lo apaga.
    func avisar(_ motor: ModeloEntreno, _ eventos: [EventoEnCola], _ acuses: [AcuseEvento]) {
        let pendientes = Set(acuses.filter { $0.resultado == .pendiente }.map(\.id))
        guard let viejo = eventos.filter({ pendientes.contains($0.id) }).min(by: { $0.creado < $1.creado }) else {
            motor.relojEsperando = nil
            return
        }
        let horas = Int((motor.ahoraMs - viejo.creado) / 3_600_000)
        guard motor.ahoraMs - viejo.creado > Self.avisarDespues else { return }
        let motivo = acuses.first { $0.id == viejo.id }?.motivo ?? ""
        motor.relojEsperando = "Hay series del Apple Watch sin pasar desde hace \(horas) h. \(motivo)"
            .trimmingCharacters(in: .whitespaces)
    }

    /// Con el disco de la cuenta del motor: los aplicados son de la cuenta, como la cola.
    public convenience init(motor: ModeloEntreno) { self.init(disco: motor.disco) }
}
