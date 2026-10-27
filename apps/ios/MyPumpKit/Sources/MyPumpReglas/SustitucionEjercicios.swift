import Foundation
import MyPumpModelos

// Sustitución de ejercicios: port exacto de `window.MyPump.exerciseSwap` (public/js/app.js:396-747) y de
// `getEffectiveEx` y `exGetSubs` (cliente.html:2040 y 2554). Lo verifican los vectores de
// scripts/nativa/vectores-ejercicios.mjs, que corren esas mismas funciones de la web.
//
// La regla (de la web, no negociable): un sustituto vale solo con el MISMO `patron_movimiento` y el MISMO
// `primary_muscle` que el original. Primero los de otro equipo ("la máquina está ocupada"), después alfabético en
// castellano, sin repetir nombre+equipo, máximo 30. Si el ejercicio no se resuelve en el catálogo o la fila no tiene
// patrón, no hay sustitutos. Calentamiento y cardio nunca tienen.
//
// Lo que la web hace raro y se iguala a propósito (se arregla allá, no acá):
// - `_toEs` junta variantes en el mismo nombre ("Curl de bíceps con barra" son varias filas): de cada nombre+equipo
//   queda la primera, y el resto no se ofrece.
// - Si el ejercicio del plan no trae imágenes ni slug y ya se sustituyó, `exGetSubs` resuelve por la foto del
//   SUSTITUTO (`ex._origImages || ex.images`), no por el original.
// - `_norm` no conoce los acentos descompuestos: "o" + U+0301 queda "o n".

/// Funciones puras de la sustitución: normalizar, resolver un nombre por reglas, traducir y ordenar.
public enum SustitucionEjercicios {
    /// `_norm`: minúsculas, sin las tildes que lista, sin paréntesis, sin el sufijo `-d1-0` del id, solo alfanumérico y
    /// espacios colapsados. Es la del RPC `mypump_match_ejercicio_por_nombre`; NO es `claveEjercicio` (esa usa NFD).
    public static func normalizar(_ s: String?) -> String {
        var n = (s ?? "").lowercased()
        for (re, letra) in vocales { n = re.reemplazarTodo(n, por: letra) }
        n = parentesis.reemplazarTodo(n, por: " ")
        n = sufijoId.reemplazarTodo(n, por: " ")
        n = noAlfanumerico.reemplazarTodo(n, por: " ")
        n = espacios.reemplazarTodo(n, por: " ")
        return n.trimmingCharacters(in: soloEspacio)   // ya no queda más que [a-z0-9 ]: el trim de JS es este
    }

    /// `_resolveByRules`: el primer slug cuya regla matchea el nombre normalizado (específico → general).
    public static func slugPorReglas(_ nombre: String?) -> String? {
        let n = normalizar(nombre)
        guard !n.isEmpty else { return nil }
        return reglas.first { $0.0.prueba(n) }?.1
    }

    /// `_toEs`: BASE (gesto) + MODIFICADORES + EQUIPO. Sin base devuelve el `name_en` tal cual (mejor inglés que algo roto).
    public static func castellano(_ e: EntradaCatalogoEjercicio) -> String {
        let en = (verdadero(e.nameEn) ?? "").lowercased()
        if en.isEmpty { return verdadero(e.slugEn).map { guionBajo.reemplazarTodo($0, por: " ") } ?? "" }
        guard let base = bases.first(where: { $0.0.prueba(en) })?.1 else { return e.nameEn ?? "" }
        let eq = equipos.first { $0.0.prueba(en) }?.1 ?? ""
        let mods = modificadores.filter { $0.0.prueba(en) }.map(\.1)
        var out = base
        if !mods.isEmpty { out += " " + mods.joined(separator: " ") }
        // Sin redundancia: "Cruce de poleas" ya dice polea.
        let nucleo = nucleosEquipo.first { $0.0 == eq }?.1 ?? eq.lowercased()
        if !eq.isEmpty, !incluyeJS(out.lowercased(), nucleo) { out += " " + eq }
        return out
    }

    /// El músculo del catálogo en castellano, para el título de «Otros ejercicios de …». nil si no se conoce.
    public static func musculo(_ m: String?) -> String? {
        switch (m ?? "").lowercased() {
        case "quadriceps": "cuádriceps"
        case "shoulders": "hombros"
        case "abdominals": "abdominales"
        case "chest": "pecho"
        case "hamstrings": "isquiotibiales"
        case "triceps": "tríceps"
        case "biceps": "bíceps"
        case "lats": "dorsales"
        case "middle back": "espalda media"
        case "calves": "pantorrillas"
        case "lower back": "zona lumbar"
        case "forearms": "antebrazos"
        case "glutes": "glúteos"
        case "traps": "trapecios"
        case "adductors": "aductores"
        case "neck": "cuello"
        case "abductors": "abductores"
        default: nil
        }
    }

    /// `_equipLabel`: "Smith" en el nombre es Multipower (free-exercise-db lo etiqueta 'machine' o 'barbell').
    public static func etiquetaEquipo(_ e: EntradaCatalogoEjercicio) -> String {
        if smith.prueba(e.nameEn ?? "") { return "Multipower" }
        if let eq = e.equipment, let etiqueta = etiquetas.first(where: { igualJS($0.0, eq) })?.1 { return etiqueta }
        return verdadero(e.equipment) ?? "Otro"
    }

