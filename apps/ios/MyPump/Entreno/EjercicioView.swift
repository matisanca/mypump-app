import SwiftUI
import MyPumpModelos
import MyPumpReglas

/// Detalle de un ejercicio: imágenes, la nota de progresión de la semana, la tabla de series y lo que hay que superar.
struct EjercicioView: View {
    let ejercicio: Ejercicio
    let semana: Int
    let semanaOffset: Int
    let resumen: ResumenHistorial?
    @State private var confirmadas: Set<Int> = []

    var body: some View {
        let pauta = Progresiones.pauta(ejercicio, semana: semana)
        let nota = Progresiones.nota(ejercicio, semanaActual: semana)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                imagenes
                HStack(spacing: 6) {
                    if let s = pauta.series, let r = pauta.reps { Chip(texto: "\(s) × \(r)") }
                    if let rir = pauta.rir { Chip(texto: "RIR \(rir)") }
                    if let d = ejercicio.descansoSegundos, d > 0 { Chip(texto: mmss(d), icono: "timer") }
                }
                if let nota {
                    // La web muestra "calibración" solo en la semana 1 sin offset.
                    let esCalibracion = nota.calibracion && semana == 1 && semanaOffset == 0
                    Label {
                        Text(nota.texto).font(.subheadline)
                    } icon: {
                        Image(systemName: esCalibracion ? "scope" : (nota.cambia ? "chart.line.uptrend.xyaxis" : "equal.circle"))
                            .foregroundStyle(Color.marcaTexto)
                    }
                    .tarjeta()
                }
                series(pauta)
                aSuperar
                acciones
                if let notas = ejercicio.notasTecnica, !notas.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        EncabezadoSeccion(titulo: "Técnica")
                        Text(notas).font(.subheadline).tarjeta()
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color.fondo)
        .navigationTitle(ejercicio.nombre)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var imagenes: some View {
        let urls = [ejercicio.imagenes?.eccentric, ejercicio.imagenes?.concentric].compactMap { $0 }.compactMap(URL.init(string:))
        if !urls.isEmpty {
            TabView {
                ForEach(Array(urls.enumerated()), id: \.offset) { i, u in
                    AsyncImage(url: u) { f in
                        if let img = f.image { img.resizable().scaledToFit() } else { ProgressView() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .overlay(alignment: .topLeading) {
                        Text(i == 0 ? "Inicio" : "Pico").font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4).background(.thinMaterial, in: .capsule).padding(10)
                    }
                }
            }
            .tabViewStyle(.page)
            .frame(height: 230)
            .clipShape(.rect(cornerRadius: 18, style: .continuous))
        }
    }

    private func series(_ pauta: Pauta) -> some View {
        let n = max(pauta.series ?? 3, 1)
        return VStack(spacing: 0) {
            HStack {
                Text("Serie").frame(width: 44, alignment: .leading)
                Text("Reps").frame(maxWidth: .infinity)
                Text("Kg").frame(maxWidth: .infinity)
                Text("RIR").frame(maxWidth: .infinity)
                Color.clear.frame(width: 44)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.bottom, 8)
            ForEach(0..<n, id: \.self) { i in
                let previa = resumen?.ultima.first { $0.serie == i + 1 }
                let hecha = confirmadas.contains(i)
                HStack {
                    Text("\(i + 1)").font(.headline.monospacedDigit()).frame(width: 44, alignment: .leading)
                    Casilla(texto: previa?.reps.map(String.init) ?? pauta.reps ?? "—", hecha: hecha)
                    Casilla(texto: previa?.pesoKg.flatMap { $0 > 0 ? $0.kg : nil } ?? "—", hecha: hecha)
                    Casilla(texto: hecha ? "1" : "–", hecha: hecha)
                    Button {
                        if hecha { confirmadas.remove(i) } else { confirmadas.insert(i) }
                    } label: {
                        Image(systemName: hecha ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(hecha ? Color.exito : Color.secondary)
                    }
                    .frame(width: 44)
                    .sensoryFeedback(.success, trigger: hecha) { _, nuevo in nuevo }
                    .accessibilityLabel(hecha ? "Serie \(i + 1) hecha" : "Confirmar serie \(i + 1)")
                }
                .padding(.vertical, 6)
                if i < n - 1 { Divider() }
            }
        }
        .tarjeta()
    }

    @ViewBuilder private var aSuperar: some View {
        if let r = resumen {
            HStack(spacing: 12) {
                Dato(titulo: "Última vez", valor: r.ultima.last.map(cargaTexto) ?? "—",
                     detalle: Fechas.haceCuanto(r.ultimaFecha), icono: "calendar")
                Dato(titulo: "Récord a superar", valor: r.recordKg.map { "\($0.kg) kg" } ?? "—", detalle: "mejor serie",
                     icono: "trophy.fill", tono: .alerta)
            }
        } else {
            Label("Primera vez: buscá un peso con el que llegues cerca del fallo.", systemImage: "sparkles")
                .font(.subheadline).foregroundStyle(.secondary).tarjeta()
        }
    }

    private var acciones: some View {
        HStack(spacing: 10) {
            Button {} label: { Label("Sustituir", systemImage: "arrow.triangle.2.circlepath") }
            Button {} label: { Label("Comentar", systemImage: "bubble.left") }
            if ejercicio.videoURL != nil { Button {} label: { Label("Video", systemImage: "play.rectangle") } }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

private struct Casilla: View {
    let texto: String
    let hecha: Bool
    var body: some View {
        Text(texto)
            .font(.body.monospacedDigit().weight(hecha ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(hecha ? Color.marcaSuave : Color(uiColor: .tertiarySystemFill), in: .rect(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 3)
    }
}

struct Dato: View {
    let titulo: String
    let valor: String
    var detalle: String?
    var icono: String
    var tono: Color = .secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(titulo, systemImage: icono).font(.caption.weight(.medium)).foregroundStyle(tono)
            Text(valor).font(.numeroMediano)
            if let detalle { Text(detalle).font(.caption).foregroundStyle(.secondary) }
        }
        .tarjeta(relleno: 14)
    }
}
