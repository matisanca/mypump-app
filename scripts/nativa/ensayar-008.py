#!/usr/bin/env python3
"""ensayar-008.py — ensaya nativa_008 (día de revisión por alumno) y su vuelta atrás en producción SIN aplicarlas.

Todo corre en una transacción que termina en ROLLBACK. Con todos en el día 7 (el default), la ronda y el check tienen
que dar exactamente lo mismo que hoy; con el día 6 en una cuenta de prueba, el domingo pasa a la semana siguiente.
Después aplica el revert dentro de la misma transacción y verifica que las funciones vuelven a ser las de antes.

  scp scripts/nativa/ensayar-008.py supabase/migrations/nativa_008_*.sql mini:/tmp/
  ssh mini '~/agentkit-coach/venv/bin/python /tmp/ensayar-008.py /tmp/nativa_008_revision_dia.sql /tmp/nativa_008_revert.sql'
"""
import os
import re
import sys

import psycopg2

CUENTA = "test-nativa-ios"
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


def cuerpo(ruta):
    """El SQL sin el BEGIN/COMMIT de afuera: lo envuelve la transacción del ensayo."""
    s = open(ruta, encoding="utf-8").read()
    s = re.sub(r"^BEGIN;\s*$", "", s, count=1, flags=re.M)
    s = re.sub(r"^COMMIT;\s*$", "", s, flags=re.M)
    return s


FUNCS = ("mypump_guardar_checkin", "mypump_get_checkin_semana", "mypump_chat_faltantes_semana")


def huellas(cur):
    cur.execute("""SELECT p.proname, md5(pg_get_functiondef(p.oid)), array_to_string(p.proacl, ',')
                   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                   WHERE n.nspname = 'public' AND p.proname = ANY(%s) ORDER BY 1""", (list(FUNCS),))
    return cur.fetchall()


def ronda(cur):
    cur.execute("""SELECT cliente_id, falta_check, fotos_puestas, avisos_semana, ia_activa, escalado, silenciado
                   FROM mypump_chat_faltantes_semana() ORDER BY 1""")
    return cur.fetchall()


def puede(cur, rol, firma):
    cur.execute("SELECT has_function_privilege(%s, %s, 'EXECUTE')", (rol, firma))
    return cur.fetchone()[0]


def main():
    mig, rev = sys.argv[1], sys.argv[2]
    con = psycopg2.connect(url_base())
    cur = con.cursor()
    try:
        antes_f = huellas(cur)
        antes_r = ronda(cur)
        cur.execute("SELECT count(*) FROM mypump_checkin_semanal")
        antes_n = cur.fetchone()[0]
        print(f"antes: {len(antes_r)} filas en la ronda, {antes_n} check-ins")

        cur.execute(cuerpo(mig))
        print("nativa_008 corrida (sin COMMIT)")

        despues_r = [r[:7] for r in ronda(cur)]
        chequear("la ronda da lo mismo con todos en el día 7", despues_r == antes_r,
                 f"{sum(1 for a, b in zip(antes_r, despues_r) if a != b)} filas distintas")
        cur.execute("SELECT count(*) FROM mypump_chat_faltantes_semana() WHERE revision_dia <> 7")
        chequear("todos en el día 7", cur.fetchone()[0] == 0)
        cur.execute("SELECT count(*) FROM mypump_chat_faltantes_semana() WHERE extract(isodow FROM semana_lunes) <> 1")
        chequear("semana_lunes siempre es lunes", cur.fetchone()[0] == 0)

        cur.execute("SELECT mypump_semana_revision(%s, '2026-11-08'), mypump_semana_revision(%s, '2026-11-07')",
                    (CUENTA, CUENTA))
        dom, sab = cur.fetchone()
        chequear("día 7: sáb y dom en la semana del lunes 2/11", str(dom) == str(sab) == "2026-11-02", (dom, sab))

        cur.execute("SELECT mypump_set_revision_dia(%s, 6::smallint)", (CUENTA,))
        chequear("set en la cuenta de prueba", cur.fetchone()[0] is True)
        cur.execute("SELECT mypump_semana_revision(%s, '2026-11-08'), mypump_semana_revision(%s, '2026-11-07'),"
                    " mypump_semana_revision(%s, '2026-11-02')", (CUENTA, CUENTA, CUENTA))
        dom, sab, lun = cur.fetchone()
        chequear("día 6: el sábado cierra la semana del 2/11", str(sab) == "2026-11-02", sab)
        chequear("día 6: el domingo abre la semana del 9/11", str(dom) == "2026-11-09", dom)
        chequear("día 6: el lunes sigue en su semana", str(lun) == "2026-11-02", lun)
        cur.execute("SELECT mypump_set_revision_dia('no-existe-xyz', 6::smallint)")
        chequear("set a un cliente que no existe da false", cur.fetchone()[0] is False)
        try:
            cur.execute("SAVEPOINT s; SELECT mypump_set_revision_dia(%s, 9::smallint)", (CUENTA,))
            chequear("día 9 se rechaza", False)
        except psycopg2.Error:
            cur.execute("ROLLBACK TO SAVEPOINT s")
            chequear("día 9 se rechaza", True)
        cur.execute("SELECT mypump_get_revision_dia('token-que-no-existe')")
        chequear("token inválido da 7", cur.fetchone()[0] == 7)
        cur.execute("SELECT mypump_get_revision_dia(access_token) FROM mypump_clientes WHERE cliente_id = %s", (CUENTA,))
        chequear("get con el token de la cuenta da 6", cur.fetchone()[0] == 6)

        chequear("anon ejecuta get_revision_dia", puede(cur, "anon", "mypump_get_revision_dia(text)"))
        for firma in ("mypump_set_revision_dia(text,smallint)", "mypump_revision_dia(text)",
                      "mypump_semana_revision(text,date)", "mypump_chat_faltantes_semana()"):
            chequear(f"anon NO ejecuta {firma}", not puede(cur, "anon", firma))
        chequear("authenticated ejecuta la ronda", puede(cur, "authenticated", "mypump_chat_faltantes_semana()"))
        cur.execute("SELECT count(*) FROM mypump_checkin_semanal")
        chequear("no cambia la cantidad de check-ins", cur.fetchone()[0] == antes_n)

        cur.execute(cuerpo(rev))
        print("revert corrido (sin COMMIT)")
        chequear("el revert deja las tres funciones como antes (definición y permisos)", huellas(cur) == antes_f,
                 huellas(cur))
        cur.execute("""SELECT count(*) FROM information_schema.columns
                       WHERE table_name = 'mypump_cliente_prefs' AND column_name = 'revision_dia'""")
        chequear("el revert saca la columna", cur.fetchone()[0] == 0)
        chequear("la ronda vuelve a dar lo mismo", ronda(cur) == antes_r)
        cur.execute("SELECT mypump_get_revision_dia(access_token) FROM mypump_clientes WHERE cliente_id = %s", (CUENTA,))
        chequear("tras el revert, get_revision_dia sigue y da 7", cur.fetchone()[0] == 7)
        chequear("tras el revert, anon sigue ejecutando get_revision_dia", puede(cur, "anon", "mypump_get_revision_dia(text)"))
    finally:
        con.rollback()
        con.close()
    con = psycopg2.connect(url_base())
    cur = con.cursor()
    chequear("ROLLBACK: la base quedó como estaba", huellas(cur) == antes_f)
    con.close()
    print("TODO OK" if not fallas else f"FALLAS: {fallas}")
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
