package com.pumpteam.mypump.datos

import com.pumpteam.mypump.modelos.ValorJson
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Lo puro de las notificaciones de Android: cuándo suena el aviso del domingo (con zona y cambio de hora) y qué se vuelve
 * a armar sin la app, cuándo se registra el push y a dónde lleva tocar un aviso. Lo que agenda y publica está en `:app`
 * (`avisos/`, con sus pruebas en el emulador: `AvisosUiTest`).
 */
class AgendaAvisosTest {
    private val buenosAires = ZoneId.of("America/Argentina/Buenos_Aires")

    private fun en(zona: ZoneId, local: String): Instant = LocalDateTime.parse(local).atZone(zona).toInstant()

    @Test
    fun elProximoDomingoALas11() {
        // Un miércoles a la tarde: el domingo que viene a las 11:00 de Buenos Aires (UTC-3, 14:00 UTC).
        assertEquals(Instant.parse("2026-10-18T14:00:00Z"), AvisoDomingo.proximo(en(buenosAires, "2026-10-14T15:00"), buenosAires))
        // El sábado a la noche y el domingo antes de las 11: ese domingo.
        assertEquals(Instant.parse("2026-10-18T14:00:00Z"), AvisoDomingo.proximo(en(buenosAires, "2026-10-17T23:59"), buenosAires))
        assertEquals(Instant.parse("2026-10-18T14:00:00Z"), AvisoDomingo.proximo(en(buenosAires, "2026-10-18T10:59:59"), buenosAires))
        // A las 11 en punto (lo que acaba de sonar) o después: el de la semana que viene.
        assertEquals(Instant.parse("2026-10-25T14:00:00Z"), AvisoDomingo.proximo(en(buenosAires, "2026-10-18T11:00"), buenosAires))
        assertEquals(Instant.parse("2026-10-25T14:00:00Z"), AvisoDomingo.proximo(en(buenosAires, "2026-10-18T23:30"), buenosAires))
        // El lunes: casi una semana.
        assertEquals(Instant.parse("2026-10-25T14:00:00Z"), AvisoDomingo.proximo(en(buenosAires, "2026-10-19T00:00"), buenosAires))
    }

    /** La hora sale del reloj de ESE domingo: con el cambio de hora en el medio sigue sonando a las 11:00 del teléfono. */
    @Test
    fun conCambioDeHoraSigueSiendoALas11DelTelefono() {
        val nuevaYork = ZoneId.of("America/New_York")
        // El domingo 8 de marzo de 2026 a las 2:00 empieza el horario de verano: el sábado es UTC-5 y el domingo, UTC-4.
        assertEquals(Instant.parse("2026-03-08T15:00:00Z"), AvisoDomingo.proximo(en(nuevaYork, "2026-03-07T12:00"), nuevaYork))
        // El domingo 1 de noviembre a las 2:00 termina: el sábado es UTC-4 y el domingo, UTC-5.
        assertEquals(Instant.parse("2026-11-01T16:00:00Z"), AvisoDomingo.proximo(en(nuevaYork, "2026-10-31T12:00"), nuevaYork))
        // El mismo domingo a la 1:30, antes del cambio: las 11:00 de ese día, ya con la hora nueva.
        assertEquals(Instant.parse("2026-11-01T16:00:00Z"), AvisoDomingo.proximo(en(nuevaYork, "2026-11-01T01:30"), nuevaYork))
        // Madrid cambia el domingo 25 de octubre: ese domingo ya es UTC+1.
        val madrid = ZoneId.of("Europe/Madrid")
        assertEquals(Instant.parse("2026-10-25T10:00:00Z"), AvisoDomingo.proximo(en(madrid, "2026-10-19T12:00"), madrid))
    }

    /** El mismo momento con otra zona (un viaje, TIMEZONE_CHANGED): otro instante, siempre a las 11:00 del reloj local. */
    @Test
    fun conOtraZonaEsOtroInstante() {
        val ahora = Instant.parse("2026-10-14T18:00:00Z")
        assertEquals(Instant.parse("2026-10-18T14:00:00Z"), AvisoDomingo.proximo(ahora, buenosAires))
        // Madrid el 18 de octubre todavía está en verano (UTC+2).
        assertEquals(Instant.parse("2026-10-18T09:00:00Z"), AvisoDomingo.proximo(ahora, ZoneId.of("Europe/Madrid")))
        // En Tokio ya es jueves a la madrugada: el mismo domingo, 11:00 de allá.
        assertEquals(Instant.parse("2026-10-18T02:00:00Z"), AvisoDomingo.proximo(ahora, ZoneId.of("Asia/Tokyo")))
    }

