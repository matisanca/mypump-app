package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.Alimento
import com.pumpteam.mypump.modelos.ComidaLibre
import com.pumpteam.mypump.modelos.ComidaMarcada
import com.pumpteam.mypump.modelos.Comida
import com.pumpteam.mypump.modelos.Macros
import com.pumpteam.mypump.modelos.ValorJson
import com.pumpteam.mypump.reglas.AgregadosComida
import com.pumpteam.mypump.reglas.AjusteComida
import com.pumpteam.mypump.reglas.AjustePorciones
import com.pumpteam.mypump.reglas.AlimentoEfectivo
import com.pumpteam.mypump.reglas.ComidaLibreNueva
import com.pumpteam.mypump.reglas.ConsumoDelDia
import com.pumpteam.mypump.reglas.CopiaDeComidas
import com.pumpteam.mypump.reglas.DiasDieta
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.MarcaComida
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// Cargar días anteriores en Dieta y copiar a hoy lo de otro día. Lo de HOY sigue exactamente como estaba (`marcas`, `ajustes`,
// `comidasLibres`, su disco y su hidratación): el día pasado es otra caja (`diaPasado`), que vive solo mientras se la mira,
// se lee del servidor y escribe por la misma cola con la fecha de ese día (las `dedupeKey` llevan la fecha: no pisan otra).
// Los días pasados no van a disco: sin señal no se pueden abrir, porque un día se guarda entero y escribir sin haber leído
// borraría lo que ya tenía. Gemelo de DiaPasadoDieta.swift.

/** El día anterior que se está mirando en Dieta. */
data class DiaPasado(
    val fecha: String,
    val cargando: Boolean = true,
    val sinRed: Boolean = false,
    val marcas: Map<String, MarcaComida> = emptyMap(),
    val ajustes: Map<String, AjusteComida> = emptyMap(),
    val libres: List<ComidaLibre> = emptyList(),
    val tipoDia: String? = null,
    /**
     * Ese día regía otro plan (fila de otra dieta o marcas de comidas que ya no existen): se ve el plan actual, sin marcas ni
     * ajustes, y solo se pueden tocar las comidas libres.
     */
    val otroPlan: Boolean = false,
    /** Un guardado de ese día no salió: sigue en el teléfono. */
    val sinGuardar: Boolean = false,
    internal val opcionesVistas: Map<String, Int> = emptyMap(),
)

data class ResultadoCopia(
    val comidas: Int = 0,
    val libres: Int = 0,
    /** Comidas libres que no se pudieron crear (la copia de comidas libres es directa, no por la cola). */
    val libresFallidas: Int = 0,
    /** Comidas que cambiaron mientras se elegía y no se reemplazaron porque el cliente no lo había pedido. */
    val saltadas: Int = 0,
)

/** Lo leído de un día (servidor + lo que sigue en la cola). */
internal class DatosDia(
    val marcas: Map<String, MarcaComida>,
    val ajustes: Map<String, AjusteComida>,
    val libres: List<ComidaLibre>,
    val tipoDia: String?,
    val otroPlan: Boolean,
    val sinGuardar: Boolean,
)

// ── Lo que dibuja Dieta ──

/** El día a la vista en formato ISO. */
val ModeloApp.fechaVista: String get() = _diaPasado.value?.fecha ?: FechaLocal.hoy()
val ModeloApp.enDiaPasado: Boolean get() = _diaPasado.value != null

/** Hoy y los días anteriores que se pueden abrir. Vacío en la demo: no escribe ni tiene días guardados. */
val ModeloApp.fechasDieta: List<String>
    get() = if (esDemo.value || token == null) emptyList() else DiasDieta.seleccionables(FechaLocal.hoy(), DiasDieta.hoyServidor())

val ModeloApp.marcasVista: Map<String, MarcaComida> get() = _diaPasado.value?.marcas ?: marcasDeHoy
val ModeloApp.ajustesVista: Map<String, AjusteComida> get() = _diaPasado.value?.ajustes ?: ajustesDeHoy
val ModeloApp.libresVista: List<ComidaLibre> get() = _diaPasado.value?.libres ?: comidasLibres.value
val ModeloApp.tipoDiaVista: String? get() = _diaPasado.value.let { p -> if (p != null) p.tipoDia else tipoDia }
val ModeloApp.ajustesSinGuardarVista: Boolean get() = _diaPasado.value?.sinGuardar ?: ajustesSinGuardar.value

