"""Del texto vigente (Markdown con etiquetas {{@campo}}) al PDF y a los bloques que muestra la página.

La maquetación es la aprobada (render_contrato.py / render_v8.py / render_exterior.py de la Mini): mismo CSS, mismos
bloques. Lo único que cambia es que las etiquetas, que BoldSign convertía en campos, acá se reemplazan por su valor.
El texto del contrato no se toca: sale de la plantilla guardada en la base, tal cual.
"""
import base64
import html
import io
import re
from datetime import datetime
from zoneinfo import ZoneInfo

from . import reglas

RX_ETIQUETA = re.compile(r"\{\{(?:@|date\|1\|\*\|\|)(\w+)\}\}")
RX_IMG_PRESTADOR = re.compile(r"!\[firma\]\(([^)]+)\)")
RX_RAYA = re.compile(r"_{6,}")
ZONA_AR = ZoneInfo("America/Argentina/Buenos_Aires")

CSS_PDF = """
@page { size: A4; margin: 18mm 16mm 16mm 16mm;
  @top-left { content: "PUMP TEAM"; font: bold 8pt 'Liberation Sans', 'DejaVu Sans', 'Arial', sans-serif; color: #2e7d32; }
  @top-right { content: "Página " counter(page) " de " counter(pages) "          %(cabecera)s"; font: 7pt 'Liberation Sans', 'DejaVu Sans', 'Arial', sans-serif; color: #555; } }
body { font: 8.6pt/1.32 'Liberation Sans', 'DejaVu Sans', 'Arial', sans-serif; color: #111; }
h1 { font-size: 12.5pt; margin: 0 0 2pt 0; letter-spacing: .3px; }
h2 { font-size: 8.8pt; font-weight: normal; color: #333; margin: 0 0 8pt 0; }
h3 { font-size: 9.5pt; margin: 10pt 0 4pt 0; }
p { margin: 0 0 5.2pt 0; text-align: justify; }
p.firma { margin-top: 7pt; text-align: left; line-height: 1.9; break-inside: avoid; page-break-inside: avoid; }
p.aviso { border: 1px solid #333; padding: 5pt 7pt; margin: 8pt 0; text-align: left; break-inside: avoid; page-break-inside: avoid; }
h3 { break-after: avoid; page-break-after: avoid; }
.v { font-weight: bold; }
.v.largo { display: block; font-weight: normal; white-space: pre-wrap; border-left: 2px solid #999; padding: 1pt 0 1pt 6pt; margin: 2pt 0; line-height: 1.35; }
.hueco { display: inline-block; min-width: 110pt; border-bottom: .6pt solid #333; height: 9pt; vertical-align: baseline; }
.hueco.firma { height: 34pt; min-width: 150pt; }
img.firma { height: 40pt; vertical-align: -12pt; margin: 0 18pt 0 4pt; }
.casilla { display: inline-block; width: 8.5pt; height: 8.5pt; border: .8pt solid #111; text-align: center; font: bold 8pt/8.5pt 'Liberation Sans', 'DejaVu Sans', 'Arial', sans-serif; vertical-align: -1pt; margin-right: 3pt; }
.constancia { break-before: page; page-break-before: always; }
.constancia h3 { font-size: 11pt; margin-top: 0; }
.constancia table { border-collapse: collapse; width: 100%%; margin: 4pt 0 8pt 0; }
.constancia td, .constancia th { border: .5pt solid #999; padding: 2.5pt 4pt; font-size: 7.6pt; text-align: left; vertical-align: top; overflow-wrap: anywhere; }
.constancia th { background: #eee; width: 26%%; }
.constancia td.mono, .mono { font-family: 'DejaVu Sans Mono', 'Liberation Mono', 'Menlo', monospace; font-size: 6.8pt; word-break: break-all; }
.constancia p { text-align: left; font-size: 7.8pt; }
"""


def fecha_ar(ts: datetime) -> str:
    return ts.astimezone(ZONA_AR).strftime("%d/%m/%Y")


