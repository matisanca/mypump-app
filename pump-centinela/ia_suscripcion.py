"""ia_suscripcion.py — qué IA de SUSCRIPCIÓN contesta: Codex o Claude.

El 19-oct-2026 se terminaron los créditos del plan de ChatGPT de Mati. Codex contesta "You've hit your usage
limit ... try again at Oct 24th, 2026 5:53 PM", y la visión de comidas y el chat con IA dejaron de andar.
Mati (20-oct): "hasta finalizar ese día podés reemplazarlo por claude cli usando mis tokens del plan max y después
volver a codex cli como antes, nunca usar api".

Por eso:
- Hasta CLAUDE_HASTA (25-oct 00:00 de Argentina) contesta Claude CLI con el token OAuth del plan Max, el mismo que
  usa el centinela.
- Desde ahí vuelve solo a Codex: nadie tiene que acordarse de nada.
- PUMP_IA=claude o PUMP_IA=codex en el entorno fuerza uno (para probar, o si la cuota se vuelve a cortar).
- Nunca API: al hijo se le sacan todas las variables de API de Anthropic y de OpenAI, y sin el token OAuth no corre.

`mini-vision/server.mjs` tiene la misma regla en JavaScript (`proveedorIA`): si cambia la fecha acá, cambia allá.
"""
from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime, timezone

CLAUDE_HASTA = datetime(2026, 10, 25, 3, 0, tzinfo=timezone.utc)  # 25-oct 00:00 en Argentina (UTC-3)
CLAUDE_BIN = os.path.expanduser(os.environ.get("CLAUDE_BIN") or "~/.local/bin/claude")
CLAUDE_MODELO = os.environ.get("PUMP_CLAUDE_MODEL") or "claude-opus-5"  # el mismo del centinela
_TOKEN_ENV = os.path.expanduser("~/pump-trazabilidad/.env")

# Si alguna quedara en el entorno, el CLI cobraría por token en vez de usar la suscripción.
VARIABLES_DE_API = ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
                    "ANTHROPIC_API_KEY_FALLBACK", "OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID")


def proveedor(ahora: datetime | None = None) -> str:
    """'claude' o 'codex'."""
    forzado = (os.environ.get("PUMP_IA") or "").strip().lower()
    if forzado in ("claude", "codex"):
        return forzado
    ahora = ahora or datetime.now(timezone.utc)
    return "claude" if ahora < CLAUDE_HASTA else "codex"


def modelo_actual(modelo_codex: str) -> str:
    """Lo que se anota como `modelo` en cada borrador."""
    return CLAUDE_MODELO if proveedor() == "claude" else modelo_codex


def _token() -> str:
    t = (os.environ.get("CLAUDE_CODE_OAUTH_TOKEN") or "").strip()
    if t:
        return t
    try:
        with open(_TOKEN_ENV) as fh:
            for linea in fh:
                if linea.startswith("CLAUDE_CODE_OAUTH_TOKEN="):
                    return linea.split("=", 1)[1].strip().strip("\"'")
    except OSError:
        pass
    return ""


def entorno_claude() -> dict | None:
    """El entorno del hijo: el token del plan Max y ninguna variable de API. None si no hay token."""
    tok = _token()
    if not tok:
        return None
    env = {k: v for k, v in os.environ.items() if k not in VARIABLES_DE_API}
    env["CLAUDE_CODE_OAUTH_TOKEN"] = tok
    return env


def claude_texto(prompt: str, timeout: int) -> tuple[str | None, str | None]:
    """(texto, error). Sin herramientas, sin los MCP ni la configuración de la Mini y con el prompt por STDIN (nunca
    como argumento: un mensaje de cliente trae comillas, saltos de línea y emojis)."""
    env = entorno_claude()
    if env is None:
        return None, "sin CLAUDE_CODE_OAUTH_TOKEN (ni en el entorno ni en ~/pump-trazabilidad/.env)"
    # --safe-mode: sin los hooks, el CLAUDE.md ni los MCP de la Mini (el login del plan Max sigue); --no-session-persistence:
    # la conversación (el mensaje del cliente, aunque vaya sin el nombre) no queda en disco (revisión del 20-oct).
    cmd = [CLAUDE_BIN, "-p", "--model", CLAUDE_MODELO, "--tools", "", "--strict-mcp-config", "--safe-mode",
           "--no-session-persistence", "--output-format", "json"]
    try:
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                           timeout=timeout, env=env, cwd="/tmp")
    except subprocess.TimeoutExpired:
        return None, f"claude no contesto en {timeout}s"
    except FileNotFoundError:
        return None, f"no existe {CLAUDE_BIN}"
    try:
        d = json.loads(p.stdout or "")
    except ValueError:
        d = None
    if p.returncode != 0 or not isinstance(d, dict) or d.get("is_error"):
        detalle = d.get("result") if isinstance(d, dict) else None
        detalle = detalle or (p.stderr or p.stdout or "").strip()[-300:] or "sin detalle"
        return None, f"claude salio con {p.returncode}: {str(detalle)[:300]}"
    texto = d.get("result")
    if not texto:
        return None, "claude no devolvio ningun mensaje"
    return texto, None
