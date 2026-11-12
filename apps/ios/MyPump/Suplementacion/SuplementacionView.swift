import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// La pestaña Suplementación (2.1.0, `mypump_suplementacion`): solo lectura. Arriba el título y la acción, después «Tu
/// día» (los momentos en el orden de `dia[]`, con la agrupación de «Tu guía»: `VistaSuplementacion`) y al final «Dejás
/// de tomar». Tocar un suplemento abre su detalle. Aparece solo si el cliente tiene suplementación (ver `Raiz`).
struct SuplementacionView: View {
    let modelo: ModeloSuplementacion
    @State private var app = Proveedor.modelo
    @Environment(\.horizontalSizeClass) private var claseAncho
    /// El detalle abierto. Si un refresco cambia la lista y en ese lugar ya no está el mismo suplemento, se cierra.
    @State private var ruta: [SuplementoAbierto] = []
    /// «Dónde comprarlo» (2.3.0, palanca `compras_pais`): el suplemento del que se están viendo las opciones.
    @State private var comprando: SuplementoAbierto?

    /// La primera fila de cada suplemento que tiene dónde comprarse: ahí va el botón (uno por suplemento, no uno por toma).
    private func filasConCompra(_ v: VistaSuplementacion) -> Set<String> {
        guard app.palanca.comprasPais, let c = app.compras, c.hay else { return [] }
        var vistos = Set<Int>(), filas = Set<String>()
        for m in v.momentos {
            for f in m.filas where v.items.indices.contains(f.item) && !vistos.contains(f.item) {
                vistos.insert(f.item)
                if !c.opciones(para: v.items[f.item].nombre).isEmpty { filas.insert(f.id) }
            }
        }
        return filas
    }

    var body: some View {
        NavigationStack(path: $ruta) {
            Group {
                if let v = modelo.vista {
                    contenido(v)
                } else {
                    ContentUnavailableView("Sin suplementación", systemImage: "pills",
                                           description: Text("Cuando Mati cargue tu suplementación, la vas a ver acá."))
                }
            }
            .background(Color.fondo)
            .navigationTitle("Suplementación")
            .navigationDestination(for: SuplementoAbierto.self) { a in
                DetalleSuplementoView(modelo: modelo, abierto: a)
            }
        }
        .onChange(of: modelo.respuesta) { _, r in
            let items = r?.suplementacion?.items ?? []
            let siguen = Array(ruta.prefix { ReglasSuplementacion.itemAbierto(items, indice: $0.item, nombre: $0.nombre) != nil })
            if siguen.count != ruta.count { ruta = siguen }
            if let c = comprando, ReglasSuplementacion.itemAbierto(items, indice: c.item, nombre: c.nombre) == nil { comprando = nil }
        }
        .sheet(item: $comprando) { c in
            HojaCompras(nombre: c.nombre, cerrar: { comprando = nil }).presentationDragIndicator(.visible)
        }
    }

    private func contenido(_ v: VistaSuplementacion) -> some View {
        let s = modelo.respuesta?.suplementacion
        let conCompra = filasConCompra(v)
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                if claseAncho == .regular {
                    Text("Suplementación")
                        .font(Archivo.fuente(34, peso: 800, relativoA: .largeTitle))
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, Espacio.s)
                }
                BannerRevision()
                if modelo.desdeCache && !app.desdeCache {
                    Label("Sin conexión: ves lo último que guardaste", systemImage: "wifi.slash")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.alerta)
                        .accessibilityIdentifier("supl-sin-red")
                }
                Cabecera(titulo: s?.titulo, accion: s?.accion)
                if !conCompra.isEmpty {
                    Label(TextosColaB.Compras.ayuda, systemImage: "cart.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Espacio.s)
                        .background(Color.marcaSuave, in: .rect(cornerRadius: Radio.control + 6))
                        .accessibilityIdentifier("compras-ayuda")
                }
                if !v.momentos.isEmpty {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        Text("Tu día").textoCeja().accessibilityAddTraits(.isHeader)
                        ForEach(v.momentos) { m in
                            MomentoTarjeta(momento: m, items: v.items, conCompra: conCompra) { comprando = $0 }
                        }
                    }
                }
                if !v.protectores.isEmpty {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        Text(VistaSuplementacion.tituloProtectores).textoCeja().accessibilityAddTraits(.isHeader)
                        BloqueProtectores(protectores: v.protectores).superficieTarjeta()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("supl-protectores")
                }
                if let f = app.feedback { SeccionYaLoTenes(modelo: f, items: v.items) }
                if let sigue = v.sigue {
                    Text("\(Text("Sigue igual.").fontWeight(.semibold)) \(sigue)")
                        .font(.subheadline)
                        .tarjeta()
                }
                if !v.sale.isEmpty {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        Text("Dejás de tomar").textoCeja().accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(Array(v.sale.enumerated()), id: \.offset) { n, x in
                                if n > 0 { Divider().padding(.leading, Espacio.m) }
                                FilaSale(sale: x)
                            }
                        }
                        .superficieTarjeta()
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("supl-sale")
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .refreshable { await modelo.cargar() }
    }
}

