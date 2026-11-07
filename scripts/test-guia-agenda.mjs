// «Tu guía» 2.2.0 en la web: novedad, videos obligatorios, agenda de la entrega y recorte de las franjas negras.
// Vectores portados de la app (rama nativa-220): MyPumpKit/Tests/MyPumpReglasTests/AgendaTests.swift, GuiaTests.swift y
// FormatoVideoTests.swift. Corre las reglas de public/js/reglas-guia.js, las mismas que usa public/js/guia.js.
// Datos inventados (GuiaMuestra de la app): ningún cliente real.
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

const require = createRequire(import.meta.url);
const G = require('../public/js/reglas-guia.js');
const { R, RA, RV } = G;
let n = 0;
const ok = (c, m) => { assert.ok(c, m); n++; };
const eq = (a, b, m) => { assert.deepEqual(a, b, m); n++; };
const cerca = (a, b, m, tol = 1e-4) => { assert.ok(Math.abs(a - b) < tol, `${m}: ${a} ≠ ${b}`); n++; };
const fecha = s => R.instante(s);
const guia = j => G.normalizarGuia(j);
const agenda = j => G.normalizarAgenda(j);
const resumen = j => G.normalizarResumen(j);
const avance = (a, b, m) => { eq([a.total, a.vistos], [b.total, b.vistos], m); cerca(a.minutosRestantes, b.minutosRestantes, m); };

// ── GuiaMuestra (la app): «Tomás», inventado ──
function clip(id, titulo, bloque, minutos, o = {}) {
  return { id, titulo, url: o.url === false ? null : `https://videos.example.invalid/videos-entrega/${id}.mp4`, yt_id: null, minutos,
           motivo: o.motivo || 'Para qué te sirve este video', bloque, visto: !!o.visto, segundos: o.segundos || 0, duda: o.duda || null };
}
const MUESTRA = {
  ok: true, nombre_pila: 'Tomás', fecha_entrega: null,
  clips: [
    clip('FT-25a', '¿Cómo funciona la app?', 'Tu app', 1.2, { visto: true }),
    clip('FT-2b', '¿Cómo subo las cargas semana a semana?', 'Tu app', 0.3, { visto: true }),
    clip('FT-2c', '¿Cómo cierro el entrenamiento y paso de semana?', 'Tu app', 0.3, { visto: true }),
    clip('FT-9a', '¿Cómo sustituyo un alimento en la app?', 'Tu app', 0.6, { visto: true }),
    clip('FT-2a', '¿Qué subo en la revisión semanal?', 'Tu app', 0.3, { segundos: 9 }),
    clip('MC-7a', '¿Por qué tu primera serie efectiva te sale floja?', 'Lo que no te podés saltear', 1.8),
    clip('FT-3a', '¿Cómo hago el calentamiento y las aproximaciones?', 'Lo que no te podés saltear', 1.2),
    clip('MC-13c', 'Anotá cargas y repeticiones para saber si progresás', 'Tu entrenamiento', 1.2),
    clip('FT-5a', '¿Para qué uso straps en espalda?', 'Tu entrenamiento', 0.5, { url: false }),
    clip('FT-26a', '¿Peso la comida cruda o cocida?', 'Tu alimentación', 0.6),
    clip('FT-17a', '¿Qué verduras puedo comer libres?', 'Tu alimentación', 0.6),
    clip('FT-1b', '¿Para qué sirve la citrulina?', 'Tu suplementación', 0.7),
    clip('FT-4b', '¿Qué magnesio compro y por qué los comunes no sirven?', 'Tu suplementación', 0.5, { visto: true }),
  ],
  dudas_llamada: [{ texto: '¿Puedo entrenar a la noche?', en: '2026-11-04T10:12:00-03:00' }],
  suplementacion: {
    titulo: 'Tu suplementación', dia: [],
    items: [
      { nombre: 'L-citrulina', estado: 'nuevo', momento: 'pre', cantidad: '6 g', video_id: 'FT-1b' },
      { nombre: 'Bisglicinato de magnesio', estado: 'sigue', momento: 'dormir', cantidad: '400 mg', video_id: 'FT-4b' },
    ],
  },
};
function v2(c, nuevo, obligatorio) { return Object.assign(c, { nuevo, obligatorio }); }
const MUESTRA_V2 = {
  ok: true, nombre_pila: 'Tomás', fecha_entrega: null, fase: 2, novedad_en: '2026-11-05T12:00:00-03:00',
  clips: [
    v2(clip('FT-25a', '¿Cómo funciona la app?', 'Tu app', 1.2, { visto: true }), false, true),
    v2(clip('FT-2b', '¿Cómo subo las cargas semana a semana?', 'Tu app', 0.3, { visto: true }), false, true),
    v2(clip('MC-7a', '¿Por qué tu primera serie efectiva te sale floja?', 'Lo que no te podés saltear', 1.8, { visto: true }), false, true),
    v2(clip('FT-26a', '¿Peso la comida cruda o cocida?', 'Tu alimentación', 0.6), false, false),
    v2(clip('N-1', 'Lo que cambia en tu entrenamiento', 'Tu entrenamiento', 0.4), true, true),
    v2(clip('N-2', 'Cómo ajustamos tu dieta esta etapa', 'Tu alimentación', 0.8, { visto: true }), true, true),
  ],
  dudas_llamada: [], suplementacion: null,
};
const g1 = () => guia(structuredClone(MUESTRA));
const g2 = () => guia(structuredClone(MUESTRA_V2));

