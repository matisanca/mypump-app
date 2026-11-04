import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

private func guia(_ json: String) -> Guia {
    Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null)
}

private func clip(_ id: String, bloque: String? = "B", minutos: Double = 1, visto: Bool = false, segundos: Int = 0, url: Bool = true) -> ClipGuia {
    ClipGuia(id: id, titulo: "¿\(id)?", url: url ? URL(string: "https://x.invalid/\(id).mp4") : nil, minutos: minutos, bloque: bloque,
             visto: visto, segundos: segundos)
}

@Suite("Tu guía: el JSON de entregas_app_get")
struct GuiaDecodificacionTests {
    @Test func laMuestraEntera() {
        let g = GuiaMuestra.guia
        #expect(g.ok)
        #expect(g.nombrePila == "Marcelo")
        #expect(g.fechaEntrega == nil)
        #expect(g.clips.count == 13)
        #expect(g.clips[0].visto && g.clips[0].id == "FT-25a")
        #expect(g.clips[4].segundos == 9)
        #expect(g.clips[8].url == nil, "sin url: se está subiendo")
        #expect(g.dudasLlamada.map(\.texto) == ["¿Puedo entrenar a la noche?"])
        #expect(g.suplementacion?.items.count == 6)
        #expect(g.suplementacion?.dia.map(\.id) == ["almuerzo", "pre", "dormir"])
        #expect(g.suplementacion?.items[1].videoId == "FT-1b")
        #expect(g.suplementacion?.items[1].detalle == ["Que diga *L-citrulina* sola, no malato."])
        #expect(g.suplementacion?.items[3].opcional == true)
    }

    @Test(arguments: ["false", "null", "{\"ok\":false}", "[]", "0", "\"x\"", "{}"])
    func todoLoQueNoEsOkTrueEsSinGuia(_ json: String) {
        #expect(!guia(json).ok)
    }

