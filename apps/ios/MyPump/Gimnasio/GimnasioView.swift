import ImageIO
import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosGimnasio

/// La tarjeta «Tu gimnasio» arriba en Entreno. Sin cuenta, con la palanca apagada o sin el servidor nuevo, no existe.
struct TarjetaGimnasio: View {
    @State private var app = Proveedor.modelo
    @State private var abierta = false

    var body: some View {
        // Si está abierta queda en pie aunque deje de hacer falta: si no, la hoja se cierra antes de ver «Recibido».
        if let m = app.gimnasio, m.tarjetaVisible || abierta || ofrecerCasa {
            VStack(spacing: Espacio.xs) {
            // Con el gimnasio ya cargado la tarjeta no va, pero el botón de casa sí: nadie queda a tres toques.
            if m.tarjetaVisible || (abierta && !ofrecerCasa) {
            Button { abierta = true } label: {
                HStack(spacing: Espacio.s) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(width: 42, height: 42)
                        .background(Color.marcaSuave, in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T.tarjetaTitulo).font(.headline).foregroundStyle(.primary)
                        Text(detalle(m)).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tarjeta()
            }
            .buttonStyle(FilaPresionable())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("gimnasio-tarjeta")
            }
            // «¿Entrenás en casa? Tocá acá» (2.3.0): mientras no entrene en casa y se pueda cambiar, un botón grande que
            // abre Tu gimnasio con el interruptor arriba de todo. Así queda a dos toques.
            if ofrecerCasa {
                Button(TextosColaB.Casa.tarjeta) { abierta = true }
                    .buttonStyle(BotonSecundario(tono: .marcaTexto))
                    .accessibilityIdentifier("casa-tarjeta")
            }
            }
            .sheet(isPresented: $abierta) {
                GimnasioRaiz(modelo: m, alCerrar: { abierta = false })
                    .presentationDragIndicator(.visible)
            }
        }
    }

    /// Palanca `casa` prendida, habilitado para la cuenta, y el interruptor apagado y libre.
    private var ofrecerCasa: Bool {
        guard app.palanca.casa, app.gimnasio?.estado != nil, let c = app.casa, c.visible else { return false }
        return !c.prendido && !c.fijo
    }

    private func detalle(_ m: ModeloGimnasio) -> String {
        // Con la carga de casa abierta no hay zonas que falten: lo que falta es marcar lo que tiene.
        if app.palanca.casa, let c = app.casa, c.visible {
            switch c.pantalla {
            case .lista: return TextosColaB.Casa.listaTitulo
            case .recibido: return T.recibido
            default: break
            }
        }
        switch m.pantalla {
        case .zonas: return m.faltantes.isEmpty ? T.revisarYEnviar : T.faltanZonas(m.faltantes.count)
        case .recibido: return T.recibido
        case .preguntas: return T.confirmarTarjeta
        default: return T.inicioBajada
        }
    }
}

/// Lo que se apila arriba de la raíz.
private enum DestinoGimnasio: Hashable {
    case zona(String), revisar, yaNoEsta
}

/// Elige la pantalla según lo que diga el servidor (`CONTRATO_APP.md`, sección 4).
struct GimnasioRaiz: View {
    let modelo: ModeloGimnasio
    let alCerrar: () -> Void
    @State private var camino: [DestinoGimnasio] = []
    @State private var app = Proveedor.modelo
    @Environment(\.dynamicTypeSize) private var letra

    /// «Entreno en casa», si la palanca `casa` está prendida y el servidor lo habilita para esta cuenta.
    private var casa: ModeloCasa? {
        guard app.palanca.casa, let c = app.casa, c.visible else { return nil }
        return c
    }

    private var destino: Binding<DestinoGimnasio?> {
        Binding(get: { camino.last }, set: { d in camino = d.map { [$0] } ?? [] })
    }

