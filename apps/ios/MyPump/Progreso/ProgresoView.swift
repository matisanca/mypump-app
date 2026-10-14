import SwiftUI
import Charts
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Progreso (PRO-01…05): totales arriba y, por día, cada ejercicio una sola vez (por clave, no por lugar) con el tope
/// de sus últimas 8 sesiones, la variación, el 🏆 PR y una curva chica. Tocar abre el detalle con el gráfico y la
/// tabla. Con una cuenta sale de `ModeloProgreso` (se carga al abrir la pestaña); en la demo y en los bocetos, de las
/// muestras con las mismas reglas.
struct ProgresoView: View {
    let datos: Muestras
    @State private var modelo = Proveedor.modelo
    @Environment(\.horizontalSizeClass) private var claseAncho
    @State private var ruta: [LineaProgreso] = []
    @State private var abrioDetalle = false

    private var progreso: ModeloProgreso? { modelo.conMuestras ? nil : modelo.progreso }

    struct Seccion: Identifiable {
        let id: String
        let titulo: String
        let lineas: [LineaProgreso]
    }

    private var lineas: [LineaProgreso] {
        if let progreso { return progreso.tarjetas.map(LineaProgreso.init) }
        return LineaProgreso.desdeMuestras(datos)
    }

    private var sesiones: Int {
        if let progreso { return progreso.sesiones }
        return ProgresoEjercicio.sesiones(datos.historial).count
    }

    /// Agrupadas por los días donde aparece cada ejercicio ("Tirón", o "Tirón · Torso" si está en los dos), en el orden
    /// de la rutina, como la web.
    private func secciones(_ ls: [LineaProgreso]) -> [Seccion] {
        var orden: [String] = []
        var porDias: [String: [LineaProgreso]] = [:]
        for l in ls {
            if porDias[l.dias] == nil { orden.append(l.dias) }
            porDias[l.dias, default: []].append(l)
        }
        return orden.map { d in
            let titulo = d.components(separatedBy: " · ").map { $0 == $0.uppercased() ? $0.localizedCapitalized : $0 }
                .joined(separator: " · ")
            return Seccion(id: d, titulo: titulo, lineas: porDias[d] ?? [])
        }
    }

    var body: some View {
        NavigationStack(path: $ruta) {
            contenido
                .background(Color.fondo)
                .navigationTitle("Progreso")
                .navigationDestination(for: LineaProgreso.self) { ProgresoDetalleView(linea: $0) }
        }
        .task {
            // Al abrir la pestaña (como la web); si ya está, se actualiza tirando para abajo.
            guard let progreso, progreso.tarjetas.isEmpty || progreso.estado == .sinRed else { return }
            await progreso.cargar(rutina: modelo.rutina)
        }
        // Capturas: `-abrir detalle` entra al primer ejercicio apenas hay datos (una sola vez).
        .onChange(of: lineas.count, initial: true) { _, n in
            guard DemoUI.abrir == "detalle", !abrioDetalle, n > 0, let primera = lineas.first else { return }
            abrioDetalle = true
            ruta = [primera]
        }
    }

