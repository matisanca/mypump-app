import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// El motor de la pantalla de Entreno: la semana, el día que se mira, la sesión del día con sus series, el historial,
/// el descanso, los comentarios, las sustituciones, cerrar el día y avanzar de semana. Hace lo mismo que cliente.html
/// (init, restoreSesionDelDia, loadHistorico, writeFinish, doAvanzarSemana…); las reglas puras viven en MyPumpReglas
/// (`DiaEnCurso` y compañía) y acá se ejecutan sus efectos: la cola, el disco y la base.
///
/// Se arma con lo que ya cargó `ModeloApp` (cliente, token, cola, disco de la cuenta, rutina e info). Sin token es la
/// demo: no toca la red ni escribe nada.
@MainActor @Observable
public final class ModeloEntreno {
    // MARK: - Estado

    public internal(set) var rutina: RutinaActiva
    /// La estructura ya normalizada (`normalizarRutina`, ENT-04).
    public internal(set) var estructura: EstructuraRutina
    /// Hay al menos un día con ejercicios. Si no, la app muestra la rutina de ejemplo (ACC-08).
    public internal(set) var usable: Bool
    /// Lo que le faltaba al plan (el aviso de GEN-05).
    public internal(set) var problemas: [String]
    /// El día que se mira, con su sesión, sus series, su historial y las sustituciones de la rutina.
    public internal(set) var dia: DiaEnCurso
    /// Días con la sesión de ESTA semana cerrada (el ✓ del selector, `get_sesiones_semana`).
    public internal(set) var diasCompletados: Set<String> = []
    public internal(set) var comentarios = IndiceComentarios()
    public internal(set) var descanso: BarraDescanso
    /// Cuándo arrancó la sesión del día (ms desde 1970, `_sessionStart`).
    public internal(set) var inicioSesion: Double?
    /// Se tocó "Empezar entrenamiento" (si no, el cronómetro dice "⏱ arrancó con tu primera serie").
    public internal(set) var iniciadaConBoton = false
    /// Hay sesión en el servidor (o se pidió crearla): el botón "Terminar el entrenamiento de hoy" se ve habilitado.
    public internal(set) var sesionIniciada = false
    /// Historial pedido y todavía sin respuesta.
    public internal(set) var historialCargando: Set<String> = []
    public internal(set) var catalogo: CatalogoEjercicios { didSet { versionCatalogo &+= 1 } }
    /// Cambia con cada catálogo que llega (la firma del volumen: dos catálogos con la misma cantidad no son el mismo).
    @ObservationIgnored public private(set) var versionCatalogo = 0
    /// E1: las filas de preparación que el alumno tocó como hechas hoy, por `Preparacion.claveTildes` (fecha + día +
    /// lugar). Es solo un estado visual del día: no va a la base.
    public internal(set) var preparacionHecha: [String: [Int]] = [:]
    /// E1: los ejercicios (por clave) con la preparación oculta («Ocultar» se recuerda).
    public internal(set) var preparacionOculta: Set<String> = []
    /// El último récord (2.0.3, E3): lo muestra la tabla del lugar como aviso dorado y se va solo.
    public internal(set) var avisoRecord: AvisoRecord?

    /// «Récord: +2,5 kg» en el lugar; el id cambia en cada aviso (dos récords seguidos se ven los dos).
    public struct AvisoRecord: Equatable, Sendable {
        public let id: UUID
        public let lugar: String
        public let texto: String
    }

    // MARK: - Dependencias

    @ObservationIgnored public let cliente: ClienteRPC
    @ObservationIgnored public let token: String?
    @ObservationIgnored let outbox: Outbox?
    @ObservationIgnored let disco: Disco?
    /// E1: la preparación ya calculada (ver `preparacion(_:)`). Fuera de la observación: es un caché.
    @ObservationIgnored private var cacheEntradas: (firma: String, entradas: [Preparacion.Entrada], ejercicios: [Ejercicio])?
    @ObservationIgnored private var cachePreparacion: [String: (clave: String, series: [Preparacion.Serie])] = [:]
    @ObservationIgnored public let info: ClienteInfo?
    @ObservationIgnored public let demo: Bool
    @ObservationIgnored let zona: TimeZone
    @ObservationIgnored let reloj: @Sendable () -> Date
    /// Lo que cambió de la rutina sin pasar por `ModeloApp` (avanzar de semana, bloque nuevo, recargar), para que lo tenga
    /// también y deje la copia offline al día.
    public enum CambioRutina: Sendable {
        /// La trajo del servidor: con la fila tal cual llegó, para la copia offline.
        case nueva(RutinaActiva, JSONValue)
        /// El servidor ya pasó de semana y la rutina no llegó: la misma, en la semana nueva.
        case semana(RutinaActiva)
        /// El servidor activó el bloque nuevo y no llegó: el viejo quedó archivado y no se puede seguir cargando en él.
        case bloqueSinTraer
    }

    /// Solo para las capturas y las pruebas de interfaz de la demo (la app lo pone en DEBUG con `-historial muestra`): el
    /// historial que devuelve la demo, que no tiene red. nil = sin historial, como siempre.
    nonisolated(unsafe) public static var historialDeMuestra: (@Sendable (String) -> [RegistroHistorico])?

    /// La demo sin cuenta (2.3.0): el historial inventado por clave (`HistorialDemo`). Lo pone `ModeloApp.entrarEnDemo`; solo
    /// se mira sin token. nil = sin historial.
    @ObservationIgnored public var historialDemo: [String: [RegistroHistorico]]?

    /// Se llama cuando el modelo cambia la rutina (avanzar de semana, bloque nuevo, recargar).
    @ObservationIgnored public var alCambiarRutina: ((CambioRutina) -> Void)?

    @ObservationIgnored var sesionesLocales: [String: SesionLocal] = [:]
    /// F1 (auditoría 10/11): las series y los estados que este teléfono mandó a la cola, por clave (lo último gana). Se
    /// pintan al reabrir sin red: antes, lo que ya había subido solo lo conocía el servidor y se veía vacío.
    @ObservationIgnored var anotadas: [String: EscrituraAnotada] = [:]
    /// F1: lo que se ve del día salió de lo guardado en el teléfono porque el servidor no contestó (sin confirmar).
    public internal(set) var seriesSinConfirmar = false
    @ObservationIgnored var sinHistorialPorClave = false
    @ObservationIgnored var generacionHistorial: [String: Int] = [:]
    @ObservationIgnored var historialEnVuelo: [String: Task<Void, Never>] = [:]
    /// La creación de la sesión en vuelo, por día y semana (la de otro día no sirve). Es la de la cuenta: la cola la usa
    /// también, así la primera serie del día no crea la sesión dos veces (hallazgo 5).
    @ObservationIgnored let sesiones: SesionesDelDia
    /// SER-14: lo último que se escribió en el archivo de la rutina. Lo que cambie desde acá sale por la cola.
    @ObservationIgnored var sustitucionesGuardadas: [String: JSONValue] = [:]
    /// La fecha real (local, YYYY-MM-DD) de cada serie confirmada del día que se mira (`claveFecha`): la del toque, la
    /// del `registrado_en` o la de la cola. Para el volumen por músculo (revisión del 3-nov).
    public internal(set) var fechasSeries: [String: String] = [:]
    /// SER-14: mientras se espera al servidor, lo que se tocó en el medio (ahí gana lo del teléfono). nil = no se espera.
    @ObservationIgnored var tocadasDuranteSync: Set<String>?
    /// SER-14: la sincronización en curso (una a la vez; cambiar de rutina la deja sin efecto).
    @ObservationIgnored var syncSustituciones: UUID?
    /// SER-14: los encolados de sustituciones, en fila (si no, dos cambios seguidos podían llegar a la cola al revés).
    @ObservationIgnored var encoladoSustituciones: Task<Void, Never>?
    /// SER-14: hora del servidor − hora del teléfono (ms), de la última lectura. Los cambios se estampan corregidos: un
    /// teléfono con el reloj adelantado no estampa en el futuro.
    @ObservationIgnored var desfaseReloj: Double = 0
    /// SER-14: la hora más alta que tuvo cada clave en esta sesión (lo deshecho y las lápidas del servidor): una elección
    /// nueva la supera aunque lo deshecho viniera de un reloj un poco adelantado.
    @ObservationIgnored var pisoPorClave: [String: Double] = [:]
    @ObservationIgnored var restauracion = 0
    /// Carga simple (2.3.0): el último OK deshacible (la foto, fuera de la observación), la serie que se está corrigiendo y
    /// la guardia contra el OK apurado.
    @ObservationIgnored var fotoOK: FotoOK?
    public internal(set) var deshacible: OKDeshacible?
    public internal(set) var corrigiendo: SerieEnCorreccion?
    public internal(set) var guardia = GuardiaOK()
    /// El día se completó con un OK cuya ventana venció después (no hay callback): la pantalla lo muestra y lo limpia.
    var okEnCurso = false
    public var diaCompletado: DiaCompletado?
    @ObservationIgnored var diaCompletadoMostrado = false
    /// Había un día guardado en este teléfono al arrancar (si no, el del almacenamiento viejo puede ganar).
    @ObservationIgnored var habiaDiaGuardado = false
    /// Lo último que se escribió del descanso (el tick corre cada 250 ms: se escribe solo si cambió).
    @ObservationIgnored var descansoEnDisco: Descanso.Guardado?
    /// ms: cuándo pasó la acción que se está aplicando, si no es ahora (un evento del reloj).
    @ObservationIgnored var instanteEvento: Double?
    /// Las series confirmadas por un evento del reloj (clave de `claveFecha` → `creado` del evento). Solo en memoria: sin
    /// la marca, gana lo que hay en el teléfono.
    @ObservationIgnored var seriesDelReloj: [String: Double] = [:]
    /// Hay eventos del Apple Watch que esperan hace horas sin poder pasar (el aviso de Entreno); nil si no.
    public internal(set) var relojEsperando: String?
    /// Series del reloj que no se guardaron en ningún lado: en disco, a la vista en Entreno hasta que el alumno la cierre.
    public internal(set) var relojPerdidas: PerdidasReloj?

    /// El alumno leyó el aviso de las series del reloj que no se guardaron.
    public func leerRelojPerdidas() {
        relojPerdidas = nil
        disco?.borrar(PerdidasReloj.archivo)
    }

