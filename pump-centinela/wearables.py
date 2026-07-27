#!/usr/bin/env python3
"""
wearables.py — trae datos de Oura/Whoop a mypump_salud_diaria (Vía A).

Corre en la Mac mini cada 3 horas (com.pump.wearables.plist).

POR QUÉ ACÁ Y NO EN CLOUDFLARE:
  Pages Functions NO tiene Cron Triggers (es exclusivo de Workers). La mini ya
  tiene launchd, la service key y el patrón de _sb_req del centinela — meter un
  Worker aparte solo para el scheduler sería una pieza más para mantener.

POR QUÉ POLLING Y NO WEBHOOKS:
  Los datos de recuperación se generan una vez por día, cuando el cliente se
  despierta. Con 100 clientes, un pull cada 3h llega holgado. Los webhooks se
  pueden sumar después como disparador — pero la escritura sigue pasando por
  acá, para tener UN solo camino donde debuggear.

  Uso:
    python3 wearables.py            # dry-run: dice qué haría, no escribe
    python3 wearables.py --write    # escribe de verdad
    python3 wearables.py --cliente <id> --write
"""
import base64, json, os, sys, urllib.request, urllib.parse, urllib.error
from datetime import date, datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BOT_ENV = os.path.expanduser("~/agentkit-coach/.env")
LOG     = os.path.expanduser("~/pump-centinela/wearables.log")
WRITE   = "--write" in sys.argv
SOLO    = None
if "--cliente" in sys.argv:
    try: SOLO = sys.argv[sys.argv.index("--cliente") + 1]
    except IndexError: pass

# Cuántos días para atrás traer la primera vez. El motor de recuperación no da
# score con menos de 14 días de historia, así que con 60 el cliente ve su
# número el mismo día que conecta en vez de esperar dos semanas.
BACKFILL_DIAS = 60
MAX_FALLOS    = 5     # a partir de acá se marca 'error' y se avisa


def _log(msg):
    ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] {msg}"
    print(line)
    try:
        with open(LOG, "a") as f: f.write(line + "\n")
    except Exception: pass


def load_env(p):
    e = {}
    try:
        for line in open(p):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("="); e[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return e

E = load_env(BOT_ENV)
SB_URL = (E.get("SUPABASE_URL") or "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")
SB_KEY = (E.get("SUPABASE_SERVICE_KEY") or E.get("SUPABASE_KEY") or "")


def _sb(path, body=None, method=None):
    req = urllib.request.Request(
        f"{SB_URL}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers={"apikey": SB_KEY, "Authorization": f"Bearer {SB_KEY}",
                 "Content-Type": "application/json"},
        method=method)
    with urllib.request.urlopen(req, timeout=45) as r:
        txt = r.read().decode()
        return json.loads(txt) if txt.strip() else None


# ── Cripto: el mismo formato que usa la Pages Function (AES-GCM, iv.ct en
#    base64url). La clave vive en el .env, nunca en Postgres. ────────────────
def _b64u_dec(s):
    s = s.replace('-', '+').replace('_', '/')
    return base64.b64decode(s + '=' * (-len(s) % 4))

def descifrar(blob):
    if not blob or '.' not in blob:
        return None
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:
        _log("FALTA la lib cryptography: pip install cryptography")
        return None
    key = base64.b64decode(E.get("OAUTH_ENC_KEY", ""))
    if len(key) != 32:
        _log("OAUTH_ENC_KEY ausente o con largo != 32 bytes")
        return None
    iv_b64, ct_b64 = blob.split('.', 1)
    try:
        return AESGCM(key).decrypt(_b64u_dec(iv_b64), _b64u_dec(ct_b64), None).decode()
    except Exception as e:
        _log(f"no pude descifrar: {e}")
        return None


def _http_json(url, headers=None, data=None, method=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=45) as r:
        return json.loads(r.read().decode() or "{}")


# ══════════════════ PROVEEDORES ══════════════════
# Agregar uno = una entrada acá con su token_url y su mapear().

def _dia(s):
    """'2026-07-27T03:12:00+00:00' o '2026-07-27' -> date."""
    if not s: return None
    try: return date.fromisoformat(str(s)[:10])
    except ValueError: return None


