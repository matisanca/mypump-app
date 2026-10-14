package com.pumpteam.mypump.diseno

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * Los íconos de la app. `material-icons` no está en el proyecto (y no se agregan dependencias), así que van los trazados
 * de Material Icons (Apache 2.0, grilla de 24) en vectores propios; la pesa está dibujada como la `dumbbell.fill` de iOS.
 * Se pintan con el color que les ponga `Icon(tint = …)`.
 */
object Iconos {
    private fun icono(nombre: String, vararg trazados: String): ImageVector = iconoEn(24f, nombre, *trazados)

    /** Los de Material Symbols vienen en una grilla de 960. */
    private fun iconoEn(grilla: Float, nombre: String, vararg trazados: String): ImageVector =
        ImageVector.Builder(name = nombre, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = grilla, viewportHeight = grilla)
            .apply { for (t in trazados) addPath(pathData = addPathNodes(t), fill = SolidColor(Color.Black)) }
            .build()

    /** Un rectángulo redondeado como trazado (para la pesa). */
    private fun rect(x: Float, y: Float, w: Float, h: Float, r: Float): String =
        "M${x + r},${y}H${x + w - r}A$r,$r 0 0 1 ${x + w},${y + r}V${y + h - r}A$r,$r 0 0 1 ${x + w - r},${y + h}" +
            "H${x + r}A$r,$r 0 0 1 $x,${y + h - r}V${y + r}A$r,$r 0 0 1 ${x + r},${y}Z"

    /** Entreno: la pesa de costado, discos afuera y barra al medio. */
    val Pesa: ImageVector by lazy {
        icono(
            "Pesa",
            rect(1f, 8f, 3f, 8f, 1.5f),
            rect(4.75f, 5f, 3.25f, 14f, 1.6f),
            rect(8f, 10.6f, 8f, 2.8f, 0.6f),
            rect(16f, 5f, 3.25f, 14f, 1.6f),
            rect(20f, 8f, 3f, 8f, 1.5f),
        )
    }

    /** Dieta (restaurant). */
    val Cubiertos: ImageVector by lazy {
        icono("Cubiertos", "M11,9H9V2H7v7H5V2H3v7c0,2.12 1.66,3.84 3.75,3.97V22h2.5v-9.03C11.34,12.84 13,11.12 13,9V2h-2v7zM16,6v8h2.5v8H21V2c-2.76,0 -5,2.24 -5,4z")
    }

    /** Chat (forum). */
    val Chat: ImageVector by lazy {
        icono("Chat", "M21,6h-2v9H6v2c0,0.55 0.45,1 1,1h11l4,4V7c0,-0.55 -0.45,-1 -1,-1zM17,12V3c0,-0.55 -0.45,-1 -1,-1H3c-0.55,0 -1,0.45 -1,1v14l4,-4h10c0.55,0 1,-0.45 1,-1z")
    }

    /** Revisión (checklist). */
    val Checklist: ImageVector by lazy {
        icono(
            "Checklist",
            "M22,7h-9v2h9V7zM22,15h-9v2h9V15zM5.54,11L2,7.46l1.41,-1.41l2.12,2.12l4.24,-4.24l1.41,1.41L5.54,11zM5.54,19L2,15.46l1.41,-1.41l2.12,2.12l4.24,-4.24l1.41,1.41L5.54,19z",
        )
    }

    /** Progreso (show_chart). */
    val Progreso: ImageVector by lazy {
        icono("Progreso", "M3.5,18.49l6,-6.01 4,4L22,6.92l-1.41,-1.41 -7.09,7.97 -4,-4L2,16.99z")
    }

    /** Mis datos (account_circle). */
    val Persona: ImageVector by lazy {
        icono(
            "Persona",
            "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM12,5c1.66,0 3,1.34 3,3s-1.34,3 -3,3 -3,-1.34 -3,-3 1.34,-3 3,-3zM12,19.2c-2.5,0 -4.71,-1.28 -6,-3.22 0.03,-1.99 4,-3.08 6,-3.08 1.99,0 5.97,1.09 6,3.08 -1.29,1.94 -3.5,3.22 -6,3.22z",
        )
    }

