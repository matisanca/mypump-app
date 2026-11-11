#!/usr/bin/env node
/* =============================================================
   presion-dibujos.mjs — las ilustraciones de la pantalla de presión arterial, desde UNA sola fuente

   Especificación: ~/Developer/nativa-evidencia/presion/GRAFICOS.md (dibujo propio, línea simple con puntas
   redondeadas, sin sombras ni degradados, figura neutra sin cara, tensiómetro genérico, sin texto ni fuentes
   dentro del SVG, manguito en color de acento, tilde y cruz como íconos).

   Cada dibujo es una lista de primitivas (path, line, circle, polyline), cada una en la capa `base` o
   `acento`, con `z` (lo de más arriba tapa a lo de abajo; las formas cerradas con el mismo `z` se funden en
   una sola silueta) y la opción `punteado`. El generador resuelve qué queda tapado y emite:

   · Web      <repo web>/public/js/presion-dibujos.js   (nombre → SVG inline; base currentColor, acento --color-brand)
   · iOS      apps/ios/MyPump/Recursos/Assets.xcassets/Presion/<nombre>_{base,acento}.imageset  (SVG negro, plantilla)
   · Android  apps/android/app/src/main/res/drawable/<nombre>_{base,acento}.xml                 (VectorDrawable negro)

   El punteado sale como segmentos cortos en las tres salidas (VectorDrawable no tiene punteado), así el dibujo
   es idéntico en todas. Los números (referencias y relojitos) son trazos, no texto.

   Uso:
     node scripts/nativa/presion-dibujos.mjs                    escribe las tres salidas
     node scripts/nativa/presion-dibujos.mjs --control [dir]    además deja SVG de control en claro y en oscuro
                                                                (por defecto ~/Developer/nativa-evidencia/presion/dibujos)
     PRESION_WEB=<repo web> cambia el repo de la web (por defecto ../mn-web-presion, al lado de este repo).

   Sin dependencias. No commitea nada.
   ============================================================= */

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const WEB = process.env.PRESION_WEB || path.join(RAIZ, '..', 'mn-web-presion');
const SALIDA_WEB = path.join(WEB, 'public', 'js', 'presion-dibujos.js');
const SALIDA_IOS = path.join(RAIZ, 'apps', 'ios', 'MyPump', 'Recursos', 'Assets.xcassets', 'Presion');
const SALIDA_ANDROID = path.join(RAIZ, 'apps', 'android', 'app', 'src', 'main', 'res', 'drawable');
const CONTROL_DEFECTO = path.join(os.homedir(), 'Developer', 'nativa-evidencia', 'presion', 'dibujos');

const TRAZO = 2.5;      // ancho de línea general (la especificación pide de 2 a 3)
const FINO = 1.8;       // dígitos y detalles chicos

// ─── Geometría ──────────────────────────────────────────────────
const rad = g => (g * Math.PI) / 180;
const mezcla = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

