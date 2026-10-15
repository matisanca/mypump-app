package com.pumpteam.mypump.acceso

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.KeyStore
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * El token con el Keystore de verdad (necesita un emulador o un teléfono: `./gradlew connectedDebugAndroidTest`). Usa un
 * alias y un archivo propios, así no toca la cuenta de quien tenga la app instalada.
 */
@RunWith(AndroidJUnit4::class)
class TokenEnKeystoreTest {
    private val contexto = InstrumentationRegistry.getInstrumentation().targetContext
    private val alias = "com.pumpteam.mypump.acceso.prueba"
    private lateinit var archivo: File

    @Before
    fun preparar() {
        archivo = File(contexto.noBackupFilesDir, "acceso-prueba.bin")
        archivo.delete()
        borrarClave()
    }

    @After
    fun limpiar() {
        archivo.delete()
        borrarClave()
    }

    private fun borrarClave() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.deleteEntry(alias)

    @Test
    fun guardaCifradoYLoLee() {
        val t = TokenEnKeystore(archivo, alias)
        assertNull(t.leer())
        t.guardar("abcdefghij0123456789ABCDEFGHIJ_-")
        assertTrue(archivo.isFile)
        // En el disco no está en claro.
        assertFalse(String(archivo.readBytes(), Charsets.ISO_8859_1).contains("abcdefghij0123456789"))
        assertEquals("abcdefghij0123456789ABCDEFGHIJ_-", t.leer())
        // Otra instancia (la app reabierta) lo lee igual.
        assertEquals("abcdefghij0123456789ABCDEFGHIJ_-", TokenEnKeystore(archivo, alias).leer())
        t.guardar(null)
        assertNull(t.leer())
        assertFalse(archivo.exists())
    }

    @Test
    fun sinLaClaveEsPegaTuLink() {
        val t = TokenEnKeystore(archivo, alias)
        t.guardar("abcdefghij0123456789ABCDEFGHIJ_-")
        borrarClave()   // como un archivo restaurado en un teléfono donde la clave no existe
        assertNull(t.leer())
        assertFalse(archivo.exists())
        // Y se puede volver a entrar con el link.
        t.guardar("ZYXWVUTSRQ0123456789zyxwvutsrq__")
        assertEquals("ZYXWVUTSRQ0123456789zyxwvutsrq__", t.leer())
    }

    /**
     * Lo que mira la Fase L de la migración al adoptar el token (`EjecutorLegado.faseLocal`, revisión del 15-oct): `guardar`
     * no tira, así que lo que no se pudo escribir se tiene que ver al leer de vuelta. Ni un archivo nuevo que no se pudo
     * escribir ni uno que no se pudo reemplazar devuelven el token que se quiso guardar.
     */
    @Test
    fun loQueNoSePudoGuardarNoSeLeeDeVuelta() {
        // Donde tendría que ir la carpeta hay un archivo: no se puede escribir adentro.
        val bloqueo = File(contexto.noBackupFilesDir, "acceso-prueba-bloqueo")
        val carpeta = File(contexto.noBackupFilesDir, "acceso-prueba-carpeta")
        bloqueo.deleteRecursively()
        carpeta.deleteRecursively()
        try {
            bloqueo.writeText("x")
            val nuevo = TokenEnKeystore(File(bloqueo, "acceso.bin"), alias)
            nuevo.guardar("abcdefghij0123456789ABCDEFGHIJ_-")
            assertNull(nuevo.leer())
            // Reemplazar el que había en una carpeta donde ya no se puede escribir: el nuevo no queda.
            carpeta.mkdirs()
            val t = TokenEnKeystore(File(carpeta, "acceso.bin"), alias)
            t.guardar("abcdefghij0123456789ABCDEFGHIJ_-")
            assertEquals("abcdefghij0123456789ABCDEFGHIJ_-", t.leer())
            assertTrue(carpeta.setWritable(false))
            t.guardar("ZYXWVUTSRQ0123456789zyxwvutsrq__")
            assertNotEquals("ZYXWVUTSRQ0123456789zyxwvutsrq__", t.leer())
        } finally {
            carpeta.setWritable(true)
            carpeta.deleteRecursively()
            bloqueo.delete()
        }
    }

    @Test
    fun unArchivoRotoOAjenoNoSeLee() {
        val t = TokenEnKeystore(archivo, alias)
        t.guardar("abcdefghij0123456789ABCDEFGHIJ_-")
        val bytes = archivo.readBytes()
        bytes[bytes.size - 1] = (bytes[bytes.size - 1].toInt() xor 1).toByte()
        archivo.writeBytes(bytes)
        assertNull(t.leer())
        archivo.writeBytes(byteArrayOf(9, 9, 9))
        assertNull(t.leer())
    }
}
