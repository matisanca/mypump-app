import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// E2 (2.0.3): el descanso de este ejercicio, elegido a mano. Una rueda de 0:30 a 5:00 en pasos de 15 s; queda en el
/// teléfono para este ejercicio y le gana al del plan. «Volver al del plan» lo borra.
struct SelectorDescanso: View {
    let plan: Int
    let propio: Bool
    let elegir: (Int?) -> Void
    @State private var seleccion: Int
    @Environment(\.dismiss) private var cerrar

    init(segundos: Int, plan: Int, propio: Bool, elegir: @escaping (Int?) -> Void) {
        self.plan = plan
        self.propio = propio
        self.elegir = elegir
        // Si el del plan no es un paso de 15 s (o está fuera de 0:30-5:00), la rueda arranca en el más cercano.
        let cercano = DescansoPropio.opciones.min { abs($0 - segundos) < abs($1 - segundos) } ?? 90
        _seleccion = State(initialValue: cercano)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Espacio.s) {
                Text("Vale para este ejercicio en todos tus días. El del plan es \(mmss(plan)).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Descanso", selection: $seleccion) {
                    ForEach(DescansoPropio.opciones, id: \.self) { s in
                        Text(mmss(s)).monospacedDigit().tag(s)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 160)
                .accessibilityIdentifier("rueda-descanso")
                Button {
                    elegir(seleccion == plan ? nil : seleccion)
                    cerrar()
                } label: { Text("Usar \(mmss(seleccion))") }
                    .buttonStyle(BotonMarca())
                    .accessibilityIdentifier("guardar-descanso")
                if propio {
                    Button("Volver al del plan (\(mmss(plan)))") {
                        elegir(nil)
                        cerrar()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.marcaTexto)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("descanso-del-plan")
                }
            }
            .padding(.horizontal, Espacio.m)
            .navigationTitle("Descanso")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } }
            }
        }
        .presentationDetents([.height(propio ? 400 : 350)])
        .presentationDragIndicator(.visible)
    }
}

/// E3 (2.0.3): «Récord: +2,5 kg», dorado, apenas se confirma la serie. Se va solo a los 3 s (o al tocarlo).
struct AvisoRecordVista: View {
    let motor: ModeloEntreno
    let lugar: String

    var body: some View {
        Group {
            if let a = motor.avisoRecord, a.lugar == lugar {
                Label(a.texto, systemImage: "trophy.fill")
                    .labelStyle(EtiquetaCompacta())
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.record)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.record.opacity(0.14), in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.record.opacity(0.35), lineWidth: 1))
                    .frame(maxWidth: .infinity)
                    .onTapGesture { withAnimation(.snappy) { motor.descartarRecord(a.id) } }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .task(id: a.id) {
                        UIAccessibility.post(notification: .announcement, argument: a.texto)
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.snappy) { motor.descartarRecord(a.id) }
                    }
                    .sensoryFeedback(.success, trigger: a.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("aviso-record")
            }
        }
        .animation(.snappy, value: motor.avisoRecord)
    }
}