def hora_ar(ts: datetime) -> str:
    return ts.astimezone(ZONA_AR).strftime("%d/%m/%Y %H:%M:%S") + " (hora de Argentina, UTC−3)"


def hora_utc(ts: datetime) -> str:
    return ts.astimezone(ZoneInfo("UTC")).strftime("%Y-%m-%d %H:%M:%S") + " UTC"


def _data_uri(png: bytes) -> str:
    return "data:image/png;base64," + base64.b64encode(png).decode()


def bloques_de(md: str):
    """Corta el Markdown igual que el render aprobado. Devuelve (titulo, subtitulo, [(clase, lineas, en_firmas)])."""
    crudos = []
    for bloque in re.split(r"\n\s*\n", md.strip()):
        actual = []
        for l in bloque.strip().split("\n"):
            if l.startswith("#"):
                if actual:
                    crudos.append("\n".join(actual))
                    actual = []
                crudos.append(l)
            else:
                actual.append(l)
        if actual:
            crudos.append("\n".join(actual))
    titulo = subtitulo = ""
    salida, en_firmas = [], False
    for b in (c.strip() for c in crudos):
        if not b:
            continue
        if b.startswith("# "):
            titulo = b[2:].strip()
            continue
        if b.startswith("## "):
            subtitulo = b[3:].strip()
            continue
        if b.startswith("### "):
            if b[4:].strip().upper() == "FIRMAS":
                en_firmas = True
            salida.append(("h3", [b[4:].strip()], en_firmas))
            continue
        lineas = b.split("\n")
        if all(l.startswith(("Por el ", "Firma:")) for l in lineas) or any("{{" in l for l in lineas):
            salida.append(("firma", lineas, en_firmas))
        elif b.startswith("**") and b.endswith("**") and b.count("**") == 2:
            salida.append(("aviso", [b], en_firmas))
        else:
            salida.append(("p", [" ".join(l.strip() for l in lineas)], en_firmas))
    return titulo, subtitulo, salida


class Valores:
    """Con qué se llena cada etiqueta. Sin `firmado_en` es el documento a firmar (huecos); con él, el firmado."""

    def __init__(self, tipo, campos, firmado_en=None, firma_png=None, inicio_anticipado=None,
                 firma_prestador_png=None, estampar_prestador=False):
        self.tipo = tipo
        self.campos = campos
        self.firmado_en = firmado_en
        self.firma_png = firma_png
        self.inicio_anticipado = inicio_anticipado
        self.firma_prestador_png = firma_prestador_png
        self.estampar_prestador = estampar_prestador

    def html_de(self, nombre: str) -> str:
        if nombre in reglas.CAMPOS_FECHA[self.tipo]:
            return f"<span class='v'>{fecha_ar(self.firmado_en)}</span>" if self.firmado_en else "<span class='hueco'></span>"
        if nombre == reglas.CAMPO_FIRMA[self.tipo]:
            return f"<img class='firma' src='{_data_uri(self.firma_png)}'>" if self.firma_png else "<span class='hueco firma'></span>"
        if nombre == "cInicio":
            return "<span class='casilla'>%s</span>" % ("X" if self.inicio_anticipado else "&nbsp;")
        if nombre in reglas.CAMPOS_TEXTO[self.tipo]:
            v = (self.campos.get(nombre) or "").strip()
            if not v:
                return "<span class='hueco'></span>"
            clase = "v largo" if nombre in ("cPrecio", "cObjetivo") else "v"
            return f"<span class='{clase}'>{html.escape(v, quote=False)}</span>"
        raise ValueError(f"etiqueta desconocida en la plantilla: {nombre}")


