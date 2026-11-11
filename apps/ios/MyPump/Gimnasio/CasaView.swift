import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosColaB.Casa

/// «Entreno en casa» (2.3.0, palanca `casa`): el interruptor de arriba de «Tu gimnasio». Prendido, la carga pasa a ser lo
/// que tiene en su casa (una lista para marcar, sin fotos). Reemplaza la pregunta de material en casa del formulario.
struct InterruptorCasa: View {
    let casa: ModeloCasa
    let gimnasio: ModeloGimnasio
    /// Sin la bajada (fijo arriba de las zonas, con la letra muy grande).
    var compacto = false
    /// Lo que se acaba de pedir, mientras contesta el servidor (para que el interruptor no rebote).
    @State private var pedido: Bool?
    @State private var error = false
    @State private var app = Proveedor.modelo

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.xs) {
            Toggle(isOn: Binding(get: { pedido ?? casa.prendido }, set: { cambiar($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(T.interruptor).font(.headline)
                    if !compacto || casa.fijo { Text(casa.fijo ? T.fijo : T.interruptorBajada).font(.subheadline).foregroundStyle(.secondary) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .tint(Color.marca)
            .disabled(casa.fijo || pedido != nil)
            .accessibilityIdentifier("casa-interruptor")
            if error {
                Label(T.errorCambiar, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.alerta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("casa-error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
    }

    private func cambiar(_ aCasa: Bool) {
        guard pedido == nil, !casa.fijo, aCasa != casa.prendido else { return }
        pedido = aCasa
        error = false
        Task {
            var bien: Bool
            if !aCasa, casa.estado?.abierta == nil {
                // Entrenaba en casa y vuelve a un gimnasio: la carga de siempre, como «Cambié de gimnasio».
                bien = await gimnasio.empezar(modo: "completa") == .ok
            } else {
                let r = await casa.elegir(aCasa)
                bien = r == .ok || r == .enCurso
            }
            await app.refrescarGimnasioYCasa()
            if bien, casa.visible, casa.prendido != aCasa, !casa.fijo { bien = false }
            error = !bien
            pedido = nil
        }
    }
}

/// Lo de casa en lugar de las zonas con fotos: la lista para marcar, «recibido» o lo que ya tiene cargado.
struct CasaPantalla: View {
    let casa: ModeloCasa
    let gimnasio: ModeloGimnasio
    @State private var aviso: String?
    @State private var faltanDatos = false
    @State private var app = Proveedor.modelo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Espacio.m) {
                InterruptorCasa(casa: casa, gimnasio: gimnasio)
                switch casa.pantalla {
                case .lista: lista
                case .recibido: recibido
                case .vigente: vigente
                case .ninguna: EmptyView()
                }
            }
            .padding(.horizontal, Espacio.m)
            .padding(.top, Espacio.s)
            .padding(.bottom, Espacio.xl)
            .anchoLectura()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { if casa.pantalla == .lista { pie } }
    }

    // MARK: La lista

    private var lista: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            VStack(alignment: .leading, spacing: Espacio.xxs) {
                Text(T.listaTitulo).font(Archivo.fuente(24, peso: 800, relativoA: .title2)).accessibilityAddTraits(.isHeader)
                Text(T.listaTexto).font(.body).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Espacio.xs)
            ForEach(casa.estado?.tipos ?? [], id: \.tipo) { t in
                let marcado = casa.marcados.contains(t.tipo)
                VStack(alignment: .leading, spacing: Espacio.xs) {
                    Casilla(texto: t.nombre, marcada: marcado) { casa.marcar(t.tipo, !marcado); aviso = nil }
                        .accessibilityIdentifier("casa-tipo-\(t.tipo)")
                    if t.kg, marcado {
                        VStack(alignment: .leading, spacing: Espacio.xxs) {
                            Text(T.kilos).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            TextField("kg", text: Binding(get: { casa.kilos(t.tipo) }, set: { casa.fijarKilos(t.tipo, $0) }))
                                .keyboardType(.decimalPad)
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .padding(Espacio.s)
                                .background(Color.campo, in: .rect(cornerRadius: Radio.control))
                                .accessibilityLabel(T.kilos)
                                .accessibilityIdentifier("casa-kg-\(t.tipo)")
                        }
                        .padding(.leading, Espacio.xl + Espacio.xs)
                    }
                }
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficieTarjeta(radio: Radio.control + 6)
            }
            Casilla(texto: T.sinEquipo, marcada: casa.sinEquipo) { casa.marcarSinEquipo(!casa.sinEquipo); aviso = nil }
                .padding(Espacio.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .superficieTarjeta(radio: Radio.control + 6)
                .accessibilityIdentifier("casa-sin-equipo")
            VStack(alignment: .leading, spacing: Espacio.xs) {
                Text(T.nota).font(.headline).fixedSize(horizontal: false, vertical: true)
                TextField("", text: Binding(get: { casa.nota }, set: { casa.fijarNota($0) }), axis: .vertical)
                    .lineLimit(2...6)
                    .padding(Espacio.s)
                    .background(Color.campo, in: .rect(cornerRadius: Radio.control))
                    .accessibilityLabel(T.nota)
                    .accessibilityIdentifier("casa-nota")
            }
            .padding(.top, Espacio.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("casa-lista")
    }

    private var pie: some View {
        VStack(spacing: Espacio.xs) {
            if let aviso {
                Label(aviso, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.alerta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(faltanDatos ? "casa-sin-datos" : "casa-error")
            }
            Button(casa.enviando ? T.enviando : T.enviar) { enviar() }
                .buttonStyle(BotonMarca(ocupado: casa.enviando))
                .disabled(!casa.puedeEnviar || casa.enviando)
                .accessibilityIdentifier("casa-enviar")
        }
        .padding(.horizontal, Espacio.m)
        .padding(.vertical, Espacio.s)
        .anchoLectura()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func enviar() {
        Task {
            let r = await casa.enviar()
            faltanDatos = r == .sinDatos
            switch r {
            case .ok, .enCurso: aviso = nil
            case .sinDatos: aviso = T.sinDatos
            case .sinSenal, .error: aviso = T.errorEnviar
            }
            await app.refrescarGimnasioYCasa()
        }
    }

    // MARK: Recibido y vigente

    private var recibido: some View {
        VStack(spacing: Espacio.m) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(Color.marcaTexto).accessibilityHidden(true)
            Text(TextosGimnasio.recibido).font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Espacio.l)
        .frame(maxWidth: .infinity)
        .tarjeta()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("casa-recibido")
    }

    private var vigente: some View {
        let v = casa.estado?.vigente
        return VStack(alignment: .leading, spacing: Espacio.m) {
            VStack(alignment: .leading, spacing: Espacio.s) {
                Text(T.vigenteTitulo).font(Archivo.fuente(24, peso: 800, relativoA: .title2)).accessibilityAddTraits(.isHeader)
                if v?.sinEquipo == true || (v?.equipos.isEmpty ?? true) {
                    Text(T.vigenteSinEquipo).font(.body).foregroundStyle(.secondary)
                } else {
                    ForEach(Array((v?.equipos ?? []).enumerated()), id: \.offset) { n, e in
                        if n > 0 { Divider() }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(casa.nombre(e.tipo)).font(.body.weight(.semibold))
                            if let kg = e.kg { Text(Casa.textoKilos(kg)).font(.subheadline).foregroundStyle(.secondary) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tarjeta()
            if let aviso {
                Label(aviso, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.alerta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("casa-error")
            }
            Button(T.cambiar) {
                Task {
                    let r = await casa.elegir(true)
                    aviso = r == .ok || r == .enCurso ? nil : T.errorCambiar
                    await app.refrescarGimnasioYCasa()
                }
            }
            .buttonStyle(BotonSecundario(tono: .marcaTexto))
            .accessibilityIdentifier("casa-cambiar")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("casa-vigente")
    }
}

/// Una fila grande con casilla y texto. Toda la fila se toca.
private struct Casilla: View {
    let texto: String
    let marcada: Bool
    let accion: () -> Void
    @ScaledMetric(relativeTo: .body) private var lado: CGFloat = 28

    var body: some View {
        Button(action: accion) {
            HStack(spacing: Espacio.s) {
                Image(systemName: marcada ? "checkmark.square.fill" : "square")
                    .font(.system(size: min(lado, 44), weight: .semibold))
                    .foregroundStyle(marcada ? Color.marcaTexto : Color.secondary)
                    .accessibilityHidden(true)
                Text(texto).font(.body.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcada ? .isSelected : [])
    }
}