/// «¿Ya lo tenés?» (palanca `suple_estado`): cada suplemento una vez, con su marca. Se marca una sola vez y se puede cambiar.
/// Los protectores no aparecen acá. Con la palanca apagada o sin el servidor nuevo, la sección no existe.
private struct SeccionYaLoTenes: View {
    let modelo: ModeloFeedback
    let items: [ItemSuplemento]
    @State private var fallo = false
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        let filas = ReglasSupleEstado.filas(items, marcas: modelo.marcas)
        if modelo.supleHabilitado, !filas.isEmpty {
            VStack(alignment: .leading, spacing: Espacio.s) {
                HStack(alignment: .firstTextBaseline) {
                    Text(TextosFeedback.supleTitulo).textoCeja().accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Espacio.xs)
                    Text(ReglasSupleEstado.resumen(filas)).font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                        .accessibilityIdentifier("supl-estado-resumen")
                }
                VStack(spacing: 0) {
                    ForEach(Array(filas.enumerated()), id: \.element.id) { n, f in
                        if n > 0 { Divider().padding(.leading, Espacio.m) }
                        fila(f, n)
                    }
                }
                .superficieTarjeta()
                Text(TextosFeedback.supleAyuda).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("supl-estado")
            .alert(TextosFeedback.supleError, isPresented: $fallo) { Button("OK", role: .cancel) {} }
        }
    }

    @ViewBuilder private func fila(_ f: ReglasSupleEstado.Fila, _ n: Int) -> some View {
        let disposicion = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs)) : AnyLayout(HStackLayout(spacing: Espacio.s))
        VStack(alignment: .leading, spacing: 6) {
            disposicion {
                Text(f.nombre).font(.body.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Menu {
                    ForEach(ReglasSupleEstado.Estado.allCases) { e in
                        Button { marcar(f, e) } label: {
                            if f.estado == e { Label(e.accion, systemImage: "checkmark") } else { Text(e.accion) }
                        }
                    }
                } label: {
                    Marca(estado: f.estado, viajando: modelo.marcando.contains(f.id))
                }
                .accessibilityLabel(f.estado.map { "\(f.nombre), \($0.marcado)" } ?? "\(f.nombre), \(TextosFeedback.supleMarcar)")
                .accessibilityIdentifier("supl-estado-\(n)")
            }
            if f.estado == .noLoConsigo {
                Text(TextosFeedback.supleNoConsigoAviso).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("supl-estado-no-consigo")
            }
        }
        .padding(.horizontal, Espacio.m)
        .padding(.vertical, Espacio.s)
    }

    private func marcar(_ f: ReglasSupleEstado.Fila, _ e: ReglasSupleEstado.Estado) {
        // Si esa marca todavía viaja, el toque no hace nada: no es un fallo.
        guard !modelo.marcando.contains(ReglasSupleEstado.clave(f.nombre)) else { return }
        Task {
            if await modelo.marcar(nombre: f.nombre, e) { UISelectionFeedbackGenerator().selectionChanged() } else { fallo = true }
        }
    }

    /// La píldora de la marca: «Marcar» sin elegir, o el estado con su color.
    private struct Marca: View {
        let estado: ReglasSupleEstado.Estado?
        let viajando: Bool

        var body: some View {
            let tono: Color = switch estado {
            case .tomando: .exito
            case .comprado: .marcaTexto
            case .noLoConsigo: .alerta
            case .loDeje: .secondary
            case nil: .primary
            }
            let icono = switch estado {
            case .tomando: "checkmark.circle.fill"
            case .comprado: "bag.fill"
            case .noLoConsigo: "magnifyingglass"
            case .loDeje: "pause.circle.fill"
            case nil: "circle"
            }
            HStack(spacing: 6) {
                if viajando { ProgressView().controlSize(.small) } else { Image(systemName: icono).imageScale(.small) }
                Text(estado?.marcado ?? TextosFeedback.supleMarcar)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold)).opacity(0.6)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tono)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(estado == nil || estado == .loDeje ? Color.campo : tono.opacity(0.14), in: .capsule)
            .contentShape(.capsule)
        }
    }
}

