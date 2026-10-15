import Foundation
import Observation
import MyPumpModelos
import MyPumpReglas

/// Una tarjeta de Progreso: un ejercicio (agrupado por clave entre los días donde aparece) con su resumen y las filas
/// para el detalle.
public struct TarjetaProgreso: Identifiable, Equatable, Sendable {
    public let id: String
    public let nombre: String
    public let clave: String
    /// "Tirón · Piernas": los días donde aparece, en el orden de la rutina.
    public let dias: String
    public let resumen: ProgresoEjercicio.Resumen
    /// Las filas tal cual vinieron (de la más nueva a la más vieja): el detalle muestra 8.
    public let filas: [RegistroHistorico]
}

/// Progreso (`loadProgressAndRender`): UN pedido con todas las claves del plan (48 filas por clave); si la RPC por
/// clave no existe (PGRST202) se cae al camino viejo por lugar; si se cortó la red se avisa y se reintenta al volver.
@MainActor @Observable
public final class ModeloProgreso {
    public enum Estado: Equatable, Sendable { case cargando, listo, sinRed }

    public private(set) var estado: Estado = .cargando
    public private(set) var tarjetas: [TarjetaProgreso] = []
    public private(set) var sesiones = 0
    /// Lo traído por clave, para que Entreno use el mismo historial (última vez y récord).
    public private(set) var historialPorClave: [String: [RegistroHistorico]] = [:]

    @ObservationIgnored let cliente: ClienteRPC
    @ObservationIgnored let token: String

    public init(cliente: ClienteRPC, token: String) {
        self.cliente = cliente; self.token = token
    }

    /// `nombreEfectivo` da el nombre que se está haciendo (el del sustituto si el ejercicio está sustituido).
    public func cargar(rutina: RutinaActiva?, nombreEfectivo: (Ejercicio) -> String = { $0.nombre }) async {
        estado = .cargando
        guard let dias = rutina?.estructura.dias else { tarjetas = []; sesiones = 0; estado = .listo; return }
        // Una entrada por clave del ejercicio efectivo, con los días donde aparece.
        struct Entrada { var id: String; var ids: [String]; var clave: String; var nombre: String; var dias: [String] }
        var orden: [String] = []
        var porClave: [String: Entrada] = [:]
        for (i, d) in dias.enumerated() {
            let diaNombre = d.nombre.flatMap { $0.isEmpty ? nil : $0 } ?? "Día \(d.n ?? (i + 1))"
            for b in d.bloques {
                for ex in b.ejercicios where ex.tipo != "calentamiento" {
                    let nombre = nombreEfectivo(ex)
                    let c = ClaveEjercicio.de(nombre)
                    let clave = c.isEmpty ? ex.id : c
                    if var e = porClave[clave] {
                        if !e.dias.contains(diaNombre) { e.dias.append(diaNombre) }
                        e.ids.append(ex.id)
                        porClave[clave] = e
                    } else {
                        porClave[clave] = Entrada(id: ex.id, ids: [ex.id], clave: clave, nombre: nombre, dias: [diaNombre])
                        orden.append(clave)
                    }
                }
            }
        }
        let entradas = orden.compactMap { porClave[$0] }
        var filasPor: [String: [RegistroHistorico]] = [:]
        switch await cliente.filas("mypump_get_historico_por_clave", ["p_token": .texto(token), "p_claves": .lista(entradas.map { .texto($0.clave) }),
                                                                      "p_limit_por_ej": .numero(48)], como: RegistroHistorico.self) {
        case .success(let filas):
            for f in filas { if let c = f.clave { filasPor[c, default: []].append(f) } }
        case .failure(let e) where e.funcionInexistente:
            // La 072 sin aplicar: el camino viejo por id de lugar (24 filas).
            if case .success(let filas) = await cliente.filas("mypump_get_historico_ejercicios", [
                "p_token": .texto(token), "p_ejercicio_ids": .lista(entradas.map { .texto($0.id) }), "p_limit_por_ej": .numero(24),
            ], como: RegistroHistorico.self) {
                let claveDeId = Dictionary(entradas.map { ($0.id, $0.clave) }, uniquingKeysWith: { a, _ in a })
                for f in filas { if let id = f.ejercicioId, let c = claveDeId[id] { filasPor[c, default: []].append(f) } }
            }
        case .failure:
            // Sin red: NO se cae al camino por lugar (mezclaría original y sustituto) y se reintenta al volver.
            estado = .sinRed
            return
        }
        historialPorClave = filasPor
        // Las cuentas (la fecha local de cada fila) fuera del hilo principal: con el historial más largo que deja el
        // servidor (48 filas por ejercicio) son unos 0,25 s, y la pestaña se trababa al abrirla (15-oct).
        let pedidas = entradas.map { ($0.id, $0.nombre, $0.clave, $0.dias.joined(separator: " · ")) }
        let traidas = filasPor
        let (nuevas, cuantas) = await Task.detached(priority: .userInitiated) {
            let t = pedidas.compactMap { id, nombre, clave, dias -> TarjetaProgreso? in
                guard let filas = traidas[clave], let r = ProgresoEjercicio.resumen(filas) else { return nil }
                return TarjetaProgreso(id: id, nombre: nombre, clave: clave, dias: dias, resumen: r, filas: filas)
            }
            return (t, ProgresoEjercicio.sesiones(traidas.values.flatMap { $0 }).count)
        }.value
        tarjetas = nuevas
        sesiones = cuantas
        estado = .listo
    }
}
