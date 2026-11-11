#!/usr/bin/env python3
"""ensayar-check-guiado.py — ensaya supabase/propuestas/nativa_check_guiado.sql en producción SIN aplicarla.

Corre la propuesta dentro de una transacción, la prueba con las cuentas de prueba, corre el reverso y hace ROLLBACK: al
terminar la base queda como estaba (lo confirma al final). Aplicar de verdad es otro paso y necesita el OK de Mati.

Uso (en la Mini, con el venv del bot; SUPABASE_DB_URL sale de ~/agentkit-coach/.env):
  scp scripts/nativa/ensayar-check-guiado.py supabase/propuestas/nativa_check_guiado*.sql mini:/tmp/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/ensayar-check-guiado.py /tmp/nativa_check_guiado.sql /tmp/nativa_check_guiado_revertir.sql'
"""
import json
import os
import re
import sys

import psycopg2

CUENTA = "test-nativa-ios"
OTRA = "test-nativa-real"
fallas = []


def chequear(nombre, ok, detalle=""):
    print(f"  {'✓' if ok else '✗'} {nombre}{(': ' + detalle) if detalle and not ok else ''}")
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
    cur.execute("""SELECT table_name FROM information_schema.tables
                   WHERE table_schema = 'public' AND table_name LIKE 'mypump%' ORDER BY 1""")
    tablas = [r[0] for r in cur.fetchall()]
    cur.execute("""SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', md5(pg_get_functiondef(p.oid))
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname LIKE 'mypump%' AND p.prokind IN ('f', 'p') ORDER BY 1""")
    funciones = dict(cur.fetchall())
    cur.execute("""SELECT table_name || '.' || column_name || ' ' || data_type FROM information_schema.columns
                   WHERE table_schema = 'public' AND table_name LIKE 'mypump%' ORDER BY 1""")
    columnas = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT clave, valor::text FROM mypump_app_config ORDER BY 1")
    return tablas, funciones, columnas, cur.fetchall()


def cuerpo(ruta):
    """La transacción la maneja el ensayo: afuera el BEGIN y el COMMIT del archivo."""
    return re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", open(ruta, encoding="utf-8").read(), flags=re.MULTILINE | re.IGNORECASE)


def uno(cur, sql, args=()):
    cur.execute(sql, args)
    return cur.fetchone()[0]


def da_22023(cur, nombre, args):
    cur.execute("SAVEPOINT s")
    try:
        cur.execute("SELECT mypump_check_guiado_guardar(%s, %s, %s::jsonb)", args)
        chequear(f"{nombre} → error 22023", False, "no dio error")
    except psycopg2.Error as e:
        chequear(f"{nombre} → error 22023", e.pgcode == "22023", str(e.pgcode))
    cur.execute("ROLLBACK TO SAVEPOINT s")