/** Puntos de un arco; ángulos en grados de pantalla (0 a la derecha, 90 hacia abajo). */
function arco(cx, cy, r, a0, a1, paso = 6) {
  const n = Math.max(2, Math.ceil(Math.abs(a1 - a0) / paso));
  const pts = [];
  for (let i = 0; i <= n; i++) {
    const a = rad(a0 + ((a1 - a0) * i) / n);
    pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return pts;
}

/** Contorno de una cápsula que se afina: círculo de radio ra en a, rb en b, unidos por las tangentes. */
function capsulaPts(a, ra, b, rb) {
  const d = dist(a, b) || 0.001;
  const ang = (Math.atan2(b[1] - a[1], b[0] - a[0]) * 180) / Math.PI;
  const beta = (Math.acos(Math.max(-1, Math.min(1, (ra - rb) / d))) * 180) / Math.PI;
  return [...arco(a[0], a[1], ra, ang + beta, ang + 360 - beta, 5), ...arco(b[0], b[1], rb, ang - beta, ang + beta, 5)];
}

/** Rectángulo de esquinas redondeadas, centrado y girado `giro` grados. */
function rectPts(cx, cy, mw, mh, r = 0, giro = 0) {
  r = Math.min(r, mw, mh);
  let pts;
  if (r <= 0) pts = [[-mw, -mh], [mw, -mh], [mw, mh], [-mw, mh]];
  else pts = [
    ...arco(mw - r, -mh + r, r, -90, 0, 15), ...arco(mw - r, mh - r, r, 0, 90, 15),
    ...arco(-mw + r, mh - r, r, 90, 180, 15), ...arco(-mw + r, -mh + r, r, 180, 270, 15),
  ];
  const c = Math.cos(rad(giro)), s = Math.sin(rad(giro));
  return pts.map(([x, y]) => [cx + x * c - y * s, cy + x * s + y * c]);
}

/** Transformación de una figura: escala, giro (grados) y traslado. `T(p)` da el punto final. */
function Tr({ s = 1, giro = 0, dx = 0, dy = 0 } = {}) {
  const c = Math.cos(rad(giro)), sn = Math.sin(rad(giro));
  const f = p => [(p[0] * c - p[1] * sn) * s + dx, (p[0] * sn + p[1] * c) * s + dy];
  f.s = s;
  return f;
}
const ID = Tr();

// ─── Primitivas (los datos de cada dibujo) ──────────────────────
// Opciones comunes: capa ('base' | 'acento'), z, ancho, punteado ([trazo, hueco] o true), relleno,
// tapa (false = aunque sea cerrada no tapa ni se funde: detalles dentro de otra forma), recorte [x0,y0,x1,y1].
const opc = o => ({ capa: 'base', z: 0, ancho: TRAZO, ...o });
const linea = (x1, y1, x2, y2, o) => ({ t: 'line', x1, y1, x2, y2, ...opc(o) });
const circulo = (c, r, o) => ({ t: 'circle', cx: c[0], cy: c[1], r, ...opc(o) });
const poli = (pts, o) => ({ t: 'polyline', pts, cerrada: false, ...opc(o) });
const cerrada = (pts, o) => ({ t: 'polyline', pts, ...opc(o), cerrada: true });
/** path con comandos absolutos M L C Q Z, separados por espacios. `T` lo transforma. */
function trazo(d, o, T = ID) {
  const tk = d.trim().split(/[\s,]+/);
  const cmds = [];
  const cuantos = { M: 1, L: 1, C: 3, Q: 2, Z: 0 };
  for (let i = 0; i < tk.length;) {
    const c = tk[i++];
    if (!(c in cuantos)) throw new Error(`path: comando no soportado «${c}» en «${d}»`);
    const p = [];
    for (let k = 0; k < cuantos[c]; k++) { p.push(T([Number(tk[i]), Number(tk[i + 1])])); i += 2; }
    cmds.push({ c, p });
  }
  return { t: 'path', cmds, ...opc(o) };
}

// ─── Piezas que se repiten ──────────────────────────────────────
const capsula = (T, a, ra, b, rb, o) => cerrada(capsulaPts(T(a), ra * T.s, T(b), rb * T.s), o);
const rect = (x0, y0, x1, y1, r, o) => cerrada(rectPts((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, r), o);

// Dígitos como polilíneas propias, en una grilla de 4 × 6.
const DIGITOS = {
  1: [[[0.9, 1.4], [2.3, 0], [2.3, 6]]],
  2: [[...arco(2, 1.85, 1.85, 190, 395, 20), [0.2, 6], [3.9, 6]]],
  3: [[...arco(1.9, 1.55, 1.55, 205, 450, 20), ...arco(1.9, 4.35, 1.65, 270, 515, 20)]],
  4: [[[2.9, 6], [2.9, 0], [0.1, 4.2], [3.9, 4.2]]],
  5: [[[3.5, 0], [0.8, 0], [0.5, 2.7], ...arco(1.85, 4.1, 1.9, 228, 505, 20)]],
};
function digito(n, cx, cy, alto, o) {
  if (!DIGITOS[n]) throw new Error(`no hay trazos para el dígito ${n}`);
  const e = alto / 6;
  return DIGITOS[n].map(pl => poli(pl.map(([x, y]) => [cx + (x - 2) * e, cy + (y - 3) * e]), { ancho: FINO, z: 9, ...o }));
}
/** Número de referencia en un círculo. */
const referencia = (n, cx, cy) => [circulo([cx, cy], 9.5, { ancho: FINO, z: 9 }), ...digito(n, cx, cy, 9.5)];
/** Relojito (cronómetro) con un número adentro. */
function reloj(n, cx, cy, r = 13) {
  return [
    circulo([cx, cy], r, { z: 9 }),
    linea(cx, cy - r, cx, cy - r - 4, { z: 9 }),
    linea(cx - 3.5, cy - r - 4.5, cx + 3.5, cy - r - 4.5, { z: 9 }),
    linea(cx + r * 0.78, cy - r * 0.78, cx + r * 0.78 + 2.6, cy - r * 0.78 - 2.6, { z: 9 }),
    ...digito(n, cx, cy + 0.3, r * 0.92, { ancho: 2 }),
  ];
}
/** Tilde o cruz dentro de un círculo. */
function marca(tipo, cx, cy, r, ancho = TRAZO) {
  const o = { z: 9, ancho };
  const k = r / 10;
  const dentro = tipo === 'tilde'
    ? [poli([[cx - 4.6 * k, cy + 0.4 * k], [cx - 1.4 * k, cy + 3.6 * k], [cx + 4.8 * k, cy - 3.4 * k]], o)]
    : [linea(cx - 3.6 * k, cy - 3.6 * k, cx + 3.6 * k, cy + 3.6 * k, o), linea(cx + 3.6 * k, cy - 3.6 * k, cx - 3.6 * k, cy + 3.6 * k, o)];
  return [circulo([cx, cy], r, o), ...dentro];
}
/** Flecha recta con punta. */
function flecha(x1, y1, x2, y2, o = {}, punta = 5) {
  const a = Math.atan2(y2 - y1, x2 - x1);
  const p = g => [x2 - punta * Math.cos(a + rad(g)), y2 - punta * Math.sin(a + rad(g))];
  return [linea(x1, y1, x2, y2, o), poli([p(35), [x2, y2], p(-35)], o)];
}
/** Corazón chico de línea, con la punta abajo. */
const corazon = (cx, cy, o, e = 1) => trazo('M 0 -1.6 C -1.2 -5 -5.4 -4.2 -5 -0.6 C -4.7 2 -1.8 3.6 0 5.6 C 1.8 3.6 4.7 2 5 -0.6 C 5.4 -4.2 1.2 -5 0 -1.6',
  { ancho: FINO, ...o }, Tr({ s: e, dx: cx, dy: cy }));

/** Manguito sobre el brazo (hombro → codo), en la capa de acento. `t` es dónde cae su centro. */
function manguito(T, hombro, codo, t, rBrazo, o = {}) {
  const c = mezcla(hombro, codo, t);
  const giro = (Math.atan2(codo[1] - hombro[1], codo[0] - hombro[0]) * 180) / Math.PI;
  const ml = o.medioLargo ?? 11.5, ma = rBrazo + 3.2;
  const z = o.z ?? 3;
  const local = pts => pts.map(T);
  const g = Tr({ giro, dx: c[0], dy: c[1] });
  return [
    cerrada(local(rectPts(c[0], c[1], ml, ma, 3.5, giro)), { capa: 'acento', z, ancho: o.ancho ?? 3, recorte: o.recorte }),
    poli(local([g([ml - 5.5, -ma + 2.5]), g([ml - 5.5, ma - 2.5])]), { capa: 'acento', z, ancho: FINO, recorte: o.recorte }),
  ];
}

/**
 * Figura de costado, mirando a la derecha, hecha de cápsulas que se funden en una silueta.
 * La pose va en las coordenadas de G1 (1,6 px por cm); `T` la lleva a su lugar y tamaño.
 */
function figura(T, p, o = {}) {
  const z = o.z ?? 1;
  const cuerpo = { z, recorte: o.recorteCuerpo };
  const brazo = { z: z + 1, recorte: o.recorteBrazo };
  const out = [];
  if (p.lejos) {
    out.push(capsula(T, p.lejos.rodilla, 11.5, p.lejos.tobillo, 7.5, { z: z - 0.5 }));
    out.push(capsula(T, p.lejos.pie[0], 7.5, p.lejos.pie[1], 6, { z: z - 0.5 }));
  }
  out.push(circulo(T(p.cabeza), 13 * T.s, cuerpo));
  out.push(capsula(T, p.cuello[0], 6.5, p.cuello[1], 7, cuerpo));
  out.push(capsula(T, p.pecho, 20, p.pelvis, 18, cuerpo));
  if (p.cadera) {
    out.push(capsula(T, p.cadera, 15, p.rodilla, 11.5, cuerpo));
    out.push(capsula(T, p.rodilla, 11.5, p.tobillo, 7.5, cuerpo));
    out.push(capsula(T, p.pie[0], 7.5, p.pie[1], 6, cuerpo));
  }
  out.push(capsula(T, p.hombro, 10, p.codo, 8.5, brazo));
  out.push(capsula(T, p.codo, 8.5, p.muneca, 6, brazo));
  out.push(capsula(T, p.muneca, 6, p.mano, 5, brazo));
  if (p.manguito !== false) out.push(...manguito(T, p.hombro, p.codo, p.manguito ?? 0.5, 9.3, { z: z + 2, recorte: o.recorteBrazo }));
  return out;
}

// Poses (coordenadas de G1).
const TRONCO = { cabeza: [95.5, 38], cuello: [[95, 50], [93.5, 63]], pecho: [92, 84], pelvis: [90, 138], hombro: [95, 73] };
const SENTADO = {
  ...TRONCO, codo: [134, 98], muneca: [184, 100], mano: [203, 100.5],
  cadera: [92, 142], rodilla: [166, 144], tobillo: [168, 206], pie: [[168, 214.5], [192, 216.5]],
  lejos: { rodilla: [179, 144], tobillo: [183, 206], pie: [[183, 214.5], [207, 216.5]] },
};
const PARADO = {
  cabeza: [106, -32], cuello: [[105.5, -20], [104, -8]], pecho: [102, 12], pelvis: [100, 66], hombro: [104, 1],
  codo: [142, 28], muneca: [190, 30], mano: [208, 30.5],
  cadera: [100, 70], rodilla: [101, 142], tobillo: [100, 206], pie: [[100, 214.5], [124, 216.5]],
};
const ACOSTADO = { ...PARADO, codo: [107, 50], muneca: [111, 96], mano: [112, 114] };
const CORAZON_Y = 85.5; // altura del corazón en la pose sentada: el centro del manguito con el brazo apoyado

/** La escena de G1 (silla, mesa, persona, tensiómetro, línea del corazón). La reusa la variante sentada de G6. */
function escenaSentado(T, { numeros = false, relojEn = null, corta = false } = {}) {
  const s = T.s;
  const R = (x0, y0, x1, y1, r, o) => cerrada(rectPts((x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, r).map(T), o);
  const L = (x1, y1, x2, y2, o) => { const a = T([x1, y1]), b = T([x2, y2]); return linea(a[0], a[1], b[0], b[1], o); };
  const out = [
    // piso
    L(34, 225, corta ? 316 : 330, 225),
    // silla: respaldo recto, asiento y patas
    R(62.5, 60, 70.5, 164, 3.5, { z: 0 }), R(62.5, 158.5, 152, 165.5, 3, { z: 0 }),
    L(67, 166, 65, 225), L(146, 166, 148, 225),
    // mesa y tensiómetro
    R(124, 108, 314, 114.5, 3, { z: 0 }), L(302, 115, 302, 225),
    R(234, 86, 280, 107.2, 5, { z: 0.2 }), R(240, 91, 261, 102.5, 2, { z: 0.2, tapa: false, ancho: FINO }),
    circulo(T([270.5, 96.8]), 3 * s, { z: 0.2, tapa: false, ancho: FINO }),
    ...figura(T, SENTADO),
    // tubo del manguito al aparato
    trazo('M 127 95 C 146 88 176 84 204 88 C 220 90 224 98 234 98', { capa: 'acento', z: 8, ancho: 2 }, T),
    // corazón y línea punteada hasta el centro del manguito
    corazon(...T([82.5, CORAZON_Y - 0.5]), { z: 1 }, s * 1.25),
    L(numeros ? 42 : 52, CORAZON_Y, 146, CORAZON_Y, { z: 8, punteado: [3.5, 5.5] }),
  ];
  if (numeros) out.push(
    ...referencia(1, 44, 128), ...referencia(2, 232, 204), ...referencia(3, 168, 68), ...referencia(4, 28, CORAZON_Y),
  );
  if (relojEn) out.push(...reloj(5, relojEn[0], relojEn[1], relojEn[2] ?? 14));
  return out;
}

// ─── Los dibujos ────────────────────────────────────────────────
const DIBUJOS = {};
const dibujo = (nombre, ancho, alto, prims) => { DIBUJOS[nombre] = { ancho, alto, prims: prims.flat(Infinity).filter(Boolean) }; };

// G1 · Postura
dibujo('presion_g1_postura', 360, 240, escenaSentado(ID, { numeros: true, relojEn: [322, 44, 15] }));

// G2 · Altura del brazo (cruz, tilde, cruz)
{
  const prims = [];
  const variantes = [
    { tipo: 'cruz', pose: { codo: [97, 124], muneca: [101, 168], mano: [102, 184], manguito: 0.66 }, flecha: 1 },
    { tipo: 'tilde', pose: { codo: [134, 98], muneca: [171, 100], mano: [187, 100.5], manguito: 0.5 }, mesa: true },
    { tipo: 'cruz', pose: { codo: [135, 50], muneca: [168, 26], mano: [182, 16], manguito: 0.5 }, flecha: -1 },
  ];
  variantes.forEach((v, i) => {
    const x0 = 120 * i;
    const T = Tr({ s: 0.9, dx: x0 - 55.8, dy: -4 });
    const pose = { ...TRONCO, ...v.pose };
    // del torso para arriba: el muslo se corta enseguida y el asiento apenas se insinúa
    prims.push(figura(T, pose));
    prims.push(capsula(T, [92, 142], 15, [150, 143.5], 13, { z: 1, recorte: [0, 0, x0 + 67, 240] }));
    const a = T([66, 158.6]), b = T([122, 165]);
    prims.push(rect(a[0], a[1], b[0], b[1], 2.5, { z: 0 }));
    if (v.mesa) {
      const m0 = T([122, 107.6]), m1 = T([194, 114]);
      prims.push(rect(m0[0], m0[1], m1[0], m1[1], 2.5, { z: 0 }), linea(m1[0] - 6, m1[1], m1[0] - 6, b[1], { z: 0 }));
    }
    const yC = T([0, CORAZON_Y])[1];
    prims.push(corazon(...T([82, CORAZON_Y - 0.5]), { z: 1 }, 1.1));
    prims.push(linea(x0 + 6, yC, x0 + 114, yC, { z: 8, punteado: [3.5, 5.5] }));
    if (v.flecha) {
      // flecha de la línea del corazón al centro del manguito: queda por debajo o por encima
      const c = T(mezcla(pose.hombro, pose.codo, pose.manguito));
      const x = c[0] + (v.flecha > 0 ? 26 : 31);
      prims.push(flecha(x, yC + 3.5 * v.flecha, x, c[1], { z: 8, ancho: 2 }, 4.5));
    }
    prims.push(marca(v.tipo, x0 + 60, 213, 12));
  });
  dibujo('presion_g2_altura_brazo', 360, 240, prims);
}

// G3 · Medir el brazo (solo la parte de arriba: brazo, centímetro y las dos marcas)
{
  const T = Tr({ dx: 14, dy: 0 });
  const hombro = [186, 60], codo = [206, 144], muneca = [221, 206];
  const yMedio = 92.5;
  const cB = mezcla(hombro, codo, (yMedio - hombro[1]) / (codo[1] - hombro[1]));
  const xI = cB[0] - 18.6, xD = cB[0] + 18.6, xM = cB[0];
  const prims = [
    // cuello, hombros, costado del torso y pectoral (de frente)
    trazo('M 100 -6 L 100 14 C 100 25 88 29 68 35 C 54 39 46 46 44 60', { z: 0 }, T),
    trazo('M 128 -6 L 128 14 C 128 25 144 30 172 40', { z: 0 }, T),
    trazo('M 174 66 C 164 78 167 110 164 134 C 161 164 158 188 158 206 C 158 222 160 236 163 248', { z: 0 }, T),
    trazo('M 114 96 C 130 110 154 106 166.5 82', { z: 0, ancho: FINO }, T),
    trazo('M 114 96 C 98 110 76 108 62 96', { z: 0, ancho: FINO }, T),
    // brazo relajado al costado
    capsula(T, hombro, 20, codo, 14, { z: 2 }), capsula(T, codo, 14, muneca, 9.5, { z: 2 }),
    capsula(T, [222, 210], 9.5, [226, 240], 8.5, { z: 2 }),
    // centímetro alrededor del brazo, en la mitad
    trazo(`M ${xI} ${yMedio - 5.5} Q ${xM} ${yMedio + 1.5} ${xD} ${yMedio - 5.5} L ${xD} ${yMedio + 5.5} Q ${xM} ${yMedio + 12.5} ${xI} ${yMedio + 5.5} Z`, { capa: 'acento', z: 4, ancho: 2.4 }, T),
    ...[-12, -6, 0, 6, 12].map((dx, i) => { const y = yMedio + 3.5 - (dx * dx) / 48; return trazo(`M ${xM + dx} ${y + (i % 2 ? -2.2 : -3.6)} L ${xM + dx} ${y + 1}`, { capa: 'acento', z: 4, ancho: 1.5 }, T); }),
    // la punta del centímetro, que cuelga
    trazo(`M ${xD} ${yMedio - 5.5} C ${xD + 9} ${yMedio - 8} ${xD + 13} ${yMedio - 2} ${xD + 13} ${yMedio + 8} L ${xD + 13} ${yMedio + 34} L ${xD + 3.5} ${yMedio + 34} L ${xD + 3.5} ${yMedio + 12} C ${xD + 3.5} ${yMedio + 8} ${xD + 2.5} ${yMedio + 6} ${xD} ${yMedio + 5.5}`, { capa: 'acento', z: 4, ancho: 2.4 }, T),
    ...[18, 26].map(dy => trazo(`M ${xD + 9.5} ${yMedio + dy} L ${xD + 13} ${yMedio + dy}`, { capa: 'acento', z: 4, ancho: 1.5 }, T)),
    // marcas en la punta del hombro y en el codo, y la regla con la mitad
    circulo(T([191, 40]), 3.4, { z: 6, relleno: true }), circulo(T([219.5, 145]), 3.4, { z: 6, relleno: true }),
    trazo('M 199 40 L 262 40', { z: 6, ancho: FINO, punteado: [2.5, 5] }, T),
    trazo('M 227 145 L 262 145', { z: 6, ancho: FINO, punteado: [2.5, 5] }, T),
    trazo(`M ${xD + 20} ${yMedio} L 262 ${yMedio}`, { z: 6, ancho: FINO, punteado: [2.5, 5] }, T),
    trazo('M 270 40 L 270 145', { z: 6 }, T),
    trazo('M 263 40 L 277 40', { z: 6 }, T), trazo('M 263 145 L 277 145', { z: 6 }, T),
    trazo(`M 263 ${yMedio} L 282 ${yMedio}`, { z: 6 }, T),
    // dos rayitas iguales en cada mitad: son la misma distancia
    ...[64, 68.5, 117, 121.5].map(y => trazo(`M 266.5 ${y + 1.5} L 273.5 ${y - 1.5}`, { z: 6, ancho: FINO }, T)),
  ];
  dibujo('presion_g3_medir_brazo', 360, 240, prims);
}

// G4 · Colocar el manguito (brazo del lado de adentro, palma para arriba)
{
  const hombro = [-56, 117], codo = [184, 129], muneca = [290, 104];
  const rA = 31, rC = 22.5;
  const tM = (130 + 56) / 240;                    // centro del manguito sobre el eje del brazo
  const giro = (Math.atan2(codo[1] - hombro[1], codo[0] - hombro[0]) * 180) / Math.PI;
  const cM = mezcla(hombro, codo, tM);
  const g = Tr({ giro, dx: cM[0], dy: cM[1] });   // ejes del manguito: x a lo largo del brazo hacia el codo
  const ml = 35, ma = 30.5;
  const prims = [
    // brazo, antebrazo y mano con la palma para arriba
    capsula(ID, hombro, rA, codo, rC, { z: 1 }), capsula(ID, codo, rC, muneca, 13.5, { z: 1 }),
    capsula(ID, [294, 103], 13.5, [338, 94], 10.5, { z: 1 }), capsula(ID, [301, 93], 6.5, [322, 73], 5.5, { z: 1 }),
    // pliegue del codo
    trazo('M 185 111 C 190 121 190 137 184 148', { z: 1.2, ancho: FINO }),
    // por dónde pasa la arteria, del lado de adentro
    trazo('M 8 121 L 92 125', { z: 1.2, ancho: FINO, punteado: [2.5, 5.5] }),
    trazo('M 172 129.5 L 185 130 L 240 117', { z: 1.2, ancho: FINO, punteado: [2.5, 5.5] }),
    // la mano del otro lado: el índice entra justo debajo del borde de arriba
    capsula(ID, [14, 44], 21, [40, 60], 19, { z: 2 }), capsula(ID, [40, 70], 9, [107, 97], 7.5, { z: 2 }),
    trazo('M 30 78 C 38 82 44 80 48 75', { z: 2.1, ancho: FINO }), trazo('M 16 70 C 23 76 30 76 34 72', { z: 2.1, ancho: FINO }),
    // manguito
    cerrada(rectPts(cM[0], cM[1], ml, ma, 6, giro), { capa: 'acento', z: 3, ancho: 3 }),
    poli([g([-ml + 8, -ma + 3]), g([-ml + 8, ma - 3])], { capa: 'acento', z: 3, ancho: FINO }),
    poli([g([ml - 8, -ma + 3]), g([ml - 8, ma - 3])], { capa: 'acento', z: 3, ancho: FINO }),
    // marca de la arteria: un punto y una flecha hacia el codo
    circulo(g([-2, 0]), 3.4, { capa: 'acento', z: 3, relleno: true }),
    ...flecha(...g([-2, 0]), ...g([20, 0]), { capa: 'acento', z: 3, ancho: 2.2 }, 6),
    // tubo
    trazo('M 165 141 C 190 145 220 151 234 175 C 244 193 244 220 242 246', { capa: 'acento', z: 8, ancho: 2.2 }),
    // llave entre el borde de abajo del manguito y el pliegue del codo
    trazo('M 166 162 L 166 170 L 185 170 L 185 162', { z: 6 }),
    ...referencia(1, 175.5, 189), ...referencia(2, ...g([-17, -13])), ...referencia(3, 86, 62),
  ];
  dibujo('presion_g4_colocar_manguito', 360, 240, prims);
}

// G5 · Qué evitar (10 tarjetas de 96 × 96, con la cruz en la esquina)
{
  const tarjeta = (n, prims) => dibujo(`presion_g5_${String(n).padStart(2, '0')}`, 96, 96, [marca('cruz', 82, 14, 9.5, 2.2), prims]);
  const o1 = { z: 1 }, f = { ancho: FINO };

  // 1 · Hablar o mirar el celular: persona con un globo de diálogo
  tarjeta(1, [
    circulo([32, 46], 12, o1),
    trazo('M 8 90 C 8 72 18 64 32 64 C 46 64 56 72 56 90'),
    trazo('M 52 30 L 82 30 Q 88 30 88 36 L 88 50 Q 88 56 82 56 L 62 56 L 53 64 L 55 56 L 52 56 Q 46 56 46 50 L 46 36 Q 46 30 52 30 Z', { z: 2 }),
    ...[57, 67, 77].map(x => circulo([x, 43], 1.9, { z: 2, relleno: true })),
  ]);

  // 2 · Piernas cruzadas
  tarjeta(2, [
    linea(4, 91, 92, 91),
    rect(6, 58, 50, 63.5, 2.5, { z: 0 }), linea(11, 64, 10, 91), linea(45, 64, 46, 91),
    capsula(ID, [22, -8], 12.5, [21.5, 44], 11.5, { z: 1 }),
    capsula(ID, [23, 49], 8.5, [55, 52], 6.5, { z: 1 }), capsula(ID, [55, 52], 6.5, [54, 80], 5, { z: 1 }),
    capsula(ID, [55, 85.5], 4.6, [69, 86.5], 3.8, { z: 1 }),
    capsula(ID, [23, 45], 9, [60, 41], 7, { z: 2 }), capsula(ID, [60, 41], 7, [78, 63], 5, { z: 2 }),
    capsula(ID, [80, 67], 4.6, [90, 76], 3.6, { z: 2 }),
  ]);

  // 3 · Sobre la ropa: el manguito encima de la manga
  tarjeta(3, [
    capsula(ID, [36, -10], 11.5, [42, 110], 10, { z: 1 }),
    trazo('M 19 -4 L 23.5 66 Q 39 71 55.5 64.5 L 52 -4 Z', { z: 2 }),
    trazo('M 28 62 L 29.5 54', { z: 2, ...f }), trazo('M 38 65 L 38.5 56', { z: 2, ...f }), trazo('M 48 62.5 L 47.5 54.5', { z: 2, ...f }),
    trazo('M 27 10 L 31 17', { z: 2, ...f }), trazo('M 47 9 L 43 17', { z: 2, ...f }),
    cerrada(rectPts(38, 35, 19.5, 13.5, 4, 3), { capa: 'acento', z: 3, ancho: 3 }),
    poli([[20.5, 42], [56.5, 44]], { capa: 'acento', z: 3, ...f }),
  ]);

  // 4 · Brazo colgando
  {
    const T = Tr({ s: 0.56, dx: -12, dy: -3 });
    tarjeta(4, [
      figura(T, { ...TRONCO, codo: [97, 122], muneca: [100, 158], mano: [101, 168], manguito: 0.62 }),
      capsula(T, [92, 142], 15, [150, 143.5], 13, { z: 1, recorte: [0, 0, 66, 96] }),
      rect(22, 85.6, 68, 90.4, 2.3, { z: 0 }),
    ]);
  }

  // 5 · Medirte recién entrenado: una mancuerna y un reloj (el momento de medir)
  tarjeta(5, [
    rect(8, 30, 15, 50, 2.5, o1), rect(15, 24, 23, 56, 3, o1),
    rect(47, 24, 55, 56, 3, o1), rect(55, 30, 62, 50, 2.5, o1),
    linea(23.5, 37, 46.5, 37), linea(23.5, 43, 46.5, 43),
    circulo([62, 68], 17, { z: 3 }), linea(62, 68, 62, 57, { z: 3 }), linea(62, 68, 70, 72, { z: 3 }),
    ...[0, 90, 180, 270].map(a => linea(62 + 13.6 * Math.cos(rad(a)), 68 + 13.6 * Math.sin(rad(a)), 62 + 14.4 * Math.cos(rad(a)), 68 + 14.4 * Math.sin(rad(a)), { z: 3, ...f })),
  ]);

  // 6 · Café, mate, energizante o preentreno: taza, mate y lata
  tarjeta(6, [
    linea(4, 89, 92, 89),
    trazo('M 7 62 L 27 62 L 27 78 Q 27 87 19 87 L 15 87 Q 7 87 7 78 Z'),
    trazo('M 27 66 Q 34.5 66 34.5 72 Q 34.5 78 27 78'),
    trazo('M 13 55 Q 10 51 13 47 Q 16 43 13 39', f), trazo('M 21 55 Q 18 51 21 47 Q 24 43 21 39', f),
    trazo('M 41 66 L 61 66 C 66 74 64 87 51 87 C 38 87 36 74 41 66 Z'),
    linea(40, 61.5, 62, 61.5), linea(40, 61.5, 41, 66), linea(62, 61.5, 61, 66),
    trazo('M 53 61 L 61 40 L 67 38'),
    rect(71, 46, 89, 87, 3.5, {}), linea(71.5, 52, 88.5, 52, f), linea(71.5, 81, 88.5, 81, f),
    trazo('M 77 46 Q 80 43.5 83 46', f),
  ]);

  // 7 · Cigarrillo o vapeador
  tarjeta(7, [
    cerrada(rectPts(38, 48, 30, 5, 1.5, -18)),
    (() => { const g = Tr({ giro: -18, dx: 38, dy: 48 }); return [poli([g([-14, -5]), g([-14, 5])]), trazo('M 33 -3 C 38 -8 31 -12 35 -17 C 38 -21 34 -24 35 -28', f, g)]; })(),
    (() => { const g = Tr({ giro: -18, dx: 46, dy: 76 }); return [
      cerrada(rectPts(46, 76, 26, 7, 7, -18)), cerrada(capsulaPts(g([-26, 0]), 3.6, g([-36, 0]), 3.2)),
      circulo(g([6, 0]), 2.4, { tapa: false, ...f }), poli([g([16, -7]), g([16, 7])], f),
    ]; })(),
  ]);

  // 8 · Con ganas de hacer pis: inodoro y gota
  tarjeta(8, [
    linea(6, 90, 78, 90),
    rect(12, 24, 30, 58, 3.5, {}),
    cerrada(capsulaPts([33, 58], 3.2, [70, 58], 3.2)),
    trazo('M 33 61.5 C 34 73 40 79 47 80.5 L 45 90'), trazo('M 69.5 61.5 C 69 72 64 78.5 57 80.5 L 59 90'),
    linea(30, 46, 33, 55), linea(21, 58, 21, 90, { tapa: false }),
    trazo('M 53 22 C 47 31 45 35 45 39 C 45 44 48.5 47 53 47 C 57.5 47 61 44 61 39 C 61 35 59 31 53 22 Z'),
  ]);

  // 9 · Sillón blando o sin respaldo: persona hundida en un sillón, con las rodillas más altas que la cadera
  tarjeta(9, [
    linea(4, 91, 92, 91),
    rect(7, 26, 25, 86, 8.5, { z: 0 }),
    circulo([38, 32], 8.5, o1), capsula(ID, [37.5, 40], 4, [37, 45], 4.2, o1),
    capsula(ID, [35, 52], 10.5, [37, 66], 10, o1),
    capsula(ID, [38, 68], 8, [68, 55], 6.2, o1), capsula(ID, [68, 55], 6.2, [77, 82], 4.6, o1),
    capsula(ID, [78, 86.6], 3.6, [88, 87], 3, o1),
    rect(15, 55, 61, 71, 7.5, { z: 2 }), rect(9, 69, 66, 86, 5, { z: 2 }),
    linea(14, 86.5, 14, 91), linea(61, 86.5, 61, 91),
  ]);

  // 10 · Reloj o anillo para medir
  tarjeta(10, [
    rect(10, 34, 44, 68, 9, o1),
    trazo('M 16 34.5 L 19 16 L 35 16 L 38 34.5'), trazo('M 16 67.5 L 19 86 L 35 86 L 38 67.5'),
    linea(44.5, 46, 47.5, 46), linea(47.5, 46, 47.5, 54), linea(44.5, 54, 47.5, 54),
    poli([[15.5, 51], [21, 51], [24.5, 43.5], [29, 58.5], [32.5, 51], [38.5, 51]], { z: 1, ...f }),
    circulo([70, 70], 14, {}), circulo([70, 70], 9.5, { tapa: false, ...f }),
    trazo('M 64.5 55.5 L 67 50.5 L 73 50.5 L 75.5 55.5', {}),
  ]);
}

// G6 · Ortostática (acostado o sentado, después parado al minuto 1 y al 3; recuadro por si se marea)
{
  const paradoEn = dx => {
    const T = Tr({ s: 0.55, dx, dy: 104.8 });
    const a = T([126, 37.6]), b = T([201, 225]);
    return [
      linea(T([70, 0])[0], 228.6, b[0] + 2, 228.6),
      cerrada([[a[0], b[1]], [a[0], a[1]], [b[0], a[1]], [b[0], b[1]]], { z: 0 }),
      linea(a[0], a[1] + 30, b[0], a[1] + 30, { z: 0, ancho: FINO }), linea(a[0], a[1] + 60, b[0], a[1] + 60, { z: 0, ancho: FINO }),
      figura(T, PARADO),
    ];
  };
  const comun = [
    paradoEn(150), ...reloj(1, 222, 36, 13),
    paradoEn(240), ...reloj(3, 312, 36, 13),
    ...flecha(165, 84, 184, 84), ...flecha(263, 84, 276, 84),
    // recuadro: sentado en el borde de la cama
    (() => {
      const T = Tr({ s: 0.46, dx: 34, dy: 125.4 });
      const a = T([-30, 158.5]), b = T([150, 190]);
      return [
        rect(6, 130, 150, 236, 8, { ancho: FINO, z: 0, tapa: false }),
        linea(16, 228.6, 140, 228.6),
        rect(a[0], a[1], b[0], b[1], 3, { z: 0 }), linea(a[0] + 4, b[1], a[0] + 4, 228.6), linea(b[0] - 4, b[1], b[0] - 4, 228.6),
        figura(T, { ...SENTADO, lejos: null, codo: [89, 112], muneca: [101, 146], mano: [114, 151] }),
      ];
    })(),
  ];
  // viñeta 1 acostado: boca arriba, con el brazo sobre una almohada chica a la altura del medio del pecho
  const T1 = Tr({ s: 0.55, giro: -90, dx: 36, dy: 140.8 });
  const acostado = [
    rect(6, 96.4, 162, 108.5, 3, { z: 0 }), linea(12, 109, 12, 117), linea(156, 109, 156, 117),
    cerrada(capsulaPts([13, 91.5], 4.6, [33, 91.5], 4.6), { z: 0.5 }),
    rect(48, 87, 102, 96.2, 3.5, { z: 1.5 }),
    figura(T1, ACOSTADO),
    ...reloj(5, 84, 36, 13),
  ];
  dibujo('presion_g6_ortostatica', 360, 240, [acostado, comun]);
  // variante: la viñeta 1 es la persona sentada de G1
  const T1s = Tr({ s: 0.5, dx: -10, dy: 6 });
  dibujo('presion_g6_ortostatica_sentado', 360, 240, [escenaSentado(T1s, { corta: true }), ...reloj(5, 122, 30, 13), comun]);
}

// Íconos sueltos
dibujo('presion_tilde', 24, 24, marca('tilde', 12, 12, 10, 2));
dibujo('presion_cruz', 24, 24, marca('cruz', 12, 12, 10, 2));

// ─── Resolver: aplanar, tapar, recortar y puntear ───────────────
const n2 = v => { const s = (Math.round(v * 100) / 100).toFixed(2).replace(/\.?0+$/, ''); return s === '-0' ? '0' : s; };
const pt = p => `${n2(p[0])} ${n2(p[1])}`;

/** Subtrazos de una primitiva como polilíneas: [{ pts, cerrada }]. */
function aplanar(e) {
  if (e.t === 'line') return [{ pts: [[e.x1, e.y1], [e.x2, e.y2]], cerrada: false }];
  if (e.t === 'circle') return [{ pts: arco(e.cx, e.cy, e.r, 0, 360, 4).slice(0, -1), cerrada: true }];
  if (e.t === 'polyline') return [{ pts: e.pts, cerrada: e.cerrada }];
  const subs = [];
  let act = null, ult = null;
  for (const { c, p } of e.cmds) {
    if (c === 'M') { act = { pts: [p[0]], cerrada: false }; subs.push(act); ult = p[0]; }
    else if (c === 'L') { act.pts.push(p[0]); ult = p[0]; }
    else if (c === 'Q' || c === 'C') {
      const N = 18;
      for (let i = 1; i <= N; i++) {
        const t = i / N, u = 1 - t;
        act.pts.push(c === 'Q'
          ? [u * u * ult[0] + 2 * u * t * p[0][0] + t * t * p[1][0], u * u * ult[1] + 2 * u * t * p[0][1] + t * t * p[1][1]]
          : [u ** 3 * ult[0] + 3 * u * u * t * p[0][0] + 3 * u * t * t * p[1][0] + t ** 3 * p[2][0],
             u ** 3 * ult[1] + 3 * u * u * t * p[0][1] + 3 * u * t * t * p[1][1] + t ** 3 * p[2][1]]);
      }
      ult = p[p.length - 1];
    } else if (c === 'Z') act.cerrada = true;
  }
  return subs;
}

/** La primitiva tal cual, como datos de path (cuando nada la tapa ni la recorta). */
function nativo(e) {
  if (e.t === 'line') return `M${pt([e.x1, e.y1])}L${pt([e.x2, e.y2])}`;
  if (e.t === 'circle') { const r = n2(e.r); return `M${pt([e.cx - e.r, e.cy])}A${r} ${r} 0 1 0 ${pt([e.cx + e.r, e.cy])}A${r} ${r} 0 1 0 ${pt([e.cx - e.r, e.cy])}Z`; }
  if (e.t === 'polyline') return polilineaD(e.pts, e.cerrada);
  return e.cmds.map(({ c, p }) => c + p.map(pt).join(' ')).join('');
}
const polilineaD = (pts, cerrar) => 'M' + pts.map(pt).join('L') + (cerrar ? 'Z' : '');

function dentro(p, poly) {
  let d = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i], b = poly[j];
    if ((a[1] > p[1]) !== (b[1] > p[1]) && p[0] < ((b[0] - a[0]) * (p[1] - a[1])) / (b[1] - a[1]) + a[0]) d = !d;
  }
  return d;
}
function distBorde(p, poly) {
  let m = Infinity;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[j], b = poly[i];
    const vx = b[0] - a[0], vy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / (vx * vx + vy * vy || 1)));
    m = Math.min(m, Math.hypot(p[0] - a[0] - t * vx, p[1] - a[1] - t * vy));
  }
  return m;
}
/** Douglas-Peucker: saca los puntos que no aportan. */
function simplificar(pts, tol = 0.05) {
  if (pts.length < 3) return pts;
  const queda = new Uint8Array(pts.length); queda[0] = queda[pts.length - 1] = 1;
  const pila = [[0, pts.length - 1]];
  while (pila.length) {
    const [i, j] = pila.pop();
    let peor = 0, k = -1;
    const a = pts[i], b = pts[j], vx = b[0] - a[0], vy = b[1] - a[1], L = Math.hypot(vx, vy) || 1;
    for (let m = i + 1; m < j; m++) {
      const d = Math.abs((pts[m][0] - a[0]) * vy - (pts[m][1] - a[1]) * vx) / L;
      if (d > peor) { peor = d; k = m; }
    }
    if (peor > tol) { queda[k] = 1; pila.push([i, k], [k, j]); }
  }
  return pts.filter((_, i) => queda[i]);
}
function puntear(pts, [on, off]) {
  const out = [];
  let resto = on, pintando = true, act = [pts[0]];
  for (let i = 1; i < pts.length; i++) {
    let a = pts[i - 1];
    const b = pts[i];
    let d = dist(a, b);
    while (d > resto) {
      const m = mezcla(a, b, resto / d);
      if (pintando) { act.push(m); out.push(act); act = []; } else act = [m];
      d -= resto; a = m; pintando = !pintando; resto = pintando ? on : off;
    }
    resto -= d;
    if (pintando) act.push(b);
  }
  if (pintando && act.length > 1) out.push(act);
  return out;
}

