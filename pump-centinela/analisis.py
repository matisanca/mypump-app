#!/usr/bin/env python3
"""Motor de análisis de los checks semanales (P7).

Módulo puro: NO manda WhatsApp ni toca la red salvo por la interpretación de
la nota. Recibe los datos ya fetcheados y devuelve, por cliente, un veredicto
en tres baldes: ajustar | observar | bien.

Por qué existe: hasta ahora el check se evaluaba como FOTO PUNTUAL (energía<=2,
adherencia<=3...). Eso genera falsos positivos —el que siempre reporta 3
disparaba igual que el que se desplomó de 5 a 3— y no ve tendencias. Acá se
compara a cada cliente contra SU PROPIA normalidad (baseline) y se cruzan las
señales objetivas (peso, entreno, fuerza) con las subjetivas.

Reglas duras primero (deterministas, baratas); la IA solo interpreta la nota
y redacta. Así la decisión no depende del humor del modelo.
"""
import re
from datetime import date, timedelta
from statistics import median

# ── Escalas: 1-5. Mayor = mejor, SALVO hambre (5 = mucha hambre = peor). ──
METRICAS = ('energia', 'descanso', 'hambre', 'adherencia')

def _norm(m, v):
    """Normaliza a 'mayor = mejor' para poder tratarlas igual."""
    if v is None: return None
    return (6 - v) if m == 'hambre' else v

def lunes(d):
    return d - timedelta(days=d.weekday())

# ══════════════ 1) Señales por métrica ══════════════
def perfil_metrica(serie_norm):
    """serie_norm: [(semana_lunes, valor_normalizado)] ordenada ASC, la última
    es la semana en curso. Devuelve dict con baseline y estado."""
    if not serie_norm: return None
    valor = serie_norm[-1][1]
    previas = [v for _, v in serie_norm[:-1] if v is not None][-8:]
    if valor is None: return None
    base = median(previas) if len(previas) >= 2 else None
    delta = (valor - base) if base is not None else None

    # Tendencia: media de las 2 últimas cerradas vs las 2 anteriores
    vals = [v for _, v in serie_norm if v is not None]
    tend = None
    if len(vals) >= 4:
        tend = (vals[-1] + vals[-2]) / 2 - (vals[-3] + vals[-4]) / 2

    estado = 'estable'
    if valor <= 2:
        estado = 'critico'                      # piso duro, siempre marca
    elif delta is not None and delta <= -1.5:
        estado = 'caida'
    elif delta is not None and delta <= -1 and (tend or 0) < 0:
        estado = 'caida'
    elif base is not None and base <= 2.5 and (delta is None or abs(delta) < 0.5):
        estado = 'bajo_cronico'                 # viene mal hace rato y nadie lo toco
    elif delta is not None and delta >= 1:
        estado = 'mejora'

    return {'valor': valor, 'baseline': base, 'delta': delta, 'tendencia': tend, 'estado': estado}

# ══════════════ 2) Señales cruzadas ══════════════
def _pend_pct(serie):
    """Variación % entre la media de las 2 últimas y las 2 anteriores."""
    v = [x for x in serie if x not in (None, 0)]
    if len(v) < 4: return None
    rec = (v[-1] + v[-2]) / 2
    pre = (v[-3] + v[-4]) / 2
    return None if pre == 0 else (rec - pre) / pre * 100

