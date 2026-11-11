import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// La barra de talles (GRAFICOS.md, G3): cuatro tramos y un marcador en la medida del alumno. Sin colores de riesgo: el tramo
/// propio se marca con el relleno del texto y un tilde.
struct BarraTallesPresion: View {
    let cm: Double?
    static let claves = ["estandar", "grande", "extra_grande", "mas_52"]
    @ScaledMetric(relativeTo: .caption) private var altoMarcador: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var letra

    private var tramo: String? { Presion.tramoBrazo(cm) }

    /// Dónde cae la medida a lo ancho: de 22 a 52 cm ocupa los tres primeros tramos; más de 52, el medio del último.
    private var fraccion: CGFloat? {
        guard let cm, cm > 0 else { return nil }
        if cm > 52 { return 0.875 }
        return CGFloat(max(0, min(cm - 22, 30)) / 40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            if let f = fraccion, let cm {
                GeometryReader { g in
                    VStack(spacing: 0) {
                        Text("\(NumeroPresion.texto(cm)) \(NP.cm)").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(.primary)
                        Image(systemName: "arrowtriangle.down.fill").font(.caption2).foregroundStyle(.primary)
                    }
                    .fixedSize()
                    .position(x: max(28, min(g.size.width * f, g.size.width - 28)), y: g.size.height / 2)
                }
                .frame(height: altoMarcador)
                .accessibilityHidden(true)
            }
            HStack(spacing: 3) {
                ForEach(Self.claves, id: \.self) { k in
                    Rectangle().fill(k == tramo ? Color.primary : Color.secondary.opacity(0.3)).frame(height: 14)
                }
            }
            .clipShape(.capsule)
            .accessibilityHidden(true)
            // Desde los 42 cm, la marca aparte (D3).
            HStack(spacing: 3) {
                Color.clear.frame(height: 2)
                Rectangle().fill(Color.secondary).frame(height: 2)
            }
            .accessibilityHidden(true)
            Text(TP.marca42).font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Espacio.xxs) {
                ForEach(Self.claves, id: \.self) { k in
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                        Image(systemName: "checkmark").font(.footnote.weight(.bold)).opacity(k == tramo ? 1 : 0).accessibilityHidden(true)
                        // Con letra grande el nombre y el rango no entran lado a lado: van uno abajo del otro.
                        if letra.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(TP.tramos[k] ?? "").font(.subheadline.weight(k == tramo ? .bold : .regular))
                                Text(TP.tramosRango[k] ?? "").font(.subheadline.weight(k == tramo ? .bold : .regular).monospacedDigit()).foregroundStyle(k == tramo ? .primary : .secondary)
                            }
                            Spacer(minLength: 0)
                        } else {
                            Text(TP.tramos[k] ?? "").font(.subheadline.weight(k == tramo ? .bold : .regular))
                            Spacer(minLength: Espacio.xs)
                            Text(TP.tramosRango[k] ?? "").font(.subheadline.weight(k == tramo ? .bold : .regular).monospacedDigit()).foregroundStyle(k == tramo ? .primary : .secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(k == tramo ? .isSelected : [])
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("presion-talles")
    }
}

/// «Ver cuáles sirven»: la lista verificada para su tramo. Solo existe si el servidor mandó la lista.
struct ListaTensiometrosPresion: View {
    let lista: TensiometrosPresion
    let tramo: String
    let alCerrar: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.m) {
                    if let t = TP.porTramo[tramo] { TextoPresion(t) }
                    let aparatos = lista.tramos[tramo] ?? []
                    if aparatos.isEmpty { TextoPresion(NP.sinLista, secundario: true).accessibilityIdentifier("presion-sin-lista") }
                    ForEach(aparatos) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            TextoPresion(a.nombre, fuente: .headline)
                            if let c = a.codigo, !c.isEmpty { TextoPresion(c, fuente: .subheadline.monospaced()) }
                            if let n = a.nota, !n.isEmpty { TextoPresion(n, fuente: .subheadline, secundario: true) }
                        }
                        .tarjeta()
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .background(Color.fondo)
            .navigationTitle(TP.verCuales)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NP.cerrar, action: alCerrar) } }
        }
    }
}

/// «Antes de la primera serie» (sin aparato), cambiar de aparato y «medir de nuevo» (lo pide la serie).
struct AparatoPresionView: View {
    enum Modo { case primera, cambiar, medirDeNuevo }
    let modelo: ModeloPresion
    let modo: Modo
    var alGuardar: () -> Void = {}
    /// «Marcar un síntoma» tiene que estar siempre a mano, también antes de tener aparato.
    var alMarcarSintoma: (() -> Void)?