def _inline(texto: str, valores: Valores, prestador: bool) -> str:
    """Negrita y cursiva del Markdown, y cada etiqueta por su valor. Los valores entran ya escapados y después del
    Markdown: un precio con asteriscos no se vuelve negrita ni rompe nada."""
    piezas = []

    def guardar(h):
        piezas.append(h)
        return f"\x00{len(piezas) - 1}\x00"

    t = RX_ETIQUETA.sub(lambda m: guardar(valores.html_de(m.group(1))), texto)
    if RX_IMG_PRESTADOR.search(t):
        img = f"<img class='firma' src='{_data_uri(valores.firma_prestador_png)}'>" if valores.firma_prestador_png else "______________________"
        t = RX_IMG_PRESTADOR.sub(lambda m: guardar(img), t)
        if valores.firmado_en:
            t = RX_RAYA.sub(lambda m: guardar(f"<span class='v'>{fecha_ar(valores.firmado_en)}</span>"), t, count=1)
    elif prestador and valores.estampar_prestador and valores.firmado_en and valores.firma_prestador_png:
        # renglón del prestador o del médico: «Firma: ____ [Aclaración: …] Fecha: ____»
        rayas = RX_RAYA.findall(t)
        if len(rayas) == 2:
            t = RX_RAYA.sub(lambda m: guardar(f"<img class='firma' src='{_data_uri(valores.firma_prestador_png)}'>"), t, count=1)
            t = RX_RAYA.sub(lambda m: guardar(f"<span class='v'>{fecha_ar(valores.firmado_en)}</span>"), t, count=1)
    t = html.escape(t, quote=False)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"(?<![*\w])\*(?!\s)([^*]+?)\*(?![*\w])", r"<i>\1</i>", t)
    return re.sub(r"\x00(\d+)\x00", lambda m: piezas[int(m.group(1))], t)


def _es_prestador(lineas) -> bool:
    return any(l.startswith(("Por el Prestador", "Médico:")) for l in lineas) or \
        (any("Firma:" in l for l in lineas) and not any("{{" in l for l in lineas))


def _html_bloque(clase, lineas, valores) -> str:
    prestador = _es_prestador(lineas)
    if clase == "h3":
        return "<h3>%s</h3>" % _inline(lineas[0], valores, False)
    if clase == "firma":
        return "<p class='firma'>%s</p>" % "<br>".join(_inline(l, valores, prestador) for l in lineas)
    if clase == "aviso":
        return "<p class='aviso'>%s</p>" % _inline(lineas[0], valores, False)
    return "<p>%s</p>" % _inline(lineas[0], valores, prestador)


def cabecera_de(titulo: str) -> str:
    t = re.sub(r"<[^>]+>", "", titulo).title().replace("Y ", "y ").replace("De ", "de ").replace("Con ", "con ")
    return t.replace("\\", "").replace('"', "'")


def html_documento(md: str, valores: Valores, constancia_html: str = "") -> str:
    titulo, subtitulo, bloques = bloques_de(md)
    partes, abierto = [], False
    for clase, lineas, en_firmas in bloques:
        if clase == "h3" and en_firmas and not abierto:
            partes.append("<div style='break-inside: avoid; page-break-inside: avoid'>")
            abierto = True
        partes.append(_html_bloque(clase, lineas, valores))
    if abierto:
        partes.append("</div>")
    sin = Valores(valores.tipo, {})
    return ("<!doctype html><html><head><meta charset='utf-8'><style>%s</style></head><body>\n<h1>%s</h1><h2>%s</h2>\n%s\n%s</body></html>"
            % (CSS_PDF % {"cabecera": cabecera_de(titulo)}, _inline(titulo, sin, False), _inline(subtitulo, sin, False),
               "\n".join(partes), constancia_html))


def pdf_de_html(doc_html: str) -> bytes:
    from weasyprint import HTML  # import tardío: las reglas y la página se prueban sin WeasyPrint
    salida = io.BytesIO()
    HTML(string=doc_html).write_pdf(salida)
    datos = salida.getvalue()
    if not datos.startswith(b"%PDF") or b"%%EOF" not in datos[-2048:]:
        raise RuntimeError("el render no devolvió un PDF completo")
    return datos


def pdf_documento(md: str, valores: Valores, constancia_html: str = "") -> bytes:
    return pdf_de_html(html_documento(md, valores, constancia_html))


