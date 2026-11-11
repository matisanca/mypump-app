import SwiftUI
import MyPumpDatos
import MyPumpReglas

// «Novedades de tu plan» (2.3.0, palanca `novedades_plan`). Tres lugares:
// · la hoja que aparece sola al abrir, una vez por novedad;
// · la tarjeta de Entreno, durante una semana después de la última;
// · «Novedades de tu plan» en Mis datos, con todas (el lugar fijo).
// Los textos los arma `NovedadesPlan` (kit) sin IA, y se leen como escritos por Mati.

/// Qué novedad está abierta en la hoja. La abre la tarjeta, la lista o la raíz al arrancar.
@MainActor @Observable
final class NovedadesUI {
    static let compartido = NovedadesUI()
    var abierta: NovedadPlan?
    /// La de la hoja de arranque ya se pidió en esta apertura (si el alumno la cierra, no vuelve).
    var yaPedida: Set<String> = []
}

enum TextosNovedades {
    static let ceja = "Novedades de tu plan"
    static let entradaMisDatos = "Novedades de tu plan"
    static let vacio = "Cuando Mati cambie tu rutina, tu dieta o tu suplementación, lo vas a ver acá."
    static let listo = "Listo"

    static func area(_ a: String) -> String {
        switch a { case "rutina": "Rutina"; case "dieta": "Dieta"; default: "Suplementación" }
    }
    static func icono(_ a: String) -> String {
        switch a { case "rutina": "dumbbell.fill"; case "dieta": "fork.knife"; default: "pills.fill" }
    }
    static func boton(_ a: String) -> String {
        switch a { case "rutina": "Ver mi rutina"; case "dieta": "Ver mi dieta"; default: "Ver mi suplementación" }
    }
    static func etiquetaGrande(_ p: ParteNovedad) -> String? {
        guard p.grande else { return nil }
        return p.area == "rutina" ? (p.titular.contains("bloque") ? "Bloque nuevo" : "Nueva")
                                  : (p.titular.contains("nueva") ? "Nueva" : "Primera vez")
    }

    /// «Hoy», «Ayer», «Hace 3 días», «4 de noviembre».
    static func cuando(_ fecha: Date, ahora: Date = .now) -> String {
        let cal = Calendar(identifier: .gregorian)
        let dias = cal.dateComponents([.day], from: cal.startOfDay(for: fecha), to: cal.startOfDay(for: ahora)).day ?? 0
        switch dias {
        case ...0: return "Hoy"
        case 1: return "Ayer"
        case 2...6: return "Hace \(dias) días"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_AR")
            f.dateFormat = "d 'de' MMMM"
            return f.string(from: fecha)
        }
    }
}

// MARK: - El ícono

/// El ícono de la novedad: el verde del logo con un brillo, en un cuadrado redondeado.
struct IconoNovedad: View {
    var lado: CGFloat
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: lado * 0.46, weight: .semibold))
            .foregroundStyle(Color.sobreMarca)
            .frame(width: lado, height: lado)
            .background(Color.marca.gradient, in: .rect(cornerRadius: lado * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - El contenido (hoja y detalle)

struct ContenidoNovedad: View {
    let novedad: NovedadPlan
    var ver: ((String) -> Void)?
    var puede: (String) -> Bool = { _ in true }
    @ScaledMetric(relativeTo: .title) private var ladoIcono: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.l) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                IconoNovedad(lado: min(ladoIcono, 72))
                Text(TextosNovedades.ceja).textoCeja()
                    .accessibilityHidden(true)
                Text(novedad.titular)
                    .font(Archivo.fuente(30, relativoA: .title1))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("novedad-titular")
                Text(TextosNovedades.cuando(novedad.dia))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ForEach(novedad.partes) { p in
                TarjetaParteNovedad(parte: p, ver: novedad.partes.count > 1 && puede(p.area) ? ver : nil)
            }
        }
    }
}

