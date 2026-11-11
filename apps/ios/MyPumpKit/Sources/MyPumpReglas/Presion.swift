import Foundation
import MyPumpModelos

/// Reglas puras de «Presión arterial» (`presion/CONTRATO_APP.md`). Gemelo de `public/js/presion.js`, que es la referencia:
/// `apps/shared/vectores/presion.json` hace fallar las pruebas si difieren.
///
/// Invariantes:
/// · El alumno no ve promedios, colores, categorías ni palabras como hipertensión, normal, alta o riesgo. Lo que calcula
///   `resumenSerie` no se muestra: solo el avance.
/// · La presión nunca frena el entrenamiento: nada de acá toca la rutina.
/// · El texto de guardia se decide acá, sin esperar al servidor.
public enum Presion {
    public enum Lim {
        public static let sisMin = 60, sisMax = 260, diaMin = 30, diaMax = 160, pulMin = 25, pulMax = 220, difMin = 10
    }
    public static let esperaRepeticionS = 300
    public static let reposoS = 300
    public static let recordatorioMin = 10
    /// Minutos sin repetir una toma de 180/120 para que cuente como alta (el recordatorio sale a los 10).
    public static let sinRepetirMin = 15

    public static let alarma = ["dolor_pecho", "falta_aire", "cefalea_fuerte_nueva", "cambios_vista", "debilidad_un_lado", "dificultad_hablar", "confusion", "desmayo"]
    public static let otros = ["palpitaciones", "mareo_al_pararse", "vomitos_diarrea"]

    // MARK: Tipos

    public struct Toma: Codable, Equatable, Sendable {
        public var orden: Int
        /// "sentado", "acostado" o "de_pie". Sin dato vale sentado.
        public var posicion: String?
        public var minutosDePie: Int?
        public var brazo: String?
        public var sis: Int
        public var dia: Int
        public var pulso: Int
        public var latidoIrregular: Bool
        public var medidoEn: String?
        public var confirmadaPorAlumno: Bool

        public init(orden: Int, posicion: String? = "sentado", minutosDePie: Int? = nil, brazo: String? = nil, sis: Int, dia: Int, pulso: Int,
                    latidoIrregular: Bool = false, medidoEn: String? = nil, confirmadaPorAlumno: Bool = false) {
            self.orden = orden; self.posicion = posicion; self.minutosDePie = minutosDePie; self.brazo = brazo
            self.sis = sis; self.dia = dia; self.pulso = pulso; self.latidoIrregular = latidoIrregular
            self.medidoEn = medidoEn; self.confirmadaPorAlumno = confirmadaPorAlumno
        }

        /// Tolerante: sin alta, baja o pulso enteros no hay toma; lo demás vale lo de fábrica.
        public init?(_ j: JSONValue) {
            guard let s = Presion.entero(j["sis"]), let d = Presion.entero(j["dia"]), let p = Presion.entero(j["pulso"]) else { return nil }
            sis = s; dia = d; pulso = p
            orden = Presion.entero(j["orden"]) ?? 1
            posicion = j["posicion"]?.comoTexto
            minutosDePie = Presion.entero(j["minutos_de_pie"])
            brazo = j["brazo"]?.comoTexto
            latidoIrregular = j["latido_irregular"] == .bool(true)
            medidoEn = j["medido_en"]?.comoTexto
            confirmadaPorAlumno = j["confirmada_por_alumno"] == .bool(true)
        }

        var sentado: Bool { posicion == "sentado" || posicion == nil || posicion == "" }
    }

    public struct Previo: Codable, Equatable, Sendable {
        public var cafeina = false, fumo = false, comida = false, ejercicio = false
        public init(cafeina: Bool = false, fumo: Bool = false, comida: Bool = false, ejercicio: Bool = false) {
            self.cafeina = cafeina; self.fumo = fumo; self.comida = comida; self.ejercicio = ejercicio
        }
        public var alguno: Bool { cafeina || fumo || comida || ejercicio }
    }

