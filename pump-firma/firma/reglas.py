"""Reglas puras: sin red, sin base, sin reloj. Todo lo que decide algo y se puede probar solo."""
import hashlib
import hmac
import json
import re
import unicodedata

TIPOS = ("servicio_ar", "servicio_ext", "consentimiento_ar")

# Mismos países que el Apps Script de onboarding (esResidenteArgentino), para que las dos puntas decidan igual.
PAISES_NO_ARGENTINA = [
    "uruguay", "chile", "paraguay", "bolivia", "peru", "perú", "brasil", "brazil", "colombia", "ecuador", "venezuela",
    "mexico", "méxico", "costa rica", "panama", "panamá", "guatemala", "honduras", "salvador", "nicaragua", "dominicana",
    "puerto rico", "cuba", "estados unidos", "usa", "eeuu", "españa", "espana", "spain", "italia", "alemania", "francia",
    "reino unido", "inglaterra", "portugal", "canada", "canadá", "australia", "israel", "suiza", "andorra", "irlanda",
    "holanda", "paises bajos", "belgica", "bélgica",
]

CAMPOS_TEXTO = {
    "servicio_ar": ("cNombre1", "cNombre2", "cDni1", "cDni2", "cDomic", "cPais", "cPlan", "cObjetivo", "cPrecio"),
    "servicio_ext": ("cNombre1", "cNombre2", "cDni1", "cDni2", "cDomic", "cPais"),
    "consentimiento_ar": ("mNombre", "mNombre2", "mDni", "mDni2", "mDomic"),
}
CAMPOS_FECHA = {
    "servicio_ar": ("fCont", "cFecha"),
    "servicio_ext": ("fCont", "cFecha"),
    "consentimiento_ar": ("mFechaIni", "mFecha"),
}
CAMPO_FIRMA = {"servicio_ar": "cFirma", "servicio_ext": "cFirma", "consentimiento_ar": "mFirma"}
# Lo que el closer tiene que haber cargado para que el documento nazca. El DNI puede faltar: lo escribe el firmante.
OBLIGATORIOS = {
    "servicio_ar": ("cNombre1", "cPlan", "cObjetivo", "cPrecio"),
    "servicio_ext": ("cNombre1",),
    "consentimiento_ar": ("mNombre",),
}


