/* «Novedades de tu plan» (app 2.3.0, palanca `novedades_plan`): qué cambió entre la versión del plan que el alumno ya vio
 * y la que Mati acaba de publicar. Determinístico, sin IA. Port de NovedadesPlan.swift / NovedadesPlan.kt, con los mismos
 * casos (scripts/fixtures/novedades-casos.json, copia de apps/shared/fixtures/novedades/casos.json). Sin DOM.
 *
 * Textos: cortos, sin dos puntos, guiones ni emojis; nunca RIR (ni se compara) ni «cerca del fallo»; repes = referencia;
 * nunca «tu coach» ni «tu entrenador», solo Mati. Nunca una dosis: de la suplementación se nombra el suplemento y nada más.
 *
 * La versión anterior no está en el servidor (desde la 013 publicar pisa la fila): la que el alumno ya vio queda en el
 * navegador, por cuenta, en `mypump_novedades_base_<token>`; las novedades (las últimas 12) en `mypump_novedades_<token>`.
 *
 * Un área de una foto: `undefined` = no se sabe (no llegó, no se compara), `null` = el servidor dijo que no hay,
 * un objeto = la fila del RPC tal cual (mypump_get_rutina_activa, mypump_get_dieta_activa, mypump_suplementacion). */
(function (global) {
  'use strict';

  const MAX_LINEAS = 4;
  const MAXIMO = 12;
  const DIAS_TARJETA = 7;

  // ------------------------------------------------------------ Lectura (igual que Decodificacion.kt)

  const esObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
  const numFinito = (v) => typeof v === 'number' && isFinite(v);
  const txt = (v) => typeof v === 'string' ? v : numFinito(v) ? String(v) : null;
  function entero(v) {
    if (numFinito(v)) return Math.trunc(v);
    if (typeof v === 'string') { const s = v.trim(); return /^[+-]?\d+$/.test(s) ? parseInt(s, 10) : null; }
    return null;
  }
  function decimal(v) {
    if (numFinito(v)) return v;
    if (typeof v === 'string') {
      const s = v.trim().replace(',', '.');
      return /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s) ? Number(s) : null;
    }
    return null;
  }
  function booleano(v) {
    if (typeof v === 'boolean') return v;
    if (numFinito(v)) return Number.isInteger(v) ? v !== 0 : null;
    if (typeof v === 'string') return ['true', '1', 'si', 'sí'].includes(v.toLowerCase().normalize('NFC'));
    return null;
  }
  const lista = (v, f) => Array.isArray(v) ? v.map(f).filter((x) => x != null) : [];
  const nadaSiVacio = (s) => (s == null || s === '') ? null : s;
  const nadaSiBlanco = (s) => (s == null || !s.trim()) ? null : s;

  const macros = (o) => esObj(o) ? { kcal: decimal(o.kcal) } : null;

  function ejercicio(o) {
    if (!esObj(o)) return null;
    return {
      nombre: txt(o.nombre) || '', series: entero(o.series), reps: txt(o.reps),
      progresion: lista(o.progresion, (p) => esObj(p) ? { series: entero(p.series), reps: txt(p.reps) } : null),
    };
  }
  function dia(o) {
    if (!esObj(o)) return null;
    return { id: txt(o.id), n: entero(o.n), nombre: txt(o.nombre),
      bloques: lista(o.bloques, (b) => esObj(b) ? { ejercicios: lista(b.ejercicios, ejercicio) } : null) };
  }
  function leerRutina(r) {
    if (!esObj(r)) return null;
    const e = esObj(r.estructura) ? r.estructura : {};
    const sa = entero(r.semana_actual);
    return {
      semanaActual: sa == null ? 1 : sa,
      estructura: { nombrePlan: txt(e.nombre_plan), fase: entero(e.fase), dias: lista(e.dias, dia) },
    };
  }

  function alimento(o) {
    if (!esObj(o)) return null;
    return { nombre: txt(o.name) || '', qty: decimal(o.qty), unidad: txt(o.unit) };
  }
  function comida(o) {
    if (!esObj(o)) return null;
    return { id: txt(o.id) || '', nombre: txt(o.name),
      opciones: lista(o.options, (x) => esObj(x) ? { nombre: txt(x.name), alimentos: lista(x.foods, alimento) } : null) };
  }
  function leerDieta(d) {
    if (!esObj(d)) return null;
    const e = esObj(d.estructura) ? d.estructura : {};
    return {
      macrosTarget: macros(e.macros_target),
      comidas: lista(e.comidas, comida),
      tiposDia: lista(e.tipos_dia, (t) => esObj(t)
        ? { id: txt(t.id) || '', nombre: txt(t.nombre), macrosTarget: macros(t.macros_target), comidas: lista(t.comidas, comida) } : null),
    };
  }

  function textos(v) {
    if (Array.isArray(v)) return v.map((x) => { const t = txt(x); return t == null ? null : t.trim(); }).filter((x) => x);
    if (v == null) return [];
    const t = txt(v);
    return t && t.trim() ? [t.trim()] : [];
  }
  function item(o) {
    if (!esObj(o)) return null;
    const nombre = nadaSiVacio(txt(o.nombre));
    if (nombre == null) return null;
    return {
      nombre,
      cantidad: nadaSiBlanco(txt(o.cantidad)),
      momento: nadaSiBlanco(txt(o.momento)),
      tomas: lista(o.tomas, (t) => {
        if (!esObj(t)) return null;
        const m = nadaSiBlanco(txt(t.momento));
        return m == null ? null : { momento: m, cantidad: nadaSiBlanco(txt(t.cantidad)) };
      }),
      estado: nadaSiVacio(txt(o.estado)),
      opcional: booleano(o.opcional) === true,
      dias: textos(o.dias),
    };
  }
  /** La fila de mypump_suplementacion; null si no trae ningún ítem con nombre. */
  function leerSuplementacion(f) {
    if (!esObj(f) || !esObj(f.suplementacion)) return null;
    const items = lista(f.suplementacion.items, item);
    return items.length ? { items } : null;
  }

  // ------------------------------------------------------------ Texto

  const limpio = (s) => String(s == null ? '' : s).split(/[ \t\n\r]+/).filter(Boolean).join(' ');
  const TILDES = { á: 'a', à: 'a', ä: 'a', â: 'a', é: 'e', è: 'e', ë: 'e', ê: 'e', í: 'i', ì: 'i', ï: 'i', î: 'i',
    ó: 'o', ò: 'o', ö: 'o', ô: 'o', ú: 'u', ù: 'u', ü: 'u', û: 'u' };
  const clave = (s) => Array.from(limpio(s).normalize('NFC').toLowerCase()).map((c) => TILDES[c] || c).join('');
  const listaTexto = (xs) => xs.length <= 1 ? (xs[0] || '') : xs.slice(0, -1).join(', ') + ' y ' + xs[xs.length - 1];

  function recortar(l) {
    if (l.length <= MAX_LINEAS) return l;
    const resto = l.length - (MAX_LINEAS - 1);
    return l.slice(0, MAX_LINEAS - 1).concat([resto === 1 ? 'Y un cambio más' : `Y ${resto} cambios más`]);
  }

  // ------------------------------------------------------------ Rutina

  function ejercicios(d) {
    const vistos = new Set(); const r = [];
    for (const b of d.bloques) for (const e of b.ejercicios) {
      const nombre = limpio(e.nombre); const k = clave(nombre);
      if (!k || vistos.has(k)) continue;
      vistos.add(k); r.push({ clave: k, nombre, e });
    }
    return r;
  }
  const claveDia = (d, i) => { const id = limpio(d.id || ''); return id ? `id:${id}` : `i:${i}`; };

  /** «Tirón A — Ancho» → «Tirón A»; «TORSO A» → «Torso A». */
  function nombreDia(d, i) {
    let n = limpio(d.nombre || '');
    for (const sep of [' — ', ' – ', ' - ']) { const k = n.indexOf(sep); if (k >= 0) n = limpio(n.slice(0, k)); }
    if (!n) return `Día ${d.n != null ? d.n : i + 1}`;
    if (n === n.toUpperCase() && n !== n.toLowerCase()) {
      n = n.split(' ').map((p) => p.slice(0, 1).toUpperCase() + p.slice(1).toLowerCase()).join(' ');
    }
    return n;
  }

  function repsNormal(r) {
    if (r == null) return null;
    const s = limpio(r).replace(/^(\d+)\s*[-–—]\s*(\d+)$/, '$1 a $2');
    return s || null;
  }
  function formatoPauta(series, reps) {
    // Repes con texto que no puede salir (RIR, fallo, guiones, dos puntos): se dicen solo las series.
    const r = (reps && !/rir|fallo|[-–—:]/i.test(reps)) ? reps : null;
    const numerico = r != null && /^\d+( a \d+)?$/.test(r);
    const s = (n) => `${n} ${n === 1 ? 'serie' : 'series'}`;
    if (series != null && r != null) return numerico ? `${s(series)} de ${r}` : `${s(series)}, ${r}`;
    if (series != null) return s(series);
    if (r != null) return numerico ? `${r} repes` : r;
    return null;
  }
  function pauta(e, semana) {
    if (e.progresion.length) {
      const p = e.progresion[Math.max(0, Math.min(semana - 1, e.progresion.length - 1))];
      return [p.series, repsNormal(p.reps)];
    }
    return [e.series, repsNormal(e.reps)];
  }
  const pautas = (e) => e.progresion.length ? e.progresion.map((p) => [p.series, repsNormal(p.reps)]) : [[e.series, repsNormal(e.reps)]];
  const igualPauta = (a, b) => a[0] === b[0] && a[1] === b[1];

  function lineasBloque(dias, nuevos) {
    const r = [];
    if (dias.length === 1) r.push(`Un día, ${dias[0]}`);
    else if (dias.length <= 5) r.push(`${dias.length} días, ${listaTexto(dias)}`);
    else r.push(`${dias.length} días de entrenamiento`);
    if (nuevos === 1) r.push('Un ejercicio nuevo'); else if (nuevos > 1) r.push(`${nuevos} ejercicios nuevos`);
    return r;
  }

  const conIndice = (xs) => xs.map((value, index) => ({ value, index }));

  function rutina(antes, despues) {
    const nuevaE = despues.estructura;
    const diasNuevos = conIndice(nuevaE.dias).filter((x) => ejercicios(x.value).length);
    if (!diasNuevos.length) return null;
    const nombres = () => diasNuevos.map((x) => nombreDia(x.value, x.index));
    if (antes == null) return { area: 'rutina', titular: 'Mati te armó tu rutina', grande: true, lineas: lineasBloque(nombres(), 0) };
    const viejaE = antes.estructura;
    const diasViejos = conIndice(viejaE.dias).filter((x) => ejercicios(x.value).length);

    const clavesViejas = new Set(diasViejos.flatMap((d) => ejercicios(d.value).map((e) => e.clave)));
    const clavesNuevas = new Set();
    for (const d of diasNuevos) for (const e of ejercicios(d.value)) clavesNuevas.add(e.clave);
    const nuevos = [...clavesNuevas].filter((k) => !clavesViejas.has(k)).length;
    const a = viejaE.nombrePlan != null ? clave(viejaE.nombrePlan) : '';
    const b = nuevaE.nombrePlan != null ? clave(nuevaE.nombrePlan) : '';
    const otroPlan = (a && b && a !== b) || (viejaE.fase != null && nuevaE.fase != null && viejaE.fase !== nuevaE.fase);
    if (otroPlan || (nuevos >= 3 && nuevos * 2 >= clavesNuevas.size)) {
      return { area: 'rutina', titular: 'Mati te armó un bloque nuevo', grande: true, lineas: lineasBloque(nombres(), nuevos) };
    }

    const semana = Math.max(1, despues.semanaActual);
    const lineas = []; const usados = new Set();
    for (const { value: d, index: i } of diasNuevos) {
      const k = claveDia(d, i); const nombre = nombreDia(d, i);
      const v = diasViejos.find((x) => claveDia(x.value, x.index) === k);
      if (!v) { lineas.push(`Se suma un día nuevo, ${nombre}`); continue; }
      usados.add(k);
      const viejos = ejercicios(v.value); const actuales = ejercicios(d);
      const kv = new Set(viejos.map((e) => e.clave)); const ka = new Set(actuales.map((e) => e.clave));
      const salen = viejos.filter((e) => !ka.has(e.clave)); const entran = actuales.filter((e) => !kv.has(e.clave));
      const pares = Math.min(salen.length, entran.length);
      for (let j = 0; j < pares; j++) lineas.push(`En ${nombre} cambia ${salen[j].nombre} por ${entran[j].nombre}`);
      for (const e of entran.slice(pares)) lineas.push(`En ${nombre} se suma ${e.nombre}`);
      for (const e of salen.slice(pares)) lineas.push(`En ${nombre} sale ${e.nombre}`);
      for (const e of actuales) {
        const ant = viejos.find((x) => x.clave === e.clave);
        if (!ant) continue;
        const pn1 = pauta(e.e, semana); const pv1 = pauta(ant.e, semana);
        if (!igualPauta(pn1, pv1)) {
          const t = formatoPauta(pn1[0], pn1[1]);
          if (t) lineas.push(`En ${nombre}, ${e.nombre} pasa a ${t}`);
          continue;
        }
        const pn = pautas(e.e); const pv = pautas(ant.e);
        const hasta = Math.min(pn.length, pv.length);
        let cambia = false;
        for (let s = semana; s < hasta; s++) if (!igualPauta(pn[s], pv[s])) { cambia = true; break; }
        if (cambia) lineas.push(`En ${nombre}, ${e.nombre} cambia en las próximas semanas`);
      }
    }
    for (const { value: v, index: i } of diasViejos) if (!usados.has(claveDia(v, i))) lineas.push(`Sale el día ${nombreDia(v, i)}`);
    if (!lineas.length) return null;
    return { area: 'rutina', titular: 'Mati actualizó tu rutina', grande: false, lineas: recortar(lineas) };
  }

  // ------------------------------------------------------------ Dieta

  function comidas(cs) {
    const vistas = new Set(); const r = [];
    cs.forEach((c, i) => {
      const n = limpio(c.nombre || ''); const nombre = n || `Comida ${i + 1}`;
      const id = limpio(c.id); const k = id ? `id:${id}` : `n:${clave(nombre)}`;
      if (vistas.has(k)) return;
      vistas.add(k); r.push({ clave: k, nombre, c });
    });
    return r;
  }
  function alimentosDe(e) {
    const cs = e.tiposDia.length ? e.tiposDia.flatMap((t) => t.comidas) : e.comidas;
    const r = new Set();
    for (const c of cs) for (const o of c.opciones) for (const a of o.alimentos) { const k = clave(a.nombre); if (k) r.add(k); }
    return [...r];
  }
  const nombreTipo = (nombre, i) => limpio(nombre || '') || `Día ${i + 1}`;
  const claveTipo = (id, nombre) => { const x = limpio(id); return x ? `id:${x}` : `n:${clave(nombre)}`; };

  const redondear = (x) => x >= 0 ? Math.floor(x + 0.5) : -Math.floor(-x + 0.5);
  function formatoNumero(q) {
    const r = redondear(q * 10) / 10;
    if (r === redondear(r)) return String(Math.trunc(r) || 0);
    return r.toFixed(1).replace('.', ',');
  }
  function formatoKcal(k) {
    const n = redondear(k);
    const s = String(Math.abs(n));
    let out = '';
    for (let i = 0; i < s.length; i++) { if (i > 0 && (s.length - i) % 3 === 0) out += '.'; out += s[i]; }
    return (n < 0 ? '-' : '') + out;
  }
  const unidadNormal = (u) => clave(u || '') || 'g';
  function formatoCantidad(q, unidad) {
    const num = formatoNumero(q);
    const u = unidadNormal(unidad);
    if (['unidad', 'unidades', 'u', 'un', 'ud', 'uds'].includes(u)) return `${num} ${num === '1' ? 'unidad' : 'unidades'}`;
    return `${num} ${limpio(unidad || '') || 'g'}`;
  }
  const letraOpcion = (i) => i < 10 ? String.fromCharCode(65 + i) : String(i + 1);

  function lineasDietaNueva(e) {
    const r = [];
    const n = !e.tiposDia.length ? comidas(e.comidas).length : Math.max(0, ...e.tiposDia.map((t) => comidas(t.comidas).length));
    if (e.tiposDia.length > 1) r.push(`${e.tiposDia.length} tipos de día, ${listaTexto(e.tiposDia.map((t, i) => nombreTipo(t.nombre, i)))}`);
    if (n === 1) r.push('Una comida por día'); else if (n > 1) r.push(`${n} comidas por día`);
    const m = !e.tiposDia.length ? e.macrosTarget : e.tiposDia.length === 1 ? e.tiposDia[0].macrosTarget : null;
    const kcal = m ? m.kcal : null;
    if (kcal != null && kcal > 0) r.push(`Objetivo de ${formatoKcal(kcal)} kcal por día`);
    return r;
  }

  function lineasKcal(a, b, tipo) {
    const x = a && a.kcal; const y = b && b.kcal;
    if (x == null || y == null || x <= 0 || y <= 0 || Math.abs(y - x) < 50) return [];
    return [tipo != null ? `En ${tipo}, tu objetivo pasa a ${formatoKcal(y)} kcal` : `Tu objetivo del día pasa a ${formatoKcal(y)} kcal`];
  }

  function lineasOpcion(viejos, nuevos, lugar, lugarComa) {
    const planos = (xs) => { const vistos = new Set(); const r = [];
      for (const a of xs) { const k = clave(a.nombre); if (k && !vistos.has(k)) { vistos.add(k); r.push([k, a]); } } return r; };
    const v = planos(viejos); const n = planos(nuevos);
    const kv = new Set(v.map((x) => x[0])); const kn = new Set(n.map((x) => x[0]));
    const salen = v.filter((x) => !kn.has(x[0])); const entran = n.filter((x) => !kv.has(x[0]));
    const pares = Math.min(salen.length, entran.length);
    const r = [];
    for (let j = 0; j < pares; j++) r.push(`${lugar} cambia ${limpio(salen[j][1].nombre)} por ${limpio(entran[j][1].nombre)}`);
    for (const e of entran.slice(pares)) r.push(`${lugar} se suma ${limpio(e[1].nombre)}`);
    for (const e of salen.slice(pares)) r.push(`${lugar} sale ${limpio(e[1].nombre)}`);
    for (const [k, a] of n) {
      const bx = v.find((x) => x[0] === k);
      if (!bx) continue;
      const b = bx[1];
      const mismaUnidad = unidadNormal(a.unidad) === unidadNormal(b.unidad);
      const mismaCantidad = (a.qty != null && b.qty != null) ? Math.abs(a.qty - b.qty) < 0.001 : (a.qty == null && b.qty == null);
      if (!(mismaUnidad && mismaCantidad) && a.qty != null) r.push(`${lugarComa} ${limpio(a.nombre)} pasa a ${formatoCantidad(a.qty, a.unidad)}`);
    }
    return r;
  }

  function lineasComidas(viejas, nuevas, tipo) {
    const lineas = [];
    const cv = comidas(viejas); const cn = comidas(nuevas);
    const etiqueta = (n) => tipo != null ? `${n} (${tipo})` : n;
    for (const c of cn) {
      const v = cv.find((x) => x.clave === c.clave) || cv.find((x) => clave(x.nombre) === clave(c.nombre));
      if (!v) { lineas.push(`Se suma ${etiqueta(c.nombre)}`); continue; }
      const nombre = etiqueta(c.nombre);
      const on = c.c.opciones; const ov = v.c.opciones;
      const varias = on.length > 1;
      for (let i = 0; i < Math.min(on.length, ov.length); i++) {
        const letra = limpio(on[i].nombre || '') || letraOpcion(i);
        const lugar = varias ? `En ${nombre}, opción ${letra},` : `En ${nombre}`;
        const lugarComa = varias ? lugar : `${lugar},`;
        lineas.push(...lineasOpcion(ov[i].alimentos, on[i].alimentos, lugar, lugarComa));
      }
      if (on.length > ov.length) lineas.push(on.length - ov.length === 1 ? `En ${nombre} se suma una opción` : `En ${nombre} se suman ${on.length - ov.length} opciones`);
      else if (ov.length > on.length) lineas.push(ov.length - on.length === 1 ? `En ${nombre} sale una opción` : `En ${nombre} salen ${ov.length - on.length} opciones`);
    }
    for (const v of cv) if (!cn.some((x) => x.clave === v.clave || clave(x.nombre) === clave(v.nombre))) lineas.push(`Sale ${etiqueta(v.nombre)}`);
    return lineas;
  }

  function dieta(antes, despues) {
    const todosNuevos = alimentosDe(despues);
    if (!todosNuevos.length) return null;
    if (antes == null) return { area: 'dieta', titular: 'Mati te armó tu dieta', grande: true, lineas: lineasDietaNueva(despues) };
    const viejos = new Set(alimentosDe(antes));
    const nuevos = todosNuevos.filter((k) => !viejos.has(k)).length;
    const cambioDeFormato = !antes.tiposDia.length !== !despues.tiposDia.length;
    if (cambioDeFormato || (nuevos >= 4 && nuevos * 2 >= todosNuevos.length)) {
      return { area: 'dieta', titular: 'Mati te armó una dieta nueva', grande: true, lineas: lineasDietaNueva(despues) };
    }
    const lineas = [];
    if (!despues.tiposDia.length) {
      lineas.push(...lineasKcal(antes.macrosTarget, despues.macrosTarget, null));
      lineas.push(...lineasComidas(antes.comidas, despues.comidas, null));
    } else {
      const varios = despues.tiposDia.length > 1;
      const usados = new Set();
      despues.tiposDia.forEach((t, i) => {
        const nombre = nombreTipo(t.nombre, i);
        const k = claveTipo(t.id, nombre);
        const v = antes.tiposDia.find((x, j) => claveTipo(x.id, nombreTipo(x.nombre, j)) === k);
        if (!v) { lineas.push(`Se suma un tipo de día, ${nombre}`); return; }
        usados.add(k);
        lineas.push(...lineasKcal(v.macrosTarget, t.macrosTarget, varios ? nombre : null));
        lineas.push(...lineasComidas(v.comidas, t.comidas, varios ? nombre : null));
      });
      antes.tiposDia.forEach((x, j) => { const nx = nombreTipo(x.nombre, j); if (!usados.has(claveTipo(x.id, nx))) lineas.push(`Sale el tipo de día ${nx}`); });
    }
    if (!lineas.length) return null;
    return { area: 'dieta', titular: 'Mati actualizó tu dieta', grande: false, lineas: recortar(lineas) };
  }

  // ------------------------------------------------------------ Suplementación

  // «Sin dosis»: el nombre del suplemento sin la cantidad que a veces trae pegada («Creatina 5 g» → «Creatina»). Port EXACTO
  // de la referencia (scripts/nativa/novedades-sin-dosis.py en la rama nativa): se recorre palabra por palabra, sin `\b`.
  // La prueba compartida es scripts/fixtures/novedades-sin-dosis.json: las tres plataformas dan la misma salida.
  const SD_UNIDADES = new Set(('mg mcg ug µg g gr grs kg ml l ui iu % cap caps capsula capsulas comprimido comprimidos comp tableta tabletas '
    + 'tab tabs pastilla pastillas gota gotas scoop scoops cucharada cucharadas cucharadita cucharaditas sobre sobres unidad unidades').split(' '));
  const SD_TIEMPOS = new Set(['dia', 'toma', 'noche', 'semana', 'comida', 'mañana']);
  const SD_ENLACES = new Set(['por', 'x', 'al', '/', 'c/']);
  const SD_SUELTOS = new Set(['x', '-', '–', '—', ':', '·']);
  const SD_NUM = '0123456789.,';
  const SD_DIGITOS = '0123456789';
  const sdCuenta = (s, c) => s.split(c).length - 1;
  function sdNorm(t) {
    let n = clave(t);
    while (n && '(['.includes(n[0])) n = n.slice(1);
    while (n && ').,;:]'.includes(n[n.length - 1])) n = n.slice(0, -1);
    return n;
  }
  /** [número, resto]. El número: dígitos con . o , y a lo sumo un rango «3-5» o «3/5». */
  function sdPartir(n) {
    if (!n || !SD_DIGITOS.includes(n[0])) return ['', n];
    let i = 0;
    while (i < n.length && SD_NUM.includes(n[i])) i++;
    if (i + 1 < n.length && '-/'.includes(n[i]) && SD_DIGITOS.includes(n[i + 1])) {
      i++;
      while (i < n.length && SD_NUM.includes(n[i])) i++;
    }
    return [n.slice(0, i), n.slice(i)];
  }
  function sdUnidad(r) {
    r = r.split('/')[0];
    while (r.endsWith('.')) r = r.slice(0, -1);
    return SD_UNIDADES.has(r);
  }
  const sdEsNumero = (n) => { const [p, r] = sdPartir(n); return p !== '' && r === ''; };
  const sdSoloDigitos = (s) => Array.from(s).every((c) => SD_DIGITOS.includes(c));

  function sinDosis(nombre) {
    const base = limpio(nombre);
    const ts = base ? base.split(' ') : [];
    const out = [];
    let i = 0; let cerrar = 0;
    while (i < ts.length) {
      let t = ts[i];
      const n = sdNorm(t);
      const [p, r] = sdPartir(n);
      let quita = 0;
      if (p) {
        if (r && (sdUnidad(r) || r === 'x')) quita = 1;
        else if (!r && i + 1 < ts.length && sdNorm(ts[i + 1]) && sdUnidad(sdNorm(ts[i + 1]))) quita = 2;
      } else if (n.length > 1 && n[0] === 'x' && sdSoloDigitos(n.slice(1))) quita = 1;
      if (!quita) {
        if (cerrar && t.endsWith(')')) { t = t.slice(0, -1); cerrar--; }
        if (t) out.push(t);
        i++;
        continue;
      }
      let ido = ts.slice(i, i + quita);
      i += quita;
      if (i + 1 < ts.length && SD_ENLACES.has(sdNorm(ts[i])) && SD_TIEMPOS.has(sdNorm(ts[i + 1]))) { ido = ido.concat(ts.slice(i, i + 2)); i += 2; }
      else if (i < ts.length && sdNorm(ts[i]).startsWith('/') && SD_TIEMPOS.has(sdNorm(ts[i]).slice(1))) { ido = ido.concat(ts.slice(i, i + 1)); i += 1; }
      else if (i + 1 < ts.length && sdNorm(ts[i]) === 'x' && sdEsNumero(sdNorm(ts[i + 1]))) { ido = ido.concat(ts.slice(i, i + 2)); i += 2; }
      if (out.length >= 2 && sdNorm(out[out.length - 1]) === 'a' && sdEsNumero(sdNorm(out[out.length - 2]))) { ido = out.slice(-2).concat(ido); out.splice(-2, 2); }
      if (out.length && SD_SUELTOS.has(out[out.length - 1])) out.pop();
      const a = ido.reduce((s, x) => s + sdCuenta(x, '('), 0);
      const c = ido.reduce((s, x) => s + sdCuenta(x, ')'), 0);
      if (a > c) cerrar += a - c;
      else if (c > a && out.length && sdCuenta(out.join(' '), '(') > sdCuenta(out.join(' '), ')')) out[out.length - 1] += ')';
    }
    while (out.length && Array.from(out[out.length - 1]).every((ch) => '-–—:,·+/x'.includes(ch))) out.pop();
    if (out.length) {
      let u = out[out.length - 1];
      while (u && ',:;'.includes(u[u.length - 1])) u = u.slice(0, -1);
      if (u) out[out.length - 1] = u; else out.pop();
    }
    return out.join(' ').split('()').join('').trim();
  }

  /** La cantidad se compara pero nunca se muestra. */
  function firma(it) {
    const tomas = it.tomas.map((t) => `${clave(t.momento || '')}=${clave(t.cantidad || '')}`).join(';');
    const dias = it.dias.map(clave).sort().join(',');
    return [clave(it.cantidad || ''), clave(it.momento || ''), tomas, dias, it.opcional ? '1' : '0'].join('|');
  }
  /** [clave, nombre para mostrar, firma]. Se compara y se muestra sin la dosis; si el nombre la traía, la firma suma el
   *  nombre entero: «Creatina 3 g» → «Creatina 5 g» es «Cambia cómo tomás Creatina». */
  function activos(s) {
    const vistos = new Set(); const r = [];
    for (const it of (s ? s.items : [])) {
      const nombre = sinDosis(it.nombre);
      const k = clave(nombre);
      if (!k || clave(it.estado || '') === 'sale' || vistos.has(k)) continue;
      vistos.add(k);
      const entero = clave(it.nombre);
      r.push([k, nombre, entero !== k ? `${firma(it)}|${entero}` : firma(it)]);
    }
    return r;
  }
  function suplementacion(antes, despues) {
    const n = activos(despues);
    if (antes == null) {
      if (!n.length) return null;
      return { area: 'suplementacion', titular: 'Mati te armó tu suplementación', grande: true,
        lineas: [n.length === 1 ? 'Un suplemento para tu día' : `${n.length} suplementos para tu día`] };
    }
    const v = activos(antes);
    const kv = new Set(v.map((x) => x[0])); const kn = new Set(n.map((x) => x[0]));
    const lineas = [];
    for (const [k, nombre] of n) if (!kv.has(k)) lineas.push(`Se suma ${nombre}`);
    for (const [k, nombre] of v) if (!kn.has(k)) lineas.push(`Dejás de tomar ${nombre}`);
    for (const [k, nombre, f] of n) {
      const b = v.find((x) => x[0] === k);
      if (b && f !== b[2]) lineas.push(`Cambia cómo tomás ${nombre}`);
    }
    if (!lineas.length) return null;
    return { area: 'suplementacion', titular: 'Mati actualizó tu suplementación', grande: false, lineas: recortar(lineas) };
  }

  // ------------------------------------------------------------ Cálculo

  /** Un área cruda → {conocida, valor}: valor null = no hay (o no se pudo leer y entonces no es conocida). */
  function area(v, leer) {
    if (v === undefined) return { conocida: false, valor: null };
    if (v === null) return { conocida: true, valor: null };
    const x = leer(v);
    return x == null ? { conocida: false, valor: null } : { conocida: true, valor: x };
  }

  /** null = nada que contar (sin cambios, solo cambió la semana, el RIR o datos internos). */
  function calcular(antes, despues) {
    antes = antes || {}; despues = despues || {};
    const partes = [];
    const ra = area(antes.rutina, leerRutina); const rn = area(despues.rutina, leerRutina);
    if (ra.conocida && rn.valor) { const p = rutina(ra.valor, rn.valor); if (p) partes.push(p); }
    const da = area(antes.dieta, leerDieta); const dn = area(despues.dieta, leerDieta);
    if (da.conocida && dn.valor) { const p = dieta(da.valor, dn.valor); if (p) partes.push(p); }
    const sa = area(antes.suplementacion, leerSuplementacion); const sn = area(despues.suplementacion, leerSuplementacion);
    if (sa.conocida && sn.valor) { const p = suplementacion(sa.valor, sn.valor); if (p) partes.push(p); }
    if (!partes.length) return null;
    if (partes.length === 1) return { titular: partes[0].titular, resumen: partes[0].lineas[0] || partes[0].titular, partes };
    const nombres = partes.map((p) => p.area === 'rutina' ? 'tu rutina' : p.area === 'dieta' ? 'tu dieta' : 'tu suplementación');
    return { titular: 'Mati actualizó tu plan', resumen: `Hay cambios en ${listaTexto(nombres)}`, partes };
  }

  // ------------------------------------------------------------ Modelo (el plan visto y la lista, por cuenta)

  const uuid = () => (global.crypto && global.crypto.randomUUID) ? global.crypto.randomUUID()
    : 'n' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);

  /** almacen: {leer(k) → texto|null, guardar(k, texto)}; ahora: () → ms. */
  function crearModelo(token, almacen, ahora = () => Date.now()) {
    const kBase = `mypump_novedades_base_${token}`;
    const kLista = `mypump_novedades_${token}`;
    const leerJson = (k) => { try { return JSON.parse(almacen.leer(k) || 'null'); } catch (_) { return null; } };
    const valida = (n) => esObj(n) && typeof n.id === 'string' && typeof n.fecha === 'number' && typeof n.titular === 'string'
      && typeof n.resumen === 'string' && Array.isArray(n.partes);
    let lista = (() => { const l = leerJson(kLista); return Array.isArray(l) ? l.filter(valida) : []; })();
    const escuchas = [];
    const guardarLista = () => { try { almacen.guardar(kLista, JSON.stringify(lista)); } catch (_) {} escuchas.forEach((f) => { try { f(); } catch (_) {} }); };
    const guardada = (v) => v === undefined ? undefined : v === null ? { hay: false } : { hay: true, valor: v };
    const cruda = (a) => !esObj(a) ? undefined : a.hay !== true ? null : (a.valor == null ? undefined : a.valor);

    return {
      get lista() { return lista; },
      /** La que se muestra sola al abrir: la más nueva sin ver. */
      get pendiente() { return lista.find((n) => !n.vista) || null; },
      /** La tarjeta de Entreno: la última, durante DIAS_TARJETA días. */
      get reciente() { const n = lista[0]; return n && ahora() - n.fecha < DIAS_TARJETA * 86400000 ? n : null; },
      alCambiar(f) { escuchas.push(f); },
      marcarVista(id) {
        const i = lista.findIndex((n) => n.id === id);
        if (i < 0 || lista[i].vista) return;
        lista = lista.slice(); lista[i] = Object.assign({}, lista[i], { vista: true });
        guardarLista();
      },
      /** Compara lo que llegó con lo que ya se vio, guarda la base nueva y, si cambió algo, la novedad.
       *  semilla: lo que había en el navegador antes de esta carga, por si todavía no hay base. */
      observar(llego, semilla = {}) {
        // Una fila de suplementación sin ningún ítem con nombre es «no hay», como en la app.
        const supl = (v) => (esObj(v) && !leerSuplementacion(v)) ? null : v;
        llego = Object.assign({}, llego, { suplementacion: supl(llego.suplementacion) });
        semilla = Object.assign({}, semilla, { suplementacion: supl(semilla.suplementacion) });
        const base = leerJson(kBase);
        const antes = esObj(base) ? { rutina: base.rutina, dieta: base.dieta, suplementacion: base.suplementacion }
          : { rutina: guardada(semilla.rutina), dieta: guardada(semilla.dieta), suplementacion: guardada(semilla.suplementacion) };
        const nueva = Object.assign({}, antes);
        for (const k of ['rutina', 'dieta', 'suplementacion']) { const g = guardada(llego[k]); if (g !== undefined) nueva[k] = g; }
        for (const k of Object.keys(nueva)) if (nueva[k] === undefined) delete nueva[k];
        const txtNueva = JSON.stringify(nueva);
        if (txtNueva !== JSON.stringify(base)) { try { almacen.guardar(kBase, txtNueva); } catch (_) {} }
        const fa = { rutina: cruda(antes.rutina), dieta: cruda(antes.dieta), suplementacion: cruda(antes.suplementacion) };
        const fd = { rutina: llego.rutina, dieta: llego.dieta, suplementacion: llego.suplementacion };
        const r = calcular(fa, fd);
        if (!r) return null;
        const n = { id: uuid(), fecha: ahora(), titular: r.titular, resumen: r.resumen, partes: r.partes, vista: false };
        // Las anteriores quedan vistas: se muestra la de esta publicación, nunca una vieja que no se llegó a abrir.
        lista = [n].concat(lista.map((x) => x.vista ? x : Object.assign({}, x, { vista: true }))).slice(0, MAXIMO);
        guardarLista();
        return n;
      },
    };
  }

  /** Con la palanca apagada el plan «ya visto» no se guarda: se borra en cada carga, así al prenderla se parte de la copia
   *  de la última carga y no de una base de hace semanas. La lista de novedades ya guardadas no se toca. */
  function olvidarBase(token, almacen) {
    const k = `mypump_novedades_base_${token}`;
    try {
      if (almacen.leer(k) == null) return;
      if (almacen.borrar) almacen.borrar(k); else almacen.guardar(k, 'null');
    } catch (_) {}
  }

  const API = { MAX_LINEAS, MAXIMO, DIAS_TARJETA, calcular, crearModelo, sinDosis, olvidarBase, formatoPauta, repsNormal, formatoCantidad, formatoKcal,
    recortar, nombreDia, clave, limpio };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else global.NovedadesPlan = API;
})(typeof window !== 'undefined' ? window : globalThis);
