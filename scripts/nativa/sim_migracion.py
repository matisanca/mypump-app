#!/usr/bin/env python3
"""Prueba de punta a punta de la migración del almacenamiento viejo en un simulador (la orquesta sim-migracion.sh).

El token de la cuenta de prueba `test-nativa-ios` se lee ACÁ ADENTRO de ~/Developer/nativa-evidencia/privado/
cuentas-prueba.json y nunca se imprime ni viaja por argumentos (los ve `ps`): todo lo que lo necesita (sembrar, llamar a
las RPC) pasa en este proceso. Nada de lo que se escribe en <salida>/ lo contiene: las claves y archivos que lo llevan
adentro se copian con el token tapado.

Uso (siempre con `python3 -I`):
  explorar                            rutina y dieta de la cuenta (sin datos sensibles)
  db <contenedor>                     ruta del localstorage.sqlite3 de capacitor://localhost (por el archivo `origin`)
  token <db>                          siembra mypump_token (con la app cerrada)
  cola-capacitor <db> <salida>        una cola chica que la Capacitor manda ELLA al abrirse con red (valida el formato)
  preparar <db> <salida>              "el resto": la cola para la nativa y los casos que no se producen a mano
  backend <salida> <etiqueta>         lo que dice la base de lo sembrado (RPC de lectura) → backend-<etiqueta>.json
  almacen <db> <salida> <etiqueta>    el localStorage con el token tapado → almacen-<etiqueta>.json
  nativa <contenedor> <salida> <etiq> copia los archivos de la nativa (legado/, cuenta) con el token tapado
  ajustes <contenedor> <salida> <etiq> los UserDefaults `mypump*` de la app (su plist, no el dominio global del simulador)
  verificar <salida>                  junta todo y escribe informe.md; sale con 1 si algo no da
  limpiar <salida>                    deshace los swaps de prueba en la cuenta
"""
import base64
import glob
import json
import os
import plistlib
import random
import re
import shutil
import sqlite3
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import legado_sqlite  # noqa: E402  (mismo directorio; -I lo saca del path a propósito)

RAIZ = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REGISTRO = os.path.expanduser("~/Developer/nativa-evidencia/privado/cuentas-prueba.json")
CUENTA = "test-nativa-ios"   # la ÚNICA cuenta en la que escribe esta prueba
ZONA = timezone(timedelta(hours=-3))   # Argentina, sin horario de verano


def _config():
    cfg = open(os.path.join(RAIZ, "public", "js", "config.js"), encoding="utf-8").read()
    return (re.search(r"SUPABASE_URL:\s*'([^']+)'", cfg).group(1), re.search(r"SUPABASE_ANON_KEY:\s*'([^']+)'", cfg).group(1))


URL, KEY = _config()


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


def _rutina_y_dieta(t):
    return rpc("mypump_get_rutina_activa", {"p_token": t})[0], rpc("mypump_get_dieta_activa", {"p_token": t})[0]


def _dias(rutina):
    return [(d.get("id"), d.get("nombre"), [x for b in (d.get("bloques") or []) for x in (b.get("ejercicios") or [])])
            for d in rutina["estructura"]["dias"]]


def _comidas(dieta):
    e = dieta["estructura"]
    return (e["tipos_dia"][0].get("comidas") if e.get("tipos_dia") else e.get("comidas")) or []


def explorar():
    t = _token()
    info = rpc("mypump_get_cliente_info", {"p_token": t})
    print("cliente:", info[0]["cliente_id"] if info else "NO RESUELVE")
    rutina, dieta = _rutina_y_dieta(t)
    print("rutina", rutina["id"], "versión", rutina["version"], "semana", rutina["semana_actual"])
    for dia, nombre, ejs in _dias(rutina):
        print(f"  día {dia} ({nombre}): {len(ejs)} ejercicios; el primero {ejs[0]['id'] if ejs else '-'}")
    print("dieta", dieta["id"], "tipos de día", [x.get("id") for x in dieta["estructura"].get("tipos_dia") or []])
    for c in _comidas(dieta)[:8]:
        ops = c.get("options") or []
        a = (ops[0].get("foods") or [None])[0] if ops else None
        print(f"  comida {c.get('id')} ({c.get('name')}): {len(ops)} opciones, la primera '{ops[0].get('name') if ops else '-'}'; "
              f"primer alimento {a and {k: a.get(k) for k in ('name', 'qty', 'unit')}}")
    print("swaps en la base:", len(rpc("mypump_get_food_swaps", {"p_token": t, "p_dieta_id": dieta["id"]}) or []))
    sem = rpc("mypump_get_sesiones_semana", {"p_token": t, "p_semana": rutina["semana_actual"]}) or []
    print("sesiones de la semana:", [(s["dia_id"], bool(s.get("finalizada_en"))) for s in sem])


