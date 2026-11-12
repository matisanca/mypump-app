package com.pumpteam.mypump.datos

import com.pumpteam.mypump.reglas.BaldeDiario
import com.pumpteam.mypump.reglas.EntrenoCrudo
import com.pumpteam.mypump.reglas.MuestraSalud
import com.pumpteam.mypump.reglas.PasosHealthConnect
import com.pumpteam.mypump.reglas.PlataformaSalud
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** 2.3.1: `ModeloSalud.estadoPasos()` lee del teléfono los pasos de 3 días con su origen. */
class EstadoPasosTest {
    private class FuentePasos(
        override val plataforma: PlataformaSalud = PlataformaSalud.ANDROID,
        val permiso: Boolean = true,
        val pasos: List<MuestraSalud> = emptyList(),
        val falla: Boolean = false,
    ) : FuenteSalud {
        var ventana: Pair<Double, Double>? = null
        override suspend fun disponible() = true
        override suspend fun pedirLectura(tipos: List<String>) {}
        override suspend fun permisos(tipos: List<String>) =
            if (permiso) PermisosSalud(tipos, emptyList()) else PermisosSalud(emptyList(), tipos)
        override suspend fun agregado(dataType: String, agregacion: String, desde: Double, hasta: Double): List<BaldeDiario> = emptyList()
        override suspend fun muestras(dataType: String, desde: Double, hasta: Double, limite: Int): List<MuestraSalud> {
            if (falla) throw ErrorFuenteSalud("Failed to read samples.")
            ventana = desde to hasta
            return if (dataType == "steps") pasos else emptyList()
        }
        override suspend fun entrenos(desde: Double, hasta: Double): List<EntrenoCrudo> = emptyList()
    }

    private fun m(f: FuenteSalud?, alcance: kotlinx.coroutines.CoroutineScope) =
        ModeloSalud(ClienteRpc(transporte = BasePorFuncion()), "tok-de-prueba-nativa-0001", f, PreferenciasEnMemoria(), alcance)

    private fun muestra(paquete: String, n: Double) = MuestraSalud(0.0, 0.0, n, paquete, paquete)

    @Test fun ceroPasosConPermisoAvisa() = enUnHilo { a ->
        val f = FuentePasos()
        assertEquals(PasosHealthConnect.Estado(true, null), m(f, a).estadoPasos())
        val (desde, hasta) = f.ventana!!
        assertEquals(3 * 86_400_000.0, hasta - desde)
    }

    @Test fun conPasosDiceElOrigen() = enUnHilo { a ->
        val f = FuentePasos(pasos = listOf(muestra(PasosHealthConnect.SAMSUNG_HEALTH, 3000.0)))
        assertEquals(PasosHealthConnect.Estado(false, "Samsung Health"), m(f, a).estadoPasos())
    }

    @Test fun sinPermisoIphoneOFallaNoAvisa() = enUnHilo { a ->
        assertNull(m(FuentePasos(permiso = false), a).estadoPasos())
        assertNull(m(FuentePasos(plataforma = PlataformaSalud.IOS), a).estadoPasos())
        assertNull(m(FuentePasos(falla = true), a).estadoPasos())
        assertNull(m(null, a).estadoPasos())
    }
}