// ── Novedad (NovedadTests) ──
{
  const g = g2();
  ok(g.fase === 2 && g.novedadEn === '2026-11-05T12:00:00-03:00', 'fase y novedad_en');
  const l = R.deLaLista(g);
  eq(l.map(c => c.id), ['N-1', 'N-2', 'FT-25a', 'FT-2b', 'MC-7a', 'FT-26a'], 'los nuevos en su orden, después lo de siempre');
  const b = R.bloques(l);
  ok(b[0].novedad && b[0].titulo === 'Novedad' && b[0].id === R.ID_NOVEDAD && !b[0].esApp, 'el bloque Novedad');
  eq(b[0].indices, [0, 1], 'índices de Novedad');
  eq(R.textoBloque(b[0]), '2 videos nuevos para vos · 1 min', 'texto de Novedad');
  ok(b.slice(1).every(x => !x.novedad && x.indices.every(i => !l[i].nuevo)), 'debajo, solo los que no son nuevos');
  eq(b.find(x => x.titulo === 'Tu alimentación').indices, [5], 'N-2 no se repite en su capítulo');
  ok(R.claveBloque(l[0]) === R.ID_NOVEDAD && R.claveBloque(l[2]) === 'Tu app', 'claveBloque');
}
{
  const g = g1();
  ok(g.fase === 1 && g.novedadEn === null && g.clips.every(c => !c.nuevo && c.obligatorio === null), 'sin campos, la 2.1.0');
  const l = R.deLaLista(g);
  eq(l[0].id, 'FT-25a', 'orden de la 2.1.0');
  ok(R.bloques(l).every(x => !x.novedad), 'sin Novedad');
  eq(R.textoBloque(R.bloques(l)[0]), '5 videos, unos 3 minutos', 'texto de bloque');
}
{
  const g = guia({ ok: true, clips: [{ id: 'a', titulo: 'A', url: 'https://x.invalid/a.mp4', minutos: 1, bloque: 'Novedad', nuevo: false },
                                     { id: 'b', titulo: 'B', url: 'https://x.invalid/b.mp4', minutos: 2, nuevo: true }] });
  const b = R.bloques(R.deLaLista(g));
  ok(b.length === 2 && new Set(b.map(x => x.id)).size === 2, 'un bloque del servidor llamado Novedad no choca');
  eq(R.textoBloque(b[0]), '1 video nuevo para vos · 2 min', 'uno nuevo');
}
{
  const g = g2();
  avance(R.avanceNovedad(null, g), { total: 2, vistos: 1, minutosRestantes: 0.4 }, 'la tarjeta cuenta solo los nuevos');
  eq(R.textoTarjetaNovedad(R.avanceNovedad(null, g)), '1 de 2 videos nuevos, te queda 1 min', 'texto de la tarjeta');
  eq(R.textoTarjetaNovedad({ total: 3, vistos: 0, minutosRestantes: 9 }), '3 videos nuevos, unos 9 min', 'texto sin ver');
  const vista = g2(); vista.clips.forEach(c => { c.visto = true; });
  eq(R.avanceNovedad(null, vista), null, 'con todo lo nuevo visto, la de la 2.1.0');
  const sin = g2(); sin.novedadEn = null;
  eq(R.avanceNovedad(null, sin), null, 'sin novedad_en, la de la 2.1.0');
}
{
  const r = resumen({ ok: true, total: 6, vistos: 4, minutos_restantes: 1.0, novedad_en: '2026-11-05T12:00:00-03:00', nuevos_total: 3, nuevos_vistos: 1 });
  ok(r.nuevosTotal === 3 && r.nuevosVistos === 1, 'nuevos del resumen');
  avance(R.avanceNovedad(r, g2()), { total: 3, vistos: 1, minutosRestantes: 0.4 }, 'los minutos, de la copia al día');
  avance(R.avanceNovedad(r, null), { total: 3, vistos: 1, minutosRestantes: 1.0 }, 'sin copia, los del resumen');
  const completo = resumen({ ok: true, total: 6, vistos: 6, novedad_en: '2026-11-05T12:00:00-03:00', nuevos_total: 3, nuevos_vistos: 3 });
  eq(R.avanceNovedad(completo, null), null, 'todo lo nuevo visto');
  eq(resumen({ ok: true, nuevos_total: 2, nuevos_vistos: 9 }).nuevosVistos, 2, 'nuevos_vistos de más se recorta');
  eq(resumen({ ok: true, nuevos_vistos: 1 }).nuevosVistos, null, 'sin nuevos_total no hay nuevos_vistos');
}
{
  const r = resumen({ ok: true, total: 13, vistos: 11, minutos_restantes: 2.5, novedad_en: '2026-11-05T12:00:00-03:00' });
  avance(R.avanceNovedad(r, g1()), { total: 13, vistos: 11, minutosRestantes: 2.5 }, 'copia vieja: con el resumen');
  const g = g1(); g.novedadEn = '2026-11-05T12:00:00-03:00';
  eq(R.avanceNovedad(r, g), null, 'la copia al día y sin nuevos: nada');
}
{
  const marca = fecha('2026-11-04T18:00:00-03:00');
  ok(R.quitadaVigente(true, marca, null), 'sin novedad, la 2.1.0');
  ok(!R.quitadaVigente(false, null, '2026-11-05T12:00:00-03:00'), 'sin quitar');
  ok(!R.quitadaVigente(true, marca, '2026-11-05T12:00:00-03:00'), 'novedad posterior: vuelve');
  ok(R.quitadaVigente(true, marca, '2026-11-03T12:00:00-03:00'), 'novedad anterior: sigue oculta');
  ok(R.quitadaVigente(true, marca, '2026-11-04 21:00:00+00'), 'la misma: sigue oculta');
  ok(R.quitadaVigente(true, fecha('2026-11-06T09:00:00-03:00'), '2026-11-05T12:00:00-03:00'), 'ocultar de nuevo');
  ok(!R.quitadaVigente(true, null, '2026-11-05T12:00:00-03:00'), 'marca sin fecha con novedad: vuelve');
  ok(R.quitadaVigente(true, null, 'ayer'), 'una novedad que no se entiende no cambia nada');
}

