import Foundation
import MyPumpModelos
import MyPumpReglas

/// Cómo se ejecuta cada `kind` de la cola: las MISMAS RPC y parámetros que el EXEC de la web (cliente.html:2722-2790,
/// supabase-client.js). Las ops que trae la migración del almacenamiento viejo son acciones reales del cliente, así que
/// todos los kinds se ejecutan aunque la nativa ya no genere algunos (por ejemplo `comida`, desde que se sacó
/// "Comí / Salté").
public struct Escrituras: Sendable {
    let cliente: ClienteRPC
    let token: String
    let sesiones: CacheSesiones

    public init(cliente: ClienteRPC, token: String) {
        self.cliente = cliente; self.token = token; self.sesiones = CacheSesiones()
    }

    public func ejecutar(_ op: Operacion) async -> ResultadoOp {
        let p = op.payload
        let t: JSONValue = .texto(token)
        switch op.kind {
        case "carga":
            guard let sid = await resolverSesion(p) else { return .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin sesión todavía"))) }
            let d = p["datos"] ?? .objeto([:])
            return .respuesta(await cliente.llamar("mypump_registrar_carga", [
                "p_token": t, "p_sesion_id": .texto(sid), "p_dia_id": d["diaId"] ?? .null, "p_ejercicio_id": d["ejercicioId"] ?? .null,
                "p_ejercicio_nombre": d["ejercicioNombre"] ?? .null, "p_serie": d["serie"] ?? .null, "p_peso": d["peso"] ?? .null,
                "p_reps": d["reps"] ?? .null, "p_rir": d["rir"] ?? .null, "p_notas": d["notas"] ?? .null,
            ]))
        case "estado":
            guard let sid = await resolverSesion(p) else { return .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin sesión todavía"))) }
            return .respuesta(await cliente.llamar("mypump_marcar_ejercicio_estado", [
                "p_token": t, "p_sesion_id": .texto(sid), "p_dia_id": p["diaId"] ?? .null, "p_ejercicio_id": p["exId"] ?? .null,
                "p_series_objetivo": p["seriesObjetivo"] ?? .null, "p_status": p["status"] ?? .null,
                "p_marcado_manualmente": p["manual"] ?? .bool(false),
            ]))
        case "swap":
            return .respuesta(await cliente.llamar("mypump_save_food_swap", [
                "p_token": t, "p_dieta_id": p["dietaId"] ?? .null, "p_comida_id": p["comidaId"] ?? .null,
                "p_opt_idx": p["optIdx"] ?? .null, "p_food_idx": p["foodIdx"] ?? .null, "p_food_data": p["food"] ?? .null,
            ]))
        case "swap_del":
            // FALSE = no había fila: objetivo cumplido.
            return .respuesta(await cliente.llamar("mypump_delete_food_swap", [
                "p_token": t, "p_dieta_id": p["dietaId"] ?? .null, "p_comida_id": p["comidaId"] ?? .null,
                "p_opt_idx": p["optIdx"] ?? .null, "p_food_idx": p["foodIdx"] ?? .null,
            ]).map { _ in .texto("ok") })
        case "habito":
            return .respuesta(await cliente.llamar("mypump_set_habito", [
                "p_token": t, "p_fecha": p["fecha"] ?? .null, "p_campo": p["campo"] ?? .null, "p_valor": .texto(Self.stringJS(p["valor"])),
            ]))
        case "comida":
            if p["estado"] == nil || p["estado"] == .null {
                return .respuesta(await cliente.llamar("mypump_desmarcar_comida", [
                    "p_token": t, "p_fecha": p["fecha"] ?? .null, "p_comida_id": p["comidaId"] ?? .null,
                ]).map { _ in .texto("ok") })
            }
            var excl: JSONValue = .null
            if case .lista(let a)? = p["excl"], !a.isEmpty { excl = .lista(a) }
            return .respuesta(await cliente.llamar("mypump_marcar_comida", [
                "p_token": t, "p_fecha": p["fecha"] ?? .null, "p_comida_id": p["comidaId"] ?? .null, "p_opcion": p["opcion"] ?? .null,
                "p_estado": p["estado"] ?? .null, "p_foods_excluidos": excl,
            ]))
        case "peso":
            let registro: JSONValue = .objeto(["fecha": p["fecha"] ?? .null, "tipo": .texto("peso_kg"), "valor": p["valor"] ?? .null, "fuente": .texto("manual")])
            return .respuesta(await cliente.llamar("mypump_ingest_salud", ["p_token": t, "p_registros": .lista([registro])]))
        case "checkin":
            let d = p["datos"] ?? .objeto([:])
            let nota = d["nota"].flatMap { AnclajeSwaps.esVerdadero($0) ? $0 : nil } ?? .null
            return .respuesta(await cliente.llamar("mypump_guardar_checkin", [
                "p_token": t, "p_fecha": p["fecha"] ?? .null, "p_energia": d["energia"] ?? .null, "p_descanso": d["descanso"] ?? .null,
                "p_hambre": d["hambre"] ?? .null, "p_adherencia": d["adherencia"] ?? .null, "p_nota": nota,
            ]))
        case "chat":
            return .respuesta(await cliente.llamar("mypump_agregar_comentario", [
                "p_token": t, "p_ambito": .texto("general"), "p_referencia_id": .null, "p_referencia_nombre": .null,
                "p_contenido": p["contenido"] ?? .null,
            ]))
        default:
            // Un kind desconocido no se descarta: va a fallidos (arreglo nativo #2).
            return .respuesta(.failure(ErrorRPC(clase: .permanente, status: 0, codigo: "KIND_DESCONOCIDO", mensaje: op.kind)))
        }
    }

    /// `resolveSesion` (cliente.html:2698): la sesión capturada al encolar, o la de ESE día y semana, o se crea. Si no se
    /// pudo preguntar (red), nil: se reintenta después — crear una segunda sesión partiría las series del día.
    func resolverSesion(_ p: JSONValue) async -> String? {
        if let s = p["sesionId"]?.comoTexto, !s.isEmpty { return s }
        guard let dia = p["diaId"]?.comoTexto else { return nil }
        let semana = p["semana"] ?? .null
        let clave = "\(dia)|\(AnclajeSwaps.numeroJS(semana.comoNumero))"
        if let s = await sesiones.leer(clave) { return s }
        switch await cliente.llamar("mypump_get_sesion_dia", ["p_token": .texto(token), "p_dia_id": .texto(dia), "p_semana": semana]) {
        case .failure:
            return nil
        case .success(let r):
            if case .lista(let filas) = r, let id = filas.first?["id"]?.comoTexto {
                await sesiones.guardar(clave, id)
                return id
            }
        }
        if case .success(let id) = await cliente.llamar("mypump_iniciar_sesion", ["p_token": .texto(token), "p_dia_id": .texto(dia), "p_semana": semana]),
           let s = id.comoTexto {
            await sesiones.guardar(clave, s)
            return s
        }
        return nil
    }

    /// `String(valor)` de JS: null → "null", true → "true", 12 → "12".
    static func stringJS(_ v: JSONValue?) -> String {
        switch v {
        case .none, .some(.null): return "null"
        case .some(.bool(let b)): return b ? "true" : "false"
        case .some(.numero(let d)): return AnclajeSwaps.numeroJSConCero(d)
        case .some(.texto(let s)): return s
        default: return ""
        }
    }
}

actor CacheSesiones {
    private var mapa: [String: String] = [:]
    func leer(_ k: String) -> String? { mapa[k] }
    func guardar(_ k: String, _ v: String) { mapa[k] = v }
}

extension AnclajeSwaps {
    /// Como `numeroJS` pero el 0 se imprime "0" (no es el `|| 0` de la huella: acá es el valor tal cual).
    static func numeroJSConCero(_ d: Double) -> String { d == 0 ? "0" : numeroJS(d) }
}
