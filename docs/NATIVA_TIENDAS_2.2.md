# MyPump 2.2.0: lo que cambia para las tiendas

Rama `nativa-220` (desde `nativa-202`), con `nativa-agenda-ios`, `nativa-agenda-and` y `nativa-etiqueta`. Diseño con OK
de Mati el 6-nov. Tags previstos (solo con el OK de Mati): `nios-2.2.0-129` y `nand-2.2.0-109`, livianos y sobre la
punta de `nativa-220`, como los de la 2.1.0.

Contenido: la agenda de la entrega desde «Tu guía» (franjas de lunes a viernes, se habilita al ver los obligatorios),
los videos nuevos marcados (la novedad arriba de la guía), el cuadro del video con la forma de cada clip (sin franjas
negras) y la lectura de la etiqueta nutricional que pregunta los gramos de la porción cuando no los dice.

Permisos, Info.plist, manifest, etiqueta de privacidad y Data safety: no cambian. La foto de la etiqueta ya iba a la
lectura con IA desde la 2.0.

Demo («Ver demo», la que usa App Review): una sola fuente en `apps/shared/demo` (`guia.json` con FT-2a y FT-2d nuevos y
obligatorios; `agenda.json` habilitada y con 6 franjas). Codemagic la copia a `Demo.bundle` con
`scripts/nativa/copiar-recursos-ios.sh`; Android la empaqueta desde el mismo lugar. Al integrar, cada rama traía su
propia demo y la de iOS se iba a pisar con la de Android en Codemagic (agenda sin franjas en «Ver demo»).

## Novedades (es-419)

### App Store (584 de 4000 caracteres)

```
Pump Team 2.2 te deja agendar tu entrega desde Tu guía.

• Agendá tu entrega desde Tu guía. Cuando terminás los videos que te marcó tu entrenador, elegís el día y el horario, y ese día entrás a la videollamada desde la app.
• Los videos nuevos que te suma tu entrenador aparecen marcados y arriba de todo en Tu guía.
• El reproductor se adapta a cada video, vertical u horizontal, sin franjas negras.
• Cuando le sacás una foto a la etiqueta de un alimento y no dice cuántos gramos tiene la porción, la app te la pregunta antes de guardarlo.

Tu cuenta y tu historial siguen intactos.
```

### Google Play (365 de 500 caracteres)

```
Pump Team 2.2 te deja agendar tu entrega desde Tu guía.

• Agendá tu entrega cuando terminás los videos de tu entrenador.
• Los videos nuevos aparecen marcados en Tu guía.
• El reproductor se adapta a cada video, vertical u horizontal.
• Si la foto de una etiqueta no dice los gramos de la porción, la app te los pregunta.

Tu cuenta y tu historial siguen intactos.
```

## Envíos (6-nov)
- Tags nios-2.2.0-129 y nand-2.2.0-109 sobre 6746d5c; Codemagic verde en los dos.
- Play: 109 (2.2.0) en producción al 100 %, novedades es-419, enviado a revisión ~20:35. Publicación administrada apagada: al aprobarse sale sola. AAB sha256 41eb596d20c51020…, subido en 3 trozos.
- App Store: 2.2.0 (129) enviada a revisión 6-nov 20:44, publicación automática al aprobarse, para todos de una (sin escalonado). Notas para el revisor actualizadas (WHAT IS NEW IN 2.2.0).
