# pump-firma

Firma electrónica propia de los contratos de Pump Team: reemplaza a BoldSign para las altas nuevas. **Sin desplegar.**
Cómo se pone en marcha y cómo se vuelve atrás: [RUNBOOK.md](RUNBOOK.md).

- `firma/` — el servicio (FastAPI). `servicio.py` es la lógica; `app.py` solo traduce pedidos web; `reglas.py` no toca nada externo.
- `web/` — la página de firma (`/f/<enlace>`) y la de verificación (`/verificar`). Sin dependencias ni scripts de terceros.
- `../supabase/propuestas/nativa_contrato_firma.sql` — el esquema `contrato` (y su reverso).
- `tools/` — cargar una versión de plantilla; recalcular la cadena de eventos.
- `propuestas/` — cambio del Apps Script y parche del bot, para aplicar con OK.
- `tests/` — `python -m pytest tests -q` (necesita Node con PGlite: ver `tests/conftest.py`). `tests/demo.py` levanta todo en local con datos inventados.

Los textos de los contratos **no están en este repo** (es público): se cargan en la base desde los archivos aprobados, byte a byte, con su md5.

Qué deja como prueba cada firma: el texto exacto y su versión (hash calculado por la base), los datos precargados y lo que el firmante
escribió, cada casilla con su texto y su hora, el código de un solo uso validado en su correo, IP y dispositivo, la hora del servidor,
el PDF final con una página de constancia, su SHA-256, dos sellos de tiempo externos (RFC 3161), la copia enviada al firmante en el momento,
una copia en una casilla ajena, y un registro de eventos encadenado que solo agrega y cuya cabeza se sella todos los días.
