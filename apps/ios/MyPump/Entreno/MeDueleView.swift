import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosFeedback

// MARK: En la tarjeta del ejercicio

/// Lo que «Me duele» deja a la vista en el ejercicio: la molestia avisada (o ya revisada) y «Cambiar». Sin molestia, nada:
/// el botón vive en la fila de acciones. Con la palanca apagada o sin el servidor nuevo, no existe.
struct EstadoMolestia: View {
    let lugar: String
    let abrir: () -> Void
    @State private var app = Proveedor.modelo

    var body: some View {
        if let f = app.feedback, f.dueleHabilitado, let m = f.molestia(ejercicio: lugar) {
            HStack(alignment: .center, spacing: Espacio.s) {
                Image(systemName: m.abierta ? "bandage.fill" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(m.abierta ? Color.alerta : Color.exito)
                    .frame(width: 40, height: 40)
                    .background((m.abierta ? Color.alerta : Color.exito).opacity(0.14), in: .circle)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.abierta ? T.dueleAvisada : T.dueleResuelta).font(.subheadline.weight(.semibold))
                    Text(m.abierta ? "\(m.nombreZona). \(T.dueleListo)" : "\(m.nombreZona).")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if m.abierta {
                    Button(T.dueleCambiar, action: abrir)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("duele-cambiar")
                }
            }
            .tarjeta(relleno: 14)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(m.abierta ? "duele-avisada" : "duele-resuelta")
        }
    }
}

// MARK: La hoja

/// «Me duele»: dónde (el dibujo), desde cuándo, en qué parte del movimiento, cómo es y cuánto. Un solo envío; si ya había una
/// abierta para este ejercicio, la corrige.
struct MeDueleView: View {
    let modelo: ModeloFeedback
    let lugar: String
    let ejercicioNombre: String
    let diaId: String?
    let cerrar: () -> Void

