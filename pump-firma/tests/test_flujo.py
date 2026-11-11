import hashlib
import io

import pytest
from pypdf import PdfReader

from firma import reglas, tareas
from firma.servicio import Rechazo
from conftest import CASILLAS_OK, dibujo, token_de_url

IP, UA = "10.0.0.2", "Navegador de prueba"


def texto_pdf(pdf: bytes) -> str:
    return "\n".join(p.extract_text() for p in PdfReader(io.BytesIO(pdf)).pages)


def test_alta_argentina_crea_dos_documentos_y_es_idempotente(srv, alta):
    a = alta()
    r = srv.crear(a, IP, UA)
    assert r["ok"] and [d["tipo"] for d in r["documentos"]] == ["servicio_ar", "consentimiento_ar"]
    assert all(d["estado"] == "pendiente" and d["resultado"] == "creado" for d in r["documentos"])
    r2 = srv.crear(a, IP, UA)  # el mismo envío del formulario otra vez
    assert [d["id"] for d in r2["documentos"]] == [d["id"] for d in r["documentos"]]
    assert all(d["resultado"] == "ya_existia" for d in r2["documentos"])
    assert [d["url"] for d in r2["documentos"]] == [d["url"] for d in r["documentos"]]


def test_alta_exterior_un_solo_documento_y_variante(srv, alta, admin):
    r = srv.crear(alta(residente=False), IP, UA)
    assert [d["tipo"] for d in r["documentos"]] == ["servicio_ext"]
    assert admin("SELECT variante FROM contrato.documentos WHERE id = %s", (r["documentos"][0]["id"],), uno=True)[0] == "ES"
    r = srv.crear(alta(residente=False, pais="México", whatsapp="+52 55"), IP, UA)
    assert admin("SELECT variante FROM contrato.documentos WHERE id = %s", (r["documentos"][0]["id"],), uno=True)[0] == "OTRO"


def test_alta_sin_datos_no_crea_nada(srv, alta, admin):
    a = alta(plan="")
    r = srv.crear(a, IP, UA)
    assert not r["ok"] and r["errores"][0]["error"] == "faltan_datos" and r["documentos"] == []
    assert admin("SELECT count(*) FROM contrato.documentos WHERE alta_ref = %s", (a["alta_ref"],), uno=True)[0] == 0
    assert not srv.crear(alta(email="no-es-mail"), IP, UA)["ok"]
    assert srv.crear({k: v for k, v in alta().items() if k != "residente_argentina"}, IP, UA)["error"] == "falta_residente_argentina"


def test_firma_completa_argentina(srv, alta, smtp, bot, admin, firmar_todo, sellos_falsos):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar", casillas=dict(CASILLAS_OK, inicio_anticipado=True))
    assert r["ok"] and r["estado"] == "firmado" and not r["repetido"] and len(r["sha256"]) == 64

    nombre, pdf = srv.pdf(t, IP, UA)
    assert nombre.endswith("firmado.pdf") and reglas.sha256_hex(pdf) == r["sha256"]
    txt = texto_pdf(pdf)
    assert d["id"] in txt and "Navegador de prueba" in txt and "10.0.0.2" in txt and a["email"] in txt

    antes_bot, antes_mail = len(bot), len(smtp.mensajes)
    res = srv.despachar(d["id"])
    assert res["sellos"] == 2 and res["correos"] == 2 and res["avisos"] == 1 and not (res["sellos_fallan"] or res["correos_fallan"] or res["avisos_fallan"])
    copia = smtp.para(a["email"], "firmad")[-1]
    adj = [p for p in copia["m"].iter_attachments()]
    assert len(adj) == 1 and reglas.sha256_hex(adj[0].get_content()) == r["sha256"]
    assert "archivo@prueba.test" in copia["para"] and "archivo@prueba.test" not in str(copia["m"])
    cust = smtp.para("custodia@ajena.test")[-1]
    nombres = sorted(p.get_filename() for p in cust["m"].iter_attachments())
    assert "firmado.pdf" in nombres and "registro.json" in nombres and sum(n.endswith(".tsr") for n in nombres) == 2
    aviso = bot[-1]
    assert len(bot) == antes_bot + 1 and aviso["cabeceras"]["X-Pump-Onboarding-Secret"] == "secreto-del-bot"
    c = aviso["cuerpo"]
    assert c["action"] == "contrato_firma" and c["evento"] == "firmado" and c["documento"]["tipo"] == "servicio_ar"
    assert c["firma"]["inicio_anticipado"] is True and c["estado"]["servicio_firmado"] is True
    # la agenda depende del contrato de servicio; el consentimiento médico va aparte (se firma solo si se atiende con el médico)
    assert c["estado"]["bloquea_agenda"] is False and c["estado"]["consentimiento_vigente"] is False

    assert srv.despachar(d["id"]) == {k: 0 for k in res}  # nada se manda dos veces
    assert len(smtp.mensajes) == antes_mail + 2

    v = srv.verificar(sha256=r["sha256"])
    assert v["existe"] and v["estado"] == "firmado" and len(v["sellos"]) == 2
    assert srv.verificar(sha256="0" * 64) == {"existe": False}
    assert srv.verificar(doc_id=d["id"])["existe"]


def test_estado_con_los_dos_firmados(srv, alta, smtp, firmar_todo):
    a = alta()
    assert srv.crear(a, IP, UA)["ok"] and srv.estado(email=a["email"])["bloquea_agenda"] is True  # contrato pendiente: agenda cerrada
    firmar_todo(a, "servicio_ar")
    assert srv.estado(email=a["email"])["bloquea_agenda"] is False
    r = srv.crear(a, IP, UA)
    t = token_de_url(next(x for x in r["documentos"] if x["tipo"] == "consentimiento_ar")["url"])
    srv.pedir_codigo(t, "firma", IP, UA)
    cuerpo = {"casillas": dict(CASILLAS_OK), "nombre": "Ana Maria Perez Ñandu", "documento": "30111222", "firma_png": dibujo(), "codigo": smtp.codigo(a["email"])}
    assert srv.firmar(t, cuerpo, IP, UA)["estado"] == "firmado"
    e = srv.estado(email=a["email"])
    assert e["servicio_firmado"] and e["consentimiento_vigente"] and e["bloquea_agenda"] is False


