"""La cara web del servicio (FastAPI). Escucha solo en 127.0.0.1; a internet sale por el túnel de Cloudflare.

Arranque:  FIRMA_ENV=~/pump-firma-datos/firma.env  uvicorn firma.app:app --host 127.0.0.1 --port 8793 --no-access-log
(sin registro de accesos: el enlace personal va en la ruta y no tiene que quedar en ningún log)."""
import hmac
import os
import threading
import time
from collections import defaultdict, deque

from starlette.concurrency import run_in_threadpool
from fastapi import FastAPI, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse, Response

from . import VERSION, reglas
from .almacen import Almacen
from .base import Base
from .config import Config
from .correo import Correo
from .servicio import Rechazo, Servicio

WEB = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web")
CABECERAS = {
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "X-Robots-Tag": "noindex, nofollow",
    "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; "
                               "form-action 'none'; base-uri 'none'; frame-ancestors 'none'",
}


def crear_app(cfg: Config = None, servicio: Servicio = None, exigir_config: bool = True, despacho_en_linea: bool = False) -> FastAPI:
    cfg = cfg or Config()
    if servicio is None:
        if exigir_config and cfg.faltantes():
            raise SystemExit("pump-firma no arranca, falta configurar: " + "; ".join(cfg.faltantes()))
        servicio = Servicio(cfg, Base(cfg.db_url), Almacen(cfg.datos, cfg.supabase_url, cfg.supabase_key),
                            Correo(cfg.smtp_host, cfg.smtp_puerto, cfg.smtp_usuario, cfg.smtp_clave, cfg.remitente, cfg.smtp_seguro))
    app = FastAPI(title="pump-firma", version=VERSION, docs_url=None, redoc_url=None, openapi_url=None)
    golpes = defaultdict(deque)
    candado = threading.Lock()

    def origen(req: Request):
        ip = (req.headers.get("cf-connecting-ip") or (req.client.host if req.client else "") or "")[:80]
        return ip, (req.headers.get("user-agent") or "")[:400]

    def frenar(ip: str, tope: int = 90, ventana: int = 60) -> bool:
        ahora = time.monotonic()
        with candado:
            q = golpes[ip]
            while q and q[0] < ahora - ventana:
                q.popleft()
            if len(q) >= tope:
                return True
            q.append(ahora)
            if len(golpes) > 5000:
                golpes.clear()
        return False

    def interno(req: Request) -> bool:
        dado = req.headers.get("x-pump-firma-secreto") or ""
        return bool(cfg.secreto_interno) and hmac.compare_digest(dado.encode(), cfg.secreto_interno.encode())

    def despachar_luego(doc_id: str):
        def tarea():
            try:
                servicio.despachar(doc_id)
            except Exception as e:  # queda pendiente: lo levanta `tareas`
                print(f"[pump-firma] despacho de {doc_id} quedó pendiente: {type(e).__name__}: {e}", flush=True)
        if despacho_en_linea:  # solo en las pruebas
            return tarea()
        threading.Thread(target=tarea, daemon=True).start()

    @app.exception_handler(Rechazo)
    async def rechazo(req: Request, r: Rechazo):
        return JSONResponse({"error": r.codigo, **r.extra}, status_code=r.http)

    @app.middleware("http")
    async def cabeceras(req: Request, seguir):
        ip, _ = origen(req)
        if req.url.path.startswith(("/api/", "/f/")) and not req.url.path.startswith("/api/interno/") and frenar(ip):
            resp = JSONResponse({"error": "esperar"}, status_code=429)
        else:
            try:
                resp = await seguir(req)
            except Rechazo as r:
                resp = JSONResponse({"error": r.codigo, **r.extra}, status_code=r.http)
            except Exception as e:
                print(f"[pump-firma] error en {req.method} {req.url.path.split('/f/')[0]}: {type(e).__name__}: {e}", flush=True)
                resp = JSONResponse({"error": "interno"}, status_code=500)
        for k, v in CABECERAS.items():
            resp.headers.setdefault(k, v)
        if req.url.path.startswith("/api/app/"):
            o = req.headers.get("origin") or ""
            if o in cfg.origenes_app:
                resp.headers["Access-Control-Allow-Origin"] = o
                resp.headers["Access-Control-Allow-Headers"] = "content-type"
                resp.headers["Vary"] = "Origin"
        return resp

    async def cuerpo(req: Request, tope: int = 700_000) -> dict:
        crudo = await req.body()
        if len(crudo) > tope:
            raise Rechazo("interno", 413)
        try:
            import json
            d = json.loads(crudo or b"{}")
        except ValueError:
            raise Rechazo("interno", 400)
        if not isinstance(d, dict):
            raise Rechazo("interno", 400)
        return d

    # ── página ──
    @app.get("/f/{token}")
    def pagina(token: str):
        return FileResponse(os.path.join(WEB, "index.html"), media_type="text/html; charset=utf-8")

    @app.get("/verificar")
    def pagina_verificar():
        return FileResponse(os.path.join(WEB, "verificar.html"), media_type="text/html; charset=utf-8")

    @app.get("/static/{nombre}")
    def estatico(nombre: str):
        tipos = {"firma.js": "text/javascript; charset=utf-8", "firma.css": "text/css; charset=utf-8", "verificar.js": "text/javascript; charset=utf-8"}
        if nombre not in tipos:
            return JSONResponse({"error": "no"}, status_code=404)
        return FileResponse(os.path.join(WEB, nombre), media_type=tipos[nombre])

    @app.get("/f/{token}/documento.pdf")
    def pdf(token: str, req: Request):
        nombre, datos = servicio.pdf(token, *origen(req))
        return Response(datos, media_type="application/pdf", headers={"Content-Disposition": f'inline; filename="{nombre}"'})

    # ── API del firmante ──
    @app.post("/api/doc")
    async def api_doc(req: Request):
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.ver, d.get("t", ""), *origen(req))

    @app.post("/api/evento")
    async def api_evento(req: Request):
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.evento, d.get("t", ""), str(d.get("tipo", "")), d.get("datos") or {}, *origen(req))

    @app.post("/api/codigo")
    async def api_codigo(req: Request):
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.pedir_codigo, d.get("t", ""), str(d.get("proposito", "firma")), *origen(req))

    @app.post("/api/firmar")
    async def api_firmar(req: Request):
        d = await cuerpo(req)
        r = await run_in_threadpool(servicio.firmar, d.get("t", ""), d, *origen(req))
        despachar_luego(r["id"])
        return r

    @app.post("/api/revocar")
    async def api_revocar(req: Request):
        d = await cuerpo(req)
        r = await run_in_threadpool(servicio.revocar, d.get("t", ""), d, *origen(req))
        despachar_luego(None)
        return r

    @app.post("/api/baja")
    async def api_baja(req: Request):
        d = await cuerpo(req)
        r = await run_in_threadpool(servicio.pedir_baja, d.get("t", ""), d, *origen(req))
        despachar_luego(None)
        return r

    @app.post("/api/verificar")
    async def api_verificar(req: Request):
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.verificar, str(d.get("id") or "").strip() or None, str(d.get("sha256") or "").strip().lower() or None)

    @app.post("/api/verificar/pdf")
    async def api_verificar_pdf(archivo: UploadFile):
        datos = await archivo.read(12_000_001)
        if len(datos) > 12_000_000 or not datos.startswith(b"%PDF"):
            raise Rechazo("interno", 400)
        sha = reglas.sha256_hex(datos)
        return {"sha256": sha, **servicio.verificar(None, sha)}

    # ── app (Fase 2) ──
    @app.options("/api/app/documentos")
    def app_docs_preflight():
        return Response(status_code=204)

    @app.post("/api/app/documentos")
    async def app_docs(req: Request):
        d = await cuerpo(req)
        docs = await run_in_threadpool(servicio.docs_de_app, str(d.get("token") or ""))
        if docs is None:
            return JSONResponse({"error": "token"}, status_code=401)
        return {"documentos": docs}

    # ── interno (Apps Script, bot, operaciones): con secreto ──
    @app.post("/api/interno/crear")
    async def interno_crear(req: Request):
        if not interno(req):
            return JSONResponse({"error": "no autorizado"}, status_code=401)
        r = await run_in_threadpool(servicio.crear, await cuerpo(req), *origen(req))
        if r.get("documentos"):
            despachar_luego(None)  # sale el correo con el enlace
        return r

    @app.post("/api/interno/reenviar")
    async def interno_reenviar(req: Request):
        if not interno(req):
            return JSONResponse({"error": "no autorizado"}, status_code=401)
        d = await cuerpo(req)
        r = await run_in_threadpool(servicio.reenviar, str(d.get("documento_id", "")), d.get("cambios") or {}, *origen(req))
        if r.get("documentos"):
            despachar_luego(None)
        return r

    @app.post("/api/interno/anular")
    async def interno_anular(req: Request):
        if not interno(req):
            return JSONResponse({"error": "no autorizado"}, status_code=401)
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.anular, str(d.get("documento_id", "")), str(d.get("motivo", "")), *origen(req))

    @app.post("/api/interno/estado")
    async def interno_estado(req: Request):
        if not interno(req):
            return JSONResponse({"error": "no autorizado"}, status_code=401)
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.estado, d.get("lead_id"), d.get("email"), d.get("whatsapp"))

    @app.post("/api/interno/resolver_baja")
    async def interno_resolver_baja(req: Request):
        if not interno(req):
            return JSONResponse({"error": "no autorizado"}, status_code=401)
        d = await cuerpo(req)
        return await run_in_threadpool(servicio.resolver_baja, str(d.get("documento_id", "")), str(d.get("resultado", "")), str(d.get("nota", "")), *origen(req))

    @app.post("/api/interno/despachar")
    async def interno_despachar(req: Request):
        if not interno(req):
            return JSONResponse({"error": "no autorizado"}, status_code=401)
        return await run_in_threadpool(servicio.despachar)

    @app.get("/salud")
    def salud():
        return servicio.salud()

    return app


def app():  # uvicorn --factory firma.app:app
    from . import tareas
    cfg = Config()
    if cfg.faltantes():
        raise SystemExit("pump-firma no arranca, falta configurar: " + "; ".join(cfg.faltantes()))
    servicio = Servicio(cfg, Base(cfg.db_url), Almacen(cfg.datos, cfg.supabase_url, cfg.supabase_key),
                        Correo(cfg.smtp_host, cfg.smtp_puerto, cfg.smtp_usuario, cfg.smtp_clave, cfg.remitente, cfg.smtp_seguro))
    servicio.salud()  # si la base o el esquema no están, mejor no levantar
    tareas.en_segundo_plano(servicio)
    return crear_app(cfg, servicio)
