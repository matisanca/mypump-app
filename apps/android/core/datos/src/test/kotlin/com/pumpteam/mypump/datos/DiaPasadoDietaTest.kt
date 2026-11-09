package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AgregadosComida
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AlimentoAgregado
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import com.pumpteam.mypump.reglas.CopiaDeComidas
import com.pumpteam.mypump.reglas.DiasDieta
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.MarcaComida.Estado.COMIDO
import com.pumpteam.mypump.reglas.MarcaComida.Estado.SALTADO
import java.io.IOException
import java.util.Collections
import kotlinx.coroutines.CoroutineScope
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Cargar días anteriores y copiar a hoy: lo de hoy no se toca, cada fecha va por su clave, sin leer no se escribe, la ventana
 * de «Comí» es la real de la base, y copiar nunca pisa lo cargado hoy sin que el cliente lo haya pedido. Gemelo de
 * DiaPasadoDietaTests.swift.
 */
class DiaPasadoDietaTest {
    private val raiz = carpetaTemporal("dia-pasado")

    private class Servidor {
        val marcas = Collections.synchronizedMap(HashMap<String, MutableList<ValorJson>>())
        val libres = Collections.synchronizedMap(HashMap<String, MutableList<ValorJson>>())
        val ajustes = Collections.synchronizedMap(HashMap<String, ValorJson>())
        val escrituras: MutableList<Pair<String, ValorJson>> = Collections.synchronizedList(mutableListOf())
        @Volatile var sinRed = false
        @Volatile var config = "{}"
        /** Sin red solo para guardar los ajustes: la op queda en la cola y las lecturas siguen. */
        @Volatile var cortarGuardado = false
        /** Una vez, con la foto de la lectura de ajustes ya tomada: lo que pasa mientras viaja la respuesta. */
        @Volatile var alLeerAjustes: (suspend () -> Unit)? = null
        private var seq = 0

        fun nombres(fn: String) = escrituras.toList().filter { it.first == fn }.map { it.second }

        fun ponerMarca(f: String, id: String, op: String, e: String) {
            marcas.getOrPut(f) { mutableListOf() } += ValorJson.objeto(
                "comida_id" to ValorJson.Texto(id), "fecha" to ValorJson.Texto(f), "opcion_elegida" to ValorJson.Texto(op),
                "estado" to ValorJson.Texto(e), "foods_excluidos" to ValorJson.Nulo,
            )
        }

        fun ponerLibre(f: String, d: String, k: Double) {
            seq += 1
            libres.getOrPut(f) { mutableListOf() } += ValorJson.objeto(
                "id" to ValorJson.Texto("L$seq"), "fecha" to ValorJson.Texto(f), "hora" to ValorJson.Texto("21:30:00"), "descripcion" to ValorJson.Texto(d),
                "kcal" to ValorJson.Numero(k), "prot" to ValorJson.Numero(1.0), "carb" to ValorJson.Numero(1.0), "fat" to ValorJson.Numero(1.0),
            )
        }

        fun ponerAjustes(f: String, a: ValorJson, dieta: String = DIETA_ID) {
            ajustes[f] = ValorJson.objeto("fecha" to ValorJson.Texto(f), "dieta_id" to ValorJson.Texto(dieta), "tipo_dia" to ValorJson.Nulo, "ajustes" to a)
        }

        private fun js(l: List<ValorJson>) = ValorJson.Lista(l).aJson().toString()