    @State private var medida = ""
    @State private var tipo: String?
    @State private var marca = ""
    @State private var modeloAparato = ""
    @State private var codigo = ""
    @State private var desde = ""
    @State private var hasta = ""
    @State private var guardando = false
    @State private var fallo = false
    @State private var verLista = false
    @State private var cargado = false
    @Environment(\.dynamicTypeSize) private var letra

    private static let tipos = ["brazo", "muneca", "reloj_anillo_otro", "ninguno"]
    private var cm: Double? { NumeroPresion.decimal(medida) }
    private var cmValida: Double? { cm.flatMap { $0 >= 20 && $0 <= 70 ? $0 : nil } }
    private var conDatos: Bool { tipo == "brazo" || tipo == "muneca" }
    private var escrito: Presion.Aparato {
        Presion.Aparato(tipo: tipo, marca: marca, modelo: modeloAparato, modeloCodigo: codigo, manguitoMinCm: NumeroPresion.decimal(desde), manguitoMaxCm: NumeroPresion.decimal(hasta))
    }
    private var puedeGuardar: Bool {
        guard cmValida != nil, !guardando else { return false }
        return modo == .medirDeNuevo || tipo != nil
    }

    /// Un paso por pantalla: leer de qué se trata, medir el brazo y anotar el tensiómetro. El último guarda.
    private enum Paso { case leer, medir, aparato }
    private var pasos: [Paso] {
        switch modo {
        case .primera: [.leer, .medir, .aparato]
        case .cambiar: [.medir, .aparato]
        case .medirDeNuevo: [.medir]
        }
    }
    @State private var indice = 0
    private var paso: Paso { pasos[min(indice, pasos.count - 1)] }
    private var ultimo: Bool { indice >= pasos.count - 1 }
    private var puedeSeguir: Bool {
        switch paso {
        case .leer: true
        case .medir: ultimo ? puedeGuardar : cmValida != nil
        case .aparato: puedeGuardar
        }
    }

    var body: some View {
        PantallaPresion {
            switch paso {
            case .leer:
                TituloPresion(NP.antesTitulo)
                // El paso 4 pide fotos: sin esa función en el servidor no se muestra.
                PasosPresion(pasos: modelo.estado?.fotos == true ? TP.antes : Array(TP.antes.prefix(3))).accessibilityIdentifier("presion-antes")
            case .medir:
                TituloPresion(NP.medirBrazoTitulo)
                if modo == .medirDeNuevo { TextoPresion(TP.medirDeNuevo, fuente: .headline).tarjeta().accessibilityIdentifier("presion-medir-de-nuevo") }
                LaminaPresion(dibujo: "presion_g3_medir_brazo", alt: TP.g3Alt, textos: TP.g3)
                PasosPresion(pasos: TP.medirBrazo).accessibilityIdentifier("presion-medir-brazo")
                VStack(alignment: .leading, spacing: Espacio.m) {
                    CampoPresion(rotulo: NP.medida, texto: $medida, teclado: .decimalPad, grande: true, id: "presion-medida")
                    BarraTallesPresion(cm: cmValida)
                    if modo != .primera, Presion.manguitoCalza(cmValida, modo == .medirDeNuevo ? (modelo.estado?.aparato ?? escrito) : escrito) == false {
                        TextoPresion(TP.fueraDeTalle, fuente: .subheadline.weight(.medium)).accessibilityIdentifier("presion-fuera-de-talle")
                    }
                    if let l = modelo.estado?.tensiometros, let t = Presion.tramoBrazo(cmValida), t != "menos_22" {
                        Button(TP.verCuales) { verLista = true }
                            .buttonStyle(BotonPresion(secundario: true))
                            .accessibilityIdentifier("presion-ver-cuales")
                            .sheet(isPresented: $verLista) { ListaTensiometrosPresion(lista: l, tramo: t, alCerrar: { verLista = false }) }
                    }
                }
                .tarjeta()
            case .aparato:
                aparato
            }
            if fallo { TextoPresion(NP.noGuardo, fuente: .headline).tarjeta().accessibilityIdentifier("presion-no-guardo") }
            if let alMarcarSintoma {
                Button(TP.marcarSintoma, action: alMarcarSintoma).buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-marcar-sintoma")
            }
        } pie: {
            if ultimo {
                Button(NP.guardar) { Task { await guardar() } }
                    .buttonStyle(BotonPresion(ocupado: guardando))
                    .disabled(!puedeSeguir)
                    .accessibilityIdentifier("presion-guardar")
            } else {
                Button(NP.seguir) { fallo = false; indice += 1 }
                    .buttonStyle(BotonPresion())
                    .disabled(!puedeSeguir)
                    .accessibilityIdentifier("presion-antes-seguir")
            }
            if indice > 0 {
                Button(NP.volver) { fallo = false; indice -= 1 }.buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-antes-volver")
            }
        }
        .background(Color.fondo)
        .onAppear(perform: cargar)
    }

