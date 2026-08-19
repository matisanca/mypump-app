#!/usr/bin/env python3
"""test_aviso_escalacion.py — que un 'urgente' NUNCA quede en silencio

POR QUE EXISTE
La mig 057 le saco `ambito='general'` al trigger 019 que avisaba por WhatsApp
—correcto, si no eran ~60 mensajes por semana— pero NADA lo reemplazo para las
escalaciones. Durante dos semanas el sistema hizo esto:

  cliente escribe algo medico -> la IA clasifica 'urgente' -> NO publica nada
  (correcto) -> marca escalado=True -> y ahi termina. Mati nunca se entera.

O sea: silencio absoluto justo en la emergencia. Se descubrio el 18-ago porque
Mati pregunto por que no le habia llegado nada de dos clientes escalados.
"""
import json
import os
import pathlib
import sys
import tempfile

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))
os.environ.setdefault("META_ACCESS_TOKEN", "x")
os.environ.setdefault("META_PHONE_NUMBER_ID", "x")
os.environ.setdefault("COACH_PHONE_NUMBER", "x")

import chat_worker as W  # noqa: E402

fallas = 0
enviados = []


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


W.whatsapp = lambda t: (enviados.append(t), True)[1]
W.AVISADOS = pathlib.Path(tempfile.mkdtemp()) / ".chat_avisados"


def r(clase, cid="c1", nombre="Juan Perez", mensaje="hola"):
    return {"clase": clase, "cliente_id": cid, "nombre": nombre,
            "mensaje": mensaje, "respuesta": None}


print("\n1. Un urgente SIEMPRE avisa, y avisa solo")
enviados.clear(); W.AVISADOS.unlink(missing_ok=True)
W.avisar_escalaciones([r("urgente", mensaje="me duele el pecho desde ayer")])
check("mando exactamente 1 WhatsApp", len(enviados) == 1, f"mando {len(enviados)}")
check("dice URGENTE", "URGENTE" in (enviados[0] if enviados else ""))
check("lleva el mensaje textual del cliente",
      "me duele el pecho" in (enviados[0] if enviados else ""))
check("aclara que la IA no contesto",
      "no le contest" in (enviados[0] if enviados else "").lower())

print("\n2. El urgente NO respeta el silencio — avisa aunque ya se haya avisado")
enviados.clear()
W.avisar_escalaciones([r("urgente", mensaje="me desmaye en el gym")])
W.avisar_escalaciones([r("urgente", mensaje="me desmaye otra vez")])
check("dos urgentes seguidos = dos avisos", len(enviados) == 2, f"mando {len(enviados)}")

print("\n3. Los 'derivar' se agrupan en UN mensaje por corrida")
enviados.clear(); W.AVISADOS.unlink(missing_ok=True)
W.avisar_escalaciones([r("derivar", "a", "Ana", "puedo cambiar el jueves?"),
                       r("derivar", "b", "Beto", "me subio el peso"),
                       r("derivar", "c", "Ceci", "consulta de dieta")])
check("3 escalados = 1 solo WhatsApp", len(enviados) == 1, f"mando {len(enviados)}")
check("los nombra a los tres",
      all(n in (enviados[0] if enviados else "") for n in ("Ana", "Beto", "Ceci")))

print("\n4. No repite el aviso del mismo cliente")
enviados.clear()
W.avisar_escalaciones([r("derivar", "a", "Ana", "otra consulta")])
check("Ana ya avisada -> no se repite", len(enviados) == 0, f"mando {len(enviados)}")
enviados.clear()
W.avisar_escalaciones([r("derivar", "z", "Zoe", "primera vez")])
check("un cliente nuevo SI avisa", len(enviados) == 1, f"mando {len(enviados)}")

print("\n5. Los 'simple' no molestan a nadie")
enviados.clear()
W.avisar_escalaciones([r("simple", "q", "Quique", "gracias!")])
check("un simple no manda nada", len(enviados) == 0, f"mando {len(enviados)}")

print("\n6. Si el WhatsApp falla, NO se anota como avisado")
# Si se anotara igual, el reintento de la corrida siguiente quedaria callado por
# el silencio de 12h y la escalacion se perderia del todo.
W.AVISADOS.unlink(missing_ok=True)
W.whatsapp = lambda t: False
W.avisar_escalaciones([r("derivar", "f", "Falla", "algo")])
libreta = {}
try:
    libreta = json.loads(W.AVISADOS.read_text())
except Exception:
    pass
check("un envio fallido no marca al cliente como avisado", "f" not in libreta,
      f"libreta quedo con {list(libreta)}")

print("\n7. main() llega hasta el final (no alcanza con que el codigo exista)")
# Esta seccion era un grep sobre el texto del archivo: buscaba la cadena
# "avisados = avisar_escalaciones(resultados)" y daba verde si aparecia. El
# 18-ago el commit dc8eb3a metio ese bloque a nivel de MODULO en el medio de
# main(): main quedo cortada en el ThreadPoolExecutor y sus ultimas 60 lineas
# —guardar borradores, agendar respuestas, anotar cupo, avisar a Mati— quedaron
# colgando DENTRO de avisar_escalaciones, despues de su return. Codigo muerto.
# El grep seguia encontrando la cadena, asi que los 14 checks pasaban en verde
# mientras en produccion cada mensaje se mandaba a OpenAI y se tiraba.
#
# Ahora se ejecuta main() de verdad con todo stubbeado, y se mira QUE HIZO.
import ast  # noqa: E402

