import SwiftUI
import MyPumpModelos

/// Mi Día: la racha, cómo fue hoy (entrenamiento, hábitos ✓/✗ y agua) y los últimos 30 días (DIA-01…05). Cierra con
/// el respaldo científico (GEN-09).
struct MiDia: View {
    let racha: Racha?
    let habitos: HabitosDia?
    let adherencia: [DiaAdherencia]
    @Environment(\.dynamicTypeSize) private var tamañoLetra
    @State private var entreno: String?
    @State private var habito: [String: Bool] = [:]
    @State private var agua = 0
    @State private var cargado = false

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
                TarjetaRacha(racha: racha)
                hoy
                UltimosTreintaDias(dias: adherencia).id("dias")
                PieRespaldo(origen: .miDia)
            }
        }
        .onAppear {
            guard !cargado else { return }
            cargado = true
            entreno = habitos?.entrenamiento
            if let v = habitos?.comioSegunPlan { habito["comio"] = v }
            if let v = habitos?.durmioBien { habito["durmio"] = v }
            if let v = habitos?.cardio { habito["cardio"] = v }
            agua = habitos?.vasosAgua ?? 0
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
                filaHabito("comio", "Comí según el plan", "Seguiste tu dieta hoy", "fork.knife", .alerta)
                Divider().padding(.leading, 42)
                filaHabito("durmio", "Dormí bien", "7 horas o más", "bed.double.fill", .sueno)
                Divider().padding(.leading, 42)
                filaHabito("cardio", "Hice cardio", "Sesión de cardio hoy", "figure.run", .corazon)
            }

            vasos
        }
        .tarjeta()
        .sensoryFeedback(.selection, trigger: entreno)
        .sensoryFeedback(.selection, trigger: habito)
    }

    /// Entrené / Descansé / Falté. Tocar de nuevo la elegida la borra (como la web).
    private func opcion(_ clave: String, _ titulo: String, _ icono: String) -> some View {
        let elegida = entreno == clave
        return Button {
            withAnimation(.snappy(duration: 0.25)) { entreno = elegida ? nil : clave }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icono).font(.title3).symbolEffect(.bounce, value: elegida)
                Text(titulo).font(.caption.weight(.semibold))
            }
            .foregroundStyle(elegida ? Color.sobreMarca : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 66)
            .background(elegida ? Color.marca : Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(elegida ? .isSelected : [])
    }

    /// Un hábito con ✓ y ✗: sin marcar, sí o no (tocar de nuevo borra).
    private func filaHabito(_ clave: String, _ titulo: String, _ sub: String, _ icono: String, _ color: Color) -> some View {
        let valor = habito[clave]
        return HStack(spacing: Espacio.s) {
            Image(systemName: icono)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(.body)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Espacio.xs)
            botonHabito(clave, si: false, valor: valor)
            botonHabito(clave, si: true, valor: valor)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func botonHabito(_ clave: String, si: Bool, valor: Bool?) -> some View {
        let activo = valor == si
        return Button {
            withAnimation(.snappy(duration: 0.25)) { habito[clave] = activo ? nil : si }
        } label: {
            Image(systemName: si ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(activo ? (si ? Color.sobreMarca : Color.white) : Color.secondary)
                .frame(width: 38, height: 38)
                .background(activo ? (si ? Color.marca : Color.peligro) : Color.campo, in: .circle)
                .symbolEffect(.bounce, value: activo)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(si ? "Sí" : "No")
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    /// Agua 0-12 vasos: doce gotas que se llenan, con − y + grandes.
    private var vasos: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
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
                .accessibilityElement()
                .accessibilityLabel("\(agua) de 12 vasos de agua")
                botonAgua("plus", 1).disabled(agua == 12).accessibilityLabel("Un vaso más")
            }
        }
        .sensoryFeedback(trigger: agua) { viejo, nuevo in nuevo > viejo ? .increase : .decrease }
    }

    private func botonAgua(_ icono: String, _ delta: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { agua = min(12, max(0, agua + delta)) }
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

/// La racha (DIA-01): el número grande en Archivo, el ícono del nivel (🔥 7+, ⚡ 3+, ✨ 1+, 💤 0) y la frase de la web.
private struct TarjetaRacha: View {
    let racha: Racha?

    var body: some View {
        let n = racha?.streak ?? 0
        let nivel = Self.nivel(n)
        HStack(alignment: .center, spacing: Espacio.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Racha activa").textoCeja()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(n)").font(.numeroGigante).contentTransition(.numericText())
                    Text(n == 1 ? "día" : "días").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text(sub(n)).font(.footnote).foregroundStyle(.secondary)
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
        .accessibilityElement(children: .combine)
    }

    private func sub(_ n: Int) -> String {
        switch n {
        case 0: return "Completá hoy para empezar tu racha"
        case 1: return "¡Primer día, seguí así!"
        default:
            let f = racha?.ultimoDiaValido.flatMap(Fechas.dia)
            return "Último día válido: \(f?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_AR"))) ?? "—")"
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

/// Los últimos 30 días como calendario (DIA-05): lunes a domingo, cumplido en lima, parcial en lima suave, vacío en
/// gris, y hoy con aro.
private struct UltimosTreintaDias: View {
    let dias: [DiaAdherencia]

    private struct Celda: Identifiable {
        let fecha: Date
        let estado: Int   // 2 cumplido, 1 parcial, 0 vacío
        let esHoy: Bool
        var id: Date { fecha }
    }

    var body: some View {
        let validos = dias.filter(\.esValido).count
        let (celdas, huecos) = armar()
        let columnas = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mis últimos 30 días").font(.headline)
                Spacer()
                Text("\(validos)/30").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            if dias.isEmpty {
                Text("Sin datos aún").font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columnas, spacing: 6) {
                    ForEach(["L", "M", "X", "J", "V", "S", "D"], id: \.self) { d in
                        Text(d).font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
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
        .tarjeta()
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
    private func armar() -> ([Celda], Int) {
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
