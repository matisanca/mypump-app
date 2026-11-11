package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson

/**
 * Todo lo que lee el alumno en «Presión arterial». [T] son los textos del protocolo (presion/PROTOCOLO.md y GRAFICOS.md), que van
 * tal cual; [N] son los propios de la app. La referencia es `public/js/presion.js`: para cambiar un texto se cambia allá, acá y en
 * el gemelo de iOS (`apps/shared/vectores/presion.json` hace fallar las pruebas si difieren).
 *
 * El alumno no ve promedios, categorías ni colores de riesgo, y ningún texto dice «hipertensión», «normal» ni «riesgo».
 */
object TextosPresion {
    /** El nombre que ve el alumno de cada síntoma, por código. */
    val sintomas: Map<String, String> = mapOf("dolor_pecho" to "Dolor de pecho", "falta_aire" to "Falta de aire", "cefalea_fuerte_nueva" to "Dolor de cabeza fuerte y distinto", "cambios_vista" to "Cambios en la vista", "debilidad_un_lado" to "Debilidad u hormigueo de un lado del cuerpo", "dificultad_hablar" to "Dificultad para hablar", "confusion" to "Confusión", "desmayo" to "Desmayo", "palpitaciones" to "Palpitaciones", "mareo_al_pararse" to "Mareo al pararse", "vomitos_diarrea" to "Vómitos o diarrea")