    /// Una sesión de medición: lo que evalúa `evaluarSesion` y lo que se manda a `mypump_presion_sesion`.
    public struct Sesion: Codable, Equatable, Sendable {
        public var id: String?
        public var serieId: String?
        /// "estandar", "bajo_efecto", "suelta", "ortostatica" o "comparacion_brazos".
        public var tipo: String
        public var inicio: String?
        public var zonaHoraria: String?
        public var brazo: String?
        public var previo: Previo
        public var reposoCumplido: Bool?
        public var temporizadorSalteado: Bool?
        public var dosisEstimulanteHora: String?
        public var entrenoEntreDosisYToma: Bool?
        public var sintomas: [String]
        /// nil sin contestar, "si" con algún Sí, "no" con todos en No.
        public var listaEspera: String?
        public var nota: String?
        /// Minutos desde la última toma: solo para evaluar, no viaja.
        public var minutosDesdeUltima: Double
        public var tomas: [Toma]
        /// Día local "AAAA-MM-DD" y orden dentro del día: los usa `resumenSerie`.
        public var fecha: String?
        public var orden: Int?

        public init(id: String? = nil, serieId: String? = nil, tipo: String = "estandar", inicio: String? = nil, zonaHoraria: String? = nil, brazo: String? = nil,
                    previo: Previo = Previo(), reposoCumplido: Bool? = nil, temporizadorSalteado: Bool? = nil, dosisEstimulanteHora: String? = nil,
                    entrenoEntreDosisYToma: Bool? = nil, sintomas: [String] = [], listaEspera: String? = nil, nota: String? = nil, minutosDesdeUltima: Double = 0,
                    tomas: [Toma] = [], fecha: String? = nil, orden: Int? = nil) {
            self.id = id; self.serieId = serieId; self.tipo = tipo; self.inicio = inicio; self.zonaHoraria = zonaHoraria; self.brazo = brazo
            self.previo = previo; self.reposoCumplido = reposoCumplido; self.temporizadorSalteado = temporizadorSalteado
            self.dosisEstimulanteHora = dosisEstimulanteHora; self.entrenoEntreDosisYToma = entrenoEntreDosisYToma
            self.sintomas = sintomas; self.listaEspera = listaEspera; self.nota = nota; self.minutosDesdeUltima = minutosDesdeUltima
            self.tomas = tomas; self.fecha = fecha; self.orden = orden
        }

        /// Con la forma de los vectores y del servidor (claves con guion bajo).
        public init(_ j: JSONValue) {
            id = j["id"]?.comoTexto
            serieId = j["serie_id"]?.comoTexto
            tipo = j["tipo"]?.comoTexto ?? "estandar"
            inicio = j["inicio"]?.comoTexto
            zonaHoraria = j["zona_horaria"]?.comoTexto
            brazo = j["brazo"]?.comoTexto
            let p = j["previo"]
            previo = Previo(cafeina: p?["cafeina"] == .bool(true), fumo: p?["fumo"] == .bool(true), comida: p?["comida"] == .bool(true), ejercicio: p?["ejercicio"] == .bool(true))
            reposoCumplido = Presion.booleano(j["reposo_cumplido"])
            temporizadorSalteado = Presion.booleano(j["temporizador_salteado"])
            dosisEstimulanteHora = j["dosis_estimulante_hora"]?.comoTexto
            entrenoEntreDosisYToma = Presion.booleano(j["entreno_entre_dosis_y_toma"])
            sintomas = Presion.lista(j["sintomas"]).compactMap(\.comoTexto)
            listaEspera = j["lista_espera"]?.comoTexto
            nota = j["nota"]?.comoTexto
            minutosDesdeUltima = j["minutos_desde_ultima"]?.comoNumero ?? 0
            tomas = Presion.lista(j["tomas"]).compactMap(Toma.init)
            fecha = j["fecha"]?.comoTexto
            orden = Presion.entero(j["orden"])
        }
    }

