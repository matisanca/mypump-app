"""Aviso de pump-firma al bot (action = "contrato_firma"). PROPUESTA, SIN APLICAR: va a agent/medical/contrato_firma.py.

Módulo cerrado y sin dependencias del bot: valida el aviso, evita repetidos (pump-firma reintenta hasta recibir 200) y
arma el texto para Mati. No escribe en la base: el registro legal de la firma vive en el esquema `contrato`; el estado
se consulta con `public.contrato_estado(lead_id, email, whatsapp)` (lo usa AUTOMATIZAR ENTREGAS para abrir la agenda).
No le escribe al alumno."""
import json
import os
from datetime import datetime, timedelta, timezone

EVENTOS = ("firmado", "revocado", "baja_pedida")
TIPOS = {"servicio_ar": "el contrato de coaching", "servicio_ext": "el contrato de coaching",
         "consentimiento_ar": "el consentimiento de atención médica"}
RUTA_LOG = os.path.expanduser("~/pump-bot-contrato-firma.jsonl")
AR = timezone(timedelta(hours=-3))


def validar(payload: dict):
    """Devuelve (ok, motivo). Solo acepta la forma exacta que manda pump-firma."""
    if not isinstance(payload, dict) or payload.get("action") != "contrato_firma":
        return False, "accion"
    if payload.get("evento") not in EVENTOS:
        return False, "evento"
    doc, cli = payload.get("documento"), payload.get("cliente")
    if not isinstance(doc, dict) or doc.get("tipo") not in TIPOS or not doc.get("id"):
        return False, "documento"
    if not isinstance(cli, dict) or not str(cli.get("nombre") or "").strip():
        return False, "cliente"
    if not str(payload.get("aviso_id") or "").strip():
        return False, "aviso_id"
    return True, ""


def ya_visto(aviso_id: str, ruta: str = RUTA_LOG) -> bool:
    try:
        with open(ruta, encoding="utf-8") as f:
            return any(json.loads(l).get("aviso_id") == aviso_id for l in f if l.strip())
    except FileNotFoundError:
        return False


def anotar(payload: dict, ruta: str = RUTA_LOG) -> None:
    """Sin datos de contacto: id del aviso, evento, documento y lead."""
    fila = {"aviso_id": payload["aviso_id"], "evento": payload["evento"], "documento": payload["documento"]["id"],
            "tipo": payload["documento"]["tipo"], "lead_id": (payload.get("cliente") or {}).get("lead_id"),
            "recibido": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    with open(ruta, "a", encoding="utf-8") as f:
        f.write(json.dumps(fila, ensure_ascii=False) + "\n")
    os.chmod(ruta, 0o600)


def _cuando(iso: str) -> str:
    try:
        return datetime.fromisoformat(iso).astimezone(AR).strftime("%d/%m a las %H:%M")
    except (TypeError, ValueError):
        return "recién"


def texto_para_mati(payload: dict) -> str:
    nombre = " ".join(str(payload["cliente"]["nombre"]).split())[:80]
    que = TIPOS[payload["documento"]["tipo"]]
    estado = payload.get("estado") or {}
    cuando = _cuando(payload.get("cuando"))
    if payload["evento"] == "firmado":
        t = f"{nombre} firmó {que} ({cuando})."
        if payload["documento"]["tipo"] != "consentimiento_ar":
            t += " Agenda habilitada." if estado.get("bloquea_agenda") is False else " Ojo: la agenda sigue frenada, mirá el estado."
            if estado.get("consentimiento_pendiente"):
                t += " Le falta firmar el consentimiento médico."
        firma = payload.get("firma") or {}
        if firma.get("correcciones"):
            campos = ", ".join(sorted({str(c.get("campo")) for c in firma["correcciones"]}))
            t += f" Corrigió al firmar: {campos}."
        if firma.get("inicio_anticipado") is True:
            t += " Marcó el inicio anticipado."
        return t
    if payload["evento"] == "revocado":
        return f"{nombre} revocó {que} ({cuando}). Desde ahora no hay consentimiento vigente: no emitir órdenes ni recetas hasta resolverlo."
    dias = payload.get("dias_desde_la_firma")
    motivo = " ".join(str(payload.get("motivo") or "").split())[:200]
    return (f"{nombre} pidió la revocación o la baja del contrato ({cuando})"
            + (f", a {dias:.0f} días de la firma" if isinstance(dias, (int, float)) else "")
            + (f". Motivo: {motivo}" if motivo else ".")
            + " La agenda queda frenada hasta que lo resuelvas. Hay que contestarle dentro de las 24 h.")


def procesar(payload: dict, ruta: str = RUTA_LOG):
    """Devuelve (http, cuerpo, texto_para_mati | None). 200 también para un repetido: pump-firma deja de reintentar.
    NO anota el aviso como recibido: eso lo hace `confirmar`, después de que el mensaje a Mati salió de verdad. Si el
    envío falla, el que llama contesta 503 y pump-firma reintenta (una baja o una revocación no se pueden perder)."""
    ok, motivo = validar(payload)
    if not ok:
        return 400, {"status": "invalido", "motivo": motivo}, None
    if ya_visto(payload["aviso_id"], ruta):
        return 200, {"status": "repetido"}, None
    return 200, {"status": "ok"}, texto_para_mati(payload)


def confirmar(payload: dict, ruta: str = RUTA_LOG) -> None:
    anotar(payload, ruta)
