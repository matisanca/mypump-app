import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// Las pantallas del recorrido de una toma. El nombre queda guardado con la sesión en curso (`EnCursoPresion.etapa`), así al
/// volver a abrir la app se sabe dónde quedó.
enum EtapaPresion {
    static let medir = "medir"
    /// «Cuándo» (o las indicaciones de bajo efecto). El nombre viene de cuando Cuándo y Cómo eran una sola pantalla.
    static let instrucciones = "instrucciones"
    static let como = "como"
    static let previa = "previa"
    static let esperarMejor = "esperarMejor"
    static let reposo = "reposo"
    static let anotar = "anotar"
    static let espera = "espera"
    static let guardiaPresion = "guardiaPresion"
    static let guardiaSintomas = "guardiaSintomas"
    static let listo = "listo"
    static let guiaIntro = "guiaIntro"
    static let guiaEspera = "guiaEspera"
    static let guiaAnotar = "guiaAnotar"
    static let mareo = "mareo"
    /// La hoja de síntomas que se abre después de una toma con el pulso o la alta fuera de lo esperado. La toma ya quedó guardada.
    static let sintomas = "sintomas"
}

extension EnCursoPresion {
    /// La sesión sigue abierta en pantalla: un síntoma del botón también se suma a ella. Cerrada (el cierre, el mareo de la
    /// ortostática o la guardia), solo viaja el aviso.
    var abiertaASintomas: Bool {
        ![EtapaPresion.listo, EtapaPresion.mareo, EtapaPresion.guardiaPresion, EtapaPresion.guardiaSintomas].contains(etapa)
    }
}

/// Las listas de síntomas para marcar: las 8 de alarma y las otras 3.
struct SelectorSintomasPresion: View {
    @Binding var seleccion: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            grupo(NP.alarma, Presion.alarma)
            grupo(NP.otros, Presion.otros)
        }
    }

    private func grupo(_ titulo: String, _ codigos: [String]) -> some View {
        VStack(alignment: .leading, spacing: Espacio.xxs) {
            TituloPresion(titulo)
            ForEach(codigos, id: \.self) { c in
                let marcado = seleccion.contains(c)
                Button { if marcado { seleccion.remove(c) } else { seleccion.insert(c) } } label: {
                    HStack(spacing: Espacio.s) {
                        Image(systemName: marcado ? "checkmark.square.fill" : "square").font(.title3).foregroundStyle(.primary).accessibilityHidden(true)
                        TextoPresion(TextosPresion.sintomas[c] ?? c)
                    }
                    .frame(minHeight: 56)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(marcado ? .isSelected : [])
                .accessibilityIdentifier("presion-sintoma-\(c)")
            }
        }
        .tarjeta()
    }
}

/// «Qué evitar» (G5): diez tarjetas con su dibujo, el título y la aclaración.
struct QueEvitarPresion: View {
    let alCerrar: () -> Void
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: letra.isAccessibilitySize ? 280 : 150), spacing: Espacio.s, alignment: .top)], spacing: Espacio.s) {
                    ForEach(Array(TP.g5.enumerated()), id: \.offset) { i, t in
                        VStack(alignment: .leading, spacing: Espacio.xs) {
                            DibujoPresion(String(format: "presion_g5_%02d", i + 1), alt: "").frame(maxWidth: 120).frame(maxWidth: .infinity).accessibilityHidden(true)
                            TextoPresion(t[0], fuente: .subheadline.weight(.semibold))
                            TextoPresion(t[1], fuente: .footnote, secundario: true)
                        }
                        .tarjeta(relleno: 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(TP.asiNo). \(t[0]). \(t[1])")
                        .accessibilityIdentifier("presion-evitar-\(i + 1)")
                    }
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .background(Color.fondo)
            .navigationTitle(TP.queEvitar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NP.cerrar, action: alCerrar) .accessibilityIdentifier("presion-evitar-cerrar") } }
        }
    }
}

/// La alta, la baja, el pulso y el símbolo de latido irregular. Un valor imposible no pasa; uno fuera de lo común pide confirmar.
private struct AnotarPresion: View {
    let titulo: String?
    let conFoto: Bool
    /// Solo sentado: con el pulso o la alta fuera de lo esperado, después de guardar la toma se abre la hoja de síntomas.
    let preguntaSintomas: Bool
    /// `conHoja`: la toma se guarda y sigue la hoja de síntomas; recién con lo que conteste se decide el paso.
    let registrar: (_ sis: Int, _ dia: Int, _ pulso: Int, _ irregular: Bool, _ confirmada: Bool, _ conHoja: Bool) -> Void

