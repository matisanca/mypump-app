#!/usr/bin/env python3
"""Ensayo de nativa_devolucion_semanal.sql sobre ensayar-migracion.py. Todo termina en ROLLBACK: nada queda aplicado.

Uso (en la Mini, con el venv del bot):
  scp scripts/nativa/ensayar-migracion.py scripts/nativa/ensayar_devolucion.py \
      supabase/propuestas/nativa_devolucion_semanal.sql supabase/propuestas/nativa_devolucion_semanal_revertir.sql mini:/tmp/dev/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/dev/ensayar_devolucion.py /tmp/dev/nativa_devolucion_semanal.sql'
Los textos son inventados. La llave es de mentira y vive solo dentro de la transacción.
"""
import datetime as dt
import hashlib
import importlib.util
import json
import os
import re
import uuid

import psycopg2

AQUI = os.path.dirname(os.path.abspath(__file__))
s = importlib.util.spec_from_file_location("em", os.path.join(AQUI, "ensayar-migracion.py"))
em = importlib.util.module_from_spec(s)
s.loader.exec_module(em)
ch = em.chequear
NADIE = "no-es-un-token-de-nadie-000000"
LLAVE = "llave-de-ensayo-" + "x" * 40
BUENO = ("Muy buena semana, cumpliste las cuatro sesiones y el peso bajó medio kilo.\n"
         "En sentadilla subiste dos kilos y mantuviste las repeticiones, eso es progreso real.\n"
         "Esta semana enfocate en llegar a los pasos todos los días.\n"
         "Seguí así que vas muy bien.")
OTRO = BUENO.replace("medio kilo", "casi un kilo")


