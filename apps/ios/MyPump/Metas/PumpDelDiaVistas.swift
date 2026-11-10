import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// De dónde sale el «Pump del día» en pantalla: con cuenta, del modelo (palanca `metas_pasos`, la meta de la dieta y los
/// pasos de Salud); con `-metas muestra`, de una semana de muestra que no es de nadie (bocetos, capturas y el video).
@MainActor @Observable
final class MetasUI {
    static let shared = MetasUI()

    /// Los pasos de hoy de la muestra (`-pasos`); `-pasosLuego` los cambia a los 3 s.
    var pasosMuestra: Double = DemoUI.pasosHoy ?? 7420
    /// En la muestra, las fechas celebradas viven en memoria: cada arranque vuelve a festejar (el video).
    private var registroMuestra = PumpDelDia.Registro()
    /// La fecha del último aviso local (para no mandar dos el mismo día mientras la app sigue en segundo plano).
    private var avisadoEl: String?

    var muestra: Bool { DemoUI.metas != nil }

    func estado(_ m: ModeloApp, hoy: String = FechaLocal.hoy()) -> (vista: PumpDelDia.Vista, conectado: Bool)? {
        guard let modo = DemoUI.metas else { return m.pumpDelDia(hoy: hoy) }
        guard let n = DiaCalendario.numero(hoy) else { return nil }
        // Tres días seguidos con la meta, uno abajo y uno más atrás con la meta.
        var p: [String: Double] = [:]
        for (i, v) in [11_200, 8_600, 10_400, 12_100, 10_050].enumerated() { p[DiaCalendario.texto(n - 5 + i)] = Double(v) }
        if modo != "sinsalud" { p[hoy] = pasosMuestra }
        guard let v = PumpDelDia.vista(pasosPorDia: modo == "sinsalud" ? [:] : p, meta: 10_000, hoy: hoy) else { return nil }
        return (v, modo != "sinsalud")
    }

    /// El ritmo de peso del plan (con la muestra, bajar medio kilo por semana).
    func ritmo(_ m: ModeloApp) -> Double? { muestra ? -0.5 : m.metas?.ritmoKgSemana }

    func debeCelebrar(_ v: PumpDelDia.Vista, _ m: ModeloApp, hoy: String) -> Bool {
        PumpDelDia.debeCelebrar(muestra ? registroMuestra : m.registroMetas, hoy: hoy, pasosHoy: v.pasosHoy, meta: v.meta)
    }

    func marcar(_ m: ModeloApp, hoy: String) {
        if muestra { registroMuestra = PumpDelDia.marcar(registroMuestra, hoy: hoy) } else { m.marcarPumpCelebrado(hoy: hoy) }
    }

    func yaAvisado(_ hoy: String) -> Bool { avisadoEl == hoy }
    func anotarAviso(_ hoy: String) { avisadoEl = hoy }
}

// MARK: - La tarjeta

/// El «Pump del día» en una tarjeta: el torso que se llena, los pasos de hoy en Archivo, lo que falta y la semana en
/// torsitos (llenos los días con la meta). En Entreno lleva a Salud; en Salud suma la meta contra el promedio.
struct PumpDelDiaTarjeta: View {
    let vista: PumpDelDia.Vista
    let conectado: Bool
    /// En Salud: con la línea del promedio y sin el toque que lleva a Salud.
    var enSalud = false
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    @ScaledMetric(relativeTo: .title) private var ladoTorso: CGFloat = 76

    var body: some View {
        Group {
            if enSalud || !conectado {
                contenido
            } else {
                Button { navegacion?.irASalud(.recuperacion) } label: { contenido }
                    .buttonStyle(FilaPresionable())
                    .accessibilityHint("Abre Salud")
            }
        }
        .accessibilityIdentifier("pump-del-dia")
    }