def mapear_oura(payloads):
    """Oura API v2 -> registros de mypump_salud_diaria.

    average_hrv de daily_sleep es rMSSD NOCTURNO: la métrica correcta medida
    en el contexto correcto. Es exactamente lo que Apple Health no da, y la
    razón por la que esta integración existe.
    """
    regs = []
    for s in (payloads.get("sleep") or {}).get("data", []) or []:
        f = _dia(s.get("day"))
        if not f: continue
        fs = str(f)
        if s.get("average_hrv"):
            regs.append({"fecha": fs, "tipo": "hrv_ms", "valor": s["average_hrv"],
                         "fuente": "oura",
                         "detalle": {"metrica": "rmssd", "ventana": "nocturna"}})
        if s.get("lowest_heart_rate"):
            regs.append({"fecha": fs, "tipo": "fc_reposo", "valor": s["lowest_heart_rate"], "fuente": "oura"})
        if s.get("total_sleep_duration"):
            regs.append({"fecha": fs, "tipo": "sueno_min",
                         "valor": round(s["total_sleep_duration"] / 60), "fuente": "oura"})
        for k, tipo in (("deep_sleep_duration", "sueno_profundo_min"),
                        ("rem_sleep_duration", "sueno_rem_min"),
                        ("light_sleep_duration", "sueno_ligero_min")):
            if s.get(k):
                regs.append({"fecha": fs, "tipo": tipo, "valor": round(s[k] / 60), "fuente": "oura"})
        if s.get("efficiency"):
            regs.append({"fecha": fs, "tipo": "sueno_eficiencia_pct", "valor": s["efficiency"], "fuente": "oura"})
        if s.get("average_breath"):
            regs.append({"fecha": fs, "tipo": "respiracion_rpm",
                         "valor": round(float(s["average_breath"]), 1), "fuente": "oura"})
        # Punto medio del sueño: insumo de la regularidad (su desvío en 7 días).
        bt, wt = s.get("bedtime_start"), s.get("bedtime_end")
        if bt and wt:
            try:
                d1 = datetime.fromisoformat(bt.replace("Z", "+00:00"))
                d2 = datetime.fromisoformat(wt.replace("Z", "+00:00"))
                mid = d1 + (d2 - d1) / 2
                regs.append({"fecha": fs, "tipo": "sueno_medio_min",
                             "valor": mid.hour * 60 + mid.minute, "fuente": "oura"})
            except Exception: pass

    # El readiness score de Oura NO entra al motor: es una caja negra ajena y
    # mezclarlo sería importar sus decisiones de diseño. Se adjunta al HRV del
    # mismo día como referencia, para poder comparar contra el motor propio
    # durante las primeras semanas y recalibrar los pesos con datos reales.
    scores = {}
    for d in (payloads.get("readiness") or {}).get("data", []) or []:
        f = _dia(d.get("day"))
        if f and d.get("score") is not None:
            scores[str(f)] = d["score"]
    if scores:
        for r in regs:
            if r["tipo"] == "hrv_ms" and r["fecha"] in scores:
                r.setdefault("detalle", {})["proveedor_score"] = scores[r["fecha"]]

    for a in (payloads.get("activity") or {}).get("data", []) or []:
        f = _dia(a.get("day"))
        if not f: continue
        if a.get("steps"):
            regs.append({"fecha": str(f), "tipo": "pasos", "valor": a["steps"], "fuente": "oura"})
        if a.get("active_calories"):
            regs.append({"fecha": str(f), "tipo": "kcal_activas", "valor": a["active_calories"], "fuente": "oura"})
    return regs


def traer_oura(access, desde, hasta):
    h = {"Authorization": f"Bearer {access}"}
    q = urllib.parse.urlencode({"start_date": str(desde), "end_date": str(hasta)})
    out = {}
    for clave, ep in (("sleep", "daily_sleep"), ("readiness", "daily_readiness"),
                      ("activity", "daily_activity")):
        try:
            out[clave] = _http_json(f"https://api.ouraring.com/v2/usercollection/{ep}?{q}", headers=h)
        except urllib.error.HTTPError as e:
            if e.code == 401: raise
            _log(f"  oura {ep}: HTTP {e.code}")
        except Exception as e:
            _log(f"  oura {ep}: {e}")
    # `sleep` detallado trae average_hrv por sesión; daily_sleep trae el resumen.
    try:
        out["sleep"] = _http_json(f"https://api.ouraring.com/v2/usercollection/sleep?{q}", headers=h)
    except Exception:
        pass
    return out


