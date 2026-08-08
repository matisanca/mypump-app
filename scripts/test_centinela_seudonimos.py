#!/usr/bin/env python3
"""
test_centinela_seudonimos.py — que ningún nombre real viaje pegado a un dato de salud.

QUÉ PROTEGE

El centinela le manda datos de clientes a la API de Anthropic para redactar el
informe de Mati. En cuatro envíos distintos. Uno de ellos, `ajustes`, llevaba el
score de recuperación, la media de 7 días, los días en rojo, el estado
autonómico y la métrica de HRV —todo derivado de lo que se leyó de Health
Connect o de Apple Salud— con NOMBRE Y APELLIDO al lado.

El modelo nunca necesitó el nombre: lo usa como clave para devolver cada
respuesta con la suya. O sea que mandarlo era gratis para el resultado y caro
para el cliente. Ahora va un alias por corrida (c1, c2…).

LA LÍNEA, QUE NO ES "QUÉ DATO ES SENSIBLE"
Los otros dos envíos que sí llevan el apodo (`personalizados` y `msg_ajuste`)
escriben el mensaje de WhatsApp que Mati reenvía, y ese mensaje ARRANCA con el
apodo: seudonimizarlos rompería el producto. A cambio, no llevan un solo dato
de salud. La regla es "qué dato viaja PEGADO a un nombre", y este test la fija.

Por qué un test y no una revisión: esto no da error. Si mañana alguien suma
`"nombre"` al payload de ajustes, todo sigue funcionando igual y nadie se
entera hasta que importe.

USO:  python3 scripts/test_centinela_seudonimos.py
"""
import sys
import json
import pathlib
import importlib.util

RAIZ = pathlib.Path(__file__).resolve().parent.parent
CENT = RAIZ / "pump-centinela" / "centinela.py"

ok = fallo = 0


def test(nombre):
    def deco(fn):
        global ok, fallo
        try:
            fn()
            print(f"  ✓ {nombre}")
            ok += 1
        except AssertionError as e:
            print(f"  ✗ {nombre}\n      {e}")
            fallo += 1
        except Exception as e:                    # noqa: BLE001
            print(f"  ✗ {nombre}\n      excepción: {type(e).__name__}: {e}")
            fallo += 1
        return fn
    return deco


# ── Cargar el módulo sin que corra la ronda ─────────────────────────────
spec = importlib.util.spec_from_file_location("centinela", CENT)
cent = importlib.util.module_from_spec(spec)
sys.modules["centinela"] = cent
try:
    spec.loader.exec_module(cent)
except SystemExit:
    pass
except Exception as e:                            # noqa: BLE001
    print(f"✗ no se pudo importar centinela.py: {type(e).__name__}: {e}")
    sys.exit(1)

# Los nombres son inventados; lo que importa es que no aparezcan en el prompt.
NOMBRES = ["Ezequiel Villalobos", "María José Paggi"]

# ── Interceptar la llamada a la API ─────────────────────────────────────
PROMPTS = []


def espiar(prompt, timeout=None, etiqueta="json"):
    PROMPTS.append({"etiqueta": etiqueta, "prompt": prompt})
    # Se contesta con las claves que el prompt pidió, para poder verificar
    # también que el mapeo de vuelta funciona.
    claves = set()
    for linea in prompt.split("DATOS:")[-1].split("\n"):
        for c in ("c1", "c2", "c3"):
            if f'"cliente": "{c}"' in linea or f'"{c}"' in linea:
                claves.add(c)
    if not claves:
        import re
        claves = set(re.findall(r'"cliente":\s*"(c\d+)"', prompt))
    return {c: "respuesta de prueba" for c in claves}


cent.claude_json = espiar

print("\nAjustes: el envío que lleva la recuperación del wearable")


