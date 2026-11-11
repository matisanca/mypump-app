import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// El check guiado: el check de la semana, un paso por pantalla. Arriba dice en qué paso va; abajo hay un solo botón
/// grande que avanza. Cada cambio queda guardado en el teléfono (`ModeloRevision.guardarBorrador`): si sale, vuelve donde
/// estaba. Al final manda lo de siempre por donde siempre (`ModeloRevision.enviarGuiado`).
struct CheckGuiadoFlujo: View {
    let revision: ModeloRevision
    let fotos: ModeloFotos?
    let saludSemana: [SaludSemana.Fila]
    let sincronizarSalud: (() -> Void)?

    @Environment(\.dismiss) private var cerrar
    @State private var borrador: CheckGuiado.Borrador
    @State private var pasos: [CheckGuiado.Paso]
    @State private var paso: CheckGuiado.Paso
    @State private var yaEnviado: Bool
    /// El alumno tocó algo: recién ahí se guarda el borrador (abrir y salir no deja nada «a medias»).
    @State private var tocado = false
    @State private var aviso: String?
    @State private var listo = false
    @State private var trabajando = false
    @State private var envios = 0
    @FocusState private var escribiendo: Bool

    init(revision: ModeloRevision, fotos: ModeloFotos?, saludSemana: [SaludSemana.Fila], sincronizarSalud: (() -> Void)?,
         pasoInicial: CheckGuiado.Paso? = nil) {
        self.revision = revision; self.fotos = fotos; self.saludSemana = saludSemana; self.sincronizarSalud = sincronizarSalud
        var b = revision.abrirGuiado()
        let pasos = CheckGuiado.pasos(faltanFotos: (fotos?.posesDeLaSemana.count ?? 3) < 3)
        // El peso de hoy, si ya está cargado, viene puesto.
        if b.peso.isEmpty, let hoy = revision.pesoDeHoy { b.peso = PesoCorporal.kg(hoy) }
        _borrador = State(initialValue: b)
        _pasos = State(initialValue: pasos)
        _paso = State(initialValue: pasoInicial.flatMap { pasos.contains($0) ? $0 : nil } ?? CheckGuiado.retomar(b, pasos: pasos))
        _yaEnviado = State(initialValue: revision.checkinEnviado)
    }

    private var indice: Int { pasos.firstIndex(of: paso) ?? 0 }
    private var fotosHechas: Int { fotos?.posesDeLaSemana.count ?? 0 }
    private var catalogo: CheckGuiado.Catalogo { borrador.catalogo }

