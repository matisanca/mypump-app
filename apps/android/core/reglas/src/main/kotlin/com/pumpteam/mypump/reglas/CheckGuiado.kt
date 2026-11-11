package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.ValorJson

/**
 * El check guiado (2.3.0): el check de la semana, un paso por pantalla. Guarda lo mismo que el check de siempre (las
 * cuatro escalas y la nota por `checkin`, el peso por `peso`, las fotos por su cola) y suma una sola cosa: lo que el
 * alumno marca en «¿Notaste algo de esto?» (`check_guiado`). Gemelo de `CheckGuiado.swift`; las mismas reglas están en la
 * web, y los casos compartidos en `apps/shared/vectores/check_guiado.json`.
 */
object CheckGuiado {
    enum class Paso(val clave: String) {
        PESO("peso"), ESCALAS("escalas"), FOTOS("fotos"), SENALES("senales"), NOTA("nota"), RESUMEN("resumen");

        companion object {
            fun desde(clave: String?): Paso? = entries.firstOrNull { it.clave == clave }
        }
    }

    /** Qué lista de «¿Notaste algo?» le toca: la de ciclo solo si el servidor dice explícitamente que está en ciclo. */
    enum class Catalogo(val clave: String) {
        GENERAL("general"), CICLO("ciclo");

        companion object {
            fun desde(clave: String?): Catalogo? = entries.firstOrNull { it.clave == clave }
            fun de(enCiclo: Boolean): Catalogo = if (enCiclo) CICLO else GENERAL
        }
    }

    data class Opcion(val clave: String, val etiqueta: String)

    /** «Nada de esto»: se guarda para distinguir «no pasó nada» de «no contestó». No convive con otra. */
    const val NINGUNO = "ninguno"

    /** Los efectos digestivos de la lista de efectos: se muestran solo a quien usa un GLP-1 (lo dice el servidor). */
    val DIGESTIVAS = listOf("nauseas", "vomitos", "estrenimiento", "diarrea", "acidez")

    /**
     * La lista que se muestra. [glp1] = false saca las digestivas de la lista de efectos; `normalizar` y `textoSenales`
     * usan la lista entera (lo ya marcado vale aunque el perfil haya cambiado).
     */
    fun opciones(c: Catalogo, glp1: Boolean): List<Opcion> =
        if (c == Catalogo.CICLO && !glp1) opciones(c).filter { it.clave !in DIGESTIVAS } else opciones(c)

    /** La lista entera de cada catálogo. */
    fun opciones(c: Catalogo): List<Opcion> = when (c) {
        Catalogo.GENERAL -> listOf(
            Opcion("dolor", "Dolor o molestia al entrenar"),
            Opcion("digestion", "Digestión pesada o malestar"),
            Opcion("animo", "Ánimo bajo"),
            Opcion("enfermo", "Estuve enfermo"),
            Opcion(NINGUNO, "Nada de esto"),
        )
        Catalogo.CICLO -> listOf(
            Opcion("acne", "Acné o piel grasa"),
            Opcion("retencion", "Retención de líquido o hinchazón"),
            Opcion("pecho", "Sensibilidad en el pecho"),
            Opcion("cabeza", "Dolor de cabeza o presión alta"),
            Opcion("animo", "Irritabilidad o cambios de ánimo"),
            Opcion("libido", "Cambios en el deseo sexual"),
            Opcion("sueno", "Insomnio o sudor de noche"),
            Opcion("aplicacion", "Dolor en la zona de aplicación"),
            Opcion("nauseas", "Náuseas"),
            Opcion("vomitos", "Vómitos"),
            Opcion("estrenimiento", "Estreñimiento"),
            Opcion("diarrea", "Diarrea"),
            Opcion("acidez", "Acidez o reflujo"),
            Opcion(NINGUNO, "Nada de esto"),
        )
    }

    fun titulo(p: Paso, catalogo: Catalogo = Catalogo.GENERAL): String = when (p) {
        Paso.PESO -> "¿Cuánto pesaste hoy?"
        Paso.ESCALAS -> "¿Cómo venís esta semana?"
        Paso.FOTOS -> "Tus fotos de la semana"
        Paso.SENALES -> if (catalogo == Catalogo.CICLO) "¿Notaste algo de esto?" else "¿Algo de esto esta semana?"
        Paso.NOTA -> "¿Algo que quieras contarme?"
        Paso.RESUMEN -> "Así va tu check"
    }