    /**
     * Hallazgo 8 del 15-oct: el aviso es de una vez. Lo que vuelve a armar el sistema (reinicio, actualización, zona, hora)
     * es SOLO el pendiente: su domingo anotado, a las 11:00 de la zona de ahora. Sin uno anotado, ninguno.
     */
    @Test
    fun loPendienteSeVuelveAArmarALas11DeLaZonaDeAhora() {
        // Lo que se anota al agendar: el domingo en la zona de ese momento.
        val cuando = AvisoDomingo.proximo(en(buenosAires, "2026-10-14T15:00"), buenosAires)
        assertEquals("2026-10-18", AvisoDomingo.anotar(cuando, buenosAires))
        // Al prender el teléfono en la misma zona: el mismo instante.
        assertEquals(cuando, AvisoDomingo.pendiente("2026-10-18", buenosAires))
        // Si cambió la zona (un viaje): las 11:00 de ese domingo allá, no las de Buenos Aires.
        assertEquals(Instant.parse("2026-10-18T09:00:00Z"), AvisoDomingo.pendiente("2026-10-18", ZoneId.of("Europe/Madrid")))
        // Las 11:00 de Tokio de ese domingo son las 23:00 del sábado en Buenos Aires: se anota el domingo de allá.
        val tokio = ZoneId.of("Asia/Tokyo")
        assertEquals("2026-10-18", AvisoDomingo.anotar(AvisoDomingo.proximo(Instant.parse("2026-10-14T18:00:00Z"), tokio), tokio))
        // Sin uno anotado (sonó y la app no se volvió a abrir) o con algo que no es una fecha: no se inventa otro.
        assertNull(AvisoDomingo.pendiente(null, buenosAires))
        assertNull(AvisoDomingo.pendiente("", buenosAires))
        assertNull(AvisoDomingo.pendiente("domingo", buenosAires))
    }

    @Test
    fun cuandoSeRegistraElPush() {
        val p = PreferenciasEnMemoria()
        // Sin cuenta, en la demo, sin el permiso o sin token: nunca.
        assertEquals(RegistroPush.Decision.NO_CORRESPONDE, RegistroPush.decidir(null, false, true, "fcm-1", p))
        assertEquals(RegistroPush.Decision.NO_CORRESPONDE, RegistroPush.decidir("cuentaA_00000000000", true, true, "fcm-1", p))
        assertEquals(RegistroPush.Decision.NO_CORRESPONDE, RegistroPush.decidir("cuentaA_00000000000", false, false, "fcm-1", p))
        assertEquals(RegistroPush.Decision.NO_CORRESPONDE, RegistroPush.decidir("cuentaA_00000000000", false, true, " ", p))
        // La primera vez, sí.
        assertEquals(RegistroPush.Decision.REGISTRAR, RegistroPush.decidir("cuentaA_00000000000", false, true, "fcm-1", p))
        p.guardar(RegistroPush.CLAVE_TOKEN, "fcm-1")
        p.guardar(RegistroPush.CLAVE_CUENTA, RegistroPush.huella("cuentaA_00000000000"))
        // El mismo token con la misma cuenta: ya está, no se repite la RPC en cada arranque.
        assertEquals(RegistroPush.Decision.YA_REGISTRADO, RegistroPush.decidir("cuentaA_00000000000", false, true, "fcm-1", p))
        // FCM lo cambió (onNewToken): de nuevo.
        assertEquals(RegistroPush.Decision.REGISTRAR, RegistroPush.decidir("cuentaA_00000000000", false, true, "fcm-2", p))
        // Otra cuenta en el mismo teléfono, con el mismo token de push: de nuevo (si no, seguía llegando lo de la anterior).
        assertEquals(RegistroPush.Decision.REGISTRAR, RegistroPush.decidir("cuentaB_00000000000", false, true, "fcm-1", p))
        // El registro viejo de la web (solo el token, sin cuenta) se vuelve a mandar una vez.
        val web = PreferenciasEnMemoria(mapOf(RegistroPush.CLAVE_TOKEN to "fcm-1"))
        assertEquals(RegistroPush.Decision.REGISTRAR, RegistroPush.decidir("cuentaA_00000000000", false, true, "fcm-1", web))
    }

    @Test
    fun laHuellaNoEsElToken() {
        val h = RegistroPush.huella("cuentaA_00000000000")
        assertEquals(16, h.length)
        assertFalse("cuentaA" in h)
        assertEquals(h, RegistroPush.huella("cuentaA_00000000000"))
        assertTrue(h != RegistroPush.huella("cuentaB_00000000000"))
    }

