import SwiftUI
import Charts
import MyPumpDatos
import MyPumpModelos
import MyPumpReglas

// Las dos cards de salud de Mi Día (cliente.html:6680-6788 y 7233-7328), con los datos de ModeloSalud. Son vistas
// sueltas: las ubica quien arma Revisión. "Ver todos mis datos" empuja SaludDetalleView (hace falta un NavigationStack).

/// "Conectar Apple Health" con todo lo que hace la web al tocarlo (`_conectarSalud`): el botón no se puede tocar dos
/// veces, un error se explica debajo y, si el historial termina sin un solo dato, se avisa dónde se activan los
/// permisos (con 7 días vacíos no se puede acusar a nadie de haber denegado).
struct BotonConectarSalud: View {
    let modelo: ModeloSalud
    var titulo = "Conectar Apple Health"
    @State private var aviso: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await conectar() }
            } label: {
                if modelo.conectando { ProgressView().tint(Color.sobreMarca) } else { Text(titulo) }
            }
            .buttonStyle(BotonMarca())
            .disabled(modelo.conectando)
            .accessibilityIdentifier("conectar-salud")
            if let aviso { Text(aviso).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func conectar() async {
        aviso = nil
        let r = await modelo.conectar()
        guard r.ok else {
            aviso = r.motivo == "no_disponible" ? "Este iPhone no tiene Salud de Apple."
                : "No pudimos conectar. Probá de nuevo en un rato; si sigue igual, avisale a Mati."
            return
        }
        if let h = r.historial, await h.value.sinDatos {
            aviso = "Quedó conectado pero no llegó ningún dato. Fijate que esté todo activado en Ajustes → Privacidad y seguridad → Salud → MyPump."
        }
    }
}

/// Encabezado de las secciones de Mi Día (ícono + título), como `myday-section-hdr`.
struct EncabezadoSalud: View {
    let icono: String
    let titulo: String
    var body: some View {
        HStack(spacing: 8) {
            // Decorativo: el título ya lo dice (VoiceOver leía «batería, Recuperación»).
            Text(icono).accessibilityHidden(true)
            Text(titulo).font(.headline).accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - Recuperación (SAL-09)

struct CardRecuperacionView: View {
    let modelo: ModeloSalud

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EncabezadoSalud(icono: "🔋", titulo: "Recuperación")
            contenido
        }
        .tarjeta()
        .accessibilityIdentifier("card-recuperacion")
    }

    @ViewBuilder private var contenido: some View {
        switch modelo.cardRecuperacion {
        case .sinConectar:
            Text("Tu recuperación se calcula con lo que mide tu reloj mientras dormís: pulso en reposo, sueño y variabilidad.")
                .font(.subheadline).foregroundStyle(.secondary)
            if modelo.sincronizador != nil {
                BotonConectarSalud(modelo: modelo)
            } else {
                NotaSalud("Si tenés reloj o anillo, conectalo desde la app de iPhone y esto se llena solo.")
            }
        case .conectadoSinScore(let caso):
            Text(caso.frase).font(.subheadline.weight(.medium)).monospacedDigit()
            NotaSalud(caso.nota)
        case .calibrando(let dias, let pct, let yaSe):
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(dias)").font(.numeroGrande)
                Text("/ 14 días").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(pct), total: 100).tint(Color.marcaTexto)
            Text("Estoy aprendiendo cómo es tu normal. \(yaSe)").font(.subheadline.weight(.medium))
            NotaSalud("Sin unos días de historia, cualquier número sería inventado.")
        case .oculto:
            Text("Tenés el score apagado. Tus datos se siguen guardando y Mati los ve igual.").font(.subheadline)
            verTodo
        case .conScore(let c):
            conScore(c)
        }
    }