    private var contenido: some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            let apilada = tamañoLetra.isAccessibilitySize
            let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                      : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.m))
            disposicion {
                TorsoLleno(fraccion: conectado ? vista.fraccion : 0, lado: min(ladoTorso, 120))
                if conectado { numeros } else { sinSalud }
                if !apilada { Spacer(minLength: 0) }
            }
            if conectado {
                SemanaPump(semana: vista.semana, fraccionHoy: vista.fraccion)
                if enSalud {
                    Text(PumpDelDia.lineaSalud(meta: vista.meta, promedio: vista.promedio7))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tarjeta()
        .accessibilityElement(children: conectado ? .ignore : .contain)
        .accessibilityLabel(conectado ? textoAccesible : "")
    }

    private var numeros: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(PumpDelDia.nombre).textoCeja()
                Spacer(minLength: Espacio.xs)
                if let r = PumpDelDia.racha(vista.racha) {
                    Label(r, systemImage: "flame.fill")
                        .labelStyle(EtiquetaCompacta())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.alerta)
                        .lineLimit(1)
                        .accessibilityIdentifier("pump-racha")
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) { cifra; deMeta }
                VStack(alignment: .leading, spacing: 0) { cifra; deMeta }
            }
            Text(PumpDelDia.estado(vista))
                .font(.subheadline.weight(vista.cumplido ? .semibold : .regular))
                .foregroundStyle(vista.cumplido ? Color.marcaTexto : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cifra: some View {
        Text(PumpDelDia.numeroPasos(vista.pasosHoy))
            .font(.numeroGrande)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(vista.pasosHoy)))
            .animation(.snappy, value: vista.pasosHoy)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var deMeta: some View {
        Text(PumpDelDia.deMeta(vista)).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
    }

    private var sinSalud: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PumpDelDia.nombre).textoCeja()
            Text(PumpDelDia.sinSalud(meta: vista.meta))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(PumpDelDia.conectar)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !enSalud {
                Button("Conectar Salud") { navegacion?.irASalud(.recuperacion) }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    .accessibilityIdentifier("pump-conectar")
            }
        }
    }

    private var textoAccesible: String {
        let pasados = vista.semana.filter { $0.estado != .futuro }
        let hechos = pasados.filter { $0.estado == .cumplido }.count
        return PumpDelDia.accesible(vista) + " Esta semana, \(hechos) de \(pasados.count) días con la meta."
    }
}

