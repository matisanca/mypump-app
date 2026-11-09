import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// La tira de días de Dieta: hoy y los 7 anteriores, fija arriba. «Hoy» va primero: se abre siempre ahí.
struct SelectorDiaDieta: View {
    let fechas: [String]
    let elegida: String
    let alElegir: (String) -> Void

    var body: some View {
        let hoy = FechaLocal.hoy()
        ScrollViewReader { lector in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(fechas, id: \.self) { f in
                        let activo = f == elegida
                        Button { alElegir(f) } label: {
                            Text(DiasDieta.rotuloCorto(f, hoy: hoy))
                                .font(.subheadline.weight(activo ? .bold : .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .foregroundStyle(activo ? Color.sobreMarca : Color.primary.opacity(0.8))
                                .background(activo ? Color.marca : Color.campo, in: .capsule)
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .id(f)
                        .accessibilityLabel(f == hoy ? "Hoy" : DiasDieta.rotuloLargo(f))
                        .accessibilityAddTraits(activo ? .isSelected : [])
                        .accessibilityIdentifier("dia-\(f)")
                    }
                }
                .padding(.horizontal)
            }
            .onChange(of: elegida) { _, f in withAnimation(.snappy) { lector.scrollTo(f, anchor: .center) } }
        }
        .padding(.vertical, 2)
    }
}

/// Mirando un día anterior: de qué día se trata, a la vista todo el tiempo, y la vuelta a hoy.
struct BannerDiaPasado: View {
    let dia: DiaPasado
    let puedeMarcar: Bool
    let diasMarcar: Int
    let copiar: () -> Void
    let volver: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "calendar.badge.clock").accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Estás viendo otro día").font(.caption.weight(.semibold))
                    Text(DiasDieta.rotuloLargo(dia.fecha)).font(.headline).accessibilityIdentifier("dia-rotulo")
                }
                Spacer(minLength: 8)
            }
            HStack(spacing: 10) {
                Button(action: volver) {
                    Label("Volver a hoy", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.alerta)
                .background(Color.fondo, in: .rect(cornerRadius: 10, style: .continuous))
                .accessibilityIdentifier("volver-a-hoy")
                if !dia.cargando && !dia.sinRed {
                    Button(action: copiar) {
                        Label("Copiar a hoy", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.alerta)
                    .background(Color.fondo, in: .rect(cornerRadius: 10, style: .continuous))
                    .accessibilityIdentifier("copiar-a-hoy")
                }
            }
            if dia.otroPlan {
                Text("Ese día tenías otro plan. Acá ves el plan actual: lo que cargaste entonces queda guardado y solo podés sumar comidas libres.")
                    .font(.footnote)
                    .accessibilityIdentifier("dia-otro-plan")
            } else if !puedeMarcar {
                Text("«Comí» y «Salté» se pueden marcar hasta \(diasMarcar) días atrás. Para este día, cargá lo que comiste en «Comidas libres».")
                    .font(.footnote)
                    .accessibilityIdentifier("dia-sin-marcas")
            }
        }
        .foregroundStyle(Color.alerta)
        .padding(12)
        .background(Color.alerta.opacity(0.16), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("banner-dia-pasado")
    }
}

/// Copiar a hoy lo cargado otro día: una lista con cada comida y cada comida libre, ya tildada, para copiar el día entero o
/// solo lo que se quiera. Lo que hoy ya tiene algo viene sin tildar, y tildarlo pregunta antes de reemplazar.
struct CopiarDiaView: View {
    let modelo: ModeloApp
    @State var origen: String
    @Environment(\.dismiss) private var cerrar

    @State private var plan: CopiaDeComidas.Plan?
    @State private var sinRed = false
    @State private var elegidas: Set<String> = []
    @State private var preguntar = false
    @State private var copiando = false
    @State private var falla: ResultadoCopia?
    private var textoFalla: String {
        var p: [String] = []
        if let f = falla, f.libresFallidas > 0 { p.append("Faltaron \(f.libresFallidas) comidas libres: probá de nuevo cuando tengas señal.") }
        if let f = falla, f.saltadas > 0 { p.append("No se copiaron \(f.saltadas) comidas: cambiaron mientras elegías o no entran más alimentos agregados hoy.") }
        return p.joined(separator: " ")
    }