    @ViewBuilder private func conScore(_ c: SaludVista.ConScore) -> some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(c.fila.score ?? 0)").font(.numeroGigante).foregroundStyle(Self.color(c.banda))
                Text("/100").font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.bandaTexto).font(.headline).foregroundStyle(Self.color(c.banda))
                if let frase = c.frase { Text(frase).font(.subheadline) }
            }
            .padding(.top, 8)
        }
        if let vieja = c.notaVieja { NotaSalud(vieja) }
        if !c.grafico.isEmpty {
            Chart(Array(c.grafico.enumerated()), id: \.offset) { i, p in
                LineMark(x: .value("Día", i), y: .value("Score", p.score)).interpolationMethod(.monotone)
                if i == c.grafico.count - 1 { PointMark(x: .value("Día", i), y: .value("Score", p.score)).symbolSize(30) }
            }
            .foregroundStyle(Self.color(c.banda))
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 38)
            .accessibilityLabel("Tu recuperación de los últimos 14 días")
        }
        if !c.motivos.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(c.motivos.enumerated()), id: \.offset) { _, m in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(m.sube ? "↑" : "↓").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        (Text(m.antes) + Text(m.negrita).bold() + Text(m.despues)).font(.subheadline)
                    }
                }
            }
        }
        if c.provisoria { NotaSalud("Todavía estoy afinando tu rango normal — puede moverse un poco estos días.") }
        verTodo
    }

    private var verTodo: some View {
        NavigationLink {
            SaludDetalleView(modelo: modelo)
        } label: {
            HStack {
                Text("Ver todos mis datos")
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.marcaTexto)
        }
        .accessibilityIdentifier("ver-todos-mis-datos")
    }

    static func color(_ banda: String) -> Color {
        switch banda {
        case "alta": .exito
        case "baja": .peligro
        default: .alerta
        }
    }
}

// MARK: - Salud (SAL-10)

struct CardSaludView: View {
    let modelo: ModeloSalud

    /// Sin conectar, la tarjeta de Recuperación ya ofrece conectar: dos botones iguales seguidos se ven mal (la web los
    /// muestra los dos). Esta lo ofrece solo si la otra no lo hace (por ejemplo, con el score oculto).
    private var otraOfreceConectar: Bool {
        if case .sinConectar = modelo.cardRecuperacion { return true }
        return false
    }

    var body: some View {
        if modelo.sincronizador != nil && !modelo.conectado {
            if !otraOfreceConectar {
                VStack(alignment: .leading, spacing: 12) {
                    EncabezadoSalud(icono: "👟", titulo: "Salud")
                    Text("Conectá Salud de Apple una sola vez y tus pasos y actividad se sincronizan solos para que Mati los vea.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    BotonConectarSalud(modelo: modelo)
                }
                .tarjeta()
            }
        } else if let r = modelo.resumenSalud {
            VStack(alignment: .leading, spacing: 14) {
                EncabezadoSalud(icono: "👟", titulo: "Salud")
                HStack(alignment: .top, spacing: 24) {
                    MetricaSalud(valor: r.pasosHoy.map(SaludVista.miles) ?? "—", etiqueta: "pasos hoy")
                    if let act = r.minutosActivosHoy { MetricaSalud(valor: SaludVista.miles(act), etiqueta: "min activos") }
                }
                if r.suenoAnoche != nil || r.hrv != nil {
                    HStack(alignment: .top, spacing: 24) {
                        if let s = r.suenoAnoche { MetricaSalud(valor: SaludVista.horas(s), etiqueta: "dormiste anoche") }
                        if let h = r.hrv { MetricaSalud(valor: SaludVista.enteroJS(h), unidad: " ms", etiqueta: "HRV (recuperación)") }
                    }
                }
                Text("Promedio \(r.diasPromedio) día\(r.diasPromedio != 1 ? "s" : ""): ") .font(.footnote).foregroundStyle(.secondary)
                    + Text("\(SaludVista.miles(Double(r.promedioPasos))) pasos").font(.footnote.weight(.semibold))
            }
            .tarjeta()
            .accessibilityIdentifier("card-salud")
        } else if let p = modelo.progresoHistorial {
            VStack(alignment: .leading, spacing: 10) {
                EncabezadoSalud(icono: "👟", titulo: "Salud")
                Text("Trayendo tu historial… \(p.hecho)/\(p.total) días").font(.subheadline.weight(.medium)).monospacedDigit()
            }
            .tarjeta()
        }
        // Sin pasos ni actividad, la card no muestra nada (la de Recuperación explica qué falta).
    }
}

struct MetricaSalud: View {
    let valor: String
    var unidad = ""
    let etiqueta: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            (Text(valor) + Text(unidad).font(.subheadline)).font(.numeroMediano).monospacedDigit()
            Text(etiqueta).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// El texto chico y gris de las cards (`rec-nota`).
struct NotaSalud: View {
    let texto: String
    init(_ texto: String) { self.texto = texto }
    var body: some View {
        Text(texto).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
