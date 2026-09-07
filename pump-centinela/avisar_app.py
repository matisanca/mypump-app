#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""avisar_app.py — un WhatsApp a Mati POR CLIENTE, con el mensaje de la app listo

Para cada asesorado activo, le manda a Mati (no al cliente) un mensaje con un
link wa.me que abre el chat de ESE cliente con el texto personalizado ya
escrito: nombre + su link de acceso. Mati toca, lee y manda. Sin copiar nada y
sin la etiqueta "Reenviado" que delata una difusion.

  python3 avisar_app.py                 # dry-run: cuenta y muestra uno
  python3 avisar_app.py --uno           # manda UN solo mensaje real (prueba)
  python3 avisar_app.py --enviar        # manda todos
  python3 avisar_app.py --enviar --desde 30   # retoma desde el N (si se corto)

Ningun cliente recibe nada de este script: todo va a COACH_PHONE_NUMBER.
"""
import os, sys, json, time, re, urllib.request, urllib.parse
import psycopg2

def cargar_env(p):
    env = {}
    for l in open(os.path.expanduser(p)):
        l = l.strip()
        if '=' in l and not l.startswith('#'):
            k, v = l.split('=', 1); env[k] = v.strip().strip('"').strip("'")
    return env

DB = cargar_env('~/agentkit-coach/.env')
# Las credenciales de Meta viven en el .env del bot, el mismo que usa el
# centinela (BOT_ENV en centinela.py). El de pump-centinela no las tiene.
E  = DB
ENVIAR = '--enviar' in sys.argv
UNO    = '--uno' in sys.argv
DESDE  = int(sys.argv[sys.argv.index('--desde') + 1]) if '--desde' in sys.argv else 1

APP = 'https://app.mypumpteam.com/?t='

def normalizar_tel(raw):
    """Devuelve el numero internacional sin '+', o None si es ambiguo.

    Los telefonos del Cerebro vienen en formatos mezclados: "+54 9 351...",
    "3512445876" (local argentino, sin codigo), "573001234567" (internacional
    sin +). wa.me exige el internacional. Reglas claras; lo que no encaja en
    ninguna NO se adivina: ese cliente va a la lista manual y Mati pega el
    texto a mano. Nunca se abre el chat de otra persona.
    """
    raw = (raw or '').strip()
    d = re.sub(r'\D', '', raw)
    if not d: return None
    if raw.startswith('+'): return d                       # ya internacional
    if d.startswith('549') and 12 <= len(d) <= 13: return d # AR movil internacional
    if len(d) == 10 and d[0] in '123' and not d.startswith('0'):
        return '549' + d                                   # AR local: area + numero
    # Otros paises, con codigo pero sin '+': largo tipico de cada uno.
    for cc, largo in (('1',11), ('34',11), ('56',11), ('52',12), ('57',12), ('58',12),
                      ('593',12), ('595',12), ('598',11), ('591',11), ('51',11),
                      ('61',11), ('31',11), ('506',11), ('507',11), ('502',11), ('503',11)):
        if d.startswith(cc) and len(d) == largo: return d
    return None                                            # ambiguo

def apodo(nombre):
    p = (nombre or '').strip().split()
    return p[0].lower() if p else 'che'

def mensaje(nombre, link):
    n = apodo(nombre)
    return f"""{n}! te escribo por algo importante para seguir con la asesoría

Desde ahora te voy a escribir por el chat de la app. Ahí te aviso cuando toca la revisión, vos la subís cada semana en la sección *Revisión* (peso, fotos y cómo venís), y con eso voy siguiendo tu progreso y ajustando lo que haga falta. Si no la tenés instalada, no ves lo que te escribo, y sin revisión no puedo hacer mi parte

*1. Bajala* (tocá el de tu teléfono)
iPhone: https://apps.apple.com/ar/app/mypump/id6793259380
Android: https://play.google.com/store/apps/details?id=com.pumpteam.mypump

