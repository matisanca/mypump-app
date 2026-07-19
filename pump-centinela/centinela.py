#!/usr/bin/env python3
"""Pump Centinela — monitoreo semanal de clientes MyPump (independiente del bot).

Corre los domingos (LaunchAgent com.pump.centinela) y le manda a Mati por
WhatsApp (Meta Cloud API, mismo camino que heartbeat/brief):

  1) ALERTAS: solo los clientes con algo mal — sin entrenar, rendimiento
     estancado/cayendo segun su objetivo, o peso fuera del rango — con
     numeros concretos y un borrador de mensaje listo para mandarle.
  2) MINI-FICHAS: 2-3 lineas por cliente activo para que Mati personalice
     su pedido de check dominical sin abrir nada.

Datos: RPC mypump_get_metricas_coach (migracion 034) con service key.
Senal primaria de adherencia = semanas con tonelaje > 0 (muchos clientes
entrenan sin apretar "Finalizar", asi que sesiones_finalizadas subestima).

Seguridad: por defecto NO envia (dry-run imprime). Para enviar: --send
Config: lee el .env del bot (~/agentkit-coach/.env).
"""
import os, sys, json, re, subprocess, urllib.request, urllib.error
from datetime import datetime, timedelta, date

BOT_ENV = os.path.expanduser("~/agentkit-coach/.env")
STATE   = os.path.expanduser("~/pump-centinela/state.json")
DRY     = "--send" not in sys.argv
FORCE   = "--force" in sys.argv
SEMANAS = 6

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

def supabase_key():
    return (E.get("SUPABASE_SERVICE_KEY") or E.get("SUPABASE_KEY")
            or E.get("SUPABASE_ANON_KEY") or "")

def supabase_url():
    return (E.get("SUPABASE_URL") or "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")

