package com.pumpteam.mypump.fotos

import android.content.ActivityNotFoundException
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.foundation.clickable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Elegir una foto (gemelo de `BotonFoto` de iOS): sacarla con la cámara del teléfono, si tiene, o elegirla de la galería
 * con el selector de fotos del sistema (no pide permisos: el cliente elige una y MyPump ve solo esa). Lo que recibe
 * [alElegir] ya es el JPEG reducido ([ReduccionFoto]: lado mayor ≤ [maxPx], [calidad], derecho y sin metadatos).
 *
 * En iOS un toque abre la cámara y uno largo el menú; acá un toque abre el menú con las dos, porque en Android nadie
 * espera un toque largo. Sin app de cámara, va directo a la galería. Una foto que no se puede leer (un formato raro, una
 * foto de la nube que no bajó) se avisa, como la web.
 *
 * [clave] distingue los botones de una misma pantalla (la pose): cada uno tiene su archivo para la cámara, así la foto
 * se encuentra aunque Android haya cerrado MyPump mientras el cliente sacaba la foto.
 */
@Composable
fun BotonFoto(
    clave: String,
    maxPx: Int,
    calidad: Double,
    alElegir: (ByteArray) -> Unit,
    modifier: Modifier = Modifier,
    habilitado: Boolean = true,
    contenido: @Composable () -> Unit,
) {
    val contexto = LocalContext.current
    val alcance = LocalAlcanceApp.current
    val alElegirAhora by rememberUpdatedState(alElegir)
    var menu by remember { mutableStateOf(false) }
    var ilegible by rememberSaveable { mutableStateOf(false) }
    val hayCamara = remember { contexto.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }

    // En el alcance de la app: si el cliente cambia de pestaña mientras se reduce, la foto no se pierde.
    fun procesar(uri: Uri, temporal: File?) {
        val resolver = contexto.contentResolver
        alcance.launch {
            val jpeg = withContext(Dispatchers.Default) { ReduccionFoto.jpeg(resolver, uri, maxPx, calidad) }
            temporal?.delete()
            if (jpeg != null) alElegirAhora(jpeg) else ilegible = true
        }
    }

    val galeria = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) procesar(uri, null)
    }
    val camara = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val archivo = ProveedorFotos.archivo(contexto, clave)
        if (ok && archivo.length() > 0) procesar(ProveedorFotos.uri(contexto, archivo), archivo) else archivo.delete()
    }

    fun abrirGaleria() {
        galeria.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    fun abrirCamara() {
        val (archivo, uri) = ProveedorFotos.paraLaCamara(contexto, clave)
        try {
            camara.launch(uri)
        } catch (_: ActivityNotFoundException) {
            // Un teléfono con cámara pero sin app que la abra: la galería.
            archivo.delete()
            abrirGaleria()
        }
    }

    Box(modifier) {
        // "Presioná dos veces para sacar la foto o elegirla de la galería" (el hint de iOS).
        Box(Modifier.clickable(enabled = habilitado, role = Role.Button, onClickLabel = "sacar la foto o elegirla de la galería") { menu = true }) {
            contenido()
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            if (hayCamara) {
                DropdownMenuItem(
                    text = { Text("Sacar foto") },
                    leadingIcon = { Icon(Iconos.Camara, contentDescription = null, modifier = Modifier.size(20.dp)) },
                    onClick = {
                        menu = false
                        abrirCamara()
                    },
                    modifier = Modifier.testTag("sacar-foto"),
                )
            }
            DropdownMenuItem(
                text = { Text("Elegir de la galería") },
                leadingIcon = { Icon(Galeria, contentDescription = null, modifier = Modifier.size(20.dp)) },
                onClick = {
                    menu = false
                    abrirGaleria()
                },
                modifier = Modifier.testTag("elegir-de-la-galeria"),
            )
        }
    }

    if (ilegible) {
        AlertDialog(
            onDismissRequest = { ilegible = false },
            title = { Text("No se pudo leer esa foto") },
            text = { Text("Probá con otra, o sacala con la cámara.") },
            confirmButton = {
                TextButton(onClick = { ilegible = false }, modifier = Modifier.testTag("foto-ilegible-ok")) {
                    Text("OK", color = MyPump.colores.marcaTexto)
                }
            },
            containerColor = MyPump.colores.tarjeta,
        )
    }
}

/** photo_library (Material Icons, Apache 2.0): "Elegir de la galería". */
private val Galeria: ImageVector by lazy {
    ImageVector.Builder(name = "Galeria", defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .apply {
            addPath(
                pathData = addPathNodes(
                    "M22,16V4c0,-1.1 -0.9,-2 -2,-2H8c-1.1,0 -2,0.9 -2,2v12c0,1.1 0.9,2 2,2h12c1.1,0 2,-0.9 2,-2zM11,12l2.03,2.71L16,11l4,5H8l3,-4zM2,6v14c0,1.1 0.9,2 2,2h14v-2H4V6H2z",
                ),
                fill = SolidColor(Color.Black),
            )
        }
        .build()
}