/// La semana de lunes a domingo en torsitos: lleno el día con la meta, a medio llenar hoy, vacío el que no llegó.
struct SemanaPump: View {
    let semana: [PumpDelDia.Dia]
    /// Lo de hoy, para el torsito a medio llenar.
    var fraccionHoy: Double = 0
    @ScaledMetric(relativeTo: .caption) private var lado: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(semana.enumerated()), id: \.offset) { _, d in
                VStack(spacing: 4) {
                    TorsoLleno(fraccion: d.estado == .cumplido ? 1 : (d.estado == .hoy ? fraccionHoy : 0), lado: min(lado, 40),
                               vivo: false, detalle: false)
                        .opacity(d.estado == .futuro ? 0.35 : (d.estado == .sinDato ? 0.6 : 1))
                    Text(d.inicial)
                        .font(.caption2.weight(esHoy(d) ? .bold : .medium))
                        .foregroundStyle(esHoy(d) ? Color.marcaTexto : Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func esHoy(_ d: PumpDelDia.Dia) -> Bool { d.fecha == FechaLocal.hoy() }
}

/// Lo que va en Entreno (y en Salud): la tarjeta solo con la palanca, una meta de pasos y una cuenta.
struct PumpDelDiaSiCorresponde: View {
    var enSalud = false
    @State private var app = Proveedor.modelo
    @State private var metas = MetasUI.shared

    var body: some View {
        if let e = metas.estado(app), (!app.conMuestras || metas.muestra) {
            PumpDelDiaTarjeta(vista: e.vista, conectado: e.conectado, enSalud: enSalud)
        }
    }
}

// MARK: - Ritmo de peso

/// El ritmo que buscamos, debajo de la media de 7 días. Sin juicios: la tendencia tal cual y, si va al ritmo, se dice.
struct RitmoPesoLinea: View {
    let serie: [PesoCorporal.Punto]
    @State private var app = Proveedor.modelo
    @State private var metas = MetasUI.shared

    var body: some View {
        if let ritmo = metas.ritmo(app), !app.conMuestras || metas.muestra {
            let r = RitmoPeso.resumen(ritmo: ritmo, serie: serie, hoy: FechaLocal.hoy())
            VStack(alignment: .leading, spacing: 4) {
                Label(r.meta, systemImage: "scope")
                    .labelStyle(EtiquetaCompacta())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                if let t = r.tendencia {
                    Text(t).font(.subheadline).foregroundStyle(.secondary)
                }
                if r.enRitmo {
                    Text(RitmoPeso.enRitmoTexto).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.marcaSuave, in: RoundedRectangle(cornerRadius: Radio.control, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("ritmo-peso")
        }
    }
}

// MARK: - La celebración

/// «Pump lleno»: el torso termina de llenarse, late como un bombeo (con hápticos), saltan chispas verdes y doradas y
/// aparece el número del día con la racha. Con «Reducir movimiento», todo quieto y un solo háptico.
struct CelebracionPump: View {
    let vista: PumpDelDia.Vista
    let cerrar: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var nivel = 0.8
    @State private var bombeo = false
    @State private var textos = false
    @State private var chispas: Date?
    @ScaledMetric(relativeTo: .largeTitle) private var tituloTamaño: CGFloat = 46

    var body: some View {
        ZStack {
            // Fondo de la app casi opaco, con el verde de la marca subiendo desde el torso: no un gris de vidrio.
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            Color.fondo.opacity(0.82).ignoresSafeArea()
            RadialGradient(colors: [Color.marcaVivo.opacity(bombeo ? 0.22 : 0), Color.marcaVivo.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.3), startRadius: 20, endRadius: 520)
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: Espacio.l) {
                    Spacer(minLength: Espacio.xl)
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Color.marcaVivo.opacity(0.45), Color.marcaVivo.opacity(0)],
                                                 center: .center, startRadius: 40, endRadius: 150))
                            .frame(width: 300, height: 300)
                        Circle()
                            .strokeBorder(Color.marcaVivo.opacity(bombeo ? 0 : 0.6), lineWidth: 3)
                            .frame(width: 230, height: 230)
                            .scaleEffect(bombeo ? 1.35 : 0.7)
                            .scaleEffect(bombeo ? 1.08 : 0.5)
                            .opacity(bombeo ? 1 : 0)
                        TorsoLleno(fraccion: nivel, lado: 200)
                            .scaleEffect(bombeo || reducir ? 1 : 0.9)
                    }
                    .overlay {
                        if let chispas, !reducir {
                            Chispas(inicio: chispas).frame(width: 640, height: 760).allowsHitTesting(false)
                        }
                    }
                    VStack(spacing: Espacio.xs) {
                        Text(PumpDelDia.lleno)
                            .font(Archivo.fuente(tituloTamaño, relativoA: .largeTitle))
                            .foregroundStyle(Color.marcaTexto)
                            .accessibilityAddTraits(.isHeader)
                        Text(PumpDelDia.celebracion(meta: vista.meta))
                            .font(.title3.weight(.semibold))
                        if let r = PumpDelDia.celebracionRacha(vista.racha) {
                            Label(r, systemImage: "flame.fill")
                                .labelStyle(EtiquetaCompacta())
                                .font(.headline)
                                .foregroundStyle(Color.alerta)
                                .padding(.top, 2)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(textos ? 1 : 0)
                    .offset(y: textos || reducir ? 0 : 18)
                    SemanaPump(semana: vista.semana, fraccionHoy: vista.fraccion)
                        .padding(.horizontal, Espacio.s)
                        .opacity(textos ? 1 : 0)
                    Spacer(minLength: Espacio.l)
                    Button(PumpDelDia.seguir, action: cerrar)
                        .buttonStyle(BotonMarca())
                        .opacity(textos ? 1 : 0)
                        .accessibilityIdentifier("pump-seguir")
                }
                .padding(.horizontal, Espacio.l)
                .padding(.bottom, Espacio.l)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("pump-celebracion")
        .task { await secuencia() }
    }

    /// Llenarse, latir (pump, pump) y mostrar el día. Cada háptico va con lo que se ve.
    private func secuencia() async {
        let anuncio = [PumpDelDia.lleno, PumpDelDia.celebracion(meta: vista.meta), PumpDelDia.celebracionRacha(vista.racha)]
            .compactMap { $0 }.joined(separator: ". ")
        if reducir {
            nivel = 1; bombeo = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.25)) { textos = true }
            AccessibilityNotification.Announcement(anuncio).post()
            return
        }
        let suave = UIImpactFeedbackGenerator(style: .soft)
        let fuerte = UIImpactFeedbackGenerator(style: .rigid)
        suave.prepare(); fuerte.prepare()
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeIn(duration: 0.75)) { nivel = 1 }
        for i in 0..<3 {
            suave.impactOccurred(intensity: 0.4 + 0.2 * CGFloat(i))
            try? await Task.sleep(for: .milliseconds(220))
        }
        // El bombeo: dos golpes, como el pump de una serie.
        fuerte.impactOccurred(intensity: 1)
        withAnimation(.spring(duration: 0.45, bounce: 0.55)) { bombeo = true }
        chispas = .now
        try? await Task.sleep(for: .milliseconds(140))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) { textos = true }
        AccessibilityNotification.Announcement(anuncio).post()
    }
}

/// Las chispas: placas y destellos que salen del torso y caen con gravedad, en los verdes de la marca y un poco de oro.
/// Dibujadas en un Canvas: livianas y sin vistas por partícula. Duran 1,8 s.
private struct Chispas: View {
    let inicio: Date

    private struct Chispa {
        let angulo: Double, velocidad: Double, tamaño: Double, giro: Double, color: Int, placa: Bool
    }

