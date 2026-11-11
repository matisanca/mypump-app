import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// Salud (2.1, S1), que reemplaza a Progreso, con tres segmentos. Desde la 2.1.0 no es una pestaña: se abre en una hoja
/// desde la tarjeta Recuperación de Revisión, un aviso o un link.
/// - Recuperación: la card de recuperación (score, motivos, confianza, tendencia de 14 días), la de salud (sueño,
///   corazón, actividad) y Mi reloj. Salieron de Revisión.
/// - Fuerza: las series por músculo de la semana (S2) y lo que era Progreso (récords y curvas).
/// - Cuerpo: el peso con su media (la tarjeta que estaba en Revisión), las fotos por semana y el check de la semana, de
///   solo lectura (se suben en Revisión).
/// Arranca en Recuperación y recuerda el segmento mientras viva la app. Un aviso o un botón que pide un segmento lo deja
/// en `Navegacion.segmentoSalud`, y acá se consume.
struct SaludView: View {
    let datos: Muestras
    /// La hoja de Salud (`Navegacion.saludAbierta`): «Listo» la cierra. nil = sin botón (bocetos).
    var alCerrar: (() -> Void)?
    @State private var modelo = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @Environment(\.horizontalSizeClass) private var claseAncho
    @State private var segmento: SegmentoSalud = DemoUI.segmento.flatMap(SegmentoSalud.init(rawValue:)) ?? .recuperacion
    @State private var ruta: [LineaProgreso] = []

    private var salud: ModeloSalud? { modelo.conMuestras ? nil : modelo.salud }
    private var revision: ModeloRevision? { modelo.conMuestras ? nil : modelo.revision }
    private var modeloFotos: ModeloFotos? { modelo.conMuestras ? nil : modelo.fotos }

    var body: some View {
        NavigationStack(path: $ruta) {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.l) {
                    // Como la web, arriba de todas las escenas menos Revisión (GEN-03).
                    BannerRevision()
                    Picker("Sección de Salud", selection: $segmento) {
                        ForEach(SegmentoSalud.allCases) { Text($0.titulo).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("segmento-salud")
                    switch segmento {
                    case .recuperacion: recuperacion
                    case .fuerza: FuerzaSeccion(datos: datos, ruta: $ruta)
                    case .cuerpo: CuerpoSeccion(datos: datos, revision: revision, modeloFotos: modeloFotos)
                    }
                }
                .padding(.horizontal, Espacio.m)
                .padding(.top, Espacio.xs)
                .padding(.bottom, Espacio.xl)
                .anchoLectura(claseAncho == .regular && segmento == .fuerza ? Ancho.doble : Ancho.lectura)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refrescar() }
            .background(Color.fondo)
            .navigationTitle("Salud")
            .navigationDestination(for: LineaProgreso.self) { ProgresoDetalleView(linea: $0) }
            .toolbar {
                if let alCerrar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo", action: alCerrar).accessibilityIdentifier("salud-cerrar")
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: segmento)
        }
        .onChange(of: navegacion?.segmentoSalud, initial: true) { _, pedido in
            guard let pedido else { return }
            segmento = pedido
            navegacion?.segmentoSalud = nil
        }
    }

    @ViewBuilder private var recuperacion: some View {
        if let salud {
            VStack(alignment: .leading, spacing: Espacio.l) {
                PumpDelDiaSiCorresponde(enSalud: true)
                CardRecuperacionView(modelo: salud)
                CardSaludView(modelo: salud)
                // Oura y WHOOP según lo que ofrezca el servidor (sin relojes para ofrecer, no ocupa lugar).
                MiRelojView(modelo: salud)
            }
        } else if MetasUI.shared.muestra {
            PumpDelDiaSiCorresponde(enSalud: true)
        } else {
            ContentUnavailableView {
                Label("Sin datos de salud en la demo", systemImage: "heart.text.square")
            } description: {
                Text("La recuperación sale de tu reloj o del teléfono. Con tu cuenta la vas a ver acá.")
            }
        }
    }

    /// Tirar para actualizar: lo del segmento que se ve (sin cuenta no hay nada que traer).
    private func refrescar() async {
        guard !modelo.conMuestras else { return }
        switch segmento {
        case .recuperacion: await salud?.cargar()
        case .fuerza: await modelo.cargarProgreso()
        case .cuerpo:
            async let r: Void = revision?.cargarRevision() ?? ()
            async let f: Void = modeloFotos?.cargar() ?? ()
            _ = await (r, f)
        }
    }
}

// MARK: - Fuerza: series por músculo (S2)

/// «Series por músculo · esta semana»: una fila por músculo con el número de esta semana grande, la pasada chica y una
/// barra fina (la semana pasada, tenue, detrás). Liviana como la preparación de E1: sin cajas dentro de la tarjeta.
struct VolumenMusculoTarjeta: View {
    let resumen: VolumenMusculo.Resumen
    /// Lo que se dice sin filas: sin series, trayendo el historial o sin red.
    var vacio: String = Self.sinSeries

