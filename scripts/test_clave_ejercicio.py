#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_clave_ejercicio.py — la clave de un ejercicio es UNA función en tres lenguajes

POR QUE EXISTE
Desde la 072 (19-sep-2026) el historial de cargas se busca por CLAVE del
ejercicio efectivo —lo que el cliente realmente hizo, normalizado— y no por el
id del slot de la rutina. Esa clave se calcula en TRES lugares:

    SQL     mypump_clave_ejercicio()   (columna generada + RPC)     mig 072
    JS      claveEjercicio()           (la app pide el historial)   cliente.html
    Python  clave_ejercicio()          (senales_carga del centinela) centinela.py

Si uno diverge, el historial se parte en silencio: lo que escribe uno no
matchea lo que lee el otro, y el cliente vuelve a ver "Primera vez con este
ejercicio" para algo que hace hace meses. Verificado sobre los 1.246 nombres
reales de la base el 19-sep: 0 diferencias. Este test fija los vectores que
cubren cada regla y corre JS y Python de verdad (SQL no tiene base acá: se
verifica que el texto de la 072 use las mismas reglas, en test-historial-por-identidad.mjs).

USO:  python3 scripts/test_clave_ejercicio.py
"""
import json
import pathlib
import re
import subprocess
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


# ── Python: importar SOLO la función, sin arrancar el centinela ──────────────
src = (RAIZ / "pump-centinela" / "centinela.py").read_text(encoding="utf-8")
m = re.search(r"^def clave_ejercicio\(nombre\):.*?(?=^def |\Z)", src, re.S | re.M)
check("centinela.py define clave_ejercicio()", m is not None)
ns = {}
exec(m.group(0), ns)  # noqa: S102 — es nuestro propio código, extraído del archivo
clave_py = ns["clave_ejercicio"]

# ── JS: la función real de cliente.html, ejecutada con node ─────────────────
html = (RAIZ / "public" / "cliente.html").read_text(encoding="utf-8")
mj = re.search(r"function claveEjercicio\(nombre\) \{.*?\n\}", html, re.S)
check("cliente.html define claveEjercicio()", mj is not None)

VECTORES = [
    "Curl de bíceps con mancuernas",
    "Jalón al pecho", "Jalon al pecho",
    "Extensión de cuádriceps", "Pájaros en máquina", "Curl araña",
    "Press inclinado con mancuernas (pectoral superior)", "Press inclinado con mancuernas",
    "Extensión en polea con cuerda agarre neutro (cabeza medial)",
    "Curl inclinado con mancuernas a 45°",
    "  Remo   en polea — sentado, agarre neutro ",
    "Cruce de poleas alto→bajo",
    "Press plano con mancuernas", "Curl femoral sentado", "Curl femoral tumbado",
    "", None,
    "Sentadilla búlgara (cuádriceps / glúteo) 3x10",
    "PRESS MILITAR EN MÁQUINA", "press militar en maquina",
    "Elevación de talón sentado con mancuernas (gastrocnemio)",
    "Hip thrust con barra (máquina o piso)",
    "Abductores en máquina (glúteo medio / glúteo menor)",
    "Ñoquis de pecho",  # ñ al principio, para la tabla de acentos
    "Curl Zottman con mancuernas (braquiorradial)",
]


def clave_js(nombres):
    prog = mj.group(0) + "\n;process.stdout.write(JSON.stringify(JSON.parse(process.argv[1]).map(claveEjercicio)));"
    out = subprocess.run(["node", "-e", prog, json.dumps(nombres)], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)


print("\n1. Python y JS dan lo mismo en cada vector")
js = clave_js(VECTORES)
for n, cj in zip(VECTORES, js):
    cp = clave_py(n)
    check(f"{(n or repr(n))[:48]!s:48s} → {cp!r}", cp == cj, f"python={cp!r} js={cj!r}")

print("\n2. Las reglas, una por una (Python)")
check("acentos: Jalón == Jalon", clave_py("Jalón al pecho") == clave_py("Jalon al pecho"))
check("paréntesis es el músculo, no el ejercicio",
      clave_py("Press inclinado con mancuernas (pectoral superior)") == clave_py("Press inclinado con mancuernas"))
check("grados, guiones y espacios no cuentan",
      clave_py("  Remo   en polea — sentado, agarre neutro ") == "remo en polea sentado agarre neutro")
check("ejercicios distintos siguen distintos",
      clave_py("Curl femoral sentado") != clave_py("Curl femoral tumbado"))
check("vacío y None → ''", clave_py("") == "" and clave_py(None) == "")

print("\n3. El corpus real, si está a mano (JS vs SQL, generado el 19-sep)")
corpus = pathlib.Path("/private/tmp/claude-501/-Users-matiassancari-Desktop-nutriplan/08cc11e6-6457-499c-98e0-277de202025c/scratchpad/claves_sql.json")
if corpus.exists():
    pares = json.loads(corpus.read_text(encoding="utf-8"))
    nombres = [p[0] for p in pares]
    js_all = clave_js(nombres)
    dif_py = [(n, s, clave_py(n)) for (n, s) in pares if clave_py(n) != s]
    dif_js = [(n, s, j) for (n, s), j in zip(pares, js_all) if j != s]
    check(f"Python == SQL sobre {len(pares)} nombres reales", not dif_py, str(dif_py[:3]))
    check(f"JS == SQL sobre {len(pares)} nombres reales", not dif_js, str(dif_js[:3]))
else:
    print("  · (corpus real no disponible en este checkout, salteo)")

print("\n4. senales_carga agrupa por clave y colapsa a una por semana")
sc = re.search(r"^def senales_carga\(prog\):.*?(?=^def |\Z)", src, re.S | re.M).group(0)
check("agrupa por clave_ejercicio(r['ejercicio'])", 'clave_ejercicio(r.get("ejercicio"))' in sc,
      "volvió a agrupar por ejercicio_id: una sustitución se lee como caída de fuerza")
check("no agrupa por ejercicio_id", 'setdefault(eid' not in sc)
check("colapsa a un punto por semana antes de comparar", "por_sem" in sc and "pts[-4:-2]" in sc,
      "sin colapsar, 'últimas 2 vs 2 anteriores' pasa a ser 1 semana contra 1 cuando el ejercicio va 2 veces por semana")
check("rotula con el nombre de la sesión más reciente", "sem_max" in sc)

print()
if fallas:
    print(f"✗ {fallas} fallo(s): la clave dejó de ser una sola función\n")
    sys.exit(1)
print("✓ una clave, tres lenguajes, mismo resultado\n")
