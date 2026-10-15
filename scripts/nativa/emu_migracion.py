#!/usr/bin/env python3
"""Prueba de punta a punta de la migración del almacenamiento viejo en el emulador de Android (la orquesta
emu-migracion.sh). Gemelo de sim_migracion.py.

El token de la cuenta de prueba `test-nativa-android` se lee ACÁ ADENTRO de ~/Developer/nativa-evidencia/privado/
cuentas-prueba.json y nunca se imprime ni viaja por argumentos (los ve `ps`): lo que lo necesita (sembrar por DevTools,
llamar a las RPC) pasa en este proceso, y a node le llega por stdin. Nada de lo que se escribe en <salida>/ lo contiene:
las claves y archivos que lo llevan adentro se copian con el token tapado.

Uso (siempre con `python3 -I`):
  explorar                                  rutina y dieta de la cuenta (sin datos sensibles)
  semilla-capacitor <puerto> <salida>       token y una cola chica que la Capacitor manda ELLA al abrirse con red
  semilla-nativa <puerto> <salida>          lo que va a levantar la nativa: cola (con y sin sesión), sesión en curso, la
                                            cola de fotos y una sustitución de ejercicio (MIG-03), …
  almacen <puerto> <salida> <etiqueta>      el localStorage de la Capacitor viva, con el token tapado
  esperar-semilla <serial> <que> <salida> <segundos>
                                            espera que lo sembrado esté EN el leveldb (token | nota): Chromium baja el
                                            localStorage en tandas, y espacia las bajadas según cuántas hizo el proceso
  esperar-marca <serial> <salida> <segundos>
                                            espera que la escritura de vuelta de la nativa esté en el leveldb (su marca)
  backend <salida> <etiqueta>               lo que dice la base de lo sembrado (RPC de lectura) → backend-<etiqueta>.json
  nativa <serial> <salida> <etiqueta>       copia los archivos de la nativa (files/legado, la cuenta) con el token tapado
  tiempo <salida> <clave> <valor>           anota un tiempo en tiempos.json
  verificar <salida>                        junta todo y escribe informe.md; sale con 1 si algo no da
  limpiar <salida>                          deshace la sustitución de ejercicio de prueba en la cuenta (deja la lápida)
"""
import base64
import json
import os
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REGISTRO = os.path.expanduser("~/Developer/nativa-evidencia/privado/cuentas-prueba.json")
CUENTA = "test-nativa-android"   # la ÚNICA cuenta en la que escribe esta prueba
ZONA = timezone(timedelta(hours=-3))   # Argentina, sin horario de verano
PKG = "com.pumpteam.mypump"
ADB = os.path.join(os.environ.get("ANDROID_HOME", os.path.expanduser("~/Library/Android/sdk")), "platform-tools", "adb")
CDP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cdp-localstorage.mjs")


def _config():
    cfg = open(os.path.join(RAIZ, "public", "js", "config.js"), encoding="utf-8").read()
    return (re.search(r"SUPABASE_URL:\s*'([^']+)'", cfg).group(1), re.search(r"SUPABASE_ANON_KEY:\s*'([^']+)'", cfg).group(1),
            re.search(r"VISION_URL:\s*'([^']+)'", cfg).group(1))


URL, KEY, VISION = _config()


def _token():
    with open(REGISTRO, encoding="utf-8") as f:
        return json.load(f)[CUENTA]["token"]


