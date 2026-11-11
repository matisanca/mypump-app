import Foundation
import MyPumpModelos

/// Todo lo que lee el alumno en «Presión arterial». `T` son los textos del protocolo (presion/PROTOCOLO.md y GRAFICOS.md), que
/// van tal cual; `N` son los propios de la app. La referencia es `public/js/presion.js`: para cambiar un texto se cambia allá, acá
/// y en el gemelo de Android (`apps/shared/vectores/presion.json` hace fallar las pruebas si difieren).
///
/// El alumno no ve promedios, categorías ni colores de riesgo, y ningún texto dice «hipertensión», «normal» ni «riesgo».
public enum TextosPresion {
    /// El nombre que ve el alumno de cada síntoma, por código.
    public static let sintomas: [String: String] = ["dolor_pecho": "Dolor de pecho", "falta_aire": "Falta de aire", "cefalea_fuerte_nueva": "Dolor de cabeza fuerte y distinto", "cambios_vista": "Cambios en la vista", "debilidad_un_lado": "Debilidad u hormigueo de un lado del cuerpo", "dificultad_hablar": "Dificultad para hablar", "confusion": "Confusión", "desmayo": "Desmayo", "palpitaciones": "Palpitaciones", "mareo_al_pararse": "Mareo al pararse", "vomitos_diarrea": "Vómitos o diarrea"]