    // Una pila propia con `path`: `navigationDestination(item:)` dejaba la app en un bucle al 100 % de CPU en iOS 17, y sin
    // pila explícita no hay cómo volver a la raíz cuando la carga cambia de etapa.
    var body: some View {
        NavigationStack(path: $camino) {
            Group {
                if modelo.estado == nil {
                    Color.fondo
                } else if modelo.envio != nil {
                    EnviandoGimnasio(modelo: modelo)
                } else if let c = casa, c.pantalla != .ninguna {
                    // «Entreno en casa» (2.3.0): la carga es de su casa, sin zonas ni fotos.
                    CasaPantalla(casa: c, gimnasio: modelo)
                } else {
                    VStack(spacing: 0) {
                        // El interruptor, arriba de todo y siempre. Con la letra muy grande va sin la bajada: fijo y entero
                        // le sacaba media pantalla a lo de abajo.
                        if let c = casa {
                            InterruptorCasa(casa: c, gimnasio: modelo, compacto: letra.isAccessibilitySize)
                                .padding(.horizontal, Espacio.m).padding(.top, Espacio.s).padding(.bottom, Espacio.xs)
                                .anchoLectura()
                        }
                        switch modelo.pantalla {
                        case .inicio: ArranqueGimnasio(modelo: modelo)
                        case .zonas: ZonasGimnasio(modelo: modelo, destino: destino)
                        case .recibido: RecibidoGimnasio()
                        case .preguntas: PreguntasGimnasio(modelo: modelo)
                        case .listo: ListoGimnasio(modelo: modelo, destino: destino)
                        }
                    }
                }
            }
            .background(Color.fondo)
            .navigationTitle(T.tarjetaTitulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar, action: alCerrar) } }
            .navigationDestination(for: DestinoGimnasio.self) { d in
                switch d {
                case .zona(let clave):
                    if let z = Gimnasio.zonas.first(where: { $0.clave == clave }) { ZonaGimnasio(modelo: modelo, zona: z) }
                case .revisar: RevisarGimnasio(modelo: modelo)
                case .yaNoEsta: YaNoEstaGimnasio(modelo: modelo)
                }
            }
        }
        .task { await modelo.refrescar(); modelo.drenarEnFondo(); if app.palanca.casa { await app.casa?.refrescar() } }
        .onChange(of: modelo.estado == nil) { _, apagado in if apagado { alCerrar() } }
        // Si la carga pasó a otra etapa, se vuelve a la raíz: lo que importa es lo que dice ella.
        .onChange(of: "\(modelo.pantalla)-\(modelo.envio != nil)-\(casa?.pantalla ?? .ninguna)") { _, _ in camino = [] }
    }
}

/// Texto suave de error o estado, siempre con el mismo aspecto.
private struct NotaGimnasio: View {
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

/// Por qué no salió lo enviado.
private struct AvisoEnvioGimnasio: View {
    let modelo: ModeloGimnasio

    var body: some View {
        switch modelo.avisoEnvio {
        case .faltan(let f)?: NotaGimnasio(texto: T.faltanZonas(f.count), alerta: true).accessibilityIdentifier("gimnasio-aviso-envio")
        case .sinNovedad?: NotaGimnasio(texto: T.sinNovedad, alerta: true).accessibilityIdentifier("gimnasio-aviso-envio")
        case .error?: NotaGimnasio(texto: T.errorGenerico, alerta: true).accessibilityIdentifier("gimnasio-aviso-envio")
        case nil: EmptyView()
        }
    }
}

/// Sin carga abierta no hay nada que leer: abre una sola y sigue a las zonas. Solo se queda acá si no se pudo.
private struct ArranqueGimnasio: View {
    let modelo: ModeloGimnasio
    @State private var error: String?
    @State private var ocupado = false