    private enum Aviso { case imposible, confirmar }
    @State private var sis = ""
    @State private var dia = ""
    @State private var pulso = ""
    @State private var irregular = false
    @State private var aviso: Aviso?
    @State private var confirmada = false
    /// Sube cada vez que hay que traer el tilde de latido irregular a la vista (con el teclado abierto en el pulso).
    @State private var alTilde = 0
    @FocusState private var foco: Int?
    @Environment(\.dynamicTypeSize) private var letra
    @Environment(\.marcarSintomaFlujoPresion) private var marcarSintomaFlujo
    @Environment(\.cerrarFlujoPresion) private var cerrarFlujo

    private var numeros: (Int, Int, Int)? {
        guard let s = Int(sis), let d = Int(dia), let p = Int(pulso) else { return nil }
        return (s, d, p)
    }

    /// Tres cifras, o dos que ya no admiten una tercera (con «95» no hay alta posible de tres cifras): el número está entero.
    private static func entero(_ v: String, tope: Int) -> Bool {
        v.count >= 3 || (v.count == 2 && (Int(v) ?? 0) * 10 > tope)
    }

    /// Solo cifras, tres como mucho. Con el número entero el foco pasa solo al campo que sigue; después del pulso se va el
    /// teclado, así el tilde de latido irregular y el botón quedan a la vista también con letra grande.
    private func escrito(_ campo: Int, _ valor: String, tope: Int, poner: (String) -> Void) {
        let limpio = String(valor.filter(\.isNumber).prefix(3))
        if limpio != valor { poner(limpio); return }
        limpiar()
        guard foco == campo, Self.entero(limpio, tope: tope) else { return }
        foco = campo < 2 ? campo + 1 : nil
    }

    var body: some View {
        // Con letra grande los tres campos van uno debajo del otro.
        let campos = letra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.m)) : AnyLayout(HStackLayout(alignment: .top, spacing: Espacio.s))
        PantallaPresion(ancla: "presion-irregular-ancla", vez: alTilde) {
            if let titulo { TituloPresion(titulo).accessibilityIdentifier("presion-anotar-titulo") }
            campos {
                CampoPresion(rotulo: NP.alta, texto: $sis, teclado: .numberPad, grande: true, id: "presion-alta").focused($foco, equals: 0)
                CampoPresion(rotulo: NP.baja, texto: $dia, teclado: .numberPad, grande: true, id: "presion-baja").focused($foco, equals: 1)
                CampoPresion(rotulo: NP.pulso, texto: $pulso, teclado: .numberPad, grande: true, id: "presion-pulso").focused($foco, equals: 2)
            }
            .disabled(aviso == .confirmar)
            .tarjeta()
            Button { irregular.toggle() } label: {
                HStack(alignment: .top, spacing: Espacio.s) {
                    Image(systemName: irregular ? "checkmark.square.fill" : "square").font(.title2).foregroundStyle(.primary).accessibilityHidden(true)
                    TextoPresion(NP.irregular)
                }
                .frame(minHeight: 56)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(aviso == .confirmar)
            .tarjeta()
            .accessibilityAddTraits(irregular ? .isSelected : [])
            .accessibilityIdentifier("presion-irregular")
            .id("presion-irregular-ancla")
            if aviso != nil {
                TextoPresion(conFoto ? TP.revisarNumero : TP.revisarNumeroSinFoto, fuente: .headline).tarjeta().accessibilityIdentifier("presion-revisar")
            }
        } pie: {
            if aviso == .confirmar {
                Button(NP.confirmar) { confirmada = true; seguir() }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-confirmar")
                Button(NP.corregir) { self.aviso = nil; foco = 0 }.buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-corregir")
            } else {
                // Siempre a la vista, por encima del teclado.
                Button(NP.anotar) { anotar() }
                    .buttonStyle(BotonPresion())
                    .disabled(sis.isEmpty || dia.isEmpty || pulso.isEmpty)
                    .accessibilityIdentifier("presion-anotar")
            }
        }
        .onChange(of: sis) { _, v in escrito(0, v, tope: Presion.Lim.sisMax) { sis = $0 } }
        .onChange(of: dia) { _, v in escrito(1, v, tope: Presion.Lim.diaMax) { dia = $0 } }
        .onChange(of: pulso) { _, v in escrito(2, v, tope: Presion.Lim.pulMax) { pulso = $0 } }
        // Con el teclado en el pulso, el tilde de abajo se trae a la vista (con letra grande quedaba tapado).
        .onChange(of: foco) { _, f in if f == 2 { alTilde += 1 } }
        // Con el teclado arriba solo queda «Anotar la toma» sobre el teclado; los del recorrido vuelven al bajarlo.
        .environment(\.marcarSintomaFlujoPresion, foco == nil ? marcarSintomaFlujo : nil)
        .environment(\.cerrarFlujoPresion, foco == nil ? cerrarFlujo : nil)
    }

    private func limpiar() { aviso = nil; confirmada = false }

    private func anotar() {
        foco = nil
        // Lo que no es un número entero no pasa, igual que un valor imposible.
        switch Presion.validarToma(sis: Double(sis), dia: Double(dia), pulso: Double(pulso)) {
        case .imposible:
            aviso = .imposible
            AccessibilityNotification.Announcement(conFoto ? TP.revisarNumero : TP.revisarNumeroSinFoto).post()
        case .confirmar:
            aviso = .confirmar
            AccessibilityNotification.Announcement(conFoto ? TP.revisarNumero : TP.revisarNumeroSinFoto).post()
        case .ok:
            seguir()
        }
    }

    /// La toma se guarda primero (queda en disco y en la cola); la hoja de síntomas, si toca, va después.
    private func seguir() {
        guard let (s, d, p) = numeros else { return }
        registrar(s, d, p, irregular, confirmada, preguntaSintomas && (p >= 120 || p <= 40 || s < 90))
    }
}

