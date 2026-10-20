"""Claude contesta mientras Codex no tenga créditos, y nunca por API (20-oct-2026).

Codex se quedó sin cuota el 19-oct ("try again at Oct 24th, 2026 5:53 PM"). Mati: "hasta finalizar ese día podés
reemplazarlo por claude cli usando mis tokens del plan max y después volver a codex cli como antes, nunca usar api".
Este test cuida tres cosas:
1. La fecha: Claude hasta el 24-oct inclusive (hora de Argentina) y Codex desde el 25, en Python y en la visión.
2. Nunca API: el hijo de Claude no ve ninguna variable de API y sin el token OAuth no corre.
3. Que el chat, el vigilante y la visión usen de verdad el camino de Claude en esa ventana.
"""
import json
import os
import pathlib
import stat
import sys
import tempfile
from datetime import datetime, timezone

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))
os.environ.setdefault("META_ACCESS_TOKEN", "x")
os.environ.setdefault("META_PHONE_NUMBER_ID", "x")
os.environ.setdefault("COACH_PHONE_NUMBER", "x")
os.environ.pop("PUMP_IA", None)

import ia_suscripcion as IA  # noqa: E402

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


AR = lambda d, h, m=0: datetime(2026, 10, d, h + 3, m, tzinfo=timezone.utc) if h + 3 < 24 else \
    datetime(2026, 10, d + 1, h + 3 - 24, m, tzinfo=timezone.utc)

print("\n1. La fecha")
check("el 20-oct contesta Claude", IA.proveedor(AR(20, 10)) == "claude")
check("el 24-oct a las 23:59 de Argentina sigue Claude", IA.proveedor(AR(24, 23, 59)) == "claude")
check("el 25-oct a las 00:00 de Argentina vuelve Codex", IA.proveedor(AR(25, 0)) == "codex")
check("y después sigue Codex", IA.proveedor(datetime(2026, 12, 1, tzinfo=timezone.utc)) == "codex")
os.environ["PUMP_IA"] = "codex"
check("PUMP_IA=codex fuerza Codex dentro de la ventana", IA.proveedor(AR(20, 10)) == "codex")
os.environ["PUMP_IA"] = "claude"
check("PUMP_IA=claude fuerza Claude fuera de la ventana", IA.proveedor(AR(26, 10)) == "claude")
os.environ["PUMP_IA"] = "openai-api"
check("un valor raro en PUMP_IA no cambia nada", IA.proveedor(AR(20, 10)) == "claude")
os.environ.pop("PUMP_IA", None)

vision = (RAIZ / "mini-vision" / "server.mjs").read_text(encoding="utf-8")
check("la visión corta en el mismo instante que Python",
      f"Date.parse('{IA.CLAUDE_HASTA.strftime('%Y-%m-%dT%H:%M:%SZ')}')" in vision,
      "si cambia la fecha en ia_suscripcion.py, tiene que cambiar en server.mjs")

print("\n2. Nunca API")
tmp = pathlib.Path(tempfile.mkdtemp())
falso = tmp / "claude"
falso.write_text("#!/bin/sh\n"
                 "env > \"$(dirname \"$0\")/env.txt\"\n"
                 "cat > \"$(dirname \"$0\")/stdin.txt\"\n"
                 "echo \"$@\" > \"$(dirname \"$0\")/args.txt\"\n"
                 "if [ -f \"$(dirname \"$0\")/falla\" ]; then echo '{\"is_error\": true, \"result\": \"limite\"}'; exit 1; fi\n"
                 "echo '{\"is_error\": false, \"result\": \"{\\\"clase\\\": \\\"simple\\\", \\\"respuesta\\\": \\\"dale\\\"}\"}'\n")
falso.chmod(falso.stat().st_mode | stat.S_IEXEC)
IA.CLAUDE_BIN = str(falso)
# Lista propia del test: si alguien saca una del código, esto la sigue mirando.
DE_API = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL", "OPENAI_API_KEY", "OPENAI_BASE_URL")
for v in DE_API:
    os.environ[v] = "sk-NO-TIENE-QUE-LLEGAR"
