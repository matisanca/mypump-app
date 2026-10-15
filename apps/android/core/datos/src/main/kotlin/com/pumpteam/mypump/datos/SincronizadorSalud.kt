package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.EntrenoSalud
import com.pumpteam.mypump.reglas.Js
import com.pumpteam.mypump.reglas.PlataformaSalud
import com.pumpteam.mypump.reglas.PuenteSalud
import com.pumpteam.mypump.reglas.RegistroSalud
import com.pumpteam.mypump.reglas.RelojLocal
import com.pumpteam.mypump.reglas.SemanticaJs
import com.pumpteam.mypump.reglas.jsRound
import java.time.Instant
import java.time.ZoneId
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async

/**
 * La sincronización de la salud del teléfono, igual que `window.MyPumpHealth` (healthkit-bridge.js:241-1378) y que
 * SincronizadorSalud.swift:
 *
 * - [conectar]: permisos en dos tandas (núcleo y resto, de a uno si la tanda falla), nunca escritura; después los últimos
 *   7 días y el historial de 60 de fondo.
 * - [sincronizar]: los últimos 7 días (al abrir, al volver y con el botón), en lotes de 300 a `ingest_salud` y de 200 a
 *   `ingest_entrenos`.
 * - [historial]: 60 días en ventanas de 5 con cursor; se retoma si se cortó, con un reintento cada 6 h si no avanza. En
 *   Android sin el permiso de historial de Health Connect, 30 (lo anterior vuelve vacío) y sin darlo por hecho.
 * - "No llega nada" se deduce de los datos: 3 sincronizaciones vacías seguidas, o 60 días sin una muestra.
 *
 * Todo el estado vive en [Preferencias] con las claves de la web. Como el `@MainActor` de iOS, se usa desde UN hilo
 * (el principal, con el [alcance] del ViewModel): la sincronización y el historial se pueden intercalar en cada espera,
 * igual que en el hilo de JS.
 */
