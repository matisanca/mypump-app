#!/usr/bin/env python3
"""generar-vectores-cola-a.py — vectores de «Récords y logros» (wins.json) y de la lista previa a la videollamada
(lista_previa.json). Esta es la referencia: las reglas de iOS (MyPumpReglas), Android (core/reglas) y la web tienen que dar
exactamente lo que dice cada vector.

Uso:  python3 scripts/nativa/generar-vectores-cola-a.py [--check]

── Récords del día (al cerrar la sesión) ──
Por ejercicio del día: `anteriores` son las marcas de días anteriores (misma clave) y `hoy` las series de hoy confirmadas
y verosímiles. Una marca sirve si kg > 0, finito, y reps >= 1. Sin kg (`sin_kg`), sin historia suficiente (`suficiente`
false), sin marcas anteriores que sirvan o sin series de hoy que sirvan: no hay récord.
  mejor(marcas) = la de más kg; entre las de ese kg (tolerancia 1e-6), la de más reps.
  hoy.kg > antes.kg + tol              → record_kg,   delta = redondeo a 2 decimales de (hoy.kg − antes.kg)
  mismo kg y hoy.reps > antes.reps     → record_reps, delta = hoy.reps − antes.reps
A lo sumo un récord por ejercicio, en el orden del día, y como mucho 12.
"""
import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOL = 1e-6
TOPE = 12
HITOS = [7, 14, 21, 30, 60, 90, 120, 180, 365]


def num(x):
    """Como el número de JS pasado a texto: 60.0 → "60", 62.5 → "62.5"."""
    x = float(x)
    return str(int(x)) if x.is_integer() else repr(x)


def kilos(x):
    return num(x).replace(".", ",")


def sirve(m):
    kg, reps = m.get("kg"), m.get("reps")
    return isinstance(kg, (int, float)) and kg == kg and abs(kg) != float("inf") and kg > 0 and isinstance(reps, int) and reps >= 1


def mejor(marcas):
    kg = max(m["kg"] for m in marcas)
    reps = max(m["reps"] for m in marcas if abs(m["kg"] - kg) < TOL)
    return kg, reps


def records(ejercicios):
    salida = []
    for e in ejercicios:
        if e.get("sin_kg") or not e.get("suficiente", True):
            continue
        antes = [m for m in e["anteriores"] if sirve(m)]
        hoy = [m for m in e["hoy"] if sirve(m)]
        if not antes or not hoy:
            continue
        akg, areps = mejor(antes)
        kg, reps = mejor(hoy)
        if kg > akg + TOL:
            tipo, delta = "record_kg", round((kg - akg) * 100) / 100
            chip = f"+{kilos(delta)} kg"
        elif abs(kg - akg) < TOL and reps > areps:
            tipo, delta = "record_reps", reps - areps
            chip = f"+{delta} rep{'' if delta == 1 else 's'}"
        else:
            continue
        salida.append({"tipo": tipo, "clave": e["clave"], "ejercicio": e["nombre"], "kg": kg, "reps": reps,
                       "antes_kg": akg, "antes_reps": areps, "delta": delta,
                       "marca": f"{kilos(kg)} kg × {reps}", "chip": chip, "antes": f"Antes: {kilos(akg)} kg × {areps}"})
        if len(salida) == TOPE:
            break
    return salida


def titulo(n):
    return "Récord nuevo" if n == 1 else f"{n} récords hoy"


def subtitulo(n):
    return "Superaste tu mejor marca." if n == 1 else f"Superaste {n} de tus mejores marcas."


def con_permiso(n):
    return "Mati se va a enterar de este logro." if n == 1 else "Mati se va a enterar de estos logros."


def ej(clave, anteriores, hoy, nombre=None, **k):
    m = lambda l: [{"kg": a, "reps": b} for a, b in l]
    return dict({"clave": clave, "nombre": nombre or clave.capitalize(), "anteriores": m(anteriores), "hoy": m(hoy)}, **k)


