// Équivalents web des briques Qt utilisées par les deux applis :
// QMessageBox, QFileDialog (sélecteur simulé), QSettings (localStorage).

export const esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export function settings(app) {
  const key = (k) => `${app}:${k}`;
  return {
    value(k, fallback) {
      try { return localStorage.getItem(key(k)) ?? fallback; } catch { return fallback; }
    },
    setValue(k, v) {
      try { localStorage.setItem(key(k), v); } catch { /* stockage indisponible */ }
    },
  };
}

/** Ouvre un dialogue modal dans la fenêtre `host` ; `build(dialog, close)` le remplit. */
function modal(host, build) {
  return new Promise((resolve) => {
    const scrim = document.createElement("div");
    scrim.className = "qt-scrim";
    const dialog = document.createElement("div");
    dialog.className = "qt-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    scrim.append(dialog);
    const close = (value) => {
      scrim.remove();
      document.removeEventListener("keydown", onKey);
      resolve(value);
    };
    const onKey = (e) => { if (e.key === "Escape") close(null); };
    document.addEventListener("keydown", onKey);
    build(dialog, close);
    host.append(scrim);
    (dialog.querySelector("[data-default]") || dialog.querySelector("button"))?.focus();
  });
}

const ICONS = { information: "i", question: "?", warning: "!", critical: "✕" };

/**
 * QMessageBox.information / warning / question / critical.
 * buttons : [{ label, value, default?, className? }] — renvoie la valeur du bouton cliqué.
 */
export function messageBox(host, { kind, title, text, buttons, buttonClass = "" }) {
  return modal(host, (dialog, close) => {
    dialog.setAttribute("aria-label", title);
    dialog.innerHTML = `
      <div class="qt-msg">
        <div class="qt-msg__icon qt-msg__icon--${kind}" aria-hidden="true">${ICONS[kind]}</div>
        <div>
          <h2 class="qt-dialog__title">${esc(title)}</h2>
          <p class="qt-msg__text">${esc(text)}</p>
        </div>
      </div>
      <div class="qt-actions"></div>`;
    const actions = dialog.querySelector(".qt-actions");
    for (const b of buttons) {
      const btn = document.createElement("button");
      btn.className = `${buttonClass} ${b.className || ""}`.trim();
      btn.textContent = b.label;
      if (b.default) btn.dataset.default = "";
      btn.addEventListener("click", () => close(b.value));
      actions.append(btn);
    }
  });
}

/** QDialog générique : contenu HTML libre + boutons. */
export function dialog(host, { title, body, buttons, buttonClass = "", maxWidth }) {
  return modal(host, (dlg, close) => {
    if (maxWidth) dlg.style.maxWidth = maxWidth;
    dlg.setAttribute("aria-label", title);
    if (typeof body === "string") dlg.innerHTML = body;
    else dlg.append(body);
    const actions = document.createElement("div");
    actions.className = "qt-actions";
    for (const b of buttons) {
      const btn = document.createElement("button");
      btn.className = `${buttonClass} ${b.className || ""}`.trim();
      btn.textContent = b.label;
      btn.addEventListener("click", () => close(b.value));
      actions.append(btn);
    }
    dlg.append(actions);
  });
}

/**
 * QFileDialog simulé : la preview n'a pas accès au disque, on propose des emplacements de démo.
 * choices : [{ name, path }] — renvoie le chemin choisi ou "" (annulé).
 */
export function filePicker(host, { title, choices, labels, buttonClass = "" }) {
  return modal(host, (dlg, close) => {
    let selected = 0;
    dlg.style.maxWidth = "520px";
    dlg.setAttribute("aria-label", title);
    dlg.innerHTML = `
      <h2 class="qt-dialog__title">${esc(title)}</h2>
      <p class="qt-picker__hint">${esc(labels.hint)}</p>
      <ul class="qt-picker__list" role="listbox"></ul>
      <div class="qt-actions"></div>`;
    const list = dlg.querySelector("ul");
    const render = () => {
      list.querySelectorAll(".qt-picker__item").forEach((el, i) => {
        el.classList.toggle("is-selected", i === selected);
        el.setAttribute("aria-selected", String(i === selected));
      });
    };
    choices.forEach((c, i) => {
      const li = document.createElement("li");
      li.innerHTML = `<button class="qt-picker__item" role="option">
        <span class="qt-picker__name">${esc(c.name)}</span>
        <span class="qt-picker__path">${esc(c.path)}</span></button>`;
      const btn = li.firstElementChild;
      btn.addEventListener("click", () => { selected = i; render(); });
      btn.addEventListener("dblclick", () => close(c.path));
      list.append(li);
    });
    render();
    const actions = dlg.querySelector(".qt-actions");
    const cancel = document.createElement("button");
    cancel.className = buttonClass;
    cancel.textContent = labels.cancel;
    cancel.addEventListener("click", () => close(""));
    const ok = document.createElement("button");
    ok.className = buttonClass;
    ok.textContent = labels.choose;
    ok.dataset.default = "";
    ok.addEventListener("click", () => close(choices[selected].path));
    actions.append(cancel, ok);
  }).then((v) => v || "");
}

/** Libellés des boutons standard Qt et du sélecteur simulé, par langue. */
export const STD = {
  fr: { yes: "Oui", no: "Non", ok: "OK", cancel: "Annuler", choose: "Choisir", hint: "Aperçu web : emplacements de démonstration (aucun accès au disque)." },
  en: { yes: "Yes", no: "No", ok: "OK", cancel: "Cancel", choose: "Choose", hint: "Web preview: demo locations (no disk access)." },
  it: { yes: "Sì", no: "No", ok: "OK", cancel: "Annulla", choose: "Scegli", hint: "Anteprima web: percorsi dimostrativi (nessun accesso al disco)." },
  es: { yes: "Sí", no: "No", ok: "OK", cancel: "Cancelar", choose: "Elegir", hint: "Vista previa web: ubicaciones de demostración (sin acceso al disco)." },
};
