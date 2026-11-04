import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

/// «Recuperación», arriba de todo en Revisión (2.1.0, pedido de Mati del 4-nov): lo principal de Salud, en corto. Toda la
/// tarjeta abre Salud en Recuperación (sueño, corazón, fuerza y cuerpo). El estado sale de `SaludVista.cardRecuperacion`,
/// el mismo de la card grande de Salud; acá solo se resume. Sin cuenta (demo y bocetos), `modelo` es nil.
struct RecuperacionTarjeta: View {
    let modelo: ModeloSalud?
    let abrir: () -> Void

    var body: some View {
        Button(action: abrir) {
            VStack(alignment: .leading, spacing: 12) {
                EncabezadoSalud(icono: "🔋", titulo: "Recuperación")
                contenido
                Divider()
                HStack(spacing: Espacio.s) {
                    Text("Ver sueño, corazón y cuerpo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .tarjeta()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre Salud")
        .accessibilityIdentifier("tarjeta-recuperacion-revision")
    }

    @ViewBuilder private var contenido: some View {
        if let modelo {
            switch modelo.cardRecuperacion {
            case .conScore(let c): conScore(c)
            case .oculto:
                texto("Ocultaste el número de recuperación. Tocá para ver tus datos de salud.")
            case .calibrando(let dias, _, let yaSe, _):
                Text("Aprendiendo tu normal: \(dias) de 14 días").font(.subheadline.weight(.medium))
                if !yaSe.isEmpty { texto(yaSe) }
            case .conectadoSinScore(let caso, _):
                texto(caso.frase)
            case .sinConectar:
                texto("Conectá tu reloj o Salud para ver tu recuperación de cada día.")
            }
        } else {
            texto("Con tu cuenta, acá vas a ver tu recuperación de cada día.")
        }
    }

    @ViewBuilder private func conScore(_ c: SaludVista.ConScore) -> some View {
        let tono = CardRecuperacionView.color(c.banda, apagado: c.confianza?.apagado == true)
        HStack(alignment: .center, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(c.fila.score ?? 0)").font(.numeroGrande).foregroundStyle(tono)
                Text("de 100").font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.bandaTexto).font(.headline).foregroundStyle(tono)
                // Una pastilla quieta: tocar cualquier parte abre Salud, donde se explica cómo mejorarla.
                if let conf = c.confianza { Chip(texto: conf.etiqueta, icono: "info.circle") }
            }
        }
        if let linea = Self.linea(c) { texto(linea) }
        if let vieja = c.notaVieja { Text(vieja).font(.caption).foregroundStyle(.secondary) }
    }

    private func texto(_ s: String) -> some View {
        Text(s).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    /// La frase de la card grande o, sin frase, el primer motivo («↓ Dormiste 1 h menos que tu normal»).
    static func linea(_ c: SaludVista.ConScore) -> String? {
        if let f = c.frase { return f }
        guard let m = c.motivos.first else { return nil }
        return "\(m.sube ? "↑" : "↓") \(m.antes)\(m.negrita)\(m.despues)"
    }
}

/// «Tu progreso», debajo de Recuperación (2.1.0, aprobada por Mati el 4-nov): en una línea lo más útil de la semana (un
/// récord, los ejercicios que subieron o las sesiones; `ProgresoSemana`). Toda la tarjeta abre Salud en Fuerza, lo que era
/// la pestaña Progreso. Sin línea (la demo, o sin entrenos esta semana), lo genérico.
struct ProgresoTarjeta: View {
    let linea: ProgresoSemana.Linea?
    let abrir: () -> Void

    var body: some View {
        Button(action: abrir) {
            VStack(alignment: .leading, spacing: 12) {
                EncabezadoSalud(icono: "📈", titulo: "Tu progreso")
                if let linea {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // El trofeo es ícono, no texto: los textos para el cliente van sin emojis.
                        if linea.record {
                            Image(systemName: "trophy.fill").font(.subheadline).foregroundStyle(Color.alerta).accessibilityHidden(true)
                        }
                        Text(linea.texto).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Tu fuerza y tus récords, ejercicio por ejercicio.")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack(spacing: Espacio.s) {
                    Text("Ver fuerza y récords")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.marcaTexto)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .tarjeta()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre tu fuerza y tus récords")
        .accessibilityIdentifier("tarjeta-progreso-revision")
    }
}
