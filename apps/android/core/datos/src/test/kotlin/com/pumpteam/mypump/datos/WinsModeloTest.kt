package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.RecordSerie
import com.pumpteam.mypump.reglas.ReglasWins
import java.io.File
import java.util.UUID
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** «Récords y logros» (2.3.0): el permiso, la cola local y cuándo no se llama a nada. Gemelo de WinsModeloTests.swift. */
class WinsModeloTest {
    private val token = "WWWWWWWWWWWWWWWWWWWW"
    private fun raiz() = carpetaTemporal("wins")

    /** El modelo suelto, con la palanca ya leída (en la app la recuerda `ModeloApp.cargar`). */
    private fun armar(d: DobleColaA, r: File = raiz(), palanca: Boolean? = true) =
        ModeloWins(ClienteRpc(transporte = d), token, Disco(r, token)).also { m -> palanca?.let(m::recordarPalanca) }

    private val records: List<ReglasWins.Record>
        get() = ReglasWins.records(
            listOf(
                ReglasWins.Ejercicio("remo con barra", "Remo con barra", listOf(RecordSerie.Marca(55.0, 8)), listOf(RecordSerie.Marca(57.5, 8))),
                ReglasWins.Ejercicio("curl", "Curl", listOf(RecordSerie.Marca(12.0, 10)), listOf(RecordSerie.Marca(12.0, 12))),
            ),
        )

    @Test fun lasPalancasSeLeenYSinLaClaveEstanApagadas() {
        val p = PalancaRemota.desde(ValorJson.objeto("wins_app" to ValorJson.Booleano(true), "lista_previa" to ValorJson.Booleano(true)))
        assertTrue(p.winsApp && p.listaPrevia)
        assertFalse(PalancaRemota.desde(ValorJson.objeto()).winsApp || PalancaRemota.desde(ValorJson.objeto()).listaPrevia)
        val raras = PalancaRemota.desde(ValorJson.objeto("wins_app" to ValorJson.Texto("true"), "lista_previa" to ValorJson.Numero(1.0)))
        assertFalse(raras.winsApp || raras.listaPrevia)
        assertFalse(PalancaRemota.deFabrica.winsApp || PalancaRemota.deFabrica.listaPrevia)
    }

    @Test fun conLaPalancaApagadaModeloAppNoLlamaANada() = enUnHilo { alcance ->
        val d = DobleColaA.escenario("apagado")
        val m = ModeloApp(ClienteRpc(transporte = d), TokenEnMemoria(token), raiz(), PreferenciasEnMemoria(), alcance)
        m.cargar()
        m.alVolverAPrimerPlano()
        m.sincronizarListaPrevia()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        assertTrue(d.llamadasWins.isEmpty() && d.llamadasLista.isEmpty())
        val w = m.wins.value!!
        assertFalse(w.prendida || w.permiso || w.estado.value.visibleEnMisDatos)
        assertFalse(w.encolar(records))
        assertFalse(w.encolarRacha(7, 9000))
        w.vaciar()
        assertFalse(w.darPermiso(records))
        assertNull(m.listaPrevia.value?.vista?.value)
        assertTrue(d.llamadasWins.isEmpty() && d.llamadasLista.isEmpty())
    }

