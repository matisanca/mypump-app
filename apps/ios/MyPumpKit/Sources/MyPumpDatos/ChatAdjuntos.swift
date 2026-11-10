import Foundation
import MyPumpModelos
import MyPumpReglas

/// Una URL firmada de `/chat/urls` (dura 1 h; se usa 50 minutos) con el formato real del archivo.
struct FirmaAdjunto: Sendable {
    let url: URL
    let mime: String
    let vence: Date
}

/// Fotos y audios en el chat con Mati (2.3.0, `nativa_chat_adjuntos`). Cada adjunto tiene un id que pone el teléfono:
/// es el nombre del archivo, la clave de la cola y lo que mini-vision usa para no guardarlo dos veces. La burbuja aparece
/// al instante («Enviando…») y sale por el carril de archivos de la cola (`Outbox.pasadaAudios`): sin señal espera sin
/// gastar intentos y nada se pierde. Lo que el servidor guarda es una fila del chat con «Foto» o «Audio de 0:42».
extension ModeloChat {
    nonisolated public static let kindAdjunto = "chat_adjunto"
    /// La carpeta de la cuenta donde esperan los archivos y quedan los que ya se vieron.
    nonisolated public static let carpetaAdjuntosNombre = "chat-adjuntos"

    nonisolated static func claveAdjunto(_ id: String) -> String { "\(kindAdjunto)_\(id)" }

    // MARK: - Si se muestra

    /// Con la palanca prendida pregunta al servidor si este cliente los tiene (`mypump_chat_adjuntos_estado`). Sin red
    /// queda lo último que se supo: con la palanca prendida, sin señal en el gimnasio igual se puede mandar (sale después).
    public func consultarAdjuntos(palanca: Bool) async {
        guard palanca, carpetaAdjuntos != nil else { adjuntosActivos = false; return }
        switch await cliente.llamar("mypump_chat_adjuntos_estado", ["p_token": .texto(token)]) {
        case .success(let j):
            ponerEstado(habilitado: j["habilitado"] == .bool(true), audioMax: j["audio_max_s"]?.comoNumero)
            recordarEstado()
        case .failure(let e) where e.clase == .permanente:
            ponerEstado(habilitado: false, audioMax: nil)   // la función todavía no está en la base
            recordarEstado()
        case .failure:
            if let r = leerEstado() { ponerEstado(habilitado: r.habilitado, audioMax: r.audioMaximo) }
        }
    }

    private struct EstadoGuardado: Codable { var habilitado: Bool; var audioMaximo: Double? }

    private func ponerEstado(habilitado: Bool, audioMax: Double?) {
        adjuntosActivos = habilitado
        if let a = audioMax, a.isFinite, a >= 10 { audioMaximo = min(a, ReglasChatAdjuntos.audioMaximo) } else { audioMaximo = ReglasChatAdjuntos.audioMaximo }
    }

    private func recordarEstado() {
        guard let c = carpetaAdjuntos, let d = try? JSONEncoder().encode(EstadoGuardado(habilitado: adjuntosActivos, audioMaximo: audioMaximo)) else { return }
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        try? d.write(to: c.appendingPathComponent("estado.json"), options: .atomic)
    }

    private func leerEstado() -> EstadoGuardado? {
        guard let c = carpetaAdjuntos, let d = try? Data(contentsOf: c.appendingPathComponent("estado.json")) else { return nil }
        return try? JSONDecoder().decode(EstadoGuardado.self, from: d)
    }

    // MARK: - Mandar

    /// Una foto de la cámara o del carrete (JPEG, HEIC, PNG): se redibuja con el lado mayor en 1600 px, sin EXIF ni GPS,
    /// y sale por la cola. false si no es una imagen que se pueda leer.
    @discardableResult
    public func enviarFoto(_ original: Data) async -> Bool {
        guard adjuntosActivos, let carpeta = carpetaAdjuntos, outbox != nil else { return false }
        var jpeg = ReduccionFoto.jpeg(original, maxPx: ReglasChatAdjuntos.fotoLadoMaximo, calidad: ReglasChatAdjuntos.fotoCalidad)
        if let j = jpeg, j.count > ReglasChatAdjuntos.bytesMaximos {
            jpeg = ReduccionFoto.jpeg(original, maxPx: 1200, calidad: 0.6)   // una muy cargada de detalle
        }
        guard let jpeg, jpeg.count <= ReglasChatAdjuntos.bytesMaximos else { avisar(ReglasChatAdjuntos.textoFotoIlegible); return false }
        let id = UUID().uuidString.lowercased()
        let destino = carpeta.appendingPathComponent("\(id).jpg")
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            try jpeg.write(to: destino, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            avisar(ReglasChatAdjuntos.textoFotoIlegible)
            return false
        }
        await encolarAdjunto(id: id, tipo: .foto, segundos: nil, archivo: destino)
        return true
    }

