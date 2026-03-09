/**
 * main.js — Proceso principal del launcher (Electron)
 *
 * Flujo:
 *  1. Lee la versión local del engine (engine.json) y del mod activo (mods/{mod}/mod.json)
 *  2. Consulta GitHub Releases API y/o GameBanana API para ver si hay actualizaciones
 *  3. Si hay actualización → muestra ventana de launcher con la info
 *     Si todo está al día → lanza el juego directamente
 */

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path  = require('path');
const fs    = require('fs');
const https = require('https');

// ── Configuración — edita esto según tu proyecto ───────────────────────────
const CONFIG = {
  // Ejecutable del juego (relativo a la carpeta del launcher)
  gameExecutable: '../CoolEngine.exe',         // Windows
  // gameExecutable: '../CoolEngine',           // Linux
  // gameExecutable: '../CoolEngine.app/Contents/MacOS/CoolEngine', // Mac

  // Ruta al engine.json (versión local del engine)
  engineVersionFile: '../engine.json',

  // Ruta a la carpeta de mods
  modsFolder: '../mods',

  // GameBanana — página del ENGINE en GameBanana
  // Ve a tu página en GB, el ID es el número de la URL:
  //   gamebanana.com/mods/123456  →  engineGamebananaId: 123456
  // Pon null para desactivar esta comprobación.
  engineGamebananaId: null,   // ← PON AQUÍ TU ID DE GAMEBANANA

  // GitHub — repo del engine (alternativa/complemento a GB)
  // Si usas GB para distribuir el engine, puedes poner enabled: false aquí.
  github: {
    enabled: false,
    owner: 'Manux123',       // ← tu usuario de GitHub (si lo usas)
    repo:  'https://github.com/Manux123/FNF-Cool-Engine',          // ← tu repo
    token: null,               // 'ghp_xxxxx' o null para repo público
  },

  // GameBanana — para MODS instalados
  // Cada mod puede tener "gamebananaid": 12345 en su mod.json
  // No requiere API key para lectura pública
  gamebanana: {
    modsEnabled: true,
  },

  // Ventana
  window: {
    width:  900,
    height: 620,
    title:  'Cool Engine Launcher',
  }
};
// ──────────────────────────────────────────────────────────────────────────

let mainWindow = null;

app.whenReady().then(async () => {
  const updateInfo = await checkForUpdates();

  if (!updateInfo.hasUpdates) {
    // Todo al día → lanzar el juego y salir
    launchGame();
    app.quit();
    return;
  }

  // Hay actualizaciones → mostrar launcher
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
    frame:           false,        // Sin bordes nativos (usamos los del HTML)
    transparent:     false,
    backgroundColor: '#0a0a0f',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'ui', 'index.html'));

  // Envía la info de actualización al renderer cuando esté listo
  mainWindow.webContents.on('did-finish-load', () => {
    mainWindow.webContents.send('update-info', updateInfo);
  });
}

// ── IPC: acciones del renderer ─────────────────────────────────────────────

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

// ── Comprobación de actualizaciones ───────────────────────────────────────

async function checkForUpdates() {
  const result = {
    hasUpdates:    false,
    engineUpdate:  null,   // { currentVersion, latestVersion, downloadUrl, changelog }
    modUpdates:    [],     // [{ modName, currentVersion, latestVersion, downloadUrl }]
  };

  // 1. Versión local del engine
  const localEngineVersion = readLocalEngineVersion();

  // 2. Comprobar el ENGINE en GameBanana (prioridad si está configurado)
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
      console.warn('[Launcher] No se pudo comprobar GameBanana para el engine:', e.message);
    }
  }

  // 3. Comprobar GitHub (si está habilitado y GB no encontró actualización ya)
  if (CONFIG.github.enabled && !result.engineUpdate) {
    try {
      const release = await fetchGitHubLatestRelease();
      if (release && release.tag_name) {
        const latestVersion = release.tag_name.replace(/^v/, '');
        if (isNewerVersion(latestVersion, localEngineVersion)) {
          result.hasUpdates   = true;
          result.engineUpdate = {
            currentVersion: localEngineVersion,
            latestVersion:  latestVersion,
            downloadUrl:    release.html_url,
            changelog:      release.body || '',
          };
        }
      }
    } catch (e) {
      console.warn('[Launcher] No se pudo comprobar GitHub:', e.message);
    }
  }

  // 4. Comprobar mods instalados en GB
  const mods = readInstalledMods();
  for (const mod of mods) {
    if (!mod.gamebananaid) continue;
    if (!CONFIG.gamebanana.modsEnabled) continue;

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
    const versionFile = path.resolve(__dirname, CONFIG.engineVersionFile);
    if (fs.existsSync(versionFile)) {
      const data = JSON.parse(fs.readFileSync(versionFile, 'utf8'));
      return data.version || '0.0.0';
    }
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

/**
 * Compara dos versiones semánticas (major.minor.patch).
 * @returns true si a > b
 */
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
    const options = {
      headers: {
        'User-Agent': 'CoolEngineLauncher/1.0',
        ...headers,
      },
    };
    https.get(url, options, (res) => {
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
  const headers = token ? { Authorization: `token ${token}` } : {};
  return fetchJSON(url, headers);
}

async function fetchGameBananaLatest(modId) {
  // GameBanana Core API — no requiere API key
  const fields = 'name,Version().sVersion(),text';
  const url = `https://api.gamebanana.com/Core/Item/Data?itemtype=Mod&itemid=${modId}&fields=${encodeURIComponent(fields)}`;
  const data = await fetchJSON(url);

  const version   = data['Version().sVersion()'] || null;
  // Eliminamos HTML del description para mostrarlo como changelog
  const changelog = data['text']
    ? data['text'].replace(/<[^>]+>/g, '').slice(0, 500)
    : '';

  return version ? { version, changelog } : null;
}