def para_pagina(md: str, valores: Valores) -> dict:
    """Lo que muestra la página: el documento hasta FIRMAS como HTML, y la sección de firmas partida en piezas, en el
    orden del documento. La pieza del firmante no viaja como HTML: la página pone ahí sus propios controles."""
    titulo, subtitulo, bloques = bloques_de(md)
    sin = Valores(valores.tipo, {})
    cuerpo, firmas = [], []
    k_firma = "{{@%s}}" % reglas.CAMPO_FIRMA[valores.tipo]
    for clase, lineas, en_firmas in bloques:
        if not en_firmas:
            cuerpo.append(_html_bloque(clase, lineas, valores))
            continue
        junto = "\n".join(lineas)
        if clase == "h3":
            continue
        if k_firma in junto:
            firmas.append({"pieza": "firmante"})
        elif "{{@cInicio}}" in junto:
            firmas.append({"pieza": "inicio_anticipado", "html": _inline(junto.replace("{{@cInicio}}", "").strip(), sin, False)})
        elif _es_prestador(lineas):
            firmas.append({"pieza": "prestador", "html": "<br>".join(_inline(l, valores, True) for l in lineas)})
        else:
            firmas.append({"pieza": "aviso", "html": _inline(junto, sin, False)})
    if sum(1 for f in firmas if f["pieza"] == "firmante") != 1:
        raise ValueError("la plantilla no tiene exactamente un bloque de firma del firmante")
    # CCyC 1111: el último aviso (revocación) tiene que quedar inmediatamente antes de la firma
    if firmas[-1]["pieza"] != "firmante":
        raise ValueError("el bloque del firmante no es el último de FIRMAS")
    return {"titulo": _inline(titulo, sin, False), "subtitulo": _inline(subtitulo, sin, False),
            "cuerpo_html": "\n".join(cuerpo), "firmas": firmas}


def _fila(th, td, mono=False):
    return "<tr><th>%s</th><td%s>%s</td></tr>" % (html.escape(th), " class='mono'" if mono else "", td)


def _e(v) -> str:
    return html.escape(str(v if v is not None else ""), quote=False)


def constancia(datos: dict) -> str:
    """La página de constancia que cierra el PDF firmado. `datos` lo arma el servicio con lo que consta en la base."""
    d = datos
    filas = [
        _fila("Documento", _e(d["titulo"])),
        _fila("Versión del texto", f"{_e(d['plantilla_id'])} — SHA-256 del texto: <span class='mono'>{_e(d['fuente_sha256'])}</span>"),
        _fila("Identificador", _e(d["documento_id"]), True),
        _fila("Firmante", f"{_e(d['nombre'])} — documento {_e(d['documento'])}"),
        _fila("Correo verificado", f"{_e(d['email'])} (código de un solo uso enviado a ese correo y validado el {_e(hora_utc(d['codigo_validado_en']))})"),
        _fila("Fecha y hora de la firma", f"{_e(hora_utc(d['firmado_en']))}<br>{_e(hora_ar(d['firmado_en']))}<br>Hora del servidor, no la del dispositivo."),
        _fila("Dirección IP", _e(d.get("ip") or "no informada")),
        _fila("Dispositivo", _e(d.get("user_agent") or "no informado")),
        _fila("Documento que se le mostró", f"PDF sin firmar, SHA-256: <span class='mono'>{_e(d['pdf_base_sha256'])}</span>"),
    ]
    casillas = "".join("<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (
        "Marcada" if c["valor"] else "Sin marcar", _e(c["texto"]), _e(hora_utc(c["ts"])) if c.get("ts") else "")
        for c in d["casillas"])
    recorrido = "".join("<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (_e(hora_utc(e["ts"])), _e(e["que"]), _e(e.get("ip") or ""))
                        for e in d["recorrido"])
    extra = ""
    if d.get("correcciones"):
        extra += "<p><b>Datos corregidos por el firmante al firmar:</b> " + "; ".join(
            f"{_e(c['campo'])}: «{_e(c['antes'])}» → «{_e(c['despues'])}»" for c in d["correcciones"]) + ".</p>"
    if d.get("prestador"):
        extra += f"<p>{_e(d['prestador'])}</p>"
    return f"""
<div class='constancia'>
<h3>CONSTANCIA DE FIRMA ELECTRÓNICA</h3>
<p>Esta página forma parte del documento firmado y deja constancia de cómo se firmó. La generó el servidor de Pump Team en el momento de la firma.</p>
<table>{''.join(filas)}</table>
<p><b>Manifestaciones del firmante</b></p>
<table><tr><th style='width:12%'>Estado</th><th style='width:66%'>Texto</th><th>Hora</th></tr>{casillas}</table>
<p><b>Recorrido</b></p>
<table><tr><th style='width:24%'>Hora</th><th style='width:52%'>Qué pasó</th><th>IP</th></tr>{recorrido}</table>
{extra}
<p>Método: firma electrónica. El firmante abrió su enlace personal, leyó el documento, escribió su nombre y su documento, validó un código de un solo uso enviado a su correo, dibujó su firma y confirmó. Se le envía una copia de este PDF a ese correo. La huella SHA-256 de este PDF completo recibe un sello de tiempo de una autoridad externa (RFC 3161) y queda en el registro de eventos encadenado.</p>
<p>Verificación: {_e(d['url_verificar'])} — con el identificador de arriba o subiendo este PDF.</p>
</div>"""


