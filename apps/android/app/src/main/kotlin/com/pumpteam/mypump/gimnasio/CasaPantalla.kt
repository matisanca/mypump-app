package com.pumpteam.mypump.gimnasio

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.pumpteam.mypump.datos.ModeloCasa
import com.pumpteam.mypump.diseno.BotonMarca
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.Interruptor
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.Separador
import com.pumpteam.mypump.diseno.Tarjeta
import com.pumpteam.mypump.diseno.superficieTarjeta
import com.pumpteam.mypump.raiz.LocalAlcanceApp
import com.pumpteam.mypump.reglas.Casa
import com.pumpteam.mypump.reglas.Casa.Textos as T
import com.pumpteam.mypump.reglas.TipoCasa
import kotlinx.coroutines.launch

// Entrenar en casa (2.3.0, palanca `casa`; contrato `cola-b/CONTRATO_APP.md`, sección 3): el interruptor arriba de todo en
// «Mi gimnasio», la lista para marcar (la da el servidor: acá no hay ninguna escrita) y la vigente de casa. Regla de Mati:
// filas grandes, botones con texto y que ande con la letra más grande.

/** «Entreno en casa»: toda la fila lo mueve. Mientras contesta el servidor muestra a dónde va; si falla, vuelve y avisa. */
@Composable
internal fun InterruptorCasa(casa: ModeloCasa) {
    val estado by casa.estado.collectAsStateWithLifecycle()
    val e = estado ?: return
    val moviendoA by casa.moviendoA.collectAsStateWithLifecycle()
    val aviso by casa.aviso.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    val c = MyPump.colores
    val i = Casa.interruptor(e)
    val prendido = moviendoA ?: i.prendido
    val sePuede = i.sePuedeMover && moviendoA == null
    Column(Modifier.fillMaxWidth().superficieTarjeta()) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .toggleable(value = prendido, enabled = sePuede, role = Role.Switch, onValueChange = { a -> alcance.launch { casa.mover(a) } })
                .padding(Espacio.m)
                .testTag("casa-interruptor"),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(T.INTERRUPTOR, style = MaterialTheme.typography.titleMedium, color = c.texto)
                Text(
                    if (i.sePuedeMover) T.INTERRUPTOR_AYUDA else T.YA_RECIBIDO,
                    style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario,
                )
            }
            Interruptor(prendido, alCambiar = null, habilitado = sePuede)
        }
        if (aviso == ModeloCasa.Aviso.NO_SE_PUDO_CAMBIAR) {
            NotaGimnasio(T.ERROR_CAMBIAR, Modifier.padding(horizontal = Espacio.m).padding(bottom = Espacio.m).testTag("casa-error"), alerta = true)
        }
    }
}

/** Un borrador de casa: la lista para marcar, en lugar de las zonas con fotos. */
@Composable
internal fun CasaLista(casa: ModeloCasa, relleno: PaddingValues) {
    val estado by casa.estado.collectAsStateWithLifecycle()
    val e = estado ?: return
    val b by casa.borrador.collectAsStateWithLifecycle()
    val enviando by casa.enviando.collectAsStateWithLifecycle()
    val aviso by casa.aviso.collectAsStateWithLifecycle()
    val alcance = LocalAlcanceApp.current
    val c = MyPump.colores
    Desplazable(relleno) {
        Column(Modifier.testTag("casa-lista"), verticalArrangement = Arrangement.spacedBy(Espacio.m)) {
            Column(verticalArrangement = Arrangement.spacedBy(Espacio.xxs)) {
                Text(T.LISTA_TITULO, style = MaterialTheme.typography.titleLarge, color = c.texto, modifier = Modifier.semantics { heading() })
                Text(T.LISTA_TEXTO, style = MaterialTheme.typography.bodyLarge, color = c.textoSecundario)
            }
            Tarjeta(relleno = 0.dp, espaciado = 0.dp) {
                e.tipos.forEachIndexed { n, t ->
                    if (n > 0) Separador(sangria = Espacio.m)
                    // La clave incluye la carga: al abrir otra, lo escrito en los kilos de la anterior no queda en el campo.
                    key(b.gimnasioId, t.tipo) {
                        FilaTipo(
                            t, marcado = t.tipo in b.marcados, kilos = b.kilos[t.tipo].orEmpty(), habilitado = !enviando,
                            alMarcar = { casa.marcar(t.tipo, it) }, alEscribirKilos = { casa.fijarKilos(t.tipo, it) },
                        )
                    }
                }
                if (e.tipos.isNotEmpty()) Separador(sangria = Espacio.m)
                FilaCasilla(T.SIN_EQUIPO, b.sinEquipo, "casa-sin-equipo", habilitado = !enviando) { casa.marcarSinEquipo(it) }
            }
        }
        key(b.gimnasioId) {
            CampoCasa(
                rotulo = T.NOTA, inicial = b.nota, alCambiar = casa::fijarNota, etiqueta = "casa-nota", habilitado = !enviando,
                acepta = { it.length <= Casa.MAX_NOTA }, minLineas = 2, maxLineas = 6,
                teclado = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
        }
        when (aviso) {
            ModeloCasa.Aviso.NO_SE_PUDO_ENVIAR -> NotaGimnasio(T.ERROR_ENVIAR, Modifier.testTag("casa-error"), alerta = true)
            ModeloCasa.Aviso.SIN_DATOS -> NotaGimnasio(T.SIN_DATOS, Modifier.testTag("casa-sin-datos"), alerta = true)
            else -> Unit
        }
        BotonMarca(
            T.ENVIAR,
            alTocar = { alcance.launch { casa.enviar() } },
            habilitado = Casa.puedeEnviar(b.marcados, b.sinEquipo, e.tipos),
            cargando = enviando,
            modifier = Modifier.testTag("casa-enviar"),
        )
    }
}

/** Una fila grande con casilla y nombre; si lleva kilos y está marcada, el campo debajo. */
@Composable
private fun FilaTipo(t: TipoCasa, marcado: Boolean, kilos: String, habilitado: Boolean, alMarcar: (Boolean) -> Unit, alEscribirKilos: (String) -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        FilaCasilla(t.nombre, marcado, "casa-tipo-${t.tipo}", habilitado, alMarcar)
        if (t.kg && marcado) {
            CampoCasa(
                rotulo = T.KILOS, inicial = kilos, alCambiar = alEscribirKilos, etiqueta = "casa-kg-${t.tipo}", habilitado = habilitado,
                acepta = Casa::kilosEscribibles, teclado = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                modifier = Modifier.padding(horizontal = Espacio.m).padding(bottom = Espacio.m),
            )
        }
    }
}

