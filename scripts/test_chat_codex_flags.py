#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_chat_codex_flags.py — cómo se invoca a Codex y cómo se reporta su error

POR QUE EXISTE
El 25-sep el watchdog avisó "El chat con IA esta caido" y el detalle que
mostró era esto:

    Reading prompt from stdin...
    ERROR rmcp::transport::worker: worker quit with fatal: Transport channel
    closed, when Client(HttpRequest(... http://127.0.0.1:7433/mcp ...))

Ninguna de esas líneas es el error. Son el arranque de codex y el servidor MCP
`daydream` del config del ESCRITORIO, que no existe cuando la Codex.app está
cerrada. El detalle se truncaba a los primeros 200 caracteres, así que la causa
real (que estaba más abajo) nunca se veía, y el aviso pedía un `codex login`
que no tenía nada que ver.

Las dos mitades del arreglo:
  1. `--ignore-user-config` en lugar de `-c mcp_servers={}` (que en
     codex-cli 0.145.0 no hace nada). Saltea config.toml: ni MCP servers, ni
     el `model = gpt-5.5` dado de baja. La sesión no se toca.
  2. El detalle del error se arma con las ÚLTIMAS líneas útiles.

USO:  python3 scripts/test_chat_codex_flags.py
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


SALUD = (RAIZ / "pump-centinela" / "chat_salud.py").read_text(encoding="utf-8")
WORKER = (RAIZ / "pump-centinela" / "chat_worker.py").read_text(encoding="utf-8")

print("\n1. Los dos llaman a Codex igual, y sin el config del escritorio")
for nombre, src in (("chat_salud.py", SALUD), ("chat_worker.py", WORKER)):
    check(f"{nombre}: usa --ignore-user-config", '"--ignore-user-config"' in src,
          "sin esto arrastra los MCP del escritorio y el modelo dado de baja")
    # Solo el código: los comentarios SÍ nombran el override viejo, que es
    # justamente donde se explica por qué no se usa.
    codigo = "\n".join(l for l in src.splitlines() if not l.strip().startswith("#"))
    check(f"{nombre}: ya no usa el override que no funciona",
          'mcp_servers={}' not in codigo,
          "`-c mcp_servers={}` no hace nada en codex-cli 0.145.0")
    check(f"{nombre}: el modelo va explícito", '"-m", MODELO' in src,
          "al ignorar el config, el modelo TIENE que venir por flag")

print("\n2. El detalle del error son las últimas líneas útiles, no el ruido")
m = re.search(r"def _err_util\(stderr, limite=400\):.*?(?=\n\n\ndef |\Z)", SALUD, re.S)
check("chat_salud.py define _err_util()", m is not None)
ns = {"re": re}
exec(m.group(0).replace("_RUIDO", "_R"), {"re": re, "_R": re.compile(r"rmcp::|Reading prompt from stdin|^\s*$")}, ns)
_err = ns["_err_util"]

RUIDO_REAL = """Reading prompt from stdin...
2026-09-25T23:08:22.970228Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed, when Client(HttpRequest(HttpRequest("http/request failed: error sending request for url (http://127.0.0.1:7433/mcp)")))
2026-09-25T23:08:23.222Z ERROR rmcp::transport::worker: worker quit with fatal: Transport channel closed
stream error: exceeded retry limit, last status: 429 Too Many Requests"""
d = _err(RUIDO_REAL)
check("se queda con el error de verdad", "429" in d, d)
check("tira el ruido de rmcp", "rmcp::" not in d, d)
check("tira el 'Reading prompt from stdin'", "Reading prompt" not in d, d)
check("sin nada útil, devuelve algo igual", _err("Reading prompt from stdin...\n").strip() != "")
check("stderr vacío no rompe", isinstance(_err(""), str) and isinstance(_err(None), str))

print("\n3. Un fallo aislado no despierta a nadie")
# Se ejecuta el main() REAL con codex_vivo() falseado: un fallo seguido de un
# éxito no puede terminar en aviso, y dos fallos sí.
def _correr_main(resultados):
    import types
    mod = types.ModuleType("cs")
    mod.__dict__["__file__"] = str(RAIZ / "pump-centinela" / "chat_salud.py")
    src = SALUD.replace('if __name__ == "__main__":\n    sys.exit(main())', '')
    exec(compile(src, "chat_salud.py", "exec"), mod.__dict__)
    llamadas = {"vivo": 0, "wa": []}

    def vivo():
        i = min(llamadas["vivo"], len(resultados) - 1)
        llamadas["vivo"] += 1
        return resultados[i]
    mod.codex_vivo = vivo
    mod.whatsapp = lambda t: (llamadas["wa"].append(t), True)[1]
    mod.time = type("T", (), {"sleep": staticmethod(lambda s: None)})
    mod._log = lambda *a, **k: None
    mod.aviso_reciente = lambda: False
    mod.anotar_aviso = lambda: None
    mod.ESTADO = type("P", (), {"exists": staticmethod(lambda: False), "unlink": staticmethod(lambda: None)})()
    rc = mod.main()
    return rc, llamadas

rc, l = _correr_main([(False, "timed out"), (True, "ok")])
check("un fallo seguido de un éxito NO manda aviso", not l["wa"] and rc == 0,
      f"mandó {len(l['wa'])} aviso(s) por un fallo aislado")
rc, l = _correr_main([(False, "timed out"), (False, "timed out otra vez")])
check("dos fallos seguidos SÍ mandan aviso", len(l["wa"]) == 1 and rc == 1,
      f"mandó {len(l['wa'])} aviso(s) con la caída real")
check("el aviso cuenta los dos intentos", l["wa"] and "al reintentar" in l["wa"][0], (l["wa"] or [""])[0][:120])
check("chat_salud.py reintenta antes de avisar", "ESPERA_REINTENTO_S" in SALUD and "reintento" in SALUD,
      "un corte de red de 10 s no es una caída del chat")
check("si el reintento anda, no manda aviso", "el reintento anduvo" in SALUD)
i = SALUD.find("def main()")
cuerpo = SALUD[i:i + 1800]
check("el reintento corre ANTES del aviso",
      cuerpo.find("ESPERA_REINTENTO_S") < cuerpo.find("aviso_reciente"),
      "se reintenta después de haber avisado: no sirve de nada")

print("\n4. El remedio que propone depende del síntoma")
check("sesión vencida → propone codex login", 'login' in SALUD and '"sesion" in d' in SALUD)
check("timeout → NO propone codex login",
      'no contesto en' in SALUD and 'red o el modelo lento' in SALUD,
      "mandar 'corré codex login' ante un timeout hace tocar la sesión al pedo")
check("límite de uso → lo dice", '429' in SALUD and 'limite de uso' in SALUD)

print()
if fallas:
    print(f"✗ {fallas} fallo(s): el aviso del chat puede volver a mentir\n")
    sys.exit(1)
print("✓ Codex se invoca limpio y el aviso dice la causa real\n")
