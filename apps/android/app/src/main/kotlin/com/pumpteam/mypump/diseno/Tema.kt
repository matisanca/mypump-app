package com.pumpteam.mypump.diseno

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.pumpteam.mypump.R

// La identidad de MyPump en Material 3, con los mismos colores que el Tema.swift de iOS:
// · El lima de la marca es un RELLENO con texto negro encima (botones principales, selección, logros).
// · Para texto e íconos va `marcaTexto` (en claro un verde oscuro: el lima sobre blanco no tiene contraste) y para gráficos
//   `marcaVivo`.
// · Archivo (la letra de la marca, OFL) para títulos grandes y números; el resto, la del sistema.
// · Fondos agrupados: el fondo gris claro (negro en oscuro) y las tarjetas blancas (gris oscuro), como iOS.

/** Relleno de marca (botones principales, día hecho). Siempre con [SobreMarca] encima. */
val Marca = Color(0xFFB8F060)

/** Lo que va encima del lima. */
val SobreMarca = Color(0xFF0A0A0A)

/** Los colores propios de MyPump que Material no tiene (macros, señales, superficies agrupadas). */
@Immutable
data class ColoresMyPump(
    val marca: Color,
    val sobreMarca: Color,
    /** Verde para texto e íconos. */
    val marcaTexto: Color,
    /** Fondo teñido de marca (ícono de comida, aviso suave). */
    val marcaSuave: Color,
    /** Verde para gráficos (anillos, líneas, barras). */
    val marcaVivo: Color,
    val exito: Color,
    val alerta: Color,
    val peligro: Color,
    val sueno: Color,
    val corazon: Color,
    val record: Color,
    val agua: Color,
    val proteina: Color,
    val carbohidrato: Color,
    val grasa: Color,
    /** Fondo de la pantalla (agrupado). */
    val fondo: Color,
    /** Tarjetas sobre el fondo. */
    val tarjeta: Color,
    /** Superficie de un campo o control dentro de una tarjeta. */
    val campo: Color,
    /** Borde de pelo: separa la tarjeta del fondo en oscuro, donde no hay sombra que lo haga. */
    val borde: Color,
    /** Línea entre filas de una tarjeta (el `separator` de iOS). */
    val separador: Color,
    val texto: Color,
    val textoSecundario: Color,
    val textoTerciario: Color,
    val oscuro: Boolean,
)

private val coloresClaros = ColoresMyPump(
    marca = Marca,
    sobreMarca = SobreMarca,
    marcaTexto = Color(0xFF3F6212),
    marcaSuave = Color(0x42B8F060),
    marcaVivo = Color(0xFF65A30D),
    exito = Color(0xFF16A34A),
    alerta = Color(0xFFC2410C),
    peligro = Color(0xFFDC2626),
    sueno = Color(0xFF4F5BD5),
    corazon = Color(0xFFE11D48),
    record = Color(0xFFA16207),
    agua = Color(0xFF0A84FF),
    proteina = Color(0xFFE11D48),
    carbohidrato = Color(0xFFB45309),
    grasa = Color(0xFF4F5BD5),
    fondo = Color(0xFFF2F2F7),
    tarjeta = Color(0xFFFFFFFF),
    campo = Color(0x1F767680),
    borde = Color(0x0D000000),
    separador = Color(0x4A3C3C43),
    texto = Color(0xFF000000),
    // El gris secundario de iOS es 3,5:1 sobre blanco; acá un poco más oscuro para pasar 4,5:1 con letra chica.
    textoSecundario = Color(0xFF6B6B70),
    textoTerciario = Color(0xFFA1A1A6),
    oscuro = false,
)