    @State private var borrador = ReglasMolestia.Borrador()
    @State private var vista = FiguraCuerpo.Vista.frente
    /// El mismo id en cada reintento: el servidor no duplica.
    @State private var id = UUID().uuidString.lowercased()
    @State private var enviando = false
    @State private var enviada = false
    @State private var fallo: String?
    @State private var corrige = false
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        NavigationStack {
            Group {
                if enviada { listo } else { formulario }
            }
            .background(Color.fondo)
            .navigationTitle(T.dueleTitulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar, action: cerrar).accessibilityIdentifier("duele-cerrar") } }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(enviando)
        .onAppear {
            if let m = modelo.molestia(ejercicio: lugar), m.abierta {
                borrador = ReglasMolestia.Borrador(m)
                vista = FiguraCuerpo.vista(de: m.zona)
                id = m.id
                corrige = true
            }
        }
    }

    private var formulario: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(NombreEjercicio(ejercicioNombre).principal).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
                    Text(T.dueleIntro).font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                donde
                Pregunta(titulo: T.dueleDesde, opciones: ReglasMolestia.desde, elegida: $borrador.desde, prefijo: "duele-desde")
                Pregunta(titulo: T.dueleCuando, opciones: ReglasMolestia.cuando, elegida: $borrador.cuando, prefijo: "duele-cuando")
                Pregunta(titulo: T.dueleTipo, opciones: ReglasMolestia.tipo, elegida: $borrador.tipo, prefijo: "duele-tipo")
                cuanto
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    TextField(T.dueleNota, text: $borrador.nota, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                        .accessibilityIdentifier("duele-nota")
                        .onChange(of: borrador.nota) { _, n in
                            let corta = ReglasMolestia.nota(n)
                            if corta != n { borrador.nota = corta }
                        }
                }
                .tarjeta()
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.xs)
            .padding(.bottom, Espacio.l)
            .anchoLectura()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { pie }
    }

    private var pie: some View {
        VStack(spacing: Espacio.xs) {
            if let fallo {
                Label(fallo, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.alerta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("duele-fallo")
            } else if !borrador.completa {
                Text(T.dueleFalta).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("duele-falta")
            }
            Button { enviar() } label: {
                if enviando { ProgressView().tint(Color.sobreMarca) } else { Text(corrige ? T.dueleCorregir : T.dueleEnviar) }
            }
            .buttonStyle(BotonMarca(ocupado: enviando))
            .disabled(!borrador.completa || enviando)
            .accessibilityIdentifier("duele-enviar")
        }
        .padding(.horizontal, Espacio.m)
        .padding(.top, Espacio.s)
        .padding(.bottom, Espacio.xs)
        .frame(maxWidth: Ancho.lectura)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    /// El dibujo: tocar una parte da la zona y el lado de una vez.
    private var donde: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(T.dueleDonde).font(.headline).accessibilityAddTraits(.isHeader)
                Text(T.dueleDondeAyuda).font(.subheadline).foregroundStyle(.secondary)
            }
            Picker(T.dueleDonde, selection: $vista) {
                Text(T.dueleFrente).tag(FiguraCuerpo.Vista.frente)
                Text(T.dueleEspalda).tag(FiguraCuerpo.Vista.espalda)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("duele-vista")
            DibujoCuerpo(vista: vista, zona: borrador.zona, lado: borrador.lado) { p in
                guard let z = p.zona, let l = p.lado else { return }
                withAnimation(.snappy(duration: 0.2)) {
                    // Con «los dos» elegido, tocar el otro lado de la misma zona no lo deshace.
                    if borrador.zona == z, borrador.lado == "ambos", l != "centro" { return }
                    borrador.zona = z; borrador.lado = l
                }
                fallo = nil
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            if let nombre = borrador.nombreZona {
                HStack(spacing: Espacio.xs) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.marca).accessibilityHidden(true)
                    Text(nombre).font(.headline)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("duele-zona")
                if borrador.lado != "centro" {
                    Opciones(opciones: ReglasMolestia.ladosElegibles,
                             elegida: $borrador.lado, prefijo: "duele-lado", centradas: true)
                        .accessibilityLabel(T.dueleLado)
                }
            }
        }
        .tarjeta()
    }

    /// La escala simple: cuatro escalones, cada uno con su medidor.
    private var cuanto: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text(T.dueleCuanto).font(.headline).accessibilityAddTraits(.isHeader)
            let disposicion = letra.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Espacio.xs)) : AnyLayout(HStackLayout(alignment: .top, spacing: Espacio.xs))
            disposicion {
                ForEach(Array(ReglasMolestia.niveles.enumerated()), id: \.element.id) { n, nivel in
                    let elegido = borrador.intensidad == nivel.id
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { borrador.intensidad = nivel.id }
                        fallo = nil
                    } label: {
                        VStack(spacing: 8) {
                            Medidor(nivel: n + 1, de: ReglasMolestia.niveles.count, encendido: elegido)
                            Text(nivel.texto).font(.caption.weight(.semibold)).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(elegido ? Color.sobreMarca : Color.primary)
                        .padding(.vertical, 12).padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(elegido ? Color.marca : Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(nivel.texto)
                    .accessibilityAddTraits(elegido ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("duele-nivel-\(nivel.id)")
                }
            }
        }
        .tarjeta()
    }

    private var listo: some View {
        VStack(spacing: Espacio.m) {
            Spacer(minLength: Espacio.l)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(Color.marca)
                .symbolEffect(.bounce, value: enviada)
                .accessibilityHidden(true)
            Text(T.dueleListoTitulo).font(.title2.weight(.bold)).accessibilityAddTraits(.isHeader)
            VStack(spacing: Espacio.xs) {
                Text(T.dueleListo)
                if ReglasMolestia.esFuerte(borrador.intensidad ?? 0) { Text(T.dueleListoFuerte).fontWeight(.semibold).accessibilityIdentifier("duele-listo-fuerte") }
            }
            .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Espacio.l)
            Button(T.listo, action: cerrar).buttonStyle(BotonMarca()).accessibilityIdentifier("duele-listo")
        }
        .padding(Espacio.l)
        .frame(maxWidth: Ancho.lectura)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duele-recibido")
    }

    private func enviar() {
        guard borrador.completa, !enviando else { return }
        enviando = true; fallo = nil
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        Task {
            let r = await modelo.avisar(id: id, ejercicioId: lugar, ejercicioNombre: ejercicioNombre, diaId: diaId, borrador, version: version)
            enviando = false
            switch r {
            case .ok:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.snappy) { enviada = true }
            case .sinSenal: fallo = T.dueleSinRed
            case .tope: fallo = T.dueleTope
            case .error: fallo = T.dueleError
            }
        }
    }
}

// MARK: Piezas

/// Una pregunta de una sola respuesta, en su tarjeta.
private struct Pregunta: View {
    let titulo: String
    let opciones: [ReglasMolestia.Opcion]
    @Binding var elegida: String?
    let prefijo: String

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            Text(titulo).font(.headline).accessibilityAddTraits(.isHeader)
            Opciones(opciones: opciones, elegida: $elegida, prefijo: prefijo)
        }
        .tarjeta()
    }
}

/// Las opciones como píldoras que saltan de renglón: con letra grande no se corta nada.
private struct Opciones: View {
    let opciones: [ReglasMolestia.Opcion]
    @Binding var elegida: String?
    let prefijo: String
    var centradas = false