/// Lo que se apila al tocar un suplemento: su índice en `items` y su nombre, para no mostrar otro si la lista cambia.
struct SuplementoAbierto: Hashable {
    let item: Int
    let nombre: String
}

/// El `titulo` y la `accion`, si vienen.
private struct Cabecera: View {
    let titulo: String?
    let accion: String?

    var body: some View {
        let t = titulo.flatMap { $0.isEmpty ? nil : $0 }
        let a = accion.flatMap { $0.isEmpty ? nil : $0 }
        if t != nil || a != nil {
            VStack(alignment: .leading, spacing: Espacio.xs) {
                if let t { Text(t).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader) }
                if let a {
                    Label(a, systemImage: "arrow.right.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("supl-cabecera")
        }
    }
}

/// Un momento del día: su título y lo que se toma ahí, cada fila con su cantidad de esa toma.
private struct MomentoTarjeta: View {
    let momento: VistaSuplementacion.Momento
    let items: [ItemSuplemento]
    var conCompra: Set<String> = []
    var comprar: (SuplementoAbierto) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(momento.titulo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.marcaTexto)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.s)
                .padding(.bottom, Espacio.xxs)
            ForEach(Array(momento.filas.enumerated()), id: \.element.id) { n, f in
                if n > 0 { Divider().padding(.leading, Espacio.m) }
                if items.indices.contains(f.item) {
                    FilaSuplemento(fila: f, item: items[f.item])
                    if conCompra.contains(f.id) {
                        Button { comprar(SuplementoAbierto(item: f.item, nombre: items[f.item].nombre)) } label: {
                            Label(TextosColaB.Compras.boton, systemImage: "cart.fill")
                        }
                        .buttonStyle(BotonSecundario(tono: .marcaTexto))
                        .padding(.horizontal, Espacio.m)
                        .padding(.bottom, Espacio.s)
                        .accessibilityIdentifier("compras-abrir-\(f.item)")
                    }
                }
            }
        }
        .padding(.bottom, Espacio.xxs)
        .superficieTarjeta()
        // Un contenedor: si no, el identificador pisaba el de cada fila.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("supl-momento-\(momento.id)")
    }
}

/// Una toma: nombre, cantidad, nota y las etiquetas (estado, opcional, días). Tocarla abre el detalle del suplemento.
private struct FilaSuplemento: View {
    let fila: VistaSuplementacion.Fila
    let item: ItemSuplemento
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        NavigationLink(value: SuplementoAbierto(item: fila.item, nombre: item.nombre)) {
            HStack(alignment: .center, spacing: Espacio.s) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                        Text(fila.nombre).font(.body.weight(.semibold)).foregroundStyle(.primary)
                        if !letra.isAccessibilitySize, let c = fila.cantidad {
                            Spacer(minLength: Espacio.xs)
                            Text(c).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if letra.isAccessibilitySize, let c = fila.cantidad {
                        Text(c).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.primary)
                    }
                    if let n = fila.nota { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                    Etiquetas(item: item)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Espacio.m)
            .padding(.vertical, Espacio.s)
            .contentShape(.rect)
        }
        .buttonStyle(FilaPresionable())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ReglasSuplementacion.descripcionHablada(fila, item: item))
        .accessibilityHint("Abre el detalle")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("supl-fila-\(fila.id)")
    }
}

/// Estado (sin etiqueta para «sigue»), «Opcional» y los días. Nada si no hay nada que decir.
private struct Etiquetas: View {
    let item: ItemSuplemento
    var conSigue = false

