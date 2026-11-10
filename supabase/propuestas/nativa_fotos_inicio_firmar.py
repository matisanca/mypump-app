#!/usr/bin/env python3
"""Fotos de inicio, del lado de la Mini: el set de un alumno con URLs firmadas, para el revisor de físico de la entrega.

Postgres no puede firmar URLs de Storage, así que la función de servicio tiene dos pasos: la base devuelve el set con los
paths (`mypump_fotos_inicio_servicio`, solo service_role) y acá se firman contra Storage con la misma service_role.
Las URLs duran 10 minutos y se bajan desde la Mini, nunca desde un navegador. Solo biblioteca estándar.

Como módulo:
    import nativa_fotos_inicio_firmar as fi
    for p in fi.pendientes():                      # sets completos sin leer, quietos hace 10 minutos
        s = fi.set_firmado(p["cliente_id"])        # {cliente_id, completo, actualizado_en, nota_motivacion, fotos: [...]}
        rutas = fi.bajar(s, carpeta)               # frente.jpg, perfil.jpg, espalda.jpg, motivacion_1.jpg…
        ...                                        # por_fotos(cliente_id, carpeta)
        fi.leido(s["cliente_id"], s["actualizado_en"])

Cada foto: id, cliente_id, pose (frente | perfil | espalda | motivacion), tomada_en, ancho, alto, lado_largo, bytes,
brillo, nitidez, path, url, url_vence_en.

Por línea de comandos (SUPABASE_URL y SUPABASE_SERVICE_KEY en el entorno, nunca en el repo):
    nativa_fotos_inicio_firmar.py pendientes [minutos_de_reposo]
    nativa_fotos_inicio_firmar.py set <cliente_id>
    nativa_fotos_inicio_firmar.py bajar <cliente_id> <carpeta>
    nativa_fotos_inicio_firmar.py leido <cliente_id> <actualizado_en>
    nativa_fotos_inicio_firmar.py pedir <cliente_id>     # le abre la sección en la app
    nativa_fotos_inicio_firmar.py cerrar <cliente_id>    # después de la entrega
"""
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BUCKET = "fotos-inicio"
EXPIRA_S = 600
ESPERA_S = 30


class ErrorFotosInicio(Exception):
    pass


def _config():
    url, clave = os.environ.get("SUPABASE_URL"), os.environ.get("SUPABASE_SERVICE_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not clave:
        raise ErrorFotosInicio("faltan SUPABASE_URL y SUPABASE_SERVICE_KEY")
    return url.rstrip("/"), clave


def _post(ruta, cuerpo):
    url, clave = _config()
    pedido = urllib.request.Request(
        url + ruta, data=json.dumps(cuerpo).encode(), method="POST",
        headers={"apikey": clave, "Authorization": f"Bearer {clave}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(pedido, timeout=ESPERA_S) as r:
            return json.loads(r.read().decode() or "null")
    except urllib.error.HTTPError as e:
        raise ErrorFotosInicio(f"{ruta}: HTTP {e.code}") from None
    except (urllib.error.URLError, TimeoutError, ValueError) as e:
        raise ErrorFotosInicio(f"{ruta}: {e}") from None


def _rpc(fn, **args):
    return _post(f"/rest/v1/rpc/{fn}", args)


def pendientes(reposo_min=10):
    """Los sets completos que el revisor no leyó o que cambiaron después: [{cliente_id, completado_en, actualizado_en, leido_en}]."""
    return _rpc("mypump_fotos_inicio_pendientes", p_reposo_min=reposo_min) or []


def set_firmado(cliente_id, expira_s=EXPIRA_S):
    """El set con una URL firmada por foto. None si a ese alumno no se le pidieron fotos."""
    s = _rpc("mypump_fotos_inicio_servicio", p_cliente_id=cliente_id)
    if not s:
        return None
    fotos = s.get("fotos") or []
    if fotos:
        url, _ = _config()
        firmadas = _post(f"/storage/v1/object/sign/{BUCKET}", {"expiresIn": int(expira_s), "paths": [f["path"] for f in fotos]})
        por_path = {str(x.get("path", "")).lstrip("/"): x.get("signedURL") for x in firmadas or [] if isinstance(x, dict)}
        vence = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=int(expira_s))).isoformat(timespec="seconds")
        for f in fotos:
            firmada = por_path.get(f["path"])
            if not firmada:
                raise ErrorFotosInicio(f"sin firma para la foto {f['id']}")   # antes que un set a medias
            f["url"] = f"{url}/storage/v1{firmada}"
            f["url_vence_en"] = vence
    return s


def bajar(s, carpeta):
    """Baja las fotos de un set firmado. Devuelve {pose: ruta} (motivacion_1, motivacion_2…). Verifica que sean JPEG."""
    os.makedirs(carpeta, mode=0o700, exist_ok=True)
    rutas, n = {}, 0
    for f in s.get("fotos") or []:
        if f["pose"] == "motivacion":
            n += 1
            nombre = f"motivacion_{n}"
        else:
            nombre = f["pose"]
        destino = os.path.join(carpeta, nombre + ".jpg")
        try:
            with urllib.request.urlopen(f["url"], timeout=ESPERA_S * 2) as r:
                datos = r.read()
        except (urllib.error.URLError, TimeoutError) as e:
            raise ErrorFotosInicio(f"bajar {nombre}: {e}") from None
        if datos[:3] != b"\xff\xd8\xff" or len(datos) != f.get("bytes", len(datos)):
            raise ErrorFotosInicio(f"bajar {nombre}: no es la foto guardada")
        with open(os.open(destino, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "wb") as a:
            a.write(datos)
        rutas[nombre] = destino
    return rutas


def leido(cliente_id, hasta):
    """Anota que el revisor leyó el set tal como estaba en `hasta` (el `actualizado_en` del set que bajó)."""
    return bool(_rpc("mypump_fotos_inicio_leido", p_cliente_id=cliente_id, p_hasta=hasta))


def pedir(cliente_id, por="entregas"):
    """Le abre la sección al alumno (con la palanca `fotos_inicio` prendida). Idempotente."""
    return _rpc("mypump_fotos_inicio_pedir", p_cliente_id=cliente_id, p_por=por)


def cerrar(cliente_id):
    """Después de la entrega: la app deja de mostrar la sección. Las fotos quedan."""
    return bool(_rpc("mypump_fotos_inicio_cerrar", p_cliente_id=cliente_id))


def main(argv):
    try:
        if len(argv) >= 1 and argv[0] == "pendientes":
            salida = pendientes(int(argv[1]) if len(argv) > 1 else 10)
        elif len(argv) == 2 and argv[0] == "set":
            salida = set_firmado(argv[1])
        elif len(argv) == 3 and argv[0] == "bajar":
            s = set_firmado(argv[1])
            if not s:
                raise ErrorFotosInicio("a ese alumno no se le pidieron fotos")
            salida = {"completo": s["completo"], "actualizado_en": s["actualizado_en"], "rutas": bajar(s, argv[2])}
        elif len(argv) == 3 and argv[0] == "leido":
            salida = leido(argv[1], argv[2])
        elif len(argv) == 2 and argv[0] == "pedir":
            salida = pedir(argv[1])
        elif len(argv) == 2 and argv[0] == "cerrar":
            salida = cerrar(argv[1])
        else:
            print(__doc__, file=sys.stderr)
            return 2
    except ErrorFotosInicio as e:
        print(str(e), file=sys.stderr)
        return 1
    print(json.dumps(salida, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
