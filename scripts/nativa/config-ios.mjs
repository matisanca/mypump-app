#!/usr/bin/env node
// Genera la configuración pública del backend para iOS a partir de public/js/config.js (la misma que usa la web):
// URL de Supabase, anon key (pública: viaja en la web), servicio de visión y URL de la app. Así no hay dos fuentes.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const RAIZ = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const w = {};
new Function('window', fs.readFileSync(path.join(RAIZ, 'public/js/config.js'), 'utf8'))(w);
const c = w.MYPUMP_CONFIG;
const destino = path.join(RAIZ, 'apps/ios/MyPumpKit/Sources/MyPumpDatos/ConfigBackend+Produccion.swift');
fs.writeFileSync(destino, `// Generado por scripts/nativa/config-ios.mjs desde public/js/config.js — NO editar a mano.
import Foundation

extension ConfigBackend {
    public static let produccion = ConfigBackend(
        supabase: URL(string: ${JSON.stringify(c.SUPABASE_URL)})!,
        anonKey: ${JSON.stringify(c.SUPABASE_ANON_KEY)},
        vision: URL(string: ${JSON.stringify(c.VISION_URL)})!,
        app: URL(string: ${JSON.stringify(c.APP_URL)})!
    )
}
`);
console.log('✓', path.relative(RAIZ, destino));
