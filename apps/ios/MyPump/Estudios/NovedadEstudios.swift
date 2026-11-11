import SwiftUI
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosEstudios

// Que un estudio pedido o una orden nueva no se pierdan (pedido de Mati, 10-nov; hay alumnos mayores): una tarjeta arriba
// de Entreno que lleva a Estudios con un toque, un punto en el camino a Mis datos y la etiqueta «Nuevo» en la tarjeta.
// Ningún texto dice qué estudio ni por qué. Todo sale de `ModeloEstudios` (lo que ya trajo el `get`): acá no se llama a nada.

/// La tarjeta de arriba de Entreno, con el patrón de la destacada de «Tu guía»: verde, con el botón blanco de ancho
/// completo. Con algo sin ver dice que hay un estudio o una orden nueva y el botón es «Ver»; sin novedad y con algo por
/// hacer, «Tenés un estudio para hacer» y «Subir resultado». Las dos llevan a Estudios, en esa tarjeta.
struct TarjetaEstudiosInicio: View {
    @State private var app = Proveedor.modelo
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @ScaledMetric(relativeTo: .title2) private var ladoIcono: CGFloat = 52
    @Environment(\.dynamicTypeSize) private var letra

    var body: some View {
        if !app.conMuestras, let m = app.estudios, m.habilitado, let t = m.tarjetaInicio {
            let apilada = letra.isAccessibilitySize
            VStack(alignment: .leading, spacing: Espacio.s) {
                let disposicion = apilada ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.s))
                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.s))
                disposicion {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: ladoIcono * 0.42, weight: .bold))
                        .frame(width: ladoIcono, height: ladoIcono)
                        .background(.white.opacity(0.2), in: .circle)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(T.entradaMisDatos)
                            .textCase(.uppercase)
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                        Text(t.titulo).font(.title3.weight(.bold))
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(T.entradaMisDatos), \(t.titulo)")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("estudios-tarjeta-inicio-texto")

                Button { withAnimation(.snappy) { navegacion?.irAEstudios() } } label: {
                    Label(t.boton, systemImage: t.nueva ? "arrow.right" : "arrow.up.doc.fill").multilineTextAlignment(.center)
                }
                .buttonStyle(BotonSobreVerde())
                .accessibilityLabel("\(t.boton), \(t.titulo)")
                .accessibilityIdentifier("estudios-tarjeta-inicio-boton")
            }
            .foregroundStyle(.white)
            .padding(Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.guiaDestacada, in: .rect(cornerRadius: Radio.tarjeta, style: .continuous))
            .shadow(color: Color.guiaDestacada.opacity(0.28), radius: 16, x: 0, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("estudios-tarjeta-inicio")
        }
    }
}

/// El punto de «hay algo sin ver». VoiceOver lo lee como «Novedad».
struct PuntoNovedad: View {
    @ScaledMetric(relativeTo: .body) private var lado: CGFloat = 12

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: lado))
            .foregroundStyle(Color.marcaVivo)
            .accessibilityLabel(T.novedad)
    }
}

/// «Nuevo», en la tarjeta que el alumno todavía no vio: ícono y texto, no solo color.
struct EtiquetaNuevo: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").imageScale(.small).font(.caption2).accessibilityHidden(true)
            Text(T.nuevo)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(Color.sobreMarca)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.marca, in: .capsule)
        .fixedSize()
    }
}

extension View {
    /// Avisa si esta vista está de verdad en pantalla dentro de su `ScrollView`: al menos la mitad de su alto (o de lo que
    /// entra en la pantalla, si es más alta). Lo que quedó más abajo sin desplazarse no cuenta.
    func alEstarALaVista(_ accion: @escaping (Bool) -> Void) -> some View {
        onGeometryChange(for: Bool.self) { p in
            guard let ventana = p.bounds(of: .scrollView), p.size.height > 0 else { return false }
            let corte = ventana.intersection(CGRect(origin: .zero, size: p.size))
            return !corte.isNull && corte.height >= min(p.size.height, ventana.height) * 0.5
        } action: { accion($0) }
    }
}