class SincronizadorSalud(
    val fuente: FuenteSalud,
    private val cliente: ClienteRpc,
    private val token: String,
    private val almacen: Preferencias,
    private val alcance: CoroutineScope,
    private val ahora: () -> Instant = Instant::now,
    zona: ZoneId = ZoneId.systemDefault(),
    /**
     * Desvío a propósito de la web (el de iOS, 14-oct): la última ventana del historial lee la noche de hoy solo hasta la
     * medianoche y la mandaba igual, pisando el sueño completo que había subido la sincronización de 7 días (470 → 89
     * minutos en el caso `conectar-primera-vez`) hasta la próxima sincronización. Con esto, en el historial se descartan
     * las filas con fecha igual o posterior al cierre de cada ventana. Los vectores de la web lo apagan.
     */
    private val descartarNochesPartidas: Boolean = true,
) {
    val reloj = RelojLocal(zona)
    private val recolector = RecolectorSalud(fuente, reloj)

    /** Avance del historial en curso ("Trayendo tu historial… 40/60 días"); null si no hay uno corriendo. */
    var progresoHistorial: Pair<Int, Int>? = null
        private set(v) {
            field = v
            alCambiarProgreso?.invoke(v)
        }

    /** Cada cambio del avance, el 0/60 del arranque y el null del final incluidos (para la card). */
    var alCambiarProgreso: ((Pair<Int, Int>?) -> Unit)? = null

    /** El historial de fondo en vuelo (`backfillEnCurso()`). */
    var historialEnCurso: Deferred<ResultadoHistorial>? = null
        private set

    /** El último rechazo de la base (lo muestra el diagnóstico). */
    var ultimoErrorIngesta: String? = null
        private set

    /** Hay datos nuevos en la base: la web repinta las cards (`loadSalud` + `loadRecuperacion`). */
    var alCambiar: (() -> Unit)? = null

    /** Cada ventana del historial que termina (`onProgreso`). */
    var alProgresar: ((Int, Int) -> Unit)? = null
    private var silencio = false

    /** Quién tiene el historial en curso (para no pisar el slot de otro al terminar). */
    private var slot: Any? = null

    /**
     * El veredicto del permiso de historial de Health Connect (`_historial`, `historialAndroid()`): null hasta que se pide
     * en esta sesión, y siempre en iOS. Lo que vale entre sesiones es lo guardado ([sinHistorialAndroid]).
     */
    var historialAndroid: HistorialSalud? = null
        private set

    // MARK: Estado

    val conectado: Boolean get() = almacen.leer(ClaveSalud.CONECTADO) == "1"

    /** "No llega nada": una sospecha por falta de datos, no un veredicto del sistema (que nunca lo da). */
    val sinDatos: Boolean get() = almacen.leer(ClaveSalud.DENEGADO) == "1"
    val ultimaSync: String? get() = almacen.leer(ClaveSalud.ULTIMA_SYNC)
    val historialHecho: Boolean get() = almacen.leer(ClaveSalud.HISTORIAL_HECHO) == "1"

    /**
     * `_sinHistorialAndroid()`: true si se sabe que Health Connect NO dio el historial (en esta sesión o en una anterior).
     * Sin veredicto se asume que sí: es iOS, o un Android que todavía no pasó por la hoja.
     */
    val sinHistorialAndroid: Boolean
        get() {
            if (fuente.plataforma != PlataformaSalud.ANDROID) return false
            historialAndroid?.let { return !it.autorizado }
            return almacen.leer(ClaveSalud.HISTORIAL_OK) == "0"
        }

    /**
     * Anota el veredicto del historial. PERSISTIDO: el de memoria se pierde al cerrar la app, y sin esto el historial del
     * arranque siguiente creía tener los 60 días, Health Connect devolvía vacío lo anterior a 30 y quedaba como COMPLETO.
     */
    private fun anotarHistorial(h: HistorialSalud) {
        historialAndroid = h
        almacen.guardar(ClaveSalud.HISTORIAL_OK, if (h.autorizado) "1" else "0")
    }

    /**
     * `_refrescarHistorial()`: re-pregunta por el historial SIN abrir la hoja. El veredicto se guardaba solo al pasar por
     * los permisos, a los que se llega con "Conectar" (que no se ofrece si ya está conectada): quien negó el historial y
     * después lo habilitó desde Health Connect se quedaba con 30 días para siempre. Si no se puede preguntar, queda el
     * veredicto anterior.
     */
    private suspend fun refrescarHistorial() {
        if (fuente.plataforma != PlataformaSalud.ANDROID) return
        try {
            fuente.historial()?.let(::anotarHistorial)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
        }
    }

    private val ms: Double get() = RelojLocal.ms(ahora())

    private fun refrescar() {
        if (!silencio) alCambiar?.invoke()
    }

    private fun marcarSync() = almacen.guardar(ClaveSalud.ULTIMA_SYNC, RelojLocal.iso(ms))

    /**
     * `registrarCosecha`: se cuenta lo que entregó el sistema, NO lo que aceptó el servidor (un problema de red no es
     * falta de permiso). Un teléfono siempre tiene pasos: tres veces nada de nada es permiso denegado.
     */
    private fun registrarCosecha(n: Int) {
        if (n > 0) {
            almacen.guardar(ClaveSalud.RACHA_VACIA, "0")
            almacen.guardar(ClaveSalud.DENEGADO, null)
            return
        }
        // `(parseInt(localStorage.getItem(K_RACHA), 10) || 0) + 1`
        val r = Js.oCero(Js.parseInt(almacen.leer(ClaveSalud.RACHA_VACIA))) + 1
        almacen.guardar(ClaveSalud.RACHA_VACIA, Js.texto(r))
        if (r >= 3) almacen.guardar(ClaveSalud.DENEGADO, "1")
    }

    // MARK: Envío

    internal class Envio(val ok: Int, val rechazados: Int, val error: String?)

    /** `postearDetalle`: lotes de 300. Un lote rechazado (o sin red) cuenta y guarda su texto. */
    internal suspend fun postear(registros: List<RegistroSalud>): Envio {
        var ok = 0
        var rechazados = 0
        var error: String? = null
        for (lote in registros.chunked(PuenteSalud.LOTE_SALUD)) {
            val r = cliente.llamar("mypump_ingest_salud", mapOf("p_token" to texto(token), "p_registros" to ValorJson.Lista(lote.map { it.json })))
            when (r) {
                is Resultado.Ok -> ok += numeroJs(r.valor)
                is Resultado.Falla -> {
                    rechazados++
                    error = r.error.mensaje.ifEmpty { "error desconocido" }
                    ultimoErrorIngesta = error
                }
            }
        }
        return Envio(ok, rechazados, error)
    }

    /** `postearEntrenos`: lotes de 200 (la base no acepta más de 500). */
    internal suspend fun postearEntrenos(entrenos: List<EntrenoSalud>): Int {
        var ok = 0
        for (lote in entrenos.chunked(PuenteSalud.LOTE_ENTRENOS)) {
            val r = cliente.llamar("mypump_ingest_entrenos", mapOf("p_token" to texto(token), "p_entrenos" to ValorJson.Lista(lote.map { it.json })))
            if (r is Resultado.Ok) ok += numeroJs(r.valor)
        }
        return ok
    }

    // MARK: Sincronizar (7 días)

    /** `sync()`: los últimos 7 días desde la medianoche (el día del borde entero) hasta ahora. */
    suspend fun sincronizar(): ResultadoSync {
        ultimoErrorIngesta = null
        val hasta = ms
        val desde = reloj.medianoche(7, hasta)
        val registros = recolector.recolectar(desde, hasta)
        registrarCosecha(registros.size)
        val envio = if (registros.isEmpty()) Envio(0, 0, null) else postear(registros)
        // Los entrenos van por su propia vía: si fallan, lo diario ya quedó guardado.
        val nEnt = postearEntrenos(recolector.entrenos(desde, hasta))
        marcarSync()
        refrescar()
        return ResultadoSync(ok = true, motivo = null, ingresados = envio.ok, entrenos = nEnt, errorIngesta = envio.error)
    }

    // MARK: Historial (60 días)

    internal data class Cursor(val off: Int, val alcance: Int?)

    /** `_cursorGuardado()`: `{"off":20,"alcance":60}` o el formato viejo (solo el número, alcance 60). */
    internal fun cursorGuardado(): Cursor? {
        val raw = almacen.leer(ClaveSalud.CURSOR)
        if (raw.isNullOrEmpty()) return null
        if (raw.startsWith("{")) {
            val j = try {
                ValorJson.parsear(raw)
            } catch (_: Exception) {
                return null
            }
            val off = j["off"]?.comoNumero ?: 0.0
            if (!(off > 0)) return null
            return Cursor(enteroTruncado(off), j["alcance"]?.comoNumero?.let(::enteroTruncado))
        }
        val v = Js.parseInt(raw) ?: return null
        if (!(v > 0 && v <= 60)) return null
        return Cursor(v.toInt(), 60)
    }

    private fun guardarCursor(off: Int, alcance: Int) = almacen.guardar(ClaveSalud.CURSOR, "{\"off\":$off,\"alcance\":$alcance}")

    /**
     * `backfill()`: una sola vez (hasta que quede hecho). El motor no da score con menos de 14 días de historia: con esto
     * el cliente ve su score el primer día.
     */
    suspend fun historial(): ResultadoHistorial {
        if (historialHecho) return ResultadoHistorial(ok = true, saltado = true, ingresados = 0, ventanasFallidas = 0, sinDatos = sinDatos)
        try {
            var total = 0
            var cosechados = 0
            var ventanas = 0
            var fallaron = 0
            // Android sin el permiso de historial: Health Connect devuelve CERO para todo lo anterior a 30 días, sin error.
            // Se piden 30, se dice 30, y NO se marca como hecho: el próximo arranque con el permiso completa el resto.
            refrescarHistorial()   // ¿lo habilitó desde Health Connect?
            val sinHistorial = sinHistorialAndroid
            val alcance = if (sinHistorial) ALCANCE_SIN_HISTORIAL else ALCANCE
            val cur = cursorGuardado()
            val desdeOff = if (cur?.alcance != null && cur.alcance >= alcance) minOf(cur.off, alcance) else alcance
            progresoHistorial = (alcance - desdeOff) to alcance
            var off = desdeOff
            while (off > 0) {
                // Las dos puntas a medianoche: si no, el día de cada costura sale partido en dos.
                val ahora = ms
                val hasta = reloj.medianoche(off - 5, ahora)
                val desde = reloj.medianoche(off, ahora)
                ventanas++
                var regs = recolector.recolectar(desde, hasta)
                cosechados += regs.size
                if (descartarNochesPartidas) {
                    val corte = reloj.ymd(hasta)
                    regs = regs.filter { it.fecha < corte }
                }
                val envio = postear(regs)
                total += envio.ok
                // Una ventana con lotes rechazados es una ventana fallida (si no, sin señal quedaba "completo" sin nada).
                if (envio.rechazados > 0) fallaron++
                postearEntrenos(recolector.entrenos(desde, hasta))
                progresoHistorial = (alcance - off + 5) to alcance
                guardarCursor(off - 5, alcance)
                alProgresar?.invoke(alcance - off + 5, alcance)
                off -= 5
            }
            // Las 12 ventanas sin una muestra: "no llega nada" de una, salvo que no se haya podido mirar.
            val todoFallo = fallaron == ventanas
            val nadaEntro = cosechados > 0 && total == 0
            if (cosechados == 0 && !todoFallo) almacen.guardar(ClaveSalud.DENEGADO, "1")
            // Se marca hecho solo si al menos una ventana anduvo, entró algo y se pudo mirar todo el alcance. El orden de
            // las ramas es el de la web: sin historial el cursor se borra siempre (la corrida de 60 empieza de cero); si
            // se leyó y no entró nada, el cursor queda (en 0) aunque hayan fallado todas.
            if (!todoFallo && !nadaEntro && !sinHistorial) {
                almacen.guardar(ClaveSalud.HISTORIAL_HECHO, "1")
                almacen.guardar(ClaveSalud.CURSOR, null)
            } else if (sinHistorial || !nadaEntro) {
                almacen.guardar(ClaveSalud.CURSOR, null)
            }
            refrescar()
            return ResultadoHistorial(ok = !todoFallo, saltado = false, ingresados = total, ventanasFallidas = fallaron, sinDatos = sinDatos)
        } finally {
            // Si quedara colgado, la card diría "25/60" para siempre.
            progresoHistorial = null
        }
    }

    /**
     * `_retomarBackfillSiFalta()`: al abrir y al volver. Si un historial se cortó (la app se cerró a mitad), sigue desde el
     * cursor; si no avanza (todo falla), espera 6 h para no repetir 12 ventanas en cada vuelta a la app.
     */
    fun retomarHistorialSiFalta() {
        if (!conectado || historialEnCurso != null || historialHecho) return
        val ultimo = Js.oCero(Js.parseInt(almacen.leer(ClaveSalud.INTENTO) ?: "0"))
        if (ms - ultimo < ESPERA_REINTENTO) return
        val antes = cursorGuardado()
        val mio = Any()
        slot = mio
        // El slot y la tarea quedan anotados ANTES de que arranque (con el despachador inmediato del ViewModel, `async`
        // corre en el acto hasta la primera espera).
        val tarea = alcance.async(start = CoroutineStart.LAZY) {
            try {
                val r = historial()
                // El sello de las 6 h se pone solo si no avanzó: si avanzó, la próxima vuelta tiene que poder seguir.
                val avanzo = normalizado(cursorGuardado()) != normalizado(antes)
                if (!avanzo && !historialHecho) almacen.guardar(ClaveSalud.INTENTO, jsRound(ms).toLong().toString())
                r
            } finally {
                liberar(mio)
            }
        }
        historialEnCurso = tarea
        tarea.start()
    }

    private fun liberar(id: Any) {
        if (slot !== id) return
        slot = null
        historialEnCurso = null
    }

    private fun normalizado(c: Cursor?): String = c?.let { "${it.off}|${it.alcance?.toString() ?: "-"}" } ?: "null"

    // MARK: Conectar

    /**
     * `connect()`: espera los permisos y los 7 días; el historial sale de fondo (en un teléfono con años de historia son
     * minutos, y la app no se puede quedar congelada esperándolo).
     */
    suspend fun conectar(esperarHistorial: Boolean = false): ResultadoConexion {
        var errorDisponible: String? = null
        val disponible = try {
            fuente.disponible()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorDisponible = textoError(e)
            false
        }
        if (!disponible) {
            anotarIntento(
                "paso" to ValorJson.Texto("isAvailable"), "motivo" to ValorJson.Texto("no_disponible"),
                "error" to (errorDisponible?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            )
            return ResultadoConexion(false, "no_disponible", errorDisponible, null, 0, sinDatos, emptyList(), null)
        }
        val p = pedirPermisos()
        if (!p.ok) {
            anotarIntento(
                "paso" to ValorJson.Texto("permiso"), "motivo" to ValorJson.Texto(p.motivo ?: ""),
                "error" to (p.detalle?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            )
            return ResultadoConexion(false, p.motivo, p.detalle, null, 0, sinDatos, emptyList(), null)
        }
        anotarIntento(
            "paso" to ValorJson.Texto("ok"),
            "preguntados" to (p.preguntados?.let { ValorJson.Numero(it.toDouble()) } ?: ValorJson.Nulo),
            "total" to ValorJson.Numero(p.total.toDouble()),
            "errEstado" to (p.errorEstado?.let { ValorJson.Texto(it) } ?: ValorJson.Nulo),
            "rechazados" to if (p.rechazados.isEmpty()) {
                ValorJson.Nulo
            } else {
                ValorJson.Lista(p.rechazados.map { (t, e) -> ValorJson.objeto("tipo" to ValorJson.Texto(t), "error" to ValorJson.Texto(e)) })
            },
        )
        // Se reinicia la RACHA, no el veredicto: "Reintentar" no apaga el cartel sin haber leído una muestra.
        almacen.guardar(ClaveSalud.RACHA_VACIA, "0")
        almacen.guardar(ClaveSalud.CONECTADO, "1")
        silencio = true
        try {
            sincronizar()
            marcarSync()
        } finally {
            silencio = false
        }
        refrescar()
        // El slot se reserva antes de soltar el hilo: un "volver a la app" en el medio no larga un segundo historial.
        val mio = Any()
        slot = mio
        val tarea = alcance.async(start = CoroutineStart.LAZY) {
            try {
                historial().copy(sinDatos = sinDatos)
            } finally {
                liberar(mio)
            }
        }
        historialEnCurso = tarea
        tarea.start()
        if (esperarHistorial) tarea.join()
        return ResultadoConexion(true, null, null, p.preguntados, p.total, sinDatos, p.rechazados, tarea)
    }

    internal class Permisos(
        val ok: Boolean,
        val motivo: String? = null,
        val detalle: String? = null,
        val preguntados: Int? = null,
        val total: Int = 0,
        val errorEstado: String? = null,
        val rechazados: List<Pair<String, String>> = emptyList(),
    )

    /**
     * `requestPermission()`: primero el núcleo (la hoja aparece sí o sí); si falla, lo mínimo (pasos y sueño). Después
     * el resto en otra tanda que puede fallar sin arrastrar a la primera; si falla en bloque, de a uno: que se pierda un
     * tipo es aceptable, que se lleve puestos a los otros doce, no.
     */
    internal suspend fun pedirPermisos(): Permisos {
        try {
            // En Android el historial (más de 30 días) se pide acá, junto con el núcleo; se guarda el veredicto para
            // distinguir "el cliente lo negó" de "este Health Connect es viejo y no lo conoce".
            if (fuente.plataforma == PlataformaSalud.ANDROID) {
                fuente.pedirLecturaConHistorial(PuenteSalud.nucleo)?.let(::anotarHistorial)
            } else {
                fuente.pedirLectura(PuenteSalud.nucleo)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            try {
                fuente.pedirLectura(listOf("steps", "sleep"))
            } catch (e: CancellationException) {
                throw e
            } catch (e2: Exception) {
                return Permisos(ok = false, motivo = "error_nativo", detalle = textoError(e2))
            }
        }
        val resto = PuenteSalud.resto(fuente.plataforma, fuente.iosMayor)
        val rechazados = ArrayList<Pair<String, String>>()
        if (resto.isNotEmpty()) {
            try {
                fuente.pedirLectura(resto)
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                for (t in resto) {
                    try {
                        fuente.pedirLectura(listOf(t))
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e2: Exception) {
                        rechazados += t to textoError(e2)
                    }
                }
            }
        }
        // En HealthKit "listo" significa "se mostró la hoja", no "me dieron permiso": de acá solo sale cuántos se
        // preguntaron.
        val est = estadoPermisos()
        return Permisos(ok = true, preguntados = est.preguntados, total = est.total, errorEstado = est.error, rechazados = rechazados)
    }

    internal class EstadoPermisos(val preguntados: Int?, val total: Int, val pendientes: List<String>, val error: String?)

    /** `estadoPermisos()`. */
    internal suspend fun estadoPermisos(): EstadoPermisos {
        val tipos = PuenteSalud.tiposLectura(fuente.plataforma, fuente.iosMayor)
        return try {
            val r = fuente.permisos(tipos)
            EstadoPermisos(r.preguntados.size, tipos.size, r.pendientes, null)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            EstadoPermisos(null, tipos.size, emptyList(), textoError(e))
        }
    }

    /** `disconnect()`: solo local. Lo ya subido queda (es del cliente y el coach lo usa). */
    fun desconectar() {
        almacen.guardar(ClaveSalud.CONECTADO, null)
        almacen.guardar(ClaveSalud.ULTIMA_SYNC, null)
        almacen.guardar(ClaveSalud.HISTORIAL_HECHO, null)
    }

    /** `estado()`. */
    suspend fun estado(): EstadoSalud {
        val disponible = try {
            fuente.disponible()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
        val est = if (disponible) estadoPermisos() else EstadoPermisos(null, 0, emptyList(), null)
        return EstadoSalud(
            disponible = disponible, conectado = conectado, sinDatos = sinDatos, preguntados = est.preguntados, total = est.total,
            pendientes = est.pendientes, errorEstado = est.error, ultimaSync = ultimaSync, ios = fuente.iosMayor,
        )
    }

    /** El rastro del último intento de conectar (queda en el teléfono y lo muestra el diagnóstico). */
    private fun anotarIntento(vararg datos: Pair<String, ValorJson>) {
        val o = linkedMapOf<String, ValorJson>(
            "cuando" to ValorJson.Texto(RelojLocal.iso(ms)), "ios" to ValorJson.Numero(fuente.iosMayor.toDouble()),
            "nativo" to ValorJson.Booleano(true), "plugin" to ValorJson.Booleano(true),
        )
        for ((k, v) in datos) o[k] = v
        almacen.guardar(ClaveSalud.DIAG, ValorJson.Objeto(o).serializar())
    }

    val ultimoIntento: ValorJson?
        get() = almacen.leer(ClaveSalud.DIAG)?.let {
            try {
                ValorJson.parsear(it)
            } catch (_: Exception) {
                null
            }
        }

    // MARK: Diagnóstico

    /**
     * `diagnostico()`: 14 días de cada tipo por su camino, y el sueño por noche y por fuente (lo que decide si la elección
     * de fuente está bien para los datos reales de este cliente).
     */
    suspend fun diagnostico(): DiagnosticoSalud {
        val errores = RecolectorSalud.Errores()
        val disponible = try {
            fuente.disponible()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            false
        }
        if (!disponible) return DiagnosticoSalud(false, token.isNotEmpty(), ultimoErrorIngesta, emptyList(), emptyList(), emptyList())
        val hasta = ms
        val desde = reloj.medianoche(14, hasta)
        val tipos = ArrayList<DiagnosticoSalud.Tipo>()
        for (a in PuenteSalud.agregados) {
            tipos += try {
                val s = fuente.agregado(a.dataType, a.agregacion, desde, hasta)
                DiagnosticoSalud.Tipo(a.tipo, a.dataType, "aggregated", s.size, s.firstOrNull()?.let { reloj.ymd(it.inicio) },
                    s.lastOrNull()?.let { reloj.ymd(it.inicio) }, null)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                DiagnosticoSalud.Tipo(a.tipo, a.dataType, "aggregated", 0, null, null, textoError(e))
            }
        }
        // Todas las tablas, como la web (también las que esta plataforma no pide: el error queda a la vista).
        val todos = PuenteSalud.muestras.map { it.dataType to it.tipo } + ("heartRateVariability" to "hrv_ms")
        for ((dataType, tipo) in todos) {
            val ms = recolector.leer(dataType, desde, hasta, errores = errores)
            tipos += DiagnosticoSalud.Tipo(tipo, dataType, "samples", ms.size, ms.firstOrNull()?.let { reloj.ymd(it.inicio) },
                ms.lastOrNull()?.let { reloj.ymd(it.inicio) }, null)
        }
        val porNoche = HashMap<String, LinkedHashMap<String, LinkedHashMap<String, Double>>>()
        for (s in recolector.leer("sleep", desde, hasta, errores = errores)) {
            val k = reloj.ymd(s.fin)
            val src = s.fuenteNombre.ifEmpty { s.fuenteId.ifEmpty { "?" } }
            // Mismo criterio que procesarSueno: una sesión con etapas se cuenta como tal.
            val st = s.estadoSueno?.let(Js::minusculas) ?: if (!s.etapas.isNullOrEmpty()) "sesion+etapas" else "asleep"
            val porFuente = porNoche.getOrPut(k) { LinkedHashMap() }.getOrPut(src) { LinkedHashMap() }
            porFuente[st] = jsRound((porFuente[st] ?: 0.0) + (s.fin - s.inicio) / 60_000)
        }
        val noches = porNoche.keys.sorted().map { f ->
            DiagnosticoSalud.NocheFuente(f, porNoche.getValue(f).mapValues { (_, m) -> m.mapValues { enteroTruncado(it.value).toLong() } })
        }
        return DiagnosticoSalud(true, token.isNotEmpty(), ultimoErrorIngesta, tipos, noches, errores.todos)
    }

    companion object {
        const val ALCANCE = 60

        /** Lo que da Health Connect sin el permiso de historial. */
        const val ALCANCE_SIN_HISTORIAL = 30
        internal const val ESPERA_REINTENTO = 6.0 * 60 * 60 * 1000

        /** `Number(r.data) || 0` como entero (truncado y acotado, sin riesgo con un número raro). */
        internal fun numeroJs(j: ValorJson): Int = enteroTruncado(Js.oCero(SemanticaJs.numero(j)))
    }
}
