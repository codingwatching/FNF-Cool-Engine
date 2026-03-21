/**
 * main.js — Proceso principal del launcher (Electron)
 *
 * Flujo:
 *  1. Lee el mod activo (mods/.active_mod.json) y parchea el icono del .exe
 *     con rcedit antes de lanzar, para que Windows Explorer muestre el icono
 *     del mod activo sin recompilar.
 *  2. Lee la versión local (engine.json) y comprueba actualizaciones.
 *  3. Si hay actualización → muestra ventana launcher con la info.
 *     Si todo está al día → lanza el juego directamente.
 */

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path  = require('path');
const fs    = require('fs');
const https = require('https');

// ── Configuración ──────────────────────────────────────────────────────────
const CONFIG = {
  gameExecutable:    '../CoolEngine.exe',
  // gameExecutable: '../CoolEngine',                                    // Linux
  // gameExecutable: '../CoolEngine.app/Contents/MacOS/CoolEngine',      // Mac

  engineVersionFile: '../engine.json',
  modsFolder:        '../mods',

  // rcedit: herramienta para parchar el icono del .exe en disco.
  // Descárgala de: https://github.com/electron/rcedit/releases
  // y ponla en tools/rcedit.exe (solo necesaria en Windows).
  rcedit: './tools/rcedit.exe',

  // Archivo donde ModManager guarda qué mod está activo
  activeModFile: '../mods/.active_mod.json',

  // Cache local: evita re-parchar si el icono no cambió entre lanzamientos
  iconCacheFile: './.icon_cache.json',

  engineGamebananaId: null,

  github: {
    enabled: false,
    owner: 'Manux123',
    repo:  'https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine',
    token: null,
  },

  gamebanana: { modsEnabled: true },

  window: { width: 900, height: 620, title: 'Cool Engine Launcher' }
};
// ──────────────────────────────────────────────────────────────────────────

let mainWindow = null;

