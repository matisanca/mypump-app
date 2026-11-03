#if DEBUG
import Foundation
import MyPumpDatos

/// `-offDePrueba encontrado|incompleto|noEncontrado|sinRed` (solo DEBUG): Open Food Facts de mentira para las pruebas de
/// interfaz del código de barras (2.1, S3), junto con `-codigoDePrueba <número>` en lugar de la cámara. «encontrado» es la
/// respuesta real del yogur de los vectores (`barras_off.json`) con solo los campos que se usan; «incompleto», la misma sin
/// proteínas; «noEncontrado», el 404 real de un código que no está.
struct OFFDePrueba: Transporte {
    let caso: String

    static let encontrado = #"{"code":"7791337006355","status":1,"product":{"product_name":"Yogurisimo sabor Natural","product_name_es":"Yogurisimo sabor Natural","brands":"La serenisima","serving_quantity":200,"serving_size":"200 g","nutriments":{"energy-kcal_100g":81.5,"energy-kj_100g":341.8,"energy_100g":341.8,"proteins_100g":7,"carbohydrates_100g":6.25,"fat_100g":3.15}}}"#
    static let incompleto = #"{"code":"7791337006355","status":1,"product":{"product_name":"Yogurisimo sabor Natural","brands":"La serenisima","nutriments":{"energy-kcal_100g":81.5,"carbohydrates_100g":6.25,"fat_100g":3.15}}}"#
    static let noEncontrado = #"{"code":"7790742000101","status":0,"status_verbose":"product not found"}"#

    func enviar(_ pedido: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(for: .milliseconds(400))   // que se vea el «Buscando…»
        let (status, cuerpo): (Int, String)
        switch caso {
        case "encontrado": (status, cuerpo) = (200, Self.encontrado)
        case "incompleto": (status, cuerpo) = (200, Self.incompleto)
        case "sinRed": throw URLError(.notConnectedToInternet)
        default: (status, cuerpo) = (404, Self.noEncontrado)
        }
        return (Data(cuerpo.utf8), HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