/// Una parte (rutina, dieta o suplementación): su ícono, el nombre y las líneas.
struct TarjetaParteNovedad: View {
    let parte: ParteNovedad
    /// Con varias partes, cada una lleva a su pantalla.
    var ver: ((String) -> Void)?
    @ScaledMetric(relativeTo: .body) private var punto: CGFloat = 7
    @ScaledMetric(relativeTo: .headline) private var ladoIcono: CGFloat = 34
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(spacing: Espacio.xs) {
                // Con letra de accesibilidad el ícono no entra al lado del nombre: se va.
                if !tamañoLetra.isAccessibilitySize {
                    Image(systemName: TextosNovedades.icono(parte.area))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(width: ladoIcono, height: ladoIcono)
                        .background(Color.marcaSuave, in: .rect(cornerRadius: ladoIcono * 0.3, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(TextosNovedades.area(parte.area))
                    .font(Archivo.fuente(19, peso: 700, relativoA: .headline))
                    .accessibilityAddTraits(.isHeader)
                if let e = TextosNovedades.etiquetaGrande(parte) {
                    Text(e)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.marcaTexto)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.marcaSuave, in: .capsule)
                }
                Spacer(minLength: Espacio.xs)
                if let ver {
                    Button { ver(parte.area) } label: {
                        HStack(spacing: 3) {
                            Text("Ver")
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(.rect)
                    }
                    .accessibilityLabel(TextosNovedades.boton(parte.area))
                    .accessibilityIdentifier("novedad-ver-\(parte.area)")
                }
            }
            VStack(alignment: .leading, spacing: Espacio.xs) {
                ForEach(Array(parte.lineas.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.s) {
                        Circle().fill(Color.marca).frame(width: punto, height: punto)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + punto * 0.35 }
                            .accessibilityHidden(true)
                        Text(l)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 2)
        }
        .tarjeta()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("novedad-parte-\(parte.area)")
    }
}

/// La hoja: el contenido, «Ver mi …» y «Listo». Al abrirse queda vista.
struct HojaNovedad: View {
    let novedad: NovedadPlan
    let cerrar: () -> Void
    @Environment(Navegacion.self) private var navegacion
    @State private var modelo = Proveedor.modelo

    private func puedeIr(_ a: String) -> Bool { a != "suplementacion" || modelo.suplementacion?.hay == true }

    private var destino: String? {
        guard novedad.partes.count == 1, let a = novedad.partes.first?.area, puedeIr(a) else { return nil }
        return a
    }

    var body: some View {
        ScrollView {
            ContenidoNovedad(novedad: novedad, ver: { ir(a: $0) }, puede: puedeIr)
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.xl)
                .padding(.bottom, Espacio.m)
                .anchoLectura()
        }
        .background(Color.fondo)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Espacio.xs) {
                if let d = destino {
                    Button(TextosNovedades.boton(d)) { ir(a: d) }
                        .buttonStyle(BotonMarca())
                        .accessibilityIdentifier("novedad-ver")
                    Button(TextosNovedades.listo, action: cerrar)
                        .buttonStyle(BotonSecundario())
                        .accessibilityIdentifier("novedad-listo")
                } else {
                    Button(TextosNovedades.listo, action: cerrar)
                        .buttonStyle(BotonMarca())
                        .accessibilityIdentifier("novedad-listo")
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.vertical, Espacio.s)
            .anchoLectura()
            .background(.bar)
        }
        .onAppear { modelo.novedades?.marcarVista(novedad.id) }
    }

    private func ir(a area: String) {
        cerrar()
        switch area {
        case "rutina": navegacion.pestaña = .entreno
        case "dieta": navegacion.pestaña = .dieta
        default: navegacion.pestaña = .suplementacion
        }
    }
}

// MARK: - La tarjeta de Entreno

