import SwiftUI
import Charts
import MyPumpModelos
import MyPumpReglas

/// Progreso (PRO-01…05): totales arriba y, por día, cada ejercicio una sola vez (por clave, no por lugar) con su
/// máximo por sesión, la variación, el PR y una curva chica. Tocar abre el detalle con el gráfico y la tabla.
struct ProgresoView: View {
    let datos: Muestras
    @Environment(\.horizontalSizeClass) private var claseAncho
    @State private var ruta: [LineaProgreso] = []

    struct Seccion: Identifiable {
        let id: String
        let titulo: String
        let lineas: [LineaProgreso]
    }

    /// Una sección por día de la rutina; un ejercicio que se repite entre días aparece solo en el primero.
    private var secciones: [Seccion] {
        var vistas = Set<String>()
        return (datos.rutina?.estructura.dias ?? []).enumerated().compactMap { i, dia in
            let lineas = dia.bloques.flatMap(\.ejercicios).compactMap { e -> LineaProgreso? in
                let clave = ClaveEjercicio.de(e.nombre)
                guard !vistas.contains(clave), let filas = datos.historialPorClave[clave], !filas.isEmpty else { return nil }
                vistas.insert(clave)
                // Con el peso del cuerpo no hay kilos que graficar: como en la web, no entra.
                let linea = LineaProgreso(clave: clave, nombre: e.nombre, filas: filas)
                return linea.sesiones.isEmpty ? nil : linea
            }
            guard !lineas.isEmpty else { return nil }
            let n = dia.nombre ?? "Día \(i + 1)"
            return Seccion(id: dia.id ?? "\(i)", titulo: n == n.uppercased() ? n.localizedCapitalized : n, lineas: lineas)
        }
    }

    var body: some View {
        NavigationStack(path: $ruta) {
            contenido
                .background(Color.fondo)
                .navigationTitle("Progreso")
                .navigationDestination(for: LineaProgreso.self) { ProgresoDetalleView(linea: $0) }
        }
        .onAppear {
            if DemoUI.abrir == "detalle", ruta.isEmpty, let primera = secciones.first?.lineas.first { ruta = [primera] }
        }
    }

    @ViewBuilder private var contenido: some View {
        let ss = secciones
        switch DemoUI.estado {
        case .cargando:
            ScrollView { EsqueletoProgreso().padding(.horizontal, Espacio.m).anchoLectura() }.scrollDisabled(true)
        case .error:
            ContentUnavailableView {
                Label("No pudimos traer tu historial", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Revisá la conexión y probá de nuevo.")
            } actions: {
                Button("Reintentar") {}.buttonStyle(BotonMarca(compacto: true))
            }
        case .vacio:
            vacio
        case nil:
            if ss.isEmpty { vacio } else { lista(ss) }
        }
    }

    private var vacio: some View {
        ContentUnavailableView {
            Label("Aún no hay historial", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Cuando registres tus primeras series, acá vas a ver cómo suben tus cargas sesión a sesión.")
        }
    }

    private func lista(_ ss: [Seccion]) -> some View {
        let ejercicios = ss.reduce(0) { $0 + $1.lineas.count }
        let sesiones = Set(datos.historial.map { String($0.registradoEn.prefix(10)) }).count
        let columnas = claseAncho == .regular
            ? [GridItem(.flexible(), spacing: Espacio.l, alignment: .top), GridItem(.flexible(), spacing: Espacio.l, alignment: .top)]
            : [GridItem(.flexible(), alignment: .top)]
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                // Con letra de accesibilidad los totales van uno debajo del otro (no se cortan las palabras).
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Espacio.s) { totales(ejercicios, sesiones) }
                    VStack(spacing: Espacio.s) { totales(ejercicios, sesiones) }
                }
                LazyVGrid(columns: columnas, alignment: .leading, spacing: Espacio.l) {
                    ForEach(ss) { s in seccion(s) }
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura(claseAncho == .regular ? Ancho.doble : Ancho.lectura)
        }
    }

    @ViewBuilder
    private func totales(_ ejercicios: Int, _ sesiones: Int) -> some View {
        Dato(titulo: "Ejercicios", valor: "\(ejercicios)", icono: "dumbbell.fill")
        Dato(titulo: "Sesiones", valor: "\(sesiones)", icono: "calendar")
    }

    private func seccion(_ s: Seccion) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: s.titulo, detalle: "\(s.lineas.count)")
            VStack(spacing: 0) {
                ForEach(Array(s.lineas.enumerated()), id: \.element.id) { i, l in
                    NavigationLink(value: l) { FilaProgreso(linea: l) }
                        .buttonStyle(FilaPresionable())
                    if i < s.lineas.count - 1 { Divider().padding(.leading, Espacio.m) }
                }
            }
            .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .superficieTarjeta()
        }
    }
}

/// Un ejercicio con su historial por sesión (el máximo de cada día, las últimas 8).
struct LineaProgreso: Identifiable, Hashable {
    let clave: String
    let nombre: String
    let sesiones: [SesionProgreso]
    var id: String { clave }

    struct SesionProgreso: Identifiable, Hashable {
        let fecha: Date
        let kg: Double
        let reps: Int?
        let rir: Int?
        var id: Date { fecha }
    }

    init(clave: String, nombre: String, filas: [RegistroHistorico]) {
        self.clave = clave
        self.nombre = nombre
        let porDia = Dictionary(grouping: filas) { String($0.registradoEn.prefix(10)) }
        let todas = porDia.compactMap { dia, fs -> SesionProgreso? in
            guard let f = Fechas.dia(dia), let mejor = fs.max(by: { ($0.pesoKg ?? 0) < ($1.pesoKg ?? 0) }),
                  let kg = mejor.pesoKg, kg > 0 else { return nil }
            return SesionProgreso(fecha: f, kg: kg, reps: mejor.reps, rir: mejor.rir)
        }
        sesiones = Array(todas.sorted { $0.fecha < $1.fecha }.suffix(8))
    }