const PASO = 0.7, EPS = 0.22;

/** Devuelve, por capa, los grupos { ancho, relleno, d } listos para emitir. */
function resolver({ ancho, alto, prims }) {
  const planos = prims.map(e => ({ e, subs: aplanar(e) }));
  const tapas = [];
  for (const { e, subs } of planos) {
    if (e.tapa === false || e.relleno) continue;
    for (const s of subs) if (s.cerrada) {
      const xs = s.pts.map(p => p[0]), ys = s.pts.map(p => p[1]);
      tapas.push({ e, poly: s.pts, caja: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)] });
    }
  }
  const seFunde = e => e.tapa !== false && !e.relleno && aplanar(e).some(s => s.cerrada);
  const oculto = (p, e, funde) => {
    if (e.recorte && (p[0] < e.recorte[0] || p[1] < e.recorte[1] || p[0] > e.recorte[2] || p[1] > e.recorte[3])) return true;
    if (p[0] < -4 || p[1] < -4 || p[0] > ancho + 4 || p[1] > alto + 4) return true;
    for (const t of tapas) {
      if (t.e === e) continue;
      if (!(t.e.z > e.z || (t.e.z === e.z && funde))) continue;
      if (p[0] < t.caja[0] || p[1] < t.caja[1] || p[0] > t.caja[2] || p[1] > t.caja[3]) continue;
      if (dentro(p, t.poly) && distBorde(p, t.poly) > EPS) return true;
    }
    return false;
  };
  const grupos = new Map();
  const agregar = (e, d) => {
    if (!d) return;
    const k = `${e.capa}|${e.relleno ? 'r' : e.ancho}`;
    if (!grupos.has(k)) grupos.set(k, { capa: e.capa, ancho: e.ancho, relleno: !!e.relleno, d: [] });
    grupos.get(k).d.push(d);
  };
  for (const { e, subs } of planos) {
    if (e.relleno) { const c = subs[0].pts[0]; if (!oculto(c, e, false)) agregar(e, nativo(e)); continue; }
    const funde = seFunde(e);
    let entero = !e.punteado;
    const tramos = [];
    for (const s of subs) {
      // muestreo denso del subtrazo
      const base = s.cerrada ? [...s.pts, s.pts[0]] : s.pts;
      const m = [base[0]];
      for (let i = 1; i < base.length; i++) {
        const n = Math.max(1, Math.ceil(dist(base[i - 1], base[i]) / PASO));
        for (let k = 1; k <= n; k++) m.push(mezcla(base[i - 1], base[i], k / n));
      }
      const vis = m.map(p => !oculto(p, e, funde));
      if (vis.every(Boolean)) { tramos.push({ pts: s.pts, cerrada: s.cerrada }); continue; }
      entero = false;
      if (!vis.some(Boolean)) continue;
      // afinar el borde entre visible y tapado por bisección
      const borde = (a, b) => { let v = a, h = b; for (let i = 0; i < 7; i++) { const c = mezcla(v, h, 0.5); if (oculto(c, e, funde)) h = c; else v = c; } return v; };
      let ini = 0;
      if (s.cerrada) { ini = vis.indexOf(false); }
      const N = m.length - (s.cerrada ? 1 : 0);
      let act = null;
      for (let q = 0; q <= N; q++) {
        const i = s.cerrada ? (ini + q) % N : q;
        if (!s.cerrada && q === N) break;
        const v = vis[i];
        if (v) {
          if (!act) { act = []; if (q > 0) { const ant = s.cerrada ? (i - 1 + N) % N : i - 1; act.push(borde(m[i], m[ant])); } }
          act.push(m[i]);
        } else if (act) { act.push(borde(act[act.length - 1], m[i])); tramos.push({ pts: act, cerrada: false }); act = null; }
      }
      if (act) tramos.push({ pts: act, cerrada: false });
    }
    if (entero) { agregar(e, nativo(e)); continue; }
    for (const t of tramos) {
      if (e.punteado) {
        const patron = e.punteado === true ? [4, 6] : e.punteado;
        const linea0 = t.cerrada ? [...t.pts, t.pts[0]] : t.pts;
        for (const seg of puntear(linea0, patron)) agregar(e, polilineaD(simplificar(seg), false));
      } else {
        const s = simplificar(t.pts);
        if (s.length > 1) agregar(e, polilineaD(s, t.cerrada));
      }
    }
  }
  const capas = { base: [], acento: [] };
  for (const g of grupos.values()) capas[g.capa].push({ ancho: g.ancho, relleno: g.relleno, d: g.d.join('') });
  return capas;
}

