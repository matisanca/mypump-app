import SwiftUI
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosControles

// «Tu próximo control de salud» (pedido de Mati, 11/11; palanca `controles_app`). Desde `avisar_desde` y mientras el control
// siga programado, una tarjeta arriba de todo en la primera pestaña con un botón grande «Ver mis estudios» que lleva a
// Estudios en un toque (el mismo camino que la tarjeta de estudios pendientes). Nunca dice por qué ni nombra el ciclo.
// Todo sale de `ModeloEstudios` (lo que ya trajo el `get`): acá no se llama a nada.

/// La tarjeta de arriba de Entreno, con el patrón de la destacada: verde, letra grande y el botón blanco de ancho completo.
struct TarjetaControlInicio: View {
    @State private var app = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @ScaledMetric(relativeTo: .title2) private var ladoIcono: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        if !app.conMuestras, app.palanca.controlesApp, let m = app.estudios, m.habilitado, let t = m.tarjetaControl {
            let apilada = letra.isAccessibilitySize
            VStack(alignment: .leading, spacing: Espacio.s) {
                let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
                disposicion {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: ladoIcono * 0.42, weight: .bold))
                        .frame(width: ladoIcono, height: ladoIcono)
                        .background(.white.opacity(0.2), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T.cejaInicio)
                            .textCase(.uppercase)
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                        Text(t.titulo).font(.title3.weight(.bold))
                        Text(t.cuando).font(.title3.weight(.semibold))
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(t.titulo). \(t.cuando)")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("control-tarjeta-inicio-texto")

                Text(t.nota)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("control-tarjeta-inicio-nota")

                Button { withAnimation(.snappy) { navegacion?.irAEstudios() } } label: {
                    Label(t.boton, systemImage: "arrow.right").multilineTextAlignment(.center)
                }
                .buttonStyle(BotonSobreVerde())
                .accessibilityLabel(t.boton)
                .accessibilityHint("\(t.titulo), \(t.cuando)")
                .accessibilityIdentifier("control-tarjeta-inicio-boton")
            }
            .foregroundStyle(.white)
            .padding(Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.guiaDestacada, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .shadow(color: Color.guiaDestacada.opacity(0.28), radius: 16, x: 0, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("control-tarjeta-inicio")
        }
    }
}

/// «Tu recorrido»: el próximo control y los últimos, como hitos con fecha. Nada si no hay.
struct HitosControlRecorrido: View {
    @State private var app = Proveedor.modelo

    var body: some View {
        if app.palanca.controlesApp, let m = app.estudios, m.habilitado, !m.hitosControl.isEmpty {
            VStack(alignment: .leading, spacing: Espacio.s) {
                Text(T.hitosTitulo).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
                ForEach(Array(m.hitosControl.enumerated()), id: \.offset) { n, h in
                    HStack(alignment: .firstTextBaseline, spacing: Espacio.s) {
                        Image(systemName: h.estado == T.hitoProximo ? "calendar" : "checkmark.circle.fill")
                            .foregroundStyle(Color.marcaTexto)
                            .accessibilityHidden(true)
                        // El estado va abajo, como texto: con la letra más grande no se corta.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(h.titulo).font(.headline)
                            Text(h.cuando).font(.body).foregroundStyle(.secondary)
                            Text(h.estado).font(.subheadline.weight(.semibold)).foregroundStyle(Color.marcaTexto)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tarjeta()
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("recorrido-control-\(n)")
                }
            }
            .accessibilityIdentifier("recorrido-controles")
        }
    }
}