/// Una toma de principio a fin: medir de nuevo (si la serie lo pide), cuándo y cómo, las preguntas previas, el reposo, anotar y lo
/// que toque después (repetir, la lista de alarma, la guardia o el cierre), y la ortostática y la comparación de brazos si la serie
/// las trae. Nada de acá toca Entreno ni la rutina.
struct TomaPresionView: View {
    let modelo: ModeloPresion
    let alCerrar: () -> Void

    @State private var previas: [String: Bool] = [:]
    @State private var horaDosis = Date()
    @State private var entreno: Bool?
    @State private var queEvitar = false
    @State private var esperaTerminada = false
    @State private var sintoma = false
    /// Lo marcado en la hoja de síntomas de después de la toma.
    @State private var sintomasHoja: Set<String> = []

    private var enCurso: EnCursoPresion? { modelo.enCurso }
    private var tipo: String { enCurso?.sesion.tipo ?? "estandar" }
    private var guiada: Bool { tipo == "ortostatica" || tipo == "comparacion_brazos" }
    private var brazo: String? { enCurso?.sesion.brazo }
    private var sentadoParado: Bool { enCurso?.variante == "sentado_parado" }
    private var pasos: [Presion.PasoGuiado] { Presion.pasos(tipo, enCurso?.variante) }
    private var pasoActual: Presion.PasoGuiado? { enCurso.flatMap { pasos.indices.contains($0.paso) ? pasos[$0.paso] : nil } }