private val coloresOscuros = ColoresMyPump(
    marca = Marca,
    sobreMarca = SobreMarca,
    marcaTexto = Color(0xFFB8F060),
    marcaSuave = Color(0x24B8F060),
    marcaVivo = Color(0xFFB8F060),
    exito = Color(0xFF30D158),
    alerta = Color(0xFFFF9F0A),
    peligro = Color(0xFFFF453A),
    sueno = Color(0xFF7D8BFF),
    corazon = Color(0xFFFF5C7A),
    record = Color(0xFFFFD60A),
    agua = Color(0xFF64D2FF),
    proteina = Color(0xFFFF5C7A),
    carbohidrato = Color(0xFFFFB020),
    grasa = Color(0xFF7D8BFF),
    fondo = Color(0xFF000000),
    tarjeta = Color(0xFF1C1C1E),
    campo = Color(0x3D767680),
    borde = Color(0x14FFFFFF),
    separador = Color(0x99545458),
    texto = Color(0xFFFFFFFF),
    textoSecundario = Color(0xFFA1A1A8),
    textoTerciario = Color(0xFF6C6C70),
    oscuro = true,
)

// Material: el primario es el verde de texto (botones de texto, interruptores, foco) y el contenedor primario es el lima.
// Las superficies son las agrupadas de iOS: el fondo gris y la barra de pestañas y las tarjetas en blanco.
private val esquemaClaro = lightColorScheme(
    primary = coloresClaros.marcaTexto,
    onPrimary = Color.White,
    primaryContainer = Marca,
    onPrimaryContainer = SobreMarca,
    inversePrimary = Marca,
    secondary = coloresClaros.marcaTexto,
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFE3F9BF),
    onSecondaryContainer = Color(0xFF233A06),
    tertiary = coloresClaros.agua,
    onTertiary = Color.White,
    background = coloresClaros.fondo,
    onBackground = coloresClaros.texto,
    surface = coloresClaros.fondo,
    onSurface = coloresClaros.texto,
    surfaceVariant = Color(0xFFE5E5EA),
    onSurfaceVariant = coloresClaros.textoSecundario,
    surfaceTint = coloresClaros.fondo,
    surfaceBright = Color.White,
    surfaceDim = Color(0xFFE5E5EA),
    surfaceContainerLowest = Color.White,
    surfaceContainerLow = Color(0xFFF7F7FA),
    surfaceContainer = Color.White,
    surfaceContainerHigh = Color(0xFFECECF1),
    surfaceContainerHighest = Color(0xFFE5E5EA),
    inverseSurface = Color(0xFF1C1C1E),
    inverseOnSurface = Color.White,
    outline = Color(0xFFC6C6C8),
    outlineVariant = Color(0xFFE5E5EA),
    error = coloresClaros.peligro,
    onError = Color.White,
    scrim = Color.Black,
)

private val esquemaOscuro = darkColorScheme(
    primary = Marca,
    onPrimary = SobreMarca,
    primaryContainer = Marca,
    onPrimaryContainer = SobreMarca,
    inversePrimary = coloresClaros.marcaTexto,
    secondary = Marca,
    onSecondary = SobreMarca,
    secondaryContainer = Color(0xFF3B4A28),
    onSecondaryContainer = Color(0xFFE1F8BC),
    tertiary = coloresOscuros.agua,
    onTertiary = Color.Black,
    background = coloresOscuros.fondo,
    onBackground = coloresOscuros.texto,
    surface = coloresOscuros.fondo,
    onSurface = coloresOscuros.texto,
    surfaceVariant = Color(0xFF2C2C2E),
    onSurfaceVariant = coloresOscuros.textoSecundario,
    surfaceTint = coloresOscuros.fondo,
    surfaceBright = Color(0xFF2C2C2E),
    surfaceDim = Color.Black,
    surfaceContainerLowest = Color(0xFF0B0B0C),
    surfaceContainerLow = Color(0xFF121214),
    surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerHigh = Color(0xFF2C2C2E),
    surfaceContainerHighest = Color(0xFF3A3A3C),
    inverseSurface = Color(0xFFE5E5EA),
    inverseOnSurface = Color.Black,
    outline = Color(0xFF545458),
    outlineVariant = Color(0xFF38383A),
    error = coloresOscuros.peligro,
    onError = Color.Black,
    scrim = Color.Black,
)

/**
 * Archivo es variable (`wght` de 100 a 900, 600 por defecto): cada peso es la misma fuente con su eje. El eje se pasa a
 * mano: `Font(resId, peso)` arma la fuente con los ajustes de variación VACÍOS y todo salía en el 600 de fábrica, con los
 * títulos y los números flojos al lado del iPhone (15-oct, ArchivoPesoTest). Desde Android 8, el mínimo de la app.
 */
