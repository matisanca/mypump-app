#!/usr/bin/env python3
"""ensayar-contrato.py — ensaya supabase/propuestas/nativa_contrato_firma.sql en producción SIN aplicarlo.

Corre la propuesta dentro de una transacción, prueba lo que agrega (con datos inventados que nacen y mueren adentro),
prueba también el reverso, y termina SIEMPRE en ROLLBACK: la base queda exactamente como estaba (lo confirma al final).
No toca ninguna tabla que ya exista. Aplicar de verdad es otro paso y necesita el OK de Mati (pump-firma/RUNBOOK.md).

Uso (en la Mini, con el venv del bot; SUPABASE_DB_URL sale de ~/agentkit-coach/.env):
  scp scripts/nativa/ensayar-contrato.py supabase/propuestas/nativa_contrato_firma*.sql mini:/tmp/contrato-ensayo/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/contrato-ensayo/ensayar-contrato.py /tmp/contrato-ensayo'
"""
import hashlib
import os
import re
import sys
import uuid

import psycopg
from psycopg.types.json import Jsonb

fallas = []


def chequear(nombre, ok, detalle=""):
    print(f"  {'✓' if ok else '✗'} {nombre}{(': ' + str(detalle)) if detalle and not ok else ''}")
    if not ok:
        fallas.append(nombre)


def url_base():
    if os.environ.get("SUPABASE_DB_URL"):
        return os.environ["SUPABASE_DB_URL"]
    for linea in open(os.path.expanduser("~/agentkit-coach/.env"), encoding="utf-8"):
        linea = linea.strip()
        if linea.startswith("SUPABASE_DB_URL="):
            return linea.split("=", 1)[1].strip().strip('"').strip("'")
    raise SystemExit("sin SUPABASE_DB_URL")


def foto(cur):
    """Todo lo que la propuesta podría tocar: esquemas, roles, funciones de public, buckets y membresías."""
    f = {}
    cur.execute("SELECT nspname FROM pg_namespace ORDER BY 1"); f["esquemas"] = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT rolname FROM pg_roles ORDER BY 1"); f["roles"] = [r[0] for r in cur.fetchall()]
    cur.execute("""SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', md5(pg_get_functiondef(p.oid))
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.prokind = 'f' ORDER BY 1""")
    f["funciones_public"] = cur.fetchall()
    cur.execute("SELECT count(*), md5(string_agg(schemaname || '.' || tablename, ',' ORDER BY 1)) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema')")
    f["tablas"] = cur.fetchone()
    cur.execute("SELECT to_regclass('storage.buckets') IS NOT NULL"); hay = cur.fetchone()[0]
    if hay:
        cur.execute("SELECT id, public FROM storage.buckets ORDER BY 1"); f["buckets"] = cur.fetchall()
    cur.execute("SELECT count(*) FROM pg_auth_members"); f["membresias"] = cur.fetchone()[0]
    return f


def sin_transaccion(sql):
    return re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", sql, flags=re.M)


def niega(cur, nombre, sql, args=None, estados=("42501",)):
    """Tiene que fallar, y por el motivo esperado (por defecto «permiso denegado»): un error cualquiera no cuenta."""
    cur.execute("SAVEPOINT p")
    try:
        cur.execute(sql, args)
        chequear(nombre, False, "no lo negó")
    except psycopg.Error as e:
        chequear(nombre, e.sqlstate in estados, f"falló por otro motivo: {e.sqlstate} {str(e)[:120]}")
    cur.execute("ROLLBACK TO SAVEPOINT p")


