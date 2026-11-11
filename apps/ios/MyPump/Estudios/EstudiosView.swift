import SwiftUI
import UIKit
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosEstudios

extension Color {
    /// Una fecha que ya pasó: ámbar, nunca rojo ni tono de alarma.
    static let ambarEstudios = Color(claro: UIColor(hex: 0xB45309), oscuro: UIColor(hex: 0xFFB020))
}

/// La fila de Mis datos: «Estudios y órdenes» y, abajo, cuántos faltan.
struct FilaEstudiosMisDatos: View {
    let modelo: ModeloEstudios

    var body: some View {
        NavigationLink { EstudiosView(modelo: modelo) } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(T.entradaMisDatos).foregroundStyle(.primary)
                    Text(T.subtituloEntrada(modelo.pendientes)).font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: { IconoAzulejo("doc.text.fill", color: .marcaTexto) }
        }
        .accessibilityIdentifier("mis-datos-estudios")
    }
}

/// «Estudios»: lo que falta hacer, las órdenes y lo que llegó. Documentos, fechas y estados: sin valores ni interpretación.
struct EstudiosView: View {
    let modelo: ModeloEstudios
    @State private var subida: Subida?
    @State private var fecha: PendienteEstudio?
    @State private var abridor = AbridorEstudios()
    @State private var ocupado: String?
    @State private var errorPendiente: String?

    struct Subida: Identifiable {
        let pedidoId: String?
        var id: String { pedidoId ?? "suelto" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                if modelo.errorDeCarga {
                    NotaEstudios(texto: T.errorDeCarga, icono: "arrow.clockwise", tono: .secondary).accessibilityIdentifier("estudios-error-carga")
                }
                if let e = modelo.estado { contenido(e) }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(T.titulo)
        .navigationBarTitleDisplayMode(.large)
        // Respetan la palanca: apagada, ni el `get` ni la cola llaman a nada.
        .refreshable { await modelo.sincronizar() }
        .task { await modelo.sincronizar() }
        .onDisappear { modelo.limpiarAviso(); abridor.cancelar(modelo) }
        // Al cerrarse la hoja, como sea, lo elegido y no enviado se borra (tras «Enviar» ya no queda nada).
        .sheet(item: $subida, onDismiss: { modelo.descartarBorrador() }) { s in
            HojaSubidaEstudios(modelo: modelo, pedidoId: s.pedidoId) { subida = nil }
        }
        .sheet(item: $fecha) { p in
            HojaFechaEstudio(modelo: modelo, pendiente: p) { fecha = nil }
        }
        .visorDeEstudios(abridor, modelo: modelo)
    }

