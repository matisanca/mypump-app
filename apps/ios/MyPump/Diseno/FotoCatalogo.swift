import MyPumpDatos
import SwiftUI
import UIKit

/// Lo que muestra una foto del catálogo mientras llega, ya lista o si no se pudo bajar (como las fases de `AsyncImage`).
enum FaseFoto {
    case cargando
    case lista(Image)
    case error

    var imagen: Image? { if case .lista(let i) = self { i } else { nil } }
}

/// Las fotos de los ejercicios del catálogo (batería, 2.3.2). `AsyncImage` no guarda nada: el bucket responde
/// `no-cache`, así que cada fila que entraba al scroll y cada ejercicio que se abría era un viaje de red. Ahora van por
/// `CacheFotosCatalogo` (memoria y disco) y, ya decodificadas, por una caché de imágenes en memoria: la que ya se vio
/// aparece al instante, sin el fundido; la nueva llega con el mismo fundido de 0,25 s que antes.
struct FotoCatalogo<Contenido: View>: View {
    let url: URL
    @ViewBuilder let contenido: (FaseFoto) -> Contenido

    @State private var imagen: UIImage?
    @State private var deURL: URL?
    @State private var fallo = false

    init(url: URL, @ViewBuilder contenido: @escaping (FaseFoto) -> Contenido) {
        self.url = url
        self.contenido = contenido
        let ya = ImagenesCatalogo.enMemoria(url)
        _imagen = State(initialValue: ya)
        _deURL = State(initialValue: ya == nil ? nil : url)
    }

    private var fase: FaseFoto {
        if deURL == url, let imagen { return .lista(Image(uiImage: imagen)) }
        return fallo ? .error : .cargando
    }

    var body: some View {
        contenido(fase)
            .task(id: url) {
                if deURL == url, imagen != nil { return }
                if let ya = ImagenesCatalogo.enMemoria(url) {
                    imagen = ya; deURL = url; fallo = false
                    return
                }
                fallo = false
                let lista = await ImagenesCatalogo.cargar(url)
                guard !Task.isCancelled else { return }
                if let lista {
                    withAnimation(.easeOut(duration: 0.25)) { imagen = lista; deURL = url }
                } else {
                    fallo = true
                }
            }
    }
}

/// Las fotos del catálogo ya decodificadas y listas para pintar. NSCache se vacía sola si iOS pide memoria.
enum ImagenesCatalogo {
    nonisolated(unsafe) private static let cache: NSCache<NSURL, UIImage> = {
        let c = NSCache<NSURL, UIImage>()
        c.totalCostLimit = 48 * 1024 * 1024
        return c
    }()

    static func enMemoria(_ url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }

    /// De la memoria, del disco o de la red (`CacheFotosCatalogo`), decodificada fuera del hilo principal.
    static func cargar(_ url: URL) async -> UIImage? {
        if let ya = enMemoria(url) { return ya }
        guard let datos = await CacheFotosCatalogo.compartida.datos(url), let img = UIImage(data: datos) else { return nil }
        let lista = await img.byPreparingForDisplay() ?? img
        let costo = Int(lista.size.width * lista.scale * lista.size.height * lista.scale * 4)
        cache.setObject(lista, forKey: url as NSURL, cost: costo)
        return lista
    }
}