Ojo con esto: si tenés el ícono de MyPump en el inicio pero nunca la bajaste de la tienda, esa es la versión web y no sirve para esto. Para estar seguro tocá el link de arriba: si dice *Abrir*, ya la tenés y pasá directo al paso 3. Si dice *Obtener* o *Instalar*, todavía no

*2. Abrila y pegá tu link* en el casillero que dice "Pegá acá el link que te pasó Mati", y tocá *Entrar a mi plan*. Es una sola vez, después abre directo. Tu link es este:
{link}
(mantené apretado el link y tocá Copiar; en el casillero mantené apretado y tocá Pegar)

*3. Aceptá las notificaciones*, así te enterás cuando te escribo

*4. Conectá Salud*, que me sirve un montón: en Mi Día tocá *Conectar Apple Health* (o *Health Connect* en Android) y aceptá todo. Así veo tus pasos, el sueño y la variabilidad cardíaca, que me dicen cómo venís recuperando. Eso solo anda con la app de la tienda, no con la web

El chat de la app es conmigo, así que cualquier duda me la escribís por ahí también. Por acá seguimos igual que siempre, eh. Lo de la revisión de cada semana te lo voy a mandar solo por la app

Avisame cuando la tengas 🤝"""

def enviar_a_mati(texto):
    tok, pnid, to = E.get('META_ACCESS_TOKEN'), E.get('META_PHONE_NUMBER_ID'), E.get('COACH_PHONE_NUMBER')
    if not (tok and pnid and to):
        print('  [meta] faltan credenciales'); return False
    payload = json.dumps({"messaging_product": "whatsapp", "recipient_type": "individual",
                          "to": to, "type": "text", "text": {"body": texto}}).encode()
    req = urllib.request.Request(f"https://graph.facebook.com/v21.0/{pnid}/messages", data=payload,
                                 headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status == 200
    except Exception as ex:
        print(f'  [meta] fail: {str(ex)[:120]}'); return False

# ── Clientes ────────────────────────────────────────────────────────────────
c = psycopg2.connect(DB['SUPABASE_DB_URL']); cur = c.cursor()
cur.execute("SELECT payload->'clients' FROM nutriplan_data LIMIT 1")
clientes = cur.fetchone()[0]
clientes = list(clientes.values()) if isinstance(clientes, dict) else clientes
cur.execute("SELECT cliente_id, nombre, access_token FROM mypump_clientes WHERE access_token_active AND access_token IS NOT NULL")
_rows = cur.fetchall()
tokens = {r[0]: r[2] for r in _rows}
c.close()

import unicodedata
def _norm(s):
    s = unicodedata.normalize('NFD', (s or '').lower())
    s = ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')
    return ' '.join(re.sub(r'[^a-z ]', ' ', s).split())
# El id del Cerebro NO siempre coincide con el cliente_id de MyPump (Facundo
# Noriega y Erick Leanos estan en la bandeja de chats y el cruce por id no los
# encontraba). Segunda llave: el nombre normalizado.
tokens_por_nombre = {_norm(r[1]): r[2] for r in _rows if r[1]}
_palabras = [(set(t for t in _norm(r[1]).split() if len(t) >= 3), r[2]) for r in _rows if r[1]]

def token_por_palabras(nombre):
    """Tercera llave: nombre y apellido CONTENIDOS en el de MyPump.

    "Facundo Noriega" en el Cerebro es "Facundo Manuel Noriega" en MyPump; la
    igualdad exacta no los une. Se exige que el match sea UNICO: si dos
    clientes comparten dos palabras, mejor no adivinar.
    """
    w = set(t for t in _norm(nombre).split() if len(t) >= 3)
    if not w: return None
    minimo = 2 if len(w) >= 2 else 1
    cands = [tok for pal, tok in _palabras if len(w & pal) >= minimo]
    return cands[0] if len(cands) == 1 else None

# El token vive en dos lados: en el blob del Cerebro (`mypump.token`, que es
# el link que Mati les mando al principio) y en mypump_clientes.access_token.
# Se toma el del blob y se cruza con la base: si difieren, se avisa.
lista, sin_token, sin_tel, difieren, vistos = [], [], [], [], set()
for x in clientes:
    if (x.get('estado') or '') != 'activo': continue
    cid = x.get('id')
    nombre = f"{x.get('nombre','')} {x.get('apellido','')}".strip()
    tel = normalizar_tel(x.get('whatsapp') or '')
    tok_blob = (x.get('mypump') or {}).get('token') if isinstance(x.get('mypump'), dict) else None
    tok_db = tokens.get(cid) or tokens_por_nombre.get(_norm(nombre)) or token_por_palabras(nombre)
    tok = tok_blob or tok_db
    if tok_blob and tok_db and tok_blob != tok_db: difieren.append(nombre)
    if not tok: sin_token.append(nombre); continue
    # Una misma persona puede tener dos fichas en el Cerebro ("Sebastian" y
    # "Sebastian Marello"): el token es la identidad real, no el nombre.
    if tok in vistos: continue
    vistos.add(tok)
    if not tel: sin_tel.append((nombre, APP + tok)); continue
    lista.append((nombre, tel, APP + tok))
manual = sorted(sin_tel, key=lambda t: t[0].lower())
lista.sort(key=lambda t: t[0].lower())

print(f"activos en el Cerebro: {sum(1 for x in clientes if x.get('estado')=='activo')}")
print(f"  listos para mandar : {len(lista)}")
if sin_token: print(f"  SIN MYPUMP (no se les manda, hay que publicarlos antes): {len(sin_token)} -> {', '.join(sin_token)}")
if manual:    print(f"  sin tel o ambiguo  : {len(manual)} -> texto plano para pegar a mano: {', '.join(n for n,_ in manual)}")
if difieren:  print(f"  token distinto blob vs base (se usa el del blob): {', '.join(difieren)}")

# ── Enviar ──────────────────────────────────────────────────────────────────
def wa_link(tel, texto):
    return f"https://wa.me/{tel}?text={urllib.parse.quote(texto, safe='')}"

ok = fallo = 0
for i, (nombre, tel, link) in enumerate(lista, 1):
    if i < DESDE: continue
    texto = mensaje(nombre, link)
    cuerpo = f"📲 *{i}/{len(lista)} · {nombre}* — tocá y mandá:\n{wa_link(tel, texto)}"
    if not (ENVIAR or UNO):
        if i == DESDE:
            print(f"\n[DRY-RUN] así le llegaría a Mati el #{i} ({len(cuerpo)} caracteres):")
            print(cuerpo[:160] + ' …')
            print(f"\n[DRY-RUN] y al tocarlo, esto queda escrito en el chat de {nombre}:\n")
            print(texto.replace(link, link[:34] + '…'))
        continue
    if enviar_a_mati(cuerpo): ok += 1
    else: fallo += 1
    time.sleep(1.2)   # sin ráfaga: que le lleguen ordenados
    if UNO: break

# Los manuales: el texto entero, para copiar y pegar en ese chat.
if (ENVIAR and not UNO):
    for j, (nombre, link) in enumerate(manual, 1):
        cuerpo = f"✍️ *manual {j}/{len(manual)} · {nombre}* — no tengo su WhatsApp cargado, copiá y pegá esto en su chat:\n\n{mensaje(nombre, link)}"
        if enviar_a_mati(cuerpo): ok += 1
        else: fallo += 1
        time.sleep(1.2)

if ENVIAR or UNO:
    print(f"\nenviados a Mati: {ok} · fallidos: {fallo}")
else:
    print(f"\n(dry-run: no se mandó nada; --uno para probar con el primero, --enviar para todos)")