    @ViewBuilder
    private func contenido(_ e: EstadoEstudios) -> some View {
        let b = Estudios.bloques(e)
        if let c = e.proximoControl { ProximoControlEstudios(control: c) }
        if b.pendientes {
            VStack(alignment: .leading, spacing: Espacio.s) {
                EncabezadoSeccion(titulo: T.teFaltaHacer)
                ForEach(e.pendientes) { p in
                    TarjetaPendiente(pendiente: p, hoy: e.hoy, ocupado: ocupado == p.id, bloqueada: abridor.abriendo != nil, abriendo: abridor.abriendo == p.ordenId && p.ordenId != nil,
                                     error: errorDe(p),
                                     subir: { subida = Subida(pedidoId: p.id) },
                                     hecho: { errorPendiente = nil; fecha = p },
                                     deshacer: { Task { await deshacer(p) } },
                                     verOrden: { if let o = p.ordenId { errorPendiente = nil; abridor.abrir(clase: "orden", id: o, titulo: p.titulo, modelo: modelo) } })
                }
            }
        }
        if b.vacio {
            VStack(spacing: Espacio.s) {
                Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
                Text(T.vacio).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Espacio.l)
            .accessibilityIdentifier("estudios-vacio")
        }
        VStack(alignment: .leading, spacing: Espacio.s) {
            Button { modelo.limpiarAviso(); subida = Subida(pedidoId: nil) } label: {
                Label(T.subirEstudio, systemImage: "arrow.up.doc.fill").multilineTextAlignment(.center).padding(.vertical, 6)
            }
            .buttonStyle(BotonMarca())
            .disabled(abridor.abriendo != nil)
            .accessibilityIdentifier("estudios-subir")
            EstadoSubidaEstudios(modelo: modelo)
        }
        if b.ordenes {
            VStack(alignment: .leading, spacing: Espacio.s) {
                EncabezadoSeccion(titulo: T.tusOrdenes)
                VStack(spacing: 0) {
                    ForEach(Array(e.ordenes.enumerated()), id: \.element.id) { i, o in
                        if i > 0 { Divider().padding(.leading, Espacio.m) }
                        FilaOrden(orden: o, modelo: modelo)
                    }
                }
                .superficieTarjeta()
                .clipShape(.rect(cornerRadius: Radio.tarjeta, style: .continuous))
            }
        }
        if b.estudios {
            VStack(alignment: .leading, spacing: Espacio.s) {
                EncabezadoSeccion(titulo: T.tusEstudios)
                VStack(spacing: 0) {
                    let envios = e.enviosVisibles
                    ForEach(Array(envios.enumerated()), id: \.element.id) { i, envio in
                        if i > 0 { Divider().padding(.leading, Espacio.m) }
                        FilaEnvio(envio: envio)
                    }
                    ForEach(Array(e.estudios.enumerated()), id: \.element.id) { i, estudio in
                        if i > 0 || !envios.isEmpty { Divider().padding(.leading, Espacio.m) }
                        FilaEstudio(estudio: estudio, abriendo: abridor.abriendo == estudio.id, error: abridor.errorEn == estudio.id,
                                    todaviaNo: abridor.todaviaNoEn == estudio.id) {
                            abridor.abrir(clase: "estudio", id: estudio.id, titulo: estudio.titulo, modelo: modelo)
                        }
                    }
                }
                .superficieTarjeta()
                Text(T.notaRecibido)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("estudios-nota")
            }
        }
    }

    private func errorDe(_ p: PendienteEstudio) -> String? {
        if errorPendiente == p.id { return T.noSePudoGuardar }
        if let o = p.ordenId, abridor.errorEn == o { return T.noSePudoAbrir }
        return nil
    }