def mapear_whoop(payloads):
    """WHOOP API v2 -> registros. score.hrv_rmssd_milli viene en SEGUNDOS en
    algunas versiones del payload; se normaliza a ms."""
    regs = []
    for r in (payloads.get("recovery") or {}).get("records", []) or []:
        f = _dia(r.get("created_at"))
        sc = r.get("score") or {}
        if not f or not sc: continue
        fs = str(f)
        hrv = sc.get("hrv_rmssd_milli")
        if hrv:
            hrv = float(hrv)
            if hrv < 1:      # vino en segundos
                hrv *= 1000
            regs.append({"fecha": fs, "tipo": "hrv_ms", "valor": round(hrv, 1), "fuente": "whoop",
                         "detalle": {"metrica": "rmssd", "ventana": "nocturna",
                                     "proveedor_score": sc.get("recovery_score")}})
        if sc.get("resting_heart_rate"):
            regs.append({"fecha": fs, "tipo": "fc_reposo", "valor": sc["resting_heart_rate"], "fuente": "whoop"})
        if sc.get("spo2_percentage"):
            regs.append({"fecha": fs, "tipo": "spo2_pct",
                         "valor": round(float(sc["spo2_percentage"]), 1), "fuente": "whoop"})
        if sc.get("skin_temp_celsius"):
            regs.append({"fecha": fs, "tipo": "temp_muneca_c",
                         "valor": round(float(sc["skin_temp_celsius"]), 1), "fuente": "whoop"})
    for s in (payloads.get("sleep") or {}).get("records", []) or []:
        f = _dia(s.get("end"))
        sc = (s.get("score") or {}).get("stage_summary") or {}
        if not f or not sc: continue
        fs = str(f)
        tot = (sc.get("total_light_sleep_time_milli", 0) + sc.get("total_slow_wave_sleep_time_milli", 0)
               + sc.get("total_rem_sleep_time_milli", 0))
        if tot:
            regs.append({"fecha": fs, "tipo": "sueno_min", "valor": round(tot / 60000), "fuente": "whoop"})
        for k, tipo in (("total_slow_wave_sleep_time_milli", "sueno_profundo_min"),
                        ("total_rem_sleep_time_milli", "sueno_rem_min"),
                        ("total_light_sleep_time_milli", "sueno_ligero_min")):
            if sc.get(k):
                regs.append({"fecha": fs, "tipo": tipo, "valor": round(sc[k] / 60000), "fuente": "whoop"})
        rr = (s.get("score") or {}).get("respiratory_rate")
        if rr:
            regs.append({"fecha": fs, "tipo": "respiracion_rpm", "valor": round(float(rr), 1), "fuente": "whoop"})
    return regs


def traer_whoop(access, desde, hasta):
    h = {"Authorization": f"Bearer {access}"}
    q = urllib.parse.urlencode({"start": f"{desde}T00:00:00.000Z", "end": f"{hasta}T23:59:59.999Z", "limit": 25})
    out = {}
    for clave, ep in (("recovery", "recovery"), ("sleep", "activity/sleep")):
        try:
            out[clave] = _http_json(f"https://api.prod.whoop.com/developer/v2/{ep}?{q}", headers=h)
        except urllib.error.HTTPError as e:
            if e.code == 401: raise
            _log(f"  whoop {ep}: HTTP {e.code}")
        except Exception as e:
            _log(f"  whoop {ep}: {e}")
    return out


PROVEEDORES = {
    "oura":  {"token_url": "https://api.ouraring.com/oauth/token",
              "id_env": "OURA_CLIENT_ID", "secret_env": "OURA_CLIENT_SECRET",
              "traer": traer_oura, "mapear": mapear_oura},
    "whoop": {"token_url": "https://api.prod.whoop.com/oauth/oauth2/token",
              "id_env": "WHOOP_CLIENT_ID", "secret_env": "WHOOP_CLIENT_SECRET",
              "traer": traer_whoop, "mapear": mapear_whoop},
}


def refrescar(prov, refresh_token):
    """Canjea el refresh_token por uno nuevo. Devuelve (access, refresh, expira)."""
    p = PROVEEDORES[prov]
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token", "refresh_token": refresh_token,
        "client_id": E.get(p["id_env"], ""), "client_secret": E.get(p["secret_env"], ""),
    }).encode()
    tok = _http_json(p["token_url"], headers={"Content-Type": "application/x-www-form-urlencoded"},
                     data=data, method="POST")
    exp = None
    if tok.get("expires_in"):
        exp = (datetime.now(timezone.utc) + timedelta(seconds=int(tok["expires_in"]))).isoformat()
    return tok.get("access_token"), tok.get("refresh_token") or refresh_token, exp


