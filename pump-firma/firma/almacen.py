"""Dónde viven los PDF: siempre en el disco de la Mini (copia fuera de Supabase) y además en el bucket privado
`contratos` de Supabase (copia fuera de la Mini). Lo que se lee se verifica contra su SHA-256 antes de usarlo."""
import os
import urllib.error
import urllib.request

from . import reglas


class Almacen:
    def __init__(self, carpeta: str, supabase_url: str = "", service_key: str = "", bucket: str = "contratos"):
        self.carpeta = carpeta
        self.url = (supabase_url or "").rstrip("/")
        self.key = service_key or ""
        self.bucket = bucket

    def _local(self, ruta: str) -> str:
        if ".." in ruta or ruta.startswith("/") or "\\" in ruta:
            raise ValueError("ruta inválida")
        return os.path.join(self.carpeta, "pdf", ruta)

    def _pendiente(self, ruta: str) -> str:
        return os.path.join(self.carpeta, "por_subir", ruta.replace("/", "__"))

    def guardar(self, ruta: str, datos: bytes) -> None:
        """Escribe en disco (obligatorio, con fsync, sin pisar) y sube al bucket. Si la subida falla, queda anotada y
        la reintenta `tareas`: la firma no se cae por un corte de Supabase Storage."""
        destino = self._local(ruta)
        os.makedirs(os.path.dirname(destino), exist_ok=True)
        if os.path.exists(destino):
            if reglas.sha256_hex(open(destino, "rb").read()) != reglas.sha256_hex(datos):
                raise RuntimeError(f"ya existe {ruta} con otro contenido: no se pisa")
        else:
            tmp = destino + ".part"
            with open(tmp, "wb") as f:
                f.write(datos)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(tmp, 0o600)
            os.replace(tmp, destino)
        if not self.subir(ruta, datos):
            os.makedirs(os.path.dirname(self._pendiente(ruta)), exist_ok=True)
            open(self._pendiente(ruta), "w").write(ruta)

    def subir(self, ruta: str, datos: bytes) -> bool:
        if not self.url:
            return True  # pruebas o modo sin bucket
        req = urllib.request.Request(f"{self.url}/storage/v1/object/{self.bucket}/{ruta}", data=datos, method="POST",
                                     headers={"Authorization": f"Bearer {self.key}", "apikey": self.key,
                                              "Content-Type": "application/pdf", "x-upsert": "false"})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status in (200, 201)
        except urllib.error.HTTPError as e:
            return e.code == 409 or b"Duplicate" in e.read(500)  # ya estaba: las rutas llevan el hash
        except Exception:
            return False

    def reintentar_subidas(self) -> dict:
        carpeta = os.path.join(self.carpeta, "por_subir")
        hechas, fallan = 0, 0
        for nombre in sorted(os.listdir(carpeta)) if os.path.isdir(carpeta) else []:
            ruta = open(os.path.join(carpeta, nombre)).read().strip()
            if self.subir(ruta, open(self._local(ruta), "rb").read()):
                os.remove(os.path.join(carpeta, nombre))
                hechas += 1
            else:
                fallan += 1
        return {"subidas": hechas, "fallan": fallan}

    def leer(self, ruta: str, sha256_esperado: str) -> bytes:
        datos = None
        try:
            datos = open(self._local(ruta), "rb").read()
        except FileNotFoundError:
            if self.url:
                req = urllib.request.Request(f"{self.url}/storage/v1/object/{self.bucket}/{ruta}",
                                             headers={"Authorization": f"Bearer {self.key}", "apikey": self.key})
                with urllib.request.urlopen(req, timeout=20) as r:
                    datos = r.read()
        if datos is None:
            raise FileNotFoundError(ruta)
        if reglas.sha256_hex(datos) != sha256_esperado:
            raise RuntimeError(f"{ruta}: el contenido no coincide con su hash registrado")
        return datos
