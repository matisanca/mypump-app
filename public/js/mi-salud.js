/* =============================================================
   mi-salud.js — «Mi salud» (pedido de Mati, 11/11; va con la palanca `web_230`): una sola pantalla con todo lo de
   salud, que se abre desde Revisión. Acá solo la lógica pura: qué bloques se ven, la tarjeta de Revisión (número y
   línea) y adónde lleva cada `destino` viejo. Lo que muestra cada bloque es de su sección (Estudios, Presión, Salud):
   esto no inventa palancas ni condiciones, solo lee las que ya existen.
   Alineado con iPhone y Android: nativa-evidencia/mi-salud/DECISIONES.md.
   ============================================================= */
(function (raiz) {
  'use strict';

  const T = {
    titulo: 'Mi salud',
    volver: 'Revisión',
    estudios: 'Estudios y órdenes',
    presion: 'Presión arterial',
    verPresion: 'Ver mis tomas y cómo medirme',
    recuperacion: 'Recuperación',
    control: 'Tu próximo control de salud',
    presionRepetir: 'Te falta repetir la toma de presión',
    presionPreparar: 'Primero medí tu brazo y anotá tu tensiómetro',
    presionFaltan: (n) => (n === 1 ? 'Te falta 1 toma de presión' : `Te faltan ${n} tomas de presión`),
    pendientes: (n) => (n === 1 ? '1 cosa para hacer' : `${n} cosas para hacer`),
    entradaMisDatos: 'Mi salud',
    pieMisDatos: 'Tus controles, estudios, presión y recuperación, y la conexión con tu reloj.',
  };

  /* El orden de la pantalla. */
  const BLOQUES = ['control', 'estudios', 'presion', 'recuperacion'];
  const NOMBRES = { control: 'control', estudios: 'estudios y órdenes', presion: 'presión', recuperacion: 'recuperación' };
  const TOPE = 3;

  /* e: lo que dicen hoy las secciones.
       { estudios: bool (la sección existe), proximoControl: bool, tarjetaEstudios: { titulo } | null (la de Entreno),
         controlCerca: bool (la tarjeta del control, desde `avisar_desde`), presion: bool (la sección existe),
         tarjetaPresion: { estado: 'repetir'|'preparar'|'toma'|'hoyListo', faltan } | null, recuperacion: bool } */
  function bloques(e) {
    const x = e || {};
    const ve = {
      control: !!(x.estudios && x.proximoControl),
      estudios: !!x.estudios,
      presion: !!x.presion,
      recuperacion: !!x.recuperacion,
    };
    return BLOQUES.filter((b) => ve[b]);
  }

  /* «Control, estudios y órdenes, presión y recuperación»: lo que hay adentro, en el orden de la pantalla. */
  function lista(bs) {
    const n = (bs || []).map((b) => NOMBRES[b]).filter(Boolean);
    if (!n.length) return '';
    const s = n.length === 1 ? n[0] : `${n.slice(0, -1).join(', ')} y ${n[n.length - 1]}`;
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  /* Lo pendiente, por prioridad: estudios, control, presión. «La de hoy ya está» no cuenta. */
  function pendientes(e) {
    const x = e || {}, l = [];
    if (x.estudios && x.tarjetaEstudios && x.tarjetaEstudios.titulo) l.push({ bloque: 'estudios', texto: x.tarjetaEstudios.titulo });
    if (x.estudios && x.controlCerca) l.push({ bloque: 'control', texto: T.control });
    const p = x.presion ? x.tarjetaPresion : null;
    if (p && p.estado === 'repetir') l.push({ bloque: 'presion', texto: T.presionRepetir });
    else if (p && p.estado === 'preparar') l.push({ bloque: 'presion', texto: T.presionPreparar });
    else if (p && p.estado === 'toma') l.push({ bloque: 'presion', texto: T.presionFaltan(Math.max(1, Number(p.faltan) || 1)) });
    return l;
  }

  /* La tarjeta grande de Revisión: null si no hay ningún bloque (entonces no aparece). */
  function tarjeta(e) {
    const bs = bloques(e);
    if (!bs.length) return null;
    const p = pendientes(e);
    const numero = Math.min(TOPE, p.length);
    return { bloques: bs, numero, linea: numero ? p[0].texto : lista(bs), primero: numero ? p[0].bloque : null };
  }

  /* Los `destino` viejos (avisos, links, novedades) que ahora abren «Mi salud» en su bloque. El resto sigue igual (null). */
  const DESTINOS = { estudios: 'estudios', presion: 'presion', salud: 'recuperacion', myday: 'recuperacion', misalud: null };
  function destino(d) {
    if (typeof d !== 'string' || !Object.prototype.hasOwnProperty.call(DESTINOS, d)) return null;
    return { escena: 'misalud', bloque: DESTINOS[d] };
  }

  /* La tarjeta de presión de Entreno, solo cuando pide algo («La de hoy ya está» queda en Mi salud). */
  const presionPideAlgo = (t) => !!t && (t.estado === 'repetir' || t.estado === 'preparar' || t.estado === 'toma');

  const API = { T, BLOQUES, TOPE, bloques, lista, pendientes, tarjeta, destino, presionPideAlgo };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.MiSalud = API;
})(typeof window !== 'undefined' ? window : globalThis);
