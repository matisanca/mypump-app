package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PlataformaSalud
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Revisión del 15-oct, hallazgo 3 (gemelo de SaludPorCuentaTests.swift): el estado de Salud era del teléfono. Con el link de
 * otra cuenta en el mismo teléfono (Mati mirando la de un cliente), al abrir se subían 7 días de su salud a la ficha del
 * otro, y el historial quedaba marcado como hecho para una cuenta que nunca lo trajo.
 */
class SaludPorCuentaTest {
    /** Lo que dejó la migración (o una versión anterior): Health Connect conectado, sin cuenta. */
    private fun telefonoConectado() = PreferenciasEnMemoria(mapOf(ClaveSalud.CONECTADO to "1", ClaveSalud.HISTORIAL_HECHO to "1"))

    @Test
    fun laPrimeraCuentaSeQuedaConLoQueHabiaYLaOtraArrancaSinConectar() {
        val telefono = telefonoConectado()
        val duenio = AlmacenSaludPorCuenta(telefono, "aaaa")
        assertTrue(duenio.leer(ClaveSalud.CONECTADO) == "1" && duenio.leer(ClaveSalud.HISTORIAL_HECHO) == "1")
        val otra = AlmacenSaludPorCuenta(telefono, "bbbb")
        assertTrue(otra.leer(ClaveSalud.CONECTADO) == null && otra.leer(ClaveSalud.HISTORIAL_HECHO) == null)
        // Lo que haga una no toca a la otra, y la dueña no cambia al volver.
        otra.guardar(ClaveSalud.CONECTADO, "1")
        duenio.guardar(ClaveSalud.ULTIMA_SYNC, "2026-10-15T03:00:00.000Z")
        assertNull(AlmacenSaludPorCuenta(telefono, "bbbb").leer(ClaveSalud.ULTIMA_SYNC))
        assertEquals("1", AlmacenSaludPorCuenta(telefono, "aaaa").leer(ClaveSalud.CONECTADO))
        assertEquals("aaaa", telefono.leer(AlmacenSaludPorCuenta.DUENIA))
    }

    /**
     * Con el ModeloApp de cada cuenta (lo que arma la app), no con el ModeloSalud suelto como iOS: así la prueba también
     * mira que la cuenta le pase SU almacén a Salud.
     */
    @Test
    fun alAbrirConOtraCuentaNoSeSubeLaSaludDelDuenio() = enUnHilo { alcance ->
        val telefono = telefonoConectado()   // las preferencias del teléfono: las comparten las dos cuentas
        ModeloSalud.fuenteDelSistema = FuenteConPasos()
        try {
            // El dueño abre primero (se queda con lo que había) y después se abre el link de otra persona.
            val baseDuenio = BasePorFuncion().also { it.respuestas["mypump_ingest_salud"] = 200 to ValorJson.Numero(1.0) }
            val duenio = ModeloApp(ClienteRpc(transporte = baseDuenio), TokenEnMemoria("tok-del-duenio-0000001"), carpetaTemporal("salud-a"), telefono, alcance)
            val base = BasePorFuncion()
            val otra = ModeloApp(ClienteRpc(transporte = base), TokenEnMemoria("tok-de-otra-cuenta-00001"), carpetaTemporal("salud-b"), telefono, alcance)
            val saludOtra = otra.salud.value!!
            saludOtra.alAbrir()
            assertFalse(saludOtra.conectado.value)
            assertEquals(0, base.cuantas("mypump_ingest_salud"), "se subió la salud del dueño a otra cuenta")

            // El dueño sí sincroniza al abrir.
            val saludDuenio = duenio.salud.value!!
            saludDuenio.alAbrir()
            assertTrue(saludDuenio.conectado.value)
            assertTrue(baseDuenio.cuantas("mypump_ingest_salud") >= 1)
            assertEquals(Disco.huella("tok-del-duenio-0000001"), telefono.leer(AlmacenSaludPorCuenta.DUENIA))
        } finally {
            ModeloSalud.fuenteDelSistema = null
        }
    }
}

/** Un Health Connect con pasos de hoy: si se sincroniza, hay algo para subir. */
private class FuenteConPasos : FuenteSalud {
    override val plataforma = PlataformaSalud.ANDROID

    override suspend fun disponible(): Boolean = true

    override suspend fun pedirLectura(tipos: List<String>) {}

    override suspend fun permisos(tipos: List<String>): PermisosSalud = PermisosSalud(tipos, emptyList())

    override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> =
        if (dataType == "steps") listOf(BaldeDiario(hasta - 3_600_000, 4_321.0)) else emptyList()

    override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> = emptyList()

    override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = emptyList()
}