internal fun ModeloApp.comidasDeTipo(tipo: String?): List<Comida> {
    val e = dieta.value?.estructura ?: return emptyList()
    if (e.tiposDia.isEmpty()) return e.comidas
    return (e.tiposDia.firstOrNull { it.id == tipo } ?: e.tiposDia[0]).comidas
}

val ModeloApp.comidasVista: List<Comida> get() = _diaPasado.value?.let { comidasDeTipo(it.tipoDia) } ?: comidasDelDia

val ModeloApp.objetivoVista: Macros
    get() {
        val p = _diaPasado.value ?: return objetivo
        val e = dieta.value?.estructura
        if (e == null || e.tiposDia.isEmpty()) return objetivo
        return (e.tiposDia.firstOrNull { it.id == p.tipoDia } ?: e.tiposDia[0]).macrosTarget ?: Macros()
    }

/** Lo mismo que [ModeloApp.efectivo] para el tipo de día del día a la vista. */
fun ModeloApp.efectivoVista(original: Alimento, comidaId: String, opt: Int, idx: Int): AlimentoEfectivo =
    efectivo(original, comidaId, opt, idx, tipoDiaVista)

/** Se pueden tocar la marca, los ajustes y los agregados (las comidas libres no dependen del plan). */
val ModeloApp.vistaEditable: Boolean get() = _diaPasado.value?.let { !it.cargando && !it.sinRed && !it.otroPlan } ?: true

/** Se pueden cargar comidas libres: el día ya se leyó. */
val ModeloApp.vistaAdmiteLibres: Boolean get() = _diaPasado.value?.let { !it.cargando && !it.sinRed } ?: true

/** La ventana de «Comí» / «Salté» vigente. */
val ModeloApp.diasMarcar: Int
    get() = maxOf(DiasDieta.DIAS_MARCAR_DE_FABRICA, minOf(palanca.value.diasMarcarDieta ?: DiasDieta.DIAS_MARCAR_DE_FABRICA, DiasDieta.DIAS_ATRAS))

/** ¿«Comí» y «Salté» valen para el día a la vista? (Hoy, siempre.) */
val ModeloApp.vistaPuedeMarcar: Boolean
    get() {
        val p = _diaPasado.value ?: return true
        return vistaEditable && DiasDieta.permiteMarcar(p.fecha, DiasDieta.hoyServidor(), diasMarcar)
    }

/** Cambia el tipo de día de lo que se mira: el de un día pasado no toca el de hoy. */
fun ModeloApp.elegirTipoDia(id: String) {
    val p = _diaPasado.value
    if (p == null) {
        tipoDia = id
        return
    }
    if (p.tipoDia == id || !vistaEditable) return
    val nuevo = p.copy(tipoDia = id)
    _diaPasado.value = nuevo
    ordenDiaPasado += 1
    if (nuevo.ajustes.isNotEmpty()) alcance.launch { encolarDiaPasado(nuevo) }
}

// ── Abrir y volver ──

/** Abre un día anterior, o vuelve a hoy con null (o la fecha de hoy). */
suspend fun ModeloApp.irADia(fecha: String?) {
    vueltaDiaPasado += 1
    val vuelta = vueltaDiaPasado
    if (fecha == null || fecha == FechaLocal.hoy() || fecha !in fechasDieta) {
        _diaPasado.value = null
        return
    }
    _diaPasado.value = DiaPasado(fecha = fecha, tipoDia = tipoDia)
    leerDiaPasado(fecha, vuelta)
}

/** Tirar para actualizar (o volver a la app) mirando un día anterior. */
suspend fun ModeloApp.refrescarDiaPasado() {
    val f = _diaPasado.value?.fecha ?: return
    _diaPasado.update { p -> if (p?.sinRed == true) p.copy(cargando = true, sinRed = false) else p }
    vueltaDiaPasado += 1
    leerDiaPasado(f, vueltaDiaPasado)
}

