import Foundation
import Observation
import os
import UIKit
import MyPumpDatos

/// Todo el arranque de la migración del almacenamiento viejo (la 2.0.0 sale como update de la app Capacitor y tiene que
/// levantar lo que ella dejó en el `localStorage` sin perder nada). Una sola entrada: `arrancar`, que llama
/// `Proveedor.modelo` con la fábrica del modelo.
///
/// 1. **Fase L**, local y sin red, ANTES de crear el modelo: el modelo lee el token del Keychain y su cola del disco al
///    iniciar. Si la Fase L corriera después, arrancaría sin cuenta y mostraría la bienvenida ("pegá tu link") a alguien
///    que ya tenía todo. Solo con `isProtectedDataAvailable`; si no, espera a que se desbloquee.
/// 2. Con la primera carga con red del modelo (la de `RaizApp`): **Fase R** (validar las ops sin sesión contra la rutina
///    activa, reasignar tokens rotados, recibo).
/// 3. **Escritura de vuelta**, una vez: saca del `localStorage` lo que ya tomó la nativa y deja la marca; el arranque
///    siguiente la confirma leyendo el archivo (Ruta B).
///
/// Si alguien vuelve a la Capacitor (TestFlight vencido, reinstalación, plan B) y después a la nativa, la huella de los
/// archivos cambia y se repite. El libro mayor evita duplicados.
@MainActor
enum ArranqueMigracion {
    private static var arrancada = false
    static let entorno = EntornoLegado()

    static var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Corre la Fase L (si corresponde), crea el modelo y deja andando el resto. Una vez por proceso.
    static func arrancar(_ crear: () -> ModeloApp) -> ModeloApp {
        guard !arrancada else { return crear() }
        arrancada = true
        var hecha = false
        if datosProtegidos {
            hecha = faseLocal(cuentaViva: nil) != nil
        } else {
            RegistroLegado.anotar("arranque con datos protegidos: la Fase L espera al desbloqueo")
        }
        let modelo = crear()
        Task { await seguir(modelo, faseLocalHecha: hecha) }
        return modelo
    }

    /// `UIApplication.shared` sin trampa: en `App.init()` todavía no existe (medido en iOS 26.5: da nil por KVC) y la
    /// propiedad de Swift no es opcional. Sin app no se asume nada: la Fase L espera.
    private static var datosProtegidos: Bool {
        (UIApplication.value(forKey: "sharedApplication") as? UIApplication)?.isProtectedDataAvailable ?? false
    }

    /// nil = falló la lectura (se reintenta en el arranque siguiente; no es lo mismo que "no había nada").
    @discardableResult
    private static func faseLocal(cuentaViva: String?) -> EjecutorLegado.Resultado? {
        do {
            let r = try EjecutorLegado.faseLocal(entorno: entorno, almacen: TokenEnKeychain(), ajustes: .standard, cuentaViva: cuentaViva)
            if r.corrio {
                RegistroLegado.anotar("Fase L corrida \(r.corrida)\(r.repeticion ? " (repetición)" : ""): token \(r.adoptoToken ? "adoptado" : "sin cambios"), "
                    + "cola \(r.aLaCola), por validar \(r.porValidar), estacionadas \(r.estacionadas), anon \(r.anon), ya en el libro \(r.yaEnElLibro), "
                    + "reemplazadas \(r.reemplazadas), escritura confirmada \(r.escrituraConfirmada.map(String.init) ?? "no")")
            }
            return r
        } catch {
            RegistroLegado.anotar("Fase L falló: \(error)")
            return nil
        }
    }

