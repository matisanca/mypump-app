package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.DiaCalendario
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.Presion
import java.io.IOException
import java.util.UUID
import kotlinx.serialization.json.Json

/**
 * El servidor de presión de mentira: sigue `presion/CONTRATO_APP.md` en memoria. Lo usan las pruebas JVM y las de interfaz (este
 * directorio se suma a sus fuentes: nunca va en la app). Nunca toca la red. Todos los datos son inventados. Gemelo de
 * DoblePresion.swift.
 */
class DoblePresion : Transporte {
    @Volatile var palanca = true
    @Volatile var sinFuncion = false
    @Volatile var habilitado = true
    @Volatile var sinRed = false
    @Volatile var tokenCaido = false

    /** Estados forzados para las próximas escrituras de sesión o de síntoma, en orden. 0 = sin red en esa. */
    val proximas = ArrayDeque<Int>()

    /** La próxima escritura contesta `{"ok": false, "error": …}`. */
    @Volatile var proximoError: String? = null
    val llamadas = java.util.concurrent.CopyOnWriteArrayList<String>()

    var hoy: String = FechaLocal.hoy()
    var fotos = false
    var aparato: MutableMap<String, ValorJson>? = null
    var circunferencia: Double? = null
    var serie: MutableMap<String, ValorJson>? = null

    /** Las sesiones guardadas, la más nueva primero, con la forma de `p_sesion` más `fecha`. */
    val sesiones = mutableListOf<Map<String, ValorJson>>()
    val sintomas = mutableListOf<Map<String, ValorJson>>()
    var tensiometros: ValorJson = ValorJson.Nulo

    /** Cada `p_sesion` recibido, tal cual. */
    val recibidas = mutableListOf<ValorJson>()

    val llamadasPresion: List<String> get() = llamadas.filter { "presion" in it }
    fun cuantas(nombre: String): Int = llamadas.count { it == nombre }

    override suspend fun enviar(pedido: Pedido): Respuesta = synchronized(this) {
        val nombre = pedido.ruta.substringAfterLast('/')
        llamadas += nombre
        if (sinRed) throw IOException("sin red (doble)")
        val (status, cuerpo) = atender(nombre, pedido)
        Respuesta(status, cuerpo.toByteArray())
    }

    private fun cuerpo(p: Pedido): ValorJson = p.cuerpo?.let { ValorJson.desde(Json.parseToJsonElement(it.toString(Charsets.UTF_8))) } ?: ValorJson.Nulo
    private fun n(i: Int): ValorJson = ValorJson.Numero(i.toDouble())
    private fun t(s: String): ValorJson = ValorJson.Texto(s)
    private fun b(x: Boolean): ValorJson = ValorJson.Booleano(x)
    private fun conEstado(): String = ValorJson.objeto("ok" to b(true), "estado" to estado()).serializar()

    private fun atender(nombre: String, p: Pedido): Pair<Int, String> = when {
        nombre == "mypump_get_app_config" -> 200 to """{"presion_app":$palanca}"""
        nombre.startsWith("mypump_presion") && sinFuncion -> 404 to """{"code":"PGRST202","message":"no existe"}"""
        nombre.startsWith("mypump_presion") && tokenCaido -> 200 to "null"
        nombre == "mypump_presion_get" -> 200 to estado().serializar()
        nombre == "mypump_presion_aparato" -> {
            val a = cuerpo(p)["p_aparato"]
            val tipo = a?.get("tipo")?.comoTexto
            if (tipo !in listOf("brazo", "muneca", "reloj_anillo_otro")) {
                200 to """{"ok":false,"error":"datos"}"""
            } else {
                aparato = mutableMapOf(
                    "id" to t(UUID.randomUUID().toString()), "tipo" to t(tipo!!), "marca" to (a["marca"] ?: ValorJson.Nulo), "modelo" to (a["modelo"] ?: ValorJson.Nulo),
                    "modelo_codigo" to (a["modelo_codigo"] ?: ValorJson.Nulo), "manguito_min_cm" to (a["manguito_min_cm"] ?: ValorJson.Nulo),
                    "manguito_max_cm" to (a["manguito_max_cm"] ?: ValorJson.Nulo), "manguito_validado_min_cm" to ValorJson.Nulo, "manguito_validado_max_cm" to ValorJson.Nulo,
                    "validado" to t("sin_revisar"),
                )
                200 to conEstado()
            }
        }
        nombre == "mypump_presion_medida" -> {
            val cm = cuerpo(p)["p_cm"]?.comoNumero
            if (cm == null || cm < 20 || cm > 70) {
                200 to """{"ok":false,"error":"datos"}"""
            } else {
                circunferencia = cm
                serie?.put("medida_pedida", b(false))
                200 to conEstado()
            }
        }
        nombre == "mypump_presion_sesion" -> forzada() ?: guardarSesion(cuerpo(p)["p_sesion"] ?: ValorJson.Nulo)
        nombre == "mypump_presion_sintoma" -> forzada() ?: run {
            val s = cuerpo(p)["p_sintoma"] as? ValorJson.Objeto
            val id = s?.get("id")?.comoTexto
            if (s == null || id.isNullOrEmpty()) {
                200 to """{"ok":false,"error":"datos"}"""
            } else {
                if (sintomas.none { it["id"]?.comoTexto == id }) sintomas += s.campos
                200 to """{"ok":true}"""
            }
        }
        else -> 200 to "[]"
    }

