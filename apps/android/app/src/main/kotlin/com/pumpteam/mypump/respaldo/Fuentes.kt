package com.pumpteam.mypump.respaldo

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.pumpteam.mypump.diseno.AccionHoja
import com.pumpteam.mypump.diseno.AsaHoja
import com.pumpteam.mypump.diseno.EncabezadoHoja
import com.pumpteam.mypump.diseno.Espacio
import com.pumpteam.mypump.diseno.FormaHoja
import com.pumpteam.mypump.diseno.Iconos
import com.pumpteam.mypump.diseno.MyPump
import com.pumpteam.mypump.diseno.Radio
import com.pumpteam.mypump.diseno.abrirEnNavegador
import com.pumpteam.mypump.diseno.superficieTarjeta
import kotlinx.coroutines.launch

/**
 * "Respaldo científico" (Apple 1.4.1 y la política de salud de Play, cliente.html:4711-4837, FuentesView.swift): las
 * guías y trabajos en los que se apoyan los números y las recomendaciones, agrupados por la afirmación que respaldan, cada
 * uno con su link y la URL como texto seleccionable, y el aviso legal al final.
 */
object Fuentes {
    data class Fuente(val ref: String, val url: String)

    val grupos: List<Pair<String, List<Fuente>>> = listOf(
        "Cómo se calcula tu objetivo de calorías" to listOf(
            Fuente(
                "Mifflin MD, St Jeor ST, Hill LA, et al. A new predictive equation for resting energy expenditure in healthy individuals. Am J Clin Nutr. 1990;51(2):241-247.",
                "https://pubmed.ncbi.nlm.nih.gov/2305711/",
            ),
            Fuente(
                "National Institutes of Health (NIDDK). Body Weight Planner — modelo de balance energético.",
                "https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner",
            ),
        ),
        "De dónde salen tus carbohidratos y tus grasas" to listOf(
            Fuente(
                "National Academies of Sciences, Engineering, and Medicine (Institute of Medicine). Dietary Reference Intakes for Energy, Carbohydrate, Fiber, Fat, Fatty Acids, Cholesterol, Protein, and Amino Acids. 2005.",
                "https://www.nationalacademies.org/publications/10490",
            ),
            Fuente(
                "Aragon AA, Schoenfeld BJ, Wildman R, et al. International Society of Sports Nutrition position stand: diets and body composition. J Int Soc Sports Nutr. 2017;14:16.",
                "https://pmc.ncbi.nlm.nih.gov/articles/PMC5470183/",
            ),
        ),
        "Cuánta proteína y por qué" to listOf(
            Fuente(
                "Jäger R, Kerksick CM, Campbell BI, et al. International Society of Sports Nutrition position stand: protein and exercise. J Int Soc Sports Nutr. 2017;14:20.",
                "https://pmc.ncbi.nlm.nih.gov/articles/PMC5477153/",
            ),
            Fuente(
                "Thomas DT, Erdman KA, Burke LM. Position of the Academy of Nutrition and Dietetics, Dietitians of Canada, and the American College of Sports Medicine: Nutrition and Athletic Performance. Med Sci Sports Exerc. 2016;48(3):543-568.",
                "https://pubmed.ncbi.nlm.nih.gov/26920240/",
            ),
        ),
        "Elección de alimentos y porciones" to listOf(
            Fuente("Organización Mundial de la Salud. Alimentación sana (nota descriptiva).", "https://www.who.int/news-room/fact-sheets/detail/healthy-diet"),
            Fuente(
                "U.S. Departments of Agriculture and Health and Human Services. Dietary Guidelines for Americans, 2025-2030.",
                "https://odphp.health.gov/our-work/nutrition-physical-activity/dietary-guidelines/current-dietary-guidelines",
            ),
        ),
        "Hidratación" to listOf(
            Fuente(
                "National Academies of Sciences, Engineering, and Medicine (Institute of Medicine). Dietary Reference Intakes for Water, Potassium, Sodium, Chloride, and Sulfate. 2005.",
                "https://www.nationalacademies.org/publications/10925",
            ),
        ),
        "Entrenamiento: intensidad, volumen y progresión" to listOf(
            Fuente(
                "American College of Sports Medicine. Position stand: Progression models in resistance training for healthy adults. Med Sci Sports Exerc. 2009;41(3):687-708.",
                "https://pubmed.ncbi.nlm.nih.gov/19204579/",
            ),
            Fuente(
                "Garber CE, Blissmer B, Deschenes MR, et al. American College of Sports Medicine position stand: Quantity and quality of exercise for developing and maintaining fitness in apparently healthy adults. Med Sci Sports Exerc. 2011;43(7):1334-1359.",
                "https://pubmed.ncbi.nlm.nih.gov/21694556/",
            ),
            Fuente("Organización Mundial de la Salud. Actividad física (nota descriptiva).", "https://www.who.int/news-room/fact-sheets/detail/physical-activity"),
            Fuente("MedlinePlus (U.S. National Library of Medicine). Exercise and Physical Fitness.", "https://medlineplus.gov/exerciseandphysicalfitness.html"),
        ),
        "Guía local (Argentina)" to listOf(
            Fuente(
                "Ministerio de Salud de la Nación. Guías Alimentarias para la Población Argentina (GAPA).",
                "https://www.argentina.gob.ar/sites/default/files/bancos/2020-08/guias-alimentarias-para-la-poblacion-argentina.pdf",
            ),
        ),
    )