@Composable
private fun FilaCasilla(texto: String, marcada: Boolean, etiqueta: String, habilitado: Boolean, alMarcar: (Boolean) -> Unit) {
    val c = MyPump.colores
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 60.dp)
            .toggleable(value = marcada, enabled = habilitado, role = Role.Checkbox, onValueChange = alMarcar)
            .padding(horizontal = Espacio.m, vertical = Espacio.s)
            .testTag(etiqueta),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Marca(marcada)
        Text(texto, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.weight(1f))
    }
}

/** Un campo con su rótulo siempre a la vista, arriba (nunca solo como marcador que se va al escribir). */
@Composable
private fun CampoCasa(
    rotulo: String,
    inicial: String,
    alCambiar: (String) -> Unit,
    etiqueta: String,
    habilitado: Boolean,
    acepta: (String) -> Boolean,
    modifier: Modifier = Modifier,
    minLineas: Int = 1,
    maxLineas: Int = 1,
    teclado: KeyboardOptions = KeyboardOptions.Default,
) {
    val c = MyPump.colores
    var texto by remember { mutableStateOf(inicial) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Espacio.xs)) {
        Text(rotulo, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario)
        BasicTextField(
            value = texto,
            onValueChange = {
                if (acepta(it)) {
                    texto = it
                    alCambiar(it)
                }
            },
            enabled = habilitado,
            minLines = minLineas,
            maxLines = maxLineas,
            singleLine = maxLineas == 1,
            keyboardOptions = teclado,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.texto),
            cursorBrush = SolidColor(c.marcaTexto),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = rotulo }.testTag(etiqueta),
            decorationBox = { campo ->
                Box(Modifier.heightIn(min = 52.dp).background(c.campo, RoundedCornerShape(Radio.control)).padding(Espacio.s), contentAlignment = Alignment.CenterStart) { campo() }
            },
        )
    }
}

/** La vigente es de casa: lo que tiene y «Cambió lo que tengo en casa». Acá no van «Falta algo», «Esto ya no está» ni las zonas. */
@Composable
internal fun CasaVigente(casa: ModeloCasa, relleno: PaddingValues) {
    val estado by casa.estado.collectAsStateWithLifecycle()
    val e = estado ?: return
    val v = e.vigente ?: return
    val alcance = LocalAlcanceApp.current
    val c = MyPump.colores
    var cambiando by remember { mutableStateOf(false) }
    Desplazable(relleno) {
        Column(Modifier.testTag("casa-vigente"), verticalArrangement = Arrangement.spacedBy(Espacio.s)) {
            Text(T.VIGENTE_TITULO, style = MaterialTheme.typography.titleLarge, color = c.texto, modifier = Modifier.semantics { heading() })
            if (v.sinEquipo) {
                Text(T.VIGENTE_SIN_EQUIPO, style = MaterialTheme.typography.bodyLarge, color = c.texto, modifier = Modifier.testTag("casa-vigente-sin-equipo"))
            } else if (v.equipos.isNotEmpty()) {
                Tarjeta(espaciado = Espacio.s) {
                    for (eq in v.equipos) Text(Casa.renglonVigente(eq, e.tipos), style = MaterialTheme.typography.bodyLarge, color = c.texto)
                }
            }
        }
        BotonMarca(
            T.CAMBIAR,
            alTocar = {
                cambiando = true
                alcance.launch {
                    try {
                        casa.cambiar()
                    } finally {
                        cambiando = false
                    }
                }
            },
            cargando = cambiando,
            modifier = Modifier.testTag("casa-cambiar"),
        )
    }
}
