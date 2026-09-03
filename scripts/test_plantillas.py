#!/usr/bin/env python3
"""test_plantillas.py — que ninguna frase firmada como Mati suene a bot

POR QUÉ EXISTE
Estas 26 frases se mandan como si las escribiera Mati. Son el texto más
repetido del negocio: 62 personas, todas las semanas. Un "¿" de más o un punto
final donde él nunca pone uno, y el mensaje deja de sonar a él — y ahí se cae
toda la premisa de la feature.

El banco se escribe a mano, así que el error entra a mano. Este test lo revisa
entero de una.

Y prueba la parte que no es de estilo: la selección tiene que ser ESTABLE.
El domingo puede correr dos veces (reintento, reinicio de la mini), y si la
segunda corrida elige otra frase, el cliente ve dos redacciones distintas del
mismo pedido.

USO:  python3 scripts/test_plantillas.py
"""
import pathlib
import sys

RAIZ = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(RAIZ / "pump-centinela"))

import plantillas as P  # noqa: E402

ok = fail = 0


def t(nombre, fn):
    global ok, fail
    try:
        fn()
        print(f"  ✓ {nombre}")
        ok += 1
    except AssertionError as e:
        print(f"  ✗ {nombre}\n      {e}")
        fail += 1
    except Exception as e:  # noqa: BLE001
        print(f"  ✗ {nombre}\n      {type(e).__name__}: {e}")
        fail += 1


apodo = lambda n: (n or "").split()[0].lower() if n else "che"

print("\n=== Banco de plantillas ===\n")


def todas_respetan_el_tono():
    malas = []
    for banco, frases in P.BANCOS.items():
        for f in frases:
            p = P.problemas(f)
            if p:
                malas.append(f"[{banco}] {f[:48]}… → {', '.join(p)}")
    assert not malas, "frases que rompen el tono:\n      " + "\n      ".join(malas)
t("todas las frases respetan el tono de Mati", todas_respetan_el_tono)


def hay_suficiente_variedad():
    # Con pocas variantes, dos clientes que se conocen reciben lo mismo la misma
    # tarde. Pasa: se entrenan juntos y comparan el teléfono.
    assert len(P.DOMINGO) >= 12, f"el banco del domingo tiene {len(P.DOMINGO)}, hacen falta 12+"
    assert len(P.RECORDATORIO) >= 6, "pocos recordatorios"
    for banco, frases in P.BANCOS.items():
        assert len(set(frases)) == len(frases), f"hay frases repetidas en {banco}"
t("hay variedad suficiente y sin repetidas", hay_suficiente_variedad)


def la_eleccion_es_estable():
    a = P.elegir(P.DOMINGO, "Gerardo Fernández", apodo)
    b = P.elegir(P.DOMINGO, "Gerardo Fernández", apodo)
    assert a == b, "dos llamadas seguidas dieron frases distintas: una re-corrida del domingo mandaría dos textos"
t("la misma persona en la misma semana recibe SIEMPRE la misma frase", la_eleccion_es_estable)


def distintos_clientes_distinta_frase():
    nombres = ["Gerardo Fernández", "Lucas Torres", "Ezequiel Romero", "Facundo Palero",
               "Mario Suárez", "Nacho Pérez", "Emiliano Díaz", "Tomás Vega"]
    frases = {P.elegir(P.DOMINGO, n, apodo) for n in nombres}
    assert len(frases) >= 5, f"8 clientes se repartieron en solo {len(frases)} frases distintas"
t("clientes distintos reciben frases distintas", distintos_clientes_distinta_frase)


def el_apodo_entra_bien():
    # Ya no se exige que TODA frase arranque con el nombre (ver el test del
    # tope, abajo). Lo que sí: en las que lo llevan, tiene que entrar en
    # minúscula y no quedar el placeholder crudo.
    con_nombre = [f for f in P.DOMINGO if "{n}" in f]
    assert con_nombre, "el banco del domingo se quedó sin ninguna frase con nombre"
    for cruda in con_nombre:
        f = cruda.format(n=apodo("Gerardo Fernández"))
        assert f.startswith("gerardo"), f"el apodo tiene que ir primero y en minúscula: {f[:20]}"
    for banco in P.BANCOS.values():
        for cruda in banco:
            f = cruda.format(n=apodo("Gerardo Fernández"))
            assert "{n}" not in f, f"quedó el placeholder sin reemplazar: {f[:40]}"
