#!/usr/bin/env python3
"""Ensayo de nativa_novedades_plan.sql y de su reverso sobre ensayar-migracion.py. Todo termina en ROLLBACK: nada queda aplicado.

Uso (en la Mini, con el venv del bot):
  scp scripts/nativa/ensayar-migracion.py scripts/nativa/ensayar_novedades.py \
      supabase/propuestas/nativa_novedades_plan.sql supabase/propuestas/nativa_novedades_plan_revertir.sql mini:/tmp/novedades/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/novedades/ensayar_novedades.py /tmp/novedades/nativa_novedades_plan.sql'
El archivo solo suma la palanca `novedades_plan` APAGADA en mypump_app_config. Además de lo que mira ensayar-migracion.py
(tablas, funciones y columnas iguales después del ROLLBACK), acá se mira la fila: el resto de las palancas no cambia, la
app la ve en false con el rol anon, prenderla y apagarla es un UPDATE, aplicarlo dos veces no pisa nada y el reverso deja
la tabla como estaba. Al final, con otra conexión, se confirma que la clave sigue sin existir.
"""
import importlib.util
import json
import os
import re
import sys

import psycopg2

AQUI = os.path.dirname(os.path.abspath(__file__))
s = importlib.util.spec_from_file_location("em", os.path.join(AQUI, "ensayar-migracion.py"))
em = importlib.util.module_from_spec(s)
s.loader.exec_module(em)
ch = em.chequear
CLAVE = "novedades_plan"


def cuerpo(ruta):
    return re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", open(ruta, encoding="utf-8").read(), flags=re.M | re.I)


def uno(cur, q, *a):
    cur.execute(q, a)
    return cur.fetchone()[0]


def palancas(cur):
    cur.execute("SELECT clave, valor::text FROM mypump_app_config ORDER BY clave")
    return dict(cur.fetchall())


def como_anon(cur):
    """Lo que ve la app: mypump_get_app_config con el rol anon (dentro de la transacción)."""
    cur.execute("SET LOCAL ROLE anon")
    try:
        return uno(cur, "SELECT mypump_get_app_config()")
    finally:
        cur.execute("RESET ROLE")


def anon_prende(cur):
    """Intenta el UPDATE como anon dentro de un savepoint: vale que lo niegue el permiso o que RLS no deje tocar ninguna fila."""
    cur.execute("SAVEPOINT anon")
    try:
        cur.execute("SET LOCAL ROLE anon")
        cur.execute("UPDATE mypump_app_config SET valor = 'true'::jsonb WHERE clave = %s", (CLAVE,))
        tocadas = cur.rowcount
    except psycopg2.Error:
        tocadas = 0
    cur.execute("ROLLBACK TO SAVEPOINT anon")
    cur.execute("RESET ROLE")
    return tocadas > 0


def contar_clave(cur):
    return uno(cur, "SELECT count(*) FROM mypump_app_config WHERE clave = %s", CLAVE)


ANTES = {}


def chequeos(cur, token, otro):
    sql = cuerpo(os.path.join(AQUI, "nativa_novedades_plan.sql"))
    rev = cuerpo(os.path.join(AQUI, "nativa_novedades_plan_revertir.sql"))
    # La foto de antes se toma en una transacción aparte: acá adentro el archivo ya se aplicó.
    antes = ANTES["palancas"]

    print("▸ La palanca nace apagada")
    ahora = palancas(cur)
    ch("antes no existía la clave", CLAVE not in antes, antes.get(CLAVE, ""))
    ch("queda una sola fila, en false", contar_clave(cur) == 1 and ahora.get(CLAVE) == "false", str(ahora.get(CLAVE)))
    ch("la nota dice qué es", "Novedades de tu plan" in (uno(cur, "SELECT nota FROM mypump_app_config WHERE clave = %s", CLAVE) or ""))
    ch("las demás palancas no cambian", {k: v for k, v in ahora.items() if k != CLAVE} == antes, str(set(ahora.items()) ^ set(antes.items()))[:300])
    cfg = como_anon(cur)
    ch("la app (rol anon) la lee en false", cfg.get(CLAVE) is False, str(cfg.get(CLAVE)))
    ch("la app sigue leyendo las demás igual", {k: json.dumps(v, sort_keys=True) for k, v in cfg.items() if k != CLAVE}
       == {k: json.dumps(json.loads(v), sort_keys=True) for k, v in antes.items()})
    ch("anon no puede prenderla", not anon_prende(cur))

    print("▸ Aplicarlo dos veces no pisa nada")
    cur.execute(sql)
    ch("sigue una sola fila en false", contar_clave(cur) == 1 and palancas(cur)[CLAVE] == "false")

    print("▸ Prender y apagar (el UPDATE del pie del archivo)")
    cur.execute("UPDATE mypump_app_config SET valor = 'true'::jsonb, actualizado_en = NOW() WHERE clave = %s", (CLAVE,))
    ch("prendida: la app la ve en true", como_anon(cur).get(CLAVE) is True)
    cur.execute(sql)
    ch("aplicarlo con la palanca prendida no la apaga", como_anon(cur).get(CLAVE) is True)
    cur.execute("UPDATE mypump_app_config SET valor = 'false'::jsonb, actualizado_en = NOW() WHERE clave = %s", (CLAVE,))
    ch("apagada otra vez: false", como_anon(cur).get(CLAVE) is False)

    print("▸ Reverso (dentro de un savepoint)")
    cur.execute("SAVEPOINT rev")
    cur.execute(rev)
    ch("no queda la clave", contar_clave(cur) == 0 and CLAVE not in como_anon(cur))
    ch("la tabla queda como antes", palancas(cur) == antes)
    cur.execute(rev)
    ch("el reverso dos veces no rompe", contar_clave(cur) == 0 and palancas(cur) == antes)
    cur.execute("ROLLBACK TO SAVEPOINT rev")
    ch("después del savepoint la clave vuelve (el ensayo sigue en su transacción)", contar_clave(cur) == 1)


def foto_previa():
    c = psycopg2.connect(em.url_base())
    c.autocommit = False
    try:
        cur = c.cursor()
        cur.execute("SET TRANSACTION READ ONLY")
        ANTES["palancas"] = palancas(cur)
    finally:
        c.rollback()
        c.close()


em.CHEQUEOS["nativa_novedades"] = chequeos
foto_previa()
try:
    em.main()
except SystemExit as fin:
    codigo = fin.code
    foto_actual = dict(ANTES)
    foto_previa()
    igual = ANTES["palancas"] == foto_actual["palancas"] and CLAVE not in ANTES["palancas"]
    print(f"  {'✓' if igual else '✗'} con otra conexión: mypump_app_config igual que antes y sin `{CLAVE}`")
    sys.exit(codigo if igual else 1)
