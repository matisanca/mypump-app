package com.pumpteam.mypump.presion

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloPresion
import com.pumpteam.mypump.datos.TensiometrosPresion
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.reglas.Presion
import kotlinx.coroutines.launch

private val CLAVES_TRAMOS = listOf("estandar", "grande", "extra_grande", "mas_52")

/**
 * La barra de talles (GRAFICOS.md, G3): cuatro tramos y un marcador en la medida del alumno. Sin colores de riesgo: el tramo
 * propio se marca con el relleno del texto y un tilde.
 */
@Composable
internal fun BarraTallesPresion(cm: Double?) {
    val c = MyPump.colores
    val tramo = Presion.tramoBrazo(cm)
    // Dónde cae la medida a lo ancho: de 22 a 52 cm ocupa los tres primeros tramos; más de 52, el medio del último.
    val fraccion: Float? = when {
        cm == null || cm <= 0 -> null
        cm > 52 -> 0.875f
        else -> ((cm - 22).coerceIn(0.0, 30.0) / 40.0).toFloat()
    }
    Column(Modifier.fillMaxWidth().testTag("presion-talles"), verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        if (fraccion != null && cm != null) {
            BoxWithConstraints(Modifier.fillMaxWidth().clearAndSetSemantics { }) {
                val densidad = LocalDensity.current
                var anchoMarca by remember { mutableStateOf(0) }
                val mitad = with(densidad) { (anchoMarca / 2).toDp() }
                val x = (maxWidth * fraccion - mitad).coerceIn(0.dp, (maxWidth - mitad * 2).coerceAtLeast(0.dp))
                Column(Modifier.offset(x = x).onSizeChanged { anchoMarca = it.width }, horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${NumeroPresion.texto(cm)} ${NP.cm}", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = c.texto, maxLines = 1)
                    Text("▼", style = MaterialTheme.typography.labelSmall, color = c.texto)
                }
            }
        }
        Row(Modifier.fillMaxWidth().clip(CircleShape).clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            for (k in CLAVES_TRAMOS) Box(Modifier.weight(1f).height(14.dp).background(if (k == tramo) c.texto else c.textoSecundario.copy(alpha = 0.3f)))
        }
        // Desde los 42 cm, la marca aparte (D3).
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            Box(Modifier.weight(1f).height(2.dp))
            Box(Modifier.weight(1f).height(2.dp).background(c.textoSecundario))
        }
        Text(TP.marca42, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth())
        Column(verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
            for (k in CLAVES_TRAMOS) {
                val mio = k == tramo
                val peso = if (mio) FontWeight.Bold else FontWeight.Normal
                val nombre = TP.tramos[k] ?: ""
                val rango = TP.tramosRango[k] ?: ""
                Row(
                    Modifier.fillMaxWidth().clearAndSetSemantics {
                        contentDescription = "$nombre. $rango"
                        selected = mio
                    },
                    horizontalArrangement = Arrangement.spacedBy(Espacio.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(18.dp)) { if (mio) Icon(Iconos.Tilde, contentDescription = null, tint = c.texto, modifier = Modifier.size(18.dp)) }
                    // Con letra grande el nombre y el rango no entran lado a lado: van uno abajo del otro.
                    if (letraGrande()) {
                        Column(Modifier.weight(1f)) {
                            Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = peso, color = c.texto)
                            Text(rango, style = MaterialTheme.typography.bodyMedium, fontWeight = peso, color = if (mio) c.texto else c.textoSecundario)
                        }
                    } else {
                        Text(nombre, style = MaterialTheme.typography.bodyMedium, fontWeight = peso, color = c.texto, modifier = Modifier.weight(1f))
                        Text(rango, style = MaterialTheme.typography.bodyMedium, fontWeight = peso, color = if (mio) c.texto else c.textoSecundario)
                    }
                }
            }
        }
    }
}

/** «Ver cuáles sirven»: la lista verificada para su tramo. Solo existe si el servidor mandó la lista. */
@Composable
internal fun ListaTensiometrosPresion(lista: TensiometrosPresion, tramo: String, alCerrar: () -> Unit) {
    BackHandler(onBack = alCerrar)
    MarcoPresion(TP.verCuales, NP.volver, alCerrar, etiqueta = "presion-lista", etiquetaSalir = "presion-lista-volver") {
        TP.porTramo[tramo]?.let { TextoPresion(it) }
        val aparatos = lista.tramos[tramo] ?: emptyList()
        if (aparatos.isEmpty()) TextoPresion(NP.sinLista, Modifier.testTag("presion-sin-lista"), secundario = true)
        for (a in aparatos) {
            Tarjeta(espaciado = 2.dp) {
                TextoPresion(a.nombre, estilo = MaterialTheme.typography.titleMedium, fuerte = true)
                a.codigo?.takeIf { it.isNotEmpty() }?.let { TextoPresion(it, estilo = MaterialTheme.typography.bodyMedium) }
                a.nota?.takeIf { it.isNotEmpty() }?.let { TextoPresion(it, estilo = MaterialTheme.typography.bodyMedium, secundario = true) }
            }
        }
    }
}

