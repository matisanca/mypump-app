/* =============================================================
   healthkit-bridge.js — Puente Apple Health → backend (Vía B, Etapa D)

   SOLO corre dentro del wrapper nativo iOS (Capacitor). En la web es no-op
   total: window.MyPumpHealth.isAvailable() === false y no se muestra nada.

   Usa el plugin @capgo/capacitor-health (registrado como "Health"). Flujo:
   el cliente toca "Conectar Apple Health" UNA vez → diálogo de permisos iOS →
   después sincroniza solo (al abrir/volver a foco; el background delivery real
   se configura nativo, ver docs/IOS_SETUP.md). Cada sync agrega por DÍA los
   pasos / minutos de ejercicio / kcal activas de los últimos 7 días y los
   postea a mypump_ingest_salud(token, registros) — la MISMA RPC/tabla que todo.
   ============================================================= */
(function () {
  'use strict';

  const Cap = window.Capacitor;
  const isNative = !!(Cap && typeof Cap.isNativePlatform === 'function' && Cap.isNativePlatform());
  const HEALTH = () => (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.Health) || null;

  // dataType del plugin → tipo interno de mypump_salud_diaria.
  // agg: cómo se agrega el bucket diario ('sum' para volúmenes, 'average' para
  // métricas puntuales como HRV/FC reposo).
  const MAP = [
    { dataType: 'steps',                tipo: 'pasos',         agg: 'sum' },
    { dataType: 'exerciseTime',         tipo: 'actividad_min', agg: 'sum' },
    { dataType: 'calories',             tipo: 'kcal_activas',  agg: 'sum' },   // energía activa
    { dataType: 'sleep',                tipo: 'sueno_min',     agg: 'sum' },   // minutos dormidos
    { dataType: 'heartRateVariability', tipo: 'hrv_ms',        agg: 'average' },
    { dataType: 'restingHeartRate',     tipo: 'fc_reposo',     agg: 'average' },
  ];

  function ymd(iso) {
    const d = new Date(iso);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  // ¿HealthKit disponible en este device? (async, chequea el plugin nativo)
  async function hkAvailable() {
    if (!isNative) return false;
    const h = HEALTH();
    if (!h) return false;
    try { const r = await h.isAvailable(); return !!(r && r.available); }
    catch { return false; }
  }

  async function requestPermission() {
    const h = HEALTH();
    if (!h) return false;
    try { await h.requestAuthorization({ read: MAP.map(m => m.dataType), write: [] }); return true; }
    catch (e) { console.warn('[health] permiso denegado/err:', e); return false; }
  }

  // Lee agregado por día (sum) de cada tipo y postea a la RPC de ingesta.
  async function sync() {
    if (!isNative) return { ok: false, reason: 'no-native' };
    const token = window.TOKEN;
    if (!token || !window.mypumpDB || !window.mypumpDB.ingestSalud) return { ok: false, reason: 'no-token' };
    const h = HEALTH();
    if (!h) return { ok: false, reason: 'no-plugin' };

    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - 7);
    const registros = [];

    for (const { dataType, tipo, agg } of MAP) {
      try {
        const res = await h.queryAggregated({
          dataType,
          startDate: start.toISOString(),
          endDate: end.toISOString(),
          bucket: 'day',
          aggregation: agg || 'sum',
        });
        for (const s of (res && res.samples) || []) {
          const val = Math.round(Number(s.value) || 0);
          if (val <= 0) continue;
          registros.push({ fecha: ymd(s.startDate), tipo, valor: val, fuente: 'apple_health' });
        }
      } catch (e) {
        console.warn('[health] queryAggregated err', dataType, e);
      }
    }

    if (!registros.length) return { ok: true, ingresados: 0 };
    const r = await window.mypumpDB.ingestSalud(token, registros);
    if (r && r.success && typeof window.loadSalud === 'function') window.loadSalud();
    return { ok: !!(r && r.success), ingresados: r && r.data };
  }

  function isConnected() {
    return localStorage.getItem('mypump_health_connected') === '1';
  }

  async function connect() {
    if (!(await hkAvailable())) return false;
    const ok = await requestPermission();
    if (!ok) return false;
    localStorage.setItem('mypump_health_connected', '1');
    await sync();
    return true;
  }

  // Fallback del background delivery: sincronizar al abrir y al volver a foco.
  if (isNative) {
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden && isConnected()) sync();
    });
    window.addEventListener('load', () => { if (isConnected()) sync(); });
  }

  // isAvailable() para la UI = "¿estamos en la app nativa?" (sync, barato). El
  // chequeo real del plugin (hkAvailable) se hace dentro de connect().
  window.MyPumpHealth = {
    isAvailable: () => isNative,
    isConnected,
    connect,
    sync,
  };
})();