    public init(cliente: ClienteRPC, token: String?, outbox: Outbox?, disco: Disco?, rutina: RutinaActiva, info: ClienteInfo? = nil,
                catalogo: CatalogoEjercicios = CatalogoEjercicios([]), demo: Bool? = nil, zona: TimeZone = .current,
                reloj: @escaping @Sendable () -> Date = { Date() }, sesiones: SesionesDelDia = SesionesDelDia()) {
        self.cliente = cliente
        self.token = token
        self.outbox = outbox
        self.disco = disco
        relojPerdidas = disco?.leer(PerdidasReloj.self, PerdidasReloj.archivo)
        self.sesiones = sesiones
        self.info = info
        self.catalogo = catalogo
        self.demo = demo ?? (token == nil || outbox == nil)
        self.zona = zona
        self.reloj = reloj
        self.rutina = rutina
        let n = NormalizacionRutina.normalizar(rutina.estructura)
        estructura = n.estructura
        usable = n.usable
        problemas = n.problemas
        let enDisco = disco?.leer(Descanso.Guardado.self, Archivo.descanso)
        descanso = BarraDescanso(guardado: enDisco)
        sesionesLocales = disco?.leer([String: SesionLocal].self, Archivo.sesiones) ?? [:]
        anotadas = Self.podarAnotadas(disco?.leer([String: EscrituraAnotada].self, Archivo.anotadas) ?? [:],
                                      ahora: reloj().timeIntervalSince1970 * 1000)
        let semana = rutina.semanaActual == 0 ? 1 : rutina.semanaActual
        let guardado = disco?.leer(String.self, Archivo.dia(rutina.id))
        habiaDiaGuardado = guardado != nil
        let elegido = TextosEntreno.diaSugerido(n.estructura.dias, ultimo: guardado) ?? Dia(id: "d1")
        dia = DiaEnCurso(dia: elegido, semana: semana, demo: self.demo, zona: zona)
        dia.descansosPropios = disco?.leer([String: Int].self, Archivo.descansos) ?? [:]
        dia.sustituciones = SustitucionesEntreno.compat(disco?.leer([String: JSONValue].self, Archivo.sustituciones(rutina.id)) ?? [:])
        sustitucionesGuardadas = disco?.leer([String: JSONValue].self, SustitucionesServidor.archivoEncoladas(rutinaId: rutina.id))
            ?? dia.sustituciones
        desfaseReloj = disco?.leer(Double.self, Archivo.reloj) ?? 0
        descansoEnDisco = enDisco
        // Los tildes de la preparación son del día: lo de otra fecha se descarta al arrancar.
        let hoy = FechaJS.ymd(reloj(), zona: zona)
        preparacionHecha = (disco?.leer([String: [Int]].self, Archivo.preparacion) ?? [:]).filter { $0.key.hasPrefix(hoy + "|") }
        preparacionOculta = Set(disco?.leer([String].self, Archivo.preparacionOculta) ?? [])
        leerCargas()
        guardarDiaVisualizado()
    }

    /// Lo que la web hace en el arranque después de pintar: poda las sustituciones vencidas, vuelve a poner el descanso
    /// que estaba corriendo, trae el historial del día, restaura la sesión del día (confirmándola con el servidor), los
    /// días completados de la semana y los comentarios.
    public func cargar() async {
        await vaciarDeshacer()
        await recuperarDeshacerGuardado()
        // Lo que se cambió y no llegó a la cola (la app se cerró en el medio), antes de leer el servidor.
        encolarSustituciones()
        podarSustituciones()
        // Solo si no hay uno corriendo: restaurar borra lo guardado (como la web), y un segundo `cargar()` (tirar para
        // actualizar) dejaría el descanso en curso sin copia en disco.
        if descanso.descanso == nil {
            descanso.restaurar(ahora: ahoraMs)
            guardarDescanso()
        }
        async let historial: Void = precargarHistorial()
        async let servidor: Void = sincronizarSustituciones()
        await restaurarSesion()
        async let completados: Void = cargarDiasCompletados()
        async let coms: Void = cargarComentarios()
        _ = await (historial, servidor, completados, coms)
    }

    // MARK: - Semana y días

    /// `semana_actual || 1`: la que se usa para escribir. `semana_offset` solo cambia rótulos (ENT-09).
    public var semana: Int { dia.semana }
    public var semanasTotal: Int { estructura.semanasTotal ?? 12 }
    public var offset: Int { estructura.semanaOffset ?? 0 }
    /// "SEM x/y" del encabezado, con el offset del macrociclo.
    public var semanaMostrada: Int { semana + offset }
    public var totalMostrado: Int { semanasTotal + offset }
    public var dias: [Dia] { estructura.dias }

    /// "DÍA n" de un día (`getDayNum`).
    public func numero(_ d: Dia) -> Int { TextosEntreno.numeroDia(d, en: dias) }
    /// La primera palabra del nombre (`getDayShortName`).
    public func nombreCorto(_ d: Dia) -> String { TextosEntreno.nombreCortoDia(d.nombre) }
    /// ✓ del selector: el día tiene la sesión de esta semana cerrada.
    public func hecho(_ d: Dia) -> Bool { d.id.map(diasCompletados.contains) ?? false }
    /// 💬 del selector.
    public func sinLeer(_ d: Dia) -> Int { comentarios.sinLeer(dia: d) }
    /// El badge de la pestaña Entreno (sin el chat).
    public var sinLeerEntreno: Int { comentarios.totalEntreno }

    /// ENT-07/08
    public var banner: BannerSemana { SemanaEntreno.banner(dia.dia, semana: semana, offset: offset) }
    public var puedeAvanzar: Bool { SemanaEntreno.puedeAvanzar(semana: semana, total: semanasTotal, demo: demo) }
    public var puedeEmpezarBloque: Bool {
        SemanaEntreno.puedeEmpezarBloque(semana: semana, total: semanasTotal, tieneSiguiente: rutina.tieneSiguiente, demo: demo)
    }
    public var botonAvanzar: String { SemanaEntreno.botonAvanzar(semana: semana, offset: offset) }
    /// La confirmación de "Pasar a Semana N" (cambia si el día está incompleto).
    public var preguntaAvanzar: Pregunta? {
        SemanaEntreno.preguntaAvanzar(semana: semana, total: semanasTotal, offset: offset, diaCompleto: dia.diaCompleto)
    }

    /// `cambiarDia` (ENT-02): la ÚNICA forma de cambiar de día. Poda antes de mover (con el estado del día que se deja),
    /// arma la sesión del nuevo, recuerda el día en este teléfono y restaura su sesión.
    public func cambiarDia(_ id: String) async {
        guard let nuevo = dias.first(where: { $0.id == id }), nuevo.id != dia.dia.id else { return }
        await vaciarDeshacer()
        guardarCargas()
        descanso.detener()
        guardarDescanso()
        podarSustituciones(sinPrecarga: true)
        let sustituciones = dia.sustituciones
        historialEnVuelo.values.forEach { $0.cancel() }
        historialEnVuelo = [:]
        historialCargando = []
        generacionHistorial = generacionHistorial.mapValues { $0 + 1 }
        let descansos = dia.descansosPropios
        dia = DiaEnCurso(dia: nuevo, semana: semana, demo: demo, zona: zona)
        dia.sustituciones = sustituciones
        dia.descansosPropios = descansos
        leerCargas()
        diaCompletadoMostrado = false
        guardarDiaVisualizado()
        async let historial: Void = precargarHistorial()
        await restaurarSesion()
        _ = await historial
    }

    // MARK: - El día

    /// Un bloque como lo pinta la web: "B{i} · NOMBRE · hechos/total" (ENT-05).
    public struct BloqueDelDia: Sendable {
        public let indice: Int
        public let nombre: String
        public let hechos: Int
        public let ejercicios: [Ejercicio]
    }

    public var bloques: [BloqueDelDia] {
        dia.dia.bloques.enumerated().map { i, b in
            BloqueDelDia(indice: i, nombre: TextosEntreno.nombreBloque(b),
                         hechos: b.ejercicios.filter { EstadosEjercicio.terminales.contains(dia.estado($0.id)) }.count, ejercicios: b.ejercicios)
        }
    }

    public var totalEjercicios: Int { dia.lista.count }
    public var hechos: Int { dia.hechos }
    /// "Este día no tiene ejercicios cargados…" (ENT-16)
    public var vacio: Bool { dia.lista.isEmpty }
    /// Todos en un estado terminal, o el día cerrado: se muestra la card de cierre.
    public var todoHecho: Bool { (totalEjercicios > 0 && hechos == totalEjercicios) || dia.diaFinalizado }
    public var resumen: ResumenDia { dia.resumen }
    /// Los minutos de la sesión, o nil (más de 6 h, SES-03): la UI pinta "—".
    public var minutos: Int? { TiempoEntreno.minutosSesion(inicio: inicioSesion, ahora: ahoraMs) }
    /// El cronómetro de arriba (llamarlo en cada tick de la vista).
    public func cronometro() -> TiempoEntreno.Cronometro? {
        TiempoEntreno.cronometro(inicio: inicioSesion, ahora: ahoraMs, porBoton: iniciadaConBoton, diaFinalizado: dia.diaFinalizado, todoHecho: todoHecho)
    }
    /// El botón "Terminar el entrenamiento de hoy" del pie se ve habilitado.
    public var cierreHabilitado: Bool { sesionIniciada || hechos > 0 }

    /// La card de un ejercicio del día, con todo lo que muestra (ENT-10/11).
    public struct Tarjeta: Sendable {
        public let lugar: String
        public let efectivo: EjercicioEfectivo
        public let estado: String
        /// Chip "manual": `completo_sin_datos` marcado a mano.
        public let manual: Bool
        public let sinLeer: Int
        public let pauta: Pauta
        /// La nota de la semana (nil en el calentamiento).
        public let nota: NotaProgresion?
        public let sinKg: Bool
        public let variantes: VariantesEjercicio?
        public let varianteActual: String?
        public let filas: [FilaSerie]
        public let confirmadas: Int
        /// "🏆 Récord" / "Primera vez con este ejercicio" (nil).
        public let record: String?
        public let ultimaVez: UltimaVez?
        /// Hay con qué sustituirlo: una variante del mismo movimiento U otro ejercicio del mismo músculo (revisión del
        /// 21-oct: a «Fondos» o a la patada de tríceps, sin variantes, se les apagaba «Sustituir» aunque tenían 26 a 30).
        public let puedeSustituir: Bool
        /// El chip del descanso ("2:30"): el elegido a mano para este ejercicio, si hay (E2), o el del plan.
        public let descanso: String
        /// El mismo descanso en segundos, y el del plan (para «Volver al del plan»).
        public let descansoSegundos: Int
        public let descansoPlan: Int
        /// El descanso es el elegido a mano, no el del plan.
        public let descansoPropio: Bool
        public let comentarios: [Comentario]
    }

