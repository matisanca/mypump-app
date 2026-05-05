/* =============================================================
   theme.js — Toggle light/dark mode para MyPump
   Default: light (ignorar prefers-color-scheme en primer carga).
   Persiste en localStorage. Dispara evento 'themechange' al cambiar.
   ============================================================= */

window.mypumpTheme = {
  init() {
    const stored = localStorage.getItem('mypump-theme');
    this.apply(stored || 'light');
  },

  apply(theme) {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('mypump-theme', theme);
    window.dispatchEvent(new CustomEvent('themechange', { detail: { theme } }));
  },

  toggle() {
    const current = document.documentElement.getAttribute('data-theme');
    this.apply(current === 'dark' ? 'light' : 'dark');
  },

  current() {
    return document.documentElement.getAttribute('data-theme') || 'light';
  },
};

document.addEventListener('DOMContentLoaded', () => window.mypumpTheme.init());
