/*
 * Repeatable checks that need no game server:
 *   1. every Lua file parses
 *   2. every NUI script parses
 *   3. server logic runs under a Lua VM with FiveM stand-ins (stubs.lua)
 *   4. codec unit tests
 *
 *   cd tests && npm install && npm test
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const luaparse = require('luaparse');
const { lua, lauxlib, lualib, to_luastring } = require('fengari');

const ROOT = path.resolve(__dirname, '..');
let failures = 0;

function walk(dir, ext, out) {
  for (const name of fs.readdirSync(dir)) {
    if (name === 'node_modules') continue;
    const full = path.join(dir, name);
    if (fs.statSync(full).isDirectory()) walk(full, ext, out);
    else if (name.endsWith(ext)) out.push(full);
  }
  return out;
}

// ---- 1. Lua syntax
console.log('Lua syntax');
for (const file of walk(ROOT, '.lua', [])) {
  try {
    luaparse.parse(fs.readFileSync(file, 'utf8'), { luaVersion: '5.3' });
  } catch (e) {
    failures++;
    console.log('  FAIL: ' + path.relative(ROOT, file) + ': ' + e.message);
  }
}

// ---- 2. JavaScript syntax
console.log('JavaScript syntax');
for (const file of walk(path.join(ROOT, 'web'), '.js', [])) {
  try {
    execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' });
  } catch (e) {
    failures++;
    console.log('  FAIL: ' + path.relative(ROOT, file) + ': ' + String(e.stderr));
  }
}

// ---- 3. server logic under fengari
console.log('Server logic');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function runLua(file) {
  const source = fs.readFileSync(file);
  const name = to_luastring('@' + path.relative(ROOT, file).replace(/\\/g, '/'));
  const status = lauxlib.luaL_loadbuffer(L, source, source.length, name) || lua.lua_pcall(L, 0, 0, 0);
  if (status !== lua.LUA_OK) {
    console.log('  ERROR: ' + lua.lua_tojsstring(L, -1));
    lua.lua_pop(L, 1);
    return false;
  }
  return true;
}

function runChunk(code) {
  const status = lauxlib.luaL_dostring(L, to_luastring(code));
  if (status !== lua.LUA_OK) throw new Error(lua.lua_tojsstring(L, -1));
}

function getGlobalString(name) {
  lua.lua_getglobal(L, to_luastring(name));
  const v = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return v;
}

// Read the script order straight from fxmanifest.lua so the tests load
// exactly what the game server would.
runChunk(`
  __manifest = {}
  setmetatable(_G, { __index = function(_, key)
    return function(value) __manifest[key] = value end
  end })
`);
let ok = runLua(path.join(ROOT, 'fxmanifest.lua'));
runChunk(`
  setmetatable(_G, nil)
  local list = {}
  for _, f in ipairs(__manifest.shared_scripts or {}) do list[#list + 1] = f end
  for _, f in ipairs(__manifest.server_scripts or {}) do list[#list + 1] = f end
  __server_files = table.concat(list, '\\n')
  __manifest_files = table.concat(__manifest.files or {}, '\\n') .. '\\n' .. table.concat(__manifest.client_scripts or {}, '\\n')
`);

// every file the manifest names must exist
for (const rel of (getGlobalString('__server_files') + '\n' + getGlobalString('__manifest_files')).split('\n')) {
  if (rel && !fs.existsSync(path.join(ROOT, rel))) {
    failures++;
    console.log('  FAIL: fxmanifest.lua names a missing file: ' + rel);
  }
}

ok = ok && runLua(path.join(__dirname, 'stubs.lua'));
// the server reads its locale file through LoadResourceFile
runChunk(`T.files['locales/en.json'] = ${JSON.stringify(fs.readFileSync(path.join(ROOT, 'locales/en.json'), 'utf8'))}`);
for (const rel of getGlobalString('__server_files').split('\n')) {
  ok = ok && runLua(path.join(ROOT, rel));
}
ok = ok && runLua(path.join(__dirname, 'server_spec.lua'));
if (!ok) {
  failures++;
} else {
  lua.lua_getglobal(L, to_luastring('__failed'));
  failures += lua.lua_tointeger(L, -1);
  lua.lua_pop(L, 1);
}

// ---- 4. codecs
console.log('\nCodecs');
failures += require('./codecs.test.js')();

console.log(failures === 0 ? '\nALL CHECKS PASSED' : `\n${failures} CHECK(S) FAILED`);
process.exit(failures === 0 ? 0 : 1);