    var ultimo: Double { sesiones.last?.kg ?? 0 }
    var primero: Double { sesiones.first?.kg ?? 0 }
    var record: Double { sesiones.map(\.kg).max() ?? 0 }
    /// PR: la última sesión superó a todas las anteriores.
    var esPR: Bool { sesiones.count > 1 && ultimo > (sesiones.dropLast().map(\.kg).max() ?? 0) }
    /// Variación de la primera a la última de las 8 (no invertida).
    var delta: Double { primero > 0 ? (ultimo - primero) / primero * 100 : 0 }

    static func == (a: Self, b: Self) -> Bool { a.clave == b.clave }
    func hash(into h: inout Hasher) { h.combine(clave) }
}

private struct FilaProgreso: View {
    let linea: LineaProgreso
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        let nombre = NombreEjercicio(linea.nombre)
        let grande = tamañoLetra.isAccessibilitySize
        let disposicion = grande
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
        disposicion {
            VStack(alignment: .leading, spacing: 4) {
                Text(nombre.principal)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(grande ? nil : 2)
                if let d = nombre.detalle {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(grande ? nil : 1)
                }
                FilaFluida(espaciado: 6, interlineado: 4) {
                    if linea.esPR { InsigniaPR(compacta: true) }
                    Text("\(linea.ultimo.kg) kg").font(.numeroChico).foregroundStyle(.primary)
                    PildoraVariacion(delta: linea.delta)
                }
                .padding(.top, 2)
            }
            if !grande { Spacer(minLength: Espacio.xs) }
            CurvaChica(sesiones: linea.sesiones, esPR: linea.esPR)
                .frame(width: grande ? nil : 84, height: grande ? 56 : 44)
                .frame(maxWidth: grande ? .infinity : nil)
        }
        .padding(.leading, Espacio.m)
        .padding(.trailing, Espacio.m + 18)
        .padding(.vertical, 14)
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, Espacio.m)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(linea.nombre): \(linea.ultimo.kg) kilos, \(Int(linea.delta.rounded())) por ciento\(linea.esPR ? ", récord" : "")")
    }
}

/// "+12 %" verde si sube, rojo si baja (sin invertir: más kilos es mejor).
struct PildoraVariacion: View {
    let delta: Double

    var body: some View {
        let n = Int(delta.rounded())
        Label("\(n > 0 ? "+" : "")\(n) %", systemImage: n > 0 ? "arrow.up.right" : (n < 0 ? "arrow.down.right" : "equal"))
            .labelStyle(EtiquetaCompacta())
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(n > 0 ? Color.exito : (n < 0 ? Color.peligro : Color.secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background((n > 0 ? Color.exito : (n < 0 ? Color.peligro : Color.secondary)).opacity(0.12), in: .capsule)
    }
}

/// Insignia de récord personal: trofeo en lima con texto negro. `compacta`: solo el trofeo (en las filas).
struct InsigniaPR: View {
    var compacta = false
    @ScaledMetric(relativeTo: .caption2) private var lado: CGFloat = 22

    var body: some View {
        Group {
            if compacta {
                Image(systemName: "trophy.fill")
                    .font(.caption2.weight(.bold))
                    .frame(width: lado, height: lado)
                    .background(Color.marca, in: .circle)
            } else {
                Label("PR", systemImage: "trophy.fill")
                    .labelStyle(EtiquetaCompacta())
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.marca, in: .capsule)
            }
        }
        .foregroundStyle(Color.sobreMarca)
        .accessibilityLabel("Récord personal")
    }
}

/// La curva chica de la fila: área con degradado, línea y el último punto marcado.
private struct CurvaChica: View {
    let sesiones: [LineaProgreso.SesionProgreso]
    var esPR = false

    var body: some View {
        let minimo = (sesiones.map(\.kg).min() ?? 0), maximo = (sesiones.map(\.kg).max() ?? 1)
        let margen = max((maximo - minimo) * 0.25, 0.5)
        Chart {
            ForEach(sesiones) { s in
                AreaMark(x: .value("Fecha", s.fecha), yStart: .value("Base", minimo - margen), yEnd: .value("Kg", s.kg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.marcaVivo.opacity(0.3), Color.marcaVivo.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Fecha", s.fecha), y: .value("Kg", s.kg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.marcaVivo)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let u = sesiones.last {
                // El último punto en oro si es récord: la marca va pegada al dato.
                PointMark(x: .value("Fecha", u.fecha), y: .value("Kg", u.kg))
                    .symbolSize(esPR ? 40 : 28)
                    .foregroundStyle(esPR ? Color.record : Color.marcaVivo)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (minimo - margen)...(maximo + margen))
        .accessibilityHidden(true)
    }
}

private struct EsqueletoProgreso: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.l) {
            HStack(spacing: Espacio.s) {
                ForEach(0..<3, id: \.self) { _ in Dato(titulo: "Ejercicios", valor: "30", icono: "dumbbell.fill") }
            }
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Espacio.s) {
                    Text("Tirón").font(.title3.weight(.bold))
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nombre del ejercicio").font(.subheadline.weight(.semibold))
                                    Text("58 kg · +12 %").font(.caption)
                                }
                                Spacer()
                                RoundedRectangle(cornerRadius: 6).fill(Color.campo).frame(width: 92, height: 44)
                            }
                            .padding(Espacio.m)
                        }
                    }
                    .superficieTarjeta()
                }
            }
        }
        .padding(.top, Espacio.xs)
        .esqueleto()
    }
}
