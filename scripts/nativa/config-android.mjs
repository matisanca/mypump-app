#!/usr/bin/env node
// Genera la configuración pública del backend para Android a partir de public/js/config.js (la misma que usa la web y
// que config-ios.mjs lleva a iOS): URL de Supabase, anon key (pública: viaja en la web), servicio de visión y URL de la
// app. Así no hay dos fuentes.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const w = {};
new Function('window', fs.readFileSync(path.join(RAIZ, 'public/js/config.js'), 'utf8'))(w);
const c = w.MYPUMP_CONFIG;
const destino = path.join(RAIZ, 'apps/android/core/datos/src/main/kotlin/com/pumpteam/mypump/datos/ConfigBackendProduccion.kt');
fs.writeFileSync(destino, `// Generado por scripts/nativa/config-android.mjs desde public/js/config.js — NO editar a mano.
package com.pumpteam.mypump.datos

/** El backend de producción, el mismo de la web. */
val ConfigBackend.Companion.produccion: ConfigBackend
    get() = ConfigBackend(
        supabase = ${JSON.stringify(c.SUPABASE_URL)},
        anonKey = ${JSON.stringify(c.SUPABASE_ANON_KEY)},
        vision = ${JSON.stringify(c.VISION_URL)},
        app = ${JSON.stringify(c.APP_URL)},
    )
`);
console.log('✓', path.relative(RAIZ, destino));
