import Foundation
import Testing
import MyPumpModelos
@testable import MyPumpReglas

/// El ejemplo de `docs/NATIVA_CONTRATO.md`, sección 10 (ficticio), tal cual.
let ejemploContratoSuplementacion = """
{
  "suplementacion": {
    "titulo": "Tu suplementación",
    "accion": "Empezá esta semana con lo nuevo",
    "dia": [
      { "id": "desayuno", "nombre": "Con el desayuno" },
      { "id": "pre", "nombre": "30 a 60 minutos antes de entrenar" },
      { "id": "dormir", "nombre": "30 minutos antes de acostarte" }
    ],
    "items": [
      { "nombre": "Creatina monohidrato", "cantidad": "5 g", "momento": "desayuno", "estado": "nuevo",
        "detalle": ["Todos los días, también los de descanso", "Con agua o con el desayuno"],
        "por_que": "Te ayuda a rendir más en las series pesadas",
        "comprar": { "buscar": "Creatina monohidrato 100 % pura" }, "video_id": "VID-1" },
      { "nombre": "Omega 3", "estado": "sigue",
        "tomas": [ { "momento": "desayuno", "cantidad": "1 g" }, { "momento": "dormir", "cantidad": "1 g" } ] },
      { "nombre": "Cafeína", "cantidad": "200 mg", "momento": "pre", "estado": "nuevo", "dias": "gym", "opcional": true,
        "nota": "No después de las 17" },
      { "nombre": "Magnesio glicinato", "cantidad": "400 mg", "antes": "200 mg", "momento": "dormir", "estado": "sube" },
      { "nombre": "Multivitamínico", "estado": "sale", "por_que": "Ya lo cubrís con la dieta" }
    ]
  },
  "fase": "final",
  "actualizado": "2026-11-04T18:30:00+00:00",
  "esquema": 1
}
"""

private func respuesta(_ json: String) throws -> RespuestaSuplementacion {
    try JSONDecoder().decode(RespuestaSuplementacion.self, from: Data(json.utf8))
}

@Suite("Suplementación: el JSON de mypump_suplementacion")
struct SuplementacionDecodificacionTests {
    @Test func elEjemploDelContrato() throws {
        let r = try respuesta(ejemploContratoSuplementacion)
        #expect(r.fase == "final" && r.esquema == 1 && r.actualizado == "2026-11-04T18:30:00+00:00")
        #expect(r.hay)
        let s = try #require(r.suplementacion)
        #expect(s.titulo == "Tu suplementación" && s.accion == "Empezá esta semana con lo nuevo")
        #expect(s.dia.map(\.id) == ["desayuno", "pre", "dormir"])
        #expect(s.items.map(\.nombre) == ["Creatina monohidrato", "Omega 3", "Cafeína", "Magnesio glicinato", "Multivitamínico"])
        let creatina = s.items[0]
        #expect(creatina.detalle == ["Todos los días, también los de descanso", "Con agua o con el desayuno"])
        #expect(creatina.comprar == CompraSuplemento(buscar: "Creatina monohidrato 100 % pura"))
        #expect(creatina.videoId == "VID-1" && creatina.porQue == "Te ayuda a rendir más en las series pesadas")
        let omega = s.items[1]
        #expect(omega.momento == nil && omega.tomas.map(\.momento) == ["desayuno", "dormir"] && omega.tomas.map(\.cantidad) == ["1 g", "1 g"])
        let cafeina = s.items[2]
        #expect(cafeina.dias == ["gym"] && cafeina.opcional && cafeina.nota == "No después de las 17")
        let magnesio = s.items[3]
        #expect(magnesio.antes == "200 mg" && magnesio.estado == "sube")
        #expect(s.items[4].estado == "sale" && s.items[4].momento == nil && s.items[4].tomas.isEmpty)
    }

    @Test func detalleTextoOLista() throws {
        let r = try respuesta("""
        {"suplementacion":{"dia":[],"items":[
          {"nombre":"A","momento":"cena","detalle":"Con comida"},
          {"nombre":"B","momento":"cena","detalle":["Uno","","Dos"]},
          {"nombre":"C","momento":"cena","detalle":null}]},"esquema":1}
        """)
        let it = try #require(r.suplementacion?.items)
        #expect(it[0].detalle == ["Con comida"])
        #expect(it[1].detalle == ["Uno", "Dos"])
        #expect(it[2].detalle.isEmpty)
    }