// ── Obligatorios (ObligatoriosTests) ──
{
  const g = g2();
  eq(RA.obligatorios(g).map(c => c.id), ['N-1', 'N-2', 'FT-25a', 'FT-2b', 'MC-7a'], 'con el campo cuentan los marcados');
  eq(RA.faltan(g), 1, 'falta 1');
  eq(RA.primeroQueFalta(g).id, 'N-1', 'el primero que falta');
  ok(!RA.esObligatorio(g.clips.find(c => c.id === 'FT-26a'), g), 'FT-26a no');
  const todo = g2(); todo.clips.find(c => c.id === 'N-1').visto = true;
  ok(RA.faltan(todo) === 0 && RA.primeroQueFalta(todo) === null, 'todo visto');
}
{
  const g = g1();
  const o = RA.obligatorios(g);
  ok(o.length === 10 && !o.some(c => ['FT-5a', 'FT-1b', 'FT-4b'].includes(c.id)), 'sin el campo: los de la lista con url');
  eq(RA.faltan(g), 6, 'faltan 6');
  eq(RA.primeroQueFalta(g).id, 'FT-2a', 'primero que falta');
  eq(RA.textoContador(6), 'Te faltan 6 videos para habilitar la agenda', 'contador');
  eq(RA.textoContador(1), 'Te falta 1 video para habilitar la agenda', 'contador 1');
  eq(RA.textoBloqueada(1), 'Cuando termines los videos de arriba se habilita la agenda. Te falta 1.', 'bloqueada 1');
}
{
  const g = guia({ ok: true, clips: [{ id: 'a', titulo: 'A', url: 'https://x.invalid/a.mp4', minutos: 1, obligatorio: true },
                                     { id: 'b', titulo: 'B', url: 'https://x.invalid/b.mp4', minutos: 1 }] });
  eq(RA.obligatorios(g).map(c => c.id), ['a'], 'con uno solo con el campo, los demás no cuentan');
  eq(RA.faltan(null), 0, 'sin guía');
}
{
  const g = guia({ ok: true, fase: '2', novedad_en: '  ', clips: [{ id: 'a', titulo: 'A', minutos: 1, nuevo: 1, obligatorio: 'true' },
                                                                   { id: 'b', titulo: 'B', minutos: 1, nuevo: null, obligatorio: 0 }] });
  ok(g.fase === 2 && g.novedadEn === null, 'campos tolerantes');
  ok(g.clips[0].nuevo && g.clips[0].obligatorio === true, 'nuevo 1, obligatorio "true"');
  ok(!g.clips[1].nuevo && g.clips[1].obligatorio === false, 'nuevo null, obligatorio 0');
  eq(guia({ ok: true, fase: 7, clips: [] }).fase, 1, 'fase 7 es 1');
}

