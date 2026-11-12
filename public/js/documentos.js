/* =============================================================
   documentos.js — «Documentos» (contrato y consentimiento): textos y reglas puras.

   La firma es propia (firma.mypumpteam.com). La web no firma: muestra el estado
   que devuelve `mypump_contrato_get(p_token)` y abre la página del servicio en
   una pestaña nueva. Gemelo de TextosDocumentos (Swift y Kotlin): los textos son
   los mismos. Nada de pagos ni precios: solo el estado y abrir el documento.

   Tolerante como el resto: un documento con un tipo o un estado desconocido (o
   sin id) se descarta sin tirar los demás; cualquier otra forma es «ninguno».
   ============================================================= */
(function (raiz) {
  'use strict';

  const FIRMA_URL_PRODUCCION = 'https://firma.mypumpteam.com';

  const T = {
    titulo: 'Documentos',
    entradaMisDatos: 'Documentos',
    pie: 'Tu contrato y tu consentimiento. Se abren en el navegador para leerlos, firmarlos o descargarlos.',
    avisoContrato: 'Tenés el contrato pendiente de firma',
    avisoContratoDetalle: 'Tocá para leerlo y firmarlo.',
    errorAbrir: 'No pudimos abrir el documento. Probá de nuevo en un rato o usá el enlace que te llegó por correo.',
    leerYFirmar: 'Leer y firmar',
    verDocumento: 'Ver documento',
    pendiente: 'Pendiente',
    abriendo: 'Abriendo…',
  };

  const TIPOS = ['servicio_ar', 'servicio_ext', 'consentimiento_ar'];
  const ESTADOS = ['pendiente', 'firmado', 'revocado'];

  function texto(v) {
    if (typeof v === 'string') return v;
    if (typeof v === 'number' && isFinite(v)) return String(v);
    return null;
  }

  /** Un documento de la respuesta, o null si no sirve. */
  function documentoDe(o) {
    if (!o || typeof o !== 'object' || Array.isArray(o)) return null;
    const id = texto(o.id);
    const tipo = texto(o.tipo);
    const estado = texto(o.estado);
    if (!id || TIPOS.indexOf(tipo) === -1 || ESTADOS.indexOf(estado) === -1) return null;
    return {
      id, tipo, estado,
      titulo: texto(o.titulo),
      firmado_en: texto(o.firmado_en),
      revocado_en: texto(o.revocado_en),
    };
  }

  /** La respuesta de `mypump_contrato_get` (o null si falló): la lista de documentos que se entienden. */
  function decodificar(resp) {
    if (!resp || typeof resp !== 'object' || !Array.isArray(resp.documentos)) return [];
    return resp.documentos.map(documentoDe).filter(Boolean);
  }

  function esContrato(tipo) { return tipo === 'servicio_ar' || tipo === 'servicio_ext'; }

  function nombre(tipo) {
    return esContrato(tipo) ? 'Contrato de coaching' : 'Consentimiento de atención médica';
  }

  /** Un timestamptz del servidor: con T o con espacio, con microsegundos, con la zona como `+00`. */
  function instante(iso) {
    if (typeof iso !== 'string' || !iso) return null;
    let s = iso.replace(' ', 'T').replace(/\.(\d{1,3})\d*/, '.$1');
    if (/[+-]\d\d$/.test(s)) s += ':00';
    const ms = Date.parse(s);
    return isNaN(ms) ? null : new Date(ms);
  }

  /** "dd/mm/aaaa" en la hora del navegador (o en `zona`, para las pruebas). null si no se entiende. */
  function fecha(iso, zona) {
    const d = instante(iso);
    if (!d) return null;
    const p = {};
    new Intl.DateTimeFormat('en-GB', { timeZone: zona, day: '2-digit', month: '2-digit', year: 'numeric' })
      .formatToParts(d).forEach(x => { p[x.type] = x.value; });
    return `${p.day}/${p.month}/${p.year}`;
  }

  /** «Pendiente de firma», «Firmado el 10/11/2026», «Revocado el 10/11/2026». Sin fecha legible, el estado solo. */
  function estado(doc, zona) {
    if (doc.estado === 'pendiente') return 'Pendiente de firma';
    const palabra = doc.estado === 'firmado' ? 'Firmado' : 'Revocado';
    const f = fecha(doc.estado === 'firmado' ? doc.firmado_en : doc.revocado_en, zona);
    return f ? `${palabra} el ${f}` : palabra;
  }

  function boton(est) { return est === 'pendiente' ? T.leerYFirmar : T.verDocumento; }

  /** El aviso de Entreno: solo con un contrato de coaching pendiente (el consentimiento no lo prende). */
  function hayContratoPendiente(docs) {
    return (docs || []).some(d => d && esContrato(d.tipo) && d.estado === 'pendiente');
  }

  /** El enlace de ese documento en la respuesta del servicio, solo si es https del propio servicio de firma. */
  function enlaceDe(resp, id, servicio) {
    if (!resp || typeof resp !== 'object' || !Array.isArray(resp.documentos)) return null;
    const d = resp.documentos.find(x => x && typeof x === 'object' && texto(x.id) === id);
    return d ? enlaceSeguro(texto(d.url), servicio) : null;
  }

  function enlaceSeguro(url, servicio) {
    if (!url) return null;
    let u, s;
    try { u = new URL(url); s = new URL(servicio || FIRMA_URL_PRODUCCION); } catch (_) { return null; }
    if (u.protocol !== 'https:' || u.hostname.toLowerCase() !== s.hostname.toLowerCase()) return null;
    return u.href;
  }

  const API = {
    T, FIRMA_URL_PRODUCCION, decodificar, documentoDe, esContrato, nombre, fecha, estado, boton, hayContratoPendiente,
    enlaceDe, enlaceSeguro,
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.MyPumpDocumentos = API;
})(typeof window !== 'undefined' ? window : globalThis);
