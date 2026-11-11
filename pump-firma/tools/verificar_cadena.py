#!/usr/bin/env python3
"""Recalcula la cadena de eventos y dice si está íntegra. Solo lee.
  FIRMA_ENV=~/pump-firma-datos/firma.env python tools/verificar_cadena.py            (desde la base)
  python tools/verificar_cadena.py --archivo ~/pump-firma-datos/respaldo/AAAA-MM-DD/eventos.jsonl   (desde un respaldo)
Sale con código 0 si está íntegra y 1 si no."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from firma import reglas  # noqa: E402


def main():
    if "--archivo" in sys.argv:
        eventos = [json.loads(l) for l in open(sys.argv[sys.argv.index("--archivo") + 1], encoding="utf-8") if l.strip()]
    else:
        from firma.base import Base
        from firma.config import Config
        cfg = Config()
        eventos, desde = [], 0
        with Base(cfg.db_url).conexion() as s:
            while True:
                tanda = s.f("cadena", desde, 2000)
                if not tanda:
                    break
                eventos += tanda
                desde = tanda[-1]["n"]
    v = reglas.verificar_cadena(eventos)
    print(json.dumps(v, ensure_ascii=False))
    sys.exit(0 if v["ok"] else 1)


if __name__ == "__main__":
    main()
