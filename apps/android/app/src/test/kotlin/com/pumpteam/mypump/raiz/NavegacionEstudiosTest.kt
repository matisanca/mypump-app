package com.pumpteam.mypump.raiz

import com.pumpteam.mypump.datos.DestinoAviso
import com.pumpteam.mypump.reglas.MiSalud
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * «Mi salud» (2.3.0): los destinos viejos que llevaban a Estudios, Presión o Salud ahora abren Mi salud en su bloque. Mi
 * salud siempre se abre (es la caída segura): si la sección del bloque no existe, se queda arriba de todo.
 */
class NavegacionEstudiosTest {
    @Test
    fun elAvisoDeEstudiosAbreMiSaludEnEstudios() {
        val n = Navegacion(pestana = Pestana.DIETA, tecnicaEnMisDatos = true)
        n.ir(DestinoAviso.ESTUDIOS)
        assertEquals(Pestana.REVISION, n.pestana)
        assertTrue(n.miSalud)
        assertFalse(n.misDatos, "ya no pasa por Mis datos")
        assertFalse(n.tecnicaEnMisDatos)
        assertEquals(MiSalud.Bloque.ESTUDIOS, n.anclaMiSalud)
        assertTrue(n.enfocarEstudios, "a la primera tarjeta nueva")
    }

    @Test
    fun elAvisoDePresionAbreMiSaludYPresionEncima() {
        val n = Navegacion(pestana = Pestana.ENTRENO)
        n.ir(DestinoAviso.PRESION)
        assertEquals(Pestana.REVISION, n.pestana)
        assertTrue(n.miSalud)
        assertEquals(MiSalud.Bloque.PRESION, n.anclaMiSalud)
        assertTrue(n.presion && n.presionDirecta)
        // Al cerrar Presión queda Mi salud.
        n.cerrarPresion()
        assertTrue(n.miSalud)
        assertEquals(Pestana.REVISION, n.pestana)
    }

    @Test
    fun myDayAbreMiSaludEnRecuperacion() {
        val n = Navegacion(pestana = Pestana.CHAT)
        n.ir(DestinoAviso.RECUPERACION)
        assertEquals(Pestana.REVISION, n.pestana)
        assertTrue(n.miSalud)
        assertEquals(MiSalud.Bloque.RECUPERACION, n.anclaMiSalud)
    }

    @Test
    fun losOtrosDestinosNoCambian() {
        val n = Navegacion()
        n.irAMiSalud()
        n.ir(DestinoAviso.FUERZA)
        assertEquals(Pestana.SALUD, n.pestana)
        assertEquals(SegmentoSalud.FUERZA, n.segmentoSalud)
        assertFalse(n.miSalud, "Fuerza no es de salud: Atrás vuelve a Revisión")
        n.volverDeSalud()
        assertEquals(Pestana.REVISION, n.pestana)
        assertFalse(n.miSalud)

        // `salud` (Mis datos en el kit): Mi salud en la recuperación, como la web y iOS.
        n.misDatos = true
        n.ir(DestinoAviso.MIS_DATOS)
        assertFalse(n.misDatos)
        assertTrue(n.miSalud)
        assertEquals(MiSalud.Bloque.RECUPERACION, n.anclaMiSalud)

        n.irAMiSalud()
        n.ir(DestinoAviso.REVISION)
        assertFalse(n.miSalud)
        assertEquals(AnclaRevision.AVISO, n.anclaRevision)

        n.irAMiSalud()
        n.ir(DestinoAviso.CHAT)
        assertEquals(Pestana.CHAT, n.pestana)
    }

    @Test
    fun lasTarjetasDelInicioLlevanASuBloque() {
        val n = Navegacion()
        n.irAEstudios()
        assertTrue(n.miSalud && n.enfocarEstudios)
        assertEquals(MiSalud.Bloque.ESTUDIOS, n.anclaMiSalud)
        n.elegir(Pestana.ENTRENO)
        n.irAControl()
        assertTrue(n.miSalud)
        assertEquals(MiSalud.Bloque.CONTROL, n.anclaMiSalud)
        assertFalse(n.enfocarEstudios, "no arrastra el foco viejo")
        n.elegir(Pestana.ENTRENO)
        n.irAPresion(directo = false)
        assertEquals(MiSalud.Bloque.PRESION, n.anclaMiSalud)
        assertTrue(n.presion)
        assertFalse(n.presionDirecta)
    }

    @Test
    fun saludDesdeMiSaludVuelveAMiSalud() {
        val n = Navegacion()
        n.irAMiSalud(MiSalud.Bloque.RECUPERACION)
        n.anclaMiSalud = null
        n.irASalud(SegmentoSalud.RECUPERACION, desdeMiSalud = true)
        assertEquals(Pestana.SALUD, n.pestana)
        n.volverDeSalud()
        assertEquals(Pestana.REVISION, n.pestana)
        assertTrue(n.miSalud)
        // Tocar Revisión estando en Mi salud vuelve a Revisión (el principio de la pila).
        n.elegir(Pestana.REVISION)
        assertFalse(n.miSalud)
        // Y con Salud abierta desde Mi salud, también.
        n.irAMiSalud()
        n.irASalud(SegmentoSalud.RECUPERACION, desdeMiSalud = true)
        n.elegir(Pestana.REVISION)
        assertEquals(Pestana.REVISION, n.pestana)
        assertFalse(n.miSalud)
    }

    @Test
    fun irAMisDatosOARevisionCierraMiSalud() {
        val n = Navegacion()
        n.irAEstudios()
        n.irARevision(null)
        assertFalse(n.miSalud || n.enfocarEstudios)
        assertNull(n.anclaMiSalud)
    }

    @Test
    fun rotarConservaMiSalud() {
        val n = Navegacion()
        n.irAMiSalud()
        val guardado = with(Navegacion.Guardador) { androidx.compose.runtime.saveable.SaverScope { true }.save(n) }!!
        val vuelta = Navegacion.Guardador.restore(guardado)!!
        assertTrue(vuelta.miSalud)
        assertEquals(Pestana.REVISION, vuelta.pestana)
    }
}