    public struct Aparato: Codable, Equatable, Sendable {
        public var id: String?
        /// "brazo", "muneca" o "reloj_anillo_otro".
        public var tipo: String?
        public var marca: String?
        public var modelo: String?
        public var modeloCodigo: String?
        public var manguitoMinCm: Double?
        public var manguitoMaxCm: Double?
        public var manguitoValidadoMinCm: Double?
        public var manguitoValidadoMaxCm: Double?
        /// "si", "no" o "sin_revisar".
        public var validado: String?

        public init(id: String? = nil, tipo: String?, marca: String? = nil, modelo: String? = nil, modeloCodigo: String? = nil, manguitoMinCm: Double? = nil,
                    manguitoMaxCm: Double? = nil, manguitoValidadoMinCm: Double? = nil, manguitoValidadoMaxCm: Double? = nil, validado: String? = nil) {
            self.id = id; self.tipo = tipo; self.marca = marca; self.modelo = modelo; self.modeloCodigo = modeloCodigo
            self.manguitoMinCm = manguitoMinCm; self.manguitoMaxCm = manguitoMaxCm
            self.manguitoValidadoMinCm = manguitoValidadoMinCm; self.manguitoValidadoMaxCm = manguitoValidadoMaxCm; self.validado = validado
        }

        public init?(_ j: JSONValue?) {
            guard let j, case .objeto = j else { return nil }
            id = j["id"]?.comoTexto
            tipo = j["tipo"]?.comoTexto
            marca = j["marca"]?.comoTexto
            modelo = j["modelo"]?.comoTexto
            modeloCodigo = j["modelo_codigo"]?.comoTexto
            manguitoMinCm = j["manguito_min_cm"]?.comoNumero
            manguitoMaxCm = j["manguito_max_cm"]?.comoNumero
            manguitoValidadoMinCm = j["manguito_validado_min_cm"]?.comoNumero
            manguitoValidadoMaxCm = j["manguito_validado_max_cm"]?.comoNumero
            validado = j["validado"]?.comoTexto
        }
    }

    public enum Validez: String, Equatable, Sendable { case ok, imposible, confirmar }
    public enum Nivel: String, Equatable, Sendable { case comun, alta, urgencia }

    public struct Metodo: Equatable, Sendable {
        /// "brazo", "muneca_provisoria", "muneca_habitual" o "no_sirve".
        public var metodo = "brazo"
        public var provisoria = false
        public var pedirBrazo = false
        public var pedirValidado = false
        public var admiteTomas = true
    }

    public struct PasoGuiado: Equatable, Sendable {
        public let esperaS: Int
        public let posicion: String
        public let minutosDePie: Int?
        public let brazo: String?
    }

    public struct Ortostatica: Equatable, Sendable {
        public let caidaSisMax: Int
        public let caidaDiaMax: Int
        public let subidaPulsoMax: Int
        public let hipotension: Bool
        public let hipertensionPosible: Bool
    }

    public struct Valor: Equatable, Sendable {
        public let sis: Int
        public let dia: Int
        public let pulso: Int
    }

    public enum Paso: String, Equatable, Sendable {
        case listo, repetir
        case repetirConLista = "repetir_con_lista"
        case guardiaPresion = "guardia_presion"
        case guardiaSintomas = "guardia_sintomas"
    }

    public struct Evaluacion: Equatable, Sendable {
        public let paso: Paso
        /// "ninguno", "guardia_sintomas", "guardia_presion", "repetir_pendiente", "lista_sintomas_espera", "quedate_sentado_5min",
        /// "sentate_agua", "quedate_sentado_ortostatica" o "toma_no_cuenta".
        public let texto: String
        public let cuenta: Bool
        public let motivoExclusion: String?
        public let valor: Valor?
        public let validaBajoEfecto: Bool
        public let urgencia: Bool
        public let ortostatica: Ortostatica?
        public let reglas: [String]
    }

