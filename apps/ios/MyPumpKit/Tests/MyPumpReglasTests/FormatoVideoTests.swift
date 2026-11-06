import CoreGraphics
import Foundation
import Testing
@testable import MyPumpReglas

@Suite("Formato de los videos (sin franjas negras)")
struct FormatoVideoTests {
    @Test func laProporcionSaleDelTamañoConLaRotacionAplicada() throws {
        #expect(try #require(ReglasVideo.proporcion(ancho: 1280, alto: 720)) == 1280.0 / 720.0)
        #expect(ReglasVideo.proporcion(ancho: 720, alto: 720) == 1)
        // Un vertical grabado acostado (720×570) con la pista girada 90°: se ve 570×720.
        let p = try #require(ReglasVideo.proporcion(ancho: 720, alto: 570, transformacion: CGAffineTransform(rotationAngle: .pi / 2)))
        #expect(abs(p - 570.0 / 720.0) < 0.0001)
    }

    @Test func unTamañoRotoNoDaProporcion() {
        #expect(ReglasVideo.proporcion(ancho: 0, alto: 720) == nil)
        #expect(ReglasVideo.proporcion(ancho: 1280, alto: 0) == nil)
        #expect(ReglasVideo.proporcion(ancho: .nan, alto: 720) == nil)
        #expect(ReglasVideo.proporcion(ancho: 1, alto: 2000) == nil)
    }

    @Test func horizontalYCuadradoOcupanTodoElAncho() {
        // 17 Pro: 402 × 874, con la tarjeta de 370 de ancho.
        #expect(ReglasVideo.cuadro(proporcion: 1280.0 / 720.0, anchoDisponible: 370, altoPantalla: 874) == CGSize(width: 370, height: 208))
        #expect(ReglasVideo.cuadro(proporcion: 1, anchoDisponible: 370, altoPantalla: 874) == CGSize(width: 370, height: 370))
    }

    @Test func elVerticalNoPasaDel60PorCientoDelAlto() {
        let v = 570.0 / 720.0
        // 17 Pro: entra a lo ancho (467 de alto, menos de 524).
        #expect(ReglasVideo.cuadro(proporcion: v, anchoDisponible: 370, altoPantalla: 874) == CGSize(width: 370, height: 467))
        // SE (667 de alto): 400 de alto y el ancho que le toca, centrado en la tarjeta.
        #expect(ReglasVideo.cuadro(proporcion: v, anchoDisponible: 343, altoPantalla: 667) == CGSize(width: 317, height: 400))
        // Un 9:16 en el 17 Pro: tampoco pasa del 60 %.
        let c = ReglasVideo.cuadro(proporcion: 9.0 / 16.0, anchoDisponible: 370, altoPantalla: 874)
        #expect(c.height == 524 && c.width == 295)
        // El cuadro de la tarjeta (sin franjas): misma proporción que el clip.
        #expect(abs(c.width / c.height - 9.0 / 16.0) < 0.01)
    }

    @Test func sinDatoEs16a9() {
        #expect(ReglasVideo.cuadro(proporcion: nil, anchoDisponible: 352, altoPantalla: 874) == CGSize(width: 352, height: 198))
        #expect(ReglasVideo.cuadro(proporcion: 50, anchoDisponible: 352, altoPantalla: 874) == CGSize(width: 352, height: 198))
        #expect(ReglasVideo.cuadro(proporcion: 1, anchoDisponible: 0, altoPantalla: 874) == .zero)
    }
}

@Suite("Franjas negras metidas en el archivo")
struct RecuadroVideoTests {
    /// Un cuadro `ancho × alto` negro (12, como el negro comprimido) con la zona `x0..<x1` × `y0..<y1` clara.
    private func cuadro(_ ancho: Int, _ alto: Int, x0: Int, x1: Int, y0: Int = 0, y1: Int? = nil) -> [UInt8] {
        var l = [UInt8](repeating: 12, count: ancho * alto)
        for y in y0..<(y1 ?? alto) { for x in x0..<x1 { l[y * ancho + x] = 140 } }
        return l
    }

