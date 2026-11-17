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
    /// El pitido con el grabador de dudas activo: no suena (quedaría grabado en la duda) y la sesión no se toca.
    case callar
    case nada
}

/// La cuenta de quién usa la sesión de audio (batería, 2.3.2; revisión de 83920fe0). Se decide por la cuenta y nunca
/// por la categoría: `setActive(false)` no devuelve la categoría y quedaba `.playback` después de un video, así el
/// pitido pausaba la música, sonaba con el teléfono en silencio y no la soltaba más.
///
/// · Reproductores (videos de técnica, videos y audios de la guía y del chat): `tomar` al sonar, `soltar` al frenar,
///   terminar o irse. Repetir cualquiera de los dos no cambia la cuenta. Al soltarse el último, `.soltar`.
/// · Grabador: `contar` (fija su propia categoría) y `soltarGrabador`: si queda otro dueño, la sesión vuelve a la de
///   ese reproductor (`.reproducir`), nunca se desactiva debajo de él.
/// · Pitido: con el grabador activo no suena (`.callar`). Con algún reproductor activo suena sobre esa sesión sin tocarla
///   (no lo corta ni lo silencia); si no, arma la suya `.ambient` y la suelta al terminar, salvo que en el medio la haya
///   tomado un reproductor. Antes de decidir, cada dueño se re-confirma (`siguen`): el que quedó contado pero ya no suena
///   (lo cortó una llamada o Siri, o la app se fue con él sonando) se descarta y nunca bloquea al pitido.
public struct CuentaSesionAudio<Dueño: Hashable & Sendable>: Sendable {
    public private(set) var activos: Set<Dueño> = []
    /// La sesión activa la armó el pitido y nadie la tomó después.
    public private(set) var pitidoArmoLaSuya = false
    /// Los dueños que son el grabador de dudas (también están en `activos`).
    public private(set) var grabadores: Set<Dueño> = []

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
        grabadores.insert(dueño)
        pitidoArmoLaSuya = false
    }

    public mutating func soltar(_ dueño: Dueño) -> AccionSesionAudio {
        grabadores.remove(dueño)
        guard activos.remove(dueño) != nil, activos.isEmpty else { return .nada }
        return .soltar
    }

    /// El grabador terminó (o no pudo empezar). Repetirlo no hace nada: nunca dos `setActive(false)` seguidos. Si queda
    /// otro dueño, la sesión vuelve a la suya (`.playback`), sin desactivarse.
    public mutating func soltarGrabador(_ dueño: Dueño) -> AccionSesionAudio {
        grabadores.remove(dueño)
        guard activos.remove(dueño) != nil else { return .nada }
        return activos.isEmpty ? .soltar : .reproducir
    }

    /// Nadie la usa: un reintento de desactivarla (después de `isBusy`) todavía corresponde.
    public var libre: Bool { activos.isEmpty && !pitidoArmoLaSuya }

    /// `siguen` dice si el dueño de verdad sigue sonando o grabando; los que no, se descartan antes de decidir.
    public mutating func alSonarPitido(siguen: (Dueño) -> Bool = { _ in true }) -> AccionSesionAudio {
        let muertos = activos.filter { !siguen($0) }
        activos.subtract(muertos)
        grabadores.subtract(muertos)
        guard grabadores.isEmpty else { return .callar }
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
