/* =============================================================
   controles.js — «Tu próximo control de salud» (pedido de Mati, 11/11; palanca `controles_app`): la lógica pura de lo
   que devuelve `mypump_controles_get` (supabase/propuestas/nativa_controles_salud.sql). Gemela de iOS y Android: los
   vectores de scripts/vectores-app/controles.json (copia exacta de apps/shared/vectores/controles.json) hacen fallar
   las pruebas si difieren. La web solo lee. Nunca el ciclo, fármacos ni «IA»: solo «Mati» y «control de salud».
   Usa las fechas de js/estudios.js (el control vive dentro de Estudios).
   ============================================================= */
(function (raiz) {
  'use strict';
  const E = typeof module !== 'undefined' && module.exports ? require('./estudios.js') : raiz.Estudios;

  const T = {
    cejaInicio: 'Control de salud',
    tituloInicio: 'Tu próximo control de salud',
    verMisEstudios: 'Ver mis estudios',
    notaProgramado: 'Te vamos a mandar las órdenes unos días antes.',
    notaOrdenes: 'Ya te mandamos las órdenes. Están más abajo, en Tus órdenes.',
    notaOrdenesSinLista: 'Ya te mandamos las órdenes.',       // mandadas por fuera de la app: no hay «Tus órdenes»
    tituloPorDefecto: 'Control de salud',
    hitosTitulo: 'Tus controles de salud',
    hitoProximo: 'Próximo',
    hitoRecibido: 'Recibido',
    hitoVisto: 'Mati lo vio',
  };
  const TITULO_MAX = 60;

  const PROHIBIDAS = new Set(['ciclo', 'ciclos', 'posciclo', 'posciclos', 'postciclo', 'postciclos', 'pct', 'trt', 'blast', 'cruise',
    'nandrolona', 'trembolona', 'oxandrolona', 'estanozolol', 'primobolan', 'boldenona', 'masteron', 'sarm', 'sarms', 'peptido',
    'peptidos', 'dosis', 'mg', 'ml', 'ui', 'ia']);
  const PREFIJOS = ['farmac', 'testo', 'esteroid', 'anabolic', 'androgen', 'hormona'];

  /* El título del servidor, si es corto y no nombra nada del ciclo (el servidor ya lo controla: esta es la segunda llave).
     Si no, «Control de salud». */
  function titulo(s) {
    const t = typeof s === 'string' ? s.trim() : '';
    if (!t || [...t].length > TITULO_MAX) return T.tituloPorDefecto;
    const plano = t.toLowerCase().normalize('NFD').replace(/\p{M}+/gu, '');
    const palabras = plano.split(/[^\p{L}\p{N}]+/u).filter(Boolean);
    const malo = palabras.some((p) => PROHIBIDAS.has(p) || PREFIJOS.some((x) => p.startsWith(x))) || plano.includes('inteligencia artificial');
    return malo ? T.tituloPorDefecto : t;
  }

  const numero = (d) => Math.round(Date.UTC(d.anio, d.mes - 1, d.dia) / 86400000);

  /* «lunes 16/11», con el año si no es el de hoy: «lunes 4/1/2027». */
  const conDia = (d, hoy) => (hoy && hoy.anio !== d.anio ? `${E.conDia(d)}/${d.anio}` : E.conDia(d));
  /* «El lunes 16/11» o, si ya pasó, «Era para el lunes 9/11» (sin tono de alarma). */
  const cuando = (d, hoy) => (hoy && numero(d) < numero(hoy) ? `Era para el ${conDia(d, hoy)}` : `El ${conDia(d, hoy)}`);

  /* 'programado' (también sin el campo) | 'ordenes_enviadas' | 'resultado_subido' | 'revisado' | 'otro' (uno que esta versión no conoce). */
  function estadoDe(s) {
    if (s === undefined || s === null || s === 'programado') return 'programado';
    return ['ordenes_enviadas', 'resultado_subido', 'revisado'].includes(s) ? s : 'otro';
  }
  const cerrado = (e) => e === 'resultado_subido' || e === 'revisado';
  const objeto = (x) => !!x && typeof x === 'object' && !Array.isArray(x);

  function control(j) {
    if (!objeto(j)) return null;
    const f = E.dia(j.fecha_objetivo);
    if (!f) return null;
    return { titulo: titulo(j.titulo_alumno), fecha: f, avisarDesde: E.dia(j.avisar_desde), estado: estadoDe(j.estado) };
  }

  /* null: token caído, palanca apagada en el servidor o una respuesta que no es la esperada. */
  function decodificar(j) {
    if (!objeto(j) || j.habilitado !== true) return null;
    const p = control(j.proximo);
    return {
      hoy: E.dia(j.hoy),
      proximo: p && !cerrado(p.estado) ? p : null,
      ultimos: (Array.isArray(j.ultimos) ? j.ultimos : []).map(control).filter((c) => c && cerrado(c.estado)).slice(0, 3),
    };
  }

  const nota = (e, hayOrdenes) => (e === 'programado' ? T.notaProgramado : e === 'ordenes_enviadas' ? (hayOrdenes ? T.notaOrdenes : T.notaOrdenesSinLista) : null);

  /* El bloque «Próximo control» de Estudios, alimentado por el control. null sin próximo. `hayOrdenes`: si Estudios muestra
     «Tus órdenes» (si no, la nota no manda a buscarlas ahí). */
  function proximoParaEstudios(e, hayOrdenes = true) {
    if (!e || !e.proximo) return null;
    const c = e.proximo;
    return { tipo: null, titulo: c.titulo, desde: null, hasta: null, cuando: cuando(c.fecha, e.hoy), nota: nota(c.estado, hayOrdenes) };
  }

  /* La tarjeta de arriba de la primera pestaña: desde `avisar_desde` y mientras siga programado. `hoyTelefono` cuenta solo
     si el servidor no mandó `hoy`; sin ninguno de los dos no se muestra (mejor nada que antes de tiempo). */
  function tarjetaInicio(e, hoyTelefono) {
    if (!e || !e.proximo) return null;
    const c = e.proximo, hoy = e.hoy || hoyTelefono || null;
    if (c.estado !== 'programado' || !c.avisarDesde || !hoy || numero(c.avisarDesde) > numero(hoy)) return null;
    return { titulo: T.tituloInicio, cuando: cuando(c.fecha, hoy), nota: T.notaProgramado, boton: T.verMisEstudios };
  }

  /* «Tu recorrido»: el próximo y los últimos, cada uno con su fecha. */
  function hitos(e) {
    if (!e) return [];
    const l = [];
    if (e.proximo) l.push({ titulo: e.proximo.titulo, cuando: conDia(e.proximo.fecha, e.hoy), estado: T.hitoProximo });
    for (const u of e.ultimos) l.push({ titulo: u.titulo, cuando: conDia(u.fecha, e.hoy), estado: u.estado === 'revisado' ? T.hitoVisto : T.hitoRecibido });
    return l;
  }

  const API = { T, TITULO_MAX, titulo, conDia, cuando, decodificar, proximoParaEstudios, tarjetaInicio, hitos };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.Controles = API;
})(typeof window !== 'undefined' ? window : globalThis);