    /// Textos del protocolo.
    public enum T {
        public static let antes = ["Para esto necesitás un tensiómetro automático de brazo. El reloj no sirve. Si ya tenés uno de muñeca, por ahora lo usamos, pero vas a tener que comprar uno de brazo.", "Antes de comprarlo medite el brazo con un centímetro de costura. Medí en la mitad entre el hombro y el codo, con el brazo relajado al costado del cuerpo y sin haber entrenado ese día.", "Con esa medida la app te muestra qué aparatos sirven. El manguito trae impreso un rango en centímetros y tu medida tiene que entrar en ese rango. Si quedás justo en el límite entre dos talles, elegí el más grande.", "Sacale una foto al tensiómetro y otra a la etiqueta del manguito y subilas acá. Yo te confirmo si sirve."]
        public static let medirBrazo = ["Usá un centímetro de costura, de los blandos.", "Medí el brazo en el que te vas a tomar la presión. Sacate la remera o subí bien la manga.", "Dejá el brazo relajado, colgando al costado del cuerpo, sin hacer fuerza.", "Buscá la mitad entre la punta del hombro y la punta del codo. Si podés, pedile a alguien que te ayude.", "Rodeá el brazo a esa altura, sobre la piel, derecho y sin apretar.", "Anotá los centímetros. Si dudás entre dos números, anotá el más alto.", "No te midas recién entrenado ni con el brazo hinchado. Hacelo un día de descanso o antes de entrenar."]
        public static let medirDeNuevo = "Antes de empezar, medite de nuevo el brazo y anotalo."
        public static let g3 = ["Medí en la mitad entre el hombro y el codo", "Brazo relajado y sin haber entrenado ese día", "Tu medida tiene que entrar en el rango que trae impreso el manguito", "Si quedás justo entre dos talles, elegí el más grande"]
        public static let g3Alt = "Brazo relajado con un centímetro alrededor, en la mitad entre el hombro y el codo. Abajo, una etiqueta de manguito con su rango en centímetros y una barra de talles de chico a extra grande."
        public static let tramos = ["estandar": "Estándar", "grande": "Grande", "extra_grande": "Extra grande", "mas_52": "Te indico yo"]
        public static let tramosRango = ["estandar": "22 a 32 cm", "grande": "32 a 42 cm", "extra_grande": "42 a 52 cm", "mas_52": "Más de 52 cm"]
        public static let marca42 = "Más de 42 cm, manguito más grande, mejor si es cónico"
        public static let verCuales = "Ver cuáles sirven"
        public static let fueraDeTalle = "Ese manguito no es de tu talle. Mandame una foto de la etiqueta y lo vemos."
        public static let porTramo = ["estandar": "Con tu medida te sirve casi cualquier tensiómetro de brazo de esta lista. Fijate que el código de la caja sea igual al de la lista, con las letras del final.", "grande": "Con tu medida necesitás un manguito que llegue hasta 42. Te dejo cuáles sirven. Fijate que el código de la caja sea igual al de la lista, con las letras del final.", "extra_grande": "Con tu medida necesitás un manguito más grande, que en general se compra aparte. Te dejo cuáles sirven.", "mas_52": "Con tu medida te indico yo cuál usar. Si ya tenés un tensiómetro, subí las fotos y te digo."]
        public static let muneca = ["Por ahora usamos el de muñeca, pero necesito que compres uno de brazo.", "Te dejo cuáles sirven según la medida de tu brazo."]
        public static let munecaNoValidada = "Ese de muñeca no está entre los que miden bien. Te dejo cuáles sirven."
        public static let noValidado = ["Ese tensiómetro no está entre los que miden bien. Por ahora lo usamos, pero necesito que compres uno de la lista.", "Te dejo cuáles sirven según la medida de tu brazo."]
        public static let cuandoTitulo = "Cuándo"
        public static let cuando = ["Son 3 tomas en total, una por día, en 3 días distintos de la misma semana.", "A la mañana, después de hacer pis y antes de desayunar, del mate o el café, del preentreno, de tus remedios y de entrenar.", "En la media hora previa nada de cigarrillo, vapeador, comida, café, mate, energizante ni preentreno."]
        public static let comoTitulo = "Cómo"
        public static func como(_ brazo: String?) -> [String] { [
            "Sentate en una silla con respaldo, al lado de una mesa, en un lugar tranquilo. Espalda apoyada, pies planos en el piso y piernas sin cruzar.",
            "Apoyá el brazo \(brazo == "der" ? "derecho" : "izquierdo") en la mesa, relajado y con la palma para arriba. El manguito va sobre la piel, nunca sobre la ropa. Si la manga te aprieta al subirla, sacate la remera.",
            "La mitad del manguito tiene que quedar a la altura del corazón. Si la mesa es baja, poné un almohadón abajo del brazo.",
            "El borde de abajo del manguito va 2 o 3 centímetros arriba del pliegue del codo, con la marca de la arteria del lado de adentro del brazo. Ajustalo firme, que entre justo un dedo.",
            "Quedate 5 minutos quieto, sin hablar ni mirar el celular.",
            "Hacé la toma y anotá la alta, la baja y el pulso. Si el aparato muestra el símbolo de latido irregular, marcalo.",
            "Si sale error, revisá el manguito, esperá un minuto y repetí.",
            "Listo por hoy. La próxima, otro día.",
        ] }
        public static let g1 = ["Espalda apoyada", "Pies planos en el piso y piernas sin cruzar", "Brazo apoyado en la mesa", "La mitad del manguito a la altura del corazón", "5 minutos quieto y sin hablar"]
        public static let g1Alt = "Persona sentada de costado en una silla con respaldo, con la espalda apoyada, los pies en el piso, el brazo sobre la mesa y el manguito a la altura del corazón."
        public static let g2 = [["Brazo colgando", "Da más alto"], ["A la altura del corazón", "Así sí"], ["Brazo levantado", "Da más bajo"]]
        public static let g2Alt = "Tres dibujos. Con el brazo colgando la presión da más alta, con el brazo levantado da más baja y con el manguito a la altura del corazón da bien."
        public static let g4 = ["2 o 3 centímetros arriba del pliegue del codo", "La marca de la arteria va del lado de adentro", "Firme, que entre justo un dedo", "Sobre la piel, nunca sobre la ropa"]
        public static let g4Alt = "Brazo visto del lado de adentro con el manguito sobre la piel, dos o tres centímetros arriba del pliegue del codo, con la marca de la arteria del lado de adentro y un dedo que entra justo debajo del borde."
        public static let queEvitar = "Qué evitar"
        public static let g5 = [["Hablar o mirar el celular", "Ni antes ni durante la toma"], ["Piernas cruzadas", "Pies planos en el piso"], ["Sobre la ropa", "El manguito va sobre la piel"], ["Brazo colgando", "Apoyalo en la mesa"], ["Medirte recién entrenado", "Esperá al menos una hora"], ["Café, mate, energizante o preentreno", "Nada en la media hora previa"], ["Cigarrillo o vapeador", "Nada en la media hora previa"], ["Con ganas de hacer pis", "Andá al baño antes"], ["Sillón blando o sin respaldo", "Silla con respaldo recto"], ["Reloj o anillo para medir", "Solo tensiómetro de brazo"]]
        public static let g5Alt = "Diez cosas que hay que evitar al medirte la presión. Hablar o mirar el celular, cruzar las piernas, poner el manguito sobre la ropa, dejar el brazo colgando, medirte recién entrenado, tomar café, mate, energizante o preentreno, fumar o vapear, medirte con ganas de hacer pis, sentarte en un sillón blando y usar un reloj o un anillo para medir."
        public static let bien = "Bien"
        public static let asiNo = "Así no"
        public static let bajoEfecto = ["Estas 3 tomas son con el estimulante hecho efecto. Medite entre 1 y 2 horas después de tomarlo, en 3 días distintos.", "Hacé la toma antes de entrenar. Si entrenaste entre la dosis y la toma, esa no cuenta y la hacés otro día.", "Sentado, con la espalda apoyada y el brazo a la altura del corazón. Esperá 5 minutos sin hablar y medite, igual que en las otras tomas.", "Anotá a qué hora tomaste el estimulante."]
        public static let brazos = ["Hoy hacé 4 tomas en este orden, izquierdo, derecho, derecho e izquierdo, con un minuto de descanso entre cada una.", "Estas no cuentan para el promedio. Sirven para ver qué brazo usar."]
        public static func ortostatica(sentado: Bool) -> [String] {
            var p = ["Hacela a la mañana, después de la toma sentado, con el mismo manguito puesto.", "Hacela al lado de la cama, sin nadie apurándote."]
            if sentado { p.append("Sentado 5 minutos y una toma") } else {
                p.append("Acostate boca arriba 5 minutos. Dejá el brazo apoyado sobre una almohada chica, a la altura del medio del pecho.")
                p.append("Hacé una toma acostado.")
            }
            return p + [
                "Parate al lado de la cama. Apoyá el antebrazo en un mueble alto o sostenelo con la otra mano, así el manguito queda a la altura del corazón. No dejes el brazo colgando.",
                "Cuando la app marque un minuto parado, hacé una toma.",
                "Cuando marque 3 minutos parado, hacé otra.",
                "Si te mareás, se te nubla la vista o sentís que te vas a desmayar, sentate o acostate enseguida y marcalo. No hace falta terminar.",
            ]
        }
        public static func g6(sentado: Bool) -> [String] { [sentado ? "Sentado 5 minutos y una toma" : "Acostado 5 minutos y una toma", "Parado, toma al minuto 1", "Parado, toma al minuto 3"] }
        public static let g6Mareo = "Si te mareás, sentate o acostate enseguida"
        public static let g6Antebrazo = "Antebrazo apoyado, sin dejarlo colgando"
        public static let g6Alt = "Tres dibujos. Acostado cinco minutos con una toma, después parado con el antebrazo apoyado y tomas al minuto uno y al minuto tres. Si te mareás, sentate o acostate enseguida."
        public static func faltan(_ n: Int) -> String { n == 1 ? "Te falta 1 toma" : "Te faltan \(n) tomas" }
        public static func avanceAlt(_ n: Int, _ total: Int) -> String {
            let hechas = ["cero", "una", "dos", "tres"]
            return "\(total == 3 ? "Tres" : "\(total)") círculos, uno por toma. Completaste \(hechas.indices.contains(n) ? hechas[n] : "\(n)") de \(total == 3 ? "tres" : "\(total)")."
        }
        public static let listoSerie = "Listo, terminaste las 3 tomas. Gracias."
        public static let listoSerieCorto = "Listo, terminaste las 3 tomas"
        public static let marcarSintoma = "Marcar un síntoma"
        public static let esperaTitulo = "Quedate sentado y tranquilo. En 5 minutos volvé a medirte."
        public static let esperaLista = "Mientras esperás, decime si tenés alguno de estos."
        public static let esperaVoz = "Faltan 5 minutos para volver a medirte."
        public static let si = "Sí"
        public static let no = "No"
        public static let repetirPendiente = "Te quedó pendiente repetir la toma. Hacela sentado y tranquilo cuando puedas."
        public static let guardiaPresion = ["Con estos valores tiene que verte un médico hoy. Andá a una guardia.", "No tomes nada por tu cuenta para bajarla. Si ya tenés un remedio para la presión indicado, tomalo como siempre, sin doblarlo.", "Si aparece dolor de pecho, falta de aire, debilidad de un lado del cuerpo o te cuesta hablar, no vayas manejando y llamá a emergencias."]
        public static let guardiaSintomas = ["Con lo que marcaste tiene que verte un médico ahora. Andá a una guardia.", "No vayas manejando. Si es dolor de pecho, falta de aire, debilidad de un lado del cuerpo o te cuesta hablar, llamá a emergencias."]
        public static let sentateAgua = "Sentate o acostate un rato y tomá agua. Escribime cuando puedas."
        public static let mareoOrtostatica = "Quedate sentado o acostado hasta que se te pase."
        public static let latidoIrregular = "Gracias, seguí como siempre."
        public static let revisarNumero = "Revisá el número que anotaste. Si podés, sacale una foto a la pantalla del aparato."
        public static let revisarNumeroSinFoto = "Revisá el número que anotaste."
        public static let noCuenta = "Esta no cuenta. Hacé otra otro día, antes del café y del preentreno."
        public static let recordatorioManana = "Buen día, te toca la presión antes de desayunar."

