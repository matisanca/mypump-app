"""Envío de correo por SMTP (la casilla info@ de Yandex 360, con contraseña de aplicación). El servidor de Yandex
firma con DKIM y fecha el mensaje: el mail en el buzón del firmante es prueba que no depende de nosotros."""
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formatdate, make_msgid


class Correo:
    def __init__(self, host: str, puerto: int, usuario: str, clave: str, remitente: str, seguro: str = "ssl",
                 dominio_id: str = "mypumpteam.com"):
        self.host, self.puerto, self.usuario, self.clave = host, int(puerto or 0), usuario, clave
        self.remitente, self.seguro, self.dominio_id = remitente, seguro, dominio_id

    def configurado(self) -> bool:
        return bool(self.host and self.puerto and self.remitente)

    def armar(self, para: str, asunto: str, texto: str, adjuntos=(), cco=()) -> EmailMessage:
        m = EmailMessage()
        m["From"] = self.remitente
        m["To"] = para
        m["Subject"] = asunto
        m["Date"] = formatdate(localtime=False)
        m["Message-ID"] = make_msgid(domain=self.dominio_id)
        m["Auto-Submitted"] = "auto-generated"
        m.set_content(texto)
        for nombre, tipo, datos in adjuntos:
            principal, _, sub = tipo.partition("/")
            m.add_attachment(datos, maintype=principal, subtype=sub, filename=nombre)
        m._cco = list(cco)  # no va en los encabezados: solo en el sobre
        return m

    def enviar(self, m: EmailMessage) -> dict:
        """Devuelve {'ok', 'message_id', 'respuesta'}. No lanza: el que llama decide reintentar."""
        if not self.configurado():
            return {"ok": False, "message_id": m["Message-ID"], "respuesta": "correo sin configurar"}
        destinos = [m["To"]] + list(getattr(m, "_cco", []))
        try:
            if self.seguro == "ssl":
                s = smtplib.SMTP_SSL(self.host, self.puerto, timeout=25, context=ssl.create_default_context())
            else:
                s = smtplib.SMTP(self.host, self.puerto, timeout=25)
                if self.seguro == "starttls":
                    s.starttls(context=ssl.create_default_context())
            with s:
                if self.usuario:
                    s.login(self.usuario, self.clave)
                rechazados = s.send_message(m, to_addrs=destinos)
            if m["To"] in rechazados:
                return {"ok": False, "message_id": m["Message-ID"], "respuesta": f"rechazado: {rechazados[m['To']]}"}
            return {"ok": True, "message_id": m["Message-ID"],
                    "respuesta": "aceptado por %s%s" % (self.host, f"; rechazados: {sorted(rechazados)}" if rechazados else "")}
        except Exception as e:
            return {"ok": False, "message_id": m["Message-ID"], "respuesta": f"{type(e).__name__}: {e}"[:400]}
