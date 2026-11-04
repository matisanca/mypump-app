import SwiftUI
import MyPumpReloj

/// Los datos del modo calibración en el iPhone (tanda 4): las series que manda el reloj por `transferFile`, juntas en un
/// archivo `.mpcal` por sesión, en una carpeta con tope. Solo salen del teléfono si el alumno las exporta (hoja de
/// compartir). Nada va al servidor.
enum DatosCalibracion {
    static var carpeta: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("calibracion")
    }
    static var almacen: AlmacenCalibracion { AlmacenCalibracion(carpeta: carpeta, tope: AlmacenCalibracion.topeIPhone) }
    /// Los archivos del reloj ya recibidos (un reenvío no duplica una serie).
    static let claveRecibidos = "mypump-calibracion-recibidos"

    /// Un archivo que llegó del reloj. Corre en el hilo de WatchConnectivity y tiene que terminar antes de volver (el
    /// sistema borra el archivo después). Con el modo apagado para esa cuenta se descarta.
    static func recibir(_ url: URL, metadatos: [String: Any]?) {
        let cuenta = metadatos?["cuenta"] as? String ?? ""
        guard ModoCalibracion().prendido(cuenta: cuenta), let d = try? Data(contentsOf: url),
              let registros = try? ArchivoCalibracion.leer(d), !registros.isEmpty else { return }
        let nombre = metadatos?["nombre"] as? String ?? url.lastPathComponent
        let defaults = UserDefaults.standard
        var recibidos = defaults.stringArray(forKey: claveRecibidos) ?? []
        guard !recibidos.contains(nombre) else { return }
        var escrito = true
        for (sesion, rs) in Dictionary(grouping: registros, by: \.encabezado.sesion) {
            let datos = rs.compactMap { try? ArchivoCalibracion.datos($0) }.reduce(Data(), +)
            do { try almacen.anexar(datos, nombre: "calibracion-\(seguro(sesion)).\(ArchivoCalibracion.extension_)") } catch { escrito = false }
        }
        // Solo si quedó escrito: si no, un reenvío del reloj lo vuelve a intentar.
        guard escrito else { return }
        recibidos.append(nombre)
        defaults.set(Array(recibidos.suffix(2_000)), forKey: claveRecibidos)
    }

    static func seguro(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }.prefix(40)))
    }

    struct Sesion: Identifiable {
        var url: URL
        var series: Int
        var bytes: Int
        var id: URL { url }
        /// «calibracion-2026-11-03-s2-d3» → «2026-11-03 · semana 2»
        var titulo: String {
            let partes = url.deletingPathExtension().lastPathComponent.split(separator: "-").dropFirst()
            guard partes.count >= 4 else { return url.lastPathComponent }
            return "\(partes.prefix(3).joined(separator: "-")) · semana \(partes[partes.startIndex + 3].dropFirst())"
        }
    }

    static func sesiones() -> [Sesion] {
        almacen.archivos().reversed().map { a in
            let n = (try? Data(contentsOf: a.url)).map { ArchivoCalibracion.encabezados($0).count } ?? 0
            return Sesion(url: a.url, series: n, bytes: a.bytes)
        }
    }
}

/// Mis datos → Conteo de reps (con el reloj emparejado). Viene prendido; acá se apaga para la cuenta abierta,
/// explica qué se graba y exporta los datos (un archivo por sesión).
struct CalibracionView: View {
    let cuenta: String
    private let modo = ModoCalibracion()
    @State private var prendido = false
    @State private var sesiones: [DatosCalibracion.Sesion] = []
    @State private var confirmarBorrado = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { prendido }, set: { nuevo in
                    prendido = nuevo
                    modo.poner(nuevo, cuenta: cuenta)
                    PuenteReloj.compartido.mandarRutina(forzar: true)
                })) {
                    Label { Text("Contar reps con el reloj") } icon: { IconoAzulejo("waveform.path.ecg", color: .agua) }
                }
                .tint(Color.marcaVivo)
                .accessibilityIdentifier("modo-calibracion")
            } header: {
                Text("Apple Watch")
            } footer: {
                Text(ModoCalibracion.textoPrivacidad)
            }

            Section {
                if sesiones.isEmpty {
                    Text("Todavía no hay series grabadas. Entrená con el reloj y el conteo prendido.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sesiones) { s in
                        LabeledContent(s.titulo, value: "\(s.series) \(s.series == 1 ? "serie" : "series") · \(ByteCountFormatter.string(fromByteCount: Int64(s.bytes), countStyle: .file))")
                    }
                    ShareLink(items: sesiones.map(\.url)) {
                        Label("Exportar series grabadas", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("exportar-calibracion")
                    Button("Borrar series grabadas", role: .destructive) { confirmarBorrado = true }
                }
            } header: {
                Text("Grabado en este iPhone")
            } footer: {
                Text("Un archivo por sesión de entreno. Al exportarlo elegís a dónde va; la app no lo manda a ningún lado.")
            }
        }
        .navigationTitle("Conteo de reps")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Borrar todas las series grabadas en este iPhone?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                DatosCalibracion.almacen.borrarTodo()
                sesiones = []
            }
        }
        .task {
            prendido = modo.prendido(cuenta: cuenta)
            sesiones = DatosCalibracion.sesiones()
        }
    }
}