os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = "oat-de-prueba"
texto, err = IA.claude_texto("hola \"cliente\"\ncon salto", 10)
env_hijo = (tmp / "env.txt").read_text()
check("contesta con el texto del modelo", err is None and "dale" in (texto or ""), f"{texto!r} {err!r}")
check("ninguna variable de API llega al hijo", not any(f"{v}=" in env_hijo for v in DE_API),
      [v for v in DE_API if f"{v}=" in env_hijo])
check("el token OAuth del plan Max sí llega", "CLAUDE_CODE_OAUTH_TOKEN=oat-de-prueba" in env_hijo)
check("el prompt va por stdin, entero", (tmp / "stdin.txt").read_text() == "hola \"cliente\"\ncon salto")
args = (tmp / "args.txt").read_text()
check("sin herramientas y sin los MCP del Mini", "--tools" in args and "--strict-mcp-config" in args, args)
(tmp / "falla").write_text("1")
texto, err = IA.claude_texto("x", 10)
check("si Claude falla, devuelve el error y no un texto", texto is None and err and "limite" in err, f"{texto!r} {err!r}")
(tmp / "falla").unlink()
os.environ.pop("CLAUDE_CODE_OAUTH_TOKEN")
IA._TOKEN_ENV = str(tmp / "no-existe.env")
texto, err = IA.claude_texto("x", 10)
check("sin token OAuth no corre (no hay plan B por API)", texto is None and "CLAUDE_CODE_OAUTH_TOKEN" in (err or ""), err)
for v in DE_API:
    os.environ.pop(v, None)
os.environ["CLAUDE_CODE_OAUTH_TOKEN"] = "oat-de-prueba"

print("\n3. El chat, el vigilante y la visión usan ese camino")
import chat_worker as W  # noqa: E402
llamadas = []
IA.claude_texto = lambda p, t: (llamadas.append(p), ('```json\n{"clase": "simple", "respuesta": "dale"}\n```', None))[1]
W.IA.proveedor = lambda ahora=None: "claude"
d, err = W.llamar_codex("prompt del chat")
check("el chat le pregunta a Claude en la ventana", llamadas == ["prompt del chat"], llamadas)
check("y su respuesta pasa por el mismo control de JSON", err is None and d and d.get("clase") == "simple", f"{d!r} {err!r}")
IA.claude_texto = lambda p, t: ('{"clase": "inventada"}', None)
d, err = W.llamar_codex("x")
check("una clase desconocida de Claude se rechaza igual que la de Codex", d is None and "clase desconocida" in (err or ""), err)
check("el borrador anota el modelo de Claude", W.IA.modelo_actual(W.MODELO) == IA.CLAUDE_MODELO)

salud = (RAIZ / "pump-centinela" / "chat_salud.py").read_text(encoding="utf-8")
i = salud.find("def main()")
check("el vigilante pregunta por la IA de hoy", "ia_viva()" in salud[i:i + 400] and "codex_vivo()" not in salud[i:i + 400])
check("y el aviso dice cuál cayó", '{ia} no responde' in salud)

i = vision.find("const runIA")
check("la visión elige por fecha", "proveedorIA() === 'claude'" in vision[i:i + 200])
check("Claude usa su versión del prompt del plato", "PROMPTS_CLAUDE[tipo]" in vision[i:i + 200])
inicio = vision.find("  plato: `") + len("  plato: `")
plato = vision[inicio:vision.find("`,\n};", inicio)]
pares = __import__("re").findall(r"\['([^']+)', '[^']*'\]", vision[vision.find("const PARA_CLAUDE"):vision.find("const PROMPTS_CLAUDE")])
check("las tres frases que Claude bloquea están en el prompt del plato", len(pares) == 3 and all(p in plato for p in pares),
      [p for p in pares if p not in plato])
check("con el reemplazo, a Claude no le llega «en voz alta»",
      "en voz alta" not in __import__("functools").reduce(lambda t, p: t.replace(p, ""), pares, plato))

print(f"\n{'✓ todo bien' if not fallas else f'✗ {fallas} falla(s)'}")
sys.exit(1 if fallas else 0)
