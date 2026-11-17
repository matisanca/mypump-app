import Foundation

/// Qué hacer con la sesión de audio del teléfono (la aplica `SesionAudio`, en la app).
public enum AccionSesionAudio: Equatable, Sendable {
    /// Un video o un audio con voz: `.playback` con `.duckOthers`, activa. La música de otra app sigue, más baja.
    case reproducir
    /// El pitido del descanso: `.ambient` con `.mixWithOthers`, activa. Se mezcla con la música y respeta el silencio.
    case mezclar
    /// Ya no suena nada de la app: `.ambient` con `.mixWithOthers` y se desactiva con `.notifyOthersOnDeactivation`,
    /// así la música vuelve a su volumen (o a sonar).
    case soltar
    case nada
}

/// La cuenta de quién usa la sesión de audio (batería, 2.3.2; revisión de 83920fe0). Se decide por la cuenta y nunca
/// por la categoría: `setActive(false)` no devuelve la categoría y quedaba `.playback` después de un video, así el
/// pitido pausaba la música, sonaba con el teléfono en silencio y no la soltaba más.
///
/// · Reproductores (videos de técnica, videos y audios de la guía y del chat): `tomar` al sonar, `soltar` al frenar,
///   terminar o irse. Repetir cualquiera de los dos no cambia la cuenta. Al soltarse el último, `.soltar`.
/// · Grabador: `contar` (fija su propia categoría) y `soltar`.
/// · Pitido: con algún reproductor o grabador activo suena sobre esa sesión sin tocarla (no lo corta ni lo silencia);
///   si no, arma la suya `.ambient` y la suelta al terminar, salvo que en el medio la haya tomado un reproductor.
public struct CuentaSesionAudio<Dueño: Hashable & Sendable>: Sendable {
    public private(set) var activos: Set<Dueño> = []
    /// La sesión activa la armó el pitido y nadie la tomó después.
    public private(set) var pitidoArmoLaSuya = false

    public init() {}

    public var hayReproductor: Bool { !activos.isEmpty }

    public mutating func tomar(_ dueño: Dueño) -> AccionSesionAudio {
        activos.insert(dueño)
        pitidoArmoLaSuya = false
        return .reproducir
    }

    /// Solo cuenta: el grabador fija `.playAndRecord` por su lado.
    public mutating func contar(_ dueño: Dueño) {
        activos.insert(dueño)
        pitidoArmoLaSuya = false
    }

    public mutating func soltar(_ dueño: Dueño) -> AccionSesionAudio {
        guard activos.remove(dueño) != nil, activos.isEmpty else { return .nada }
        return .soltar
    }

    public mutating func alSonarPitido() -> AccionSesionAudio {
        guard activos.isEmpty else { return .nada }
        pitidoArmoLaSuya = true
        return .mezclar
    }

    /// Cuando el pitido terminó y no volvió a sonar.
    public mutating func alTerminarPitido() -> AccionSesionAudio {
        guard pitidoArmoLaSuya, activos.isEmpty else { return .nada }
        pitidoArmoLaSuya = false
        return .soltar
    }
}