    var body: some View {
        let estado = ReglasSuplementacion.estado(item.estado)
        let dias = ReglasSuplementacion.textoDias(item.dias)
        let conEstado = estado.map { $0.destacada || conSigue } ?? false
        if conEstado || item.opcional || dias != nil {
            FilaFluida(espaciado: 6, interlineado: 6) {
                if conEstado, let estado {
                    Chip(texto: estado.texto, icono: Self.icono(estado), tono: estado.destacada ? .marcaTexto : .secondary)
                }
                if item.opcional { Chip(texto: "Opcional") }
                if let dias { Chip(texto: dias, icono: "calendar") }
            }
            .accessibilityElement(children: .combine)
        }
    }

    static func icono(_ e: ReglasSuplementacion.Estado) -> String? {
        switch e {
        case .nuevo: "sparkles"
        case .cambia: "arrow.triangle.2.circlepath"
        case .sube: "arrow.up"
        case .baja: "arrow.down"
        case .vuelve: "arrow.uturn.backward"
        case .sigue: "checkmark"
        case .sale: "xmark"
        }
    }
}

/// Lo que deja de tomar, con su porqué. Tocarlo abre el detalle.
private struct FilaSale: View {
    let sale: VistaSuplementacion.Sale

    var body: some View {
        NavigationLink(value: SuplementoAbierto(item: sale.item, nombre: sale.nombre)) {
            HStack(spacing: Espacio.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(sale.nombre).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    if let p = sale.porQue { Text(p).font(.subheadline).foregroundStyle(.secondary) }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Espacio.m)
            .padding(.vertical, Espacio.s)
            .contentShape(.rect)
        }
        .buttonStyle(FilaPresionable())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([sale.nombre, sale.porQue].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Abre el detalle")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("supl-sale-\(sale.item)")
    }
}

// MARK: - Detalle

/// El detalle de un suplemento: la dosis (con la anterior si cambia), cuándo, cómo tomarlo, por qué y qué comprar.
struct DetalleSuplementoView: View {
    let modelo: ModeloSuplementacion
    let abierto: SuplementoAbierto

    var body: some View {
        let s = modelo.respuesta?.suplementacion
        Group {
            if let s, let it = ReglasSuplementacion.itemAbierto(s.items, indice: abierto.item, nombre: abierto.nombre) {
                contenido(it, dia: s.dia)
            } else {
                // La suplementación cambió mientras estaba abierto (otra carga): ese ítem ya no está.
                ContentUnavailableView("Este suplemento ya no está", systemImage: "pills",
                                       description: Text("Volvé atrás para ver tu suplementación al día."))
            }
        }
        .background(Color.fondo)
    }

