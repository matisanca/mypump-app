"""deid_chat.py — sacarle el nombre a un chat antes de mandarlo a un modelo de afuera, y volver a ponerlo después.

POR QUÉ EXISTE (Mati, 14-oct-2026)
La IA no es algo que el cliente acepte ("funcionaba bajo mi aprobación"). En su lugar: "pasar sus mensajes antes por
IA local, quitar el nombre de la persona, responderle y volver a agregarle el nombre, usando la IA local de la Mac
Mini, pero que siga usando Codex". Lo usan chat_worker.py y sugerir_pendientes.py (Codex), y app_chat.py de la skill
responder-clientes (la sesión de Mensajes).

CÓMO
- Tapa con agent/medical/deid_qwen (agentkit-coach): primero lo que se sabe de la ficha del Cerebro (nombre, apellido,
  teléfono, edad), que no falla, y después Qwen para la prosa (otros nombres, lugares, trabajo).
- Qwen viene calibrado para calls clínicas y en el chat listaba palabras del entreno como si identificaran a alguien
  ("el cardio lo hago antes o después de entrenar" salía "el [INSTITUCION_1] lo hago antes o después de [TRABAJO_1]").
  En los procesos que importan este módulo el filtro de entidades suma dos reglas: el vocabulario del entreno y la
  dieta no se tapa nunca, y un trabajo, una institución o una dirección se tapan solo si tienen nombre propio o
  número. El módulo compartido no se toca: el pipeline médico sigue igual.
- Si Qwen no contesta, se tapa igual lo conocido y queda marcado DEGRADADO: la IA sigue (pedido de Mati).
- Si algo identificable sobrevive a todo, `tapar` devuelve None y NO se manda: queda para Mati.
- El mapa (placeholder → valor) no sale del Mini. `destapar` lo usa sobre lo que contestó el modelo, más `{nombre}`
  para el nombre de pila.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path.home() / "agentkit-coach"))

from agent.medical import deid_qwen as D  # noqa: E402

PLACEHOLDER = re.compile(r"\[[A-Z]+_\d+\]")

_DEL_CHAT = frozenset((
    "cardio", "entrenar", "entreno", "entrenamiento", "entrene", "entrenando", "entrenaste", "rutina", "rutinas",
    "dieta", "comida", "comidas", "desayuno", "almuerzo", "merienda", "cena", "colacion", "gym", "gimnasio", "pesas",
    "piernas", "pierna", "pecho", "espalda", "hombros", "brazos", "gluteos", "abdominales", "core", "caminata",
    "caminar", "correr", "running", "cinta", "bici", "bicicleta", "eliptico", "natacion", "futbol", "crossfit",
    "pilates", "yoga", "boxeo", "funcional", "hiit", "descanso", "sueno", "pasos", "peso", "balanza", "fotos", "foto",
    "revision", "check", "plan", "macros", "proteinas", "carbohidratos", "carbos", "grasas", "calorias", "ayuno",
    "suplementos", "app", "mypump", "pump", "pump team", "mati", "matias", "coach", "serie", "series", "repeticiones",
    "reps", "ejercicio", "ejercicios", "sentadilla", "press", "remo", "dominadas", "jalon", "estocadas", "trabajo",
))
_valida_del_modulo = D._entidad_valida


def _valida_en_el_chat(tipo: str, texto: str) -> bool:
    if not _valida_del_modulo(tipo, texto):
        return False
    t = (texto or "").strip(" .,;:()\"'")
    if D._norm_clave(t) in _DEL_CHAT:
        return False
    if tipo in ("trabajo", "institucion", "direccion") and not any(c.isupper() or c.isdigit() for c in t):
        return False
    return True


D._entidad_valida = _valida_en_el_chat


class NoSeTapa(RuntimeError):
    """Quedó algo identificable: no se manda a ningún modelo."""


def nombres_de_fichas(fichas: dict | None, salvo: str | None = None) -> list[str]:
    """Los nombres completos de todas las fichas del Cerebro (menos la del cliente): van como `otros_nombres` y se tapan
    sin preguntarle a Qwen. Con Qwen caído, el bloque CANDIDATOS de contexto_cliente.py mostraba sin tapar a los otros
    clientes parecidos (lo encontró la sesión de Mensajes el 14-oct)."""
    out = []
    for cid, f in (fichas or {}).items():
        if cid == salvo or not isinstance(f, dict) or f.get("_dup_of"):
            continue
        n = " ".join(x for x in (f.get("nombre"), f.get("apellido")) if x).strip()
        if len(n.split()) >= 2:   # un nombre suelto («Juan») se comería palabras en cualquier texto
            out.append(n)
    return out


def datos_de(ficha: dict | None, nombre_app: str | None = None, otros: list[str] | None = None) -> "D.DatosPaciente":
    """Lo conocido de la ficha del Cerebro (el id es el mismo que en la app), el nombre que figura en la app y los
    nombres de los demás clientes (`nombres_de_fichas`)."""
    f = ficha or {}
    completo = " ".join(x for x in (f.get("nombre"), f.get("apellido")) if x).strip() or (nombre_app or None)
    otros = list(otros or []) + ([nombre_app] if nombre_app and completo and nombre_app.strip().lower() != completo.lower() else [])
    try:
        edad = int(f["edad"]) if f.get("edad") not in (None, "") else None
    except (TypeError, ValueError):
        edad = None
    return D.DatosPaciente(nombre_completo=completo, telefono=(f.get("whatsapp") or None), edad=edad,
                           otros_nombres=otros)


def nombre_de_pila(ficha: dict | None, nombre_app: str | None = None) -> str:
    n = ((ficha or {}).get("nombre") or nombre_app or "").strip().split()
    return n[0] if n else ""


def tapar(texto: str, datos: "D.DatosPaciente", *, usar_qwen: bool = True) -> tuple[str | None, dict, list[str]]:
    """(texto tapado, o None si no se puede mandar; mapa; avisos). Los guardrails de `prepare_for_ai`."""
    avisos: list[str] = []
    rep: dict = {"motivos": [], "degradada": False}
    try:
        out, mapa = D.deidentify(texto, datos, usar_qwen=usar_qwen, reporte=rep)
    except D.DeidError as e:
        out, mapa = D.deidentify(texto, datos, usar_qwen=False)
        avisos.append(f"DEGRADADO: Qwen no respondió ({type(e).__name__}); se tapó lo conocido de la ficha")
    if rep.get("degradada"):
        avisos.append("DEGRADADO: " + (", ".join(rep.get("motivos") or []) or "Qwen dudó en algún trozo"))
    quedan = D.tipos_de_identificadores_restantes(out, datos)
    if quedan:
        return None, mapa, avisos + [f"quedaron identificadores ({', '.join(quedan)})"]
    duras, _ = D.pii_de_prosa(out)
    if duras:
        out, tapadas = D.tapar_prosa_dura(out)
        avisos.append("DEGRADADO: se taparon a mano " + "/".join(tapadas or duras))
        if D.pii_de_prosa(out)[0]:
            return None, mapa, avisos + ["sobrevivió algo identificable"]
    return out, mapa, avisos


def destapar(texto: str | None, mapa: dict, nombre_pila: str) -> str | None:
    """Lo que contestó el modelo, con el nombre de vuelta. Lanza NoSeTapa si quedó un placeholder sin valor."""
    if texto is None:
        return None
    out = D.reidentify(texto.replace("{nombre}", nombre_pila or ""), mapa or {})
    resto = PLACEHOLDER.search(out)
    if resto:
        raise NoSeTapa(f"quedó un dato tapado sin valor: {resto.group(0)}")
    return out