    @ViewBuilder private var contenido: some View {
        let ls = lineas
        if DemoUI.estado == .cargando || (progreso?.estado == .cargando && ls.isEmpty) {
            ScrollView { EsqueletoProgreso().padding(.horizontal, Espacio.m).anchoLectura() }.scrollDisabled(true)
        } else if DemoUI.estado == .error || (progreso?.estado == .sinRed && ls.isEmpty) {
            ContentUnavailableView {
                Label("No pudimos traer tu historial", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Sin conexión. Revisá la señal y probá de nuevo.")
            } actions: {
                Button("Reintentar") { Task { await progreso?.cargar(rutina: modelo.rutina) } }
                    .buttonStyle(BotonMarca(compacto: true))
            }
        } else if DemoUI.estado == .vacio || ls.isEmpty {
            ContentUnavailableView {
                Label("Aún no hay historial", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Aún no hay historial registrado. Empezá tu primera sesión para ver el progreso acá.")
            }
        } else {
            lista(secciones(ls), ejercicios: ls.count)
        }
    }

    private func lista(_ ss: [Seccion], ejercicios: Int) -> some View {
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
        .refreshable { await progreso?.cargar(rutina: modelo.rutina) }
    }

    @ViewBuilder
    private func totales(_ ejercicios: Int, _ sesiones: Int) -> some View {
        Dato(titulo: "Ejercicios", valor: "\(ejercicios)", icono: "dumbbell.fill")
        Dato(titulo: "Sesiones", valor: "\(sesiones)", icono: "calendar")
    }

    private func seccion(_ s: Seccion) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: s.titulo, detalle: "máx. por sesión")
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

/// Un ejercicio de Progreso, igual venga de la cuenta (`TarjetaProgreso`) o de las muestras.
struct LineaProgreso: Identifiable, Hashable {
    let id: String
    let nombre: String
    /// "Tirón · Torso": los días donde aparece.
    let dias: String
    let resumen: ProgresoEjercicio.Resumen
    /// Los registros de la más nueva a la más vieja: el detalle muestra 8.
    let filas: [RegistroHistorico]
    /// El máximo de cada sesión con su fecha (las 8 más recientes): los mismos valores que `resumen.serie`.
    let sesiones: [SesionProgreso]

    struct SesionProgreso: Identifiable, Hashable {
        let fecha: Date
        let kg: Double
        var id: Date { fecha }
    }

    init(id: String, nombre: String, dias: String, resumen: ProgresoEjercicio.Resumen, filas: [RegistroHistorico]) {
        self.id = id
        self.nombre = nombre
        self.dias = dias
        self.resumen = resumen
        self.filas = filas
        var porFecha: [String: Double] = [:]
        for f in filas {
            let fecha = FechaLocal.de(f.registradoEn)
            guard !fecha.isEmpty else { continue }
            porFecha[fecha] = max(porFecha[fecha] ?? -1, f.pesoKg ?? 0)
        }
        sesiones = porFecha.keys.sorted().suffix(8).compactMap { d in
            Fechas.dia(d).map { SesionProgreso(fecha: $0, kg: porFecha[d] ?? 0) }
        }
    }

    init(_ t: TarjetaProgreso) {
        self.init(id: t.id, nombre: t.nombre, dias: t.dias, resumen: t.resumen, filas: t.filas)
    }

    /// Lo mismo que hace `ModeloProgreso.cargar` (una entrada por clave, sin calentamientos, con los días donde
    /// aparece), pero con la rutina y el historial de las muestras.
    static func desdeMuestras(_ datos: Muestras) -> [LineaProgreso] {
        var orden: [String] = []
        var entradas: [String: (id: String, nombre: String, dias: [String])] = [:]
        for (i, d) in (datos.rutina?.estructura.dias ?? []).enumerated() {
            let dia = d.nombre.flatMap { $0.isEmpty ? nil : $0 } ?? "Día \(d.n ?? i + 1)"
            for e in d.bloques.flatMap(\.ejercicios) where e.tipo != "calentamiento" {
                let c = ClaveEjercicio.de(e.nombre)
                let clave = c.isEmpty ? e.id : c
                if var x = entradas[clave] {
                    if !x.dias.contains(dia) { x.dias.append(dia) }
                    entradas[clave] = x
                } else {
                    entradas[clave] = (e.id, e.nombre, [dia])
                    orden.append(clave)
                }
            }
        }
        let historial = datos.historialPorClave
        return orden.compactMap { clave in
            guard let e = entradas[clave], let filas = historial[clave], let r = ProgresoEjercicio.resumen(filas) else { return nil }
            let recientes = filas.sorted { $0.registradoEn > $1.registradoEn }
            return LineaProgreso(id: e.id, nombre: e.nombre, dias: e.dias.joined(separator: " · "), resumen: r, filas: recientes)
        }
    }

    /// Con el peso del cuerpo no hay kilos: el tope es 0.
    var conPeso: Bool { resumen.tope > 0 }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
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
                    if linea.resumen.esPR { InsigniaPR(compacta: true) }
                    if linea.conPeso {
                        Text("\(Text("Top").font(.caption.weight(.semibold)).foregroundStyle(.secondary)) \(linea.resumen.tope.kg) kg")
                            .font(.numeroChico)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Peso corporal").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    PildoraVariacion(variacion: linea.resumen.variacion)
                }
                .padding(.top, 2)
            }
            if !grande { Spacer(minLength: Espacio.xs) }
            CurvaChica(valores: linea.resumen.serie, esPR: linea.resumen.esPR)
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
        .accessibilityLabel(accesible)
    }

