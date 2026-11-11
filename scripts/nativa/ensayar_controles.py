#!/usr/bin/env python3
"""Ensayo de nativa_controles_salud.sql sobre ensayar-migracion.py. Todo termina en ROLLBACK: nada queda aplicado.

Uso (en la Mini, con el venv del bot):
  scp scripts/nativa/ensayar-migracion.py scripts/nativa/ensayar_controles.py supabase/propuestas/nativa_controles_salud.sql \
      supabase/propuestas/nativa_controles_salud_revertir.sql supabase/propuestas/nativa_estudios.sql mini:/tmp/controles/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/controles/ensayar_controles.py /tmp/controles/nativa_controles_salud.sql'
Los controles son inventados, de las cuentas de prueba, y viven solo dentro de la transacción. Con nativa_estudios.sql en la
misma carpeta, ensaya también la segunda pasada (la clave foránea al pedido), dentro de un savepoint.
"""
import datetime as dt
import importlib.util
import json
import os
import re

AQUI = os.path.dirname(os.path.abspath(__file__))
s = importlib.util.spec_from_file_location("em", os.path.join(AQUI, "ensayar-migracion.py"))
em = importlib.util.module_from_spec(s)
s.loader.exec_module(em)
ch = em.chequear
NADIE = "no-es-un-token-de-nadie-000000"
CLAVES = {"titulo_alumno", "fecha_objetivo", "avisar_desde", "estado"}
NOTA = "nota-interna-de-ensayo-que-no-sale"


def cuerpo(ruta):
    return re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", open(ruta, encoding="utf-8").read(), flags=re.M | re.I)


def uno(cur, q, *a):
    cur.execute(q, a)
    return cur.fetchone()[0]


def falla(cur, nombre, q, a, estados):
    """Tiene que fallar, y por el motivo esperado."""
    cur.execute("SAVEPOINT f")
    try:
        cur.execute(q, a)
        ch(nombre, False, "no lo negó")
    except Exception as e:  # psycopg2.Error
        ch(nombre, getattr(e, "pgcode", None) in estados, f"{getattr(e, 'pgcode', None)} {str(e)[:120]}")
    cur.execute("ROLLBACK TO SAVEPOINT f")


