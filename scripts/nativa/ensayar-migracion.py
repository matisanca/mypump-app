#!/usr/bin/env python3
"""ensayar-migracion.py — ensaya una migración nativa en producción SIN aplicarla.

Corre el SQL dentro de una transacción, prueba lo que agrega con las cuentas de prueba y hace ROLLBACK: al terminar la
base queda exactamente como estaba (lo confirma al final). Es el "ensayo en rollback" de la compuerta G2; aplicar de
verdad es otro paso y necesita el OK de Mati.

Los tokens de las cuentas de prueba los lee la propia base: no pasan por la terminal ni por este archivo.

Uso (en la Mini, con el venv y el .env del bot, que tiene SUPABASE_DB_URL):
  scp scripts/nativa/ensayar-migracion.py supabase/migrations/nativa_001_recibo_conteos_palanca.sql mini:/tmp/
  ssh mini 'cd ~/agentkit-coach && . venv/bin/activate && set -a && . ./.env && set +a && \
            python3 /tmp/ensayar-migracion.py /tmp/nativa_001_recibo_conteos_palanca.sql'
"""
import json
import os
import re
import sys
import uuid

import psycopg

CUENTA = "test-nativa-ios"
OTRA = "test-nativa-real"
fallas = []


def chequear(nombre, ok, detalle=""):
    print(f"  {'✓' if ok else '✗'} {nombre}{(': ' + detalle) if detalle and not ok else ''}")
    if not ok:
        fallas.append(nombre)


def foto(cur):
    """Lo que hay: tablas y funciones mypump_* con su firma."""
    cur.execute("""SELECT table_name FROM information_schema.tables
                   WHERE table_schema = 'public' AND table_name LIKE 'mypump%' ORDER BY 1""")
    tablas = [r[0] for r in cur.fetchall()]
    cur.execute("""SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', md5(pg_get_functiondef(p.oid))
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname LIKE 'mypump%' ORDER BY 1""")
    return tablas, dict(cur.fetchall())