        /// Todo, con la forma de `textos` en los vectores.
        public static let todos: JSONValue = .objeto([
            "antes": .lista(antes.map(JSONValue.texto)), "medirBrazo": .lista(medirBrazo.map(JSONValue.texto)), "medirDeNuevo": .texto(medirDeNuevo),
            "g3": .lista(g3.map(JSONValue.texto)), "g3Alt": .texto(g3Alt), "tramos": .objeto(tramos.mapValues(JSONValue.texto)),
            "tramosRango": .objeto(tramosRango.mapValues(JSONValue.texto)), "marca42": .texto(marca42), "verCuales": .texto(verCuales),
            "fueraDeTalle": .texto(fueraDeTalle), "porTramo": .objeto(porTramo.mapValues(JSONValue.texto)), "muneca": .lista(muneca.map(JSONValue.texto)),
            "munecaNoValidada": .texto(munecaNoValidada), "noValidado": .lista(noValidado.map(JSONValue.texto)), "cuandoTitulo": .texto(cuandoTitulo),
            "cuando": .lista(cuando.map(JSONValue.texto)), "comoTitulo": .texto(comoTitulo), "g1": .lista(g1.map(JSONValue.texto)), "g1Alt": .texto(g1Alt),
            "g2": .lista(g2.map { .lista($0.map(JSONValue.texto)) }), "g2Alt": .texto(g2Alt), "g4": .lista(g4.map(JSONValue.texto)), "g4Alt": .texto(g4Alt),
            "queEvitar": .texto(queEvitar), "g5": .lista(g5.map { .lista($0.map(JSONValue.texto)) }), "g5Alt": .texto(g5Alt), "bien": .texto(bien),
            "asiNo": .texto(asiNo), "bajoEfecto": .lista(bajoEfecto.map(JSONValue.texto)), "brazos": .lista(brazos.map(JSONValue.texto)), "g6Mareo": .texto(g6Mareo),
            "g6Antebrazo": .texto(g6Antebrazo), "g6Alt": .texto(g6Alt), "listoSerie": .texto(listoSerie), "listoSerieCorto": .texto(listoSerieCorto),
            "marcarSintoma": .texto(marcarSintoma), "esperaTitulo": .texto(esperaTitulo), "esperaLista": .texto(esperaLista), "esperaVoz": .texto(esperaVoz),
            "si": .texto(si), "no": .texto(no), "repetirPendiente": .texto(repetirPendiente), "guardiaPresion": .lista(guardiaPresion.map(JSONValue.texto)),
            "guardiaSintomas": .lista(guardiaSintomas.map(JSONValue.texto)), "sentateAgua": .texto(sentateAgua), "mareoOrtostatica": .texto(mareoOrtostatica),
            "latidoIrregular": .texto(latidoIrregular), "revisarNumero": .texto(revisarNumero), "revisarNumeroSinFoto": .texto(revisarNumeroSinFoto),
            "noCuenta": .texto(noCuenta), "recordatorioManana": .texto(recordatorioManana), "comoIzq": .lista(como("izq").map(JSONValue.texto)),
            "comoDer": .lista(como("der").map(JSONValue.texto)), "ortostaticaAcostado": .lista(ortostatica(sentado: false).map(JSONValue.texto)),
            "ortostaticaSentado": .lista(ortostatica(sentado: true).map(JSONValue.texto)), "g6Acostado": .lista(g6(sentado: false).map(JSONValue.texto)),
            "g6Sentado": .lista(g6(sentado: true).map(JSONValue.texto)), "faltan1": .texto(faltan(1)), "faltan2": .texto(faltan(2)),
            "avanceAlt2": .texto(avanceAlt(2, 3)),
        ])
    }

