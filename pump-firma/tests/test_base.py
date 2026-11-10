"""La base se defiende sola: aunque el servicio tenga un error, el rol con el que corre no puede reescribir la historia."""
import psycopg

from firma.base import Base
import pytest

IP, UA = "10.0.0.2", "Navegador de prueba"


def como_firma_srv(db_url, sql, args=None):
    with Base(db_url, intentos=6)._conectar() as c, c.cursor() as cur:
        cur.execute("SET LOCAL ROLE firma_srv")
        cur.execute(sql, args)
        return cur.fetchall() if cur.description else None


@pytest.mark.parametrize("sql", [
    "SELECT * FROM contrato.documentos", "SELECT * FROM contrato.eventos", "SELECT * FROM contrato.codigos",
    "UPDATE contrato.documentos SET estado = 'firmado'", "DELETE FROM contrato.eventos", "INSERT INTO contrato.autorizaciones (rol, tipo, quien, firma_sha256, constancia) VALUES ('medico','consentimiento_ar','x',repeat('a',64),'x')",
    "UPDATE contrato.plantillas SET vigente = false", "SELECT * FROM public.mypump_clientes", "SELECT * FROM public.onboarding_leads",
    "SELECT contrato.plantillas_inmutables()", "TRUNCATE contrato.eventos",
])
def test_firma_srv_no_toca_tablas(db_url, sql):
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        como_firma_srv(db_url, sql)


@pytest.mark.parametrize("rol", ["anon", "authenticated"])
def test_anon_no_ve_nada_del_esquema(db_url, rol):
    for sql in ("SELECT * FROM contrato.documentos", "SELECT contrato.doc_por_id(gen_random_uuid())", "SELECT contrato.cadena(0, 10)",
                "SELECT public.contrato_estado(NULL, 'a@b.c', NULL)"):
        with Base(db_url, intentos=6)._conectar() as c, c.cursor() as cur:
            cur.execute(f"SET LOCAL ROLE {rol}")
            with pytest.raises(psycopg.errors.InsufficientPrivilege):
                cur.execute(sql)


def test_ni_el_duenio_edita_eventos_sellos_ni_plantillas(admin, srv, alta, firmar_todo):
    d, t, r = firmar_todo(alta(), "servicio_ar")
    srv.despachar(d["id"])
    for sql in ("UPDATE contrato.eventos SET ip = 'x' WHERE documento_id = %s", "DELETE FROM contrato.eventos WHERE documento_id = %s",
                "UPDATE contrato.sellos SET tsa = 'x' WHERE documento_id = %s", "DELETE FROM contrato.sellos WHERE documento_id = %s",
                "DELETE FROM contrato.documentos WHERE id = %s",
                "UPDATE contrato.documentos SET pdf_final_sha256 = repeat('0', 64) WHERE id = %s",
                "UPDATE contrato.documentos SET estado = 'pendiente' WHERE id = %s",
                "UPDATE contrato.documentos SET firma = '{}'::jsonb WHERE id = %s",
                "UPDATE contrato.documentos SET campos = '{}'::jsonb WHERE id = %s"):
        with pytest.raises(psycopg.Error):
            admin(sql, (d["id"],))
    with pytest.raises(psycopg.Error):
        admin("UPDATE contrato.plantillas SET fuente_md = 'otro texto' WHERE tipo = 'servicio_ar'")
    with pytest.raises(psycopg.Error):
        admin("DELETE FROM contrato.plantillas")
    with pytest.raises(psycopg.Error):
        admin("INSERT INTO contrato.plantillas (id, tipo, version, titulo, fuente_md, fuente_sha256, fuente_md5) VALUES ('x','servicio_ar','x','t','texto',repeat('a',64),md5('texto'))")


def test_una_sola_plantilla_vigente_por_tipo(admin):
    with pytest.raises(psycopg.Error):
        admin("INSERT INTO contrato.plantillas (id, tipo, version, titulo, fuente_md, fuente_sha256, fuente_md5, vigente) "
              "VALUES ('servicio_ar@dos','servicio_ar','dos','t','# t', encode(sha256(convert_to('# t','UTF8')),'hex'), md5('# t'), true)")


def test_un_documento_vivo_por_alta_y_tipo(admin, srv, alta):
    a = alta()
    r = srv.crear(a, IP, UA)
    d = r["documentos"][0]
    with pytest.raises(psycopg.Error):
        admin("INSERT INTO contrato.documentos SELECT (jsonb_populate_record(d, jsonb_build_object('id', gen_random_uuid(), 'token_sha256', repeat('b', 64)))).* "
              "FROM contrato.documentos d WHERE id = %s", (d["id"],))


def test_firmar_exige_el_codigo_validado(db_url, admin, srv, alta):
    """Llamando a la función directo, salteando el servicio: sin código validado no firma."""
    r = srv.crear(alta(), IP, UA)
    d = r["documentos"][0]
    falso = admin("SELECT gen_random_uuid()", uno=True)[0]
    res = como_firma_srv(db_url, "SELECT contrato.firmar(%s, %s, now(), 'x/y.pdf', repeat('a', 64), '{}'::jsonb, 'ip', 'ua', '{}', '[]'::jsonb, NULL)", (d["id"], falso))
    assert res[0][0]["resultado"] not in ("firmado", "ya_firmado")
    assert admin("SELECT estado FROM contrato.documentos WHERE id = %s", (d["id"],), uno=True)[0] == "pendiente"
