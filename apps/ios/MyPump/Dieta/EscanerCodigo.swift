import SwiftUI
import AVFoundation
import VisionKit
import MyPumpReglas

/// El escáner de códigos de barras de «Agregar alimento» (2.1, S3): el de VisionKit (`DataScannerViewController`, el del
/// sistema, con el resaltado en vivo), solo EAN-13, EAN-8 y UPC-E (UPC-A llega como EAN-13 con un 0 adelante). Se cierra
/// con el primer código válido. En DEBUG, `-codigoDePrueba <número>` lo reemplaza (el simulador no tiene cámara).
enum EscanerCodigo {
    /// Qué se puede hacer en este teléfono.
    enum Estado { case listo, sinPermiso, noSoportado }

    /// Antes de abrir: el escáner necesita la cámara (pide el permiso la primera vez) y un iPhone que lo soporte (A12 o
    /// más nuevo). `isAvailable` da false con el permiso sin pedir, así que el permiso va primero.
    @MainActor static func preparar() async -> Estado {
        guard DataScannerViewController.isSupported else { return .noSoportado }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return .sinPermiso }
        case .denied, .restricted:
            return .sinPermiso
        default:
            break
        }
        return DataScannerViewController.isAvailable ? .listo : .sinPermiso
    }

    #if DEBUG
    /// `-codigoDePrueba 7791337006355`: el código que «lee» el escáner en las pruebas de interfaz, sin abrir la cámara.
    static var dePrueba: String? { UserDefaults.standard.string(forKey: "codigoDePrueba") }
    #else
    static var dePrueba: String? { nil }
    #endif
}

/// La pantalla del escáner: la cámara entera, la indicación arriba y «Cancelar».
struct EscanerCodigoView: View {
    /// El código ya normalizado (`CodigoBarras.normalizar`), o nil si se canceló.
    let alTerminar: (String?) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            CamaraCodigos { alTerminar($0) }
                .ignoresSafeArea()
            VStack(spacing: Espacio.s) {
                HStack {
                    Spacer()
                    Button("Cancelar") { alTerminar(nil) }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Espacio.m).padding(.vertical, Espacio.xs)
                        .background(.black.opacity(0.45), in: .capsule)
                        .accessibilityIdentifier("escaner-cancelar")
                }
                Spacer()
                Label("Apuntá al código de barras del envase", systemImage: "barcode.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Espacio.m).padding(.vertical, Espacio.s)
                    .background(.black.opacity(0.55), in: .capsule)
                    .padding(.bottom, Espacio.xl)
            }
            .padding(Espacio.m)
        }
        .background(Color.black)
    }
}

/// `DataScannerViewController` con el primer código válido.
private struct CamaraCodigos: UIViewControllerRepresentable {
    let alLeer: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        // Arranca cuando ya está en pantalla (antes, `startScanning` no hace nada).
        if !vc.isScanning { try? vc.startScanning() }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinador) { vc.stopScanning() }

    func makeCoordinator() -> Coordinador { Coordinador(alLeer: alLeer) }

    final class Coordinador: NSObject, DataScannerViewControllerDelegate {
        let alLeer: (String) -> Void
        private var leido = false
        init(alLeer: @escaping (String) -> Void) { self.alLeer = alLeer }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !leido else { return }
            for item in items {
                guard case .barcode(let b) = item, let texto = b.payloadStringValue,
                      let codigo = CodigoBarras.normalizar(texto, upcE: b.observation.symbology == .upce) else { continue }
                leido = true
                scanner.stopScanning()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                alLeer(codigo)
                return
            }
        }
    }
}
