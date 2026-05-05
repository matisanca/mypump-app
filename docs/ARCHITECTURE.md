# Arquitectura de MyPump

## Diagrama de componentes

```
┌─────────────────────────────────────────────────────────────────┐
│                         CEREBRO DE PUMP TEAM                    │
│              cerebro-de-pump-team.pages.dev                     │
│              (Cloudflare Pages — repo separado)                 │
│                                                                 │
│   ┌───────────────────────────────────────┐                     │
│   │  nutriplan_data (Supabase)            │                     │
│   │  ─ UNA fila, id='main'               │                     │
│   │  ─ payload JSONB: clientes, planes,  │                     │
│   │    finanzas, agenda...               │                     │
│   └───────────┬───────────────────────────┘                     │
│               │                                                 │
│   "Publicar a MyPump" ──► mypump_publicar_cliente()            │
│               │           (RPC authenticated)                   │
└───────────────┼─────────────────────────────────────────────────┘
                │  Escribe SUBSET (rutina + dieta + nombre + perfil)
                │  NUNCA expone nutriplan_data completo
                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       SUPABASE (gydinputrtptqakdzyvc)           │
│                                                                 │
│   Tablas mypump_*                   RLS habilitado en todo      │
│   ┌──────────────────────┐                                      │
│   │ mypump_clientes      │  anon: solo via RPC con token        │
│   │ mypump_rutinas       │  authenticated: acceso completo      │
│   │ mypump_dietas        │                                      │
│   │ mypump_sesiones      │  RPC públicas (SECURITY DEFINER):    │
│   │ mypump_registros_    │  ─ mypump_get_cliente_info()         │
│   │   carga              │  ─ mypump_get_rutina_activa()        │
│   │ mypump_dietas_       │  ─ mypump_get_dieta_activa()         │
│   │   elecciones         │  ─ mypump_iniciar_sesion()           │
│   └──────────────────────┘  ─ mypump_registrar_carga()         │
│                             ─ mypump_get_historico_ejercicio()  │
│                             ─ mypump_finalizar_sesion()         │
│                             ─ mypump_elegir_opcion_comida()     │
│                             ─ mypump_get_elecciones_dia()       │
└───────────────────────────────────────┬─────────────────────────┘
                                        │ Supabase JS (CDN)
                                        │ window.mypumpDB.rpc()
                                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                         MYPUMP                                  │
│                  app.mypumpteam.com/TOKEN                       │
│                  (Cloudflare Pages — este repo)                 │
│                                                                 │
│   Cliente abre URL con su token único                           │
│   → cliente.html extrae token de window.location.pathname       │
│   → mypumpDB.getClienteInfo(token) valida acceso                │
│   → carga rutina, dieta, historial                              │
│   → escribe registros de carga y elecciones de comida           │
│                                                                 │
│   NUNCA accede a nutriplan_data                                 │
│   NUNCA hace queries directas a las tablas (todo es RPC)        │
└─────────────────────────────────────────────────────────────────┘
```

## Flujo de token

1. **Generación**: `mypump_publicar_cliente()` llama a `generate_mypump_token()` → 32 chars alfanuméricos, colisión prácticamente imposible.
2. **Distribución**: Cerebro muestra el link completo al admin. El admin lo comparte con el cliente (WhatsApp, email, etc.).
3. **Uso**: El cliente abre `app.mypumpteam.com/TOKEN`. El frontend extrae `TOKEN` del pathname y lo pasa a cada RPC call.
4. **Validación**: Cada RPC pública llama a `mypump_get_cliente_id_from_token()` (SECURITY DEFINER). Si el token no existe o está revocado → devuelve NULL → la función retorna vacío/false.
5. **Revocación**: `mypump_revocar_acceso()` setea `access_token_active = FALSE`. El cliente pierde acceso inmediatamente en la próxima request.
6. **Rotación**: `mypump_regenerar_token()` genera uno nuevo y reemplaza el anterior in-place.

## Aislamiento crítico

**MyPump NUNCA toca `nutriplan_data`.**

- `nutriplan_data` es el JSONB gigante de Cerebro con TODO (clientes, finanzas, agenda...). Exponerlo desde el frontend sería un riesgo de seguridad enorme.
- MyPump solo lee/escribe en tablas `mypump_*`, que son un subset mínimo copiado por Cerebro al publicar.
- `cliente_id` en las tablas `mypump_*` es un TEXT que referencia el ID interno de Cerebro, pero Postgres no lo valida (no hay FK cross-tabla). Esto es intencional.

## Decisiones de diseño

| Decisión | Alternativa descartada | Razón |
|---|---|---|
| Token en URL (sin auth) | Supabase Auth / magic link | Fricción cero para el cliente. El token actúa como credencial. |
| Todo via RPC | Queries directas con RLS anon | RPC centraliza la lógica de validación. Anon no necesita policies. |
| SECURITY DEFINER en RPC | SECURITY INVOKER | Anon no puede acceder a las tablas directamente. La función valida el token y actúa con privilegios del owner. |
| Rutina expandida en Cerebro | Expandir en MyPump | Mantiene la lógica de `TRAIN_PROG_MAESTRA` en un solo lugar. |
| Vanilla JS | React / Next | Coherencia con el stack de Cerebro. Cero dependencias pesadas. |
