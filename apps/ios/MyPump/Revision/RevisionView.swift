import SwiftUI
import Charts
import MyPumpModelos

/// Revisión: fotos de la semana, check, peso, reloj y Mi Día, en ese orden (como la web).
struct RevisionView: View {
    let datos: Muestras
    @State private var check: [String: Int] = [:]
    @State private var entreno: String?
    @State private var habitos: Set<String> = []
    @State private var agua = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    fotos
                    checkSemanal
                    peso
                    reloj
                    miDia
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.fondo)
            .navigationTitle("Revisión")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { MisDatosView(datos: datos) } label: { Image(systemName: "person.crop.circle") }
                        .accessibilityLabel("Mis datos")
                }
            }
        }
    }

    private var fotos: some View {
        VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "Fotos de la semana", detalle: "0/3")
            HStack(spacing: 10) {
                ForEach(["Frente", "Perfil", "Espalda"], id: \.self) { pose in
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill").font(.title3).foregroundStyle(Color.marcaTexto)
                        Text(pose).font(.footnote.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                    .background(Color.tarjeta, in: .rect(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5])))
                }
            }
        }
    }

    private var checkSemanal: some View {
        VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "Check de la semana")
            VStack(alignment: .leading, spacing: 14) {
                ForEach([("energia", "Energía"), ("descanso", "Descanso"), ("hambre", "Hambre"), ("adherencia", "Adherencia")], id: \.0) { clave, nombre in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(nombre).font(.subheadline.weight(.medium))
                        Picker(nombre, selection: Binding(get: { check[clave] ?? 0 }, set: { check[clave] = $0 })) {
                            ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Button {} label: { Text("Enviar mi check") }.buttonStyle(BotonMarca()).disabled(check.count < 4)
            }
            .tarjeta()
        }
    }

    private var peso: some View {
        let pesos = datos.salud.filter { $0.tipo == "peso_kg" }.compactMap { f in f.valor.map { (Fechas.dia(f.fecha) ?? .now, $0) } }
            .sorted { $0.0 < $1.0 }
        return VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "Peso")
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(pesos.last.map { $0.1.kg } ?? "—").font(.numeroGrande)
                    Text("kg").foregroundStyle(.secondary)
                    Spacer()
                    if pesos.count > 7, let a = pesos.last?.1 {
                        let b = pesos[pesos.count - 8].1
                        Label("\(a - b > 0 ? "+" : "")\((a - b).kg) kg vs la semana pasada", systemImage: a - b > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                if !pesos.isEmpty {
                    Chart(pesos, id: \.0) { p in
                        LineMark(x: .value("Fecha", p.0), y: .value("Kg", p.1)).interpolationMethod(.catmullRom).foregroundStyle(Color.marcaTexto)
                        PointMark(x: .value("Fecha", p.0), y: .value("Kg", p.1)).symbolSize(14).foregroundStyle(Color.marcaTexto)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 140)
                }
                Button {} label: { Label("Cargar peso de hoy", systemImage: "plus") }.buttonStyle(.bordered)
            }
            .tarjeta()
        }
    }

    private var reloj: some View {
        VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "Mi reloj")
            VStack(spacing: 0) {
                ForEach(["Oura", "WHOOP"], id: \.self) { p in
                    HStack {
                        Image(systemName: "applewatch").foregroundStyle(.secondary)
                        Text(p)
                        Spacer()
                        Button("Conectar") {}.buttonStyle(.bordered).controlSize(.small)
                    }
                    .padding(.vertical, 8)
                    if p == "Oura" { Divider() }
                }
            }
            .tarjeta(relleno: 14)
        }
    }

    private var miDia: some View {
        VStack(alignment: .leading, spacing: 10) {
            EncabezadoSeccion(titulo: "Mi día")
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(datos.racha?.streak ?? 0)").font(.numeroGigante)
                    VStack(alignment: .leading) {
                        Text(racha(datos.racha?.streak ?? 0)).font(.headline)
                        Text("días seguidos").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Picker("Hoy", selection: $entreno) {
                    Text("Entrené").tag(Optional("entrene"))
                    Text("Descansé").tag(Optional("descanso"))
                    Text("Falté").tag(Optional("falte"))
                }
                .pickerStyle(.segmented)
                ForEach([("comio", "Comí según el plan", "fork.knife"), ("durmio", "Dormí bien", "bed.double.fill"), ("cardio", "Hice cardio", "figure.run")], id: \.0) { c, t, i in
                    Toggle(isOn: Binding(get: { habitos.contains(c) }, set: { if $0 { habitos.insert(c) } else { habitos.remove(c) } })) {
                        Label(t, systemImage: i)
                    }
                    .tint(Color.exito)
                }
                Stepper(value: $agua, in: 0...12) {
                    Label("\(agua) vasos de agua", systemImage: "drop.fill").monospacedDigit()
                }
            }
            .tarjeta()
            .sensoryFeedback(.selection, trigger: habitos)
        }
    }

    private func racha(_ n: Int) -> String {
        switch n {
        case 7...: return "🔥 En llamas"
        case 3...: return "⚡ Buen ritmo"
        case 1...: return "✨ Arrancando"
        default: return "💤 A retomar"
        }
    }
}
