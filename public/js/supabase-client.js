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

// Llamada RPC de solo lectura — devuelve data o null ante error.
// Guarda el último error en window.mypumpDB._lastError para que el frontend
// pueda distinguir "token inválido" (null sin error) de "servicio caído" (error existente).
async function rpc(fn, params) {
  try {
    const { data, error } = await getClient().rpc(fn, params);
    if (error) {
      logDev(`RPC ${fn} error:`, error);
      if (window.mypumpDB) window.mypumpDB._lastError = error;
      return null;
    }
    if (window.mypumpDB) window.mypumpDB._lastError = null;
    return data;
  } catch (e) {
    logDev(`RPC ${fn} exception:`, e);
    if (window.mypumpDB) {
      window.mypumpDB._lastError = { code: 'NETWORK', message: e.message || String(e) };
    }
    return null;
  }
}

// Llamada RPC de escritura — devuelve {success, data, error}
async function rpcMutation(fn, params) {
  try {
    const { data, error } = await getClient().rpc(fn, params);
    if (error) {
      logDev(`RPC ${fn} error:`, error);
      if (window.mypumpDB) window.mypumpDB._lastError = error;
      return { success: false, data: null, error: error.message };
    }
    if (window.mypumpDB) window.mypumpDB._lastError = null;
    return { success: true, data, error: null };
  } catch (e) {
    logDev(`RPC ${fn} exception:`, e);
    if (window.mypumpDB) {
      window.mypumpDB._lastError = { code: 'NETWORK', message: e.message || String(e) };
    }
    return { success: false, data: null, error: e.message };
  }
}

window.mypumpDB = {
  _lastError: null,  // populated por rpc/rpcMutation — útil para distinguir
                     // "token inválido" (info===null && _lastError===null) de
                     // "servicio caído" (info===null && _lastError!==null).
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

  // Marca o actualiza el estado de un ejercicio en la sesión.
  // status: 'pendiente' | 'completo' | 'completo_sin_datos' | 'saltado'
  // Devuelve {success, data: uuid, error}.
  async marcarEjercicioEstado(token, sesionId, diaId, ejercicioId, seriesObjetivo, status, marcadoManualmente = false) {
    return await rpcMutation('mypump_marcar_ejercicio_estado', {
      p_token:               token,
      p_sesion_id:           sesionId,
      p_dia_id:              diaId,
      p_ejercicio_id:        ejercicioId,
      p_series_objetivo:     seriesObjetivo,
      p_status:              status,
      p_marcado_manualmente: marcadoManualmente,
    });
  },

  // Devuelve array de filas completas de mypump_ejercicios_estado para la sesión.
  // Campos clave: ejercicio_id, status, series_completadas, marcado_manualmente, marcado_en.
  async getEjerciciosEstado(token, sesionId) {
    return await rpc('mypump_get_ejercicios_estado', {
      p_token:     token,
      p_sesion_id: sesionId,
    });
  },

  // Avanza semana_actual en la rutina activa del cliente.
  // Si semanaDestino es null, avanza +1. Devuelve la nueva semana (integer) o null.
  async avanzarSemana(token, semanaDestino = null) {
    return await rpc('mypump_avanzar_semana', {
      p_token:          token,
      p_semana_destino: semanaDestino,
    });
  },

  // Devuelve array de registros de mypump_registros_carga para la sesión.
  // Campos clave: ejercicio_id, serie_numero, peso_kg, reps_realizadas, rir_real, notas.
  // Usado para restaurar los valores exactos de cada serie al recargar la página.
  async getRegistrosSesion(token, sesionId) {
    const rows = await rpc('mypump_get_registros_sesion', {
      p_token:     token,
      p_sesion_id: sesionId,
    });
    return { success: rows !== null, data: rows || [] };
  },

  // Devuelve la sesión más reciente para (cliente, dia, semana) o null.
  // Permite reconectar con una sesión existente sin depender de localStorage
  // (útil cuando el cliente cambia de dispositivo, borra cache, o el admin
  // retrocede manualmente la semana de la rutina).
  async getSesionDia(token, diaId, semana) {
    const rows = await rpc('mypump_get_sesion_dia', {
      p_token:  token,
      p_dia_id: diaId,
      p_semana: semana,
    });
    return rows && rows.length > 0 ? rows[0] : null;
  },

  // ─── MI DÍA / HÁBITOS ─────────────────────────────────────

  // Devuelve el registro de hábitos del día (o crea uno vacío). fecha = 'YYYY-MM-DD'.
  async getHabitosDia(token, fecha) {
    const rows = await rpc('mypump_get_habitos_dia', { p_token: token, p_fecha: fecha });
    return rows?.[0] || null;
  },

  // Actualiza un campo del día. valor debe ser string ('true','false','null', o número).
  // Devuelve {success, data: rowActualizada, error}.
  async setHabito(token, fecha, campo, valor) {
    return await rpcMutation('mypump_set_habito', {
      p_token: token,
      p_fecha: fecha,
      p_campo: campo,
      p_valor: valor === null ? 'null' : String(valor),
    });
  },

  // Devuelve {streak: integer, ultimo_dia_valido: DATE|null}.
  async getStreak(token) {
    const rows = await rpc('mypump_get_streak', { p_token: token });
    return rows?.[0] || { streak: 0, ultimo_dia_valido: null };
  },

  // Devuelve array de 30 filas (más reciente primero) con adherencia del cliente.
  async getAdherencia30d(token) {
    return await rpc('mypump_get_adherencia_30d', { p_token: token });
  },

};
