package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Ejercicio

// La carga simple dentro del día en curso (2.3.0; gemelo de CargaSimpleDia.swift). Las series siguen siendo las de
// `ejercicios[id].series` y salen por la cola de siempre; la carga única vive aparte, en `cargas`, hasta que un OK la baja a la serie.

/** Lo de afuera que hace falta para armar la carga de un lugar. */
data class ContextoCarga(
    val efectivo: Ejercicio,
    val equipo: Preparacion.Equipo,
    val mensajeSemana: String?,
    /** YYYY-MM-DD local de hoy. */
    val hoy: String,
)

/**
 * Una corrección de una serie ya hecha: nunca la desconfirma, así no queda en un limbo sin registrar. Reescribe esa serie con
 * la misma clave de cola y, sin cambios, no escribe nada.
 */
sealed interface Correccion {
    data object SinCambios : Correccion
    data class Guardada(val efectos: List<DiaEnCurso.Efecto>) : Correccion
    data class Rechazada(val aviso: String) : Correccion
    data class Preguntar(val pregunta: Pregunta) : Correccion
    data object FaltanDatos : Correccion
}

fun DiaEnCurso.claveAumento(id: String): String = "${ClaveEjercicio.de(nombreEfectivo(id))}|$semana"

/** La carga del lugar como se ve ahora. */
fun DiaEnCurso.cargaSimple(id: String, c: ContextoCarga): CargaSimple? {
    val e = ejercicios[id] ?: return null
    val (v, d) = varianteActiva(id)
    val h = historial[id] ?: emptyList()
    val refs = HistorialEntreno.ultimaSesion(h, v, d, c.hoy, zona)
    val sinKg = ReglasEjercicio.sinKg(c.efectivo)
    fun armar(estado: CargaSimple.Estado?): CargaSimple = CargaSimple(
        c.efectivo, semana, refs, c.equipo, sinKg, HistorialEntreno.recordKg(h), mensajeSemana = c.mensajeSemana, seriesLocales = e.series,
        estado = estado, yaAumentadoEstaSemana = claveAumento(id) in aumentosSemana,
    ).also { s ->
        s.varianteActual = if (variantesVisibles(id) == null) null else Js.verdadero(e.variante)
        s.marcarAjenas(e.series.indices.filter { !esDelEjercicioActual(id, e.series[it]) }.toSet())
    }

    // La carga guardada de otro ejercicio (sustituido acá, en otro teléfono o republicado) no vale para este.
    var estado = cargas[id]?.takeIf { it.clave == null || it.clave == ClaveEjercicio.de(nombreEfectivo(id)) } ?: return armar(null)
    // Se tocó algo antes de que llegara el historial (sin base): cuando llega, la carga no puede quedar vacía.
    if (estado.carga == null && estado.cargaUltimaVez == null && estado.aumento == CargaSimple.Aumento.NoCorresponde) {
        val base = armar(null)
        estado = estado.copy(carga = base.carga, cargaUltimaVez = base.cargaUltimaVez, aumento = base.aumento)
    }
    return armar(estado)
}

/** Una acción sobre la carga (subir, aceptar, marcar reps…): guarda el estado resultante. */
fun DiaEnCurso.cambiarCarga(id: String, c: ContextoCarga, accion: (CargaSimple) -> Unit) {
    val s = cargaSimple(id, c) ?: return
    accion(s)
    cargas = cargas + (id to s.estado.copy(clave = ClaveEjercicio.de(nombreEfectivo(id))))
    if (s.aumento is CargaSimple.Aumento.Aceptado || s.aumento == CargaSimple.Aumento.Descartado) aumentosSemana = aumentosSemana + claveAumento(id)
}

fun DiaEnCurso.corregirSerie(id: String, idx: Int, reps: Int, kg: Double?, efectivo: Ejercicio? = null, registrarIgual: Boolean? = null): Correccion {
    val e = ejercicios[id] ?: return Correccion.FaltanDatos
    val s = e.series.getOrNull(idx)?.takeIf { it.confirmada } ?: return Correccion.FaltanDatos
    val ex = ejercicio(id) ?: return Correccion.FaltanDatos
    val propia = esDelEjercicioActual(id, s)
    val registrado = Js.verdadero(s.nombreRegistrado)
    val deLaSerie = if (!propia && registrado != null) ex.copy(nombre = registrado) else efectivo ?: ex
    val sinKg = ReglasEjercicio.sinKg(deLaSerie) && (propia || s.kg.isEmpty())
    if (!sinKg && kg == null) return Correccion.FaltanDatos
    val repsTexto = reps.toString()
    val kgTexto = if (sinKg) "" else kg?.let(Js::texto) ?: ""
    if (repsTexto == s.reps && kgTexto == s.kg) return Correccion.SinCambios
    val prog = Progresiones.pauta(deLaSerie, semana)
    when (
        val r = Verosimilitud.evaluar(
            repsTexto, kgTexto, sinKg, if (propia) HistorialEntreno.recordKg(historial[id] ?: emptyList()) else 0.0,
            if (propia) repsUltimaVez(id, idx) else "", prog.reps,
        )
    ) {
        Verosimilitud.Resultado.Ok -> {}
        is Verosimilitud.Resultado.Rechazada -> return Correccion.Rechazada(r.aviso)
        is Verosimilitud.Resultado.Preguntar -> if (registrarIgual != true) {
            return if (registrarIgual == false) Correccion.SinCambios else Correccion.Preguntar(r.pregunta)
        }
    }
    reescribirSerie(id, idx, repsTexto, kgTexto)
    return Correccion.Guardada(escribirSerie(id, idx))
}
