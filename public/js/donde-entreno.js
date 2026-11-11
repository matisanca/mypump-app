/* =============================================================
   donde-entreno.js — «Mi gimnasio y mi técnica» (simplificar, OK de Mati del 11/11; va con la palanca `web_230`):
   Mi gimnasio (con «Entreno en casa» adentro) y Mi técnica en una sola pantalla, con un renglón grande al final de
   Entreno. Cada bloque va con su palanca de siempre (`gimnasio_fotos`, `casa`, `tecnica_video`): acá no hay palancas
   nuevas. Solo lógica pura y textos; los mismos que DondeEntreno de iPhone y Android
   (nativa-evidencia/mi-salud/DECISIONES.md, iOS simplificar 4).
   ============================================================= */
(function (raiz) {
  'use strict';

  const T = {
    tituloAmbos: 'Mi gimnasio y mi técnica',
    tituloGimnasio: 'Mi gimnasio',
    tituloTecnica: 'Mi técnica',
    bajadaAmbos: 'Las fotos de tu gimnasio y los videos de tu técnica',
    bajadaGimnasio: 'Las fotos de tu gimnasio o lo que tenés en casa',
    bajadaTecnica: 'Tus videos y lo que te respondió Mati',
    verRespuesta: 'Ver lo que te respondió Mati',
    vacio: 'Por ahora no hay nada para mostrar acá.',
    volver: 'Entreno',
    tuGimnasio: 'Tu gimnasio',
    misVideos: 'Mandar un video o ver todos',
  };

  /* El título del renglón y de la pantalla, según lo que haya. null: no hay ninguno de los dos. */
  function titulo(gimnasio, tecnica) {
    if (gimnasio && tecnica) return T.tituloAmbos;
    if (gimnasio) return T.tituloGimnasio;
    if (tecnica) return T.tituloTecnica;
    return null;
  }
  function bajada(gimnasio, tecnica) {
    if (gimnasio && tecnica) return T.bajadaAmbos;
    if (gimnasio) return T.bajadaGimnasio;
    if (tecnica) return T.bajadaTecnica;
    return null;
  }

  /* Cuántos días una respuesta de técnica sigue «nueva» en el renglón de Entreno. */
  const DIAS_RESPUESTA_RECIENTE = 7;
  const instante = (s) => { if (typeof s !== 'string' || !s) return null; const d = new Date(s); return isNaN(d.getTime()) ? null : d; };

  /* La respuesta de Mati más nueva, publicada en los últimos 7 días. Sin fecha legible no cuenta (la lista la sigue
     mostrando). `envios`: los de TecnicaCola ({ id, estado, devolucion, publicadoEn }). */
  function respuestaReciente(envios, ahora) {
    const t = ahora instanceof Date && !isNaN(ahora.getTime()) ? ahora.getTime() : Date.now();
    let mejor = null, mejorEn = -Infinity;
    for (const e of Array.isArray(envios) ? envios : []) {
      if (!e || e.estado !== 'publicado' || !e.devolucion) continue;
      const d = instante(e.publicadoEn);
      if (!d) continue;
      const en = d.getTime();
      if (t - en >= DIAS_RESPUESTA_RECIENTE * 86400000) continue;
      if (en > mejorEn) { mejor = e; mejorEn = en; }
    }
    return mejor;
  }

  const API = { T, titulo, bajada, respuestaReciente, DIAS_RESPUESTA_RECIENTE };
  if (typeof module !== 'undefined' && module.exports) module.exports = API;
  else raiz.DondeEntreno = API;
})(typeof window !== 'undefined' ? window : globalThis);
