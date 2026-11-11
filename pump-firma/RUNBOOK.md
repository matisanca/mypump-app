# RUNBOOK — poner en marcha la firma propia

**Nada de esto está aplicado.** Cada paso que toca producción necesita el OK de Mati. El orden importa: hasta el paso 8
todo es invisible (BoldSign sigue funcionando igual); el paso 8 es el único que cambia lo que le pasa a un alumno.

## Antes de empezar: lo que solo puede hacer o decidir Mati

| # | Qué | Para qué |
|---|-----|----------|
| A | Crear una **contraseña de aplicación** en Yandex 360 para info@mypumpteam.com (Seguridad → Contraseñas de aplicación → Correo) | El servicio manda el código, la invitación y la copia. La misma sirve para respaldar la casilla. **Hecho el 10/11:** está en `mini:~/pump-firma-datos/yandex.clave` (permisos 600); al instalar se pasa a `FIRMA_SMTP_CLAVE` del `firma.env` sin mostrarla en pantalla |
| B | Crear una **casilla de custodia** en un proveedor ajeno (por ejemplo un Gmail nuevo que no se use para nada más) | Copia de cada firma fuera de nuestro control (condición de la segunda opinión). **Hecho el 10/11:** la casilla existe (un Gmail dedicado); la dirección está en el ESTADO privado y va en `FIRMA_CUSTODIA_EMAIL` al instalar (no se escribe en este repo, que es público) |
| C | Decidir si la **firma del prestador** (contrato AR) y la **del médico** (consentimiento) se estampan en el PDF | Si sí: se asienta una autorización con fecha (paso 6). Si no: el PDF sale con la línea de firma en blanco, como el texto vigente. El del exterior ya la lleva impresa, como hoy. **Decidido el 10/11: SÍ, las dos** |
| D | Dar el OK a los **textos nuevos** de `firma/textos.py` (casillas, avisos, correos, botones) | Son los únicos textos que no existían. El contrato no se tocó |
| E | Publicar la **política de privacidad** actualizada (sección nueva en `PRIVACIDAD_PROPUESTA.md`) | La firma guarda DNI, domicilio, IP y el contrato |

## Pasos

1. **Base** — `supabase/propuestas/nativa_contrato_firma.sql`.
   Ensayo (termina en ROLLBACK, no cambia nada): `scripts/nativa/ensayar-contrato.py` (instrucciones en su encabezado). Tiene que decir `ENSAYO OK`.
   Aplicar: con `~/_aplicar.py` en la Mini, como cualquier migración. Crea el esquema `contrato`, el rol `firma_srv`, dos funciones en `public` y el bucket privado `contratos`. No toca ninguna tabla existente.
2. **Plantillas** — los tres textos vigentes, byte a byte (el md5 esperado evita cargar un archivo equivocado):
   ```
   FIRMA_DB_ADMIN_URL=... python tools/cargar_plantillas.py servicio_ar v13 <A_v13.md> 31e7d1ce…        (md5 completo en ESTADO.md)
   FIRMA_DB_ADMIN_URL=... python tools/cargar_plantillas.py servicio_ext v8 <E_v8.md> f0341711…
   FIRMA_DB_ADMIN_URL=... python tools/cargar_plantillas.py consentimiento_ar v1 <B_consentimiento_medico.md> e3ca3de1…
   ```
   Desde el 10/11 las vigentes son **v13 (Argentina) y v8 (exterior)**, con las decisiones de Mati de ese día (detalle y textos finales en la carpeta privada, `TEXTOS_FINALES_1011.md`). Lo último (v13/v8): el plazo del Programa corre desde el día en que se le envía la planificación por escrito, no desde la videollamada; en el exterior la falta de pago exige aviso escrito con fecha de corte, y quien revoca o desiste con inicio anticipado paga planificación más días. Además de lo que sigue: tope de tres meses al compromiso de continuidad, retención máxima del 30 % antes de la entrega, cláusulas 9 y 14 del exterior alineadas con Argentina (en la UE, el EEE y el Reino Unido se paga solo lo ya prestado) y teléfono del Prestador en la cláusula 10.2 del exterior (el número vive solo en la plantilla privada). Las primeras tres: (1) una sola videollamada (cláusulas 1 c y 9.3 c); (2) Argentina: pasados los 10 días de revocación lo pagado no se reembolsa y no se cobran las cuotas futuras, con las excepciones de incumplimiento del Prestador y de salud (14.2 y lo que la toca: 8.4, 10.1, 14.3, 14.4, Anexo I y avisos antes de la firma); (3) exterior: cláusula 10 con el desistimiento europeo de 14 días completo, formulario modelo en anexo y aviso antes de la firma. Las versiones anteriores quedan como historia. El cargador se niega a cargar cualquier redacción retirada. La variante «ES» de la página (aviso, casilla de inicio durante el plazo y botón con obligación de pago) ahora vale para toda la UE, el EEE y el Reino Unido. Los contratos ya firmados (BoldSign) no se tocan.
   Con `--ensayo` hace todo y termina en ROLLBACK. Después de cargar: generar un PDF de muestra de cada uno con `tests/demo.py` (`PUMP_FIRMA_FUENTES=<carpeta>`) y **compararlo a ojo con el PDF vigente de BoldSign**, hoja por hoja.
