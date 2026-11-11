"""Configuración: todo sale del entorno (archivo privado ~/pump-firma-datos/firma.env en la Mini). Nada secreto vive
en el repo. Ver env.ejemplo."""
import os


def _leer_env(ruta: str) -> dict:
    datos = {}
    if ruta and os.path.exists(ruta):
        for l in open(ruta, encoding="utf-8"):
            l = l.strip()
            if l and not l.startswith("#") and "=" in l:
                k, v = l.split("=", 1)
                datos[k.strip()] = v.split(" #", 1)[0].strip().strip('"').strip("'")  # admite comentario al final de la línea
    return datos


class Config:
    def __init__(self, entorno: dict = None):
        e = dict(entorno if entorno is not None else os.environ)
        archivo = _leer_env(e.get("FIRMA_ENV", ""))
        g = lambda k, d="": e.get(k) or archivo.get(k) or d  # noqa: E731
        self.db_url = g("FIRMA_DB_URL")
        self.secreto = g("FIRMA_SECRETO").encode()
        self.secreto_interno = g("FIRMA_SECRETO_INTERNO")
        self.url_publica = g("FIRMA_URL_PUBLICA", "https://firma.mypumpteam.com").rstrip("/")
        self.datos = os.path.expanduser(g("FIRMA_DATOS", "~/pump-firma-datos"))
        self.supabase_url = g("SUPABASE_URL")
        self.supabase_key = g("SUPABASE_SERVICE_KEY")
        self.smtp_host = g("FIRMA_SMTP_HOST", "smtp.yandex.com")
        self.smtp_puerto = int(g("FIRMA_SMTP_PUERTO", "465"))
        self.smtp_seguro = g("FIRMA_SMTP_SEGURO", "ssl")
        self.smtp_usuario = g("FIRMA_SMTP_USUARIO")
        self.smtp_clave = g("FIRMA_SMTP_CLAVE")
        self.remitente = g("FIRMA_REMITENTE", "Pump Team <info@mypumpteam.com>")
        self.cco_copia = [x.strip() for x in g("FIRMA_CCO_COPIA").split(",") if x.strip()]
        self.custodia = g("FIRMA_CUSTODIA_EMAIL")
        self.aviso_interno = g("FIRMA_AVISO_INTERNO_EMAIL")
        # altas frenadas por un dato faltante: cada cuánto se repite el aviso y hasta cuándo
        self.frenada_repite_horas = int(g("FIRMA_FRENADA_REPITE_HORAS", "24"))
        self.frenada_dias = int(g("FIRMA_FRENADA_DIAS", "14"))
        self.bot_url = g("FIRMA_BOT_URL")
        self.bot_secreto = g("FIRMA_BOT_SECRETO")
        self.bot_cabecera = g("FIRMA_BOT_CABECERA", "X-Pump-Onboarding-Secret")
        self.tsas = [x.strip() for x in g("FIRMA_TSAS", "digicert,globalsign").split(",") if x.strip()]
        # Hace falta OpenSSL 3: el LibreSSL de macOS no verifica los sellos de GlobalSign ni de SSL.com.
        self.openssl = g("FIRMA_OPENSSL") or next((p for p in ("/opt/homebrew/opt/openssl@3/bin/openssl", "/opt/homebrew/bin/openssl",
                                                                "/usr/local/opt/openssl@3/bin/openssl") if os.path.exists(p)), "/usr/bin/openssl")
        self.ca_file = g("FIRMA_CA_FILE", "/etc/ssl/cert.pem")
        self.firma_prestador = os.path.expanduser(g("FIRMA_PRESTADOR_PNG", os.path.join(self.datos, "privado", "firma_prestador.png")))
        self.minutos_codigo = int(g("FIRMA_MINUTOS_CODIGO", "15"))
        self.origenes_app = [x.strip() for x in g("FIRMA_ORIGENES_APP", "https://app.mypumpteam.com").split(",") if x.strip()]

    def faltantes(self) -> list:
        """Lo que impide arrancar en producción. El servicio se niega a levantar si falta algo de esto."""
        f = []
        if not self.db_url: f.append("FIRMA_DB_URL")
        if len(self.secreto) < 32: f.append("FIRMA_SECRETO (32+ caracteres)")
        if len(self.secreto_interno) < 32: f.append("FIRMA_SECRETO_INTERNO (32+ caracteres)")
        if not (self.smtp_usuario and self.smtp_clave): f.append("FIRMA_SMTP_USUARIO / FIRMA_SMTP_CLAVE")
        if not self.custodia: f.append("FIRMA_CUSTODIA_EMAIL (casilla ajena, condición de la segunda opinión)")
        if not (self.supabase_url and self.supabase_key): f.append("SUPABASE_URL / SUPABASE_SERVICE_KEY")
        if not self.tsas: f.append("FIRMA_TSAS")
        return f
