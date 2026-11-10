import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpDatos

/// Un alumno quedó afuera con «No reconocí ese link»: la pantalla de acceso solo aparece sin cuenta, así que primero se le
/// había cerrado la sesión. Un fallo pasajero no puede cerrarla: solo un `[]` del servidor dice que el token no sirve.
@Suite("Un fallo pasajero no cierra la sesión", .serialized)
@MainActor
struct SesionNoSeCierraTests {
    let raiz = FileManager.default.temporaryDirectory.appendingPathComponent("sesion-\(UUID().uuidString)")
    nonisolated static let info = #"[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"#

    /// El Keychain antes del primer desbloqueo: `SecItemCopyMatching` falla y no hay token, aunque esté guardado.
    final class Bloqueado: AlmacenToken, @unchecked Sendable {
        var abierto = false
        var token: String?
        init(_ t: String) { token = t }
        func leer() -> String? { abierto ? token : nil }
        func guardar(_ t: String?) { token = t }
    }

    func modelo(_ almacen: AlmacenToken, cuerpo: @escaping @Sendable () -> String) -> ModeloApp {
        let t = TransporteProgramado { fn, _ in
            if fn == "mypump_get_cliente_info" { return (200, cuerpo()) }
            return (200, "[]")
        }
        return ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
    }

    @Test(arguments: ["", "null", "{}", #"{"message":"ocupado"}"#])
    func unDoscientosQueNoEsListaNoBorraLaCuenta(cuerpo: String) async {
        let tok = "TOKENRARO" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let almacen = TokenEnMemoria(tok)
        let m = modelo(almacen) { cuerpo }
        await m.cargar()
        #expect(m.fase == .sinServicio, "con «\(cuerpo)» quedó en \(m.fase)")
        #expect(almacen.leer() == tok, "borró la cuenta")
        #expect(UserDefaults.standard.string(forKey: "mypump_token_invalido") != tok, "anotó como vencido un token válido")
    }

    @Test func conCopiaGuardadaSigueAdentro() async {
        let tok = "TOKENCOPIA" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let almacen = TokenEnMemoria(tok)
        final class Caja: @unchecked Sendable { var cuerpo = SesionNoSeCierraTests.info }
        let caja = Caja()
        // Con un plan: sin plan no se guarda copia.
        let t = TransporteProgramado { fn, _ in
            switch fn {
            case "mypump_get_cliente_info": return (200, caja.cuerpo)
            case "mypump_get_dieta_activa": return (200, SwapsViejosPalancaTests.dieta)
            default: return (200, "[]")
            }
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
        await m.cargar()
        #expect(m.fase == .listo)
        caja.cuerpo = ""
        await m.cargar()
        #expect(m.fase == .listo)
        #expect(m.desdeCache)
        #expect(almacen.leer() == tok)
    }

    @Test func laListaVaciaSigueSiendoUnLinkQueYaNoSirve() async {
        let almacen = TokenEnMemoria("TOKENREVOCADO0000000")
        let m = modelo(almacen) { "[]" }
        await m.cargar()
        #expect(m.fase == .tokenInvalido)
        #expect(almacen.leer() == nil)
    }

    @Test func unLinkNuevoConRespuestaRaraNoSeDaPorVencido() async {
        let actual = "TOKENACTUAL000000000", nuevo = "LINKNUEVO" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let t = TransporteProgramado { fn, cuerpo in
            if fn == "mypump_get_cliente_info" { return (200, cuerpo["p_token"]?.comoTexto == nuevo ? "" : Self.info) }
            return (200, "[]")
        }
        let almacen = TokenEnMemoria(actual)
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
        await m.cargar()
        #expect(await m.entrar(con: nuevo) == false)
        #expect(m.avisoLink == .sinConexion)
        #expect(m.fase == .listo)
        #expect(almacen.leer() == actual)
        #expect(UserDefaults.standard.string(forKey: "mypump_token_invalido") != nuevo)
    }

    /// La app arranca en segundo plano antes del primer desbloqueo (reinicio del teléfono, Salud): el modelo se crea sin
    /// token y queda vivo. Al abrirla, el alumno veía «Entrá con tu link» hasta matarla.
    @Test func elTokenQueNoSePudoLeerSeRetomaAlVolver() async {
        let almacen = Bloqueado("TOKENGUARDADO0000000")
        let m = modelo(almacen) { Self.info }
        #expect(m.fase == .sinToken)
        almacen.abierto = true
        await m.alVolverAPrimerPlano()
        #expect(m.fase == .listo)
        #expect(m.token == "TOKENGUARDADO0000000")
    }

    @Test func unLinkViejoQueLlegaAntesDeVolverNoPisaLaCuenta() async {
        let guardado = "TOKENGUARDADO0000000", viejo = "LINKVIEJO" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let almacen = Bloqueado(guardado)
        let t = TransporteProgramado { fn, cuerpo in
            if fn == "mypump_get_cliente_info" { return (200, cuerpo["p_token"]?.comoTexto == viejo ? "[]" : Self.info) }
            return (200, "[]")
        }
        let m = ModeloApp(cliente: ClienteRPC(config: .produccion, transporte: t), almacen: almacen, raizDisco: raiz)
        almacen.abierto = true
        #expect(await m.entrar(con: viejo) == false)
        #expect(m.fase == .listo)
        #expect(almacen.leer() == guardado)
        #expect(m.avisoLink == .vencido)
    }

    @Test func habiendoSalidoNoVuelveAEntrarSolo() async {
        let almacen = TokenEnMemoria("TOKENGUARDADO0000000")
        let m = modelo(almacen) { Self.info }
        await m.cargar()
        m.salir()
        await m.alVolverAPrimerPlano()
        #expect(m.fase == .sinToken)
    }
}