    private static func seguir(_ modelo: ModeloApp, faseLocalHecha: Bool) async {
        // La copia cruda se borra 90 días después de que el servidor confirme el recibo (con el recibo solo en disco, nunca).
        FaseRemotaLegado.podarCopias(entorno: entorno)
        if !faseLocalHecha {
            while !datosProtegidos { try? await Task.sleep(for: .seconds(2)) }
            // El modelo ya existe: si tiene cuenta, su cola está viva y la Fase L no le escribe el archivo.
            if let r = faseLocal(cuentaViva: modelo.token), r.adoptoToken, let t = r.tokenVigente, modelo.token != t {
                await modelo.entrar(con: t)
            }
        }
        let recibos = entorno.carpeta.appendingPathComponent("recibos")
        while FaseRemotaLegado.hayPendiente(entorno: entorno) {
            await esperarCargaConRed(modelo)
            guard let token = modelo.token, let info = modelo.info, let cola = modelo.outbox else { await cambio(modelo); continue }
            // La palanca remota (nativa_001). Sin poder leerla se espera, como sin red; sin la tabla vale la de fábrica.
            guard let palanca = await PalancaRemota.leer(modelo.cliente) else { await esperarOtraCarga(modelo); continue }
            if !palanca.opsLegadas, FaseRemotaLegado.faseRPendiente(entorno: entorno) {
                RegistroLegado.anotar("Fase R en pausa por la palanca remota: se reintenta con la próxima carga")
                await esperarOtraCarga(modelo)
                continue
            }
            let r = await FaseRemotaLegado.correr(entorno: entorno, token: token, clienteId: info.clienteId, cliente: modelo.cliente,
                                                  outbox: cola, recibo: ReciboEnServidor(cliente: modelo.cliente, carpeta: recibos),
                                                  conteos: ConteosRPC(cliente: modelo.cliente), app: version)
            if r.corrio {
                RegistroLegado.anotar("Fase R: cola \(r.aLaCola), para revisar \(r.paraRevisar), reasignadas \(r.reasignadas), reemplazadas "
                    + "\(r.reemplazadas), no resuelven \(r.noResuelven), otro cliente \(r.otroCliente), swaps sin migrar \(r.swapsSinMigrar), "
                    + "recibo \(r.recibo?.rawValue ?? "-")"
                    + (r.sinRed ? ", sin red: queda pendiente" : ""))
            }
            if r.sinRed {
                // Se reintenta con la próxima carga con red del modelo, no antes.
                await esperarOtraCarga(modelo)
                continue
            }
            if palanca.escrituraVuelta {
                await escribirDeVuelta()
            } else {
                RegistroLegado.anotar("escritura de vuelta en pausa por la palanca remota: se reintenta en el arranque siguiente")
            }
            break
        }
        // Los recibos que quedaron solo en el disco (antes de la nativa_001, o sin red), otra vez al servidor.
        if ReciboEnServidor.hayPendientes(carpeta: recibos) {
            await esperarCargaConRed(modelo)
            if let token = modelo.token, let info = modelo.info {
                let n = await FaseRemotaLegado.reenviarRecibos(entorno: entorno, token: token, clienteId: info.clienteId, cliente: modelo.cliente)
                if n > 0 { RegistroLegado.anotar("recibos reenviados y confirmados: \(n)") }
            }
        }
    }

    /// La Fase R necesita el primer `get_cliente_info` que contestó: el modelo listo, sin copia offline y fuera de la demo.
    /// No dispara cargas: `get_cliente_info` anota una apertura y eso lo decide la app (RaizApp), no la migración.
    private static func esperarCargaConRed(_ m: ModeloApp) async {
        while !(m.fase == .listo && !m.desdeCache && !m.esDemo && m.info != nil) {
            await cambio(m)
        }
    }

    private static func esperarOtraCarga(_ m: ModeloApp) async {
        // Primero que salga de "listo" (empezó otra carga) y después que vuelva con red.
        while m.fase == .listo { await cambio(m) }
        await esperarCargaConRed(m)
    }

    private static func cambio(_ m: ModeloApp) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = (m.fase, m.desdeCache, m.esDemo, m.info)
            } onChange: {
                c.resume()
            }
        }
    }

    private static func escribirDeVuelta() async {
        guard let cambios = FaseRemotaLegado.escrituraPendiente(entorno: entorno, app: version) else { return }
        // Hace falta una ventana para el WebView (oculto): con la app en segundo plano, se espera.
        while UIApplication.shared.applicationState != .active { try? await Task.sleep(for: .seconds(2)) }
        do {
            let resultado = try await EscritorLegado().escribir(cambios)
            FaseRemotaLegado.registrarEscritura(entorno: entorno, cambios: cambios, resultado: resultado)
            let porEstado = Dictionary(grouping: resultado.values, by: { $0 }).mapValues(\.count)
            RegistroLegado.anotar("escritura de vuelta, corrida \(cambios.corrida): \(porEstado.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))")
        } catch {
            RegistroLegado.anotar("escritura de vuelta falló: \(error) (se reintenta en el arranque siguiente)")
        }
    }
}

/// `legado/registro.log`: qué hizo la migración, sin tokens ni contenido (para el diagnóstico y la prueba en el
/// simulador). Tope de 200 KB.
enum RegistroLegado {
    private static let log = Logger(subsystem: "com.pumpteam.mypump", category: "legado")

    static func anotar(_ texto: String) {
        log.notice("\(texto, privacy: .public)")
        let url = EntornoLegado().carpeta.appendingPathComponent("registro.log")
        let linea = "\(ISO8601DateFormatter().string(from: Date())) \(texto)\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            if (try? h.seekToEnd()) ?? 0 > 200_000 { try? h.truncate(atOffset: 0) }
            try? h.write(contentsOf: Data(linea.utf8))
        } else {
            try? Data(linea.utf8).write(to: url)
        }
    }
}
