#!/usr/bin/env python3
"""ensayar-migracion.py — ensaya una migración nativa en producción SIN aplicarla.

Corre el SQL dentro de una transacción, prueba lo que agrega con las cuentas de prueba y hace ROLLBACK: al terminar la
base queda exactamente como estaba (lo confirma al final). Es el "ensayo en rollback" de la compuerta G2; aplicar de
verdad es otro paso y necesita el OK de Mati.

Los tokens de las cuentas de prueba los lee la propia base: no pasan por la terminal ni por este archivo.

Uso (en la Mini, con el venv del bot; SUPABASE_DB_URL sale de ~/agentkit-coach/.env, como en ~/_aplicar.py):
  scp scripts/nativa/ensayar-migracion.py supabase/migrations/nativa_001_recibo_conteos_palanca.sql mini:/tmp/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/ensayar-migracion.py /tmp/nativa_001_recibo_conteos_palanca.sql'
"""
import json
import os
import re
import sys
import uuid

import psycopg2
import psycopg2.errors

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
    """Lo que hay: tablas y funciones mypump_* con su firma."""
    cur.execute("""SELECT table_name FROM information_schema.tables
                   WHERE table_schema = 'public' AND table_name LIKE 'mypump%' ORDER BY 1""")
    tablas = [r[0] for r in cur.fetchall()]
    cur.execute("""SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', md5(pg_get_functiondef(p.oid))
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname LIKE 'mypump%' AND p.prokind IN ('f', 'p') ORDER BY 1""")
    return tablas, dict(cur.fetchall())


def chequeos_001(cur, token, otro):
    """nativa_001: recibo, conteos y palanca remota."""
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
        except psycopg2.errors.InvalidParameterValue:
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



def chequeos_002(cur, token, otro):
    """nativa_002: el permiso para la IA (D7)."""
    print("▸ Consentimiento")
    cur.execute("SELECT mypump_get_consentimiento_ia(%s)", (token,))
    chequear("sin fila → acepta null", cur.fetchone()[0] == {"acepta": None})
    guardar = "SELECT mypump_guardar_consentimiento_ia(%s, %s, %s, %s)"
    cur.execute(guardar, (token, False, "ios", "2.0.0"))
    chequear("guardar un no → TRUE", cur.fetchone()[0] is True)
    cur.execute("SELECT mypump_get_consentimiento_ia(%s)", (token,))
    chequear("se lee el no", (cur.fetchone()[0] or {}).get("acepta") is False)
    cur.execute(guardar, (otro, True, "android", "2.0.0"))
    chequear("otro cliente acepta → TRUE", cur.fetchone()[0] is True)
    cur.execute("SELECT cliente_id FROM mypump_clientes WHERE access_token IN (%s, %s) ORDER BY access_token = %s DESC", (token, otro, token))
    cid, cid_otro = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT mypump_clientes_sin_ia(%s::text[])", ([cid, cid_otro, "nadie"],))
    chequear("el servidor ve solo al que dijo que no", cur.fetchone()[0] == [cid])
    cur.execute(guardar, (token, True, "ios", "2.0.0"))
    cur.execute("SELECT count(*) FROM mypump_consentimiento_ia WHERE cliente_id = %s", (cid,))
    chequear("cambiar de opinión no duplica", cur.fetchone()[0] == 1)
    cur.execute("SELECT mypump_clientes_sin_ia(%s::text[])", ([cid],))
    chequear("después de aceptar ya no aparece", cur.fetchone()[0] == [])
    cur.execute(guardar, ("no-es-un-token-de-nadie-000000", True, "ios", None))
    chequear("token inexistente → NULL", cur.fetchone()[0] is None)
    for nombre, args in [("plataforma rara", (token, True, "web", None)), ("acepta null", (token, None, "ios", None))]:
        cur.execute("SAVEPOINT s")
        try:
            cur.execute(guardar, args)
            chequear(f"{nombre} → error 22023", False, "no dio error")
        except psycopg2.errors.InvalidParameterValue:
            chequear(f"{nombre} → error 22023", True)
        cur.execute("ROLLBACK TO SAVEPOINT s")

    print("▸ Permisos")
    for f in ["mypump_get_consentimiento_ia(text)", "mypump_guardar_consentimiento_ia(text,boolean,text,text)"]:
        cur.execute("SELECT has_function_privilege('anon', %s, 'EXECUTE')", (f,))
        chequear(f"anon puede llamar {f.split('(')[0]}", cur.fetchone()[0] is True)
    cur.execute("SELECT has_function_privilege('anon', 'mypump_clientes_sin_ia(text[])', 'EXECUTE')")
    chequear("anon NO puede llamar mypump_clientes_sin_ia", cur.fetchone()[0] is False)
    cur.execute("SELECT has_function_privilege('authenticated', 'mypump_clientes_sin_ia(text[])', 'EXECUTE')")
    chequear("authenticated NO puede llamar mypump_clientes_sin_ia", cur.fetchone()[0] is False)
    cur.execute("SELECT has_function_privilege('service_role', 'mypump_clientes_sin_ia(text[])', 'EXECUTE')")
    chequear("service_role sí", cur.fetchone()[0] is True)
    cur.execute("SELECT relrowsecurity FROM pg_class WHERE relname = 'mypump_consentimiento_ia'")
    chequear("mypump_consentimiento_ia con RLS", cur.fetchone()[0] is True)