    public func tarjeta(_ lugar: String) -> Tarjeta? {
        guard let plan = dia.ejercicio(lugar) else { return nil }
        let ef = efectivo(plan)
        let e = dia.ejercicios[lugar]
        // El selector del ejercicio que se hace (el sustituto, si hay): la misma condición con la que se graba la variante.
        let variantes = dia.variantesVisibles(lugar)
        return Tarjeta(
            lugar: lugar, efectivo: ef, estado: dia.estado(lugar),
            manual: dia.estado(lugar) == "completo_sin_datos" && dia.meta[lugar]?.manual == true,
            sinLeer: comentarios.sinLeer(ejercicio: lugar), pauta: Progresiones.pauta(ef.ejercicio, semana: semana),
            nota: ef.ejercicio.tipo == "calentamiento" ? nil : Progresiones.nota(ef.ejercicio, semanaActual: semana),
            sinKg: ReglasEjercicio.sinKg(ef.ejercicio), variantes: variantes,
            varianteActual: JS.verdadero(e?.variante) ?? variantes?.opciones.first,
            filas: (e?.series.indices).map { $0.compactMap { filaConLeyenda(lugar, $0, ef.ejercicio) } } ?? [],
            confirmadas: e?.series.filter(\.confirmada).count ?? 0,
            // El cardio va por tiempo: sin última vez ni récord aunque haya cargas viejas en su clave (4-nov).
            record: ReglasEjercicio.esCardio(ef.ejercicio) ? nil : dia.record(lugar),
            ultimaVez: ReglasEjercicio.esCardio(ef.ejercicio) ? nil : dia.ultimaVez(lugar, ahora: reloj()),
            puedeSustituir: !catalogo.sustitutos(de: ef).isEmpty || !catalogo.otrosDelMismoMusculo(de: ef).isEmpty,
            descanso: TiempoEntreno.fmtTiempo(Double(dia.descanso(lugar))),
            descansoSegundos: dia.descanso(lugar), descansoPlan: plan.descansoSegundos ?? NormalizacionRutina.descansoPorDefecto,
            descansoPropio: dia.tieneDescansoPropio(lugar),
            comentarios: comentarios.comentarios(ejercicio: lugar))
    }

    /// `getEffectiveEx`: el sustituto si hay, o las fotos del catálogo si el plan no las trae.
    public func efectivo(_ ex: Ejercicio) -> EjercicioEfectivo {
        catalogo.efectivo(ex, sustitucion: SustitucionesEntreno.aplicada(dia.sustituciones[ex.id]))
    }

    /// El ejercicio que se hace con el equipo del catálogo: el del sustituto, y para el del plan el `equipment` de
    /// `catalogo.resolver` (así «Sentadilla» o «Peso muerto» a secas reconocen la barra). Para la preparación y el RIR.
    func hecho(_ ex: Ejercicio) -> Ejercicio {
        var e = efectivo(ex).ejercicio
        if e.equipo == nil { e.equipo = catalogo.resolver(ex)?.equipment }
        return e
    }

    /// La fila, con el aviso de primera vez diciendo lo mismo que la leyenda («al fallo» o el rango del plan) y no el
    /// «dejando 1–2 en reserva» fijo de la web (2.0.3).
    func filaConLeyenda(_ lugar: String, _ idx: Int, _ ef: Ejercicio) -> FilaSerie? {
        guard var f = dia.fila(lugar, idx, efectivo: ef) else { return nil }
        f.calibracion = f.calibracion.map { RIRDelPlan.calibracion($0, leyenda: leyendaRIR(lugar)) }
        return f
    }

    /// La leyenda debajo de «Series efectivas» («Al fallo» o el rango del plan); nil si el ejercicio no lleva RIR.
    public func leyendaRIR(_ lugar: String) -> String? {
        dia.leyendaRIR(lugar, efectivo: dia.ejercicio(lugar).map(hecho))
    }

    public func actualizarCatalogo(_ c: CatalogoEjercicios) { catalogo = c }

    // MARK: - Acciones de la card

    /// Lo que pasa después de una acción que puede completar el día: la pregunta "🎉 ¡Día completado!" (una sola vez
    /// por día) y el día siguiente al que ofrece ir.
    public struct DiaCompletado: Sendable {
        public let pregunta: Pregunta
        public let siguiente: Dia?
    }

    /// Abrir o cerrar una card (al abrir: historial y comentarios leídos).
    public func tocarCard(_ lugar: String) async {
        await ejecutar(dia.tocarCard(lugar))
    }

    /// Un campo de la serie (SER-04).
    public func escribir(_ lugar: String, _ idx: Int, campo: String, valor: String) {
        dia.escribir(lugar, idx, campo: campo, valor: valor)
    }

    /// El check o el "✓ Tocá para registrar lo de la última vez" (SER-01/03/05). `preguntar` muestra la pregunta y
    /// devuelve lo que eligió el cliente (reabrir el día cerrado; "¿Está bien cargado?").
    @discardableResult
    public func confirmarSerie(_ lugar: String, _ idx: Int, delReloj: Double? = nil, preguntar: (Pregunta) async -> Bool) async -> DiaCompletado? {
        await confirmarSerieInterno(lugar, idx, delReloj: delReloj, demorar: false, preguntar: preguntar).completo
    }

    /// `demorar`: lo que escribe (cola y «día completado») no sale ahora y vuelve en `diferidos`, para poder deshacer el OK.
    func confirmarSerieInterno(_ lugar: String, _ idx: Int, delReloj: Double? = nil, demorar: Bool,
                               preguntar: (Pregunta) async -> Bool) async -> (completo: DiaCompletado?, diferidos: [DiaEnCurso.Efecto]) {
        var respuestas = DiaEnCurso.Respuestas()
        var completo: DiaCompletado?
        var diferidos: [DiaEnCurso.Efecto] = []
        // La serie se fecha (y el récord y el volumen) con la hora de ahora en el iPhone, igual que el servidor
        // (`registrado_en` = now()). `delReloj` (ms): cuándo se hizo en el reloj; solo ancla el descanso y deja anotado
        // que la serie vino del reloj (una corrección posterior del reloj puede pisarla; un pendiente viejo, no).
        let cuando = reloj()
        instanteEvento = delReloj
        defer { instanteEvento = nil }
        seriesDelReloj[claveFecha(lugar, idx + 1)] = delReloj
        let ef = dia.ejercicio(lugar).map { efectivo($0).ejercicio }
        dia.fijarRIRDelPlan(lugar, idx, efectivo: dia.ejercicio(lugar).map(hecho))
        while true {
            let paso = dia.confirmarSerie(lugar, idx, efectivo: ef, respuestas: respuestas, hoy: FechaJS.ymd(cuando, zona: zona))
            anotarFecha(lugar, idx + 1, FechaJS.ymd(cuando, zona: zona), soloConfirmada: true)
            if let r = paso.record { avisoRecord = AvisoRecord(id: UUID(), lugar: lugar, texto: r.texto) }
            var efectos = paso.efectos
            if demorar {
                diferidos += efectos.filter(Self.seDemora)
                efectos.removeAll(where: Self.seDemora)
            }
            if let c = await ejecutar(efectos) { completo = c }
            guard let p = paso.pregunta, let motivo = paso.motivo else { return (completo, diferidos) }
            let si = await preguntar(p)
            switch motivo {
            case .reabrir: respuestas.reabrir = si
            case .registrarIgual: respuestas.registrarIgual = si
            }
        }
    }

    /// El aviso de récord ya se mostró (o se tocó): se va.
    public func descartarRecord(_ id: UUID) {
        if avisoRecord?.id == id { avisoRecord = nil }
    }

    /// E2 (2.0.3): el descanso de este ejercicio elegido a mano (por su clave, vale en cualquier día y rutina); nil vuelve
    /// al del plan. Queda en el teléfono; el descanso que ya corre no cambia, el próximo sale con este.
    public func elegirDescanso(_ lugar: String, segundos: Int?) {
        let clave = ClaveEjercicio.de(dia.nombreEfectivo(lugar))
        guard !clave.isEmpty else { return }
        dia.descansosPropios[clave] = DescansoPropio.valido(segundos)
        disco?.guardar(dia.descansosPropios, Archivo.descansos)
    }

    // MARK: - Preparación (E1, 2.0.3)

    /// La preparación del lugar: la del plan si la trae (también con un sustituto, que la hereda), si no la que arma la app
    /// con el tipo y el músculo del ejercicio que se hace (el músculo del sustituto si el catálogo lo tiene). El kg sigue
    /// en vivo al de la primera serie efectiva (lo escrito o, si no, lo sugerido).
    public func preparacion(_ lugar: String) -> [Preparacion.Serie] {
        let lista = dia.lista
        guard let i = lista.firstIndex(where: { $0.id == lugar }) else { return [] }
        let (entradas, ejercicios) = entradasPreparacion(lista)
        let ef = ejercicios[i]
        let primera = dia.ejercicios[lugar]?.series.first
        let sugerido = dia.fila(lugar, 0, efectivo: efectivo(lista[i]).ejercicio)?.placeholderKg ?? ""
        // La carga única se elige antes de empezar: la preparación se calcula con ella (sin heredarla como serie).
        let conCarga = !(primera?.kg ?? "").isEmpty ? primera!.kg : (dia.cargas[lugar]?.carga.map(JS.texto) ?? "")
        let kg = Preparacion.kgEfectivo(escrito: conCarga, sugerido: sugerido)
        let clave = "\(lugar)|\(kg.map { "\($0)" } ?? "-")|\(cacheEntradas?.firma ?? "")"
        if let c = cachePreparacion[lugar], c.clave == clave { return c.series }
        let series = Preparacion.series(dia: entradas, indice: i, nombre: ef.nombre, equipo: ef.equipo,
                                        sinKg: ReglasEjercicio.sinKg(efectivo(lista[i]).ejercicio), kgEfectivo: kg, plan: ef.aproximaciones)
        cachePreparacion[lugar] = (clave, series)
        return series
    }