@OptIn(ExperimentalTextApi::class)
private fun archivo(peso: Int) = Font(R.font.archivo, FontWeight(peso), variationSettings = FontVariation.Settings(FontVariation.weight(peso)))

val Archivo = FontFamily(archivo(500), archivo(600), archivo(700), archivo(800), archivo(900))

private val base = Typography()

/**
 * Los títulos grandes (la barra de cada pestaña, la marca) en Archivo; el texto corrido, los rótulos y los botones en la
 * letra del sistema, como iOS con SF Pro.
 */
private val tipografia = Typography(
    displayLarge = base.displayLarge.copy(fontFamily = Archivo, fontWeight = FontWeight.W900, letterSpacing = (-0.02).em),
    displayMedium = base.displayMedium.copy(fontFamily = Archivo, fontWeight = FontWeight.W900, letterSpacing = (-0.02).em),
    displaySmall = base.displaySmall.copy(fontFamily = Archivo, fontWeight = FontWeight.W800),
    headlineLarge = base.headlineLarge.copy(fontFamily = Archivo, fontWeight = FontWeight.W800),
    headlineMedium = base.headlineMedium.copy(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 32.sp, lineHeight = 38.sp),
    headlineSmall = base.headlineSmall.copy(fontFamily = Archivo, fontWeight = FontWeight.W800),
    titleLarge = base.titleLarge.copy(fontFamily = Archivo, fontWeight = FontWeight.W700),
    titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp, lineHeight = 22.sp),
    titleSmall = base.titleSmall.copy(fontWeight = FontWeight.SemiBold),
    bodyLarge = base.bodyLarge.copy(fontSize = 17.sp, lineHeight = 22.sp, letterSpacing = 0.sp),
    bodyMedium = base.bodyMedium.copy(fontSize = 15.sp, lineHeight = 20.sp, letterSpacing = 0.sp),
    bodySmall = base.bodySmall.copy(fontSize = 13.sp, lineHeight = 18.sp, letterSpacing = 0.sp),
    labelLarge = base.labelLarge.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    labelMedium = base.labelMedium.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
    labelSmall = base.labelSmall.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium),
)

/** Los números en Archivo, como `Font.numero*` de iOS. */
object Numeros {
    val gigante = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 56.sp, lineHeight = 60.sp)
    val grande = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W800, fontSize = 36.sp, lineHeight = 40.sp)
    val mediano = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = 22.sp, lineHeight = 26.sp)
    val chico = TextStyle(fontFamily = Archivo, fontWeight = FontWeight.W700, fontSize = 17.sp, lineHeight = 22.sp)
}

val LocalColoresMyPump = staticCompositionLocalOf { coloresClaros }

/** Los colores de MyPump del tema vigente: `MyPump.colores.marcaTexto`. */
object MyPump {
    val colores: ColoresMyPump
        @Composable @ReadOnlyComposable get() = LocalColoresMyPump.current
}

/**
 * D5: sigue al sistema salvo que el cliente haya guardado oscuro (`mypump-theme = dark`, en Mis datos o lo que trajo la
 * migración de la web). El `'light'` que guarda la web no es una elección: `theme.js` lo escribe en cada carga.
 */
fun temaOscuro(sistemaOscuro: Boolean, oscuroGuardado: Boolean): Boolean = oscuroGuardado || sistemaOscuro

@Composable
fun TemaMyPump(oscuro: Boolean = isSystemInDarkTheme(), contenido: @Composable () -> Unit) {
    val colores = if (oscuro) coloresOscuros else coloresClaros
    CompositionLocalProvider(LocalColoresMyPump provides colores) {
        MaterialTheme(colorScheme = if (oscuro) esquemaOscuro else esquemaClaro, typography = tipografia) {
            // El color del texto y de los íconos sin color propio. Material lo pone solo adentro de un Surface o un Scaffold:
            // afuera (la bienvenida, "Sin conexión") quedaba el negro por defecto, invisible en oscuro.
            CompositionLocalProvider(LocalContentColor provides colores.texto, content = contenido)
        }
    }
}
