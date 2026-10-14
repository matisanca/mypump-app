package com.pumpteam.mypump.acceso

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import com.pumpteam.mypump.datos.AlmacenToken
import com.pumpteam.mypump.datos.escribirAtomico
import java.io.File
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * El acceso del cliente (el token de su link), cifrado con una clave AES-256-GCM que vive en el Keystore de Android y
 * nunca sale del teléfono. Es el Keychain de iOS (`TokenEnKeychain`), con las mismas reglas:
 *
 * - Se puede leer con el teléfono bloqueado después del primer desbloqueo (la sincronización de salud en segundo plano lo
 *   necesita), así que la clave no pide autenticación ni pantalla desbloqueada.
 * - El archivo va en `noBackupFilesDir`: no viaja en la copia de Google ni en el pase a otro teléfono, y además las
 *   reglas de backup excluyen la carpeta de la cuenta. Restaurar un token en otro teléfono sería entrar a una cuenta sin
 *   el link.
 * - Si la clave del Keystore no está (se borró, se restauró el archivo sin ella, el Keystore se rompió) o el archivo no se
 *   puede descifrar, no hay token: la app muestra "pegá tu link". El archivo huérfano se borra.
 *
 * Formato: `[versión=1][IV de 12 bytes][texto cifrado + etiqueta de 16]`, con el alias como dato asociado (un archivo de
 * otra clave o de otra versión no se descifra por accidente).
 */
class TokenEnKeystore(
    private val archivo: File,
    private val alias: String = ALIAS,
) : AlmacenToken {
    @Synchronized
    override fun leer(): String? {
        if (!archivo.isFile) return null
        val datos = try {
            archivo.readBytes()
        } catch (_: IOException) {
            return null
        }
        val clave = claveExistente()
        if (clave == null) {
            // Sin la clave el archivo no sirve para nada: "pegá tu link".
            archivo.delete()
            return null
        }
        return try {
            descifrar(clave, datos)
        } catch (_: GeneralSecurityException) {
            archivo.delete()
            null
        } catch (_: IllegalArgumentException) {
            archivo.delete()
            null
        }
    }

    @Synchronized
    override fun guardar(token: String?) {
        if (token == null) {
            archivo.delete()
            return
        }
        try {
            val clave = claveExistente() ?: crearClave()
            if (!escribirAtomico(archivo, cifrar(clave, token))) archivo.delete()
        } catch (_: GeneralSecurityException) {
            // Sin Keystore no se guarda en claro: el token queda en memoria hasta cerrar la app y después se pide el link.
            archivo.delete()
        }
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVEEDOR).apply { load(null) }

    private fun claveExistente(): SecretKey? = try {
        keyStore().getKey(alias, null) as? SecretKey
    } catch (_: GeneralSecurityException) {
        null
    } catch (_: IOException) {
        null
    }

    private fun crearClave(): SecretKey {
        val generador = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVEEDOR)
        generador.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generador.generateKey()
    }

    private fun cifrar(clave: SecretKey, token: String): ByteArray {
        val c = Cipher.getInstance(TRANSFORMACION)
        c.init(Cipher.ENCRYPT_MODE, clave)   // el Keystore elige el IV (no deja reusar uno propio)
        c.updateAAD(alias.toByteArray())
        val cifrado = c.doFinal(token.toByteArray(Charsets.UTF_8))
        val iv = c.iv
        require(iv.size == LARGO_IV) { "IV de ${iv.size} bytes" }
        return byteArrayOf(VERSION) + iv + cifrado
    }

    private fun descifrar(clave: SecretKey, datos: ByteArray): String {
        require(datos.size > 1 + LARGO_IV && datos[0] == VERSION) { "formato desconocido" }
        val c = Cipher.getInstance(TRANSFORMACION)
        c.init(Cipher.DECRYPT_MODE, clave, GCMParameterSpec(128, datos, 1, LARGO_IV))
        c.updateAAD(alias.toByteArray())
        return c.doFinal(datos, 1 + LARGO_IV, datos.size - 1 - LARGO_IV).toString(Charsets.UTF_8)
    }

    companion object {
        const val ALIAS = "com.pumpteam.mypump.acceso"
        const val ARCHIVO = "acceso.bin"
        private const val PROVEEDOR = "AndroidKeyStore"
        private const val TRANSFORMACION = "AES/GCM/NoPadding"
        private const val LARGO_IV = 12
        private const val VERSION: Byte = 1
    }
}
