import SwiftUI
import MyPumpReglas
import MyPumpReloj

/// Adónde se navega: el día (la lista de ejercicios) y un ejercicio de ese día.
enum PasoReloj: Hashable {
    case dia
    case ejercicio(String)
}

struct RaizReloj: View {
    @Environment(EstadoReloj.self) private var estado
    @State private var camino: [PasoReloj] = []
    @State private var preparado = false

    var body: some View {
        NavigationStack(path: $camino) {
            Group {
                if estado.sesion.rutina == nil { SinRutina() } else { ListaDias() }
            }
            .navigationDestination(for: PasoReloj.self) { paso in
                switch paso {
                case .dia: ListaDia()
                case .ejercicio(let l): EjercicioVista(lugar: l)
                }
            }
        }
        // Llegó el día elegido (o se tocó el que ya estaba): se entra.
        .onChange(of: estado.abrirDia) { camino = [.dia] }
        .fullScreenCover(isPresented: Binding(get: { estado.sesion.descanso != nil && estado.resumen == nil },
                                              set: { if !$0 { estado.saltarDescanso() } })) {
            DescansoVista()
        }
        .sheet(isPresented: Binding(get: { estado.resumen != nil }, set: { if !$0 { estado.resumen = nil } })) {
            if let r = estado.resumen { ResumenVista(resumen: r) }
        }
        .onAppear(perform: pantallaDePrueba)
    }

    /// `-pantalla …` (simulador y capturas): deja la demo en una pantalla.
    private func pantallaDePrueba() {
        guard !preparado else { return }
        preparado = true
        // Con el entreno empezado se abre directo en el día (no se puede cambiar).
        if estado.sesion.rutina != nil, !estado.sesion.puedeCambiarDia { camino = [.dia] }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-pantalla"), i + 1 < args.count else { return }
        switch args[i + 1] {
        case "lista":
            camino = [.dia]
        case "sin-iphone":
            // La lista de días con el aviso de que para cambiar hace falta el iPhone.
            estado.elegirDia("d2", demoSinIPhone: true)
        case "ejercicio", "preparacion":
            if let l = estado.sesion.lugar { camino = [.dia, .ejercicio(l)] }
        case "progreso":
            estado.empezar()
            estado.confirmar(); estado.saltarDescanso()
            estado.girarKg(1); estado.confirmar(); estado.saltarDescanso()
            if let l = estado.sesion.lugar { camino = [.dia, .ejercicio(l)] }
        case "descanso":
            camino = [.dia]
            estado.empezar()
            estado.confirmar()
        case "resumen":
            estado.empezar()
            estado.girarKg(1)
            for _ in 0..<20 { estado.confirmar(); estado.saltarDescanso() }
            estado.terminar()
        default: break
        }
    }
}

// MARK: - Sin rutina