t("cuando el apodo va, entra en minúscula y sin placeholder", el_apodo_entra_bien)


def el_nombre_no_esta_en_todas():
    """El bug que reportó Mati el 3-sep, mirando su propio panel de chats.

    Todos los mensajes del sistema arrancaban con el nombre: "nahuel, acá
    todavía…", "facundo, todavía te espero…", "mauro, te leo cuando…", "ismael,
    dale…", "justo, vi tu check…", "paula, buenísimo el check…". Uno solo está
    bien; veintiséis seguidos se leen como un mailing, no como Mati.

    Su palabra fue: "está bien que lo ponga, pero SIEMPRE es raro".

    `problemas()` no puede ver esto porque mira una frase por vez: el defecto
    solo existe en el conjunto.
    """
    malos = []
    for banco, frases in P.BANCOS.items():
        pr = P.problemas_banco(banco, frases)
        if pr:
            malos.append(f"[{banco}] {', '.join(pr)}")
    assert not malos, "bancos desbalanceados:\n      " + "\n      ".join(malos)
t("el nombre NO está en todas las frases de ningún banco", el_nombre_no_esta_en_todas)


def el_tope_del_banco_detecta_de_verdad():
    # Mismo criterio que con problemas(): si problemas_banco() devolviera
    # siempre [], el test de arriba pasaría con el banco entero nombrado.
    todas = ["{n}! una", "{n}, dos", "{n}! tres"]
    assert P.problemas_banco("recordatorio", todas), "no detectó un banco 100% con nombre"
    ninguna = ["una", "dos", "tres"]
    assert P.problemas_banco("recordatorio", ninguna), "no detectó un banco sin ningún nombre"
    mezcla = ["{n}! una", "dos", "tres", "cuatro"]
    assert not P.problemas_banco("recordatorio", mezcla), "marcó como malo un banco bien mezclado"
t("el tope del banco detecta lo que dice detectar", el_tope_del_banco_detecta_de_verdad)


def el_validador_detecta_de_verdad():
    # Si `problemas()` devolviera siempre [], el primer test pasaría con
    # cualquier cosa adentro del banco.
    casos = [
        ("{n}! ¿cómo venís?", "signo de apertura"),
        ("{n}, subí tu revisión.", "punto final"),
        # Ojo: "hola, subí tu revisión" YA NO es un error — una frase sin
        # nombre es válida a propósito. Lo que sigue siendo error es meter el
        # apodo en el medio, que no lo dice nadie.
        ("che {n}, subí tu revisión", "el apodo no va primero"),
        ("{n}! dale 💪🔥", "dos emojis"),
        ("{n}, por favor subí la revisión", "tono ajeno"),
    ]
    for frase, que in casos:
        assert P.problemas(frase), f"no detectó: {que} → {frase}"
t("el validador detecta lo que dice detectar", el_validador_detecta_de_verdad)


def sin_nombre_no_explota():
    f = P.elegir(P.DOMINGO, "", apodo)
    assert f and "{n}" not in f, "un cliente sin nombre cargado no puede romper la ronda entera"
t("un cliente sin nombre no rompe la ronda", sin_nombre_no_explota)


def solo_fotos_no_pide_el_check():
    # A quien ya mandó el check, pedirle "la revisión" entera lo hace sentir
    # ignorado: es la forma más rápida de que deje de subir cosas.
    for f in P.SOLO_FOTOS:
        assert "foto" in f.lower(), f"la frase de solo-fotos no nombra las fotos: {f}"
        assert "peso" not in f.lower() or "check" in f.lower(), \
            f"le vuelve a pedir lo que ya hizo: {f}"
t("el banco de solo-fotos no le re-pide lo que ya subió", solo_fotos_no_pide_el_check)


print(f"\n{'✅' if fail == 0 else '❌'}  {ok} pasaron, {fail} fallaron\n")
sys.exit(0 if fail == 0 else 1)
