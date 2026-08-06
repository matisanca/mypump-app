#!/usr/bin/env python3
"""
test_centinela_guardrail.py — que la ronda de lun-jue no se pise a sí misma.

QUÉ PROTEGE

1. El guardarrail "se ajustó hace menos de 2 semanas" NO puede dispararse
   contra una sugerencia de la MISMA semana. El bot corre lunes a jueves: si el
   lunes anota `ultimo_ajuste` y el martes lo lee, `semanas_atras` da 0, el
   cliente baja de "ajustar" a "observar" y la sugerencia del lunes se pierde.

2. Dentro de una semana gana el PRIMER día que se sugirió. Si el jueves pisara
   al lunes, el reloj de las 2 semanas correría 3 días de más.

3. `persist_analisis` no borra con NULL una sugerencia ya escrita esta semana:
   es lo que Mati tiene para revisar en el panel.

4. `push.py` no vuelve a mandar un aviso que ya salió, aunque el reporte a
   Supabase haya fallado (corre cada 5 min: sería spam al cliente).

USO:  python3 scripts/test_centinela_guardrail.py
"""
import sys
import json
import pathlib
import tempfile
import importlib.util
from datetime import date

RAIZ = pathlib.Path(__file__).resolve().parent.parent
ok = fail = 0


def t(nombre, fn):
    global ok, fail
    try:
        fn()
        print(f"  ✓ {nombre}")
        ok += 1
    except AssertionError as e:
        print(f"  ✗ {nombre}\n      {e}")
        fail += 1
    except Exception as e:
        print(f"  ✗ {nombre}\n      {type(e).__name__}: {e}")
        fail += 1


def assert_eq(a, b, msg):
    assert a == b, f"{msg}\n      esperado: {b}\n      obtenido: {a}"


def assert_true(c, msg):
    assert c, msg


# ── 1 y 2: la lógica de semanas del guardarrail ──────────────────────────
# Se importa centinela.py de verdad. main() no corre al importar (está bajo
# __main__), así que esto no habla con Supabase ni con Claude.

