/* =============================================================
   presion-prueba.js — doble del servidor de «Presión arterial», en memoria, para ver
   las pantallas sin base ni red. Datos inventados.

   SOLO en localhost: lo carga cliente.html con ?presionprueba=<pantalla> y, por si alguien
   lo incluyera a mano, acá se vuelve a mirar el host. No está en el shell del service worker.

   USO:  npx serve public -l <puerto>
         http://localhost:<puerto>/cliente.html?demo=1&presionprueba=inicio[&tema=oscuro][&letra=150]
   pantallas: inicio, antes, antesmedir, antesaparato, medir, cuando, evitar, como, previas, reposo, anotar, confirmar,
              espera, guardia, guardiasintomas, sintoma, listo, orto, pendiente
   la tarjeta de arriba en Entreno (no abre Presión): tarjeta-toma, tarjeta-seguir, tarjeta-repetir, tarjeta-preparar, tarjeta-hoylisto
   directo (como un aviso con destino presion): directo-toma, directo-repetir, directo-preparar
   ============================================================= */
(function (raiz) {
  'use strict';
  if (!/^(localhost|127\.0\.0\.1|\[::1\])$/.test(location.hostname)) return;
  const q = new URLSearchParams(location.search);
  const pantalla = q.get('presionprueba');
  if (!pantalla) return;

  const dia = (n) => { const d = new Date(); d.setDate(d.getDate() + n); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
  const toma = (orden, sis, dia_, pulso) => ({ orden, posicion: 'sentado', sis, dia: dia_, pulso, latido_irregular: false });
  const caso = pantalla.replace(/^(tarjeta|directo)-/, '');
  const enEntreno = /^tarjeta-/.test(pantalla), directo = /^directo-/.test(pantalla);
  const sinAparato = /^antes/.test(pantalla) || ((enEntreno || directo) && caso === 'preparar');
  const primera = (enEntreno || directo) && caso === 'toma';
  const S = {
    aparato: sinAparato ? null : { id: 'a1', tipo: 'brazo', marca: 'Marca', modelo: 'Modelo 3', modelo_codigo: 'AB-1234-LA', manguito_min_cm: 22, manguito_max_cm: 42, manguito_validado_min_cm: null, manguito_validado_max_cm: null, validado: 'si' },
    cm: sinAparato ? null : 36.5,
    serie: {
      id: 'serie-prueba', motivo: 'inicio', tipo: 'estandar', estado: 'en_curso', tomas_objetivo: 3, fecha_inicio: dia(-2), fecha_limite: dia(4), brazo: 'izq',
      ortostatica: pantalla === 'orto' ? 'acostado_parado' : null, comparar_brazos: false, medida_pedida: pantalla === 'medir',
      dias: sinAparato || primera ? [] : caso === 'hoylisto' ? [dia(-1), dia(0)] : [dia(-2), dia(-1)], faltan: sinAparato || primera ? 3 : 1,
    },
    sesiones: sinAparato ? [] : [
      { id: 's2', serie_id: 'serie-prueba', fecha: dia(-1), tipo: 'estandar', cuenta: true, tomas: [toma(1, 128, 82, 64)] },
      { id: 's1', serie_id: 'serie-prueba', fecha: dia(-2), tipo: 'estandar', cuenta: true, tomas: [toma(1, 124, 78, 61)] },
      { id: 's0', serie_id: null, fecha: dia(-6), tipo: 'suelta', cuenta: false, tomas: [toma(1, 131, 84, 70)] },
    ],
    pendiente: pantalla === 'pendiente' || caso === 'repetir' ? { sesion_id: 's9', nivel: 'urgencia', desde: new Date(Date.now() - 20 * 60000).toISOString() } : null,
    sintomas: [],
  };
  if (pantalla === 'pendiente' || caso === 'repetir') S.sesiones.unshift({ id: 's9', serie_id: 'serie-prueba', fecha: dia(0), tipo: 'estandar', cuenta: false, tomas: [toma(1, 184, 112, 80)] });

  const estado = () => ({
    habilitado: true, fotos: false, hoy: dia(0), aparato: S.aparato, circunferencia_brazo_cm: S.cm, serie: S.serie,
    sesiones: S.sesiones, pendiente: S.pendiente, tensiometros: null,
  });
  async function rpc(fn, p) {
    switch (fn) {
      case 'mypump_presion_get': return { ok: true, data: estado() };
      case 'mypump_presion_aparato': S.aparato = { id: 'a2', validado: 'sin_revisar', manguito_validado_min_cm: null, manguito_validado_max_cm: null, ...p.p_aparato }; return { ok: true, data: { ok: true, estado: estado() } };
      case 'mypump_presion_medida': S.cm = p.p_cm; S.serie.medida_pedida = false; return { ok: true, data: { ok: true, estado: estado() } };
      case 'mypump_presion_sesion': {
        const s = p.p_sesion, i = S.sesiones.findIndex((x) => x.id === s.id);
        const fila = { id: s.id, serie_id: s.serie_id || null, fecha: dia(0), tipo: s.tipo, cuenta: false, tomas: s.tomas.map((t) => ({ orden: t.orden, posicion: t.posicion, sis: t.sis, dia: t.dia, pulso: t.pulso, latido_irregular: t.latido_irregular })) };
        if (i === -1) S.sesiones.unshift(fila); else S.sesiones[i] = fila;
        return { ok: true, data: { ok: true, estado: estado() } };
      }
      case 'mypump_presion_sintoma': S.sintomas.push(p.p_sintoma); return { ok: true, data: { ok: true } };
      default: return { ok: false, status: 404, codigo: 'PGRST202', clase: 'permanente' };
    }
  }

  /* Emula el zoom de texto del teléfono: agranda solo la letra, no las cajas. */
  function agrandar(factor) {
    const xs = [...document.body.querySelectorAll('*')].filter((el) => !el.closest('svg'));
    const px = xs.map((el) => parseFloat(getComputedStyle(el).fontSize));
    xs.forEach((el, i) => { if (px[i] > 0) el.style.fontSize = `${(px[i] * factor).toFixed(2)}px`; });
  }

  /* Lleva la pantalla al punto pedido con las mismas acciones que tocaría el alumno. */
  async function guion(UI) {
    const m = UI._modelo;
    if (!m) return;
    if (q.get('tema') === 'oscuro') { document.documentElement.setAttribute('data-theme', 'dark'); document.body.setAttribute('data-theme', 'dark'); }
    await m.cerrar();
    for (const f of m.cola.slice()) await m._sacar(f.id);
    if (directo) UI.abrirDirecto('train'); else if (!enEntreno) UI.abrir('misdatos');
    const u = UI._ui, a = (n, b) => UI._accion(n, b);
    const no = () => { u.previas = { cafeina: 'no', fumo: 'no', comida: 'no', ejercicio: 'no' }; };
    const hastaAnotar = async () => { a('toma'); a('seguirCuando'); await a('seguirComo'); no(); await a('medirIgual'); await a('saltear'); };
    const anotar = async (sis, dia_, pulso) => { u.toma = { sis: String(sis), dia: String(dia_), pulso: String(pulso), irregular: false }; await a('confirmar'); };
    switch (pantalla) {
      case 'antes': a('principal'); break;
      case 'antesmedir': a('principal'); u.form.cm = '36,5'; a('seguirAntes'); break;
      case 'antesaparato': a('principal'); u.form.cm = '36,5'; a('seguirAntes'); a('seguirAntes'); u.form.tipo = 'brazo'; u.form.min = '22'; u.form.max = '32'; break;
      case 'medir': a('toma'); break;
      case 'cuando': a('toma'); break;
      case 'evitar': a('toma'); a('evitar'); break;
      case 'como': a('toma'); a('seguirCuando'); break;
      case 'previas': a('toma'); a('seguirCuando'); await a('seguirComo'); u.previas = { cafeina: 'no', fumo: 'no' }; break;
      case 'reposo': a('toma'); a('seguirCuando'); await a('seguirComo'); no(); await a('medirIgual'); break;
      case 'anotar': await hastaAnotar(); u.toma = { sis: '124', dia: '78', pulso: '62', irregular: false }; break;
      case 'confirmar': await hastaAnotar(); u.toma = { sis: '166', dia: '98', pulso: '72', irregular: false }; await a('anotar'); break;
      case 'espera': await hastaAnotar(); await anotar(186, 112, 84); break;
      case 'guardia': await hastaAnotar(); await anotar(186, 112, 84); for (const k of raiz.Presion.ALARMA) await m.responderLista(k, false); m.curso.fin = Date.now() - 1000; await a('repetir'); await anotar(184, 110, 82); break;
      case 'guardiasintomas': await hastaAnotar(); await anotar(186, 112, 84); await a('sn', { dataset: { g: 'lista', k: 'dolor_pecho', v: 'si' } }); break;
      case 'sintoma': a('sintoma'); break;
      case 'listo': await hastaAnotar(); await anotar(122, 78, 60); break;
      case 'orto': await m.empezar('ortostatica'); u.enSesion = true; break;
      default: break;
    }
    u.ultimoHtml = null;
    if (!enEntreno) UI.renderEscena();
    window.scrollTo(0, 0);
    const letra = Number(q.get('letra'));
    if (letra > 100) setTimeout(() => agrandar(letra / 100), 150);
    setTimeout(() => { document.documentElement.setAttribute('data-presion-prueba', 'lista'); }, 300);
  }

  raiz.PresionPrueba = { token: 'prueba-local-presion', rpc, guion };
})(window);
