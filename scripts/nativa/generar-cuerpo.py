#!/usr/bin/env python3
"""generar-cuerpo.py — la figura del cuerpo de «Me duele», dibujo propio hecho de cápsulas, elipses y cajas.

Una sola definición para las tres plataformas: escribe `apps/shared/fixtures/feedback/cuerpo.json` (la web lo copia tal cual)
y las tablas de Swift y Kotlin. Lienzo de 200 × 420. En la vista de frente la derecha del alumno queda a la izquierda de
quien mira; en la de espalda, a la derecha. Uso: python3 scripts/nativa/generar-cuerpo.py
"""
import json, os

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANCHO, ALTO = 200, 420

def espejo(f):
    k, a = f
    if k == "capsula": return (k, [ANCHO - a[0], a[1], ANCHO - a[2], a[3], a[4]])
    if k == "elipse": return (k, [ANCHO - a[0], a[1], a[2], a[3]])
    return (k, [ANCHO - a[0] - a[2], a[1], a[2], a[3], a[4]])

# El lado de quien mira a la izquierda (x < 100). Se espeja para el otro.
PARES = [
    ("hombro", ("elipse", [64, 84, 15, 14])),
    ("brazo", ("capsula", [57, 106, 52, 138, 10.5])),
    ("codo", ("elipse", [49, 156, 10, 10])),
    ("antebrazo", ("capsula", [46, 174, 41, 202, 8.5])),
    ("muneca", ("elipse", [38, 222, 9, 12])),
    ("rodilla", ("elipse", [83, 290, 13, 13])),
    ("pantorrilla", ("capsula", [83, 314, 84, 358, 10.5])),
    ("tobillo", ("elipse", [84, 388, 10, 13])),
]
FRENTE_CENTRO = [("cuello", ("caja", [90, 52, 20, 16, 7])), ("pecho", ("caja", [76, 70, 48, 40, 14])), ("abdomen", ("caja", [79, 112, 42, 50, 12]))]
FRENTE_PARES = [("cadera", ("elipse", [86, 180, 14, 15])), ("muslo_frente", ("capsula", [84, 208, 83, 262, 14.5]))]
ESPALDA_CENTRO = [("cuello", ("caja", [90, 52, 20, 16, 7])), ("espalda_alta", ("caja", [76, 70, 48, 46, 14])), ("espalda_baja", ("caja", [79, 118, 42, 44, 12]))]
ESPALDA_PARES = [("gluteo", ("elipse", [86, 180, 14, 15])), ("muslo_atras", ("capsula", [84, 208, 83, 262, 14.5]))]
CABEZA = ("elipse", [100, 27, 17, 21])

def vista(centro, pares, izquierda_es):
    otro = "izquierdo" if izquierda_es == "derecho" else "derecho"
    out = [{"zona": None, "lado": None, "forma": CABEZA[0], "a": CABEZA[1]}]
    for z, f in centro: out.append({"zona": z, "lado": "centro", "forma": f[0], "a": f[1]})
    for z, f in PARES[:1] + pares + PARES[1:]:
        e = espejo(f)
        out.append({"zona": z, "lado": izquierda_es, "forma": f[0], "a": f[1]})
        out.append({"zona": z, "lado": otro, "forma": e[0], "a": e[1]})
    return out

figura = {"ancho": ANCHO, "alto": ALTO, "vistas": {"frente": vista(FRENTE_CENTRO, FRENTE_PARES, "derecho"), "espalda": vista(ESPALDA_CENTRO, ESPALDA_PARES, "izquierdo")}}

def num(x): return str(int(x)) if float(x).is_integer() else str(x)

def swift():
    l = ["// Generado por scripts/nativa/generar-cuerpo.py. No editar a mano: cambiar el script y volver a correrlo.", "",
         "extension FiguraCuerpo {"]
    for v, piezas in figura["vistas"].items():
        l.append(f"    static let {v}: [Pieza] = [")
        for p in piezas:
            z = f'"{p["zona"]}"' if p["zona"] else "nil"; la = f'"{p["lado"]}"' if p["lado"] else "nil"
            l.append(f'        Pieza(zona: {z}, lado: {la}, forma: .{p["forma"]}, a: [{", ".join(num(x) for x in p["a"])}]),')
        l.append("    ]")
    l.append("}"); return "\n".join(l) + "\n"

def kotlin():
    l = ["// Generado por scripts/nativa/generar-cuerpo.py. No editar a mano: cambiar el script y volver a correrlo.",
         "package com.pumpteam.mypump.reglas", "", "internal object FiguraCuerpoDatos {"]
    for v, piezas in figura["vistas"].items():
        l.append(f"    val {v}: List<FiguraCuerpo.Pieza> = listOf(")
        for p in piezas:
            z = f'"{p["zona"]}"' if p["zona"] else "null"; la = f'"{p["lado"]}"' if p["lado"] else "null"
            l.append(f'        FiguraCuerpo.Pieza({z}, {la}, FiguraCuerpo.Forma.{p["forma"].upper()}, doubleArrayOf({", ".join(str(float(x)) for x in p["a"])})),')
        l.append("    )")
    l.append("}"); return "\n".join(l) + "\n"

def escribir(rel, texto):
    ruta = os.path.join(RAIZ, rel)
    if os.path.isdir(os.path.dirname(ruta)):
        open(ruta, "w", encoding="utf-8").write(texto); print("escrito", rel)

escribir("apps/shared/fixtures/feedback/cuerpo.json", json.dumps(figura, ensure_ascii=False, indent=1) + "\n")
escribir("apps/ios/MyPumpKit/Sources/MyPumpReglas/FiguraCuerpoDatos.swift", swift())
escribir("apps/android/core/reglas/src/main/kotlin/com/pumpteam/mypump/reglas/FiguraCuerpoDatos.kt", kotlin())
