import SwiftUI
import Charts
import MyPumpDatos
import MyPumpModelos
import MyPumpReglas

/// "Mis datos" de salud: la escena `salud` de la web (cliente.html:6886-7059). Cómo se arma el score, sueño, corazón,
/// actividad, otras señales y cuerpo (cada uno con su promedio de 7 y 30 días y un gráfico chico), "Mostrarme el
/// score" y el estado de Salud de Apple (cuyo título, con 5 toques, abre el diagnóstico).
struct SaludDetalleView: View {
    let modelo: ModeloSalud
    /// Un decimal con coma, como el resto de la app ("82,5 kg"); la web deja el punto.
    private let unDecimal: @Sendable (Double) -> String = { SaludVista.unDecimal($0).replacingOccurrences(of: ".", with: ",") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if modelo.salud.isEmpty {
                    sinDatos
                } else {
                    recuperacion
                    sueno
                    seccion("❤️", "Corazón") {
                        FilaMetricaView(modelo: modelo, tipo: "fc_reposo", nombre: "Pulso en reposo", unidad: " lpm", mejorSube: false, color: .corazon)
                        FilaMetricaView(modelo: modelo, tipo: "hrv_ms", nombre: "Variabilidad (HRV)", unidad: " ms", color: .corazon, nota: notaHRV)
                    }
                    seccion("👟", "Actividad") {
                        FilaMetricaView(modelo: modelo, tipo: "pasos", nombre: "Pasos", formato: SaludVista.miles)
                        FilaMetricaView(modelo: modelo, tipo: "actividad_min", nombre: "Minutos activos", unidad: " min")
                        FilaMetricaView(modelo: modelo, tipo: "kcal_activas", nombre: "Calorías activas", unidad: " kcal")
                    }
                    seccion("🌡", "Otras señales", sub: "Solo importan comparadas con lo normal tuyo, no con una tabla general.") {
                        FilaMetricaView(modelo: modelo, tipo: "respiracion_rpm", nombre: "Respiración", unidad: " /min", color: .teal,
                                        nota: "Sube cuando estás incubando algo, con alcohol encima o durmiendo mal.")
                        FilaMetricaView(modelo: modelo, tipo: "spo2_pct", nombre: "Oxígeno en sangre", unidad: "%", color: .teal)
                        FilaMetricaView(modelo: modelo, tipo: "temp_muneca_c", nombre: "Temperatura de muñeca", unidad: "°", color: .orange,
                                        formato: unDecimal)
                    }
                    seccion("⚖️", "Cuerpo") {
                        FilaMetricaView(modelo: modelo, tipo: "peso_kg", nombre: "Peso", unidad: " kg", formato: unDecimal)
                        FilaMetricaView(modelo: modelo, tipo: "grasa_pct", nombre: "Grasa corporal", unidad: "%", formato: unDecimal)
                    }
                    preferencias
                    SeccionAppleHealth(modelo: modelo)
                    NotaSalud("Los datos los manda tu reloj a Salud de Apple y de ahí llegan acá. Si algo no aparece, es porque tu dispositivo no lo mide.")
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.fondo)
        .navigationTitle("Salud")   // se abre desde Mis datos: con el mismo título quedaban dos "Mis datos" apiladas
        .refreshable { await modelo.cargar() }
    }

    // MARK: - Secciones

