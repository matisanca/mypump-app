import os

import pytest

from firma import reglas


def test_residencia_como_el_apps_script():
    assert reglas.es_residente_argentino("Argentina", "+34 600") is True
    assert reglas.es_residente_argentino("España", "+54 9 11") is False
    assert reglas.es_residente_argentino("", "+54 9 11 5555") is True
    assert reglas.es_residente_argentino("", "+34 600") is False


def test_variante():
    assert reglas.variante_de("España", False) == "ES"
    assert reglas.variante_de("espana", False) == "ES"
    assert reglas.variante_de("México", False) == "OTRO"
    assert reglas.variante_de("España", True) == "AR"


def test_token_determinista_y_distinto_por_numero():
    s = b"x" * 40
    a, b = reglas.token_de(s, "doc", 1), reglas.token_de(s, "doc", 2)
    assert a == reglas.token_de(s, "doc", 1) and a != b and len(a) == 48
    assert reglas.token_de(b"y" * 40, "doc", 1) != a


def test_codigo_hmac_depende_de_documento_y_proposito():
    s = b"x" * 40
    assert reglas.codigo_hmac(s, "d1", "firma", "123456") != reglas.codigo_hmac(s, "d2", "firma", "123456")
    assert reglas.codigo_hmac(s, "d1", "firma", "123456") != reglas.codigo_hmac(s, "d1", "baja", "123456")
    assert reglas.codigo_valido_forma("012345") and not reglas.codigo_valido_forma("12345a") and not reglas.codigo_valido_forma("1234567")


def test_identidad_coincide_sin_acentos_ni_mayusculas():
    campos = reglas.campos_de_alta("servicio_ar", {"nombre": "Ana María", "apellido": "Pérez", "dni": "30.111.222", "domicilio": "Calle 1234"})
    r = reglas.resolver_identidad("servicio_ar", "AR", campos, {"nombre": "ana maria perez", "documento": "30111222"})
    assert r["ok"] and not r["correcciones"]
    assert r["campos"]["cNombre2"] == campos["cNombre1"] and r["campos"]["cDni2"] == campos["cDni1"]


def test_identidad_distinta_no_pasa_sin_confirmar():
    campos = reglas.campos_de_alta("servicio_ar", {"nombre": "Ana", "apellido": "Pérez", "dni": "30111222", "domicilio": "Calle 1234"})
    r = reglas.resolver_identidad("servicio_ar", "AR", campos, {"nombre": "Ana Peres", "documento": "30111223"})
    assert not r["ok"] and {e["campo"] for e in r["errores"]} == {"nombre", "documento"}
    r = reglas.resolver_identidad("servicio_ar", "AR", campos, {"nombre": "Ana Peres", "documento": "30111223",
                                                                "confirma_correccion": ["nombre", "documento"]})
    assert r["ok"] and len(r["correcciones"]) == 2 and r["campos"]["cDni1"] == "30111223" and r["campos"]["cNombre1"] == "Ana Peres"


def test_identidad_completa_lo_que_faltaba():
    campos = reglas.campos_de_alta("consentimiento_ar", {"nombre": "Ana", "apellido": "Pérez", "dni": "", "domicilio": ""})
    r = reglas.resolver_identidad("consentimiento_ar", "AR", campos, {"nombre": "Ana Pérez", "documento": "30111222"})
    assert not r["ok"] and r["errores"] == [{"campo": "domicilio", "error": "incompleto"}]
    r = reglas.resolver_identidad("consentimiento_ar", "AR", campos, {"nombre": "Ana Pérez", "documento": "30111222", "domicilio": "Calle 1234"})
    assert r["ok"] and set(r["completados"]) == {"documento", "domicilio"} and r["campos"]["mDni2"] == "30111222"


def test_documento_argentino_y_pasaporte():
    assert reglas.documento_valido("30.111.222", "AR") and not reglas.documento_valido("AB12", "AR")
    assert reglas.documento_valido("X1234567T", "OTRO") and not reglas.documento_valido("12", "OTRO")


def test_casillas_obligatorias():
    assert reglas.validar_casillas("servicio_ar", "AR", {"electronico": True}) == ["lei_acepto"]
    assert reglas.validar_casillas("consentimiento_ar", "AR", {"electronico": True, "lei_acepto": True}) == ["datos_salud"]
    assert "inicio_en_desistimiento" in reglas.casillas_de("servicio_ext", "ES")
    assert "inicio_en_desistimiento" not in reglas.casillas_de("servicio_ext", "OTRO")
    assert reglas.validar_casillas("servicio_ext", "ES", {"electronico": True, "lei_acepto": True}) == []


def test_faltantes_bloquean_el_alta():
    c = reglas.campos_de_alta("servicio_ar", {"nombre": "Ana", "apellido": "Pérez", "plan": "", "objetivo": "o", "precio": "p"})
    assert "cPlan" in reglas.faltantes("servicio_ar", c)


def test_alta_ref_estable():
    a = {"email": "A@b.com", "whatsapp": "1", "marca_temporal": "2026-11-10 10:00"}
    assert reglas.alta_ref(a) == reglas.alta_ref(dict(a, email="a@b.com")) != reglas.alta_ref(dict(a, marca_temporal="x"))


