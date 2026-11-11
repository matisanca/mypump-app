import MyPumpReglas

extension DestinoAviso {
    /// «Mi salud» (11/11): lo que antes abría Estudios, Presión o Salud → Recuperación ahora abre Mi salud en ese bloque.
    /// Los `destino` viejos siguen iguales (el contrato no cambia); `progress` (Fuerza) y `salud` (Mis datos) no son
    /// bloques de Mi salud y siguen yendo a donde iban.
    public var bloqueMiSalud: MiSalud.Bloque? {
        switch self {
        case .estudios: .estudios
        case .presion: .presion
        case .recuperacion: .recuperacion
        default: nil
        }
    }
}