    /** Textos del protocolo. */
    object T {
        val antes = listOf("Para esto necesitás un tensiómetro automático de brazo. El reloj no sirve. Si ya tenés uno de muñeca, por ahora lo usamos, pero vas a tener que comprar uno de brazo.", "Antes de comprarlo medite el brazo con un centímetro de costura. Medí en la mitad entre el hombro y el codo, con el brazo relajado al costado del cuerpo y sin haber entrenado ese día.", "Con esa medida la app te muestra qué aparatos sirven. El manguito trae impreso un rango en centímetros y tu medida tiene que entrar en ese rango. Si quedás justo en el límite entre dos talles, elegí el más grande.", "Sacale una foto al tensiómetro y otra a la etiqueta del manguito y subilas acá. Yo te confirmo si sirve.")
        val medirBrazo = listOf("Usá un centímetro de costura, de los blandos.", "Medí el brazo en el que te vas a tomar la presión. Sacate la remera o subí bien la manga.", "Dejá el brazo relajado, colgando al costado del cuerpo, sin hacer fuerza.", "Buscá la mitad entre la punta del hombro y la punta del codo. Si podés, pedile a alguien que te ayude.", "Rodeá el brazo a esa altura, sobre la piel, derecho y sin apretar.", "Anotá los centímetros. Si dudás entre dos números, anotá el más alto.", "No te midas recién entrenado ni con el brazo hinchado. Hacelo un día de descanso o antes de entrenar.")
        val medirDeNuevo = "Antes de empezar, medite de nuevo el brazo y anotalo."
        val g3 = listOf("Medí en la mitad entre el hombro y el codo", "Brazo relajado y sin haber entrenado ese día", "Tu medida tiene que entrar en el rango que trae impreso el manguito", "Si quedás justo entre dos talles, elegí el más grande")
        val g3Alt = "Brazo relajado con un centímetro alrededor, en la mitad entre el hombro y el codo. Abajo, una etiqueta de manguito con su rango en centímetros y una barra de talles de chico a extra grande."
        val tramos = mapOf("estandar" to "Estándar", "grande" to "Grande", "extra_grande" to "Extra grande", "mas_52" to "Te indico yo")
        val tramosRango = mapOf("estandar" to "22 a 32 cm", "grande" to "32 a 42 cm", "extra_grande" to "42 a 52 cm", "mas_52" to "Más de 52 cm")
        val marca42 = "Más de 42 cm, manguito más grande, mejor si es cónico"
        val verCuales = "Ver cuáles sirven"
        val fueraDeTalle = "Ese manguito no es de tu talle. Mandame una foto de la etiqueta y lo vemos."
        val porTramo = mapOf("estandar" to "Con tu medida te sirve casi cualquier tensiómetro de brazo de esta lista. Fijate que el código de la caja sea igual al de la lista, con las letras del final.", "grande" to "Con tu medida necesitás un manguito que llegue hasta 42. Te dejo cuáles sirven. Fijate que el código de la caja sea igual al de la lista, con las letras del final.", "extra_grande" to "Con tu medida necesitás un manguito más grande, que en general se compra aparte. Te dejo cuáles sirven.", "mas_52" to "Con tu medida te indico yo cuál usar. Si ya tenés un tensiómetro, subí las fotos y te digo.")
        val muneca = listOf("Por ahora usamos el de muñeca, pero necesito que compres uno de brazo.", "Te dejo cuáles sirven según la medida de tu brazo.")
        val munecaNoValidada = "Ese de muñeca no está entre los que miden bien. Te dejo cuáles sirven."
        val noValidado = listOf("Ese tensiómetro no está entre los que miden bien. Por ahora lo usamos, pero necesito que compres uno de la lista.", "Te dejo cuáles sirven según la medida de tu brazo.")
        val cuandoTitulo = "Cuándo"
        val cuando = listOf("Son 3 tomas en total, una por día, en 3 días distintos de la misma semana.", "A la mañana, después de hacer pis y antes de desayunar, del mate o el café, del preentreno, de tus remedios y de entrenar.", "En la media hora previa nada de cigarrillo, vapeador, comida, café, mate, energizante ni preentreno.")
        val comoTitulo = "Cómo"
        val g1 = listOf("Espalda apoyada", "Pies planos en el piso y piernas sin cruzar", "Brazo apoyado en la mesa", "La mitad del manguito a la altura del corazón", "5 minutos quieto y sin hablar")
        val g1Alt = "Persona sentada de costado en una silla con respaldo, con la espalda apoyada, los pies en el piso, el brazo sobre la mesa y el manguito a la altura del corazón."
        val g2 = listOf(listOf("Brazo colgando", "Da más alto"), listOf("A la altura del corazón", "Así sí"), listOf("Brazo levantado", "Da más bajo"))
        val g2Alt = "Tres dibujos. Con el brazo colgando la presión da más alta, con el brazo levantado da más baja y con el manguito a la altura del corazón da bien."
        val g4 = listOf("2 o 3 centímetros arriba del pliegue del codo", "La marca de la arteria va del lado de adentro", "Firme, que entre justo un dedo", "Sobre la piel, nunca sobre la ropa")
        val g4Alt = "Brazo visto del lado de adentro con el manguito sobre la piel, dos o tres centímetros arriba del pliegue del codo, con la marca de la arteria del lado de adentro y un dedo que entra justo debajo del borde."
        val queEvitar = "Qué evitar"
        val g5 = listOf(listOf("Hablar o mirar el celular", "Ni antes ni durante la toma"), listOf("Piernas cruzadas", "Pies planos en el piso"), listOf("Sobre la ropa", "El manguito va sobre la piel"), listOf("Brazo colgando", "Apoyalo en la mesa"), listOf("Medirte recién entrenado", "Esperá al menos una hora"), listOf("Café, mate, energizante o preentreno", "Nada en la media hora previa"), listOf("Cigarrillo o vapeador", "Nada en la media hora previa"), listOf("Con ganas de hacer pis", "Andá al baño antes"), listOf("Sillón blando o sin respaldo", "Silla con respaldo recto"), listOf("Reloj o anillo para medir", "Solo tensiómetro de brazo"))
        val g5Alt = "Diez cosas que hay que evitar al medirte la presión. Hablar o mirar el celular, cruzar las piernas, poner el manguito sobre la ropa, dejar el brazo colgando, medirte recién entrenado, tomar café, mate, energizante o preentreno, fumar o vapear, medirte con ganas de hacer pis, sentarte en un sillón blando y usar un reloj o un anillo para medir."
        val bien = "Bien"
        val asiNo = "Así no"
        val bajoEfecto = listOf("Estas 3 tomas son con el estimulante hecho efecto. Medite entre 1 y 2 horas después de tomarlo, en 3 días distintos.", "Hacé la toma antes de entrenar. Si entrenaste entre la dosis y la toma, esa no cuenta y la hacés otro día.", "Sentado, con la espalda apoyada y el brazo a la altura del corazón. Esperá 5 minutos sin hablar y medite, igual que en las otras tomas.", "Anotá a qué hora tomaste el estimulante.")
        val brazos = listOf("Hoy hacé 4 tomas en este orden, izquierdo, derecho, derecho e izquierdo, con un minuto de descanso entre cada una.", "Estas no cuentan para el promedio. Sirven para ver qué brazo usar.")
        val g6Mareo = "Si te mareás, sentate o acostate enseguida"
        val g6Antebrazo = "Antebrazo apoyado, sin dejarlo colgando"
        val g6Alt = "Tres dibujos. Acostado cinco minutos con una toma, después parado con el antebrazo apoyado y tomas al minuto uno y al minuto tres. Si te mareás, sentate o acostate enseguida."
        val listoSerie = "Listo, terminaste las 3 tomas. Gracias."
        val listoSerieCorto = "Listo, terminaste las 3 tomas"
        val marcarSintoma = "Marcar un síntoma"
        val esperaTitulo = "Quedate sentado y tranquilo. En 5 minutos volvé a medirte."
        val esperaLista = "Mientras esperás, decime si tenés alguno de estos."
        val esperaVoz = "Faltan 5 minutos para volver a medirte."
        val si = "Sí"
        val no = "No"
        val repetirPendiente = "Te quedó pendiente repetir la toma. Hacela sentado y tranquilo cuando puedas."
        val guardiaPresion = listOf("Con estos valores tiene que verte un médico hoy. Andá a una guardia.", "No tomes nada por tu cuenta para bajarla. Si ya tenés un remedio para la presión indicado, tomalo como siempre, sin doblarlo.", "Si aparece dolor de pecho, falta de aire, debilidad de un lado del cuerpo o te cuesta hablar, no vayas manejando y llamá a emergencias.")
        val guardiaSintomas = listOf("Con lo que marcaste tiene que verte un médico ahora. Andá a una guardia.", "No vayas manejando. Si es dolor de pecho, falta de aire, debilidad de un lado del cuerpo o te cuesta hablar, llamá a emergencias.")
        val sentateAgua = "Sentate o acostate un rato y tomá agua. Escribime cuando puedas."
        val mareoOrtostatica = "Quedate sentado o acostado hasta que se te pase."
        val latidoIrregular = "Gracias, seguí como siempre."
        val revisarNumero = "Revisá el número que anotaste. Si podés, sacale una foto a la pantalla del aparato."
        val revisarNumeroSinFoto = "Revisá el número que anotaste."
        val noCuenta = "Esta no cuenta. Hacé otra otro día, antes del café y del preentreno."
        val recordatorioManana = "Buen día, te toca la presión antes de desayunar."

