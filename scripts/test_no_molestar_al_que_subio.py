#!/usr/bin/env python3
"""test_no_molestar_al_que_subio.py — no le pidas la revisión a quien ya la mandó.

POR QUE EXISTE
El 28-ago-2026 tres clientes preguntaron lo mismo por WhatsApp:

  Ismael:  "No se que pasa que no te aparece la revisión. La hice hace dos días"
  Gerardo: "Pudiste ver la revisión porq la envié el lunes o martes"
  José:    "Está hecha mati... no sé porque no se han registrado"

Los tres habían subido el check Y las 3 fotos. La app se los mostraba con el
tilde de "✓ enviado". Y aun así el recordatorio del martes y el del jueves les
volvió a pedir la revisión. A Ismael le llegó uno CINCO HORAS DESPUÉS de que
escribiera "Ayer subí, ¿lo habré subido mal?".

La RPC calculaba bien `falta_check` y `fotos_puestas`. `programar_ronda` los
usaba solo para elegir el TEXTO (fotos vs revisión entera) y nunca para dejar a
nadie afuera, así que el que tenía todo caía en el `elif recordatorio`.

Este test corre `faltantes()` con datos reales de esos tres y exige que queden
afuera.
"""
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))
import recordatorios as R  # noqa: E402

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


def fila(cid, nombre, falta_check, fotos, avisos=0, escalado=False, silenciado=False):
    return {"cliente_id": cid, "nombre": nombre, "falta_check": falta_check,
            "fotos_puestas": fotos, "avisos_semana": avisos, "ia_activa": True,
            "escalado": escalado, "silenciado": silenciado}


CASOS = [
    # los tres que se quejaron: check hecho + las 3 fotos
    fila("mrl1cd0zwavd", "Ismael Pose",        False, 3),
    fila("mrk2n0qm7swk", "Gerardo Mendez",     False, 3),
    fila("mrl1cczlai0u", "Jose Sanchez",       False, 3),
    # los que SI tienen algo pendiente
    fila("c-sincheck",   "Sin check",          True,  0),
    fila("c-solofotos",  "Check si, fotos no", False, 1),
    fila("c-parcial",    "Check si, 2 de 3",   False, 2),
    # los que quedan afuera por otras razones, que ya andaban
    fila("c-escalado",   "Escalado",           True,  0, escalado=True),
    fila("c-silenciado", "Silenciado",         True,  0, silenciado=True),
    fila("c-tope",       "En el tope",         True,  0, avisos=3),
]

R._sb = lambda fn, payload=None: CASOS
R._ya_recibio_hoy = lambda: set()

todos, listos = R.faltantes()
ids = {f["cliente_id"] for f in listos}

print("\n1. Los tres que se quejaron NO reciben nada")
check("Ismael queda afuera",  "mrl1cd0zwavd" not in ids,
      "subió check + 3 fotos y le llegarían recordatorios igual")
check("Gerardo queda afuera", "mrk2n0qm7swk" not in ids)
check("José queda afuera",    "mrl1cczlai0u" not in ids)

print("\n2. A quien SÍ le falta algo se le sigue escribiendo")
check("sin check → se le escribe",        "c-sincheck"  in ids)
check("check pero 0 fotos → se le escribe", "c-solofotos" in ids)
check("check pero 2 de 3 fotos → se le escribe", "c-parcial" in ids,
      "3 poses son la revisión completa; con 2 todavía falta una")

print("\n3. Los filtros que ya existían siguen andando")
check("escalado afuera",   "c-escalado"   not in ids)
check("silenciado afuera", "c-silenciado" not in ids)
check("en el tope afuera", "c-tope"       not in ids)

print("\n4. El total cierra")
check("quedan exactamente 3 de 9", len(listos) == 3, f"quedaron {len(listos)}: {sorted(ids)}")
check("faltantes() devuelve igual la lista completa", len(todos) == 9)

print("\n5. El dato viene de la RPC y no de una heurística local")
FUENTE = (RAIZ / "pump-centinela" / "recordatorios.py").read_text()
check("se filtra por falta_check y fotos_puestas",
      'if not f["falta_check"] and f["fotos_puestas"] >= 3:' in FUENTE,
      "si esto cambia de forma, el test de arriba puede pasar por casualidad")


print("\n6. El drenador vuelve a chequear justo antes de publicar")
# El filtro de faltantes() evita PROGRAMAR. Pero entre programar y publicar
# pasan 40-60 min por el escalonado, y quien sube en ese rato —justo lo que hace
# el que ve la notificación y va a la app— tenía el mensaje ya en la cola.
SQL69 = (RAIZ / "supabase" / "migrations" / "069_no_pedir_lo_ya_subido.sql").read_text()
check("el drenador consulta el check al publicar",
      "FROM mypump_checkin_semanal k" in SQL69 and "INTO v_falta_check" in SQL69)
check("y también las fotos", "count(DISTINCT f.pose)" in SQL69 and "INTO v_fotos" in SQL69)
check("cancela en vez de publicar",
      "SET estado = 'cancelado', motivo = 'ya subió la revisión completa'" in SQL69)
check("solo toca los pedidos de revisión, no las respuestas",
      "r.dedupe_key LIKE 'dom-%' OR r.dedupe_key LIKE 'rec-%'" in SQL69,
      "si aplicara a todo, cancelaría respuestas de la IA que no piden nada")

print("\n7. Mandar exige --correr: elegir el modo no alcanza")
FUENTE = (RAIZ / "pump-centinela" / "recordatorios.py").read_text()
check("--correr es bandera válida", '"--correr"' in FUENTE)
check("el modo cae a dry sin --correr",
      'MODO = _ELEGIDO if (_CORRER or _ELEGIDO in ("dry", "drenar")) else "dry"' in FUENTE,
      "sin esto, --recordar solo vuelve a mandarle a los 62")
RONDA = (RAIZ / "pump-centinela" / "ronda.sh").read_text()
# Se miran las lineas que EJECUTAN, no el archivo entero: el comentario de
# arriba tambien nombra --correr y contarlo daba un falso negativo.
_execs = [l for l in RONDA.splitlines() if l.strip().startswith("7)") or l.strip().startswith("2|4)")]
check("ronda.sh pasa --correr en los dos horarios que mandan",
      len(_execs) == 2 and all("--correr" in l for l in _execs),
      "si falta, la ronda deja de salir EN SILENCIO, que es peor que el bug original\n"
      f"      lineas: {_execs}")

print()
if fallas:
    print(f"✗ {fallas} fallo(s): se le puede estar pidiendo la revisión a quien ya la mandó\n")
    sys.exit(1)
print("✓ nadie que ya subió recibe recordatorios\n")