def _lista_ajustes():
    return [{
        "nombre": n,
        "chk": {"energia": 2, "descanso": 2, "hambre": 4, "adherencia": 3, "nota": ""},
        "ctx": {"obj": "recomp", "perfil": "intermedio", "delta_peso_g": -300,
                "var_rendimiento": -4,
                "recup": {"estado": "ok", "score_hoy": 41, "media_7d": 48, "delta": -9,
                          "dias_banda_baja": 4, "autonomico": "fatiga_acumulada",
                          "hrv_metrica": "rmssd"}},
        "alertas": ["sin entrenar 4 días"],
        "dieta": {"kcal": 2400}, "rutina": {"dias": 4},
        "suplementos": {"stack": "creatina"},
        "veredicto": {"cruces": []},
    } for n in NOMBRES]


@test("el prompt de ajustes NO contiene ningún nombre real")
def _():
    PROMPTS.clear()
    cent.gen_ajustes(_lista_ajustes())
    assert PROMPTS, "no se llamó a la API"
    p = PROMPTS[0]["prompt"]
    for n in NOMBRES:
        assert n not in p, f"el nombre '{n}' viaja en el prompt de ajustes"
        for parte in n.split():
            assert parte not in p, f"'{parte}' (de '{n}') viaja en el prompt de ajustes"


@test("el prompt de ajustes SÍ sigue llevando la recuperación (no se rompió el producto)")
def _():
    PROMPTS.clear()
    cent.gen_ajustes(_lista_ajustes())
    p = PROMPTS[0]["prompt"]
    for campo in ("score_hoy", "estado_autonomico", "sensor_hrv"):
        assert campo in p, f"falta '{campo}': se perdió el dato que hace útil al informe"
    assert '"cliente": "c1"' in p, "no se está mandando el alias como clave"


@test("la respuesta vuelve mapeada al nombre real")
def _():
    PROMPTS.clear()
    out = cent.gen_ajustes(_lista_ajustes())
    for n in NOMBRES:
        assert n in out, (f"'{n}' no volvió en el resultado: el mapeo alias->nombre está roto "
                          "y el informe de Mati sale con los clientes cambiados o vacíos")


print("\nNotas: texto libre que escribió el cliente")


@test("el prompt de notas NO contiene ningún nombre real")
def _():
    PROMPTS.clear()
    metricas = [{"cliente_id": f"cid{i}", "nombre": n} for i, n in enumerate(NOMBRES)]
    chk = {f"cid{i}": {"nota": f"esta semana anduve flojo, me lesioné el hombro ({i})"}
           for i in range(len(NOMBRES))}
    cent.interpretar_notas(metricas, chk, {})
    assert PROMPTS, "no se llamó a la API"
    p = PROMPTS[0]["prompt"]
    for n in NOMBRES:
        assert n not in p, f"el nombre '{n}' viaja en el prompt de notas"


print("\nLa línea: dónde SÍ va el apodo, y por qué ahí no hay salud")


@test("los envíos que llevan apodo no llevan ningún dato de salud")
def _():
    src = CENT.read_text()
    for etiqueta in ("personalizados", "msg_ajuste"):
        i = src.find(f'etiqueta="{etiqueta}"')
        assert i > 0, f"no encontré el envío '{etiqueta}'"
        bloque = src[src.rfind("\ndef ", 0, i):i]
        for prohibido in ("recuperacion", "hrv_metrica", "score_hoy", "autonomico",
                          "sueno_min", "fc_reposo"):
            assert prohibido not in bloque, (
                f"'{etiqueta}' lleva el apodo del cliente Y '{prohibido}'. Si hay que mandar "
                "salud ahí, hay que seudonimizar ese envío también.")


@test("_seudonimizar da alias estables dentro de la corrida y no persiste nada")
def _():
    a2n, n2a = cent._seudonimizar(["Ana", "Beto", "Ana"])
    assert n2a["Ana"] == "c1" and n2a["Beto"] == "c2", f"alias raros: {n2a}"
    assert a2n["c1"] == "Ana", "el mapeo de vuelta no cierra"
    assert len(a2n) == 2, "un nombre repetido debería reusar su alias, no crear otro"


print(f"\n{ok} pasaron, {fallo} fallaron\n")
sys.exit(1 if fallo else 0)
