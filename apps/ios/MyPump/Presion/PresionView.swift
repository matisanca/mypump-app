import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// «Presión arterial» en Mis datos (`presion/CONTRATO_APP.md`). Con la palanca `presion_app` apagada o sin el servidor nuevo, la
/// fila no existe y esto no se abre.
///
/// El alumno ve sus pasos, sus temporizadores, sus tomas tal como las anotó y el avance. No ve promedios, categorías ni colores
/// de riesgo. Y nada de acá toca Entreno ni la rutina: la presión nunca frena el entrenamiento.
struct PresionRaiz: View {
    let modelo: ModeloPresion
    /// Desde la tarjeta de arriba o un aviso: se abre directo en lo que toca (la repetición, preparar o la toma de hoy).
    var directo = false
    let alCerrar: () -> Void

    private enum Destino: Hashable { case aparato }
    @State private var directoHecho = false
    @State private var camino: [Destino] = []
    @State private var flujo = false
    @State private var sintoma = false
    @State private var guardia = false
    /// Las respuestas de la lista del recordatorio (una repetición de 180/120 que quedó sin hacer).
    @State private var recordatorio: [String: Bool] = [:]
    @State private var recordatorioMandado = false
    @State private var verLista = false

    var body: some View {
        NavigationStack(path: $camino) {
            Group {
                if let e = modelo.estado {
                    if e.aparato == nil {
                        AparatoPresionView(modelo: modelo, modo: .primera, alMarcarSintoma: { sintoma = true })
                    } else {
                        inicio(e)
                    }
                } else {
                    Color.fondo
                }
            }
            .background(Color.fondo)
            .navigationTitle(NP.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NP.cerrar, action: alCerrar).accessibilityIdentifier("presion-cerrar-seccion") } }
            .navigationDestination(for: Destino.self) { _ in
                AparatoPresionView(modelo: modelo, modo: .cambiar, alGuardar: { camino = [] })
                    .navigationTitle(NP.aparato)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await modelo.refrescar(); modelo.drenarEnFondo() }
        .task {
            guard directo, !directoHecho else { return }
            directoHecho = true
            // Que la hoja termine de subir: presentar otra pantalla encima a mitad de la animación se pierde.
            try? await Task.sleep(for: .milliseconds(500))
            irALoQueToca()
        }
        // Con algo abierto no se cierra sola: el texto de guardia se queda aunque el servidor apague la sección.
        .onChange(of: modelo.habilitado) { _, si in if !si && !flujo && !guardia && !sintoma { alCerrar() } }
        .fullScreenCover(isPresented: $flujo) { TomaPresionView(modelo: modelo, alCerrar: { flujo = false }) }
        .sheet(isPresented: $sintoma) { MarcarSintomaPresion(modelo: modelo, alCerrar: { sintoma = false }).presentationDragIndicator(.visible) }
        .fullScreenCover(isPresented: $guardia) {
            NavigationStack {
                GuardiaPresion(porSintomas: true, alCerrar: { guardia = false })
                    .navigationTitle(NP.titulo)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: Inicio

    private var pendiente: PendientePresion? { modelo.pendiente }

    /// Lo que la tarjeta o el aviso prometieron: sin pasar por la pantalla de inicio.
    private func irALoQueToca() {
        guard !flujo, !sintoma, !guardia, let e = modelo.estado else { return }
        switch modelo.tarjeta {
        case .repetir:
            if let p = pendiente { repetir(p) }
        case .preparar:
            // Sin aparato ya se está en «Antes de la primera serie». Con reloj, a cambiar el aparato. Si falta medir, la toma lo pide.
            if e.aparato == nil { return }
            if !Presion.metodo(e.circunferenciaBrazoCm, e.aparato).admiteTomas { camino = [.aparato] } else { empezar(e) }
        case .toma:
            empezar(e)
        case .hoyListo, nil:
            break
        }
    }

    private func inicio(_ e: EstadoPresion) -> some View {
        let m = Presion.metodo(e.circunferenciaBrazoCm, e.aparato)
        let p = pendiente
        return ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                if let s = modelo.serieVista { avance(s) }
                if !m.admiteTomas {
                    TextoPresion(NP.relojNoSirve, fuente: .headline).tarjeta().accessibilityIdentifier("presion-reloj-no-sirve")
                } else if let p {
                    bloquePendiente(p)
                } else if modelo.hoyListo {
                    TextoPresion(NP.hoyListo, fuente: .headline).tarjeta().accessibilityIdentifier("presion-hoy-listo")
                } else {
                    Button(e.serie == nil || (modelo.serieVista?.faltan ?? 0) <= 0 ? NP.tomaSuelta : NP.tomaDeHoy) { empezar(e) }
                        .buttonStyle(BotonPresion())
                        .accessibilityIdentifier("presion-toma")
                }
                avisosAparato(e, m)
                Button(TP.marcarSintoma) { sintoma = true }
                    .buttonStyle(BotonPresion(secundario: true))
                    .accessibilityIdentifier("presion-marcar-sintoma")
                if modelo.enCola > 0 { TextoPresion(NP.sinSenal, fuente: .footnote, secundario: true).accessibilityIdentifier("presion-sin-senal") }
                tusTomas(e)
                filaAparato(e)
            }
            .padding(Espacio.m)
            .anchoLectura()
        }
        .accessibilityIdentifier("presion-inicio")
    }