private suspend fun ModeloApp.leerDiaPasado(fecha: String, vuelta: Int) {
    val orden = ordenDiaPasado
    val r = leerDia(fecha)
    // Otro día elegido (o la vuelta a hoy) mientras viajaba: esta respuesta ya no es de nadie.
    val p = _diaPasado.value
    if (vuelta != vueltaDiaPasado || p == null || p.fecha != fecha) return
    // Tocó algo mientras viajaba: la respuesta es una foto de antes de ese cambio.
    if (orden != ordenDiaPasado) return
    _diaPasado.value = if (r == null) {
        // Con el día ya a la vista, un corte al refrescar no lo cierra.
        p.copy(cargando = false, sinRed = p.sinRed || (p.marcas.isEmpty() && p.ajustes.isEmpty() && p.libres.isEmpty()))
    } else {
        p.copy(
            cargando = false, sinRed = false, marcas = r.marcas, ajustes = r.ajustes, libres = r.libres,
            tipoDia = r.tipoDia ?: p.tipoDia, otroPlan = r.otroPlan, sinGuardar = r.sinGuardar,
        )
    }
}

/**
 * Lo que hay guardado de un día: lo del servidor con lo pendiente de la cola por encima (lo pendiente es lo último que
 * decidió el cliente). null si no se pudo leer: nunca se trata un corte como un día vacío.
 */
internal suspend fun ModeloApp.leerDia(fecha: String): DatosDia? {
    val t = token ?: return null
    val cola = outbox ?: return null
    if (esDemo.value) return null
    // Lo pendiente al empezar también gana: si sale mientras viaja la lectura, la foto del servidor puede ser de antes.
    val pendientesAntes = cola.pendientesPorClave()
    val porFecha = mapOf("p_token" to ValorJson.Texto(t), "p_fecha" to ValorJson.Texto(fecha))
    val (rm, rl, ra) = coroutineScope {
        val m = async { cliente.filas("mypump_get_comidas_marcadas", porFecha, ComidaMarcada::desde) }
        val l = async { cliente.filas("mypump_get_comidas_libres", porFecha, ComidaLibre::desde) }
        val a = async {
            cliente.llamar("mypump_get_ajustes_dieta", mapOf("p_token" to ValorJson.Texto(t), "p_desde" to ValorJson.Texto(fecha), "p_hasta" to ValorJson.Texto(fecha)))
        }
        Triple(m.await(), l.await(), a.await())
    }
    if (!deLaCuenta(t) || rm !is Resultado.Ok || rl !is Resultado.Ok) return null
    val filas = when (ra) {
        // null = token caído
        is Resultado.Ok -> (ra.valor as? ValorJson.Lista)?.elementos ?: return null
        // Sin la tabla: no hay ajustes.
        is Resultado.Falla -> if (ra.error.codigo == "PGRST202") emptyList() else return null
    }

    val marcas = ConsumoDelDia.marcas(rm.valor).toMutableMap()
    val prefijo = MarcasComidas.clave(fecha, "")
    val pendientes = cola.pendientesPorClave()
    for (lote in listOf(pendientesAntes, pendientes)) {
        for ((k, op) in lote) {
            if (!k.startsWith(prefijo)) continue
            val id = k.removePrefix(prefijo)
            val m = MarcasComidas.desdePayload(op.payload)
            if (m != null) marcas[id] = m else marcas.remove(id)
        }
    }

    var ajustes: Map<String, AjusteComida> = emptyMap()
    var tipo: String? = null
    var dietaRemota: String? = null
    // false: no se pudo leer. No es un día vacío: la próxima edición reemplazaría la fila entera.
    fun adoptar(a: ValorJson?, tipoFila: String?, dietaFila: String?): Boolean {
        val leidos = AjustesDieta.comidasDesde(a) ?: return false
        ajustes = leidos.filterValues { !it.neutro }
        tipo = tipoFila
        dietaRemota = dietaFila
        return true
    }
    filas.firstOrNull { it["fecha"]?.comoTexto == fecha }?.let { f ->
        if (!adoptar(f["ajustes"], f["tipo_dia"]?.comoTexto, f["dieta_id"]?.comoTexto)) return null
    }
    val clave = AjustesDieta.clave(fecha)
    // Lo que la base rechazó sigue valiendo en el teléfono, como el de hoy; lo pendiente manda sobre todo.
    val fallido = cola.fallidos().lastOrNull { it.op.kind == AjustesDieta.KIND && it.op.dedupeKey == clave }
    for (op in listOfNotNull(fallido?.op, pendientesAntes[clave], pendientes[clave])) {
        if (!adoptar(op.payload["ajustes"], op.payload["tipoDia"]?.comoTexto, op.payload["dietaId"]?.comoTexto)) return null
    }

    // ¿Regía otro plan? La fila dice con qué dieta se guardó; las marcas, qué comidas había.
    val e = dieta.value?.estructura
    val idsPlan = (e?.comidas.orEmpty().map { it.id } + e?.tiposDia.orEmpty().flatMap { d -> d.comidas.map { it.id } }).toSet()
    val otraDieta = ajustes.isNotEmpty() && dietaRemota != null && dietaRemota != dieta.value?.id
    val otroPlan = otraDieta || marcas.keys.any { it !in idsPlan }
    val tipoValido = tipo?.takeIf { t2 -> e?.tiposDia.orEmpty().any { it.id == t2 } }
    return DatosDia(
        if (otroPlan) emptyMap() else marcas, if (otroPlan) emptyMap() else ajustes, rl.valor, tipoValido, otroPlan,
        sinGuardar = fallido != null && pendientes[clave] == null && pendientesAntes[clave] == null,
    )
}