def chequeos_003(cur, token, otro):
    """nativa_003: las sustituciones de ejercicio en el servidor (SER-14). Gana lo más nuevo, con lápidas."""
    rutina_de = """SELECT r.id::text FROM mypump_rutinas r JOIN mypump_clientes c ON c.cliente_id = r.cliente_id
                   WHERE c.access_token = %s AND r.estado = 'activa' ORDER BY r.created_at DESC LIMIT 1"""
    cur.execute(rutina_de, (token,))
    rutina = cur.fetchone()[0]
    cur.execute(rutina_de, (otro,))
    rutina_otro = cur.fetchone()[0]
    nadie = "no-es-un-token-de-nadie-000000"

    def swap(nombre, ts=None, fijado=True):
        s = {"original": {"slug": "sentadilla", "nombre": "Sentadilla", "images": None},
             "current": {"slug": "prensa-45", "nombre": nombre, "equipment": "machine",
                         "images": {"eccentric": "https://x/e.jpg", "concentric": None}},
             "fijado": fijado, "semana": 2, "diaId": "d1"}
        if ts is not None:
            s["_ts"] = ts
        return s

    leer = "SELECT mypump_get_exercise_swaps(%s, %s::uuid)"
    guardar = "SELECT mypump_save_exercise_swap(%s, %s::uuid, %s, %s::jsonb)"
    borrar = "SELECT mypump_delete_exercise_swap(%s, %s::uuid, %s, %s)"

    def uno(sql, args):
        cur.execute(sql, args)
        return cur.fetchone()[0]

    def vivas(t=token, r=rutina):
        return (uno(leer, (t, r)) or {}).get("vivas")

    def borradas(t=token, r=rutina):
        return (uno(leer, (t, r)) or {}).get("borradas")

    def da_22023(nombre, sql, args):
        cur.execute("SAVEPOINT s")
        try:
            cur.execute(sql, args)
            chequear(f"{nombre} → error 22023", False, "no dio error")
        except psycopg2.errors.InvalidParameterValue:
            chequear(f"{nombre} → error 22023", True)
        cur.execute("ROLLBACK TO SAVEPOINT s")

    print("▸ Lectura")
    primera = uno(leer, (token, rutina)) or {}
    cur.execute("SELECT (floor(extract(epoch FROM clock_timestamp()) * 1000))::bigint")
    reloj = cur.fetchone()[0]
    chequear("sin filas → vivas y borradas vacías", primera.get("vivas") == {} and primera.get("borradas") == {}, json.dumps(primera))
    chequear("trae la hora del servidor (ms)", isinstance(primera.get("ahora"), int) and abs(primera["ahora"] - reloj) < 60_000,
             f"{primera.get('ahora')} vs {reloj}")
    chequear("token inexistente → NULL", uno(leer, (nadie, rutina)) is None)
    chequear("la rutina de otro cliente → NULL", uno(leer, (token, rutina_otro)) is None)

    print("▸ Guardar: gana lo más nuevo")
    chequear("guardar → TRUE", uno(guardar, (token, rutina, "e1", json.dumps(swap("Prensa", 1000)))) is True)
    chequear("se lee tal cual", vivas() == {"e1": swap("Prensa", 1000)})
    chequear("una más nueva → TRUE y gana", uno(guardar, (token, rutina, "e1", json.dumps(swap("Hack", 2000)))) is True
             and vivas() == {"e1": swap("Hack", 2000)})
    chequear("una más vieja → TRUE pero no pisa", uno(guardar, (token, rutina, "e1", json.dumps(swap("Vieja", 1500)))) is True
             and vivas() == {"e1": swap("Hack", 2000)})
    cur.execute("SELECT count(*), max(cambiado_en) FROM mypump_exercise_swaps WHERE rutina_id = %s::uuid", (rutina,))
    chequear("no duplica y guarda la hora", cur.fetchone() == (1, 2000))
    chequear("sin hora (la app vieja) entra como 0", uno(guardar, (token, rutina, "e2", json.dumps(swap("Legado")))) is True
             and vivas().get("e2") == swap("Legado"))
    chequear("en la rutina de otro → FALSE", uno(guardar, (token, rutina_otro, "e1", json.dumps(swap("X", 1)))) is False)
    cur.execute("SELECT count(*) FROM mypump_exercise_swaps WHERE rutina_id = %s::uuid", (rutina_otro,))
    chequear("…y no escribe nada", cur.fetchone()[0] == 0)
    chequear("token inexistente → NULL", uno(guardar, (nadie, rutina, "e1", json.dumps(swap("X", 9000)))) is None)
    raro = swap("Press «inclinado» 30° — mancuernas 💪", 1234)
    uno(guardar, (token, rutina, "día-2_ñ", json.dumps(raro)))
    chequear("unicode ida y vuelta", vivas().get("día-2_ñ") == raro)
    da_22023("ex_id vacío", guardar, (token, rutina, "", json.dumps(swap("X", 1))))
    da_22023("ex_id de 121", guardar, (token, rutina, "x" * 121, json.dumps(swap("X", 1))))
    da_22023("no es un objeto", guardar, (token, rutina, "e9", json.dumps([1, 2])))
    da_22023("más de 16 KB", guardar, (token, rutina, "e9", json.dumps({**swap("X", 1), "relleno": "x" * 17000})))
    da_22023("_ts de texto", guardar, (token, rutina, "e9", json.dumps({**swap("X"), "_ts": "ayer"})))
    da_22023("_ts negativo", guardar, (token, rutina, "e9", json.dumps(swap("X", -5))))

    print("▸ Borrar: lápida con hora")
    chequear("borrar → TRUE", uno(borrar, (token, rutina, "e1", 3000)) is True)
    chequear("deja de estar viva y queda la lápida", "e1" not in vivas() and borradas().get("e1") == 3000)
    chequear("una más vieja que la lápida no la revive", uno(guardar, (token, rutina, "e1", json.dumps(swap("Vieja", 2500)))) is True
             and "e1" not in vivas())
    chequear("la que vino sin hora tampoco", uno(guardar, (token, rutina, "e1", json.dumps(swap("Legado")))) is True
             and "e1" not in vivas())
    chequear("una más nueva sí", uno(guardar, (token, rutina, "e1", json.dumps(swap("Nueva", 3500)))) is True
             and vivas().get("e1") == swap("Nueva", 3500) and "e1" not in borradas())
    chequear("un borrado más viejo no la saca", uno(borrar, (token, rutina, "e1", 3200)) is True and "e1" in vivas())
    chequear("borrar lo que nunca subió deja lápida", uno(borrar, (token, rutina, "e7", 100)) is True and borradas().get("e7") == 100)
    chequear("token inexistente → NULL", uno(borrar, (nadie, rutina, "e1", 9999)) is None)
    chequear("en la rutina de otro → FALSE", uno(borrar, (token, rutina_otro, "e1", 9999)) is False)
    uno(guardar, (otro, rutina_otro, "e1", json.dumps(swap("Del otro", 10))))
    chequear("no toca la del otro cliente", vivas(otro, rutina_otro) == {"e1": swap("Del otro", 10)})
    da_22023("sin hora", borrar, (token, rutina, "e1", None))
    da_22023("hora negativa", borrar, (token, rutina, "e1", -1))
    da_22023("ex_id vacío", borrar, (token, rutina, "", 1))

    print("▸ Relojes adelantados: la hora se recorta a la del servidor + 5 min")
    cur.execute("SELECT (floor(extract(epoch FROM clock_timestamp()) * 1000))::bigint")
    ahora = cur.fetchone()[0]
    dia = 86_400_000
    chequear("una hora de mañana → TRUE", uno(guardar, (token, rutina, "f1", json.dumps(swap("Futura", ahora + dia)))) is True)
    cur.execute("SELECT cambiado_en, (swap->>'_ts')::bigint FROM mypump_exercise_swaps WHERE rutina_id = %s::uuid AND ex_id = 'f1'", (rutina,))
    col, js = cur.fetchone()
    chequear("se guarda recortada (≤ ahora + 5 min) y la entrada dice lo mismo",
             ahora + 290_000 <= col <= ahora + 310_000 and js == col, f"{col - ahora} ms, entrada {js}")
    chequear("algo hecho 6 minutos después le gana", uno(guardar, (token, rutina, "f1", json.dumps(swap("Después", ahora + 360_000)))) is True
             and vivas().get("f1", {}).get("current", {}).get("nombre") == "Después")
    chequear("una lápida de mañana también se recorta", uno(borrar, (token, rutina, "f2", ahora + dia)) is True
             and ahora + 290_000 <= borradas().get("f2", 0) <= ahora + 310_000, str(borradas().get("f2")))
    chequear("lo que no tiene hora sigue en 0", uno(guardar, (token, rutina, "f3", json.dumps(swap("Legado")))) is True
             and "_ts" not in vivas()["f3"])

    print("▸ Tope de 300 claves por rutina")
    cur.execute("DELETE FROM mypump_exercise_swaps WHERE rutina_id = %s::uuid", (rutina,))
    cur.execute("""SELECT count(*) FILTER (WHERE r) FROM (
                     SELECT mypump_save_exercise_swap(%s, %s::uuid, 't' || g, %s::jsonb) AS r FROM generate_series(1, 300) g) x""",
                (token, rutina, json.dumps(swap("T", 5))))
    chequear("300 entran", cur.fetchone()[0] == 300)
    da_22023("la 301", guardar, (token, rutina, "t301", json.dumps(swap("T", 6))))
    chequear("cambiar una de las 300 sí", uno(guardar, (token, rutina, "t1", json.dumps(swap("T2", 7)))) is True)
    chequear("borrar una que no está con el tope lleno → TRUE sin lápida",
             uno(borrar, (token, rutina, "t999", 8)) is True and "t999" not in borradas())
    chequear("borrar una de las 300 sí deja lápida", uno(borrar, (token, rutina, "t2", 9)) is True and borradas().get("t2") == 9)

    print("▸ Permisos")
    for f in ["mypump_get_exercise_swaps(text,uuid)", "mypump_save_exercise_swap(text,uuid,text,jsonb)",
              "mypump_delete_exercise_swap(text,uuid,text,bigint)"]:
        cur.execute("SELECT has_function_privilege('anon', %s, 'EXECUTE')", (f,))
        chequear(f"anon puede llamar {f.split('(')[0]}", cur.fetchone()[0] is True)
    for f in ["mypump_sustitucion_valida(text,jsonb)", "mypump_sustitucion_ts(jsonb)", "mypump_sustitucion_tope()"]:
        for rol in ["anon", "authenticated"]:
            cur.execute("SELECT has_function_privilege(%s, %s, 'EXECUTE')", (rol, f))
            chequear(f"{rol} NO puede llamar {f.split('(')[0]}", cur.fetchone()[0] is False)
    cur.execute("SELECT relrowsecurity FROM pg_class WHERE relname = 'mypump_exercise_swaps'")
    chequear("mypump_exercise_swaps con RLS", cur.fetchone()[0] is True)
    cur.execute("SELECT count(*) FROM pg_policies WHERE tablename = 'mypump_exercise_swaps' AND 'anon' = ANY(roles)")
    chequear("sin política para anon", cur.fetchone()[0] == 0)

    print("▸ Como la app (rol anon)")
    cur.execute("DELETE FROM mypump_exercise_swaps WHERE rutina_id = %s::uuid", (rutina,))
    cur.execute("SAVEPOINT s")
    cur.execute("SET LOCAL ROLE anon")
    try:
        chequear("guardar", uno(guardar, (token, rutina, "a1", json.dumps(swap("A", 50)))) is True)
        chequear("leer", vivas().get("a1") == swap("A", 50))
        chequear("borrar", uno(borrar, (token, rutina, "a1", 60)) is True and borradas().get("a1") == 60)
        cur.execute("SAVEPOINT t")
        try:
            cur.execute("SELECT count(*) FROM mypump_exercise_swaps")
            chequear("la tabla directa → sin filas (RLS)", cur.fetchone()[0] == 0)
        except psycopg2.errors.InsufficientPrivilege:
            chequear("la tabla directa → sin permiso", True)
            cur.execute("ROLLBACK TO SAVEPOINT t")
    finally:
        cur.execute("ROLLBACK TO SAVEPOINT s")