def test_sin_documentos_no_bloquea_pero_lo_dice(srv):
    e = srv.estado(email="nadie@correo.test")
    assert e["documentos"] == [] and e["servicio_firmado"] is False


def test_no_se_firma_sin_casillas_identidad_dibujo_ni_codigo(srv, alta, smtp):
    a = alta()
    t = token_de_url(srv.crear(a, IP, UA)["documentos"][0]["url"])
    srv.pedir_codigo(t, "firma", IP, UA)
    bien = {"casillas": dict(CASILLAS_OK), "nombre": "Ana María Pérez Ñandú", "documento": "30111222", "firma_png": dibujo(), "codigo": smtp.codigo(a["email"])}
    for cambio, error in (({"casillas": {"electronico": True}}, "casillas"), ({"casillas": {"electronico": "true", "lei_acepto": 1}}, "casillas"),
                          ({"nombre": "Otra Persona"}, "identidad"), ({"documento": "30111223"}, "identidad"),
                          ({"firma_png": dibujo(vacio=True)}, "firma"), ({"firma_png": None}, "firma"),
                          ({"codigo": ""}, "incorrecto"), ({"codigo": "abc"}, "incorrecto")):
        with pytest.raises(Rechazo) as e:
            srv.firmar(t, dict(bien, **cambio), IP, UA)
        assert e.value.codigo == error, cambio
    assert srv.ver(t, IP, UA)["estado"] == "pendiente"
    assert srv.firmar(t, bien, IP, UA)["estado"] == "firmado"


def test_codigo_incorrecto_cinco_veces_bloquea(srv, alta, smtp, admin):
    a = alta()
    r = srv.crear(a, IP, UA)
    t = token_de_url(r["documentos"][0]["url"])
    srv.pedir_codigo(t, "firma", IP, UA)
    bueno = smtp.codigo(a["email"])
    malo = "000000" if bueno != "000000" else "111111"
    cuerpo = {"casillas": dict(CASILLAS_OK), "nombre": "Ana María Pérez Ñandú", "documento": "30111222", "firma_png": dibujo(), "codigo": malo}
    codigos = []
    for _ in range(5):
        with pytest.raises(Rechazo) as e:
            srv.firmar(t, cuerpo, IP, UA)
        codigos.append(e.value.codigo)
    assert codigos == ["incorrecto"] * 4 + ["bloqueado"]
    with pytest.raises(Rechazo) as e:  # ni con el bueno: hay que pedir otro
        srv.firmar(t, dict(cuerpo, codigo=bueno), IP, UA)
    assert e.value.codigo == "sin_codigo"
    with pytest.raises(Rechazo) as e:  # y no enseguida
        srv.pedir_codigo(t, "firma", IP, UA)
    assert e.value.codigo == "esperar"


def test_codigo_vencido_y_limite_por_hora(srv, alta, smtp, admin):
    a = alta()
    r = srv.crear(a, IP, UA)
    doc_id, t = r["documentos"][0]["id"], token_de_url(r["documentos"][0]["url"])
    srv.pedir_codigo(t, "firma", IP, UA)
    admin("UPDATE contrato.codigos SET vence_en = now() - interval '1 minute' WHERE documento_id = %s", (doc_id,))
    cuerpo = {"casillas": dict(CASILLAS_OK), "nombre": "Ana María Pérez Ñandú", "documento": "30111222", "firma_png": dibujo(), "codigo": smtp.codigo(a["email"])}
    with pytest.raises(Rechazo) as e:
        srv.firmar(t, cuerpo, IP, UA)
    assert e.value.codigo == "vencido"
    for _ in range(4):
        admin("UPDATE contrato.codigos SET creado_en = creado_en - interval '50 seconds' WHERE documento_id = %s", (doc_id,))
        srv.pedir_codigo(t, "firma", IP, UA)
    admin("UPDATE contrato.codigos SET creado_en = creado_en - interval '50 seconds' WHERE documento_id = %s", (doc_id,))
    with pytest.raises(Rechazo) as e:
        srv.pedir_codigo(t, "firma", IP, UA)
    assert e.value.codigo == "limite"
    # el último código emitido sí sirve; uno anterior, no
    assert srv.firmar(t, dict(cuerpo, codigo=smtp.codigo(a["email"])), IP, UA)["estado"] == "firmado"


def test_codigo_de_un_documento_no_sirve_en_otro(srv, alta, smtp):
    a = alta()
    r = srv.crear(a, IP, UA)
    t1, t2 = (token_de_url(d["url"]) for d in r["documentos"])
    srv.pedir_codigo(t1, "firma", IP, UA)
    c1 = smtp.codigo(a["email"])
    srv.pedir_codigo(t2, "firma", IP, UA)
    c2 = smtp.codigo(a["email"])
    if c1 == c2:
        pytest.skip("códigos iguales por azar")
    cuerpo = {"casillas": dict(CASILLAS_OK), "nombre": "Ana María Pérez Ñandú", "documento": "30111222", "firma_png": dibujo(), "codigo": c1}
    with pytest.raises(Rechazo) as e:
        srv.firmar(t2, cuerpo, IP, UA)
    assert e.value.codigo == "incorrecto"


def test_doble_toque_no_firma_dos_veces(srv, alta, smtp, admin, firmar_todo):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")
    otra = srv.firmar(t, {"casillas": {}, "codigo": "000000"}, IP, UA)
    assert otra["repetido"] and otra["sha256"] == r["sha256"]
    assert admin("SELECT count(*) FROM contrato.eventos WHERE documento_id = %s AND tipo = 'firmado'", (d["id"],), uno=True)[0] == 1
    assert admin("SELECT count(*) FROM contrato.correos WHERE documento_id = %s AND tipo = 'copia_firmado'", (d["id"],), uno=True)[0] == 1
    with pytest.raises(Rechazo):  # ya firmado: no se piden más códigos de firma
        srv.pedir_codigo(t, "firma", IP, UA)