    /// `a.localeCompare(b, 'es')`, el orden alfabético de los sustitutos. Foundation usa el mismo ICU que el `Intl` de
    /// la web: se verificó contra node con todos los nombres del catálogo (vectores `orden`).
    public static func compararNombres(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [], range: nil, locale: espanol)
    }

    // ── Tablas: copiadas literal de app.js (el orden es la prioridad) ─────────

    static let reglas = tabla([
        (#"cinta.*trote|trote suave|cinta.*suave"#, "Jogging_Treadmill"),
        (#"cinta|caminadora|treadmill"#, "Running_Treadmill"),
        (#"rollout|ab wheel|rueda abdom"#, "Ab_Roller"),
        (#"crunch.*maquina|crunch en m"#, "Ab_Crunch_Machine"),
        (#"plancha|plank"#, "Plank"),
        (#"remo.*maquina palanca|palanca|leverage.*row|iso.?row"#, "Leverage_Iso_Row"),
        (#"remo.*polea.*sentad|seated cable row|remo en polea sentad"#, "Seated_Cable_Rows"),
        (#"remo.*menton|upright row"#, "Upright_Cable_Row"),
        (#"remo.*polea|cable row"#, "Seated_Cable_Rows"),
        (#"remo.*mancuern"#, "Bent_Over_Two-Dumbbell_Row"),
        (#"remo.*barra|remo con barra"#, "Bent_Over_Barbell_Row"),
        (#"jalon.*neutr|jalon.*v.?bar|agarre neutro"#, "V-Bar_Pulldown"),
        (#"jalon.*pecho|jalon.*prono|pulldown|jalon"#, "Wide-Grip_Lat_Pulldown"),
        (#"pajaro|reverse.*fly|reverse pec deck|deltoides posterior"#, "Reverse_Machine_Flyes"),
        (#"face pull"#, "Face_Pull"),
        (#"elevac.*later.*polea|elevac.*later.*cable|elevac.*later.*una mano"#, "Cable_Seated_Lateral_Raise"),
        (#"elevac.*later"#, "Side_Lateral_Raise"),
        (#"extension.*overhead.*cuerda|overhead.*cuerda|rope.*overhead"#, "Cable_Rope_Overhead_Triceps_Extension"),
        (#"extension.*overhead.*mancuern|overhead.*mancuern"#, "Seated_Triceps_Press"),
        (#"extension.*polea alta|extension.*tricep.*polea|polea alta.*tricep|extension.*barra.*tricep|extension de tricep"#, "Triceps_Pushdown"),
        (#"push.?down"#, "Triceps_Pushdown"),
        (#"patada.*tricep|tricep.*kickback"#, "Tricep_Dumbbell_Kickback"),
        (#"press cerrad.*smith|press cerrad.*multipower"#, "Smith_Machine_Close-Grip_Bench_Press"),
        (#"press cerrad|close.?grip.*bench"#, "Close-Grip_Barbell_Bench_Press"),
        (#"press.*inclin.*maquin"#, "Leverage_Incline_Chest_Press"),
        (#"press.*inclin.*mancuern"#, "Incline_Dumbbell_Press"),
        (#"press.*inclin.*smith|press.*inclin.*multipower"#, "Smith_Machine_Incline_Bench_Press"),
        (#"press.*inclin"#, "Barbell_Incline_Bench_Press_-_Medium_Grip"),
        (#"press.*plano.*maquin"#, "Leverage_Chest_Press"),
        (#"press.*plano.*mancuern"#, "Dumbbell_Bench_Press"),
        (#"press.*plano.*smith|press.*plano.*multipower"#, "Smith_Machine_Bench_Press"),
        (#"press.*plano|press banca"#, "Barbell_Bench_Press_-_Medium_Grip"),
        (#"press.*militar.*maquin|press hombros?.*maquin|press.*hombro.*maquin"#, "Machine_Shoulder_Military_Press"),
        (#"press.*mancuern.*sentad|press hombros?.*mancuern|press.*hombro.*mancuern"#, "Seated_Dumbbell_Press"),
        (#"press.*hombro|press.*militar"#, "Seated_Dumbbell_Press"),
        (#"apertur.*inclin"#, "Incline_Dumbbell_Flyes"),
        (#"cruce.*polea.*bajo|low cable cross"#, "Low_Cable_Crossover"),
        (#"apertur.*polea|cruce.*polea|crossover"#, "Cable_Crossover"),
        (#"apertur|pec deck|butterfly"#, "Butterfly"),
        (#"fondos|dips"#, "Dips_-_Chest_Version"),
        (#"curl.*predicad.*maquin|preacher.*machine"#, "Machine_Preacher_Curls"),
        (#"curl.*predicad"#, "Preacher_Curl"),
        (#"curl.*martillo|hammer"#, "Hammer_Curls"),
        (#"curl.*spider|spider"#, "Spider_Curl"),
        (#"curl.*inclin"#, "Incline_Dumbbell_Curl"),
        (#"curl.*invers|reverse.*curl|curl inverso"#, "Reverse_Cable_Curl"),
        (#"curl.*polea.*una mano|curl.*cable.*una mano|curl en cable a una mano"#, "Standing_One-Arm_Cable_Curl"),
        (#"curl.*polea|curl.*cable"#, "Standing_Biceps_Cable_Curl"),
        (#"curl.*mancuern.*sentad"#, "Seated_Dumbbell_Curl"),
        (#"curl.*mancuern"#, "Dumbbell_Bicep_Curl"),
        (#"curl.*barra"#, "Barbell_Curl"),
        (#"curl femoral.*sentad|leg curl.*sentad|femoral sentad"#, "Seated_Leg_Curl"),
        (#"curl femoral|leg curl|hamstring curl|femoral"#, "Lying_Leg_Curls"),
        (#"extension.*cuad|leg extension|cuadricep"#, "Leg_Extensions"),
        (#"prensa|leg press"#, "Leg_Press"),
        (#"hack squat|sentadilla hack|sentadilla jaca"#, "Hack_Squat"),
        (#"sentadilla.*bulgar|split squat|bulgara"#, "Split_Squat_with_Dumbbells"),
        (#"sentadilla.*smith|smith.*squat|sentadilla.*multipower"#, "Smith_Machine_Squat"),
        (#"sentadilla|squat"#, "Barbell_Squat"),
        (#"zancada|lunge|estocada"#, "Dumbbell_Lunges"),
        (#"peso muerto.*rumano|romanian|rdl.*mancuern"#, "Stiff-Legged_Dumbbell_Deadlift"),
        (#"\brdl\b|peso muerto.*rigid|stiff.?leg"#, "Romanian_Deadlift"),
        (#"peso muerto|deadlift"#, "Barbell_Deadlift"),
        (#"hip thrust|empuje de cadera"#, "Barbell_Hip_Thrust"),
        (#"puente.*gluteo|glute bridge"#, "Barbell_Glute_Bridge"),
        (#"patada.*gluteo|patada.*tras|kickback.*glute"#, "One-Legged_Cable_Kickback"),
        (#"abductor|abduccion"#, "Thigh_Abductor"),
        (#"aductor|aduccion"#, "Thigh_Adductor"),
        (#"soleo|talon sentad|seated calf"#, "Seated_Calf_Raise"),
        (#"talon.*multipower|talon.*smith|smith.*calf"#, "Smith_Machine_Calf_Raise"),
        (#"talon|gemelo|\bcalf\b|gastrocnem|pantorrilla"#, "Standing_Calf_Raises"),
        (#"encogim|shrug|trapecio"#, "Dumbbell_Shrug"),
        (#"elevac.*frontal|front raise"#, "Front_Cable_Raise"),
        (#"pullover.*mancuern"#, "Straight-Arm_Dumbbell_Pullover"),
        (#"pullover"#, "Straight-Arm_Pulldown"),
        (#"skull|press frances|french|rompecraneo"#, "EZ-Bar_Skullcrusher"),
        (#"dominad|pull.?up|pullup"#, "Pullups"),
        (#"flexion|push.?up|lagartij"#, "Pushups"),
    ])

    static let bases = tabla([
        (#"romanian deadlift"#, "Peso muerto rumano"),
        (#"stiff.?leg.*deadlift|stiff legged"#, "Peso muerto piernas rígidas"),
        (#"sumo deadlift"#, "Peso muerto sumo"),
        (#"trap bar deadlift"#, "Peso muerto con trap bar"),
        (#"deadlift"#, "Peso muerto"),
        (#"good morning"#, "Buenos días"),
        (#"leg press"#, "Prensa de piernas"),
        (#"hack squat"#, "Hack squat"),
        (#"split squat|bulgarian"#, "Sentadilla búlgara"),
        (#"front squat"#, "Sentadilla frontal"),
        (#"squat"#, "Sentadilla"),
        (#"walking lunge"#, "Zancadas caminando"),
        (#"lunge|lunges"#, "Zancadas"),
        (#"step-?up"#, "Subida al cajón"),
        (#"leg extension"#, "Extensión de cuádriceps"),
        (#"lying leg curl"#, "Curl femoral acostado"),
        (#"seated leg curl"#, "Curl femoral sentado"),
        (#"leg curl|glute ham|nordic"#, "Curl femoral"),
        (#"hip thrust"#, "Hip thrust"),
        (#"glute bridge"#, "Puente de glúteos"),
        // Desvío a propósito de la web (20-oct): ahí la patada de tríceps también sale «Patada de glúteo». Allá no se ve
        // (no tiene variantes); en la app sí, entre los otros ejercicios de tríceps, y es el nombre que se registra.
        (#"tricep.*kickback|kickback.*tricep"#, "Patada de tríceps"),
        (#"(glute|cable) kickback|kickback"#, "Patada de glúteo"),
        (#"thigh abductor|hip abduction|abductor"#, "Abductores"),
        (#"thigh adductor|hip adduction|adductor"#, "Aductores"),
        (#"seated calf raise|calf raise.*seated"#, "Elevación de talones sentado"),
        (#"calf raise|calf press|calves"#, "Elevación de talones"),
        (#"bench press"#, "Press de banca"),
        (#"chest press"#, "Press de pecho"),
        (#"shoulder press|military press"#, "Press militar"),
        (#"overhead press|push press"#, "Press sobre la cabeza"),
        (#"arnold press"#, "Press Arnold"),
        (#"floor press"#, "Press en el piso"),
        (#"\bpress\b"#, "Press"),
        (#"lat pulldown|pulldown|pull-down|pull down"#, "Jalón al pecho"),
        (#"chin-?up"#, "Dominadas supinas"),
        (#"pull-?up|pullup"#, "Dominadas"),
        (#"straight-?arm|pullover"#, "Pullover"),
        (#"upright row"#, "Remo al mentón"),
        (#"t-bar row"#, "Remo en T"),
        (#"\brows?\b"#, "Remo"),
        (#"face pull"#, "Face pull"),
        (#"rear delt|reverse fly|reverse machine fly|rear lateral"#, "Pájaros"),
        (#"lateral raise|side lateral"#, "Elevaciones laterales"),
        (#"front raise"#, "Elevaciones frontales"),
        (#"shrug"#, "Encogimientos"),
        (#"pec deck|butterfly"#, "Pec deck"),
        (#"crossover|cross over|cable cross"#, "Cruce de poleas"),
        (#"fly|flye"#, "Aperturas"),
        (#"hammer curl"#, "Curl martillo"),
        (#"preacher curl"#, "Curl predicador"),
        (#"spider curl"#, "Curl araña"),
        (#"concentration curl"#, "Curl concentrado"),
        (#"reverse curl"#, "Curl invertido"),
        (#"wrist curl"#, "Curl de muñeca"),
        (#"bicep.*curl|curl"#, "Curl de bíceps"),
        (#"pushdown|push-down|push down"#, "Extensión de tríceps en polea"),
        (#"skull|french press|nose breaker"#, "Press francés"),
        (#"overhead.*(triceps|extension)|triceps.*overhead"#, "Extensión de tríceps sobre la cabeza"),
        (#"triceps? (extension|press)|extension.*triceps"#, "Extensión de tríceps"),
        (#"dips?\b"#, "Fondos"),
        (#"push-?up|pushup"#, "Flexiones"),
        (#"rollout|roller|ab wheel"#, "Rollout"),
        (#"plank"#, "Plancha"),
        (#"hanging.*raise|leg raise|knee raise"#, "Elevación de piernas"),
        (#"russian twist|oblique|woodchop|wood chop"#, "Oblicuos"),
        (#"crunch|sit-?up"#, "Crunch"),
        (#"hyperextension|back extension"#, "Hiperextensiones"),
    ])

    static let equipos = tabla([
        (#"\bsmith\b"#, "en multipower"),
        (#"leverage|lever |machine"#, "en máquina"),
        (#"cable|pulley"#, "en polea"),
        (#"e-?z[ -]?(curl )?bar"#, "con barra Z"),
        (#"dumbbell|\bdb\b"#, "con mancuernas"),
        (#"barbell"#, "con barra"),
        (#"kettlebell"#, "con kettlebell"),
        (#"\bband\b|bands"#, "con banda"),
        (#"exercise ball|ball "#, "con pelota"),
    ])

    static let modificadores = tabla([
        (#"incline"#, "inclinado"),
        (#"decline"#, "declinado"),
        (#"close-?grip"#, "agarre cerrado"),
        (#"wide-?grip"#, "agarre ancho"),
        (#"one-?arm|single-?arm|one arm"#, "a una mano"),
    ])

    /// `eqCore` de `_toEs`: lo que tiene que aparecer en el nombre para que el equipo sea redundante.
    static let nucleosEquipo: [(String, String)] = [
        ("en polea", "polea"), ("en máquina", "máquina"), ("en multipower", "multipower"), ("con barra", "barra"),
        ("con mancuernas", "mancuern"), ("con kettlebell", "kettlebell"), ("con banda", "banda"), ("con barra Z", "barra z"),
        ("con pelota", "pelota"),
    ]

    /// `EQUIP_LABEL` (free-exercise-db → castellano).
    static let etiquetas: [(String, String)] = [
        ("machine", "Máquina"), ("dumbbell", "Mancuernas"), ("barbell", "Barra"), ("cable", "Polea"),
        ("body only", "Peso corporal"), ("kettlebells", "Kettlebell"), ("bands", "Banda"), ("e-z curl bar", "Barra Z"),
        ("exercise ball", "Pelota"), ("medicine ball", "Balón medicinal"), ("other", "Otro"),
    ]

    static let vocales = tabla([
        (#"[áàäâã]"#, "a"), (#"[éèëê]"#, "e"), (#"[íìïî]"#, "i"), (#"[óòöôõ]"#, "o"), (#"[úùüû]"#, "u"), (#"ñ"#, "n"),
    ])
    static let parentesis = regexJS(#"\(.*?\)"#)
    static let sufijoId = regexJS(#"-d\d+-\d+"#)
    static let noAlfanumerico = regexJS(#"[^a-z0-9 ]+"#)
    static let espacios = regexJS(#"\s+"#)
    static let guionBajo = regexJS(#"_"#)
    /// `/\bsmith\b/i`. Sin flag `u`, la `i` de JS solo junta mayúsculas y minúsculas ASCII; ICU con CASE_INSENSITIVE
    /// también tomaría "ſ" por "s". Por eso las clases explícitas.
    static let smith = regexJS(#"\b[Ss][Mm][Ii][Tt][Hh]\b"#)
    /// `/exercise-images\/([^/]+)\//`: hace falta el grupo, así que va directo a NSRegularExpression (misma traducción).
    static let imagenURL = try! NSRegularExpression(pattern: JSRegex.traducir(#"exercise-images\/([^/]+)\/"#))
    static let soloEspacio = CharacterSet(charactersIn: " ")
    static let espanol = Locale(identifier: "es")

    /// `…/exercise-images/<SLUG>/<0|1>.jpg` → SLUG (`exec` de JS: la primera aparición, aunque no esté en el catálogo).
    static func slugDeURL(_ url: String) -> String? {
        guard let m = imagenURL.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
              let r = Range(m.range(at: 1), in: url) else { return nil }
        return String(url[r])
    }
}

/// Lo que mira `_resolve` de un ejercicio: el que viene en el plan, o el `orig` que arma `exGetSubs`.
public struct ReferenciaEjercicio: Sendable, Equatable {
    public var nombre: String?
    public var imagenes: Imagenes?
    public var catalogoSlug: String?
    /// `_matched_slug` suelto. El `orig` de `exGetSubs` no lo trae.
    public var matchedSlug: String?

    public init(nombre: String? = nil, imagenes: Imagenes? = nil, catalogoSlug: String? = nil, matchedSlug: String? = nil) {
        self.nombre = nombre; self.imagenes = imagenes; self.catalogoSlug = catalogoSlug; self.matchedSlug = matchedSlug
    }

    /// El ejercicio del plan tal cual (lo que recibe `_resolve` desde `getEffectiveEx`).
    public init(_ ex: Ejercicio) {
        self.init(nombre: ex.nombre, imagenes: ex.imagenes, catalogoSlug: ex.catalogoSlug, matchedSlug: ex.matchedSlug)
    }
}

/// Un sustituto válido, con los campos del objeto que arma `findSubstitutes`.
public struct SustitutoEjercicio: Sendable, Equatable {
    /// `slug` (el `slug_en` de la fila).
    public let slug: String?
    /// `name`: el nombre en castellano (`_toEs`). Es el que se muestra y el que se registra al sustituir.
    public let nombre: String
    /// `name_en`
    public let nombreIngles: String?
    /// `equipo`: la etiqueta ("Máquina", "Multipower"…).
    public let equipo: String
    /// `equipmentRaw`: el `equipment` del catálogo.
    public let equipoCrudo: String?
    /// `primary_muscle`
    public let musculo: String?
    /// `patron_movimiento`
    public let patron: String?
    /// `images`: las del catálogo, con "" como null. Sin `_matched_slug`.
    public let imagenes: Imagenes
    /// `_sameEquip`: mismo equipo que el original (van al final).
    public let mismoEquipo: Bool
}

extension SustitutoEjercicio {
    /// Lo que lo identifica aunque la lista cambie: el slug del catálogo; sin slug, el nombre con el equipo. La hoja de
    /// "Sustituir" elige por esto y no por la posición: si mientras está abierta llega el catálogo del servidor, la lista
    /// cambia de orden y la misma posición es otro ejercicio (revisión del 15-oct, hallazgo 13).
    public var clave: String {
        if let slug, !slug.isEmpty { return slug }
        return "\(nombre)|\(equipoCrudo ?? equipo)"
    }

    init(_ e: EntradaCatalogoEjercicio, mismoEquipo: Bool) {
        self.init(slug: e.slugEn, nombre: SustitucionEjercicios.castellano(e), nombreIngles: e.nameEn,
                  equipo: SustitucionEjercicios.etiquetaEquipo(e), equipoCrudo: e.equipment, musculo: e.primaryMuscle,
                  patron: e.patronMovimiento,
                  imagenes: Imagenes(eccentric: verdadero(e.imageEccentric), concentric: verdadero(e.imageConcentric)),
                  mismoEquipo: mismoEquipo)
    }
}

/// La sustitución aplicada en un lugar (`STATE.exerciseSwaps[ex.id]`): el `current` que guarda `confirmExSwap`, y si
/// quedó fijada para las próximas semanas.
public struct SustitucionAplicada: Sendable, Equatable {
    public var slug: String?
    public var nombre: String
    /// `equipment` crudo del catálogo.
    public var equipo: String?
    public var imagenes: Imagenes?
    public var fijado: Bool

    public init(slug: String?, nombre: String, equipo: String? = nil, imagenes: Imagenes? = nil, fijado: Bool) {
        self.slug = slug; self.nombre = nombre; self.equipo = equipo; self.imagenes = imagenes; self.fijado = fijado
    }

    /// Lo que guarda `confirmExSwap` al elegir un sustituto.
    public init(_ s: SustitutoEjercicio, fijado: Bool) {
        self.init(slug: s.slug, nombre: s.nombre, equipo: s.equipoCrudo, imagenes: s.imagenes, fijado: fijado)
    }
}

/// `getEffectiveEx`: el ejercicio que se muestra. Nombre e imágenes son los del sustituto si hay, o las fotos del
/// catálogo si el plan no las trae; id, tipo, descanso y progresión son siempre los del lugar. Guarda referencias al
/// original (`_orig*`) para ofrecer sustitutos sobre él y para volver.
public struct EjercicioEfectivo: Sendable, Equatable {
    public var ejercicio: Ejercicio
    /// `_isSwapped`
    public var sustituido: Bool
    /// `_swapSlug`
    public var slugSustituto: String?
    /// `_swapFijado`
    public var fijado: Bool
    /// `_origNombre`
    public var nombreOriginal: String?
    /// `_origImages`
    public var imagenesOriginales: Imagenes?
    /// `_origSlug`
    public var slugOriginal: String?

    public init(ejercicio: Ejercicio, sustituido: Bool = false, slugSustituto: String? = nil, fijado: Bool = false,
                nombreOriginal: String? = nil, imagenesOriginales: Imagenes? = nil, slugOriginal: String? = nil) {
        self.ejercicio = ejercicio; self.sustituido = sustituido; self.slugSustituto = slugSustituto; self.fijado = fijado
        self.nombreOriginal = nombreOriginal; self.imagenesOriginales = imagenesOriginales; self.slugOriginal = slugOriginal
    }
}

/// El catálogo en memoria (`window.MYPUMP_EJERCICIO_DB`).
///
/// El ORDEN de las filas es parte de la entrada, como en la web: de cada nombre+equipo repetido queda la primera fila,
/// los empates de nombre quedan en el orden del catálogo, y un alias genérico ("abdominales", "core") se resuelve a la
/// primera fila que lo tenga. La web usa el orden en que responde el servidor (el GET no tiene ORDER BY); el archivo
/// empaquetado va por `slug_en`, y con ese orden cambian unas 200 de las 873 listas (la foto o el slug del que queda, o
/// el orden entre iguales) y "Abdominales" pasa de no tener sustitutos a tener. El catálogo bajado se usa tal cual
/// llega.
public struct CatalogoEjercicios: Sendable {
    public let entradas: [EntradaCatalogoEjercicio]
    /// `byId`: si un slug se repite, gana la última fila.
    private let indice: [ClaveJS: Int]
    /// El músculo de cada patrón de movimiento: el de la mayoría de sus filas (en un empate, el que aparece primero).
    /// Para «otros del mismo músculo»: una fila mal clasificada (encogimientos como espalda media) no se ofrece, porque
    /// su patrón es de otro músculo.
    private let musculoDelPatron: [ClaveJS: String]
    /// El músculo y el patrón de cada fila, y el patrón que nombra, por la clave del historial (`ClaveEjercicio`) de su
    /// nombre en castellano, que es lo que de verdad comparten dos ejercicios con nombres parecidos. Para no ofrecer entre
    /// «otros del mismo músculo» el nombre de otro ejercicio (ver `nombreDeOtroEjercicio`). Se arma una vez, la primera vez
    /// que hace falta: traducir las 873 filas son unos 20 ms, y el catálogo empaquetado se arma al abrir la app.
    private let usosDelNombre: UnaVez<[String: UsosDeUnNombre]>

    public init(_ entradas: [EntradaCatalogoEjercicio]) {
        self.entradas = entradas
        var indice: [ClaveJS: Int] = [:]
        for (i, e) in entradas.enumerated() { if let slug = e.slugEn { indice[ClaveJS(slug)] = i } }
        self.indice = indice
        var cuentas: [ClaveJS: [(musculo: String, filas: Int)]] = [:]
        for e in entradas {
            guard let p = verdadero(e.patronMovimiento), let m = verdadero(e.primaryMuscle) else { continue }
            var lista = cuentas[ClaveJS(p)] ?? []
            if let i = lista.firstIndex(where: { igualJS($0.musculo, m) }) { lista[i].filas += 1 } else { lista.append((m, 1)) }
            cuentas[ClaveJS(p)] = lista
        }
        musculoDelPatron = cuentas.mapValues { lista in
            lista.reduce(lista[0]) { mejor, x in x.filas > mejor.filas ? x : mejor }.musculo
        }
        usosDelNombre = UnaVez {
            var filas: [String: [(musculo: String?, patron: String?)]] = [:]
            for e in entradas {
                filas[ClaveEjercicio.de(SustitucionEjercicios.castellano(e)), default: []].append((verdadero(e.primaryMuscle), verdadero(e.patronMovimiento)))
            }
            return filas.mapValues(UsosDeUnNombre.init)
        }
    }

    /// El nombre del candidato es, en el catálogo, el de OTRO ejercicio de otro músculo, y compartiría con él el historial
    /// (que va por la clave del nombre). Cuenta si hay filas con ese nombre de otro músculo y otro patrón, y el candidato no
    /// es del patrón que tiene la mayoría de las filas con ese nombre: el movimiento que el nombre nombra (con un empate, no
    /// nombra a ninguno). Revisión del 21-oct: salen los remos del deltoide posterior de los otros de hombros («Remo con
    /// barra», «Remo en polea»: los nombres son de los remos de espalda) y «Curl de bíceps · Otro» (un curl invertido con
    /// disco). Se quedan los que son el mismo ejercicio cargado también en otro músculo (los fondos, la sentadilla búlgara,
    /// las zancadas) o que chocan con la traducción equivocada de otro que la app no ofrece (el cruce de poleas).
    func nombreDeOtroEjercicio(_ s: SustitutoEjercicio) -> Bool {
        guard let usos = usosDelNombre.valor[ClaveEjercicio.de(s.nombre)] else { return false }
        let deOtroMusculo = usos.filas.contains { !igualJS($0.musculo, verdadero(s.musculo)) && !igualJS($0.patron, verdadero(s.patron)) }
        return deOtroMusculo && !igualJS(usos.dominante, verdadero(s.patron))
    }

    /// El músculo de un patrón (el de la mayoría de sus filas).
    public func musculo(dePatron p: String?) -> String? { verdadero(p).flatMap { musculoDelPatron[ClaveJS($0)] } }

    /// El JSON del GET (o del archivo empaquetado), en el orden en que viene.
    public init(json: Data) throws {
        self.init(try JSONDecoder().decode([EntradaCatalogoEjercicio].self, from: json))
    }

    public func entrada(slug: String) -> EntradaCatalogoEjercicio? {
        indice[ClaveJS(slug)].map { entradas[$0] }
    }

    /// `_resolve`: slug explícito → slug de la URL de la imagen → reglas por nombre → nombre normalizado o alias exactos.
    /// Sin trigram (matchea "pullover" con "crunch").
    public func resolver(_ r: ReferenciaEjercicio) -> EntradaCatalogoEjercicio? {
        guard !entradas.isEmpty else { return nil }
        // 1) Slug explícito. Si el primero que hay no está en el catálogo, NO se prueba el siguiente.
        if let slug = verdadero(r.catalogoSlug) ?? verdadero(r.imagenes?.matchedSlug) ?? verdadero(r.matchedSlug),
           let e = entrada(slug: slug) { return e }
        // 2) Slug embebido en la URL de la imagen.
        let url = verdadero(r.imagenes?.eccentric) ?? verdadero(r.imagenes?.concentric) ?? ""
        if let slug = SustitucionEjercicios.slugDeURL(url), let e = entrada(slug: slug) { return e }
        // 3) Reglas castellano → slug (gesto exacto).
        let nombre = verdadero(r.nombre) ?? ""
        if let slug = SustitucionEjercicios.slugPorReglas(nombre), let e = entrada(slug: slug) { return e }
        // 4) Nombre normalizado o alias, exactos y en el orden del catálogo.
        let nn = SustitucionEjercicios.normalizar(nombre)
        guard !nn.isEmpty else { return nil }
        return entradas.first { igualJS($0.nameNormalized, nn) }
            ?? entradas.first { e in (e.aliasesEs ?? []).contains { igualJS($0, nn) } }
    }

    public func resolver(_ ex: Ejercicio) -> EntradaCatalogoEjercicio? { resolver(ReferenciaEjercicio(ex)) }

    /// `findSubstitutes`: mismo patrón y mismo músculo, otro equipo primero, alfabético, sin repetir nombre+equipo, 30.
    public func sustitutos(_ r: ReferenciaEjercicio) -> [SustitutoEjercicio] {
        guard let original = resolver(r), let patron = verdadero(original.patronMovimiento) else { return [] }
        let candidatos = entradas
            .filter {
                igualJS($0.patronMovimiento, patron) && igualJS($0.primaryMuscle, original.primaryMuscle)
                    && !igualJS($0.slugEn, original.slugEn)
            }
            .map { SustitutoEjercicio($0, mismoEquipo: igualJS($0.equipment, original.equipment)) }
        // El sort de JS es estable: lo que empata queda en el orden del catálogo.
        let ordenados = candidatos.enumerated().sorted { a, b in
            if a.element.mismoEquipo != b.element.mismoEquipo { return !a.element.mismoEquipo }
            switch SustitucionEjercicios.compararNombres(a.element.nombre, b.element.nombre) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }.map(\.element)
        var vistos = Set<[ClaveJS]>()
        return Array(ordenados.filter { vistos.insert([ClaveJS($0.nombre), ClaveJS($0.equipo)]).inserted }.prefix(30))
    }

    /// Los otros ejercicios del mismo músculo, con otro movimiento (Mati, 20-oct: con la polea ocupada, a una extensión en
    /// polea no le quedaba nada; Eric quería fondos). Es de la app, no de la web: van en su propia sección, debajo de las
    /// variantes del mismo movimiento y sin repetirlas. Solo filas con su patrón (las sin clasificar no se ofrecen) y con
    /// un patrón de ESE músculo (el de la mayoría de sus filas: así los encogimientos mal cargados como espalda media no
    /// aparecen para un remo), sin nombres que no se tradujeron ni el «Press» suelto, ni el nombre de otro ejercicio
    /// (`nombreDeOtroEjercicio`), otro equipo primero, alfabético, sin repetir nombre+equipo, 30.
    public func otrosDelMismoMusculo(_ r: ReferenciaEjercicio) -> [SustitutoEjercicio] {
        guard let original = resolver(r), let patron = verdadero(original.patronMovimiento),
              verdadero(original.primaryMuscle) != nil else { return [] }
        let deArriba = Set(sustitutos(r).map { [ClaveJS($0.nombre), ClaveJS($0.equipo)] })
        let propio = [ClaveJS(SustitucionEjercicios.castellano(original)), ClaveJS(SustitucionEjercicios.etiquetaEquipo(original))]
        let candidatos = entradas
            .filter {
                igualJS($0.primaryMuscle, original.primaryMuscle) && verdadero($0.patronMovimiento) != nil
                    && !igualJS($0.patronMovimiento, patron) && !igualJS($0.slugEn, original.slugEn)
                    && igualJS(musculo(dePatron: $0.patronMovimiento), original.primaryMuscle)
            }
            .map { SustitutoEjercicio($0, mismoEquipo: igualJS($0.equipment, original.equipment)) }
            .filter { s in
                let n = s.nombre
                return !n.isEmpty && n != "Press" && !igualJS(n, s.nombreIngles) && !nombreDeOtroEjercicio(s)
            }
        let ordenados = candidatos.enumerated().sorted { a, b in
            if a.element.mismoEquipo != b.element.mismoEquipo { return !a.element.mismoEquipo }
            switch SustitucionEjercicios.compararNombres(a.element.nombre, b.element.nombre) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.offset < b.offset
            }
        }.map(\.element)
        var vistos = deArriba
        vistos.insert(propio)
        return Array(ordenados.filter { vistos.insert([ClaveJS($0.nombre), ClaveJS($0.equipo)]).inserted }.prefix(30))
    }

    /// Los otros del mismo músculo para la tarjeta, resueltos sobre el original (como `sustitutos(de:)`).
    public func otrosDelMismoMusculo(de ef: EjercicioEfectivo) -> [SustitutoEjercicio] {
        if ef.ejercicio.tipo == "calentamiento" || ef.ejercicio.tipo == "cardio" { return [] }
        return otrosDelMismoMusculo(referenciaDeLasListas(ef))
    }

    /// `getEffectiveEx(ex)` con `STATE.exerciseSwaps[ex.id]` = `sustitucion`.
    public func efectivo(_ ex: Ejercicio, sustitucion sw: SustitucionAplicada?) -> EjercicioEfectivo {
        var ef = ex
        if let sw {
            ef.nombre = sw.nombre
            ef.imagenes = sw.imagenes
            // Desvío a propósito de la web (27-oct): el equipo del sustituto decide el kg cuando el nombre traducido lo
            // pierde («Rope Crunch» sale «Crunch»). Ver `ReglasEjercicio.esSinPeso`.
            ef.equipo = sw.equipo
        } else if verdadero(ex.imagenes?.eccentric) == nil, let e = resolver(ex), verdadero(e.imageEccentric) != nil {
            // El plan no trae foto (ejercicio creado en NutriPlan sin match): sale del catálogo, sin republicar.
            ef.imagenes = Imagenes(eccentric: e.imageEccentric, concentric: e.imageConcentric, matchedSlug: e.slugEn)
        }
        return EjercicioEfectivo(
            ejercicio: ef, sustituido: sw != nil, slugSustituto: sw?.slug, fijado: sw?.fijado ?? false,
            nombreOriginal: ex.nombre, imagenesOriginales: ex.imagenes,
            slugOriginal: verdadero(ex.imagenes?.matchedSlug) ?? verdadero(ex.catalogoSlug) ?? verdadero(ef.imagenes?.matchedSlug))
    }

    /// `exGetSubs`: los sustitutos que ofrece la tarjeta, resueltos sobre el original. Ni calentamiento ni cardio.
    public func sustitutos(de ef: EjercicioEfectivo) -> [SustitutoEjercicio] {
        if ef.ejercicio.tipo == "calentamiento" || ef.ejercicio.tipo == "cardio" { return [] }
        return sustitutos(referenciaDeLasListas(ef))
    }

    /// Sobre qué se arman las dos listas de «Sustituir»: el `orig` de `exGetSubs` (`referencia(de:)`) y, con el lugar
    /// sustituido, el del original tal como estaba antes de sustituir (su nombre, su slug y sus fotos o las del catálogo),
    /// así al reabrir «Cambiar» las listas son las mismas. Desvío a propósito de la web (revisión del 21-oct): con un plan
    /// sin fotos (la demo, que es la que mira Apple, o la cuenta test-nativa-ios) `_origImages || images` caía en la foto
    /// del sustituto, y después de pasar la extensión en polea a fondos las listas eran las de los fondos.
    public func referenciaDeLasListas(_ ef: EjercicioEfectivo) -> ReferenciaEjercicio {
        guard ef.sustituido else { return Self.referencia(de: ef) }
        var plan = ef.ejercicio   // el del plan con el nombre y las fotos del sustituto: se le devuelven los suyos
        plan.nombre = ef.nombreOriginal ?? ""
        plan.imagenes = ef.imagenesOriginales
        return Self.referencia(de: efectivo(plan, sustitucion: nil))
    }

    /// El `orig` de `exGetSubs`: `{nombre: _origNombre || nombre, images: _origImages || images,
    /// catalogo_slug: _origSlug || images?._matched_slug || null}`.
    public static func referencia(de ef: EjercicioEfectivo) -> ReferenciaEjercicio {
        ReferenciaEjercicio(nombre: verdadero(ef.nombreOriginal) ?? ef.ejercicio.nombre,
                            imagenes: ef.imagenesOriginales ?? ef.ejercicio.imagenes,
                            catalogoSlug: verdadero(ef.slugOriginal) ?? verdadero(ef.ejercicio.imagenes?.matchedSlug))
    }
}

// ── Semántica de JS ───────────────────────────────────────────────────

/// Un texto en un `||` de JS: null y "" son falsos.
private func verdadero(_ s: String?) -> String? {
    guard let s, !s.isEmpty else { return nil }
    return s
}

/// `a === b` entre textos: unidad UTF-16 por unidad. El `==` de Swift compara por equivalencia canónica.
private func igualJS(_ a: String?, _ b: String?) -> Bool {
    switch (a, b) {
    case (nil, nil): return true
    case let (a?, b?): return a.utf16.elementsEqual(b.utf16)
    default: return false
    }
}

/// `texto.includes(buscado)`, por unidades UTF-16.
private func incluyeJS(_ texto: String, _ buscado: String) -> Bool {
    let t = Array(texto.utf16), b = Array(buscado.utf16)
    guard !b.isEmpty else { return true }
    guard b.count <= t.count else { return false }
    return (0...(t.count - b.count)).contains { t[$0..<($0 + b.count)].elementsEqual(b) }
}

/// Las filas del catálogo con un mismo nombre (su clave del historial): el músculo y el patrón de cada una, y el patrón de
/// la mayoría de las que tienen patrón, que es el movimiento que el nombre nombra (nil sin patrones o con un empate).
private struct UsosDeUnNombre: Sendable {
    let filas: [(musculo: String?, patron: String?)]
    let dominante: String?

    init(_ filas: [(musculo: String?, patron: String?)]) {
        self.filas = filas
        var cuentas: [String: Int] = [:]
        for f in filas { if let p = f.patron { cuentas[p, default: 0] += 1 } }
        let maximo = cuentas.values.max()
        let primeros = cuentas.filter { $0.value == maximo }
        dominante = primeros.count == 1 ? primeros.first?.key : nil
    }
}

/// Un valor que se calcula una sola vez, la primera vez que se pide (y se comparte entre las copias del catálogo).
private final class UnaVez<Valor: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var calculado: Valor?
    private let calcular: @Sendable () -> Valor

    init(_ calcular: @escaping @Sendable () -> Valor) { self.calcular = calcular }

    var valor: Valor {
        lock.withLock {
            if let v = calculado { return v }
            let v = calcular()
            calculado = v
            return v
        }
    }
}

/// Clave de diccionario con la igualdad de JS: `byId[slug]` y el dedup de nombre+equipo.
private struct ClaveJS: Hashable {
    let unidades: [UInt16]
    init(_ s: String) { unidades = Array(s.utf16) }
}

private func regexJS(_ patron: String) -> JSRegex { JSRegex(patron) }

/// Una lista `[[/regex/, valor], …]` de app.js, en el mismo orden.
private func tabla(_ pares: [(String, String)]) -> [(JSRegex, String)] { pares.map { (regexJS($0.0), $0.1) } }

