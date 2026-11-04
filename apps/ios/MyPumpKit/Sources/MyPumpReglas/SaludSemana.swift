import MyPumpModelos

/// «Tu salud, últimos 7 días» (2.1.0, pedido de Mati del 4-nov): lo que va con el check de la semana, en Revisión. Los
/// promedios de los últimos 7 días (hoy incluido) de lo que ya está en el servidor: el coach lo ve con su panel
/// (`mypump_get_recuperacion_cliente_coach` y la salud diaria), sin migración. Una fila por dato que tenga al menos un
/// día; sin ninguno, vacío y el bloque no se muestra. Los vectores, en `apps/shared/vectores/salud_semana.json`.
public enum SaludSemana {
    public struct Fila: Sendable, Equatable {
        /// recuperacion | sueno | hrv | fc_reposo | pasos
        public let clave: String
        public let etiqueta: String
        public let valor: String
        /// "promedio de 5 días" | "1 día"
        public let detalle: String
    }

    /// Los tipos de `mypump_salud_diaria`, en el orden en que se muestran (la recuperación va primero).
    static let tipos: [(clave: String, tipo: String, etiqueta: String)] = [
        ("sueno", "sueno_min", "Sueño"),
        ("hrv", "hrv_ms", "Variabilidad (HRV)"),
        ("fc_reposo", "fc_reposo", "Pulso en reposo"),
        ("pasos", "pasos", "Pasos"),
    ]

    /// `mostrarScore` es `mypump_get_mostrar_recuperacion`: si el cliente apagó el número, no se promedia.
    public static func resumen(salud: [FilaSalud], recuperacion: [RecuperacionDia], hoy: String, mostrarScore: Bool) -> [Fila] {
        guard let n = DiaCalendario.numero(hoy) else { return [] }
        let fechas = (0..<7).map { DiaCalendario.texto(n - $0) }
        var filas: [Fila] = []

        if mostrarScore {
            // Un score por fecha: el último con número de esa fecha, si viniera repetida.
            var porFecha: [String: Int] = [:]
            for r in recuperacion where fechas.contains(r.fecha) { if let s = r.score { porFecha[r.fecha] = s } }
            if !porFecha.isEmpty {
                let prom = Double(porFecha.values.reduce(0, +)) / Double(porFecha.count)
                filas.append(Fila(clave: "recuperacion", etiqueta: "Recuperación",
                                  valor: "\(SaludVista.enteroJS(prom)) de 100", detalle: detalle(porFecha.count)))
            }
        }

        for t in tipos {
            let vals = fechas.compactMap { SaludVista.valor(salud, tipo: t.tipo, fecha: $0) }.filter { $0 > 0 && $0.isFinite }
            guard !vals.isEmpty else { continue }
            let prom = vals.reduce(0, +) / Double(vals.count)
            let valor: String
            switch t.clave {
            // Redondeado antes: con decimales, `horas` redondea el resto aparte y 419,5 min salía «6h 60».
            case "sueno": valor = SaludVista.horas(prom.rounded())
            case "hrv": valor = "\(SaludVista.enteroJS(prom)) ms"
            case "fc_reposo": valor = "\(SaludVista.enteroJS(prom)) lpm"
            default: valor = "\(SaludVista.miles(prom)) por día"
            }
            filas.append(Fila(clave: t.clave, etiqueta: t.etiqueta, valor: valor, detalle: detalle(vals.count)))
        }
        return filas
    }

    static func detalle(_ dias: Int) -> String { dias == 1 ? "1 día" : "promedio de \(dias) días" }
}