def test_enlace_invalido_y_anulado(srv, alta):
    for malo in ("", "abc", "g" * 48, "0" * 48, "0" * 200):
        with pytest.raises(Rechazo) as e:
            srv.ver(malo, IP, UA)
        assert e.value.http == 404
    r = srv.crear(alta(), IP, UA)
    d = r["documentos"][0]
    assert srv.anular(d["id"], "prueba", IP, UA)["resultado"] == "anulado"
    with pytest.raises(Rechazo) as e:
        srv.ver(token_de_url(d["url"]), IP, UA)
    assert e.value.http == 410


def test_firmado_no_se_anula_ni_se_reemplaza(srv, alta, firmar_todo):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")
    assert srv.anular(d["id"], "prueba", IP, UA)["resultado"] != "anulado"
    assert srv.reenviar(d["id"], {"email": "otro@correo.test"}, IP, UA)["error"] == "no_reemplazable"
    assert srv.ver(t, IP, UA)["estado"] == "firmado"


def test_reenviar_con_mail_corregido_cambia_todos_los_pendientes(srv, alta, smtp):
    a = alta()
    r = srv.crear(a, IP, UA)
    viejos = {d["tipo"]: d for d in r["documentos"]}
    nuevo_mail = "corregido-" + a["email"]
    r2 = srv.reenviar(viejos["servicio_ar"]["id"], {"email": nuevo_mail}, IP, UA)
    assert r2["ok"], r2
    nuevos = {d["tipo"]: d for d in r2["documentos"]}
    assert set(nuevos) == {"servicio_ar", "consentimiento_ar"}  # el hermano no queda con el correo equivocado
    for tipo, n in nuevos.items():
        assert n["id"] != viejos[tipo]["id"] and n["url"] != viejos[tipo]["url"] and n["email"] == nuevo_mail
        with pytest.raises(Rechazo) as e:
            srv.ver(token_de_url(viejos[tipo]["url"]), IP, UA)
        assert e.value.http == 410
    t = token_de_url(nuevos["servicio_ar"]["url"])
    srv.pedir_codigo(t, "firma", IP, UA)
    assert smtp.para(nuevo_mail) and not smtp.para(a["email"])
    # corregir solo el precio toca solo el contrato
    r3 = srv.reenviar(nuevos["servicio_ar"]["id"], {"precio": "USD 200 en un pago"}, IP, UA)
    assert r3["ok"] and [d["tipo"] for d in r3["documentos"]] == ["servicio_ar"]
    assert "USD 200" in srv.ver(token_de_url(r3["documentos"][0]["url"]), IP, UA)["cuerpo_html"]


def test_formulario_reenviado_con_un_dato_corregido(srv, alta, admin, firmar_todo):
    a = alta()
    r = srv.crear(a, IP, UA)
    r2 = srv.crear(dict(a, precio="USD 150 en dos pagos"), IP, UA)  # mismo envío, precio corregido
    assert r2["ok"]
    por_tipo = {d["tipo"]: d for d in r2["documentos"]}
    assert por_tipo["servicio_ar"]["id"] != r["documentos"][0]["id"] and por_tipo["servicio_ar"]["resultado"] != "ya_existia"
    assert por_tipo["consentimiento_ar"]["resultado"] == "ya_existia"  # el consentimiento no lleva precio: no cambia
    with pytest.raises(Rechazo):
        srv.ver(token_de_url(r["documentos"][0]["url"]), IP, UA)  # el del precio viejo ya no se puede firmar
    assert "USD 150" in srv.ver(token_de_url(por_tipo["servicio_ar"]["url"]), IP, UA)["cuerpo_html"]
    # otro día (otra referencia), misma persona: los pendientes de antes se anulan; queda un solo juego firmable
    b = dict(a, alta_ref=a["alta_ref"] + "-otro-dia", precio="USD 150 en dos pagos")
    assert srv.crear(b, IP, UA)["ok"]
    assert admin("SELECT count(*) FROM contrato.documentos WHERE lower(firmante_email) = %s AND estado = 'pendiente'", (a["email"],), uno=True)[0] == 2
    # ya firmado y el formulario vuelve con otro precio: no se toca y se avisa
    d, t, f = firmar_todo(b, "servicio_ar")
    r3 = srv.crear(dict(b, precio="USD 1"), IP, UA)
    assert not r3["ok"] and r3["errores"] == [{"tipo": "servicio_ar", "error": "ya_firmado_con_otros_datos"}]
    assert srv.ver(t, IP, UA)["estado"] == "firmado"


def test_baja_se_resuelve_y_destraba(srv, alta, smtp, firmar_todo, admin):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")
    assert srv.resolver_baja(d["id"], "sigue", "", IP, UA)["resultado"] == "sin_baja_pedida"
    admin("UPDATE contrato.codigos SET creado_en = creado_en - interval '50 seconds' WHERE documento_id = %s", (d["id"],))
    srv.pedir_codigo(t, "baja", IP, UA)
    srv.pedir_baja(t, {"codigo": smtp.codigo(a["email"]), "motivo": "x"}, IP, UA)
    e = srv.estado(email=a["email"])
    assert e["bloquea_agenda"] and e["baja_abierta"] and not e["servicio_firmado"]
    assert srv.resolver_baja(d["id"], "cualquiera", "", IP, UA)["resultado"] == "resultado_invalido"
    assert srv.resolver_baja(d["id"], "sigue", "Lo hablamos y continúa", IP, UA)["resultado"] == "resuelta"
    e = srv.estado(email=a["email"])
    assert not e["bloquea_agenda"] and not e["baja_abierta"] and e["servicio_firmado"]
    assert srv.resolver_baja(d["id"], "terminado", "", IP, UA)["resultado"] == "ya_resuelta"
    with pytest.raises(Exception):
        admin("UPDATE contrato.documentos SET baja_resultado = 'terminado' WHERE id = %s", (d["id"],))