def rpc(fn, params):
    req = urllib.request.Request(f"{URL}/rest/v1/rpc/{fn}", data=json.dumps(params).encode(), method="POST",
                                 headers={"apikey": KEY, "Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        cuerpo = r.read()
        return json.loads(cuerpo) if cuerpo else None


def ahora_ms():
    return int(datetime.now(timezone.utc).timestamp() * 1000)


def hoy():
    return datetime.now(ZONA).date()


def leer(salida, nombre, defecto=None):
    p = os.path.join(salida, nombre)
    if not os.path.exists(p):
        return defecto
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def guardar(salida, nombre, obj):
    os.makedirs(salida, exist_ok=True)
    with open(os.path.join(salida, nombre), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1, sort_keys=True)


def tapar(texto, t):
    return texto.replace(t, "<TOKEN>")


def _rutina_y_dieta(t):
    r = rpc("mypump_get_rutina_activa", {"p_token": t}) or []
    d = rpc("mypump_get_dieta_activa", {"p_token": t}) or []
    return (r[0] if r else None), (d[0] if d else None)


def _dias(rutina):
    return [(d.get("id"), d.get("nombre"), [x for b in (d.get("bloques") or []) for x in (b.get("ejercicios") or [])])
            for d in rutina["estructura"]["dias"]]


def explorar():
    t = _token()
    info = rpc("mypump_get_cliente_info", {"p_token": t})
    print("cliente:", info[0]["cliente_id"] if info else "NO RESUELVE")
    rutina, dieta = _rutina_y_dieta(t)
    if rutina:
        print("rutina", rutina["id"], "versión", rutina["version"], "semana", rutina["semana_actual"])
        for dia, nombre, ejs in _dias(rutina):
            print(f"  día {dia} ({nombre}): {len(ejs)} ejercicios; el primero {ejs[0]['id'] if ejs else '-'}")
        sem = rpc("mypump_get_sesiones_semana", {"p_token": t, "p_semana": rutina["semana_actual"]}) or []
        print("sesiones de la semana:", [(s["dia_id"], bool(s.get("finalizada_en"))) for s in sem])
    else:
        print("sin rutina activa")
    print("dieta", dieta["id"] if dieta else "ninguna")
    print("consentimiento IA:", rpc("mypump_get_consentimiento_ia", {"p_token": t}))


def cdp(puerto, accion, entrada=None, arg=None):
    """node cdp-localstorage.mjs, con la semilla por stdin. Devuelve lo que escribió (puede traer el token: no se imprime)."""
    args = ["node", CDP, str(puerto), accion] + ([arg] if arg else (["-"] if entrada is not None else []))
    r = subprocess.run(args, input=entrada, capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise SystemExit(f"cdp {accion} falló: {r.stderr.strip()[:300]}")
    return r.stdout


def _op(kind, payload, dk, ts, con_id=True, tries=0):
    o = {"kind": kind, "payload": payload, "dedupeKey": dk, "tries": tries, "ts": ts}
    if con_id:
        o["_id"] = f"{ts}_{random.randint(1, 99)}"
    return o


def _almacen(items, t):
    """El localStorage con el token tapado. De cada valor: largo en unidades UTF-16 y, si es una cola, cuántas ops."""
    out = {}
    for k, v in items.items():
        d = {"unidades": len(v.encode("utf-16-le", "surrogatepass")) // 2}
        if k.startswith("mypump_outbox_"):
            try:
                d["ops"] = len(json.loads(v))
            except Exception:
                d["ops"] = "ilegible"
        # La cola de fotos ("<lunes>|<pose>" → foto) y las sustituciones de ejercicio (exId → sustitución): cuántas.
        if k.startswith("mypump_fotoq_") or k.startswith("mypump_exercise_swaps_"):
            try:
                d["entradas"] = len(json.loads(v))
            except Exception:
                d["entradas"] = "ilegible"
        if k == "mypump_nativa_marca":
            d["valor"] = json.loads(v)
        if k in ("mypump-theme", "mypump_tipo_dia"):
            d["valor"] = v
        out[tapar(k, t)] = d
    return out


def almacen(puerto, salida, etiqueta):
    t = _token()
    items = json.loads(cdp(puerto, "leer"))
    out = _almacen(items, t)
    guardar(salida, f"almacen-{etiqueta}.json", out)
    print(f"localStorage {etiqueta}: {len(out)} claves; marca {'sí' if 'mypump_nativa_marca' in out else 'no'}; "
          f"cola de la cuenta {out.get('mypump_outbox_<TOKEN>', {}).get('ops', 'no está')}; "
          f"sesiones {sum(1 for k in out if k.startswith('mypump_sesion_<TOKEN>'))}")


def semilla_capacitor(puerto, salida):
    """Dos ops que la Capacitor manda sola al abrirse con red: si las acepta el código real de la web, el formato está bien."""
    t = _token()
    rutina, _ = _rutina_y_dieta(t)
    dia, _, ejs = _dias(rutina)[0]
    semana = rutina["semana_actual"]
    run = f"{random.randint(1000, 9999)}"
    hoy_s = hoy().isoformat()
    # Valores propios de esta corrida: si la cuenta ya los tuviera de una corrida anterior, el chequeo no probaría nada.
    antes = (rpc("mypump_get_habitos_dia", {"p_token": t, "p_fecha": hoy_s}) or [{}])[0].get("vasos_agua")
    agua = random.choice([x for x in (1, 2, 3, 4) if x != antes])
    peso = 30 + int(run) % 30 + 0.5
    ts = ahora_ms()
    ops = [
        _op("habito", {"fecha": hoy_s, "campo": "vasos_agua", "valor": str(agua)}, f"habito|{hoy_s}|vasos_agua", ts),
        _op("carga", {"sesionId": None, "diaId": dia, "semana": semana, "datos": {
            "diaId": dia, "ejercicioId": ejs[0]["id"], "ejercicioNombre": ejs[0]["nombre"], "serie": 1, "peso": peso, "reps": 10,
            "rir": 2, "notas": None}}, f"carga_{dia}_{ejs[0]['id']}_0", ts + 1),
    ]
    items = json.loads(cdp(puerto, "sembrar", json.dumps({"mypump_token": t, f"mypump_outbox_{t}": json.dumps(ops, ensure_ascii=False)})))
    guardar(salida, "almacen-semilla-capacitor.json", _almacen(items, t))
    guardar(salida, "plan.json", {"run": run, "hoy": hoy_s, "rutina": rutina["id"], "semana": semana, "dia": dia,
                                  "capacitor": {"agua": agua, "ejercicio": ejs[0]["id"], "peso": peso}})
    print(f"cola para la Capacitor: {len(ops)} ops (agua {agua}, una serie de {ejs[0]['id']} con {peso} kg, sin sesión)")


# MIG-03: la foto de la cola de la web. Un JPEG chico y válido (30×40, gris) al que cada corrida le agrega su marca en un
# comentario (segmento COM): el servicio de fotos guarda los bytes tal cual, así se ve que lo que quedó en el servidor es
# la foto de ESTA corrida y no la de una anterior.
JPEG_BASE = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA0JCgsKCA0LCgsODg0PEyAVExISEyccHhcgLikxMC4pLSwzOko+MzZGNywtQFdBRkxOUlNSMj5aYVpQYEpRUk//"
    "2wBDAQ4ODhMREyYVFSZPNS01T09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0//wAARCAAoAB4DASIAAhEBAxEB/8QAFwAB"
    "AQEBAAAAAAAAAAAAAAAAAwQABf/EABYQAQEBAAAAAAAAAAAAAAAAAAACA//EABYBAQEBAAAAAAAAAAAAAAAAAAABAv/EABQRAQAAAAAAAAAAAAAAAAAAAAD/2gAM"
    "AwEAAhEDEQA/AOhWYqzX1mKs20QVmOs11ZjrMHYrMVZr6zFWYIKzFWa+sxVmDs1mKs2YBVmKs2YH/9k=")
POSE_FOTO = "frente"
# SER-14: la sustitución que trae la app vieja (la misma de sim_migracion.py, la de iOS).
SUSTITUTO = {"slug": "Seated_Cable_Rows", "nombre": "Remo sentado en polea", "equipment": "cable", "images": None}


def _jpeg_con_marca(marca):
    """El JPEG base con `marca` en un comentario, después del APP0 (JFIF lo quiere pegado al SOI)."""
    fin_app0 = 4 + int.from_bytes(JPEG_BASE[4:6], "big")
    com = marca.encode("ascii")
    return JPEG_BASE[:fin_app0] + b"\xff\xfe" + (len(com) + 2).to_bytes(2, "big") + com + JPEG_BASE[fin_app0:]


def _lunes(fecha):
    """`_lunesISO` de la web: el lunes de la semana de `fecha` (la clave de la cola de fotos y la semana del servidor)."""
    return (fecha - timedelta(days=fecha.weekday())).isoformat()


def _sustituciones(t, rutina_id):
    """`mypump_get_exercise_swaps` (nativa_003): (vivas, borradas), o None sin la migración en la base (PGRST202)."""
    try:
        m = rpc("mypump_get_exercise_swaps", {"p_token": t, "p_rutina_id": rutina_id}) or {}
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise
    return (m.get("vivas") or {}), (m.get("borradas") or {})


def _lugar_sin_historial(t, rutina, preferido, evitar):
    """El ejercicio para la sustitución de prueba: uno sin historia en el servidor (ni vivo ni borrado). Lo de la app vieja
    no trae hora y cuenta como lo más viejo: contra una fila anterior pierde (y con una lápida se saca del teléfono), así que
    sobre un ejercicio con historia el chequeo no probaría nada. Devuelve (día, ejercicio, sin_historial)."""
    lugares = [(d, x) for d, _, ejs in _dias(rutina) for x in ejs if x["id"] not in evitar]
    s = _sustituciones(t, rutina["id"])
    usados = set() if s is None else set(s[0]) | set(s[1])
    for d, x in sorted(lugares, key=lambda p: p[1]["id"] != preferido):   # el preferido primero
        if x["id"] not in usados:
            return d, x, True
    d, x = next((p for p in lugares if p[1]["id"] == preferido), lugares[0])
    return d, x, False


def semilla_nativa(puerto, salida):
    t = _token()
    plan = leer(salida, "plan.json", {})
    rutina, _ = _rutina_y_dieta(t)
    dias = _dias(rutina)
    dia, _, ejs = dias[0]
    semana = rutina["semana_actual"]
    run = plan.get("run") or f"{random.randint(1000, 9999)}"
    hoy_s = hoy().isoformat()
    sesion = (rpc("mypump_get_sesion_dia", {"p_token": t, "p_dia_id": dia, "p_semana": semana}) or [{}])[0].get("id")
    if not sesion:   # la Capacitor no la creó: se crea (idempotente desde la 075)
        sesion = rpc("mypump_iniciar_sesion", {"p_token": t, "p_dia_id": dia, "p_semana": semana})
    habitos = (rpc("mypump_get_habitos_dia", {"p_token": t, "p_fecha": hoy_s}) or [{}])[0]
    cardio_antes = bool(habitos.get("cardio"))
    agua = (plan.get("capacitor", {}).get("agua") or 0) + random.randint(3, 6)
    peso = round(random.uniform(78, 84), 2)
    nota = f"Prueba de migración Android {run}-{random.randint(0, 16**8):08x}: semana tranquila"
    ts = ahora_ms()
    ex2, ex3 = ejs[1], ejs[2]
    # Propios de la corrida: la sesión del día es la misma en cada corrida de la semana y cada serie se pisa (una fila por
    # ejercicio y serie). Si el peso coincidiera con el que dejó una corrida anterior, el chequeo de "todavía no estaba"
    # fallaría sin que nada ande mal (le pasó a 4465 contra 1205: 1205 % 20 == 4465 % 20), así que se corre hasta uno libre.
    ya = {(r["ejercicio_id"], r["serie_numero"]): r.get("peso_kg")
          for r in (rpc("mypump_get_registros_sesion", {"p_token": t, "p_sesion_id": sesion}) or [])}

    def libre(base, rango, ex, series):
        p = base + int(run) % rango + 0.5
        while any(ya.get((ex["id"], s)) is not None and float(ya[(ex["id"], s)]) == p for s in series):
            p += 1
        return p

    p2 = libre(40, 40, ex2, (1, 2))
    p3 = libre(20, 20, ex3, (1,))
    ops = [
        # v1.0.11/main: con `_id` y la sesión capturada al encolar.
        _op("carga", {"sesionId": sesion, "diaId": dia, "semana": semana, "datos": {"diaId": dia, "ejercicioId": ex2["id"],
            "ejercicioNombre": ex2["nombre"], "serie": 1, "peso": p2, "reps": 8, "rir": 1, "notas": None}}, f"carga_{dia}_{ex2['id']}_0", ts),
        _op("carga", {"sesionId": sesion, "diaId": dia, "semana": semana, "datos": {"diaId": dia, "ejercicioId": ex2["id"],
            "ejercicioNombre": ex2["nombre"], "serie": 2, "peso": p2, "reps": 7, "rir": 0, "notas": None}}, f"carga_{dia}_{ex2['id']}_1", ts + 1, tries=1),
        _op("estado", {"sesionId": sesion, "semana": semana, "diaId": dia, "exId": ex2["id"], "seriesObjetivo": 2, "status": "completo",
                       "manual": False}, f"estado_{dia}_{ex2['id']}", ts + 2),
        # Sin sesión (se cargó sin señal): la Fase R la valida contra la rutina activa antes de mandarla.
        _op("carga", {"sesionId": None, "diaId": dia, "semana": semana, "datos": {"diaId": dia, "ejercicioId": ex3["id"],
            "ejercicioNombre": ex3["nombre"], "serie": 1, "peso": p3, "reps": 12, "rir": 2, "notas": None}}, f"carga_{dia}_{ex3['id']}_0", ts + 3),
        # Sin sesión y de un día que la rutina activa ya no tiene: para revisar, nunca se manda.
        _op("carga", {"sesionId": None, "diaId": "zz9", "semana": semana, "datos": {"diaId": "zz9", "ejercicioId": "fantasma-zz9-0",
            "ejercicioNombre": "Ejercicio de un bloque viejo", "serie": 1, "peso": 99, "reps": 9, "rir": 1, "notas": None}},
            "carga_zz9_fantasma-zz9-0_0", ts + 4),
        _op("habito", {"fecha": hoy_s, "campo": "vasos_agua", "valor": str(agua)}, f"habito|{hoy_s}|vasos_agua", ts + 5),
        # v1.0.2: sin `_id`.
        _op("peso", {"fecha": hoy_s, "valor": peso}, f"peso_{hoy_s}", ts + 6, con_id=False),
        _op("checkin", {"fecha": hoy_s, "datos": {"energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5, "nota": nota}},
            f"checkin_{hoy_s}", ts + 7, con_id=False),
    ]
    rotado = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789") for _ in range(32))
    p = f"mypump_sesion_{t}_"
    actuales = json.loads(cdp(puerto, "leer"))
    # MIG-03: la cola de fotos como la deja `_tomarFoto` de la web ("<lunes>|<pose>" → {pose, fecha, dataUrl, intentos}), y
    # una sustitución de ejercicio fijada (sin `fijado`: cuenta como fijada), en un ejercicio sin historia en el servidor.
    lunes = _lunes(hoy())
    marca_foto = f"mypump-migracion-android {run}-{random.randint(0, 16**8):08x}"
    foto = "data:image/jpeg;base64," + base64.b64encode(_jpeg_con_marca(marca_foto)).decode("ascii")
    dia_swap, ex_swap, swap_libre = _lugar_sin_historial(t, rutina, preferido=ejs[3]["id"], evitar={ex2["id"], ex3["id"]})
    items = {
        f"mypump_outbox_{t}": json.dumps(ops, ensure_ascii=False),
        # Sin token (la demo): nunca se ejecuta. Cambiaría `cardio` de hoy si se mandara.
        "mypump_outbox_anon": json.dumps([_op("habito", {"fecha": hoy_s, "campo": "cardio", "valor": str(not cardio_antes).lower()},
                                              f"habito|{hoy_s}|cardio", ts + 20)]),
        # Un token rotado que la base no conoce: queda estacionado, nunca se ejecuta.
        f"mypump_outbox_{rotado}": json.dumps([_op("peso", {"fecha": hoy_s, "valor": 55.55}, f"peso_{hoy_s}", ts + 21)]),
        # El descanso vence a la media hora: la nativa arranca recién cuando lo sembrado llegó al disco (puede tardar).
        f"mypump_rest_{t}": json.dumps({"endsAt": ts + 1_800_000, "target": 1800, "autoCloseAt": ts + 1_802_000}),
        f"mypump_fotoq_{t}": json.dumps({f"{lunes}|{POSE_FOTO}": {"pose": POSE_FOTO, "fecha": hoy_s, "dataUrl": foto, "intentos": 0}}),
        f"mypump_exercise_swaps_{rutina['id']}": json.dumps({ex_swap["id"]: {
            "original": {"slug": None, "nombre": ex_swap["nombre"], "images": None}, "current": SUSTITUTO,
            "semana": semana, "diaId": dia_swap}}, ensure_ascii=False),
        # La de la demo: nunca se toma.
        "mypump_exercise_swaps_demo": json.dumps({"x-d1-0": {"original": {"nombre": "A"}, "current": {"nombre": "B"}, "fijado": True}}),
        "mypump-theme": "dark",
        "mypump_tipo_dia": "entreno",
        "mypump_onboarding_v1": "1",
        "mypump_valor_grande": "x" * (1024 * 1024),
        "mypump_unicode_∂ñ😀": "valor con \u0000 nulo, emoji 😀 y acento á",
        "mypump_surrogate_suelto": "a\ud83db",
    }
    # La sesión en curso: la que dejó la Capacitor; si no la dejó, una igual. El arranque se pisa SIEMPRE con uno de hace 5
    # minutos (como sim_migracion.py): la Capacitor guarda el `iniciada_en` del servidor, y la sesión de la cuenta de prueba
    # es la misma toda la semana, así que puede venir de una corrida de horas antes (más de 6 h es vencida, como en la web,
    # y la migración la deja al servidor). El caso vencido lo cubren los tests de :core.
    if p + dia not in actuales:
        items.update({p + dia: sesion, p + dia + "_semana": str(semana)})
    items[p + dia + "_start"] = str(ts - 5 * 60_000)
    todo = json.loads(cdp(puerto, "sembrar", json.dumps(items)))
    guardar(salida, "almacen-sembrado.json", _almacen(todo, t))
    plan.update({"run": run, "hoy": hoy_s, "rutina": rutina["id"], "semana": semana, "dia": dia, "sesion": sesion,
                 "ex2": ex2["id"], "ex3": ex3["id"], "p2": p2, "p3": p3, "agua": agua, "peso": peso, "nota": nota, "cardio_antes": cardio_antes,
                 "ops_vigente": len(ops), "ops_sin_sesion": 2, "claves_sembradas": len(todo),
                 "sesion_de_la_capacitor": p + dia in actuales,
                 "foto_lunes": lunes, "foto_pose": POSE_FOTO, "foto_marca": marca_foto,
                 "ex_swap": ex_swap["id"], "ex_swap_dia": dia_swap, "swap_libre": swap_libre})
    guardar(salida, "plan.json", plan)
    print(f"sembrado: cola de {len(ops)} ops (5 kinds, 2 sin sesión, 2 sin _id), anon 1, token rotado 1, descanso, "
          f"sesión en curso ({'la de la Capacitor' if p + dia in actuales else 'sembrada'}), la cola de fotos ({POSE_FOTO} de la "
          f"semana del {lunes}), una sustitución de {ex_swap['id']} ({'sin' if swap_libre else 'CON'} historia en el servidor), "
          f"ajustes, 1 MB, unicode, nulo y un surrogate suelto; {len(todo)} claves en total")


def _adb(serial, *args, binario=False):
    r = subprocess.run([ADB, "-s", serial, *args], capture_output=True, timeout=60)
    return r.stdout if binario else r.stdout.decode("utf-8", "replace")


def _leveldb(serial):
    """Los archivos de datos del leveldb del WebView (sin LOCK ni LOG), buscados como los busca la app: sin ruta fija."""
    salida = _adb(serial, "shell", f"run-as {PKG} find . -path './app_webview*' -path '*Local Storage/leveldb/*' -type f")
    return sorted(l.strip() for l in salida.splitlines() if l.strip() and not re.search(r"/(LOCK|LOG|LOG\.old)$", l.strip()))


def _contiene(serial, texto):
    """¿Está `texto` en el leveldb? Chromium guarda cada valor en Latin-1 o en UTF-16LE: se buscan las dos. Recién bajado
    está en el `.log`, sin comprimir."""
    agujas = [texto.encode("latin-1", "replace"), texto.encode("utf-16-le")]
    for f in _leveldb(serial):
        b = _adb(serial, "exec-out", f"run-as {PKG} cat '{f}'", binario=True)
        if any(a in b for a in agujas):
            return True
    return False


def _tiempo(salida, clave, valor):
    t = leer(salida, "tiempos.json", {})
    t[clave] = valor
    guardar(salida, "tiempos.json", t)


def esperar_semilla(serial, que, salida, segundos):
    texto = _token() if que == "token" else leer(salida, "plan.json")["nota"]
    t0 = time.time()
    while time.time() - t0 < float(segundos):
        if _contiene(serial, texto):
            print(f"lo sembrado ({que}) está en el leveldb a los {time.time() - t0:.0f} s")
            _tiempo(salida, f"semilla_{que}_al_disco_s", round(time.time() - t0))
            return 0
        time.sleep(3)
    print(f"✗ lo sembrado ({que}) no llegó al leveldb en {segundos} s")
    return 1


def esperar_marca(serial, salida, segundos):
    """La marca de la escritura de vuelta lleva el uuid de la migración de este teléfono (legado/estado.json)."""
    estado = json.loads(_adb(serial, "exec-out", f"run-as {PKG} cat files/legado/estado.json") or "{}")
    migracion = estado.get("migracion")
    if not migracion:
        print("✗ sin legado/estado.json")
        return 1
    t0 = time.time()
    while time.time() - t0 < float(segundos):
        if _contiene(serial, migracion):
            print(f"la escritura de vuelta está en el leveldb a los {time.time() - t0:.0f} s de verla en el registro")
            _tiempo(salida, "escritura_al_disco_s", round(time.time() - t0))
            return 0
        time.sleep(2)
    print(f"✗ la escritura de vuelta no llegó al leveldb en {segundos} s")
    _tiempo(salida, "escritura_al_disco_s", f"más de {segundos}")
    return 1


def backend(salida, etiqueta):
    """Lo que dice la base de lo que se sembró. Solo RPC de lectura (get_cliente_info no: anota una apertura)."""
    t = _token()
    plan = leer(salida, "plan.json")
    hoy_s = plan["hoy"]
    sesion = (rpc("mypump_get_sesion_dia", {"p_token": t, "p_dia_id": plan["dia"], "p_semana": plan["semana"]}) or [{}])[0].get("id")
    registros = rpc("mypump_get_registros_sesion", {"p_token": t, "p_sesion_id": sesion}) if sesion else []
    estados = rpc("mypump_get_ejercicios_estado", {"p_token": t, "p_sesion_id": sesion}) if sesion else []
    habitos = (rpc("mypump_get_habitos_dia", {"p_token": t, "p_fecha": hoy_s}) or [{}])[0]
    salud = rpc("mypump_get_salud", {"p_token": t, "p_desde": hoy_s, "p_hasta": hoy_s}) or []
    checkin = (rpc("mypump_get_checkin_semana", {"p_token": t, "p_fecha": hoy_s}) or [{}])[0]
    fantasma = rpc("mypump_get_sesion_dia", {"p_token": t, "p_dia_id": "zz9", "p_semana": plan["semana"]}) or []
    b = {
        "sesion_dia": sesion,
        "registros": sorted([f"{r['ejercicio_id']}#{r['serie_numero']}:{r.get('peso_kg')}x{r.get('reps_realizadas')}@{r.get('rir_real')}"
                             for r in registros or []]),
        "estados": sorted([f"{e['ejercicio_id']}:{e['status']}" for e in estados or []]),
        "vasos_agua": habitos.get("vasos_agua"),
        "cardio": bool(habitos.get("cardio")),
        "peso_manual": [s["valor"] for s in salud if s.get("tipo") == "peso_kg" and s.get("fuente") == "manual"],
        "checkin_nota": checkin.get("nota"),
        "sesion_fantasma": len(fantasma),
        "sustituciones": _sustituciones_texto(t, plan["rutina"]),
        "foto": _foto_de_la_corrida(t, plan) if plan.get("foto_marca") else None,
    }
    guardar(salida, f"backend-{etiqueta}.json", b)
    print(f"backend {etiqueta}: {len(b['registros'])} series, agua {b['vasos_agua']}, peso {b['peso_manual']}, "
          f"check {'sí' if b['checkin_nota'] else 'no'}, sustituciones {b['sustituciones']}, foto {b['foto']}")


def _sustituciones_texto(t, rutina_id):
    """SER-14: las sustituciones vivas de la rutina ("exId:nombre"), o "sin tabla" si la migración no está aplicada."""
    s = _sustituciones(t, rutina_id)
    if s is None:
        return "sin tabla"
    return sorted(f"{k}:{(v.get('current') or {}).get('nombre')}" for k, v in s[0].items())


def _foto_de_la_corrida(t, plan):
    """MIG-03: la foto de la semana y la pose sembradas, según el servidor: si está registrada y si lo guardado es la de
    ESTA corrida (la marca del JPEG). Lo guardado se baja con la URL firmada del servicio de fotos, como lo ve la app; ni la
    URL ni la foto se escriben en ningún lado."""
    filas = rpc("mypump_get_fotos_progreso", {"p_token": t, "p_desde": None}) or []
    fila = next((f for f in filas if f.get("semana_lunes") == plan["foto_lunes"] and f.get("pose") == plan["foto_pose"]), None)
    r = {"registrada": fila is not None, "tomada_el": (fila or {}).get("tomada_el"), "es_la_de_esta_corrida": False}
    if fila is None:
        return r
    # Con un User-Agent propio: el de urllib lo frena Cloudflare antes de llegar al servicio (403, "error code: 1010").
    cabeceras = {"Content-Type": "application/json", "User-Agent": "MyPump-pruebas/1.0 (emu_migracion.py)"}
    req = urllib.request.Request(f"{VISION}/progreso/urls", data=json.dumps({"token": t, "desde": plan["foto_lunes"]}).encode(),
                                 method="POST", headers=cabeceras)
    with urllib.request.urlopen(req, timeout=30) as resp:
        urls = json.loads(resp.read() or b"{}")
    url = next((f.get("url") for f in urls.get("fotos") or []
                if f.get("semana_lunes") == plan["foto_lunes"] and f.get("pose") == plan["foto_pose"]), None)
    if url:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": cabeceras["User-Agent"]}), timeout=30) as resp:
            r["es_la_de_esta_corrida"] = plan["foto_marca"].encode("ascii") in resp.read()
    return r


def nativa(serial, salida, etiqueta):
    """Los archivos de la nativa (files/legado sin la copia cruda, y la carpeta de la cuenta), con el token tapado."""
    t = _token()
    destino = os.path.join(salida, f"nativa-{etiqueta}")
    lista = _adb(serial, "shell", f"run-as {PKG} find files/legado files/MyPump -type f").splitlines()
    copiados = 0
    for rel in (l.strip() for l in lista):
        if not rel or "/crudo/" in rel or rel.endswith(".tmp"):
            continue
        b = _adb(serial, "exec-out", "run-as", PKG, "cat", rel, binario=True)
        dst = os.path.join(destino, rel[len("files/"):])
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(b.replace(t.encode(), b"<TOKEN>"))
        copiados += 1
    crudo = [l.strip() for l in _adb(serial, "shell", f"run-as {PKG} find files/legado/crudo -type f").splitlines() if l.strip()]
    guardar(destino, "crudo.json", crudo)
    print(f"archivos de la nativa ({etiqueta}): {copiados} (+ {len(crudo)} de la copia cruda, sin copiar)")


def _registro(salida, etiqueta):
    p = os.path.join(salida, f"nativa-{etiqueta}", "legado", "registro.log")
    return open(p, encoding="utf-8").read() if os.path.exists(p) else ""


def verificar(salida):
    plan = leer(salida, "plan.json")
    filas = []

    def chequeo(nombre, ok, detalle=""):
        filas.append((nombre, bool(ok), str(detalle)))

    cap = leer(salida, "backend-capacitor.json", {})
    antes = leer(salida, "backend-sembrado.json", {})
    nat = leer(salida, "backend-nativa.json", {})
    seg = leer(salida, "backend-segundo.json", {})
    vuelta = leer(salida, "backend-vuelta.json", {})
    alm_s = leer(salida, "almacen-sembrado.json", {})
    alm_v = leer(salida, "almacen-vuelta.json", {})
    tiempos = leer(salida, "tiempos.json", {})
    reg = _registro(salida, "tercero") or _registro(salida, "segundo") or _registro(salida, "nativa")

    c = plan["capacitor"]
    serie_cap = f"{c['ejercicio']}#1:{c['peso']}x10@2" if c.get("peso") else f"{c['ejercicio']}#1"
    chequeo("La Capacitor mandó su cola (formato aceptado por el código real de la web)",
            cap.get("vasos_agua") == c["agua"] and any(r.startswith(serie_cap) for r in cap.get("registros", [])),
            f"agua {cap.get('vasos_agua')}, {serie_cap} en {cap.get('registros', [])}")
    p2, p3 = plan.get("p2", 52.5), plan.get("p3", 30)
    chequeo("Lo sembrado para la nativa todavía no estaba en la base",
            antes.get("vasos_agua") != plan["agua"] and plan["peso"] not in [float(x) for x in antes.get("peso_manual", [])]
            and antes.get("checkin_nota") != plan["nota"] and not any(r.startswith(f"{plan['ex2']}#1:{p2}x8") for r in antes.get("registros", []))
            and not any(r.startswith(f"{plan['ex3']}#1:{p3}x12") for r in antes.get("registros", [])))
    fase_l = re.findall(r"Fase L corrida (\d+)[^\n]*?token (\w+)[^\n]*?cola (\d+), por validar (\d+), estacionadas (\d+), anon (\d+)", reg)
    chequeo("Entró a la cuenta sin pegar el link: Fase L con el token adoptado", fase_l and fase_l[0][1] == "adoptado", f"{fase_l[:1]}")
    chequeo("Fase L: las ops con sesión a la cola (6), las 2 sin sesión a validar, la rotada estacionada, la anon aparte",
            fase_l and fase_l[0][2:] == ("6", "2", "1", "1"), f"{fase_l[:1]}")
    fase_r = re.findall(r"Fase R: cola (\d+), para revisar (\d+), reasignadas (\d+), reemplazadas (\d+), no resuelven (\d+), otro cliente (\d+), "
                        r"swaps sin migrar (\d+), recibo (\w+)", reg)
    chequeo("Fase R: la sin sesión válida a la cola, la del día que no existe para revisar, la rotada no resuelve",
            fase_r and fase_r[0][:2] == ("1", "1") and fase_r[0][4] == "1", f"{fase_r[:1]}")
    chequeo("Recibo confirmado por el servidor", fase_r and fase_r[0][7] == "confirmado", f"{fase_r[:1]}")
    enviados = [os.path.join(dp, f) for dp, _, fs in os.walk(os.path.join(salida, "nativa-nativa", "legado", "recibos", "enviados")) for f in fs]
    recibo = json.load(open(enviados[0], encoding="utf-8")) if enviados else {}
    chequeo("El recibo quedó en recibos/enviados, sin token", bool(recibo) and "<TOKEN>" not in json.dumps(recibo), f"{[os.path.basename(e) for e in enviados]}")
    regs = nat.get("registros", [])
    ex2, ex3 = plan["ex2"], plan["ex3"]
    chequeo("carga con sesión (2 series) y estado", any(r.startswith(f"{ex2}#1:{p2}x8@1") for r in regs)
            and any(r.startswith(f"{ex2}#2:{p2}x7@0") for r in regs) and f"{ex2}:completo" in nat.get("estados", []), f"{regs}")
    chequeo("carga SIN sesión validada contra la rutina activa y mandada", any(r.startswith(f"{ex3}#1:{p3}x12@2") for r in regs))
    chequeo("carga SIN sesión de un día que ya no existe: no se mandó (para revisar)", nat.get("sesion_fantasma") == 0)
    chequeo("habito (agua)", nat.get("vasos_agua") == plan["agua"], f"{nat.get('vasos_agua')} vs {plan['agua']}")
    chequeo("peso (cola sin _id, v1.0.2)", plan["peso"] in [float(x) for x in nat.get("peso_manual", [])], f"{nat.get('peso_manual')}")
    chequeo("checkin (sin _id)", nat.get("checkin_nota") == plan["nota"])
    chequeo("cola anon: nunca se ejecutó (cardio igual)", nat.get("cardio") == plan["cardio_antes"])
    chequeo("cola del token rotado: nunca se ejecutó (55.55 no aparece)", 55.55 not in [float(x) for x in nat.get("peso_manual", [])])
    escritura = re.findall(r"escritura de vuelta, corrida (\d+): ([^\n]+)", reg)
    chequeo("Escritura de vuelta hecha (la marca ok)", escritura and "ok 1" in escritura[0][1], f"{escritura[:1]}")
    chequeo("Segundo arranque: Fase L de nuevo (la huella cambió), nada nuevo y la escritura CONFIRMADA",
            len(fase_l) >= 2 and fase_l[1][2:4] == ("0", "0") and re.search(r"Fase L corrida 2[^\n]*escritura confirmada 1", reg), f"{fase_l}")
    chequeo("Segundo arranque: la base no cambió", seg == nat, "")
    chequeo("Tercer arranque: la Fase L no corre (la huella quedó quieta)", len(fase_l) == 2, f"{len(fase_l)} corridas")
    # Entreno toma `legado-entreno.json` al cargar y lo pasa a sus archivos (entreno-sesiones.json, entreno-descanso.json).
    sesiones, descanso_entreno = {}, None
    for dp, _, fs in os.walk(os.path.join(salida, "nativa-nativa", "MyPump")):
        if "entreno-sesiones.json" in fs:
            sesiones = json.load(open(os.path.join(dp, "entreno-sesiones.json"), encoding="utf-8"))
        if "entreno-descanso.json" in fs:
            descanso_entreno = json.load(open(os.path.join(dp, "entreno-descanso.json"), encoding="utf-8"))
    antes_r = recibo.get("antes", {})
    chequeo("Fase L: la sesión en curso y el descanso vigentes (recibo), y la sesión ya en Entreno",
            antes_r.get("sesionesVigentes") == 1 and antes_r.get("descansoVigente") is True
            and (sesiones.get(plan["dia"]) or {}).get("sesionId") == plan.get("sesion"),
            f"recibo {antes_r.get('sesionesVigentes')} sesión / descanso {antes_r.get('descansoVigente')}; Entreno {list(sesiones)}")
    # Que el descanso SIGA corriendo en Entreno no se ve desde acá: como en la web, restaurarlo borra lo guardado
    # (entreno-descanso.json) y vive en memoria hasta el próximo tick de la pantalla. Lo cubre
    # EntrenoLegadoTest.loQueDejaLaMigracionSeLeeEntero (el orden día → descanso, iOS 5eb8738).
    del descanso_entreno

    # MIG-03: la cola de fotos y la sustitución de ejercicio de la app vieja.
    if plan.get("foto_marca"):
        foto_antes, foto_nat = antes.get("foto") or {}, nat.get("foto") or {}
        chequeo("Fase L: la foto y la sustitución de la app vieja leídas, sin las de la demo (recibo)",
                antes_r.get("fotos") == 1 and antes_r.get("fotosFueraDeVentana") == 0 and antes_r.get("sustituciones") == 1,
                f"fotos {antes_r.get('fotos')} (fuera de ventana {antes_r.get('fotosFueraDeVentana')}), sustituciones {antes_r.get('sustituciones')}")
        chequeo("MIG-03: la foto de la cola vieja todavía no estaba en el servidor antes de la nativa",
                foto_antes.get("es_la_de_esta_corrida") is False, f"{foto_antes}")
        chequeo("MIG-03: la foto de la cola vieja subió: la del servidor es la de esta corrida (su marca), con su fecha",
                foto_nat.get("es_la_de_esta_corrida") is True and foto_nat.get("tomada_el") == plan["hoy"],
                f"{plan['foto_lunes']}|{plan['foto_pose']}: {foto_nat}")
        en_cola = [os.path.relpath(os.path.join(dp, f), salida) for dp, _, fs in os.walk(os.path.join(salida, "nativa-nativa", "MyPump"))
                   for f in fs if f == "fotos-pendientes.json"]
        chequeo("MIG-03: la cola de fotos de la nativa quedó vacía (subió, no quedó esperando)", not en_cola, f"{en_cola}")
        esperada = f"{plan['ex_swap']}:{SUSTITUTO['nombre']}"
        sust_antes, sust_nat = antes.get("sustituciones"), nat.get("sustituciones")
        chequeo("SER-14: la sustitución vieja es de un ejercicio sin historia en el servidor (con historia no probaría nada)",
                plan.get("swap_libre") is True and isinstance(sust_antes, list) and esperada not in sust_antes,
                f"{plan['ex_swap']}, antes {sust_antes}")
        chequeo("SER-14: la sustitución de la app vieja quedó en el servidor (mypump_get_exercise_swaps)",
                isinstance(sust_nat, list) and esperada in sust_nat, f"{sust_nat}")
        mapa = {}
        for dp, _, fs in os.walk(os.path.join(salida, "nativa-nativa", "MyPump")):
            if f"ejercicios-swaps_{plan['rutina']}.json" in fs:
                mapa = json.load(open(os.path.join(dp, f"ejercicios-swaps_{plan['rutina']}.json"), encoding="utf-8"))
        local = mapa.get(plan["ex_swap"]) or {}
        chequeo("SER-14: y en el teléfono, fijada, en el archivo de la rutina",
                (local.get("current") or {}).get("nombre") == SUSTITUTO["nombre"] and local.get("fijado") is True,
                f"{sorted(mapa)}: {(local.get('current') or {}).get('nombre')}, fijado {local.get('fijado')}")

    if alm_v:
        chequeo("Capacitor reinstalada encima: sin la cola de la cuenta ni los cachés de sesión, con la marca",
                alm_v.get("mypump_outbox_<TOKEN>", {}).get("ops", 0) == 0 and not any(k.startswith("mypump_sesion_<TOKEN>") for k in alm_v)
                and "mypump_nativa_marca" in alm_v, f"marca {alm_v.get('mypump_nativa_marca', {}).get('valor')}")
        chequeo("Capacitor reinstalada encima: la cola anon y la del token rotado quedan (no se tomaron)",
                alm_v.get("mypump_outbox_anon", {}).get("ops") == 1
                and sum(1 for k in alm_v if k.startswith("mypump_outbox_") and k not in ("mypump_outbox_anon", "mypump_outbox_<TOKEN>")) == 1)
        chequeo("Capacitor reinstalada encima: el 1 MB, el unicode y el surrogate suelto siguen",
                all(k in alm_v for k in ("mypump_valor_grande", "mypump_unicode_∂ñ😀", "mypump_surrogate_suelto")))
    if vuelta:
        chequeo("Capacitor reinstalada encima, con red: no resucita nada en la base",
                vuelta.get("registros") == nat.get("registros") and vuelta.get("vasos_agua") == nat.get("vasos_agua")
                and vuelta.get("peso_manual") == nat.get("peso_manual") and vuelta.get("sustituciones") == nat.get("sustituciones")
                and (vuelta.get("foto") or {}).get("es_la_de_esta_corrida") == (nat.get("foto") or {}).get("es_la_de_esta_corrida"), "")

    estado = leer(os.path.join(salida, "nativa-segundo", "legado"), "estado.json", {})
    lineas = [f"# Migración en el emulador de Android, corrida {plan.get('run')}", "",
              f"- Día: {plan.get('hoy')}. Cuenta: `{CUENTA}`. Claves sembradas: {plan.get('claves_sembradas')} "
              f"({len(alm_s)} leídas por DevTools después de sembrar).",
              f"- Recibo (corrida 1): antes {json.dumps(recibo.get('antes', {}).get('opsPorKind', {}), ensure_ascii=False)}; "
              f"después {json.dumps(recibo.get('despues', {}).get('libro', {}), ensure_ascii=False)}",
              f"- Servidor antes → después: {json.dumps(recibo.get('servidorAntes'), ensure_ascii=False)} → "
              f"{json.dumps(recibo.get('servidorDespues'), ensure_ascii=False)}",
              f"- Estado: {estado.get('corridas')} corridas, escritura hecha {estado.get('escrituraHecha')}, confirmada "
              f"{estado.get('escrituraConfirmada')}, recibo confirmado {'sí' if estado.get('reciboConfirmadoEn') else 'no'}",
              f"- Tiempos: {json.dumps(tiempos, ensure_ascii=False)}",
              # Para saber, no es un chequeo: la escritura de vuelta no saca la cola de fotos (tampoco en iOS). Si el cliente
              # vuelve a la app vieja, ella la vuelve a subir (la misma foto, en el mismo lugar del servidor).
              f"- La cola de fotos vieja, con la Capacitor de vuelta: "
              f"{'sigue' if 'mypump_fotoq_<TOKEN>' in alm_v else 'no está'}" if alm_v else "- (sin la vuelta a la Capacitor)",
              "", "| Chequeo | | Detalle |", "|---|---|---|"]
    for n, ok, d in filas:
        lineas.append(f"| {n} | {'✅' if ok else '❌'} | {d[:160]} |")
    lineas += ["", "## Registro de la nativa", "", "```", reg.strip(), "```"]
    with open(os.path.join(salida, "informe.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lineas) + "\n")
    malos = [n for n, ok, _ in filas if not ok]
    print(f"{len(filas) - len(malos)}/{len(filas)} chequeos OK")
    for n in malos:
        print("  ✗", n)
    return 1 if malos else 0


def limpiar(salida):
    """Deshace la sustitución de prueba en la cuenta: el borrado deja la lápida con la hora de ahora (no hay cómo sacar la
    fila). Ese ejercicio queda con historia y la próxima corrida elige otro. La foto queda: es la de la semana de la cuenta
    de prueba y la próxima la pisa."""
    t = _token()
    plan = leer(salida, "plan.json", {})
    if not plan.get("ex_swap"):
        print("nada que limpiar")
        return
    s = _sustituciones(t, plan["rutina"])
    viva = (s[0] if s else {}).get(plan["ex_swap"]) or {}
    if (viva.get("current") or {}).get("nombre") != SUSTITUTO["nombre"]:
        print(f"la sustitución de prueba no está en el servidor ({plan['ex_swap']}): no se toca")
        return
    rpc("mypump_delete_exercise_swap", {"p_token": t, "p_rutina_id": plan["rutina"], "p_ex_id": plan["ex_swap"], "p_ts": ahora_ms()})
    print(f"sustitución de prueba borrada: {plan['ex_swap']} (queda la lápida)")


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    a = argv[2:]
    if cmd == "explorar":
        explorar()
    elif cmd == "semilla-capacitor" and len(a) == 2:
        semilla_capacitor(*a)
    elif cmd == "semilla-nativa" and len(a) == 2:
        semilla_nativa(*a)
    elif cmd == "almacen" and len(a) == 3:
        almacen(*a)
    elif cmd == "esperar-semilla" and len(a) == 4:
        return esperar_semilla(*a)
    elif cmd == "esperar-marca" and len(a) == 3:
        return esperar_marca(*a)
    elif cmd == "tiempo" and len(a) == 3:
        _tiempo(*a)
    elif cmd == "backend" and len(a) == 2:
        backend(*a)
    elif cmd == "nativa" and len(a) == 3:
        nativa(*a)
    elif cmd == "verificar" and len(a) == 1:
        return verificar(*a)
    elif cmd == "limpiar" and len(a) == 1:
        limpiar(*a)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
