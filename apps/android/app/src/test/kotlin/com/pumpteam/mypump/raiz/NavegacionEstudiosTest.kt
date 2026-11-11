package com.pumpteam.mypump.raiz

import com.pumpteam.mypump.datos.DestinoAviso
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** El destino `estudios`: primero Mis datos (la caída segura) y Estudios recién cuando se sabe que la sección existe. */
class NavegacionEstudiosTest {
    @Test
    fun elAvisoDejaEnMisDatosYPideEstudios() {
        val n = Navegacion(pestana = Pestana.DIETA, tecnicaEnMisDatos = true)
        n.ir(DestinoAviso.ESTUDIOS)
        assertEquals(Pestana.REVISION, n.pestana)
        assertTrue(n.misDatos)
        assertFalse(n.estudiosEnMisDatos, "todavía no se sabe si existe")
        assertFalse(n.tecnicaEnMisDatos)
        assertEquals(1, n.pedidoEstudios)
        // La sección existe: se abre, con la primera tarjeta nueva a la vista.
        n.abrirEstudiosPedido()
        assertTrue(n.estudiosEnMisDatos)
        assertTrue(n.enfocarEstudios)
        // Otro aviso con Estudios ya abierta: vuelve a pedirlo.
        n.ir(DestinoAviso.ESTUDIOS)
        assertEquals(2, n.pedidoEstudios)
    }

    @Test
    fun siElAlumnoSeFueMientrasSeEsperabaNoSeLoArrastra() {
        for (irse in listOf<(Navegacion) -> Unit>({ it.elegir(Pestana.CHAT) }, { it.misDatos = false }, { it.gimnasioEnMisDatos = true }, { it.irARevision(null) })) {
            val n = Navegacion()
            n.ir(DestinoAviso.ESTUDIOS)
            irse(n)
            n.abrirEstudiosPedido()
            assertFalse(n.estudiosEnMisDatos)
            assertFalse(n.enfocarEstudios)
        }
    }

    @Test
    fun laTarjetaDeEntrenoAbreEnElMomento() {
        val n = Navegacion()
        n.irAEstudios(resuelto = true)
        assertEquals(Pestana.REVISION, n.pestana)
        assertTrue(n.misDatos && n.estudiosEnMisDatos && n.enfocarEstudios)
        assertEquals(0, n.pedidoEstudios, "no queda nada pedido")
        // Ir a Mis datos a secas (el aviso de salud) no arrastra el foco viejo.
        n.ir(DestinoAviso.MIS_DATOS)
        assertFalse(n.estudiosEnMisDatos || n.enfocarEstudios)
    }
}