def test_no_vincula_un_lead_dudoso(srv, alta, admin):
    from firma import tareas
    a = alta()
    srv.crear(a, IP, UA)
    # mismo teléfono pero otro correo (un familiar): no es el mismo
    admin("INSERT INTO public.onboarding_leads (nombre, email, whatsapp) VALUES ('x', %s, %s)", ("otro-" + a["email"], a["whatsapp"]))
    # mismo correo pero nacido mucho después
    admin("INSERT INTO public.onboarding_leads (nombre, email, whatsapp, created_at) VALUES ('x', %s, %s, now() + interval '5 days')", (a["email"], a["whatsapp"]))
    tareas.ciclo(srv)
    assert admin("SELECT count(*) FROM contrato.documentos WHERE alta_ref = %s AND lead_id IS NOT NULL", (a["alta_ref"],), uno=True)[0] == 0
    # dos candidatos con el mismo correo: tampoco
    for _ in range(2):
        admin("INSERT INTO public.onboarding_leads (nombre, email, whatsapp) VALUES ('x', %s, %s)", (a["email"], a["whatsapp"]))
    tareas.ciclo(srv)
    assert admin("SELECT count(*) FROM contrato.documentos WHERE alta_ref = %s AND lead_id IS NOT NULL", (a["alta_ref"],), uno=True)[0] == 0


def test_estado_con_lead_no_toma_documentos_de_otro_lead(srv, alta, admin):
    a = alta()
    srv.crear(a, IP, UA)
    admin("INSERT INTO public.onboarding_leads (nombre, email, whatsapp) VALUES ('x', %s, %s)", (a["email"], a["whatsapp"]))
    lead_a = admin("SELECT max(id) FROM public.onboarding_leads WHERE email = %s", (a["email"],), uno=True)[0]
    from firma import tareas
    assert tareas.ciclo(srv)["altas_vinculadas"] == 1
    # otra persona (otro lead, sin documentos) que comparte el WhatsApp: no queda frenada por el contrato de la primera
    e = srv.estado(lead_id=lead_a + 100000, whatsapp=a["whatsapp"])
    assert e["bloquea_agenda"] is False and e["documentos"] == []
    assert srv.estado(lead_id=lead_a, whatsapp=a["whatsapp"])["bloquea_agenda"] is True


def test_correccion_de_identidad_queda_en_la_constancia(srv, alta, smtp, firmar_todo, admin):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar", documento="30111999", confirma_correccion=["documento"], domicilio="Otra Calle 456")
    txt = texto_pdf(srv.pdf(t, IP, UA)[1])
    assert "30111999" in txt and "Otra Calle 456" in txt
    firma = admin("SELECT firma FROM contrato.documentos WHERE id = %s", (d["id"],), uno=True)[0]
    assert {c["campo"] for c in firma["correcciones"]} == {"documento", "domicilio"}


def test_espana_boton_aviso_y_casilla(srv, alta, smtp, firmar_todo):
    a = alta(residente=False)
    r = srv.crear(a, IP, UA)
    t = token_de_url(r["documentos"][0]["url"])
    v = srv.ver(t, IP, UA)
    assert "obligación de pago" in v["boton"] and v["aviso_es"] and "desist" in str(v["aviso_es"]).lower()
    assert [c["clave"] for c in v["casillas"]] == ["electronico", "lei_acepto", "inicio_anticipado"]
    assert v["documento_rotulo"] == "Documento"
    d, t, r = firmar_todo(a, "servicio_ext", casillas=dict(CASILLAS_OK, inicio_anticipado=True))
    assert r["estado"] == "firmado"
    assert srv.estado(email=a["email"])["bloquea_agenda"] is False  # exterior: alcanza con el contrato
    b = srv.ver(t, IP, UA)
    assert b["baja"] and not b["puede_revocar"]


def test_otro_pais_sin_boton_de_espana(srv, alta):
    r = srv.crear(alta(residente=False, pais="México"), IP, UA)
    v = srv.ver(token_de_url(r["documentos"][0]["url"]), IP, UA)
    assert v["aviso_es"] is None and "obligación de pago" not in v["boton"]
    assert [c["clave"] for c in v["casillas"]] == ["electronico", "lei_acepto", "inicio_anticipado"]  # optativa, del propio contrato


def test_revocar_consentimiento(srv, alta, smtp, bot, firmar_todo, admin):
    a = alta()
    d, t, r = firmar_todo(a, "consentimiento_ar")
    srv.despachar(d["id"])
    assert srv.estado(email=a["email"])["consentimiento_vigente"] is True
    with pytest.raises(Rechazo):
        srv.revocar(t, {"codigo": "000000"}, IP, UA)  # sin código pedido
    admin("UPDATE contrato.codigos SET creado_en = creado_en - interval '50 seconds' WHERE documento_id = %s", (d["id"],))
    srv.pedir_codigo(t, "revocacion", IP, UA)
    rv = srv.revocar(t, {"codigo": smtp.codigo(a["email"]), "motivo": "No quiero seguir <b>"}, IP, UA)
    assert rv["estado"] == "revocado" and not rv["repetido"]
    nombre, pdf = srv.pdf(t, IP, UA)
    txt = texto_pdf(pdf)
    assert nombre.endswith("revocado.pdf") and "No quiero seguir" in txt and r["sha256"] in txt.replace("\n", "")
    # el firmado original sigue intacto y verificable
    v = srv.verificar(sha256=r["sha256"])
    assert v["existe"] and v["estado"] == "revocado"
    res = srv.despachar(d["id"])
    assert res["correos"] == 2 and res["avisos"] == 1 and res["sellos"] == 2
    assert bot[-1]["cuerpo"]["evento"] == "revocado" and bot[-1]["cuerpo"]["estado"]["consentimiento_vigente"] is False
    assert srv.revocar(t, {"codigo": "x"}, IP, UA)["repetido"] is True