// ── Escribir en el día pasado ──

internal suspend fun ModeloApp.ajustarPasado(comidaId: String, ajuste: AjusteComida?, opciones: Map<String, Int>) {
    val p0 = _diaPasado.value ?: return
    if (!vistaEditable) return
    var p = p0.copy(opcionesVistas = p0.opcionesVistas + opciones)
    val anclado = ajuste?.let { x -> comidasVistaParaAjustar(p, p.opcionesVistas).firstOrNull { it.id == comidaId }?.let { AjustePorciones.anclar(x, it) } ?: x }
    val nuevos = if (anclado != null && !anclado.neutro) p.ajustes + (comidaId to anclado) else p.ajustes - comidaId
    if (nuevos == p.ajustes) {
        _diaPasado.value = p
        return
    }
    val antes = p.ajustes[comidaId]?.agregados.orEmpty()
    // Los tildes siguen a los agregados con una marca nueva: fuera de la ventana de «Comí» la base la rechazaría y quedaría
    // un tilde corrido, así que los agregados de una comida marcada no se tocan.
    if (antes.map { it.ts } != nuevos[comidaId]?.agregados.orEmpty().map { it.ts } && p.marcas[comidaId]?.estado == MarcaComida.Estado.COMIDO && !vistaPuedeMarcar) {
        _diaPasado.value = p
        return
    }
    p = p.copy(ajustes = nuevos)
    // Los tildes de «Comí» siguen a cada agregado (por `_ts`), como hoy.
    var marcaNueva: MarcaComida? = null
    var marcaCambio = false
    val despues = nuevos[comidaId]?.agregados.orEmpty()
    val m = p.marcas[comidaId]
    val c = comidasDeTipo(p.tipoDia).firstOrNull { it.id == comidaId }
    if (antes.map { it.ts } != despues.map { it.ts } && m != null && m.estado == MarcaComida.Estado.COMIDO && c != null) {
        val o = ConsumoDelDia.opcionDeLaMarca(c, m) ?: 0
        val n = c.opciones.getOrNull(o)?.alimentos?.size ?: 0
        val excl = AgregadosComida.excluidosTrasCambio(m.excluidos, n, antes.map { it.ts }, despues.map { it.ts })
        if (excl != m.excluidos) {
            val nueva = MarcaComida(m.opcion, MarcaComida.Estado.COMIDO, excl)
            marcaNueva = nueva
            marcaCambio = true
            p = p.copy(marcas = p.marcas + (comidaId to nueva))
        }
    }
    // «Ese día no la comí» sobre una marcada: la marca se va, como hoy.
    val saleMarca = nuevos[comidaId]?.omitida == true && p.marcas[comidaId] != null
    val opcionMarca = p.marcas[comidaId]?.opcion
    if (saleMarca) p = p.copy(marcas = p.marcas - comidaId)
    ordenDiaPasado += 1
    _diaPasado.value = p
    if (esDemo.value) return
    if (marcaCambio && !saleMarca) encolarMarcaPasado(p.fecha, comidaId, marcaNueva, marcaNueva?.opcion)
    encolarDiaPasado(p)
    if (saleMarca) encolarMarcaPasado(p.fecha, comidaId, null, opcionMarca)
}