// ─── Emisores ───────────────────────────────────────────────────
const AVISO = 'Generado por scripts/nativa/presion-dibujos.mjs. No editar a mano: cambiar el dibujo ahí y regenerar.';

function pathsSvg(grupos, color) {
  return grupos.map(g => g.relleno
    ? `<path d="${g.d}" fill="${color}" stroke="none"/>`
    : `<path d="${g.d}" fill="none" stroke="${color}" stroke-width="${n2(g.ancho)}" stroke-linecap="round" stroke-linejoin="round"/>`).join('');
}
function svgWeb(d, capas) {
  const capa = (g, color) => (g.length ? `<g>${pathsSvg(g, color)}</g>` : '');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${d.ancho} ${d.alto}" role="img" focusable="false">`
    + capa(capas.base, 'currentColor') + capa(capas.acento, 'var(--color-brand)') + '</svg>';
}
function svgSuelto(d, grupos, color, { fondo = null, escala = 1 } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${d.ancho * escala}" height="${d.alto * escala}" viewBox="0 0 ${d.ancho} ${d.alto}">`
    + (fondo ? `<rect width="${d.ancho}" height="${d.alto}" fill="${fondo}"/>` : '')
    + (typeof color === 'string' ? pathsSvg(grupos, color) : pathsSvg(grupos.base, color.base) + pathsSvg(grupos.acento, color.acento))
    + '</svg>\n';
}
function vectorAndroid(d, grupos) {
  const paths = grupos.map(g => g.relleno
    ? `    <path\n        android:fillColor="#FF000000"\n        android:pathData="${g.d}" />`
    : `    <path\n        android:pathData="${g.d}"\n        android:strokeColor="#FF000000"\n        android:strokeLineCap="round"\n        android:strokeLineJoin="round"\n        android:strokeWidth="${n2(g.ancho)}" />`).join('\n');
  return `<?xml version="1.0" encoding="utf-8"?>\n<!-- ${AVISO}\n     El negro es solo la máscara: se tiñe al usarlo (DibujoPresion.kt). -->\n`
    + `<vector xmlns:android="http://schemas.android.com/apk/res/android"\n    android:width="${d.ancho}dp"\n    android:height="${d.alto}dp"\n    android:viewportWidth="${d.ancho}"\n    android:viewportHeight="${d.alto}">\n${paths}${paths ? '\n' : ''}</vector>\n`;
}

