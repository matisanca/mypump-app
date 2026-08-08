#!/usr/bin/env python3
"""
auditar_seguridad_db.py — qué puede hacer un desconocido con la anon key.

POR QUÉ EXISTE
La anon key de Supabase está en `public/js/config.js`, commiteada, y tiene que
estarlo: es la que usa la app en el navegador. O sea que cualquiera la tiene.
Lo único que separa los datos de los clientes de internet es la combinación de
RLS, GRANTs y las guardas dentro de cada función. Eso son tres capas que se
pueden desalinear de a una, y ninguna avisa cuando se desalinea.

Los avisos de "RLS disabled" del panel de Supabase no alcanzan para saber si hay
un problema real: una tabla sin RLS es inofensiva si anon no tiene GRANT, y una
tabla CON RLS puede estar abierta si una política dice `USING (true)` para
public. Hay que cruzar las tres cosas, que es lo que hace esto.

DÓNDE CORRE
Necesita la conexión directa a Postgres, que vive en la **mini**:

    scp scripts/auditar_seguridad_db.py mini:~/
    ssh mini "~/agentkit-coach/venv/bin/python3 ~/auditar_seguridad_db.py"

SOLO LECTURA. No modifica nada.
"""
import os
import sys

try:
    import psycopg2
except ImportError:
    print("falta psycopg2 — esto corre en la mini, con ~/agentkit-coach/venv/bin/python3")
    sys.exit(1)

ENV = os.path.expanduser("~/agentkit-coach/.env")
if not os.path.exists(ENV):
    print(f"no encuentro {ENV}. ¿Estás corriendo esto en la mini?")
    sys.exit(1)

env = {}
for linea in open(ENV):
    linea = linea.strip()
    if "=" in linea and not linea.startswith("#"):
        k, v = linea.split("=", 1)
        env[k] = v.strip().strip('"').strip("'")

cn = psycopg2.connect(env["SUPABASE_DB_URL"])
cu = cn.cursor()


def q(sql, args=None):
    cu.execute(sql, args or ())
    return cu.fetchall()


problemas = []
avisos = []

# ── 1. Tablas ───────────────────────────────────────────────────────────
print("\n1. Tablas alcanzables por anon")
filas = q("""
  SELECT c.relname, c.relrowsecurity,
         has_table_privilege('anon', c.oid, 'SELECT'),
         has_table_privilege('anon', c.oid, 'INSERT'),
         has_table_privilege('anon', c.oid, 'UPDATE'),
         has_table_privilege('anon', c.oid, 'DELETE'),
         (SELECT count(*) FROM pg_policy p WHERE p.polrelid = c.oid)
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'r'
  ORDER BY c.relname""")

for nom, rls, s, i, u, d, pols in filas:
    ops = "".join(x for x, f in zip("SIUD", [s, i, u, d]) if f)
    if not ops:
        continue                      # anon no tiene GRANT: inalcanzable
    if not rls:
        # GRANT sin RLS = acceso directo y total a la tabla.
        problemas.append(f"{nom}: anon tiene {ops} y la tabla NO tiene RLS")
        print(f"  ✗ {nom:32} {ops}  SIN RLS")
    elif pols == 0:
        # RLS sin políticas deniega todo: el GRANT sobra pero no abre nada.
        print(f"  · {nom:32} {ops}  RLS sin políticas (deniega todo)")
    else:
        print(f"  ✓ {nom:32} {ops}  RLS con {pols} política/s")

# ── 2. Políticas que no filtran ─────────────────────────────────────────
print("\n2. Políticas abiertas a anon/public")
filas = q("""
  SELECT c.relname, p.polname, p.polcmd,
         (SELECT array_agg(rolname) FROM pg_roles WHERE oid = ANY(p.polroles)),
         pg_get_expr(p.polqual, p.polrelid)
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'""")

for nom, pol, cmd, roles, qual in filas:
    roles = roles or ["public"]
    abierta = qual is None or qual.strip().lower() == "true"
    alcanza_anon = "public" in roles or "anon" in roles
    if not (abierta and alcanza_anon):
        continue
    if cmd == "r":
        # SELECT abierto: puede ser deliberado (catálogo público de ejercicios).
        avisos.append(f"{nom}.{pol}: SELECT abierto a {roles}")
        print(f"  ⚠ {nom}.{pol} [SELECT] {roles} — ¿es público a propósito?")
    else:
        problemas.append(f"{nom}.{pol}: {cmd} abierto a {roles} sin filtro")
        print(f"  ✗ {nom}.{pol} [{cmd}] {roles} — ESCRITURA sin filtro")

# ── 3. Funciones SECURITY DEFINER que anon puede llamar ─────────────────
print("\n3. Funciones SECURITY DEFINER ejecutables por anon")
filas = q("""
  SELECT p.proname, pg_get_function_result(p.oid), pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prosecdef
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
  ORDER BY p.proname""")

# Una función SECURITY DEFINER corre con los permisos del dueño, asi que tiene
# que traer su propia guarda. Hay DOS válidas y hay que aceptar las dos:
#   · por token  -> la usan las RPC del cliente (p_token / *_from_token)
#   · por rol    -> la usan las del coach (auth.role() <> 'authenticated')
# La primera version de este chequeo solo miraba la de token y marcaba como
# sospechosas funciones que estaban perfectamente protegidas por rol.
GUARDAS = ("p_token", "from_token", "auth.role()", "auth.uid()", "auth.jwt()")

desprotegidas, triggers, ok = [], 0, 0
for nom, ret, definicion in filas:
    if ret.strip() == "trigger":
        # PostgREST no expone triggers: no se pueden invocar por RPC.
        triggers += 1
        continue
    if any(g in definicion for g in GUARDAS):
        ok += 1
        continue
    escribe = any(f"{k} " in definicion.upper() for k in ("INSERT", "UPDATE", "DELETE"))
    desprotegidas.append((nom, escribe))

print(f"  {len(filas)} funciones · {ok} con guarda · {triggers} triggers (no invocables)")
for nom, escribe in desprotegidas:
    if escribe:
        problemas.append(f"{nom}: SECURITY DEFINER, anon puede llamarla, ESCRIBE y no tiene guarda")
        print(f"  ✗ {nom} — escribe y no valida ni token ni rol")
    else:
        avisos.append(f"{nom}: SECURITY DEFINER sin guarda (solo lectura)")
        print(f"  ⚠ {nom} — solo lectura, sin guarda. ¿Los datos son públicos?")

# ── Veredicto ───────────────────────────────────────────────────────────
print("\n" + "=" * 66)
if problemas:
    print(f"✗ {len(problemas)} problema(s) de seguridad:")
    for p in problemas:
        print(f"    · {p}")
else:
    print("✓ ningún agujero: con la anon key sola no se llega a datos de clientes")
if avisos:
    print(f"\n{len(avisos)} cosa(s) a confirmar que sean a propósito:")
    for a in avisos:
        print(f"    · {a}")

cn.close()
sys.exit(1 if problemas else 0)