        val transporte = TransporteProgramado { fn, c ->
            if (sinRed) throw IOException("sin conexión a internet")
            val f = c["p_fecha"]?.comoTexto ?: ""
            when (fn) {
                "mypump_get_cliente_info" -> 200 to """[{"cliente_id":"c1","nombre":"Cliente","perfil":"natural"}]"""
                "mypump_get_dieta_activa" -> 200 to DIETA
                "mypump_get_app_config" -> 200 to config
                "mypump_get_comidas_marcadas" -> 200 to js(marcas[f].orEmpty().toList())
                "mypump_get_comidas_libres" -> 200 to js(libres[f].orEmpty().toList())
                "mypump_get_ajustes_dieta" -> {
                    val foto = js(listOfNotNull(ajustes[c["p_desde"]?.comoTexto ?: ""]))
                    alLeerAjustes?.let { alLeerAjustes = null; it() }
                    200 to foto
                }
                "mypump_marcar_comida" -> {
                    escrituras += fn to c
                    val fila = ValorJson.objeto(
                        "comida_id" to (c["p_comida_id"] ?: ValorJson.Nulo), "fecha" to ValorJson.Texto(f), "opcion_elegida" to (c["p_opcion"] ?: ValorJson.Nulo),
                        "estado" to (c["p_estado"] ?: ValorJson.Nulo), "foods_excluidos" to (c["p_foods_excluidos"] ?: ValorJson.Nulo),
                    )
                    val filas = marcas.getOrPut(f) { mutableListOf() }
                    filas.removeAll { it["comida_id"] == c["p_comida_id"] }
                    filas += fila
                    200 to js(listOf(fila))
                }
                "mypump_desmarcar_comida" -> {
                    escrituras += fn to c
                    marcas[f]?.removeAll { it["comida_id"] == c["p_comida_id"] }
                    200 to "true"
                }
                "mypump_crear_comida_libre" -> {
                    escrituras += fn to c
                    seq += 1
                    val fila = ValorJson.objeto(
                        "id" to ValorJson.Texto("N$seq"), "fecha" to ValorJson.Texto(f), "hora" to (c["p_hora"] ?: ValorJson.Nulo),
                        "descripcion" to (c["p_descripcion"] ?: ValorJson.Nulo), "kcal" to (c["p_kcal"] ?: ValorJson.Nulo),
                        "prot" to (c["p_prot"] ?: ValorJson.Nulo), "carb" to (c["p_carb"] ?: ValorJson.Nulo), "fat" to (c["p_fat"] ?: ValorJson.Nulo),
                    )
                    libres.getOrPut(f) { mutableListOf() } += fila
                    200 to js(listOf(fila))
                }
                "mypump_guardar_ajustes_dieta" -> {
                    if (cortarGuardado) throw IOException("sin conexión a internet")
                    escrituras += fn to c
                    ajustes[f] = ValorJson.objeto(
                        "fecha" to ValorJson.Texto(f), "dieta_id" to (c["p_dieta_id"] ?: ValorJson.Nulo), "tipo_dia" to (c["p_tipo_dia"] ?: ValorJson.Nulo),
                        "ajustes" to (c["p_ajustes"] ?: ValorJson.Nulo),
                    )
                    200 to "true"
                }
                "mypump_borrar_comida_libre" -> 200 to "true"
                else -> 200 to "[]"
            }
        }
    }

    private fun modelo(s: Servidor, alcance: CoroutineScope) =
        ModeloApp(ClienteRpc(transporte = s.transporte), TokenEnMemoria(TOKEN), raiz, PreferenciasEnMemoria(), alcance)

    private val hoy: String get() = FechaLocal.hoy()
    private fun hace(n: Int) = DiasDieta.sumar(hoy, -n)!!
    /** Un ajuste con [n] alimentos agregados. */
    private fun conAgregados(n: Int) = AjusteComida(
        agregados = (1..n).map { AlimentoAgregado.desde(ValorJson.parsear(AGREGADO.replace("TS", it.toString())))!! },
    )

    private fun datosLibre(d: String = "Cena afuera") = ComidaLibreNueva.Datos("21:00", d, 700.0, 30.0, 60.0, 30.0, null)

