#!/usr/bin/env python3
"""Lee y siembra el localStorage de WebKit que dejó la app Capacitor (pruebas de migración, Fase 0).

WebKit guarda cada origen en un SQLite `ItemTable(key TEXT, value BLOB)` con el valor en UTF-16LE. Lo reciente
vive en el `-wal`, así que para LEER se copian db + wal + shm a un temporal (nunca se abre el original mientras la
app podría estar viva). SEMBRAR escribe sobre el original y solo se usa con la app cerrada, en el simulador.

Uso:
  python3 -I legado_sqlite.py dump <localstorage.sqlite3>              → JSON {clave: valor} por stdout
  python3 -I legado_sqlite.py sembrar <localstorage.sqlite3> <a.json>  → escribe esas claves
  python3 -I legado_sqlite.py semilla --token T --rutina R [--token-viejo V] > semilla.json
"""
import json
import os
import shutil
import sqlite3
import sys
import tempfile


def dump(db_path):
    tmp = tempfile.mkdtemp(prefix="legado-")
    try:
        copia = os.path.join(tmp, "ls.sqlite3")
        shutil.copy2(db_path, copia)
        for suf in ("-wal", "-shm"):
            if os.path.exists(db_path + suf):
                shutil.copy2(db_path + suf, copia + suf)
        con = sqlite3.connect(copia)
        filas = con.execute("SELECT key, value FROM ItemTable").fetchall()
        con.close()
        return {k: (v.decode("utf-16-le") if isinstance(v, bytes) else v) for k, v in filas}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def sembrar(db_path, items):
    con = sqlite3.connect(db_path)
    with con:
        for k, v in items.items():
            con.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (k, v.encode("utf-16-le")))
    con.close()