    @Test func elFT2bDeLaDemo() throws {
        // 320×180, como lo lee la app: la grabación de 434 px de 1280 (columnas 422 a 855) cae en 105..<214.
        let r = try #require(ReglasVideo.recuadro(luma: cuadro(320, 180, x0: 105, x1: 214), ancho: 320, alto: 180))
        // Un píxel hacia adentro de cada lado (nunca negro a la vista); arriba y abajo toca el cuadro: entero.
        #expect(abs(r.x - 106.0 / 320) < 0.0001 && abs(r.ancho - 107.0 / 320) < 0.0001 && r.y == 0 && r.alto == 1)
        let c = try #require(ReglasVideo.recorte(r))
        let p = ReglasVideo.proporcion(archivo: 16.0 / 9, recorte: c)
        #expect(p > 0.57 && p < 0.63)
        // Vertical: en el 17 Pro, 370 de ancho darían más del 60 %: queda por el alto.
        #expect(ReglasVideo.cuadro(proporcion: p, anchoDisponible: 370, altoPantalla: 874).height == 524)
    }

    /// El marco del teléfono grabado (gris oscuro parejo, 30) pasa el umbral pero se ve como franja: se suma al recorte.
    @Test func elMarcoOscuroDelTelefonoTambienSeRecorta() throws {
        var l = cuadro(320, 180, x0: 100, x1: 220)
        for y in 0..<180 { for x in [100, 101, 102, 103, 217, 218, 219] { l[y * 320 + x] = 30 } }
        // Y la imagen de adentro, con variación (un video de verdad).
        for y in 0..<180 { for x in 104..<217 where (x + y) % 3 == 0 { l[y * 320 + x] = 200 } }
        let r = try #require(ReglasVideo.recuadro(luma: l, ancho: 320, alto: 180))
        #expect(abs(r.x - 105.0 / 320) < 0.0001)
        #expect(abs((r.x + r.ancho) - 216.0 / 320) < 0.0001)
    }

    @Test func sinFranjasNoSeRecorta() {
        let r = ReglasVideo.recuadro(luma: cuadro(320, 180, x0: 0, x1: 320), ancho: 320, alto: 180)
        #expect(r == .entero)
        #expect(ReglasVideo.recorte(r) == nil)
        // Un borde oscuro chico del propio video (menos del 8 %): tampoco.
        #expect(ReglasVideo.recorte(RecuadroVideo(x: 0.03, y: 0, ancho: 0.94, alto: 1)) == nil)
        #expect(ReglasVideo.proporcion(archivo: 16.0 / 9, recorte: nil) == 16.0 / 9)
    }

    @Test func elRuidoSueltoNoCuentaYTodoNegroNoDaNada() {
        var l = cuadro(320, 180, x0: 105, x1: 214)
        l[5 * 320 + 3] = 255   // un píxel suelto en la franja
        let r = ReglasVideo.recuadro(luma: l, ancho: 320, alto: 180)
        #expect(r?.x == 106.0 / 320)
        #expect(ReglasVideo.recuadro(luma: [UInt8](repeating: 12, count: 320 * 180), ancho: 320, alto: 180) == nil)
        #expect(ReglasVideo.recuadro(luma: [], ancho: 320, alto: 180) == nil)
    }

    @Test func laUnionYElRecorteCentrado() throws {
        let a = RecuadroVideo(x: 0.3, y: 0, ancho: 0.3, alto: 1)
        let b = RecuadroVideo(x: 0.35, y: 0.1, ancho: 0.4, alto: 0.8)
        let u = try #require(ReglasVideo.unir([a, b]))
        #expect(abs(u.x - 0.3) < 1e-9 && abs(u.ancho - 0.45) < 1e-9 && u.y == 0 && u.alto == 1)
        // Corrido a la derecha: se achica parejo (0,3 a 0,7) para que el reproductor recorte igual de los dos lados sin
        // dejar negro del lado angosto.
        let c = try #require(ReglasVideo.recorte(u))
        #expect(abs(c.x - 0.3) < 1e-9 && abs(c.ancho - 0.4) < 1e-9)
        // Letterbox (franjas arriba y abajo).
        let lb = try #require(ReglasVideo.recorte(RecuadroVideo(x: 0, y: 0.2, ancho: 1, alto: 0.6)))
        #expect(abs(ReglasVideo.proporcion(archivo: 1, recorte: lb) - 1 / 0.6) < 1e-9)
        #expect(ReglasVideo.unir([]) == nil)
    }
}