def main():
    sql = open(sys.argv[1], encoding="utf-8").read()
    # La transacción la maneja el ensayo: afuera el BEGIN y el COMMIT del archivo.
    cuerpo = re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", sql, flags=re.MULTILINE | re.IGNORECASE)

    with psycopg.connect(os.environ["SUPABASE_DB_URL"], autocommit=False) as c:
        cur = c.cursor()
        tablas0, funciones0 = foto(cur)
        cur.execute("SELECT access_token FROM mypump_clientes WHERE cliente_id = %s AND access_token_active", (CUENTA,))
        token = cur.fetchone()[0]
        cur.execute("SELECT access_token FROM mypump_clientes WHERE cliente_id = %s AND access_token_active", (OTRA,))
        otro = cur.fetchone()[0]

        print(f"▸ {os.path.basename(sys.argv[1])}: aplicando dentro de la transacción…")
        cur.execute(cuerpo)
        tablas1, funciones1 = foto(cur)

        print("▸ Qué cambia")
        nuevas_t = sorted(set(tablas1) - set(tablas0))
        nuevas_f = sorted(set(funciones1) - set(funciones0))
        cambiadas = sorted(f for f in funciones0 if f in funciones1 and funciones0[f] != funciones1[f])
        borradas = sorted((set(tablas0) - set(tablas1)) | (set(funciones0) - set(funciones1)))
        print(f"  tablas nuevas: {nuevas_t}")
        print(f"  funciones nuevas: {nuevas_f}")
        chequear("ninguna función existente cambia", not cambiadas, str(cambiadas))
        chequear("no se borra nada", not borradas, str(borradas))

        print("▸ Conteos")
        cur.execute("SELECT mypump_conteos_cliente(%s)", (token,))
        conteos = cur.fetchone()[0]
        chequear("15 tablas, todas con un entero", isinstance(conteos, dict) and len(conteos) == 15
                 and all(isinstance(v, int) for v in conteos.values()), json.dumps(conteos))
        print(f"  {CUENTA}: {json.dumps(conteos, ensure_ascii=False)}")
        cur.execute("SELECT mypump_conteos_cliente('no-es-un-token-de-nadie-000000')")
        chequear("token inexistente → NULL", cur.fetchone()[0] is None)

        print("▸ Recibo")
        mig = str(uuid.uuid4())
        recibo = {"migracion": mig, "corrida": 0, "fecha": "2026-10-14T12:00:00Z", "plataforma": "ios", "app": "2.0.0",
                  "antes": {"ops": 3}, "despues": {"libro": {"cola": 3}}, "servidorAntes": conteos, "servidorDespues": conteos}
        llamar = "SELECT mypump_registrar_migracion_nativa(%s, %s::uuid, %s, %s::jsonb)"
        cur.execute(llamar, (token, mig, 0, json.dumps(recibo)))
        chequear("primer envío → TRUE", cur.fetchone()[0] is True)
        cur.execute(llamar, (token, mig, 0, json.dumps(recibo)))
        chequear("reenvío → TRUE", cur.fetchone()[0] is True)
        cur.execute("SELECT count(*) FROM mypump_migracion_nativa WHERE migracion = %s::uuid", (mig,))
        chequear("el reenvío no duplica", cur.fetchone()[0] == 1)
        cur.execute(llamar, (otro, mig, 1, json.dumps(recibo)))
        chequear("el uuid de otro cliente → FALSE", cur.fetchone()[0] is False)
        cur.execute(llamar, ("no-es-un-token-de-nadie-000000", mig, 2, json.dumps(recibo)))
        chequear("token inexistente → NULL", cur.fetchone()[0] is None)
        for nombre, rec in [("plataforma rara", {**recibo, "plataforma": "web"}),
                            ("más de 16 KB", {**recibo, "relleno": "x" * 17000}),
                            ("no es un objeto", [1, 2])]:
            cur.execute("SAVEPOINT s")
            try:
                cur.execute(llamar, (token, mig, 3, json.dumps(rec)))
                chequear(f"{nombre} → error 22023", False, "no dio error")
            except psycopg.errors.InvalidParameterValue:
                chequear(f"{nombre} → error 22023", True)
            cur.execute("ROLLBACK TO SAVEPOINT s")

        print("▸ Palanca")
        cur.execute("SELECT mypump_get_app_config()")
        cfg = cur.fetchone()[0]
        chequear("los 5 valores por defecto", cfg == {"migracion_ops_legadas": True, "migracion_escritura_vuelta": True,
                                                      "anclaje_borra_swaps": True, "version_minima_ios": None,
                                                      "version_minima_android": None}, json.dumps(cfg))

        print("▸ Permisos")
        for f in ["mypump_registrar_migracion_nativa(text,uuid,integer,jsonb)", "mypump_conteos_cliente(text)",
                  "mypump_get_app_config()"]:
            cur.execute("SELECT has_function_privilege('anon', %s, 'EXECUTE')", (f,))
            chequear(f"anon puede llamar {f.split('(')[0]}", cur.fetchone()[0] is True)
        for t in ["mypump_migracion_nativa", "mypump_app_config"]:
            cur.execute("SELECT relrowsecurity FROM pg_class WHERE relname = %s", (t,))
            chequear(f"{t} con RLS", cur.fetchone()[0] is True)
            cur.execute("SELECT count(*) FROM pg_policies WHERE tablename = %s AND 'anon' = ANY(roles)", (t,))
            chequear(f"{t} sin política para anon", cur.fetchone()[0] == 0)

        c.rollback()
        tablas2, funciones2 = foto(cur)
        chequear("después del ROLLBACK la base quedó igual", (tablas2, funciones2) == (tablas0, funciones0))

    print(f"\n{'✓ ENSAYO OK' if not fallas else '✗ FALLAS: ' + ', '.join(fallas)} (nada quedó aplicado)")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