internal enum class ModoAparato { PRIMERA, CAMBIAR, MEDIR_DE_NUEVO }

/** «Antes de la primera serie» (sin aparato), cambiar de aparato y «medir de nuevo» (lo pide la serie). */
@Composable
internal fun AparatoPresionPantalla(
    modelo: ModeloPresion,
    modo: ModoAparato,
    alSalir: () -> Unit,
    alGuardar: () -> Unit = {},
    /** «Marcar un síntoma» tiene que estar siempre a mano, también antes de tener aparato. */
    alMarcarSintoma: (() -> Unit)? = null,
) {
    val estado by modelo.estado.collectAsStateWithLifecycle()
    val alcance = rememberCoroutineScope()
    val inicial = remember { modelo.estado.value }
    // «Medir de nuevo» arranca vacío: la medida vieja no vale para esta serie.
    var medida by rememberSaveable { mutableStateOf(if (modo == ModoAparato.MEDIR_DE_NUEVO) "" else NumeroPresion.texto(inicial?.circunferenciaBrazoCm)) }
    var tipo by rememberSaveable { mutableStateOf(inicial?.aparato?.tipo) }
    var marca by rememberSaveable { mutableStateOf(inicial?.aparato?.marca ?: "") }
    var modeloAparato by rememberSaveable { mutableStateOf(inicial?.aparato?.modelo ?: "") }
    var codigo by rememberSaveable { mutableStateOf(inicial?.aparato?.modeloCodigo ?: "") }
    var desde by rememberSaveable { mutableStateOf(NumeroPresion.texto(inicial?.aparato?.manguitoMinCm)) }
    var hasta by rememberSaveable { mutableStateOf(NumeroPresion.texto(inicial?.aparato?.manguitoMaxCm)) }
    var guardando by remember { mutableStateOf(false) }
    var fallo by remember { mutableStateOf(false) }
    var verLista by rememberSaveable { mutableStateOf(false) }

    val cmValida = NumeroPresion.decimal(medida)?.takeIf { it in 20.0..70.0 }
    val conDatos = tipo == "brazo" || tipo == "muneca"
    val escrito = Presion.Aparato(
        tipo = tipo, marca = marca, modelo = modeloAparato, modeloCodigo = codigo, manguitoMinCm = NumeroPresion.decimal(desde), manguitoMaxCm = NumeroPresion.decimal(hasta),
    )
    val puedeGuardar = cmValida != null && !guardando && (modo == ModoAparato.MEDIR_DE_NUEVO || tipo != null)
    val tramo = Presion.tramoBrazo(cmValida)
    val lista = estado?.tensiometros

    fun guardar() {
        val cm = cmValida ?: return
        guardando = true
        fallo = false
        alcance.launch {
            try {
                if (modo == ModoAparato.MEDIR_DE_NUEVO || cm != modelo.estado.value?.circunferenciaBrazoCm) {
                    if (modelo.guardarMedida(cm) != ModeloPresion.Salida.OK) {
                        fallo = true
                        return@launch
                    }
                }
                val t = tipo
                if (modo != ModoAparato.MEDIR_DE_NUEVO && t != null && t != "ninguno") {
                    val a = if (conDatos) escrito else Presion.Aparato(tipo = t)
                    val v = modelo.estado.value?.aparato
                    val igual = v?.tipo == a.tipo && (v?.marca ?: "") == (a.marca?.trim() ?: "") && (v?.modelo ?: "") == (a.modelo?.trim() ?: "") &&
                        (v?.modeloCodigo ?: "") == (a.modeloCodigo?.trim() ?: "") && v?.manguitoMinCm == a.manguitoMinCm && v?.manguitoMaxCm == a.manguitoMaxCm
                    if (!igual && modelo.guardarAparato(a) != ModeloPresion.Salida.OK) {
                        fallo = true
                        return@launch
                    }
                }
                alGuardar()
            } finally {
                guardando = false
            }
        }
    }

    if (verLista && lista != null && tramo != null) {
        ListaTensiometrosPresion(lista, tramo, alCerrar = { verLista = false })
        return
    }
    MarcoPresion(
        titulo = if (modo == ModoAparato.CAMBIAR) NP.aparato else NP.titulo,
        salir = if (modo == ModoAparato.CAMBIAR) NP.volver else NP.cerrar,
        alSalir = alSalir,
        etiqueta = "presion-aparato-pantalla",
        pie = {
            if (fallo) TextoPresion(NP.noGuardo, Modifier.testTag("presion-no-guardo"), estilo = MaterialTheme.typography.bodyMedium, fuerte = true)
            BotonPresion(NP.guardar, "presion-guardar", habilitado = puedeGuardar, cargando = guardando) { guardar() }
        },
    ) {
        if (modo == ModoAparato.PRIMERA) {
            TituloPresion(NP.antesTitulo)
            // El paso 4 pide fotos: sin esa función en el servidor no se muestra.
            Tarjeta(Modifier.testTag("presion-antes")) { PasosPresion(if (estado?.fotos == true) TP.antes else TP.antes.take(3)) }
        }
        if (modo == ModoAparato.MEDIR_DE_NUEVO) TextoPresion(TP.medirDeNuevo, Modifier.testTag("presion-medir-de-nuevo"), estilo = MaterialTheme.typography.titleMedium, fuerte = true)
        if (modo != ModoAparato.CAMBIAR) {
            TituloPresion(NP.medirBrazoTitulo)
            LaminaPresion("presion_g3_medir_brazo", TP.g3Alt, TP.g3)
            Tarjeta { PasosPresion(TP.medirBrazo) }
        }
        Tarjeta(espaciado = Espacio.m) {
            CampoPresion(NP.medida, medida, "presion-medida", teclado = KeyboardType.Decimal, grande = true, accion = ImeAction.Done, largoMaximo = 5) { medida = it }
            BarraTallesPresion(cmValida)
            // Sin la lista verificada no hay «Ver cuáles sirven».
            if (lista != null && tramo != null && tramo != "menos_22") BotonPresionSecundario(TP.verCuales, "presion-ver-cuales") { verLista = true }
        }
        if (modo != ModoAparato.MEDIR_DE_NUEVO) {
            Tarjeta {
                TituloPresion(NP.tipoAparato)
                for (k in listOf("brazo", "muneca", "reloj_anillo_otro", "ninguno")) {
                    val elegido = tipo == k
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .selectable(selected = elegido, role = Role.RadioButton, onClick = { tipo = k })
                            .testTag("presion-tipo-$k"),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
                    ) {
                        val c = MyPump.colores
                        Icon(if (elegido) Iconos.TildeEnCirculo else Iconos.Circulo, contentDescription = null, tint = if (elegido) c.marcaTexto else c.textoSecundario, modifier = Modifier.size(26.dp))
                        TextoPresion(NP.tipos[k] ?: k, Modifier.weight(1f))
                    }
                }
                if (tipo == "reloj_anillo_otro") TextoPresion(NP.relojNoSirve, Modifier.testTag("presion-reloj-no-sirve"), estilo = MaterialTheme.typography.bodyMedium, fuerte = true)
            }
            if (conDatos) {
                Tarjeta(espaciado = Espacio.m) {
                    CampoPresion(NP.marca, marca, "presion-marca") { marca = it }
                    CampoPresion(NP.modelo, modeloAparato, "presion-modelo") { modeloAparato = it }
                    CampoPresion(NP.codigo, codigo, "presion-codigo", mayusculas = true, ayuda = NP.codigoAyuda) { codigo = it }
                    Text(NP.rango, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = MyPump.colores.texto)
                    if (letraGrande()) {
                        CampoPresion(NP.desde, desde, "presion-rango-desde", teclado = KeyboardType.Decimal, largoMaximo = 5) { desde = it }
                        CampoPresion(NP.hasta, hasta, "presion-rango-hasta", teclado = KeyboardType.Decimal, accion = ImeAction.Done, largoMaximo = 5) { hasta = it }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(Espacio.s)) {
                            CampoPresion(NP.desde, desde, "presion-rango-desde", Modifier.weight(1f), teclado = KeyboardType.Decimal, largoMaximo = 5) { desde = it }
                            CampoPresion(NP.hasta, hasta, "presion-rango-hasta", Modifier.weight(1f), teclado = KeyboardType.Decimal, accion = ImeAction.Done, largoMaximo = 5) { hasta = it }
                        }
                    }
                    if (Presion.manguitoCalza(cmValida, escrito) == false) {
                        TextoPresion(TP.fueraDeTalle, Modifier.testTag("presion-fuera-de-talle"), estilo = MaterialTheme.typography.bodyMedium, fuerte = true)
                    }
                }
            }
        }
        if (alMarcarSintoma != null) BotonPresionSecundario(TP.marcarSintoma, "presion-marcar-sintoma", alTocar = alMarcarSintoma)
    }
}
