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

  // ── Matcher por REGLAS español → slug (gesto exacto) ──────────────
  // Las rutinas publicadas guardan el nombre en español, sin slug y a veces sin
  // imágenes. El RPC trigram contra el catálogo en inglés es PELIGROSO (matchea
  // "pullover" con "crunch"), así que resolvemos con reglas determinísticas —
  // el mismo set que usamos para asignar imágenes (semánticamente correcto).
  // Orden = prioridad (la primera que matchea gana). Específico → general.
  _RESOLVE_RULES: [
    [/cinta.*trote|trote suave|cinta.*suave/, 'Jogging_Treadmill'],
    [/cinta|caminadora|treadmill/, 'Running_Treadmill'],
    [/rollout|ab wheel|rueda abdom/, 'Ab_Roller'],
    [/crunch.*maquina|crunch en m/, 'Ab_Crunch_Machine'],
    [/plancha|plank/, 'Plank'],
    [/remo.*maquina palanca|palanca|leverage.*row|iso.?row/, 'Leverage_Iso_Row'],
    [/remo.*polea.*sentad|seated cable row|remo en polea sentad/, 'Seated_Cable_Rows'],
    [/remo.*menton|upright row/, 'Upright_Cable_Row'],
    [/remo.*polea|cable row/, 'Seated_Cable_Rows'],
    [/remo.*mancuern/, 'Bent_Over_Two-Dumbbell_Row'],
    [/remo.*barra|remo con barra/, 'Bent_Over_Barbell_Row'],
    [/jalon.*neutr|jalon.*v.?bar|agarre neutro/, 'V-Bar_Pulldown'],
    [/jalon.*pecho|jalon.*prono|pulldown|jalon/, 'Wide-Grip_Lat_Pulldown'],
    [/pajaro|reverse.*fly|reverse pec deck|deltoides posterior/, 'Reverse_Machine_Flyes'],
    [/face pull/, 'Face_Pull'],
    [/elevac.*later.*polea|elevac.*later.*cable|elevac.*later.*una mano/, 'Cable_Seated_Lateral_Raise'],
    [/elevac.*later/, 'Side_Lateral_Raise'],
    [/extension.*overhead.*cuerda|overhead.*cuerda|rope.*overhead/, 'Cable_Rope_Overhead_Triceps_Extension'],
    [/extension.*overhead.*mancuern|overhead.*mancuern/, 'Seated_Triceps_Press'],
    [/extension.*polea alta|extension.*tricep.*polea|polea alta.*tricep|extension.*barra.*tricep|extension de tricep/, 'Triceps_Pushdown'],
    [/push.?down/, 'Triceps_Pushdown'],
    [/patada.*tricep|tricep.*kickback/, 'Tricep_Dumbbell_Kickback'],
    [/press cerrad.*smith|press cerrad.*multipower/, 'Smith_Machine_Close-Grip_Bench_Press'],
    [/press cerrad|close.?grip.*bench/, 'Close-Grip_Barbell_Bench_Press'],
    [/press.*inclin.*maquin/, 'Leverage_Incline_Chest_Press'],
    [/press.*inclin.*mancuern/, 'Incline_Dumbbell_Press'],
    [/press.*inclin.*smith|press.*inclin.*multipower/, 'Smith_Machine_Incline_Bench_Press'],
    [/press.*inclin/, 'Barbell_Incline_Bench_Press_-_Medium_Grip'],
    [/press.*plano.*maquin/, 'Leverage_Chest_Press'],
    [/press.*plano.*mancuern/, 'Dumbbell_Bench_Press'],
    [/press.*plano.*smith|press.*plano.*multipower/, 'Smith_Machine_Bench_Press'],
    [/press.*plano|press banca/, 'Barbell_Bench_Press_-_Medium_Grip'],
    [/press.*militar.*maquin|press hombros?.*maquin|press.*hombro.*maquin/, 'Machine_Shoulder_Military_Press'],
    [/press.*mancuern.*sentad|press hombros?.*mancuern|press.*hombro.*mancuern/, 'Seated_Dumbbell_Press'],
    [/press.*hombro|press.*militar/, 'Seated_Dumbbell_Press'],
    [/apertur.*inclin/, 'Incline_Dumbbell_Flyes'],
    [/cruce.*polea.*bajo|low cable cross/, 'Low_Cable_Crossover'],
    [/apertur.*polea|cruce.*polea|crossover/, 'Cable_Crossover'],
    [/apertur|pec deck|butterfly/, 'Butterfly'],
    [/fondos|dips/, 'Dips_-_Chest_Version'],
    [/curl.*predicad.*maquin|preacher.*machine/, 'Machine_Preacher_Curls'],
    [/curl.*predicad/, 'Preacher_Curl'],
    [/curl.*martillo|hammer/, 'Hammer_Curls'],
    [/curl.*spider|spider/, 'Spider_Curl'],
    [/curl.*inclin/, 'Incline_Dumbbell_Curl'],
    [/curl.*invers|reverse.*curl|curl inverso/, 'Reverse_Cable_Curl'],
    [/curl.*polea.*una mano|curl.*cable.*una mano|curl en cable a una mano/, 'Standing_One-Arm_Cable_Curl'],
    [/curl.*polea|curl.*cable/, 'Standing_Biceps_Cable_Curl'],
    [/curl.*mancuern.*sentad/, 'Seated_Dumbbell_Curl'],
    [/curl.*mancuern/, 'Dumbbell_Bicep_Curl'],
    [/curl.*barra/, 'Barbell_Curl'],
    [/curl femoral.*sentad|leg curl.*sentad|femoral sentad/, 'Seated_Leg_Curl'],
    [/curl femoral|leg curl|hamstring curl|femoral/, 'Lying_Leg_Curls'],
    [/extension.*cuad|leg extension|cuadricep/, 'Leg_Extensions'],
    [/prensa|leg press/, 'Leg_Press'],
    [/hack squat|sentadilla hack|sentadilla jaca/, 'Hack_Squat'],
    [/sentadilla.*bulgar|split squat|bulgara/, 'Split_Squat_with_Dumbbells'],
    [/sentadilla.*smith|smith.*squat|sentadilla.*multipower/, 'Smith_Machine_Squat'],
    [/sentadilla|squat/, 'Barbell_Squat'],
    [/zancada|lunge|estocada/, 'Dumbbell_Lunges'],
    [/peso muerto.*rumano|romanian|rdl.*mancuern/, 'Stiff-Legged_Dumbbell_Deadlift'],
    [/\brdl\b|peso muerto.*rigid|stiff.?leg/, 'Romanian_Deadlift'],
    [/peso muerto|deadlift/, 'Barbell_Deadlift'],
    [/hip thrust|empuje de cadera/, 'Barbell_Hip_Thrust'],
    [/puente.*gluteo|glute bridge/, 'Barbell_Glute_Bridge'],
    [/patada.*gluteo|patada.*tras|kickback.*glute/, 'One-Legged_Cable_Kickback'],
    [/abductor|abduccion/, 'Thigh_Abductor'],
    [/aductor|aduccion/, 'Thigh_Adductor'],
    [/soleo|talon sentad|seated calf/, 'Seated_Calf_Raise'],
    [/talon.*multipower|talon.*smith|smith.*calf/, 'Smith_Machine_Calf_Raise'],
    [/talon|gemelo|\bcalf\b|gastrocnem|pantorrilla/, 'Standing_Calf_Raises'],
    [/encogim|shrug|trapecio/, 'Dumbbell_Shrug'],
    [/elevac.*frontal|front raise/, 'Front_Cable_Raise'],
    [/pullover.*mancuern/, 'Straight-Arm_Dumbbell_Pullover'],
    [/pullover/, 'Straight-Arm_Pulldown'],
    [/skull|press frances|french|rompecraneo/, 'EZ-Bar_Skullcrusher'],
    [/dominad|pull.?up|pullup/, 'Pullups'],
    [/flexion|push.?up|lagartij/, 'Pushups'],
  ],

  _resolveByRules(nombre) {
    const n = this._norm(nombre);
    if (!n) return null;
    for (const [re, slug] of this._RESOLVE_RULES) {
      if (re.test(n)) return slug;
    }
    return null;
  },

  // Resuelve el ejercicio original (de la rutina) a una entrada del catálogo.
  // Prioridad: slug explícito → slug embebido en la URL de imagen →
  // matcher por reglas (ES→slug) → alias/nombre exacto. SIN trigram (peligroso).
  _resolve(originalEjercicio) {
    const db = window.MYPUMP_EJERCICIO_DB;
    if (!db || !db.length) return null;

    const byId = {};
    for (const e of db) byId[e.slug_en] = e;

    // 1) slug explícito (catalogo_slug / _matched_slug)
    let slug = originalEjercicio.catalogo_slug
            || originalEjercicio.images?._matched_slug
            || originalEjercicio._matched_slug
            || null;
    if (slug && byId[slug]) return byId[slug];

    // 2) slug embebido en la URL de imagen: .../exercise-images/<SLUG>/<0|1>.jpg
    const imgUrl = originalEjercicio.images?.eccentric || originalEjercicio.images?.concentric || '';
    const m = /exercise-images\/([^/]+)\//.exec(imgUrl);
    if (m && byId[m[1]]) return byId[m[1]];

    // 3) matcher por reglas español → slug (gesto exacto)
    slug = this._resolveByRules(originalEjercicio.nombre || originalEjercicio.name || '');
    if (slug && byId[slug]) return byId[slug];

    // 4) alias / nombre normalizado exacto (sin contains laxo: evita falsos cruces)
    const nn = this._norm(originalEjercicio.nombre || originalEjercicio.name || '');
    if (!nn) return null;
    let hit = db.find(e => e.name_normalized === nn);
    if (hit) return hit;
    hit = db.find(e => Array.isArray(e.aliases_es) && e.aliases_es.includes(nn));
    return hit || null;
  },

  // ── Traductor compositivo name_en → español ───────────────────────
  // El catálogo (free-exercise-db) está en inglés. Para mostrar los sustitutos
  // en español componemos: BASE (gesto) + MODIFICADORES (inclinado/sentado…) +
  // EQUIPO (con barra / en polea…). Orden de listas = específico → general.
  _BASE_ES: [
    [/romanian deadlift/, 'Peso muerto rumano'],
    [/stiff.?leg.*deadlift|stiff legged/, 'Peso muerto piernas rígidas'],
    [/sumo deadlift/, 'Peso muerto sumo'],
    [/trap bar deadlift/, 'Peso muerto con trap bar'],
    [/deadlift/, 'Peso muerto'],
    [/good morning/, 'Buenos días'],
    [/leg press/, 'Prensa de piernas'],
    [/hack squat/, 'Hack squat'],
    [/split squat|bulgarian/, 'Sentadilla búlgara'],
    [/front squat/, 'Sentadilla frontal'],
    [/squat/, 'Sentadilla'],
    [/walking lunge/, 'Zancadas caminando'],
    [/lunge|lunges/, 'Zancadas'],
    [/step-?up/, 'Subida al cajón'],
    [/leg extension/, 'Extensión de cuádriceps'],
    [/lying leg curl/, 'Curl femoral acostado'],
    [/seated leg curl/, 'Curl femoral sentado'],
    [/leg curl|glute ham|nordic/, 'Curl femoral'],
    [/hip thrust/, 'Hip thrust'],
    [/glute bridge/, 'Puente de glúteos'],
    [/(glute|cable) kickback|kickback/, 'Patada de glúteo'],
    [/thigh abductor|hip abduction|abductor/, 'Abductores'],
    [/thigh adductor|hip adduction|adductor/, 'Aductores'],
    [/seated calf raise|calf raise.*seated/, 'Elevación de talones sentado'],
    [/calf raise|calf press|calves/, 'Elevación de talones'],
    [/bench press/, 'Press de banca'],
    [/chest press/, 'Press de pecho'],
    [/shoulder press|military press/, 'Press militar'],
    [/overhead press|push press/, 'Press sobre la cabeza'],
    [/arnold press/, 'Press Arnold'],
    [/floor press/, 'Press en el piso'],
    [/\bpress\b/, 'Press'],
    [/lat pulldown|pulldown|pull-down|pull down/, 'Jalón al pecho'],
    [/chin-?up/, 'Dominadas supinas'],
    [/pull-?up|pullup/, 'Dominadas'],
    [/straight-?arm|pullover/, 'Pullover'],
    [/upright row/, 'Remo al mentón'],
    [/t-bar row/, 'Remo en T'],
    [/\brows?\b/, 'Remo'],
    [/face pull/, 'Face pull'],
    [/rear delt|reverse fly|reverse machine fly|rear lateral/, 'Pájaros'],
    [/lateral raise|side lateral/, 'Elevaciones laterales'],
    [/front raise/, 'Elevaciones frontales'],
    [/shrug/, 'Encogimientos'],
    [/pec deck|butterfly/, 'Pec deck'],
    [/crossover|cross over|cable cross/, 'Cruce de poleas'],
    [/fly|flye/, 'Aperturas'],
    [/hammer curl/, 'Curl martillo'],
    [/preacher curl/, 'Curl predicador'],
    [/spider curl/, 'Curl araña'],
    [/concentration curl/, 'Curl concentrado'],
    [/reverse curl/, 'Curl invertido'],
    [/wrist curl/, 'Curl de muñeca'],
    [/bicep.*curl|curl/, 'Curl de bíceps'],
    [/pushdown|push-down|push down/, 'Extensión de tríceps en polea'],
    [/skull|french press|nose breaker/, 'Press francés'],
    [/overhead.*(triceps|extension)|triceps.*overhead/, 'Extensión de tríceps sobre la cabeza'],
    [/triceps? (extension|press)|extension.*triceps/, 'Extensión de tríceps'],
    [/dips?\b/, 'Fondos'],
    [/push-?up|pushup/, 'Flexiones'],
    [/rollout|roller|ab wheel/, 'Rollout'],
    [/plank/, 'Plancha'],
    [/hanging.*raise|leg raise|knee raise/, 'Elevación de piernas'],
    [/russian twist|oblique|woodchop|wood chop/, 'Oblicuos'],
    [/crunch|sit-?up/, 'Crunch'],
    [/hyperextension|back extension/, 'Hiperextensiones'],
  ],
  _EQUIP_ES: [
    [/\bsmith\b/, 'en multipower'],
    [/leverage|lever |machine/, 'en máquina'],
    [/cable|pulley/, 'en polea'],
    [/e-?z[ -]?(curl )?bar/, 'con barra Z'],
    [/dumbbell|\bdb\b/, 'con mancuernas'],
    [/barbell/, 'con barra'],
    [/kettlebell/, 'con kettlebell'],
    [/\bband\b|bands/, 'con banda'],
    [/exercise ball|ball /, 'con pelota'],
  ],
  _MOD_ES: [
    [/incline/, 'inclinado'],
    [/decline/, 'declinado'],
    [/close-?grip/, 'agarre cerrado'],
    [/wide-?grip/, 'agarre ancho'],
    [/one-?arm|single-?arm|one arm/, 'a una mano'],
  ],

  // Traduce el nombre de un ejercicio del catálogo a español compositivo.
  // Devuelve el name_en si no encuentra base (mejor inglés que algo roto).
  _toEs(entry) {
    const en = (entry.name_en || '').toLowerCase();
    if (!en) return entry.slug_en ? entry.slug_en.replace(/_/g, ' ') : '';
    let base = null;
    for (const [re, es] of this._BASE_ES) { if (re.test(en)) { base = es; break; } }
    if (!base) return entry.name_en;          // fallback: inglés
    let eq = '';
    for (const [re, es] of this._EQUIP_ES) { if (re.test(en)) { eq = es; break; } }
    const mods = [];
    for (const [re, es] of this._MOD_ES) { if (re.test(en)) mods.push(es); }
    let out = base;
    if (mods.length) out += ' ' + mods.join(' ');
    // Evitar redundancia: no agregar el equipo si la base ya lo implica
    // ('Cruce de poleas' ya tiene polea, 'Prensa de piernas' no lleva equipo, etc.)
    const eqCore = { 'en polea':'polea','en máquina':'máquina','en multipower':'multipower','con barra':'barra','con mancuernas':'mancuern','con kettlebell':'kettlebell','con banda':'banda','con barra Z':'barra z','con pelota':'pelota' };
    if (eq && !out.toLowerCase().includes(eqCore[eq] || eq.toLowerCase())) out += ' ' + eq;
    return out;
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
        // Nombre traducido al español (compositivo). aliases_es del catálogo son
        // keywords genéricas ('remo','jalon'), no sirven para distinguir variantes.
        name:          this._toEs(e),
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
      // Dedup por nombre+equipo: varias variantes casi idénticas traducen al
      // mismo nombre ('Dominadas [Peso corporal]' ×3). Conservamos la primera.
      .filter((s, i, arr) => arr.findIndex(x => x.name === s.name && x.equipo === s.equipo) === i)
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
