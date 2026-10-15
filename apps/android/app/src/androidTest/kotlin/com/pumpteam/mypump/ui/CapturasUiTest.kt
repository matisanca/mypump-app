package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Las capturas de evidencia, en claro y en oscuro: recorre la bienvenida, el link vencido, la demo, las fuentes, una
 * cuenta (con badges y el banner de Revisión), Mis datos y sin red. Quedan en [Telefono.CARPETA_CAPTURAS] y las baja
 * `scripts/nativa/emu-ui.sh` a `~/Developer/nativa-evidencia/android-ui/<fecha>/`.
 */
@RunWith(AndroidJUnit4::class)
class CapturasUiTest : PruebaUi() {
    @Test
    fun enClaro() = recorrer(oscuro = false)

    @Test
    fun enOscuro() = recorrer(oscuro = true)

    @Test
    fun entrenoEnClaro() = recorrerEntreno(oscuro = false)

    @Test
    fun entrenoEnOscuro() = recorrerEntreno(oscuro = true)

    /**
     * Entreno con la cuenta grabada y una sesión en curso (23 minutos): dos ejercicios hechos (uno a mano, "Manual"), el
     * jalón con 2 de 4 series, un comentario de Mati sin leer en el remo y el día 2 cerrado esta semana. Después el
     * detalle, una serie con su descanso, sustituir, la card sustituida, los comentarios, cerrar el día antes de tiempo y
     * "Todavía no hay rutina".
     */
    private fun recorrerEntreno(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        val inicio = java.time.Instant.now().minusSeconds(23 * 60).toString()
        servidor.respuestas["mypump_get_sesion_dia"] =
            """[{"id":"ses-captura","dia_id":"d1","semana":5,"iniciada_en":"$inicio","finalizada_en":null}]"""
        servidor.respuestas["mypump_get_sesiones_semana"] =
            """[{"dia_id":"d2","semana":5,"iniciada_en":"2026-10-12T21:00:00Z","finalizada_en":"2026-10-12T22:05:00Z"}]"""
        servidor.respuestas["mypump_get_ejercicios_estado"] = """[
            {"ejercicio_id":"cinta-10-min-entrada-en-calor-d1-0","status":"completo_sin_datos","series_completadas":0,"marcado_manualmente":true},
            {"ejercicio_id":"rollout-con-ab-wheel-core-anterior-d1-1","status":"completo","series_completadas":3,"marcado_manualmente":false}]"""
        fun serie(ej: String, nombre: String, n: Int, kg: Number, reps: Int, rir: Int) =
            """{"ejercicio_id":"$ej","ejercicio_nombre":"$nombre","serie_numero":$n,"peso_kg":$kg,"reps_realizadas":$reps,"rir_real":$rir,"notas":null}"""
        servidor.respuestas["mypump_get_registros_sesion"] = "[" + listOf(
            serie("rollout-con-ab-wheel-core-anterior-d1-1", "Rollout con ab wheel (core anterior)", 1, 0, 13, 1),
            serie("rollout-con-ab-wheel-core-anterior-d1-1", "Rollout con ab wheel (core anterior)", 2, 0, 12, 1),
            serie("rollout-con-ab-wheel-core-anterior-d1-1", "Rollout con ab wheel (core anterior)", 3, 0, 12, 1),
            serie("jalon-al-pecho-prono-dorsal-ancho-d1-0", "Jalón al pecho prono (dorsal ancho)", 1, 60, 10, 0),
            serie("jalon-al-pecho-prono-dorsal-ancho-d1-0", "Jalón al pecho prono (dorsal ancho)", 2, 60, 9, 0),
        ).joinToString(",") + "]"
        servidor.respuestas["mypump_get_comentarios"] =
            """[{"id":"c1","ambito":"ejercicio","referencia_id":"remo-en-polea-sentado-grosor-dorsal-bajo-d1-1","referencia_nombre":"Remo en polea sentado","autor":"coach","contenido":"Bajá un poco el peso y apretá arriba un segundo.","leido_por_cliente":false,"created_at":"2026-10-13T21:10:00Z"}]"""
        servidor.respuestas["mypump_iniciar_sesion"] = "\"ses-captura\""
        guardarCuenta()
        abrir().also {
            p.nodo(texto("2 de 9 ejercicios hechos"))
            p.nodo(etiqueta("cronometro"))
            p.esperar("el badge de Entreno") { "1" in p.textosBajo(etiqueta("pestana-entreno")) }
            foto("13-entreno-dia")
            p.desplazar(etiqueta("entreno-lista"), 1_450f)
            p.esperar("el historial") { p.estado(etiqueta("ejercicio-jalon-al-pecho-prono-dorsal-ancho-d1-0"))?.contains("récord") == true }
            foto("14-entreno-cards")

            p.tocar(etiqueta("ejercicio-jalon-al-pecho-prono-dorsal-ancho-d1-0"))
            p.nodo(etiqueta("pista-serie"))
            foto("15-entreno-ejercicio")
            p.tocar(etiqueta("confirmar-serie-3"))
            p.nodo(etiqueta("descanso"))
            foto("16-entreno-serie-y-descanso")

            p.desplazar(etiqueta("ejercicio-pantalla"), 900f)
            p.tocar(etiqueta("sustituir"))
            p.nodo(etiqueta("hoja-sustituir"))
            p.tocar(etiqueta("variante"))
            p.tocar(etiqueta("fijar"))
            foto("17-entreno-sustituir")
            p.tocar(etiqueta("confirmar-sustitucion"))
            p.esperarQueNoEste(etiqueta("hoja-sustituir"))
            p.tocar(etiqueta("descanso-saltar"))
            p.esperarQueNoEste(etiqueta("descanso"))
            p.desplazar(etiqueta("ejercicio-pantalla"), -3_000f)
            p.nodo(etiqueta("en-lugar-de"))
            foto("18-entreno-sustituido")

            p.tocar(etiqueta("volver"))
            p.tocar(etiqueta("ejercicio-remo-en-polea-sentado-grosor-dorsal-bajo-d1-1"))
            p.nodo(texto("Bajá un poco el peso y apretá arriba un segundo."))
            p.desplazar(etiqueta("ejercicio-pantalla"), 3_000f)
            foto("19-entreno-comentarios")

            // Sin volver arriba: desplazar de más con la acción de accesibilidad deja a medio tirar el "tirar para actualizar".
            p.tocar(etiqueta("volver"))
            p.tocar(texto("Cerrar"))
            p.nodo(etiqueta("hoja-cerrar-dia"))
            p.nodo(etiqueta("pendientes-cierre"))
            foto("20-entreno-cerrar-dia")
        }.close()

        // D11+: sin rutina.
        servidor.respuestas["mypump_get_rutina_activa"] = "[]"
        abrir().also {
            p.nodo(etiqueta("entreno-vacio"))
            foto("21-entreno-sin-rutina")
        }.close()
        servidor.respuestas.remove("mypump_get_rutina_activa")
    }