def test_el_contrato_no_se_revoca_se_pide_la_baja(srv, alta, smtp, bot, firmar_todo, admin):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")
    srv.despachar(d["id"])
    with pytest.raises(Rechazo):
        srv.revocar(t, {"codigo": "000000"}, IP, UA)
    admin("UPDATE contrato.codigos SET creado_en = creado_en - interval '50 seconds' WHERE documento_id = %s", (d["id"],))
    srv.pedir_codigo(t, "baja", IP, UA)
    b = srv.pedir_baja(t, {"codigo": smtp.codigo(a["email"]), "motivo": "Me arrepentí"}, IP, UA)
    assert b["ok"] and b["baja_pedida_en"]
    res = srv.despachar(d["id"])
    assert res["correos"] == 1 and res["avisos"] == 1
    c = bot[-1]["cuerpo"]
    assert c["evento"] == "baja_pedida" and c["motivo"] == "Me arrepentí" and c["dias_desde_la_firma"] < 1
    assert c["estado"]["bloquea_agenda"] is True and c["estado"]["servicio_firmado"] is False  # con baja pedida no se agenda
    assert srv.ver(t, IP, UA)["estado"] == "firmado"  # la baja la resuelve una persona; el documento firmado no cambia


def test_si_falla_correo_sello_o_bot_queda_pendiente_y_se_reintenta(srv, alta, smtp, bot, firmar_todo, sellos_falsos, admin):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")
    smtp.rechazar, bot.fallar, sellos_falsos.fallar = True, True, True
    res = srv.despachar(d["id"])
    # la copia al firmante falla; la de custodia ni se intenta: espera a los sellos
    assert res["correos_fallan"] == 1 and res["custodia_espera_sello"] == 1 and res["avisos_fallan"] == 1 and res["sellos_fallan"] == 2
    assert res["correos"] == res["avisos"] == res["sellos"] == 0
    assert srv.ver(t, IP, UA)["estado"] == "firmado"  # la firma no depende de eso
    smtp.rechazar, bot.fallar, sellos_falsos.fallar = False, False, False
    # enseguida no reintenta (espera creciente), y nunca abandona por cantidad de intentos
    res = srv.despachar(d["id"])
    assert res["sellos"] == 2 and res["correos"] == 0 and res["avisos"] == 0
    admin("UPDATE contrato.correos SET intentos = 500, proximo_en = now() - interval '1 second' WHERE documento_id = %s AND estado <> 'enviado'", (d["id"],))
    admin("UPDATE contrato.avisos SET intentos = 500, proximo_en = now() - interval '1 second' WHERE documento_id = %s", (d["id"],))
    res = srv.despachar(d["id"])
    assert res["correos"] == 2 and res["avisos"] == 1
    cust = smtp.para("custodia@ajena.test")[-1]
    assert sum((p.get_filename() or "").endswith(".tsr") for p in cust["m"].iter_attachments()) == 2  # con los sellos adentro


def test_no_manda_codigo_si_el_correo_no_sale(srv, alta, smtp, admin):
    a = alta()
    r = srv.crear(a, IP, UA)
    smtp.rechazar = True
    with pytest.raises(Rechazo) as e:
        srv.pedir_codigo(token_de_url(r["documentos"][0]["url"]), "firma", IP, UA)
    assert e.value.codigo == "correo"
    tipos = [x[0] for x in admin("SELECT tipo FROM contrato.eventos WHERE documento_id = %s ORDER BY n", (r["documentos"][0]["id"],))]
    assert tipos[-1] == "codigo_no_enviado"


def test_pdf_guardado_alterado_no_se_entrega(srv, alta, firmar_todo, cfg):
    import glob
    import os
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")
    ruta = glob.glob(os.path.join(cfg.datos, "**", "firmado-*.pdf"), recursive=True)[0]
    os.chmod(ruta, 0o600)
    with open(ruta, "ab") as f:
        f.write(b"x")
    with pytest.raises(Exception):
        srv.pdf(t, IP, UA)


def test_cadena_de_eventos_integra_y_recalculable(srv, alta, firmar_todo, admin):
    firmar_todo(alta(), "servicio_ar")
    cols = "n, documento_id::text, tipo, ts, ip, user_agent, datos, prev_hash, hash"
    evs = [dict(zip([c.split("::")[0].strip() for c in cols.split(",")], f)) for f in admin(f"SELECT {cols} FROM contrato.eventos ORDER BY n")]
    v = reglas.verificar_cadena(evs)
    assert v["ok"], v
    assert v["n"] == len(evs) and v["cabeza"] == evs[-1]["hash"]
    evs[3]["ip"] = "1.2.3.4"
    assert not reglas.verificar_cadena(evs)["ok"]


def test_app_ve_sus_documentos_por_token(srv, alta, admin, firmar_todo):
    a = alta()
    tok = "tok-" + a["alta_ref"]
    admin("INSERT INTO public.onboarding_leads (nombre, email, whatsapp, linked_client_id) VALUES ('x', %s, %s, %s)", (a["email"], a["whatsapp"], "cli-" + a["alta_ref"]))
    admin("INSERT INTO public.mypump_clientes (cliente_id, nombre, access_token) VALUES (%s, 'x', %s)", ("cli-" + a["alta_ref"], tok))
    lead = admin("SELECT id FROM public.onboarding_leads WHERE email = %s", (a["email"],), uno=True)[0]
    a["lead_id"] = lead
    firmar_todo(a, "servicio_ar")
    docs = srv.docs_de_app(tok)
    assert {d["tipo"]: d["estado"] for d in docs} == {"servicio_ar": "firmado", "consentimiento_ar": "pendiente"}
    assert all(d["url"].startswith("https://firma.prueba.test/f/") for d in docs)
    assert srv.docs_de_app("token-que-no-existe") is None
    admin("UPDATE public.mypump_clientes SET access_token_active = false WHERE access_token = %s", (tok,))
    assert srv.docs_de_app(tok) is None


