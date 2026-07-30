#!/usr/bin/env python3
"""
test_consolidar_identidad.py — que la quimica de un cliente NO termine en la
ficha de otro.

POR QUE EXISTE
Los consolidadores (pump-quimica y pump-suplementos) cruzaban clientes por
NOMBRE con un match de substring bidireccional:

    if nom and (nom in k or k in nom) and len(nom) >= 5

Un titulo de videollamada que normalizaba a "gerardo" matcheaba con Gerardo
Casal, Gerardo Farias Y Gerardo Luis Mendez a la vez. Lo que se copia de esa
transcripcion es el protocolo de AAS — dosis de testosterona, trembolona, GH,
insulina — y va a mypump_quimica del cliente y al panel del coach.

Los homonimos de abajo son REALES: salen del padron de 50 clientes.

USO:  python3 scripts/test_consolidar_identidad.py
"""
import sys
import pathlib

RAIZ = pathlib.Path(__file__).resolve().parent.parent

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
    except Exception as e:
        print(f"  ✗ {nombre}\n      {type(e).__name__}: {e}")
        fail += 1


def cargar(modulo_dir):
    """Importa el consolidar.py de un subproyecto sin ejecutar main()."""
    import importlib.util
    p = RAIZ / modulo_dir / "consolidar.py"
    spec = importlib.util.spec_from_file_location(f"cons_{modulo_dir}", p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


CLI = lambda n, a: {"nombre": n, "apellido": a}

# Homonimos reales del padron.
GERARDOS = [
    ("g1", CLI("Gerardo", "Casal")),
    ("g2", CLI("Gerardo", "Farias")),
    ("g3", CLI("Gerardo Luis", "Mendez")),
]
OTROS = [
    ("u1", CLI("Gustavo", "Guardia")),
    ("u2", CLI("Gustavo", "Pucheta")),
    ("n1", CLI("Nacho", "Arnaudo")),
    ("n2", CLI("Ignacio", "Enriquez Bruce")),
]


def correr(mod_dir):
    print(f"\n{mod_dir}")
    M = cargar(mod_dir)

    def con_cache(por_nombre, por_mail=None):
        M._FATHOM_CACHE = (por_mail or {}, por_nombre)

    t("un titulo con solo el nombre de pila no matchea a NADIE", lambda: (
        con_cache({"gerardo": ["PROTOCOLO DE g?"]}),
        [(_ for _ in ()).throw(AssertionError(
            f"{c['nombre']} {c['apellido']} se llevo una transcripcion ajena"))
         for _cid, c in GERARDOS if M.fathom_transcripts(c)],
    ))

    t("con nombre Y apellido matchea solo el dueno", lambda: (
        con_cache({"gerardo casal": ["TR-CASAL"]}),
        assert_eq(M.fathom_transcripts(GERARDOS[0][1]), ["TR-CASAL"], "Casal no recibio la suya"),
        assert_eq(M.fathom_transcripts(GERARDOS[1][1]), [], "Farias recibio la de Casal"),
        assert_eq(M.fathom_transcripts(GERARDOS[2][1]), [], "Mendez recibio la de Casal"),
    ))

    t("el orden de los tokens en el titulo no importa", lambda: (
        con_cache({"casal gerardo seguimiento": ["TR-CASAL"]}),
        assert_eq(M.fathom_transcripts(GERARDOS[0][1]), ["TR-CASAL"], "no matcheo con el orden invertido"),
    ))

    t("un cliente sin apellido NO matchea por nombre", lambda: (
        con_cache({"damian": ["TR-X"]}),
        assert_eq(M.fathom_transcripts(CLI("Damian", "")), [], "matcheo sin apellido"),
    ))

    t("el mail gana y no se cae al nombre", lambda: (
        con_cache({"gerardo": ["TR-AJENA"]}, {"casal@mail.com": ["TR-MAIL"]}),
        assert_eq(
            M.fathom_transcripts({"nombre": "Gerardo", "apellido": "Casal", "mail": "Casal@Mail.com"}),
            ["TR-MAIL"], "no uso el mail"),
    ))

    t("descartar_titulos_ambiguos saca el titulo que le pega a dos", lambda: (
        con_cache({"juan pablo pagan": ["TR-AMBIGUA"], "gerardo casal": ["TR-OK"]}),
        M.descartar_titulos_ambiguos([
            ("j1", CLI("Juan", "Pagan")),
            ("j2", CLI("Juan Pablo", "Pagan")),
            *GERARDOS,
        ]),
        assert_in("gerardo casal", M._FATHOM_CACHE[1], "borro un titulo que no era ambiguo"),
        assert_not_in("juan pablo pagan", M._FATHOM_CACHE[1], "dejo el titulo ambiguo"),
    ))

    t("tokens_identidad normaliza acentos y toma solo el primer token", lambda: (
        assert_eq(M.tokens_identidad(CLI("Matías Alejandro", "Lara")), {"matias", "lara"}, "mal normalizado"),
        assert_eq(M.tokens_identidad(CLI("", "Lara")), None, "acepto sin nombre"),
    ))

    t("dos Gustavos: cada uno se lleva la suya y nada mas", lambda: (
        con_cache({"gustavo guardia": ["TR-G"], "gustavo pucheta": ["TR-P"]}),
        assert_eq(M.fathom_transcripts(OTROS[0][1]), ["TR-G"], "Guardia mal"),
        assert_eq(M.fathom_transcripts(OTROS[1][1]), ["TR-P"], "Pucheta mal"),
    ))


def assert_eq(a, b, msg):
    assert a == b, f"{msg}\n      esperado: {b}\n      obtenido: {a}"


def assert_in(k, d, msg):
    assert k in d, msg


def assert_not_in(k, d, msg):
    assert k not in d, msg


print("Identidad de cliente en los consolidadores")
for d in ("pump-quimica", "pump-suplementos"):
    if (RAIZ / d / "consolidar.py").exists():
        correr(d)

print(f"\n{ok} pasaron, {fail} fallaron\n")
sys.exit(1 if fail else 0)
