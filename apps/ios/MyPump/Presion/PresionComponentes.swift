import SwiftUI
import MyPumpReglas

typealias TP = TextosPresion.T
typealias NP = TextosPresion.N

/// Tiempos de las esperas. En las pruebas de interfaz `-presionSegundos <n>` las acorta (solo Debug).
enum TiemposPresion {
    static func segundos(_ s: Int) -> TimeInterval {
        #if DEBUG
        let n = UserDefaults.standard.integer(forKey: "presionSegundos")
        if n > 0 { return TimeInterval(min(n, s)) }
        #endif
        return TimeInterval(s)
    }

    /// El reposo de antes de la toma. `-presionReposo <n>` lo fija aparte (solo Debug): una prueba puede acortar la espera de la
    /// repetición y dejar el reposo largo, para que «Ya esperé» no corra una carrera contra el temporizador.
    static func reposo() -> TimeInterval {
        #if DEBUG
        let n = UserDefaults.standard.integer(forKey: "presionReposo")
        if n > 0 { return TimeInterval(n) }
        #endif
        return segundos(Presion.reposoS)
    }
}

/// Los botones de Presión: ancho completo, 56 pt de alto como mínimo y siempre con texto, que nunca se corta (con letra grande
/// crece en alto). Uno principal por pantalla; los secundarios, debajo.
struct BotonPresion: ButtonStyle {
    var secundario = false
    var ocupado = false

    func makeBody(configuration: Configuration) -> some View {
        CuerpoBotonPresion(configuration: configuration, secundario: secundario, ocupado: ocupado)
    }
}

private struct CuerpoBotonPresion: View {
    let configuration: ButtonStyleConfiguration
    let secundario: Bool
    let ocupado: Bool
    @Environment(\.isEnabled) private var habilitado

