#!/usr/bin/env python3
"""Los avisos locales que MyPump tiene agendados en un simulador (NOT-03: el del domingo, id 1002).

Desde la prueba de interfaz no se ven: iOS los guarda en la carpeta de avisos del simulador, archivados con
NSKeyedArchiver. `Library.plist` dice qué carpeta es de cada app y `PendingNotifications.plist` trae lo agendado.
Solo lee. Uso: scripts/nativa/avisos_programados.py <udid> [bundle]
"""
import os
import plistlib
import sys


def desarchivar(ruta):
    d = plistlib.load(open(ruta, "rb"))
    objs = d["$objects"]

    def r(x):
        if isinstance(x, plistlib.UID):
            return r(objs[x.data])
        if isinstance(x, dict):
            if "NS.keys" in x:
                return {r(k): r(v) for k, v in zip(x["NS.keys"], x["NS.objects"])}
            if "NS.objects" in x:
                return [r(v) for v in x["NS.objects"]]
            if "NS.string" in x:
                return x["NS.string"]
            return {k: r(v) for k, v in x.items() if k != "$class"}
        return x

    return r(list(d["$top"].values())[0])


def main():
    udid = sys.argv[1]
    bundle = sys.argv[2] if len(sys.argv) > 2 else "com.pumpteam.mypump"
    base = os.path.expanduser(f"~/Library/Developer/CoreSimulator/Devices/{udid}/data/Library/UserNotifications")
    carpeta = desarchivar(os.path.join(base, "Library.plist")).get(bundle)
    pendientes = os.path.join(base, carpeta or "-", "PendingNotifications.plist")
    if not carpeta or not os.path.exists(pendientes):
        print(f"{bundle}: nada agendado")
        return
    dias = {1: "domingo", 2: "lunes", 3: "martes", 4: "miércoles", 5: "jueves", 6: "viernes", 7: "sábado"}
    for a in desarchivar(pendientes):
        c = a.get("TriggerDateComponents") or {}
        if a.get("UNNotificationTriggerType") == "Calendar":
            if c.get('NS.year') and c.get('NS.month') and c.get('NS.day'):
                # Un aviso de una vez (el domingo desde el 15-oct): con la fecha.
                cuando = f"{c['NS.year']}-{c['NS.month']:02d}-{c['NS.day']:02d} {c.get('NS.hour', 0):02d}:{c.get('NS.minute', 0):02d}"
            else:
                cuando = f"{dias.get(c.get('NS.weekday'), '?')} {c.get('NS.hour', 0):02d}:{c.get('NS.minute', 0):02d}"
        else:
            cuando = f"en {a.get('TriggerTimeInterval')} s"
        print(f"{a.get('AppNotificationIdentifier')} · {cuando}{' · se repite' if a.get('TriggerRepeats') else ''}"
              f" · {a.get('AppNotificationTitle')!r} · {a.get('AppNotificationMessage')!r}"
              f" · destino={(a.get('UNNotificationUserInfo') or {}).get('destino')}")


if __name__ == "__main__":
    main()