def fetch_metricas():
    k = supabase_key()
    req = urllib.request.Request(
        f"{supabase_url()}/rest/v1/rpc/mypump_get_metricas_coach",
        data=json.dumps({"p_semanas": SEMANAS}).encode(),
        headers={"apikey": k, "Authorization": f"Bearer {k}",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

# ── WhatsApp (Meta Cloud API — mismo camino que heartbeat.py) ──
def send_whatsapp(text):
    tok = E.get("META_ACCESS_TOKEN"); pnid = E.get("META_PHONE_NUMBER_ID"); to = E.get("COACH_PHONE_NUMBER")
    if not (tok and pnid and to):
        print("  [meta] faltan credenciales"); return False
    if DRY:
        print(f"\n[DRY-RUN] WhatsApp -> {to}:\n{text}\n" + "-" * 60); return True
    payload = json.dumps({"messaging_product": "whatsapp", "recipient_type": "individual",
                          "to": to, "type": "text", "text": {"body": text}}).encode()
    try:
        req = urllib.request.Request(f"https://graph.facebook.com/v21.0/{pnid}/messages", data=payload,
                                     headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            print(f"  [meta] HTTP {r.status}"); return r.status == 200
    except Exception as ex:
        print(f"  [meta] fail: {ex}"); return False

def send_multi(text, limit=3500):
    """Trocea en mensajes de <= limit chars cortando por bloque de cliente."""
    if len(text) <= limit:
        return send_whatsapp(text)
    partes, actual = [], ""
    for bloque in text.split("\n\n"):
        if len(actual) + len(bloque) + 2 > limit and actual:
            partes.append(actual); actual = bloque
        else:
            actual = (actual + "\n\n" + bloque) if actual else bloque
    if actual: partes.append(actual)
    ok = True
    for i, p in enumerate(partes):
        ok = send_whatsapp((f"(parte {i+1}/{len(partes)})\n" if len(partes) > 1 else "") + p) and ok
    return ok

# ── Analisis ──
def norm_objetivo(raw):
    s = (raw or "").lower()
    if re.search(r"defici|défici|defini|cut|grasa", s): return "definicion"
    if re.search(r"manten|recomposi", s): return "mantenimiento"
    if re.search(r"superavit|superávit|volumen|hipertrofia|masa|bulk", s): return "volumen"
    return "volumen"

def rango_peso(objetivo, perfil):
    """Rango objetivo semanal en gramos (min, max)."""
    if objetivo == "definicion": return (-1000, -400)
    if objetivo == "mantenimiento": return (-200, 200)
    return (350, 500) if perfil == "farma" else (75, 250)

def lunes(d):
    return d - timedelta(days=d.weekday())

def semana_map(arr, key):
    """[{semana, <key>}] -> dict fecha_lunes(str) -> valor"""
    return {x["semana"]: x[key] for x in (arr or [])}

def analizar(c, hoy):
    """Devuelve (alertas:[str], ficha:str|None)."""
    obj = norm_objetivo(c.get("objetivo"))
    perfil = c.get("perfil") or "natural"
    nombre = c.get("nombre") or c.get("cliente_id")

    ton = semana_map(c.get("tonelaje_por_semana"), "kg")
    ses = semana_map(c.get("sesiones_por_semana"), "sesiones")
    peso = semana_map(c.get("peso_semanal"), "kg")

    # Semanas ISO: actual (parcial) y las 4 completas previas
    w0 = lunes(hoy)                                   # semana en curso
    ws = [str(w0 - timedelta(weeks=i)) for i in range(0, 6)]  # w0, w-1, ... w-5
    t = [float(ton.get(w, 0) or 0) for w in ws]       # t[0]=actual parcial

    nunca_uso = not any(t) and not peso
    if nunca_uso:
        return [], None   # se lista aparte como "sin actividad en la app"

    alertas = []

    # 1) Adherencia (tonelaje como senal primaria)
    if t[1] == 0 and t[2] == 0 and t[0] == 0:
        alertas.append("SIN ENTRENAR hace 2+ semanas (tonelaje 0)")
    elif t[1] == 0 and t[0] == 0:
        alertas.append("sin entrenos registrados la semana pasada ni esta")

    # 2) Rendimiento (necesita 4 semanas completas con datos)
    completas = [x for x in t[1:5]]
    if all(x > 0 for x in completas):
        reciente = (completas[0] + completas[1]) / 2
        previo   = (completas[2] + completas[3]) / 2
        var = (reciente - previo) / previo * 100 if previo else 0
        if obj == "volumen":
            if var < -5:
                alertas.append(f"rendimiento CAYENDO en volumen ({var:+.0f}% tonelaje ult. 2 sem)")
            elif -5 <= var <= 2:
                alertas.append(f"rendimiento estancado en volumen ({var:+.0f}% tonelaje) — revisar kcal/descanso/progresion")
        elif obj == "definicion" and var < -20:
            alertas.append(f"caida fuerte de rendimiento en deficit ({var:+.0f}% tonelaje ult. 2 sem)")

    # 3) Peso vs rango (media semanal, 2 semanas consecutivas fuera)
    pw = [peso.get(str(w0 - timedelta(weeks=i))) for i in range(0, 3)]
    if pw[0] is not None and pw[1] is not None and pw[2] is not None:
        lo, hi = rango_peso(obj, perfil)
        d1 = (float(pw[0]) - float(pw[1])) * 1000
        d2 = (float(pw[1]) - float(pw[2])) * 1000
        fuera1 = d1 < lo or d1 > hi
        fuera2 = d2 < lo or d2 > hi
        if fuera1 and fuera2:
            dir_ = "por debajo" if d1 < lo else "por encima"
            alertas.append(f"peso {dir_} del rango 2 semanas seguidas ({d1:+.0f} g/sem, objetivo {lo:+d} a {hi:+d})")

    # Mini-ficha (para la ronda del domingo)
    partes = []
    sem_act = [w for w in ws[0:2] if float(ton.get(w, 0) or 0) > 0]
    n_ses = sum(int(ses.get(w, 0) or 0) for w in ws[0:2])
    t_ult = t[1] if t[1] else t[0]
    partes.append(f"entreno: {'activo' if sem_act else 'PARADO'}"
                  + (f" ({int(t_ult):,} kg tonelaje/sem)".replace(",", ".") if t_ult else "")
                  + (f", {n_ses} dias cerrados" if n_ses else ""))
    if pw[0] is not None and pw[1] is not None:
        d1 = (float(pw[0]) - float(pw[1])) * 1000
        lo, hi = rango_peso(obj, perfil)
        estado = "en rango" if lo <= d1 <= hi else ("bajo el rango" if d1 < lo else "sobre el rango")
        partes.append(f"peso: media {float(pw[0]):.1f} kg ({d1:+.0f} g/sem, {estado})")
    else:
        ult = c.get("ultimo_peso_fecha")
        if not ult:
            partes.append("peso: sin datos en la app todavia")
        elif (hoy - date.fromisoformat(ult)).days > 10:
            partes.append(f"peso: sin registrar hace {(hoy - date.fromisoformat(ult)).days} dias")
    # Check semanal de la app (energia/descanso/hambre/adherencia + nota)
    chk = c.get("ultimo_checkin")
    if chk and any(chk.get(k) for k in ("energia", "descanso", "hambre", "adherencia")):
        def _v(k): return chk.get(k) if chk.get(k) is not None else "-"
        linea = f"se siente: energia {_v('energia')}/5, descanso {_v('descanso')}/5, hambre {_v('hambre')}/5, adherencia {_v('adherencia')}/5"
        if chk.get("nota"):
            linea += f' - "{str(chk["nota"])[:90]}"'
        partes.append(linea)
    ficha = f"*{nombre}* (sem {c.get('semana_actual')}, {obj} {perfil})\n  " + "\n  ".join(partes)
    return alertas, ficha

# ── Borradores con claude -p (best-effort, fallback a template) ──
def borradores_claude(alertados):
    try:
        env = dict(os.environ)
        env["PATH"] = env.get("PATH", "") + ":/opt/homebrew/bin:/usr/local/bin:" + \
            ":".join(os.path.expanduser(f"~/.nvm/versions/node/{d}/bin")
                     for d in (os.listdir(os.path.expanduser("~/.nvm/versions/node"))
                               if os.path.isdir(os.path.expanduser("~/.nvm/versions/node")) else []))
        resumen = "\n".join(f"- {a['nombre']}: {'; '.join(a['alertas'])}" for a in alertados)
        prompt = (
            "Sos Mati Sancari, coach de Pump Team (Argentina, tono cercano, tuteo rioplatense, "
            "directo pero calido, sin emojis excesivos, sin sonar a IA). Para cada cliente de la "
            "lista escribi UN mensaje corto de WhatsApp (2-4 lineas) para retomar contacto segun "
            "su problema. No menciones 'la app detecto' ni 'el sistema': hablale como si vos lo "
            "hubieras notado. No uses signos de apertura. Devolve SOLO un JSON valido "
            '{"nombre": "mensaje"} sin texto extra.\n\nClientes:\n' + resumen)
        out = subprocess.run(["claude", "-p", prompt], capture_output=True, text=True,
                             timeout=120, env=env)
        m = re.search(r"\{.*\}", out.stdout, re.S)
        return json.loads(m.group(0)) if m else {}
    except Exception as ex:
        print(f"  [claude] fallback a template: {ex}")
        return {}

def borrador_template(a):
    n = a["nombre"].split()[0]
    if any("SIN ENTRENAR" in x or "sin entrenos" in x for x in a["alertas"]):
        return (f"{n}! Como venis? Vi que hace unos dias no registras entrenos. "
                "Todo bien? Si se te complico la semana contame y lo acomodamos, "
                "no pasa nada. Lo importante es retomar esta semana.")
    if any("estancado" in x or "CAYENDO" in x or "caida" in x for x in a["alertas"]):
        return (f"{n}! Estuve mirando tus entrenos y hace un par de semanas venimos "
                "planchados con las cargas. Como te venis sintiendo? Descanso, comida, "
                "energia en el gym? Contame y ajustamos lo que haga falta.")
    return (f"{n}! Como va? Estuve revisando tu semana y hay un par de cosas que "
            "quiero charlar con vos. Tenes un rato hoy o manana?")

# ── Main ──
def main():
    hoy = date.today()
    st = {}
    try: st = json.load(open(STATE))
    except Exception: pass
    if not FORCE and st.get("last_run") == str(hoy):
        print("ya corrio hoy (usar --force para repetir)"); return

    data = fetch_metricas()
    data = [c for c in data if not str(c.get("cliente_id", "")).startswith("test")
            and "test" not in (c.get("nombre") or "").lower()]
    print(f"clientes activos: {len(data)}")

    alertados, fichas, sin_uso = [], [], []
    for c in data:
        alertas, ficha = analizar(c, hoy)
        if alertas:
            alertados.append({"nombre": c.get("nombre"), "alertas": alertas})
        if ficha:
            fichas.append((bool(alertas), ficha))
        elif ficha is None and not alertas:
            sin_uso.append(c.get("nombre"))

    # Mensaje 1: alertas + borradores
    if alertados:
        drafts = borradores_claude(alertados)
        lineas = ["🚨 *Centinela MyPump — clientes que necesitan tu atencion*"]
        for a in alertados:
            lineas.append(f"\n🔴 *{a['nombre']}*\n· " + "\n· ".join(a["alertas"]))
            msg = drafts.get(a["nombre"]) or borrador_template(a)
            lineas.append(f"📋 Borrador:\n_{msg}_")
        send_multi("\n".join(lineas))
    else:
        print("sin alertas esta semana")

    # Mensaje 2: mini-fichas para la ronda
    if fichas:
        fichas.sort(key=lambda x: not x[0])   # alertados primero
        cuerpo = ["📇 *Mini-fichas para tu ronda del domingo*"] + [f for _, f in fichas]
        if sin_uso:
            cuerpo.append("\n🕳 Sin actividad en la app: " + ", ".join(sorted(sin_uso)))
        send_multi("\n\n".join(cuerpo))

    st["last_run"] = str(hoy)
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    try: json.dump(st, open(STATE, "w"))
    except Exception as ex: print("state save fail:", ex)

if __name__ == "__main__":
    main()