    var body: some View {
        let activo = habilitado || ocupado
        let forma = RoundedRectangle(cornerRadius: 20, style: .continuous)
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(secundario ? (activo ? Color.primary : Color.secondary) : (activo ? Color.sobreMarca : Color.secondary))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(secundario || !activo ? Color.campo : Color.marca, in: forma)
            .overlay { if secundario { forma.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 1) } }
            .contentShape(forma)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Una pantalla de un paso: lo que hay que leer scrollea y los botones quedan siempre a la vista abajo (también por encima del
/// teclado), el principal primero.
struct PantallaPresion<Contenido: View, Pie: View>: View {
    /// Cada vez que cambia `vez`, se trae `ancla` (un `.id` del contenido) a la vista, pegada abajo: con el teclado abierto y
    /// letra grande, lo que quedaba tapado debajo del campo.
    var ancla: String? = nil
    var vez = 0
    @ViewBuilder var contenido: Contenido
    @ViewBuilder var pie: Pie
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        ScrollView {
            ScrollViewReader { lector in
                VStack(alignment: .leading, spacing: Espacio.m) {
                    contenido
                    // Con letra grande la barra de abajo se comería la pantalla: los del recorrido van al final, scrolleando.
                    if letra.isAccessibilitySize { BotonesFlujoPresion() }
                }
                    .padding(Espacio.m)
                    .anchoLectura()
                    .onChange(of: vez) { _, _ in
                        guard let ancla else { return }
                        // Que el teclado termine de subir: recién ahí se sabe cuánto lugar queda.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(400))
                            withAnimation { lector.scrollTo(ancla, anchor: .bottom) }
                        }
                    }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Espacio.xs) {
                pie
                if !letra.isAccessibilitySize { BotonesFlujoPresion() }
            }
                .padding(.horizontal, Espacio.m)
                .padding(.vertical, Espacio.xs)
                .anchoLectura()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}

/// Texto de lectura: nunca se corta, siempre a la izquierda.
struct TextoPresion: View {
    let texto: String
    var fuente: Font = .body
    var secundario = false

    init(_ texto: String, fuente: Font = .body, secundario: Bool = false) { self.texto = texto; self.fuente = fuente; self.secundario = secundario }

    var body: some View {
        Text(texto)
            .font(fuente)
            .foregroundStyle(secundario ? Color.secondary : Color.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TituloPresion: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto).font(.title3.weight(.bold)).foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Pasos numerados desde 1, con el número en un círculo como las referencias de los dibujos. Una idea por tarjeta, nunca un
/// bloque largo; `enTarjetas: false` es la leyenda de un dibujo, que ya va adentro de la tarjeta del dibujo.
struct PasosPresion: View {
    let pasos: [String]
    var enTarjetas = true
    var fuente: Font = .body
    @ScaledMetric(relativeTo: .subheadline) private var lado: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            ForEach(Array(pasos.enumerated()), id: \.offset) { i, p in
                if enTarjetas { fila(i, p).tarjeta(relleno: 12) } else { fila(i, p) }
            }
        }
    }

    private func fila(_ i: Int, _ p: String) -> some View {
        HStack(alignment: .top, spacing: Espacio.s) {
            Text("\(i + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(minWidth: lado, minHeight: lado)
                .background(Color.campo, in: .circle)
                .accessibilityHidden(true)
            TextoPresion(p, fuente: fuente)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(i + 1). \(p)")
    }
}

/// Sí y No: mismo tamaño y mismo color, ninguno marcado de entrada. El elegido se rellena igual sea cual sea.
struct SiNoPresion: View {
    let valor: Bool?
    let id: String
    let elegir: (Bool) -> Void

    var body: some View {
        HStack(spacing: Espacio.xs) {
            boton(TP.si, true)
            boton(TP.no, false)
        }
    }

    private func boton(_ texto: String, _ v: Bool) -> some View {
        let elegido = valor == v
        return Button { elegir(v) } label: {
            Text(texto)
                .font(.headline)
                .foregroundStyle(elegido ? Color(uiColor: .systemBackground) : Color.primary)
                .frame(minWidth: 76, minHeight: 56)
                .padding(.horizontal, Espacio.xs)
                .background(elegido ? Color.primary : Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(elegido ? .isSelected : [])
        .accessibilityIdentifier("\(id)-\(v ? "si" : "no")")
    }
}

/// Una pregunta con Sí y No. Con letra grande los botones bajan debajo del texto.
struct FilaSiNoPresion: View {
    let texto: String
    let valor: Bool?
    let id: String
    let elegir: (Bool) -> Void
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        let apilado = letra >= .xxLarge
        let disposicion = apilado ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs)) : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
        disposicion {
            TextoPresion(texto)
            SiNoPresion(valor: valor, id: id, elegir: elegir)
        }
        .padding(.vertical, Espacio.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

/// La lista de alarma con Sí y No en cada fila (la espera de una toma de 180/120 y su recordatorio).
struct ListaAlarmaPresion: View {
    let respuestas: [String: Bool]
    let responder: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            ForEach(Presion.alarma, id: \.self) { c in
                FilaSiNoPresion(texto: TextosPresion.sintomas[c] ?? c, valor: respuestas[c], id: "presion-alarma-\(c)") { responder(c, $0) }
                if c != Presion.alarma.last { Divider() }
            }
        }
    }
}

/// El temporizador. Guarda la hora de fin y no cuenta ticks: al volver del fondo muestra lo que falta de verdad.
/// El lector de pantalla lo anuncia al empezar y al terminar, no cada segundo.
struct TemporizadorPresion: View {
    let fin: Date
    let voz: String
    let alTerminar: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { t in
            let falta = max(0, Int(fin.timeIntervalSince(t.date).rounded(.up)))
            Text(String(format: "%d:%02d", falta / 60, falta % 60))
                .font(Archivo.fuente(56, relativoA: .largeTitle).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())
        }
        .accessibilityElement()
        .accessibilityLabel(voz)
        .accessibilityIdentifier("presion-temporizador")
        .task(id: fin) {
            if fin > Date() { AccessibilityNotification.Announcement(voz).post() }
            // Mira la hora cada medio segundo: si la app estuvo en el fondo, al volver ya sabe si terminó.
            while fin > Date() {
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            }
            alTerminar()
        }
    }
}

/// El texto de guardia, numerado. Lo decide el teléfono y se muestra aunque no haya red. Sin colores de riesgo.
struct GuardiaPresion: View {
    let porSintomas: Bool
    let alCerrar: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                PasosPresion(pasos: porSintomas ? TP.guardiaSintomas : TP.guardiaPresion, fuente: .headline)
                    .accessibilityIdentifier(porSintomas ? "presion-guardia-sintomas" : "presion-guardia-presion")
                Button(NP.cerrar, action: alCerrar).buttonStyle(BotonPresion()).accessibilityIdentifier("presion-guardia-cerrar")
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .onAppear {
            CentroAvisos.shared.cancelarRepetirPresion()
            AccessibilityNotification.Announcement((porSintomas ? TP.guardiaSintomas : TP.guardiaPresion)[0]).post()
        }
    }
}

/// Un dibujo del catálogo con sus referencias numeradas debajo.
struct LaminaPresion: View {
    let dibujo: String
    let alt: String
    let textos: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            DibujoPresion(dibujo, alt: alt).frame(maxWidth: 420).frame(maxWidth: .infinity)
            PasosPresion(pasos: textos, enTarjetas: false)
        }
        .tarjeta()
    }
}