/// Arriba de Entreno, durante una semana después de la última novedad. Sin ver, con el punto verde.
struct TarjetaNovedadPlan: View {
    @State private var modelo = Proveedor.modelo
    @ScaledMetric(relativeTo: .title3) private var ladoIcono: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        if modelo.palanca.novedadesPlan || modelo.esDemo, let n = modelo.novedades?.reciente {
            Button { NovedadesUI.compartido.abierta = n } label: {
                HStack(spacing: Espacio.s) {
                    if !tamañoLetra.isAccessibilitySize { IconoNovedad(lado: min(ladoIcono, 60)) }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(n.titular)
                                .font(Archivo.fuente(18, peso: 750, relativoA: .headline))
                                .foregroundStyle(.primary)
                            if !n.vista {
                                Circle().fill(Color.marca).frame(width: 8, height: 8).accessibilityHidden(true)
                            }
                        }
                        Text(n.resumen)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Espacio.xs)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .tarjeta(relleno: Espacio.s + 2)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Abre lo que cambió")
            .accessibilityIdentifier("novedad-tarjeta")
        }
    }
}

// MARK: - Mis datos

/// «Novedades de tu plan» en Mis datos: todas las guardadas, de la más nueva a la más vieja.
struct NovedadesListaView: View {
    let modelo: ModeloNovedades
    /// Estudios y órdenes: un pedido o una orden sin ver también es una novedad, y lleva directo a Estudios.
    var estudios: ModeloEstudios? = nil
    var irAEstudios: (() -> Void)? = nil