def json_canonico(obj) -> str:
    """El texto exacto que entra al hash de un evento: claves ordenadas, sin espacios, sin caracteres de control."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, default=str)


def sha256_hex(datos: bytes) -> str:
    return hashlib.sha256(datos).hexdigest()


def es_residente_argentino(pais: str, whatsapp: str) -> bool:
    p = (pais or "").lower().strip()
    if "argentin" in p:
        return True
    if any(x in p for x in PAISES_NO_ARGENTINA):
        return False
    return re.sub(r"\D", "", whatsapp or "").startswith("54")


def variante_de(pais: str, residente_argentina: bool) -> str:
    if residente_argentina:
        return "AR"
    p = sin_acentos(pais or "").lower()
    return "ES" if re.search(r"\b(espana|spain)\b", p) else "OTRO"


def dni_plausible(v: str) -> str:
    """Igual que el Apps Script: un DNI argentino tiene 7 u 8 dígitos; si no, no se precarga."""
    d = re.sub(r"\D", "", v or "")
    return (v or "").strip() if len(d) in (7, 8) else ""


def sin_acentos(t: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", t or "") if unicodedata.category(c) != "Mn")


def norm_nombre(t: str) -> str:
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", sin_acentos(t).lower())).strip()


def norm_documento(t: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", sin_acentos(t).upper())


def mismo_nombre(a: str, b: str) -> bool:
    return norm_nombre(a) == norm_nombre(b) and bool(norm_nombre(a))


def documento_valido(valor: str, variante: str) -> bool:
    d = norm_documento(valor)
    if variante == "AR":
        return d.isdigit() and len(d) in (7, 8)
    return 5 <= len(d) <= 20


def limpiar_texto(t, tope: int) -> str:
    """Una sola línea, sin caracteres de control, recortada."""
    t = "".join(" " if unicodedata.category(c)[0] == "C" else c for c in str(t or ""))
    return re.sub(r"\s+", " ", t).strip()[:tope]


def limpiar_parrafo(t, tope: int) -> str:
    """Como limpiar_texto, pero conserva los saltos de línea (precio y forma de pago)."""
    lineas = [limpiar_texto(l, tope) for l in str(t or "").replace("\r", "").split("\n")]
    return "\n".join(l for l in lineas if l)[:tope]


def campos_de_alta(tipo: str, alta: dict) -> dict:
    """Los valores que se precargan en el documento, como hoy los manda el Apps Script a BoldSign."""
    nombre = limpiar_texto(f"{alta.get('nombre', '')} {alta.get('apellido', '')}", 120)
    dni = limpiar_texto(dni_plausible(alta.get("dni", "")) if tipo != "servicio_ext" else alta.get("dni", ""), 40)
    domic = limpiar_texto(alta.get("domicilio", ""), 200)
    if tipo == "consentimiento_ar":
        return {"mNombre": nombre, "mNombre2": nombre, "mDni": dni, "mDni2": dni, "mDomic": domic}
    c = {"cNombre1": nombre, "cNombre2": nombre, "cDni1": dni, "cDni2": dni, "cDomic": domic,
         "cPais": limpiar_texto(alta.get("pais", ""), 80)}
    if tipo == "servicio_ar":
        c["cPlan"] = limpiar_texto(alta.get("plan", ""), 200)
        c["cObjetivo"] = limpiar_texto(alta.get("objetivo", ""), 300)
        c["cPrecio"] = limpiar_parrafo(alta.get("precio", ""), 1500)
    return c


def faltantes(tipo: str, campos: dict) -> list:
    return [k for k in OBLIGATORIOS[tipo] if not (campos.get(k) or "").strip()]


def alta_ref(alta: dict) -> str:
    """Clave de idempotencia del alta: el mismo envío del formulario da siempre la misma."""
    if alta.get("alta_ref"):
        return limpiar_texto(alta["alta_ref"], 200)
    base = "|".join(limpiar_texto(alta.get(k, ""), 200).lower() for k in ("email", "whatsapp", "marca_temporal"))
    return "alta-" + sha256_hex(base.encode())[:40]


def token_de(secreto: bytes, doc_id: str, n: int) -> str:
    return hmac.new(secreto, f"tok:{doc_id}:{n}".encode(), hashlib.sha256).hexdigest()[:48]


def token_sha(token: str) -> str:
    return sha256_hex(token.encode())


def codigo_hmac(secreto: bytes, doc_id: str, proposito: str, codigo: str) -> str:
    return hmac.new(secreto, f"cod:{doc_id}:{proposito}:{codigo}".encode(), hashlib.sha256).hexdigest()


def codigo_valido_forma(codigo: str) -> bool:
    return bool(re.fullmatch(r"\d{6}", codigo or ""))


def mail_tapado(mail: str) -> str:
    u, _, d = (mail or "").partition("@")
    return (u[:2] + "•" * max(1, len(u) - 2) + "@" + d) if d else ""


def resolver_identidad(tipo: str, variante: str, campos: dict, escrito: dict) -> dict:
    """Cruza lo que escribió el firmante con lo precargado.
    Devuelve {'ok', 'errores': [...], 'campos': valores finales, 'correcciones': [{campo, antes, despues}], 'completados': [...]}.
    Si lo escrito no coincide con lo precargado, solo pasa cuando el firmante confirmó que el dato del documento estaba mal."""
    pre = "m" if tipo == "consentimiento_ar" else "c"
    k_nom1, k_nom2 = pre + "Nombre" + ("" if pre == "m" else "1"), pre + "Nombre2"
    k_dni1, k_dni2 = pre + "Dni" + ("" if pre == "m" else "1"), pre + "Dni2"
    k_dom = pre + "Domic"
    finales, errores, correcciones, completados = dict(campos), [], [], []
    confirma = set(escrito.get("confirma_correccion") or [])

    nombre = limpiar_texto(escrito.get("nombre", ""), 120)
    if len(norm_nombre(nombre).split()) < 2:
        errores.append({"campo": "nombre", "error": "incompleto"})
    elif not mismo_nombre(nombre, campos.get(k_nom1, "")):
        if "nombre" in confirma:
            correcciones.append({"campo": "nombre", "antes": campos.get(k_nom1, ""), "despues": nombre})
            finales[k_nom1] = finales[k_nom2] = nombre
        else:
            errores.append({"campo": "nombre", "error": "no_coincide"})
    else:
        finales[k_nom2] = finales[k_nom1]

    doc = limpiar_texto(escrito.get("documento", ""), 40)
    previo = campos.get(k_dni1, "")
    # El consentimiento es de Argentina aunque el alta diga otra cosa; el contrato del exterior acepta pasaporte.
    var_doc = "AR" if tipo in ("servicio_ar", "consentimiento_ar") else "OTRO"
    if not documento_valido(doc, var_doc):
        errores.append({"campo": "documento", "error": "invalido"})
    elif not previo:
        completados.append("documento")
        finales[k_dni1] = finales[k_dni2] = doc
    elif norm_documento(doc) != norm_documento(previo):
        if "documento" in confirma:
            correcciones.append({"campo": "documento", "antes": previo, "despues": doc})
            finales[k_dni1] = finales[k_dni2] = doc
        else:
            errores.append({"campo": "documento", "error": "no_coincide"})
    else:
        finales[k_dni2] = finales[k_dni1]

    dom = limpiar_texto(escrito.get("domicilio", ""), 200)
    if dom and dom != campos.get(k_dom, ""):
        if campos.get(k_dom):
            correcciones.append({"campo": "domicilio", "antes": campos.get(k_dom, ""), "despues": dom})
        else:
            completados.append("domicilio")
        finales[k_dom] = dom
    if len(finales.get(k_dom, "")) < 5:
        errores.append({"campo": "domicilio", "error": "incompleto"})
    return {"ok": not errores, "errores": errores, "campos": finales, "correcciones": correcciones, "completados": completados}


# Casillas de la pantalla. `obligatoria` = sin ella no se firma. El texto exacto de cada una sale de textos.py y
# queda en el evento y en la constancia.
CASILLAS = {
    "servicio_ar": {"electronico": True, "lei_acepto": True, "inicio_anticipado": False},
    "servicio_ext": {"electronico": True, "lei_acepto": True},
    "consentimiento_ar": {"electronico": True, "lei_acepto": True, "datos_salud": True},
}
CASILLAS_ES = {"inicio_en_desistimiento": False}


def casillas_de(tipo: str, variante: str) -> dict:
    c = dict(CASILLAS[tipo])
    if tipo == "servicio_ext" and variante == "ES":
        c.update(CASILLAS_ES)
    return c


def validar_casillas(tipo: str, variante: str, marcadas: dict) -> list:
    """Devuelve las obligatorias que faltan. Ignora lo que no corresponde a este documento."""
    return [k for k, obligatoria in casillas_de(tipo, variante).items() if obligatoria and marcadas.get(k) is not True]


def evento_canon(prev: str, n: int, doc, tipo: str, ts, ip, ua, datos: str) -> str:
    """Igual que contrato.evento_canon de la base: con esto se recalcula la cadena sin tocar la base."""
    from datetime import timezone
    return "\n".join([prev, str(n), str(doc or ""), tipo, ts.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"),
                      ip or "", ua or "", datos])


def verificar_cadena(eventos: list, prev: str = "0" * 64, n_previo: int = 0) -> dict:
    """`eventos`: filas de contrato.eventos en orden (dicts con n, documento_id, tipo, ts, ip, user_agent, datos, prev_hash, hash;
    `ts` puede venir como texto ISO). Devuelve {'ok', 'n', 'cabeza', 'error'}."""
    from datetime import datetime
    for e in eventos:
        ts = e["ts"] if not isinstance(e["ts"], str) else datetime.fromisoformat(e["ts"])
        if e["n"] != n_previo + 1:
            return {"ok": False, "n": e["n"], "cabeza": prev, "error": f"falta o sobra un evento antes del {e['n']}"}
        if e["prev_hash"] != prev:
            return {"ok": False, "n": e["n"], "cabeza": prev, "error": f"el evento {e['n']} no encadena con el anterior"}
        h = sha256_hex(evento_canon(prev, e["n"], e.get("documento_id"), e["tipo"], ts, e.get("ip"), e.get("user_agent"), e["datos"]).encode())
        if h != e["hash"]:
            return {"ok": False, "n": e["n"], "cabeza": prev, "error": f"el evento {e['n']} fue alterado"}
        prev, n_previo = h, e["n"]
    return {"ok": True, "n": n_previo, "cabeza": prev, "error": None}
