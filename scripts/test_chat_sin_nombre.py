#!/usr/bin/env python3
"""test_chat_sin_nombre.py — el chat va a Codex SIN el nombre del cliente, y la respuesta vuelve con él.

POR QUÉ EXISTE (Mati, 14-oct-2026): "pasar sus mensajes antes por IA local, quitar el nombre de la persona, responderle
y volver a agregarle el nombre, usando la IA local de la Mac Mini, pero que siga usando Codex". Si mañana alguien arma
un prompt nuevo y se olvida de tapar, nada se rompe a la vista: el nombre vuelve a viajar. Por eso un test.

Corre en el Mini (usa agent/medical/deid_qwen de agentkit-coach y el Qwen local), sobre una copia:
  mkdir -p /tmp/chatdeid && cp ~/pump-centinela/{chat_worker,deid_chat,validador_chat,sugerir_pendientes}.py /tmp/chatdeid/
  ~/agentkit-coach/venv/bin/python /tmp/chatdeid/test_chat_sin_nombre.py [--sin-qwen]
No llama a Supabase ni a Codex: los dos se reemplazan acá.
"""
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
for k in ("META_ACCESS_TOKEN", "META_PHONE_NUMBER_ID", "COACH_PHONE_NUMBER"):
    os.environ.setdefault(k, "x")

import chat_worker as W  # noqa: E402
import deid_chat as DC  # noqa: E402

SIN_QWEN = "--sin-qwen" in sys.argv
fallas = 0


def chequear(ok, que):
    global fallas
    print(("  ✓ " if ok else "  ✗ ") + que)
    if not ok:
        fallas += 1


W._FICHAS = {"c-prueba": {"nombre": "Jonathan", "apellido": "Pérez Achával", "whatsapp": "5491155550000", "edad": 34}}
if SIN_QWEN:
    _tapar = DC.tapar
    DC.tapar = lambda t, d, usar_qwen=True: _tapar(t, d, usar_qwen=False)

FILA = {
    "cliente_id": "c-prueba", "nombre": "Jonathan Pérez", "mensaje_id": "00000000-0000-4000-8000-000000000001",
    "mensaje": "el cardio lo hago antes o después de entrenar?",
    "contexto": [
        {"autor": "coach", "texto": "buenas! cómo venís con la semana?"},
        {"autor": "cliente", "texto": "hola mati, soy Jonathan Pérez. el cardio lo hago antes o después de entrenar? "
                                      "cualquier cosa llamame al 11 5555-0000. trabajo en el Banco Galicia y salgo tarde"},
    ],
    "revision": None, "plan": None,
}
visto = {}


def codex_falso(respuesta):
    def f(prompt):
        visto["prompt"] = prompt
        return respuesta, None
    return f


print("1. A Codex no le llega el nombre, y la respuesta vuelve con él" + (" (sin Qwen)" if SIN_QWEN else ""))
W.llamar_codex = codex_falso({"clase": "derivar", "sugerencia": "{nombre} hacelo después de entrenar",
                              "motivo": "pregunta por el cardio"})
r = W.procesar(FILA)
p = visto.get("prompt", "")
for prohibido in ("Jonathan", "Pérez", "Perez", "Achával", "5555-0000", "1155550000"):
    chequear(prohibido.lower() not in p.lower(), f"el prompt no trae «{prohibido}»")
chequear("cardio" in p and "entrenar" in p, "el prompt conserva «cardio» y «entrenar»")
if not SIN_QWEN:
    chequear("Galicia" not in p, "Qwen tapó el trabajo con nombre propio («Banco Galicia»)")
chequear(r["clase"] == "derivar" and r["sugerencia"] == "Jonathan hacelo después de entrenar",
         f"la sugerencia vuelve con el nombre de pila: {r.get('sugerencia')!r}")
chequear(r["nombre"] == "Jonathan Pérez", "el aviso a Mati sigue con el nombre (no va a ningún modelo)")

print("2. Un dato tapado que el modelo inventó no se publica")
W.llamar_codex = codex_falso({"clase": "simple", "respuesta": "dale [NOMBRE_9]", "motivo": "acuse"})
r = W.procesar(FILA)
chequear(r["clase"] == "derivar" and r["respuesta"] is None and "dato tapado" in r["motivo"],
         f"queda para Mati: {r['motivo']!r}")

print("3. Si no se puede tapar, no va a la IA")
visto.clear()
_original = DC.tapar
DC.tapar = lambda t, d, usar_qwen=True: (None, {}, ["quedaron identificadores (NOMBRE)"])
W.llamar_codex = codex_falso({"clase": "simple", "respuesta": "dale", "motivo": "acuse"})
r = W.procesar(FILA)
DC.tapar = _original
chequear("prompt" not in visto, "Codex no se llamó")
chequear(r["clase"] == "derivar" and "no fue a la IA" in r["motivo"], f"queda para Mati: {r['motivo']!r}")

print("4. Sin Qwen, lo conocido se tapa igual y la IA sigue")
D = DC.D
_qwen = D.pasada_qwen


def qwen_caido(*a, **k):
    raise D.DeidServicioCaido("simulado")


D.pasada_qwen = qwen_caido
visto.clear()
W.llamar_codex = codex_falso({"clase": "simple", "respuesta": "dale, después de entrenar", "motivo": "acuse"})
r = W.procesar(FILA)
D.pasada_qwen = _qwen
p = visto.get("prompt", "")
chequear(bool(p) and "jonathan" not in p.lower() and "5555-0000" not in p, "se mandó sin el nombre ni el teléfono")
chequear(r["clase"] == "simple" and r["respuesta"] == "dale, después de entrenar", "la respuesta sale igual")

print()
print("TODO OK" if not fallas else f"{fallas} FALLAS")
sys.exit(1 if fallas else 0)
