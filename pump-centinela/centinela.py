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
    q = urllib.parse.quote(f"({lunes_previo},{lunes_actual})")
    return _sb_req(f"/rest/v1/mypump_checkin_semanal?semana_lunes=in.{q}&select=*")

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
        "signos de apertura ni ¿ ni ¡; sin punto despues del saludo ni al final; sin "
        "guion largo; CERO emojis; nada de cierres motivacionales tipo 'a darle' o 'espero tus "
        "novedades'; frases cortas e irregulares, que no suene a IA ni a checklist.")

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
    "Al despertar, en ayunas antes de comer o tomar nada, pesate y cargá el peso en la app. "
    "Aprovechá y completá ahí mismo el check de la semana, son 4 toques: energía, descanso, "
    "hambre y adherencia. "
    "Subí ahí también tus 3 fotos (frente, perfil y espalda) y contame cómo te fue la semana. Si querés contarme algo más, aprovechá y escribime"
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
    if not re.search(r"cont(a|a)me|escribime|charlamos|mandame un audio|si quer(e|e)s contarme", ml):
        return False
    return True

def gen_general():
    sem = date.today().isocalendar()[1]
    ang = ANGULOS[sem % len(ANGULOS)]
    prompt = (
        f"{TONO}\n\nEscribi el mensaje de WhatsApp del domingo a la tarde avisando que manana "
        f"lunes toca la revision semanal. Se manda por broadcast: cada uno lo recibe como mensaje "
        f"privado e individual.\nANGULO DE ESTA SEMANA: {ang}\n"
        "El cliente tiene una APP (MyPump) donde carga sus datos. Pedi TRES cosas para manana:\n"
        "(1) que al despertar en ayunas, antes de comer o tomar nada, se pese y CARGUE EL PESO EN "
        "LA APP. NUNCA le pidas que te mande el peso por WhatsApp: el peso va en la app.\n"
        "(2) que complete en la app el CHECK DE LA SEMANA (son 4 toques rapidos: energia, "
        "descanso, hambre y adherencia, con un campo libre opcional).\n"
        "(3) que suba EN LA APP sus 3 fotos (frente, perfil y espalda) — ya NO se mandan por WhatsApp. "
        "(4) cerra invitandolo a contarte por WhatsApp algo mas de su semana si tiene ganas "
        "(redactalo distinto cada semana, que suene a interes real, no a formula). Ejemplo de idea: "
        "si queres contarme algo mas de como venis, escribime. "
        "audio o texto como le fue la semana.\n"
        "3-5 oraciones, natural, sin listas ni numeracion. Nada de 'Buen dia' (es de tarde). "
        "Devolve SOLO el mensaje, sin explicaciones."
    )
    msg = claude_text(prompt) or ""
    msg = re.sub(r"\s*(Espero\s+(tus|tu|mis)\b[^.]*|Quedo\s+(atento|a\s+la\s+espera)\b[^.]*|A\s+darle\b[^.]*)\.?\s*$",
                 "", msg, flags=re.IGNORECASE).strip()
    if not _general_valido(msg):
        print("  [general] la IA se desvio (no manda a la app), uso template fijo")
        msg = FALLBACK_GENERAL
    return re.sub(r"\.\s*$", "", msg)

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
    n = nombre.split()[0]
    partes = [f"{n}! Vi tu check de la semana, gracias por completarlo."]
    if mal:
        m = _peor_metrica(chk)
        if m == "adherencia": partes.append(f"Veo que la adherencia te costo ({chk.get('adherencia')}/5).")
        elif m == "energia": partes.append(f"Veo la energia baja ({chk.get('energia')}/5).")
        elif m == "descanso": partes.append(f"Veo que el descanso no viene bien ({chk.get('descanso')}/5).")
        elif m == "hambre": partes.append(f"Veo que el hambre esta pegando fuerte ({chk.get('hambre')}/5).")
        if m and m in PREGUNTAS: partes.append(PREGUNTAS[m])
    else:
        partes.append("Se te ve una buena semana, seguimos asi.")
    partes.append("Manana al despertar subi en la app tus 3 fotos (frente, perfil y espalda) asi te hago la devolucion completa. Si queres contarme algo mas de tu semana, escribime.")
    return " ".join(partes)