    /// Un círculo por toma. Sin promedios ni colores de riesgo: lleno o vacío.
    private func avance(_ s: SeriePresion) -> some View {
        let hechas = min(s.tomasObjetivo, max(0, s.tomasObjetivo - s.faltan))
        return VStack(alignment: .leading, spacing: Espacio.s) {
            HStack(spacing: Espacio.s) {
                ForEach(0..<s.tomasObjetivo, id: \.self) { i in
                    ZStack {
                        Circle().fill(i < hechas ? Color.marcaVivo : Color.clear)
                        Circle().strokeBorder(i < hechas ? Color.marcaVivo : Color.secondary, lineWidth: 2)
                        if i < hechas { Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Color.sobreMarca) }
                        // La toma que lleva ortostática: un ícono chico de persona parada.
                        else if i == hechas, s.ortostatica != nil { Image(systemName: "figure.stand").font(.footnote).foregroundStyle(.secondary) }
                    }
                    .frame(width: 32, height: 32)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(TP.avanceAlt(hechas, s.tomasObjetivo))
            .accessibilityIdentifier("presion-avance")
            TextoPresion(s.faltan == 0 ? TP.listoSerieCorto : TP.faltan(s.faltan), fuente: .headline).accessibilityIdentifier("presion-avance-texto")
        }
        .tarjeta()
    }

    private func bloquePendiente(_ p: PendientePresion) -> some View {
        VStack(alignment: .leading, spacing: Espacio.m) {
            TextoPresion(TP.repetirPendiente, fuente: .headline).accessibilityIdentifier("presion-pendiente")
            if p.nivel == "urgencia" {
                TextoPresion(TP.esperaLista)
                ListaAlarmaPresion(respuestas: recordatorio) { c, si in responderRecordatorio(p, c, si) }
            }
            Button(NP.repetir) { repetir(p) }.buttonStyle(BotonPresion()).accessibilityIdentifier("presion-repetir")
        }
        .tarjeta()
    }

    @ViewBuilder private func avisosAparato(_ e: EstadoPresion, _ m: Presion.Metodo) -> some View {
        // La segunda línea habla de una lista: sin la lista verificada no se muestra, ni «Ver cuáles sirven».
        let conLista = e.tensiometros != nil
        let textos: [String] = m.metodo == "muneca_provisoria" ? (conLista ? TP.muneca : [TP.muneca[0]])
            : m.metodo == "muneca_habitual" && m.pedirValidado ? (conLista ? [TP.munecaNoValidada] : [])
            : m.metodo == "brazo" && m.pedirValidado ? (conLista ? TP.noValidado : [TP.noValidado[0]]) : []
        if !textos.isEmpty {
            VStack(alignment: .leading, spacing: Espacio.s) {
                ForEach(textos, id: \.self) { TextoPresion($0) }
                if let l = e.tensiometros, let t = Presion.tramoBrazo(e.circunferenciaBrazoCm), t != "menos_22" {
                    Button(TP.verCuales) { verLista = true }
                        .buttonStyle(BotonPresion(secundario: true))
                        .accessibilityIdentifier("presion-ver-cuales")
                        .sheet(isPresented: $verLista) { ListaTensiometrosPresion(lista: l, tramo: t, alCerrar: { verLista = false }) }
                }
            }
            .tarjeta()
            .accessibilityIdentifier("presion-aviso-aparato")
        }
    }

    private func tusTomas(_ e: EstadoPresion) -> some View {
        let conTomas = e.sesiones.filter { !$0.tomas.isEmpty }
        return VStack(alignment: .leading, spacing: Espacio.s) {
            TituloPresion(NP.tusTomas)
            if conTomas.isEmpty {
                TextoPresion(NP.sinTomas, secundario: true).accessibilityIdentifier("presion-sin-tomas")
            } else {
                // El gráfico, con 2 tomas o más; con 1, solo la lista.
                if conTomas.reduce(0, { $0 + $1.tomas.count }) >= 2 { GraficoPresion(sesiones: conTomas) }
                ListaTomasPresion(sesiones: conTomas)
            }
        }
        .tarjeta()
    }

    private func filaAparato(_ e: EstadoPresion) -> some View {
        let a = e.aparato
        let nombre = [a?.marca, a?.modelo].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: Espacio.xs) {
            TituloPresion(NP.aparato)
            TextoPresion(NP.tipos[a?.tipo ?? ""] ?? "")
            if !nombre.isEmpty { TextoPresion(nombre, fuente: .subheadline, secundario: true) }
            if let cm = e.circunferenciaBrazoCm { TextoPresion("\(NP.brazo) \(NumeroPresion.texto(cm)) \(NP.cm)", fuente: .subheadline, secundario: true) }
            Button(NP.cambiarAparato) { camino = [.aparato] }
                .buttonStyle(BotonPresion(secundario: true))
                .accessibilityIdentifier("presion-cambiar-aparato")
        }
        .tarjeta()
        .accessibilityIdentifier("presion-aparato")
    }