    var body: some View {
        NavigationStack {
            Group {
                switch enCurso?.etapa {
                case EtapaPresion.medir: AparatoPresionView(modelo: modelo, modo: .medirDeNuevo, alGuardar: trasMedir)
                case EtapaPresion.instrucciones: instrucciones
                case EtapaPresion.como: como
                case EtapaPresion.previa: previa
                case EtapaPresion.esperarMejor: esperarMejor
                case EtapaPresion.reposo: reposo
                case EtapaPresion.anotar:
                    AnotarPresion(titulo: nil, conFoto: modelo.estado?.fotos == true, preguntaSintomas: true, registrar: registrar)
                case EtapaPresion.espera: espera
                case EtapaPresion.guardiaPresion: GuardiaPresion(porSintomas: false, alCerrar: cerrar)
                case EtapaPresion.guardiaSintomas: GuardiaPresion(porSintomas: true, alCerrar: cerrar)
                case EtapaPresion.listo: listo
                case EtapaPresion.guiaIntro: guiaIntro
                case EtapaPresion.guiaEspera: guiaEspera
                case EtapaPresion.guiaAnotar:
                    AnotarPresion(titulo: tituloPaso(anotando: true), conFoto: modelo.estado?.fotos == true, preguntaSintomas: pasoActual?.posicion == "sentado" && tipo == "ortostatica",
                                  registrar: registrar)
                        .id(enCurso?.paso ?? 0)
                        .safeAreaInset(edge: .bottom) { if tipo == "ortostatica" { botonMareo.padding(Espacio.m).background(.bar) } }
                case EtapaPresion.mareo: mareo
                case EtapaPresion.sintomas: hojaSintomas
                default: Color.fondo
                }
            }
            .background(Color.fondo)
            .navigationTitle(NP.titulo)
            .navigationBarTitleDisplayMode(.inline)
            // «Marcar un síntoma» siempre a mano y «Cerrar»: botones de ancho completo con texto, debajo del principal.
            .environment(\.marcarSintomaFlujoPresion, accionMarcarSintoma)
            .environment(\.cerrarFlujoPresion, accionCerrar)
            .sheet(isPresented: $sintoma) {
                MarcarSintomaPresion(modelo: modelo, alCerrar: { sintoma = false }).presentationDragIndicator(.visible).sinBotonesFlujoPresion()
            }
        }
        .onChange(of: enCurso == nil) { _, sin in if sin { alCerrar() } }
    }

    /// En la guardia ya no hace falta, y en la hoja de síntomas ya se está marcando.
    private var conMarcarSintoma: Bool {
        guard let e = enCurso?.etapa else { return false }
        return ![EtapaPresion.guardiaPresion, EtapaPresion.guardiaSintomas, EtapaPresion.sintomas].contains(e)
    }

    /// Donde el botón principal ya es «Cerrar» (la guardia, el mareo y el cierre sin nada que siga) no se repite.
    private var conCerrar: Bool {
        guard let e = enCurso?.etapa else { return true }
        if [EtapaPresion.guardiaPresion, EtapaPresion.guardiaSintomas, EtapaPresion.mareo].contains(e) { return false }
        if e == EtapaPresion.listo { return siguiente != nil }
        return true
    }

    private var accionMarcarSintoma: (@MainActor () -> Void)? {
        guard conMarcarSintoma else { return nil }
        return { sintoma = true }
    }

    private var accionCerrar: (@MainActor () -> Void)? {
        guard conCerrar else { return nil }
        return { cerrar() }
    }

    // MARK: Pasos

    private func ir(_ etapa: String, fin: Date? = nil) {
        modelo.cambiar { $0.etapa = etapa; $0.finTemporizador = fin }
    }

    /// Al salir: una repetición que quedó pendiente se guarda para retomarla; lo demás se cierra (lo anotado ya está en la cola).
    private func cerrar() {
        if let e = enCurso, !guiada, !e.sesion.tomas.isEmpty, [EtapaPresion.espera, EtapaPresion.anotar, EtapaPresion.sintomas].contains(e.etapa),
           let ev = modelo.evaluar(), ev.paso == .repetir || ev.paso == .repetirConLista {
            alCerrar()
            return
        }
        modelo.terminar()
        alCerrar()
    }

    private func empezarReposo() {
        ir(EtapaPresion.reposo, fin: Date().addingTimeInterval(TiemposPresion.reposo()))
    }

    /// Con el brazo medido: la comparación de brazos va antes de la toma del día, si la serie la pide.
    private func trasMedir() {
        if let s = modelo.serieVista, s.compararBrazos, enCurso?.sesion.serieId == s.id {
            modelo.empezar(tipo: "comparacion_brazos", serieId: s.id, brazo: s.brazo, etapa: EtapaPresion.guiaIntro)
        } else {
            ir(EtapaPresion.instrucciones)
        }
    }

    private func registrar(_ sis: Int, _ dia: Int, _ pulso: Int, _ irregular: Bool, _ confirmada: Bool, _ conHoja: Bool) {
        CentroAvisos.shared.cancelarRepetirPresion()
        let p = guiada ? pasoActual : nil
        // La toma queda guardada (en disco y en la cola) antes de cualquier pregunta: si cierra la app en la hoja, no se pierde.
        guard let ev = modelo.anotarToma(sis: sis, dia: dia, pulso: pulso, latidoIrregular: irregular, posicion: p?.posicion ?? "sentado", minutosDePie: p?.minutosDePie,
                                         brazo: p?.brazo, confirmada: confirmada) else { return }
        if conHoja {
            sintomasHoja = []
            ir(EtapaPresion.sintomas)
            return
        }
        trasToma(ev)
    }

