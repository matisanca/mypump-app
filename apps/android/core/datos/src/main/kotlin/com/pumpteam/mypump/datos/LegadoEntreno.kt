package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.BarraDescanso
import com.pumpteam.mypump.reglas.Descanso
import com.pumpteam.mypump.reglas.Js
import com.pumpteam.mypump.reglas.SustitucionesEntreno
import kotlinx.serialization.json.JsonObject

/**
 * Lo que la app vieja (la Capacitor) dejó del Entreno en curso, como lo lee la migración del almacenamiento viejo (MIG-02):
 * la sesión de cada día (`mypump_sesion_<TOKEN>_<dia>{,_semana,_finalizada,_start}`), el descanso que estaba corriendo
 * (`mypump_rest_<TOKEN>`), el último día que se vio (`mypump_dia_visualizado_<RUTINA>`) y las sustituciones de la rutina
 * (`mypump_exercise_swaps_<RUTINA>`). Gemelo de LegadoEntreno.swift: un lector tolerante y un punto de entrada,
 * [aplicarLegado].
 */
data class LegadoEntreno(
    val sesiones: List<SesionDia> = emptyList(),
    val descanso: Descanso.Guardado? = null,
    val diaVisualizado: String? = null,
    /** En el formato de la web (`exId → {original, current, fijado, semana, diaId}`). */
    val sustituciones: Map<String, ValorJson>? = null,
) {
    data class SesionDia(
        val diaId: String,
        val sesionId: String? = null,
        val semana: Int? = null,
        /** `_start` (ms desde 1970). */
        val inicio: Double? = null,
        /** `_finalizada === '1'` */
        val finalizada: Boolean = false,
    )

    val vacio: Boolean get() = sesiones.isEmpty() && descanso == null && diaVisualizado == null && sustituciones.isNullOrEmpty()

    companion object {
        /** Las claves crudas del localStorage viejo (clave → valor, como las lee la migración). */
        fun desdeAlmacenamiento(claves: Map<String, String>, token: String, rutinaId: String): LegadoEntreno {
            val porDia = LinkedHashMap<String, SesionDia>()
            val prefijo = "mypump_sesion_${token}_"
            for ((k, v) in claves) {
                if (!k.startsWith(prefijo)) continue
                var dia = k.removePrefix(prefijo)
                var campo = ""
                for (sufijo in listOf("_semana", "_start", "_finalizada")) {
                    if (dia.endsWith(sufijo)) {
                        campo = sufijo
                        dia = dia.removeSuffix(sufijo)
                    }
                }
                if (dia.isEmpty()) continue
                val s = porDia[dia] ?: SesionDia(dia)
                porDia[dia] = when (campo) {
                    "_semana" -> s.copy(semana = Js.parseInt(v)?.takeIf { it.isFinite() && Math.abs(it) < 1e15 }?.let(::enteroTruncado))
                    "_start" -> s.copy(inicio = Js.parseInt(v)?.takeIf { it > 0 })
                    "_finalizada" -> s.copy(finalizada = v == "1")
                    else -> s.copy(sesionId = Js.verdadero(v))
                }
            }
            val descanso = claves["mypump_rest_$token"]?.let { r ->
                try {
                    Descanso.Guardado.desde(ValorJson.parsear(r))
                } catch (_: Exception) {
                    null
                }
            }
            val sustituciones = claves["mypump_exercise_swaps_$rutinaId"]?.let { s ->
                try {
                    (ValorJson.parsear(s) as? ValorJson.Objeto)?.campos
                } catch (_: Exception) {
                    null
                }
            }
            return LegadoEntreno(
                sesiones = porDia.values.sortedBy { it.diaId },
                descanso = descanso,
                diaVisualizado = Js.verdadero(claves["mypump_dia_visualizado_$rutinaId"]),
                sustituciones = sustituciones,
            )
        }

        /**
         * `legado-entreno.json` del disco de la cuenta. Acepta las claves crudas (`{"mypump_sesion_…": "…", …}` o
         * `{"claves": {…}}`) o la forma por día: `{"dias": {"d1": {"sesionId", "_semana" | "semana", "_start" | "inicio",
         * "_finalizada" | "finalizada"}}, "descanso": {"endsAt", "target", "autoCloseAt"}, "diaVisualizado", "sustituciones"}`.
         *
         * También la que deja la migración ([EntrenoLegado], [EjecutorLegado]): `"sesiones"` en vez de `"dias"`, el arranque
         * en `"start"` y `"diaVisualizado"` por rutina (`{rutinaId: diaId}`).
         */
        fun leer(disco: Disco, token: String, rutinaId: String): LegadoEntreno? {
            val o = (disco.leer(ModeloEntreno.Archivo.LEGADO) as? JsonObject)?.let { ValorJson.desde(it) as ValorJson.Objeto }?.campos ?: return null
            fun textos(m: Map<String, ValorJson>): Map<String, String> = m.mapNotNull { (k, x) ->
                val v = when (x) {
                    is ValorJson.Texto -> x.valor
                    is ValorJson.Numero -> Js.texto(x.valor)
                    is ValorJson.Booleano -> if (x.valor) "1" else null
                    is ValorJson.Objeto, is ValorJson.Lista -> x.serializar()
                    ValorJson.Nulo -> null
                }
                v?.let { k to it }
            }.toMap()
            (o["claves"] as? ValorJson.Objeto)?.let { return desdeAlmacenamiento(textos(it.campos), token, rutinaId) }
            if (o.keys.any { it.startsWith("mypump_") }) return desdeAlmacenamiento(textos(o), token, rutinaId)
            val sesiones = mutableListOf<SesionDia>()
            ((o["dias"] ?: o["sesiones"]) as? ValorJson.Objeto)?.campos?.forEach { (dia, x) ->
                val d = x as? ValorJson.Objeto ?: return@forEach
                fun numero(k: String): Double? = when (val v = d[k]) {
                    is ValorJson.Numero -> v.valor
                    is ValorJson.Texto -> Js.parseInt(v.valor)
                    else -> null
                }
                val fin = d["_finalizada"] ?: d["finalizada"]
                sesiones += SesionDia(
                    diaId = dia,
                    sesionId = (d["sesionId"] ?: d["_sesionId"])?.comoTexto,
                    semana = (numero("_semana") ?: numero("semana"))?.takeIf { it.isFinite() && Math.abs(it) < 1e15 }?.let(::enteroTruncado),
                    inicio = (numero("_start") ?: numero("inicio") ?: numero("start"))?.takeIf { it > 0 },
                    finalizada = fin == ValorJson.Booleano(true) || fin == ValorJson.Texto("1") || fin == ValorJson.Numero(1.0),
                )
            }
            return LegadoEntreno(
                sesiones = sesiones.sortedBy { it.diaId },
                descanso = o["descanso"]?.let { Descanso.Guardado.desde(it) },
                diaVisualizado = when (val d = o["diaVisualizado"]) {
                    is ValorJson.Objeto -> d[rutinaId]?.comoTexto
                    else -> d?.comoTexto
                },
                sustituciones = (o["sustituciones"] as? ValorJson.Objeto)?.campos,
            )
        }
    }
}

