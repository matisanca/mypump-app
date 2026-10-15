#!/usr/bin/env python3
"""APL-08: el respaldo de Google de la nativa en el emulador, con `bmgr` y el transporte local (lo orquesta
emu-respaldo.sh). Lo que se espera (D14 en docs/NATIVA_ESTADO.md y res/xml/reglas_*.xml):

- el respaldo se lleva app_webview/ (la app vieja) MENOS sus cachés, legado/ menos legado/crudo/ y las preferencias;
- NO se lleva el token de la nativa: noBackupFilesDir (acceso.bin) no viaja nunca y la clave del Keystore no sale del
  teléfono; tampoco la carpeta de cada cuenta (files/MyPump/);
- restaurado en un teléfono nuevo, si vino de la app vieja la migración vuelve a correr y adopta el token que quedó en
  app_webview: el cliente entra sin pegar el link (D14, a propósito). Si nunca tuvo la app vieja, pide el link.

El token de `test-nativa-android` se lee ACÁ ADENTRO (como en emu_migracion.py) y nunca se imprime: los archivos de la
app se revisan en este proceso y en <salida>/ quedan solo rutas y tamaños, sin contenido.

Uso (siempre con `python3 -I`):
  token <puerto> <salida>                 siembra el token (y la cola vacía) en la Capacitor viva (por DevTools)
  inventario <serial> <salida> <etiqueta> los archivos de la app (ruta y tamaño) → inventario-<etiqueta>.json
  token-en <serial> <salida> <etiqueta>   en cuáles de esos archivos está el token (solo las rutas) → token-<etiqueta>.json
  pantalla <serial> <salida> <etiqueta>   qué muestra la app: la bienvenida o la cuenta → pantalla-<etiqueta>.json/.png
  saltar-hoja <serial>                    "Ahora no" en la hoja de permisos de la primera vez (para ver las pestañas)
  verificar <salida>                      junta todo y escribe informe.md; sale con 1 si algo no da
"""
import json
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import emu_migracion as mig  # noqa: E402  (mismo directorio; -I lo saca del path a propósito)

PKG = mig.PKG
CUENTA = mig.CUENTA   # la ÚNICA cuenta que usa esta prueba
# Lo que el respaldo NO tiene que llevar (reglas_extraccion.xml) y lo que sí.
NUNCA = ("no_backup/", "files/MyPump/", "files/legado/crudo/", "app_webview/Default/Cache/", "app_webview/Default/Code Cache/",
         "app_webview/Default/GPUCache/")
CACHES_WEBVIEW = ("app_webview/Default/Cache/", "app_webview/Default/Code Cache/", "app_webview/Default/GPUCache/")


def leer(salida, nombre, defecto=None):
    return mig.leer(salida, nombre, defecto)


def guardar(salida, nombre, obj):
    mig.guardar(salida, nombre, obj)


def token(puerto, salida):
    """`mypump_token` y la cola de la cuenta vacía, como la deja la Capacitor de cualquier cliente: sin nada para mandar.
    La cola vacía igual la borra la escritura de vuelta, y su clave (que lleva el token en el nombre) queda anotada en
    files/legado/estado.json: así se ve si eso viaja en el respaldo."""
    t = mig._token()
    items = json.loads(mig.cdp(puerto, "sembrar", json.dumps({"mypump_token": t, f"mypump_outbox_{t}": "[]"})))
    guardar(salida, "almacen-capacitor.json", {mig.tapar(k, t): len(v) for k, v in items.items()})
    print(f"token y cola vacía sembrados en la Capacitor ({len(items)} claves en su localStorage)")


def _archivos(serial):
    """Ruta (relativa a la carpeta de datos de la app) → (bytes, fecha de modificación en s), con run-as (la app de debug)."""
    r = mig._adb(serial, "shell", f"run-as {PKG} find . -type f -exec stat -c '%s %Y %n' {{}} +")
    out = {}
    for linea in r.splitlines():
        m = re.match(r"^(\d+) (\d+) \./(.+)$", linea.strip())
        if m:
            out[m.group(3)] = (int(m.group(1)), int(m.group(2)))
    return dict(sorted(out.items()))