    // MARK: Acciones

    private func empezar(_ e: EstadoPresion) {
        // Con la serie completa y todavía abierta, lo que se anota es una toma suelta.
        let s = modelo.serieVista.flatMap { $0.faltan > 0 ? $0 : nil }
        if let s, s.compararBrazos, !s.medidaPedida {
            // La comparación de brazos va antes de la toma del día (si falta medir el brazo, primero eso: `trasMedir`).
            modelo.empezar(tipo: "comparacion_brazos", serieId: s.id, brazo: s.brazo, etapa: EtapaPresion.guiaIntro)
        } else {
            modelo.empezar(tipo: s?.tipo ?? "suelta", serieId: s?.id, brazo: s?.brazo, etapa: s?.medidaPedida == true ? EtapaPresion.medir : EtapaPresion.instrucciones)
        }
        flujo = true
    }

    private func repetir(_ p: PendientePresion) {
        if let e = modelo.enCurso, e.sesion.id == p.sesionId {
            // Si la espera sigue corriendo, vuelve a la espera; si ya pasó, directo a anotar.
            modelo.cambiar {
                if let f = $0.finTemporizador, f > Date() { $0.etapa = EtapaPresion.espera } else { $0.etapa = EtapaPresion.anotar; $0.finTemporizador = nil }
            }
            flujo = true
        } else {
            // Sin la sesión guardada se refresca primero; si el servidor tampoco la tiene, es una toma nueva normal.
            Task {
                if await modelo.retomar(p, etapa: EtapaPresion.anotar) != nil { flujo = true }
                else if let e = modelo.estado, !flujo { empezar(e) }
            }
        }
    }

    /// La lista del recordatorio viaja como síntoma. Con un Sí, guardia por síntomas en el acto. Sin contestar todo no cuenta como «no».
    private func responderRecordatorio(_ p: PendientePresion, _ codigo: String, _ si: Bool) {
        recordatorio[codigo] = si
        if si {
            modelo.marcarSintoma(codigos: Presion.alarma.filter { recordatorio[$0] == true }, nota: nil, contexto: "recordatorio_180_120", sesionId: p.sesionId, sinSintomasEnLista: false)
            guardia = true
        } else if !recordatorioMandado, Presion.alarma.allSatisfy({ recordatorio[$0] == false }) {
            recordatorioMandado = true
            modelo.marcarSintoma(codigos: [], nota: nil, contexto: "recordatorio_180_120", sesionId: p.sesionId, sinSintomasEnLista: true)
        }
    }
}

/// «Marcar un síntoma»: siempre a mano, haya o no una sesión en curso. Medir nunca es condición para marcarlo.
struct MarcarSintomaPresion: View {
    let modelo: ModeloPresion
    let alCerrar: () -> Void

    private enum Resultado { case guardia, anotado }
    @State private var seleccion: Set<String> = []
    @State private var nota = ""
    @State private var resultado: Resultado?

    var body: some View {
        NavigationStack {
            Group {
                switch resultado {
                case .guardia:
                    GuardiaPresion(porSintomas: true, alCerrar: alCerrar)
                case .anotado:
                    PantallaPresion {
                        TextoPresion(NP.sintomaRecibido, fuente: .headline).tarjeta().accessibilityIdentifier("presion-sintoma-recibido")
                    } pie: {
                        Button(NP.cerrar, action: alCerrar).buttonStyle(BotonPresion()).accessibilityIdentifier("presion-sintoma-cerrar")
                    }
                case nil:
                    PantallaPresion {
                        SelectorSintomasPresion(seleccion: $seleccion)
                        TextField(NP.nota, text: $nota, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(Espacio.s)
                            .frame(minHeight: 56)
                            .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                            .accessibilityIdentifier("presion-sintoma-nota")
                    } pie: {
                        Button(NP.enviar) { enviar() }
                            .buttonStyle(BotonPresion())
                            .disabled(seleccion.isEmpty && nota.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("presion-sintoma-enviar")
                    }
                }
            }
            .background(Color.fondo)
            .navigationTitle(TP.marcarSintoma)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(NP.cerrar, action: alCerrar) } }
        }
    }

    private func enviar() {
        // En el orden de las listas, no en el que los tocó.
        let codigos = (Presion.alarma + Presion.otros).filter(seleccion.contains)
        // Con una sesión abierta que ya tiene tomas, el síntoma también se suma a ella y la regla decide (`marcarSintomaBoton`).
        let abierta = modelo.enCurso?.abiertaASintomas == true
        let guardia = modelo.marcarSintomaBoton(codigos: codigos, nota: nota, sumarASesion: abierta)
        if guardia, abierta, modelo.enCurso?.sesion.tomas.isEmpty == false, modelo.evaluar()?.paso == .guardiaSintomas {
            // La toma en curso también pasa a la guardia.
            modelo.cambiar { $0.etapa = EtapaPresion.guardiaSintomas; $0.finTemporizador = nil }
        }
        resultado = guardia ? .guardia : .anotado
    }
}