    var body: some View {
        VStack(spacing: 0) {
            if listo {
                pantallaListo
            } else {
                cabecera
                ScrollView {
                    VStack(alignment: .leading, spacing: Espacio.l) {
                        VStack(alignment: .leading, spacing: Espacio.xs) {
                            Text(CheckGuiado.titulo(paso, catalogo: catalogo))
                                .font(.tituloCheck)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("cg-titulo")
                            Text(CheckGuiado.apoyo(paso, catalogo: catalogo))
                                .font(.body)
                                .foregroundStyle(Color.apoyoCheck)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        contenido
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, Espacio.m)
                    .padding(.bottom, Espacio.l)
                    .frame(maxWidth: Ancho.lectura, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                pie
            }
        }
        .background(Color.fondo.ignoresSafeArea())
        .animation(.snappy(duration: 0.22), value: paso)
        .animation(.snappy, value: listo)
        .onChange(of: borrador) { _, _ in guardar() }
        .onChange(of: paso) { _, _ in aviso = nil; escribiendo = false; guardar() }
        // Semana nueva con el check abierto: lo contestado era de la semana anterior.
        .onChange(of: revision.semana) { _, _ in cerrar() }
        .sensoryFeedback(.success, trigger: envios)
    }

    private func guardar() {
        guard tocado, !listo else { return }
        var b = borrador
        b.paso = paso
        revision.guardarBorrador(b)
    }

    // MARK: - Arriba y abajo

    private var cabecera: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            HStack {
                if indice > 0 {
                    Button { paso = pasos[indice - 1] } label: {
                        Label("Atrás", systemImage: "chevron.left").labelStyle(EtiquetaCompacta())
                    }
                    .buttonStyle(BotonCabeceraCheck())
                    .accessibilityIdentifier("cg-atras")
                }
                Spacer(minLength: Espacio.xs)
                Button { guardar(); cerrar() } label: {
                    Label("Salir", systemImage: "xmark").labelStyle(EtiquetaCompacta())
                }
                .buttonStyle(BotonCabeceraCheck())
                .accessibilityHint("Guarda lo que llevás y vuelve a Revisión")
                .accessibilityIdentifier("cg-cerrar")
            }
            Text("Paso \(indice + 1) de \(pasos.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.apoyoCheck)
                .accessibilityIdentifier("cg-avance")
            AvanceCheck(total: pasos.count, hechos: indice + 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, Espacio.xs)
        .padding(.bottom, Espacio.s)
    }

    private var pie: some View {
        let falta = paso == .resumen ? CheckGuiado.faltaParaEnviar(borrador) : nil
        let faltanEscalas = paso == .escalas && borrador.valores.values.contains { $0 > 0 } ? CheckinSemanal.faltan(borrador.valores) : nil
        return VStack(spacing: Espacio.xxs) {
            if let texto = aviso ?? falta ?? faltanEscalas {
                Text(texto)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(aviso != nil ? Color.alerta : Color.apoyoCheck)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, Espacio.xs)
                    .accessibilityIdentifier("cg-falta")
            }
            if paso == .resumen {
                Button(yaEnviado ? "Actualizar mi check" : "Enviar mi check") { enviar() }
                    .buttonStyle(BotonCheck())
                    .disabled(trabajando)
                    .accessibilityIdentifier("cg-enviar")
            } else {
                Button("Seguir") { seguir() }
                    .buttonStyle(BotonCheck())
                    .disabled(trabajando || !CheckGuiado.puedeSeguir(paso, borrador, fotosHechas: fotosHechas))
                    .accessibilityIdentifier("cg-seguir")
            }
            if let omitir = CheckGuiado.omitir(paso) {
                Button(omitir) {
                    if paso == .peso { tocado = true; borrador.peso = "" }
                    avanzar()
                }
                .buttonStyle(BotonCheckDiscreto())
                .accessibilityIdentifier("cg-omitir")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, Espacio.s)
        .padding(.bottom, Espacio.xs)
        .frame(maxWidth: Ancho.lectura)
        .frame(maxWidth: .infinity)
        .background(Color.fondo)
    }

    private func avanzar() {
        guard indice + 1 < pasos.count else { return }
        paso = pasos[indice + 1]
    }

    private func seguir() {
        // Un efecto marcado sin decir cuánto molesta: no avanza y lo dice.
        if paso == .senales, CheckGuiado.faltaIntensidad(borrador) { aviso = CheckGuiado.avisoIntensidad; return }
        guard paso == .peso else { avanzar(); return }
        // El peso se guarda en el momento, por la misma cola que la tarjeta de peso.
        trabajando = true
        Task {
            let ok = await revision.guardarPesoGuiado(borrador.peso)
            trabajando = false
            if ok { avanzar() } else { aviso = PesoCorporal.avisoRango }
        }
    }

    private func enviar() {
        if let falta = CheckGuiado.pasoQueFalta(borrador) { paso = falta; return }
        trabajando = true
        Task {
            if let falta = await revision.enviarGuiado(borrador) {
                aviso = falta
            } else {
                sincronizarSalud?()
                envios += 1
                listo = true
            }
            trabajando = false
        }
    }

    // MARK: - Los pasos

    @ViewBuilder private var contenido: some View {
        switch paso {
        case .peso: pasoPeso
        case .escalas: pasoEscalas
        case .fotos: FotosSemana(modelo: fotos, muestras: [], peso: [], soloMarcos: true)
        case .senales: pasoSenales
        case .nota: pasoNota
        case .resumen: pasoResumen
        }
    }

    private var pasoPeso: some View {
        let media = PesoCorporal.media(revision.serieDePeso, hasta: revision.fecha, dias: 7)
        return VStack(spacing: Espacio.m) {
            HStack(alignment: .firstTextBaseline, spacing: Espacio.xs) {
                TextField("78,4", text: Binding(get: { borrador.peso }, set: { tocado = true; aviso = nil; borrador.peso = $0 }))
                    .font(.pesoCheck)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .focused($escribiendo)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Tu peso de hoy, en kilos")
                    .accessibilityIdentifier("cg-peso")
                Text("kg").font(.title2.weight(.semibold)).foregroundStyle(Color.apoyoCheck)
            }
            .padding(.vertical, Espacio.m)
            .frame(maxWidth: .infinity)
            .background(Color.tarjeta, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .contentShape(.rect)
            .onTapGesture { escribiendo = true }
            if let media {
                Text("Media de 7 días: \(PesoCorporal.kg(media)) kg")
                    .font(.subheadline)
                    .foregroundStyle(Color.apoyoCheck)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var pasoEscalas: some View {
        VStack(alignment: .leading, spacing: Espacio.l) {
            ForEach(CheckinSemanal.metricas, id: \.clave) { m in
                EscalaCheck(metrica: m, valor: Binding(get: { borrador.valores[m.clave] }, set: {
                    tocado = true
                    borrador.valores[m.clave] = $0
                }))
            }
        }
    }

    /// Las del catálogo que le tocan, más cualquier digestiva que ya venía marcada (si dejó de usar un GLP-1 a mitad de
    /// semana tiene que poder verla para sacarla o decir cuánto molesta).
    private var opcionesVisibles: [CheckGuiado.Opcion] {
        let visibles = CheckGuiado.opciones(catalogo, glp1: revision.glp1Guiado).map(\.clave)
        return CheckGuiado.opciones(catalogo).filter { visibles.contains($0.clave) || borrador.senales.contains($0.clave) }
    }

    private var pasoSenales: some View {
        VStack(spacing: Espacio.xs) {
            ForEach(opcionesVisibles, id: \.clave) { o in
                let elegida = borrador.senales.contains(o.clave)
                Button {
                    tocado = true
                    withAnimation(.snappy(duration: 0.18)) {
                        borrador.senales = CheckGuiado.alternar(borrador.senales, o.clave)
                        // Al desmarcar (o con «Nada de esto») su intensidad se va con él.
                        borrador.intensidades = CheckGuiado.normalizarIntensidades(borrador.senales, borrador.intensidades, catalogo)
                    }
                    if !CheckGuiado.faltaIntensidad(borrador) { aviso = nil }
                } label: {
                    HStack(spacing: Espacio.s) {
                        Text(o.etiqueta)
                            .font(.body.weight(elegida ? .semibold : .regular))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Espacio.xs)
                        Image(systemName: elegida ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(elegida ? Color.marcaTexto : Color.rielCheck)
                    }
                    .padding(.horizontal, Espacio.m)
                    .padding(.vertical, Espacio.s)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .background(elegida ? Color.marcaSuave : Color.tarjeta, in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radio.control + 4, style: .continuous)
                            .strokeBorder(elegida ? Color.marcaTexto : Color.borde, lineWidth: elegida ? 2 : 1)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(elegida ? .isSelected : [])
                .accessibilityIdentifier("cg-senal-\(o.clave)")
                if elegida, o.clave != CheckGuiado.ninguno, CheckGuiado.llevaIntensidad(catalogo) { intensidad(de: o) }
            }
        }
        .sensoryFeedback(.selection, trigger: borrador.senales)
        .sensoryFeedback(.selection, trigger: borrador.intensidades)
    }

    /// «¿Cuánto te molesta?» debajo del efecto marcado: tres botones con texto, uno al lado del otro si entran y apilados
    /// con letra grande.
    private func intensidad(de o: CheckGuiado.Opcion) -> some View {
        let botones = ForEach(CheckGuiado.intensidades, id: \.clave) { i in
            let elegida = borrador.intensidades[o.clave] == i.clave
            Button {
                tocado = true
                borrador.intensidades[o.clave] = i.clave
                if !CheckGuiado.faltaIntensidad(borrador) { aviso = nil }
            } label: {
                Text(i.etiqueta)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(elegida ? Color.sobreMarca : Color.primary)
                    .lineLimit(1)
                    .padding(.horizontal, Espacio.xs)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(elegida ? Color.marca : Color.tarjeta, in: .rect(cornerRadius: Radio.control, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radio.control, style: .continuous)
                            .strokeBorder(elegida ? Color.marca : Color.borde, lineWidth: 1)
                    }
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(o.etiqueta): \(i.etiqueta)")
            .accessibilityAddTraits(elegida ? .isSelected : [])
            .accessibilityIdentifier("cg-intensidad-\(o.clave)-\(i.clave)")
        }
        return VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(CheckGuiado.preguntaIntensidad)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.apoyoCheck)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Espacio.xs) { botones }
                VStack(spacing: Espacio.xs) { botones }
            }
        }
        .padding(.leading, Espacio.m)
        .padding(.bottom, Espacio.xs)
        .transition(.opacity)
    }

    private var pasoNota: some View {
        TextField("Escribí acá (opcional)", text: Binding(get: { borrador.nota }, set: { tocado = true; borrador.nota = $0 }), axis: .vertical)
            .lineLimit(4...10)
            .font(.body)
            .focused($escribiendo)
            .padding(Espacio.m)
            .frame(minHeight: 140, alignment: .topLeading)
            .background(Color.tarjeta, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).strokeBorder(Color.borde, lineWidth: 1) }
            .contentShape(.rect)
            .onTapGesture { escribiendo = true }
            .accessibilityIdentifier("cg-nota")
    }

    private var pasoResumen: some View {
        let peso = borrador.peso.trimmingCharacters(in: .whitespaces)
        let marcado = CheckGuiado.textoSenales(borrador.senales, catalogo, intensidades: borrador.intensidades)
        let nota = borrador.nota.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: Espacio.l) {
            VStack(spacing: 0) {
                FilaResumenCheck(titulo: "Peso", valor: peso.isEmpty ? "Sin cargar" : "\(peso) kg", falta: false, id: "cg-fila-peso") { paso = .peso }
                ForEach(Array(CheckinSemanal.metricas.enumerated()), id: \.element.clave) { i, m in
                    Divider()
                    let v = borrador.valores[m.clave] ?? 0
                    FilaResumenCheck(titulo: m.etiqueta, valor: v > 0 ? "\(v) de 5" : "Falta", falta: v == 0,
                                     id: i == 0 ? "cg-fila-escalas" : "cg-fila-escalas-\(m.clave)") { paso = .escalas }
                }
                Divider()
                FilaResumenCheck(titulo: "Fotos", valor: "\(fotosHechas) de 3", falta: false, id: "cg-fila-fotos",
                                 accion: pasos.contains(.fotos) ? { paso = .fotos } : nil)
                Divider()
                FilaResumenCheck(titulo: CheckGuiado.titulo(.senales, catalogo: catalogo), valor: marcado.isEmpty ? "Falta" : marcado,
                                 falta: marcado.isEmpty, larga: true, id: "cg-fila-senales") { paso = .senales }
                Divider()
                FilaResumenCheck(titulo: "Nota", valor: nota.isEmpty ? "Sin nota" : nota, falta: false, larga: !nota.isEmpty, id: "cg-fila-nota") { paso = .nota }
            }
            .padding(.horizontal, Espacio.m)
            .background(Color.tarjeta, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous).strokeBorder(Color.borde, lineWidth: 1) }
            if !saludSemana.isEmpty { SaludSemanaBloque(filas: saludSemana) }
        }
    }

    private var pantallaListo: some View {
        VStack(spacing: Espacio.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84, weight: .bold))
                .foregroundStyle(Color.marca)
                .accessibilityHidden(true)
            VStack(spacing: Espacio.xs) {
                Text("Listo").font(.tituloCheck).accessibilityAddTraits(.isHeader)
                Text("Mati lo ve antes de tu devolución.")
                    .font(.body)
                    .foregroundStyle(Color.apoyoCheck)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cg-listo")
            Spacer()
            Button("Cerrar") { cerrar() }
                .buttonStyle(BotonCheck())
                .accessibilityIdentifier("cg-cerrar-listo")
        }
        .padding(20)
        .frame(maxWidth: Ancho.lectura)
        .frame(maxWidth: .infinity)
    }
}

/// «Atrás» y «Salir»: con texto, en cápsula gris, zona de 44.
private struct BotonCabeceraCheck: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.campo, in: .capsule)
            .contentShape(.capsule)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Una escala de 1 a 5: cinco círculos grandes; el elegido, en verde lleno. Los extremos, rotulados.