    public struct EntradaSerie: Equatable, Sendable {
        public var tipo: String?
        public var tomasObjetivo: Int?
        public var fechaInicio: String?
        public var sesiones: [Sesion]
        public var soloUrgencias: Bool
        public var basalPulso: Int?

        public init(tipo: String? = nil, tomasObjetivo: Int? = nil, fechaInicio: String? = nil, sesiones: [Sesion] = [], soloUrgencias: Bool = false, basalPulso: Int? = nil) {
            self.tipo = tipo; self.tomasObjetivo = tomasObjetivo; self.fechaInicio = fechaInicio
            self.sesiones = sesiones; self.soloUrgencias = soloUrgencias; self.basalPulso = basalPulso
        }
    }

    public struct BajoEfecto: Equatable, Sendable {
        public let n: Int
        public let validas: Int
        public let promedio: Valor?
        public let tomasPulso100OMas: Int
        public let aviso: Bool
        public let alta: Bool
    }

    /// Lo calcula el teléfono igual que el servidor, pero el alumno solo ve `faltan` y `dias`.
    public struct ResumenSerie: Equatable, Sendable {
        public let tomasValidas: Int
        public let dias: [String]
        public let serieValida: Bool
        public let faltan: Int
        public let promedio: Valor?
        public let maximos: (sis: Int, dia: Int)?
        public let categoria: String?
        public let bajoEfecto: BajoEfecto
        public let reglas: [String]

        public static func == (a: ResumenSerie, b: ResumenSerie) -> Bool {
            a.tomasValidas == b.tomasValidas && a.dias == b.dias && a.serieValida == b.serieValida && a.faltan == b.faltan && a.promedio == b.promedio
                && a.maximos?.sis == b.maximos?.sis && a.maximos?.dia == b.maximos?.dia && a.categoria == b.categoria && a.bajoEfecto == b.bajoEfecto && a.reglas == b.reglas
        }
    }

    // MARK: Ayudas

    static func entero(_ j: JSONValue?) -> Int? {
        guard case .numero(let n)? = j, n.isFinite, n == n.rounded(.down), abs(n) < 1_000_000_000 else { return nil }
        return Int(n)
    }
    static func booleano(_ j: JSONValue?) -> Bool? { if case .bool(let b)? = j { b } else { nil } }
    static func lista(_ j: JSONValue?) -> [JSONValue] { if case .lista(let l)? = j { l } else { [] } }

    /// Promedio redondeado al entero, la mitad para arriba, con cuentas enteras (igual en todos los lenguajes).
    public static func media(_ xs: [Int]) -> Int {
        let n = xs.count
        guard n > 0 else { return 0 }
        let arriba = 2 * xs.reduce(0, +) + n
        let abajo = 2 * n
        // Como `Math.floor`: hacia abajo también con negativos.
        return arriba >= 0 ? arriba / abajo : -((-arriba + abajo - 1) / abajo)
    }

    // MARK: Reglas

    /// `.ok`, `.imposible` (no se acepta) o `.confirmar` (valor de urgencia o de alta: se pide confirmar el número).
    /// Los valores llegan como los tecleó el alumno: uno que falta o que no es entero es imposible.
    public static func validarToma(sis: Double?, dia: Double?, pulso: Double?) -> Validez {
        func e(_ x: Double?) -> Int? { guard let x, x.isFinite, x == x.rounded(.down), abs(x) < 1_000_000_000 else { return nil }; return Int(x) }
        guard let s = e(sis), let d = e(dia), let p = e(pulso) else { return .imposible }
        if s < Lim.sisMin || s > Lim.sisMax || d < Lim.diaMin || d > Lim.diaMax || p < Lim.pulMin || p > Lim.pulMax { return .imposible }
        if s - d < Lim.difMin { return .imposible }
        if s >= 160 || d >= 100 || p >= 120 || p <= 40 { return .confirmar }
        return .ok
    }

    public static func validarToma(sis: Int?, dia: Int?, pulso: Int?) -> Validez {
        validarToma(sis: sis.map(Double.init), dia: dia.map(Double.init), pulso: pulso.map(Double.init))
    }

