package com.pumpteam.mypump.raiz

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Test

/**
 * La escena es la clave del `Crossfade` de la raíz, y Compose arma con su `hashCode` la clave de todo el estado guardado
 * de la app. Tiene que dar lo mismo en otro proceso: si dependiera de la identidad del enum (el `hashCode` de un data
 * class con un enum adentro), al volver de la cámara después de que Android cerró MyPump no se encontraba nada guardado y
 * la foto se perdía (15-oct, `scripts/nativa/camara-muerte-android.py`).
 */
class EscenaTest {
    @Test
    fun suHashSaleDelNombreDelDestinoYDeLaCuentaNoDeLaIdentidadDelEnum() {
        for (d in Destino.entries) {
            assertEquals(31 * d.name.hashCode() + "token-de-prueba".hashCode(), Escena(d, "token-de-prueba").hashCode(), d.name)
            assertEquals(31 * d.name.hashCode(), Escena(d, null).hashCode(), d.name)
        }
    }

    @Test
    fun igualdadYHashSiguenDeAcuerdo() {
        assertEquals(Escena(Destino.APP, "a"), Escena(Destino.APP, "a"))
        assertEquals(Escena(Destino.APP, "a").hashCode(), Escena(Destino.APP, "a").hashCode())
        assertNotEquals(Escena(Destino.APP, "a"), Escena(Destino.APP, "demo"))
        assertNotEquals(Escena(Destino.APP, null), Escena(Destino.ACCESO, null))
    }
}
