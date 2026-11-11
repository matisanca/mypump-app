import SwiftUI
import MyPumpModelos
import MyPumpReglas
import MyPumpDatos

// «Tu inicio con Mati» (simplificar, OK de Mati del 11/11): Tu guía, la videollamada de comienzo y «Antes de la
// videollamada» eran tres tarjetas del mismo camino que podían salir juntas arriba de Entreno. Ahora van en una sola, en el
// lugar de la videollamada. Adentro, las vistas de siempre (`TarjetaGuiaDestacada`, `TarjetaVideollamadaEntreno`,
// `ListaPreviaBloque`, `TarjetaGuia`), en este orden:
// · la guía GRANDE con su avance mientras falte ver algo (o haya un video nuevo de Mati): es lo primero;
// · la videollamada de comienzo (con la lista previa adentro) o «Elegí tu horario» (palanca `elegir_horario`). Cuando ya
//   se puede entrar, va arriba de todo: ese día lo urgente es entrar;
// · la lista previa sola, sin videollamada (palanca `lista_previa`);
// · con todo visto, una fila discreta «Tu guía», durante 7 días desde que se terminó (`ModeloGuia.filaEnInicio`); después la
//   guía queda en Mis datos.
// Una videollamada de REVISIÓN no es parte del inicio: va con su tarjeta propia, como antes. La bienvenida de la guía,
// «Ocultar»/«Quitar de Entreno» y el aviso con «Deshacer» no cambian (viven en `Raiz` y `EntrenoView`).

enum TextosInicioConMati {
    static let titulo = "Tu inicio con Mati"
}

struct TarjetaInicioConMati: View {
    let abrirGuia: () -> Void
    var ocultarGuia: (() -> Void)? = nil
    @State private var app = Proveedor.modelo

    var body: some View {
        // Cada 30 s: la videollamada sube arriba de todo cuando se habilita «Entrar» (la tarjeta de adentro tiene su propio reloj).
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            contenido(ahora: ctx.date)
        }
        // La fecha en que se terminó la guía (para la fila de 7 días): se anota al detectarlo, nunca sale del servidor.
        .task(id: GuiaUI.modelo?.claveCompleta) { GuiaUI.modelo?.anotarCompleta() }
    }

    @ViewBuilder private func contenido(ahora: Date) -> some View {
        let g = GuiaUI.modelo
        let reserva = g?.reservaTarjeta(ahora: ahora)
        let deRevision = reserva?.tipo == .revision
        VStack(alignment: .leading, spacing: Espacio.l) {
            // La de revisión, afuera y como siempre.
            if let g, deRevision { TarjetaVideollamadaEntreno(modelo: g, abrirGuia: abrirGuia) }
            if let g {
                let guiaGrande = g.tarjetaDestacada
                let guiaFila = g.filaEnInicio(ahora: ahora)
                let llamada = !deRevision && (reserva != nil || ofreceHorario(g))
                let lista = ListaPreviaUI.sola(app, guia: g)
                let llamadaPrimero = llamada && reserva.map { ReglasAgenda.estadoEntrar($0, ahora: ahora, desdeMin: g.agenda.entrarDesdeMin) == .habilitado } == true
                if guiaGrande || guiaFila || llamada || lista != nil {
                    VStack(alignment: .leading, spacing: Espacio.s) {
                        encabezado
                        // La videollamada queda en UNA sola posición (si cambiara de rama perdería su estado y cerraría sus
                        // hojas al habilitarse «Entrar»): lo que se mueve es la guía.
                        if guiaGrande && !llamadaPrimero { guia(g) }
                        if llamada { videollamada(g) }
                        if guiaGrande && llamadaPrimero { guia(g) }
                        if let lista { ListaPreviaBloque(vista: lista, sobreVerde: false, conIcono: true, abrirGuia: abrirGuia).padding(Espacio.xs) }
                        if guiaFila { TarjetaGuia(modelo: g, abrir: abrirGuia) }
                    }
                    .padding(Espacio.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .superficieTarjeta(radio: Radio.tarjeta + 4)
                    .overlay {
                        RoundedRectangle(cornerRadius: Radio.tarjeta + 4, style: .continuous)
                            .strokeBorder(Color.marca.opacity(0.45), lineWidth: 1.5)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("inicio-con-mati")
                }
            } else if let lista = ListaPreviaUI.sola(app, guia: nil) {
                // Sin guía (raro: la lista es de la entrega) la lista previa igual se ve, sola, como antes.
                TarjetaListaPrevia(vista: lista, abrirGuia: nil)
            }
        }
    }

    private var encabezado: some View {
        HStack(spacing: Espacio.s) {
            Image(systemName: "flag.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.sobreMarca)
                .frame(width: 34, height: 34)
                .background(Color.marca, in: .circle)
                .accessibilityHidden(true)
            Text(TextosInicioConMati.titulo)
                .font(Archivo.fuente(22, peso: 750, relativoA: .title2))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("inicio-con-mati-titulo")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Espacio.xs)
        .padding(.top, Espacio.xs)
    }

    private func guia(_ g: ModeloGuia) -> some View {
        TarjetaGuiaDestacada(modelo: g, abrir: abrirGuia, ocultar: ocultarGuia)
    }

    private func videollamada(_ g: ModeloGuia) -> some View {
        TarjetaVideollamadaEntreno(modelo: g, listaPrevia: ListaPreviaUI.dentro(app, guia: g), abrirGuia: abrirGuia)
    }

    /// «Agendá tu videollamada» (palanca `elegir_horario`), sin reserva y con horarios libres.
    private func ofreceHorario(_ g: ModeloGuia) -> Bool {
        guard Videollamada.elegirHorario, case .franjas = g.vistaAgenda else { return false }
        return true
    }
}
