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
        }
    }

    private func contenido(_ v: VistaSuplementacion) -> some View {
        let s = modelo.respuesta?.suplementacion
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
                if !v.momentos.isEmpty {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        Text("Tu día").textoCeja().accessibilityAddTraits(.isHeader)
                        ForEach(v.momentos) { m in
                            MomentoTarjeta(momento: m, items: v.items)
                        }
                    }
                }
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
