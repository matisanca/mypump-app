#!/usr/bin/env python3
"""Ensayo de nativa_presion.sql sobre ensayar-migracion.py. Todo termina en ROLLBACK: nada queda aplicado.

Uso (en la Mini, con el venv del bot):
  scp scripts/nativa/ensayar-migracion.py scripts/nativa/ensayar_presion.py apps/shared/vectores/presion.json \
      supabase/propuestas/nativa_presion.sql supabase/propuestas/nativa_presion_revertir.sql mini:/tmp/presion/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/presion/ensayar_presion.py /tmp/presion/nativa_presion.sql'
Las tomas son inventadas y viven solo dentro de la transacción. Las reglas del servidor se corren contra los mismos
vectores que las apps (apps/shared/vectores/presion.json).
"""
import datetime as dt
import importlib.util
import json
import os
import re
import uuid

AQUI = os.path.dirname(os.path.abspath(__file__))
s = importlib.util.spec_from_file_location("em", os.path.join(AQUI, "ensayar-migracion.py"))
em = importlib.util.module_from_spec(s)
s.loader.exec_module(em)
ch = em.chequear
NADIE = "no-es-un-token-de-nadie-000000"
ZONA = "America/Argentina/Buenos_Aires"
APP = ["mypump_presion_get(text,text)", "mypump_presion_aparato(text,jsonb)", "mypump_presion_medida(text,numeric,text)",
       "mypump_presion_sesion(text,jsonb)", "mypump_presion_sintoma(text,jsonb)"]
TABLAS = ["habilitados", "tensiometros", "brazo", "aparatos", "comparaciones", "series", "sesiones", "tomas", "sintomas", "avisos", "pausas"]


def cuerpo(ruta):
    return re.sub(r"^\s*(BEGIN|COMMIT)\s*;\s*$", "", open(ruta, encoding="utf-8").read(), flags=re.M | re.I)


def uno(cur, q, *a):
    cur.execute(q, a)
    return cur.fetchone()[0]


def J(x):
    return json.dumps(x)


def vectores(cur):
    V = json.load(open(os.path.join(AQUI, "presion.json"), encoding="utf-8"))
    print("▸ Reglas del servidor contra los vectores de las apps")
    mal = [v for v in V["validar"] if uno(cur, "SELECT mypump_presion_validar(%s,%s,%s)", v["toma"].get("sis"), v["toma"].get("dia"), v["toma"].get("pulso")) != v["sale"]]
    ch(f"validar: {len(V['validar'])} casos", not mal, J(mal)[:300])
    mal = []
    for v in V["sesion"]:
        sale = uno(cur, "SELECT mypump_presion_evaluar_sesion(%s::jsonb)", J(v["entrada"]))
        if sale != v["sale"]:
            mal.append((v["nombre"], {k: (sale.get(k), v["sale"].get(k)) for k in v["sale"] if sale.get(k) != v["sale"].get(k)}))
    ch(f"sesión: {len(V['sesion'])} casos", not mal and len(V["sesion"]) >= 50, str(mal)[:900])
    mal = []
    for v in V["serie"]:
        sale = uno(cur, "SELECT mypump_presion_resumen_serie(%s::jsonb)", J(v["entrada"]))
        if sale != v["sale"]:
            mal.append((v["nombre"], {k: (sale.get(k), v["sale"].get(k)) for k in v["sale"] if sale.get(k) != v["sale"].get(k)}))
    ch(f"serie: {len(V['serie'])} casos", not mal and len(V["serie"]) >= 24, str(mal)[:900])
    mal = []
    for v in V["calza"]:
        e = v.get("entrada", v)
        ap = e.get("aparato") or {}
        sale = uno(cur, "SELECT mypump_presion_calza(%s::numeric, jsonb_populate_record(NULL::mypump_presion_aparatos, %s::jsonb))", e.get("cm"), J(ap))
        if sale != v["sale"]:
            mal.append((e, sale))
    ch(f"manguito calza: {len(V['calza'])} casos", not mal, str(mal)[:400])
    return V


