import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

// «Antes de la videollamada» (2.3.0, palanca `lista_previa`): lo que falta para la videollamada de comienzo. Los textos son
// los de `apps/shared/vectores/lista_previa.json` (`ReglasListaPrevia`). Siempre desplegada, arriba de todo en Entreno:
// · con la tarjeta de la videollamada (reserva de comienzo), DENTRO de esa tarjeta, debajo de lo que ya tiene;
// · sin tarjeta de videollamada, como tarjeta propia en ese mismo lugar;
// · con una reserva de revisión, no se muestra.
// Solo lee: tocar un punto que falta lleva directo a donde se resuelve (la guía de videos o las fotos de Revisión).

@MainActor
enum ListaPreviaUI {
    /// La lista que hay para mostrar, o nil (palanca apagada, sin lista, bocetos).
    static func vista(_ m: ModeloApp) -> ReglasListaPrevia.Vista? {
        #if DEBUG
        // `-listaPreviaDePrueba demo|listo`: la lista de muestra sin cuenta (pruebas de interfaz y capturas).
        if let caso = UserDefaults.standard.string(forKey: "listaPreviaDePrueba") {
            return ReglasListaPrevia.vista(caso == "listo" ? DobleColaA.listaLista : DobleColaA.listaDemo)
        }
        #endif
        if DemoUI.bocetos { return nil }
        // La demo trae la suya (`historial.json`), sin palanca: no sale de ninguna cuenta.
        if m.esDemo { return m.listaPrevia?.vista }
        guard m.palanca.listaPrevia else { return nil }
        return m.listaPrevia?.vista
    }

    /// La que va DENTRO de la tarjeta de la videollamada: solo con una reserva de comienzo.
    static func dentro(_ m: ModeloApp, guia: ModeloGuia?) -> ReglasListaPrevia.Vista? {
        guard let r = guia?.reservaTarjeta(), r.tipo == .comienzo else { return nil }
        return vista(m)
    }

    /// La que va como tarjeta propia: cuando no hay tarjeta de videollamada.
    static func sola(_ m: ModeloApp, guia: ModeloGuia?) -> ReglasListaPrevia.Vista? {
        guard guia?.reservaTarjeta() == nil else { return nil }
        return vista(m)
    }

    /// Lo que cambia cuando cambian la guía o la agenda: ahí se vuelve a pedir la lista (el modelo no pide más de una vez
    /// por minuto).
    static func clave(_ guia: ModeloGuia?) -> String {
        guard let guia else { return "" }
        let r = guia.reservaTarjeta()
        return "\(r?.inicio ?? "")|\(r?.estado.rawValue ?? "")|\(guia.tarjetaDestacada)"
    }
}

/// La lista sola, en el lugar de la tarjeta de la videollamada.
struct TarjetaListaPrevia: View {
    let vista: ReglasListaPrevia.Vista
    /// nil sin guía: la fila de la guía no es un botón.
    let abrirGuia: (() -> Void)?

    var body: some View {
        ListaPreviaBloque(vista: vista, sobreVerde: false, conIcono: true, abrirGuia: abrirGuia)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .superficieTarjeta(radio: Radio.tarjeta)
            .overlay {
                RoundedRectangle(cornerRadius: Radio.tarjeta, style: .continuous)
                    .strokeBorder(Color.marca.opacity(0.45), lineWidth: 1.5)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("lista-previa-tarjeta")
    }
}

/// El contenido: título y resumen, una fila por punto y el consejo. `sobreVerde`: dentro de la tarjeta de la videollamada
/// cuando ya se puede entrar (fondo verde, letras claras).
struct ListaPreviaBloque: View {
    let vista: ReglasListaPrevia.Vista
    let sobreVerde: Bool
    var conIcono = false
    let abrirGuia: (() -> Void)?
    @Environment(Navegacion.self) private var navegacion: Navegacion?
    @Environment(\.dynamicTypeSize) private var tamañoLetra

    private var secundario: Color { sobreVerde ? Color.sobreMarca.opacity(0.85) : .secondary }

    var body: some View {
        VStack(alignment: .leading, spacing: Espacio.s) {
            cabecera
            VStack(alignment: .leading, spacing: Espacio.xs) {
                ForEach(vista.items) { item in
                    if let accion = accion(item) {
                        Button(action: accion) { fila(item, boton: true) }
                            .buttonStyle(FilaListaPrevia(sobreVerde: sobreVerde))
                            .accessibilityLabel(item.accesible)
                            .accessibilityIdentifier("lista-previa-\(item.clave)")
                    } else {
                        fila(item, boton: false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(item.accesible)
                            .accessibilityIdentifier("lista-previa-\(item.clave)")
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "wifi").accessibilityHidden(true)
                Text(ReglasListaPrevia.consejo).fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(secundario)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("lista-previa-consejo")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lista-previa")
    }

    private var cabecera: some View {
        let disposicion = tamañoLetra.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Espacio.xs))
                                                          : AnyLayout(HStackLayout(alignment: .center, spacing: Espacio.xs))
        return disposicion {
            HStack(spacing: Espacio.xs) {
                if conIcono {
                    Image(systemName: "checklist")
                        // Tamaño fijo: el círculo no crece con la letra y el dibujo no se tiene que cortar.
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.sobreMarca)
                        .frame(width: 30, height: 30).background(Color.marca, in: .circle)
                        .accessibilityHidden(true)
                }
                Text(ReglasListaPrevia.titulo)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("lista-previa-titulo")
            }
            if !tamañoLetra.isAccessibilitySize { Spacer(minLength: Espacio.xs) }
            if let r = vista.resumen {
                Text(r)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(sobreVerde ? Color.marca : Color.marcaTexto)
                    .background(sobreVerde ? Color.sobreMarca : Color.marcaSuave, in: .capsule)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("lista-previa-resumen")
            }
        }
    }

    /// A dónde lleva la fila, o nil si no es un botón (hecha, sin destino, o sin a dónde ir).
    private func accion(_ item: ReglasListaPrevia.Item) -> (() -> Void)? {
        switch item.destino {
        case .guia: return abrirGuia
        case .fotos:
            guard let navegacion else { return nil }
            return { navegacion.irARevision("fotos") }
        case nil: return nil
        }
    }

    private func fila(_ item: ReglasListaPrevia.Item, boton: Bool) -> some View {
        HStack(alignment: .center, spacing: Espacio.s) {
            Image(systemName: item.hecho ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(item.hecho ? (sobreVerde ? Color.sobreMarca : Color.marcaVivo) : secundario)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.titulo)
                    .font(.body.weight(boton ? .semibold : .regular))
                    .foregroundStyle(sobreVerde ? Color.sobreMarca : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let d = item.detalle {
                    Text(d)
                        .font(.footnote)
                        .foregroundStyle(secundario)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Espacio.xs)
            if boton {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(sobreVerde ? Color.sobreMarca : Color.marcaTexto)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, boton ? Espacio.s : 0)
        .padding(.vertical, boton ? Espacio.s : 4)
        .frame(minHeight: boton ? 56 : nil)
    }
}

/// La fila que es un botón: toda la fila, grande, con su fondo.
private struct FilaListaPrevia: ButtonStyle {
    let sobreVerde: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(sobreVerde ? Color.sobreMarca.opacity(0.18) : Color.campo, in: .rect(cornerRadius: Radio.control + 4, style: .continuous))   // neutro: el verde suave queda para lo ya hecho
            .contentShape(.rect(cornerRadius: Radio.control + 4, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
