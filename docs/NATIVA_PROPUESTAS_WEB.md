# Cambios propuestos para la web (compuerta G3)

Bugs de la web que aparecieron al portarla. La nativa ya los evita, salvo que se diga otra cosa. La web **no se toca
sin el OK de Mati**: un push a `main` publica `public/`. Cada propuesta trae el cambio exacto para aplicarlo en una
sesión aparte.

## 1. El historial de Salud pisa el sueño de hoy con un valor cortado

**Qué pasa.** Después de conectar Apple Health, la última ventana del historial de 60 días lee la noche de hoy solo
hasta la medianoche. La manda igual, y pisa el sueño completo que había subido la sincronización de 7 días. En el caso
`conectar-primera-vez` de los vectores pasa de 470 a 89 minutos. Queda así hasta la próxima sincronización. Mati ve en
el Cerebro una mala noche que no existió, y el score de recuperación baja.

**Nativa:** ya no lo hace. `SincronizadorSalud.descartarNochesPartidas` tiene test (`SaludNocheParcialTests`).

**Web** (`public/js/healthkit-bridge.js`, dentro de `backfill()`, línea ~1021 de `origin/main` 684b3e2):

```diff
         const regs = await recolectar(desde, hasta);
         cosechados += regs.length;
-        const envio = await postearDetalle(regs);
+        // La noche que cruza el cierre de la ventana llega cortada a medianoche. No se manda: la completa la sube la
+        // ventana siguiente o la sincronización de 7 días. Antes pisaba el sueño de hoy con un valor parcial.
+        const corte = new Date(hasta).toLocaleDateString('en-CA');
+        const envio = await postearDetalle(regs.filter((r) => r.fecha < corte));
```

## 2. El orden del catálogo de ejercicios no está fijado

**Qué pasa.** `getCatalogoEjercicios` (`public/js/supabase-client.js` ~600) pide `mypump_ejercicios_catalogo` sin
`ORDER BY`. El motor de sustitutos desempata por el orden en que llegan las filas, y eso alcanza para cambiar 201 de las
873 listas de sustitutos:
- en 128 cambia la foto o el slug de la variante que queda;
- en 73 cambia el orden visible;
- "Abdominales" y "core" resuelven a otro ejercicio y dejan de ofrecer sustitutos.

Hoy el orden es el físico de Postgres: estable en la práctica, pero no garantizado. Puede cambiar después de un
`VACUUM FULL` o de editar filas del catálogo.

**Propuesta.** Agregar `.order('slug_en')` en la web. La nativa ya respeta el orden que recibe y pediría igual
(`&order=slug_en`). Así las dos quedan iguales y estables.

**Ojo:** el cambio altera los sustitutos que ven hoy algunos clientes, los de esas 201 listas. Conviene hacerlo junto
con la salida de la 2.0.0.

## 3. La dieta de ejemplo aparece como si fuera del cliente (D11)

**Qué pasa.** Sin dieta publicada, `cliente.html` (~8784) muestra `SAMPLE_DIET` (3.200 kcal, 5 comidas) sin ningún
aviso en Dieta. Solo hay una línea en Revisión. El cliente la lee como su plan.

**Nativa:** dice "Todavía no hay plan de comidas. Cuando Mati publique tu dieta, la vas a ver acá."

**Web** (opcional): hacer lo mismo, o al menos un cartel "Ejemplo, todavía no tenés dieta" arriba de la de ejemplo.

## 4. La política de privacidad cuenta que se puede decir que no a la IA (D7)

**Qué pasa.** La app nativa pide permiso antes de usar la IA. Si el cliente dice que no, ningún proveedor recibe sus
datos (`nativa_002`, `chat_worker`, `centinela`). `privacidad.html` ya nombra a Anthropic y a OpenAI, pero no dice que
existe esa opción.

**Web** (`public/privacidad.html`, después del párrafo "Cualquier consulta, pedido de cambio o mención de un síntoma…",
línea ~157 de `origin/main` 684b3e2):

```diff
   <p>Cualquier consulta, pedido de cambio o mención de un síntoma <strong>la
   responde Mati en persona</strong>, siempre. Y todo lo que escribís en el chat lo
   ve él.</p>
+  <h3>Podés decir que no</h3>
+  <p>En la app de iPhone y de Android te pedimos permiso antes de usar estos
+  proveedores de inteligencia artificial. Si no aceptás, <strong>ninguno recibe
+  tus datos</strong>: el chat lo responde Mati, las fotos de comida no se analizan y
+  tu revisión semanal se prepara sin IA. Lo podés cambiar cuando quieras en
+  <strong>Revisión → Mis datos → Asistente de IA</strong>.</p>
```
