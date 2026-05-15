/* =============================================================
   app.js — MyPump: módulos de lógica del cliente
   ============================================================= */

window.MyPump = {};

/* ---- FOOD SWAP ----
 * Política (decidida con Mati):
 *  - Misma categoría (no cross — proteína por proteína, etc.)
 *  - Mismo macro dominante
 *  - kcal ratio estrecho (±10%) → "macros muy parecidos"
 *  - REGLA ANTI-REDUCCIÓN DE PROTEÍNA: el sustituto no puede tener
 *    significativamente menos prot que el original (tolerancia 10%
 *    para no devolver lista vacía). Esto preserva la prot total del día.
 *  - Top 30 (era 6) → habilita búsqueda libre y "dieta flexible".
 *  - qty calculada para matchear el macro dominante en gramos.
 *  - Incluye custom foods del cliente (push al MYPUMP_FOOD_DB al login).
 */
window.MyPump.foodSwap = {

  findSubstitutes(originalFood) {
    const db = window.MYPUMP_FOOD_DB;
    if (!db || !db.length) return [];

    const originalCat = originalFood.category || this._inferCategory(originalFood);
    if (originalCat === 'condimento') return [];

    const dominantMacro = this._getDominantMacro(originalFood);
    const targetMacroGrams = (originalFood[dominantMacro] || 0);
    const originalKcal = originalFood.kcal;
    const originalProt = originalFood.prot || 0;
    // Tolerancia 10% para no devolver lista vacía si el original tiene mucha prot.
    const minProt = originalProt * 0.9;

    return db
      .filter(food =>
        food.category === originalCat &&
        food.name.toLowerCase() !== originalFood.name.toLowerCase()
      )
      .map(food => {
        const macroPerGram = (food[dominantMacro] || 0) / 100;
        if (macroPerGram === 0) return null;

        const requiredQty = targetMacroGrams / macroPerGram;
        const factor = requiredQty / 100;

        let qty = Math.round(requiredQty);
        let unit = 'g';

        // Convert to unit-based quantity if applicable
        const unitInfo = food.unitGrams ? food : null;
        if (unitInfo && unitInfo.unitGrams) {
          const units = requiredQty / unitInfo.unitGrams;
          if (units >= 0.5) {
            qty = Math.round(units);
            unit = unitInfo.unit || 'unidad';
          }
        }

        const result = {
          name: food.name,
          qty,
          unit,
          kcal: Math.round(food.kcal * factor),
          prot: Math.round(food.prot * factor * 10) / 10,
          carb: Math.round(food.carb * factor * 10) / 10,
          fat:  Math.round(food.fat  * factor * 10) / 10,
          category: food.category,
        };
        if (food._isCustom) result._isCustom = true;

        // 1) kcal ratio estrecho (±10%)
        if (originalKcal === 0) return null;
        const kcalRatio = result.kcal / originalKcal;
        if (kcalRatio < 0.90 || kcalRatio > 1.10) return null;

        // 2) Regla anti-reducción de proteína
        if (result.prot < minProt) return null;

        return result;
      })
      .filter(Boolean)
      .sort((a, b) => {
        const targetKcal = originalFood.kcal;
        return Math.abs(a.kcal - targetKcal) - Math.abs(b.kcal - targetKcal);
      })
      .slice(0, 30);
  },

  // Búsqueda libre por nombre dentro de los sustitutos válidos.
  // Mantiene todos los constraints de findSubstitutes (misma categoría,
  // mismo macro dominante, kcal ±10%, no reduce proteína).
  searchSubstitutes(originalFood, query) {
    const all = this.findSubstitutes(originalFood);
    if (!query) return all;
    const q = query.toLowerCase().trim();
    return all.filter(f => f.name.toLowerCase().includes(q));
  },

  _inferCategory(food) {
    const total = (food.prot||0) + (food.carb||0) + (food.fat||0);
    if (total === 0) return 'condimento';
    const pPct = food.prot / total, cPct = food.carb / total, fPct = food.fat / total;
    if (pPct > 0.5) return 'proteina';
    if (cPct > 0.5) return 'carbohidrato';
    if (fPct > 0.5) return 'grasa';
    if (food.prot > 0 && food.carb > 0 && fPct < 0.3) return 'lacteo';
    if (cPct > 0.4) return 'fruta_verdura';
    return 'mixto';
  },

  _getDominantMacro(food) {
    const kcalFromProt = (food.prot||0) * 4;
    const kcalFromCarb = (food.carb||0) * 4;
    const kcalFromFat  = (food.fat||0)  * 9;
    if (kcalFromProt >= kcalFromCarb && kcalFromProt >= kcalFromFat) return 'prot';
    if (kcalFromCarb >= kcalFromFat) return 'carb';
    return 'fat';
  },
};

/* ---- UI HELPERS ---- */
window.MyPump.ui = {

  /**
   * Muestra un modal de confirmación genérico.
   * @param {object} opts
   * @param {string} opts.title        — Título del modal
   * @param {string} [opts.body]       — Texto descriptivo (opcional)
   * @param {string} [opts.confirmLabel] — Label del botón de confirmar (default: "Confirmar")
   * @param {string} [opts.cancelLabel]  — Label del botón de cancelar (default: "Cancelar")
   * @returns {Promise<boolean>}        — true si confirmó, false si canceló/cerró
   */
  showConfirmModal({ title, body = '', confirmLabel = 'Confirmar', cancelLabel = 'Cancelar' }) {
    return new Promise(resolve => {
      const host = document.getElementById('modalHost');
      if (!host) { resolve(false); return; }

      host.innerHTML = `
        <div class="modal-back" id="confirmBack">
          <div class="modal-sheet" style="max-width:380px">
            <div class="modal-handle"></div>
            <div class="modal-title">${title}</div>
            ${body ? `<div class="modal-text">${body}</div>` : ''}
            <button class="btn-primary" id="confirmYes">${confirmLabel}</button>
            <button class="btn-secondary" id="confirmNo">${cancelLabel}</button>
          </div>
        </div>`;

      function close(result) {
        host.innerHTML = '';
        resolve(result);
      }

      document.getElementById('confirmYes').addEventListener('click', () => close(true));
      document.getElementById('confirmNo').addEventListener('click',  () => close(false));
      document.getElementById('confirmBack').addEventListener('click', e => {
        if (e.target.id === 'confirmBack') close(false);
      });
    });
  },
};
