# Parche del bot (PROPUESTA, SIN APLICAR)

Se prueba primero en la copia del bot (`correr.sh`, HOME falso) y se aplica con el OK de Mati y reinicio del bot
(`launchctl kickstart -k gui/$(id -u)/com.pump.bot`). El import es perezoso: sin reinicio no toma el cambio.

1. Copiar `contrato_firma.py` a `~/agentkit-coach/agent/medical/contrato_firma.py` y `test_contrato_firma.py` a `~/agentkit-coach/tests/`.
2. En `agent/main.py`, en los DOS lugares donde hoy se atiende `ficha_plan` dentro del webhook POST (el tramo «no es de Meta»
   y el tramo normal), agregar inmediatamente después:

```python
        if isinstance(payload, dict) and payload.get("action") == "contrato_firma":
            return await _webhook_contrato_firma(request, payload, cliente_ip)
```

   y en la línea que hoy dice `if _accion != "ficha_plan":` (para que el aviso, que trae email y WhatsApp, no vaya al
   webhook-debug): `if _accion not in ("ficha_plan", "contrato_firma"):`

3. Junto a `_webhook_ficha_plan`, agregar:

```python
async def _webhook_contrato_firma(request: Request, payload: dict, cliente_ip: str):
    """Aviso de pump-firma: alguien firmó, revocó o pidió la baja. Solo le avisa a Mati; no le escribe al alumno."""
    if not ONBOARDING_HEADER_SECRET or not _onboarding_autorizado(request):
        logger.warning(f"Aviso de firma rechazado: secret inválido (client={cliente_ip})")
        return JSONResponse({"status": "unauthorized"}, status_code=401)
    from agent.medical import contrato_firma as _cf
    try:
        http, cuerpo, texto = _cf.procesar(payload)
    except Exception as e:  # noqa: BLE001
        logger.warning("[contrato_firma] no pude procesar el aviso: %s", type(e).__name__)
        return JSONResponse({"status": "reintentar"}, status_code=503)  # pump-firma reintenta
    if texto:
        try:
            await provider.enviar_texto(COACH_PHONE, "— para vos — " + texto)
            _cf.confirmar(payload)  # recién ahora cuenta como recibido
        except Exception as e:  # noqa: BLE001
            logger.warning("[contrato_firma] no pude avisarle a Mati: %s", e)
            return JSONResponse({"status": "reintentar"}, status_code=503)  # pump-firma reintenta con espera creciente
    return JSONResponse(cuerpo, status_code=http)
```

Volver atrás: quitar esos tres agregados y reiniciar. Sin el parche, el bot rechaza el aviso (401, «firma Meta inválida») y
pump-firma lo deja pendiente y reintenta con espera creciente (hasta cada 30 min, durante 45 días; `/salud` lo muestra): Mati no se entera hasta aplicar el parche. Por eso va ANTES del Apps Script.