def test_estado_no_mezcla_personas_y_decide_el_contrato_mas_nuevo(srv, alta, firmar_todo, admin):
    a = alta()
    firmar_todo(a, "servicio_ar")
    # otra persona con el mismo WhatsApp (familiar) y contrato pendiente: no bloquea a la primera
    b = alta(whatsapp=a["whatsapp"])
    assert srv.crear(b, IP, UA)["ok"]
    e = srv.estado(email=a["email"], whatsapp=a["whatsapp"])
    assert e["encontrado_por"] == "email" and e["bloquea_agenda"] is False and len(e["documentos"]) == 2
    assert srv.estado(email=b["email"], whatsapp=b["whatsapp"])["bloquea_agenda"] is True
    # recompra de la misma persona: contrato nuevo pendiente → vuelve a bloquear hasta que firme el nuevo
    c = alta(email=a["email"], whatsapp=a["whatsapp"])
    assert srv.crear(c, IP, UA)["ok"]
    assert srv.estado(email=a["email"])["bloquea_agenda"] is True
    # solo por WhatsApp, sin mail
    assert srv.estado(whatsapp=b["whatsapp"])["encontrado_por"] == "whatsapp"
    with pytest.raises(Exception):
        srv.estado()


def test_tareas_ciclo_y_diario(srv, alta, smtp, firmar_todo, cfg, admin, sellos_falsos):
    import json
    import os
    import subprocess
    import sys
    from firma import tareas
    d, t, r = firmar_todo(alta(), "servicio_ar")
    c = tareas.ciclo(srv)
    assert c["sellos"] >= 2 and c["correos"] >= 2 and c["fallan"] == 0
    res = tareas.diario(srv, "2026-01-02")
    assert res["cadena_ok"] and res["sellos"] == 2 and res["custodia"] is True and res["eventos"] > 5
    carpeta = os.path.join(cfg.datos, "respaldo", "2026-01-02")
    assert sorted(os.listdir(carpeta))[:2] == [f"cadena-{res['cabeza']['n']}-digicert.tsr", f"cadena-{res['cabeza']['n']}-globalsign.tsr"]
    assert any(x["id"] == d["id"] and x["estado"] == "firmado" for x in json.load(open(os.path.join(carpeta, "documentos.json"))))
    assert admin("SELECT count(*) FROM contrato.sellos WHERE objeto = 'cadena' AND sha256 = %s", (res["cabeza"]["hash"],), uno=True)[0] == 2
    assert "cadena de eventos" in smtp.para("custodia@ajena.test")[-1]["m"]["Subject"]
    # el respaldo en disco se verifica solo, sin la base
    herramienta = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools", "verificar_cadena.py")
    archivo = os.path.join(carpeta, "eventos.jsonl")
    assert subprocess.run([sys.executable, herramienta, "--archivo", archivo], capture_output=True).returncode == 0
    lineas = open(archivo, encoding="utf-8").read().splitlines()
    lineas[2] = lineas[2].replace('"ip": ', '"ip": "6.6.6.6", "ip_vieja": ', 1)
    open(archivo, "w", encoding="utf-8").write("\n".join(lineas))
    assert subprocess.run([sys.executable, herramienta, "--archivo", archivo], capture_output=True).returncode == 1


def test_invitacion_por_correo_una_sola_vez(srv, alta, smtp, admin):
    a = alta()
    r = srv.crear(a, IP, UA)
    srv.crear(a, IP, UA)  # el formulario llega dos veces
    res = srv.despachar()
    inv = smtp.para(a["email"], "para leer y firmar")
    assert len(inv) == 2  # una por documento, en correos separados, como hoy
    cuerpos = [m["m"].get_body(("plain",)).get_content() for m in inv]
    assert all(any(d["url"] in c for c in cuerpos) for d in r["documentos"])
    assert any("firmarlo es tu decisión" in c for c in cuerpos)  # el del consentimiento médico
    srv.despachar()
    assert len(smtp.para(a["email"], "para leer y firmar")) == 2
    # con invitar=false (por ejemplo, si el enlace se entrega por otro lado) no sale correo
    b = alta(invitar=False)
    srv.crear(b, IP, UA)
    srv.despachar()
    assert smtp.para(b["email"]) == []


def test_invitacion_no_sale_si_ya_firmo_o_se_anulo(srv, alta, smtp, firmar_todo):
    a = alta()
    d, t, r = firmar_todo(a, "servicio_ar")  # firma antes de que salga la invitación
    otro = next(x for x in srv.crear(a, IP, UA)["documentos"] if x["tipo"] == "consentimiento_ar")
    srv.anular(otro["id"], "prueba", IP, UA)
    srv.despachar()
    assert smtp.para(a["email"], "para leer y firmar") == []
    assert smtp.para(a["email"], "firmado")


def test_el_alta_se_vincula_sola_cuando_aparece_el_lead(srv, alta, admin):
    from firma import tareas
    a = alta()
    r = srv.crear(a, IP, UA)
    assert tareas.ciclo(srv)["altas_vinculadas"] == 0
    admin("INSERT INTO public.onboarding_leads (nombre, email, whatsapp, linked_client_id) VALUES ('x', %s, %s, %s)", (a["email"].upper(), a["whatsapp"], "cli-" + a["alta_ref"]))
    admin("INSERT INTO public.mypump_clientes (cliente_id, nombre, access_token) VALUES (%s, 'x', %s)", ("cli-" + a["alta_ref"], "tk-" + a["alta_ref"]))
    assert tareas.ciclo(srv)["altas_vinculadas"] == 1
    assert {d["tipo"] for d in srv.docs_de_app("tk-" + a["alta_ref"])} == {"servicio_ar", "consentimiento_ar"}
    assert tareas.ciclo(srv)["altas_vinculadas"] == 0


