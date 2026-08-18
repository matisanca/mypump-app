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

print("\n7. El worker llama al aviso (no solo existe la funcion)")
SRC = (RAIZ / "pump-centinela" / "chat_worker.py").read_text()
# Ojo con buscar "avisar_escalaciones(resultados)" a secas: eso tambien matchea
# la linea del `def`, que esta ANTES del guardado, y el chequeo de orden daba un
# falso positivo. Hay que apuntar al call site.
LLAMADA = "avisados = avisar_escalaciones(resultados)"
check("avisar_escalaciones se invoca en el flujo", LLAMADA in SRC,
      "la funcion existe pero nadie la llama: seria silencio igual que antes")
check("se avisa DESPUES de guardar los borradores",
      LLAMADA in SRC and SRC.index("mypump_chat_borrador_guardar") < SRC.index(LLAMADA),
      "si avisa antes, puede avisar de algo que no se guardo")
check("el resultado lleva nombre y mensaje",
      '"nombre": fila.get("nombre")' in SRC and '"mensaje": fila.get("mensaje"' in SRC,
      "sin esto el aviso muere con KeyError o manda un id opaco")

print()
if fallas:
    print(f"✗ {fallas} fallo(s): una escalacion puede quedar en silencio\n")
    sys.exit(1)
print("✓ ninguna escalacion queda en silencio\n")
