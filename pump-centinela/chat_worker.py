#!/usr/bin/env python3
"""chat_worker.py — la IA contesta el chat. En sombra: escribe, no publica.

COMO ESTA ARMADO, Y LA SIMPLIFICACION QUE LO ORDENA TODO
La app NUNCA le habla a esta maquina. El cliente escribe -> Supabase. Este
worker pollea Supabase cada minuto, corre Codex, y deja el resultado como
BORRADOR. Eso elimina de un plumazo: el corte de ~100s del edge de Cloudflare,
el patron 202+polling, un hostname nuevo en el tunel, CORS con
capacitor://localhost, rate limit por token, y el telefono esperando a un
proceso `codex`.

No hace falta nada de eso porque la respuesta TARDA MINUTOS A PROPOSITO.

MODO SOMBRA
Genera, valida y guarda un borrador. NO publica. Mati lo manda con un click
desde la bandeja del Cerebro, o lo edita, o lo descarta. Asi se calibra el tono
con un click en vez de escribir de cero, y de paso queda medida la tasa de
clasificacion antes de que la IA hable sola.

DEGRADA A ESCALAR, NUNCA A SILENCIO
Si Codex se cae, si la sesion vencio, si el JSON viene roto, si el validador
bloquea: se guarda un borrador de clase 'derivar' y la conversacion queda
ESCALADA. El peor resultado posible es que Mati tenga que contestar a mano —
que es exactamente lo que hace hoy. Lo que no puede pasar es que un mensaje
quede sin que nadie lo mire.

USO
  python3 chat_worker.py            # dry-run: muestra que haria
  python3 chat_worker.py --correr   # genera y guarda borradores
"""
import json
import math
import os
import pathlib
import random
import re
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
import datetime as dt
from datetime import datetime

import validador_chat as VAL

BASE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(BASE))


def load_env(p):
    e = {}
    try:
        for line in open(p):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                e[k.strip()] = v.strip().strip('"').strip("'")
    except FileNotFoundError:
        pass
    return e


E = load_env(os.path.expanduser("~/agentkit-coach/.env"))
E.update(load_env(str(BASE / ".env")))
_g = lambda k, d="": os.environ.get(k) or E.get(k) or d

SB_URL = _g("SUPABASE_URL", "https://gydinputrtptqakdzyvc.supabase.co").rstrip("/")
SB_KEY = _g("SUPABASE_SERVICE_KEY") or _g("SUPABASE_KEY")

# Ruta ABSOLUTA. El codex de nvm no existe bajo launchd, que corre con un PATH
# minimo: el worker moriria con "command not found" y nadie lo veria.
CODEX = os.path.expanduser(_g("CODEX_BIN", "~/.local/bin/codex"))
MODELO = _g("CODEX_MODELO", "gpt-5.6-sol")

CORRER = "--correr" in sys.argv

# AUTOMATICO: la respuesta sale sola, con demora humana.
# En OFF (modo sombra) genera y deja borrador para que Mati lo mande.
# Se prende con --auto o con CHAT_IA_AUTO=1 en el .env, asi se puede apagar
# desde la mini sin tocar el plist ni el codigo.
AUTO = ("--auto" in sys.argv) or (_g("CHAT_IA_AUTO", "0") == "1")

# ── La demora humana ─────────────────────────────────────────────────────
#
# No es un adorno. Una respuesta que llega 900 ms despues del mensaje no la
# escribio una persona, y con eso se cae toda la premisa de la feature.
#
# Y ademas es el unico requisito de producto que SIMPLIFICA la ingenieria:
# tapa por completo la latencia de Codex. 25 s de generacion adentro de 4
# minutos es invisible.
#
# Mediana ~2,5 min con cola larga, recortada a [60 s, 15 min]. Mas ~1 s cada
# 12 caracteres, que es el tiempo de tipear la respuesta.
DEMORA_MIN_S = 60
DEMORA_MAX_S = 900
DEMORA_MEDIANA_S = 150

# Semaforo. Con ~20 mensajes/hora de pico y 20-30s por llamada, 3 sobra 20x. El
# cuello no es la CPU de esta Mac: es el rate limit de la cuenta.
CONCURRENCIA = 3
TIMEOUT_S = 90