def cargar_centinela():
    sys.argv = ["centinela.py", "--dry", "--no-db"]
    spec = importlib.util.spec_from_file_location(
        "cent_mod", RAIZ / "pump-centinela" / "centinela.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


C = cargar_centinela()
leer_ua = C._ua_vigente


def guardar_ua(prev, nuevo):
    """Corre _guardar_state de verdad sobre un state en memoria y devuelve lo
    que quedó guardado para ese cliente."""
    st = {"clientes": {"c1": {"ultimo_ajuste": prev}}}
    C.DRY = False          # _guardar_state no escribe nada en dry-run
    C.STATE = str(pathlib.Path(tempfile.mkdtemp()) / "state.json")
    C._guardar_state(st, date(2026, 8, 6), {"c1": nuevo})
    return st["clientes"]["c1"]["ultimo_ajuste"]


LUN = date(2026, 8, 3)
MAR = date(2026, 8, 4)
JUE = date(2026, 8, 6)
W0 = "2026-08-03"
W_ANT = "2026-07-27"

print("Guardarrail del centinela")

t("el martes NO se bloquea con la sugerencia del lunes", lambda: (
    assert_eq(leer_ua({"fecha": "2026-08-03", "semana": W0}, MAR, W0), None,
              "el guardarrail se disparo contra si mismo")
))

t("una entrada vieja SIN campo 'semana' tambien se detecta por fecha", lambda: (
    # El state.json ya escrito en produccion no tiene 'semana'. Si el fallback
    # por semana ISO no funcionara, el bug seguiria vivo hasta la semana que viene.
    assert_eq(leer_ua({"fecha": "2026-08-03"}, MAR, W0), None,
              "no detecto la misma semana sin el campo nuevo")
))

t("una sugerencia de la semana pasada SI bloquea", lambda: (
    assert_eq((leer_ua({"fecha": "2026-07-30", "semana": W_ANT}, MAR, W0) or {}).get("semanas_atras"),
              0, "semanas_atras mal calculado"),
    # 0 < 2 -> el guardarrail de analisis.py se activa, que es lo que se quiere
    assert_true(leer_ua({"fecha": "2026-07-30", "semana": W_ANT}, MAR, W0) is not None,
                "descarto una sugerencia de OTRA semana")
))

t("a las 3 semanas ya no bloquea", lambda: (
    assert_eq(leer_ua({"fecha": "2026-07-13", "semana": "2026-07-13"}, MAR, W0)["semanas_atras"],
              3, "semanas_atras mal calculado a 3 semanas")
))

t("una fecha corrupta no rompe la ronda", lambda: (
    assert_eq(leer_ua({"fecha": "ayer"}, MAR, W0), None, "no tolero la fecha rota")
))

t("dentro de la semana gana el PRIMER dia", lambda: (
    assert_eq(guardar_ua({"fecha": "2026-08-03", "semana": W0},
                         {"fecha": "2026-08-06", "semana": W0})["fecha"],
              "2026-08-03", "el jueves piso al lunes y corrio el reloj 3 dias")
))

t("una semana nueva SI pisa a la anterior", lambda: (
    assert_eq(guardar_ua({"fecha": "2026-07-30", "semana": W_ANT},
                         {"fecha": "2026-08-03", "semana": W0})["fecha"],
              "2026-08-03", "no actualizo al pasar de semana")
))


# ── 3: persist_analisis no degrada la sugerencia ─────────────────────────
preservar = C._preservar_ajuste

print("\nPersistencia del analisis semanal")

t("una corrida posterior con None no borra la sugerencia del lunes", lambda: (
    assert_eq(preservar(None, None, "subir 150 kcal", "hablalo asi"),
              ("subir 150 kcal", "hablalo asi"), "se perdio la sugerencia")
))

t("una sugerencia nueva SI pisa a la vieja", lambda: (
    assert_eq(preservar("bajar 100 kcal", "nuevo", "subir 150 kcal", "viejo"),
              ("bajar 100 kcal", "nuevo"), "no acepto informacion mas fresca")
))

t("sin nada previo queda en None (no se inventa)", lambda: (
    assert_eq(preservar(None, None, None, None), (None, None), "invento una sugerencia")
))


# ── 4: la libreta de push ────────────────────────────────────────────────
print("\nLibreta de entregados de push.py")


def cargar_push():
    spec = importlib.util.spec_from_file_location(
        "push_mod", RAIZ / "pump-centinela" / "push.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


P = cargar_push()


def _escribir_ledger(regs):
    with open(P.LEDGER, "w") as f:
        for r in regs:
            f.write(json.dumps(r) + "\n")


def _con_ledger(fn, crear=True):
    """Corre fn con LEDGER apuntando a un archivo temporal."""
    d = tempfile.mkdtemp()
    orig = P.LEDGER
    P.LEDGER = str(pathlib.Path(d) / ".push_entregados")
    try:
        fn()
    finally:
        P.LEDGER = orig


t("un id anotado se reconoce en la corrida siguiente", lambda: _con_ledger(lambda: (
    P.anotar_entregado("abc-123"),
    assert_true("abc-123" in P.cargar_entregados(), "no recordo el aviso ya entregado"),
)))

t("un id que nunca salio NO figura", lambda: _con_ledger(lambda: (
    P.anotar_entregado("abc-123"),
    assert_true("otro-id" not in P.cargar_entregados(), "invento un entregado"),
)))

t("lo de hace mas de 7 dias se poda", lambda: _con_ledger(lambda: (
    _escribir_ledger([{"id": "viejo", "ts": 0},
                      {"id": "nuevo", "ts": int(__import__("time").time())}]),
    assert_eq(P.cargar_entregados(), {"nuevo"}, "no podo lo viejo"),
)))

t("una linea corrupta no voltea la corrida", lambda: _con_ledger(lambda: (
    open(P.LEDGER, "w").write('{"id":"bueno","ts":%d}\n{roto\n' % int(__import__("time").time())),
    assert_eq(P.cargar_entregados(), {"bueno"}, "se cayo con una linea a medio escribir"),
)))

t("sin libreta todavia devuelve vacio, no explota", lambda: _con_ledger(lambda: (
    assert_eq(P.cargar_entregados(), set(), "no tolero la primera corrida"),
), crear=False))


print(f"\n{ok} pasaron, {fail} fallaron\n")
sys.exit(1 if fail else 0)
