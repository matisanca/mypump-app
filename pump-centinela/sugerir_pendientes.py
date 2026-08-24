#!/usr/bin/env python3
"""sugerir_pendientes.py — le escribe la sugerencia a los borradores que quedaron sin ella.

POR QUE EXISTE
La 064 hizo que la IA redacte una sugerencia para `derivar` y `urgente`, pero
solo para lo que entra de ahora en más. Los borradores que ya estaban esperando
en la bandeja se generaron antes, tienen `sugerencia` en NULL, y el Cerebro los
sigue mostrando con el composer vacío — que es exactamente lo que el cambio
venía a arreglar.

Esto los rellena. Reusa `armar_prompt` y `llamar_codex` del worker, así que la
sugerencia sale idéntica a la que habría salido en su momento: si el prompt
cambia, esto cambia solo.

USO
    python3 sugerir_pendientes.py            # dry-run: muestra qué escribiría
    python3 sugerir_pendientes.py --correr   # lo guarda

NO PUEDE PUBLICAR NADA. Solo llama a mypump_chat_borrador_sugerir, que toca una
columna y ni siquiera cambia el estado del borrador. Lo que sale al cliente
sigue saliendo únicamente por el botón de Mati.
"""
import sys

import chat_worker as W

_BANDERAS = {"--correr", "--limite"}
_desconocidas = [a for a in sys.argv[1:]
                 if a.startswith("--") and a.split("=")[0] not in _BANDERAS]
if _desconocidas:
    print(f"bandera desconocida: {' '.join(_desconocidas)}")
    sys.exit(2)

CORRER = "--correr" in sys.argv
LIMITE = 20
for a in sys.argv[1:]:
    if a.startswith("--limite="):
        LIMITE = max(1, min(50, int(a.split("=", 1)[1])))


def main():
    if not W.SB_KEY:
        print("falta SUPABASE_SERVICE_KEY")
        return 1

    try:
        filas = W._sb("mypump_chat_borradores_sin_sugerencia", {"p_limite": LIMITE}) or []
    except Exception as e:  # noqa: BLE001
        print(f"no pude leer los borradores: {e}")
        return 1

    if not filas:
        print("no hay borradores sin sugerencia")
        return 0

    print(f"{len(filas)} borradores sin sugerencia" + ("" if CORRER else "   [DRY-RUN]"))
    print()

    ok = fallos = 0
    for f in filas:
        quien = (f.get("nombre") or f["cliente_id"])[:24]
        d, err = W.llamar_codex(W.armar_prompt(f))
        if err:
            print(f"  ✗ {quien:<24} la IA no pudo: {err}")
            fallos += 1
            continue

        # El modelo puede devolver la sugerencia o, si reclasifica, la respuesta.
        # Cualquiera de las dos sirve como borrador PARA MATI: no se envía sola.
        txt = (d.get("sugerencia") or d.get("respuesta") or "").strip()
        if not txt:
            print(f"  · {quien:<24} no propuso nada")
            fallos += 1
            continue

        print(f"  ✓ {quien:<24} {txt[:78]}")
        if not CORRER:
            continue
        try:
            guardado = W._sb("mypump_chat_borrador_sugerir",
                             {"p_id": f["borrador_id"], "p_sugerencia": txt})
            if guardado:
                ok += 1
            else:
                print(f"      (ya tenía sugerencia o cambió de estado)")
        except Exception as e:  # noqa: BLE001
            print(f"      no pude guardar: {e}")
            fallos += 1

    print()
    if CORRER:
        print(f"{ok} guardadas, {fallos} sin sugerencia")
    else:
        print("(dry-run: no se guardó nada; usá --correr)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