private struct EscalaCheck: View {
    let metrica: CheckinSemanal.Metrica
    @Binding var valor: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Text(metrica.etiqueta).font(.headline)
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { n in
                    let elegido = valor == n
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { valor = elegido ? nil : n }
                    } label: {
                        Text("\(n)")
                            .font(.datoCheck)
                            .foregroundStyle(elegido ? Color.sobreMarca : Color.primary)
                            .frame(width: 52, height: 52)
                            .background(elegido ? Color.marca : Color.tarjeta, in: .circle)
                            .overlay { Circle().strokeBorder(elegido ? Color.clear : Color.borde, lineWidth: 1) }
                            .scaleEffect(elegido ? 1.06 : 1)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(metrica.etiqueta): \(n) de 5")
                    .accessibilityAddTraits(elegido ? .isSelected : [])
                    .accessibilityIdentifier("cg-escala-\(metrica.clave)-\(n)")
                }
            }
            HStack {
                Text("1 · \(metrica.bajo)")
                Spacer()
                Text("5 · \(metrica.alto)")
            }
            .font(.footnote)
            .foregroundStyle(Color.apoyoCheck)
            .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: valor)
    }
}

/// Una fila del resumen: el dato y adónde tocar para cambiarlo. Lo largo (lo marcado, la nota) va debajo del rótulo.
private struct FilaResumenCheck: View {
    let titulo: String
    let valor: String
    let falta: Bool
    var larga = false
    let id: String
    var accion: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    var body: some View {
        Button { accion?() } label: {
            HStack(spacing: Espacio.s) {
                if larga || tamañoLetra.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { rotulo; dato.multilineTextAlignment(.leading) }
                    Spacer(minLength: 0)
                } else {
                    rotulo
                    Spacer(minLength: Espacio.xs)
                    dato.multilineTextAlignment(.trailing)
                }
                if accion != nil {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.apoyoCheck).accessibilityHidden(true)
                }
            }
            .padding(.vertical, Espacio.s)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(accion == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(accion == nil ? "" : "Tocá para cambiarlo")
        .accessibilityIdentifier(id)
    }

    private var rotulo: some View {
        Text(titulo).font(.body).foregroundStyle(Color.apoyoCheck).fixedSize(horizontal: false, vertical: true)
    }
    private var dato: some View {
        Text(valor)
            .font(.body.weight(.semibold))
            .foregroundStyle(falta ? Color.alerta : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