/**
 * Lo del almacenamiento viejo, SIN pisar lo que la nativa ya sabe: la sesión de un día solo si no tiene una local; el
 * descanso solo si no hay uno; el día que se veía, solo si este teléfono todavía no eligió; las sustituciones solo si no
 * hay ninguna. La sesión se CONFIRMA con el servidor al restaurar (SES-02): una vieja que el servidor ya archivó se
 * descarta, sin sesiones fantasma. Se puede llamar antes o después de `cargar()`.
 */
suspend fun ModeloEntreno.aplicarLegado(l: LegadoEntreno) {
    var huboSesion = false
    for (s in l.sesiones) {
        if (tieneSesionLocal(s.diaId) || (s.sesionId == null && s.inicio == null)) continue
        ponerSesionLocal(s.diaId, ModeloEntreno.SesionLocal(Js.verdadero(s.sesionId), s.semana, s.finalizada, s.inicio))
        huboSesion = huboSesion || s.diaId == dia.value.dia.id
    }
    guardarSesiones()
    val sustituciones = l.sustituciones
    if (!sustituciones.isNullOrEmpty() && dia.value.sustituciones.isEmpty()) {
        ponerSustituciones(SustitucionesEntreno.compat(sustituciones))
        guardarSustituciones()
        podarSustituciones()
    }
    // Primero el día y después el descanso, como la web al abrir: arranca en el último día visto y recién ahí
    // `restoreRest()`. Cambiar de día detiene el descanso (`cambiarDia` → `stopRest()`), así que al revés el descanso que
    // venía corriendo se perdía (lo encontró la prueba de punta a punta en el emulador; en iOS, 5eb8738).
    var cambioDeDia = false
    val visto = Js.verdadero(l.diaVisualizado)
    if (!diaGuardadoAlArrancar && visto != null && visto != dia.value.dia.id && dias.any { it.id == visto }) {
        diaGuardadoAlArrancar = true
        cambiarDia(visto)
        cambioDeDia = true
    }
    val g = l.descanso
    if (descanso.value.descanso == null && descanso.value.guardado == null && g != null) {
        reemplazarDescanso(BarraDescanso(g).also { it.restaurar(ahoraMs) })
        guardarDescanso()
    }
    if (!cambioDeDia && huboSesion && dia.value.sesionId == null) restaurarSesion()
}

/** Lee `legado-entreno.json` del disco de la cuenta, lo aplica y lo borra (para no aplicarlo dos veces). */
suspend fun ModeloEntreno.aplicarLegadoDelDisco(): Boolean {
    val d = discoDeLaCuenta ?: return false
    val t = token ?: return false
    val l = LegadoEntreno.leer(d, t, rutina.value.id) ?: return false
    aplicarLegado(l)
    d.borrar(ModeloEntreno.Archivo.LEGADO)
    return true
}