    private var sinDatos: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                EncabezadoSalud(icono: "⌚️", titulo: "Todavía no hay datos")
                Text("Cuando conectes tu reloj o tu anillo, acá vas a ver todo lo que mide: sueño con sus fases, pulso en reposo, variabilidad, respiración, oxígeno y temperatura.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if modelo.sincronizador != nil && !modelo.conectado { BotonConectarSalud(modelo: modelo) }
                else if modelo.sincronizador == nil { NotaSalud("Se conecta desde la app de iPhone.") }
            }
            .tarjeta()
            SeccionAppleHealth(modelo: modelo)
        }
    }

    @ViewBuilder private var recuperacion: some View {
        let componentes = modelo.componentes
        if let score = modelo.scoreDeHoy {
            seccion("🔋", "Cómo se arma tu recuperación") {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(score)").font(.numeroGrande)
                    Text("/100").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(componentes, id: \.clave) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.nombre).font(.subheadline)
                            Spacer()
                            Text("\(c.score)").font(.subheadline.weight(.bold)).monospacedDigit()
                        }
                        ProgressView(value: Double(min(max(c.score, 0), 100)), total: 100)
                            .tint(c.score >= 67 ? Color.exito : c.score >= 34 ? Color.alerta : Color.peligro)
                        Text("pesa \(c.aporte)% en tu score").font(.caption).foregroundStyle(.secondary)
                    }
                }
                NotaSalud("Los que no tenés no se promedian como cero: el score se reparte entre los datos que sí hay. Por eso podés tener número aunque tu reloj no mida variabilidad.")
            }
        }
    }

    @ViewBuilder private var sueno: some View {
        let serie = modelo.serie("sueno_min")
        if let ultima = serie.last {
            seccion("😴", "Sueño") {
                HStack {
                    Text(SaludVista.rotuloNoche(ultima.fecha, hoy: modelo.fecha)).font(.subheadline)
                    Spacer()
                    Text(SaludVista.horas(ultima.valor)).font(.numeroMediano).monospacedDigit()
                }
                if ultima.detalle?["estimado"] == .bool(true) {
                    NotaSalud("Estimado a partir del tiempo en la cama: tu reloj no mandó las fases.")
                }
                etapas
                GraficoSalud(serie: serie, color: .sueno)
                Text("promedio 7 días: ").font(.caption).foregroundStyle(.secondary)
                    + Text(SaludVista.horas(serie.suffix(7).map(\.valor).reduce(0, +) / Double(min(serie.count, 7)))).font(.caption.weight(.semibold))
                    + Text(" · \(serie.count) noches con dato").font(.caption).foregroundStyle(.secondary)
                FilaMetricaView(modelo: modelo, tipo: "sueno_eficiencia_pct", nombre: "Eficiencia (dormido / en cama)", unidad: "%", color: .sueno)
                if let r = SaludVista.regularidad(modelo.salud) {
                    (Text("Te dormís en promedio cerca de las ") + Text(r.horaDormirse).bold() + Text(", con una variación de ")
                        + Text("±\(r.variacion) min").bold() + Text(". \(r.texto)"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var etapas: some View {
        let tipos: [(tipo: String, nombre: String, color: Color)] = [
            ("sueno_profundo_min", "Profundo", Color(red: 0x5B / 255, green: 0x6E / 255, blue: 0xE1 / 255)),
            ("sueno_rem_min", "REM", Color(red: 0x9B / 255, green: 0x6E / 255, blue: 0xE1 / 255)),
            ("sueno_ligero_min", "Ligero", Color(red: 0x8F / 255, green: 0xA8 / 255, blue: 0xD8 / 255)),
        ]
        let et = tipos.compactMap { t in modelo.serie(t.tipo).last.map { (t, $0.valor) } }
        if !et.isEmpty {
            let total = et.reduce(0) { $0 + $1.1 }
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(et, id: \.0.tipo) { t, v in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(t.color)
                            .frame(height: max(6, CGFloat(v / (total == 0 ? 1 : total)) * 70))
                        Text(SaludVista.horas(v)).font(.caption.weight(.semibold)).monospacedDigit()
                        Text(t.nombre).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
    }

    private var notaHRV: String? {
        switch modelo.serie("hrv_ms").last?.detalle?["metrica"]?.comoTexto {
        case "sdnn": "Tu reloj mide SDNN en momentos sueltos del día, así que un valor aislado varía mucho. Lo que importa es la línea, no el número de hoy."
        case "rmssd": "Medida durante la noche (rMSSD): es la más confiable para ver recuperación."
        default: nil
        }
    }

    private var preferencias: some View {
        seccion("⚙️", "Preferencias") {
            Toggle(isOn: Binding(get: { modelo.mostrarRecuperacion }, set: { v in Task { await modelo.cambiarMostrarRecuperacion(v) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mostrarme el score").font(.subheadline.weight(.medium))
                    Text("Si preferís no ver el número, lo apagás acá. Tus datos se siguen guardando y Mati los sigue viendo igual.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Color.exito)
            .accessibilityIdentifier("mostrar-score")
        }
    }

    private func seccion(_ icono: String, _ titulo: String, sub: String? = nil, @ViewBuilder _ cuerpo: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EncabezadoSalud(icono: icono, titulo: titulo)
            if let sub { Text(sub).font(.footnote).foregroundStyle(.secondary) }
            cuerpo()
        }
        .tarjeta()
    }
}

/// `_filaSalud`: el valor del último día con su flecha contra el promedio de 30 días, el gráfico chico y los
/// promedios. Si no hay datos de ese tipo, no ocupa lugar.
struct FilaMetricaView: View {
    let modelo: ModeloSalud
    let tipo: String
    let nombre: String
    var unidad = ""
    var mejorSube = true
    var color: Color = .marcaTexto
    var formato: (Double) -> String = SaludVista.entero
    var nota: String?

    var body: some View {
        if let f = SaludVista.fila(modelo.salud, tipo: tipo, mejorSube: mejorSube, formato: formato) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(nombre).font(.subheadline)
                    Spacer()
                    (Text(f.valor).font(.headline) + Text(unidad).font(.caption)).monospacedDigit()
                    if let d = f.delta {
                        Text(d).font(.caption.weight(.semibold)).foregroundStyle(f.deltaEsBueno ? Color.exito : Color.alerta)
                    }
                }
                GraficoSalud(serie: f.serie, color: color)
                (Text("promedio 7 días: ") + Text("\(f.promedio7)\(unidad)").bold()
                    + Text(f.promedio30.map { " · 30 días: \($0)\(unidad)" } ?? "")
                    + Text(" · \(f.diasConDato) día\(f.diasConDato != 1 ? "s" : "") con dato"))
                    .font(.caption).foregroundStyle(.secondary)
                if let nota { NotaSalud(nota) }
            }
            .padding(.vertical, 2)
        }
    }
}

/// El gráfico chico de una serie (últimos 30 puntos; hacen falta 3).
struct GraficoSalud: View {
    let serie: [PuntoSalud]
    var color: Color = .marcaTexto

    var body: some View {
        let puntos = Array(serie.suffix(30).enumerated())
        if puntos.count >= 3 {
            let vs = puntos.map(\.element.valor)
            let lo = vs.min() ?? 0, hi = vs.max() ?? 1
            Chart(puntos, id: \.offset) { i, p in
                LineMark(x: .value("Día", i), y: .value("Valor", p.valor)).interpolationMethod(.monotone)
            }
            .foregroundStyle(color.opacity(0.85))
            .chartYScale(domain: lo...(hi > lo ? hi : lo + 1))
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .frame(height: 30)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Salud de Apple (renderAppleHealthEstado)

/// El estado real de Apple Health: no disponible, "no está llegando ningún dato" (con Reintentar), conectado (última
/// sincronización y Sincronizar) o sin conectar. El título, tocado 5 veces seguidas, abre el diagnóstico (SAL-13).
struct SeccionAppleHealth: View {
    let modelo: ModeloSalud
    @State private var estado: EstadoSalud?
    @State private var mensaje: String?
    @State private var ocupado = false
    @State private var toques = 0
    @State private var ultimoToque = Date.distantPast
    @State private var diagnostico = false

    var body: some View {
        if modelo.sincronizador != nil {
            VStack(alignment: .leading, spacing: 10) {
                EncabezadoSalud(icono: "❤️", titulo: "Salud de Apple")
                    .contentShape(Rectangle())
                    .onTapGesture { tocarTitulo() }
                    .accessibilityIdentifier("titulo-salud-apple")
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("iPhone y Apple Watch").font(.subheadline.weight(.medium))
                            if modelo.conectado && !modelo.sinDatos { Chip(texto: "activo", tono: .exito) }
                        }
                        Text(descripcion).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    boton
                }
                if let mensaje { NotaSalud(mensaje) }
            }
            .tarjeta()
            .task { estado = await modelo.estado() }
            .sheet(isPresented: $diagnostico) { NavigationStack { DiagnosticoSaludView(modelo: modelo) } }
        }
    }

    private var descripcion: String {
        if estado?.disponible == false { return "Este iPhone no tiene Salud de Apple." }
        if modelo.sinDatos {
            return "No está llegando ningún dato. Revisá que esté todo activado en Ajustes → Privacidad y seguridad → Salud → MyPump."
        }
        if modelo.conectado {
            guard let u = modelo.ultimaSync else { return "Conectado" }
            return "Última sincronización: \(Self.hace(u))"
        }
        return "Conectalo y tus pasos, sueño y pulso entran solos."
    }

    @ViewBuilder private var boton: some View {
        if estado?.disponible == false {
            EmptyView()
        } else if modelo.sinDatos {
            Button(ocupado ? "…" : "Reintentar") { Task { await reintentar() } }.buttonStyle(.bordered).disabled(ocupado)
        } else if modelo.conectado {
            Button(ocupado || modelo.sincronizando ? "…" : "Sincronizar") { Task { await sincronizar() } }
                .buttonStyle(.bordered).disabled(ocupado || modelo.sincronizando)
                .accessibilityIdentifier("sincronizar-salud")
        } else {
            Button(ocupado || modelo.conectando ? "…" : "Conectar") { Task { await conectar() } }
                .buttonStyle(.borderedProminent).tint(Color.marca).foregroundStyle(Color.sobreMarca).disabled(ocupado)
        }
    }

    private func tocarTitulo() {
        let ahora = Date()
        toques = ahora.timeIntervalSince(ultimoToque) < 1.5 ? toques + 1 : 1   // la racha se corta sola
        ultimoToque = ahora
        if toques >= 5 { toques = 0; diagnostico = true }
    }

    private func conectar() async {
        ocupado = true
        let r = await modelo.conectar()
        ocupado = false
        if !r.ok { mensaje = r.motivo == "no_disponible" ? "Este iPhone no tiene Salud de Apple." : "No pudimos conectar. Probá de nuevo en un rato; si sigue igual, avisale a Mati." }
        estado = await modelo.estado()
    }

    /// Solo sirve si volvió de Ajustes y activó algo: si sigue denegado, iOS no muestra nada.
    private func reintentar() async {
        ocupado = true
        let r = await modelo.conectar()
        ocupado = false
        if !r.ok { mensaje = "Sigue sin permiso. Activalo en Ajustes y volvé." }
    }

    private func sincronizar() async {
        ocupado = true
        let r = await modelo.sincronizar()
        await modelo.cargar()
        ocupado = false
        mensaje = ModeloSalud.textoSincronizacion(r)
    }

    /// "recién", "hace 3 h" o "12 oct".
    static func hace(_ d: Date) -> String {
        let h = Date().timeIntervalSince(d) / 3600
        if h < 1 { return "recién" }
        if h < 24 { return "hace \(Int(jsRound(h))) h" }
        return SaludVista.fechaCorta(FechaLocal.hoy(d)) ?? ""
    }
}
