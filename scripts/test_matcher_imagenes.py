#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""test_matcher_imagenes.py — que la foto sea la del ejercicio, no la de otro

POR QUE EXISTE
Mati abrió su propia app el 3-sep y "Extensión en polea con cuerda agarre neutro
(cabeza medial)" mostraba a alguien parado en un rack. La imagen asignada era
`Sled_Overhead_Triceps_Extension`: un TRINEO.

No era el único. Auditadas las rutinas ACTIVAS: 373 pares (nombre, imagen)
distintos, 34 indiscutiblemente mal.

    Abductores en máquina          -> Iliotibial_Tract-SMR       (un foam roller)
    Abductores en máquina sentado  -> IT_Band_and_Glute_Stretch  (un estiramiento)
    Curl femoral en máquina        -> Ball_Leg_Curl              (una pelota suiza)
    Crunch en máquina              -> Bosu_Ball_Cable_Crunch     (un bosu)
    Aperturas en pec deck          -> Bodyweight_Flyes           (sin máquina)

Y esto YA se había "arreglado" el 2-ago, subiendo la exigencia a que el match
fuera inequívoco. No alcanzó, porque el problema nunca fue cuánta ventaja saca
el primero: era CONTRA QUÉ se compara. La función puntuaba el nombre en español
contra el nombre en inglés (ruido) y contra `aliases_es`, que son etiquetas de
GRUPO MUSCULAR — así que todo el grupo empata y gana cualquiera.

La tabla tenía dos columnas que lo resuelven y que nadie miraba:
`primary_muscle` y `equipment`. Eso es la migración 070.

QUE FIJA ESTE TEST
Las cuatro reglas de la 070, sobre el texto de la migración. No corre contra la
base a propósito: `npm test` tiene que andar en la laptop sin credenciales.
La verificación contra datos reales se hizo aparte, ejercicio por ejercicio.

USO:  python3 scripts/test_matcher_imagenes.py
"""
import pathlib
import re
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
SQL = (RAIZ / "supabase/migrations/070_matcher_mira_musculo_y_equipo.sql").read_text(encoding="utf-8")

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


print("\n1. El matcher mira las columnas que existían y no usaba")
check("filtra por músculo", "c.primary_muscle = ANY(v_musculos)" in SQL,
      "sin esto, todo el grupo muscular empata y gana cualquiera")
check("el equipo pesa en el score", "k.equipment = ANY(v_equipos)" in SQL)
check("el equipo NO excluye",
      "no excluye" in SQL.lower() or "-0.20" in SQL,
      "un curl spider con barra Z ilustrando uno con mancuernas es el mismo gesto")

print("\n2. Nada de aparatos que no son el gesto")
for palabra in ("foam roll", "exercise ball", "stretch", "sled", "bosu"):
    check(f"excluye '{palabra}'", palabra in SQL.lower(),
          "un estiramiento nunca es la foto de un ejercicio de fuerza")
check("salvo que el nombre lo pida", "v_quiere_raro" in SQL,
      "si alguien programa movilidad de verdad, la foto tiene que poder salir")

print("\n3. Los dos bugs que aparecieron escribiéndolo")
# El nombre pone el músculo entre paréntesis — "(cabeza medial)", "(glúteo
# medio)" — y la versión vieja los borraba ANTES de leerlos.
i_musculo = SQL.index("v_musculos := CASE")
i_borra_parentesis = SQL.index(r"regexp_replace(v_norm, '\(.*?\)'")
check("lee el músculo ANTES de tirar los paréntesis",
      i_musculo < i_borra_parentesis,
      "ahí está el dato más útil del nombre y se estaba tirando sin mirarlo")

# "jalón AL PECHO": la palabra pecho dice adónde va la barra, no qué entrena.
i_espalda = SQL.index("'dorsal|espalda|jalon")
i_pecho = SQL.index("'pectoral|pecho|pec deck")
check("la espalda se evalúa antes que el pecho",
      i_espalda < i_pecho,
      "con el orden invertido, un jalón al pecho matchea con un press de pecho")

print("\n4. El desempate por especificidad")
# Los alias son etiquetas de grupo, así que dentro del grupo todos empatan.
# Sin este desempate, "Elevaciones laterales con mancuernas" ganaba con un
# "Dumbbell Lying One-Arm REAR Lateral Raise": acostado, a un brazo y de
# deltoides posterior. Las tres cosas de más.
for mod, porque in (("lying", "acostado"), ("one.?arm|single", "a un brazo"),
                    ("rear", "posterior"), ("incline", "inclinado")):
    check(f"penaliza '{mod}' no pedido", re.search(re.escape(mod), SQL) is not None, porque)

print("\n5. No se afloja la guarda de quien llama")
# El Cerebro vive en OTRO repo. Se prueban las ubicaciones conocidas y, si no
# está en este checkout (CI), se saltea en vez de fallar.
CANDIDATOS = [
    RAIZ.parent / "nutriplan" / "index.html",
    pathlib.Path.home() / "Desktop" / "nutriplan" / "index.html",
]
APP = next((c for c in CANDIDATOS if c.exists()), None)
if APP:
    txt = APP.read_text(encoding="utf-8", errors="ignore")
    check("sigue exigiendo match inequívoco",
          "top.score > seg.score + 0.01" in txt,
          "esa guarda es lo que convierte una duda en 'sin imagen' en vez de en una foto equivocada")
    check("sigue exigiendo score >= 0.5", "top.score >= 0.5" in txt)
    check("sin match no deja la imagen vieja", "ej.images = null" in txt,
          "mejor sin foto que con la del ejercicio equivocado: el cliente hace lo que ve")
else:
    print("  · (index.html del Cerebro no está en este checkout, salteo)")

print()
if fallas:
    print(f"✗ {fallas} fallo(s): las fotos pueden volver a ser las del ejercicio equivocado\n")
    sys.exit(1)
print("✓ el matcher mira músculo y equipo\n")
