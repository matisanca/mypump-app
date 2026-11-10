"""El servicio de firma, sin HTTP: cada método es una operación completa. `app.py` solo traduce pedidos web.

Orden de una firma (no se altera): casillas → identidad → dibujo → código → hora del servidor → PDF final →
guardar → `contrato.firmar` (atómico: marca el código, cambia el estado, agrega el evento y deja en la bandeja de
salida la copia al firmante, la copia de custodia y el aviso al bot). Después, fuera del pedido: sello de tiempo
externo, correos y aviso. Si algo de eso falla, queda pendiente y lo reintenta `tareas`."""
import json
import os
import secrets
import urllib.request
import uuid
from datetime import datetime, timedelta

from . import reglas, render, sello, textos
from .base import J


class Rechazo(Exception):
    """Algo que el firmante puede corregir. `codigo` es la clave de textos.ERRORES."""

    def __init__(self, codigo: str, http: int = 400, **extra):
        super().__init__(codigo)
        self.codigo, self.http, self.extra = codigo, http, extra


def _ts(v):
    return v if isinstance(v, datetime) or v is None else datetime.fromisoformat(v)


QUE_PASO = {
    "creado": "Se generó el documento con los datos del alta",
    "abierto": "Abrió el documento",
    "fin_lectura": "Llegó al final del documento",
    "pdf_visto": "Abrió el PDF del documento",
    "identidad_escrita": "Escribió su nombre y su documento",
    "codigo_emitido": "Pidió el código, enviado a su correo",
    "codigo_incorrecto": "Escribió un código incorrecto",
    "codigo_validado": "Validó el código recibido en su correo",
}


