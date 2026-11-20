/* =============================================================
   revision-desde.js — desde cuándo se pide la revisión semanal (19/11, OK de Mati).

   `mypump_cliente_prefs.revision_desde` lo escribe AUTOMATIZAR ENTREGAS: el lunes
   siguiente a la publicación del plan. La app lo lee con mypump_get_revision_desde
   (token → la fecha efectiva, la misma que usa el servidor para frenar el push de
   «fotos de la semana»). Antes de esa fecha no hay aviso de revisión: ni el badge,
   ni el banner, ni «todavía no subiste tus fotos». Sin fecha, o una que no se
   entiende, todo como siempre. DATE '9999-12-31' es «la entrega todavía no se hizo»:
   nunca habilitada y sin aviso que agendar.

   Sin red, sin pantalla y sin almacenamiento. Gemelo de SemanaRevision.habilitada /
   avisoDesde de iOS y Android. Vectores comunes: scripts/vectores-app/revision_desde.json
   (copia exacta de apps/shared/vectores/revision_desde.json), que corre
   scripts/test-revision-desde.mjs.
   ============================================================= */
(function (raiz) {
  'use strict';

  const FECHA = /^([0-9]{4})-([0-9]{2})-([0-9]{2})/;
  // DATE '9999-12-31' (mypump_revision_desde_efectiva): la entrega todavía no se hizo.
  const ANIO_SIN_ARRANQUE = 9999;

  /** Días desde 1970-01-01 de "YYYY-MM-DD" (como DiaCalendario.numero de las apps), o null. */
  function numero(f) {
    const m = typeof f === 'string' ? FECHA.exec(f) : null;
    if (!m) return null;
    const a = +m[1], mes = +m[2], dia = +m[3];
    if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
    return Math.round(Date.UTC(a, mes - 1, dia) / 86400000);
  }

  /** La fecha de arranque que vale: "YYYY-MM-DD" o null (sin fecha o ilegible: como siempre). */
  function normalizar(v) {
    if (typeof v !== 'string') return null;
    const m = FECHA.exec(v.trim());
    return m && numero(m[0]) != null ? m[0] : null;
  }

  /** La revisión ya se pide: `hoy` (fecha local del teléfono) en o después de `desde`. Sin fecha, sí. */
  function habilitada(hoy, desde) {
    const d = normalizar(desde);
    if (d == null) return true;
    const h = numero(hoy), n = numero(d);
    if (h == null) return true;
    return h >= n;
  }

  /** «La entrega todavía no se hizo» (9999-12-31): no hay aviso que agendar. */
  function sinArranque(desde) {
    const d = normalizar(desde);
    return d != null && +d.slice(0, 4) >= ANIO_SIN_ARRANQUE;
  }

  const API = { numero, normalizar, habilitada, sinArranque };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.RevisionDesde = API;
})(typeof window !== 'undefined' ? window : globalThis);