    /// `.urgencia` (180 o 120), `.alta` (160 o 100) o `.comun`.
    public static func nivelToma(sis: Int, dia: Int) -> Nivel {
        if sis >= 180 || dia >= 120 { return .urgencia }
        if sis >= 160 || dia >= 100 { return .alta }
        return .comun
    }

    public static func deAlarma(_ codigos: [String]) -> Bool {
        codigos.contains { alarma.contains($0) || $0 == "desmayo_en_esfuerzo" }
    }

    /// El tramo de la barra de talles. Justo en el límite, el de arriba.
    public static func tramoBrazo(_ cm: Double?) -> String? {
        guard let cm, cm > 0 else { return nil }
        if cm < 22 { return "menos_22" }
        if cm < 32 { return "estandar" }
        if cm < 42 { return "grande" }
        if cm <= 52 { return "extra_grande" }
        return "mas_52"
    }

    /// true, false, o nil si el aparato no trae ningún rango. Manda el validado; si no hay, el impreso.
    public static func manguitoCalza(_ cm: Double?, _ a: Aparato?) -> Bool? {
        guard let a, let cm, cm > 0 else { return nil }
        var min = a.manguitoValidadoMinCm, max = a.manguitoValidadoMaxCm
        if min == nil || max == nil { min = a.manguitoMinCm; max = a.manguitoMaxCm }
        guard let min, let max else { return nil }
        if cm < min || cm > max { return false }
        // En el límite entre dos talles, el más grande: un manguito que termina en 32 o en 42 no calza justo ahí.
        if cm == max && (max == 32 || max == 42) { return false }
        return true
    }

    /// Qué lugar tiene el aparato con esa medida: brazo, muñeca provisoria o muñeca habitual (más de 52 cm).
    public static func metodo(_ cm: Double?, _ a: Aparato?) -> Metodo {
        var r = Metodo()
        guard let a else { return r }
        if a.tipo == "reloj_anillo_otro" { r.metodo = "no_sirve"; r.admiteTomas = false; r.pedirBrazo = true; return r }
        if a.tipo == "muneca" {
            if let cm, cm > 52 { r.metodo = "muneca_habitual"; r.pedirValidado = a.validado == "no" }
            else { r.metodo = "muneca_provisoria"; r.provisoria = true; r.pedirBrazo = true }
            return r
        }
        if a.validado == "no" { r.provisoria = true; r.pedirValidado = true }
        return r
    }

    /// Mañana, de 4 a 11.59 hora local.
    public static func momento(_ hora: Int) -> String { hora >= 4 && hora < 12 ? "manana" : "otro" }

    /// Los pasos guiados de una sesión: cada uno con su espera y la toma que pide.
    public static func pasos(_ tipo: String, _ variante: String? = nil) -> [PasoGuiado] {
        if tipo == "ortostatica" {
            let base = variante == "sentado_parado" ? "sentado" : "acostado"
            return [
                PasoGuiado(esperaS: 300, posicion: base, minutosDePie: nil, brazo: nil),
                PasoGuiado(esperaS: 60, posicion: "de_pie", minutosDePie: 1, brazo: nil),
                PasoGuiado(esperaS: 120, posicion: "de_pie", minutosDePie: 3, brazo: nil),
            ]
        }
        if tipo == "comparacion_brazos" {
            return ["izq", "der", "der", "izq"].enumerated().map { i, b in PasoGuiado(esperaS: i == 0 ? reposoS : 60, posicion: "sentado", minutosDePie: nil, brazo: b) }
        }
        return [PasoGuiado(esperaS: reposoS, posicion: "sentado", minutosDePie: nil, brazo: nil)]
    }

