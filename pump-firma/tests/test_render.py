import io
import os
from datetime import datetime, timezone

import pytest
from pypdf import PdfReader

from firma import reglas, render
from conftest import dibujo

AQUI = os.path.dirname(os.path.abspath(__file__))


def md(tipo):
    return open(os.path.join(AQUI, "plantillas", tipo + ".md"), encoding="utf-8").read()


def texto_pdf(pdf: bytes) -> str:
    return "\n".join(p.extract_text() for p in PdfReader(io.BytesIO(pdf)).pages)


ALTA = {"nombre": "José <b>Ñ</b>", "apellido": "O'Connor & Cía", "dni": "30111222", "domicilio": "Av. Siempre Viva 742 {{@cFirma}}",
        "pais": "Argentina", "plan": "Plan 3 meses", "objetivo": "Bajar grasa", "precio": "USD 100\nen dos cuotas"}


@pytest.mark.parametrize("tipo", ["servicio_ar", "servicio_ext", "consentimiento_ar"])
def test_pdf_a_firmar_sin_etiquetas_y_con_los_datos(tipo):
    campos = reglas.campos_de_alta(tipo, ALTA)
    pdf = render.pdf_documento(md(tipo), render.Valores(tipo, campos))
    t = texto_pdf(pdf)
    assert pdf.startswith(b"%PDF") and "{{" not in t.replace("{{@cFirma}}", "")
    assert "O'Connor & Cía" in t and "<b>" in t  # lo escrito se muestra tal cual, sin interpretarse como HTML
    assert "30111222" in t


def test_un_valor_no_puede_inyectar_etiquetas():
    campos = reglas.campos_de_alta("servicio_ar", ALTA)
    h = render.html_documento(md("servicio_ar"), render.Valores("servicio_ar", campos))
    assert "<b>Ñ</b>" not in h and "&lt;b&gt;Ñ&lt;/b&gt;" in h
    # el domicilio trae «{{@cFirma}}» escrito: no se reemplaza por la firma
    assert h.count("Av. Siempre Viva 742 {{@cFirma}}") == 1


def test_mismo_dato_mismo_pdf_base():
    campos = reglas.campos_de_alta("servicio_ar", ALTA)
    a = render.html_documento(md("servicio_ar"), render.Valores("servicio_ar", campos))
    b = render.html_documento(md("servicio_ar"), render.Valores("servicio_ar", campos))
    assert a == b


def test_pdf_firmado_lleva_firma_fecha_y_constancia():
    campos = reglas.campos_de_alta("servicio_ar", ALTA)
    ahora = datetime(2026, 11, 10, 15, 30, tzinfo=timezone.utc)
    png = render.limpiar_firma_png(dibujo())
    cons = render.constancia({"titulo": "T", "plantilla_id": "servicio_ar@prueba1", "fuente_sha256": "a" * 64, "documento_id": "doc-1",
                              "nombre": campos["cNombre2"], "documento": "30111222", "email": "x@y.test", "codigo_validado_en": ahora,
                              "firmado_en": ahora, "ip": "10.0.0.1", "user_agent": "UA <script>", "pdf_base_sha256": "b" * 64,
                              "casillas": [{"clave": "lei_acepto", "valor": True, "texto": "Leí y acepto", "ts": ahora}],
                              "recorrido": [{"ts": ahora, "que": "Abrió el documento", "ip": "10.0.0.1"}], "correcciones": [],
                              "url_verificar": "https://firma.prueba.test/verificar", "prestador": ""})
    assert "<script>" not in cons
    pdf = render.pdf_documento(md("servicio_ar"), render.Valores("servicio_ar", campos, firmado_en=ahora, firma_png=png, inicio_anticipado=True), cons)
    t = texto_pdf(pdf)
    assert "doc-1" in t and "b" * 64 in t.replace("\n", "") and "Leí y acepto" in t
    assert "10/11/2026" in t or "10 de noviembre de 2026" in t
    assert len(PdfReader(io.BytesIO(pdf)).pages) >= 2


def test_precio_largo_no_rompe():
    alta = dict(ALTA, precio="\n".join(f"Cuota {i}: USD 100 el día {i} de cada mes, con recargo si se atrasa" for i in range(1, 25)))
    campos = reglas.campos_de_alta("servicio_ar", alta)
    t = texto_pdf(render.pdf_documento(md("servicio_ar"), render.Valores("servicio_ar", campos)))
    assert "Cuota 1:" in t and "Cuota 12:" in t


def test_pagina_separa_cuerpo_y_firmas():
    campos = reglas.campos_de_alta("servicio_ar", ALTA)
    p = render.para_pagina(md("servicio_ar"), render.Valores("servicio_ar", campos))
    assert p["titulo"] and "Cláusula sintética" in p["cuerpo_html"]
    piezas = [f["pieza"] for f in p["firmas"]]
    assert "inicio_anticipado" in piezas
    assert "<script" not in p["cuerpo_html"]


def test_dibujo_vacio_o_raro_se_rechaza():
    for malo in (dibujo(vacio=True), "data:image/png;base64,AAAA", "data:text/html;base64,AAAA", None, "x"):
        with pytest.raises(Exception):
            render.limpiar_firma_png(malo)
    assert render.limpiar_firma_png(dibujo()).startswith(b"\x89PNG")