    @Test func camposQueFaltanONullNoRompen() {
        let g = guia(#"{"ok":true,"clips":[{"id":"a"},{"id":"b","titulo":null,"minutos":"1,5","visto":"true","segundos":"12.7","duda":""},null,{"titulo":"sin id"},7],"dudas_llamada":null,"suplementacion":"rota"}"#)
        #expect(g.ok)
        #expect(g.clips.map(\.id) == ["a", "b"], "el null, el que no tiene id y el número se descartan")
        #expect(g.clips[0].titulo == "" && g.clips[0].url == nil && g.clips[0].minutos == 0 && !g.clips[0].visto)
        #expect(g.clips[1].minutos == 1.5 && g.clips[1].visto && g.clips[1].segundos == 12)
        #expect(g.clips[1].duda == nil, "duda vacía es sin duda")
        #expect(g.dudasLlamada.isEmpty)
        #expect(g.suplementacion == nil)
    }

    @Test func urlsQueNoSonWebNoSeReproducen() {
        let g = guia(#"{"ok":true,"clips":[{"id":"a","url":"javascript:alert(1)"},{"id":"b","url":"  https://x.invalid/b.mp4 "},{"id":"c","url":"file:///etc/passwd"}]}"#)
        #expect(g.clips.map { $0.url?.absoluteString } == [nil, "https://x.invalid/b.mp4", nil])
    }

    @Test func minutosNegativosOInfinitosSonCero() {
        let g = guia(#"{"ok":true,"clips":[{"id":"a","minutos":-3,"segundos":-5}]}"#)
        #expect(g.clips[0].minutos == 0 && g.clips[0].segundos == 0)
    }

    @Test func dudasDeLaLlamadaComoTextosSueltos() {
        let g = guia(#"{"ok":true,"clips":[],"dudas_llamada":["una",{"texto":"dos"},{"texto":""}]}"#)
        #expect(g.dudasLlamada.map(\.texto) == ["una", "dos"])
    }

    @Test func idaYVueltaParaLaCopia() throws {
        let g = GuiaMuestra.guia
        let otra = try JSONDecoder().decode(Guia.self, from: JSONEncoder().encode(g))
        #expect(otra == g)
    }

    @Test func resumen() {
        let r = ResumenGuia(json: .objeto(["ok": .bool(true), "total": .numero(20), "vistos": .numero(3), "minutos_restantes": .numero(14.5)]))
        #expect(r == ResumenGuia(ok: true, total: 20, vistos: 3, minutosRestantes: 14.5))
        #expect(r.hayGuia)
        #expect(!ResumenGuia(json: .bool(false)).ok)
        #expect(!ResumenGuia(json: .objeto(["ok": .bool(true), "total": .numero(0)])).hayGuia, "ok sin videos no muestra tarjeta")
        let raro = ResumenGuia(json: .objeto(["ok": .bool(true), "total": .texto("5"), "vistos": .numero(9), "minutos_restantes": .null]))
        #expect(raro.total == 5 && raro.vistos == 5 && raro.minutosRestantes == 0)
    }
}

@Suite("Tu guía: reglas de la web")
struct GuiaReglasTests {
    @Test func tuAppVaPrimeroYElRestoEnSuOrden() {
        let c = [clip("a", bloque: "Tu entrenamiento"), clip("b", bloque: " tu APP "), clip("c", bloque: "Tu salud"), clip("d", bloque: "Tu app")]
        #expect(ReglasGuia.ordenados(c).map(\.id) == ["b", "d", "a", "c"])
    }

    @Test func bloquesEnElOrdenEnQueAparecen() {
        let c = [clip("a", bloque: "X", minutos: 1.2), clip("b", bloque: "Y"), clip("c", bloque: "X", minutos: 0.5), clip("d", bloque: nil), clip("e", bloque: "")]
        let b = ReglasGuia.bloques(c)
        #expect(b.map(\.titulo) == ["X", "Y", "Videos"])
        #expect(b[0].indices == [0, 2])
        #expect(abs(b[0].minutos - 1.7) < 0.0001)
        #expect(b[2].indices == [3, 4])
        #expect(ReglasGuia.textoBloque(b[0]) == "2 videos, unos 2 minutos")
        #expect(ReglasGuia.textoBloque(b[1]) == "1 video, unos 1 minuto")
    }

    @Test func duraciones() {
        #expect(ReglasGuia.duracion(minutos: 1.2) == "1:12")
        #expect(ReglasGuia.duracion(minutos: 0.3) == "0:18")
        #expect(ReglasGuia.duracion(minutos: 0) == "0:00")
        #expect(ReglasGuia.duracionHablada(minutos: 1.2) == "1 minuto y 12 segundos")
        #expect(ReglasGuia.duracionHablada(minutos: 0.3) == "18 segundos")
        #expect(ReglasGuia.duracionHablada(minutos: 2) == "2 minutos")
    }

    @Test func avanceComoLaWeb() {
        let c = [clip("a", minutos: 1.2, visto: true), clip("b", minutos: 0.3), clip("c", minutos: 0.4)]
        let a = ReglasGuia.avance(c)
        #expect(a.vistos == 1 && a.total == 3 && abs(a.minutosRestantes - 0.7) < 0.0001)
        #expect(ReglasGuia.textoAvance(a) == "Viste 1 de 3, te quedan unos 1 minutos")
        #expect(ReglasGuia.textoTarjeta(a) == "1 de 3 videos, te quedan 1 min")
        let todos = ReglasGuia.avance(c.map { var x = $0; x.visto = true; return x })
        #expect(ReglasGuia.textoAvance(todos) == "Viste todos, nos vemos en la videollamada")
        #expect(ReglasGuia.textoTarjeta(todos) == "Viste los 3 videos")
        #expect(ReglasGuia.textoTarjeta(.init(total: 13, vistos: 0, minutosRestantes: 12.4)) == "13 videos, unos 12 min")
        #expect(ReglasGuia.textoTarjeta(.init(total: 13, vistos: 4, minutosRestantes: 12)) == "4 de 13 videos, te quedan 12 min")
    }

    @Test func partesDelMotivo() {
        #expect(ReglasGuia.partes("Hacé esto ||| porque sí") == ("Hacé esto", "porque sí"))
        #expect(ReglasGuia.partes("solo motivo") == ("", "solo motivo"))
        #expect(ReglasGuia.partes(nil) == ("", ""))
    }

    @Test func yaPasoLaLlamada() {
        let ahora = ReglasGuia.fechaISO("2026-11-04T15:00:00-03:00")!
        #expect(!ReglasGuia.yaPaso(nil, ahora: ahora))
        #expect(ReglasGuia.yaPaso("2026-11-04T14:00:00-03:00", ahora: ahora))
        #expect(!ReglasGuia.yaPaso("2026-11-04T16:00:00-03:00", ahora: ahora))
        #expect(!ReglasGuia.yaPaso("2026-11-04", ahora: ahora), "solo la fecha: hoy todavía no pasó")
        #expect(ReglasGuia.yaPaso("2026-11-03", ahora: ahora))
        #expect(!ReglasGuia.yaPaso("cualquier cosa larga", ahora: ahora))
    }

    @Test func fechaDeLaLlamadaEnBuenosAires() {
        #expect(ReglasGuia.fechaLlamada("2026-11-04T14:00:00-03:00") == "miércoles 4/11")
        // A la 1 de la mañana UTC del 5 todavía es el 4 en Buenos Aires.
        #expect(ReglasGuia.fechaLlamada("2026-11-05T01:00:00Z") == "miércoles 4/11")
        #expect(ReglasGuia.fechaLlamada(nil) == nil)
    }

    @Test func textoParaMandar() {
        #expect(ReglasGuia.textoParaMandar("  hola \n") == "hola")
        #expect(ReglasGuia.textoParaMandar("   ") == nil)
        #expect(ReglasGuia.textoParaMandar(String(repeating: "a", count: 1000)) != nil)
        #expect(ReglasGuia.textoParaMandar(String(repeating: "a", count: 1001)) == nil)
    }

    @Test func negritasDelPDF() {
        let t = ReglasGuia.negritas("Que diga *L-citrulina* sola y *no* malato")
        #expect(t.map(\.texto) == ["Que diga ", "L-citrulina", " sola y ", "no", " malato"])
        #expect(t.map(\.negrita) == [false, true, false, true, false])
        #expect(ReglasGuia.negritas("sin cerrar *esto").map(\.texto) == ["sin cerrar *esto"])
        #expect(ReglasGuia.negritas("**").map(\.texto) == ["**"])
    }

    @Test func inicialSiguienteYAnteriorSalteanLosQueSeEstanSubiendo() {
        let c = [clip("a", visto: true), clip("b", url: false), clip("c"), clip("d", url: false)]
        #expect(ReglasGuia.inicial(c) == 2)
        #expect(ReglasGuia.siguiente(c, desde: 0) == 2)
        #expect(ReglasGuia.siguiente(c, desde: 2) == nil)
        #expect(ReglasGuia.anterior(c, desde: 2) == 0)
        #expect(ReglasGuia.anterior(c, desde: 0) == nil)
        let vistos = [clip("a", visto: true, url: false), clip("b", visto: true)]
        #expect(ReglasGuia.inicial(vistos) == 1, "si vio todos, el primero que se pueda")
        #expect(ReglasGuia.inicial([clip("a", url: false)]) == nil)
    }

    @Test func retomar() {
        #expect(ReglasGuia.retomar(clip("a", segundos: 30), duracion: 60) == 30)
        #expect(ReglasGuia.retomar(clip("a", segundos: 5), duracion: 60) == nil, "desde el segundo 5 exclusive")
        #expect(ReglasGuia.retomar(clip("a", segundos: 55), duracion: 60) == nil, "5 s antes del final ya no")
        #expect(ReglasGuia.retomar(clip("a", segundos: 54), duracion: 60) == 54)
        #expect(ReglasGuia.retomar(clip("a", visto: true, segundos: 30), duracion: 60) == nil, "visto arranca de cero")
        #expect(ReglasGuia.retomar(clip("a", segundos: 30), duracion: .nan) == nil)
    }

    @Test func velocidad() {
        #expect(ReglasGuia.velocidadSiguiente(1) == 1.25)
        #expect(ReglasGuia.velocidadSiguiente(1.25) == 1.5)
        #expect(ReglasGuia.velocidadSiguiente(1.5) == 1)
        #expect(ReglasGuia.textoVelocidad(1) == "1x")
        #expect(ReglasGuia.textoVelocidad(1.25) == "1,25x")
        #expect(ReglasGuia.textoVelocidad(1.5) == "1,5x")
    }

    @Test func textosDeLaPlaca() {
        #expect(ReglasGuia.textoPlaca(2, de: 13) == "Otro tema · Video 3 de 13")
        #expect(ReglasGuia.textoNumero(0, de: 13, bloque: "Tu app") == "Video 1 de 13 · Tu app")
        #expect(ReglasGuia.textoNumero(0, de: 1, bloque: "") == "Video 1 de 1")
    }
}

@Suite("Tu guía: cuándo se guarda el avance")
struct AvanceVideoTests {
    @Test func cadaDiezSegundosYAlOchentaPorCiento() {
        var a = AvanceVideo(visto: false)
        var guardados: [AvanceVideo.Guardado] = []
        for t in stride(from: 0.0, through: 100, by: 1) { if let g = a.alAvanzar(t, duracion: 100) { guardados.append(g) } }
        #expect(guardados.map(\.segundos) == [10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
        #expect(guardados.map(\.visto) == [false, false, false, false, false, false, false, true, true, true])
    }

    @Test func elOchentaGuardaAunqueNoPasaronDiez() {
        var a = AvanceVideo(visto: false)
        #expect(a.alAvanzar(10, duracion: 18) == .init(segundos: 10, visto: false))
        #expect(a.alAvanzar(14, duracion: 18) == nil)
        #expect(a.alAvanzar(14.5, duracion: 18) == .init(segundos: 15, visto: true), "14,5 de 18 es el 80 %")
        #expect(a.alAvanzar(15, duracion: 18) == nil, "ya visto: no repite")
    }

    @Test func retomarNoGuardaEnseguida() {
        var a = AvanceVideo(visto: false, desde: 30)
        #expect(a.alAvanzar(31, duracion: 100) == nil)
        #expect(a.alAvanzar(40, duracion: 100) == .init(segundos: 40, visto: false))
    }

    @Test func unoYaVistoSigueMandandoVisto() {
        var a = AvanceVideo(visto: true)
        #expect(a.alAvanzar(10, duracion: 100) == .init(segundos: 10, visto: true))
    }

    @Test func alTerminarYAlSalir() {
        var a = AvanceVideo(visto: false)
        #expect(a.alSalir(0.5) == nil, "no avanzó")
        #expect(a.alSalir(7) == .init(segundos: 7, visto: false))
        #expect(a.alSalir(7.5) == nil)
        #expect(a.alTerminar(duracion: 42.4) == .init(segundos: 42, visto: true))
        var b = AvanceVideo(visto: false, desde: 12)
        #expect(b.alTerminar(duracion: .nan) == .init(segundos: 12, visto: true), "sin duración, lo último")
    }

    @Test func segundosDentroDelRangoDeLaBase() {
        var a = AvanceVideo(visto: false)
        #expect(a.alAvanzar(50_000, duracion: 60_000)?.segundos == 36_000)
        #expect(a.alAvanzar(.infinity, duracion: 100) == nil)
        #expect(a.alAvanzar(-3, duracion: 100) == nil)
    }
}

@Suite("Tu guía: suplementación como «Tu día» del PDF")
struct VistaSuplementacionTests {
    @Test func laMuestra() throws {
        let v = try #require(VistaSuplementacion(GuiaMuestra.guia.suplementacion))
        #expect(v.titulo == "Tu suplementación")
        #expect(v.accion == "Sumá lo nuevo de a uno por día")
        #expect(v.momentos.map(\.titulo) == ["Tu primera comida", "30 a 60 minutos antes de entrenar", "30 minutos antes de acostarte", "Además"])
        // Creatina va en dos momentos, por sus tomas; el por qué, solo la primera vez que aparece.
        let comida = v.momentos[0].filas
        #expect(comida.map(\.nombre) == ["Creatina"])
        #expect(comida[0].nota == "Los días que no entrenás")
        let pre = v.momentos[1].filas
        #expect(pre.map(\.nombre) == ["Creatina", "L-citrulina"])
        #expect(comida[0].porQue != nil && pre[0].porQue == nil)
        #expect(pre[1].nuevo && pre[1].videoId == "FT-1b")
        let noche = v.momentos[2].filas
        #expect(noche.map(\.nombre) == ["Bisglicinato de magnesio", "Melatonina"])
        #expect(noche[1].opcional && noche[1].nuevo)
        #expect(v.momentos[3].filas.map(\.nombre) == ["Vitamina C"])
        #expect(v.sigue == "Tus gotas de vitamina D, como venías")
        #expect(v.sale.map(\.nombre) == ["Quemador"])
        #expect(Set(v.momentos.flatMap(\.filas).map(\.id)).count == 6, "ids únicos")
    }

    @Test func vaciaONullNoSeMuestra() {
        #expect(VistaSuplementacion(nil) == nil)
        #expect(VistaSuplementacion(SuplementacionGuia()) == nil)
    }

    @Test func sinDiaOrdenaPorElDiaDelPDF() throws {
        let s = SuplementacionGuia(items: [
            ItemSuplemento(nombre: "A", momento: "dormir"), ItemSuplemento(nombre: "B", momento: "raro_x"),
            ItemSuplemento(nombre: "C", momento: "despertar"), ItemSuplemento(nombre: "D", momento: "pre"),
        ])
        let v = try #require(VistaSuplementacion(s))
        #expect(v.momentos.map(\.titulo) == ["Al despertar", "Antes de entrenar", "Antes de dormir", "Raro x"])
    }

    @Test func momentosQueNoEstanEnDiaVanDespues() throws {
        let s = SuplementacionGuia(dia: [MomentoDia(id: "cena", nombre: "La cena")], items: [
            ItemSuplemento(nombre: "A", momento: "zz"), ItemSuplemento(nombre: "B", momento: "cena"), ItemSuplemento(nombre: "C", momento: "desayuno"),
        ])
        let v = try #require(VistaSuplementacion(s))
        #expect(v.momentos.map(\.titulo) == ["La cena", "Desayuno", "Zz"])
    }
}

@Suite("Tu guía: los videos de los suplementos (A5)")
struct GuiaVerPorQueTests {
    @Test func laMuestraSacaLosDosDeLaLista() {
        let g = GuiaMuestra.guia
        let lista = ReglasGuia.deLaLista(g)
        #expect(lista.count == 11)
        #expect(!lista.contains { $0.id == "FT-1b" || $0.id == "FT-4b" })
        #expect(ReglasGuia.esBloqueApp(lista[0].bloque), "«Tu app» sigue primero")
        #expect(ReglasGuia.clipDeSuplemento(g, videoId: "FT-1b")?.id == "FT-1b")
        #expect(ReglasGuia.avance(lista).total == 11)
    }

    /// Los bordes de la regla de `entregas_012` (la tarjeta del servidor y la lista tienen que dar lo mismo).
    private static let bordes = guia("""
    {"ok":true,"clips":[
      {"id":"esp","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"  TU SUPLEMENTACIÓN \u{A0}"},
      {"id":"sinacento","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu Suplementacion"},
      {"id":"nulo","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":null},
      {"id":"otro","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Otro tema"},
      {"id":"sale","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu suplementación"},
      {"id":"Sale","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu suplementación"},
      {"id":"sinnombre","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu suplementación"},
      {"id":"blanco","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu suplementación"},
      {"id":"suelto","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu suplementación"}],
     "suplementacion":{"items":[
      {"nombre":"Creatina","video_id":"esp"},
      {"nombre":"Creatina","video_id":"sinacento"},
      {"nombre":"Zinc","video_id":"nulo"},
      {"nombre":"Zinc","video_id":"otro"},
      {"nombre":"Cafeína","estado":"sale","video_id":"sale"},
      {"nombre":"Cafeína","estado":"Sale","video_id":"Sale"},
      {"nombre":"","video_id":"sinnombre"},
      {"nombre":"  ","video_id":"blanco"},
      {"nombre":"Omega 3","video_id":""}]}}
    """)

    @Test func bloqueConEspaciosEnMayusculasOSinAcento() {
        let fuera = Set(GuiaMuestra.guia.clips.map(\.id)).subtracting(ReglasGuia.deLaLista(GuiaMuestra.guia).map(\.id))
        #expect(fuera == ["FT-1b", "FT-4b"])
        let lista = ReglasGuia.deLaLista(Self.bordes).map(\.id)
        #expect(!lista.contains("esp"))
        #expect(!lista.contains("sinacento"))
    }

    @Test func bloqueNuloUOtroNoSale() {
        let lista = ReglasGuia.deLaLista(Self.bordes).map(\.id)
        #expect(lista.contains("nulo"))
        #expect(lista.contains("otro"))
        #expect(!ReglasGuia.esBloqueSuplementacion(nil))
    }

    @Test func itemQueSaleNoLoNombra() {
        let lista = ReglasGuia.deLaLista(Self.bordes).map(\.id)
        #expect(lista.contains("sale"))
        // Como el servidor (`<> 'sale'`): solo «sale» exacto.
        #expect(!lista.contains("Sale"))
    }

    @Test func nombreVacioYVideoIdVacio() {
        let lista = ReglasGuia.deLaLista(Self.bordes).map(\.id)
        #expect(lista.contains("sinnombre"))
        #expect(!lista.contains("blanco"), "el servidor no recorta el nombre: «  » no es vacío")
        #expect(lista.contains("suelto"), "video_id vacío no nombra a nadie")
        #expect(lista == ["nulo", "otro", "sale", "sinnombre", "suelto"])
        #expect(ReglasGuia.avance(ReglasGuia.deLaLista(Self.bordes)).total == 5)
    }

    @Test func laCacheGuardaLaRegla() throws {
        let datos = try JSONEncoder().encode(Self.bordes)
        let leida = try JSONDecoder().decode(Guia.self, from: datos)
        #expect(ReglasGuia.deLaLista(leida).map(\.id) == ReglasGuia.deLaLista(Self.bordes).map(\.id))
    }

    @Test func sinSuplementacionNoSacaNada() {
        let g = guia(#"{"ok":true,"clips":[{"id":"a","titulo":"A","minutos":1,"bloque":"Tu suplementación"}]}"#)
        #expect(ReglasGuia.deLaLista(g).map(\.id) == ["a"])
        #expect(ReglasGuia.deLaLista(nil).isEmpty)
    }

    @Test func elClipSinUrlNoTieneBoton() {
        let g = guia(#"{"ok":true,"clips":[{"id":"a","titulo":"A","minutos":1,"bloque":"Tu suplementación"}],"suplementacion":{"items":[{"nombre":"Creatina","video_id":"a"}]}}"#)
        #expect(ReglasGuia.clipDeSuplemento(g, videoId: "a") == nil)
        #expect(ReglasGuia.clipDeSuplemento(g, videoId: nil) == nil)
        #expect(ReglasGuia.clipDeSuplemento(g, videoId: "zz") == nil)
    }

    @Test func elRotuloEnSegundos() {
        #expect(ReglasGuia.rotuloVerPorQue(clip("a", minutos: 0.7)) == "Ver por qué (42 s)")
        #expect(ReglasGuia.rotuloVerPorQue(clip("a", minutos: 0)) == "Ver por qué (1 s)")
    }
}

@Suite("Tu guía: revisión adversarial (4/11)")
struct GuiaRevisionTests {
    @Test func suplementacionEnNFDNoEsElBloque() {
        // «ó» descompuesta (o + acento combinado): Swift la compara igual, el regex de entregas_012 no.
        #expect(!ReglasGuia.esBloqueSuplementacion("Tu suplementacio\u{301}n"))
        #expect(ReglasGuia.esBloqueSuplementacion("Tu suplementaci\u{F3}n"))
        #expect(ReglasGuia.esBloqueSuplementacion("\u{FEFF}\t tu SUPLEMENTACI\u{D3}N \u{A0}\n"))
        #expect(!ReglasGuia.esBloqueSuplementacion("Tu suplementación\u{2003}"), "un espacio que el servidor no recorta")
        #expect(!ReglasGuia.esBloqueSuplementacion("Tu  suplementación"))
        #expect(!ReglasGuia.esBloqueSuplementacion("Tu suplementaciones"))
        #expect(!ReglasGuia.esBloqueSuplementacion(""))
    }

    @Test func saleConMayusculaYNombreEnBlancoSeVenConSuVideo() throws {
        let g = guia("""
        {"ok":true,"clips":[
          {"id":"a","titulo":"A","url":"https://x.invalid/a.mp4","minutos":1,"bloque":"Tu suplementación"},
          {"id":"b","titulo":"B","url":"https://x.invalid/b.mp4","minutos":1,"bloque":"Tu suplementación"}],
         "suplementacion":{"items":[
          {"nombre":"Cafeína","estado":"Sale","video_id":"a"},
          {"nombre":"  ","video_id":"b"},
          {"nombre":"","video_id":"zz"}]}}
        """)
        let s = try #require(g.suplementacion)
        #expect(s.items.count == 2, "sin nombre no va; en blanco sí, como la web")
        #expect(ReglasGuia.deLaLista(g).isEmpty)
        let v = try #require(VistaSuplementacion(s))
        #expect(v.sale.isEmpty, "«Sale» no es «sale»: va con los demás, como la web")
        let filas = v.momentos.flatMap(\.filas)
        #expect(filas.compactMap(\.videoId) == ["a", "b"], "los dos videos se pueden ver con «Ver por qué»")
    }

    @Test func vecesCuentaDudasDeVariosRenglones() {
        #expect(ReglasGuia.veces("hola", en: "hola\nchau\nhola") == 2)
        #expect(ReglasGuia.veces("a\nb", en: "x\na\nb\na\nb") == 2)
        #expect(ReglasGuia.veces("hola", en: "holas") == 0)
        #expect(ReglasGuia.veces("hola", en: nil) == 0)
        #expect(ReglasGuia.veces("", en: "hola") == 0)
        #expect(ReglasGuia.veces("x", en: [DudaLlamada(texto: "x", en: nil), DudaLlamada(texto: "y", en: nil), DudaLlamada(texto: "x", en: nil)]) == 2)
    }

    @Test func alFinalSeVuelveAEmpezar() {
        #expect(ReglasGuia.estaAlFinal(59.8, duracion: 60))
        #expect(!ReglasGuia.estaAlFinal(30, duracion: 60))
        #expect(!ReglasGuia.estaAlFinal(10, duracion: .nan))
        #expect(!ReglasGuia.estaAlFinal(.nan, duracion: 60))
    }
}