def señales_cruzadas(ctx, perfiles):
    """Las que valen de verdad: combinan objetivo + peso + fuerza + adherencia."""
    out = []
    obj = ctx.get('obj')
    dpeso = ctx.get('delta_peso_g')
    en_rango = ctx.get('peso_en_rango')
    fuerza = ctx.get('var_e1rm')          # % vs 4 semanas atrás
    adh_entreno = ctx.get('adh_entreno')  # sesiones/dias_plan de la semana
    ener = (perfiles.get('energia') or {}).get('valor')
    hamb = (perfiles.get('hambre') or {}).get('valor')      # normalizado (5=sin hambre)
    adh = (perfiles.get('adherencia') or {}).get('valor')

    if obj == 'definicion' and en_rango and ener is not None and ener <= 2 and hamb is not None and hamb <= 2:
        out.append(('deficit_costoso',
                    'el deficit esta funcionando pero le esta costando (energia baja + mucha hambre)',
                    'evaluar refeed o diet break, NO recortar mas calorias', 2))

    if obj == 'definicion' and dpeso is not None and dpeso > -100 and adh is not None and adh >= 4:
        out.append(('estancado_pese_adherencia',
                    'peso estancado pero reporta buena adherencia',
                    'PREGUNTAR antes de tocar nada: puede ser sub-registro o menos gasto diario', 2))

    if obj == 'volumen' and en_rango is False and dpeso is not None and dpeso > 0 and (fuerza is None or fuerza < 1):
        out.append(('sube_sin_rendir',
                    'sube de peso pero la fuerza no acompana',
                    'recortar el superavit: esta ganando mas grasa que musculo', 2))

    if adh_entreno is not None and adh_entreno < 0.6 and (fuerza is None or fuerza >= -2):
        out.append(('falta_asistencia',
                    'entrena menos dias de los planificados pero mantiene fuerza',
                    'es problema de ASISTENCIA, no del programa: no cambiar la rutina', 1))

    d = (perfiles.get('descanso') or {}).get('valor')
    if d is not None and d <= 2 and ener is not None and ener <= 2 and (fuerza is not None and fuerza < -3):
        out.append(('sobrealcance',
                    'descanso y energia bajos con la fuerza cayendo',
                    'considerar deload esta semana', 3))
    return out

# ══════════════ 3) Interpretación de la nota (banderas) ══════════════
# Fallback determinista por si no hay LLM disponible. Nunca peor que hoy.
BANDERAS_RX = {
    'lesion':       r'lesion|lesión|dolor|duele|molest|desgarr|tendin|pinchazo|contractur',
    'enfermedad':   r'enferm|fiebre|gripe|covid|angina|virus|antibiotic',
    'viaje':        r'viaj|vacacion|vacación|afuera|hotel|congreso',
    'evento':       r'cumple|casamiento|fiesta|asado|evento|finde largo',
    'estres':       r'estres|estrés|ansiedad|laburo|trabajo|examen|mudanza',
    'desmotivacion':r'no puedo|dejar|bajon|bajón|desmotiv|sin ganas|cuesta mucho',
}
SUPRIMEN = ('viaje', 'evento', 'enfermedad')   # explican una mala semana

def banderas_por_regex(nota):
    if not nota: return []
    n = nota.lower()
    return [b for b, rx in BANDERAS_RX.items() if re.search(rx, n)]

# ══════════════ 4) Veredicto ══════════════
DISPARADORES_DUROS = {
    'lesion', 'sin_entrenar', 'peso_fuera_2sem', 'metrica_critica', 'adh_entreno_muy_baja',
}

