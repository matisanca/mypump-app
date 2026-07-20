#!/bin/zsh
# Consolidacion autonoma de suplementos + quimica (N15).
# Corre a diario despues del refresh de memorias (03:03). Es BARATO: cada
# script saltea los clientes cuyo texto candidato no cambio (hash) y no pisa
# lo que Mati ya confirmo (revisado=true). Asi la info de cada cliente se
# mantiene actualizada segun lo que va apareciendo en las videollamadas y
# WhatsApp, sin gasto cuando no hay novedades.
export PATH="$HOME/.nvm/versions/node/v24.16.0/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
PY="$HOME/agentkit-coach/venv/bin/python"
LOG="$HOME/pump-consolidar/consolidar.log"
mkdir -p "$HOME/pump-consolidar"
echo "===== $(date) =====" >> "$LOG"
echo "--- suplementos ---" >> "$LOG"
"$PY" "$HOME/pump-suplementos/consolidar.py" >> "$LOG" 2>&1
echo "--- quimica ---" >> "$LOG"
"$PY" "$HOME/pump-quimica/consolidar.py" >> "$LOG" 2>&1
echo "fin $(date)" >> "$LOG"
# recortar log si crece
tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
