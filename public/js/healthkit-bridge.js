/* =============================================================
   healthkit-bridge.js — Puente Apple Health → backend (Vía B, Etapa D)

   SOLO corre dentro del wrapper nativo iOS (Capacitor). En la web es no-op
   total: window.MyPumpHealth.isAvailable() === false y no se muestra nada.

   Flujo del cliente: toca "Conectar Apple Health" UNA vez → diálogo de permisos
   de iOS → después sincroniza solo (al abrir/volver a foco; el background
   delivery real se configura en AppDelegate, ver docs/IOS_SETUP.md). Cada sync
   lee pasos / minutos activos / kcal activas de los últimos 7 días, agrega por
   día y los postea a mypump_ingest_salud(token, registros) — la MISMA RPC/tabla
   que todo lo demás.

   ⚠️ Los nombres de sample y la forma de la respuesta son los del plugin
   @perfood/capacitor-healthkit; VERIFICAR en device al integrar (marcado abajo).
   ============================================================= */
(function () {
  'use strict';

  const Cap = window.Capacitor;
  const isNative = !!(Cap && typeof Cap.isNativePlatform === 'function' && Cap.isNativePlatform());
  const HK = () => (window.Capacitor && window.Capacitor.Plugins && window.Capacitor.Plugins.CapacitorHealthkit) || null;

  // Permisos de lectura que pedimos (extensible a 'heart_rate','sleep_analysis','weight').
  const READ_PERMS = ['steps', 'activity', 'calories'];
  // sample HealthKit → tipo interno. Todos se agregan por SUMA diaria.
  // ⚠️ VERIFICAR nombres de sample contra el plugin instalado en device.
  const SAMPLES = [
    { sample: 'stepCount',          tipo: 'pasos' },
    { sample: 'appleExerciseTime',  tipo: 'actividad_min' },
    { sample: 'activeEnergyBurned', tipo: 'kcal_activas' },
  ];

  function ymd(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  async function requestPermission() {
    const hk = HK();
    if (!hk) return false;
    try {
      await hk.requestAuthorization({ all: [], read: READ_PERMS, write: [] });
      return true;
    } catch (e) {
      console.warn('[health] permiso denegado/err:', e);
      return false;
    }
  }

  // Lee un sample de los últimos 7 días y agrega por día → { 'YYYY-MM-DD': valor }.
  async function readDaily(sampleName) {
    const hk = HK();
    if (!hk) return {};
    const end = new Date();
    const start = new Date();
    start.setDate(start.getDate() - 7);
    let res;
    try {
      res = await hk.queryHKitSampleType({
        sampleName,
        startDate: start.toISOString(),
        endDate: end.toISOString(),
        limit: 0,
      });
    } catch (e) {
      console.warn('[health] query err', sampleName, e);
      return {};
    }
    const byDay = {};
    for (const s of (res && res.resultData) || []) {
      const raw = s.startDate || s.date || s.endDate;
      if (!raw) continue;
      const day = ymd(new Date(raw));
      byDay[day] = (byDay[day] || 0) + (Number(s.value) || 0);
    }
    return byDay;
  }

  // Lee todo, arma los registros y los postea a la RPC de ingesta.
  async function sync() {
    if (!isNative) return { ok: false, reason: 'no-native' };
    const token = window.TOKEN;
    if (!token || !window.mypumpDB || !window.mypumpDB.ingestSalud) return { ok: false, reason: 'no-token' };

    const registros = [];
    for (const { sample, tipo } of SAMPLES) {
      const byDay = await readDaily(sample);
      for (const fecha in byDay) {
        registros.push({ fecha, tipo, valor: Math.round(byDay[fecha]), fuente: 'apple_health' });
      }
    }
    if (!registros.length) return { ok: true, ingresados: 0 };

    const res = await window.mypumpDB.ingestSalud(token, registros);
    // Refrescar la card de Salud si estamos en Mi Día.
    if (res && res.success && typeof window.loadSalud === 'function') window.loadSalud();
    return { ok: !!(res && res.success), ingresados: res && res.data };
  }

  function isConnected() {
    return localStorage.getItem('mypump_health_connected') === '1';
  }

  async function connect() {
    if (!isNative) return false;
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

  window.MyPumpHealth = {
    isAvailable: () => isNative,
    isConnected,
    connect,
    sync,
  };
})();