# Cupo diario en libreta local, mismo patron que .push_entregados. Pasado el
# cupo NO se contesta: se escala. Quedarse sin cuota a mitad de la tarde y
# empezar a fallar en silencio seria peor que escalar de mas.
CUPO_DIARIO = 120
LIBRETA = BASE / ".chat_worker_cupo"


def _log(*a):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}]", *a, flush=True)


def _sb(fn, payload):
    req = urllib.request.Request(
        f"{SB_URL}/rest/v1/rpc/{fn}",
        data=json.dumps(payload).encode(),
        headers={"apikey": SB_KEY, "Authorization": f"Bearer {SB_KEY}",
                 "Content-Type": "application/json"},
        method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        cuerpo = r.read().decode()
    return json.loads(cuerpo) if cuerpo.strip() else None


def cupo_usado():
    hoy = datetime.now().strftime("%Y-%m-%d")
    try:
        d = json.loads(LIBRETA.read_text())
        return d.get(hoy, 0)
    except Exception:
        return 0


def anotar_cupo(n=1):
    hoy = datetime.now().strftime("%Y-%m-%d")
    try:
        d = json.loads(LIBRETA.read_text())
    except Exception:
        d = {}
    d = {k: v for k, v in d.items() if k >= hoy}   # se poda sola
    d[hoy] = d.get(hoy, 0) + n
    try:
        LIBRETA.write_text(json.dumps(d))
    except Exception:
        pass


# ── El prompt ────────────────────────────────────────────────────────────
#
# Se antepone el TONO verbatim y se pasa apodo, ultimos ~10 mensajes y si ya
# subio el check. CERO datos de salud: el modelo no necesita saber el HRV de
# nadie para contestar "dale, gracias".
TONO = """Escribis como Mati, entrenador argentino, por chat con un cliente suyo.
Tuteo rioplatense: "vos", "subi", "contame". Nunca "tu" ni "usted".
Sin signos de apertura: escribis "como venis", no "¿Cómo venís?".
Sin punto final. Como maximo UN emoji, y al final. Minusculas al arrancar.
Corto: una o dos oraciones. Si no entra en dos renglones de un telefono, sobra."""

REGLA_DURA = """REGLA QUE NO SE NEGOCIA:
NUNCA das indicaciones de entrenamiento, nutricion, suplementacion ni salud.
NI SIQUIERA genericas. Nada de "toma mas agua", "descansa mejor", "sumale
proteina", "baja el volumen". Nada de numeros, gramos, series, repeticiones,
calorias ni horas de sueno.
Cualquier pregunta, cambio, numero o sintoma -> clase "derivar".
Dolor de pecho, desmayo, lesion aguda o ideacion suicida -> clase "urgente".
Ante la duda, derivas. Escalar de mas cuesta un mensaje que Mati lee; escalar
de menos le manda una frase enlatada a alguien que necesitaba una persona."""

SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["clase", "respuesta", "motivo"],
    "properties": {
        "clase": {"type": "string", "enum": ["simple", "derivar", "urgente"]},
        "respuesta": {"type": "string"},
        "motivo": {"type": "string"},
    },
}


def _revision_texto(rev):
    """La revisión de la semana en prosa corta, o None si no mandó nada.

    Va al prompt para que la sugerencia pueda CRUZAR lo que el cliente escribió
    con lo que efectivamente subió. Sin esto la IA solo sabía `ya_subio` (un
    booleano) y terminaba pidiendo cosas ya entregadas: a Nicolás le propuso
    "cuando subas la revisión lo miro" cuando el check ya había llegado.

    Los 1-5 se traducen a palabras a propósito. "energia: 2" invita al modelo a
    hacer aritmética con un número que no entiende; "energía baja (2 de 5)" se
    lee como lo que es.
    """
    if not rev or not rev.get("hay_check"):
        return None

    ESCALA = {1: "muy baja", 2: "baja", 3: "normal", 4: "buena", 5: "muy buena"}
    HAMBRE = {1: "nada de hambre", 2: "poco hambre", 3: "hambre normal",
              4: "bastante hambre", 5: "mucha hambre"}
    partes = []
    for clave, etiqueta, mapa in (("energia", "energía", ESCALA),
                                  ("descanso", "descanso", ESCALA),
                                  ("adherencia", "adherencia al plan", ESCALA)):
        v = rev.get(clave)
        if v:
            partes.append(f"{etiqueta} {mapa.get(v, v)} ({v} de 5)")
    if rev.get("hambre"):
        h = rev["hambre"]
        partes.append(f"{HAMBRE.get(h, h)} ({h} de 5)")

    peso, prev = rev.get("peso_kg"), rev.get("peso_previo")
    if peso is not None:
        if prev is not None:
            d = round(float(peso) - float(prev), 1)
            comp = "igual que la semana pasada" if abs(d) < 0.2 else \
                   f"{'subió' if d > 0 else 'bajó'} {abs(d)} kg vs la semana pasada"
            partes.append(f"peso {peso} kg ({comp})")
        else:
            partes.append(f"peso {peso} kg")

    fotos = rev.get("fotos") or 0
    partes.append("las 3 fotos" if fotos >= 3
                  else "sin fotos" if fotos == 0 else f"{fotos} de 3 fotos")

    txt = "SI subio la revision de esta semana: " + ", ".join(partes) + "."
    if rev.get("nota"):
        txt += f'\nEn la nota escribio: "{rev["nota"]}"'
    return txt


