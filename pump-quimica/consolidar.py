#!/usr/bin/env python3
"""Consolidar quimica / ciclo disperso -> mypump_quimica (N13, COACH-ONLY).

Reconciliacion clinica para Mati (medico): que esta usando cada cliente
(AAS, orales, GH, insulina, peptidos, ancilares AI/SERM/HCG). Hoy esta
suelto en la memoria de WhatsApp, en las videollamadas de entrega
(cambios_ciclo) y en farmaData del Cerebro. Este job junta lo alcanzable,
pre-filtra a las lineas que mencionan quimica (para gastar poquisimo), y
con Codex CLI (cuenta ChatGPT de la Mini, sin API) extrae el protocolo
estructurado. Escribe en mypump_quimica con revisado=false.

CONFIDENCIAL: mypump_quimica es SOLO del coach (RLS authenticated). Esta
info NUNCA llega a la app del cliente. Es info clinica de referencia.

Uso:
  python3 consolidar.py --dry                 # imprime, no escribe
  python3 consolidar.py --only <cliente_id>   # un solo cliente
  python3 consolidar.py --limit 5             # primeros N con candidatos
  python3 consolidar.py                        # todos, escribe
"""
import os, sys, re, json, subprocess, unicodedata, urllib.request, urllib.parse
from datetime import datetime, timezone

BOT_ENV = os.path.expanduser("~/agentkit-coach/.env")
DRY   = "--dry" in sys.argv
FORCE_HASH = "--all" in sys.argv
ONLY  = None
LIMIT = None
for i, a in enumerate(sys.argv):
    if a == "--only" and i + 1 < len(sys.argv): ONLY = sys.argv[i + 1]
    if a == "--limit" and i + 1 < len(sys.argv): LIMIT = int(sys.argv[i + 1])

def load_env(p):
    e = {}
    try:
        for line in open(p):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("="); e[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError: pass
    return e
E = load_env(BOT_ENV)
KEY = (E.get("SUPABASE_SERVICE_KEY") or E.get("SUPABASE_KEY") or E.get("SUPABASE_ANON_KEY") or "")
URL = (E.get("SUPABASE_URL") or "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")

def sb(path, method="GET", body=None, prefer=None):
    hdr = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}
    if prefer: hdr["Prefer"] = prefer
    req = urllib.request.Request(f"{URL}{path}", data=(json.dumps(body).encode() if body is not None else None),
                                 headers=hdr, method=method)
    with urllib.request.urlopen(req, timeout=40) as r:
        txt = r.read().decode()
        return json.loads(txt) if txt.strip() else None

CODEX = os.path.expanduser("~/.nvm/versions/node/v24.16.0/bin/codex")
FATHOM_PULL = os.path.expanduser("~/pump-trazabilidad/cache/fathom-pull.json")
HASHES = os.path.expanduser("~/pump-quimica/hashes.json")

import hashlib
def _norm_mail(s): return (s or "").strip().lower()

_FATHOM_CACHE = None
def cargar_fathom():
    global _FATHOM_CACHE
    if _FATHOM_CACHE is not None: return _FATHOM_CACHE
    por_mail, por_nombre = {}, {}
    try:
        pull = json.load(open(FATHOM_PULL))
        meetings = pull.get("meetings", pull) if isinstance(pull, dict) else pull
        for m in meetings:
            tr = m.get("transcript") or ""
            if len(tr) < 100: continue
            for inv in (m.get("calendar_invitees") or []):
                em = _norm_mail(inv.get("email"))
                if em and inv.get("is_external"): por_mail.setdefault(em, []).append(tr)
            titulo = m.get("meeting_title") or m.get("title") or ""
            nm = re.sub(r"(?i)reuni[oó]n|acceso|vc|videollamada|entrega|seguimiento|call|pump|[-|]", " ", titulo)
            nm = norm(nm).strip()
            if len(nm) >= 4: por_nombre.setdefault(nm, []).append(tr)
    except Exception as ex:
        print(f"  [fathom] no se pudo cargar: {ex}")
    _FATHOM_CACHE = (por_mail, por_nombre)
    return _FATHOM_CACHE

