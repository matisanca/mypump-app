import Foundation
import MyPumpModelos
import MyPumpReglas

// Los alimentos que el cliente suma a una comida del plan (2.0.3, D1: el pedido de un alumno con capturas de
// MyFitnessPal: «comí 80 g de puré de zapallo y no lo pude cargar», «el huevo lo tuve que poner en extras»). Van dentro
// del ajuste de esa comida y de ese día (`AjusteComida.agregados`), así que viajan con el resto del ajuste: en el teléfono,
// por la cola (`ajustes_dieta`, una op por día) y en `mypump_ajustes_dieta`. La cuenta es de `AgregadosComida`.

extension ModeloApp {
    nonisolated static let archivoRecientes = "agregados_recientes.json"
    /// Cuántos recientes se guardan.
    nonisolated static let maximoRecientes = 12

    /// Los recientes del teléfono (de cualquier día). La demo no tiene carpeta: los suyos duran hasta la próxima carga.
    func cargarRecientes() {
        agregadosRecientes = disco?.leer([AlimentoAgregado].self, Self.archivoRecientes) ?? []
    }

    /// Lo último agregado va primero (un mismo alimento una sola vez, con la última cantidad).
    public func recordarReciente(_ a: AlimentoAgregado) {
        var r = agregadosRecientes.filter { $0.nombre.lowercased() != a.nombre.lowercased() }
        r.insert(a, at: 0)
        agregadosRecientes = Array(r.prefix(Self.maximoRecientes))
        if !esDemo { _ = disco?.guardar(agregadosRecientes, Self.archivoRecientes) }
    }

    /// Saca un agregado de una comida de hoy (los tildes de «Comí» los corre `ajustar`, por `_ts`). Se busca por `_ts` en
    /// el ajuste de AHORA: dos toques seguidos en «Sacar» no borran otro.
    public func borrarAgregado(_ comidaId: String, ts: Int64, opciones: [String: Int]) async {
        guard var a = ajustesDeHoy[comidaId], let j = a.agregados.firstIndex(where: { $0.ts == ts }) else { return }
        a.agregados.remove(at: j)
        await ajustar(comidaId, a, opciones: opciones)
    }

    /// Cambiaron los agregados de una comida marcada «Comí»: sus tildes siguen a cada agregado (por `_ts`). Va antes de
    /// cualquier espera (la marca cambia en memoria al toque), así dos cambios seguidos no leen una marca vieja.
    func seguirTildes(_ comidaId: String, antes: [AlimentoAgregado], despues: [AlimentoAgregado]) async {
        guard antes.map(\.ts) != despues.map(\.ts), let m = marcasDeHoy[comidaId], m.estado == .comido,
              let c = comidasDelDia.first(where: { $0.id == comidaId }) else { return }
        let o = ConsumoDelDia.opcionDeLaMarca(c, m) ?? 0
        let n = c.opciones.indices.contains(o) ? c.opciones[o].alimentos.count : 0
        let excluidos = AgregadosComida.excluidosTrasCambio(m.excluidos, alimentosPlan: n, antes: antes.map(\.ts), despues: despues.map(\.ts))
        if excluidos != m.excluidos {
            await cambiarMarca(comidaId, MarcaComida(opcion: m.opcion, estado: .comido, excluidos: excluidos), opcionAlDesmarcar: m.opcion)
        }
    }
}