def _plan_texto(plan):
    """Lo que Mati le prescribio, en una linea. None si no hay plan activo.

    No es lo mismo que la revision: la revision es lo que el cliente REPORTO,
    esto es lo que se supone que tiene que hacer. Sin esto la IA no puede
    contestar "¿agrego cardio?" ni "¿esta bien que coma X?", que es la mitad de
    lo que preguntan.
    """
    if not plan:
        return None
    p = []
    if plan.get("dias_entreno"):
        p.append(f"{plan['dias_entreno']} dias de entrenamiento por semana")
    if plan.get("semana") and plan.get("semanas_total"):
        p.append(f"va por la semana {plan['semana']} de {plan['semanas_total']}")
    elif plan.get("semana"):
        p.append(f"va por la semana {plan['semana']}")
    if plan.get("fase"):
        p.append(f"fase: {plan['fase']}")
    m = plan.get("macros") or {}
    if m.get("kcal"):
        p.append(f"objetivo {m['kcal']} kcal"
                 + (f", {m['prot']} g de proteina" if m.get("prot") else "")
                 + (f", {m['carb']} g de carbos" if m.get("carb") else "")
                 + (f", {m['fat']} g de grasa" if m.get("fat") else ""))
    if not p:
        return None
    # El cardio se nombra SOLO si no esta en la rutina, porque es la pregunta
    # que mas aparece y la IA tiene que saber que no lo tiene prescrito en vez
    # de suponer que si.
    return ("Su plan: " + ". ".join(p) + ". La rutina no tiene cardio prescrito"
            "; lo que haga de cardio es por fuera del plan.")