def chequeos(cur, token, otro):
    C = em.CUENTA
    ahora = dt.datetime.now(dt.timezone.utc)
    get = lambda t=token: uno(cur, "SELECT mypump_presion_get(%s,%s)", t, ZONA)
    avisos = lambda cli=C: {r[0]: r for r in (cur.execute("SELECT regla, nivel, es_alta, origen_tipo FROM mypump_presion_avisos WHERE cliente_id=%s", (cli,)) or cur.fetchall())}

    def toma(orden, sis, dia, pulso=62, hace_min=0, **mas):
        return dict({"orden": orden, "posicion": "sentado", "brazo": "izq", "sis": sis, "dia": dia, "pulso": pulso, "latido_irregular": False,
                     "medido_en": (ahora - dt.timedelta(minutes=hace_min)).isoformat(), "confirmada_por_alumno": False}, **mas)

    def sesion(tomas, serie=None, tipo="estandar", dias=0, sid=None, t=token, **mas):
        p = {"id": sid or str(uuid.uuid4()), "serie_id": serie, "tipo": tipo, "inicio": (ahora - dt.timedelta(days=dias, minutes=30)).isoformat(),
             "zona_horaria": ZONA, "brazo": "izq", "previo": {"cafeina": False, "fumo": False, "comida": False, "ejercicio": False},
             "reposo_cumplido": True, "temporizador_salteado": False, "sintomas": [], "lista_espera": None, "texto_alumno": "ninguno",
             "app_version": "2.3.0", "plataforma": "ios", "tomas": tomas}
        p.update(mas)
        return p["id"], uno(cur, "SELECT mypump_presion_sesion(%s,%s::jsonb)", t, J(p))

    V = vectores(cur)

    print("▸ Palanca apagada")
    cfg = uno(cur, "SELECT mypump_get_app_config()")
    ch("presion_app y presion_para_todos en false", cfg.get("presion_app") is False and cfg.get("presion_para_todos") is False, str(cfg)[:200])
    ch("get: no habilitado", get() == {"habilitado": False}, str(get()))
    ch("get token caído: NULL", get(NADIE) is None)
    ch("guardar con la palanca apagada: no_habilitado", sesion([toma(1, 120, 80)], tipo="suelta")[1] == {"ok": False, "error": "no_habilitado"})
    cur.execute("UPDATE mypump_app_config SET valor='true'::jsonb WHERE clave='presion_app'")
    ch("palanca prendida y sin estar en la lista: no habilitado", get() == {"habilitado": False})
    cur.execute("INSERT INTO mypump_presion_habilitados (cliente_id, motivo) VALUES (%s,'ensayo')", (C,))

    print("▸ Aparato y medida del brazo")
    g = get()
    ch("estado vacío", g.get("habilitado") is True and g["aparato"] is None and g["serie"] is None and g["sesiones"] == [] and g["pendiente"] is None
       and g["tensiometros"] is None and g["fotos"] is False, str(g)[:300])
    ch("al alumno no le llegan promedios, categorías ni avisos", not ({"promedio", "categoria", "avisos", "resumen"} & set(J(g).replace('"', " ").split())))
    ch("sin aparato no se guarda", sesion([toma(1, 120, 80)], tipo="suelta")[1].get("error") == "aparato")
    ap = lambda a, t=token: uno(cur, "SELECT mypump_presion_aparato(%s,%s::jsonb)", t, J(a))
    ch("aparato de tipo raro: datos", ap({"tipo": "dedo"}).get("error") == "datos")
    ch("rango al revés: datos", ap({"tipo": "brazo", "manguito_min_cm": 42, "manguito_max_cm": 22}).get("error") == "datos")
    ap({"tipo": "reloj_anillo_otro", "marca": "Reloj"})
    ch("con reloj no se guarda", sesion([toma(1, 120, 80)], tipo="suelta")[1].get("error") == "aparato")
    r = ap({"tipo": "brazo", "marca": "Marca de ensayo", "modelo": "M1", "manguito_min_cm": 22, "manguito_max_cm": 42})
    ch("aparato de brazo", r.get("ok") is True and r["estado"]["aparato"]["tipo"] == "brazo" and r["estado"]["aparato"]["validado"] == "sin_revisar", str(r)[:200])
    ch("el anterior queda inactivo, uno solo activo", uno(cur, "SELECT count(*) FILTER (WHERE activo) || '/' || count(*) FROM mypump_presion_aparatos WHERE cliente_id=%s", C) == "1/2")
    pedir = lambda motivo="basal", cli=C, op=None: uno(cur, "SELECT mypump_presion_serie_pedir(%s,%s,'mati',%s::jsonb)", cli, motivo, J(op or {}))
    ch("pedir serie a un cliente que no existe", pedir(cli="no-existe-ensayo").get("error") == "cliente")
    S = pedir(op={"requisito_pre_entrega": True})["id"]
    ch("pedirla dos veces devuelve la misma", pedir().get("ya") is True and pedir()["id"] == S)
    g = get()
    ch("la serie aparece pendiente y pide la medida", g["serie"]["id"] == S and g["serie"]["estado"] == "pendiente" and g["serie"]["medida_pedida"] is True and g["serie"]["faltan"] == 3, str(g["serie"]))
    med = lambda cm, t=token: uno(cur, "SELECT mypump_presion_medida(%s,%s,%s)", t, cm, ZONA)
    ch("medida imposible: datos", med(12).get("error") == "datos" and med(71).get("error") == "datos")
    r = med(34.5)
    ch("medida guardada en la serie", r.get("ok") is True and r["estado"]["circunferencia_brazo_cm"] == 34.5 and r["estado"]["serie"]["medida_pedida"] is False
       and uno(cur, "SELECT manguito_calza FROM mypump_presion_series WHERE id=%s::uuid", S) is True, str(r)[:200])

    print("▸ Serie de 3 tomas en 3 días")
    ch("toma imposible", sesion([toma(1, 300, 80)], S, dias=2)[1].get("error") == "imposible" and sesion([toma(1, 120, 115)], S, dias=2)[1].get("error") == "imposible")
    ch("serie ajena: no", sesion([toma(1, 120, 80)], S, t=otro)[1] in ({"ok": False, "error": "no_habilitado"}, {"ok": False, "error": "serie"}))
    sx, r = sesion([toma(1, 120.0, 80, latido_irregular="quizás")], dias=5, inicio=(ahora + dt.timedelta(hours=3)).isoformat())
    ch("estándar sin serie, con el reloj adelantado y tipos raros: se guarda como suelta, no se pierde", r.get("ok") is True
       and uno(cur, "SELECT tipo || '/' || (serie_id IS NULL) || '/' || (inicio <= NOW()) FROM mypump_presion_sesiones WHERE id=%s::uuid", sx) == "suelta/true/true", str(r)[:200])
    ch("serie de otro: no", sesion([toma(1, 120, 80)], str(uuid.uuid4()))[1].get("error") == "serie")
    s1, r = sesion([toma(1, 138, 88)], S, dias=2)
    e = r["estado"]
    ch("día 1: cuenta, serie en curso, faltan 2", r.get("ok") is True and e["serie"]["estado"] == "en_curso" and e["serie"]["faltan"] == 2 and len(e["serie"]["dias"]) == 1
       and [x for x in e["sesiones"] if x["id"] == s1][0]["cuenta"] is True and [x for x in e["sesiones"] if x["id"] == s1][0]["tomas"][0]["sis"] == 138, str(e["serie"]))
    ch("plazo de 7 días desde la primera", uno(cur, "SELECT fecha_limite - fecha_inicio FROM mypump_presion_series WHERE id=%s::uuid", S) == 6)
    _, r = sesion([toma(1, 111, 71)], S, dias=2, sid=s1)
    ch("reenviar no duplica ni pisa la toma", r["estado"]["serie"]["faltan"] == 2 and uno(cur, "SELECT count(*) || '-' || max(sistolica) FROM mypump_presion_tomas WHERE sesion_id=%s::uuid", s1) == "1-138")
    _, r = sesion([toma(1, 120, 80)], S, dias=2)
    ch("otra toma el mismo día no suma", r["estado"]["serie"]["faltan"] == 2)
    sc, r = sesion([toma(1, 136, 86)], S, dias=1, previo={"cafeina": True, "fumo": False, "comida": False, "ejercicio": False})
    ch("con café antes: se guarda y no cuenta", r["estado"]["serie"]["faltan"] == 2 and [x for x in r["estado"]["sesiones"] if x["id"] == sc][0]["cuenta"] is False)
    _, r = sesion([toma(1, 136, 86)], S, dias=1)
    ch("día 2: faltan 1", r["estado"]["serie"]["faltan"] == 1)
    ch("una pendiente no se abre con otra en curso", pedir("control_ciclo").get("ok") is True and sesion([toma(1, 120, 80)], pedir("control_ciclo")["id"])[1].get("ok") is True and uno(cur, "SELECT estado FROM mypump_presion_series WHERE id=%s::uuid", pedir("control_ciclo")["id"]) == "pendiente")
    _, r = sesion([toma(1, 137, 87, 64)], S, dias=0)
    fila = lambda: (cur.execute("SELECT estado, resumen FROM mypump_presion_series WHERE id=%s::uuid", (S,)) or cur.fetchone())
    est, res = fila()
    ch("día 3: serie completa", est == "completa" and res["serie_valida"] is True and res["tomas_validas"] == 3, str(est))
    ch("resumen para el brief: promedio 137/87, categoría y cortes", res["promedios"]["global"] == {"sis": 137, "dia": 87, "pulso": 63, "n": 3} and res["categoria"] == "hipertension_casa"
       and res["cortes"]["urgencia"] == "180/120" and res["tomas_excluidas"] == {"condicion_incumplida": 1} and res["aparato"]["manguito_calza"] is True
       and res["alta"]["es_alta"] is True and res["requisito_pre_entrega"] is True and res["version"] == 1, J(res)[:600])
    a = avisos()
    ch("promedio de 135/85 o más: aviso de alta a Mensajes", a.get("alta_promedio_135_85", ())[1:] == ("aviso", True, "serie"), str(a))
    ch("al completar pasa a la siguiente pendiente", get()["serie"]["motivo"] == "control_ciclo")
    b = uno(cur, "SELECT mypump_presion_para_brief(%s)", C)
    ch("para el brief: tiene tomas, la serie y el requisito cumplido", b["tiene_tomas"] is True and b["requisito_pre_entrega"] == {"pedido": True, "cumplido": True, "pendientes": []}
       and any(x["id"] == S and x["resumen"]["serie_valida"] for x in b["series"]) and len(b["avisos_abiertos"]) >= 1, J(b)[:300])
    b2 = uno(cur, "SELECT mypump_presion_para_brief(%s)", em.OTRA)
    ch("sin tomas dice que no hay", b2["tiene_tomas"] is False and b2["series"] == [] and b2["requisito_pre_entrega"]["pedido"] is False)

    print("▸ 160/100 y 180/120")
    S2 = get()["serie"]["id"]
    s2, r = sesion([toma(1, 164, 96)], S2)
    p = r["estado"]["pendiente"]
    ch("164/96: queda la repetición pendiente, sin aviso todavía", p and p["sesion_id"] == s2 and p["nivel"] == "alta" and "alta_toma_160_100" not in avisos(), str(p))
    # La repetición retomada desde el aviso llega sin lo que contestó antes de medir: no se pisa.
    _, r = sesion([toma(1, 164, 96), toma(2, 162, 101)], S2, sid=s2, previo={}, reposo_cumplido=None, temporizador_salteado=None)
    ch("repetida y confirmada: alta, y la sesión conserva lo de antes de medir", r["estado"]["pendiente"] is None and avisos().get("alta_toma_160_100", ())[1:] == ("aviso", True, "sesion")
       and uno(cur, "SELECT reposo_cumplido AND NOT previo_cafeina FROM mypump_presion_sesiones WHERE id=%s::uuid", s2) is True, str(avisos()))
    s3, r = sesion([toma(1, 186, 122)], None, tipo="suelta")
    ch("186/122: pendiente de urgencia", r["estado"]["pendiente"]["nivel"] == "urgencia" and r["estado"]["pendiente"]["sesion_id"] == s3)
    cur.execute("UPDATE mypump_presion_tomas SET medido_en = NOW() - INTERVAL '16 minutes' WHERE sesion_id=%s::uuid", (s3,))
    n = uno(cur, "SELECT mypump_presion_barrer(%s)", C)
    ch("sin repetir a los 15 minutos: el barrido la pasa a alta", n >= 1 and avisos().get("alta_180_120_sin_repetir", ())[1:3] == ("aviso", True), str(avisos().keys()))
    ch("el barrido no la vuelve a tocar", uno(cur, "SELECT mypump_presion_barrer(%s)", C) == 0)
    _, r = sesion([toma(1, 186, 122), toma(2, 184, 121)], None, tipo="suelta", sid=s3, lista_espera="no")
    a = avisos()
    ch("repetida y sigue en 180/120: urgencia a Mensajes", a.get("toma_180_120_confirmada", ())[1:3] == ("urgencia", True) and r["estado"]["pendiente"] is None, str(a.keys()))
    s4, _ = sesion([toma(1, 150, 95)], None, tipo="suelta", dias=1, lista_espera="si", sintomas=["dolor_pecho"])
    ch("un Sí de la lista: urgencia por síntomas", uno(cur, "SELECT nivel FROM mypump_presion_avisos WHERE origen_id=%s::uuid AND regla='sintoma_alarma_en_espera'", s4) == "urgencia"
       and uno(cur, "SELECT de_alarma AND NOT sin_sintomas_en_lista FROM mypump_presion_sintomas WHERE id=%s::uuid", s4) is True)
    ch("todo aviso va a Mensajes, ninguno directo", uno(cur, "SELECT bool_and(destino='mensajes') FROM mypump_presion_avisos") is True)

    print("▸ Toma suelta de 135/85 y síntomas")
    cur.execute("UPDATE mypump_presion_series SET estado='cancelada' WHERE cliente_id=%s AND estado IN ('pendiente','en_curso')", (C,))
    s5, _ = sesion([toma(1, 141, 84)], None, tipo="suelta", dias=3)
    ch("suelta de 135/85 o más: pide una serie de 3", uno(cur, "SELECT motivo || '/' || pedida_por || '/' || tomas_objetivo FROM mypump_presion_series WHERE cliente_id=%s AND estado='pendiente'", C) == "control_toma_alta/regla/3")
    cur.execute("UPDATE mypump_presion_series SET estado='cancelada' WHERE cliente_id=%s AND estado='pendiente'", (C,))
    sesion([toma(1, 141, 84)], None, tipo="suelta", dias=3, sid=s5)
    ch("reenviar esa suelta no pide otra serie", uno(cur, "SELECT count(*) FROM mypump_presion_series WHERE cliente_id=%s AND estado='pendiente'", C) == 0)
    sint = lambda p, t=token: uno(cur, "SELECT mypump_presion_sintoma(%s,%s::jsonb)", t, J(p))
    i = str(uuid.uuid4())
    ch("síntoma de alarma por el botón", sint({"id": i, "contexto": "boton", "codigos": ["falta_aire"], "zona_horaria": ZONA}) == {"ok": True}
       and uno(cur, "SELECT nivel FROM mypump_presion_avisos WHERE origen_tipo='sintoma' AND origen_id=%s::uuid", i) == "urgencia")
    ch("reenviado no duplica", sint({"id": i, "contexto": "boton", "codigos": ["falta_aire"]}) == {"ok": True} and uno(cur, "SELECT count(*) FROM mypump_presion_avisos WHERE origen_id=%s::uuid", i) == 1)
    ch("código inventado: datos", sint({"id": str(uuid.uuid4()), "codigos": ["me_duele_todo"]}).get("error") == "datos")
    ch("síntoma con el id de otro: datos", sint({"id": i, "codigos": []}, otro) in ({"ok": False, "error": "datos"}, {"ok": False, "error": "no_habilitado"}))

    j = str(uuid.uuid4())
    ch("síntoma con una sesión que nunca llegó: se guarda suelto, con la hora del teléfono", sint({"id": j, "contexto": "boton", "codigos": ["dolor_pecho"], "sesion_id": str(uuid.uuid4()),
       "marcado_en": (ahora - dt.timedelta(hours=8)).isoformat(), "sin_sintomas_en_lista": "x"}) == {"ok": True}
       and uno(cur, "SELECT (sesion_id IS NULL) AND marcado_en < NOW() - INTERVAL '7 hours' FROM mypump_presion_sintomas WHERE id=%s::uuid", j) is True
       and uno(cur, "SELECT nivel FROM mypump_presion_avisos WHERE origen_id=%s::uuid AND regla='sintoma_alarma'", j) == "urgencia")

    print("▸ Ortostática")
    cur.execute("UPDATE mypump_presion_series SET estado='cancelada' WHERE cliente_id=%s AND estado IN ('pendiente','en_curso')", (C,))
    O = pedir("ortostatica_suelta", op={"motivos_ortostatica": ["sintomas_al_pararse"]})["id"]
    _, r = sesion([toma(1, 121, 79)], O, dias=4)
    ch("la toma sentado no cierra la serie si falta la ortostática", r["estado"]["serie"] and r["estado"]["serie"]["id"] == O and r["estado"]["serie"]["ortostatica"] == "acostado_parado"
       and r["estado"]["serie"]["faltan"] == 0, str(r["estado"]["serie"]))
    o1, r = sesion([toma(1, 120, 80, posicion="acostado"), toma(2, 96, 72, 80, posicion="de_pie", minutos_de_pie=1), toma(3, 99, 70, 78, posicion="de_pie", minutos_de_pie=3)], O, tipo="ortostatica", dias=4)
    est, res = (cur.execute("SELECT estado, resumen FROM mypump_presion_series WHERE id=%s::uuid", (O,)) or cur.fetchone())
    ch("con la ortostática hecha, completa y con la caída en el resumen", r.get("ok") is True and est == "completa" and res["ortostatica"]["hecha"] is True and res["ortostatica"]["caida_sis_max"] == 24
       and res["ortostatica"]["hipotension"] is True and "ortostatica_positiva" in avisos(), str(r)[:120] + J(res.get("ortostatica")))

    print("▸ Mensajes, pausa y consultorio")
    cola = uno(cur, "SELECT mypump_presion_avisos_pendientes(50)")
    mios = [x for x in cola if x["cliente_id"] == C]
    ch("cola: urgencias primero y sin las de brief", mios and mios[0]["nivel"] == "urgencia" and all(x["nivel"] != "brief" for x in cola)
       and [x["nivel"] for x in mios] == sorted([x["nivel"] for x in mios], key=lambda n: n != "urgencia"), str([x["regla"] for x in mios]))
    u = mios[0]["id"]
    uno(cur, "SELECT mypump_presion_aviso_marcar(%s::uuid,%s::jsonb)", u, J({"tomado": True, "mensaje_borrador": "borrador de ensayo"}))
    ch("tomado: sale de la cola con su borrador", u not in [x["id"] for x in uno(cur, "SELECT mypump_presion_avisos_pendientes(50)")]
       and uno(cur, "SELECT mensaje_borrador FROM mypump_presion_avisos WHERE id=%s::uuid", u) == "borrador de ensayo")
    brief = uno(cur, "SELECT id FROM mypump_presion_avisos WHERE cliente_id=%s AND NOT es_alta LIMIT 1", C)
    if brief:
        ch("pausa sobre un aviso que no es alta: no", uno(cur, "SELECT mypump_presion_pausa_abrir(%s::uuid,'urgencia',ARRAY['cafeína'])", brief).get("error") == "aviso")
    pz = uno(cur, "SELECT mypump_presion_pausa_abrir(%s::uuid,'urgencia',ARRAY['pre entreno'],'pausar el pre entreno')", u)
    ch("pausa de estimulantes abierta, una sola", pz.get("ok") is True and uno(cur, "SELECT mypump_presion_pausa_abrir(%s::uuid,'urgencia',ARRAY['x'])", u).get("ya") is True)
    ch("el brief ve la pausa", uno(cur, "SELECT mypump_presion_para_brief(%s)", C)["pausa_estimulantes"]["id"] == pz["id"])
    uno(cur, "SELECT mypump_presion_pausa_actualizar(%s::uuid,%s::jsonb)", pz["id"], J({"editor_estado": "aplicado", "reanudar": "no"}))
    ch("decidir reanudar cierra la pausa", uno(cur, "SELECT cerrado_en IS NOT NULL AND editor_estado='aplicado' FROM mypump_presion_pausas WHERE id=%s::uuid", pz["id"]) is True)
    r = ap({"tipo": "muneca", "marca": "Marca de ensayo", "modelo": "W1", "manguito_min_cm": 13.5, "manguito_max_cm": 21.5})
    apid = r["estado"]["aparato"]["id"]
    ch("medida de más de 52 con muñeca: excepción anotada", med(54).get("ok") is True and uno(cur, "SELECT excepcion_brazo_mas_52 FROM mypump_presion_aparatos WHERE id=%s::uuid", apid) is True)
    pares = [{"consultorio_sis": 130, "consultorio_dia": 80, "casa_sis": 143 + k, "casa_dia": 84} for k in range(3)]
    r = uno(cur, "SELECT mypump_presion_comparacion_cargar(%s::uuid,%s::jsonb,'equipo (ensayo)')", apid, J({"motivo": "muneca_mas_52_inicio", "fecha": str(ahora.date()), "pares": pares}))
    ch("consultorio: más de 10 con muñeca queda solo para urgencias", r.get("mas_de_10") is True and r.get("solo_urgencias") is True and r["dif_media_sis"] == 14.0, str(r))
    uno(cur, "SELECT mypump_presion_aparato_validar(%s::uuid,%s::jsonb,'equipo (ensayo)')", apid, J({"validado": "si", "validado_fuente": "stridebp"}))
    ch("validar el aparato", get()["aparato"]["validado"] == "si")
    cur.execute("INSERT INTO mypump_presion_tensiometros (tramos, verificado_por) VALUES (%s::jsonb,'equipo (ensayo)')", (J({"estandar": [{"nombre": "Modelo de ensayo", "codigo": "X-1", "pais": "AR", "nota": ""}]}),))
    ch("la lista de tensiómetros llega cuando el equipo la carga", get()["tensiometros"]["tramos"]["estandar"][0]["codigo"] == "X-1")

    print("▸ La rutina no se toca")
    ch("ninguna función escribe fuera de las tablas de presión", uno(cur, r"""SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname LIKE 'mypump_presion%%' AND (p.prosrc ~* '(INSERT INTO|DELETE FROM)\s+(?!mypump_presion_)[a-z_]+' OR p.prosrc ~* 'UPDATE\s+(?!mypump_presion_)(?!SET\M)[a-z_]+\s+([a-z]+\s+)?SET\M')""") == 0)
    ch("ninguna nombra rutinas, entrenos ni ejercicios", uno(cur, r"""SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname LIKE 'mypump_presion%%' AND p.prosrc ~* 'mypump_(rutin|entren|ejerc|sesiones_entren)'""") == 0)

    print("▸ Permisos")
    serv = uno(cur, "SELECT array_agg(p.oid::regprocedure::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'mypump_presion%%'")
    malos = [f for f in APP if not uno(cur, "SELECT has_function_privilege('anon',%s,'EXECUTE')", f)]
    ch("anon ejecuta las 5 de la app", not malos, str(malos))
    resto = [f for f in serv if f.replace(" ", "") not in APP]
    malos = [f for f in resto if uno(cur, "SELECT has_function_privilege('anon',%s,'EXECUTE') OR has_function_privilege('authenticated',%s,'EXECUTE')", f, f)]
    ch("anon y authenticated no ejecutan ninguna otra", not malos and len(resto) >= 24, str(malos) + str(len(resto)))
    ch("todas con search_path fijo", uno(cur, "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname LIKE 'mypump_presion%%' AND NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,'{}'::text[])) c WHERE c LIKE 'search_path=%%')") == 0)
    for t in ["mypump_presion_" + x for x in TABLAS]:
        cur.execute("SELECT relrowsecurity FROM pg_class WHERE oid=%s::regclass", (t,))
        rls = cur.fetchone()[0]
        cur.execute("SELECT " + ",".join(f"has_table_privilege('{rol}',%s,'{pr}')" for rol in ("anon", "authenticated") for pr in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE")), (t,) * 10)
        ch(f"{t}: RLS y nada para anon ni authenticated", rls is True and not any(cur.fetchone()))
    r = [uno(cur, "SELECT has_table_privilege('service_role',%s,%s)", "mypump_presion_" + t, pr) for t in ("tomas", "sesiones", "avisos", "series") for pr in ("INSERT", "UPDATE", "DELETE", "TRUNCATE")]
    ch("service_role no escribe tomas ni avisos de costado", not any(r), str(r))

    print("▸ Palanca apagada otra vez")
    cur.execute("UPDATE mypump_app_config SET valor='false'::jsonb WHERE clave='presion_app'")
    ch("el alumno no ve nada y no guarda", get() == {"habilitado": False} and sesion([toma(1, 120, 80)], tipo="suelta")[1].get("error") == "no_habilitado")

    print("▸ Reverso (dentro de un savepoint)")
    cur.execute("SAVEPOINT rev")
    cur.execute(cuerpo(os.path.join(AQUI, "nativa_presion_revertir.sql")))
    ch("no quedan tablas", uno(cur, "SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name LIKE 'mypump_presion%%'") == 0)
    ch("no quedan funciones", uno(cur, "SELECT count(*) FROM pg_proc WHERE proname LIKE 'mypump_presion%%'") == 0)
    cfg = uno(cur, "SELECT mypump_get_app_config()")
    ch("no quedan las claves", "presion_app" not in cfg and "presion_para_todos" not in cfg)
    cur.execute("ROLLBACK TO SAVEPOINT rev")


em.CHEQUEOS["nativa_presion.sql"] = chequeos
em.main()