    public static func ortostatica(_ tomas: [Toma]) -> Ortostatica? {
        guard let base = tomas.first(where: { $0.posicion != "de_pie" }) else { return nil }
        let pie = tomas.filter { $0.posicion == "de_pie" }
        guard !pie.isEmpty else { return nil }
        let cs = pie.map { base.sis - $0.sis }.max() ?? 0
        let cd = pie.map { base.dia - $0.dia }.max() ?? 0
        let sp = pie.map { $0.pulso - base.pulso }.max() ?? 0
        let sube = pie.map { $0.sis - base.sis }.max() ?? 0
        return Ortostatica(caidaSisMax: cs, caidaDiaMax: cd, subidaPulsoMax: sp, hipotension: cs >= 20 || cd >= 10,
                           hipertensionPosible: sube >= 20 || pie.contains { $0.sis >= 140 && $0.sis > base.sis })
    }

    private static func tiene(_ xs: [String], _ ys: [String]) -> Bool { xs.contains { ys.contains($0) } }

    /// Una sesión: qué hace la app ahora (`paso` y `texto`), si la toma cuenta para el promedio y qué reglas se cumplen.
    /// La urgencia y la alta se evalúan siempre, también en las tomas que no cuentan. Solo con tomas sentado.
    public static func evaluarSesion(_ s: Sesion) -> Evaluacion {
        let tipo = s.tipo.isEmpty ? "estandar" : s.tipo
        let sint = s.sintomas
        // Orden estable, como el `sort` de JS: a igual `orden`, el que estaba antes.
        let S = s.tomas.enumerated().filter { $0.element.sentado }
            .sorted { $0.element.orden != $1.element.orden ? $0.element.orden < $1.element.orden : $0.offset < $1.offset }.map(\.element)
        var reglas: [String] = []
        let niv = S.map { nivelToma(sis: $0.sis, dia: $0.dia) }
        var conf180 = false, conf160 = false
        if S.count > 1 {
            for i in 1..<S.count {
                if niv[i] == .urgencia && niv[i - 1] == .urgencia { conf180 = true }
                if niv[i] != .comun && niv[i - 1] != .comun { conf160 = true }
            }
        }
        // La comparación de brazos y la ortostática son secuencias fijas: no piden repetición.
        let guiada = tipo == "ortostatica" || tipo == "comparacion_brazos"
        let ultimo: Nivel = niv.last ?? .comun
        let pendiente = !guiada && !S.isEmpty && ((ultimo == .urgencia && !conf180) || (ultimo == .alta && !conf160))
        let min = s.minutosDesdeUltima

        var paso = Paso.listo
        var texto = "ninguno"
        let hayAlarma = deAlarma(sint)
        let pulso120 = S.contains { $0.pulso >= 120 } && tiene(sint, ["palpitaciones", "dolor_pecho", "falta_aire", "mareo_al_pararse"])
        let pulso40 = S.contains { $0.pulso <= 40 } && tiene(sint, ["mareo_al_pararse", "desmayo", "desmayo_en_esfuerzo"])
        if hayAlarma { reglas.append(s.listaEspera == "si" ? "sintoma_alarma_en_espera" : "sintoma_alarma") }
        if tiene(sint, ["desmayo", "desmayo_en_esfuerzo"]) { reglas.append("desmayo") }
        if pulso120 { reglas.append("pulso_120_sintomas") }
        if pulso40 { reglas.append("pulso_40_mareo") }
        if conf180 { reglas.append("toma_180_120_confirmada") } else if conf160 { reglas.append("alta_toma_160_100") }
        if pendiente && ultimo == .urgencia && min >= Double(sinRepetirMin) { reglas.append("alta_180_120_sin_repetir") }
        if pendiente && ultimo == .alta && min >= Double(recordatorioMin) { reglas.append("repetir_pendiente") }

        let urgSintomas = hayAlarma || pulso120 || pulso40
        if urgSintomas { paso = .guardiaSintomas; texto = "guardia_sintomas" }
        else if conf180 { paso = .guardiaPresion; texto = "guardia_presion" }
        else if pendiente {
            paso = ultimo == .urgencia ? .repetirConLista : .repetir
            texto = min >= Double(recordatorioMin) ? "repetir_pendiente" : (ultimo == .urgencia ? "lista_sintomas_espera" : "quedate_sentado_5min")
        }

        let otrosMarcados = sint.filter { !deAlarma([$0]) }
        if S.contains(where: { $0.sis < 90 }) && !otrosMarcados.isEmpty {
            reglas.append("sistolica_menor_90_sintomas")
            if paso == .listo { texto = "sentate_agua" }
        }
        if sint.contains("mareo_al_pararse") {
            reglas.append("sintomas_al_pararse")
            if tipo == "ortostatica" && paso == .listo { texto = "quedate_sentado_ortostatica" }
        }
        if sint.contains("vomitos_diarrea") { reglas.append("sintoma_vomitos_diarrea") }
        if S.contains(where: { $0.pulso <= 40 }) && sint.isEmpty { reglas.append("pulso_40_sin_sintomas") }

        var orto: Ortostatica?
        if tipo == "ortostatica" {
            orto = ortostatica(s.tomas)
            if orto?.hipotension == true { reglas.append("ortostatica_positiva") }
        }

        let valor = S.isEmpty ? nil : Valor(sis: media(S.map(\.sis)), dia: media(S.map(\.dia)), pulso: media(S.map(\.pulso)))
        let incumplida = s.previo.alguno || s.reposoCumplido != true || s.temporizadorSalteado == true
        var cuenta = false
        var motivo: String?
        if s.tomas.isEmpty { motivo = "error" }
        else if tipo == "bajo_efecto" { motivo = "bajo_efecto" }
        else if tipo == "ortostatica" { motivo = "ortostatica" }
        else if tipo == "comparacion_brazos" { motivo = "comparacion_brazos" }
        else if tipo == "suelta" { motivo = "otra" }
        else if S.isEmpty { motivo = "error" }
        else if incumplida { motivo = "condicion_incumplida" }
        else if pendiente { motivo = "otra" }
        else { cuenta = true }
        if motivo == "condicion_incumplida" && paso == .listo && texto == "ninguno" { texto = "toma_no_cuenta" }
        let validaBajoEfecto = tipo == "bajo_efecto" && !S.isEmpty && !pendiente && s.reposoCumplido == true && s.temporizadorSalteado != true && s.entrenoEntreDosisYToma == false
        if tipo == "bajo_efecto" && !S.isEmpty && !validaBajoEfecto && paso == .listo && texto == "ninguno" { texto = "toma_no_cuenta" }
        // Una toma suelta de 135/85 o más no avisa: dispara una serie de 3 tomas.
        if tipo == "suelta", let valor, !pendiente, valor.sis >= 135 || valor.dia >= 85 { reglas.append("suelta_135_85") }

        return Evaluacion(paso: paso, texto: texto, cuenta: cuenta, motivoExclusion: motivo, valor: valor, validaBajoEfecto: validaBajoEfecto,
                          urgencia: urgSintomas || conf180, ortostatica: orto, reglas: reglas.sorted())
    }

