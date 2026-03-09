/**
 * preload.js — Puente IPC seguro entre el renderer y el proceso principal.
 * Usa contextBridge para exponer solo lo necesario al HTML.
 */

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('launcher', {
  // Recibe la info de actualización enviada por main.js
  onUpdateInfo: (callback) => {
    ipcRenderer.on('update-info', (_, data) => callback(data));
  },

  // Lanza el juego
  launchGame: () => ipcRenderer.send('launch-game'),

  // Abre una URL en el navegador del sistema
  openUrl: (url) => ipcRenderer.send('open-url', url),

  // Cierra el launcher
  close: () => ipcRenderer.send('close-window'),
});