def armar_prompt(fila):
    apodo = (fila.get("nombre") or "").split()
    apodo = apodo[0].lower() if apodo else "che"
    hilo = fila.get("contexto") or []
    conversacion = "\n".join(
        f"{'CLIENTE' if m.get('autor') == 'cliente' else 'MATI'}: {m.get('texto','')}"
        for m in hilo[-10:])
    rev = _revision_texto(fila.get("revision"))
    # Si no hay check, se dice explicito: que el modelo sepa que NO subio es tan
    # util como saber que subio, y evita que invente que vio algo.
    subio = rev or "TODAVIA NO subio la revision de esta semana."
    plan = _plan_texto(fila.get("plan")) or "(no hay plan activo cargado)"

    return f"""{TONO}

{REGLA_DURA}

Le escribis a {apodo}.

Lo que dice su revision (dato real, no lo inventes ni lo contradigas):
{subio}
{plan}

Conversacion (lo ultimo es lo que hay que contestar):
{conversacion}

Devolves JSON con:
  clase: "simple" si alcanza con confirmar, agradecer o acusar recibo.
         "derivar" si pregunta algo, pide un cambio, da un numero o cuenta un
         sintoma. "urgente" si hay riesgo (dolor de pecho, desmayo, lesion
         aguda, ideacion suicida).
  respuesta: SOLO si clase es "simple". Una o dos oraciones, arrancando con
             "{apodo}". Dejala vacia si la clase es otra: eso no se manda solo.
  motivo: en una linea, por que elegiste esa clase.
  sugerencia: SOLO si clase es "derivar" o "urgente". Es el mensaje que Mati
             va a leer y mandar. El escribe LO QUE HAY QUE CONTESTAR, no un
             acuse de recibo.

             ESTO ES LO QUE VENIAS HACIENDO MAL Y NO SE HACE MAS:

             1. NO REPITAS lo que el cliente acaba de escribir. El sabe que pesa
                72 kg y que le cuesta entrenar 6 dias: lo escribio el. Devolverle
                sus propias palabras no le dice nada y suena a robot.
                MAL:  "recibi el check y vi los 72 kg, tambien que se te esta
                       complicando entrenar 6 dias"
                BIEN: algo que el no sabia antes de leerte.

             2. NO PREGUNTES lo que ya te contesto en ese mismo mensaje. Si dijo
                "un poco de hambre por el deficit", preguntarle si tiene hambre
                es no haberlo leido.

             3. SI TE HIZO UNA PREGUNTA, CONTESTALA. Es lo unico que espera.
                Tenes arriba su plan y su revision: usalos. Si preguntó si
                agregar cardio, la respuesta es "si", "no" o "esperemos a X" —
                con el porque en media linea. No le devuelvas otra pregunta.

             Si de verdad falta un dato para decidir, pedi ESE dato y decile
             cuando le confirmas ("dejame ver como cierra la semana y el jueves
             te digo"). Eso es una respuesta; "contame como venis" no.

             Escribilo como Mati, con el tono de arriba. Dos o tres oraciones,
             arrancando con "{apodo}". Va a salir con su nombre, asi que tiene
             que sonar a el decidiendo, no a un formulario.

             LIMITES: no inventes numeros que no esten arriba (no ves sus cargas
             ni sus comidas dia por dia, solo el resumen). Si algo depende de
             ver la semana entera, decilo en vez de improvisar.

"""


def llamar_codex(prompt):
    """Devuelve (dict, error). El prompt va por STDIN, nunca como argumento.

    Un mensaje de cliente puede tener comillas, saltos de linea y emojis; como
    argumento de shell eso es una fuente de bugs raros y de inyeccion.

    Se borra OPENAI_API_KEY del entorno del hijo A PROPOSITO: obliga a usar la
    sesion con suscripcion. Si quedara, cada respuesta se cobraria por API sin
    que nadie lo note hasta la factura.
    """
    env = dict(os.environ)
    for k in ("OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENAI_ORG_ID"):
        env.pop(k, None)

    cmd = [CODEX, "exec", "-m", MODELO, "--json", "-s", "read-only",
           "--skip-git-repo-check",
           # Sin esto, cada llamada arrastra los servidores MCP de la mini y
           # escupe errores de transporte cuando alguno esta caido. Verificado:
           # ensucia la salida y suma latencia sin aportar nada acá.
           "-c", "mcp_servers={}"]
    try:
        p = subprocess.run(cmd, input=prompt, capture_output=True, text=True,
                           timeout=TIMEOUT_S, env=env, cwd="/tmp")
    except subprocess.TimeoutExpired:
        return None, f"codex no contesto en {TIMEOUT_S}s"
    except FileNotFoundError:
        return None, f"no existe {CODEX}"

    if p.returncode != 0:
        return None, f"codex salio con {p.returncode}: {(p.stderr or '')[:160]}"

    # La salida es JSONL. Interesa el ultimo agent_message.
    texto = None
    for linea in (p.stdout or "").splitlines():
        try:
            ev = json.loads(linea)
        except Exception:
            continue
        it = ev.get("item") or {}
        if ev.get("type") == "item.completed" and it.get("type") == "agent_message":
            texto = it.get("text")
    if not texto:
        return None, "codex no devolvio ningun mensaje"

    # El modelo a veces envuelve el JSON en ```json … ```.
    m = re.search(r"\{.*\}", texto, re.DOTALL)
    if not m:
        return None, f"la respuesta no traia JSON: {texto[:120]}"
    try:
        d = json.loads(m.group(0))
    except Exception as e:
        return None, f"JSON invalido: {e}"

    if d.get("clase") not in ("simple", "derivar", "urgente"):
        return None, f"clase desconocida: {d.get('clase')!r}"
    return d, None