def main():
    if not SB_KEY:
        _log("sin SUPABASE_SERVICE_KEY en el .env — no puedo seguir"); return 1
    faltan = [p for p in PROVEEDORES if not E.get(PROVEEDORES[p]["id_env"])]
    if len(faltan) == len(PROVEEDORES):
        _log("ningun proveedor configurado (faltan CLIENT_ID/SECRET en el .env) — nada que hacer")
        return 0

    filtro = f"&cliente_id=eq.{urllib.parse.quote(SOLO)}" if SOLO else ""
    conexiones = _sb("/rest/v1/mypump_wearable_conexiones?estado=in.(conectada,expirada)"
                     f"&select=*{filtro}&order=ultimo_pull_en.nullsfirst") or []
    if not conexiones:
        _log("no hay conexiones activas"); return 0

    _log(f"{len(conexiones)} conexion(es){'  [DRY-RUN: no escribe]' if not WRITE else ''}")
    hoy = date.today()

    for c in conexiones:
        cid, prov = c["cliente_id"], c["proveedor"]
        if prov not in PROVEEDORES or not E.get(PROVEEDORES[prov]["id_env"]):
            _log(f"{cid}/{prov}: proveedor no configurado, salteo"); continue

        # Watermark: desde el último día traído (con 2 de solape por si el
        # proveedor recalcula la noche anterior). Sin watermark, cada corrida
        # re-bajaría 60 días para nada.
        desde = hoy - timedelta(days=BACKFILL_DIAS)
        if c.get("ultimo_pull_hasta"):
            try: desde = max(desde, date.fromisoformat(c["ultimo_pull_hasta"]) - timedelta(days=2))
            except ValueError: pass

        access = descifrar(c.get("access_token_enc"))
        refresh = descifrar(c.get("refresh_token_enc"))
        venc = c.get("token_expira_en")
        vencido = True
        if venc:
            try: vencido = datetime.fromisoformat(venc.replace("Z", "+00:00")) <= datetime.now(timezone.utc) + timedelta(minutes=5)
            except ValueError: pass

        try:
            if (vencido or not access) and refresh:
                access, refresh, venc = refrescar(prov, refresh)
                if WRITE and access:
                    # El token nuevo se cifra del lado del servidor web; acá se
                    # guarda solo la fecha de vencimiento para no duplicar la
                    # cripto. El access dura lo suficiente para esta corrida.
                    _sb(f"/rest/v1/mypump_wearable_conexiones?id=eq.{c['id']}",
                        {"token_expira_en": venc, "updated_at": datetime.now(timezone.utc).isoformat()},
                        method="PATCH")
            if not access:
                raise RuntimeError("sin access token")

            payloads = PROVEEDORES[prov]["traer"](access, desde, hoy)
            regs = PROVEEDORES[prov]["mapear"](payloads)
            regs = [r for r in regs if r.get("valor") is not None]

            _log(f"{cid}/{prov}: {len(regs)} registros desde {desde}")
            if regs and WRITE:
                n = _sb("/rest/v1/rpc/mypump_ingest_salud_service",
                        {"p_cliente_id": cid, "p_registros": regs})
                _sb(f"/rest/v1/mypump_wearable_conexiones?id=eq.{c['id']}",
                    {"ultimo_pull_en": datetime.now(timezone.utc).isoformat(),
                     "ultimo_pull_hasta": str(hoy), "estado": "conectada",
                     "ultimo_error": None, "intentos_fallidos": 0}, method="PATCH")
                _log(f"  ingresados: {n}")

        except urllib.error.HTTPError as e:
            fallos = int(c.get("intentos_fallidos") or 0) + 1
            estado = "expirada" if e.code == 401 else ("error" if fallos >= MAX_FALLOS else c["estado"])
            _log(f"{cid}/{prov}: HTTP {e.code} (fallo {fallos}) -> {estado}")
            if WRITE:
                _sb(f"/rest/v1/mypump_wearable_conexiones?id=eq.{c['id']}",
                    {"intentos_fallidos": fallos, "ultimo_error": f"HTTP {e.code}", "estado": estado},
                    method="PATCH")
        except Exception as e:
            fallos = int(c.get("intentos_fallidos") or 0) + 1
            _log(f"{cid}/{prov}: {e} (fallo {fallos})")
            if WRITE:
                _sb(f"/rest/v1/mypump_wearable_conexiones?id=eq.{c['id']}",
                    {"intentos_fallidos": fallos, "ultimo_error": str(e)[:200],
                     "estado": "error" if fallos >= MAX_FALLOS else c["estado"]}, method="PATCH")
    return 0


if __name__ == "__main__":
    sys.exit(main())