def sha(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()


def cuerpo(ruta):
    return re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", open(ruta, encoding="utf-8").read(), flags=re.M | re.I)


def uno(cur, q, *a):
    cur.execute(q, a)
    return cur.fetchone()[0]


def da(cur, nombre, codigo, q, *a):
    cur.execute("SAVEPOINT x")
    try:
        cur.execute(q, a)
        ch(f"{nombre} → {codigo}", False, "no dio error")
    except psycopg2.Error as e:
        ch(f"{nombre} → {codigo}", e.pgcode == codigo, f"{e.pgcode} {str(e).splitlines()[0]}")
    cur.execute("ROLLBACK TO SAVEPOINT x")


def chequeos(cur, token, otro):
    C = em.CUENTA
    lunes = dt.date.today() - dt.timedelta(days=dt.date.today().weekday())
    get = lambda t=token: uno(cur, "SELECT mypump_devolucion_get(%s)", t)
    cargar = lambda texto=BUENO, cli=C, sem=lunes, llave=LLAVE: uno(cur, "SELECT mypump_devolucion_cargar(%s,%s,%s::date,%s,%s::date)", llave, cli, sem, texto, lunes)
    emitir = lambda ids: uno(cur, "SELECT mypump_devolucion_emitir_codigo(%s,%s::uuid[],'Mati (ensayo)',%s::date,12)", LLAVE, ids, lunes)
    aprobar = lambda cod, ids: uno(cur, "SELECT mypump_devolucion_aprobar(%s,%s,%s::uuid[])", LLAVE, cod, ids)
    publicar = lambda i, h: uno(cur, "SELECT mypump_devolucion_publicar(%s,%s::uuid,%s)", LLAVE, i, h)
    estado = lambda i: uno(cur, "SELECT estado FROM mypump_devoluciones WHERE id=%s::uuid", i)
    motivo = lambda t: uno(cur, "SELECT mypump_devolucion_texto_motivo(%s)", t)
    hora = lambda b: cur.execute(f"CREATE OR REPLACE FUNCTION mypump_devolucion_hora_de_publicar() RETURNS BOOLEAN LANGUAGE sql STABLE SET search_path = public AS $$ SELECT {'TRUE' if b else 'FALSE'} $$")

    print("▸ Palanca apagada")
    cfg = uno(cur, "SELECT mypump_get_app_config()")
    ch("devolucion_semanal y para_todos en false", cfg.get("devolucion_semanal") is False and cfg.get("devolucion_para_todos") is False, str(cfg)[:160])
    ch("get: no habilitado", get() == {"habilitado": False}, str(get()))
    ch("get token caído: NULL", get(NADIE) is None)

    print("▸ Guarda (token interno)")
    da(cur, "sin llave cargada", "42501", "SELECT mypump_devolucion_cargar(%s,%s,%s::date,%s)", LLAVE, C, lunes, BUENO)
    cur.execute("INSERT INTO mypump_devolucion_llave (id, hash) VALUES (1, %s)", (sha(LLAVE),))
    da(cur, "llave errada", "42501", "SELECT mypump_devolucion_cargar(%s,%s,%s::date,%s)", LLAVE + "y", C, lunes, BUENO)
    da(cur, "llave corta", "42501", "SELECT mypump_devolucion_cargar(%s,%s,%s::date,%s)", "corta", C, lunes, BUENO)
    da(cur, "token del alumno no sirve", "42501", "SELECT mypump_devolucion_cargar(%s,%s,%s::date,%s)", token, C, lunes, BUENO)
    for rol in ("anon", "authenticated"):
        cur.execute("SAVEPOINT r")
        cur.execute(f"SET LOCAL ROLE {rol}")
        try:
            cur.execute("SELECT mypump_devolucion_cargar(%s,%s,%s::date,%s)", (LLAVE, C, lunes, BUENO))
            ch(f"{rol} no puede cargar aun con la llave", False, "pasó")
        except psycopg2.Error as e:
            ch(f"{rol} no puede cargar aun con la llave", e.pgcode == "42501", str(e.pgcode))
        cur.execute("ROLLBACK TO SAVEPOINT r")
        cur.execute("SAVEPOINT r")
        cur.execute(f"SET LOCAL ROLE {rol}")
        try:
            cur.execute("SELECT count(*) FROM mypump_devoluciones")
            ch(f"{rol} no lee la tabla", False, "leyó")
        except psycopg2.Error as e:
            ch(f"{rol} no lee la tabla", e.pgcode == "42501", str(e.pgcode))
        cur.execute("ROLLBACK TO SAVEPOINT r")
        cur.execute("SAVEPOINT r")
        cur.execute(f"SET LOCAL ROLE {rol}")
        try:
            cur.execute("SELECT mypump_devolucion_get(%s)", (token,))
            ch(f"{rol} sí lee por su token", cur.fetchone()[0] == {"habilitado": False})
        except psycopg2.Error as e:
            ch(f"{rol} sí lee por su token", False, str(e.pgcode))
        cur.execute("ROLLBACK TO SAVEPOINT r")

    print("▸ Filtro de texto")
    ch("texto bueno pasa", motivo(BUENO) is None, str(motivo(BUENO)))
    malos = {
        "dos líneas": "Buena semana.\nSeguí así.",
        "seis líneas": "\n".join(["Bien."] * 6),
        "dos puntos": BUENO.replace("Seguí así", "Ojo: seguí así"),
        "guion": BUENO.replace("Seguí así", "- Seguí así"),
        "emoji": BUENO + " 💪",
        "fármaco": BUENO.replace("los pasos", "la testosterona"),
        "fármaco con tilde": BUENO.replace("los pasos", "los anabólicos"),
        "hormonal": BUENO.replace("los pasos", "lo hormonal"),
        "dosis": BUENO.replace("los pasos", "la dosis"),
        "análisis": BUENO.replace("los pasos", "los análisis"),
        "hematocrito": BUENO.replace("los pasos", "el hematocrito"),
        "RIR": BUENO.replace("los pasos", "el RIR"),
        "reserva": BUENO.replace("los pasos", "dejar dos reps en reserva"),
        "lejos del fallo": BUENO.replace("los pasos", "no quedarte lejos del fallo"),
        "IA": BUENO.replace("los pasos", "lo que dice la IA"),
        "tu coach": BUENO.replace("Seguí así", "Tu coach dice que sigas así"),
        "tu entrenador": BUENO.replace("Seguí así", "Tu entrenador te felicita"),
        "Mati": BUENO.replace("Seguí así", "Mati te felicita"),
        "plural": BUENO.replace("Seguí así", "Ajustamos la carga y seguí así"),
        "cambio de plan": BUENO.replace("Seguí así", "Te armo una rutina nueva"),
        "línea larga": BUENO + " " + "a" * 320,
    }
    for n, t in malos.items():
        ch(f"bloquea {n}", motivo(t) is not None, "pasó")
    ch("«al fallo» sí pasa", motivo(BUENO.replace("los pasos", "llevar cada serie al fallo")) is None,
       str(motivo(BUENO.replace("los pasos", "llevar cada serie al fallo"))))
    ch("«diario» no es «ia»", motivo(BUENO.replace("los pasos", "los pasos a diario")) is None)

    print("▸ Cargar")
    ch("semana que no es lunes", cargar(sem=lunes + dt.timedelta(days=1)).get("error") == "semana_invalida")
    ch("cliente inexistente", cargar(cli="no-existe-" + uuid.uuid4().hex[:6]).get("error") == "cliente_inexistente")
    ch("texto prohibido no entra", cargar(texto=malos["fármaco"]).get("error") == "texto_prohibido")
    r = cargar()
    i = r.get("id")
    ch("carga borrador", r.get("ok") is True and r.get("ya") is False and estado(i) == "borrador" and r["texto_hash"] == sha(BUENO), str(r))
    ch("cargar lo mismo: ya", cargar().get("ya") is True)
    ch("espacios de más dan el mismo hash", cargar(texto="  " + BUENO + "\n").get("ya") is True)
    r2 = cargar(cli=em.OTRA)
    j = r2.get("id")
    ch("otra cuenta, otra fila", r2.get("ok") is True and j != i)

    print("▸ Código y aprobación")
    da(cur, "emitir con lista vacía", "22023", "SELECT mypump_devolucion_emitir_codigo(%s,'{}'::uuid[],'x')", LLAVE)
    da(cur, "emitir con repetidas", "22023", "SELECT mypump_devolucion_emitir_codigo(%s,%s::uuid[],'x')", LLAVE, [i, i])
    da(cur, "emitir sin quién", "22023", "SELECT mypump_devolucion_emitir_codigo(%s,%s::uuid[],'  ')", LLAVE, [i])
    e = emitir([i, j])
    cod = e.get("codigo", "")
    ch("emite código XXXX-XXXX", e.get("ok") is True and re.fullmatch(r"[0-9A-F]{4}-[0-9A-F]{4}", cod) is not None and e.get("n") == 2, str({k: v for k, v in e.items() if k != "codigo"}))
    ch("el código no queda guardado en claro", uno(cur, "SELECT count(*) FROM mypump_devolucion_aprobaciones WHERE codigo_hash = %s", sha(cod.replace("-", ""))) == 1
       and uno(cur, "SELECT count(*) FROM mypump_devolucion_aprobaciones WHERE items::text LIKE %s", "%" + cod[:4] + "%") == 0)
    ch("código errado", aprobar("ZZZZ-ZZZZ", [i]).get("error") == "codigo_invalido")
    ch("el errado suma intento", uno(cur, "SELECT intentos_fallidos FROM mypump_devolucion_aprobaciones WHERE codigo_hash=%s", sha(cod.replace("-", ""))) == 1)
    ch("id fuera del código", aprobar(cod, [i, str(uuid.uuid4())]).get("error") == "codigo_de_otro_texto" and estado(i) == "borrador")
    ch("el fallo por lista no gasta el código", uno(cur, "SELECT usado_en IS NULL FROM mypump_devolucion_aprobaciones WHERE codigo_hash=%s", sha(cod.replace("-", ""))) is True)
    # Cambia el texto: el código queda anulado y vuelve a borrador.
    ch("cambiar texto", cargar(texto=OTRO).get("ya") is False and estado(i) == "borrador")
    ch("código anulado por el cambio", aprobar(cod, [i]).get("error") == "codigo_invalido")
    e = emitir([i, j])
    cod = e["codigo"]
    a = aprobar(cod.lower(), [i])
    ch("aprueba una parte, en minúsculas", a.get("ok") is True and a.get("aprobadas") == 1 and estado(i) == "aprobado" and estado(j) == "borrador", str(a))
    ch("código de un solo uso", aprobar(cod, [j]).get("error") == "codigo_invalido" and estado(j) == "borrador")
    ch("aprobada guarda quién y el hash del texto", uno(cur, "SELECT aprobado_por = 'Mati (ensayo)' AND aprobado_hash = texto_hash AND texto_hash = %s FROM mypump_devoluciones WHERE id=%s::uuid", sha(OTRO), i) is True)
    ch("emitir sobre una aprobada no se puede", emitir([i]).get("error") == "estado_invalido")
    # Cinco errados anulan los abiertos.
    e = emitir([j])
    for _ in range(5):
        aprobar("AAAA-0000", [j])
    ch("cinco errados anulan el código", aprobar(e["codigo"], [j]).get("error") == "codigo_invalido")
    da(cur, "aprobado sin aprobación por fuera", "23514", "UPDATE mypump_devoluciones SET estado='aprobado' WHERE id=%s::uuid", j)
    da(cur, "publicado de costado", "23514", "UPDATE mypump_devoluciones SET estado='publicado', publicado_en=now() WHERE id=%s::uuid", j)
    da(cur, "hash que no es del texto", "23514", "UPDATE mypump_devoluciones SET texto='otro' WHERE id=%s::uuid", j)

    print("▸ Publicar")
    ch("hash errado", publicar(i, sha(BUENO)).get("error") == "texto_distinto")
    hora(True)
    ch("palanca apagada: no habilitado", publicar(i, sha(OTRO)).get("error") == "no_habilitado" and estado(i) == "aprobado")
    cur.execute("UPDATE mypump_app_config SET valor='true'::jsonb WHERE clave='devolucion_semanal'")
    ch("prendida sin habilitar: no", publicar(i, sha(OTRO)).get("error") == "no_habilitado")
    cur.execute("INSERT INTO mypump_devolucion_habilitados (cliente_id, motivo) VALUES (%s,'ensayo')", (C,))
    hora(False)
    ch("fuera de horario no sale", publicar(i, sha(OTRO)).get("error") == "fuera_de_horario" and estado(i) == "aprobado")
    hora(True)
    g = get()
    ch("habilitado y sin nada publicado: lista vacía", g == {"habilitado": True, "devoluciones": []}, str(g))
    cur.execute("SAVEPOINT v")
    cur.execute("UPDATE mypump_devoluciones SET aprobado_en = now() - interval '37 hours' WHERE id=%s::uuid", (i,))
    ch("aprobación de más de 36 h no sale", publicar(i, sha(OTRO)).get("error") == "aprobacion_vencida")
    cur.execute("ROLLBACK TO SAVEPOINT v")
    p = publicar(i, sha(OTRO))
    ch("publica", p.get("ok") is True and p.get("ya") is False and estado(i) == "publicado", str(p))
    cur.execute("SELECT titulo, cuerpo, destino FROM mypump_push_cola WHERE dedupe_key=%s", ("dev-" + i,))
    ch("encola el aviso «Mati» a Revisión", cur.fetchall() == [("Mati", "Te dejé la devolución de tu semana", "revision")])
    ch("publicar otra vez: ya, sin otro aviso", publicar(i, sha(OTRO)).get("ya") is True
       and uno(cur, "SELECT count(*) FROM mypump_push_cola WHERE dedupe_key=%s", "dev-" + i) == 1)
    g = get()
    d = (g.get("devoluciones") or [{}])[0]
    ch("el alumno la ve", g.get("habilitado") is True and len(g["devoluciones"]) == 1 and d.get("texto") == OTRO and d.get("semana_lunes") == str(lunes), str(g)[:200])
    ch("solo id, semana, texto y fecha", set(d) == {"id", "semana_lunes", "texto", "publicado_en"}, str(set(d)))
    ch("la otra cuenta no ve nada", get(otro) == {"habilitado": False})
    cur.execute("INSERT INTO mypump_devolucion_habilitados (cliente_id, motivo) VALUES (%s,'ensayo')", (em.OTRA,))
    ch("la otra, habilitada, no ve lo ajeno ni su borrador", get(otro) == {"habilitado": True, "devoluciones": []}, str(get(otro))[:120])
    ch("cargar sobre publicada no se puede", cargar(texto=BUENO).get("error") == "ya_publicada")
    ch("descartar publicada no se puede", uno(cur, "SELECT mypump_devolucion_descartar(%s,%s::uuid,'x')", LLAVE, i).get("error") == "estado_invalido")
    v = uno(cur, "SELECT mypump_devolucion_ver(%s,%s::uuid[])", LLAVE, [i, j])
    ch("ver: sin texto", len(v) == 2 and all("texto" not in x for x in v), str(v)[:160])

    print("▸ Descartar y retirar")
    ch("descartar borrador", uno(cur, "SELECT mypump_devolucion_descartar(%s,%s::uuid,'esta semana no')", LLAVE, j).get("ok") is True and estado(j) == "descartado")
    ch("descartada se puede volver a cargar", cargar(cli=em.OTRA, texto=OTRO).get("ok") is True and estado(j) == "borrador")
    da(cur, "retirar sin motivo", "22023", "SELECT mypump_devolucion_retirar(%s,%s::uuid,'')", LLAVE, i)
    cur.execute("UPDATE mypump_push_cola SET estado='pendiente' WHERE dedupe_key=%s", ("dev-" + i,))
    ch("retirar", uno(cur, "SELECT mypump_devolucion_retirar(%s,%s::uuid,'error de ensayo')", LLAVE, i).get("ok") is True and estado(i) == "retirado")
    ch("retirada no se ve", get() == {"habilitado": True, "devoluciones": []})
    ch("su aviso pendiente no sale", uno(cur, "SELECT estado FROM mypump_push_cola WHERE dedupe_key=%s", "dev-" + i) == "descartado")
    cur.execute("UPDATE mypump_app_config SET valor='false'::jsonb WHERE clave='devolucion_semanal'")
    ch("palanca apagada: el alumno no ve nada", get() == {"habilitado": False})

    print("▸ Permisos")
    serv = uno(cur, "SELECT array_agg(p.oid::regprocedure::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'mypump_devolucion%%'")
    privadas = [f for f in serv if not f.startswith("mypump_devolucion_get(")]
    ch("anon ejecuta get", uno(cur, "SELECT has_function_privilege('anon','public.mypump_devolucion_get(text)','EXECUTE')") is True)
    malos = [f for f in privadas if uno(cur, "SELECT has_function_privilege('anon',%s,'EXECUTE') OR has_function_privilege('authenticated',%s,'EXECUTE')", f, f)]
    ch("anon y authenticated no ejecutan las de servicio", not malos and len(privadas) >= 12, str(malos) + str(len(privadas)))
    malos = [f for f in privadas if not uno(cur, "SELECT has_function_privilege('service_role',%s,'EXECUTE')", f)]
    ch("service_role las ejecuta", not malos, str(malos))
    ch("todas con search_path fijo", uno(cur, "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'mypump_devolucion%%' AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}'::text[])) c WHERE c LIKE 'search_path=%%')") == 0)
    r = [uno(cur, "SELECT has_table_privilege('service_role',%s,%s)", t, pr) for t in ("mypump_devoluciones", "mypump_devolucion_aprobaciones", "mypump_devolucion_llave") for pr in ("INSERT", "UPDATE", "DELETE", "TRUNCATE")]
    ch("service_role no escribe de costado", not any(r), str(r))
    ch("service_role no lee códigos ni llave", not uno(cur, "SELECT has_table_privilege('service_role','mypump_devolucion_aprobaciones','SELECT') OR has_table_privilege('service_role','mypump_devolucion_llave','SELECT')"))
    for t in ("mypump_devoluciones", "mypump_devolucion_aprobaciones", "mypump_devolucion_llave", "mypump_devolucion_habilitados"):
        ch(f"RLS en {t}", uno(cur, "SELECT relrowsecurity FROM pg_class WHERE oid=%s::regclass", t) is True)
        cur.execute("SELECT has_table_privilege('anon',%s,'SELECT'), has_table_privilege('anon',%s,'INSERT'), has_table_privilege('authenticated',%s,'SELECT'), has_table_privilege('authenticated',%s,'UPDATE')", (t, t, t, t))
        r = cur.fetchone()
        ch(f"privilegios de {t}", r == (False, False, False, False), str(r))
    ch("agentes_devoluciones intacta", uno(cur, "SELECT count(*) FROM agentes_devoluciones WHERE estado='aprobada'") == 0)

    print("▸ Reverso (dentro de un savepoint)")
    cur.execute("SAVEPOINT rev")
    cur.execute(cuerpo(os.path.join(os.path.dirname(os.path.abspath(em.__file__)), "nativa_devolucion_semanal_revertir.sql")))
    ch("no quedan tablas", uno(cur, "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'mypump_devolucion%%'") == 0)
    ch("no quedan funciones", uno(cur, "SELECT count(*) FROM pg_proc WHERE proname LIKE 'mypump_devolucion%%'") == 0)
    cfg = uno(cur, "SELECT mypump_get_app_config()")
    ch("no quedan las claves", "devolucion_semanal" not in cfg and "devolucion_para_todos" not in cfg)
    cur.execute("ROLLBACK TO SAVEPOINT rev")


em.CHEQUEOS["nativa_devolucion"] = chequeos
em.main()