    /** IA y demo (auto_awesome). */
    val Chispas: ImageVector by lazy {
        icono(
            "Chispas",
            "M19,9l1.25,-2.75L23,5l-2.75,-1.25L19,1l-1.25,2.75L15,5l2.75,1.25L19,9zM11.5,9.5L9,4L6.5,9.5L1,12l5.5,2.5L9,20l2.5,-5.5L17,12L11.5,9.5zM19,15l-1.25,2.75L15,19l2.75,1.25L19,23l1.25,-2.75L23,19l-2.75,-1.25L19,15z",
        )
    }

    /** photo_camera */
    val Camara: ImageVector by lazy {
        icono(
            "Camara",
            "M12,12m-3.2,0a3.2,3.2 0,1 1,6.4 0a3.2,3.2 0,1 1,-6.4 0",
            "M9,2L7.17,4H4c-1.1,0 -2,0.9 -2,2v12c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V6c0,-1.1 -0.9,-2 -2,-2h-3.17L15,2H9zM12,17c-2.76,0 -5,-2.24 -5,-5s2.24,-5 5,-5 5,2.24 5,5 -2.24,5 -5,5z",
        )
    }

    /** wifi_off */
    val SinWifi: ImageVector by lazy {
        icono(
            "SinWifi",
            "M22.99,9C19.15,5.16 13.8,3.76 8.84,4.78l2.52,2.52c3.47,-0.17 6.99,1.05 9.63,3.7l2,-2zM18.99,13c-1.29,-1.29 -2.84,-2.13 -4.49,-2.56l3.53,3.53 0.96,-0.97zM2,3.05L5.07,6.1C3.6,6.82 2.22,7.78 1,9l1.99,2c1.24,-1.24 2.67,-2.16 4.2,-2.77l2.24,2.24C7.81,10.89 6.27,11.73 5,13v0.01L6.99,15c1.36,-1.36 3.14,-2.04 4.92,-2.06L18.98,20l1.27,-1.26L3.29,1.79 2,3.05zM9,17l3,3 3,-3c-1.65,-1.66 -4.34,-1.66 -6,0z",
        )
    }

    /** cloud_off */
    val SinNube: ImageVector by lazy {
        icono(
            "SinNube",
            "M19.35,10.04C18.67,6.59 15.64,4 12,4c-1.48,0 -2.85,0.43 -4.01,1.17l1.46,1.46C10.21,6.23 11.08,6 12,6c3.04,0 5.5,2.46 5.5,5.5v0.5H19c1.66,0 3,1.34 3,3 0,1.13 -0.64,2.11 -1.56,2.62l1.45,1.45C23.16,18.16 24,16.68 24,15c0,-2.64 -2.05,-4.78 -4.65,-4.96zM3,5.27l2.75,2.74C2.56,8.15 0,10.77 0,14c0,3.31 2.69,6 6,6h11.73l2,2L21,20.73 4.27,4 3,5.27zM7.73,10l8,8H6c-2.21,0 -4,-1.79 -4,-4s1.79,-4 4,-4h1.73z",
        )
    }

    /** link */
    val Link: ImageVector by lazy {
        icono(
            "Link",
            "M3.9,12c0,-1.71 1.39,-3.1 3.1,-3.1h4V7H7c-2.76,0 -5,2.24 -5,5s2.24,5 5,5h4v-1.9H7c-1.71,0 -3.1,-1.39 -3.1,-3.1zM8,13h8v-2H8v2zM17,7h-4v1.9h4c1.71,0 3.1,1.39 3.1,3.1s-1.39,3.1 -3.1,3.1h-4V17h4c2.76,0 5,-2.24 5,-5s-2.24,-5 -5,-5z",
        )
    }

    /** content_paste */
    val Pegar: ImageVector by lazy {
        icono(
            "Pegar",
            "M19,2h-4.18C14.4,0.84 13.3,0 12,0c-1.3,0 -2.4,0.84 -2.82,2H5c-1.1,0 -2,0.9 -2,2v16c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2zM12,2c0.55,0 1,0.45 1,1s-0.45,1 -1,1 -1,-0.45 -1,-1 0.45,-1 1,-1zM19,20H5V4h2v3h10V4h2v16z",
        )
    }

