#!/usr/bin/env python3
"""generar-demo-historial.py — arma apps/shared/demo/historial.json: el historial INVENTADO de la demo sin cuenta.

La demo ("Ver demo", la que usa la revisión de las tiendas) muestra ocho semanas de un alumno que no existe: series por
ejercicio de la rutina de demo, peso, pasos, el chat con Mati, devoluciones y metas. Nada sale de una cuenta real y nada
viaja por la red: el archivo se empaqueta con cada app (y la web lo copia a public/demo/historial.json).

Los días son relativos a hoy (0 = hoy, -1 = ayer): cada app los convierte a fechas al cargar, así el historial nunca
queda viejo. Es determinista (sin azar): correrlo dos veces da el mismo archivo.

Uso:  python3 scripts/nativa/generar-demo-historial.py          (escribe el archivo)
      python3 scripts/nativa/generar-demo-historial.py --check  (falla si el archivo no coincide)
"""
import json
import math
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SALIDA = os.path.join(RAIZ, "apps/shared/demo/historial.json")
SEMANAS = 8

# Con qué arranca cada ejercicio de la rutina de demo y de a cuánto sube. Los días de la rutina van cada 7 días:
# el día 1 cae en -5, -12…; el día 2 en -3, -10…; el día 3 en -1, -8… (hoy no entrenó todavía).
ARRANQUE = {
    "Remo con barra": (50, 2.5), "Jalón al pecho prono": (45, 2.5), "Pullover en polea": (20, 2.5),
    "Curl con barra Z": (22.5, 2.5), "Curl martillo con mancuerna": (10, 1),
    "Press banca plano con barra": (60, 2.5), "Press inclinado con mancuernas": (20, 2),
    "Press militar con barra": (35, 2.5), "Extensión tríceps en polea": (22.5, 2.5),
    "Sentadilla con barra": (80, 2.5), "Prensa 45°": (140, 10),
}
ULTIMO_DIA = {0: -5, 1: -3, 2: -1}
HORA = {0: (18, 40), 1: (19, 5), 2: (18, 20)}


def rango(reps):
    n = [int(x) for x in re.findall(r"\d+", str(reps))]
    if not n:
        return 8, 10
    return (n[0], n[1]) if len(n) > 1 else (n[0], n[0] + 2)


def num(x):
    return int(x) if float(x).is_integer() else round(float(x), 2)


def entreno():
    rutina = json.load(open(os.path.join(RAIZ, "apps/shared/demo/rutina.json"), encoding="utf-8"))
    salida = []
    for d, dia in enumerate(rutina["dias"]):
        orden = 0
        for bloque in dia["bloques"]:
            for ej in bloque["ejercicios"]:
                if ej.get("tipo") == "calentamiento":
                    continue
                if ej["nombre"] not in ARRANQUE:
                    raise SystemExit(f"falta el arranque de «{ej['nombre']}»: la rutina de demo cambió")
                kg, paso = ARRANQUE[ej["nombre"]]
                bajo, alto = rango(ej.get("reps"))
                series = int(ej.get("series") or 3)
                tope = bajo          # las reps de la primera serie
                sesiones = []
                for s in range(SEMANAS):
                    # Una semana floja por ejercicio (distinta en cada uno): repite lo de la anterior.
                    floja = s == 3 + (orden + d) % 3
                    if s > 0 and not floja:
                        if tope >= alto:
                            kg, tope = kg + paso, bajo
                        else:
                            tope += 1
                    h, m = HORA[d]
                    minuto = m + orden * 11
                    filas = []
                    for i in range(series):
                        # La fatiga: de la tercera serie en adelante sale una repetición menos.
                        reps = max(bajo - 1, tope - (1 if i >= 2 else 0) - (1 if floja and i == series - 1 else 0))
                        filas.append({"kg": num(kg), "reps": reps})
                    sesiones.append({"dia": ULTIMO_DIA[d] - 7 * (SEMANAS - 1 - s),
                                     "hora": f"{h + (minuto // 60):02d}:{minuto % 60:02d}", "series": filas})
                salida.append({"ejercicio_id": ej["id"], "nombre": ej["nombre"], "sesiones": sesiones})
                orden += 1
    return salida


def peso():
    filas = []
    for dia in range(-56, 0):
        if dia % 7 not in (0, 2, 4, 5):
            continue
        semanas = (dia + 56) / 7
        kg = 84.6 - 0.42 * semanas + 0.35 * math.sin(dia * 1.7) + 0.15 * math.cos(dia * 0.9)
        filas.append({"dia": dia, "kg": round(kg, 1)})
    return filas


