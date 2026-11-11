#!/usr/bin/env python3
"""Carga una versión de plantilla en contrato.plantillas y la deja vigente. El texto NO se toca: entra byte a byte
desde el archivo aprobado, y el md5 esperado se pasa a mano para que un archivo equivocado no entre.

Uso (con el rol dueño, no con firma_srv):
  FIRMA_DB_ADMIN_URL=postgresql://... python tools/cargar_plantillas.py servicio_ar v12 /ruta/A_v12.md <md5 esperado> [--ensayo]

`--ensayo` hace todo y termina en ROLLBACK. Una versión ya cargada con el mismo texto no se vuelve a cargar."""
import hashlib
import os
import sys

import psycopg

TIPOS = ("servicio_ar", "servicio_ext", "consentimiento_ar")

# Decisiones de Mati del 10/11. Una plantilla de servicio con una redacción retirada NO se carga (los contratos ya
# firmados no se tocan; esto frena que un archivo viejo vuelva a quedar vigente):
#   - una sola videollamada (cláusula 1 c en los dos; 9.3 c en los dos);
#   - Argentina: pasado el plazo de revocación lo pagado no se reembolsa (14.2), sin el 30 % fijo ni devolución del excedente;
#   - exterior: el desistimiento europeo de 14 días informado completo (cláusula 10.2, formulario modelo y aviso).
#   - compromiso de continuidad con tope de tres meses; antes de la entrega se retiene como máximo el 30 % (AR 8.7 y 14.2);
#   - exterior: cláusula 9 sin «garantía» ni extinción automática; cláusula 14 con el criterio de Argentina fuera de
#     Europa y, para la UE, el EEE y el Reino Unido, pago solo de lo ya prestado; teléfono del Prestador en la 10.2;
#   - «no grabar la videollamada» (ya no «las sesiones»).
# Las frases se comparan sin distinguir mayúsculas ni saltos de línea. Vigentes: servicio_ar v12, servicio_ext v7.
#   - (v12/v7) compromiso de continuidad con tope de un mes; caducidad por falta de inicio (AR 8.4) con tope del 40 %;
#     exterior con Anexo I (plan, objetivo, precio y su composición), diez días de revocación para todos, sin reclamo
#     de diferencia al europeo, y cláusulas 6 y 8.1 equilibradas.
RETIRADAS = {
    "servicio_ar": ("sesiones de coaching individual",
                    "de las sesiones de coaching y de los controles programados",
                    "una suma fija equivalente al treinta por ciento (30 %) del precio total",
                    "14.2. desistimiento del cliente",
                    "ni difundir las sesiones",
                    "por un máximo de tres (3) meses adicionales",
                    "hasta el tope del treinta por ciento (30 %) del precio total del anexo i, y devuelve el excedente, si lo hubiera"),
    "servicio_ext": ("sesiones de coaching individual",
                     "la asistencia a la totalidad de las sesiones de coaching",
                     "con devolución de lo abonado cuando la prestación del servicio no hubiera comenzado. a modo de referencia",
                     "ni difundir las sesiones",
                     "garantía de resultados físicos",
                     "extinción automática",
                     "constituyen prueba suficiente del cumplimiento",
                     "cualquiera de las partes podrá terminar el contrato con aviso previo",
                     "no libera al cliente de las cuotas vencidas e impagas",
                     "por un máximo de tres (3) meses adicionales",
                     "que el cliente acepta como prueba suficiente",
                     "el cliente adeuda solo la diferencia",
                     "dentro del plazo que le reconozca la normativa de defensa del consumidor de su país de residencia, que este contrato no reduce"),
}
EXIGIDAS = {
    "servicio_ar": ("una videollamada individual de entrega y acompañamiento del proceso por mensajes",
                    "la asistencia a la videollamada de entrega y al menos el ochenta por ciento (80 %) de los check-ins programados",
                    "las sumas abonadas hasta esa comunicación no se reembolsan",
                    "el cliente no adeuda las cuotas impagas a la fecha de esa comunicación ni las que venzan después",
                    "cuando la terminación obedece a un incumplimiento del prestador",
                    "una imposibilidad de continuar por razones de salud",
                    "dentro de los diez (10) días corridos desde la fecha de celebración",
                    "botón de revocación",
                    "por un máximo de un (1) mes adicional",
                    "hasta el tope del cuarenta por ciento (40 %) del precio total del anexo i",
                    "si la terminación se comunica antes de la entrega de la planificación inicial (cláusula 10.3 c), el prestador conserva lo abonado solo hasta el tope del treinta por ciento (30 %)",
                    "si la resolución ocurre antes de la entrega de la planificación inicial (cláusula 10.3 c), el prestador conserva lo abonado solo hasta el tope del treinta por ciento (30 %)",
                    "ni difundir la videollamada"),
    "servicio_ext": ("una videollamada individual de entrega y acompañamiento del proceso por mensajes",
                     "la asistencia a la videollamada de entrega y la realización de los check-ins programados",
                     "en un plazo de catorce (14) días naturales sin necesidad de justificación",
                     "solicitar expresamente que el servicio comience durante el plazo de desistimiento",
                     "un importe proporcional a la parte ya prestada del servicio",
                     "habrá perdido su derecho de desistimiento",
                     "modelo de formulario de desistimiento",
                     "por la presente le comunico que desisto de mi contrato",
                     "estados unidos de américa; teléfono +",
                     "por un máximo de un (1) mes adicional",
                     "anexo i — condiciones particulares",
                     "{{@cplan}}", "{{@cobjetivo}}", "{{@cprecio}}", "{{@cinicio}}",
                     "dentro de los diez (10) días corridos desde la fecha de su firma",
                     "el prestador no le reclama la diferencia",
                     "no se aplican a la muerte ni a los daños personales",
                     "acreditan los pagos y no modifican lo pactado",
                     "anexo ii — modelo de formulario de desistimiento",
                     "las sumas abonadas hasta esa comunicación no se reembolsan",
                     "a estos clientes no se les aplica la cláusula 14.2",
                     "abona únicamente el precio de lo ya prestado",
                     "ni difundir la videollamada"),
}


