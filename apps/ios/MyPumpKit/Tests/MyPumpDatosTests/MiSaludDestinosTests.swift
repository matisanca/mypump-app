import Testing
import MyPumpReglas
@testable import MyPumpDatos

/// Los destinos viejos de avisos y links llevan a «Mi salud» en su bloque; los demás, a donde iban (caída segura).
struct MiSaludDestinosTests {
    @Test func losDeSaludVanASuBloque() {
        #expect(DestinoAviso(destino: "estudios").bloqueMiSalud == .estudios)
        #expect(DestinoAviso(destino: "presion").bloqueMiSalud == .presion)
        #expect(DestinoAviso(destino: "myday").bloqueMiSalud == .recuperacion)
        #expect(DestinoAviso(escena: "estudios")?.bloqueMiSalud == .estudios)
        #expect(DestinoAviso(escena: "presion")?.bloqueMiSalud == .presion)
        // `salud` sigue llegando como Mis datos (vectores compartidos) y desde el 11/11 abre Mi salud en Recuperación.
        #expect(DestinoAviso(destino: "salud").bloqueMiSalud == .recuperacion)
        #expect(DestinoAviso(escena: "salud")?.bloqueMiSalud == .recuperacion)
    }

    @Test func losDemasSiguenComoAntes() {
        for d in ["train", "diet", "chat", "revision", "progress", "fotos_inicio", "desconocido"] {
            #expect(DestinoAviso(destino: d).bloqueMiSalud == nil, "\(d)")
        }
        #expect(DestinoAviso(destino: "salud") == .misDatos)
        #expect(DestinoAviso(destino: "progress") == .fuerza)
    }
}