function escribir(archivo, texto) {
  fs.mkdirSync(path.dirname(archivo), { recursive: true });
  fs.writeFileSync(archivo, texto);
}

const resueltos = Object.entries(DIBUJOS).map(([nombre, d]) => ({ nombre, d, capas: resolver(d) }));

// Web
{
  const filas = resueltos.map(({ nombre, d, capas }) => `    ${nombre}: '${svgWeb(d, capas)}',`).join('\n');
  escribir(SALIDA_WEB, `/* =============================================================
   presion-dibujos.js — Las ilustraciones de la pantalla de presión arterial,
   como SVG inline (nombre → string).

   ${AVISO.replace('scripts/nativa/', 'scripts/nativa/ del repo de las apps: ')}
   La misma fuente genera los imagesets de iOS y los VectorDrawable de Android.

   · La capa base usa currentColor y la de acento (el manguito) var(--color-brand).
   · Cada SVG lleva role="img" y no trae <title>: el texto alternativo lo pone
     quien lo usa, con aria-label.
   · Sin texto ni fuentes adentro: los números son trazos.
   ============================================================= */
(function (raiz) {
  'use strict';

  const API = Object.freeze({
${filas}
  });
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.PresionDibujos = API;
})(typeof window !== 'undefined' ? window : globalThis);
`);
}