def fathom_transcripts(c):
    por_mail, por_nombre = cargar_fathom()
    trs = []
    em = _norm_mail(c.get("mail") or c.get("email"))
    if em and em in por_mail: trs += por_mail[em]
    if not trs:
        nom = norm(((c.get("nombre") or "") + " " + (c.get("apellido") or "")).strip())
        for k, v in por_nombre.items():
            if nom and (nom in k or k in nom) and len(nom) >= 5:
                trs += v
    return trs[-2:]

# Palabras que delatan QUIMICA / ciclo (AAS, orales, GH, insulina, peptidos,
# ancilares). Para pre-filtrar y no mandarle todo el texto al modelo.
KW = re.compile(
    r"testosterona|enantato|cipionato|propionato|sustanon|undecanoato|nebido|"
    r"nandrolona|deca|durabolin|npp|fenilprop|boldenona|equipoise|primobolan|metenolona|"
    r"masteron|drostanolon|trembolona|trembo|\btren\b|parabolan|"
    r"oxandrolona|anavar|oxa\b|estanozolol|stanozolol|winstrol|winny|"
    r"dianabol|dbol|metandro|oximetolona|anadrol|turinabol|halotest|"
    r"clembuterol|clenbuterol|\bclen\b|efedrina|dnp|t3\b|t4\b|citomel|cytomel|liotironina|"
    r"\bhgh\b|\bgh\b|somatropina|hormona de crecimiento|hexarelin|ipamorelin|cjc|ghrp|mk.?677|"
    r"insulina|humalog|novorapid|lantus|hcg|gonadotrofina|"
    r"tamoxifeno|nolvadex|clomifeno|clomid|toremifeno|"
    r"anastrozol|arimidex|letrozol|femara|exemestano|aromasin|inhibidor de aromatasa|\bIA\b|\bSERM\b|"
    r"cabergolina|caber|prolactina|pramipexol|"
    r"finasteride|dutasteride|proscar|"
    r"pct|post.?ciclo|blast|cruise|\bciclo\b|farmac|anabolico|esteroide|"
    r"nebivolol|telmisartan|valsartan|ezetimib|rosuvastatin|atorvastatin|"
    r"aromatas|ginecomastia|hematocrito", re.IGNORECASE)
# Ruido: menciones de que NO usa / descarta / no es momento.
RUIDO = re.compile(r"no usa|no toma|sin ciclo|descart|no es momento|todavia no|natural sin", re.IGNORECASE)

def solo_digitos(s):
    return re.sub(r"\D", "", s or "")