    private func deshacer(_ p: PendienteEstudio) async {
        ocupado = p.id
        errorPendiente = nil
        let r = await modelo.marcarHecho(pedidoId: p.id, fecha: nil)
        ocupado = nil
        if r != .ok { errorPendiente = p.id }
    }
}

// MARK: - Piezas

/// Nota con ícono y texto: el estado nunca va solo en el color.
struct NotaEstudios: View {
    let texto: String
    var icono: String?
    var tono: Color = .secondary
    var anunciar = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
            if let icono { Image(systemName: icono).foregroundStyle(tono).accessibilityHidden(true) }
            Text(texto).foregroundStyle(tono == .secondary ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onAppear { if anunciar { AccessibilityNotification.Announcement(texto).post() } }
    }
}

private struct ProximoControlEstudios: View {
    let control: ProximoControl
    @ScaledMetric(relativeTo: .body) private var lado: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        HStack(alignment: .center, spacing: Espacio.s) {
            // Con letra de accesibilidad el adorno le saca ancho al texto: se va.
            if !letra.isAccessibilitySize {
                Image(systemName: "calendar")
                    .font(.system(size: lado * 0.45, weight: .semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .frame(width: lado, height: lado)
                    .background(Color.marcaSuave, in: .circle)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(T.proximoControl).textoCeja()
                Text(control.titulo).font(.headline)
                if let cuando = Estudios.fechaControl(desde: control.desde, hasta: control.hasta) {
                    Text(cuando).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tarjeta()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("estudios-proximo-control")
    }
}

private struct TarjetaPendiente: View {
    let pendiente: PendienteEstudio
    let hoy: Estudios.Dia?
    let ocupado: Bool
    /// Se está bajando algo para ver: hasta que abra no se presenta otra hoja encima.
    let bloqueada: Bool
    let abriendo: Bool
    let error: String?
    let subir: () -> Void
    let hecho: () -> Void
    let deshacer: () -> Void
    let verOrden: () -> Void
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pendiente.titulo).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                if let d = pendiente.detalle { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                if pendiente.hecho {
                    Label(Estudios.hecho(pendiente.hechoFecha), systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("estudios-hecho-\(pendiente.id)")
                } else if let f = Estudios.fechaPendiente(desde: pendiente.desde, hasta: pendiente.hasta, hoy: hoy) {
                    Label(f.texto, systemImage: f.pasada ? "clock" : "calendar")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(f.pasada ? Color.ambarEstudios : Color.secondary)
                        .accessibilityIdentifier("estudios-fecha-\(pendiente.id)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Button(action: subir) {
                Label(T.subirResultado, systemImage: "arrow.up.doc").multilineTextAlignment(.center).padding(.vertical, 4)
            }
            .buttonStyle(BotonMarca())
            .disabled(bloqueada)
            .accessibilityLabel("\(T.subirResultado), \(pendiente.titulo)")
            .accessibilityIdentifier("estudios-subir-\(pendiente.id)")

            let fila = letra.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Espacio.xs)) : AnyLayout(HStackLayout(spacing: Espacio.xs))
            fila {
                if pendiente.hecho {
                    Button(action: deshacer) { rotulo(T.deshacer, trabajando: ocupado) }
                        .buttonStyle(BotonSecundario())
                        .disabled(ocupado)
                        .accessibilityLabel("\(T.deshacer), \(pendiente.titulo)")
                        .accessibilityIdentifier("estudios-deshacer-\(pendiente.id)")
                } else {
                    Button(action: hecho) { rotulo(T.yaMeLoHice, trabajando: false) }
                        .buttonStyle(BotonSecundario())
                        .disabled(bloqueada)
                        .accessibilityLabel("\(T.yaMeLoHice), \(pendiente.titulo)")
                        .accessibilityIdentifier("estudios-hecho-boton-\(pendiente.id)")
                }
                if pendiente.ordenId != nil {
                    Button(action: verOrden) { rotulo(T.verOrden, trabajando: abriendo) }
                        .buttonStyle(BotonSecundario(tono: .marcaTexto))
                        .disabled(bloqueada)
                        .accessibilityLabel("\(T.verOrden), \(pendiente.titulo)")
                        .accessibilityIdentifier("estudios-ver-orden-\(pendiente.id)")
                }
            }
            if let error { NotaEstudios(texto: error, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true) }
        }
        .tarjeta()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("estudios-pendiente-\(pendiente.id)")
    }

    private func rotulo(_ texto: String, trabajando: Bool) -> some View {
        HStack(spacing: Espacio.xs) {
            if trabajando { ProgressView() }
            Text(texto).multilineTextAlignment(.center)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.vertical, 4)
    }
}

/// Lo que está saliendo o lo último que pasó con un envío.
private struct EstadoSubidaEstudios: View {
    let modelo: ModeloEstudios

    var body: some View {
        if let p = modelo.progreso {
            VStack(alignment: .leading, spacing: Espacio.s) {
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    HStack(spacing: Espacio.s) {
                        if modelo.sinSenal {
                            Image(systemName: "wifi.slash").foregroundStyle(.secondary).accessibilityHidden(true)
                        } else if modelo.detenida {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(Color.ambarEstudios).accessibilityHidden(true)
                        } else if modelo.subiendo {
                            ProgressView()
                        } else {
                            Image(systemName: "clock").foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                        // Detenida por algo que no es la red (el link, el servidor): no está «subiendo», se dice qué pasó.
                        Text(modelo.detenida ? T.noSePudoEnviar : p).font(.subheadline.weight(.semibold)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if modelo.sinSenal {
                        Text(T.sinSenal).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("estudios-sin-senal")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(modelo.detenida ? "estudios-detenida" : "estudios-subiendo")
                .onChange(of: modelo.detenida) { _, d in if d { AccessibilityNotification.Announcement(T.noSePudoEnviar).post() } }
                if modelo.detenida {
                    Button { Task { await modelo.reintentar() } } label: { Text(T.probarDeNuevo).multilineTextAlignment(.center) }
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                        .accessibilityIdentifier("estudios-reintentar")
                }
            }
            .tarjeta()
        } else if let a = modelo.aviso {
            VStack(alignment: .leading, spacing: Espacio.xs) {
                switch a {
                case .recibido:
                    NotaEstudios(texto: T.envioRecibido, icono: "checkmark.circle.fill", tono: .marcaTexto, anunciar: true)
                case .recibidoConRechazo:
                    NotaEstudios(texto: T.envioRecibido, icono: "checkmark.circle.fill", tono: .marcaTexto, anunciar: true)
                    NotaEstudios(texto: T.archivoRechazado, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true)
                case .rechazado:
                    NotaEstudios(texto: T.archivoRechazado, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true)
                case .topeDia:
                    NotaEstudios(texto: T.topeDia, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true)
                case .error:
                    NotaEstudios(texto: T.noSePudoEnviar, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true)
                }
            }
            .tarjeta()
            .accessibilityIdentifier("estudios-aviso")
        }
    }
}

/// «Recibido» neutro, «Mati lo vio» verde con tilde: ícono y texto, no solo color.
private struct EtiquetaEstadoEstudio: View {
    let visto: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: visto ? "checkmark.circle.fill" : "tray.and.arrow.down.fill").imageScale(.small).accessibilityHidden(true)
            Text(visto ? T.matiLoVio : T.recibido)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(visto ? Color.marcaTexto : Color.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(visto ? Color.marcaSuave : Color.campo, in: .capsule)
    }
}

private struct FilaOrden: View {
    let orden: OrdenEstudio
    let modelo: ModeloEstudios

    var body: some View {
        if orden.vigente {
            NavigationLink { DetalleOrdenView(orden: orden, modelo: modelo) } label: {
                HStack(spacing: Espacio.s) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(orden.titulo).font(.headline).foregroundStyle(.primary)
                        let d = Estudios.detalleOrden(orden)
                        if !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Espacio.xs)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                .padding(Espacio.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(FilaPresionable())
            .accessibilityIdentifier("estudios-orden-\(orden.id)")
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(orden.titulo).font(.headline).foregroundStyle(.secondary)
                Text(T.ordenVencida).font(.subheadline).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("estudios-orden-vencida-\(orden.id)")
        }
    }
}

private struct FilaEnvio: View {
    let envio: EnvioRecibido

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Estudios.tituloEnvio(envio)).font(.headline)
            if let a = Estudios.archivos(envio.archivos) { Text(a).font(.subheadline).foregroundStyle(.secondary) }
            EtiquetaEstadoEstudio(visto: false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Estudios.lineaEnvio(envio))
        .accessibilityIdentifier("estudios-envio-\(envio.id)")
    }
}

private struct FilaEstudio: View {
    let estudio: EstudioRecibido
    let abriendo: Bool
    let error: Bool
    /// Llegó pero todavía no se puede abrir: se dice lo mismo que la web, sin tono de error.
    let todaviaNo: Bool
    let ver: () -> Void
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        let fila = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s)) : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
        VStack(alignment: .leading, spacing: Espacio.xs) {
            fila {
                VStack(alignment: .leading, spacing: 6) {
                    Text(estudio.titulo).font(.headline)
                    Text(Estudios.detalleEstudio(estudio)).font(.subheadline).foregroundStyle(.secondary)
                    EtiquetaEstadoEstudio(visto: estudio.visto)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if estudio.sePuedeAbrir {
                    Button(action: ver) {
                        HStack(spacing: 6) {
                            if abriendo { ProgressView() }
                            Text(T.ver)
                        }
                    }
                    .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    .disabled(abriendo)
                    .accessibilityLabel("\(T.ver), \(estudio.titulo)")
                    .accessibilityIdentifier("estudios-ver-\(estudio.id)")
                }
            }
            if error { NotaEstudios(texto: T.noSePudoAbrir, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true) }
            if todaviaNo {
                NotaEstudios(texto: T.envioRecibido, icono: "checkmark.circle", tono: .secondary, anunciar: true)
                    .accessibilityIdentifier("estudios-todavia-no-\(estudio.id)")
            }
        }
        .padding(Espacio.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("estudios-estudio-\(estudio.id)")
    }
}

// MARK: - Detalle de una orden

struct DetalleOrdenView: View {
    let orden: OrdenEstudio
    let modelo: ModeloEstudios
    @State private var abridor = AbridorEstudios()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                VStack(alignment: .leading, spacing: Espacio.s) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(orden.titulo).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                        let d = Estudios.detalleOrden(orden)
                        if !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Button { abridor.abrir(clase: "orden", id: orden.id, titulo: orden.titulo, modelo: modelo) } label: {
                        Label(T.verOrden, systemImage: "doc.text.fill").multilineTextAlignment(.center).padding(.vertical, 6)
                    }
                    .buttonStyle(BotonMarca(ocupado: abridor.abriendo != nil))
                    .disabled(abridor.abriendo != nil)
                    .overlay(alignment: .trailing) { if abridor.abriendo != nil { ProgressView().tint(Color.sobreMarca).padding(.trailing, Espacio.m) } }
                    .accessibilityIdentifier("estudios-ver-orden")
                    if abridor.errorEn != nil {
                        NotaEstudios(texto: T.noSePudoAbrir, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true)
                            .accessibilityIdentifier("estudios-error-abrir")
                    }
                }
                .tarjeta()
                seccion(T.comoPrepararte, "checklist", Estudios.preparacion(tipo: orden.tipo)).accessibilityIdentifier("estudios-preparacion")
                seccion(T.dondeHacerlo, "mappin.and.ellipse", Estudios.donde(tipo: orden.tipo)).accessibilityIdentifier("estudios-donde")
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .background(Color.fondo)
        .navigationTitle(T.tusOrdenes)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { abridor.cancelar(modelo) }
        .visorDeEstudios(abridor, modelo: modelo)
    }

    private func seccion(_ titulo: String, _ icono: String, _ renglones: [String]) -> some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: titulo)
            VStack(alignment: .leading, spacing: Espacio.s) {
                ForEach(Array(renglones.enumerated()), id: \.offset) { _, r in
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.s) {
                        Circle().fill(Color.marcaVivo).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }.accessibilityHidden(true)
                        Text(r).font(.body).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tarjeta()
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Fecha de «Ya me lo hice»

private struct HojaFechaEstudio: View {
    let modelo: ModeloEstudios
    let pendiente: PendienteEstudio
    let alCerrar: () -> Void
    @State private var fecha = Date()
    @State private var guardando = false
    @State private var error: String?

    /// Lo que acepta el servidor: hasta 120 días atrás; hacia adelante, hoy.
    private var rango: ClosedRange<Date> {
        let hoy = Date()
        return (Calendar.current.date(byAdding: .day, value: -120, to: hoy) ?? hoy)...hoy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.m) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T.cuandoTeLoHiciste).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                        Text(pendiente.titulo).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    DatePicker(T.cuandoTeLoHiciste, selection: $fecha, in: rango, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Color.marca)
                        .accessibilityIdentifier("estudios-fecha-picker")
                    if let error {
                        NotaEstudios(texto: error, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true).accessibilityIdentifier("estudios-fecha-error")
                    }
                    Button { Task { await guardar() } } label: {
                        HStack(spacing: Espacio.xs) { if guardando { ProgressView().tint(Color.sobreMarca) }; Text(T.guardar) }
                    }
                    .buttonStyle(BotonMarca(ocupado: guardando))
                    .disabled(guardando)
                    .accessibilityIdentifier("estudios-fecha-guardar")
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .background(Color.fondo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cancelar, action: alCerrar) } }
        }
        .tint(Color.marcaTexto)
        .presentationDragIndicator(.visible)
    }

    private func guardar() async {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        guard let dia = Estudios.Dia(String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)) else { error = T.revisaLaFecha; return }
        guardando = true
        error = nil
        let r = await modelo.marcarHecho(pedidoId: pendiente.id, fecha: dia)
        guardando = false
        switch r {
        case .ok: alCerrar()
        case .fecha: error = T.revisaLaFecha
        case .sinSenal, .error: error = T.noSePudoGuardar
        }
    }
}
