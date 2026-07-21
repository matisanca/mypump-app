#!/usr/bin/env python3
"""Pump Centinela v2 — la ronda del domingo inteligente (N10).

Corre los domingos 18:00 (LaunchAgent com.pump.centinela) y arma TODA la
ronda semanal leyendo primero los checks de la app. Le manda a Mati por
WhatsApp (Meta Cloud API), en orden:

  1) ALERTAS: clientes con problemas objetivos que NO mandaron check.
  2) MENSAJE GENERAL de difusion — solo para los que NO completaron el
     check — + mini-fichas de esos clientes.
  3) PERSONALIZADOS: por cada cliente que SI mando su check, dos mensajes:
     "Nombre" (separador para copiar) y el mensaje listo para reenviar,
     con feedback relativo a su planilla + pedido de fotos + una pregunta
     concreta si algo va mal (redactado con claude -p, fallback template).
  4) AJUSTES SUGERIDOS (solo Mati): para los que van mal, cambios concretos
     de dieta/entrenamiento/suplementos leyendo SU dieta y rutina reales.
     JAMAS sugiere farmacos: eso es decision medica de Mati.

Datos: mypump_get_metricas_coach + mypump_checkin_semanal + mypump_dietas
+ mypump_rutinas (service key, .env del bot). El mensaje general del bot
core (scheduler _seguimiento_semanal) queda REEMPLAZADO por este script.

Seguridad: por defecto NO envia (dry-run imprime). Para enviar: --send
"""
import os, sys, json, re, subprocess, urllib.request, urllib.error, urllib.parse
from datetime import datetime, timedelta, date
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analisis as AN

BOT_ENV = os.path.expanduser("~/agentkit-coach/.env")
STATE   = os.path.expanduser("~/pump-centinela/state.json")
DRY     = "--send" not in sys.argv
FORCE   = "--force" in sys.argv
NO_DB   = "--no-db" in sys.argv   # no persistir en mypump_analisis_semanal (solo pruebas)
# Dos momentos distintos: el DOMINGO se PIDE (nadie mando el check todavia) y
# el JUEVES se ANALIZA (ya llegaron). Antes todo corria el domingo y el
# analisis llegaba siempre vacio.
MODO    = "analisis" if "--analisis" in sys.argv else ("pedido" if "--pedido" in sys.argv else "auto")
SEMANAS = 12
SEM_CHECKS = 8      # serie de checks para baseline/tendencia

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