    /// Lo marcado en la hoja de síntomas se suma a la sesión y, con eso, se decide el paso.
    private func responderHoja() {
        let codigos = (Presion.alarma + Presion.otros).filter(sintomasHoja.contains)
        guard let ev = codigos.isEmpty ? modelo.evaluar() : modelo.sumarSintomas(codigos) else { return }
        trasToma(ev)
    }

    /// Con la toma anotada: el paso que sigue de la ortostática o la comparación de brazos, o lo que diga la regla.
    private func trasToma(_ ev: Presion.Evaluacion) {
        if guiada, ev.paso == .listo, let e = enCurso, e.paso + 1 < pasos.count {
            let sigue = pasos[e.paso + 1]
            modelo.cambiar { $0.paso += 1; $0.etapa = EtapaPresion.guiaEspera; $0.finTemporizador = Date().addingTimeInterval(TiemposPresion.segundos(sigue.esperaS)) }
            return
        }
        rutear(ev)
    }

    /// Qué pantalla sigue según la regla. Se decide en el teléfono, sin esperar al servidor.
    private func rutear(_ ev: Presion.Evaluacion) {
        switch ev.paso {
        case .guardiaSintomas: ir(EtapaPresion.guardiaSintomas)
        case .guardiaPresion: ir(EtapaPresion.guardiaPresion)
        case .repetir, .repetirConLista:
            esperaTerminada = false
            ir(EtapaPresion.espera, fin: Date().addingTimeInterval(TiemposPresion.segundos(Presion.esperaRepeticionS)))
            // El recordatorio de los 10 minutos, por si no hace la repetición. Con los tiempos acortados de las pruebas no se agenda.
            if TiemposPresion.segundos(Presion.esperaRepeticionS) == TimeInterval(Presion.esperaRepeticionS) {
                let cuando = Date().addingTimeInterval(TimeInterval(Presion.recordatorioMin * 60))
                Task { await CentroAvisos.shared.programarRepetirPresion(cuando) }
            }
        case .listo: ir(EtapaPresion.listo)
        }
    }

    // MARK: Cuándo y cómo

    /// «Cuándo», o las indicaciones de la toma bajo efecto. Un paso por pantalla: «Cómo» va en la siguiente.
    private var instrucciones: some View {
        PantallaPresion {
            if tipo == "bajo_efecto" {
                PasosPresion(pasos: TP.bajoEfecto).accessibilityIdentifier("presion-bajo-efecto")
            } else {
                TituloPresion(TP.cuandoTitulo)
                PasosPresion(pasos: TP.cuando).accessibilityIdentifier("presion-cuando")
                Button(TP.queEvitar) { queEvitar = true }
                    .buttonStyle(BotonPresion(secundario: true))
                    .accessibilityIdentifier("presion-que-evitar")
                    .sheet(isPresented: $queEvitar) { QueEvitarPresion(alCerrar: { queEvitar = false }) }
            }
        } pie: {
            Button(NP.seguir) { ir(EtapaPresion.como) }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-cuando-seguir")
        }
    }