        fun como(brazo: String?): List<String> = listOf(
            "Sentate en una silla con respaldo, al lado de una mesa, en un lugar tranquilo. Espalda apoyada, pies planos en el piso y piernas sin cruzar.",
            "Apoyá el brazo ${if (brazo == "der") "derecho" else "izquierdo"} en la mesa, relajado y con la palma para arriba. El manguito va sobre la piel, nunca sobre la ropa. Si la manga te aprieta al subirla, sacate la remera.",
            "La mitad del manguito tiene que quedar a la altura del corazón. Si la mesa es baja, poné un almohadón abajo del brazo.",
            "El borde de abajo del manguito va 2 o 3 centímetros arriba del pliegue del codo, con la marca de la arteria del lado de adentro del brazo. Ajustalo firme, que entre justo un dedo.",
            "Quedate 5 minutos quieto, sin hablar ni mirar el celular.",
            "Hacé la toma y anotá la alta, la baja y el pulso. Si el aparato muestra el símbolo de latido irregular, marcalo.",
            "Si sale error, revisá el manguito, esperá un minuto y repetí.",
            "Listo por hoy. La próxima, otro día."
        )

        fun ortostatica(sentado: Boolean): List<String> = buildList {
            add("Hacela a la mañana, después de la toma sentado, con el mismo manguito puesto.")
            add("Hacela al lado de la cama, sin nadie apurándote.")
            if (sentado) {
                add("Sentado 5 minutos y una toma")
            } else {
                add("Acostate boca arriba 5 minutos. Dejá el brazo apoyado sobre una almohada chica, a la altura del medio del pecho.")
                add("Hacé una toma acostado.")
            }
            addAll(listOf("Parate al lado de la cama. Apoyá el antebrazo en un mueble alto o sostenelo con la otra mano, así el manguito queda a la altura del corazón. No dejes el brazo colgando.", "Cuando la app marque un minuto parado, hacé una toma.", "Cuando marque 3 minutos parado, hacé otra.", "Si te mareás, se te nubla la vista o sentís que te vas a desmayar, sentate o acostate enseguida y marcalo. No hace falta terminar."))
        }

        fun g6(sentado: Boolean): List<String> = listOf(if (sentado) "Sentado 5 minutos y una toma" else "Acostado 5 minutos y una toma", "Parado, toma al minuto 1", "Parado, toma al minuto 3")