    private var pisan: [CopiaDeComidas.ItemComida] { (plan?.comidas ?? []).filter { elegidas.contains($0.id) && $0.estado == .conflicto } }
    private var cuantas: Int { elegidas.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SelectorDiaDieta(fechas: Array(modelo.fechasDieta.dropFirst()), elegida: origen) { origen = $0 }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Copiar desde")
                }
                contenido
            }
            .navigationTitle("Copiar a hoy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { cerrar() }.accessibilityIdentifier("copiar-cancelar")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !(plan?.vacio ?? true) {
                    Button { tocarCopiar() } label: {
                        Group {
                            if copiando { ProgressView() } else { Text(cuantas == 1 ? "Copiar 1 comida a hoy" : "Copiar \(cuantas) comidas a hoy") }
                        }
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(BotonSecundario(compacto: false))
                    .disabled(cuantas == 0 || copiando)
                    .padding()
                    .background(.bar)
                    .accessibilityIdentifier("copiar-confirmar")
                }
            }
            .confirmationDialog("¿Reemplazar lo que cargaste hoy?", isPresented: $preguntar, titleVisibility: .visible) {
                Button("Reemplazar y copiar", role: .destructive) { Task { await copiar() } }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Hoy ya tenés cargado: \(pisan.map(\.nombre).joined(separator: ", ")). Se reemplaza por lo de ese día.")
            }
            .alert("No se pudo copiar todo", isPresented: Binding(get: { falla != nil }, set: { if !$0 { falla = nil; cerrar() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(textoFalla)
            }
            .task(id: origen) { await cargar() }
        }
    }

    @ViewBuilder private var contenido: some View {
        if sinRed {
            ContentUnavailableView("Sin conexión", systemImage: "wifi.slash", description: Text("Hace falta señal para traer lo de ese día."))
        } else if let plan {
            if plan.otroPlan {
                Text("Ese día tenías otro plan: solo se pueden copiar las comidas libres.").font(.footnote).foregroundStyle(.secondary)
            }
            if plan.vacio {
                ContentUnavailableView("Nada para copiar", systemImage: "fork.knife", description: Text("Ese día no tiene comidas marcadas ni cargadas."))
                    .accessibilityIdentifier("copiar-vacio")
            }
            if !plan.comidas.isEmpty {
                Section("Comidas") {
                    ForEach(plan.comidas) { i in
                        fila(id: i.id, titulo: i.nombre, detalle: detalle(i), estado: i.estado)
                    }
                }
            }
            if !plan.libres.isEmpty {
                Section("Comidas libres") {
                    ForEach(plan.libres) { i in
                        fila(id: i.id, titulo: i.libre.descripcion ?? "", detalle: "\((i.libre.kcal ?? 0).jsEntero) kcal", estado: i.estado)
                    }
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private func detalle(_ i: CopiaDeComidas.ItemComida) -> String {
        var p = ["Opción \(i.nombreOpcion)"]
        if i.agregados > 0 { p.append("\(i.agregados) \(i.agregados == 1 ? "agregado" : "agregados")") }
        if i.conCantidades { p.append("con ajustes") }
        p.append("\(i.kcal.enteroSeguro) kcal")
        return p.joined(separator: " · ")
    }

    private func fila(id: String, titulo: String, detalle: String, estado: CopiaDeComidas.Estado) -> some View {
        let tildada = elegidas.contains(id)
        return Button {
            guard estado != .igual else { return }
            if tildada { elegidas.remove(id) } else { elegidas.insert(id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tildada ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(tildada ? Color.marca : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(detalle).font(.caption).foregroundStyle(.secondary)
                    if estado == .conflicto {
                        Text("Hoy ya cargaste algo acá: si la tildás, se reemplaza.").font(.caption2.weight(.semibold)).foregroundStyle(Color.alerta)
                    } else if estado == .igual {
                        Text("Ya está igual hoy").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(estado == .igual)
        .accessibilityAddTraits(tildada ? .isSelected : [])
        .accessibilityIdentifier("copiar-item-\(id)")
    }

    private func cargar() async {
        let pedido = origen
        plan = nil
        sinRed = false
        let p = await modelo.prepararCopia(desde: pedido)
        guard pedido == origen else { return }
        plan = p
        sinRed = p == nil
        // Todo lo nuevo viene tildado: es copiar el día entero con un toque. Lo que pisa algo de hoy, no.
        elegidas = Set((p?.comidas.filter { $0.estado == .nueva }.map(\.id) ?? []) + (p?.libres.filter { $0.estado == .nueva }.map(\.id) ?? []))
    }

    private func tocarCopiar() {
        if pisan.isEmpty { Task { await copiar() } } else { preguntar = true }
    }

    private func copiar() async {
        guard let plan else { return }
        copiando = true
        let r = await modelo.copiarAHoy(comidas: plan.comidas.filter { elegidas.contains($0.id) },
                                        // Las «igual» van también: cada una descuenta la suya de hoy y no le roba la coincidencia a una nueva.
                                        libres: plan.libres.filter { elegidas.contains($0.id) || $0.estado == .igual },
                                        reemplazar: Set(pisan.map(\.id)))
        copiando = false
        await modelo.irADia(nil)
        if r.libresFallidas > 0 || r.saltadas > 0 { falla = r } else { cerrar() }
    }
}