    var body: some View {
        let deEstudios = irAEstudios == nil ? nil : estudios?.novedadDeEstudios
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Espacio.s) {
                if let deEstudios, let irAEstudios {
                    Button(action: irAEstudios) {
                        HStack(alignment: .center, spacing: Espacio.s) {
                            Text(deEstudios.titulo).font(Archivo.fuente(18, peso: 750, relativoA: .headline)).foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Espacio.xs)
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .tarjeta()
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("novedad-estudios")
                }
                if modelo.lista.isEmpty, deEstudios == nil {
                    ContentUnavailableView {
                        Label(TextosNovedades.ceja, systemImage: "sparkles")
                    } description: {
                        Text(TextosNovedades.vacio)
                    }
                    .padding(.top, 80)
                }
                ForEach(modelo.lista) { n in
                    Button { NovedadesUI.compartido.abierta = n } label: {
                        HStack(alignment: .top, spacing: Espacio.s) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(TextosNovedades.cuando(n.dia)).textoCeja()
                                Text(n.titular).font(Archivo.fuente(18, peso: 750, relativoA: .headline)).foregroundStyle(.primary)
                                Text(n.resumen).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: Espacio.xs)
                            Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
                                .padding(.top, 4).accessibilityHidden(true)
                        }
                        .tarjeta()
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("novedad-fila")
                }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(TextosNovedades.entradaMisDatos)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - En la raíz

extension View {
    /// La hoja de la novedad (desde cualquier lugar) y, al abrir, la pendiente una sola vez. Espera a que no haya otra hoja
    /// (permisos, la bienvenida de la guía, Salud).
    func hojaDeNovedades(otraHoja: Bool, navegacion: Navegacion) -> some View {
        modifier(HojaDeNovedades(otraHoja: otraHoja, navegacion: navegacion))
    }
}

private struct HojaDeNovedades: ViewModifier {
    let otraHoja: Bool
    let navegacion: Navegacion
    @State private var ui = NovedadesUI.compartido
    @State private var modelo = Proveedor.modelo
    /// Cambia para volver a esperar cuando justo se abrió otra hoja.
    @State private var reintento = 0

    private var pendiente: NovedadPlan? {
        guard modelo.palanca.novedadesPlan || modelo.esDemo, modelo.fase == .listo else { return nil }
        return modelo.novedades?.pendiente
    }

    func body(content: Content) -> some View {
        @Bindable var ui = ui
        content
            .sheet(item: $ui.abierta) { n in
                HojaNovedad(novedad: n, cerrar: { ui.abierta = nil })
                    .environment(navegacion)
                    .presentationDragIndicator(.visible)
            }
            // Otra cuenta (o salir): no queda abierta ni pedida ninguna de la anterior.
            .onChange(of: modelo.novedades.map(ObjectIdentifier.init)) {
                ui.abierta = nil
                ui.yaPedida = []
            }
            .task(id: "\(pendiente?.id ?? "")-\(otraHoja)-\(reintento)") {
                guard let p = pendiente, !ui.yaPedida.contains(p.id) else { return }
                // `otraHoja` solo sabe de las hojas de la raíz. Una hoja de una pantalla (Tu gimnasio, cerrar el día, la
                // técnica) tapaba la novedad: SwiftUI no la presentaba y quedaba pedida sin verse. UIKit sí lo sabe.
                while ((otraHoja || OnboardingPermisos.pendiente) && !modelo.esDemo) || RecorridoUI.compartido.abierta || HojasAbiertas.hay {
                    try? await Task.sleep(for: .seconds(1))
                    if Task.isCancelled { return }
                }
                // Que se vea la app un momento antes de la hoja.
                try? await Task.sleep(for: .milliseconds(1200))
                guard !Task.isCancelled, !otraHoja, ui.abierta == nil, pendiente?.id == p.id else { return }
                // En ese momento se abrió otra: se vuelve a esperar en la próxima vuelta (no queda como ya pedida).
                guard !RecorridoUI.compartido.abierta, !HojasAbiertas.hay else { reintento += 1; return }
                ui.yaPedida.insert(p.id)
                ui.abierta = p
            }
    }
}

#if DEBUG
/// Las novedades de la demo para las capturas (`-novedadDeMuestra`). Con los nombres de la rutina y la dieta de ejemplo.
enum DemoNovedades {
    static func lista(_ tipo: String) -> [NovedadPlan] {
        let ahora = Date.now.timeIntervalSince1970 * 1000
        let rutina = ParteNovedad(area: "rutina", titular: "Mati actualizó tu rutina", grande: false, lineas: [
            "En Tirón A cambia Pullover en polea por Remo en máquina",
            "En Tirón A, Jalón al pecho prono pasa a 4 series de 6 a 8",
            "En Empuje A se suma Vuelos laterales",
        ])
        let dieta = ParteNovedad(area: "dieta", titular: "Mati actualizó tu dieta", grande: false, lineas: [
            "Tu objetivo del día pasa a 2.450 kcal",
            "En Almuerzo, Arroz blanco cocido pasa a 180 g",
            "En Merienda cambia Manzana por Frutillas",
        ])
        let supl = ParteNovedad(area: "suplementacion", titular: "Mati actualizó tu suplementación", grande: false, lineas: [
            "Se suma Magnesio glicinato",
        ])
        let bloque = ParteNovedad(area: "rutina", titular: "Mati te armó un bloque nuevo", grande: true, lineas: [
            "3 días, Tirón A, Empuje A y Pierna A", "9 ejercicios nuevos",
        ])
        if tipo.hasSuffix("-vista") {
            return lista(String(tipo.dropLast(6))).map { var n = $0; n.vista = true; return n }
        }
        switch tipo {
        case "bloque":
            return [NovedadPlan(id: "demo-b", fecha: ahora, resumen: ResumenNovedad(titular: bloque.titular, resumen: bloque.lineas[0], partes: [bloque]))]
        case "rutina":
            return [NovedadPlan(id: "demo-r", fecha: ahora, resumen: ResumenNovedad(titular: rutina.titular, resumen: rutina.lineas[0], partes: [rutina]))]
        default:
            return [
                NovedadPlan(id: "demo-p", fecha: ahora, resumen: ResumenNovedad(titular: "Mati actualizó tu plan",
                                                                                resumen: "Hay cambios en tu rutina, tu dieta y tu suplementación",
                                                                                partes: [rutina, dieta, supl])),
                NovedadPlan(id: "demo-v", fecha: ahora - 9 * 86_400_000,
                            resumen: ResumenNovedad(titular: bloque.titular, resumen: bloque.lineas[0], partes: [bloque]), vista: true),
            ]
        }
    }
}
#endif
