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

  // Idéntica a inferFoodCategory en cliente.html / inferCategory en food-db.js.
  // Keyword-first → reglas explícitas para no confundir asado/milanesa/hongos/etc.
  // Fallback heurístico solo cuando ningún keyword matchea.
  _inferCategory(food) {
    const name = (food.name || '').toLowerCase();
    if (/\b(carne|asado|bife|lomo|paleta|matambre|vacío|vacio|costill|nalga|cuadril|cuadrada|entraña|entrana|hígado|higado|cerdo|lechón|lechon|bondiola|jam[óo]n|salame|chorizo|longaniza|morcilla|salchicha|panceta|tocino|pollo|pavo|pato|pechuga|muslo|alita|pescado|salm[óo]n|merluza|atún|atun|sardin|trucha|lenguado|langostino|camar[óo]n|camaron|mejill[óo]n|mejillon|calamar|pulpo|kani|surimi|huevo|clara de huevo|tofu|tempeh|seit[áa]n|seitan|prote[íi]na (whey|de soja|vegetal)|pavita|cordero|cabrito|conejo|vísc|visc|chinchulín|riñón|rinon|mondongo|carpaccio|carne picada|hamburguesa)/.test(name)
        && !/leche|yogur|queso/.test(name)) return 'proteina';
    if (/\b(leche(?! de coco)|yogur|yoghurt|kéfir|kefir|requesón|cottage|cuajada|nata|burrata|mozzarella|mozarella|provolone|provoleta|parmesano|reggianito|queso|cheddar|gouda|gruyere|brie|camembert|gorgonzola|fontina|sardo|tybo|port salut|ricotta|crema de leche|caf[ée] con leche|leche de soja|cacao con leche|chocolatada)\b/.test(name))
      return 'lacteo';
    if (/\b(aceite|manteca|mantequilla|margarina|mayonesa|crema (?!de leche)|nuez|nueces|almendra|cacahuet|cacahuete|man[íi] |\bmaní$|pistacho|avellana|castaña|piñ[óo]n|semilla|ch[íi]a|lin(o|aza)|s[ée]samo|sesamo|chía|coco rallado|leche de coco|aceitun|olivas|palta|aguacate|tahini|mantequilla de maní|mantequilla de almendras|ghee|sebo)\b/.test(name))
      return 'grasa';
    if (!/polenta|harina|copos? de ma[íi]z|corn flakes|trigo (sarraceno|burgol)/.test(name) && (
        /\b(manzana|banana|plátano|platano|naranja|mandarina|kiwi|fresa|frutilla|uva|pera|durazno|melocot[óo]n|melocoton|ciruela|mel[óo]n|melon|sandía|sandia|pomelo|mango|ananá|anana|piña|pina|ar[áa]ndano|arandano|cereza|lim[óo]n|limon|papaya|mam[óo]n|maracuyá|maracuya|higo|frambuesa|mora|d[áa]til|datil|grosella|granada|guayaba|caqui|chirimoya|tuna|nispero|n[íi]spero|carambola|pitaya|lychee|rambut[áa]n|fruta de la pasi[óo]n|coco fresco)\b/.test(name) ||
        /\b(zanahoria|calabaza|zapallito|zucchini|tomate|pepino|lechuga|rúcula|rucula|apio|repollo|berenjena|morr[óo]n|morron|pimiento|cebolla|ajo(?! en polvo)|chauch|arveja|guisante|remolacha|champiñ[óo]n|champinon|hongo|esp[áa]rrago|esparrago|alcauci|alcachof|palmito|ma[íi]z|choclo|puerro|acelga|radicheta|endivia|escarola|espinaca|brócoli|brocoli|coliflor|kale|repollito|rabanito|r[áa]bano|nabo|hinojo|jengibre fresco|cúrcuma fresca|verduras? salteadas|wok de verduras|ensalada (?!cesar|c[ée]sar))/.test(name)
      )) return 'fruta_verdura';
    if (/\b(papa(?! frita)|patata(?! frita)|batata|camote|boniato|yuca|mandioca|cassava|tap[íi]oca|tapioca|polenta|plátano macho|platano macho)\b/.test(name))
      return 'carbohidrato';
    if (/\b(lenteja|garbanzo|frijol|poroto|jud[íi]a blanca|judia blanca|alubia|haba|soja cocida|soya|edamame|chícharo|chicharo)\b/.test(name))
      return 'carbohidrato';
    if (/\b(arroz|pasta|fideo|spaguett|spaghet|tallarines|ravioli|ñoqui|gnocch|pan(?! con|cake)|pancake|hotcake|tostada|harina|avena|cuscus|cousc[óo]us|quinoa|cebada|bulgur|trigo (sarraceno)?|cereal|granola|galleta|tortilla(?! española)|bollillo|telera|pita|wrap|arepa|crouton|chocolate|miel|az[úu]car|edulcorante|mermelada|dulce de leche|alfajor|barrita|snack|cracker|chip|salsa de tomate|kétchup|ketchup|panqueque|waffle|donut|crep|brownie|muffin|budín|budin|bizcoch|torta|magdalena|barra cereal|gomitas|caramelo|chuche)\b/.test(name))
      return 'carbohidrato';
    if (/\b(mostaza|vinagre|sal\b|pimienta|albahaca|comino|perejil|orégano|oregano|romero|tomillo|laurel|nuez moscada|p[áa]prika|cilantro|hierba|condimento|caldo cubo|sazonador|chimichurri|salsa picante|tabasco|sriracha)\b/.test(name))
      return 'condimento';
    // Fallback heurístico
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