    private func contenido(_ it: ItemSuplemento, dia: [MomentoDia]) -> some View {
        let sale = it.estado == ReglasSuplementacion.Estado.sale.rawValue
        let tomas = ReglasSuplementacion.tomas(it, dia: dia)
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(it.nombre)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("supl-detalle-nombre")
                    if let d = ReglasSuplementacion.dosis(it), !sale {
                        Text(d).font(.numeroMediano)
                            .accessibilityLabel(ReglasSuplementacion.dosisHablada(it) ?? d)
                    }
                    if let c = it.cambio { Text(c).font(.subheadline).foregroundStyle(.secondary) }
                    Etiquetas(item: it, conSigue: true)
                    if let n = it.nota { Text(n).font(.subheadline) }
                }
                .tarjeta(relleno: 20)
                if !tomas.isEmpty && !sale {
                    Seccion(titulo: "Cuándo") {
                        ForEach(tomas) { t in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                                    Text(t.momento).font(.body)
                                    if let c = t.cantidad {
                                        Spacer(minLength: Espacio.xs)
                                        Text(c).font(.body.weight(.semibold).monospacedDigit())
                                    }
                                }
                                if let n = t.nota { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                if !it.detalle.isEmpty {
                    Seccion(titulo: "Cómo tomarlo") {
                        ForEach(Array(it.detalle.enumerated()), id: \.offset) { _, d in
                            ConNegritas(texto: d).font(.body)
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) { Rectangle().fill(Color.marca).frame(width: 2) }
                        }
                    }
                }
                if let p = it.porQue {
                    Seccion(titulo: "Por qué") { Text(p).font(.body) }
                }
                if let c = it.comprar {
                    Seccion(titulo: "Para comprar") {
                        if let b = c.buscar {
                            Text("\(Text("Buscá ").foregroundStyle(.secondary))\(Text(b).fontWeight(.semibold))").font(.body)
                                .textSelection(.enabled)
                        }
                        if let d = c.donde { Label(d, systemImage: "bag").font(.subheadline) }
                        if let n = c.nota { Text(n).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .navigationTitle(it.nombre)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Un bloque del detalle: la ceja y la tarjeta.
private struct Seccion<Contenido: View>: View {
    let titulo: String
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(titulo).textoCeja().accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: Espacio.s) { contenido() }
                .tarjeta()
        }
    }
}

/// La suplementación de la demo («Ver demo», la revisión de Apple): la muestra ficticia de `apps/shared/demo`
/// (`Demo.bundle/suplementacion.json`, como la rutina, la dieta y la guía de ejemplo).
enum DemoSuplementacion {
    static var datos: Data? {
        Bundle.main.url(forResource: "suplementacion", withExtension: "json", subdirectory: "Demo.bundle").flatMap { try? Data(contentsOf: $0) }
    }
}

// MARK: - Dónde comprarlo

extension SuplementoAbierto: Identifiable {
    var id: String { "\(item)-\(nombre)" }
}

/// Las opciones que cargó Mati para ese suplemento en el país del alumno. Sin opciones se cierra sola.
private struct HojaCompras: View {
    let nombre: String
    let cerrar: () -> Void
    @State private var app = Proveedor.modelo
    @Environment(\.openURL) private var abrir

    private var opciones: [OpcionCompra] { app.palanca.comprasPais ? app.compras?.opciones(para: nombre) ?? [] : [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.m) {
                    VStack(alignment: .leading, spacing: Espacio.xxs) {
                        Text(TextosColaB.Compras.boton).textoCeja()
                        Text(nombre.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(Archivo.fuente(28, peso: 800, relativoA: .title1))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("compras-titulo")
                    }
                    ForEach(Array(opciones.enumerated()), id: \.offset) { n, o in
                        VStack(alignment: .leading, spacing: Espacio.xs) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.producto).font(.title3.weight(.bold))
                                Text(o.tienda).font(.body).foregroundStyle(.secondary)
                                if let nota = o.nota { Text(nota).font(.subheadline).foregroundStyle(.secondary) }
                            }
                            .accessibilityElement(children: .combine)
                            if let u = o.url {
                                Button { abrir(u) } label: { Label(TextosColaB.Compras.abrirTienda, systemImage: "arrow.up.right.square") }
                                    .buttonStyle(BotonMarca())
                                    .accessibilityIdentifier("compras-tienda-\(n)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tarjeta()
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("compras-opcion-\(n)")
                    }
                    Text(TextosColaB.Compras.pie).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("compras-pie")
                }
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.s)
                .padding(.bottom, Espacio.xl)
                .anchoLectura()
            }
            .background(Color.fondo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TextosColaB.Compras.cerrar, action: cerrar).accessibilityIdentifier("compras-cerrar")
                }
            }
        }
        .accessibilityIdentifier("compras-hoja")
        .onChange(of: opciones.isEmpty, initial: true) { _, vacia in if vacia { cerrar() } }
    }
}

/// «Protectores» (2.3.1): los fármacos que indicó Mati, aparte de los suplementos. Cada uno con su
/// cantidad y su momento; sin «Comprar», sin marcar y sin abrir el detalle comercial. Lo usan la pestaña y «Tu guía».
struct BloqueProtectores: View {
    let protectores: [VistaSuplementacion.Protector]
    /// En la tarjeta de «Tu guía» el margen ya lo pone la tarjeta.
    var margen: CGFloat = Espacio.m

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(protectores.enumerated()), id: \.element.id) { n, p in
                if n > 0 { Divider().padding(.leading, margen) }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                        Text(p.nombre).font(.body.weight(.semibold))
                        Spacer(minLength: Espacio.xs)
                        if let c = p.cantidad { Text(c).font(.body.weight(.semibold).monospacedDigit()).multilineTextAlignment(.trailing) }
                    }
                    if let m = p.momento { Text(m).font(.subheadline).foregroundStyle(Color.marcaTexto) }
                    if let nota = p.nota { Text(nota).font(.subheadline).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, margen)
                .padding(.vertical, Espacio.s)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("supl-protector-\(p.item)")
            }
        }
    }
}
