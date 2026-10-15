import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Revisión del 15-oct, hallazgo 11: `entrar(con:)` guardaba el token nuevo antes de validarlo y lo borraba al ver `[]`.
/// Un cliente con su cuenta andando que tocaba un link viejo de WhatsApp (nunca usado en ese teléfono, así que no estaba
/// anotado como inválido) quedaba en "pegá tu link" y sin su cuenta. Ahora, con una cuenta que anda, el link nuevo se
/// valida antes de reemplazarla.
@Suite("Un link vencido no saca de la cuenta que anda", .serialized)
@MainActor
struct LinkVencidoTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("link-vencido-\(UUID().uuidString)")
    nonisolated static let tokA = "AAAAAAAAAAAAAAAAAAAA"
    nonisolated static let viejo = "VVVVVVVVVVVVVVVVVVVV"
    nonisolated static let nuevo = "NNNNNNNNNNNNNNNNNNNN"
    nonisolated static let info = #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#

    func modelo(sinRedParaElLink: Bool = false) -> (ModeloApp, TokenEnMemoria, TransporteProgramado) {
        let t = TransporteProgramado { fn, cuerpo in
            let tok = cuerpo["p_token"]?.comoTexto
            if fn == "mypump_get_cliente_info" {
                if tok == Self.viejo { if sinRedParaElLink { throw URLError(.notConnectedToInternet) }; return (200, "[]") }
                if tok == Self.nuevo, sinRedParaElLink { throw URLError(.notConnectedToInternet) }
                return (200, Self.info)
            }
            return (200, "[]")
        }
        let almacen = TokenEnMemoria(Self.tokA)
        return (ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz), almacen, t)
    }

    @Test func unLinkViejoNuncaUsadoNoBorraLaCuenta() async {
        UserDefaults.standard.removeObject(forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let (m, almacen, _) = modelo()
        await m.cargar()
        #expect(m.fase == .listo)
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.viejo)") == false)
        #expect(m.fase == .listo, "quedó en \"pegá tu link\"")
        #expect(m.token == Self.tokA && almacen.leer() == Self.tokA, "se perdió la cuenta que andaba")
        #expect(UserDefaults.standard.string(forKey: "mypump_token_invalido") == Self.viejo, "queda anotado: la próxima vez ni se pregunta")
        #expect(m.avisoLink == .vencido)
        // Tocarlo otra vez avisa lo mismo sin preguntar, y lo que no tocó el cliente (la migración) no avisa.
        m.avisoLink = nil
        #expect(await m.entrar(con: Self.viejo) == false)
        #expect(m.avisoLink == .vencido && m.token == Self.tokA)
        m.avisoLink = nil
        #expect(await m.entrar(con: Self.viejo, avisar: false) == false)
        #expect(m.avisoLink == nil)
    }

    @Test func siLaMigracionDejoElLinkVencidoEnElKeychainVuelveElQueAnda() async {
        UserDefaults.standard.removeObject(forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let (m, almacen, _) = modelo()
        await m.cargar()
        almacen.guardar(Self.viejo)   // la Fase L adoptó el link de la app vieja, que ya no sirve
        #expect(await m.entrar(con: Self.viejo, avisar: false) == false)
        #expect(m.token == Self.tokA && almacen.leer() == Self.tokA, "el próximo arranque iba a abrir con el link vencido")
    }

    @Test func sinRedParaRevisarElLinkSeQuedaEnLaCuenta() async {
        UserDefaults.standard.removeObject(forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let (m, almacen, _) = modelo(sinRedParaElLink: true)
        await m.cargar()
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.nuevo)") == false)
        #expect(m.fase == .listo && m.token == Self.tokA && almacen.leer() == Self.tokA, "se reemplazó la cuenta sin poder revisar el link")
        #expect(m.avisoLink == .sinConexion)
    }

    @Test func unLinkQueAndaCambiaDeCuenta() async {
        let (m, almacen, _) = modelo()
        await m.cargar()
        #expect(await m.entrar(con: "https://app.mypumpteam.com/?t=\(Self.nuevo)"))
        #expect(m.fase == .listo && m.token == Self.nuevo && almacen.leer() == Self.nuevo)
    }

    @Test func sinCuentaUnLinkVencidoAvisaComoHoy() async {
        UserDefaults.standard.removeObject(forKey: "mypump_token_invalido")
        defer { UserDefaults.standard.removeObject(forKey: "mypump_token_invalido") }
        let t = TransporteProgramado { fn, _ in fn == "mypump_get_cliente_info" ? (200, "[]") : (200, "[]") }
        let almacen = TokenEnMemoria(nil)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
        #expect(await m.entrar(con: Self.viejo) == false)
        #expect(m.fase == .tokenInvalido && almacen.leer() == nil)
    }
}
