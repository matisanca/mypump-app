package com.pumpteam.mypump.acceso

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.FormatoToken
import com.pumpteam.mypump.datos.ModeloApp
import com.pumpteam.mypump.diseno.Aviso
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MarcaMyPump
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.diseno.fondoMarca
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import kotlinx.coroutines.launch

const val URL_PRIVACIDAD = "https://app.mypumpteam.com/privacidad.html"
const val URL_BORRADO = "https://app.mypumpteam.com/eliminar-datos.html"

/**
 * "Bienvenido a MyPump" (index.html:376-423 + cliente.html:3415-3484, AccesoView.swift): se entra con el link personal que
 * manda Mati (por App Link se abre solo; si no, se pega acá, entero, a medias o el token solo), o se mira la demo. Con un
 * token que ya no sirve explica qué pasó y deja pegar uno nuevo (ACC-03, ACC-04).
 */
@Composable
fun AccesoPantalla(modelo: ModeloApp, alVerDemo: () -> Unit) {
    val fase by modelo.fase.collectAsStateWithLifecycle()
    var texto by rememberSaveable { mutableStateOf("") }
    var entrando by remember { mutableStateOf(false) }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    val alcance = LocalAlcanceApp.current
    val alcancePantalla = rememberCoroutineScope()
    val foco = LocalFocusManager.current
    val teclado = LocalSoftwareKeyboardController.current
    val haptico = LocalHapticFeedback.current
    val portapapeles = LocalClipboard.current
    val contexto = LocalContext.current
    val c = MyPump.colores

    fun entrar(t: String) {
        if (entrando) return
        foco.clearFocus()
        teclado?.hide()
        if (FormatoToken.extraer(t) == null) {
            error = "No reconocí ese link. Copialo entero de WhatsApp y pegalo de nuevo."
            haptico.performHapticFeedback(HapticFeedbackType.Reject)
            return
        }
        error = null
        entrando = true
        alcance.launch {
            val ok = try {
                modelo.entrar(t)
            } finally {
                entrando = false
            }
            if (!ok) {
                error = when (modelo.fase.value) {
                    ModeloApp.Fase.TOKEN_INVALIDO -> null   // lo explica el aviso de arriba
                    ModeloApp.Fase.SIN_SERVICIO -> "Sin conexión. Probá de nuevo cuando tengas señal."
                    else -> "No pudimos entrar. Probá de nuevo."
                }
                haptico.performHapticFeedback(HapticFeedbackType.Reject)
            }
        }
    }

    // El botón de pegar: lo que haya copiado y, si es un link, entra (como el PasteButton de iOS).
    fun pegar() {
        alcancePantalla.launch {
            val pegado = try {
                portapapeles.getClipEntry()?.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(contexto)?.toString()
            } catch (_: Exception) {
                null
            }
            if (pegado.isNullOrBlank()) {
                error = "No hay nada copiado. Copiá el link de WhatsApp y volvé a tocar pegar."
                return@launch
            }
            texto = pegado.trim()
            entrar(pegado)
        }
    }

    Box(Modifier.fillMaxSize().fondoMarca().testTag("bienvenida")) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .systemBarsPadding()
                .imePadding()
                .padding(horizontal = 24.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = Modifier.widthIn(max = 520.dp).fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(28.dp),
            ) {
                Spacer(Modifier.height(8.dp))
                MarcaMyPump()
                AnimatedVisibility(
                    visible = fase == ModeloApp.Fase.TOKEN_INVALIDO,
                    enter = fadeIn() + expandVertically(),
                    exit = fadeOut() + shrinkVertically(),
                ) {
                    Aviso(
                        icono = Iconos.Link,
                        titulo = "Este link ya no sirve",
                        texto = "Pedile a Mati un link nuevo y pegalo acá abajo.",
                        modifier = Modifier.testTag("link-vencido"),
                    )
                }
                Tarjeta(relleno = 20.dp, espaciado = 14.dp) {
                    Text("Entrá con tu link", style = TextStyle(fontSize = 20.sp, lineHeight = 25.sp, fontWeight = FontWeight.SemiBold), color = c.texto)
                    Text(
                        "Abrí el link que te pasó Mati por WhatsApp. Si no se abre solo, copialo y pegalo acá.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = c.textoSecundario,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        TextField(
                            value = texto,
                            onValueChange = { texto = it },
                            placeholder = { Text("app.mypumpteam.com/?t=…", maxLines = 1) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(
                                capitalization = KeyboardCapitalization.None,
                                autoCorrectEnabled = false,
                                keyboardType = KeyboardType.Uri,
                                imeAction = ImeAction.Go,
                            ),
                            keyboardActions = KeyboardActions(onGo = { entrar(texto) }),
                            shape = RoundedCornerShape(12.dp),
                            colors = TextFieldDefaults.colors(
                                focusedContainerColor = c.campo,
                                unfocusedContainerColor = c.campo,
                                disabledContainerColor = c.campo,
                                focusedIndicatorColor = Color.Transparent,
                                unfocusedIndicatorColor = Color.Transparent,
                                disabledIndicatorColor = Color.Transparent,
                                cursorColor = c.marcaTexto,
                                focusedPlaceholderColor = c.textoTerciario,
                                unfocusedPlaceholderColor = c.textoTerciario,
                            ),
                            modifier = Modifier.weight(1f).heightIn(min = 52.dp).testTag("campo-link"),
                        )
                        FilledTonalIconButton(
                            onClick = ::pegar,
                            shape = RoundedCornerShape(12.dp),
                            colors = IconButtonDefaults.filledTonalIconButtonColors(containerColor = c.marcaSuave, contentColor = c.marcaTexto),
                            modifier = Modifier.size(52.dp).testTag("pegar"),
                        ) {
                            Icon(Iconos.Pegar, contentDescription = "Pegar el link")
                        }
                    }
                    val e = error
                    if (e != null) {
                        Row(
                            modifier = Modifier.fillMaxWidth().semantics { liveRegion = LiveRegionMode.Polite }.testTag("error-link"),
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(Iconos.Error, contentDescription = null, tint = c.peligro, modifier = Modifier.size(18.dp))
                            Text(e, style = MaterialTheme.typography.bodySmall, color = c.peligro)
                        }
                    }
                    BotonMarca(
                        texto = "Entrar",
                        alTocar = { entrar(texto) },
                        habilitado = texto.isNotBlank(),
                        cargando = entrando,
                        modifier = Modifier.testTag("entrar"),
                    )
                }
                TextButton(onClick = alVerDemo, modifier = Modifier.testTag("ver-demo")) {
                    Text(
                        buildAnnotatedString {
                            withStyle(SpanStyle(color = c.textoSecundario)) { append("¿Querés ver cómo funciona? ") }
                            withStyle(SpanStyle(color = c.marcaTexto, fontWeight = FontWeight.SemiBold)) { append("Ver demo") }
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                TextButton(onClick = { abrirEnNavegador(contexto, URL_PRIVACIDAD) }) {
                    Text("Política de privacidad", style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
                }
            }
        }
    }
}
