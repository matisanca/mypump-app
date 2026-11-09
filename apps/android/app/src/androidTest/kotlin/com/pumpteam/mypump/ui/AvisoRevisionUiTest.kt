package com.pumpteam.mypump.ui

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.pumpteam.mypump.avisos.CentroAvisos
import com.pumpteam.mypump.avisos.PermisoAvisos
import com.pumpteam.mypump.avisos.PermisoDePrueba
import com.pumpteam.mypump.datos.AvisoDomingo
import com.pumpteam.mypump.reglas.FechaLocal
import com.pumpteam.mypump.reglas.FotosProgreso
import java.time.Instant
import java.time.ZoneId
import org.junit.Test
import org.junit.runner.RunWith

/**
 * R2 de la 2.0.3: el aviso local de revisión no sale si la semana ya está completa (el check y las tres fotos), se
 * reprograma apenas se completa y, con la semana incompleta, sigue como hoy. Gemelo de `AvisoRevisionUITests.swift`.
 */
@RunWith(AndroidJUnit4::class)
class AvisoRevisionUiTest : PruebaUi() {
    private val zona: ZoneId get() = ZoneId.systemDefault()

    private fun esperado(completa: Boolean): String = AvisoDomingo.anotar(AvisoDomingo.proximo(Instant.now(), zona, completa), zona)

    private fun esperarDomingo(completa: Boolean) {
        val quiero = esperado(completa)
        p.esperar("el aviso agendado para $quiero (está ${CentroAvisos.domingoPendiente(app)})") {
            CentroAvisos.domingoPendiente(app)?.takeIf { it == quiero && CentroAvisos.domingoAgendado(app) }
        }
    }

    private fun conFotosDeLaSemana() = servidor.ponerFotos(mapOf(FotosProgreso.lunes(FechaLocal.hoy()) to listOf("frente", "perfil", "espalda")))

    @Test
    fun conLaSemanaCompletaSeSalteaElDeEstaSemana() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        servidor.respuestas["mypump_get_checkin_semana"] = """[{"energia":4,"descanso":3,"hambre":2,"adherencia":4,"nota":null}]"""
        conFotosDeLaSemana()
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("check-enviado"))
            esperarDomingo(completa = true)
        }.close()
    }

    @Test
    fun conLaSemanaIncompletaSigueComoHoy() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        conFotosDeLaSemana()   // las fotos sí, el check no
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("enviar-check"))
            p.quieto(1_500)
            esperarDomingo(completa = false)
        }.close()
    }

    /** Quien completa el sábado (acá: cuando sea) no recibe nada el domingo: mandar el check reprograma el aviso. */
    @Test
    fun alCompletarSeReprograma() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        conFotosDeLaSemana()
        guardarCuenta()
        abrir().also {
            p.tocar(etiqueta("pestana-revision"))
            esperarDomingo(completa = false)
            for (t in listOf("Energía: 4 de 5", "Descanso: 4 de 5", "Hambre: 3 de 5", "Adherencia: 5 de 5")) p.tocar(texto(t))
            p.escribir(etiqueta("peso-check"), "80")
            p.tocar(etiqueta("enviar-check"))
            p.nodo(etiqueta("check-enviado"))
            esperarDomingo(completa = true)
        }.close()
    }

    /** Un alumno que revisa los sábados: el aviso se agenda su sábado y la pestaña lo dice. La semana no se corre. */
    @Test
    fun conDiaSabadoElAvisoSaleElSabado() {
        PermisoDePrueba.estado = PermisoAvisos.CONCEDIDO
        servidor.respuestas["mypump_get_revision_dia"] = "6"
        guardarCuenta()
        val quiero = AvisoDomingo.anotar(AvisoDomingo.proximo(Instant.now(), zona, false, 6), zona)
        abrir().also {
            p.tocar(etiqueta("pestana-revision"))
            p.nodo(etiqueta("dia-de-revision"))
            p.esperar("el aviso agendado para $quiero") { CentroAvisos.domingoPendiente(app)?.takeIf { it == quiero } }
        }.close()
    }
}