def gen_personalizados(lista):
    """lista: [{nombre, chk, chk_prev, ctx, mal}] -> {nombre: mensaje}"""
    datos = []
    for x in lista:
        chk, prev, ctx = x["chk"], x["chk_prev"], x["ctx"]
        d = {"nombre": x["nombre"],
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
        "(1) arrancar con el nombre de pila y agradecer/reconocer el check con una referencia "
        "ESPECIFICA a lo que puso (valores o su nota textual), "
        "(2) si va_mal=true: interpretar que le puede estar pasando y hacerle UNA pregunta "
        "concreta que apunte a la causa (o un feedback accionable, no generico), "
        "(3) si viene bien: reconocimiento breve y genuino sin exagerar, "
        "(4) cerrar pidiendo que manana lunes al despertar SUBA EN LA APP sus 3 fotos (frente, perfil y "
        "espalda; el peso tambien lo carga ahi). Invitalo a contarte algo mas de su semana si quiere. "
        "NO menciones numeros de rango de peso ni la palabra 'deficit calorico' en tono tecnico; "
        "hablale como coach cercano. NO menciones 'la app detecto' ni 'el sistema'.\n\n"
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
    lineas = []
    for x in lista:
        sug = res.get(x["nombre"])
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
        sup_txt = (x.get("suplementos") or {}).get("stack")
        extra = f"\n_ya toma: {sup_txt}_" if sup_txt else ""
        lineas.append(f"🔧 *{x['nombre']}*\n{sug}{extra}")
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

    alertados_sin_check, fichas_sin_check, sin_uso = [], [], []
    personalizados, ajustables = [], []

    for c in metricas:
        cid = c["cliente_id"]
        nombre = c.get("nombre") or cid
        alertas, ficha, ctx = analizar(c, hoy)
        chk = chk_actual.get(cid)
        obj = ctx.get("obj")
        mal = va_mal(alertas, chk, obj)

        if chk:
            personalizados.append({"nombre": nombre, "chk": chk, "chk_prev": chk_previo.get(cid),
                                   "ctx": ctx, "mal": mal, "alertas": alertas, "cid": cid})
            if mal:
                ajustables.append({"nombre": nombre, "chk": chk, "ctx": ctx, "alertas": alertas,
                                   "dieta": resumen_dieta(cid), "rutina": resumen_rutina(cid),
                                   "suplementos": fetch_suplementos(cid)})
        else:
            if alertas: alertados_sin_check.append({"nombre": nombre, "alertas": alertas})
            if ficha: fichas_sin_check.append(ficha)
            elif ctx.get("nunca_uso"): sin_uso.append(nombre)

    # 1) Alertas (solo sin-check; los con check van al personalizado + ajustes)
    if alertados_sin_check:
        lineas = ["🚨 *Centinela — clientes que necesitan tu atencion (no mandaron check)*"]
        for a in alertados_sin_check:
            lineas.append(f"\n🔴 *{a['nombre']}*\n· " + "\n· ".join(a["alertas"]))
        send_multi("\n".join(lineas))

    # 2) Mensaje general (solo para los SIN check) + sus mini-fichas
    general = gen_general()
    cuerpo = ["📨 *Revision semanal — mensaje general*",
              "_Mandaselo a los de la difusion EXCEPTO a los de los mensajes personalizados de abajo:_",
              "", general]
    send_multi("\n".join(cuerpo))
    if fichas_sin_check:
        extra = ["📇 *Mini-fichas de los que NO mandaron check*"] + fichas_sin_check
        if sin_uso:
            extra.append("\n🕳 Sin actividad en la app: " + ", ".join(sorted(sin_uso)))
        send_multi("\n\n".join(extra))

    # 3) Personalizados: nombre + mensaje, por cada cliente con check
    if personalizados:
        send_whatsapp(f"✅ *{len(personalizados)} cliente(s) ya mandaron su check — mensajes personalizados:*")
        drafts = gen_personalizados(personalizados)
        for x in personalizados:
            send_whatsapp(f"👤 *{x['nombre']}*")
            send_whatsapp(drafts[x["nombre"]])

    # 4) Ajustes sugeridos a Mati (solo los que van mal)
    if ajustables:
        send_multi("🔬 *Ajustes sugeridos (solo para vos — nada de esto va al cliente)*\n\n" + gen_ajustes(ajustables))

    # El dry-run NO guarda state: si no, una prueba en domingo bloquearia la ronda real.
    if not DRY:
        st["last_run"] = str(hoy)
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        try: json.dump(st, open(STATE, "w"))
        except Exception as ex: print("state save fail:", ex)

if __name__ == "__main__":
    main()