    /// Las entradas del día para la preparación (lo caro: resolver cada ejercicio en el catálogo). Se recalculan solo si
    /// cambia el día, una sustitución o el catálogo; no en cada dibujo ni al tipear.
    private func entradasPreparacion(_ lista: [Ejercicio]) -> ([Preparacion.Entrada], [Ejercicio]) {
        let firma = "\(dia.dia.id ?? "")|\(lista.map(\.id))|\(dia.sustituciones.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })|\(catalogo.entradas.count)"
        if let c = cacheEntradas, c.firma == firma { return (c.entradas, c.ejercicios) }
        var entradas: [Preparacion.Entrada] = [], ejercicios: [Ejercicio] = []
        for ex in lista {
            let ef = efectivo(ex)
            entradas.append(Preparacion.Entrada(tipo: ef.ejercicio.tipo, musculo: musculo(ex), nombre: ef.ejercicio.nombre,
                                                sinPeso: ReglasEjercicio.esSinPeso(nombre: ef.ejercicio.nombre, tipo: ef.ejercicio.tipo, equipo: ef.ejercicio.equipo)))
            ejercicios.append(hecho(ex))
        }
        cacheEntradas = (firma, entradas, ejercicios)
        cachePreparacion = [:]
        return (entradas, ejercicios)
    }

    /// El músculo principal del ejercicio que se hace: el del sustituto si el catálogo lo tiene; si no, el del original
    /// (`CatalogoEjercicios.resolver`: catalogo_slug → matched → reglas y nombre). nil = el catálogo no lo tiene (el
    /// respaldo conservador). La misma cadena para la preparación (E1) y el volumen por músculo (S2).
    public func musculo(_ ex: Ejercicio) -> String? {
        efectivo(ex).slugSustituto.flatMap { catalogo.entrada(slug: $0)?.primaryMuscle } ?? catalogo.resolver(ex)?.primaryMuscle
    }

    // MARK: - Volumen por músculo (2.1, S2)

    /// La clave de `fechasSeries`: el día, la semana, el lugar y el número de la serie.
    func claveFecha(_ lugar: String, _ n: Int) -> String { "\(dia.dia.id ?? "")|\(semana)|\(lugar)|\(n)" }

    /// Anota la fecha real (local) de una serie del día que se mira, si no tenía: la primera vale (el servidor conserva
    /// el `registrado_en` al corregirla). `soloConfirmada`: solo si la serie quedó confirmada (el toque).
    func anotarFecha(_ lugar: String, _ n: Int, _ fecha: String, soloConfirmada: Bool = false) {
        guard fecha.count == 10 else { return }
        if soloConfirmada {
            guard let e = dia.ejercicios[lugar], n >= 1, n <= e.series.count, e.series[n - 1].confirmada else { return }
        }
        let k = claveFecha(lugar, n)
        if fechasSeries[k] == nil { fechasSeries[k] = fecha }
    }

    /// Las series confirmadas en el teléfono del día que se mira, para el volumen por músculo (el cierre del día y Salud
    /// → Fuerza), cada una con su fecha REAL: la del toque, la del `registrado_en` si vino del servidor o la de la cola si
    /// quedó sin mandar. Una sin fecha conocida no va (ya está en el historial). El día que se mira puede ser de otro día
    /// (`restaurarSesion` va por día y semana): antes todo salía con la fecha de hoy y se contaba dos veces (revisión del
    /// 3-nov). Van con la clave del ejercicio con que se registraron, para no sumar lo que el historial ya tiene. Las de
    /// preparación no están: nunca se registran.
    public var registrosVolumenEnVivo: [VolumenMusculo.Registro] {
        var vistos = Set<String>()
        var out: [VolumenMusculo.Registro] = []
        for ex in dia.lista where vistos.insert(ex.id).inserted {
            guard let e = dia.ejercicios[ex.id], e.series.contains(where: \.confirmada) else { continue }
            let m = musculo(ex), ef = efectivo(ex).ejercicio
            for (i, s) in e.series.enumerated() where s.confirmada {
                guard let fecha = fechasSeries[claveFecha(ex.id, i + 1)] else { continue }
                let c = ClaveEjercicio.de(JS.verdadero(s.nombreRegistrado) ?? ef.nombre)
                out.append(VolumenMusculo.Registro(musculo: m, tipo: ef.tipo, fecha: fecha, lugar: ex.id, serie: i + 1,
                                                   clave: c.isEmpty ? ex.id : c))
            }
        }
        return out
    }

