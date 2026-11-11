/* El doble de prueba de la agenda de la videollamada (2.3.0), para las pruebas y las capturas de la web.
   Es el equivalente de ServidorAgendaUI (apps/ios/MyPump/Guia/AgendaView.swift): responde como entregas_app_agenda,
   entregas_app_reservar y entregas_app_cambiar, sin red. Nunca llama a producción ni crea links de Meet: el link es
   de mentira. Datos inventados, ningún cliente real.

   Escenarios:
   · elegir     franjas a las 10 y a las 12 de Argentina, 1 h, los próximos 5 días hábiles; sin reserva. Reservar la
                deja confirmada enseguida (con un cambio disponible).
   · diasAntes  confirmada en la 3.ª franja de la lista, con 1 cambio disponible hasta 24 h antes.
   · porEntrar  confirmada que empieza en 6 minutos y medio: «Entrar» ya está habilitado.

   Se usa en el navegador (window.DobleAgenda) y en node (require). */
(function (raiz) {
  'use strict';

  const MEET_DE_MENTIRA = 'https://meet.google.com/abc-defg-hij';
  const ESCENARIOS = ['elegir', 'diasAntes', 'porEntrar'];
  const ART_MS = -3 * 3600000;   // Argentina no tiene horario de verano
  const dos = n => String(n).padStart(2, '0');

  // «2026-11-12T10:00:00-03:00» para ese día (en Argentina) y esa hora.
  function isoArt(diaUTC, hora) {
    const d = new Date(diaUTC);
    return `${d.getUTCFullYear()}-${dos(d.getUTCMonth() + 1)}-${dos(d.getUTCDate())}T${dos(hora)}:00:00-03:00`;
  }
  // El ISO con la zona de Argentina de un instante.
  function isoDe(t) {
    const d = new Date(t + ART_MS);
    return `${d.getUTCFullYear()}-${dos(d.getUTCMonth() + 1)}-${dos(d.getUTCDate())}T${dos(d.getUTCHours())}:${dos(d.getUTCMinutes())}:${dos(d.getUTCSeconds())}-03:00`;
  }

  // Los próximos `n` días hábiles después de hoy (en Argentina), a la medianoche UTC de esa fecha.
  function diasHabiles(ahora, n) {
    const hoy = new Date(ahora.getTime() + ART_MS);
    let d = Date.UTC(hoy.getUTCFullYear(), hoy.getUTCMonth(), hoy.getUTCDate());
    const fuera = [];
    while (fuera.length < n) {
      d += 86400000;
      const sem = new Date(d).getUTCDay();
      if (sem !== 0 && sem !== 6) fuera.push(d);
    }
    return fuera;
  }

  function crear(escenario, opciones) {
    if (!ESCENARIOS.includes(escenario)) throw new Error(`escenario desconocido: ${escenario}`);
    const o = opciones || {};
    const ahora = () => (o.ahora ? new Date(o.ahora) : new Date());
    const base = ahora();
    const llamadas = [];
    let cambios = 0;

    // Las franjas de la videollamada 2.3.0: 10 y 12 de Argentina, 1 h, 5 días hábiles.
    const franjas = [];
    for (const d of diasHabiles(base, 5)) {
      for (const h of [10, 12]) franjas.push({ id: `f${franjas.length + 1}`, inicio: isoArt(d, h), fin: isoArt(d, h + 1) });
    }
    let reserva = null;
    if (escenario === 'diasAntes') {
      reserva = { id: 'r1', inicio: franjas[2].inicio, fin: franjas[2].fin, estado: 'confirmada', tipo: 'comienzo', meet_url: MEET_DE_MENTIRA, sala_abierta_en: null };
    } else if (escenario === 'porEntrar') {
      const i = base.getTime() + (6 * 60 + 30) * 1000;
      reserva = { id: 'r1', inicio: isoDe(i), fin: isoDe(i + 3600000), estado: 'confirmada', tipo: 'comienzo', meet_url: MEET_DE_MENTIRA, sala_abierta_en: null };
    }

    function agenda() {
      // Con un cambio disponible (diasAntes, o elegir después de reservar), van las franjas para cambiar (sin la suya).
      let cambio = null;
      if ((escenario === 'diasAntes' || escenario === 'elegir') && reserva && reserva.estado === 'confirmada') {
        cambio = { permitido: cambios < 1, restantes: Math.max(0, 1 - cambios), hasta: isoDe(new Date(reserva.inicio).getTime() - 24 * 3600000) };
      }
      const vigente = !!reserva && (reserva.estado === 'confirmada' || reserva.estado === 'pendiente');
      const libres = franjas.filter(f => !reserva || f.inicio !== reserva.inicio);
      return {
        ok: true, autorizada: true, habilitada: true, faltan: 0, zona: 'America/Argentina/Buenos_Aires', tipo: 'comienzo',
        entrar_desde_min: 10, aviso_min: 30, textos: {},
        franjas: !vigente || (cambio && cambio.permitido) ? libres : [],
        reserva: reserva ? Object.assign({}, reserva) : null,
        cambio,
      };
    }

    const doble = {
      escenario, llamadas, MEET_DE_MENTIRA,
      get reserva() { return reserva ? Object.assign({}, reserva) : null; },
      agenda,

      // Lo que pide guia.js a window.mypumpDB.
      async getGuiaResumen() {
        return { ok: true, total: 13, vistos: 13, minutos_restantes: 0, fecha_entrega: null, mostrar_tarjeta: true,
                 reserva: reserva ? Object.assign({}, reserva) : null };
      },
      async getAgendaGuia(token) {
        llamadas.push({ fn: 'entregas_app_agenda', p_token: token });
        return { success: true, data: agenda() };
      },
      async reservarEntregaGuia(token, franja, id) {
        llamadas.push({ fn: 'entregas_app_reservar', p_token: token, p_franja: franja, p_id: id });
        const f = franjas.find(x => x.id === franja);
        if (!f) return { success: true, data: { ok: false, motivo: 'franja' } };
        if (reserva && (reserva.estado === 'confirmada' || reserva.estado === 'pendiente')) return { success: true, data: { ok: false, motivo: 'ya_tiene', reserva } };
        // Como pide el contrato: si el daemon ya la confirmó, vuelve confirmada y con el link (acá, de mentira).
        reserva = { id, inicio: f.inicio, fin: f.fin, estado: 'confirmada', tipo: 'comienzo', meet_url: MEET_DE_MENTIRA, sala_abierta_en: null };
        return { success: true, data: { ok: true, reserva: Object.assign({}, reserva) } };
      },
      async cambiarEntregaGuia(token, vieja, franja, id) {
        llamadas.push({ fn: 'entregas_app_cambiar', p_token: token, p_reserva: vieja, p_franja: franja, p_id: id });
        const f = franjas.find(x => x.id === franja);
        if (!f || !reserva) return { success: true, data: { ok: false, motivo: f ? 'sin_reserva' : 'franja' } };
        if (cambios >= 1) return { success: true, data: { ok: false, motivo: 'tope' } };
        cambios++;
        reserva = Object.assign({}, reserva, { inicio: f.inicio, fin: f.fin, estado: 'confirmada' });
        return { success: true, data: { ok: true, reserva: Object.assign({}, reserva) } };
      },
      async getAppConfig() { return { elegir_horario: true }; },
      async getGuia() { return null; },
      async getAudiosGuia() { return { success: true, data: [] }; },
    };
    return doble;
  }

  const API = { crear, ESCENARIOS, MEET_DE_MENTIRA, diasHabiles };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.DobleAgenda = API;
})(typeof window !== 'undefined' ? window : globalThis);