    /// Textos propios de la app (botones, títulos y preguntas).
    public enum N {
        public static let titulo = "Presión"
        public static let entrada = "Presión arterial"
        public static let antesTitulo = "Antes de la primera serie"
        public static let medirBrazoTitulo = "Cómo medirte el brazo"
        public static let medida = "Medida del brazo, en centímetros"
        public static let tipoAparato = "¿Qué tensiómetro tenés?"
        public static let tipos = ["brazo": "De brazo", "muneca": "De muñeca", "reloj_anillo_otro": "Reloj, anillo u otro", "ninguno": "Todavía no tengo"]
        public static let marca = "Marca"
        public static let modelo = "Modelo"
        public static let codigo = "Código de la etiqueta"
        public static let codigoAyuda = "Copialo tal cual, con las letras del final"
        public static let rango = "Rango impreso en el manguito, en centímetros"
        public static let desde = "Desde"
        public static let hasta = "Hasta"
        public static let guardar = "Guardar"
        public static let seguir = "Seguir"
        public static let empezar = "Empezar"
        public static let cerrar = "Cerrar"
        public static let volver = "Volver"
        public static let tomaDeHoy = "Hacer la toma de hoy"
        public static let tomaSuelta = "Anotar una toma"
        public static let repetir = "Repetir la toma"
        public static let previas = "Antes de medirte"
        public static let previa = ["cafeina": "¿Tomaste café, mate, energizante o preentreno en la última media hora?", "fumo": "¿Fumaste o vapeaste en la última media hora?", "comida": "¿Comiste en la última media hora?", "ejercicio": "¿Entrenaste en la última hora?"]
        public static let esperarMejor = "Mejor esperá un rato y medite después."
        public static let esperar = "Esperar"
        public static let medirIgual = "Medirme igual"
        public static let reposo = "Quedate 5 minutos quieto, sin hablar ni mirar el celular"
        public static let saltear = "Ya esperé"
        public static let alta = "Alta"
        public static let baja = "Baja"
        public static let pulso = "Pulso"
        public static let irregular = "El aparato mostró el símbolo de latido irregular"
        public static let anotar = "Anotar la toma"
        public static let confirmar = "Sí, es ese número"
        public static let corregir = "Corregir"
        public static let horaDosis = "¿A qué hora tomaste el estimulante?"
        public static let entrenoEntre = "¿Entrenaste entre la dosis y la toma?"
        public static let alarma = "Avisame si tenés alguno de estos"
        public static let otros = "Otros"
        public static let nota = "Si querés, contame algo más"
        public static let enviar = "Enviar"
        public static let sintomaRecibido = "Anotado."
        public static let tusTomas = "Tus tomas"
        public static let sinTomas = "Todavía no anotaste ninguna toma"
        public static let hoyListo = "La de hoy ya está. La próxima, otro día."
        public static let relojNoSirve = "El reloj y el anillo no sirven para esto. Hace falta un tensiómetro de brazo."
        public static let aparato = "Tu tensiómetro"
        public static let cambiarAparato = "Cambiar"
        public static let brazo = "Brazo"
        public static let cm = "cm"
        public static let sinSenal = "Sin señal. Queda guardada y se manda sola."
        public static let meMaree = "Me mareé"
        public static func minutoParado(_ n: Int) -> String { n == 1 ? "Toma al minuto 1" : "Toma al minuto 3" }
        public static let sinLista = "Todavía estamos armando la lista para tu país."
        public static func graficoAlt(_ n: Int) -> String { "Gráfico con tus \(n) tomas, alta y baja, por día." }