CASOS_WINS = [
    ("más kg", [ej("remo con barra", [(55, 8), (52.5, 10)], [(57.5, 8), (57.5, 7)], "Remo con barra")]),
    ("mismo kg, más reps", [ej("press banca", [(60, 8), (60, 7)], [(60, 9), (60, 8)], "Press banca plano con barra")]),
    ("mismo kg, dos reps más", [ej("curl", [(12, 10)], [(12, 12)])]),
    ("menos kg con más reps no es récord", [ej("curl", [(12, 10)], [(10, 20)])]),
    ("igual que antes no es récord", [ej("curl", [(12, 10)], [(12, 10)])]),
    ("sin historia no es récord", [ej("curl", [], [(12, 10)])]),
    ("sin series hoy", [ej("curl", [(12, 10)], [])]),
    ("sin kg (peso corporal)", [ej("dominadas", [(5, 8)], [(10, 8)], sin_kg=True)]),
    ("historia cortada", [ej("curl", [(12, 10)], [(14, 10)], suficiente=False)]),
    ("las filas en 0 kg no cuentan", [ej("curl", [(0, 30), (12, 10)], [(0, 40), (12.5, 8)])]),
    ("solo filas en 0 antes: sin historia", [ej("curl", [(0, 30)], [(12.5, 8)])]),
    ("reps en 0 hoy no cuentan", [ej("curl", [(12, 10)], [(20, 0), (12, 11)])]),
    ("el mejor de hoy: más kg aunque con menos reps", [ej("sentadilla", [(80, 8)], [(80, 10), (85, 5)], "Sentadilla con barra")]),
    ("lo mejor de antes es el kg más alto con sus reps", [ej("prensa", [(150, 12), (160, 6), (160, 8)], [(160, 9)], "Prensa 45°")]),
    ("decimales: de 62,5 a 63,75", [ej("press", [(62.5, 8)], [(63.75, 6)])]),
    ("tolerancia: 0,1 + 0,2 contra 0,3", [ej("lateral", [(0.3, 12)], [(0.1 + 0.2, 13)])]),
    ("varios ejercicios, en el orden del día", [
        ej("remo con barra", [(55, 8)], [(57.5, 8)], "Remo con barra"),
        ej("jalon", [(50, 8)], [(50, 8)], "Jalón al pecho prono"),
        ej("pullover", [(25, 10)], [(25, 11)], "Pullover en polea"),
        ej("curl", [(27.5, 10)], [(30, 8)], "Curl con barra Z")]),
    ("tope de 12", [ej(f"ejercicio {i}", [(10, 10)], [(12, 10)]) for i in range(14)]),
]

# ── Lista previa ──
# Lo que devuelve `mypump_lista_previa` → lo que se muestra. Solo con ok y activa en true. Un ítem vale si es un objeto con
# una clave conocida y un estado conocido; una clave repetida, la primera. `opcional` solo si es true. `faltan` solo en la
# guía, si falta, y si es un entero >= 1. Sin ítems válidos, no se muestra nada. El orden es el del servidor.
TITULOS = {
    "guia": "Mirar los videos de tu guía",
    "dudas": "Dejarle tus dudas a Mati",
    "formulario": "Responder las preguntas de Mati",
    "fotos": "Subir tus fotos de inicio",
    "estudios": "Subir tus estudios",
    "contrato": "Firmar el contrato",
}
# guia = la guía de videos; fotos = las fotos de Revisión. Sin destino, la fila no es un botón.
DESTINOS = {"guia": "guia", "dudas": "guia", "fotos": "fotos"}
TEXTOS_LISTA = {
    "titulo": "Antes de la videollamada",
    "todo_listo": "Ya tenés todo listo",
    "consejo": "Ese día buscá un lugar tranquilo y con buena conexión.",
    "opcional": "Opcional",
    "hecho": "Hecho",
    "falta": "Falta",
}


def lista(j):
    if not isinstance(j, dict) or j.get("ok") is not True or j.get("activa") is not True or not isinstance(j.get("items"), list):
        return None
    items, vistas = [], set()
    for it in j["items"]:
        if not isinstance(it, dict):
            continue
        clave, estado = it.get("clave"), it.get("estado")
        if clave not in TITULOS or estado not in ("hecho", "falta") or clave in vistas:
            continue
        vistas.add(clave)
        hecho, opcional = estado == "hecho", it.get("opcional") is True
        faltan = it.get("faltan")
        detalle = None
        if not hecho and clave == "guia" and isinstance(faltan, (int, float)) and not isinstance(faltan, bool) and float(faltan).is_integer() and faltan >= 1:
            n = int(faltan)
            detalle = "Te falta 1 video" if n == 1 else f"Te faltan {n} videos"
        elif not hecho and opcional:
            detalle = TEXTOS_LISTA["opcional"]
        accesible = ", ".join(x for x in [TITULOS[clave], TEXTOS_LISTA["hecho"] if hecho else (detalle if opcional else TEXTOS_LISTA["falta"]),
                                          detalle if (detalle and not opcional) else None] if x)
        # A dónde lleva tocar un punto que falta (un toque, directo al lugar). Lo hecho no se toca.
        destino = None if hecho else DESTINOS.get(clave)
        items.append({"clave": clave, "titulo": TITULOS[clave], "hecho": hecho, "opcional": opcional, "detalle": detalle,
                      "destino": destino, "accesible": accesible})
    if not items:
        return None
    obligatorios = [i for i in items if not i["opcional"]]
    hechos = sum(1 for i in obligatorios if i["hecho"])
    if not obligatorios:
        resumen = None
    elif hechos == len(obligatorios):
        resumen = TEXTOS_LISTA["todo_listo"]
    else:
        resumen = f"Llevás {hechos} de {len(obligatorios)}"
    return {"items": items, "resumen": resumen, "todo_listo": bool(obligatorios) and hechos == len(obligatorios)}


def it(clave, estado, **k):
    return dict({"clave": clave, "estado": estado}, **k)