// iOS
{
  fs.rmSync(SALIDA_IOS, { recursive: true, force: true });
  const info = '"info" : {\n    "author" : "xcode",\n    "version" : 1\n  }';
  escribir(path.join(SALIDA_IOS, 'Contents.json'), `{\n  ${info}\n}\n`);
  for (const { nombre, d, capas } of resueltos) for (const capa of ['base', 'acento']) {
    const dir = path.join(SALIDA_IOS, `${nombre}_${capa}.imageset`);
    escribir(path.join(dir, `${nombre}_${capa}.svg`), svgSuelto(d, capas[capa], '#000000'));
    escribir(path.join(dir, 'Contents.json'), `{
  "images" : [
    {
      "filename" : "${nombre}_${capa}.svg",
      "idiom" : "universal"
    }
  ],
  ${info},
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
`);
  }
}

// Android
{
  fs.mkdirSync(SALIDA_ANDROID, { recursive: true });
  for (const f of fs.readdirSync(SALIDA_ANDROID)) if (/^presion_.*_(base|acento)\.xml$/.test(f)) fs.rmSync(path.join(SALIDA_ANDROID, f));
  for (const { nombre, d, capas } of resueltos) for (const capa of ['base', 'acento'])
    escribir(path.join(SALIDA_ANDROID, `${nombre}_${capa}.xml`), vectorAndroid(d, capas[capa]));
}