FUENTE = (RAIZ / "pump-centinela" / "chat_worker.py").read_text()

# 7a. Ningun bloque queda despues de un return, en NINGUNA funcion. Este es el
#     chequeo que hubiera cazado el bug de una, y caza toda la familia.
def _muertas(arbol):
    malas = []
    for nodo in ast.walk(arbol):
        cuerpos = []
        for campo in ("body", "orelse", "finalbody"):
            b = getattr(nodo, campo, None)
            if isinstance(b, list):
                cuerpos.append(b)
        for b in cuerpos:
            for i, st in enumerate(b[:-1]):
                if isinstance(st, (ast.Return, ast.Raise, ast.Continue, ast.Break)):
                    malas.append((st.lineno, b[i + 1].lineno))
    return malas

muertas = _muertas(ast.parse(FUENTE))
check("no hay codigo despues de un return", not muertas,
      "inalcanzable: " + ", ".join(f"linea {b} (el return esta en {a})" for a, b in muertas))

# 7b. main() corre entera y hace las cuatro cosas que tiene que hacer.
llamadas = {"rpc": [], "cupo": [], "aviso": []}
W.SB_KEY = "clave-de-prueba"      # sin esto main() sale en la primera guarda
W.CORRER = True
W.AUTO = True
W.CUPO_DIARIO = 100
W.cupo_usado = lambda: 0
W.anotar_cupo = lambda n: llamadas["cupo"].append(n)
W.avisar_escalaciones = lambda res: (llamadas["aviso"].append(len(res)), 1)[1]
W.procesar = lambda fila: {
    "clase": fila["_clase"], "cliente_id": fila["cliente_id"],
    "respuesta_a": fila["mensaje_id"], "nombre": fila.get("nombre"),
    "mensaje": fila["mensaje"], "respuesta": fila.get("_resp"),
    "motivo": "test", "bloqueos": None, "modelo": "test",
}

COLA = [
    {"cliente_id": "c1", "mensaje_id": "m1", "nombre": "Ana", "mensaje": "gracias!",
     "_clase": "simple", "_resp": "de nada, ana"},
    {"cliente_id": "c2", "mensaje_id": "m2", "nombre": "Beto", "mensaje": "me duele el pecho",
     "_clase": "urgente", "_resp": None},
]


def _sb_falso(fn, args=None):
    llamadas["rpc"].append(fn)
    if fn == "mypump_chat_para_responder":
        return COLA
    if fn == "mypump_chat_programar":
        return "id-programado"
    return None


W._sb = _sb_falso
salida = W.main()

check("main() devuelve 0", salida == 0, f"devolvio {salida!r}")
check("agenda la respuesta automatica del 'simple'",
      "mypump_chat_programar" in llamadas["rpc"],
      "nunca se llamo a mypump_chat_programar: el cliente no recibe nada")
check("guarda el borrador del 'urgente' en la bandeja",
      "mypump_chat_borrador_guardar" in llamadas["rpc"],
      "no queda nada en 💬 Chats del Cerebro")
check("descuenta el cupo diario", llamadas["cupo"] == [2],
      f"anotar_cupo recibio {llamadas['cupo']}")
check("avisa a Mati de las escalaciones", llamadas["aviso"] == [2],
      "avisar_escalaciones no se ejecuto: un urgente queda en silencio")

# 7c. Mutante: si a main() le cortan la cola, 7b tiene que ponerse en rojo.
_ORIG = W.main
_corte = ast.parse(FUENTE)
for _n in _corte.body:
    if isinstance(_n, ast.FunctionDef) and _n.name == "main":
        for _i, _st in enumerate(_n.body):
            if isinstance(_st, ast.With):       # el ThreadPoolExecutor
                _n.body = _n.body[: _i + 1]
                break
_ns = dict(W.__dict__)
exec(compile(ast.fix_missing_locations(_corte), "<mutante>", "exec"), _ns)
llamadas["rpc"].clear(); llamadas["cupo"].clear(); llamadas["aviso"].clear()
_ns["_sb"] = _sb_falso
_ns["procesar"] = W.procesar
_ns["cupo_usado"] = lambda: 0
_ns["anotar_cupo"] = W.anotar_cupo
_ns["avisar_escalaciones"] = W.avisar_escalaciones
_ns["SB_KEY"] = "clave-de-prueba"
_ns["CORRER"] = True
_ns["AUTO"] = True
_ns["CUPO_DIARIO"] = 100
_ns["main"]()
check("MUTANTE: cortarle la cola a main() rompe el test",
      "mypump_chat_borrador_guardar" not in llamadas["rpc"] and not llamadas["aviso"],
      "el test no distingue una main() completa de una truncada — es un grep disfrazado")

print()
if fallas:
    print(f"✗ {fallas} fallo(s): una escalacion puede quedar en silencio\n")
    sys.exit(1)
print("✓ ninguna escalacion queda en silencio\n")
