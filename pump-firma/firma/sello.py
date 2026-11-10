"""Sello de tiempo externo (RFC 3161) sobre un hash SHA-256. Gratis, de autoridades públicas, y verificable por
cualquiera con `openssl ts -verify` y los certificados raíz públicos: no depende de nosotros.

Solo viaja el hash: ningún dato del documento sale de la Mini."""
import os
import re
import subprocess
import tempfile
import urllib.request
from datetime import datetime, timezone

# Autoridades probadas el 10/11/2026 (responden y verifican contra las raíces públicas).
TSAS = {
    "digicert": "http://timestamp.digicert.com",
    "globalsign": "http://timestamp.globalsign.com/tsa/r6advanced1",
    "sslcom": "http://ts.ssl.com",
}
_OID_SHA256 = bytes.fromhex("3031300d060960864801650304020105000420")


def pedido(sha256_hex: str, nonce: bytes = None) -> bytes:
    """TimeStampReq en DER: versión 1, SHA-256, nonce de 8 bytes y certReq (para que el sello traiga su certificado)."""
    h = bytes.fromhex(sha256_hex)
    if len(h) != 32:
        raise ValueError("hace falta un SHA-256")
    n = bytearray(nonce or os.urandom(8))
    n[0] = (n[0] & 0x7F) | 0x40  # entero positivo y sin ceros a la izquierda
    cuerpo = b"\x02\x01\x01" + _OID_SHA256 + h + b"\x02\x08" + bytes(n) + b"\x01\x01\xff"
    return b"\x30" + bytes([len(cuerpo)]) + cuerpo


class SelloError(Exception):
    pass


def pedir(url: str, sha256_hex: str, timeout: float = 10.0) -> bytes:
    req = urllib.request.Request(url, data=pedido(sha256_hex), method="POST",
                                 headers={"Content-Type": "application/timestamp-query", "User-Agent": "pump-firma"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            if r.status != 200:
                raise SelloError(f"HTTP {r.status}")
            tsr = r.read(200_000)
    except SelloError:
        raise
    except Exception as e:  # red, DNS, tiempo
        raise SelloError(f"{type(e).__name__}: {e}") from e
    if len(tsr) < 100 or tsr[:1] != b"\x30":
        raise SelloError("respuesta que no es un sello")
    return tsr


def verificar(tsr: bytes, sha256_hex: str, openssl: str, ca_file: str) -> datetime:
    """Verifica el sello contra el hash y las raíces públicas, y devuelve su hora. Lanza SelloError si no cierra."""
    with tempfile.TemporaryDirectory() as d:
        f, tok, cadena = os.path.join(d, "s.tsr"), os.path.join(d, "s.p7"), os.path.join(d, "cadena.pem")
        open(f, "wb").write(tsr)
        orden = [openssl, "ts", "-verify", "-digest", sha256_hex, "-in", f, "-CAfile", ca_file]
        # Los certificados intermedios vienen dentro del sello. OpenSSL 3 los usa solo; LibreSSL (el de macOS) necesita
        # que se los pasen como «no confiables»: la confianza sigue saliendo únicamente de las raíces públicas.
        subprocess.run([openssl, "ts", "-reply", "-in", f, "-token_out", "-out", tok], capture_output=True, timeout=30)
        subprocess.run([openssl, "pkcs7", "-inform", "DER", "-in", tok, "-print_certs", "-out", cadena], capture_output=True, timeout=30)
        if os.path.exists(cadena) and os.path.getsize(cadena) > 100:
            orden += ["-untrusted", cadena]
        v = subprocess.run(orden, capture_output=True, text=True, timeout=30)
        if v.returncode != 0 or "Verification: OK" not in (v.stdout + v.stderr):
            raise SelloError("el sello no verifica: " + (v.stdout + v.stderr).strip()[-300:])
        t = subprocess.run([openssl, "ts", "-reply", "-in", f, "-text"], capture_output=True, text=True, timeout=30)
    m = re.search(r"Time stamp:\s*(\w{3})\s+(\d+)\s+(\d\d:\d\d:\d\d)(?:\.\d+)?\s+(\d{4})\s+GMT", t.stdout)
    if not m:
        raise SelloError("no se pudo leer la hora del sello")
    return datetime.strptime(" ".join(m.groups()), "%b %d %H:%M:%S %Y").replace(tzinfo=timezone.utc)


def sellar(sha256_hex: str, tsa: str, openssl: str, ca_file: str, timeout: float = 10.0):
    """Pide y verifica. Devuelve (tsr, hora). Nunca devuelve un sello sin verificar."""
    tsr = pedir(TSAS[tsa], sha256_hex, timeout)
    return tsr, verificar(tsr, sha256_hex, openssl, ca_file)
