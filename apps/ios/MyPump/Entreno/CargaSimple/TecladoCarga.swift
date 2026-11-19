import SwiftUI
import UIKit
import MyPumpReglas

/// El teclado del peso (2.3.3, caso Sebastián del 19/11: editaba el peso, no sabía cómo salir y, al tocar abajo, se le
/// registró una serie). Lo mismo que `TecladoCarga.kt` de Android: soltarlo desde cualquier lado y que el OK espere al volver.
@MainActor
enum TecladoCarga {
    /// Suelta el foco del campo que lo tenga, sea cual sea (el kilo, el de cada serie o el de la corrección): el
    /// `@FocusState` de cada vista se entera solo. Sin campo con foco no hace nada.
    static func soltar() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// Si el punto (en la ventana) cae sobre un campo de texto: tocar otro peso pasa el foco sin cerrar el teclado y
    /// volverlo a abrir, y tocar el mismo campo para mover el cursor no lo cierra.
    static func esCampo(_ punto: CGPoint) -> Bool {
        let ventanas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard let ventana = ventanas.first(where: \.isKeyWindow) ?? ventanas.first,
              var vista = ventana.hitTest(punto, with: nil) else { return false }
        while true {
            if vista is UITextField || vista is UITextView { return true }
            guard let padre = vista.superview else { return false }
            vista = padre
        }
    }

    /// Lo que dura la espera del OK. Las pruebas de interfaz la alargan con `-esperaOK <ms>`: el simulador tarda más de
    /// medio segundo entre dos toques y la prueba no podría tocar el OK adentro de la espera.
    static var esperaOK: Double { DemoUI.esperaOK ?? EsperaTrasTeclado.porDefecto }

    /// El reloj de la espera, en milisegundos: el del sistema, que no salta si cambia la hora.
    static func ahora() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }
}

extension View {
    /// Tocar fuera de un campo de texto cierra el teclado. Mira el toque sin quedárselo: el botón tocado hace lo suyo igual
    /// (como `soltarFocoAlTocarAfuera` de Android). Va sobre la lista y la página del ejercicio.
    func soltarTecladoAlTocarAfuera() -> some View {
        simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { toque in
            if !TecladoCarga.esCampo(toque.location) { TecladoCarga.soltar() }
        })
    }
}
