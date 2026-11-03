import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// «Agregar alimento» a una comida del plan (2.0.3, D1; el pedido con capturas de MyFitnessPal: el zapallo que no se
/// podía cargar y el huevo que terminaba en extras): los recientes con «+» de un toque, los alimentos propios, el buscador
/// sobre la base de alimentos (la misma de los reemplazos) y crear uno nuevo. Tocar uno abre la hoja de cantidad.
/// 2.1 (S3): «Escanear código de barras», como el «Barcode scan» de MyFitnessPal: VisionKit lee el código, se busca en Open
/// Food Facts y abre la misma hoja de cantidad. Si no está (o le faltan datos), se carga a mano o con la foto de la etiqueta.
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
    /// El código de barras: escaneando, buscando, lo que no se encontró y lo que precarga «Alimento propio».
    @State private var escaneando = false
    @State private var buscando: String?
    @State private var sinProducto: SinProducto?
    @State private var sinRed: String?
    @State private var noSePuede: EscanerCodigo.Estado?
    @State private var precarga: CrearAlimentoView.Precarga?

    /// Un código que Open Food Facts no tiene, o tiene incompleto.
    struct SinProducto: Equatable {
        let codigo: String
        let parcial: CodigoBarras.Parcial?
    }

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
                seccionCodigo
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
                    Button { precarga = nil; creando = true } label: {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await escanear() } } label: { Image(systemName: "barcode.viewfinder") }
                        .accessibilityLabel("Escanear código de barras")
                        .accessibilityIdentifier("agregar-escanear-barra")
                        .disabled(buscando != nil)
                }
            }
            .fullScreenCover(isPresented: $escaneando) {
                EscanerCodigoView { codigo in
                    escaneando = false
                    if let codigo { Task { await buscar(codigo) } }
                }
            }
            .alert(noSePuede == .sinPermiso ? "Sin permiso para la cámara" : "Este teléfono no puede escanear códigos",
                   isPresented: Binding(get: { noSePuede != nil }, set: { if !$0 { noSePuede = nil } })) {
                if noSePuede == .sinPermiso {
                    Button("Abrir Ajustes") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(noSePuede == .sinPermiso
                     ? "Para escanear el código, dale permiso a Pump Team para usar la cámara en Ajustes. Mientras, buscá el alimento por nombre."
                     : "Buscá el alimento por nombre, o creá el tuyo con la foto de la etiqueta.")
            }
            .navigationDestination(isPresented: $abierto) {
                if let elegido {
                    CantidadAlimentoView(modelo: modelo, pedido: elegido, opciones: opciones, enHoja: false) { cerrar() }
                }
            }
            .navigationDestination(isPresented: $creando) {
                CrearAlimentoView(modelo: modelo, categoria: "", precarga: precarga) { creado in
                    creando = false
                    var c = AgregadosComida.Candidato(AlimentoBase(
                        nombre: creado.nombre, kcal: creado.kcal ?? 0, prot: creado.prot ?? 0, carb: creado.carb ?? 0,
                        fat: creado.fat ?? 0, categoria: creado.categoria, unidad: creado.unidad,
                        gramosPorUnidad: creado.gramosPorUnidad, esPropio: true))
                    // Creado desde un código: el agregado lleva el código y el próximo escaneo encuentra este alimento.
                    if let codigo = precarga?.codigo {
                        c = AgregadosComida.Candidato(nombre: c.nombre, por100: c.por100, unidad: c.unidad, gramosPorUnidad: c.gramosPorUnidad,
                                                      origen: .propio, codigo: codigo)
                        modelo.recordarCodigoPropio(codigo, c)
                        sinProducto = nil
                    }
                    precarga = nil
                    abrir(CantidadAlimento(comidaId: comidaId, que: .nuevo(c)))
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Código de barras

    /// Arriba de todo: el acceso al escáner (bien visible, como en MyFitnessPal) o, después de escanear, lo que pasó.
    @ViewBuilder private var seccionCodigo: some View {
        if let codigo = buscando {
            Section {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Buscando el producto…").font(.body.weight(.medium))
                        Text("Código \(codigo)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("codigo-buscando")
            }
        } else if let sp = sinProducto {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(sp.parcial == nil ? "No encontramos este producto" : "Le faltan datos a este producto", systemImage: "barcode")
                        .font(.headline)
                    Text(sp.parcial?.texto ?? "Todavía no está en Open Food Facts, la base de productos que usamos.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Código \(sp.codigo)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("codigo-sin-producto")
                if modelo.token != nil {
                    Button { crearDesdeCodigo(sp, etiqueta: true) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Escanear la etiqueta").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text("Sacale una foto a la tabla nutricional y se completa solo").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "text.viewfinder").foregroundStyle(Color.marcaTexto)
                        }
                    }
                    .accessibilityIdentifier("codigo-etiqueta")
                }
                Button { crearDesdeCodigo(sp, etiqueta: false) } label: {
                    Label("Cargarlo a mano", systemImage: "square.and.pencil")
                        .font(.body.weight(.medium)).foregroundStyle(Color.marcaTexto)
                }
                .accessibilityIdentifier("codigo-a-mano")
                Button { Task { await escanear() } } label: {
                    Label("Escanear otro código", systemImage: "barcode.viewfinder").foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("codigo-otro")
            }
        } else {
            Section {
                Button { Task { await escanear() } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.sobreMarca)
                            .frame(width: 46, height: 46)
                            .background(Color.marca, in: .rect(cornerRadius: Radio.miniatura, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Escanear código de barras").font(.body.weight(.semibold)).foregroundStyle(.primary)
                            Text("Apuntá al código del envase y se carga solo").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("agregar-escanear")
                if let sinRed {
                    Label(sinRed, systemImage: "wifi.slash").font(.footnote).foregroundStyle(Color.alerta)
                        .accessibilityIdentifier("codigo-sin-red")
                }
            }
        }
    }

    /// Abre el escáner (o, en DEBUG con `-codigoDePrueba`, busca ese código sin cámara).
    private func escanear() async {
        sinRed = nil
        if let c = EscanerCodigo.dePrueba, let codigo = CodigoBarras.normalizar(c) {
            await buscar(codigo)
            return
        }
        switch await EscanerCodigo.preparar() {
        case .listo: escaneando = true
        case let otro: noSePuede = otro
        }
    }

    private func buscar(_ codigo: String) async {
        sinProducto = nil
        sinRed = nil
        withAnimation(.snappy) { buscando = codigo }
        let r = await modelo.buscarCodigo(codigo)
        withAnimation(.snappy) {
            buscando = nil
            switch r {
            case .lectura(.encontrado(let p)):
                abrir(CantidadAlimento(comidaId: comidaId, que: .nuevo(p.candidato)))
            case .lectura(.incompleto(let parcial)):
                sinProducto = SinProducto(codigo: codigo, parcial: parcial)
            case .lectura(.noEncontrado):
                sinProducto = SinProducto(codigo: codigo, parcial: nil)
            case .sinRed:
                sinRed = "Sin conexión: no pudimos buscar el código. Probá de nuevo o buscalo por nombre."
            }
        }
    }

    private func crearDesdeCodigo(_ sp: SinProducto, etiqueta: Bool) {
        precarga = CrearAlimentoView.Precarga(codigo: sp.codigo, parcial: sp.parcial, escanearEtiqueta: etiqueta)
        creando = true
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