3. **Servicio en la Mini** — copiar `pump-firma/` a `~/pump-firma`, `python3 -m venv venv && venv/bin/pip install -r requirements.txt` (WeasyPrint 69.0 y OpenSSL 3 ya están en la Mini). Crear `~/pump-firma-datos/firma.env` desde `env.ejemplo` (chmod 600) y copiar `firma_prestador.png` a `~/pump-firma-datos/privado/`. Probar a mano: `FIRMA_ENV=~/pump-firma-datos/firma.env venv/bin/python -m firma.tareas verificar`.
4. **Arranque** — `com.pump.firma.plist.ejemplo` → `~/Library/LaunchAgents/com.pump.firma.plist`; `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.pump.firma.plist`. Control: `curl -s 127.0.0.1:8793/salud`. El servicio se niega a arrancar si falta algo de la configuración (dice qué).
5. **Túnel** — en la configuración de cloudflared de la Mini, sumar el hostname `firma.mypumpteam.com → http://127.0.0.1:8793` (como los de bot, claude-proxy y vision) y su registro DNS. Control: `https://firma.mypumpteam.com/salud`.
6. **Autorizaciones de firma** (Mati dijo que sí en C) — una fila por rol, con el SHA-256 del PNG y el texto de la autorización. La imagen es una sola para los dos roles (`firma_prestador.png`, la misma que ya lleva impresa el contrato del exterior; sha256 `5c5aa2ca…2fe618`, completo en ESTADO.md). Constancia: «Respuesta “si” de Mati del 10/11/2026 a la pregunta de si en el PDF van su firma como prestador y como médico»:
   `INSERT INTO contrato.autorizaciones (rol, tipo, quien, firma_sha256, constancia) VALUES ('prestador', 'servicio_ar', '<nombre>', '<sha256 del png>', '<texto y fecha del OK>');` (ídem `'medico', 'consentimiento_ar'`).
7. **Bot** — `propuestas/bot/PARCHE_main.md` (probado primero en la copia del bot; reinicio). Y avisar a AUTOMATIZAR ENTREGAS: el estado se lee con `public.contrato_estado(lead_id, email, whatsapp)` → `bloquea_agenda`.
8. **Prueba real de punta a punta, con una persona del equipo** — crear un documento a mano (`curl` a `/api/interno/crear`, con un **alias de correo** tipo `info+pruebafirma@…` y sin WhatsApp real, para que no le frene la agenda a nadie; lo firmado no se puede borrar y lo que sobre pendiente se anula con `/api/interno/anular`), firmarlo desde un teléfono, y controlar: correo de invitación, código, copia con PDF, mail en la casilla de custodia con sellos, aviso de WhatsApp a Mati, `/verificar` con el PDF. Recién entonces:
9. **Apps Script** — `propuestas/apps_script_firma_propia.gs`: pegar la función, las tres líneas, y poner la propiedad `FIRMA_PROPIA=1`. Desde acá las altas nuevas firman con pump-firma.
10. **Apps** (Fase 2) — la pantalla «Documentos» de las ramas `nativa-contrato` y `nativa-web-contrato` sale con la versión que corresponda. Antes de aplicar el paso 1 no muestra nada.

## Volver atrás

- **Rápido (segundos):** borrar la propiedad `FIRMA_PROPIA` del Apps Script. Las altas vuelven a BoldSign. Los documentos ya emitidos siguen firmables y los firmados siguen valiendo: no se apaga el servicio.
- **Total:** primero listar los documentos **pendientes** (`contrato.pendientes_de_atencion` y `/api/interno/estado`), anularlos uno por uno (`/api/interno/anular`: un pendiente frena la agenda) y reemitirlos por BoldSign. Si hay **firmados vigentes, el servicio NO se apaga**: es el canal por el que el alumno baja su copia, revoca el consentimiento o pide la baja «por el mismo medio»; se deja corriendo sin altas nuevas. Recién sin firmados: `launchctl bootout gui/$(id -u)/com.pump.firma`, quitar el hostname del túnel y el parche del bot. La base se deja como está. `nativa_contrato_firma_revertir.sql` solo si no hay ningún documento firmado (se niega si los hay): **un contrato firmado no se borra**.

