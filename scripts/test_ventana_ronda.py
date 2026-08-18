#!/usr/bin/env python3
"""test_ventana_ronda.py — la ronda no puede programarse a la madrugada

POR QUE EXISTE
El 16-ago la ronda del domingo murio por una RPC ambigua (PGRST203) y hubo que
reponerla a mano. La reposicion se corrio 00:43: el escalonado repartia los 61
mensajes entre las 00:43 y la 01:34, y el drenador de la 062 —que fuera de la
ventana solo publica respuestas— los iba a retener y soltar TODOS JUNTOS a las
08:00. El cliente habria visto 61 mensajes en el mismo minuto.

El drenador protege la HORA. Esto protege el ESCALONADO. Son dos cosas
distintas y hacen falta las dos.
"""
import datetime as dt
import pathlib
import re
import sys
from zoneinfo import ZoneInfo

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SRC = (RAIZ / "pump-centinela" / "recordatorios.py").read_text()
TZ = ZoneInfo("America/Argentina/Buenos_Aires")

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


# Las constantes salen del ARCHIVO, no se re-declaran aca. Si alguien cambia la
# ventana en el codigo, el test la sigue; si la borra, el test se cae.
def _const(nombre):
    m = re.search(rf"^{nombre}\s*=\s*(\d+)", SRC, re.M)
    if not m:
        print(f"✗ no encuentro la constante {nombre} en recordatorios.py")
        sys.exit(1)
    return int(m.group(1))


DESDE, HASTA = _const("HORA_DESDE"), _const("HORA_HASTA")

print("\n1. La ventana existe y es la misma que la del drenador (mig 062)")
check("HORA_DESDE = 8", DESDE == 8, f"vale {DESDE}; la 062 usa v_hora < 8")
check("HORA_HASTA = 23", HASTA == 23, f"vale {HASTA}; la 062 usa v_hora >= 23")

print("\n2. La base horaria respeta la ventana")


def base_horaria(ahora, a_las=None):
    """Reimplementa la decision para poder probarla con horas fijas.

    Se mantiene alineada con el original por el check de estructura de abajo:
    si el codigo real deja de empujar la base, ese check falla.
    """
    if a_las:
        h, m = a_las
        base = ahora.replace(hour=h, minute=m, second=0, microsecond=0)
        return base + dt.timedelta(days=1) if base <= ahora else base
    if DESDE <= ahora.hour < HASTA:
        return ahora
    base = ahora.replace(hour=DESDE, minute=0, second=0, microsecond=0)
    return base + dt.timedelta(days=1) if base <= ahora else base


casos = [
    ("madrugada 00:43 -> empuja a las 08:00 de HOY", dt.datetime(2026, 8, 18, 0, 43, tzinfo=TZ), None,
     dt.datetime(2026, 8, 18, 8, 0, tzinfo=TZ)),
    ("23:30 -> empuja a las 08:00 de MANANA", dt.datetime(2026, 8, 18, 23, 30, tzinfo=TZ), None,
     dt.datetime(2026, 8, 19, 8, 0, tzinfo=TZ)),
    ("domingo 18:00 (el horario normal) -> no toca nada", dt.datetime(2026, 8, 16, 18, 0, tzinfo=TZ), None,
     dt.datetime(2026, 8, 16, 18, 0, tzinfo=TZ)),
    ("08:00 clavadas -> ya esta adentro, no empuja un dia", dt.datetime(2026, 8, 18, 8, 0, tzinfo=TZ), None,
     dt.datetime(2026, 8, 18, 8, 0, tzinfo=TZ)),
    ("22:59 -> ultimo minuto valido, no empuja", dt.datetime(2026, 8, 18, 22, 59, tzinfo=TZ), None,
     dt.datetime(2026, 8, 18, 22, 59, tzinfo=TZ)),
    ("--a-las 18:00 desde la madrugada -> hoy 18:00", dt.datetime(2026, 8, 18, 0, 43, tzinfo=TZ), (18, 0),
     dt.datetime(2026, 8, 18, 18, 0, tzinfo=TZ)),
    ("--a-las 09:00 cuando ya son las 20:00 -> manana", dt.datetime(2026, 8, 18, 20, 0, tzinfo=TZ), (9, 0),
     dt.datetime(2026, 8, 19, 9, 0, tzinfo=TZ)),
]
for nombre, ahora, a_las, esperado in casos:
    got = base_horaria(ahora, a_las)
    check(nombre, got == esperado, f"esperaba {esperado:%a %d/%m %H:%M}, dio {got:%a %d/%m %H:%M}")

print("\n3. La ventana completa cae adentro del horario que publica el drenador")
# El ultimo mensaje sale hasta VENTANA_MAX minutos despues de la base. Si la
# base fuera valida pero la cola se pasara de las 23:00, el ultimo tramo
# quedaria retenido y saldria al otro dia, descolgado del resto.
VMAX = _const("VENTANA_MAX")
fin = dt.datetime(2026, 8, 18, HASTA - 1, 59, tzinfo=TZ) + dt.timedelta(minutes=VMAX)
check(f"una base a las {HASTA - 1}:59 desborda la ventana en {VMAX} min (limitacion conocida)",
      fin.hour >= HASTA,
      "esto es esperado: el drenador retiene la cola y la suelta a las 08:00")

print("\n4. El codigo real usa la guarda (no solo el test)")
check("programar_ronda llama a _base_horaria()", "base = _base_horaria()" in SRC,
      "si volvio a ser datetime.now(timezone.utc), la guarda no corre")
check("_base_horaria empuja la base fuera de ventana",
      bool(re.search(r"def _base_horaria.*?hour=HORA_DESDE", SRC, re.S)),
      "la funcion existe pero no empuja al proximo HORA_DESDE")
check("--a-las esta cableado", "_arg_a_las" in SRC and "A_LAS" in SRC)

print()
if fallas:
    print(f"✗ {fallas} fallo(s) en la ventana de la ronda\n")
    sys.exit(1)
print("✓ la ronda no puede programarse fuera de la ventana\n")
