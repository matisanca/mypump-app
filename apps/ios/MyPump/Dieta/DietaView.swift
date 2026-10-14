import SwiftUI
import MyPumpModelos

struct DietaView: View {
    let datos: Muestras
    @State private var opcion: [String: Int] = [:]
    @State private var estado: [String: String] = [:]   // comida → "comido" | "saltado"

    private var dieta: EstructuraDieta? { datos.dieta?.estructura }
    private var comidas: [Comida] { dieta?.comidas ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    cabecera
                    ForEach(comidas, id: \.id) { c in tarjeta(c) }
                    RespaldoCientifico(texto: "Tu plan lo arma Mati, que es médico, con base en ISSN, NASEM y OMS")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color.fondo)
            .navigationTitle("Dieta")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu { Button("Día de entreno") {}; Button("Día de descanso") {} } label: {
                        Label("Entreno", systemImage: "figure.strengthtraining.traditional").labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private func totales(_ alimentos: [Alimento]) -> Macros {
        Macros(kcal: alimentos.compactMap(\.kcal).reduce(0, +), prot: alimentos.compactMap(\.prot).reduce(0, +),
               carb: alimentos.compactMap(\.carb).reduce(0, +), fat: alimentos.compactMap(\.fat).reduce(0, +))
    }

    private var consumido: Macros {
        let comidas = self.comidas.filter { estado[$0.id] == "comido" }
        return totales(comidas.flatMap { c in c.opciones[safe: opcion[c.id] ?? 0]?.alimentos ?? [] })
    }

    private var cabecera: some View {
        let objetivo = dieta?.macrosTarget ?? totales(comidas.compactMap(\.opciones.first).flatMap(\.alimentos))
        let hecho = consumido
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                Anillo(valor: hecho.kcal ?? 0, total: objetivo.kcal ?? 1) {
                    VStack(spacing: 0) {
                        Text(Int(hecho.kcal ?? 0), format: .number).font(.numeroGrande).contentTransition(.numericText())
                        Text("de \(Int(objetivo.kcal ?? 0)) kcal").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 10) {
                    BarraMacro(nombre: "Proteínas", valor: hecho.prot ?? 0, total: objetivo.prot ?? 1, color: .corazon)
                    BarraMacro(nombre: "Carbos", valor: hecho.carb ?? 0, total: objetivo.carb ?? 1, color: .alerta)
                    BarraMacro(nombre: "Grasas", valor: hecho.fat ?? 0, total: objetivo.fat ?? 1, color: .sueno)
                }
            }
            RespaldoCientifico()
        }
        .tarjeta()
        .animation(.snappy, value: estado)
    }

    private func tarjeta(_ c: Comida) -> some View {
        let idx = opcion[c.id] ?? 0
        let op = c.opciones[safe: idx]
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(c.nombre ?? "Comida").font(.title3.weight(.semibold))
                Spacer()
                if let e = estado[c.id] {
                    Label(e == "comido" ? "Comí" : "Salteada", systemImage: e == "comido" ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.footnote.weight(.semibold)).foregroundStyle(e == "comido" ? Color.exito : Color.secondary)
                }
                Text("\(Int(totales(op?.alimentos ?? []).kcal ?? 0)) kcal").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            if c.opciones.count > 1 {
                Picker("Opción", selection: Binding(get: { idx }, set: { opcion[c.id] = $0 })) {
                    ForEach(Array(c.opciones.enumerated()), id: \.offset) { i, _ in Text("Opción \(letra(i))").tag(i) }
                }
                .pickerStyle(.segmented)
            }
            VStack(spacing: 0) {
                ForEach(Array((op?.alimentos ?? []).enumerated()), id: \.offset) { i, a in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.nombre).font(.subheadline)
                            Text(cantidad(a)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(a.kcal ?? 0))").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                        Button {} label: { Image(systemName: "hand.raised") }.accessibilityLabel("Porción casera")
                        Button {} label: { Image(systemName: "arrow.left.arrow.right") }.accessibilityLabel("Sustituir \(a.nombre)")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 8)
                    if i < (op?.alimentos.count ?? 0) - 1 { Divider() }
                }
            }
            HStack(spacing: 10) {
                Button { estado[c.id] = estado[c.id] == "comido" ? nil : "comido" } label: {
                    Label("Comí", systemImage: "checkmark")
                }
                .buttonStyle(BotonMarca())
                .sensoryFeedback(.success, trigger: estado[c.id] == "comido") { _, n in n }
                Button { estado[c.id] = estado[c.id] == "saltado" ? nil : "saltado" } label: {
                    Label("Salté", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
            }
        }
        .tarjeta()
    }

    private func letra(_ i: Int) -> String { String(UnicodeScalar(65 + i).map(Character.init) ?? "?") }

    private func cantidad(_ a: Alimento) -> String {
        guard let q = a.qty else { return a.unidad ?? "" }
        return "\(q.kg) \(a.unidad ?? "g")"
    }
}

struct Anillo<Centro: View>: View {
    let valor: Double
    let total: Double
    @ViewBuilder let centro: () -> Centro

    var body: some View {
        ZStack {
            Circle().stroke(Color(uiColor: .tertiarySystemFill), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(valor / max(total, 1), 1))
                .stroke(Color.marca, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            centro()
        }
    }
}

struct BarraMacro: View {
    let nombre: String
    let valor: Double
    let total: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(nombre).font(.caption.weight(.medium))
                Spacer()
                Text("\(Int(valor))/\(Int(total)) g").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(valor, total), total: max(total, 1)).tint(color)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