    @Test
    fun abreEnHoyYVuelve() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        assertFalse(m.enDiaPasado)
        assertEquals(hoy, m.fechaVista)
        assertEquals(8, m.fechasDieta.size)
        m.irADia(hace(1))
        assertTrue(m.enDiaPasado)
        assertEquals(hace(1), m.fechaVista)
        assertTrue(m.vistaEditable)
        m.irADia(null)
        assertFalse(m.enDiaPasado)
        assertEquals(hoy, m.fechaVista)
        // Un día que no está en la ventana no se abre.
        m.irADia(hace(30))
        assertFalse(m.enDiaPasado)
    }

    @Test
    fun marcarAyerNoTocaHoyYVaConSuFecha() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.marcar("desayuno", COMIDO, 0)
        m.irADia(hace(1))
        assertTrue(m.marcasVista.isEmpty())
        m.marcar("desayuno", SALTADO, 0)
        assertEquals(SALTADO, m.marcasVista["desayuno"]?.estado)
        assertEquals(COMIDO, m.marcasDeHoy["desayuno"]?.estado)
        // Los dos en la cola al mismo tiempo: la clave lleva la fecha, no se pisan.
        val clavePasada = MarcasComidas.clave(hace(1), "desayuno")
        val claveHoy = MarcasComidas.clave(hoy, "desayuno")
        assertNotEquals(claveHoy, clavePasada)
        assertTrue(m.outbox?.pendientesPorClave()?.get(clavePasada) != null || s.nombres("mypump_marcar_comida").isNotEmpty())
        m.outbox?.drenar()
        assertEquals(setOf(hoy, hace(1)), s.nombres("mypump_marcar_comida").mapNotNull { it["p_fecha"]?.comoTexto }.toSet())
        m.irADia(null)
        assertEquals(COMIDO, m.marcasVista["desayuno"]?.estado)
    }

    @Test
    fun ajustarAyerNoTocaLaFilaDeHoy() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(1))
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap())
        assertEquals(100, m.ajustesVista["almuerzo"]?.deltaKcal)
        assertTrue(m.ajustesDeHoy.isEmpty())
        m.outbox?.drenar()
        val w = s.nombres("mypump_guardar_ajustes_dieta")
        assertEquals(1, w.size)
        assertEquals(hace(1), w[0]["p_fecha"]?.comoTexto)
        assertEquals(DIETA_ID, w[0]["p_dieta_id"]?.comoTexto)
        m.irADia(null)
        assertTrue(m.ajustesVista.isEmpty())
    }

    @Test
    fun alimentoAgregadoAyerYDescuentoDeAyer() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.irADia(hace(1))
        m.marcar("almuerzo", COMIDO, 0)
        assertEquals(330.0, m.consumo(emptyMap()).kcal)
        m.alternarAlimento("almuerzo", 0)
        assertEquals(0.0, m.consumo(emptyMap()).kcal)
        m.irADia(null)
        assertEquals(0.0, m.consumo(emptyMap()).kcal)
        assertTrue(m.marcasDeHoy.isEmpty())
    }

    @Test
    fun libreCaeEnElDiaQueSeMira() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(3))
        assertTrue(m.crearComidaLibre(datosLibre()) is Resultado.Ok)
        assertEquals(1, m.libresVista.size)
        assertTrue(m.comidasLibres.value.isEmpty())
        assertEquals(hace(3), s.nombres("mypump_crear_comida_libre")[0]["p_fecha"]?.comoTexto)
        assertTrue(m.borrarComidaLibre(m.libresVista[0].id))
        assertTrue(m.libresVista.isEmpty())
    }

    @Test
    fun loPendienteDeEseDiaGanaALoDelServidor() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.sinRed = false
        m.irADia(hace(1))
        // La marca queda en la cola sin salir: el servidor no la ve.
        m.outbox?.cerrar()
        m.marcar("desayuno", COMIDO, 1)
        m.irADia(null)
        s.ponerMarca(hace(1), "desayuno", "A", "saltado")   // algo viejo o de otro lado
        m.irADia(hace(1))
        assertEquals("B", m.marcasVista["desayuno"]?.opcion)
        assertEquals(COMIDO, m.marcasVista["desayuno"]?.estado)
    }

    @Test
    fun sinRedNoSeAbreNiSeEscribe() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.sinRed = true
        m.irADia(hace(1))
        assertEquals(true, m.diaPasado.value?.sinRed)
        assertFalse(m.vistaEditable)
        m.marcar("desayuno", COMIDO, 0)
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap())
        assertTrue(m.marcasVista.isEmpty())
        assertTrue(m.ajustesVista.isEmpty())
        assertEquals(0, m.outbox?.pendientes())
    }

    @Test
    fun otroPlanEnEseDiaSoloDejaComidasLibres() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerAjustes(hace(2), ValorJson.objeto("almuerzo" to ValorJson.objeto("deltaKcal" to ValorJson.Numero(50.0))), dieta = "99999999-9999-4999-8999-999999999999")
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(2))
        assertEquals(true, m.diaPasado.value?.otroPlan)
        assertFalse(m.vistaEditable)
        assertTrue(m.vistaAdmiteLibres)
        assertTrue(m.ajustesVista.isEmpty())
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap())
        m.outbox?.drenar()
        assertTrue(s.nombres("mypump_guardar_ajustes_dieta").isEmpty())
        assertTrue(m.crearComidaLibre(datosLibre()) is Resultado.Ok)
    }

    @Test
    fun marcasDeComidasQueYaNoExistenTambienSonOtroPlan() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(2), "colacion-vieja", "A", "comido")
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(2))
        assertEquals(true, m.diaPasado.value?.otroPlan)
    }

    @Test
    fun comiSoloDentroDeLaVentanaDeLaBase() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        assertEquals(2, m.diasMarcar)
        m.irADia(hace(2))
        assertTrue(m.vistaPuedeMarcar)
        m.irADia(hace(5))
        assertTrue(m.vistaEditable)
        assertFalse(m.vistaPuedeMarcar)
        m.marcar("desayuno", COMIDO, 0)
        assertTrue(m.marcasVista.isEmpty())
        assertEquals(0, m.outbox?.pendientes())
    }

    @Test
    fun conLaPalancaEnSieteSeMarcaHastaElSeptimoDia() = enUnHilo { alcance ->
        val s = Servidor()
        s.config = """{"dieta_dias_marcar":7}"""
        val m = modelo(s, alcance)
        m.cargar()
        assertEquals(7, m.diasMarcar)
        m.irADia(hace(7))
        assertTrue(m.vistaPuedeMarcar)
    }

    // ── Copiar ──

    @Test
    fun copiarAyerAHoyConGramosAgregadosYMarca() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(1), "desayuno", "B", "comido")
        s.ponerAjustes(
            hace(1),
            ValorJson.objeto(
                "desayuno" to ValorJson.objeto("deltaKcal" to ValorJson.Numero(0.0), "opcion" to ValorJson.Numero(1.0), "cantidades" to ValorJson.objeto("0" to ValorJson.Numero(80.0))),
            ),
        )
        s.ponerLibre(hace(1), "Pizza", 800.0)
        val m = modelo(s, alcance)
        m.cargar()
        val p = m.prepararCopia(hace(1))
        assertNotNull(p)
        assertEquals(listOf("desayuno"), p!!.comidas.map { it.comidaId })
        assertEquals(1, p.libres.size)
        assertEquals(CopiaDeComidas.Estado.NUEVA, p.comidas[0].estado)
        val r = m.copiarAHoy(p.comidas, p.libres, emptySet())
        assertEquals(1, r.comidas)
        assertEquals(1, r.libres)
        assertEquals(0, r.saltadas)
        assertEquals("B", m.marcasDeHoy["desayuno"]?.opcion)
        assertEquals(80.0, m.ajustesDeHoy["desayuno"]?.cantidades?.get("0"))
        assertEquals("Pizza", m.comidasLibres.value.firstOrNull()?.descripcion)
        m.outbox?.drenar()
        assertEquals(hoy, s.nombres("mypump_marcar_comida").last()["p_fecha"]?.comoTexto)
        assertEquals(hoy, s.nombres("mypump_guardar_ajustes_dieta").last()["p_fecha"]?.comoTexto)
        assertEquals(hoy, s.nombres("mypump_crear_comida_libre").last()["p_fecha"]?.comoTexto)
    }

    @Test
    fun nuncaPisaLoDeHoySinPermiso() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(1), "desayuno", "A", "comido")
        val m = modelo(s, alcance)
        m.cargar()
        m.marcar("desayuno", COMIDO, 1)        // hoy comió otra opción
        val p = m.prepararCopia(hace(1))!!
        assertEquals(CopiaDeComidas.Estado.CONFLICTO, p.comidas[0].estado)
        val r = m.copiarAHoy(p.comidas, emptyList(), emptySet())
        assertEquals(1, r.saltadas)
        assertEquals(0, r.comidas)
        assertEquals("B", m.marcasDeHoy["desayuno"]?.opcion)
        val r2 = m.copiarAHoy(p.comidas, emptyList(), setOf("desayuno"))
        assertEquals(1, r2.comidas)
        assertEquals("A", m.marcasDeHoy["desayuno"]?.opcion)
    }

    @Test
    fun algoQueHoyAparecioDespuesDeArmarLaListaTampocoSePisa() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(1), "almuerzo", "A", "comido")
        val m = modelo(s, alcance)
        m.cargar()
        val p = m.prepararCopia(hace(1))!!
        assertEquals(CopiaDeComidas.Estado.NUEVA, p.comidas[0].estado)
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap())   // mientras la hoja estaba abierta
        val r = m.copiarAHoy(p.comidas, emptyList(), emptySet())
        assertEquals(1, r.saltadas)
        assertEquals(100, m.ajustesDeHoy["almuerzo"]?.deltaKcal)
        assertNull(m.marcasDeHoy["almuerzo"])
    }

    @Test
    fun copiarDosVecesNoDuplicaComidasLibres() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerLibre(hace(1), "Pizza", 800.0)
        val m = modelo(s, alcance)
        m.cargar()
        val p = m.prepararCopia(hace(1))!!
        m.copiarAHoy(emptyList(), p.libres, emptySet())
        m.copiarAHoy(emptyList(), p.libres, emptySet())
        assertEquals(1, s.nombres("mypump_crear_comida_libre").size)
        assertEquals(1, m.comidasLibres.value.size)
    }

    @Test
    fun copiarMirandoUnDiaAnteriorEscribeHoy() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(1), "almuerzo", "A", "comido")
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(1))
        val p = m.prepararCopia(hace(1))!!
        val r = m.copiarAHoy(p.comidas, emptyList(), emptySet())
        assertEquals(1, r.comidas)
        assertEquals(COMIDO, m.marcasDeHoy["almuerzo"]?.estado)
        // El día que se miraba no cambió.
        assertEquals(COMIDO, m.marcasVista["almuerzo"]?.estado)
        assertEquals(hace(1), m.fechaVista)
    }

    @Test
    fun sinRedLaCopiaAvisaEnVezDeMostrarUnDiaVacio() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        s.sinRed = true
        assertNull(m.prepararCopia(hace(1)))
    }

    @Test
    fun unaOpQueSaleMientrasViajaLaLecturaNoSePierde() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(1))
        s.cortarGuardado = true
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap())
        // Al leer la op sigue pendiente; sale con la foto del servidor (todavía sin ella) ya tomada.
        s.alLeerAjustes = {
            s.cortarGuardado = false
            m.outbox?.drenar()
        }
        m.refrescarDiaPasado()
        assertEquals(0, m.outbox?.pendientes())
        assertEquals(1, s.nombres("mypump_guardar_ajustes_dieta").size)
        assertEquals(100, m.ajustesVista["almuerzo"]?.deltaKcal)
    }

    @Test
    fun unaLibreConFechaFijadaCaeAhiAunqueSeHayaVueltoAHoy() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        assertTrue(m.crearComidaLibre(datosLibre(), hace(1)) is Resultado.Ok)
        assertEquals(hace(1), s.nombres("mypump_crear_comida_libre")[0]["p_fecha"]?.comoTexto)
        assertTrue(m.comidasLibres.value.isEmpty())
    }

    @Test
    fun unaHojaDeOtroDiaNoGuardaEnElDeAhora() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap(), fecha = hace(1))
        assertTrue(m.ajustesDeHoy.isEmpty())
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 100), emptyMap(), fecha = hoy)
        assertEquals(100, m.ajustesDeHoy["almuerzo"]?.deltaKcal)
    }

    @Test
    fun agregadosDeUnaComidaMarcadaFueraDeLaVentanaNoSeTocan() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(5), "almuerzo", "A", "comido")
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(5))
        assertFalse(m.vistaPuedeMarcar)
        m.ajustar("almuerzo", conAgregados(1), emptyMap())
        assertTrue(m.ajustesVista.isEmpty())
        assertEquals(0, m.outbox?.pendientes())
        // Sin tocar los agregados el ajuste sí vale.
        m.ajustar("almuerzo", AjusteComida(deltaKcal = 50), emptyMap())
        assertEquals(50, m.ajustesVista["almuerzo"]?.deltaKcal)
    }

    @Test
    fun unaFilaIlegibleNoEsUnDiaVacio() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerAjustes(hace(1), ValorJson.Texto("roto"))
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(1))
        assertEquals(true, m.diaPasado.value?.sinRed)
        assertFalse(m.vistaEditable)
        assertNull(m.prepararCopia(hace(1)))
    }

    @Test
    fun unPayloadDeColaIlegibleTampocoEsUnDiaVacio() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        m.outbox?.cerrar()
        m.outbox?.encolar(AjustesDieta.KIND, ValorJson.objeto("ajustes" to ValorJson.Texto("roto")), AjustesDieta.clave(hace(1)))
        m.irADia(hace(1))
        assertEquals(true, m.diaPasado.value?.sinRed)
    }

    @Test
    fun lasLibresDeUnDiaPasadoInvalidanLaLecturaEnViaje() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerLibre(hace(1), "Yogur", 100.0)
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(1))
        val orden = m.ordenDiaPasado
        m.crearComidaLibre(datosLibre())
        assertEquals(orden + 1, m.ordenDiaPasado)
        assertTrue(m.borrarComidaLibre(m.libresVista[0].id))
        assertEquals(orden + 2, m.ordenDiaPasado)
    }

    @Test
    fun unaComidaQueNoEntraSeSalteaYSeAvisa() = enUnHilo { alcance ->
        val m = modelo(Servidor(), alcance)
        m.cargar()
        val item = CopiaDeComidas.ItemComida("almuerzo", "Almuerzo", 0, "A", null, conAgregados(AgregadosComida.MAXIMO_POR_COMIDA + 1), 0.0, CopiaDeComidas.Estado.NUEVA)
        val r = m.copiarAHoy(listOf(item), emptyList(), emptySet())
        assertEquals(0, r.comidas)
        assertEquals(1, r.saltadas)
        assertTrue(m.ajustesDeHoy.isEmpty())
    }

    @Test
    fun dosLibresIgualesEnElOrigenSeCopianLasDos() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerLibre(hace(1), "Yogur", 100.0)
        s.ponerLibre(hace(1), "Yogur", 100.0)
        val m = modelo(s, alcance)
        m.cargar()
        val p = m.prepararCopia(hace(1))!!
        assertEquals(listOf(CopiaDeComidas.Estado.NUEVA, CopiaDeComidas.Estado.NUEVA), p.libres.map { it.estado })
        val r = m.copiarAHoy(emptyList(), p.libres, emptySet())
        assertEquals(2, r.libres)
        assertEquals(2, m.comidasLibres.value.size)
    }

    @Test
    fun conUnaIgualHoySeCreaSoloLaQueFalta() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerLibre(hace(1), "Yogur", 100.0)
        s.ponerLibre(hace(1), "Yogur", 100.0)
        s.ponerLibre(hoy, "Yogur", 100.0)
        val m = modelo(s, alcance)
        m.cargar()
        val p = m.prepararCopia(hace(1))!!
        assertEquals(listOf(CopiaDeComidas.Estado.IGUAL, CopiaDeComidas.Estado.NUEVA), p.libres.map { it.estado })
        val r = m.copiarAHoy(emptyList(), p.libres, emptySet())
        assertEquals(1, r.libres)
        assertEquals(2, m.comidasLibres.value.size)
    }

    @Test
    fun reemplazarConOrigenSinMarcaSacaLaDeHoy() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerAjustes(hace(1), ValorJson.objeto("almuerzo" to ValorJson.objeto("deltaKcal" to ValorJson.Numero(50.0))))
        val m = modelo(s, alcance)
        m.cargar()
        m.marcar("almuerzo", SALTADO, 0)
        val p = m.prepararCopia(hace(1))!!
        assertEquals(CopiaDeComidas.Estado.CONFLICTO, p.comidas[0].estado)
        assertNull(p.comidas[0].marca)
        val r = m.copiarAHoy(p.comidas, emptyList(), setOf("almuerzo"))
        assertEquals(1, r.comidas)
        assertNull(m.marcasDeHoy["almuerzo"])
        assertEquals(50, m.ajustesDeHoy["almuerzo"]?.deltaKcal)
        m.outbox?.drenar()
        assertEquals(1, s.nombres("mypump_desmarcar_comida").size)
    }

    @Test
    fun sinConflictoYSinMarcaEnElOrigenLaDeHoyNoSeToca() = enUnHilo { alcance ->
        val s = Servidor()
        val m = modelo(s, alcance)
        m.cargar()
        val item = CopiaDeComidas.ItemComida("almuerzo", "Almuerzo", 0, "A", null, AjusteComida(deltaKcal = 50), 0.0, CopiaDeComidas.Estado.NUEVA)
        val r = m.copiarAHoy(listOf(item), emptyList(), emptySet())
        assertEquals(1, r.comidas)
        assertTrue(m.marcasDeHoy.isEmpty())
        m.outbox?.drenar()
        assertTrue(s.nombres("mypump_desmarcar_comida").isEmpty())
    }

    @Test
    fun unaLecturaViejaDeOtroDiaNoEscribeElQueSeMiraAhora() = enUnHilo { alcance ->
        val s = Servidor()
        s.ponerMarca(hace(3), "almuerzo", "A", "comido")
        val m = modelo(s, alcance)
        m.cargar()
        m.irADia(hace(3))
        m.irADia(hace(1))
        assertTrue(m.marcasVista.isEmpty())
        assertEquals(hace(1), m.fechaVista)
    }

    private companion object {
        const val TOKEN = "AAAAAAAAAAAAAAAAAAAA"
        const val AGREGADO = """{"nombre":"Huevo","cantidad":50,"unidad":"g","gramos":50,"kcal":70,"p":6,"c":0,"g":5,"por100":{"kcal":140,"p":12,"c":0,"g":10},"origen":"base","_ts":TS}"""
        const val DIETA_ID = "55555555-5555-4555-8555-555555555555"
        const val DIETA = """[{"id":"55555555-5555-4555-8555-555555555555","version":1,"estructura":{"macros_target":{"kcal":2000,"prot":150,"carb":200,"fat":60},"comidas":[""" +
            """{"id":"desayuno","name":"Desayuno","options":[{"name":"A","foods":[{"name":"Avena","qty":100,"unit":"g","kcal":380,"prot":13,"carb":60,"fat":7},{"name":"Leche","qty":200,"unit":"ml","kcal":100,"prot":7,"carb":10,"fat":3}]},{"name":"B","foods":[{"name":"Tostada","qty":50,"unit":"g","kcal":120,"prot":10,"carb":20,"fat":1}]}]},""" +
            """{"id":"almuerzo","name":"Almuerzo","options":[{"name":"A","foods":[{"name":"Pollo","qty":200,"unit":"g","kcal":330,"prot":62,"carb":0,"fat":7}]}]}""" +
            "]}}]"
    }
}