def texto_retirado(tipo: str, md: str) -> list:
    """Qué tiene mal una plantilla de servicio respecto de las redacciones vigentes ([] = está bien)."""
    if tipo not in RETIRADAS:
        return []
    plano = " ".join(md.replace("**", "").split()).lower()
    mal = [f"vuelve el texto retirado: «{f}»" for f in RETIRADAS[tipo] if f in plano]
    mal += [f"falta el texto vigente: «{f}»" for f in EXIGIDAS[tipo] if f not in plano]
    return mal


def titulo_de(md: str) -> str:
    for l in md.splitlines():
        if l.startswith("# "):
            return l[2:].strip()
    raise SystemExit("la plantilla no tiene título (# ...)")


def cargar(conn, tipo: str, version: str, md: str, vigente: bool = True, sintetica: bool = False) -> dict:
    """Devuelve {'id', 'sha256', 'md5', 'resultado'}; no hace commit."""
    if tipo not in TIPOS:
        raise SystemExit(f"tipo inválido: {tipo}")
    mal = [] if sintetica else texto_retirado(tipo, md)  # `sintetica`: solo las plantillas inventadas de las pruebas
    if mal:
        raise SystemExit("la plantilla no se carga — " + "; ".join(mal))
    pid = f"{tipo}@{version}"
    sha, md5 = hashlib.sha256(md.encode("utf-8")).hexdigest(), hashlib.md5(md.encode("utf-8")).hexdigest()
    with conn.cursor() as cur:
        cur.execute("SELECT fuente_sha256, vigente FROM contrato.plantillas WHERE id = %s", (pid,))
        fila = cur.fetchone()
        if fila:
            if fila[0] != sha:
                raise SystemExit(f"{pid} ya existe con OTRO texto: una versión no se edita; cargá una versión nueva")
            resultado = "ya_estaba"
        else:
            cur.execute("INSERT INTO contrato.plantillas (id, tipo, version, titulo, fuente_md, fuente_sha256, fuente_md5, vigente) "
                        "VALUES (%s, %s, %s, %s, %s, %s, %s, false)", (pid, tipo, version, titulo_de(md), md, sha, md5))
            resultado = "cargada"
        if vigente:
            cur.execute("UPDATE contrato.plantillas SET vigente = false WHERE tipo = %s AND vigente AND id <> %s", (tipo, pid))
            cur.execute("UPDATE contrato.plantillas SET vigente = true WHERE id = %s AND NOT vigente", (pid,))
        cur.execute("SELECT fuente_sha256 = encode(sha256(convert_to(fuente_md, 'UTF8')), 'hex') FROM contrato.plantillas WHERE id = %s", (pid,))
        assert cur.fetchone()[0], "la base no confirma el hash"
    return {"id": pid, "sha256": sha, "md5": md5, "resultado": resultado}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 4:
        raise SystemExit(__doc__)
    tipo, version, ruta, md5_esperado = args
    md = open(ruta, "rb").read().decode("utf-8")
    md5 = hashlib.md5(md.encode("utf-8")).hexdigest()
    if md5 != md5_esperado.lower():
        raise SystemExit(f"md5 del archivo {md5} ≠ esperado {md5_esperado}: no se carga")
    url = os.environ.get("FIRMA_DB_ADMIN_URL")
    if not url:
        raise SystemExit("falta FIRMA_DB_ADMIN_URL")
    with psycopg.connect(url, autocommit=False, prepare_threshold=None) as conn:
        r = cargar(conn, tipo, version, md)
        if "--ensayo" in sys.argv:
            conn.rollback()
            r["resultado"] += " (ENSAYO: ROLLBACK)"
        else:
            conn.commit()
    print(r)


if __name__ == "__main__":
    main()