def evaluar_cliente(nombre, ctx, checks, nota_extra=None, ultimo_ajuste=None, hoy=None):
    """checks: lista de filas de mypump_checkin_semanal ordenada ASC por semana.
    nota_extra: dict del LLM {banderas, temas, repite_tema, cita} o None.
    Devuelve dict con balde, motivos, señales y perfiles."""
    hoy = hoy or date.today()
    w0 = lunes(hoy)
    actual = next((c for c in checks if c['semana_lunes'] == w0.isoformat()), None)

    # madurez: cuantos checks tiene (define si podemos hablar de tendencia)
    n_checks = len([c for c in checks if c.get('energia')])
    madurez = 'nueva' if n_checks < 2 else ('parcial' if n_checks < 4 else 'completa')

    perfiles = {}
    if actual:
        for m in METRICAS:
            serie = [(c['semana_lunes'], _norm(m, c.get(m))) for c in checks]
            p = perfil_metrica(serie)
            if p: perfiles[m] = p

    banderas = list((nota_extra or {}).get('banderas') or [])
    if not nota_extra and actual:
        banderas = banderas_por_regex(actual.get('nota'))

    motivos = []
    duros_absolutos = set()    # nunca se suprimen por contexto
    duros_suprimibles = set()  # una semana de viaje/enfermedad SI los explica

    # -- Disparadores que NO se suprimen nunca --
    if 'lesion' in banderas:
        motivos.append('reporta una lesion o dolor'); duros_absolutos.add('lesion')
    if ctx.get('peso_fuera_2sem'):
        # 2 semanas de tendencia no las explica un viaje de una semana
        motivos.append('peso fuera del rango 2 semanas seguidas'); duros_absolutos.add('peso_fuera_2sem')

    # -- Disparadores que un contexto explicito SI explica --
    if ctx.get('sin_entrenar'):
        motivos.append('sin entrenar hace 2+ semanas'); duros_suprimibles.add('sin_entrenar')
    if ctx.get('adh_entreno') is not None and ctx['adh_entreno'] < 0.5:
        motivos.append('entreno menos de la mitad de los dias del plan'); duros_suprimibles.add('adh_entreno_muy_baja')
    for m, p in perfiles.items():
        if p['estado'] == 'critico':
            motivos.append(f'{m} en {p["valor"]}/5'); duros_suprimibles.add('metrica_critica')

    # -- Señales blandas (tendencia, baseline, cruces) --
    blandas = 0
    for m, p in perfiles.items():
        if p['estado'] == 'caida':
            base = f"{p['baseline']:.0f}" if p['baseline'] is not None else '?'
            motivos.append(f'{m} cayo a {p["valor"]}/5 (venia en {base})'); blandas += 1
        elif p['estado'] == 'bajo_cronico':
            motivos.append(f'{m} viene bajo hace semanas ({p["valor"]}/5)'); blandas += 1

    cruces = señales_cruzadas(ctx, perfiles)
    for _, desc, _, sev in cruces:
        motivos.append(desc); blandas += sev

    # -- Compuertas --
    contexto_explica = any(b in SUPRIMEN for b in banderas)
    if duros_absolutos:
        balde = 'ajustar'
    elif duros_suprimibles and not contexto_explica:
        balde = 'ajustar'
    elif duros_suprimibles and contexto_explica:
        balde = 'observar'
        motivos.append(f'contexto: {", ".join(b for b in banderas if b in SUPRIMEN)}')
    elif blandas == 0:
        balde = 'bien'
    elif contexto_explica:
        balde = 'observar'
        motivos.append(f'contexto: {", ".join(b for b in banderas if b in SUPRIMEN)}')
    elif madurez == 'nueva':
        balde = 'observar'   # sin historia no inventamos tendencias
    elif ultimo_ajuste and ultimo_ajuste.get('semanas_atras', 99) < 2:
        balde = 'observar'
        motivos.append('se ajusto hace menos de 2 semanas: dar tiempo')
    else:
        balde = 'ajustar' if blandas >= 2 else 'observar'

    if not actual:
        balde = 'sin_check'

    return {
        'nombre': nombre, 'balde': balde, 'motivos': motivos, 'perfiles': perfiles,
        'cruces': cruces, 'banderas': banderas, 'madurez': madurez,
        'nota': (actual or {}).get('nota'), 'check': actual,
    }

# ══════════════ 5) Resumen legible para Mati ══════════════
def linea_tendencia(perfiles):
    """'energia 4 (venia en 2)' — lo que hace que el mensaje al cliente
    demuestre que alguien miro el historial y no solo la foto de hoy."""
    partes = []
    for m in METRICAS:
        p = perfiles.get(m)
        if not p: continue
        etq = {'energia': 'energia', 'descanso': 'descanso', 'hambre': 'hambre', 'adherencia': 'adherencia'}[m]
        v = p['valor'] if m != 'hambre' else 6 - p['valor']   # des-normalizar para mostrar
        if p['baseline'] is not None and abs(p['delta'] or 0) >= 1:
            b = p['baseline'] if m != 'hambre' else 6 - p['baseline']
            partes.append(f'{etq} {v:.0f} (venia en {b:.0f})')
        else:
            partes.append(f'{etq} {v:.0f}')
    return ', '.join(partes)