    private fun forzada(): Pair<Int, String>? {
        proximas.removeFirstOrNull()?.let { s ->
            if (s == 0) throw IOException("corte (doble)")
            if (s != 200) return s to """{"message":"forzado"}"""
        }
        proximoError?.let { e ->
            proximoError = null
            return 200 to """{"ok":false,"error":"$e"}"""
        }
        return null
    }

    /** Idempotente por `id`; las tomas ya guardadas (por `orden`) no se pisan. */
    private fun guardarSesion(s: ValorJson): Pair<Int, String> {
        recibidas += s
        val id = s["id"]?.comoTexto
        val tomas = (s["tomas"] as? ValorJson.Lista)?.elementos
        if (s !is ValorJson.Objeto || id.isNullOrEmpty() || tomas.isNullOrEmpty()) return 200 to """{"ok":false,"error":"datos"}"""
        val a = aparato
        if (a == null || a["tipo"]?.comoTexto == "reloj_anillo_otro") return 200 to """{"ok":false,"error":"aparato"}"""
        if (tomas.any { Presion.validarToma(it["sis"]?.comoNumero, it["dia"]?.comoNumero, it["pulso"]?.comoNumero) == Presion.Validez.IMPOSIBLE }) {
            return 200 to """{"ok":false,"error":"imposible"}"""
        }
        s["serie_id"]?.comoTexto?.let { sid -> if (sid != serie?.get("id")?.comoTexto) return 200 to """{"ok":false,"error":"serie"}""" }
        val nueva = s.campos.toMutableMap()
        val i = sesiones.indexOfFirst { it["id"]?.comoTexto == id }
        if (i >= 0) {
            val juntas = ((sesiones[i]["tomas"] as? ValorJson.Lista)?.elementos ?: emptyList()).toMutableList()
            for (x in tomas) if (juntas.none { it["orden"] == x["orden"] }) juntas += x
            nueva["tomas"] = ValorJson.Lista(juntas)
            nueva["fecha"] = sesiones[i]["fecha"] ?: t(hoy)
            sesiones[i] = nueva
        } else {
            nueva["fecha"] = t(hoy)
            sesiones.add(0, nueva)
        }
        recalcular()
        return 200 to conEstado()
    }

    private fun deLaSerie(): List<Presion.Sesion> {
        val sid = serie?.get("id")?.comoTexto ?: return emptyList()
        return sesiones.filter { it["serie_id"]?.comoTexto == sid }.map { Presion.Sesion.desde(ValorJson.Objeto(it)) }
    }

    /** El avance de la serie, con la misma regla que el teléfono. */
    private fun recalcular() {
        val s = serie ?: return
        val r = Presion.resumenSerie(
            Presion.EntradaSerie(s["tipo"]?.comoTexto, s["tomas_objetivo"]?.comoNumero?.toInt(), s["fecha_inicio"]?.comoTexto, deLaSerie()),
        )
        s["dias"] = ValorJson.Lista(r.dias.map { t(it) })
        s["faltan"] = n(r.faltan)
        s["estado"] = t(if (r.dias.isEmpty()) "pendiente" else "en_curso")
        // Hechas en una sesión de la serie, ya no faltan.
        if (sesiones.any { it["tipo"]?.comoTexto == "ortostatica" }) s["ortostatica"] = ValorJson.Nulo
        if (sesiones.any { it["tipo"]?.comoTexto == "comparacion_brazos" }) s["comparar_brazos"] = b(false)
    }