struct SinRutina: View {
    @Environment(EstadoReloj.self) private var estado
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 34))
                    .foregroundStyle(Marca.verde)
                Text(estado.incompatible != nil ? "Actualizá Pump Team" : "Abrí Pump Team en el iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(estado.incompatible
                     ?? 
                     (estado.sinRutina ?? "Para traer tu rutina de hoy. Después podés entrenar sin el teléfono."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Los días de la semana

/// La semana del plan, como el selector de días del iPhone: se elige el día con un toque. El «de hoy» (o el próximo,
/// si el de hoy ya está hecho) va marcado. Solo el día que mandó el iPhone tiene rutina: otro se le pide al iPhone, que
/// lo abre también en Entreno. Con el entreno empezado no se cambia de día.
struct ListaDias: View {
    @Environment(EstadoReloj.self) private var estado

    var body: some View {
        let s = estado.sesion
        let r = s.rutina!
        let sugerido = r.diaSugerido
        ScrollViewReader { lector in
            List {
                if let t = estado.incompatible {
                    Section { Label(t, systemImage: "arrow.down.app").font(.footnote).foregroundStyle(Marca.oro) }
                }
                if let a = s.avisoDia {
                    Section {
                        Label(a, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Marca.oro)
                        Button("Entendido") { estado.leerAvisoDia() }
                    }
                }
                Section {
                    ForEach(r.diasParaElegir) { d in
                        let abierto = d.id == r.diaId
                        Button { estado.elegirDia(d.id) } label: {
                            FilaDia(d: d, marca: d.id == sugerido ? (abierto ? "Hoy" : "Próximo") : nil, pidiendo: s.diaPedido == d.id)
                        }
                        .disabled(!abierto && (!s.puedeCambiarDia || s.diaPedido != nil))
                        .listRowBackground(d.id == sugerido ? RoundedRectangle(cornerRadius: 12).fill(Marca.verde.opacity(0.22)) : nil)
                        .id(d.id)
                    }
                } footer: {
                    if let pie = pie(s, r) { Text(pie).font(.footnote) }
                }
            }
            .onAppear { lector.scrollTo(sugerido, anchor: .center) }
        }
        .navigationTitle("Elegí el día")
    }

    /// Lo que limita el cambio de día, si algo lo limita.
    private func pie(_ s: SesionReloj, _ r: RutinaReloj) -> String? {
        if !s.puedeCambiarDia { return SesionReloj.textoEmpezado }
        if r.dias == nil { return "Actualizá Pump Team en el iPhone para elegir otro día." }
        if !estado.conectado && !r.demo { return SesionReloj.textoSinIPhone }
        return nil
    }
}

struct FilaDia: View {
    let d: DiaReloj
    /// «Hoy» o «Próximo».
    let marca: String?
    let pidiendo: Bool
    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("Día \(d.numero)")
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    if let marca {
                        Text(marca)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 5)
                            .background(Capsule().fill(Marca.verde))
                    }
                }
                Text(TextoReloj.titulo(d.nombre)).font(.headline).lineLimit(2)
                Text(d.ejercicios == 1 ? "1 ejercicio" : "\(d.ejercicios) ejercicios")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if pidiendo {
                ProgressView().frame(width: 20)
            } else if d.hecho {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Marca.verde)
                    .accessibilityLabel("Hecho esta semana")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - La rutina del día

struct ListaDia: View {
    @Environment(EstadoReloj.self) private var estado

    var body: some View {
        let s = estado.sesion
        let r = s.rutina!
        let hechos = r.ejercicios.filter(\.terminado).count
        List {
            if !s.rechazos.isEmpty {
                Section {
                    ForEach(Array(s.rechazos.enumerated()), id: \.offset) { _, t in
                        Label(t, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Marca.oro)
                    }
                    Button("Entendido") { estado.leerRechazos() }
                }
            }
            if let t = estado.incompatible {
                Section { Label(t, systemImage: "arrow.down.app").font(.footnote).foregroundStyle(Marca.oro) }
            }
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TextoReloj.titulo(r.nombreDia))
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    Text(s.todoHecho ? "Hecho" : "\(hechos) de \(r.ejercicios.count) ejercicios")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                if !s.iniciada && !s.terminada {
                    Button { estado.empezar() } label: {
                        Label("Empezar", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .tint(Marca.verde)
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                } else if s.iniciada && !s.terminada {
                    LineaSalud()
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                ForEach(r.ejercicios, id: \.lugar) { e in
                    NavigationLink(value: PasoReloj.ejercicio(e.lugar)) { FilaEjercicio(e: e, actual: e.lugar == s.lugar) }
                }
            }
            if s.iniciada && !s.terminada {
                Section {
                    Button(role: .destructive) { estado.terminar() } label: {
                        Label("Terminar", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                }
            }
            if let t = s.resumen(ahora: EstadoReloj.ahoraMs).textoSinEnviar {
                Section {
                    Label(t, systemImage: "arrow.triangle.2.circlepath").font(.footnote).foregroundStyle(.secondary)
                    // Por qué el iPhone todavía no lo pasó (otra cuenta, otro día abierto, sin conexión…).
                    if let e = s.esperando { Text(e).font(.footnote).foregroundStyle(.secondary) }
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Hoy")
    }
}

struct FilaEjercicio: View {
    let e: EjercicioReloj
    let actual: Bool
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.35), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: e.series.isEmpty ? (e.terminado ? 1 : 0) : Double(e.confirmadas) / Double(e.series.count))
                    .stroke(Marca.verde, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if e.terminado {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Marca.verde)
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.nombre).font(.body.weight(actual ? .semibold : .regular)).lineLimit(2)
                Text("\(e.confirmadas)/\(e.series.count) series" + (e.repsPlan.map { " · \($0)" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// «♥ 128 · 85 kcal» mientras corre la sesión de entreno.
struct LineaSalud: View {
    @Environment(EstadoReloj.self) private var estado
    var body: some View {
        let s = estado.salud
        HStack(spacing: 10) {
            Label(s.fcActual.map { "\(Int($0.rounded()))" } ?? "—", systemImage: "heart.fill")
                .foregroundStyle(.red)
            Label(s.kcal.map { "\(Int($0.rounded())) kcal" } ?? "— kcal", systemImage: "flame.fill")
                .foregroundStyle(.orange)
        }
        .font(.footnote.monospacedDigit())
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - El ejercicio con la corona

struct EjercicioVista: View {
    let lugar: String
    @Environment(EstadoReloj.self) private var estado
    @Environment(\.dismiss) private var cerrar
    enum Campo { case reps, kg }
    @State private var foco: Campo = .reps
    @State private var corona = 0.0
    @FocusState private var enfocado: Bool

    var body: some View {
        let s = estado.sesion
        if let e = s.ejercicio(lugar) {
            ScrollViewReader { lector in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(e.nombre).font(.headline).lineLimit(3)
                    if let i = e.proximaSerie {
                        Text("Serie \(i + 1) de \(e.series.count)" + (e.repsPlan.map { " · objetivo \($0)" } ?? ""))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        // Flujo final (apagado): el reloj propone lo que contó.
                        if let n = estado.propuesta {
                            Text(ConfirmacionReps.texto(n)).font(.headline).foregroundStyle(Marca.verde)
                        }
                        if estado.calibrando { LineaCalibracion() }
                        HStack(spacing: 6) {
                            CampoCorona(titulo: "Reps", valor: "\(s.reps)", activo: foco == .reps) { foco = .reps }
                            if !e.sinKg {
                                CampoCorona(titulo: "Kg", valor: TextoReloj.kg(s.kg), activo: foco == .kg) { foco = .kg }
                            }
                        }
                        Button { estado.confirmar() } label: {
                            Label("Confirmar serie", systemImage: "checkmark").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Marca.verde)
                    } else {
                        Label("Ejercicio hecho", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Marca.verde)
                    }
                    if let r = estado.avisoRecord {
                        Label(r, systemImage: "trophy.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Marca.oro)
                    }
                    if s.iniciada && !s.terminada { LineaSalud() }
                    PreparacionVista(lugar: lugar, ejercicio: e).id("prep")
                    SeriesHechas(e: e)
                }
            }
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("preparacion") {
                    Task { try? await Task.sleep(for: .milliseconds(600)); lector.scrollTo("prep", anchor: .top) }
                }
            }
            }
            .focusable(true)
            .focused($enfocado)
            .digitalCrownRotation($corona, from: -10_000, through: 10_000, by: 1, sensitivity: .low, isContinuous: true,
                                  isHapticFeedbackEnabled: true)
            .onChange(of: corona) { viejo, nuevo in
                let d = Int(nuevo.rounded()) - Int(viejo.rounded())
                guard d != 0 else { return }
                if foco == .reps || e.sinKg { estado.girarReps(d) } else { estado.girarKg(d) }
            }
            .onAppear {
                estado.elegir(lugar)
                enfocado = true
            }
            .navigationTitle(e.bloque ?? "Serie")
        }
    }
}

struct CampoCorona: View {
    let titulo: String
    let valor: String
    let activo: Bool
    let tocar: () -> Void
    var body: some View {
        Button(action: tocar) {
            VStack(spacing: 0) {
                Text(valor)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(titulo).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(activo ? 0.14 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(activo ? Marca.verde : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(titulo): \(valor)")
        .accessibilityHint(activo ? "Girá la corona para cambiarlo" : "Tocá para cambiarlo con la corona")
    }
}

/// La preparación de E1 como en el teléfono: solo una indicación, no se registra.
struct PreparacionVista: View {
    let lugar: String
    let ejercicio: EjercicioReloj
    @Environment(EstadoReloj.self) private var estado
    var body: some View {
        let p = estado.sesion.preparacion(lugar)
        if !p.isEmpty && ejercicio.confirmadas == 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Preparación").font(.footnote.weight(.semibold)).foregroundStyle(Marca.verde)
                ForEach(Array(p.enumerated()), id: \.offset) { _, serie in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(serie.etiqueta).font(.caption2).foregroundStyle(.secondary)
                        Text(TextoReloj.preparacion(serie)).font(.footnote.weight(.semibold).monospacedDigit())
                    }
                }
                Text(p.contains { $0.kg != nil } ? "Solo indicación: no se registra." : MyPumpReglas.Preparacion.textoSinKg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
    }
}

struct SeriesHechas: View {
    let e: EjercicioReloj
    var body: some View {
        let hechas = e.series.filter(\.confirmada)
        if !hechas.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(hechas, id: \.numero) { s in
                    HStack {
                        Text("\(s.numero)").font(.caption2).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
                        Text(e.sinKg ? "\(s.reps ?? 0) reps" : "\(s.reps ?? 0) × \(TextoReloj.kg(s.kg)) kg")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Image(systemName: "checkmark").font(.caption2).foregroundStyle(Marca.verde)
                    }
                }
            }
        }
    }
}

/// Tanda 4, modo calibración: «● Conté 7» mientras va la serie (el contador experimental; no cambia lo que cargás) y
/// la comparación de la última serie confirmada.
struct LineaCalibracion: View {
    @Environment(EstadoReloj.self) private var estado
    var body: some View {
        let c = estado.calibracion
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Circle().fill(c.grabando ? Color.red : Color.secondary).frame(width: 6, height: 6)
                Text(c.contadas.map { "Conté \($0)" } ?? (c.grabando ? "Contando…" : "Calibración"))
                    .font(.footnote.weight(.semibold).monospacedDigit())
            }
            if let u = c.ultimaComparacion {
                Text(u).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(c.contadas.map { "Modo calibración. El reloj contó \($0) repeticiones" } ?? "Modo calibración")
    }
}

// MARK: - Descanso

struct DescansoVista: View {
    @Environment(EstadoReloj.self) private var estado
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { contexto in
            let ahora = contexto.date.timeIntervalSince1970 * 1000
            if let d = estado.sesion.descansoEnCurso(ahora: ahora) {
                let termino = ahora >= d.fin
                VStack(spacing: 6) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: d.porcentaje(ahora: ahora) / 100)
                            .stroke(Marca.verde, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text(termino ? "¡Listo!" : d.texto(ahora: ahora))
                                .font(.system(size: termino ? 26 : 36, weight: .bold, design: .rounded).monospacedDigit())
                            Text(termino ? "A la próxima serie" : d.textoObjetivo)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: 110)
                    HStack(spacing: 6) {
                        Button("−15") { estado.ajustarDescanso(-15) }
                        Button("+15") { estado.ajustarDescanso(15) }
                        Button { estado.saltarDescanso() } label: { Image(systemName: "forward.end.fill") }
                            .accessibilityLabel("Saltar")
                    }
                    .font(.footnote.weight(.semibold))
                }
                .navigationTitle("Descanso")
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Resumen

struct ResumenVista: View {
    let resumen: ResumenReloj
    @Environment(\.dismiss) private var cerrar
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Entreno terminado", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(Marca.verde)
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    Dato(titulo: "Tiempo", valor: resumen.textoMinutos)
                    Dato(titulo: "Series", valor: "\(resumen.series)")
                    Dato(titulo: "Ejercicios", valor: "\(resumen.ejercicios) de \(resumen.total)")
                    Dato(titulo: "Volumen", valor: resumen.textoVolumen)
                    if let k = resumen.kcal { Dato(titulo: "Calorías", valor: "\(Int(k.rounded())) kcal") }
                    if let m = resumen.fcMedia { Dato(titulo: "FC media", valor: "\(Int(m.rounded())) lpm") }
                    if let m = resumen.fcMaxima { Dato(titulo: "FC máxima", valor: "\(Int(m.rounded())) lpm") }
                }
                ForEach(resumen.records, id: \.self) { r in
                    Label(r, systemImage: "trophy.fill").font(.caption).foregroundStyle(Marca.oro)
                }
                if let t = resumen.textoSinEnviar {
                    Label(t, systemImage: "arrow.triangle.2.circlepath").font(.caption2).foregroundStyle(.secondary)
                }
                Button("Listo") { cerrar() }
                    .buttonStyle(.borderedProminent)
                    .tint(Marca.verde)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct Dato: View {
    let titulo: String
    let valor: String
    var body: some View {
        GridRow {
            Text(titulo).font(.footnote).foregroundStyle(.secondary)
            Text(valor).font(.body.weight(.semibold).monospacedDigit())
        }
    }
}
