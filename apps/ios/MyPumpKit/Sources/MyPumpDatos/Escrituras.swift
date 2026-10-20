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
    /// La de la cuenta: la comparte con la pantalla de Entreno (`ModeloEntreno.asegurarSesion`).
    let sesiones: SesionesDelDia

    let verificacion: VerificacionToken

    public init(cliente: ClienteRPC, token: String, sesiones: SesionesDelDia = SesionesDelDia()) {
        self.cliente = cliente; self.token = token; self.sesiones = sesiones; self.verificacion = VerificacionToken()
    }

    /// Ejecuta la op y, si no se guardó, mira una vez si el token cayó (arreglo nativo n.º 3): un token revocado hace que
    /// la base devuelva vacío a TODO, y sin esto la cola abandonaría todo lo del cliente en ~1 minuto. Con el token caído
    /// las ops quedan estacionadas sin gastar intentos hasta que entre con un link nuevo: si es de la misma persona, su
    /// cuenta las adopta (`CuentasDelTelefono`, hallazgo 4).
    public func ejecutar(_ op: Operacion) async -> ResultadoOp {
        let r = await ejecutarSinVerificar(op)
        guard case .respuesta(let res) = r else { return r }
        let noGuardado: Bool
        switch res {
        case .success(let j): noGuardado = !Outbox.seGuardo(j)
        case .failure(let e): noGuardado = e.clase == .permanente && e.codigo != "KIND_DESCONOCIDO"
        }
        if noGuardado, await verificacion.cayo(cliente: cliente, token: token) { return .tokenCaido }
        return r
    }

    func ejecutarSinVerificar(_ op: Operacion) async -> ResultadoOp {
        let p = op.payload
        let t: JSONValue = .texto(token)
        switch op.kind {
        case "carga":
            let sid: String
            switch await resolverSesion(p) {
            case .success(let s): sid = s
            case .failure(let e): return .respuesta(.failure(e))
            }
            let d = p["datos"] ?? .objeto([:])
            return .respuesta(await cliente.llamar("mypump_registrar_carga", [
                "p_token": t, "p_sesion_id": .texto(sid), "p_dia_id": d["diaId"] ?? .null, "p_ejercicio_id": d["ejercicioId"] ?? .null,
                "p_ejercicio_nombre": d["ejercicioNombre"] ?? .null, "p_serie": d["serie"] ?? .null, "p_peso": d["peso"] ?? .null,
                "p_reps": d["reps"] ?? .null, "p_rir": d["rir"] ?? .null, "p_notas": d["notas"] ?? .null,
            ]))
        case "estado":
            let sid: String
            switch await resolverSesion(p) {
            case .success(let s): sid = s
            case .failure(let e): return .respuesta(.failure(e))
            }
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
        case ModeloApp.kindAjustes:
            // Los ajustes de porciones del día (nativa_004). TRUE = guardado o borrado; NULL = el token no sirve.
            return .respuesta(Self.sinTablaEsHecho(await cliente.llamar("mypump_guardar_ajustes_dieta", [
                "p_token": t, "p_fecha": p["fecha"] ?? .null, "p_dieta_id": p["dietaId"] ?? .null, "p_tipo_dia": p["tipoDia"] ?? .null,
                "p_ajustes": p["ajustes"] ?? .objeto([:]), "p_resumen": p["resumen"] ?? .null,
                "p_kcal_plan": p["kcalPlan"] ?? .null, "p_kcal_dia": p["kcalDia"] ?? .null,
            ])))
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
            // Arreglo nativo n.º 4: si el mensaje ya llegó (se mandó, se cortó la señal antes de la respuesta y la cola lo
            // reintenta), no se manda de nuevo. El servidor deduplica el mismo texto dentro de 2 minutos (mig 075), pero
            // un reintento puede llegar mucho después. Solo un reintento (o lo que vino de la app vieja, que pudo haberlo
            // mandado): la primera vez no pudo haber llegado, y mirar igual descartaba un "dale" repetido (hallazgo 7).
            if op.intentada == true || op.legado == true,
               let id = await yaLlego(p["contenido"]?.comoTexto, desde: op.ts, despuesDe: p["desde"]?.comoTexto) {
                return .respuesta(.success(.texto(id)))
            }
            return .respuesta(await cliente.llamar("mypump_agregar_comentario", [
                "p_token": t, "p_ambito": .texto("general"), "p_referencia_id": .null, "p_referencia_nombre": .null,
                "p_contenido": p["contenido"] ?? .null,
            ]))
        case "consentimiento_ia":
            // D7 se sacó el 14-oct (Mati: la IA no es algo que el cliente acepte). La app ya no lo encola; esto vacía lo que
            // haya quedado en una cola de la 101/102. Solo registra lo que se eligió: nada del servidor lo lee.
            return .respuesta(await cliente.llamar("mypump_guardar_consentimiento_ia", [
                "p_token": t, "p_acepta": p["acepta"] ?? .null, "p_plataforma": p["plataforma"] ?? .null, "p_app": p["app"] ?? .null,
            ]))
        case SustitucionesServidor.kindGuardar:
            // TRUE también si el servidor tenía algo más nuevo. FALSE = la rutina ya no es del cliente: no hay nada que
            // guardar (cuenta como hecho).
            return .respuesta(Self.sinTablaEsHecho(await cliente.llamar("mypump_save_exercise_swap", [
                "p_token": t, "p_rutina_id": p["rutinaId"] ?? .null, "p_ex_id": p["exId"] ?? .null, "p_swap": p["swap"] ?? .null,
            ])))
        case SustitucionesServidor.kindBorrar:
            // Deja la lápida con la hora del borrado (gana lo más nuevo).
            return .respuesta(Self.sinTablaEsHecho(await cliente.llamar("mypump_delete_exercise_swap", [
                "p_token": t, "p_rutina_id": p["rutinaId"] ?? .null, "p_ex_id": p["exId"] ?? .null, "p_ts": p["ts"] ?? .null,
            ])))
        default:
            // Un kind desconocido no se descarta: va a fallidos (arreglo nativo #2).
            return .respuesta(.failure(ErrorRPC(clase: .permanente, status: 0, codigo: "KIND_DESCONOCIDO", mensaje: op.kind)))
        }
    }

    /// SER-14: sin la migración 003 en la base (PGRST202), la sustitución vive solo en el teléfono, como antes: la op se da
    /// por hecha (si no, gastaría intentos y terminaría en "no se guardó"). Lo del teléfono sube en la primera
    /// sincronización con la tabla ya creada.
    static func sinTablaEsHecho(_ r: Result<JSONValue, ErrorRPC>) -> Result<JSONValue, ErrorRPC> {
        if case .failure(let e) = r, e.funcionInexistente { return .success(.texto("sin tabla")) }
        return r
    }

    /// ¿Hay en el hilo un mensaje del cliente con ese texto, escrito después de encolar este? Devuelve su id. Con
    /// `despuesDe` (el último mensaje que el teléfono conocía al encolar, hora del servidor; "" si el hilo estaba vacío) se
    /// compara reloj del servidor contra reloj del servidor: con el del teléfono atrasado, un mensaje igual de hasta una
    /// hora antes contaba como este y el nuevo no salía nunca (revisión del 15-oct, hallazgo 7). Sin él (lo que vino de
    /// la app vieja, o un hilo que nunca cargó), desde que se encoló con un minuto de margen. Sin red, se manda igual y
    /// decide la cola.
    func yaLlego(_ contenido: String?, desde ts: Double, despuesDe: String?) async -> String? {
        guard let contenido, !contenido.isEmpty,
              case .success(let filas) = await cliente.filas("mypump_get_chat", ["p_token": .texto(token), "p_antes": .null, "p_limite": .numero(10)],
                                                             como: MensajeChat.self)
        else { return nil }
        let limite = despuesDe.map(FechaISO.ms)
        return filas.first { f in
            guard f.autor == "cliente", f.contenido == contenido else { return false }
            if let limite { return FechaISO.ms(f.createdAt) > limite }
            return FechaISO.ms(f.createdAt) >= ts - 60_000
        }?.id
    }

    /// `resolveSesion` (cliente.html:2698): la sesión capturada al encolar, o la de ESE día y semana, o se crea. "No pude
    /// preguntar" no es "no existe": con un fallo de red se devuelve ese error (la cola corta sin gastar intento) y nunca
    /// se crea una segunda sesión, que partiría las series del día. Si la base no da sesión (sin rutina activa, token
    /// revocado), es un rechazo: gasta intento y la cola sigue con las demás, como la web.
    func resolverSesion(_ p: JSONValue) async -> Result<String, ErrorRPC> {
        if let s = p["sesionId"]?.comoTexto, !s.isEmpty { return .success(s) }
        guard let dia = p["diaId"]?.comoTexto else {
            return .failure(ErrorRPC(clase: .permanente, status: 0, codigo: "SIN_DIA", mensaje: "op sin diaId"))
        }
        let semana = p["semana"] ?? .null
        let clave = SesionesDelDia.clave(dia: dia, semana: semana.comoNumero)
        if let s = await sesiones.leer(clave) { return .success(s) }
        // Si la pantalla ya la está creando (la primera serie del día), no se pregunta: se espera esa misma llamada.
        if await !sesiones.enVuelo(clave) {
            switch await cliente.llamar("mypump_get_sesion_dia", ["p_token": .texto(token), "p_dia_id": .texto(dia), "p_semana": semana]) {
            case .failure(let e):
                return .failure(e)
            case .success(let r):
                if case .lista(let filas) = r, let id = filas.first?["id"]?.comoTexto {
                    await sesiones.guardar(clave, id)
                    return .success(id)
                }
            }
        }
        let (cliente, token) = (cliente, token)
        let r = await sesiones.iniciar(clave, usarResueltas: true) {
            await cliente.llamar("mypump_iniciar_sesion", ["p_token": .texto(token), "p_dia_id": .texto(dia), "p_semana": semana])
        }
        switch r {
        case .failure(let e):
            return .failure(e)
        case .success(let id):
            if let s = JS.verdadero(id.comoTexto) { return .success(s) }
            return .failure(ErrorRPC(clase: .permanente, status: 200, codigo: "SIN_SESION", mensaje: "mypump_iniciar_sesion: vacío"))
        }
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

/// "¿Cayó el token?" una vez por minuto como mucho: un `get_cliente_info` que devuelve `[]` es un token revocado. Sin red
/// no se sabe: se asume que no (decide la cola).
actor VerificacionToken {
    private var ultima: (cuando: Date, cayo: Bool)?

    func cayo(cliente: ClienteRPC, token: String) async -> Bool {
        if let u = ultima, Date().timeIntervalSince(u.cuando) < 60 { return u.cayo }
        guard case .success(let r) = await cliente.llamar("mypump_get_cliente_info", ["p_token": .texto(token)]) else { return false }
        let cayo: Bool = if case .lista(let filas) = r { filas.isEmpty } else { r == .null }
        ultima = (Date(), cayo)
        return cayo
    }
}

/// La sesión del día por día y semana, de una cuenta: las que ya se resolvieron y la creación en vuelo. La comparten la
/// cola (`Escrituras.resolverSesion`) y la pantalla de Entreno (`ModeloEntreno.asegurarSesion`): al confirmar la primera
/// serie salen las dos a la vez y cada una mandaba su `iniciar_sesion`. La web comparte la promesa en vuelo
/// (`_sesionInflight`); acá también (revisión del 15-oct, hallazgo 5).
public actor SesionesDelDia {
    private var resueltas: [String: String] = [:]
    private var vuelos: [String: Task<Result<JSONValue, ErrorRPC>, Never>] = [:]

    public init() {}

    /// `"<día>|<semana>"`, con la semana como la escribe JS (la clave de `_sesionPorDia` de la web).
    static func clave(dia: String, semana: Double?) -> String { "\(dia)|\(AnclajeSwaps.numeroJS(semana))" }

    func leer(_ k: String) -> String? { resueltas[k] }
    func guardar(_ k: String, _ id: String) { resueltas[k] = id }
    func enVuelo(_ k: String) -> Bool { vuelos[k] != nil }

    /// `iniciar_sesion` una sola vez por clave: si ya hay una creación en vuelo, se espera esa; si no, sale `crear`. Lo
    /// que devuelve queda resuelto para la cola. La pantalla no lee lo resuelto (`usarResueltas: false`): confirma su
    /// sesión con el servidor al restaurar, y una que el servidor archivó en el medio no tiene que volver por acá.
    func iniciar(_ k: String, usarResueltas: Bool,
                 _ crear: @escaping @Sendable () async -> Result<JSONValue, ErrorRPC>) async -> Result<JSONValue, ErrorRPC> {
        if usarResueltas, let id = resueltas[k] { return .success(.texto(id)) }
        if let vuelo = vuelos[k] { return await vuelo.value }
        let vuelo = Task { await crear() }
        vuelos[k] = vuelo
        let r = await vuelo.value
        vuelos[k] = nil
        if case .success(let v) = r, let id = JS.verdadero(v.comoTexto) { resueltas[k] = id }
        return r
    }
}

extension AnclajeSwaps {
    /// Como `numeroJS` pero el 0 se imprime "0" (no es el `|| 0` de la huella: acá es el valor tal cual).
    static func numeroJSConCero(_ d: Double) -> String { d == 0 ? "0" : numeroJS(d) }
}