def semilla(token, rutina, token_viejo=None):
    """Casos que no se producen a mano: outbox de 500 ops con los 9 kinds, cola huérfana, fotos, unicode, 1 MB."""
    import random
    rnd = random.Random(42)
    kinds = ["carga", "estado", "swap", "swap_del", "habito", "comida", "peso", "checkin", "chat"]
    ops = []
    t0 = 1791900000000
    for i in range(500):
        kind = kinds[i % len(kinds)]
        dia = f"b2d{1 + i % 5}"
        if kind == "carga":
            payload = {"sesionId": None, "diaId": dia, "semana": 3, "datos": {"diaId": dia, "ejercicioId": f"press-banca-{dia}-{i % 7}",
                       "ejercicioNombre": "Press inclinado 45° — mancuernas", "serie": 1 + i % 4, "peso": "62.5", "reps": "8", "rir": 0, "notas": None}}
            dk = f"carga_{dia}_press-banca-{dia}-{i % 7}_{i % 4}"
        elif kind == "estado":
            payload = {"sesionId": None, "semana": 3, "diaId": dia, "exId": f"remo-{dia}-{i % 5}", "seriesObjetivo": 3, "status": "completo", "manual": False}
            dk = f"estado_{dia}_remo-{dia}-{i % 5}"
        elif kind in ("swap", "swap_del"):
            payload = {"dietaId": "00000000-0000-4000-8000-000000000d1e", "comidaId": "desayuno", "optIdx": i % 4, "foodIdx": i % 3}
            if kind == "swap":
                payload["food"] = {"name": "Ricota descremada", "qty": 150, "unit": "g", "kcal": 207, "prot": 17, "carb": 6, "fat": 12,
                                   "_orig": {"name": "Queso untable light", "qty": 60, "unit": "g"}}
            dk = f"swap_00000000-0000-4000-8000-000000000d1e_desayuno_{i % 4}_{i % 3}"
        elif kind == "habito":
            payload = {"fecha": f"2026-10-{1 + i % 13:02d}", "campo": "vasos_agua", "valor": str(i % 12)}
            dk = f"habito|{payload['fecha']}|vasos_agua"
        elif kind == "comida":
            payload = {"fecha": f"2026-10-{1 + i % 13:02d}", "comidaId": "almuerzo", "opcion": "Opción B", "estado": "comido", "excl": [1]}
            dk = f"comida|{payload['fecha']}|almuerzo"
        elif kind == "peso":
            payload = {"fecha": f"2026-10-{1 + i % 13:02d}", "valor": 81.4}
            dk = f"peso_{payload['fecha']}"
        elif kind == "checkin":
            payload = {"fecha": "2026-10-12", "datos": {"energia": 4, "descanso": 3, "hambre": 2, "adherencia": 5, "nota": "Semana dura, dormí poco 😴"}}
            dk = "checkin_2026-10-12"
        else:
            texto = f"Mati, ¿cambio el jalón por remo? ñandú {i}"
            payload = {"contenido": texto}
            dk = f"chat_{t0 + i}_{texto[:40]}"
        ops.append({"_id": f"{t0 + i}_{i}", "kind": kind, "payload": payload, "dedupeKey": dk, "tries": rnd.choice([0, 0, 1, 3]), "ts": t0 + i})

    items = {
        "mypump_token": token,
        f"mypump_outbox_{token}": json.dumps(ops, ensure_ascii=False),
        f"mypump_fotoq_{token}": json.dumps({"2026-10-12|frente": {"pose": "frente", "fecha": "2026-10-13",
                                             "dataUrl": "data:image/jpeg;base64," + "/9j/" + "A" * 2000, "intentos": 1}}),
        f"mypump_exercise_swaps_{rutina}": json.dumps({
            "jalon-al-pecho-b2d1-0": {"original": {"slug": "Wide-Grip_Lat_Pulldown", "nombre": "Jalón al pecho", "images": None},
                                      "current": {"slug": "Seated_Cable_Rows", "nombre": "Remo sentado en polea", "equipment": "cable",
                                                  "images": {"eccentric": "https://x/e.jpg", "concentric": "https://x/c.jpg"}},
                                      "fijado": True, "semana": 2, "diaId": "b2d1"},
            "curl-femoral-b2d3-2": {"original": {"slug": "Lying_Leg_Curls", "nombre": "Curl femoral acostado", "images": None},
                                    "current": {"slug": "Seated_Leg_Curl", "nombre": "Curl femoral sentado", "equipment": "machine", "images": None},
                                    "fijado": False, "semana": 3, "diaId": "b2d3"},
            "press-inclinado-b2d2-1": {"original": {"slug": "Incline_Dumbbell_Press", "nombre": "Press inclinado 45° — mancuernas"},
                                       "current": {"slug": "Smith_Incline", "nombre": "Press inclinado en Smith 🏋️"}, "semana": 1, "diaId": "b2d2"},
        }, ensure_ascii=False),
        f"mypump_offline_{token}": json.dumps({"info": {"cliente_id": "test-nativa-ios", "nombre": "Test Nativa", "perfil": "natural"},
                                               "rutina": {"id": rutina, "version": 3, "semana_actual": 3}, "dieta": None, "ts": t0}),
        f"mypump_sesion_{token}_b2d1": "6f0c2a8e-5b1d-4c7e-9a3f-2d8e1b7c4a90",
        f"mypump_sesion_{token}_b2d1_semana": "3",
        f"mypump_sesion_{token}_b2d1_start": str(t0),
        f"mypump_rest_{token}": json.dumps({"endsAt": t0 + 90000, "target": 90, "autoCloseAt": None}),
        "mypump_tipo_dia": "entreno",
        "mypump_notif_prefs": json.dumps({"check": {"on": True, "hora": 11, "min": 0}}),
        "mypump_notif_pedido": "1",
        "mypump_onboarding_v1": "1",
        "mypump_health_connected": "1",
        "mypump_health_backfill_off": json.dumps({"off": 20, "alcance": 60}),
        "mypump_valor_grande": "x" * (1024 * 1024),
        "mypump_unicode_∂ñ😀": "valor con \u0000 nulo, emoji 😀 y acento á",
    }
    if token_viejo:
        items[f"mypump_outbox_{token_viejo}"] = json.dumps(ops[:3], ensure_ascii=False)
    items["mypump_outbox_anon"] = json.dumps(ops[3:5], ensure_ascii=False)
    return items


def main(argv):
    if len(argv) >= 3 and argv[1] == "dump":
        json.dump(dump(argv[2]), sys.stdout, ensure_ascii=False, sort_keys=True, indent=1)
    elif len(argv) >= 4 and argv[1] == "sembrar":
        with open(argv[3], encoding="utf-8") as f:
            sembrar(argv[2], json.load(f))
    elif len(argv) >= 2 and argv[1] == "semilla":
        args = dict(zip(argv[2::2], argv[3::2]))
        json.dump(semilla(args["--token"], args["--rutina"], args.get("--token-viejo")), sys.stdout, ensure_ascii=False)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
