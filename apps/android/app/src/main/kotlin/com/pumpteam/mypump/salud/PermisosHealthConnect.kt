package com.pumpteam.mypump.salud

import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContract
import androidx.annotation.MainThread
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * La hoja de permisos de Health Connect como una llamada `suspend` desde cualquier lado (la hoja de la primera vez, Mis
 * datos, la tarjeta de Recuperación). El contrato (`PermissionController.createRequestPermissionResultContract()`) se
 * registra en la MainActivity al crearse, porque Android no deja registrarlo después; acá queda el puente hasta la
 * espera:
 *
 * - Una sola hoja a la vez: dos pedidos seguidos esperan su turno.
 * - El pedido en vuelo vive acá y no en la Activity: si la pantalla se recrea con la hoja abierta (rotar), la respuesta le
 *   llega al contrato de la Activity nueva (la misma clave) y completa la misma espera.
 * - Sin una pantalla a la vista no se abre nada y tira: una actividad que se inicia desde segundo plano no se muestra, y
 *   la espera quedaría colgada para siempre.
 * - El corte de `ModeloSalud.conectar(limiteMs)` no la cancela: la hoja sigue abierta y la conexión sigue de fondo.
 */
object PermisosHealthConnect {
    /** El de Health Connect: devuelve los permisos que quedaron dados. */
    val contratoHealthConnect: ActivityResultContract<Set<String>, Set<String>> = PermissionController.createRequestPermissionResultContract()

    private var lanzador: ActivityResultLauncher<Set<String>>? = null
    private var ciclo: Lifecycle? = null
    private var pendiente: CompletableDeferred<Set<String>>? = null
    private val turno = Mutex()

    /**
     * Lo llama la MainActivity en `onCreate` (antes de STARTED; Android no deja registrar un contrato después). Al
     * destruirse la Activity se suelta, salvo que ya la haya reemplazado otra. [contrato] cambia solo en las pruebas.
     */
    @MainThread
    fun registrar(actividad: ComponentActivity, contrato: ActivityResultContract<Set<String>, Set<String>> = contratoHealthConnect) {
        val l = actividad.registerForActivityResult(contrato) { dados ->
            pendiente?.complete(dados)
            pendiente = null
        }
        lanzador = l
        ciclo = actividad.lifecycle
        actividad.lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onDestroy(owner: LifecycleOwner) {
                if (lanzador === l) {
                    lanzador = null
                    ciclo = null
                }
            }
        })
    }

    /** Abre la hoja con [permisos] y espera a que el cliente la cierre. Devuelve lo que quedó dado. */
    suspend fun pedir(permisos: Set<String>): Set<String> = turno.withLock {
        withContext(Dispatchers.Main.immediate) {
            val l = lanzador
            val vista = ciclo?.currentState?.isAtLeast(Lifecycle.State.STARTED) == true
            check(l != null && vista) { "no hay una pantalla a la vista para pedir el permiso" }
            val espera = CompletableDeferred<Set<String>>()
            pendiente = espera
            try {
                l.launch(permisos)
                espera.await()
            } finally {
                if (pendiente === espera) pendiente = null
            }
        }
    }
}