def pasos():
    filas = []
    for dia in range(-34, 0):
        base = 9300 + 1500 * math.sin(dia * 0.83) + 900 * math.cos(dia * 2.1)
        if dia in (-23, -16, -9, -6):   # los días flojos
            base = 6400 + 300 * math.sin(dia)
        if dia >= -5:                   # los últimos cinco, todos arriba de la meta: una racha
            base = max(base, 9150 + 40 * (dia + 6) * (dia + 6))
        filas.append({"dia": dia, "pasos": int(round(base / 10) * 10)})
    filas.append({"dia": 0, "pasos": 6240})
    return filas


def coma(x):
    return str(num(x)).replace(".", ",")


def chat(ent):
    def sesion(nombre, dia):
        e = next(x for x in ent if x["nombre"] == nombre)
        return next(s for s in e["sesiones"] if s["dia"] == dia)["series"][0]
    remo, sent = sesion("Remo con barra", -12), sesion("Sentadilla con barra", -1)
    m = [
        (-12, "10:15", "coach", "Buenas, cómo arrancaste la semana?"),
        (-11, "13:40", "cliente", f"Bien! Ayer hice el remo con {coma(remo['kg'])} kg y salieron las {remo['reps']}"),
        (-11, "13:52", "coach", "Excelente, ese es el camino. La próxima subí 2,5 kg"),
        (-8, "19:05", "cliente", "Una duda, el fin de semana tengo un asado. Cómo hago con la cena?"),
        (-8, "19:30", "coach", "Tranquilo, comé la carne con ensalada y dejá el pan y el postre para otra vez. Al otro día seguís normal con el plan"),
        (-8, "19:33", "cliente", "Genial, gracias"),
        (-3, "09:12", "coach", "Vi que venís llegando a la meta de pasos todos los días, muy bien"),
        (-3, "09:40", "cliente", "Sí, me ayudó salir a caminar después de almorzar"),
        (-1, "20:10", "cliente", f"Hoy sentadilla con {coma(sent['kg'])} kg por {sent['reps']}, nunca había hecho tanto"),
        (-1, "20:25", "coach", "Enorme. Seguí así, todo al fallo y cuidando la técnica"),
    ]
    return [{"dia": d, "hora": h, "autor": a, "texto": t} for d, h, a, t in m]


DEVOLUCIONES = [
    (1, "Muy buena semana. Entrenaste los tres días y subiste la sentadilla.\n"
        "Llegaste a la meta de pasos cinco días seguidos, eso se nota en la balanza.\n"
        "Esta semana quiero que cuides el descanso, acostate siempre a la misma hora."),
    (2, "Vas bien con el peso, bajaste medio kilo y la fuerza se mantiene.\n"
        "El press de banca quedó igual que la semana pasada, es normal.\n"
        "Si el jueves te sentís con energía, buscá una repetición más en la primera serie."),
    (3, "Buen arranque. Cumpliste con la dieta casi toda la semana.\n"
        "El fin de semana se te complicó, la próxima organizá las comidas el viernes.\n"
        "Seguí registrando el peso a la mañana, me sirve para ver la tendencia."),
]


def armar():
    ent = entreno()
    return {
        "version": 1,
        "nota": "Datos inventados para la demo sin cuenta. Los días son relativos a hoy (0 = hoy, -1 = ayer). "
                "Lo genera scripts/nativa/generar-demo-historial.py: no editar a mano.",
        "entreno": ent,
        "peso": peso(),
        "pasos": pasos(),
        "metas": {"meta_pasos_dia": 9000, "ritmo_peso_kg_semana": -0.4},
        "chat": chat(ent),
        "devoluciones": [{"semanas_atras": s, "texto": t} for s, t in DEVOLUCIONES],
        "lista_previa": {"ok": True, "activa": True, "items": [
            {"clave": "guia", "estado": "falta", "faltan": 2},
            {"clave": "dudas", "estado": "falta", "opcional": True},
            {"clave": "formulario", "estado": "hecho"},
            {"clave": "fotos", "estado": "falta"},
        ]},
    }


def main():
    texto = json.dumps(armar(), ensure_ascii=False, indent=1) + "\n"
    if "--check" in sys.argv:
        if open(SALIDA, encoding="utf-8").read() != texto:
            raise SystemExit("apps/shared/demo/historial.json no coincide con el generador")
        print("historial.json coincide")
        return
    open(SALIDA, "w", encoding="utf-8").write(texto)
    print(f"escrito {SALIDA} ({len(texto)} bytes)")


if __name__ == "__main__":
    main()
