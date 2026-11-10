"""Acceso a la base: una conexión por pedido, cada llamada en su transacción y siempre como `firma_srv`
(solo puede ejecutar las funciones del esquema `contrato`; no puede tocar las tablas a mano)."""
import time
from contextlib import contextmanager

import psycopg
from psycopg.types.json import Jsonb


class Base:
    def __init__(self, url: str, rol: str = "firma_srv", intentos: int = 3):
        self.url, self.rol, self.intentos = url, rol, intentos

    def _conectar(self):
        for i in range(self.intentos):
            try:
                return psycopg.connect(self.url, autocommit=False, connect_timeout=15, prepare_threshold=None)
            except psycopg.OperationalError:  # un corte al conectar (pooler): todavía no se hizo nada, se puede reintentar
                if i == self.intentos - 1:
                    raise
                time.sleep(0.4 * (i + 1))

    @contextmanager
    def conexion(self):
        c = self._conectar()
        try:
            yield Sesion(c, self.rol)
        finally:
            c.close()


class Sesion:
    def __init__(self, c, rol):
        self.c, self.rol = c, rol

    def f(self, funcion: str, *args):
        """Llama a contrato.<funcion>(...) en una transacción propia y devuelve su valor."""
        esquema = "public" if funcion.startswith("public.") else "contrato"
        nombre = funcion.split(".")[-1]
        if not nombre.replace("_", "").isalnum():
            raise ValueError(funcion)
        marcas = ", ".join(["%s"] * len(args))
        try:
            with self.c.cursor() as cur:
                cur.execute(f"SET LOCAL ROLE {self.rol}")
                cur.execute(f"SELECT {esquema}.{nombre}({marcas})", [Jsonb(a) if isinstance(a, dict) else a for a in args])
                valor = cur.fetchone()[0]
            self.c.commit()
            return valor
        except Exception:
            self.c.rollback()
            raise


J = Jsonb  # para pasar una lista como JSONB (una lista suelta viaja como arreglo de Postgres)