    @Test func diasTextoOLista() throws {
        let r = try respuesta("""
        {"suplementacion":{"items":[
          {"nombre":"A","momento":"cena","dias":"descanso"},
          {"nombre":"B","momento":"cena","dias":["lunes","Miércoles","vie"]},
          {"nombre":"C","momento":"cena","dias":"todos"},
          {"nombre":"D","momento":"cena"}]}}
        """)
        let it = try #require(r.suplementacion?.items)
        #expect(it.map(\.dias) == [["descanso"], ["lunes", "Miércoles", "vie"], ["todos"], []])
        #expect(it.map { ReglasSuplementacion.textoDias($0.dias) } == ["Días de descanso", "Lunes, miércoles y viernes", nil, nil])
        #expect(ReglasSuplementacion.textoDias(["gym"]) == "Días de entreno")
        #expect(ReglasSuplementacion.textoDias(["gym", "sábado"]) == "Días de entreno y sábado")
        #expect(ReglasSuplementacion.textoDias(["feriados"]) == "Feriados", "lo que no se conoce, tal cual")
    }

    /// `dias` se lee elemento por elemento: un número no se lleva a los demás (antes `["lunes", 3]` daba «todos los días»).
    @Test func diasConUnNumeroNoPierdeLosDemas() throws {
        let r = try respuesta("""
        {"suplementacion":{"items":[
          {"nombre":"A","momento":"cena","dias":["lunes",3]},
          {"nombre":"B","momento":"cena","dias":["lunes",null,true,{"x":1},["mar"],"vie"]},
          {"nombre":"C","momento":"cena","dias":3},
          {"nombre":"D","momento":"cena","dias":{"x":1}}]}}
        """)
        let it = try #require(r.suplementacion?.items)
        #expect(it.map(\.dias) == [["lunes", "3"], ["lunes", "vie"], ["3"], []])
        #expect(ReglasSuplementacion.textoDias(it[0].dias) == "Lunes y 3")
        #expect(ReglasSuplementacion.textoDias(it[1].dias) == "Lunes y viernes")
        #expect(ReglasSuplementacion.textoDias(it[3].dias) == nil)
    }

