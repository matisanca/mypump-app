import SwiftUI
import PDFKit
import MyPumpReglas
import MyPumpDatos

private typealias T = TextosEstudios

/// Abre una orden o un estudio propio: pide las URL en el momento (duran 10 minutos y no se guardan), baja a un temporal y
/// lo muestra dentro de la app. Al cerrar, el temporal se borra.
@MainActor @Observable
final class AbridorEstudios {
    struct Abierto: Identifiable {
        let id = UUID()
        let titulo: String
        let archivos: [ModeloEstudios.ArchivoParaVer]
    }

    /// El id de lo que se está bajando.
    private(set) var abriendo: String?
    /// El id de lo último que no se pudo abrir.
    private(set) var errorEn: String?
    var abierto: Abierto?

    @ObservationIgnored private var vuelta = 0

    func abrir(clase: String, id: String, titulo: String, modelo: ModeloEstudios) {
        guard abriendo == nil else { return }
        abriendo = id
        errorEn = nil
        vuelta += 1
        let esta = vuelta
        Task {
            let r = await modelo.bajarParaVer(clase: clase, id: id)
            // Se fue de la pantalla mientras bajaba: no se muestra y no queda en el teléfono.
            guard esta == vuelta else { modelo.cerrarVisor(); return }
            abriendo = nil
            switch r {
            case .archivos(let a): abierto = Abierto(titulo: titulo, archivos: a)
            case .error: errorEn = id
            }
        }
    }

    /// La pantalla se va: lo que estaba bajando se descarta.
    func cancelar(_ modelo: ModeloEstudios) {
        guard abriendo != nil else { return }
        vuelta += 1
        abriendo = nil
        modelo.cerrarVisor()
    }
}

extension View {
    func visorDeEstudios(_ abridor: AbridorEstudios, modelo: ModeloEstudios) -> some View {
        sheet(item: Binding(get: { abridor.abierto }, set: { abridor.abierto = $0 }), onDismiss: { modelo.cerrarVisor() }) { a in
            VisorEstudios(abierto: a) { abridor.abierto = nil }
        }
    }
}

private struct VisorEstudios: View {
    let abierto: AbridorEstudios.Abierto
    let alCerrar: () -> Void
    @State private var documento: PDFDocument?
    @State private var fallo = false

    var body: some View {
        NavigationStack {
            Group {
                if let documento {
                    VistaPDF(documento: documento).ignoresSafeArea(edges: .bottom).accessibilityIdentifier("estudios-visor")
                } else if fallo {
                    NotaEstudios(texto: T.noSePudoAbrir, icono: "exclamationmark.circle", tono: .ambarEstudios, anunciar: true).padding(Espacio.m)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.fondo)
            .navigationTitle(abierto.titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(T.cerrar, action: alCerrar).accessibilityIdentifier("estudios-visor-cerrar") } }
        }
        .tint(Color.marcaTexto)
        .task {
            let archivos = abierto.archivos
            let d = await Task.detached(priority: .userInitiated) { Self.armar(archivos) }.value
            if let d { documento = d.documento } else { fallo = true }
        }
    }

    /// `PDFDocument` no es `Sendable`: cruza el hilo en una caja, una sola vez.
    private struct Caja: @unchecked Sendable { let documento: PDFDocument }

    /// Un solo documento con todo: las hojas de cada PDF y cada foto como una hoja. Se arma en memoria: no depende de que el
    /// temporal siga ahí.
    private nonisolated static func armar(_ archivos: [ModeloEstudios.ArchivoParaVer]) -> Caja? {
        let todo = PDFDocument()
        for a in archivos {
            guard let datos = try? Data(contentsOf: a.url) else { continue }
            if a.pdf {
                guard let d = PDFDocument(data: datos) else { continue }
                for i in 0..<d.pageCount { if let p = d.page(at: i) { todo.insert(p, at: todo.pageCount) } }
            } else if let imagen = UIImage(data: datos), let p = PDFPage(image: imagen) {
                todo.insert(p, at: todo.pageCount)
            }
        }
        return todo.pageCount > 0 ? Caja(documento: todo) : nil
    }
}

private struct VistaPDF: UIViewRepresentable {
    let documento: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = true
        v.backgroundColor = .systemGroupedBackground
        v.document = documento
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== documento { v.document = documento }
    }
}