    @Test
    fun elRegistroVaComoAndroidConLaVersionYSoloSiCambio() = enUnHilo { alcance ->
        val cuerpos = mutableListOf<ValorJson>()
        val t = TransporteProgramado { fn, cuerpo ->
            if (fn == "mypump_registrar_push") {
                synchronized(cuerpos) { cuerpos += cuerpo }
                200 to "true"
            } else {
                200 to "[]"
            }
        }
        val prefs = PreferenciasEnMemoria()
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("cuentaA_00000000000"), carpetaTemporal("push"), prefs, alcance)
        assertTrue(m.registrarPush("fcm-1", "2.0.0 (100)"))
        val c = cuerpos.single()
        assertEquals("cuentaA_00000000000", c["p_token"]?.comoTexto)
        assertEquals("fcm-1", c["p_device"]?.comoTexto, "el token de FCM va tal cual")
        assertEquals("android", c["p_plataforma"]?.comoTexto)
        assertEquals("2.0.0 (100)", c["p_app_version"]?.comoTexto)
        // Ya registrado: no vuelve a llamar.
        assertTrue(m.registrarPush("fcm-1", "2.0.0 (100)"))
        // Sin permiso, aunque el token sea nuevo, no se manda.
        assertFalse(m.registrarPush("fcm-2", "2.0.0 (100)", conPermiso = false))
        assertEquals(1, cuerpos.size)
        // El token de acceso nunca queda en las preferencias (van a la copia de Google).
        assertTrue(prefs.todo.values.none { "cuentaA" in it }, prefs.todo.toString())
    }

    /** El link de otra cuenta en el mismo teléfono (ACC-10): el mismo token de push se vuelve a registrar con la nueva. */
    @Test
    fun conOtraCuentaSeVuelveARegistrar() = enUnHilo { alcance ->
        val cuentas = mutableListOf<String?>()
        val t = TransporteProgramado { fn, cuerpo ->
            if (fn == "mypump_registrar_push") {
                synchronized(cuentas) { cuentas += cuerpo["p_token"]?.comoTexto }
                200 to "true"
            } else {
                200 to "[]"
            }
        }
        val prefs = PreferenciasEnMemoria()   // las del teléfono: las comparten las dos cuentas
        val a = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("cuentaA_00000000000"), carpetaTemporal("push-a"), prefs, alcance)
        val b = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("cuentaB_00000000000"), carpetaTemporal("push-b"), prefs, alcance)
        assertTrue(a.registrarPush("fcm-1", "2.0.0 (100)"))
        assertTrue(b.registrarPush("fcm-1", "2.0.0 (100)"))
        assertTrue(b.registrarPush("fcm-1", "2.0.0 (100)"))
        assertEquals(listOf<String?>("cuentaA_00000000000", "cuentaB_00000000000"), cuentas)
    }

    /** Si el servidor no lo tomó (false, un error, sin red) no queda anotado: se reintenta en el próximo arranque. */
    @Test
    fun unRechazoNoQuedaComoRegistrado() = enUnHilo { alcance ->
        var respuesta = 200 to "false"
        var llamadas = 0
        val t = TransporteProgramado { fn, _ ->
            if (fn == "mypump_registrar_push") {
                llamadas++
                respuesta
            } else {
                200 to "[]"
            }
        }
        val prefs = PreferenciasEnMemoria()
        val m = ModeloApp(ClienteRpc(transporte = t), TokenEnMemoria("cuentaA_00000000000"), carpetaTemporal("push"), prefs, alcance)
        assertFalse(m.registrarPush("fcm-1", "2.0.0 (100)"))
        respuesta = 400 to """{"code":"P0001","message":"token invalido"}"""
        assertFalse(m.registrarPush("fcm-1", "2.0.0 (100)"))
        assertNull(prefs.leer(RegistroPush.CLAVE_TOKEN))
        respuesta = 200 to "true"
        assertTrue(m.registrarPush("fcm-1", "2.0.0 (100)"))
        assertEquals(3, llamadas)
        assertEquals("fcm-1", prefs.leer(RegistroPush.CLAVE_TOKEN))
    }

    @Test
    fun tocarUnAvisoLlevaASuDestino() {
        val propio = setOf(DestinoAviso.EXTRA_AVISO, DestinoAviso.EXTRA_DESTINO)
        // Los que publica la app: el domingo, el fin del descanso y el push con la app abierta.
        assertEquals(DestinoAviso.REVISION, DestinoAviso.alTocar(propio, AvisoDomingo.DESTINO))
        assertEquals(DestinoAviso.ENTRENO, DestinoAviso.alTocar(propio, "train"))
        assertEquals(DestinoAviso.MIS_DATOS, DestinoAviso.alTocar(propio, "salud"))
        // El que mostró el sistema con la app en segundo plano: FCM agrega sus claves a los datos de push.py.
        val fcm = setOf(DestinoAviso.EXTRA_FCM, "from", "google.sent_time", DestinoAviso.EXTRA_DESTINO)
        assertEquals(DestinoAviso.DIETA, DestinoAviso.alTocar(fcm, "diet"))
        assertEquals(DestinoAviso.MI_DIA, DestinoAviso.alTocar(fcm, "myday"))
        // Sin destino o con el histórico "comentarios": Chat.
        assertEquals(DestinoAviso.CHAT, DestinoAviso.alTocar(setOf(DestinoAviso.EXTRA_FCM, "from"), null))
        assertEquals(DestinoAviso.CHAT, DestinoAviso.alTocar(fcm, "comentarios"))
        // Abrir desde el ícono o un link no es tocar un aviso, aunque traiga un "destino" suelto.
        assertNull(DestinoAviso.alTocar(emptySet(), null))
        assertNull(DestinoAviso.alTocar(setOf(DestinoAviso.EXTRA_DESTINO), "diet"))
    }
}
