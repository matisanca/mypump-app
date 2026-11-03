import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// «Agregar alimento» a una comida del plan (2.0.3, D1; el pedido con capturas de MyFitnessPal: el zapallo que no se
/// podía cargar y el huevo que terminaba en extras): los recientes con «+» de un toque, los alimentos propios, el buscador
/// sobre la base de alimentos (la misma de los reemplazos) y crear uno nuevo. Tocar uno abre la hoja de cantidad.
struct AgregarAlimentoView: View {
    let modelo: ModeloApp
    let comidaId: String
    let opciones: [String: Int]

    @Environment(\.dismiss) private var cerrar
    @State private var busqueda = ""
    @State private var elegido: CantidadAlimento?
    @State private var abierto = false
    @State private var creando = false
    @State private var aviso: String?

    /// La base con los propios del cliente (cada propio reemplaza al del mismo nombre, como en los reemplazos).
    private var base: BaseAlimentos { MotorSustitutos.base.conPropios(modelo.alimentosPropios) }

    var body: some View {
        let nombreComida = modelo.comidasParaAjustar(opciones: opciones).first { $0.id == comidaId }?.nombre ?? "la comida"
        NavigationStack {
            List {
                if let aviso {
                    Section {
                        Label(aviso, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.alerta)
                    }
                }
                if busqueda.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !modelo.agregadosRecientes.isEmpty {
                        Section("Recientes") {
                            ForEach(Array(modelo.agregadosRecientes.enumerated()), id: \.element.ts) { i, r in filaReciente(r, i) }
                        }
                    }
                    let propios = base.alimentos.filter(\.esPropio)
                    if !propios.isEmpty {
                        Section("Tus alimentos") { ForEach(propios, id: \.nombre) { fila($0) } }
                    }
                    Section {
                        Label("Buscá entre los \(MotorSustitutos.base.alimentos.count) alimentos de la base: zapallo, huevo, arroz…",
                              systemImage: "magnifyingglass")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    let r = AgregadosComida.buscar(base, busqueda)
                    if r.isEmpty {
                        Section {
                            ContentUnavailableView("Sin resultados para “\(busqueda)”", systemImage: "magnifyingglass",
                                                   description: Text("Probá con otro nombre o creá tu alimento con los datos de la etiqueta."))
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        Section("Base de alimentos") { ForEach(r, id: \.nombre) { fila($0) } }
                    }
                }
                Section {
                    Button { creando = true } label: {
                        Label("Crear alimento personalizado", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Color.marcaTexto)
                    }
                    .accessibilityIdentifier("agregar-crear")
                } footer: {
                    Text("Cargalo con los valores de la etiqueta y queda para tus próximas comidas y reemplazos.")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar alimento")
            .navigationTitle("Agregar \(AjustarComidaView.aLa(nombreComida))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
            .navigationDestination(isPresented: $abierto) {
                if let elegido {
                    CantidadAlimentoView(modelo: modelo, pedido: elegido, opciones: opciones, enHoja: false) { cerrar() }
                }
            }
            .navigationDestination(isPresented: $creando) {
                CrearAlimentoView(modelo: modelo, categoria: "") { creado in
                    creando = false
                    let c = AgregadosComida.Candidato(AlimentoBase(
                        nombre: creado.nombre, kcal: creado.kcal ?? 0, prot: creado.prot ?? 0, carb: creado.carb ?? 0,
                        fat: creado.fat ?? 0, categoria: creado.categoria, unidad: creado.unidad,
                        gramosPorUnidad: creado.gramosPorUnidad, esPropio: true))
                    abrir(CantidadAlimento(comidaId: comidaId, que: .nuevo(c)))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func abrir(_ p: CantidadAlimento) {
        elegido = p
        abierto = true
    }

    /// Un alimento de la base (o propio): las kcal cada 100 g y su medida casera.
    private func fila(_ a: AlimentoBase) -> some View {
        let c = AgregadosComida.Candidato(a)
        let medida = AgregadosComida.medidas(c).dropFirst().first
        return Button { abrir(CantidadAlimento(comidaId: comidaId, que: .nuevo(c))) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(a.nombre).font(.body.weight(.medium)).foregroundStyle(.primary)
                        if a.esPropio {
                            Text("★ Tuyo").font(.caption2.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Color.marcaSuave, in: .capsule)
                        }
                    }
                    Text("\(a.kcal.enteroSeguro) kcal cada 100 g" + (medida.map { " · 1 \($0.nombre) ≈ \($0.gramos.kg) g" } ?? ""))
                        .font(.subheadline).foregroundStyle(.secondary)
                    FormatoDieta.macros(prot: a.prot, carb: a.carb, fat: a.fat).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("agregar-alimento")
    }

    /// Un reciente: tocarlo abre la hoja con la última cantidad; el «+» lo suma de una.
    private func filaReciente(_ r: AlimentoAgregado, _ i: Int) -> some View {
        let medida = AgregadosComida.medidas(r.candidato).first { $0.nombre == r.unidad }
            ?? AgregadosComida.Medida(nombre: r.unidad, gramos: r.gramosUnidad ?? 1)
        return HStack(spacing: 10) {
            Button { abrir(CantidadAlimento(comidaId: comidaId, que: .nuevo(r.candidato), inicial: (r.cantidad, medida))) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.nombre).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text("\(FormatoDieta.cantidad(r.cantidad, r.unidad)) · \(r.kcal.enteroSeguro) kcal")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button { agregarDeUnToque(r, medida) } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.sobreMarca)
                    .frame(width: 34, height: 34)
                    .background(Color.marca, in: .circle)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Agregar \(r.nombre)")
            .accessibilityIdentifier("reciente-agregar-\(i)")
        }
    }

    /// El «+» de un reciente: la misma cantidad de la última vez, a esta comida, sin pasar por la hoja.
    private func agregarDeUnToque(_ r: AlimentoAgregado, _ medida: AgregadosComida.Medida) {
        var a = CantidadAlimentoView.base(modelo, comidaId, opciones: opciones)
        let nuevo = AgregadosComida.agregado(r.candidato, cantidad: r.cantidad, medida: medida, ts: CantidadAlimentoView.nuevoTs(a))
        a.agregados.append(nuevo)
        var dia = modelo.ajustesDeHoy
        dia[comidaId] = a
        if let m = AgregadosComida.motivoNoEntra(dia, comidaId: comidaId) {
            withAnimation(.snappy) { aviso = m }
            return
        }
        let id = comidaId
        Task { await modelo.ajustar(id, a, opciones: opciones) }
        modelo.recordarReciente(nuevo)
        cerrar()
    }
}
