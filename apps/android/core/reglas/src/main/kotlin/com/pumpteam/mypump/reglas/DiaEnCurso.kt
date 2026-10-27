package com.pumpteam.mypump.reglas

import com.pumpteam.mypump.modelos.Dia
import com.pumpteam.mypump.modelos.Ejercicio
import com.pumpteam.mypump.modelos.EstadoEjercicio
import com.pumpteam.mypump.modelos.RegistroHistorico
import com.pumpteam.mypump.modelos.RegistroSesion
import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import java.time.ZoneId

/**
 * El día que se está entrenando: lo que en la web es `STATE.session`, `STATE.exerciseStates`, `STATE.exerciseMeta`,
 * `STATE.expandedId`, `DATA.historico_por_ejercicio` y `STATE.exerciseSwaps`, con las acciones de la card (confirmar una
 * serie, marcar completo, "Terminé este ejercicio", reabrir, el lápiz, el RIR, la variante, abrir la card, sustituir y
 * volver). Es puro, como DiaEnCurso.swift: lo que necesita de afuera (la cola, el descanso, el historial, la sesión del
 * servidor) lo devuelve como [Efecto]s, en el orden en que la web los hace, y `ModeloEntreno` los ejecuta. Así los
 * vectores de `confirmarSerie` y de los handlers de `bindTrainEvents` se prueban sin red.
 *
 * En Swift es un struct; acá se muta en el lugar y [copia] da otro igual (el modelo publica una copia nueva en cada
 * cambio, para que la pantalla se entere).
 */