OK = lambda items, **k: dict({"ok": True, "activa": True, "items": items}, **k)
CASOS_LISTA = [
    ("la de la demo", OK([it("guia", "falta", faltan=2), it("dudas", "falta", opcional=True), it("formulario", "hecho"), it("fotos", "falta")])),
    ("todo listo, con la duda opcional sin hacer", OK([it("guia", "hecho", faltan=0), it("dudas", "falta", opcional=True), it("fotos", "hecho")])),
    ("falta un video", OK([it("guia", "falta", faltan=1), it("fotos", "hecho")])),
    ("faltan sin número", OK([it("guia", "falta"), it("fotos", "falta")])),
    ("faltan con decimales o en texto no se muestra", OK([it("guia", "falta", faltan=2.5), it("fotos", "falta", faltan="3")])),
    ("faltan solo vale en la guía", OK([it("fotos", "falta", faltan=2)])),
    ("claves del futuro que la app ya conoce", OK([it("estudios", "falta"), it("contrato", "hecho")])),
    ("clave desconocida se descarta", OK([it("pago", "falta"), it("fotos", "hecho")])),
    ("estado desconocido se descarta", OK([it("guia", "en_curso"), it("fotos", "falta")])),
    ("clave repetida: la primera", OK([it("fotos", "falta"), it("fotos", "hecho")])),
    ("opcional que no es true no es opcional", OK([it("dudas", "falta", opcional="si"), it("fotos", "hecho")])),
    ("solo opcionales: sin resumen", OK([it("dudas", "hecho", opcional=True)])),
    ("ítems que no son objetos", OK(["guia", None, 3, it("fotos", "falta")])),
    ("sin ítems válidos: nada", OK([it("pago", "falta")])),
    ("lista vacía: nada", OK([])),
    ("inactiva: nada", {"ok": True, "activa": False, "items": [it("fotos", "falta")]}),
    ("sin activa: nada", {"ok": True, "items": [it("fotos", "falta")]}),
    ("ok en false: nada", {"ok": False, "motivo": "token"}),
    ("items que no es lista: nada", {"ok": True, "activa": True, "items": {"clave": "fotos"}}),
    ("no es un objeto: nada", [1, 2]),
]


def armar():
    wins = {
        "fuente": "scripts/nativa/generar-vectores-cola-a.py (referencia en Python)",
        "tope": TOPE,
        "records": [{"nombre": n, "ejercicios": e, "salida": records(e)} for n, e in CASOS_WINS],
        "textos": [{"n": n, "titulo": titulo(n), "subtitulo": subtitulo(n), "con_permiso": con_permiso(n)} for n in (1, 2, 3, 12)],
        "fijos": {
            "contarle": "Contarle a Mati",
            "seguir": "Seguir",
            "permiso_titulo": "¿Compartir tus logros con Mati?",
            "permiso_cuerpo": [
                "Cuando logres un récord o una racha de pasos, Mati lo va a ver y lo puede compartir con el equipo de Pump Team.",
                "Se comparte tu nombre y el logro: el ejercicio y la marca, o los días de tu racha. Nunca tus fotos, tu peso ni otros datos de salud.",
                "Lo podés desactivar cuando quieras en Mis datos. Lo ya compartido no se puede borrar.",
            ],
            "permiso_si": "Sí, compartir",
            "permiso_no": "Ahora no",
            "ajuste_seccion": "Logros",
            "ajuste_interruptor": "Compartir mis logros con Mati",
            "ajuste_pie": "Mati ve tus récords y tus rachas de pasos, y los puede compartir con el equipo de Pump Team. Nunca tus fotos, tu peso ni otros datos de salud.",
            "desactivado": "Listo, no se comparte nada más.",
            "sin_red": "No se pudo guardar. Probá de nuevo cuando tengas conexión.",
            "demo": "En la demo no se envía nada.",
            "racha_con_permiso": "Mati se va a enterar de esta racha.",
        },
        "permiso_version": 1,
        "hitos_racha": HITOS,
        "racha": [{"dias": n, "es_hito": n in HITOS} for n in (0, 1, 2, 6, 7, 8, 14, 21, 29, 30, 31, 60, 90, 120, 180, 365, 366, 400)],
    }
    lp = {
        "fuente": "scripts/nativa/generar-vectores-cola-a.py (referencia en Python)",
        "textos": TEXTOS_LISTA,
        "titulos": TITULOS,
        "destinos": DESTINOS,
        "casos": [{"nombre": n, "respuesta": j, "salida": lista(j)} for n, j in CASOS_LISTA],
    }
    return {"wins.json": wins, "lista_previa.json": lp}


def main():
    for nombre, datos in armar().items():
        ruta = os.path.join(RAIZ, "apps/shared/vectores", nombre)
        texto = json.dumps(datos, ensure_ascii=False, indent=1) + "\n"
        if "--check" in sys.argv:
            if open(ruta, encoding="utf-8").read() != texto:
                raise SystemExit(f"{nombre} no coincide con el generador")
            print(f"{nombre} coincide")
        else:
            open(ruta, "w", encoding="utf-8").write(texto)
            print(f"escrito {nombre} ({len(texto)} bytes)")


if __name__ == "__main__":
    main()