app.whenReady().then(async () => {
  // Parchar icono del exe ANTES de lanzar (solo Windows)
  if (process.platform === 'win32') {
    try { await patchExeIcon(); }
    catch (e) { console.warn('[Launcher] patchExeIcon falló (no crítico):', e.message); }
  }

  const updateInfo = await checkForUpdates();

  if (!updateInfo.hasUpdates) {
    launchGame();
    app.quit();
    return;
  }

  createWindow(updateInfo);
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

// ── Ventana principal ──────────────────────────────────────────────────────

function createWindow(updateInfo) {
  mainWindow = new BrowserWindow({
    width:           CONFIG.window.width,
    height:          CONFIG.window.height,
    title:           CONFIG.window.title,
    resizable:       false,
    frame:           false,
    transparent:     false,
    backgroundColor: '#0a0a0f',
    webPreferences: {
      nodeIntegration:  false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'tools', 'index.html'));

  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.send('update-info', updateInfo);
  });
}

// ── IPC ────────────────────────────────────────────────────────────────────

ipcMain.on('launch-game',  () => { launchGame(); });
ipcMain.on('open-url',     (_, url) => { shell.openExternal(url); });
ipcMain.on('close-window', () => { app.quit(); });

// ── Lanzar el juego ────────────────────────────────────────────────────────

function launchGame() {
  const { spawn } = require('child_process');
  const exe = path.resolve(__dirname, CONFIG.gameExecutable);

  if (!fs.existsSync(exe)) {
    console.error('[Launcher] No se encontró el ejecutable:', exe);
    return;
  }

  const child = spawn(exe, [], {
    detached: true,
    stdio:    'ignore',
    cwd:      path.dirname(exe),
  });
  child.unref();
}

// ══════════════════════════════════════════════════════════════════════════
//  ICON PATCHING — modifica el icono del .exe en disco con rcedit
// ══════════════════════════════════════════════════════════════════════════

/**
 * Parchea el icono del ejecutable con el icono del mod activo (o el default
 * del engine si no hay mod / el mod no tiene icono).
 *
 * Solo actúa si el icono cambió desde la última vez (compara rutas + mtime
 * en .icon_cache.json para no relentizar el arranque innecesariamente).
 *
 * Requiere tools/rcedit.exe en Windows.
 */
async function patchExeIcon() {
  const rceditPath = path.resolve(__dirname, CONFIG.rcedit);
  const exePath    = path.resolve(__dirname, CONFIG.gameExecutable);

  if (!fs.existsSync(rceditPath)) {
    console.log('[Launcher] rcedit.exe no encontrado en tools/ — saltando patch de icono.');
    console.log('           Descárgalo de: https://github.com/electron/rcedit/releases');
    return;
  }
  if (!fs.existsSync(exePath)) return;

  // ── Determinar qué icono usar ────────────────────────────────────────────
  const iconPngPath = resolveModIconPath();
  if (!iconPngPath) {
    console.log('[Launcher] Sin icono de mod → usando icono embebido del exe.');
    return;
  }

  // ── Comprobar cache: ¿ya parchamos con esta versión del PNG? ─────────────
  const cachePath = path.resolve(__dirname, CONFIG.iconCacheFile);
  const cache     = readIconCache(cachePath);
  const mtime     = fs.statSync(iconPngPath).mtimeMs;

  if (cache.pngPath === iconPngPath && cache.mtime === mtime) {
    console.log('[Launcher] Icono sin cambios — patch saltado.');
    return;
  }

  // ── Convertir PNG → ICO en memoria ──────────────────────────────────────
  const icoPath = path.join(require('os').tmpdir(), '_coolengine_icon.ico');
  const pngData = fs.readFileSync(iconPngPath);
  const icoData = pngToIco(pngData);
  fs.writeFileSync(icoPath, icoData);

  // ── Llamar a rcedit ──────────────────────────────────────────────────────
  await runRcedit(rceditPath, exePath, icoPath);

  // ── Actualizar cache ─────────────────────────────────────────────────────
  writeIconCache(cachePath, { pngPath: iconPngPath, mtime });

  // Limpiar temp
  try { fs.unlinkSync(icoPath); } catch (_) {}

  console.log(`[Launcher] Icono del exe actualizado con: ${iconPngPath}`);
}

/**
 * Devuelve la ruta al PNG de icono del mod activo, o null si no hay ninguno.
 *
 * Orden de búsqueda:
 *  1. Mod activo: mods/<id>/<appIcon>.png  (campo "appIcon" en mod.json)
 *  2. Mod activo: mods/<id>/icon.png       (fallback de nombre fijo)
 *  3. null                                  (sin icono de mod)
 */
function resolveModIconPath() {
  const activeFile = path.resolve(__dirname, CONFIG.activeModFile);
  if (!fs.existsSync(activeFile)) return null;

  let activeId = null;
  try {
    const data = JSON.parse(fs.readFileSync(activeFile, 'utf8'));
    activeId = data.active || null;
  } catch (_) { return null; }

  if (!activeId) return null;

  const modRoot = path.resolve(__dirname, CONFIG.modsFolder, activeId);
  if (!fs.existsSync(modRoot)) return null;

  // Leer appIcon del mod.json si existe
  let appIconName = 'icon';
  const modJsonPath = path.join(modRoot, 'mod.json');
  if (fs.existsSync(modJsonPath)) {
    try {
      const meta = JSON.parse(fs.readFileSync(modJsonPath, 'utf8'));
      if (meta.appIcon) appIconName = String(meta.appIcon).replace(/\.png$/i, '');
    } catch (_) {}
  }

  // Buscar el PNG
  for (const name of [appIconName, 'icon']) {
    const p = path.join(modRoot, `${name}.png`);
    if (fs.existsSync(p)) return p;
  }

  return null;
}

/**
 * Envuelve los bytes de un PNG en un contenedor ICO mínimo.
 *
 * Windows Vista+ soporta PNG embebido directamente en ICO (sin conversión
 * a BMP). Solo necesitamos escribir la cabecera ICO correcta apuntando a
 * los bytes del PNG original. Esto evita depender de librerías externas.
 *
 * @param  {Buffer} pngBuf  Contenido binario del archivo .png
 * @returns {Buffer}         Archivo .ico listo para escribir a disco
 */
function pngToIco(pngBuf) {
  // Leer dimensiones del PNG desde la cabecera IHDR
  // Offset 16: width (4 bytes BE), offset 20: height (4 bytes BE)
  let imgW = pngBuf.readUInt32BE(16);
  let imgH = pngBuf.readUInt32BE(20);

  // En el formato ICO, el campo width/height es 1 byte.
  // El valor 0 significa 256. Para imágenes > 256 también usamos 0.
  const icoW = imgW  >= 256 ? 0 : imgW;
  const icoH = imgH >= 256 ? 0 : imgH;

  // ICONDIR (6 bytes) + ICONDIRENTRY (16 bytes) + datos PNG
  const header = Buffer.alloc(6 + 16);
  const pngSize   = pngBuf.length;
  const dataOffset = 6 + 16;

  // ICONDIR
  header.writeUInt16LE(0,     0); // reserved
  header.writeUInt16LE(1,     2); // type = 1 (icon)
  header.writeUInt16LE(1,     4); // count = 1 imagen

  // ICONDIRENTRY
  header.writeUInt8(icoW,    6);  // width
  header.writeUInt8(icoH,    7);  // height
  header.writeUInt8(0,       8);  // colorCount (0 = sin paleta)
  header.writeUInt8(0,       9);  // reserved
  header.writeUInt16LE(1,    10); // planes
  header.writeUInt16LE(32,   12); // bitCount
  header.writeUInt32LE(pngSize,   14); // bytesInRes
  header.writeUInt32LE(dataOffset, 18); // imageOffset

  return Buffer.concat([header, pngBuf]);
}

/**
 * Ejecuta rcedit para parchar el icono del exe.
 * @returns {Promise<void>}
 */
function runRcedit(rceditPath, exePath, icoPath) {
  return new Promise((resolve, reject) => {
    const { execFile } = require('child_process');
    execFile(
      rceditPath,
      [exePath, '--set-icon', icoPath],
      { timeout: 10000 },
      (err, stdout, stderr) => {
        if (err) {
          reject(new Error(`rcedit falló: ${err.message}\n${stderr}`));
        } else {
          resolve();
        }
      }
    );
  });
}

// ── Cache helpers ──────────────────────────────────────────────────────────

function readIconCache(cachePath) {
  try {
    if (fs.existsSync(cachePath))
      return JSON.parse(fs.readFileSync(cachePath, 'utf8'));
  } catch (_) {}
  return {};
}

function writeIconCache(cachePath, data) {
  try { fs.writeFileSync(cachePath, JSON.stringify(data)); }
  catch (_) {}
}

// ══════════════════════════════════════════════════════════════════════════
//  COMPROBACIÓN DE ACTUALIZACIONES
// ══════════════════════════════════════════════════════════════════════════

async function checkForUpdates() {
  const result = {
    hasUpdates:   false,
    engineUpdate: null,
    modUpdates:   [],
  };

  const localEngineVersion = readLocalEngineVersion();

  if (CONFIG.engineGamebananaId) {
    try {
      const gbLatest = await fetchGameBananaLatest(CONFIG.engineGamebananaId);
      if (gbLatest && isNewerVersion(gbLatest.version, localEngineVersion)) {
        result.hasUpdates   = true;
        result.engineUpdate = {
          currentVersion: localEngineVersion,
          latestVersion:  gbLatest.version,
          downloadUrl:    `https://gamebanana.com/mods/${CONFIG.engineGamebananaId}`,
          changelog:      gbLatest.changelog || '',
        };
      }
    } catch (e) {
      console.warn('[Launcher] No se pudo comprobar GameBanana:', e.message);
    }
  }

  if (CONFIG.github.enabled && !result.engineUpdate) {
    try {
      const release = await fetchGitHubLatestRelease();
      if (release && release.tag_name) {
        const latestVersion = release.tag_name.replace(/^v/, '');
        if (isNewerVersion(latestVersion, localEngineVersion)) {
          result.hasUpdates   = true;
          result.engineUpdate = {
            currentVersion: localEngineVersion,
            latestVersion,
            downloadUrl:    release.html_url,
            changelog:      release.body || '',
          };
        }
      }
    } catch (e) {
      console.warn('[Launcher] No se pudo comprobar GitHub:', e.message);
    }
  }

  const mods = readInstalledMods();
  for (const mod of mods) {
    if (!mod.gamebananaid || !CONFIG.gamebanana.modsEnabled) continue;
    try {
      const gbLatest = await fetchGameBananaLatest(mod.gamebananaid);
      if (gbLatest && isNewerVersion(gbLatest.version, mod.version || '0.0.0')) {
        result.hasUpdates = true;
        result.modUpdates.push({
          modName:        mod.name || mod.id,
          currentVersion: mod.version || '???',
          latestVersion:  gbLatest.version,
          downloadUrl:    `https://gamebanana.com/mods/${mod.gamebananaid}`,
        });
      }
    } catch (e) {
      console.warn(`[Launcher] No se pudo comprobar GB para ${mod.name}:`, e.message);
    }
  }

  return result;
}

// ── Helpers de versión ─────────────────────────────────────────────────────

function readLocalEngineVersion() {
  try {
    const f = path.resolve(__dirname, CONFIG.engineVersionFile);
    if (fs.existsSync(f))
      return JSON.parse(fs.readFileSync(f, 'utf8')).version || '0.0.0';
  } catch (_) {}
  return '0.0.0';
}

function readInstalledMods() {
  const modsDir = path.resolve(__dirname, CONFIG.modsFolder);
  if (!fs.existsSync(modsDir)) return [];
  const mods = [];
  try {
    for (const folder of fs.readdirSync(modsDir)) {
      const metaPath = path.join(modsDir, folder, 'mod.json');
      if (fs.existsSync(metaPath)) {
        try {
          const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
          mods.push({ id: folder, ...meta });
        } catch (_) {}
      }
    }
  } catch (_) {}
  return mods;
}

function isNewerVersion(a, b) {
  const parse = (v) => (v || '0.0.0').split('.').map(Number);
  const [aM, am, ap] = parse(a);
  const [bM, bm, bp] = parse(b);
  if (aM !== bM) return aM > bM;
  if (am !== bm) return am > bm;
  return ap > bp;
}

// ── API calls ──────────────────────────────────────────────────────────────

function fetchJSON(url, headers = {}) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'CoolEngineLauncher/1.0', ...headers } }, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try { resolve(JSON.parse(data)); }
        catch (e) { reject(new Error('JSON inválido: ' + data.slice(0, 200))); }
      });
    }).on('error', reject);
  });
}

function fetchGitHubLatestRelease() {
  const { owner, repo, token } = CONFIG.github;
  const url = `https://api.github.com/repos/${owner}/${repo}/releases/latest`;
  return fetchJSON(url, token ? { Authorization: `token ${token}` } : {});
}

async function fetchGameBananaLatest(modId) {
  const fields = 'name,Version().sVersion(),text';
  const url = `https://api.gamebanana.com/Core/Item/Data?itemtype=Mod&itemid=${modId}&fields=${encodeURIComponent(fields)}`;
  const data = await fetchJSON(url);
  const version   = data['Version().sVersion()'] || null;
  const changelog = data['text'] ? data['text'].replace(/<[^>]+>/g, '').slice(0, 500) : '';
  return version ? { version, changelog } : null;
}
