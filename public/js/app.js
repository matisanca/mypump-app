/* =============================================================
   app.js — MyPump: módulos de lógica del cliente
   ============================================================= */

window.MyPump = {};

/* ---- FOOD SWAP ---- */
window.MyPump.foodSwap = {

  findSubstitutes(originalFood) {
    const db = window.MYPUMP_FOOD_DB;
    if (!db || !db.length) return [];

    const originalCat = originalFood.category || this._inferCategory(originalFood);
    if (originalCat === 'condimento') return [];

    const dominantMacro = this._getDominantMacro(originalFood);
    const targetMacroGrams = (originalFood[dominantMacro] || 0) * (originalFood.qty / 100);
    const originalKcal = originalFood.kcal * (originalFood.qty / 100);

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

        // Validate kcal ratio against ORIGINAL (not scaled)
        if (originalKcal === 0) return null;
        const kcalRatio = result.kcal / originalKcal;
        if (kcalRatio < 0.85 || kcalRatio > 1.15) return null;

        return result;
      })
      .filter(Boolean)
      .sort((a, b) => {
        const targetKcal = originalFood.kcal * (originalFood.qty / 100);
        return Math.abs(a.kcal - targetKcal) - Math.abs(b.kcal - targetKcal);
      })
      .slice(0, 6);
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