internal suspend fun ModeloApp.marcarPasado(comidaId: String, estado: MarcaComida.Estado?, opcion: Int) {
    val p = _diaPasado.value ?: return
    if (!vistaPuedeMarcar) return
    val c = comidasDeTipo(p.tipoDia).firstOrNull { it.id == comidaId } ?: return
    val o = if (c.opciones.isEmpty()) 0 else opcion.coerceIn(0, c.opciones.size - 1)
    val nombre = ConsumoDelDia.nombreOpcion(c, o)
    cambiarMarcaPasado(comidaId, estado?.let { MarcaComida(nombre, it) }, nombre)
}

internal suspend fun ModeloApp.alternarAlimentoPasado(comidaId: String, idx: Int) {
    val p = _diaPasado.value ?: return
    if (!vistaPuedeMarcar || idx < 0) return
    val m = p.marcas[comidaId] ?: return
    if (m.estado != MarcaComida.Estado.COMIDO) return
    val excl = if (idx in m.excluidos) m.excluidos - idx else m.excluidos + idx
    cambiarMarcaPasado(comidaId, MarcaComida(m.opcion, MarcaComida.Estado.COMIDO, excl), m.opcion)
}

private suspend fun ModeloApp.cambiarMarcaPasado(comidaId: String, nueva: MarcaComida?, opcionAlDesmarcar: String?) {
    val p = _diaPasado.value ?: return
    if (nueva == p.marcas[comidaId]) return
    ordenDiaPasado += 1
    _diaPasado.value = p.copy(marcas = if (nueva != null) p.marcas + (comidaId to nueva) else p.marcas - comidaId)
    encolarMarcaPasado(p.fecha, comidaId, nueva, opcionAlDesmarcar)
}

private suspend fun ModeloApp.encolarMarcaPasado(fecha: String, comidaId: String, nueva: MarcaComida?, opcionAlDesmarcar: String?) {
    if (esDemo.value) return
    val cola = outbox ?: return
    cola.encolar(MarcasComidas.KIND, MarcasComidas.payload(fecha, comidaId, nueva, opcionAlDesmarcar), MarcasComidas.clave(fecha, comidaId))
}

internal suspend fun ModeloApp.verOpcionPasado(comidaId: String, opcion: Int) {
    val p = _diaPasado.value?.let { it.copy(opcionesVistas = it.opcionesVistas + (comidaId to opcion)) } ?: return
    _diaPasado.value = p
    if (p.ajustes.isNotEmpty() && !esDemo.value && vistaEditable) encolarDiaPasado(p)
}

/** El día pasado [p] entero a la cola (la clave lleva su fecha: no pisa el de hoy). */
internal suspend fun ModeloApp.encolarDiaPasado(p: DiaPasado) {
    encolarDia(p.fecha, p.ajustes, p.tipoDia, comidasVistaParaAjustar(p, p.opcionesVistas))
}

internal fun ModeloApp.comidasVistaParaAjustar(p: DiaPasado, opciones: Map<String, Int>): List<AjustePorciones.ComidaDelDia> =
    comidasAjustables(comidasDeTipo(p.tipoDia), p.ajustes, p.tipoDia, opciones)

internal suspend fun ModeloApp.borrarComidaLibrePasada(id: String): Boolean {
    val p = _diaPasado.value ?: return false
    ordenDiaPasado += 1
    _diaPasado.value = p.copy(libres = p.libres.filterNot { it.id == id })
    val t = token ?: return true
    if (cliente.llamar("mypump_borrar_comida_libre", mapOf("p_token" to ValorJson.Texto(t), "p_id" to ValorJson.Texto(id))) is Resultado.Falla) {
        if (deLaCuenta(t)) _diaPasado.update { d -> if (d?.fecha == p.fecha) d.copy(libres = p.libres) else d }
        return false
    }
    return true
}

// ── Copiar a hoy ──

