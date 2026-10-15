import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Fotos de la semana (REV-02…05): frente, perfil y espalda desde la cámara o la galería (JPEG de 900 px a 0,7, sin
/// ubicación). Cada lugar es un marco vertical; con la foto subida muestra la miniatura firmada. La cola de fotos es
/// propia (`ModeloFotos`): sin señal la foto queda guardada y se sube sola. En la demo y en los bocetos no se sube nada.
struct FotosSemana: View {
    /// El modelo real, o nil con las muestras.
    let modelo: ModeloFotos?
    let muestras: [FotoProgreso]
    /// Para el pie del comparador ("8 semanas · −2,4 kg").
    let peso: [PesoCorporal.Punto]
    @State private var mensaje: String?
    @State private var galeria = false
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private var fotos: [FotoProgreso] { modelo?.fotos ?? muestras }
    private var semana: String { modelo?.semanaActual ?? FotosProgreso.lunes(FechaLocal.hoy()) }
    private var hechas: Set<String> {
        modelo?.posesDeLaSemana ?? FotosProgreso.posesDeLaSemana(muestras, pendientes: [], semana: semana)
    }

    var body: some View {
        let semanas = FotosProgreso.semanas(fotos)
        let racha = FotosProgreso.racha(fotos)
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Fotos de la semana", detalle: hechas.count == 3 ? "Completas" : "\(hechas.count)/3")
            VStack(alignment: .leading, spacing: Espacio.m) {
                Label {
                    Text("Mismo lugar, misma luz, en ayunas. Las ve \(Text("solo Mati").bold()): no se publican ni salen de la app.")
                } icon: {
                    Image(systemName: "lock.fill").foregroundStyle(Color.marcaTexto)
                }
                .labelStyle(EtiquetaCompacta())
                .font(.footnote)
                .foregroundStyle(.secondary)

                // Con letra de accesibilidad, los tres marcos pasan a ser filas (no entran las palabras).
                let disposicion = tamañoLetra.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Espacio.xs))
                    : AnyLayout(HStackLayout(spacing: Espacio.s))
                disposicion {
                    ForEach(FotosProgreso.poses, id: \.clave) { pose in lugar(pose) }
                }

                if let mensaje {
                    Text(mensaje)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(mensaje.hasPrefix("No") || mensaje.hasPrefix("Esa") || mensaje.hasPrefix("Hay") ? Color.alerta : Color.marcaTexto)
                        .transition(.opacity)
                }

                if racha >= 2 {
                    Label("\(racha) semanas seguidas registradas", systemImage: "flame.fill")
                        .labelStyle(IconoTeñido(color: .alerta))
                        .font(.subheadline.weight(.semibold))
                }

                if semanas.isEmpty {
                    Text("Con la primera foto arranca tu historial. Mismo lugar y misma luz cada semana: así la comparación muestra tu cambio y no el del ambiente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Ver mis fotos · \(semanas.count) semana\(semanas.count == 1 ? "" : "s")") { galeria = true }
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    if semanas.count < 4 {
                        Text("El comparador antes/después se abre en \(4 - semanas.count) semana\(4 - semanas.count > 1 ? "s" : "") más.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .tarjeta()
            .animation(.snappy, value: mensaje)
        }
        // Las miniaturas y la galería van con URLs firmadas (duran 1 h; se piden de nuevo a los 50 min).
        .task(id: fotos.count) { if let modelo, !modelo.fotos.isEmpty { await modelo.firmar() } }
        .sheet(isPresented: $galeria) { GaleriaFotos(modelo: modelo, fotos: fotos, peso: peso) }
    }

    @ViewBuilder
    private func lugar(_ pose: (clave: String, etiqueta: String)) -> some View {
        let clave = "\(semana)|\(pose.clave)"
        let estado = MarcoPose.Estado(lista: hechas.contains(pose.clave),
                                      subiendo: modelo?.subiendo.contains(clave) ?? false,
                                      esperando: modelo?.pendientes[clave] != nil,
                                      miniatura: modelo?.urls[clave])
        let marco = MarcoPose(nombre: pose.etiqueta, estado: estado, enFila: tamañoLetra.isAccessibilitySize)
        if let modelo {
            BotonFoto(maxPx: 900, calidad: 0.7, alElegir: { jpeg in
                Task {
                    let r = await modelo.subir(pose: pose.clave, jpeg: jpeg)
                    withAnimation(.snappy) { mensaje = r.texto }
                }
            }) { marco }
            .disabled(estado.subiendo)
            .sensoryFeedback(.success, trigger: estado.lista) { _, nueva in nueva }
            .accessibilityLabel("Foto de \(pose.etiqueta.lowercased())\(estado.lista ? ", lista" : "")")
            .accessibilityHint("Sacá la foto o elegila de la galería")
        } else {
            Button { withAnimation(.snappy) { mensaje = "En la demo las fotos no se guardan." } } label: { marco }
                .buttonStyle(.plain)
                .accessibilityLabel("Foto de \(pose.etiqueta.lowercased())")
        }
    }
}

/// Marco vertical punteado con la cámara; subiendo, con un indicador; con la foto, la miniatura y el tilde de marca.
/// `enFila`: la versión horizontal para letra de accesibilidad.
private struct MarcoPose: View {
    struct Estado {
        var lista: Bool
        var subiendo: Bool
        var esperando: Bool
        var miniatura: URL?
    }

    let nombre: String
    let estado: Estado
    var enFila = false

    private var detalle: String {
        if estado.subiendo { return "Subiendo…" }
        if estado.esperando { return "Esperando señal" }
        return estado.lista ? "Lista" : "Agregar"
    }

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: Radio.control + 4, style: .continuous)
        Group {
            if enFila {
                HStack(spacing: Espacio.s) {
                    icono
                    VStack(alignment: .leading, spacing: 0) {
                        Text(nombre).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        Text(detalle).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Espacio.s)
            } else {
                // El marco pone el tamaño (un tercio del ancho, 3:4); la foto va detrás y no lo empuja, y el nombre y
                // el tilde se ubican contra el marco.
                Color.clear
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background {
                        if let url = estado.miniatura {
                            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { f in
                                if let img = f.image { img.resizable().scaledToFill() } else { Color.campo }
                            }
                        }
                    }
                    .overlay {
                        if estado.miniatura == nil {
                            VStack(spacing: Espacio.xs) {
                                icono
                                Text(nombre).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    .lineLimit(1).minimumScaleFactor(0.75)
                                Text(detalle).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if estado.miniatura != nil {
                            Text(nombre)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.top, 14)
                                .padding(.bottom, 8)
                                .frame(maxWidth: .infinity)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if estado.miniatura != nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(Color.sobreMarca)
                                .frame(width: 22, height: 22)
                                .background(Color.marca, in: .circle)
                                .padding(8)
                        }
                    }
                    .clipShape(forma)
            }
        }
        .background(Color.campo.opacity(0.5), in: forma)
        .overlay {
            forma.strokeBorder(estado.lista ? Color.marcaVivo.opacity(0.6) : Color.secondary.opacity(0.35),
                               style: StrokeStyle(lineWidth: 1.5, dash: estado.lista ? [] : [6, 5]))
        }
        .contentShape(forma)
    }

    @ViewBuilder private var icono: some View {
        ZStack {
            if estado.subiendo {
                ProgressView().tint(Color.marcaTexto)
            } else {
                Image(systemName: estado.lista ? "checkmark" : (estado.esperando ? "icloud.and.arrow.up" : "camera.fill"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(estado.lista ? Color.sobreMarca : Color.marcaTexto)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .frame(width: 42, height: 42)
        .background(estado.lista ? Color.marca : Color.marcaSuave, in: .circle)
    }
}

/// Mis fotos por semana (REV-04), y desde las 4 semanas el comparador antes/después (antes compara luz y retención de
/// líquido, no cambios reales).
private struct GaleriaFotos: View {
    let modelo: ModeloFotos?
    let fotos: [FotoProgreso]
    let peso: [PesoCorporal.Punto]
    @Environment(\.dismiss) private var cerrar
    @State private var pose = "frente"

    private var semanas: [String] { FotosProgreso.semanas(fotos) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.l) {
                    if semanas.count >= 4, let primera = semanas.first, let ultima = semanas.last {
                        comparador(primera: primera, ultima: ultima)
                    }
                    ForEach(semanas.reversed(), id: \.self) { s in semana(s) }
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .background(Color.fondo)
            .navigationTitle("Mis fotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { cerrar() }.fontWeight(.semibold) } }
            .task { await modelo?.firmar() }
        }
        .presentationDragIndicator(.visible)
    }

    private func comparador(primera: String, ultima: String) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Antes y ahora", detalle: FotosProgreso.resumenComparador(primera: primera, ultima: ultima, peso: peso))
            Picker("Pose", selection: $pose) {
                ForEach(FotosProgreso.poses, id: \.clave) { Text($0.etiqueta).tag($0.clave) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: Espacio.s) {
                foto(semana: primera, pose: pose, rotulo: Self.fecha(primera))
                foto(semana: ultima, pose: pose, rotulo: Self.fecha(ultima))
            }
        }
        .tarjeta()
    }

    private func semana(_ s: String) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text("Semana del \(Self.fecha(s))").font(.headline).padding(.horizontal, 4)
            HStack(spacing: Espacio.s) {
                ForEach(FotosProgreso.poses, id: \.clave) { p in foto(semana: s, pose: p.clave, rotulo: p.etiqueta) }
            }
        }
    }

    private func foto(semana: String, pose: String, rotulo: String) -> some View {
        let url = modelo?.urls["\(semana)|\(pose)"]
        let hay = fotos.contains { $0.semanaLunes == semana && $0.pose == pose }
        return VStack(spacing: 6) {
            Color.campo
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay {
                    if let url {
                        // La ruedita, solo mientras baja: si la foto no se pudo traer (sin señal, la URL firmada vencida, una
                        // foto rota) queda el ícono. Antes giraba para siempre (lo encontró el gemelo de Android, 15-oct).
                        AsyncImage(url: url) { f in
                            switch f {
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Image(systemName: "photo").foregroundStyle(.tertiary)
                            default: ProgressView()
                            }
                        }
                    } else {
                        Image(systemName: hay ? "photo" : "camera").foregroundStyle(.tertiary)
                    }
                }
                .clipShape(.rect(cornerRadius: Radio.control, style: .continuous))
            Text(rotulo).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rotulo)\(hay ? "" : ", sin foto")")
    }

    /// "12 de octubre".
    static func fecha(_ lunes: String) -> String {
        Fechas.dia(lunes)?.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "es_AR"))) ?? lunes
    }
}