// Control (para mirarlos): un SVG por dibujo en claro y en oscuro, con colores fijos. No es una salida de la app.
const iCtl = process.argv.indexOf('--control');
if (iCtl >= 0) {
  const dir = process.argv[iCtl + 1] && !process.argv[iCtl + 1].startsWith('--') ? process.argv[iCtl + 1] : CONTROL_DEFECTO;
  const temas = { claro: { fondo: '#ffffff', base: '#1c1c1e', acento: '#1d9330' }, oscuro: { fondo: '#111113', base: '#f2f2f7', acento: '#5bbe62' } };
  for (const { nombre, d, capas } of resueltos) for (const [tema, c] of Object.entries(temas))
    escribir(path.join(dir, 'svg', `${nombre}_${tema}.svg`), svgSuelto(d, capas, c, { fondo: c.fondo, escala: d.ancho >= 360 ? 2 : d.ancho >= 96 ? 4 : 8 }));
  // hoja con las tarjetas de G5 y los dos íconos, para verlas juntas
  const chicos = resueltos.filter(r => r.d.ancho < 360);
  for (const [tema, c] of Object.entries(temas)) {
    const celda = 240, cols = 4, filas = Math.ceil(chicos.length / cols);
    const cuerpo = chicos.map(({ d, capas }, i) => {
      const k = 216 / 96, x = (i % cols) * celda + 12, y = Math.floor(i / cols) * celda + 12;
      const e = d.ancho === 24 ? 2 : 1;
      return `<g transform="translate(${x} ${y}) scale(${k * e})">${pathsSvg(capas.base, c.base)}${pathsSvg(capas.acento, c.acento)}</g>`;
    }).join('');
    escribir(path.join(dir, 'svg', `hoja_g5_${tema}.svg`), `<svg xmlns="http://www.w3.org/2000/svg" width="${cols * celda}" height="${filas * celda}" viewBox="0 0 ${cols * celda} ${filas * celda}"><rect width="${cols * celda}" height="${filas * celda}" fill="${c.fondo}"/>${cuerpo}</svg>\n`);
  }
  console.log(`control: ${dir}/svg`);
}

const peso = resueltos.reduce((s, { capas }) => s + [...capas.base, ...capas.acento].reduce((a, g) => a + g.d.length, 0), 0);
console.log(`${resueltos.length} dibujos · ${Math.round(peso / 1024)} KB de trazos · web, iOS y Android escritos`);