    @ViewBuilder private var aparato: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            TituloPresion(NP.tipoAparato)
            ForEach(Self.tipos, id: \.self) { k in
                Button { tipo = k } label: {
                    HStack(spacing: Espacio.s) {
                        Image(systemName: tipo == k ? "largecircle.fill.circle" : "circle").font(.title3).foregroundStyle(tipo == k ? Color.marcaTexto : Color.secondary).accessibilityHidden(true)
                        TextoPresion(NP.tipos[k] ?? k, fuente: .headline)
                    }
                    .frame(minHeight: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tipo == k ? .isSelected : [])
                .accessibilityIdentifier("presion-tipo-\(k)")
            }
            if tipo == "reloj_anillo_otro" { TextoPresion(NP.relojNoSirve, fuente: .subheadline.weight(.medium)).accessibilityIdentifier("presion-reloj-no-sirve") }
        }
        .tarjeta()
        if conDatos {
            VStack(alignment: .leading, spacing: Espacio.m) {
                CampoPresion(rotulo: NP.marca, texto: $marca, id: "presion-marca")
                CampoPresion(rotulo: NP.modelo, texto: $modeloAparato, id: "presion-modelo")
                CampoPresion(rotulo: NP.codigo, texto: $codigo, mayusculas: true, ayuda: NP.codigoAyuda, id: "presion-codigo")
                Text(NP.rango).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                // Con letra grande, uno debajo del otro.
                let lado = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s)) : AnyLayout(HStackLayout(alignment: .top, spacing: Espacio.s))
                lado {
                    CampoPresion(rotulo: NP.desde, texto: $desde, teclado: .decimalPad, id: "presion-rango-desde")
                    CampoPresion(rotulo: NP.hasta, texto: $hasta, teclado: .decimalPad, id: "presion-rango-hasta")
                }
                if Presion.manguitoCalza(cmValida, escrito) == false {
                    TextoPresion(TP.fueraDeTalle, fuente: .subheadline.weight(.medium)).accessibilityIdentifier("presion-fuera-de-talle")
                }
            }
            .tarjeta()
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        // «Medir de nuevo» arranca vacío: la medida vieja no vale para esta serie.
        if modo != .medirDeNuevo { medida = NumeroPresion.texto(modelo.estado?.circunferenciaBrazoCm) }
        guard let a = modelo.estado?.aparato else { return }
        tipo = a.tipo
        marca = a.marca ?? ""
        modeloAparato = a.modelo ?? ""
        codigo = a.modeloCodigo ?? ""
        desde = NumeroPresion.texto(a.manguitoMinCm)
        hasta = NumeroPresion.texto(a.manguitoMaxCm)
    }

    private func guardar() async {
        guard let cm = cmValida else { return }
        guardando = true
        fallo = false
        defer { guardando = false }
        if modo == .medirDeNuevo || cm != modelo.estado?.circunferenciaBrazoCm {
            guard await modelo.guardarMedida(cm) == .ok else { fallo = true; return }
        }
        if modo != .medirDeNuevo, let tipo, tipo != "ninguno" {
            let a = conDatos ? escrito : Presion.Aparato(tipo: tipo)
            let v = modelo.estado?.aparato
            let igual = v?.tipo == a.tipo && (v?.marca ?? "") == a.marca?.trimmingCharacters(in: .whitespaces) ?? "" && (v?.modelo ?? "") == a.modelo?.trimmingCharacters(in: .whitespaces) ?? ""
                && (v?.modeloCodigo ?? "") == a.modeloCodigo?.trimmingCharacters(in: .whitespaces) ?? "" && v?.manguitoMinCm == a.manguitoMinCm && v?.manguitoMaxCm == a.manguitoMaxCm
            if !igual { guard await modelo.guardarAparato(a) == .ok else { fallo = true; return } }
        }
        alGuardar()
    }
}