def test_cadena_detecta_alteracion():
    from datetime import datetime, timezone
    ts = datetime(2026, 11, 10, 12, 0, 0, 123456, tzinfo=timezone.utc)
    evs, prev = [], "0" * 64
    for n in (1, 2, 3):
        h = reglas.sha256_hex(reglas.evento_canon(prev, n, "d", "t", ts, "ip", "ua", "{}").encode())
        evs.append({"n": n, "documento_id": "d", "tipo": "t", "ts": ts, "ip": "ip", "user_agent": "ua", "datos": "{}", "prev_hash": prev, "hash": h})
        prev = h
    assert reglas.verificar_cadena(evs)["ok"]
    evs[1]["datos"] = '{"x":1}'
    assert reglas.verificar_cadena(evs) == {"ok": False, "n": 2, "cabeza": evs[0]["hash"], "error": "el evento 2 fue alterado"}
    del evs[1]
    assert not reglas.verificar_cadena(evs)["ok"]


# ── Decisiones del 10/11: una sola videollamada, sin reembolso pasado el plazo (AR), desistimiento europeo completo ──
def _sintetica(tipo):
    """Un texto inventado que cumple: todas las frases vigentes y ninguna retirada."""
    import cargar_plantillas as cp
    return "# T\n\n" + " ; ".join(cp.EXIGIDAS[tipo]) + "."


def test_plantilla_con_un_texto_retirado_no_se_carga():
    import cargar_plantillas as cp
    for tipo in ("servicio_ar", "servicio_ext"):
        bien = _sintetica(tipo)
        assert cp.texto_retirado(tipo, bien) == []
        for vieja in cp.RETIRADAS[tipo]:  # cada redacción vieja, sola, frena la carga
            assert any("retirado" in m for m in cp.texto_retirado(tipo, bien + " " + vieja)), vieja
        for vigente in cp.EXIGIDAS[tipo]:  # y a la plantilla no le puede faltar ninguna de las vigentes
            assert any("falta" in m for m in cp.texto_retirado(tipo, bien.replace(vigente, "otra cosa"))), vigente
    # aunque venga con otras mayúsculas, negritas o partido en dos renglones
    partido = _sintetica("servicio_ext") + " (c) la asistencia a la Totalidad de las **sesiones de\ncoaching** y de los check-ins"
    assert cp.texto_retirado("servicio_ext", partido) != []
    assert cp.texto_retirado("consentimiento_ar", "cualquier texto") == []
    with pytest.raises(SystemExit, match="no se carga"):
        cp.cargar(None, "servicio_ar", "v8", _sintetica("servicio_ar") + " sesiones de coaching individual")
    with pytest.raises(SystemExit, match="no se carga"):  # la 14.2 con el 30 % y devolución del excedente
        cp.cargar(None, "servicio_ar", "v9", _sintetica("servicio_ar") + " 14.2. Desistimiento del Cliente. una suma fija")
    with pytest.raises(SystemExit, match="no se carga"):  # la cláusula 10 del exterior que no informaba el desistimiento
        cp.cargar(None, "servicio_ext", "v4", "# T\n\nuna videollamada individual de entrega y acompañamiento del proceso por mensajes")


def test_variante_con_desistimiento_de_14_dias_para_toda_europa():
    for pais in ("España", "Italia", "Alemania", "Países Bajos", "Reino Unido", "Irlanda", "France", "UK", "Noruega"):
        assert reglas.variante_de(pais, False) == "ES", pais
    for pais in ("Estados Unidos", "México", "Chile", "Uruguay", "", "Australia", "Ukrania"):
        assert reglas.variante_de(pais, False) == "OTRO", pais
    assert reglas.variante_de("España", True) == "AR"


def test_las_plantillas_reales_vigentes():
    """Corre donde están las fuentes privadas (PUMP_FIRMA_FUENTES); en el repo público se saltea. Las versiones
    anteriores, si están en la carpeta, tienen que ser rechazadas por el cargador."""
    import hashlib
    import cargar_plantillas as cp
    carpeta = os.environ.get("PUMP_FIRMA_FUENTES", "")
    vigentes = {"servicio_ar": ("A_v11.md", "a83186488e6b4642267ee5065c71bb62"), "servicio_ext": ("E_v6.md", "41b57e9097eb3e30cf8833a0a9ef09f1")}
    if not all(os.path.exists(os.path.join(carpeta, a)) for a, _ in vigentes.values()):
        pytest.skip("sin las fuentes privadas")
    for tipo, (archivo, md5) in vigentes.items():
        md = open(os.path.join(carpeta, archivo), "rb").read().decode("utf-8")
        assert hashlib.md5(md.encode()).hexdigest() == md5, archivo
        assert cp.texto_retirado(tipo, md) == [], archivo
        assert "videollamadas" not in md.lower() and "sesiones de coaching" not in md.lower(), archivo
    for tipo, viejas in {"servicio_ar": ("A_v8.md", "A_v9.md", "A_v10.md"), "servicio_ext": ("E_v3.md", "E_v4.md", "E_v5.md")}.items():
        for archivo in viejas:
            ruta = os.path.join(carpeta, archivo)
            if os.path.exists(ruta):
                assert cp.texto_retirado(tipo, open(ruta, encoding="utf-8").read()) != [], archivo