def inventario(serial, salida, etiqueta):
    a = _archivos(serial)
    guardar(salida, f"inventario-{etiqueta}.json", {k: v[0] for k, v in a.items()})
    # Las fechas del leveldb de la app vieja: la migración lo reconoce por su "huella" (tamaño y fecha de sus archivos), y si
    # cambió desde la última corrida vuelve a leerlo (es lo que hace que un teléfono restaurado adopte el token).
    guardar(salida, f"fechas-{etiqueta}.json", {k: v[1] for k, v in a.items() if "Local Storage/leveldb/" in k})
    raices = sorted({k.split("/")[0] + ("/" + k.split("/")[1] if k.startswith("files/") and "/" in k[6:] else "") for k in a})
    print(f"inventario {etiqueta}: {len(a)} archivos, {sum(v[0] for v in a.values())} bytes; {', '.join(raices) or 'nada'}")


def token_en(serial, salida, etiqueta):
    """En cuáles archivos de la app está el token (en Latin-1 o UTF-16LE, como lo guarda Chromium). Solo las rutas."""
    t = mig._token()
    agujas = [t.encode("latin-1"), t.encode("utf-16-le")]
    a = leer(salida, f"inventario-{etiqueta}.json", {})
    con = []
    for ruta in a:
        b = mig._adb(serial, "exec-out", f"run-as {PKG} cat '{ruta}'", binario=True)
        if any(x in b for x in agujas):
            con.append(ruta)
    guardar(salida, f"token-{etiqueta}.json", con)
    print(f"el token está en {len(con)} de {len(a)} archivos ({etiqueta}): {con}")


