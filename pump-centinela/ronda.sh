#!/bin/bash
# ronda.sh — elige el modo según el día. Lo llama com.pump.ronda.
#
# launchd no sabe pasar argumentos distintos por horario: un mismo agente con
# tres StartCalendarInterval corre SIEMPRE el mismo comando. Por eso la decisión
# vive acá y no en el plist — la alternativa serían tres agentes casi idénticos,
# y tres archivos que hay que acordarse de mantener sincronizados.
PY=/Users/matiassancari/agentkit-coach/venv/bin/python
cd /Users/matiassancari/pump-centinela || exit 1

case "$(date +%u)" in
  7) exec "$PY" recordatorios.py --programar ;;   # domingo
  2|4) exec "$PY" recordatorios.py --recordar ;;  # martes y jueves
  *) echo "[$(date '+%F %T')] ronda.sh corrio un dia que no toca ($(date +%A)) — no hago nada"; exit 0 ;;
esac
