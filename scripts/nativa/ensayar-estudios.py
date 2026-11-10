#!/usr/bin/env python3
"""ensayar-estudios.py — ensaya nativa_estudios.sql y su reverso SIN aplicarlos.

Todo corre en una sola transacción que termina en ROLLBACK: la base queda como estaba (se comprueba al final).
Usa las cuentas de prueba; los tokens los lee la base y no salen por la terminal.

Uso (en la Mini, con el venv del bot):
  scp scripts/nativa/ensayar-estudios.py supabase/propuestas/nativa_estudios.sql supabase/propuestas/nativa_estudios_revertir.sql mini:/tmp/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/ensayar-estudios.py /tmp/nativa_estudios.sql /tmp/nativa_estudios_revertir.sql'
"""
import json
import os
import re
import sys
import uuid

import psycopg2

CUENTA, OTRA = "test-nativa-ios", "test-nativa-real"
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


def sin_transaccion(sql):
    return re.sub(r"(?im)^\s*(BEGIN|COMMIT)\s*;\s*$", "", sql)


def foto(cur):
    cur.execute("""SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY 1""")
    tablas = [r[0] for r in cur.fetchall()]
    cur.execute("""SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' FROM pg_proc p
                   JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' ORDER BY 1""")
    funciones = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT id FROM storage.buckets ORDER BY 1")
    buckets = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT clave FROM mypump_app_config ORDER BY 1")
    return tablas, funciones, buckets, [r[0] for r in cur.fetchall()]


def uno(cur, sql, args=()):
    cur.execute(sql, args)
    return cur.fetchone()[0]


def falla_con(cur, sql, args=()):
    cur.execute("SAVEPOINT s")
    try:
        cur.execute(sql, args)
        cur.execute("RELEASE SAVEPOINT s")
        return None
    except psycopg2.Error as e:
        cur.execute("ROLLBACK TO SAVEPOINT s")
        return e.pgcode or "error"