/// Un campo con su rótulo arriba.
struct CampoPresion: View {
    let rotulo: String
    @Binding var texto: String
    var teclado: UIKeyboardType = .default
    var mayusculas = false
    var ayuda: String?
    /// Los números que el alumno copia del aparato o del centímetro: bien grandes (34 pt, y crecen con la letra del sistema).
    var grande = false
    let id: String

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xxs) {
            Text(rotulo).font(grande ? .headline : .subheadline.weight(.semibold)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            TextField("", text: $texto)
                .keyboardType(teclado)
                .textInputAutocapitalization(mayusculas ? .characters : teclado == .default ? .words : .never)
                .autocorrectionDisabled()
                .font(grande ? .largeTitle.weight(.bold).monospacedDigit() : .title3.monospacedDigit())
                .multilineTextAlignment(grande ? .center : .leading)
                .padding(.horizontal, Espacio.s)
                .frame(minHeight: grande ? 68 : 56)
                .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                .accessibilityLabel(rotulo)
                .accessibilityIdentifier(id)
            if let ayuda { Text(ayuda).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

enum NumeroPresion {
    /// «35,5» o «35.5».
    static func decimal(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let d = Double(t), d.isFinite else { return nil }
        return d
    }

    static func texto(_ d: Double?) -> String {
        guard let d else { return "" }
        return d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d).replacingOccurrences(of: ".", with: ",")
    }

    /// El día «AAAA-MM-DD» como «lun 9/11».
    static func dia(_ fecha: String) -> String {
        guard let n = DiaCalendario.numero(fecha) else { return fecha }
        let d = Date(timeIntervalSince1970: Double(n) * 86_400)
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE d/M"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    static func diaCorto(_ fecha: String) -> String {
        let p = fecha.prefix(10).split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? "\(p[2])/\(p[1])" : fecha
    }
}

/// «Marcar un síntoma» y «Cerrar» del recorrido de una toma: botones secundarios de ancho completo, con texto, debajo del
/// principal (nunca ítems chicos de la barra de arriba). Los pone `TomaPresionView` por el entorno; nil donde no van.
private struct MarcarSintomaFlujoPresion: EnvironmentKey { static let defaultValue: (@MainActor () -> Void)? = nil }
private struct CerrarFlujoPresion: EnvironmentKey { static let defaultValue: (@MainActor () -> Void)? = nil }

extension EnvironmentValues {
    var marcarSintomaFlujoPresion: (@MainActor () -> Void)? {
        get { self[MarcarSintomaFlujoPresion.self] }
        set { self[MarcarSintomaFlujoPresion.self] = newValue }
    }
    var cerrarFlujoPresion: (@MainActor () -> Void)? {
        get { self[CerrarFlujoPresion.self] }
        set { self[CerrarFlujoPresion.self] = newValue }
    }
}

extension View {
    /// Sin los botones del recorrido (en las hojas que se abren encima y mientras el teclado está arriba).
    func sinBotonesFlujoPresion() -> some View { environment(\.marcarSintomaFlujoPresion, nil).environment(\.cerrarFlujoPresion, nil) }
}

struct BotonesFlujoPresion: View {
    @Environment(\.marcarSintomaFlujoPresion) private var marcarSintoma
    @Environment(\.cerrarFlujoPresion) private var cerrar

    var body: some View {
        if let marcarSintoma {
            Button(TP.marcarSintoma) { marcarSintoma() }.buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-flujo-sintoma")
        }
        if let cerrar {
            Button(NP.cerrar) { cerrar() }.buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-flujo-cerrar")
        }
    }
}