class DiaEnCurso(
    dia: Dia,
    /** `DATA.rutina.semana_actual || 1` */
    var semana: Int,
    /** Sin rutina real (demo): no se escribe nada. */
    val demo: Boolean = false,
    var sesionId: String? = null,
    /** La sesión del día está cerrada (`finalizada_en`): el día cuenta como hecho. */
    var diaFinalizado: Boolean = false,
    estados: Map<String, String> = emptyMap(),
    val zona: ZoneId = ZoneId.systemDefault(),
) {
    var dia: Dia = dia

    /** Por id del LUGAR (`slug-d<n>-<i>`). */
    var ejercicios: Map<String, EjercicioEnSesion> = armar(dia, semana, estados)
    var estados: Map<String, String> = estados
    var meta: Map<String, MetaEstado> = emptyMap()

    /** La card abierta. */
    var expandido: String? = null

    /** El historial por clave del ejercicio efectivo, guardado por lugar. Sin entrada = sin pedir (o falló la red). */
    var historial: Map<String, List<RegistroHistorico>> = emptyMap()

    /** Las sustituciones, en el formato de la web (ver [SustitucionesEntreno]). */
    var sustituciones: Map<String, ValorJson> = emptyMap()

    data class MetaEstado(val seriesCompletadas: Int, val manual: Boolean)

    /** Lo que la app tiene que hacer después de una acción. */
    sealed interface Efecto {
        /** Una escritura a la cola (`carga` o `estado`). */
        data class Encolar(val kind: String, val payload: ValorJson, val clave: String) : Efecto

        /** `startRest(segundos)` */
        data class IniciarDescanso(val segundos: Double) : Efecto

        /** `stopRest()` */
        data object DetenerDescanso : Efecto

        /** `ensureSesionIniciada()` sin esperar (la serie entra a la cola ya; la cola resuelve la sesión al mandar). */
        data object AsegurarSesion : Efecto

        /** `loadHistorico(exId)` */
        data class PedirHistorial(val lugar: String) : Efecto

        /** `marcarLeidosEjercicio(exId)` */
        data class MarcarLeidos(val lugar: String) : Efecto

        /** Guardar las sustituciones en disco. */
        data object GuardarSustituciones : Efecto

        /** Se reabrió el día cerrado: se borra la marca local de "cerrado". */
        data object ReabrioDia : Efecto

        /** Todos los ejercicios en un estado terminal: "🎉 ¡Día completado!" (medio segundo después, una sola vez). */
        data object DiaCompleto : Efecto
    }

    fun copia(): DiaEnCurso = DiaEnCurso(dia, semana, demo, sesionId, diaFinalizado, emptyMap(), zona).also {
        it.ejercicios = ejercicios
        it.estados = estados
        it.meta = meta
        it.expandido = expandido
        it.historial = historial
        it.sustituciones = sustituciones
    }

    // ── Lecturas ──

    /** Los ejercicios del día, en orden (`DATA.dia.bloques.flatMap(b => b.ejercicios)`). */
    val lista: List<Ejercicio> get() = dia.bloques.flatMap { it.ejercicios }

    /** El ejercicio del PLAN en ese lugar (el primero con ese id). */
    fun ejercicio(id: String): Ejercicio? = lista.firstOrNull { it.id == id }

    /** `getExStatus` */
    fun estado(id: String): String = Js.verdadero(ejercicios[id]?.estado) ?: Js.verdadero(estados[id]) ?: "pendiente"

    /** El ejercicio que se hace en el lugar: el sustituto, si hay; si no, el del plan. Es el nombre que se registra. */
    fun nombreEfectivo(id: String): String? = SustitucionesEntreno.aplicada(sustituciones[id])?.nombre ?: ejercicio(id)?.nombre

    /**
     * El selector de agarre o nivel que muestra la tarjeta: el del ejercicio que se hace, no el del plan. Desvío a propósito
     * de la web (revisión del 21-oct): ahí el agarre del plan se grababa en las notas y filtraba el historial también con un
     * sustituto sin ese selector (la extensión en polea con Soga → fondos: «Fondos» con notas «Soga»).
     */
    fun variantesVisibles(id: String): VariantesEjercicio? = ReglasEjercicio.variantes(nombreEfectivo(id))

    /**
     * `_varianteActiva`: la elegida y si es la default (las filas viejas sin nota cuentan solo para esa). Con el lugar
     * sustituido por un ejercicio sin ese selector, el agarre del plan no filtra su historial (ver [variantesVisibles]).
     */
    fun varianteActiva(id: String): Pair<String?, Boolean> {
        val v = Js.verdadero(ejercicios[id]?.variante) ?: return null to false
        val ops = variantesVisibles(id)?.opciones
        if (ops == null && SustitucionesEntreno.aplicada(sustituciones[id]) != null) return null to false
        return v to (ops != null && ops.firstOrNull() == v)
    }

    fun pauta(id: String): Pauta? = ejercicio(id)?.let { Progresiones.pauta(it, semana) }

    /** `suggestedKg` */
    fun kgUltimaVez(id: String, idx: Int): String {
        val (v, d) = varianteActiva(id)
        // `if (ex && !exNoKg(ex)) return ''`: sin el ejercicio, el 0 se devuelve.
        val sinKgPlan = ejercicio(id)?.let(ReglasEjercicio::sinKg) ?: true
        return HistorialEntreno.kgSugerido(historial[id] ?: emptyList(), idx, v, d, sinKgPlan, zona)
    }

    /** `suggestedReps` */
    fun repsUltimaVez(id: String, idx: Int): String {
        val (v, d) = varianteActiva(id)
        return HistorialEntreno.repsSugeridas(historial[id] ?: emptyList(), idx, v, d, zona)
    }

    /**
     * `kgHeredable`, pero solo de las series registradas con el mismo ejercicio que esta: el que se hace ahora o, si se
     * corrige con el lápiz una serie registrada con otro, ese. Desvío a propósito de la web (revisión del 21-oct): al cambiar
     * de movimiento a mitad del ejercicio (2 series de extensión en polea a 30 kg y después fondos), la serie 3 heredaba los
     * 30 kg de la polea y se grababa como fondos. Sin nombre registrado (una serie de antes de esto) cuenta como del que se
     * hace ahora. Compara por el nombre (la clave del historial) y no por el movimiento, a propósito: dentro del mismo gesto
     * el kg también cambia (a una mano o a dos, otro equipo), y con el ✓ de un toque un kg heredado de otro ejercicio termina
     * grabado.
     */
    fun kgHeredable(id: String, idx: Int): String {
        val series = ejercicios[id]?.series ?: emptyList()
        val actual = nombreEfectivo(id)
        fun clave(s: SerieLocal) = ClaveEjercicio.de(Js.verdadero(s.nombreRegistrado) ?: actual)
        val esta = series.getOrNull(idx)?.let(::clave) ?: ClaveEjercicio.de(actual)
        return HistorialEntreno.kgHeredable(series.map { if (clave(it) == esta) it else SerieLocal() }, idx)
    }

    /** La serie es del ejercicio que se hace ahora: sin nombre registrado (no se sabe con cuál se hizo) o con el mismo. */
    internal fun esDelEjercicioActual(id: String, s: SerieLocal): Boolean =
        Js.verdadero(s.nombreRegistrado)?.let { ClaveEjercicio.de(it) == ClaveEjercicio.de(nombreEfectivo(id)) } ?: true

    /** "🏆 Récord a superar" (`lastSessionStr`); null es "Primera vez con este ejercicio". */
    fun record(id: String): String? = HistorialEntreno.record(historial[id] ?: emptyList())

    /** "📅 Última vez (…)" (`prevSessionStr`). */
    fun ultimaVez(id: String, ahora: Instant): UltimaVez? = HistorialEntreno.ultimaVez(historial[id] ?: emptyList(), ahora, zona)

    /**
     * La fila de una serie (`renderSetRow`). `efectivo` es lo que se muestra (el sustituto, si hay): decide la columna de
     * kg y las reps del plan; la variante y la regla del 0 salen del ejercicio del plan, como en la web.
     */
    fun fila(id: String, idx: Int, efectivo: Ejercicio? = null): FilaSerie? {
        val e = ejercicios[id] ?: return null
        if (idx < 0 || idx >= e.series.size) return null
        val plan = ejercicio(id) ?: return null
        val ef = efectivo ?: plan
        return FilaSerie.armar(
            e.series[idx], activa = e.series.indexOfFirst { !it.confirmada } == idx, sinKg = ReglasEjercicio.sinKg(ef),
            repsPlan = Progresiones.pauta(ef, semana).reps, kgUltimaVez = kgUltimaVez(id, idx),
            repsUltimaVez = repsUltimaVez(id, idx), kgHeredable = kgHeredable(id, idx),
        )
    }

    /** `checkIfDayCompleted` */
    val diaCompleto: Boolean get() = EstadosEjercicio.diaCompleto(lista.map { it.id }, ::estado)

    /** Hechos (en un estado terminal) y total, como el pie y la barra de progreso. */
    val hechos: Int get() = lista.count { estado(it.id) in EstadosEjercicio.terminales }

    /** Series, reps y volumen de lo confirmado hoy. */
    val resumen: ResumenDia
        get() {
            val vistos = HashSet<String>()
            return ResumenDia(lista.mapNotNull { if (vistos.add(it.id)) ejercicios[it.id] else null })
        }

    /** Los ejercicios sin un estado terminal. */
    val cantidadPendientes: Int get() = lista.count { estado(it.id) !in EstadosEjercicio.terminales }

    /** Para el modal de cierre anticipado: hasta 3 pendientes (con el nombre del plan) y "y N más…". */
    val pendientes: List<String>
        get() {
            val p = lista.filter { estado(it.id) !in EstadosEjercicio.terminales }.map { it.nombre }
            return if (p.size > 3) p.take(3) + "y ${p.size - 3} más…" else p
        }

    /** "Quedan 5 ejercicios sin completar:" (null sin pendientes). */
    val avisoPendientes: String?
        get() {
            val n = cantidadPendientes
            return if (n > 0) "Quedan $n ejercicio${if (n > 1) "s" else ""} sin completar:" else null
        }

    // ── Acciones ──

    /** Lo que el cliente ya contestó en esta confirmación (null = todavía no se le preguntó). */
    data class Respuestas(
        /** "Este día ya lo cerraste": "Reabrir día". */
        val reabrir: Boolean? = null,
        /** "¿Está bien cargado?": "Sí, registrar". */
        val registrarIgual: Boolean? = null,
    )

    /**
     * Un paso de una acción que puede tener que preguntar: los efectos hasta acá y, si hace falta, la pregunta. Se vuelve
     * a llamar con la respuesta (así nada queda esperando al cliente con el día "abierto" para escribir).
     */
    data class Paso(val efectos: List<Efecto> = emptyList(), val pregunta: Pregunta? = null, val motivo: Motivo? = null) {
        enum class Motivo { REABRIR, REGISTRAR_IGUAL }
    }

    /**
     * `confirmarSerie` (SER-01/03/05): con el día cerrado pregunta si se reabre; sin editar es "lo de la última vez"; lo
     * imposible se rechaza y lo raro se pregunta; confirmada, entra a la cola YA y arranca el descanso (salvo el
     * calentamiento). Con la última serie el ejercicio pasa a completo y se abre el siguiente pendiente (ENT-17). Si
     * devuelve una pregunta, se vuelve a llamar con la respuesta en `respuestas`.
     */
    fun confirmarSerie(id: String, idx: Int, respuestas: Respuestas = Respuestas(), efectivo: Ejercicio? = null): Paso {
        val e = ejercicios[id] ?: return Paso()
        if (idx < 0 || idx >= e.series.size || e.series[idx].confirmada) return Paso()
        val ex = ejercicio(id) ?: return Paso()
        val efectos = mutableListOf<Efecto>()
        if (diaFinalizado) {
            val reabrir = respuestas.reabrir ?: return Paso(pregunta = PREGUNTA_REABRIR, motivo = Paso.Motivo.REABRIR)
            if (!reabrir) return Paso()
            diaFinalizado = false
            efectos += Efecto.ReabrioDia
        }
        // `efectivo` es lo que se muestra (el sustituto, si hay): de ahí sale si la serie lleva kg, como en la fila. La web
        // usa el del plan y con un sustituto de otra clase (Crunch → Crunch en polea) borraba el kg o no dejaba registrar
        // (revisión del 14-oct, hallazgo 1).
        // Una serie registrada con OTRO ejercicio (el lápiz después de sustituir) se evalúa contra el suyo: si lleva kg, los
        // topes y la pauta. El historial que hay es el del que se hace ahora: ni lo de la última vez ni su récord le sirven.
        // Revisión del 21-oct: de crunch en máquina a plancha, reconfirmar una serie del crunch le borraba el kg.
        val propia = esDelEjercicioActual(id, e.series[idx])
        val registrado = Js.verdadero(e.series[idx].nombreRegistrado)
        val deLaSerie = if (!propia && registrado != null) ex.copy(nombre = registrado) else efectivo ?: ex
        // Y si esa serie de otro ejercicio ya tiene kg, lo conserva: solo se registra kg en los que lo llevan (`completar`
        // lo pide o lo vacía), y el equipo del sustituto no queda en la base. Sin esto, el lápiz y el ✓ sobre una serie del
        // crunch con soga del catálogo (sale «Crunch», lleva kg por su equipo), ya de vuelta al original, le borraban el kg
        // (27-oct).
        val sinKg = ReglasEjercicio.sinKg(deLaSerie) && (propia || e.series[idx].kg.isEmpty())
        val prog = Progresiones.pauta(deLaSerie, semana)
        val repsUlt = if (propia) repsUltimaVez(id, idx) else ""
        val (serie, completa) = ConfirmacionSerie.completar(
            e.series[idx], sinKg, prog.reps, if (propia) kgUltimaVez(id, idx) else "", repsUlt, kgHeredable(id, idx),
        )
        cambiarSerie(id, idx) { serie }
        if (!completa) return Paso(efectos)
        val evaluacion = Verosimilitud.evaluar(
            serie.reps, serie.kg, sinKg, if (propia) HistorialEntreno.recordKg(historial[id] ?: emptyList()) else 0.0, repsUlt, prog.reps,
        )
        when (evaluacion) {
            Verosimilitud.Resultado.Ok -> {}
            is Verosimilitud.Resultado.Rechazada -> {
                cambiarSerie(id, idx) { it.copy(aviso = evaluacion.aviso) }
                return Paso(efectos)
            }
            is Verosimilitud.Resultado.Preguntar -> {
                val registrar = respuestas.registrarIgual
                    ?: return Paso(efectos, evaluacion.pregunta, Paso.Motivo.REGISTRAR_IGUAL)
                if (!registrar) {
                    cambiarSerie(id, idx) { it.copy(aviso = "") }   // la fila queda marcada, sin texto
                    return Paso(efectos)
                }
            }
        }
        // La variante va solo si el ejercicio que se hace muestra ese selector, y la serie anota con qué ejercicio se registró
        // (el `ejercicioNombre` de la carga) para que el kg heredado no cruce de un ejercicio a otro. Una serie ya registrada
        // con OTRO ejercicio (el lápiz después de sustituir) conserva el suyo y su variante: se corrige lo que se hizo.
        // Desvíos a propósito de la web (revisión del 21-oct; ver [variantesVisibles], [kgHeredable] y
        // [EscriturasEntreno.nombre]).
        val variante = if (variantesVisibles(id) == null) null else Js.verdadero(ejercicios.getValue(id).variante)
        val sustituto = SustitucionesEntreno.aplicada(sustituciones[id])?.nombre
        cambiarSerie(id, idx) {
            it.copy(
                aviso = null,
                confirmada = true,
                varianteRegistrada = if (esDelEjercicioActual(id, it)) variante else it.varianteRegistrada,
                nombreRegistrado = EscriturasEntreno.nombre(sustituto, it, ex.nombre),
            )
        }
        efectos += Efecto.AsegurarSesion
        efectos += escribirSerie(id, idx)
        if (ex.tipo != "calentamiento") {
            efectos += Efecto.IniciarDescanso((ex.descansoSegundos ?: NormalizacionRutina.DESCANSO_POR_DEFECTO).toDouble())
        }
        if (ejercicios.getValue(id).series.all { it.confirmada } && estado(id) == "pendiente") {
            efectos += cambiarEstado(id, "completo", manual = false)
            actualizar(id) { it.copy(completo = true) }
            siguientePendiente(id)?.let { sig ->
                expandido = sig
                // El historial se pide ya, para que "Siguiente" abra con el sugerido, el récord y la última vez. Los
                // comentarios NO se marcan leídos: con D13 la card no se abre sola, y el 💬 se iba sin que el cliente
                // lo viera (la web sí los marca porque la abre). Se marcan al abrirla (`tocarCard`).
                if (historial[sig] == null) efectos += Efecto.PedirHistorial(sig)
            }
        }
        if (!demo && diaCompleto) efectos += Efecto.DiaCompleto
        return Paso(efectos)
    }

    /** "Marcar ejercicio completo": solo con todas las series confirmadas. */
    fun marcarCompleto(id: String): List<Efecto> {
        val e = ejercicios[id] ?: return emptyList()
        if (!e.series.all { it.confirmada }) return emptyList()
        val efectos = cambiarEstado(id, "completo", manual = false).toMutableList()
        actualizar(id) { it.copy(completo = true) }
        siguientePendiente(id)?.let { expandido = it }
        efectos += Efecto.DetenerDescanso
        if (!demo && diaCompleto) efectos += Efecto.DiaCompleto
        return efectos
    }

    /** "Terminé este ejercicio" (SER-15), primera parte: sin series confirmadas hay que preguntar. */
    fun preguntaTerminar(id: String): Pregunta? {
        val e = ejercicios[id] ?: return null
        return if (e.series.none { it.confirmada }) PREGUNTA_TERMINAR_SIN_DATOS else null
    }

    /**
     * "Terminé este ejercicio", ya contestada la pregunta y con la sesión asegurada (la web la espera antes): queda
     * `completo` (o `completo_sin_datos` sin series), marcado a mano.
     */
    fun terminar(id: String): List<Efecto> {
        val e = ejercicios[id] ?: return emptyList()
        val confirmadas = e.series.count { it.confirmada }
        val efectos = cambiarEstado(id, if (confirmadas > 0) "completo" else "completo_sin_datos", manual = true).toMutableList()
        actualizar(id) { it.copy(completo = true) }
        siguientePendiente(id)?.let { expandido = it }
        efectos += Efecto.DetenerDescanso
        if (!demo && diaCompleto) efectos += Efecto.DiaCompleto
        return efectos
    }

    /** "Reabrir ejercicio" */
    fun reabrir(id: String): List<Efecto> {
        if (ejercicios[id] == null) return emptyList()
        val efectos = cambiarEstado(id, "pendiente", manual = false)
        actualizar(id) { it.copy(completo = false) }
        return efectos
    }

    /** El lápiz (SER-06): desconfirma la serie; si el ejercicio estaba completo, vuelve a pendiente. */
    fun editarSerie(id: String, idx: Int): List<Efecto> {
        val e = ejercicios[id] ?: return emptyList()
        if (idx < 0 || idx >= e.series.size) return emptyList()
        cambiarSerie(id, idx) { it.copy(confirmada = false) }
        actualizar(id) { it.copy(completo = false) }
        return if (estado(id) == "completo") cambiarEstado(id, "pendiente", manual = false) else emptyList()
    }

    /** Lo que se tipea en un campo (SER-04): normalizado; borra el aviso de la fila. */
    fun escribir(id: String, idx: Int, campo: String, valor: String) {
        val e = ejercicios[id] ?: return
        if (idx < 0 || idx >= e.series.size) return
        val v = CamposSerie.normalizar(campo, valor)
        cambiarSerie(id, idx) {
            when (campo) {
                "reps" -> it.copy(reps = v, aviso = null)
                "kg" -> it.copy(kg = v, aviso = null)
                else -> it.copy(rir = v, aviso = null)
            }
        }
    }

    /** La variante (SER-07): vale para las series que se confirmen DESPUÉS. */
    fun elegirVariante(id: String, v: String) {
        if (ejercicios[id] == null) return
        actualizar(id) { it.copy(variante = v) }
    }

    /** El RIR 0-5 (SER-02): si la serie ya estaba confirmada, se vuelve a mandar (la RPC es upsert). */
    fun elegirRir(id: String, idx: Int, v: String): List<Efecto> {
        val e = ejercicios[id] ?: return emptyList()
        if (idx < 0 || idx >= e.series.size) return emptyList()
        cambiarSerie(id, idx) { it.copy(rir = v) }
        return if (e.series[idx].confirmada) escribirSerie(id, idx) else emptyList()
    }

    /** Abrir o cerrar la card: al abrir se pide el historial (si no está) y se marcan leídos los comentarios (SES-08). */
    fun tocarCard(id: String): List<Efecto> {
        val estaba = expandido == id
        expandido = if (estaba) null else id
        if (estaba) return emptyList()
        val efectos = mutableListOf<Efecto>()
        if (historial[id] == null) efectos += Efecto.PedirHistorial(id)
        efectos += Efecto.MarcarLeidos(id)
        return efectos
    }

    /** Sustituir (SER-11/13): el lugar pasa a ser OTRO ejercicio, con su historial. */
    fun sustituir(id: String, sub: SustitutoEjercicio, efectivo: EjercicioEfectivo, fijado: Boolean): List<Efecto> {
        sustituciones = sustituciones + (id to SustitucionesEntreno.nueva(sub, efectivo, fijado, semana, dia.id ?: ""))
        historial = historial - id
        return listOf(Efecto.GuardarSustituciones, Efecto.PedirHistorial(id))
    }

    /** "Volver a …": el lugar vuelve al original, y su historial también. */
    fun revertir(id: String): List<Efecto> {
        sustituciones = sustituciones - id
        historial = historial - id
        return listOf(Efecto.GuardarSustituciones, Efecto.PedirHistorial(id))
    }

    // ── Restaurar (lo que trae el servidor) ──

    /** `loadExerciseStates` */
    fun aplicarEstados(filas: List<EstadoEjercicio>) {
        for (f in filas) {
            estados = estados + (f.ejercicioId to f.status)
            meta = meta + (f.ejercicioId to MetaEstado(f.seriesCompletadas ?: 0, f.marcadoManualmente))
            if (ejercicios[f.ejercicioId] == null) continue
            actualizar(f.ejercicioId) {
                val completo = it.completo || f.status == "completo" || f.status == "completo_sin_datos"
                it.copy(estado = f.status, completo = completo)
            }
        }
    }

    /**
     * `loadRegistrosCarga`: las series guardadas, sin pisar las que ya se confirmaron en el teléfono. La variante vuelve
     * de `notas` (SER-07) y la serie recuerda con qué nombre y variante se registró.
     */
    fun aplicarRegistros(filas: List<RegistroSesion>) {
        for (r in filas) {
            val e = ejercicios[r.ejercicioId] ?: continue
            val i = r.serie - 1
            if (i < 0 || i >= e.series.size || e.series[i].confirmada) continue
            val notas = Js.verdadero(r.notas)
            val series = e.series.toMutableList()
            series[i] = series[i].copy(
                kg = r.pesoKg?.let(Js::texto) ?: "",
                reps = r.reps?.toString() ?: "",
                rir = r.rir?.toString() ?: "",
                confirmada = true,
                nombreRegistrado = Js.verdadero(r.ejercicioNombre),
                varianteRegistrada = notas,
            )
            val conVariante = notas != null && ejercicio(r.ejercicioId)?.let { ReglasEjercicio.variantes(it.nombre) } != null
            ejercicios = ejercicios + (r.ejercicioId to e.copy(series = series, variante = if (conVariante) notas else e.variante))
        }
    }

    // ── Internas ──

    /** `setExStatus` + `writeExerciseStatus`. */
    internal fun cambiarEstado(id: String, status: String, manual: Boolean): List<Efecto> {
        estados = estados + (id to status)
        if (ejercicios[id] != null) actualizar(id) { it.copy(estado = status) }
        if (demo) return emptyList()
        val objetivo = ejercicio(id)?.let { Progresiones.pauta(it, semana).series } ?: 0
        val d = dia.id ?: ""
        return listOf(
            Efecto.Encolar(
                "estado",
                EscriturasEntreno.estado(sesionId, semana, d, id, objetivo, status, manual),
                EscriturasEntreno.claveEstado(d, id, semana),
            ),
        )
    }

    /** `writeSet` */
    internal fun escribirSerie(id: String, idx: Int): List<Efecto> {
        if (demo) return emptyList()
        val ex = ejercicio(id) ?: return emptyList()
        val e = ejercicios[id] ?: return emptyList()
        if (idx >= e.series.size) return emptyList()
        val s = e.series[idx]
        val nombre = EscriturasEntreno.nombre(SustitucionesEntreno.aplicada(sustituciones[id])?.nombre, s, ex.nombre)
        // La variante del ejercicio solo completa una serie de ESTE ejercicio y con el selector a la vista: una de otro
        // (registrada antes de sustituir o de volver) va con la suya o sin ninguna.
        val variante = if (esDelEjercicioActual(id, s) && variantesVisibles(id) != null) e.variante else null
        val d = dia.id ?: ""
        return listOf(
            Efecto.Encolar(
                "carga",
                EscriturasEntreno.carga(sesionId, d, semana, id, idx, s, nombre, variante),
                EscriturasEntreno.claveCarga(d, id, idx, semana),
            ),
        )
    }

    internal fun siguientePendiente(id: String): String? = EstadosEjercicio.siguientePendiente(lista.map { it.id }, id, ::estado)

    private fun actualizar(id: String, f: (EjercicioEnSesion) -> EjercicioEnSesion) {
        val e = ejercicios[id] ?: return
        ejercicios = ejercicios + (id to f(e))
    }

    private fun cambiarSerie(id: String, idx: Int, f: (SerieLocal) -> SerieLocal) {
        actualizar(id) { e -> e.copy(series = e.series.toMutableList().also { it[idx] = f(it[idx]) }) }
    }

    companion object {
        /** `buildSession`: tantas series vacías como pide la semana, el estado que se conozca y la primera variante. */
        fun armar(dia: Dia, semana: Int, estados: Map<String, String>): Map<String, EjercicioEnSesion> {
            val s = LinkedHashMap<String, EjercicioEnSesion>()
            for (ex in dia.bloques.flatMap { it.ejercicios }) {
                val n = maxOf(0, Progresiones.pauta(ex, semana).series ?: 0)
                s[ex.id] = EjercicioEnSesion(
                    series = List(n) { SerieLocal() }, completo = false,
                    estado = Js.verdadero(estados[ex.id]) ?: "pendiente",
                    variante = ReglasEjercicio.variantes(ex.nombre)?.opciones?.firstOrNull(),
                )
            }
            return s
        }

        val PREGUNTA_REABRIR = Pregunta(
            titulo = "Este día ya lo cerraste",
            cuerpo = "Lo marcaste como terminado. ¿Querés reabrirlo para seguir cargando series?",
            confirmar = "Reabrir día", cancelar = "Dejarlo cerrado",
        )
        val PREGUNTA_TERMINAR_SIN_DATOS = Pregunta(
            titulo = "Terminaste sin cargar datos",
            cuerpo = "No confirmaste ninguna serie. ¿Querés marcar este ejercicio como terminado de todas formas?",
            confirmar = "Sí, terminé", cancelar = "Volver",
        )
    }
}
