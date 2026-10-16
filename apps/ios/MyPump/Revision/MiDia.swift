import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Mi Día: la racha, cómo fue hoy (entrenamiento, hábitos ✓/✗ y agua), la recuperación y la salud (con una cuenta) y
/// los últimos 30 días (DIA-01…06). Cierra con el respaldo científico (GEN-09). Con una cuenta sale de `ModeloRevision` (por la cola; lo pendiente gana sobre el
/// servidor); en la demo y en los bocetos se toca igual pero no se guarda nada.
struct MiDia: View {
    /// El modelo real, o nil con las muestras.
    let revision: ModeloRevision?
    /// Recuperación y Salud (SAL-09/10): las cards de ModeloSalud, después del agua como en la web. Nil sin cuenta.
    var salud: ModeloSalud? = nil
    let muestra: MuestrasExtra.MiDia
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    /// Lo de hoy con las muestras (con una cuenta manda el modelo).
    @State private var local = HabitosHoy()
    @State private var sembrado = false
    @State private var abierto30 = DemoUI.lleno

    private var habitos: HabitosHoy { revision?.habitos ?? local }
    private var cargado: Bool { revision?.miDiaCargado ?? true }
    /// Lo que cambia con un toque de entrenamiento o hábito (el agua tiene su propio háptico).
    private var firmaHabitos: String {
        [habitos.entrenamiento ?? "-", habitos.comioSegunPlan.map(String.init) ?? "-",
         habitos.durmioBien.map(String.init) ?? "-", habitos.cardio.map(String.init) ?? "-"].joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            if tamañoLetra.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    EncabezadoSeccion(titulo: "Mi día")
                    Text(Self.hoyTexto()).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            } else {
                EncabezadoSeccion(titulo: "Mi día", detalle: Self.hoyTexto())
            }
            VStack(spacing: Espacio.m) {
                Group {
                    TarjetaRacha(n: revision?.racha ?? muestra.racha?.streak ?? 0,
                                 ultimoDiaValido: revision == nil ? muestra.racha?.ultimoDiaValido : revision?.ultimoDiaValido)
                    hoy
                }
                .redacted(reason: cargado ? [] : .placeholder)
                .allowsHitTesting(cargado)
                if let salud {
                    CardRecuperacionView(modelo: salud)
                    CardSaludView(modelo: salud)
                }
                UltimosTreintaDias(dias: revision == nil ? Optional(muestra.adherencia) : revision?.adherencia, abierto: $abierto30) {
                    await revision?.cargarAdherencia()
                }
                .id("dias")
                PieRespaldo(origen: .miDia)
            }
        }
        .onAppear {
            guard !sembrado else { return }
            sembrado = true
            let h = muestra.habitos
            local = HabitosHoy(entrenamiento: h?.entrenamiento, comioSegunPlan: h?.comioSegunPlan, durmioBien: h?.durmioBien,
                               cardio: h?.cardio, vasosAgua: h?.vasosAgua ?? 0)
        }
    }

    // MARK: Hoy

    private var hoy: some View {
        VStack(alignment: .leading, spacing: Espacio.l) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                Text("Entrenamiento").font(.headline)
                let disposicion = tamañoLetra.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Espacio.xs))
                    : AnyLayout(HStackLayout(spacing: Espacio.xs))
                disposicion {
                    opcion("entrene", "Entrené", "figure.strengthtraining.traditional")
                    opcion("descanso", "Descansé", "bed.double.fill")
                    opcion("falte", "Falté", "xmark")
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("Hábitos").font(.headline).padding(.bottom, Espacio.xs)
                filaHabito("comio_segun_plan", habitos.comioSegunPlan, "Comí según el plan", "Seguiste tu dieta hoy", "fork.knife", .alerta)
                Divider().padding(.leading, 42)
                filaHabito("durmio_bien", habitos.durmioBien, "Dormí bien", "7 horas o más", "bed.double.fill", .sueno)
                Divider().padding(.leading, 42)
                filaHabito("cardio", habitos.cardio, "Hice cardio", "Sesión de cardio hoy", "figure.run", .corazon)
            }

            vasos
        }
        .tarjeta()
        .sensoryFeedback(.selection, trigger: firmaHabitos)
    }

    /// Entrené / Descansé / Falté o un hábito ✓/✗: tocar de nuevo lo elegido lo borra, como la web.
    private func tocar(_ campo: String, _ valor: String) {
        if let revision {
            Task { await revision.tocar(campo: campo, valor: valor) }
            return
        }
        switch campo {
        case "entrenamiento": local.entrenamiento = local.entrenamiento == valor ? nil : valor
        case "comio_segun_plan": local.comioSegunPlan = Self.alternar(local.comioSegunPlan, valor)
        case "durmio_bien": local.durmioBien = Self.alternar(local.durmioBien, valor)
        case "cardio": local.cardio = Self.alternar(local.cardio, valor)
        default: break
        }
    }

    private static func alternar(_ actual: Bool?, _ valor: String) -> Bool? {
        let nuevo = valor == "true"
        return actual == nuevo ? nil : nuevo
    }

    private func opcion(_ clave: String, _ titulo: String, _ icono: String) -> some View {
        let elegida = habitos.entrenamiento == clave
        return Button {
            tocar("entrenamiento", clave)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icono).font(.title3).symbolEffect(.bounce, value: elegida)
                Text(titulo).font(.caption.weight(.semibold))
            }
            .foregroundStyle(elegida ? Color.sobreMarca : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(elegida ? Color.marca : Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
            .contentShape(.rect)
            .animation(.snappy(duration: 0.25), value: elegida)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    /// Un hábito con ✓ y ✗: sin marcar, sí o no (tocar de nuevo borra).
    private func filaHabito(_ campo: String, _ valor: Bool?, _ titulo: String, _ sub: String, _ icono: String, _ color: Color) -> some View {
        HStack(spacing: Espacio.s) {
            Image(systemName: icono)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(.body)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Espacio.xs)
            botonHabito(campo, si: false, valor: valor, titulo: titulo)
            botonHabito(campo, si: true, valor: valor, titulo: titulo)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func botonHabito(_ campo: String, si: Bool, valor: Bool?, titulo: String) -> some View {
        let activo = valor == si
        return Button {
            tocar(campo, si ? "true" : "false")
        } label: {
            Image(systemName: si ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(activo ? (si ? Color.sobreMarca : Color.white) : Color.secondary)
                .frame(width: 38, height: 38)
                .background(activo ? (si ? Color.marca : Color.peligro) : Color.campo, in: .circle)
                .symbolEffect(.bounce, value: activo)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .animation(.snappy(duration: 0.25), value: activo)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(titulo): \(si ? "sí" : "no")")
        .accessibilityValue(activo ? "marcado" : "")   // VoiceOver lo dice, y las pruebas de interfaz lo leen
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    /// Agua 0-12 vasos: doce gotas que se llenan, con − y + grandes. Se guarda sola 600 ms después del último toque.
    private var vasos: some View {
        let agua = habitos.vasosAgua
        return VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Agua").font(.headline)
                Spacer()
                Text("\(Text("\(agua)").font(.numeroChico)) de 12 vasos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: Espacio.s) {
                botonAgua("minus", -1).disabled(agua == 0).accessibilityLabel("Un vaso menos")
                HStack(spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        Image(systemName: i < agua ? "drop.fill" : "drop")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(i < agua ? Color.agua : Color.secondary.opacity(0.35))
                            .frame(maxWidth: .infinity)
                    }
                }
                .animation(.snappy(duration: 0.2), value: agua)
                // Con VoiceOver las gotas son un control ajustable: deslizar para arriba o para abajo suma o resta un vaso.
                // Mide lo mismo que los botones (44): la auditoría de accesibilidad lo daba como zona tocable chica.
                .frame(minHeight: 44)
                .contentShape(.rect)
                .accessibilityElement()
                .accessibilityLabel("Agua")
                .accessibilityValue("\(agua) de 12 vasos")
                .accessibilityIdentifier("control-agua")
                .accessibilityAdjustableAction { direccion in
                    switch direccion {
                    case .increment: cambiarAgua(1)
                    case .decrement: cambiarAgua(-1)
                    @unknown default: break
                    }
                }
                botonAgua("plus", 1).disabled(agua == 12).accessibilityLabel("Un vaso más")
            }
        }
        .sensoryFeedback(trigger: agua) { viejo, nuevo in nuevo > viejo ? .increase : .decrease }
    }

    private func cambiarAgua(_ delta: Int) {
        if let revision {
            revision.cambiarAgua(delta)
        } else {
            local.vasosAgua = min(12, max(0, local.vasosAgua + delta))
        }
    }

    private func botonAgua(_ icono: String, _ delta: Int) -> some View {
        Button {
            cambiarAgua(delta)
        } label: {
            Image(systemName: icono)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.agua)
                .frame(width: 44, height: 44)
                .background(Color.agua.opacity(0.14), in: .circle)
        }
        .buttonStyle(.plain)
    }

    /// "miércoles 14 de octubre".
    static func hoyTexto(_ fecha: Date = .now) -> String {
        fecha.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_AR")))
            .replacingOccurrences(of: ",", with: "")
    }
}

// MARK: - Racha

/// La racha (DIA-01): el número grande en Archivo, el ícono del nivel (🔥 7+, ⚡ 3+, ✨ 1+, 💤 0, como
/// `RachaTexto.icono`) y la frase de la web.
private struct TarjetaRacha: View {
    let n: Int
    /// `ultimo_dia_valido` de `get_streak` (YYYY-MM-DD), de la cuenta o de las muestras.
    let ultimoDiaValido: String?

    var body: some View {
        let nivel = Self.nivel(n)
        HStack(alignment: .center, spacing: Espacio.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Racha activa").textoCeja()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(n)").font(.numeroGigante).contentTransition(.numericText())
                    Text(n == 1 ? "día" : "días").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(sub).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                Image(systemName: nivel.icono)
                    .font(.system(size: 30, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(nivel.color)
                    .frame(width: 64, height: 64)
                    .background(nivel.color.opacity(0.14), in: .circle)
                    .symbolEffect(.bounce, value: n)
                Text(nivel.texto).font(.caption.weight(.semibold)).foregroundStyle(nivel.color)
            }
        }
        .tarjeta()
        .animation(.snappy, value: n)
        .accessibilityElement(children: .combine)
    }

    private var sub: String {
        switch n {
        case 0: return "Completá hoy para empezar tu racha"
        case 1: return "¡Primer día, seguí así!"
        default:
            // `renderMydayStreak`: "martes, 21 de julio", o "—" si el servidor no lo mandó.
            return "Último día válido: \(ultimoDiaValido.flatMap(FechaJS.diaLargo) ?? "—")"
        }
    }

    static func nivel(_ n: Int) -> (icono: String, texto: String, color: Color) {
        switch n {
        case 7...: return ("flame.fill", "En llamas", .alerta)
        case 3...: return ("bolt.fill", "Buen ritmo", .record)
        case 1...: return ("sparkles", "Arrancando", .marcaTexto)
        default: return ("moon.zzz.fill", "A retomar", .sueno)
        }
    }
}

// MARK: - Últimos 30 días

/// Los últimos 30 días como calendario (DIA-05): lunes a domingo, cumplido en verde, parcial en verde suave, vacío en
/// gris, y hoy con aro. Se trae al abrirla (como la web: un pedido menos al entrar a Revisión).
private struct UltimosTreintaDias: View {
    /// nil = todavía no se trajo.
    let dias: [DiaAdherencia]?
    @Binding var abierto: Bool
    let cargar: () async -> Void
    @State private var cargando = false
    /// La carga terminó sin datos (sin red): en vez de "Cargando…" para siempre, el error y Reintentar.
    @State private var fallo = false

    private struct Celda: Identifiable {
        let fecha: Date
        let estado: Int   // 2 cumplido, 1 parcial, 0 vacío
        let esHoy: Bool
        var id: Date { fecha }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Button {
                withAnimation(.snappy) { abierto.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Mis últimos 30 días").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    if let dias {
                        Text("\(dias.filter(\.esValido).count)/30")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(abierto ? 180 : 0))
                }
                .frame(minHeight: 32)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(abierto ? "Oculta el historial" : "Muestra tu historial de adherencia")
            .accessibilityIdentifier("ultimos-30")

            if abierto {
                Group {
                    if let dias {
                        if dias.isEmpty {
                            Text("Sin datos aún").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            grilla(dias)
                        }
                    } else if fallo && !cargando {
                        VStack(spacing: Espacio.xs) {
                            Text("No pudimos traer tu historial.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Reintentar") { Task { await traer() } }
                                .buttonStyle(BotonSecundario(compacto: true))
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        HStack(spacing: Espacio.xs) {
                            ProgressView()
                            Text("Cargando…").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Ver mi historial de adherencia").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .tarjeta()
        .clipped()
        .task(id: abierto) {
            guard abierto, dias == nil, !cargando else { return }
            await traer()
        }
    }

    private func traer() async {
        cargando = true
        fallo = false
        await cargar()
        cargando = false
        fallo = dias == nil
    }

    private func grilla(_ dias: [DiaAdherencia]) -> some View {
        let (celdas, huecos) = armar(dias)
        let columnas = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: Espacio.s) {
            LazyVGrid(columns: columnas, spacing: 6) {
                ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { d in
                    Text(d).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<huecos, id: \.self) { _ in Color.clear.frame(height: 1) }
                ForEach(celdas) { c in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(fondo(c.estado))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Text(c.fecha.formatted(.dateTime.day()))
                                .font(.caption2.weight(c.esHoy ? .bold : .medium).monospacedDigit())
                                .foregroundStyle(c.estado == 2 ? Color.sobreMarca : (c.estado == 1 ? Color.primary : Color.secondary))
                                .minimumScaleFactor(0.6)
                        }
                        .overlay {
                            if c.esHoy {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.marcaVivo, lineWidth: 2)
                            }
                        }
                        .accessibilityElement()
                        .accessibilityLabel("\(c.fecha.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_AR")))): \(c.estado == 2 ? "cumplido" : (c.estado == 1 ? "parcial" : "sin datos"))")
                }
            }
            HStack(spacing: Espacio.s) {
                leyenda(fondo(2), "Cumplido")
                leyenda(fondo(1), "Parcial")
                leyenda(fondo(0), "Sin datos")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func fondo(_ estado: Int) -> Color {
        switch estado {
        case 2: Color.marca
        case 1: Color.marca.opacity(0.35)
        default: Color.campo
        }
    }

    private func leyenda(_ color: Color, _ texto: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: 12, height: 12)
            Text(texto)
        }
    }

    /// Las celdas de la más vieja a hoy, y cuántos huecos van antes para que el primer día caiga en su columna.
    private func armar(_ dias: [DiaAdherencia]) -> ([Celda], Int) {
        let filas = dias.compactMap { d -> Celda? in
            guard let f = Fechas.dia(d.fecha) else { return nil }
            let parcial = d.entrenamiento != nil || d.comioSegunPlan != nil || d.durmioBien != nil
            return Celda(fecha: f, estado: d.esValido ? 2 : (parcial ? 1 : 0), esHoy: Calendar.current.isDateInToday(f))
        }.sorted { $0.fecha < $1.fecha }
        guard let primera = filas.first?.fecha else { return ([], 0) }
        // weekday: 1 = domingo … 7 = sábado → columna con lunes primero.
        let dia = Calendar(identifier: .gregorian).component(.weekday, from: primera)
        return (filas, (dia + 5) % 7)
    }
}