def chequeos(cur, token, otro):
    hoy = uno(cur, "SELECT (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE")
    lunes = uno(cur, "SELECT date_trunc('week', %s::date)::date", (hoy,))
    general = json.dumps({"catalogo": "general", "senales": ["dolor", "animo"]})

    print("▸ Apagado (como sale)")
    chequear("la palanca sale en false", uno(cur, "SELECT valor = 'false'::jsonb FROM mypump_app_config WHERE clave = 'check_guiado'"))
    chequear("get_app_config la trae en false", uno(cur, "SELECT mypump_get_app_config()->'check_guiado' = 'false'::jsonb"))
    chequear("get apagado = {activo: false}, sin el perfil", uno(cur, "SELECT mypump_check_guiado_get(%s, %s)", (token, hoy)) == {"activo": False})
    chequear("guardar apagado = FALSE", uno(cur, "SELECT mypump_check_guiado_guardar(%s, %s, %s::jsonb)", (token, hoy, general)) is False)
    chequear("apagado no escribe", uno(cur, "SELECT count(*) FROM mypump_check_guiado") == 0)
    chequear("token malo → NULL (get)", uno(cur, "SELECT mypump_check_guiado_get('no-existe', %s)", (hoy,)) is None)

    print("▸ Prendido")
    cur.execute("UPDATE mypump_app_config SET valor = 'true' WHERE clave = 'check_guiado'")
    r = uno(cur, "SELECT mypump_check_guiado_get(%s, %s)", (token, hoy))
    chequear("get prendido: activo, sin ciclo, sin respuestas",
             r.get("activo") is True and r.get("en_ciclo") is False and r.get("senales") is None and r.get("semana") == str(lunes), str(r))
    chequear("token malo → NULL (guardar)", uno(cur, "SELECT mypump_check_guiado_guardar('no-existe', %s, %s::jsonb)", (hoy, general)) is None)
    chequear("guardar = TRUE", uno(cur, "SELECT mypump_check_guiado_guardar(%s, %s, %s::jsonb)", (token, hoy, general)) is True)
    cur.execute("SELECT semana_lunes, catalogo, senales, en_ciclo FROM mypump_check_guiado WHERE cliente_id = %s", (CUENTA,))
    chequear("la fila: lunes ISO, general, ordenadas, sin ciclo", cur.fetchall() == [(lunes, "general", ["animo", "dolor"], False)])
    r = uno(cur, "SELECT mypump_check_guiado_get(%s, %s)", (token, hoy))
    chequear("get devuelve lo guardado", r.get("senales") == ["animo", "dolor"] and r.get("catalogo") == "general", str(r))
    chequear("la otra cuenta no lo ve", uno(cur, "SELECT mypump_check_guiado_get(%s, %s)", (otro, hoy)).get("senales") is None)

    uno(cur, "SELECT mypump_check_guiado_guardar(%s, %s, %s::jsonb)", (token, hoy, json.dumps({"catalogo": "general", "senales": ["ninguno", "dolor", "dolor"]})))
    cur.execute("SELECT senales FROM mypump_check_guiado WHERE cliente_id = %s", (CUENTA,))
    chequear("la última gana, una fila por semana, 'ninguno' mezclado se descarta", cur.fetchall() == [(["dolor"],)])
    uno(cur, "SELECT mypump_check_guiado_guardar(%s, %s, %s::jsonb)", (token, hoy, json.dumps({"catalogo": "general", "senales": ["ninguno"]})))
    chequear("'ninguno' solo se guarda", uno(cur, "SELECT senales FROM mypump_check_guiado WHERE cliente_id = %s", (CUENTA,)) == ["ninguno"])

    print("▸ En ciclo (el perfil de la cuenta de prueba se cambia dentro de la transacción)")
    cur.execute("""INSERT INTO clientes_perfil (cliente_id, perfiles, fuente) VALUES (%s, ARRAY['ciclo'], 'ensayo')
                   ON CONFLICT (cliente_id) DO UPDATE SET perfiles = ARRAY['ciclo', 'peptidos']""", (CUENTA,))
    chequear("get: en_ciclo true", uno(cur, "SELECT mypump_check_guiado_get(%s, %s)", (token, hoy)).get("en_ciclo") is True)
    uno(cur, "SELECT mypump_check_guiado_guardar(%s, %s, %s::jsonb)", (token, hoy, json.dumps({"catalogo": "ciclo", "senales": ["acne", "retencion"]})))
    cur.execute("SELECT catalogo, senales, en_ciclo FROM mypump_check_guiado WHERE cliente_id = %s", (CUENTA,))
    chequear("guarda catálogo ciclo y el perfil del momento", cur.fetchall() == [("ciclo", ["acne", "retencion"], True)])
    for perfiles in (["trt"], ["posciclo", "peptidos"], ["natural"], ["sin_definir"]):
        cur.execute("UPDATE clientes_perfil SET perfiles = %s WHERE cliente_id = %s", (perfiles, CUENTA))
        chequear(f"{perfiles}: no es ciclo", uno(cur, "SELECT mypump_check_guiado_get(%s, %s)", (token, hoy)).get("en_ciclo") is False)

    print("▸ Lo inválido")
    da_22023(cur, "sin catálogo", (token, hoy, json.dumps({"senales": ["dolor"]})))
    da_22023(cur, "catálogo raro", (token, hoy, json.dumps({"catalogo": "otro", "senales": ["dolor"]})))
    da_22023(cur, "señales vacías", (token, hoy, json.dumps({"catalogo": "general", "senales": []})))
    da_22023(cur, "señales que no son lista", (token, hoy, json.dumps({"catalogo": "general", "senales": "dolor"})))
    da_22023(cur, "clave con texto libre", (token, hoy, json.dumps({"catalogo": "general", "senales": ["Me duele la rodilla"]})))
    da_22023(cur, "clave numérica", (token, hoy, json.dumps({"catalogo": "general", "senales": [3]})))
    da_22023(cur, "más de 12", (token, hoy, json.dumps({"catalogo": "general", "senales": [f"s{i}" for i in range(13)]})))
    da_22023(cur, "respuestas que no son objeto", (token, hoy, json.dumps(["dolor"])))
    da_22023(cur, "fecha futura", (token, "2099-01-01", general))
    da_22023(cur, "fecha de hace un mes", (token, "2020-01-01", general))
    da_22023(cur, "sin fecha", (token, None, general))

    print("▸ Permisos y lo que no se toca")
    chequear("anon puede get y guardar", uno(cur, """SELECT has_function_privilege('anon', 'mypump_check_guiado_get(text, date)', 'EXECUTE')
                                                     AND has_function_privilege('anon', 'mypump_check_guiado_guardar(text, date, jsonb)', 'EXECUTE')"""))
    chequear("anon no puede preguntar el perfil de otro", not uno(cur, "SELECT has_function_privilege('anon', 'mypump_check_guiado_en_ciclo(text)', 'EXECUTE')"))
    chequear("anon no lee la tabla", not uno(cur, "SELECT has_table_privilege('anon', 'mypump_check_guiado', 'SELECT')"))
    chequear("la tabla tiene RLS", uno(cur, "SELECT relrowsecurity FROM pg_class WHERE relname = 'mypump_check_guiado'"))


