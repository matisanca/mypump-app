import pytest
from fastapi.testclient import TestClient

from firma.app import crear_app
from conftest import CASILLAS_OK, SECRETO_INTERNO, dibujo, token_de_url

INT = {"X-Pump-Firma-Secreto": SECRETO_INTERNO}


@pytest.fixture()
def web(cfg, srv):
    return TestClient(crear_app(cfg, srv, despacho_en_linea=True), raise_server_exceptions=False)


def test_interno_exige_el_secreto(web, alta):
    for ruta in ("crear", "reenviar", "anular", "estado", "despachar", "descartar_alta"):
        assert web.post(f"/api/interno/{ruta}", json=alta()).status_code == 401
        assert web.post(f"/api/interno/{ruta}", json=alta(), headers={"X-Pump-Firma-Secreto": "x" * 40}).status_code == 401


def test_recorrido_completo_por_http(web, alta, smtp, bot):
    a = alta()
    r = web.post("/api/interno/crear", json=a, headers=INT).json()
    assert r["ok"] and len(r["documentos"]) == 2
    url = r["documentos"][0]["url"]
    t = token_de_url(url)
    pagina = web.get(f"/f/{t}")
    assert pagina.status_code == 200 and "text/html" in pagina.headers["content-type"]
    csp = pagina.headers["content-security-policy"]
    assert "default-src 'none'" in csp and "unsafe-inline" not in csp.split("script-src")[1].split(";")[0]
    assert pagina.headers["x-frame-options"] == "DENY" and pagina.headers["referrer-policy"] == "no-referrer"
    assert pagina.headers["cache-control"].startswith("no-store")
    assert t not in pagina.text  # la página no trae nada del alumno: lo pide después
    for n in ("firma.js", "firma.css", "verificar.js"):
        assert web.get(f"/static/{n}").status_code == 200
    assert web.get("/static/../firma/config.py").status_code == 404

    d = web.post("/api/doc", json={"t": t}).json()
    assert d["estado"] == "pendiente" and d["cuerpo_html"] and "@" in d["correo"] and a["email"] not in str(d)
    pdf = web.get(f"/f/{t}/documento.pdf")
    assert pdf.status_code == 200 and pdf.content.startswith(b"%PDF")
    assert web.post("/api/evento", json={"t": t, "tipo": "fin_lectura"}).json() == {"ok": True}
    assert web.post("/api/evento", json={"t": t, "tipo": "casilla", "datos": {"casilla": "lei_acepto", "valor": True}}).status_code == 200
    assert web.post("/api/evento", json={"t": t, "tipo": "casilla", "datos": {"casilla": "inventada", "valor": True}}).status_code == 400
    assert web.post("/api/evento", json={"t": t, "tipo": "firmado"}).status_code == 400
    c = web.post("/api/codigo", json={"t": t, "proposito": "firma"})
    assert c.status_code == 200 and c.json()["ok"]
    assert web.post("/api/codigo", json={"t": t, "proposito": "firma"}).status_code == 429
    cuerpo = {"t": t, "casillas": CASILLAS_OK, "nombre": f"{a['nombre']} {a['apellido']}", "documento": a["dni"], "firma_png": dibujo(), "codigo": "abc"}
    mal = web.post("/api/firmar", json=cuerpo)
    assert mal.status_code == 400 and mal.json()["error"] == "incorrecto"
    f = web.post("/api/firmar", json=dict(cuerpo, codigo=smtp.codigo(a["email"])))
    assert f.status_code == 200 and f.json()["estado"] == "firmado"
    assert smtp.para(a["email"], "firmad") and bot[-1]["cuerpo"]["evento"] == "firmado"  # el despacho salió solo

    firmado = web.get(f"/f/{t}/documento.pdf").content
    v = web.post("/api/verificar/pdf", files={"archivo": ("x.pdf", firmado, "application/pdf")}).json()
    assert v["existe"] and v["sha256"] == f.json()["sha256"] and v["estado"] == "firmado"
    alterado = web.post("/api/verificar/pdf", files={"archivo": ("x.pdf", firmado + b" ", "application/pdf")}).json()
    assert alterado["existe"] is False
    assert web.post("/api/verificar/pdf", files={"archivo": ("x.pdf", b"no es pdf", "application/pdf")}).status_code == 400
    assert web.post("/api/verificar", json={"id": r["documentos"][0]["id"]}).json()["existe"]
    assert a["email"] not in str(web.post("/api/verificar", json={"sha256": f.json()["sha256"]}).json())  # verificar no revela datos

    e = web.post("/api/interno/estado", json={"email": a["email"]}, headers=INT).json()
    assert e["servicio_firmado"] is True and e["bloquea_agenda"] is False
    s = web.get("/salud").json()
    assert s["ok"] and s["correo"] and s["custodia"]


def test_enlace_malo_y_cuerpos_raros(web):
    assert web.post("/api/doc", json={"t": "0" * 48}).status_code == 404
    assert web.post("/api/doc", json={}).status_code == 404
    assert web.post("/api/doc", content=b"no json").status_code == 400
    assert web.post("/api/doc", content=b"[1]").status_code == 400
    assert web.post("/api/firmar", content=b"x" * 800_000).status_code == 413
    assert web.get("/f/" + "0" * 48 + "/documento.pdf").status_code == 404
    assert web.get("/docs").status_code == 404 and web.get("/openapi.json").status_code == 404


def test_app_fase2_por_http(web, alta, admin):
    assert web.post("/api/app/documentos", json={"token": "no-existe"}).status_code == 401
    pre = web.options("/api/app/documentos", headers={"Origin": "https://app.mypumpteam.com"})
    assert pre.status_code == 204 and pre.headers["access-control-allow-origin"] == "https://app.mypumpteam.com"
    assert "access-control-allow-origin" not in web.options("/api/app/documentos", headers={"Origin": "https://otro.test"}).headers


def test_freno_por_ip(web):
    codigos = [web.post("/api/doc", json={"t": "0" * 48}, headers={"cf-connecting-ip": "9.9.9.9"}).status_code for _ in range(95)]
    assert codigos[0] == 404 and codigos[-1] == 429
    assert web.post("/api/doc", json={"t": "0" * 48}, headers={"cf-connecting-ip": "8.8.8.8"}).status_code == 404


def test_alta_incompleta_por_http_avisa_enseguida(web, alta, bot):
    a = alta(precio="")
    r = web.post("/api/interno/crear", json=a, headers=INT).json()
    assert r["ok"] is False and r["errores"][0]["campos"] == ["cPrecio"]
    avisos = [x["cuerpo"] for x in bot if x["cuerpo"].get("evento") == "alta_frenada" and x["cuerpo"]["cliente"]["email"] == a["email"]]
    assert len(avisos) == 1 and avisos[0]["alta"]["faltan"] == ["el precio"]
    assert web.post("/api/interno/descartar_alta", json={"alta_ref": a["alta_ref"], "motivo": "prueba"}, headers=INT).json() == {"ok": True}
