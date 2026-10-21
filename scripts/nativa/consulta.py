#!/usr/bin/env python3
"""consulta.py — una consulta de SOLO LECTURA a producción en un paso (por `_q.py` de la Mini).

Antes cada consulta era un script nuevo que envolvía el SQL en json_agg, lo mandaba por ssh y parseaba la salida
(21-oct: Mati pidió gastar menos pasos). Esto lo hace una vez:

  python3 scripts/nativa/consulta.py "select cliente_id, plataforma, app_version from mypump_push_devices limit 5"
  python3 scripts/nativa/consulta.py -f consulta.sql
  python3 scripts/nativa/consulta.py --completo "select ..."     # sin cortar las celdas largas
  python3 scripts/nativa/consulta.py --json salida.json "select ..."   # además guarda las filas (p. ej. en privado/)

Imprime una fila por renglón en JSON, con las celdas largas cortadas a 300 caracteres. Es de solo lectura sí o sí:
corre en una transacción READ ONLY y rechaza más de una sentencia.
"""
import json
import subprocess
import sys

Q = "~/agentkit-coach/venv/bin/python3 ~/pump-centinela/_q.py"


def main() -> int:
    args = sys.argv[1:]
    completo = "--completo" in args
    args = [a for a in args if a != "--completo"]
    destino = None
    if "--json" in args:
        i = args.index("--json")
        destino = args[i + 1]
        del args[i:i + 2]
    if args[:1] == ["-f"]:
        sql = open(args[1], encoding="utf-8").read()
    elif len(args) == 1:
        sql = args[0]
    else:
        print(__doc__)
        return 2
    sql = sql.strip().rstrip(";").strip()
    if ";" in sql:
        print("una sola sentencia, sin ';' en el medio")
        return 2
    envuelta = f"SET TRANSACTION READ ONLY; SELECT coalesce(json_agg(x)::text, '[]') FROM ({sql}) x"
    r = subprocess.run(["ssh", "mini", Q], input=envuelta, capture_output=True, text=True, timeout=300)
    if r.returncode != 0:
        print(r.stderr.strip()[-1500:])
        return 1
    filas = json.loads("\n".join(r.stdout.splitlines()[1:]).strip() or "[]")
    if destino:
        with open(destino, "w", encoding="utf-8") as f:
            json.dump(filas, f, ensure_ascii=False, indent=1)
    for fila in filas:
        if not completo and isinstance(fila, dict):
            fila = {k: (v[:300] + "…" if isinstance(v, str) and len(v) > 300 else v) for k, v in fila.items()}
        print(json.dumps(fila, ensure_ascii=False, default=str))
    print(f"({len(filas)} filas)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
