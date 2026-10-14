import SwiftUI
import MyPumpModelos
import MyPumpReglas

struct EntrenoView: View {
    let datos: Muestras
    @State private var diaId: String?
    @State private var ruta: [Ejercicio] = []
    @State private var finDescanso = Date.now.addingTimeInterval(84)

    private var rutina: RutinaActiva? { datos.rutina }
    private var dias: [Dia] { rutina?.estructura.dias ?? [] }
    private var dia: Dia? { dias.first { $0.id == diaId } ?? dias.first }
    private var semana: Int { rutina?.semanaActual ?? 1 }
    private var offset: Int { rutina?.estructura.semanaOffset ?? 0 }
    private var total: Int { rutina?.estructura.semanasTotal ?? 12 }
    private var cerrados: Set<String> { Set(datos.sesionesSemana.filter(\.cerrada).map(\.diaId)) }

    var body: some View {
        NavigationStack(path: $ruta) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SelectorDias(dias: dias, seleccionado: dia?.id, cerrados: cerrados) { diaId = $0 }
                    if let dia { contenido(de: dia) }
                    RespaldoCientifico(texto: "Tu plan lo arma Mati con base en ACSM e ISSN")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 96)
            }
            .background(Color.fondo)
            .navigationTitle(titulo(dia))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Semana \(semana + offset) de \(total + offset)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.marcaSuave, in: .capsule)
                }
            }
            .navigationDestination(for: Ejercicio.self) { e in
                EjercicioView(ejercicio: e, semana: semana, semanaOffset: offset, resumen: datos.resumen(de: e))
            }
            .safeAreaInset(edge: .bottom) { DescansoBarra(fin: finDescanso, total: 150) }
            .onAppear {
                // Bocetos: `-abrir ejercicio` entra directo al primer ejercicio de trabajo, para sacar la captura.
                if UserDefaults.standard.string(forKey: "abrir") == "ejercicio", ruta.isEmpty,
                   let e = dias.first?.bloques.flatMap(\.ejercicios).first(where: { $0.tipo == "compuesto" }) {
                    ruta = [e]
                }
            }
        }
    }

    @ViewBuilder
    private func contenido(de dia: Dia) -> some View {
        let todos = dia.bloques.flatMap(\.ejercicios)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(cerrados.contains(dia.id ?? "") ? "Día cerrado esta semana" : "\(todos.count) ejercicios")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("0/\(todos.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: 0, total: Double(max(todos.count, 1))).tint(Color.marca)
        }

        Button {} label: { Label("Empezar entrenamiento", systemImage: "play.fill") }
            .buttonStyle(BotonMarca())

        ForEach(Array(dia.bloques.enumerated()), id: \.offset) { i, bloque in
            VStack(alignment: .leading, spacing: 10) {
                EncabezadoSeccion(titulo: bloque.titulo ?? "Bloque \(i + 1)", detalle: "0/\(bloque.ejercicios.count)")
                ForEach(bloque.ejercicios, id: \.id) { e in
                    NavigationLink(value: e) {
                        FilaEjercicio(ejercicio: e, numero: numero(de: e, en: dia), semana: semana, resumen: datos.resumen(de: e))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func numero(de e: Ejercicio, en dia: Dia) -> Int {
        (dia.bloques.flatMap(\.ejercicios).firstIndex { $0.id == e.id } ?? 0) + 1
    }

    /// Los nombres que vienen todo en mayúsculas ("TIRÓN") se muestran capitalizados; los demás, tal cual.
    private func titulo(_ dia: Dia?) -> String {
        guard let n = dia?.nombre, !n.isEmpty else { return "Entreno" }
        return n == n.uppercased() ? n.localizedCapitalized : n
    }
}

extension Ejercicio: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SelectorDias: View {
    let dias: [Dia]
    let seleccionado: String?
    let cerrados: Set<String>
    let elegir: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(dias.enumerated()), id: \.offset) { i, d in
                    let activo = d.id == seleccionado
                    let hecho = cerrados.contains(d.id ?? "")
                    Button { elegir(d.id) } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 3) {
                                Text("DÍA \(d.n ?? i + 1)").font(.caption2.weight(.bold)).tracking(0.5)
                                if hecho { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
                            }
                            .foregroundStyle(activo ? Color(uiColor: .systemBackground).opacity(0.7) : .secondary)
                            Text(corto(d.nombre)).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        .frame(minWidth: 76)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                        .foregroundStyle(activo ? Color(uiColor: .systemBackground) : .primary)
                        .background(activo ? Color.primary : (hecho ? Color.marcaSuave : Color.tarjeta), in: .rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: activo)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func corto(_ nombre: String?) -> String {
        let p = (nombre ?? "").split(separator: " ").first.map(String.init) ?? ""
        return p == p.uppercased() ? p.localizedCapitalized : p
    }
}

struct FilaEjercicio: View {
    let ejercicio: Ejercicio
    let numero: Int
    let semana: Int
    let resumen: ResumenHistorial?

    var body: some View {
        let pauta = Progresiones.pauta(ejercicio, semana: semana)
        HStack(alignment: .top, spacing: 12) {
            Miniatura(url: ejercicio.imagenes?.eccentric, tipo: ejercicio.tipo)
            VStack(alignment: .leading, spacing: 6) {
                Text(ejercicio.nombre).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if ejercicio.tipo == "calentamiento" || ejercicio.tipo == "cardio" {
                        Chip(texto: ejercicio.tipo == "cardio" ? "Cardio" : "Calent.", tono: .alerta)
                    }
                    if let s = pauta.series, let r = pauta.reps { Chip(texto: "\(s) × \(r)") }
                    else if let r = pauta.reps { Chip(texto: r) }
                    if let rir = pauta.rir { Chip(texto: "RIR \(rir)") }
                    if let d = ejercicio.descansoSegundos, d > 0 { Chip(texto: mmss(d), icono: "timer") }
                }
                if let r = resumen, let s = r.ultima.last {
                    HStack(spacing: 6) {
                        // Peso corporal (0 kg): como en la web, sin columna de kilos.
                        Text("Última: \(cargaTexto(s)) · \(Fechas.haceCuanto(r.ultimaFecha))")
                        if let rec = r.recordKg, rec > 0 {
                            Label("\(rec.kg) kg", systemImage: "trophy.fill").labelStyle(.titleAndIcon).foregroundStyle(Color.alerta)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Primera vez con este ejercicio").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .tarjeta(relleno: 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ejercicio \(numero): \(ejercicio.nombre)")
    }
}

struct Miniatura: View {
    let url: String?
    let tipo: String?

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { fase in
                    if let img = fase.image { img.resizable().scaledToFill() } else { marcador }
                }
            } else { marcador }
        }
        .frame(width: 60, height: 60)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    private var marcador: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: tipo == "cardio" ? "figure.run" : (tipo == "core" ? "figure.core.training" : "dumbbell.fill"))
                .foregroundStyle(.secondary)
        }
    }
}

func mmss(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

/// "52,5 kg × 7" o, si fue con el peso del cuerpo, "12 reps".
func cargaTexto(_ r: RegistroHistorico) -> String {
    if let kg = r.pesoKg, kg > 0 { return "\(kg.kg) kg × \(r.reps ?? 0)" }
    return "\(r.reps ?? 0) reps"
}