        public static let brazoIzq = "Brazo izquierdo"
        public static let brazoDer = "Brazo derecho"
        public static let noGuardo = "No se pudo guardar. Probá de nuevo."
        // La tarjeta de arriba en Entreno.
        public static let tarjeta = "Tu presión"
        public static let tarjetaPreparar = "Primero medí tu brazo y anotá tu tensiómetro"
        public static let tarjetaSerie = "Son 3 tomas, una por día"

        /// Todo, con la forma de `propios` en los vectores.
        public static let todos: JSONValue = .objeto([
            "titulo": .texto(titulo), "entrada": .texto(entrada), "antesTitulo": .texto(antesTitulo), "medirBrazoTitulo": .texto(medirBrazoTitulo),
            "medida": .texto(medida), "tipoAparato": .texto(tipoAparato), "tipos": .objeto(tipos.mapValues(JSONValue.texto)), "marca": .texto(marca),
            "modelo": .texto(modelo), "codigo": .texto(codigo), "codigoAyuda": .texto(codigoAyuda), "rango": .texto(rango), "desde": .texto(desde),
            "hasta": .texto(hasta), "guardar": .texto(guardar), "seguir": .texto(seguir), "empezar": .texto(empezar), "cerrar": .texto(cerrar),
            "volver": .texto(volver), "tomaDeHoy": .texto(tomaDeHoy), "tomaSuelta": .texto(tomaSuelta), "repetir": .texto(repetir), "previas": .texto(previas),
            "previa": .objeto(previa.mapValues(JSONValue.texto)), "esperarMejor": .texto(esperarMejor), "esperar": .texto(esperar), "medirIgual": .texto(medirIgual),
            "reposo": .texto(reposo), "saltear": .texto(saltear), "alta": .texto(alta), "baja": .texto(baja), "pulso": .texto(pulso), "irregular": .texto(irregular),
            "anotar": .texto(anotar), "confirmar": .texto(confirmar), "corregir": .texto(corregir), "horaDosis": .texto(horaDosis),
            "entrenoEntre": .texto(entrenoEntre), "alarma": .texto(alarma), "otros": .texto(otros), "nota": .texto(nota), "enviar": .texto(enviar),
            "sintomaRecibido": .texto(sintomaRecibido), "tusTomas": .texto(tusTomas), "sinTomas": .texto(sinTomas), "hoyListo": .texto(hoyListo),
            "relojNoSirve": .texto(relojNoSirve), "aparato": .texto(aparato), "cambiarAparato": .texto(cambiarAparato), "brazo": .texto(brazo), "cm": .texto(cm),
            "sinSenal": .texto(sinSenal), "meMaree": .texto(meMaree), "sinLista": .texto(sinLista), "minutoParado1": .texto(minutoParado(1)),
            "minutoParado3": .texto(minutoParado(3)), "graficoAlt3": .texto(graficoAlt(3)),
            "brazoIzq": .texto(brazoIzq), "brazoDer": .texto(brazoDer), "noGuardo": .texto(noGuardo),
            "tarjeta": .texto(tarjeta), "tarjetaPreparar": .texto(tarjetaPreparar), "tarjetaSerie": .texto(tarjetaSerie),
        ])
    }
}