CHEQUEOS = {"nativa_001": chequeos_001, "nativa_002": chequeos_002, "nativa_003": chequeos_003}


def main():
    sql = open(sys.argv[1], encoding="utf-8").read()
    nombre_migracion = "_".join(os.path.basename(sys.argv[1]).split("_")[:2])
    if nombre_migracion not in CHEQUEOS:
        raise SystemExit(f"sin chequeos para {nombre_migracion}: agregalos en CHEQUEOS")
    # La transacción la maneja el ensayo: afuera el BEGIN y el COMMIT del archivo.
    cuerpo = re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", sql, flags=re.MULTILINE | re.IGNORECASE)

    # Sin `with`: el de psycopg2 hace COMMIT al salir. Acá solo hay ROLLBACK.
    c = psycopg2.connect(url_base())
    c.autocommit = False
    try:
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

        CHEQUEOS[nombre_migracion](cur, token, otro)

        c.rollback()
        tablas2, funciones2 = foto(cur)
        c.rollback()
        chequear("después del ROLLBACK la base quedó igual", (tablas2, funciones2) == (tablas0, funciones0))
    finally:
        c.rollback()
        c.close()

    print(f"\n{'✓ ENSAYO OK' if not fallas else '✗ FALLAS: ' + ', '.join(fallas)} (nada quedó aplicado)")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