def pagina_revocacion(datos: dict) -> str:
    d = datos
    return f"""
<div class='constancia'>
<h3>REVOCACIÓN DEL CONSENTIMIENTO</h3>
<p>El paciente <b>{_e(d['nombre'])}</b>, documento {_e(d['documento'])}, revoca el consentimiento otorgado en este mismo documento. La revocación rige desde su fecha y no alcanza a los actos ya realizados.</p>
<table>
{_fila("Identificador", _e(d["documento_id"]), True)}
{_fila("Consentimiento firmado el", _e(hora_utc(d["firmado_en"])))}
{_fila("Revocado el", _e(hora_utc(d["revocado_en"])) + "<br>" + _e(hora_ar(d["revocado_en"])))}
{_fila("Correo verificado", _e(d["email"]) + " (código de un solo uso validado para esta revocación)")}
{_fila("Dirección IP", _e(d.get("ip") or "no informada"))}
{_fila("Dispositivo", _e(d.get("user_agent") or "no informado"))}
{_fila("Motivo (optativo)", _e(d.get("motivo") or "no indicó"))}
{_fila("PDF del consentimiento firmado", "SHA-256: <span class='mono'>" + _e(d["pdf_final_sha256"]) + "</span>")}
</table>
<p>Se envió copia de este documento al correo del paciente y queda agregado a su historia clínica.</p>
</div>"""


def limpiar_firma_png(data_url_o_bytes, max_bytes=400_000) -> bytes:
    """Valida el dibujo de la firma y lo vuelve a codificar (no se guarda el archivo que mandó el navegador).
    Rechaza lo que no sea un PNG razonable o un lienzo en blanco."""
    from PIL import Image
    crudo = data_url_o_bytes
    if isinstance(crudo, str):
        m = re.fullmatch(r"data:image/png;base64,([A-Za-z0-9+/=\s]+)", crudo)
        if not m:
            raise ValueError("firma: formato inválido")
        crudo = base64.b64decode(m.group(1), validate=False)
    if not (500 < len(crudo) <= max_bytes) or not crudo.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("firma: tamaño o formato inválido")
    img = Image.open(io.BytesIO(crudo))  # todavía no decodifica: primero el formato y el tamaño declarado
    if img.format != "PNG" or img.width > 2400 or img.height > 1200 or img.width < 120 or img.height < 50:
        raise ValueError("firma: dimensiones inválidas")
    img.load()
    img = img.convert("RGBA")
    fondo = Image.new("RGBA", img.size, (255, 255, 255, 255))
    fondo.alpha_composite(img)
    gris = fondo.convert("L")
    oscuros = sum(gris.histogram()[:128])
    if oscuros < 150 or oscuros > 0.5 * img.width * img.height:
        raise ValueError("firma: vacía")
    salida = io.BytesIO()
    fondo.convert("RGB").save(salida, format="PNG", optimize=True)
    return salida.getvalue()