    private static let chispas: [Chispa] = {
        // Pseudoaleatorio fijo: el mismo dibujo en cada celebración (y en las capturas).
        var x: UInt64 = 0x9E3779B97F4A7C15
        func azar() -> Double { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return Double(x % 10_000) / 10_000 }
        return (0..<44).map { _ in
            Chispa(angulo: -.pi / 2 + (azar() - 0.5) * .pi * 1.9, velocidad: 320 + azar() * 360, tamaño: 6 + azar() * 8,
                   giro: (azar() - 0.5) * 14, color: Int(azar() * 4), placa: azar() > 0.45)
        }
    }()

    var body: some View {
        TimelineView(.animation) { t in
            Canvas { ctx, size in
                let s = t.date.timeIntervalSince(inicio)
                guard s < 1.8 else { return }
                let centro = CGPoint(x: size.width / 2, y: size.height / 2)
                let colores: [Color] = [.marcaVivo, .marca, .oro, .white]
                for c in Self.chispas {
                    let dx = cos(c.angulo) * c.velocidad * s
                    let dy = sin(c.angulo) * c.velocidad * s + 0.5 * 900 * s * s
                    let p = CGPoint(x: centro.x + dx, y: centro.y + dy)
                    var g = ctx
                    g.opacity = max(0, 1 - max(0, s - 0.9) / 0.9)
                    g.translateBy(x: p.x, y: p.y)
                    g.rotate(by: .radians(c.giro * s))
                    let r = CGRect(x: -c.tamaño / 2, y: -c.tamaño / (c.placa ? 2 : 6), width: c.tamaño, height: c.placa ? c.tamaño : c.tamaño / 3)
                    g.fill(Path(roundedRect: r, cornerRadius: c.placa ? c.tamaño * 0.3 : 1), with: .color(colores[c.color]))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Quién decide cuándo celebrar

/// En la raíz: mira el «Pump del día» cuando cambian los pasos, el día o la fase de la app. Una vez por día y por cuenta.
/// - App al frente (y sin la hoja de Salud encima): la celebración.
/// - App en segundo plano cuando llegan los pasos (una sincronización que termina después de salir): un aviso local, solo
///   si los avisos ya estaban permitidos (nunca se piden por esto). La celebración queda para cuando vuelva.
struct CelebracionPumpRaiz: ViewModifier {
    @State private var app = Proveedor.modelo
    @State private var metas = MetasUI.shared
    @State private var mostrando: PumpDelDia.Vista?
    @State private var esperando = false
    @Environment(\.scenePhase) private var fase
    @Environment(Navegacion.self) private var navegacion: Navegacion?

    private var clave: String {
        guard let e = metas.estado(app) else { return "" }
        return "\(FechaLocal.hoy())|\(e.vista.pasosHoy)|\(e.vista.meta)|\(e.conectado)"
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let v = mostrando {
                    CelebracionPump(vista: v) { withAnimation(.easeOut(duration: 0.25)) { mostrando = nil } }
                        .transition(.opacity)
                }
            }
            .onChange(of: clave, initial: true) { revisar() }
            .onChange(of: fase) { revisar() }
            .onChange(of: navegacion?.saludAbierta) { revisar() }
            .task {
                // El video: la muestra sube los pasos de hoy a los 5 s.
                guard metas.muestra, let luego = DemoUI.pasosLuego else { return }
                try? await Task.sleep(for: .seconds(5))
                metas.pasosMuestra = luego
            }
    }

    private func revisar() {
        guard mostrando == nil, let e = metas.estado(app), e.conectado, !app.conMuestras || metas.muestra else { return }
        let hoy = FechaLocal.hoy()
        guard metas.debeCelebrar(e.vista, app, hoy: hoy) else { return }
        switch fase {
        case .active:
            guard navegacion?.saludAbierta != true, !esperando else { return }
            // Un respiro para que se vea la tarjeta llenarse antes de la celebración.
            esperando = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(900))
                esperando = false
                guard mostrando == nil, fase == .active, navegacion?.saludAbierta != true, let e = metas.estado(app),
                      FechaLocal.hoy() == hoy, metas.debeCelebrar(e.vista, app, hoy: hoy) else { return }
                metas.marcar(app, hoy: hoy)
                withAnimation(.easeOut(duration: 0.2)) { mostrando = e.vista }
            }
        case .background:
            guard !metas.yaAvisado(hoy), !metas.muestra else { return }
            metas.anotarAviso(hoy)
            Task { await CentroAvisos.shared.avisarPumpLleno(meta: e.vista.meta) }
        default:
            break
        }
    }
}

extension View {
    func celebracionPump() -> some View { modifier(CelebracionPumpRaiz()) }
}
