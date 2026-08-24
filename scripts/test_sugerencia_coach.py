#!/usr/bin/env python3
"""test_sugerencia_coach.py — la IA propone, Mati dispone. Y nunca al revés.

POR QUE EXISTE
Hasta el 24-ago-2026 la bandeja del Cerebro te dejaba el composer VACIO justo
en los casos que mas trabajo dan: cuando la IA clasificaba `derivar` o
`urgente`, procesar() tiraba la respuesta a proposito y Mati escribia de cero.

Ahora la IA redacta una `sugerencia` para esos casos. Y como esa sugerencia NO
pasa por el validador de salud —a proposito: la revisa una persona antes de
salir— la garantia de que nunca se envie sola deja de ser una preferencia y
pasa a ser lo unico que separa un borrador de un mensaje a un cliente.

Este archivo prueba las dos mitades:
  1. que la sugerencia EXISTA para derivar/urgente (si no, no sirve de nada)
  2. que `respuesta` siga vacia en esas clases (si no, el automatico la manda)
"""
import ast
import io
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))
import chat_worker as W  # noqa: E402

fallas = 0


def check(nombre, ok, detalle=""):
    global fallas
    print(f"  {'✓' if ok else '✗'} {nombre}")
    if not ok:
        fallas += 1
        if detalle:
            print(f"      {detalle}")


def fila(msg="hola"):
    return {"cliente_id": "c1", "mensaje_id": "m1", "nombre": "Felipe Velasco",
            "mensaje": msg, "contexto": [], "ya_subio": True}


print("\n1. Derivar: propone algo Y no manda nada solo")
W.llamar_codex = lambda p: ({
    "clase": "derivar",
    "respuesta": "felipe, eso lo charlamos por whatsapp",
    "sugerencia": "felipe, me quedo con lo del cambio de horario. contame a que "
                  "hora te queda entrenar ahora y lo acomodamos",
    "motivo": "cambio de horario",
}, None)
r = W.procesar(fila("cambie de horario y me cuesta la comida"))
check("hay sugerencia", bool(r.get("sugerencia")), f"quedo {r.get('sugerencia')!r}")
check("la sugerencia menciona lo que contó", "horario" in (r.get("sugerencia") or ""))
check("respuesta queda en None", r["respuesta"] is None,
      f"peligro: quedo {r['respuesta']!r} y el automatico la mandaria sola")
check("la clase sigue siendo derivar", r["clase"] == "derivar")

print("\n2. Urgente: tampoco contesta solo, pero te deja el borrador")
W.llamar_codex = lambda p: ({
    "clase": "urgente", "respuesta": None,
    "sugerencia": "felipe, pará el entrenamiento y andá a que te vean hoy mismo. "
                  "avisame apenas sepas algo",
    "motivo": "dolor de pecho",
}, None)
r = W.procesar(fila("me duele el pecho entrenando"))
check("hay sugerencia", bool(r.get("sugerencia")))
check("respuesta queda en None", r["respuesta"] is None)
check("la clase sigue siendo urgente", r["clase"] == "urgente")

print("\n3. Simple: sigue como antes, sin sugerencia")
W.llamar_codex = lambda p: (
    {"clase": "simple", "respuesta": "de nada felipe", "motivo": "agradece"}, None)
r = W.procesar(fila("gracias!"))
check("respuesta presente", r["respuesta"] == "de nada felipe")
check("sugerencia vacia", r.get("sugerencia") is None,
      "en simple la sugerencia no tiene sentido: ya contesta solo")

print("\n4. Si el modelo se rebela y manda respuesta en derivar, se ignora")
W.llamar_codex = lambda p: ({
    "clase": "derivar",
    "respuesta": "felipe bajale a 3 series y sumale 200 kcal",
    "sugerencia": None, "motivo": "x",
}, None)
r = W.procesar(fila("que hago?"))
check("respuesta descartada", r["respuesta"] is None,
      "el modelo metio una indicacion de entrenamiento y casi sale sola")

print("\n5. Codex caído: degrada a derivar, sin inventar sugerencia")
W.llamar_codex = lambda p: (None, "timeout")
r = W.procesar(fila("hola"))
check("clase derivar", r["clase"] == "derivar")
check("sin respuesta", r["respuesta"] is None)
check("sin sugerencia", r.get("sugerencia") is None,
      "si la IA no pudo pensar, no puede proponer")

print("\n6. La clave viaja a la RPC (si no, se pierde en el camino)")
FUENTE = (RAIZ / "pump-centinela" / "chat_worker.py").read_text()
check("main() manda p_sugerencia", '"p_sugerencia": r.get("sugerencia")' in FUENTE,
      "el worker la calcula pero no la guarda")

print("\n7. El prompt le prohíbe inventar números del plan")
check("dice que no ve la rutina ni la dieta",
      "no ves su rutina" in FUENTE and "adivinando" in FUENTE,
      "sin esto el modelo escribe 'bajale a 3 series' y Mati lo borra igual")

print("\n8. Ningún statement después de un return (la familia del bug de ayer)")
def _muertas(arbol):
    malas = []
    for nodo in ast.walk(arbol):
        for campo in ("body", "orelse", "finalbody"):
            b = getattr(nodo, campo, None)
            if not isinstance(b, list):
                continue
            for i, st in enumerate(b[:-1]):
                if isinstance(st, (ast.Return, ast.Raise, ast.Continue, ast.Break)):
                    malas.append((st.lineno, b[i + 1].lineno))
    return malas

muertas = _muertas(ast.parse(FUENTE))
check("no hay codigo inalcanzable", not muertas,
      ", ".join(f"linea {b} (return en {a})" for a, b in muertas))