        fun faltan(n: Int): String = if (n == 1) "Te falta 1 toma" else "Te faltan $n tomas"

        fun avanceAlt(n: Int, total: Int): String {
            val hechas = listOf("cero", "una", "dos", "tres")
            return "${if (total == 3) "Tres" else "$total"} círculos, uno por toma. Completaste ${hechas.getOrNull(n) ?: "$n"} de ${if (total == 3) "tres" else "$total"}."
        }

        /** Todo, con la forma de `textos` en los vectores. */
        val todos: ValorJson get() = ValorJson.objeto(
            "antes" to ValorJson.Lista(antes.map { ValorJson.Texto(it) }),
            "medirBrazo" to ValorJson.Lista(medirBrazo.map { ValorJson.Texto(it) }),
            "medirDeNuevo" to ValorJson.Texto(medirDeNuevo),
            "g3" to ValorJson.Lista(g3.map { ValorJson.Texto(it) }),
            "g3Alt" to ValorJson.Texto(g3Alt),
            "tramos" to ValorJson.Objeto(tramos.mapValues { ValorJson.Texto(it.value) }),
            "tramosRango" to ValorJson.Objeto(tramosRango.mapValues { ValorJson.Texto(it.value) }),
            "marca42" to ValorJson.Texto(marca42),
            "verCuales" to ValorJson.Texto(verCuales),
            "fueraDeTalle" to ValorJson.Texto(fueraDeTalle),
            "porTramo" to ValorJson.Objeto(porTramo.mapValues { ValorJson.Texto(it.value) }),
            "muneca" to ValorJson.Lista(muneca.map { ValorJson.Texto(it) }),
            "munecaNoValidada" to ValorJson.Texto(munecaNoValidada),
            "noValidado" to ValorJson.Lista(noValidado.map { ValorJson.Texto(it) }),
            "cuandoTitulo" to ValorJson.Texto(cuandoTitulo),
            "cuando" to ValorJson.Lista(cuando.map { ValorJson.Texto(it) }),
            "comoTitulo" to ValorJson.Texto(comoTitulo),
            "g1" to ValorJson.Lista(g1.map { ValorJson.Texto(it) }),
            "g1Alt" to ValorJson.Texto(g1Alt),
            "g2" to ValorJson.Lista(g2.map { f -> ValorJson.Lista(f.map { ValorJson.Texto(it) }) }),
            "g2Alt" to ValorJson.Texto(g2Alt),
            "g4" to ValorJson.Lista(g4.map { ValorJson.Texto(it) }),
            "g4Alt" to ValorJson.Texto(g4Alt),
            "queEvitar" to ValorJson.Texto(queEvitar),
            "g5" to ValorJson.Lista(g5.map { f -> ValorJson.Lista(f.map { ValorJson.Texto(it) }) }),
            "g5Alt" to ValorJson.Texto(g5Alt),
            "bien" to ValorJson.Texto(bien),
            "asiNo" to ValorJson.Texto(asiNo),
            "bajoEfecto" to ValorJson.Lista(bajoEfecto.map { ValorJson.Texto(it) }),
            "brazos" to ValorJson.Lista(brazos.map { ValorJson.Texto(it) }),
            "g6Mareo" to ValorJson.Texto(g6Mareo),
            "g6Antebrazo" to ValorJson.Texto(g6Antebrazo),
            "g6Alt" to ValorJson.Texto(g6Alt),
            "listoSerie" to ValorJson.Texto(listoSerie),
            "listoSerieCorto" to ValorJson.Texto(listoSerieCorto),
            "marcarSintoma" to ValorJson.Texto(marcarSintoma),
            "esperaTitulo" to ValorJson.Texto(esperaTitulo),
            "esperaLista" to ValorJson.Texto(esperaLista),
            "esperaVoz" to ValorJson.Texto(esperaVoz),
            "si" to ValorJson.Texto(si),
            "no" to ValorJson.Texto(no),
            "repetirPendiente" to ValorJson.Texto(repetirPendiente),
            "guardiaPresion" to ValorJson.Lista(guardiaPresion.map { ValorJson.Texto(it) }),
            "guardiaSintomas" to ValorJson.Lista(guardiaSintomas.map { ValorJson.Texto(it) }),
            "sentateAgua" to ValorJson.Texto(sentateAgua),
            "mareoOrtostatica" to ValorJson.Texto(mareoOrtostatica),
            "latidoIrregular" to ValorJson.Texto(latidoIrregular),
            "revisarNumero" to ValorJson.Texto(revisarNumero),
            "revisarNumeroSinFoto" to ValorJson.Texto(revisarNumeroSinFoto),
            "noCuenta" to ValorJson.Texto(noCuenta),
            "recordatorioManana" to ValorJson.Texto(recordatorioManana),
            "comoIzq" to ValorJson.Lista(como("izq").map { ValorJson.Texto(it) }),
            "comoDer" to ValorJson.Lista(como("der").map { ValorJson.Texto(it) }),
            "ortostaticaAcostado" to ValorJson.Lista(ortostatica(sentado = false).map { ValorJson.Texto(it) }),
            "ortostaticaSentado" to ValorJson.Lista(ortostatica(sentado = true).map { ValorJson.Texto(it) }),
            "g6Acostado" to ValorJson.Lista(g6(sentado = false).map { ValorJson.Texto(it) }),
            "g6Sentado" to ValorJson.Lista(g6(sentado = true).map { ValorJson.Texto(it) }),
            "faltan1" to ValorJson.Texto(faltan(1)),
            "faltan2" to ValorJson.Texto(faltan(2)),
            "avanceAlt2" to ValorJson.Texto(avanceAlt(2, 3)),
        )
    }