def demora_humana(texto):
    """Segundos hasta publicar. Log-normal recortada + tiempo de tipeo.

    Log-normal y no uniforme porque asi se distribuyen los tiempos de respuesta
    de una persona: la mayoria cerca de la mediana y una cola larga de "estaba
    haciendo otra cosa". Una uniforme entre 1 y 15 minutos se detecta a simple
    vista mirando diez mensajes seguidos.
    """
    base = random.lognormvariate(math.log(DEMORA_MEDIANA_S), 0.55)
    tipeo = len(texto or "") / 12.0
    return int(max(DEMORA_MIN_S, min(DEMORA_MAX_S, base + tipeo)))


def procesar(fila):
    """Devuelve el dict que se guarda como borrador. NUNCA lanza."""
    # `nombre` y `mensaje` viajan en el resultado porque el aviso por WhatsApp
    # los necesita: sin ellos Mati recibiria un id opaco y ningun contexto, y
    # tendria que abrir el Cerebro solo para saber quien le escribio.
    base = {"cliente_id": fila["cliente_id"], "respuesta_a": fila["mensaje_id"],
            "nombre": fila.get("nombre"), "mensaje": fila.get("mensaje", ""),
            "modelo": MODELO, "bloqueos": None}

    d, err = llamar_codex(armar_prompt(fila))
    if err:
        # Degradar a escalar, nunca a silencio.
        return {**base, "clase": "derivar", "respuesta": None,
                "sugerencia": None,
                "motivo": f"la IA no pudo: {err}"}

    clase = d["clase"]
    if clase != "simple":
        # `respuesta` se queda en None SIEMPRE para estas dos clases: es el
        # campo que el automatico manda solo. Lo que redacto el modelo va a
        # `sugerencia`, que no tiene ningun camino al cliente que no pase por
        # el boton del Cerebro.
        #
        # Por eso la sugerencia NO pasa por VAL.revisar(): el validador existe
        # para que un modelo desviado no le mande un consejo de salud a alguien
        # sin que nadie lo mire. Aca lo mira Mati antes de que salga, que es
        # una garantia mas fuerte que una lista de palabras. Si igual la
        # bloquearamos, la sugerencia quedaria vacia justo en los casos donde
        # sirve, que es todo el punto de esto.
        return {**base, "clase": clase, "respuesta": None,
                "sugerencia": (d.get("sugerencia") or "").strip()[:1200] or None,
                "motivo": (d.get("motivo") or clase)[:300]}

    texto = (d.get("respuesta") or "").strip()
    bloqueos = VAL.revisar(texto)
    if bloqueos:
        # El validador gano. NO se reintenta ni se reescribe: intentar arreglar
        # la respuesta automaticamente es volver a confiar en el modelo para
        # justo lo que fallo.
        return {**base, "clase": "derivar", "respuesta": None,
                "sugerencia": None, "bloqueos": bloqueos,
                "motivo": "el validador la freno: " + "; ".join(bloqueos[:3])}

    return {**base, "clase": "simple", "respuesta": texto,
            "sugerencia": None, "motivo": (d.get("motivo") or "")[:300]}