    /** Respaldo científico (book). */
    val Libro: ImageVector by lazy {
        icono("Libro", "M18,2H6c-1.1,0 -2,0.9 -2,2v16c0,1.1 0.9,2 2,2h12c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2zM6,4h5v8l-2.5,-1.5L6,12V4z")
    }

    /** dark_mode */
    val Luna: ImageVector by lazy {
        icono(
            "Luna",
            "M12,3c-4.97,0 -9,4.03 -9,9s4.03,9 9,9s9,-4.03 9,-9c0,-0.46 -0.04,-0.92 -0.1,-1.36c-0.98,1.37 -2.58,2.26 -4.4,2.26c-2.98,0 -5.4,-2.42 -5.4,-5.4c0,-1.81 0.89,-3.42 2.26,-4.4C12.92,3.04 12.46,3 12,3L12,3z",
        )
    }

    /** privacy_tip */
    val Privacidad: ImageVector by lazy {
        icono("Privacidad", "M12,1L3,5v6c0,5.55 3.84,10.74 9,12c5.16,-1.26 9,-6.45 9,-12V5L12,1L12,1zM11,7h2v2h-2V7zM11,11h2v6h-2V11z")
    }

    /** delete */
    val Papelera: ImageVector by lazy {
        icono("Papelera", "M6,19c0,1.1 0.9,2 2,2h8c1.1,0 2,-0.9 2,-2V7H6v12zM19,4h-3.5l-1,-1h-5l-1,1H5v2h14V4z")
    }

    /** chevron_right */
    val Chevron: ImageVector by lazy { icono("Chevron", "M10,6L8.59,7.41 13.17,12l-4.58,4.59L10,18l6,-6z") }

    /** arrow_back */
    val Atras: ImageVector by lazy { icono("Atras", "M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z") }

    /** close */
    val Cerrar: ImageVector by lazy {
        icono("Cerrar", "M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z")
    }

    /** warning */
    val Alerta: ImageVector by lazy { icono("Alerta", "M1,21h22L12,2 1,21zM13,18h-2v-2h2v2zM13,14h-2v-4h2v4z") }