    fun apoyo(p: Paso, catalogo: Catalogo = Catalogo.GENERAL): String = when (p) {
        Paso.PESO -> "En ayunas, al despertar."
        Paso.ESCALAS -> "Del 1 al 5. Mati lo ve antes de tu devolución."
        Paso.FOTOS -> "Frente, perfil y espalda. Mismo lugar y misma luz que siempre. Las ve solo Mati."
        Paso.SENALES ->
            if (catalogo == Catalogo.CICLO) "Marcá lo que haya aparecido esta semana. Mati lo mira antes de tu devolución."
            else "Marcá lo que te haya pasado. Si no hubo nada, mejor."
        Paso.NOTA -> "Es opcional. Lo lee Mati."
        Paso.RESUMEN -> "Tocá una fila si querés cambiar algo."
    }

    /** La salida discreta de cada paso (lo que deja seguir sin contestar). null = no se puede saltear. */
    fun omitir(p: Paso): String? = when (p) {
        Paso.PESO -> "Hoy no me pesé"
        Paso.FOTOS -> "Las subo después"
        else -> null
    }

    /**
     * Los pasos de esta vez. Las fotos entran solo si al abrir faltaba alguna de las tres de la semana (y no se van al
     * subir la última: la lista se arma una vez, al abrir).
     */
    fun pasos(faltanFotos: Boolean): List<Paso> = Paso.entries.filter { it != Paso.FOTOS || faltanFotos }

    /** Tocar una opción: se marca o se desmarca. «Nada de esto» borra las demás, y cualquiera de las demás la borra. */
    fun alternar(senales: List<String>, clave: String): List<String> {
        if (clave in senales) return senales.filter { it != clave }
        if (clave == NINGUNO) return listOf(NINGUNO)
        return senales.filter { it != NINGUNO } + clave
    }

    /** Lo que se manda: solo claves del catálogo, sin repetir, en el orden del catálogo y sin «ninguno» mezclado. */
    fun normalizar(senales: List<String>, c: Catalogo): List<String> {
        val validas = opciones(c).map { it.clave }.filter { it in senales }
        return if (validas.size > 1) validas.filter { it != NINGUNO } else validas
    }

    // ── Intensidad (solo en la lista de efectos) ──

    /** Cuánto molesta cada efecto marcado. La lista general no lleva. */
    val INTENSIDADES = listOf(Opcion("leve", "Leve"), Opcion("moderado", "Moderado"), Opcion("fuerte", "Fuerte"))

    /** El rótulo de los tres botones. */
    const val ROTULO_INTENSIDAD = "¿Cuánto te molesta?"

    /** Lo que se dice si hay un efecto marcado sin intensidad. */
    const val AVISO_INTENSIDAD = "Elegí cuánto te molesta"

    /**
     * Las intensidades que valen: solo en la lista de efectos, solo de lo marcado (sin «ninguno») y con un valor conocido,
     * en el orden del catálogo. Desmarcar un efecto o tocar «Nada de esto» borra la suya.
     */
    fun normalizarIntensidades(senales: List<String>, intensidades: Map<String, String>, c: Catalogo): Map<String, String> {
        if (c != Catalogo.CICLO) return emptyMap()
        val validas = INTENSIDADES.map { it.clave }
        val queda = LinkedHashMap<String, String>()
        for (clave in normalizar(senales, c)) {
            if (clave == NINGUNO) continue
            intensidades[clave]?.takeIf { it in validas }?.let { queda[clave] = it }
        }
        return queda
    }

    /** ¿Hay algún efecto marcado sin su intensidad? (Solo en la lista de efectos.) */
    fun faltaIntensidad(b: Borrador): Boolean {
        if (b.catalogo != Catalogo.CICLO) return false
        val marcadas = normalizar(b.senales, b.catalogo).filter { it != NINGUNO }
        val puestas = normalizarIntensidades(b.senales, b.intensidades, b.catalogo)
        return marcadas.any { it !in puestas }
    }