def main():
    if not SB_KEY:
        _log("falta SUPABASE_SERVICE_KEY")
        return 1

    usado = cupo_usado()
    if usado >= CUPO_DIARIO:
        _log(f"cupo diario agotado ({usado}/{CUPO_DIARIO}) — hoy no se contesta mas, queda para Mati")
        return 0

    try:
        pendientes = _sb("mypump_chat_para_responder", {"p_limite": 10}) or []
    except urllib.error.HTTPError as e:
        _log(f"no pude leer la cola: {e.code} {e.read().decode()[:160]}")
        return 1

    if not pendientes:
        _log("nada para contestar")
        return 0

    modo = "AUTOMATICO" if AUTO else "SOMBRA"
    _log(f"{len(pendientes)} mensajes sin responder  [{modo}]" + ("" if CORRER else "  [DRY-RUN]"))

    if not CORRER:
        for f in pendientes:
            _log(f"  {(f.get('nombre') or f['cliente_id'])[:22]:<22} | {f['mensaje'][:70]}")
        _log("(dry-run: no se llamo a Codex ni se guardo nada; usa --correr)")
        return 0

    cupo = CUPO_DIARIO - usado
    if len(pendientes) > cupo:
        _log(f"solo quedan {cupo} del cupo: se procesan {cupo} y el resto espera")
        pendientes = pendientes[:cupo]

    with ThreadPoolExecutor(max_workers=CONCURRENCIA) as ex:
        resultados = list(ex.map(procesar, pendientes))

    guardados = agendados = 0
    conteo = {"simple": 0, "derivar": 0, "urgente": 0}
    for r in resultados:
        conteo[r["clase"]] = conteo.get(r["clase"], 0) + 1

        # En automatico, una respuesta 'simple' que paso el validador se AGENDA
        # con demora. Las otras dos clases NO: 'derivar' y 'urgente' necesitan a
        # Mati por definicion, y ya quedaron escaladas al guardar el borrador.
        if AUTO and r["clase"] == "simple" and r["respuesta"]:
            espera = demora_humana(r["respuesta"])
            cuando = dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=espera)
            try:
                pid = _sb("mypump_chat_programar", {
                    "p_cliente_id": r["cliente_id"],
                    "p_contenido": r["respuesta"],
                    "p_cuando": cuando.isoformat(),
                    "p_dedupe": f"ia-{r['respuesta_a']}",
                    "p_origen": "ia",
                    # `respuesta_a` es lo que activa el indice unico parcial de
                    # la 057: hace IMPOSIBLE que este mensaje reciba dos
                    # respuestas, aunque el worker muera y reinicie.
                    "p_meta": {"respuesta_a": str(r["respuesta_a"])},
                })
                if pid:
                    agendados += 1
                    _log(f"  → {r['cliente_id']}: sale en {espera // 60}m {espera % 60}s")
                else:
                    _log(f"  · {r['cliente_id']}: ya habia una respuesta agendada")
            except Exception as e:  # noqa: BLE001
                _log(f"  no pude agendar la respuesta de {r['cliente_id']}: {e}")
            continue

        try:
            _sb("mypump_chat_borrador_guardar", {
                "p_cliente_id": r["cliente_id"],
                "p_respuesta_a": r["respuesta_a"],
                "p_clase": r["clase"],
                "p_respuesta": r["respuesta"],
                "p_motivo": r["motivo"],
                "p_bloqueos": r["bloqueos"],
                "p_modelo": r["modelo"],
                "p_sugerencia": r.get("sugerencia"),
            })
            guardados += 1
        except Exception as e:  # noqa: BLE001
            _log(f"  no pude guardar el borrador de {r['cliente_id']}: {e}")

    anotar_cupo(len(resultados))

    # Va DESPUES de guardar los borradores: si el WhatsApp falla, la escalacion
    # ya quedo en la bandeja igual. Al reves se podria avisar de algo que no se
    # guardo, y Mati abriria el Cerebro para no encontrar nada.
    avisados = avisar_escalaciones(resultados)
    if avisados:
        _log(f"  avisado a Mati por WhatsApp: {avisados}")

    _log(f"{conteo['simple']} simples, {conteo['derivar']} derivan, {conteo['urgente']} urgentes"
         f"  →  {agendados} agendadas, {guardados} a la bandeja")
    if not AUTO:
        _log("MODO SOMBRA: no se publico nada. Los borradores esperan en 💬 Chats del Cerebro.")
    return 0



# ── El aviso a Mati ──────────────────────────────────────────────────────────
#
# ESTO FALTABA, Y ERA EL AGUJERO MAS GRANDE DEL DISEÑO.
#
# La mig 057 le saco `ambito='general'` al trigger 019 —correcto: si no, cada
# mensaje de chat le mandaba un WhatsApp y la feature reproducia el problema que
# venia a matar. Pero NADA lo reemplazo para las escalaciones. Resultado: la IA
# clasificaba `derivar`, le decia al cliente "eso lo charlamos por whatsapp", y
# Mati no se enteraba nunca. Y peor: un `urgente` (dolor de pecho, desmayo,
# lesion aguda, ideacion suicida) no publica NADA por diseño — asi que el
# sistema entero quedaba en silencio absoluto justo en la emergencia.
#
# Verificado en produccion el 18-ago: dos clientes escalados, cero avisos.
AVISADOS = BASE / ".chat_avisados"
SILENCIO_H = 12          # no repetir el aviso del mismo cliente antes de esto