// ── Agenda: decodificar (AgendaDecodificarTests) ──
{
  const a = agenda({ ok: true, autorizada: true, habilitada: true, faltan: 0, zona: 'America/Argentina/Buenos_Aires', extra: { x: 1 },
    franjas: [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00', coach: 'no importa' },
              { id: 'f2', inicio: '2026-11-12T14:00:00-03:00', fin: '2026-11-12T16:00:00-03:00' },
              { id: '', inicio: '2026-11-13T10:00:00-03:00', fin: '2026-11-13T12:00:00-03:00' },
              { id: 'f3', inicio: null, fin: 'x' }, null, 7,
              { id: 'f1', inicio: '2026-11-14T10:00:00-03:00', fin: '2026-11-14T12:00:00-03:00' }],
    reserva: null });
  ok(a.ok && a.autorizada && a.habilitada && a.faltan === 0 && a.zona === 'America/Argentina/Buenos_Aires', 'completa');
  eq(a.franjas.map(f => f.id), ['f1', 'f2'], 'las rotas y las repetidas no van');
  eq(a.reserva, null, 'sin reserva');
}
{
  ok(!agenda({ ok: false, motivo: 'token' }).ok, 'ok false');
  eq(agenda({ ok: false, motivo: 'sin_guia' }).motivo, 'sin_guia', 'motivo');
  ok(!agenda(null).ok && !agenda(false).ok && !agenda([]).ok, 'null, false, lista');
  ok(!agenda({ habilitada: true }).ok, 'sin ok no hay agenda');
}
{
  const a = agenda({ ok: true, habilitada: true, faltan: '2', franjas: [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' }] });
  ok(a.ok && !a.autorizada && !a.habilitada && a.franjas.length === 0 && a.faltan === 2, 'sin autorizada no hay habilitada ni franjas');
  const b = agenda({ ok: true, autorizada: true, habilitada: false, faltan: -3, franjas: [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' }] });
  ok(b.autorizada && !b.habilitada && b.franjas.length === 0 && b.faltan === 0, 'faltan negativo es 0');
}
{
  const R1 = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' };
  const p = agenda({ ok: true, autorizada: true, habilitada: true, franjas: [{ id: 'f1', ...R1 }], reserva: { id: 'r1', ...R1, estado: 'pendiente', meet_url: null, motivo: null } });
  ok(p.reserva.estado === 'pendiente' && p.reserva.id === 'r1' && p.reserva.meetUrl === null, 'pendiente');
  eq(p.franjas.length, 0, 'con la reserva vigente no van franjas');
  const c = agenda({ ok: true, autorizada: true, habilitada: true, reserva: { id: 'r1', ...R1, estado: 'CONFIRMADA', meet_url: ' https://meet.google.com/abc-defg-hij ' } });
  ok(c.reserva.estado === 'confirmada' && c.reserva.meetUrl === 'https://meet.google.com/abc-defg-hij', 'confirmada');
  const f = agenda({ ok: true, autorizada: true, habilitada: true, franjas: [{ id: 'f2', inicio: '2026-11-12T14:00:00-03:00', fin: '2026-11-12T16:00:00-03:00' }],
                     reserva: { ...R1, estado: 'fallo', motivo: 'tomada' } });
  ok(f.reserva.estado === 'fallo' && f.reserva.motivo === 'tomada', 'fallo');
  eq(f.franjas.map(x => x.id), ['f2'], 'con fallo vuelven las franjas');
  eq(agenda({ ok: true, reserva: { ...R1, estado: 'cancelada' } }).reserva, null, 'un estado que no se conoce');
  eq(agenda({ ok: true, reserva: { ...R1, estado: 'realizada' } }).reserva, null, 'realizada no se muestra');
  eq(agenda({ ok: true, reserva: { estado: 'confirmada' } }).reserva, null, 'sin horas');
  eq(agenda({ ok: true, reserva: { ...R1, estado: 'confirmada', meet_url: 'http://meet.google.com/x' } }).reserva.meetUrl, null, 'solo https');
  eq(agenda({ ok: true, reserva: 'si' }).reserva, null, 'reserva rara');
}
{
  const R1 = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' };
  const r = resumen({ ok: true, total: 3, vistos: 1, reserva: { ...R1, estado: 'confirmada', meet_url: 'https://meet.google.com/abc' } });
  ok(r.reserva.estado === 'confirmada' && r.reserva.id === null, 'el resumen suma la reserva');
  eq(resumen({ ok: true, total: 3, vistos: 1 }).reserva, null, 'sin reserva');
  const raro = resumen({ ok: true, total: 3, reserva: { estado: 'x' } });
  ok(raro.reserva === null && raro.total === 3, 'una reserva rara no rompe el resumen');
  const no = resumen({ ok: false, novedad_en: '2026-11-05T12:00:00-03:00', reserva: { inicio: 'a', fin: 'b', estado: 'confirmada' } });
  ok(!no.ok && no.novedadEn === null && no.reserva === null && no.nuevosTotal === null, 'ok false: nada');
}
{
  const a = agenda({ ok: true, autorizada: true, habilitada: true, faltan: 0, franjas: [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' }] });
  // La copia guardada en el navegador es el objeto ya leído: se vuelve a leer igual.
  const crudo = { ok: a.ok, autorizada: a.autorizada, habilitada: a.habilitada, faltan: a.faltan, franjas: a.franjas, reserva: a.reserva };
  eq(agenda(JSON.parse(JSON.stringify(crudo))).franjas, a.franjas, 'ida y vuelta por la copia');
}

// ── Agenda: qué se muestra y la hora (AgendaVistaTests) ──
const FRANJAS = [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' },
                 { id: 'f2', inicio: '2026-11-12T14:00:00-03:00', fin: '2026-11-12T16:00:00-03:00' },
                 { id: 'f3', inicio: '2026-11-13T10:00:00-03:00', fin: '2026-11-13T12:00:00-03:00' }];
const BA = 'America/Argentina/Buenos_Aires';
const AHORA = fecha('2026-11-06T12:00:00-03:00');
{
  const R1 = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' };
  eq(RA.vista(null, 2, false), { tipo: 'nada' }, 'sin agenda');
  eq(RA.vista(agenda({ ok: false }), 0, false), { tipo: 'nada' }, 'ok false');
  eq(RA.vista(agenda({ ok: true, faltan: 3 }), 1, false), { tipo: 'noAutorizada', faltan: 3 }, 'el faltan del servidor manda');
  eq(RA.vista(agenda({ ok: true }), 1, false), { tipo: 'noAutorizada', faltan: 1 }, 'el del teléfono de respaldo');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: false, faltan: 2 }), 0, false), { tipo: 'bloqueada', faltan: 2 }, 'bloqueada');
  const h = agenda({ ok: true, autorizada: true, habilitada: true, faltan: 0, franjas: FRANJAS });
  eq(RA.vista(h, 0, false), { tipo: 'franjas', aviso: null }, 'franjas');
  eq(RA.vista(h, 0, false, 'tomada'), { tipo: 'franjas', aviso: 'tomada' }, 'franjas con aviso');
  eq(RA.vista(h, 0, true), { tipo: 'reservando' }, 'en cola');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, franjas: [] }), 0, false), { tipo: 'sinFranjas', aviso: null }, 'sin franjas');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, reserva: { ...R1, estado: 'pendiente' } }), 0, false), { tipo: 'reservando' }, 'pendiente');
  const c = RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, reserva: { ...R1, estado: 'confirmada', meet_url: 'https://meet.google.com/abc' } }), 0, false);
  ok(c.tipo === 'confirmada' && c.aviso === null && c.reserva.meetUrl, 'confirmada');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, franjas: FRANJAS, reserva: { ...R1, estado: 'fallo', motivo: 'tomada' } }), 0, false),
     { tipo: 'franjas', aviso: 'tomada' }, 'fallo tomada');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, franjas: [], reserva: { ...R1, estado: 'fallo', motivo: 'error' } }), 0, false),
     { tipo: 'sinFranjas', aviso: 'error' }, 'fallo error');
}
{
  eq(RA.textoBloqueada(2), 'Cuando termines los videos de arriba se habilita la agenda. Te faltan 2.', 'bloqueada 2');
  eq(RA.TEXTO_NO_AUTORIZADA, 'Cuando termines de ver todo te habilitamos la agenda.', 'no autorizada');
  eq(RA.TEXTO_AVISO.tomada, 'Ese horario se ocupó recién, elegí otro.', 'tomada');
  eq(RA.TEXTO_SIN_FRANJAS, 'Ahora no hay horarios libres. Te escribimos por WhatsApp para coordinar.', 'sin franjas');
}
{
  const d = RA.dias(agenda({ ok: true, autorizada: true, habilitada: true, franjas: FRANJAS }).franjas, BA, AHORA);
  eq(d.map(x => x.titulo), ['jueves 12 de noviembre', 'viernes 13 de noviembre'], 'por día');
  eq(d[0].chips.map(c => c.texto), ['10:00 a 12:00', '14:00 a 16:00'], 'chips');
  ok(!RA.difiereDeArgentina(d.flatMap(x => x.chips).map(c => c.inicio), BA), 'en Argentina no difiere');
  eq(RA.textoConfirmar(d[0].chips[0], BA), '¿Confirmás la entrega el jueves 12 a las 10:00? Dura unas 2 horas.', 'confirmar');
  eq(RA.textoConfirmada({ inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00', estado: 'confirmada' }, BA),
     'Tu entrega: jueves 12 de noviembre, 10:00 a 12:00', 'confirmada');
}
{
  const fs = agenda({ ok: true, autorizada: true, habilitada: true, franjas: [{ id: 'f1', inicio: '2026-11-12T11:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' },
                                                                                { id: 'f2', inicio: '2026-11-12T12:00:00-03:00', fin: '2026-11-12T12:45:00-03:00' }] }).franjas;
  const d = RA.dias(fs, BA, AHORA);
  eq(d[0].chips.map(c => c.texto), ['11:00 a 12:00', '12:00 a 12:45'], 'la duración sale de cada franja');
  eq(RA.textoConfirmar(d[0].chips[0], BA), '¿Confirmás la entrega el jueves 12 a las 11:00? Dura alrededor de 1 hora.', '1 h');
  eq(RA.textoConfirmar(d[0].chips[1], BA), '¿Confirmás la entrega el jueves 12 a las 12:00? Dura unos 45 minutos.', '45 min');
  eq(RA.textoElegir(d[0].chips), 'Elegí un horario para la videollamada.', 'duran distinto');
  eq(RA.textoElegir([d[0].chips[0]]), 'Elegí un horario para la videollamada. Dura alrededor de 1 hora.', 'una sola');
  const dos = RA.dias(agenda({ ok: true, autorizada: true, habilitada: true, franjas: FRANJAS }).franjas, BA, AHORA);
  eq(RA.textoElegir(dos.flatMap(x => x.chips)), 'Elegí un horario para la videollamada. Dura unas 2 horas.', 'todas 2 h');
}
{
  const i = fecha('2026-11-12T10:00:00-03:00');
  const dura = m => RA.textoDuracion(i, new Date(i.getTime() + m * 60000));
  eq([120, 110, 90, 150, 70, 60, 55, 45, 40, 30, 5].map(dura),
     ['Dura unas 2 horas.', 'Dura unas 2 horas.', 'Dura alrededor de 1 hora y media.', 'Dura unas 2 horas y media.',
      'Dura alrededor de 1 hora.', 'Dura alrededor de 1 hora.', 'Dura alrededor de 1 hora.', 'Dura unos 45 minutos.',
      'Dura unos 45 minutos.', 'Dura unos 30 minutos.', 'Dura unos 15 minutos.'], 'redondeo de la duración');
  ok(dura(0) === null && dura(-30) === null, 'duración rota');
}
{
  const fs = agenda({ ok: true, autorizada: true, habilitada: true, franjas: [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' },
                                                                                { id: 'f2', inicio: '2026-11-12T22:00:00-03:00', fin: '2026-11-13T00:00:00-03:00' }] }).franjas;
  const M = 'Europe/Madrid';
  const dm = RA.dias(fs, M, AHORA);
  eq(dm.map(x => x.titulo), ['jueves 12 de noviembre', 'viernes 13 de noviembre'], 'Madrid: la de las 22 pasa al otro día');
  ok(dm[0].chips[0].texto === '14:00 a 16:00' && dm[1].chips[0].texto === '02:00 a 04:00', 'Madrid: hora convertida');
  ok(RA.difiereDeArgentina(dm.flatMap(x => x.chips).map(c => c.inicio), M), 'Madrid difiere');
  eq(RA.textoConfirmar(dm[0].chips[0], M), '¿Confirmás la entrega el jueves 12 a las 14:00 (10:00 en Argentina)? Dura unas 2 horas.', 'Madrid confirmar');
  const X = 'America/Mexico_City';
  const dx = RA.dias(fs, X, AHORA);
  ok(dx.length === 1 && dx[0].titulo === 'jueves 12 de noviembre', 'México: un día');
  eq(dx[0].chips.map(c => c.texto), ['07:00 a 09:00', '19:00 a 21:00'], 'México: 3 h menos');
  const r = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00', estado: 'confirmada' };
  eq(RA.textoConfirmada(r, X), 'Tu entrega: jueves 12 de noviembre, 07:00 a 09:00', 'México confirmada');
  eq(RA.textoEsperandoSala(r, M), 'Tu entrega es hoy a las 14:00. Cuando Mati abra la videollamada se habilita el botón para entrar.', 'Madrid sala');
}
{
  const fs = [{ id: 'vieja', inicio: '2026-11-05T10:00:00-03:00', fin: '2026-11-05T12:00:00-03:00' },
              { id: 'rota', inicio: 'mañana', fin: 'pasado' },
              { id: 'alreves', inicio: '2026-11-12T12:00:00-03:00', fin: '2026-11-12T10:00:00-03:00' },
              { id: 'ok', inicio: '2026-11-12 13:00:00+00', fin: '2026-11-12 15:00:00+00' }];
  const d = RA.dias(fs, BA, AHORA);
  ok(d.flatMap(x => x.chips).map(c => c.id).join() === 'ok' && d[0].chips[0].texto === '10:00 a 12:00', 'las viejas y rotas no van');
}
{
  const r = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00', estado: 'confirmada', meetUrl: 'https://meet.google.com/abc', salaAbiertaEn: null };
  const t = s => fecha(`2026-11-12T${s}:00-03:00`);
  ok(!RA.enVentana(r, t('09:29')) && RA.enVentana(r, t('09:30')) && !RA.enVentana(r, t('12:00')), 'ventana de 30 min');
  ok(!RA.puedeEntrar(r, t('09:50')) && RA.esperandoSala(r, t('09:50')), 'sin sala: sin botón');
  ok(!RA.esperandoSala(r, t('09:00')), 'antes de la ventana no se consulta');
  ok(RA.puedeEntrar(r, t('10:00')) && !RA.esperandoSala(r, t('10:00')), 'a la hora de inicio, el respaldo');
  eq(RA.textoEntrar(r, BA), 'Tu entrega empezó a las 10:00', 'texto del respaldo');
  ok(!RA.puedeEntrar(r, t('12:00')), 'terminó');
  const abierta = { ...r, salaAbiertaEn: '2026-11-12T09:52:00-03:00' };
  ok(RA.puedeEntrar(abierta, t('09:53')), 'sala abierta');
  eq(RA.textoEntrar(abierta, BA), 'Mati ya está en la videollamada', 'texto de la sala');
  ok(!RA.puedeEntrar(abierta, t('12:01')), 'sala abierta, terminó');
  ok(!RA.puedeEntrar({ ...abierta, meetUrl: null }, t('10:00')), 'sin link');
  const pend = { ...abierta, estado: 'pendiente' };
  ok(!RA.puedeEntrar(pend, t('10:00')) && !RA.enVentana(pend, t('10:00')), 'pendiente');
  ok(RA.esHoy(r, BA, t('07:00')) && !RA.esHoy(r, BA, fecha('2026-11-11T22:00:00-03:00')) && !RA.esHoy(r, BA, t('12:30')), 'es hoy');
  eq(RA.textoEsperandoSala(r, BA), 'Tu entrega es hoy a las 10:00. Cuando Mati abra la videollamada se habilita el botón para entrar.', 'esperando sala');
  const R1 = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T12:00:00-03:00', estado: 'confirmada', meet_url: 'https://meet.google.com/abc' };
  eq(agenda({ ok: true, autorizada: true, habilitada: true, reserva: { ...R1, sala_abierta_en: '2026-11-12T09:52:00-03:00' } }).reserva.salaAbiertaEn,
     '2026-11-12T09:52:00-03:00', 'sala_abierta_en');
  eq(agenda({ ok: true, reserva: { ...R1, sala_abierta_en: ' ' } }).reserva.salaAbiertaEn, null, 'sala_abierta_en en blanco');
}

// ── Lo que edita Mati, spec §7 (AgendaEditableTests) ──
{
  const a = agenda({ ok: true, autorizada: true, habilitada: true, franjas: [{ id: 'f1', inicio: '2026-11-12T11:00:00-03:00', fin: '2026-11-12T12:00:00-03:00' }],
    textos: { confirmar: '¿Te anoto el {dia} a las {hora}? Son {duracion}.', titulo: 'Tu llamada', cambiar: '  ', sala_abierta: 7, inventada: 'x', bloqueada: 'Faltan {faltan} videos' } });
  ok(a.textos.titulo === 'Tu llamada' && a.textos.cambiar === undefined && a.textos.sala_abierta === undefined, 'solo los textos no vacíos');
  const t = RA.textos(a.textos);
  const c = RA.dias(a.franjas, BA, AHORA)[0].chips[0];
  eq(t.confirmar(c, BA), '¿Te anoto el jueves 12 a las 11:00? Son alrededor de 1 hora.', 'texto pisado con sus valores');
  eq(t.titulo, 'Tu llamada', 'título');
  eq(t.cambiar, RA.TEXTO_CAMBIAR, 'en blanco: el de la app');
  eq(t.bloqueada(2), 'Faltan 2 videos', 'faltan');
  eq(t.bloqueada(0), RA.textoBloqueada(0), 'con 0 no hay clave');
  eq(RA.textos().confirmar(c, BA), RA.textoConfirmar(c, BA), 'sin textos, los de la app');
}
{
  const t = RA.textos({ encabezado: 'Elegí un horario. Dura {duracion}.', sin_franjas: 'Sin lugar: {hora}' });
  const chips = RA.dias([{ id: 'a', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T11:00:00-03:00' },
                         { id: 'b', inicio: '2026-11-12T14:00:00-03:00', fin: '2026-11-12T14:45:00-03:00' }], BA, AHORA).flatMap(x => x.chips);
  eq(t.encabezado(chips), RA.textoElegir(chips), 'duran distinto: el de la app');
  eq(t.encabezado([chips[0]]), 'Elegí un horario. Dura alrededor de 1 hora.', 'una duración');
  eq(t.sinFranjas, RA.TEXTO_SIN_FRANJAS, 'un valor que no hay no deja llaves');
}
{
  const t = RA.textos({ hoy_sin_sala: 'Hoy a las {hora}, esperá a Mati', sala_abierta: 'Mati te espera', fallo: 'Elegí otro', entreno_aviso: 'Entrega {hora}' });
  const r = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T11:00:00-03:00', estado: 'confirmada', meetUrl: 'https://meet.google.com/x', salaAbiertaEn: '2026-11-12T09:58:00-03:00' };
  eq(t.hoySinSala(r, BA), 'Hoy a las 10:00, esperá a Mati', 'hoy sin sala');
  eq(t.entrenoAviso(r, BA), 'Entrega 10:00', 'entreno aviso');
  eq(t.entrar(r, BA), 'Mati te espera', 'sala abierta');
  const sinSala = { ...r, salaAbiertaEn: null };
  eq(t.entrar(sinSala, BA), RA.textoEntrar(sinSala, BA), 'el respaldo no se pisa');
  ok(t.fallo('tomada') === 'Elegí otro' && t.fallo('error') === 'Elegí otro' && t.fallo('demo') === RA.TEXTO_AVISO.demo, 'fallo');
  eq(RA.textos({ hoy_sin_sala: 'Hoy {hora}' }).entrenoAviso(r, BA), 'Hoy 10:00', 'sin entreno_aviso, el de la guía');
}
{
  eq(agenda({ ok: true, autorizada: true, habilitada: true, aviso_min: 15 }).avisoMin, 15, 'aviso_min');
  ok(agenda({ ok: true, aviso_min: -3 }).avisoMin === null && agenda({ ok: true, aviso_min: 'x' }).avisoMin === null, 'aviso_min roto');
  const r = { inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T11:00:00-03:00', estado: 'confirmada' };
  const a20 = fecha('2026-11-12T09:40:00-03:00'), a10 = fecha('2026-11-12T09:50:00-03:00');
  ok(!RA.enVentana(r, a20, 15) && RA.enVentana(r, a10, 15) && RA.enVentana(r, a20), 'aviso de 15 min');
}
{
  const F = [{ id: 'f1', inicio: '2026-11-12T10:00:00-03:00', fin: '2026-11-12T11:00:00-03:00' }];
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, faltan: 0, franjas: F }), 3, false), { tipo: 'franjas', aviso: null }, 'la app no bloquea por su cuenta');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: true, faltan: 2, franjas: F }), 2, false), { tipo: 'franjas', aviso: null }, 'si habilitó, habilitó');
  eq(RA.vista(agenda({ ok: true, autorizada: true, habilitada: false, faltan: 1 }), 4, false), { tipo: 'bloqueada', faltan: 1 }, 'manda su faltan');
}

