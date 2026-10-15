package com.pumpteam.mypump.chat

import com.pumpteam.mypump.datos.BurbujaChat
import com.pumpteam.mypump.datos.FechaIso
import com.pumpteam.mypump.diseno.Formato
import com.pumpteam.mypump.modelos.TextoJs
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.de
import java.text.BreakIterator
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeParseException
import java.util.Locale

/** Una fila del hilo tal como se ve: el separador de un día o un mensaje con su lugar en el grupo. */
sealed interface FilaHilo {
    /** La clave de la fila en la lista (estable: el id del mensaje o el día). */
    val clave: String

    /** "Hoy", "Ayer" o "Lunes, 12 de octubre", arriba del primer mensaje de cada día. */
    data class Dia(val dia: String, val texto: String, override val clave: String) : FilaHilo

    /**
     * Un mensaje. [iniciaGrupo]: el anterior es de otro autor (o de otro día), así que va más separado. [cierraGrupo]: el
     * siguiente es de otro autor o de otro día, así que lleva la colita y la hora ([hora]).
     */
    data class Mensaje(val burbuja: BurbujaChat, val iniciaGrupo: Boolean, val cierraGrupo: Boolean, val hora: String?) : FilaHilo {
        override val clave: String get() = burbuja.id
    }
}

/**
 * Lo que la pantalla del chat arma con el hilo, sin Android (se prueba en la JVM): los separadores y los grupos de
 * burbujas como ChatView.swift, la hora, y el límite de 1000 caracteres con su contador (CHA-02).
 */
object TextosChat {
    /** Como el `maxlength` de la web: nunca sale un mensaje más largo. */
    const val LIMITE = 1000

    /** El contador aparece pasados los 900. */
    const val AVISO = LIMITE - 100

    /** El hilo de ChatView.swift: un separador al empezar cada día y cada mensaje con su grupo. Va en orden cronológico. */
    fun filas(mensajes: List<BurbujaChat>, hoy: LocalDate = LocalDate.now(), zona: ZoneId = ZoneId.systemDefault()): List<FilaHilo> {
        val dias = mensajes.map { FechaLocal.de(it.createdAt, zona) }
        val claves = HashSet<String>()
        val out = ArrayList<FilaHilo>(mensajes.size + 4)
        for ((i, m) in mensajes.withIndex()) {
            val dia = dias[i]
            val nuevoDia = i == 0 || dias[i - 1] != dia
            if (nuevoDia) {
                // Un día no se repite (el hilo viene ordenado); por las dudas, la clave nunca choca.
                var clave = "dia-$dia"
                while (!claves.add(clave)) clave += "+"
                out += FilaHilo.Dia(dia, separador(dia, hoy), clave)
            }
            val previo = if (i > 0 && !nuevoDia) mensajes[i - 1] else null
            val siguiente = mensajes.getOrNull(i + 1)
            val cierra = siguiente == null || siguiente.autor != m.autor || dias[i + 1] != dia
            out += FilaHilo.Mensaje(m, iniciaGrupo = previo?.autor != m.autor, cierraGrupo = cierra, hora = if (cierra) hora(m.createdAt, zona) else null)
        }
        return out
    }

    /** Hoy / Ayer / "Lunes, 12 de octubre": el día local, como iOS en es_AR (con la coma y la inicial en mayúscula). */
    fun separador(dia: String, hoy: LocalDate = LocalDate.now()): String {
        val f = try {
            LocalDate.parse(dia)
        } catch (_: DateTimeParseException) {
            return dia
        }
        if (f == hoy) return "Hoy"
        if (f == hoy.minusDays(1)) return "Ayer"
        val s = "${DIAS[f.dayOfWeek.value - 1]}, ${f.dayOfMonth} de ${MESES[f.monthValue - 1]}"
        return s.substring(0, 1).uppercase(Locale.ROOT) + s.substring(1)
    }

    /** "18:52" en la hora del teléfono, en 24 h como la web (`es-AR`). Sin una fecha legible, nada. */
    fun hora(iso: String, zona: ZoneId = ZoneId.systemDefault()): String? {
        val t = FechaIso.instante(iso)?.atZone(zona) ?: return null
        return String.format(Locale.ROOT, "%02d:%02d", t.hour, t.minute)
    }

    /**
     * Los caracteres como los cuenta iOS (`String.count`): lo que se ve, así que un emoji compuesto o una letra con su
     * tilde aparte valen uno. Es el límite de iOS para que en los dos teléfonos se corte en el mismo lugar.
     */
    fun caracteres(s: String): Int {
        if (s.isEmpty()) return 0
        // Lo común (letras, números, signos sueltos) es un carácter por char: se cuenta sin recorrer los grafemas. Menos
        // "\r\n", que para iOS es uno solo.
        if (s.all { it.code < 0x300 && it != '\r' }) return s.length
        val corte = BreakIterator.getCharacterInstance(Locale.ROOT)
        corte.setText(s)
        var n = 0
        while (corte.next() != BreakIterator.DONE) n++
        return n
    }

    /** "1.001/1.000", con los miles como los escribe un argentino. */
    fun contador(n: Int): String = "${Formato.miles(n.toDouble())}/${Formato.miles(LIMITE.toDouble())}"

    /** Lo que lee TalkBack en el contador: "Te pasaste: 1.001 de 1.000 caracteres" o "1.000 de 1.000 caracteres". */
    fun contadorAccesible(n: Int): String {
        val de = "${Formato.miles(n.toDouble())} de ${Formato.miles(LIMITE.toDouble())} caracteres"
        return if (n > LIMITE) "Te pasaste: $de" else de
    }

    /** Hay algo para mandar (el `trim()` de la web) y entra en el límite. */
    fun sePuedeMandar(texto: String): Boolean = TextoJs.recortar(texto).isNotEmpty() && caracteres(texto) <= LIMITE

    private val DIAS = listOf("lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo")

    private val MESES = listOf(
        "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre",
    )
}