    /** El borrador de la semana: lo que el alumno lleva contestado. Vive en el teléfono hasta que manda el check. */
    data class Borrador(
        /** El lunes de la semana del borrador: el de otra semana no sirve. */
        val semana: String,
        val paso: Paso = Paso.PESO,
        val peso: String = "",
        val valores: Map<String, Int> = emptyMap(),
        val catalogo: Catalogo = Catalogo.GENERAL,
        val senales: List<String> = emptyList(),
        val nota: String = "",
        /** Cuánto molesta cada efecto marcado (clave del efecto → `leve`, `moderado` o `fuerte`). */
        val intensidades: Map<String, String> = emptyMap(),
    ) {
        /** ¿Contestó algo? Un borrador sin nada no cuenta como «a medias». */
        val empezado: Boolean
            get() = peso.sinEspacios().isNotEmpty() || valores.values.any { it > 0 } || senales.isNotEmpty() || nota.isNotBlank()

        /** Como lo guarda el teléfono (las mismas claves que el `Codable` de iOS y que los vectores). */
        fun aValor(): ValorJson = ValorJson.objeto(
            "semana" to ValorJson.Texto(semana),
            "paso" to ValorJson.Texto(paso.clave),
            "peso" to ValorJson.Texto(peso),
            "valores" to ValorJson.Objeto(valores.mapValues { ValorJson.Numero(it.value.toDouble()) }),
            "catalogo" to ValorJson.Texto(catalogo.clave),
            "senales" to ValorJson.Lista(senales.map { ValorJson.Texto(it) }),
            "nota" to ValorJson.Texto(nota),
            "intensidades" to ValorJson.Objeto(intensidades.mapValues { ValorJson.Texto(it.value) }),
        )

        companion object {
            /** null si no es un borrador entero (un archivo roto o de otra forma no se retoma). */
            fun desde(j: ValorJson?): Borrador? {
                val o = j as? ValorJson.Objeto ?: return null
                val valores = LinkedHashMap<String, Int>()
                for ((k, v) in (o["valores"] as? ValorJson.Objeto ?: return null).campos) {
                    val n = v.comoNumero ?: return null
                    if (n != Math.rint(n)) return null
                    valores[k] = n.toInt()
                }
                // Un borrador de antes de las intensidades no trae el campo: se lee como vacío.
                val intensidades = LinkedHashMap<String, String>()
                when (val i = o["intensidades"]) {
                    null, ValorJson.Nulo -> Unit
                    is ValorJson.Objeto -> for ((k, v) in i.campos) intensidades[k] = v.comoTexto ?: return null
                    else -> return null
                }
                return Borrador(
                    semana = o["semana"]?.comoTexto ?: return null,
                    paso = Paso.desde(o["paso"]?.comoTexto) ?: return null,
                    peso = o["peso"]?.comoTexto ?: return null,
                    valores = valores,
                    catalogo = Catalogo.desde(o["catalogo"]?.comoTexto) ?: return null,
                    senales = (o["senales"] as? ValorJson.Lista ?: return null).elementos.map { it.comoTexto ?: return null },
                    nota = o["nota"]?.comoTexto ?: return null,
                    intensidades = intensidades,
                )
            }
        }
    }

    /** Lo ya enviado del check de siempre (las cuatro escalas y la nota). */
    data class Enviado(val valores: Map<String, Int>, val nota: String)

    /**
     * El borrador con el que se abre: el guardado si es de esta semana; si no, uno nuevo con lo que ya está enviado. Si el
     * perfil cambió (otro catálogo), lo marcado con la lista anterior no vale, ni sus intensidades.
     */
    fun abrir(
        guardado: Borrador?,
        semana: String,
        catalogo: Catalogo,
        enviado: Enviado?,
        senalesEnviadas: List<String>?,
        catalogoEnviado: Catalogo?,
        intensidadesEnviadas: Map<String, String>? = null,
    ): Borrador {
        if (guardado != null && guardado.semana == semana) {
            return if (guardado.catalogo != catalogo) guardado.copy(catalogo = catalogo, senales = emptyList(), intensidades = emptyMap()) else guardado
        }
        var b = Borrador(semana = semana, catalogo = catalogo)
        if (enviado != null) b = b.copy(valores = enviado.valores, nota = enviado.nota, paso = Paso.RESUMEN)
        if (senalesEnviadas != null && catalogoEnviado == catalogo) {
            val senales = normalizar(senalesEnviadas, catalogo)
            b = b.copy(senales = senales, intensidades = normalizarIntensidades(senales, intensidadesEnviadas ?: emptyMap(), catalogo))
        }
        return b
    }

    /** En qué paso se abre: donde lo dejó, si ese paso sigue estando; si no, el primero. */
    fun retomar(b: Borrador, pasos: List<Paso>): Paso = if (b.paso in pasos) b.paso else (pasos.firstOrNull() ?: Paso.PESO)