    /// Un audio grabado (AAC en m4a). Se mueve a la carpeta de la cuenta con el nombre del id. Menos de 1 segundo no sale.
    @discardableResult
    public func enviarAudio(archivo: URL, segundos: Double) async -> Bool {
        guard adjuntosActivos, let carpeta = carpetaAdjuntos, outbox != nil else { try? FileManager.default.removeItem(at: archivo); return false }
        guard segundos.isFinite, segundos >= ReglasChatAdjuntos.audioMinimo else {
            try? FileManager.default.removeItem(at: archivo)
            avisar(ReglasChatAdjuntos.textoMuyCorto)
            return false
        }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: archivo.path)[.size] as? Int) ?? 0
        guard bytes > 0, bytes <= ReglasChatAdjuntos.bytesMaximos else { try? FileManager.default.removeItem(at: archivo); return false }
        let id = UUID().uuidString.lowercased()
        let destino = carpeta.appendingPathComponent("\(id).m4a")
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: archivo, to: destino)
        } catch {
            return false
        }
        await encolarAdjunto(id: id, tipo: .audio, segundos: min(segundos, audioMaximo).rounded(), archivo: destino)
        return true
    }

    private func encolarAdjunto(id: String, tipo: AdjuntoChat.Tipo, segundos: Double?, archivo: URL) async {
        let ahora = Date()
        let creado = FechaISO.texto(ahora)
        hilo.agregarPendiente(Self.burbujaPendiente(id: id, tipo: tipo, segundos: segundos, creado: creado))
        archivos[id] = archivo
        var payload: [String: JSONValue] = ["id": .texto(id), "tipo": .texto(tipo.rawValue), "archivo": .texto(archivo.lastPathComponent),
                                            "creado": .texto(creado)]
        if let segundos { payload["segundos"] = .numero(segundos) }
        _ = await outbox?.encolar(Self.kindAdjunto, .objeto(payload), dedupeKey: Self.claveAdjunto(id))
    }

    nonisolated static func burbujaPendiente(id: String, tipo: AdjuntoChat.Tipo, segundos: Double?, creado: String, fallo: Bool = false, motivo: String? = nil) -> BurbujaChat {
        BurbujaChat(id: "adj_\(id)", autor: "cliente",
                    contenido: tipo == .foto ? ReglasChatAdjuntos.textoFoto : ReglasChatAdjuntos.textoAudio(segundos: segundos),
                    leidoPorCliente: nil, createdAt: creado, pendiente: true, fallo: fallo,
                    adjunto: AdjuntoChat(id: id, tipo: tipo, duracion: segundos), motivoFallo: motivo)
    }

    // MARK: - Lo que dice la cola

    /// Lo que quedó en la cola de antes (la app cerrada sin señal): las burbujas «Enviando…» y «No salió» vuelven al hilo.
    /// Los archivos de más de 14 días que nadie nombra se borran (si se vuelven a ver, se bajan de nuevo).
    public func cargarAdjuntosDeLaCola() async {
        guard let outbox, let carpeta = carpetaAdjuntos else { return }
        // La carpeta se lista ANTES de leer la cola: lo que entra en el medio ya está nombrado.
        let presentes = (try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let ops = await outbox.operaciones.filter { $0.kind == Self.kindAdjunto }
        let fallidos = await outbox.fallidos.filter { $0.op.kind == Self.kindAdjunto }
        for op in ops { restaurar(op, fallo: false, motivo: nil) }
        for f in fallidos where !ops.contains(where: { $0.dedupeKey == f.op.dedupeKey }) { restaurar(f.op, fallo: true, motivo: f.motivo) }
        let nombrados = Set((ops + fallidos.map(\.op)).compactMap { $0.payload["archivo"]?.comoTexto })
        let limite = Date().addingTimeInterval(-ReglasChatAdjuntos.diasEnElTelefono * 86_400)
        for u in presentes where u.lastPathComponent != "estado.json" && !nombrados.contains(u.lastPathComponent) {
            let fecha = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if fecha < limite {
                try? FileManager.default.removeItem(at: u)
                archivos = archivos.filter { $0.value != u }
            } else if let id = Self.idDeArchivo(u.lastPathComponent) {
                archivos[id] = u
            }
        }
    }

    private func restaurar(_ op: Operacion, fallo: Bool, motivo: String?) {
        guard let id = op.payload["id"]?.comoTexto, let tipo = op.payload["tipo"]?.comoTexto.flatMap(AdjuntoChat.Tipo.init(rawValue:)) else { return }
        if let a = op.payload["archivo"]?.comoTexto, let c = carpetaAdjuntos { archivos[id] = c.appendingPathComponent(a) }
        if hilo.tieneAdjunto(id) {
            if fallo { hilo.marcarAdjuntoFallido(id: id, motivo: Self.motivoCorto(motivo)) }
            return
        }
        let creado = op.payload["creado"]?.comoTexto ?? FechaISO.texto(Date(timeIntervalSince1970: op.ts / 1000))
        hilo.agregarPendiente(Self.burbujaPendiente(id: id, tipo: tipo, segundos: op.payload["segundos"]?.comoNumero, creado: creado,
                                                    fallo: fallo, motivo: Self.motivoCorto(motivo)))
    }

    /// El motivo de `Outbox.Fallido` es el código solo cuando fue directo; si no, «abandonada tras 8 intentos».
    nonisolated static func motivoCorto(_ m: String?) -> String? {
        guard let m else { return nil }
        return ReglasChatAdjuntos.codigosDirectos.first { m.hasPrefix($0) }
    }

    nonisolated static func idDeArchivo(_ nombre: String) -> String? {
        let base = (nombre as NSString).deletingPathExtension
        return UUID(uuidString: base) != nil ? base.lowercased() : nil
    }

    /// La cola guardó adjuntos: la burbuja pasa a ser la fila del servidor. El archivo queda en el teléfono (se ve sin
    /// bajarlo de nuevo).
    public func alGuardarAdjuntos(_ ops: [OpGuardada]) {
        for g in ops where g.op.kind == Self.kindAdjunto {
            guard let id = g.op.payload["id"]?.comoTexto else { continue }
            hilo.confirmarAdjunto(id: id, comentarioId: g.respuesta["comentario_id"]?.comoTexto ?? "", createdAt: g.respuesta["created_at"]?.comoTexto)
        }
    }

    /// La cola los dejó en fallidos: «No salió» (con el motivo que guardó la cola).
    public func alAbandonarAdjuntos(_ ops: [Operacion]) async {
        let mias = ops.filter { $0.kind == Self.kindAdjunto }
        guard !mias.isEmpty, let outbox else { return }
        let fallidos = await outbox.fallidos
        for op in mias {
            guard let id = op.payload["id"]?.comoTexto else { continue }
            let motivo = Self.motivoCorto(fallidos.last { $0.op.dedupeKey == op.dedupeKey }?.motivo)
            hilo.marcarAdjuntoFallido(id: id, motivo: motivo)
            if motivo == ReglasChatAdjuntos.codigoTope { avisar(ReglasChatAdjuntos.textoTope) }
        }
    }

    /// «Reintentar»: si sigue en la cola, sale ya; si la cola lo dejó, vuelve a la cola con el mismo archivo (y con otro id
    /// si el anterior resultó ser de otro mensaje). Primero se encola y después se olvida el fallido.
    public func reintentarAdjunto(_ id: String) async {
        guard let outbox else { return }
        let clave = Self.claveAdjunto(id)
        if await outbox.operaciones.contains(where: { $0.dedupeKey == clave }) {
            hilo.desmarcarAdjunto(id: id)
            await outbox.reintentarAudiosAhora()
            return
        }
        guard let f = await outbox.fallidos.last(where: { $0.op.dedupeKey == clave }), case .objeto(var o) = f.op.payload else { return }
        guard Self.motivoCorto(f.motivo) == ReglasChatAdjuntos.codigoId, let carpeta = carpetaAdjuntos,
              let viejo = o["archivo"]?.comoTexto else {
            hilo.desmarcarAdjunto(id: id)
            _ = await outbox.encolar(Self.kindAdjunto, f.op.payload, dedupeKey: clave)
            await outbox.olvidarFallidos(clave: clave)
            return
        }
        let nuevo = UUID().uuidString.lowercased()
        let ext = (viejo as NSString).pathExtension
        let destino = carpeta.appendingPathComponent("\(nuevo).\(ext)")
        guard (try? FileManager.default.moveItem(at: carpeta.appendingPathComponent(viejo), to: destino)) != nil else { return }
        o["id"] = .texto(nuevo); o["archivo"] = .texto(destino.lastPathComponent)
        archivos[id] = nil; archivos[nuevo] = destino
        hilo.desmarcarAdjunto(id: id, nuevoId: nuevo)
        _ = await outbox.encolar(Self.kindAdjunto, .objeto(o), dedupeKey: Self.claveAdjunto(nuevo))
        await outbox.olvidarFallidos(clave: clave)
    }

    /// «Borrar» en uno que no salió: se saca de la cola, del hilo y del teléfono. Nunca llegó a Mati.
    public func descartarAdjunto(_ id: String) async {
        guard let outbox else { return }
        let clave = Self.claveAdjunto(id)
        guard !(await outbox.operaciones.contains { $0.dedupeKey == clave }) else { return }   // sigue saliendo: no se toca
        await outbox.olvidarFallidos(clave: clave)
        if let u = archivos[id] { try? FileManager.default.removeItem(at: u) }
        archivos[id] = nil
        hilo.quitarAdjuntoPendiente(id: id)
    }

    private func avisar(_ t: String) { anuncio = t; anuncios += 1 }

    // MARK: - Ver y escuchar

    /// El archivo en el teléfono, o se baja con una URL firmada (se piden de a muchas y duran 50 minutos). nil = no se
    /// pudo (sin red, o ya no está): la burbuja lo dice y ofrece probar de nuevo.
    public func archivo(de a: AdjuntoChat) async -> URL? {
        if let u = archivos[a.id], FileManager.default.fileExists(atPath: u.path) { return u }
        guard !a.borrado, let carpeta = carpetaAdjuntos else { return nil }
        if let t = bajando[a.id] { return await t.value }
        let t = Task<URL?, Never> { [weak self] in
            guard let self else { return nil }
            guard let firma = await self.firma(de: a.id) else { return nil }
            var pedido = URLRequest(url: firma.url, timeoutInterval: 60)
            pedido.httpMethod = "GET"
            guard let (datos, resp) = try? await self.cliente.transporte.enviar(pedido),
                  (200..<300).contains((resp as? HTTPURLResponse)?.statusCode ?? 0), !datos.isEmpty else { return nil }
            let destino = carpeta.appendingPathComponent("\(a.id).\(Self.extension(de: firma.mime))")
            try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            guard (try? datos.write(to: destino, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil else { return nil }
            return destino
        }
        bajando[a.id] = t
        let u = await t.value
        bajando[a.id] = nil
        if let u { archivos[a.id] = u; sinBajar.remove(a.id) } else { sinBajar.insert(a.id) }
        return u
    }

    /// El formato real (un audio grabado desde la web en Firefox es webm u ogg, que el iPhone no reproduce).
    public func formato(de a: AdjuntoChat) -> String? {
        if let u = archivos[a.id] { return Self.mime(deExtension: u.pathExtension) }
        return firmas[a.id]?.mime
    }

    func firma(de id: String) async -> FirmaAdjunto? {
        if let f = firmas[id], f.vence > Date() { return f }
        await firmar(incluyendo: id)
        return firmas[id].flatMap { $0.vence > Date() ? $0 : nil }
    }

    /// `/chat/urls`: las del hilo que no están en el teléfono ni tienen firma vigente, las más nuevas primero, con `id`
    /// siempre adentro.
    func firmar(incluyendo id: String) async {
        let ahora = Date()
        var ids = [id]
        for a in hilo.adjuntosReales.reversed() where a.id != id && archivos[a.id] == nil && (firmas[a.id]?.vence ?? .distantPast) <= ahora {
            ids.append(a.id)
            if ids.count >= ReglasChatAdjuntos.firmasPorPedido { break }
        }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("chat/urls"), timeoutInterval: 30)
        pedido.httpMethod = "POST"
        pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pedido.httpBody = try? JSONEncoder().encode(JSONValue.objeto(["token": .texto(token), "ids": .lista(ids.map(JSONValue.texto))]))
        guard let (datos, resp) = try? await cliente.transporte.enviar(pedido),
              ((resp as? HTTPURLResponse)?.statusCode ?? 0) < 300,
              let j = try? JSONDecoder().decode(JSONValue.self, from: datos), j["ok"] == .bool(true),
              case .lista(let filas)? = j["adjuntos"] else { return }
        let vence = ahora.addingTimeInterval(ReglasChatAdjuntos.firmaVigente)
        for f in filas {
            guard let i = f["id"]?.comoTexto?.lowercased(), let u = f["url"]?.comoTexto.flatMap(URL.init(string:)) else { continue }
            firmas[i] = FirmaAdjunto(url: u, mime: f["mime"]?.comoTexto ?? "", vence: vence)
        }
    }

    static func `extension`(de mime: String) -> String {
        switch mime {
        case "image/jpeg": return "jpg"
        case "audio/webm": return "webm"
        case "audio/ogg": return "ogg"
        default: return "m4a"
        }
    }

    static func mime(deExtension e: String) -> String {
        switch e.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "webm": return "audio/webm"
        case "ogg": return "audio/ogg"
        default: return "audio/mp4"
        }
    }
}