    /// Los mismos casos que corre Android (`apps/shared/vectores/texto_dias.json`): `dias` como llega en el jsonb, leído
    /// como lo lee la app, y el texto que se muestra.
    @Test func diasConLosVectoresCompartidos() throws {
        let url = raizRepo.appendingPathComponent("apps/shared/vectores/texto_dias.json")
        let raiz = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let casos = try #require(raiz["casos"] as? [[String: Any]])
        #expect(casos.count >= 15)
        for c in casos {
            let crudo = String(decoding: try JSONSerialization.data(withJSONObject: c["dias"] ?? NSNull(), options: [.fragmentsAllowed]), as: UTF8.self)
            let r = try respuesta(#"{"suplementacion":{"items":[{"nombre":"X","momento":"cena","dias":"# + crudo + "}]}}")
            let item = try #require(r.suplementacion?.items.first)
            #expect(ReglasSuplementacion.textoDias(item.dias) == c["texto"] as? String, "dias = \(crudo)")
        }
    }

    @Test func esquemaDosConCamposNuevosSeLeeIgual() throws {
        let r = try respuesta("""
        {"suplementacion":{"titulo":"Tu suple","color":"#fff","dia":[{"id":"cena","icono":"luna"}],
          "items":[{"nombre":"Zinc","cantidad":"15 mg","momento":"cena","estado":"nuevo","marca":{"x":1},"prioridad":3},
                   {"nombre":"Taurina","momento":"cena","estado":"pausa"}],
          "extra":[1,2,3]},
         "fase":"final","esquema":2,"otra":"cosa"}
        """)
        #expect(r.esquema == 2 && r.hay)
        let v = try #require(VistaSuplementacion(r.suplementacion))
        #expect(v.titulo == "Tu suple")
        #expect(v.momentos.map(\.titulo) == ["Cena"])
        #expect(v.momentos[0].filas.map(\.nombre) == ["Zinc", "Taurina"])
        #expect(ReglasSuplementacion.estado(v.items[1].estado) == nil, "un estado nuevo va sin etiqueta, no rompe")
    }

    @Test func formasRotasNoRompen() throws {
        // Sin suplementación, null, o con otra forma: no hay (la pestaña no aparece) y nada tira.
        #expect(try !respuesta(#"{"suplementacion":null,"esquema":1}"#).hay)
        #expect(try !respuesta(#"{"suplementacion":"hola"}"#).hay)
        #expect(try !respuesta(#"{"suplementacion":{"items":[]}}"#).hay)
        #expect(try !respuesta(#"{"suplementacion":{"items":[{"cantidad":"5 g"}]}}"#).hay, "sin nombre no va")
        #expect(try respuesta(#"{"suplementacion":{"items":[{"nombre":"A"}]},"esquema":"x"}"#).esquema == 1)
        // Un ítem roto no se lleva a los demás.
        let r = try respuesta(#"{"suplementacion":{"items":[{"nombre":"A","momento":"cena"},42,null,{"nombre":"B","comprar":"Zinc"}]}}"#)
        #expect(r.suplementacion?.items.map(\.nombre) == ["A", "B"])
        #expect(r.suplementacion?.items[1].comprar?.buscar == "Zinc")
    }

    @Test func laCopiaGuardadaVuelveIgual() throws {
        let r = try respuesta(ejemploContratoSuplementacion)
        let otra = try JSONDecoder().decode(RespuestaSuplementacion.self, from: JSONEncoder().encode(r))
        #expect(otra == r)
    }

    @Test func laMuestraDeLaDemo() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../shared/demo/suplementacion.json")
        let r = try JSONDecoder().decode(RespuestaSuplementacion.self, from: Data(contentsOf: url))
        let v = try #require(VistaSuplementacion(r.suplementacion))
        #expect(v.momentos.count == 3 && v.sale.count == 1)
    }
}

@Suite("Suplementación: Tu día (la agrupación de la guía)")
struct SuplementacionAgrupacionTests {
    @Test func elEjemploDelContratoPorMomento() throws {
        let v = try #require(VistaSuplementacion(try respuesta(ejemploContratoSuplementacion).suplementacion))
        #expect(v.titulo == "Tu suplementación" && v.accion == "Empezá esta semana con lo nuevo")
        #expect(v.momentos.map(\.titulo) == ["Con el desayuno", "30 a 60 minutos antes de entrenar", "30 minutos antes de acostarte"])
        #expect(v.momentos[0].filas.map(\.nombre) == ["Creatina monohidrato", "Omega 3"])
        #expect(v.momentos[0].filas.map(\.cantidad) == ["5 g", "1 g"])
        #expect(v.momentos[1].filas.map(\.nombre) == ["Cafeína"])
        #expect(v.momentos[2].filas.map(\.nombre) == ["Omega 3", "Magnesio glicinato"])
        // Las dos tomas del omega abren el mismo ítem.
        #expect(v.momentos[0].filas[1].item == 1 && v.momentos[2].filas[0].item == 1)
        #expect(v.items[v.momentos[2].filas[1].item].nombre == "Magnesio glicinato")
        // Lo que sale no va en el día: va aparte, con su porqué.
        #expect(!v.momentos.flatMap(\.filas).contains { $0.nombre == "Multivitamínico" })
        #expect(v.sale.map(\.nombre) == ["Multivitamínico"] && v.sale[0].porQue == "Ya lo cubrís con la dieta")
        #expect(v.items[v.sale[0].item].nombre == "Multivitamínico")
    }

    @Test func momentoDesconocidoVaAlFinalConSuNombre() throws {
        let s = SuplementacionGuia(dia: [MomentoDia(id: "cena"), MomentoDia(id: "siesta", nombre: "Después de la siesta")], items: [
            ItemSuplemento(nombre: "A", momento: "siesta"), ItemSuplemento(nombre: "B", momento: "cena"),
            ItemSuplemento(nombre: "C", momento: "post_cardio"), ItemSuplemento(nombre: "D", momento: "despertar"),
        ])
        let v = try #require(VistaSuplementacion(s))
        // dia[] manda (con su nombre o el texto propio del id); lo que no está en dia[] va después, el desconocido al final.
        #expect(v.momentos.map(\.titulo) == ["Cena", "Después de la siesta", "Al despertar", "Post cardio"])
    }

    @Test func soloSaleNoArmaElDia() throws {
        let s = SuplementacionGuia(items: [ItemSuplemento(nombre: "Quemador", estado: "sale", porQue: "No lo necesitás")])
        let v = try #require(VistaSuplementacion(s))
        #expect(v.momentos.isEmpty && v.sale.map(\.nombre) == ["Quemador"])
    }