## Si algo queda pendiente

`/salud` muestra cuántos documentos firmados están sin copia enviada, sin sello o sin aviso hace más de 15 minutos. La firma no depende de eso: el servicio reintenta solo cada 2 minutos (correo caído, autoridad de sellado caída, bot caído) y avisa por correo interno una vez al día si sigue.
- **Alta frenada (el contrato no salió porque al formulario le falta un dato).** Queda anotada en `contrato.altas_frenadas` y le llega un aviso a Mati por el bot que dice qué falta (plan, objetivo, precio). Si el bot no lo recibe, sale por correo a `FIRMA_AVISO_INTERNO_EMAIL`; si tampoco, se reintenta cada 5 minutos. Mientras siga sin resolverse se repite cada 24 h (`FIRMA_FRENADA_REPITE_HORAS`) durante 14 días desde la última vez que llegó incompleta (`FIRMA_FRENADA_DIAS`); además cuenta en `/salud` (`altas_frenadas`) y en el correo diario. **Se resuelve sola** cuando el formulario se reenvía completo y nace el contrato. Si la persona no va a seguir: `POST /api/interno/descartar_alta {"alta_ref": "...", "motivo": "..."}` (sirve la referencia o la huella de 16 caracteres que trae el aviso). Un envío incompleto no anula el contrato pendiente que la persona ya tenga, y el formulario reenviado otro día no duplica avisos. En la cadena de eventos y en el aviso al bot va la huella del alta, no la referencia (que trae el correo). Para que el aviso llegue por WhatsApp hace falta el parche del bot (`propuestas/bot/`); sin el parche llega solo por correo, así que `FIRMA_AVISO_INTERNO_EMAIL` tiene que estar cargado.
- Mail del alumno mal escrito: `POST /api/interno/reenviar {"documento_id": "...", "cambios": {"email": "..."}}` anula el pendiente y crea otro con enlace nuevo. Un firmado no se reemplaza.
- Datos mal (precio, plan): igual, con `cambios`.
- El alumno perdió el enlace: reenviarle el mismo correo de invitación o darle el de la app (Mis datos → Documentos).
- El alumno pidió la baja o la revocación del contrato: llega el aviso a Mati y la agenda queda frenada. Cuando se resuelve: `POST /api/interno/resolver_baja {"documento_id": "...", "resultado": "sigue" | "terminado", "nota": "..."}` (`sigue` destraba la agenda; no se puede cambiar después).
- Reenviar el formulario del closer con un dato corregido reemplaza el pendiente (enlace nuevo, el viejo deja de servir). Si ya estaba firmado no lo toca y la planilla muestra el aviso.
- Cadena de eventos: `python tools/verificar_cadena.py`. Si dice que no está íntegra, **no tocar nada** y avisar: los respaldos diarios están en `~/pump-firma-datos/respaldo/` y en la casilla de custodia.

## Qué se respalda y dónde

PDF firmados: disco de la Mini (`~/pump-firma-datos`), bucket privado `contratos`, correo del alumno, casilla de custodia. Registro de eventos y sellos: base, `~/pump-firma-datos/respaldo/<día>/` y casilla de custodia. Sumar `~/pump-firma-datos` al respaldo habitual de la Mini.

## Límites conocidos

- El servicio se conecta con la misma credencial que el bot y se baja al rol `firma_srv` en cada transacción. Endurecimiento posible, no hecho: un usuario de base propio que solo sea miembro de `firma_srv`.
- La fecha impresa en el contrato es la de Argentina también para el exterior (cerca de la medianoche puede diferir un día de la del alumno); la constancia lleva además la hora UTC, que es la que vale.
- El trato de España (botón con obligación de pago y aviso de desistimiento) se activa solo si el país del formulario dice España. El resto de la Unión Europea recibe el contrato general: a decidir con quien asesore en lo legal.
- Si la base rechaza una firma después de generado el PDF, queda un PDF suelto en disco y bucket que no figura en ningún registro (no vale como firmado: `/verificar` no lo reconoce).
- Es firma electrónica (no digital con certificado): vale como principio de prueba por escrito y se sostiene con el conjunto de evidencias. Ver `INVESTIGACION.md` y `SEGUNDA_OPINION.md`.
- Los alumnos que firmaron en BoldSign no se migran ni se les pide nada: su respaldo es el expediente privado.
- Si la Mini está apagada, el enlace no abre: el alumno ve un error y firma cuando vuelve. Nada se pierde.
- Sin plan, objetivo o precio en el formulario el contrato no se emite, ni en Argentina ni en el exterior (desde la v7 el contrato del exterior también lleva Anexo I). No se frena en silencio: ver «Alta frenada» en «Si algo queda pendiente».
