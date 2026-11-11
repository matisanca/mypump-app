#!/usr/bin/env python3
"""Referencia de «sin dosis» (Novedades de tu plan) y generador de apps/shared/fixtures/novedades/sin_dosis.json.
Las tres plataformas implementan esta misma regla; el archivo generado es la prueba compartida."""
import json, sys
UNIDADES = set("mg mcg ug µg g gr grs kg ml l ui iu % cap caps capsula capsulas comprimido comprimidos comp tableta tabletas tab tabs pastilla pastillas gota gotas scoop scoops cucharada cucharadas cucharadita cucharaditas sobre sobres unidad unidades".split())
TIEMPOS = set("dia toma noche semana comida mañana".split())
ENLACES = {"por", "x", "al", "/", "c/"}
SUELTOS = {"x", "-", "–", "—", ":", "·"}
MAPA = dict(zip("áàäâéèëêíìïîóòöôúùüû", "aaaaeeeeiiiioooouuuu"))
NUM = "0123456789.,"

def limpio(s): return " ".join(x for x in s.replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ") if x)
def clave(s): return "".join(MAPA.get(c, c) for c in limpio(s).lower())
def norm(t):
    n = clave(t)
    while n and n[0] in "([": n = n[1:]
    while n and n[-1] in ").,;:]": n = n[:-1]
    return n
def partir(n):
    """(número, resto). El número: dígitos con . o , y a lo sumo un rango «3-5» o «3/5»."""
    i = 0
    if not n or not n[0].isdigit() or not n[0].isascii(): return "", n
    while i < len(n) and n[i] in NUM: i += 1
    if i + 1 < len(n) and n[i] in "-/" and n[i + 1] in "0123456789":
        i += 1
        while i < len(n) and n[i] in NUM: i += 1
    return n[:i], n[i:]
def unidad(r):
    r = r.split("/")[0]
    while r.endswith("."): r = r[:-1]
    return r in UNIDADES
def es_numero(n):
    p, r = partir(n); return p != "" and r == ""

def sin_dosis(nombre):
    ts = limpio(nombre).split(" ") if limpio(nombre) else []
    out, i, cerrar = [], 0, 0
    while i < len(ts):
        t = ts[i]; n = norm(t); p, r = partir(n); quita = 0
        if p:
            if r and (unidad(r) or r == "x"): quita = 1
            elif not r and i + 1 < len(ts) and norm(ts[i + 1]) and unidad(norm(ts[i + 1])): quita = 2
        elif len(n) > 1 and n[0] == "x" and all(c in "0123456789" for c in n[1:]): quita = 1
        if not quita:
            if cerrar and t.endswith(")"): t = t[:-1]; cerrar -= 1
            if t: out.append(t)
            i += 1; continue
        ido = ts[i:i + quita]; i += quita
        if i + 1 < len(ts) and norm(ts[i]) in ENLACES and norm(ts[i + 1]) in TIEMPOS: ido += ts[i:i + 2]; i += 2
        elif i < len(ts) and norm(ts[i]).startswith("/") and norm(ts[i])[1:] in TIEMPOS: ido += ts[i:i + 1]; i += 1
        elif i + 1 < len(ts) and norm(ts[i]) == "x" and es_numero(norm(ts[i + 1])): ido += ts[i:i + 2]; i += 2
        if len(out) >= 2 and norm(out[-1]) == "a" and es_numero(norm(out[-2])): ido = out[-2:] + ido; del out[-2:]
        if out and out[-1] in SUELTOS: out.pop()
        a = sum(x.count("(") for x in ido); c = sum(x.count(")") for x in ido)
        if a > c: cerrar += a - c
        elif c > a and out and " ".join(out).count("(") > " ".join(out).count(")"): out[-1] += ")"
    while out and all(ch in "-–—:,·+/x" for ch in out[-1]): out.pop()
    if out:
        while out[-1] and out[-1][-1] in ",:;": out[-1] = out[-1][:-1]
        if not out[-1]: out.pop()
    return " ".join(out).replace("()", "").strip()

NOMBRES = ["Creatina monohidrato", "Creatina 5 g", "Creatina monohidrato 5g", "Creatina 5g/día", "Vitamina C (2 g)", "Vitamina D 5.000 UI del almuerzo",
  "Vitamina D3 2000UI", "Vitamina D3 + K2 (MK-7)", "Omega 3", "Omega-3", "Omega 3 (EPA + DHA)", "Omega 3 1 g", "Magnesio 400 mg x día", "Magnesio (400 mg antes de dormir)",
  "Magnesio (la combinación de 4 que ya tomás)", "Ashwagandha KSM-66", "Ashwagandha (KSM-66 600 mg)", "Ashwagandha KSM-66 600 mg", "Cafeína 200 mg (pre)", "Cafeína - 200 mg",
  "Coenzima Q10", "Complejo B y vitamina B12", "Melatonina / 5-HTP", "Melatonina 3-5 mg", "Melatonina 3 a 5 mg", "Liv-52", "C4 (pre-entreno)", "Magnesio Complex 7",
  "Citrulina 6 g por toma", "Zinc 25 mg, con la cena", "Multivitamínico x2", "Multivitamínico 2x", "Proteína 1 scoop", "Vitamina B12 1000 mcg", "Óxido nítrico (el de las 7)",
  "  Creatina   5   G  ", "CREATINA 5 GR.", "Probiótico 2 cápsulas", "Glicina 3 g al día", "Colágeno 10 g/toma con vitamina C", "5 g", "Electrolitos 1 sobre", "Hierro 1 comprimido por día",
  "Vitamina D3 + K2 de todos los días", "Pre entreno V8", "NAC 600mg x 2", "Taurina: 2 g", ""]

if __name__ == "__main__":
    casos = [{"entrada": n, "salida": sin_dosis(n)} for n in NOMBRES]
    if len(sys.argv) > 1:
        json.dump(casos, open(sys.argv[1], "w", encoding="utf-8"), ensure_ascii=False, indent=1); open(sys.argv[1], "a").write("\n")
    for c in casos: print(f"{c['entrada']!r:48} → {c['salida']!r}")