def ubicar_db(contenedor):
    """El localstorage.sqlite3 de capacitor://localhost: el que tiene al lado un `origin` con dos veces ese origen."""
    for db in glob.glob(os.path.join(contenedor, "Library", "WebKit", "*", "WebsiteData", "Default", "*", "*", "LocalStorage",
                                     "localstorage.sqlite3")):
        origen = os.path.join(os.path.dirname(os.path.dirname(db)), "origin")
        if os.path.exists(origen):
            b = open(origen, "rb").read()
            if b.count(b"capacitor") >= 2 and b.count(b"localhost") >= 2:
                return db
    return None


def _op(kind, payload, dk, ts, con_id=True, tries=0):
    o = {"kind": kind, "payload": payload, "dedupeKey": dk, "tries": tries, "ts": ts}
    if con_id:
        o["_id"] = f"{ts}_{random.randint(1, 99)}"
    return o


def cola_capacitor(db, salida):
    """Dos ops que la Capacitor manda sola al abrirse: si las acepta el código real de la web, el formato está bien. La carga
    va SIN sesión al día que la app abre (lun): la Capacitor crea la sesión y escribe sus claves `mypump_sesion_*` reales."""
    t = _token()
    rutina, _ = _rutina_y_dieta(t)
    dias = _dias(rutina)
    dia, _, ejs = dias[0]
    semana = rutina["semana_actual"]
    run = f"{random.randint(1000, 9999)}"
    hoy_s = hoy().isoformat()
    agua = random.randint(1, 4)
    ts = ahora_ms()
    ops = [
        _op("habito", {"fecha": hoy_s, "campo": "vasos_agua", "valor": str(agua)}, f"habito|{hoy_s}|vasos_agua", ts),
        _op("carga", {"sesionId": None, "diaId": dia, "semana": semana, "datos": {
            "diaId": dia, "ejercicioId": ejs[0]["id"], "ejercicioNombre": ejs[0]["nombre"], "serie": 1, "peso": 40, "reps": 10,
            "rir": 2, "notas": None}}, f"carga_{dia}_{ejs[0]['id']}_0", ts + 1),
    ]
    legado_sqlite.sembrar(db, {f"mypump_outbox_{t}": json.dumps(ops, ensure_ascii=False)})
    guardar(salida, "plan.json", {"run": run, "hoy": hoy_s, "rutina": rutina["id"], "semana": semana, "dia": dia,
                                  "capacitor": {"agua": agua, "ejercicio": ejs[0]["id"]}})
    print(f"cola para la Capacitor: {len(ops)} ops (agua {agua}, una serie de {ejs[0]['id']} sin sesión)")


# La cola de fotos guarda dataUrls; esta prueba no sube fotos (las sube Revisión), así que alcanza con la forma.
JPEG = ("/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////"
        "wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=")