    /** Textos propios de la app (botones, títulos y preguntas). */
    object N {
        val titulo = "Presión"
        val entrada = "Presión arterial"
        val antesTitulo = "Antes de la primera serie"
        val medirBrazoTitulo = "Cómo medirte el brazo"
        val medida = "Medida del brazo, en centímetros"
        val tipoAparato = "¿Qué tensiómetro tenés?"
        val tipos = mapOf("brazo" to "De brazo", "muneca" to "De muñeca", "reloj_anillo_otro" to "Reloj, anillo u otro", "ninguno" to "Todavía no tengo")
        val marca = "Marca"
        val modelo = "Modelo"
        val codigo = "Código de la etiqueta"
        val codigoAyuda = "Copialo tal cual, con las letras del final"
        val rango = "Rango impreso en el manguito, en centímetros"
        val desde = "Desde"
        val hasta = "Hasta"
        val guardar = "Guardar"
        val seguir = "Seguir"
        val empezar = "Empezar"
        val cerrar = "Cerrar"
        val volver = "Volver"
        val tomaDeHoy = "Hacer la toma de hoy"
        val tomaSuelta = "Anotar una toma"
        val repetir = "Repetir la toma"
        val previas = "Antes de medirte"
        val previa = mapOf("cafeina" to "¿Tomaste café, mate, energizante o preentreno en la última media hora?", "fumo" to "¿Fumaste o vapeaste en la última media hora?", "comida" to "¿Comiste en la última media hora?", "ejercicio" to "¿Entrenaste en la última hora?")
        val esperarMejor = "Mejor esperá un rato y medite después."
        val esperar = "Esperar"
        val medirIgual = "Medirme igual"
        val reposo = "Quedate 5 minutos quieto, sin hablar ni mirar el celular"
        val saltear = "Ya esperé"
        val alta = "Alta"
        val baja = "Baja"
        val pulso = "Pulso"
        val irregular = "El aparato mostró el símbolo de latido irregular"
        val anotar = "Anotar la toma"
        val confirmar = "Sí, es ese número"
        val corregir = "Corregir"
        val horaDosis = "¿A qué hora tomaste el estimulante?"
        val entrenoEntre = "¿Entrenaste entre la dosis y la toma?"
        val alarma = "Avisame si tenés alguno de estos"
        val otros = "Otros"
        val nota = "Si querés, contame algo más"
        val enviar = "Enviar"
        val sintomaRecibido = "Anotado."
        val tusTomas = "Tus tomas"
        val sinTomas = "Todavía no anotaste ninguna toma"
        val hoyListo = "La de hoy ya está. La próxima, otro día."
        val relojNoSirve = "El reloj y el anillo no sirven para esto. Hace falta un tensiómetro de brazo."
        val aparato = "Tu tensiómetro"
        val cambiarAparato = "Cambiar"
        val brazo = "Brazo"
        val cm = "cm"
        val brazoIzq = "Brazo izquierdo"
        val brazoDer = "Brazo derecho"
        val noGuardo = "No se pudo guardar. Probá de nuevo."
        val sinSenal = "Sin señal. Queda guardada y se manda sola."
        val tarjeta = "Tu presión"
        val tarjetaPreparar = "Primero medí tu brazo y anotá tu tensiómetro"
        val tarjetaSerie = "Son 3 tomas, una por día"
        val meMaree = "Me mareé"
        val sinLista = "Todavía estamos armando la lista para tu país."