    private fun estado(): ValorJson {
        if (!habilitado) return ValorJson.objeto("habilitado" to b(false))
        var pendiente: ValorJson = ValorJson.Nulo
        for (s in sesiones) {
            if (s["fecha"]?.comoTexto != hoy) continue
            val ev = Presion.evaluarSesion(Presion.Sesion.desde(ValorJson.Objeto(s)))
            if (ev.paso == Presion.Paso.REPETIR || ev.paso == Presion.Paso.REPETIR_CON_LISTA) {
                pendiente = ValorJson.objeto(
                    "sesion_id" to (s["id"] ?: ValorJson.Nulo), "nivel" to t(if (ev.paso == Presion.Paso.REPETIR_CON_LISTA) "urgencia" else "alta"),
                    "desde" to (s["inicio"] ?: ValorJson.Nulo),
                )
                break
            }
        }
        val lista = sesiones.take(30).map { s ->
            val ev = Presion.evaluarSesion(Presion.Sesion.desde(ValorJson.Objeto(s)))
            val tomas = ((s["tomas"] as? ValorJson.Lista)?.elementos ?: emptyList()).map { x ->
                ValorJson.objeto(
                    "orden" to (x["orden"] ?: ValorJson.Nulo), "posicion" to (x["posicion"] ?: ValorJson.Nulo), "sis" to (x["sis"] ?: ValorJson.Nulo),
                    "dia" to (x["dia"] ?: ValorJson.Nulo), "pulso" to (x["pulso"] ?: ValorJson.Nulo), "latido_irregular" to (x["latido_irregular"] ?: b(false)),
                )
            }
            ValorJson.objeto(
                "id" to (s["id"] ?: ValorJson.Nulo), "serie_id" to (s["serie_id"] ?: ValorJson.Nulo), "fecha" to (s["fecha"] ?: ValorJson.Nulo),
                "tipo" to (s["tipo"] ?: ValorJson.Nulo), "cuenta" to b(ev.cuenta), "tomas" to ValorJson.Lista(tomas),
            )
        }
        return ValorJson.objeto(
            "habilitado" to b(true), "fotos" to b(fotos), "hoy" to t(hoy), "aparato" to (aparato?.let { ValorJson.Objeto(it.toMap()) } ?: ValorJson.Nulo),
            "circunferencia_brazo_cm" to (circunferencia?.let { ValorJson.Numero(it) } ?: ValorJson.Nulo),
            "serie" to (serie?.let { ValorJson.Objeto(it.toMap()) } ?: ValorJson.Nulo), "sesiones" to ValorJson.Lista(lista), "pendiente" to pendiente,
            "tensiometros" to tensiometros,
        )
    }

    // ── Datos de ejemplo (inventados, sin nombres reales) ──

    private fun ponerAparato(tipo: String = "brazo", validado: String = "si") {
        aparato = mutableMapOf(
            "id" to t("44444444-4444-4444-8444-444444444444"), "tipo" to t(tipo), "marca" to t("Marca de ejemplo"), "modelo" to t("Modelo A"),
            "modelo_codigo" to t("AB-1234-XY"), "manguito_min_cm" to n(22), "manguito_max_cm" to n(42),
            "manguito_validado_min_cm" to (if (validado == "si") n(22) else ValorJson.Nulo), "manguito_validado_max_cm" to (if (validado == "si") n(42) else ValorJson.Nulo),
            "validado" to t(validado),
        )
        circunferencia = 35.0
    }

    private fun ponerSerie(tipo: String = "estandar", inicioHace: Int = 0) {
        serie = mutableMapOf(
            "id" to t(ID_SERIE), "motivo" to t("inicio"), "tipo" to t(tipo), "estado" to t("pendiente"), "tomas_objetivo" to n(3),
            "fecha_inicio" to t(dia(inicioHace)), "fecha_limite" to t(dia(inicioHace - 6)), "brazo" to t("izq"), "ortostatica" to ValorJson.Nulo,
            "comparar_brazos" to b(false), "medida_pedida" to b(false), "dias" to ValorJson.Lista(emptyList()), "faltan" to n(3),
        )
    }