class Servicio:
    def __init__(self, cfg, base, almacen, correo):
        self.cfg, self.base, self.almacen, self.correo = cfg, base, almacen, correo
        self._plantillas = {}

    # ── utilidades ──
    def url_doc(self, doc) -> str:
        return f"{self.cfg.url_publica}/f/{reglas.token_de(self.cfg.secreto, doc['id'], doc['token_n'])}"

    def _url_verificar(self, doc) -> str:
        return f"{self.cfg.url_publica}/verificar"

    def _plantilla(self, s, plantilla_id: str) -> dict:
        if plantilla_id not in self._plantillas:  # una versión no cambia nunca: se puede guardar en memoria
            p = s.f("plantilla", plantilla_id)
            if not p:
                raise RuntimeError(f"plantilla {plantilla_id} inexistente")
            if reglas.sha256_hex(p["fuente_md"].encode()) != p["fuente_sha256"]:
                raise RuntimeError(f"plantilla {plantilla_id}: el texto no coincide con su hash")
            self._plantillas[plantilla_id] = p
        return self._plantillas[plantilla_id]

    def _doc(self, s, token: str) -> dict:
        if not token or not (40 <= len(token) <= 64) or not all(c in "0123456789abcdef" for c in token):
            raise Rechazo("enlace", 404)
        doc = s.f("doc_por_token", reglas.token_sha(token))
        if not doc:
            raise Rechazo("enlace", 404)
        if doc["estado"] == "anulado":
            raise Rechazo("anulado", 410)
        return doc

    def _firma_prestador(self):
        try:
            return open(self.cfg.firma_prestador, "rb").read()
        except OSError:
            return None

    def _valores_base(self, tipo, campos) -> render.Valores:
        # El del exterior lleva la firma del prestador impresa, como en la plantilla vigente (v5).
        return render.Valores(tipo, campos, firma_prestador_png=self._firma_prestador() if tipo == "servicio_ext" else None)

    def _texto_casilla(self, tipo, clave, pagina) -> str:
        if clave == "inicio_anticipado":
            pieza = next(f for f in pagina["firmas"] if f["pieza"] == "inicio_anticipado")
            return _sin_html(pieza["html"])
        t = textos.CASILLAS[clave]
        return t[tipo] if isinstance(t, dict) else t

    # ── alta ──
    def crear(self, alta: dict, ip: str, ua: str, reemplaza: str = None) -> dict:
        email = reglas.limpiar_texto(alta.get("email", ""), 200).lower()
        if not _mail_ok(email):
            return {"ok": False, "error": "mail_invalido", "documentos": []}
        if not isinstance(alta.get("residente_argentina"), bool):
            return {"ok": False, "error": "falta_residente_argentina", "documentos": []}
        residente = alta["residente_argentina"]
        tipos = ["servicio_ar", "consentimiento_ar"] if residente else ["servicio_ext"]
        if alta.get("solo"):
            tipos = [t for t in tipos if t in alta["solo"]]
        variante_servicio = reglas.variante_de(alta.get("pais", ""), residente)
        ref = reglas.alta_ref(alta)
        invitar = alta.get("invitar") is not False  # el correo con el enlace, como hacía BoldSign
        salida, errores = [], []
        with self.base.conexion() as s:
            vivos = {d["tipo"]: d for d in s.f("docs_por_alta", ref)}
            for tipo in tipos:
                reemplazar_id = reemplaza if (reemplaza and tipo == alta.get("_tipo_reemplazo")) else None
                campos = reglas.campos_de_alta(tipo, alta)
                falta = reglas.faltantes(tipo, campos)
                if tipo in vivos and not reemplazar_id:
                    vivo = vivos[tipo]
                    igual = vivo["campos"] == reglas.campos_de_alta(tipo, alta) and vivo["firmante_email"].lower() == email
                    if vivo["estado"] != "pendiente":
                        # ya firmado: no se toca. Si el formulario vino con otros datos, se dice (no pasa en silencio).
                        salida.append(self._resumen(vivo, "ya_firmado"))
                        if not igual:
                            errores.append({"tipo": tipo, "error": "ya_firmado_con_otros_datos"})
                        self._frenada_resuelta(s, ref, vivo, tipo)
                        continue
                    if igual:
                        if invitar:
                            s.f("invitar", vivo["id"])  # por si el primer intento se cortó antes de dejar la invitación
                        salida.append(self._resumen(vivo, "ya_existia"))
                        self._frenada_resuelta(s, ref, vivo, tipo)
                        continue
                    if not falta:  # incompleto no reemplaza nada: el enlace que ya tiene sigue sirviendo
                        reemplazar_id = vivo["id"]  # el formulario se reenvió corregido: el pendiente viejo se anula y nace otro
                elif not reemplazar_id and not falta:
                    for viejo in s.f("pendientes_de_email", email, tipo, ref):  # otro envío anterior, sin firmar
                        s.f("anular", viejo, "reemplazado por un alta nueva", ip, ua)
                pl = s.f("plantilla_vigente", tipo)
                if not pl:
                    errores.append({"tipo": tipo, "error": "sin_plantilla_vigente"})
                    break
                if falta:
                    errores.append({"tipo": tipo, "error": "faltan_datos", "campos": falta})
                    # No se frena en silencio: queda anotada y se avisa qué falta, hasta que llegue completa.
                    try:
                        s.f("alta_frenada", ref, tipo, campos.get(_k_nombre(tipo)) or "", email,
                            reglas.limpiar_texto(alta.get("whatsapp", ""), 40), list(falta), ip, ua)
                    except Exception as e:  # la respuesta al formulario sale igual; esto tiene que verse en el log
                        errores[-1]["sin_anotar"] = True
                        print(f"[pump-firma] NO pude anotar el alta frenada: {type(e).__name__}: {e}", flush=True)
                    break  # sin contrato no sale el consentimiento, como hoy
                doc_id = str(uuid.uuid4())
                pdf = render.pdf_documento(pl["fuente_md"], self._valores_base(tipo, campos))
                sha = reglas.sha256_hex(pdf)
                ruta = f"{doc_id}/a-firmar-{sha[:16]}.pdf"
                self.almacen.guardar(ruta, pdf)
                variante = "AR" if tipo != "servicio_ext" else variante_servicio
                evento = reglas.json_canonico({"plantilla": pl["id"], "fuente_sha256": pl["fuente_sha256"], "pdf_base_sha256": sha,
                                               "campos": campos, "variante": variante, "origen": reglas.limpiar_texto(alta.get("origen", "alta"), 40)})
                r = s.f("crear_documento", doc_id, tipo, pl["id"], ref, alta.get("lead_id"), campos[_k_nombre(tipo)], email,
                        reglas.limpiar_texto(alta.get("whatsapp", ""), 40), reglas.limpiar_texto(alta.get("pais", ""), 80), variante,
                        campos, reglas.token_sha(reglas.token_de(self.cfg.secreto, doc_id, 1)), ruta, sha,
                        reemplazar_id, ip, ua, evento)
                if r["resultado"] == "no_reemplazable":
                    errores.append({"tipo": tipo, "error": "ya_firmado_no_se_reemplaza"})
                    break
                if invitar:
                    s.f("invitar", r["documento"]["id"])
                salida.append(self._resumen(r["documento"], r["resultado"]))
        return {"ok": not errores, "alta_ref": ref, "documentos": salida, "errores": errores}

    def _frenada_resuelta(self, s, ref, doc, tipo):
        """El documento de esta alta existe: si había quedado una frenada abierta (un reenvío incompleto), se cierra."""
        try:
            s.f("altas_frenadas_resolver", ref, doc["firmante_email"], doc.get("firmante_whatsapp") or "", tipo)
        except Exception as e:
            print(f"[pump-firma] no pude cerrar el alta frenada: {type(e).__name__}: {e}", flush=True)

    def _resumen(self, doc, resultado=None) -> dict:
        r = {"id": doc["id"], "tipo": doc["tipo"], "estado": doc["estado"], "url": self.url_doc(doc),
             "firmado_en": doc.get("firmado_en"), "email": doc["firmante_email"]}
        if resultado:
            r["resultado"] = resultado
        return r

    def resolver_baja(self, doc_id: str, resultado: str, nota: str, ip: str, ua: str) -> dict:
        """Lo carga el equipo cuando el pedido de baja se resolvió: 'sigue' (continúa y se destraba la agenda) o 'terminado'."""
        with self.base.conexion() as s:
            return {"resultado": s.f("resolver_baja", doc_id, resultado, reglas.limpiar_texto(nota or "", 500), ip, ua)["resultado"]}

    def reenviar(self, doc_id: str, cambios: dict, ip: str, ua: str, _solo: bool = False) -> dict:
        """Mail mal escrito o datos mal: anula el pendiente y crea otro con link nuevo. Un firmado no se toca."""
        with self.base.conexion() as s:
            viejo = s.f("doc_por_id", doc_id)
        if not viejo:
            return {"ok": False, "error": "no_existe"}
        if viejo["estado"] != "pendiente":
            return {"ok": False, "error": "no_reemplazable", "estado": viejo["estado"]}
        # Un dato de la persona mal cargado (sobre todo el correo) está mal en TODOS sus documentos pendientes: si se
        # corrige en uno solo, el otro queda firmable por quien reciba el correo equivocado.
        de_persona = {k: v for k, v in (cambios or {}).items() if k in ("email", "nombre", "apellido", "dni", "domicilio", "whatsapp", "pais") and v is not None}
        if de_persona and not _solo:
            with self.base.conexion() as s:
                hermanos = [d for d in s.f("docs_por_alta", viejo["alta_ref"]) if d["estado"] == "pendiente" and d["id"] != doc_id]
            total = self.reenviar(doc_id, cambios, ip, ua, _solo=True)
            for h in hermanos:
                r = self.reenviar(h["id"], de_persona, ip, ua, _solo=True)
                total["documentos"] += r.get("documentos", [])
                total["errores"] = total.get("errores", []) + r.get("errores", [])
                total["ok"] = total["ok"] and r.get("ok", False)
            return total
        c, tipo = viejo["campos"], viejo["tipo"]
        pre = "m" if tipo == "consentimiento_ar" else "c"
        alta = {"alta_ref": viejo["alta_ref"], "lead_id": viejo.get("lead_id"), "email": viejo["firmante_email"],
                "whatsapp": viejo.get("firmante_whatsapp") or "", "pais": viejo.get("pais") or c.get("cPais", ""),
                "residente_argentina": tipo != "servicio_ext", "nombre": c.get(_k_nombre(tipo), ""), "apellido": "",
                "dni": c.get(pre + "Dni" + ("" if pre == "m" else "1"), ""), "domicilio": c.get(pre + "Domic", ""),
                "plan": c.get("cPlan", ""), "objetivo": c.get("cObjetivo", ""), "precio": c.get("cPrecio", ""),
                "solo": [tipo], "_tipo_reemplazo": tipo, "origen": "reenvio"}
        for k in ("email", "nombre", "apellido", "dni", "domicilio", "pais", "plan", "objetivo", "precio", "whatsapp"):
            if cambios.get(k) is not None:
                alta[k] = cambios[k]
        return self.crear(alta, ip, ua, reemplaza=doc_id)

    def anular(self, doc_id: str, motivo: str, ip: str, ua: str) -> dict:
        with self.base.conexion() as s:
            return {"resultado": s.f("anular", doc_id, motivo, ip, ua)}

    # ── lo que ve el firmante ──
    def ver(self, token: str, ip: str, ua: str) -> dict:
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            tipo, variante = doc["tipo"], doc["variante"]
            comun = {"estado": doc["estado"], "tipo": tipo, "variante": variante, "id": doc["id"],
                     "correo": reglas.mail_tapado(doc["firmante_email"]), "contacto": textos.CORREO_CONTACTO,
                     "errores": textos.ERRORES}
            pl = self._plantilla(s, doc["plantilla_id"])
            if doc["estado"] in ("firmado", "revocado"):
                comun.update({"titulo": pl["titulo"], "firmado_en": doc["firmado_en"], "revocado_en": doc.get("revocado_en"),
                              "baja_pedida_en": doc.get("baja_pedida_en"), "sha256": doc["pdf_final_sha256"],
                              "puede_revocar": tipo == "consentimiento_ar" and doc["estado"] == "firmado",
                              "baja": textos.BAJA[variante] if tipo != "consentimiento_ar" and doc["estado"] == "firmado" else None})
                return comun
            pagina = render.para_pagina(pl["fuente_md"], self._valores_base(tipo, doc["campos"]))
            casillas = [{"clave": k, "obligatoria": ob, "texto": self._texto_casilla(tipo, k, pagina)}
                        for k, ob in reglas.casillas_de(tipo, variante).items()]
            pre = "m" if tipo == "consentimiento_ar" else "c"
            comun.update({"titulo": pagina["titulo"], "subtitulo": pagina["subtitulo"], "cuerpo_html": pagina["cuerpo_html"],
                          "firmas": pagina["firmas"], "casillas": casillas, "boton": textos.BOTON[(tipo, variante)],
                          "aviso_medio": textos.AVISO_MEDIO, "aviso_es": textos.AVISO_ES if (tipo, variante) == ("servicio_ext", "ES") else None,
                          "pide_domicilio": not (doc["campos"].get(pre + "Domic") or "").strip(),
                          "documento_rotulo": "DNI" if tipo != "servicio_ext" else "Documento",
                          "pdf_sha256": doc["pdf_base_sha256"]})
            s.f("evento_de_pagina", doc["id"], "abierto", ip, ua, reglas.json_canonico(
                {"cuerpo_sha256": reglas.sha256_hex(pagina["cuerpo_html"].encode()), "pdf_base_sha256": doc["pdf_base_sha256"]}))
            return comun

    def pdf(self, token: str, ip: str, ua: str):
        """Devuelve (nombre, bytes): el firmado (o el de revocación) si ya se firmó; si no, el que se va a firmar."""
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            nombre = textos.ARCHIVO[doc["tipo"]]
            if doc["estado"] == "revocado":
                return nombre + " - revocado.pdf", self.almacen.leer(doc["pdf_revocacion_path"], doc["pdf_revocacion_sha256"])
            if doc["estado"] == "firmado":
                return nombre + " - firmado.pdf", self.almacen.leer(doc["pdf_final_path"], doc["pdf_final_sha256"])
            s.f("evento_de_pagina", doc["id"], "pdf_visto", ip, ua, reglas.json_canonico({"pdf_base_sha256": doc["pdf_base_sha256"]}))
            return nombre + " - a firmar.pdf", self.almacen.leer(doc["pdf_base_path"], doc["pdf_base_sha256"])

    def evento(self, token: str, tipo: str, datos: dict, ip: str, ua: str) -> dict:
        permitidos = {"fin_lectura": (), "casilla": ("casilla", "valor"), "identidad_escrita": ()}
        if tipo not in permitidos:
            raise Rechazo("interno", 400)
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            if doc["estado"] != "pendiente":
                return {"ok": True}
            limpio = {}
            if tipo == "casilla":
                clave = str((datos or {}).get("casilla", ""))
                if clave not in reglas.casillas_de(doc["tipo"], doc["variante"]):
                    raise Rechazo("interno", 400)
                limpio = {"casilla": clave, "valor": (datos or {}).get("valor") is True}
            s.f("evento_de_pagina", doc["id"], tipo, ip, ua, reglas.json_canonico(limpio))
            return {"ok": True}

    def pedir_codigo(self, token: str, proposito: str, ip: str, ua: str) -> dict:
        if proposito not in ("firma", "revocacion", "baja"):
            raise Rechazo("interno", 400)
        if not self.correo.configurado():
            raise Rechazo("correo", 503)
        codigo = f"{secrets.randbelow(1_000_000):06d}"
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            r = s.f("emitir_codigo", doc["id"], proposito, reglas.codigo_hmac(self.cfg.secreto, doc["id"], proposito, codigo),
                    self.cfg.minutos_codigo * 60, ip, ua)
            if r["resultado"] == "esperar":
                raise Rechazo("esperar", 429, segundos=r.get("segundos"))
            if r["resultado"] == "documento_vencido":
                raise Rechazo("documento_vencido", 410)
            if r["resultado"] != "emitido":
                raise Rechazo("limite" if r["resultado"] == "limite" else "interno", 429 if r["resultado"] == "limite" else 409)
            asunto, texto = textos.mail_codigo(_pila(doc["firmante_nombre"]), doc["tipo"], proposito, codigo, self.cfg.minutos_codigo)
            cid = s.f("correo_nuevo", doc["id"], "codigo", doc["firmante_email"])
            res = self.correo.enviar(self.correo.armar(doc["firmante_email"], asunto, texto))
            s.f("correo_resultado", cid, res["ok"], res["message_id"], res["respuesta"])
            s.f("registrar_evento", doc["id"], "codigo_enviado" if res["ok"] else "codigo_no_enviado", ip, ua,
                reglas.json_canonico({"codigo": r["codigo"], "message_id": res["message_id"], "respuesta": res["respuesta"][:200]}))
            if not res["ok"]:
                raise Rechazo("correo", 502)
            return {"ok": True, "correo": reglas.mail_tapado(doc["firmante_email"]), "minutos": self.cfg.minutos_codigo}

    def _validar_codigo(self, s, doc, proposito, codigo, ip, ua) -> str:
        if not reglas.codigo_valido_forma(str(codigo or "").strip()):
            raise Rechazo("incorrecto")
        r = s.f("validar_codigo", doc["id"], proposito, reglas.codigo_hmac(self.cfg.secreto, doc["id"], proposito, str(codigo).strip()), ip, ua)
        if r["resultado"] != "ok":
            raise Rechazo(r["resultado"], quedan=r.get("quedan"))
        return r["codigo"]

    # ── la firma ──
    def firmar(self, token: str, cuerpo: dict, ip: str, ua: str) -> dict:
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            if doc["estado"] in ("firmado", "revocado"):
                return self._firmado(doc, repetido=True)
            tipo, variante = doc["tipo"], doc["variante"]
            pl = self._plantilla(s, doc["plantilla_id"])
            pagina = render.para_pagina(pl["fuente_md"], self._valores_base(tipo, doc["campos"]))

            mandadas = cuerpo.get("casillas") if isinstance(cuerpo.get("casillas"), dict) else {}
            marcadas = {k: mandadas.get(k) is True for k in reglas.casillas_de(tipo, variante)}
            faltan = reglas.validar_casillas(tipo, variante, marcadas)
            if faltan:
                raise Rechazo("casillas", faltan=faltan)
            ident = reglas.resolver_identidad(tipo, variante, doc["campos"], cuerpo)
            if not ident["ok"]:
                raise Rechazo("identidad", errores=ident["errores"])
            try:
                png = render.limpiar_firma_png(cuerpo.get("firma_png"))
            except Exception:
                raise Rechazo("firma")
            codigo_id = self._validar_codigo(s, doc, "firma", cuerpo.get("codigo"), ip, ua)

            ahora = s.f("ahora")
            eventos = s.f("eventos_de", doc["id"])
            validado = next((_ts(e["ts"]) for e in reversed(eventos) if e["tipo"] == "codigo_validado"), ahora)
            hora_casilla = {}
            for e in eventos:
                if e["tipo"] == "casilla":
                    hora_casilla[e["datos"].get("casilla")] = _ts(e["ts"])
            casillas = [{"clave": k, "valor": v, "texto": self._texto_casilla(tipo, k, pagina), "ts": hora_casilla.get(k) or ahora}
                        for k, v in marcadas.items()]
            aut = s.f("autorizacion_vigente", "medico" if tipo == "consentimiento_ar" else "prestador", tipo)
            png_prestador = self._firma_prestador()
            estampar = bool(aut and png_prestador and reglas.sha256_hex(png_prestador) == aut["firma_sha256"])
            if tipo == "servicio_ext":
                estampar = False  # ya va impresa, como en la plantilla vigente
            pre = "m" if tipo == "consentimiento_ar" else "c"
            finales = ident["campos"]
            constancia = render.constancia({
                "titulo": pl["titulo"], "plantilla_id": pl["id"], "fuente_sha256": pl["fuente_sha256"], "documento_id": doc["id"],
                "nombre": finales[pre + "Nombre2"], "documento": finales[pre + "Dni2"], "email": doc["firmante_email"],
                "codigo_validado_en": validado, "firmado_en": ahora, "ip": ip, "user_agent": ua,
                "pdf_base_sha256": doc["pdf_base_sha256"], "casillas": casillas,
                "recorrido": _recorrido(eventos) + [{"ts": ahora, "que": "Dibujó su firma y confirmó", "ip": ip}],
                "correcciones": ident["correcciones"], "url_verificar": self._url_verificar(doc),
                "prestador": (f"La firma de {aut['quien']} se estampa por la autorización n.º {aut['id']} del {render.hora_utc(_ts(aut['desde']))}."
                              if estampar else ""),
            })
            valores = render.Valores(tipo, finales, firmado_en=ahora, firma_png=png,
                                     inicio_anticipado=marcadas.get("inicio_anticipado", False),
                                     firma_prestador_png=png_prestador if (estampar or tipo == "servicio_ext") else None,
                                     estampar_prestador=estampar)
            pdf = render.pdf_documento(pl["fuente_md"], valores, constancia)
            sha = reglas.sha256_hex(pdf)
            ruta = f"{doc['id']}/firmado-{sha[:16]}.pdf"
            self.almacen.guardar(ruta, pdf)

            firma = {"nombre": finales[pre + "Nombre2"], "documento": finales[pre + "Dni2"], "domicilio": finales.get(pre + "Domic", ""),
                     "campos": finales, "casillas": [{"clave": c["clave"], "valor": c["valor"], "texto": c["texto"], "ts": c["ts"].isoformat()} for c in casillas],
                     "correcciones": ident["correcciones"], "completados": ident["completados"],
                     "firma_png_sha256": reglas.sha256_hex(png), "email_verificado": doc["firmante_email"], "codigo": codigo_id,
                     "prestador_autorizacion": aut["id"] if estampar else None}
            evento = reglas.json_canonico({"pdf_final_sha256": sha, "pdf_base_sha256": doc["pdf_base_sha256"], "plantilla": pl["id"],
                                           "fuente_sha256": pl["fuente_sha256"], "firma_sha256": reglas.sha256_hex(reglas.json_canonico(firma).encode()),
                                           "casillas": {c["clave"]: c["valor"] for c in casillas}, "codigo": codigo_id,
                                           "correcciones": ident["correcciones"], "completados": ident["completados"]})
            correos = [{"tipo": "copia_firmado", "para": doc["firmante_email"]}, {"tipo": "custodia", "para": self.cfg.custodia}]
            aviso = {"tipo": "firmado", "cuerpo": self._cuerpo_aviso("firmado", doc, ahora, firma)}
            r = s.f("firmar", doc["id"], codigo_id, ahora, ruta, sha, firma, ip, ua, evento, J(correos), aviso)
            if r["resultado"] == "ya_firmado":
                return self._firmado(r["documento"], repetido=True)
            if r["resultado"] != "firmado":
                raise Rechazo("interno", 409, detalle=r["resultado"])
            return self._firmado(r["documento"])

    def _firmado(self, doc, repetido=False) -> dict:
        return {"ok": True, "estado": doc["estado"], "id": doc["id"], "firmado_en": doc["firmado_en"],
                "sha256": doc["pdf_final_sha256"], "correo": reglas.mail_tapado(doc["firmante_email"]), "repetido": repetido}

    def _cuerpo_aviso(self, que, doc, cuando, firma=None, extra=None) -> dict:
        c = {"action": "contrato_firma", "evento": que, "cuando": cuando.isoformat(),
             "documento": {"id": doc["id"], "tipo": doc["tipo"], "variante": doc["variante"], "alta_ref": doc["alta_ref"]},
             "cliente": {"nombre": doc["firmante_nombre"], "email": doc["firmante_email"], "whatsapp": doc.get("firmante_whatsapp") or "",
                         "lead_id": doc.get("lead_id")}}
        if firma:
            c["firma"] = {"inicio_anticipado": next((x["valor"] for x in firma["casillas"] if x["clave"] == "inicio_anticipado"), None),
                          "correcciones": [{"campo": x["campo"]} for x in firma["correcciones"]], "completados": firma["completados"]}
        if extra:
            c.update(extra)
        return c

    # ── revocación del consentimiento y baja del contrato ──
    def revocar(self, token: str, cuerpo: dict, ip: str, ua: str) -> dict:
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            if doc["tipo"] != "consentimiento_ar":
                raise Rechazo("interno", 400)
            if doc["estado"] == "revocado":
                return {"ok": True, "estado": "revocado", "revocado_en": doc["revocado_en"], "repetido": True}
            if doc["estado"] != "firmado":
                raise Rechazo("interno", 409)
            codigo_id = self._validar_codigo(s, doc, "revocacion", cuerpo.get("codigo"), ip, ua)
            ahora = s.f("ahora")
            pl = self._plantilla(s, doc["plantilla_id"])
            f = doc["firma"]
            motivo = reglas.limpiar_texto(cuerpo.get("motivo", ""), 500)
            # «En el mismo texto por el cual se otorgó»: el PDF de la revocación es el firmado, completo, más la revocación.
            firmado = self.almacen.leer(doc["pdf_final_path"], doc["pdf_final_sha256"])
            pagina = render.pdf_de_html(
                "<!doctype html><html><head><meta charset='utf-8'><style>%s .constancia{break-before:auto;page-break-before:auto}</style></head><body>%s</body></html>"
                % (render.CSS_PDF % {"cabecera": render.cabecera_de(pl["titulo"])},
                   render.pagina_revocacion({"nombre": f["nombre"], "documento": f["documento"], "documento_id": doc["id"],
                                             "firmado_en": _ts(doc["firmado_en"]), "revocado_en": ahora, "email": doc["firmante_email"],
                                             "ip": ip, "user_agent": ua, "motivo": motivo, "pdf_final_sha256": doc["pdf_final_sha256"]})))
            pdf = _unir_pdf(firmado, pagina)
            sha = reglas.sha256_hex(pdf)
            ruta = f"{doc['id']}/revocado-{sha[:16]}.pdf"
            self.almacen.guardar(ruta, pdf)
            evento = reglas.json_canonico({"pdf_revocacion_sha256": sha, "pdf_final_sha256": doc["pdf_final_sha256"], "motivo": motivo, "codigo": codigo_id})
            correos = [{"tipo": "copia_revocacion", "para": doc["firmante_email"]}, {"tipo": "custodia", "para": self.cfg.custodia}]
            aviso = {"tipo": "revocado", "cuerpo": self._cuerpo_aviso("revocado", doc, ahora, extra={"motivo": motivo})}
            r = s.f("revocar", doc["id"], codigo_id, ahora, ruta, sha, ip, ua, evento, J(correos), aviso)
            if r["resultado"] not in ("revocado", "ya_revocado"):
                raise Rechazo("interno", 409, detalle=r["resultado"])
            return {"ok": True, "estado": "revocado", "revocado_en": r["documento"]["revocado_en"], "repetido": r["resultado"] == "ya_revocado"}

    def pedir_baja(self, token: str, cuerpo: dict, ip: str, ua: str) -> dict:
        with self.base.conexion() as s:
            doc = self._doc(s, token)
            if doc["tipo"] == "consentimiento_ar" or doc["estado"] != "firmado":
                raise Rechazo("interno", 409)
            codigo_id = self._validar_codigo(s, doc, "baja", cuerpo.get("codigo"), ip, ua)
            ahora = s.f("ahora")
            motivo = reglas.limpiar_texto(cuerpo.get("motivo", ""), 500)
            dias = (ahora - _ts(doc["firmado_en"])).total_seconds() / 86400
            evento = reglas.json_canonico({"motivo": motivo, "codigo": codigo_id, "dias_desde_la_firma": round(dias, 3), "variante": doc["variante"]})
            aviso = {"tipo": "baja_pedida", "cuerpo": self._cuerpo_aviso("baja_pedida", doc, ahora, extra={"motivo": motivo, "dias_desde_la_firma": round(dias, 2)})}
            r = s.f("pedir_baja", doc["id"], codigo_id, ip, ua, evento, J([{"tipo": "acuse_baja", "para": doc["firmante_email"]}]), aviso)
            if r["resultado"] != "registrada":
                raise Rechazo("interno", 409, detalle=r["resultado"])
            return {"ok": True, "baja_pedida_en": r["documento"]["baja_pedida_en"]}

    # ── después de la firma: sellos, correos, avisos ──
    def despachar(self, doc_id: str = None) -> dict:
        """Manda todo lo pendiente (de un documento o de todos). Se puede correr las veces que haga falta."""
        res = {"sellos": 0, "sellos_fallan": 0, "correos": 0, "correos_fallan": 0, "avisos": 0, "avisos_fallan": 0}
        with self.base.conexion() as s:
            for p in s.f("sin_sello", list(self.cfg.tsas), doc_id):
                try:
                    tsr, hora = sello.sellar(p["sha256"], p["tsa"], self.cfg.openssl, self.cfg.ca_file)
                    s.f("registrar_sello", p["objeto"], p["documento"], None, p["sha256"], p["tsa"], tsr, hora)
                    res["sellos"] += 1
                except Exception:
                    res["sellos_fallan"] += 1
            for c in s.f("correos_pendientes", 50, doc_id):
                # La custodia lleva los sellos adentro: espera a que estén (hasta 6 h; después sale igual y lo dice).
                if c["tipo"] == "custodia" and (datetime.now(_ts(c["creado_en"]).tzinfo) - _ts(c["creado_en"])) < timedelta(hours=6) \
                        and s.f("sin_sello", list(self.cfg.tsas), c["documento_id"]):
                    s.f("correo_soltar", c["id"], 300)
                    res["custodia_espera_sello"] = res.get("custodia_espera_sello", 0) + 1
                    continue
                try:
                    r = self.correo.enviar(self._armar_correo(s, c))
                except Exception as e:
                    r = {"ok": False, "message_id": None, "respuesta": f"{type(e).__name__}: {e}"[:300]}
                s.f("correo_resultado", c["id"], r["ok"], r["message_id"], r["respuesta"])
                res["correos" if r["ok"] else "correos_fallan"] += 1
            for a in s.f("avisos_pendientes", 50, doc_id):
                ok, resp = self._avisar(s, a)
                s.f("aviso_resultado", a["id"], ok, resp)
                res["avisos" if ok else "avisos_fallan"] += 1
            if doc_id is None:
                res.update(self._avisar_frenadas(s))
        return res

    # ── altas que no se emitieron porque al formulario le falta un dato ──
    def _avisar_frenadas(self, s) -> dict:
        """Avisa (bot → WhatsApp de Mati; si no sale, correo interno) cada alta frenada: enseguida la primera vez y
        después cada `frenada_repite_horas` mientras siga sin resolverse."""
        res = {"frenadas_avisadas": 0, "frenadas_fallan": 0}
        try:  # nada de esto puede frenar el resto del despacho (correos, sellos, avisos de firma)
            pendientes = s.f("altas_frenadas_para_avisar", self.cfg.frenada_repite_horas, self.cfg.frenada_dias, 50)
        except Exception as e:
            print(f"[pump-firma] no pude leer las altas frenadas: {type(e).__name__}: {e}", flush=True)
            return {"frenadas_avisadas": 0, "frenadas_fallan": 1}
        for a in pendientes:
            try:
                ok, resp = self._avisar_frenada(a)
            except Exception as e:
                ok, resp = False, f"{type(e).__name__}: {e}"[:300]
            try:
                s.f("alta_frenada_avisada", a["alta_ref"], ok, resp)
            except Exception as e:
                ok = False
                print(f"[pump-firma] no pude anotar el aviso del alta frenada: {type(e).__name__}: {e}", flush=True)
            res["frenadas_avisadas" if ok else "frenadas_fallan"] += 1
        return res

    def _avisar_frenada(self, a):
        n = a["avisos"] + 1
        faltan = [textos.DATO_QUE_FALTA.get(k, k) for k in a["faltan"]]
        nombre = a.get("nombre") or a["email"]
        # `huella` y no la referencia cruda: la del formulario trae el correo, y el bot anota el id del aviso
        cuerpo = {"action": "contrato_firma", "evento": "alta_frenada", "aviso_id": f"frenada:{a['huella']}:{n}",
                  "cliente": {"nombre": nombre, "email": a["email"], "whatsapp": a.get("whatsapp")},
                  "alta": {"ref": a["huella"], "tipo": a["tipo"], "faltan": faltan, "aviso_n": n, "desde": a["visto_en"]},
                  "cuando": a["visto_en"]}
        resp = "bot sin configurar"
        if self.cfg.bot_url:
            req = urllib.request.Request(self.cfg.bot_url, data=json.dumps(cuerpo, ensure_ascii=False, default=str).encode(), method="POST",
                                         headers={"Content-Type": "application/json", self.cfg.bot_cabecera: self.cfg.bot_secreto})
            try:
                with urllib.request.urlopen(req, timeout=20) as r:
                    # 200 solo no alcanza: un bot que no conoce este aviso podría contestar 200 y no avisarle a nadie
                    try:
                        estado = json.loads(r.read(2000) or b"{}").get("status")
                    except Exception:
                        estado = None
                    if r.status == 200 and estado in ("ok", "repetido"):
                        return True, f"bot: {estado}"
                    resp = f"bot: HTTP {r.status}, status={estado!r}"
            except Exception as e:
                resp = f"bot: {type(e).__name__}: {e}"[:200]
        if self.cfg.aviso_interno and self.correo.configurado():  # el bot no lo recibió: que igual alguien se entere
            asunto, texto = textos.mail_alta_frenada(nombre, a["email"], a["tipo"], faltan, n, render.hora_ar(_ts(a["visto_en"])), a["huella"])
            r = self.correo.enviar(self.correo.armar(self.cfg.aviso_interno, asunto, texto))
            return bool(r["ok"]), f"{resp}; correo interno: {'enviado' if r['ok'] else r['respuesta']}"[:300]
        return False, resp

    def descartar_alta_frenada(self, alta_ref: str, motivo: str, ip: str, ua: str) -> dict:
        with self.base.conexion() as s:
            return {"ok": bool(s.f("alta_frenada_descartar", reglas.limpiar_texto(alta_ref, 200), reglas.limpiar_texto(motivo, 200), ip, ua))}

    def _armar_correo(self, s, c):
        doc = s.f("doc_por_id", c["documento_id"])
        nombre, tipo = _pila(doc["firmante_nombre"]), doc["tipo"]
        archivo = textos.ARCHIVO[tipo]
        if c["tipo"] == "invitacion":
            if doc["estado"] != "pendiente":
                raise ValueError("ya no está pendiente: la invitación no se manda")
            asunto, texto = textos.mail_invitacion(nombre, tipo, self.url_doc(doc))
            return self.correo.armar(c["para"], asunto, texto)
        if c["tipo"] == "copia_firmado":
            pdf = self.almacen.leer(doc["pdf_final_path"], doc["pdf_final_sha256"])
            asunto, texto = textos.mail_copia(nombre, tipo, render.hora_ar(_ts(doc["firmado_en"])), doc["pdf_final_sha256"], doc["id"],
                                              self.url_doc(doc), self._url_verificar(doc), doc["variante"])
            return self.correo.armar(c["para"], asunto, texto, [(archivo + " - firmado.pdf", "application/pdf", pdf)], cco=self.cfg.cco_copia)
        if c["tipo"] == "copia_revocacion":
            pdf = self.almacen.leer(doc["pdf_revocacion_path"], doc["pdf_revocacion_sha256"])
            asunto, texto = textos.mail_revocacion(nombre, render.hora_ar(_ts(doc["revocado_en"])), doc["pdf_revocacion_sha256"], doc["id"])
            return self.correo.armar(c["para"], asunto, texto, [(archivo + " - revocado.pdf", "application/pdf", pdf)], cco=self.cfg.cco_copia)
        if c["tipo"] == "acuse_baja":
            asunto, texto = textos.mail_baja(nombre, doc["variante"], render.hora_ar(_ts(doc["baja_pedida_en"])), doc["id"])
            return self.correo.armar(c["para"], asunto, texto, cco=self.cfg.cco_copia)
        if c["tipo"] == "custodia":
            return self._correo_custodia(s, c, doc)
        raise ValueError(c["tipo"])

    def _correo_custodia(self, s, c, doc):
        """El expediente completo, a una casilla ajena: PDF, sellos de tiempo y registro de eventos."""
        adj = []
        if doc.get("pdf_revocacion_sha256"):
            adj.append(("revocado.pdf", "application/pdf", self.almacen.leer(doc["pdf_revocacion_path"], doc["pdf_revocacion_sha256"])))
        adj.append(("firmado.pdf", "application/pdf", self.almacen.leer(doc["pdf_final_path"], doc["pdf_final_sha256"])))
        import base64
        sellos = s.f("sellos_de", doc["id"])
        for x in sellos:
            adj.append((f"sello-{x['objeto']}-{x['tsa']}.tsr", "application/timestamp-reply", base64.b64decode(x.pop("tsr_b64"))))
        registro = {"documento": {k: v for k, v in doc.items() if k != "firma"}, "firma": doc.get("firma"),
                    "eventos": s.f("eventos_de", doc["id"]), "sellos": sellos, "cabeza_cadena": s.f("cabeza_cadena")}
        adj.append(("registro.json", "application/json", json.dumps(registro, ensure_ascii=False, indent=1, default=str).encode()))
        texto = (f"Custodia de firma — {doc['tipo']} — {doc['id']}\nEstado: {doc['estado']}\n"
                 f"SHA-256 del PDF firmado: {doc['pdf_final_sha256']}\nSHA-256 del PDF de revocación: {doc.get('pdf_revocacion_sha256') or '-'}\n"
                 f"Sellos adjuntos: {len(sellos)}\nNo responder. No borrar.\n")
        return self.correo.armar(c["para"], f"[custodia] {doc['tipo']} {doc['id']} {doc['estado']}", texto, adj)

    def _avisar(self, s, a):
        if not self.cfg.bot_url:
            return False, "bot sin configurar"
        cuerpo = dict(a["cuerpo"])
        doc = s.f("doc_por_id", a["documento_id"])
        if not doc.get("lead_id"):
            lead = s.f("lead_de", doc["firmante_email"], doc.get("firmante_whatsapp") or "", _ts(doc["creado_en"]) - timedelta(hours=6), _ts(doc["creado_en"]) + timedelta(hours=48))
            if lead:
                s.f("vincular_lead", doc["alta_ref"], lead)
                cuerpo["cliente"]["lead_id"] = lead
        cuerpo["estado"] = s.f("public.contrato_estado", cuerpo["cliente"].get("lead_id"), doc["firmante_email"], doc.get("firmante_whatsapp") or "")
        cuerpo["aviso_id"] = a["id"]
        req = urllib.request.Request(self.cfg.bot_url, data=json.dumps(cuerpo, ensure_ascii=False, default=str).encode(), method="POST",
                                     headers={"Content-Type": "application/json", self.cfg.bot_cabecera: self.cfg.bot_secreto})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status == 200, f"HTTP {r.status}"
        except Exception as e:
            return False, f"{type(e).__name__}: {e}"[:300]

    # ── consultas ──
    def verificar(self, doc_id: str = None, sha256: str = None) -> dict:
        if doc_id:
            try:
                doc_id = str(uuid.UUID(doc_id))
            except ValueError:
                return {"existe": False}
        if sha256 and not (len(sha256) == 64 and all(c in "0123456789abcdef" for c in sha256)):
            return {"existe": False}
        if not doc_id and not sha256:
            return {"existe": False}
        with self.base.conexion() as s:
            r = s.f("verificar", doc_id, sha256)
        return {"existe": bool(r), **(r or {})}

    def estado(self, lead_id=None, email=None, whatsapp=None) -> dict:
        with self.base.conexion() as s:
            return s.f("public.contrato_estado", lead_id, email, whatsapp)

    def docs_de_app(self, token_app: str):
        """Para la app (Fase 2): los documentos del dueño del token, con su link de firma."""
        if not token_app or len(token_app) > 200:
            return None
        with self.base.conexion() as s:
            docs = s.f("docs_de_app", token_app)
        if docs is None:
            return None
        return [{"id": d["id"], "tipo": d["tipo"], "estado": d["estado"], "firmado_en": d.get("firmado_en"), "url": self.url_doc(d)} for d in docs]

    def salud(self) -> dict:
        with self.base.conexion() as s:
            ahora = s.f("ahora")
            pend = s.f("pendientes_de_atencion", 15)
        return {"ok": True, "hora": ahora.isoformat(), "pendientes": {k: len(v) for k, v in pend.items()},
                "correo": self.correo.configurado(), "custodia": bool(self.cfg.custodia)}


