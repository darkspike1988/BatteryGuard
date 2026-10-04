'use strict';
// Local interactions only: no analytics, cookies, external fonts or API requests.
let view = 'overview';
let dark = false;
const image = document.querySelector('#app-preview');
const alts = {
  overview: 'B-Guard Übersicht mit Akkuwerten, Ladeprofilen und Reiseplanung. Vorschau mit Beispieldaten.',
  history: 'B-Guard Messverlauf mit Ladekurve und Auswertung. Vorschau mit Beispieldaten.'
};
const sizes = { overview: [1960, 2120], history: [1580, 1520] };
function refreshPreview() {
  image.src = `previews/${dark ? 'dark' : 'light'}/${view}.png`;
  image.alt = alts[view];
  [image.width, image.height] = sizes[view];
}
document.querySelectorAll('[data-preview]').forEach(button => {
  button.addEventListener('click', () => {
    view = button.dataset.preview;
    document.querySelectorAll('[data-preview]').forEach(other => {
      const active = other === button;
      other.classList.toggle('selected', active);
      other.setAttribute('aria-pressed', String(active));
    });
    refreshPreview();
  });
});
document.querySelector('[data-theme]').addEventListener('click', event => {
  dark = !dark;
  event.currentTarget.setAttribute('aria-pressed', String(dark));
  event.currentTarget.textContent = dark ? 'Helle Ansicht' : 'Dunkle Ansicht';
  refreshPreview();
});
const notes = {
  desk: 'Schreibtisch: 55–60 %. Im Monitorbetrieb kann stattdessen das native macOS-Limit gelten.',
  everyday: 'Alltag: 75–80 %. Ein Profil für die regelmäßige Nutzung am Netzteil.',
  mobile: 'Unterwegs: 85–90 %. Mehr Reserve; ein niedrigeres natives Limit kann das Ziel verhindern.'
};
document.querySelectorAll('[data-profile]').forEach(button => {
  button.addEventListener('click', () => {
    document.querySelectorAll('[data-profile]').forEach(other => {
      other.classList.toggle('selected', other === button);
      other.setAttribute('aria-pressed', String(other === button));
    });
    document.querySelector('#profile-note').textContent = notes[button.dataset.profile];
  });
});
