#!/usr/bin/env python3
"""plantillas.py — el banco de mensajes del domingo y de los recordatorios

POR QUE UN BANCO Y NO LA IA
El mensaje del domingo lo van a recibir 62 personas la misma tarde, todas las
semanas. Es el texto mas repetido del negocio y el que mas facil se nota si sale
mal. Un modelo, por bien calibrado que este, puede escribir cualquier cosa una
vez cada cien; sobre 62 x 52 = 3.224 mensajes por ano, "una vez cada cien" son
32 mensajes raros firmados como Mati.

Estas frases las valida Mati UNA vez y quedan versionadas acá. Si alguna no le
gusta, se cambia una linea y no hay que re-calibrar nada.

LAS REGLAS DEL TONO (mismas que TONO en centinela.py)
· Tuteo rioplatense: "vos", "subí", "contame". Nunca "tú" ni "usted".
· Sin signos de apertura: "como venis", no "¿Cómo venís?".
· Sin punto final.
· Como maximo UN emoji, y al final.
· El apodo es OPCIONAL, y a proposito no esta en todas. Ver `problemas_banco`.
  Si esta, va primero y en minuscula.
· Corto. Si no entra en dos renglones del telefono, sobra.

LA SELECCION ES DETERMINISTA
Por (nombre, semana ISO): distinta por persona y por semana, IGUAL si la corrida
se repite. Eso importa porque el domingo puede correr dos veces (reintento,
reinicio de la mini) y el cliente no puede ver dos redacciones distintas del
mismo pedido.
"""
import hashlib
from datetime import date

# ── Domingo: el pedido de la revision semanal ────────────────────────────
#
# Todas piden lo mismo (revision en la app) y ninguna lo hace sonar a formulario.
# Sin "por favor" y sin "te recuerdo que": no es una notificacion, es Mati.
DOMINGO = [
    # Con el nombre. Es el mensaje que llega despues de dias de silencio, asi
    # que aca nombrarlo abre bien la conversacion.
    "{n}! como venis? cuando puedas pasá por Revisión y subí el peso y las fotos, así te miro la semana",
    "{n}, arrancamos semana nueva. dejame tu revisión en la app cuando tengas un rato y la miro",
    "{n}! contame como venis. subí peso y fotos en Revisión y te hago la devolución",
    "{n}, como cerraste la semana? pasá por Revisión y subí lo tuyo así lo reviso",
    "{n}! semana nueva. pasá por Revisión, subí lo tuyo y lo miramos",
    "{n}, como anduviste? dejame la revisión en la app y te digo qué ajustamos",
    # Sin el nombre. Como el mensaje sale del hilo de esa persona, ya sabe que
    # es para ella: el nombre suma calidez, no informacion. Y el ejemplo del
    # registro real de Mati arranca "Buenas! como va el lunes?", sin nombre.
    "buenas! toca revisión. subí el peso y las 3 fotos en la app y te miro la semana",
    "como venís? dejá el peso y las 3 fotos en Revisión y arrancamos la semana con eso",
    "cerramos la semana. subí tu revisión en la app y la miro yo",
    "cómo te fue esta semana? cargá peso y fotos en Revisión cuando puedas",
    "arrancó semana. cargá tu revisión en la app y la reviso",
    "contame cómo venís. en Revisión te queda el peso y las fotos para subir",
    "cómo la pasaste esta semana? pasá por Revisión y subí peso y fotos",
    "buenas! cerró la semana. dejame el peso y las fotos en Revisión y lo miro",
]

# ── Martes / jueves: el recordatorio ─────────────────────────────────────
#
# Mas cortos todavia, y sin reproche. "Todavia no subiste" culpa; "cuando
# puedas" no. El que se siente juzgado no sube la foto: desinstala.
RECORDATORIO = [
    # Casi ninguno lleva el nombre: es el SEGUNDO o TERCER mensaje de la misma
    # semana, en un hilo que ya tiene el del domingo arriba. Volver a nombrarlo
    # ahi es lo que hace que suene a sistema y no a Mati.
    "te leo cuando dejes tu revisión en la app",
    "si tenés un minuto, subí el peso y las fotos en Revisión",
    "quedó pendiente lo de Revisión. cuando puedas",
    "me falta tu revisión para mirarte la semana",
    "cuando tengas un rato pasá por Revisión así la miro",
    "avisame cuando subas lo tuyo y lo reviso",
    "{n}! te quedó pendiente la revisión, cuando puedas subila",
    "{n}, todavía te espero en Revisión, sin apuro",
]

