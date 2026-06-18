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

    // Regla anti-reducción de proteína (adaptativa):
    //  - 15% tolerancia relativa (era 10%, muy estricto para foods de poca prot)
    //  - O 3g de tolerancia absoluta
    //  - Usamos el MENOR de los dos thresholds (más permisivo) para no descartar
    //    sustitutos razonables cuando el original ya tiene poca prot (ej: papa).
    //  - Si el food original tiene <5g de prot total, regla off (irrelevante).
    const minProt = originalProt < 5
      ? 0
      : Math.min(originalProt * 0.85, originalProt - 3);

    // Cantidad del original en gramos absolutos (para acotar el tamaño del sustituto).
    // Si el original viene en unidad/rebanada/etc., usamos unitGrams si está.
    const originalQtyG = (() => {
      const q = originalFood.qty || 0;
      if (originalFood.unit === 'g' || originalFood.unit === 'ml') return q;
      if (originalFood.unitGrams) return q * originalFood.unitGrams;
      return q; // fallback: asumir gramos
    })();
    // Tope absoluto: el sustituto no puede requerir más de 3× la cantidad del
    // original (con piso de 500g para no descartar foods razonables en porciones chicas).
    const maxQty = Math.max(originalQtyG * 3, 500);

    return db
      .filter(food =>
        food.category === originalCat &&
        food.name.toLowerCase() !== originalFood.name.toLowerCase()
      )
      .map(food => {
        const macroPerGram = (food[dominantMacro] || 0) / 100;
        if (macroPerGram === 0) return null;

        const requiredQty = targetMacroGrams / macroPerGram;

        // Filtro de cantidad absurda (ej: 2kg de alcaparras como sustituto de papa)
        if (requiredQty > maxQty) return null;

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

        // Custom foods (creados por el cliente) bypassean los filtros estrictos
        // de kcal/proteína — la intención de crear un alimento personalizado
        // es usarlo, no que la app lo descarte por macros levemente distintos.
        // Mantenemos solo los filtros de categoría y macro dominante (arriba).
        if (food._isCustom) return result;

        // 1) kcal ratio estrecho (±10%) — solo para alimentos del seed-DB
        if (originalKcal === 0) return null;
        const kcalRatio = result.kcal / originalKcal;
        if (kcalRatio < 0.90 || kcalRatio > 1.10) return null;

        // 2) Regla anti-reducción de proteína (adaptativa, ver arriba)
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
    if (!/polenta|harina|copos? de ma[íi]z|corn flakes|trigo (sarraceno|burgol)|helado|tarta|torta|kuchen|pie|mermelada|jugo|néctar|nectar|licuado|smoothie|jarabe|sirope/.test(name) && (
        /\b(manzana|banan|pl[áa]tano|naranja|mandarin|kiwi|fres|frutilla|uva|pera|durazno|melocot[óo]n|ciruela|mel[óo]n|melon|sand[íi]a|pomelo|mango|anan[áa]|piña|pina|ar[áa]ndano|arandano|cereza|lim[óo]n|limon|papaya|mam[óo]n|maracuy[áa]|higo|frambuesa|mora|d[áa]til|datil|grosella|granada|guayaba|caqui|chirimoya|tuna|n[íi]spero|nispero|carambola|pitaya|lychee|rambut[áa]n|fruta de la pasi[óo]n|coco fresco)\w*/.test(name) ||
        /\b(zanahoria|calabaza|zapallit|zucchini|tomate|pepino|lechug|r[úu]cula|rucula|apio|repollo|berenjena|morr[óo]n|morron|pimiento|cebolla|chauch|arveja|guisante|remolach|champiñ[óo]n|champinon|hongo|esp[áa]rrago|esparrago|alcauci|alcachof|palmito|ma[íi]z|choclo|puerro|acelga|radicheta|endivia|escarola|espinac|br[óo]coli|brocoli|coliflor|kale|repollito|rabanit|r[áa]bano|nabo|hinojo|jalapeñ|jalapeno|chile(?! con carne)|aj[íi] (picante|verde|rojo|amarillo)|pimentón fresco|jengibre fresco|cúrcuma fresca|verduras? salteadas|wok de verduras|ensalada (?!cesar|c[ée]sar))\w*/.test(name) ||
        /^ajo$|^ajos$|^cabeza de ajo/.test(name)
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

/* ---- EXERCISE SWAP ----
 * Espejo de foodSwap, pero para EJERCICIOS. Lee el catálogo en memoria
 * (window.MYPUMP_EJERCICIO_DB, cargado en el bootstrap de cliente.html).
 *
 * REGLA CRÍTICA (no negociable): un sustituto SOLO es válido si tiene el
 * MISMO patron_movimiento (gesto exacto) Y el MISMO primary_muscle que el
 * original. NO se sustituye por otro patrón aunque comparta músculo
 * (press inclinado ≠ press plano ≠ aperturas ≠ press militar).
 *
 * Caso de uso: "la máquina está ocupada, dame la MISMA variante con otro
 * equipo" → por eso ordenamos priorizando equipo DISTINTO al del original.
 *
 * Fail-safe: si el ejercicio no resuelve en el catálogo, o su
 * patron_movimiento es NULL, devolvemos [] (no ofrecemos sustitutos).
 */
window.MyPump.exerciseSwap = {

  // Etiquetas legibles de equipamiento (free-exercise-db → español).
  EQUIP_LABEL: {
    'machine':       'Máquina',
    'dumbbell':      'Mancuernas',
    'barbell':       'Barra',
    'cable':         'Polea',
    'body only':     'Peso corporal',
    'kettlebells':   'Kettlebell',
    'bands':         'Banda',
    'e-z curl bar':  'Barra Z',
    'exercise ball': 'Pelota',
    'medicine ball': 'Balón medicinal',
    'other':         'Otro',
  },

  // Misma normalización que el RPC mypump_match_ejercicio_por_nombre:
  // minúsculas, sin tildes, sin paréntesis, sin sufijos -d1-0, espacios colapsados.
  _norm(s) {
    let n = (s || '').toLowerCase();
    n = n.replace(/[áàäâã]/g,'a').replace(/[éèëê]/g,'e').replace(/[íìïî]/g,'i')
         .replace(/[óòöôõ]/g,'o').replace(/[úùüû]/g,'u').replace(/ñ/g,'n');
    n = n.replace(/\(.*?\)/g,' ');        // paréntesis fuera
    n = n.replace(/-d\d+-\d+/g,' ');       // sufijos de id del ejercicio publicado
    n = n.replace(/[^a-z0-9 ]+/g,' ');     // solo alfanumérico
    n = n.replace(/\s+/g,' ').trim();
    return n;
  },

  // Etiqueta de equipo legible. "Smith" en el name_en → Multipower
  // (free-exercise-db etiqueta los Smith como equipment 'machine'/'barbell').
  _equipLabel(entry) {
    if (/\bsmith\b/i.test(entry.name_en || '')) return 'Multipower';
    return this.EQUIP_LABEL[entry.equipment] || (entry.equipment ? entry.equipment : 'Otro');
  },

  // Resuelve el ejercicio original (de la rutina) a una entrada del catálogo.
  // Prioridad: slug exacto (la rutina lleva images._matched_slug del backfill) →
  // catalogo_slug → nombre normalizado contra name_normalized / aliases_es.
  _resolve(originalEjercicio) {
    const db = window.MYPUMP_EJERCICIO_DB;
    if (!db || !db.length) return null;

    const slug = originalEjercicio.catalogo_slug
              || originalEjercicio.images?._matched_slug
              || originalEjercicio._matched_slug
              || null;
    if (slug) {
      const bySlug = db.find(e => e.slug_en === slug);
      if (bySlug) return bySlug;
    }

    const n = this._norm(originalEjercicio.nombre || originalEjercicio.name || '');
    if (!n) return null;

    // 1) match exacto contra name_normalized del catálogo
    let hit = db.find(e => e.name_normalized === n);
    if (hit) return hit;
    // 2) alias exacto en español
    hit = db.find(e => Array.isArray(e.aliases_es) && e.aliases_es.includes(n));
    if (hit) return hit;
    // 3) contains laxo (el nombre del catálogo contenido en el del cliente o viceversa)
    hit = db.find(e => e.name_normalized && (n.includes(e.name_normalized) || e.name_normalized.includes(n)));
    return hit || null;
  },

  // Devuelve los sustitutos válidos del ejercicio original.
  findSubstitutes(originalEjercicio) {
    const db = window.MYPUMP_EJERCICIO_DB;
    if (!db || !db.length) return [];

    const entry = this._resolve(originalEjercicio);
    if (!entry) return [];

    const patron = entry.patron_movimiento;
    if (!patron) return [];                 // fail-safe: sin patrón → no sugerir

    const muscle    = entry.primary_muscle;
    const origEquip = entry.equipment;

    return db
      .filter(e =>
        e.patron_movimiento === patron &&    // MISMO gesto exacto (hard filter)
        e.primary_muscle === muscle &&       // MISMO músculo
        e.slug_en !== entry.slug_en          // excluir el original
      )
      .map(e => ({
        slug:          e.slug_en,
        name:          (Array.isArray(e.aliases_es) && e.aliases_es[0]) ? e.aliases_es[0] : e.name_en,
        name_en:       e.name_en,
        equipo:        this._equipLabel(e),
        equipmentRaw:  e.equipment,
        primary_muscle:e.primary_muscle,
        patron_movimiento: e.patron_movimiento,
        images: {
          eccentric:  e.image_eccentric  || null,
          concentric: e.image_concentric || null,
        },
        _sameEquip: e.equipment === origEquip,
      }))
      // Priorizar equipo DISTINTO (máquina ocupada → dame la otra variante),
      // luego alfabético por nombre.
      .sort((a, b) => {
        if (a._sameEquip !== b._sameEquip) return a._sameEquip ? 1 : -1;
        return a.name.localeCompare(b.name, 'es');
      })
      .slice(0, 30);
  },

  // Búsqueda libre por nombre dentro de los sustitutos válidos
  // (mantiene todos los constraints de findSubstitutes).
  searchSubstitutes(originalEjercicio, query) {
    const all = this.findSubstitutes(originalEjercicio);
    if (!query) return all;
    const q = query.toLowerCase().trim();
    return all.filter(s => s.name.toLowerCase().includes(q) || (s.name_en||'').toLowerCase().includes(q));
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