def preparar(db, salida):
    t = _token()
    plan = leer(salida, "plan.json", {})
    rutina, dieta = _rutina_y_dieta(t)
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
    nota = f"Prueba de migración {run}: semana tranquila"
    chat = f"Prueba de migración {run} (cuenta de prueba, ignorar)"
    chat_rotado = f"NO DEBERÍA LLEGAR {run}: cola de un token rotado"
    comidas = _comidas(dieta)
    c1, c3 = comidas[0], comidas[2]
    f1 = c1["options"][0]["foods"][0]
    f3 = c3["options"][0]["foods"][0]
    orig1 = {k: f1[k] for k in ("name", "qty", "unit") if k in f1}
    orig3 = {k: f3[k] for k in ("name", "qty", "unit") if k in f3}
    swap1 = {"name": "Ricota descremada", "qty": 150, "unit": "g", "kcal": 207, "prot": 17, "carb": 6, "fat": 12, "category": "lacteo",
             "_orig": orig1}
    swap3 = {"name": "Atún al natural", "qty": 200, "unit": "g", "kcal": 232, "prot": 52, "carb": 0, "fat": 2, "category": "proteina",
             "_orig": orig3}
    ts = ahora_ms()
    ex2, ex3 = ejs[1], ejs[2]
    D = dieta["id"]
    # SER-14: lo de la app vieja no trae `_ts` y cuenta como lo más viejo. Sube a la base, salvo que la base tenga una
    # lápida de ese ejercicio: lo que se borró después le gana y no revive. La limpieza de cada corrida deja una lápida,
    # así que la que tiene que subir es de un ejercicio sin lápida (de cualquier día, fuera de los de la cola). Si hay
    # alguno con lápida, se siembra también y no tiene que revivir.
    try:
        base_sust = rpc("mypump_get_exercise_swaps", {"p_token": t, "p_rutina_id": rutina["id"]}) or {}
    except urllib.error.HTTPError as e:
        if e.code != 404:
            raise
        base_sust = {}   # sin la nativa_003
    lapidas = set((base_sust.get("borradas") or {}).keys())
    candidatos = [(d, e) for d, _, es in dias for e in es if e["id"] not in {ejs[0]["id"], ex2["id"], ex3["id"]}]
    libres = [(d, e) for d, e in candidatos if e["id"] not in lapidas]
    if not libres:
        sys.exit("✗ todos los ejercicios de la rutina tienen lápida: hace falta otra rutina para la cuenta de prueba")
    sust_libre = libres[0]
    sust_lapida = next(((d, e) for d, e in candidatos if e["id"] in lapidas), None)
    ops = [
        # v1.0.11/main: con `_id` y la sesión capturada al encolar.
        _op("carga", {"sesionId": sesion, "diaId": dia, "semana": semana, "datos": {"diaId": dia, "ejercicioId": ex2["id"],
            "ejercicioNombre": ex2["nombre"], "serie": 1, "peso": 52.5, "reps": 8, "rir": 1, "notas": None}}, f"carga_{dia}_{ex2['id']}_0", ts),
        _op("carga", {"sesionId": sesion, "diaId": dia, "semana": semana, "datos": {"diaId": dia, "ejercicioId": ex2["id"],
            "ejercicioNombre": ex2["nombre"], "serie": 2, "peso": 52.5, "reps": 7, "rir": 0, "notas": None}}, f"carga_{dia}_{ex2['id']}_1", ts + 1, tries=1),
        _op("estado", {"sesionId": sesion, "semana": semana, "diaId": dia, "exId": ex2["id"], "seriesObjetivo": 2, "status": "completo",
                       "manual": False}, f"estado_{dia}_{ex2['id']}", ts + 2),
        # Sin sesión (se cargó sin señal): la Fase R la valida contra la rutina activa antes de mandarla.
        _op("carga", {"sesionId": None, "diaId": dia, "semana": semana, "datos": {"diaId": dia, "ejercicioId": ex3["id"],
            "ejercicioNombre": ex3["nombre"], "serie": 1, "peso": 30, "reps": 12, "rir": 2, "notas": None}}, f"carga_{dia}_{ex3['id']}_0", ts + 3),
        # Sin sesión y de un día que la rutina activa ya no tiene: para revisar, nunca se manda.
        _op("carga", {"sesionId": None, "diaId": "zz9", "semana": semana, "datos": {"diaId": "zz9", "ejercicioId": "fantasma-zz9-0",
            "ejercicioNombre": "Ejercicio de un bloque viejo", "serie": 1, "peso": 99, "reps": 9, "rir": 1, "notas": None}},
            "carga_zz9_fantasma-zz9-0_0", ts + 4),
        _op("habito", {"fecha": hoy_s, "campo": "vasos_agua", "valor": str(agua)}, f"habito|{hoy_s}|vasos_agua", ts + 5),
        # v1.0.2: sin `_id`.
        _op("peso", {"fecha": hoy_s, "valor": peso}, f"peso_{hoy_s}", ts + 6, con_id=False),
        _op("checkin", {"fecha": hoy_s, "datos": {"energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5, "nota": nota}},
            f"checkin_{hoy_s}", ts + 7, con_id=False),
        _op("comida", {"fecha": hoy_s, "comidaId": c1["id"], "opcion": c1["options"][0].get("name") or "A", "estado": "comido", "excl": []},
            f"comida|{hoy_s}|{c1['id']}", ts + 8),
        _op("swap", {"dietaId": D, "comidaId": c1["id"], "optIdx": 0, "foodIdx": 0, "food": swap1}, f"swap_{D}_{c1['id']}_0_0", ts + 9),
        _op("swap_del", {"dietaId": D, "comidaId": comidas[1]["id"], "optIdx": 0, "foodIdx": 0}, f"swap_{D}_{comidas[1]['id']}_0_0", ts + 10),
        _op("chat", {"contenido": chat}, f"chat_{ts + 11}_{chat[:40]}", ts + 11),
    ]
    rotado = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789") for _ in range(32))
    otro_dia = dias[2][0]
    p = f"mypump_sesion_{t}_"
    actuales = legado_sqlite.dump(db)
    items = {
        f"mypump_outbox_{t}": json.dumps(ops, ensure_ascii=False),
        # Sin token (la demo): nunca se ejecuta. Cambiaría `cardio` de hoy si se mandara.
        "mypump_outbox_anon": json.dumps([_op("habito", {"fecha": hoy_s, "campo": "cardio", "valor": str(not cardio_antes).lower()},
                                              f"habito|{hoy_s}|cardio", ts + 20)], ensure_ascii=False),
        # Un token rotado que la base ya no conoce: queda estacionado, nunca se ejecuta.
        f"mypump_outbox_{rotado}": json.dumps([_op("chat", {"contenido": chat_rotado}, f"chat_{ts + 21}_{chat_rotado[:40]}", ts + 21)],
                                              ensure_ascii=False),
        f"mypump_rest_{t}": json.dumps({"endsAt": ts + 600_000, "target": 600, "autoCloseAt": ts + 602_000}),
        f"mypump_fotoq_{t}": json.dumps({f"{hoy_s}|frente": {"pose": "frente", "fecha": hoy_s, "dataUrl": "data:image/jpeg;base64," + JPEG,
                                                             "intentos": 0}}),
        f"mypump_exercise_swaps_{rutina['id']}": json.dumps({e["id"]: {
            "original": {"slug": None, "nombre": e["nombre"], "images": None},
            "current": {"slug": "Seated_Cable_Rows", "nombre": "Remo sentado en polea", "equipment": "cable", "images": None},
            "semana": semana, "diaId": d} for d, e in [sust_libre] + ([sust_lapida] if sust_lapida else [])},
            ensure_ascii=False),   # sin `fijado`: cuenta como fijada
        "mypump_exercise_swaps_demo": json.dumps({"x-d1-0": {"original": {"nombre": "A"}, "current": {"nombre": "B"}, "fijado": True}}),
        # Como `confirmSwap` de la web: el swap de la cola está también en el mapa local. El de c3, solo en el mapa (nunca
        # llegó a la base): es el que hay que migrar.
        f"mypump_food_swaps_{D}": json.dumps({f"swap_{D}_{c1['id']}_0_0": {"original": orig1, "current": swap1},
                                              f"swap_{D}_{c3['id']}_0_0": {"original": orig3, "current": swap3}}, ensure_ascii=False),
        "mypump_food_swaps_demo": json.dumps({"swap_demo_c1_0_0": {"original": None, "current": {"name": "Demo"}}}),
        f"mypump_dia_visualizado_{rutina['id']}": otro_dia,
        "mypump-theme": "dark",
        "mypump_tipo_dia": "entreno",
        "mypump_notif_prefs": json.dumps({"check": {"on": True, "hora": 10, "min": 30}}),
        "mypump_notif_pedido": "1",
        "mypump_onboarding_v1": "1",
        "mypump_health_connected": "1",
        "mypump_health_last_sync": datetime.now(timezone.utc).isoformat(),
        "mypump_valor_grande": "x" * (1024 * 1024),
        "mypump_unicode_∂ñ😀": "valor con \u0000 nulo, emoji 😀 y acento á",
    }
    # La sesión en curso: la que dejó la Capacitor; si no la dejó, una igual. El arranque se pisa SIEMPRE con uno de hace
    # 5 minutos: la Capacitor guarda el `iniciada_en` del servidor, y la sesión de la cuenta de prueba puede venir de
    # una corrida de horas antes (más de 6 h es vencida, como en la web, y la migración la deja al servidor). El caso
    # vencido lo cubren los tests (`sesionEnCursoVigenteYVencida`).
    inicio = ts - 5 * 60_000
    if p + dia not in actuales:
        items.update({p + dia: sesion, p + dia + "_semana": str(semana)})
    items[p + dia + "_start"] = str(inicio)
    legado_sqlite.sembrar(db, items)
    # La Capacitor de main marcó los swaps de esta dieta como migrados al abrir (base vacía y ninguno local). Un teléfono
    # que viene de la v1.0.11 no tiene esa marca (no existía): sin ella, el swap local de arriba es uno que el servidor
    # nunca vio y la nativa lo tiene que subir. Con la marca, la nativa (igual que la web) lo descarta.
    borrar_claves(db, [f"mypump_swaps_migrados_{D}"])
    plan.update({"run": run, "hoy": hoy_s, "rutina": rutina["id"], "dieta": D, "semana": semana, "dia": dia, "sesion": sesion, "inicio": inicio,
                 "ex2": ex2["id"], "ex3": ex3["id"], "ex_swap": sust_libre[1]["id"],
                 "ex_lapida": sust_lapida[1]["id"] if sust_lapida else None, "agua": agua, "peso": peso, "nota": nota, "chat": chat,
                 "chat_rotado": chat_rotado, "cardio_antes": cardio_antes, "comida": c1["id"], "swap1": f"{c1['id']}/0/0",
                 "swap3": f"{c3['id']}/0/0", "otro_dia": otro_dia, "ops_vigente": len(ops), "ops_sin_sesion": 2})
    guardar(salida, "plan.json", plan)
    print(f"sembrado: cola de {len(ops)} ops (9 kinds, 2 sin sesión, 2 sin _id), anon 1, token rotado 1, descanso, fotos, swaps, "
          f"ajustes, 1 MB, unicode y nulo")


def borrar_claves(db, claves):
    con = sqlite3.connect(db)
    with con:
        con.executemany("DELETE FROM ItemTable WHERE key = ?", [(k,) for k in claves])
    con.close()


def sustituciones_en_la_base(t, rutina):
    """SER-14 (nativa_003): las sustituciones de ejercicio de la rutina, o "sin tabla" si la migración no está aplicada."""
    try:
        m = rpc("mypump_get_exercise_swaps", {"p_token": t, "p_rutina_id": rutina})
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return "sin tabla"
        raise
    vivas = (m or {}).get("vivas") or {}
    return sorted(f"{k}:{(v.get('current') or {}).get('nombre')}" for k, v in vivas.items())


def backend(salida, etiqueta):
    """Lo que dice la base de lo que se sembró. Solo RPC de lectura (ninguna anota aperturas: get_cliente_info no se usa)."""
    t = _token()
    plan = leer(salida, "plan.json")
    hoy_s = plan["hoy"]
    sesion = (rpc("mypump_get_sesion_dia", {"p_token": t, "p_dia_id": plan["dia"], "p_semana": plan["semana"]}) or [{}])[0].get("id")
    registros = rpc("mypump_get_registros_sesion", {"p_token": t, "p_sesion_id": sesion}) if sesion else []
    estados = rpc("mypump_get_ejercicios_estado", {"p_token": t, "p_sesion_id": sesion}) if sesion else []
    habitos = (rpc("mypump_get_habitos_dia", {"p_token": t, "p_fecha": hoy_s}) or [{}])[0]
    salud = rpc("mypump_get_salud", {"p_token": t, "p_desde": hoy_s, "p_hasta": hoy_s}) or []
    checkin = (rpc("mypump_get_checkin_semana", {"p_token": t, "p_fecha": hoy_s}) or [{}])[0]
    comidas = rpc("mypump_get_comidas_marcadas", {"p_token": t, "p_fecha": hoy_s}) or []
    swaps = rpc("mypump_get_food_swaps", {"p_token": t, "p_dieta_id": plan["dieta"]}) or [] if plan.get("dieta") else []
    chat = rpc("mypump_get_chat", {"p_token": t, "p_antes": None, "p_limite": 30}) or []
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
        "comidas": sorted([f"{c['comida_id']}:{c.get('estado')}" for c in comidas]),
        "swaps": sorted([f"{s['comida_id']}/{s['opt_idx']}/{s['food_idx']}:{(s.get('food_data') or {}).get('name')}" for s in swaps]),
        "chat_prueba": sum(1 for m in chat if m.get("contenido") == plan.get("chat")),
        "chat_rotado": sum(1 for m in chat if m.get("contenido") == plan.get("chat_rotado")),
        "sesion_fantasma": len(fantasma),
        "sustituciones": sustituciones_en_la_base(t, plan["rutina"]),
    }
    guardar(salida, f"backend-{etiqueta}.json", b)
    print(f"backend {etiqueta}: {len(b['registros'])} series, agua {b['vasos_agua']}, swaps {len(b['swaps'])}, chat {b['chat_prueba']}")


def almacen(db, salida, etiqueta):
    """El localStorage, con el token tapado en claves y valores. De cada valor: largo y si trae ops."""
    t = _token()
    items = legado_sqlite.dump(db)
    out = {}
    for k, v in items.items():
        d = {"unidades": len(v.encode("utf-16-le")) // 2}
        if k.startswith("mypump_outbox_"):
            try:
                d["ops"] = len(json.loads(v))
            except Exception:
                d["ops"] = "ilegible"
        if k == "mypump_nativa_marca":
            d["valor"] = json.loads(v)
        if k in ("mypump-theme", "mypump_tipo_dia") or k.startswith("mypump_dia_visualizado_"):
            d["valor"] = v
        out[k.replace(t, "<TOKEN>")] = d
    guardar(salida, f"almacen-{etiqueta}.json", out)
    print(f"localStorage {etiqueta}: {len(out)} claves; marca {'sí' if 'mypump_nativa_marca' in out else 'no'}; "
          f"cola de la cuenta {out.get('mypump_outbox_<TOKEN>', {}).get('ops', 'no está')}")


def nativa(contenedor, salida, etiqueta):
    """Los archivos de la nativa, con el token tapado (pendientes.json y estado.json lo llevan: hacen falta en el teléfono)."""
    t = _token()
    destino = os.path.join(salida, f"nativa-{etiqueta}")
    shutil.rmtree(destino, ignore_errors=True)
    soporte = os.path.join(contenedor, "Library", "Application Support")
    copiados = 0
    # Los recibos confirmados pasan a recibos/enviados/ (y los rechazados a recibos/rechazados/): también se copian.
    for origen in glob.glob(os.path.join(soporte, "legado", "*")) + glob.glob(os.path.join(soporte, "legado", "recibos", "*")) \
            + glob.glob(os.path.join(soporte, "legado", "recibos", "*", "*")) + glob.glob(os.path.join(soporte, "MyPump", "cuenta-*", "*")):
        if os.path.isdir(origen):
            continue
        rel = os.path.relpath(origen, soporte)
        dst = os.path.join(destino, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(origen, "rb") as f:
            b = f.read()
        with open(dst, "wb") as f:
            f.write(b.replace(t.encode(), b"<TOKEN>"))
        copiados += 1
    print(f"archivos de la nativa ({etiqueta}): {copiados}")


def ajustes(contenedor, salida, etiqueta):
    """`simctl spawn … defaults read` lee el dominio global del simulador, no el del contenedor de la app: se lee su plist."""
    t = _token()
    p = os.path.join(contenedor, "Library", "Preferences", "com.pumpteam.mypump.plist")
    d = plistlib.load(open(p, "rb")) if os.path.exists(p) else {}
    out = {k.replace(t, "<TOKEN>"): (v.replace(t, "<TOKEN>") if isinstance(v, str) else v) for k, v in d.items() if k.startswith("mypump")}
    guardar(salida, f"ajustes-{etiqueta}.json", out)
    print(f"ajustes {etiqueta}: {sorted(out)}")


def verificar(salida):
    plan = leer(salida, "plan.json")
    filas = []

    def chequeo(nombre, ok, detalle=""):
        filas.append((nombre, bool(ok), detalle))

    cap = leer(salida, "backend-capacitor.json", {})
    nat = leer(salida, "backend-nativa.json", {})
    seg = leer(salida, "backend-segundo.json", {})
    vuelta = leer(salida, "backend-vuelta.json", {})
    alm_n = leer(salida, "almacen-nativa.json", {})
    alm_v = leer(salida, "almacen-vuelta.json", {})
    reg = ""
    p = os.path.join(salida, "nativa-segundo", "legado", "registro.log")
    if os.path.exists(p):
        reg = open(p, encoding="utf-8").read()

    chequeo("La Capacitor mandó su cola (formato aceptado por el código real de la web)",
            cap.get("vasos_agua") == plan["capacitor"]["agua"] and any(r.startswith(plan["capacitor"]["ejercicio"] + "#1") for r in cap.get("registros", [])),
            f"agua {cap.get('vasos_agua')}, series {len(cap.get('registros', []))}")
    chequeo("Entró a la cuenta sin pegar el link (token adoptado y Fase R con get_cliente_info)",
            "token adoptado" in reg and "Fase R:" in reg)
    ex2, ex3 = plan["ex2"], plan["ex3"]
    regs = nat.get("registros", [])
    chequeo("carga con sesión (2 series) y estado", any(r.startswith(f"{ex2}#1:52.5x8@1") for r in regs)
            and any(r.startswith(f"{ex2}#2:52.5x7@0") for r in regs) and f"{ex2}:completo" in nat.get("estados", []), f"{regs}")
    chequeo("carga SIN sesión validada contra la rutina activa y mandada", any(r.startswith(f"{ex3}#1:30") for r in regs))
    chequeo("carga SIN sesión de un día que ya no existe: no se mandó (para revisar)", nat.get("sesion_fantasma") == 0)
    chequeo("habito (agua)", nat.get("vasos_agua") == plan["agua"], f"{nat.get('vasos_agua')} vs {plan['agua']}")
    chequeo("peso (cola sin _id, v1.0.2)", plan["peso"] in [float(x) for x in nat.get("peso_manual", [])], f"{nat.get('peso_manual')}")
    chequeo("checkin (sin _id)", nat.get("checkin_nota") == plan["nota"])
    chequeo("comida", f"{plan['comida']}:comido" in nat.get("comidas", []))
    chequeo("swap de la cola", any(s.startswith(plan["swap1"] + ":Ricota") for s in nat.get("swaps", [])), f"{nat.get('swaps')}")
    chequeo("swap de comida local sin migrar (v1.0.11, sin marca): lo subió la nativa", any(s.startswith(plan["swap3"] + ":Atún") for s in nat.get("swaps", [])))
    mapas = glob.glob(os.path.join(salida, "nativa-nativa", "MyPump", "cuenta-*", f"swaps_{plan['dieta']}.json"))
    mapa = json.load(open(mapas[0], encoding="utf-8")) if mapas else {}
    nombres = sorted((v.get("current") or {}).get("name", "") for v in mapa.values())
    chequeo("primer arranque: Dieta ya tiene los dos swaps (mapa local)", nombres == ["Atún al natural", "Ricota descremada"], f"{nombres}")
    chequeo("chat", nat.get("chat_prueba") == 1, f"{nat.get('chat_prueba')}")
    sust = nat.get("sustituciones")
    chequeo("sustitución de ejercicio en la base (SER-14; sin la migración 003 queda solo en el teléfono, como antes)",
            sust == "sin tabla" or any(x.startswith(f"{plan['ex_swap']}:Remo sentado en polea") for x in sust or []), f"{sust}")
    if plan.get("ex_lapida") and sust != "sin tabla":
        chequeo("la de un ejercicio con lápida en la base no revive (se borró después)",
                not any(x.startswith(f"{plan['ex_lapida']}:") for x in sust or []), f"{sust}")
    chequeo("cola anon: nunca se ejecutó (cardio igual)", nat.get("cardio") == plan["cardio_antes"])
    chequeo("cola de un token rotado que ya no resuelve: no se ejecutó", nat.get("chat_rotado") == 0)
    chequeo("write-back: sin la cola de la cuenta ni cachés de sesión, con la marca",
            "mypump_outbox_<TOKEN>" not in alm_n and not any(k.startswith("mypump_sesion_<TOKEN>") for k in alm_n)
            and "mypump_nativa_marca" in alm_n, f"marca {alm_n.get('mypump_nativa_marca', {}).get('valor')}")
    chequeo("write-back: sin la cola de fotos de la cuenta (si vuelve a la Capacitor, no las sube otra vez)",
            "mypump_fotoq_<TOKEN>" not in alm_n, f"{alm_n.get('mypump_fotoq_<TOKEN>')}")
    chequeo("write-back: la cola anon y la del token rotado quedan (no se tomaron)",
            alm_n.get("mypump_outbox_anon", {}).get("ops") == 1 and sum(1 for k in alm_n if k.startswith("mypump_outbox_") and k != "mypump_outbox_anon") == 1)
    corridas = re.findall(r"Fase L corrida (\d+)[^\n]*cola (\d+), por validar (\d+)", reg)
    chequeo("segundo arranque: confirma la escritura y no trae nada", len(corridas) >= 2 and corridas[-1][1:] == ("0", "0")
            and "escritura confirmada 1" in reg, f"{corridas}")
    chequeo("segundo arranque: la base no cambió", {k: v for k, v in seg.items()} == {k: v for k, v in nat.items()})
    chequeo("Capacitor reinstalada encima: no resucita nada en la base",
            vuelta.get("registros") == nat.get("registros") and vuelta.get("chat_prueba") == 1 and vuelta.get("chat_rotado") == 0
            and vuelta.get("swaps") == nat.get("swaps"), f"{vuelta.get('chat_prueba')} chats, {len(vuelta.get('registros', []))} series")
    chequeo("Capacitor reinstalada encima: su cola sigue vacía y la marca sigue",
            alm_v.get("mypump_outbox_<TOKEN>", {}).get("ops", 0) in (0, "no está") and "mypump_nativa_marca" in alm_v)

    estado = leer(os.path.join(salida, "nativa-segundo", "legado"), "estado.json", {})
    recibos = sorted(glob.glob(os.path.join(salida, "nativa-segundo", "legado", "recibos", "*.json"))
                     + glob.glob(os.path.join(salida, "nativa-segundo", "legado", "recibos", "*", "*.json")), key=os.path.basename)
    recibo = json.load(open(recibos[0], encoding="utf-8")) if recibos else {}
    aj = leer(salida, "ajustes-nativa.json", {})
    chequeo("Ajustes: tema oscuro, tipo de día, notificaciones, onboarding, salud y día visualizado",
            aj.get("mypump-theme") == "dark" and aj.get("mypump_tipo_dia") == "entreno" and '"check"' in aj.get("mypump_notif_prefs", "")
            and aj.get("mypump_notif_pedido") == "1" and aj.get("mypump_onboarding_v1") == "1" and aj.get("mypump_health_connected") == "1"
            and aj.get(f"mypump_dia_visualizado_{plan['rutina']}") == plan["otro_dia"], f"{sorted(aj)}")
    # Entreno consume `legado-entreno.json` al cargar (lo aplica y lo borra): si ya no está, se mira lo que quedó aplicado.
    cuenta = (glob.glob(os.path.join(salida, "nativa-nativa", "MyPump", "cuenta-*")) or [""])[0]
    entreno = leer(cuenta, "legado-entreno.json", None)
    if entreno is not None:
        ok = plan["dia"] in entreno.get("sesiones", {}) and entreno.get("descanso") is not None
        detalle = f"sin aplicar todavía: {list(entreno.get('sesiones', {}))}"
    else:
        # El descanso restaurado corre en memoria y su archivo se borra al restaurar, como `restoreRest` de la web: del
        # disco se ve que la Fase L lo trajo; que siga corriendo después del cambio al día visto se ve en 2-nativa.png
        # (y lo exige `loQueDejaLaMigracionSeLeeEntero`).
        sesiones = leer(cuenta, "entreno-sesiones.json", {})
        local = sesiones.get(plan["dia"], {})
        primera = leer(os.path.join(salida, "nativa-nativa", "legado"), "estado.json", {}).get("conteos", {})
        ok = local.get("sesionId") == plan["sesion"] and local.get("inicio") == plan.get("inicio") and primera.get("descansoVigente") is True
        detalle = (f"aplicado: {sorted(sesiones)}, inicio {'igual' if local.get('inicio') == plan.get('inicio') else local.get('inicio')}, "
                   f"descanso {'traído (en memoria, ver 2-nativa.png)' if primera.get('descansoVigente') else 'no'}")
    chequeo("Fase L: la sesión en curso (con su arranque) y el descanso llegaron a Entreno", ok, detalle)
    # MIG-07: el recibo cierra. Lo de después se cuenta con la cola ya vaciada: nada pendiente, ninguna tabla del
    # cliente baja, y el libro reparte exactamente las ops que se leyeron (lo que va a revisar queda en fallidos).
    despues = recibo.get("despues", {})
    antes_srv, despues_srv = recibo.get("servidorAntes") or {}, recibo.get("servidorDespues") or {}
    leidas = sum(recibo.get("antes", {}).get("opsPorKind", {}).values())
    repartidas = sum(v for v in despues.get("libro", {}).values() if isinstance(v, int))
    bajaron = [k for k in antes_srv if despues_srv.get(k, 0) < antes_srv[k]]
    chequeo("Recibo: la cola quedó vacía, ninguna tabla bajó y el libro cierra con lo leído",
            bool(recibo) and despues.get("colaPendientes") == 0 and not bajaron and leidas == repartidas and leidas > 0,
            f"{leidas} ops leídas, {repartidas} en el libro, pendientes {despues.get('colaPendientes')}, fallidos {despues.get('fallidos')}, "
            f"bajaron {bajaron or 'ninguna'}, cambios {dict((k, despues_srv.get(k, 0) - v) for k, v in antes_srv.items() if despues_srv.get(k, 0) != v)}")
    lineas = [f"# Migración en el simulador, corrida {plan.get('run')}", "", f"- Día: {plan.get('hoy')}. Cuenta: `{CUENTA}`.",
              f"- Recibo (corrida 1): antes {json.dumps(recibo.get('antes', {}).get('opsPorKind', {}), ensure_ascii=False)}; "
              f"después {json.dumps(recibo.get('despues', {}).get('libro', {}), ensure_ascii=False)}",
              f"- Estado: {estado.get('corridas')} corridas, escritura hecha {estado.get('escrituraHecha')}, confirmada {estado.get('escrituraConfirmada')}",
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
    t = _token()
    plan = leer(salida, "plan.json")
    for s in (plan.get("swap1"), plan.get("swap3")):
        if s:
            comida, opt, food = s.split("/")
            rpc("mypump_delete_food_swap", {"p_token": t, "p_dieta_id": plan["dieta"], "p_comida_id": comida, "p_opt_idx": int(opt),
                                            "p_food_idx": int(food)})
    print("swaps de prueba borrados")
    if plan.get("rutina"):
        try:
            vivas = (rpc("mypump_get_exercise_swaps", {"p_token": t, "p_rutina_id": plan["rutina"]}) or {}).get("vivas") or {}
            for k in vivas:   # quedan lápidas con la hora de ahora: más nuevas que lo que se sembró
                rpc("mypump_delete_exercise_swap", {"p_token": t, "p_rutina_id": plan["rutina"], "p_ex_id": k, "p_ts": ahora_ms()})
            print(f"sustituciones de ejercicio de prueba borradas: {len(vivas)}")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    a = argv[2:]
    if cmd == "explorar":
        explorar()
    elif cmd == "db" and len(a) == 1:
        db = ubicar_db(a[0])
        if not db:
            return 1
        print(db)
    elif cmd == "token" and len(a) == 1:
        legado_sqlite.sembrar(a[0], {"mypump_token": _token()})
        print("token sembrado")
    elif cmd == "cola-capacitor" and len(a) == 2:
        cola_capacitor(*a)
    elif cmd == "preparar" and len(a) == 2:
        preparar(*a)
    elif cmd == "backend" and len(a) == 2:
        backend(*a)
    elif cmd == "almacen" and len(a) == 3:
        almacen(*a)
    elif cmd == "nativa" and len(a) == 3:
        nativa(*a)
    elif cmd == "ajustes" and len(a) == 3:
        ajustes(*a)
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