// ── Los textos que cambiaron en la 2.2.0 (GuiaTests) ──
{
  const b = R.bloques(R.deLaLista(guia({ ok: true, clips: [
    { id: 'a', titulo: 'A', minutos: 1.0, bloque: 'X' }, { id: 'b', titulo: 'B', minutos: 0.7, bloque: 'X' }, { id: 'c', titulo: 'C', minutos: 0.4, bloque: 'Y' }] })));
  eq(R.textoBloque(b[0]), '2 videos, unos 2 minutos', 'bloque');
  eq(R.textoBloque(b[1]), '1 video, 1 minuto', 'nunca «unos 1 minuto»');
  const c = [{ minutos: 1.2, visto: true }, { minutos: 0.3, visto: false }, { minutos: 0.4, visto: false }];
  const a = R.avance(c);
  eq(R.textoAvance(a), 'Viste 1 de 3, te queda 1 minuto', 'avance');
  eq(R.textoTarjeta(a), '1 de 3 videos, te queda 1 min', 'tarjeta');
  eq(R.textoTarjeta({ total: 13, vistos: 0, minutosRestantes: 12.4 }), '13 videos cortos, unos 12 min', 'tarjeta 13');
  eq(R.textoTarjeta({ total: 1, vistos: 0, minutosRestantes: 0.3 }), '1 video corto, 1 min', 'tarjeta 1');
  eq(R.textoTarjeta({ total: 13, vistos: 4, minutosRestantes: 12 }), '4 de 13 videos, te quedan 12 min', 'tarjeta 4 de 13');
  eq(R.textoBienvenida({ total: 11, vistos: 0, minutosRestantes: 9.4 }),
     'Antes de empezar, mirá tu guía. Son 11 videos cortos que armé para vos, unos 9 min. Así en la videollamada vamos directo a lo tuyo.', 'bienvenida');
  ok(R.textoBienvenida({ total: 1, vistos: 0, minutosRestantes: 0.2 }).includes('Es un video corto que armé para vos, de 1 min.'), 'bienvenida 1');
}

