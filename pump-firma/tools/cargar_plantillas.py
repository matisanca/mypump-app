#!/usr/bin/env python3
"""Carga una versión de plantilla en contrato.plantillas y la deja vigente. El texto NO se toca: entra byte a byte
desde el archivo aprobado, y el md5 esperado se pasa a mano para que un archivo equivocado no entre.

Uso (con el rol dueño, no con firma_srv):
  FIRMA_DB_ADMIN_URL=postgresql://... python tools/cargar_plantillas.py servicio_ar v8 /ruta/A_v8.md <md5 esperado> [--ensayo]

`--ensayo` hace todo y termina en ROLLBACK. Una versión ya cargada con el mismo texto no se vuelve a cargar."""
import hashlib
import os
import sys

import psycopg

TIPOS = ("servicio_ar", "servicio_ext", "consentimiento_ar")


def titulo_de(md: str) -> str:
    for l in md.splitlines():
        if l.startswith("# "):
            return l[2:].strip()
    raise SystemExit("la plantilla no tiene título (# ...)")


def cargar(conn, tipo: str, version: str, md: str, vigente: bool = True) -> dict:
    """Devuelve {'id', 'sha256', 'md5', 'resultado'}; no hace commit."""
    if tipo not in TIPOS:
        raise SystemExit(f"tipo inválido: {tipo}")
    pid = f"{tipo}@{version}"
    sha, md5 = hashlib.sha256(md.encode("utf-8")).hexdigest(), hashlib.md5(md.encode("utf-8")).hexdigest()
    with conn.cursor() as cur:
        cur.execute("SELECT fuente_sha256, vigente FROM contrato.plantillas WHERE id = %s", (pid,))
        fila = cur.fetchone()
        if fila:
            if fila[0] != sha:
                raise SystemExit(f"{pid} ya existe con OTRO texto: una versión no se edita; cargá una versión nueva")
            resultado = "ya_estaba"
        else:
            cur.execute("INSERT INTO contrato.plantillas (id, tipo, version, titulo, fuente_md, fuente_sha256, fuente_md5, vigente) "
                        "VALUES (%s, %s, %s, %s, %s, %s, %s, false)", (pid, tipo, version, titulo_de(md), md, sha, md5))
            resultado = "cargada"
        if vigente:
            cur.execute("UPDATE contrato.plantillas SET vigente = false WHERE tipo = %s AND vigente AND id <> %s", (tipo, pid))
            cur.execute("UPDATE contrato.plantillas SET vigente = true WHERE id = %s AND NOT vigente", (pid,))
        cur.execute("SELECT fuente_sha256 = encode(sha256(convert_to(fuente_md, 'UTF8')), 'hex') FROM contrato.plantillas WHERE id = %s", (pid,))
        assert cur.fetchone()[0], "la base no confirma el hash"
    return {"id": pid, "sha256": sha, "md5": md5, "resultado": resultado}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 4:
        raise SystemExit(__doc__)
    tipo, version, ruta, md5_esperado = args
    md = open(ruta, "rb").read().decode("utf-8")
    md5 = hashlib.md5(md.encode("utf-8")).hexdigest()
    if md5 != md5_esperado.lower():
        raise SystemExit(f"md5 del archivo {md5} ≠ esperado {md5_esperado}: no se carga")
    url = os.environ.get("FIRMA_DB_ADMIN_URL")
    if not url:
        raise SystemExit("falta FIRMA_DB_ADMIN_URL")
    with psycopg.connect(url, autocommit=False, prepare_threshold=None) as conn:
        r = cargar(conn, tipo, version, md)
        if "--ensayo" in sys.argv:
            conn.rollback()
            r["resultado"] += " (ENSAYO: ROLLBACK)"
        else:
            conn.commit()
    print(r)


if __name__ == "__main__":
    main()