    private var accesible: String {
        var s = "\(linea.nombre): tope \(linea.resumen.tope.kg) kilos"
        if let v = linea.resumen.variacion { s += ", \(PildoraVariacion.texto(v)) de progresión" }
        if linea.resumen.esPR { s += ", récord" }
        return s
    }
}

/// "+12,3 %" verde si sube, rojo si baja (sin invertir: más kilos es mejor); "—" con una sola sesión.
struct PildoraVariacion: View {
    let variacion: Double?

    var body: some View {
        if let v = variacion {
            let color = v > 0 ? Color.exito : (v < 0 ? Color.peligro : Color.secondary)
            Label(Self.texto(v), systemImage: v > 0 ? "arrow.up.right" : (v < 0 ? "arrow.down.right" : "equal"))
                .labelStyle(EtiquetaCompacta())
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: .capsule)
        } else {
            Text("—").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    /// "+12,3 %", con la coma argentina y un decimal (como `toFixed(1)` de la web).
    static func texto(_ v: Double) -> String {
        let n = v.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "es_AR")))
        return "\(v > 0 ? "+" : "")\(n) %"
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

/// La curva chica de la fila (el máximo por sesión): área con degradado, línea y el último punto marcado (en oro si es
/// récord).
private struct CurvaChica: View {
    let valores: [Double]
    var esPR = false

    var body: some View {
        let minimo = valores.min() ?? 0, maximo = valores.max() ?? 1
        let margen = max((maximo - minimo) * 0.25, 0.5)
        Chart {
            ForEach(Array(valores.enumerated()), id: \.offset) { i, kg in
                AreaMark(x: .value("Sesión", i), yStart: .value("Base", minimo - margen), yEnd: .value("Kg", kg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(LinearGradient(colors: [Color.marcaVivo.opacity(0.3), Color.marcaVivo.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Sesión", i), y: .value("Kg", kg))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.marcaVivo)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let u = valores.last {
                PointMark(x: .value("Sesión", valores.count - 1), y: .value("Kg", u))
                    .symbolSize(esPR ? 40 : 28)
                    .foregroundStyle(esPR ? Color.record : Color.marcaVivo)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(valores.count - 1, 1))
        .chartYScale(domain: (minimo - margen)...(maximo + margen))
        .accessibilityHidden(true)
    }
}

private struct EsqueletoProgreso: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.l) {
            HStack(spacing: Espacio.s) {
                ForEach(0..<2, id: \.self) { _ in Dato(titulo: "Ejercicios", valor: "30", icono: "dumbbell.fill") }
            }
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Espacio.s) {
                    Text("Tirón").font(.title3.weight(.bold))
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { _ in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Nombre del ejercicio").font(.subheadline.weight(.semibold))
                                    Text("Top 58 kg · +12 %").font(.caption)
                                }
                                Spacer()
                                RoundedRectangle(cornerRadius: 6).fill(Color.campo).frame(width: 84, height: 44)
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