def main():
    sql = sin_transaccion(open(sys.argv[1], encoding="utf-8").read())
    reverso = sin_transaccion(open(sys.argv[2], encoding="utf-8").read())
    conn = psycopg2.connect(url_base())
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SET LOCAL lock_timeout = '5s'")
    cur.execute("SET LOCAL statement_timeout = '60s'")
    antes = foto(cur)
    try:
        cur.execute("SELECT cliente_id, access_token FROM mypump_clientes WHERE cliente_id IN (%s, %s)", (CUENTA, OTRA))
        cuentas = dict(cur.fetchall())
        if len(cuentas) != 2:
            raise SystemExit("faltan las cuentas de prueba")
        tok, otro = cuentas[CUENTA], cuentas[OTRA]

        print("▸ Aplicar")
        cur.execute(sql)
        chequear("corre entero", True)

        print("▸ Apagado por defecto")
        cfg = uno(cur, "SELECT mypump_get_app_config()")
        chequear("estudios_app en false", cfg.get("estudios_app") is False, cfg)
        chequear("get con palanca apagada → habilitado false", uno(cur, "SELECT mypump_estudios_get(%s)", (tok,)) == {"habilitado": False})
        chequear("token inexistente → NULL", uno(cur, "SELECT mypump_estudios_get('no-es-un-token-000')") is None)
        chequear("abrir envío apagado → no_habilitado",
                 uno(cur, "SELECT mypump_estudios_envio_nuevo(%s, %s)", (tok, str(uuid.uuid4())))["error"] == "no_habilitado")
        cur.execute("UPDATE mypump_app_config SET valor = 'true' WHERE clave = 'estudios_app'")
        chequear("prendida sin estar en la lista → sigue false", uno(cur, "SELECT mypump_estudios_get(%s)", (tok,)) == {"habilitado": False})
        cur.execute("INSERT INTO mypump_estudios_habilitados (cliente_id, motivo) VALUES (%s, 'ensayo')", (CUENTA,))
        g = uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))
        chequear("habilitado y vacío", g["habilitado"] is True and g["pendientes"] == [] and g["estudios"] == [] and g["ordenes"] == []
                 and g["envios"] == [] and g["proximo_control"] is None, g)
        chequear("la otra cuenta sigue afuera", uno(cur, "SELECT mypump_estudios_get(%s)", (otro,)) == {"habilitado": False})

        print("▸ Control de texto")
        prohibido = "SELECT mypump_ordenes_texto_prohibido(%s, %s::jsonb)"
        limpio = "Orden de laboratorio. Paciente: Prueba Uno. Cobertura: Sin cobertura. Hemograma completo\nTestosterona total\nDiagnóstico: E29.1"
        chequear("orden limpia con su práctica pasa", uno(cur, prohibido, (limpio, json.dumps(["Testosterona total", "Hemograma completo"]))) is False)
        chequear("la práctica se descuenta una sola vez",
                 uno(cur, prohibido, (limpio + " por déficit de testosterona", json.dumps(["Testosterona total"]))) is True)
        chequear("sin la práctica en la lista no pasa", uno(cur, prohibido, (limpio, "[]")) is True)
        for malo in ["control en ciclo", "post ciclo", "Particular", "dosis semanal", "250 mg", "andrógenos", "Rp/ enantato", "TRT",
                     "uso de anabólicos", "tamoxifeno", "cada 7 días", "terapia de reemplazo hormonal", "T38.7", "hipogonadismo inducido",
                     "ANABÓLICOS", "última aplicación"]:
            chequear(f"«{malo}» frena", uno(cur, prohibido, ("Laboratorio. " + malo + ". Sin cobertura", "[]")) is True)
        for bueno in ["Hemograma completo. Sin cobertura. E78.5", "Ecocardiograma Doppler color. OSDE 210", "por tratamiento hormonal en curso",
                      "Ferritina, hierro sérico, transferrina y saturación", "Vitamina D (25-OH), vitamina B12 y ácido fólico"]:
            chequear(f"«{bueno[:30]}…» pasa", uno(cur, prohibido, (bueno, "[]")) is False)

        print("▸ Pedidos")
        pedir = ("SELECT mypump_estudios_pedir(%s, %s, %s, %s, %s::date, 'ensayo', %s::date, %s, %s::jsonb)")
        r = uno(cur, pedir, (CUENTA, "laboratorio", "orden", "ord-1", "2030-01-10", None, None, json.dumps(["Hemograma completo"])))
        chequear("alta de pedido", r.get("ok") is True and r.get("id"), r)
        ped_lab = r["id"]
        chequear("repetir no duplica", uno(cur, pedir, (CUENTA, "laboratorio", "orden", "ord-1", "2030-01-12", None, None, "[]"))["id"] == ped_lab)
        chequear("detalle con texto prohibido → rechazo",
                 uno(cur, pedir, (CUENTA, "ecografia", "entrega", "e-1", "2030-01-10", None, "control de ciclo", "[]")).get("error") == "detalle_prohibido")
        chequear("control sin «desde» → rechazo",
                 uno(cur, pedir, (CUENTA, "laboratorio", "control", "c-1", "2030-03-10", None, None, "[]")).get("error") == "control_sin_desde")
        chequear("control a futuro", uno(cur, pedir, (CUENTA, "laboratorio", "control", "c-1", "2030-03-10", "2030-03-01", None, "[]")).get("ok") is True)
        chequear("cuenta inexistente → sin_cuenta",
                 uno(cur, pedir, ("no-existe-000", "laboratorio", "orden", "x", "2030-01-10", None, None, "[]")).get("error") == "sin_cuenta")
        g = uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))
        chequear("un pendiente y un próximo control", len(g["pendientes"]) == 1 and g["proximo_control"] == {
            "tipo": "laboratorio", "titulo": "Análisis de laboratorio", "desde": "2030-03-01", "hasta": "2030-03-10"}, g)
        chequear("el pendiente no trae prácticas ni notas", set(g["pendientes"][0]) == {"id", "tipo", "titulo", "detalle", "desde", "hasta", "estado", "hecho_fecha", "orden_id"})
        chequear("«ya me lo hice» de otro → no_encontrado",
                 uno(cur, "SELECT mypump_estudios_hecho(%s, %s, mypump_estudios_hoy())", (otro, ped_lab)) in (None, {"ok": False, "error": "no_habilitado"}))
        chequear("«ya me lo hice»", uno(cur, "SELECT mypump_estudios_hecho(%s, %s, mypump_estudios_hoy())", (tok, ped_lab)).get("estado") == "hecho")
        chequear("fecha futura → rechazo", uno(cur, "SELECT mypump_estudios_hecho(%s, %s, mypump_estudios_hoy() + 5)", (tok, ped_lab)).get("error") == "fecha")

        print("▸ Envío y archivos")
        envio, a1, a2 = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
        r = uno(cur, "SELECT mypump_estudios_envio_nuevo(%s, %s, %s)", (tok, envio, ped_lab))
        chequear("abre el envío", r == {"ok": True, "ya": False, "id": envio, "estado": "borrador"}, r)
        chequear("repetir → ya", uno(cur, "SELECT mypump_estudios_envio_nuevo(%s, %s)", (tok, envio)).get("ya") is True)
        chequear("enviar sin archivos → sin_archivos", uno(cur, "SELECT mypump_estudios_enviar(%s, %s, 1)", (tok, envio)).get("error") == "sin_archivos")
        puede = "SELECT mypump_estudios_archivo_puede(%s, %s, %s)"
        chequear("puede subir", uno(cur, puede, (CUENTA, envio, a1)) == "ok")
        chequear("otra cuenta sobre este envío → no_encontrado", uno(cur, puede, (OTRA, envio, a1)) == "no_encontrado")
        reg = "SELECT mypump_estudios_archivo_registrar(%s, %s, %s, %s, 'application/pdf', 1000, %s)"
        carpeta = "0" * 32
        sha1, sha2 = "a" * 64, "b" * 64
        chequear("registra", uno(cur, reg, (CUENTA, envio, a1, f"e/{carpeta}/{envio}/{a1}.pdf", sha1)) == "ok")
        chequear("mismo id → ya", uno(cur, reg, (CUENTA, envio, a1, f"e/{carpeta}/{envio}/{a1}.pdf", sha1)) == "ya")
        chequear("mismos bytes → repetido", uno(cur, reg, (CUENTA, envio, a2, f"e/{carpeta}/{envio}/{a2}.pdf", sha1)) == "repetido")
        chequear("path fuera de formato → error", falla_con(cur, reg, (CUENTA, envio, a2, "../otro/x.pdf", sha2)) is not None)
        chequear("faltan archivos → todavía no", uno(cur, "SELECT mypump_estudios_enviar(%s, %s, 2)", (tok, envio)).get("error") == "faltan_archivos")
        chequear("enviar", uno(cur, "SELECT mypump_estudios_enviar(%s, %s, 1)", (tok, envio)) == {"ok": True, "ya": False, "estado": "enviado"})
        chequear("enviado ya no recibe archivos", uno(cur, puede, (CUENTA, envio, a2)) == "estado")
        g = uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))
        chequear("el envío se ve como enviado", [e["estado"] for e in g["envios"]] == ["enviado"], g["envios"])

        print("▸ Cola del bot")
        t = uno(cur, "SELECT mypump_estudios_tomar()")
        chequear("toma el envío con su archivo", t and t["id"] == envio and len(t["archivos"]) == 1 and t["cliente_id"] == CUENTA, t)
        chequear("no lo toma dos veces", uno(cur, "SELECT mypump_estudios_tomar()") is None)
        chequear("devolver lo deja en cola", uno(cur, "SELECT mypump_estudios_devolver(%s, FALSE, 'cuota')", (envio,)) is True)
        chequear("se vuelve a tomar", (uno(cur, "SELECT mypump_estudios_tomar()") or {}).get("id") == envio)
        cur.execute("UPDATE mypump_app_config SET valor = 'false' WHERE clave = 'estudios_app'")
        cur.execute("SAVEPOINT apagada")
        cur.execute("UPDATE mypump_estudios_envios SET estado = 'enviado' WHERE id = %s", (envio,))
        chequear("con la palanca apagada no toma nada", uno(cur, "SELECT mypump_estudios_tomar()") is None)
        cur.execute("ROLLBACK TO SAVEPOINT apagada")
        cur.execute("UPDATE mypump_app_config SET valor = 'true' WHERE clave = 'estudios_app'")

        print("▸ Registro del estudio y cierre del pedido")
        registrar = "SELECT mypump_estudios_registrar(%s, %s::date, %s, %s, %s, 'lote0001', %s, %s, 'application/pdf', %s, %s)"
        hoy = uno(cur, "SELECT mypump_estudios_hoy()::text")
        r = uno(cur, registrar, (CUENTA, hoy, True, "laboratorio", "app", f"{CUENTA}/2030_a.pdf", sha1, False, envio))
        chequear("propia por sha y cierra el pedido", r["propia"] is True and r["cruce"] == "cerrado" and r["pedido_id"] == ped_lab, r)
        estudio = r["estudio_id"]
        chequear("marca procesado", uno(cur, "SELECT mypump_estudios_procesado(%s, 'lote0001', %s::jsonb)", (envio, json.dumps({"guardados": 1}))) is True)
        g = uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))
        chequear("ya no está pendiente ni como envío", g["pendientes"] == [] and g["envios"] == [], g)
        e = g["estudios"][0]
        chequear("estudio recibido, 1 hoja, se abre por ser propia", e["estado"] == "recibido" and e["hojas"] == 1 and e["se_puede_abrir"] is True, e)
        chequear("el estudio no trae paths", set(e) == {"id", "tipo", "titulo", "fecha", "hojas", "estado", "recibido_en", "se_puede_abrir"})
        chequear("path en carpeta ajena → error",
                 falla_con(cur, registrar, (CUENTA, hoy, True, "laboratorio", "whatsapp", f"{OTRA}/x.pdf", None, True, None)) is not None)
        chequear("ficha sin cuenta → NULL", uno(cur, registrar, ("no-existe-000", hoy, True, "laboratorio", "whatsapp", "no-existe-000/x.pdf", None, True, None)) is None)

        r = uno(cur, registrar, (CUENTA, hoy, True, "ecografia", "whatsapp", f"{CUENTA}/2030_eco.pdf", "c" * 64, False, None))
        eco = r["estudio_id"]
        chequear("WhatsApp sin pedido", r["cruce"] == "sin_pedido" and r["propia"] is False, r)
        firmar = "SELECT mypump_estudios_paths_para_firmar(%s, 'estudio', %s)"
        chequear("WhatsApp sin ver no se abre", uno(cur, firmar, (CUENTA, eco))["resultado"] == "todavia_no")
        chequear("lo propio sí", uno(cur, firmar, (CUENTA, estudio))["resultado"] == "ok")
        chequear("otra cuenta no lo encuentra", uno(cur, firmar, (OTRA, estudio))["resultado"] in ("no_encontrado", "no_habilitado"))
        leido = uno(cur, "SELECT NOW()::text")
        chequear("visto sin nombre → error", falla_con(cur, "SELECT mypump_estudios_marcar_visto(%s, '', NOW())", (eco,)) == "22023")
        chequear("visto", uno(cur, "SELECT mypump_estudios_marcar_visto(%s, 'Mati', %s::timestamptz)", (eco, leido)) == "ok")
        chequear("visto con identidad floja sigue sin abrirse", uno(cur, firmar, (CUENTA, eco))["resultado"] == "todavia_no")
        cur.execute("UPDATE mypump_estudios_hojas SET identidad_fuerte = TRUE WHERE estudio_id = %s", (eco,))
        chequear("visto e identidad fuerte: se abre", uno(cur, firmar, (CUENTA, eco))["resultado"] == "ok")
        r = uno(cur, registrar, (CUENTA, hoy, True, "ecografia", "whatsapp", f"{CUENTA}/2030_eco2.pdf", "d" * 64, False, None))
        chequear("hoja nueva: deja de estar visto", uno(cur, "SELECT visto_en IS NULL FROM mypump_estudios WHERE id = %s", (eco,)) is True)
        chequear("y deja de abrirse", uno(cur, firmar, (CUENTA, eco))["resultado"] == "todavia_no")
        chequear("visto leído antes de la hoja nueva → no marca",
                 uno(cur, "SELECT mypump_estudios_marcar_visto(%s, 'Mati', NOW() - INTERVAL '1 hour')", (eco,)) == "hojas_nuevas")

        for caso, args, espera in [
            ("sin fecha legible no cierra", (False, "app", sha1), "sin_fecha"),
            ("identidad floja por WhatsApp no cierra", (True, "whatsapp", "e" * 64), "identidad_floja"),
        ]:
            cur.execute("SAVEPOINT c")
            uno(cur, pedir, (CUENTA, "ergometria", "revision", "r-1", "2030-01-10", None, None, "[]"))
            r = uno(cur, registrar, (CUENTA, hoy, args[0], "ergometria", args[1], f"{CUENTA}/2030_erg.pdf", args[2], False, None))
            chequear(caso, r["cruce"] == espera, r)
            cur.execute("ROLLBACK TO SAVEPOINT c")
        cur.execute("SAVEPOINT c")
        uno(cur, pedir, (CUENTA, "ergometria", "revision", "r-1", "2030-01-10", "2029-12-20", None, "[]"))
        r = uno(cur, registrar, (CUENTA, hoy, True, "ergometria", "whatsapp", f"{CUENTA}/2030_erg.pdf", "e" * 64, True, None))
        chequear("antes del «no antes de» no cierra", r["cruce"] == "antes_de_tiempo", r)
        uno(cur, pedir, (CUENTA, "ergometria", "entrega", "r-2", "2030-01-10", None, None, "[]"))
        r = uno(cur, registrar, (CUENTA, hoy, True, "ergometria", "whatsapp", f"{CUENTA}/2030_erg2.pdf", "f" * 64, True, None))
        chequear("dos pedidos del mismo tipo no cierran solos", r["cruce"] == "varios_pedidos", r)
        cur.execute("ROLLBACK TO SAVEPOINT c")
        chequear("reabrir el laboratorio", uno(cur, "SELECT mypump_estudios_pedido_resolver(%s, 'reabrir', 'BOT MINI', NULL, 'faltó parte')", (ped_lab,)) == "ok")
        chequear("vuelve a pendientes", len(uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))["pendientes"]) == 1)

        print("▸ Órdenes")
        proponer = ("SELECT mypump_ordenes_app_proponer(%s, %s::uuid, %s, 'laboratorio', NOW(), mypump_estudios_hoy() + 60, %s, %s, %s, %s::jsonb, %s, '[]'::jsonb)")
        oid = str(uuid.uuid4())
        path_o = lambda: f"o/{carpeta}/{uuid.uuid4()}.pdf"
        practicas = json.dumps(["Testosterona total", "Hemograma completo"])
        r = uno(cur, proponer, (CUENTA, oid, "doc-1", path_o(), sha1, limpio, practicas, True))
        chequear("limpia queda a revisar", r["estado"] == "a_revisar" and r["control2_ok"] is True, r)
        orden = r["id"]
        chequear("a revisar no se ve", uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))["ordenes"] == [])
        firmar_o = "SELECT mypump_estudios_paths_para_firmar(%s, 'orden', %s)"
        chequear("ni se firma", uno(cur, firmar_o, (CUENTA, orden))["resultado"] == "no_encontrado")
        chequear("visible a mano sin publicar → lo frena el CHECK",
                 falla_con(cur, "UPDATE mypump_ordenes_app SET estado = 'visible' WHERE id = %s", (orden,)) == "23514")
        chequear("publicar sin nombre → error", falla_con(cur, "SELECT mypump_ordenes_app_publicar(%s, ' ')", (orden,)) == "22023")
        chequear("publicar", uno(cur, "SELECT mypump_ordenes_app_publicar(%s, 'Mati')", (orden,)) == "ok")
        g = uno(cur, "SELECT mypump_estudios_get(%s)", (tok,))
        chequear("se ve, sin texto ni path", len(g["ordenes"]) == 1 and set(g["ordenes"][0]) == {"id", "tipo", "titulo", "emitida", "vence", "vigente"}, g["ordenes"])
        chequear("se firma para su dueño", uno(cur, firmar_o, (CUENTA, orden))["resultado"] == "ok")
        chequear("no para otro", uno(cur, firmar_o, (OTRA, orden))["resultado"] in ("no_encontrado", "no_habilitado"))
        chequear("ensuciar el texto de una visible → lo frena el CHECK",
                 falla_con(cur, "UPDATE mypump_ordenes_app SET texto = texto || ' en ciclo' WHERE id = %s", (orden,)) == "23514")
        r = uno(cur, proponer, (CUENTA, oid, "doc-2", path_o(), sha2, limpio + " Control intra ciclo.", practicas, True))
        chequear("control 2 la bloquea aunque el 1 diga que sí", r["estado"] == "bloqueada" and r["control2_ok"] is False, r)
        chequear("bloqueada no se publica", uno(cur, "SELECT mypump_ordenes_app_publicar(%s, 'Mati')", (r["id"],)) == "estado")
        r = uno(cur, proponer, (CUENTA, oid, "doc-3", path_o(), "c" * 64, limpio, practicas, False))
        chequear("control 1 en falso la bloquea", r["estado"] == "bloqueada", r)
        cur.execute("UPDATE mypump_app_config SET valor = 'true' WHERE clave = 'ordenes_app_auto'")
        r = uno(cur, proponer, (CUENTA, oid, "doc-4", path_o(), "d" * 64, limpio, practicas, True))
        chequear("en automático, limpia queda visible", r["estado"] == "visible", r)
        r = uno(cur, proponer, (CUENTA, oid, "doc-5", path_o(), "e" * 64, limpio + " TRT", practicas, True))
        chequear("en automático, sucia queda bloqueada", r["estado"] == "bloqueada", r)
        chequear("sacar de la vista", uno(cur, "SELECT mypump_ordenes_app_bloquear(%s, 'Sistema base', 'orden corregida')", (orden,)) == "ok")
        chequear("ya no se firma", uno(cur, firmar_o, (CUENTA, orden))["resultado"] == "no_encontrado")

        print("▸ Permisos")
        cur.execute("""SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', has_function_privilege('anon', p.oid, 'EXECUTE'),
                              p.prosecdef
                         FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                        WHERE n.nspname = 'public' AND (p.proname LIKE 'mypump_estudios%' OR p.proname LIKE 'mypump_ordenes%')""")
        publicas = {"mypump_estudios_get", "mypump_estudios_envio_nuevo", "mypump_estudios_enviar", "mypump_estudios_hecho"}
        for firma, anon, _definer in cur.fetchall():
            nombre = firma.split("(")[0]
            chequear(f"anon {'puede' if nombre in publicas else 'no puede'} {nombre}", anon is (nombre in publicas))
        for t in ["mypump_estudios", "mypump_estudios_hojas", "mypump_estudios_pedidos", "mypump_estudios_envios", "mypump_estudios_archivos",
                  "mypump_ordenes_app", "mypump_estudios_habilitados"]:
            cur.execute("SELECT relrowsecurity FROM pg_class WHERE relname = %s", (t,))
            chequear(f"{t} con RLS", cur.fetchone()[0] is True)
            for rol in ("anon", "authenticated"):
                cur.execute("SELECT has_table_privilege(%s, %s, 'SELECT') OR has_table_privilege(%s, %s, 'INSERT') OR has_table_privilege(%s, %s, 'TRUNCATE')",
                            (rol, t, rol, t, rol, t))
                chequear(f"{t}: {rol} sin permisos", cur.fetchone()[0] is False)
            if t != "mypump_estudios_habilitados":
                cur.execute("SELECT has_table_privilege('service_role', %s, 'UPDATE') OR has_table_privilege('service_role', %s, 'TRUNCATE')", (t, t))
                chequear(f"{t}: service_role solo lee", cur.fetchone()[0] is False)
        cur.execute("SELECT public FROM storage.buckets WHERE id = 'estudios'")
        chequear("bucket estudios privado", cur.fetchone()[0] is False)
        cur.execute("SELECT count(*) FROM pg_policies WHERE schemaname = 'storage' AND (qual ILIKE '%%''estudios''%%' OR with_check ILIKE '%%''estudios''%%')")
        chequear("bucket sin políticas", cur.fetchone()[0] == 0)

        print("▸ Reverso")
        cur.execute(reverso)
        despues = foto(cur)
        # El bucket lo borra aparte el script del bucket (Storage no deja borrarlo por SQL).
        chequear("después del reverso queda como antes (salvo el bucket)",
                 (despues[0], despues[1], [x for x in despues[2] if x != "estudios"], despues[3]) == antes)
    finally:
        conn.rollback()
    cur = conn.cursor()
    chequear("ROLLBACK: la base quedó como estaba", foto(cur) == antes)
    conn.rollback()
    conn.close()
    print(f"\n{'TODO BIEN' if not fallas else 'FALLAS: ' + '; '.join(fallas)}")
    sys.exit(1 if fallas else 0)


if __name__ == "__main__":
    main()