    private fun recorrer(oscuro: Boolean) {
        val tema = if (oscuro) "oscuro" else "claro"
        fun foto(nombre: String) = Telefono.captura("$nombre-$tema")
        Telefono.modoNoche(oscuro)
        servidor.respuestas["mypump_get_chat"] =
            """[{"id":"m1","autor":"coach","contenido":"¿Cómo venís con el plan?","leido_por_cliente":false,"created_at":"2026-10-14T12:00:00Z"}]"""

        abrir().also {
            p.nodo(etiqueta("ver-demo"))
            foto("01-bienvenida")
            p.escribir(etiqueta("campo-link"), "https://app.mypumpteam.com/?t=linkVencidoDePrueba_00000000")
            p.tocar(etiqueta("entrar"))
            p.nodo(etiqueta("link-vencido"))
            foto("02-link-vencido")
            p.tocar(etiqueta("ver-demo"))
            p.nodo(texto("Estás viendo la demo"))
            foto("03-demo-entreno")
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.454"))
            foto("04-demo-dieta")
            p.tocar(etiqueta("ver-fuentes"))
            p.nodo(texto("Cómo se calcula tu objetivo de calorías"))
            foto("05-fuentes")
            p.tocar(etiqueta("fuentes-listo"))
            p.esperarQueNoEste(etiqueta("hoja-fuentes"))
            p.tocar(etiqueta("salir-demo"))
            p.nodo(etiqueta("ver-demo"))
            entrarConLaCuenta()
            p.esperar("los badges") { "1" in p.textosBajo(etiqueta("pestana-chat")) && "2" in p.textosBajo(etiqueta("pestana-revision")) }
            foto("06-cuenta-entreno")
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.373"))
            p.nodo(etiqueta("banner-revision"))
            foto("07-cuenta-dieta")
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(textoQueContiene("Semana del"))
            foto("08-cuenta-revision")
            p.tocar(etiqueta("mis-datos"))
            p.nodo(etiqueta("tema-oscuro"))
            foto("09-cuenta-mis-datos")
        }.close()

        // Sin red con la copia guardada: el plan de la última vez, con el aviso arriba (OFF-06).
        servidor.sinRed = true
        abrir().also {
            p.nodo(etiqueta("banner-sin-conexion"))
            p.tocar(etiqueta("pestana-dieta"))
            p.nodo(texto("2.373"))
            foto("10-sin-red-con-copia")
        }.close()

        // Sin red y sin copia: "Sin conexión" con Reintentar (ACC-05).
        reiniciarEstado()
        guardarCuenta()
        abrir().also {
            p.nodo(etiqueta("sin-conexion"))
            foto("11-sin-conexion")
        }.close()
    }
}
