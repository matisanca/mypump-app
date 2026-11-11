import SwiftUI
import ImageIO
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// De dónde salen las fotos de «Tu cambio»: las de progreso (servidor y cola) y las de inicio guiadas, más el peso para el
/// pie. Solo lee lo que la app ya tiene; no hay ninguna llamada nueva (las URLs firmadas son las de siempre).
@MainActor
struct FuentesTuCambio {
    let fotos: ModeloFotos?
    let inicio: ModeloFotosInicio?
    let peso: [PesoCorporal.Punto]

    enum Imagen: Equatable, Sendable {
        case url(URL)
        case archivo(URL)
        case datos(String)
    }

    /// Las de progreso como (semana, pose): las del servidor y las que esperan subir.
    var entradas: [(semana: String, pose: String)] {
        guard let fotos else { return [] }
        return fotos.fotos.map { ($0.semanaLunes, $0.pose) } + fotos.pendientes.values.map { (FotosProgreso.lunes($0.fecha), $0.pose) }
    }

    /// Pose → fecha local de la foto de inicio (la de la cola, que es la más nueva, o la del servidor).
    var fechasInicio: [String: String] {
        guard let inicio, inicio.visible else { return [:] }
        var r: [String: String] = [:]
        for p in FotosProgreso.poses.map(\.clave) {
            let iso = inicio.cola.last(where: { $0.pose == p })?.tomadaEn ?? inicio.estado?.foto(pose: p)?.tomadaEn
            if let iso, let f = TuCambio.fechaLocal(iso) { r[p] = f }
        }
        return r
    }

    func vista(pose: String) -> TuCambio.Vista {
        TuCambio.vista(fotos: entradas, inicio: fechasInicio, semanaActual: fotos?.semanaActual ?? FotosProgreso.lunes(FechaLocal.hoy()),
                       pose: pose, peso: peso)
    }

    func imagen(_ foto: TuCambio.Foto?, pose: String) -> Imagen? {
        guard let foto else { return nil }
        switch foto.origen {
        case .inicio:
            guard let inicio, let v = inicio.foto(pose) else { return nil }
            if let a = v.archivoLocal { return .archivo(a) }
            return inicio.urls[v.id].map(Imagen.url)
        case .progreso:
            let clave = "\(foto.semana)|\(pose)"
            // La que espera subir es la más nueva (reemplaza a la del servidor).
            if let p = fotos?.pendientes[clave] { return .datos(p.dataUrl) }
            return fotos?.urls[clave].map(Imagen.url)
        }
    }

    /// Cambia cuando cambian las fotos (no solo cuántas): vuelve a pedir las URLs si hace falta.
    var claveFirma: [String] {
        entradas.map { "\($0.semana)|\($0.pose)" }.sorted() + fechasInicio.map { "i|\($0.key)|\($0.value)" }.sorted()
    }

    /// Las URLs firmadas de las dos fuentes (cada modelo guarda las suyas 50 minutos).
    func firmar() async {
        if let fotos, !fotos.fotos.isEmpty { await fotos.firmar() }
        if let inicio, inicio.visible { await inicio.firmar() }
    }
}

/// «Tu cambio» en Revisión (detrás de `check_guiado`), debajo de la tarjeta del check: la semana 1 al lado de la última,
/// por pose, con el pie de siempre. Tocarla abre el comparador a pantalla completa. Sin ningún botón de compartir: las
/// fotos son privadas.
struct TuCambioTarjeta: View {
    let fuentes: FuentesTuCambio
    @State private var pose = TuCambio.poseInicial
    @State private var comparador = false

    var body: some View {
        let v = fuentes.vista(pose: pose)
        VStack(alignment: .leading, spacing: Espacio.m) {
            Text(TuCambio.titulo)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            if v.modo == .par {
                SelectorPoseTuCambio(pose: $pose)
                // Tocar las fotos abre el comparador; para el lector cada foto es su propio elemento y el camino es el botón.
                ParTuCambio(vista: v, fuentes: fuentes)
                    .contentShape(.rect)
                    .onTapGesture { comparador = true }
                if let pie = v.pie {
                    Text(pie)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityIdentifier("tucambio-pie")
                }
                Button(TuCambio.botonVer) { comparador = true }
                    .buttonStyle(BotonSecundario(tono: .marcaTexto))
                    .accessibilityIdentifier("tucambio-ver")
            } else {
                HStack(alignment: .top, spacing: Espacio.m) {
                    if v.antes != nil {
                        MarcoTuCambio(imagen: fuentes.imagen(v.antes, pose: v.pose), rotulo: v.rotuloAntes, accesible: v.accesibleAntes,
                                      vacio: TuCambio.sinFoto(v.pose), id: "tucambio-antes")
                            .frame(maxWidth: 150)
                    }
                    Text(v.texto ?? "")
                        .font(.body)
                        .foregroundStyle(Color.apoyo)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("tucambio-espera")
                }
            }
        }
        .tarjeta()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tucambio-tarjeta")
        .task(id: fuentes.claveFirma) { await fuentes.firmar() }
        .fullScreenCover(isPresented: $comparador) {
            GaleriaFotos(modelo: fuentes.fotos, fotos: fuentes.fotos?.fotos ?? [], peso: fuentes.peso, tuCambio: fuentes, poseInicial: pose)
        }
    }
}