def _huella(ref):
    return hashlib.sha256(ref.encode()).hexdigest()[:16]


def _frenadas_del_bot(bot, ref):
    return [x["cuerpo"] for x in bot if x["cuerpo"].get("evento") == "alta_frenada" and x["cuerpo"]["alta"]["ref"] == _huella(ref)]


def test_alta_frenada_avisa_que_falta_y_repite_hasta_resolverse(srv, alta, bot, smtp, admin):
    a = alta(precio="", objetivo="  ")
    a["alta_ref"] = ref = f"form-{a['email']}-5491100000000-2026-11-10"  # la forma real: trae el correo adentro
    r = srv.crear(a, IP, UA)
    assert not r["ok"] and r["errores"][0] == {"tipo": "servicio_ar", "error": "faltan_datos", "campos": ["cObjetivo", "cPrecio"]}
    # no nace ningún documento, pero queda anotada (y en la cadena, sin datos de la persona)
    assert admin("SELECT count(*) FROM contrato.documentos WHERE alta_ref = %s", (ref,), uno=True)[0] == 0
    f = admin("SELECT tipo, faltan, avisos, resuelto_en FROM contrato.altas_frenadas WHERE alta_ref = %s", (ref,), uno=True)
    assert f == ("servicio_ar", ["cObjetivo", "cPrecio"], 0, None)
    ev = admin("SELECT datos FROM contrato.eventos WHERE tipo = 'alta_frenada' AND datos LIKE %s", (f"%{_huella(ref)}%",))
    assert len(ev) == 1 and a["email"] not in ev[0][0] and "Ana" not in ev[0][0]
    with srv.base.conexion() as s:
        assert ref in s.f("pendientes_de_atencion", 0)["altas_frenadas"]

    # el primer aviso sale enseguida y dice qué falta, con palabras
    d = srv.despachar()
    assert d["frenadas_avisadas"] >= 1
    avisos = _frenadas_del_bot(bot, ref)
    assert len(avisos) == 1 and avisos[0]["action"] == "contrato_firma"
    assert avisos[0]["alta"]["faltan"] == ["el objetivo", "el precio"] and avisos[0]["alta"]["aviso_n"] == 1
    assert avisos[0]["cliente"]["nombre"].startswith("Ana") and avisos[0]["aviso_id"] == f"frenada:{_huella(ref)}:1" and a["email"] not in avisos[0]["aviso_id"]

    # no se repite antes de tiempo, ni porque el formulario vuelva a llegar igual de incompleto
    srv.despachar()
    assert not srv.crear(a, IP, UA)["ok"]
    srv.despachar()
    assert len(_frenadas_del_bot(bot, ref)) == 1
    assert len(admin("SELECT 1 FROM contrato.eventos WHERE tipo = 'alta_frenada' AND datos LIKE %s", (f"%{_huella(ref)}%",))) == 1

    # pasado un día sigue sin resolverse: avisa de nuevo
    admin("UPDATE contrato.altas_frenadas SET ultimo_aviso_en = ultimo_aviso_en - interval '25 hours' WHERE alta_ref = %s", (ref,))
    srv.despachar()
    avisos = _frenadas_del_bot(bot, ref)
    assert len(avisos) == 2 and avisos[1]["alta"]["aviso_n"] == 2 and avisos[1]["aviso_id"] != avisos[0]["aviso_id"]

    # llega corregido a medias: lo que falta cambió, se avisa enseguida con lo que falta ahora
    assert not srv.crear({**a, "objetivo": "Objetivo de prueba"}, IP, UA)["ok"]
    srv.despachar()
    avisos = _frenadas_del_bot(bot, ref)
    assert len(avisos) == 3 and avisos[2]["alta"]["faltan"] == ["el precio"]

    # llega completo: nace el contrato, queda resuelta y no se avisa más
    r = srv.crear({**a, "objetivo": "Objetivo de prueba", "precio": "USD 100 en un pago"}, IP, UA)
    assert r["ok"] and len(r["documentos"]) == 2
    assert admin("SELECT resultado FROM contrato.altas_frenadas WHERE alta_ref = %s AND resuelto_en IS NOT NULL", (ref,), uno=True)[0] == "emitido"
    admin("UPDATE contrato.altas_frenadas SET ultimo_aviso_en = ultimo_aviso_en - interval '25 hours' WHERE alta_ref = %s", (ref,))
    srv.despachar()
    assert len(_frenadas_del_bot(bot, ref)) == 3
    with srv.base.conexion() as s:
        assert ref not in s.f("pendientes_de_atencion", 0)["altas_frenadas"]
    assert reglas.verificar_cadena(list(tareas.traer_cadena(srv)))["ok"]


def test_alta_frenada_si_el_bot_no_responde_va_por_correo_y_se_reintenta(srv, alta, bot, smtp, admin, cfg):
    a = alta(plan="")
    ref = a["alta_ref"]
    srv.crear(a, IP, UA)
    bot.fallar = True
    # sin bot y sin casilla interna: no se da por avisada, se reintenta
    assert srv.despachar()["frenadas_fallan"] >= 1
    assert admin("SELECT avisos, ultimo_aviso_en FROM contrato.altas_frenadas WHERE alta_ref = %s", (ref,), uno=True) == (0, None)
    # con casilla interna, el aviso sale por correo y dice qué falta
    cfg.aviso_interno = "interno@prueba.test"
    admin("UPDATE contrato.altas_frenadas SET tomado_en = tomado_en - interval '6 minutes' WHERE alta_ref = %s", (ref,))
    assert srv.despachar()["frenadas_avisadas"] >= 1
    m = smtp.para("interno@prueba.test", "contrato sin emitir: falta el plan")
    assert len(m) == 1 and a["email"] in m[0]["m"].get_body(("plain",)).get_content()
    assert admin("SELECT avisos FROM contrato.altas_frenadas WHERE alta_ref = %s", (ref,), uno=True)[0] == 1
    # una persona que resuelve con otro envío del formulario (otra referencia, mismo correo) también la cierra
    bot.fallar = False
    assert srv.crear({**alta(), "email": a["email"]}, IP, UA)["ok"]
    assert admin("SELECT resultado FROM contrato.altas_frenadas WHERE alta_ref = %s", (ref,), uno=True)[0] == "emitido"