    private fun ponerSesion(hace: Int, tipo: String = "estandar", enSerie: Boolean = true, tomas: List<Triple<Int, Int, Int>>) {
        val l = tomas.mapIndexed { i, x ->
            ValorJson.objeto(
                "orden" to n(i + 1), "posicion" to t("sentado"), "brazo" to t("izq"), "sis" to n(x.first), "dia" to n(x.second), "pulso" to n(x.third),
                "latido_irregular" to b(false),
            )
        }
        sesiones.add(
            0,
            mapOf(
                "id" to t(UUID.randomUUID().toString()), "serie_id" to (if (enSerie) t(ID_SERIE) else ValorJson.Nulo), "tipo" to t(tipo), "fecha" to t(dia(hace)),
                "inicio" to t("${dia(hace)}T11:02:00Z"),
                "previo" to ValorJson.objeto("cafeina" to b(false), "fumo" to b(false), "comida" to b(false), "ejercicio" to b(false)),
                "reposo_cumplido" to b(true), "temporizador_salteado" to b(false),
                "entreno_entre_dosis_y_toma" to (if (tipo == "bajo_efecto") b(false) else ValorJson.Nulo), "sintomas" to ValorJson.Lista(emptyList()),
                "lista_espera" to ValorJson.Nulo, "tomas" to ValorJson.Lista(l),
            ),
        )
        recalcular()
    }

    companion object {
        const val ID_SERIE = "33333333-3333-4333-8333-333333333333"

        private fun dia(atras: Int): String = DiaCalendario.texto((DiaCalendario.numero(FechaLocal.hoy()) ?: 0L) - atras)

        /** El estado de partida de cada escenario de las pruebas de interfaz. */
        fun escenario(nombre: String): DoblePresion {
            val d = DoblePresion()
            fun x(s: Int, di: Int, p: Int) = listOf(Triple(s, di, p))
            when (nombre) {
                "apagado" -> d.palanca = false
                "sinServidor" -> d.sinFuncion = true
                "sinSerie" -> d.ponerAparato()
                "serie0" -> { d.ponerAparato(); d.ponerSerie() }
                "serie2" -> {
                    d.ponerAparato(); d.ponerSerie(inicioHace = 2)
                    d.ponerSesion(2, tomas = x(124, 78, 62)); d.ponerSesion(1, tomas = x(128, 80, 64))
                }
                "pendienteUrgencia" -> {
                    d.ponerAparato(); d.ponerSerie(inicioHace = 1)
                    d.ponerSesion(1, tomas = x(126, 79, 60)); d.ponerSesion(0, tomas = x(184, 121, 88))
                }
                "hoyListo" -> {
                    d.ponerAparato(); d.ponerSerie(inicioHace = 1)
                    d.ponerSesion(1, tomas = x(126, 79, 60)); d.ponerSesion(0, tomas = x(124, 78, 62))
                }
                "pendienteAlta" -> {
                    d.ponerAparato(); d.ponerSerie(inicioHace = 1)
                    d.ponerSesion(1, tomas = x(126, 79, 60)); d.ponerSesion(0, tomas = x(164, 98, 70))
                }
                "completa" -> {
                    d.ponerAparato(); d.ponerSerie(inicioHace = 3)
                    d.ponerSesion(3, tomas = x(124, 78, 62)); d.ponerSesion(2, tomas = x(128, 80, 64)); d.ponerSesion(1, tomas = x(122, 76, 60))
                }
                "muneca" -> { d.ponerAparato("muneca"); d.ponerSerie() }
                "noValidado" -> { d.ponerAparato(validado = "no"); d.ponerSerie() }
                "reloj" -> d.ponerAparato("reloj_anillo_otro", validado = "no")
                "bajoEfecto" -> { d.ponerAparato(); d.ponerSerie("bajo_efecto") }
                "ortostatica" -> { d.ponerAparato(); d.ponerSerie(); d.serie?.put("ortostatica", ValorJson.Texto("acostado_parado")) }
                "brazos" -> { d.ponerAparato(); d.ponerSerie(); d.serie?.put("comparar_brazos", ValorJson.Booleano(true)) }
                "medirDeNuevo" -> { d.ponerAparato(); d.ponerSerie(); d.serie?.put("medida_pedida", ValorJson.Booleano(true)) }
                "conLista" -> {
                    d.ponerAparato(); d.ponerSerie()
                    d.tensiometros = ValorJson.parsear(
                        """{"version":"ejemplo","tramos":{"estandar":[{"nombre":"Marca de ejemplo Modelo A","codigo":"AB-1234-XY","pais":"AR","nota":null}],
                        "grande":[{"nombre":"Marca de ejemplo Modelo B","codigo":"CD-5678-ZW","pais":"AR","nota":"Manguito de 22 a 42 cm"}],"extra_grande":[],"mas_52":[]}}""",
                    )
                }
                else -> Unit   // "vacio": habilitado, sin aparato ni medida
            }
            return d
        }
    }
}
