#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_meta_ritmo.py — el WhatsApp a Mati respeta el ritmo de Meta y reintenta

POR QUE EXISTE
El jueves 17-sep-2026 la ronda de analisis mando 64 mensajes a Mati y Meta
rechazo 37 con un 400 pelado: mas de la mitad de los borradores por cliente
no llegaron y el log no decia por que. Es el "pair rate limit" (131056):
demasiados mensajes seguidos al mismo numero. Este test fija que
send_whatsapp() (1) deja al menos 1,5 s entre envios, (2) ante un codigo de
ritmo espera y reintenta, (3) ante un error que no se arregla esperando
(131047: ventana de 24 h vencida) NO reintenta, y (4) loguea el cuerpo.

USO:  python3 scripts/test_meta_ritmo.py
"""
import io
import json
import pathlib
import re
import sys
import urllib.error

RAIZ = pathlib.Path(__file__).resolve().parent.parent
src = (RAIZ / "pump-centinela" / "centinela.py").read_text(encoding="utf-8")

fallas = 0
def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle: print(f"      {detalle}")

# ── Extraer SOLO el bloque de Meta (constantes + _meta_error + send_whatsapp) ──
m = re.search(r"^_META_PASO = .*?^def send_whatsapp\(text\):.*?(?=^def |\Z)", src, re.S | re.M)
check("centinela.py define el bloque de ritmo de Meta", m is not None)
bloque = m.group(0)

class Reloj:
    def __init__(self): self.t = 1000.0; self.sleeps = []
    def time(self): return self.t
    def sleep(self, s): self.sleeps.append(round(s, 2)); self.t += s

class Resp:
    status = 200
    def __enter__(self): return self
    def __exit__(self, *a): return False

def armar(respuestas):
    """respuestas: lista de callables o excepciones, una por request."""
    reloj = Reloj(); pedidos = []
    def urlopen(req, timeout=20):
        pedidos.append(req)
        r = respuestas.pop(0)
        if isinstance(r, Exception): raise r
        return r
    salida = io.StringIO()
    ns = {"json": json, "time": reloj, "DRY": False,
          "E": {"META_ACCESS_TOKEN": "t", "META_PHONE_NUMBER_ID": "p", "COACH_PHONE_NUMBER": "549"},
          "urllib": type("U", (), {"request": type("R", (), {"Request": lambda *a, **k: (a, k), "urlopen": staticmethod(urlopen)}),
                                    "error": urllib.error})}
    real_print = print
    ns["print"] = lambda *a, **k: real_print(*a, file=salida, **k)
    exec(bloque, ns)
    return ns, reloj, pedidos, salida

def http_error(codigo_meta, status=400):
    cuerpo = json.dumps({"error": {"message": "x", "code": codigo_meta}}).encode()
    return urllib.error.HTTPError("u", status, "Bad Request", {}, io.BytesIO(cuerpo))

print("\n1. rate limit (131056) → espera y reintenta, y el mensaje sale")
ns, reloj, pedidos, out = armar([http_error(131056), Resp()])
ok = ns["send_whatsapp"]("hola")
check("devuelve True", ok is True)
check("hizo 2 requests", len(pedidos) == 2, str(len(pedidos)))
check("esperó 5 s antes del reintento", 5 in reloj.sleeps, str(reloj.sleeps))
check("logueó el código de Meta", "131056" in out.getvalue(), out.getvalue())

print("\n2. ventana de 24 h vencida (131047) → NO reintenta, devuelve False")
ns, reloj, pedidos, out = armar([http_error(131047), Resp()])
ok = ns["send_whatsapp"]("hola")
check("devuelve False", ok is False)
check("un solo request", len(pedidos) == 1, str(len(pedidos)))
check("no esperó backoff", not any(s >= 5 for s in reloj.sleeps), str(reloj.sleeps))
check("logueó el cuerpo", "131047" in out.getvalue())

print("\n3. rate limit persistente → 3 reintentos (5, 20, 60) y después False")
ns, reloj, pedidos, out = armar([http_error(131056) for _ in range(4)] + [Resp()])  # objetos distintos: el cuerpo se lee una vez
ok = ns["send_whatsapp"]("hola")
check("devuelve False", ok is False)
check("4 requests (1 + 3 reintentos)", len(pedidos) == 4, str(len(pedidos)))
check("esperas 5, 20, 60", [s for s in reloj.sleeps if s >= 5] == [5, 20, 60], str(reloj.sleeps))

print("\n4. ritmo: dos mensajes seguidos → al menos 1,5 s entre ellos")
ns, reloj, pedidos, out = armar([Resp(), Resp()])
ns["send_whatsapp"]("a"); ns["send_whatsapp"]("b")
check("el segundo esperó ~1,5 s", any(1.4 <= s <= 1.5 for s in reloj.sleeps), str(reloj.sleeps))
check("el primero no esperó (hacía mucho que no se mandaba)", not reloj.sleeps or reloj.sleeps[0] >= 1.4 and len(reloj.sleeps) == 1, str(reloj.sleeps))

print("\n5. red caída una vez → reintento corto y sale")
ns, reloj, pedidos, out = armar([OSError("timed out"), Resp()])
ok = ns["send_whatsapp"]("hola")
check("devuelve True", ok is True)
check("2 requests", len(pedidos) == 2)

print("\n6. HTTP 429 / 5xx también se reintentan aunque no traigan código")
ns, reloj, pedidos, out = armar([urllib.error.HTTPError("u", 503, "x", {}, io.BytesIO(b"")), Resp()])
check("503 → reintenta y sale", ns["send_whatsapp"]("hola") is True and len(pedidos) == 2)

print()
if fallas:
    print(f"✗ {fallas} fallo(s): el WhatsApp a Mati puede volver a perder la mitad de la ronda\n"); sys.exit(1)
print("✓ ritmo, reintentos y log del error: como corresponde\n")
