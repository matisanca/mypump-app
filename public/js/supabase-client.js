/* =============================================================
   supabase-client.js — Módulo de acceso a Supabase para MyPump
   Expone window.mypumpDB con todos los métodos necesarios.
   El cliente público nunca toca las tablas directamente:
   todo pasa por RPC functions que validan el token internamente.
   ============================================================= */

// Credenciales leídas de config.js (ignorado en git).
// Para local: copiar public/js/config.example.js → public/js/config.js y completar.
// Para Cloudflare Pages: inyectar MYPUMP_CONFIG vía build script o páginas worker.
const SUPABASE_URL      = window.MYPUMP_CONFIG?.SUPABASE_URL      || '';
const SUPABASE_ANON_KEY = window.MYPUMP_CONFIG?.SUPABASE_ANON_KEY || '';

const DEV_MODE = location.hostname === 'localhost' || location.hostname === '127.0.0.1';

let _client = null;

function getClient() {
  if (!_client) {
    _client = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  }
  return _client;
}

function logDev(...args) {
  if (DEV_MODE) console.warn('[mypumpDB]', ...args);
}

// Llamada RPC de solo lectura — devuelve data o null ante error
async function rpc(fn, params) {
  try {
    const { data, error } = await getClient().rpc(fn, params);
    if (error) { logDev(`RPC ${fn} error:`, error); return null; }
    return data;
  } catch (e) {
    logDev(`RPC ${fn} exception:`, e);
    return null;
  }
}

// Llamada RPC de escritura — devuelve {success, data, error}
async function rpcMutation(fn, params) {
  try {
    const { data, error } = await getClient().rpc(fn, params);
    if (error) {
      logDev(`RPC ${fn} error:`, error);
      return { success: false, data: null, error: error.message };
    }
    return { success: true, data, error: null };
  } catch (e) {
    logDev(`RPC ${fn} exception:`, e);
    return { success: false, data: null, error: e.message };
  }
}

window.mypumpDB = {
  init() {
    if (!SUPABASE_ANON_KEY) {
      console.error('[mypumpDB] SUPABASE_ANON_KEY no configurada. Ver README → Configurar credenciales.');
    }
    getClient();
  },

  // ─── LECTURA ──────────────────────────────────────────────

  // Devuelve {cliente_id, nombre, perfil} o null si token inválido.
  // Actualiza last_accessed_at en servidor.
  async getClienteInfo(token) {
    const rows = await rpc('mypump_get_cliente_info', { p_token: token });
    if (!rows || rows.length === 0) return null;
    return rows[0];
  },

  // Devuelve {id, version, estructura, semana_actual, fecha_inicio, fecha_fin} o null.
  async getRutinaActiva(token) {
    const rows = await rpc('mypump_get_rutina_activa', { p_token: token });
    if (!rows || rows.length === 0) return null;
    return rows[0];
  },

  // Devuelve {id, version, estructura} o null.
  async getDietaActiva(token) {
    const rows = await rpc('mypump_get_dieta_activa', { p_token: token });
    if (!rows || rows.length === 0) return null;
    return rows[0];
  },

  // Devuelve array de {registrado_en, peso_kg, reps_realizadas, rir_real, serie_numero}.
  async getHistoricoEjercicio(token, ejercicioId, limit = 10) {
    return await rpc('mypump_get_historico_ejercicio', {
      p_token: token,
      p_ejercicio_id: ejercicioId,
      p_limit: limit,
    });
  },

  // Devuelve array de {comida_id, opcion_elegida, completada} para la fecha dada.
  async getEleccionesDia(token, dietaId, fecha) {
    return await rpc('mypump_get_elecciones_dia', {
      p_token: token,
      p_dieta_id: dietaId,
      p_fecha: fecha,
    });
  },

  // ─── ESCRITURA ────────────────────────────────────────────

  // Inicia una sesión de entrenamiento. Devuelve {success, data: sesionId, error}.
  async iniciarSesion(token, diaId, semana) {
    return await rpcMutation('mypump_iniciar_sesion', {
      p_token: token,
      p_dia_id: diaId,
      p_semana: semana,
    });
  },

  // Registra un set. `datos` = {diaId, ejercicioId, ejercicioNombre, serie, peso, reps, rir, notas}.
  // Devuelve {success, data: registroId, error}.
  async registrarCarga(token, sesionId, datos) {
    return await rpcMutation('mypump_registrar_carga', {
      p_token:           token,
      p_sesion_id:       sesionId,
      p_dia_id:          datos.diaId,
      p_ejercicio_id:    datos.ejercicioId,
      p_ejercicio_nombre:datos.ejercicioNombre,
      p_serie:           datos.serie,
      p_peso:            datos.peso,
      p_reps:            datos.reps,
      p_rir:             datos.rir,
      p_notas:           datos.notas ?? null,
    });
  },

  // Finaliza la sesión. Devuelve {success, data: boolean, error}.
  async finalizarSesion(token, sesionId, notas = null) {
    return await rpcMutation('mypump_finalizar_sesion', {
      p_token:     token,
      p_sesion_id: sesionId,
      p_notas:     notas,
    });
  },

  // UPSERT de elección de opción de comida. Devuelve {success, data: boolean, error}.
  async elegirOpcionComida(token, dietaId, fecha, comidaId, opcion, completada = false) {
    return await rpcMutation('mypump_elegir_opcion_comida', {
      p_token:      token,
      p_dieta_id:   dietaId,
      p_fecha:      fecha,
      p_comida_id:  comidaId,
      p_opcion:     opcion,
      p_completada: completada,
    });
  },
};