/** Lo que se puede copiar de [fecha] a hoy. null si no se pudo leer ese día. */
suspend fun ModeloApp.prepararCopia(fecha: String): CopiaDeComidas.Plan? {
    if (fecha == FechaLocal.hoy()) return null
    val d = leerDia(fecha) ?: return null
    if (fechaAjustes != FechaLocal.hoy()) cargarAjustes()
    if (fechaMarcas != FechaLocal.hoy()) cargarMarcas()
    return CopiaDeComidas.plan(comidasDelDia, d.marcas, d.ajustes, d.libres, marcasDeHoy, ajustesDeHoy, comidasLibres.value, d.otroPlan) { c, m, a, o ->
        val sintetica = m ?: MarcaComida(ConsumoDelDia.nombreOpcion(c, o), MarcaComida.Estado.COMIDO)
        ConsumoDelDia.calcular(listOf(c), mapOf(c.id to sintetica), emptyList(), a?.let { mapOf(c.id to it) }.orEmpty(), mapOf(c.id to o)) { cid, op, i, al ->
            efectivo(al, cid, op, i).alimento
        }.kcal
    }
}

/**
 * Copia a hoy lo elegido. [reemplazar] son las comidas que el cliente aceptó pisar: lo que no esté ahí y hoy tenga algo
 * cargado se saltea, aunque haya cambiado después de armar la lista. En [libres] van también las que el plan dio por
 * iguales: cada una descuenta la suya de hoy, y si no, la repetida que sí falta se saltearía.
 */
suspend fun ModeloApp.copiarAHoy(comidas: List<CopiaDeComidas.ItemComida>, libres: List<CopiaDeComidas.ItemLibre>, reemplazar: Set<String>): ResultadoCopia {
    if (esDemo.value) return ResultadoCopia()
    if (fechaAjustes != FechaLocal.hoy()) cargarAjustes()
    if (fechaMarcas != FechaLocal.hoy()) cargarMarcas()
    var copiadas = 0
    var saltadas = 0
    for (i in comidas) {
        val actual = CopiaDeComidas.estado(i.marca, i.ajuste, marcasDeHoy[i.comidaId], ajustesDeHoy[i.comidaId])
        if (actual == CopiaDeComidas.Estado.IGUAL) continue
        if (actual == CopiaDeComidas.Estado.CONFLICTO && i.comidaId !in reemplazar) {
            saltadas += 1
            continue
        }
        // Los mismos topes que al agregar a mano: un día que no entra haría rechazar la fila entera de hoy.
        val nuevos = i.ajuste?.let { ajustesDeHoy + (i.comidaId to it) } ?: (ajustesDeHoy - i.comidaId)
        if (AgregadosComida.motivoNoEntra(nuevos, i.comidaId) != null) {
            saltadas += 1
            continue
        }
        val opcionHoy = marcasDeHoy[i.comidaId]?.opcion
        ajustarHoy(i.comidaId, i.ajuste, mapOf(i.comidaId to i.opcion))
        // Reemplazar es que hoy quede lo de ese día, marca incluida. Si no pisaba nada y ese día no la marcó, no se marca.
        if (actual == CopiaDeComidas.Estado.CONFLICTO || i.marca != null) cambiarMarca(i.comidaId, i.marca, i.marca?.opcion ?: opcionHoy)
        copiadas += 1
    }
    var libresCopiadas = 0
    var fallidas = 0
    // Por conteo: cada una de hoy cubre una sola del origen.
    val deHoy = comidasLibres.value.toMutableList()
    for (i in libres) {
        val j = deHoy.indexOfFirst { CopiaDeComidas.mismaLibre(it, i.libre) }
        if (j >= 0) {
            deHoy.removeAt(j)
            continue
        }
        val l = i.libre
        val d = ComidaLibreNueva.Datos(l.hora?.take(5), l.descripcion ?: "", l.kcal ?: 0.0, l.prot ?: 0.0, l.carb ?: 0.0, l.fat ?: 0.0, l.detalle)
        when (crearComidaLibreEn(FechaLocal.hoy(), d)) {
            is Resultado.Ok -> libresCopiadas += 1
            is Resultado.Falla -> fallidas += 1
        }
    }
    if (fallidas > 0) cargarComidasLibres()
    return ResultadoCopia(copiadas, libresCopiadas, fallidas, saltadas)
}