def whatsapp(texto):
    tok, pnid, to = _g("META_ACCESS_TOKEN"), _g("META_PHONE_NUMBER_ID"), _g("COACH_PHONE_NUMBER")
    if not (tok and pnid and to):
        _log("faltan credenciales de Meta — NO PUEDO AVISAR de las escalaciones")
        return False
    payload = json.dumps({"messaging_product": "whatsapp", "recipient_type": "individual",
                          "to": to, "type": "text", "text": {"body": texto}}).encode()
    try:
        req = urllib.request.Request(
            f"https://graph.facebook.com/v21.0/{pnid}/messages", data=payload,
            headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status == 200
    except Exception as e:  # noqa: BLE001
        _log(f"no pude mandar el WhatsApp de escalacion: {e}")
        return False


def _libreta():
    try:
        return json.loads(AVISADOS.read_text())
    except Exception:
        return {}


def _ya_avisado(cid, libreta):
    """Un cliente que escribe cinco veces seguidas no son cinco avisos.

    Sin esto, alguien que manda tres mensajes en un minuto le dispara tres
    WhatsApps y el cuello de botella se muda de la app al telefono — que es
    exactamente lo que esta feature vino a evitar. Los `urgente` NO pasan por
    aca: esos avisan siempre.
    """
    try:
        return (datetime.now() - datetime.fromisoformat(libreta[cid])).total_seconds() < SILENCIO_H * 3600
    except Exception:
        return False


def _anotar_avisados(cids, libreta):
    ahora = datetime.now().isoformat()
    libreta.update({c: ahora for c in cids})
    # Poda: lo de hace mas de una semana no sirve para nada y el archivo crece solo.
    corte = datetime.now() - dt.timedelta(days=7)
    libreta = {c: t for c, t in libreta.items()
               if (lambda x: x and x > corte)(_parse(t))}
    try:
        AVISADOS.write_text(json.dumps(libreta))
    except Exception as e:  # noqa: BLE001
        _log(f"no pude anotar la libreta de avisados: {e}")


def _parse(t):
    try:
        return datetime.fromisoformat(t)
    except Exception:
        return None


def avisar_escalaciones(resultados):
    """Un WhatsApp por corrida con lo que necesita a Mati. Urgentes aparte.

    Se agrupa a proposito: el worker corre cada 60s y si tres personas escalan
    en el mismo minuto, va UN mensaje con las tres. Los urgentes van solos,
    siempre, y sin pasar por la libreta de silencio.
    """
    urgentes = [r for r in resultados if r["clase"] == "urgente"]
    derivan = [r for r in resultados if r["clase"] == "derivar"]

    for r in urgentes:
        nombre = r.get("nombre") or r["cliente_id"]
        whatsapp(
            "🚨 *URGENTE en el chat de MyPump*\n\n"
            f"*{nombre}* escribió:\n"
            f"_{r['mensaje'][:600]}_\n\n"
            "La IA *no le contestó nada* — es a propósito. "
            "Contestale vos ahora, desde 💬 Chats del Cerebro o por WhatsApp."
        )

    if not derivan:
        return len(urgentes)

    libreta = _libreta()
    nuevos = [r for r in derivan if not _ya_avisado(r["cliente_id"], libreta)]
    if not nuevos:
        return len(urgentes)

    if len(nuevos) == 1:
        r = nuevos[0]
        nombre = r.get("nombre") or r["cliente_id"]
        cuerpo = (f"💬 *{nombre}* te escribió y necesita respuesta tuya\n\n"
                  f"_{r['mensaje'][:600]}_\n\n"
                  "Te espera en 💬 Chats del Cerebro.")
    else:
        lineas = "\n".join(
            f"• *{(r.get('nombre') or r['cliente_id'])}*: _{r['mensaje'][:110]}_"
            for r in nuevos)
        cuerpo = (f"💬 *{len(nuevos)} clientes* necesitan respuesta tuya\n\n{lineas}\n\n"
                  "Están en 💬 Chats del Cerebro.")

    if whatsapp(cuerpo):
        _anotar_avisados([r["cliente_id"] for r in nuevos], libreta)
    return len(urgentes) + len(nuevos)


if __name__ == "__main__":
    sys.exit(main())