// MARK: - La ejecución en la cola

extension Escrituras {
    /// Donde esperan las fotos y los audios del chat: `chat-adjuntos/` de la cuenta (al lado de `audios/`).
    var carpetaAdjuntosChat: URL {
        carpetaAudios.deletingLastPathComponent().appendingPathComponent(ModeloChat.carpetaAdjuntosNombre, isDirectory: true)
    }

    /// `chat_adjunto`: el archivo crudo a mini-vision (`POST /chat/adjunto`), con el id en un encabezado. Es idempotente:
    /// un reintento de algo que ya entró contesta el mismo mensaje. Sin el archivo, o con un rechazo que no va a cambiar,
    /// va directo a «No salió» sin gastar los 8 intentos.
    func ejecutarAdjuntoChat(_ p: JSONValue) async -> ResultadoOp {
        guard let id = p["id"]?.comoTexto, UUID(uuidString: id) != nil,
              let tipo = p["tipo"]?.comoTexto.flatMap(AdjuntoChat.Tipo.init(rawValue:)),
              let nombre = p["archivo"]?.comoTexto, !nombre.isEmpty, !nombre.contains("/")
        else { return Self.falloAdjunto(ReglasChatAdjuntos.codigoRechazo, "pedido inválido") }
        guard let datos = Self.datosAudio(nombre, en: carpetaAdjuntosChat), !datos.isEmpty else {
            return Self.falloAdjunto(ReglasChatAdjuntos.codigoSinArchivo, "sin archivo")
        }
        guard datos.count <= ReglasChatAdjuntos.bytesMaximos else { return Self.falloAdjunto(ReglasChatAdjuntos.codigoRechazo, "muy grande") }
        var pedido = URLRequest(url: cliente.config.vision.appendingPathComponent("chat/adjunto"), timeoutInterval: 120)
        pedido.httpMethod = "POST"
        pedido.setValue(tipo == .foto ? ReglasChatAdjuntos.mimeFoto : ReglasChatAdjuntos.mimeAudio, forHTTPHeaderField: "Content-Type")
        pedido.setValue(token, forHTTPHeaderField: "x-chat-token")
        pedido.setValue(id.lowercased(), forHTTPHeaderField: "x-chat-id")
        pedido.setValue(tipo.rawValue, forHTTPHeaderField: "x-chat-tipo")
        if tipo == .audio {
            let s = max(1, min(ReglasChatAdjuntos.audioMaximo, (p["segundos"]?.comoNumero ?? 1).rounded()))
            pedido.setValue(String(Int(s)), forHTTPHeaderField: "x-chat-duracion")
        }
        pedido.httpBody = datos
        let cuerpo: Data, respuesta: URLResponse
        do {
            (cuerpo, respuesta) = try await cliente.transporte.enviar(pedido)
        } catch {
            return .respuesta(.failure(ErrorRPC(clase: .red, status: 0, mensaje: "sin respuesta")))
        }
        let status = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        let j = try? JSONDecoder().decode(JSONValue.self, from: cuerpo)
        switch ReglasChatAdjuntos.subida(status: status, ok: j?["ok"] == .bool(true), error: j?["error"]?.comoTexto) {
        case .ok:
            return .respuesta(.success(.objeto([
                "ok": .bool(true), "id": .texto(id), "comentario_id": j?["comentario_id"] ?? .null, "created_at": j?["created_at"] ?? .null,
            ])))
        case .token:
            return .respuesta(.success(.null))   // `ejecutar` mira si cayó el token
        case .reintentar:
            return .respuesta(.failure(ErrorRPC(clase: .transitorio, status: status, mensaje: j?["error"]?.comoTexto ?? "HTTP \(status)")))
        case .tope:
            return Self.falloAdjunto(ReglasChatAdjuntos.codigoTope, "tope", status: status)
        case .idRepetido:
            return Self.falloAdjunto(ReglasChatAdjuntos.codigoId, "id", status: status)
        case .rechazo:
            return Self.falloAdjunto(ReglasChatAdjuntos.codigoRechazo, j?["error"]?.comoTexto ?? "HTTP \(status)", status: status)
        }
    }

    static func falloAdjunto(_ codigo: String, _ mensaje: String, status: Int = 0) -> ResultadoOp {
        .respuesta(.failure(ErrorRPC(clase: .permanente, status: status, codigo: codigo, mensaje: mensaje)))
    }
}
