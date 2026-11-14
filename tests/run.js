// Rauchtest: lädt das Addon in einer nachgebauten WoW-Umgebung (siehe harness.lua).
// Aufruf: npm install --no-save fengari && node tests/run.js
const path = require('path');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const harness = path.join(__dirname, 'harness.lua');
const addon = path.join(__dirname, '..', 'BuchDesGrolls.lua');

for (const [locale, dbVersion] of [['deDE', 'v2'], ['enUS', 'v2'], ['deDE', 'v1']]) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  let failed = lauxlib.luaL_loadfile(L, to_luastring(harness)) !== 0;
  if (!failed) {
    for (const arg of [addon, locale, dbVersion]) lua.lua_pushstring(L, to_luastring(arg));
    failed = lua.lua_pcall(L, 3, 0, 0) !== 0;
  }
  if (failed) {
    console.log(`${locale} ${dbVersion}: FEHLER: ${lua.lua_tojsstring(L, -1)}`);
    process.exit(1);
  }
}