        fun minutoParado(n: Int): String = if (n == 1) "Toma al minuto 1" else "Toma al minuto 3"

        fun graficoAlt(n: Int): String = "Gráfico con tus $n tomas, alta y baja, por día."

        /** Todo, con la forma de `propios` en los vectores. */
        val todos: ValorJson get() = ValorJson.objeto(
            "titulo" to ValorJson.Texto(titulo),
            "entrada" to ValorJson.Texto(entrada),
            "antesTitulo" to ValorJson.Texto(antesTitulo),
            "medirBrazoTitulo" to ValorJson.Texto(medirBrazoTitulo),
            "medida" to ValorJson.Texto(medida),
            "tipoAparato" to ValorJson.Texto(tipoAparato),
            "tipos" to ValorJson.Objeto(tipos.mapValues { ValorJson.Texto(it.value) }),
            "marca" to ValorJson.Texto(marca),
            "modelo" to ValorJson.Texto(modelo),
            "codigo" to ValorJson.Texto(codigo),
            "codigoAyuda" to ValorJson.Texto(codigoAyuda),
            "rango" to ValorJson.Texto(rango),
            "desde" to ValorJson.Texto(desde),
            "hasta" to ValorJson.Texto(hasta),
            "guardar" to ValorJson.Texto(guardar),
            "seguir" to ValorJson.Texto(seguir),
            "empezar" to ValorJson.Texto(empezar),
            "cerrar" to ValorJson.Texto(cerrar),
            "volver" to ValorJson.Texto(volver),
            "tomaDeHoy" to ValorJson.Texto(tomaDeHoy),
            "tomaSuelta" to ValorJson.Texto(tomaSuelta),
            "repetir" to ValorJson.Texto(repetir),
            "previas" to ValorJson.Texto(previas),
            "previa" to ValorJson.Objeto(previa.mapValues { ValorJson.Texto(it.value) }),
            "esperarMejor" to ValorJson.Texto(esperarMejor),
            "esperar" to ValorJson.Texto(esperar),
            "medirIgual" to ValorJson.Texto(medirIgual),
            "reposo" to ValorJson.Texto(reposo),
            "saltear" to ValorJson.Texto(saltear),
            "alta" to ValorJson.Texto(alta),
            "baja" to ValorJson.Texto(baja),
            "pulso" to ValorJson.Texto(pulso),
            "irregular" to ValorJson.Texto(irregular),
            "anotar" to ValorJson.Texto(anotar),
            "confirmar" to ValorJson.Texto(confirmar),
            "corregir" to ValorJson.Texto(corregir),
            "horaDosis" to ValorJson.Texto(horaDosis),
            "entrenoEntre" to ValorJson.Texto(entrenoEntre),
            "alarma" to ValorJson.Texto(alarma),
            "otros" to ValorJson.Texto(otros),
            "nota" to ValorJson.Texto(nota),
            "enviar" to ValorJson.Texto(enviar),
            "sintomaRecibido" to ValorJson.Texto(sintomaRecibido),
            "tusTomas" to ValorJson.Texto(tusTomas),
            "sinTomas" to ValorJson.Texto(sinTomas),
            "hoyListo" to ValorJson.Texto(hoyListo),
            "relojNoSirve" to ValorJson.Texto(relojNoSirve),
            "aparato" to ValorJson.Texto(aparato),
            "cambiarAparato" to ValorJson.Texto(cambiarAparato),
            "brazo" to ValorJson.Texto(brazo),
            "cm" to ValorJson.Texto(cm),
            "brazoIzq" to ValorJson.Texto(brazoIzq),
            "brazoDer" to ValorJson.Texto(brazoDer),
            "noGuardo" to ValorJson.Texto(noGuardo),
            "sinSenal" to ValorJson.Texto(sinSenal),
            "tarjeta" to ValorJson.Texto(tarjeta),
            "tarjetaPreparar" to ValorJson.Texto(tarjetaPreparar),
            "tarjetaSerie" to ValorJson.Texto(tarjetaSerie),
            "meMaree" to ValorJson.Texto(meMaree),
            "sinLista" to ValorJson.Texto(sinLista),
            "minutoParado1" to ValorJson.Texto(minutoParado(1)),
            "minutoParado3" to ValorJson.Texto(minutoParado(3)),
            "graficoAlt3" to ValorJson.Texto(graficoAlt(3)),
        )
    }
}