# Cuando ya subio el check pero le faltan las fotos. Pedir "la revision" entera
# a alguien que ya la hizo a medias es lo que hace que deje de leer.
SOLO_FOTOS = [
    # Mismo caso que el recordatorio: es una respuesta a algo que la persona
    # acaba de hacer, no una apertura.
    "ya vi el check. cuando puedas subí las fotos y queda completa",
    "me llegó el check. faltan las fotos nomás",
    "buenísimo el check. subí las 3 fotos y lo miro entero",
    "{n}! vi tu check, gracias. te faltan las 3 fotos para completarla",
]


def _indice(clave, n):
    """Estable por (clave, semana ISO). Ver la nota de arriba sobre re-corridas."""
    sem = date.today().isocalendar()[1]
    return int(hashlib.md5(f"{clave}-{sem}".encode()).hexdigest(), 16) % n


def elegir(banco, nombre, apodo_fn, sufijo=""):
    """Devuelve la frase ya armada para este cliente y esta semana.

    `apodo_fn` se inyecta en vez de importarse para no arrastrar todo
    centinela.py (y su .env, y su cliente de WhatsApp) cuando solo se quiere
    probar el banco de frases.
    """
    n = apodo_fn(nombre)
    return banco[_indice(f"{nombre}{sufijo}", len(banco))].format(n=n)


# ── El validador ─────────────────────────────────────────────────────────
def problemas(frase):
    """Devuelve la lista de reglas del tono que rompe la frase. Vacía = está bien.

    Existe para que el test pueda revisar el banco ENTERO de una: son 26 frases
    escritas a mano y alcanza con un "¿" de mas para que un mensaje firmado como
    Mati no suene a Mati.
    """
    p = []
    if "¿" in frase or "¡" in frase:
        p.append("tiene signo de apertura")
    if frase.rstrip().endswith("."):
        p.append("termina en punto")
    # El apodo es OPCIONAL. Antes era obligatorio en las 26 frases, y el
    # resultado fue que TODO mensaje del sistema arrancaba con el nombre:
    # "nahuel, aca todavia...", "facundo, todavia te espero...", "mauro, te leo
    # cuando...". Uno esta bien; veintiseis seguidos se leen como un mailing.
    # Lo que si: si esta, va primero. "che sofia, subi" no lo dice nadie.
    if "{n}" in frase and not frase.startswith("{n}"):
        p.append("el apodo va primero o no va")
    emojis = [c for c in frase if ord(c) > 0x2100]
    if len(emojis) > 1:
        p.append(f"tiene {len(emojis)} emojis")
    if len(frase) > 155:
        p.append(f"muy larga ({len(frase)})")
    for palabra in ("usted", "tú ", "debes", "por favor", "te recuerdo"):
        if palabra in frase.lower():
            p.append(f"no es el tono: '{palabra.strip()}'")
    return p


BANCOS = {"domingo": DOMINGO, "recordatorio": RECORDATORIO, "solo_fotos": SOLO_FOTOS}

# Cuanto del banco puede llevar el nombre. Es un TOPE, no una meta.
#
# `problemas()` mira una frase a la vez y por eso no puede ver el problema real,
# que solo existe mirando el banco entero: que el nombre este en todas. La
# seleccion es deterministica por (nombre, semana ISO), asi que con el banco
# mezclado cada persona alterna sola entre semanas.
#
# El domingo tolera mas porque es una apertura en frio, despues de dias sin
# hablarse. El recordatorio y el de las fotos son seguimiento dentro del mismo
# hilo y de la misma semana: ahi el nombre sobra casi siempre.
TOPE_APODO = {"domingo": 0.60, "recordatorio": 0.35, "solo_fotos": 0.35}


def problemas_banco(nombre_banco, banco):
    """Reglas que solo se ven mirando el banco completo. Vacia = esta bien."""
    p = []
    con = [f for f in banco if "{n}" in f]
    tope = TOPE_APODO.get(nombre_banco, 0.60)
    if len(con) == len(banco):
        p.append("TODAS llevan el nombre: el cliente lo va a ver en cada mensaje")
    elif len(con) / len(banco) > tope:
        p.append(f"{len(con)}/{len(banco)} llevan el nombre, el tope es {tope:.0%}")
    if not con:
        p.append("ninguna lleva el nombre: perdio toda la cercania")
    return p