    const val INTRO =
        "Tu plan lo arma Mati, que es médico. Estas son las guías y los trabajos publicados en los que se apoyan los números y las recomendaciones que ves acá."

    const val AVISO_LEGAL =
        "MyPump es una herramienta para seguir tu plan de entrenamiento y nutrición, pensada para personas sanas. No es un dispositivo médico y no reemplaza la consulta con un profesional de la salud. Si tenés alguna condición médica, estás embarazada o tomás medicación, consultá con tu médico antes de empezar o de cambiar tu plan, y avisale a Mati para adaptarlo. Si algo te hace sentir mal, pará y consultá."
}

/** La hoja con las 14 fuentes. "Abrir fuente" va al navegador del teléfono. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HojaFuentes(alCerrar: () -> Unit) {
    val hoja = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val alcance = rememberCoroutineScope()
    val contexto = LocalContext.current
    val c = MyPump.colores
    fun cerrar() {
        alcance.launch { hoja.hide() }.invokeOnCompletion { alCerrar() }
    }
    ModalBottomSheet(
        onDismissRequest = alCerrar,
        sheetState = hoja,
        shape = FormaHoja,
        containerColor = c.fondo,
        tonalElevation = 0.dp,
        dragHandle = { AsaHoja() },
        modifier = Modifier.testTag("hoja-fuentes"),
    ) {
        EncabezadoHoja("Respaldo científico", confirmar = AccionHoja("Listo", "fuentes-listo", alTocar = ::cerrar))
        LazyColumn(
            contentPadding = PaddingValues(start = Espacio.m, end = Espacio.m, top = Espacio.xs, bottom = Espacio.xl),
            verticalArrangement = Arrangement.spacedBy(Espacio.s),
        ) {
            item {
                Text(Fuentes.INTRO, style = MaterialTheme.typography.bodyMedium, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.xs))
            }
            for ((titulo, fuentes) in Fuentes.grupos) {
                item(key = titulo) {
                    Text(
                        titulo,
                        style = MaterialTheme.typography.titleSmall,
                        color = c.textoSecundario,
                        modifier = Modifier.padding(start = Espacio.xs, top = Espacio.s).semantics { heading() },
                    )
                }
                items(fuentes, key = { it.url }) { f ->
                    Column(Modifier.fillMaxWidth().superficieTarjeta(radio = Radio.control + 4.dp).padding(Espacio.m), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(f.ref, style = MaterialTheme.typography.bodyMedium)
                        SelectionContainer {
                            Text(f.url, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace), color = c.textoSecundario, maxLines = 2)
                        }
                        TextButton(onClick = { abrirEnNavegador(contexto, f.url) }, contentPadding = PaddingValues(horizontal = 0.dp)) {
                            Icon(Iconos.Abrir, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.size(6.dp))
                            Text("Abrir fuente", color = c.marcaTexto, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            item {
                Spacer(Modifier.height(Espacio.xs))
                Text(Fuentes.AVISO_LEGAL, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario, modifier = Modifier.padding(horizontal = Espacio.xs))
            }
        }
    }
}

/**
 * El renglón pegado a los números ("Objetivos calculados con… · Ver fuentes", Apple 1.4.1): gris y chico, con "Ver
 * fuentes" en el verde de la marca. Abre las fuentes.
 */
@Composable
fun RenglonFuentes(
    modifier: Modifier = Modifier,
    texto: String = "Objetivos calculados con Mifflin-St Jeor · macros según ISSN y NASEM",
) {
    var abierta by remember { mutableStateOf(false) }
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClickLabel = "Ver las fuentes científicas") { abierta = true }
            .padding(vertical = 2.dp)
            .testTag("ver-fuentes"),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(Iconos.Libro, contentDescription = null, tint = c.textoSecundario, modifier = Modifier.padding(top = 1.dp).size(14.dp))
        Text(
            buildAnnotatedString {
                append("$texto · ")
                withStyle(SpanStyle(color = c.marcaTexto, fontWeight = FontWeight.SemiBold)) { append("Ver fuentes") }
            },
            style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal),
            color = c.textoSecundario,
        )
    }
    if (abierta) HojaFuentes(alCerrar = { abierta = false })
}

/** La fila al pie de Dieta, Entreno y Mi Día (GEN-09): "Respaldo científico del plan" con las siglas de cada escena. */
enum class OrigenRespaldo(val subtitulo: String) {
    DIETA("Mifflin-St Jeor · ISSN · NASEM · OMS · Guías Alimentarias (Argentina)"),
    ENTRENO("ACSM · OMS · MedlinePlus (NIH)"),
    MI_DIA("NASEM · OMS · MedlinePlus (NIH)"),
}

@Composable
fun PieRespaldo(origen: OrigenRespaldo, modifier: Modifier = Modifier) {
    var abierta by remember { mutableStateOf(false) }
    val c = MyPump.colores
    Row(
        modifier = modifier
            .fillMaxWidth()
            .superficieTarjeta(radio = 16.dp)
            .clickable(role = Role.Button) { abierta = true }
            .padding(14.dp)
            .testTag("respaldo-cientifico"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Espacio.s),
    ) {
        Icon(Iconos.Libro, contentDescription = null, tint = c.marcaTexto, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("Respaldo científico del plan", style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Text(origen.subtitulo, style = MaterialTheme.typography.bodySmall, color = c.textoSecundario)
        }
        Icon(Iconos.Chevron, contentDescription = null, tint = c.textoTerciario, modifier = Modifier.size(20.dp))
    }
    if (abierta) HojaFuentes(alCerrar = { abierta = false })
}
