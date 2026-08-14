#!/usr/bin/env python3
"""validador_chat.py — el cinturón, puesto después de los tiradores

QUE ES
Un filtro deterministico, en Python, que corre ANTES de publicar cualquier
respuesta generada por IA en el chat de un cliente. No usa modelos, no llama a
nada: son reglas.

POR QUE NO ALCANZA CON EL PROMPT
El prompt le dice al modelo que NUNCA de indicaciones de entrenamiento,
nutricion, suplementacion ni salud. Y va a obedecer casi siempre. Pero "casi
siempre" sobre miles de mensajes al ano no es una garantia, es una estadistica.
Un modelo alucinado, o uno al que un cliente le escribio algo raro a proposito,
puede escribir "tomate 2 scoops mas de proteina" — y eso saldria firmado como
Mati, que es entrenador, a una persona que le paga por sus indicaciones.

Este archivo hace que ESO NO PUEDA PASAR aunque el modelo se desvie, porque el
filtro no depende del modelo.

QUE BLOQUEA, Y POR QUE CADA COSA
· Numeros pegados a unidades (kcal, g, kg, series, reps, mg, ml) → es una
  indicacion, aunque este redactada como charla.
· Lista negra de palabras del dominio → "proteina", "dosis", "lesion", "dolor",
  "ciclo"… Si aparecen, no es una respuesta simple: es una consulta que tiene
  que ver Mati.
· Autodelacion → "soy un asistente", "IA", "automatico". El cliente cree que
  habla con Mati; que el propio mensaje lo desmienta es peor que no contestar.
· Tono → signos de apertura, punto final, mas de un emoji, largo. Lo mismo que
  valida el banco de plantillas: si no suena a Mati, no sale.

CUANDO ALGO SE BLOQUEA NO SE REESCRIBE: SE DERIVA.
Intentar arreglar la respuesta automaticamente es volver a confiar en el modelo
para justo lo que fallo.
"""
import re
import unicodedata

# ── Lo que nunca puede salir de una respuesta automatica ─────────────────
#
# Cada palabra de acá es una consulta que merece a Mati, no un enlatado. La
# lista es AMPLIA a proposito: el costo de escalar de mas es que Mati lee un
# mensaje que podria haberse contestado solo. El costo de escalar de menos es
# que un cliente con una molestia recibe "dale, gracias" y deja de escribir.
PALABRAS_PROHIBIDAS = {
    # Nutricion y suplementacion
    "proteina", "proteinas", "creatina", "whey", "caseina", "bcaa", "glutamina",
    "carbohidrato", "carbohidratos", "carbo", "grasa", "grasas", "caloria", "calorias",
    "macro", "macros", "dieta", "deficit", "superavit", "ayuno", "suplemento",
    "suplementos", "vitamina", "omega", "creatinina", "quemador", "termogenico",
    "dosis", "miligramos", "escalon", "recomposicion",
    # Entrenamiento
    "serie", "series", "repeticion", "repeticiones", "rir", "rpe", "carga",
    "descarga", "deload", "volumen", "frecuencia", "progresion", "rutina",
    "ejercicio", "ejercicios", "tecnica", "sentadilla", "peso muerto", "press",
    # Salud
    "lesion", "lesionado", "dolor", "duele", "molestia", "inflamacion", "esguince",
    "tendinitis", "contractura", "medicamento", "medico", "remedio", "antibiotico",
    "ciclo", "hormona", "hormonal", "testosterona", "analisis", "estudio",
    "presion", "mareo", "mareado", "nausea", "vomito", "fiebre",
    # Autodelacion
    "asistente", "inteligencia artificial", "automatico", "automatica", "bot",
    "modelo de lenguaje", "chatgpt", "openai", "generado",
}

# Numero pegado a una unidad: "200g", "3 series", "1500 kcal", "2x10", "8 horas".
#
# Las unidades de TIEMPO estaban afuera y era un agujero: "descansa 8 horas" y
# "tomate 2 litros por dia" son indicaciones de salud tan concretas como
# "sumale 30g de proteina", solo que suenan a consejo de amigo. Lo encontro el
# test, no la lectura.
UNIDADES = re.compile(
    r"\d+\s*(kcal|cal|kg|kilos?|gr?s?\b|gramos?|mg|ml|litros?|series?|reps?|"
    r"repeticiones?|min|minutos?|horas?|hs\b|dias?|semanas?|veces|vueltas?|"
    r"x\s*\d)", re.IGNORECASE)

# "IA" suelta, en mayusculas, como palabra. Aparte de la lista para no pisar
# palabras que la contienen (por ejemplo "dia" no lleva acento en el mensaje).
IA_SUELTA = re.compile(r"\bIA\b")

LARGO_MAX = 300


def _normalizar(t):
    """Sin acentos y en minuscula: 'proteína' y 'proteina' son la misma palabra,
    y un modelo puede escribir cualquiera de las dos."""
    t = unicodedata.normalize("NFD", (t or "").lower())
    return "".join(c for c in t if unicodedata.category(c) != "Mn")


def revisar(texto):
    """Devuelve la lista de motivos por los que NO se puede publicar.

    Vacía = se puede publicar. Nunca reescribe: eso seria volver a confiar en el
    modelo para justo lo que fallo.
    """
    if texto is None:
        return ["no hay texto"]
    t = texto.strip()
    if not t:
        return ["texto vacio"]

    motivos = []
    plano = _normalizar(t)

    if len(t) > LARGO_MAX:
        motivos.append(f"muy largo ({len(t)} caracteres)")

    m = UNIDADES.search(t)
    if m:
        motivos.append(f"da un numero con unidad ('{m.group(0).strip()}')")

    # Palabras completas: 'seria' no puede disparar por 'serie'.
    tokens = set(re.findall(r"[a-z]+", plano))
    for p in PALABRAS_PROHIBIDAS:
        if " " in p:
            if p in plano:
                motivos.append(f"habla de '{p}'")
        elif p in tokens:
            motivos.append(f"habla de '{p}'")

    if IA_SUELTA.search(t):
        motivos.append("se delata como IA")

    if "¿" in t or "¡" in t:
        motivos.append("usa signos de apertura (Mati no los usa)")

    if t.endswith("."):
        motivos.append("termina en punto (Mati no lo hace)")

    emojis = [c for c in t if ord(c) > 0x2100]
    if len(emojis) > 1:
        motivos.append(f"tiene {len(emojis)} emojis")

    # Ordenados y sin repetir, para que el log sea legible cuando saltan varios.
    return sorted(set(motivos))


def se_puede_publicar(texto):
    return not revisar(texto)
