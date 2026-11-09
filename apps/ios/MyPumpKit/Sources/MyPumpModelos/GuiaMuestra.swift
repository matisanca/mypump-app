import Foundation

/// Una guía inventada con la forma de `entregas_app_get` (un cliente inventado, «Tomás»): la usan los tests, los previews y
/// las capturas de la maqueta. Nada de un cliente real; los videos apuntan a un dominio que no existe.
public enum GuiaMuestra {
    public static var guia: Guia { Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))) ?? .null) }

    private static func clip(_ id: String, _ titulo: String, _ bloque: String, _ minutos: Double, visto: Bool = false,
                             segundos: Int = 0, duda: String? = nil, motivo: String = "Para qué te sirve este video", url: Bool = true) -> String {
        let u = url ? "\"https://videos.example.invalid/videos-entrega/\(id).mp4\"" : "null"
        let d = duda.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","titulo":"\(titulo)","url":\(u),"yt_id":null,"minutos":\(minutos),"motivo":"\(motivo)","bloque":"\(bloque)","visto":\(visto),"segundos":\(segundos),"duda":\(d)}
        """
    }

    public static let json: String = {
        let clips = [
            clip("FT-25a", "¿Cómo funciona la app?", "Tu app", 1.2, visto: true,
                 motivo: "Conectá tu reloj y subí tu check cada lunes ||| Así ves todo tu plan en un solo lugar"),
            clip("FT-2b", "¿Cómo subo las cargas semana a semana?", "Tu app", 0.3, visto: true),
            clip("FT-2c", "¿Cómo cierro el entrenamiento y paso de semana?", "Tu app", 0.3, visto: true),
            clip("FT-9a", "¿Cómo sustituyo un alimento en la app?", "Tu app", 0.6, visto: true, duda: "¿Puedo cambiar el arroz por fideos?"),
            clip("FT-2a", "¿Qué subo en la revisión semanal?", "Tu app", 0.3, segundos: 9),
            clip("MC-7a", "¿Por qué tu primera serie efectiva te sale floja?", "Lo que no te podés saltear", 1.8),
            clip("FT-3a", "¿Cómo hago el calentamiento y las aproximaciones?", "Lo que no te podés saltear", 1.2),
            clip("MC-13c", "Anotá cargas y repeticiones para saber si progresás", "Tu entrenamiento", 1.2),
            clip("FT-5a", "¿Para qué uso straps en espalda?", "Tu entrenamiento", 0.5, url: false),
            clip("FT-26a", "¿Peso la comida cruda o cocida?", "Tu alimentación", 0.6),
            clip("FT-17a", "¿Qué verduras puedo comer libres?", "Tu alimentación", 0.6),
            clip("FT-1b", "¿Para qué sirve la citrulina?", "Tu suplementación", 0.7),
            clip("FT-4b", "¿Qué magnesio compro y por qué los comunes no sirven?", "Tu suplementación", 0.5, visto: true),
        ]
        return """
        {"ok":true,"nombre_pila":"Tomás","fecha_entrega":null,
         "clips":[\(clips.joined(separator: ","))],
         "dudas_llamada":[{"texto":"¿Puedo entrenar a la noche?","en":"2026-11-04T10:12:00-03:00"}],
         "suplementacion":{"titulo":"Tu suplementación",
          "dia":[{"id":"almuerzo","nombre":"Tu primera comida"},{"id":"pre","nombre":"30 a 60 minutos antes de entrenar"},{"id":"dormir","nombre":"30 minutos antes de acostarte"}],
          "items":[
           {"nombre":"Creatina","estado":"sigue","nota":"una sola toma por día","por_que":"Te sostiene la fuerza y la recuperación",
            "tomas":[{"momento":"pre","cantidad":"5 g","nota":"los días que entrenás"},{"momento":"almuerzo","cantidad":"5 g","nota":"los días que no entrenás"}]},
           {"nombre":"L-citrulina","estado":"nuevo","momento":"pre","cantidad":"6 g","nota":"solo los días que entrenás",
            "por_que":"Mejora la circulación y rendís más en las series","detalle":"Que diga *L-citrulina* sola, no malato.","video_id":"FT-1b"},
           {"nombre":"Bisglicinato de magnesio","estado":"sigue","momento":"dormir","cantidad":"400 mg","nota":"todos los días",
            "por_que":"Te ayuda a dormir más profundo","video_id":"FT-4b"},
           {"nombre":"Melatonina","estado":"nuevo","opcional":true,"momento":"dormir","cantidad":"1 comprimido","nota":"de prueba"},
           {"nombre":"Vitamina C","cantidad":"1 g","nota":"con el desayuno"},
           {"nombre":"Quemador","estado":"sale","por_que":"No suma y te saca el sueño"}
          ],
          "sigue_texto":"Tus gotas de vitamina D, como venías",
          "accion":"Sumá lo nuevo de a uno por día"}}
        """
    }()

    // MARK: - «Lo que más te importa»

    /// El texto de ejemplo, inventado. Trae una parte «## Tu plan para estas semanas» y marcas que no se tienen que ver.
    public static let dolor = DolorGuia(titulo: "Bajar la panza sin perder fuerza", texto: """
    Me contaste que lo que más te molesta es la **panza** y que venís perdiendo fuerza cuando comés poco.

    El plan arranca por ahí, con comida que te llene y una rutina que te sostenga las cargas.

    ## Tu plan para estas semanas

    Las primeras dos semanas el objetivo es que anotes todo y no te saltees comidas.
    """)

    /// La muestra con `dolor`: dos videos pasan al bloque del dolor y uno a la parte. `fecha` es la de la videollamada.
    public static func guiaConDolor(fecha: String? = nil) -> Guia {
        var g = guia
        g.dolor = dolor
        g.fechaEntrega = fecha
        for (i, c) in g.clips.enumerated() {
            if c.id == "MC-7a" || c.id == "FT-3a" { g.clips[i].bloque = "Lo que más te importa" }
            if c.id == "MC-13c" { g.clips[i].bloque = "Tu plan para estas semanas" }
        }
        return g
    }

    // MARK: - La guía v2 (2.2.0): novedad, obligatorios y agenda

    /// La misma forma con lo de la 2.2.0: `fase: 2`, `novedad_en`, dos clips `nuevo` (uno visto y otro no) y los
    /// `obligatorio`. Falta ver un solo obligatorio (`N-1`, el nuevo sin ver): así se prueba «bloqueada → ver el último →
    /// habilitada». `urlPendiente` cambia la url de ese clip (las pruebas de interfaz usan un video que se pueda reproducir)
    /// y `todoVisto` lo deja visto (la agenda habilitada desde el arranque).
    public static func jsonV2(urlPendiente: String? = nil, todoVisto: Bool = false) -> String {
        func clipV2(_ id: String, _ titulo: String, _ bloque: String, _ minutos: Double, visto: Bool, nuevo: Bool, obligatorio: Bool,
                    url: String? = nil) -> String {
            let u = url ?? "https://videos.example.invalid/videos-entrega/\(id).mp4"
            return """
            {"id":"\(id)","titulo":"\(titulo)","url":"\(u)","minutos":\(minutos),"motivo":"Para qué te sirve este video","bloque":"\(bloque)","visto":\(visto),"segundos":0,"duda":null,"nuevo":\(nuevo),"obligatorio":\(obligatorio)}
            """
        }
        let clips = [
            clipV2("FT-25a", "¿Cómo funciona la app?", "Tu app", 1.2, visto: true, nuevo: false, obligatorio: true),
            clipV2("FT-2b", "¿Cómo subo las cargas semana a semana?", "Tu app", 0.3, visto: true, nuevo: false, obligatorio: true),
            clipV2("MC-7a", "¿Por qué tu primera serie efectiva te sale floja?", "Lo que no te podés saltear", 1.8, visto: true, nuevo: false, obligatorio: true),
            clipV2("FT-26a", "¿Peso la comida cruda o cocida?", "Tu alimentación", 0.6, visto: false, nuevo: false, obligatorio: false),
            clipV2("N-1", "Lo que cambia en tu entrenamiento", "Tu entrenamiento", 0.4, visto: todoVisto, nuevo: true, obligatorio: true, url: urlPendiente),
            clipV2("N-2", "Cómo ajustamos tu dieta esta etapa", "Tu alimentación", 0.8, visto: true, nuevo: true, obligatorio: true),
        ]
        return """
        {"ok":true,"nombre_pila":"Tomás","fecha_entrega":null,"fase":2,"novedad_en":"2026-11-05T12:00:00-03:00",
         "clips":[\(clips.joined(separator: ","))],"dudas_llamada":[],"suplementacion":null}
        """
    }

    public static var guiaV2: Guia { Guia(json: (try? JSONDecoder().decode(JSONValue.self, from: Data(jsonV2().utf8))) ?? .null) }
}
