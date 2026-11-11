"""Lo que corre solo, fuera de los pedidos: reintentos de lo pendiente, sello diario de la cadena de eventos, respaldo
fuera de Supabase y aviso si algo quedó trabado. Todo se puede correr las veces que haga falta sin duplicar nada."""
import json
import os
import threading
import time
from datetime import datetime, timezone

from . import reglas, sello


def ciclo(servicio) -> dict:
    """Cada pocos minutos: manda lo pendiente (sellos, correos, avisos) y sube al bucket lo que no subió."""
    r = servicio.despachar()
    r.update(servicio.almacen.reintentar_subidas())
    with servicio.base.conexion() as s:
        r["altas_vinculadas"] = s.f("vincular_leads_pendientes")
    return r


def traer_cadena(servicio, desde: int = 0):
    with servicio.base.conexion() as s:
        while True:
            tanda = s.f("cadena", desde, 2000)
            if not tanda:
                return
            yield from tanda
            desde = tanda[-1]["n"]


def verificar_cadena(servicio) -> dict:
    return reglas.verificar_cadena(list(traer_cadena(servicio)))


def diario(servicio, hoy: str = None) -> dict:
    """Una vez por día: 1) recalcula toda la cadena; 2) sella la cabeza con las autoridades externas (así nadie, ni
    nosotros, puede reescribir eventos anteriores a ese sello sin que se note); 3) deja en disco, fuera de Supabase,
    el registro completo y los sellos; 4) manda la cabeza sellada a la casilla de custodia."""
    cfg = servicio.cfg
    hoy = hoy or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    eventos = list(traer_cadena(servicio))
    v = reglas.verificar_cadena(eventos)
    res = {"dia": hoy, "eventos": len(eventos), "cadena_ok": v["ok"], "error": v["error"], "sellos": 0, "sellos_fallan": 0}
    carpeta = os.path.join(cfg.datos, "respaldo", hoy)
    os.makedirs(carpeta, exist_ok=True)
    with open(os.path.join(carpeta, "eventos.jsonl"), "w", encoding="utf-8") as f:
        for e in eventos:
            f.write(json.dumps(e, ensure_ascii=False, default=str) + "\n")
    adjuntos = []
    with servicio.base.conexion() as s:
        docs = s.f("respaldo_documentos", datetime(2000, 1, 1, tzinfo=timezone.utc))
        with open(os.path.join(carpeta, "documentos.json"), "w", encoding="utf-8") as f:
            json.dump(docs, f, ensure_ascii=False, indent=1, default=str)
        if eventos and v["ok"]:
            cabeza = eventos[-1]
            for tsa in cfg.tsas:
                try:
                    tsr, hora = sello.sellar(cabeza["hash"], tsa, cfg.openssl, cfg.ca_file)
                    s.f("registrar_sello", "cadena", None, cabeza["n"], cabeza["hash"], tsa, tsr, hora)
                    open(os.path.join(carpeta, f"cadena-{cabeza['n']}-{tsa}.tsr"), "wb").write(tsr)
                    adjuntos.append((f"cadena-{cabeza['n']}-{tsa}.tsr", "application/timestamp-reply", tsr))
                    res["sellos"] += 1
                except Exception:
                    res["sellos_fallan"] += 1
            res["cabeza"] = {"n": cabeza["n"], "hash": cabeza["hash"]}
        pend = s.f("pendientes_de_atencion", 30)
    res["pendientes"] = {k: len(x) for k, x in pend.items()}
    json.dump(res, open(os.path.join(carpeta, "resumen.json"), "w"), ensure_ascii=False, indent=1)
    if eventos and cfg.custodia and servicio.correo.configurado():
        texto = (f"Cadena de eventos de firma al {hoy}\nEventos: {len(eventos)}\nCadena íntegra: {'sí' if v['ok'] else 'NO — ' + str(v['error'])}\n"
                 f"Cabeza: n={eventos[-1]['n']} hash={eventos[-1]['hash']}\nSellos adjuntos: {len(adjuntos)}\nNo responder. No borrar.\n")
        r = servicio.correo.enviar(servicio.correo.armar(cfg.custodia, f"[custodia] cadena de eventos {hoy} n={eventos[-1]['n']}", texto, adjuntos))
        res["custodia"] = r["ok"]
    alerta = (not v["ok"]) or any(res["pendientes"].values())
    if alerta and cfg.aviso_interno and servicio.correo.configurado():
        servicio.correo.enviar(servicio.correo.armar(
            cfg.aviso_interno, "[pump-firma] hay algo para mirar",
            f"Cadena íntegra: {'sí' if v['ok'] else 'NO — ' + str(v['error'])}\nPendientes hace más de 30 min: {res['pendientes']}\n"
            "Detalle: /salud del servicio y RUNBOOK.md, sección «Si algo queda pendiente».\n"))
    return res


def en_segundo_plano(servicio, cada: int = 120, hora_diaria_utc: int = 6) -> threading.Thread:
    """Hilo del servicio. Si el servicio se reinicia no se pierde nada: lo pendiente vive en la base."""
    def bucle():
        ultimo_dia = None
        while True:
            try:
                ciclo(servicio)
                ahora = datetime.now(timezone.utc)
                dia = ahora.strftime("%Y-%m-%d")
                if dia != ultimo_dia and ahora.hour >= hora_diaria_utc:
                    marca = os.path.join(servicio.cfg.datos, "respaldo", dia, "resumen.json")
                    if not os.path.exists(marca):
                        r = diario(servicio, dia)
                        print(f"[pump-firma] diario {dia}: {r}", flush=True)
                    ultimo_dia = dia
            except Exception as e:
                print(f"[pump-firma] tareas: {type(e).__name__}: {e}", flush=True)
            time.sleep(cada)
    h = threading.Thread(target=bucle, daemon=True, name="pump-firma-tareas")
    h.start()
    return h


def main():
    """python -m firma.tareas ciclo | diario | verificar     (usa FIRMA_ENV, como el servicio)"""
    import sys
    from .almacen import Almacen
    from .base import Base
    from .config import Config
    from .correo import Correo
    from .servicio import Servicio
    cfg = Config()
    servicio = Servicio(cfg, Base(cfg.db_url), Almacen(cfg.datos, cfg.supabase_url, cfg.supabase_key),
                        Correo(cfg.smtp_host, cfg.smtp_puerto, cfg.smtp_usuario, cfg.smtp_clave, cfg.remitente, cfg.smtp_seguro))
    que = sys.argv[1] if len(sys.argv) > 1 else ""
    if que not in ("ciclo", "diario", "verificar", "respaldo"):
        raise SystemExit(main.__doc__)
    r = {"ciclo": lambda: ciclo(servicio), "diario": lambda: diario(servicio), "respaldo": lambda: diario(servicio),
         "verificar": lambda: verificar_cadena(servicio)}[que]()
    print(json.dumps(r, ensure_ascii=False, default=str))
    sys.exit(0 if r.get("ok", r.get("cadena_ok", True)) else 1)


if __name__ == "__main__":
    main()