def main():
    c = psycopg2.connect(url_base())
    c.autocommit = False
    try:
        cur = c.cursor()
        antes = foto(cur)
        cur.execute("SELECT count(*), max(updated_at) FROM mypump_checkin_semanal")
        checks0 = cur.fetchone()
        cur.execute("SELECT access_token FROM mypump_clientes WHERE cliente_id = %s AND access_token_active", (CUENTA,))
        token = cur.fetchone()[0]
        cur.execute("SELECT access_token FROM mypump_clientes WHERE cliente_id = %s AND access_token_active", (OTRA,))
        otro = cur.fetchone()[0]

        print("▸ nativa_check_guiado.sql: aplicando dentro de la transacción…")
        cur.execute(cuerpo(sys.argv[1]))
        despues = foto(cur)
        print(f"  tablas nuevas: {sorted(set(despues[0]) - set(antes[0]))}")
        print(f"  funciones nuevas: {sorted(set(despues[1]) - set(antes[1]))}")
        cambiadas = sorted(f for f in antes[1] if f in despues[1] and antes[1][f] != despues[1][f])
        chequear("no cambia ninguna función que ya existía", not cambiadas, str(cambiadas))
        chequear("no se borra nada", set(antes[0]) <= set(despues[0]) and set(antes[1]) <= set(despues[1]) and set(antes[2]) <= set(despues[2]))
        chequear("las tablas que ya existían no cambian de columnas", [x for x in despues[2] if not x.startswith("mypump_check_guiado.")] == antes[2])
        chequear("las otras palancas no cambian", [x for x in despues[3] if x[0] != "check_guiado"] == antes[3])

        chequeos(cur, token, otro)
        cur.execute("SELECT count(*), max(updated_at) FROM mypump_checkin_semanal")
        chequear("mypump_checkin_semanal no se tocó", cur.fetchone() == checks0)

        print("▸ nativa_check_guiado_revertir.sql")
        cur.execute(cuerpo(sys.argv[2]))
        chequear("el reverso deja todo como antes", foto(cur) == antes)

        c.rollback()
        chequear("después del ROLLBACK la base quedó igual", foto(cur) == antes)
    finally:
        c.rollback()
        c.close()

    print(f"\n{'✓ ENSAYO OK' if not fallas else '✗ FALLAS: ' + ', '.join(fallas)} (nada quedó aplicado)")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
