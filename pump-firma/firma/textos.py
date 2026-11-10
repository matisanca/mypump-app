"""Textos que ve o recibe el firmante. PROPUESTOS: no salen a producción sin el OK de Mati (y conviene que los vea
el abogado). El texto de los documentos NO está acá: vive en la base, en contrato.plantillas, tal cual el vigente.

Cada casilla queda registrada con su texto exacto, así que cambiar un texto de este archivo no altera lo ya firmado."""

CORREO_CONTACTO = "info@mypumpteam.com"

CASILLAS = {
    "electronico": "Acepto leer, firmar y recibir este documento en formato electrónico, y que las comunicaciones sobre él me lleguen por correo electrónico o por WhatsApp. Sé que voy a recibir una copia en PDF por correo, que puedo guardar e imprimir, y que puedo pedirla en papel escribiendo a " + CORREO_CONTACTO + ".",
    "lei_acepto": {
        "servicio_ar": "Leí el contrato completo, incluido el Anexo I, lo entiendo y lo acepto.",
        "servicio_ext": "Leí el contrato completo, lo entiendo y lo acepto.",
        "consentimiento_ar": "Leí este documento completo, incluido el Anexo, lo comprendo y decido atenderme con el Dr. Sancari en estas condiciones.",
    },
    "datos_salud": "Doy mi consentimiento expreso para que el Dr. Sancari trate mis datos de salud con el único fin de atenderme, y para que queden en mi historia clínica.",
    # El texto de «inicio_anticipado» es el párrafo de la casilla del propio contrato (cláusula 10.2): sale de la plantilla.
    "inicio_en_desistimiento": "Pido expresamente que el servicio empiece antes de que terminen los 14 días de desistimiento. Sé que, si desisto con el servicio ya empezado, pago la parte proporcional de lo prestado hasta ese momento, y que cuando el servicio esté completamente ejecutado pierdo el derecho de desistimiento.",
}

AVISO_MEDIO = ("Cómo funciona esta firma. Vas a leer el documento, confirmar tus datos, validar un código que te mandamos a "
               "tu correo y dibujar tu firma. Al firmar guardamos la fecha y la hora, la dirección IP y el dispositivo, "
               "como constancia. En el momento te llega por correo una copia en PDF del documento firmado. Si algo de "
               "tus datos está mal o tenés una duda, no firmes y escribinos antes.")

AVISO_ES = ("Derecho de desistimiento. Tenés 14 días naturales desde hoy para desistir de este contrato sin dar ningún "
            "motivo. Para hacerlo alcanza con escribir a " + CORREO_CONTACTO + " o con usar el botón «Quiero desistir» "
            "de esta misma página, que queda disponible después de firmar (cláusula 10).")

BOTON = {
    ("servicio_ar", "AR"): "Firmar contrato",
    ("servicio_ext", "OTRO"): "Firmar contrato",
    ("servicio_ext", "ES"): "Firmar contrato con obligación de pago",
    ("consentimiento_ar", "AR"): "Firmar consentimiento",
}

BAJA = {
    "AR": {"boton": "Quiero revocar el contrato o darme de baja", "titulo": "Revocación o baja"},
    "ES": {"boton": "Quiero desistir", "titulo": "Desistimiento"},
    "OTRO": {"boton": "Quiero revocar el contrato o darme de baja", "titulo": "Revocación o baja"},
}

NOMBRE_DOC = {"servicio_ar": "contrato de coaching", "servicio_ext": "contrato de coaching", "consentimiento_ar": "consentimiento de atención médica"}
ARCHIVO = {"servicio_ar": "Contrato Pump Team", "servicio_ext": "Contrato Pump Team", "consentimiento_ar": "Consentimiento medico Dr Sancari"}
PROPOSITO = {"firma": "firmar tu {doc}", "revocacion": "revocar tu {doc}", "baja": "pedir la revocación o la baja de tu {doc}"}


# Cómo se le dice a Mati lo que le falta al formulario (el contrato no se emite sin esto).
DATO_QUE_FALTA = {"cPlan": "el plan", "cObjetivo": "el objetivo", "cPrecio": "el precio", "cNombre1": "el nombre", "mNombre": "el nombre"}


def lista(cosas) -> str:
    cosas = list(cosas)
    return cosas[0] if len(cosas) == 1 else ", ".join(cosas[:-1]) + " y " + cosas[-1]


def mail_alta_frenada(nombre: str, email: str, tipo: str, faltan: list, n: int, desde_ar: str, huella: str = "") -> tuple:
    asunto = f"[pump-firma] contrato sin emitir: falta {lista(faltan)}"
    texto = (f"El {NOMBRE_DOC[tipo]} de {nombre} ({email}) NO se emitió: al formulario del closer le falta {lista(faltan)}.\n"
             f"Llegó incompleto el {desde_ar}. Aviso número {n}.\n\n"
             "Qué hacer: completar ese dato en el formulario y volver a enviarlo. Cuando llega completo, el contrato sale solo "
             "y este aviso deja de repetirse.\nMientras tanto la persona no recibe un contrato nuevo para firmar.\n"
             f"Si no va a seguir, se cierra con /api/interno/descartar_alta (alta_ref: {huella}).\n")
    return asunto, texto


