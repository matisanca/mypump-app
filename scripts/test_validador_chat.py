#!/usr/bin/env python3
"""test_validador_chat.py — el filtro que hace imposible un consejo de salud automático

POR QUÉ ESTE TEST ES EL MÁS IMPORTANTE DE LA FEATURE
Todo lo demás, si falla, molesta. Esto, si falla, manda una indicación de
entrenamiento o de salud firmada como Mati —que es entrenador— a una persona
que le paga justamente por sus indicaciones.

El prompt le pide al modelo que no lo haga y va a obedecer casi siempre. Pero
"casi siempre" sobre miles de mensajes al año es una estadística, no una
garantía. Este filtro es lo que convierte la estadística en garantía, porque no
depende del modelo.

Los casos de abajo NO son inventados en abstracto: son las respuestas que un
modelo genera naturalmente cuando un cliente escribe "me quedó doliendo el
hombro" o "cuánta proteína tomo".

USO:  python3 scripts/test_validador_chat.py
"""
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))

import validador_chat as V  # noqa: E402

ok = fail = 0


def t(nombre, fn):
    global ok, fail
    try:
        fn(); print(f"  ✓ {nombre}"); ok += 1
    except AssertionError as e:
        print(f"  ✗ {nombre}\n      {e}"); fail += 1
    except Exception as e:  # noqa: BLE001
        print(f"  ✗ {nombre}\n      {type(e).__name__}: {e}"); fail += 1


def bloquea(texto, por=None):
    m = V.revisar(texto)
    assert m, f"SE PUBLICARÍA: {texto!r}"
    if por:
        assert any(por in x for x in m), f"lo bloqueó por {m}, esperaba algo con '{por}': {texto!r}"


def pasa(texto):
    m = V.revisar(texto)
    assert not m, f"lo bloqueó de más ({m}): {texto!r}"


print("\n=== Validador del chat ===\n")

# ── Lo que NUNCA puede salir ──────────────────────────────────────────────
def indicaciones_de_nutricion():
    bloquea("dale, sumale 30g de proteína al desayuno", "proteina")
    bloquea("tomate 2 scoops más de whey", "whey")
    bloquea("subile 200 kcal al día y vemos", "numero")
    bloquea("bajá un poco los carbohidratos esta semana", "carbohidratos")
t("bloquea indicaciones de nutrición", indicaciones_de_nutricion)


def indicaciones_de_entrenamiento():
    bloquea("hacé 3 series más de press", "numero")
    bloquea("bajale el volumen esta semana", "volumen")
    bloquea("mové el RIR a 1 y seguimos", "rir")
t("bloquea indicaciones de entrenamiento", indicaciones_de_entrenamiento)


def temas_de_salud():
    # El caso que más importa. Si un cliente dice que le duele algo, la
    # respuesta enlatada NO puede hablar del dolor: tiene que verlo Mati.
    bloquea("si te duele parás y seguimos la semana que viene", "duele")
    bloquea("puede ser una tendinitis, tranquilo", "tendinitis")
    bloquea("fijate con tu médico y me contás", "medico")
t("bloquea cualquier respuesta sobre dolor o salud", temas_de_salud)


def consejos_genericos_tambien():
    # Regla dura del plan: NI SIQUIERA genéricos. "Tomá más agua" parece
    # inofensivo hasta que se lo decís a alguien con un problema renal.
    bloquea("tomá 2 litros de agua por día", "numero")
    bloquea("descansá 8 horas y vas a andar mejor", "numero")
t("bloquea también los consejos que parecen inofensivos", consejos_genericos_tambien)


def autodelacion():
    bloquea("soy un asistente automático, Mati te responde luego", "asistente")
    bloquea("esto lo generó una IA", "IA")
    bloquea("respuesta automatica de MyPump", "automatica")
t("bloquea que el mensaje se delate como automático", autodelacion)


def acentos_no_lo_esquivan():
    # Un modelo escribe 'proteína' con acento y 'lesión' con acento. Si el
    # filtro comparara literales, esas dos pasarían derecho.
    bloquea("subile la proteína", "proteina")
    bloquea("puede ser una lesión", "lesion")
t("los acentos no esquivan el filtro", acentos_no_lo_esquivan)


def tono_ajeno():
    bloquea("¿Cómo venís?", "apertura")
    bloquea("dale, gracias por avisar.", "punto")
    bloquea("genial 💪🔥", "emojis")
    bloquea("x" * 320, "largo")
t("bloquea lo que no suena a Mati", tono_ajeno)


# ── Lo que SÍ tiene que poder salir ───────────────────────────────────────
def las_simples_pasan():
    # Si el filtro bloqueara todo, la feature no existe: cada mensaje escalaría
    # a WhatsApp y el cuello de botella volvería igual que antes.
    pasa("dale, gracias por avisar")
    pasa("buenísimo, lo miro y te digo")
    pasa("perfecto, ya lo vi")
    pasa("me llegó, gracias 💪")
    pasa("dale, quedamos así entonces")
    pasa("copiado, cualquier cosa avisame")
t("las respuestas simples SÍ pasan", las_simples_pasan)


def no_bloquea_por_pedazos_de_palabra():
    # Estas frases son inofensivas, pero CONTIENEN palabras de la lista negra
    # adentro de otras palabras. Con un filtro por substring —que es lo primero
    # que uno escribe— las tres se bloquean:
    #   "botella"  contiene "bot"
    #   "impresión" contiene "presion"
    #   "encargate" contiene "carga"
    #   "seriedad"  contiene "serie"
    # Y ahí la feature deja de servir: escala todo, nadie entiende por qué, y el
    # cuello de botella vuelve igual que antes.
    pasa("dale, llevate una botella")
    pasa("me dio muy buena impresión")
    pasa("encargate vos y listo")
    pasa("me gusta esa seriedad")
    pasa("dale, sería lo mejor")
    pasa("gracias por contarme")
t("no bloquea por pedazos de palabra ('botella', 'impresión')", no_bloquea_por_pedazos_de_palabra)


def casos_borde():
    assert V.revisar(None), "None tiene que bloquearse, no explotar"
    assert V.revisar(""), "vacío tiene que bloquearse"
    assert V.revisar("   "), "solo espacios tiene que bloquearse"
t("None, vacío y espacios se bloquean sin explotar", casos_borde)


def se_puede_publicar_es_coherente():
    assert V.se_puede_publicar("dale, gracias") is True
    assert V.se_puede_publicar("sumale 30g de proteína") is False
t("se_puede_publicar() coincide con revisar()", se_puede_publicar_es_coherente)


def el_motivo_es_util():
    # El motivo va al log y a la bandeja. "bloqueado" a secas no le sirve a
    # nadie para calibrar el prompt.
    m = V.revisar("sumale 30g de proteína al desayuno")
    assert len(m) >= 2, f"esperaba varios motivos, dio {m}"
    assert all(isinstance(x, str) and len(x) > 5 for x in m), f"motivos poco útiles: {m}"
t("el motivo del bloqueo explica qué pasó", el_motivo_es_util)


print(f"\n{'✅' if fail == 0 else '❌'}  {ok} pasaron, {fail} fallaron\n")
sys.exit(0 if fail == 0 else 1)
