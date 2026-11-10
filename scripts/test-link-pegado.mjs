// El link pegado (FormatoToken.extraer de las apps, casos de AvisosTests.swift). Token inventado.
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const window = {};
vm.runInNewContext(readFileSync(new URL('../public/js/deeplink.js', import.meta.url), 'utf8'), { window, URL, URLSearchParams, location: { search: '', pathname: '/' } });
const x = window.MyPumpLink.extraerToken;
const t = 'abcdefghij0123456789ABCDEFGHIJ_-';
const si = [`\u200E${t}\u200F`, `\uFEFFhttps://app.mypumpteam.com/?t=${t}\u200B`, `${t}.`, `«${t}»`, `(https://app.mypumpteam.com/acceso/${t})`,
  `Tu link: https://app.mypumpteam.com/acceso/${t} entrá cuando puedas`, `https://app.mypumpteam.com/? t=${t}`, `https://app.mypumpteam.com/?t=\n${t}`,
  `  \n${t}\n  `, `?t=${t}`, `Hola! Este es tu link para entrar a MyPump: https://app.mypumpteam.com/?t=${t}`, `app.mypumpteam.com/cliente.html?t=${t}`, t];
const no = ['https://app.mypumpteam.com/', 'hola este mensaje largo no trae ningun link', 'holaestemensajelargonotraeningunlink ok', 'https://app.mypumpteam.com/?t=corto',
  'https://app.mypumpteam.com/?t=corto hola que tal todo', `https://app.mypumpteam.com/?${t}`, '', 'hola'];
for (const s of si) assert.equal(x(s), t, JSON.stringify(s));
for (const s of no) assert.equal(x(s), null, JSON.stringify(s));
console.log(`link pegado: ${si.length + no.length} casos OK`);