def _sb_req(path, body=None):
    k = supabase_key()
    req = urllib.request.Request(
        f"{supabase_url()}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        headers={"apikey": k, "Authorization": f"Bearer {k}",
                 "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())

def fetch_metricas():
    return _sb_req("/rest/v1/rpc/mypump_get_metricas_coach", {"p_semanas": SEMANAS})

def fetch_checks(lunes_actual, lunes_previo):
    """Serie larga (8 semanas): sin historia no hay baseline ni tendencia, y
    todo el motor de analisis se cae a umbrales absolutos."""
    desde = str(date.fromisoformat(lunes_actual) - timedelta(weeks=SEM_CHECKS))
    return _sb_req(f"/rest/v1/mypump_checkin_semanal?semana_lunes=gte.{desde}"
                   f"&select=*&order=semana_lunes.asc")

def fetch_fotos_semana(lunes_actual):
    try:
        return _sb_req(f"/rest/v1/mypump_fotos_progreso?semana_lunes=eq.{lunes_actual}&select=cliente_id,pose")
    except Exception:
        return []

def fetch_dieta(cliente_id):
    rows = _sb_req(f"/rest/v1/mypump_dietas?cliente_id=eq.{cliente_id}&estado=eq.activa&select=estructura&limit=1")
    return rows[0]["estructura"] if rows else None

def fetch_rutina(cliente_id):
    rows = _sb_req(f"/rest/v1/mypump_rutinas?cliente_id=eq.{cliente_id}&estado=eq.activa&select=estructura,semana_actual&limit=1")
    return rows[0] if rows else None

def fetch_suplementos(cliente_id):
    try:
        rows = _sb_req(f"/rest/v1/mypump_suplementos?cliente_id=eq.{cliente_id}&select=items,resumen,revisado,confianza&limit=1")
        if not rows: return None
        r = rows[0]
        items = r.get("items") or []
        if not items and not r.get("resumen"): return None
        stack = ", ".join(i.get("nombre", "") + (f" {i['dosis']}" if i.get("dosis") else "") for i in items) or r.get("resumen")
        return {"stack": stack, "confirmado": bool(r.get("revisado")), "confianza": r.get("confianza")}
    except Exception:
        return None

# -- WhatsApp (Meta Cloud API, mismo camino que heartbeat.py) --

def fetch_progresion(cliente_id):
    """Serie de cargas por ejercicio (mejor set por sesion). La RPC ya existe
    pero el centinela nunca la usaba: aca sacamos ESTANCAMIENTO de fuerza y el
    RIR real, senales de AJUSTE DE RUTINA que hoy se perdian."""
    try:
        rows = _sb_req("/rest/v1/rpc/mypump_get_progresion_cargas",
                       {"p_cliente_id": cliente_id, "p_semanas": SEMANAS})
        return rows if isinstance(rows, list) else []
    except Exception:
        return []

def senales_carga(prog):
    """De la serie de cargas: ejercicios en RETROCESO de fuerza y el RIR medio.
    OJO: un ejercicio 'plano' NO es senal — la carga se congela a proposito en
    la fase de acumulacion (misma carga, +1 serie). Solo marcamos CAIDA real
    (>=3% de e1RM en 4+ semanas), que es lo que amerita mirar. Requiere 4 puntos
    para no confundir ruido semana a semana con una tendencia."""
    if not prog:
        return {}
    por_ej = {}
    for r in prog:
        eid = r.get("ejercicio_id")
        if not eid:
            continue
        d = por_ej.setdefault(eid, {"nombre": r.get("ejercicio"), "pts": []})
        e1 = r.get("e1rm")
        d["pts"].append({"sem": r.get("semana"),
                         "e1rm": float(e1) if e1 not in (None, "") else None,
                         "rir": r.get("rir_real")})
    retroceso, rirs = [], []
    for d in por_ej.values():
        for x in d["pts"]:
            if x["rir"] is not None:
                try: rirs.append(float(x["rir"]))
                except Exception: pass
        pts = sorted([x for x in d["pts"] if x["e1rm"] is not None], key=lambda x: (x["sem"] or 0))
        if len(pts) < 4:
            continue
        rec = max(x["e1rm"] for x in pts[-2:])       # mejor de las 2 recientes
        prev = max(x["e1rm"] for x in pts[-4:-2])     # mejor de las 2 anteriores
        if prev and rec < prev * 0.97:                # cayo 3%+
            retroceso.append({"ej": d["nombre"], "caida_pct": round((rec / prev - 1) * 100)})
    out = {}
    if retroceso:
        retroceso.sort(key=lambda x: x["caida_pct"])   # peor primero
        out["cargas_en_retroceso"] = retroceso[:4]
    if rirs:
        out["rir_medio"] = round(sum(rirs) / len(rirs), 1)
    return out

def persist_analisis(cid, semana_lunes, balde, motivos, banderas, senales,
                     mensaje_cliente, sugerencia_coach):
    """Upsert a mypump_analisis_semanal. La escritura a DB es INDEPENDIENTE del
    envio de WhatsApp: --no-db la desactiva, pero --dry (que silencia WhatsApp)
    igual persiste, para poder ver el panel sin spamear."""
    if NO_DB:
        print(f"[no-db] {cid} -> {balde}")
        return
    try:
        _sb_req("/rest/v1/rpc/mypump_upsert_analisis", {
            "p_cliente_id": cid, "p_semana_lunes": semana_lunes, "p_balde": balde,
            "p_motivos": motivos or [], "p_banderas": banderas or [],
            "p_senales": senales or {}, "p_mensaje_cliente": mensaje_cliente,
            "p_sugerencia_coach": sugerencia_coach})
    except Exception as e:
        print(f"[persist fail] {cid}: {e}")

def _senales_dict(veredicto, ctx, carga):
    perfiles = {}
    for m, pf in (veredicto.get("perfiles") or {}).items():
        perfiles[m] = {"valor": pf.get("valor"), "baseline": pf.get("baseline"),
                       "estado": pf.get("estado")}
    return {
        "perfiles": perfiles,
        "cruces": [{"clave": k, "desc": d} for k, d, _a, _sv in (veredicto.get("cruces") or [])],
        "var_e1rm": ctx.get("var_e1rm"),
        "adh_entreno": ctx.get("adh_entreno"),
        "delta_peso_g": ctx.get("delta_peso_g"),
        "peso_en_rango": ctx.get("peso_en_rango"),
        "carga": carga or {},
    }

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

# -- claude -p (best-effort; via LaunchAgent tiene keychain, via ssh no) --
def claude_call(prompt, timeout=180):
    env = dict(os.environ)
    nvm = os.path.expanduser("~/.nvm/versions/node")
    extra = ":".join(os.path.join(nvm, d, "bin") for d in (os.listdir(nvm) if os.path.isdir(nvm) else []))
    env["PATH"] = env.get("PATH", "") + ":/opt/homebrew/bin:/usr/local/bin:" + extra
    out = subprocess.run(["claude", "-p", prompt], capture_output=True, text=True,
                         timeout=timeout, env=env)
    return out.stdout

def claude_json(prompt, timeout=180):
    try:
        out = claude_call(prompt, timeout)
        m = re.search(r"\{.*\}", out, re.S)
        return json.loads(m.group(0)) if m else None
    except Exception as ex:
        print(f"  [claude] fallback: {ex}")
        return None

def claude_text(prompt, timeout=120):
    try:
        t = claude_call(prompt, timeout).strip()
        # sacar cercos de codigo o comillas envolventes si los hay
        t = re.sub(r"^```[a-z]*\n?|\n?```$", "", t).strip().strip('"').strip()
        return t if len(t) > 40 else None
    except Exception as ex:
        print(f"  [claude] fallback: {ex}")
        return None

TONO = ("Escribi como Mati Sancari, coach de Pump Team (argentino, tuteo rioplatense, cercano, "
        "directo, humano). Reglas duras: singular siempre (te, vos, contame, mandame); NUNCA "
        "signos de apertura ni interrogacion ni exclamacion de apertura; sin punto al final; sin "
        "guion largo; nada de cierres motivacionales tipo 'a darle' o 'espero tus novedades'; "
        "frases cortas e irregulares, que no suene a IA ni a checklist. "
        "Como mucho UN emoji, y solo al final (ej: un apreton de manos). Nunca emojis en el medio.\n"
        "Asi escribe el de verdad, calca este registro (no el contenido, el REGISTRO):\n"
        "  Buenas! cómo va el lunes? toca revisión!\n"
        "  Mañana pesate apenas te levantes en ayunas y cargá en la app, en la parte de revisión, "
        "tu peso actual y las fotos de frente, perfil y espaldas.\n"
        "  Además podés contarme cómo estuvo tu semana en cuanto a energía, descanso, hambre y "
        "adherencia con 4 toques, y obvio cualquier cosa que quieras agregar me podés contar por "
        "acá o por la app donde también tenés un espacio para eso\n"
        "Escribi CON acentos y eñes, como en el ejemplo.")

# -- Analisis --
def norm_objetivo(raw):
    s = (raw or "").lower()
    if re.search(r"defici|défici|defini|cut|grasa", s): return "definicion"
    if re.search(r"manten|recomposi", s): return "mantenimiento"
    if re.search(r"superavit|superávit|volumen|hipertrofia|masa|bulk", s): return "volumen"
    return "volumen"

def rango_peso(objetivo, perfil):
    if objetivo == "definicion": return (-1000, -400)
    if objetivo == "mantenimiento": return (-200, 200)
    return (350, 500) if perfil == "farma" else (75, 250)

def lunes(d):
    return d - timedelta(days=d.weekday())

def semana_map(arr, key):
    return {x["semana"]: x[key] for x in (arr or [])}

def analizar(c, hoy):
    """(alertas, ficha_corta, contexto) — ficha SIN la linea 'se siente'."""
    obj = norm_objetivo(c.get("objetivo"))
    perfil = c.get("perfil") or "natural"
    nombre = c.get("nombre") or c.get("cliente_id")

    ton = semana_map(c.get("tonelaje_por_semana"), "kg")
    ses = semana_map(c.get("sesiones_por_semana"), "sesiones")
    peso = semana_map(c.get("peso_semanal"), "kg")

    w0 = lunes(hoy)
    ws = [str(w0 - timedelta(weeks=i)) for i in range(0, 6)]
    t = [float(ton.get(w, 0) or 0) for w in ws]

    nunca_uso = not any(t) and not peso
    ctx = {"obj": obj, "perfil": perfil, "t": t, "nunca_uso": nunca_uso}
    if nunca_uso:
        return [], None, ctx

    alertas = []
    if t[1] == 0 and t[2] == 0 and t[0] == 0:
        alertas.append("SIN ENTRENAR hace 2+ semanas (tonelaje 0)")
    elif t[1] == 0 and t[0] == 0:
        alertas.append("sin entrenos registrados la semana pasada ni esta")

    completas = [x for x in t[1:5]]
    if all(x > 0 for x in completas):
        reciente = (completas[0] + completas[1]) / 2
        previo   = (completas[2] + completas[3]) / 2
        var = (reciente - previo) / previo * 100 if previo else 0
        ctx["var_rendimiento"] = round(var)
        if obj == "volumen":
            if var < -5: alertas.append(f"rendimiento CAYENDO en volumen ({var:+.0f}% tonelaje ult. 2 sem)")
            elif -5 <= var <= 2: alertas.append(f"rendimiento estancado en volumen ({var:+.0f}% tonelaje)")
        elif obj == "definicion" and var < -20:
            alertas.append(f"caida fuerte de rendimiento en deficit ({var:+.0f}% tonelaje)")

    # -- Señales que estaban disponibles y NO se usaban --
    # (a) Adherencia OBJETIVA de entreno: sesiones cerradas / dias del plan.
    dias_plan = c.get("dias_plan") or 0
    if dias_plan:
        ses_ult = int(ses.get(ws[1], 0) or 0) or int(ses.get(ws[0], 0) or 0)
        ctx["adh_entreno"] = round(ses_ult / dias_plan, 2)
    # (b) Fuerza real por e1RM: el tonelaje se contamina con cambios de volumen
    #     del programa; el e1RM se mueve con la fuerza de verdad.
    e1 = {}
    for x in (c.get("e1rm_top") or []):
        e1.setdefault(x.get("ejercicio"), {})[str(x.get("semana"))] = x.get("e1rm")
    variaciones = []
    for _ej, porsem in e1.items():
        sems = sorted(porsem)
        if len(sems) >= 2:
            ini, fin = porsem[sems[0]], porsem[sems[-1]]
            if ini: variaciones.append((float(fin) - float(ini)) / float(ini) * 100)
    if variaciones:
        ctx["var_e1rm"] = round(sum(variaciones) / len(variaciones), 1)

    ctx["sin_entrenar"] = bool(t[0] == 0 and t[1] == 0 and t[2] == 0)

    pw = [peso.get(str(w0 - timedelta(weeks=i))) for i in range(0, 3)]
    if pw[0] is not None and pw[1] is not None:
        lo, hi = rango_peso(obj, perfil)
        d1 = (float(pw[0]) - float(pw[1])) * 1000
        ctx["delta_peso_g"] = round(d1)
        ctx["media_peso"] = round(float(pw[0]), 1)
        ctx["peso_en_rango"] = lo <= d1 <= hi
        if pw[2] is not None:
            d2 = (float(pw[1]) - float(pw[2])) * 1000
            if (d1 < lo or d1 > hi) and (d2 < lo or d2 > hi):
                ctx["peso_fuera_2sem"] = True
                dir_ = "por debajo" if d1 < lo else "por encima"
                alertas.append(f"peso {dir_} del rango 2 semanas seguidas ({d1:+.0f} g/sem, objetivo {lo:+d} a {hi:+d})")

    partes = []
    t_ult = t[1] if t[1] else t[0]
    activo = bool(t[0] or t[1])
    n_ses = sum(int(ses.get(w, 0) or 0) for w in ws[0:2])
    partes.append(f"entreno: {'activo' if activo else 'PARADO'}"
                  + (f" ({int(t_ult):,} kg tonelaje/sem)".replace(",", ".") if t_ult else "")
                  + (f", {n_ses} dias cerrados" if n_ses else ""))
    if pw[0] is not None and pw[1] is not None:
        lo, hi = rango_peso(obj, perfil)
        d1 = (float(pw[0]) - float(pw[1])) * 1000
        estado = "en rango" if lo <= d1 <= hi else ("bajo el rango" if d1 < lo else "sobre el rango")
        partes.append(f"peso: media {float(pw[0]):.1f} kg ({d1:+.0f} g/sem, {estado})")
    else:
        ult = c.get("ultimo_peso_fecha")
        if not ult:
            partes.append("peso: sin datos en la app todavia")
        elif (hoy - date.fromisoformat(ult)).days > 10:
            partes.append(f"peso: sin registrar hace {(hoy - date.fromisoformat(ult)).days} dias")
    ctx["activo"] = activo
    ficha = f"*{nombre}* (sem {c.get('semana_actual')}, {obj} {perfil})\n  " + "\n  ".join(partes)
    return alertas, ficha, ctx

def va_mal(alertas, chk, obj):
    if alertas: return True
    if not chk: return False
    if (chk.get("adherencia") or 5) <= 3: return True
    if (chk.get("energia") or 5) <= 2: return True
    if (chk.get("descanso") or 5) <= 2: return True
    if obj == "definicion" and (chk.get("hambre") or 1) >= 4: return True
    return False

# -- Resumenes compactos de dieta y rutina (para el prompt de ajustes) --
def resumen_dieta(cliente_id):
    try:
        est = fetch_dieta(cliente_id)
        if not est: return "sin dieta publicada"
        mt = est.get("macros_target") or {}
        lineas = [f"target: {mt.get('kcal','?')} kcal, {mt.get('prot','?')}P/{mt.get('carb','?')}C/{mt.get('fat','?')}G"]
        for com in (est.get("comidas") or [])[:6]:
            op = (com.get("options") or [{}])[0]
            foods = ", ".join(f.get("name", "?") for f in (op.get("foods") or [])[:4])
            kcal = sum(f.get("kcal", 0) for f in (op.get("foods") or []))
            lineas.append(f"{com.get('name','?')} (~{kcal} kcal): {foods}")
        return "; ".join(lineas)
    except Exception as ex:
        return f"(dieta no legible: {ex})"

def resumen_rutina(cliente_id):
    try:
        row = fetch_rutina(cliente_id)
        if not row: return "sin rutina publicada"
        est = row["estructura"]
        dias = est.get("dias") or []
        partes = [f"semana {row.get('semana_actual')}, split {est.get('split') or est.get('perfil',{}).get('split','?')}, {len(dias)} dias"]
        for d in dias:
            ejs = []
            for b in (d.get("bloques") or []):
                for e in (b.get("ejercicios") or []):
                    if e.get("tipo") == "compuesto":
                        ejs.append(e.get("nombre", "?"))
            partes.append(f"{d.get('nombre','?')}: {', '.join(ejs[:5]) or 'accesorios'}")
        return "; ".join(partes)
    except Exception as ex:
        return f"(rutina no legible: {ex})"

# -- Generadores --
ANGULOS = [
    "Arranca preguntando en general como venis, natural, antes de pedir nada.",
    "Arranca comentando que se termina una semana mas y toca hacer el balance juntos.",
    "Arranca preguntando puntualmente como venis con el descanso y la energia esta semana.",
    "Arranca preguntando como venis con la constancia en los entrenos.",
    "Arranca reconociendo que el finde a veces cuesta y preguntando como lo llevaste.",
    "Arranca preguntando como venis con el hambre y la adherencia a la dieta.",
    "Arranca directo y al grano, como quien ya tiene confianza y escribe rapido.",
]

FALLBACK_GENERAL = (
    "Buenas! Cómo va el finde? Mañana toca revisión. "
    "Pesate apenas te levantes en ayunas y cargá en la app, en Revisión, tu peso y las fotos de "
    "frente, perfil y espalda. "
    "Ahí mismo contame cómo estuvo tu semana en energía, descanso, hambre y adherencia, son 4 "
    "toques, y cualquier cosa que quieras agregar me la podés contar por acá o en la app 🤝"
)

# El mensaje DEBE mandar el peso + el check a la app. Si el modelo se desvia
# (pide el peso por WhatsApp o ni menciona la app), se usa el template fijo.
def _general_valido(m):
    ml = (m or "").lower()
    if len(ml) < 60: return False
    if "app" not in ml: return False
    if re.search(r"mandame (me )?(tu |el )?peso|pas(a|a)me (tu |el )?peso|envi(a|a)me (tu |el )?peso", ml):
        return False
    # Las fotos ahora van EN LA APP: no puede pedirlas por WhatsApp.
    if re.search(r"mandame (por aca |por aqui )?(las |tus )?fotos|pas(a|a)me (las |tus )?fotos", ml):
        return False
    # Requisito duro de Mati: el mensaje invita a contar algo mas.
    if not re.search(r"cont(a|a)me|cont(a|a)r|escribime|charlamos|mandame un audio", ml):
        return False
    # Y tiene que decir DONDE: "Revisión" es la pestaña, si no quedan dando
    # vueltas por la app. La clase [oó] es obligatoria: mas abajo se hace
    # .lower() pero NO se normalizan acentos, y al modelo se le pide que
    # escriba con tildes — sin eso el validador rechaza todo y siempre cae al
    # fallback.
    if not re.search(r"revisi[oó]n", ml):
        return False
    return True

def interpretar_notas(metricas, chk_actual, chk_series):
    """Extrae banderas/temas de las notas libres. EXTRACCION, no diagnostico:
    la decision la toman las reglas. Valida que la `cita` sea textual para
    descartar alucinaciones (mismo espiritu que _general_valido)."""
    items = []
    for c in metricas:
        cid = c["cliente_id"]; nombre = c.get("nombre") or cid
        chk = chk_actual.get(cid)
        if not chk or not (chk.get("nota") or "").strip(): continue
        previas = [r.get("nota") for r in chk_series.get(cid, [])[:-1] if r.get("nota")][-2:]
        items.append({"nombre": nombre, "nota": chk["nota"], "notas_previas": previas})
    if not items: return {}

    prompt = (
        "Sos un asistente que EXTRAE informacion de notas que dejaron clientes de un coach. "
        "NO diagnostiques ni recomiendes: solo extrae. Para cada cliente devolve:\n"
        '{"<nombre>": {"banderas": [...], "temas": [...], "sentimiento": "positivo|neutro|negativo", '
        '"repite_tema": true|false, "cita": "fragmento TEXTUAL de la nota"}}\n'
        "banderas posibles (solo si aparecen claras): lesion, enfermedad, viaje, evento, estres, desmotivacion.\n"
        "repite_tema = true si el tema principal ya aparecia en notas_previas.\n"
        "cita DEBE ser un fragmento copiado literal de la nota.\n"
        "Responde SOLO el JSON.\n\nDATOS:\n" + json.dumps(items, ensure_ascii=False)
    )
    res = claude_json(prompt) or {}
    out = {}
    for it in items:
        r = res.get(it["nombre"])
        if not isinstance(r, dict): continue
        cita = (r.get("cita") or "").strip()
        if cita and cita.lower() not in it["nota"].lower():
            print(f"  [notas] cita no textual en {it['nombre']}, descarto extraccion")
            continue
        out[it["nombre"]] = r
    # los que no salieron por IA quedan con el fallback por regex del motor
    return out

def gen_general():
    sem = date.today().isocalendar()[1]
    ang = ANGULOS[sem % len(ANGULOS)]
    prompt = (
        f"{TONO}\n\nEscribi el mensaje de WhatsApp del domingo a la tarde avisando que manana "
        f"lunes toca la revision semanal. Se manda por broadcast: cada uno lo recibe como mensaje "
        f"privado e individual.\nANGULO DE ESTA SEMANA: {ang}\n"
        "Todo se carga en la APP (MyPump), en la pestaña REVISIÓN. Nombrala: que sepan donde ir.\n"
        "Que quede claro, en la MENOR cantidad de palabras posible:\n"
        "(1) que manana se pese apenas se levante, en ayunas, y cargue el PESO en la app. "
        "El peso NUNCA por WhatsApp.\n"
        "(2) que suba ahi mismo las FOTOS de frente, perfil y espalda. Tampoco por WhatsApp. "
        "El peso y las fotos van juntos en la misma frase, no los separes en dos pedidos.\n"
        "(3) el CHECK: que cuente como estuvo su semana en energia, descanso, hambre y adherencia, "
        "'con 4 toques'. Planteado como una invitacion a contarte, no como una tarea.\n"
        "(4) cerra diciendo que cualquier otra cosa que quiera agregar te la puede contar por "
        "WhatsApp o en el espacio libre de la app. Redactalo distinto cada semana.\n"
        "MAXIMO 3 oraciones. Cuanto mas corto mejor: ya saben usar la app, no expliques de mas "
        "ni aclares para que sirve cada cosa. Sin listas ni numeracion. Nada de 'Buen dia' (es de "
        "tarde). Devolve SOLO el mensaje, sin explicaciones."
    )
    msg = claude_text(prompt) or ""
    msg = re.sub(r"\s*(Espero\s+(tus|tu|mis)\b[^.]*|Quedo\s+(atento|a\s+la\s+espera)\b[^.]*|A\s+darle\b[^.]*)\.?\s*$",
                 "", msg, flags=re.IGNORECASE).strip()
    if not _general_valido(msg):
        print("  [general] la IA se desvio (no manda a la app), uso template fijo")
        msg = FALLBACK_GENERAL
    return re.sub(r"\.\s*$", "", msg)

# Mati casi siempre llama a la gente por su apodo, en minuscula (ezequiel->eze).
# Mapa de los mas comunes en rioplatense; si no esta, cae al nombre en minuscula
# (igual sin mayuscula, como el quiere). El revisa antes de mandar.
APODOS = {
    "ezequiel":"eze","emmanuel":"ema","facundo":"facu","matias":"mati","matías":"mati",
    "nicolas":"nico","nicolás":"nico","gustavo":"gus","sebastian":"seba","sebastián":"seba",
    "santiago":"santi","agustin":"agus","agustín":"agus","federico":"fede","gonzalo":"gonza",
    "ignacio":"nacho","joaquin":"joaco","joaquín":"joaco","tomas":"tomi","tomás":"tomi",
    "francisco":"fran","alejandro":"ale","rodrigo":"rodri","leandro":"lea","mauricio":"mauri",
    "guillermo":"guille","gabriel":"gabo","damian":"dami","damián":"dami","maximiliano":"maxi",
    "cristian":"cris","cristián":"cris","valentin":"valen","valentín":"valen","benjamin":"benja",
    "benjamín":"benja","lisandro":"lisan","bautista":"bauti","juan":"juan","lucas":"lucas",
    "franco":"franco","martin":"martin","martín":"martin","gaston":"gaston","gastón":"gaston",
    "borja":"borja","diego":"diego","pablo":"pablo","bruno":"bruno","ivan":"iván","iván":"iván",
}
def apodo(nombre):
    n = (nombre or "").strip().split()[0] if (nombre or "").strip() else ""
    return APODOS.get(n.lower(), n.lower())

def _peor_metrica(chk):
    vals = {"energia": chk.get("energia"), "descanso": chk.get("descanso"),
            "adherencia": chk.get("adherencia")}
    peor = min((v, k) for k, v in vals.items() if v is not None)[1] if any(v is not None for v in vals.values()) else None
    if (chk.get("hambre") or 1) >= 4: return "hambre"
    return peor

PREGUNTAS = {
    "energia": "Qué creés que te está bajando la energía, el descanso, la comida o el estrés?",
    "descanso": "Qué te está costando del sueño, te cuesta dormirte o te despertás durante la noche?",
    "adherencia": "Qué comida o momento del día se te hace más cuesta arriba seguir?",
    "hambre": "En qué momento del día te pega más el hambre? Ahí lo ajustamos",
}

def fallback_personalizado(nombre, chk, mal):
    n = apodo(nombre)
    partes = [f"{n}! vi tu check de la semana, gracias por completarlo."]
    m = _peor_metrica(chk) if mal else None
    # Solo se nombra una metrica si REALMENTE esta baja. Decirle "la adherencia
    # te costo" a alguien que puso 4/5 lo desmotiva y ademas es falso.
    # NO se ponen los numeros (4/5): a Mati le queda poco natural en el mensaje.
    v = chk.get(m) if m else None
    baja = v is not None and ((v >= 4) if m == "hambre" else (v <= 3))
    if mal and m and baja:
        if m == "adherencia": partes.append("veo que la adherencia te costó un poco.")
        elif m == "energia": partes.append("veo la energía media baja.")
        elif m == "descanso": partes.append("veo que el descanso no viene bien.")
        elif m == "hambre": partes.append("veo que el hambre está pegando fuerte.")
        if m in PREGUNTAS: partes.append(PREGUNTAS[m])
    elif mal:
        # Va mal por señales objetivas (entreno/peso), no por como se siente.
        partes.append("en las sensaciones venís bien, pero quiero repasar un par de cosas del entreno con vos.")
    else:
        partes.append("se te ve una buena semana, seguimos así.")
    partes.append("Mañana al despertar subí en la app, en Revisión, tus 3 fotos (frente, perfil y espalda) así te hago la devolución completa. Cualquier cosa que quieras agregar, contame por acá.")
    return " ".join(partes)

def gen_personalizados(lista):
    """lista: [{nombre, chk, chk_prev, ctx, mal}] -> {nombre: mensaje}"""
    datos = []
    for x in lista:
        chk, prev, ctx = x["chk"], x["chk_prev"], x["ctx"]
        d = {"nombre": x["nombre"], "apodo": apodo(x["nombre"]),
             "check": {k: chk.get(k) for k in ("energia", "descanso", "hambre", "adherencia")},
             "nota": chk.get("nota"), "objetivo": ctx.get("obj"),
             "entreno_activo": ctx.get("activo"), "va_mal": x["mal"]}
        if prev: d["check_semana_pasada"] = {k: prev.get(k) for k in ("energia", "descanso", "hambre", "adherencia")}
        if ctx.get("delta_peso_g") is not None:
            d["peso"] = {"tendencia_ok": ctx.get("peso_en_rango")}   # sin numeros de rango: el cliente no los conoce
        datos.append(d)
    prompt = (
        f"{TONO}\n\nPara cada cliente escribi UN mensaje de WhatsApp del domingo a la tarde "
        "(3-6 oraciones) que Mati le va a reenviar tal cual. El cliente completo su check "
        "semanal en la app (escalas 1-5; hambre 5 = mucha hambre). El mensaje debe: "
        "(1) arrancar con el APODO del cliente (campo 'apodo') tal cual viene, en MINUSCULA, "
        "sin mayuscula al principio (asi escribe Mati). Agradecer/reconocer el check con una "
        "referencia a como viene, PERO SIN decir los numeros del check (nada de '3/5' ni '4/5' "
        "ni 'pusiste 2'): queda poco natural. Traducilos a palabras (mucha hambre, energia baja, "
        "venis firme con la dieta, etc.), "
        "(2) si va_mal=true: interpretar que le puede estar pasando y hacerle UNA pregunta "
        "concreta que apunte a la causa (o un feedback accionable, no generico), "
        "(3) si viene bien: reconocimiento breve y genuino sin exagerar, "
        "(4) cerrar pidiendo que manana lunes al despertar SUBA EN LA APP sus 3 fotos (frente, perfil y "
        "espalda; el peso tambien lo carga ahi). Invitalo a contarte algo mas de su semana si quiere. "
        "NO menciones numeros de rango de peso ni la palabra 'deficit calorico' en tono tecnico; "
        "hablale como coach cercano. NO menciones 'la app detecto' ni 'el sistema'. "
        "NUNCA pongas numeros de las escalas del check en el mensaje.\n\n"
        f"Clientes (JSON):\n{json.dumps(datos, ensure_ascii=False)}\n\n"
        'Devolve SOLO un JSON valido {"Nombre Completo": "mensaje"} sin texto extra.'
    )
    res = claude_json(prompt) or {}
    out = {}
    for x in lista:
        out[x["nombre"]] = res.get(x["nombre"]) or fallback_personalizado(x["nombre"], x["chk"], x["mal"])
    return out

FALLBACK_AJUSTES = {
    "adherencia": "adherencia baja: revisar flexibilidad de la dieta (mas opciones/comidas libres) o simplificar comidas problema",
    "hambre": "hambre alta en deficit: sumar volumen alimentario (vegetales/caldos) o redistribuir carbos a la noche; evaluar +100-200 kcal si el ritmo de perdida lo permite",
    "descanso": "descanso <=2: higiene de sueno + evaluar magnesio/melatonina; revisar cafeina tarde",
    "energia": "energia <=2: revisar kcal totales, timing de carbos peri-entreno y descanso",
    "entreno": "sin entrenar / rendimiento cayendo: simplificar la semana (menos dias o menos series) para recuperar consistencia",
}

def gen_ajustes(lista):
    """lista: [{nombre, chk, ctx, alertas, dieta, rutina}] -> texto para Mati"""
    datos = []
    for x in lista:
        sup = x.get("suplementos")
        datos.append({"nombre": x["nombre"], "objetivo": x["ctx"].get("obj"), "perfil": x["ctx"].get("perfil"),
                      "check": {k: x["chk"].get(k) for k in ("energia", "descanso", "hambre", "adherencia")} if x["chk"] else None,
                      "nota": (x["chk"] or {}).get("nota"), "alertas": x["alertas"],
                      "peso_delta_g_sem": x["ctx"].get("delta_peso_g"), "var_rendimiento_pct": x["ctx"].get("var_rendimiento"),
                      "dieta": x["dieta"], "rutina": x["rutina"],
                      "ya_toma_suplementos": (sup or {}).get("stack") or "sin datos"})
    prompt = (
        "Sos el asistente tecnico de Mati Sancari (coach y medico, Pump Team). Para cada cliente "
        "que viene MAL esta semana, proponele a MATI (no al cliente) ajustes concretos de "
        "planificacion basados en los datos: dieta real, rutina real, check subjetivo, peso, "
        "rendimiento Y los suplementos que YA TOMA. Por cliente: 1 linea de diagnostico + 2-4 "
        "sugerencias accionables y especificas (ej: 'subir ~150 kcal moviendo 40g de arroz a la "
        "cena', 'recortar las series de aislamiento del dia 2'). "
        "IMPORTANTE sobre suplementos: mira 'ya_toma_suplementos' — NO sugieras algo que ya toma; "
        "si corresponde, ajusta su dosis/timing o suma algo LEGAL que le falte (magnesio, "
        "melatonina, creatina, omega 3, cafeina, etc). "
        "REGLA ABSOLUTA: JAMAS sugieras farmacos, hormonas, AAS ni dosis de quimica — eso es "
        "decision exclusivamente medica de Mati y NO va en este informe.\n\n"
        f"Clientes (JSON):\n{json.dumps(datos, ensure_ascii=False)}\n\n"
        'Devolve SOLO un JSON valido {"Nombre Completo": "diagnostico y sugerencias en texto plano"} sin nada mas.'
    )
    res = claude_json(prompt) or {}
    out = {}
    for x in lista:
        sug = res.get(x["nombre"])
        if not sug:
            # Preferir las acciones del motor (deterministas y coherentes con
            # el diagnostico) antes que los templates genericos.
            acciones = [acc for _k, _d, acc, _s in (x.get("veredicto") or {}).get("cruces", [])]
            if acciones:
                sug = "; ".join(acciones[:3])
        if not sug:
            causas = []
            chk = x["chk"] or {}
            sup = (x.get("suplementos") or {}).get("stack", "").lower()
            if (chk.get("adherencia") or 5) <= 3: causas.append(FALLBACK_AJUSTES["adherencia"])
            if (chk.get("hambre") or 1) >= 4: causas.append(FALLBACK_AJUSTES["hambre"])
            if (chk.get("descanso") or 5) <= 2 and "melatonin" not in sup and "magnesi" not in sup:
                causas.append(FALLBACK_AJUSTES["descanso"])
            if (chk.get("energia") or 5) <= 2: causas.append(FALLBACK_AJUSTES["energia"])
            if x["alertas"]: causas.append(FALLBACK_AJUSTES["entreno"])
            sug = "; ".join(causas) or "revisar en la proxima call"
        # Retroceso de fuerza: senal de RUTINA (no de dieta), va al diagnostico.
        ret = ((x.get("ctx") or {}).get("carga") or {}).get("cargas_en_retroceso")
        if ret:
            det = ", ".join(f"{r['ej']} ({r['caida_pct']}%)" for r in ret[:2])
            sug += f" · fuerza cayendo en: {det} (revisar recuperacion/tecnica)"
        out[x["nombre"]] = {"sug": sug, "sup": (x.get("suplementos") or {}).get("stack")}
    return out

def fmt_ajustes(dic):
    lineas = []
    for nombre, v in dic.items():
        extra = f"\n_ya toma: {v['sup']}_" if v.get("sup") else ""
        lineas.append(f"🔧 *{nombre}*\n{v['sug']}{extra}")
    return "\n\n".join(lineas)

# -- Main --
def main():
    hoy = date.today()
    st = {}
    try: st = json.load(open(STATE))
    except Exception: pass
    if not FORCE and st.get("last_run") == str(hoy):
        print("ya corrio hoy (usar --force para repetir)"); return

    metricas = fetch_metricas()
    metricas = [c for c in metricas if not str(c.get("cliente_id", "")).startswith("test")
                and "test" not in (c.get("nombre") or "").lower()]
    w0 = str(lunes(hoy)); w1 = str(lunes(hoy) - timedelta(weeks=1))
    checks = fetch_checks(w0, w1)
    chk_actual = {c["cliente_id"]: c for c in checks if c["semana_lunes"] == w0}
    chk_previo = {c["cliente_id"]: c for c in checks if c["semana_lunes"] == w1}
    print(f"clientes activos: {len(metricas)} | checks esta semana: {len(chk_actual)}")

    # Serie completa por cliente (8 semanas) para baseline/tendencia
    chk_series = {}
    for row in checks:
        chk_series.setdefault(row["cliente_id"], []).append(row)
    for v in chk_series.values():
        v.sort(key=lambda r: r["semana_lunes"])

    # Interpretacion de las notas (una sola llamada batcheada; si falla, el
    # motor cae al fallback por regex y nunca queda peor que antes)
    notas_extra = interpretar_notas(metricas, chk_actual, chk_series)

    alertados_sin_check, fichas_sin_check, sin_uso = [], [], []
    personalizados, ajustables = [], []
    sin_check_persist = []

    observados = []
    ult_ajustes = (st.get("clientes") or {})

    for c in metricas:
        cid = c["cliente_id"]
        nombre = c.get("nombre") or cid
        alertas, ficha, ctx = analizar(c, hoy)
        chk = chk_actual.get(cid)

        # -- Motor de analisis (P7): baseline propio + tendencias + cruces --
        serie_chk = chk_series.get(cid, [])
        ua = (ult_ajustes.get(cid) or {}).get("ultimo_ajuste")
        if ua and ua.get("fecha"):
            try: ua = {"semanas_atras": (hoy - date.fromisoformat(ua["fecha"])).days // 7, **ua}
            except Exception: ua = None
        veredicto = AN.evaluar_cliente(nombre, ctx, serie_chk, notas_extra.get(nombre), ua, hoy)
        balde = veredicto["balde"]
        mal = (balde == "ajustar")

        # Senales de carga (estancamiento/RIR): solo para quienes mandaron check
        # (es una RPC por cliente; los sin-check no se analizan a fondo).
        if chk and MODO in ("analisis", "auto"):
            ctx["carga"] = senales_carga(fetch_progresion(cid))

        if chk:
            personalizados.append({"nombre": nombre, "chk": chk, "chk_prev": chk_previo.get(cid),
                                   "ctx": ctx, "mal": mal, "alertas": alertas, "cid": cid,
                                   "veredicto": veredicto, "balde": balde})
            if mal:
                ajustables.append({"nombre": nombre, "chk": chk, "ctx": ctx, "alertas": alertas,
                                   "dieta": resumen_dieta(cid), "rutina": resumen_rutina(cid),
                                   "suplementos": fetch_suplementos(cid), "veredicto": veredicto})
            elif balde == "observar" and veredicto["motivos"]:
                observados.append(f"*{nombre}*: {'; '.join(veredicto['motivos'][:2])}")
        else:
            if not ctx.get("nunca_uso"):
                # cliente activo en la app pero sin check esta semana: se persiste
                # como sin_check para que aparezca en el dashboard.
                sin_check_persist.append({"cid": cid, "nombre": nombre, "balde": balde,
                                          "veredicto": veredicto, "ctx": ctx})
            if alertas: alertados_sin_check.append({"nombre": nombre, "alertas": alertas})
            if ficha: fichas_sin_check.append(ficha)
            elif ctx.get("nunca_uso"): sin_uso.append(nombre)

    modo = MODO
    if modo == "auto":
        modo = "analisis" if hoy.weekday() == 3 else "pedido"   # jueves = 3

    if modo == "pedido":
        # ── DOMINGO: se pide. Nadie mando el check todavia, asi que solo van
        #    el mensaje general y las alertas OBJETIVAS (entreno/peso).
        if alertados_sin_check:
            lineas = ["🚨 *Centinela — clientes que necesitan tu atencion*"]
            for a in alertados_sin_check:
                lineas.append(f"\n🔴 *{a['nombre']}*\n· " + "\n· ".join(a["alertas"]))
            send_multi("\n".join(lineas))

        general = gen_general()
        send_multi("\n".join(["📨 *Revision semanal — mensaje general*",
                              "_Mandaselo a la lista de difusion:_", "", general]))
        if fichas_sin_check:
            extra = ["📇 *Mini-fichas (para personalizar si querés)*"] + fichas_sin_check
            if sin_uso:
                extra.append("\n🕳 Sin actividad en la app: " + ", ".join(sorted(sin_uso)))
            send_multi("\n\n".join(extra))
        return _guardar_state(st, hoy, {})

    # ── LUN-JUE: se analiza a medida que llegan los checks. Solo el jueves es
    #    el cierre; antes van llegando, asi que el texto lo aclara. ──
    dia_sem = hoy.weekday()   # 0=lun ... 3=jue
    cierre = (dia_sem == 3)
    cab = "🔎 *Analisis de los checks*" if cierre else "🔎 *Checks que fueron llegando hoy*"
    n_ok = len([x for x in personalizados if not x["mal"]]) - len(observados)
    resumen = (f"{cab}\n"
               f"· {len(personalizados)} mandaron el check{'' if cierre else ' hasta ahora'}\n"
               f"· {len(ajustables)} necesitan que ajustes algo\n"
               f"· {len(observados)} para observar (nada que tocar)\n"
               f"· {max(0, n_ok)} vienen bien\n"
               f"· {len(fichas_sin_check)} {'no mandaron check' if cierre else 'todavia sin check'}")
    send_multi(resumen)

    # UN mensaje personalizado por cliente CON check (ajustar, observar y bien
    # por igual). Mati elige a quien reenviarselo desde el panel; no se manda
    # solo. Una sola llamada batcheada al modelo.
    drafts = gen_personalizados(personalizados) if personalizados else {}
    ajustes = gen_ajustes(ajustables) if ajustables else {}

    # ── PERSISTENCIA: cada cliente queda guardado en mypump_analisis_semanal ──
    #    (lo lee el panel "para revisar hoy" y el brief pre-call). Independiente
    #    de que se mande o no el WhatsApp.
    for x in personalizados:
        v = x.get("veredicto") or {}
        persist_analisis(
            x["cid"], w0, x["balde"],
            v.get("motivos") or [], v.get("banderas") or [],
            _senales_dict(v, x["ctx"], (x["ctx"] or {}).get("carga")),
            drafts.get(x["nombre"]),
            (ajustes.get(x["nombre"]) or {}).get("sug") if x["mal"] else None)
    for x in sin_check_persist:
        v = x.get("veredicto") or {}
        persist_analisis(x["cid"], w0, "sin_check",
                         v.get("motivos") or [], v.get("banderas") or [],
                         _senales_dict(v, x["ctx"], None), None, None)

    # 1) Los que necesitan ajuste: mensaje al cliente + ajustes para Mati
    if ajustables:
        send_whatsapp(f"🎯 *{len(ajustables)} para ajustar — mensaje listo para reenviar:*")
        for x in ajustables:
            motivos = "; ".join((x.get("veredicto") or {}).get("motivos", [])[:3])
            send_whatsapp(f"👤 *{x['nombre']}*" + (f"\n_{motivos}_" if motivos else ""))
            d = drafts.get(x["nombre"])
            if d: send_whatsapp(d)
        send_multi("🔬 *Ajustes sugeridos (solo para vos)*\n\n" + fmt_ajustes(ajustes))

    # 2) Observar: una linea, SIN sugerencia (no fabricar ajustes)
    if observados:
        send_multi("👀 *Para observar (no hace falta tocar nada)*\n\n" + "\n".join(observados))

    # 3) Los que vienen bien: mensaje corto de refuerzo
    bien = [x for x in personalizados if not x["mal"] and
            f"*{x['nombre']}*" not in " ".join(observados)]
    if bien:
        send_whatsapp(f"✅ *{len(bien)} vienen bien — mensajes de devolucion:*")
        for x in bien:
            send_whatsapp(f"👤 *{x['nombre']}*")
            d = drafts.get(x["nombre"])
            if d: send_whatsapp(d)

    # 4) Quienes siguen sin mandar el check
    if fichas_sin_check:
        send_multi("⏳ *Todavia no mandaron el check*\n\n" + "\n\n".join(fichas_sin_check))

    # Memoria: que se sugirio, para no repetir la semana que viene
    nuevos = {}
    for x in ajustables:
        v = x.get("veredicto") or {}
        nuevos[x["nombre"]] = {"fecha": str(hoy), "senal": (v.get("motivos") or [""])[0]}
    return _guardar_state(st, hoy, nuevos)

def _guardar_state(st, hoy, ajustes_por_nombre):
    # El dry-run NO guarda state: si no, una prueba bloquearia la ronda real.
    if DRY: return
    st["last_run"] = str(hoy)
    cl = st.setdefault("clientes", {})
    for nombre, info in (ajustes_por_nombre or {}).items():
        cl.setdefault(nombre, {})["ultimo_ajuste"] = info
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    try:
        json.dump(st, open(STATE, "w"))
    except Exception as ex:
        print("state save fail:", ex)

if __name__ == "__main__":
    main()