/// La semana 1 y la última, lado a lado (también con letra grande: es una comparación).
struct ParTuCambio: View {
    let vista: TuCambio.Vista
    let fuentes: FuentesTuCambio

    var body: some View {
        HStack(alignment: .top, spacing: Espacio.s) {
            MarcoTuCambio(imagen: fuentes.imagen(vista.antes, pose: vista.pose), rotulo: vista.rotuloAntes, accesible: vista.accesibleAntes,
                          vacio: TuCambio.sinFoto(vista.pose), id: "tucambio-antes")
            MarcoTuCambio(imagen: fuentes.imagen(vista.despues, pose: vista.pose), rotulo: vista.rotuloDespues, accesible: vista.accesibleDespues,
                          vacio: vista.vacioDespues, id: "tucambio-despues")
        }
    }
}

/// Frente / Perfil / Espalda: tres botones grandes con texto (48 de alto); el elegido, verde lleno. Con letra grande se apilan.
struct SelectorPoseTuCambio: View {
    @Binding var pose: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Espacio.xs) { botones }
            VStack(spacing: Espacio.xs) { botones }
        }
    }

    @ViewBuilder private var botones: some View {
        ForEach(FotosProgreso.poses, id: \.clave) { p in
            let elegida = pose == p.clave
            Button { withAnimation(.snappy(duration: 0.2)) { pose = p.clave } } label: {
                Text(p.etiqueta)
                    .font(.headline)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, Espacio.s)
                    .foregroundStyle(elegida ? Color.sobreMarca : Color.primary)
                    .background(elegida ? Color.marca : Color.campo, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(elegida ? [.isSelected] : [])
            .accessibilityIdentifier("tucambio-pose-\(p.clave)")
        }
    }
}

/// Una foto vertical 3:4 con su rótulo debajo. Sin foto: el marco gris con «Sin foto de perfil».
struct MarcoTuCambio: View {
    let imagen: FuentesTuCambio.Imagen?
    let rotulo: String
    let accesible: String
    let vacio: String
    let id: String

    var body: some View {
        VStack(spacing: 6) {
            Color.campo
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let imagen {
                        ImagenTuCambio(imagen: imagen)
                    } else {
                        Text(vacio)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(Espacio.xs)
                    }
                }
                .clipShape(.rect(cornerRadius: Radio.control, style: .continuous))
            if !rotulo.isEmpty {
                Text(rotulo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accesible)
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier(id)
    }
}

/// La imagen de una fuente: la URL firmada, el archivo de la cola de inicio o el JPEG de la cola de progreso.
struct ImagenTuCambio: View {
    let imagen: FuentesTuCambio.Imagen
    @State private var local: UIImage?

    var body: some View {
        switch imagen {
        case .url(let u):
            AsyncImage(url: u) { f in
                switch f {
                case .success(let i): i.resizable().scaledToFill()
                case .failure: Image(systemName: "photo").foregroundStyle(.tertiary)
                default: ProgressView()
                }
            }
        case .archivo, .datos:
            Group {
                if let local { Image(uiImage: local).resizable().scaledToFill() } else { Color.campo }
            }
            .task(id: imagen) {
                let i = imagen
                local = await Task.detached(priority: .utility) { Self.leer(i) }.value
            }
        }
    }

    /// Reducida fuera del hilo principal (900 px de lado largo: alcanza para pantalla completa).
    nonisolated private static func leer(_ i: FuentesTuCambio.Imagen) -> UIImage? {
        let fuente: CGImageSource?
        switch i {
        case .archivo(let u): fuente = CGImageSourceCreateWithURL(u as CFURL, nil)
        case .datos(let d):
            guard let coma = d.firstIndex(of: ","), let datos = Data(base64Encoded: String(d[d.index(after: coma)...])) else { return nil }
            fuente = CGImageSourceCreateWithData(datos as CFData, nil)
        case .url: return nil
        }
        guard let fuente, let c = CGImageSourceCreateThumbnailAtIndex(fuente, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                                kCGImageSourceThumbnailMaxPixelSize: 900,
                                                                                kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: c)
    }
}
