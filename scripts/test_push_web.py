#!/usr/bin/env python3
"""test_push_web.py — que el sender elija bien el transporte

POR QUÉ EXISTE
Hasta la 058, `push.py` mandaba TODO por APNs. Con Web Push entrando por la
misma cola, el sender tiene que mirar `plataforma` y elegir. Los tres modos de
equivocarse son todos silenciosos:

  · Mandar un endpoint de Web Push a APNs → BadDeviceToken. Se gastan los 4
    intentos y el aviso muere sin que nadie lea el log.
  · Cortar la corrida entera porque falta la config de APNs → los clientes web
    tampoco reciben nada, aunque su transporte esté perfectamente configurado.
    Ese era el comportamiento viejo de main().
  · Quemar los intentos de un aviso web cuando todavía no hay clave VAPID →
    cuando Mati la configure, el aviso ya está en 'error' y no sale nunca.

Ninguno tira una excepción. Los tres se ven como "no me llegó la notificación".

USO:  python3 scripts/test_push_web.py
"""
import os
import pathlib
import sys
import types

RAIZ = pathlib.Path(__file__).resolve().parent.parent
PUSH = RAIZ / "pump-centinela" / "push.py"

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


def cargar(env=None):
    """Importa push.py con un entorno controlado.

    Se carga el archivo REAL, no una copia: si se copiara el código acá, el
    test seguiría verde después de que alguien rompa el que corre de verdad.
    """
    for k in ("VAPID_PRIVATE_KEY", "APNS_KEY_ID", "APNS_TEAM_ID", "APNS_KEY_PATH",
              "SUPABASE_SERVICE_KEY", "VAPID_SUBJECT"):
        os.environ.pop(k, None)
    os.environ.update(env or {})
    mod = types.ModuleType("push_bajo_prueba")
    mod.__file__ = str(PUSH)
    src = PUSH.read_text()
    # Se recorta el `if __name__ == "__main__"` para que importarlo no dispare
    # una corrida real contra la cola de producción.
    src = src.split('if __name__ == "__main__"')[0]
    exec(compile(src, str(PUSH), "exec"), mod.__dict__)  # noqa: S102
    return mod


print("\n=== push.py — elección de transporte ===\n")


def sin_vapid_dice_por_que():
    m = cargar()
    exito, error, baja = m.enviar_web("https://fcm.googleapis.com/x", "p", "a", "T", "C", "chat")
    assert exito is False, "sin clave no puede decir que mandó"
    assert error and "VAPID" in error, f"el error tiene que nombrar la config que falta, dijo: {error}"
    assert baja is False, "no hay que dar de baja el device: el problema es nuestro, no del cliente"
t("sin VAPID_PRIVATE_KEY falla diciendo QUÉ falta", sin_vapid_dice_por_que)


def lee_la_clave_del_entorno():
    m = cargar({"VAPID_PRIVATE_KEY": "una-clave-cualquiera"})
    assert m.VAPID_PRIVATE == "una-clave-cualquiera", "no leyó VAPID_PRIVATE_KEY"
    assert m.VAPID_SUBJECT.startswith("mailto:"), "el subject de VAPID tiene que ser un mailto:"
t("lee la clave y el subject del entorno", lee_la_clave_del_entorno)


def baja_solo_en_404_410():
    """404/410 = la suscripción murió. Cualquier otro código NO da de baja.

    Confundirlos borra devices vivos: un 500 pasajero del servicio de push
    apagaría el timbre de ese cliente para siempre, y nadie lo notaría hasta
    que avise que no le llega nada.
    """
    m = cargar({"VAPID_PRIVATE_KEY": "x"})
    src = pathlib.Path(m.__file__).read_text()
    i = src.index("def enviar_web")
    cuerpo = src[i:src.index("\ndef ", i + 10)]
    assert "(404, 410)" in cuerpo, "tiene que dar de baja SOLO con 404/410"
    assert cuerpo.count("return False") >= 3, "los otros errores no pueden dar de baja el device"
t("solo 404/410 dan de baja la suscripción", baja_solo_en_404_410)


def sin_apns_igual_manda_web():
    """El bug viejo: un .env sin APNs cortaba main() y no salía NADA."""
    m = cargar({"VAPID_PRIVATE_KEY": "x"})
    src = pathlib.Path(m.__file__).read_text()
    i = src.index("def main()")
    cuerpo = src[i:i + 2000]
    assert "hay_web" in cuerpo and "hay_apns" in cuerpo, "main() tiene que distinguir los transportes"
    # Desde que existe FCM son TRES, no dos. La regla no cambió —solo se corta
    # si no hay NINGUNO— pero la condición ahora los nombra a los tres, así que
    # buscar el texto viejo daba un falso negativo.
    assert "hay_fcm" in cuerpo, "main() tiene que conocer también el transporte de Android"
    assert "if not (hay_apns or hay_web or hay_fcm)" in cuerpo, \
        "solo se corta si NO hay ninguno; con cualquiera configurado, esos avisos salen"
t("falta APNs pero hay VAPID → los avisos web salen igual", sin_apns_igual_manda_web)


def web_sin_config_no_quema_intentos():
    m = cargar()
    src = pathlib.Path(m.__file__).read_text()
    i = src.index('if plataforma == "web"')
    tramo = src[i:i + 400]
    # Se pide la GUARDA, no solo el `continue`. Buscar "continue" a secas deja
    # pasar un `if False: continue`, que es exactamente el bug: el aviso cae al
    # envío, falla por falta de clave, y se come uno de los 4 intentos.
    guarda = tramo.index("if not hay_web:")
    assert "continue" in tramo[guarda:guarda + 300], \
        "un aviso web sin VAPID tiene que quedar EN LA COLA, no marcarse como error: " \
        "si se queman los 4 intentos, cuando se configure la clave ya no sale nunca"
t("un aviso web sin VAPID queda en la cola, no se quema", web_sin_config_no_quema_intentos)


def android_no_se_va_por_apns():
    m = cargar()
    src = pathlib.Path(m.__file__).read_text()
    i = src.index('if plataforma == "web"')
    tramo = src[i:i + 1200]
    assert 'elif plataforma == "android"' in tramo, \
        "sin rama propia, un device Android caería en el else y se mandaría por APNs"
t("un device Android no se va por APNs por descarte", android_no_se_va_por_apns)


def el_dry_run_dice_el_transporte():
    m = cargar()
    src = pathlib.Path(m.__file__).read_text()
    assert "[{p.get('plataforma','ios')}]" in src, \
        "el dry-run tiene que mostrar por dónde saldría cada aviso; es lo único que se mira antes de --enviar"
t("el dry-run muestra el transporte de cada aviso", el_dry_run_dice_el_transporte)


print(f"\n{'✅' if fail == 0 else '❌'}  {ok} pasaron, {fail} fallaron\n")
sys.exit(0 if fail == 0 else 1)
