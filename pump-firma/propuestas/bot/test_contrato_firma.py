import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import contrato_firma as cf  # noqa: E402


def aviso(**c):
    p = {"action": "contrato_firma", "evento": "firmado", "cuando": "2026-11-10T21:38:23+00:00", "aviso_id": "a-1",
         "documento": {"id": "d-1", "tipo": "servicio_ar", "variante": "AR", "alta_ref": "x"},
         "cliente": {"nombre": "Persona  De Prueba", "email": "p@correo.test", "whatsapp": "+54", "lead_id": 7},
         "firma": {"inicio_anticipado": True, "correcciones": [{"campo": "documento"}], "completados": []},
         "estado": {"bloquea_agenda": False, "servicio_firmado": True, "consentimiento_pendiente": True}}
    p.update(c)
    return p


def test_firmado_avisa_una_sola_vez(tmp_path):
    ruta = str(tmp_path / "log.jsonl")
    http, cuerpo, texto = cf.procesar(aviso(), ruta)
    assert (http, cuerpo) == (200, {"status": "ok"})
    assert texto == ("Persona De Prueba firmó el contrato de coaching (10/11 a las 18:38). Agenda habilitada. "
                     "Le falta firmar el consentimiento médico. Corrigió al firmar: documento. Marcó el inicio anticipado.")
    # si el WhatsApp a Mati falla no se confirma: el reintento vuelve a traer el texto
    assert cf.procesar(aviso(), ruta)[2] == texto
    cf.confirmar(aviso(), ruta)
    assert cf.procesar(aviso(), ruta) == (200, {"status": "repetido"}, None)
    registro = open(ruta).read()
    assert "p@correo.test" not in registro and "+54" not in registro and "Persona" not in registro


def test_revocado_y_baja(tmp_path):
    ruta = str(tmp_path / "log.jsonl")
    _, _, t = cf.procesar(aviso(evento="revocado", aviso_id="a-2", documento={"id": "d-2", "tipo": "consentimiento_ar"}), ruta)
    assert "revocó el consentimiento de atención médica" in t and "no emitir órdenes" in t
    _, _, t = cf.procesar(aviso(evento="baja_pedida", aviso_id="a-3", motivo="Me arrepentí", dias_desde_la_firma=2.4), ruta)
    assert "pidió la revocación o la baja" in t and "a 2 días de la firma" in t and "Motivo: Me arrepentí" in t


def test_invalidos_no_avisan_ni_anotan(tmp_path):
    ruta = str(tmp_path / "log.jsonl")
    for malo in ({}, aviso(evento="otro"), aviso(documento={"id": "d", "tipo": "raro"}), aviso(cliente={"nombre": " "}),
                 aviso(aviso_id=""), aviso(action="onboarding_notification"), "texto", None):
        http, _, texto = cf.procesar(malo, ruta)
        assert http == 400 and texto is None
    assert not os.path.exists(ruta)


def test_agenda_frenada_se_dice(tmp_path):
    _, _, t = cf.procesar(aviso(estado={"bloquea_agenda": True}, firma={}), str(tmp_path / "l"))
    assert "la agenda sigue frenada" in t