    /// Lo que cambia `registrosVolumenEnVivo` (para el caché del volumen): las series confirmadas, con qué nombre y fecha.
    public var firmaVolumenEnVivo: String {
        _ = catalogo   // para que la vista se entere de un catálogo nuevo
        var partes: [String] = [dia.dia.id ?? "", "\(semana)", "\(versionCatalogo)"]
        partes.append(dia.sustituciones.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","))
        for ex in dia.lista {
            guard let e = dia.ejercicios[ex.id] else { continue }
            for (i, s) in e.series.enumerated() where s.confirmada {
                partes.append("\(ex.id)#\(i)#\(s.nombreRegistrado ?? "")#\(fechasSeries[claveFecha(ex.id, i + 1)] ?? "")")
            }
        }
        return partes.joined(separator: "|")
    }

    func clavePreparacion(_ lugar: String) -> String {
        Preparacion.claveTildes(fecha: FechaJS.ymd(reloj(), zona: zona), dia: dia.dia.id ?? "", lugar: lugar)
    }

    /// Las filas de preparación ya hechas hoy en el lugar.
    public func preparacionHecha(_ lugar: String) -> Set<Int> { Set(preparacionHecha[clavePreparacion(lugar)] ?? []) }

    /// Tocar una fila de preparación: queda atenuada como hecha y arranca el descanso corto (30 s). Tocarla de nuevo la
    /// desmarca (sin descanso). No se registra nada como carga.
    public func tocarPreparacion(_ lugar: String, _ i: Int) {
        let clave = clavePreparacion(lugar)
        var hechas = Set(preparacionHecha[clave] ?? [])
        if hechas.contains(i) {
            hechas.remove(i)
        } else {
            hechas.insert(i)
            descanso.iniciar(segundos: Double(Preparacion.descansoSegundos), ahora: ahoraMs)
            guardarDescanso()
        }
        preparacionHecha[clave] = hechas.isEmpty ? nil : hechas.sorted()
        disco?.guardar(preparacionHecha, Archivo.preparacion)
    }

    /// La preparación del lugar está oculta (por la clave del ejercicio que se hace).
    public func preparacionOculta(_ lugar: String) -> Bool { preparacionOculta.contains(ClaveEjercicio.de(dia.nombreEfectivo(lugar))) }

    /// «Ocultar» / «Mostrar»: se recuerda para ese ejercicio.
    public func ocultarPreparacion(_ lugar: String, _ ocultar: Bool) {
        let clave = ClaveEjercicio.de(dia.nombreEfectivo(lugar))
        guard !clave.isEmpty else { return }
        if ocultar { preparacionOculta.insert(clave) } else { preparacionOculta.remove(clave) }
        disco?.guardar(preparacionOculta.sorted(), Archivo.preparacionOculta)
    }

    /// El lápiz (SER-06).
    /// Tocar una serie hecha abre la corrección: nunca la desmarca. El servidor no tiene cómo borrar una serie y una
    /// desmarcada volvía al recargar (error de 2.2.0). Se reescribe con `guardarCorreccion`.
    public func editarSerie(_ lugar: String, _ idx: Int) async {
        guard dia.ejercicios[lugar]?.series[safe: idx]?.confirmada == true else { return }
        await vaciarDeshacer()
        corrigiendo = SerieEnCorreccion(lugar: lugar, indice: idx)
    }

    /// El selector de RIR 0-5 (SER-02): la leyenda del valor actual es `CamposSerie.leyendaRIR`.
    public func elegirRIR(_ lugar: String, _ idx: Int, _ valor: Int) async { await ejecutar(dia.elegirRIR(lugar, idx, String(valor))) }

    /// Agarre o nivel (SER-07).
    public func elegirVariante(_ lugar: String, _ v: String) {
        dia.elegirVariante(lugar, v)
        guardarCargas()
    }

    /// "Marcar ejercicio completo"
    @discardableResult
    public func marcarCompleto(_ lugar: String) async -> DiaCompletado? {
        await vaciarDeshacer()
        return await ejecutar(dia.marcarCompleto(lugar))
    }

    /// "Terminé este ejercicio" (SER-15)
    @discardableResult
    public func terminar(_ lugar: String, preguntar: (Pregunta) async -> Bool) async -> DiaCompletado? {
        await vaciarDeshacer()
        if let p = dia.preguntaTerminar(lugar) {
            guard await preguntar(p) else { return nil }
        }
        // La web espera la sesión antes de marcar: el estado sale con su id.
        await asegurarSesion()
        return await ejecutar(dia.terminar(lugar))
    }

    /// "Reabrir ejercicio"
    public func reabrir(_ lugar: String) async {
        await vaciarDeshacer()
        await ejecutar(dia.reabrir(lugar))
    }

    // MARK: - Sesión (SES-01/02/03)

    /// "▶ Empezar entrenamiento": arranca el cronómetro y crea la sesión.
    public func empezar(desde: Double? = nil) async {
        iniciadaConBoton = true
        // Empezado en el reloj: el cronómetro arranca cuando se tocó allá, no cuando llegó.
        if let desde, inicioSesion == nil, desde <= ahoraMs {
            inicioSesion = desde
            guardarInicio()
        }
        await asegurarSesion()
    }

    /// "Empezar de nuevo" con una sesión de más de 6 h: solo mueve el arranque del cronómetro.
    public func reiniciarCronometro() {
        inicioSesion = ahoraMs
        iniciadaConBoton = true
        guardarInicio()
    }

    /// `ensureSesionIniciada`: arranca el cronómetro y crea la sesión del día y la semana (idempotente desde la 075).
    /// Devuelve el id, o nil si no se pudo (sin red, demo).
    @discardableResult
    public func asegurarSesion() async -> String? {
        arrancarCronometro()
        if let s = dia.sesionId { return s }
        if demo { sesionIniciada = true; return nil }
        guard let diaId = dia.dia.id, let token else { return nil }
        let semana = self.semana
        let cliente = cliente
        let r = await sesiones.iniciar(SesionesDelDia.clave(dia: diaId, semana: Double(semana)), usarResueltas: false) {
            await cliente.llamar("mypump_iniciar_sesion", ["p_token": .texto(token), "p_dia_id": .texto(diaId), "p_semana": .numero(Double(semana))])
        }
        let id: String? = if case .success(let v) = r { JS.verdadero(v.comoTexto) } else { nil }
        // Si se cambió de día mientras viajaba, no es la sesión del día que se mira.
        if let id, dia.dia.id == diaId, dia.semana == semana {
            dia.sesionId = id
            sesionIniciada = true
            var l = sesionesLocales[diaId] ?? SesionLocal(semana: semana)
            l.sesionId = id
            l.semana = semana
            sesionesLocales[diaId] = l
            guardarSesiones()
        }
        return id
    }

    /// La parte sincrónica de `ensureSesionIniciada`: el cronómetro arranca con la primera serie aunque la sesión
    /// todavía no exista.
    func arrancarCronometro() {
        guard inicioSesion == nil else { return }
        inicioSesion = ahoraMs
        guardarInicio()
    }

    /// `restoreSesionDelDia` con el arreglo de la rama `fix/sesion-cache-valida-servidor` (SES-02): la sesión que
    /// recuerda el teléfono se CONFIRMA con el servidor. Si el servidor no devuelve esa (archivó el bloque viejo,
    /// 070b/071/078), se descarta sin heredar su arranque; sin red se confía en el caché. Lo ya confirmado en el
    /// teléfono no se pisa.
    public func restaurarSesion() async {
        restauracion += 1
        let seq = restauracion
        // Las fechas de la sesión anterior no se heredan (una clave repetida, otro bloque con los mismos lugares): vuelven
        // del servidor (`registrado_en`) y de la cola, y lo que se toque desde ahora se anota de nuevo.
        fechasSeries = [:]
        seriesSinConfirmar = false
        dia.sesionId = nil
        dia.diaFinalizado = false
        sesionIniciada = false
        inicioSesion = nil
        guard !demo, let diaId = dia.dia.id else { return }
        let semana = self.semana
        var local = sesionesLocales[diaId]
        // Un caché de otra semana no sirve (ni su arranque).
        if let l = local, l.semana != semana {
            sesionesLocales[diaId] = nil
            guardarSesiones()
            local = nil
        }
        var inicioGuardado = local?.inicio ?? 0
        var cacheValido = local?.sesionId != nil
        var remota: ConsultaSesion?
        if cacheValido {
            let r = await consultarSesionDia(diaId, semana)
            guard seq == restauracion else { return }
            if case .respondio(let s) = r {
                remota = r
                if !JS.iguales(s?.id, local?.sesionId) {
                    cacheValido = false
                    inicioGuardado = 0
                }
            }
        }
        if cacheValido, let l = local {
            dia.sesionId = l.sesionId
            sesionIniciada = true
            // El cerrado es LOCAL a propósito: reabrir el día solo borra la marca del teléfono.
            dia.diaFinalizado = l.finalizada
            if inicioGuardado > 0 { inicioSesion = inicioGuardado }
            await cargarEstadosYSeries(seq)
            return
        }
        if local?.sesionId != nil {
            sesionesLocales[diaId] = nil
            guardarSesiones()
        }
        if remota == nil {
            remota = await consultarSesionDia(diaId, semana)
            guard seq == restauracion else { return }
        }
        guard case .respondio(let s)? = remota, let s, let id = JS.verdadero(s.id) else {
            // Sin sesión conocida (sin red, o todavía no se pudo crear): lo que está en la cola para este día se pinta
            // igual. Antes las series confirmadas sin señal aparecían vacías y un toque las pisaba (revisión, hallazgo 5).
            // Sin respuesta del servidor, también lo que ya había subido desde este teléfono (F1).
            await aplicarPendientes(conAnotadas: remota == .sinRespuesta)
            return
        }
        dia.sesionId = id
        sesionIniciada = true
        dia.diaFinalizado = s.finalizadaEn != nil
        if inicioGuardado > 0 {
            inicioSesion = inicioGuardado
        } else if let ini = s.iniciadaEn, let d = FechaJS.leer(ini) {
            inicioSesion = d.timeIntervalSince1970 * 1000
        }
        sesionesLocales[diaId] = SesionLocal(sesionId: id, semana: semana, finalizada: dia.diaFinalizado, inicio: inicioSesion)
        guardarSesiones()
        await cargarEstadosYSeries(seq)
    }

    enum ConsultaSesion: Equatable {
        /// El servidor contestó: la sesión del día y la semana, o ninguna.
        case respondio(Sesion?)
        /// No se le pudo preguntar (sin red o error): la web confía en el caché.
        case sinRespuesta
    }

    func consultarSesionDia(_ diaId: String, _ semana: Int) async -> ConsultaSesion {
        guard let token else { return .sinRespuesta }
        switch await cliente.filas("mypump_get_sesion_dia", ["p_token": .texto(token), "p_dia_id": .texto(diaId), "p_semana": .numero(Double(semana))],
                                   como: Sesion.self) {
        case .success(let filas): return .respondio(filas.first)
        case .failure: return .sinRespuesta
        }
    }

    /// `loadExerciseStates` + `loadRegistrosCarga`, y encima lo que sigue en la cola para este día y esta semana (lo
    /// pendiente gana: una serie confirmada sin red no vuelve a aparecer vacía si se cerró la app).
    func cargarEstadosYSeries(_ seq: Int) async {
        guard let token, let sid = dia.sesionId else { await aplicarPendientes(conAnotadas: true); return }
        let p: [String: JSONValue] = ["p_token": .texto(token), "p_sesion_id": .texto(sid)]
        async let e = cliente.filas("mypump_get_ejercicios_estado", p, como: EstadoEjercicio.self)
        async let r = cliente.filas("mypump_get_registros_sesion", p, como: RegistroSesion.self)
        let (estados, registros) = await (e, r)
        guard seq == restauracion, dia.sesionId == sid else { return }
        if case .success(let f) = estados { dia.aplicarEstados(f) }
        var fallo = false
        if case .success(let f) = registros {
            for r in f { if let t = r.registradoEn { anotarFecha(r.ejercicioId, r.serie, FechaLocal.de(t, zona: zona)) } }
            dia.aplicarRegistros(f)
        } else {
            fallo = true
        }
        // F1: si el servidor no devolvió las series, lo que ya subió desde este teléfono se pinta (sin confirmar) para que
        // un toque no pise la serie buena con una cargada de memoria.
        await aplicarPendientes(conAnotadas: fallo)
    }

    /// Lo que está en la cola sin mandar para el día y la semana que se miran se pinta encima de lo del servidor: es lo
    /// más nuevo (una serie corregida sin red le gana a la que el servidor ya tenía). `conAnotadas`: el servidor no
    /// contestó, así que primero va lo que este teléfono ya había mandado (F1) y la cola encima.
    func aplicarPendientes(conAnotadas: Bool = false) async {
        guard let diaId = dia.dia.id else { return }
        let cola = await outbox?.operaciones ?? []
        var ops: [(kind: String, payload: JSONValue, ts: Double)] = []
        if conAnotadas {
            // Lo que sigue en la cola manda (con su fecha): lo anotado solo cubre lo que ya subió.
            let claves = Set(cola.compactMap(\.dedupeKey))
            // Lo que terminó en fallidos (el servidor lo rechazó o la cola lo abandonó) no se pinta como hecho.
            // (Es la misma escritura si coincide lo mandado: una corrección posterior que sí subió se sigue pintando.)
            let caidas = await outbox?.fallidos.map(\.op) ?? []
            let propias = anotadas.filter { clave, a in
                !claves.contains(clave) && !caidas.contains { $0.dedupeKey == clave && $0.payload == a.payload }
                    && a.rutinaId == rutina.id && a.payload["diaId"]?.comoTexto == diaId
                    && a.payload["semana"]?.comoNumero == Double(semana)
            }.values
            if !propias.isEmpty { seriesSinConfirmar = true }
            ops += propias.sorted { $0.ts < $1.ts }.map { ($0.kind, $0.payload, $0.ts) }
        }
        ops += cola.map { ($0.kind, $0.payload, $0.ts) }
        guard !ops.isEmpty else { return }
        for op in ops {
            let p = op.payload
            guard p["diaId"]?.comoTexto == diaId, p["semana"]?.comoNumero == Double(semana) else { continue }
            if op.kind == "carga", let d = p["datos"], let ex = d["ejercicioId"]?.comoTexto, let n = d["serie"]?.comoNumero {
                let i = n.enteroTruncado - 1
                guard var e = dia.ejercicios[ex], i >= 0, i < e.series.count else { continue }
                e.series[i].kg = d["peso"]?.comoNumero.map(JS.texto) ?? ""
                e.series[i].reps = d["reps"]?.comoNumero.map(JS.texto) ?? ""
                e.series[i].rir = d["rir"]?.comoNumero.map(JS.texto) ?? ""
                e.series[i].confirmada = true
                e.series[i].nombreRegistrado = d["ejercicioNombre"]?.comoTexto
                e.series[i].varianteRegistrada = d["notas"]?.comoTexto
                anotarFecha(ex, i + 1, FechaJS.ymd(Date(timeIntervalSince1970: op.ts / 1000), zona: zona))
                dia.ejercicios[ex] = e
            } else if op.kind == "estado", let ex = p["exId"]?.comoTexto, let st = p["status"]?.comoTexto {
                dia.estados[ex] = st
                dia.ejercicios[ex]?.estado = st
                dia.ejercicios[ex]?.completo = st == "completo" || st == "completo_sin_datos"
            }
        }
    }

    // MARK: - Cerrar el día (SES-06/07)

    public enum ResultadoCierre: Equatable, Sendable {
        case cerrado
        /// "No se pudo guardar la sesión. Revisá tu conexión e intentá de nuevo."
        case sinSesion
        /// "No se pudo terminar el entrenamiento. Revisá tu conexión e intentá de nuevo."
        case fallo
        /// Demo: no se cierra nada.
        case demo

        public var aviso: String? {
            switch self {
            case .sinSesion: return TextosEntreno.cerrarSinSesion
            case .fallo: return TextosEntreno.cerrarFallo
            case .cerrado, .demo: return nil
            }
        }
    }

    /// `writeFinish`: PRIMERO vacía la cola (las series tienen que estar en la base antes de cerrar), después
    /// `finalizar_sesion` con la duración (null si pasa de 6 h). Un `false` es que no se cerró.
    public func cerrarDia(notas: String, fin: Double? = nil) async -> ResultadoCierre {
        await vaciarDeshacer()
        guard !demo, let token else {
            // La demo no cierra nada en el servidor, pero el descanso termina igual.
            if demo {
                descanso.detener()
                guardarDescanso()
            }
            return .demo
        }
        await asegurarSesion()
        guard let sid = dia.sesionId else { return .sinSesion }
        await outbox?.drenar()
        // `fin`: cuándo se terminó de verdad (el «terminar» del reloj que llega después).
        let minutos = TiempoEntreno.minutosSesion(inicio: inicioSesion, ahora: min(fin ?? ahoraMs, ahoraMs))
        let notas = JS.trim(notas)
        let r = await cliente.llamar("mypump_finalizar_sesion", [
            "p_token": .texto(token), "p_sesion_id": .texto(sid), "p_notas": notas.isEmpty ? .null : .texto(notas),
            "p_duracion_segundos": minutos.map { .numero(Double($0 * 60)) } ?? .null,
        ])
        guard case .success(let v) = r, v != .bool(false) else { return .fallo }
        dia.diaFinalizado = true
        descanso.detener()
        guardarDescanso()
        if let d = dia.dia.id {
            var l = sesionesLocales[d] ?? SesionLocal(semana: semana)
            l.finalizada = true
            sesionesLocales[d] = l
            guardarSesiones()
            diasCompletados.insert(d)
        }
        // Las "solo hoy" de OTROS días expiran; las de hoy se conservan por si se reabre para corregir.
        podarSustituciones(conservarDiaActual: true)
        return .cerrado
    }

    /// Los récords del día (2.3.0, `ReglasWins`): lo que se festeja después de cerrar la sesión. Las marcas de antes salen
    /// del historial por clave de días anteriores (lo mismo que usa el aviso de récord al confirmar una serie).
    public func recordsDeHoy() -> [ReglasWins.Record] {
        ReglasWins.records(dia.entradasDeRecords(hoy: FechaJS.ymd(reloj(), zona: zona)) { self.efectivo($0).ejercicio })
    }

    // MARK: - Semana nueva y bloque nuevo (ENT-14/15)

    public enum ResultadoAvance: Equatable, Sendable {
        /// Se avanzó: la rutina ya se recargó.
        case listo
        /// No salió: la pregunta de la web ("Sin conexión" / "No se pudo pasar de semana"); "Recargar" es `recargar()`.
        case error(Pregunta)
    }

    /// `doAvanzarSemana`: manda la semana DESTINO (`actual + 1`, idempotente; el servidor nunca retrocede, 077),
    /// borra los cachés de sesión y recarga.
    public func avanzarSemana() async -> ResultadoAvance {
        await vaciarDeshacer()
        guard let token, !demo else { return .error(SemanaEntreno.errorAvanzar(sinRed: false)) }
        let destino = semana + 1
        let r = await cliente.llamar("mypump_avanzar_semana", ["p_token": .texto(token), "p_semana_destino": .numero(Double(destino))])
        if case .success(let v) = r, v != .null {
            borrarCachesDeSesion()
            if !(await recargar()) {
                // El servidor ya está en la semana nueva y la rutina no llegó (se cortó la señal en el medio): la misma
                // rutina en esa semana. Si no, lo que se cargara iba a la semana pasada y pisaba sus series (revisión
                // del 15-oct, hallazgo 1).
                let nueva = rutina.conSemana(destino)
                reemplazarRutina(nueva)
                alCambiarRutina?(.semana(nueva))
                await cargar()
            }
            return .listo
        }
        return .error(SemanaEntreno.errorAvanzar(sinRed: Self.sinRed(r)))
    }

    /// `doEmpezarBloqueNuevo`: `activar_siguiente`, y si activó, lo mismo que avanzar.
    public func empezarBloqueNuevo() async -> ResultadoAvance {
        await vaciarDeshacer()
        guard let token, !demo else { return .error(SemanaEntreno.errorBloqueNuevo(sinRed: false)) }
        let r = await cliente.llamar("mypump_activar_siguiente", ["p_token": .texto(token)])
        if case .success(let v) = r, AnclajeSwaps.esVerdadero(v) {
            borrarCachesDeSesion()
            if !(await recargar()) {
                // El bloque nuevo quedó activo y no llegó: el viejo está archivado y lo que se cargara en él armaba
                // sesiones fantasma en el nuevo. Sin rutina hasta que vuelva la señal (la próxima carga trae el nuevo).
                usable = false
                alCambiarRutina?(.bloqueSinTraer)
            }
            return .listo
        }
        return .error(SemanaEntreno.errorBloqueNuevo(sinRed: Self.sinRed(r)))
    }

    /// Lo que en la web es `location.reload()`: trae la rutina activa y arranca de nuevo. false si no llegó.
    @discardableResult
    public func recargar() async -> Bool {
        await vaciarDeshacer()
        guard let token else { return false }
        guard case .success(let j) = await cliente.llamar("mypump_get_rutina_activa", ["p_token": .texto(token)]),
              case .lista(let filas) = j, let fila = filas.first,
              let nueva = try? JSONDecoder().decode(RutinaActiva.self, from: JSONEncoder().encode(fila)) else { return false }
        reemplazarRutina(nueva)
        alCambiarRutina?(.nueva(nueva, fila))
        await cargar()
        return true
    }

    /// Una rutina nueva (la trajo este modelo o `ModeloApp`): todo lo del día se arma de cero.
    public func reemplazarRutina(_ nueva: RutinaActiva) {
        soltarDeshacer()
        historialEnVuelo.values.forEach { $0.cancel() }
        historialEnVuelo = [:]
        historialCargando = []
        generacionHistorial = generacionHistorial.mapValues { $0 + 1 }
        restauracion += 1
        rutina = nueva
        let n = NormalizacionRutina.normalizar(nueva.estructura)
        estructura = n.estructura
        usable = n.usable
        problemas = n.problemas
        let semana = nueva.semanaActual == 0 ? 1 : nueva.semanaActual
        let elegido = TextosEntreno.diaSugerido(n.estructura.dias, ultimo: disco?.leer(String.self, Archivo.dia(nueva.id))) ?? Dia(id: "d1")
        let sustituciones = SustitucionesEntreno.compat(disco?.leer([String: JSONValue].self, Archivo.sustituciones(nueva.id)) ?? [:])
        let descansos = dia.descansosPropios
        dia = DiaEnCurso(dia: elegido, semana: semana, demo: demo, zona: zona)
        leerCargas()
        dia.sustituciones = sustituciones
        dia.descansosPropios = descansos
        sustitucionesGuardadas = disco?.leer([String: JSONValue].self, SustitucionesServidor.archivoEncoladas(rutinaId: nueva.id)) ?? sustituciones
        syncSustituciones = nil
        tocadasDuranteSync = nil
        diasCompletados = []
        diaCompletadoMostrado = false
        inicioSesion = nil
        sesionIniciada = false
        guardarDiaVisualizado()
    }

    static func sinRed(_ r: Result<JSONValue, ErrorRPC>) -> Bool {
        if case .failure(let e) = r { return e.clase != .permanente }
        return false
    }

    func borrarCachesDeSesion() {
        sesionesLocales = [:]
        disco?.borrar(Archivo.sesiones)
    }

    /// `loadDiasCompletados`: los días con la sesión de esta semana cerrada. Después se podan las sustituciones.
    public func cargarDiasCompletados() async {
        guard !demo, let token else { return }
        if case .success(let filas) = await cliente.filas("mypump_get_sesiones_semana", ["p_token": .texto(token), "p_semana": .numero(Double(semana))],
                                                          como: Sesion.self) {
            diasCompletados = Set(filas.filter { $0.finalizadaEn != nil }.map(\.diaId))
            podarSustituciones()
        }
    }

    // MARK: - Historial por clave (SER-08/09/10)

    /// La clave del ejercicio EFECTIVO de un lugar (cualquier día de la rutina): `claveDeSlot`.
    public func clave(_ lugar: String) -> String? {
        guard let ex = dias.lazy.flatMap({ $0.bloques.flatMap(\.ejercicios) }).first(where: { $0.id == lugar }) else { return nil }
        let nombre = SustitucionesEntreno.aplicada(dia.sustituciones[lugar])?.nombre ?? ex.nombre
        return JS.verdadero(ClaveEjercicio.de(nombre))
    }

    enum Historial {
        case filas([RegistroHistorico])
        /// Falló este pedido (red): queda sin cargar para reintentar. NUNCA se cae al camino por lugar.
        case sinRed
    }

    /// `loadHistorico`: el historial por clave del efectivo (48 filas). Si ya hay uno en vuelo, espera a ese. Con
    /// PGRST202 (la 072 no está) cae al camino viejo por lugar, y se recuerda.
    public func pedirHistorial(_ lugar: String) async {
        if let t = historialEnVuelo[lugar] { await t.value; return }
        if dia.historial[lugar] != nil { return }
        let clave = self.clave(lugar)
        let gen = (generacionHistorial[lugar] ?? 0) + 1
        generacionHistorial[lugar] = gen
        historialCargando.insert(lugar)
        let t = Task { [weak self] in
            guard let self else { return }
            let r = await self.traerHistorial(clave: clave, lugar: lugar)
            // CARRERA (SER-10): si mientras viajaba se sustituyó o se revirtió, esta respuesta es de OTRO ejercicio.
            guard self.generacionHistorial[lugar] == gen, self.clave(lugar) == clave else { return }
            self.historialCargando.remove(lugar)
            self.historialEnVuelo[lugar] = nil
            if case .filas(let f) = r { self.dia.historial[lugar] = f }
        }
        historialEnVuelo[lugar] = t
        await t.value
    }

    func traerHistorial(clave: String?, lugar: String) async -> Historial {
        guard let token else {
            if let muestra = Self.historialDeMuestra { return .filas(muestra(clave ?? "")) }
            return .filas(demo ? (historialDemo?[clave ?? ""] ?? []) : [])
        }
        if let clave, !sinHistorialPorClave {
            switch await porClave([clave]) {
            case .some(.some(let m)): return .filas(m[clave] ?? [])
            case .some(.none): return .sinRed
            case .none: break   // no existe: camino viejo
            }
        }
        switch await cliente.filas("mypump_get_historico_ejercicio", ["p_token": .texto(token), "p_ejercicio_id": .texto(lugar), "p_limit": .numero(48)],
                                   como: RegistroHistorico.self) {
        case .success(let f): return .filas(f)
        case .failure: return .sinRed
        }
    }

    /// `getHistoricoPorClave`: nil = la RPC no existe (PGRST202, se recuerda); .some(nil) = falló (red); si no, las
    /// filas por clave, con TODAS las claves pedidas (vacías si no hay nada).
    func porClave(_ claves: [String]) async -> [String: [RegistroHistorico]]?? {
        guard let token else { return .some(nil) }
        if sinHistorialPorClave { return nil }
        var vistas = Set<String>()
        let ks = claves.filter { !$0.isEmpty && vistas.insert($0).inserted }
        var m: [String: [RegistroHistorico]] = [:]
        for k in ks { m[k] = [] }
        guard !ks.isEmpty else { return .some(m) }
        switch await cliente.filas("mypump_get_historico_por_clave",
                                   ["p_token": .texto(token), "p_claves": .lista(ks.map(JSONValue.texto)), "p_limit_por_ej": .numero(Double(RecordSerie.topeHistorial))],
                                   como: RegistroHistorico.self) {
        case .failure(let e):
            if Self.noExiste(e) { sinHistorialPorClave = true; return nil }
            return .some(nil)
        case .success(let filas):
            for f in filas { if let c = f.clave, m[c] != nil { m[c]!.append(f) } }
            return .some(m)
        }
    }

    static func noExiste(_ e: ErrorRPC) -> Bool {
        e.funcionInexistente || e.mensaje.range(of: #"PGRST202|could not find the function|does not exist"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// `prefetchHistoricoDia`: UN pedido para todo el día, repartido a los lugares que comparten clave. Si no salió,
    /// de a uno (que deja sin cargar lo que falle por red).
    public func precargarHistorial() async {
        let ids = dia.lista.filter { $0.tipo != "calentamiento" && dia.historial[$0.id] == nil && historialEnVuelo[$0.id] == nil }.map(\.id)
        guard !ids.isEmpty else { return }
        var vistas = Set<String>()
        let claves = ids.compactMap { clave($0) }.filter { vistas.insert($0).inserted }
        let lote: [String: [RegistroHistorico]]?? = claves.isEmpty ? .some(nil) : await porClave(claves)
        guard case .some(.some(let m)) = lote else {
            await withTaskGroup(of: Void.self) { g in for id in ids { g.addTask { await self.pedirHistorial(id) } } }
            return
        }
        for id in ids where historialEnVuelo[id] == nil {
            if let k = clave(id), let filas = m[k] { dia.historial[id] = filas }
        }
        let faltan = ids.filter { dia.historial[$0] == nil }
        await withTaskGroup(of: Void.self) { g in for id in faltan { g.addTask { await self.pedirHistorial(id) } } }
    }

    /// `invalidarHistorico`: el lugar pasó a ser otro ejercicio; lo que había (o venía en camino) es de otro.
    func invalidarHistorial(_ lugar: String) {
        dia.historial[lugar] = nil
        historialEnVuelo[lugar]?.cancel()
        historialEnVuelo[lugar] = nil
        historialCargando.remove(lugar)
        generacionHistorial[lugar] = (generacionHistorial[lugar] ?? 0) + 1
    }

    // MARK: - Sustituciones (SER-11..14)

    /// Los sustitutos del lugar (mismo patrón y músculo, otro equipo primero, 30), filtrados por la búsqueda del modal.
    public func sustitutos(_ lugar: String, busqueda: String = "") -> [SustitutoEjercicio] {
        guard let ex = dia.ejercicio(lugar) else { return [] }
        return SustitucionesEntreno.filtrar(catalogo.sustitutos(de: efectivo(ex)), busqueda)
    }

    /// Los otros ejercicios del mismo músculo, con otro movimiento (la sección de abajo de «Sustituir»; Mati, 20-oct).
    public func otrosDelMismoMusculo(_ lugar: String, busqueda: String = "") -> [SustitutoEjercicio] {
        guard let ex = dia.ejercicio(lugar) else { return [] }
        return SustitucionesEntreno.filtrar(catalogo.otrosDelMismoMusculo(de: efectivo(ex)), busqueda)
    }

    /// El sustituto elegido en la hoja, buscado por su clave en las listas de AHORA (con el catálogo que haya llegado
    /// mientras tanto). nil si ya no está en ninguna.
    public func sustituto(_ lugar: String, clave: String) -> SustitutoEjercicio? {
        sustitutos(lugar).first { $0.clave == clave } ?? otrosDelMismoMusculo(lugar).first { $0.clave == clave }
    }

    /// El "🔒 Fijar" arranca como estaba la sustitución previa (al cambiar de sustituto no se pierde).
    public func fijadaAntes(_ lugar: String) -> Bool { SustitucionesEntreno.aplicada(dia.sustituciones[lugar])?.fijado ?? false }

    /// `confirmExSwap`: sin fijar vale solo por hoy. La serie se registra con el nombre del sustituto y el id del lugar.
    public func sustituir(_ lugar: String, por sub: SustitutoEjercicio, fijar: Bool) async {
        await vaciarDeshacer()
        guard let ex = dia.ejercicio(lugar) else { return }
        let ef = efectivo(ex)
        invalidarHistorial(lugar)
        let previa = dia.sustituciones[lugar]
        let efectos = dia.sustituir(lugar, por: sub, efectivo: ef, fijado: fijar)
        // SER-14: la hora del cambio (en el servidor gana lo más nuevo), nunca menos que la de lo que reemplaza. Es solo
        // de la nativa: la web no la lee.
        if let s = dia.sustituciones[lugar] {
            dia.sustituciones[lugar] = SustitucionesServidor.conHora(
                s, SustitucionesServidor.horaDeUnCambio(ahoraMs + desfaseReloj, reemplaza: previa, piso: pisoPorClave[lugar] ?? 0))
        }
        await ejecutar(efectos)
        guardarCargas()
    }

    /// "Volver a …"
    public func revertirSustitucion(_ lugar: String) async {
        await vaciarDeshacer()
        pisoPorClave[lugar] = max(pisoPorClave[lugar] ?? 0, SustitucionesServidor.ts(dia.sustituciones[lugar]))
        invalidarHistorial(lugar)
        await ejecutar(dia.revertir(lugar))
        guardarCargas()
    }

    /// `pruneExerciseSwaps` (SER-12): las no fijadas de otra semana o de un día cerrado se van.
    func podarSustituciones(conservarDiaActual: Bool = false, sinPrecarga: Bool = false) {
        let r = SustitucionesEntreno.podar(dia.sustituciones, semanaActual: semana, diasCompletados: diasCompletados, diaActual: dia.dia.id,
                                           diaFinalizado: dia.diaFinalizado, conservarDiaActual: conservarDiaActual)
        guard !r.borradas.isEmpty else { return }
        dia.sustituciones = r.quedan
        // SER-14: la poda es solo de este teléfono y no se manda: un teléfono viejo no puede borrar en el servidor lo que
        // el cliente fijó después en otro (lo vencido que quede allá, cada teléfono lo poda al leerlo).
        for id in r.borradas {
            sustitucionesGuardadas[id] = nil
            invalidarHistorial(id)
        }
        guardarSustituciones()
        anotarEncoladas(sustitucionesGuardadas, rutinaId: rutina.id)
        if !sinPrecarga { Task { await self.precargarHistorial() } }
    }

    /// SER-14: lee el servidor y lo combina con lo del teléfono clave por clave (gana lo más nuevo; ver
    /// `SustitucionesServidor.combinar`), y sube lo que el servidor no tiene o tiene más viejo. Sin la tabla en la base
    /// (PGRST202), sin red o con el token caído queda lo del teléfono, como antes, y se reintenta al recargar.
    public func sincronizarSustituciones() async {
        guard !demo, let token, syncSustituciones == nil else { return }
        let mia = UUID()
        syncSustituciones = mia
        tocadasDuranteSync = []
        defer {
            if syncSustituciones == mia {
                syncSustituciones = nil
                tocadasDuranteSync = nil
            }
        }
        // Lo que ya se cambió tiene que estar en la cola antes de preguntar.
        await encoladoSustituciones?.value
        guard syncSustituciones == mia else { return }
        let rutinaId = rutina.id
        // Lo que está en la cola al empezar (la respuesta puede no traerlo aunque se mande en el medio) y lo que quedó en
        // fallidos (nunca llegó): ahí queda lo del teléfono.
        let prefijo = "swap_ej_\(rutinaId)_"
        if let outbox {
            let enCola = Array(await outbox.pendientesPorClave().filter { $0.key.hasPrefix(prefijo) }.values)
            let fallidas = await outbox.fallidos.map(\.op).filter { ($0.dedupeKey ?? "").hasPrefix(prefijo) }
            for op in enCola + fallidas { if let ex = op.payload["exId"]?.comoTexto { tocadasDuranteSync?.insert(ex) } }
        }
        guard syncSustituciones == mia else { return }
        let r = await cliente.llamar("mypump_get_exercise_swaps", ["p_token": .texto(token), "p_rutina_id": .texto(rutinaId)])
        guard syncSustituciones == mia, rutina.id == rutinaId, case .success(let j) = r, let servidor = SustitucionesServidor.leer(j)
        else { return }
        if let ahora = servidor.ahora {
            desfaseReloj = ahora - ahoraMs
            disco?.guardar(desfaseReloj, Archivo.reloj)
        }
        for (k, b) in servidor.borradas { pisoPorClave[k] = max(pisoPorClave[k] ?? 0, b) }
        await encoladoSustituciones?.value
        let pendientes = await outbox?.pendientesPorClave() ?? [:]
        guard syncSustituciones == mia, rutina.id == rutinaId else { return }
        let tocadas = tocadasDuranteSync ?? []
        let combinado = SustitucionesEntreno.compat(SustitucionesServidor.combinar(
            vivas: servidor.vivas, borradas: servidor.borradas, local: dia.sustituciones, pendientes: pendientes, rutinaId: rutinaId,
            tocadas: tocadas, ahora: servidor.ahora))
        // La poda antes de comparar: lo vencido que vuelve del servidor ni se muestra ni pide su historial de nuevo.
        let poda = SustitucionesEntreno.podar(combinado, semanaActual: semana, diasCompletados: diasCompletados, diaActual: dia.dia.id,
                                              diaFinalizado: dia.diaFinalizado, conservarDiaActual: false)
        let antes = dia.sustituciones
        let cambiadas = Set(poda.quedan.keys).union(antes.keys).filter { poda.quedan[$0] != antes[$0] }
        // Contra lo que tiene el servidor se calcula qué subir. Lo podado no se manda, y lo que ya está en la cola (o se
        // tocó, o quedó en fallidos) no se vuelve a encolar.
        var base = SustitucionesEntreno.compat(servidor.vivas)
        for id in poda.borradas { base[id] = nil }
        for id in tocadas.union(pendientes.keys.filter { $0.hasPrefix(prefijo) }.map { String($0.dropFirst(prefijo.count)) }) {
            base[id] = poda.quedan[id]
        }
        sustitucionesGuardadas = base
        dia.sustituciones = poda.quedan
        guardarSustituciones()
        anotarEncoladas(sustitucionesGuardadas, rutinaId: rutinaId)
        for id in cambiadas { invalidarHistorial(id) }
        if !cambiadas.isEmpty { await precargarHistorial() }
    }

    // MARK: - Comentarios (SES-08)

    /// `loadComentarios`. Si falla, quedan los que había (la web los borraba hasta el próximo intento).
    public func cargarComentarios() async {
        guard !demo, let token else { return }
        if case .success(let filas) = await cliente.filas("mypump_get_comentarios", ["p_token": .texto(token), "p_ambito": .null, "p_referencia_id": .null],
                                                          como: Comentario.self) {
            comentarios = IndiceComentarios(filas)
        }
    }

    /// `enviarComentarioEjercicio`: va directo (no por la cola). false: avisar `TextosEntreno.comentarioFallo`.
    public func comentar(_ lugar: String, _ texto: String) async -> Bool {
        let contenido = JS.trim(texto)
        guard !contenido.isEmpty, !demo, let token else { return false }
        let r = await cliente.llamar("mypump_agregar_comentario", [
            "p_token": .texto(token), "p_ambito": .texto("ejercicio"), "p_referencia_id": .texto(lugar),
            "p_referencia_nombre": .texto(dia.ejercicio(lugar)?.nombre ?? ""), "p_contenido": .texto(contenido),
        ])
        guard case .success(let v) = r, Outbox.seGuardo(v) else { return false }
        await cargarComentarios()
        return true
    }

    /// `marcarLeidosEjercicio`: optimista (el badge se va ya); la base se avisa sin esperar.
    public func marcarLeidos(_ lugar: String) async {
        guard comentarios.sinLeer(ejercicio: lugar) > 0 else { return }
        comentarios.marcarLeidos(ejercicio: lugar)
        guard !demo, let token else { return }
        _ = await cliente.llamar("mypump_marcar_leidos_cliente", ["p_token": .texto(token), "p_ambito": .texto("ejercicio"), "p_referencia_id": .texto(lugar)])
    }

    // MARK: - Descanso (SES-04)

    /// El tick de la barra (cada 250 ms y al volver a primer plano). true la vez que termina: la app suena y vibra.
    @discardableResult
    public func tickDescanso() -> Bool {
        let termino = descanso.tick(ahora: ahoraMs)
        guardarDescanso()
        return termino
    }

    /// −15 / +15
    public func ajustarDescanso(_ segundos: Int) {
        descanso.ajustar(String(segundos), ahora: ahoraMs)
        guardarDescanso()
    }

    /// "Saltar"
    public func saltarDescanso() {
        descanso.ajustar("skip", ahora: ahoraMs)
        guardarDescanso()
    }

    /// Al volver a primer plano (GEN-07): el descanso se recalcula contra el reloj y la cola se drena.
    public func alVolverAPrimerPlano() async -> Bool {
        let termino = tickDescanso()
        await outbox?.drenar()
        return termino
    }

    // MARK: - Efectos

    @discardableResult
    func ejecutar(_ efectos: [DiaEnCurso.Efecto]) async -> DiaCompletado? {
        var completo: DiaCompletado?
        for e in efectos {
            switch e {
            case .encolar(let kind, let payload, let clave):
                await encolarYAnotar(kind, payload, clave: clave)
            case .iniciarDescanso(let s):
                // Una serie que llega tarde (del reloj) ancla el descanso a cuando se hizo; si ya terminó, no arranca.
                let desde = min(instanteEvento ?? ahoraMs, ahoraMs)
                if desde + (s + 2) * 1000 > ahoraMs {
                    descanso.iniciar(segundos: s, ahora: desde)
                    guardarDescanso()
                }
            case .detenerDescanso:
                descanso.detener()
                guardarDescanso()
            case .asegurarSesion:
                arrancarCronometro()
                Task { await self.asegurarSesion() }
            case .pedirHistorial(let lugar):
                await pedirHistorial(lugar)
            case .marcarLeidos(let lugar):
                Task { await self.marcarLeidos(lugar) }
            case .guardarSustituciones:
                guardarSustituciones()
            case .reabrioDia:
                if let d = dia.dia.id, sesionesLocales[d] != nil {
                    sesionesLocales[d]!.finalizada = false
                    guardarSesiones()
                }
            case .diaCompleto:
                // Con el día completo no hay próxima serie: el descanso de la última serie no tiene sentido y dejaba la
                // Live Activity («¡A la próxima serie!») y el aviso de fin después del entreno (revisión del 20-oct).
                descanso.detener()
                guardarDescanso()
                if !diaCompletadoMostrado {
                    diaCompletadoMostrado = true
                    let (p, sig) = SemanaEntreno.preguntaDiaCompletado(dias: dias, actual: dia.dia.id)
                    completo = DiaCompletado(pregunta: p, siguiente: sig)
                }
            }
        }
        // En la demo la regla no avisa el día completo (no hay pregunta ni servidor), pero el descanso de la última serie
        // tampoco tiene sentido: la demo es lo que mira la revisión de Apple (revisión del 20-oct).
        if demo, dia.diaCompleto, descanso.descanso != nil {
            descanso.detener()
            guardarDescanso()
        }
        return completo
    }

    // MARK: - Lo que vive en el teléfono

    /// Lo que la web guardaba en `mypump_sesion_<TOKEN>_<dia>{,_semana,_finalizada,_start}`.
    public struct SesionLocal: Codable, Equatable, Sendable {
        public var sesionId: String?
        public var semana: Int?
        public var finalizada = false
        /// `_start` (ms).
        public var inicio: Double?

        public init(sesionId: String? = nil, semana: Int?, finalizada: Bool = false, inicio: Double? = nil) {
            self.sesionId = sesionId; self.semana = semana; self.finalizada = finalizada; self.inicio = inicio
        }
    }

    enum Archivo {
        static let sesiones = "entreno-sesiones.json"
        static let descanso = "entreno-descanso.json"
        static let legado = "legado-entreno.json"
        /// E2: el descanso elegido a mano por ejercicio (`[clave: segundos]`), de la cuenta y no de una rutina.
        static let descansos = "entreno-descansos.json"
        /// E1: los tildes de la preparación de hoy y los ejercicios con la preparación oculta.
        static let preparacion = "entreno-preparacion.json"
        /// 2.3.0: lo escrito por un OK dentro de su ventana de Deshacer (si la app muere ahí, va a la cola al abrir).
        static let okDemorado = "entreno-ok-demorado.json"
        /// F1: lo que este teléfono mandó del día (`anotadas`), con su rutina.
        static let anotadas = "entreno-anotadas.json"
        /// 2.3.0: la carga simple de la semana.
        static func cargas(_ rutinaId: String) -> String { "entreno-cargas_\(rutinaId).json" }
        static let preparacionOculta = "entreno-preparacion-oculta.json"
        static func dia(_ rutinaId: String) -> String { "entreno-dia_\(rutinaId).json" }
        static func sustituciones(_ rutinaId: String) -> String { "ejercicios-swaps_\(rutinaId).json" }
        /// SER-14: el desfase del reloj con el servidor.
        static let reloj = "reloj-servidor.json"
    }

    var ahoraMs: Double { reloj().timeIntervalSince1970 * 1000 }

    func guardarDiaVisualizado() {
        guard let id = dia.dia.id else { return }
        disco?.guardar(id, Archivo.dia(rutina.id))
    }

    func guardarSustituciones() {
        disco?.guardar(dia.sustituciones, Archivo.sustituciones(rutina.id))
        encolarSustituciones()
    }

    /// SER-14: lo que cambió desde la última escritura sale por la cola, en orden (sin la tabla en la base, la cola lo da
    /// por hecho y queda solo en el teléfono, como antes).
    func encolarSustituciones() {
        let ahora = dia.sustituciones
        let ops = SustitucionesServidor.operaciones(antes: sustitucionesGuardadas, ahora: ahora, rutinaId: rutina.id)
        sustitucionesGuardadas = ahora
        guard !demo, token != nil, let outbox, !ops.isEmpty else { return }
        tocadasDuranteSync?.formUnion(ops.map(\.exId))
        let anterior = encoladoSustituciones, disco = disco, rutinaId = rutina.id
        encoladoSustituciones = Task {
            await anterior?.value
            for op in ops { await outbox.encolar(op.kind, op.payload, dedupeKey: op.clave) }
            disco?.guardar(ahora, SustitucionesServidor.archivoEncoladas(rutinaId: rutinaId))
        }
    }

    /// Anota en disco que `m` ya está en la cola (o en el servidor), detrás de los encolados en curso.
    func anotarEncoladas(_ m: [String: JSONValue], rutinaId: String) {
        let anterior = encoladoSustituciones, disco = disco
        encoladoSustituciones = Task {
            await anterior?.value
            disco?.guardar(m, SustitucionesServidor.archivoEncoladas(rutinaId: rutinaId))
        }
    }

    func guardarSesiones() { disco?.guardar(sesionesLocales, Archivo.sesiones) }

    /// F1: una serie o un estado mandados desde este teléfono (lo que se pinta si al reabrir el servidor no contesta).
    struct EscrituraAnotada: Codable, Equatable, Sendable {
        var kind: String
        var payload: JSONValue
        var ts: Double
        /// La rutina en la que se escribió: un bloque nuevo repite días y semanas, y lo del viejo no se pinta ahí.
        var rutinaId: String?
    }

    /// Cuánto se guarda lo mandado: una semana alcanza para el día que se mira (una sesión que cruza la medianoche, o
    /// abrir sin red al otro día) sin que el archivo crezca.
    static let vigenciaAnotadas: Double = 7 * 24 * 3600 * 1000

    static func podarAnotadas(_ a: [String: EscrituraAnotada], ahora: Double) -> [String: EscrituraAnotada] {
        a.filter { ahora - $0.value.ts < vigenciaAnotadas }
    }

    /// Toda escritura del día pasa por acá: a la cola y, si es una serie o un estado, anotada en el teléfono (F1).
    func encolarYAnotar(_ kind: String, _ payload: JSONValue, clave: String?) async {
        await outbox?.encolar(kind, payload, dedupeKey: clave)
        guard kind == "carga" || kind == "estado", let clave, !demo else { return }
        anotadas[clave] = EscrituraAnotada(kind: kind, payload: payload, ts: ahoraMs, rutinaId: rutina.id)
        disco?.guardar(anotadas, Archivo.anotadas)
    }

    func guardarInicio() {
        guard let d = dia.dia.id else { return }
        var l = sesionesLocales[d] ?? SesionLocal(semana: semana)
        l.inicio = inicioSesion
        l.semana = l.semana ?? semana
        sesionesLocales[d] = l
        guardarSesiones()
    }

    func guardarDescanso() {
        guard descanso.guardado != descansoEnDisco else { return }
        descansoEnDisco = descanso.guardado
        if let g = descanso.guardado { disco?.guardar(g, Archivo.descanso) } else { disco?.borrar(Archivo.descanso) }
    }
}