    static let sinSeries = VolumenMusculo.vacioSinSeries

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Series por músculo", detalle: "esta semana")
            VStack(alignment: .leading, spacing: 12) {
                if resumen.filas.isEmpty {
                    Text(vacio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(resumen.filas) { FilaVolumen(fila: $0, tope: resumen.tope) }
                }
                Text("Series efectivas registradas, de lunes a domingo. La preparación no cuenta.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tarjeta()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volumen-musculo")
    }
}

private struct FilaVolumen: View {
    let fila: VolumenMusculo.Fila
    let tope: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fila.nombre)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(fila.musculo == nil ? .secondary : .primary)
                Spacer(minLength: Espacio.xs)
                Text("\(fila.semana)").font(.numeroChico).monospacedDigit()
                Text("\(fila.anterior) la pasada")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            GeometryReader { g in
                let escala = tope > 0 ? g.size.width / CGFloat(tope) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.campo)
                    Capsule().fill(Color.marcaSuave).frame(width: CGFloat(fila.anterior) * escala)
                    Capsule().fill(Color.marca).frame(width: CGFloat(fila.semana) * escala)
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fila.textoAccesible)
        .accessibilityIdentifier("volumen-\(fila.musculo ?? "sin")")
    }
}

/// La semana de muestra de los bocetos (sin datos de nadie): esta semana y la pasada.
enum VolumenMuestra {
    static var resumen: VolumenMusculo.Resumen {
        let hoy = FechaLocal.hoy()
        let pasada = DiaCalendario.numero(hoy).map { DiaCalendario.texto($0 - 7) } ?? hoy
        let cuentas: [(String?, Int, Int)] = [("chest", 10, 8), ("quadriceps", 9, 12), ("lats", 8, 8), ("shoulders", 6, 4),
                                              ("biceps", 4, 6), (nil, 2, 0)]
        var r: [VolumenMusculo.Registro] = []
        for (m, ahora, antes) in cuentas {
            r += (0..<ahora).map { _ in .init(musculo: m, tipo: "compuesto", fecha: hoy, lugar: m ?? "x", serie: nil) }
            r += (0..<antes).map { _ in .init(musculo: m, tipo: "compuesto", fecha: pasada, lugar: m ?? "x", serie: nil) }
        }
        return VolumenMusculo.calcular(historial: r, hoy: hoy)
    }
}

// MARK: - Cuerpo

/// El peso con su media (con la carga del día), las fotos por semana y el check de la semana de solo lectura.
private struct CuerpoSeccion: View {
    let datos: Muestras
    let revision: ModeloRevision?
    let modeloFotos: ModeloFotos?
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @State private var galeria = false

    private var muestras: Muestras { datos.paraPantalla() }
    private var fotos: [FotoProgreso] { modeloFotos?.fotos ?? muestras.fotos }
    private var peso: [PesoCorporal.Punto] { revision?.serieDePeso ?? PesoCorporal.serie(muestras.salud) }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xl) {
            PesoTarjeta(revision: revision, saludMuestra: muestras.salud)
            fotosPorSemana
            checkDeLaSemana
        }
        .task(id: fotos.count) { if let modeloFotos, !modeloFotos.fotos.isEmpty { await modeloFotos.firmar() } }
        .sheet(isPresented: $galeria) { GaleriaFotos(modelo: modeloFotos, fotos: fotos, peso: peso) }
    }

    private var fotosPorSemana: some View {
        let semanas = FotosProgreso.semanas(fotos)
        let racha = FotosProgreso.racha(fotos)
        return VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Fotos por semana", detalle: semanas.isEmpty ? nil : "\(semanas.count) semana\(semanas.count == 1 ? "" : "s")")
            VStack(alignment: .leading, spacing: Espacio.s) {
                if semanas.isEmpty {
                    Text("Las fotos se suben desde Revisión.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    irARevision("fotos")
                } else {
                    if racha >= 2 {
                        Label("\(racha) semanas seguidas registradas", systemImage: "flame.fill")
                            .labelStyle(IconoTeñido(color: .alerta))
                            .font(.subheadline.weight(.semibold))
                    }
                    Button("Ver mis fotos · \(semanas.count) semana\(semanas.count == 1 ? "" : "s")") { galeria = true }
                        .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
                    if semanas.count < 4 {
                        Text("El comparador antes/después se abre en \(4 - semanas.count) semana\(4 - semanas.count > 1 ? "s" : "") más.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tarjeta()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cuerpo-fotos")
    }

    /// Lo enviado de esta semana: con cuenta, el del modelo; en los bocetos, la muestra.
    private var check: (valores: [String: Int], nota: String)? {
        if let revision {
            guard revision.checkinEnviado, let c = revision.checkin else { return nil }
            return (c.valores, c.nota)
        }
        guard let m = DemoUI.lleno ? MuestrasExtra.checkinLleno : muestras.checkin, (m.energia ?? 0) > 0 else { return nil }
        return (["energia": m.energia ?? 0, "descanso": m.descanso ?? 0, "hambre": m.hambre ?? 0, "adherencia": m.adherencia ?? 0],
                m.nota ?? "")
    }

    private var checkDeLaSemana: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            EncabezadoSeccion(titulo: "Tu check de la semana", detalle: check == nil ? nil : "Enviado")
            VStack(alignment: .leading, spacing: 10) {
                if let check {
                    ForEach(CheckinSemanal.metricas, id: \.clave) { m in
                        let v = check.valores[m.clave] ?? 0
                        HStack(alignment: .firstTextBaseline) {
                            Text(m.etiqueta).font(.subheadline)
                            Spacer(minLength: Espacio.xs)
                            Text("\(v) de 5").font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(m.etiqueta), \(v) de 5")
                    }
                    let nota = check.nota.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !nota.isEmpty {
                        Text(nota).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Todavía no mandaste el check de esta semana.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    irARevision("check")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tarjeta()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cuerpo-check")
    }

    private func irARevision(_ ancla: String) -> some View {
        Button("Ir a Revisión") { withAnimation(.snappy) { navegacion?.irARevision(ancla) } }
            .buttonStyle(BotonSecundario(compacto: true, tono: .marcaTexto))
            .accessibilityHint("Abre Revisión para subirlo")
    }
}