print("\n9. La migración no deja funciones duplicadas ni caminos nuevos de envío")
SQL = (RAIZ / "supabase" / "migrations" / "064_borrador_sugerencia.sql").read_text()
check("dropea la firma vieja de guardar",
      "DROP FUNCTION IF EXISTS mypump_chat_borrador_guardar(text, uuid, text, text, text, text[], text)" in SQL,
      "sin el DROP quedan dos firmas y PostgREST tira PGRST203")
check("dropea pendientes antes de recrearla",
      "DROP FUNCTION IF EXISTS mypump_chat_borradores_pendientes()" in SQL,
      "CREATE OR REPLACE no puede cambiar el RETURNS TABLE")
check("trae el guardarrail de duplicadas", "PGRST203" in SQL)
# El unico lugar del SQL que INSERTA en mypump_comentarios tiene que ser el
# resolver, que exige p_enviar. Si aparece otro, hay un camino de envio nuevo.
check("solo el resolver publica al cliente",
      SQL.count("INSERT INTO mypump_comentarios") == 1,
      "apareció otro INSERT: alguien abrió un segundo camino al cliente")


print("\n10. La revisión de la semana llega al prompt")
REV = {"hay_check": True, "energia": 2, "descanso": 3, "hambre": 5,
       "adherencia": 2, "nota": "me cuesta la cena", "fotos": 3,
       "peso_kg": 69.0, "peso_previo": 70.2}
txt = W._revision_texto(REV)
check("dice que SI subió", txt.startswith("SI subio"), txt[:60])
check("traduce los 1-5 a palabras", "energía baja (2 de 5)" in txt, txt)
check("el hambre tiene su propia escala", "mucha hambre (5 de 5)" in txt, txt)
check("compara el peso con la semana previa", "bajó 1.2 kg" in txt, txt)
check("dice cuántas fotos", "las 3 fotos" in txt, txt)
check("incluye la nota textual", "me cuesta la cena" in txt, txt)

check("sin check devuelve None", W._revision_texto({"hay_check": False}) is None)
check("sin dato devuelve None", W._revision_texto(None) is None)

sin_peso = W._revision_texto({"hay_check": True, "energia": 4, "fotos": 0})
check("sin peso no inventa comparación", "kg" not in sin_peso, sin_peso)
check("cero fotos se dice", "sin fotos" in sin_peso, sin_peso)

fila_rev = {"nombre": "Nicolas Giovanetti", "contexto": [], "ya_subio": True,
            "revision": REV}
prompt = W.armar_prompt(fila_rev)
check("el prompt trae los números del check", "adherencia al plan baja (2 de 5)" in prompt)
check("el prompt manda cruzarlo", "CRUZALO CON LA REVISION" in prompt)
check("y prohíbe volver a pedir el check", "NO le" in prompt and "pidas que lo suba" in prompt)

prompt_sin = W.armar_prompt({"nombre": "Juan", "contexto": [], "ya_subio": False,
                             "revision": {"hay_check": False}})
check("si no subió, el prompt lo dice explícito",
      "TODAVIA NO subio" in prompt_sin,
      "el modelo tiene que saber que no hay check, no quedarse sin dato")

print("\n11. La política de privacidad dice lo que realmente se manda")
POL = (RAIZ / "public" / "privacidad.html").read_text()
check("ya no dice que no se manda el peso",
      "ni tu peso, ni tus fotos, ni lo que trae tu reloj" not in POL,
      "quedó la frase vieja: ahora SÍ se manda el peso")
check("declara el resumen de la revisión", "revisión de esa" in POL and "energía, descanso" in POL)
check("aclara que las fotos NO se envían", "solo se cuentan" in POL)


print("\n12. La revisión se ancla a la semana DEL MENSAJE, no a hoy")
# El lunes 24-ago la semana en curso arrancaba ese mismo día y estaba vacía. El
# mensaje de Nicolás era del 21 (semana del 17), donde su check SÍ existía. La
# 066 miraba now() y la IA le propuso "completá la revisión, que todavía no
# quedó cargada" — cuando Mati ya le había dicho que le llegó. Pasa todos los
# lunes con lo que llega el fin de semana, que es cuando llega casi todo.
SQL67 = (RAIZ / "supabase" / "migrations" / "067_revision_de_la_semana_del_mensaje.sql").read_text()
check("la función toma una fecha de referencia",
      "p_ref        timestamptz DEFAULT now()" in SQL67,
      "sin p_ref vuelve a anclar a hoy")
check("el ancla usa p_ref y no now()",
      "date_trunc('week', p_ref AT TIME ZONE" in SQL67 and
      "date_trunc('week', now() AT TIME ZONE" not in SQL67,
      "quedó algún date_trunc sobre now()")
check("las dos RPCs pasan la fecha del mensaje",
      SQL67.count("mypump_revision_semana(") >= 3,
      "alguna RPC quedó llamándola sin fecha")
check("ya_subio sale de la misma fuente",
      "(u.rev->>'hay_check')::boolean" in SQL67 and "(x.rev->>'hay_check')::boolean" in SQL67,
      "ya_subio con su propio date_trunc es el mismo bug esperando")
check("el peso de la semana no se pasa de largo",
      "sd.fecha >= l.d AND sd.fecha < l.d + 7" in SQL67,
      "sin el tope superior, el peso de una semana vieja sumaba todo lo posterior")
check("la revisión dice de qué semana es", "'semana',      (SELECT d FROM lunes)" in SQL67,
      "sin eso no hay forma de auditar si se miró la semana correcta")

print()
if fallas:
    print(f"✗ {fallas} fallo(s)\n")
    sys.exit(1)
print("✓ la IA propone, Mati dispone\n")