    private var como: some View {
        PantallaPresion {
            TituloPresion(TP.comoTitulo).accessibilityIdentifier("presion-como")
            LaminaPresion(dibujo: "presion_g1_postura", alt: TP.g1Alt, textos: TP.g1)
            VStack(alignment: .leading, spacing: Espacio.s) {
                DibujoPresion("presion_g2_altura_brazo", alt: TP.g2Alt).frame(maxWidth: 420).frame(maxWidth: .infinity)
                ForEach(Array(TP.g2.enumerated()), id: \.offset) { i, t in
                    HStack(alignment: .top, spacing: Espacio.s) {
                        DibujoPresion(i == 1 ? "presion_tilde" : "presion_cruz", alt: i == 1 ? TP.bien : TP.asiNo).frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            TextoPresion(t[0], fuente: .subheadline.weight(.semibold))
                            TextoPresion(t[1], fuente: .subheadline, secundario: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .tarjeta()
            LaminaPresion(dibujo: "presion_g4_colocar_manguito", alt: TP.g4Alt, textos: TP.g4)
            // Numerados corridos desde 1, igual en las tres plataformas (los números de adentro del dibujo son de su leyenda).
            PasosPresion(pasos: TP.como(brazo)).accessibilityIdentifier("presion-como-pasos")
        } pie: {
            Button(NP.empezar) { ir(EtapaPresion.previa) }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-empezar")
            Button(NP.volver) { ir(EtapaPresion.instrucciones) }.buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-como-volver")
        }
    }

    // MARK: Antes de medirte

    private static let clavesPrevias = ["cafeina", "fumo", "comida", "ejercicio"]

    private var previa: some View {
        PantallaPresion {
            TituloPresion(NP.previas)
            if tipo == "bajo_efecto" {
                VStack(alignment: .leading, spacing: Espacio.s) {
                    TextoPresion(NP.horaDosis)
                    DatePicker(NP.horaDosis, selection: $horaDosis, in: ...Date(), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .accessibilityIdentifier("presion-hora-dosis")
                    Divider()
                    FilaSiNoPresion(texto: NP.entrenoEntre, valor: entreno, id: "presion-entreno-entre") { entreno = $0 }
                }
                .tarjeta()
            } else {
                ForEach(Self.clavesPrevias, id: \.self) { k in
                    FilaSiNoPresion(texto: NP.previa[k] ?? k, valor: previas[k], id: "presion-previa-\(k)") { previas[k] = $0 }.tarjeta(relleno: 12)
                }
            }
        } pie: {
            if tipo == "bajo_efecto" {
                Button(NP.seguir) {
                    let hora = ISO8601DateFormatter().string(from: horaDosis)
                    modelo.cambiar { $0.sesion.dosisEstimulanteHora = hora; $0.sesion.entrenoEntreDosisYToma = entreno }
                    empezarReposo()
                }
                .buttonStyle(BotonPresion())
                .disabled(entreno == nil)
                .accessibilityIdentifier("presion-previa-seguir")
            } else {
                Button(NP.seguir) {
                    let p = Presion.Previo(cafeina: previas["cafeina"] == true, fumo: previas["fumo"] == true, comida: previas["comida"] == true, ejercicio: previas["ejercicio"] == true)
                    modelo.cambiar { $0.sesion.previo = p }
                    if p.alguno { ir(EtapaPresion.esperarMejor) } else { empezarReposo() }
                }
                .buttonStyle(BotonPresion())
                .disabled(previas.count < Self.clavesPrevias.count)
                .accessibilityIdentifier("presion-previa-seguir")
            }
        }
    }

    private var esperarMejor: some View {
        PantallaPresion {
            TextoPresion(NP.esperarMejor, fuente: .title3.weight(.semibold)).tarjeta().accessibilityIdentifier("presion-esperar-mejor")
        } pie: {
            Button(NP.esperar) { modelo.terminar(); alCerrar() }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-esperar")
            Button(NP.medirIgual) { empezarReposo() }.buttonStyle(BotonPresion(secundario: true)).accessibilityIdentifier("presion-medir-igual")
        }
    }

    // MARK: Reposo

    private var reposo: some View {
        ScrollView {
            VStack(spacing: Espacio.l) {
                TextoPresion(NP.reposo, fuente: .headline).accessibilityIdentifier("presion-reposo")
                if let fin = enCurso?.finTemporizador {
                    TemporizadorPresion(fin: fin, voz: NP.reposo) {
                        modelo.cambiar { $0.sesion.reposoCumplido = true; $0.sesion.temporizadorSalteado = false; $0.etapa = EtapaPresion.anotar; $0.finTemporizador = nil }
                        AccessibilityNotification.Announcement(NP.anotar).post()
                    }
                    .tarjeta()
                }
                Button(NP.saltear) {
                    modelo.cambiar { $0.sesion.reposoCumplido = false; $0.sesion.temporizadorSalteado = true; $0.etapa = EtapaPresion.anotar; $0.finTemporizador = nil }
                }
                .buttonStyle(BotonPresion(secundario: true))
                .accessibilityIdentifier("presion-saltear")
                BotonesFlujoPresion()
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
    }

    // MARK: Espera de la repetición

    private var espera: some View {
        let ev = modelo.evaluar()
        let conLista = ev?.paso == .repetirConLista
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                TextoPresion(ev?.texto == "repetir_pendiente" ? TP.repetirPendiente : TP.esperaTitulo, fuente: .headline).accessibilityIdentifier("presion-espera")
                if let fin = enCurso?.finTemporizador, !esperaTerminada {
                    TemporizadorPresion(fin: fin, voz: TP.esperaVoz) {
                        esperaTerminada = true
                        AccessibilityNotification.Announcement(NP.repetir).post()
                    }
                    .tarjeta()
                }
                if esperaTerminada || enCurso?.finTemporizador == nil {
                    Button(NP.repetir) { ir(EtapaPresion.anotar) }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-repetir-toma")
                }
                if conLista {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        TextoPresion(TP.esperaLista, fuente: .headline)
                        ListaAlarmaPresion(respuestas: enCurso?.lista ?? [:]) { c, si in
                            // Con un Sí, la guardia por síntomas en el acto, sin esperar la repetición.
                            if let r = modelo.responderLista(c, si), r.paso == .guardiaSintomas { ir(EtapaPresion.guardiaSintomas) }
                        }
                    }
                    .tarjeta()
                    .accessibilityIdentifier("presion-espera-sintomas")
                }
                BotonesFlujoPresion()
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .onAppear { esperaTerminada = (enCurso?.finTemporizador ?? .distantPast) <= Date() }
    }

    // MARK: Cierre

    /// Lo que sigue después de esta sesión, si la serie lo pide: la ortostática después de la toma sentado y la comparación de brazos.
    private var siguiente: String? {
        guard let e = enCurso, e.sesion.serieId != nil, let s = modelo.serieVista, s.id == e.sesion.serieId else { return nil }
        switch e.sesion.tipo {
        // La ortostática va después de la toma sentado.
        case "estandar", "bajo_efecto": return s.ortostatica != nil ? "ortostatica" : nil
        // La comparación de brazos va antes de la toma del día: al terminarla sigue la toma, si hoy todavía no la hizo.
        case "comparacion_brazos": return !s.dias.contains(modelo.hoy) && s.faltan > 0 ? s.tipo : nil
        default: return nil
        }
    }

    private func completo(_ ev: Presion.Evaluacion?) -> Bool {
        guard let e = enCurso, e.sesion.serieId != nil, let s = modelo.estado?.serie else { return false }
        if guiada || s.dias.contains(modelo.hoy) { return s.faltan == 0 }
        let vale = s.tipo == "bajo_efecto" ? ev?.validaBajoEfecto == true : ev?.cuenta == true
        return vale && s.faltan <= 1
    }

    private var listo: some View {
        let ev = modelo.evaluar()
        let sigue = siguiente
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                VStack(alignment: .leading, spacing: Espacio.s) {
                    if ev?.texto == "toma_no_cuenta" { TextoPresion(TP.noCuenta).accessibilityIdentifier("presion-no-cuenta") }
                    if ev?.texto == "sentate_agua" { TextoPresion(TP.sentateAgua).accessibilityIdentifier("presion-sentate-agua") }
                    if enCurso?.sesion.tomas.contains(where: \.latidoIrregular) == true { TextoPresion(TP.latidoIrregular).accessibilityIdentifier("presion-latido-irregular") }
                    if sigue == nil {
                        // En una toma suelta, «Anotado.»; en serie, el cierre del protocolo (si la toma no cuenta, ya lo dice arriba).
                        if tipo == "suelta" {
                            TextoPresion(NP.sintomaRecibido, fuente: .headline).accessibilityIdentifier("presion-listo")
                        } else if completo(ev) {
                            TextoPresion(TP.listoSerie, fuente: .headline).accessibilityIdentifier("presion-listo")
                        } else if ev?.texto != "toma_no_cuenta" {
                            TextoPresion(TP.como(brazo).last ?? "", fuente: .headline).accessibilityIdentifier("presion-listo")
                        }
                    } else if let ultima = enCurso?.sesion.tomas.last {
                        TextoPresion("\(ultima.sis)/\(ultima.dia)  \(NP.pulso) \(ultima.pulso)", fuente: .headline.monospacedDigit()).accessibilityIdentifier("presion-anotada")
                    }
                }
                .tarjeta()
                if let sigue {
                    Button(NP.seguir) {
                        let s = modelo.serieVista
                        if sigue == "ortostatica" {
                            modelo.empezar(tipo: sigue, serieId: s?.id, brazo: brazo, etapa: EtapaPresion.guiaIntro, variante: s?.ortostatica)
                        } else {
                            modelo.empezar(tipo: sigue, serieId: s?.id, brazo: s?.brazo, etapa: EtapaPresion.instrucciones)
                        }
                    }
                    .buttonStyle(BotonPresion())
                    .accessibilityIdentifier("presion-seguir")
                } else {
                    Button(NP.cerrar, action: cerrar).buttonStyle(BotonPresion()).accessibilityIdentifier("presion-cerrar")
                }
                BotonesFlujoPresion()
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .onAppear { CentroAvisos.shared.cancelarRepetirPresion() }
    }

    // MARK: Ortostática y comparación de brazos

    private func tituloPaso(anotando: Bool) -> String {
        guard let e = enCurso else { return "" }
        if tipo == "ortostatica" {
            if anotando, let m = pasoActual?.minutosDePie { return NP.minutoParado(m) }
            let t = TP.g6(sentado: sentadoParado)
            return t.indices.contains(e.paso) ? t[e.paso] : ""
        }
        return pasoActual?.brazo == "der" ? NP.brazoDer : NP.brazoIzq
    }

    private var guiaIntro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                if tipo == "ortostatica" {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        DibujoPresion(sentadoParado ? "presion_g6_ortostatica_sentado" : "presion_g6_ortostatica", alt: TP.g6Alt).frame(maxWidth: 420).frame(maxWidth: .infinity)
                        PasosPresion(pasos: TP.g6(sentado: sentadoParado), enTarjetas: false)
                        TextoPresion(TP.g6Antebrazo, fuente: .subheadline, secundario: true)
                        TextoPresion(TP.g6Mareo, fuente: .subheadline.weight(.semibold))
                    }
                    .tarjeta()
                    .accessibilityIdentifier("presion-ortostatica")
                    PasosPresion(pasos: TP.ortostatica(sentado: sentadoParado))
                } else {
                    VStack(alignment: .leading, spacing: Espacio.s) { ForEach(TP.brazos, id: \.self) { TextoPresion($0).tarjeta(relleno: 12) } }
                        .accessibilityIdentifier("presion-brazos")
                }
                Button(NP.empezar) {
                    let s = pasos.first?.esperaS ?? Presion.reposoS
                    modelo.cambiar { $0.paso = 0; $0.etapa = EtapaPresion.guiaEspera; $0.finTemporizador = Date().addingTimeInterval(TiemposPresion.segundos(s)) }
                }
                .buttonStyle(BotonPresion())
                .accessibilityIdentifier("presion-empezar")
                BotonesFlujoPresion()
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
    }

    private var guiaEspera: some View {
        let titulo = tituloPaso(anotando: false)
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.l) {
                TituloPresion(titulo).accessibilityIdentifier("presion-guia-titulo")
                if let fin = enCurso?.finTemporizador {
                    TemporizadorPresion(fin: fin, voz: titulo) {
                        modelo.cambiar { $0.etapa = EtapaPresion.guiaAnotar; $0.finTemporizador = nil }
                        AccessibilityNotification.Announcement(NP.anotar).post()
                    }
                    .tarjeta()
                }
                if tipo == "ortostatica" { botonMareo }
                BotonesFlujoPresion()
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
    }

    private var botonMareo: some View {
        Button(NP.meMaree) {
            // Marcarlo nunca depende de haber medido: sin ninguna toma viaja además como síntoma suelto. La regla decide: con
            // un pulso de urgencia, guardia.
            if modelo.meMaree()?.paso == .guardiaSintomas { ir(EtapaPresion.guardiaSintomas) } else { ir(EtapaPresion.mareo) }
        }
        .buttonStyle(BotonPresion(secundario: true))
        .accessibilityIdentifier("presion-me-maree")
    }

    /// La hoja de síntomas de después de la toma: la toma ya está guardada.
    private var hojaSintomas: some View {
        PantallaPresion {
            TituloPresion(TP.marcarSintoma).accessibilityIdentifier("presion-sintomas-hoja")
            SelectorSintomasPresion(seleccion: $sintomasHoja)
        } pie: {
            Button(NP.seguir) { responderHoja() }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-sintomas-seguir")
        }
    }

    private var mareo: some View {
        PantallaPresion {
            TextoPresion(TP.mareoOrtostatica, fuente: .headline).tarjeta().accessibilityIdentifier("presion-mareo")
        } pie: {
            Button(NP.cerrar, action: cerrar).buttonStyle(BotonPresion()).accessibilityIdentifier("presion-cerrar")
        }
    }
}