def _volcado(serial):
    """Los nodos de la pantalla según uiautomator (ve los textos de Compose): [(texto, (x, y) del centro)]."""
    for _ in range(6):
        subprocess.run([mig.ADB, "-s", serial, "shell", "uiautomator", "dump", "/sdcard/mypump-respaldo.xml"], capture_output=True, timeout=60)
        xml = mig._adb(serial, "exec-out", "cat", "/sdcard/mypump-respaldo.xml")
        mig._adb(serial, "shell", "rm", "-f", "/sdcard/mypump-respaldo.xml")
        nodos = []
        for m in re.finditer(r'<node [^>]*>', xml):
            n = m.group(0)
            t = re.search(r' text="([^"]*)"', n)
            d = re.search(r' content-desc="([^"]*)"', n)
            b = re.search(r' bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
            centro = ((int(b.group(1)) + int(b.group(3))) // 2, (int(b.group(2)) + int(b.group(4))) // 2) if b else None
            for x in (t.group(1) if t else "", d.group(1) if d else ""):
                if x:
                    nodos.append((x, centro))
        if nodos:
            return nodos
        time.sleep(3)
    return []


def _hoja_primera_vez(textos):
    """La hoja de permisos de la primera vez (GEN-06): sale recién con una cuenta adentro."""
    return any(re.search(r"paso \d de \d", x) for x in textos)


def saltar_hoja(serial):
    """Toca "Ahora no" en la hoja de la primera vez (salud y avisos) hasta que se va: para ver las pestañas."""
    for _ in range(4):
        nodos = _volcado(serial)
        if not _hoja_primera_vez([x for x, _ in nodos]):
            return
        boton = next((c for x, c in nodos if x == "Ahora no" and c), None)
        if not boton:
            return
        mig._adb(serial, "shell", "input", "tap", str(boton[0]), str(boton[1]))
        time.sleep(2)


def pantalla(serial, salida, etiqueta):
    """Qué muestra la app: la bienvenida ("Entrá con tu link") o la cuenta (las pestañas, o la hoja de la primera vez
    encima, que sale recién con una cuenta). Guarda la captura."""
    textos = [x for x, _ in _volcado(serial)]
    png = mig._adb(serial, "exec-out", "screencap", "-p", binario=True)
    with open(os.path.join(salida, f"pantalla-{etiqueta}.png"), "wb") as f:
        f.write(png)
    pestanas = all(any(x.startswith(p) for x in textos) for p in ("Entreno", "Dieta", "Revisión"))
    hoja = _hoja_primera_vez(textos)
    r = {"bienvenida": "Entrá con tu link" in textos, "pestanas": pestanas, "hoja_primera_vez": hoja, "cuenta": pestanas or hoja,
         "textos": textos[:40]}
    guardar(salida, f"pantalla-{etiqueta}.json", r)
    que = ("la bienvenida (pide el link)" if r["bienvenida"] else "las pestañas (entró)" if pestanas
           else "la hoja de la primera vez (entró)" if hoja else f"otra cosa: {textos[:8]}")
    print(f"pantalla {etiqueta}: {que}")


def _hay(a, prefijo):
    return [k for k in a if k.startswith(prefijo)]


def verificar(salida):
    filas = []

    def chequeo(nombre, ok, detalle=""):
        filas.append((nombre, bool(ok), str(detalle)))

    def registro_nuevo(e):
        """Las líneas del registro de la migración que escribió el teléfono "nuevo" (después de restaurar)."""
        antes = open(os.path.join(salida, f"registro-{e}-restaurado.txt"), encoding="utf-8").read().splitlines() \
            if os.path.exists(os.path.join(salida, f"registro-{e}-restaurado.txt")) else []
        despues = open(os.path.join(salida, f"registro-{e}.txt"), encoding="utf-8").read().splitlines() \
            if os.path.exists(os.path.join(salida, f"registro-{e}.txt")) else []
        return despues[len(antes):]

    def bmgr(e):
        p = os.path.join(salida, f"bmgr-{e}.txt")
        return open(p, encoding="utf-8").read() if os.path.exists(p) else ""

    informacion = []
    for e, titulo in (("A", "A · Con la app vieja (D14)"), ("B", "B · Solo la nativa")):
        antes = leer(salida, f"inventario-{e}-antes.json")
        if antes is None:
            continue
        rest = leer(salida, f"inventario-{e}-restaurado.json", {})
        abierta = leer(salida, f"inventario-{e}-abierta.json", {})
        tok_antes = leer(salida, f"token-{e}-antes.json", [])
        tok_rest = leer(salida, f"token-{e}-restaurado.json", [])
        pant = leer(salida, f"pantalla-{e}.json", {})
        nuevo = registro_nuevo(e)
        como = open(os.path.join(salida, f"restauracion-{e}.txt"), encoding="utf-8").read().strip() \
            if os.path.exists(os.path.join(salida, f"restauracion-{e}.txt")) else "?"
        p = f"{e} ·"
        chequeo(f"{p} antes del respaldo, el token de la nativa en no_backup/acceso.bin y la cuenta en files/MyPump/",
                "no_backup/acceso.bin" in antes and _hay(antes, "files/MyPump/cuenta-"),
                f"{len(_hay(antes, 'files/MyPump/'))} archivos en files/MyPump/")
        if e == "A":
            chequeo(f"{p} antes del respaldo: la app vieja en app_webview/ (con el token, D14) y la migración en files/legado/",
                    _hay(antes, "app_webview/") and any(k.startswith("app_webview/") for k in tok_antes) and "files/legado/estado.json" in antes,
                    f"{len(_hay(antes, 'app_webview/'))} archivos en app_webview/, {len(_hay(antes, 'files/legado/crudo/'))} en legado/crudo/, "
                    f"{len([k for k in antes if k.startswith(CACHES_WEBVIEW)])} de cachés del WebView")
        else:
            chequeo(f"{p} antes del respaldo: sin app_webview/ (nunca tuvo la app vieja)", not _hay(antes, "app_webview/"))
        chequeo(f"{p} bmgr backupnow: Success", f"Package {PKG} with result: Success" in bmgr(e), bmgr(e).strip().replace("\n", " · ")[:150])
        chequeo(f"{p} volvió algo (restauración: {como})", bool(rest), f"{len(rest)} archivos")
        if e == "A":
            leveldb = [k for k in rest if k.startswith("app_webview/") and k.endswith("leveldb/CURRENT")]
            chequeo(f"{p} volvió app_webview/ con el leveldb de la app vieja", leveldb, f"{leveldb}")
            chequeo(f"{p} volvió files/legado/ (el libro de la migración: no se vuelve a mandar lo que ya se mandó)",
                    "files/legado/estado.json" in rest and "files/legado/libro.json" in rest)
        chequeo(f"{p} volvieron las preferencias (shared_prefs/)", _hay(rest, "shared_prefs/"), f"{_hay(rest, 'shared_prefs/')}")
        no = [k for k in rest if k.startswith(NUNCA)]
        chequeo(f"{p} NO volvió nada de: {', '.join(NUNCA)}", not no and rest, f"{no}" if no else
                f"antes había {len([k for k in antes if k.startswith(NUNCA)])} archivos ahí")
        if e == "A":
            # D14: el token de la app vieja viaja en su almacenamiento (app_webview/). La migración lo copia además a su
            # libro (files/legado/: las claves de la escritura de vuelta y las colas pendientes llevan el token en el nombre),
            # que viaja para no volver a mandar lo ya mandado. Es el MISMO token de la app vieja, que ya va en app_webview/.
            fuera = [k for k in tok_rest if not k.startswith(("app_webview/", "files/legado/"))]
            chequeo(f"{p} el token solo volvió en lo de la app vieja (app_webview/ y el libro de la migración, D14), nunca en lo de la nativa",
                    not fuera, f"con el token: {tok_rest}")
        else:
            chequeo(f"{p} ningún archivo restaurado tiene el token", not tok_rest and rest, f"{tok_rest}")
        fase_l = [l for l in nuevo if "Fase L corrida" in l]
        pestanas = leer(salida, f"pantalla-{e}-pestanas.json", {})
        if e == "A":
            chequeo(f"{p} al abrir, la migración vuelve a correr y adopta el token de app_webview/ (D14: entra sin pegar el link)",
                    any("token adoptado" in l for l in fase_l) and pant.get("cuenta") and not pant.get("bienvenida")
                    and "no_backup/acceso.bin" in abierta and _hay(abierta, "files/MyPump/cuenta-"),
                    f"{fase_l[:1]}; pantalla: {'pestañas' if pant.get('pestanas') else 'la hoja de la primera vez' if pant.get('hoja_primera_vez') else pant.get('textos', [])[:5]}"
                    f"{', después las pestañas' if pestanas.get('pestanas') else ''}")
            m = re.search(r"cola (\d+), por validar (\d+)", fase_l[0]) if fase_l else None
            chequeo(f"{p} y no vuelve a mandar nada: el libro restaurado ya tenía lo de la app vieja",
                    m is not None and m.groups() == ("0", "0"), f"{fase_l[:1]}")
        else:
            chequeo(f"{p} al abrir, pide el link (la bienvenida) y no hay token guardado",
                    pant.get("bienvenida") and not pant.get("cuenta") and "no_backup/acceso.bin" not in abierta,
                    f"pantalla {pant.get('textos', [])[:6]}")
        informacion.append(f"- {titulo}: volvieron {len(rest)} archivos ({sum(rest.values())} bytes) de {len(antes)} ({sum(antes.values())} bytes). "
                           f"Restauración: {como}. Con el token antes del respaldo: {tok_antes}; restaurados: {tok_rest}.")
        f_antes, f_rest = leer(salida, f"fechas-{e}-antes.json", {}), leer(salida, f"fechas-{e}-restaurado.json", {})
        if f_antes:
            informacion.append(f"  - fechas del leveldb de la app vieja (s desde 1970), antes → restaurado: "
                               f"{ {k.rsplit('/', 1)[-1]: (f_antes.get(k), f_rest.get(k)) for k in sorted(set(f_antes) | set(f_rest))} }")
        informacion.append(f"  - shared_prefs restauradas: {_hay(rest, 'shared_prefs/')}")
        informacion.append(f"  - lo demás que volvió (fuera de app_webview/, files/legado/ y shared_prefs/): "
                           f"{[k for k in rest if not k.startswith(('app_webview/', 'files/legado/', 'shared_prefs/'))]}")
        informacion.append(f"  - registro de la migración en el teléfono nuevo: {nuevo}")

    modo = open(os.path.join(salida, "modo.txt"), encoding="utf-8").read().strip() if os.path.exists(os.path.join(salida, "modo.txt")) else "?"
    lineas = ["# Respaldo de Google en el emulador de Android (APL-08, D14)", "",
              f"- Cuenta: `{CUENTA}`. Transporte: `com.android.localtransport/.LocalTransport` (`bmgr backupnow`, sin cuenta de Google). "
              f"Modo: {modo}.",
              *informacion, "", "| Chequeo | | Detalle |", "|---|---|---|"]
    for n, ok, d in filas:
        lineas.append(f"| {n} | {'✅' if ok else '❌'} | {d[:220]} |")
    with open(os.path.join(salida, "informe.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lineas) + "\n")
    malos = [n for n, ok, _ in filas if not ok]
    print(f"{len(filas) - len(malos)}/{len(filas)} chequeos OK")
    for n in malos:
        print("  ✗", n)
    return 1 if malos else 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    a = argv[2:]
    if cmd == "token" and len(a) == 2:
        token(*a)
    elif cmd == "inventario" and len(a) == 3:
        inventario(*a)
    elif cmd == "token-en" and len(a) == 3:
        token_en(*a)
    elif cmd == "pantalla" and len(a) == 3:
        pantalla(*a)
    elif cmd == "saltar-hoja" and len(a) == 1:
        saltar_hoja(*a)
    elif cmd == "verificar" and len(a) == 1:
        return verificar(*a)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