def _k_nombre(tipo):
    return "mNombre" if tipo == "consentimiento_ar" else "cNombre1"


def _pila(nombre: str) -> str:
    return (nombre or "").split(" ")[0]


def _mail_ok(m: str) -> bool:
    import re
    return bool(re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", m or "")) and len(m) <= 200


def _sin_html(h: str) -> str:
    import html as _h
    import re
    return _h.unescape(re.sub(r"<[^>]+>", "", h)).strip()


def _recorrido(eventos) -> list:
    """Los pasos que constan, en orden, sin repetir de más lo que se repite (abrir la página varias veces)."""
    salida, vistos = [], {}
    for e in eventos:
        que = QUE_PASO.get(e["tipo"])
        if not que:
            continue
        vistos[e["tipo"]] = vistos.get(e["tipo"], 0) + 1
        if e["tipo"] in ("abierto", "pdf_visto", "fin_lectura", "identidad_escrita") and vistos[e["tipo"]] > 3:
            continue
        salida.append({"ts": _ts(e["ts"]), "que": que, "ip": e.get("ip")})
    return salida[-40:]


def _unir_pdf(a: bytes, b: bytes) -> bytes:
    import io
    from pypdf import PdfReader, PdfWriter
    w = PdfWriter()
    for datos in (a, b):
        for p in PdfReader(io.BytesIO(datos)).pages:
            w.add_page(p)
    salida = io.BytesIO()
    w.write(salida)
    return salida.getvalue()
