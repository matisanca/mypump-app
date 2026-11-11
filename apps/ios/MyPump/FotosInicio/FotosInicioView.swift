import ImageIO
import PhotosUI
import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosFotosInicio

/// La tarjeta «Tus fotos de inicio»: arriba de todo en Entreno (lo primero que se ve al abrir la app) mientras falte alguna, y
/// arriba en Revisión siempre. Solo existe mientras Mati las tenga pedidas (contrato, sección 13): sin cuenta, con la palanca
/// apagada, sin el servidor nuevo o con el pedido cerrado, no se ve nada. Un toque lleva derecho a la pose que falta, y el
/// segundo ya es «Sacar o elegir foto» (regla de Mati: fácil de encontrar y nada a más de dos toques).
struct TarjetaFotosInicio: View {
    /// En Entreno: se va cuando ya están las tres.
    var soloSiFaltan = false
    @State private var app = Proveedor.modelo
    @State private var abierta = false

    var body: some View {
        if let m = app.fotosInicio, (m.visible && !(soloSiFaltan && m.faltan.isEmpty)) || abierta {
            Button { abierta = true } label: {
                VStack(spacing: Espacio.s) {
                HStack(spacing: Espacio.s) {
                    Image(systemName: m.listas ? "checkmark.circle.fill" : "camera.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(width: 42, height: 42)
                        .background(Color.marcaSuave, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T.tarjetaTitulo).font(.headline).foregroundStyle(.primary)
                        Text(m.listas ? T.tarjetaLista : T.tarjetaBajada).font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        if !m.listas {
                            Text(T.cuenta(m.hechas)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    if m.listas { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                    // Un botón grande y con texto: que se vea que es lo que hay que tocar.
                    if !m.listas {
                        Label(m.hechas == 0 ? T.tarjetaEmpezar : T.tarjetaSeguir, systemImage: "camera.fill")
                            .font(.headline).foregroundStyle(Color.sobreMarca)
                            .padding(.horizontal, 20).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.marca, in: .capsule)
                    }
                }
                .tarjeta()
            }
            .buttonStyle(FilaPresionable())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("fotos-inicio-tarjeta")
            .sheet(isPresented: $abierta) {
                FotosInicioRaiz(modelo: m, directo: true, alCerrar: { abierta = false }).presentationDragIndicator(.visible)
            }
        }
    }
}

/// Lo que se apila arriba del resumen.
private enum DestinoFotosInicio: Hashable {
    case pose(String), revisar(FotoARevisar)
}

/// La foto que se está revisando viaja en el destino: leída de un `@State` de la raíz, el destino quedaba con el valor viejo
/// (vacío). No sobrevive a cerrar la hoja.
private struct FotoARevisar: Hashable {
    let pose: String
    let foto: FotoInicioPreparada
    static func == (a: Self, b: Self) -> Bool { a.pose == b.pose && a.foto.id == b.foto.id }
    func hash(into h: inout Hasher) { h.combine(pose); h.combine(foto.id) }
}

/// El resumen (las tres poses, los consejos y «El físico que te motiva»), y arriba la pose y la foto a revisar.
struct FotosInicioRaiz: View {
    let modelo: ModeloFotosInicio
    let alCerrar: () -> Void
    @State private var camino: [DestinoFotosInicio]

    /// `directo` (la tarjeta): abre ya en la pose que falta, con el resumen atrás. Desde Mis datos, el resumen.
    init(modelo: ModeloFotosInicio, directo: Bool = false, alCerrar: @escaping () -> Void) {
        self.modelo = modelo
        self.alCerrar = alCerrar
        _camino = State(initialValue: directo ? (modelo.faltan.first.map { [.pose($0)] } ?? []) : [])
    }

    private func alPreparar(_ pose: String, _ p: FotoInicioPreparada) {
        // «Sacar otra» reemplaza a la que se estaba revisando.
        if case .revisar? = camino.last { camino.removeLast() }
        camino.append(.revisar(FotoARevisar(pose: pose, foto: p)))
    }

    // Una pila propia con `path`, como Gimnasio: `navigationDestination(item:)` dejaba la app en un bucle en iOS 17.
    var body: some View {
        NavigationStack(path: $camino) {
            Group {
                if modelo.estado == nil { Color.fondo } else { ResumenFotosInicio(modelo: modelo, alAbrir: { camino = [.pose($0)] }, alPreparar: alPreparar, alListo: alCerrar) }
            }
            .background(Color.fondo)
            .navigationTitle(T.tarjetaTitulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar, action: alCerrar) } }
            .navigationDestination(for: DestinoFotosInicio.self) { d in
                switch d {
                case .pose(let clave):
                    if let p = FotosInicio.pose(clave) { PoseFotoInicio(pose: p, alPreparar: alPreparar) }
                case .revisar(let r):
                    RevisarFotoInicio(modelo: modelo, pose: r.pose, foto: r.foto, alPreparar: alPreparar) { siguiente in
                        camino = siguiente.map { [.pose($0)] } ?? []
                    }
                }
            }
        }
        .task { await modelo.refrescar(); modelo.drenarEnFondo() }
        // Las miniaturas firmadas: al abrir y cada vez que aparece una foto nueva en el servidor.
        .task(id: modelo.estado?.fotos.map(\.id) ?? []) { await modelo.firmar() }
        .onChange(of: modelo.estado == nil) { _, apagado in if apagado { alCerrar() } }
    }
}

/// Texto suave de error o estado, siempre con el mismo aspecto.
private struct NotaFotosInicio: View {
    let texto: String
    var alerta = false
    var body: some View {
        Text(texto)
            .font(.footnote.weight(.medium))
            .foregroundStyle(alerta ? Color.alerta : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { if alerta { AccessibilityNotification.Announcement(texto).post() } }
    }
}

// MARK: Resumen

private struct ResumenFotosInicio: View {
    let modelo: ModeloFotosInicio
    let alAbrir: (String) -> Void
    let alPreparar: (String, FotoInicioPreparada) -> Void
    let alListo: () -> Void
    @State private var errorMotivacion: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                    Image(systemName: "lock.fill").font(.footnote).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                    Text(T.privacidad).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("fotos-inicio-privacidad")

                VStack(alignment: .leading, spacing: Espacio.xs) {
                    if modelo.listas {
                        Text(T.listoTitulo).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("fotos-inicio-listas")
                        Text(T.listoBajada).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if !modelo.faltan.isEmpty {
                        Text(T.faltan(modelo.faltan.count)).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("fotos-inicio-faltan")
                    }
                    switch modelo.aviso {
                    case .rechazada?: NotaFotosInicio(texto: T.fotoRechazada, alerta: true).accessibilityIdentifier("fotos-inicio-aviso")
                    case .tope?: NotaFotosInicio(texto: T.motivacionTope, alerta: true).accessibilityIdentifier("fotos-inicio-aviso")
                    case nil: EmptyView()
                    }
                    if !modelo.cola.isEmpty && modelo.subiendo == nil { NotaFotosInicio(texto: T.sinSenal).accessibilityIdentifier("fotos-inicio-sin-senal") }
                }

                VStack(spacing: 0) {
                    ForEach(Array(FotosInicio.poses.enumerated()), id: \.element.clave) { i, p in
                        if i > 0 { Divider().padding(.leading, 84) }
                        FilaPoseFotoInicio(modelo: modelo, pose: p) { alAbrir(p.clave) }
                    }
                }
                .superficieTarjeta()

                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(T.consejosTitulo).font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(FotosInicio.consejos, id: \.self) { consejo in
                        HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                            Text(consejo).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .tarjeta()

                motivacion

                Button(T.listoBoton, action: alListo)
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("fotos-inicio-listo")
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { modelo.limpiarAviso() }
    }

    /// «El físico que te motiva» (opcional): una o más fotos y una nota.
    private var motivacion: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) { tituloMotivacion; Spacer(minLength: 0); opcional }
                VStack(alignment: .leading, spacing: 2) { tituloMotivacion; opcional }
            }
            Text(T.motivacionBajada).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            let fotos = modelo.motivacion
            if !fotos.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: Espacio.s)], alignment: .leading, spacing: Espacio.s) {
                    ForEach(fotos) { f in
                        MiniaturaMotivacion(foto: f, url: modelo.urls[f.id]) {
                            Task {
                                let r = await modelo.borrarMotivacion(id: f.id)
                                errorMotivacion = r == .sinSenal ? T.borrarSinSenal : nil
                            }
                        }
                    }
                }
            }
            if let errorMotivacion { NotaFotosInicio(texto: errorMotivacion, alerta: true) }
            if modelo.puedeAgregarMotivacion {
                BotonFotoInicio(texto: T.motivacionAgregar, id: "fotos-inicio-motivacion-agregar", primario: false) { alPreparar(FotosInicio.motivacion, $0) }
            } else {
                NotaFotosInicio(texto: T.motivacionTope).accessibilityIdentifier("fotos-inicio-motivacion-tope")
            }
            NotaMotivacion(modelo: modelo)
        }
        .tarjeta()
    }

    private var tituloMotivacion: some View {
        Text(T.motivacionTitulo).font(.headline).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    private var opcional: some View { Text(T.opcional).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
}

private struct FilaPoseFotoInicio: View {
    let modelo: ModeloFotosInicio
    let pose: FotosInicio.Pose
    let alTocar: () -> Void

    private var estado: ModeloFotosInicio.EstadoPose { modelo.estadoPose(pose.clave) }
    private var textoEstado: String {
        switch estado {
        case .falta: T.falta
        case .subiendo: T.subiendo
        case .esperando: T.esperandoSenal
        case .lista: T.lista
        }
    }

    var body: some View {
        Button(action: alTocar) {
            HStack(spacing: Espacio.s) {
                Color.campo
                    .frame(width: 56, height: 72)
                    .overlay {
                        if let f = modelo.foto(pose.clave) {
                            ImagenFotoInicio(foto: f, url: modelo.urls[f.id])
                        } else {
                            SiluetaFotoInicio(pose: pose.clave).padding(6)
                        }
                    }
                    .clipShape(.rect(cornerRadius: Radio.miniatura, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pose.nombre).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        if estado == .lista { Image(systemName: "checkmark.circle.fill").imageScale(.small).accessibilityHidden(true) }
                        if estado == .subiendo { ProgressView().controlSize(.mini) }
                        Text(textoEstado)
                    }
                    .font(.subheadline.weight(estado == .falta ? .regular : .semibold))
                    .foregroundStyle(estado == .lista ? Color.marcaTexto : Color.secondary)
                }
                Spacer(minLength: 0)
                if estado != .falta { Text(T.repetir).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(Espacio.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(FilaPresionable())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pose.nombre)
        .accessibilityValue(textoEstado)
        .accessibilityHint(estado == .falta ? "" : T.repetir)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("fotos-inicio-pose-\(pose.clave)")
    }
}

/// La foto de una pose o de motivación: la del teléfono mientras espera subir, o la del servidor con su URL firmada.
private struct ImagenFotoInicio: View {
    let foto: ModeloFotosInicio.VistaFoto
    let url: URL?

    var body: some View {
        if let f = foto.archivoLocal {
            MiniaturaLocalFotoInicio(archivo: f)
        } else if let url {
            AsyncImage(url: url) { fase in
                if let i = fase.image { i.resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(.tertiary) }
            }
        } else {
            Image(systemName: "photo").foregroundStyle(.tertiary)
        }
    }
}

/// La foto del disco, reducida fuera del hilo principal.
private struct MiniaturaLocalFotoInicio: View {
    let archivo: URL
    @State private var imagen: UIImage?

    var body: some View {
        Group {
            if let imagen { Image(uiImage: imagen).resizable().scaledToFill() } else { Color.campo }
        }
        .task(id: archivo) {
            let f = archivo
            imagen = await Task.detached(priority: .utility) { () -> UIImage? in
                guard let s = CGImageSourceCreateWithURL(f as CFURL, nil),
                      let c = CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 320, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
                return UIImage(cgImage: c)
            }.value
        }
    }
}

private struct MiniaturaMotivacion: View {
    let foto: ModeloFotosInicio.VistaFoto
    let url: URL?
    let borrar: () -> Void

    var body: some View {
        Color.campo
            .aspectRatio(1, contentMode: .fit)
            .overlay { ImagenFotoInicio(foto: foto, url: url) }
            .overlay(alignment: .bottom) {
                if foto.subiendo || foto.esperando {
                    Text(foto.subiendo ? T.subiendo : T.esperandoSenal)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(4).frame(maxWidth: .infinity).background(.black.opacity(0.55))
                }
            }
            .clipShape(.rect(cornerRadius: Radio.control, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(T.motivacionTitulo)
            .accessibilityValue(foto.subiendo ? T.subiendo : foto.esperando ? T.esperandoSenal : "")
            .accessibilityIdentifier("fotos-inicio-motivacion-foto")
            .overlay(alignment: .topTrailing) {
                Button(action: borrar) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(.black.opacity(0.6), in: .circle)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(T.borrarFoto)
                .accessibilityIdentifier("fotos-inicio-motivacion-borrar")
            }
    }
}

/// La nota de «El físico que te motiva»: hasta 300 caracteres. Sin señal queda guardada y sale sola.
private struct NotaMotivacion: View {
    let modelo: ModeloFotosInicio
    @State private var texto = ""
    @State private var cargada = false
    @State private var guardando = false
    @State private var resultado: String?
    @FocusState private var foco: Bool

    private var guardada: String { modelo.notaPendiente ?? modelo.estado?.nota ?? "" }
    private var cambio: Bool { FotosInicio.notaRecortada(texto) != guardada }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            TextField(T.motivacionNota, text: $texto, axis: .vertical)
                .lineLimit(2...6)
                .focused($foco)
                .padding(Espacio.s)
                .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                .accessibilityLabel(T.motivacionNota)
                .accessibilityIdentifier("fotos-inicio-nota")
                .onChange(of: texto) { _, nuevo in
                    resultado = nil
                    if nuevo.unicodeScalars.count > FotosInicio.maxNota {
                        var u = String.UnicodeScalarView(); u.append(contentsOf: nuevo.unicodeScalars.prefix(FotosInicio.maxNota)); texto = String(u)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if foco { Spacer(); Button(T.listoTeclado) { foco = false }.accessibilityIdentifier("fotos-inicio-teclado-listo") }
                    }
                }
            if let resultado { NotaFotosInicio(texto: resultado).accessibilityIdentifier("fotos-inicio-nota-resultado") }
            else if modelo.notaPendiente != nil && !cambio { NotaFotosInicio(texto: T.notaSinSenal).accessibilityIdentifier("fotos-inicio-nota-resultado") }
            if cambio || guardando {
                Button {
                    foco = false
                    guardando = true
                    Task {
                        let r = await modelo.guardarNota(texto)
                        guardando = false
                        switch r {
                        case .ok: texto = guardada; resultado = T.motivacionGuardada
                        case .sinSenal: texto = guardada; resultado = T.notaSinSenal
                        case .error: resultado = T.notaError
                        case .tokenCaido: resultado = nil
                        }
                    }
                } label: {
                    if guardando { ProgressView().tint(.primary) } else { Text(T.motivacionGuardar) }
                }
                .buttonStyle(BotonSecundario())
                .disabled(guardando)
                .accessibilityIdentifier("fotos-inicio-nota-guardar")
            }
        }
        .onAppear { if !cargada { texto = guardada; cargada = true } }
        // Si la nota llega después (la primera lectura tarda) y todavía no escribió nada, se muestra.
        .onChange(of: guardada) { viejo, nuevo in if !foco && texto == viejo { texto = nuevo } }
    }
}

// MARK: Pose

/// La pose: la silueta de referencia, cómo pararse y el botón de la foto.
private struct PoseFotoInicio: View {
    let pose: FotosInicio.Pose
    let alPreparar: (String, FotoInicioPreparada) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                SiluetaFotoInicio(pose: pose.clave)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .padding(Espacio.m)
                    .superficieTarjeta()
                    .accessibilityIdentifier("fotos-inicio-silueta")
                Text(pose.instruccion).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("fotos-inicio-instruccion")
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    ForEach([T.consejoDistancia, T.consejoAltura, T.consejoLuz], id: \.self) { consejo in
                        HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                            Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                            Text(consejo).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                BotonFotoInicio(texto: T.botonFoto, id: "fotos-inicio-foto", primario: true) { alPreparar(pose.clave, $0) }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(pose.nombre)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// La silueta de referencia de una pose (los mismos trazos que Android y la web).
struct SiluetaFotoInicio: View {
    let pose: String

    var body: some View {
        if let s = SiluetasFotosInicio.de(pose) {
            ZStack {
                TrazoSilueta(trazo: s.contorno).fill(Color.marcaSuave)
                TrazoSilueta(trazo: s.contorno).stroke(Color.marcaTexto, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if !s.detalle.isEmpty {
                    TrazoSilueta(trazo: s.detalle).stroke(Color.marcaTexto.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
            .aspectRatio(SiluetasFotosInicio.ancho / SiluetasFotosInicio.alto, contentMode: .fit)
            .accessibilityHidden(true)
        }
    }
}

private struct TrazoSilueta: Shape {
    let trazo: String

    func path(in r: CGRect) -> Path {
        let e = min(r.width / SiluetasFotosInicio.ancho, r.height / SiluetasFotosInicio.alto)
        let dx = r.minX + (r.width - SiluetasFotosInicio.ancho * e) / 2, dy = r.minY + (r.height - SiluetasFotosInicio.alto * e) / 2
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: dx + x * e, y: dy + y * e) }
        var camino = Path()
        for orden in SiluetasFotosInicio.ordenes(trazo) {
            switch orden {
            case .mover(let x, let y): camino.move(to: p(x, y))
            case .curva(let x1, let y1, let x2, let y2, let x, let y): camino.addCurve(to: p(x, y), control1: p(x1, y1), control2: p(x2, y2))
            case .cerrar: camino.closeSubpath()
            }
        }
        return camino
    }
}

// MARK: Revisar

/// La foto recién sacada con lo que encontró el control de calidad: usarla, o sacar otra.
private struct RevisarFotoInicio: View {
    let modelo: ModeloFotosInicio
    let pose: String
    let foto: FotoInicioPreparada
    let alPreparar: (String, FotoInicioPreparada) -> Void
    let alUsar: (_ siguiente: String?) -> Void
    @State private var vistaPrevia: UIImage?
    @State private var error: String?
    /// Un doble toque en «Usar esta foto» no la encola dos veces.
    @State private var usada = false

    private var problemas: [FotosInicio.Problema] { foto.problemas(pose: pose) }
    private var titulo: String { pose == FotosInicio.motivacion ? T.motivacionTitulo : FotosInicio.pose(pose)?.nombre ?? T.tarjetaTitulo }

    private func usar() {
        guard !usada else { return }
        switch modelo.encolar(pose: pose, jpeg: foto.jpeg, tomadaEn: foto.tomadaEn, medida: foto.medida) {
        case .guardada:
            usada = true
            modelo.drenarEnFondo()
            alUsar(pose == FotosInicio.motivacion ? nil : FotosInicio.siguiente(despuesDe: pose, faltan: modelo.faltan))
        case .tope: error = T.motivacionTope
        case .noSeGuardo: error = T.noSeGuardo
        }
    }

    var body: some View {
        let problemas = problemas
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                Color.campo
                    .aspectRatio(CGFloat(foto.ancho) / CGFloat(max(1, foto.alto)), contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .overlay { if let vistaPrevia { Image(uiImage: vistaPrevia).resizable().scaledToFit() } }
                    .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                if problemas.isEmpty {
                    HStack(spacing: Espacio.xs) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                        Text(T.seVeBien).font(.headline)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("fotos-inicio-bien")
                } else {
                    VStack(alignment: .leading, spacing: Espacio.xs) {
                        ForEach(problemas, id: \.self) { problema in
                            HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.alerta).accessibilityHidden(true)
                                Text(FotosInicio.texto(problema, dias: foto.dias)).fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("fotos-inicio-problema-\(problema.rawValue)")
                        }
                    }
                }
                if let error { NotaFotosInicio(texto: error, alerta: true) }
                if problemas.isEmpty {
                    Button(T.botonUsar, action: usar).buttonStyle(BotonMarca()).accessibilityIdentifier("fotos-inicio-usar")
                    BotonFotoInicio(texto: T.botonOtra, id: "fotos-inicio-otra", primario: false) { alPreparar(pose, $0) }
                } else {
                    BotonFotoInicio(texto: T.botonOtra, id: "fotos-inicio-otra", primario: true) { alPreparar(pose, $0) }
                    if !FotosInicio.bloquea(problemas) {
                        Button(T.botonUsarIgual, action: usar).buttonStyle(BotonSecundario()).accessibilityIdentifier("fotos-inicio-usar-igual")
                    }
                }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: foto.id) {
            error = nil
            let jpeg = foto.jpeg
            vistaPrevia = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let s = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let c = CGImageSourceCreateThumbnailAtIndex(s, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) else { return nil }
                return UIImage(cgImage: c)
            }.value
            if !problemas.isEmpty {
                AccessibilityNotification.Announcement(problemas.map { FotosInicio.texto($0, dias: foto.dias) }.joined(separator: ". ")).post()
            }
        }
    }
}

// MARK: El botón de foto

/// «Sacar o elegir foto» (y «Sacar otra», «Agregar foto»): la cámara o la galería, y la foto ya preparada para revisar (1600 px,
/// 0,85, derecha, sin metadatos y con el control de calidad hecho). Con `-fotosInicioDePrueba` arma una foto de mentira
/// (`-fotosInicioFoto buena|oscura|chica|movida`) que pasa por el mismo camino.
private struct BotonFotoInicio: View {
    let texto: String
    let id: String
    let primario: Bool
    let alPreparar: (FotoInicioPreparada) -> Void

    @State private var camara = false
    @State private var galeria = false
    @State private var item: PhotosPickerItem?
    @State private var ilegible = false
    @State private var preparando = false

    private var etiqueta: some View {
        HStack(spacing: Espacio.xs) {
            if preparando { ProgressView().tint(primario ? Color.sobreMarca : Color.primary) } else { Image(systemName: "camera.fill").accessibilityHidden(true) }
            Text(texto).multilineTextAlignment(.center)
        }
        .font(.headline)
        .foregroundStyle(primario ? Color.sobreMarca : Color.primary)
        .padding(.horizontal, 20).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(primario ? Color.marca : Color.campo, in: .capsule)
        .contentShape(.capsule)
    }

    /// Fuera del hilo principal: decodificar y medir una foto de 1600 px tarda.
    private func preparar(_ trabajo: @escaping @Sendable () -> FotoInicioPreparada?) {
        preparando = true
        ilegible = false
        Task {
            let p = await Task.detached(priority: .userInitiated, operation: trabajo).value
            preparando = false
            if let p { alPreparar(p) } else { ilegible = true }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            boton
                .disabled(preparando)
                .accessibilityIdentifier(id)
            if ilegible { NotaFotosInicio(texto: T.ilegible, alerta: true).accessibilityIdentifier("fotos-inicio-ilegible") }
        }
    }

    @ViewBuilder private var boton: some View {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "fotosInicioDePrueba") != nil {
            Button {
                let escenario = UserDefaults.standard.string(forKey: "fotosInicioFoto") ?? "buena"
                preparar { FotoSinteticaFotosInicio.jpeg(escenario).flatMap { PreparacionFotoInicio.preparar($0) } }
            } label: { etiqueta }
            .buttonStyle(.plain)
        } else { real }
        #else
        real
        #endif
    }

    private var real: some View {
        Group {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Menu {
                    Button { camara = true } label: { Label("Sacar foto", systemImage: "camera") }
                    Button { galeria = true } label: { Label("Elegir de la galería", systemImage: "photo.on.rectangle") }
                } label: { etiqueta }
            } else {
                Button { galeria = true } label: { etiqueta }.buttonStyle(.plain)
            }
        }
        .photosPicker(isPresented: $galeria, selection: $item, matching: .images, photoLibrary: .shared())
        .fullScreenCover(isPresented: $camara) {
            Camara { imagen in
                camara = false
                guard let imagen else { return }
                // Recién sacada: la fecha es ahora. Redibujarla la deja derecha y sin EXIF ni ubicación.
                preparar {
                    FotoReducida.jpeg(imagen, maxPx: CGFloat(FotosInicio.maxPx), calidad: FotosInicio.calidad).flatMap { PreparacionFotoInicio.deJPEG($0, tomadaEn: nil) }
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: item) { _, nuevo in
            guard let nuevo else { return }
            item = nil
            preparando = true
            ilegible = false
            Task {
                // Los datos originales: de ahí sale la fecha en que se sacó, antes de reducirla (ImageIO no decodifica entera una de 48 MP).
                let datos = try? await nuevo.loadTransferable(type: Data.self)
                let p = await Task.detached(priority: .userInitiated) { datos.flatMap { PreparacionFotoInicio.preparar($0) } }.value
                preparando = false
                if let p { alPreparar(p) } else { ilegible = true }
            }
        }
    }
}