    @Test fun conLaPalancaPrendidaTraeElEstadoYAlVolverTambien() = enUnHilo { alcance ->
        val d = DobleColaA.escenario("conPermiso")
        val m = ModeloApp(ClienteRpc(transporte = d), TokenEnMemoria(token), raiz(), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(listOf("mypump_wins_estado"), d.llamadasWins)
        val w = m.wins.value!!
        assertTrue(w.prendida && w.permiso && w.estado.value.visibleEnMisDatos)
        m.alVolverAPrimerPlano()
        assertEquals(listOf("mypump_wins_estado", "mypump_wins_estado"), d.llamadasWins)
        // La palanca se apaga: en la carga siguiente ya no se llama, y el permiso recordado deja ver el interruptor.
        d.palancaWins = false
        m.cargar()
        assertEquals(2, d.llamadasWins.size)
        assertTrue(!w.prendida && w.permiso && w.estado.value.visibleEnMisDatos)
    }

    @Test fun sinHaberLeidoLaPalancaNoSeLlama(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso")
        val m = armar(d, palanca = null)
        m.refrescar()
        m.vaciar()
        assertFalse(m.encolar(records))
        assertTrue(d.llamadas.isEmpty())
    }

    @Test fun sinPermisoNuncaEncola(): Unit = runBlocking {
        val d = DobleColaA.escenario("sinPermiso")
        val m = armar(d)
        m.refrescar()
        assertTrue(m.prendida && !m.permiso)
        assertFalse(m.encolar(records))
        assertFalse(m.encolarRacha(7, 9000))
        assertTrue(m.cola.isEmpty())
        m.vaciar()
        assertFalse("mypump_wins_registrar" in d.llamadasWins)
    }

    @Test fun darElPermisoEncolaLosRecordsDelFestejoYLosManda(): Unit = runBlocking {
        val d = DobleColaA.escenario("sinPermiso")
        val m = armar(d)
        m.refrescar()
        assertTrue(m.darPermiso(records, "2026-11-10"))
        assertTrue(m.permiso && d.permiso)
        assertEquals(listOf(true), d.permisosPedidos.toList())
        // El permiso viaja con su versión y la plataforma.
        assertEquals(ValorJson.Numero(1.0), d.cuerposPermiso.first()["p_version"])
        assertEquals(ValorJson.Texto("android"), d.cuerposPermiso.first()["p_plataforma"])
        m.vaciar()
        assertTrue(m.cola.isEmpty())
        assertEquals(listOf("record_kg", "record_reps"), d.registrados.map { it.tipo })
        assertEquals(listOf("remo con barra", "curl"), d.registrados.map { it.clave })
        assertTrue(d.registrados.all { it.dia == "2026-11-10" && UUID.fromString(it.id).toString() == it.id })
        assertEquals(
            ValorJson.objeto(
                "ejercicio" to ValorJson.Texto("Remo con barra"), "kg" to ValorJson.Numero(57.5), "reps" to ValorJson.Numero(8.0),
                "antes_kg" to ValorJson.Numero(55.0), "antes_reps" to ValorJson.Numero(8.0),
            ),
            d.registrados.first().datos,
        )
    }

    @Test fun alEncolarSeLanzaElVaciado() = enUnHilo { alcance ->
        val d = DobleColaA.escenario("conPermiso")
        val lanzadas = mutableListOf<suspend () -> Unit>()
        val m = ModeloWins(ClienteRpc(transporte = d), token, Disco(raiz(), token)) { lanzadas += it }
        m.recordarPalanca(true)
        m.refrescar()
        assertTrue(m.encolar(records))
        assertEquals(1, lanzadas.size)
        lanzadas.forEach { it() }
        assertTrue(m.cola.isEmpty())
        assertEquals(2, d.registrados.size)
    }

    @Test fun sinRedElPermisoNoQuedaDado(): Unit = runBlocking {
        val d = DobleColaA.escenario("sinRedPermiso")
        val m = armar(d)
        m.refrescar()
        assertFalse(m.darPermiso(records))
        assertTrue(!m.permiso && m.cola.isEmpty())
        // Y sacarlo sin red tampoco cambia nada.
        d.sinRedPermiso = false
        d.permiso = true
        m.refrescar()
        d.sinRedPermiso = true
        assertFalse(m.revocar())
        assertTrue(m.permiso)
    }

    @Test fun revocarVaciaLaColaYAndaConLaPalancaApagada(): Unit = runBlocking {
        val r = raiz()
        val d = DobleColaA.escenario("conPermiso").apply { registrarCaido = true }
        val m = armar(d, r)
        m.refrescar()
        assertTrue(m.encolar(records))
        m.vaciar()
        assertEquals(2, m.cola.size)
        // La palanca se apaga: el permiso recordado sigue y el interruptor se sigue viendo para poder sacarlo.
        d.palancaWins = false
        val m2 = armar(d, r, palanca = false)
        assertTrue(m2.permiso && m2.estado.value.visibleEnMisDatos && !m2.prendida && m2.cola.size == 2)
        m2.refrescar()
        m2.vaciar()
        assertEquals(1, d.llamadasWins.count { it == "mypump_wins_estado" })
        assertTrue(m2.revocar())
        assertEquals(listOf(false), d.permisosPedidos.toList())
        assertTrue(!m2.permiso && m2.cola.isEmpty() && !m2.estado.value.visibleEnMisDatos && !d.permiso)
        assertTrue(armar(d, r, palanca = null).cola.isEmpty())
    }

    @Test fun laColaPersisteYSeReintenta(): Unit = runBlocking {
        val r = raiz()
        val d = DobleColaA.escenario("conPermiso").apply { registrarCaido = true }
        val m = armar(d, r)
        m.refrescar()
        assertTrue(m.encolar(records, "2026-11-10"))
        assertTrue(m.encolarRacha(7, 9000, "2026-11-10"))
        assertFalse(m.encolarRacha(8, 9000), "8 días no es un hito")
        m.vaciar()
        assertTrue(m.cola.size == 3 && d.registrados.isEmpty(), "un 503 lo deja para después")
        // Sin red tampoco se pierde.
        d.registrarCaido = false
        d.sinRed = true
        m.vaciar()
        assertEquals(3, m.cola.size)
        // Otra vez la app: la cola está en disco y sale con los mismos ids.
        val ids = m.cola.map { it.id }
        d.sinRed = false
        val m2 = armar(d, r, palanca = null)
        assertTrue(m2.cola.map { it.id } == ids && m2.permiso && m2.prendida)
        m2.refrescar()
        m2.vaciar()
        assertTrue(m2.cola.isEmpty())
        assertEquals(ids, d.registrados.map { it.id })
        assertEquals(
            DobleColaA.Registro(
                ids[2], "racha_pasos", "pasos", "2026-11-10",
                ValorJson.objeto("dias" to ValorJson.Numero(7.0), "meta" to ValorJson.Numero(9000.0)),
            ),
            d.registrados.last(),
        )
        assertTrue(armar(d, r, palanca = null).cola.isEmpty())
    }

    @Test fun elMismoLogroDelDiaReemplazaAlQueNoSalio(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso").apply { registrarCaido = true }
        val m = armar(d)
        m.refrescar()
        m.encolar(records, "2026-11-10")
        val ids = m.cola.map { it.id }
        // Lo mismo otra vez (rotar la pantalla, reabrir el festejo): no se encola de nuevo ni cambian los ids.
        assertTrue(m.encolar(records, "2026-11-10"))
        assertEquals(ids, m.cola.map { it.id })
        // Mejoró la marca del remo: reemplaza al que no salió, con id nuevo; el curl queda como estaba.
        val mejor = ReglasWins.records(
            listOf(ReglasWins.Ejercicio("remo con barra", "Remo con barra", listOf(RecordSerie.Marca(55.0, 8)), listOf(RecordSerie.Marca(60.0, 8)))),
        )
        m.encolar(mejor, "2026-11-10")
        assertEquals(2, m.cola.size)
        assertEquals(ids[1], m.cola.first().id)
        assertNotEquals(ids[0], m.cola.last().id)
        assertEquals(ValorJson.Numero(60.0), m.cola.last().datos["kg"])
        // Otro día es otro logro.
        m.encolar(records, "2026-11-11")
        assertEquals(4, m.cola.size)
        // La racha, igual.
        assertTrue(m.encolarRacha(7, 9000, "2026-11-10"))
        val racha = m.cola.last().id
        assertTrue(m.encolarRacha(7, 9000, "2026-11-10"))
        assertTrue(m.cola.size == 5 && m.cola.last().id == racha)
    }

    @Test fun loYaEnviadoEnEstaSesionNoSeMandaDeNuevo(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso")
        val m = armar(d)
        m.refrescar()
        m.encolar(records, "2026-11-10")
        m.vaciar()
        assertTrue(m.cola.isEmpty() && d.registrados.size == 2)
        // El festejo vuelve a aparecer (rotar el teléfono): nada nuevo en la cola ni en el servidor.
        assertTrue(m.encolar(records, "2026-11-10"))
        m.vaciar()
        assertTrue(m.cola.isEmpty())
        assertEquals(2, d.registrados.size)
        assertEquals(2, d.llamadasWins.count { it == "mypump_wins_registrar" })
        // Con una marca mejor, sí.
        m.encolar(
            ReglasWins.records(
                listOf(ReglasWins.Ejercicio("remo con barra", "Remo con barra", listOf(RecordSerie.Marca(55.0, 8)), listOf(RecordSerie.Marca(60.0, 8)))),
            ),
            "2026-11-10",
        )
        m.vaciar()
        assertEquals(3, d.registrados.size)
    }

    @Test fun loQueElServidorNoEntiendeSaleAlTercerIntento(): Unit = runBlocking {
        for (caso in listOf("token", "raro", "400")) {
            val r = raiz()
            val d = DobleColaA.escenario("conPermiso")
            val m = armar(d, r)
            m.refrescar()
            when (caso) {
                "token" -> d.tokenCaido = true
                "raro" -> d.registrarRaro = true
                else -> d.registrar400 = true
            }
            m.encolar(records, "2026-11-10")
            val ids = m.cola.map { it.id }
            m.vaciar()
            assertEquals(listOf(1, 0), m.cola.map { it.intentos }, caso)
            // Los intentos se guardan: otra vez la app, sigue la cuenta.
            val m2 = armar(d, r, palanca = null)
            assertEquals(listOf(1, 0), m2.cola.map { it.intentos }, caso)
            m2.vaciar()
            assertEquals(ids, m2.cola.map { it.id }, caso)
            // Al tercero sale el primero y se sigue con el otro.
            m2.vaciar()
            assertEquals(listOf(ids[1]), m2.cola.map { it.id }, caso)
            assertEquals(1, m2.cola.first().intentos, caso)
            m2.vaciar()
            m2.vaciar()
            assertTrue(m2.cola.isEmpty(), caso)
            assertTrue(d.registrados.isEmpty() && m2.permiso && m2.prendida, caso)
            assertEquals(6, d.llamadasWins.count { it == "mypump_wins_registrar" }, caso)
        }
    }

    @Test fun laRedCaidaOUn5xxNoCuentanIntentos(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso").apply { registrarCaido = true }
        val m = armar(d)
        m.refrescar()
        m.encolar(records, "2026-11-10")
        repeat(5) { m.vaciar() }
        d.registrarCaido = false
        d.sinRed = true
        repeat(5) { m.vaciar() }
        assertEquals(listOf(0, 0), m.cola.map { it.intentos })
        d.sinRed = false
        m.vaciar()
        assertTrue(m.cola.isEmpty() && d.registrados.size == 2)
    }

    @Test fun elServidorRechazaLosDatosYSeDescarta(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso").apply { registrarRechaza = true }
        val m = armar(d)
        m.refrescar()
        m.encolar(records)
        m.vaciar()
        assertTrue(m.cola.isEmpty() && d.registrados.isEmpty() && m.permiso)
        assertEquals(2, d.llamadasWins.count { it == "mypump_wins_registrar" })
    }

    @Test fun sinPermisoEnElServidorSeRecuerdaYSeVaciaLaCola(): Unit = runBlocking {
        val r = raiz()
        val d = DobleColaA.escenario("conPermiso")
        val m = armar(d, r)
        m.refrescar()
        d.permiso = false   // lo sacó desde otro teléfono
        m.encolar(records)
        m.encolarRacha(7, 9000)
        assertEquals(3, m.cola.size)
        m.vaciar()
        assertTrue(!m.permiso && m.cola.isEmpty())
        assertEquals(1, d.llamadasWins.count { it == "mypump_wins_registrar" })
        assertFalse(armar(d, r, palanca = null).permiso)
        assertFalse(m.encolar(records))
    }

    @Test fun elTokenCaidoNoPierdeNada(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso")
        val m = armar(d)
        m.refrescar()
        d.tokenCaido = true
        m.encolar(records)
        m.vaciar()
        m.refrescar()
        assertTrue(m.cola.size == 2 && m.permiso && m.prendida)
        // Se recupera antes del tercer intento: sale todo.
        d.tokenCaido = false
        m.vaciar()
        assertTrue(m.cola.isEmpty() && d.registrados.size == 2)
    }

    @Test fun sinLaFuncionDelServidorSeVaciaLaCola(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso").apply { registrarCaido = true }
        val m = armar(d)
        m.refrescar()
        m.encolar(records)
        m.vaciar()
        assertEquals(2, m.cola.size)
        d.registrarCaido = false
        d.sinFuncion = true
        m.vaciar()
        assertTrue(m.cola.isEmpty())
        // PGRST202 al mandar: además deja de estar activa y el permiso se baja (nada que mostrar).
        assertTrue(!m.prendida && !m.permiso && !m.estado.value.activa)
        // Y al preguntar el estado no queda nada prendido ni dado: no se muestra ni se encola nada.
        m.refrescar()
        assertTrue(!m.prendida && !m.permiso && !m.estado.value.visibleEnMisDatos)
        assertFalse(m.encolar(records))
    }

    @Test fun sinElServidorNuevoDesdeElPrincipioNadaSeMuestra() = enUnHilo { alcance ->
        val d = DobleColaA.escenario("sinServidor")
        val m = ModeloApp(ClienteRpc(transporte = d), TokenEnMemoria(token), raiz(), PreferenciasEnMemoria(), alcance)
        m.cargar()
        assertEquals(ModeloApp.Fase.LISTO, m.fase.value)
        val w = m.wins.value!!
        assertTrue(!w.prendida && !w.permiso && !w.estado.value.visibleEnMisDatos)
        assertFalse(w.darPermiso(records))
        assertNull(m.listaPrevia.value?.vista?.value)
    }

    @Test fun elTopeDeLaColaDescartaLoMasViejo(): Unit = runBlocking {
        val d = DobleColaA.escenario("conPermiso")
        val m = armar(d)
        m.refrescar()
        d.sinRed = true
        for (i in 0 until 60) {
            m.encolar(
                ReglasWins.records(
                    listOf(ReglasWins.Ejercicio("ejercicio $i", "Ejercicio $i", listOf(RecordSerie.Marca(10.0, 10)), listOf(RecordSerie.Marca(12.0, 10)))),
                ),
            )
        }
        assertEquals(ModeloWins.TOPE_COLA, m.cola.size)
        assertTrue(m.cola.first().clave == "ejercicio 10" && m.cola.last().clave == "ejercicio 59")
    }

    @Test fun sinRedAlAbrirValeElUltimoPermisoConocido(): Unit = runBlocking {
        val r = raiz()
        val d = DobleColaA.escenario("conPermiso")
        armar(d, r).refrescar()
        d.sinRed = true
        val m = armar(d, r, palanca = null)
        m.refrescar()
        assertTrue(m.permiso && m.prendida)
        assertTrue(m.encolar(records))
        assertEquals(2, m.cola.size)
    }

    @Test fun unArchivoTocadoNoRompeYLoQueNoSeEntiendeSeDescarta() {
        val r = raiz()
        val disco = Disco(r, token)
        disco.guardar(
            ModeloWins.ARCHIVO,
            ValorJson.parsear(
                """{"palanca":true,"activa":true,"permiso":true,"cola":[{"id":"a","tipo":"otro_tipo","clave":"x","dia":"2026-11-10","datos":{}},
                   {"id":"b","tipo":"record_kg","clave":"x","dia":"2026-11-10","datos":{"kg":1}}, 7, {"id":"c","tipo":"record_kg"}]}""",
            ),
        )
        val m = ModeloWins(ClienteRpc(transporte = DobleColaA()), token, disco)
        assertEquals(listOf("b"), m.cola.map { it.id })
    }

    @Test fun laDemoNoTieneModeloNiLlamaANada() = enUnHilo { alcance ->
        val d = DobleColaA.escenario("conPermiso")
        val m = ModeloApp(ClienteRpc(transporte = d), TokenEnMemoria(null), raiz(), PreferenciasEnMemoria(), alcance)
        m.entrarEnDemo(
            Compartido.texto("demo/rutina.json"), Compartido.texto("demo/dieta.json"), historial = Compartido.texto("demo/historial.json"),
        )
        m.cargar()
        m.alVolverAPrimerPlano()
        m.sincronizarListaPrevia()
        delay(50)
        assertNull(m.wins.value)
        assertTrue(d.llamadas.isEmpty(), d.llamadas.toString())
    }
}