// ── El cuadro y las franjas negras (FormatoVideoTests) ──
{
  eq(RV.proporcion(1280, 720), 1280 / 720, '16:9');
  eq(RV.proporcion(720, 720), 1, 'cuadrado');
  ok(RV.proporcion(0, 720) === null && RV.proporcion(1280, 0) === null && RV.proporcion(NaN, 720) === null && RV.proporcion(1, 2000) === null, 'rotos');
  eq(RV.cuadro(1280 / 720, 370, 874), { ancho: 370, alto: 208 }, 'horizontal a lo ancho');
  eq(RV.cuadro(1, 370, 874), { ancho: 370, alto: 370 }, 'cuadrado a lo ancho');
  const v = 570 / 720;
  eq(RV.cuadro(v, 370, 874), { ancho: 370, alto: 467 }, 'vertical que entra');
  eq(RV.cuadro(v, 343, 667), { ancho: 317, alto: 400 }, 'vertical topeado al 60 %');
  const c = RV.cuadro(9 / 16, 370, 874);
  ok(c.alto === 524 && c.ancho === 295 && Math.abs(c.ancho / c.alto - 9 / 16) < 0.01, '9:16');
  eq(RV.cuadro(null, 352, 874), { ancho: 352, alto: 198 }, 'sin dato, 16:9');
  eq(RV.cuadro(50, 352, 874), { ancho: 352, alto: 198 }, 'dato roto, 16:9');
  eq(RV.cuadro(1, 0, 874), { ancho: 0, alto: 0 }, 'sin ancho');
}
function cuadroLuma(ancho, alto, x0, x1, y0 = 0, y1 = alto) {
  const l = new Uint8Array(ancho * alto).fill(12);
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) l[y * ancho + x] = 140;
  return l;
}
{
  const r = RV.recuadro(cuadroLuma(320, 180, 105, 214), 320, 180);
  ok(Math.abs(r.x - 106 / 320) < 1e-4 && Math.abs(r.ancho - 107 / 320) < 1e-4 && r.y === 0 && r.alto === 1, 'el FT-2b de la demo');
  const c = RV.recorte(r);
  const p = RV.conRecorte(16 / 9, c);
  ok(p > 0.57 && p < 0.63, 'queda vertical');
  eq(RV.cuadro(p, 370, 874).alto, 524, 'topeado por el alto');
}
{
  const l = cuadroLuma(320, 180, 100, 220);
  for (let y = 0; y < 180; y++) for (const x of [100, 101, 102, 103, 217, 218, 219]) l[y * 320 + x] = 30;
  for (let y = 0; y < 180; y++) for (let x = 104; x < 217; x++) if ((x + y) % 3 === 0) l[y * 320 + x] = 200;
  const r = RV.recuadro(l, 320, 180);
  cerca(r.x, 105 / 320, 'el marco oscuro del teléfono, izquierda');
  cerca(r.x + r.ancho, 216 / 320, 'el marco oscuro del teléfono, derecha');
}
{
  const r = RV.recuadro(cuadroLuma(320, 180, 0, 320), 320, 180);
  eq(r, RV.ENTERO, 'sin franjas: entero');
  eq(RV.recorte(r), null, 'sin franjas no se recorta');
  eq(RV.recorte({ x: 0.03, y: 0, ancho: 0.94, alto: 1 }), null, 'un borde chico del propio video tampoco');
  eq(RV.conRecorte(16 / 9, null), 16 / 9, 'sin recorte, la del archivo');
}
{
  const l = cuadroLuma(320, 180, 105, 214);
  l[5 * 320 + 3] = 255;
  eq(RV.recuadro(l, 320, 180).x, 106 / 320, 'el ruido suelto no cuenta');
  eq(RV.recuadro(new Uint8Array(320 * 180).fill(12), 320, 180), null, 'todo negro no da nada');
  eq(RV.recuadro(new Uint8Array(0), 320, 180), null, 'vacío');
}
{
  const u = RV.unir([{ x: 0.3, y: 0, ancho: 0.3, alto: 1 }, { x: 0.35, y: 0.1, ancho: 0.4, alto: 0.8 }]);
  ok(Math.abs(u.x - 0.3) < 1e-9 && Math.abs(u.ancho - 0.45) < 1e-9 && u.y === 0 && u.alto === 1, 'la unión');
  const c = RV.recorte(u);
  ok(Math.abs(c.x - 0.3) < 1e-9 && Math.abs(c.ancho - 0.4) < 1e-9, 'el recorte centrado');
  const lb = RV.recorte({ x: 0, y: 0.2, ancho: 1, alto: 0.6 });
  cerca(RV.conRecorte(1, lb), 1 / 0.6, 'letterbox', 1e-9);
  eq(RV.unir([]), null, 'unir nada');
  // La luma de un canvas RGBA, como Android.
  eq(Array.from(RV.luma(new Uint8ClampedArray([255, 255, 255, 255, 0, 0, 0, 255, 12, 12, 12, 255]), 3)), [255, 0, 12], 'luma');
}

console.log(`test-guia-agenda: ${n} comprobaciones OK`);