    /**
     * ¿Se puede seguir desde este paso? El peso vacío no sigue (para eso está «Hoy no me pesé»); con algo escrito sigue, y
     * si no es un peso válido lo dice la pantalla. Las fotos, con las tres.
     */
    fun puedeSeguir(p: Paso, b: Borrador, fotosHechas: Int = 0): Boolean = when (p) {
        Paso.PESO -> b.peso.sinEspacios().isNotEmpty()
        Paso.ESCALAS -> CheckinSemanal.faltan(b.valores) == null
        Paso.FOTOS -> fotosHechas >= 3
        Paso.SENALES -> normalizar(b.senales, b.catalogo).isNotEmpty()
        Paso.NOTA, Paso.RESUMEN -> true
    }

    /** Lo que falta para poder mandar (el resumen lo dice en vez de dejar el botón gris sin explicación). */
    fun faltaParaEnviar(b: Borrador): String? {
        CheckinSemanal.faltan(b.valores)?.let { return it }
        if (normalizar(b.senales, b.catalogo).isEmpty()) return "Falta: ${titulo(Paso.SENALES, b.catalogo)}"
        if (faltaIntensidad(b)) return AVISO_INTENSIDAD
        return null
    }

    /** El primer paso al que hay que volver para completar lo que falta. */
    fun pasoQueFalta(b: Borrador): Paso? {
        if (CheckinSemanal.faltan(b.valores) != null) return Paso.ESCALAS
        if (normalizar(b.senales, b.catalogo).isEmpty() || faltaIntensidad(b)) return Paso.SENALES
        return null
    }

    /** «Acné o piel grasa · Leve, Náuseas · Moderado» para la fila del resumen (sin intensidad, solo el efecto). */
    fun textoSenales(senales: List<String>, c: Catalogo, intensidades: Map<String, String> = emptyMap()): String {
        val n = normalizar(senales, c)
        val puestas = normalizarIntensidades(senales, intensidades, c)
        return opciones(c).filter { it.clave in n }.joinToString(", ") { o ->
            val cuanto = INTENSIDADES.firstOrNull { it.clave == puestas[o.clave] }
            if (cuanto != null) "${o.etiqueta} · ${cuanto.etiqueta}" else o.etiqueta
        }
    }

    // ── La tarjeta de Revisión ──

    enum class Estado(val clave: String) {
        SIN_EMPEZAR("sinEmpezar"), A_MEDIAS("aMedias"), ENVIADO("enviado"), ENVIADO_SIN_FOTOS("enviadoSinFotos")
    }

    fun estado(enviado: Boolean, borrador: Borrador?, semana: String, faltanFotos: Boolean): Estado {
        // Un borrador de esta semana posterior al envío («Cambiar algo» sin terminar) no lo vuelve a «a medias».
        if (enviado) return if (faltanFotos) Estado.ENVIADO_SIN_FOTOS else Estado.ENVIADO
        if (borrador != null && borrador.semana == semana && borrador.empezado) return Estado.A_MEDIAS
        return Estado.SIN_EMPEZAR
    }

    fun textoTarjeta(e: Estado): String = when (e) {
        Estado.SIN_EMPEZAR -> "Un minuto: tu peso, cómo venís y tus fotos. Mati lo ve antes de tu devolución."
        Estado.A_MEDIAS -> "Lo dejaste por la mitad. Seguís donde quedaste."
        Estado.ENVIADO -> "Enviado. Mati lo ve antes de tu devolución."
        Estado.ENVIADO_SIN_FOTOS -> "Enviado. Te faltan las fotos de la semana."
    }

    fun botonTarjeta(e: Estado): String = when (e) {
        Estado.SIN_EMPEZAR -> "Empezar"
        Estado.A_MEDIAS -> "Seguir"
        Estado.ENVIADO -> "Cambiar algo"
        Estado.ENVIADO_SIN_FOTOS -> "Subir fotos"
    }

    /** Lo que se le dice al alumno cuando el peso que escribió no se puede guardar (`PesoCorporal.avisoRango` de iOS). */
    const val AVISO_RANGO_PESO = "Revisá el peso: tiene que estar entre 30 y 300 kg."

    /** `trimmingCharacters(in: .whitespaces)` de Swift: espacios y tabulaciones, no los saltos de línea. */
    internal fun String.sinEspacios(): String = trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
}