    /// Para Mati y el servidor. NUNCA se le muestra al alumno.
    public static func categoria(sis: Int, dia: Int) -> String {
        if sis >= 150 || dia >= 95 { return "hipertension_casa_estadio_2" }
        if sis >= 135 || dia >= 85 { return "hipertension_casa" }
        if sis >= 130 || dia >= 80 { return "limitrofe" }
        if sis >= 120 { return "elevada" }
        return "optima"
    }

    private static func promedio(_ vs: [Valor]) -> Valor? {
        vs.isEmpty ? nil : Valor(sis: media(vs.map(\.sis)), dia: media(vs.map(\.dia)), pulso: media(vs.map(\.pulso)))
    }

    /// La serie: 3 tomas válidas, una por día, en 3 días distintos dentro de los 7 días del inicio.
    public static func resumenSerie(_ e: EntradaSerie) -> ResumenSerie {
        let objetivo = (e.tomasObjetivo ?? 0) != 0 ? e.tomasObjetivo! : 3
        let deBajoEfecto = e.tipo == "bajo_efecto"
        let inicio = (e.fechaInicio ?? "").isEmpty ? nil : e.fechaInicio
        let hasta = inicio.flatMap(DiaCalendario.numero).map { DiaCalendario.texto($0 + 6) }
        func enPlazo(_ f: String) -> Bool {
            guard let inicio, let hasta else { return true }
            return f >= inicio && f <= hasta
        }
        let ses = e.sesiones.enumerated().sorted { a, b in
            let fa = a.element.fecha ?? "", fb = b.element.fecha ?? ""
            if fa != fb { return fa < fb }
            let oa = a.element.orden ?? 0, ob = b.element.orden ?? 0
            return oa != ob ? oa < ob : a.offset < b.offset
        }.map(\.element)
        var reglas: [String] = []
        var dias: [String] = [], valores: [Valor] = [], maxS: [Int] = [], maxD: [Int] = []
        var beDias: [String] = [], beValores: [Valor] = []
        var beN = 0, irregulares = 0
        for s in ses {
            let ev = evaluarSesion(s)
            reglas.append(contentsOf: ev.reglas)
            irregulares += s.tomas.filter(\.latidoIrregular).count
            let fecha = s.fecha ?? ""
            if s.tipo == "bajo_efecto" {
                beN += 1
                if ev.validaBajoEfecto, let v = ev.valor, enPlazo(fecha), !beDias.contains(fecha), beDias.count < objetivo { beDias.append(fecha); beValores.append(v) }
            }
            if ev.cuenta, let v = ev.valor, enPlazo(fecha), !dias.contains(fecha), dias.count < objetivo {
                dias.append(fecha); valores.append(v)
                for t in s.tomas { maxS.append(t.sis); maxD.append(t.dia) }
            }
        }
        let prom = promedio(valores)
        let validas = deBajoEfecto ? beDias.count : dias.count
        let serieValida = validas >= objetivo

        if !deBajoEfecto, serieValida, !e.soloUrgencias, let prom, prom.sis >= 135 || prom.dia >= 85 { reglas.append("alta_promedio_135_85") }
        if valores.filter({ $0.pulso >= 100 }).count >= 2 { reglas.append("pulso_100_dos_tomas") }
        if !deBajoEfecto, serieValida, let basal = e.basalPulso, let prom, prom.pulso - basal >= 20 { reglas.append("pulso_20_sobre_basal") }
        if irregulares >= 2 { reglas.append("latido_irregular_2_tomas") }

        let bp = promedio(beValores)
        let beAlta = beValores.count >= 2 && ((bp?.sis ?? 0) >= 150 || (bp?.dia ?? 0) >= 95)
        let beAviso = beValores.count >= 2 && !beAlta && ((bp?.sis ?? 0) >= 135 || (bp?.dia ?? 0) >= 85)
        let bePulso = beValores.filter { $0.pulso >= 100 }.count
        if beAlta { reglas.append("alta_bajo_efecto_150_95") }
        if beAviso { reglas.append("bajo_efecto_135_85") }
        if bePulso >= 2 { reglas.append("pulso_100_bajo_efecto") }

        var unicas: [String] = []
        for r in reglas where !unicas.contains(r) { unicas.append(r) }
        return ResumenSerie(
            tomasValidas: validas, dias: deBajoEfecto ? beDias : dias, serieValida: serieValida, faltan: max(0, objetivo - validas),
            promedio: prom, maximos: maxS.isEmpty ? nil : (maxS.max() ?? 0, maxD.max() ?? 0),
            categoria: !deBajoEfecto && serieValida && !e.soloUrgencias ? prom.map { categoria(sis: $0.sis, dia: $0.dia) } : nil,
            bajoEfecto: BajoEfecto(n: beN, validas: beValores.count, promedio: beValores.count >= 2 ? bp : nil, tomasPulso100OMas: bePulso, aviso: beAviso, alta: beAlta),
            reglas: unicas.sorted())
    }
}