    var body: some View {
        VStack(spacing: Espacio.m) {
            if let error {
                NotaGimnasio(texto: error, alerta: true)
                Button(T.botonReintentar) { Task { await empezar() } }
                    .buttonStyle(BotonMarca())
                    .disabled(ocupado)
                    .accessibilityIdentifier("gimnasio-reintentar")
            } else {
                ProgressView().accessibilityIdentifier("gimnasio-arrancando")
            }
        }
        .padding(Espacio.m)
        .anchoLectura()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await empezar() }
    }

    private func empezar() async {
        guard !ocupado, modelo.abierta == nil else { return }
        ocupado = true
        defer { ocupado = false }
        switch await modelo.empezar() {
        // Abrió la carga pero no se pudo traer: sin esto quedaría cargando para siempre.
        case .ok: error = modelo.abierta == nil ? T.sinSenal : nil
        case .sinSenal: error = T.sinSenal
        default: error = T.errorGenerico
        }
    }
}

/// Una fila que apila otra pantalla, con el mismo aspecto que un enlace de lista.
private struct FilaApilar<Contenido: View>: View {
    let accion: () -> Void
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        Button(action: accion) {
            HStack(spacing: Espacio.s) {
                contenido().frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .foregroundStyle(.primary)
    }
}

private struct ZonasGimnasio: View {
    let modelo: ModeloGimnasio
    @Binding var destino: DestinoGimnasio?