def chequeos(cur, token, otro):
    get = lambda t=token: uno(cur, "SELECT mypump_controles_get(%s)", t)
    C = uno(cur, "SELECT cliente_id FROM mypump_clientes WHERE access_token = %s", token)
    O = uno(cur, "SELECT cliente_id FROM mypump_clientes WHERE access_token = %s", otro)
    hoy = uno(cur, "SELECT (NOW() AT TIME ZONE 'America/Argentina/Buenos_Aires')::DATE")
    d = lambda n: (hoy + dt.timedelta(days=n)).isoformat()
    ins = ("INSERT INTO mypump_controles_salud (cliente_id, tipo, titulo_alumno, fecha_objetivo, avisar_desde, estado, origen, nota_mati) "
           "VALUES (%s,%s,%s,%s,%s,%s,%s,%s)")

    print("▸ Palanca apagada")
    ch("la clave nace en false", uno(cur, "SELECT valor FROM mypump_app_config WHERE clave='controles_app'") is False)
    ch("get_app_config la trae en false", uno(cur, "SELECT mypump_get_app_config()").get("controles_app") is False)
    ch("token caído: NULL", get(NADIE) is None)
    ch("apagada: {habilitado: false}", get() == {"habilitado": False})
    cur.execute(ins, (C, "ciclo_intra", "Control de salud", d(20), d(14), "programado", "vigia", NOTA))
    ch("apagada, aunque tenga un control, no ve nada", get() == {"habilitado": False})

    print("▸ Palanca prendida")
    cur.execute("UPDATE mypump_app_config SET valor='true'::jsonb WHERE clave='controles_app'")
    g = get()
    ch("hoy en Argentina", g.get("hoy") == hoy.isoformat(), g.get("hoy"))
    ch("próximo: el programado", g.get("proximo") == {"titulo_alumno": "Control de salud", "fecha_objetivo": d(20), "avisar_desde": d(14), "estado": "programado"}, g)
    ch("sin pasados: ultimos []", g.get("ultimos") == [])
    ch("la otra cuenta no ve el control ajeno", get(otro) == {"habilitado": True, "hoy": hoy.isoformat(), "proximo": None, "ultimos": []}, get(otro))
    cur.execute(ins, (C, "fin_posciclo", "Control de salud", d(90), d(84), "programado", "entregas", None))
    cur.execute(ins, (C, "otro", "Control de salud", d(5), d(0), "ordenes_enviadas", "mati", NOTA))
    ch("próximo: el de fecha más cercana (también con órdenes enviadas)", get()["proximo"]["fecha_objetivo"] == d(5))
    for n, (tipo, est) in enumerate([("ciclo_intra", "revisado"), ("fin_posciclo", "resultado_subido"), ("otro", "revisado"),
                                     ("fin_trt_pre_ciclo", "revisado"), ("otro", "cancelado")]):
        cur.execute(ins, (C, tipo, "Control de salud", d(-30 * (n + 1)), d(-30 * (n + 1) - 6), est, "vigia", NOTA))
    cur.execute(ins, (C, "otro", "Control de salud", d(-1), d(-7), "cancelado", "mati", NOTA))
    cur.execute("UPDATE mypump_controles_salud SET resultado_en = '2026-01-02 03:04:05+00' WHERE cliente_id=%s AND estado='resultado_subido'", (C,))
    ch("resultado_en guardado (lo escribe el bot)", uno(cur, "SELECT count(*) FROM mypump_controles_salud WHERE cliente_id=%s AND resultado_en IS NOT NULL", C) == 1)
    g = get()
    ch("ultimos: 3, del más nuevo al más viejo, sin cancelados", [u["fecha_objetivo"] for u in g["ultimos"]] == [d(-30), d(-60), d(-90)], g["ultimos"])
    ch("ultimos con su estado", [u["estado"] for u in g["ultimos"]] == ["revisado", "resultado_subido", "revisado"])
    ch("cada control trae solo sus 4 claves", set(g["proximo"]) == CLAVES and all(set(u) == CLAVES for u in g["ultimos"]))
    ch("el sobre trae solo habilitado, hoy, proximo y ultimos", set(g) == {"habilitado", "hoy", "proximo", "ultimos"})
    texto = json.dumps(g)
    ch("nunca la nota de Mati, el tipo, el origen ni ids", not any(x in texto for x in (NOTA, "ciclo_intra", "fin_posciclo", "fin_trt", "vigia", "entregas", C, "2026-01-02", "resultado_en")), texto[:300])
    cur.execute("UPDATE mypump_controles_salud SET estado='cancelado' WHERE cliente_id=%s AND estado IN ('programado','ordenes_enviadas')", (C,))
    cur.execute(ins, (C, "otro", "Control de salud", d(-45), d(-51), "ordenes_enviadas", "vigia", None))
    ch("uno vencido hace más de 30 días, solo: sale igual", get()["proximo"]["fecha_objetivo"] == d(-45))
    cur.execute(ins, (C, "fin_posciclo", "Control de salud", d(20), d(14), "programado", "vigia", None))
    ch("uno vencido hace más de 30 días no tapa al siguiente", get()["proximo"]["fecha_objetivo"] == d(20))
    cur.execute(ins, (C, "ciclo_intra", "Control de salud", d(-10), d(-16), "ordenes_enviadas", "vigia", None))
    ch("uno vencido hace menos de 30 días sí va primero", get()["proximo"]["fecha_objetivo"] == d(-10))
    cur.execute("UPDATE mypump_controles_salud SET estado='cancelado' WHERE cliente_id=%s AND estado IN ('programado','ordenes_enviadas')", (C,))
    ch("todo cancelado: proximo null", get()["proximo"] is None)

    print("▸ Restricciones")
    cur.execute("SAVEPOINT u")
    cur.execute(ins, (O, "ciclo_intra", "Control de salud", d(40), d(34), "programado", "vigia", None))
    falla(cur, "UNIQUE (cliente_id, tipo, fecha_objetivo)", ins, (O, "ciclo_intra", "Control de salud", d(40), d(30), "programado", "mati", None), ("23505",))
    cur.execute(ins.replace("VALUES (%s,%s,%s,%s,%s,%s,%s,%s)", "VALUES (%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT (cliente_id, tipo, fecha_objetivo) "
                            "DO UPDATE SET avisar_desde = EXCLUDED.avisar_desde, origen = EXCLUDED.origen"),
                (O, "ciclo_intra", "Control de salud", d(40), d(33), "programado", "vigia", None))
    ch("el upsert del vigía pisa la misma fila", uno(cur, "SELECT count(*) FROM mypump_controles_salud WHERE cliente_id=%s", O) == 1
       and uno(cur, "SELECT avisar_desde FROM mypump_controles_salud WHERE cliente_id=%s", O).isoformat() == d(33))
    cur.execute("SELECT actualizado_en > creado_en OR actualizado_en = NOW() FROM mypump_controles_salud WHERE cliente_id=%s", (O,))
    ch("actualizado_en se toca al actualizar", cur.fetchone()[0] is True)
    cur.execute("ROLLBACK TO SAVEPOINT u")
    for nombre, args in [
        ("avisar_desde después de la fecha", (C, "otro", "Control de salud", d(10), d(11), "programado", "vigia", None)),
        ("tipo desconocido", (C, "ciclo", "Control de salud", d(10), d(5), "programado", "vigia", None)),
        ("estado desconocido", (C, "otro", "Control de salud", d(10), d(5), "pendiente", "vigia", None)),
        ("origen desconocido", (C, "otro", "Control de salud", d(10), d(5), "programado", "app", None)),
        ("título con «ciclo»", (C, "otro", "Control de mitad de ciclo", d(10), d(5), "programado", "vigia", None)),
        ("título con «posciclo»", (C, "otro", "Control del Posciclo", d(10), d(5), "programado", "vigia", None)),
        ("título con un fármaco", (C, "otro", "Control de testosterona", d(10), d(5), "programado", "vigia", None)),
        ("título con «IA»", (C, "otro", "Control de la IA", d(10), d(5), "programado", "vigia", None)),
        ("título con dosis", (C, "otro", "Control 250 mg", d(10), d(5), "programado", "vigia", None)),
        ("título vacío", (C, "otro", "  ", d(10), d(5), "programado", "vigia", None)),
        ("título largo", (C, "otro", "Control de salud " * 5, d(10), d(5), "programado", "vigia", None)),
    ]:
        falla(cur, f"CHECK: {nombre}", ins, args, ("23514",))
    for t in ["Control de salud", "Control de salud de mitad de año", "Análisis de control", "Control con la guía de Mati"]:
        ch(f"título permitido: «{t}»", uno(cur, "SELECT mypump_controles_titulo_ok(%s)", t) is True)
    falla(cur, "sin avisar_desde: NOT NULL", "INSERT INTO mypump_controles_salud (cliente_id, tipo, fecha_objetivo, origen) VALUES (%s,'otro',%s,'vigia')",
          (C, d(10)), ("23502",))

    print("▸ Permisos")
    ch("RLS activo", uno(cur, "SELECT relrowsecurity FROM pg_class WHERE oid='mypump_controles_salud'::regclass") is True)
    for rol in ("anon", "authenticated"):
        cur.execute("SELECT " + ",".join(f"has_table_privilege('{rol}','mypump_controles_salud','{p}')" for p in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE")))
        ch(f"{rol}: nada sobre la tabla", not any(cur.fetchone()))
        ch(f"{rol}: ejecuta mypump_controles_get", uno(cur, "SELECT has_function_privilege(%s,'mypump_controles_get(text)','EXECUTE')", rol) is True)
        ch(f"{rol}: no ejecuta titulo_ok ni tocado", not uno(cur, "SELECT has_function_privilege(%s,'mypump_controles_titulo_ok(text)','EXECUTE') "
                                                                  "OR has_function_privilege(%s,'mypump_controles_tocado()','EXECUTE')", rol, rol))
    ch("PUBLIC no ejecuta mypump_controles_get", not uno(cur, "SELECT bool_or(a.grantee = 0) FROM pg_proc p, aclexplode(p.proacl) a "
                                                         "WHERE p.proname='mypump_controles_get' AND a.privilege_type='EXECUTE'"))
    ch("mypump_controles_get es SECURITY DEFINER con search_path fijo",
       uno(cur, "SELECT prosecdef AND EXISTS (SELECT 1 FROM unnest(proconfig) c WHERE c LIKE 'search_path=%%') FROM pg_proc WHERE proname='mypump_controles_get'") is True)
    ch("todas las funciones nuevas con search_path fijo", uno(cur, "SELECT count(*) FROM pg_proc WHERE proname LIKE 'mypump_controles%%' "
                                                            "AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(proconfig,'{}'::text[])) c WHERE c LIKE 'search_path=%%')") == 0)
    cur.execute("SAVEPOINT r")
    cur.execute("SET LOCAL ROLE anon")
    ch("como anon: get con el token anda", uno(cur, "SELECT mypump_controles_get(%s)", token).get("habilitado") is True)
    falla(cur, "como anon: no lee la tabla", "SELECT * FROM mypump_controles_salud", None, ("42501",))
    cur.execute("RESET ROLE")
    cur.execute("SET LOCAL ROLE service_role")
    cur.execute(ins + " ON CONFLICT (cliente_id, tipo, fecha_objetivo) DO NOTHING", (O, "otro", "Control de salud", d(50), d(44), "programado", "vigia", None))
    ch("como service_role: escribe (con el CHECK del título)", uno(cur, "SELECT count(*) FROM mypump_controles_salud WHERE cliente_id=%s", O) == 1)
    cur.execute("RESET ROLE")
    cur.execute("ROLLBACK TO SAVEPOINT r")

    print("▸ Propuestas de suplementación (solo el servidor)")
    T = "salud_suplementos_propuestas"
    ch("propuestas: RLS activo", uno(cur, f"SELECT relrowsecurity FROM pg_class WHERE oid='{T}'::regclass") is True)
    for rol in ("anon", "authenticated", "public"):
        cur.execute("SELECT " + ",".join(f"has_table_privilege('{rol}','{T}','{p}')" for p in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER")))
        ch(f"propuestas: {rol} sin ningún permiso", not any(cur.fetchone()))
    ch("propuestas: ninguna función nueva la nombra (sin RPC para el alumno)",
       uno(cur, "SELECT count(*) FROM pg_proc WHERE prosrc ILIKE '%%salud_suplementos_propuestas%%'") == 0)
    pins = f"INSERT INTO {T} (cliente_id, estudio_id, propuesta, requiere_farmaco, aviso_farmaco, estado) VALUES (%s,%s,%s::jsonb,%s,%s,%s)"
    cur.execute("SAVEPOINT sp")
    cur.execute("SET LOCAL ROLE service_role")
    cur.execute(pins + " RETURNING estado, creado_en IS NOT NULL", (C, "estudio-ensayo-1", '{"agregar":[]}', False, None, "propuesta"))
    ch("propuestas: service_role escribe", cur.fetchone() == ("propuesta", True))
    cur.execute(f"INSERT INTO {T} (cliente_id, estudio_id, propuesta) VALUES (%s,%s,'[]'::jsonb) RETURNING estado, requiere_farmaco", (C, "estudio-ensayo-2"))
    ch("propuestas: por defecto 'propuesta' y requiere_farmaco false", cur.fetchone() == ("propuesta", False))
    cur.execute(f"UPDATE {T} SET estado='aplicada' WHERE estudio_id='estudio-ensayo-1'")
    cur.execute(f"INSERT INTO {T} (cliente_id, estudio_id, propuesta) VALUES (%s,%s,'{{}}'::jsonb) ON CONFLICT (estudio_id, cliente_id) DO NOTHING RETURNING id", (C, "estudio-ensayo-1"))
    ch("propuestas: UNIQUE (estudio_id, cliente_id) con upsert", cur.fetchone() is None)
    cur.execute("SELECT id FROM mypump_controles_salud LIMIT 1")
    fila = cur.fetchone()
    if fila:
        cur.execute(f"UPDATE {T} SET control_id=%s WHERE estudio_id='estudio-ensayo-2' AND cliente_id=%s", (fila[0], C))
        cur.execute("DELETE FROM mypump_controles_salud WHERE id=%s", (fila[0],))
        ch("propuestas: borrar el control deja control_id en NULL", uno(cur, f"SELECT control_id IS NULL FROM {T} WHERE estudio_id='estudio-ensayo-2' AND cliente_id=%s", C) is True)
    else:
        ch("propuestas: hay un control para probar control_id", False)
    ch("propuestas: service_role lee y actualiza", uno(cur, f"SELECT count(*) FROM {T} WHERE cliente_id=%s AND estado='aplicada'", C) == 1)
    cur.execute("RESET ROLE")
    cur.execute("SAVEPOINT sc")
    cur.execute(pins + " RETURNING estado", (C, "estudio-ensayo-3", "{}", False, None, "sin_cambios"))
    ch("propuestas: acepta 'sin_cambios' (lo escribe el runner)", cur.fetchone() == ("sin_cambios",))
    cur.execute("ROLLBACK TO SAVEPOINT sc")
    falla(cur, "propuestas: estado fuera de la lista", pins, (C, "e", "{}", False, None, "pendiente"), ("23514",))
    falla(cur, "propuestas: propuesta que no es objeto ni lista", pins, (C, "e", '"texto"', False, None, "propuesta"), ("23514",))
    falla(cur, "propuestas: sin estudio_id", pins, (C, None, "{}", False, None, "propuesta"), ("23502",))
    falla(cur, "propuestas: UNIQUE (estudio_id, cliente_id)", pins, (C, "estudio-ensayo-2", "{}", False, None, "propuesta"), ("23505",))
    falla(cur, "propuestas: control_id que no existe", f"INSERT INTO {T} (cliente_id, estudio_id, propuesta, control_id) VALUES (%s,'e9','{{}}'::jsonb, gen_random_uuid())", (C,), ("23503",))
    falla(cur, "propuestas: requiere_farmaco NULL", pins, (C, "e", "{}", None, None, "propuesta"), ("23502",))
    cur.execute("SAVEPOINT sa")
    cur.execute("SET LOCAL ROLE anon")
    falla(cur, "propuestas: anon no lee", f"SELECT * FROM {T}", None, ("42501",))
    falla(cur, "propuestas: anon no escribe", pins, (C, "e", "{}", False, None, "propuesta"), ("42501",))
    cur.execute("RESET ROLE")
    cur.execute("ROLLBACK TO SAVEPOINT sa")
    cur.execute("ROLLBACK TO SAVEPOINT sp")

    print("▸ Segunda pasada, con Estudios aplicado (savepoint)")
    estudios = os.path.join(os.path.dirname(os.path.abspath(sys_argv1())), "nativa_estudios.sql")
    if os.path.exists(estudios):
        cur.execute("SAVEPOINT e")
        cur.execute(cuerpo(estudios))
        cur.execute(cuerpo(sys_argv1()))
        ch("con mypump_estudios_pedidos, la segunda pasada suma la clave foránea",
           uno(cur, "SELECT count(*) FROM pg_constraint WHERE conname='controles_pedido_fk'") == 1)
        cur.execute(cuerpo(sys_argv1()))
        ch("con Estudios, la clave foránea de propuestas al pedido", uno(cur, "SELECT count(*) FROM pg_constraint WHERE conname='propuestas_pedido_fk'") == 1)
        ch("una tercera pasada no la duplica ni falla", uno(cur, "SELECT count(*) FROM pg_constraint WHERE conname='controles_pedido_fk'") == 1)
        cur.execute("ROLLBACK TO SAVEPOINT e")
    else:
        ch("nativa_estudios.sql junto al ensayo (para la segunda pasada)", False, estudios)
    ch("sin Estudios aplicado no hay clave foránea (y no rompe)", uno(cur, "SELECT count(*) FROM pg_constraint WHERE conname='controles_pedido_fk'") == 0)

    print("▸ Reverso (savepoint)")
    cur.execute("SAVEPOINT rev")
    cur.execute(cuerpo(os.path.join(os.path.dirname(os.path.abspath(sys_argv1())), "nativa_controles_salud_revertir.sql")))
    ch("no queda la tabla", uno(cur, "SELECT to_regclass('public.mypump_controles_salud') IS NULL") is True)
    ch("no queda la tabla de propuestas", uno(cur, "SELECT to_regclass('public.salud_suplementos_propuestas') IS NULL") is True)
    ch("no quedan funciones", uno(cur, "SELECT count(*) FROM pg_proc WHERE proname LIKE 'mypump_controles%%'") == 0)
    ch("no queda la clave", "controles_app" not in uno(cur, "SELECT mypump_get_app_config()"))
    cur.execute("ROLLBACK TO SAVEPOINT rev")


def sys_argv1():
    import sys
    return sys.argv[1]


em.CHEQUEOS["nativa_controles"] = chequeos
em.main()