def mail_invitacion(nombre: str, tipo: str, url_doc: str) -> tuple:
    doc = NOMBRE_DOC[tipo]
    asunto = f"Tu {doc} de Pump Team para leer y firmar"
    extra = ("Este documento es un acuerdo aparte, entre vos y el médico, y firmarlo es tu decisión.\n\n"
             if tipo == "consentimiento_ar" else "")
    texto = (f"Hola {nombre},\n\n"
             f"Te dejamos el enlace para leer y firmar tu {doc}:\n\n{url_doc}\n\n"
             f"{extra}"
             "El enlace es personal: no lo reenvíes. Se firma desde el teléfono o la computadora, en unos minutos: "
             "vas a leer el documento, confirmar tus datos y validar un código que te mandamos a este mismo correo.\n\n"
             "Tomate el tiempo para leerlo con detenimiento y, ante cualquier duda, consultanos antes de firmar.\n\n"
             "Pump Team\n" + CORREO_CONTACTO + "\n")
    return asunto, texto


def mail_codigo(nombre: str, tipo: str, proposito: str, codigo: str, minutos: int) -> tuple:
    que = PROPOSITO[proposito].format(doc=NOMBRE_DOC[tipo])
    asunto = f"Tu código para {que}"  # el código no va en el asunto (se vería en la notificación del teléfono)
    texto = (f"Hola {nombre},\n\n"
             f"Tu código para {que} es:\n\n    {codigo}\n\n"
             f"Vale por {minutos} minutos y sirve una sola vez. Escribilo en la página donde lo pediste.\n\n"
             "Si no lo pediste vos, no hagas nada: sin el código no se firma nada.\n\n"
             "Pump Team\n" + CORREO_CONTACTO + "\n")
    return asunto, texto


def mail_copia(nombre: str, tipo: str, firmado_ar: str, sha256: str, doc_id: str, url_doc: str, url_verificar: str, variante: str) -> tuple:
    doc = NOMBRE_DOC[tipo]
    asunto = f"Copia de tu {doc} firmado"
    extra = ""
    if tipo == "servicio_ar":
        extra = ("\nRecordá que podés revocar el contrato, sin dar motivos, dentro de los 10 días corridos desde la firma, "
                 "escribiendo a este correo o desde el enlace de arriba.\n")
    elif tipo == "servicio_ext" and variante == "ES":
        extra = ("\nRecordá que tenés 14 días naturales desde la firma para desistir del contrato sin dar motivos, "
                 "escribiendo a este correo o desde el enlace de arriba.\n")
    elif tipo == "consentimiento_ar":
        extra = "\nPodés revocar este consentimiento cuando quieras, desde el enlace de arriba o escribiendo a este correo.\n"
    texto = (f"Hola {nombre},\n\n"
             f"Recibimos tu firma. Te dejamos adjunta la copia de tu {doc}, firmado el {firmado_ar}.\n\n"
             f"Guardá este correo. También podés ver y bajar el documento cuando quieras desde acá:\n{url_doc}\n"
             f"{extra}\n"
             "Datos para verificar que el PDF no cambió:\n"
             f"  Identificador: {doc_id}\n"
             f"  Huella SHA-256 del PDF: {sha256}\n"
             f"  Verificación: {url_verificar}\n\n"
             "Pump Team\n" + CORREO_CONTACTO + "\n")
    return asunto, texto


def mail_revocacion(nombre: str, revocado_ar: str, sha256: str, doc_id: str) -> tuple:
    asunto = "Constancia de la revocación de tu consentimiento de atención médica"
    texto = (f"Hola {nombre},\n\n"
             f"Registramos la revocación de tu consentimiento de atención médica el {revocado_ar}. Desde ese momento el "
             "Dr. Sancari no emite órdenes ni recetas a tu nombre. Tus otros contratos no cambian.\n\n"
             "Te dejamos adjunto el documento con la constancia.\n\n"
             f"  Identificador: {doc_id}\n  Huella SHA-256 del PDF: {sha256}\n\n"
             "Dr. Salomón Matías Sancari\n" + CORREO_CONTACTO + "\n")
    return asunto, texto


def mail_baja(nombre: str, variante: str, pedido_ar: str, doc_id: str) -> tuple:
    que = "desistimiento" if variante == "ES" else "revocación o baja"
    asunto = f"Recibimos tu pedido de {que}"
    texto = (f"Hola {nombre},\n\n"
             f"Recibimos tu pedido de {que} del contrato el {pedido_ar}. Queda registrado con esa fecha y hora.\n"
             "Te escribimos a la brevedad para confirmarte cómo sigue.\n\n"
             f"  Identificador del contrato: {doc_id}\n\n"
             "Pump Team\n" + CORREO_CONTACTO + "\n")
    return asunto, texto


# Lo que la página le dice al firmante en cada error. La página no inventa textos: usa estos.
ERRORES = {
    "enlace": "Este enlace no es válido. Revisá que esté completo o pedinos uno nuevo.",
    "documento_vencido": "Este enlace venció porque pasaron más de 60 días. Escribinos y te mandamos uno nuevo.",
    "anulado": "Este enlace ya no está vigente porque te mandamos uno nuevo. Usá el último que te llegó.",
    "sin_codigo": "Primero pedí el código. Te llega por correo.",
    "vencido": "El código venció. Pedí uno nuevo.",
    "incorrecto": "El código no coincide. Revisalo y probá de nuevo.",
    "bloqueado": "Demasiados intentos con ese código. Pedí uno nuevo.",
    "esperar": "Ya te mandamos un código hace instantes. Esperá un momento antes de pedir otro.",
    "limite": "Se pidieron demasiados códigos. Probá más tarde o escribinos.",
    "correo": "No pudimos mandarte el correo. Probá de nuevo en un momento; si sigue igual, escribinos.",
    "casillas": "Falta marcar una casilla obligatoria.",
    "firma": "Falta tu firma. Dibujala con el dedo o el mouse en el recuadro.",
    "interno": "Algo falló de nuestro lado y no se firmó nada. Probá de nuevo en un momento.",
}
