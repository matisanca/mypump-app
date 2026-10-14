import SwiftUI
import MyPumpReglas
import MyPumpDatos

/// "Cerrar sesión de hoy" (SES-06): el resumen (series, reps, volumen y minutos), lo que queda sin completar si se
/// cierra antes, y las notas para Mati. El motor vacía la cola antes de cerrar.
struct CerrarDiaView: View {
    let motor: ModeloEntreno
    @Environment(\.dismiss) private var cerrar
    @State private var notas = ""
    @State private var enviando = false
    @State private var aviso: String?
    @State private var cerrados = 0
    @FocusState private var escribiendo: Bool

    var body: some View {
        let r = motor.resumen
        let anticipado = !motor.todoHecho
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Espacio.l) {
                    HStack(spacing: 0) {
                        celda("Series", "\(r.series)")
                        separador
                        celda("Reps", JS.texto(r.reps))
                        separador
                        celda("Volumen", "\(JS.texto(r.volumenRedondeado)) kg")
                        separador
                        celda("Tiempo", motor.minutos.map { "\($0) min" } ?? "—")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .tarjeta(relleno: 14)

                    if let titulo = motor.dia.avisoPendientes {
                        VStack(alignment: .leading, spacing: Espacio.xs) {
                            Label(titulo, systemImage: "exclamationmark.circle.fill")
                                .labelStyle(IconoTeñido(color: .alerta))
                                .font(.subheadline.weight(.semibold))
                            ForEach(motor.dia.pendientes, id: \.self) { p in
                                Text("· \(NombreEjercicio(p).principal)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(Espacio.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.alerta.opacity(0.12), in: .rect(cornerRadius: Radio.control + 4, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: Espacio.xs) {
                        Text("Notas de la sesión \(Text("· opcional").foregroundStyle(.tertiary))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(anticipado ? "ej: poco tiempo hoy, saltó press de banca…" : "ej: molestia leve hombro derecho, jalón se sintió pesado…",
                                  text: $notas, axis: .vertical)
                            .lineLimit(3...6)
                            .focused($escribiendo)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color.campo, in: .rect(cornerRadius: Radio.control, style: .continuous))
                    }

                    if let aviso {
                        Label(aviso, systemImage: "wifi.exclamationmark")
                            .labelStyle(IconoTeñido(color: .peligro))
                            .font(.subheadline)
                            .transition(.opacity)
                    }
                }
                .padding(Espacio.m)
                .anchoLectura()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.fondo)
            .safeAreaInset(edge: .bottom) {
                Button(action: confirmar) {
                    if enviando {
                        ProgressView().tint(Color.sobreMarca)
                    } else {
                        Label("Confirmar y cerrar", systemImage: "flag.checkered")
                    }
                }
                .buttonStyle(BotonMarca())
                .disabled(enviando)
                .padding(.horizontal, Espacio.m)
                .padding(.bottom, Espacio.xs)
                .anchoLectura()
                .sensoryFeedback(.success, trigger: cerrados)
                .accessibilityIdentifier("confirmar-cierre")
            }
            .navigationTitle("Cerrar sesión de hoy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { cerrar() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .animation(.snappy, value: aviso)
    }

    private var separador: some View {
        Rectangle().fill(Color.borde).frame(width: 1).frame(maxHeight: .infinity)
    }

    private func celda(_ titulo: String, _ valor: String) -> some View {
        VStack(spacing: 3) {
            Text(titulo).textoCeja().lineLimit(1).minimumScaleFactor(0.8)
            Text(valor).font(.numeroChico).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func confirmar() {
        escribiendo = false
        enviando = true
        aviso = nil
        Task {
            let r = await motor.cerrarDia(notas: notas)
            enviando = false
            if let a = r.aviso {
                aviso = a
            } else {
                cerrados += 1
                cerrar()
            }
        }
    }
}