def test_alta_frenada_se_descarta_a_mano(srv, alta, bot, admin):
    a = alta(precio="")
    srv.crear(a, IP, UA)
    assert srv.descartar_alta_frenada(_huella(a["alta_ref"]), "no va a seguir", IP, UA) == {"ok": True}  # por la huella del aviso
    ev = admin("SELECT datos FROM contrato.eventos WHERE tipo = 'alta_descartada' AND datos LIKE %s", (f"%{_huella(a['alta_ref'])}%",))
    assert len(ev) == 1 and "no va a seguir" not in ev[0][0]
    assert srv.descartar_alta_frenada(a["alta_ref"], "otra vez", IP, UA) == {"ok": False}
    srv.despachar()
    assert _frenadas_del_bot(bot, a["alta_ref"]) == []
    assert admin("SELECT resultado FROM contrato.altas_frenadas WHERE alta_ref = %s", (a["alta_ref"],), uno=True)[0] == "descartada: no va a seguir"


def test_alta_frenada_reenviada_otro_dia_no_duplica_avisos(srv, alta, bot, admin):
    a = alta(precio="")
    srv.crear(a, IP, UA)
    srv.despachar()
    # al día siguiente el formulario trae otra referencia, igual de incompleto: es la misma persona
    b = {**a, "alta_ref": a["alta_ref"] + "-dia2"}
    srv.crear(b, IP, UA)
    filas = admin("SELECT alta_ref, resultado, avisos FROM contrato.altas_frenadas WHERE email = %s ORDER BY visto_en", (a["email"],))
    assert filas == [(a["alta_ref"], "reemplazada", 1), (b["alta_ref"], None, 1)]
    srv.despachar()
    assert len(_frenadas_del_bot(bot, a["alta_ref"])) == 1 and _frenadas_del_bot(bot, b["alta_ref"]) == []
    # pasadas las 24 h avisa una sola (la abierta), con el número que sigue
    admin("UPDATE contrato.altas_frenadas SET ultimo_aviso_en = ultimo_aviso_en - interval '25 hours' WHERE email = %s", (a["email"],))
    srv.despachar()
    assert len(_frenadas_del_bot(bot, a["alta_ref"])) == 1
    assert [x["alta"]["aviso_n"] for x in _frenadas_del_bot(bot, b["alta_ref"])] == [2]
    # pasados los 14 días sin novedades deja de avisar, pero sigue contando como pendiente
    admin("UPDATE contrato.altas_frenadas SET visto_en = visto_en - interval '15 days', ultimo_aviso_en = ultimo_aviso_en - interval '15 days' "
          "WHERE alta_ref = %s", (b["alta_ref"],))
    srv.despachar()
    assert len(_frenadas_del_bot(bot, b["alta_ref"])) == 1
    with srv.base.conexion() as s:
        assert b["alta_ref"] in s.f("pendientes_de_atencion", 0)["altas_frenadas"]


def test_envio_incompleto_no_rompe_el_enlace_vivo_y_se_cierra_al_volver_completo(srv, alta, bot, admin):
    a = alta()
    r = srv.crear(a, IP, UA)
    url = r["documentos"][0]["url"]
    # reenvío incompleto (misma alta, y otro día con otra referencia): no anula el pendiente bueno
    assert not srv.crear({**a, "precio": ""}, IP, UA)["ok"]
    assert not srv.crear({**a, "precio": "", "alta_ref": a["alta_ref"] + "-dia2"}, IP, UA)["ok"]
    assert admin("SELECT count(*) FROM contrato.documentos WHERE firmante_email = %s AND estado = 'pendiente'", (a["email"],), uno=True)[0] == 2
    srv.ver(token_de_url(url), IP, UA)  # el enlace sigue sirviendo (anulado daría Rechazo)
    assert admin("SELECT count(*) FROM contrato.altas_frenadas WHERE email = %s AND resuelto_en IS NULL", (a["email"],), uno=True)[0] == 1
    # vuelve a llegar igual al original: no nace nada nuevo, pero la frenada se cierra y no avisa de más
    r = srv.crear(a, IP, UA)
    assert r["ok"] and r["documentos"][0]["url"] == url
    assert admin("SELECT count(*) FROM contrato.altas_frenadas WHERE email = %s AND resuelto_en IS NULL", (a["email"],), uno=True)[0] == 0


def test_alta_frenada_un_200_sin_acuse_del_bot_no_cuenta_como_avisada(srv, alta, bot, admin):
    a = alta(objetivo="")
    srv.crear(a, IP, UA)
    bot.respuesta = b'{"status": "ignored"}'  # un bot sin el parche, que contesta 200 a lo que no conoce
    assert srv.despachar()["frenadas_fallan"] >= 1
    assert admin("SELECT avisos, ultimo_aviso_en FROM contrato.altas_frenadas WHERE alta_ref = %s", (a["alta_ref"],), uno=True) == (0, None)


def test_si_falla_la_base_de_frenadas_no_se_rompe_crear_ni_despachar(srv, alta, monkeypatch):
    from firma import base as _base
    real = _base.Sesion.f

    def f(self, funcion, *args):
        if "frenada" in funcion:
            raise RuntimeError("base caída")
        return real(self, funcion, *args)
    monkeypatch.setattr(_base.Sesion, "f", f)
    r = srv.crear(alta(plan=""), IP, UA)
    assert not r["ok"] and r["errores"][0]["error"] == "faltan_datos" and r["errores"][0]["sin_anotar"] is True
    assert srv.despachar()["frenadas_fallan"] == 1
