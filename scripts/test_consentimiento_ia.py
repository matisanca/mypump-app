#!/usr/bin/env python3
"""test_consentimiento_ia.py — quien dijo que NO a la IA en la app no pasa por ningún modelo

POR QUE EXISTE
Apple (guía 5.1.2(i)) pide permiso explícito antes de compartir datos con una IA de
terceros. Mati eligió (14-oct, D7) un permiso con un "no" real que cubre TODO lo que lee
los datos del cliente con IA: el chat (chat_worker y sugerir_pendientes, Codex) y la ronda
del domingo (centinela, Claude). La foto del plato la frena la app.

Esto no da error si se rompe: si mañana alguien arma un prompt nuevo con la lista entera,
todo sigue andando y los datos de quien dijo que no vuelven a viajar. Por eso un test.

USO:  python3 scripts/test_consentimiento_ia.py
"""
import io
import os
import pathlib
import sys
import tempfile
import urllib.error

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))
for k in ("META_ACCESS_TOKEN", "META_PHONE_NUMBER_ID", "COACH_PHONE_NUMBER"):
    os.environ.setdefault(k, "x")

import chat_worker as W  # noqa: E402
import centinela as C  # noqa: E402

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


def error_http(codigo, cuerpo):
    return urllib.error.HTTPError("https://x/rpc", codigo, "x", {}, io.BytesIO(cuerpo.encode()))


# ── 1. chat_worker: a quién le pregunta y qué hace si no puede ─────────────────
print("\n1. chat_worker: quién va sin IA")
llamadas = []


def sb_ok(fn, payload):
    llamadas.append(fn)
    return ["c1"]


W._sb = sb_ok
check("los que dijeron que no", W.clientes_sin_ia(["c2", "c1", "c1"]) == {"c1"})
llamadas.clear()
check("sin clientes no pregunta", W.clientes_sin_ia([]) == set() and not llamadas)


def sb_falla(error):
    def f(fn, payload):
        raise error
    return f


W._sb = sb_falla(error_http(404, '{"code":"PGRST202","message":"Could not find the function"}'))
check("sin la nativa_002 nadie pudo decir que no", W.clientes_sin_ia(["c1", "c2"]) == set())
W._sb = sb_falla(error_http(500, "boom"))
check("si no puede preguntar, nadie va con IA", W.clientes_sin_ia(["c1", "c2"]) == {"c1", "c2"})
W._sb = sb_falla(TimeoutError("timeout"))
check("sin red tampoco", W.clientes_sin_ia(["c1"]) == {"c1"})

# ── 2. chat_worker: una pasada entera ──────────────────────────────────────────
print("\n2. chat_worker: el mensaje de quien dijo que no nunca llega al modelo")
pendientes = [{"cliente_id": "c1", "mensaje_id": "m1", "nombre": "Ana", "mensaje": "SECRETO-DE-ANA"},
              {"cliente_id": "c2", "mensaje_id": "m2", "nombre": "Beto", "mensaje": "hola beto"}]
guardados, prompts = [], []


def sb_pasada(fn, payload):
    if fn == "mypump_chat_para_responder":
        return pendientes
    if fn == "mypump_clientes_sin_ia":
        return ["c1"]
    if fn == "mypump_chat_borrador_guardar":
        guardados.append(payload)
        return True
    return None


W._sb = sb_pasada
W.SB_KEY = "x"
W.CORRER = True
W.AUTO = False
W.LIBRETA = pathlib.Path(tempfile.mkdtemp()) / ".cupo"
W.AVISADOS = pathlib.Path(tempfile.mkdtemp()) / ".avisados"
W.whatsapp = lambda t: True
W.armar_prompt = lambda fila: f"PROMPT {fila['mensaje']}"
W.llamar_codex = lambda prompt: (prompts.append(prompt), ({"clase": "simple", "respuesta": "dale!"}, None))[1]
W.main()
check("el modelo se llamó una sola vez", len(prompts) == 1, str(prompts))
check("y no con el mensaje de Ana", all("SECRETO-DE-ANA" not in p for p in prompts))
ana = next((g for g in guardados if g["p_cliente_id"] == "c1"), None)
check("el de Ana quedó en la bandeja como derivar", ana is not None and ana["p_clase"] == "derivar")
check("marcado sin IA", ana is not None and ana["p_modelo"] == W.MODELO_SIN_IA)
check("el cupo cuenta solo lo que fue al modelo", W.cupo_usado() == 1, str(W.cupo_usado()))

# ── 3. centinela: cada envío saca a quien dijo que no ──────────────────────────
print("\n3. centinela: la ronda del domingo")
enviados = []
C.claude_json = lambda prompt, timeout=0, etiqueta="": (enviados.append(prompt), {})[1]
C.SIN_IA = {"c1"}


def cliente(cid, nombre, nota):
    chk = {"energia": 2, "descanso": 2, "hambre": 4, "adherencia": 2, "nota": nota}
    return {"cid": cid, "nombre": nombre, "chk": chk, "chk_prev": None, "mal": True, "fotos_ok": False,
            "ctx": {"obj": "recomposicion", "activo": True, "perfil": "natural"}, "alertas": [],
            "dieta": "dieta", "rutina": "rutina", "suplementos": None, "veredicto": {"motivos": ["adherencia baja"]}}


lista = [cliente("c1", "Ana Gomez", "NOTA-PRIVADA-ANA"), cliente("c2", "Beto Paz", "nota de beto")]
for nombre, fn in (("personalizados", C.gen_personalizados), ("ajustes", C.gen_ajustes),
                   ("mensajes de ajuste", C.gen_mensajes_ajuste)):
    enviados.clear()
    out = fn(lista)
    check(f"{nombre}: el prompt no lleva a Ana", enviados and all("NOTA-PRIVADA-ANA" not in p and "Ana Gomez" not in p
                                                                  for p in enviados))
    check(f"{nombre}: Ana igual tiene su respaldo", bool(out.get("Ana Gomez")))
    enviados.clear()
    fn([cliente("c1", "Ana Gomez", "NOTA-PRIVADA-ANA")])
    check(f"{nombre}: si todos dijeron que no, no se llama al modelo", not enviados)

enviados.clear()
metricas = [{"cliente_id": "c1", "nombre": "Ana Gomez"}, {"cliente_id": "c2", "nombre": "Beto Paz"}]
chk_actual = {"c1": {"nota": "NOTA-PRIVADA-ANA"}, "c2": {"nota": "nota de beto"}}
C.interpretar_notas(metricas, chk_actual, {})
check("notas: no lleva la de Ana", enviados and all("NOTA-PRIVADA-ANA" not in p for p in enviados))

print(f"\n{'✓ todo bien' if not fallas else f'✗ {fallas} fallas'}")
sys.exit(1 if fallas else 0)