    @Test func estados() {
        #expect(ReglasSuplementacion.estado(nil) == .nuevo, "si falta, nuevo (contrato)")
        #expect(ReglasSuplementacion.estado("") == .nuevo)
        #expect(ReglasSuplementacion.Estado.allCases.allSatisfy { ReglasSuplementacion.estado($0.rawValue) == $0 })
        #expect(ReglasSuplementacion.estado("Sale") == nil, "exactos, como la guía y la web")
        #expect(!ReglasSuplementacion.Estado.sigue.destacada && ReglasSuplementacion.Estado.cambia.destacada)
        #expect(["nuevo", "cambia", "sube", "baja", "vuelve"].compactMap { ReglasSuplementacion.estado($0)?.texto }
                == ["Nuevo", "Cambia", "Sube", "Baja", "Vuelve"])
    }

    @Test func dosisYTomasDelDetalle() throws {
        let s = try #require(try respuesta(ejemploContratoSuplementacion).suplementacion)
        #expect(ReglasSuplementacion.dosis(s.items[3]) == "200 mg → 400 mg")
        #expect(ReglasSuplementacion.dosis(s.items[0]) == "5 g")
        #expect(ReglasSuplementacion.dosis(s.items[1]) == nil, "el omega lleva la cantidad en cada toma")
        let tomas = ReglasSuplementacion.tomas(s.items[1], dia: s.dia)
        #expect(tomas.map(\.momento) == ["Con el desayuno", "30 minutos antes de acostarte"] && tomas.map(\.cantidad) == ["1 g", "1 g"])
        #expect(ReglasSuplementacion.tomas(s.items[2], dia: s.dia).map(\.momento) == ["30 a 60 minutos antes de entrenar"])
        #expect(ReglasSuplementacion.tomas(s.items[4], dia: s.dia).isEmpty)
    }

    @Test func dosisHablada() throws {
        let s = try #require(try respuesta(ejemploContratoSuplementacion).suplementacion)
        #expect(ReglasSuplementacion.dosisHablada(s.items[3]) == "Antes 200 mg, ahora 400 mg")
        #expect(ReglasSuplementacion.dosisHablada(s.items[0]) == "5 g")
        let r = try respuesta(#"{"suplementacion":{"items":[{"nombre":"A","cantidad":"5 g","antes":""},{"nombre":"B","cantidad":"5 g","antes":"5 g"}]}}"#)
        #expect(r.suplementacion?.items.map { ReglasSuplementacion.dosisHablada($0) } == ["5 g", "5 g"])
        #expect(r.suplementacion?.items.map { ReglasSuplementacion.dosis($0) } == ["5 g", "5 g"])
    }

    /// El detalle abierto se busca por su lugar y se confirma por el nombre: si un refresco puso otro ahí, se cierra.
    @Test func detalleAbiertoPorLugarYNombre() throws {
        let antes = try #require(try respuesta(ejemploContratoSuplementacion).suplementacion?.items)
        #expect(ReglasSuplementacion.itemAbierto(antes, indice: 1, nombre: "Omega 3")?.nombre == "Omega 3")
        // Un refresco sacó la creatina: en el lugar 1 quedó otro suplemento.
        let despues = Array(antes.dropFirst())
        #expect(ReglasSuplementacion.itemAbierto(despues, indice: 1, nombre: "Omega 3") == nil)
        // La lista se achicó y el lugar ya no existe.
        #expect(ReglasSuplementacion.itemAbierto(Array(despues.prefix(1)), indice: 3, nombre: "Magnesio glicinato") == nil)
        #expect(ReglasSuplementacion.itemAbierto(antes, indice: -1, nombre: "Omega 3") == nil)
        // El mismo nombre en el mismo lugar, con la dosis cambiada: sigue abierto, con lo nuevo.
        var cambiada = antes
        cambiada[3].cantidad = "600 mg"
        #expect(ReglasSuplementacion.itemAbierto(cambiada, indice: 3, nombre: "Magnesio glicinato")?.cantidad == "600 mg")
    }

    @Test func loQueLeeVoiceOver() throws {
        let r = try respuesta(ejemploContratoSuplementacion)
        let v = try #require(VistaSuplementacion(r.suplementacion))
        let cafe = v.momentos[1].filas[0]
        #expect(ReglasSuplementacion.descripcionHablada(cafe, item: v.items[cafe.item])
                == "Cafeína, 200 mg, Nuevo, opcional, Días de entreno, No después de las 17")
        let omega = v.momentos[0].filas[1]
        #expect(ReglasSuplementacion.descripcionHablada(omega, item: v.items[omega.item]) == "Omega 3, 1 g")
    }
}