    var body: some View {
        FilaFluida(espaciado: 8, interlineado: 8) {
            ForEach(opciones) { o in
                let si = elegida == o.id
                Button {
                    withAnimation(.snappy(duration: 0.18)) { elegida = o.id }
                } label: {
                    Text(o.texto)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(si ? Color.sobreMarca : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(si ? Color.marca : Color.campo, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(si ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("\(prefijo)-\(o.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: centradas ? .center : .leading)
    }
}

/// Barras que crecen: una, dos, tres o cuatro encendidas.
private struct Medidor: View {
    let nivel: Int
    let de: Int
    let encendido: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...de, id: \.self) { n in
                Capsule()
                    .fill(n <= nivel ? (encendido ? Color.sobreMarca : Color.marca) : (encendido ? Color.sobreMarca.opacity(0.3) : Color.primary.opacity(0.14)))
                    .frame(width: 5, height: CGFloat(6 + n * 4))
            }
        }
        .frame(height: 22, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// La figura, dibujada con las piezas compartidas. Cada parte es un botón para VoiceOver; el dedo usa un blanco más
/// generoso que el dibujo (`FiguraCuerpo.pieza(en:)`).
private struct DibujoCuerpo: View {
    let vista: FiguraCuerpo.Vista
    let zona: String?
    let lado: String?
    let alTocar: (FiguraCuerpo.Pieza) -> Void

    private func elegida(_ p: FiguraCuerpo.Pieza) -> Bool {
        guard let z = p.zona, z == zona else { return false }
        return lado == "ambos" || p.lado == lado
    }

    var body: some View {
        GeometryReader { g in
            let escala = min(g.size.width / FiguraCuerpo.ancho, g.size.height / FiguraCuerpo.alto)
            let ancho = FiguraCuerpo.ancho * escala, alto = FiguraCuerpo.alto * escala
            ZStack(alignment: .topLeading) {
                ForEach(FiguraCuerpo.piezas(vista)) { p in
                    let si = elegida(p)
                    let m = p.marco
                    FormaPieza(pieza: p, escala: escala)
                        .fill(p.zona == nil ? Color.primary.opacity(0.08) : si ? Color.marca : Color.primary.opacity(0.16))
                        .overlay { if si { FormaPieza(pieza: p, escala: escala).stroke(Color.marca.opacity(0.35), lineWidth: 6) } }
                        .frame(width: m.ancho * escala, height: m.alto * escala)
                        .position(x: (m.x + m.ancho / 2) * escala, y: (m.y + m.alto / 2) * escala)
                        .accessibilityElement()
                        .accessibilityHidden(p.zona == nil)
                        .accessibilityLabel(p.zona.map { ReglasMolestia.nombreZona($0, lado: p.lado ?? "centro") } ?? "")
                        .accessibilityAddTraits(si ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { alTocar(p) }
                        .accessibilityIdentifier("duele-pieza-\(vista.rawValue)-\(p.id)")
                }
            }
            .frame(width: ancho, height: alto)
            .contentShape(.rect)
            .gesture(SpatialTapGesture().onEnded { t in
                if let p = FiguraCuerpo.pieza(en: vista, x: t.location.x / escala, y: t.location.y / escala) {
                    UISelectionFeedbackGenerator().selectionChanged()
                    alTocar(p)
                }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("duele-dibujo")
    }
}

private struct FormaPieza: Shape {
    let pieza: FiguraCuerpo.Pieza
    let escala: Double

    /// Dibuja en el marco de la pieza: las coordenadas del lienzo, corridas a su esquina.
    func path(in rect: CGRect) -> Path {
        let m = pieza.marco
        let dx = CGFloat(m.x * escala), dy = CGFloat(m.y * escala)
        var a = pieza.a.map { CGFloat($0 * escala) }
        switch pieza.forma {
        case .elipse:
            return Path(ellipseIn: CGRect(x: a[0] - a[2] - dx, y: a[1] - a[3] - dy, width: a[2] * 2, height: a[3] * 2))
        case .caja:
            return Path(roundedRect: CGRect(x: a[0] - dx, y: a[1] - dy, width: a[2], height: a[3]), cornerRadius: a[4], style: .continuous)
        case .capsula:
            a[0] -= dx; a[2] -= dx; a[1] -= dy; a[3] -= dy
            var p = Path()
            p.move(to: CGPoint(x: a[0], y: a[1]))
            p.addLine(to: CGPoint(x: a[2], y: a[3]))
            return p.strokedPath(StrokeStyle(lineWidth: a[4] * 2, lineCap: .round))
        }
    }
}