    /** error */
    val Error: ImageVector by lazy {
        icono("Error", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM13,17h-2v-2h2v2zM13,13h-2V7h2v6z")
    }

    /** verified (el sello de "dentro del 5 %"). */
    val Verificado: ImageVector by lazy {
        icono(
            "Verificado",
            "M23,12l-2.44,-2.79l0.34,-3.69l-3.61,-0.82L15.4,1.5L12,2.96L8.6,1.5L6.71,4.69L3.1,5.5L3.44,9.2L1,12l2.44,2.79l-0.34,3.7l3.61,0.82L8.6,20.5l3.4,-1.47l3.4,1.46l1.89,-3.19l3.61,-0.82l-0.34,-3.69L23,12zM10.09,16.72l-3.8,-3.81l1.48,-1.48l2.32,2.33l5.85,-5.87l1.48,1.48L10.09,16.72z",
        )
    }

    /** calendar_today */
    val Calendario: ImageVector by lazy {
        icono("Calendario", "M20,3h-1V1h-2v2H7V1H5v2H4c-1.1,0 -2,0.9 -2,2v16c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2zM20,21H4V8h16v13z")
    }

    /** Desayuno (wb_twilight). */
    val Amanecer: ImageVector by lazy {
        icono(
            "Amanecer",
            "M16.95,8.66l2.12,-2.12l1.41,1.41l-2.12,2.12zM17.9,14c-0.5,-2.85 -2.95,-5 -5.9,-5s-5.45,2.15 -5.9,5h11.8zM2,16h20v4H2zM11,4h2v3h-2zM3.54,7.93l1.41,-1.42l2.12,2.12l-1.41,1.42z",
        )
    }

    /** Almuerzo (light_mode). */
    val Sol: ImageVector by lazy {
        icono(
            "Sol",
            "M12,7c-2.76,0 -5,2.24 -5,5s2.24,5 5,5s5,-2.24 5,-5S14.76,7 12,7L12,7z",
            "M2,13l2,0c0.55,0 1,-0.45 1,-1s-0.45,-1 -1,-1l-2,0c-0.55,0 -1,0.45 -1,1S1.45,13 2,13zM20,13l2,0c0.55,0 1,-0.45 1,-1s-0.45,-1 -1,-1l-2,0c-0.55,0 -1,0.45 -1,1S19.45,13 20,13zM11,2v2c0,0.55 0.45,1 1,1s1,-0.45 1,-1V2c0,-0.55 -0.45,-1 -1,-1S11,1.45 11,2zM11,20v2c0,0.55 0.45,1 1,1s1,-0.45 1,-1v-2c0,-0.55 -0.45,-1 -1,-1C11.45,19 11,19.45 11,20z",
            "M5.99,4.58c-0.39,-0.39 -1.03,-0.39 -1.41,0c-0.39,0.39 -0.39,1.03 0,1.41l1.06,1.06c0.39,0.39 1.03,0.39 1.41,0s0.39,-1.03 0,-1.41L5.99,4.58zM18.36,16.95c-0.39,-0.39 -1.03,-0.39 -1.41,0c-0.39,0.39 -0.39,1.03 0,1.41l1.06,1.06c0.39,0.39 1.03,0.39 1.41,0c0.39,-0.39 0.39,-1.03 0,-1.41L18.36,16.95zM19.42,5.99c0.39,-0.39 0.39,-1.03 0,-1.41c-0.39,-0.39 -1.03,-0.39 -1.41,0l-1.06,1.06c-0.39,0.39 -0.39,1.03 0,1.41s1.03,0.39 1.41,0L19.42,5.99zM7.05,18.36c0.39,-0.39 0.39,-1.03 0,-1.41c-0.39,-0.39 -1.03,-0.39 -1.41,0l-1.06,1.06c-0.39,0.39 -0.39,1.03 0,1.41s1.03,0.39 1.41,0L7.05,18.36z",
        )
    }

    /** Merienda (local_cafe). */
    val Taza: ImageVector by lazy {
        icono("Taza", "M20,3H4v10c0,2.21 1.79,4 4,4h6c2.21,0 4,-1.79 4,-4v-3h2c1.11,0 2,-0.9 2,-2V5c0,-1.11 -0.89,-2 -2,-2zM20,8h-2V5h2v3zM4,19h16v2H4z")
    }

    /** Pre y post entreno (bolt). */
    val Rayo: ImageVector by lazy {
        icono(
            "Rayo",
            "M11,21h-1l1,-7H7.5c-0.58,0 -0.57,-0.32 -0.38,-0.66 0.19,-0.34 0.05,-0.08 0.07,-0.12C8.48,10.94 10.42,7.54 13,3h1l-1,7h3.5c0.49,0 0.56,0.33 0.47,0.51l-0.07,0.15C12.96,17.55 11,21 11,21z",
        )
    }

    /** Colación (eco). */
    val Hoja: ImageVector by lazy {
        icono(
            "Hoja",
            "M6.05,8.05c-2.73,2.73 -2.73,7.15 -0.02,9.88c1.47,-3.4 4.09,-6.24 7.36,-7.93c-2.77,2.34 -4.71,5.61 -5.39,9.32c2.6,1.23 5.8,0.78 7.95,-1.37C19.43,14.47 20,4 20,4S9.53,4.57 6.05,8.05z",
        )
    }

    /** swap_horiz (un alimento reemplazado). */
    val Intercambio: ImageVector by lazy { icono("Intercambio", "M6.99,11L3,15l3.99,4v-3H14v-2H6.99v-3zM21,9l-3.99,-4v3H10v2h7.01v3L21,9z") }

    /** open_in_new */
    val Abrir: ImageVector by lazy {
        icono("Abrir", "M19,19H5V5h7V3H5c-1.11,0 -2,0.9 -2,2v14c0,1.1 0.89,2 2,2h14c1.1,0 2,-0.9 2,-2v-7h-2v7zM14,3v2h3.59l-9.83,9.83 1.41,1.41L19,6.41V10h2V3h-7z")
    }

    /** share */
    val Compartir: ImageVector by lazy {
        icono(
            "Compartir",
            "M18,16.08c-0.76,0 -1.44,0.3 -1.96,0.77L8.91,12.7c0.05,-0.23 0.09,-0.46 0.09,-0.7s-0.04,-0.47 -0.09,-0.7l7.05,-4.11c0.54,0.5 1.25,0.81 2.04,0.81 1.66,0 3,-1.34 3,-3s-1.34,-3 -3,-3 -3,1.34 -3,3c0,0.24 0.04,0.47 0.09,0.7L8.04,9.81C7.5,9.31 6.79,9 6,9c-1.66,0 -3,1.34 -3,3s1.34,3 3,3c0.79,0 1.5,-0.31 2.04,-0.81l7.12,4.16c-0.05,0.21 -0.08,0.43 -0.08,0.65 0,1.61 1.31,2.92 2.92,2.92 1.61,0 2.92,-1.31 2.92,-2.92s-1.31,-2.92 -2.92,-2.92z",
        )
    }

    /** description (el informe de la actualización). */
    val Documento: ImageVector by lazy {
        icono(
            "Documento",
            "M14,2H6c-1.1,0 -1.99,0.9 -1.99,2L4,20c0,1.1 0.89,2 1.99,2H18c1.1,0 2,-0.9 2,-2V8l-6,-6zM16,18H8v-2h8v2zM16,14H8v-2h8v2zM13,9V3.5L18.5,9H13z",
        )
    }

    /** system_update ("Actualizá MyPump"). */
    val Actualizar: ImageVector by lazy {
        icono(
            "Actualizar",
            "M17,1.01L7,1c-1.1,0 -1.99,0.9 -1.99,2v18c0,1.1 0.89,2 1.99,2h10c1.1,0 2,-0.9 2,-2V3c0,-1.1 -0.9,-1.99 -2,-1.99zM17,19H7V5h10v14zM16,13h-3V8h-2v5H8l4,4 4,-4z",
        )
    }

    // ── Entreno ──

    /** check: una serie hecha, el ejercicio completo, el día cerrado. */
    val Tilde: ImageVector by lazy { icono("Tilde", "M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z") }

    /** check_circle (la variante elegida al sustituir). */
    val TildeEnCirculo: ImageVector by lazy {
        icono("TildeEnCirculo", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM10,17l-5,-5 1.41,-1.41L10,14.17l7.59,-7.59L19,8l-9,9z")
    }

    /** radio_button_unchecked (una variante sin elegir). */
    val Circulo: ImageVector by lazy {
        icono("Circulo", "M12,2C6.48,2 2,6.48 2,12s4.48,10 10,10 10,-4.48 10,-10S17.52,2 12,2zM12,20c-4.42,0 -8,-3.58 -8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8z")
    }

    /** timer: el descanso. */
    val Temporizador: ImageVector by lazy {
        icono(
            "Temporizador",
            "M15,1H9v2h6V1zM11,14h2V8h-2v6zM19.03,7.39l1.42,-1.42c-0.43,-0.51 -0.9,-0.99 -1.41,-1.41l-1.42,1.42C16.07,4.74 14.12,4 12,4c-4.97,0 -9,4.03 -9,9s4.02,9 9,9 9,-4.03 9,-9c0,-2.12 -0.74,-4.07 -1.97,-5.61zM12,20c-3.87,0 -7,-3.13 -7,-7s3.13,-7 7,-7 7,3.13 7,7 -3.13,7 -7,7z",
        )
    }

    /** schedule: una sesión que quedó sin cerrar. */
    val Reloj: ImageVector by lazy {
        icono(
            "Reloj",
            "M11.99,2C6.47,2 2,6.48 2,12s4.47,10 9.99,10C17.52,22 22,17.52 22,12S17.52,2 11.99,2zM12,20c-4.42,0 -8,-3.58 -8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8z",
            "M12.5,7H11v6l5.25,3.15 0.75,-1.23 -4.5,-2.67z",
        )
    }

    /** whatshot: calentamiento y cardio. */
    val Fuego: ImageVector by lazy {
        icono(
            "Fuego",
            "M13.5,0.67s0.74,2.65 0.74,4.8c0,2.06 -1.35,3.73 -3.41,3.73 -2.07,0 -3.63,-1.67 -3.63,-3.73l0.03,-0.36C5.21,7.51 4,10.62 4,14c0,4.42 3.58,8 8,8s8,-3.58 8,-8C20,8.61 17.41,3.8 13.5,0.67zM11.71,19c-1.78,0 -3.22,-1.4 -3.22,-3.14 0,-1.62 1.05,-2.76 2.81,-3.12 1.77,-0.36 3.6,-1.21 4.62,-2.58 0.39,1.29 0.59,2.65 0.59,4.04 0,2.65 -2.15,4.8 -4.8,4.8z",
        )
    }

    /** emoji_events: el récord. */
    val Trofeo: ImageVector by lazy {
        icono(
            "Trofeo",
            "M19,5h-2V3H7v2H5C3.9,5 3,5.9 3,7v1c0,2.55 1.92,4.63 4.39,4.94c0.63,1.5 1.98,2.63 3.61,2.96V19H7v2h10v-2h-4v-3.1c1.63,-0.33 2.98,-1.46 3.61,-2.96C19.08,12.63 21,10.55 21,8V7C21,5.9 20.1,5 19,5zM5,8V7h2v3.82C5.84,10.4 5,9.3 5,8zM19,8c0,1.3 -0.84,2.4 -2,2.82V7h2V8z",
        )
    }

    /** lock: una sustitución fijada. */
    val Candado: ImageVector by lazy {
        icono(
            "Candado",
            "M18,8h-1V6c0,-2.76 -2.24,-5 -5,-5S7,3.24 7,6v2H6c-1.1,0 -2,0.9 -2,2v10c0,1.1 0.9,2 2,2h12c1.1,0 2,-0.9 2,-2V10c0,-1.1 -0.9,-2 -2,-2zM12,17c-1.1,0 -2,-0.9 -2,-2s0.9,-2 2,-2 2,0.9 2,2 -0.9,2 -2,2zM15.1,8H8.9V6c0,-1.71 1.39,-3.1 3.1,-3.1 1.71,0 3.1,1.39 3.1,3.1v2z",
        )
    }

    /** pan_tool: "Manual" (terminado a mano). */
    val Mano: ImageVector by lazy {
        icono(
            "Mano",
            "M23,5.5V20c0,2.2 -1.8,4 -4,4h-7.3c-1.08,0 -2.1,-0.43 -2.85,-1.19L1,14.83c0,0 1.26,-1.23 1.3,-1.25c0.22,-0.19 0.49,-0.29 0.79,-0.29c0.22,0 0.42,0.06 0.6,0.16C3.73,13.46 8,15.91 8,15.91V4c0,-0.83 0.67,-1.5 1.5,-1.5S11,3.17 11,4v7h1V1.5C12,0.67 12.67,0 13.5,0S15,0.67 15,1.5V11h1V2.5C16,1.67 16.67,1 17.5,1S19,1.67 19,2.5V11h1V5.5C20,4.67 20.67,4 21.5,4S23,4.67 23,5.5z",
        )
    }

    /** chat_bubble: comentarios de Mati. */
    val Burbuja: ImageVector by lazy { icono("Burbuja", "M20,2H4c-1.1,0 -2,0.9 -2,2v18l4,-4h14c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2z") }

    /** play_arrow: "Empezar entrenamiento". */
    val Play: ImageVector by lazy { icono("Play", "M8,5v14l11,-7z") }

    /** flag: cerrar la sesión. */
    val Bandera: ImageVector by lazy { icono("Bandera", "M14.4,6L14,4H5v17h2v-7h5.6l0.4,2h7V6z") }

    /** edit: reabrir un ejercicio. */
    val Lapiz: ImageVector by lazy {
        icono(
            "Lapiz",
            "M3,17.25V21h3.75L17.81,9.94l-3.75,-3.75L3,17.25zM20.71,7.04c0.39,-0.39 0.39,-1.02 0,-1.41l-2.34,-2.34c-0.39,-0.39 -1.02,-0.39 -1.41,0l-1.83,1.83 3.75,3.75 1.83,-1.83z",
        )
    }

    /** skip_next: saltar el descanso. */
    val Saltar: ImageVector by lazy { icono("Saltar", "M6,18l8.5,-6L6,6v12zM16,6v12h2V6h-2z") }

    /** undo: volver al ejercicio del plan. */
    val Deshacer: ImageVector by lazy {
        icono(
            "Deshacer",
            "M12.5,8c-2.65,0 -5.05,0.99 -6.9,2.6L2,7v9h9l-3.62,-3.62c1.39,-1.16 3.16,-1.88 5.12,-1.88 3.54,0 6.55,2.31 7.6,5.5l2.37,-0.78C21.08,11.03 17.15,8 12.5,8z",
        )
    }

    /** search */
    val Buscar: ImageVector by lazy {
        icono(
            "Buscar",
            "M15.5,14h-0.79l-0.28,-0.27C15.41,12.59 16,11.11 16,9.5 16,5.91 13.09,3 9.5,3S3,5.91 3,9.5 5.91,16 9.5,16c1.61,0 3.09,-0.59 4.23,-1.57l0.27,0.28v0.79l5,4.99L20.49,19l-4.99,-5zM9.5,14C7.01,14 5,11.99 5,9.5S7.01,5 9.5,5 14,7.01 14,9.5 11.99,14 9.5,14z",
        )
    }

    /** remove: el "saltado" de la card. */
    val Menos: ImageVector by lazy { icono("Menos", "M19,13H5v-2h14v2z") }

    /** format_list_bulleted: cuántos ejercicios tiene el día. */
    val Lista: ImageVector by lazy {
        icono(
            "Lista",
            "M4,10.5c-0.83,0 -1.5,0.67 -1.5,1.5s0.67,1.5 1.5,1.5 1.5,-0.67 1.5,-1.5 -0.67,-1.5 -1.5,-1.5zM4,4.5c-0.83,0 -1.5,0.67 -1.5,1.5S3.17,7.5 4,7.5 5.5,6.83 5.5,6 4.83,4.5 4,4.5zM4,16.5c-0.83,0 -1.5,0.68 -1.5,1.5s0.68,1.5 1.5,1.5 1.5,-0.68 1.5,-1.5 -0.67,-1.5 -1.5,-1.5zM7,19h14v-2H7v2zM7,13h14v-2H7v2zM7,5v2h14V5H7z",
        )
    }

    /** trending_up: la semana cambia carga o volumen. */
    val Tendencia: ImageVector by lazy { icono("Tendencia", "M16,6l2.29,2.29 -4.88,4.88 -4,-4L2,16.59 3.41,18l6,-6 4,4 6.3,-6.29L22,12V6z") }

    /** gps_fixed: la calibración. */
    val Mira: ImageVector by lazy {
        icono(
            "Mira",
            "M12,8c-2.21,0 -4,1.79 -4,4s1.79,4 4,4 4,-1.79 4,-4 -1.79,-4 -4,-4zM20.94,11c-0.46,-4.17 -3.77,-7.48 -7.94,-7.94V1h-2v2.06C6.83,3.52 3.52,6.83 3.06,11H1v2h2.06c0.46,4.17 3.77,7.48 7.94,7.94V23h2v-2.06c4.17,-0.46 7.48,-3.77 7.94,-7.94H23v-2h-2.06zM12,19c-3.87,0 -7,-3.13 -7,-7s3.13,-7 7,-7 7,3.13 7,7 -3.13,7 -7,7z",
        )
    }

    /** touch_app: lo de la última vez a un toque. */
    val Toque: ImageVector by lazy {
        icono(
            "Toque",
            "M9,11.24V7.5C9,6.12 10.12,5 11.5,5S14,6.12 14,7.5v3.74c1.21,-0.81 2,-2.18 2,-3.74C16,5.01 13.99,3 11.5,3S7,5.01 7,7.5c0,1.56 0.79,2.93 2,3.74zM18.84,15.87l-4.54,-2.26c-0.17,-0.07 -0.35,-0.11 -0.54,-0.11H13v-6c0,-0.83 -0.67,-1.5 -1.5,-1.5S10,6.67 10,7.5v10.74l-3.43,-0.72c-0.08,-0.01 -0.15,-0.03 -0.24,-0.03 -0.31,0 -0.59,0.13 -0.79,0.33l-0.79,0.8 4.94,4.94c0.27,0.27 0.65,0.44 1.06,0.44h6.79c0.75,0 1.33,-0.55 1.44,-1.28l0.75,-5.27c0.01,-0.07 0.02,-0.14 0.02,-0.2 0,-0.62 -0.38,-1.16 -0.91,-1.38z",
        )
    }

    /** ondemand_video */
    val Video: ImageVector by lazy {
        icono(
            "Video",
            "M21,3H3c-1.11,0 -2,0.89 -2,2v12c0,1.1 0.89,2 2,2h5v2h8v-2h5c1.1,0 1.99,-0.9 1.99,-2L23,5c0,-1.11 -0.9,-2 -2,-2zM21,17H3V5h18v12zM16,11l-7,4V7z",
        )
    }

    /** arrow_forward ("Siguiente: Remo →", "Pasar a Semana 6 →"). */
    val FlechaDerecha: ImageVector by lazy { icono("FlechaDerecha", "M12,4l-1.41,1.41L16.17,11H4v2h12.17l-5.58,5.59L12,20l8,-8z") }

    /** arrow_upward: mandar un comentario. */
    val FlechaArriba: ImageVector by lazy { icono("FlechaArriba", "M4,12l1.41,1.41L11,7.83V20h2V7.83l5.58,5.59L20,12l-8,-8 -8,8z") }

    /** format_quote: la nota técnica de Mati. */
    val Cita: ImageVector by lazy { icono("Cita", "M6,17h3l2,-4V7H5v6h3zM14,17h3l2,-4V7h-6v6h3z") }

    /** image: la foto que no cargó. */
    val Foto: ImageVector by lazy {
        icono("Foto", "M21,19V5c0,-1.1 -0.9,-2 -2,-2H5c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2zM8.5,13.5l2.5,3.01L14.5,12l4.5,6H5l3.5,-4.5z")
    }

    /** unfold_more: el selector de RIR. */
    val ArribaAbajo: ImageVector by lazy {
        icono("ArribaAbajo", "M12,5.83L15.17,9l1.41,-1.41L12,3 7.41,7.59 8.83,9 12,5.83zM12,18.17L8.83,15l-1.41,1.41L12,21l4.59,-4.59L15.17,15 12,18.17z")
    }

    /** cloud_done: la sesión del día quedó guardada. */
    val NubeGuardada: ImageVector by lazy {
        icono(
            "NubeGuardada",
            "M19.35,10.04C18.67,6.59 15.64,4 12,4 9.11,4 6.6,5.64 5.35,8.04 2.34,8.36 0,10.91 0,14c0,3.31 2.69,6 6,6h13c2.76,0 5,-2.24 5,-5 0,-2.64 -2.05,-4.78 -4.65,-4.96zM10,17l-3.5,-3.5 1.41,-1.41L10,14.17 15.18,9l1.41,1.41L10,17z",
        )
    }

    /** directions_run (Material Symbols, el de Android): la miniatura del cardio sin foto. */
    val Correr: ImageVector by lazy {
        iconoEn(
            960f,
            "Correr",
            "M520,920L520,680L436,600L396,776L120,720L136,640L328,680L392,356L320,384L320,520L240,520L240,332L398,264Q433,249 449.5,244.5Q466,240 480,240Q501,240 519,251Q537,262 548,280L588,344Q614,386 658.5,413Q703,440 760,440L760,520Q694,520 636.5,492.5Q579,465 540,420L516,540L600,620L600,920L520,920ZM540,220Q507,220 483.5,196.5Q460,173 460,140Q460,107 483.5,83.5Q507,60 540,60Q573,60 596.5,83.5Q620,107 620,140Q620,173 596.5,196.5Q573,220 540,220Z",
        )
    }
}
