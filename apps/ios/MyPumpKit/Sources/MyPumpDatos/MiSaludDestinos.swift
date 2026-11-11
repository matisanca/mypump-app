import MyPumpReglas

extension DestinoAviso {
    /// «Mi salud» (11/11): lo que antes abría Estudios, Presión o Salud → Recuperación ahora abre Mi salud en ese bloque.
    /// Los `destino` viejos siguen iguales (el contrato no cambia). `salud` (que llega como `.misDatos`) va a Recuperación,
    /// alineado con la web; `progress` (Fuerza) no es un bloque de Mi salud y sigue yendo a Salud.
    public var bloqueMiSalud: MiSalud.Bloque? {
        switch self {
        case .estudios: .estudios
        case .presion: .presion
        case .recuperacion, .misDatos: .recuperacion
        default: nil
        }
    }
}