def norm(s):
    s = unicodedata.normalize("NFD", (s or "").lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")

def extraer_lineas(texto, ctx=1, cap=3000):
    """Lineas que mencionan suplementos + N de contexto, deduplicadas.
    OJO con el recorte: el protocolo NUEVO que indica Mati aparece al FINAL de
    la call (la tabla del plan); lo que el cliente 'venia usando' aparece al
    principio. Antes se cortaba a 1800 chars desde el inicio y el plan final
    quedaba afuera (caso Lara: registro 250+100 viejos, se perdio el plan de
    500+primo+masteron x4). Ahora, si sobra, se conserva un poco del inicio
    (contexto de lo que traia) y TODO lo posible del final (el plan vigente)."""
    if not texto: return ""
    lineas = re.split(r"[\n\r]+|(?<=[.!?])\s+", texto)
    idx = [i for i, l in enumerate(lineas) if KW.search(l) and not (RUIDO.search(l) and not KW.search(RUIDO.sub("", l)))]
    keep = set()
    for i in idx:
        for j in range(max(0, i - ctx), min(len(lineas), i + ctx + 1)):
            keep.add(j)
    frag = " ".join(lineas[j].strip() for j in sorted(keep) if lineas[j].strip())
    if len(frag) <= cap:
        return frag
    ini = cap // 5                       # ~20% del presupuesto para el inicio
    fin = cap - ini - 30
    return frag[:ini] + " [...RECORTE...] " + frag[-fin:]

def codex_json(texto):
    prompt = ("Sos el asistente clinico de un MEDICO especialista en farmacologia deportiva. Del "
              "texto (notas del medico sobre su paciente/cliente) extrae el PROTOCOLO FARMACOLOGICO "
              "VIGENTE de la persona: anabolicos (AAS) inyectables y orales, GH, "
              "insulina, peptidos, y ancilares (inhibidores de aromatasa, SERM, HCG, cabergolina, "
              "etc). Esto es reconciliacion clinica para que el medico tenga presente que usa cada "
              "paciente.\n"
              "REGLA CRITICA — QUE ES 'VIGENTE': en las llamadas suele haber DOS protocolos: (a) el "
              "que el cliente VENIA usando por su cuenta (lo cuenta al principio, 'estoy con X'), y "
              "(b) el PLAN NUEVO que el medico le INDICA durante/al final de la conversacion (la "
              "prescripcion: 'vamos a ir con...', 'te dejo...', la tabla del plan con dias de "
              "aplicacion). Si existe el plan nuevo (b), ESE es el vigente y el (a) NO va en items "
              "(como mucho, mencionalo en protocolo como 'venia con...'). Ante dosis distintas del "
              "mismo compuesto, vale la MAS TARDIA en el texto. Presta atencion a frecuencias de "
              "aplicacion (2x/semana, 4x/semana): el total semanal = dosis x aplicaciones.\n"
              "Ignora lo que se descarta o dice que no usa. NO incluyas suplementos "
              "legales comunes (creatina, magnesio, omega, etc: van en otra ficha). Para cada item "
              "marca tipo: aas|oral|gh|insulina|peptido|ai|serm|hcg|protector|otro. Inferi la fase si se "
              "menciona (on-cycle, off, pct, trt, cruise). Responde SOLO un JSON valido, sin texto "
              "extra: {\"items\":[{\"compuesto\":\"\",\"dosis\":\"\",\"frecuencia\":\"\",\"semanas\":\"\","
              "\"tipo\":\"\"}],\"protocolo\":\"\",\"fase\":\"\",\"confianza\":\"alta|media|baja\"}. "
              "Si no hay quimica clara, items vacio y confianza baja.\n\nTexto: " + texto)
    env = dict(os.environ); env["PATH"] = env.get("PATH", "") + f":{os.path.dirname(CODEX)}:/opt/homebrew/bin:/usr/local/bin"
    try:
        out = subprocess.run([CODEX, "exec", "--skip-git-repo-check", "-s", "read-only",
                              "-c", "mcp_servers={}", "--", prompt],
                             capture_output=True, text=True, timeout=120, input="", env=env, cwd="/tmp")
        m = None
        for mm in re.finditer(r"\{.*\}", out.stdout, re.S):
            m = mm  # el ultimo bloque {...} es la respuesta final
        return json.loads(m.group(0)) if m else None
    except Exception as ex:
        print(f"    [codex] fail: {ex}"); return None

def main():
    print("cargando datos...")
    blob = sb("/rest/v1/nutriplan_data?id=eq.main&select=payload")
    clients = (blob[0]["payload"].get("clients") if blob else {}) or {}
    memoria = sb("/rest/v1/clientes_memoria?select=chat_id,chat_name,md_content") or []

    # index de memoria por ultimos 10 digitos y por nombre normalizado
    mem_por_tel, mem_por_nombre = {}, {}
    for m in memoria:
        d = solo_digitos(m.get("chat_id"))[-10:]
        if d: mem_por_tel.setdefault(d, []).append(m)
        n = norm(m.get("chat_name"))
        if n: mem_por_nombre.setdefault(n, []).append(m)

    # clientes de la app (con token MyPump)
    activos = [(cid, c) for cid, c in clients.items()
               if isinstance(c, dict) and (c.get("mypump") or {}).get("token")]
    if ONLY:
        activos = [(cid, c) for cid, c in activos if cid == ONLY]
    print(f"clientes en la app: {len(activos)}")

    existentes = {r["cliente_id"]: r for r in (sb("/rest/v1/mypump_quimica?select=cliente_id,revisado") or [])}
    try: hashes = json.load(open(HASHES))
    except Exception: hashes = {}

    procesados = 0
    for cid, c in activos:
        if LIMIT and procesados >= LIMIT: break
        nombre = (c.get("nombre", "") + " " + c.get("apellido", "")).strip() or cid
        # juntar texto candidato: memoria (por tel o nombre) + formulario
        textos = []
        tel = solo_digitos(c.get("whatsapp"))[-10:]
        rows = mem_por_tel.get(tel, []) if tel else []
        if not rows:
            rows = mem_por_nombre.get(norm(c.get("nombre")), []) + mem_por_nombre.get(norm(nombre), [])
        for m in rows:
            textos.append(m.get("md_content", ""))
        # farmaData del Cerebro (tab Ciclo) + flag usaCiclo
        fd = c.get("farmaData")
        if isinstance(fd, dict):
            textos.append("Ficha ciclo (Cerebro): " + json.dumps(fd, ensure_ascii=False))
        elif isinstance(fd, str) and fd.strip():
            textos.append("Ficha ciclo (Cerebro): " + fd)
        for r in (c.get("vc", {}) or {}).get("realizadas", []):
            cs = (r.get("insights") or {}).get("cambios_ciclo")
            if cs: textos.append("Videollamada (insight ciclo): " + cs)
        for tr in fathom_transcripts(c):
            textos.append("Transcripcion videollamada: " + tr)

        frag = extraer_lineas("\n".join(t for t in textos if t))
        if len(frag) < 15:
            print(f"- {nombre}: sin candidatos"); continue

        if existentes.get(cid, {}).get("revisado"):
            print(f"- {nombre}: confirmado por vos, no se toca"); continue
        h = hashlib.md5(frag.encode("utf-8", "ignore")).hexdigest()
        if not FORCE_HASH and hashes.get(cid) == h:
            print(f"- {nombre}: sin cambios, skip"); continue

        procesados += 1
        print(f"* {nombre}: {len(frag)} chars candidatos -> codex...")
        res = codex_json(frag) if not (DRY and os.environ.get("SKIP_CODEX")) else None
        if DRY:
            print(f"    frag: {frag[:200]}...")
            print(f"    codex: {json.dumps(res, ensure_ascii=False) if res else '(dry sin codex)'}")
            continue
        if not res:
            print("    sin resultado, skip"); continue
        items = res.get("items") or []
        row = {"cliente_id": cid, "items": items, "protocolo": res.get("protocolo") or "",
               "fase": res.get("fase") or None, "confianza": res.get("confianza") or "baja",
               "revisado": False, "notas": None,
               "actualizado_en": datetime.now(timezone.utc).isoformat()}
        sb("/rest/v1/mypump_quimica?on_conflict=cliente_id", method="POST", body=row,
           prefer="resolution=merge-duplicates")
        hashes[cid] = h
        print(f"    guardado: {len(items)} items ({row['confianza']}) fase={row['fase']}")

    if not DRY:
        try:
            os.makedirs(os.path.dirname(HASHES), exist_ok=True)
            json.dump(hashes, open(HASHES, "w"))
        except Exception as ex: print("hashes save fail:", ex)
    print(f"\nlisto. procesados con candidatos: {procesados}")

if __name__ == "__main__":
    main()