    // Sin `List`: en iOS 17 esta lista con su encabezado dejaba la app en un bucle de layout al 100 % de CPU.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    if modelo.abierta?.modo == "completa", !modelo.faltantes.isEmpty {
                        Text(T.faltanZonas(modelo.faltantes.count)).font(.headline).accessibilityAddTraits(.isHeader)
                    }
                    NotaGimnasio(texto: T.consejoPermiso)
                    aviso
                    AvisoEnvioGimnasio(modelo: modelo)
                }
                VStack(spacing: 0) {
                    ForEach(Array(Gimnasio.zonas.enumerated()), id: \.element.clave) { i, z in
                        if i > 0 { Divider().padding(.leading, 44) }
                        FilaApilar(accion: { destino = .zona(z.clave) }) { fila(z) }
                            .padding(.horizontal, Espacio.m)
                            .frame(minHeight: 56)
                            .accessibilityIdentifier("gimnasio-zona-\(z.clave)")
                    }
                }
                .tarjeta(relleno: 0)
                Button(T.revisarYEnviar) { destino = .revisar }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("gimnasio-revisar")
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
    }

    @ViewBuilder private var aviso: some View {
        if let a = modelo.avisoFoto { NotaGimnasio(texto: a == .tope ? T.tope : T.fotoRechazada, alerta: true).accessibilityIdentifier("gimnasio-aviso-foto") }
    }

    private func faltaEnElEnvio(_ clave: String) -> Bool {
        if case .faltan(let f)? = modelo.avisoEnvio { f.contains(clave) } else { false }
    }

    private func fila(_ z: Gimnasio.Zona) -> some View {
        let fotos = modelo.fotos(zona: z.clave)
        let no = modelo.noHay.contains(z.clave) && fotos.isEmpty
        let detalle = no ? T.noHayCorto : fotos.isEmpty ? (z.clave == Gimnasio.zonaOpcional ? T.opcional : T.sinFotos) : T.cuentaFotos(fotos.count)
        let lista = no || !fotos.isEmpty
        return HStack(spacing: Espacio.s) {
            Image(systemName: lista ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(lista ? Color.marcaTexto : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(z.nombre).font(.body)
                Text(detalle).font(.caption).foregroundStyle(faltaEnElEnvio(z.clave) ? Color.alerta : .secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ZonaGimnasio: View {
    let modelo: ModeloGimnasio
    let zona: Gimnasio.Zona
    @State private var error: String?

    private var fotos: [ModeloGimnasio.VistaFoto] { modelo.fotos(zona: zona.clave) }
    private var noHay: Bool { modelo.noHay.contains(zona.clave) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(zona.pedido).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(T.consejoCamara).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gimnasio-consejo")

                if !fotos.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Espacio.s)], spacing: Espacio.s) {
                        ForEach(fotos) { f in
                            MiniaturaFoto(foto: f, url: modelo.urls[f.id]) { Task { await borrar(f) } }
                        }
                    }
                }
                if let a = modelo.avisoFoto { NotaGimnasio(texto: a == .tope ? T.tope : T.fotoRechazada, alerta: true).accessibilityIdentifier("gimnasio-aviso-foto") }
                if let error { NotaGimnasio(texto: error, alerta: true) }

                AgregarFotoGimnasio(puede: modelo.puedeAgregar) { jpeg in
                    switch modelo.agregar(zona: zona.clave, jpeg: jpeg) {
                    case .guardada: error = nil; modelo.drenarEnFondo()
                    case .tope: error = T.tope
                    case .noSeGuardo: error = T.noSeGuardo
                    }
                } contenido: {
                    Label(T.agregarFoto, systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 54)
                        .font(.headline).foregroundStyle(Color.sobreMarca)
                        .background(modelo.puedeAgregar ? Color.marca : Color.secondary, in: .capsule)
                }
                .accessibilityIdentifier("gimnasio-agregar-foto")

                if zona.clave != Gimnasio.zonaOpcional, modelo.abierta?.modo == "completa", fotos.isEmpty {
                    Button { modelo.marcarNoHay(zona.clave, !noHay) } label: {
                        Label(T.noHay, systemImage: noHay ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(BotonSecundario(tono: noHay ? .marcaTexto : .primary))
                    .accessibilityAddTraits(noHay ? .isSelected : [])
                    .accessibilityIdentifier("gimnasio-no-hay")
                }
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(zona.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: fotos.count) { await firmar() }
        .onDisappear { modelo.limpiarAvisoFoto() }
    }

    private func firmar() async {
        guard let a = modelo.abierta else { return }
        let ids = fotos.filter { $0.archivoLocal == nil }.map(\.id)
        if !ids.isEmpty { await modelo.firmar(gimnasioId: a.id, ids: ids) }
    }

    private func borrar(_ f: ModeloGimnasio.VistaFoto) async {
        switch await modelo.borrarFoto(id: f.id) {
        case .ok: error = nil
        case .sinSenal: error = T.sinSenal
        default: error = T.errorGenerico
        }
    }
}

/// `BotonFoto` a 1600 px y 0,8, sin EXIF. En las pruebas, un JPEG armado acá (el simulador no tiene cámara).
struct AgregarFotoGimnasio<Contenido: View>: View {
    let puede: Bool
    let alElegir: (Data) -> Void
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "gimnasioDePrueba") != nil {
            Button {
                if let j = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image(actions: { c in
                    UIColor.systemGray3.setFill(); c.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
                }).jpegData(compressionQuality: 0.8) { alElegir(j) }
            } label: { contenido() }
            .buttonStyle(.plain)
            .disabled(!puede)
        } else { real }
        #else
        real
        #endif
    }

    private var real: some View {
        BotonFoto(maxPx: CGFloat(Gimnasio.maxPx), calidad: Gimnasio.calidad, alElegir: alElegir, etiqueta: contenido)
            .disabled(!puede)
    }
}

private struct MiniaturaFoto: View {
    let foto: ModeloGimnasio.VistaFoto
    let url: URL?
    let borrar: () -> Void

    var body: some View {
        Color.campo
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let f = foto.archivoLocal {
                    MiniaturaLocal(archivo: f)
                } else if let url {
                    AsyncImage(url: url) { fase in
                        if let i = fase.image { i.resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(.tertiary) }
                    }
                } else {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                }
            }
            .overlay(alignment: .bottom) {
                if foto.subiendo || foto.esperando {
                    Text(foto.subiendo ? T.subiendo : T.esperandoSenal)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(4).frame(maxWidth: .infinity).background(.black.opacity(0.55))
                }
            }
            .clipShape(.rect(cornerRadius: Radio.control, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button(action: borrar) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(.black.opacity(0.6), in: .circle)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(T.borrarFoto)
                .accessibilityIdentifier("gimnasio-borrar-foto")
            }
    }
}

/// La foto del disco, reducida fuera del hilo principal: en una zona puede haber varias de 1600 px.
private struct MiniaturaLocal: View {
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

private struct RevisarGimnasio: View {
    let modelo: ModeloGimnasio
    @State private var nota = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    ForEach(Gimnasio.zonas) { z in
                        HStack {
                            Text(z.nombre).font(.subheadline)
                            Spacer()
                            let n = modelo.fotos(zona: z.clave).count
                            Text(n > 0 ? T.cuentaFotos(n) : modelo.noHay.contains(z.clave) ? T.noHayCorto : z.clave == Gimnasio.zonaOpcional ? T.opcional : T.sinFotos)
                                .font(.subheadline).foregroundStyle(modelo.faltantes.contains(z.clave) ? Color.alerta : .secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .tarjeta()

                VStack(alignment: .leading, spacing: Espacio.xs) {
                    TextField(T.notaPlaceholder, text: $nota, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(Espacio.s)
                        .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                        .accessibilityIdentifier("gimnasio-nota")
                    Text("\(nota.count)/\(Gimnasio.maxNota)").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !modelo.faltantes.isEmpty {
                    NotaGimnasio(texto: T.faltanZonas(modelo.faltantes.count), alerta: true).accessibilityIdentifier("gimnasio-faltan")
                }
                AvisoEnvioGimnasio(modelo: modelo)
                Button(T.botonEnviar) { modelo.fijarNota(nota); Task { await modelo.enviarCarga() } }
                    .buttonStyle(BotonMarca())
                    .disabled(!modelo.puedeEnviar)
                    .accessibilityIdentifier("gimnasio-enviar")
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(T.revisarTitulo)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { nota = modelo.nota }
        .onChange(of: nota) { _, n in
            if n.count > Gimnasio.maxNota { nota = Gimnasio.notaRecortada(n) }
            modelo.fijarNota(nota)
        }
    }
}

private struct EnviandoGimnasio: View {
    let modelo: ModeloGimnasio

    var body: some View {
        VStack(spacing: Espacio.m) {
            ProgressView().controlSize(.large)
            if !modelo.cola.isEmpty {
                Text(T.subiendoFotos(modelo.subidasEnvio, de: max(modelo.totalEnvio, modelo.subidasEnvio + modelo.cola.count)))
                    .font(.headline).multilineTextAlignment(.center)
            }
            Text(T.enviandoSeguir).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .accessibilityIdentifier("gimnasio-enviando")
            Button(T.volverAEditar) { modelo.cancelarEnvio() }
                .buttonStyle(BotonSecundario())
                .accessibilityIdentifier("gimnasio-volver-editar")
        }
        .padding(Espacio.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecibidoGimnasio: View {
    var body: some View {
        VStack(spacing: Espacio.m) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
            Text(T.recibido).font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Espacio.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("gimnasio-recibido")
    }
}

private struct ListoGimnasio: View {
    let modelo: ModeloGimnasio
    @Binding var destino: DestinoGimnasio?
    @State private var error: String?

    private var v: CargaGimnasio? { modelo.vigente }

    var body: some View {
        List {
            Section {
                if let t = titulo { Text(t).font(.headline).accessibilityIdentifier("gimnasio-resultado") }
                if let error { NotaGimnasio(texto: error, alerta: true) }
            }
            ForEach(Gimnasio.zonas) { z in
                let equipos = (v?.equipos ?? []).filter { $0.zona == z.clave }
                if !equipos.isEmpty {
                    Section(z.nombre) {
                        ForEach(equipos, id: \.tipo) { e in
                            HStack {
                                Text(e.nombre)
                                Spacer()
                                if e.cantidad > 1 { Text("×\(e.cantidad)").foregroundStyle(.secondary) }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            Section {
                Button(T.faltaAlgo) { empezar("parcial") }.accessibilityIdentifier("gimnasio-falta-algo")
                FilaApilar(accion: { destino = .yaNoEsta }) { Text(T.yaNoEsta) }.accessibilityIdentifier("gimnasio-ya-no-esta")
                Button(T.cambieDeGimnasio) { empezar("completa") }.accessibilityIdentifier("gimnasio-cambie")
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var titulo: String? {
        switch v?.resultado {
        case "sin_cambios": T.sinCambios
        case "adaptada", "plan_nuevo": Gimnasio.fechaCorta(v?.publicadoEn).map(T.adaptadoPorMati)
        default: nil
        }
    }

    private func empezar(_ modo: String) {
        Task {
            switch await modelo.empezar(modo: modo) {
            case .ok: error = nil
            case .sinSenal: error = T.sinSenal
            default: error = T.errorGenerico
            }
        }
    }
}

private struct YaNoEstaGimnasio: View {
    let modelo: ModeloGimnasio
    @State private var marcados: Set<String> = []
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(modelo.vigente?.equipos ?? [], id: \.tipo) { e in
                    Button { if marcados.remove(e.tipo) == nil { marcados.insert(e.tipo) } } label: {
                        Label { Text(e.nombre).foregroundStyle(.primary) } icon: {
                            Image(systemName: marcados.contains(e.tipo) ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.marcaTexto)
                        }
                    }
                    .accessibilityAddTraits(marcados.contains(e.tipo) ? .isSelected : [])
                }
            } header: { Text(T.marcarLoQueNoEsta).textCase(nil) }
            Section {
                if let error { NotaGimnasio(texto: error, alerta: true) }
                Button(T.botonEnviar) { enviar() }.disabled(marcados.isEmpty).accessibilityIdentifier("gimnasio-enviar-quitar")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.fondo)
        .navigationTitle(T.yaNoEsta)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func enviar() {
        Task {
            let r = await modelo.empezar(modo: "parcial")
            guard r == .ok, modelo.abierta?.modo == "parcial" else { error = r == .sinSenal ? T.sinSenal : T.errorGenerico; return }
            for t in marcados where !modelo.quitar.contains(t) { modelo.alternarQuitar(t) }
            await modelo.enviarCarga()
        }
    }
}

/// Una pregunta por pantalla: con 18 juntas no se contesta ninguna.
private struct PreguntasGimnasio: View {
    let modelo: ModeloGimnasio
    @State private var indice = 0

    private var preguntas: [PreguntaGimnasio] { modelo.abierta?.preguntas ?? [] }

    var body: some View {
        let ps = preguntas
        let i = min(indice, max(ps.count - 1, 0))
        VStack(alignment: .leading, spacing: Espacio.m) {
            if ps.isEmpty {
                RecibidoGimnasio()
            } else {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Text(T.preguntaDe(i + 1, ps.count)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                        .accessibilityIdentifier("gimnasio-numero-pregunta")
                    ProgressView(value: Double(i + 1), total: Double(ps.count)).tint(Color.marcaTexto).accessibilityHidden(true)
                    let n = Gimnasio.fotosPedidas(ps, modelo.respuestas)
                    if n > 0 { Text(T.necesitamosFotos(n)).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("gimnasio-necesitamos") }
                    if let a = modelo.avisoFoto { NotaGimnasio(texto: a == .tope ? T.tope : T.fotoRechazada, alerta: true) }
                    if modelo.avisoEnvio != nil { NotaGimnasio(texto: T.errorGenerico, alerta: true) }
                }
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.s)

                ScrollView {
                    PreguntaGimnasioVista(modelo: modelo, pregunta: ps[i]).id(ps[i].id).padding(Espacio.m)
                }
                .scrollDismissesKeyboard(.interactively)

                HStack(spacing: Espacio.s) {
                    if i > 0 {
                        Button(T.anterior) { indice = i - 1 }.buttonStyle(BotonSecundario()).accessibilityIdentifier("gimnasio-anterior")
                    }
                    if i < ps.count - 1 {
                        Button(T.siguiente) { indice = i + 1 }.buttonStyle(BotonMarca()).accessibilityIdentifier("gimnasio-siguiente")
                    } else {
                        Button(T.botonEnviar) { Task { await modelo.enviarRespuestas() } }.buttonStyle(BotonMarca()).accessibilityIdentifier("gimnasio-enviar-respuestas")
                    }
                }
                .padding(Espacio.m)
            }
        }
        .anchoLectura()
    }
}

private struct PreguntaGimnasioVista: View {
    let modelo: ModeloGimnasio
    let pregunta: PreguntaGimnasio
    @State private var kilos = ""
    @FocusState private var enKilos: Bool

    private var valor: JSONValue? { modelo.respuestas[pregunta.id] }
    private var noSe: Bool { valor == .texto("no_se") }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            Text(pregunta.texto).font(.title3.bold()).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            fotosDeReferencia(pregunta.fotos)
            switch pregunta.clase {
            case .elegir: elegir
            case .numero: numero
            case .confirmar: confirmar
            case .foto: foto
            case .desconocida: EmptyView()
            }
            if pregunta.clase != .foto && pregunta.clase != .confirmar {
                opcionFila(T.noSe, marcada: noSe, id: "gimnasio-no-se") { modelo.responder(pregunta.id, noSe ? nil : .texto("no_se")) }
            }
        }
        .task { await firmarReferencias() }
        .onAppear { if case .numero(let n)? = valor { kilos = n == n.rounded() ? String(Int(n)) : String(n).replacingOccurrences(of: ".", with: ",") } }
    }

    private func firmarReferencias() async {
        let ids = pregunta.fotos + pregunta.items.flatMap(\.fotos)
        guard let a = modelo.abierta, !ids.isEmpty else { return }
        await modelo.firmar(gimnasioId: a.id, ids: ids)
    }

    @ViewBuilder private func fotosDeReferencia(_ ids: [String]) -> some View {
        if !ids.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Espacio.xs) {
                    ForEach(ids, id: \.self) { id in
                        Color.campo.frame(width: 110, height: 110).overlay {
                            if let u = modelo.urls[id] {
                                AsyncImage(url: u) { f in if let i = f.image { i.resizable().scaledToFill() } else { Image(systemName: "photo").foregroundStyle(.tertiary) } }
                            }
                        }
                        .clipShape(.rect(cornerRadius: Radio.control, style: .continuous))
                        .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func opcionFila(_ texto: String, marcada: Bool, id: String? = nil, _ accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: Espacio.s) {
                Image(systemName: marcada ? "checkmark.circle.fill" : "circle").foregroundStyle(marcada ? Color.marcaTexto : Color.secondary).accessibilityHidden(true)
                Text(texto).foregroundStyle(.primary).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(Espacio.s)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcada ? .isSelected : [])
        .modifier(IdOpcional(id: id))
    }

    @ViewBuilder private var elegir: some View {
        if pregunta.multiple {
            NotaGimnasio(texto: T.marcarTodas)
            ForEach(pregunta.opciones) { o in
                let actuales = seleccion
                opcionFila(o.texto, marcada: actuales.contains(o.valor), id: "gimnasio-opcion-\(o.valor)") {
                    var s = seleccion
                    if s.contains(o.valor) { s.remove(o.valor) } else { s.insert(o.valor) }
                    modelo.responder(pregunta.id, .lista(pregunta.opciones.map(\.valor).filter(s.contains).map(JSONValue.texto)))
                }
            }
        } else {
            ForEach(pregunta.opciones) { o in
                let marcada = valor == .texto(o.valor)
                opcionFila(o.texto, marcada: marcada, id: "gimnasio-opcion-\(o.valor)") { modelo.responder(pregunta.id, marcada ? nil : .texto(o.valor)) }
            }
        }
    }

    private var seleccion: Set<String> {
        if case .lista(let l)? = valor { return Set(l.compactMap(\.comoTexto)) }
        return []
    }

    @ViewBuilder private var numero: some View {
        HStack {
            TextField(T.elegirKilos, text: $kilos)
                .keyboardType(.decimalPad)
                .focused($enKilos)
                .padding(Espacio.s)
                .frame(minHeight: 44)
                .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                .accessibilityIdentifier("gimnasio-kilos")
            Text(pregunta.unidad ?? T.kg).foregroundStyle(.secondary)
        }
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button(T.listoTeclado) { enKilos = false } } }
        .onChange(of: kilos) { _, s in
            if let n = Gimnasio.kilos(s) { modelo.responder(pregunta.id, .numero(n)) } else if !noSe { modelo.responder(pregunta.id, nil) }
        }
        if !kilos.isEmpty && Gimnasio.kilos(kilos) == nil { NotaGimnasio(texto: T.kilosInvalidos, alerta: true) }
    }

    @ViewBuilder private var confirmar: some View {
        ForEach(pregunta.items) { item in
            VStack(alignment: .leading, spacing: Espacio.xs) {
                Text(item.texto).font(.headline)
                fotosDeReferencia(item.fotos)
                HStack(spacing: Espacio.xs) {
                    botonConfirmar(item, "si", T.si)
                    botonConfirmar(item, "no", T.no)
                    botonConfirmar(item, "no_se", T.noSe)
                }
            }
            .tarjeta(relleno: 12)
        }
    }

    private func botonConfirmar(_ item: ItemGimnasio, _ v: String, _ texto: String) -> some View {
        var mapa: [String: JSONValue] = { if case .objeto(let o)? = valor { o } else { [:] } }()
        let marcada = mapa[item.tipo] == .texto(v)
        return Button {
            if case .objeto(let o)? = valor { mapa = o } else { mapa = [:] }
            mapa[item.tipo] = mapa[item.tipo] == .texto(v) ? nil : .texto(v)
            modelo.responder(pregunta.id, mapa.isEmpty ? nil : .objeto(mapa))
        } label: {
            Text(texto).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(marcada ? Color.sobreMarca : .primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(marcada ? Color.marca : Color.campo, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.texto): \(texto)")
        .accessibilityAddTraits(marcada ? .isSelected : [])
        .accessibilityIdentifier("gimnasio-\(item.tipo)-\(v)")
    }

    @ViewBuilder private var foto: some View {
        NotaGimnasio(texto: T.consejoCamara)
        let enCola = modelo.cola.first { $0.pregunta == pregunta.id }
        if valor == .texto("subida") {
            NotaGimnasio(texto: enCola == nil ? T.cuentaFotos(1) : modelo.subiendo == enCola?.id ? T.subiendo : T.esperandoSenal)
        }
        AgregarFotoGimnasio(puede: true) { jpeg in
            if modelo.agregar(zona: pregunta.zona ?? Gimnasio.zonaOpcional, jpeg: jpeg, pregunta: pregunta.id) == .guardada { modelo.drenarEnFondo() }
        } contenido: {
            Label(T.agregarFoto, systemImage: "camera.fill").frame(maxWidth: .infinity, minHeight: 54)
                .font(.headline).foregroundStyle(Color.sobreMarca).background(Color.marca, in: .capsule)
        }
        .accessibilityIdentifier("gimnasio-agregar-foto")
        let noPuedo = valor == .texto("no_puedo")
        opcionFila(T.noPuedoFoto, marcada: noPuedo, id: "gimnasio-no-puedo") { modelo.responder(pregunta.id, noPuedo ? nil : .texto("no_puedo")) }
    }
}

private struct IdOpcional: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id { content.accessibilityIdentifier(id) } else { content }
    }
}