def main():
    carpeta = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    propuesta = open(os.path.join(carpeta, "nativa_contrato_firma.sql"), encoding="utf-8").read()
    reverso = open(os.path.join(carpeta, "nativa_contrato_firma_revertir.sql"), encoding="utf-8").read()
    cn = psycopg.connect(url_base(), autocommit=False, prepare_threshold=None)
    cur = cn.cursor()
    try:
        cur.execute("SET LOCAL lock_timeout = '4s'; SET LOCAL statement_timeout = '90s'")
        cur.execute("SELECT version(), current_user"); v = cur.fetchone()
        print(f"base: {v[0].split(',')[0]} · usuario {v[1]}")
        antes = foto(cur)
        chequear("no existe todavía (esquema contrato, rol firma_srv, bucket contratos)",
                 "contrato" not in antes["esquemas"] and "firma_srv" not in antes["roles"]
                 and "contratos" not in [b[0] for b in antes.get("buckets", [])])

        print("1. propuesta")
        cur.execute(sin_transaccion(propuesta))
        chequear("la propuesta corre entera", True)
        cur.execute("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'contrato'")
        print(f"     funciones en contrato: {cur.fetchone()[0]}")
        cur.execute("SELECT id, public FROM storage.buckets WHERE id = 'contratos'")
        chequear("bucket contratos creado y privado", cur.fetchone() == ("contratos", False))
        cur.execute("""SELECT count(*) FROM information_schema.role_table_grants WHERE table_schema = 'contrato' AND grantee IN ('anon', 'authenticated', 'firma_srv', 'PUBLIC')""")
        chequear("ningún permiso de tabla para anon, authenticated ni firma_srv", cur.fetchone()[0] == 0)
        cur.execute("SELECT count(*) FROM pg_tables WHERE schemaname = 'contrato' AND NOT rowsecurity")
        chequear("RLS activo en todas las tablas", cur.fetchone()[0] == 0)
        cur.execute("""SELECT has_function_privilege('anon', 'public.contrato_estado(bigint,text,text)', 'EXECUTE'),
                              has_function_privilege('authenticated', 'public.contrato_estado(bigint,text,text)', 'EXECUTE'),
                              has_function_privilege('service_role', 'public.contrato_estado(bigint,text,text)', 'EXECUTE'),
                              has_function_privilege('anon', 'public.mypump_contrato_get(text)', 'EXECUTE'),
                              has_schema_privilege('anon', 'contrato', 'USAGE'), has_schema_privilege('authenticated', 'contrato', 'USAGE')""")
        chequear("puertas de public: contrato_estado solo service_role; mypump_contrato_get anon; esquema cerrado",
                 cur.fetchone() == (False, False, True, True, False, False))

        print("2. recorrido con datos inventados (como firma_srv)")
        md = "# CONTRATO DE ENSAYO\n\nTexto sintético {{@cNombre1}} {{@cFirma}}\n"
        sha, md5 = hashlib.sha256(md.encode()).hexdigest(), hashlib.md5(md.encode()).hexdigest()
        cur.execute("INSERT INTO contrato.plantillas (id, tipo, version, titulo, fuente_md, fuente_sha256, fuente_md5, vigente) VALUES ('servicio_ar@ensayo', 'servicio_ar', 'ensayo', 'CONTRATO DE ENSAYO', %s, %s, %s, true)", (md, sha, md5))
        niega(cur, "plantilla con hash que no es el de su texto: la base la rechaza",
              "INSERT INTO contrato.plantillas (id, tipo, version, titulo, fuente_md, fuente_sha256, fuente_md5) VALUES ('x@x', 'servicio_ext', 'x', 't', 'texto', repeat('a', 64), md5('texto'))", estados=("23514",))
        cur.execute("SELECT l.id FROM public.onboarding_leads l JOIN public.mypump_clientes c ON l.linked_client_id = c.cliente_id WHERE c.access_token_active LIMIT 0")
        chequear("las columnas de leads y clientes que usa la app existen y cruzan", True)
        cur.execute("SET LOCAL ROLE firma_srv")
        chequear("la conexión puede trabajar como firma_srv", True)
        doc, tok, a, b = str(uuid.uuid4()), "c" * 64, "a" * 64, "b" * 64
        ref = "ensayo-" + uuid.uuid4().hex
        cur.execute("SELECT contrato.crear_documento(%s, 'servicio_ar', 'servicio_ar@ensayo', %s, NULL, 'Persona De Ensayo', 'ensayo@correo.invalid', '+00 000 0000000', 'Argentina', 'AR', %s, %s, 'ensayo/a.pdf', %s, NULL, '0.0.0.0', 'ensayo', '{}')",
                    (doc, ref, Jsonb({"cNombre1": "Persona De Ensayo"}), tok, a))
        chequear("crear_documento", cur.fetchone()[0]["resultado"] == "creado")
        cur.execute("SELECT contrato.doc_por_token(%s)", (tok,)); chequear("doc_por_token", cur.fetchone()[0]["id"] == doc)
        cur.execute("SELECT public.contrato_estado(NULL, 'ensayo@correo.invalid', NULL)"); e = cur.fetchone()[0]
        chequear("contrato_estado: pendiente bloquea la agenda", e["bloquea_agenda"] is True and e["servicio_firmado"] is False)
        cur.execute("SELECT contrato.emitir_codigo(%s, 'firma', %s, 900, '0.0.0.0', 'ensayo')", (doc, a)); cod = cur.fetchone()[0]
        chequear("emitir_codigo", cod["resultado"] == "emitido")
        cur.execute("SELECT contrato.firmar(%s, %s, clock_timestamp(), 'ensayo/f.pdf', %s, '{}'::jsonb, '0.0.0.0', 'ensayo', '{}', '[]'::jsonb, NULL)", (doc, cod["codigo"], b))
        chequear("firmar sin validar el código: se niega", cur.fetchone()[0]["resultado"] != "firmado")
        cur.execute("SELECT contrato.validar_codigo(%s, 'firma', %s, '0.0.0.0', 'ensayo')", (doc, b)); chequear("código incorrecto", cur.fetchone()[0]["resultado"] == "incorrecto")
        cur.execute("SELECT contrato.validar_codigo(%s, 'firma', %s, '0.0.0.0', 'ensayo')", (doc, a)); chequear("código correcto", cur.fetchone()[0]["resultado"] == "ok")
        cur.execute("SELECT contrato.firmar(%s, %s, clock_timestamp(), 'ensayo/f.pdf', %s, %s, '0.0.0.0', 'ensayo', '{}', %s, %s)",
                    (doc, cod["codigo"], b, Jsonb({"nombre": "Persona De Ensayo"}), Jsonb([{"tipo": "copia_firmado", "para": "ensayo@correo.invalid"}]),
                     Jsonb({"tipo": "firmado", "cuerpo": {"action": "contrato_firma"}})))
        chequear("firmar", cur.fetchone()[0]["resultado"] == "firmado")
        cur.execute("SELECT public.contrato_estado(NULL, 'ensayo@correo.invalid', NULL)"); e = cur.fetchone()[0]
        chequear("contrato_estado: firmado libera la agenda", e["bloquea_agenda"] is False and e["servicio_firmado"] is True)
        cur.execute("SELECT contrato.verificar(NULL, %s)", (b,)); chequear("verificar por hash", cur.fetchone()[0]["estado"] == "firmado")
        cur.execute("SELECT jsonb_array_length(contrato.correos_pendientes(10, %s)), jsonb_array_length(contrato.avisos_pendientes(10, %s))", (doc, doc))
        chequear("la copia y el aviso quedaron en la bandeja de salida, en la misma transacción", cur.fetchone() == (1, 1))
        cur.execute("SELECT contrato.invitar(%s), contrato.docs_de_app('token-que-no-existe'), contrato.vincular_leads_pendientes(), contrato.pendientes_de_email('ensayo@correo.invalid', 'servicio_ar', 'otra')", (doc,))
        f = cur.fetchone()
        chequear("invitar no invita a un firmado; docs_de_app sin token; vincular y pendientes corren", f[0] is None and f[1] is None and f[2] == 0 and f[3] == [])
        cur.execute("SELECT contrato.resolver_baja(%s, 'sigue', '', '0.0.0.0', 'ensayo')", (doc,))
        chequear("resolver_baja sin baja pedida: se niega", cur.fetchone()[0]["resultado"] == "sin_baja_pedida")
        cur.execute("SELECT contrato.cadena(0, 100)"); cad = cur.fetchone()[0]
        chequear("cadena de eventos encadenada", len(cad) >= 5 and all(cad[i]["prev_hash"] == cad[i - 1]["hash"] for i in range(1, len(cad))))
        for nombre, sql in (("firma_srv no lee tablas", "SELECT * FROM contrato.documentos"), ("firma_srv no edita documentos", "UPDATE contrato.documentos SET estado = 'pendiente'"),
                            ("firma_srv no borra eventos", "DELETE FROM contrato.eventos"), ("firma_srv no ve clientes", "SELECT * FROM public.mypump_clientes LIMIT 1"),
                            ("firma_srv no ve leads", "SELECT * FROM public.onboarding_leads LIMIT 1")):
            niega(cur, nombre, sql)
        cur.execute("RESET ROLE")
        for nombre, sql in (("ni el dueño edita eventos", "UPDATE contrato.eventos SET ip = 'x'"), ("ni el dueño borra documentos", "DELETE FROM contrato.documentos"),
                            ("ni el dueño cambia lo firmado", "UPDATE contrato.documentos SET pdf_final_sha256 = repeat('0', 64)"),
                            ("ni el dueño vuelve un firmado a pendiente", "UPDATE contrato.documentos SET estado = 'pendiente', firmado_en = NULL, pdf_final_sha256 = NULL, pdf_final_path = NULL, firma = NULL"),
                            ("ni el dueño edita una plantilla", "UPDATE contrato.plantillas SET titulo = 'otro'")):
            niega(cur, nombre, sql, estados=("42501", "23514"))
        for rol in ("anon", "authenticated"):
            cur.execute(f"SET LOCAL ROLE {rol}")
            niega(cur, f"{rol} no entra al esquema", "SELECT contrato.doc_por_id(gen_random_uuid())")
            niega(cur, f"{rol} no consulta contrato_estado", "SELECT public.contrato_estado(NULL, 'ensayo@correo.invalid', NULL)")
            niega(cur, f"{rol}: mypump_contrato_get con token inventado (y solo por eso)", "SELECT public.mypump_contrato_get('token-que-no-existe')", estados=("28000",))
            cur.execute("RESET ROLE")
        cur.execute("SET LOCAL ROLE service_role")
        cur.execute("SELECT public.contrato_estado(NULL, 'nadie@correo.invalid', NULL)"); e = cur.fetchone()[0]
        chequear("service_role consulta contrato_estado; sin documentos no bloquea", e["bloquea_agenda"] is False and e["documentos"] == [])
        cur.execute("RESET ROLE")

        print("3. reverso")
        cur.execute("SAVEPOINT r")
        try:
            cur.execute(sin_transaccion(reverso))
            chequear("con firmados, el reverso se niega", False, "borró firmados sin confirmar")
        except psycopg.Error as ex:
            chequear("con firmados, el reverso se niega", "firmados" in str(ex))
        cur.execute("ROLLBACK TO SAVEPOINT r")
        cur.execute("SET LOCAL contrato.confirmo_borrar_firmados = 'si'")
        cur.execute(sin_transaccion(reverso))
        medio = foto(cur)
        # el reverso deja el bucket a propósito (Supabase además no deja borrarlo por SQL): se descuenta al comparar
        medio["buckets"] = [b for b in medio.get("buckets", []) if b[0] != "contratos"]
        chequear("después del reverso no queda nada (salvo el bucket, que se conserva a propósito)", medio == antes,
                 {k: "cambió" for k in antes if antes[k] != medio.get(k)})
    finally:
        cn.rollback()
        print("ROLLBACK")
    cur = cn.cursor()
    despues = foto(cur)
    cn.rollback()
    cn.close()
    chequear("la base quedó exactamente como estaba", despues == antes, {k: "cambió" for k in antes if antes[k] != despues.get(k)})
    print("\nENSAYO " + ("OK" if not fallas else f"CON {len(fallas)} FALLAS: {fallas}"))
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
