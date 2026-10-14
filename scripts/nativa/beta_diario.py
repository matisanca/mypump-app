#!/usr/bin/env python3
"""El control diario de la beta de la 2.0 (plan, Fase 3: «todos los días miro recibos, conteos, devices iOS por
app_version y fallidos»). SOLO LECTURA: corre en la MacBook y consulta la base por `_q.py` de la Mini.

Por cliente con la nativa:
  · el teléfono: plataforma, versión, si el push anda y cuándo se lo vio;
  · el último recibo de la migración: ⚠️ si alguna tabla del servidor BAJÓ (la prueba de cero pérdida), si quedó algo en
    la cola o en fallidos, o fotos sin subir;
  · las sustituciones de ejercicio en el servidor (SER-14).
Por defecto muestra ids, no nombres, y saltea las cuentas test-*.

Uso: python3 scripts/nativa/beta_diario.py [--dias 7] [--con-pruebas]
"""
import argparse
import json
import subprocess
import sys

Q = "~/agentkit-coach/venv/bin/python3 ~/pump-centinela/_q.py"


def consulta(sql: str) -> list:
    """Una consulta que devuelve una sola celda de JSON (json_agg::text)."""
    r = subprocess.run(["ssh", "mini", Q], input=sql, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        sys.exit(f"la consulta falló: {r.stderr.strip()[:300]}")
    # _q.py imprime el encabezado y después la celda; json_agg corta el JSON en varias líneas.
    lineas = r.stdout.splitlines()
    cuerpo = "\n".join(lineas[1:]).strip()
    return json.loads(cuerpo) if cuerpo else []


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dias", type=int, default=7)
    ap.add_argument("--con-pruebas", action="store_true")
    a = ap.parse_args()
    filtro = "" if a.con_pruebas else "and cliente_id not like 'test%'"

    devices = consulta(f"""select coalesce(json_agg(d order by visto_en desc nulls last)::text, '[]') from (
        select cliente_id, plataforma, app_version, activo, ultimo_error, visto_en from mypump_push_devices
        where app_version like '2.%' {filtro}) d""")
    recibos = consulta(f"""select coalesce(json_agg(r order by recibido_en desc)::text, '[]') from (
        select cliente_id, plataforma, corrida, app_version, recibido_en, recibo from mypump_migracion_nativa
        where recibido_en > now() - interval '{int(a.dias)} days' {filtro}) r""")
    swaps = consulta(f"""select coalesce(json_agg(s)::text, '[]') from (
        select cliente_id, count(*) filter (where swap is not null) as vivas, count(*) filter (where swap is null) as lapidas,
               max(actualizado_en) as ultima from mypump_exercise_swaps where true {filtro} group by cliente_id) s""")

    clientes = sorted({x["cliente_id"] for x in devices + recibos + swaps})
    print(f"Beta de la 2.0 · últimos {a.dias} días · {len(clientes)} clientes con la nativa"
          + ("" if a.con_pruebas else " (sin las cuentas test-*)"))
    alertas = 0
    for c in clientes:
        print(f"\n== {c}")
        for d in [x for x in devices if x["cliente_id"] == c]:
            push = "push OK" if d["activo"] and not d["ultimo_error"] else f"push ⚠️ {d['ultimo_error'] or 'inactivo'}"
            print(f"  {d['plataforma']} {d['app_version']} · {push} · visto {str(d['visto_en'])[:16]}")
        propios = [x for x in recibos if x["cliente_id"] == c]
        if propios:
            r = propios[0]
            rec = r["recibo"] or {}
            antes, despues = rec.get("servidorAntes") or {}, rec.get("servidorDespues") or {}
            bajaron = [f"{t} {antes[t]}→{despues[t]}" for t in antes if t in despues and despues[t] < antes[t]]
            local = rec.get("despues") or {}
            quedaron = {k: local.get(k) for k in ("fallidos", "colaPendientes", "fotosPendientes", "colasEsperando") if local.get(k)}
            marca = "⚠️" if bajaron or quedaron else "✓"
            alertas += bool(bajaron or quedaron)
            print(f"  recibo {marca} corrida {r['corrida']} · {r['app_version']} · {str(r['recibido_en'])[:16]}"
                  f" · {len(propios)} recibos en el período")
            if bajaron:
                print(f"    BAJARON en el servidor: {', '.join(bajaron)}")
            if quedaron:
                print(f"    quedaron en el teléfono: {quedaron}")
            if not despues:
                print("    (el recibo no trae los conteos de después: la Fase R no terminó)")
        for s in [x for x in swaps if x["cliente_id"] == c]:
            print(f"  sustituciones en el servidor: {s['vivas']} vivas, {s['lapidas']} lápidas · última {str(s['ultima'])[:16]}")
    print(f"\n{'⚠️ ' + str(alertas) + ' con algo para mirar' if alertas else '✓ sin alertas'}")


if __name__ == "__main__":
    main()
